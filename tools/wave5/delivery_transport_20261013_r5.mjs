import https from 'node:https';
import crypto from 'node:crypto';
import { PROJECT_URL, PROJECT_ID, GuardError, requireGuard, isUuid, hashBytes, hashJson, safeCode } from './runtime_contract.mjs';
import { SQL_CONTRACTS, SQL_PREPARATION_CONTRACTS } from './runtime_fixture_spec.mjs';

const RPCS = new Set([...Object.values(SQL_CONTRACTS), ...Object.values(SQL_PREPARATION_CONTRACTS)]
  .map(contract => contract.signature.split('(')[0].replace(/^api\./, '')).concat(['wave5_delivery_review','wave5_integration_list']));
const MAX_BODY = 8 * 1024 * 1024 + 1;
const AUTH_PATH = /^\/auth\/v1\/(token\?grant_type=password|user|factors|factors\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/(challenge|verify))$/i;
const fail = code => { throw new GuardError(code); };

// This is an actual HTTPS implementation. Constructor/import performs no I/O or secret read.
// Every connection has its own TLS agent/socket queue. Credentials remain closure-private.
export function createSupabaseHttpsTransport({ projectId, apiKey, requestFactory = https.request,
  agentFactory = () => new https.Agent({ keepAlive: true, maxSockets: 1, maxFreeSockets: 1 }), timeoutMs = 30000 }) {
  requireGuard(projectId === PROJECT_ID && typeof apiKey === 'string' && apiKey.length > 8, 'EXACT_DEVELOPMENT_TARGET_REQUIRED');
  const agents = new Map(); let closed = false, activeSends = 0;
  function connection() {
    requireGuard(!closed, 'RUN_ABORTED');
    const handle = Object.freeze({ connectionId: `w5-${crypto.randomUUID()}` });
    agents.set(handle, agentFactory()); return handle;
  }
  async function send(handle, route, { method = 'POST', body, bearer, signal, onTransportStart, onTransportEnd, profile } = {}) {
    requireGuard(!closed && agents.has(handle) && !signal?.aborted, 'RUN_ABORTED');
    requireGuard(AUTH_PATH.test(route) || /^\/rest\/v1\/rpc\/[a-z0-9_]+$/.test(route)
      && RPCS.has(route.split('/').at(-1)), 'EXACT_DEVELOPMENT_TARGET_REQUIRED');
    requireGuard(route === '/auth/v1/user' ? method === 'GET' : method === 'POST', 'EXACT_DEVELOPMENT_TARGET_REQUIRED');
    if (route.startsWith('/rest/')) requireGuard(profile === 'api' && typeof bearer === 'string' && bearer.length > 8, 'PARTICIPANT_TRANSPORT_MISMATCH');
    const bytes = body === undefined ? '' : JSON.stringify(body);
    const startedAt = new Date().toISOString(); let sentAt = null;
    const headers = { apikey: apiKey, 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bytes) };
    if (bearer) headers.Authorization = `Bearer ${bearer}`;
    if (profile) { headers['Content-Profile'] = profile; headers['Accept-Profile'] = profile; }
    return new Promise((resolve, reject) => {
      let settled = false, req, dispatched = false; const chunks = []; let size = 0;
      const release = () => { if (dispatched) { activeSends--; dispatched = false; } };
      const finishError = code => { if (!settled) { settled = true; release(); reject(new GuardError(code)); } };
      try {
        req = requestFactory(new URL(route, PROJECT_URL), { method, headers, agent: agents.get(handle), signal }, res => {
          res.on('data', chunk => { size += chunk.length; if (size > MAX_BODY) { req.destroy(); finishError('LIMIT_EXCEEDED'); } else chunks.push(chunk); });
          res.on('error', () => finishError('TRANSPORT_UNCERTAIN'));
          res.on('end', () => {
            if (settled) return;
            try {
              onTransportEnd?.();
              const raw = Buffer.concat(chunks), finishedAt = new Date().toISOString();
              let value = null;
              try { value = raw.length ? JSON.parse(raw.toString('utf8')) : null; } catch { return finishError('INVALID_PROVIDER_OUTCOME'); }
              const evidence = { projectId: PROJECT_ID, method, route, startedAt, sentAt, finishedAt, connectionId: handle.connectionId,
                status: res.statusCode, responseSha256: hashBytes(raw), responseBytes: raw.length };
              settled = true; release();
              resolve({ ok: res.statusCode >= 200 && res.statusCode < 300, status: res.statusCode, value,
                responseSha256: evidence.responseSha256, transportEvidenceSha256: hashJson(evidence), evidence });
            } catch { finishError('PROVIDER_FAILURE'); }
          });
        });
        req.on('error', () => finishError(signal?.aborted ? 'RUN_ABORTED' : 'TRANSPORT_UNCERTAIN'));
        req.setTimeout(timeoutMs, () => { req.destroy(); finishError('TRANSPORT_TIMEOUT'); });
        // New sockets are assigned before their TLS handshake completes. Dispatch
        // only after verified TLS, including any socket/handshake queue in the
        // synchronous coordinator deadline and actual-start observation.
        req.once('socket', socket => {
          const write = () => {
            if (settled) { req.destroy(); return; }
            try { requireGuard(socket.encrypted === true && socket.authorized === true, 'EXACT_DEVELOPMENT_TARGET_REQUIRED');
              requireGuard(!signal?.aborted, 'RUN_ABORTED'); requireGuard(activeSends < 2000, 'GENERATOR_CAPACITY_UNSUPPORTED');
              onTransportStart?.(); activeSends++; dispatched = true; sentAt = new Date().toISOString(); req.end(bytes); }
            catch (error) { req.destroy(); finishError(error instanceof GuardError ? safeCode(error.code) : 'PROVIDER_FAILURE'); }
          };
          if (settled) { req.destroy(); return; }
          if (socket?.encrypted !== true) { req.destroy(); finishError('EXACT_DEVELOPMENT_TARGET_REQUIRED'); return; }
          if (socket.authorized === true) write(); else socket.once('secureConnect', write);
        });
      } catch { finishError('PROVIDER_FAILURE'); }
    });
  }
  return Object.freeze({ connection, send,
    drainIdleConnections() { for (const agent of agents.values()) for (const sockets of Object.values(agent.freeSockets ?? {}))
      for (const socket of sockets) socket.destroy(); },
    closeConnection(handle) { const agent = agents.get(handle); agent?.destroy(); agents.delete(handle); },
    close() { closed = true; for (const agent of agents.values()) agent.destroy(); agents.clear(); } });
}

export function decodeReceivedAccessToken(token) {
  // Parsing is used only to locate the real server session. Online /user plus auth.sessions must verify it.
  requireGuard(typeof token === 'string' && token.split('.').length === 3, 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
  try {
    const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
    requireGuard(claims.iss === `${PROJECT_URL}/auth/v1` && claims.role === 'authenticated'
      && isUuid(claims.sub) && isUuid(claims.session_id) && Number.isSafeInteger(claims.exp)
      && ['aal1', 'aal2'].includes(claims.aal), 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
    return claims;
  } catch { fail('ONLINE_SESSION_ROW_PROOF_REQUIRED'); }
}

export function totpFromPrivateSecret(secret, nowMs = Date.now()) {
  requireGuard(typeof secret === 'string' && /^[A-Z2-7]+=*$/.test(secret.toUpperCase()) && Number.isFinite(nowMs), 'GENUINE_RUNTIME_MFA_REQUIRED');
  let bits = '', bytes = [];
  for (const letter of secret.toUpperCase().replace(/=+$/, '')) bits += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.indexOf(letter).toString(2).padStart(5, '0');
  for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2));
  requireGuard(bytes.length >= 10, 'GENUINE_RUNTIME_MFA_REQUIRED');
  const counter = Buffer.alloc(8); counter.writeBigUInt64BE(BigInt(Math.floor(nowMs / 30000)));
  const digest = crypto.createHmac('sha1', Buffer.from(bytes)).update(counter).digest(), offset = digest.at(-1) & 15;
  return String((digest.readUInt32BE(offset) & 0x7fffffff) % 1000000).padStart(6, '0');
}

export function createAuthClient({ transport, privateActors, privateSessions, readServerSession, persistPrivateSession }) {
  requireGuard(typeof privateActors === 'function' && typeof readServerSession === 'function', 'PRIVATE_PROVIDER_INCOMPLETE');
  const hidden = new WeakMap();
  async function user(handle, token, signal) {
    const online = await transport.send(handle, '/auth/v1/user', { method: 'GET', bearer: token, signal });
    requireGuard(online.ok && isUuid(online.value?.id), 'ONLINE_SESSION_ROW_PROOF_REQUIRED'); return online;
  }
  async function verify(handle, token, slot, actor, signal) {
    const online = await user(handle, token, signal), claims = decodeReceivedAccessToken(token);
    requireGuard(online.value.id === actor.id && claims.sub === actor.id, 'SESSION_ACTOR_MISMATCH');
    const row = await readServerSession({ sessionId: claims.session_id, actorId: actor.id, signal });
    requireGuard(row?.id === claims.session_id && row.userId === actor.id && row.committed === true && row.readOnly === true
      && row.present === true && /^[a-f0-9]{64}$/.test(row.evidenceSha256), 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
    let expiryMs = claims.exp * 1000;
    if (row.notAfter) expiryMs = Math.min(expiryMs, Date.parse(row.notAfter));
    requireGuard(expiryMs >= Date.now() + 900000, 'FRESH_UNREVOKED_SESSION_REQUIRED');
    const factor = row.factorId;
    if (claims.aal === 'aal2') requireGuard(row.aal === 'aal2' && isUuid(factor)
      && online.value.factors?.some(f => f.id === factor && f.status === 'verified'), 'GENUINE_RUNTIME_MFA_REQUIRED');
    const evidence = hashJson({ online: online.transportEvidenceSha256, row: row.evidenceSha256, subject: actor.id,
      sessionId: claims.session_id, aal: claims.aal, expiresAt: new Date(expiryMs).toISOString() });
    const descriptor = Object.freeze({ kind: 'auth', ...slot, actorId: actor.id, sessionId: claims.session_id,
      connectionId: handle.connectionId, connectionEvidenceSha256: hashJson({ connectionId: handle.connectionId, online: online.transportEvidenceSha256 }),
      verificationEvidenceSha256: evidence, onlineAuthVerified: true, serverSessionRowVerified: true,
      serverSessionId: row.id, serverSessionActorId: row.userId, issuer: claims.iss, authRole: claims.role,
      verifiedAt: new Date().toISOString(), expiresAt: new Date(expiryMs).toISOString(), revoked: false, aal: claims.aal,
      realMfaVerified: claims.aal === 'aal2', verifiedFactorId: claims.aal === 'aal2' ? factor : null });
    hidden.set(descriptor, { handle, token, actor, slot }); return descriptor;
  }
  async function acquire(slot, needsMfa, signal) {
    requireGuard(slot.actorLabel !== 'operator', 'SESSION_ACTOR_MISMATCH');
    const actor = await privateActors(slot.actorLabel);
    requireGuard(isUuid(actor?.id) && typeof actor.email === 'string' && typeof actor.password === 'string', 'EXACT_REAL_AUTH_IDS_REQUIRED');
    const handle = transport.connection();
    const signed = await transport.send(handle, '/auth/v1/token?grant_type=password', { body: { email: actor.email, password: actor.password }, signal });
    requireGuard(signed.ok && signed.value?.user?.id === actor.id && typeof signed.value?.access_token === 'string', 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
    let tokens = signed.value;
    if (needsMfa) {
      requireGuard(isUuid(actor.mfa?.factorId) && typeof actor.mfa?.secret === 'string', 'GENUINE_RUNTIME_MFA_REQUIRED');
      const challenge = await transport.send(handle, `/auth/v1/factors/${actor.mfa.factorId}/challenge`, { bearer: tokens.access_token, body: {}, signal });
      requireGuard(challenge.ok && isUuid(challenge.value?.id), 'GENUINE_RUNTIME_MFA_REQUIRED');
      const verified = await transport.send(handle, `/auth/v1/factors/${actor.mfa.factorId}/verify`, { bearer: tokens.access_token,
        body: { challenge_id: challenge.value.id, code: totpFromPrivateSecret(actor.mfa.secret) }, signal });
      requireGuard(verified.ok && typeof verified.value?.access_token === 'string', 'GENUINE_RUNTIME_MFA_REQUIRED'); tokens = verified.value;
    }
    const descriptor = await verify(handle, tokens.access_token, slot, actor, signal);
    if (needsMfa) requireGuard(descriptor.aal === 'aal2', 'GENUINE_RUNTIME_MFA_REQUIRED');
    if (persistPrivateSession) await persistPrivateSession({ slot, actorId: actor.id, sessionId: descriptor.sessionId,
      accessToken: tokens.access_token, refreshToken: tokens.refresh_token });
    return descriptor;
  }
  async function adopt(slot, needsMfa, signal) {
    // Reuse only an explicitly supplied real private session; it still requires online Auth and row proof.
    requireGuard(typeof privateSessions === 'function', 'PRIVATE_PROVIDER_INCOMPLETE');
    const actor = await privateActors(slot.actorLabel), tokens = await privateSessions(slot);
    requireGuard(isUuid(actor?.id) && typeof tokens?.accessToken === 'string', 'EXACT_REAL_AUTH_IDS_REQUIRED');
    const descriptor = await verify(transport.connection(), tokens.accessToken, slot, actor, signal);
    if (needsMfa) requireGuard(descriptor.aal === 'aal2' && descriptor.realMfaVerified, 'GENUINE_RUNTIME_MFA_REQUIRED');
    return descriptor;
  }
  return Object.freeze({ acquire, adopt, async reverify(descriptor, signal) { const privateValue = hidden.get(descriptor);
    requireGuard(privateValue, 'ONLINE_SESSION_ROW_PROOF_REQUIRED');
    return verify(privateValue.handle, privateValue.token, privateValue.slot, privateValue.actor, signal); },
    privateConnection(descriptor) { const value = hidden.get(descriptor); requireGuard(value, 'SESSION_ACTOR_MISMATCH'); return value; },
    async enrollPrivateTotp(slot, persistFactor, signal) {
      requireGuard(typeof persistFactor === 'function', 'GENUINE_RUNTIME_MFA_REQUIRED');
      const descriptor = await acquire(slot, false, signal), privateValue = hidden.get(descriptor);
      const enrolled = await transport.send(privateValue.handle, '/auth/v1/factors', { bearer: privateValue.token,
        body: { factor_type: 'totp', friendly_name: 'Jentra bounded runtime', issuer: 'Jentra OS' }, signal });
      requireGuard(enrolled.ok && isUuid(enrolled.value?.id) && typeof enrolled.value.totp?.secret === 'string', 'GENUINE_RUNTIME_MFA_REQUIRED');
      // Real Auth enrollment; factor secret never enters a public descriptor/journal.
      await persistFactor({ actorLabel: slot.actorLabel, actorId: descriptor.actorId, factorId: enrolled.value.id,
        secret: enrolled.value.totp.secret, status: 'enrolled-unverified' });
      const challenge = await transport.send(privateValue.handle, `/auth/v1/factors/${enrolled.value.id}/challenge`,
        { bearer: privateValue.token, body: {}, signal });
      requireGuard(challenge.ok && isUuid(challenge.value?.id), 'GENUINE_RUNTIME_MFA_REQUIRED');
      const verified = await transport.send(privateValue.handle, `/auth/v1/factors/${enrolled.value.id}/verify`,
        { bearer: privateValue.token, body: { challenge_id: challenge.value.id, code: totpFromPrivateSecret(enrolled.value.totp.secret) }, signal });
      requireGuard(verified.ok, 'GENUINE_RUNTIME_MFA_REQUIRED');
      const result = await verify(privateValue.handle, verified.value.access_token, slot, privateValue.actor, signal);
      requireGuard(result.aal === 'aal2', 'GENUINE_RUNTIME_MFA_REQUIRED');
      await persistFactor({ actorLabel: slot.actorLabel, actorId: descriptor.actorId, factorId: enrolled.value.id,
        secret: enrolled.value.totp.secret, status: 'server-verified' });
      return result;
    } });
}
