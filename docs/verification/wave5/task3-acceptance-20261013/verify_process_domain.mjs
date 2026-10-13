import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {pathToFileURL,fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

const repository=process.cwd();
const output='docs/verification/wave5/task3-acceptance-20261013';
const runName=process.argv[2]??'';
assert.ok(!runName||/^run\d+$/.test(runName));
const suffix=runName?`-${runName}`:'';
const snapshot=path.resolve(output,`process-domain-snapshot${suffix}`);
const packageRoot=path.join(snapshot,'packages/jentra_domain');
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=name=>fs.readFileSync(path.resolve(repository,name));
const bind=name=>({path:name,bytes:read(name).length,sha256:sha(read(name))});
const before=[];
function copyTree(relative){
 const source=path.resolve(repository,relative),target=path.join(snapshot,relative);
 if(fs.statSync(source).isDirectory()){fs.mkdirSync(target,{recursive:true});for(const name of fs.readdirSync(source))copyTree(path.join(relative,name));return;}
 fs.mkdirSync(path.dirname(target),{recursive:true});fs.copyFileSync(source,target);before.push(bind(relative.replaceAll('\\','/')));
}
copyTree('packages/jentra_domain/lib');
for(const file of ['pubspec.yaml','analysis_options.yaml','test/analytics/process_metrics_test.dart','test/analytics/process_filter_contract_test.dart'])copyTree(`packages/jentra_domain/${file}`);
fs.mkdirSync(path.join(snapshot,'.dart_tool'),{recursive:true});
const sourceConfig='.dart_tool/package_config.json';
const config=JSON.parse(read(sourceConfig));
for(const pkg of config.packages){
 pkg.rootUri=pkg.name==='jentra_domain'?pathToFileURL(packageRoot+path.sep).href:new URL(pkg.rootUri,pathToFileURL(path.resolve(repository,sourceConfig))).href;
}
const configPath=path.join(snapshot,'.dart_tool/package_config.json');
fs.writeFileSync(configPath,JSON.stringify(config,null,2)+'\n');
fs.writeFileSync(path.join(snapshot,'pubspec.yaml'),'name: task3_process_domain_verification\npublish_to: none\nenvironment:\n  sdk: ^3.12.2\nworkspace:\n  - packages/jentra_domain\n');
const dart='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe';
const testPackage=config.packages.find(p=>p.name==='test');
const testScript=path.join(fileURLToPath(testPackage.rootUri),'bin/test.dart');
const stages=[];
const taskTemp=path.join(snapshot,'capture-temp');
fs.mkdirSync(taskTemp,{recursive:true});
for(const [name,args] of [
 ['test',[`--packages=${configPath}`,testScript,'--concurrency=1','--reporter=expanded','test/analytics/process_metrics_test.dart','test/analytics/process_filter_contract_test.dart']],
 ['analysis',['analyze','lib/src/analytics/process_metrics.dart','lib/src/analytics/process_metric_repository.dart','lib/src/exact_decimal.dart','lib/src/errors.dart','test/analytics/process_metrics_test.dart','test/analytics/process_filter_contract_test.dart']],
]){
 const startedAt=new Date().toISOString();
 const result=spawnSync(dart,args,{cwd:packageRoot,env:{...process.env,TEMP:taskTemp,TMP:taskTemp},encoding:'utf8',timeout:60000,maxBuffer:4*1024*1024});
 const logPath=`${output}/process-domain-${name}${suffix}.log`;
 fs.writeFileSync(path.resolve(repository,logPath),(result.stdout??'')+(result.stderr??''));
 stages.push({stage:name,startedAt,finishedAt:new Date().toISOString(),command:[dart,...args],cwd:packageRoot,exitCode:result.status,error:result.error?.message??null,log:bind(logPath)});
 if(result.status!==0)break;
}
const after=before.map(item=>bind(item.path));
const unchanged=before.every((item,index)=>item.sha256===after[index].sha256);
const previousPath='docs/verification/wave5/golden-review-processDomain-20261010-r2-serial.json';
const previous=JSON.parse(read(previousPath));
const fixtureContinuity=previous.sourceFixtureBindings.map(item=>({...item,currentSha256:bind(item.path).sha256,currentMatches:item.sha256===bind(item.path).sha256}));
const report={kind:'fresh-isolated-process-domain-verification',recordedAt:new Date().toISOString(),runName,selectedSourceCount:before.length,selectedSourceUnchanged:unchanged,sourceBindings:before,configurationSource:bind(sourceConfig),configurationRebased:'All existing external and workspace package URIs resolved to absolute originals; only jentra_domain points into the isolated exact-byte copy. No pub get, Flutter, build, or shared package cache writes.',temporaryDirectory:taskTemp,testRunner:bind(testScript),sdk:bind(dart),stages,previousEvidence:bind(previousPath),fixtureContinuity,expectedTestIdentities:previous.expectedCaseIdentities,limitations:['Domain fixtures use an exact-byte recognizing test hasher rather than authoritative server trust. This verification covers pure calculation/validation and cannot authorize source access.','The isolated snapshot tests and scoped analysis do not certify native, installed server workflows, external delivery, contention or production.'],passed:unchanged&&fixtureContinuity.every(x=>x.currentMatches)&&stages.length===2&&stages.every(x=>x.exitCode===0)};
fs.writeFileSync(path.resolve(repository,`${output}/process-domain-verification${suffix}.json`),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({kind:report.kind,selectedSourceCount:before.length,selectedSourceUnchanged:unchanged,stages:stages.map(s=>({stage:s.stage,exitCode:s.exitCode,error:s.error})),fixtureContinuity:fixtureContinuity.map(x=>({path:x.path,currentMatches:x.currentMatches})),passed:report.passed},null,2));
assert.equal(report.passed,true);
