import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {resolve,relative} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=resolve(fileURLToPath(new URL('../../../../',import.meta.url)));
const directory=resolve(root,'docs/verification/wave5/task3-health-independent-20261015');
const source='tools/wave5/probe_worker_v7_health_20261014_r5.mjs';
const authored='docs/verification/wave5/task3-health-readiness-20261014/health_readiness.test.mjs';
const peers='docs/verification/wave5/task3-health-independent-20261015/peer_cases_a2.mjs';
const combined='docs/verification/wave5/task3-health-independent-20261015/health_readiness.independent-a2.test.mjs';
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const bind=path=>{const bytes=readFileSync(resolve(root,path));return {path,bytes:bytes.length,sha256:digest(bytes)};};
const must=(condition,message)=>{if(!condition)throw Error(message);};
mkdirSync(directory,{recursive:true});
const expectedSource='e01c262cdd75f85c6fb56e155691cf37ac274380a55f92cd39881acd59694108';
const expectedAuthored='3b50385654040c32ae1d48fe73e8ae0216a5d70e329360adb2f118020374758a';
must(bind(source).sha256===expectedSource,'CORE_DRIFT_BEFORE_INDEPENDENT_RUN');
must(bind(authored).sha256===expectedAuthored,'AUTHOR_TEST_DRIFT_BEFORE_INDEPENDENT_RUN');
const authorBytes=readFileSync(resolve(root,authored));
writeFileSync(resolve(root,combined),Buffer.concat([authorBytes,Buffer.from('\n'),readFileSync(resolve(root,peers))]),{flag:'wx'});
const paths=[source,authored,peers,combined,relative(root,fileURLToPath(import.meta.url)).replaceAll('\\','/')];
const before=paths.map(bind),startedAt=new Date().toISOString();
const syntax=[source,authored,combined].map(path=>{
  const run=spawnSync(process.execPath,['--check',resolve(root,path)],{cwd:root,encoding:'utf8',timeout:15000});
  return {path,status:run.status,signal:run.signal,stdout:run.stdout,stderr:run.stderr,error:run.error?.message??null};
});
const run=spawnSync(process.execPath,['--test','--test-reporter=tap','--test-concurrency=1',resolve(root,combined)],
  {cwd:root,encoding:'utf8',timeout:45000,maxBuffer:4*1024*1024});
const tapName='independent-health-a2.tap',errName='independent-health-a2.stderr.txt';
writeFileSync(resolve(directory,tapName),run.stdout??'',{flag:'wx'});
writeFileSync(resolve(directory,errName),run.stderr??'',{flag:'wx'});
const parse=name=>Number(new RegExp('^# '+name+' (\\d+)$','m').exec(run.stdout??'')?.[1]??NaN);
const after=paths.map(bind),unchanged=JSON.stringify(before)===JSON.stringify(after);
const proof={kind:'independent-controlled-health-core-verification',version:1,startedAt,completedAt:new Date().toISOString(),
  root:root.replaceAll('\\','/'),node:process.execPath,nodeVersion:process.version,
  scope:'Local authored sixteen plus independent fourteen synthetic injected-port tests; no actual readiness, network, SQL, SDK or private input.',
  sourceExpected:expectedSource,authoredExpected:expectedAuthored,bindingsBefore:before,bindingsAfter:after,bindingsUnchanged:unchanged,
  syntax,test:{status:run.status,signal:run.signal,error:run.error?.message??null,tests:parse('tests'),passed:parse('pass'),failed:parse('fail'),
    tap:bind(relative(root,resolve(directory,tapName)).replaceAll('\\','/')),stderr:bind(relative(root,resolve(directory,errName)).replaceAll('\\','/'))},
  sourceOnly:true,actualNetworkRequests:0,actualSqlExecutions:0,privateInputsRead:false,liveExecutionPermitted:false,
  passed:syntax.every(row=>row.status===0)&&run.status===0&&parse('tests')===30&&parse('pass')===30&&parse('fail')===0&&unchanged};
writeFileSync(resolve(directory,'independent-local-verification-a2.json'),JSON.stringify(proof,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({passed:proof.passed,tests:proof.test.tests,passedTests:proof.test.passed,failedTests:proof.test.failed,
  exitCode:run.status,source:before[0],proof:bind(relative(root,resolve(directory,'independent-local-verification-a2.json')).replaceAll('\\','/'))}));
process.exitCode=proof.passed?0:1;
