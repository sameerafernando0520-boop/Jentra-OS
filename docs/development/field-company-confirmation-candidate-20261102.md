# Company contact and response-request workspace candidate

2 November 2026, Asia/Colombo. Continues the
[order email-confirmation candidate](field-order-email-confirmation-candidate-20261102.md).
This prepares company staff source and isolated rollback verification. It installs
no migration, activates no sender, deploys no application and claims no live or
company acceptance. Sales and Employee remain separate applications.

## Company workflow

The desktop **Customer email requests** destination requires only the dedicated
`sales.field.confirmations.manage` capability, current operational scope and a
current authenticated actor. Both `FIELD_SALES_CANDIDATE_ENABLED` and
`FIELD_SALES_EMAIL_CONFIRMATION_ENABLED` must be true to wire its gateway and
navigation; both default to false. The server additionally requires a current
company session and MFA. Broad order or discount permissions are unnecessary.

Staff select an independently approved request, review its exact commercial
terms and complete structured address, and manage customer contacts with a
company authority note and expiry. Contact authorization records company
authority; it does not verify the mailbox or establish legal signing authority.
Contact creation, revision and revocation remain available when the sender is
unavailable. Request issuance stays disabled until the private transport policy
is configured by a separately reviewed rollout.

Issuance requires an explicit contact selection and review declaration. The
command binds the approved request version, source digest and reviewed contact
version. The app reports **queued**, never email delivery or customer acceptance.
The service-only dispatch seam is not callable by the staff gateway. No worker
or network sender is included or activated.

A current accepted response cannot be silently replaced by another issuance.
Staff must explicitly revoke the challenge or contact first. Historical evidence
is retained. A request has at most one challenge whose state is not revoked,
including issuance races across different recipients. The existing canonical
draft remains guarded; a customer response cannot advance it.

## Candidate database contracts

Compose `supabase/candidates/20261102120000_field_confirmation_company_workspace.sql`
after the governance and order-email candidates. Existing applied migrations are
unchanged. This additive candidate introduces:

| RPC | Contract |
| --- | --- |
| `api.field_sales_confirmation_subjects(t,e,b,after,limit)` | Approved requests in the current company/branch, customer names, independent states and provider availability |
| `api.field_sales_confirmation_challenges(t,e,b,request,after,limit)` | Scoped, bounded history with effective state and recipient name; no bearer, code, proof or secret hash |
| `api.field_sales_confirmation_company_command(t,e,b,command,key,timestamp,action,payload,expected)` | Reviewed command wrapper; `issue_order` additionally requires `contact_version` |

The existing scoped contact and own-actor receipt RPCs are reused. Page defaults
are 50, with a server maximum of 200; the app requests 50. The wrapper delegates
to the original audited command under the caller's JWT. Its owner can call that
command internally, while direct client execution of the old command is revoked
to close the bypass. The wrapper checks the original receipt's contact revision
on an exact retry and rejects a changed payload under an existing command/key.
Receipt recovery remains separately available after later source/contact changes.

The new uniqueness constraint and command permission change require a reviewed
full-schema and existing-data rehearsal before any future installation. The
isolated fixture suite does not prove compatibility with existing hosted rows.

## Protected recovery and privacy

Each write is sealed in the existing encrypted draft repository before dispatch,
using its own `sales.field.confirmation_company` entity type and actor/company/
branch key. It never shares a pending action with Employee, Sales order drafts,
quotation drafts or the discount decision store. Concurrent preparation in the
same app process permits one pending command per actor/scope.

Reopening loads the pending identity without resending. An explicit receipt check
can finish a committed command; a not-found result permits only an explicit retry
with the original command ID, key, timestamp, payload and expected version. A
receipt must match the exact actor/scope/entity, version and action-specific
reviewed details before the encrypted pending row is cleared. Definite server
validation/conflict failures clear the pending row for a fresh review. Uncertain
transport or receipt failures retain it.

After 24 hours, or an invalid future timestamp, loading strips private contact
details and reasons from the saved body. Only receipt checking remains available.
There is no automatic replay and no automatic discard of an unresolved identity.

Scope, actor, session, capability or gateway loss fences late results and clears
private in-memory data. Backgrounding and a 15-minute local lease also lock the
workspace. Unsaved contact edits require explicit save or discard. Outcome
messages appear first in the scroll area and are announced as live regions.
Automated phone, tablet and desktop checks use 200% text; physical-device and
assistive-technology acceptance remain separate.

## Focused implementation and verification

The missing staff workflow crossed four public seams: company selectors and
commands, protected immutable recovery, current-authority desktop UI and its
dedicated navigation. The dependency path is SQL candidates -> the existing
scoped Supabase transport -> the new company gateway/store -> controller ->
desktop route and order-workspace shortcut. The existing encrypted repository,
exact decimal/domain JSON contracts, current Auth providers and theme are reused.
No package is installed and no Employee application code is edited.

Review repairs cover fixed-length paged lists, contact-version replay binding,
independent confirmation-only navigation, protection of current accepted evidence,
and visible outcome notices at narrow widths. Regression checks exercise the
actual gateway, encrypted storage, controller actions, navigation and widgets.

Run from the workspace root:

```powershell
node supabase/candidates/run-field-company-test.mjs --run-isolated
node --test supabase/candidates/tests/field_company_runner.test.mjs
```

The runner rejects hosted target options, uses the already-present pinned PGlite
runtime and composes all three candidates. It first reruns the prior 134 checks,
then verifies the company workspace. The extension rolls back independently and
restores the original command body and ACL; subsequent rollback removes the
email extension, governance candidate, fixtures and entire simulated baseline.
Exact final results, source hashes and local compilation are recorded in the
[verification record](../verification/field-company-20261102/README.md).

## Separate remaining gates

This is the November 2 verification boundary. The [November 3 continuation](field-sales-rollout-candidate-20261103.md)
now supplies candidate worker, company progression and separate delivery flows;
its own record distinguishes implementation from hosted activation and acceptance.

- **Email-link activation:** real worker/provider, reviewed sender/domain,
  mailbox receipt and forwarded-link behavior, hosted HTTP/cache/scanner checks,
  origin/log redaction and service-level abuse controls. Staff source and local
  compilation do not establish any message transport or delivery.
- **Delivery acknowledgement:** exact posted partial-delivery/version and
  received/refused/short quantities require their own verified recipient flow.
- **Company progression:** reviewed credit/stock/order progression remains a
  separate implementation and acceptance boundary.
- **Company acceptance:** full current Supabase schema and existing-data
  rehearsal, genuine independent sessions/MFA, contention and revocation,
  ordinary company/Employee compatibility, device privacy/accessibility and
  representative/approver/customer pilot signoff.
- **Installation and distribution:** migration installation, sender activation,
  signing/distribution, deployment and live verification require a separately
  authorized rollout. They are excluded here.
