import {readFile,writeFile} from 'node:fs/promises';
const base='docs/verification/ai-integrations-test-20261103/';
let sql=await readFile(base+'model-accounting-final.sql','utf8');
const replace=(from,to)=>{if(sql.split(from).length!==2)throw Error('ACCOUNTING_QUERY_TEMPLATE_CHANGED');sql=sql.replace(from,to);};
replace("select jsonb_build_object('projectId'","with accounting as (select jsonb_build_object('projectId'");
replace("jsonb_build_object('state',state,'tokens',tokens::text,'recordedAt',recorded_at)","jsonb_build_object('state',state,'tokens',tokens::text,'suggestion',suggestion,'recordedAt',recorded_at)");
replace(') as final_model_attempt_accounting;',`) as evidence)
select evidence#>>'{outcome,state}' as state,
 evidence#>>'{outcome,tokens}' as trusted_tokens,
 evidence#>>'{usage,quantity}' as ledger_tokens,
 evidence#>>'{quotaPeriods,0,reserved}' as quota_reserved,
 evidence#>>'{quotaPeriods,0,settled}' as quota_settled,
 evidence as verified_evidence from accounting;`);
await writeFile(base+'publishable-repair-accounting.sql',sql,{flag:'wx'});
console.log(JSON.stringify({prepared:true,readOnly:true,networkCalls:0}));
