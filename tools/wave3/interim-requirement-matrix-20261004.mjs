import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import {artifactTag, sourceHash, writeNewJson} from './strict-candidate-evidence.mjs';

// A pending-state matrix only. The final generator still requires the three
// completed source-matched strict suites before verifying selected-policy work.
const base='docs/verification/remaining-wave3/';
const read=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const hash=file=>sourceHash(file);
const unique=values=>[...new Set(values)];
const normalized=value=>value.replace(/\s+/g,' ').trim();
const [inputPath,selectedTag='20261004-interim']=process.argv.slice(2);
const tag=artifactTag(selectedTag);
if(!inputPath?.startsWith(base)||!fs.existsSync(inputPath))throw Error('Pass explicit task-owned pending evidence input.');
const input=read(inputPath),prior=read(base+'requirement-matrix-20261002.json');
const head=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
if(input.head!==head)throw Error('Interim input must bind the current observed HEAD.');
const spec=fs.readFileSync(prior.spec,'utf8');
const approved=new Map([...spec.matchAll(/^(?:- |### )((?:FR|AC|EC|NFR)-\d{3}):\s*([\s\S]*?)(?=^(?:- |### )(?:FR|AC|EC|NFR)-\d{3}:|^## |^### [^A]|$(?![\s\S]))/gm)].map(match=>[match[1],normalized(match[2])]));
if(approved.size!==181||hash(prior.spec)!==prior.spec_sha256||prior.requirements.length!==181||prior.requirements.some(row=>approved.get(row.id)!==normalized(row.approved_behavior)))throw Error('Approved181 wording/count/hash mismatch.');
for(const [kind,count]of Object.entries({FR:95,AC:26,EC:40,NFR:20}))if([...approved.keys()].filter(id=>id.startsWith(kind+'-')).length!==count)throw Error('Approved category mismatch.');
const scope=fs.readFileSync(input.coverage_scope,'utf8').trim().split(/\r?\n/);
const baseline=fs.readFileSync(base+'requirements-coverage-paths-20261003.txt','utf8').trim().split(/\r?\n/);
if(scope.length!==194||new Set(scope).size!==194||baseline.length!==189||baseline.some(file=>!scope.includes(file)))throw Error('Full cumulative194 source selection required.');
const raw=read(input.coverage_raw),coverage=read(input.coverage_reviewed),pure=read(input.coverage_additional_pure_domain);
if(coverage.changed_dart.files!==194||coverage.files.filter(row=>row.changed).length!==194||coverage.files.some(row=>row.source_sha256!==hash(row.file))||
    pure.report.sha256!==hash(input.coverage_reviewed)||pure.combined_pure_domain.files!==26||pure.additional_pure_domain.some(row=>row.source_sha256!==hash(row.file)))throw Error('Current coverage/source/extended-pure mismatch.');
for(const key of ['files','lines','lines_hit','branches','branches_hit','line_percent','branch_percent'])if(raw.changed_dart[key]!==coverage.changed_dart[key]||raw.pure_domain[key]!==coverage.pure_domain[key])throw Error('Declaration supplement changed measured counts.');
const coverageGates={...coverage.gates,...pure.gates};
const installation=read(input.database_package);
if(installation.head!==head||installation.candidates?.length!==46||installation.candidates.some((row,index)=>row.ordinal!==index+1||row.sha256!==hash(row.path)||row.installed===true||row.installed_now===true))throw Error('Pending46 source/order/install drift.');
if(installation.fresh_strict_execution)throw Error('This interim method never labels completed selected-policy execution; use the final strict generator for that state.');
const ownerReply='Approve interim issues at the last authoritative positive moving-average cost, block unknown cost basis, and post linked later-receipt variance corrections.';
if(input.policy?.approved!==true||input.policy.owner_reply!==ownerReply||input.policy.selection!=='last_authoritative_positive_moving_average'||input.policy.implemented_verified!==false)throw Error('Explicit policy approval and pending implementation verification required.');
const checks=(input.checks??[]).map(row=>{
  if(row.complete!==true||!row.kind||!row.file)throw Error('Record only explicitly completed local checks.');
  const result={...row,sha256:hash(row.file),current_source_match:false};
  if(Number.isInteger(row.passed)&&Number.isInteger(row.failed)) {
    const log=fs.readFileSync(row.file,'utf8'),progress=[...log.matchAll(/\+(\d+)(?:\s+-(\d+))?\s*:/g)].at(-1);
    if(!progress||Number(progress[1])!==row.passed||Number(progress[2]??0)!==row.failed||!(row.failed?/Some tests failed[.!]/:/All tests passed[.!]/).test(log))throw Error('Completed log count/terminal outcome mismatch.');
  }
  if(row.source_capture) {
    const capture=read(row.source_capture);
    if(!Array.isArray(capture.files))throw Error('Actual source capture required.');
    result.source_capture_sha256=hash(row.source_capture);
    result.source_mismatches=capture.files.filter(item=>!fs.existsSync(item.file)||item.sha256!==hash(item.file)).map(item=>item.file);
    result.current_source_match=result.source_mismatches.length===0;
    result.current_source_match_scope='Complete actual capture; unrelated concurrent Wave4 drift remains explicit.';
  }
  return result;
});
if(!checks.length)throw Error('Explicit completed client checks required.');
const classification=read(input.desktop_failure_classification);
if(classification.passed!==1617||classification.failed!==76||classification.failures?.length!==76)throw Error('Actual whole desktop classification count mismatch.');
const policySources=[input.policy.contract,input.policy.candidate,input.policy.assertions,...input.policy.dart_sources];
if(policySources.some(file=>!fs.existsSync(file))||installation.candidates.at(-1).path!==input.policy.candidate)throw Error('Current reviewed policy sources required.');
const evidence=unique([inputPath,input.database_package,input.coverage_scope,input.coverage_raw,input.coverage_reviewed,input.coverage_additional_pure_domain,input.desktop_failure_classification,...checks.flatMap(row=>[row.file,...(row.source_capture?[row.source_capture]:[])]),...(input.additional_review??[])]);
const requirements=prior.requirements.map(row=>{
  const policyRow=['FR-353','EC-323'].includes(row.id);
  const negativeRelevant=policyRow||['receipt','inventory','order','control'].includes(row.review_group)||['FR-395','NFR-313'].includes(row.id);
  return {...row,implementation:policyRow?'approved_policy_candidate_and_client_present_final_database_verification_pending':'current_source_present_limited_review_pending_external_acceptance',
    missing_implementation:policyRow?'Selected-policy implementation completion is unverified. Latest source corrections require successful strict46stack regression; source presence and client tests do not close the accounting gap.':null,
    development_status:policyRow?'pending_source_frozen_database_verification':'bounded_source_review_recorded',
    missing_verification:policyRow?'Three complete source-matched strict rollback suites, actual tail schema/compatibility review and accounting correction regressions remain pending after actual failed iterations and connector transport failure.':row.id==='NFR-317'?'Current numerical/source-matched194-file line and26-file branch gates are recorded separately; failed visual/whole-checkout cases and external acceptance remain pending.':'Completed captured local scenarios are recorded. Whole desktop contains pixel, protected rendering and compilation/load failures; later source drift and installed/authenticated/native/load acceptance remain explicit.',
    external_acceptance:'Specific isolated installation/resources/restore/fixtures, existing distinct signed actors/sessions, target-scale p95, separate native profile/stores/cold launch and owner signoff remain unapproved or unverified.',
    source_evidence:unique([...row.source_evidence,...(negativeRelevant?policySources:[])]),
    verification_evidence_historical:row.verification_evidence.map(file=>({file,sha256:hash(file),boundary:'Historical artifact retained; no current result inferred.'})),
    verification_evidence_current:evidence,completed_local_checks:checks,selected_policy_execution:null};
});
const allSources=unique(requirements.flatMap(row=>row.source_evidence));
const matrix={generated_on:'2026-10-04',generated_at:new Date().toISOString(),head,interim:true,development_complete:false,goal_complete:false,
  generator:'tools/wave3/interim-requirement-matrix-20261004.mjs',generator_sha256:hash('tools/wave3/interim-requirement-matrix-20261004.mjs'),spec:prior.spec,spec_sha256:hash(prior.spec),counts:prior.counts,requirements,
  policy:{...input.policy,selected_policy_execution:null,source_sha256:Object.fromEntries(policySources.map(file=>[file,hash(file)]))},
  candidate_preparation:{file:input.database_package,sha256:hash(input.database_package),candidates:46,installed:false,fresh_strict_execution:null},
  coverage:{raw:input.coverage_raw,reviewed:input.coverage_reviewed,additional_pure_domain:input.coverage_additional_pure_domain,scope:input.coverage_scope,selected_files:194,changed_dart:coverage.changed_dart,combined_pure_domain:pure.combined_pure_domain,gates:coverageGates},
  completed_local_checks:checks,actual_full_desktop_classification:{file:input.desktop_failure_classification,sha256:hash(input.desktop_failure_classification),passed:1617,failed:76,categories:classification.categories},
  evidence_sha256:Object.fromEntries(evidence.map(file=>[file,hash(file)])),source_sha256:Object.fromEntries(allSources.map(file=>[file,hash(file)])),
  confirmed_unverified_development:['FR-353','EC-323'],
  boundary:'Interim exact181 matrix only. Explicit owner policy approval, current reviewed source and completed local outcomes are retained. No successful46stack SQL or complete development/release claim is inferred; final strict generator remains unchanged in requiring all three actual complete suites. Installation/authenticated contention/load/native/visual acceptance and owner signoff remain open.'};
const output=base+`requirement-matrix-${tag}.json`,markdown=base+`requirement-matrix-${tag}.md`;
if([output,markdown].some(file=>fs.existsSync(file)))throw Error('Retain earlier interim matrices; choose an unused tag.');
writeNewJson(output,matrix);
const cell=value=>String(value??'').replaceAll('|','\\|').replace(/\r?\n/g,' ');
fs.writeFileSync(markdown,[`# Interim approved Wave3 matrix — 2026-10-04`,'',
  'All181 exact approved IDs and normalized full wording retained:95FR,26AC,40EC,20NFR. This matrix records pending development/verification, separately from external acceptance. It does not close Wave3.','',
  `Current HEAD:${head}. Exact46 candidate source package:${input.database_package}. Three successful source-matched strict suites and actual tail schema review remain pending; no candidate was installed. Owner-selected policy approval is explicit and development completion is unverified.`, '',
  `Current cumulative194-file coverage:${coverage.changed_dart.lines_hit}/${coverage.changed_dart.lines} lines (${coverage.changed_dart.line_percent.toFixed(5)}%). Combined26pure branch coverage:${pure.combined_pure_domain.branches_hit}/${pure.combined_pure_domain.branches} (${pure.combined_pure_domain.branch_percent.toFixed(5)}%). Gates:${JSON.stringify(coverageGates)}. Exact declaration supplements preserve allscope/hits/denominators/thresholds.`, '',
  `Actual whole desktop:${classification.passed} passes/${classification.failed} failures; categories:${JSON.stringify(classification.categories)}. Complete-capture source drift is separately recorded percheck. Later focused startup passes and fresh render/coverage evidence do not turn this complete-suite failure into a pass.`, '',
  ...checks.map(row=>`- ${row.kind}: ${row.file}; ${row.passed??'see log'} passed/${row.failed??'see log'} failed; complete-capture current source match:${row.current_source_match}.`), '',
  '| ID | Exact approved behavior | Current development | Missing implementation or verification | External acceptance |','|---|---|---|---|---|',
  ...requirements.map(row=>`| ${row.id} | ${cell(row.approved_behavior)} | ${cell(row.development_status)} | ${cell(row.missing_implementation??row.missing_verification)} | ${cell(row.external_acceptance)} |`),'',
  'This is an interim reviewable result. The final strict generator still requires actual successful complete procurement/inventory/receivables executions, exact source/order and actual schema equality before marking selected-policy development verified.',''].join('\n'),{flag:'wx'});
console.log(JSON.stringify({output,markdown,approved:181,interim:true,scope:194,coverage_gates:coverageGates,policy_execution:null,development_complete:false}));
