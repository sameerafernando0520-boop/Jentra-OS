import fs from 'node:fs';
import crypto from 'node:crypto';
const composed = fs.readFileSync('build/remaining-wave3/final-procurement-20260930.sql','utf8');
const prefix = composed.slice(0, composed.indexOf('create extension if not exists pgtap'));
if (!prefix.startsWith('begin;')) throw Error('Missing rollback candidate prefix');
function collectStatements(sql) {
  let start=0, quote=null, dollar=null, line=false, block=0, out='';
  const emit=(end)=>{
    const statement=sql.slice(start,end);
    const first=/^(\s*(?:(?:--[^\n]*\n\s*)|(?:\/\*[\s\S]*?\*\/\s*))*)select\s+(?!plan\(|no_plan\()/i;
    out+=statement.replace(first,'$1insert into wave3_baseline_results select ');
    start=end;
  };
  for(let i=0;i<sql.length;i++) {
    const c=sql[i], n=sql[i+1];
    if(line) { if(c==='\n') line=false; continue; }
    if(block) { if(c==='/'&&n==='*'){block++;i++;} else if(c==='*'&&n==='/'){block--;i++;} continue; }
    if(dollar) { if(sql.startsWith(dollar,i)){i+=dollar.length-1;dollar=null;} continue; }
    if(quote) { if(c===quote){if(n===quote)i++;else quote=null;} continue; }
    if(c==='-'&&n==='-'){line=true;i++;continue;}
    if(c==='/'&&n==='*'){block=1;i++;continue;}
    if(c==="'"||c==='"'){quote=c;continue;}
    if(c==='$'){const m=sql.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$/);if(m){dollar=m[0];i+=dollar.length-1;continue;}}
    if(c===';')emit(i+1);
  }
  if(quote||dollar||block)throw Error('Unclosed SQL quote');
  emit(sql.length);
  return out;
}
for (const name of ['operational_foundation','crm_pipeline','quotation_workspace','order_workspace']) {
  const source = 'supabase/tests/wave3_' + name + '_test.sql';
  let body = fs.readFileSync(source,'utf8').replace(/^begin;\s*/,'').replace(/select \* from finish\((?:true)?\);[\s\S]*?rollback;\s*$/,'');
  if (name === 'operational_foundation') {
    // The legacy fixture predates governed period transitions. Supply its
    // synthetic event in this rollback-only stack, preserving the original test.
    body = body.replace('update finance.fiscal_periods', `
select set_config('request.jwt.claims','{"sub":"13000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}',true);
insert into finance.period_events(id,tenant_id,legal_entity_id,period_id,action,from_state,to_state,period_version,reason,exceptions,actor_id,transaction_id)
select '65000000-0000-0000-0000-000000000003',tenant_id,legal_entity_id,id,'soft_lock','open','soft_locked',version,
'Synthetic legacy locked-period fixture','[]',auth.uid(),txid_current()
from finance.fiscal_periods where id='65000000-0000-0000-0000-000000000002';
update finance.fiscal_periods`);
    // Authenticated read-only RLS predicates are required by private attachment
    // policies. The historical blanket helper assertion predates that contract.
    const grants = "where g.grantee = 'authenticated'";
    if (!body.includes(grants)) throw Error('Missing helper grant assertion');
    body = body.replace(grants, grants + `
      and g.routine_name not in ('wave3_attachment_access','wave3_storage_access','wave3_source_descriptor')`);
  }
  if (/\b(?:commit|rollback)\s*;/i.test(body)) throw Error('Nested transaction in '+source);
  body = collectStatements(body);
  const query = prefix + 'create temporary table wave3_baseline_results(message text);\ngrant all on wave3_baseline_results to authenticated;\n' + body + '\nset constraints all immediate;\ninsert into wave3_baseline_results select * from finish(true);\nselect jsonb_agg(message) as results from wave3_baseline_results;\nrollback;\n';
  const path = 'build/remaining-wave3/baseline-'+name+'-20260930.sql';
  fs.writeFileSync(path,query);
  console.log(JSON.stringify({name,path,characters:query.length,sha256:crypto.createHash('sha256').update(query).digest('hex')}));
}
