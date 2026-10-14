import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../../../../',import.meta.url)),prefix='docs/verification/wave5/task3-export-source-independent-20261014/';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function binding(file,expected){const bytes=await fs.readFile(path.join(root,file));const value={path:file,sha256:hash(bytes),bytes:bytes.length};if(expected&&value.sha256!==expected)throw Error('FINAL_REVIEW_SOURCE_DRIFT');return value;}
const verificationBinding=await binding(prefix+'independent-local-verification-a3.json','055db7815f9b1e1fd5a6c632af88528fba22686184234699749818dd7454beed');
const verification=JSON.parse(await fs.readFile(path.join(root,verificationBinding.path)));
if(!verification.passed||verification.tests.tests!==64)throw Error('ACTUAL_PASSING_VERIFICATION_REQUIRED');
for(const row of verification.sourcesAfter)await binding(row.path,row.sha256);
const authority=await Promise.all([
 ['docs/verification/wave5/task3-completion-20261013/export-continuation-technical-decision-20261014-a1.json','90b0d2c6767b983308bb4d8258583da26bd03b746941daac6fd1737d703bebee'],
 ['docs/verification/wave5/task3-completion-20261013/export-continuation-technical-decision-20261014-a2.json','493f4e266bf1c427f4830a224f712f8869df22734855d6359e28a5547bd555d1'],
 ['docs/verification/wave5/task3-export-independent-20261014/export-budget-day-independent-review-a2.json','7564bc4564fcbf1e68af2484373d3bd4571a2694c57f94d2633fbb88518a308b'],
 ['docs/verification/wave5/task3-export-independent-20261014/export-budget-day-independent-review-a3.json','c460b3cd02ab85737b0e1252e50eb66dd833f22c9a203e0524649f399efcf062']
].map(([file,expected])=>binding(file,expected)));
const adapter=await binding('scripts/wave5/run_private_management_installer_20261013_r5.ps1');
const checks=[
 ['authority','The current source-only decision is the exact493f successor. Historical156/150 records remain preserved; no counter reset or personal human signature is claimed.'],
 ['budget','Actual charged prior remains131 until exactly one owner A10 readiness GET is recorded. The conditional132 base permits24 ordered ordinary calls to156 and at most one pending-command read-only resolution to157.'],
 ['time','The original UTC13 fixture remains fixed; only reviewed UTC14 exports are allowed. One immutable executionStartedAt is shared by startup timer, once record and call gate. Ordinary dispatch reserves90s and resolution45s against the earliest run, fresh owner and original runtime expiry.'],
 ['private gate','The CLI validates fixed execution root, every exact source/evidence hash, fresh profile/control documents and exact final review hash plus current adapter hash before stdin/private unseal. PublicBindings is exactly six unique declared paths.'],
 ['actual public budget','The immutable actual a3 document is accepted by exact decision path/SHA with optional bytes exactly21081; the dedicated regression rejects wrong path/hash/bytes without rewriting the source evidence.'],
 ['consumed operations','The preserved A3 plan/stop/once and A2 once hashes are read from the fixed approved snapshot. A3 completed six original date operations, ended at128 with no pending uncertainty, and may not be replayed.'],
 ['source population','The final source depends on the exact old A3 source population plus fixed consumed evidence and three new authored files; no broad copy or added dependency is accepted. All112 review bindings match before/after and final recheck.'],
 ['original commands','Only the two original export commands/IDs are permitted; no new financial statement, date, journal, scenario, actor, MFA enrollment or grant is dispatched. Failed attempts are charged before dispatch and no command resend is present.'],
 ['MFA','The live wiring retains the unchanged existing-actor helper: real password sign-in, factor challenge/verify, server clock, online user and UUID session row. Writer/reopen sessions must differ; no constructed AAL claim is accepted. Synthetic test sessions are labelled controlled.'],
 ['evidence','Preflight management responses and read RPC responses are saved with query/response hashes before validation. Intent dispatch requires acknowledged encrypted private and public journals; result acknowledgement failure preserves pending identity.'],
 ['cancellation','Cancellation after dispatch permits only the one still-authorized read-only resolution; response and stop evidence can persist after abort. Exact deadline failures forbid all late requests/resolution, close the ports once, and allow bounded local evidence persistence independently for at most5s.'],
 ['mixed currency','The exact fixed pipeline ID/basis and ordered two rows retain LKR2000.125000/1000.062500 and USD1000.000001/333.300000. Number coercion, replacement IDs, merged currency or canonical-hash substitution is rejected.'],
 ['CSV','Only two exact filenames are written with exclusive wx, durable sync, bounded10MiB, real path/symlink checks, exact raw readback and the unchanged CSV codec. Saved-byte mutation blocks registration.'],
 ['reopen','Pipeline reopening uses the distinct session and exact canonical text/hash plus byte reproduction. Statement uses the original saved summary/ten rows and fresh page/preview reproduction; registered statement reopen is explicitly false.'],
 ['reconciliation','Before/after consolidate the exact115/363 baseline, seven function MD5s, original source hash, three dates, nine journals/eighteen lines, pipeline/statement/date digests, two exact jobs/receipts and only two original export event appends. Unrelated mutation fails.'],
 ['cleanup','The private startup is covered by try/finally; timer/abort, transport, seal key and config credential fields are cleared on startup or operation failure. The injected workflow closes once on success/failure/deadline and still exposes unavailable evidence honestly.']
].map(([area,conclusion])=>({area,conclusion,passed:true,basis:'Independent source inspection plus the hash-bound controlled cases where applicable.'}));
const reviewedAt=new Date().toISOString();
const report={kind:'independent-export-only-successor-source-review',reviewer:'/root/completion_peer',reviewedAt,
 technicalDecision:'approve additive source candidate for final operation review',sourceCandidateApproved:true,liveExecutionAuthorizedByThisReview:false,
 personalHumanExactSourceSignatureClaimed:false,authoredSources:verification.authoredSources,verification:verificationBinding,
 authoredProof:verification.authorProof,actualTests:{authored:54,independent:10,total:64,passed:64,failed:0,syntaxChecks:3},
 finalBindingsVerified:verification.sourcesAfter.length,all112BindingsUnchanged:true,checks,authority,
 sourcePreservation:{original150PlanAndConsumedIntentsRetained:true,original68SnapshotSourcesRetained:true,preservedInputCount:90,
  originalSharedAdapterHashIsHistorical:'99f9af0c2204ce7d745d125c6db724aaef3e2bbac1bf3c0f9f135e9df7489091',currentPublicAdapterAtReview:adapter,
  privateAdapterFinalDeltaRequiresSeparateRootReview:true},
 resolvedReviewFindings:[
  'Abort cannot discard pending-response or stop evidence.',
  'Setup does not reset the timer/call-gate start.',
  'Public population cannot contain added or duplicate files.',
  'Natural expiry closes ports and permits only a bounded local audit write.',
  'Actual a3 budget binding accepts its declared byte metadata and rejects mismatches.'
 ],
 preservedVerificationRecords:[
  {path:prefix+'independent-local-verification-a1.json',sha256:'f930c078fc2920c2a0de6a9e751ca42fe222acfa42a1cf234a10e2b007fde90b',meaning:'Initial spec-reporter output count parser recorded zero; the actual saved output was63/63.'},
  {path:prefix+'independent-local-verification-a2.json',sha256:'a92961a59c5ea424440c300a7d97535489f81ac2760fcd9691e891136da61586',meaning:'Count correction only, no rerun.'}
 ],
 runtimeExpiry:'2026-10-14T09:57:07.481942Z',runtimeExpiryExtended:false,
 executionStillRequires:['One actually recorded and charged fresh A10 readiness GET after source review.',
  'Actual A10 metadata/refresh/accounting and exact public profile bound into the generated snapshot plan.',
  'Root final independent operation review binding the exact plan/profile/current adapter delta before private read.',
  'Exclusive new intent and genuine execution entirely before original expiry; expired inputs fail closed.'],
 limitations:['This is source approval. Controlled Auth/SQL/socket values do not establish a genuine export or authenticated Windows acceptance.',
  'Momentary pg_stat_activity quiescence is not a continuing lock; immediate pre-registration checks and live-owner coordination remain necessary.',
  'No registered statement reopen, completed full-finance/cash gate, target-scale load, production release, or personal human signature follows.',
  'No future A10/profile artifact or successful operation was fabricated to pass tests; hypothetical values remained inside controlled fixtures.'],
 actualNetworkRequests:0,privateCredentialFilesRead:false,liveOrPrivateWrites:0,SDKJobs:0,existingSourcesEdited:0,
 authenticatedNative:false,targetScaleLoad:false,productionReleaseReady:false};
const file=prefix+'independent-source-review-a1.json',bytes=Buffer.from(JSON.stringify(report,null,2)+'\n');await fs.writeFile(path.join(root,file),bytes,{flag:'wx'});
const md=`The exact additive export source candidate passes independent source review. The final controlled run passed64/64 cases (54 author,10 peer) with3 syntax checks and112 unchanged source/evidence bindings. This review approves the source for a separate final operation review; it grants no live execution authority.\n\nThe candidate fixes cancelled stop persistence, a reset startup clock, extra public bindings and deadline-bound audit loss. After expiry it closes the transport and permits only a bounded local audit write. Ordinary requests still reserve90 seconds; the one conditional receipt resolution reserves45 seconds and never resends a command.\n\nThe exact pipeline keeps both LKR/USD decimal rows and the original statement/commands. All earlier date commands, three date decisions, hashes and consumed intents are preserved. The unchanged real MFA helper remains the live authentication path. The actual public a3 budget document was tested without replacing its bindings.\n\nThe owner still must record one charged A10 readiness GET, generate a plan from actual fresh metadata/profile, and obtain root review of the exact final plan and private adapter delta before opening private input. Original expiry remains **2026-10-14T09:57:07.481942Z**; no extension or expired execution is approved.\n\nControlled tests are not genuine export/native/load/release evidence. Registered statement reopen remains unverified. Historical test/failure/count-correction records are preserved.\n\nExact source hashes:\n\n${verification.authoredSources.map(row=>`- ${row.path}: ${row.sha256}`).join('\n')}\n\nReview JSON SHA256: ${hash(bytes)}. Verification JSON SHA256: ${verificationBinding.sha256}.\n`;
const mdFile=prefix+'independent-source-review-a1.md';await fs.writeFile(path.join(root,mdFile),md,{flag:'wx'});
console.log(JSON.stringify({sourceCandidateApproved:true,liveExecutionAuthorized:false,review:{path:file,sha256:hash(bytes),bytes:bytes.length},markdown:{path:mdFile,sha256:hash(md),bytes:Buffer.byteLength(md)},reviewedAt}));
