# Independent Wave 3 requirements and API review — 2026-10-01

This review covers the approved 95 FR, 26 AC, 40 EC and 20 NFR identifiers.
The companion JSON retains every approved behavior and separates reviewed source,
synthetic evidence, remaining development/verification and external acceptance.
It does not infer completion from a contract, route or test filename.

The current checkout is `f9cc342815e2446fb3f26204d5e65e03c1b2a140`, with concurrent
dirty Wave 4/5 work. The index was empty when refreshed. Root's 09:58 UTC ledger
refresh records 37 installed migrations, 85 API functions, unchanged shared
finance helpers and 45 unapplied candidates. This review installed nothing and
did not change acceptance-owned stock opening, authentication or native stores.
The latest source/build/coverage hashes must be refreshed after the concurrent
corrections below; dated reports are historical evidence.

| Approved area | Current source and synthetic evidence | Remaining boundary |
|---|---|---|
| FR-301–312 / AC-301 | Scoped command hash/replay, optimistic versions, permanent numbers, workflow decisions, atomic receipts/audit/outbox; security-invoker views and private helpers. Contract 49 extends aggregate-specific files/notifications. | Independent sessions and installed/native scope/replay remain unverified. Three authenticated read-only policy predicates are the documented narrow helper exception, not mutation grants. |
| FR-313–318 / AC-302 | CRM leads, activities, qualification, conversion and dated exact pipeline readers; foundation/CRM candidate assertions. | Full native keyboard/role flows and target-scale pipeline reads remain open. |
| FR-319–334 / AC-303–308 | Versioned quotations, traced orders/credit controls, reservations, delivery, invoices, receipt allocation and immutable returns/dated AR. | Genuine final-stock/credit races, installed financial flows and full visual acceptance remain open. |
| FR-335–349 / AC-309–312 | Requisitions/RFQ/PO, receipt/matching/AP/payment/return commands, source links, statements and allocation corrections. | Exact form/recovery checks are synthetic; native settlement and claims contention remain open. |
| FR-350–361 / AC-313–315 | Rational units, immutable tracked movements, pooled cost, transfers, cutoff counts, bounded partitions, provenance, landed corrections, disposition, dated valuation and governed reservation maintenance. | Required negative-stock policy edge case EC-323 has no implementation; see the compatible design below. Genuine issue/serial/transfer races and target-scale valuation are open. |
| FR-362–368 / AC-316–317 | Exact immutable journals, manual approval, source-line evidence, open-item source controls, linked AR/AP allocation reversals and retired mapping registry. | Unsupported historical account conventions fail explicitly and require installation review. Current catalogue labels must not be described as historical labels. |
| FR-369–378 / AC-318–320 | Governed accounts, bounded bank import/matches, FX/period rules, AR/AP/GRNI/inventory/cash/tax controls, financial/comparative statements and indirect cash-flow lineage. | Independent matching/close races, real p95 and MFA-backed native reopen remain open. |
| FR-379–382 / AC-320 | Approved exact budget versions, governed dimensions, variance, tax treatment/review notice and frozen report scope/cutoff/lineage. | Approved images remain preserved; all report/native and unmapped historical handling still need acceptance. |
| FR-383–395 / AC-321–324 | Capability navigation, dated dashboard metrics, filtered bounded current lists, scoped deep links, source/files, notification subscriptions/due scans and governed CSV/XLSX jobs. | The private-link root-dialog access gap was confirmed and corrected below; native files/restart and complete accessibility remain open. |
| NFR-301–306 / NFR-318 | Numeric/exact strings, force-RLS/grants, empty privileged search paths, capabilities/MFA/SoD, immutable history and late-failure rollback assertions. | Assertion totals do not prove every possible failure location or genuine concurrent sessions. Installed role/Storage checks remain external acceptance. |
| NFR-307–312 / NFR-320 / AC-325 | Tenant-leading indexes, bounded readers, small-fixture plans and offline load/race harness preparation. | NFR-309 population, populated reservation plans, nested RPC plans, genuine contention and measured p95 remain unexecuted. Two private bank plans are privileged fixture evidence. |
| NFR-313–319 / AC-326 | Encrypted input-only recovery corrections, rendered synthetic previews, keyboard cases, coverage and isolated compilation. | Overall 80% coverage, 81 retained approved-golden failures, complete WCAG/native cold launch/process restart and final current-source compilation remain open until fresh evidence is recorded. |

## Confirmed attachment correction

The earlier `OperationalWorkspace._openAttachment` displayed a signed URL in an
ordinary root dialog. It checked connection only before opening, so disconnect,
refresh or disposal could leave the link visible; a reconnect or replaced
workspace could accept an old link reply. The rejection dialog could also retain
an obsolete action. These are FR-388/391/395, AC-322/324 and NFR-313 boundaries.

Contract 49 was updated before behavior. `OperationalController` now implements
the existing verified read-access epoch interface; denial clears evidence and
disposal notifies surviving dialogs. Private-link/rejection dialogs reuse the
shared access guard. Late link/file-picker replies bind both originating
controller and epoch. Encrypted upload/rejection envelopes and confirmations
are unchanged.

Ten new desktop cases failed against the prior behavior. The corrected cases
and existing operational/file/report recovery tests pass **23/23** in
`build/remaining-wave3/operational-attachment-first-20261001.log`; its branch
coverage is retained in the matching `.info`. The actual Storage SDK exposed a
second adapter gap: HTTP 401/403, malformed signed responses and transport errors
escaped as raw SDK exceptions. The mocked-HTTP red run has **2 passes / 7 failures**
in `operational-attachment-platform-red-20261001.log`. Adapter correction and
final tests are recorded in the companion evidence once executed. No real file,
Storage object, signed URL or native dialog was used in these checks.

## Required negative-stock development gap — FR-353 / EC-323

The approved wording is:

> FR-353: A posting that would make on-hand or available quantity negative MUST
> be rejected unless the legal entity has an active negative-stock policy and
> the actor has the override capability; every override MUST be separately audited.

> EC-323: Negative stock override produces a later receipt -> value the interim
> issue and subsequent correction according to the versioned negative-stock
> policy and expose the variance.

Blueprint 02 also says negative inventory is disabled by default and requires a
separately audited entity policy. No approved document in the blueprint/development
search fixes an interim or later-receipt costing algorithm. Negative-stock OFF
behavior is implemented: the installed delivery schema has nonnegative stock and
carrying-value constraints, and delivery rejects insufficient reservation/stock.
The `inventory.stock.override` capability exists without a policy/override path.
Contract 29 prohibits negative receipt-provenance positions. The approved enabled-
policy edge case is therefore **missing development**, not an installation-only
or native-only gate. The current 181-ID matrix must not silently mark EC-323 done.

A compatible proposal for a new public contract and additive candidate is:

1. Keep the policy disabled by default. A versioned, attributable entity policy
   must specify the interim basis and recovery-variance account/rule. An online
   override requires current stock override capability, configured MFA/SoD,
   reason, an open period and matching policy version. The normal off path and
   stock-opening acceptance remain unchanged.
2. Accept a basis only from an authoritative **positive** quantity/carrying-value
   snapshot for the same tenant/entity/warehouse/product under existing sorted
   locks. Persist its source/version and exact numerator/denominator. With no
   valid basis, reject the override. Do not use an invented last receipt, unknown
   baseline or client-supplied historical cost. Lot/serial unavailable or disposed
   identities remain rejected; an override cannot invent physical units.
3. Record each uncovered quantity and its provisional value in immutable deficit
   evidence separate from receipt provenance. Existing positive cohorts never
   become negative. Original issue/movement/journal rows remain unchanged. Report
   negative/provisional stock and deficit basis explicitly rather than calculating
   an ordinary average through a zero/negative denominator.
4. A later eligible receipt covers a bounded deficit set in a declared stable order.
   Compute its actual receipt-value share using exact cumulative rounding and
   compare it to the provisional covered share. Post the difference through a
   linked inventory/COGS or governed variance journal, with receipt and deficit
   identities, at the receipt/correction date. The receipt, deficit settlement,
   provenance, projections, journals, audit, receipt and outbox are one transaction.
   No historical cost/quantity or posted journal is overwritten.
5. Include dated deficit/settlement evidence in valuation and inventory-to-GL
   controls. Prevent duplicate settlement/overcoverage; preserve reversal
   compatibility, closed-period rules, exact retry and tenant/cost boundaries.
   Require strict synthetic rollback, property and real-session tests.

For an explanatory policy example, a frozen positive pool of 10 units / 100 value
supports provisional unit cost 10. Issuing 13 yields a 3-unit / 30 provisional
deficit. A later receipt of 5 units / 100 value covers 3 at actual value 60; a
linked 30 correction leaves 2 units / 40 carrying value. This is a **proposed
policy example**, not implemented accounting or approved golden behavior.

The owner must approve the proposed last-valid-positive-pool interim basis,
stable deficit cover order and classification/account of recovery differences,
including whether a zero-value positive snapshot is admissible. The approved
specification does not select those material accounting choices. No policy was
enabled and no deficit schema or valuation rule was fabricated in this review.
This policy decision must be requested separately from installation approval.

## Historical and compatibility findings

Contract 50's registry seeds current and audited before/after AR/AP controls and
records future remapping/retirement. The report includes attributable retired
accounts even without remaining open items, exposes missing historical basis and
does not guess arbitrary same-type GL accounts. Original source controls drive
allocation corrections. Dated residuals, linked FX reversals and remaining-value
rounding preserve immutable items/journals. Unsupported unknown history is an
explicit compatibility limitation, not invented provenance or silent balance repair.

Contract 51's landed extension supports quantity/original-value/manual exact
weights; cumulative rounding conserves the total. Held, transit and consumed
variance are separate. Later consumption in tests uses a synthetic pooled issue
and the real provenance trigger; that is not an authenticated delivery walkthrough.
Wholly consumed new allocations reject; a reasoned later correction can post only
its incremental consumed variance. Frozen transfer cost remains unchanged while
supplemental transit value settles exactly on receive/reverse.

Count partitions cover 501 serial/lot identities as 500 + 1 with one cutoff and
immutable unique manifest, independent approval/posting and explicit cancellation/
incomplete totals; 10,001 rejects. The reservation maintenance page is bounded,
cursor-based, permission checked and atomic through governed child releases. It
does not promise an automatic scheduler. Serial history is supplied by immutable
serial-linked movements; the specification does not require a new serial-history
workspace. Tax classifications/review notice do not require a supplier-withholding
engine or statutory certification.

The compatibility checker reports **zero breaking changes and eight potential
warnings**, not a green verdict. The exact dependency order is nonlexical: posted
journal candidate ordinal 36 precedes operational evidence ordinal 37. The reviewed
45-candidate/eight-phase installation and restore/forward-repair plan exists, but
requires the specific isolated target, owner acceptance of semantic warnings,
restore point and approved resource/fixture/native profile boundaries. No global
`db push`, ledger repair or destructive downgrade is justified.

The approved release gate remains open. Candidate rollback, test coverage and
compilation must not be labelled installed, authenticated native, genuine
multi-session, target-scale p95 or owner acceptance.
