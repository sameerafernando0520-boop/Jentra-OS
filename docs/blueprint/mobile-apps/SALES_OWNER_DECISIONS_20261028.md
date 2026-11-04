# Jentra Sales owner decisions and implementation order

Author: Codex. Date: 28 October 2026. Status: records the owner's explicit
decisions and the additive implementation path. Reviewers: owner, sales manager,
credit/finance, warehouse and security/engineering. The existing
[Sales blueprint](SALESMAN_APP_BLUEPRINT.md) remains the full S1 contract.

## Context

The owner selected **discount requests with company approval** and **verified
email links** for customer acceptance and delivery acknowledgement. Selecting
the channel does not authorize sending, deployment or provider activation.
Customer acceptance, company approval and delivery acknowledgement remain
independent, revision-bound facts. An internal salesperson/owner field is
attribution and does not establish customer portfolio authorization.

## Functional requirements

- SD-01: The field app MUST use dated, explicit representative/customer/company/
  branch assignments. Its installation MUST NOT grant broad CRM, order,
  receivable or file access. Every server request MUST recheck the assignment.
- SD-02: A representative MAY request a discount with a reason against a governed
  commercial source. The representative MUST NOT approve their own request or
  silently replace an approved price. A company approver MUST review the exact
  request/revision under current delegated authority and credit policy.
- SD-03: Customer confirmation MUST use the selected verified email channel and
  a company-authorized contact. Link possession alone MUST NOT be described as
  proof of legal signing authority. The challenge MUST be short-lived, revocable,
  scope/revision-bound and protected against reuse, abuse and contact enumeration.
- SD-04: Reading a link, following a redirect, email security scanning or link
  previewing MUST NOT accept an order or acknowledge delivery. An explicit
  customer action is required. No sensitive token or prices may enter telemetry.
- SD-05: A commercial revision MUST invalidate earlier acceptance as required by
  the blueprint; each posted partial delivery MUST have its own quantity-bound
  acknowledgement. Neither customer action MAY post stock, payment or invoice.
- SD-06: The app MUST distinguish a local draft, a submitted request, an existing
  canonical quotation/order and confirmed company/customer/delivery evidence.
  Provider absence MUST remain unavailable, never synthetic success.

## Non-functional requirements

Existing NFR-7001–7009 and NFR-7201–7206 remain applicable. First-release page
limits are 50 by default, 200 maximum; order inputs cap at 100 lines and exact
decimal strings. Confirmation defaults remain 15-minute challenges, five failed
attempts per challenge and five issues per recipient/hour, with service abuse
controls. No measured latency/load, device acceptance or distribution is awarded
by this decision record.

## Acceptance criteria

- SD-A1 (SD-01): Given two portfolios or a revoked assignment, when a rep uses
  either the mobile interface or legacy APIs, then other customers' data and
  effects remain denied. Own customers without transactions remain searchable.
- SD-A2 (SD-02): Given a discount request, when its author attempts approval or
  its source changes, then no approval is recorded. A current independent
  approver reviews the exact revision and retains the decision/reason history.
- SD-A3 (SD-03, SD-04): Given a forwarded, expired, revoked, replayed or scanned
  link, then it cannot silently establish a new verified customer response.
- SD-A4 (SD-05, SD-06): Given changed terms and two partial deliveries, then
  acceptance and each delivery response bind their own source; no response
  implies approval, stock posting, invoicing or cleared payment.

## Edge cases

Assignment/contact/price changes require fresh server review. An uncertain
submission retains its original encrypted recovery identity. A missing email
provider leaves confirmation pending; a rep cannot override it. Company review,
customer rejection and shortage history remain visible without editing posted
ledger facts.

## API contracts

The proposed `field_sales_*` contracts in the existing blueprint are not yet
installed endpoints. Discover actual canonical commerce signatures before
implementing wrappers. Use the caller's own JWT, a private scoped helper or an
authorized company-side canonical command. Never impersonate a representative,
temporarily grant broad permissions or embed service credentials in an app.

```typescript
interface DiscountRequest {
  subjectId: UUID; sourceVersion: string; sourceDigest: string;
  requestedDiscountPercent: Decimal; reason: string;
}
interface CompanyDiscountDecision {
  requestId: UUID; expectedVersion: string;
  decision: 'approve' | 'reject'; reason: string;
}
```

## Data models

| Fact | Required binding |
| --- | --- |
| Portfolio assignment | Tenant, entity, branch, active representative membership, customer, effective range and version |
| Governed price source | Product/unit/customer/currency, effective range, exact price/discount rule and source revision |
| Discount request/decision | Immutable request/source digest, exact discount, author, independent approver, reason and timestamps |
| Customer response | Authorized contact and verified email channel, challenge, commercial digest/version, explicit response and expiry |
| Delivery response | Specific posted delivery/version and exact received/refused/short quantities with verified recipient evidence |

## Out of scope and implementation order

1. Establish the server portfolio boundary and verify direct legacy-path denial
   with field-only roles before granting any field account access.
2. Implement the separate mobile app, governed catalogue/draft/discount review
   and company-side canonical quotation/order integration.
3. Prepare verified email challenge/response and customer confirmation UI,
   retaining provider-disabled behavior until a reviewed sending rollout.
4. Run rollback-only database, device, recovery, privacy and company acceptance
   on the exact reviewed release before signed distribution.

Collections/returns remain S2. No invitation sender, customer email transport,
employee push worker or production job is activated by these selections.
