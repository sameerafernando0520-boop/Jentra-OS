const encoder = new TextEncoder();
const decoder = new TextDecoder();
const aliasDomain = '@admin.jentra.invalid';

const json = (status, body) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
});

export function fault(code, retryable = true) {
  return Object.assign(new Error(code), { code, retryable });
}

export async function authorized(request, expectedSecret) {
  const provided = request.headers.get('x-jentra-handover-secret') ?? '';
  if (!expectedSecret || provided.length > 256) return false;
  const [expectedHash, providedHash] = await Promise.all([expectedSecret, provided].map(
    async (value) => new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))),
  ));
  return expectedHash.reduce((difference, byte, index) => difference | (byte ^ providedHash[index]), 0) === 0;
}

function fromBase64(value) {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

function toBase64(value) {
  return btoa(String.fromCharCode(...value));
}

export async function handoverKey(value) {
  if (!value) return null;
  try {
    const key = fromBase64(value);
    if (key.length !== 32) return null;
    return await crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt', 'decrypt']);
  } catch {
    return null;
  }
}

function temporaryPassword() {
  const random = crypto.getRandomValues(new Uint8Array(24));
  const digits = Array.from(random, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return 'Jt2-' + digits;
}

function encryptionContext(job) {
  return encoder.encode(JSON.stringify(['subscription-handover', job.order_id, job.generation]));
}

async function encryptPassword(job, key, password) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: encryptionContext(job) },
    key, encoder.encode(password));
  return ['v1', toBase64(iv), toBase64(new Uint8Array(ciphertext))].join('.');
}

async function decryptPassword(job, key) {
  try {
    const [version, iv, ciphertext] = job.ciphertext.split('.');
    if (version !== 'v1') throw fault('credential_unavailable');
    const value = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromBase64(iv),
      additionalData: encryptionContext(job) }, key, fromBase64(ciphertext));
    return decoder.decode(value);
  } catch {
    throw fault('credential_unavailable');
  }
}

async function prepareIdentity(job, services, scope, password) {
  const getIdentity = async () => {
    const identity = await services.rpc('subscription_handover_identity', scope);
    if (!identity) throw fault('job_unavailable');
    return identity;
  };
  const metadata = {
    managed_org_admin: true,
    provisioned_tenant_id: job.tenant_id,
    checkout_order_id: job.order_id,
    jentra_handover_generation: job.generation,
    jentra_subscription_prepare_token: job.lease_token,
  };
  let identity = await getIdentity();
  if (!identity.user_id) {
    try {
      const userId = await services.createUser(job.username + aliasDomain, password, metadata);
      identity = { user_id: userId, password_prepared: true };
    } catch (error) {
      if (error?.code !== 'username_unavailable') throw error;
      identity = await getIdentity();
      if (!identity.user_id) throw fault('username_unavailable', false);
    }
  }
  if (!identity.password_prepared) {
    await services.setPassword(identity.user_id, password, metadata);
  }
  if (!await services.rpc('subscription_register_handover', { ...scope, p_user_id: identity.user_id })) {
    throw fault('job_unavailable');
  }
}

async function deliver(job, services) {
  const scope = { p_order_id: job.order_id, p_lease_token: job.lease_token, p_generation: job.generation };
  try {
    let expiresAt = job.credential_expires_at;
    let password;
    if (job.ciphertext) {
      password = await decryptPassword(job, services.key);
    } else {
      password = temporaryPassword();
      const ciphertext = await encryptPassword(job, services.key, password);
      expiresAt = await services.rpc('subscription_stage_handover', { ...scope, p_ciphertext: ciphertext });
      if (!expiresAt) throw fault('job_unavailable');
    }
    await prepareIdentity(job, services, scope, password);
    const email = await services.sendMail({
      to: job.email,
      subject: 'Your Jentra OS administrator sign-in',
      text: [
        'Sign in to Jentra OS using these credentials.',
        'Username: ' + job.username,
        'Temporary password: ' + password,
        'Expires: ' + new Date(expiresAt).toUTCString(),
        '',
        'Change your password when prompted on your first sign-in. If the credential expires, use Forgot password or return to your purchase to request a new one.',
      ].join('\n'),
    }, 'subscription-handover/' + job.order_id + '/' + job.generation);
    if (!await services.rpc('subscription_finish_handover', { ...scope, p_message_id: email })) {
      throw fault('job_unavailable');
    }
  } catch (error) {
    await services.rpc('subscription_fail_handover', {
      ...scope, p_error: error?.code ?? 'job_unavailable', p_retryable: error?.retryable !== false,
    });
  }
}

export async function handleSubscriptionHandover(request, services) {
  if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  if (!await authorized(request, services.secret)) return json(401, { error: 'authentication_required' });
  if (!services.key || !services.mailReady) return json(503, { error: 'handover_unavailable' });

  try {
    const job = await services.rpc('subscription_claim_handover', {});
    if (!job) return json(200, { ok: true, claimed: false });
    await deliver(job, services);
    return json(200, { ok: true, claimed: true });
  } catch {
    services.log('subscription_handover_worker_unavailable');
    return json(503, { error: 'handover_unavailable' });
  }
}
