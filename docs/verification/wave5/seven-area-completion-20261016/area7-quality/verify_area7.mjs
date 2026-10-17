import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const root = process.cwd();
const dir = 'docs/verification/wave5/seven-area-completion-20261016';
const own = `${dir}/area7-quality`;
const read = p => JSON.parse(fs.readFileSync(path.join(root, p), 'utf8'));
const binding = p => { const b = fs.readFileSync(path.join(root, p)); return {path:p,bytes:b.length,sha256:crypto.createHash('sha256').update(b).digest('hex')}; };
const checked = [];
function verify(b) {
  assert.equal(typeof b.path, 'string'); assert.match(b.sha256, /^[a-f0-9]{64}$/);
  const now = binding(b.path);
  assert.equal(now.sha256,b.sha256,`Source/evidence drift: ${b.path}`);
  if (b.bytes !== undefined) assert.equal(now.bytes,b.bytes);
  checked.push(now);
}
const matrixPath = 'docs/verification/wave5/task3-acceptance-20261013/delegated-technical-acceptance-matrix.json';
const prereqPath = 'docs/verification/wave5/task3-acceptance-20261013/open-requirement-prerequisites.json';
const matrix = read(matrixPath), prerequisites = read(prereqPath);
const byGroup = Object.fromEntries(prerequisites.groups.map(g=>[g.id,g.rowIds]));
const groups = [['G8'],['G2'],['G1','G4','G7'],['G3','G5'],['G6'],['G9'],['G0','G10']];
const areas = groups.map((g,i)=>({area:i+1,rowIds:g.flatMap(k=>byGroup[k])}));
const assigned = areas.flatMap(a=>a.rowIds);
assert.equal(assigned.length,86); assert.equal(new Set(assigned).size,86);
assert.deepEqual([...assigned].sort(),matrix.rows.filter(r=>!r.accepted).map(r=>r.id).sort());
assert.equal(matrix.totalAcceptedCount,23);

const area2 = read(`${dir}/area2-finance/area2-report.json`);
const area3 = read(`${dir}/area3-permissions-ai/completion-report.json`);
const area5 = read(`${dir}/area5-subscriptions/sourceproof.json`);
for(const b of area2.inputBindings) verify(b);
for(const b of [...area3.sourceBindings,...area3.reviewedReferenceBindings]) verify(b);
for(const v of Object.values(area3.tests)) verify(v.binding);
for(const b of [...area5.sources,...area5.historicalEvidence]) verify(b);
for(const report of [area2,area3,area5]) assert.equal(report.acceptanceDecisionsAdded ?? report.acceptedThisPass ?? report.newAcceptanceCount,0);

const currentPath=`${dir}/current-state-verification-a1.json`, current=read(currentPath);
for(const b of current.sourceBindings) verify(b);
assert.equal(current.cumulativeConservativeCharge,137);
assert.equal(current.mutations,0);
assert.equal(current.actualWorkerTicks,0); assert.equal(current.actualExports,0);
assert.equal(current.scopeAndAuthorityExpired,true); assert.equal(current.threeSchedulesRemainPaused,true);

const tap = p => {const text=fs.readFileSync(path.join(root,p),'utf8');
 const n=k=>{const m=text.match(new RegExp(`^# ${k} (\\d+)$`,'m'));assert.ok(m,`${k}: ${p}`);return Number(m[1]);};
 return {binding:binding(p),tests:n('tests'),passed:n('pass'),failed:n('fail'),skipped:n('skipped')};};
const workerTap=tap(`${dir}/area3-permissions-ai/all-worker-after-fix.tap`);
assert.deepEqual([workerTap.tests,workerTap.passed,workerTap.failed,workerTap.skipped],[260,260,0,0]);
const releasePath='docs/verification/wave5/task3-load-release-20261013/source-release-checks.json';
const release=read(releasePath), releaseTotals={};
for(const c of release.checks) {const state=c.status??c.result; releaseTotals[state]=(releaseTotals[state]??0)+1;}
const ciPath='.github/workflows/ci.yml', ci=fs.readFileSync(ciPath,'utf8');
assert.match(ci,/Build unsigned Windows release/); assert.match(ci,/jentra-os-windows-unsigned/);
const coveragePath='docs/verification/wave5/coverage-final-20261006.json', coverage=read(coveragePath);
const coverageDrift=coverage.files.map(f=>({path:f.path,originalSha256:f.sha256,currentSha256:binding(f.path).sha256,branchPercent:f.branch_percent}));
const gaps={
 'FR-532':'Actual installed provider readiness/missing/incompatible and dependent-operation isolation across all required adapters remain unproved; fixture success grants no live evidence.',
 'FR-533':'The bounded current ownership is attributable; complete historical refresh for every shared composition/authorization/report/workflow/finance integration is not established.',
 'FR-560':'Preserved first slice work and present ownership do not reconstruct every later shared barrel/router/main/migration/dashboard/producer ownership refresh.',
 'AC-516':'Historical rollback and installed ledger are distinct and retained; a complete concurrent shared-change attribution and integration history remains required.',
 'EC-515':'Current source fingerprints are refreshed here; a complete independently bound shared-provider drift/ownership integration event remains required.',
 'NFR-509':'Scoped changed-source analysis and controlled cases pass. Current whole-source zero-findings, critical-domain branch coverage tied to current source, and deterministic coverage of all criteria/edge cases remain required.',
 'NFR-554':'Historical process fixtures and preview results exist, but complete current source-bound native theme/density/200% variants are not authenticated native acceptance.',
 'AC-558':'Malformed scope/UTC/manifest domain cases pass in retained evidence; linked complete provider snapshot and current native quality cases remain incomplete.'
};
const rows=matrix.rows.filter(r=>areas[6].rowIds.includes(r.id)).map(r=>({id:r.id,fullStatement:r.fullStatement,statementSha256:r.statementSha256,decision:'remain_open',reason:gaps[r.id]}));
assert.equal(rows.length,8);
const report={kind:'independent-seven-area-quality-and-release-review',recordedAt:new Date().toISOString(),projectId:current.projectId,
 areaPartition:areas.map(a=>({...a,count:a.rowIds.length})),assignedOpenRows:86,totalAccepted:23,newAcceptanceRecommended:0,area7Rows:rows,
 sourceEvidenceBindingsChecked:checked.length,uniqueVerifiedBindings:[...new Map(checked.map(b=>[b.path,b])).values()],
 semanticReviews:[
 {area:2,conclusion:'No confirmed defect in changed currency/cohort or parsed-cutoff checks.',evidence:'6 focused Flutter cases, scoped analyzer zero findings, 8 controlled retained-finance audit cases; author logs inspected and hashes verified, not rerun here.'},
 {area:3,conclusion:'Early trusted-usage guard precedes protected evidence/quota/provider work; replay validates usage/suggestion before settlement and reauthorizes after await.',evidence:'16 focused and 260 whole-worker controlled cases; actual provider deployment/use remains unproved.'},
 {area:5,conclusion:'Positive authoritative period required; historical generatedAt after periodEnd remains valid. Exact arithmetic/requested period checks retained.',evidence:'5 focused Flutter cases and scoped analyzer zero findings; no live quota race.'},
 {area:6,conclusion:'Trace validator recomputes coverage, scheduled slots, operation classes and P95. Cross-session connection reuse question sent to area author before final freeze.',evidence:'Author work in progress; final source hash/review follow-up will be additive.'},
 {area:4,conclusion:'Draft health/scheduler operation launchers remain separate from actual execution.',evidence:'Author controlled checkpoint inspected; final source package and independent review pending.'}],
 actualWorkerControlledLog:workerTap,currentSavedObservation:{binding:binding(currentPath),databaseObservedAt:current.actualDatabaseObservedAt,cumulativeCharge:137,ledger:115,apiFunctions:363,expiredAuthorities:true,pausedJobs:3,ticks:0,exports:0,scenarios:0,advisorGroups:current.advisorGroups},
 release:{verdict:'NOT_READY_FOR_PRODUCTION',historicalShipGate:{binding:binding(releasePath),checks:release.checks.length,totals:releaseTotals,originalObservedAt:release.observedAt,currentWholeSourceScanClaimed:false},
 ciBinding:binding(ciPath),unsignedBuildConfigured:true,
 gates:[{gate:'staging-production separation and migration rehearsal',status:'missing executed evidence in reviewed artifacts'},
 {gate:'isolated backup restore and consistency/recovery verification',status:'missing executed evidence in reviewed artifacts'},
 {gate:'monitoring and delivered alert receipt',status:'missing executed evidence in reviewed artifacts'},
 {gate:'signed MSIX and clean-account installation/upgrade/rollback',status:'unsigned CI only; separate certificate metadata observation saved'},
 {gate:'performance and accessibility certification',status:'actual target load and authenticated native variant matrix incomplete'},
 {gate:'controlled pilot and release decision',status:'missing executed evidence in reviewed artifacts'}],
 advisorMeaning:'No ERROR-level advisor entries in saved observation. INFO RLS/no-policy findings are not proof of access leakage; index findings are not measured latency. Leaked-password-protection and duplicate-index WARNs require scoped resolution/review, not automatic waiver or destructive index deletion.'},
 historicalCoverage:{binding:binding(coveragePath),originalScope:coverage.scope,criticalDomainBranchesAtLeast90:coverage.critical_domain_branches_at_least_90,currentSourceComparisons:coverageDrift,currentWholeWaveCoverageClaimed:false},
 reviewedInputBindings:[matrixPath,prereqPath,`${dir}/area2-finance/area2-report.json`,`${dir}/area3-permissions-ai/completion-report.json`,`${dir}/area5-subscriptions/sourceproof.json`,`${dir}/area1-windows/README.md`,`${dir}/area4-integrations/checkpoint-lineage.json`,'docs/blueprint/05_TEST_AND_DELIVERY.md'].map(binding),
 actualBoundaries:{liveQueries:0,privateInputsRead:false,SDKJobs:0,deployments:0,sourceCodeMutations:0,globalAcceptanceMatrixModified:false,productionReleasePerformed:false},
 limitation:'This report verifies saved source/evidence bindings and reviewed changes. It does not transform controlled fixtures, historical tests, advisor reads or a successful package build into current native/provider/load/production acceptance.'};
fs.writeFileSync(path.join(root,own,'quality-release-review-a1.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({passed:true,sourceEvidenceBindingsChecked:checked.length,partitionCounts:areas.map(a=>a.rowIds.length),openRows:86,accepted:23,area7NewAcceptances:0,releaseVerdict:report.release.verdict,output:binding(`${own}/quality-release-review-a1.json`)}));
