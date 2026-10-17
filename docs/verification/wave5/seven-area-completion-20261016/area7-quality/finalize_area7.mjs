import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const base='docs/verification/wave5/seven-area-completion-20261016',own=base+'/area7-quality';
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const bind=p=>{const b=fs.readFileSync(p);return {path:p,bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex')};};
const verified=[];
function verify(b){assert.equal(bind(b.path).sha256,b.sha256,`Drift: ${b.path}`);if(b.bytes!==undefined)assert.equal(bind(b.path).bytes,b.bytes);verified.push(bind(b.path));}
const original=read(own+'/quality-release-review-a1.json');
for(const b of original.uniqueVerifiedBindings)verify(b);
const a1=read(base+'/area1-windows/source-and-historical-evidence-verification.json');
for(const b of a1.verifiedHistoricalEvidence)verify(b);
for(const r of a1.sourceComparison){assert.equal(bind(r.path).sha256,r.currentSha256);assert.equal(r.currentMatchesSavedSnapshot,true);verified.push(bind(r.path));}
const a4=read(base+'/area4-integrations/completion-report.json');
for(const b of [...a4.sourceBeforeAfterUnchanged,...a4.inputBindings,...a4.evidenceBindings])verify(b);
verify(a4.deployedArchive.manifest);
const a6=read(base+'/area6-load/completion-report.json');
for(const b of [...a6.sourceBindings,...a6.historicalSourceInputs])verify(b);
for(const v of Object.values(a6.verification))if(v?.log)verify(v.log);
assert.equal(a4.controlledTests.pass,27);assert.equal(a4.acceptedByThisWork,0);
assert.equal(a6.verification.distinctPassingTests,204);assert.equal(a6.actual.fullTargetLoad,'NOT_RUN');
const trace=fs.readFileSync('tools/wave5/runtime_load_trace_20261017_r5.mjs','utf8');
assert.match(trace,/connections\.get\(p\.connectionId\) === p\.sessionId/);
assert.match(trace,/actualMaximumLag === result\.maximumDispatchLagMs/);
assert.match(trace,/peak <= result\.peakInflightRequests/);
const before=read(own+'/domain-before-a1.json');for(const b of before.sources)verify(b);
const jsonl=fs.readFileSync(own+'/domain-analytics-current-a2.jsonl','utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse);
assert.equal(jsonl.findLast(r=>r.type==='done').success,true);
const testIds=new Set(jsonl.filter(r=>r.type==='testStart'&&!r.test.name.startsWith('loading ')).map(r=>r.test.id));
const outcomes=jsonl.filter(r=>r.type==='testDone'&&testIds.has(r.testID));
assert.equal(outcomes.length,72);assert.ok(outcomes.every(r=>r.result==='success'&&!r.skipped));
assert.equal(fs.readFileSync(own+'/domain-analytics-current-a2.exit.txt','utf8').trim(),'0');
assert.equal(fs.readFileSync(own+'/domain-analytics-analysis-a2.exit.txt','utf8').trim(),'0');
assert.match(fs.readFileSync(own+'/domain-analytics-analysis-a2.log','utf8'),/No issues found!/);
const raw=fs.readFileSync(own+'/domain-analytics-current-a2.lcov','utf8');assert.ok(raw.length>0);
const analytics=[];let nonAnalyticsRecords=0;
for(const record of raw.split('end_of_record')){
 const sf=record.match(/^SF:(.+)$/m)?.[1].trim();if(!sf)continue;
 const rel=path.relative(process.cwd(),sf).replaceAll('\\','/');
 if(!rel.startsWith('packages/jentra_domain/lib/src/analytics/')){nonAnalyticsRecords++;continue;}
 const lines=[...record.matchAll(/^DA:\d+,(\d+)/mg)],branches=[...record.matchAll(/^BRDA:\d+,\d+,\d+,([\d-]+)/mg)];
 const lineHit=lines.filter(r=>Number(r[1])>0).length,branchHit=branches.filter(r=>Number(r[1])>0).length;
 analytics.push({source:bind(rel),lineHit,lineCount:lines.length,linePercent:100*lineHit/lines.length,branchHit,branchCount:branches.length,branchPercent:100*branchHit/branches.length});
}
const cash=analytics.find(r=>r.source.path.endsWith('/cash_scenarios.dart'));assert.ok(cash);
assert.deepEqual([cash.lineHit,cash.lineCount,cash.branchHit,cash.branchCount],[76,76,25,25]);
const sums=analytics.reduce((a,r)=>({lines:a.lines+r.lineCount,lineHit:a.lineHit+r.lineHit,branches:a.branches+r.branchCount,branchHit:a.branchHit+r.branchHit}),{lines:0,lineHit:0,branches:0,branchHit:0});
const sdkOutputs=['domain-before-a1.json','domain-analytics-current-a1.log','domain-analytics-current-a1.jsonl','domain-analytics-current-a1.lcov','domain-analytics-current-a2.log','domain-analytics-current-a2.jsonl','domain-analytics-current-a2.lcov','domain-analytics-current-a2.exit.txt','domain-analytics-analysis-a1.log','domain-analytics-analysis-a1.exit.txt','domain-analytics-analysis-a2.log','domain-analytics-analysis-a2.exit.txt'].map(p=>bind(own+'/'+p));
const coverage={kind:'current-scoped-domain-analytics-test-and-genuine-branch-coverage',recordedAt:new Date().toISOString(),sourceInputsBeforeAfterUnchanged:before.sources.length,sourceBindings:before.sources,
 testCases:{passed:72,failed:0,skipped:0,exitCode:0},analyzer:{exitCode:0,findings:0,scope:['packages/jentra_domain/lib/src/analytics','packages/jentra_domain/test/analytics']},
 analyticsFiles:analytics,analyticsTotals:sums,analyticsBranchPercent:100*sums.branchHit/sums.branches,nonAnalyticsLoadedRecordsExcluded:nonAnalyticsRecords,
 cashSourceDriftGapResolved:true,allCurrentCriticalBranchesAtLeast90:false,
 preservedInfrastructureFailures:[{run:'test a1',reason:'Sandbox could not copy cached kernel into its Temp directory, errno5; all seven suites failed loading before assertions; process exit -1073741816; empty LCOV is not evidence.'},
 {run:'analyzer a1',reason:'Analyzer reported zero issues but telemetry cache modification was denied; exit1. Approved exact rerun a2 exited0.'}],
 outputs:sdkOutputs,limitation:'Requested analytics-only tests cover nine analytics source files with unequal coverage; zero repository hits and uncovered branches remain visible. No whole-domain, 109-case, installed, native, model-provider or production acceptance inferred.'};
fs.writeFileSync(own+'/domain-current-coverage-a1.json',JSON.stringify(coverage,null,2)+'\n',{flag:'wx'});
const report={kind:'area7-independent-quality-acceptance-and-release-completion-report',recordedAt:new Date().toISOString(),projectId:original.projectId,
 assignedRows:8,rows:original.area7Rows,newAcceptedRows:0,totalAccepted:23,remainingOpen:86,sevenAreaPartition:original.areaPartition,
 verifiedBindings:[...new Map(verified.map(b=>[b.path,b])).values()],
 previousBoundedReview:bind(own+'/quality-release-review-a1.json'),currentSDKVerification:bind(own+'/domain-current-coverage-a1.json'),
 currentSDKSummary:{passed:72,failed:0,skipped:0,analyzerFindings:0,cashLines:'76/76',cashBranches:'25/25',analyticsTotals:sums,wholeCurrentCritical90PercentProved:false},
 independentFinalReviews:[{area:1,report:bind(base+'/area1-windows/source-and-historical-evidence-verification.json'),conclusion:'25 historical bindings and ten unchanged current native-source comparisons verified; actual authenticated native acceptance remains false.'},
 {area:4,report:bind(base+'/area4-integrations/completion-report.json'),sourceBindings:a4.sourceBeforeAfterUnchanged,controlledPassingTests:27,
 conclusion:'Source/public lock inventory validates every required binding, health imports are mandatory, actual-renewal chronology and exact paused-job/health gates remain bounded. Deployed archive retains the actual V7 source separately from changed model candidate. No confirmed additional source defect in this review; no operation ran.'},
 {area:6,report:bind(base+'/area6-load/completion-report.json'),controlledDistinctPassingTests:204,
 conclusion:'Final trace guards reject cross-session connection reuse and reconcile actual dispatch lag and lower-bound real transport peak, addressing the independent review question. CLI requires new validator source binding; counts and final source/evidence hashes verified. Genuine races/target load remain unrun.',
 conditionalScope:'NFR-505 governs larger allowed work. Missing a larger-work route in this load provider alone is not a mandatory product defect if larger work is rejected by supported synchronous caps; actual supported-operation inventory and crash/cancel evidence must establish scope.'}],
 preservedReportInterpretation:'Initial a1 is retained with its then-pending area4/6 status. This additive report verifies the subsequent final freezes and current SDK run; the historical 51-binding/old-coverage observations are not rewritten.',
 release:{...original.release,codeSigningMetadata:bind(own+'/code-signing-metadata-a1.json'),currentWholeWaveCoverageClaimed:false},
 categories:{confirmedProductDefects:'Area2/3/5/6 reports record repaired source defects with controlled regression evidence. No further confirmed unresolved product defect is manufactured by this independent review.',
 missingEvidence:'Actual allowed/denied/revoked native/provider/scenario/export/integration/entitlement/race/load observations, complete ownership history and current whole-quality coverage remain open.',
 missingExternalReleasePrerequisites:'Separate staging/production, restore, alert delivery, signing, certification and pilot are unexecuted in reviewed artifacts.'},
 actualActions:{liveQueries:0,privateInputsRead:false,SDKTestsExecuted:true,currentDomainAnalyticsCases:72,SDKAnalyzerExecuted:true,deployments:0,productionRelease:false,globalAcceptanceMatrixModified:false}};
fs.writeFileSync(own+'/completion-report.json',JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({passed:true,verifiedUniqueBindings:report.verifiedBindings.length,SDK:report.currentSDKSummary,report:bind(own+'/completion-report.json'),coverage:bind(own+'/domain-current-coverage-a1.json')}));
