# Jentra Sales portfolio and governed orders candidate

Candidate dated 31 October 2026; verification finalized 1 November 2026,
Asia/Colombo. This is a source and isolated-verification slice
under the [Sales blueprint](../blueprint/mobile-apps/SALESMAN_APP_BLUEPRINT.md)
and [owner decisions](../blueprint/mobile-apps/SALES_OWNER_DECISIONS_20261028.md).
No migration is installed, no application is deployed, and no live or company
acceptance is claimed. Existing unrelated workspace changes are preserved.

## Implemented boundary

`supabase/candidates/20261031090000_field_sales_governance.sql` adds private
field-account enrollment, dated representative/customer/company/branch
assignments, dated price policies, and order requests. The candidate DDL does
not modify existing accounts, roles or permission grants. A company
administrator must separately delegate the new capabilities through the
existing access-administration contracts.

Enrollment is a deliberate, durable restriction on a field account in a tenant.
Expiry/revocation of its portfolio cannot restore accidentally inherited broad
CRM, commerce, finance, inventory, report, export or file authority. Company
administrators and tenant owners cannot enroll themselves or a tenant owner.
The existing `core.has_permission` identity and ordinary company behavior are
retained with the field-account predicate. Restrictive policies also close
member-only legacy business projections. Legacy command-replay and bootstrap
guards prevent old receipts from bypassing current portfolio authorization.
Field representatives use the named narrow facades; their legacy customer and
commerce paths are denied, including their own legacy document paths.

The separate Employee app is retained. Six existing Employee self capabilities
remain eligible under their existing grants. A narrow adaptation of the real
`people.require_access` helper skips its redundant broad `people.view` gate
only for those self operations; current self permission, active scope, People
subscription/entitlement, and each endpoint's linked-subject checks remain.
Broad staff reads remain denied. The isolated suite executes the actual
Employee self-bootstrap API; it does not award acceptance to all attendance,
leave, HR-document or payroll actions.

## Order and discount flow

1. A representative explicitly selects an authorized company/branch and
   customer. Portfolio search includes assigned customers without transactions.
2. The catalogue supplies company-governed product/base-unit prices, currency,
   dated policy versions and discount ceilings. This slice uses the company's
   base currency and base units; it does not add alternate-unit or FX entry.
3. Online review uses the existing exact quotation/order pricing calculator,
   tax definitions and rounding. The representative cannot supply a unit price,
   tax override, conversion ratio, payment terms or ship-to override. A positive
   requested discount needs a reason and remains a request.
4. Submission rechecks current membership, portfolio, product, warehouse,
   policy versions and the reviewed commercial digest. It records an auditable,
   idempotent **order/discount request**, with no canonical order, reservation,
   invoice, receipt or customer acceptance. At this request stage, credit is
   explicitly awaiting company review and stock availability is unavailable.
   This does not claim complete S1 quotation/fulfilment or FR-7209 acceptance.
5. An independent company approver needs current AAL2, the scoped
   `sales.field.discounts.decide` capability and existing
   `sales.orders.manage`. Approval rechecks the author's active assignment and
   capability, the exact request revision/digest and current commercial source.
   It calls the existing `api.upsert_sales_order` using the company's own JWT,
   then the existing canonical credit-preview contract. Missing credit data,
   a credit hold or overdue exposure prevents approval and rolls back the
   attempted canonical draft. No credit override authority is delegated.
6. A successful approval retains the representative attribution and creates one
   canonical **draft**. Company decision, customer response and delivery response
   stay distinct. Canonical header/line guards block older edit/confirm commands
   until a separately reviewed verified-customer-acceptance slice is available.
   Rejecting a request needs a reason and creates no canonical order.

Material source changes require a new explicit review/request; this slice does
not silently reprice, edit a submitted request, or transfer approval to another
revision. The canonical draft is intentionally unavailable for downstream
confirmation/reservation in this candidate.

## Matching applications

`apps/jentra_sales` retains its explicit synthetic preview. The governed
workspace is a separate runtime path behind
`FIELD_SALES_CANDIDATE_ENABLED=true`, which defaults to false. An absent service
fails closed without using broad APIs or sample data. Password sessions stay
memory-only; cancelled/timed-out attempts cannot silently restore a session.

The governed path has phone navigation, tablet/desktop navigation, explicit
company scope, assigned customers, governed order review, protected local
drafts, unsaved-change choices, exact totals, request history and independent
company/customer/delivery labels. It displays company ship-to/payment terms.
Backgrounding, actor changes, access loss and a 15-minute local authorization
lease lock private content. A draft is restored only after online portfolio
revalidation; its body expires after 24 hours. This is protected local storage,
not proof of physical-device privacy acceptance.

The immutable command is protected locally before dispatch. An uncertain
outcome retains its original command, key, timestamp, actor, scope and digest.
Startup never resubmits automatically. Check receipt and retry original are
explicit actions. Recovery refreshes current request history so a historical
submission receipt cannot overwrite a newer company decision. Expired or
no-longer-authorized bodies are reduced to recovery metadata and cannot be
retransmitted. Company intervention is required where current authority cannot
reconcile an expired/revoked pending request; metadata is not silently discarded.

The desktop Sales orders workspace adds **Field company review** for the
separately delegated company approver, behind the same candidate flag. It
shows the frozen requested lines, discount/reason and exact total; approval or
rejection requires an explicit company reason. Both review and nested decision
dialog lose access on actor, scope, session or capability changes. Company
decisions use their own encrypted recovery entity type, not the representative,
quotation or Employee stores. No external message is sent.

## Candidate API contracts

All RPCs are in `api`, use the caller's own authenticated session, and expose no
private table write grants. Versions and decimals cross JSON as strings.
Each new Sales facade also requires a valid JWT `session_id` referencing the
caller's current, unexpired `auth.sessions` row. A retained access JWT cannot
reopen the workspace after that session is removed.

| RPC | Scope and purpose |
| --- | --- |
| `field_sales_workspace()` | Current representative's authorized company/branch choices and warehouses |
| `field_sales_customers(t,e,b,query,after,limit)` | Assigned customer page, including zero-transaction customers |
| `field_sales_catalogue(t,e,b,customer,after,limit)` | Current governed price policies for one assigned customer |
| `field_sales_preview(t,e,b,input)` | Exact requested terms/pricing and reviewed digest |
| `field_sales_command(t,e,b,command,key,timestamp,payload,expected)` | New order/discount request; expected version is null |
| `field_sales_subject_page(t,e,b,after,limit)` | Current authorized representative history or scoped company review |
| `field_sales_command_receipt(t,e,b,key)` | Own actor's scoped original submission/company-decision receipt |
| `field_sales_company_decide(t,e,b,command,key,timestamp,payload,expected)` | Independent approve/reject with exact revision and digest |
| `field_sales_admin_command(t,e,b,command,key,timestamp,action,payload,expected)` | MFA company assignment/revocation or price-policy administration |

The actual SQL uses the repository's `p_tenant_id`, `p_legal_entity_id`,
`p_branch_id`, `p_command_id`, `p_idempotency_key`, `p_client_timestamp`,
`p_payload` and `p_expected_entity_version` parameter names. Configuration
actions are `assign_customer`, `revoke_assignment` and `set_price_policy`.
Configuration creation/updates bind scope and expected version even on a
conflicting insert; enrollment removal is not an application action.

## Verification and rollback

Run from the workspace root:

```powershell
node supabase/candidates/run-field-sales-test.mjs --run-isolated
```

The runner accepts only that option and opens an in-memory PGlite PostgreSQL
engine. It never reads a database URL, resolves a linked/hosted project, calls a
sender, updates a migration ledger, or installs a migration. It uses the pinned
build-only runtime already present at `build/launch-validation-runtime`.

The [database report](../verification/field-sales-20261031/postgres-result.json)
records source hashes, the exact baseline and **88 successful checks**. The
actual repository migrations through `20260910135507` plus the exact workforce
foundation/private-HR migrations execute. CRLF is normalized to LF for existing
function-body splices; report hashes bind the original unmodified bytes.
Auth users, sessions and `session_id` JWT claims, plus minimal Storage catalogue
tables, are simulated. The suite denies missing, malformed, foreign, deleted
and expired sessions across the new representative and company facades.
Actual Supabase sign-out/refresh behavior remains a full-stack gate. This is
not a full Supabase stack, current hosted-schema rehearsal, Storage byte-delivery
test, independent-session contention test or load measurement.

All candidate definitions and synthetic business effects run inside a
savepoint/transaction. Verification proves removal of candidate schema/policies,
fixtures, Employee links, requests and receipts; restoration of every modified
original function and ACL plus permissions/entitlements; and rollback of the
outer isolated baseline. No applied migration file is edited.

The [verification record](../verification/field-sales-20261031/README.md)
records exact commands and results: 40 Sales tests, 8 gateway/recovery tests,
9 company-review widget tests and 2 runner safety tests. Scoped analysis and a
separate local Sales candidate web build also pass. These are automated
candidate results; they do not imply hosted installation, deployment,
physical-device testing or company acceptance.

## Separate remaining gates

**Verified email links:** the [2 November continuation](field-order-email-confirmation-candidate-20261102.md)
prepares order contact/challenge/response source and a recipient screen. The
staff issuance workflow, actual worker/sender, hosted HTTP/mailbox verification
and service abuse controls remain gates. Each partial delivery still needs its
own quantity-bound verified recipient response. No provider or customer sending
is activated here.

**Company acceptance:** separately authorize/rehearse the exact candidate on the
full current Supabase schema with genuine authenticated pilot sessions and MFA;
verify independent-session races, revocation, storage/recovery, credit-provider
freshness and normal company/Employee compatibility. Then perform device,
privacy/accessibility and real representative/approver acceptance of the exact
reviewed release. Company approval in a synthetic test is not this acceptance.

**Installation/distribution:** future migration installation, any customer sender,
web/APK deployment, signing, live verification and owner release decision require
their own authorized rollout. None is performed or awarded by this task.
