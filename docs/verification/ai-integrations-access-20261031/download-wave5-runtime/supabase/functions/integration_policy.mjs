import { createHmac, createHash, timingSafeEqual } from 'node:crypto';
import {Buffer} from 'node:buffer';
import { isIP } from 'node:net';
import https from 'node:https';
import {waitForSignal} from './bounded_json.mjs';

const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const hash = /^[0-9a-f]{64}$/;
function requireValue(condition, code = 'VALIDATION_ERROR') {
  if (!condition) throw new Error(code);
}
function v4Number(address) {
  requireValue(isIP(address) === 4);
  return address.split('.').reduce((n, octet) => (n << 8n) + BigInt(octet), 0n);
}
function v6Number(address) {
  requireValue(isIP(address) === 6 && !address.includes('.') && !address.includes('%'));
  const [left, right] = address.toLowerCase().split('::');
  const a = left ? left.split(':') : [], b = right ? right.split(':') : [];
  const parts = right !== undefined ? [...a, ...Array(8 - a.length - b.length).fill('0'), ...b] : a;
  requireValue(parts.length === 8);
  return parts.reduce((n, part) => (n << 16n) + BigInt(`0x${part}`), 0n);
}
function inside(value, network, prefix, width) {
  const shift = BigInt(width - prefix);
  return (value >> shift) === (network >> shift);
}
// Conservative special-purpose exclusions, reviewed against the IANA registries
// on 2026-10-06. Protocol exceptions and translation prefixes are unsupported.
const denied4 = [
  ['0.0.0.0', 8], ['10.0.0.0', 8], ['100.64.0.0', 10], ['127.0.0.0', 8],
  ['169.254.0.0', 16], ['172.16.0.0', 12], ['192.0.0.0', 24], ['192.0.2.0', 24],
  ['192.88.99.0', 24], ['192.168.0.0', 16], ['198.18.0.0', 15], ['198.51.100.0', 24],
  ['203.0.113.0', 24], ['224.0.0.0', 4], ['240.0.0.0', 4],
].map(([network, prefix]) => [v4Number(network), prefix]);
const denied6 = [['2001::', 23], ['2001:db8::', 32], ['2002::', 16], ['3fff::', 20]]
  .map(([network, prefix]) => [v6Number(network), prefix]);
export function permittedAddress(address) {
  try {
    if (isIP(address) === 4) {
      const n = v4Number(address);
      return !denied4.some(([network, prefix]) => inside(n, network, prefix, 32));
    }
    if (isIP(address) === 6) {
      const n = v6Number(address);
      return inside(n, v6Number('2000::'), 3, 128) &&
        !denied6.some(([network, prefix]) => inside(n, network, prefix, 128));
    }
  } catch { return false; }
  return false;
}
export async function resolveDestination(input, allowedHosts, resolve) {
  const url = new URL(input);
  requireValue(url.protocol === 'https:' && (!url.port || url.port === '443') &&
    !url.username && !url.password && !url.hash && url.href.length <= 2048 &&
    allowedHosts.has(url.hostname) && !isIP(url.hostname) && !url.hostname.endsWith('.'), 'UNSAFE_DESTINATION');
  const addresses = await resolve(url.hostname);
  requireValue(Array.isArray(addresses) && addresses.length > 0 && addresses.length <= 32 &&
    addresses.every(a => typeof a === 'string' && permittedAddress(a)), 'UNSAFE_DESTINATION');
  return Object.freeze({ url: url.href, hostname: url.hostname, address: addresses[0], family: isIP(addresses[0]) });
}
function sameScope(a, b) {
  return ['tenantId', 'legalEntityId', 'branchId'].every(k => a[k] === b[k]);
}
function validScope(s) {
  return s && Object.keys(s).length === 3 && uuid.test(s.tenantId) && uuid.test(s.legalEntityId) &&
    (s.branchId === null || uuid.test(s.branchId));
}
export function forecastEvent(event, subscriptionScope) {
  requireValue(event && Object.keys(event).length === 8 && uuid.test(event.eventId) && validScope({tenantId:event.tenantId,legalEntityId:event.legalEntityId,branchId:event.branchId}) &&
    sameScope(event, subscriptionScope) && event.type === 'analytics.forecast.frozen.v1' &&
    uuid.test(event.forecastId) && event.definitionVersion === 1 && hash.test(event.sourceHash), 'EVENT_CONTRACT_MISMATCH');
  return Buffer.from(JSON.stringify({
    eventId: event.eventId, type: event.type, tenantId: event.tenantId,
    legalEntityId: event.legalEntityId, branchId: event.branchId,
    forecastId: event.forecastId, definitionVersion: 1, sourceHash: event.sourceHash,
  }), 'utf8');
}
export function signDelivery({ payload, eventId, timestamp, key, keyVersion }) {
  requireValue(Buffer.isBuffer(payload) && payload.length <= 8192 && uuid.test(eventId) &&
    Number.isSafeInteger(timestamp) && timestamp > 0 && Number.isSafeInteger(keyVersion) && keyVersion > 0 &&
    Buffer.isBuffer(key) && key.length >= 32 && key.length <= 128);
  const prefix = Buffer.from(`${timestamp}.${eventId}.`, 'utf8');
  return `v${keyVersion}=${createHmac('sha256', key).update(prefix).update(payload).digest('hex')}`;
}
export function attemptOutcome(eventId, subscriptionId, attempt, status) {
  requireValue(uuid.test(eventId) && uuid.test(subscriptionId) && Number.isInteger(attempt) && attempt >= 1 && attempt <= 8 &&
    (status === null || (Number.isInteger(status) && status >= 100 && status <= 599)));
  const success = status !== null && status >= 200 && status < 300;
  // A timeout cannot establish whether the consumer accepted the bytes. Keep
  // that state separate so a scheduler cannot silently retry an unknown send.
  return Object.freeze({ eventId, subscriptionId, attempt, httpStatus:status, state: status === null ? 'unknown' : success ? 'acknowledged' : attempt === 8 ? 'dead_letter' : 'retry',
    retryAfterSeconds: status === null || success || attempt === 8 ? null : Math.min(3600, 15 * 2 ** (attempt - 1)) });
}

/** No redirects or proxy; TLS validates the original hostname while DNS is pinned. */
export async function pinnedHttpsPost(destination, payload, headers, signal) {
  requireValue(permittedAddress(destination.address) && isIP(destination.address) === destination.family &&
    Buffer.isBuffer(payload) && payload.length <= 8192, 'UNSAFE_DESTINATION');
  const url = new URL(destination.url);
  requireValue(url.protocol === 'https:' && url.hostname === destination.hostname && (!url.port || url.port === '443') &&
    !url.username && !url.password && !url.hash, 'UNSAFE_DESTINATION');
  return new Promise((resolve, reject) => {
    const req = https.request({
      protocol: 'https:', hostname: destination.hostname, port: 443,
      path: url.pathname + url.search, method: 'POST', agent: false,
      servername: destination.hostname, rejectUnauthorized: true,
      signal,
      headers: { ...headers, host: destination.hostname, 'content-type': 'application/json', 'content-length': payload.length },
      lookup: (_hostname, options, callback) => options?.all
        ? callback(null, [{ address: destination.address, family: destination.family }])
        : callback(null, destination.address, destination.family),
    }, response => {
      // Node https.request does not follow redirects. Only the status is kept.
      let size = 0;
      response.on('data', chunk => { size += chunk.length; if (size > 65536) req.destroy(new Error('RESPONSE_LIMIT')); });
      response.on('end', () => resolve(response.statusCode));
      response.on('error', () => reject(new Error('DELIVERY_OUTCOME_UNKNOWN')));
    });
    const timeout = setTimeout(() => req.destroy(new Error('DELIVERY_OUTCOME_UNKNOWN')), 10000);
    req.on('close', () => clearTimeout(timeout));
    req.on('error', () => reject(new Error('DELIVERY_OUTCOME_UNKNOWN')));
    req.end(payload);
  });
}

/** Injected authority reads committed events and server-held subscription/key versions. */
export async function deliverForecast({ event, subscription, attempt, timestamp, key, authorizeCommittedEvent, resolve, post = pinnedHttpsPost, signal }) {
  if(signal?.aborted)throw Error('WORKER_REQUEST_TIMEOUT');
  requireValue(subscription && validScope(subscription.scope) && uuid.test(subscription.id) && subscription.enabled === true);
  const payload = forecastEvent(event, subscription.scope);
  // An exhausted or invalid attempt must fail before any DNS or network work.
  attemptOutcome(event.eventId, subscription.id, attempt, null);
  const signature = signDelivery({ payload, eventId: event.eventId, timestamp, key, keyVersion: subscription.keyVersion });
  await waitForSignal(authorizeCommittedEvent(event, subscription),signal); // trusted live source/outbox/entitlement check
  const destination = await waitForSignal(resolveDestination(subscription.url, new Set(subscription.allowedHosts), resolve),signal);
  // Revalidate authority after asynchronous DNS; revoked subscriptions cannot send.
  await waitForSignal(authorizeCommittedEvent(event, subscription),signal);
  let status = null;
  try { status = await waitForSignal(post(destination, payload, { 'x-jentra-signature': signature, 'x-jentra-event-id': event.eventId, 'x-jentra-timestamp': `${timestamp}` },signal),signal); }
  catch { /* Retain an uncertain attempt; no secret or remote diagnostic reaches logs. */ }
  return attemptOutcome(event.eventId, subscription.id, attempt, status);
}

export function validateIntegrationIdentity({ token, credential, scope, commandCode, now, liveEntitlement, schemaVersion }) {
  requireValue(typeof token === 'string' && token.length >= 32 && token.length <= 256 && credential &&
    hash.test(credential.tokenHash) && validScope(scope) && validScope(credential.scope) && sameScope(scope, credential.scope) && credential.revokedAt === null &&
    Number.isSafeInteger(now) && Number.isSafeInteger(credential.startsAt) && Number.isSafeInteger(credential.expiresAt) &&
    credential.expiresAt > credential.startsAt && now >= credential.startsAt && now < credential.expiresAt &&
    commandCode === 'analytics.freeze_pipeline.v1' && Array.isArray(credential.commands) &&
    credential.commands.includes(commandCode) && schemaVersion === 1 &&
    liveEntitlement === true, 'INTEGRATION_ACCESS_DENIED');
  const actual = createHash('sha256').update(token, 'utf8').digest(), expected = Buffer.from(credential.tokenHash, 'hex');
  requireValue(timingSafeEqual(actual, expected), 'INTEGRATION_ACCESS_DENIED');
}
export function validateIntegrationCredential(options) {
  validateIntegrationIdentity(options);
  requireValue(options.quotaReserved === true && options.throttleReserved === true,'INTEGRATION_ACCESS_DENIED');
}
