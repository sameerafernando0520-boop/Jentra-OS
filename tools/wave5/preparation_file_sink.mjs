import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { PROJECT_ID, GuardError, requireGuard, isSha, isUuid, hashBytes, hashJson, immutableJson } from './runtime_contract.mjs';

// No import/constructor I/O. A new private directory and privately supplied key
// are mandatory. Recovery is read-only and never dispatches or restores a job.
const WORKSPACE = path.resolve(fileURLToPath(new URL('../../', import.meta.url))),
  MAX_RECORD_BYTES = 8 * 1024 * 1024 + 1, MAX_FILE_BYTES = 16 * 1024 * 1024, MAX_RECORDS = 1024,
  KIND = 'wave5-encrypted-private-preparation-file', RECORD_KIND = 'wave5-private-preparation-journal-record',
  FILE = /^([0-9]{8})-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.w5prep$/,
  FIELDS = ['kind', 'version', 'projectId', 'runtimeBundleSha256', 'planBodySha256', 'sourceSha256', 'sequence', 'recordId',
    'previousStorageSha256', 'recordSha256', 'nonce', 'tag', 'ciphertext'];
const failure = () => new GuardError('EVIDENCE_WRITE_FAILED');
const samePath = (left, right) => process.platform === 'win32'
  ? path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase() : path.resolve(left) === path.resolve(right);
const sameNode = (left, right) => left.dev === right.dev && left.ino === right.ino;

function privateInput({ directory, encryptionKey, expectedBinding, expectedHead }) {
  requireGuard(typeof directory === 'string' && path.isAbsolute(directory)
    && /^jentra-w5-preparation-[0-9a-f-]{36}$/.test(path.basename(directory))
    && isUuid(path.basename(directory).slice('jentra-w5-preparation-'.length))
    && encryptionKey instanceof Uint8Array && encryptionKey.byteLength === 32
    && expectedBinding?.projectId === PROJECT_ID
    && ['runtimeBundleSha256', 'planBodySha256', 'sourceSha256'].every(name => isSha(expectedBinding[name])), 'REVIEWED_PREPARATION_REQUIRED');
  const relative = path.relative(WORKSPACE, path.resolve(directory));
  requireGuard(relative !== '' && (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)), 'REVIEWED_PREPARATION_REQUIRED');
  requireGuard(expectedHead === undefined || (expectedHead && Number.isSafeInteger(expectedHead.recordCount)
    && expectedHead.recordCount >= 1 && expectedHead.recordCount <= MAX_RECORDS && isSha(expectedHead.storageEvidenceSha256)),
  'REVIEWED_PREPARATION_REQUIRED');
  return { directory: path.resolve(directory), key: Buffer.from(encryptionKey),
    expectedHead: expectedHead === undefined ? null : immutableJson({ recordCount: expectedHead.recordCount,
      storageEvidenceSha256: expectedHead.storageEvidenceSha256 }),
    binding: immutableJson(Object.fromEntries(['projectId', 'runtimeBundleSha256', 'planBodySha256', 'sourceSha256']
      .map(name => [name, expectedBinding[name]]))) };
}
function bound(value, binding) { return Object.entries(binding).every(([name, expected]) => value[name] === expected); }
function validRecord(value, binding) {
  requireGuard(value?.kind === RECORD_KIND && bound(value, binding) && Number.isSafeInteger(value.sequence)
    && value.sequence >= 1 && value.sequence <= MAX_RECORDS && isUuid(value.recordId) && isUuid(value.caseId)
    && ['runtime', 'load-001'].includes(value.scopeKey) && ['checkpoint', 'intent', 'confirmed', 'uncertain'].includes(value.phase)
    && typeof value.action === 'string' && /^[a-z][a-z0-9-]{0,95}$/.test(value.action)
    && typeof value.observedAt === 'string' && new Date(value.observedAt).toISOString() === value.observedAt
    && (value.operationId === undefined || isUuid(value.operationId)) && Object.hasOwn(value, 'details'), 'EVIDENCE_WRITE_FAILED');
  requireGuard(Buffer.byteLength(JSON.stringify(value)) <= MAX_RECORD_BYTES, 'EVIDENCE_WRITE_FAILED');
}
const header = value => Object.fromEntries(FIELDS.slice(0, -3).map(name => [name, value[name]]));
const b64 = (value, length) => {
  requireGuard(typeof value === 'string' && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value), 'EVIDENCE_WRITE_FAILED');
  const bytes = Buffer.from(value, 'base64');
  requireGuard(bytes.toString('base64') === value && (length === undefined || bytes.length === length), 'EVIDENCE_WRITE_FAILED'); return bytes;
};
async function exactDirectory(directory, expected = null) {
  const stat = await fs.lstat(directory);
  requireGuard(stat.isDirectory() && !stat.isSymbolicLink() && samePath(await fs.realpath(directory), directory)
    && (!expected || sameNode(stat, expected)), 'EVIDENCE_WRITE_FAILED'); return stat;
}
async function readExactFile(filename) {
  const prior = await fs.lstat(filename);
  requireGuard(prior.isFile() && !prior.isSymbolicLink() && prior.nlink === 1 && prior.size > 0 && prior.size <= MAX_FILE_BYTES, 'EVIDENCE_WRITE_FAILED');
  const handle = await fs.open(filename, 'r');
  try {
    requireGuard(sameNode(await handle.stat(), prior), 'EVIDENCE_WRITE_FAILED');
    const buffer = Buffer.alloc(prior.size + 1); let position = 0;
    while (position < buffer.length) {
      const result = await handle.read(buffer, position, buffer.length - position, position);
      if (result.bytesRead === 0) break; position += result.bytesRead;
    }
    const actual = await handle.stat(), latest = await fs.lstat(filename);
    requireGuard(position === prior.size && actual.size === prior.size && sameNode(actual, latest)
      && latest.isFile() && !latest.isSymbolicLink() && latest.nlink === 1, 'EVIDENCE_WRITE_FAILED'); return buffer.subarray(0, position);
  } finally { await handle.close(); }
}

export function createEncryptedPreparationFileSink(config) {
  requireGuard(config?.expectedHead === undefined, 'REVIEWED_PREPARATION_REQUIRED');
  const { directory, key, binding } = privateInput(config);
  let tail = Promise.resolve(), created = false, originalDirectory = null, sequence = 0, previousStorageSha256 = null,
    blocked = false, closed = false, closing;
  async function store(value) {
    requireGuard(!blocked && value.sequence === sequence + 1, 'EVIDENCE_WRITE_FAILED');
    if (!created) {
      // Exclusive creation refuses all existing directories, partial attempts or
      // symlinks. Never choose a replacement path or overwrite an original.
      await exactDirectory(path.dirname(directory)); await fs.mkdir(directory, { mode: 0o700 });
      originalDirectory = await exactDirectory(directory); created = true;
    } else await exactDirectory(directory, originalDirectory);
    const original = JSON.stringify(value), nonce = crypto.randomBytes(12), envelope = { kind: KIND, version: 1, ...binding,
      sequence: value.sequence, recordId: value.recordId, previousStorageSha256, recordSha256: hashBytes(original) };
    const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
    cipher.setAAD(Buffer.from(JSON.stringify(header(envelope))));
    const encrypted = Buffer.concat([cipher.update(original, 'utf8'), cipher.final()]);
    const bytes = Buffer.from(JSON.stringify({ ...envelope, nonce: nonce.toString('base64'), tag: cipher.getAuthTag().toString('base64'),
      ciphertext: encrypted.toString('base64') }) + '\n');
    requireGuard(bytes.length <= MAX_FILE_BYTES, 'EVIDENCE_WRITE_FAILED');
    const filename = path.join(directory, `${String(value.sequence).padStart(8, '0')}-${value.recordId.toLowerCase()}.w5prep`),
      handle = await fs.open(filename, 'wx', 0o600);
    try {
      await handle.writeFile(bytes); await handle.sync();
      const actual = await handle.stat(), named = await fs.lstat(filename);
      requireGuard(actual.size === bytes.length && named.isFile() && !named.isSymbolicLink() && named.nlink === 1 && sameNode(actual, named), 'EVIDENCE_WRITE_FAILED');
      await exactDirectory(directory, originalDirectory);
    } finally { await handle.close(); }
    // `durable` acknowledges the actual file-content sync above. Directory-entry
    // fsync/power-loss guarantees on the configured Windows filesystem are not
    // supplied by this acknowledgement and remain a separate preparation proof.
    sequence = value.sequence; previousStorageSha256 = hashBytes(bytes);
    return Object.freeze({ durable: true, appendOnly: true, recordSha256: hashJson(value), storageEvidenceSha256: previousStorageSha256 });
  }
  return Object.freeze({ kind: 'wave5-encrypted-private-preparation-sink',
    async appendPreparationEvidence(record) {
      try {
        requireGuard(!closed && !blocked, 'EVIDENCE_WRITE_FAILED');
        const value = immutableJson(record); validRecord(value, binding);
        const result = tail.then(() => store(value)); tail = result.catch(() => { blocked = true; });
        return await result;
      } catch { blocked = true; throw failure(); }
    },
    async close() {
      closed = true; closing ??= tail.finally(() => key.fill(0)); await closing;
    } });
}

export async function readEncryptedPreparationRecords(config) {
  let key;
  try {
    const input = privateInput(config); key = input.key; const { directory, binding, expectedHead } = input;
    const originalDirectory = await exactDirectory(directory), files = (await fs.readdir(directory)).sort();
    requireGuard(files.length > 0 && files.length <= MAX_RECORDS && files.every(name => FILE.test(name)), 'EVIDENCE_WRITE_FAILED');
    const records = []; let previousStorageSha256 = null;
    for (const [index, filename] of files.entries()) {
      const match = FILE.exec(filename); requireGuard(Number(match[1]) === index + 1, 'EVIDENCE_WRITE_FAILED');
      await exactDirectory(directory, originalDirectory);
      const bytes = await readExactFile(path.join(directory, filename)), envelope = JSON.parse(bytes.toString('utf8'));
      requireGuard(Object.keys(envelope).length === FIELDS.length && FIELDS.every(name => Object.hasOwn(envelope, name))
        && envelope.kind === KIND && envelope.version === 1 && bound(envelope, binding)
        && envelope.sequence === index + 1 && envelope.recordId.toLowerCase() === match[2]
        && isUuid(envelope.recordId) && isSha(envelope.recordSha256) && envelope.previousStorageSha256 === previousStorageSha256,
      'EVIDENCE_WRITE_FAILED');
      const encrypted = b64(envelope.ciphertext); requireGuard(encrypted.length > 0 && encrypted.length <= MAX_RECORD_BYTES, 'EVIDENCE_WRITE_FAILED');
      const decipher = crypto.createDecipheriv('aes-256-gcm', key, b64(envelope.nonce, 12));
      decipher.setAAD(Buffer.from(JSON.stringify(header(envelope)))); decipher.setAuthTag(b64(envelope.tag, 16));
      const original = Buffer.concat([decipher.update(encrypted), decipher.final()]);
      requireGuard(hashBytes(original) === envelope.recordSha256, 'EVIDENCE_WRITE_FAILED');
      const record = JSON.parse(original.toString('utf8')); validRecord(record, binding);
      requireGuard(record.sequence === envelope.sequence && record.recordId === envelope.recordId && hashJson(record) === envelope.recordSha256,
        'EVIDENCE_WRITE_FAILED'); records.push(record); previousStorageSha256 = hashBytes(bytes);
    }
    await exactDirectory(directory, originalDirectory);
    // Without an independently retained head, loss of the last whole file is
    // undetectable locally. A valid available prefix is never a complete result.
    if (expectedHead) requireGuard(records.length === expectedHead.recordCount
      && previousStorageSha256 === expectedHead.storageEvidenceSha256, 'EVIDENCE_WRITE_FAILED');
    return immutableJson({ records, availableRecordCount: records.length, availableHeadSha256: previousStorageSha256,
      completenessVerified: expectedHead !== null, automaticReplayAllowed: false });
  } catch { throw failure(); } finally { key?.fill(0); }
}
