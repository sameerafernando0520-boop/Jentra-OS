# Wave 5 independent runtime harness review — 2026-10-12

**Result: local source reviewed.** The finalized public coordinator, contract, CLI and controlled tests passed independent review. There are no unresolved material findings within this local source scope. This review does not approve a private provider, live preparation, installed behavior, genuine contention/load or owner acceptance.

The exact runtime owner decision is handled separately. This report is deliberately not a `wave5-runtime-harness-independent-preparation-review` and cannot satisfy the private-provider execution preparation guard.

Independent Node v24.11.0 run: **38/38 passed**, zero failures/skips/cancelled/todo; actual time 2026-10-12T09:22:25.481Z to 2026-10-12T09:22:27.586Z. Tool `c1645f`, child exit 0. All 18 before/after source bindings matched the preserved a3 record. Raw TAP, exact command and bindings are retained in the accompanying JSON. No network, private provider, SDK, native, SQL/Auth write or credential/store/session access occurred.

Five review findings were corrected and verified:

- Actual transport start determines warmup/measurement phase, enforces the deadline and counts only actual sends.
- A fixed public code allowlist prevents provider exception detail reaching evidence.
- Canonical review and source-bound plan are revalidated before provider access; the factory and live entry receive copied, frozen contexts.
- The parsed independent preparation review must carry the required verdict and exact runtime/harness/plan/provider/operation bindings.
- Actual dispatch lag includes evidence and provider queues; rate-bounded actual warmup and exact sample/send counts prevent the previously observed catch-up false pass.

The original held-warmup probe `f4477b` remains a failed historical review probe: 0 warmup sends, 7,200 measurement sends, 2,000 sessions/500 scopes and falsely passing gate. The final repeated probe fails capacity, records 60,000ms actual dispatch lag, retains 0 warmup and 21 actual sends, and leaves the gate false. The prior 37-test a2 run and r5 review remain unmodified; their passing local tests did not rule out this defect.

The source review also confirms the exact 500-scope/2,000-session distribution, genuine Auth/session-row/MFA requirements, separate trusted worker authority, barriers and actual transport overlap, committed effects and zero-effect denials. Lease claim alone creates one attempt with zero usage reservations. Load retains 70/20/10, 60s warmup plus 300s measurement, strict p95 and reviewed caps. Database row counters are separate from actual remote-send observation. Unsupported excessive-source/group/output fixtures remain blocked under the reviewed seed caps.

| Final bound input | SHA-256 |
| --- | --- |
| tools/wave5/runtime_contract.mjs | 2f518fdffa0f8b6e947118a259f10fbfb20b41e7fcc7e6ef3146461030f8747f |
| tools/wave5/runtime_coordinator.mjs | e41ab3830523f030f7a3cf2bb42ebabf24387697afc521b1d94458ec30dbf9be |
| tools/wave5/run_runtime_verification.mjs | 143f460b88c1e1dba4a06b7ed869fb5de46e6eff77421ebf8d0aee15efb74b20 |
| tools/wave5/runtime_coordinator.test.mjs | d5b8aba2a49673e540a87fd414be38419c65535902c3eff572afd005733b81c8 |
| tools/wave5/PRIVATE_PROVIDER_CONTRACT.md | 53b691012312db8d0c6b634c8b8cc21690cac73e80a66b286dd4ab97b1c0ec30 |
| tools/wave5/verify_local_harness.mjs | db5b4c163c549b32e6e831483fdb4f6c07c8158c50e7ef3565000d04f48e9834 |

Runtime bundle: `db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b`; immutable runtime JSON SHA-256 `b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3`.

Primary a3 evidence: JSON `d2d83cefad2a8e535d7850a57b84c13749e7b494f79964d7a01d3c329caff2db`, TAP `94670bf3441fbd8c9b1d09c623d7fcc21a1cf4081e66f13255307a14f78e1bbc`. Independent raw TAP hash: `176d24398499a947df0a56f6a176fedb2c288a1db4c4169c88a9bf6ec567512c`.

A genuine private provider and concrete fixture/restoration/query plan still require independent review and actual Auth/MFA, installed-contract, capacity, population and transport observations. Local fixtures verify orchestration, not those claims. Installed SQL, authenticated native, actual delivery/model, full keyboard, real contention/load and owner acceptance remain separate gates.

[Structured evidence and raw local output](runtime-harness-peer-review-20261012-r5.json)
