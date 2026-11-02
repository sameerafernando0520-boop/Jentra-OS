# AI and integrations evidence — 31 October 2026

The [development runbook](../../development/ai-integrations-hosted-verification-20261031.md)
records the implementation and remaining live gates. This directory contains
source-bound local checks; the separate public probe directories contain actual
credential-free HTTPS observations.

| Check | Result / artifact | Limit |
| --- | --- | --- |
| Ordinary worker deployment regression | `regression-before.log`: ten failures reproduced | Original source before correction |
| Worker suite | `worker-suite-isolated-final.log`: 287 pass; `worker-suite-in-process.log`: same 287 pass | Controlled transports; not hosted delivery/model usage |
| Read-only accounting SQL | `accounting-postgres-result.json`: nine checks pass; `accounting-postgres-final.log` | Exact query in isolated PGlite with minimal synthetic tables |
| Edge entrypoints | `deno-check-final.log`: runtime and receiver checked | Import/type check, not deployment |
| Backend access | `backend-access.json`: renewed authentication required | Sanitized result of current read-only CLI project list |
| Actual hosted responses | [Latest four-response report](../ai-integrations/2026-10-30T23-21-56-155Z-e73f5427-94b5-4fd7-9999-d4c953e1bb07/report.json) | Three unsigned denials; model 503; no authenticated positive result |

`worker-suite.log` preserves the four initial failures caused by older synthetic
test keys. `worker-suite-final.log` preserves the 286-test checkpoint before the
additional opaque-key receiver test. `worker-suite-reviewed.log` preserves the
sandbox's test-process spawn failures; in-process and normal-isolation reruns
are separately recorded. `probe-before.log` and `accounting-before.log` preserve
the initial missing-module test runs. `accounting-postgres.log` preserves the
synthetic preparation error from attempting two prepared statements in one call;
the corrected preparation uses separate statements and retains the same query.

The recorded local query verification used the existing pinned build-only runtime:

```powershell
node docs/verification/ai-integrations-20261031/verify-accounting-postgres.mjs
```

The fixed evidence verifier refuses to overwrite its existing result JSON. For a new run, use
a separately reviewed new evidence destination; preserve the current record.
The engine test does not execute Supabase migrations, install a hosted schema,
exercise RLS/Auth, consume model tokens or establish external delivery.

The Standards review agent completed focused tests and reported no confirmed
finding before its usage limit prevented final review. The root reviewed the
scoped source and evidence locally; this is not a completed independent
Standards verdict. The Spec review status is recorded in `verification.json`.
No new owner acceptance is awarded.
