import https from 'node:https';
import { PROJECT } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';

const must = (ok, code) => { if (!ok) { const error = Error(code); error.publicCode = code; throw error; } };
const actorEmails = Object.freeze(Object.fromEntries(['proposer','approver','executor','billing-admin','operator','foreign-member']
  .map(label => [label, `w5-${label}@jentra.invalid`])));
export const APPROVED_ACTOR_EMAILS = actorEmails;

function privateJson(url, headers, method, body, requestFactory = https.request, timeoutMs = 45000) {
  const bytes = body === undefined ? null : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    let request, settled = false, timer, sent = false, count = 0; const chunks = [];
    const fail = code => { if (settled) return; settled = true; clearTimeout(timer); request?.destroy();
      const error = Error(code); error.publicCode = code; error.sent = sent; reject(error); };
    try {
      request = requestFactory(url, { method, rejectUnauthorized: true, headers: { ...headers,
        ...(bytes === null ? {} : { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(bytes) }) } }, response => {
        response.on('error', () => fail('PRIVATE_HTTP_RESPONSE_UNCERTAIN'));
        response.on('data', chunk => { if (settled) return; count += chunk.length;
          if (count > 2 * 1024 * 1024) fail('PRIVATE_HTTP_RESPONSE_LIMIT'); else chunks.push(chunk); });
        response.on('end', () => {
          if (settled) return;
          const raw = Buffer.concat(chunks);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            let returnedCode; try { returnedCode = JSON.parse(raw).error_code; } catch {}
            const code = ['email_exists','user_already_exists'].includes(returnedCode) ? 'APPROVED_AUTH_EMAIL_COLLISION'
              : [401,403].includes(response.statusCode) ? 'PRIVATE_AUTH_PERMISSION_DENIED'
              : response.statusCode === 429 ? 'PRIVATE_AUTH_RATE_LIMITED' : 'PRIVATE_HTTP_NON_SUCCESS';
            fail(code); return;
          }
          let value; try { value = JSON.parse(raw); } catch { fail('PRIVATE_HTTP_JSON_INVALID'); return; }
          settled = true; clearTimeout(timer); resolve({ value, status: response.statusCode,
            responseSha256: hashBytes(raw), actualFinishedAt: new Date().toISOString() });
        });
      });
      request.on('error', () => fail('PRIVATE_HTTP_TRANSPORT_UNCERTAIN'));
      timer = setTimeout(() => fail('PRIVATE_HTTP_TIMEOUT_UNCERTAIN'), timeoutMs);
      request.once('socket', socket => {
        const send = () => { if (settled) { request.destroy(); return; }
          if (socket.encrypted !== true || socket.authorized !== true) { fail('VERIFIED_PRIVATE_TLS_REQUIRED'); return; }
          sent = true; request.end(bytes ?? undefined); };
        if (settled) { request.destroy(); return; }
        if (socket.encrypted !== true) { fail('VERIFIED_PRIVATE_TLS_REQUIRED'); return; }
        if (socket.authorized === true) send(); else socket.once('secureConnect', send);
      });
    } catch { fail('PRIVATE_HTTP_REQUEST_FAILED'); }
  });
}

export function createPrivateKeyReader(ownerToken, options = {}) {
  must(typeof ownerToken === 'string' && ownerToken.length > 8 && !/\s/.test(ownerToken), 'PRIVATE_OWNER_INPUT_REQUIRED');
  return () => privateJson(new URL(`https://api.supabase.com/v1/projects/${PROJECT}/api-keys?reveal=true`),
    { Authorization: `Bearer ${ownerToken}` }, 'GET', undefined, options.requestFactory, options.timeoutMs);
}
export function selectExistingLegacyKeys(rows) {
  must(Array.isArray(rows), 'PRIVATE_PROJECT_KEYS_REQUIRED');
  const select = name => {
    const matches = rows.filter(row => row.name === name && typeof row.api_key === 'string' && row.api_key.startsWith('eyJ'));
    must(matches.length === 1, 'EXACT_EXISTING_LEGACY_KEY_REQUIRED'); return matches[0].api_key;
  };
  return { serviceRole: select('service_role'), anon: select('anon') };
}
export function createApprovedAuthAdmin(serviceRole, options = {}) {
  must(typeof serviceRole === 'string' && serviceRole.startsWith('eyJ'), 'PRIVATE_ADMIN_KEY_REQUIRED');
  const headers = { apikey: serviceRole, Authorization: `Bearer ${serviceRole}` };
  return Object.freeze({
    get(id) { must(typeof id === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id), 'EXACT_AUTH_ID_REQUIRED');
      return privateJson(new URL(`https://${PROJECT}.supabase.co/auth/v1/admin/users/${id}`), headers, 'GET', undefined,
        options.requestFactory, options.timeoutMs); },
    create(label, password) {
      must(Object.hasOwn(actorEmails,label) && typeof password === 'string' && /^[A-Za-z0-9_-]{43}$/.test(password), 'EXACT_PRIVATE_NEW_ACCOUNT_REQUIRED');
      return privateJson(new URL(`https://${PROJECT}.supabase.co/auth/v1/admin/users`), headers, 'POST',
        { email: actorEmails[label], password, email_confirm: true }, options.requestFactory, options.timeoutMs);
    }
  });
}
