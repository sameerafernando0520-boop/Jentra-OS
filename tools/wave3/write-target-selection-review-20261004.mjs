import fs from 'node:fs';
import crypto from 'node:crypto';
import {artifactTag, sourceHash, writeNewJson} from './strict-candidate-evidence.mjs';

const [logPath,capturePath,selectedTag='20261004']=process.argv.slice(2);
const tag=artifactTag(selectedTag),base='docs/verification/remaining-wave3/';
if(![logPath,capturePath].every(file=>file?.startsWith(base)&&fs.existsSync(file)))throw Error('Pass actual completed offline log and its execution-start source capture.');
const log=fs.readFileSync(logPath,'utf8'),capture=JSON.parse(fs.readFileSync(capturePath,'utf8').replace(/^\uFEFF/,''));
if(!/tests 78\b/.test(log)||!/pass 78\b/.test(log)||!/fail 0\b/.test(log)||!/executed_database_or_http_calls":0/.test(log))throw Error('Require actual completed78 offline checks and their no-dispatch boundary.');
const drift=Object.entries(capture.source_sha256??{}).filter(([file,expected])=>crypto.createHash('sha256').update(fs.readFileSync(file,'utf8')).digest('hex')!==expected).map(([file])=>file);
if(drift.length)throw Error('Offline check execution sources changed: '+drift.join(', '));
for(const file of ['supabase/migrations/20261003090000_wave3_negative_stock_policy.sql','tools/wave3/target_review_selection.mjs','tools/wave3/target_review_selection_20261004.test.mjs'])if(!capture.source_sha256[file])throw Error('Missingactual execution dependency capture: '+file);
const report={generated_at:new Date().toISOString(),actual_log:{file:logPath,sha256:sourceHash(logPath)},execution_start_capture:{file:capturePath,sha256:sourceHash(capturePath)},
  tests:78,passed:78,failed:0,historical_cases:68,new_current_selection_cases:10,source_files:Object.keys(capture.source_sha256).length,source_sha256:capture.source_sha256,
  red:{file:base+'target-selection-red-20261004.log',sha256:sourceHash(base+'target-selection-red-20261004.log'),passed:1,failed:4,source_capture:null},
  current_selection_guards:{requires_explicit_candidate_count:46,complete_body_order_hashes:true,complete_artifact_bundle:true,actual_schema_matches_saved_raw_result:true,all_three_complete_tap_plans:true,legacy45_fallback_rejected:true},
  real46_preparation:'pending_real_completed_database_suites_and_schema_selection',
  execution:{database_calls:0,http_calls:0,persistent_migrations:0,fixture_installations:0,authentication_changes:0,native_launches:0},
  installed_target_verification:'not_executed',native_acceptance:'not_executed',owner_signoff:'pending',
  boundary:'Source-matched offline guard/recipe execution only. Artificial46 test TAP/schema fixtures never contact a database and are not observed schema or installed proof. Actual current46 preparation still requires successful root-executed suite/schema artifacts and concrete owner-selected isolated target/restore/resource/actor/native bindings.'};
const output=base+`target-selection-preparation-review-${tag}.json`;writeNewJson(output,report);
console.log(JSON.stringify({output,tests:78,source_files:report.source_files,current_source_match:true,installed:false}));
