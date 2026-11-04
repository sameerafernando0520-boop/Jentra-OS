# Free AI activation candidate — 2 November 2026

The owner authorized implementation and activation of a free hosted AI route,
then requested Chrome for Cloudflare account setup. The replacement is
implemented, reviewed, tested and staged. **It is not deployed or activated.**
No OpenAI key was created, payment method added, credit purchased, or model
request sent by this work.

## Implemented behavior

The canonical Wave 5 runtime now selects `cloudflare.workers-ai.free.v1` with
`@cf/meta/llama-3.3-70b-instruct-fp8-fast`. It requires
`W5_CLOUDFLARE_ACCOUNT_ID` and `W5_CLOUDFLARE_API_TOKEN`. An existing
`W5_OPENAI_API_KEY` cannot provide a fallback. Historical versioned entrypoints
retain their original configuration for comparison and recovery review.

The provider sends only the permitted command code, source UUID, source hash
and horizon dates. It does not send tenant IDs, currency amounts or population
data. Requests use a fixed Cloudflare API origin, a fixed model, bounded JSON,
an explicit raw prompt, no tools, no redirects, and one attempt. Missing or
inconsistent provider token counts cannot settle usage. Quota errors stop the
attempt; uncertain outcomes remain reserved for review without an automatic
resend.

The runtime retains caller-scoped evidence reads, reservation and authorization
before provider access, persisted outcomes, exact settlement, and authorization
again before returning a suggestion. The invocation manifest binds the
Cloudflare account, model and provider. Changing any of them cannot reopen a
previous invocation. Deterministic invalid inputs or an insufficient token
ceiling fail before creating an invocation or reserving quota. No schema
migration is required for this manifest binding.

## Verified local evidence

All **303 worker tests passed**, with no failed, skipped or cancelled tests.
The normal runtime and receiver entrypoints passed Deno checks. Two independent
read-only reviews identified provider identity binding and early budget
validation gaps; both received regression coverage and were corrected. The
review fixture was also corrected to match the actual database RPC's sanitized
503 error for a stored-request mismatch.

The staged runtime contains 17 source inputs and passed Deno checking from its
own directory:

`build/wave5-cloudflare-free-20261102/2026-11-01T19-57-55.413Z`

Its `candidate.json` SHA-256 is:

`0fc36fbd03cad60e73e1681249b7b24d58cd2e815cc8808bbbe933b30ce8dc6a`

The candidate contains no secret values. It is built from the normal
`supabase/functions/wave5-runtime/index.ts` entrypoint and a minimal staging
configuration. Its `verify_jwt = false` matches the deployed worker's existing
gateway setting; Jentra's own request and schedule authentication remain
enforced. The preparation helper performs no network calls, deployment or
database writes. Preserve this candidate unchanged; prepare a successor if its
runtime source changes.

Evidence and source integrity are indexed in
[`docs/verification/ai-integrations-free-20261102/README.md`](../verification/ai-integrations-free-20261102/README.md).

## Hosted state before activation

At **2026-11-01T19:54:57.967Z** (2 November 2026, 01:24:57 in Colombo), a
read-only Supabase CLI preflight observed project `xpdoufauvrbdmxgngetv` as
`ACTIVE_HEALTHY`. Both `wave5-runtime` and `wave5-receiver` were active at V7,
using their historical versioned entrypoints. Neither Cloudflare secret name
was configured. No secret value was read and no hosted configuration changed.

Chrome previously displayed a Cloudflare account-home title after private user
interaction. That title does not establish its Workers plan or an API token.
On resuming, Chrome showed a Supabase window and Computer Use reported that
window as minimized. No Cloudflare plan, account ID or token has been verified.
Native Chrome must be restored before account setup can continue. Do not create
a duplicate account based on the missing active tab alone.

The earlier 31 October database snapshot reported inactive runtime authority,
no model ledger records, and unresolved external delivery. Those are dated
observations, not refreshed database evidence for this candidate. A current
authority check and a genuine authorized business caller are still necessary.

## Activation sequence and evidence still required

1. In Chrome, inspect the existing Cloudflare account and confirm **Workers
   Free**, an eligible model and the actual account ID. Add no payment method
   and enable no paid upgrade. Private password entry and any account-creation
   terms must be completed with the required owner involvement.
2. Prepare an account-scoped token using only the documented Workers AI Read
   and Edit permissions for that account. Review its exact permissions before
   the action-time confirmation required for creating persistent access. Keep
   its value out of chat, source control and logs.
3. Make one bounded synthetic provider probe, with durable attempt intent and
   no automatic retry, before spending a governed Jentra invocation. Verify
   actual raw-prompt/schema compatibility and all returned token fields. The
   conservative byte/framing bound is a local assumption until this is tested;
   it is never reported as actual usage.
4. Configure the two Cloudflare Supabase secrets privately for the verified
   account. Refresh hosted runtime authority and genuine caller/source
   readiness. An expired lease, dashboard session or fabricated user session
   does not satisfy these gates.
5. Recheck candidate integrity, then deploy only `wave5-runtime` from the
   staged candidate to `xpdoufauvrbdmxgngetv`. This activation request does not
   require a new migration, receiver deployment or schedule activation.
6. Read back deployed source and verify expected unsigned denials. Use an
   actual authorized caller for the positive hosted model request and reconcile
   the exact persisted provider usage, reservation and settlement under its
   original invocation identity.
7. Continue the original external-delivery investigation separately. Preserve
   its existing retry/unknown identity; do not resend it or substitute a new
   delivery to obtain a positive receipt.

Cloudflare documents a 10,000-Neuron daily free allowance, rather than unlimited
requests. On Workers Free, exhaustion returns an error; paid overage requires a
paid plan. The adapter's flags do not independently prove the account plan.
Actual plan verification is therefore an activation gate. Existing Supabase
and external-delivery resources retain their own plans and limits.

Sources: [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/),
[model reference](https://developers.cloudflare.com/workers-ai/models/llama-3.3-70b-instruct-fp8-fast/),
[JSON mode](https://developers.cloudflare.com/workers-ai/features/json-mode/),
[REST setup and token permissions](https://developers.cloudflare.com/workers-ai/get-started/rest-api/).
