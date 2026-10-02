import fs from 'node:fs';
import crypto from 'node:crypto';
const root='docs/verification/remaining-wave3/';
const prior=JSON.parse(fs.readFileSync(root+'requirement-matrix-20260928.json','utf8'));
const hash=crypto.createHash('sha256').update(fs.readFileSync(prior.spec)).digest('hex');
if(hash!==prior.spec_sha256 || prior.requirements.length!==181) throw Error('Approved specification changed');
const e={foundation:root+'baseline-operational_foundation-20260930.json',crm:root+'baseline-crm_pipeline-20260930.json',
 quotation:root+'baseline-quotation_workspace-20260930.json',order:root+'baseline-order_workspace-20260930.json',
 procurement:root+'observability-final-procurement-20260930.json',inventory:root+'observability-final-inventory-20260930.json',receivables:root+'observability-final-receivables-20260930.json',
 desktop:'build/remaining-wave3/desktop-report-full-final-20260930.log',recovery:'build/remaining-wave3/read-access-desktop-20260930.log',visual:'build/remaining-wave3/workspaces-visual-final2-20260930.log',
 diagnostics:'build/remaining-wave3/platform-report-full-final-20260930.log',queue:'build/remaining-wave3/queue-visual-final-20260930.log',
 readAdapters:'build/remaining-wave3/read-access-platform-20260930.log',reportEdges:'build/remaining-wave3/read-report-edges-final2-20260930.log',
 reportVisual:'build/remaining-wave3/report-progress-visual-20260930.log',forms:'build/remaining-wave3/procurement-interaction-20260930.log',
 goldenControl:root+'golden-control-comparison-20260930.json'};
const source={
 312:['wave3_operational_evidence','wave3_notification'],318:['wave3_dashboard_metrics'],334:['wave3_historical_controls_receivables','wave3_operational_evidence'],
 349:['wave3_control_procurement','wave3_operational_evidence'],354:['wave3_stock_disposition'],355:['wave3_stock_disposition','wave3_tracked_counts','wave3_receipt_provenance'],
 358:['wave3_count_partitions'],359:['wave3_landed_extensions'],361:['wave3_reservation_maintenance'],366:['wave3_posted_journal'],368:['wave3_historical_controls_receivables','wave3_control_procurement'],
 377:['wave3_operational_evidence'],382:['wave3_operational_evidence','wave3_report_exports'],389:['wave3_operational_evidence'],390:['wave3_dashboard_metrics'],
 391:['wave3_operational_evidence'],392:['wave3_notification'],394:['wave3_operational_evidence','wave3_report_exports']};
const missing={
 'FR-312':'Installed private Storage upload/read and native file dialogs remain unverified.',
 'FR-334':'Authenticated source/allocation/credit/receipt navigation needs native review.',
 'FR-349':'Authenticated bill/credit/allocation/payment navigation needs native review.',
 'FR-360':'Target-scale dated lot/transit valuation and reconciliation plans remain unverified.',
 'FR-384':'Complete loading/error/empty/timeline/accessibility review for every workspace remains open.',
 'FR-385':'Full native keyboard/focus/validation walkthrough and approved golden regression remain open.',
 'FR-391':'Private file bytes and native file dialogs have not been exercised against installed candidates.',
 'FR-392':'Nine event classes and bounded due scan pass synthetic checks; installed scheduling and authenticated recipients remain unverified.',
 'FR-395':'Contracts 54–56 correct confirmed report confirmation/access and root-selector gaps; focused exact recovery/access checks pass. Complete native restart, storage exhaustion and every module failure state remain unverified.',
 'AC-321':'Complete workspace accessibility and approved golden regression remain open.',
 'AC-322':'Native encrypted-store restart and complete cross-module recovery acceptance remain open.',
 'AC-323':'Target-scale lists/reports and approved golden failures remain open.',
 'AC-324':'Installed authenticated private Storage, notifications and contextual links need acceptance.',
 'AC-325':'Target-scale p95/plans, independent sessions and full observability review remain open.',
 'AC-326':'Release gate is open: approved goldens, coverage, real scale/contention, installation/native checks and owner signoff.',
 'EC-310':'Synthetic locked cases pass; independent credit-exposure race remains unverified.',
 'EC-311':'Synthetic locked cases pass; independent final-stock reservation race remains unverified.',
 'EC-319':'Synthetic settled/foreign/locked cases pass; independent selection contention remains unverified.',
 'EC-330':'Closed-period rejection and rollback pass; two-session close/post race remains unverified.',
 'EC-334':'Synthetic match conflict passes; independent-session matching remains unverified.',
 'EC-340':'Synthetic storage-failure checks exist; installed disk-full/process-restart checks remain open.',
 'NFR-307':'Target-scale ordinary-read p95 under 500 ms has not been measured.',
 'NFR-308':'Target-scale save/transition p95 under 1.5 s and posting p95 under 3 s have not been measured.',
 'NFR-309':'500 tenants, 10 entities per tenant, 25 warehouses per entity, 100k products per large tenant, 10m movements and 20m journal lines have not been exercised.',
 'NFR-310':'Three warm synthetic control plans exist; target-scale queue/aging/stock/bank/report plans remain open.',
 'NFR-312':'Single-session lock/rollback checks do not prove independent authenticated concurrency.',
 'NFR-313':'AES-GCM synthetic recovery passes; Credential Manager/process-restart acceptance is outside this prompt.',
 'NFR-314':'Full WCAG/keyboard/screen-reader/reduced-motion acceptance remains open.',
 'NFR-315':'Current synthetic workspace/report/diagnostic renders pass at required sizes and 200%. Unchanged HEAD reproduces all 81 failed golden cases with 83 identical images; latest fixture comparison and complete native visual acceptance remain open.',
 'NFR-316':'Redacted scoped HTTP latency/outcomes, reconciliation/close counts and bounded dead-letter depth pass synthetic platform/database and rendered status checks. Installed/native observability remains unverified.',
 'NFR-317':'Reviewed 25-file pure Dart rule scope has 642/677 branches (94.83%); SQL assertions are separate. The changed-file line gate was 64.89% before contracts 55–56 and remains below the required 80%; fresh full coverage is running.',
 'NFR-318':'Fresh synthetic security/exactness/rollback/history checks pass; genuine contention remains open.',
 'NFR-319':'Report-recovery isolated compilation succeeded in 157.4 seconds with later source drift recorded; current read-access isolated compilation is running. Cold launch and native critical-path QA remain approval-owned.',
 'NFR-320':'Progress/presentation cancellation and durable original-request confirmation pass synthetic edge and 200% render checks under contract 54. Target-scale ordinary p95 under 2 s and complex p95 at most 10 s remain unverified.'};
function suites(r){const n=+r.id.split('-')[1];if(!r.id.startsWith('FR-'))return [e.foundation,e.procurement,e.inventory,e.receivables];
 if(n<=312)return [e.foundation,e.procurement];if(n<=318)return [e.crm,e.procurement];if(n<=321)return [e.quotation];if(n<=325)return [e.order,e.receivables];
 if(n<=334)return [e.receivables,e.procurement];if(n<=349)return [e.procurement];if(n<=361)return [e.inventory,e.procurement,e.receivables];if(n<=382)return [e.procurement,e.receivables];return [e.desktop,e.recovery,e.visual];}
const rows=prior.requirements.map(r=>({id:r.id,approved_behavior:r.statement,implementation:'code_or_contract_evidence_present',missing_implementation:null,
 source_evidence:[...new Set([r.source_evidence.split(' (')[0],...(r.id.startsWith('FR-')?source[+r.id.slice(3)]??[]:[]).map(s=>'supabase/tests/'+s+'_test.sql')])].filter(p=>fs.existsSync(p)),
 verification_evidence:suites(r),missing_verification:missing[r.id]??'Fresh synthetic evidence covers the referenced scenarios; installed authenticated workflow and owner acceptance remain open.',
 external_acceptance:'45 candidates remain unapplied. Concrete development installation, isolated contention/load environment, native checks and owner signoff require separate approval.'}));
for(const r of rows) {
 if(['FR-334','FR-349','FR-384','FR-385','FR-395','AC-322','NFR-313'].includes(r.id)) {
  r.source_evidence.push('docs/blueprint/55_WAVE3_RECEIVABLE_READ_ACCESS_CONTRACT.md','docs/blueprint/56_WAVE3_PROCUREMENT_REFERENCE_ACCESS_CONTRACT.md');
  r.verification_evidence.push(e.recovery,e.readAdapters,e.forms);
 }
 if(['FR-395','AC-320','AC-322','NFR-320'].includes(r.id)) {
  r.source_evidence.push('docs/blueprint/54_WAVE3_REPORT_RECOVERY_AND_CANCELLATION_CONTRACT.md');
  r.verification_evidence.push(e.reportEdges,e.reportVisual);
 }
 if(['FR-385','AC-321','AC-323','AC-326','NFR-314','NFR-315'].includes(r.id))r.verification_evidence.push(e.goldenControl);
 if(['FR-319','FR-320','FR-385'].includes(r.id))r.source_evidence.push('docs/blueprint/52_WAVE3_COMMERCIAL_CLIENT_VALIDATION_CONTRACT.md');
 if(r.id==='NFR-316') {
  r.source_evidence.push('docs/blueprint/53_WAVE3_OBSERVABILITY_CONTRACT.md','packages/jentra_platform/lib/src/wave3_observability.dart','supabase/migrations/20260930005000_wave3_observability.sql');
  r.verification_evidence.push(e.diagnostics,e.queue);
 }
}
for(const r of rows)for(const p of [...r.source_evidence,...r.verification_evidence])if(!fs.existsSync(p))throw Error('Missing evidence '+p);
const out={generated_on:'2026-09-30',spec:prior.spec,spec_sha256:hash,head:'f9cc342815e2446fb3f26204d5e65e03c1b2a140',
 counts:Object.fromEntries(['FR','AC','EC','NFR'].map(k=>[k,rows.filter(r=>r.id.startsWith(k+'-')).length])),
 boundary:'Evidence presence is not exhaustive implementation or acceptance proof. Missing verification is separate from a confirmed code gap. Historical Sep 28/29 matrices are preserved.',
 stale_status_corrections:['FR-325 adds no automatic expiry/retirement scheduler; FR-361 is supported by permitted bounded maintenance.',
 'FR-355 requires preserved serial history, supplied by immutable serial-linked movement lines; no invented new history workspace.',
 'FR-381 requires tax-treatment classification and statutory-review notice, not a supplier withholding engine or certified statutory rules.',
 'Landed corrections, count partitions, disposition, dashboards, governed reports/exports, attachments/links and nine notification classes are now present in candidate source.'],requirements:rows};
fs.writeFileSync(root+'requirement-matrix-20260930.json',JSON.stringify(out,null,2)+'\n');
const link=p=>`[${p.split('/').at(-1)}](../../../${p})`;
fs.writeFileSync(root+'requirement-matrix-20260930.md',['# Approved Wave 3 requirement-to-evidence matrix — 2026-09-30','',
 'All 181 approved IDs and full wording are preserved. Code/contract presence is not exhaustive verification. Synthetic candidates are rolled back. Required development verification and external acceptance remain open; Wave 3 is not fully complete.','',
 '| ID | Approved behavior | Implementation evidence | Current verification | Missing implementation | Missing verification | External gate |','|---|---|---|---|---|---|---|',
 ...rows.map(r=>`| ${r.id} | ${r.approved_behavior.split('**Covers:**')[0].replaceAll('|','/')} | ${r.source_evidence.map(link).join(', ')} | ${r.verification_evidence.map(link).join(', ')} | No specific code gap confirmed at this checkpoint; further review may identify one | ${r.missing_verification} | Installation/native/owner gates open |`),'',
 'JSON preserves the full approved wording, specification hash, evidence boundaries and stale-status corrections.',''].join('\n'));
console.log(JSON.stringify({total:rows.length,counts:out.counts,spec_sha256:hash}));
