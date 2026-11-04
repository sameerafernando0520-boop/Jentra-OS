# Cloudflare token setup status — 2 November 2026

The owner approved creating `Jentra Wave 5 Free AI`, limited to Workers AI Read
and Edit for account `a63366d2bc7f95bb4ea1578cdf093ff3`, and storing it privately
in Jentra Supabase. Cloudflare confirmed token creation. The token was saved in
an ignored temporary local environment file; it has not been installed in
Supabase or used for an API request.

After the creation dialog was finished, Cloudflare inserted the token into its
quick-start example. An unredacted accessibility observation exposed that
credential in a tool result. Treat it as exposed. Subsequent observations are
redacted. No copy of the credential belongs in this document or public evidence.

The scoped token's **Roll** confirmation is prepared in the Cloudflare profile
API-token page. Rolling immediately invalidates the exposed credential and
produces a replacement with the same permissions. Automatic approval review
rejected the attempted Roll action because the owner had not explicitly
authorized that specific rotation. The action did not run. A question now asks
for explicit approval to roll this token and continue setup. Do not retry it
or use an indirect route before receiving that approval. Do not install or
invoke the exposed credential.

A fresh read-only Supabase CLI observation at `2026-11-02T09:19:42.424Z`
(14:49:42 in Colombo) still found the project healthy, runtime and receiver at
V7, and both Cloudflare secret names absent. No database query, hosted change,
provider call, deployment or delivery resend occurred.

An operator-only single-attempt synthetic provider probe was prepared under the
ignored build directory and passed a syntax check. It refuses to run without
the verified Free-account record, a completed rotation record, and matching
hashes for all staged candidate sources. It writes durable request intent
before dispatch, allows one fixed-model request, records only bounded safe
response metadata and exact validated usage, and never retries. It has not
been executed. It does not create or settle a Jentra business invocation.

After explicit rotation approval, complete the rotation, replace the ignored
temporary credential privately, and verify the invalidation/success state.
Then run the bounded synthetic model probe and configure Supabase secrets if
the actual provider contract passes. Current runtime authority, genuine caller
acceptance, deployment readback, exact Jentra usage and external delivery
remain separate gates.

Evidence:

- `docs/verification/ai-integrations-free-20261102/cloudflare-token-creation-intent.json`
- `docs/verification/ai-integrations-free-20261102/cloudflare-token-created.json`
- `docs/verification/ai-integrations-free-20261102/cloudflare-token-roll-review.jpg`
- `docs/verification/ai-integrations-free-20261102/hosted-preactivation-20261102.json`
- `docs/verification/ai-integrations-free-20261102/token-activation-status.json`

The Free account and original 303-test candidate records remain unchanged.
