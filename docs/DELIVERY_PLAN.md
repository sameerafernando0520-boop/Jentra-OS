# Jentra OS Delivery Plan

Status date: **2026-08-04**. Audited directly against the working tree.

`DEVELOPMENT_ROADMAP.md` specifies what each module must eventually do. This
document says where the project actually stands, what order to work in, and what
must be true before each phase is allowed to close. `../AGENTS.md` holds the
engineering rules that apply throughout.

Update the status table and the phase checkboxes whenever a module changes.
A stale plan is worse than no plan — the previous roadmap baseline claimed the
Flutter app had not started while nine modules were already running.

---

## 1. Where the project actually is

Nine migrations create 26 tables, a `private` schema of tenant guard helpers,
and seven public RPCs that carry the trusted server logic. The Flutter client
is 132 Dart files with 25 test files, using Riverpod, GoRouter, and the
application/domain/data/presentation layering.

The first commercially meaningful loop — register, create company, select
company, add customer, add product, create invoice, record payment, generate a
journal entry — is implemented end to end. `record_invoice_payment` really does
write the payment, the allocation, the money-account movement, the updated
invoice balance, and the journal entry in one server-side function.

That is a genuine milestone, but the loop has never been reconciled against
expected figures, and the audit behind this document found two ways the client
can bypass it entirely (blockers 2 and 3 below). Treat the numbers as
unverified until Phase 2 closes.

### Module status

| Module | Status | What exists | Main gaps |
| --- | --- | --- | --- |
| Foundation / Auth | Working slice | Sign in, sign up, forgot password, auth gate, session-driven redirects, `profiles`, `handle_new_auth_user` | Email verification and resend, profile screen, invitations, member administration, role and branch management screens |
| Company | Working slice | Onboarding, create, selector, settings overview, `CompanyContextGate`, `initialize_company_defaults`, owner protection triggers | Branch management, team administration, multi-company switching hardening |
| Dashboard | Working slice | `DashboardScreen` backed by the `get_dashboard_summary` RPC | KPI drill-down, recent activity feed, permission-filtered quick actions, cache and stale labelling |
| CRM | Partial | Customers on the shared `parties` table with `search_customers`, list, detail, create, edit | Suppliers, leads, activities, contacts, addresses, attachments, duplicate detection |
| Inventory | Partial, with a defect | Products with `search_products`, warehouse list, stock overview, `stock_balances` and `stock_movements` tables | Stock balances are computed and written client-side without a transaction (blocker 2). Adjustments, transfers, category management UI, costing, valuation, reorder reporting |
| Sales | Partial | Invoices with the `save_sales_invoice` RPC, `InvoiceCalculationService`, list, detail, create, edit, record-payment dialog | Quotations, sales orders, document conversion, `tax_rates`, credit notes, PDF and share |
| Finance | Partial | `money_accounts`, `payments`, `payment_allocations`, finance screen, `record_invoice_payment` RPC | Outgoing payments, allocation workspace, receivables and payables aging, statements, reversal and void |
| Accounting | Partial | `chart_of_accounts`, `journal_entries`, `journal_lines`, `ensure_company_default_accounts`, accounting screen | General ledger, trial balance, P&L, balance sheet, manual journal editor, `accounting_periods`, event queue, reversal |
| AI Assistant | Scaffold, no model | `ai_conversations`, `ai_messages`, `ai_insights`, `get_company_business_summary`, `AiPermissionGuard`, `BusinessContextBuilder`, chat, insights and settings screens. Replies are deterministic templates composed from real company figures, and insights are seeded from hard-coded templates | No Edge Function gateway and therefore no LLM provider at all. No tool allow-list, action approval, or AI audit log |
| Subscription | Not started | Route placeholder | Everything: `plans`, `company_subscriptions`, entitlements, webhooks, usage limits |
| Settings | Not started | Route placeholder | Company preferences, currency, tax, numbering, user preferences |
| Purchasing / HR / Projects | Not started | — | Out of scope until the sales-to-accounting chain is closed |

Tables referenced by the roadmap that **do not exist yet**: `audit_logs`,
`purchase_documents`, `tax_rates`, `accounting_event_queue`,
`accounting_periods`, `plans`, `company_subscriptions`, `attachments`, `leads`,
`activities`, `units_of_measure`. Do not write code that assumes them.

---

## 2. Open blockers

These are not features. They gate everything after Phase 0.

1. **The project folder is not under version control.** `git` reports no
   repository. There is no history, no branches, no way to revert a bad agent
   edit, and no checkpoint commits. Every change made so far is unprotected.
   This is the single highest-priority item in the project.
2. **Stock balances are written from the client, unsafely.**
   `InventoryService.recordStockMovement` inserts the movement, reads
   `stock_balances`, computes the new quantity in Dart, then writes it back —
   three round trips with no transaction and no row lock. Two concurrent
   movements silently lose an update. The schema allows it because
   `stock_balances` grants `insert, update` to `authenticated`. This breaks the
   project's own rule that stock is server-computed. Fix with a transactional
   `post_stock_movement` RPC and revoke direct write access.
3. **Journals can be written directly by the client.** `journal_entries` and
   `journal_lines` grant `insert` to `authenticated`, so a caller holding only
   the publishable key can post an unbalanced or fabricated journal without
   going through `record_invoice_payment`. Revoke and route through server
   functions before anyone relies on the ledger.
4. **The Supabase service-role credential in older external notes has not been
   rotated.** It must be rotated before any production or shared use, and the
   new value must never enter this repository.
5. **No CI.** `flutter analyze` and `flutter test` run only when someone
   remembers. Nothing enforces the gates below.
6. **Branding leftovers.** Android application ID `com.ibook.i_book`,
   `android/i_book_android.iml`, and the `i Book` title in `README.md`. Low
   urgency, but the Android ID must be settled before the first store submission
   because changing it later breaks upgrade paths.
7. **Duplicate `AiAssistantService` name** across
   `lib/data/services/` (abstract Edge Function contract) and
   `lib/features/ai_assistant/data/` (concrete Supabase service). Rename when
   the Edge Function lands.

---

## 3. Phases

A phase closes only when every box is checked. Do not begin a later phase while
a security or data-integrity blocker is open in one of its dependencies.

### Phase 0 — Protect the work (do this first)

- [x] `git init`, a `.gitignore` that excludes `build/`, `.dart_tool/`, and any
      real env file, then an initial commit of the current tree
- [x] Confirm no secret is present in the tree before that first commit
- [ ] Rotate the exposed service-role credential and record only that it was
      rotated, never the value
- [x] Baseline `flutter analyze` and `flutter test`, and record the result
- [ ] Push to a private remote

Exit gate: the current state is recoverable and no live credential is exposed.

### Phase 1 — Verify the foundation against the hosted project

- [ ] `supabase db reset` locally, then `supabase test db` green
- [ ] Security Advisor and Performance Advisor clean, or every finding
      documented with a reason
- [ ] pgTAP tenant-isolation test per table: a member reads, a non-member
      holding a known UUID cannot
- [ ] Manually walk register → create company → select company → dashboard on
      both a mobile target and web
- [ ] Confirm a user in two companies can switch without state from the first
      company leaking into the second

Exit gate: the tenant boundary is proven, not assumed.

### Phase 2 — Close the money loop

The chain invoice → payment → journal entry is the product's core claim. It is
implemented but unproven.

- [ ] Reconcile: create an invoice, record a partial payment, then a second
      payment, and confirm `balance_due`, `paid_amount`, and the resulting
      journal lines are correct and balanced
- [ ] Confirm total debits equal total credits for every generated journal
- [ ] Confirm `record_invoice_payment` is idempotent under a retried call and
      rejects an amount above the outstanding balance
- [x] Replace client-side stock balance arithmetic with a transactional
      `post_stock_movement` RPC, then revoke `insert, update` on
      `stock_balances` from `authenticated` (blocker 2)
- [x] Revoke `insert` on `journal_entries` and `journal_lines` from
      `authenticated` and route all posting through server functions (blocker 3)
- [x] Re-audit: grep the client for direct writes to totals, balances, journals
      and stock, and confirm none remain
- [x] Add `audit_logs` and write to it from the posting paths
- [ ] Widget and state tests for the failure paths, not just the happy path

Exit gate: an accountant could trust the numbers.

### Phase 3 — Complete the accounting reports

- [ ] `accounting_periods` with period locking
- [ ] General ledger, trial balance, profit and loss, balance sheet as
      parameterized report functions
- [ ] Trial balance debits equal credits; the balance sheet equation reconciles
- [ ] Manual journal editor with the balanced-entry constraint enforced server-side
- [ ] Journal reversal flow, with posted journals remaining immutable

Exit gate: statutory reports reconcile to the ledger on fixture data.

### Phase 4 — Finish the operational modules

- [ ] Finance: outgoing payments, allocation workspace, receivables and payables
      aging, customer and supplier statements, payment reversal
- [ ] Inventory: adjustments and transfers through a transactional posting
      service, costing, valuation and reorder reports
- [ ] Sales: quotations and sales orders, document conversion with replay
      protection, `tax_rates`, credit notes, PDF export
- [ ] CRM: suppliers, leads with atomic conversion, activities, contacts,
      addresses, attachments on private company-prefixed storage paths
- [ ] Settings: currency, tax, document numbering, company preferences

Exit gate: an SME could run a full month of trading in the product.

### Phase 5 — AI assistant with a real provider

- [ ] Edge Function gateway holding the provider key; no key in Flutter
- [ ] Allow-listed, company-scoped read-only tools; no arbitrary SQL from user text
- [ ] Prompt-injection tests using both user input and stored business text
- [ ] Answers cite their evidence and state data freshness
- [ ] Read-only first; mutating actions only later, behind explicit preview,
      confirmation, idempotency keys, and audit records

Exit gate: the assistant cannot read or change another company's data under
adversarial input.

### Phase 6 — Commercial hardening

- [ ] `plans`, `company_subscriptions`, `subscription_events`, usage counters
- [ ] Entitlements evaluated server-side; Flutter cannot mutate subscription state
- [ ] Signature-verified, idempotent payment-provider webhooks
- [ ] Feature access fails closed when subscription state is unavailable
- [ ] Trial, grace period, past-due, cancellation and reactivation transitions tested
- [ ] Accessibility, localization, timezone and currency behaviour verified
- [ ] CI running analyze, test, and the database tests on every change
- [ ] Logging, metrics, alerts, and an operational runbook

Exit gate: ready to charge money.

---

## 4. Next three actions

1. Initialize git, verify no secret is staged, and commit the current tree.
2. Rotate the service-role credential.
3. Close blockers 2 and 3 — move stock balance updates and journal posting
   behind transactional server functions and revoke the direct client grants.
   Until this is done, both stock quantities and the ledger can be corrupted by
   ordinary concurrent use or by anyone holding the publishable key.

Then run `supabase db reset` and `supabase test db`, and walk the register →
company → dashboard → customer → product → invoice → payment loop by hand,
writing down every defect found rather than fixing them mid-walk.

Do not start a new feature module until those three are done. The project's
risk right now is concentrated in unprotected work and unsafe writes to money
and stock, not in missing screens.
