// Compose only new immutable read-only preflight evidence. No connector or SDK call.
import {access,lstat,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),base='docs/verification/wave5/';
if(process.argv.length!==2)throw Error('NO_ARGUMENTS_SUPPORTED');
const sha=b=>createHash('sha256').update(b).digest('hex'),eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const must=(c,m)=>{if(!c)throw Error(m);};
const files={raw:base+'complete-live-preflight-20261010-r3-raw.json',edge:base+'complete-live-preflight-20261010-r3-edge-list.json',
  priorRaw:base+'complete-live-preflight-20261010-r2-raw.json',priorSummary:base+'complete-live-preflight-20261010-r2-summary.json',
  priorComparison:base+'complete-live-preflight-20261010-r2-fingerprint-comparison.json',sql:base+'complete-live-preflight-20261010-r2.sql',
  queryManifest:base+'complete-live-preflight-20261010-r2-query-hashes.json',native:base+'complete-live-preflight-20261010-r2-native-net.json',
  oldNative:base+'complete-live-preflight-20261010-r2-native.json',review:base+'complete-app-runtime-review-20261009-r13.json',
  originalReview:base+'complete-app-runtime-review-20261009.json',acceptance:base+'owner-criterion-acceptance-after-20261010-r2-serial.json',
  ownerCriteria:base+'owner-criterion-decision-20261010-r2.json',promotion:base+'golden-promotion-result-20261010-r2.json',
  fullSuite:base+'golden-review-approvedAll-20261010-r2.json',source:base+'golden-review-postapproval-source-20261010-r2.json',
  preparation:base+'windows-userflow-preparation-20261010-r3.json',
  summary:base+'complete-live-preflight-20261010-r3-summary.json',index:base+'complete-live-preflight-20261010-r3-index.json',md:base+'complete-live-preflight-20261010-r3.md'};
const bound=new Map();
function inside(file){must(typeof file==='string'&&!path.isAbsolute(file),'RELATIVE_INPUT_REQUIRED');const absolute=path.resolve(root,file),rel=path.relative(root,absolute);must(rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'INPUT_ESCAPES');return absolute;}
async function bind(file,h){const loc=inside(file);must((await lstat(loc)).isFile()&&!(await lstat(loc)).isSymbolicLink(),'REGULAR_INPUT_REQUIRED');const b=await readFile(loc),actual=sha(b);must((!h||h===actual)&&(!bound.has(file)||bound.get(file).sha256===actual),'BOUND_INPUT_DRIFT:'+file);bound.set(file,{path:file,sha256:actual,bytes:b.length});return b;}
const json=async(file,h)=>JSON.parse((await bind(file,h)).toString('utf8').replace(/^\uFEFF/,''));
const [raw,edge,old,previous,oldCompare,queries,native,oldNative,review,originalReview,accepted,owner,promotion,fullSuite,source,preparation]=await Promise.all([
  json(files.raw),json(files.edge),json(files.priorRaw),json(files.priorSummary),json(files.priorComparison),json(files.queryManifest),
  json(files.native),json(files.oldNative),json(files.review),json(files.originalReview),json(files.acceptance),json(files.ownerCriteria),json(files.promotion),
  json(files.fullSuite),json(files.source),json(files.preparation)]);
const sql=await bind(files.sql);
must(raw.projectId==='xpdoufauvrbdmxgngetv'&&raw.readOnly===true&&raw.queryPath===files.sql&&raw.querySha256===sha(sql)&&raw.rawConnectorResult.isError===false,'RAW_QUERY_PROVENANCE_CHANGED');
const rawPayload=JSON.parse(raw.rawConnectorResult.content.find(c=>c.type==='text').text).result;
const match=rawPayload.match(/\n<untrusted-data-([a-z0-9-]+)>\s*([\s\S]*?)\s*<\/untrusted-data-\1>/);must(match,'ACTUAL_CONNECTOR_BOUNDARY_REQUIRED');
const rows=JSON.parse(match[2]);must(rows.length===1,'ONE_LIVE_RESULT_REQUIRED');const live=rows[0],prior=old.parsedCatalogAndCollisions[0];
must(eq(Object.keys(live).filter(k=>!eq(live[k],prior[k])),['observed_at']),'LIVE_METADATA_OR_COLLISIONS_CHANGED');
must(live.observed_at==='2026-10-10 06:36:27.034589+00'&&Date.parse(live.observed_at)>Date.parse(prior.observed_at),'FRESH_OBSERVATION_REQUIRED');
must(live.migration_count===43&&live.api_functions===107&&live.functions.length===120&&new Set(live.functions.map(f=>`${f.schema}.${f.name}(${f.arguments})`)).size===120&&
  live.wave5_tables.length===15&&live.wave5_tables.every(t=>t.rlsEnabled&&t.rlsForced),'EXPECTED_DATABASE_BASELINE_CHANGED');
const collisionKeys=Object.keys(previous.collisions);must(collisionKeys.length===14&&collisionKeys.every(k=>live[k]===0)&&live.proposed_runtime_accounts===0&&
  live.reviewed_scope_count===500&&live.reviewed_second_branch_count===1&&live.reviewed_plan_count===4&&live.reviewed_account_count===6&&live.reviewed_role_count===1003,'EXACT_COLLISION_SCOPE_NOT_CLEAR');
must(live.role_permissions===87&&live.role_assignments===1&&live.entitlements===28&&live.memberships===1,'ACCESS_COUNTS_CHANGED');
must(edge.projectId===raw.projectId&&edge.readOnly===true&&edge.rawConnectorResult.isError===false,'EDGE_LIST_PROVENANCE_CHANGED');
const functions=JSON.parse(edge.rawConnectorResult.content.find(c=>c.type==='text').text).functions;
const priorFunctions=JSON.parse(old.edgeVerification.content.find(c=>c.type==='text').text).functions;
must(eq(functions,priorFunctions)&&functions.length===2&&eq(functions.map(f=>f.slug),['people-private-documents','people-private-purge']),'EDGE_DEPLOYMENT_INVENTORY_CHANGED');
must(native.accountName==='jentra-w5-runtime'&&native.accountExistenceVerified===true&&native.accountExists===false&&native.exitCode===2&&native.namedError==='NERR_UserNotFound / NET HELPMSG 2221'&&
  native.rawOutput.includes('The user name could not be found.')&&native.rawOutput.includes('2221')&&native.packageDirectoryExists===false&&native.profileDirectoryExists===false&&
  native.readOnly===true&&native.provisionedByThisCheck===false&&native.accountOrSessionContentsRead===false&&native.previousUnverifiedRecordPreserved===files.oldNative&&
  oldNative.accountExistenceVerified===false&&oldNative.accountExists===null,'EXACT_NATIVE_OBSERVATION_CHANGED');
must(review.ownerApproved===false&&review.bundleSha256==='92a68a58d70a1f9061776be1b6416b8124112577b0a0859ed6f389becc2533d4'&&
  originalReview.ownerApproved===false&&originalReview.bundleSha256==='13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e','UNAPPROVED_RUNTIME_REVIEWS_CHANGED');
must(accepted.status==='complete'&&accepted.fullPublication===true&&accepted.observedOwnerAcceptedCriteria===3&&eq(accepted.observedOwnerAcceptedIds,['AC-551','AC-552','AC-553'])&&
  accepted.ownerDecision.path===files.ownerCriteria&&accepted.ownerDecision.sha256===bound.get(files.ownerCriteria).sha256&&owner.submittedByOwner===true&&
  owner.authorizationKind==='direct-human-message','THREE_CRITERION_ACCEPTANCE_RECORD_CHANGED');
must(promotion.status==='complete'&&promotion.fullPromotion===true&&promotion.publishedImageCount===83&&fullSuite.status==='complete'&&fullSuite.fullSuitePassed===true&&
  fullSuite.exitCode===0&&fullSuite.integrityError===null&&eq(fullSuite.counts,{passed:2004,failed:0,skipped:0})&&
  fullSuite.sourceManifest.path===files.source&&fullSuite.sourceManifest.sha256===bound.get(files.source).sha256&&source.selectedSources===1068,'GOLDEN_EVIDENCE_CHANGED');
must(preparation.sourceStable===true&&preparation.sourceFileCount===1068&&preparation.SDKExecuted===false&&preparation.nativeLaunched===false&&preparation.localStoresRead===false,
  'SOURCE_ONLY_PREPARATION_CHANGED');
for(const b of preparation.manifests)await bind(b.path,b.sha256);
for(const b of [queries.sourceProposal,oldCompare.previousRead,oldCompare.currentRead,accepted.before])await bind(b.path,b.sha256);
await bind(fullSuite.log,fullSuite.logSha256);
must(queries.mainSql.sha256===sha(sql)&&queries.mainSqlBytes===sql.length,'EXACT_SAVED_QUERY_CHANGED');
await bind('scripts/wave5/record_live_preflight_20261010_r3.mjs');
const noLiterals=sql.toString('utf8').replace(/--[^\r\n]*/g,'').replace(/'(?:''|[^'])*'/g,"''");
must(/^\s*WITH\b/i.test(noLiterals)&&(noLiterals.match(/;/g)||[]).length===1&&!/\b(?:insert|update|delete|alter|drop|create|grant|revoke|truncate|execute|call|do|set|copy|vacuum|refresh)\b/i.test(noLiterals),'READ_ONLY_QUERY_REQUIRED');
const now=new Date().toISOString(),binding=file=>bound.get(file);
const summary={recordedAt:now,projectId:raw.projectId,observedAt:live.observed_at,rawEvidence:binding(files.raw),query:binding(files.sql),
  connectorResultDecodedFromExactUntrustedDataBoundary:true,queryBytes:sql.length,readOnly:true,
  migrationCount:43,apiFunctions:107,checkedProviders:120,unchangedProvidersSinceR2:120,unchangedProvidersSinceOriginalOctober9Read:120,
  previousObservedAt:prior.observed_at,originalFunctionComparisonObservedAt:oldCompare.previousObservedAt,
  changedProviderIdentities:[],missingProviderIdentities:[],addedProviderIdentities:[],wave5Tables:live.wave5_tables,wave5RlsFlagsUnchangedSinceR2:true,
  rolePermissions:87,roleAssignments:1,entitlements:28,memberships:1,accessCountsUnchanged:true,
  accessRowFingerprints:live.access_row_fingerprints,accessRowFingerprintsUnchangedSinceFirstR2Baseline:true,
  policyAndGrantFingerprints:live.wave5_policy_and_grant_fingerprints,policyAndGrantFingerprintsUnchangedSinceFirstR2Baseline:true,
  fingerprintBoundary:'The r2 access-row/policy/grant hashes were first baselines; r3 directly equals those saved r2 hashes. No earlier historical row/policy equality is inferred from counts.',
  exactProposedCollisionScope:{accounts:6,tenants:500,entities:500,branches:501,plans:4,roles:1003,reviewBundleSha256:review.bundleSha256,
    unchangedIdentifierQuery:binding(files.sql),savedProposal:binding(files.review)},collisions:Object.fromEntries(collisionKeys.map(k=>[k,live[k]])),
  proposedRuntimeAccounts:0,accountLabelCollisionCounts:live.account_label_collision_counts,currentTrialAccount:live.trial_account,
  runtimeRelations:{edgeAuthorities:live.edge_authorities,workerScopes:live.runtime_worker_scopes,externalCredentials:live.runtime_external_credentials,
    deliveryOutbox:live.delivery_outbox,cronJobs:live.cron_jobs,netQueue:live.net_queue},
  edgeInventory:{record:binding(files.edge),observedAt:edge.observedAt,deployments:functions.map(f=>({slug:f.slug,id:f.id,version:f.version,status:f.status,verifyJwt:f.verify_jwt,
    sourceBundleHashMetadata:f.ezbr_sha256})),unchangedMetadataSinceR2:true,actualFunctionSourceBodyReread:false,
    boundary:'Fresh list-functions deployment metadata only. Bundle hashes come from that metadata; no fresh get-source operation occurred in this r3 read.'},
  originalSixLedger:{lastObservedEvidence:binding(files.priorRaw),lastObservedAt:prior.observed_at,entries:previous.ledgerOriginalSix,
    migrationLedgerListRereadInR3:false,originalSixReinstalled:false,boundary:'The new SELECT refreshes ledger count only. Exact original-six connector versions retain their prior observed evidence; no migration was installed or replayed.'},
  nativeAccountMetadata:{record:binding(files.native),observedAt:native.observedAt,accountName:native.accountName,accountExistenceVerified:true,accountExists:false,
    exitCode:2,namedError:native.namedError,packageDirectoryExists:false,profileDirectoryExists:false,earlierLookupErrors:binding(files.oldNative),
    provisioned:false,storesOrSessionsRead:false,boundary:'Exact account/path metadata only. No isolated account provisioning, native launch, credential entry or authenticated acceptance is implied.'},
  databaseMetadataAndExactCollisionPreflightClean:true,nativeTargetMetadataCollisionCheckClear:true,fullRuntimePreflightComplete:false,
  remainingRuntimePreflight:['Fresh paired final-source Preview/Connected builds, release/package bindings and truthful native observations are still separate required gates.',
    'No final r3 runtime operation bundle has been composed or owner-approved; original and r13 reviews remain unapproved historical records.',
    'Private owner Auth Admin/model/secret context and operation authority are required for actual runtime setup; do not fabricate Auth rows.',
    'Recheck all exact source/release/credential-reference/live collision bindings immediately before any separately approved operation.'],
  savedRuntimeReviews:[{record:binding(files.originalReview),bundleSha256:originalReview.bundleSha256,ownerApproved:false},{record:binding(files.review),bundleSha256:review.bundleSha256,ownerApproved:false}],
  currentSource:{record:binding(files.source),selectedSources:1068,preparation:binding(files.preparation),preparationOnly:true,nativeBuildsOrPackagesInferred:false},
  ownerAcceptanceSnapshot:{record:binding(files.acceptance),ownerDecision:binding(files.ownerCriteria),ownerAcceptedCriteria:3,criterionIds:accepted.observedOwnerAcceptedIds,
    remainingUnaccepted:106,wholeSystemOwnerSignoff:false},
  goldenSnapshot:{promotion:binding(files.promotion),promotedImages:83,fullDesktopSuite:binding(files.fullSuite),passed:2004,failed:0,skipped:0,
    boundary:'Actual image decisions and calculation acceptance provide no runtime authority.'},
  currentRuntimeApprovalReady:false,runtimeOwnerApproved:false,newRuntimeInstallationComplete:false,authenticatedNative:false,nativeKeyboardVerified:false,realMfa:false,
  actualDelivery:false,actualModelUsage:false,independentSessionContention:false,targetScaleLoad:false,wholeSystemOwnerSignoff:false,
  mutationsExecuted:false,businessFunctionsCalled:false,AuthAccountsCreatedOrDeleted:false,privateSecretsRead:false,SDKJobsExecutedByThisReport:false,livingDocumentsChanged:false,
  productionExcluded:true,realBillingExcluded:true,
  boundary:'A saved read-only live database/query and Edge-list refresh plus separately saved exact native account metadata. No install, bootstrap, private configuration, operation authority or native/runtime/delivery/load acceptance is established.'};
const summaryBytes=Buffer.from(JSON.stringify(summary,null,2)+'\n');
const md='# Fresh read-only live preflight — October 10, 2026, r3\n\n'+
  `The connected SELECT at **${live.observed_at}** on \`${raw.projectId}\` records **43 migrations / 107 API functions**. All **120 protected function definitions**, all **15 enabled/forced RLS table flags**, access counts **87/1/28/1**, the four access-row hashes, fifteen policy/grant fingerprints and every exact proposed collision result equal the saved r2 read. The actual decoded result differs only in \`observed_at\`.\n\n`+
  '| Read-only observation | Fresh result |\n|---|---|\n'+
  '| Exact synthetic resource scope | Six actors; 500 tenant/entity scopes, 501 branches, four plans, 1,003 roles; all 14 collision counts zero |\n'+
  '| Runtime relations | Runtime authority/worker scope/external credential/delivery outbox/cron/net queue relations absent |\n'+
  '| Separate trial account | Confirmed; membership count 0; last sign-in remains October 9 at 18:30:22 UTC |\n'+
  `| Edge inventory | Fresh list at ${edge.observedAt}; exactly the same two People deployments, versions and metadata bundle hashes; no get-source reread |\n`+
  `| Exact Windows target | At ${native.observedAt}, net.exe returns exit 2 / NERR_UserNotFound / 2221 for jentra-w5-runtime; package/profile paths absent |\n\n`+
  'The earlier failed Windows account lookups remain preserved as unverified history. The later net.exe result establishes account absence only at its dated observation. No account, profile, credential, acceptance store or session was created, adopted, read or removed.\n\n'+
  'The r2 access-row/policy/grant fingerprints were first baselines; this r3 query directly compares equal to them. It does not infer earlier historical row equality from matching counts. The fresh SELECT reads migration count; the exact original-six ledger versions retain the prior saved list evidence. None of the six migrations was reinstalled.\n\n'+
  '**Database metadata/resource collision checks and native account metadata are clear; full runtime preflight remains incomplete.** Current paired source/release/packages, actual native observations, private owner configuration, an exact new runtime bundle review and direct runtime approval remain separate. Both original and r13 runtime bundles remain unapproved historical records.\n\n'+
  'The owner-approved image promotion and passing 2,004-test desktop suite are separate evidence. Exactly AC-551, AC-552 and AC-553 are accepted; the other 106 criteria and whole-system signoff remain unaccepted. Genuine MFA, native keyboard/authentication, actual export/worker delivery/model usage, independent-session contention and target-scale load remain open. Production and real billing remain excluded.\n\n'+
  '[Summary](complete-live-preflight-20261010-r3-summary.json) · [Exact artifact/hash index](complete-live-preflight-20261010-r3-index.json) · [Actual raw connected SELECT](complete-live-preflight-20261010-r3-raw.json) · [Fresh Edge metadata](complete-live-preflight-20261010-r3-edge-list.json) · [Exact native metadata](complete-live-preflight-20261010-r2-native-net.json) · [Unchanged read-only query](complete-live-preflight-20261010-r2.sql).\n\n'+
  'No migration, Auth bootstrap, secret setting, deployment, business RPC, SDK job, source/PNG or living-document mutation was performed by these read-only observations or this evidence recorder. Recheck collisions and exact bindings immediately before any separately approved operation.\n';
const mdBytes=Buffer.from(md),index={recordedAt:now,kind:'read_only_live_preflight_artifact_index',projectId:raw.projectId,queryObservedAt:live.observed_at,
  summary:{path:files.summary,sha256:sha(summaryBytes),bytes:summaryBytes.length},report:{path:files.md,sha256:sha(mdBytes),bytes:mdBytes.length},
  originalRawToR3Comparison:{comparedFields:Object.keys(live).length,onlyChangedFields:['observed_at'],r2:binding(files.priorRaw),r3:binding(files.raw)},
  immutableInputs:[...bound.values()],summaryAndReportCreatedExclusively:true,existingDocumentsOverwritten:false,
  boundary:'Artifact index only; all connected observations are read-only and saved. No current whole-runtime readiness or owner runtime approval is inferred.'};
const outputs=new Map([[files.summary,summaryBytes],[files.md,mdBytes],[files.index,Buffer.from(JSON.stringify(index,null,2)+'\n')]]);
async function recheck(){for(const b of bound.values())must(sha(await readFile(inside(b.path)))===b.sha256,'INPUT_CHANGED_BEFORE_EVIDENCE_PUBLICATION:'+b.path);}
for(const file of outputs.keys()){try{await access(inside(file));throw Error('IMMUTABLE_OUTPUT_EXISTS:'+file);}catch(e){if(e.code!=='ENOENT')throw e;}}
for(const[file,b]of outputs){await recheck();await writeFile(inside(file),b,{flag:'wx'});}
await recheck();for(const[file,b]of outputs)must(sha(await readFile(inside(file)))===sha(b),'OUTPUT_HASH_CHANGED:'+file);
console.log(JSON.stringify({created:[...outputs].map(([file,b])=>({path:file,sha256:sha(b),bytes:b.length})),observedAt:live.observed_at,metadataFieldsUnchangedExceptTimestamp:true,
  migrations:43,apiFunctions:107,protectedFunctions:120,rlsTables:15,collisions:0,nativeAccountExists:false,ownerAcceptedCriteria:3,
  fullRuntimePreflightComplete:false,runtimeOwnerApproved:false,SDKExecuted:false,livingDocumentsChanged:false},null,2));
