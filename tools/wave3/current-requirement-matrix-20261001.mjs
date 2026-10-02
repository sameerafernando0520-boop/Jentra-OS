import fs from 'node:fs';
import crypto from 'node:crypto';
const root='docs/verification/remaining-wave3/';
const prior=JSON.parse(fs.readFileSync(root+'requirement-matrix-20260930.json','utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
if(hash(prior.spec)!==prior.spec_sha256||prior.requirements.length!==181)throw Error('Approved specification drift');
const coverage=JSON.parse(fs.readFileSync(root+'coverage-value-final-reviewed-20261001.json','utf8'));
const build=JSON.parse(fs.readFileSync(root+'windows-build-20261001-value-recovery.json','utf8').replace(/^\uFEFF/,''));
const golden=JSON.parse(fs.readFileSync(root+'golden-control-value-20261001.json','utf8'));
const full='build/remaining-wave3/desktop-value-full-20261001.log';
const matches=[...fs.readFileSync(full,'utf8').matchAll(/\+(\d+)\s+-(\d+):/g)];
if(!matches.length)throw Error('Missing complete client run');
const [passes,failures]=matches.at(-1).slice(1).map(Number);
if(!fs.readFileSync(full,'utf8').includes('Some tests failed.')||failures!==golden.current_failed_cases)throw Error('Incomplete client/golden evidence');
const e={full,inventory:'build/remaining-wave3/inventory-value-render-final-20261001.log',
 reference:'build/remaining-wave3/inventory-shared-final-20261001.log',
 adapters:'build/remaining-wave3/inventory-read-platform-20261001.log',
 payment:'build/remaining-wave3/ap-inventory-interaction-final-20261001.log',
 plans:root+'representative-plans-final-20261001.json',coverage:root+'coverage-value-final-reviewed-20261001.json',
 golden:root+'golden-control-value-20261001.json',build:root+'windows-build-20261001-value-recovery.json',
 review:root+'inventory-recovery-review-20261001.md'};
const updated={
 'FR-395':'Typed root selectors and input-only count/disposition recovery now pass synthetic disconnect, denial, disposal, legacy-envelope and immutable retry checks. Complete native restart, disk exhaustion and every module failure state remain unverified.',
 'NFR-310':'Eleven small-fixture plans include scoped aging/allocation/stock/journal/queue/views and two separately labelled privileged private-bank bases. Reservation basis has zero fixture rows; nested PL/pgSQL and populated target-scale plans remain open.',
 'NFR-313':'Exact input-only count/disposition recovery omits server money/posting evidence; old encrypted forms are sanitized for presentation without rewriting pending commands. Credential Manager and native process-restart acceptance remain open.',
 'NFR-315':`32 recovery and 16 root-access renders cover all required sizes/themes/densities at 200%. Whole desktop has ${passes} passes and ${failures} retained approved-golden failures; current/control-only cases are ${golden.current_only.length}/${golden.control_only.length}. Full native visual acceptance and golden cause remain open.`,
 'NFR-317':`Reviewed pure-domain scope is ${coverage.pure_domain.branches_hit}/${coverage.pure_domain.branches} branches (${coverage.pure_domain.branch_percent.toFixed(2)}%); changed whole-file Dart is ${coverage.changed_dart.lines_hit}/${coverage.changed_dart.lines} lines (${coverage.changed_dart.line_percent.toFixed(2)}%). The 80% gate remains open. SQL assertion counts are not branch coverage.`,
 'NFR-319':`Current isolated copy status is ${build.status}, ${build.seconds.toFixed(1)} s, ${build.source_files} source hashes. Current-source match: ${build.current_source_match}. No executable was launched. Native cold-launch and critical paths remain approval-owned.`,
 'AC-322':'Input-only inventory value recovery, old-envelope presentation, definite denial and original-command acknowledgement pass synthetic checks. Complete native cross-module restart/storage acceptance remains open.',
};
const requirements=prior.requirements.map(r=>({...r,source_evidence:[...r.source_evidence],verification_evidence:[...r.verification_evidence],
 missing_verification:updated[r.id]??r.missing_verification,
 external_acceptance:'45 candidates remain unapplied. Concrete isolated development installation, independent authenticated contention/load, native checks and owner signoff require separate approval.'}));
for(const r of requirements){
 if(['FR-358','FR-354','FR-385','FR-395','AC-315','AC-322','NFR-313','NFR-314','NFR-315'].includes(r.id)){
  r.source_evidence.push('docs/blueprint/51_WAVE3_INVENTORY_EXTENSION_CONTRACT.md','apps/jentra_desktop/lib/src/features/operations/inventory_recovery_inputs.dart');
  r.verification_evidence.push(e.inventory,e.reference,e.adapters,e.review);
 }
 if(['FR-346','FR-348','FR-349','AC-312'].includes(r.id))r.verification_evidence.push(e.payment);
 if(['NFR-310','AC-325'].includes(r.id))r.verification_evidence.push(e.plans);
 if(['NFR-317','AC-326'].includes(r.id))r.verification_evidence.push(e.coverage);
 if(['NFR-315','AC-321','AC-326'].includes(r.id))r.verification_evidence.push(e.golden);
 if(['NFR-319','AC-326'].includes(r.id))r.verification_evidence.push(e.build);
 if(['FR-384','FR-385','AC-326'].includes(r.id))r.verification_evidence.push(e.full);
 r.source_evidence=[...new Set(r.source_evidence)];r.verification_evidence=[...new Set(r.verification_evidence)];
 for(const p of [...r.source_evidence,...r.verification_evidence])if(!fs.existsSync(p))throw Error('Missing referenced evidence '+p);
}
const out={...prior,generated_on:'2026-10-01',requirements,
 boundary:'All approved wording and 181 IDs preserved. Source presence is not exhaustive implementation or installed/native acceptance. Prior dated results are historical; newly confirmed inventory recovery defects were corrected and verified.',
 refreshed_evidence:root+'refresh-value-recovery-20261001.json',
 confirmed_development_corrections:['Root reference/serial epoch invalidation and typed read auth normalization under contract 51.',
 'Count/disposition encrypted recovery excludes server monetary/posting output and preserves original pending command identity.'],
 open_development_gates:['80% changed-overall code coverage','81 approved-golden failures and unresolved rendering cause','Complete cross-module accessibility/error-state review'],
 source_sha256:Object.fromEntries(requirements.flatMap(r=>r.source_evidence).map(p=>[p,hash(p)]))};
fs.writeFileSync(root+'requirement-matrix-20261001.json',JSON.stringify(out,null,2)+'\n');
const link=p=>`[${p.split('/').at(-1)}](../../../${p})`;
fs.writeFileSync(root+'requirement-matrix-20261001.md',[
 '# Approved Wave 3 requirement-to-evidence matrix — 2026-10-01','',
 'All 95 FR, 26 AC, 40 EC and 20 NFR IDs retain their full approved wording in JSON. A referenced source or synthetic check does not prove every scenario. Development verification, installation, native acceptance and owner signoff remain open.','',
 '| ID | Approved behavior | Implementation evidence | Verification evidence | Missing implementation | Missing verification | External acceptance |',
 '|---|---|---|---|---|---|---|',
 ...requirements.map(r=>`| ${r.id} | ${r.approved_behavior.split('**Covers:**')[0].replaceAll('|','/')} | ${r.source_evidence.map(link).join(', ')} | ${r.verification_evidence.map(link).join(', ')} | No further specific code gap confirmed in reviewed scenarios; exhaustive proof remains open | ${r.missing_verification} | Isolated installation, genuine sessions/load, native checks and owner signoff |`),
 '',`Current whole desktop: ${passes} passed, ${failures} approved-golden failures. Coverage/build boundaries are recorded per NFR; Wave 3 is not fully complete.`,''
 ].join('\n'));
console.log(JSON.stringify({total:requirements.length,counts:out.counts,passes,failures,spec_sha256:out.spec_sha256}));
