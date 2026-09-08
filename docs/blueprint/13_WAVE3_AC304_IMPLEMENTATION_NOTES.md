# AC-304 implementation notes

2026-09-07. Implements the approved Wave 3 specification, FR-322–FR-325 and
AC-304, as explicitly requested by the product owner. The specification remains
the acceptance contract; its strict validation passed 100/100 with no findings.
Development only: `xpdoufauvrbdmxgngetv`. Starting ledger: 28 migrations, latest
`20260906153036`. Preserve the uncommitted AC-303 implementation on `main` at
`b3d793b`; no staging, commits or pushes are authorized.

Implementation and synthetic-development verification are complete. See
[the verification report](14_WAVE3_AC304_VERIFICATION.md). The additive migration
`20260907044241_complete_sales_order_workspace.sql` is applied in development;
the live ledger now contains 29 migrations. Existing migrations were preserved.

## Contract gaps found before implementation

- Order headers and lines are separate reads. Add a caller-RLS detail view so
  the editor receives one coherent commercial/version snapshot.
- Credit decisions exist, but there is no authoritative pre-confirmation read.
  Add a permission-checked, currency-specific credit preview with its projection
  timestamp and availability. Confirmation must still re-evaluate under locks.
- Converted orders reject every existing upsert. Add a narrow command to revise
  promised date, ship-to and warehouse while still in draft/credit hold, retaining
  source quotation, source lines, all prices/taxes and commercial terms.
- Confirmation must reject an inactive customer even if the order was created
  while that customer was active. Stock reservation must validate current product
  and warehouse eligibility and exclude already delivered demand.
- Cancellation must record cancelled line quantities as well as releasing active
  reservations. It must not change on-hand stock or create journals/movements.

Corrections are additive migrations; all previously applied files remain immutable.
Tests must demonstrate failures before correction and pass in rollback before any
development application. Existing conversion/idempotency, credit-override roles,
audit, receipts, telemetry, outbox and RLS safeguards remain in force.

## Desktop slice

Capability-gated Sales Orders register, literal search and bounded pages; direct
order drafts and exact commercial editing; accepted-quotation conversion with
promised date, ship-to and governed warehouse; converted-order fulfillment editing;
server credit preview/decision history, credit hold and reasoned privileged override;
stock availability, bounded reservations and cancellation/release feedback.

Persist raw fields and complete command envelopes encrypted in an order-specific,
actor/tenant/entity/branch namespace before transport. Keep exact request IDs,
timestamps, payload and expected version across uncertain retry. Guard offline
commands, double actions, stale responses, revoked/loading/failed capabilities,
and explicit version-conflict choices. Never treat conversion or reservation as
revenue recognition, an accounting posting or a physical stock movement.

## Verification plan

SQL tests: coherent scoped reads, inactive customer, currency mismatch, credit
preview/decision agreement, immutable conversion pricing, fulfillment edits and
stale/replayed commands, cancelled quantities, reservation eligibility and remaining
demand, revoked access, atomic failure and no posting effects.

Dart/Flutter tests: exact codecs, bounded/scoped adapter requests, immutable retry
envelopes, editor/conversion/credit/reservation flows, denial/offline/conflict/scope
changes, readable financial snapshots and responsive light/dark/accessibility
goldens. Run full regression, formatter, analyzer, secret scan and Windows build
after `flutter pub get --offline`. Record runtime/load limitations separately.

The Engineering spec-driven skill guides traceability and test-first work. Finance
guidance is limited to source-data validation, currency separation and explicit
assumptions; Revenue Operations guidance is limited to traceable commercial
handoffs. Valuation, SaaS metrics, financial projections, delivery posting (AC-305),
invoicing, production changes and plugin permission changes are outside this slice.
