# Accounting calculation and gateway checks — October 10, 2026 r2

The fresh, serialized checks passed **528 tests across 38 existing files**, with zero failures or skips. Independent review matched the actual expanded logs to every reported test identity and selected file; both reports have exit code 0, `stagePassed: true`, and null spawn/integrity errors.

| Controlled stage | Passed / failed / skipped | Exact files | Finished (UTC) | Record |
|---|---:|---:|---|---|
| Domain calculations | 122 / 0 / 0 | 16 | 2026-10-10 06:49:26.206 | [Domain result](accounting-checks-domain-20261010-r2.json) |
| Injected platform gateways and stores | 406 / 0 / 0 | 22 | 2026-10-10 06:50:28.913 | [Platform result](accounting-checks-platform-20261010-r2.json) |

The domain scope covers exact arithmetic and rounding, procurement and partial returns, landed-cost conservation, receivables, stock movement/count/opening and negative-stock rules, and dated cash scenarios. The platform scope covers injected journal, period/FX, reconciliation, statement/tax, bank, receivable, procurement and inventory contracts, access denial, recovery, and cash provider/store behavior. The [source manifest](accounting-checks-source-20261010-r2.json) lists the exact selected files and command arguments. These are bounded checks of the selected contracts; they do not establish complete accounting-system acceptance.

Both executions used file concurrency 1 in the existing matching warm tree. Their complete before/after audits equal the frozen manifest: 1,068 source inputs, 290 immutable evidence bindings, four pinned SDK files, and three package-resolution files. Independent postflight rehashed all those inputs, including both the current checkout and warm source trees. The matching base-source [full desktop run](golden-review-approvedAll-20261010-r2.json) passed 2,004 / 0 / 0 separately; the accounting checks were not executed in either native r3 identity-overlay tree. Hosted dependency contents were not independently audited file by file.

Exact SHA-256 bindings:

| Artifact | SHA-256 |
|---|---|
| Source manifest | `0590786a5d996879a2430007ff0779a26ac65ee1488e68e1e7ecf8454dfbc8f3` |
| Source-input digest | `04885214bf309928fd04acf4dcfd9a8c6ae2b97ba81484b3c371c2d309fd4405` |
| Domain result | `b1bf13aae6384a15e577f152e1cfccde878e27f9f1b7b7f1e071c5213c9f90d2` |
| [Domain log](accounting-checks-domain-20261010-r2.log) | `0382d8f9f67dfc305324e70fa4eb39c72c9fdd6edf1753a225343e3b033fc675` |
| Platform result | `f99850f03d7b34d98fc4219897223fe44a1cbea5714dc50a7bc0e42b32b397d4` |
| [Platform log](accounting-checks-platform-20261010-r2.log) | `1fed1e76472df94b03d4ef2705651ece4ede097d6c3a5df9d0361ae1289e7e2a` |

HTTP/gateway behavior is injected. Store fixtures use test-owned memory or unique temporary databases. These runs perform no actual user accounting transaction, installed SQL change, authenticated native operation, MFA ceremony, delivery, independent-session contention, target-scale load, or owner acceptance. They do not inspect or alter existing acceptance stores or sessions. Production and real billing remain excluded.

Actual native accounting posting, financial-statement generation, and acceptance remain pending. Follow the [end-user accounting test plan](end-user-accounting-test-plan-20261010-r2.md) with an authorized workspace after the relevant runtime and access gates are satisfied. The Preview package has unavailable operational accounting gateways; its shell and demonstration behavior cannot supply transaction evidence. This report adds evidence only and changes no requirement-matrix acceptance flag.
