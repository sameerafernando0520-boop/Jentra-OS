# Jentra OS Development Roadmap

## Purpose and scope

This document defines the production development sequence for **Jentra OS**, an
AI Business Operating System for SMEs built with Flutter and Supabase. Work must
follow the module order in this roadmap because each stage depends on security,
data contracts, and workflows established by the previous stage.

Jentra OS is an AI Business Operating System that connects CRM, sales,
purchasing, inventory, finance, accounting, employees, projects, subscriptions,
analytics, and AI-assisted business intelligence in one secure multi-company
platform.

This roadmap is the *specification* of each module: purpose, tables, screens,
services, acceptance criteria, and testing checklist. It deliberately describes
the finished state, so a module listed here is not evidence that the module
exists. For what is actually built today and what to work on next, read
`DELIVERY_PLAN.md`. For engineering rules, read `../AGENTS.md`.

Earlier temporary product names were `i Connect` and `i Book`. Database tables,
functions, policies, and migration filenames are never renamed for branding.

The roadmap covers mobile and web clients, PostgreSQL schema and migrations,
Supabase Auth, Row Level Security (RLS), Storage, Edge Functions, services,
repositories, and automated verification. It is not a feature specification or
a substitute for module-level technical designs.

## Current baseline

Audited against the working tree on 2026-08-04. An earlier version of this
section claimed Flutter had not started; that was long out of date. Keep the
authoritative, dated status in `DELIVERY_PLAN.md` and treat the summary below as
a pointer only.

- 9 migrations are applied, creating 26 tables, `private` schema tenant guard
  helpers, and 7 public RPCs that carry the trusted server logic.
- The Flutter client is real and running: 132 Dart files, 25 test files, using
  Riverpod for injection and state, GoRouter for mobile/web navigation, and the
  repository/service layering described in `../AGENTS.md`.
- Modules with working vertical slices: authentication, company onboarding and
  selection, dashboard, CRM customers, inventory products and warehouses, sales
  invoices, finance money accounts and payments, accounting journals and chart
  of accounts, and an AI assistant shell.
- Subscription and settings are route placeholders. Purchasing, HR, projects,
  attachments/storage, and `audit_logs` have not been started.
- The AI assistant has no language model behind it because no Edge Functions
  exist yet. It answers with deterministic templates composed from real company
  figures, which is safe but is not the module described in section 8.
- Two blockers carried from the original baseline are still open: the external
  service-role credential has not been rotated, and the project folder is not
  under version control.

## Delivery rules for every module

1. All business records must be scoped by `company_id`.
2. Parent-child relationships must enforce the same company using composite
   foreign keys or an equally strong database constraint.
3. RLS and explicit Data API grants must ship in the same migration as a table.
4. Flutter may use only the Supabase URL and publishable key. Service-role and
   secret keys are restricted to trusted server environments.
5. Financial totals, stock quantities, subscription status, and other critical
   state must be calculated or changed through transactional server operations.
6. Every migration must pass rollback validation, database tests, Security
   Advisor, and Performance Advisor before deployment.
7. Every module must support loading, empty, success, validation-error,
   permission-denied, offline, and retry states where applicable.
8. Accessibility, localization, responsive layouts, auditability, observability,
   and safe error handling are part of acceptance—not later cleanup work.

---

## 1. Foundation

### Purpose

Establish secure application startup, authentication, user identity, company
onboarding, membership, role-based access, and current-company context. Every
later module depends on this tenant boundary.

### Database tables used

- Supabase-managed `auth.users`
- `profiles`
- `companies`
- `branches`
- `roles`
- `permissions`
- `role_permissions`
- `company_memberships`
- `company_member_branches`
- `company_settings`

The core tables already exist. A production invitation workflow may require a
separate `company_invitations` table containing a hashed token, target email,
role, expiry, inviter, status, and accepted user ID.

### Main screens

- Startup/configuration error screen
- Splash and authenticated-session gate
- Sign in
- Sign up
- Email verification and resend
- Forgot/reset password
- User profile
- Create company onboarding flow
- Join/accept company invitation flow
- Company selector
- Company profile and settings
- Branch management
- Team member list
- Invite member
- Member role and branch assignment
- Role and permission management

### Services/repositories required

- `EnvironmentConfig` and startup configuration validator
- `SupabaseClientProvider`
- `AuthRepository`
- `AuthSessionController`
- `ProfileRepository`
- `CompanyRepository`
- `CompanyOnboardingService`
- `CompanyMembershipRepository`
- `CompanyInvitationService` backed by an Edge Function
- `RolePermissionRepository`
- `BranchRepository`
- `CurrentCompanyController` with safe local persistence
- `AuthorizationService` for UI capability checks
- Centralized app router and auth/company route guards
- Structured logging and user-safe error mapping

### Acceptance criteria

- The app refuses to start with missing or malformed public configuration.
- No service-role, secret, database password, or private AI key exists in Flutter
  source, assets, logs, build arguments, or committed environment files.
- Sign-up creates exactly one profile linked to the authenticated user.
- Sign-in, sign-out, session refresh, password recovery, and email verification
  work on supported mobile and web platforms.
- Creating a company atomically creates its default branch, settings, roles,
  owner membership, permissions, and owner branch assignment.
- A user can belong to multiple companies and switch current company without
  leaking state from the previous company.
- Non-members cannot read or mutate a company, its roles, memberships, branches,
  or settings, even when UUIDs are known.
- Company ownership cannot be changed through direct table updates.
- The owner membership and owner role cannot be removed through normal member
  administration.
- Invitations expire, are single-use, and cannot assign a role from another
  company.
- UI permissions improve usability but never replace database authorization.

### Testing checklist

- Unit-test configuration parsing, error mapping, and current-company state.
- Widget-test every authentication and onboarding state.
- Integration-test sign-up, profile creation, sign-in, refresh, and sign-out.
- Test company creation rollback when any default record fails.
- Test two users in separate companies against every foundation table.
- Test a multi-company user switching between tenants repeatedly.
- Test forged company, role, membership, and branch UUIDs.
- Test invitation expiry, replay, wrong-email acceptance, and suspended users.
- Test owner-role and owner-membership protection.
- Run pgTAP foundation tests, RLS tests, and Supabase advisors.
- Verify no credential is printed in debug, crash, or analytics logs.

---

## 2. Core Dashboard

### Purpose

Give the signed-in user an accurate, fast, role-aware summary of the selected
company and direct access to the most common permitted actions.

### Database tables used

- Foundation tables, especially `companies`, `company_memberships`, and
  `company_settings`
- `parties`
- `leads`
- `activities`
- `sales_documents`
- `purchase_documents`
- `payments`
- `products`
- `stock_balances`
- `ai_insights`
- `audit_logs`

Dashboard values should be returned through a company-scoped summary RPC or
security-invoker view rather than many independent client queries.

### Main screens

- Dashboard/home
- Current company selector
- Company/branch filter sheet
- KPI detail drill-down
- Recent activity list
- Quick action launcher
- Dashboard customization or visibility settings, if approved

### Services/repositories required

- `DashboardRepository`
- Company-scoped `get_dashboard_summary` RPC
- `KpiDefinitionService`
- `RecentActivityRepository`
- `QuickActionRegistry`
- `CurrentCompanyController`
- Dashboard refresh coordinator
- Currency, date, number, and timezone formatting services
- Cache policy for last successful non-sensitive dashboard snapshot

### Acceptance criteria

- Every dashboard request requires a selected active company membership.
- Switching company clears stale dashboard data before loading the new tenant.
- KPI definitions document formula, date range, currency, exclusions, and data
  freshness.
- KPI values match source documents and payments for the same period.
- Recent activity contains only records visible to the current user.
- Quick actions appear only when the user has the required permission.
- Dashboard startup uses a bounded number of server requests and avoids N+1
  queries.
- Pull-to-refresh and retry never duplicate activity or mix company data.
- Empty and partially configured companies show useful onboarding actions.

### Testing checklist

- Unit-test each KPI formula against fixed database fixtures.
- Test company switching while a dashboard request is in flight.
- Test owner, admin, accountant, sales, warehouse, and viewer dashboards.
- Test empty company, high-volume company, and partial-data scenarios.
- Test timezone boundaries, month-end, year-end, and currency formatting.
- Test offline cached state and stale-data labeling.
- Profile RPC latency and verify supporting indexes.
- Confirm dashboard queries cannot reveal cross-company counts or identifiers.

---

## 3. CRM

### Purpose

Maintain a single company-scoped source of truth for customers, suppliers,
prospects, contacts, addresses, follow-ups, and relationship history.

### Database tables used

- `parties`
- `party_contacts`
- `party_addresses`
- `leads`
- `activities`
- `attachments`
- `audit_logs`
- Foundation membership, branch, and permission tables

Customers and suppliers should remain roles of a shared `parties` entity rather
than separate duplicate master records.

### Main screens

- Customer list and search
- Customer detail
- Create/edit customer
- Supplier list and search
- Supplier detail
- Create/edit supplier
- Lead pipeline
- Lead detail and conversion
- Activity timeline
- Create/edit activity
- Contacts and addresses editor
- Attachment viewer/uploader

### Services/repositories required

- `PartyRepository`
- `CustomerRepository` and `SupplierRepository` domain adapters
- `LeadRepository`
- `ActivityRepository`
- `LeadConversionService`
- `AttachmentRepository`
- Company-scoped search and pagination service
- Duplicate-party detection service
- Contact/address validation service
- CRM audit event producer

### Acceptance criteria

- Every CRM row is company-scoped and all child records enforce the parent
  company through composite constraints.
- Customer/supplier conversion does not duplicate contacts or addresses.
- Lead conversion is atomic and records who converted it and when.
- Search is paginated, indexed, case-insensitive, and safe for large datasets.
- Duplicate email, phone, tax number, and normalized-name warnings are defined
  without blocking legitimate duplicates unnecessarily.
- Activities support assignment, due dates, completion, and overdue states.
- Users without `crm.write` have read-only access only where policy permits.
- Attachments use private storage paths prefixed by company ID and protected by
  Storage RLS.
- Deletes follow an explicit archive/soft-delete policy where records are
  referenced by financial documents.

### Testing checklist

- Test CRUD and pagination for every party type.
- Test customer and supplier views of a `both` party.
- Test cross-company contact, address, lead, and attachment references.
- Test duplicate detection and normalization edge cases.
- Test lead conversion success, retry, and transaction rollback.
- Test activity assignment to suspended or non-member users.
- Test storage upload, read, update/upsert, and delete policies.
- Test permissions for CRM writer, viewer, and unrelated tenant users.
- Load-test search and activity timelines with production-scale fixtures.

---

## 4. Sales

### Purpose

Support the controlled sales lifecycle from quotation through sales order,
invoice, payment, and accounting/inventory handoff.

### Database tables used

- `sales_documents`
- `sales_document_items`
- `parties`
- `products`
- `tax_rates`
- `payments`
- `payment_allocations`
- `branches`
- `company_settings`
- `attachments`
- `stock_movements`
- `accounting_event_queue`
- `audit_logs`

### Main screens

- Quotation list, editor, preview, and detail
- Sales order list, editor, and detail
- Invoice list, editor, preview, and detail
- Reusable sales document item editor
- Document conversion flow
- Payment entry
- Payment allocation
- Customer statement
- PDF/share/export flow
- Overdue invoice view

### Services/repositories required

- `SalesDocumentRepository`
- `SalesDocumentDraftService`
- Atomic `DocumentNumberService`
- Server-side totals and tax calculation service
- `SalesConversionService`
- `InvoicePostingService`
- `PaymentRepository`
- `PaymentAllocationService`
- PDF rendering/export service
- Email/share Edge Function
- Sales-to-stock and sales-to-accounting event publisher
- Idempotency key service for posting and payment operations

### Acceptance criteria

- Document numbers are unique per company/type and allocated atomically.
- Line subtotal, discount, tax, grand total, paid total, and balance are computed
  by trusted server logic using documented rounding rules.
- A source document can be converted without duplicate target documents.
- Posted invoices are immutable; corrections use credit notes or controlled
  reversal workflows.
- Payment allocation cannot exceed the payment amount or document balance.
- Customer, product, tax, branch, document, payment, and allocation records must
  all belong to the same company.
- Inventory and accounting events are idempotent and created in the same
  transaction as the business state change.
- PDF output matches stored totals and company identity.
- Users cannot directly change posted totals, paid balances, or posting status.

### Testing checklist

- Test all document types and valid status transitions.
- Test multi-line totals, inclusive/exclusive tax, discounts, and rounding.
- Test concurrent document number allocation.
- Test quotation-to-order-to-invoice conversion and replay protection.
- Test partial, full, excess, reversed, and voided payments.
- Test cross-company product, party, tax, and payment references.
- Test immutable posted documents and controlled corrections.
- Compare generated PDF values with database values.
- Test posting rollback when stock or accounting event creation fails.
- Run performance tests on document list, search, and statement queries.

---

## 5. Inventory

### Purpose

Maintain reliable product master data and a traceable stock ledger across
warehouses and branches without allowing clients to manipulate balances.

### Database tables used

- `units_of_measure`
- `product_categories`
- `brands`
- `products`
- `warehouses`
- `stock_balances`
- `stock_movements`
- `branches`
- `purchase_documents`
- `purchase_document_items`
- `sales_documents`
- `sales_document_items`
- `audit_logs`

A production transfer workflow may require `stock_transfers` and
`stock_transfer_items` so paired warehouse movements share one controlled
business document.

### Main screens

- Product list and search
- Product create/edit/detail
- Category management
- Brand and unit management
- Warehouse management
- Stock-on-hand by warehouse
- Stock movement history
- Stock adjustment
- Warehouse transfer
- Reorder/low-stock report
- Inventory valuation report

### Services/repositories required

- `ProductRepository`
- `CategoryRepository`
- `WarehouseRepository`
- `StockQueryRepository`
- Transactional `StockPostingService`
- `StockAdjustmentService`
- `StockTransferService`
- Costing/average-cost service
- Reservation service if sales orders reserve stock
- Reorder recommendation service
- Barcode/SKU validation and scanning adapter

### Acceptance criteria

- `stock_balances` cannot be inserted, edited, or deleted directly by Flutter.
- Every balance change is backed by an immutable stock movement.
- Movement posting and balance update occur in one transaction with row locking.
- Duplicate source events do not create duplicate stock movements.
- Negative-stock behavior is explicitly configured and consistently enforced.
- Transfers create balanced transfer-out and transfer-in movements atomically.
- Product, warehouse, branch, and source document belong to the same company.
- Average-cost calculations are reproducible and documented.
- Stock reports reconcile balances to the movement ledger.
- Archived products remain visible on historical documents.

### Testing checklist

- Test opening, purchase, sale, return, adjustment, and transfer movements.
- Test concurrent sales against the same stock row.
- Test negative-stock allowed and denied configurations.
- Test duplicate posting/idempotency behavior.
- Test average-cost changes across purchases and returns.
- Test cross-company product and warehouse references.
- Reconcile generated balances to summed movements for every fixture.
- Test high-volume stock history pagination and indexes.
- Test offline retry without duplicate movements.

---

## 6. Finance

### Purpose

Manage operational cash, bank, customer receivable, supplier payable, and
payment allocation workflows before general-ledger reporting is introduced.

### Database tables used

- `money_accounts`
- `payments`
- `payment_allocations`
- `sales_documents`
- `purchase_documents`
- `parties`
- `branches`
- `accounting_settings`
- `accounting_event_queue`
- `audit_logs`

### Main screens

- Cash and bank account list
- Money account detail and transaction history
- Incoming payment
- Outgoing payment
- Payment allocation workspace
- Customer receivables aging
- Supplier payables aging
- Customer statement
- Supplier statement
- Cash-flow summary
- Payment reversal/void flow

### Services/repositories required

- `MoneyAccountRepository`
- `PaymentRepository`
- Transactional `PaymentService`
- `PaymentAllocationService`
- `ReceivablesRepository`
- `PayablesRepository`
- Aging report query service
- Customer/supplier statement service
- Payment reversal service
- Finance-to-accounting event publisher
- Reconciliation-ready import abstraction for future bank feeds

### Acceptance criteria

- Money-account balances are derived or transactionally maintained by trusted
  server code and cannot be edited directly by the client.
- Incoming payments allocate only to eligible sales documents; outgoing
  payments allocate only to eligible purchase documents.
- Allocation totals cannot exceed payment amount or outstanding document amount.
- Receivable and payable aging agrees with document balances as of a selected
  date.
- Confirmed payments are immutable; corrections use void/reversal records.
- Reversal restores allocations and balances exactly once.
- Currency and exchange-rate rules are explicit for every payment.
- Financial access is restricted to authorized roles and fully audited.

### Testing checklist

- Test incoming and outgoing payment lifecycles.
- Test partial allocation across multiple documents.
- Test one document paid by multiple payments.
- Test over-allocation and cross-direction allocation rejection.
- Test payment reversal, repeated reversal, and rollback behavior.
- Test aging buckets at date boundaries and after credit/debit notes.
- Test cross-company accounts, parties, documents, and allocations.
- Reconcile statements, account balances, and document balances.
- Test concurrent allocations against the same document.

---

## 7. Accounting Engine

### Purpose

Convert validated business events into an immutable double-entry ledger and
produce auditable statutory and management reports.

### Database tables used

- `chart_of_accounts`
- `accounting_settings`
- `journal_entries`
- `journal_lines`
- `accounting_event_queue`
- `sales_documents`
- `purchase_documents`
- `payments`
- `stock_movements`
- `parties`
- `products`
- `branches`
- `audit_logs`

Required production additions should include `accounting_periods` for period
locking and may include versioned `accounting_posting_rules` for traceable event
mapping. General ledger, trial balance, profit and loss, and balance sheet should
prefer parameterized report functions or security-invoker views over duplicated
summary tables unless measured performance requires materialization.

### Main screens

- Chart of accounts
- Accounting configuration
- Manual journal editor
- Journal list and detail
- General ledger
- Trial balance
- Profit and loss
- Balance sheet
- Accounting event/error queue
- Fiscal period management and lock flow
- Journal reversal flow

### Services/repositories required

- `ChartOfAccountsRepository`
- `AccountingSettingsRepository`
- `JournalRepository`
- Transactional `JournalPostingService`
- `AccountingEventProcessor` running in a trusted Edge Function/worker
- Versioned posting-rules engine
- General ledger query service
- Trial balance service
- Profit-and-loss service
- Balance-sheet service
- Period lock service
- Journal reversal service
- Reconciliation and accounting health-check service

### Acceptance criteria

- Every posted journal contains at least two lines and total debits equal total
  credits before posting.
- Journal lines and posted journal headers are immutable.
- Corrections create linked reversing journals; they never rewrite history.
- Posting requires `finance.write` and verified membership in the journal company.
- Every source business event produces at most one active posting.
- Event processing is retryable, idempotent, and records failures without losing
  the source event.
- Closed accounting periods reject new or modified postings.
- General ledger totals reconcile to the trial balance.
- Trial balance debits equal credits.
- Profit-and-loss closing result and balance sheet accounting equation reconcile.
- Report queries support date, company, branch, account, and party filters without
  bypassing RLS.

### Testing checklist

- Unit-test every posting rule with expected debit and credit lines.
- Test unbalanced, empty, duplicate, and unauthorized journals.
- Test invoice, credit note, bill, debit note, payment, stock, and reversal events.
- Test event retries and exactly-once accounting outcomes.
- Test posting and reversal across open and closed periods.
- Reconcile general ledger, trial balance, P&L, and balance sheet fixtures.
- Test retained earnings and year-end closing behavior.
- Test cross-company account, party, product, and journal references.
- Run high-volume report performance tests and verify query plans/indexes.
- Confirm audit history can reconstruct every posted journal decision.

---

## 8. AI Assistant

### Purpose

Provide company-scoped conversational analysis, proactive insights, and report
explanations while preserving authorization, auditability, privacy, and human
control over business actions.

### Database tables used

- `ai_conversations`
- `ai_messages`
- `ai_insights`
- `ai_action_logs`
- `audit_logs`
- Read-only, company-scoped reporting functions/views from CRM, sales,
  inventory, finance, and accounting

AI provider credentials must exist only in trusted Edge Function secrets. The AI
must not query arbitrary tables or receive a service-role key in Flutter.

### Main screens

- AI assistant conversation list
- AI conversation
- Suggested business questions
- Insight inbox
- Insight detail and evidence
- Report explanation panel
- Proposed action review/approval
- AI privacy, data-use, and history settings

### Services/repositories required

- `AiConversationRepository`
- `AiInsightRepository`
- Trusted AI gateway Edge Function
- Company-scoped business query layer with allow-listed tools
- Report context builder
- Report explanation service
- Prompt/template registry with versioning
- Tool authorization and permission evaluator
- Action proposal and explicit approval service
- PII minimization/redaction service
- Token, cost, timeout, retry, and rate-limit controller
- AI action audit logger
- Model evaluation and regression suite

### Acceptance criteria

- Every conversation, message, insight, query, and action log is company-scoped.
- The AI can access only allow-listed tools and fields authorized for the user.
- Natural-language input cannot bypass RLS, tool permissions, or company scope.
- Business answers cite the report/query evidence and state data freshness.
- The assistant distinguishes calculated facts from generated interpretation.
- Mutating actions require an explicit preview and user confirmation.
- High-impact actions use idempotency keys and produce audit records.
- Prompt injection in stored business text cannot redefine tools or system rules.
- Provider failures, timeouts, and rate limits degrade safely without losing user
  messages or duplicating actions.
- Users can delete eligible conversation history without deleting statutory
  financial audit records.

### Testing checklist

- Test company and role isolation for every AI tool.
- Test prompt injection from user input and retrieved database content.
- Test unsupported, ambiguous, stale, and no-data questions.
- Compare AI calculations with deterministic report outputs.
- Test action preview, approval, cancellation, retry, and duplicate submission.
- Test PII minimization and absence of secrets in prompts/logs.
- Test provider timeout, malformed output, refusal, and rate-limit handling.
- Run fixed evaluation datasets for correctness and hallucination regression.
- Review token usage, latency, and cost budgets.
- Perform adversarial security review before enabling mutating tools.

---

## 9. Subscription System

### Purpose

Control commercial plans, trials, entitlements, usage limits, and subscription
state without allowing the frontend to grant itself paid features.

### Database tables used

- `plans`
- `company_subscriptions`
- `subscription_events`
- `companies`
- `company_memberships`
- `audit_logs`

Production usage enforcement will likely require `subscription_usage_counters`
or a similarly transactional usage ledger. Provider webhook idempotency must be
enforced with a unique provider event identifier.

### Main screens

- Plan comparison
- Current plan and subscription status
- Trial status and countdown
- Usage and limits
- Upgrade/downgrade flow
- Billing portal launcher
- Subscription issue/past-due screen
- Feature-locked explanation and upgrade prompt
- Admin subscription event/support view

### Services/repositories required

- `PlanRepository`
- Read-only `SubscriptionRepository` for Flutter
- Trusted subscription management Edge Function
- Verified payment-provider webhook handler
- `EntitlementService`
- `FeatureAccessController`
- Transactional usage-limit service
- Trial lifecycle service
- Subscription event/idempotency repository
- Billing portal integration
- Subscription notification service
- Reconciliation job between provider and local subscription state

### Acceptance criteria

- Flutter cannot insert, update, or delete subscription state or provider events.
- Webhooks are signature-verified, idempotent, ordered safely, and auditable.
- Plan entitlements and numerical limits are evaluated server-side.
- Trial start, expiry, grace period, past-due, cancellation, and reactivation
  transitions are explicitly defined and tested.
- Feature access fails closed when subscription state is unavailable or invalid.
- Limits are enforced transactionally under concurrent requests.
- Downgrades define behavior for data exceeding the new plan without destructive
  automatic deletion.
- Company owners can manage billing; ordinary members cannot.
- Provider state and local state are periodically reconciled.
- Subscription changes never weaken tenant RLS or expose service credentials.

### Testing checklist

- Test every subscription status transition.
- Test duplicate, delayed, out-of-order, invalid-signature, and replayed webhooks.
- Test trial expiry and grace-period boundaries using controlled clocks.
- Test each plan entitlement and usage limit at below/equal/above thresholds.
- Test concurrent limit consumption.
- Test upgrades, downgrades, cancellation, reactivation, and failed payment.
- Test owner versus non-owner billing access.
- Test provider/local reconciliation and recovery from missed webhooks.
- Confirm frontend attempts to mutate subscription tables are denied.
- Run security review against forged plan IDs, company IDs, and provider events.

---

## Production release gates

A module is complete only when all of the following are true:

- Database migrations are versioned, replayable, reviewed, and deployed through
  the established migration workflow.
- Required tables have RLS, explicit grants, indexes, constraints, and tenant
  isolation tests.
- Security Advisor has no unresolved warnings attributable to the module.
- Performance Advisor findings are resolved or documented with evidence.
- Flutter analyzer and tests pass with pinned dependencies and committed lockfiles.
- Mobile and web happy paths and failure paths are verified on real runtimes.
- Accessibility, responsive layout, localization, and timezone/currency behavior
  are verified.
- Logs, metrics, alerts, retry behavior, and operational runbooks exist.
- No secret, personal data, payment data, or sensitive business content is logged
  unnecessarily.
- Acceptance criteria and testing checklist evidence are linked from the module's
  delivery record.

## Recommended milestone boundaries

1. Foundation backend and auth client
2. Company onboarding and membership administration
3. Dashboard shell and company context
4. CRM
5. Sales documents and payments
6. Inventory and purchases integration
7. Finance operations
8. Accounting posting and reports
9. AI read-only assistant, followed later by approved actions
10. Subscription enforcement and commercial launch hardening

Do not start a later milestone while a security or data-integrity blocker remains
open in an earlier dependency.
