# AC-317 development review — 2026-09-24

Solo review of contract 33, the additive candidate, authenticated gateway, desktop
workspace, encrypted recovery and rollback/client fixtures. Candidate development
is complete within the documented branch/report bounds. Installation and native
acceptance are not claimed; the stock-opening acceptance boundary is unchanged.

## Corrections made

- **Historical control attribution:** current mappings cannot relocate old open
  items. The source journal supplies a unique signed account basis; unsupported or
  ambiguous history fails explicitly. Settlement across controls posts an exact
  control transfer. AR and AP controls use opposite GL sign conventions.
- **AR correction completeness:** a linked reasoned reversal restores immutable
  allocation amounts and reverses the actual original FX, discount and write-off
  journal. It also refreshes AR credit exposure. Reallocation apportions remaining
  carrying values, preserving final cents after an earlier allocation is reversed.
- **Chronology and atomicity:** AR cannot allocate before later reversal history.
  Open-period and deterministic customer/item locks reuse existing primitives.
  A late outbox failure leaves neither reversal history nor an extra journal.
  Real simultaneous contention is still unverified.
- **Report truth:** all control GL lines are included, including unmatched source
  commands. Zero aggregate difference cannot hide offsetting command differences.
  The stable snapshot, immutable evidence, explicit stream/output/byte limits and
  bounded pages prevent mixed cutoffs or silent truncation. Source filtering includes
  either account side of an allocation. Saved evidence survives later backdating.
- **Recovery and permissions:** report and correction requests use independent
  encrypted slots, scope isolation and sealed retries. A confirmed request is cleared
  before optional refresh. Explicit access denial clears displayed evidence; offline
  restart does not disclose restored source descriptions. Refreshing access first
  preserves unsubmitted inputs. AR/AP reversal permissions are separate from report
  access and from each other; server checks remain authoritative.
- **Client confirmation:** gateway rejects numeric financial JSON, scope/kind/date
  mismatch, inconsistent account sums and malformed receipts. Such mutation responses
  remain uncertain instead of creating a replacement command.

## Fresh evidence

| Check | Result |
|---|---|
| Procurement, valuation and finance SQL | 365 passing rollback assertions |
| AR and reservation SQL | 158 passing strict rollback assertions |
| Inventory SQL | 105 passing rollback assertions |
| Desktop controllers, recovery, widgets and goldens | 63 pass, including 14 AC-317 checks |
| Gateways and shared encrypted storage | 77 pass, including 8 AC-317 checks |
| Exact receivables domain | 5 pass |
| Focused app and platform analysis | No issues |
| Isolated Windows release | Passed in 74.4 seconds, not launched |
| Installed state after tests | 34 migrations; AC-317 table/RPC absent |

SQL tests include cross-control settlement after remapping, exact one-micro-unit
differences, full/partial allocations, out-of-order restored cents, write-off/discount
and FX reversal, unchanged earlier-date evidence, duplicate reversal, reason and
permission denial, hard-locked period, late failure/retry, immutable evidence, saved
report replay, scoped reads, MFA, private table denial and 50-row journal pagination.
The AR suite ends in `finish(true)`; procurement/inventory results were checked for
`not ok` and returned their complete plans. All candidate DDL and synthetic rows
ended in rollback. The SQL builder emits only and cannot install anything.

Client tests prove actor/branch isolation, identical sealed envelopes after controller
restart, hidden offline source evidence, permission-revocation clearing, AR/AP routing,
invalid input rejection, exact strings beyond binary precision and confirmation
cancellation. Shared SQLite tests use synthetic keys; they do not prove Windows
Credential Manager recovery. Light/dark 200% report renders were inspected and the
minimum-height reversal confirmation is reachable. No app login or MFA was automated.

Intermediate verification errors were corrected: an invalid test matcher name; a
fixture attempting open-to-hard-lock directly; a formatting tool applying stale
offsets during an overlapping edit; and large shell-output truncation causing invalid
SQL transfer. The controller was repaired and retested. Final SQL transfer used
bounded JSON chunks with exact character counts where required. No failed run is
counted as passing evidence. An initial build-log path error prevented execution;
the corrected absolute in-workspace log records the successful build.

## Boundary and follow-up

Twenty candidate migrations are unapplied. Transaction rollback is the verification
rollback path; no destructive down migration is run against immutable financial
history. Any future installed correction must preserve that history and be separately
coordinated. No stock-opening, authentication, Git history or production changes.

Before installation, review supported source-journal attribution and account metadata,
full permission/role rollout, historical retired mappings, configuration mutation races
and real contention. Reports currently cover one branch, at most 10,000 records per
input stream, 50 controls and 16 MiB of evidence; broader consolidation/export and
large-data p95/load are unverified. Bank matching, FX revaluation, period close,
financial reporting/budgets and remaining Wave 3 work are separate slices. Native
walkthrough, real encrypted restart, installation and owner signoff remain open.
