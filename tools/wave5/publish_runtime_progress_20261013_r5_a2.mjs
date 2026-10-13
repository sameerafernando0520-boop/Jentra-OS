import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {PROJECT,BUNDLE,loadApprovedInputs,decodePublicResult} from './approved_management_installer.mjs';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const must=(ok,code)=>{if(!ok)throw Error(code);};
const bindings={
 installation:{path:base+'approved-management-installation-20261013-r5-1791875214803/99-finish.json',sha256:'5f4b4612d51274765bc772b99c8c353194c6c500d786989addc7a2ad14bb9fbd'},
 installedMetadata:{path:base+'installed-management-verification-20261013-r5-1791877136909/99-result.json',sha256:'8c414bbe88c18336ac6f9a1d44d4d3cca9366249487da466c0ba4316acdd733e'},
 authProvisioning:{path:base+'auth-admin-provisioning-20261013-r5-1791877892653/99-result.json',sha256:'f8a67d9a2659bb4185d71c05c1a7644e5248e56c72fded4af297e3a2d3888abb'},
 genuineMfa:{path:base+'genuine-mfa-20261013-r5-1791878507585/99-result.json',sha256:'af4e9dec3987f5d6ba8c49fc1162be1374f93a14c043e46065119297a73e0bba'},
 bootstrap:{path:base+'exact-bootstrap-20261013-r5-1791879174385/99-result.json',sha256:'bfa415c72a62ef202d836de00fd94887bcbb414f5a6f02e4466a84bef21521d5'},
 sourceWorkflows:{path:base+'genuine-source-workflows-completed-20261013-r5-a3-1791883333161/99-result.json',sha256:'e71b6d78578ab5261d39243c493abdde045b0dddfe587486363190848b676428'},
 workerSource:{path:base+'worker-deployment-source-verification-20261013-r5.json',sha256:'a225a93f91800469b61e4893675aa9f85451cb1310b85263e39cf410b8f8a253'},
 persistentSetup:{path:base+'persistent-setup-actual-verification-20261013-r5-a3.json',sha256:'acfcf0b58bff2d3da4855612978395ba481e3d8cac76300d6086bca4d2ecfd4f'},
 activationRace:{path:base+'synthetic-activation-contention-20261013-r5-1791884748470/99-result.json',sha256:'cdb366e5c4c597d8379ecb86634dfae8674bbf5c96c0609af96fee86df8dcb4f'},
 leaseRecovery:{path:base+'genuine-delivery-lease-20261013-r5-1791885923843/99-result.json',sha256:'e35cf55c3f093a17416bf132e89783eb4e4a337c808eda69fd747238c2322076'},
 deliveryFixtures:{path:base+'actual-delivery-fixtures-20261013-r5-1791886204826/99-result.json',sha256:'a39892480eb4009eac5a3c6cbf0debbc1a74860eec63ceca5f39a65c240ddd79'},
 startSchedules:{path:base+'scheduled-delivery-start-20261013-r5-a4-1791889430942/99-result.json',sha256:'429087815ee06fe390245243ae5bda98ac942eebfb5477feed0f5e04b05b2ee6'},
 pauseSchedules:{path:base+'scheduled-delivery-pause-20261013-r5-1791889754523/99-result.json',sha256:'f10b6c67bbf7d33a9ed5f64c0ccd6bbb573a162dbab6383c11d36ad79e6dc2b4'},
 freshState:{path:base+'scheduled-delivery-paused-live-20261013-r5-a2.json',sha256:'4adb4fbbbd9d340ded212788e1a6b66c489763904e424c8d879271c6608021cd'},
 providerNode:{path:base+'runtime-node-tests-20261013-r5-a4.log',sha256:'00a3d9b6bdbe68002e73cb2a9466df0444632136ebeea3ea7530dccaa5954a21'},
 routingLocal:{path:base+'worker-routing-local-verification-20261013-r5.json',sha256:'48a2b9e073859fdbe512d9486c747a6e3d554abe4054404ba5677e4b805b7616'},
 routingReview:{path:base+'worker-routing-runtime-review-20261013-r5-a2.json',sha256:'7b5f7f62dba4cfb5557285dd08af5f7239b192295b5dce44f4175da748492968'},
 nativeValidation:{path:base+'native-profile-helper-validation-20261013-r5-a2.json',sha256:'393afebd8461022df58d62137136ae3515594f282452da41daad7ab188cea290'},
 matrixPreparation:{path:base+'requirement-status-preparation-20261013-r5.json',sha256:'926922d274ecc669bc0cc6d65ec772ce1266f06829b212f7174b51d7f7428fe8'}
};
await loadApprovedInputs();
const records={};
for(const [kind,b]of Object.entries(bindings)){
 const bytes=await fs.readFile(path.join(root,b.path));must(hashBytes(bytes)===b.sha256,'EXACT_PROGRESS_EVIDENCE_REQUIRED');
 records[kind]=kind==='providerNode'?bytes.toString('utf8'):JSON.parse(bytes);
}
const canonicalSha='298f767d74ff1e1913e19fce5fc9b79f76dc57da05666b5418355af0ab48b887';
const historical=records.matrixPreparation.preservedRows;
must(historical.length===109&&hashBytes(JSON.stringify(historical))===canonicalSha,'EXACT_109_ROWS_REQUIRED');
const accepted=historical.filter(r=>r.ownerAccepted).map(r=>r.id).sort();
must(JSON.stringify(accepted)===JSON.stringify(['AC-551','AC-552','AC-553']),'OWNER_ACCEPTANCE_CHANGED');
const live=decodePublicResult(records.freshState)[0].snapshot;
must(live.migrationCount===114&&live.apiFunctionCount===363&&live.ownJobs.length===3&&live.ownJobs.every(j=>j.active===false)
 &&live.netResponseCount===18&&live.allKnownHandler404===true&&live.ticks===0&&live.deliveryOutcomes===0&&live.receiverReceipts===0
 &&live.quotaPeriods===0,'ACTUAL_PAUSED_DELIVERY_STATE_REQUIRED');
must(Date.now()-Date.parse(live.observedAt)<3600000&&Date.now()-Date.parse(live.observedAt)>-10000,'FRESH_PROGRESS_READ_REQUIRED');
must(records.sourceWorkflows.passed&&records.sourceWorkflows.scopesVerified===500&&records.sourceWorkflows.actualScopedForecastReads===500
 &&records.sourceWorkflows.actualScopedProcessReads===500&&records.workerSource.deployedWorkerSource===true
 &&records.persistentSetup.passed&&records.activationRace.passed&&records.leaseRecovery.passed&&records.deliveryFixtures.passed,'ACTUAL_NARROW_RUNTIME_CASES_REQUIRED');
must(/# tests 148\s/.test(records.providerNode)&&/# pass 148\s/.test(records.providerNode)&&/# fail 0\s/.test(records.providerNode)
 &&records.routingLocal.tests===105&&records.routingLocal.failed===0&&records.routingLocal.deno.runtimeExitCode===0
 &&records.routingLocal.deno.receiverExitCode===0,'FRESH_LOCAL_TEST_OUTPUT_REQUIRED');
for(const b of records.routingLocal.testedSource)must(hashBytes(await fs.readFile(path.join(root,b.path)))===b.sha256,'WORKER_TESTED_SOURCE_CHANGED');
must(records.routingReview.bundleSha256==='bce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552'
 &&records.routingReview.ownerApproved===false&&records.routingReview.livePostPatchVerified===false,'UNAPPROVED_CANDIDATE_REQUIRED');
const publishedAt=new Date().toISOString();
const gates={originalSixInstallationComplete:true,new71MigrationInstallationComplete:true,installedSqlMetadataVerified:true,
 sixGenuineAuthAdminAccounts:true,realMfa:true,exact500CompanyBootstrapPersisted:true,
 genuineNonempty500ScopePipelineReads:true,genuineNonempty500ScopeProcessReads:true,
 actualAccountingPosting:false,authoritativeCashDateWorkflows:false,scenarioRecovery:false,actualGovernedExports:false,
 reviewedWorkerV1Deployed:true,reviewedVaultAndSchedulesInstalled:true,scheduledHttpAttemptObserved:true,schedulesCurrentlyPaused:true,
 actualWorkerDelivery:false,actualTrustedModelUsage:false,
 genuineSyntheticActivationCasePassed:true,genuinePendingLeaseAndMfaRecoveryCasePassed:true,
 allIndependentContentionCasesPassed:false,privateProviderCoordinatorPassed:false,fullExternalTransportObserverAvailable:false,
 targetScale2000SessionLoad:false,authenticatedNative:false,nativeKeyboard:false,
 all109OwnerCriteriaAccepted:false,ownerSignoff:false,wholeSystemAccepted:false};
const next={
 shared:'Complete genuine nonempty/denied business workflows, receipt/audit checks and all scope isolation cases.',
 process:'Retain AC-551/552/553 acceptance; extend the genuine 500-scope source reads to all required process-provider cases and native workflows.',
 pipeline:'Genuine 500-scope generation/readbacks passed. Finish historical realized results, additional boundaries and native forecast review; independently reconcile prior-command preservation labels.',
 finance:'Genuine statement/classification and nonempty synthetic source fixtures, governed export creation/download/hash/reopen, and separately authorized posting proof remain open. Existing runtime roles lack journals.post.',
 cash:'Exercise authoritative payroll/correction/project-reimbursement payment dates, settlements/reversals, all five families and immutable scenarios/recovery.',
 ai:'Private reviewed model-key input and at most four bounded genuine invocations; verify trusted sources/numerics, usage and distinct human approval/execution.',
 integration:'Resolve the actual 18 NOT_FOUND responses with the independently reviewed exact candidate after source approval; resume only the three existing bounded schedules and prove real signed delivery, rotation, restart, reconciliation, replay and quotas.',
 billing:'Synthetic activation case passed with two independent TLS connections. Complete quota/admission/seat races, preserving plan and membership history; real billing stays excluded.',
 operator:'Issue exact short-lived operator authority just before the genuine MFA operator phase; complete health/revocation evidence.',
 native:'Human UAC/private password is still pending for the approved separate Windows profile. Then inspect real Connected workflows, keyboard, actor switch, restart and revocation.',
 provider:'Local 148 checks passed after actual-response/private-config fixes. Complete independent review, verified private PostgreSQL access and full-window external transport observations; narrow TLS cases do not certify the coordinator.',
 ownership:'Obtain exact owner decisions against complete requirement statements and evidence; retain only AC-551/552/553 acceptance until new decisions arrive.',
 quality:'Preserve the original 83 plus eight later approved images and historical 2010/0/0 desktop result. Fresh analysis/tests/build/render checks are required after application source edits.',
 load:'Run all reviewed contention cases and the 500-company/2000-distinct-genuine-session load protocol; 500 source reads with two genuine sessions do not satisfy this gate.'
};
const currentRows=historical.map(r=>({id:r.id,bundle:r.bundle,ownerAccepted:r.ownerAccepted,
 currentDisposition:r.ownerAccepted?'Explicit owner acceptance preserved.':'Owner acceptance remains open.',
 currentFoundation:'114 migrations / 363 API functions; six genuine actors/MFA, exact500-company bootstrap, 500 pipeline/process source reads, installed worker v1/Vault/schedules.',
 userWorkflowAcceptance:r.ownerAccepted,nextEvidence:next[r.bundle]}));
const checkpoint={kind:'current-actual-runtime-successor',publishedAt,projectId:PROJECT,approvedSetupBundleSha256:BUNDLE,
 liveObservedAt:live.observedAt,migrationsInstalled:114,apiFunctions:363,approvedAdditionalMigrationsInstalled:71,
 originalSixReplayed:false,original43LedgerEntriesPreserved:true,
 installedMetadata:{functionBodiesMatched:541,tablesPresent:215,forcedRlsPredicates:72,exactGrantPredicates:18,priorProviderIdentities:121},
 syntheticSetup:records.bootstrap.actualScopedCounts,
 genuineSourceWorkflowEvidence:{scopes:500,forecastReads:500,processReads:500,genuineAal2Sessions:2,realForeignDenial:true,realWideWindowDenial:true,
  sourceFixtureType:'Bounded synthetic CRM and process rows seeded administratively; API generation and reads use genuine actors.',
  independentPriorCommandPreservationAudit:'Pending. Earlier failures and response records are preserved.'},
 localVerification:{providerNodeTests:148,workerNodeTests:105,freshDenoEntrypoints:2,allPassed:true,privateProviderVerdict:false,
  applicationSourceEdited:false,flutterJobsRun:false},
 persistentRuntime:{deployedFunctions:2,version:1,returnedModulesMatched:20,compilerConfigurationsReturned:false,
  vaultSecretIdentities:3,keyReferences:2,existingTestSchedules:3,
  scheduledHttpResponses:18,allResponsesHandlerNotFound:true,workerTicks:0,deliveryOutcomes:0,receiverReceipts:0,quotaPeriods:0,
  jobs:live.ownJobs,candidateBundle:records.routingReview.bundleSha256,candidateDeployed:false,candidateApproved:false,independentReviewPending:true},
 narrowContention:{syntheticActivation:true,pendingDeliveryLease:true,genuineMfaRecovery:true,allRequiredCasesPassed:false,
  privatePostgresDriverVerified:false,externalModelOrDeliveryTransportCounts:null},
 native:{helperReadOnlyValidationPassed:true,provisioningConfirmed:false,authenticated:false,keyboardVerified:false,
  pending:'Human UAC response and private Windows password entry; user reply do the best thing is not a provisioning result.'},
 ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,acceptedCriterionIds:accepted,
 privateDatabaseAndModelInputReady:false,gates,evidence:bindings,
 excluded:{production:true,realBilling:true,unconfirmedExistingAccountDeletion:true},
 preservation:'All 5539 original approved review inputs and 109 historical requirement rows verified unchanged; older reports and failures retained.'};
const matrix={kind:'current-requirement-readiness-successor',publishedAt,projectId:PROJECT,approvedSetupBundleSha256:BUNDLE,
 requirementCount:109,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,acceptedCriterionIds:accepted,
 canonicalHistoricalRowsSha256:canonicalSha,preservedRowsAreHistorical:true,
 historicalRowWarning:'Preserved developmentStatus prose predates installation. CurrentRows and this dated checkpoint carry current gates.',
 preservedRows:historical,currentRows,gates,evidence:bindings,production:false,realBilling:false,wholeWaveComplete:false};
async function save(file,value){const bytes=typeof value==='string'?value:JSON.stringify(value,null,2)+'\n';
 const handle=await fs.open(path.join(root,file),'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:file,sha256:hashBytes(bytes)};}
const checkpointBinding=await save(base+'approved-runtime-progress-checkpoint-20261013-r5-a2.json',checkpoint);
const matrixBinding=await save(base+'requirement-readiness-matrix-20261013-r5-a2.json',matrix);
const esc=s=>String(s).replaceAll('|','\\|').replaceAll('\n',' ');
const mdBinding=await save(base+'requirement-readiness-matrix-20261013-r5-a2.md',
 `Current evidence published ${publishedAt}; live read ${live.observedAt}. Owner acceptance is **3/109**: AC-551, AC-552 and AC-553. Other 106 remain open.\n\n`+
 'The 114 migrations / 363 API functions, 500 source workflows, local tests, installed workers, actual failed delivery transport, native testing, full contention/load and owner decisions are separate gates. Historical rows are preserved in JSON.\n\n'+
 '| Requirement | Bundle | Owner accepted | Current gate and next evidence |\n|---|---|---|---|\n'+
 currentRows.map(r=>`| ${r.id} | ${r.bundle} | ${r.ownerAccepted?'Yes':'No'} | ${esc(r.nextEvidence)} |`).join('\n')+'\n');
const statusBinding=await save('docs/development/wave5-status-20261013-r5-a2.md',
 `Jentra OS remains incomplete. Fresh live state at ${live.observedAt} is **114 migrations / 363 API functions**. All 71 additional approved migrations are installed; the original 43 ledger entries and six earlier Wave 5 migrations were preserved.\n\n`+
 'Installed verification matched 541 reviewed function bodies and 215 tables, with 72 forced-RLS and 18 exact-grant checks. Six confirmed accounts were created through genuine Auth Admin; all six passed genuine TOTP/AAL2 and online/server session checks. The exact 500-company setup was committed after a clean rollback probe. Original accounts and sessions are preserved.\n\n'+
 'Nonempty synthetic CRM and process fixtures were seeded within the reviewed scopes. Genuine actor calls generated/read forecasts and read process results across all 500 scopes, including foreign-scope and wide-window denials. This used two genuine sessions and proves those source workflows. Prior-command preservation labels are under independent audit; earlier unsuccessful attempts remain preserved. It does not prove accounting journal posting or the 2000-session load protocol.\n\n'+
 'The two reviewed version-1 workers are deployed; all 20 returned source modules match their approved bytes. Three Vault secret identities, two key references and three expiring test schedules are installed. A genuine delivery fixture has four receiver paths. Two independent trusted-TLS activation requests proved one synthetic activation/version increment; two independent delivery claims proved one lease, natural expiry and genuine MFA recovery. Full contention/provider acceptance remains open.\n\n'+
 '**Actual scheduled delivery failed:** all 18 completed HTTP requests returned the handler NOT_FOUND response. No worker tick, delivery outcome, receiver receipt or quota period was created. Exact jobs 4, 5 and 6 are paused. A separate routing candidate passed 105 worker checks and two fresh Deno entrypoint checks, preserves original custom authentication and recognizes the documented function-name path. It is not deployed or owner-approved; independent review is pending. The internal request path diagnosis remains an inference until verified live.\n\n'+
 'The provider suite passed 148 local checks after fixes grounded in actual API responses and private configuration reference snapshots. This is local evidence; the full private provider coordinator, verified PostgreSQL driver, complete external transport observation and 500-company/2000-session load gate remain open. The private model key is absent, and no actual model use is claimed.\n\n'+
 'The isolated Windows helper passed normal-owner validation against 1068 application inputs and 34 Connected release files. The standard Windows account/package were absent at that check. Human UAC and hidden password steps are pending; do the best thing is not a created-profile report. Authenticated native and native keyboard remain unverified. No application source edit or Flutter job occurred during these helper/worker candidate changes.\n\n'+
 'Owner acceptance is **3/109**: AC-551, AC-552 and AC-553. The original 83 golden failures and eight later image decisions were resolved in preserved October 10 evidence (2010 passed, 0 failed, 0 skipped). No new baseline replacement occurred. Finance/cash dates/scenarios/recovery, actual governed exports/delivery/model usage, full contention/load, native checks and the other 106 owner decisions remain open.\n\n'+
 'Production and real billing stay excluded. No reset, clean, broad staging, commit or push occurred. Every frozen approval input and all109 historical matrix rows were verified unchanged.\n\n'+
 'Current evidence: [checkpoint](../verification/wave5/approved-runtime-progress-checkpoint-20261013-r5-a2.json), [matrix](../verification/wave5/requirement-readiness-matrix-20261013-r5-a2.md), [routing review](../verification/wave5/worker-routing-runtime-review-20261013-r5-a2.json), [native private handoff](../verification/wave5/native-profile-private-handoff-20261013-r5.md).\n');
const handoffBinding=await save('docs/development/wave5-next-session-20261013-r5-a2.md',
 `Continue Jentra OS at C:\\Users\\sheha\\Desktop\\Jentra OS, project ${PROJECT}. Read wave5-status-20261013-r5-a2.md and checkpoint/matrix evidence first. Fresh published live state:114 migrations/API363, original6/43 preserved; all71 additional installed. Do not replay migrations/accounts/factors/bootstrap/nonce intents.\n\n`+
 'Exact original setup approval db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b remains valid for its bound bytes. The owner explicitly authorized the existing Windows-encrypted owner token; never print or request another token merely because historical plugin errors occurred. Ready a3 expires 2026-10-13T12:59:06.909Z; preserve UTC/DateKind String guards and renew by fresh same-project/org reads when necessary. Private database/model inputs remain pending.\n\n'+
 'Six genuine actors/AAL2, exact500-company bootstrap and nonempty CRM/process source reads across all500 are proved. Synthetic activation and one pending lease/MFA recovery are narrow cases only. Agent provider review is auditing prior-command preservation labels; preserve earlier failed attempts and actual response envelopes.\n\n'+
 'Workers v1/Vault3/keyrefs2/schedules3 installed. Actual18 scheduled HTTP responses all NOT_FOUND, worker ticks/outcomes/receiver receipts/quota0. Exact jobs4/5/6 paused; do not resume old once-only intents blindly. New routing candidate bundle bce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552 is unapproved and undeployed. Review payloads a2 contain15 runtime/9 receiver bound files, 105 Node checks and2 fresh Deno checks. Obtain independent review and concrete owner source decision before replacing only these2 functions; then independently read returned sources and resume only the original3 jobs within original expiry/caps. No spending/user/SQL/grant/destination expansion.\n\n'+
 'The original three agents resumed after the stated16:54SL reset: provider_review_20261013 reviews routing/provider evidence; runtime_provider_20261013 prepares permitted finance/cash helpers; native_matrix_20261013 audits exact native prerequisites. Root serializes private writes and publishes successor status/matrix.\n\n'+
 'Native helper validated; user replied do the best thing to human UAC/password request, not created. Computer Use forbids auth/UAC automation. Preserve existing sessions and await a private human setup result. Do not call native keyboard/authenticated native verified.\n\n'+
 'Continue real finance/classification/cashdates/scenarios/recovery/governedexports, actualdelivery/model max4calls, allcontention cases, privatePg fullprovider/fullobserver and500companies/2000genuine distinct sessions. Runtimeroles lack journals.post; do not invent grants or promote admin sourcefixtures to user journal posting.\n\n'+
 'Preserve concurrent W3/W4/Employee changes, acceptance stores, session stores and all5539 approved inputs. No reset/clean/stash/broadstage/commit/push. Serialize heavy Flutter checks; appsourceedits require fresh analysis/tests/build/render evidence. Golden83+8 accepted/resolved; owner acceptance ONLY AC551/552/553 =3/109. Production/realbilling excluded.\n');
must(hashBytes(JSON.stringify(matrix.preservedRows))===canonicalSha,'HISTORICAL_ROWS_CHANGED');
await loadApprovedInputs();
process.stdout.write(JSON.stringify({published:true,currentLiveRead:live.observedAt,all109HistoricalRowsPreserved:true,
 ownerAcceptedCriteria:3,actualWorkerDelivery:false,schedulesPaused:true,candidateApproved:false,
 checkpoint:checkpointBinding,matrix:matrixBinding,matrixMarkdown:mdBinding,status:statusBinding,handoff:handoffBinding})+'\n');
