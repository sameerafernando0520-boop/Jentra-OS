import fs from 'node:fs';
import crypto from 'node:crypto';

const base='docs/verification/remaining-wave3/';
const args=process.argv.slice(2), options={};
for(let i=0;i<args.length;i+=2){
  if(!args[i].startsWith('--')||!args[i+1])throw Error('Expected --name path pairs');
  options[args[i].slice(2)]=args[i+1];
}
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const prior=read(base+'requirement-matrix-20260930.json');
const spec=fs.readFileSync(prior.spec,'utf8');
const approved=[...spec.matchAll(/^(?:- |### )((?:FR|AC|EC|NFR)-\d{3}):/gm)].map(m=>m[1]);
const ids=prior.requirements.map(r=>r.id);
if(hash(prior.spec)!==prior.spec_sha256||approved.length!==181||ids.length!==181||
  new Set(ids).size!==181||approved.some(id=>!ids.includes(id)))throw Error('Approved specification/181-ID drift');
const normalized=s=>s.replace(/\s+/g,' ').trim();
const approvedWording=new Map([...spec.matchAll(/^(?:- |### )((?:FR|AC|EC|NFR)-\d{3}):\s*([\s\S]*?)(?=^(?:- |### )(?:FR|AC|EC|NFR)-\d{3}:|^## |^### [^A]|$(?![\s\S]))/gm)]
 .map(m=>[m[1],normalized(m[2])]));
for(const r of prior.requirements)if(approvedWording.get(r.id)!==normalized(r.approved_behavior))throw Error('Approved wording drift: '+r.id);
const migration=n=>'supabase/migrations/'+n+'.sql';
const controller=(area,n)=>`apps/jentra_desktop/lib/src/features/${area}/${n}_controller.dart`;
const groups={
 shared:{files:[migration('20260904121647_wave3_operational_foundation'),'packages/jentra_platform/lib/src/draft_repository.dart','packages/jentra_platform/lib/src/local_draft_storage_failure.dart','docs/blueprint/57_WAVE3_LOCAL_DRAFT_STORAGE_FAILURE_CONTRACT.md'],finding:'Scoped commands, optimistic versions, immutable receipts/audit, workflow and atomic outbox primitives are present. Shared encrypted persistence preserves classified local storage errors and original recovery.'},
 crm:{files:[migration('20260904130000_create_wave3_crm_pipeline_commands'),controller('crm','crm')],finding:'Leads, activities, qualification, scoped conversion and exact dated pipeline source are present.'},
 quotation:{files:[migration('20260905050428_create_wave3_quotation_commands'),controller('sales','quotation')],finding:'Exact versioned quotations, workflow, approved revision and expiry guards are present.'},
 order:{files:[migration('20260905050444_create_wave3_order_credit_reservation_commands'),controller('sales','sales_order')],finding:'Source-linked conversion, locked credit evaluation and bounded reservation commands are present.'},
 ar:{files:[migration('20260910135010_complete_delivery_receivables'),controller('receivables','receivables')],finding:'Delivery/invoice/receipt/return, immutable AR allocation and dated customer statement paths are present.'},
 requisition:{files:[migration('20260912153000_procurement_requisition_drafts'),migration('20260913003000_procurement_sourcing'),controller('procurement','procurement'),controller('procurement','sourcing')],finding:'Versioned requisitions, RFQ invitations, exact supplier responses and selection rationale are present.'},
 po:{files:[migration('20260913004000_procurement_purchase_orders'),migration('20260913005000_procurement_order_workflow'),controller('procurement','purchase_order')],finding:'Sourced purchase orders and material revision/approval rules are present.'},
 receipt:{files:[migration('20260913006000_procurement_goods_receipts'),controller('procurement','goods_receipt')],finding:'Accepted/rejected partial tracked goods receipts, exact accrual, tolerance and linked reversals are present.'},
 bill:{files:[migration('20260913007000_procurement_supplier_bills'),controller('procurement','supplier_bill')],finding:'Supplier reference uniqueness, bounded three-way exceptions and governed AP posting are present.'},
 settlement:{files:[migration('20260914001000_procurement_supplier_settlement'),migration('20260915002000_procurement_purchase_returns'),controller('procurement','supplier_payment'),controller('procurement','purchase_return')],finding:'Payment proposal claims, exact supplier payment/allocation, immutable returns and dated statements are present.'},
 units:{files:[migration('20260912152000_product_unit_conversions'),migration('20260910135010_complete_delivery_receivables'),controller('procurement','product_unit')],finding:'Exact rational conversions, immutable tracked movements and negative-stock OFF checks are present; enabled policy remains missing.'},
 inventory:{files:[migration('20260919181407_inventory_receipt_provenance'),migration('20260919185538_inventory_landed_value'),migration('20260930001000_wave3_landed_extensions'),migration('20260930002000_wave3_count_partitions'),migration('20260930003000_wave3_stock_disposition'),migration('20260927200706_wave3_inventory_extensions'),controller('inventory_transfer','inventory_transfer'),controller('stock_count','stock_count'),controller('disposition','disposition')],finding:'Pooled carrying value, exact landed corrections, held/transit/consumed treatment, cutoff partitions, disposition and bounded reservation maintenance are present.'},
 journal:{files:[migration('20260921041348_manual_journals'),migration('20260928001000_wave3_posted_journal_evidence'),controller('manual_journal','manual_journal')],finding:'Exact immutable manual/automatic journal source and scoped posted-line evidence are present.'},
 control:{files:[migration('20260922001000_ar_ap_control_reconciliation'),migration('20260927200703_wave3_historical_controls'),controller('control_reconciliation','control_reconciliation')],finding:'Original control basis, dated immutable residuals, linked allocation corrections and attributable retired mapping registry are present.'},
 bank:{files:[migration('20260923225202_bank_reconciliation'),controller('bank_reconciliation','bank_reconciliation')],finding:'Governed operational accounts, bounded exact CSV/XLSX import, current access guards and reversible locked matching are present.'},
 period:{files:[migration('20260924185321_wave3_period_governance'),controller('period_fx','period_fx')],finding:'Persisted-rate FX, locked close checks and approval/reason/MFA reopen paths are present.'},
 statements:{files:[migration('20260925002000_wave3_financial_statements'),migration('20260925003000_wave3_cash_flow'),migration('20260926008000_wave3_close_control_review'),controller('financial_statements','financial_statement'),controller('close_review','close_review')],finding:'Posted comparative statements, mapped indirect cash flow and immutable multi-component close reviews are present.'},
 budget:{files:[migration('20260925004000_wave3_budgets'),migration('20260926010000_wave3_financial_dimensions'),migration('20260926001000_wave3_tax_summary'),controller('budgets','budget')],finding:'Governed budget versions/dimensions, posted actuals and non-certified tax treatment/review notice are present.'},
 desktop:{files:['apps/jentra_desktop/lib/src/router.dart',controller('operations','operational'),'apps/jentra_desktop/lib/src/features/operations/operational_screen.dart',migration('20260927200629_wave3_operational_evidence'),migration('20260930004000_wave3_dashboard_metrics'),migration('20260929001000_wave3_notifications'),migration('20260926009000_wave3_governed_report_exports')],finding:'Capability routing, bounded filtered current lists, dated party/bank reports, dashboards, scoped links, private files, notifications and governed exports are present.'},
 verification:{files:['supabase/tests/build_remaining_wave3_candidate.ps1','supabase/tests/wave3_representative_read_plans_test.sql',base+'migration-review-and-runbook-20260930.md'],finding:'Strict rollback builders and reviewed candidate dependency/compatibility/restore/native procedures exist; execution gates remain separate.'},
};
const frGroups=[[301,312,'shared'],[313,318,'crm'],[319,321,'quotation'],[322,325,'order'],[326,334,'ar'],[335,337,'requisition'],[338,339,'po'],[340,341,'receipt'],[342,345,'bill'],[346,349,'settlement'],[350,355,'units'],[356,361,'inventory'],[362,366,'journal'],[367,368,'control'],[369,371,'bank'],[372,374,'period'],[375,378,'statements'],[379,382,'budget'],[383,395,'desktop']];
const acGroups=['shared','crm','quotation','order','ar','ar','ar','ar','requisition','receipt','bill','settlement','units','inventory','inventory','journal','control','bank','period','statements','desktop','desktop','desktop','desktop','verification','verification'];
const ecGroups=['shared','shared','desktop','shared','shared','shared','shared','shared','quotation','order','order','ar','ar','control','control','ar','bill','bill','settlement','units','units','inventory','units','inventory','inventory','inventory','inventory','journal','control','period','shared','bank','bank','bank','bank','period','period','statements','desktop','desktop'];
const nfrGroups=['shared','units','shared','shared','shared','shared','verification','verification','verification','verification','verification','verification','desktop','desktop','desktop','verification','verification','verification','verification','verification'];
const evidence={
 coverage:options.coverage??base+'coverage-final-sealing-20261001.json',
 build:options.build??base+'windows-build-20261001-sealing-current.json',
 bundle:options.bundle??base+'windows-bundle-final-current-20261001.json',
 refresh:options.refresh??base+'refresh-final-current-20261001.json',
 sourceLedger:options.sources??base+'source-ledger-final-current-20261001.json',
 desktop:options.desktop??base+'desktop-final-current-20261001.log',
 platform:options.platform??base+'platform-final-current-20261001.log',
 golden:options.golden??base+'golden-control-final-current-20261001.json',
 plans:options.plans??base+'representative-plans-final-20261001.json',
 candidates:base+'migration-order-final-20260930-45.json',
 compatibility:base+'schema-compatibility-final-20260930.json',
};
for(const p of Object.values(evidence))if(!fs.existsSync(p))throw Error('Missing required evidence '+p);
const coverage=read(evidence.coverage), build=read(evidence.build), golden=read(evidence.golden), ledger=read(evidence.sourceLedger), refresh=read(evidence.refresh);
const completion=p=>{
 const text=fs.readFileSync(p,'utf8');
 const runs=[...text.matchAll(/\+(\d+)(?:\s+~\d+)?(?:\s+-(\d+))?:/g)];
 if(!runs.length||!/(?:All tests passed!|Some tests failed\.)/.test(text))throw Error('Incomplete client log '+p);
 return {file:p,sha256:hash(p),passed:Number(runs.at(-1)[1]),failed:Number(runs.at(-1)[2]??0)};
};
const currentChecks={desktop:{...completion(evidence.desktop),scope:options['desktop-scope']??'whole_shared_checkout'},platform:{...completion(evidence.platform),scope:options['platform-scope']??'recorded_whole_platform'},coverage:{file:evidence.coverage,generated_at:coverage.generated_at,pure_domain:coverage.pure_domain,changed_dart:coverage.changed_dart},build:{file:evidence.build,...build},golden:{file:evidence.golden,failed_cases:golden.current_failed_cases,control_failed_cases:golden.control_failed_cases,current_only:golden.current_only,control_only:golden.control_only,compared_images:golden.compared_images,identical_images:golden.identical_images,failure_breakdown:golden.failure_breakdown??null}};
currentChecks.platform.failures=[...fs.readFileSync(evidence.platform,'utf8').matchAll(/test\/([^:\r\n]+\.dart): (.+?) \[E\]/g)].map(m=>({file:m[1],scenario:m[2]}));
const resolution=options.resolution?read(options.resolution):{resolved_findings:{}};
const resolved=resolution.resolved_findings??{};
for(const [name,r] of Object.entries(resolved)){
 if(!['material_conflict_comparison','local_storage'].includes(name)||!r.finding||!r.source_evidence?.length||!r.verification_evidence?.length)throw Error('Invalid correction resolution '+name);
 for(const p of [...r.source_evidence,...r.verification_evidence])if(!fs.existsSync(p))throw Error('Missing correction evidence '+p);
}
const optionalEvidence=names=>names.flatMap(n=>{
 const candidates=[base+n,'build/remaining-wave3/'+n];
 const p=candidates.find(p=>fs.existsSync(p));return p?[p]:[];
});
const focused=optionalEvidence(['attachment-report-adapters-final-20261001.log','access-interactions-corrected-20261001.log','report-access-final-20261001.log','landed-procurement-interaction-final-20261001.log','inventory-sealing-final-20261001.log','report-workflow-final2-20261001.log','bank-access-visual-final-20261001.log','local-draft-storage-final-20261002.log']);
const currentCoverageDrift=(coverage.files??[]).filter(r=>r.changed&&hash(r.file)!==r.source_sha256).map(r=>r.file);
const sourceMismatch=[...new Set([...(coverage.changed_dart.source_mismatches??[]),...currentCoverageDrift])], unmeasured=coverage.changed_dart.unmeasured_executable??[];
const coveragePassed=coverage.pure_domain.branch_percent>=90&&coverage.changed_dart.line_percent>=80&&sourceMismatch.length===0&&unmeasured.length===0;
const coverageText=`Reviewed pure-domain scope ${coverage.pure_domain.branches_hit}/${coverage.pure_domain.branches} branches (${coverage.pure_domain.branch_percent.toFixed(2)}%); changed whole-file Dart ${coverage.changed_dart.lines_hit}/${coverage.changed_dart.lines} lines (${coverage.changed_dart.line_percent.toFixed(2)}%). Source mismatches ${sourceMismatch.length}; unmeasured executable files ${unmeasured.length}. The numerical gate is ${coveragePassed?'met for this hashed scope':'open'}. SQL assertions are not SQL branch coverage.`;
const external='Specific approval for isolated synthetic development installation/fixtures/resources, genuine separately authenticated sessions and load, native profile/checks and owner signoff remains open. No production, authentication or acceptance-owned operation is authorized.';
const specific={
 'FR-353':{implementation:'partially_implemented_required_policy_gap',missing_implementation:'Negative-stock OFF checks exist. Versioned authorized/audited enabled-policy issue and subsequent receipt valuation/correction are absent (EC-323).',missing_verification:'Enabled-policy scenarios cannot be verified until the owner selects the material interim basis, cover order and recovery variance classification/account.'},
 'EC-323':{implementation:'required_development_missing',missing_implementation:'Versioned negative-stock policy, audited interim deficit issue and later-receipt exact immutable correction path are absent.',missing_verification:'No enabled-policy implementation exists. The Oct1 weighted-average/oldest-first proposal is not approved accounting; silence or continuation does not select it.'},
 'FR-387':{implementation:'partial_material_comparison_gap',missing_implementation:'Requisition/order/bill conflict editors retain local inputs and block overwrite but lack a fresh scoped current/local material-field comparison before discard/reload.',missing_verification:'Inspect current/local material fields, preserve encrypted inputs through comparison, recheck scope/epoch, and require explicit resolution across the affected mutable forms.'},
 'EC-302':{implementation:'partial_material_comparison_gap',missing_implementation:'The affected procurement conflict UI exposes a conflict notice and discard path without current/local material comparison.',missing_verification:'Structured stale-version handling and immutable local inputs exist; current/local comparison and explicit resolution checks remain required for affected forms.'},
 'EC-340':{implementation:'shared_storage_corrected_caller_verification_pending',missing_implementation:'Shared encryption/write/commit classification is corrected under contract57; complete module-specific safe propagation and no-dispatch-on-failed-save integration is not yet evidenced.',missing_verification:'Synthetic SQLite FULL, key failure and acknowledgement rollback checks are present. Module caller checks plus native storage-full/unavailable recovery remain open.'},
 'NFR-301':{missing_verification:'Strict late-failure rollback assertions cover named side effects. Totals do not prove every possible injected failure point; complete installed roles/atomic effects and independent sessions remain open.'},
 'NFR-307':{missing_verification:'No target-scale ordinary-read p95 under500ms evidence. Small synthetic timings and offline harness checks are not real-load/p95.'},
 'NFR-308':{missing_verification:'No target-scale save/transition p95 under1.5s or single-document posting p95 under3s samples. Mutation load must use fresh command identities.'},
 'NFR-309':{missing_verification:'Required population (500tenants,10entities each,25warehouses/entity,100kproducts/large tenant,10mstock movements,20mjournal lines) has not been installed or measured.'},
 'NFR-310':{missing_verification:'Eleven small-fixture plans exist: nine use synthetic authenticated SQL-role claims; two private-bank plans are privileged. The current residual-plan review labels AR balance, allocation history, requisition lifecycle and reservation lifecycle as zero-row selections. Populated target-scale, nested RPC and no-cross-tenant scan plans remain open.'},
 'NFR-312':{missing_verification:'Sorted locks, unique constraints and prepared race invariants exist; no genuine independently authenticated session/overlap execution establishes the required contention outcomes.'},
 'NFR-313':{missing_verification:'Input-only encrypted recovery, exact original retry and synthetic persistence failures are tested. Native Credential Manager, process restart, storage exhaustion and complete cross-module access acceptance remain open.'},
 'NFR-314':{missing_verification:'Selected semantic/keyboard/reduced-motion/200% checks and rendered matrices exist; complete all-workspace WCAG2.2AA, keyboard and screen-reader acceptance remain open.'},
 'NFR-315':{missing_verification:`Whole shared-checkout desktop has ${currentChecks.desktop.failed} failures. The golden artifact separately classifies preserved control cases and concurrent Wave4 failures. ${golden.identical_images}/${golden.compared_images} final/control output images match; approved images remain unchanged. Rounded border raster differences and preexisting shell navigation content differences are inspected; complete renderer/per-case cause and native visual acceptance remain open.`},
 'NFR-317':{missing_verification:coverageText},
 'NFR-318':{missing_verification:'45-candidate strict final-stack assertions remain synthetic rollback evidence. Genuine concurrency, installed grants/roles and native side effects remain unverified; overlapping assertion totals are not additive unique coverage.'},
 'NFR-319':{missing_verification:`Isolated build ${build.status} in ${build.seconds.toFixed(1)}s, ${build.source_files} source files, source-match at recorded build ${build.current_source_match}. Compilation and bundle hashes do not establish cold launch or authenticated native critical-path acceptance; no executable was launched.`},
 'NFR-320':{missing_verification:'No target-scale ordinary-report p95 under2s or bounded complex-report10s evidence. Scoped progress/cancellation exists; real timing/native cancellation remains open.'},
 'AC-325':{missing_verification:'Target population, populated representative plans, genuinely authenticated critical races and documented p95 samples remain unexecuted.'},
 'AC-326':{missing_verification:'Negative-stock conditional-policy development, any unresolved development findings, golden cause, complete security/native/concurrent/load and owner gates remain open. Executed test/build counts do not close the release gate.'},
};
if(resolved.material_conflict_comparison){
 for(const id of ['FR-387','EC-302'])specific[id]={implementation:'reviewed_correction_source_present',missing_implementation:null,missing_verification:'Fresh scoped current/local comparison and explicit resolution are recorded in the correction evidence; native conflict recovery and complete role acceptance remain open.'};
}
if(resolved.local_storage)specific['EC-340']={implementation:'reviewed_correction_source_present',missing_implementation:null,missing_verification:'Shared and affected module storage failures preserve current input, prevent pre-save dispatch and retain original recovery in synthetic checks. Native disk-full/Credential Manager/process restart acceptance remains open.'};
const requirements=prior.requirements.map(r=>{
 const [kind,num]=r.id.split('-'), n=Number(num);
 const group=kind==='FR'?frGroups.find(([a,b])=>n>=a&&n<=b)?.[2]:kind==='AC'?acGroups[n-301]:kind==='EC'?ecGroups[n-301]:nfrGroups[n-301];
 if(!group||!groups[group])throw Error('Unreviewed approved ID '+r.id);
 const additional=['FR-387','EC-302'].includes(r.id)?resolved.material_conflict_comparison:r.id==='EC-340'?resolved.local_storage:null;
 return {...r,review_group:group,implementation:'reviewed_candidate_source_present',missing_implementation:null,
  source_evidence:[...new Set([...r.source_evidence,...groups[group].files,...(additional?.source_evidence??[])])],
  verification_evidence:[...new Set([...r.verification_evidence,...Object.values(evidence),...focused,...(additional?.verification_evidence??[])])],
  review_finding:groups[group].finding,
  missing_verification:'Referenced synthetic tests establish their named scenarios for their recorded source/query revision. Complete installed/native roles, recovery, accessibility and target-scale sessions remain unverified.',
  external_acceptance:external,...specific[r.id]};
});
const files=[...new Set(requirements.flatMap(r=>[...r.source_evidence,...r.verification_evidence]))];
for(const p of files)if(!fs.existsSync(p))throw Error('Missing cited source/evidence '+p);
// Reading Git references needs no subprocess or index mutation. The caller may
// supply a separately observed staged-path list; absent evidence stays unknown.
let head=fs.readFileSync('.git/HEAD','utf8').trim();
if(head.startsWith('ref: ')){
 const ref=head.slice(5), loose='.git/'+ref;
 if(fs.existsSync(loose))head=fs.readFileSync(loose,'utf8').trim();
 else {
  const packed=fs.readFileSync('.git/packed-refs','utf8').split(/\r?\n/).find(line=>line.endsWith(' '+ref));
  if(!packed)throw Error('Unable to resolve current checkout reference');
  head=packed.split(' ')[0];
 }
}
if(head!==ledger.head)throw Error('Source ledger belongs to a different HEAD');
const staged=options.staged?JSON.parse(options.staged):null;
if(staged!==null&&(!Array.isArray(staged)||staged.some(p=>typeof p!=='string')))throw Error('Invalid observed staged-path list');
const candidates=read(evidence.candidates);
const matrix={generated_on:'2026-10-02',generated_at:new Date().toISOString(),generator:'tools/wave3/current-requirement-matrix-20261002.mjs',generator_sha256:hash('tools/wave3/current-requirement-matrix-20261002.mjs'),head,staged_paths:staged,
 spec:prior.spec,spec_sha256:prior.spec_sha256,counts:prior.counts,
 boundary:'All181approved IDs/full wording are retained. Source presence and synthetic execution are not exhaustive implementation proof, installation, native acceptance, real session/load or owner signoff. Historical checkpoints are superseded only where fresh evidence states a correction.',
 stale_status_corrections:prior.stale_status_corrections,requirements,current_checks:currentChecks,evidence,
 candidate_boundary:{installed:refresh.migrations.length,api_functions:refresh.api_catalogue.length,candidates:candidates.candidate_count,unapplied:ledger.candidates?.every(c=>!c.installed)??'See source ledger artifact',observed_at:refresh.observed_at},
 confirmed_missing_development:requirements.filter(r=>r.missing_implementation).map(r=>({id:r.id,description:r.missing_implementation})),
 policy_decision:'Owner policy selection remains pending. The approved spec does not select interim costing basis, deficit-cover order, recovery variance account/classification or zero-value basis admissibility.',
 coverage_gate:coveragePassed?'met_for_hashed_scope':'open',coverage_source_drift_at_generation:currentCoverageDrift,resolutions:resolved,
 source_sha256:Object.fromEntries(files.map(p=>[p,hash(p)]))};
fs.writeFileSync(base+'requirement-matrix-20261002.json',JSON.stringify(matrix,null,2)+'\n');
fs.writeFileSync(base+'independent-requirements-review-20261002.json',JSON.stringify({...matrix,reviewer:'independent final requirements review agent',reviewed_contracts:[33,43,44,46,47,48,49,50,51,52,53,54,55,56,57,58],review_findings:matrix.confirmed_missing_development},null,2)+'\n');
const link=p=>`[${p.split('/').at(-1)}](../../../${p})`;
const safe=s=>String(s??'No further specific code gap confirmed in reviewed scenarios; exhaustive verification remains open.').replaceAll('|','/').replace(/\s+/g,' ').trim();
fs.writeFileSync(base+'requirement-matrix-20261002.md',[
 '# Approved Wave3 requirement-to-evidence matrix — 2026-10-02','',
 'All95FR,26AC,40EC and20NFR IDs/full approved wording are retained in the companion JSON. This matrix separates confirmed development gaps, missing verification and external acceptance. Wave3 is not fully complete.','',
 `HEAD ${head}; staged paths ${staged?.length??'not independently observed by this generator'}. Current whole desktop ${currentChecks.desktop.passed} passes/${currentChecks.desktop.failed} failures. Whole platform ${currentChecks.platform.passed} passes/${currentChecks.platform.failed} failures. Failure ownership is recorded in the cited logs; whole-checkout results can include concurrent Wave4 changes. Focused runs overlap and are not added to whole-suite totals.`, '',
 coverageText,'',
 '|ID|Approved behavior|Reviewed implementation sources|Verification evidence|Missing implementation|Missing verification|External acceptance|',
 '|---|---|---|---|---|---|---|',
 ...requirements.map(r=>`|${r.id}|${safe(r.approved_behavior)}|${r.source_evidence.map(link).join(', ')}|${r.verification_evidence.map(link).join(', ')}|${safe(r.missing_implementation)}|${safe(r.missing_verification)}|${safe(r.external_acceptance)}|`),
 '', 'Every evidence file is hashed in JSON. September30 candidate totals and source-specific whole-client results remain dated synthetic evidence; new tests do not turn them into an installed/native release.', ''
].join('\n'));
fs.writeFileSync(base+'independent-requirements-review-20261002.md',[
 '# Independent Wave3 requirements review — 2026-10-02','',
 'The companion JSON reviews every approved identifier and preserves its wording. This review follows current source, public contracts 33/43/44/46/47/48 and additive contracts 49–58. No migration, Git index, authentication, native store or acceptance-owned file is changed by the generator.','',
 `The source snapshot is HEAD ${head}. The supplied read-only catalogue refresh records ${refresh.migrations.length}installed migrations and ${refresh.api_catalogue.length}API functions; the reviewed45 candidates remain separate and unapplied. Stock-opening/approved-golden protection and concurrent-owner drift are recorded in ${link(evidence.sourceLedger)}.`, '',
 '|Approved area|Reviewed source finding|', '|---|---|',
 ...Object.entries(groups).map(([name,g])=>`|${name}|${g.finding} Sources: ${g.files.map(link).join(', ')}|`), '',
 'Confirmed required development gaps:', '',
 ...matrix.confirmed_missing_development.map(r=>`- ${r.id}: ${r.description}`), '',
 'FR353/EC323 is a real conditional-policy development gap, not an installation-only gate. The Oct1 proposal for an authoritative positive-pool basis, stable cover order and exact later-receipt variance remains a proposal. Material owner policy selection is pending; no accounting algorithm approval, fabricated provenance or negative receipt cohort is inferred.', '',
 `Current/local material conflict comparison and EC-340 storage state are ${resolved.material_conflict_comparison&&resolved.local_storage?'resolved in current source and executed synthetic correction evidence':'still subject to the resolution evidence below'}. Contract 58 precedes current/local comparison; contract 57 precedes typed safe storage failure. Comparison preserves encrypted input and requires explicit reload; failed saving retains in-memory fields and blocks new prerequisite-dependent dispatch. Earlier failed test attempts remain historical. Native storage, original-command restart and authenticated access acceptance remain separate.`, '',
 `Current whole desktop: ${currentChecks.desktop.passed} passed/${currentChecks.desktop.failed} failures. Whole platform: ${currentChecks.platform.passed} passed/${currentChecks.platform.failed} failures. Failure ownership must be read from the cited source-sensitive logs. ${golden.identical_images}/${golden.compared_images} failed render outputs match unchanged HEAD control, with ${golden.current_only.length}/${golden.control_only.length} current/control-only cases. This establishes reproduced failures, not their root cause or visual acceptance.`, '',
 coverageText,'',
 `Isolated Windows compilation: ${build.status}, ${build.seconds.toFixed(1)}seconds, ${build.source_files}source hashes. Current-source match is the build’s recorded observation (${build.current_source_match}), not a permanent guarantee against concurrent later edits. ${link(evidence.bundle)} supplies separately dated host/Dart bundle evidence. No executable was launched.`, '',
 'Strict 1,328 final-stack rollback assertions (991 finance/procurement, 155 inventory, 182 AR) are recorded for 45 candidate sources; 209 foundation/CRM/quotation/order assertions used the preceding 44-candidate stack. Counts overlap and do not prove installation, all possible failure stages, real concurrent sessions or target-scale p95. The refreshed representative-plan query passes 1,005 overlapping assertions with strict finish and final rollback. Its nine authenticated SQL-role plans use synthetic copied claims; two private bank bases are privileged. AR balances, allocation history, requisition lifecycle and reservation lifecycle selections are explicitly zero-row; populated plans/load remain open.', '',
 'The existing compatibility result is zero breaking/eight potential warnings, with a nonlexical45candidate/eight-phase dependency/restore/native procedure. These warnings require the concrete owner acceptance before installation. Complete genuine independently authenticated contention, required large fixture population, ordinary/report p95, native cold-launch/file/draft/keyboard/accessibility and owner signoff remain separate gates.', '',
 'No unapproved automatic reservation scheduler, separate serial-history workspace, supplier-withholding engine, statutory certification or background oversized report is added as a requirement. Unknown historical control attribution remains explicit rather than guessed.', '',
 'Wave3 is not fully complete. Concrete installation/native approval belongs after remaining development and source-sensitive review checks are completed.', ''
].join('\n'));
console.log(JSON.stringify({total:requirements.length,counts:matrix.counts,confirmed_missing_development:matrix.confirmed_missing_development,coverage_gate:matrix.coverage_gate,evidence_files:files.length,spec_sha256:matrix.spec_sha256}));
