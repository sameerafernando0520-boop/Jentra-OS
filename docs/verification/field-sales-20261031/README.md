# Field Sales candidate verification

Finalized 1 November 2026, Asia/Colombo. This verifies the
[candidate implementation](../../development/field-sales-governance-candidate-20261031.md)
in the existing workspace. No migration was installed, no application was
deployed, no email was sent, and no live acceptance is claimed.

| Check | Result | Evidence |
| --- | --- | --- |
| Isolated candidate SQL | 88 checks passed; all rollback assertions true | [Database report](postgres-result.json) |
| Runner target/transaction safety | 2 tests passed | [Runner log](runner-tests.log) |
| Sales app | 40 tests passed | [Sales log](sales-tests.log) |
| Scoped gateways and encrypted company recovery | 8 tests passed | [Platform log](platform-tests.log) |
| Company decision UI and access loss | 9 tests passed | [Company log](company-tests.log) |
| Scoped Dart analysis | No issues | [Analyzer log](analyzer.log) |
| Sales release web compilation, candidate flag enabled | Local build passed | [Build log](web-build.log) |

[Machine-readable verification](verification.json) records commands, source and
evidence hashes, the local artifact, and separate open gates. Hashing a workspace
input records the tested snapshot; it does not attribute unrelated existing
changes to this slice.

## Reproduce

The runner uses the pinned PGlite runtime already present under
`build/launch-validation-runtime`; it does not install packages or accept a
hosted target. From the workspace root:

```powershell
node supabase/candidates/run-field-sales-test.mjs --run-isolated
node --test supabase/candidates/tests/field_sales_runner.test.mjs
```

Run Flutter tests separately from each owning app/package, with the existing
workspace dependencies resolved:

```powershell
# apps/jentra_sales
flutter test --no-pub --concurrency=1

# packages/jentra_platform
flutter test --no-pub --concurrency=1 test/field_sales_gateway_test.dart test/field_sales_decision_store_test.dart

# apps/jentra_desktop
flutter test --no-pub --concurrency=1 test/field_company_review_test.dart

# apps/jentra_sales; compile only, no public key or deployment
flutter build web --no-pub --release --dart-define=FIELD_SALES_CANDIDATE_ENABLED=true --output=build/field-sales-governance-candidate
```

The recorded invocations use the installed SDK's Dart executable and
`flutter_tools.snapshot` directly, with analytics suppressed and version checks
disabled. The scoped analyzer's full input list is in `verification.json`.
Node's subprocess tests and the installed Flutter SDK required local execution
outside the process sandbox. The first sandboxed runner test stopped at
`spawn EPERM`; its rerun passed both tests.

## Evidence boundary

The SQL baseline is the exact repository migration prefix through
`20260910135507` plus workforce foundation `20260925181927` and private HR
`20260929224939`. Auth users, sessions and JWT claims, plus minimal Storage
catalogue tables, are simulated in PGlite 0.5.12 / PostgreSQL 18. This is not the
full current hosted schema or a Supabase Auth/Storage service test.

The suite tests populated legacy reads, broad-grant denial, command replay,
session loss, dated portfolio and price revisions, exact pricing, independent
MFA company approval, canonical draft/credit guards, and the actual linked
Employee bootstrap. It rolls back the candidate, modified functions and ACLs,
permissions/entitlements, every synthetic fixture/receipt, and the outer
baseline. Employee attendance, leave, payroll and file delivery acceptance are
not inferred from the bootstrap check.

Client tests cover actor/scope fencing, interrupted authentication, immutable
submission recovery, encrypted company decisions, draft/review invalidation,
responsive layouts and large text. The local candidate bundle contains no
configured public key and is compilation evidence. The default release keeps
the candidate flag disabled.

## Separate open gates

- **Email links:** authorized contacts; expiring, revocable and revision-bound
  challenges; explicit scanning-safe responses; replay/abuse controls; reviewed
  sender activation; quantity-bound responses for each partial delivery.
- **Company acceptance:** full-schema rehearsal with genuine pilot sessions and
  MFA, independent-session contention, real sign-out/revocation, credit-provider
  freshness, storage/recovery, normal company/Employee compatibility, device and
  accessibility/privacy checks, and representative/approver signoff.
- **Installation/distribution:** migration installation, sender activation,
  signing, web/APK distribution and live verification require a separately
  authorized rollout. This task performs none of them.
