# Jentra OS — Engineering Instructions

Read this file before writing any code. It is the authoritative engineering
contract for this repository. If a request conflicts with the invariants in
section 3, raise the conflict instead of silently working around it.

**Jentra OS is an AI Business Operating System that connects CRM, sales,
purchasing, inventory, finance, accounting, employees, projects, subscriptions,
analytics, and AI-assisted business intelligence in one secure multi-company
platform.**

This is a commercial multi-tenant SaaS product, not a demo. Correctness of money,
stock, and tenant isolation outranks delivery speed on every decision.

---

## 1. Naming

| Context | Correct value |
| --- | --- |
| Product / user-facing name | `Jentra OS` |
| Dart package | `jentra_os` |
| Code prefix where needed | `jentra` |
| Supabase dev project label | `jentra-os-dev` |

`i Connect` and `i Book` were earlier temporary names. Replace them in
user-facing strings and documentation when you touch the surrounding code.

**Never rename for branding reasons:** database tables, columns, PostgreSQL
functions, RLS policies, migration filenames, or existing Supabase project IDs,
URLs, and keys. The `i_connect_*` SQL and blueprint filenames stay as they are.

Known outstanding leftovers (do not fix opportunistically; they need their own
change with a rebuild/reinstall plan): Android application ID
`com.ibook.i_book`, `android/i_book_android.iml`, and the `i Book` title in
`README.md`.

---

## 2. Stack and versions

Pinned in `pubspec.yaml` / `pubspec.lock` — do not bump without being asked.

- Dart SDK `^3.12.2`, Flutter targeting mobile **and** web
- `flutter_riverpod ^3.3.2` — dependency injection and application state
- `go_router ^17.3.0` — routing for mobile and web
- `supabase_flutter ^2.16.0` — Auth, Data API, RPC
- `flutter_lints ^6.0.0` — lint baseline via `analysis_options.yaml`

There is no code generation in this project. No `build_runner`, no `freezed`, no
`json_serializable`. Write models and `fromJson`/`toJson` by hand to match the
existing style. Do not introduce a codegen dependency without asking.

---

## 3. Non-negotiable invariants

Violating any of these is a defect, regardless of whether tests pass.

**Tenancy**

1. Every business record is scoped by `company_id`. Every query filters on it.
2. Repositories receive `companyId` as an explicit parameter. They never read it
   from mutable global state. See `lib/data/repositories/company_scoped_repository.dart`.
3. Parent-child relationships enforce the same company through composite foreign
   keys, not application-level checks alone.
4. Row Level Security is the final authorization boundary. UI permission checks
   are usability affordances only, never a substitute.
5. Never disable RLS. Ship RLS policies and explicit Data API grants in the same
   migration that creates a table.

**Secrets**

6. Flutter receives only the Supabase project URL and a client-safe
   publishable/anonymous key, supplied at build time via `--dart-define`.
7. A `service_role` key, a legacy service-role JWT, an `sb_secret_*` key, a
   database password, or an AI provider key must never appear in Dart source,
   assets, committed env files, logs, build arguments, or error messages.
   `EnvConfig.configurationIssues` actively rejects `sb_secret_` keys — keep that
   guard.
8. AI provider credentials live only in Edge Function secrets.

**Money, stock, and other critical state**

9. Financial totals, paid balances, stock balances, journal postings, and
   subscription entitlements are computed or mutated by trusted server code
   inside a transaction — a PostgreSQL function called over RPC, or an Edge
   Function. Never by the client.
10. `stock_balances` is never inserted, updated, or deleted from Flutter. Every
    balance change is backed by an immutable `stock_movements` row.
11. Posted invoices and posted journals are immutable. Corrections create
    reversing or credit documents; they never rewrite history.
12. Posting and payment operations must be idempotent under retry.

**Process**

13. No business logic inside widgets. See section 4.
14. Do not make unrelated changes, drive-by refactors, or dependency bumps
    while working a task.
15. Never claim a validation, build, or test passed unless you actually ran the
    command and read the output.
16. Never perform a destructive database operation (`drop`, `truncate`, data
    backfill without a filter) without explicit confirmation.

---

## 4. Architecture

Feature-first clean architecture. Copy the shape of an existing module rather
than inventing a new pattern — `lib/features/sales/` is the fullest example.

```
lib/
  main.dart
  app/
    app.dart        router.dart      theme.dart
  core/
    config/         constants/       errors/
    extensions/     utils/           widgets/
  data/
    models/         repositories/    services/
  features/<module>/
    application/    domain/          data/            presentation/
  shared/
    components/     layouts/
```

### Layer responsibilities

`application/` — the module's contract and state. Contains:

- `<x>_models.dart` — immutable models, inputs, page/cursor types
- `<x>_repository.dart` — **abstract** repository interface, the boundary the
  presentation layer depends on
- `<x>_failure.dart` — a module-specific failure type with user-safe messages
- `<x>_validators.dart` — pure input validation, independently unit-testable
- `<x>_state.dart` — Riverpod providers and controllers

`domain/` — pure business rules with **no** Supabase or Flutter import. Examples:
`sales/domain/invoice_calculation_service.dart`,
`ai_assistant/domain/ai_permission_guard.dart`,
`ai_assistant/domain/business_context_builder.dart`. Client-side calculation here
is for display and validation only; the server remains the source of truth.

`data/` — Supabase adapters. Two files:

- `<x>_service.dart` — low-level Data API/RPC adapter. Owns the select field
  lists, calls `requireSession()` first, and throws the module's failure type on
  an unexpected response shape.
- `supabase_<x>_repository.dart` — implements the `application/` interface using
  the service, mapping rows to models.

`presentation/` — `screens/` and `widgets/`. Widgets read providers and render.
They do not call Supabase, do not compute totals, and do not hold business rules.

### Providers

Declare a provider in the same file as the type it constructs, e.g.
`invoiceServiceProvider` lives in `invoice_service.dart`.

Four providers live in `lib/core/config/app_providers.dart`: `envConfigProvider`,
`supabaseClientProvider`, `startupFailureProvider`, and `supabaseServiceProvider`.
The first three are declared with fail-closed defaults — `envConfigProvider`
throws, `supabaseClientProvider` returns `null` — and are overridden with real
values in `main.dart`'s `ProviderScope`, using the result of
`AppBootstrap.initialize`. `supabaseServiceProvider` derives from the client and
throws `AppConfigurationException` when the client is null. Keep that
fail-closed behaviour: a misconfigured app must reach the configuration screen,
never a half-initialized Supabase call.

### Errors

- `AppException` (sealed) in `core/errors/` with `AppConfigurationException` and
  `AppDataException`
- `Result<T>` / `Success<T>` / `Failure<T>` (sealed) in `core/utils/result.dart`
- Per-module `<X>Failure` for user-facing messages

Never surface a raw PostgREST or Auth error string to the user. Map it to a
module failure with a safe message. Never log tokens, keys, or full row payloads
containing personal data.

### Routing

All routes are registered in `lib/app/router.dart`. Authenticated business
routes live inside the `ShellRoute` wrapped by `AppShell` +
`CompanyContextGate`, which guarantees a selected company before a business
screen renders. Redirect precedence is: configuration failure → `/configuration`,
then unauthenticated → `/login`, then authenticated-on-public-route →
`/auth-gate`. New business modules go inside the shell and get an `AppModule`
enum entry in `lib/core/constants/app_module.dart` for navigation.

---

## 5. Database

Migrations live in `supabase/migrations/`, tests in `supabase/tests/`.

### Current objects

26 tables across 9 migrations: `profiles`, `companies`, `branches`, `roles`,
`permissions`, `role_permissions`, `company_memberships`,
`company_member_branches`, `company_settings`, `parties`, `product_categories`,
`products`, `warehouses`, `stock_balances`, `stock_movements`,
`sales_documents`, `sales_document_items`, `money_accounts`,
`chart_of_accounts`, `payments`, `payment_allocations`, `journal_entries`,
`journal_lines`, `ai_conversations`, `ai_messages`, `ai_insights`.

Tenant guard helpers in the `private` schema: `is_company_member`,
`is_company_admin`, `has_permission`, `shares_company_with`, `set_updated_at`,
`handle_new_auth_user`, `prevent_company_owner_change`,
`protect_owner_membership`, `initialize_company_defaults`,
`ensure_company_default_accounts`.

Public RPCs — the trusted server surface: `get_dashboard_summary`,
`search_customers`, `search_products`, `search_invoices`, `save_sales_invoice`,
`record_invoice_payment`, `get_company_business_summary`.

Tables named in the roadmap but **not yet created**: `audit_logs`,
`purchase_documents`, `tax_rates`, `accounting_event_queue`,
`accounting_periods`, `plans`, `company_subscriptions`, `attachments`, `leads`,
`activities`, `units_of_measure`. Do not write code that assumes they exist.

### Rules for new migrations

- One migration per logical change, forward-only, never edit a migration that
  has been applied to the hosted project.
- Every new table ships in the same migration with: `company_id` column, RLS
  enabled, explicit policies, explicit grants, foreign key indexes, and
  composite tenant foreign keys on child tables.
- Functions handling money or stock: `security definer`, an explicit
  `set search_path`, and a company-membership check on entry.
- Every public function must `revoke all ... from public, anon` and
  `grant execute ... to authenticated` (add `service_role` only when a trusted
  server caller needs it). Follow the pattern already used by
  `record_invoice_payment`.
- Add a pgTAP test in `supabase/tests/` covering tenant isolation for the new
  objects: a member can read, a non-member with a known UUID cannot.

### Local workflow

```powershell
supabase start
supabase db reset
supabase test db
supabase db push --dry-run
```

Do not push to the hosted project until the local reset, tests, and Security
Advisor are clean.

---

## 6. Commands

```powershell
flutter pub get
flutter analyze
flutter test

flutter run `
  --dart-define=APP_ENV=development `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

`flutter analyze` must be clean and `flutter test` must be green before you
report a task finished. Without the `--dart-define` values the app deliberately
opens a configuration screen instead of initializing Supabase.

---

## 7. Testing

Tests mirror the `lib/` structure under `test/`. Each module with a repository
has a hand-written fake, e.g. `test/features/sales/fake_invoice_repository.dart`
— use the fake, do not mock `SupabaseClient`.

Cover per module: validators (pure unit tests), domain calculations against fixed
fixtures, state/controller transitions including failure paths, and widget tests
for loading, empty, populated, and error states.

Tenant isolation is tested in the database with pgTAP, not in Dart.

---

## 8. Working agreement

For each task:

1. Read the relevant existing module first and follow its conventions.
2. State what you are about to change before changing it. Keep the change scoped
   to the requested module.
3. If the schema needs to change, propose the migration and wait for approval
   before applying anything to the hosted project.
4. Run `flutter analyze` and `flutter test`. Fix only failures caused by your
   change; report pre-existing failures separately rather than fixing them
   silently.
5. Report: files changed, how to test manually, known limitations, and anything
   you deliberately left undone.

Between modules, do not start a later roadmap module while a security or
data-integrity blocker is open in one of its dependencies.

Module order and per-module acceptance criteria live in
`docs/DEVELOPMENT_ROADMAP.md`. Current position, phase gates, and the next
concrete actions live in `docs/DELIVERY_PLAN.md`.

---

## 9. Repository state you should know about

- **There is no git repository in this folder.** Nothing is under version
  control and there are no checkpoint commits. Treat every edit as unprotected
  and flag this until it is resolved.
- **Invariants 9 and 10 are currently violated in inventory.**
  `InventoryService.recordStockMovement` in
  `lib/features/inventory/data/inventory_service.dart` inserts the stock
  movement, then reads `stock_balances`, computes the new quantity in Dart, and
  writes it back — three separate round trips, no transaction, no row lock. Two
  concurrent movements will lose an update. The schema permits this because
  `20260714160000_create_products_and_inventory.sql` grants
  `insert, update` on `stock_balances` to `authenticated`. The fix is a
  transactional `post_stock_movement` RPC plus revoking direct write access on
  `stock_balances`. Do not copy this pattern; do not extend it.
- `journal_entries` and `journal_lines` likewise grant `insert` to
  `authenticated`, so a client could post an unbalanced or fabricated journal
  without going through `record_invoice_payment`. Writes should be revoked and
  routed through server functions.
- The Supabase service-role credential recorded in older external project notes
  must be rotated before production use.
- There are no Edge Functions yet, so no LLM provider is wired up. The assistant
  is deterministic: `generateAssistantResponse` sanitizes the prompt, calls
  `get_company_business_summary`, and hands the result to
  `BusinessContextBuilder.buildContextualResponse`, which composes a templated
  reply from real company figures. `ai_insights` rows are likewise seeded from
  hard-coded templates. This is honest and safe, but it is not AI — treat it as
  the scaffold the real gateway will replace.
  `lib/data/services/ai_assistant_service.dart` is the abstract server-mediated
  contract for that future boundary; it shares a class name with the concrete
  `features/ai_assistant/data/ai_assistant_service.dart`, which is confusing and
  should be renamed when the Edge Function lands.
- There is no CI pipeline.
