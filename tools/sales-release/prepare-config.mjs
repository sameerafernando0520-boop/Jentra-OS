import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const input = path.resolve(root, process.argv[2] || '.env.production.json');
const output = path.resolve(root, 'build/sales-release/public-client.json');
const raw = JSON.parse((await readFile(input, 'utf8')).replace(/^\uFEFF/, ''));
const url = raw.SUPABASE_URL;
const key = raw.SUPABASE_PUBLISHABLE_KEY;
if (url !== 'https://xpdoufauvrbdmxgngetv.supabase.co' || typeof key !== 'string') throw Error('EXPECTED_PUBLIC_PROJECT_REQUIRED');
if (!key.startsWith('sb_publishable_')) {
  const claims = JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString('utf8'));
  if (claims.role !== 'anon' || claims.ref !== 'xpdoufauvrbdmxgngetv') throw Error('PUBLIC_CLIENT_KEY_REQUIRED');
}
await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, JSON.stringify({ SUPABASE_URL: url, SUPABASE_PUBLISHABLE_KEY: key }, null, 2) + '\n');
console.log('Prepared allowlisted public client configuration for xpdoufauvrbdmxgngetv. No server or signing credentials copied.');
