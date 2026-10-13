// Validate actual post-approval catalog reads. No live operation or fixture writes.
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual as eq} from 'node:util';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateApproval} from '../../tools/wave5/runtime_contract.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base='docs/verification/wave5/';
const sha=b=>createHash('sha256').update(b).digest('hex');
const must=(test,message)=>{if(!test)throw Error(message);};
must(process.argv.length===2,'NO_ARGUMENTS_ALLOWED');
const inputs=[];
async function json(file){const b=await readFile(path.join(root,file));inputs.push({path:file,sha256:sha(b),bytes:b.length});return JSON.parse(b);}
function decode(value){
  if(typeof value==='string'){
    let parsed;try{parsed=JSON.parse(value);}catch{
      const block=value.match(/(?:^|\n)<untrusted-data-([a-zA-Z0-9-]+)>\r?\n([\s\S]*?)\r?\n<\/untrusted-data-\1>(?:\n|$)/);
      must(block,'DELIMITED_CONNECTOR_DATA_REQUIRED');return JSON.parse(block[2]);
    }return decode(parsed);
  }
  must(value?.isError!==true,'CONNECTOR_ERROR');
  if(value?.rawConnectorResult)return decode(value.rawConnectorResult);
  if(Array.isArray(value?.content)){const t=value.content.filter(c=>c.type==='text');must(t.length===1,'ONE_TEXT_BLOCK_REQUIRED');return decode(t[0].text);}
  if(typeof value?.result==='string')return decode(value.result);
  return value;
}
const review=await json(base+'complete-app-runtime-review-20261010-r5.json');
must(inputs.at(-1).sha256==='b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3','FROZEN_REVIEW_REQUIRED');
const decision=await json(base+'runtime-owner-decision-20261012-r5.json');
validateApproval(decision,review,{runtimeFileSha256:inputs[0].sha256});
const byteCheck=await json(base+'approved-runtime-byte-check-20261012-r5.json');
must(byteCheck.passed===true && byteCheck.failures.length===0 && byteCheck.inspectedBindings===5539 && byteCheck.finishedAt>=decision.approvedAt,'ACTUAL_APPROVED_BYTE_CHECK_REQUIRED');
const actual=await json(base+'approved-live-preflight-20261012-r5-raw.json');
must(actual.results.length===3 && actual.results.every(x=>x.status==='fulfilled' && x.value.startedAt>=decision.approvedAt),'ACTUAL_POST_APPROVAL_READS_REQUIRED');
const results=Object.fromEntries(actual.results.map(x=>[x.value.label,decode(x.value.result)]));
const prior=decode(await json(base+'complete-live-preflight-20261010-r5-raw.json'));
const oldLedger=decode(await json(base+'complete-live-preflight-20261010-r5-ledger.json')).migrations;
const oldEdges=decode(await json(base+'complete-live-preflight-20261010-r5-edge-list.json')).functions;
const install=await json(base+'installation-result-20261008.json');
const query=await readFile(path.join(root,base+'complete-live-preflight-20261010-r2.sql'));
must(sha(query)==='cf886dbb2fac359b530626b50d99312c14b5398a7d620b22100852154594e250','EXACT_QUERY_REQUIRED');
must(results.fullPreflight.length===1 && prior.length===1,'ONE_SNAPSHOT_REQUIRED');
const before=prior[0],current=results.fullPreflight[0];
const changed=Object.keys(current).filter(k=>!eq(before[k],current[k]));
const failures=[];
const check=(test,reason)=>{if(!test)failures.push(reason);};
check(eq(Object.keys(before).sort(),Object.keys(current).sort())&&Object.keys(current).length===40,'FORTY_FIELD_SCHEMA_CHANGED');
check(eq(changed,['observed_at']),'UNEXPECTED_METADATA_DRIFT:'+changed.join(','));
check(current.migration_count===43&&current.api_functions===107&&current.functions.length===120,'BASELINE_COUNTS_CHANGED');
check(current.wave5_tables.length===15&&current.wave5_tables.every(t=>t.rlsEnabled===true&&t.rlsForced===true),'FORCED_RLS_CHANGED');
check(current.role_permissions===87&&current.role_assignments===1&&current.entitlements===28&&current.memberships===1,'ACCESS_COUNTS_CHANGED');
const ledger=results.ledger.migrations,edges=results.edge.functions;
const sortLedger=rows=>[...rows].sort((a,b)=>a.version.localeCompare(b.version));
check(ledger.length===43&&new Set(ledger.map(x=>x.version)).size===43&&eq(sortLedger(ledger),sortLedger(oldLedger)),'MIGRATION_LEDGER_DRIFT');
check(eq(edges,oldEdges),'EDGE_METADATA_DRIFT');
const preservedSix=install.migrationsInOrder.map(m=>({sourcePath:m.path,ledgerEntry:m.ledgerEntry,
  matches:ledger.filter(x=>x.name===m.ledgerEntry.name&&x.version===m.ledgerEntry.version).length,reinstalled:false}));
check(preservedSix.length===6&&preservedSix.every(x=>x.matches===1),'ORIGINAL_SIX_CHANGED');
const observedMs=Date.parse(current.observed_at.replace(' ','T').replace(/\+00$/,'Z'));
check(Number.isFinite(observedMs)&&observedMs>=Date.parse(decision.approvedAt),'POST_APPROVAL_SERVER_TIMESTAMP_REQUIRED');
const summary={kind:'wave5-approved-runtime-immediate-live-preflight',recordedAt:new Date().toISOString(),
  projectId:review.projectId,connectionLinkId:'link_6aa8c9ca60408191b9e7e8344c5a6693',
  runtimeBundleSha256:review.bundleSha256,operationScopeSha256:decision.operationScopeSha256,
  observedAt:current.observed_at,startedAt:actual.startedAt,finishedAt:actual.finishedAt,
  comparedFields:40,changedFields:changed,providerFunctionsChecked:120,forcedRlsTablesChecked:15,
  migrationCount:current.migration_count,apiFunctions:current.api_functions,ledgerEntries:ledger.length,
  originalSix:preservedSix,edgeMetadataEntries:edges.length,edgeSourceBodiesReread:false,
  accessCounts:{rolePermissions:current.role_permissions,roleAssignments:current.role_assignments,entitlements:current.entitlements,memberships:current.memberships},
  trialAccount:current.trial_account,proposedRuntimeAccounts:current.proposed_runtime_accounts,
  failures,passed:failures.length===0,installationPreflightComplete:failures.length===0,
  privateProvisioningPreflightComplete:false,capacityForFullRuntimeVerified:false,
  rawEvidence:inputs.find(x=>x.path.endsWith('approved-live-preflight-20261012-r5-raw.json')),
  query:{path:base+'complete-live-preflight-20261010-r2.sql',sha256:sha(query)},inputs,
  metadataArchiveAttemptFailure:{reason:'Combined JavaScript input exceeded the 64000-byte auto-review limit; three bounded data parts preserved the same successful connector responses without rerunning SQL.'},
  readOnly:true,sqlInstalled:false,authCreatedOrDeleted:false,secretValuesRead:false,nativeAcceptance:false,
  actualDelivery:false,independentContention:false,targetScaleLoad:false,ownerAcceptedCriteria:3,production:false,realBilling:false};
for(const input of inputs)must(sha(await readFile(path.join(root,input.path)))===input.sha256,'INPUT_CHANGED:'+input.path);
const out=base+'approved-live-preflight-20261012-r5-summary.json';
const bytes=Buffer.from(JSON.stringify(summary,null,2)+'\n');await writeFile(path.join(root,out),bytes,{flag:'wx'});
console.log(JSON.stringify({path:out,sha256:sha(bytes),passed:summary.passed,observedAt:current.observed_at,migrationCount:current.migration_count,apiFunctions:current.api_functions,changedFields:changed,failures}));
if(!summary.passed)process.exitCode=1;
