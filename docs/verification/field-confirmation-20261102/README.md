# Order email-confirmation candidate verification

2 November 2026, Asia/Colombo. Verifies the
[candidate source](../../development/field-order-email-confirmation-candidate-20261102.md).
No migration installation, deployment, email sending, hosted or company
acceptance is performed or claimed.

| Check | Result | Evidence |
| --- | --- | --- |
| Composed governance and email SQL candidates | 134 checks: 88 governance regressions, 46 confirmation checks | [Database report](postgres-result.json), [run log](postgres.log) |
| Rollback | All 16 assertions true, including independent email rollback, original functions/ACLs and private/API schema grants | [Database report](postgres-result.json) |
| Isolated runner target/transaction safety | 2 tests passed | [Runner log](runner-tests.log) |
| Full Sales app suite | 55 tests passed | [Sales log](sales-tests.log) |
| Recipient links/gateway and existing protected recovery | 12 tests passed | [Platform log](platform-tests.log) |
| Company review UI regression | 9 tests passed | [Company log](company-tests.log) |
| Scoped analyzer | No issues | [Analyzer log](analyzer.log) |
| Dart formatting | 13 files, no changes | [Formatting log](format.log) |
| Sales release web compilation with both candidate flags | Separate local bundle compiled | [Build log](web-build.log) |

[Machine-readable verification](verification.json) binds the final source,
commands, evidence and local bundle hashes. Earlier focused diagnostic logs are
intermediate results; the complete final suites above supersede them. Existing
dirty workspace inputs are hashed as a snapshot, not attributed to this slice.
The [earlier governance record](../field-sales-20261031/README.md) remains evidence
for its earlier source snapshot; this record covers the continuation.

## Reproduce

From the workspace root, using the existing pinned runtime and dependencies:

```powershell
node supabase/candidates/run-field-confirmation-test.mjs --run-isolated
node --test supabase/candidates/tests/field_confirmation_runner.test.mjs
```

Run Flutter commands separately from the indicated owning app/package:

```powershell
# apps/jentra_sales
flutter test --no-pub --concurrency=1

# packages/jentra_platform
flutter test --no-pub --concurrency=1 test/field_confirmation_test.dart test/field_sales_gateway_test.dart test/field_sales_decision_store_test.dart

# apps/jentra_desktop
flutter test --no-pub --concurrency=1 test/field_company_review_test.dart

# apps/jentra_sales; compile only
flutter build web --no-pub --release --dart-define=FIELD_SALES_CANDIDATE_ENABLED=true --dart-define=FIELD_SALES_EMAIL_CONFIRMATION_ENABLED=true --output=build/field-order-email-confirmation-candidate
```

The recorded invocations call the installed SDK's Dart executable and Flutter
tool snapshot directly, suppress analytics and disable version checks. Exact
arguments and scoped analyzer/format inputs are in `verification.json`. The SDK
and Node test subprocesses required execution outside the process sandbox.

## Verified boundary

The SQL runner uses the exact migration prefix through `20260910135507` plus
workforce foundation `20260925181927` and private HR `20260929224939`, then both
candidates. CRLF normalization is limited to baseline execution; hashes bind
unmodified source bytes. It uses PGlite 0.5.12 / PostgreSQL 18 and simulated
Auth/Storage, then removes the entire baseline. It accepts no hosted target or
database connection string and does not access a migration ledger.

Provider acknowledgements, email addresses and verification secrets are synthetic
fixtures in the rolled-back engine. The suite proves current-session/MFA company
authority, private contact/helper denial, an exact three-function anonymous API
surface, POST/scanner guards, hash-only secrets, original receipts, source/contact
revocation, five-attempt/five-issue limits, offer-proof binding, completed-response
immutability, and separate company/customer/delivery states. Customer acceptance
does not unlock canonical progression or create stock, invoice or payment effects.

App tests verify explicit actions without initial calls, strict raw-fragment
handling before URI normalization, actor changes, exact decimal/reference types,
structured addresses, original retry, background/late-response privacy and phone,
tablet and desktop layouts at 200% text. These are automated widget results,
not physical-device, hosted-mailbox or accessibility acceptance.

The local bundle contains no configured public key. Both new runtime paths and
private transport default to disabled. A default-build confirmation link must
scrub its fragment and show unavailable, without sign-in or synthetic success.
To accept a later release, rehearse the actual issue/mailbox/code/review/explicit
response and recovery flow on a separately authorized isolated full Supabase
stack, then approved pilot devices; do not enable sending to obtain these checks
from this candidate harness.

## Separate remaining gates

- **Email activation:** staff issuance UI and protected pending commands, real
  worker/provider, reviewed sender/domain, mailbox receipt and forwarding tests,
  hosted POST/GET/HEAD/cache/scanner behavior, log redaction and service abuse
  controls. No message transport is activated by the prepared dispatch seam.
- **Delivery acknowledgement:** posted partial-delivery/version and exact
  received/refused/short quantities with their own verified recipient responses.
- **Company progression:** reviewed company credit/stock/order progression remains
  unavailable even after a candidate customer response.
- **Company acceptance:** full current schema, genuine independent sessions/MFA,
  contention/revocation, ordinary company/Employee compatibility, device privacy
  and accessibility, and representative/approver/customer pilot signoff.
- **Installation/distribution:** separately authorized migration installation,
  sender activation, signing/distribution, deployment and live verification.
