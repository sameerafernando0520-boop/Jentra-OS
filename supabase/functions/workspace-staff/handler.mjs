const headers = {
  'content-type': 'application/json',
  'cache-control': 'no-store',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'access-control-allow-methods': 'POST, OPTIONS',
};
const id = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const usernamePattern = /^[a-z0-9][a-z0-9_-]{2,39}$/;
const reply = (status, body) => new Response(JSON.stringify(body), { status, headers });
const invalidLogin = () => reply(401, { code: 'INVALID_CREDENTIALS' });

export async function handleWorkspaceStaff(request, dependencies) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return reply(405, { code: 'METHOD_NOT_ALLOWED' });
  let payload;
  try {
    const reader = request.body?.getReader();
    if (!reader) return reply(400, { code: 'INVALID_REQUEST' });
    // Bound memory and bytes before parsing, including chunked requests without
    // Content-Length. Stop consuming the stream as soon as it exceeds the cap.
    const bytes = new Uint8Array(8192);
    let length = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        if (value.byteLength > bytes.length - length) {
          // A peer's cancellation cleanup must not delay the refusal.
          void reader.cancel().catch(() => {});
          return reply(413, { code: 'REQUEST_TOO_LARGE' });
        }
        bytes.set(value, length);
        length += value.byteLength;
      }
      payload = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, length)));
    } finally {
      reader.releaseLock();
    }
  } catch {
    return reply(400, { code: 'INVALID_REQUEST' });
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return reply(400, { code: 'INVALID_REQUEST' });
  }
  const username = typeof payload.username === 'string' ? payload.username.trim().toLowerCase() : '';
  const password = payload.password;
  if (payload.operation === 'login') {
    if (!usernamePattern.test(username) || typeof password !== 'string' ||
      password.length < 1 || password.length > 256 ||
      Object.keys(payload).some(key => !['operation', 'username', 'password'].includes(key))) {
      return invalidLogin();
    }
    try {
      const target = await dependencies.loginTarget(username);
      if (target.limited === true) return reply(429, { code: 'SIGN_IN_UNAVAILABLE' });
      // Unknown, suspended and revoked users follow the same password-auth path
      // and receive the same error. Resolution is never returned to the caller.
      const session = await dependencies.signIn(
        target.email ?? 'unknown.account@accounts.jentra.invalid', password,
      );
      if (!target.email || typeof session?.refresh_token !== 'string') return invalidLogin();
      return reply(200, { refresh_token: session.refresh_token });
    } catch {
      return invalidLogin();
    }
  }
  if (payload.operation !== 'create') return reply(400, { code: 'INVALID_REQUEST' });
  try {
    const actor = await dependencies.authenticate();
    if (!actor) return reply(401, { code: 'AUTHENTICATION_REQUIRED' });
    if (Object.keys(payload).some(key => ![
      'operation', 'tenant_id', 'request_id', 'username', 'display_name', 'role_ids', 'password',
    ].includes(key)) || !id.test(payload.tenant_id) || !id.test(payload.request_id) ||
      !usernamePattern.test(username) || typeof password !== 'string' || password.length < 12 ||
      new TextEncoder().encode(password).length > 256 || password.includes('\0') ||
      typeof payload.display_name !== 'string' || !payload.display_name.trim() ||
      payload.display_name.length > 100 || /[\u0000-\u001f\u007f]/.test(payload.display_name) ||
      !Array.isArray(payload.role_ids) || payload.role_ids.length < 1 || payload.role_ids.length > 16 ||
      payload.role_ids.some(role => typeof role !== 'string' || !id.test(role))) {
      return reply(400, { code: 'INVALID_STAFF_ACCOUNT' });
    }
    const args = {
      p_tenant_id: payload.tenant_id, p_request_id: payload.request_id,
      p_username: username, p_display_name: payload.display_name.trim(),
      p_role_ids: [...new Set(payload.role_ids)].sort(),
    };
    let reservation = await dependencies.reserve(args);
    const validReservation = value => value?.request_id === payload.request_id &&
      value.tenant_id === payload.tenant_id && value.created_by === actor &&
      value.username === username && value.display_name === args.p_display_name &&
      JSON.stringify(value.role_ids) === JSON.stringify(args.p_role_ids) &&
      value.email === `staff.${payload.request_id.replaceAll('-', '')}@accounts.jentra.invalid`;
    if (!validReservation(reservation)) throw Error('UNCONFIRMED_RESERVATION');
    let userId = reservation.user_id;
    let reusedIdentity = Boolean(userId);
    if (!userId) {
      try {
        const user = await dependencies.createUser({
          email: reservation.email, password, email_confirm: true,
          user_metadata: { full_name: args.p_display_name },
          app_metadata: {
            jentra_staff_request: payload.request_id, jentra_tenant_id: payload.tenant_id,
            jentra_created_by: actor, jentra_username: username,
          },
        });
        userId = user?.id;
      } catch (error) {
        // Auth may have committed before its response was lost, or a parallel
        // retry may have created it. Only a server-bound identity can resume.
        reservation = await dependencies.reserve(args);
        if (!validReservation(reservation) || !reservation.user_id) throw error;
        userId = reservation.user_id;
        reusedIdentity = true;
      }
    }
    if (reusedIdentity) {
      // Recovery preserves the request identity, never the password. Verify a
      // re-entered password, including a parallel/lost-response retry. Never
      // reset an already-created identity's password as a replay side effect.
      try {
        const session = await dependencies.signIn(reservation.email, password);
        if (session?.user?.id !== userId || typeof session.refresh_token !== 'string' ||
          session.refresh_token.length === 0) {
          return reply(400, { code: 'STAFF_ORIGINAL_PASSWORD_REQUIRED' });
        }
      }
      catch { return reply(400, { code: 'STAFF_ORIGINAL_PASSWORD_REQUIRED' }); }
    }
    if (typeof userId !== 'string' || !id.test(userId)) throw Error('UNCONFIRMED_USER');
    const result = await dependencies.complete({
      p_tenant_id: payload.tenant_id, p_request_id: payload.request_id, p_user_id: userId,
    });
    if (result?.request_id !== payload.request_id || result.tenant_id !== payload.tenant_id ||
      result.user_id !== userId || result.username !== username || result.status !== 'active' ||
      !id.test(result.membership_id)) throw Error('UNCONFIRMED_MEMBERSHIP');
    return reply(200, result);
  } catch (error) {
    if (error?.code === '42501' && error?.message === 'STAFF_ACCESS_CHANGED') {
      return reply(409, { code: 'STAFF_ACCESS_CHANGED' });
    }
    if (error?.code === '42501') return reply(403, { code: 'STAFF_ACCESS_DENIED' });
    if (error?.code === '23505') return reply(409, { code: 'USERNAME_UNAVAILABLE' });
    if (error?.code === '23514') return reply(409, { code: 'STAFF_LIMIT_REACHED' });
    if (error?.code === '22023') return reply(400, { code: 'INVALID_STAFF_ACCOUNT' });
    if (error?.code === 'weak_password') return reply(400, { code: 'PASSWORD_TOO_WEAK' });
    // Never return an Auth/API exception: it can contain credentials or tokens.
    return reply(503, { code: 'STAFF_RESULT_UNCONFIRMED' });
  }
}
