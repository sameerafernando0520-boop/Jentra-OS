# Cloudflare Free provider deployed — 2 November 2026

The Cloudflare Free provider is configured in Jentra Supabase and deployed in
`wave5-runtime` **V9**. A real synthetic Cloudflare request returned HTTP 200,
the exact permitted suggestion, and **223 tokens**: 122 prompt tokens plus
101 completion tokens. This proves provider connectivity and the reviewed
response/usage contract. It is not a settled Jentra business invocation.

## Completed evidence

- Cloudflare Billing / Subscriptions showed **Workers Free — Active** and
  **No payment method on file** for the selected account.
- The owner approved the account-scoped `Jentra Wave 5 Free AI` token with
  Workers AI Read and Edit. After its original value appeared in a tool result,
  the owner explicitly approved rotation. Cloudflare confirmed the rotation;
  the exposed value was invalidated before use. The replacement was handled
  without displaying its value.
- One fixed-model synthetic provider request passed the adapter's real
  raw-prompt, JSON-schema, exact-reference and returned-usage checks. It sent
  synthetic references and dates, with no tenant identifier, business amounts
  or population data. It did not create a Jentra invocation or settle usage.
- `W5_CLOUDFLARE_ACCOUNT_ID` and `W5_CLOUDFLARE_API_TOKEN` were installed in
  `xpdoufauvrbdmxgngetv`. Their remote SHA-256 digests matched the exact intended
  values locally. The temporary local secret file was then deleted.
- All **303 worker tests** passed. The normal runtime/receiver and the staged
  runtime passed Deno source checks. The candidate's sources and reviewed test
  files still matched their frozen hashes before deployment.
- After secret provisioning, function metadata counters read V8, while their
  original V7 entrypoints and source timestamps were unchanged. A fresh runtime
  backup showed all 16 executable modules exactly matching the archived V7
  code. No unreviewed intervening source change was overwritten.
- Only the reviewed runtime candidate was deployed. Its active V9 source was
  downloaded again; all **16 executable modules matched** the staged source
  byte for byte. The candidate also contains one non-executable Deno config
  input, giving 17 staged inputs in total. The receiver remained unchanged at
  its observed V8 metadata version. Gateway JWT configuration was preserved;
  Jentra's own caller and schedule authentication remains enforced.
- Four actual unsigned hosted requests all returned the expected 403 denial:
  schedule, external forecast, model suggestion and receiver. The model route
  now returns `AUTH_REQUIRED` rather than missing-provider configuration.

The initial secret-readback checker expected a JSON field named `digest`.
The installed CLI 2.75.0 names that field `value`, even though it holds the
digest. The field semantics were verified against the official CLI source;
both digest comparisons passed after correcting the readback check. The
secret-setting operation was not repeated.

Source: [Supabase CLI 2.75.0 secret-list implementation](https://raw.githubusercontent.com/supabase/cli/v2.75.0/internal/secrets/list/list.go).

The fixed model remains `@cf/meta/llama-3.3-70b-instruct-fp8-fast`, with no paid
fallback, no model substitution and no automatic retry of an uncertain call.
Cloudflare documents a 10,000-Neuron daily free allocation. Requests above the
Free limits fail; paid overage requires a paid plan. No payment method, paid
upgrade, credits or OpenAI key was added by this work.

Source: [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/).

## Remaining business acceptance gates

The read-only Jentra accounting snapshot at
`2026-11-02T11:03:01.944795+00:00` observed:

- Runtime authority inactive.
- No model invocations, no model settlements and no quota-period rows.
- One existing delivery in retry state at attempt 1, with no acknowledgement
  or receiver receipt.

A separate read-only detail query at
`2026-11-02T11:06:47.752899+00:00` confirmed that the existing branch scope
expired on 14 October at 08:13:04 UTC and the edge/schedule authority expired
that day at 09:57:07 UTC. The branch itself was active. These are timestamped
observations, not a continuously current certification. The accounting assessor
correctly rejects the saved snapshot once it is more than five minutes old;
its freshness rejection is not evidence that the delivery row disappeared.

A genuine authenticated Jentra request and exact Jentra reservation/outcome/
settlement evidence are still required. The existing desktop/web client uses
its signed-in user's own token through `SupabaseReviewedModelGateway`; no
dashboard session, stored desktop token or fabricated user session is used.
The owner has been asked to sign in privately to the existing Jentra web app
and complete MFA if needed. That app tab is preserved for continuation.

Renewal of expired branch/runtime access is a separate security-sensitive
operation and has not been applied. Establish current source readiness and a
concrete bounded renewal before requesting that action's confirmation. The
existing four-logical-invocation tenant cap and 2,000-token invocation ceiling
have not been expanded. Keep the expired delivery/schedule authority separate
from an authenticated model test.

The original delivery remains unresolved under its original identity. It was
not replayed, replaced or resent. No receiver change, schedule activation,
database migration, committed business-data change, commit or push occurred.

## Evidence index

The current machine-readable result and hashes are in
`docs/verification/ai-integrations-free-20261102/activation-result-20261102.json`.
The public denial probe is in
`docs/verification/ai-integrations/2026-11-02T11-19-11-120Z-adbbe455-6bed-41a0-80d1-6bf5f876ea33/report.json`.
The source candidate manifest remains
`0fc36fbd03cad60e73e1681249b7b24d58cd2e815cc8808bbbe933b30ce8dc6a`.

Earlier candidate/account/token records are frozen observations of their own
steps. This result supersedes their incomplete deployment/token-rotation
status; it does not rewrite those historical records as if later actions had
already happened.
