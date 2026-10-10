# Prepared accounting calculation and gateway checks — October 10, 2026

The two stages are **prepared and unrun**. Their source record binds all 1068 current and warm-tree inputs after the owner-approved 83 PNG changes, the actual 2004/0/0 desktop result, immutable approval/recovery evidence, four cached SDK tool hashes and the warm package-resolution files. There are no guessed passing counts for accounting. Existing fixture tests supply the checks; no new Dart tests, external template, application source edit, account operation or owner acceptance was created.

| Stage | Existing test files | Meaningful checks |
| --- | ---: | --- |
| Domain | 16 | Exact six-place money, rational tax/units and discount allocation; purchase estimates and complete bid comparison; accepted/rejected receipt quantities; partial returns; landed-value conservation; stock quantity/deficit corrections; immutable dated cash and scenario overrides. |
| Platform | 22 | Journal/FX/control/statement/tax arithmetic and immutable lineage; AR/AP allocations and reversals; stock and landed valuation; scope/version/permission and malformed receipt rejection; encrypted command recovery and cash-date provider completeness. |

The explicit file paths, hashes, commands and rationale are in [the new source manifest](accounting-checks-source-20261010-r2.json). Arithmetic examples read from these existing fixtures include 3 × 0.333333 = 0.999999; separate returned net/tax rounding totals of 147.66 + 147.64 = 295.30; all 200 partial returns exhausting 99999999999999.99 exactly; one six-place landed allocation leg changed by 0.000001 being rejected; and the cash sequence 1.000000 → -0.000001 with currency/provider/date errors rejected. Iterations within a test are never counted as separately executed tests.

Default check and independent static review passed. The pure log parser validated the genuine 2004-test/138-file log and ten acceptance/rejection controls, including duplicate identity, missing file, wrong scope, skip and nonzero-exit cases. The initial read-only preflight rejected an array-order discrepancy; the guard now requires the exact four unique dependency members as a set and still verifies all 1068 file hashes. [Static evidence](accounting-checks-runner-static-review-20261010-r2.json) preserves that diagnostic. No SDK job was launched by this preparation.

Root runs the following **sequentially after its native build queue**. The immutable source manifest already exists; do not rerun freeze. Each stage reserves its own result journal and log before SDK execution, audits source/tool/resolution/runner bytes before and after, and requires zero skips/failures, unique executed identities matching the actual pass count, and every selected file. On failure, retain the log/result and prepare a new revision rather than overwriting or rerunning an immutable stage.

```powershell
& 'C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' scripts/wave5/run_accounting_checks_20261010_r2.mjs check
& 'C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' scripts/wave5/run_accounting_checks_20261010_r2.mjs domain
& 'C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe' scripts/wave5/run_accounting_checks_20261010_r2.mjs platform
```

Fresh outputs will be accounting-checks-domain-20261010-r2.{json,log} and accounting-checks-platform-20261010-r2.{json,log}. Counts and per-file identities must come from those actual logs. SDK file concurrency is one in both stages.

The HTTP clients receive injected responses and fake fixture identities; stores use in-memory or uniquely owned temporary databases and test key stores. These checks do not touch an acceptance store or establish installed journal posting, a genuine signed-in/MFA actor, real financial transaction/delivery, authenticated native keyboard, independent-session contention, target-scale load or whole-system owner signoff. Hosted dependency resolution is locked and hashed; hosted library files are not independently byte-audited. Production and real billing remain excluded.

Runner SHA-256: f80f73fde4a56717a28fce7cb2624a2b23590bbaa74f906a8fe07acc2427eaf0. Source-manifest SHA-256: 0590786a5d996879a2430007ff0779a26ac65ee1488e68e1e7ecf8454dfbc8f3.
