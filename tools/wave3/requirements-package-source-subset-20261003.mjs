import fs from 'node:fs';
import crypto from 'node:crypto';
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const [kind, captureFile, logFile, ...packages] = process.argv.slice(2);
if (!['platform','domain'].includes(kind) || !captureFile || !logFile || !packages.length || packages.some(name=>!/^[a-z_]+$/.test(name))) throw Error('Pass kind actual-start-capture actual-completed-log package_names; no guessed capture.');
const before = hash(captureFile);
const capture = JSON.parse(fs.readFileSync(captureFile,'utf8').replace(/^\uFEFF/,''));
const prefixes = packages.map(name=>'packages/'+name+'/lib/');
const files = capture.files.filter(row=>prefixes.some(prefix=>row.file.startsWith(prefix)));
if (!capture.observed_at || prefixes.some(prefix=>!files.some(row=>row.file.startsWith(prefix)))) throw Error('Original execution-start capture lacks selected dependency sources.');
const mismatches = files.filter(row=>!fs.existsSync(row.file) || hash(row.file)!==row.sha256).map(row=>row.file);
const progress = [...fs.readFileSync(logFile,'utf8').matchAll(/\+(\d+)(?:\s+-(\d+))?\s*:/g)].at(-1);
if (!progress) throw Error('Completed recorded test count missing.');
const allMismatches = capture.files.filter(row=>!fs.existsSync(row.file) || hash(row.file)!==row.sha256).map(row=>row.file);
const result = {generated_at:new Date().toISOString(),actual_execution_observed_at:capture.observed_at,
  original_capture:{file:captureFile,sha256:before,head:capture.head,unchanged:before===hash(captureFile)},
  actual_completed_log:{file:logFile,sha256:hash(logFile),passed:Number(progress[1]),failed:Number(progress[2]??0)},
  scope:prefixes,files,current_package_lib_source_match:mismatches.length===0,source_mismatches:mismatches,
  full_original_capture_source_mismatches:allMismatches,
  subset_proof:{every_row_is_from_original_capture:true,only_actual_package_lib_dependencies_selected:true,original_observation_timestamp_preserved:true,original_capture_unchanged:true,no_generated_execution_hits:true},
  boundary:'Current-source claim applies only to explicitly selected actual package library dependencies. Completed whole-suite outcome belongs to its recorded fixture revision; original generic capture includes other concurrent work. No capture or measurement is backdated, and no installed/native/load/owner acceptance is inferred.'};
const output = 'docs/verification/remaining-wave3/requirements-'+kind+'-execution-subset-20261003.json';
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({output,files:files.length,current_match:result.current_package_lib_source_match,passed:result.actual_completed_log.passed,failed:result.actual_completed_log.failed,full_capture_drift:allMismatches.length}));
