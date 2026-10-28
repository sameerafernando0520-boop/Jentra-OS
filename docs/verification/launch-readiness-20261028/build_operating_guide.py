from pathlib import Path
import csv
import hashlib
import json
import re

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs" / "user-guide"
OUT.mkdir(parents=True, exist_ok=True)
DOCX = OUT / "Jentra OS Company Setup and Operating Guide.docx"

pages = [
("Jentra OS Company Setup and Operating Guide", [
("p", "Owner and team manual for setting up a real company group and running daily business operations. Prepared on 28 October 2026 from the current Jentra OS workspace."),
("h", "Start here"),
("p", "Use the Windows application for administration and business operations. Use Jentra Employee for the employee's own records and requests. First establish the correct company structure, access and opening balances; then test complete business journeys before wider use."),
("table", (["Your task", "Read"], [
["Create the group and prepare real data", "Pages 2 and 3"],
["Run sales purchases and stock", "Page 4"],
["Run finance and employee workflows", "Page 5"],
["Use projects service assets and audit", "Page 6"],
["Understand analytics and AI", "Page 7"],
["Run the pilot and daily controls", "Page 8"],
["Check what is included", "Pages 9 and 10 and feature inventory CSV"],
])),
("h", "Current launch position"),
("p", "The main business modules, analytics and reviewed AI workflows are implemented in source. Source availability does not establish that every module is enabled or installed in your selected database. The current desktop test suite passed 2322 tests. Production configuration and real company acceptance remain separate checks."),
("table", (["Item", "Current position"], [
["Company group", "Enter your own registered details after the target workspace is confirmed."],
["Stored test companies", "Cleanup is pending a verified company inventory. The saved management connection is currently invalid."],
["Employee HR additions", "New self service and notification producers exist as candidate SQL. Installation and push activation need the reviewed rollout."],
["AI service", "Application and worker adapters exist. Current hosted model configuration and actual usage are not freshly verified."],
["Payroll", "Current implementation is synthetic payroll. Statutory and payment acceptance are required before real salary use."],
])),
("p", "Record your group name, administrator, operating entities and pilot start date in your internal rollout record. Keep this guide with the approved release version and support contact.")
]),
("Prepare the company group", [
("h", "Understand the company hierarchy"),
("p", "A business group is the workspace boundary. A legal entity is a registered company inside that group. A branch is an operating location inside a legal entity. Check all three selections before entering or approving a document. Selecting a branch does not transfer another company's balances or permissions."),
("h", "Remove the correct test companies"),
("steps", [
"Have the administrator restore the Supabase management connection and identify the exact project used by this installation.",
"Obtain the current company names and IDs from that project. Classify each as a named test company or a company to retain. Source fixtures and old reports are not a current database inventory.",
"Take an approved database and private file backup, and verify the recovery procedure before permanent cleanup.",
"Review all linked records for the named test companies, including users, files, finance, stock, HR and audit history. Perform the reviewed tenant cleanup only for those IDs.",
"Verify retained companies and user access after cleanup. Do not delete your existing business records merely to make the home screen look empty."
]),
("h", "Create the first real workspace"),
("steps", [
"Launch the administrator supplied connected build and sign in using your own account. Complete MFA when requested.",
"Open the first workspace setup form. Enter Business group name and a unique Workspace slug.",
"Enter Registered entity name and Entity code using the first company's real details.",
"Enter Branch name and Branch code. Confirm Head Office and HQ only if those values match your intended first branch.",
"Submit once. If the result is unconfirmed, retry the same request rather than creating another workspace.",
"After confirmation, select the new group, legal entity and branch and verify the scope shown in the application."
]),
("p", "The current setup wizard creates the first entity and branch. A complete general administration screen for adding every extra entity, branch and staff role was not found in the current application. Arrange reviewed administrator provisioning for the rest of your group before testing cross company workflows. Do not represent a second legal company as a warehouse or department of the first.")
]),
("Configure access and business foundations", [
("h", "Give each person an individual account"),
("p", "The workspace creator becomes the owner. Assign access by job, legal entity and branch. Sharing an owner account prevents reliable attribution and independent approval. Staff invitation support exists in the backend; the general invitation and role administration interface still needs completion or reviewed administrator provisioning."),
("table", (["Person", "Typical responsibility"], [
["Owner or administrator", "Company structure access and release coordination"],
["Finance preparer and separate approver", "Documents allocations journals reconciliation and period review"],
["Sales and purchasing staff", "Their customer or supplier documents within the allowed branch"],
["Warehouse staff", "Receipts fulfillment transfers and counts"],
["HR staff and independent reviewer", "Employment private HR attendance leave and payroll review"],
["Auditor and process owner", "Evidence findings responses and remediation under audit access"],
["Employee", "Own accepted employee link and permitted self service records"],
])),
("h", "Complete Business setup in a controlled order"),
("steps", [
"Confirm currencies and exchange rates, then configure the chart of accounts and fiscal periods with the responsible finance reviewer.",
"Review tax definitions and document numbering before issuing real documents. This guide does not prescribe tax rates or statutory rules.",
"Create customers and suppliers under Parties, then their contacts. Check legal names and duplicate records.",
"Create units and valid conversions before products. Set product classifications and warehouse records for the intended branch.",
"Configure workflow definitions and approval matrix steps. Test that the preparer cannot approve their own restricted transaction.",
"Review file access, notifications and report definitions. Import and export job registers are present, but each actual import/export provider needs its own acceptance check."
]),
("h", "Load opening records once"),
("p", "Agree one cutoff date and signed opening balances. Reconcile the opening trial balance, customer and supplier balances, bank balances, quantities, lots or serials and stock value. Use the relevant reviewed opening workflow and an independent approval. Compare the resulting reports with the signed source records before entering normal transactions. Retain the opening document references to prevent duplicate loading.")
]),
("Run sales purchases and inventory", [
("h", "Sales and customer money"),
("steps", [
"Use CRM and Revenue to record leads and opportunities with a responsible owner and next action.",
"Prepare a quotation in Sales. Verify customer, branch, quantities, unit conversions, prices, currency, tax and validity before confirming it.",
"Create the sales order from the accepted commercial record. Review reservations and credit or approval requirements.",
"Use Fulfillment and receivables to record the actual dispatch or service fulfillment and issue the relevant invoice through the allowed workflow.",
"Record a customer receipt only when the actual payment evidence exists, then allocate it to the correct open invoices.",
"Process returns and credits through their source documents. Check that quantities, outstanding balances and journal effects match the intended correction."
]),
("h", "Purchasing and supplier money"),
("steps", [
"Create a requisition and use sourcing or RFQ comparison when your purchasing policy requires it.",
"Create the purchase order for the correct supplier, branch, currency and warehouse.",
"Receive only the goods actually accepted. Record lot, serial and unit details where required and retain the receipt reference.",
"Enter the supplier bill and review differences between the order, receipt and invoice before posting.",
"Record and allocate a supplier payment from actual bank or cash evidence. Keep approval and reconciliation separate.",
"Use purchase returns and settlement correction workflows for reversals. Preserve the original transaction history."
]),
("h", "Warehouse operating rules"),
("p", "Check the active company and warehouses before a transfer. Track both source and destination and verify the transfer reaches its final state. For stock counts, follow the count cutoff and review variances before approval. Use reservations, receipt quantity trace, landed allocations, inventory valuation and disposition for their specific purposes; do not fix stock by entering an unrelated purchase or sale."),
("p", "Work offline only on supported drafts. Inventory, payments, approval and ledger posting need a confirmed online result. An uncertain result is not proof that nothing happened: retain the original request and use its recovery or retry action.")
]),
("Run finance and people operations", [
("h", "Finance responsibilities"),
("p", "Use Manual journals for reviewed adjustments and preserve their supporting evidence. Use Financial dimensions for reporting classifications, Bank reconciliation for matching statement items, Financial statements for posted results, Tax review for reviewed summaries, Cash flow mappings for classification and Budgets and variance for comparison."),
("steps", [
"Each day compare receipt and payment records with actual evidence, review unallocated amounts and investigate unexpected balances.",
"Review Finance controls and Control and close review for exceptions before closing a period.",
"Reconcile receivables, payables, inventory control and bank or cash to the general ledger.",
"Review open documents, adjustments, foreign exchange and supporting reports. Obtain the finance approver's acceptance before a period close.",
"Use the supported reversal or correction when an issued transaction is wrong. Keep the reason and link to the original document."
]),
("h", "HR and workforce"),
("p", "In People, establish the employee record, dated employment, Work calendars and Organization assignments before recording attendance or leave. Use Private HR and account for protected content and accountable staff case handling. Use Attendance and leave for canonical time records, independent decisions and employee request intake."),
("steps", [
"Review current employment and branch dates before approving work or leave.",
"Review attendance evidence and select the matching independently approved canonical record when resolving an employee request.",
"Approve, reject or cancel using the owning attendance or leave workflow. A staff request outcome does not by itself create payable work.",
"Publish a private document explicitly to the intended employee only after review.",
"Treat payroll preparation, independent approval, posting, payslip publication, correction and payment evidence as distinct events."
]),
("h", "Jentra Employee"),
("p", "The employee signs in, selects an available workplace and accepts the correct employee account link. They can use the implemented own attendance, leave, payslip, review, case, document and inbox flows when their backend endpoints and permissions are available. MFA is required for protected actions. Downloaded private documents remain the employee's responsibility. Notifications carry a generic update; opening the app rechecks access."),
("p", "A message saying the service is not enabled means the reviewed backend rollout or entitlement is missing. It does not mean the employee should create a second account. Push sending remains a separate activation step.")
]),
("Run projects service assets and audit", [
("h", "Projects"),
("p", "Create the project with its customer, scope and responsible owner. Review milestones, approved time and expenses, service links and project finance before billing. Use the supported milestone and source consumption workflows so the same time or expense is not billed twice. Review a changed source before a later payroll or billing correction."),
("h", "Service and fixed assets"),
("p", "Use Service for tickets, work orders, labor, parts and completion under the assigned branch. Record actual work and consumed stock through the relevant source workflow. Review equipment or internal asset links before closing the work order."),
("p", "Use Fixed assets for the asset register, reviewed acquisition or capitalization, assignment, maintenance, depreciation and disposal flows supported by the installed release. Reconcile asset values with finance. A service completion, an asset disposal and the related financial posting are separate confirmations."),
("h", "Corporate Audit and Assurance"),
("steps", [
"Use Audit planning to maintain the universe, risk assessments and approved plans.",
"Create a scoped engagement and grant only the required team and process owner access through Audit access.",
"Map controls and request evidence. Upload and review the relevant private evidence; verify the file before relying on it.",
"Record procedures, samples and exceptions. Issue findings through the independent review workflow.",
"Capture management responses, risk decisions, remediation and independent retesting. Reopen a finding when the evidence requires it.",
"Freeze the appropriate evidence and issue a versioned report. Review legal holds, carry forward and governed exports before release.",
"Use Audit metrics for current evidence based process and finding measures."
]),
("h", "What an owner should review"),
("p", "A successful screen or automated test does not establish that a real employee, manager or external reviewer has the correct access. Include a positive authorized action and a denied action from another company in the pilot. Review the audit trail for actor, document, revision and result. Capture acceptance by the responsible business owner.")
]),
("Use analytics and the AI intelligent section", [
("h", "Analytics that do not require a language model"),
("table", (["Analytics tab", "How to use it"], [
["Process", "Choose the authorized process scope and period and inspect the source based metrics."],
["Pipeline", "Review opportunities probabilities and horizons before relying on a forecast."],
["Historical pipeline", "Compare published historical and realized results using compatible periods."],
["Financial ratios", "Select compatible published statements and reviewed classifications."],
["Cash scenarios", "Compare hypothetical timing changes with the dated authoritative baseline."],
["Integrations", "Review scoped subscriptions credentials and delivery outcomes. A worker and destination must be configured."],
["Governed exports", "Generate or reopen an allowed export and verify its source and access evidence."],
])),
("h", "Reviewed AI requests in Jentra Control"),
("p", "The current AI implementation is a governed forecast assistance workflow. It has an OpenAI Responses adapter and a reviewed model worker. It is not a general chatbot or an autonomous operator for every module. The actual model, server credentials, quotas and current hosted runtime must be configured and verified by the administrator."),
("steps", [
"Select the correct entity and branch and open Jentra Control with the required proposal permission.",
"Use an authorized current pipeline forecast and its exact source reference. Review the scope, currency, horizon and source evidence.",
"Request a reviewed suggestion only when the model service is available and the allowance permits it.",
"Check the suggestion against the source. The worker validates its limited command and source identity; a suggestion does not execute a business transaction.",
"If appropriate, submit an explicit human proposal. A different authorized MFA approver reviews the exact revision before the separately permitted execution action.",
"If the outcome is pending or unknown, reopen the saved original request. Do not submit replacements to bypass an unresolved reservation."
]),
("p", "The present allowlisted AI action concerns pipeline forecast freezing. Do not expect automatic payroll, purchasing, stock, payment or journal posting from the AI section. Keep model credentials on the server. Actual trusted usage, cost limits, access revocation and one real provider response must pass the pilot before this feature is advertised as active.")
]),
("Operate daily and complete the company pilot", [
("h", "Daily checklist"),
("steps", [
"Confirm the release, sign in and check business group, entity, branch and current access.",
"Review notifications, pending approvals and any unconfirmed requests before entering new work.",
"Enter actual business activity, retain source documents and verify each confirmed outcome.",
"Review stock exceptions, unallocated customer or supplier money, failed integrations and employee requests.",
"Sign out on a shared device. Lock private screens when leaving the desk and protect exported files."
]),
("h", "When something goes wrong"),
("table", (["Message or situation", "Action"], [
["Permission denied or MFA required", "Recheck your account and scope. Complete MFA or contact the administrator; do not use a colleague's account."],
["Record changed or version conflict", "Reload and review the current revision before making a new decision."],
["Unconfirmed or uncertain result", "Keep the original command and use its recovery or retry option before starting another."],
["Service not installed or provider unavailable", "Ask the administrator to check the installed release entitlement and worker configuration."],
["Draft or protected storage failure", "Preserve the device and recovery information. Avoid clearing app data while an unresolved draft exists."],
])),
("h", "Pilot acceptance before wider rollout"),
("p", "Test one complete sale through receipt, one purchase through payment, stock receipt and transfer, a count variance, an accounting close review, an employee request and private document, and an audit evidence cycle. Test AI separately with a real approved provider response. Compare resulting stock and finance reports with the expected business results."),
("p", "Test a second company and a restricted branch user to prove separation. Restart the app with an unfinished draft, recover an uncertain operation and confirm access removal takes effect. Rehearse database and private file restoration. Review monitoring and support ownership. Obtain the company owner's written acceptance before general use."),
("p", "Current gaps include complete group and staff administration, the separate Jentra Sales app, verified production configuration, HR candidate rollout, worker/model/push activation, signed distribution and real company acceptance. The following inventory records source inclusion; it is not a production certification.")
]),
]

navigation = (ROOT / "apps/jentra_desktop/lib/src/shell/navigation.dart").read_text(encoding="utf-8")
router = (ROOT / "apps/jentra_desktop/lib/src/router.dart").read_text(encoding="utf-8")
block = navigation.split("const jentraDestinations = <JentraDestination>[", 1)[1].split("\n];", 1)[0]
routes = set(re.findall(r"GoRoute\(\s*path:\s*'([^']+)'", router))
features = []
for item in re.findall(r"JentraDestination\((.*?)\n  \)", block, re.S):
    label = re.search(r"label:\s*'([^']+)'", item)
    path = re.search(r"path:\s*'([^']+)'", item)
    if label and path:
        features.append({"feature": label[1], "route": path[1], "route_present": path[1] in routes,
                         "source_status": "Screen route present" if path[1] in routes else "Route requires review",
                         "production_status": "Requires installed backend access and company pilot"})
assert features and all(f["route_present"] for f in features), "Every advertised destination must have a route"
for start in range(0, len(features), 22):
    rows = [[f["feature"], f["route"], "Present in source"] for f in features[start:start+22]]
    pages.append(("Feature inclusion inventory" + (" continued" if start else ""), [
        ("p", "All advertised desktop navigation destinations below have matching routes in the current source. Availability also depends on sign in, permissions, plan entitlements and installed backend contracts. This check does not prove each production workflow."),
        ("table", (["Feature", "Application route", "Inclusion"], rows)),
        ("p", "Additional scope: Jentra Employee is implemented; device and distribution acceptance remain open. The separate Jentra Sales app remains a blueprint. Employee self service, cases, documents and push have candidate backend additions. Extra company and staff administration needs completion or reviewed provisioning. Statutory payroll, live payment collection and production recovery certification remain open.")
    ]))

doc = Document()
section = doc.sections[0]
section.page_width, section.page_height = Inches(8.5), Inches(11)
section.top_margin = section.bottom_margin = Inches(0.65)
section.left_margin = section.right_margin = Inches(0.72)
section.header_distance = section.footer_distance = Inches(0.25)
normal = doc.styles["Normal"]
normal.font.name, normal.font.size = "Arial", Pt(10.5)
normal.paragraph_format.space_after = Pt(7)
normal.paragraph_format.line_spacing = 1.06
for name in ["Title", "Heading 1", "Heading 2"]:
    style = doc.styles[name]
    style.font.name = "Arial"
    style.font.color.rgb = RGBColor(0, 0, 0) if name == "Title" else RGBColor(28, 52, 72)
    style.paragraph_format.keep_with_next = True
    style.paragraph_format.space_after = Pt(9)
    style.paragraph_format.space_before = Pt(9)
doc.styles["Title"].font.size = Pt(27)
doc.styles["Heading 1"].font.size = Pt(19)
doc.styles["Heading 2"].font.size = Pt(12)
for style in doc.styles:
    if style.type == 1 and style.element.pPr is not None:
        for border in list(style.element.pPr.findall(qn("w:pBdr"))):
            style.element.pPr.remove(border)
header = section.header.paragraphs[0]
header.text = "JENTRA OS   COMPANY GROUP OPERATING GUIDE"
header.style = doc.styles["Normal"]
for run in header.runs:
    run.font.size, run.font.color.rgb = Pt(8), RGBColor(95, 105, 115)
footer = section.footer.paragraphs[0]
footer.text = "28 October 2026   |   Owner and team guide"
footer.paragraph_format.space_after = Pt(0)
footer.add_run("                                                 ")
field = OxmlElement("w:fldSimple")
field.set(qn("w:instr"), "PAGE")
footer._p.append(field)
for run in footer.runs:
    run.font.size, run.font.color.rgb = Pt(8), RGBColor(95, 105, 115)
markdown = []
for index, (title, items) in enumerate(pages):
    if index:
        doc.add_page_break()
    doc.add_paragraph(title, "Title" if index == 0 else "Heading 1")
    markdown.append(("# " if index == 0 else "## ") + title + "\n")
    previous_kind = None
    for kind, text in items:
        if kind == "h":
            doc.add_paragraph(text, "Heading 2")
            markdown.append("### " + text + "\n")
        elif kind == "p":
            paragraph = doc.add_paragraph(text)
            if previous_kind == "table":
                paragraph.paragraph_format.space_before = Pt(8)
            markdown.append(text + "\n")
        elif kind == "steps":
            for number, item in enumerate(text, 1):
                p = doc.add_paragraph()
                p.paragraph_format.left_indent = Inches(0.16)
                p.paragraph_format.first_line_indent = Inches(-0.16)
                p.add_run(str(number) + ". ").bold = True
                p.add_run(item)
                markdown.append(str(number) + ". " + item)
            markdown.append("")
        elif kind == "table":
            headers, rows = text
            table = doc.add_table(rows=1, cols=len(headers))
            table.style = "Light Shading Accent 1"
            table.autofit = False
            widths = [2.0, 5.06] if len(headers) == 2 else [2.2, 3.3, 1.56]
            for col, width in zip(table.columns, widths):
                col.width = Inches(width)
            for cell, heading in zip(table.rows[0].cells, headers):
                cell.text = heading
            repeat = OxmlElement("w:tblHeader")
            table.rows[0]._tr.get_or_add_trPr().append(repeat)
            for row in rows:
                for cell, value in zip(table.add_row().cells, row):
                    cell.text = value
            for row_index, row in enumerate(table.rows):
                trpr = row._tr.get_or_add_trPr()
                no_split = OxmlElement("w:cantSplit")
                trpr.append(no_split)
                for cell in row.cells:
                    for p in cell.paragraphs:
                        p.paragraph_format.space_after = Pt(5)
                        p.paragraph_format.space_before = Pt(4)
                        p.paragraph_format.line_spacing = 1.0
                        for run in p.runs:
                            run.font.name, run.font.size = "Arial", Pt(9.5)
                            run.font.color.rgb = RGBColor(28, 52, 72) if row_index == 0 else RGBColor(30, 35, 40)
                            if row_index == 0:
                                run.bold = True
            markdown += ["| " + " | ".join(headers) + " |",
                         "| " + " | ".join(["---"] * len(headers)) + " |"]
            markdown += ["| " + " | ".join(row) + " |" for row in rows]
            markdown.append("")
        previous_kind = kind
doc.core_properties.title = "Jentra OS Company Setup and Operating Guide"
doc.core_properties.subject = "Company group setup operations feature inclusion and pilot acceptance"
doc.core_properties.author = "Jentra OS"
doc.core_properties.keywords = "company setup operations analytics AI employee pilot"
doc.save(DOCX)
markdown += ["## Related launch records", "",
             "[Download the Word manual](<Jentra OS Company Setup and Operating Guide.docx>). "
             "Read the [capability completeness review](feature-completeness.md) for functional gaps, "
             "the [43-section inventory](feature-inventory.csv) for route inclusion, and the "
             "[launch readiness record](../development/launch-readiness-20261028.md) for verified results and pending launch gates.", ""]
(OUT / "README.md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
with (OUT / "feature-inventory.csv").open("w", encoding="utf-8-sig", newline="") as file:
    writer = csv.DictWriter(file, fieldnames=list(features[0]))
    writer.writeheader()
    writer.writerows(features)
report = {"date": "2026-10-28", "kind": "source-feature-inclusion",
          "advertised_destinations": len(features), "matching_routes": sum(f["route_present"] for f in features),
          "production_certified": False, "features": features,
          "known_incomplete": ["general extra legal entity and branch administration UI",
            "general staff invitation and role administration UI",
            "production target backup restore monitoring and company pilot acceptance",
            "reviewed employee HR candidate rollout and push activation",
            "freshly verified hosted AI model provider and trusted usage",
            "standalone Jentra Sales app is not implemented",
            "employee physical-device and platform distribution acceptance",
            "statutory payroll and real payment certification"],
          "sources": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in [
            "apps/jentra_desktop/lib/src/shell/navigation.dart",
            "apps/jentra_desktop/lib/src/router.dart",
            "apps/jentra_desktop/lib/main.dart",
            "packages/jentra_platform/lib/src/analytics/reviewed_model_gateway.dart",
            "workers/wave5/openai_model_adapter.mjs"]}}
(OUT / "feature-inventory.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"docx": str(DOCX), "planned_pages": len(pages),
                  "destinations": len(features), "all_advertised_routes_present": True}))
