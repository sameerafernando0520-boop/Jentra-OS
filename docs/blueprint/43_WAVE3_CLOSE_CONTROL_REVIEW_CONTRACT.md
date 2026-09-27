# Consolidated control and close review — FR-375 / FR-382 / AC-320

Unapplied development candidate, 2026-09-26. The immutable review captures all
entity branches, including retired branches with history. The requested branch is
the working context. Generation, replay and reads require entity finance and
control-reconciliation access and finance/control/stock/cost access in every
branch. Existing privileged MFA rules apply. Authentication is unchanged.

`api.generate_close_control_review` saves a version-one snapshot for an active
fiscal period and a nonfuture cutoff within that period. `api.close_control_reviews`
lists 50 saved summaries. `api.close_control_review_page` reads 50 frozen controls,
differences, sources, stock, transit or blockers, optionally filtered by component
key. A saved report from another working branch is readable only with the same
entity-wide access. Known IDs never bypass scope checks.

AR/AP/GRNI reuse the existing exact open-item, original-account, dated allocation,
return and reversal builders. AR/AP source differences are adjusted only for
attributable frozen FX runs by the existing period governance helper. Inventory
reuses dated valuation, pooled stock value and in-transit evidence. Its account
basis is disclosed: current product inventory mappings plus asset legs of the
original posted stock journals at the cutoff, including retired mappings. No
account or journal is rewritten. Net-zero source mismatches remain blockers.

Bank controls show transaction-currency book balance, last statement closing,
dated unmatched bank and book movements and their exact reconciliation equation:
adjusted statement = closing - unmatched bank + unmatched book; difference =
adjusted statement - book. Matches/reversals are evaluated at the cutoff, not
from today's mutable claims. Missing statement coverage, ambiguous currencies or
duplicate bank GL basis block review. Cash registers expose attributed ledger
balance with an explicit `ledger_only` status; this is not a physical cash count.
Components use their own disclosed currency; no mixed-currency grand total is
invented. Journal and bank-line source identity remains visible in frozen pages.

The review includes the existing live close exceptions for drafts, FX, bank,
cash-flow and tax, plus GRNI, inventory and bank-balance checks. Hard close runs
the new checks again under the existing locked period; a previously saved clean
review cannot waive a later backdated difference. Unavailable or oversized checks
fail closed. Review snapshots have no posting or period-transition authority.

Bounds: 500 branches, 50 inventory accounts, existing per-builder input limits,
10,000 cash GL and bank inputs, 50,000 rows per section and 16 MiB total evidence.
Limit failure saves no partial review, audit, command receipt or outbox event.
Database arithmetic uses numeric; all amounts cross the public boundary as
decimal strings. Client validation checks exact component equations, scope,
cutoff, filters, source identities and cursor bounds before display.

`/finance/close-review` supports encrypted inputs, sealed identical retry, atomic
confirmation even after route disposal, and evidence invalidation after offline,
permission or MFA changes. Stale reads cannot restore cleared evidence. Development
rollback tests, rendered previews and compilation remain distinct from installed
behavior, concurrent load, Credential Manager restart and native/owner acceptance.

Additive contract [47](47_WAVE3_CONTROL_READ_PLAN_CONTRACT.md) preserves this API
and its exact source/cutoff/boundary while improving the private inventory-account
read plan with deduplicated command/source joins and a supporting index.
