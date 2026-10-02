import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const inputs=[
 ['build/remaining-wave3/domain-branch-coverage-final5-20260930.info','packages/jentra_domain'],
 ['build/remaining-wave3/platform-branch-coverage-20260930.info','packages/jentra_platform'],
 ['build/remaining-wave3/desktop-branch-coverage-20260930.info','apps/jentra_desktop']];
const merged=new Map();
for(const [file,base] of inputs){
 const lcov=fs.readFileSync(file,'utf8');
 for(const record of lcov.split('end_of_record')){
  const raw=record.match(/^SF:(.+)/m)?.[1];if(!raw)continue;
  const absolute=path.isAbsolute(raw)?raw:path.resolve(base,raw);
  const filePath=path.relative(process.cwd(),absolute).replaceAll('\\','/');
  // The quotation source changed after the Flutter coverage runs. Domain
  // coverage is freshly executed; older cross-package line IDs cannot be merged.
  if(base!=='packages/jentra_domain' && filePath.startsWith('packages/jentra_domain/'))continue;
  const row=merged.get(filePath)??{lines:new Map(),branches:new Map()};
  for(const m of record.matchAll(/^DA:(\d+),(\d+)/gm))row.lines.set(m[1],(row.lines.get(m[1])??false)||+m[2]>0);
  for(const m of record.matchAll(/^BRDA:(\d+),(\d+),(\d+),([^\r\n]+)/gm)){
   const key=m.slice(1,4).join(':');row.branches.set(key,(row.branches.get(key)??false)||(m[4]!=='-'&&+m[4]>0));
  }
  merged.set(filePath,row);
 }
}
const rows=[...merged.entries()].map(([file,row])=>({file,source_sha256:fs.existsSync(file)?crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'):null,
 lines:row.lines.size,lines_hit:[...row.lines.values()].filter(Boolean).length,branches:row.branches.size,branches_hit:[...row.branches.values()].filter(Boolean).length}));
for(const row of rows){row.line_percent=row.lines?100*row.lines_hit/row.lines:null;row.branch_percent=row.branches?100*row.branches_hit/row.branches:null;}
const names=['count_partition','disposition','landed_extension','crm','lead_to_cash','quotation_workspace','sales_order_workspace','receivables','procurement','goods_receipt','inventory_transfer','stock_count_quantity','purchase_return_amount','money','exact_decimal','document_lifecycle'];
const wave3=rows.filter(r=>r.file.startsWith('packages/jentra_domain/lib/src/')&&names.some(n=>r.file.endsWith('/'+n+'.dart')));
const out={generated_on:'2026-09-30',inputs:inputs.map(([file])=>({file,sha256:crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')})),
 boundary:'Fresh domain coverage only for domain files; older Flutter domain line IDs are excluded after quotation edits. Platform/desktop coverage retains its execution-time source boundary and approved golden failures. Recorded source hashes identify current reviewed files, not a retroactive execution fingerprint for older Flutter reports. Concurrent Wave 4 files are excluded from the Wave 3 domain subset. Whole changed-code 80% gate is not inferred from this subset.',
 wave3_domain:wave3,totals:{branches:wave3.reduce((s,r)=>s+r.branches,0),branches_hit:wave3.reduce((s,r)=>s+r.branches_hit,0)},files:rows};
out.totals.branch_percent=100*out.totals.branches_hit/out.totals.branches;
fs.writeFileSync('docs/verification/remaining-wave3/coverage-20260930.json',JSON.stringify(out,null,2)+'\n');
console.log(JSON.stringify({totals:out.totals,wave3_domain:wave3.map(({file,branch_percent})=>({file,branch_percent}))},null,2));
