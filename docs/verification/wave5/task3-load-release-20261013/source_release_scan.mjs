import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const folder = path.dirname(fileURLToPath(import.meta.url)), root = path.resolve(folder, '../../../..');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const relative = file => path.relative(root, file).replaceAll('\\', '/');
const files = [];
async function walk(directory, selector) {
  for (const entry of await fs.readdir(directory, { withFileTypes: true }).catch(() => [])) {
    if (['build', '.dart_tool', 'node_modules', '.git', 'dist'].includes(entry.name)) continue;
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await walk(file, selector);
    else if (selector(file)) files.push({ file, text: await fs.readFile(file, 'utf8') });
  }
}
for (const surface of ['apps', 'packages']) for (const name of await fs.readdir(path.join(root, surface)))
  await walk(path.join(root, surface, name, 'lib'), file => file.endsWith('.dart'));
for (const surface of ['workers', 'supabase/functions'])
  await walk(path.join(root, surface), file => /\.(ts|js|mjs)$/.test(file) && !/\.test\./.test(file));
await walk(path.join(root, 'supabase/migrations'), file => file.endsWith('.sql'));
const manifests = [path.join(root, 'pubspec.yaml')];
for (const surface of ['apps', 'packages']) for (const name of await fs.readdir(path.join(root, surface)))
  manifests.push(path.join(root, surface, name, 'pubspec.yaml'));
for (const file of manifests) { const text = await fs.readFile(file, 'utf8').catch(() => null); if (text) files.push({ file, text }); }
const frontend = files.filter(file => file.file.endsWith('.dart'));
const server = files.filter(file => !file.file.endsWith('.dart') && !file.file.endsWith('.yaml'));
const yaml = files.filter(file => file.file.endsWith('.yaml'));
const checks = [];
function scan(id, name, severity, population, pattern, candidatesOnly = false) {
  const matches = [];
  for (const file of population) {
    const expression = new RegExp(pattern.source, pattern.flags.includes('g') ? pattern.flags : pattern.flags + 'g');
    for (const match of file.text.matchAll(expression)) matches.push({ file: relative(file.file),
      line: file.text.slice(0, match.index).split('\n').length });
  }
  checks.push({ id, name, severity, status: matches.length ? (candidatesOnly ? 'MANUAL' : 'FAIL') : 'PASS',
    method: 'bounded source pattern scan; no secret values copied', candidateCount: matches.length,
    candidates: matches.slice(0, 12), limitation: matches.length && candidatesOnly ? 'Matches require semantic review and are not automatically classified as defects.'
      : 'PASS means no occurrence of the documented pattern in the recorded source population.' });
}
const manual = (id, name, severity, reason) => checks.push({ id, name, severity, status: 'MANUAL', reason });
const skip = (id, name, reason) => checks.push({ id, name, status: 'SKIP', reason });
scan('SEC-01', 'No secret credential literals in frontend code', 'critical', frontend,
  /(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|sk_live_[A-Za-z0-9]{24,}|xox[bsap]-[A-Za-z0-9-]{20,})/);
manual('SEC-02', 'Every protected route authenticates and authorizes', 'critical', 'Current exact RPC grants/actor contracts and genuine native/foreign-scope workflows remain separate; keyword presence cannot certify every route.');
manual('SEC-03', 'HTTPS enforced', 'critical', 'Exact local Pg helper enforces TLS>=1.2, chain and hostname checks; actual private Pg connection and production endpoints remain unverified.');
scan('SEC-04', 'No wildcard CORS', 'critical', server, /Access-Control-Allow-Origin[^\n]{0,60}['"]\*['"]|origin:\s*['"]\*['"]/, true);
skip('SEC-05', 'CSRF cookie protection', 'Native Windows and bearer/custom-authority worker/API scope; no cookie-authorized browser mutation endpoint identified.');
manual('SEC-06', 'All server inputs validated', 'high', 'Source-listed RPC/provider request allowlists and controlled tests exist; complete live boundary fixture acceptance is still open.');
manual('SEC-07', 'Sensitive endpoint rate limits', 'high', 'Supabase Auth limits and application quotas apply; independent genuine quota contention and production rate-policy evidence remain open.');
manual('SEC-08', 'Password storage hashing', 'critical', 'Managed Supabase Auth; no custom frontend password hash implementation is introduced. External platform assurance remains an operational check.');
manual('SEC-09', 'Auth token expiry', 'high', 'Public provider validates returned expiry online; 2,000 fresh unrevoked eligible sessions are not established.');
manual('SEC-10', 'Server logout invalidation', 'high', 'Actual native signout/revocation is owned by the Windows acceptance slice.');
skip('SEC-11', 'CSP headers', 'Native desktop; no product web deployment audited.');
scan('SEC-12', 'No alg:none JWT configuration', 'critical', server, /(?:alg|algorithm)\s*:\s*['"]none['"]/);
scan('SEC-13', 'No unsafe eval or raw HTML insertion', 'high', server, /\beval\s*\(|new\s+Function\s*\(|dangerouslySetInnerHTML/);
scan('SEC-14', 'Sensitive credential logging', 'high', [...frontend, ...server], /(?:print|debugPrint|console\.(?:log|error|info))\s*\([^\n]{0,150}(?:password|accessToken|refreshToken|serviceRoleKey)/i, true);
skip('SEC-15', 'Cookie security flags', 'No cookie-based native authority path audited.');
manual('SEC-16', 'Upload validation', 'high', 'Storage policy/type/size/path source exists; production storage configuration and actual upload acceptance are separate.');
const trackedEnv = spawnSync('git', ['ls-files', '--', '.env', '.env.*'], { cwd: root, encoding: 'utf8', windowsHide: true });
const envFiles = trackedEnv.stdout.trim().split(/\r?\n/).filter(Boolean).filter(name => name !== '.env.example');
checks.push({ id: 'SEC-17', name: 'No tracked secret env file', severity: 'critical', status: trackedEnv.status === 0 ? (envFiles.length ? 'MANUAL' : 'PASS') : 'MANUAL', filenamesOnly: envFiles });
const ignored = spawnSync('git', ['check-ignore', '-q', '.env.acceptance.json'], { cwd: root, windowsHide: true });
checks.push({ id: 'SEC-18', name: 'Private acceptance env ignored', severity: 'critical', status: ignored.status === 0 ? 'PASS' : 'FAIL' });
manual('DB-01', 'Backup configured and tested', 'critical', 'No current backup availability proof for a separately authorized production project.');
manual('DB-02', 'Isolated backup restore passed', 'critical', 'No executed and verified isolated restore drill established.');
scan('DB-03', 'Unsafe SQL interpolation in worker source', 'critical', server.filter(file => !file.file.endsWith('.sql')), /(?:SELECT|INSERT|UPDATE|DELETE)[^`\n]{0,150}\$\{/, true);
manual('DB-04', 'Separate development/production databases', 'high', 'Current project is synthetic development; separately authorized staging/production are external gates.');
manual('DB-05', 'Production connection capacity/pooling', 'high', 'Local adapter max8 is implemented/tested; server max60 is not proof of 2,000 HTTP session capacity.');
const migrationFiles = files.filter(file => file.file.endsWith('.sql'));
checks.push({ id: 'DB-06', name: 'Versioned migration source present', severity: 'high', status: migrationFiles.length ? 'PASS' : 'FAIL', sourceFileCount: migrationFiles.length,
  limitation: 'Source presence, not staging rehearsal or production migration approval.' });
checks.push({ id: 'DB-07', name: 'Product table RLS enabled', severity: 'critical', status: 'PASS', evidence: 'read-only-live-audit.json: all261 tables in recorded named product schemas have RLS enabled; scope excludes platform schemas.', limitation: 'Direct grants/policies and exposed schemas require separate semantic authorization review.' });
scan('DB-08', 'No service-role credential literal in client', 'critical', frontend, /(?:SUPABASE_SERVICE_ROLE|service_role_key)\s*[:=]\s*['"][A-Za-z0-9._-]{20,}/i);
manual('DB-09', 'No anonymous writes without scoped RLS', 'high', 'All recorded product tables have RLS enabled; privileges alone do not establish permitted rows. Exact policies/grants remain contract-bound.');
manual('DB-10', 'Production storage policies', 'high', 'Actual production buckets/policy and download/upload acceptance not supplied.');
manual('DB-11', 'Non-root app database identity', 'high', 'App uses Supabase HTTP authority; fixture/read verification credentials are private and separate from app runtime.');
manual('DB-12', 'Sensitive data encryption', 'high', 'Encrypted local drafts and private stores have controlled evidence; production encryption/keys and recovery are operational gates.');
scan('CODE-01', 'Raw console logging in worker source', 'high', server.filter(file => !file.file.endsWith('.sql')), /console\.(?:log|debug|info)\s*\(/, true);
manual('CODE-02', 'Complete async error handling', 'high', 'Pattern scan cannot certify every async path; current installed/native/recovery outcomes remain evidence-bound.');
scan('CODE-03', 'Empty catch candidates', 'high', [...frontend, ...server], /catch\s*\([^)]*\)\s*\{\s*\}/, true);
skip('CODE-04', 'React loading/error states', 'Flutter UI; no React product detected.');
manual('CODE-05', 'List endpoint bounds/pagination', 'high', 'Bounded API source exists; complete dataset boundary/recovery acceptance remains separate.');
skip('CODE-06', 'npm product audit', 'Product dependencies are Dart/Deno. The isolated pg helper has its own actual npm audit result.');
scan('CODE-07', 'Unresolved authentication/security TODO', 'critical', [...frontend, ...server], /(?:TODO|FIXME|HACK)[^\n]{0,80}(?:auth|security|permission)/i, true);
manual('CODE-08', 'Unhandled promise rejections', 'high', 'Worker and coordinator controlled tests pass; complete deployed failure handling remains separate.');
skip('CODE-09', 'React error boundaries', 'Flutter UI.');
scan('CODE-10', 'Stack traces in response candidates', 'high', server.filter(file => !file.file.endsWith('.sql')), /(?:Response|json|body)[^\n]{0,90}(?:error\.stack|stackTrace)/, true);
scan('CODE-11', 'Security lint rule suppression', 'high', server, /eslint-disable[^\n]*(?:no-eval|no-implied-eval|no-script-url)/);
const lockTracked = spawnSync('git', ['ls-files', '--error-unmatch', 'pubspec.lock'], { cwd: root, encoding: 'utf8', windowsHide: true });
checks.push({ id: 'CODE-12', name: 'Root Dart lockfile tracked', severity: 'high', status: lockTracked.status === 0 ? 'PASS' : 'FAIL' });
skip('CODE-13', 'npm wildcard versions', 'No npm application dependency manifest; isolated helper pins pg8.23.1.');
skip('CODE-14', 'TypeScript strict mode', 'Deno workers and Flutter/Dart; no TypeScript application tsconfig.');
scan('DEP-01', 'Unpinned external Dart dependencies', 'high', yaml, /^\s{2}[a-z0-9_]+:\s*(?:git:|https?:\/\/)/m, true);
manual('DEP-02', 'Typosquatting review', 'advisory', 'Lockfile exact public package identifiers recorded; package provenance/comprehensive maintainer trust is outside a regex scan.');
checks.push({ id: 'DEP-03', name: 'Lockfile preserved through advisory audit', severity: 'high', status: 'PASS', evidence: 'dart-dependency-audit.json; exact root before/after hash unchanged.' });
checks.push({ id: 'DEP-04', name: 'Known dependency vulnerabilities', severity: 'high', status: 'PASS', evidence: 'Actual OSV lookup:173 hosted Pub versions,0 known advisories. Isolated npm pg helper:14 packages,0 advisories.', limitation: 'Does not certify engine/native/path dependencies or undisclosed vulnerabilities.' });
skip('DEP-05', 'npm product postinstall scripts', 'No npm product manifest; isolated helper installation disabled scripts.');
scan('DEP-06', 'Unbounded Dart package versions', 'high', yaml, /^\s{2}[a-z0-9_]+:\s*(?:any|\*)\s*$/m);
checks.push({ id: 'DEP-07', name: 'Dependency lockfile tracked', severity: 'high', status: lockTracked.status === 0 ? 'PASS' : 'FAIL' });
manual('AI-01', 'System prompt confidentiality', 'critical', 'Numeric server-side model contract exists; actual configured provider/security acceptance remains open.');
manual('AI-02', 'Prompt injection boundaries', 'critical', 'Numeric-only/redacted source controls require actual model workflow verification; load excludes all model dispatches.');
scan('AI-03', 'No model credential literal in frontend', 'critical', frontend, /(?:OPENAI_API_KEY|ANTHROPIC_API_KEY)\s*[:=]\s*['"][A-Za-z0-9._-]{20,}/);
manual('AI-04', 'Model cost limits', 'high', 'Reviewed four-call/token caps exist; actual trusted model usage and quota/contention remain separate.');
manual('AI-05', 'Model output validation', 'high', 'Controlled contracts exist; actual provider response path unverified.');
skip('AI-06', 'Product MCP server inputs', 'No Jentra product MCP server detected.');
manual('AI-07', 'Agent authority scope', 'high', 'Source-bound human proposal/approval/execution contract; actual full native and revocation workflows remain acceptance gates.');
manual('AI-08', 'Third-party data consent', 'high', 'Only reviewed synthetic model path authorized; no real customer/payroll disclosure or production processing authorized.');
for (const [id, name, severity] of [['DEPLOY-01','Production configuration','critical'],['DEPLOY-02','Production TLS certificate','critical'],
  ['DEPLOY-05','Production rollback plan','high'],['DEPLOY-06','Staging rehearsal passed','high'],['DEPLOY-07','Zero-downtime rollout','advisory'],
  ['DEPLOY-08','Production domain/DNS','high'],['DEPLOY-09','Production health check','high'],['DEPLOY-10','Structured production logging','high'],
  ['DEPLOY-11','Monitoring destination connected','advisory'],['DEPLOY-12','Scheduled workers verified','high'],['DEPLOY-13','Static distribution/CDN','advisory']])
  manual(id, name, severity, 'Current development/source evidence is not a production configuration, rehearsal or installed operational observation; see release-audit.md.');
skip('DEPLOY-03', 'VPS firewall', 'Managed Supabase hosting; no VPS audited.'); skip('DEPLOY-04', 'VPS process manager', 'Managed Supabase hosting.');
for (const [id, name] of [['FE-01','Web metadata'],['FE-02','Web favicon'],['FE-03','Web 404'],['FE-04','Web responsive design'],
  ['FE-05','Web alt attributes'],['FE-08','Web analytics'],['FE-09','Web robots'],['FE-10','Web image optimization']]) skip(id,name,'Native Windows product scope; mobile and web releases are separate.');
manual('FE-06', 'Native keyboard/accessibility', 'high', 'Actual Windows authenticated keyboard/focus acceptance is owned by the native task.');
manual('FE-07', 'Native form feedback', 'high', 'Existing widget/golden tests support source behavior; authenticated native workflows remain separate.');
for (const [id,name] of [['OBS-01','Monitoring configured'],['OBS-02','Critical alerts delivered'],['OBS-03','Production structured logs'],
  ['OBS-04','Latency/error dashboards'],['OBS-05','Uptime monitoring'],['OBS-06','Incident response ownership'],['OBS-07','Runbooks and recovery exercises']])
  manual(id,name,'advisory','Repository operational contracts do not establish actual monitoring destinations, alert delivery, live dashboards or an executed recovery exercise.');
const byCategory = Object.fromEntries(['SEC','DB','CODE','DEP','AI','DEPLOY','FE','OBS'].map(category => [category,
  Object.fromEntries(['PASS','FAIL','MANUAL','SKIP'].map(status => [status,checks.filter(check => check.id.startsWith(category+'-') && check.status===status).length]))]));
const record = { kind: 'bounded-current-source-production-release-audit', observedAt: new Date().toISOString(),
  detectedStack: 'Flutter/Dart Windows + Supabase/PostgreSQL + Deno/Node workers',
  skill: 'Performance Profiler + Ship Gate, applicable checks/patterns adapted to native stack',
  categoryOrder: Object.keys(byCategory), byCategory, checks,
  sourcePopulation: files.map(file => ({ path:relative(file.file),bytes:Buffer.byteLength(file.text),sha256:hash(file.text) })),
  productionReleaseReady: false, verdict: 'DO NOT RELEASE: required operational, genuine-load, native and signed-distribution evidence remains incomplete.',
  noPrivateCredentialsRead: true, liveWrites:0, SDKJobs:0,
  limitation:'Bounded source scan, exact dependency advisory lookup and linked read-only live observations. Manual/semantic checks are not promoted to pass by regex absence.' };
const bytes = JSON.stringify(record,null,2)+'\n', handle = await fs.open(path.join(folder,'source-release-checks.json'),'wx');
try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
console.log(JSON.stringify({path:'source-release-checks.json',sha256:hash(bytes),sourceFiles:files.length,checkCount:checks.length,byCategory}));
