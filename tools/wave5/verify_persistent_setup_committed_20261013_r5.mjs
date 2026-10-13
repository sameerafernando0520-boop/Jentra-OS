import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs,decodePublicResult} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(v,c)=>{if(!v)throw Error(c);};await loadApprovedInputs();
const beforePath=base+'persistent-setup-20261013-r5-a3-1791885422750/00-before.json';
const afterPath=base+'persistent-setup-committed-readback-20261013-r5-a3.json';
const beforeBytes=await fs.readFile(path.join(root,beforePath)),afterBytes=await fs.readFile(path.join(root,afterPath));
const before=JSON.parse(beforeBytes),after=decodePublicResult(JSON.parse(afterBytes))[0].snapshot;
const names=['jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'];
must(before.authorities.length===0&&before.ownJobs.length===0&&before.ownVault.length===0,'ZERO_ACTUAL_PREWRITE_BASELINE_REQUIRED');
must(after.authorities.length===1&&after.authorities[0].enabled&&after.authorities[0].runtimeId==='778237e3-3d4e-4871-8cc9-e08b07b989c7'
 &&after.authorities[0].publicKeySha256==='e3ea9ff3f18e6bb24be674430cc494a31c4cd7d92482367b60383b5aedd6fa9d'
 &&JSON.stringify(after.authorities[0].jobIds.slice().sort())===JSON.stringify(after.ownJobs.map(j=>j.jobId).sort())
 &&after.ownJobs.length===3&&after.ownJobs.every(j=>j.active===false&&j.schedule==='* * * * *'&&names.includes(j.name)
  &&j.command===`select intelligence_control.edge_schedule_tick('${j.name.split('-').at(-1)}');`)
 &&after.ownVault.length===3&&after.keyRefs.length===2&&after.ownVault.some(v=>v.name==='jentra-w5-runtime-20261009-schedule'
  &&v.id===after.authorities[0].scheduleSecretId)
 &&after.keyRefs.every(k=>after.ownVault.some(v=>v.id===k.secretId&&v.name.endsWith(k.ref.endsWith('v1')?'v1':'v2')))
 &&after.ticks===0&&after.quotaPeriods===0&&before.outsideJobHash===after.outsideJobHash
 &&before.outsideVaultIdentityHash===after.outsideVaultIdentityHash,'EXACT_COMMITTED_PERSISTENT_SETUP_REQUIRED');
const evidence={kind:'actual-persistent-setup-after-ambiguous-http-response',passed:true,projectId:PROJECT,bundleSha256:BUNDLE,
 actualVerifiedAt:new Date().toISOString(),databaseObservedAt:after.observedAt,reviewedSetupSourceSha256:'c2ae865c9bae23be94dec512dd15645a85c9a7a82b4edbd32fbccf92a7462e41',
 bindings:{before:{path:beforePath,sha256:hashBytes(beforeBytes)},after:{path:afterPath,sha256:hashBytes(afterBytes)}},
 authority:after.authorities[0],ownJobs:after.ownJobs,vaultSecretIdentities:after.ownVault,keyRefs:after.keyRefs,
 sourceAttempt:'persistent-setup-20261013-r5-a3-1791885422750',managementHttpResponseFailurePreserved:true,
 laterCollisionGuardStoppedReplay:true,existingJobsAndVaultIdentitiesPreserved:true,secretValuesReadOrPrinted:false,
 scheduledExecution:false,actualDelivery:false,actualModelCalls:0,fullProviderCoordinatorPassed:false,ownerAccepted:false};
const out=base+'persistent-setup-actual-verification-20261013-r5-a3.json',h=await fs.open(path.join(root,out),'wx');
const bytes=JSON.stringify(evidence,null,2)+'\n';try{await h.writeFile(bytes);await h.sync();}finally{await h.close();}
process.stdout.write(JSON.stringify({passed:true,evidence:{path:out,sha256:hashBytes(bytes)},jobsPaused:true,secretsPrinted:false})+'\n');
