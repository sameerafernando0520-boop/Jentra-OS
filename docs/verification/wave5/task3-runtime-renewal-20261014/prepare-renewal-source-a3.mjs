// Additive, source-only repair of the reviewed a2 SQL. No database transport.
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
const dir=new URL('./',import.meta.url),root=new URL('../../../../',import.meta.url);
const hash=x=>createHash('sha256').update(x).digest('hex');
const bind=async path=>{const bytes=await fs.readFile(new URL(path,root));return {path,bytes:bytes.length,sha256:hash(bytes)};};
const must=(ok,code)=>{if(!ok)throw Error(code);};
const prefix='docs/verification/wave5/task3-runtime-renewal-20261014/';
const oldWrite=await fs.readFile(new URL('renewal-expiry-update-template-a2.sql',dir),'utf8');
const oldRead=await fs.readFile(new URL('renewal-preflight-read-a1.sql',dir),'utf8');
must(hash(oldWrite)==='f8eab2e077a83c9d60c6be8a068396df054064ba8f4b1c39c6adea16d7bf3724','EXACT_A2_WRITE_REQUIRED');
must(hash(oldRead)==='6e58be0ba744340f8883fc9b59dc7443192df2f3dc282aca8d7ee8cdd0484e65','EXACT_A1_READ_REQUIRED');
const runtime='778237e3-3d4e-4871-8cc9-e08b07b989c7',tenant='babe6c86-a764-4d3a-80a3-952a7c096c2c';
const count=(table,where)=>`(SELECT count(*) FROM ${table} WHERE ${where})`;
const financeTables={journals:'finance.journal_entries',lines:'finance.journal_lines',publications:'finance.financial_reports',
 classifications:'analytics.statement_classifications',dateProposals:'analytics.cash_date_proposals',dateDecisions:'analytics.cash_date_decisions',
 scenarios:'analytics.cash_scenario_revisions',exports:'core.export_jobs',processEvents:'workflow.process_events'};
const finance=`jsonb_build_object(${Object.entries(financeTables).map(([key,table])=>`'${key}',${count(table,`tenant_id='${tenant}'`)}`).join(',')})`;
const effectTables={ticks:['intelligence_control.edge_ticks',`runtime_id='${runtime}'`],outcomes:['intelligence_control.edge_tick_outcomes',`runtime_id='${runtime}'`],
 quotaPeriods:['intelligence_control.quota_periods',`tenant_id='${tenant}'`],deliveryOutcomes:['intelligence_control.delivery_outcomes',`tenant_id='${tenant}'`],
 receiverReceipts:['intelligence_control.edge_receiver_receipts',`runtime_id='${runtime}'`],modelInvocations:['intelligence_control.model_invocations',`tenant_id='${tenant}'`],
 usageEvents:['intelligence_control.usage_events',`tenant_id='${tenant}'`]};
const effects=`jsonb_build_object(${Object.entries(effectTables).map(([key,args])=>`'${key}',${count(...args)}`).join(',')},'modelOutcomes',
 (SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id='${tenant}'))`;
const baseline={journals:9,lines:18,publications:3,classifications:1,dateProposals:3,dateDecisions:3,scenarios:0,exports:0,processEvents:7};
const effectBaseline=Object.fromEntries([...Object.keys(effectTables),'modelOutcomes'].map(key=>[key,0]));
const billing=`(SELECT jsonb_agg(jsonb_build_object('status',status,'trialEndsAt',trial_ends_at,'currentPeriodEndsAt',current_period_ends_at) ORDER BY status,trial_ends_at)
 FROM billing.tenant_subscriptions WHERE tenant_id='${tenant}')`;
const read=oldRead.replace("'observedAt',statement_timestamp(),",`'observedAt',statement_timestamp(),'timeZone',current_setting('TimeZone'),
 'financeCounters',${finance},'effectCounters',${effects},'billingWindow',${billing},`)
 .replace(') AS renewal_snapshot;',") AS renewal_snapshot WHERE current_setting('TimeZone')='UTC';");
must(read!==oldRead&&read.includes('financeCounters')&&read.includes("WHERE current_setting('TimeZone')='UTC'"),'UTC_PUBLIC_PROJECTION_REQUIRED');
let write=oldWrite.replace("SET LOCAL search_path=pg_catalog;","SET LOCAL search_path=pg_catalog;\nSET LOCAL TimeZone='UTC';");
const counterCheck=` IF ${finance} IS DISTINCT FROM '${JSON.stringify(baseline)}'::jsonb
  OR ${effects} IS DISTINCT FROM '${JSON.stringify(effectBaseline)}'::jsonb
  OR (SELECT count(*) FROM cron.job_run_details WHERE jobid IN(4,5,6) AND start_time>='2026-10-13T09:57:07.481942Z'::timestamptz)<>24
  THEN RAISE EXCEPTION 'PRESERVED_FINANCE_AND_WORKER_COUNTERS_REQUIRED'; END IF;
`;
write=write.replace(' UPDATE intelligence_control.edge_authorities SET expires_at=v_new_expiry',counterCheck+' UPDATE intelligence_control.edge_authorities SET expires_at=v_new_expiry');
write=write.replace('END $renew_exact_two_expiries$;',counterCheck+'END $renew_exact_two_expiries$;');
write+=`\n-- This is an actual server post-commit observation, not a client timestamp.
-- The earlier fresh preflight remains the conservative expiry anchor.
SELECT jsonb_build_object('runtimeId','${runtime}','appliedAt',clock_timestamp(),
 'expiresAt',(SELECT expires_at FROM intelligence_control.edge_authorities WHERE runtime_id='${runtime}'),
 'affectedRows',2,'applicationTimestampProvenance','server-post-commit-observation') AS renewal_application;\n`;
const outputs={'renewal-preflight-read-a3.sql':read,'renewal-expiry-update-template-a3.sql':write};
for(const [name,content]of Object.entries(outputs))await fs.writeFile(new URL(name,dir),content,{flag:'wx'});
const report={kind:'additive-renewal-a3-source-repair',preparedAt:new Date().toISOString(),sourceOnly:true,executionPermitted:false,
 predecessors:[await bind(prefix+'renewal-preflight-read-a1.sql'),await bind(prefix+'renewal-expiry-update-template-a2.sql')],
 sources:await Promise.all(Object.keys(outputs).map(name=>bind(prefix+name))),financeBaseline:baseline,effectBaseline,
 changes:['Write transaction fixes UTC for unchanged non-window hash bindings.','Read returns no row in a non-UTC session.',
 'Read projects finance/effect/billing evidence; write guards exact counters before and after two expiry updates.',
 'Write returns actual server post-commit application observation after COMMIT; preflight remains expiry anchor.'],
 contract:{readColumn:'renewal_snapshot',writeColumn:'renewal_application',writeFields:['runtimeId','appliedAt','expiresAt','affectedRows','applicationTimestampProvenance'],
 readAddedFields:['timeZone','financeCounters','effectCounters','billingWindow'],applicationTimestampMeaning:'Actual server observation after successful COMMIT; not exact row-update or commit timestamp.'},
 validation:{predecessorHashesVerified:true,approvalInputsRemainNull:true,exactExpiryUpdateStatements:(write.match(/UPDATE intelligence_control\.(edge_authorities|runtime_worker_scopes) SET expires_at=/g)||[]).length,
  counterGuards:(write.match(/RAISE EXCEPTION 'PRESERVED_FINANCE_AND_WORKER_COUNTERS_REQUIRED'/g)||[]).length,readUtcFilter:read.endsWith("WHERE current_setting('TimeZone')='UTC';\r\n")||read.trim().endsWith("WHERE current_setting('TimeZone')='UTC';"),
  databaseParsed:false,databaseExecuted:false,managementCalls:0,privateInputRead:false}};
must(report.validation.exactExpiryUpdateStatements===2&&report.validation.counterGuards===2&&report.validation.readUtcFilter,'SOURCE_GUARD_REPAIR_REQUIRED');
await fs.writeFile(new URL('source-repair-a3.json',dir),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify(report)+'\n');
