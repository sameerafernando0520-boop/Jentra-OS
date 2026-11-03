# Sales mail, company progression and delivery evidence — candidate continuation

This continuation implements a reusable organization-scoped Resend worker, explicit company order progression and a separate posted-delivery acknowledgement flow. Sales and Employee remain separate apps. All new backend source is under `supabase/candidates`; nothing in this continuation installs migrations, deploys a worker/client, enables a sender or establishes company acceptance.

The owner selected **verified domain via Resend** on November 3. A sender domain/address, approved pilot mailbox, server credentials and named company signoff have not been supplied. Provider selection alone does not establish ownership of a domain or authorize sending to customers.

## Source and behavior

Compose these after the three existing governance/email/company candidates, in this order:

| Candidate | Result |
| --- | --- |
| `20261103090000_field_sales_mail_worker.sql` | Private per-organization mail policy/jobs; service-only claim/prepare/ack/defer APIs; no default policy, enablement or client access |
| `20261103100000_field_sales_company_progression.sql` | Independent company capability, accepted response and reviewed fresh credit evidence before canonical confirmation; guarded canonical reservation/fulfillment |
| `20261103110000_field_sales_delivery_acknowledgement.sql` | Separate posted partial-delivery challenges, code verification, exact quantity responses and history; no automatic stock or financial mutation |

The [worker](../../workers/field-sales/mail_worker.mjs) and [Edge entry](../../supabase/functions/field-sales-mail/index.ts) use the real Resend HTTPS API. Local verification substitutes its network responses. The scheduler cannot supply an organization, recipient, template or origin: its private deployment allowlist and the database select one eligible job. Each policy names a server credential alias and secret-key version; raw credentials and bearer material never enter a Flutter build or command log.

Jobs freeze sender, recipient, organization, origin, expiry and template. HMAC secrets are reproducible after restart and separated by organization, challenge, job and order/delivery purpose. PostgreSQL stores challenge hashes; the private queue stores the frozen recipient snapshot, not raw tokens/codes. One job has one immutable provider idempotency key and at most five claims. Expired leases can be recovered; uncertain sends retry the same message. An accepted Resend API response means **provider accepted**, not mailbox delivery. No webhook or inbox-delivery claim is implemented.

Resend retains idempotency keys for 24 hours; the challenge lasts 15 minutes. Keep frozen template/key versions available for that recovery window, and disable the organization policy before emergency credential retirement. See [Resend idempotency](https://resend.com/docs/dashboard/emails/idempotency-keys). New Supabase secret keys are sent as `apikey` only; legacy service-role JWTs also use Bearer authorization. Public keys are rejected as worker credentials. See [Supabase key migration](https://supabase.com/docs/guides/api/api-keys/migrating-to-new-api-keys).

## Company order progression

Company discount approval creates a canonical draft. Customer order acceptance remains an independent verified response. The company must then explicitly confirm the draft through the existing canonical command, with current independent MFA authority and `sales.field.orders.progress` plus existing order permissions. The candidate grants this capability to no role.

Confirmation binds the exact accepted commercial source and current credit projection. The company app seals the reviewed credit digest in its existing immutable command envelope; missing/changed/stale credit or missing acceptance fails closed. Credit override retains the existing separate permission and reason requirement. Request/order/customer/exposure locks and private transaction permits protect the canonical call. Public/private legacy paths cannot manufacture a permit or bypass the company decision. Replays return the original canonical receipt; permits are removed before returning.

Canonical reservation, delivery posting, invoice and payment implementations retain their own authority and invariants. This candidate does not synthesize an invoice, receipt, reservation or delivery from customer acceptance. Applied acceptance remains historical evidence if contact access later expires or is revoked. New recipient access still requires current contact authority.

## Separate delivery acknowledgement

A company operator selects a **posted** delivery, explicitly reviews its version, digest, recipient revision and base quantities, then issues a delivery request. Each partial delivery has its own current challenge and immutable response. Order and delivery issues share the same five-per-recipient/hour limit; purposes have distinct tokens, codes, proofs, facades, fragments and pending-command stores.

The recipient opens `/#delivery=…`, explicitly requests a code, verifies mailbox access, reviews the posted quantities and declares authority to respond. Every posted line requires exact string quantities for received, refused and short; their sum must equal the posted base quantity. Refusal or shortage requires a note. A response cannot add lines, change the posted delivery, update stock, invoice or settle payment. Explicit retries recover the original quantity evidence; conflicting retries cannot replace it.

The Sales recipient surface handles phone/tablet/desktop widths and large text, clears private state on background/scope loss, and freezes uncertain responses for explicit retry. Fragment capture scrubs both link purposes before SDK initialization. A signed-in staff actor cannot use the anonymous recipient gateway. The desktop has a distinct **Delivery responses** route and purpose-specific encrypted recovery. Its pending command cannot collide with order confirmation recovery.

All three compile-time flags are required for delivery behavior:

```text
FIELD_SALES_CANDIDATE_ENABLED=true
FIELD_SALES_EMAIL_CONFIRMATION_ENABLED=true
FIELD_SALES_DELIVERY_CONFIRMATION_ENABLED=true
```

Defaults are false. Missing candidate APIs fail unavailable; there is no broad legacy fallback. Provider enablement also requires the worker flag, private tenant allowlist, enabled tenant mail policy and existing confirmation transport policy. Merely compiling a flag does not install or activate its backend.

## Verification and release boundaries

The [November 3 evidence record](../verification/field-rollout-20261103/README.md) binds local checks and the approved hosted trial to their actual sources. All six candidates compose locally with synthetic Auth/MFA and provider responses. Two non-stocked partial deliveries exercise canonical posting and independent quantity evidence. Stocked fulfillment/load testing remains a separate company acceptance requirement.

The approved **original three** candidates were composed against the full hosted PostgreSQL 17 schema and rolled back. After separate explicit owner approval, the exact **six-candidate** SQL also composed successfully against the complete hosted schema and rolled back. Its assertions restored compared function bodies/ACLs, policies, schema grants and permission/entitlement state; the final result confirms the candidate schema was removed. See the [six-candidate execution record](../verification/field-rollout-20261103/hosted-six-rehearsal.json). This establishes DDL/ACL compatibility and restoration, not genuine sessions/MFA, business workflow, sender or device acceptance. The prepared review plan remains the pre-execution snapshot.

Current public GET observations find the existing Sales preview and required privacy headers; the worker and six recipient RPC probes return 404. No real mailbox flow or hosted recipient POST behavior has passed. A GET probe does not certify fragment scrubbing, scanner behavior, privacy, sessions/MFA or a deployed bundle.

Follow the concrete [rollout and rollback runbook](../verification/field-rollout-20261103/review/rollout-runbook.md) for per-organization onboarding, sender validation, sessions/MFA, device checks and company pilot signoff. Installation/deployment, email activation, order progression acceptance and delivery acceptance are four separate decisions. Collections, custody and returns remain S2.
