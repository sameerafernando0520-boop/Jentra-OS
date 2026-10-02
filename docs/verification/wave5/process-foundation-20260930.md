# W5-01 process foundation checkpoint

Date: 2026-09-30, Asia/Colombo. Synthetic development only.
The owner approved the detailed contracts with “continue”. This checkpoint
covers the first domain implementation step, not full W5-01 acceptance.

## Implemented behavior

- Dependency-free domain scope, source projection, immutable manifest and
  digest-verification boundary; exact calculation uses existing `ExactDecimal`
  and BigInt microseconds.
- Strict UTC/calendar and numeric(20,6) validation; complete snapshot and
  source-selection checks; tenant/entity/branch and document-kind matching;
  10,000-row and 366-day bounds; serialized-size guards.
- Half-open entered cohort, inclusive recorded/completion cutoffs, independent
  excluded/open/invalid/completed counts and exact discrete P50/P90.
- Available zero versus missing duration evidence; explicit uncertified
  stage-dwell, throughput, handoff, productive-work and rework measures.
- Ordered canonical UTF-8 JSON for frozen projected values and source basis;
  independent SHA-256 adapter reuses existing platform cryptography. Hashes
  validate consistency; they do not authorize source access.
- Safe digest-verifier failure handling and read-only projections without actor,
  owner, private text or provider exception detail.

## Evidence

| Check | Result |
|---|---|
| Focused domain | 25/25 passed, including all 120 permutations of the five-value sample |
| Full domain package regression | 194/194 passed, zero skips/failures |
| Focused platform | 8/8 passed; empty/ASCII/binary and empty/nonempty Python-generated SHA-256 vectors; tampering and byte/size guards |
| New source/test analysis | Zero findings across all six new domain/platform files |
| Format | New files formatted; no existing source formatted |
| New calculation line coverage | 242/246, 98.37% |
| New calculation branch coverage | 77/81, 95.06%, actual branch collection enabled |
| Dependency changes | No domain/platform pubspec or root lockfile change |
| Installed development ledger | Before/after 37 migrations; last `20260929224939_wave4_private_hr`; no Wave 5 installation |

The checks used the available Dart 3.13.4/Flutter runtime and cached package
configuration. They are not pinned-CI or Windows-package build proof. Windows
sandbox signal-handler/telemetry restrictions required an approved sandbox
override for native test/analyzer execution. The initial ordinary `dart test`
startup was cancelled; subsequent domain tests used the cached test snapshot
directly. No package resolution was regenerated.

Commands, from the respective package/workspace directories:

```powershell
# Domain: cached runner, avoiding shared dependency resolution.
& 'C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe' `
  --packages='C:\Users\sheha\Desktop\Jentra OS\.dart_tool\package_config.json' `
  'C:\Users\sheha\Desktop\Jentra OS\.dart_tool\pub\bin\test\test.dart-3.13.4.snapshot' `
  --branch-coverage `
  --coverage-path='C:\Users\sheha\Desktop\Jentra OS\docs\verification\wave5\process-domain-coverage-20260930.lcov' `
  test/analytics/process_metrics_test.dart

# Full domain regression: same cached runner, --reporter json, no file filter.
# Platform: cached Flutter dependencies.
& 'C:\src\flutter\bin\flutter.bat' test --no-pub `
  test/analytics/process_metric_hasher_test.dart
```

Machine evidence:
[full domain results](domain-regression-20260930.jsonl),
[coverage](process-domain-coverage-20260930.lcov), and
[source/check summary](process-foundation-20260930.json).

## Acceptance coverage and remaining gates

| Criterion | Evidence / boundary |
|---|---|
| AC-551/552/553/555/558 | Domain cases pass; adapter/hash cases pass; server source retrieval remains unimplemented |
| AC-554 | Domain rejects substituted scope; actual source permission/own-event RLS/entitlement denial awaits server adapter and authenticated SQL checks |
| AC-556 | Native UI, stale-request clearing, encrypted filters, visual and actual restart evidence remain open |
| AC-557 | Only new slice-owned source/test files and own documents/evidence were changed |
| NFR-551/552 | Exact arithmetic and domain bounds verified; first definition has one group, below the 100-group ceiling; source paging/output must also be checked at the server boundary |
| NFR-553 | No authenticated permission or RLS claim from domain checks |
| NFR-554 | Deterministic domain checks and analysis pass; native views are still pending |

No SQL candidate, migration installation, native view, Windows release build,
live authenticated read, external worker, target-scale performance/contention,
or owner acceptance was completed for W5-01. The next step is the additive
bounded source provider with the stronger source-domain permission boundary.
Current process-event producers and Wave 3/4 shared composition remain unchanged.
