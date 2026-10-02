import fs from 'node:fs';
import crypto from 'node:crypto';
const base='docs/verification/remaining-wave3/';
const queryPath=process.argv[2]??'build/remaining-wave3/final-procurement-20260930.sql';
const outputPath=process.argv[3]??base+'migration-order-20260930.json';
const expectedCount=Number(process.argv[4]??44);
const schemaBeforePath=process.argv[5]??base+'schema-before-20260930.json';
const schemaAfterPath=process.argv[6]??base+'schema-after-20260930.json';
const query=fs.readFileSync(queryPath,'utf8');
const prefix=query.slice(0,query.indexOf('create extension if not exists pgtap'));
if(!prefix || !query.includes('finish(true)') || !/rollback;\s*$/.test(query))throw Error('Only a verified rollback builder output is accepted.');
const ledger=JSON.parse(fs.readFileSync(base+'installed-ledger-final-20260930.json','utf8').replace(/^\uFEFF/,'')).migrations;
const installed=new Set(ledger.map(m=>m.version));
const found=[];
for(const file of fs.readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql'))){
  const path='supabase/migrations/'+file,body=fs.readFileSync(path,'utf8');
  const offset=prefix.indexOf(body);
  if(offset>=0)found.push({path,version:file.split('_')[0],offset,sha256:crypto.createHash('sha256').update(body).digest('hex'),
    installed:installed.has(file.split('_')[0])});
}
found.sort((a,b)=>a.offset-b.offset);
if(found.length!==expectedCount || found.some(r=>r.installed))throw Error('Candidate order needs review: '+JSON.stringify({count:found.length,installed:found.filter(r=>r.installed)}));
const schemaBefore=JSON.parse(fs.readFileSync(schemaBeforePath,'utf8'));
const schemaAfter=JSON.parse(fs.readFileSync(schemaAfterPath,'utf8'));
const removedFunctions=Object.keys(schemaBefore.functions).filter(k=>!schemaAfter.functions[k]);
const changedReturnTypes=Object.keys(schemaBefore.functions).filter(k=>schemaAfter.functions[k] && schemaBefore.functions[k].return_type!==schemaAfter.functions[k].return_type);
const changedGrants=Object.keys(schemaBefore.functions).filter(k=>schemaAfter.functions[k] && schemaBefore.functions[k].acl!==schemaAfter.functions[k].acl);
const modifiedFunctions=Object.keys(schemaBefore.functions).filter(k=>schemaAfter.functions[k] && schemaBefore.functions[k].source_md5!==schemaAfter.functions[k].source_md5);
const removedViews=Object.keys(schemaBefore.views).filter(k=>!schemaAfter.views[k]);
const out={generated_on:'2026-09-30',project_id:'xpdoufauvrbdmxgngetv',head:'f9cc342815e2446fb3f26204d5e65e03c1b2a140',
 installed_count:ledger.length,latest_installed:ledger.at(-1),candidate_count:found.length,
 boundary:'Dependency order observed from the complete passing candidate composition. None installed. Approval, data preflight and independent-session/native acceptance remain separate.',
 query_sha256:crypto.createHash('sha256').update(query).digest('hex'),schemaBeforePath,schemaAfterPath,removedFunctions,changedReturnTypes,changedGrants,modifiedFunctions,removedViews,
 candidates:found.map(({offset,...r},i)=>({...r,ordinal:i+1,requires_previous_candidates:true}))};
fs.writeFileSync(outputPath,JSON.stringify(out,null,2)+'\n');
console.log(JSON.stringify({candidates:out.candidate_count,removedFunctions,changedReturnTypes,changedGrants,removedViews}));

