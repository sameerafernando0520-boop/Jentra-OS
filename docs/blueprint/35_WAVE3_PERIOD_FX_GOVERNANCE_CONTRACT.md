# Period governance and exchange revaluation — AC-319

Development candidate only. This contract does not install the migration or grant
native, production, load, or owner acceptance. Existing sign-in and MFA remain
user-managed.

## Accounting boundary

The existing exact journal, immutable open-item, realized-settlement FX, posting
mapping and command engines remain authoritative. A period-end revaluation never
changes source-currency principal or rewrites an open item. It freezes the scoped
residual set, historical control account, persisted closing-rate ID/value, six-place
base delta, hash, journal ID, actor, reason and time. One run covers one branch,
foreign currency, period and as-of date. The source snapshot is bounded to 1,000
items and 4 MiB; larger work must be partitioned before posting. Journal lines
debit/credit the historical AR/AP control and configured exchange gain/loss at
zero transaction amount. A new run reverses the previous active unrealized run
in the same transaction, links it, and posts the replacement. An explicit reverse
also preserves both original records. Reversal uses the original journal amounts.

`finance.fx.post` is entity scoped and `finance.view` branch scoped. An FX journal
may post in `open` or `soft_locked`; every ordinary posting source still requires
`open`. `hard_locked` rejects all posting. Period row locks serialize commands
against allocations and other posting. Commands require exact version, scoped
identity and sealed idempotency. The existing correction engine continues to
recognize realized settlement differences; unrealized revaluation is separate.

## Governed period states

`api.period_governance_command` accepts `soft_lock`, `hard_lock`,
`request_reopen`, and `approve_reopen` with `id`, `period_id` and a reason of
3–1,000 characters. A reopen approval also supplies `request_id`. State
transitions are `open → soft_locked → hard_locked → open`; a same-actor,
same-transaction private event is required, so the older Setup update API cannot
bypass governance. `finance.period.close` or `finance.period.reopen` must be
entity scoped, with `finance.view` for the selected branch. Reopen request and
independent approval require a signed `aal2` JWT with a `totp` or `otp` AMR
timestamp no older than 15 minutes. AAL2 without a recent method timestamp
fails closed. The requester cannot approve their own request. The prior hard
close remains immutable after reopen.

Hard close recalculates every active branch's AR/AP report at period end, then
matches each control-account/command difference to independent immutable FX
snapshot and reversal deltas. Unexplained differences block close. Draft
journals, unmatched bank lines or bank GL lines, missing/stale FX valuation,
missing current closing rate, and a period that has not ended also block close.
An attempted close with exceptions leaves the period soft locked and writes an
immutable `close_blocked` event containing coded exceptions. A successful close
records an empty exception array and hard locks atomically. An active prior FX
run must be renewed at the cutoff even if all foreign items have since settled;
the current residual hash and most recent active closing rate must match.

## Public API and recovery

All commands use the existing envelope: tenant, entity, branch, command ID,
idempotency key, timestamp, JSON payload and expected version. Period actions
expect the current fiscal-period version; FX `post` expects 0 and `reverse`
expects 1. `post` adds `as_of`, `currency_code`, and `exchange_rate_id`;
`reverse` adds `as_of` and `run_id`. The response contains the sealed receipt,
scope, action/status, version and source linkage. `blocked` is a confirmed
period-command outcome, not a transport error.

`api.period_governance_options` pages active periods, events and reopen requests.
`api.exchange_revaluation_options` pages closing rates and runs.
`api.exchange_revaluation_detail` pages a frozen run's source items. Each page
has at most 50 rows and scoped identifiers. Private event, snapshot and reversal
tables have forced RLS and no direct authenticated table grants.

The `/finance/periods` desktop workspace shows the current state, close
exceptions, reopen requests, closing rates, run lineage and bounded source
items. It saves forms and sealed retry envelopes in the existing encrypted,
actor/scope-specific draft store. Offline actions are disabled and server
evidence is hidden until access is freshly verified. A confirmed command is
cleared before refresh; uncertain outcomes retain the identical request.

## Verification boundary

The additive candidate migration is rollback-tested with historical procurement,
finance, inventory and receivables suites. Focused tests cover open/soft/hard
posting, a genuine clean hard close, blocked close evidence, independent
recent-MFA reopen, exact FX replacement/reversal and control valuation pairing.
Client tests cover scoped RPC contracts, decimal strings, encrypted restart
recovery, offline behavior and 200% desktop rendering. These checks do not
prove migration installation, concurrent-session races, sustained load, real
Credential Manager restart or authenticated native acceptance. No destructive
down migration is proposed for immutable financial history.
