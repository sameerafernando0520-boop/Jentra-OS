# Native stock-opening workspace: Wave 3

Date: 2026-09-11. Scope: the native implementation of the approved
[stock-opening contract](17_WAVE3_STOCK_OPENING_CONTRACT.md), under FR-301–311,
FR-350–356, FR-358, FR-360 and AC-313–315. Synthetic development only.

## Delivered behavior

`/inventory` now opens the stock-opening register with status filtering and
bounded pagination. The sidebar and direct route require cost visibility plus
opening-management or approval access. Controllers and reference dialogs are
invalidated when the active actor, business scope or permissions change.

The editor selects active scoped warehouses, stocked products and posting equity
accounts through paginated lookups. Quantities and line values remain exact
decimal strings; totals use `ExactDecimal`/`BigInt`. Lot codes, optional lot dates
and individual serial codes are supported. Local totals are previews; command
responses provide the authoritative saved snapshot and posting references.

Submit, approve/reject, recall/cancel and post call the three named opening RPCs
explicitly. UI actions respect state, capability and configured lifecycle paths.
The creator, latest editor and submitter cannot approve their own opening.
The database remains authoritative for approval roles/steps, MFA, precision,
periods, mappings, stock eligibility and atomic stock/journal posting.

Local work uses the existing encrypted repository in a separate
`inventory.stock_opening` namespace scoped to actor, tenant, legal entity and
branch. Field saves are serialized before dispatch. Storage failures retain the
editor and prevent route exit until saving succeeds. Unknown outcomes preserve
the original command identity, timestamp, payload and expected version for an
explicit retry. Confirmed SQL rejection releases the pending request; conflicts
require explicit discard/reload. Lifecycle recovery remains read-only whether
opened from the register or the recovery chooser.

## Source and test evidence

New source is under `features/stock_opening` in the desktop app, the
`jentra_stock_opening.dart` domain entry point, and the
`jentra_stock_opening_platform.dart` platform entry point. Shared integration is
limited to the gateway provider, `/inventory` route and navigation permission.

There are **38 new passing tests**: 3 domain, 15 platform, 11 controller and
9 workspace tests. They cover exact values, draft scope/isolation, durable
envelope replay, malformed command replies, definite versus uncertain failure,
bounded/scoped reference queries, duplicate clicks, self-approval, offline guards,
storage failure, version conflicts, rapid local edits, access loss, picker
invalidation and 200% text scaling.

Across the package suites and affected-test reruns, **313 unique tests pass**:

| Package | Passing tests | Evidence |
| --- | ---: | --- |
| Domain | 81 | `native-domain-tests.log` |
| Platform | 81 | `native-platform-tests.log` |
| Design system | 10 | `native-design-tests.log` |
| Desktop | 141 | Full-suite baseline plus the affected-file reruns below |

The initial full desktop run passed 126 tests and failed 14 old sidebar goldens.
Pixel comparisons showed only the newly permission-gated Inventory destination
and consequent sidebar row positions changed. All 14 baselines were reviewed
and updated; the two affected test files then passed all 32 tests without golden
updates. Content areas were unchanged. The comparison bounds are recorded in
`native-sidebar-differences.json`; generated failure images were removed afterward.

A final regression test reproduced register-based lifecycle recovery incorrectly
opening an edit form. Both recovery entry points now share the same operation
check. The 11 controller and 9 workspace tests passed again after this correction,
including all six new goldens. The initial full run, red regression and successful
reruns are retained as distinct logs rather than replacing the failed evidence.

The full analyzer reports **No issues found** after the recovery correction.
Formatting checks report **18 files, 0 changed**; `git diff --check` is clean.
Logs and the machine-readable summary are in
[stock-opening verification](../verification/stock-opening/native-verification.json).

## Rendered review

Fresh Flutter renders were inspected for the register, light and dark editors,
1024-pixel editor at 200% text scale, posted detail and pending recovery. The
enlarged editor scrolls vertically without overflow. The six images are synthetic
widget-test evidence, not screenshots of an authenticated database session.

Preview: [light editor](../../apps/jentra_desktop/test/goldens/stock_opening_editor_light.png),
[dark editor](../../apps/jentra_desktop/test/goldens/stock_opening_editor_dark.png),
[200% text](../../apps/jentra_desktop/test/goldens/stock_opening_editor_text200.png).

## Windows artifact and development state

The final Windows release built successfully in 88.4 seconds from ordinary
`lib/main.dart` without backend defines. A ten-second native startup observation
confirmed a responsive process with three process-owned windows; the probe then
closed its own process. See `native-windows-build.log` and
`native-release-smoke.json` for the executable hash and recorded observation.
This startup check does not exercise signed-in stock opening or prove
process-kill recovery for openings.

A fresh read-only development query confirmed 32 migrations, latest
`20260910201410`, zero users and zero tenants. All three opening RPC definition
MD5 values still match the prior installed evidence. The immutable migration's
SHA-256 remains
`063f8a8b91c502730ed51e52f014faf080fbe8b497c611e55e0f8054de44a3d0`.
The prior database slice passed 549 assertions; those SQL suites were not rerun
for this native-only change. No database mutation or production action occurred.

## Remaining acceptance

**Later acceptance preflight, 2026-09-11:** the development-connected release is
now built and open. Two synthetic accounts exist, and native first-workspace
onboarding was observed after the user signed in. The user subsequently created
the workspace and completed MFA; both are confirmed by read-only database
counts. Governed setup and authenticated transaction acceptance remain pending.
See the current [acceptance start record](../verification/stock-opening/acceptance-start.md)
and [control repair](../verification/stock-opening/auth-controls-verification.md).
The earlier ordinary-release evidence above remains valid for its recorded hash.

At the original native-verification checkpoint, two user-managed synthetic
accounts, MFA and governed business masters were still needed. For a subsequent
development rebuild, from `apps/jentra_desktop`, run `flutter build windows --release --no-pub
--dart-define-from-file=../../.env.acceptance.json`.

Configure tenant/entity/branch/warehouse, stocked products and base units,
inventory and posting equity accounts, an open period, opening/journal sequences
and the independent approval workflow. Then exercise native draft save, submit,
independent approval, post, identical replay and stock/journal reconciliation,
and continue the existing sales-to-receivables walkthrough. Real credentials and
MFA codes stay outside chat. Final authenticated acceptance and user signoff
remain pending. Existing unrelated source changes are preserved; no files were
staged, committed or pushed.
