# Company response-request workspace candidate verification

2 November 2026, Asia/Colombo. Covers the
[company workspace candidate](../../development/field-company-confirmation-candidate-20261102.md).
Evidence is limited to candidate source, isolated SQL, automated app behavior and
local compilation. No migration installation, deployment, sender activation,
hosted access or live/company acceptance is performed or claimed.

| Check | Result | Evidence |
| --- | --- | --- |
| Composed SQL candidates | 150 checks: 88 governance regressions, 46 email checks, 16 company workspace checks | [Database report](postgres-result.json), [run log](database.log) |
| Rollback | All 18 assertions true, including independent company extension rollback and original command ACL/body restoration | [Database report](postgres-result.json) |
| Isolated runner safety | 2 tests passed | [Runner log](runner-safety.log) |
| Desktop company, order, discount and navigation regressions with both flags | 58 tests passed | [Desktop log](desktop-tests.log) |
| Company recovery, email and governance platform regressions | 18 tests passed | [Platform log](platform-tests.log) |
| Navigation with default flags | 1 test passed; candidate destination hidden | [Navigation log](default-navigation-tests.log) |
| Scoped analyzer | No issues | [Analyzer log](analyze.log) |
| Formatting | 12 files, no changes | [Formatting log](format.log) |
| Desktop release web compilation with both candidate flags | Compiled successfully | [Build log](web-build.log); separate local output: `apps/jentra_desktop/build/field-company-confirmation-candidate` |

[Machine-readable verification](verification.json) binds the final source,
commands, evidence and complete local bundle hashes. Existing dirty workspace
inputs are recorded as a snapshot and are not attributed to this continuation.

The earlier [email recipient verification](../field-confirmation-20261102/README.md)
and [governance verification](../field-sales-20261031/README.md) remain records of
their original source snapshots. This continuation adds staff behavior and reruns
their SQL fixtures. Sales recipient application code is unchanged by this staff
slice; all 31 Sales library/test Dart files match the earlier record's hashes.
Its earlier full Sales suite and local bundle are recorded separately.
`phone-diagnostic.log` is intermediate pre-fix output; the final desktop suite
above verifies the repaired notice placement and supersedes that failed check.

## Reproduce

From the workspace root, with existing dependencies and the pinned local runtime:

```powershell
node supabase/candidates/run-field-company-test.mjs --run-isolated
node --test supabase/candidates/tests/field_company_runner.test.mjs
```

Run SDK jobs serially from each owning app/package:

```powershell
# apps/jentra_desktop
flutter test --no-pub --concurrency=1 --dart-define=FIELD_SALES_CANDIDATE_ENABLED=true --dart-define=FIELD_SALES_EMAIL_CONFIRMATION_ENABLED=true test/field_confirmation_company_screen_test.dart test/field_confirmation_company_controller_test.dart test/field_confirmation_navigation_test.dart test/field_company_review_test.dart test/sales_order_controller_test.dart test/sales_order_workspace_test.dart test/quotation_navigation_test.dart
flutter test --no-pub --concurrency=1 test/field_confirmation_navigation_test.dart

# packages/jentra_platform
flutter test --no-pub --concurrency=1 test/field_confirmation_company_test.dart test/field_confirmation_test.dart test/field_sales_gateway_test.dart test/field_sales_decision_store_test.dart

# apps/jentra_desktop; compile only
flutter build web --no-pub --release --dart-define=FIELD_SALES_CANDIDATE_ENABLED=true --dart-define=FIELD_SALES_EMAIL_CONFIRMATION_ENABLED=true --output=build/field-company-confirmation-candidate
```

The recorded SDK invocations use the installed Dart executable and Flutter tool
snapshot directly, suppress analytics and disable version checks. SDK cache and
test subprocess access required execution outside the process sandbox. No package
installation, database connection string or hosted target is used.

## Verified boundary

The isolated runner accepts only `--run-isolated`, validates candidate transaction
boundaries and pins the already-present PGlite 0.5.12 / PostgreSQL 18 runtime.
It composes the exact migration prefix through `20260910135507` plus workforce
foundation `20260925181927` and private HR `20260929224939`, then the governance,
email and company workspace candidates. It executes the prior 134 checks before
the new candidate restricts direct execution of the old company command, then
tests the new wrapper and its denial of that legacy bypass.

Auth, Storage, recipient addresses and provider acknowledgements are simulated.
The new extension rolls back first, restoring the original command body/ACL;
email and governance rollbacks restore functions, schema grants, permissions and
entitlements. The outer rollback removes all fixtures and the baseline. All 40
database source hashes were matched to the current source snapshot.

The new checks prove current MFA company authority, field/anonymous denial,
confirmation-only authority without broad order/discount grants, bounded safe
selectors, reviewed contact versions, exact-retry binding, current-response
protection and a single non-revoked challenge per request. The app checks cover
encrypted immutable pending bodies, expiry, explicit recovery/retry, failure
before dispatch, authorization loss, background privacy, unsaved-edit guarding,
paged fixed-length responses and phone/tablet/desktop views with 200% text.

Automated widgets and PGlite do not establish physical-device, mailbox, hosted
HTTP, genuine Supabase session or full PostgreSQL 17 compatibility. No configured
public client key is passed to the local build. Both flags and private transport
default to disabled. Sales and Employee remain separate apps; no Employee app
code is edited by this continuation.

## Separate remaining gates

- **Email-link activation:** actual worker/provider and sender/domain, hosted
  mailbox receipt and forwarding, HTTP/cache/scanner behavior, origin/log
  redaction and service-level abuse controls. A queued challenge establishes
  neither message transport nor delivery.
- **Delivery acknowledgement:** exact posted partial-delivery versions and
  received/refused/short quantities need their own verified recipient workflow.
- **Company progression:** reviewed credit/stock/order advancement remains
  separate from customer response evidence.
- **Company acceptance:** full current schema and existing-data rehearsal,
  genuine independent sessions/MFA, contention/revocation, ordinary company and
  Employee compatibility, device privacy/accessibility and pilot signoff.
- **Installation/distribution:** separately authorized migration installation,
  sender activation, signing/distribution, deployment and live verification.
