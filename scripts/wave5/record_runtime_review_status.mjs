import {readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const read=async p=>readFile(path.join(root,p),'utf8');
const json=async p=>JSON.parse(await read(p));
const write=async(p,s)=>writeFile(path.join(root,p),s.trimEnd()+'\n');
const review=await json(base+'runtime-review-20261009.json');
const cash=await json(base+'cash-dates-verification-20261009.json');
if(review.ownerApproved||review.evidence.realMfa||!cash.current_source_match||!cash.buildSucceeded||cash.frames.length!==60||!cash.visualReview.passed)throw Error('EVIDENCE_BOUNDARY_CHANGED');
const matrixPath=base+'requirement-matrix-20261008.json';
const matrix=await json(matrixPath);
if(matrix.rows.length!==109||matrix.rows.some(r=>r.ownerAccepted)||matrix.wholeWaveComplete)throw Error('ACCEPTANCE_CHANGED');
const description=`October 9 scoped Dart analysis is clean; ${cash.stages.domainTests.assertions} domain, ${cash.stages.platformTests.assertions} platform and ${cash.stages.nativeTests.assertions} desktop/controller/render tests pass. The Windows release matches all ${cash.sourceFileCount.toLocaleString('en-US')} selected desktop dependency source files and ${cash.releaseFileCount} release files, including current workspace dependency manifests. Sixty fresh cash frames were captured at twelve viewport/theme/density variants with 200% text; ${cash.visualReview.inspectedFrames.length} were visually inspected. Initial Tab focus was checked. These are controlled renders; authenticated native acceptance and full keyboard navigation remain open.`;
await write(base+'cash-dates-verification-20261009.md',[
 '# Current cash UI verification - October 9, 2026','',description,'',
 'The root pubspec added the concurrent employee app after the previous cash build. A new immutable copy in `build/w5rt9` includes every declared workspace member. Dependency resolution, analysis, focused tests and the Windows build ran serially there. Existing source files, earlier builds, approved goldens and acceptance-owned stores were preserved.','',
 `The full-workspace comparison is ${cash.workspace_source_match}; ${cash.workspaceSourceChangesSinceSnapshot.length} employee-app files changed during the run. The build attribution follows the desktop's transitive workspace dependencies and includes every workspace dependency manifest. Employee application code is outside that dependency graph and has no desktop import. The [initial whole-workspace result](cash-dates-workspace-drift-20261009.json) is retained; all desktop source, manifests, lockfile and release bytes match. No employee file was overwritten or copied back.`,'',
 '| Verification | Result |','|---|---|',
 '| Dependency resolution / scoped Dart analysis | Passed / no issues |',
 `| Domain / platform / desktop tests | ${cash.stages.domainTests.assertions} / ${cash.stages.platformTests.assertions} / ${cash.stages.nativeTests.assertions} passed |`,
 `| Selected source / release hashes | ${cash.sourceFileCount} / ${cash.releaseFileCount} match |`,
 '| Fresh renders | 60 frames; 16 inspected; all 12 approval variants |',
 '| Authenticated native, installed new providers, real MFA, worker delivery, contention/load, owner acceptance | Open |','',
 'The full [machine evidence](cash-dates-verification-20261009.json) records commands, times, hashed logs, source/release/frame hashes and exact inspection paths. [Run metadata](cash-dates-run-20261009.json) records the twelve viewport/theme/density variants. Flutter 3.47.5 / Dart 3.13.4 were verified from the local SDK cache. An initial restricted dependency attempt was stopped; successful jobs had SDK/package cache access.','',
 'At 200% text, the reviewed digest wraps at 1024x720 and approve/reject controls remain visible. The inspected source/date/reason/proposal/recovery controls remain readable. All-five-family availability and closing cash 4.000003 are controlled fixture values; unavailable-provider cards and injected sessions do not establish installed features. Full authenticated keyboard/restart/revocation/export checks remain open.','',
 'No native executable was launched, profile provisioned, installer created or approved golden regenerated. The 13 shared dashboard/setup failures remain open. The [runtime review](runtime-review-20261009.md) specifies the distinct real-session and isolated-profile gates.'
 ].join('\n'));
if(process.argv[2]==='cash-only'){console.log(JSON.stringify({cashVerification:base+'cash-dates-verification-20261009.md',sourceMatch:true}));process.exit(0);}
const statuses={
 shared:'Installed Wave 5 foundation remains intact. The exact new 28-file dependency closure passes 63 strict rollback assertions; all new candidates remain uninstalled.',
 ai:'Numeric-only redaction, strict model output/counting and trusted usage adapters are candidates. The scoped runtime persists a four-invocation limit; model/provider configuration is specified for approval. No real model call occurred.',
 integration:'Candidate storage, key/credential revocation, outbox leases/attempts/replay, atomic throttle/quota and dispatch are implemented. The runtime guard scopes expiry/discovery/claim/settlement before mutation; 38 controlled worker tests pass.',
 billing:'Installed synthetic authority remains intact. Confirmed billing-admin label, exact new plans/seats/quotas and a tenant-scoped scheduler are prepared in the runtime review; no activation occurred.',
 operator:'Installed operator isolation remains intact. The confirmed separate operator has proposed exact-tenant/reason authority limited to 45 minutes and a grant guard; no operator or grant was provisioned.',
 ownership:'Fresh October 9 live reads retain 43 migrations, 107 API functions and unchanged access counts. All 28 new migration hashes are reviewed; eight Wave 4 owned sources remain byte-preserved. No new file is installed.',
 quality:`The 28-file composition passes 63 strict rollback assertions and the separate synthetic mapping probe passes 10; 38 controlled worker tests pass. ${description}`,
 native:`Seven analytics workspaces and cash payment dates are implemented. ${description}`,
 load:'Candidate SQL verifies bounded inputs and atomic policy behavior in rollback. The review specifies 500 synthetic tenants and 2,000 real independent sessions; no contention or target-scale run has occurred.'
};
const remaining={
 shared:'Bind owner-controlled host/receiver and approve the exact runtime package before new installation/bootstrap. Real source access, scope/revocation and distinct MFA evidence remain open.',
 ai:'Final bound approval and private host/provider injection remain required. Prove actual usage, distinct real MFA approval, stale-cohort rejection, revocation, overlapping execution and unknown-outcome reconciliation.',
 integration:'Final host/receiver binding and approval precede installation/provisioning/deployment. Signed delivery, receiver idempotency, key rotation/revocation, restart, dead letters/reviewed replay and real independent-session races remain open.',
 billing:'Final bound approval precedes the exact synthetic bootstrap/activation. Real quota/seat/admission/activation races and trusted usage settlement remain open; real billing is excluded.',
 operator:'Final bound approval precedes creation of the separate operator and real MFA grant. Exact scope, owner denial, expiry, health probes and immutable access audit remain unverified.',
 ownership:'Keep all 28 candidates uninstalled until final bound approval. Preserve acceptance stores and concurrent sources; never replay the six connector-mapped installed migrations.',
 native:'Provision the chosen new standard Windows profile only after final approval; use a freshly attributed ordinary runtime build. Real login/MFA, exports/reopen/restart/revocation, full keyboard navigation, 13 shared golden failures and owner review remain open.',
 quality:'The original 126 installed SQL checks were not rerun. Candidate, mapping and controlled UI/worker evidence remain separate from installed/authenticated/native/delivery/contention/load gates. Keep all 13 shared golden failures and zero owner acceptance visible.',
 load:'After final bound approval and exact synthetic setup, record real session identities, barrier overlap, committed effects, hardware/distributions and target-scale p95. Sequential rollback replay and injected claims cannot close this gate.'
};
let md=await read(base+'requirement-matrix-20261008.md');
for(const r of matrix.rows){
 if(statuses[r.bundle]){md=md.replaceAll(r.developmentStatus,statuses[r.bundle]);r.developmentStatus=statuses[r.bundle];}
 if(remaining[r.bundle]){md=md.replaceAll(r.remaining,remaining[r.bundle]);r.remaining=remaining[r.bundle];}
 for(const p of [base+'runtime-review-20261009.md',base+'runtime-review-live-after-20261009.json'])if(!r.evidence.includes(p))r.evidence.push(p);
}
matrix.updatedAt=new Date().toISOString();
matrix.runtimeReview={path:base+'runtime-review-20261009.md',manifest:base+'runtime-review-20261009.json',bundleSha256:review.bundleSha256,
 approvalReady:review.approvalReady,ownerApproved:false,pendingBindings:review.pendingBindings,migrations:28,confirmedAccounts:6,
 nativeTarget:review.workerConfiguration.nativeIsolation.target,nativeProvisioned:false,liveAfter:base+'runtime-review-live-after-20261009.json',
 strictCandidateAssertions:63,strictMappingAssertions:10,controlledWorkerTests:38,newInstalled:false,realMfa:false,actualModelUsage:false,ownerSignoff:false};
matrix.continuationChecks.workerLastVerified=38;
matrix.continuationChecks.workerEvidence=base+'runtime-worker-tests-20261009.json';
matrix.continuationChecks.runtimeCandidateSql=63;
matrix.continuationChecks.runtimeCandidateSqlScope='Actual 28-file Wave 3/4/5 composition, strict finish, rollback; injected policy claims';
matrix.continuationChecks.bootstrapMappingSql=10;
matrix.continuationChecks.bootstrapMappingSqlScope='Separate rolled-back relational mapping with test-only Auth shapes/permission registration; not real Auth';
matrix.continuationChecks.cashUiVerification=base+'cash-dates-verification-20261009.json';
matrix.continuationChecks.sourceFileCount=cash.sourceFileCount;
matrix.continuationChecks.sourceVerifiedAt=cash.capturedAt;
matrix.continuationChecks.currentSourceScope=cash.sourceAttributionScope;
matrix.continuationChecks.wholeWorkspaceSourceMatch=cash.workspace_source_match;
matrix.installationCompleteScope='Original six owner-approved Wave 5 migrations only';
matrix.newRuntimeInstallationComplete=false;
const firstEnd=md.indexOf('\n\n| ID');
if(firstEnd<0)throw Error('MATRIX_LAYOUT_CHANGED');
md='# Wave 5 requirement matrix - updated October 9, 2026\n\nAll 109 identifiers remain mapped with **zero owner-accepted criteria**. Fresh live reads retain 43 migrations and 107 API functions. The [concrete runtime review](runtime-review-20261009.md) enumerates 28 uninstalled migration hashes, six confirmed labels, exact new synthetic roles/plans, operator limits and worker/provider configuration. Host/receiver binding and final approval remain pending. The new standard Windows profile `jentra-w5-runtime` is selected but uncreated.\n\nThe full candidate composition passes 63 strict rollback checks, the separate bootstrap mapping probe passes 10, and 38 controlled worker tests pass. Test-only claims/Auth shapes/transports do not establish real MFA or delivery. The original 126 installed checks and historical 116/35 rollback checks retain their distinct scopes. [Post-rollback live read](runtime-review-live-after-20261009.json).\n\n'+description+' [Fresh cash verification](cash-dates-verification-20261009.md). Installed new SQL, authenticated native/MFA/export, actual worker/model delivery, independent-session contention, target-scale load and owner signoff remain open.'+md.slice(firstEnd);
await write(matrixPath,JSON.stringify(matrix,null,2));
await write(base+'requirement-matrix-20261008.md',md);
for(const p of ['docs/development/wave5-status.md',base+'integrated-runtime-protocol-20261006.md']){
 let text=await read(p);
 const prefix=text.match(/^(?:Current-source|October 9) scoped Dart analysis is clean;/m)?.[0];
 const start=prefix?text.indexOf(prefix):-1,end=text.indexOf('\n\n',start);
 if(start<0||end<0)throw Error('SDK_STATUS_PARAGRAPH_CHANGED');
 text=text.slice(0,start)+description+' [Fresh cash verification]('+ (p.startsWith('docs/development/')?'../verification/wave5/':'')+'cash-dates-verification-20261009.md). The 13 shared dashboard/setup golden failures remain open; no approved golden was regenerated.'+text.slice(end);
 await write(p,text);
}
console.log(JSON.stringify({requirements:109,accepted:0,waveComplete:false,runtimeReview:matrix.runtimeReview.path,bundleSha256:review.bundleSha256}));
