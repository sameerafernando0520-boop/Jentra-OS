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

function operatorLogin(value) {
  const login = clean(value);
  return validEmail(login) && !login.endsWith(aliasDomain) ? login : '';
}

async function sendResetCode(login, services, operator) {
  if (!login || !services.mailReady || !services.codeSecret) return;
  const code = newCode();
  const address = await services.adminRpc(operator ? 'platform_operator_issue_reset' : 'organization_issue_reset', {
    p_login_email: login,
    p_hash: await hashCode(services.codeSecret, operator ? 'operator-reset' : 'reset', login, code),
  });
  if (address) {
    const product = operator ? 'Jentra Admin' : 'Jentra OS';
    await services.sendMail(address, `Reset your ${product} password`,
      `Enter this code in ${product} to reset your password: ${code}\n\nIt expires in 10 minutes and can only be used once.`);
  }
}

const operatorAccountActions = new Set([
  'operator_profile', 'set_operator_password', 'change_operator_password',
  'request_operator_recovery_email', 'verify_operator_recovery_email',
]);

async function operatorAccount(data, actor, services) {
  const profile = await services.operatorProfile();
  if (data.action === 'operator_profile') return json(200, profile);
  const scope = { p_actor_id: actor.id, p_password_changed_at: profile.password_changed_at };

  if (data.action === 'verify_operator_recovery_email') {
    if (!validCode(data.code)) return error(400, 'invalid_code');
    if (!services.codeSecret) return error(503, 'identity_unavailable');
    const verified = await services.adminRpc('platform_operator_verify_recovery_email', {
      ...scope, p_hash: await hashCode(services.codeSecret, 'operator-verify', actor.id, data.code),
    });
    return verified ? ok() : error(400, 'invalid_code');
  }

  const settingPassword = data.action === 'set_operator_password';
  if (settingPassword && profile.has_password) return error(409, 'password_already_set');
  if (!settingPassword) {
    if (!profile.has_password) return error(409, 'password_not_set');
    if (typeof data.current_password !== 'string' || !data.current_password || !actor.email ||
        !await services.checkPassword(actor, data.current_password)) return error(403, 'incorrect_password');
  }
  if (settingPassword || data.action === 'change_operator_password') {
    if (!validPassword(data.new_password)) return error(400, 'weak_password');
    if (!settingPassword && data.new_password === data.current_password) return error(400, 'password_unchanged');
    const token = await services.adminRpc('platform_operator_prepare_password', {
      ...scope, p_set_password: settingPassword,
    });
    if (!token) return error(503, 'identity_unavailable');
    await services.setOperatorPassword(actor.id, data.new_password, token);
    return ok();
  }

  if (!services.codeSecret || !services.mailReady) return error(503, 'delivery_unavailable');
  const email = operatorLogin(data.email);
  if (!email || email === profile.email) return error(400, 'invalid_recovery_email');
  const code = newCode();
  const issued = await services.adminRpc('platform_operator_issue_recovery_verification', {
    ...scope, p_email: email, p_hash: await hashCode(services.codeSecret, 'operator-verify', actor.id, code),
  });
  if (!issued) return error(429, 'try_again_later');
  await services.sendMail(email, 'Verify your Jentra Admin recovery email',
    `Enter this code in Jentra Admin to verify your recovery email: ${code}\n\nIt expires in 10 minutes and can only be used once.`);
  return ok();
}

async function verifyPurchaseEmail(data, actor, services) {
  const email = clean(actor.email);
  if (actor.app_metadata?.managed_org_admin === true || !validEmail(email) || email.endsWith(aliasDomain)) {
    return error(403, 'forbidden');
  }
  if (!services.codeSecret || !services.mailReady) return error(503, 'delivery_unavailable');
  const subject = `${actor.id}:${email}`;
  if (data.action === 'verify_purchase_email_code') {
    if (!validCode(data.code)) return error(400, 'invalid_code');
    const verified = await services.adminRpc('subscription_consume_buyer_verification', {
      p_buyer_id: actor.id,
      p_email: email,
      p_hash: await hashCode(services.codeSecret, 'purchase-email', subject, data.code),
    });
    return verified ? ok() : error(400, 'invalid_code');
  }
  const code = newCode();
  const issued = await services.adminRpc('subscription_issue_buyer_verification', {
    p_buyer_id: actor.id,
    p_email: email,
    p_hash: await hashCode(services.codeSecret, 'purchase-email', subject, code),
  });
  if (!issued) return error(429, 'try_again_later');
  await services.sendMail(email, 'Verify your Jentra OS purchase email',
    `Enter this code in Jentra OS to verify your purchase email: ${code}\n\nIt expires in 10 minutes and can only be used once.`);
  return ok();
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
      !['sales', 'procurement', 'finance', 'inventory', 'projects', 'service'].includes(department)) {
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

function verificationLink(value, key, id) {
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password) return '';
    if (url.hash.startsWith('#/')) {
      const route = new URL(url.hash.slice(1), url.origin);
      route.searchParams.set(key, id);
      url.hash = route.pathname + route.search;
    } else {
      url.searchParams.set(key, id);
    }
    return url.toString();
  } catch {
    return '';
  }
}

async function ownerVerification(data, services) {
  const id = clean(data.verification_id);
  if (!uuidPattern.test(id)) return error(400, 'invalid_input');
  if (!services.codeSecret) return error(503, 'identity_unavailable');
  if (data.action === 'system_owner_verify_code') {
    if (!validCode(data.code)) return error(400, 'invalid_code');
    const verified = await services.adminRpc('system_consume_owner_verification', {
      p_verification_id: id,
      p_hash: await hashCode(services.codeSecret, 'system-owner', id, data.code),
    });
    return verified?.ok === true ? ok() : error(400, 'invalid_code');
  }
  const actor = await services.authenticate();
  if (!actor || !await services.isOperator()) return error(403, 'forbidden');
  const link = verificationLink(services.ownerVerifyUrl, 'verification_id', id);
  if (!services.mailReady || !link) return error(503, 'delivery_unavailable');
  const code = newCode();
  const recipient = await services.adminRpc('system_issue_owner_verification', {
    p_verification_id: id, p_actor_id: actor.id,
    p_hash: await hashCode(services.codeSecret, 'system-owner', id, code),
  });
  if (!recipient) return error(429, 'try_again_later');
  await services.sendMail(recipient, 'Verify your Jentra system owner email',
    'Open ' + link + '\nVerification ID: ' + id + '\nCode: ' + code +
    '\n\nThe code expires in 10 minutes.');
  return ok();
}

async function staffVerificationCode(staff, services) {
  const id = staff.identity_id;
  const link = verificationLink(services.staffVerifyUrl, 'id', id);
  if (!services.codeSecret || !services.mailReady || !link) throw Object.assign(
    new Error('delivery unavailable'), { code: 'delivery_unavailable' },
  );
  const code = newCode();
  const recipient = await services.adminRpc('managed_staff_issue_mailbox_code', {
    p_identity_id: id,
    p_hash: await hashCode(services.codeSecret, 'staff-mailbox', id, code),
  });
  if (recipient) {
    await services.sendMail(recipient, 'Verify your Jentra staff email',
      'Open ' + link + '\nVerification ID: ' + id + '\nCode: ' + code +
      '\n\nThe code expires in 10 minutes.');
  }
}

function staffPassword() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return 'Jt2-' + Array.from(bytes, (value) => value.toString(16).padStart(2, '0')).join('');
}

async function deliverStaff(staff, services) {
  const claim = await services.adminRpc('managed_staff_claim', { p_identity_id: staff.identity_id });
  if (!claim) return staff;
  const scope = { p_identity_id: claim.identity_id, p_lease_token: claim.lease_token };
  const metadata = {
    managed_org_admin: true,
    managed_staff_identity_id: claim.identity_id,
    provisioned_tenant_id: claim.tenant_id,
    managed_staff_generation: claim.generation,
    managed_staff_prepare_token: claim.lease_token,
  };
  const password = staffPassword();
  try {
    const userId = claim.user_id || await services.createStaffUser(
      claim.username + aliasDomain, password, metadata, claim.name,
    );
    if (claim.user_id) await services.updateStaffPassword(userId, password, metadata);
    if (!await services.adminRpc('managed_staff_bind', { ...scope, p_user_id: userId })) {
      throw new Error('staff claim changed');
    }
    if (claim.delivery === 'email') {
      await services.sendMail(claim.email, 'Your Jentra sign-in',
        'Username: ' + claim.username + '\nTemporary password: ' + password +
        '\nExpires: ' + claim.expires_at +
        '\n\nChange this password when you first sign in.',
        'jentra-staff/' + claim.generation);
    }
    if (!await services.adminRpc('managed_staff_finish', scope)) {
      throw new Error('staff handover changed');
    }
    return {
      ...staff, status: 'issued', expires_at: claim.expires_at,
      ...(claim.delivery === 'reveal' ? { temporary_password: password } : {}),
    };
  } catch {
    await services.adminRpc('managed_staff_fail', scope).catch(() => services.log('staff_handover_status_failed'));
    services.log('staff_handover_failed');
    return { ...staff, status: 'failed' };
  }
}

async function managedStaff(data, services) {
  let staff;
  if (data.action === 'reissue_staff_credentials') {
    staff = await services.callerRpc('request_managed_staff_reissue', {
      p_identity_id: clean(data.identity_id),
      p_request_id: clean(data.request_id),
    });
  } else {
    const manager = data.action === 'create_hr_manager';
    staff = await services.callerRpc('prepare_managed_staff_identity', {
      p_tenant_id: clean(data.tenant_id),
      p_kind: manager ? 'hr_manager' : 'employee',
      p_request_id: clean(data.request_id),
      p_delivery: data.delivery,
      p_username: clean(manager ? data.username : data.name_segment) || null,
      p_name: manager && typeof data.name === 'string' ? data.name.trim() : null,
      p_email: clean(data.email) || null,
      p_legal_entity_ids: manager ? data.legal_entity_ids : [],
      p_legal_entity_id: manager ? null : clean(data.legal_entity_id),
      p_branch_id: manager ? null : clean(data.branch_id),
      p_employee_id: manager ? null : clean(data.employee_id),
      p_migration_id: clean(data.migration_id) || null,
      p_supersedes_membership_id: clean(data.supersedes_membership_id) || null,
      p_supersedes_link_id: clean(data.supersedes_link_id) || null,
    });
  }
  if (!staff?.identity_id) return error(503, 'identity_unavailable');
  if (staff.status === 'verification_required') {
    await staffVerificationCode(staff, services);
    return json(200, staff);
  }
  if (staff.status === 'prepared' && staff.delivery === 'email' && !services.mailReady) {
    return error(503, 'delivery_unavailable');
  }
  return json(200, staff.status === 'prepared' ? await deliverStaff(staff, services) : staff);
}

async function verifyStaffMailbox(data, services) {
  const id = clean(data.identity_id);
  if (!uuidPattern.test(id) || !validCode(data.code)) return error(400, 'invalid_code');
  if (!services.codeSecret || !services.mailReady) return error(503, 'delivery_unavailable');
  const verified = await services.adminRpc('managed_staff_consume_mailbox_code', {
    p_identity_id: id,
    p_hash: await hashCode(services.codeSecret, 'staff-mailbox', id, data.code),
  });
  if (!verified) return error(400, 'invalid_code');
  const result = await deliverStaff({ identity_id: id, status: 'prepared' }, services);
  if (result.status !== 'issued') return error(502, 'handover_failed');
  return ok();
}

export async function handleOrganizationIdentity(request, services) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return error(405, 'method_not_allowed');
  const data = await requestData(request);
  if (!data) return error(400, 'invalid_input');
  try {
    if (data.action === 'system_owner_request_code' || data.action === 'system_owner_verify_code') {
      return await ownerVerification(data, services);
    }
    if (data.action === 'verify_staff_mailbox') return await verifyStaffMailbox(data, services);
    if (data.action === 'request_reset' || data.action === 'request_operator_reset') {
      const operator = data.action === 'request_operator_reset';
      const login = operator ? operatorLogin(data.login) : loginEmail(data.login);
      services.background(sendResetCode(login, services, operator).catch(() => services.log('reset_delivery_failed')));
      return ok();
    }
    if (data.action === 'reset_password' || data.action === 'reset_operator_password') {
      if (!validPassword(data.new_password)) return error(400, 'weak_password');
      const operator = data.action === 'reset_operator_password';
      const login = operator ? operatorLogin(data.login) : loginEmail(data.login);
      if (!login || !validCode(data.code)) return error(400, 'invalid_code');
      if (!services.codeSecret) return error(503, 'identity_unavailable');
      const proof = {
        p_login_email: login,
        p_hash: await hashCode(services.codeSecret, operator ? 'operator-reset' : 'reset', login, data.code),
      };
      const reset = operator
        ? await services.adminRpc('platform_operator_consume_reset', proof)
        : await services.consumeReset(proof);
      if (!reset?.user_id) return error(400, 'invalid_code');
      if (operator) {
        if (!reset.token) return error(503, 'identity_unavailable');
        await services.setOperatorPassword(reset.user_id, data.new_password, reset.token);
      } else if (reset.staff_token) {
        await services.updateStaffPassword(reset.user_id, data.new_password, {
          managed_staff_password_token: reset.staff_token,
        });
      } else {
        await services.setPassword(reset.user_id, data.new_password, null, reset.reset_token);
      }
      return ok();
    }

    const actor = await services.authenticate();
    if (!actor) return error(401, 'authentication_required');
    if (['create_hr_manager', 'create_employee_credentials', 'reissue_staff_credentials'].includes(data.action)) {
      return await managedStaff(data, services);
    }
    if (operatorAccountActions.has(data.action)) return await operatorAccount(data, actor, services);
    if (data.action === 'request_purchase_email_code' || data.action === 'verify_purchase_email_code') {
      return await verifyPurchaseEmail(data, actor, services);
    }
    const profile = await services.profile();
    if (data.action === 'provision_admin' || data.action === 'reissue_admin') return await handover(data, actor, services);
    if (data.action === 'create_department_account') return await createDepartmentAccount(data, actor, profile, services);
    if (data.action === 'profile') return json(200, profile);
    if (['change_password', 'request_recovery_email', 'verify_recovery_email'].includes(data.action)
        && await services.operatorAssigned()) return error(403, 'forbidden');
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
    const staffAccount = profile.account_kind === 'employee' || profile.account_kind === 'hr_manager';
    if (data.action === 'change_password' && !profile.is_administrator && !staffAccount &&
        !(profile.username && profile.must_change_password && !profile.organization_locked)) {
      return error(403, 'forbidden');
    }
    if (typeof data.current_password !== 'string' || !data.current_password || !actor.email ||
        !await services.checkPassword(actor, data.current_password)) return error(403, 'incorrect_password');
    if (data.action === 'change_password') {
      if (!validPassword(data.new_password)) return error(400, 'weak_password');
      if (data.new_password === data.current_password) return error(400, 'password_unchanged');
      if (staffAccount) {
        const token = await services.adminRpc('managed_staff_authorize_password_change', {
          p_user_id: actor.id, p_password_changed_at: profile.password_changed_at,
        });
        await services.updateStaffPassword(actor.id, data.new_password, {
          managed_staff_password_token: token,
        });
        return ok();
      }
      const token = profile.must_change_password ? await services.authorizeChange({
        p_user_id: actor.id, p_password_changed_at: profile.password_changed_at,
      }) : null;
      await services.setPassword(actor.id, data.new_password, null, token);
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
