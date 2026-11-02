# Jentra OS feature completeness — 28 October 2026

The OS has substantial business functionality, but **all planned features and production launch gates are not complete**. All 43 advertised desktop navigation destinations have matching screen routes. That is a source inclusion check, not a claim that every journey works in the selected hosted database.

**Client delivery update, 29 October:** actual Windows installer/portable ZIP and
web ZIP were built as 0.3.1+2302 Development. Staging, native regressions, web
sign-in and four durable browser storage scenarios passed. These clients are
unsigned/Development; the later Firebase update below publishes the updated web client. See the
[installation guide](install-desktop-and-web.md) and
[delivery verification](../verification/desktop-web-20261029/README.md).

**Firebase web update, 29 October:** browser version 0.3.1+2303 is now published
at [Jentra OS](https://jentra-os-desktop.web.app) on the separate desktop Hosting
site. It adds password visibility and a 12-character mixed-character signup
form rule. Hosting completion does not install backend candidates or complete
the real-company launch gates listed below.

Use the [operating manual](README.md) for setup and daily use, the [43-section inventory](feature-inventory.csv) for navigation, and the [launch record](../development/launch-readiness-20261028.md) for current verification and blockers. This review preserves the approved blueprints and their historical acceptance records; it does not award new business acceptance.

| Capability | Included in current source | Remaining work for a company launch |
| --- | --- | --- |
| Sign in, MFA, workspace selection, encrypted drafts and recovery | Implemented desktop foundation and shared adapters | Authenticated native restart, revocation, cross-company and independent approval acceptance on the release target |
| First company group, legal entity and branch | Implemented first-workspace setup | Confirm the launch project and real structure before onboarding |
| Extra legal entities and branches | Company & access screen and additive administration APIs now implement creation and permitted versioned edits | Run the full isolated database gate, review rollout and verify actual multi-company/native acceptance; see the administration addendum |
| Staff invitations and general role administration | New custom roles, scoped assignments, suspend/revoke/restore and verified-email invitation acceptance UI/API candidate | Reviewed installation and individual-account acceptance, independent approvers and recovery; invitation email sending is separate |
| Shared business setup | Currency, exchange rate, accounts, periods, parties, contacts, products, units, tax, numbering, workflows, approvals, files and report setup resources exist | Review the real company's configuration and acceptance; job registers alone do not certify each import/export provider |
| CRM, quotations and sales orders | Implemented source and desktop screens | Complete a real-company pilot from opportunity through approval and order recovery |
| Procurement | Requisition, sourcing, order, goods receipt, bill, payment and return source/screens exist | Confirm current installed contracts and end-to-end quantities, money and independent approval |
| Fulfillment, receivables and returns | Implemented source and desktop screens | Pilot dispatch, invoice, receipt/allocation and correction with stock and ledger reconciliation |
| Inventory | Transfers, counts, reservations, receipt trace, landed cost, valuation, disposition and negative-stock policy source/screens exist | Validate selected policy, lots/serials, opening values, concurrent changes and ledger reconciliation |
| Finance | Journals, AR/AP and GRNI controls, bank reconciliation, periods/FX, statements, tax review, dimensions and budgets exist | Accountant-reviewed opening and close acceptance; statutory configuration and real bank/payment integration are separate |
| People and HR | Directory, dated employment, organization, calendars, private HR, reviews, attendance, leave and staff intake source/screens exist | Reviewed installation of employee candidates, actual authorization and employee/staff journeys |
| Payroll and corrections | Synthetic payroll, approval/posting, correction and payslip source exist | Qualified statutory review and payment acceptance before real salary processing |
| Projects, time, expense and milestone billing | Implemented source and desktop screens | Pilot source consumption, expense evidence, corrections and reconciliation |
| Service, equipment and fixed assets | Work orders, labor/parts, internal equipment, assets and depreciation source/screens exist | Pilot operational, stock and finance outcomes with the business owner |
| Corporate Audit & Assurance | Engagement, evidence, findings, responses, planning, metrics, access and exports exist | Successful authenticated private-file operations, native accessibility and production promotion acceptance |
| Analytics | Process, current/historical pipeline, financial ratios and cash scenarios exist | Reproduce outputs from actual scoped business sources; measure accuracy and target-scale latency |
| AI suggestions and proposals | Reviewed model client and OpenAI adapter exist; proposal policy permits `analytics.freeze_pipeline.v1` | Configure the approved hosted provider and trusted usage; prove separate MFA approval/execution, recovery and source freshness |
| Integrations, usage and operator health | Source and control screens exist for scoped integrations, synthetic subscriptions, quotas and separate operator authority | Actual signed delivery, reconciliation, retries/replay, independent quota contention and current operator authority |
| Jentra Employee | Separate Flutter employee application includes own records, requests, documents and inbox; signed Android APK/AAB 0.5.0+9 built and verified, with 224 tests passing and a clean analyzer; see the [30 October rollout record](../verification/company-employee-20261030/README.md) | Backend candidate rollout, physical-device privacy/authentication checks, portable signing backup and store publication; push requires separate activation |
| Jentra Sales mobile app | Separate adaptive Flutter app now implements an explicit sample-data preview: Today, customer portfolio/detail, catalogue, order drafting/review, protected local recovery, visits and delivery state views; see the [Sales release record](../development/jentra-sales-release-20261030.md) | Implement and install portfolio authorization across legacy paths, governed server selling and independent discount approval; verified email links for separate customer acceptance and delivery acknowledgement; translations, physical-device and company acceptance remain open |
| Production operations and distribution | Build, packaging, installer and CI tooling exist | Staging/production target, full current CI, migration rehearsal, tested restoration, monitoring, signed release, load/accessibility checks and company signoff |
| Named test-company cleanup | Cleanup requested; no deletion performed | Renew the management connection, obtain current project/name/ID inventory and a reviewed recovery/scope record |

## AI intelligence in practice

Open **Analytics** for process, pipeline, historical pipeline, ratios and cash scenarios. Open **Jentra Control** for reviewed model suggestions, proposals, usage and authorized operator health. The application's `main.dart` wires both the analytics repositories and the reviewed model gateway to the connected Supabase client.

The reviewed model gateway calls `wave5-runtime/model/suggestion`. The current contract retrieves a redacted numeric pipeline projection. A model response is advisory. An accepted suggestion may become a versioned proposal for the allowlisted forecast command; a separate authorized person must approve it with MFA, and execution rechecks scope, source versions, expiry and quota. Current source does not implement unrestricted AI chat or general autonomous business posting.

The 28 October checkpoint had 260 worker tests using controlled providers/transports. Those results do not establish a live provider response, billable usage, model quality or actual webhook delivery. Hosted readiness was not refreshed in that audit because project management access was unavailable.

**31 October continuation:** the ordinary worker source now preserves reviewed
managed routing and server-key handling, and repeatable hosted/accounting
verification tools are implemented. The current worker suite has 287 passing
tests and the read-only accounting query passes nine isolated PostgreSQL checks.
Actual HTTPS requests confirmed three authentication denials and a model
`503 MODEL_PROVIDER_UNAVAILABLE`. Backend access is now restored and the hosted
read-only snapshot shows no model/quota records, one unresolved retry delivery
and expired runtime authority. The provider key is absent; actual successful
model usage accounting and signed delivery remain open. See
the [current AI and integrations runbook](../development/ai-integrations-hosted-verification-20261031.md).

## Source basis and limits

The review checked `apps/jentra_desktop/lib/src/shell/navigation.dart`, `src/router.dart`, `lib/main.dart`, the feature directories, `packages/jentra_platform/lib/src/supabase_foundation_gateway.dart`, `src/analytics/reviewed_model_gateway.dart`, `workers/wave5`, the workspace app list, and the approved delivery/mobile blueprints. The source inventory JSON records the principal file hashes.

The mobile blueprint's October 8 statement that no employee app exists is historical: `apps/jentra_employee` now exists. On October 30, `apps/jentra_sales` was added to the workspace as an interactive preview; its live sales backend and full S1 acceptance are still open. Similarly, earlier development status counts are historical; they do not replace current release acceptance. There is no defensible percentage of total production completeness from a route count or test count alone.
