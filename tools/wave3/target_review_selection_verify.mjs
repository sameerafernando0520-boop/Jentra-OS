import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {sourceHash} from './strict-candidate-evidence.mjs';

const file=process.argv[2];
if(!file?.startsWith('docs/verification/remaining-wave3/')||!file.endsWith('.json'))throw Error('Pass an explicit dated actual offline selection review.');
const review=JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
assert.equal(review.tests,78);assert.equal(review.passed,78);assert.equal(review.failed,0);
assert.equal(review.actual_log.sha256,sourceHash(review.actual_log.file));
assert.equal(review.execution_start_capture.sha256,sourceHash(review.execution_start_capture.file));
for(const value of Object.values(review.execution))assert.equal(value,0);
assert.equal(review.installed_target_verification,'not_executed');assert.equal(review.native_acceptance,'not_executed');assert.equal(review.owner_signoff,'pending');
for(const [file,expected]of Object.entries(review.source_sha256))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(file,'utf8')).digest('hex'),expected,'Offline execution source drift: '+file);
console.log(JSON.stringify({review_integrity:'passed',offline_checks:78,source_files:review.source_files,real46_preparation:review.real46_preparation,
  boundary:'Offline source/execution integrity only. No inferred database implementation, installation/session/load/native acceptance, harness completion or owner release.'}));
