# Spec: Wave 2 Shared Business Foundation

**Author:** Jentra OS Engineering  
**Date:** 2026-09-01  
**Status:** Approved  
**Reviewer:** Product owner (approval expressed by “start and finish wave 2”)  
**Related specs:** `00_PRODUCT_SPEC.md`, `01_ARCHITECTURE.md`, `03_DATA_SECURITY.md`, `04_DESIGN_SYSTEM.md`

## Context

Wave 1 established the executable Windows shell, authentication, tenant hierarchy, scoped RBAC,
audit, idempotency, encrypted drafts, and the private-schema/Data API boundary. The application
cannot yet support commerce or finance because the shared records referenced by every later
document—customers, suppliers, products, currencies, tax rules, ledger accounts, fiscal periods,
numbering, approvals, files, and reporting definitions—do not exist.

Wave 2 supplies that shared business foundation for Sri Lankan SMEs without posting inventory,
ledger, payroll, or payment transactions. It must be usable as a coherent Business Setup Centre,
not as disconnected schema scaffolding. A tenant administrator must be able to complete the
foundation from the desktop application, import bounded master data, export it, work safely with
offline drafts, and receive consistent authorization, conflict, audit, and validation behavior.

The target remains approximately 500 tenants and millions of later operational rows. All Wave 2
writes are additive commands against the synthetic-data-only development project. Existing Wave 1
contracts and applied migrations remain immutable.

## Functional Requirements

### Shared command and read behavior

- FR-201: Every Wave 2 tenant record MUST carry `tenant_id`, UUID identity, UTC timestamps,
  `created_by`, `updated_by`, status, and optimistic `version`.
- FR-202: Finance configuration MUST require a legal entity; branch scope MUST be optional only
  for resources explicitly defined as branch-specific.
- FR-203: Every client mutation MUST execute through a named `api` RPC, validate `auth.uid()`,
  permission and scope, compare the expected version, and reject direct base-table mutation.
- FR-204: Every client mutation MUST accept an idempotency key and create one command receipt and
  one attributable append-only audit event when it changes state.
- FR-205: Reads MUST use `security_invoker` API views, bounded cursor pages, deterministic sorting,
  literal search, and tenant-enforced RLS.
- FR-206: Mutable master records MUST use soft retirement (`active` or `inactive`) and MUST NOT be
  hard-deleted through the client.

### Currency, tax, accounts, and periods

- FR-207: The system MUST expose an ISO-currency reference catalogue including LKR, USD, EUR, GBP,
  INR, AUD, SGD, JPY, CNY, AED, and SAR with scale metadata.
- FR-208: A permitted user MUST create and revise dated exchange rates with positive direct rates,
  source, rate type, legal-entity scope, and uniqueness per entity/pair/date/type.
- FR-209: The system MUST reject an exchange rate whose source and target currencies match or whose
  value is zero or negative.
- FR-210: A permitted user MUST create and revise tax definitions with code, name, rate, tax kind,
  recoverability, inclusive/exclusive behavior, validity dates, and legal-entity scope.
- FR-211: Tax rates MUST be stored as exact `numeric(12,6)` values between 0 and 100 and MUST NOT use
  binary floating point in Dart.
- FR-212: A permitted user MUST create and revise chart-of-account records with unique entity code,
  name, account type, normal balance, optional parent, posting permission, currency, and status.
- FR-213: Account hierarchy MUST stay inside one tenant/legal entity, MUST NOT be cyclic, and a
  non-posting parent MUST remain distinguishable from a posting account.
- FR-214: A permitted user MUST create fiscal periods with unique dates and names per legal entity;
  periods MUST NOT overlap.
- FR-215: Fiscal period state MUST follow `open → soft_locked → hard_locked`; reopening a hard lock
  is outside Wave 2 and no client may delete a period.

### Parties, contacts, products, and units

- FR-216: A permitted user MUST create and revise parties as customer, supplier, or both, with
  unique tenant code, legal name, display name, tax identifier, contact channels, credit metadata,
  and status.
- FR-217: A permitted user MUST create and revise multiple contacts per party with name, role,
  email, phone, primary flag, and status; contacts MUST inherit the party tenant.
- FR-218: At most one active primary contact MUST exist for a party.
- FR-219: A permitted user MUST create and revise units of measure with unique tenant code, name,
  symbol, category, precision, and status.
- FR-220: A permitted user MUST create and revise products with unique tenant SKU, name, kind,
  base unit, legal-entity tax/account defaults, tracking mode, sale/purchase flags, and status.
- FR-221: Product unit, tax, revenue, expense, inventory, and cost-of-goods references MUST remain
  inside the same tenant and, where applicable, legal entity.

### Numbering, workflows, and approvals

- FR-222: A permitted user MUST configure document sequences by tenant, legal entity, optional
  branch, document type, prefix, padding, reset policy, and next value.
- FR-223: Reserving a document number MUST require online confirmation, lock the matching sequence,
  increment it atomically, and return a unique formatted value without gaps caused by retries.
- FR-224: A permitted user MUST create versioned workflow definitions per document type and scope
  with enabled lifecycle transitions.
- FR-225: A permitted user MUST configure ordered approval-matrix steps with role, optional amount
  range, currency, and sequence; ranges MUST be valid and steps MUST reference the workflow tenant.
- FR-226: Workflow configuration MUST NOT decide operational documents in Wave 2; it only defines
  reusable rules consumed by later waves.

### Files and notifications

- FR-227: A permitted user MUST register an attachment with tenant, aggregate type/id, safe file
  name, MIME type, byte size, private storage path, and staged status before upload.
- FR-228: Attachments MUST use a private bucket, allow only PDF, PNG, JPEG, CSV, and XLSX, enforce a
  25 MiB limit, and expose time-bounded signed reads to permitted tenant members.
- FR-229: A completed upload MUST be confirmed through a named RPC before the attachment becomes
  ready; rejected or missing uploads MUST remain unavailable to business consumers.
- FR-230: Users MUST list their tenant notifications, distinguish unread/read state, and mark only
  their own notifications read through an idempotent command.
- FR-231: Business mutations and import/export requests MUST enqueue outbox events for later worker
  delivery without exposing the outbox table to clients.

### Import, export, and reporting primitives

- FR-232: The desktop client MUST parse UTF-8 CSV and XLSX worksheets into normalized headers,
  preview rows, and structured row/field validation errors without applying data during preview.
- FR-233: A permitted user MUST apply an import of at most 500 rows for parties, contacts, units,
  products, exchange rates, taxes, accounts, or fiscal periods in one transaction.
- FR-234: If any import row is invalid or unauthorized, the import MUST roll back all rows, record a
  failed import job, and return bounded structured errors without partial master-data mutation.
- FR-235: A permitted user MUST export a filtered Wave 2 resource page to valid UTF-8 CSV or XLSX
  with stable column order and exact decimal strings.
- FR-236: Import and export jobs MUST record tenant, actor, resource, format, status, counts,
  correlation identifier, file metadata, errors, and timestamps.
- FR-237: A permitted user MUST create and revise saved report definitions with code, title, source
  view, selected columns, bounded filters, sorting, sharing mode, and status.
- FR-238: Saved reports in Wave 2 MUST describe permitted API-view queries only; arbitrary SQL and
  scheduled delivery MUST be rejected.

### Desktop and offline behavior

- FR-239: The desktop application MUST provide a Business Setup Centre covering Finance, Parties,
  Catalogue, Governance, Files & Data, and Reports from one route and command-palette destination.
- FR-240: Every setup list MUST provide loading, error, empty and populated states, literal search,
  status filters, cursor continuation, compact/comfortable density, and create/edit commands.
- FR-241: Setup forms MUST expose field-level validation, keyboard traversal, visible focus,
  semantic labels, unsaved-change confirmation, and exact decimal/date entry.
- FR-242: Offline users MAY edit encrypted setup drafts and view cached references, but imports,
  number reservation, file upload completion, workflow activation, and every server mutation MUST
  remain disabled until live confirmation.
- FR-243: A version conflict MUST preserve the encrypted local draft, show the current server
  version, and require explicit reload or merge; the client MUST NOT silently overwrite.
- FR-244: Routes, quick-create actions, tabs, edit controls, and export controls MUST respect
  server-resolved capabilities, while the database remains authoritative.

## Non-Functional Requirements

- NFR-201: Ordinary setup reads MUST meet p95 under 500 ms and setup commands p95 under 1.5 seconds
  at the target scale, excluding file transfer and external providers.
- NFR-202: List limits MUST be between 1 and 200; import limits MUST be at most 500 rows and 5 MiB.
- NFR-203: Every tenant-bearing Wave 2 table MUST enable RLS and deny cross-tenant reads and writes
  to `authenticated`, `anon`, and `PUBLIC` unless an explicit policy permits the actor.
- NFR-204: Every privileged function MUST use an empty search path, fully-qualified objects,
  explicit authentication/permission checks, and no execution grant to `PUBLIC` or `anon`.
- NFR-205: One hundred percent of successful Wave 2 mutations MUST be attributable by tenant,
  actor, request, command, aggregate, before/after context, and UTC occurrence time.
- NFR-206: Numeric business values MUST use Postgres `numeric` and decimal-string/BigInt-backed Dart
  representations; no binary floating point may cross a public contract.
- NFR-207: Unique constraints and optimistic version checks MUST prevent duplicate codes, SKUs,
  sequence values, primary contacts, exchange rates, and lost updates under concurrency.
- NFR-208: Foreign-key and primary list/filter paths MUST have tenant-leading indexes; no known
  high-volume query may require an unbounded table scan.
- NFR-209: Attachment storage MUST remain private, use signed access of at most 15 minutes, sanitize
  names, and never expose service-role or provider secrets to the desktop client.
- NFR-210: Local drafts and cached sensitive payloads MUST use the Wave 1 AES-256-GCM and Windows
  Credential Manager boundary.
- NFR-211: The Business Setup Centre MUST meet WCAG 2.2 AA, full keyboard operation, visible focus,
  semantic status text, screen-reader labels, reduced motion, and 200% text scaling.
- NFR-212: Wave 2 widgets MUST render without overflow at 1024×720, 1440×900, and 1920×1080 in
  light/dark and compact/comfortable modes.
- NFR-213: Pure domain and codec logic MUST maintain at least 90% branch coverage; changed overall
  code MUST preserve the project-wide 80% target.
- NFR-214: Database tests MUST prove RLS, grants, idempotency, optimistic conflicts, atomic imports,
  number concurrency, audit immutability, and storage access boundaries.
- NFR-215: The Windows release build MUST complete and cold-launch without an immediate crash after
  all Wave 2 changes.

## Acceptance Criteria

### AC-201: Scoped setup catalogue (FR-201–FR-206, NFR-203–NFR-208)
Given two tenants with active members and Wave 2 records
When each member reads API views and attempts direct base-table writes
Then each member sees only permitted records from their own tenant
And both direct writes and cross-tenant reads are denied
And every successful RPC increments version and writes one receipt and audit event.

### AC-202: Currency and exchange rates (FR-207–FR-209, NFR-206–NFR-207)
Given a permitted user in a legal entity with base currency LKR
When they save a positive dated USD-to-LKR rate and replay its idempotency key
Then exactly one rate exists with an exact decimal value
And the replay returns the original response
And same-currency, zero, and negative rates are rejected.

### AC-203: Tax definitions (FR-210–FR-211, NFR-206)
Given a permitted finance setup user
When they create an exclusive 18.000000 percent output tax and read it back
Then the exact six-decimal rate and validity fields are preserved
And rates below zero or above one hundred are rejected with field details.

### AC-204: Chart of accounts (FR-212–FR-213, NFR-207)
Given an entity with a non-posting parent account
When a permitted user creates a posting child and attempts a cross-entity or cyclic parent update
Then the valid child is saved
And the cross-entity and cyclic updates are rejected without changing the account.

### AC-205: Fiscal periods (FR-214–FR-215, NFR-207)
Given an open January fiscal period
When a user creates an overlapping period and transitions January through both lock states
Then the overlap is rejected
And the valid state transitions succeed in order
And hard-lock reopening and deletion are unavailable.

### AC-206: Parties and contacts (FR-216, FR-217, FR-218, NFR-207)
Given a permitted CRM setup user
When they create a customer/supplier party and two contacts marked primary
Then the party and first primary contact are saved
And the second active primary contact is rejected atomically.

### AC-207: Units and products (FR-219, FR-220, FR-221, NFR-206–NFR-208)
Given a tenant unit and legal-entity tax/account defaults
When a permitted user creates a stocked product and attempts a foreign-tenant unit reference
Then the valid SKU is saved with exact scoped references
And the foreign reference is rejected.

### AC-208: Atomic document number reservation (FR-222–FR-223, NFR-207)
Given an active invoice sequence with next value 42
When two online commands reserve numbers and one command is replayed
Then the unique results are `INV-000042` and `INV-000043`
And the replay returns its original number without another increment.

### AC-209: Workflow and approval matrix (FR-224, FR-225, FR-226)
Given a draft purchase-order workflow and a tenant role
When a permitted user adds ordered non-overlapping amount steps and activates the workflow
Then the workflow and steps are readable in order
And invalid ranges or foreign-tenant roles are rejected
And no operational approval decision is created.

### AC-210: Private attachment lifecycle (FR-227, FR-228, FR-229, NFR-209)
Given a permitted user and an existing tenant aggregate
When they register, upload, and complete a valid PDF under 25 MiB
Then metadata moves from staged to ready and a signed read expires within 15 minutes
And disallowed MIME types, oversized files, or another tenant path are denied.

### AC-211: User notification state (FR-230–FR-231)
Given notifications for two users in one tenant
When one user lists and marks their own notification read
Then only their notifications are returned and the selected notification has `read_at`
And they cannot mutate the other recipient’s notification.

### AC-212: CSV import preview and apply (FR-232–FR-234, NFR-202)
Given a UTF-8 CSV containing valid parties and one invalid row
When the user previews and then applies the import
Then preview reports the exact invalid row and field
And apply records a failed job and creates no parties
And a corrected file of at most 500 rows applies atomically.

### AC-213: XLSX import (FR-232–FR-234)
Given a valid single-sheet XLSX with normalized Wave 2 headers
When a permitted user previews and applies it
Then rows match the equivalent CSV representation
And formulas, macros, multiple data sheets, or malformed archives are rejected safely.

### AC-214: CSV and XLSX export (FR-235–FR-236, NFR-206)
Given a filtered page of products with exact decimal metadata
When the user exports CSV and XLSX
Then both files have stable headers and equivalent row values
And decimal values remain strings without precision loss
And completed export jobs are attributable.

### AC-215: Saved report definition (FR-237–FR-238)
Given a permitted reporting user and an allowlisted API source view
When they save selected columns, filters, and sorting
Then the definition is tenant-scoped and reusable
And arbitrary SQL, unknown columns, and unbounded limits are rejected.

### AC-216: Business Setup Centre states (FR-239, FR-240, FR-241, NFR-211–NFR-212)
Given each setup resource is respectively loading, failed, empty, or populated
When the screen renders at every target viewport, theme, and density
Then the correct accessible state appears without overflow
And keyboard users can search, filter, page, create, edit, and cancel forms.

### AC-217: Offline drafts and conflicts (FR-242–FR-243, NFR-210)
Given the desktop is offline with a cached setup page
When a user edits a draft and later encounters a newer server version
Then the encrypted draft survives restart and becomes conflicted
And no server mutation, import, reservation, or upload completion runs offline
And reload/merge is explicitly required.

### AC-218: Capability-gated desktop (FR-244, NFR-203–NFR-204)
Given users with view-only, manage, and no setup capabilities
When they open the Business Setup route and invoke commands directly
Then view-only users cannot edit, unauthorized users cannot use the route or data
And manage users still require the normal database authorization checks.

### AC-219: Performance and bounded work (FR-205, FR-233, NFR-201–NFR-202)
Given representative indexed setup data at target cardinality
When list, search, command, and maximum-size import benchmarks run
Then read and command p95 thresholds are met
And no request exceeds the documented cursor or import bounds.

### AC-220: Complete release gate (FR-201–FR-244, NFR-213–NFR-215)
Given the complete Wave 2 implementation
When format, analysis, unit, widget, golden, pgTAP, advisor, Windows build, cold-launch, and visual
checks run
Then all executable checks pass
And the security advisor has no findings
And any informational performance notices are reviewed and recorded.

## Edge Cases and Error Scenarios

- EC-201: Empty or malformed code/SKU → return `VALIDATION_ERROR` with field details; create nothing.
- EC-202: Duplicate tenant/entity code under concurrency → one command succeeds; one returns `CONFLICT`.
- EC-203: Expected version is stale → return `VERSION_CONFLICT` with current version; preserve draft.
- EC-204: Reused idempotency key for a different command → return `IDEMPOTENCY_MISMATCH`.
- EC-205: Database constraint or connection failure → roll back command; mark error retryability safely.
- EC-206: Exchange rate has identical currencies, non-positive value, or invalid ISO code → reject.
- EC-207: Tax validity end precedes start or rate is outside 0–100 → reject.
- EC-208: Account parent is self, descendant, another entity, or posting-incompatible → reject.
- EC-209: Fiscal period dates overlap or end precedes start → reject.
- EC-210: Second primary contact races with first → unique constraint prevents both becoming primary.
- EC-211: Product references inactive/foreign unit, tax, or account → reject.
- EC-212: Sequence is inactive, padding is outside 1–12, or reset policy is unknown → reject.
- EC-213: Approval amount minimum exceeds maximum or step order duplicates → reject.
- EC-214: Attachment name contains path traversal/control characters → sanitize or reject before storage.
- EC-215: Attachment upload is missing when completion runs → keep staged and return `UPLOAD_MISSING`.
- EC-216: Notification belongs to another actor → return `NOT_FOUND` without disclosing ownership.
- EC-217: CSV has duplicate/blank headers, invalid UTF-8, more than 500 rows, or exceeds 5 MiB → reject preview.
- EC-218: XLSX is encrypted, macro-enabled, zip-bomb-like, multi-sheet ambiguous, formula-bearing, or malformed → reject.
- EC-219: Import row 500 is invalid after 499 valid rows → roll back all 500 master records and record failure.
- EC-220: Export filter references an unknown field or exceeds page limit → reject without creating a ready export.
- EC-221: Saved report source or column is not allowlisted → return `REPORT_SOURCE_DENIED`.
- EC-222: Connectivity drops between validation and RPC → preserve draft and show retryable network error.
- EC-223: Local storage is unavailable/full → retain in-memory edits and return `LOCAL_STORAGE_FULL`.
- EC-224: Text scaling reaches 200% at 1024×720 → controls remain reachable without horizontal page overflow.

## API Contracts

All functions are invoked in the exposed `api` schema. Success returns a `CommandResult<T>`-shaped
JSON object with `request_id`, `entity`, and `warnings`. PostgreSQL errors are translated by the
platform adapter into the stable `DomainError` contract.

PostgREST invocation form: `POST /rest/v1/rpc/{function_name}` with an authenticated bearer token;
read models use bounded `GET /rest/v1/{api_view}` requests.

```typescript
interface SetupCommand<T> {
  tenantId: string;
  legalEntityId?: string;
  branchId?: string;
  expectedVersion?: number;
  idempotencyKey: string;
  payload: T;
}

interface SetupEntity {
  id: string;
  tenantId: string;
  legalEntityId?: string;
  code: string;
  name: string;
  status: "active" | "inactive";
  version: number;
  createdAt: string;
  updatedAt: string;
  fields: Record<string, string | boolean | number | null>;
}

interface CommandResult<T> {
  request_id: string;
  entity: T;
  warnings: string[];
}

interface CursorPage<T> {
  items: T[];
  limit: number;
  nextCursor?: string;
  filters: Record<string, string>;
  sort: string[];
}

interface ImportRequest {
  tenantId: string;
  legalEntityId?: string;
  resource: SetupResource;
  format: "csv" | "xlsx";
  fileName: string;
  fileSize: number;
  rows: Record<string, string>[];
  idempotencyKey: string;
}

interface ImportResult {
  request_id: string;
  job_id: string;
  status: "completed" | "failed";
  total_rows: number;
  accepted_rows: number;
  rejected_rows: number;
  errors: Array<{row: number; field: string; code: string; message: string}>;
}

type SetupResource =
  | "exchange_rates" | "tax_definitions" | "accounts" | "fiscal_periods"
  | "parties" | "contacts" | "units" | "products" | "document_sequences"
  | "workflow_definitions" | "approval_matrix_steps" | "report_definitions";
```

### Named RPC commands

| Function | Required permission | Purpose |
|---|---|---|
| `api.upsert_exchange_rate` | `finance.setup.manage` | Create/update exact dated rate |
| `api.upsert_tax_definition` | `finance.setup.manage` | Create/update tax rule |
| `api.upsert_account` | `finance.setup.manage` | Create/update chart account |
| `api.upsert_fiscal_period` | `finance.setup.manage` | Create/update or lock period |
| `api.upsert_party` | `crm.parties.manage` | Create/update customer/supplier |
| `api.upsert_contact` | `crm.parties.manage` | Create/update party contact |
| `api.upsert_unit` | `inventory.catalog.manage` | Create/update UOM |
| `api.upsert_product` | `inventory.catalog.manage` | Create/update product |
| `api.upsert_document_sequence` | `core.setup.manage` | Configure numbering |
| `api.reserve_document_number` | `core.setup.view` | Atomically reserve number |
| `api.upsert_workflow_definition` | `workflow.configure` | Configure lifecycle |
| `api.upsert_approval_matrix_step` | `workflow.configure` | Configure approval step |
| `api.register_attachment` | `core.files.manage` | Create staged private metadata |
| `api.complete_attachment` | `core.files.manage` | Confirm ready object |
| `api.mark_notification_read` | authenticated recipient | Mark own notification read |
| `api.import_setup_records` | resource manage permission | Apply bounded atomic import |
| `api.create_export_job` | resource view permission | Record completed local export |
| `api.upsert_report_definition` | `analytics.reports.manage` | Save allowlisted report query |

Common errors are `AUTHENTICATION_REQUIRED`, `PERMISSION_DENIED`, `VALIDATION_ERROR`,
`NOT_FOUND`, `CONFLICT`, `VERSION_CONFLICT`, `IDEMPOTENCY_MISMATCH`, `LIMIT_EXCEEDED`,
`OFFLINE_CONFIRMATION_REQUIRED`, `UPLOAD_MISSING`, and `REPORT_SOURCE_DENIED`.

## Data Models

Every mutable table also has `id UUID PK`, `version BIGINT > 0`, `created_by`, `updated_by`,
`created_at TIMESTAMPTZ`, and `updated_at TIMESTAMPTZ` unless noted.

| Entity | Schema/table | Required fields and constraints | Primary indexes |
|---|---|---|---|
| Currency | `core.currencies` | ISO code PK, name, numeric code, minor units 0–6, active; reference-only | active/code |
| Exchange rate | `finance.exchange_rates` | tenant/entity FKs, source/target currency, rate `numeric(20,10)>0`, date, type, source, status; unique entity/pair/date/type | tenant/entity/date/id |
| Tax definition | `finance.tax_definitions` | tenant/entity, code/name, rate `numeric(12,6)` 0–100, kind, inclusive, recoverable, valid dates, status; unique entity/code | tenant/entity/status/code |
| Account | `finance.accounts` | tenant/entity, code/name, type, normal balance, parent, posting flag, currency, status; unique entity/code; scoped parent | tenant/entity/status/code |
| Fiscal period | `finance.fiscal_periods` | tenant/entity, name, start/end, state, status; unique entity/name; exclusion for overlapping dates | tenant/entity/start/id |
| Party | `crm.parties` | tenant, code, legal/display names, kind, tax ID, email/phone/address, credit decimal/currency, status; unique tenant/code | tenant/status/name/id |
| Contact | `crm.contacts` | tenant/party, name, role, email/phone, primary, status; partial unique active primary | tenant/party/status/id |
| Unit | `inventory.units` | tenant, code/name/symbol/category, precision 0–6, status; unique tenant/code | tenant/status/code/id |
| Product | `inventory.products` | tenant/entity, SKU/name/kind, unit, tracking, sell/buy flags, tax/account FKs, status; unique tenant/SKU | tenant/entity/status/SKU/id |
| Document sequence | `core.document_sequences` | tenant/entity/branch, document type, prefix, padding 1–12, reset policy, next value >0, status; unique scoped type | tenant/entity/branch/type |
| Workflow definition | `workflow.workflow_definitions` | tenant/entity, document type, name, lifecycle JSON, status; unique active scope/type | tenant/entity/type/status |
| Approval step | `workflow.approval_matrix_steps` | tenant/workflow/role, step order, min/max exact amount, currency, status; unique workflow/order | tenant/workflow/order |
| Attachment | `core.attachments` | tenant, aggregate type/id, name, MIME, bytes, bucket/path, staged/ready/rejected, checksum; unique bucket/path | tenant/aggregate/status/id |
| Notification | `workflow.notifications` | tenant, recipient, type/title/body, aggregate, read/created timestamps | recipient/read/created/id |
| Import job | `core.import_jobs` | tenant/actor, resource, format, file metadata, status/counts, errors JSON, request | tenant/created/id |
| Export job | `core.export_jobs` | tenant/actor, resource, format, filters/columns, status/count, file metadata, request | tenant/created/id |
| Report definition | `core.report_definitions` | tenant, code/title, allowlisted source, columns/filters/sort JSON, sharing, owner, status; unique tenant/code | tenant/status/code/id |
| Reference cache | local Drift `reference_cache_entries` | tenant/resource/record key, encrypted payload, server version, cached UTC; local only | tenant/resource/record |

## Out of Scope

- OS-201: Sales, procurement, inventory movement, receivable/payable, journal, cash, or bank posting—Wave 3.
- OS-202: Stock quantities, lots/serials, costing, replenishment, and valuation—Wave 3.
- OS-203: Operational approval decisions—Wave 3 documents consume Wave 2 workflow configuration.
- OS-204: External email/SMS/push delivery workers—outbox processing is implemented in a later integration wave.
- OS-205: OCR, virus-scanning provider integration, or public file links—provider selection and production infrastructure are not approved.
- OS-206: Imports above 500 rows, background chunking, or partial-success mode—requires a separate high-volume import spec.
- OS-207: Arbitrary SQL reports, scheduled delivery, PDF report rendering, or cross-tenant operator reports—later analytics/control waves.
- OS-208: Statutory tax validation or filing—qualified Sri Lankan review and government connectors remain external gates.
- OS-209: Production storage buckets, staging/production projects, real customer data, deployment, push, billing, or signing—separate authorization required.

## Traceability and Test Plan

| Requirement range | Acceptance criteria | Primary evidence |
|---|---|---|
| FR-201–FR-206 | AC-201, AC-220 | pgTAP grants/RLS/audit/idempotency and domain tests |
| FR-207–FR-215 | AC-202–AC-205 | domain exact-decimal tests and pgTAP constraints/RPC tests |
| FR-216–FR-221 | AC-206–AC-207 | pgTAP tenancy/uniqueness and widget CRUD tests |
| FR-222–FR-226 | AC-208–AC-209 | concurrency/idempotency and workflow tests |
| FR-227–FR-231 | AC-210–AC-211 | storage/RLS/lifecycle and notification tests |
| FR-232–FR-238 | AC-212–AC-215 | codec round-trip, atomic import, export, report allowlist tests |
| FR-239–FR-244 | AC-216–AC-218 | widget/golden/offline/conflict/capability tests |
| NFR-201–NFR-215 | AC-201, AC-219–AC-220 | explain/load checks, coverage, advisors, build, launch, visual QA |
