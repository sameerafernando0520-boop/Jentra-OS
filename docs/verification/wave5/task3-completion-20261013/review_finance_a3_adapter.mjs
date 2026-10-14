import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const read=async relative=>{const bytes=await fs.readFile(path.join(root,relative));return{path:relative,bytes:bytes.length,sha256:sha(bytes),text:bytes.toString('utf8')};};
const ref=({text,...binding})=>binding;
const before=await read('docs/verification/wave5/finance-a3-private-adapter-predecessor-20261014-r5.ps1');
const after=await read('scripts/wave5/run_private_management_installer_20261013_r5.ps1');
assert.equal(before.sha256,'bc9b5671013bed109d441c847373d97068f2d8a91c35219e4052ff91960a2e77');
assert.equal(after.sha256,'51541f5406721fd7d4f9403c2b8fa04b2cae96f2cb213410cdaec5129eb1ec1a');
const start="    if ($Mode -in @('ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3')) {";
const end='    $taskNode = (Get-Command node -CommandType Application';
const i=after.text.indexOf(start),j=after.text.indexOf(end,i);assert.ok(i>0&&j>i);
const selector=after.text.slice(i,j);
let reversed=after.text.slice(0,i)+after.text.slice(j);
reversed=reversed.replace("'ExecuteRemainingFinance','ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3')][string]","'ExecuteRemainingFinance')][string]");
let privateLists=0;
reversed=reversed.split('\n').map(line=>{
 if(line.startsWith('$taskNeedsPrivate =')||line.includes("if ($Mode -in @('ProvisionAuth','EnrollMfa'")){
  assert.ok(line.includes("'ExecuteRemainingFinance','ExecuteRemainingFinanceA3')"));privateLists++;
  return line.replace("'ExecuteRemainingFinance','ExecuteRemainingFinanceA3')","'ExecuteRemainingFinance')");}
 return line;
}).join('\n');
assert.equal(privateLists,2);
reversed=reversed.replace("'ExecuteRemainingFinance' { '--execute' } 'ExecuteRemainingFinanceA3' { '--execute' }","'ExecuteRemainingFinance' { '--execute' }");
assert.equal(reversed,before.text);
for(const exact of ['9c9e856c2cfdb852a3a9b9e66474f14c86a32dc72cc5b613e806699b2fb78c01',
 '8cf6068a4f4863c27d234b96755b2e1f9332c13590a25e5b66ef4742da87bd52',
 '6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198',
 'f661da3175194cdf472e8c24046804023b545485e13dbd40279d39991ff5d135',
 '8399666dc0528532cd3462e26a70ac89a340b6484a7b3fe911172d291aae814e'])assert.ok(selector.includes(exact));
assert.ok(!selector.includes('ConvertTo-SecureString')&&!selector.includes('SecureStringToBSTR'));
const sourceReview=await read('docs/verification/wave5/task3-completion-20261013/finance-a3-independent-source-and-plan-review.json');
assert.equal(sourceReview.sha256,'8399666dc0528532cd3462e26a70ac89a340b6484a7b3fe911172d291aae814e');
const review=JSON.parse(sourceReview.text);assert.equal(review.generatedPlanApproved,true);
const plan=await read('build/wave5-approved-execution-20261013-r5-a2/docs/verification/wave5/finance-remaining-preparation-20261014-r5-a3.json');
assert.equal(plan.sha256,'6c39a389ebaec0315774500af2af1e71874486173d85a3e352ef5782153e1198');
const preparation=await read('docs/verification/wave5/finance-a3-private-adapter-source-preparation-20261014-r5.json');
const report={kind:'primary-independent-exact-finance-a3-private-adapter-operation-review',reviewedAt:new Date().toISOString(),
 projectId:'xpdoufauvrbdmxgngetv',technicalVerdict:'approve one existing bounded finance-a3 execution through the exact reviewed adapter',
 exactReverseDeltaEqualsPreservedPredecessor:true,modesAdded:['ValidateRemainingFinanceA3','ExecuteRemainingFinanceA3'],
 newPrivateMode:'ExecuteRemainingFinanceA3',validateModeUnsealsCredentials:false,
 unchangedGuards:['original mode selectors','fixed approved snapshot','exact new source/plan/both technical reviews before unseal',
 'fresh same-SID private metadata and protected ACL','DPAPI and existing seal','UTC expiry/two-hour scope','hidden child/pipe and sanitized output'],
 priorRequestBound:78,maximumTotalAttempts:150,maximumOrdinaryAttempts:71,maximumReadOnlyResolutionAttempts:1,
 individualTimeoutMs:45000,maximumExecutionMs:900000,staleCommandReplayForbidden:true,
 authority:'Verified direct user delegation; separate source and generated-plan decisions preserved. No personal human exact-source signature.',
 personalHumanExactSourceSignatureClaimed:false,adapter:ref(after),predecessor:ref(before),plan:ref(plan),sourceAndPlanReview:ref(sourceReview),preparation:ref(preparation),
 privateInputsReadByReviewer:false,networkCallsByReviewer:0,executionPerformedByReviewer:false,
 actualNewFinanceResultEstablished:false,fullFinanceCashComplete:false,authenticatedNative:false,targetScaleLoad:false,productionReleaseReady:false,
 decision:'The live owner may execute once using this exact adapter after its normal validation. Fresh online original-baseline/quiescence/functions and original UTC day/expiry checks must pass; preserve all failures and never replay the old uncertain command.'};
const bytes=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'finance-a3-independent-adapter-operation-review.json');
await fs.writeFile(output,bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({approved:true,adapterSha256:after.sha256,report:{path:path.relative(root,output).replaceAll('\\','/'),bytes:bytes.length,sha256:sha(bytes)}})+'\n');
