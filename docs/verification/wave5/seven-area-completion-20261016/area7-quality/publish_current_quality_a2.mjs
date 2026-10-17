import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const own='docs/verification/wave5/seven-area-completion-20261016/area7-quality';
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const bind=p=>{const b=fs.readFileSync(p);return {path:p,bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex')};};
const previous=read(own+'/completion-report.json');
const before=read(own+'/domain-before-a5.json');
for(const b of before.sources){assert.equal(bind(b.path).sha256,b.sha256,`Changed since a5: ${b.path}`);assert.equal(bind(b.path).bytes,b.bytes);}
const events=fs.readFileSync(own+'/domain-analytics-current-a5.jsonl','utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse);
assert.equal(events.findLast(r=>r.type==='done').success,true);
const starts=events.filter(r=>r.type==='testStart'&&!r.test.name.startsWith('loading '));
const ids=new Set(starts.map(r=>r.test.id));
const done=events.filter(r=>r.type==='testDone'&&ids.has(r.testID));
assert.equal(done.length,83);assert.ok(done.every(r=>r.result==='success'&&!r.skipped));
assert.equal(fs.readFileSync(own+'/domain-analytics-current-a5.exit.txt','utf8').trim(),'0');
assert.equal(fs.readFileSync(own+'/domain-analytics-analysis-a3.exit.txt','utf8').trim(),'0');
assert.match(fs.readFileSync(own+'/domain-analytics-analysis-a3.log','utf8'),/No issues found!/);
const records=fs.readFileSync(own+'/domain-analytics-current-a5.lcov','utf8').split('end_of_record');
const files=[];let outsideScopeRecords=0;
for(const record of records){
 const source=record.match(/^SF:(.+)$/m)?.[1].trim();if(!source)continue;
 const file=path.relative(process.cwd(),source).replaceAll('\\','/');
 if(!file.startsWith('packages/jentra_domain/lib/src/analytics/')){outsideScopeRecords++;continue;}
 const lines=[...record.matchAll(/^DA:(\d+),(\d+)/mg)],branches=[...record.matchAll(/^BRDA:(\d+),(\d+),(\d+),([\d-]+)/mg)];
 const lineHit=lines.filter(r=>Number(r[2])>0).length,branchHit=branches.filter(r=>Number(r[4])>0).length;
 files.push({source:bind(file),linesHit:lineHit,linesFound:lines.length,linePercent:100*lineHit/lines.length,
  branchesHit:branchHit,branchesFound:branches.length,branchPercent:100*branchHit/branches.length,
  uncoveredBranchLocations:branches.filter(r=>!(Number(r[4])>0)).map(r=>({line:Number(r[1]),block:Number(r[2]),branch:Number(r[3])}))});
}
assert.equal(files.length,9);assert.ok(files.every(r=>r.branchesFound>0&&r.branchPercent>=90));
const aggregate=files.reduce((a,r)=>({linesHit:a.linesHit+r.linesHit,linesFound:a.linesFound+r.linesFound,
 branchesHit:a.branchesHit+r.branchesHit,branchesFound:a.branchesFound+r.branchesFound}),{linesHit:0,linesFound:0,branchesHit:0,branchesFound:0});
aggregate.branchPercent=100*aggregate.branchesHit/aggregate.branchesFound;
aggregate.linePercent=100*aggregate.linesHit/aggregate.linesFound;
const artifacts=['domain-before-a3.json','domain-before-a4.json','domain-before-a5.json',
 'current-quality-test-before-annotation-fix.dart','current-quality-test-before-type-matchers.dart',
 'domain-analytics-current-a3.log','domain-analytics-current-a3.jsonl','domain-analytics-current-a3.lcov','domain-analytics-current-a3.exit.txt',
 'domain-analytics-current-a4.log','domain-analytics-current-a4.jsonl','domain-analytics-current-a4.lcov','domain-analytics-current-a4.exit.txt',
 'domain-analytics-current-a5.log','domain-analytics-current-a5.jsonl','domain-analytics-current-a5.lcov','domain-analytics-current-a5.exit.txt',
 'domain-analytics-analysis-a3.log','domain-analytics-analysis-a3.exit.txt'].map(p=>bind(own+'/'+p));
const proof={kind:'current-analytics-domain-quality-gap-closure',recordedAt:new Date().toISOString(),
 sourceBindingsBeforeAfterUnchanged:before.sources,allCapturedSourcesUnchanged:true,
 productSourceChanges:0,ownedTest:bind('packages/jentra_domain/test/analytics/wave5_current_quality_20261017_test.dart'),
 tests:{baseline:72,newFocusedCases:11,totalPassing:83,failed:0,skipped:0,exitCode:0},
 analysis:{scope:['packages/jentra_domain/lib/src/analytics','packages/jentra_domain/test/analytics'],exitCode:0,findings:0},
 branchInstrumentation:'package:test 1.31.1 --branch-coverage --coverage-path with the cached Dart VM; one complete analytics test run, no LCOV merge or exclusions.',
 files,aggregate,allNineCurrentAnalyticsFilesAtLeast90BranchPercent:true,
 otherLoadedRecords:outsideScopeRecords,scope:'Nine current analytics-domain source files; exact_decimal and unrelated loaded domain files are outside this declared gate, still retained in raw LCOV.',
 addedBehaviors:['Immutable cash override malformed basis/shape/integer/reason/date rejection, duplicate source and unknown override rejection, immutable recovery and nested payload errors.',
 'Historical complete/cutoff/scope/currency-group boundaries, revision order/identity conflicts and zero-cycle unavailable states.',
 'Incomplete or unsupported named-ratio publication basis rejection.',
 'Frozen forecast exact envelope/captured-byte binding, canonical key ordering, recomputed currency totals, immutable observations and missing/invalid field/contract rejection.'],
 controlledHasherBoundary:'CapturedBytesHasher recognizes the exact expected bytes and is explicitly not a cryptographic SHA implementation. Real SHA provider/platform acceptance is not claimed.',
 preservedFailures:[{run:'a3',result:'72 prior tests passed; new suite failed to compile because helper override shadowed @override. Original bytes and outputs retained; fixture helper renamed.'},
 {run:'a4',result:'80 passed,3 failed: new assertions incorrectly expected strings for DateTime dueDate and BigInt version. Product behavior was correct; fixed matcher types only, original bytes retained.'}],
 outputs:artifacts,noNetworkCalls:true,noPrivateInputsRead:true,noDeployment:true,noProductionAcceptance:true,
 whole109CriteriaQualityAccepted:false,requirementsNewlyAccepted:0};
fs.writeFileSync(own+'/domain-current-coverage-a2.json',JSON.stringify(proof,null,2)+'\n',{flag:'wx'});
const successor={...previous,kind:'area7-independent-quality-acceptance-and-release-completion-report-a2',recordedAt:new Date().toISOString(),
 previousCompletionReport:bind(own+'/completion-report.json'),currentSDKVerification:bind(own+'/domain-current-coverage-a2.json'),
 currentSDKSummary:{passed:83,newFocusedCases:11,failed:0,skipped:0,analyzerFindings:0,allNineCurrentAnalyticsFilesAtLeast90BranchPercent:true,
  files:files.map(r=>({path:r.source.path,lines:`${r.linesHit}/${r.linesFound}`,branches:`${r.branchesHit}/${r.branchesFound}`,branchPercent:r.branchPercent})),aggregate,
  full109CriteriaAndCurrentNativeQualityProved:false},
 rows:previous.rows.map(r=>r.id==='NFR-509'?{...r,reason:'Current nine-file analytics-domain gate now has >=90% real branch coverage per file and zero scoped analyzer findings; deterministic fixtures for every one of the 109 criteria, full current source analysis and all linked native/provider cases remain unproved.'}:r),
 actualActions:{...previous.actualActions,currentDomainAnalyticsCases:83,productSourceChanges:0,newTestCases:11},
 limitations:'This successor closes the requested current analytics-domain branch gaps. It preserves the old 72-pass/82.54% report and every failed fixture iteration. Native, genuine provider, actual race/load and production gates remain distinct; 23 accepted/86 open is unchanged.'};
fs.writeFileSync(own+'/completion-report-a2.json',JSON.stringify(successor,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({passed:true,cases:83,files:successor.currentSDKSummary.files,aggregate,
 coverage:bind(own+'/domain-current-coverage-a2.json'),report:bind(own+'/completion-report-a2.json')}));
