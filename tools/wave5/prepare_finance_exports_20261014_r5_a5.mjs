// A public-only preparation. It never unseals credentials or selects an intent.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs} from './approved_management_installer.mjs';
import {hashBytes,immutableJson} from './runtime_contract.mjs';
import {FINANCE_CALENDAR,validateFinanceFixture} from './finance_cash_fixture_20261013_r5.mjs';
import {EXECUTION_ROOT,PUBLIC_EVIDENCE_ROOT,readExactRemainingFile,verifyRemainingPreparation} from './finance_remaining_20261014_r5_a3.mjs';
import {EXPORTS_SOURCE_PATHS,EXPORTS_PLAN,EXPORTS_ONCE,EXPORTS_PROFILE,EXPORTS_FINAL_REVIEW,EXPORTS_RUNTIME_EXPIRY,
 EXPORTS_DAY,EXPORTS_PRESERVED_BINDINGS,EXPORTS_COMMANDS,EXPORTS_SQL_SHA256,loadExportsProfile,loadExportsPreserved,
 validateExportsProfile,validateExportsConsumed,validateExportsPreparation,writeExportsEvidence} from './finance_exports_20261014_r5_a5.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
export function buildExportsPreparation({profileBinding,profile,documents,oldPlan,preserved,sourceBindings,preparedAt}={}){
 const now=Date.parse(preparedAt);validateExportsProfile(profile,documents,now);validateExportsConsumed(preserved);
 must(profileBinding?.path===EXPORTS_PROFILE&&/^[a-f0-9]{64}$/.test(profileBinding.sha256)&&oldPlan?.maximumTotalWorkflowRequestAttempts===150,
  'PINNED_PUBLIC_EXPORT_PREPARATION_INPUTS_REQUIRED');
 const expected=[...new Set([...oldPlan.sourceBindings.map(row=>row.path),...Object.values(EXPORTS_PRESERVED_BINDINGS).map(row=>row.path),...EXPORTS_SOURCE_PATHS])].sort();
 must(JSON.stringify(sourceBindings.map(row=>row.path).sort())===JSON.stringify(expected)
  &&[...oldPlan.sourceBindings,...Object.values(EXPORTS_PRESERVED_BINDINGS)].every(previous=>sourceBindings.some(row=>row.path===previous.path&&row.sha256===previous.sha256)),
  'EXACT_PRESERVED_EXPORT_SOURCE_AND_EVIDENCE_BINDINGS_REQUIRED');
 const plan=immutableJson({kind:'source-bound-genuine-export-only-preparation',preparedAt,projectId:PROJECT,runtimeBundleSha256:BUNDLE,
  priorConservativeBound:132,ordinaryAttempts:24,ordinaryLimit:156,cumulativeLimit:157,resolutionAttempts:1,originalConcreteCap:150,
  explicitAdditionalCeiling:7,requiredActualExportUtcDay:EXPORTS_DAY,originalFixtureUtcDay:FINANCE_CALENDAR.fixtureDay,
  authorizationExpiresAt:profile.authorizationExpiresAt,runtimeAuthorityExpiresAt:EXPORTS_RUNTIME_EXPIRY,profileBinding,controlBindings:profile.controlBindings,
  preservedBindings:EXPORTS_PRESERVED_BINDINGS,sourceBindings,publicBindings:[profileBinding,...Object.values(profile.controlBindings)],
  privateAdapterPredecessor:profile.privateAdapterPredecessor,permittedOriginalExportCommands:EXPORTS_COMMANDS,consolidatedSqlSha256:EXPORTS_SQL_SHA256,
  snapshotRoot:EXECUTION_ROOT,publicEvidenceRoot:PUBLIC_EVIDENCE_ROOT,exclusiveOncePath:EXPORTS_ONCE,finalReviewPath:EXPORTS_FINAL_REVIEW,
  maximumRunMs:900000,maximumSingleRequestMs:45000,ordinaryDispatchMustReserveInflightAndResolutionMs:90000,
  successfulDateCommandsReexecuted:false,oldConsumedIntentsPreserved:true,transportRetries:0,unlistedCallsAllowed:0,
  liveExecutionAuthorizedByPreparation:false,personalHumanExactSourceSignatureClaimed:false,networkCallsDuringPreparation:0,
  privateInputsRead:false,authenticatedNative:false,targetScaleLoad:false,registeredStatementReopen:false,fullFinanceAndCashGatesComplete:false,productionReleaseReady:false});
 validateExportsPreparation(plan);return plan;
}
export async function prepareExports(profileBinding){
 must(path.resolve(await fs.realpath(root))===path.resolve(EXECUTION_ROOT),'EXACT_FROZEN_EXPORT_PREPARATION_ROOT_REQUIRED');
 const {review}=await loadApprovedInputs();validateFinanceFixture(review);
 const context=await loadExportsProfile(profileBinding),old=await verifyRemainingPreparation(),preserved=await loadExportsPreserved(),bindings=[];
 for(const binding of [...old.plan.sourceBindings,...Object.values(EXPORTS_PRESERVED_BINDINGS)]){
  await readExactRemainingFile(EXECUTION_ROOT,binding);const existing=bindings.find(row=>row.path===binding.path);
  must(!existing||existing.sha256===binding.sha256,'PRESERVED_EXPORT_BINDING_COLLISION');if(!existing)bindings.push(binding);
 }
 for(const file of EXPORTS_SOURCE_PATHS){const absolute=path.resolve(root,file);
  must(path.resolve(await fs.realpath(absolute))===absolute&&!bindings.some(row=>row.path===file),'NEW_EXPORT_SOURCE_REDIRECTION_OR_COLLISION');
  bindings.push({path:file,sha256:hashBytes(await fs.readFile(absolute))});
 }
 await readExactRemainingFile(PUBLIC_EVIDENCE_ROOT,context.profile.privateAdapterPredecessor);
 const plan=buildExportsPreparation({profileBinding,profile:context.profile,documents:context.documents,oldPlan:old.plan,preserved:preserved.documents,
  sourceBindings:bindings,preparedAt:new Date().toISOString()});
 const receipt=await writeExportsEvidence('',EXPORTS_PLAN,plan);
 return {prepared:true,evidence:receipt,sourceBindings:bindings.length,priorConservativeBound:132,cumulativeLimit:157,networkCalls:0,privateInputsRead:false};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const mode=process.argv[2];Promise.resolve().then(()=>{
  must(mode==='--prepare'&&process.argv.length===4&&/^[a-f0-9]{64}$/.test(process.argv[3]??''),'FIXED_PUBLIC_EXPORT_PROFILE_SHA_REQUIRED');
  return prepareExports({path:EXPORTS_PROFILE,sha256:process.argv[3]});
 }).then(value=>process.stdout.write(JSON.stringify(value)+'\n')).catch(error=>{
  process.stderr.write(JSON.stringify({failureCode:error.publicCode??'EXPORT_PREPARATION_STOPPED',networkCalls:0,privateInputsRead:false})+'\n');process.exitCode=1;
 });
}
