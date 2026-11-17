# Platform control, Sales and HR improvements — design

Date: 2026-11-14. Status: approved by the owner on 2026-11-14.

## Intent

Make organization creation, J Panel control, the Sales App and HR work together end to end, fix the known defects, and add four capabilities. The J Panel must be the place that decides which organization exists and which modules it may use.

## Owner decisions

- Scope: defect fixes, J Panel module control, hardening, and four new capabilities, delivered in phases.
- Organizations are created only through the J Panel or an approved checkout order. Self-created organizations are blocked by default; the trial allowlist remains for named test accounts.
- No installs on any hosted database. SQL is staged under `supabase/candidates/` with tests.

## Goals

1. One current baseline: organization control (PR #26) plus the newest Sales work.
2. J Panel controls module access per package and can move an organization between packages.
3. Field Sales has a module switch like the other optional modules.
4. Employee App logins issued by the company can use self-service.
5. HR decisions cannot be made by their own subject; per-employee pay amounts need MFA.
6. A Sales rep is never locked out by a lost submission and never loses a draft to another customer's draft.
7. New: multi-day leave, stock availability for reps, sales rep to employee link, live customer visits.

## Non-goals

- Owner password-only sign-in stays (documented choice in `20261105102000_organization_identity.sql`).
- Field Sales enrollment removal stays unavailable (documented choice in `20261031090000_field_sales_governance.sql`).
- Request visibility by assigned customer stays.
- No column encryption for private HR text, no configurable retention, no tax or statutory payroll rules.
- No targets or commission-to-payroll.
- No change to the stale local `main` checkout.

## Anti-goals

- A module switch that only hides menus. Every switch is enforced in the SQL access functions.
- Rewriting long installed functions when a small trigger or helper achieves the rule.
- Any path that lets a rep discard a submission whose outcome is still unknown.

## Approaches considered for module control

1. **Per-organization override table plus a shared helper.** Cleanest model, but about twenty existing access functions check `billing.plan_entitlements` inline and would each have to be replaced. High risk for an installed surface.
2. **Private package per organization.** Works with the inline checks but pollutes the package list and breaks price propagation.
3. **Package-level module switches plus "move organization to package" (chosen).** Matches the existing model (entitlements belong to a package), needs no change to the inline checks, and gives per-organization control by assigning the organization to a package with the wanted module set.

## Design by phase

### Phase 0 — baseline

Branch from `claude/jpanel-combined-install-fix`, merge `origin/codex/sales-workflows-candidate-20261111`, record a green baseline.

### Phase 1 — organization creation and J Panel control

New candidate `20261114090000_organization_creation_control.sql`, installed last.

- `billing.subscription_checkout_settings.enforce_checkout` defaults to true. `api.platform_set_checkout_enforcement(p_enforce, p_reason)` lets an operator change it, with an audit event.
- `api.platform_save_package_modules(p_code, p_modules, p_expected_revision)` sets module entitlements on a package, using the same optimistic revision and `billing.package_events` trail as `api.platform_save_package`.
- `api.platform_set_organization_package(p_tenant_id, p_plan_code, p_reason)` moves an organization to an active package and records an event.
- New entitlement `module.field_sales`, seeded off, required by `field_sales.require_rep` and `field_sales.require_company`.
- `api.platform_create_organization` is revoked from `authenticated`; the J Panel uses `api.platform_create_system`.
- J Panel UI: module switches in the package editor, package change on an organization, checkout-enforcement switch. Desktop onboarding explains `SUBSCRIPTION_CHECKOUT_REQUIRED` in plain words.

### Phase 2 — HR

- The managed `people.employee_app` role carries the six self-service permissions; `people.require_access` accepts them for a managed employee within its own entity and branch.
- Reads that return per-employee pay amounts require an MFA session.
- Triggers refuse a leave or attendance decision when the decider's linked employee is the subject. Attendance cancel follows the approve/reject independence rule.
- The displayed leave balance uses the same date rule as allocation.
- The payroll double-pay guard ignores reversed runs.

### Phase 3 — Sales App

- A pending submission that has expired and for which the server holds no receipt can be discarded by the rep.
- The live draft key includes the customer; the existing single draft is migrated on first read.
- The order form is saved as a draft before access expiry clears it.
- Customer search escapes `%` and `_`; confirmation faults are not reported as an expired link.

### Phase 4 — new capabilities

- Multi-day leave: one command creates the per-slot requests for a date range as a batch decided together.
- Stock availability: the rep catalogue returns a real availability state with an as-of time; nothing is reserved.
- Rep to employee: derived from `people_private.account_links`; labels are employee names or `Unlinked member ····1234`, never e-mail addresses.
- Visits: `field_sales.visits` with an idempotent command; location is optional and only at a declared action.

## Constraints

- Combined install order is documented in `docs/development/organization-control-rollout.md` and tested by `supabase/tests/combined_candidate_install.test.mjs`; every new candidate is added to both.
- Candidates that replace `core.has_permission`, `people.require_access` or the Field Sales helpers must carry forward the exceptions already documented in those files.
- Every new tenant table reinstalls the organization lifecycle write guards.

## Left to the builder

Exact function bodies, UI layout inside the existing J Panel screens, test fixture shape, and the per-phase task plans under `docs/superpowers/plans/`.
