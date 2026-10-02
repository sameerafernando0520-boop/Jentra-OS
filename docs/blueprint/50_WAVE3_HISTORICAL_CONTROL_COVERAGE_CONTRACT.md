# Historical AR/AP control coverage

Additive candidate for FR-367–368, FR-375, EC-329 and AC-317/320. Contract 33's
source-derived controls and immutable allocations/reversals remain authoritative.

An append-only private control-basis registry records each current and subsequent
AR/AP mapping with tenant/entity, kind, account, effective observation time, actor
and source. Retirement/remapping cannot remove its account from reconciliation.
Existing historical account basis is discovered only from attributable original
open-item/source journal controls and audit mapping snapshots. Missing historical
evidence is disclosed; no arbitrary same-type GL account or guessed provenance is
treated as a control. Historical retired mappings with supported recorded evidence
participate even when they have no remaining open items. Every posted GL leg in
the covered control set is compared, preserving net-zero per-command differences.

The candidate seeds the registry from current AR/AP mappings and the immutable
before/after contexts of `posting_mappings` and `supplier_bill_controls` audit
events. It validates account tenant/entity and asset/liability type before
admitting a recorded historical account. Additive mapping triggers record future
replacements and retirement before the old account can be lost from the current
configuration. The registry does not backfill undocumented manual account use.

The report exposes basis coverage and historical account identities. More than
50 controls or existing input/evidence bounds fails without partial totals.
The existing GRNI wrapper first counts the bounded receipt input using the
tenant/entity/branch index, then performs provenance work only when it fits;
the same 10,000-row limit and output remain authoritative.
Allocation corrections retain original account/FX/rounding values, append linked
records and use existing sorted locks and exact posting engine. No source item or
journal is rewritten. The development installation review must inspect unknown
legacy conventions explicitly; native/owner acceptance remains separate.
