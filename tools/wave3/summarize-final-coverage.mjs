import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const hash=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const root='docs/verification/remaining-wave3/';
const profile=process.argv[2]?JSON.parse(fs.readFileSync(process.argv[2],'utf8')):null;
const inputs=profile?.inputs??[['build/remaining-wave3/domain-branch-coverage-final5-20260930.info','packages/jentra_domain'],
 ['build/remaining-wave3/desktop-read-access-full-coverage-20260930.info','apps/jentra_desktop'],
 ['build/remaining-wave3/platform-read-access-full-coverage-20260930.info','packages/jentra_platform'],
 ['build/remaining-wave3/exact-form-interaction-coverage-20260930.info','apps/jentra_desktop']];
const merged=new Map();
const verifiedSources=new Map(),ignoredStale=[];
function ingest(input,base,accept=()=>true){
const file=input;
 for(const record of fs.readFileSync(file,'utf8').split('end_of_record')){
  const raw=record.match(/^SF:([^\r\n]+)/m)?.[1];if(!raw)continue;
  const file=path.relative(process.cwd(),path.isAbsolute(raw)?raw:path.resolve(base,raw)).replaceAll('\\','/');
  if(!accept(file))continue;
  const row=merged.get(file)??{lines:new Map(),branches:new Map()};
  for(const m of record.matchAll(/^DA:(\d+),(\d+)/gm))row.lines.set(m[1],(row.lines.get(m[1])??false)||+m[2]>0);
  for(const m of record.matchAll(/^BRDA:(\d+),(\d+),(\d+),([^\r\n]+)/gm)){
   const key=m.slice(1,4).join(':');row.branches.set(key,(row.branches.get(key)??false)||(m[4]!=='-'&&+m[4]>0));
  }
  merged.set(file,row);
 }
}
if(profile?.checked_inputs){
 for(const entry of profile.checked_inputs){
  const sources=new Map(JSON.parse(fs.readFileSync(entry.source_fingerprint,'utf8')).files.map(r=>[r.file,r.sha256]));
  ingest(entry.file,entry.base,file=>{
   if(!fs.existsSync(file)||sources.get(file)!==hash(file)){
    ignoredStale.push({input:entry.file,file});return false;
   }
   verifiedSources.set(file,sources.get(file));return true;
  });
 }
}else for(const [file,base] of inputs)ingest(file,base);
const domainNames=['count_partition','disposition','landed_extension','crm','lead_to_cash','quotation_workspace',
 'quotation_references','sales_order_workspace','receivables','procurement','goods_receipt','inventory_transfer',
 'stock_count_quantity','purchase_return_amount','money','exact_decimal','document_lifecycle',
 'commands','errors','pagination','permissions','tenant_context','validation','tabular_document','attachment_policy'];
const excluded=p=>/\/people\/|\/analytics\/|\/features\/assets\/|\/features\/projects\/|private_hr|payroll|workforce|sensitive_leave|work_time|work_calendar|calendar_resolution|calendar_repository|employee|supabase_leave|supabase_attendance|leave_draft|attendance_gateway|leave_gateway|jentra_people|jentra_payroll|jentra_assets|fixed_asset|assets_repository|supabase_assets|clock_import|jentra_projects|project_values|projects_repository|supabase_projects_gateway/.test(p);
const changed=fs.readFileSync(profile?.changed_paths??'build/remaining-wave3/changed-dart-paths-20260930.txt','utf8').replace(/^\uFEFF/,'').trim().split(/\r?\n/)
 .map(p=>p.replaceAll('\\','/')).filter(p=>p.includes('/lib/')&&p.endsWith('.dart')&&!excluded(p));
const selected=[...new Set([...changed,...domainNames.map(n=>'packages/jentra_domain/lib/src/'+n+'.dart')])];
const fingerprint=profile?.source_fingerprint??root+'client-sources-read-access-start-20260930.json';
const start=JSON.parse(fs.readFileSync(fingerprint,'utf8'));
const sourceMap=new Map(start.files.map(r=>[r.file,r.sha256]));
if(profile?.checked_inputs){sourceMap.clear();for(const [file,value] of verifiedSources)sourceMap.set(file,value);}
const domainFiles=new Set(domainNames.map(n=>'packages/jentra_domain/lib/src/'+n+'.dart'));
for(const prior of profile?.pure_domain_history??[]){
 const sources=new Map(JSON.parse(fs.readFileSync(prior.source_fingerprint,'utf8')).files.map(r=>[r.file,r.sha256]));
 for(const file of domainFiles)if(sources.get(file)!==hash(file))throw Error('Historical domain source changed: '+file);
 ingest(prior.file,prior.base,file=>domainFiles.has(file));
}
for(const override of profile?.source_overrides??[]){
 const files=new Set(override.files),sources=new Map(JSON.parse(fs.readFileSync(override.source_fingerprint,'utf8')).files.map(r=>[r.file,r.sha256]));
 for(const file of files){
  if(sources.get(file)!==hash(file))throw Error('Override source changed: '+file);
  merged.delete(file);sourceMap.set(file,sources.get(file));
 }
 for(const [input,base] of override.inputs)ingest(input,base,file=>files.has(file));
 for(const file of files)if(!merged.has(file))throw Error('Override source unmeasured: '+file);
}
const rows=selected.map(file=>{
 const source=fs.readFileSync(file,'utf8'),row=merged.get(file),source_sha256=hash(file);
 const declarations=source.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,'')
  .replace(/^\s*(?:library|import|export)\b[^;]*;/gm,'').trim();
 const declarationsOnly=!row&&(declarations===''||
  /^abstract interface class \w+(?: implements \w+)?\s*\{[^{}=]*\}$/.test(declarations));
 const constantDataOnly=!row&&file==='packages/jentra_platform/lib/src/wave3_observability_allowlist.dart'&&
  declarations.split(/\r?\n/).map(line=>line.trim()).filter(Boolean)
   .every(line=>/^(?:const \w+ = <String>\{|\};|'[^']*',)$/.test(line));
 return {file,source_sha256,execution_source_matches:sourceMap.get(file)===source_sha256||
   ((declarationsOnly||constantDataOnly)&&start.files.some(r=>r.file===file&&r.sha256===source_sha256)),
  changed:changed.includes(file),pure_domain:domainNames.some(n=>file==='packages/jentra_domain/lib/src/'+n+'.dart'),
  declarations_only:declarationsOnly,constant_data_only:constantDataOnly,measured:!!row,
  lines:row?.lines.size??0,lines_hit:row?[...row.lines.values()].filter(Boolean).length:0,
  branches:row?.branches.size??0,branches_hit:row?[...row.branches.values()].filter(Boolean).length:0};
});
const total=files=>{const t={files:files.length,lines:0,lines_hit:0,branches:0,branches_hit:0};
 for(const r of files)for(const k of ['lines','lines_hit','branches','branches_hit'])t[k]+=r[k];
 return {...t,line_percent:t.lines?100*t.lines_hit/t.lines:null,branch_percent:t.branches?100*t.branches_hit/t.branches:null,
  unmeasured_executable:files.filter(r=>!r.measured&&!r.declarations_only&&!r.constant_data_only).map(r=>r.file),source_mismatches:files.filter(r=>!r.execution_source_matches).map(r=>r.file)};
};
const domain=total(rows.filter(r=>r.pure_domain)),overall=total(rows.filter(r=>r.changed));
const out={generated_at:new Date().toISOString(),inputs:inputs.map(([file])=>({file,sha256:hash(file)})),
 checked_inputs:(profile?.checked_inputs??[]).map(entry=>({...entry,sha256:hash(entry.file),fingerprint_sha256:hash(entry.source_fingerprint)})),
 ignored_stale_coverage:ignoredStale,
 pure_domain_history:(profile?.pure_domain_history??[]).map(r=>({...r,sha256:hash(r.file),scope:'Only unchanged reviewed pure-domain sources are merged'})),
 source_overrides:profile?.source_overrides??[],
 source_fingerprint:fingerprint,
 boundary:'Merged executed Dart coverage with current source checks. Pure Wave 3 rules include shared command/access/decimal/lifecycle/query/export rules; concurrent Wave 4/5 files are excluded. Changed Dart denominator includes complete shared main/router/provider/shell files, conservatively including concurrent lines. SQL pgTAP assertions are separate and do not pretend to measure SQL branch coverage. Approved golden failures are retained; coverage is not visual signoff. Domain source has not changed since its full coverage run; older unrelated source coverage is not used.',
 pure_domain:domain,changed_dart:overall,files:rows,
 gates:{pure_domain_branch_90:domain.branch_percent>=90&&!domain.unmeasured_executable.length&&!domain.source_mismatches.length,
  changed_dart_line_80:overall.line_percent>=80&&!overall.unmeasured_executable.length&&!overall.source_mismatches.length}};
fs.writeFileSync(profile?.output??root+'coverage-final-reviewed-20260930.json',JSON.stringify(out,null,2)+'\n');
console.log(JSON.stringify({domain,overall,gates:out.gates},null,2));
