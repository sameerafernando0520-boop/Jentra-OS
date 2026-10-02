# W4-07 fixed assets and exact book effects

2026-09-30. Synthetic development contract for FR-435–438, AC-416–418,
NFR-401–406 and EC-413–414. Parent: blueprint 40. No statutory certification or
production accounting is implied. All write authorities require current scope,
the Assets entitlement, the specific capability and MFA before actor-bound replay.

## Source and capitalization authority

An asset belongs to a tenant/entity/accountable branch, with immutable source
lineage, cost components, ownership, location, custodian and in-service evidence.
Equipment linking is an explicit operational association and creates no value.
Opening evidence is a governed, independently approved synthetic command; it
states cost, original accumulated depreciation and opening offset accounts.
Procurement and stock sources require an installed provider that locks the actual
eligible source, excludes previously consumed/capitalized quantities and removes
the same amount from stock value atomically. Missing source providers are explicit
unavailable states; a text source reference never establishes eligibility.

Capitalization locks source then asset/book, verifies active same-entity base-
currency accounts, customer/supplier control exclusions, open period, independent
approval and the exact frozen revision. It posts cost and opening accumulated
depreciation with source UUID attribution through the installed journal engine.
Source ownership, book history, redacted audit/receipt and outbox commit together.
New source values never remain simultaneously authoritative stock and asset value.
Foreign-currency source components retain their exact provider FX/tax basis;
the first posting book is in entity base currency.

## Immutable books and schedules

Each book revision freezes cost, original accumulated depreciation, residual,
remaining life, method, in-service/first-period convention, currency precision,
expense/accumulated-depreciation accounts and reason/actor. Residual cannot exceed
carrying value. Amounts use exact decimal strings/BigInt; book cost, residual and
opening accumulated amounts must be representable at the stated 0–6 precision.
Remaining life is 1–1200 months and schedule pages are at most 50 rows.
Impairment has a separate reserve; it never rewrites accumulated depreciation.
Schedules deduct both balances from gross cost while retaining depreciation-only
accumulation. Revaluation changes gross cost through explicit surplus/loss
mappings and preserves both historical contra balances.

The initial synthetic methods are `straight_line` and `reducing_balance` with a
published exact rational rate in (0,1]. No business/legal rate is inferred. The
initial conventions are full in-service month or next calendar month; these are
explicit whole-month allocation choices, not actual-day depreciation. A book
using an unsupported convention/method is unconfigured until its provider exists.
Calendar months use civil first-day boundaries and retained period/date evidence.

Straight-line schedules round cumulative targets at the stated precision using
half-even, then allocate differences between successive targets. This distributes
small-value rounding deterministically, prevents negative or excess installments,
and conserves the exact depreciable value at the final period. Reducing-balance
periods multiply current carrying value by the exact published ratio, half-even
round, cap at carrying minus residual, and allocate the remaining depreciable
balance to the final life period. Zero installments are explicit schedule facts;
they are not fabricated zero journals.

Prospective changes start at the first unposted period and retain all old
schedules/effects. They freeze current carrying/accumulated values and a new
remaining life/rate/residual. Already posted periods require separately governed
original-effect reversal/correction. No change silently recalculates past facts.

## Posting, reversal and disposal

Posting serializes asset, book and period, validates the exact approved schedule
revision/current carrying basis, active state and open period, and consumes each
period once. Journal expense debits equal accumulated depreciation credits with
asset/book/period source attribution. A disposed asset rejects further posting.
Reversal references only the original journal/effect once, requires an open
original posting period, and cannot pass a dependent later posting/disposal.
It restores the original carrying balance without replacing history.
Each immutable book/period has one posting effect, including explicit zero
periods without journals. After a period reversal, posting that calendar period
requires a new independently approved book revision; the original effect remains
unique. A book revision itself can be reversed before dependent posting.
Journal source identities are immutable effect UUIDs, linked to asset/book/period
facts and original source/component UUIDs. Opening reversal retains terminal
source ownership and does not authorize reusing the same opening evidence.

Transfers retain original/current accountable branch, location and custodian with
dated authorization in both scopes. Impairment and configured revaluation record
independently approved before/after cost/accumulated/residual facts and explicit
expense/surplus accounts; unsupported mappings reject before effects. Disposal
freezes proceeds, exact tax/FX provider evidence where applicable, cost removed,
accumulated depreciation removed, net book value and gain/loss. It uses named
configured accounts and journals atomically with the disposed state. Reversing
disposal restores its original effects only and checks all dependent consumption.
Depreciation/disposal races use the same lock ordering.

## Native recovery and evidence

Native register/books/schedules/effects use scoped named source/account/location/
custodian pickers, permitted actions, bounded history and explicit provider
unavailability. Exact uncertain commands are encrypted by actor and complete
operational scope, immutable until reconciled, and require comparison after a
version conflict. Late old-context responses cannot restore visible state.
Confirmed writes remain confirmed if optional reads fail.

Verification covers exact final conservation, tiny values, half-even ties,
prospective boundaries, source duplication, stock exclusion, cross-scope/grants,
independent approval, stale/revoked replay, closed periods, late atomic failure,
original reversal and disposed-state denial. Real overlapping connections and
measured p95, installed checks, native authenticated/restart/rendered evidence and
owner acceptance remain distinct. A schedule calculator alone closes none of
the database, gateway, native or acceptance requirements.
