import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const output='docs/verification/wave5/task3-acceptance-20261013';
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=name=>fs.readFileSync(name);
const json=name=>JSON.parse(read(name));
const bind=name=>({path:name,bytes:read(name).length,sha256:sha(read(name))});
const reportPath=`${output}/delegated-technical-acceptance-matrix.json`;
const report=json(reportPath);
const checks=[];
function check(label,fn){try{fn();checks.push({label,passed:true});}catch(error){checks.push({label,passed:false,error:error.message});}}
check('Complete unique 109-row review and original 106 review coverage',()=>{assert.equal(report.rows.length,109);assert.equal(new Set(report.rows.map(r=>r.id)).size,109);assert.equal(report.reviewedPreviouslyUnacceptedCount,106);});
check('Original 109 historical rows unchanged and accepted IDs preserved',()=>{
 const original=json('docs/verification/wave5/requirement-matrix-20261008.json');
 assert.deepEqual(report.preservedHistoricalRows,original.rows);
 assert.equal(sha(JSON.stringify(original.rows)),report.historicalRowsCanonicalSha256);
 assert.deepEqual(report.originalHumanAcceptedIds,['AC-551','AC-552','AC-553']);
 assert.deepEqual(report.originalHumanAcceptance,original.ownerCriterionAcceptance);
 assert.equal(bind(original.ownerCriterionAcceptance.ownerDecision.path).sha256,original.ownerCriterionAcceptance.ownerDecision.sha256);
});
check('Counts distinguish direct human and delegated decisions',()=>{
 const direct=report.rows.filter(r=>r.decision==='retained_original_human_acceptance');
 const delegated=report.rows.filter(r=>r.decision==='accepted_delegated_technical');
 const open=report.rows.filter(r=>r.decision==='open_missing_evidence');
 assert.equal(direct.length,3);assert.equal(report.originalHumanAcceptedCount,direct.length);
 assert.equal(report.delegatedTechnicalAcceptedCount,delegated.length);assert.equal(report.remainingOpenCount,open.length);
 assert.equal(report.totalAcceptedCount,direct.length+delegated.length);assert.equal(direct.length+delegated.length+open.length,109);
 assert.deepEqual(delegated.map(r=>r.id),report.delegatedTechnicalAcceptedIds);
 assert.equal(report.personalHumanSignatureClaimed,false);assert.equal(report.ownerPersonalSignoff,false);
});
check('Exact full statements extracted independently from approved specifications',()=>{
 const statements=new Map();
 for(const spec of report.specificationBindings){
  assert.equal(bind(spec.path).sha256,spec.sha256);
  const lines=read(spec.path).toString().split(/\r?\n/);
  for(let i=0;i<lines.length;i++){
   const match=/^(?:- |### )((?:FR|NFR|AC|EC)-\d+):/.exec(lines[i]);if(!match)continue;
   let end=i+1;while(end<lines.length&&lines[end].trim()&&!/^(?:- |### )(?:FR|NFR|AC|EC)-\d+:/.test(lines[end]))end++;
   statements.set(match[1],lines.slice(i,end).join(' ').replace(/^(?:- |### )/,'').replace(/\s+/g,' ').trim());
  }
 }
 assert.equal(statements.size,109);
 for(const row of report.rows){assert.equal(row.fullStatement,statements.get(row.id),row.id);assert.equal(row.statementSha256,sha(row.fullStatement),row.id);}
});
check('Bound input documents and checkpoint results unchanged',()=>{
 for(const item of [...report.inputBindings,...report.checkpointEvidenceBindings])assert.equal(bind(item.path).sha256,item.sha256,item.path);
 for(const row of report.rows)for(const item of row.evidence)assert.equal(bind(item.path).sha256,item.sha256,`${row.id} ${item.path}`);
});
check('Every open row has a concrete gap and no accepted-by identity',()=>{
 for(const row of report.rows.filter(r=>!r.accepted)){assert.equal(row.decision,'open_missing_evidence');assert.equal(row.accepted_by,null);assert.ok(row.nextEvidence&&row.nextEvidence.length>40,row.id);assert.ok(row.reason.length>40,row.id);}
});
check('Delegated acceptances bind exact authority and actual calculation cases',()=>{
 const delegation=json(report.authority.path);
 assert.equal(delegation.technicalDecisionAuthority,true);assert.equal(delegation.personalHumanSignatureClaimed,false);
 assert.equal(report.authorityQuote,delegation.source.text);
 const domain=json(`${output}/process-domain-verification-final.json`);
 assert.equal(domain.passed,true);assert.equal(domain.stages[0].exitCode,0);assert.equal(domain.stages[1].exitCode,0);
 assert.equal(domain.actualTestIdentities.length,27);
 for(const source of domain.sourceBindings)assert.equal(bind(source.path).sha256,source.sha256,source.path);
 for(const row of report.rows.filter(r=>r.decision==='accepted_delegated_technical')){
  assert.equal(row.accepted_by,'Codex technical reviewer, delegated by user');
  assert.equal(row.authority.sha256,report.authority.sha256);
  assert.equal(row.nextEvidence,null);assert.ok(row.evidence.length>0);
  if(row.decisionScope.startsWith('Complete pure process')){assert.ok(row.actualTestIdentities.length>0,row.id);for(const identity of row.actualTestIdentities)assert.ok(domain.actualTestIdentities.includes(identity),`${row.id} ${identity}`);}
 }
});
check('Missing native/load/provider behaviors cannot be accepted',()=>{
 for(const id of ['FR-530','FR-531','FR-532','NFR-504','NFR-505','NFR-506','NFR-508','AC-515','EC-513','FR-557','FR-558','FR-559','FR-560','NFR-553','AC-554','AC-556'])assert.equal(report.rows.find(row=>row.id===id).accepted,false,id);
 assert.equal(report.all109Accepted,false);assert.equal(report.wholeWaveComplete,false);assert.equal(report.wholeSystemAccepted,false);assert.equal(report.productionDeploymentPerformed,false);assert.equal(report.realBilling,false);
 assert.ok(Object.values(report.separateOpenGates).every(value=>value===true));
});
check('Fresh results and failures are bounded, preserved and not promoted',()=>{
 assert.equal(report.verifiedFreshResults.process.passed,27);assert.equal(report.verifiedFreshResults.worker.tests,240);assert.equal(report.verifiedFreshResults.worker.fail,0);
 assert.ok(fs.existsSync(`${output}/process-domain-verification.json`));assert.ok(fs.existsSync(`${output}/process-domain-verification-run2.json`));
 assert.match(report.latestDesktopEvidenceBoundary,/dated/);assert.match(report.latestDesktopEvidenceBoundary,/memory/);
 const worker=json(`${output}/worker-v3-independent-review.json`);assert.equal(worker.localVerification.counts.pass,240);assert.equal(worker.customAuthenticationChecksUnchanged,true);
});
const result={kind:'independent-delegated-matrix-invariant-validation',verifiedAt:new Date().toISOString(),matrix:bind(reportPath),markdown:bind(`${output}/delegated-technical-acceptance-matrix.md`),checks,passed:checks.every(item=>item.passed),counts:{reviewed:109,originalHumanAccepted:report.originalHumanAcceptedCount,delegatedTechnicalAccepted:report.delegatedTechnicalAcceptedCount,totalAccepted:report.totalAcceptedCount,open:report.remainingOpenCount}};
fs.writeFileSync(`${output}/acceptance-matrix-validation.json`,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({passed:result.passed,checks:checks.length,failures:checks.filter(item=>!item.passed),counts:result.counts},null,2));
assert.equal(result.passed,true);
