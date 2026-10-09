import {readFile} from 'node:fs/promises';
import {validateBoundReview,verifyArtifactHashes} from './runtime_launcher.mjs';
try{
 const review=JSON.parse(await readFile(process.argv[2],'utf8')),approval=JSON.parse(await readFile(process.argv[3],'utf8'));
 validateBoundReview(review,approval);await verifyArtifactHashes(review,process.argv[4]);
 process.stdout.write('APPROVED_REVIEW_HASH_VALID\n');
}catch{process.stderr.write('Runtime review refused: missing bindings, explicit owner approval or matching source.\n');process.exitCode=1;}
