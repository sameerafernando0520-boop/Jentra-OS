# Wave 3 consolidated close review and governed exports — 2026-09-26

Development candidate evidence only. This continuation started from `main` at
`b51eec0dce3a73236f3460325394a4dc19e7a2ce` with an empty index. All earlier
Wave 3 work and concurrent Wave 4 changes are preserved. No staging, commit,
push, migration installation, production action, authentication change, stock-opening
acceptance record/sequence change or native application launch occurred.

## Implemented behavior

Contract 43 and additive candidate `20260926008000` consolidate AR, AP, GRNI,
inventory, transit and configured bank/cash controls at one entity-wide posting
cutoff. Every entity branch, including retired branches with historical movements,
requires finance, control, stock and cost access. Independent source values,
original/historical asset and GRNI accounts, command IDs, journals and receipt
links remain attributable. The dated bank bridge uses immutable match/reversal
history. Cash-register balances explicitly have no physical-count evidence.

Hard close rechecks live GRNI, inventory and bank evidence alongside existing
AR/AP, tax and cash-flow exceptions. A saved review cannot waive later backdating
or unavailable configuration. Bounds fail atomically rather than truncating.
The private read graph uses one statement snapshot; no shared posting, allocation,
residual or journal helper was changed. The desktop `/finance/close-review`
preserves encrypted uncertain requests and confirmed identity after disconnect or
route disposal. Permission/MFA changes and stale responses clear evidence.

Contract 44 and additive candidate `20260926009000` reuse six existing saved
report types: financial statements, AR/AP/GRNI controls, inventory valuation,
tax reviews, budget variance and close reviews. Current source access and
`finance.reports.export` are checked before every preview and command replay.
The complete filtered frozen section is bounded to 10,000 rows and 8 MiB, hashed
as canonical server JSON and encoded as exact CSV or string-only XLSX. Scope,
cutoff, version, source, filters, actor and file hash remain attributable even for
an empty report. CSV formula-like labels are neutralized; amount columns must be
imported as text. Invalid cells and excessive rows/columns/cells/file size fail.

Export registration uses the existing immutable command/receipt/audit/outbox and
`core.export_jobs` engine. Server metadata explicitly records
`generated_local_delivery_unconfirmed`. Cancellation sends no command;
uncertain registration retries the sealed envelope. Atomic encrypted registration
precedes optional native delivery. File-write failure retains the same job and
byte hash; fresh access and identical bytes are required for delivery retry.

## Verification

| Check | Result |
|---|---:|
| Procurement/finance composition, strict rollback | 735/735 assertions |
| Inventory composition, strict rollback | 105/105 assertions |
| Receivables/reservations composition, strict rollback | 169/169 assertions |
| Eleven affected platform/gateway/codec/store suites | 109 passed |
| Ten affected desktop/recovery/widget suites | 148 passed |
| Full platform and desktop analyzers | No issues |
| Light/dark close controls, source drill and export renders | Six inspected at 200% text |
| Isolated Windows compilation | Passed in 268.6 seconds without launch |

SQL evidence is `export-procurement-release-candidate-20260926.json`,
`export-inventory-release-candidate-20260926.json` and
`export-receivables-release-candidate-20260926.json`. Each builder ends in
strict `finish(true)` and `rollback;`. Tests exercise original source arithmetic,
historical accounts, all-branch/cost denial and replay checks, frozen reports,
late outbox rollback, bank reversal cutoff, hard-close failure, bounded asset
basis and all six export source permission paths. Excess export rows cannot
create partial jobs. Diagnostic iterations and a transport retry remain archived;
only the named final results establish passage.

Client evidence is in `close-export-platform-tests-20260926.log`,
`close-export-desktop-tests-20260926.log` and the corresponding analyzer logs.
Tests cover failed encrypted confirmation, disposal/offline acknowledgement,
scope/MFA revocation, stale reads, exact strings above binary precision, complete
export filters, cancelled save selection, uncertain registration, file-write
failure, byte mismatch refusal and recovery without duplicate jobs. File dialogs,
writes and process lifecycle use test doubles; this is not native acceptance.

The shorter isolated build copy is `build/w3ce26`. It contains source,
manifests, assets and Windows runner files, with cached offline dependency
resolution. No environment, authentication or acceptance stores were copied.
The first longer-path build failed with MSBuild MSB6003 in a plugin tracking path;
its log is diagnostic. The shorter compilation log is
`close-export-short-windows-build-20260926.log`. Eighteen relevant source
hashes match the workspace and shorter snapshot in
`close-export-build-source-hashes-20260926.json`.

## Development state

At 2026-09-26 17:36:30 UTC, `xpdoufauvrbdmxgngetv` remains ACTIVE_HEALTHY,
PostgreSQL 17.6.1.166, with 36 installed migrations through concurrent Wave 4
`20260926082441_wave4_calendar_versions`. These Wave 3 candidates are absent
outside rollback. All four installed allocation/journal/residual/open-period MD5
values match the starting refresh. Before/after raw health, ledger, catalog,
fingerprint and advisor records are preserved.

The advisors retain seven private Wave 4 RLS tables without policies
([advisor reference](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)),
the existing leaked-password warning
([reference](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)),
and ten unindexed foreign keys / 297 unused indexes. These remain review items;
no unrelated Wave 4 schema or authentication setting was changed here.

Wave 3 remains incomplete. Governed dimensions, remaining operational reporting,
broader landed allocation/correction, oversized counts/disposition,
attachments/source navigation/dashboard integration and broader security,
contention/load evidence remain development work. Installation, authenticated
native walkthrough, Credential Manager process restart and owner signoff remain
separate acceptance gates.
