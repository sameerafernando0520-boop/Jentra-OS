# Free AI candidate evidence — 2 November 2026

This directory records source-only verification and a read-only hosted
configuration preflight. **It does not establish activated Cloudflare AI,
hosted model usage, or external delivery acceptance.**

| Evidence | Result and boundary |
| --- | --- |
| `worker-suite-final.log` | 303 passed, 0 failed/skipped/cancelled; local worker tests only. |
| `deno-check-after-review.log` | Normal runtime and receiver entrypoints passed Deno source checks. |
| `candidate-preparation-ready.log` | 17-input runtime package prepared and checked in its staging directory; not deployed. |
| `hosted-configuration-before-activation.json` | Project healthy, runtime/receiver V7, both Cloudflare secret names absent, observed 2026-11-01T19:54:57.967Z; no secret values read. |
| `candidate-integrity.json` | Independent hash comparison between the frozen candidate, its manifest and current source; no external calls. |
| `verification.json` | Frozen source, test and evidence hashes with explicit incomplete hosted gates. |

The final candidate is at:

`build/wave5-cloudflare-free-20261102/2026-11-01T19-57-55.413Z`

The SHA-256 of its `candidate.json` is
`0fc36fbd03cad60e73e1681249b7b24d58cd2e815cc8808bbbe933b30ce8dc6a`.
It contains no secret values and has not been deployed.

Earlier failing logs are retained to show the development and review
regressions. In particular, `review-regressions-before.log` reproduces the
provider-identity and early-budget gaps; `review-regressions-final.log` covers
their fixes. `worker-suite-final.log` additionally includes the corrected
stored-request error fixture matching the actual sanitized RPC behavior.
Earlier preparation logs failed before a candidate was ready; only
`candidate-preparation-ready.log` is the successful staged result.

Two independent read-only code reviews were completed. No unresolved concrete
code defect remained in their reviewed scope. Account-plan verification,
credentials, actual provider compatibility, current runtime authority,
genuine caller acceptance, deployed-source readback, exact hosted usage and
external delivery are separate open gates.

See the [activation record](../../development/ai-integrations-free-activation-20261102.md)
for the bounded rollout sequence. No commit, push, database migration, hosted
configuration change, provider request or delivery resend was performed for
this candidate.
