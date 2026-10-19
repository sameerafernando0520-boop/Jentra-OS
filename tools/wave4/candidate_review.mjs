import fs from 'node:fs';
import crypto from 'node:crypto';

const hash=text=>crypto.createHash('sha256').update(text).digest('hex');
const base='docs/verification/wave4/';
const suites={
 projects:['20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql','20261001080000_wave4_projects_time.sql'],
 project_finance:['20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql','20261001080000_wave4_projects_time.sql','20261001100000_wave4_project_expenses_billing.sql'],
 service:['20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql','20261001090000_wave4_service.sql'],
 payroll_corrections:['20260926160000_wave4_calendar_resolution.sql','20260926161000_wave4_organization.sql','20260928082234_wave4_attendance_intervals.sql','20260928083449_wave4_leave_ledger.sql','20260930070000_wave4_synthetic_payroll.sql','20261001110000_wave4_payroll_corrections.sql'],
 assets:['20260930071000_wave4_fixed_assets.sql']
};
const read=p=>fs.readFileSync(p,'utf8');
const sampleTables={projects:['project_assertions','project_client_samples','label','body'],project_finance:['project_assertions','project_finance_client_samples','label','body'],service:['service_assertions','service_samples','name','body'],payroll_corrections:['payroll_assertions','correction_client_samples','name','response'],assets:['asset_assertions','asset_client_samples','label','body']};
const snapshot=`select jsonb_build_object('functions',coalesce((select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('result',pg_get_function_result(p.oid),'source_md5',md5(pg_get_functiondef(p.oid)),'grants',p.proacl::text)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('api','core','people','workforce','projects','service','payroll','assets','finance','inventory','procurement','sales','workflow')),'{}'),'tables',coalesce((select jsonb_object_agg(n.nspname||'.'||c.relname,jsonb_build_object('forced_rls',c.relforcerowsecurity,'rls',c.relrowsecurity,'grants',c.relacl::text,'columns',(select jsonb_object_agg(a.attname,jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'nullable',not a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))) from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),'constraints',(select coalesce(jsonb_agg(pg_get_constraintdef(k.oid) order by k.conname),'[]') from pg_constraint k where k.conrelid=c.oid))) from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in('r','p') and n.nspname in('core','people','workforce','projects','service','payroll','assets','finance','inventory','procurement','sales','workflow')),'{}')) catalog`;
if(process.argv.includes('--read')){
 const i=process.argv.indexOf('--read'),name=process.argv[i+1],offset=Number(process.argv[i+2]);
 if(!Object.hasOwn(suites,name)||!Number.isSafeInteger(offset)||offset<0)throw Error('Reviewed suite and exact offset required');
 process.stdout.write(read(base+name+'-candidate-reviewed-20261002-v3.sql').slice(offset,offset+40000));
}else{
 const refresh=JSON.parse(read(base+'candidate-refresh-20261002.json'));
 const installed=new Set(refresh.evidence.ledger.map(m=>m.version));
 const result={review_date:'2026-10-02',installed_count:installed.size,installed_latest:refresh.evidence.ledger.at(-1),installed_api_count:refresh.evidence.api_functions.length,
  suites:[],boundary:'Source-order/strict rollback preparation only. Actual execution results must be recorded separately. No persistent migrations.'};
 for(const [name,migrations]of Object.entries(suites)){
  const filename=base+name+'-candidate-strict-20261002.sql',raw=read(filename);
  if(!/^\uFEFF?begin;/i.test(raw)||/^(?:\s*)commit\s*;/mi.test(raw)||!raw.trimEnd().endsWith('rollback;')||!(raw.match(/select \* from finish\(true\);/g)||[]).length)throw Error('Strict rollback boundary missing: '+name);
  let sql=raw.replace(/^\uFEFF?begin;/i,'begin;\nset local search_path=pg_catalog;\ncreate temporary table w4_before as '+snapshot+';\nset local search_path=public,extensions;');
  const [assertions,samples,key,body]=sampleTables[name];
  sql=sql.replace(/rollback;\s*$/,'reset role;\nset local search_path=pg_catalog;\nselect jsonb_build_object(\'before\',(select catalog from w4_before),\'after\',('+snapshot.replace(/ catalog$/,'')+')) as candidate_catalog,'+
   '(select count(*) from '+assertions+') assertion_count,(select jsonb_object_agg('+key+','+body+' order by '+key+') from '+samples+') client_samples;\nrollback;\n');
  const output=base+name+'-candidate-reviewed-20261002-v3.sql';fs.writeFileSync(output,sql,{flag:'wx'});
  const sources=['supabase/tests/build_'+name+'_candidate.ps1','supabase/wave_tests/wave4_synthetic_fixture.sql','supabase/wave_tests/wave4_'+name+'_test.sql',...migrations.map(m=>'supabase/migrations/'+m)];
  if(name==='project_finance')sources.push('supabase/wave_tests/wave4_projects_test.sql');
  if(name==='payroll_corrections')sources.push('supabase/tests/build_payroll_candidate.ps1','supabase/wave_tests/wave4_payroll_test.sql');
  result.suites.push({name,query_path:output,query_sha256:hash(sql),query_length:sql.length,assertions:(sql.match(/insert into \w+_assertions select (is|ok|throws_ok|lives_ok)\(/g)||[]).length,
   strict_finish_true:true,final_rollback:true,candidates:migrations.map((m,ordinal)=>({path:'supabase/migrations/'+m,ordinal:ordinal+1,installed:installed.has(m.slice(0,14)),sha256:hash(read('supabase/migrations/'+m))})),
   source_sha256:Object.fromEntries([...new Set(sources)].map(p=>[p,hash(read(p))]))});
 }
 fs.writeFileSync(base+'candidate-order-source-review-20261002-v3.json',JSON.stringify(result,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify(result.suites.map(s=>({name:s.name,query_length:s.query_length,assertions:s.assertions,query_sha256:s.query_sha256}))));
}
