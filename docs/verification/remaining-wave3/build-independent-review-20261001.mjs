import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';

const base='docs/verification/remaining-wave3/';
const prior=JSON.parse(fs.readFileSync(base+'requirement-matrix-20261001.json','utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const specText=fs.readFileSync(prior.spec,'utf8');
if(hash(prior.spec)!==prior.spec_sha256)throw Error('Approved specification changed');
const approved=[...specText.matchAll(/^(?:- |### )((?:FR|AC|EC|NFR)-\d{3}):/gm)].map(x=>x[1]);
const ids=prior.requirements.map(r=>r.id);
if(ids.length!==181||new Set(ids).size!==181||approved.length!==181||approved.some(id=>!ids.includes(id)))throw Error('Requirement coverage changed');
const migration=name=>'supabase/migrations/'+name+'.sql';
const feature=(area,name)=>`apps/jentra_desktop/lib/src/features/${area}/${name}_controller.dart`;
const groups={
  shared:{files:[migration('20260904121647_wave3_operational_foundation')], finding:'Scoped authenticated command hash/replay, optimistic versions, receipt/audit/telemetry/outbox and immutable event boundary are present; direct private mutation remains denied.'},
  crm:{files:[migration('20260904130000_create_wave3_crm_pipeline_commands'),feature('crm','crm')],finding:'Lead/activity/opportunity workflow and conversion/pipeline source is present; conversion and dated exact values have synthetic tests.'},
  quotation:{files:[migration('20260905050428_create_wave3_quotation_commands'),feature('sales','quotation')],finding:'Versioned exact quotation/editor/workflow and expired revision behavior are present.'},
  order:{files:[migration('20260905050444_create_wave3_order_credit_reservation_commands'),feature('sales','sales_order')],finding:'Traced order conversion, locked credit decision and bounded reservations are present; real competing sessions remain open.'},
  ar:{files:[migration('20260910135010_complete_delivery_receivables'),feature('receivables','receivables')],finding:'Delivery/invoice/receipt/return and immutable AR allocation/source statements are present; current read denial/epoch corrections are synthetic client evidence.'},
  requisition:{files:[migration('20260913003000_procurement_sourcing'),feature('procurement','procurement'),feature('procurement','sourcing')],finding:'Versioned requisition/workflow, RFQ, supplier responses and selection rationale are present.'},
  po:{files:[migration('20260913004000_procurement_purchase_orders'),migration('20260913005000_procurement_order_workflow'),feature('procurement','purchase_order')],finding:'Sourced purchase-order revisions and configured material-change approval are present.'},
  receipt:{files:[migration('20260913006000_procurement_goods_receipts'),feature('procurement','goods_receipt')],finding:'Accepted/rejected and partial tracked receipts, exact accrued value, tolerance and reversal paths are present.'},
  bill:{files:[migration('20260913007000_procurement_supplier_bills'),feature('procurement','supplier_bill')],finding:'Supplier bill uniqueness, three-way exceptions, approvals and AP posting are present.'},
  settlement:{files:[migration('20260914001000_procurement_supplier_settlement'),migration('20260915002000_procurement_purchase_returns'),feature('procurement','supplier_payment'),feature('procurement','purchase_return')],finding:'Payment proposals/claims, exact payment/allocation/return and dated supplier statements are present; no external funds execution is implied.'},
  units:{files:[feature('procurement','product_unit'),'packages/jentra_domain/lib/src/inventory_transfer.dart',migration('20260910135010_complete_delivery_receivables')],finding:'Exact rational units and immutable tracked stock are present. Negative-stock OFF checks are present; enabled policy EC-323 is missing.'},
  inventory:{files:[migration('20260930001000_wave3_landed_extensions'),migration('20260930002000_wave3_count_partitions'),migration('20260930003000_wave3_stock_disposition'),migration('20260927200706_wave3_inventory_extensions'),feature('inventory_transfer','inventory_transfer'),feature('stock_count','stock_count'),feature('disposition','disposition')],finding:'Pooled valuation, transfer conservation, cutoff partitions, reasoned landed/disposition corrections and bounded reservation maintenance are present; receipt quantity provenance is not costing provenance.'},
  journal:{files:[migration('20260921041348_manual_journals'),migration('20260928001000_wave3_posted_journal_evidence'),feature('manual_journal','manual_journal')],finding:'Exact immutable automatic/manual journal and contextual source-line evidence are present; original labels/dimensions and access are preserved.'},
  control:{files:[migration('20260922001000_ar_ap_control_reconciliation'),migration('20260927200703_wave3_historical_controls'),feature('control_reconciliation','control_reconciliation')],finding:'Original source controls, dated immutable residuals, linked allocation reversals and supported retired mapping registry are present; undocumented history remains explicit.'},
  bank:{files:[migration('20260923225202_bank_reconciliation'),feature('bank_reconciliation','bank_reconciliation')],finding:'Scoped operational accounts, bounded exact CSV/XLSX preview/import and locked reversible matches are present; native import and true competing matches remain unverified.'},
  period:{files:[migration('20260924185321_wave3_period_governance'),feature('period_fx','period_fx')],finding:'Persisted-rate FX, locked close checks and reasoned approval/MFA reopen are present; actual independent close races and native MFA are external gates.'},
  statements:{files:[migration('20260925002000_wave3_financial_statements'),migration('20260925003000_wave3_cash_flow'),migration('20260926008000_wave3_close_control_review'),feature('financial_statements','financial_statement'),feature('close_review','close_review')],finding:'Posted comparative financial statements, mapped indirect cash flow and exact multi-component frozen close/control evidence are present.'},
  budget:{files:[migration('20260925004000_wave3_budgets'),migration('20260926010000_wave3_financial_dimensions'),migration('20260926001000_wave3_tax_summary'),feature('budgets','budget')],finding:'Versioned exact governed budgets/dimensions, posted actuals and tax classifications/review notice are present; no inferred historical dimensions or certified statutory rules.'},
  desktop:{files:['apps/jentra_desktop/lib/src/router.dart',feature('operations','operational'),'apps/jentra_desktop/lib/src/features/operations/operational_screen.dart',migration('20260927200629_wave3_operational_evidence'),migration('20260930004000_wave3_dashboard_metrics'),migration('20260929001000_wave3_notifications'),migration('20260926009000_wave3_governed_report_exports')],finding:'Capability routes, bounded current/dated reports, dashboard metrics, governed exports, context restoration, files and configured notifications/due scan are present. Confirmed attachment read epoch/Storage errors are addressed in this review, with separate synthetic checks.'},
  verification:{files:['supabase/tests/build_remaining_wave3_candidate.ps1','supabase/tests/wave3_representative_read_plans_test.sql',base+'migration-review-and-runbook-20260930.md'],finding:'Strict rollback builders and concrete compatibility/install/restore/native procedures exist. Source/test preparation does not satisfy load, concurrent-session or native release gates.'},
};
const frGroups=[[301,312,'shared'],[313,318,'crm'],[319,321,'quotation'],[322,325,'order'],[326,334,'ar'],[335,337,'requisition'],[338,339,'po'],[340,341,'receipt'],[342,345,'bill'],[346,349,'settlement'],[350,355,'units'],[356,361,'inventory'],[362,366,'journal'],[367,368,'control'],[369,371,'bank'],[372,374,'period'],[375,378,'statements'],[379,382,'budget'],[383,395,'desktop']];
const acGroups=['shared','crm','quotation','order','ar','ar','ar','ar','requisition','receipt','bill','settlement','units','inventory','inventory','journal','control','bank','period','statements','desktop','desktop','desktop','desktop','verification','verification'];
const ecGroups=['shared','shared','desktop','shared','shared','shared','shared','shared','quotation','order','order','ar','ar','control','control','ar','bill','bill','settlement','units','units','inventory','units','inventory','inventory','inventory','inventory','journal','control','period','shared','bank','bank','bank','bank','period','period','statements','desktop','desktop'];
const nfrGroups=['shared','units','shared','shared','shared','shared','verification','verification','verification','verification','verification','verification','desktop','desktop','desktop','verification','verification','verification','verification','verification'];
const specific={
 'FR-353':{implementation:'partially_implemented_required_policy_gap',missing_implementation:'Negative-stock OFF behavior exists; a versioned authorized override and later receipt valuation/correction path are absent (EC-323).',missing_verification:'No enabled-policy interim-cost/later-receipt cases exist; owner policy decision precedes implementation and verification.'},
 'EC-323':{implementation:'required_development_missing',missing_implementation:'Versioned negative-stock policy, audited permitted interim issue, separate immutable deficit evidence and later-receipt exact linked variance correction are absent.',missing_verification:'No policy-enabled code to verify. Last-valid-positive-pool basis/cover-order/variance classification proposal needs an owner policy decision; this is not installation-only.'},
 'NFR-301':{missing_verification:'Late outbox/injected failure and no-partial-effect cases exist, but assertion totals alone do not prove every possible failure stage/side effect. Independent sessions and installed transaction/grant behavior remain open.'},
 'NFR-307':{missing_verification:'No target-scale ordinary-read p95 <500 ms evidence. Synthetic timings and offline workload self-tests cannot meet this gate.'},
 'NFR-308':{missing_verification:'No target-scale save/transition p95 <1.5s or posting p95 <3s samples; each mutation sample must use a fresh command.'},
 'NFR-309':{missing_verification:'500 tenants, >=10 entities each, >=25 warehouses per entity, 100k products per large tenant, 10m stock movements and 20m journal lines are not installed or measured. Count/harness preparation is separate.'},
 'NFR-310':{missing_verification:'Small-fixture representative plans exist. Reservation fixture has zero rows; two private bank plans are privileged; nested RPC, populated high-volume and target-scale no-cross-tenant plans remain open.'},
 'NFR-312':{missing_verification:'Source lock ordering/unique constraints and offline independent-session harness checks exist, but no genuine independently authenticated sessions/overlap evidence was executed.'},
 'NFR-313':{missing_verification:'Synthetic encrypted input-only recovery and exact retry cases exist. Native Credential Manager, cold process restart, permission revocation and disk exhaustion remain unverified.'},
 'NFR-314':{missing_verification:'Rendered/semantic and selected keyboard cases exist; complete every-workspace WCAG/keyboard/screen-reader/reduced-motion acceptance remains open.'},
 'NFR-315':{missing_verification:'Selected current rendering matrices exist, but81approved-golden failures persist and cause is unproven. Complete all states/required viewport/theme/density/200% native visual QA is not established.'},
 'NFR-317':{missing_verification:'94.83% reviewed pure-domain branch scope passed. Historical changed-overall72.41% remains below80%; subsequent sources/tests require fresh hashes and merged coverage. SQL assertions do not measure branch coverage.'},
 'NFR-318':{missing_verification:'Strict synthetic candidate tests cover named invariants; real concurrent sessions and installed grants/history/atomic behavior are not established. Assertions overlap across stacks.'},
 'NFR-319':{missing_verification:'Isolated release compilations exist but current source changed afterward; latest landed copy marks current_source_match=false. No native executable was launched; cold launch and critical native paths remain approval-owned.'},
 'NFR-320':{missing_verification:'No target-scale ordinary report p95<2s or bounded complex report<=10s measurement. Client progress/cancellation does not establish installed/native timing.'},
 'AC-325':{missing_verification:'Target-scale dataset/plans, genuine independently authenticated critical races and documented p95 samples remain unexecuted; prepared harnesses do not prove outcomes.'},
 'AC-326':{missing_verification:'Required negative-policy development, overallcoverage, golden/security/native/load/owner gates remain open. Complete release cannot be inferred from candidate/tests/build counts.'},
};
const requirements=prior.requirements.map(r=>{
 const [kind,num]=r.id.split('-');const n=Number(num);
 const group=kind==='FR'?frGroups.find(([a,b])=>n>=a&&n<=b)?.[2]:kind==='AC'?acGroups[n-301]:kind==='EC'?ecGroups[n-301]:nfrGroups[n-301];
 if(!group||!groups[group])throw Error('Unreviewed ID '+r.id);
 const g=groups[group];
 return {...r,review_group:group,implementation:'reviewed_candidate_source_present',missing_implementation:null,
   source_evidence:[...new Set([...r.source_evidence,...g.files])],review_finding:g.finding,
   verification_boundary:'Named synthetic evidence belongs to its recorded source/query revision; it does not prove every approved sub-scenario, installed state or native acceptance.',
   missing_verification:'Additional complete installed/native role, recovery, keyboard/visual and target-scale session checks remain open. Current development evidence must be hashed after final source changes.',
   external_acceptance:'Specific isolated installation/resource/fixtures/authenticated-session/native-profile approval, eight compatibility decisions and owner signoff remain open.',
   ...specific[r.id]};
});
const files=[...new Set(requirements.flatMap(r=>[...r.source_evidence,...r.verification_evidence]))];
for(const p of files)if(!fs.existsSync(p))throw Error('Missing evidence '+p);
const knownLogs=['operational-attachment-red-20261001.log','operational-attachment-first-20261001.log','operational-attachment-platform-red-20261001.log','operational-attachment-platform-final-20261001.log','operational-attachment-final-20261001.log'];
const corrections=knownLogs.map(n=>'build/remaining-wave3/'+n).filter(p=>fs.existsSync(p)).map(p=>({file:p,sha256:hash(p),tail:fs.readFileSync(p,'utf8').trim().split(/\r?\n/).slice(-2)}));
const out={generated_at:new Date().toISOString(),head:execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),spec:prior.spec,spec_sha256:prior.spec_sha256,
 counts:prior.counts,reviewer:'independent requirements review agent',boundary:'181approved IDs retained. Candidate source review and synthetic evidence do not satisfy installation/native/load/owner acceptance. Required negative-policy development is explicitly open; concurrent corrections remain source-sensitive.',
 read_contracts:[33,43,44,46,47,48,49,50,51,52,53,54,55,56],requirements,
 confirmed_missing_development:['FR-353/EC-323 versioned negative-stock policy interim/later-receipt correction path'],
 corrected_development:['Private attachment root-dialog epoch and stale controller binding; real Storage denied/unknown/malformed read normalization under contract49 (see executed logs).'],
 correction_evidence:corrections,source_sha256:Object.fromEntries(files.map(p=>[p,hash(p)])),
 policy_proposal:base+'independent-requirements-review-20261001.md',
 policy_decision:'Owner must select last-valid-positive-pool interim basis, deficit-cover order, variance classification/account and zero-value basis admissibility. Approved spec does not fix these accounting choices.'};
fs.writeFileSync(base+'independent-requirements-review-20261001.json',JSON.stringify(out,null,2)+'\n');
console.log(JSON.stringify({requirements:requirements.length,counts:out.counts,confirmed_missing_development:out.confirmed_missing_development,hashed_evidence:files.length,correction_logs:corrections.length}));
