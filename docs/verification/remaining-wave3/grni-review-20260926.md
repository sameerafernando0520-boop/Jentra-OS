# Wave 3 GRNI control continuation — 2026-09-26

Development candidate evidence only. `main` stays at `6595d14` with an empty index.
Existing dirty work and concurrent Wave 4 calendar work are preserved. This
continuation did not stage, commit, push, install migrations, change production,
alter authentication or modify stock-opening acceptance source/data/runtime.

## Behavior and compatibility

Contract 39 and additive candidate `20260926007000_wave3_grni_control_reconciliation.sql`
extend the existing control APIs with `kind: GRNI`, `version: 1`. Original AR/AP
builders, allocation/reversal commands, exact decimals, immutable open items and
the atomic journal engine remain in use. New receipts freeze the original GRNI
account from their just-posted journal, avoiding a race with later setup changes.
Legacy receipts require an unambiguous original transaction/base credit basis.
Existing history is not backfilled or rewritten.

Credit-positive expected GRNI is receipt accrual minus dated matched-bill accrual,
unbilled receipt returns and receipt reversals. Bill-linked returns remain AP
effects. All expected money comes from independent immutable operational amounts;
the GL side includes every posted line on current, original and historical GRNI
accounts within the branch/cutoff. A different-rate bill consumes the original
receipt accrual rather than its new payable carrying value. At entity cent
precision, the synthetic USD receipt accrues `1.100000` base; its unbilled return
leaves `0.730000`, and the later matched bill exhausts it exactly.

Differences are grouped by account plus source type/ID. Two independent GL
adjustments can net to zero while remaining two visible mismatches. A missing
original GRNI credit remains attributable using a new receipt's frozen account.
Ambiguous legacy basis fails explicitly. Input/output/evidence limits abort
atomically; the private immutable report and existing command/audit/outbox machinery
preserve exact replay and frozen evidence after later backdated activity.

`/finance/controls` adds GRNI, receipt balances and bill-to-receipt journal attribution.
The gateway checks exact arithmetic, scope, report kind, account/source identity and
page progression. GRNI has no allocation reversal action. The controller now uses
the existing atomic encrypted confirmation primitive, persists confirmed identity
after disconnect or route closure, retains sealed retries on write failure, and
clears evidence after disconnect, permission/authentication/MFA denial or disposal.
An earlier access epoch cannot restore it after reconnect. Coordinated schema/client
installation is required because old clients only accept AR/AP kinds.

## Verification

| Check | Current result |
|---|---:|
| Full procurement/finance strict rollback composition | 671/671 assertions |
| Full receivables/reservation strict rollback composition | `1..169`, no failure |
| Full inventory strict rollback composition | 105/105 assertions |
| Nine affected finance gateway/codec/encrypted-store suites | 83 passed |
| Eight affected desktop finance/recovery/golden suites | 116 passed |
| Full platform and desktop analyzers | No issues |
| Isolated Windows release compilation | Passed in 307.2 seconds; no executable launched |

The SQL evidence is `grni-procurement-release-candidate-20260926.json`,
`grni-receivables-release-candidate-20260926.json` and
`grni-inventory-release-candidate-20260926.json`. Each final composition uses strict
`finish(true)` and final `rollback;`; every fixture and candidate DDL rolled back.
Tests cover actual scoped receipt, return, matched bill and reversal commands,
FX and cumulative entity rounding, original-account changes, exact replay/changed
replay refusal, frozen cutoffs, missing/extra GL, net-zero differences, 10,001-row
input rejection, 50-row paging, atomic late outbox failure, immutable history,
branch/permission/MFA denial and private-helper access. The established journal
minimum base precision guard remains enforced and leaves no partial journal.

Client tests cover GRNI retry across controller restart, account drill, revocation
and MFA expiry, late access/page responses after disconnect/reconnect, confirmation
after view disposal/offline response, and an injected SQLite confirmation failure
retaining the exact sealed envelope. Shared storage tests also cover encrypted
confirmed-state recovery after closing and reopening SQLite on disk. This is
separate from a Windows Credential Manager process restart.

Logs are `grni-platform-tests-20260926.log`, `grni-finance-client-tests-20260926.log`,
`grni-platform-analyze-20260926.log`, `grni-desktop-analyze-20260926.log` and
`grni-previews-tests-20260926.log`. Six 1024-pixel light/dark widget previews of
controls, receipts and bill-source drill were inspected at 200% text: amounts,
original source labels, account filtering and journal IDs remain readable without
overflow. Existing AR/AP and adjacent finance goldens pass. These are previews,
not authenticated native evidence.

The build snapshot is `build/wave3-grni-20260926`, populated with source,
manifests/assets and Windows runner files only, then resolved from cached dependencies
with `pub get --offline`. No environment or authentication stores were copied.
Compilation log: `grni-windows-build-20260926.log`. No acceptance executable is
replaced or launched.
Seven GRNI/gateway/store/main/router/navigation source hashes match the workspace
and isolated snapshot in `grni-build-source-hashes-20260926.json`. The executable
is under `build/wave3-grni-20260926/apps/jentra_desktop/build/windows/x64/runner/Release/`.

## Exact content

| Content | SHA-256 |
|---|---|
| `20260926007000_wave3_grni_control_reconciliation.sql` | `B1864D4AC1612EBFC54439873EF5C8AFAB790051CF399869F55BC8BA4FF67F02` |
| `build/grni-procurement.sql` | `6D9C7BDE5846AF914F5F49541E0804A1D799B6DFF4221C4E4382DC0C864E1D29` |
| `build/grni-receivables.sql` | `FBF2017032D3F8BB2229750241B64D4CC5A5765B278CA8DF6009B4CA02DC4A58` |
| `build/grni-inventory.sql` | `A070BA9D280ABBA7E375E53DABF1266BCDB1AFC690AC97410AEE532FCC3D46B5` |

Builder: `supabase/tests/build_grni_candidate.ps1 -Suite <suite>`, after the
unchanged ordered tax/finance/procurement chain. Archived iteration outputs are
diagnostic history and do not establish final passage or installation.

## Development state and remaining gates

Before/after project, ledger, catalog and advisor responses are the `grni-before-*`
and `grni-after-*` JSON records. Final observation: **2026-09-26 09:10:41 UTC**,
`xpdoufauvrbdmxgngetv` ACTIVE_HEALTHY on PostgreSQL 17.6.1.166. The ledger began at
35 entries and ends at **36**, including concurrent Wave 4 `20260926082441_wave4_calendar_versions`.
This Wave 3 continuation applied none. Procurement receipts, control/tax reports
and the GRNI basis helper are absent outside rollback. Allocation, residual,
journal-posting and open-period function MD5 values match the starting refresh.

Current security evidence reports seven RLS-enabled private Wave 4 tables with no
policies ([advisor reference](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy))
and the existing leaked-password warning ([reference](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)).
Performance reports ten unindexed foreign keys and 297 unused indexes. These are
recorded review items outside this GRNI change; no auth setting or concurrent
Wave 4 schema was changed here. Candidate index/permission checks and bounded
fixtures are not representative installed load or query-plan certification.

Wave 3 remains incomplete. Consolidated inventory/GRNI/cash close and operational
reports, governed dimensions, attributable bounded exports, broader landed/count/
disposition work, source/attachment/dashboard integration and broader security/
contention/load checks remain. Installation, authenticated native walkthrough,
Credential Manager process recovery and owner signoff are separate gates. The
[remaining status](../../development/remaining-wave3-status.md) records the next work.
