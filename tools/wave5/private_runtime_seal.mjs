import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { PROJECT, BUNDLE } from './approved_management_installer.mjs';

const must = (ok, code) => { if (!ok) { const error = Error(code); error.publicCode = code; throw error; } };
export function runtimeSealKey(base64) {
  must(typeof base64 === 'string' && /^[A-Za-z0-9+/]{43}=$/.test(base64), 'PRIVATE_RUNTIME_KEY_REQUIRED');
  const bytes = Buffer.from(base64, 'base64'); must(bytes.length === 32, 'PRIVATE_RUNTIME_KEY_REQUIRED'); return bytes;
}
export async function appendRuntimeSecret(directory, key, kind, value) {
  must(Buffer.isBuffer(key) && key.length === 32 && /^[a-z][a-z0-9-]{1,60}$/.test(kind), 'PRIVATE_RUNTIME_SEAL_REQUIRED');
  must(path.isAbsolute(directory) && /^JentraOS-Wave5-owner-[a-f0-9]{32}$/.test(path.basename(directory)), 'PRIVATE_RUNTIME_DIRECTORY_REQUIRED');
  const folderStat = await fs.lstat(directory); must(folderStat.isDirectory() && !folderStat.isSymbolicLink(), 'PRIVATE_RUNTIME_DIRECTORY_REQUIRED');
  const id = crypto.randomUUID(), aad = { projectId: PROJECT, bundleSha256: BUNDLE, kind, id, revision: 1 };
  const iv = crypto.randomBytes(12), cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(Buffer.from(JSON.stringify(aad)));
  const plain = Buffer.from(JSON.stringify(value));
  let encrypted; try { encrypted = Buffer.concat([cipher.update(plain), cipher.final()]); } finally { plain.fill(0); }
  const record = { ...aad, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), ciphertext: encrypted.toString('base64') };
  const file = path.join(directory, `runtime-${kind}-${id}.sealed.json`), handle = await fs.open(file, 'wx', 0o600);
  try { await handle.writeFile(JSON.stringify(record) + '\n'); await handle.sync(); } finally { await handle.close(); }
  return path.basename(file);
}
export async function readRuntimeSecret(directory, key, filename, kind) {
  must(typeof filename === 'string' && /^runtime-[a-z][a-z0-9-]{1,60}-[a-f0-9-]{36}\.sealed\.json$/.test(filename)
    && path.basename(filename) === filename, 'EXACT_PRIVATE_RECORD_REQUIRED');
  const record = JSON.parse(await fs.readFile(path.join(directory, filename), 'utf8'));
  must(record.projectId === PROJECT && record.bundleSha256 === BUNDLE && record.kind === kind && record.revision === 1,
    'PRIVATE_RUNTIME_RECORD_BINDING_REQUIRED');
  const { projectId, bundleSha256, id, revision } = record;
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(record.iv, 'base64'));
  decipher.setAAD(Buffer.from(JSON.stringify({ projectId, bundleSha256, kind, id, revision })));
  decipher.setAuthTag(Buffer.from(record.tag, 'base64'));
  let plain; try { plain = Buffer.concat([decipher.update(Buffer.from(record.ciphertext, 'base64')), decipher.final()]);
    return JSON.parse(plain.toString('utf8')); } finally { plain?.fill(0); }
}
