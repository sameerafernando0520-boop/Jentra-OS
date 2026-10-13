import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const bindings={
 installation:{path:base+'approved-management-installation-20261013-r5-1791875214803/99-finish.json',sha256:'5f4b4612d51274765bc772b99c8c353194c6c500d786989addc7a2ad14bb9fbd'},
 installedMetadata:{path:base+'installed-management-verification-20261013-r5-1791877136909/99-result.json',sha256:'8c414bbe88c18336ac6f9a1d44d4d3cca9366249487da466c0ba4316acdd733e'},
 authProvisioning:{path:base+'auth-admin-provisioning-20261013-r5-1791877892653/99-result.json',sha256:'f8a67d9a2659bb4185d71c05c1a7644e5248e56c72fded4af297e3a2d3888abb'},
 genuineMfa:{path:base+'genuine-mfa-20261013-r5-1791878507585/99-result.json',sha256:'af4e9dec3987f5d6ba8c49fc1162be1374f93a14c043e46065119297a73e0bba'},
 bootstrap:{path:base+'exact-bootstrap-20261013-r5-1791879174385/99-result.json',sha256:'bfa415c72a62ef202d836de00fd94887bcbb414f5a6f02e4466a84bef21521d5'},
 privateAccess:{path:base+'runtime-access-investigation-20261013-r5-1791879588405.json',sha256:'816a800efb43482094c44a64b70e997354691f8e78654d48422cf2cdc22b361e'},
 matrixPreparation:{path:base+'requirement-status-preparation-20261013-r5.json',sha256:'926922d274ecc669bc0cc6d65ec772ce1266f06829b212f7174b51d7f7428fe8'},
 providerLocal:{path:base+'supabase-provider-local-verification-20261013-r5-a20.json',sha256:'ab513caba4d03dc5f0d2ff764ab64545ba72966d671bf5deb3456f624311fd1e'},
 peerAuthoredLocal:{path:base+'independent-provider-local-verification-20261013-r5-a4.json',sha256:'b8738d50cbefd74949c2c1abab8f86ae1a1bf4fa1cd5711b0a4eb4286e2a8722'}
};
const must=(ok,code)=>{if(!ok)throw Error(code);};
const records={};
await loadApprovedInputs();
for(const [kind,binding]of Object.entries(bindings)){const bytes=await fs.readFile(path.join(root,binding.path));
 must(hashBytes(bytes)===binding.sha256,'ACTUAL_PROGRESS_EVIDENCE_CHANGED');records[kind]=JSON.parse(bytes);}
const prep=records.matrixPreparation,canonicalSha='298f767d74ff1e1913e19fce5fc9b79f76dc57da05666b5418355af0ab48b887';
must(prep.preservedRows.length===109&&hashBytes(JSON.stringify(prep.preservedRows))===canonicalSha,'EXACT_109_ROWS_REQUIRED');
const accepted=prep.preservedRows.filter(row=>row.ownerAccepted).map(row=>row.id).sort();
must(JSON.stringify(accepted)===JSON.stringify(['AC-551','AC-552','AC-553']),'OWNER_ACCEPTANCE_CHANGED');
must(records.installation.actualLedgerCount===114&&records.installedMetadata.passed&&records.installedMetadata.catalog.apiFunctions===363
 &&records.authProvisioning.accountsCreated===6&&records.authProvisioning.passed&&records.genuineMfa.genuineMfaVerifiedActors===6
 &&records.genuineMfa.passed&&records.bootstrap.bootstrapPersisted&&records.bootstrap.passed,'ACTUAL_PROGRESS_REQUIRED');
const now=new Date().toISOString();
const gates={sourceImplementation:'Existing reviewed application source preserved; runtime-provider local work is separately verified.',
 originalSixInstallationComplete:true,new71MigrationInstallationComplete:true,installedSqlMetadataVerified:true,
 sixGenuineAuthAdminAccounts:true,realMfa:true,exactSyntheticBootstrapPersisted:true,
 installedBusinessWorkflowBehavior:false,authenticatedNative:false,nativeKeyboard:false,actualAccountingPosting:false,
 authoritativeReportsGenerated:false,actualGovernedExportDelivery:false,workersDeployed:false,schedulesInstalled:false,
 actualWorkerDelivery:false,actualTrustedModelUsage:false,independentSessionContention:false,targetScaleLoad:false,
 all109OwnerCriteriaAccepted:false,ownerSignoff:false,wholeSystemAccepted:false};
const checkpoint={kind:'actual-approved-runtime-progress-checkpoint',actualPublishedAt:now,projectId:PROJECT,bundleSha256:BUNDLE,
 actualLedgerCount:114,apiFunctionCount:363,additionalMigrationsInstalled:71,pendingApprovedMigrations:0,
 originalSixReplayed:false,original43LedgerEntriesPreserved:true,installedFunctionBodiesMatched:541,installedTablesPresent:215,
 forcedRlsPredicatesPassed:72,exactFunctionGrantPredicatesPassed:18,priorProviderIdentitiesChecked:121,
 existingAccessRowsPreserved:true,approvedOwnerPermissionAdditions:4,approvedDisabledEntitlementAdditions:4,
 genuineCreatedAccounts:6,genuineMfaVerifiedActors:6,syntheticBootstrapCounts:records.bootstrap.actualScopedCounts,
 installedSqlMetadataObservedAt:records.installedMetadata.catalog.observedAt,bootstrapFinishedAt:records.bootstrap.actualFinishedAt,
 actualOwnerAcceptedCriteria:3,remainingUnacceptedCriteria:106,acceptedCriterionIds:accepted,gates,evidence:bindings,
 privateInputsRequired:{databasePassword:true,openAiApiKey:true,temporaryAccessState:records.privateAccess.observations.temporaryAccess.state,
  modelKeyConfigured:records.privateAccess.observations.secretNames.modelKeyConfigured},
 historicalConnectorFailurePreserved:true,failedPreservationCheckPreserved:true,credentialsPrinted:false,
 excluded:{production:true,realBilling:true,existingAccountDeletionWithoutExactDirectConfirmation:true},
 preservation:'All frozen review/status/matrix/app artifacts remain unchanged. This is a new successor; historical counts are not current state.'};
const next={
 shared:'Run real permitted/denied API workflows across the reviewed scope and compare committed receipts and audit evidence.',
 process:'Complete nonempty authoritative process-provider and authenticated runtime cases; retain accepted AC-551 through AC-553.',
 pipeline:'Create bounded nonempty source fixtures, generate authoritative forecasts and verify replay, pagination and isolation.',
 finance:'Exercise actual statement/classification providers and governed finance exports with eligible genuine actors.',
 cash:'Exercise actual payroll/project payment dates, independent approvals, scenarios and recovery within reviewed caps.',
 ai:'Configure the private model key and run at most four bounded model invocations with trusted numeric/source and usage proof.',
 integration:'Deploy exact reviewed workers/receiver, register real MFA subscriptions, prove actual delivery and recovery with transport observations.',
 billing:'Run permitted synthetic activation and genuine admission/seat/quota races before usage buckets; exclude real billing.',
 operator:'Issue the exact short-lived authority immediately before the operator phase and capture the real MFA grant/health receipt.',
 native:'Provision the approved separate Windows profile; test connected workflows and native keyboard, preserving existing sessions.',
 provider:'Verify genuine nonempty provider behavior, source provenance, denial cases and complete external-effect observations.',
 ownership:'Present complete requirement statements with their exact evidence and obtain the owner decision; do not self-sign.',
 quality:'Keep the resolved approved goldens; collect fresh analysis/tests/build/render evidence after any application source edit.',
 load:'Supply private verified-TLS PostgreSQL access, obtain 2000 distinct genuine sessions and run the exact 500-company workload and contention cases.'
};
const currentRows=prep.preservedRows.map(row=>({id:row.id,bundle:row.bundle,ownerAccepted:row.ownerAccepted,
 currentDisposition:row.ownerAccepted?'Explicit owner acceptance preserved.':'Owner acceptance remains open.',
 installedFoundation:'71 approved migrations installed; metadata and genuine six-actor Auth/MFA plus exact 500-company bootstrap verified.',
 userWorkflowAcceptance:false,nextEvidence:next[row.bundle]}));
const matrix={kind:'current-requirement-readiness-successor',actualPublishedAt:now,projectId:PROJECT,bundleSha256:BUNDLE,
 requirementCount:109,ownerAcceptedCriteria:3,remainingUnacceptedCriteria:106,acceptedCriterionIds:accepted,
 canonicalHistoricalRowsSha256:canonicalSha,preservedRowsAreHistorical:true,
 historicalRowWarning:'The preserved developmentStatus prose predates actual approval/installation. Use currentRows and the fresh checkpoint for current state.',
 preservedRows:prep.preservedRows,currentRows,gates,evidence:bindings,production:false,realBilling:false,wholeWaveComplete:false};
async function save(file,value){const bytes=typeof value==='string'?value:JSON.stringify(value,null,2)+'\n';
 const handle=await fs.open(path.join(root,file),'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:file,sha256:hashBytes(bytes)};}
const checkpointBinding=await save(base+'approved-runtime-progress-checkpoint-20261013-r5.json',checkpoint);
const matrixBinding=await save(base+'requirement-readiness-matrix-20261013-r5.json',matrix);
const esc=value=>String(value).replaceAll('|','\\|').replaceAll('\n',' ');
const matrixMd=`Current evidence successor, published ${now}. Owner acceptance is **3/109**: AC-551, AC-552 and AC-553. The other 106 remain open. Historical rows remain byte-for-byte equivalent in the JSON; their older approval/install prose is explicitly historical.\n\n`+
 `| Requirement | Bundle | Owner accepted | Current gate and next evidence |\n|---|---|---|---|\n`+
 currentRows.map(row=>`| ${row.id} | ${row.bundle} | ${row.ownerAccepted?'Yes':'No'} | ${esc(row.nextEvidence)} |`).join('\n')+'\n';
const mdBinding=await save(base+'requirement-readiness-matrix-20261013-r5.md',matrixMd);
const status=`Jentra OS is still in development. The approved isolated setup has progressed to a live ledger of **114 migrations / 363 API functions**. All 71 additional approved migrations are installed; the original 43 entries and six earlier Wave 5 migrations were preserved.\n\n`+
 `Actual installed checks matched 541 reviewed function bodies and 215 tables, with 72 forced-RLS and 18 exact grant predicates. The initial all-row preservation check stopped because five approved migrations added four owner permissions and four disabled integration entitlements. A successor query proved exact additions and unchanged prior rows; both the failure and correction are retained. Three renamed helper bodies were captured immediately before migration 58 and preserved.\n\n`+
 `Six new confirmed users were genuinely created through Auth Admin. All six passed actual password sign-in, TOTP enrollment/challenge/verification, online Auth and server session/factor checks at AAL2. Credentials, seeds and tokens are held only in encrypted private records outside the repository. The original desktop account is preserved.\n\n`+
 `The exact bootstrap passed 12 structural assertions inside a clean rollback and was then committed. Fresh reads verified 500 tenants, 500 entities, 501 branches, 1997 memberships, 1003 roles, 2003 assignments, 500 subscriptions and four synthetic plans. Outside-scope access hashes stayed unchanged. This proves setup, not business workflow acceptance.\n\n`+
 `Owner acceptance remains **3/109**, with AC-551, AC-552 and AC-553 accepted. The other 106 remain open. The original 83 golden failures and eight later image decisions are resolved in the preserved October 10 desktop evidence (2010 passed, 0 failed, 0 skipped); no new baseline replacement occurred here. Native keyboard and authenticated native checks remain open. No application source or SDK job was changed or run during these Management API helper changes.\n\n`+
 `The provider suite has 101 passing local checks and 116 passing peer-authored local checks. Root executed the latter after the reviewer agent hit its account usage limit; this is not a completed independent private-provider verdict. Preserve the recorded earlier failures.\n\n`+
 `Next: private database access and model-key input, exact worker/receiver deployment and scoped Vault/schedules, nonempty authoritative source fixtures and real workflows, actual delivery/export/model usage, independent-session contention, 500-company/2000-session load, separate-profile native testing and owner decisions. Temporary token-based database access is currently **unavailable** and the reviewed model key is absent. Existing database passwords and project settings are not reset. The private input helper is prepared; it requests no new owner token.\n\n`+
 `Production and real billing remain excluded. No reset, clean, broad staging, commit or push occurred. Frozen source/review/status/matrix artifacts stay unchanged; these dated successor documents carry the fresh state.\n\n`+
 `Fresh evidence: [checkpoint](../verification/wave5/approved-runtime-progress-checkpoint-20261013-r5.json), [requirement matrix](../verification/wave5/requirement-readiness-matrix-20261013-r5.md), [private input note](../verification/wave5/private-runtime-inputs-20261013-r5.md).\n`;
const statusBinding=await save('docs/development/wave5-status-20261013-r5.md',status);
const handoff=`Continue Jentra OS at C:\\Users\\sheha\\Desktop\\Jentra OS, project ${PROJECT}. Read wave5-status-20261013-r5.md and the fresh approved-runtime-progress-checkpoint-20261013-r5.json first, then their referenced actual evidence.\n\n`+
 `The exact db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b setup is approved. All 71 additional migrations are installed: ledger114/API363. Never replay them or the original six. Preserve the old connector failures and the initial preservation failure; the approved additions have been independently reconciled against all preexisting row hashes.\n\n`+
 `Six genuine Auth Admin users, six genuine AAL2 actors and the committed exact 500-company bootstrap are complete. Account IDs, encrypted record references and public proofs are in the checkpoint bindings. Do not recreate users, reenroll factors or replay the bootstrap. Once-only intent files deliberately refuse this. Never INSERT auth.users or construct JWT/MFA claims.\n\n`+
 `The existing owner PAT is authorized and Windows-encrypted outside the repository. The private runner passes it through child stdin, never command text, output or builds. Its initial ready metadata expires two hours after import; before later use, perform a deliberate fresh owner/project check and publish a bounded metadata successor rather than disabling freshness guards. Database-password/model-key prompts are prepared separately. Do not ask for a new PAT or expose credentials.\n\n`+
 `Root took over after all three agents reported the account usage limit with retry time 15:40 Asia/Colombo. Resume native_matrix_20261013, provider_review_20261013 and runtime_provider_20261013 only when available, from their actual last files. No private-provider independent signoff exists.\n\n`+
 `Remaining gates are genuine nonempty workflows/providers, cash dates/scenarios/recovery, exports, exact workers/Vault/schedules and actual delivery/model usage, independent-session contention, exact500-company/2000-session load, separate-profile native and native keyboard, and106 owner decisions. Model calls are capped at4. Unavailable10001-row/8MiB/101-group boundary fixtures cannot be fabricated or promoted.\n\n`+
 `Preserve concurrent Wave3/4/Employee work and acceptance/session stores. No reset, clean, broad staging, commit or push. Serialize heavy Flutter checks and collect fresh source/analysis/test/build/render evidence after application edits. Keep all gates separate. Production and real billing remain excluded. Preserve all109 historical matrix rows and onlyAC-551/552/553 acceptance.\n`;
const handoffBinding=await save('docs/development/wave5-next-session-20261013-r5.md',handoff);
must(hashBytes(JSON.stringify(matrix.preservedRows))===canonicalSha,'CANONICAL_ROWS_CHANGED');await loadApprovedInputs();
process.stdout.write(JSON.stringify({published:true,all109HistoricalRowsPreserved:true,ownerAcceptedCriteria:3,ledgerCount:114,apiFunctionCount:363,
 checkpoint:checkpointBinding,matrix:matrixBinding,matrixMarkdown:mdBinding,status:statusBinding,handoff:handoffBinding})+'\n');
