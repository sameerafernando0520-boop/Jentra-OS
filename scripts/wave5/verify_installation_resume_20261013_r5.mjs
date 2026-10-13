// Validate the exact intentional one-migration delta before resuming the approved install.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {isDeepStrictEqual as eq} from 'node:util';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateApproval} from '../../tools/wave5/runtime_contract.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const sha=b=>createHash('sha256').update(b).digest('hex');
const must=(test,message)=>{if(!test)throw Error(message);};
must(process.argv.length===2,'NO_ARGUMENTS_ALLOWED');
const inputs=[];
async function json(file){const b=await readFile(path.join(root,file));inputs.push({path:file,sha256:sha(b),bytes:b.length});return JSON.parse(b);}
function decode(v){
 if(typeof v==='string'){let p;try{p=JSON.parse(v);}catch{const m=v.match(/(?:^|\n)<untrusted-data-([a-zA-Z0-9-]+)>\r?\n([\s\S]*?)\r?\n<\/untrusted-data-\1>(?:\n|$)/);must(m,'DELIMITED_DATA_REQUIRED');return JSON.parse(m[2]);}return decode(p);}
 must(v?.isError!==true,'CONNECTOR_ERROR');
 if(v?.rawConnectorResult)return decode(v.rawConnectorResult);
 if(Array.isArray(v?.content)){const t=v.content.filter(x=>x.type==='text');must(t.length===1,'ONE_TEXT_REQUIRED');return decode(t[0].text);}
 if(typeof v?.result==='string')return decode(v.result);return v;
}
const review=await json(base+'complete-app-runtime-review-20261010-r5.json');
must(inputs[0].sha256==='b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3','EXACT_REVIEW_REQUIRED');
const owner=await json(base+'runtime-owner-decision-20261012-r5.json');
validateApproval(owner,review,{runtimeFileSha256:inputs[0].sha256});
const byteCheck=await json(base+'approved-runtime-byte-check-20261013-r5.json');
must(byteCheck.passed&&byteCheck.inspectedBindings===5539&&byteCheck.failures.length===0,'FRESH_APPROVED_BYTES_REQUIRED');
const raw=await json(base+'approved-live-resume-20261013-r5-raw.json');
must(raw.results.length===3&&raw.results.every(x=>x.status==='fulfilled'),'THREE_ACTUAL_READS_REQUIRED');
const fresh=Object.fromEntries(raw.results.map(x=>[x.value.label,decode(x.value.result)]));
const old=decode(await json(base+'complete-live-preflight-20261010-r5-raw.json'))[0];
const oldLedger=decode(await json(base+'complete-live-preflight-20261010-r5-ledger.json')).migrations;
const oldEdge=decode(await json(base+'complete-live-preflight-20261010-r5-edge-list.json')).functions;
const first=await json(base+'approved-installation-20261012-r5-steps/01-result.json');
const installation=await json(base+'installation-result-20261008.json');
must(first.passed===true&&first.migration.order===1&&first.migration.path===review.migrations[0].path&&first.migration.sha256===review.migrations[0].sha256,'ACTUAL_FIRST_MIGRATION_REQUIRED');
const current=fresh.fullPreflight[0];
const changes=Object.keys(current).filter(k=>!eq(old[k],current[k]));
const failures=[],check=(condition,reason)=>{if(!condition)failures.push(reason);};
check(fresh.fullPreflight.length===1&&Object.keys(current).length===40&&eq(Object.keys(current).sort(),Object.keys(old).sort()),'FORTY_FIELD_SCHEMA_CHANGED');
check(eq(changes,['observed_at','migration_count','api_functions','functions']),'UNEXPECTED_METADATA_DRIFT:'+changes.join(','));
check(current.migration_count===44&&current.api_functions===108&&current.functions.length===121,'PARTIAL_INSTALLED_COUNTS_CHANGED');
const identity=p=>p.schema+'.'+p.name+'('+p.arguments+')';
const map=new Map(current.functions.map(p=>[identity(p),p]));
const changedProviders=old.functions.filter(p=>!eq(p,map.get(identity(p)))).map(identity);
const oldIdentities=new Set(old.functions.map(identity));
const addedProviders=current.functions.filter(p=>!oldIdentities.has(identity(p)));
check(changedProviders.length===0,'BASELINE_PROVIDER_CHANGED');
check(addedProviders.length===1&&addedProviders[0].schema==='api'&&addedProviders[0].name==='upsert_product_unit_conversion','UNEXPECTED_PROVIDER_ADDITION');
const expectedLedger=[...oldLedger,first.assignedLedgerEntry];
const sorted=rows=>[...rows].sort((a,b)=>a.version.localeCompare(b.version));
check(fresh.ledger.migrations.length===44&&eq(sorted(expectedLedger),sorted(fresh.ledger.migrations)),'UNEXPECTED_LEDGER_DRIFT');
check(eq(oldEdge,fresh.edge.functions),'EDGE_METADATA_DRIFT');
const preservedSix=installation.migrationsInOrder.map(m=>({sourcePath:m.path,ledgerEntry:m.ledgerEntry,matches:fresh.ledger.migrations.filter(x=>x.name===m.ledgerEntry.name&&x.version===m.ledgerEntry.version).length,reinstalled:false}));
check(preservedSix.length===6&&preservedSix.every(m=>m.matches===1),'INSTALLED_SIX_CHANGED');
const observedMs=Date.parse(current.observed_at.replace(' ','T').replace(/\+00$/,'Z'));
check(Number.isFinite(observedMs)&&Date.now()-observedMs<600000,'FRESH_SERVER_OBSERVATION_REQUIRED');
const result={kind:'wave5-approved-installation-resume-preflight',recordedAt:new Date().toISOString(),projectId:review.projectId,
 runtimeBundleSha256:review.bundleSha256,operationScopeSha256:owner.operationScopeSha256,ownerApproved:true,
 observedAt:current.observed_at,metadataFieldsCompared:40,changedFields:changes,
 migrations:44,apiFunctions:108,providerFunctions:121,preservedProviderFingerprints:120,changedProviders,addedProviders,
 installedFromApproved71:1,pendingFromApproved71:70,firstAssignedLedgerEntry:first.assignedLedgerEntry,
 originalSix:preservedSix,accessCounts:{rolePermissions:current.role_permissions,roleAssignments:current.role_assignments,entitlements:current.entitlements,memberships:current.memberships},
 allResourceCollisionFieldsUnchanged:changes.every(k=>['observed_at','migration_count','api_functions','functions'].includes(k)),
 proposedRuntimeAccounts:current.proposed_runtime_accounts,edgeMetadataEntries:fresh.edge.functions.length,
 privateProvisioningPreflightComplete:false,fullRuntimeCapacityProved:false,inputs,failures,passed:failures.length===0,
 installationMayResume:failures.length===0,installedGateComplete:false,authenticatedNative:false,realMfa:false,
 actualDelivery:false,actualModel:false,independentSessionContention:false,targetScaleLoad:false,
 ownerAcceptedCriteria:3,additionalCriteriaAccepted:0,production:false,realBilling:false};
for(const input of inputs)must(sha(await readFile(path.join(root,input.path)))===input.sha256,'INPUT_CHANGED:'+input.path);
const out=base+'approved-installation-resume-preflight-20261013-r5.json';
const bytes=Buffer.from(JSON.stringify(result,null,2)+'\n');await writeFile(path.join(root,out),bytes,{flag:'wx'});
console.log(JSON.stringify({path:out,sha256:sha(bytes),passed:result.passed,observedAt:result.observedAt,installedFromApproved71:1,pendingFromApproved71:70,changedProviders,addedProvider:addedProviders[0]?.name,failures}));
if(!result.passed)process.exitCode=1;
