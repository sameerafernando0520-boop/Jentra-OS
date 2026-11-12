const aliasDomain = '@admin.jentra.invalid';
const usernamePattern = /^[a-z0-9][a-z0-9._-]{2,47}$/;
const emailPattern = /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/;
const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const headers = {
  'content-type': 'application/json',
  'cache-control': 'no-store',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'access-control-allow-methods': 'POST, OPTIONS',
};

const json = (status, data) => new Response(JSON.stringify(data), { status, headers });
const error = (status, code, detail = {}) => json(status, { error: code, ...detail });
const ok = () => json(200, { ok: true });
const clean = (value) => typeof value === 'string' ? value.trim().toLowerCase() : '';

function validUsername(name) {
  return usernamePattern.test(name) && !name.endsWith('.') && !name.includes('..');
}

function validEmail(value) {
  return value.length <= 254 && emailPattern.test(value);
}

export function loginEmail(value) {
  const login = clean(value);
  if (validEmail(login)) return login;
  const username = login.replace(/\s+/g, '-');
  return validUsername(username) ? `${username}${aliasDomain}` : '';
}

function validPassword(value) {
  return typeof value === 'string' && Array.from(value).length >= 12 &&
    new TextEncoder().encode(value).length <= 72 && !/[\u0000-\u001f\u007f]/.test(value) &&
    /[A-Z]/.test(value) && /[a-z]/.test(value) && /[0-9]/.test(value);
}

function validCode(value) {
  return typeof value === 'string' && /^[0-9]{8}$/.test(value);
}

export function newCode() {
  const range = 100_000_000;
  const maximum = Math.floor(2 ** 32 / range) * range;
  const value = new Uint32Array(1);
  do { crypto.getRandomValues(value); } while (value[0] >= maximum);
  return String(value[0] % range).padStart(8, '0');
}

export async function hashCode(secret, purpose, subject, code) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const digest = await crypto.subtle.sign('HMAC', key, encoder.encode(JSON.stringify([purpose, subject, code])));
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, '0')).join('');
}

async function requestData(request) {
  if (!request.body || Number(request.headers.get('content-length') ?? 0) > 8192) return null;
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let size = 0;
  let input = '';
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 8192) {
        await reader.cancel();
        return null;
      }
      input += decoder.decode(value, { stream: true });
    }
    const data = JSON.parse(input + decoder.decode());
    return data && typeof data === 'object' && !Array.isArray(data) ? data : null;
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
}

async function sendResetCode(login, services) {
  if (!login || !services.mailReady || !services.codeSecret) return;
  const code = newCode();
  const address = await services.adminRpc('organization_issue_reset', {
    p_login_email: login,
    p_hash: await hashCode(services.codeSecret, 'reset', login, code),
  });
  if (address) {
    await services.sendMail(address, 'Reset your Jentra OS password',
      `Enter this code in Jentra OS to reset your password: ${code}\n\nIt expires in 10 minutes and can only be used once.`);
  }
}

async function handover(data, actor, services) {
  if (!await services.isOperator()) return error(403, 'forbidden');
  if (!services.mailReady || !services.codeSecret) return error(503, 'delivery_unavailable');
  const tenant = clean(data.tenant_id);
  const username = clean(data.username).replace(/\s+/g, '-');
  if (!uuidPattern.test(tenant) || !validUsername(username)) {
    return error(400, 'invalid_input');
  }
  if (!validPassword(data.password)) return error(400, 'weak_password');
  if (data.confirm_password != null && data.password !== data.confirm_password) {
    return error(400, 'password_mismatch');
  }

  const scope = { p_actor_id: actor.id, p_tenant_id: tenant };
  let userId;
  let recipient;
  let initialChangedAt = null;
  let generation = null;
  if (data.action === 'provision_admin') {
    const email = clean(data.signup_email);
    const name = typeof data.name === 'string' ? data.name.trim() : '';
    if (name.length > 100 || /[\u0000-\u001f\u007f]/.test(name)) return error(400, 'invalid_input');
    if (!validEmail(email) || email.endsWith(aliasDomain)) return error(400, 'invalid_email');
    recipient = await services.adminRpc('organization_check_admin_provision', { ...scope, p_signup_email: email });
    try {
      userId = await services.createUser(`${username}${aliasDomain}`, data.password, tenant, undefined, name);
    } catch (cause) {
      if (cause?.code !== 'username_unavailable') throw cause;
      const abandoned = await services.adminRpc('organization_abandoned_admin_identity', {
        ...scope, p_signup_email: recipient, p_username: username,
      });
      if (!abandoned) throw cause;
      await services.deleteUser(abandoned);
      userId = await services.createUser(`${username}${aliasDomain}`, data.password, tenant, undefined, name);
    }
    try {
      initialChangedAt = await services.adminRpc('organization_register_admin', {
        ...scope, p_user_id: userId, p_username: username, p_signup_email: recipient,
      });
    } catch (cause) {
      // If the database committed before a lost response, the membership FK
      // prevents this compensation from deleting the registered account.
      await services.deleteUser(userId).catch(() => services.log('registration_cleanup_failed'));
      throw cause;
    }
  } else {
    const target = await services.adminRpc('organization_admin_reissue_target', { ...scope, p_username: username });
    if (!target) return error(409, 'handover_unavailable');
    userId = target.user_id;
    recipient = target.email;
    generation = crypto.randomUUID();
    await services.setPassword(userId, data.password, generation);
  }

  try {
    await services.sendMail(recipient, 'Your Jentra OS administrator sign-in',
      `Username: ${username}\nTemporary password: ${data.password}\n\nOpen Jentra OS and change this password when you first sign in.`);
    const current = await services.adminRpc('organization_finish_admin_handover', {
      p_actor_id: actor.id, p_user_id: userId, p_email: recipient,
      p_initial_changed_at: initialChangedAt, p_generation: generation,
    });
    if (!current) return error(409, 'handover_superseded', { user_id: userId });
  } catch {
    services.log('administrator_handover_failed');
    return error(502, 'handover_failed', { user_id: userId });
  }
  return json(200, { ok: true, user_id: userId });
}

async function createDepartmentAccount(data, actor, profile, services) {
  if (!profile.is_administrator || profile.must_change_password) return error(403, 'forbidden');
  const tenant = clean(data.tenant_id);
  const username = clean(data.username).replace(/\s+/g, '-');
  const department = clean(data.department);
  const name = typeof data.name === 'string' ? data.name.trim() : '';
  if (!uuidPattern.test(tenant) || !validUsername(username) || !name || name.length > 100 ||
      /[\u0000-\u001f\u007f]/.test(name) ||
      !['hr', 'sales', 'procurement', 'finance', 'inventory', 'projects', 'service'].includes(department)) {
    return error(400, 'invalid_input');
  }
  if (!validPassword(data.password)) return error(400, 'weak_password');
  if (data.password !== data.confirm_password) return error(400, 'password_mismatch');
  if (!await services.staffCanProvision(tenant)) return error(403, 'forbidden');
  if (typeof data.current_password !== 'string' || !actor.email ||
      !await services.checkPassword(actor, data.current_password)) return error(403, 'incorrect_password');

  const userId = await services.createUser(`${username}${aliasDomain}`, data.password, tenant, department, name);
  try {
    await services.adminRpc('organization_register_department_staff', {
      p_actor_id: actor.id, p_tenant_id: tenant, p_user_id: userId, p_username: username,
      p_display_name: name, p_department: department,
    });
  } catch (cause) {
    // A committed membership restricts deletion if the response was lost.
    await services.deleteUser(userId).catch(() => services.log('staff_registration_cleanup_failed'));
    throw cause;
  }
  return json(200, { ok: true, username });
}

export async function handleOrganizationIdentity(request, services) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return error(405, 'method_not_allowed');
  const data = await requestData(request);
  if (!data) return error(400, 'invalid_input');
  try {
    if (data.action === 'request_reset') {
      services.background(sendResetCode(loginEmail(data.login), services).catch(() => services.log('reset_delivery_failed')));
      return ok();
    }
    if (data.action === 'reset_password') {
      if (!validPassword(data.new_password)) return error(400, 'weak_password');
      const login = loginEmail(data.login);
      if (!login || !validCode(data.code)) return error(400, 'invalid_code');
      if (!services.codeSecret) return error(503, 'identity_unavailable');
      const userId = await services.adminRpc('organization_consume_reset', {
        p_login_email: login,
        p_hash: await hashCode(services.codeSecret, 'reset', login, data.code),
      });
      if (!userId) return error(400, 'invalid_code');
      await services.setPassword(userId, data.new_password);
      return ok();
    }

    const actor = await services.authenticate();
    if (!actor) return error(401, 'authentication_required');
    const profile = await services.profile();
    if (data.action === 'provision_admin' || data.action === 'reissue_admin') return await handover(data, actor, services);
    if (data.action === 'create_department_account') return await createDepartmentAccount(data, actor, profile, services);
    if (data.action === 'profile') return json(200, profile);
    if (data.action === 'verify_recovery_email') {
      if (!validCode(data.code)) return error(400, 'invalid_code');
      if (!services.codeSecret) return error(503, 'identity_unavailable');
      const verified = await services.adminRpc('organization_verify_recovery_email', {
        p_user_id: actor.id,
        p_hash: await hashCode(services.codeSecret, 'verify', actor.id, data.code),
      });
      return verified ? ok() : error(400, 'invalid_code');
    }
    if (data.action !== 'change_password' && data.action !== 'request_recovery_email') return error(400, 'invalid_action');
    if (data.action === 'change_password' && !profile.is_administrator &&
        !(profile.username && profile.must_change_password && !profile.organization_locked)) {
      return error(403, 'forbidden');
    }
    if (typeof data.current_password !== 'string' || !data.current_password || !actor.email ||
        !await services.checkPassword(actor, data.current_password)) return error(403, 'incorrect_password');
    if (data.action === 'change_password') {
      if (!validPassword(data.new_password)) return error(400, 'weak_password');
      if (data.new_password === data.current_password) return error(400, 'password_unchanged');
      await services.setPassword(actor.id, data.new_password);
      return ok();
    }

    if (!services.codeSecret || !services.mailReady) return error(503, 'delivery_unavailable');
    const email = clean(data.email);
    if (!validEmail(email) || email.endsWith(aliasDomain)) return error(400, 'invalid_email');
    const code = newCode();
    const issued = await services.adminRpc('organization_issue_recovery_verification', {
      p_user_id: actor.id,
      p_email: email,
      p_hash: await hashCode(services.codeSecret, 'verify', actor.id, code),
    });
    if (!issued) return error(429, 'try_again_later');
    await services.sendMail(email, 'Verify your Jentra OS recovery email',
      `Enter this code in your Jentra OS account profile: ${code}\n\nIt expires in 10 minutes and can only be used once.`);
    return ok();
  } catch (cause) {
    const exposedErrors = {
      forbidden: 403, invalid_input: 400, username_unavailable: 409,
      weak_password: 400, delivery_unavailable: 503,
    };
    const status = Object.hasOwn(exposedErrors, cause?.code) ? exposedErrors[cause.code] : null;
    if (status) return error(status, cause.code);
    services.log('identity_operation_failed');
    return error(503, 'identity_unavailable');
  }
}
