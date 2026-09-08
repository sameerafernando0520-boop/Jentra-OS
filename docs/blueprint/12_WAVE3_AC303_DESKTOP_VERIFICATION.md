# AC-303 Windows quotation workspace verification

Verified 2026-09-07 (Asia/Colombo), continuing `main` at
`b3d793bb9aab0293a874d75d785650784203b869`. Wave 3 remains approved for synthetic
development only. Production was not accessed or changed. Nothing was staged,
committed or pushed.

## Implemented desktop behavior

The Sales route now opens a capability-gated quotation register and workspace.
It supports literal document-number search, status filters, bounded pagination,
coherent saved details, a draft/revision editor, saved server totals, customer-facing
revision snapshots and approval decisions. History includes revision, actor,
reason/note, decision step, timestamp, currency and exact amounts.

The editor preserves customer/contact/opportunity, entity/branch context,
currency and governed FX rate, validity, payment/delivery terms, salesperson,
header discounts, notes, and product/service lines. Quantity, rational conversion,
unit price, discounts, tax references and all financial values remain decimal
strings or `BigInt`. Saving asks the server to calculate authoritative totals;
editing never changes the displayed saved totals. No cross-currency aggregation,
stock movement, credit commitment or reservation was introduced.

Submit, approve, reject, recall, accept, expire, cancel and revision controls use
the existing permission-checked commands and expected versions. Candidate actions
follow the pinned lifecycle when available; the server remains authoritative for
workflow configuration, live roles, segregation of duties and UTC validity. Reasons
are required by the relevant revision/decision controls. Accepted contents remain
read-only; cancellation still requires its configured server edge.

Reference pickers read only scoped `api.*` views in bounded pages. Customer/contact/
unit data retains its tenant-wide scope; entity resources retain their entity scope;
opportunity searches preserve branch and customer filters. Reference names are
current directory labels, while immutable IDs and saved financial/tax snapshots
remain the source of historical identity and amounts. The existing API has no
member directory or unit-conversion catalogue: new quotations default salesperson
to the signed-in actor, saved salesperson IDs are preserved read-only, and exact
conversion numerator/denominator are supplied explicitly for server validation.

## Draft and access protections

Raw incomplete edits and complete command envelopes are encrypted before network
transport. Recovery discovery is bounded and filters actor, tenant, legal entity
and branch before decryption. Uncertain results retain the original command ID,
idempotency key, timestamp, payload and expected version for explicit retry.
Definite refusals preserve editable fields. Confirmed success clears only its
matching pending request, including when the follow-up server read fails.

Conflicts display changed fields beside server values. The user can keep the
conflict unresolved, use the server version, or prepare local fields against the
specific compared version for review. Resolution never sends an automatic save.
A newer server change still causes the next save to conflict.

Offline writes, double submissions and stale asynchronous responses are guarded.
Actor/scope/access changes hide old workspace and dialog contents; loading or failed
permission refreshes also fail closed. Encryption failures keep the in-memory edits
visible and prevent switching quotations from silently losing them.

## Verification

| Dart/Flutter suite | Passed |
| --- | ---: |
| Framework-free domain | 68 |
| Platform adapters and encrypted persistence | 40 |
| Design system | 10 |
| Desktop controllers, widgets, navigation and goldens | 73 |
| **Client total** | **191** |

The new tests cover editing, lifecycle/refreshed versions, denial, bounded reference
reads, offline recovery, exact large prices/conversion, retry after controller
recreation, scope changes, failed permission refreshes, encryption failure,
explicit conflict choices and success followed by read failure. An additional
disk test closes and reopens SQLite, verifies quotation fields are absent from
plaintext file contents, then restores the exact encrypted draft and retry envelope.
The key-store dependency is controlled in these tests.

All six new rendered goldens were inspected: light/dark 1440-pixel editor,
1024-pixel layout with 200% text, revision/decision history, conflict comparison
and expanded line conversion. The review corrected clipped conversion labels and
helper text. Flutter labelled-control accessibility checks pass. Existing CRM,
dashboard, Setup Centre and design-system golden baselines remain unchanged.

Analyzer: no issues. Non-mutating formatter: **87 files, zero changes**.
Detailed logs are in `docs/verification/ac303-desktop/`.

The final Windows build ran `flutter pub get --offline`, then
`flutter build windows --debug --no-pub` from `apps/jentra_desktop`; it passed in
**40.6 seconds**. Git tracks zero generated Windows Flutter/plugin artifacts,
and all four generated-path ignore checks pass. Whitespace checks pass. A
heuristic scan of **177 source/test/documentation files** found zero private-key,
AWS/Supabase secret-token, credentialed PostgreSQL URL or JWT-shaped literals.
Gitleaks is unavailable locally; full-history secret scanning remains a CI gate.

A fresh launch of that executable with the backend unconfigured remained alive
and responsive for 10 seconds. A process-scoped Win32 check found the native
`jentra_desktop` window, and the local Dart VM service returned a Flutter widget
tree containing `JentraApp`. The process was then closed. The initial standard
`MainWindowHandle` assertion could not detect the intentionally hidden window;
the follow-up enumerated windows owned by the launched process and confirmed it.
This is a passing hidden-window startup smoke check, not a visual native-window
or authenticated quotation walkthrough. See `windows-launch.json` and
`windows-widget-tree.json` in the evidence directory.

### Development database

The development project `xpdoufauvrbdmxgngetv` and live view contracts were re-read.
All **356 SQL assertions** passed in six separate strict pgTAP transactions followed
by rollback: 30 foundation, 99 Wave 2, 50 operational foundation, 88 CRM, 46
lead-to-cash and 43 quotation workspace assertions. See
[SQL evidence](../verification/ac303-desktop/sql-verification.md).

The final read at 2026-09-06 21:41 UTC confirmed **28 migrations**, latest
`20260906153036`, and zero quotations, quotation lines, revisions and sales orders.
Fresh security advisors returned zero findings. No database objects, policies,
migrations or permanent fixtures changed in this desktop slice. All immutable
migrations still match the baseline. SQL functions were unchanged, so their prior
lint evidence was not presented as a new lint run.

## Remaining release evidence and next slice

The development database has no active quotation workflow or populated quotation
fixtures. Authenticated Windows use against governed development users/data and a
configured workflow remains a runtime check. The automated UI tests use synthetic
repositories; they are not evidence of a live authenticated end-to-end transaction.
Native Windows Credential Manager persistence across an actual process restart,
multi-session contention/load, release-build verification and the full Wave 3
release gate remain separate checks. No real-data or production readiness is claimed.

The next implementation slice is **AC-304 / FR-322–FR-325**: convert an accepted
quotation idempotently into one sales order with traced source lines; edit promised
dates, ship-to and fulfillment warehouse; expose server-calculated credit exposure,
blocked confirmation and permitted override reason; reserve/release only available
stock within remaining demand, without creating accounting or stock movements.
AC-304 implementation has not started in this change.
