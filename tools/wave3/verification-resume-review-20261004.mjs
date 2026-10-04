import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {sourceHash, writeNewJson} from './strict-candidate-evidence.mjs';

// Read-only derivative review. No test, SQL, network, installation or native call.
const base='docs/verification/remaining-wave3/';
const read=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const hash=file=>sourceHash(file);
const normalize=value=>value.replace(/\s+/g,' ').trim();
const matrix=read(base+'requirement-matrix-20261002.json');
const spec=fs.readFileSync(matrix.spec,'utf8');
const approved=new Map([...spec.matchAll(/^(?:- |### )((?:FR|AC|EC|NFR)-\d{3}):\s*([\s\S]*?)(?=^(?:- |### )(?:FR|AC|EC|NFR)-\d{3}:|^## |^### [^A]|$(?![\s\S]))/gm)].map(match=>[match[1],normalize(match[2])]));
if(approved.size!==181||hash(matrix.spec)!==matrix.spec_sha256||matrix.requirements.some(row=>approved.get(row.id)!==normalize(row.approved_behavior)))throw Error('Approved181 wording/source mismatch.');
const counts={FR:95,AC:26,EC:40,NFR:20};
for(const [kind,count]of Object.entries(counts))if([...approved.keys()].filter(id=>id.startsWith(kind+'-')).length!==count)throw Error('Approved category mismatch.');
const scopePath=base+'requirements-coverage-paths-negative-stock-policy-20261003.txt';
const baselinePath=base+'requirements-coverage-paths-20261003.txt';
const paths=file=>fs.readFileSync(file,'utf8').trim().split(/\r?\n/);
const scope=paths(scopePath),baseline=paths(baselinePath);
if(baseline.length!==189||scope.length!==194||new Set(scope).size!==194||baseline.some(file=>!scope.includes(file)))throw Error('Cumulative194 scope dropped/duplicated an approved baseline path.');
const priorAudit=read(base+'requirements-coverage-input-audit-pre-policy-microtask-20261003.json');
if(priorAudit.locked_summarizer.sha256!==hash('tools/wave3/summarize-final-coverage.mjs'))throw Error('Locked summarizer source changed.');
const failurePath=base+'desktop-final-failure-classification-20261003.json';
const failure=read(failurePath),categories={};
for(const row of failure.failures)categories[row.category]=(categories[row.category]??0)+1;
if(failure.failures.length!==89||categories.golden!==85||hash(failure.log)!==failure.log_sha256)throw Error('Historical whole-suite classification/log drift.');
const oldCapture=read(failure.execution_source_capture);
const oldSourceDrift=oldCapture.files.filter(row=>!fs.existsSync(row.file)||hash(row.file)!==row.sha256).map(row=>row.file);
const imagePath=base+'approved-golden-investigation-20261002.json';
const images=read(imagePath).images.map(row=>({file:row.approved,recorded_sha256:row.approved_sha256,current_sha256:hash(row.approved),unchanged:hash(row.approved)===row.approved_sha256,
  historical_output:row.actual,historical_output_sha256:row.actual_sha256,current_output_matches_historical:fs.existsSync(row.actual)&&hash(row.actual)===row.actual_sha256}));
const offlineCapturePath=base+'target-selection-all-start-sources-20261004.json';
const offline=read(offlineCapturePath),offlineDrift=Object.entries(offline.source_sha256).filter(([file,expected])=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8')).digest('hex')!==expected).map(([file])=>file);
const offlineLog=base+'target-selection-all-green-20261004.log';
const log=fs.readFileSync(offlineLog,'utf8');
if(!/tests 78\b/.test(log)||!/pass 78\b/.test(log)||!/fail 0\b/.test(log))throw Error('Actual completed78-check offline log mismatch.');
const refreshPath=base+'refresh-policy-final-20261004.json',refresh=read(refreshPath);
const report={generated_on:'2026-10-04',generated_at:new Date().toISOString(),head:execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),
  approved_requirements:{file:matrix.spec,sha256:hash(matrix.spec),counts,total:181,wording_unchanged:true},
  coverage_scope:{file:scopePath,sha256:hash(scopePath),files:194,retained_baseline:189,additional:scope.filter(file=>!baseline.includes(file)),locked_summarizer:priorAudit.locked_summarizer,
    pure_domain_files:26,thresholds:{changed_dart_line:80,combined_pure_domain_branch:90},boundary:'Scope and evaluation source only; current coverage outcomes are separate.'},
  historical_desktop:{classification:{file:failurePath,sha256:hash(failurePath)},log:{file:failure.log,sha256:hash(failure.log)},source_capture:failure.execution_source_capture,
    recorded_summary:failure.summary,independent_categories:categories,current_source_drift:oldSourceDrift,
    boundary:'The recorded1567pass/89fail run remains historical for later policy/client changes. Failure classes do not assert current outcomes or visual acceptance.'},
  preserved_approved_images:{review:{file:imagePath,sha256:hash(imagePath)},count:images.length,unchanged:images.filter(row=>row.unchanged).length,images,
    boundary:'Byte preservation of the83 approved images reviewed onOctober2. Concurrent Wave4 service golden changes outside this set are preserved and separately owned. No rerender/rebaseline/comparator/tolerance change.'},
  raster_probe:{review:{file:base+'golden-cause-20261003.json',sha256:hash(base+'golden-cause-20261003.json')},provenance:{file:base+'golden-cause-20261003.md',sha256:hash(base+'golden-cause-20261003.md')},
    boundary:'Controlled identical primitive source proves a rounded-border SDK raster difference. It does not explain all full-screen cases; documented capability/navigation differences and current visual acceptance remain separate.'},
  offline_target_preparation:{actual_log:{file:offlineLog,sha256:hash(offlineLog)},start_source_capture:{file:offlineCapturePath,sha256:hash(offlineCapturePath)},tests:78,passed:78,failed:0,
    old_tests:68,new_tests:10,current_source_drift:offlineDrift,source_files:Object.keys(offline.source_sha256).length,
    red:{file:base+'target-selection-red-20261004.log',sha256:hash(base+'target-selection-red-20261004.log'),passed:1,failed:4,source_capture:null},
    boundary:'Fictitious offline guard and recipe tests only. Artificial46 test schemas are not actual database observations. No final real46 recipe exists until actual completed schema/suite selection is available.'},
  installed_read_only_refresh:{file:refreshPath,sha256:hash(refreshPath),observed_at:refresh.observed_at,installed:refresh.migrations.length,api:refresh.api_catalogue.length,shared_helpers:refresh.shared_helpers,
    boundary:'Read-only ledger/catalogue/helper observation of existing development project, not candidate installation or independent authenticated acceptance.'},
  boundary:'Independent source, historical visual/failure and offline preparation review only. Root retains actual tests/SQL/build execution and public status. No development/verification completion, installation, native/load or owner signoff inference.'};
const output=base+'verification-resume-review-20261004.json';writeNewJson(output,report);
console.log(JSON.stringify({output,approved:181,scope:194,approved_images_preserved:report.preserved_approved_images.unchanged,offline_tests:78,offline_source_drift:offlineDrift.length,historical_desktop_source_drift:oldSourceDrift.length,final46_execution:false}));
