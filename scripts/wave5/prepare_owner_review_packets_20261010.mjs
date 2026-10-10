import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';

// New review artifacts only. Never updates a golden, source, matrix, or acceptance store.
const root = process.cwd();
const out = 'docs/verification/wave5';
const matrixPath = `${out}/requirement-matrix-20261008.json`;
const nativePath = `${out}/windows-test-verification-20261009-r13.json`;
const livePath = `${out}/continuation-live-summary-20261010.json`;
const reviewPath = `${out}/complete-app-runtime-review-20261009-r13.json`;
const read = p => fs.readFileSync(path.resolve(root, p));
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const hash = p => sha(read(p));
const json = p => JSON.parse(read(p));
const binding = p => ({ path: p, sha256: hash(p) });
const observedAt = new Date().toISOString();
const head = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const status = execFileSync('git', ['status', '--short'], { encoding: 'utf8' }).trim();
const matrix = json(matrixPath), native = json(nativePath), live = json(livePath), review = json(reviewPath);
if (matrix.rows.length !== 109 || matrix.ownerAcceptedCriteria !== 0 || matrix.rows.some(r => r.ownerAccepted)) {
  throw new Error('Owner acceptance changed; refresh and review before preparing a packet.');
}
if (native.goldenFailures.length !== 83 || native.nativeKeyboardVerified || review.ownerApproved) {
  throw new Error('Recorded gate state changed; refresh the review.');
}
const inputBindings = [matrixPath, nativePath, livePath, reviewPath,
  `${out}/continuation-goldens-native-20261009.json`,
  `${out}/process-foundation-20260930.json`, `${out}/process-foundation-20260930.md`,
  `${out}/preflight-20260930.json`, `${out}/continuation-status-20261010-r13.json`,
  `${out}/complete-app-candidate-result-20261009.json`,
  `${out}/complete-app-bootstrap-probe-result-20261009.json`,
  `${out}/installation-result-20261008.json`].map(binding);

function rgba(p) {
  const b = read(p);
  if (!b.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || b[24] !== 8 || b[25] !== 6 || b[28] !== 0) {
    throw new Error(`Unsupported PNG format: ${p}`);
  }
  const w = b.readUInt32BE(16), h = b.readUInt32BE(20), chunks = [];
  for (let i = 8; i < b.length;) {
    const n = b.readUInt32BE(i), kind = b.toString('ascii', i + 4, i + 8);
    if (kind === 'IDAT') chunks.push(b.subarray(i + 8, i + 8 + n));
    i += n + 12;
  }
  const raw = zlib.inflateSync(Buffer.concat(chunks)), stride = w * 4, result = Buffer.alloc(stride * h);
  if (raw.length !== (stride + 1) * h) throw new Error(`PNG byte count: ${p}`);
  const paeth = (a,b,c) => { const v=a+b-c, da=Math.abs(v-a), db=Math.abs(v-b), dc=Math.abs(v-c); return da<=db&&da<=dc?a:db<=dc?b:c; };
  for (let y = 0; y < h; y++) {
    const f=raw[y*(stride+1)], start=y*stride;
    if (f>4) throw new Error(`PNG filter: ${p}`);
    for (let x=0;x<stride;x++) {
      const a=x>=4?result[start+x-4]:0, b=y>0?result[start+x-stride]:0, c=y>0&&x>=4?result[start+x-stride-4]:0;
      const predictor=[0,a,b,Math.floor((a+b)/2),paeth(a,b,c)][f];
      result[start+x]=(raw[y*(stride+1)+x+1]+predictor)&255;
    }
  }
  return { w,h,data:result };
}
function measure(a,b) {
  const x=rgba(a),y=rgba(b); if(x.w!==y.w||x.h!==y.h) throw new Error('Dimension drift');
  let count=0, alpha=0, max=0, x0=x.w,y0=x.h,x1=-1,y1=-1;
  for(let i=0;i<x.data.length;i+=4) {
    let diff=false;
    for(let c=0;c<4;c++){const d=Math.abs(x.data[i+c]-y.data[i+c]);max=Math.max(max,d);diff ||= d!==0;}
    if(x.data[i+3]!==y.data[i+3]) alpha++;
    if(diff){count++;const px=(i/4)%x.w,py=Math.floor(i/4/x.w);x0=Math.min(x0,px);y0=Math.min(y0,py);x1=Math.max(x1,px);y1=Math.max(y1,py);}
  }
  return { dimensions:[x.w,x.h], differentPixels:count, differentPercent:100*count/(x.w*x.h), bbox:[x0,y0,x1+1,y1+1], bboxCoordinates:'left/top inclusive; right/bottom exclusive', maximumChannelDelta:max, changedAlphaPixels:alpha };
}

const traces = [
  { path:'apps/jentra_desktop/lib/src/features/people/payroll_screen.dart', line:428, purpose:'people.payroll.view gates the navigation action; it opens PayrollCorrectionScreen in a dialog without issuing a correction command.' },
  { path:'apps/jentra_desktop/lib/src/features/people/payroll_correction_controller.dart', line:21, purpose:'Current operational scope, loaded capabilities, source repositories and people.payroll.view are independently required; encrypted drafts reauthorize through the correction repository.' },
  { path:'apps/jentra_desktop/lib/src/features/people/payroll_correction_screen.dart', line:74, purpose:'Preparation is a separate capability/action; busy or offline disables it. Missing controller shows an unavailable state.' },
  { path:'supabase/migrations/20261001110000_wave4_payroll_corrections.sql', line:165, purpose:'Candidate server correction_access validates named capability/current People access and genuine aal2 for protected write/read flows; this SQL is not installed runtime proof.' },
  { path:'docs/blueprint/63_WAVE4_PAYROLL_CORRECTIONS_CONTRACT.md', line:20, purpose:'Prepare/approve/source-view permissions and current entitlement/scope/MFA checks remain distinct.' },
  { path:'docs/blueprint/53_WAVE4_SYNTHETIC_PAYROLL_CONTRACT.md', line:96, purpose:'Separate payroll command capabilities; live entitlement/scope/capability/MFA revalidation.' },
  { path:'docs/development/wave4-status.md', line:10, purpose:'October 6 checkpoint already records these same two intentional toolbar comparisons with approved images preserved.' },
  { path:'apps/jentra_desktop/test/payroll_workspace_test.dart', line:506, purpose:'Layout-only fixture uses all payroll capabilities, 1440x1100 and 200% text; it does not tap the dialog, authenticate, or prove native keyboard access.' }
].map(t=>({...t,sha256:hash(t.path)}));
const retained = json(`${out}/continuation-goldens-native-20261009.json`);
const payroll = retained.cases.filter(c=>c.classification==='payroll-content-change');
if(payroll.length!==2) throw new Error('Expected exactly two payroll cases');
const cases = payroll.map(c=>{
  const base=`build/w5win9r13/preview/apps/jentra_desktop/test/failures/${c.stem}`;
  const approved=binding(c.approved), current=binding(`${base}_testImage.png`), master=binding(`${base}_masterImage.png`), diff=binding(`${base}_isolatedDiff.png`);
  const retainedCurrent=c.renders.find(r=>r.kind==='testImage');
  if(approved.sha256!==c.approvedSha256||master.sha256!==approved.sha256||current.sha256!==retainedCurrent.sha256) throw new Error(`Payroll provenance drift ${c.stem}`);
  const measured=measure(approved.path,current.path);
  for(const k of ['dimensions','differentPixels','bbox','maximumChannelDelta','changedAlphaPixels']) {
    if(JSON.stringify(measured[k])!==JSON.stringify(c[k])) throw new Error(`Pixel measurement drift ${c.stem}/${k}`);
  }
  return { stem:c.stem, theme:c.stem.includes('light')?'light':'dark', textScale:2, approved, currentCandidate:current, master, isolatedDiff:diff, ...measured,
    changedArea:'Top toolbar only: Linked corrections is present and Reload moves right. No changed pixels outside the measured bounding box.',
    cause:'Intentional authorized Wave 4 feature already present in historical commit d7a2022; the approved image predates this toolbar content.',
    decisionProposal:'Keep the permission-gated navigation action. After an explicit exact-image owner visual decision, replace only this approved PNG with these candidate bytes and rerun the unchanged strict comparison.',
    ownerVisualDecision:null, approvedBaselineUpdated:false, navigationOrMfaVerified:false };
});
const payrollPacket = { observedAt, gitHead:head, concurrentStatusAtRead:status, state:'review proposal; owner visual decision absent',
  inputBindings, sourceTraces:traces, cases,
  boundary:'Fresh read-only SHA-256 and decoded-pixel measurements of retained r13 images, previously viewed as approved/current/diff. No newly run Flutter/native test. No approved image or source is changed.',
  permissionsConclusion:'Viewing the corrections workspace requires payroll view; preparation, decisions, posting and recovery remain independently gated. The fixture proves toolbar composition only. The missing installed correction provider and genuine MFA/native action checks remain open.',
  recommendation:'Approve the two exact candidate images if the toolbar is desired. Preserve Wave 4 source and strict comparator. Image approval is independent from runtime bundle approval and 109 requirement decisions.',
  nativeKeyboardVerified:false, runtimeApproved:false, ownerAcceptedCriteria:0 };

const reviewReasons = {
  'FR-533':{scope:'Preservation and ownership refresh during this continuation, as a development checkpoint.',reason:'The original review/r10 evidence is retained; r13 binds selected current source and packages, and the status writer checks concurrent source/document hashes before replacement. Historical source attribution remains inspectable.',evidence:[nativePath,reviewPath,`${out}/continuation-status-20261010-r13.json`,'scripts/wave5/update_continuation_status_20261010.mjs'],obligations:'Continue ownership refresh before each shared change. Review this observed continuation only; future changes are not preapproved.'},
  'FR-534':{scope:'Candidate-versus-installed SQL boundary and recorded exact approval target/list.',reason:'Historical strict candidates end in rollback; fresh connected baseline still reports 43 migrations, 107 APIs and 120/120 unchanged fingerprints. The six installed originals are excluded from the exact 71-migration runtime proposal, which remains unapproved.',evidence:[livePath,reviewPath,`${out}/complete-app-candidate-result-20261009.json`,`${out}/complete-app-bootstrap-probe-result-20261009.json`,`${out}/installation-result-20261008.json`],obligations:'Refresh live state before a future authorized operation; historical rollback checks do not prove installed candidate behavior.'},
  'FR-536':{scope:'Accuracy of the current completion report, independently of product completion.',reason:'The current native/status/runtime reports name source/test/build/installed/native/MFA/delivery/contention/load/owner gates separately and retain the failing strict desktop suite.',evidence:[nativePath,reviewPath,`${out}/continuation-status-20261010-r13.json`,'docs/development/wave5-status.md'],obligations:'Keep reports current and separately identify later results; this decision does not accept unfinished functionality.'},
  'FR-560':{scope:'Historical first W5-01 implementation ownership, with current integration attribution retained.',reason:'The September 30 foundation/preflight records explicitly list six new slice-owned source/test files, no shared producer/lockfile edits and an unchanged ledger. Current source has evolved; the original record is historical attribution only.',evidence:[`${out}/process-foundation-20260930.md`,`${out}/process-foundation-20260930.json`,`${out}/preflight-20260930.json`,nativePath],obligations:'Owner must review the historical first-step attribution. Do not interpret its old source/test hashes as current calculation or integration verification.'},
  'AC-516':{scope:'Concurrent development and strict candidate rollback boundary.',reason:'Owned artifacts and source manifests preserve W3/W4 attribution; the historical strict rollback results and fresh unchanged live fingerprints are separately recorded.',evidence:[livePath,reviewPath,`${out}/complete-app-candidate-result-20261009.json`,`${out}/complete-app-bootstrap-probe-result-20261009.json`,`${out}/continuation-status-20261010-r13.json`],obligations:'Source preservation is a continuing rule. No candidate installation or dependent runtime outcome is accepted by this decision.'},
  'AC-517':{scope:'Honest reporting of this slice evidence.',reason:'The reports record clean scoped analysis, full platform success, 83 strict desktop failures, ordinary Windows packages and controlled worker tests while keeping native/MFA/delivery/load/owner outcomes false.',evidence:[nativePath,reviewPath,`${out}/continuation-status-20261010-r13.json`,'docs/development/wave5-status.md'],obligations:'This report criterion does not waive NFR-509 coverage/fixture obligations or turn scoped analysis into whole-repository analysis.'},
  'AC-557':{scope:'Historical first domain implementation attribution.',reason:'The original W5-01 foundation record explicitly attests only new W5-01 source/tests and owned evidence were changed; the preflight captures the concurrent checkout boundary.',evidence:[`${out}/process-foundation-20260930.md`,`${out}/process-foundation-20260930.json`,`${out}/preflight-20260930.json`],obligations:'Review the September 30 checkpoint itself. Current source/functionality, server integration and native acceptance remain separate.'},
  'EC-515':{scope:'Refreshing concurrent ownership/fingerprints before integration in this continuation.',reason:'The current source manifest and living-document byte guards reject changed shared inputs, while the refreshed connected summary records 120/120 unchanged provider fingerprints.',evidence:[livePath,nativePath,`${out}/continuation-status-20261010-r13.json`,'scripts/wave5/update_continuation_status_20261010.mjs'],obligations:'Repeat the refresh before each integration; this point-in-time observation is not a guarantee about later edits.'},
  'EC-516':{scope:'Retaining unproved gates despite passing fixtures.',reason:'The full reports keep installation, authenticated native, genuine MFA, actual provider/worker delivery, independent contention/load and owner acceptance open despite successful controlled/scoped checks.',evidence:[nativePath,reviewPath,`${out}/continuation-status-20261010-r13.json`],obligations:'Maintain these false gates until direct evidence and exact owner decisions exist.'}
};
const blocking = {
  shared:['runtime_bundle_approval','installed_provider_and_permission_evidence','genuine_authenticated_authorization','criterion_specific_quality_or_load_evidence','explicit_owner_acceptance'],
  provider:['runtime_bundle_approval','installed_compatible_provider_readiness','real_nonempty_authorized_sources','explicit_owner_acceptance'],
  process:['current_domain_and_adapter_evidence_for_exact_scope','installed_authorization_and_source_semantics_where_required','native_access_change_and_keyboard_where_required','explicit_owner_acceptance'],
  pipeline:['runtime_bundle_approval','installed_historical_realized_cohorts','genuine_authorized_and_denied_sessions','explicit_owner_acceptance'],
  finance:['runtime_bundle_approval','installed_statement_publications_and_classifications','genuine_distinct_mfa_and_authorized_ratios','explicit_owner_acceptance'],
  cash:['runtime_bundle_approval','installed_authoritative_dates_and_residuals','genuine_distinct_mfa','native_recovery_export_create_download_reopen_revocation','explicit_owner_acceptance'],
  ai:['runtime_bundle_approval','private_provider_and_worker_configuration','actual_trusted_model_usage_settlement','genuine_distinct_mfa_and_stale_revoked_execution','explicit_owner_acceptance'],
  integration:['runtime_bundle_approval','reviewed_private_worker_and_destination_setup','actual_signed_delivery_receipt_unknown_reconciliation_replay_restart','independent_session_contention','explicit_owner_acceptance'],
  billing:['runtime_bundle_approval','installed_trusted_synthetic_activation_usage','persistent_scheduling_and_independent_reservation_contention','explicit_owner_acceptance'],
  operator:['runtime_bundle_approval','separate_operator_identity_and_authority','genuine_mfa_scoped_expiring_grant_and_audited_denial','explicit_owner_acceptance'],
  native:['exact_visual_decisions_and_strict_regression','authenticated_native_keyboard_restart_context_revoke_offline_recovery','genuine_mfa_where_required','explicit_owner_acceptance'],
  quality:['criterion_specific_current_analysis_coverage_and_projection_scans','actual_runtime_binary_export_prompt_log_checks_where_required','explicit_owner_acceptance'],
  load:['runtime_bundle_approval','installed_bounded_worker_runtime','independent_session_barrier_races','target_scale_populations_latency_errors_host_tier','explicit_owner_acceptance']
};
const pureCalculation = new Set(['FR-551','FR-553','FR-554','FR-555','FR-556','NFR-551','AC-551','AC-552','AC-553','EC-551','EC-554','EC-555']);
function fullStatement(r) {
  const lines=read(r.specification).toString('utf8').split(/\r?\n/); const result=[];
  for(let i=r.specificationLine-1;i<lines.length;i++) {
    const line=lines[i];
    if(i>r.specificationLine-1 && (!line.trim() || /^(?:- |###? )?(?:FR|NFR|AC|EC)-\d+:/.test(line) || /^## /.test(line))) break;
    result.push(line.replace(/^(?:- |### )/, '').trim());
  }
  if(!result[0]?.startsWith(`${r.id}:`)) throw new Error(`Specification binding drift ${r.id}`);
  return result.join(' ');
}
const rows=matrix.rows.map(r=>{
  const proposal=reviewReasons[r.id];
  const gates=proposal?['full_criterion_evidence_review_and_scope_confirmation','explicit_owner_acceptance']:pureCalculation.has(r.id)?['fresh_exact_source_domain_verification','explicit_owner_acceptance']:(blocking[r.bundle]??['criterion_specific_direct_evidence','explicit_owner_acceptance']);
  return { id:r.id,bundle:r.bundle,specification:r.specification,specificationLine:r.specificationLine,statement:r.statement,
    fullCriterionStatement:fullStatement(r), fullStatement:fullStatement(r), sourceMatrixOwnerAccepted:r.ownerAccepted, ownerAccepted:false,
    wholeCriterionReadyForOwnerReview:false, proposedGovernanceReview:!!proposal,
    reviewReadiness:proposal?'proposed_bounded_governance_owner_review':'full_acceptance_blocked',
    decisionScope:proposal?.scope??'Full criterion remains open; review available source/fixture evidence without closing acceptance.',
    rationale:proposal?.reason??r.remaining,
    unresolvedObligations:proposal?.obligations??r.remaining,
    blockingGates:gates,
    evidence:(proposal?.evidence??[nativePath,reviewPath,livePath,...r.evidence.filter(p=>p.endsWith('process-foundation-20260930.json'))]).map(binding),
    historicalDomainBoundary: pureCalculation.has(r.id)?'Historical deterministic checks exist; no fresh domain test is claimed by this packet. A fresh focused exact-source check can support a separate calculation decision without proving an adapter, native behavior, or source certification.':null,
    ownerDecision:null };
});
if(rows.length!==109||new Set(rows.map(r=>r.id)).size!==109) throw new Error('Requirement identity drift');
const acceptancePacket={observedAt,gitHead:head,concurrentStatusAtRead:status,
  boundary:'Read-only readiness proposal. A request to obtain acceptance is not an owner decision; no criterion, matrix or acceptance store is changed.',
  sourceMatrix:binding(matrixPath),inputBindings,
  requirementCount:109,ownerAcceptedCriteria:0,wholeWaveComplete:false,
  wholeCriterionReadyForOwnerReviewCount:0,
  proposedBoundedGovernanceReviewCount:rows.filter(r=>reviewReasons[r.id]).length,
  fullAcceptanceBlockedCount:109,
  proposedOwnerReviewIds:Object.keys(reviewReasons),
  runtimeReview:{...binding(reviewPath),bundleSha256:review.bundleSha256,ownerApproved:false,originalBundleSha256:'13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e'},
  liveObservation:{observedAt:live.observedAt,migrations:live.migrationCount,apiFunctions:live.apiFunctions,checkedProviders:live.checkedProviders,unchangedProviders:live.unchangedProviders,readOnly:true},
  currentEvidence:{sourceFilesPerApp:native.sourceFilesPerApp,releaseEntriesVerified:native.releaseEntriesVerified,goldenFailures:native.goldenFailures.length,approvedGoldensRegenerated:false,nativeLaunched:native.nativeLaunched,authenticatedNative:native.authenticatedNative,nativeKeyboardVerified:false,realMfa:false,actualModelUsage:false,actualWorkerDelivery:false,independentSessionContention:false,targetScaleLoad:false,ownerAccepted:false},
  reviewOrder:['Review the two payroll image decisions and the combined exact 83-case visual packet; any resulting baseline change requires strict rerun.',
    'Consider only the nine named bounded governance/ownership decisions with their complete statements and explicit scopes. Record each actual owner decision before changing matrix flags.',
    'Refresh and decide the exact runtime bundle separately; hosting selection and a privately created trial login do not approve provisioning.',
    'After required approval, collect installed providers, genuine MFA, authenticated native, actual exports/model/worker delivery, independent contention and target-scale evidence, then present remaining criteria.'],
  rows};

const outputs=new Map();
outputs.set(`${out}/payroll-visual-review-20261010.json`,JSON.stringify(payrollPacket,null,2)+'\n');
outputs.set(`${out}/owner-acceptance-readiness-20261010.json`,JSON.stringify(acceptancePacket,null,2)+'\n');
const abs = p => path.resolve(root,p).replaceAll('\\','/');
const link = (label,p,line) => `[${label}](<${abs(p)}${line?`:${line}`:''}>)`;
const image=(label,p)=>`![${label}](${abs(p)})`;
let md='# Payroll exact-image review — October 10, 2026\n\n';
md+='The two failures are intentional Wave 4 toolbar content changes: “Linked corrections” appears before Reload. Preserve that feature and its capability gate. Owner visual decisions are absent; both approved PNGs remain unchanged.\n\n';
md+=`HEAD: \`${head}\`. Measurements use retained r13 images; no new Flutter or native test was run. The fixture is 1440 × 1100 at 200% text.\n\n`;
for(const c of cases){
  md+=`## ${c.stem}\n\n${c.differentPixels.toLocaleString('en-US')} pixels differ (${c.differentPercent.toFixed(6)}%); bounding box [${c.bbox.join(', ')}]. No dimension or alpha change.\n\n`;
  md+=`Approved SHA-256: \`${c.approved.sha256}\`\n\nCandidate SHA-256: \`${c.currentCandidate.sha256}\`\n\n`;
  md+=`${image('Approved payroll',c.approved.path)}\n\n${image('Candidate payroll',c.currentCandidate.path)}\n\n${image('Isolated pixel difference',c.isolatedDiff.path)}\n\n`;
  md+=`Proposed decision: retain the Linked corrections action and, only after explicit approval of these candidate bytes, update ${link('this one approved PNG',c.approved.path)}. The unchanged strict comparison must pass afterward.\n\n`;
}
md+='## Permission and source rationale\n\n';
for(const t of traces) md+=`- ${link(t.path,t.path,t.line)}: ${t.purpose}\n`;
md+='\nThe view action opens a separately gated workspace. It does not grant preparation, approval, posting or replay authority. Current server SQL is candidate evidence; a toolbar render does not prove dialog loading, installed authorization, genuine MFA or native keyboard use.\n\n';
md+=`Exact measurements, input/source hashes and the pending decisions are in ${link('the JSON record',`${out}/payroll-visual-review-20261010.json`)}. Image decisions are independent from runtime approval and requirement acceptance.\n`;
outputs.set(`${out}/payroll-visual-review-20261010.md`,md);

let amd='# Owner acceptance readiness — October 10, 2026\n\n';
amd+='All 109 criteria remain unaccepted and are conservatively marked not ready for a whole-criterion acceptance decision by this initial packet. Nine bounded governance/ownership reviews are proposed as non-counting checkpoint reviews. It records no owner approval and changes neither the matrix nor an acceptance store. Each complete criterion statement, evidence hash, scope and unresolved obligation is retained in the companion JSON.\n\n';
amd+=`The source matrix SHA-256 is \`${acceptancePacket.sourceMatrix.sha256}\`. The exact additional runtime bundle is \`${review.bundleSha256}\` and remains unapproved. The original bundle \`13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e\` remains preserved.\n\n`;
amd+='## Proposed owner decisions now\n\n';
amd+='These are individual, non-counting checkpoint reviews. A partial checkpoint approval must never set a whole criterion ownerAccepted flag. A governance decision does not waive any unfinished product criterion, future ownership refresh, installed behavior or runtime approval. The first W5-01 attribution records are historical evidence of that first step, rather than current test results. Full-criterion eligibility must be separately justified against the complete wording before requesting an acceptance decision.\n\n';
amd+='| Criterion | Full statement | Review scope and evidence | Continuing obligation |\n|---|---|---|---|\n';
for(const r of rows.filter(r=>reviewReasons[r.id])){
  amd+=`| ${r.id} | ${r.fullCriterionStatement.replaceAll('|','\\|')} | ${r.decisionScope} ${r.evidence.map(e=>link(path.basename(e.path),e.path)).join(', ')} | ${r.unresolvedObligations} |\n`;
}
amd+='\n## Remaining 100 criteria\n\nThe rows below preserve every remaining ID and full statement. Gates are evidence work, not requests to infer approval from passing fixtures. Pure calculation rows can be reviewed after a fresh focused exact-source run; that run cannot establish adapter permissions, certified source semantics, native behavior or load.\n\n';
amd+='| Criterion | Full statement | Evidence still required |\n|---|---|---|\n';
for(const r of rows.filter(r=>!reviewReasons[r.id])) amd+=`| ${r.id} | ${r.fullCriterionStatement.replaceAll('|','\\|')} | ${r.blockingGates.join('; ').replaceAll('_',' ')}. ${r.unresolvedObligations} |\n`;
amd+='\n## Current evidence boundaries\n\n';
amd+=`The connected observation at ${live.observedAt} records ${live.migrationCount} migrations, ${live.apiFunctions} API functions and ${live.unchangedProviders}/${live.checkedProviders} unchanged fingerprints. The six approved Wave 5 migrations remain installed; the additional 71 and runtime bootstrap are uninstalled.\n\n`;
amd+='r13 has scoped analysis, full platform verification and ordinary Preview/Connected release packages, with the same 83 strict golden failures. Controlled worker deadline tests are source evidence. Current authenticated native, genuine MFA, native keyboard, actual model/worker/export delivery, independent contention, target-scale load and owner signoff remain unverified. Production and real billing remain excluded.\n\n';
amd+=`${link('Exact 109-row readiness record',`${out}/owner-acceptance-readiness-20261010.json`)} · ${link('Current native report',nativePath)} · ${link('Current runtime review',reviewPath)} · ${link('Two payroll visual decisions',`${out}/payroll-visual-review-20261010.md`)}\n`;
outputs.set(`${out}/owner-acceptance-readiness-20261010.md`,amd);

// Fail before publication if any bound input/source/image moved concurrently.
for(const b of [...inputBindings,...traces,...cases.flatMap(c=>[c.approved,c.currentCandidate,c.master,c.isolatedDiff])]) if(hash(b.path)!==b.sha256) throw new Error(`Concurrent drift ${b.path}`);
for(const p of outputs.keys()) if(fs.existsSync(path.resolve(root,p))) throw new Error(`Refusing to overwrite existing packet: ${p}`);
for(const [p,content] of outputs) fs.writeFileSync(path.resolve(root,p),content,{flag:'wx'});
console.log(JSON.stringify({created:[...outputs.keys()],payrollCases:cases.length,proposedOwnerReviewIds:acceptancePacket.proposedOwnerReviewIds,blocked:acceptancePacket.fullAcceptanceBlockedCount,ownerAccepted:0,matrixUnchanged:hash(matrixPath)===acceptancePacket.sourceMatrix.sha256},null,2));
