import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {HEALTH_IMPORT_DEPENDENCIES,LAUNCHER,PLAN as HEALTH_PLAN,REVIEW as HEALTH_REVIEW} from '../../../../../tools/wave5/run_worker_v7_health_20261015_r5.mjs';
import {SOURCE,PLAN as SCHEDULER_PLAN,REVIEW as SCHEDULER_REVIEW,BUDGET,ARCHIVE_MANIFEST,CALL_INVENTORY} from '../../../../../tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';
const base='docs/verification/wave5/seven-area-completion-20261016/area4-integrations/';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=async file=>JSON.parse((await fs.readFile(file,'utf8')).replace(/^\uFEFF/,''));
const bind=async file=>{const bytes=await fs.readFile(file);return {path:file,sha256:sha(bytes),bytes:bytes.length};};
const before=await json(base+'verification-a2-before-hashes.json'),after=[];
for(const item of before){const file=path.relative(process.cwd(),item.Path).replaceAll('\\','/');const row=await bind(file);
 if(row.sha256!==item.Hash.toLowerCase())throw Error('Source changed during controlled verification: '+file);after.push(row);}
const tap=await fs.readFile(base+'controlled-entrypoints-a2.tap','utf8');
if(!/^# tests 27$/m.test(tap)||!/^# pass 27$/m.test(tap)||!/^# fail 0$/m.test(tap)||!/^# skipped 0$/m.test(tap)
 ||(await fs.readFile(base+'controlled-entrypoints-a2.exit.txt','utf8')).trim()!=='0')throw Error('Controlled test proof failed');
const syntax=await json(base+'syntax-and-validation-a2.json');if(Object.values(syntax).some(x=>x!==0))throw Error('Source validation failed');
const sourceValidation=await json(base+'scheduler-source-validation-a2.json');
if(!sourceValidation.passed||sourceValidation.actualResumeAllowed!==false||sourceValidation.deployedArchiveBindings!==39)throw Error('Archive source verification failed');
const archive=await json(ARCHIVE_MANIFEST.path);if(sha(await fs.readFile(ARCHIVE_MANIFEST.path))!==ARCHIVE_MANIFEST.sha256)throw Error('Archive manifest changed');
for(const item of archive.entries)if(sha(await fs.readFile(item.path))!==item.sha256)throw Error('Archived deployed source changed');
const ids=['FR-515','FR-535','AC-506','EC-506','FR-521','FR-522','FR-523','AC-510','AC-511','EC-509','EC-510'];
const acceptanceFile='docs/verification/wave5/task3-acceptance-20261013/open-requirement-prerequisites.json';
const acceptance=await json(acceptanceFile),requirements=ids.map(id=>{const row=acceptance.rows.find(x=>x.id===id);
 if(!row||row.accepted)throw Error('Unexpected area requirement state');return row;});
const inputs=[...HEALTH_IMPORT_DEPENDENCIES,base+'entrypoints.test.mjs',ARCHIVE_MANIFEST.path,CALL_INVENTORY.path,
 base+'health-launcher-before.mjs',base+'scheduler-before.mjs',base+'health-launcher-21-test-checkpoint.mjs',base+'scheduler-21-test-checkpoint.mjs',
 base+'checkpoint-lineage.json',base+'README.md',acceptanceFile,'docs/verification/wave5/seven-area-completion-20261016/current-state-verification-a1.json'];
const inputBindings=[];for(const file of [...new Set(inputs)])inputBindings.push(await bind(file));
const evidenceFiles=['controlled-entrypoints-a1.tap','controlled-entrypoints-a1.exit.txt','controlled-entrypoints-a2.tap','controlled-entrypoints-a2.exit.txt',
 'verification-a2-before-hashes.json','scheduler-source-validation-a2.json','syntax-and-validation-a2.json'];
const evidenceBindings=[];for(const file of evidenceFiles)evidenceBindings.push(await bind(base+file));
const report={kind:'area4-export-and-integration-source-completion-report',recordedAt:new Date().toISOString(),sourceOnly:true,executionPermitted:false,
 actualStateBaseline:{chargedPriorCalls:137,verifiedDatabaseAt:'2026-10-16T12:13:25.833347Z',bothOriginalAuthoritiesExpired:true,ownJobsPaused:true,actualExports:0},
 proposedBudget:BUDGET,budgetApproved:false,sourceChangesComplete:true,actualWorkflowComplete:false,
 syntax,controlledTests:{tests:27,pass:27,fail:0,skip:0,exitCode:0,syntheticPortsOnly:true,independentHumanAcceptance:false},
 sourceBeforeAfterUnchanged:after,sourceValidation,deployedArchive:{manifest:ARCHIVE_MANIFEST,exactCopiedInputs:39,
  codeExecutedFromArchive:false,currentProductCandidate:archive.currentProductCandidate,candidateDiffersFromDeployed:true},
 interfaces:{health:{source:LAUNCHER,plan:HEALTH_PLAN,review:HEALTH_REVIEW},scheduler:{source:SOURCE,plan:SCHEDULER_PLAN,review:SCHEDULER_REVIEW},
  argv:['--preflight <finalReviewSha256>','--execute <finalReviewSha256>'],
  exactPreflightKeys:['passed','networkCalls','privateInputsRead','planSha256','finalReviewSha256'],
  exactPrivateInputKeys:['projectId','bundleSha256','ownerToken'],privateInputMaximumBytes:8192,privateInputTimeoutMs:15000,
  planBindingField:'generatedPlan; optional planBinding must match',lockInventories:['sourceBindings','publicBindings'],
  healthImportSourcePaths:HEALTH_IMPORT_DEPENDENCIES,renewalRawResponseBindings:['renewalPreflightResponse','renewalWriteResponse','renewalReadbackResponse'],
  renewalReceiptOrdinals:[139,140,141],serverWindowAnchorMeaning:'Actual raw preflight observation; distinct from actual raw server post-COMMIT appliedAt'},
 requirements,assignedRequirements:11,acceptedByThisWork:0,acceptanceChanged:false,
 actualWorkPending:['genuine owner refresh and explicit bounded authority renewal','actual renewal/export/provider/health/scheduler records',
  'actual delivery and receiver receipts, retries, dead letters and replay protection','external-command restrictions and all eleven row acceptance gaps'],
 limitations:['Controlled tests and archived source verification are not actual workflow acceptance.',
  'a7 exporter, renewal controller and private adapter are separately owned and must be independently frozen/reviewed.',
  'Saved candidate differs from deployed V7; archive preservation does not install product changes.',
  'No future approval, private owner input, renewal or operation result was created.'],
 actions:{networkCalls:0,privateInputsRead:false,liveWrites:0,SDKExecuted:false,deployment:false,intentsCreated:0,approvalCreated:false,productionRelease:false},
 inputBindings,evidenceBindings};
await fs.writeFile(base+'completion-report.json',JSON.stringify(report,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({report:await bind(base+'completion-report.json'),sources:after.filter(x=>[SOURCE,LAUNCHER].includes(x.path)),tests:27})+'\n');
