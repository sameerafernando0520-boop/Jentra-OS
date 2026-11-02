# Cloudflare Free account review — 2 November 2026

This is a successor observation to the earlier
[activation candidate record](ai-integrations-free-activation-20261102.md).
The owner authorized switching to the built-in browser after the native Chrome
connection could not access the visible window. The owner completed private
sign-in. The account dashboard was then verified through the browser UI.

At `2026-11-02T09:07:44.067Z` (14:37:44 in Colombo), the account review recorded:

- Account ID: `a63366d2bc7f95bb4ea1578cdf093ff3`.
- Billing / Subscriptions: **Workers Free — Active**.
- Payment method: **No payment method on file**.
- Token form: `Jentra Wave 5 Free AI`, Workers AI **Read** and **Edit**, included
  account resource restricted to this account.
- Token creation: **pending owner action-time confirmation**. No token value
  has been created, read, saved or transmitted by this review.

The prepared token permits Workers AI access and consumption of the account's
daily free allowance. It grants no DNS, billing, account-administration or
payment permission. Its value is intended for private configuration as
`W5_CLOUDFLARE_API_TOKEN` in the existing Jentra Supabase project. The account ID
will be configured as `W5_CLOUDFLARE_ACCOUNT_ID`. Token creation is a distinct
security-sensitive action; the concrete form was prepared before requesting
its required confirmation.

Cloudflare's current official REST documentation requires Workers AI Read and
Edit for a custom token. Its pricing documentation permits the fixed
`@cf/meta/llama-3.3-70b-instruct-fp8-fast` model under the 10,000-Neuron daily
free allocation. Workers Free does not enable paid overage; operations above
the free limits fail. The observed dashboard example uses a different model,
`@cf/moonshotai/kimi-k2.7-code`, which is listed as requiring paid access.
That example was not executed. The reviewed Jentra candidate retains its fixed
Llama model and no paid fallback.

Sources: [REST setup](https://developers.cloudflare.com/workers-ai/get-started/rest-api/),
[Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/).

The actual provider response, returned token usage, Supabase configuration,
deployment, current runtime authority, genuine caller acceptance and external
delivery remain unverified for this free-provider candidate. No model request,
deployment, migration, delivery resend or payment action was performed during
this account review.

Evidence:

- `docs/verification/ai-integrations-free-20261102/cloudflare-account-reviewed.json`
- `docs/verification/ai-integrations-free-20261102/cloudflare-workers-free.jpg`
- `docs/verification/ai-integrations-free-20261102/cloudflare-token-review.jpg`
- `docs/verification/ai-integrations-free-20261102/account-review-verification.json`

The original `verification.json` is a frozen earlier snapshot. It is not
rewritten to turn its historical incomplete gates into current positive
claims. The successor account-review evidence records the newly verified plan
and account independently.
