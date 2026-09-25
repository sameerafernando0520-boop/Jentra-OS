# AC-320 financial statements candidate review — 2026-09-25

This review covers the first FR-376 slice only. The development Supabase
project `xpdoufauvrbdmxgngetv` was `ACTIVE_HEALTHY` on PostgreSQL 17.6. Its
installed migration ledger still contains 34 migrations and ends at
`20260911130900_stock_opening_approver_setup`. The financial statement,
period/FX, bank, and other later Wave 3 migration files were not installed.
No production project, authentication setting, stock-opening acceptance record,
commit, stage or push was changed by this slice.

The candidate is `supabase/migrations/20260925002000_wave3_financial_statements.sql`,
composed by `supabase/tests/build_financial_statement_candidate.ps1` with
the existing unapplied dependencies. The builder requires a final `ROLLBACK`
and substitutes strict pgTAP `finish(true)`. Fresh development executions:

| Rollback suite | Result |
|---|---:|
| Procurement, finance, period/FX, bank and statements | 467/467 assertions, no failures |
| Inventory regressions with the same candidate stack | 105/105 assertions, no failures |
| Receivables regressions with the same candidate stack | strict `1..158`, no failures |

The new synthetic statement fixtures prove posted-only exact balances,
period-only profit, comparative profit and balance equations, cumulative
unclosed earnings, journal/account drill-through, idempotent replay,
immutable backdated results, direct evidence access denial, cross-actor read
denial and invalid period/statement rejection. They do not simulate real
multi-session contention or a large ledger at the documented caps.

The scoped Supabase gateway verifies receipt identity, tenant/entity scope,
exact decimal strings and balance equations before accepting data. The
desktop `/finance/statements` route exposes report generation, saved reports,
comparison and source drill-through. The editor uses the existing encrypted
draft store; a simulated restart retries the identical sealed envelope.
Offline and permission-revoked states hide report evidence. Focused adjacent
finance client tests pass: 27 gateway checks and 42 desktop checks, including
five new gateway checks and nine new workspace checks. The new light/dark
200% text goldens were opened and visually reviewed; labels, commands and
saved report identity were legible without a visible overflow. Both platform
and desktop analyzers reported no issues. A final current-source Windows
release build passed in 78.5 seconds; the executable was not launched.

Existing development security advice still reports leaked-password
protection disabled; no Auth change was made. Existing performance advice
lists unused indexes. These advisor results concern the installed schema and
cannot validate an unapplied candidate.

Open within AC-320: cash-flow classification and its unmapped blocker,
inventory/GRNI/tax/cash report consolidation, tax summary/return review,
approved budgets and exact budget variance, dimension-bearing journal
actuals, richer as-of exports and load/contention tests. Installed behavior,
real Windows Credential Manager restart recovery, authenticated native
walkthrough and owner signoff remain unverified. The candidate is not an
acceptance or release claim.
