# Order email confirmation candidate

2 November 2026, Asia/Colombo. Continues the
[portfolio/order candidate](field-sales-governance-candidate-20261031.md) and
[owner-selected email channel](../blueprint/mobile-apps/SALES_OWNER_DECISIONS_20261028.md).
This prepares order-response database and recipient-app source. No migration is
installed, no sender or worker is activated, no application is deployed, and no
live or company acceptance is claimed. Sales and Employee remain separate apps.

## Implemented boundary

The additive `supabase/candidates/20261102090000_field_order_email_confirmation.sql`
requires the prior governance candidate. It adds one company capability,
`sales.field.confirmations.manage`, without changing existing role/account grants.
Current company scope, Auth session and AAL2 are required to authorize/revoke a
customer contact, issue an order challenge, or revoke a challenge. Field accounts
cannot inherit this authority through their broad legacy grants.

A contact has a company-recorded authority note, normalized email, customer and
company/branch scope, expiry and version. Authorization does not itself verify
email access or legal signing authority. Contact changes invalidate pending
challenges. The selector defaults to 50 contacts and permits at most 200 per page.

Transport policy is private and disabled when missing. There is no application
API to enable it. An unavailable provider prevents challenge creation and command
receipts. A separately reviewed rollout would need both the provider and worker;
neither exists as an active transport in this slice.

## Recipient flow

1. A current company command freezes an independently approved request revision,
   source digest, canonical draft digest, authorized contact revision and transport
   policy. It creates a queue entry without exposing a bearer to the representative
   or company client. Five issues per recipient/tenant/hour are enforced across
   superseded challenges.
2. The private service-role dispatch seam accepts an ephemeral 32-byte hex bearer
   from a future worker and retains only its hash. Preparing a message and
   recording provider acknowledgement are separate operations. Acknowledgement
   references are immutable; provider acceptance is not proof of delivery.
3. The minimal recipient page captures only the exact root fragment
   `#confirm=<bearer>`, then removes it before SDK initialization. Malformed,
   embedded, duplicate, encoded-key and query-string forms are scrubbed and
   rejected. Opening the page makes no RPC or business decision.
4. The recipient explicitly requests a six-digit code at the already authorized
   address. The caller cannot choose a destination. A future worker must prepare
   and acknowledge this separate message. Code preparation alone grants no access.
5. Correct code verification opens the exact frozen terms, prices, discounts,
   taxes, units and complete structured ship-to address. The proof binds the
   displayed offer hash as well as the challenge. The explicit response checks
   that same offer and stores the exact JSON value it checked.
6. Accept/reject requires the recipient's authority declaration. It records a
   separate evidence row with contact/offer snapshots, method, revision, digest,
   response and expiry. It does not confirm a canonical order, reserve/post stock,
   invoice, clear credit, record payment, or acknowledge delivery.

Challenges last 15 minutes and allow five failed attempts in total. Correct
verification alone never accepts an order. Completed responses cannot be revoked
by subsequent bad guesses, and an identical response retry returns its original
evidence. Conflicting responses cannot replace it. Explicit company revocation,
contact/source changes and expiry are distinct from a customer response.

Commercial response validity defaults to 24 hours, bounded by contact expiry;
the private reviewed policy permits 15 minutes through seven days. The short
verification challenge and the commercial acceptance deadline are separate.
Historical evidence remains stored when its current state becomes expired or
superseded. A transport outage does not erase a completed response.

Public RPCs permit only anonymous explicit POST operations, deny absent/other
methods, and return non-cacheable responses. This uses PostgREST's documented
[request-method transaction setting](https://postgrest.org/en/stable/references/transactions.html#request-path-and-method).
The candidate SQL suite simulates this setting; it is not a hosted HTTP rehearsal.

## Matching applications and recovery

The recipient surface is a small route in the existing Sales web distribution,
not another full application. It uses a dedicated anonymous client and no Sales,
Employee or desktop draft storage. Tokens, codes, proofs and private terms stay
in memory; opening the page never consumes a challenge. Both
`FIELD_SALES_CANDIDATE_ENABLED` and `FIELD_SALES_EMAIL_CONFIRMATION_ENABLED` must
be true, with public client configuration present. Both flags default to false.

The page supports phone/tablet/desktop widths and large text. It permits switching
to email before verification. Backgrounding an active or in-flight private review
clears terms and fences late results. A 15-minute local lease also clears the page.
An uncertain response freezes its original decision/note and permits only an
explicit original retry. No response is replayed on startup or rebuild.

Sales history and desktop company review read current independent company,
customer and delivery states. Canonical drafts remain guarded even after
customer acceptance; company progression is a separate reviewed slice.

Company command recovery uses the new scoped, actor-owned receipt facade. It can
recover a committed issuance after a later price revision without issuing another
message. The subsequent [company workspace candidate](field-company-confirmation-candidate-20261102.md)
adds the staff contact/issuance UI and protected pending-command recovery. It
still activates no transport. Its reviewed wrapper replaces direct client access
to the original company command described below.

## Contracts and focused repair scope

| Surface | Contract |
| --- | --- |
| `api.field_sales_confirmation_contacts(t,e,b,customer,after,limit)` | MFA company selector; provider state; bounded pages |
| `api.field_sales_confirmation_command(t,e,b,command,key,timestamp,action,payload,expected)` | `authorize_contact`, `revoke_contact`, `issue_order`, `revoke_challenge`; existing command/receipt conventions |
| `api.field_sales_confirmation_receipt(t,e,b,key)` | Current company authority, own actor and exact scope; no source-freshness requirement for historical recovery |
| `field_sales.confirmation_dispatch(id,step,secret,provider_reference)` | Private service-only preparation/ack seam; no network implementation |
| `api.field_sales_confirmation_request_code(token)` | Explicit anonymous request; no address enumeration or offer disclosure |
| `api.field_sales_confirmation_verify(token,code)` | Separate verified-channel proof and minimal frozen offer |
| `api.field_sales_confirmation_respond(token,proof,response,reason,authorized)` | Exact explicit response; original-result recovery; no ledger effects |

The feature spans SQL candidates, the shared platform gateway/link capture, the
Sales recipient controller/page, and two existing status consumers. Those
cross-folder edits connect the same bounded flow; Employee code and applied
migrations are untouched. Dependencies are the prior field-sales schema, canonical
commerce/pricing helpers, current Auth sessions, the existing public Supabase
client package, the Sales theme and Flutter lifecycle. No new package is installed.

The public seams under verification are candidate RPC authorization/state,
anonymous transport calls, link capture, recipient actions/privacy and the two
status consumers. Review repairs address missing-method denial, bounded contact
pages, immutable transport acknowledgements, terminal evidence protection,
historical receipt recovery, displayed-offer binding, malformed-link scrubbing,
background races, structured addresses and corrupt decimal/reference shapes.

## Verification and separate remaining gates

Run `node supabase/candidates/run-field-confirmation-test.mjs --run-isolated`.
The runner composes the prior governance and new confirmation candidates over
the same exact baseline. It reruns governance regression checks, verifies the
new flow with synthetic provider acknowledgements, then rolls back the email
extension independently, the governance candidate and the entire baseline.
Original functions, ACLs, schema grants, permissions, entitlements, fixtures and
receipts are checked for restoration. Hosted target arguments are rejected.

Exact results and source hashes are in the
[verification record](../verification/field-confirmation-20261102/README.md).
PGlite/PostgreSQL 18, simulated Auth/Storage, synthetic recipient mailboxes and
provider references are source evidence, not Supabase/PostgreSQL 17 acceptance.

**Email-link activation:** the [staff issuance continuation](field-company-confirmation-candidate-20261102.md)
prepares company UI and protected recovery; remaining activation needs the actual
worker and provider, sender/domain configuration,
mailbox receipt and forwarded-link tests, HTTP/browser cache/scanner behavior,
deployment-origin/log redaction, and service-level abuse controls. Keep transport
and both feature flags disabled until that rollout is authorized and accepted.

**Delivery acknowledgement:** exact posted partial-delivery/version/quantity-bound
recipient responses remain a separate slice. Order acceptance cannot substitute
for received, refused or short quantities.

**Company acceptance:** rehearse the exact candidate on the full current schema
with genuine independent sessions/MFA; verify contention, revocation, credit
freshness, ordinary company/Employee compatibility, device privacy/accessibility
and representative/approver/customer pilot signoff. Candidate tests do not award
these gates.

Migration installation, sender activation, signing/distribution, deployment and
live verification are excluded from this task and require a separate rollout.
