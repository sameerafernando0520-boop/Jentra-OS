import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const base='docs/verification/wave5/';
const bindings=[
 ['persistent-setup-actual-verification-20261013-r5-a3.json','acfcf0b58bff2d3da4855612978395ba481e3d8cac76300d6086bca4d2ecfd4f'],
 ['genuine-delivery-lease-20261013-r5-1791885923843/99-result.json','e35cf55c3f093a17416bf132e89783eb4e4a337c808eda69fd747238c2322076'],
 ['actual-delivery-fixtures-20261013-r5-1791886204826/99-result.json','a39892480eb4009eac5a3c6cbf0debbc1a74860eec63ceca5f39a65c240ddd79'],
 ['worker-deployment-source-verification-20261013-r5.json','a225a93f91800469b61e4893675aa9f85451cb1310b85263e39cf410b8f8a253']
];
const runtime='778237e3-3d4e-4871-8cc9-e08b07b989c7';
const tenant='babe6c86-a764-4d3a-80a3-952a7c096c2c';
const names=['jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'];
const namesSql=names.map(n=>`'${n}'`).join(',');
const emptyHash='4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945';
const query=`SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'scopeAllowed',intelligence_control.runtime_scope_allowed('${runtime}','${tenant}','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1'),
 'authority',(SELECT jsonb_build_object('runtimeId',runtime_id,'enabled',enabled,'issuedAt',issued_at,'expiresAt',expires_at,'jobIds',job_ids) FROM intelligence_control.edge_authorities WHERE runtime_id='${runtime}'),
 'ownJobs',(SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'active',active,'schedule',schedule,'command',command) ORDER BY jobid) FROM cron.job WHERE jobid IN (4,5,6)),
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN (4,5,6)),
 'ticks',(SELECT count(*) FROM intelligence_control.edge_ticks WHERE runtime_id='${runtime}'),
 'quotaPeriods',(SELECT count(*) FROM intelligence_control.quota_periods WHERE tenant_id='${tenant}')
 ) AS snapshot;`;
const sql=`BEGIN;
DO $start_exact_jobs$
DECLARE a intelligence_control.edge_authorities%rowtype; j bigint;
BEGIN
 SELECT * INTO a FROM intelligence_control.edge_authorities WHERE runtime_id='${runtime}' FOR UPDATE;
 IF NOT FOUND OR NOT a.enabled OR a.expires_at<=statement_timestamp() OR a.expires_at>a.issued_at+interval '24 hours'
  OR cardinality(a.job_ids)<>3 OR NOT a.job_ids @> ARRAY[4,5,6]::bigint[] THEN RAISE EXCEPTION 'EXACT_UNEXPIRED_AUTHORITY_REQUIRED'; END IF;
 IF NOT intelligence_control.runtime_scope_allowed('${runtime}','${tenant}','caa2bb06-219a-47e9-8132-66d1271b0ffd','3813692c-f0de-4c69-8e34-d56cf54695b1') THEN RAISE EXCEPTION 'EXACT_APPROVED_SCOPE_REQUIRED'; END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobid IN (4,5,6) AND NOT active AND schedule='* * * * *'
  AND ((jobid=4 AND jobname='${names[0]}' AND command='select intelligence_control.edge_schedule_tick(''delivery'');')
   OR (jobid=5 AND jobname='${names[1]}' AND command='select intelligence_control.edge_schedule_tick(''subscription'');')
   OR (jobid=6 AND jobname='${names[2]}' AND command='select intelligence_control.edge_schedule_tick(''health'');')))<>3
  OR (SELECT count(*) FROM cron.job WHERE jobname IN (${namesSql}))<>3 THEN RAISE EXCEPTION 'EXACT_THREE_PAUSED_OWN_JOBS_REQUIRED'; END IF;
 IF (SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(c) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job c WHERE jobid NOT IN (4,5,6))<>'${emptyHash}' THEN RAISE EXCEPTION 'OUTSIDE_JOB_PRESERVATION_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM intelligence_control.edge_ticks WHERE runtime_id='${runtime}')
  OR EXISTS(SELECT 1 FROM intelligence_control.quota_periods WHERE tenant_id='${tenant}') THEN RAISE EXCEPTION 'ZERO_WORKER_START_BASELINE_REQUIRED'; END IF;
 FOREACH j IN ARRAY ARRAY[4,5,6]::bigint[] LOOP PERFORM cron.alter_job(j,active:=true); END LOOP;
END $start_exact_jobs$;
COMMIT;
${query}`;
await loadApprovedInputs();
for(const [file,sha] of bindings){const b=await fs.readFile(path.join(root,base+file)),v=JSON.parse(b);
 const actualPassed=file==='worker-deployment-source-verification-20261013-r5.json'
  ?v.deployedWorkerSource===true&&v.existingPeopleFunctionsUnchanged===true&&v.functions.length===2
   &&v.functions.every(f=>f.status==='ACTIVE'&&f.allReturnedSourceHashesMatch===true)
  :v.passed===true;
 if(hashBytes(b)!==sha||!actualPassed)throw Error('EXACT_PASSED_BINDING_REQUIRED');}
async function save(file,bytes){const h=await fs.open(path.join(root,base+file),'wx');try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}return {path:base+file,sha256:hashBytes(bytes)};}
const sqlBinding=await save('scheduled-delivery-start-20261013-r5.sql',sql);
const readBinding=await save('scheduled-delivery-start-read-20261013-r5.sql',query);
const intent=await save('scheduled-delivery-start-intent-20261013-r5.json',JSON.stringify({kind:'approved-exact-scheduled-delivery-start-intent',projectId:PROJECT,bundleSha256:BUNDLE,actualPreparedAt:new Date().toISOString(),bindings:bindings.map(([file,sha])=>({path:base+file,sha256:sha})),sql:sqlBinding,readback:readBinding,runtimeId:runtime,ownJobs:names.map((name,i)=>({jobId:i+4,name})),reviewedExpiryUnchanged:true,automaticRetry:false,leaseFixtureCompleted:true,registeredReceiverPaths:['accept','redirect','timeout','reject'],expectedEligibleDeliveries:5,modelCallApprovalCap:4,actualDeliveryYetVerified:false,fullProviderCoordinatorPassed:false,production:false,realBilling:false,secretsSelectedOrPrinted:false},null,2)+'\n');
process.stdout.write(JSON.stringify({passed:true,networkCalls:0,intent,sql:sqlBinding,readback:readBinding})+'\n');
