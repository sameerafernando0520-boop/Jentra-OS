import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const prefix='docs/verification/wave5/task3-export-source-independent-20261014/';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const bytes=await fs.readFile(path.join(root,prefix+'independent-local-verification-a1.json'));
const previous=JSON.parse(bytes),output=await fs.readFile(path.join(root,previous.tests.tap.path));
if(hash(output)!==previous.tests.tap.sha256)throw Error('INDEPENDENT_OUTPUT_DRIFT');
const count=name=>{const match=output.toString().match(new RegExp('^[#ℹ] '+name+' (\\d+)\\r?$','m'));if(!match)throw Error('ACTUAL_TEST_COUNT_REQUIRED');return Number(match[1]);};
const sourcesAfter=await Promise.all(previous.sourcesBefore.map(async row=>{const value=await fs.readFile(path.join(root,row.path));return {path:row.path,sha256:hash(value),bytes:value.length};}));
const tests={...previous.tests,tests:count('tests'),passed:count('pass'),failed:count('fail'),cancelled:count('cancelled'),skipped:count('skipped'),
 reporter:'node-spec',output:previous.tests.tap,tap:undefined};
const passed=tests.exitCode===0&&tests.tests===63&&tests.passed===63&&tests.failed===0&&tests.cancelled===0&&tests.skipped===0
 &&previous.syntax.every(row=>row.exitCode===0)&&JSON.stringify(previous.sourcesBefore)===JSON.stringify(sourcesAfter);
const proof={...previous,checkedAt:new Date().toISOString(),tests,sourcesAfter,sourcesUnchanged:JSON.stringify(previous.sourcesBefore)===JSON.stringify(sourcesAfter),passed,
 supersedesCountParsingOnly:{path:prefix+'independent-local-verification-a1.json',sha256:hash(bytes),bytes:bytes.length,
  initialRecordedCounts:previous.tests.tests,actualOutputWasAlreadyPassing:true,
  reason:'Node emitted spec output. The initial parser expected TAP summary markers and recorded zero; parse the preserved actual spec output explicitly.'},
 authoredCases:53,independentPeerCases:10,testsRerunForCorrection:false,originalOutputPreserved:true};
const out=Buffer.from(JSON.stringify(proof,null,2)+'\n'),file=prefix+'independent-local-verification-a2.json';
await fs.writeFile(path.join(root,file),out,{flag:'wx'});
console.log(JSON.stringify({passed,tests:{tests:tests.tests,passed:tests.passed,failed:tests.failed},proof:{path:file,sha256:hash(out),bytes:out.length}}));
process.exitCode=passed?0:1;
