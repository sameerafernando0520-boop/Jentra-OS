import fs from 'node:fs';
import crypto from 'node:crypto';
const root='docs/verification/remaining-wave3/';
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const spec='docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md';
const order=read(root+'migration-order-final-20260930-45.json');
const refreshPath=process.argv[2]??root+'refresh-final-current-20261001.json';
const outputPath=process.argv[3]??root+'source-ledger-final-current-20261001.json';
if(!refreshPath.startsWith(root)||!outputPath.startsWith(root)||!outputPath.endsWith('.json'))throw Error('Use task-owned evidence paths');
const refresh=read(refreshPath);
const protectedRows=read(root+'protected-source-opening-20260928.json').map(r=>({...r,current_sha256:hash(r.path),matches:hash(r.path).toLowerCase()===r.sha256.toLowerCase()}));
const candidates=order.candidates.map(c=>({...c,current_sha256:hash(c.path),matches:hash(c.path)===c.sha256,unapplied:!refresh.migrations.some(m=>c.path.includes(m.version+'_'))}));
const expected={flow_residual:'c0933ed943663701bbc7e01a1c21831f',wave3_lock_open_period:'a316c04eef62ba1a43d49ea4d5261ca2',flow_post_journal:'bebe95827a7e5ac3f2192d0f7acd38b4',flow_allocate:'e6e9f68ec7d8aca03be157816fe8eef6'};
const helpers=refresh.shared_helpers.map(h=>({...h,matches:h.source_md5===expected[h.name]}));
const evidence={observed_at:new Date().toISOString(),head:order.head,refresh_path:refreshPath,refresh_sha256:hash(refreshPath),spec_sha256:hash(spec),
 boundary:'Fresh read-only source and catalogue comparison. Protected concurrent-file drift is reported separately; no source reset, installed migration, native acceptance or owner signoff.',
 installed:refresh.migrations.length,api_functions:refresh.api_catalogue.length,protected_files:protectedRows,candidates,helpers};
fs.writeFileSync(outputPath,JSON.stringify(evidence,null,2)+'\n');
const failures=[];
if(evidence.spec_sha256!=='a5b6b788a21f51d1267f9148c1196d06e3dd37cc8fddff2b0a9e55c097e92454')failures.push('approved spec drift');
if(candidates.length!==45||candidates.some(c=>!c.matches||!c.unapplied))failures.push('candidate source/install drift');
if(helpers.length!==4||helpers.some(h=>!h.matches))failures.push('shared helper drift');
if(protectedRows.some(r=>!r.matches&&/stock.?opening|\/goldens\//i.test(r.path)))failures.push('acceptance/golden source drift');
console.log(JSON.stringify({candidates:candidates.length,unapplied:candidates.filter(c=>c.unapplied).length,protected_original_matches:protectedRows.filter(r=>r.matches).length,protected_total:protectedRows.length,protected_drift:protectedRows.filter(r=>!r.matches).map(r=>r.path),failures}));
if(failures.length)process.exitCode=1;

