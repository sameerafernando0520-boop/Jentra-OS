# AC-320 budget and posted-actual variance candidate review — 2026-09-26

The development Supabase project `xpdoufauvrbdmxgngetv` is `ACTIVE_HEALTHY` on PostgreSQL 17.6.1. The ledger refresh at review end found **35 installed migrations**, now ending at `20260925181927_wave4_employee_foundation`, which arrived concurrently with this Wave 3 work. The candidate `20260925004000_wave3_budgets.sql`, the preceding Wave 3 statement/cash-flow candidates and their client RPCs are **not installed**; the budget and cash-flow tables were absent in a read-only `to_regclass` check. No migration was applied by this budget session. The Wave 4 checkout edits and installation are separate and were not staged or rewritten here.

The budget candidate adds versioned exact-decimal account plans, independent approval, immutable reasoned events, revision from an approved source and permission-scoped as-of variance snapshots from posted journal lines. Its branch report list and drill require the report's requesting branch. The gateway checks scoped receipts, exact amounts, arithmetic and frozen source identity. `/finance/budgets` has separate encrypted budget and variance slots; an uncertain command reuses its original envelope. Scope revocation clears viewed figures. The four light/dark 200% text previews were rendered and visually checked: `apps/jentra_desktop/test/goldens/budgets_light_200.png`, `budgets_dark_200.png`, `budget_variance_light_200.png`, `budget_variance_dark_200.png`. The workspace scrolls to the account and journal drill below the first viewport; no overflow remained after the branch selector correction.

| Check | Fresh result |
|---|---:|
| Strict combined procurement/finance candidate, transaction ending in `ROLLBACK` | 533/533 assertions |
| Strict inventory regression with budget candidate, rollback-only | 105/105 assertions |
| Strict receivables regression with budget candidate, rollback-only | `1..158`, no failures |
| Adjacent finance gateway tests | 35 passed |
| Adjacent finance desktop/recovery/golden tests | 64 passed |
| Focused platform and desktop analyzers | No issues |
| Current-source Windows release compile | Passed in 94.7 seconds; executable not launched |

The database assertions cover version and segregation of duties, idempotent replay, JSON-number rejection, unavailable cost-centre rejection, exact signed posted actuals, percentage, immutable frozen evidence after a backdated posting, filtered journal and account drill, cross-branch report isolation and direct-table denial. A review found two defects before the final strict run: JSON numeric amounts were initially accepted by a text extraction, and a report line filter used the journal line key. Both were corrected. Transition reasons are now stored in immutable budget events. The first run's expected row-order value was also corrected to the fixture's UUID order.

The 533-assertion procurement/finance rollback suite was rerun successfully after the concurrent 35th installed migration appeared in the development ledger.

Installed behavior and real multi-session contention/load are not established. The tests use one transaction and synthetic actors. The encrypted restart test recreates the controller and store against an in-memory encrypted database; it is **not** a Windows Credential Manager process-restart acceptance. Rendered widget previews and a Windows build do not constitute an authenticated native walkthrough or owner signoff. Stock-opening acceptance remains separate. No authentication setting or production system was changed.

AC-320 still lacks tax summaries based on posted tax-line provenance and effective-dated definitions, and the full inventory/GRNI/tax/cash reconciliation and operational report consolidation required by FR-375/377/382. Cost-centre/project budgets stay unavailable until governed dimensions and posting attribution exist. Large-data, cross-session and export coverage are separate requirements.

The development project's advisor refresh reported four `RLS Enabled No Policy` informational findings, ten `Unindexed foreign keys` informational findings and 292 `Unused index` informational findings. It also reported `Leaked Password Protection Disabled`; authentication was outside this task and was not changed. See the [RLS advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [foreign-key index advisor](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [unused-index advisor](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) and [password-protection guide](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
