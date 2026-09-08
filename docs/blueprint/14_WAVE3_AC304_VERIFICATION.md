# AC-304 sales orders: implementation and verification

Verified 2026-09-07 in `C:\Users\sheha\Desktop\Jentra OS`, on `main` at baseline
`b3d793bb9aab0293a874d75d785650784203b869`. AC-304 / FR-322–FR-325 is complete
within the approved synthetic-development boundary. Production was not accessed.
The approved Wave 3 specification passed strict validation at 100/100, with no
findings. No files were staged, committed or pushed.

## Delivered behavior

| Requirement | Implemented behavior and evidence |
| --- | --- |
| FR-322: quotation conversion | Accepted quotations open an explicit conversion form. Server conversion creates one order, preserves quotation/revision/line provenance and exact commercial snapshots, and returns the same result on replay. Converted quotations link to their resulting order through a bounded, scoped lookup. SQL and controller tests cover conversion and immutable retries. |
| FR-323: sales order workspace | Permission-gated register, literal search, status filters and bounded pagination; direct order drafts with exact commercial fields; promised date, governed warehouse and ship-to editing. Converted orders use a narrow fulfillment command that preserves source pricing and terms. Saved detail comes from one RLS-protected coherent snapshot. Line summaries show ordered, cancelled, allocated, delivered and invoiced base quantities. |
| FR-324: credit control | Server preview displays due balance, its overdue subset, other order exposure, this order and total exposure with currencies and timestamps. Confirmation re-evaluates under locks. Inactive customers and currency mismatch block confirmation. Over-limit confirmation enters credit hold unless a separately authorized user provides an override reason. Credit decision history retains exposure and override attribution. |
| FR-325: stock reservations | Online reservation reads scoped availability, checks per-line remaining demand and aggregate product quantities, and then rechecks authoritative limits on the server. Delivered quantities are excluded from remaining demand. Inactive warehouses/products are rejected. Cancellation releases reservations and records cancelled quantities. These commands do not change on-hand stock or create accounting/stock postings. |

Drafts and complete pending command envelopes use the existing authenticated
encryption infrastructure with a separate sales-order namespace scoped to actor,
tenant, legal entity and branch. Pending retries retain their original request ID,
timestamp, version and payload. Unknown outcomes remain recoverable. Stale versions
require explicit inspection and a choice between the current server version and
retaining reviewed local edits. Offline use, permission refresh/revocation,
context changes and double actions cannot silently send a new command.

The UI includes exact credit review, reasoned override, reservation validation,
credit decision/reservation history and source quotation details. Visual review
found and corrected lost reservation input after an error, and tests verify that
clearing a contact preserves current delivery edits without restoring the contact.

## Client verification

| Suite | Passing tests |
| --- | ---: |
| Domain, including five concurrently present receivables tests | 78 |
| Platform | 50 |
| Design system | 10 |
| Desktop controllers, navigation, widgets and goldens | 102 |
| **Current shared-worktree total** | **240** |

The AC-303 baseline plus AC-304 scope accounts for **235** tests: 73 domain, 50
platform, 10 design-system and 102 desktop tests. AC-304 adds 44 tests to the
191-test AC-303 baseline. The additional five domain tests belong to existing
concurrent AC-305–AC-308 work; they are not claimed as an AC-304 deliverable.

Coverage includes exact large decimals and currency separation, bounded/scoped
gateway queries, isolated encrypted order recovery, immutable pending retries,
credit hold/override, inventory-only permissions, stale preview rejection,
conversion, server conflicts, contact removal, offline sending denial and hiding
an open credit dialog during a permission refresh.

All seven new rendered goldens passed and were inspected: 1440-pixel light/dark
editor, 1024-pixel editor at 200% text, credit review, reservation validation,
explicit conflict comparison and quotation conversion. Existing quotation and
other golden baselines were preserved.

Whole-workspace analyzer: **no issues**, 19.0 seconds. Final non-mutating formatter:
**27 files, zero changes**. Whitespace checks pass. The final heuristic secret scan
examined 63 changed/untracked text files with no findings; full-history scanning
remains a CI release check. Git reports no modified preexisting migration files,
no tracked generated Windows plugin artifacts and no staged files.

Windows verification ran `flutter pub get --offline`, then
`flutter build windows --debug --no-pub` from `apps/jentra_desktop`. The debug build
passed in **107.3 seconds**. A fresh hidden startup at 11:13 UTC remained responsive
for 10 seconds, created a process-owned native window and returned a Flutter tree
containing `JentraApp` through the local Dart VM service. The launched process was
then closed. The build preceded the final whitespace-only formatter pass.

Logs, startup script/results and repository checks are in
[`docs/verification/ac304-orders`](../verification/ac304-orders/).

## Development database verification

Development project: **`xpdoufauvrbdmxgngetv`**. The live migration ledger, relevant
contracts and four function fingerprints were re-read before changing the server.
The starting ledger contained 28 migrations, latest `20260906153036`.

The single additive migration
`20260907044241_complete_sales_order_workspace.sql` adds the coherent order detail
view, authoritative credit preview and narrow fulfillment command, and hardens
confirmation, reservation and cancellation. All previous migrations remain
immutable. The applied ledger statement matches the local migration after line
ending normalization.

**384 strict pgTAP assertions passed**: the existing 356 assertions plus 28 order
workspace assertions. The candidate migration and all six baseline suites passed
inside rolled-back transactions before application; all 28 new assertions passed
again against the applied migration. Four changed/new PL/pgSQL functions were
checked with `plpgsql_check`, with zero findings. The lint extension was created
only inside a rolled-back transaction. See
[SQL evidence](../verification/ac304-orders/sql-verification.md).

Security advisors returned **zero findings**. The final read at
**2026-09-07 11:13:42 UTC** confirmed **29 migrations**, latest
`20260907044241`, **zero quotations and zero sales orders**. Synthetic SQL fixtures
were rolled back. Concurrent AC-305–AC-308 migration files were preserved and were
not applied by this slice.

## Release evidence still required

The rendered UI tests use synthetic repositories. The startup check uses an
unconfigured backend preview. Authenticated Windows workflows with governed
development users/data, actual Windows Credential Manager persistence across a
process restart, multi-session contention/load and a Windows release build remain
release checks. This report does not claim authenticated native end-to-end proof
or production readiness.

AC-303 and concurrent AC-305–AC-308 source changes remain intact. No subsequent
acceptance slice was implemented as part of this AC-304 change.
