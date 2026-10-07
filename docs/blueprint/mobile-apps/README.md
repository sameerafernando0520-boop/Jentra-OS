# Jentra Employee and Jentra Sales — mobile app blueprints

**Author:** Codex, prepared for the Jentra OS owner  
**Date:** 2026-10-08 (Asia/Colombo)  
**Status:** Draft for product and engineering review; no mobile implementation or deployment is claimed.  
**Reviewers:** Product owner, HR/payroll owner, sales manager, finance owner, engineering and design.

Jentra Employee gives each employee a clear view of their work, leave, payslips and HR requests. Jentra Sales gives each salesman a practical field workspace for assigned customers, quotations, orders, all three confirmation steps and follow-up. They are two installable apps with a common Jentra backend, identity foundation and visual language. The desktop remains the administration and accounting workspace.

The owner confirmed on October 8 that sales confirmations include **customer acceptance, company approval and delivery acknowledgement**. These are separate facts. Accepting an order does not reserve stock, acknowledge delivery, issue an invoice or prove payment.

## Read the package

| Document | Purpose |
|---|---|
| [Employee app blueprint](EMPLOYEE_APP_BLUEPRINT.md) | Employee and delegated supervisor journeys, features, permissions, contracts and acceptance |
| [Salesman app blueprint](SALESMAN_APP_BLUEPRINT.md) | Field selling, customer/company/delivery confirmations, credit/stock controls and collections roadmap |
| [Shared mobile foundation](SHARED_MOBILE_FOUNDATION.md) | Architecture, identity, offline drafts, security, notifications and common acceptance |
| [Mobile design brief](MOBILE_DESIGN_BRIEF.md) | Existing Jentra identity translated into accessible phone layouts |
| [Business glossary](CONTEXT.md) | Precise meanings of employee identity, acceptance, confirmation, delivery and payment |

Requirement ranges are provisional and distinct from approved Wave 1–5 IDs: shared 7001+, employee 7101+, sales 7201+. MUST/SHOULD/MAY define the proposed contract; they do not imply owner approval or installed capability.

## Current system versus proposed work

The current repository has one app, `apps/jentra_desktop`, and shared domain, platform and design packages. No employee or salesman mobile app is present. Existing employee links, self HR projections, exact payroll, quotations, orders and receivables provide reusable foundations. Mobile self-service authorization, rep/customer isolation, governed selling prices, customer verification, mobile device storage and push delivery require additional work.

The latest recorded [Wave 3 status](../../development/remaining-wave3-status.md) and [Wave 4 status](../../development/wave4-status.md) are dated October 6. They retain installation and authenticated/native/load/visual/owner gates. In particular, attendance, leave and payroll include unapplied candidates. These blueprints use source and recorded evidence; this authoring task did not refresh the live migration ledger or certify production readiness.

## Product decisions

| Decision | Basis and trade-off |
|---|---|
| Two apps, one backend | Directly matches the requested employee and salesman products; shares business rules while keeping navigation, permissions and local storage separate |
| Flutter mobile, shared pure Dart contracts | Fits Jentra's existing architecture; mobile adapters and release builds still need separate proof |
| Android and iPhone scope; Android pilot first is proposed | Avoids designing an Android-only product; pilot order and minimum OS/device versions await owner selection |
| Offline reading and draft capture; explicit online submission | Preserves Jentra's accepted offline policy and avoids silently posting stale payroll, orders, stock or payments |
| Keep Jentra Flow identity | Reuse the supplied logo, palette and fonts; introduce phone layouts rather than compressing the desktop shell |
| Online private payslips in the first release | Reduces retained salary data on lost devices; employee export remains separately authorized |
| Basic operation without push/GPS | Notification or location denial must not prevent payslip viewing, ordinary HR requests or selling; attendance policy can request an alternative evidence route |

## Delivery sequence

| Phase | Deliverable | Exit condition |
|---|---|---|
| M0 — contracts and authorization | Validate installed dependencies; employee self endpoints; rep assignments; price/discount policy; customer confirmation verification; restore/rollback plan | No broad legacy read/write bypass, complete permission tests, approved production policy decisions |
| M1 — shared mobile foundation | Two app shells, login/linking, workspace choice, secure storage, recovery, inbox and phone components | Physical Android/iPhone authentication, resume, storage, deep-link and privacy checks |
| E1 — employee self-service | My work, leave, payslips, profile, review acknowledgement and HR cases | Full own-employee journeys; other employees inaccessible; payroll disputes routed to accountable HR owner |
| S1 — field sales | Assigned customers, product catalogue, governed prices, quotes/orders, all three confirmations, delivery/invoice status and customer follow-up | Correct price/credit/stock behavior; revision-bound customer acceptance; warehouse/finance separation |
| E2/S2 — approved extensions | Supervisor approvals, expenses/time and field collections/handover/returns requests | Each extension has independent permissions, accounting rules and end-to-end evidence |
| Release | Signed binaries, store/private distribution, staged rollout, support and rollback | Separate backend installation, app build, physical-device, load, visual and business owner sign-offs |

No calendar duration is promised before team capacity, backend installation, distribution accounts and device matrix are known. E1 and S1 can be scheduled independently after their M0 dependencies pass.

## Desktop work that must accompany the apps

HR needs governed invitation/link administration, self-service policy configuration, attendance exceptions, leave approval queues, payroll query cases and employee-access revocation. Sales management needs dated rep/customer assignments, selling-price and discount policies, order approval/credit-hold queues and confirmation disputes. Warehouse users own picking/dispatch and posted stock. Finance users own invoice/receipt posting, allocation and reconciliation. Administrators need device registrations, inbox delivery health and app version policy.

These are backend and desktop product changes, not features that can be secured by hiding buttons in a phone app.

## Open policy decisions

The draft is usable for review without silently choosing these business rules:

1. Android pilot or simultaneous Android/iPhone rollout; distribution method, actual devices and minimum supported OS versions.
2. Attendance evidence: server time, location at tap, site QR, trusted clock feed or an approved combination; grace windows, shifts and offline exception handling.
3. Who may represent a customer; verified customer channel and assurance required for order acceptance and delivery acknowledgement.
4. Whether customer acceptance is required before every company confirmation or only selected order types; material revisions always require re-acceptance when acceptance is required.
5. Manager mobile approvals in the first employee pilot or the second release; delegated-team scope and independence rules.
6. Cash/cheque collection authority, custody/handover, receipt numbering and reversal policy before S2.
7. Real payroll localization, published statutory rules and payroll-owner validation before any real salary rollout; the mobile app cannot supply this certification.
8. Retention and visibility of employee attachments, location evidence, customer signatures and dispute history; the limits below are proposed engineering defaults.

## Review record

Normal and exception walkthroughs are included in both app blueprints. They are design exercises, not executed software tests. Structural validation and cross-document checks belong to the authoring task; installed behavior, device acceptance and production activation remain future evidence.

The first implementation slice should be M0 plus the shared foundation, followed by one own-payslip journey and one assigned-customer order journey. This exposes the identity and authorization risks before building the full screen catalogue.

### Authoring validation — October 8

All three specification files passed the engineering skill's strict structural validator with no findings. Cross-document checks found 58 functional requirements, 20 non-functional requirements, 28 acceptance criteria and 32 edge cases; every functional/non-functional requirement is referenced by acceptance criteria. Requirement definitions are unique across the package and all local document/source links resolve. These checks establish document structure and traceability, not implementation correctness or business approval.
