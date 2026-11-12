# Jentra OS Company Setup and Operating Guide

Owner and team manual for setting up a real company group and running daily business operations. Prepared on 28 October 2026 from the current Jentra OS workspace.

For the 12 November Windows, Android and web packages, see the [app installation and first-use guide](app-handoff.md).

**Client delivery, 29 October:** Windows installer and browser packages are now
built as **0.3.1+2302 Development**. Read the
[desktop and web installation guide](install-desktop-and-web.md). The unsigned
installer and web client use the existing Development backend; company launch
gates remain pending. The Firebase update below supplies the hosted web client.

**Firebase web update, 29 October:** the updated browser client **0.3.1+2303**
is hosted at [Jentra OS](https://jentra-os-desktop.web.app). The employee site is
preserved. Password visibility controls and the 12-character new-account form
rule are included. This advances web delivery; the Development backend and
remaining company-launch gates still apply.

**Administration update, 28 October:** the new Company & access screen and
additive backend candidate now implement extra companies/branches, custom roles,
staff assignments, suspension/restore and verified-email invitation acceptance.
Read the [step-by-step administration addendum](company-access-administration.md)
or its [downloadable Word version](<Jentra OS Company Access Administration Addendum.docx>).
Hosted installation and pilot acceptance remain pending. The Word manual retains
the earlier checkpoint; use this addendum for the new administration workflow.
The [Sales owner decision record](../blueprint/mobile-apps/SALES_OWNER_DECISIONS_20261028.md)
records approved discount requests and verified email links without activating sending.

### Start here

Use the Windows application for administration and business operations. Use Jentra Employee for the employee's own records and requests. First establish the correct company structure, access and opening balances; then test complete business journeys before wider use.

| Your task | Read |
| --- | --- |
| Create the group and prepare real data | Pages 2 and 3 |
| Run sales purchases and stock | Page 4 |
| Run finance and employee workflows | Page 5 |
| Use projects service assets and audit | Page 6 |
| Understand analytics and AI | Page 7 |
| Run the pilot and daily controls | Page 8 |
| Check what is included | Pages 9 and 10 and feature inventory CSV |

### Current launch position

The main business modules, analytics and reviewed AI workflows are implemented in source. Source availability does not establish that every module is enabled or installed in your selected database. The latest desktop test suite passed 2343 tests, including the new administration/privacy checks. Production configuration and real company acceptance remain separate checks.

| Item | Current position |
| --- | --- |
| Company group | Enter your own registered details after the target workspace is confirmed. |
| Stored test companies | Cleanup is pending a verified company inventory. The saved management connection is currently invalid. |
| Employee HR additions | New self service and notification producers exist as candidate SQL. Installation and push activation need the reviewed rollout. |
| AI service | Application and worker adapters exist. Current hosted model configuration and actual usage are not freshly verified. |
| Payroll | Current implementation is synthetic payroll. Statutory and payment acceptance are required before real salary use. |

Record your group name, administrator, operating entities and pilot start date in your internal rollout record. Keep this guide with the approved release version and support contact.

## Prepare the company group

### Understand the company hierarchy

A business group is the workspace boundary. A legal entity is a registered company inside that group. A branch is an operating location inside a legal entity. Check all three selections before entering or approving a document. Selecting a branch does not transfer another company's balances or permissions.

### Remove the correct test companies

1. Have the administrator restore the Supabase management connection and identify the exact project used by this installation.
2. Obtain the current company names and IDs from that project. Classify each as a named test company or a company to retain. Source fixtures and old reports are not a current database inventory.
3. Take an approved database and private file backup, and verify the recovery procedure before permanent cleanup.
4. Review all linked records for the named test companies, including users, files, finance, stock, HR and audit history. Perform the reviewed tenant cleanup only for those IDs.
5. Verify retained companies and user access after cleanup. Do not delete your existing business records merely to make the home screen look empty.

### Create the first real workspace

1. Launch the administrator supplied connected build and sign in using your own account. Complete MFA when requested.
2. Open the first workspace setup form. Enter Business group name and a unique Workspace slug.
3. Enter Registered entity name and Entity code using the first company's real details.
4. Enter Branch name and Branch code. Confirm Head Office and HQ only if those values match your intended first branch.
5. Submit once. If the result is unconfirmed, retry the same request rather than creating another workspace.
6. After confirmation, select the new group, legal entity and branch and verify the scope shown in the application.

The setup wizard creates the first entity and branch. After the reviewed
administration candidate is installed, use **Business setup → Company & access**
for extra companies and branches, following the addendum above. Verify the
subscription limit and actual company structure before testing cross-company
workflows. Do not represent a second legal company as a warehouse or department
of the first.

## Configure access and business foundations

### Give each person an individual account

The workspace creator becomes the owner. Assign access by job, legal entity and
branch. Sharing an owner account prevents reliable attribution and independent
approval. The new Company & access workflow supports custom roles, scoped staff
invitations and access changes after its reviewed backend rollout. Staff sign in
with their verified account email and accept their own invitation. The candidate
does not send invitation email.

| Person | Typical responsibility |
| --- | --- |
| Owner or administrator | Company structure access and release coordination |
| Finance preparer and separate approver | Documents allocations journals reconciliation and period review |
| Sales and purchasing staff | Their customer or supplier documents within the allowed branch |
| Warehouse staff | Receipts fulfillment transfers and counts |
| HR staff and independent reviewer | Employment private HR attendance leave and payroll review |
| Auditor and process owner | Evidence findings responses and remediation under audit access |
| Employee | Own accepted employee link and permitted self service records |

### Complete Business setup in a controlled order

1. Confirm currencies and exchange rates, then configure the chart of accounts and fiscal periods with the responsible finance reviewer.
2. Review tax definitions and document numbering before issuing real documents. This guide does not prescribe tax rates or statutory rules.
3. Create customers and suppliers under Parties, then their contacts. Check legal names and duplicate records.
4. Create units and valid conversions before products. Set product classifications and warehouse records for the intended branch.
5. Configure workflow definitions and approval matrix steps. Test that the preparer cannot approve their own restricted transaction.
6. Review file access, notifications and report definitions. Import and export job registers are present, but each actual import/export provider needs its own acceptance check.

### Load opening records once

Agree one cutoff date and signed opening balances. Reconcile the opening trial balance, customer and supplier balances, bank balances, quantities, lots or serials and stock value. Use the relevant reviewed opening workflow and an independent approval. Compare the resulting reports with the signed source records before entering normal transactions. Retain the opening document references to prevent duplicate loading.

## Run sales purchases and inventory

### Sales and customer money

1. Use CRM and Revenue to record leads and opportunities with a responsible owner and next action.
2. Prepare a quotation in Sales. Verify customer, branch, quantities, unit conversions, prices, currency, tax and validity before confirming it.
3. Create the sales order from the accepted commercial record. Review reservations and credit or approval requirements.
4. Use Fulfillment and receivables to record the actual dispatch or service fulfillment and issue the relevant invoice through the allowed workflow.
5. Record a customer receipt only when the actual payment evidence exists, then allocate it to the correct open invoices.
6. Process returns and credits through their source documents. Check that quantities, outstanding balances and journal effects match the intended correction.

### Purchasing and supplier money

1. Create a requisition and use sourcing or RFQ comparison when your purchasing policy requires it.
2. Create the purchase order for the correct supplier, branch, currency and warehouse.
3. Receive only the goods actually accepted. Record lot, serial and unit details where required and retain the receipt reference.
4. Enter the supplier bill and review differences between the order, receipt and invoice before posting.
5. Record and allocate a supplier payment from actual bank or cash evidence. Keep approval and reconciliation separate.
6. Use purchase returns and settlement correction workflows for reversals. Preserve the original transaction history.

### Warehouse operating rules

Check the active company and warehouses before a transfer. Track both source and destination and verify the transfer reaches its final state. For stock counts, follow the count cutoff and review variances before approval. Use reservations, receipt quantity trace, landed allocations, inventory valuation and disposition for their specific purposes; do not fix stock by entering an unrelated purchase or sale.

Work offline only on supported drafts. Inventory, payments, approval and ledger posting need a confirmed online result. An uncertain result is not proof that nothing happened: retain the original request and use its recovery or retry action.

## Run finance and people operations

### Finance responsibilities

Use Manual journals for reviewed adjustments and preserve their supporting evidence. Use Financial dimensions for reporting classifications, Bank reconciliation for matching statement items, Financial statements for posted results, Tax review for reviewed summaries, Cash flow mappings for classification and Budgets and variance for comparison.

1. Each day compare receipt and payment records with actual evidence, review unallocated amounts and investigate unexpected balances.
2. Review Finance controls and Control and close review for exceptions before closing a period.
3. Reconcile receivables, payables, inventory control and bank or cash to the general ledger.
4. Review open documents, adjustments, foreign exchange and supporting reports. Obtain the finance approver's acceptance before a period close.
5. Use the supported reversal or correction when an issued transaction is wrong. Keep the reason and link to the original document.

### HR and workforce

In People, establish the employee record, dated employment, Work calendars and Organization assignments before recording attendance or leave. Use Private HR and account for protected content and accountable staff case handling. Use Attendance and leave for canonical time records, independent decisions and employee request intake.

1. Review current employment and branch dates before approving work or leave.
2. Review attendance evidence and select the matching independently approved canonical record when resolving an employee request.
3. Approve, reject or cancel using the owning attendance or leave workflow. A staff request outcome does not by itself create payable work.
4. Publish a private document explicitly to the intended employee only after review.
5. Treat payroll preparation, independent approval, posting, payslip publication, correction and payment evidence as distinct events.

### Jentra Employee

The employee signs in, selects an available workplace and accepts the correct employee account link. They can use the implemented own attendance, leave, payslip, review, case, document and inbox flows when their backend endpoints and permissions are available. MFA is required for protected actions. Downloaded private documents remain the employee's responsibility. Notifications carry a generic update; opening the app rechecks access.

A message saying the service is not enabled means the reviewed backend rollout or entitlement is missing. It does not mean the employee should create a second account. Push sending remains a separate activation step.

## Run projects service assets and audit

### Projects

Create the project with its customer, scope and responsible owner. Review milestones, approved time and expenses, service links and project finance before billing. Use the supported milestone and source consumption workflows so the same time or expense is not billed twice. Review a changed source before a later payroll or billing correction.

### Service and fixed assets

Use Service for tickets, work orders, labor, parts and completion under the assigned branch. Record actual work and consumed stock through the relevant source workflow. Review equipment or internal asset links before closing the work order.

Use Fixed assets for the asset register, reviewed acquisition or capitalization, assignment, maintenance, depreciation and disposal flows supported by the installed release. Reconcile asset values with finance. A service completion, an asset disposal and the related financial posting are separate confirmations.

### Corporate Audit and Assurance

1. Use Audit planning to maintain the universe, risk assessments and approved plans.
2. Create a scoped engagement and grant only the required team and process owner access through Audit access.
3. Map controls and request evidence. Upload and review the relevant private evidence; verify the file before relying on it.
4. Record procedures, samples and exceptions. Issue findings through the independent review workflow.
5. Capture management responses, risk decisions, remediation and independent retesting. Reopen a finding when the evidence requires it.
6. Freeze the appropriate evidence and issue a versioned report. Review legal holds, carry forward and governed exports before release.
7. Use Audit metrics for current evidence based process and finding measures.

### What an owner should review

A successful screen or automated test does not establish that a real employee, manager or external reviewer has the correct access. Include a positive authorized action and a denied action from another company in the pilot. Review the audit trail for actor, document, revision and result. Capture acceptance by the responsible business owner.

## Use analytics and the AI intelligent section

### Analytics that do not require a language model

| Analytics tab | How to use it |
| --- | --- |
| Process | Choose the authorized process scope and period and inspect the source based metrics. |
| Pipeline | Review opportunities probabilities and horizons before relying on a forecast. |
| Historical pipeline | Compare published historical and realized results using compatible periods. |
| Financial ratios | Select compatible published statements and reviewed classifications. |
| Cash scenarios | Compare hypothetical timing changes with the dated authoritative baseline. |
| Integrations | Review scoped subscriptions credentials and delivery outcomes. A worker and destination must be configured. |
| Governed exports | Generate or reopen an allowed export and verify its source and access evidence. |

### Reviewed AI requests in Jentra Control

The current AI implementation is a governed forecast assistance workflow. It has an OpenAI Responses adapter and a reviewed model worker. It is not a general chatbot or an autonomous operator for every module. The actual model, server credentials, quotas and current hosted runtime must be configured and verified by the administrator.

1. Select the correct entity and branch and open Jentra Control with the required proposal permission.
2. Use an authorized current pipeline forecast and its exact source reference. Review the scope, currency, horizon and source evidence.
3. Request a reviewed suggestion only when the model service is available and the allowance permits it.
4. Check the suggestion against the source. The worker validates its limited command and source identity; a suggestion does not execute a business transaction.
5. If appropriate, submit an explicit human proposal. A different authorized MFA approver reviews the exact revision before the separately permitted execution action.
6. If the outcome is pending or unknown, reopen the saved original request. Do not submit replacements to bypass an unresolved reservation.

The present allowlisted AI action concerns pipeline forecast freezing. Do not expect automatic payroll, purchasing, stock, payment or journal posting from the AI section. Keep model credentials on the server. Actual trusted usage, cost limits, access revocation and one real provider response must pass the pilot before this feature is advertised as active.

## Operate daily and complete the company pilot

### Daily checklist

1. Confirm the release, sign in and check business group, entity, branch and current access.
2. Review notifications, pending approvals and any unconfirmed requests before entering new work.
3. Enter actual business activity, retain source documents and verify each confirmed outcome.
4. Review stock exceptions, unallocated customer or supplier money, failed integrations and employee requests.
5. Sign out on a shared device. Lock private screens when leaving the desk and protect exported files.

### When something goes wrong

| Message or situation | Action |
| --- | --- |
| Permission denied or MFA required | Recheck your account and scope. Complete MFA or contact the administrator; do not use a colleague's account. |
| Record changed or version conflict | Reload and review the current revision before making a new decision. |
| Unconfirmed or uncertain result | Keep the original command and use its recovery or retry option before starting another. |
| Service not installed or provider unavailable | Ask the administrator to check the installed release entitlement and worker configuration. |
| Draft or protected storage failure | Preserve the device and recovery information. Avoid clearing app data while an unresolved draft exists. |

### Pilot acceptance before wider rollout

Test one complete sale through receipt, one purchase through payment, stock receipt and transfer, a count variance, an accounting close review, an employee request and private document, and an audit evidence cycle. Test AI separately with a real approved provider response. Compare resulting stock and finance reports with the expected business results.

Test a second company and a restricted branch user to prove separation. Restart the app with an unfinished draft, recover an uncertain operation and confirm access removal takes effect. Rehearse database and private file restoration. Review monitoring and support ownership. Obtain the company owner's written acceptance before general use.

Current gaps include complete group and staff administration, the separate Jentra Sales app, verified production configuration, HR candidate rollout, worker/model/push activation, signed distribution and real company acceptance. The following inventory records source inclusion; it is not a production certification.

## Feature inclusion inventory

All advertised desktop navigation destinations below have matching routes in the current source. Availability also depends on sign in, permissions, plan entitlements and installed backend contracts. This check does not prove each production workflow.

| Feature | Application route | Inclusion |
| --- | --- | --- |
| Command centre | /dashboard | Present in source |
| Business setup | /setup | Present in source |
| Notification management | /operations/notifications | Present in source |
| CRM & Revenue | /crm | Present in source |
| Sales | /sales | Present in source |
| Procurement | /procurement | Present in source |
| Fulfillment & receivables | /receivables | Present in source |
| Inventory | /inventory | Present in source |
| Warehouse transfers | /inventory/transfers | Present in source |
| Stock counts | /inventory/counts | Present in source |
| Stock reservations | /inventory/reservations | Present in source |
| Negative-stock policy | /inventory/negative-stock-policy | Present in source |
| Receipt quantity trace | /inventory/receipt-trace | Present in source |
| Landed value | /inventory/landed-value | Present in source |
| Inventory valuation | /inventory/valuation | Present in source |
| Receipt landed allocation | /inventory/landed-extensions | Present in source |
| Stock disposition | /inventory/dispositions | Present in source |
| Finance | /finance | Present in source |
| People | /people | Present in source |
| Work calendars | /people/calendars | Present in source |
| Organization | /people/organization | Present in source |
| Private HR & account | /people/private | Present in source |

Additional scope: Jentra Employee is implemented; device and distribution acceptance remain open. The separate Jentra Sales app remains a blueprint. Employee self service, cases, documents and push have candidate backend additions. Extra company and staff administration needs completion or reviewed provisioning. Statutory payroll, live payment collection and production recovery certification remain open.

## Feature inclusion inventory continued

All advertised desktop navigation destinations below have matching routes in the current source. Availability also depends on sign in, permissions, plan entitlements and installed backend contracts. This check does not prove each production workflow.

| Feature | Application route | Inclusion |
| --- | --- | --- |
| Attendance & leave | /people/workforce | Present in source |
| Payroll | /people/payroll | Present in source |
| Fixed assets | /assets | Present in source |
| Manual journals | /finance/journals | Present in source |
| Finance controls | /finance/controls | Present in source |
| Control and close review | /finance/close-review | Present in source |
| Financial dimensions | /finance/dimensions | Present in source |
| Bank reconciliation | /finance/bank | Present in source |
| Period & FX close | /finance/periods | Present in source |
| Financial statements | /finance/statements | Present in source |
| Tax review | /finance/tax | Present in source |
| Cash-flow mappings | /finance/cash-flow-mappings | Present in source |
| Budgets & variance | /finance/budgets | Present in source |
| Projects | /projects | Present in source |
| Service | /service | Present in source |
| Governance & Audit | /governance/audit | Present in source |
| Audit planning | /governance/audit/planning | Present in source |
| Audit metrics | /governance/audit/metrics | Present in source |
| Audit access | /governance/audit/access | Present in source |
| Analytics | /analytics | Present in source |
| Jentra Control | /control | Present in source |

Additional scope: Jentra Employee is implemented; device and distribution acceptance remain open. The separate Jentra Sales app remains a blueprint. Employee self service, cases, documents and push have candidate backend additions. Extra company and staff administration needs completion or reviewed provisioning. Statutory payroll, live payment collection and production recovery certification remain open.

## Related launch records

[Download the Word manual](<Jentra OS Company Setup and Operating Guide.docx>). Read the [capability completeness review](feature-completeness.md) for functional gaps, the [43-section inventory](feature-inventory.csv) for route inclusion, and the [launch readiness record](../development/launch-readiness-20261028.md) for verified results and pending launch gates.

