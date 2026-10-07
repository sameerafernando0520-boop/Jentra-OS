import fs from 'node:fs';
import {reviewedCandidateSelection} from './target_review_selection.mjs';
import {sourceHash,writeNewJson} from './strict-candidate-evidence.mjs';
const [input,output]=process.argv.slice(2);
if(![input,output].every(file=>file?.startsWith('docs/verification/remaining-wave3/')&&file.endsWith('.json')))throw Error('Use explicit task-owned selection input/output.');
const selection=JSON.parse(fs.readFileSync(input,'utf8'));
const verified=reviewedCandidateSelection(selection);
const report={observed_at:new Date().toISOString(),candidate_count:verified.candidate_count,selection,artifacts:verified.artifact_paths.map(file=>({file,sha256:sourceHash(file)})),boundary:verified.boundary,network_calls:0,installed:false};
writeNewJson(output,report);
console.log(JSON.stringify({output,candidate_count:report.candidate_count,artifacts:report.artifacts.length,network_calls:0,installed:false}));

