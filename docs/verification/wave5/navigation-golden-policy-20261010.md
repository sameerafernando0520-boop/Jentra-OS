# Navigation golden policy review — October 10, 2026

The 16 navigation cases should retain their current limited capability fixtures. Their proposed exact r13 images remove People, Projects, Service and Analytics and move the Intelligence heading to Jentra Control. This matches current permission policy; no navigation or fixture source defect was confirmed. Original approved PNGs remain unchanged. Owner visual approval and a verified isolated candidate suite are still required.

## Scope and trace

Refreshed external HEAD: 1b03ad09af331262534f535762148b1beeaf8fa4. The shared checkout was clean at this scope refresh. Primary boundary: the three shell files (1330 lines). Permission data flows from controlled fixtures through businessCapabilitiesProvider and visibleJentraDestinations to both the sidebar and command palette. Quick-create reads the same capability set. This diagnosis reads no secrets, environment files, private sessions or acceptance stores and performs no live operations.

The representative approved dashboard, CRM, quick-create and warehouse PNGs were last changed in e307d15 on September 11. The current navigation diff adds capability gates after that baseline. FR-244/FR-383/FR-388 require routes and actions to respect server-resolved capabilities; the design system preserves section headings after filtering. This supports updating the reviewed images rather than granting unrelated capabilities.

## Fixture decisions

| Fixture | Cases | Intended controlled role | Decision |
|---|---:|---|---|
| foundation | 13 | Controlled development preview of the foundation dashboard/setup administrator, with quotation-read navigation; no People, Projects, Service or Analytics workspace authority. | Preserve current capability set; propose exact r13 baseline for review. |
| crm | 1 | Controlled populated CRM manager and quotation viewer. | Preserve current capability set; propose exact r13 baseline for review. |
| quickCreate | 1 | Controlled party, quotation and invoice creator; only three implemented quick-create links. | Preserve current capability set; propose exact r13 baseline for review. |
| warehouse | 1 | Controlled warehouse setup manager in a selected branch, with memory-only drafts. | Preserve current capability set; propose exact r13 baseline for review. |

### foundation

[Fixture source](../../../apps/jentra_desktop/test/jentra_app_test.dart). AC-1/AC-7/AC-216/EC-224 exercise foundation geometry, dashboard sample evidence and setup forms, not an all-modules privileged role. analytics.reports.view is a setup-report permission and is not analytics.view.

Exact capabilities:

- `analytics.reports.manage`
- `analytics.reports.view`
- `core.files.manage`
- `core.files.view`
- `core.setup.manage`
- `core.setup.view`
- `crm.parties.manage`
- `crm.parties.view`
- `finance.setup.manage`
- `finance.setup.view`
- `inventory.catalog.manage`
- `inventory.catalog.view`
- `sales.quotations.view`
- `workflow.configure`

Current source-derived visible paths/group headings: `/dashboard (WORKSPACE)`, `/setup (FOUNDATION)`, `/sales (OPERATIONS)`, `/procurement`, `/finance (MANAGEMENT)`, `/control (INTELLIGENCE)`. These path lists are source-derived; this slice ran no new Flutter test.

### crm

[Fixture source](../../../apps/jentra_desktop/test/crm_workspace_test.dart). CRM opportunity permission permits CRM; the Analytics workspace additionally requires analytics.view, which this role does not have. HR/project/service authority is unrelated to the tested CRM actions.

Exact capabilities:

- `crm.activities.manage`
- `crm.leads.convert`
- `crm.leads.manage`
- `crm.leads.view`
- `crm.opportunities.manage`
- `crm.opportunities.view`
- `sales.quotations.view`

Current source-derived visible paths/group headings: `/dashboard (WORKSPACE)`, `/crm (OPERATIONS)`, `/sales`, `/procurement`, `/finance (MANAGEMENT)`, `/control (INTELLIGENCE)`. These path lists are source-derived; this slice ran no new Flutter test.

### quickCreate

[Fixture source](../../../apps/jentra_desktop/test/quick_create_test.dart). The fixture deliberately omits Purchase request, Task and Service ticket actions. Adding unrelated People/project/service/analytics grants would weaken the declared scope of this quick-create test.

Exact capabilities:

- `crm.parties.manage`
- `crm.parties.view`
- `sales.invoices.manage`
- `sales.invoices.view`
- `sales.quotations.manage`
- `sales.quotations.view`

Current source-derived visible paths/group headings: `/dashboard (WORKSPACE)`, `/setup (FOUNDATION)`, `/sales (OPERATIONS)`, `/procurement`, `/receivables`, `/finance (MANAGEMENT)`, `/control (INTELLIGENCE)`. These path lists are source-derived; this slice ran no new Flutter test.

### warehouse

[Fixture source](../../../apps/jentra_desktop/test/warehouse_setup_test.dart). Contract 19 requires core.setup.manage for the scoped warehouse command and retains existing read policy. It does not grant HR, projects, service, analytics or stock-cost/posting authority.

Exact capabilities:

- `core.setup.manage`
- `core.setup.view`

Current source-derived visible paths/group headings: `/dashboard (WORKSPACE)`, `/setup (FOUNDATION)`, `/procurement (OPERATIONS)`, `/finance (MANAGEMENT)`, `/control (INTELLIGENCE)`. These path lists are source-derived; this slice ran no new Flutter test.

## Private HR and section behavior

`people.view` makes Private HR & account available for the account workflow. Dedicated HR permissions control its private views; plain People access yields My account only and no private contacts or subjects, as the existing private_hr_workspace_test verifies. The four current fixtures lack people.view. Adding it and then hiding the account entry to match an old screenshot would contradict the intended account behavior.

People requires people.view plus people.employees.view; Projects requires projects.view; Service requires service.view; Analytics requires analytics.view plus opportunity view/manage. analytics.reports.view in setup does not confer analytics.view. When Analytics is absent, the pending Intelligence heading moves to Jentra Control, preserving the design-system grouping contract. Existing placeholder destinations and unrelated permission rules remain unchanged.

## Exact candidates

Each approved/current/difference file below was freshly SHA-256 checked. All proposed images are unchanged r13 original-fixture bytes, identical to the previously inspected r10 images. Five representative approved/current pairs were independently viewed in this slice; the all-case inspection and exact r13/r10 bindings remain in the separate recorded investigation. Sparse body border/corner pixels also differ, so approval must cover each full candidate image. No comparator exception is proposed. Full hashes, capabilities and source bindings are in [the JSON manifest](navigation-golden-policy-20261010.json).

| Case | Fixture | Current approved | Proposed exact r13 image | Isolated difference | Sidebar/body differing pixels |
|---|---|---|---|---|
| crm_1440_light_comfortable | crm | [approved](../../../apps/jentra_desktop/test/goldens/crm_1440_light_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/crm_1440_light_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/crm_1440_light_comfortable_isolatedDiff.png) | 19711/2715 |
| setup_1024_light_compact_text_200 | foundation | [approved](../../../apps/jentra_desktop/test/goldens/setup_1024_light_compact_text_200.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1024_light_compact_text_200_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1024_light_compact_text_200_isolatedDiff.png) | 5288/1968 |
| dashboard_1024_light_compact | foundation | [approved](../../../apps/jentra_desktop/test/goldens/dashboard_1024_light_compact.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1024_light_compact_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1024_light_compact_isolatedDiff.png) | 5288/2280 |
| dashboard_1024_dark_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/dashboard_1024_dark_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1024_dark_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1024_dark_comfortable_isolatedDiff.png) | 5288/2387 |
| dashboard_1440_light_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/dashboard_1440_light_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1440_light_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1440_light_comfortable_isolatedDiff.png) | 19711/2995 |
| dashboard_1440_dark_compact | foundation | [approved](../../../apps/jentra_desktop/test/goldens/dashboard_1440_dark_compact.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1440_dark_compact_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1440_dark_compact_isolatedDiff.png) | 19711/3155 |
| dashboard_1920_light_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/dashboard_1920_light_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1920_light_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1920_light_comfortable_isolatedDiff.png) | 19711/3905 |
| dashboard_1920_dark_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/dashboard_1920_dark_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1920_dark_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/dashboard_1920_dark_comfortable_isolatedDiff.png) | 19711/4126 |
| setup_1024_light_compact | foundation | [approved](../../../apps/jentra_desktop/test/goldens/setup_1024_light_compact.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1024_light_compact_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1024_light_compact_isolatedDiff.png) | 5288/2234 |
| setup_1024_dark_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/setup_1024_dark_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1024_dark_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1024_dark_comfortable_isolatedDiff.png) | 5288/2296 |
| setup_1440_light_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/setup_1440_light_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1440_light_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1440_light_comfortable_isolatedDiff.png) | 19711/2948 |
| setup_1440_dark_compact | foundation | [approved](../../../apps/jentra_desktop/test/goldens/setup_1440_dark_compact.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1440_dark_compact_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1440_dark_compact_isolatedDiff.png) | 19711/3069 |
| setup_1920_light_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/setup_1920_light_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1920_light_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1920_light_comfortable_isolatedDiff.png) | 19711/2961 |
| setup_1920_dark_comfortable | foundation | [approved](../../../apps/jentra_desktop/test/goldens/setup_1920_dark_comfortable.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1920_dark_comfortable_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/setup_1920_dark_comfortable_isolatedDiff.png) | 19711/3073 |
| quick_create_workspace_links | quickCreate | [approved](../../../apps/jentra_desktop/test/goldens/quick_create_workspace_links.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/quick_create_workspace_links_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/quick_create_workspace_links_isolatedDiff.png) | 19711/2447 |
| warehouse_setup_form | warehouse | [approved](../../../apps/jentra_desktop/test/goldens/warehouse_setup_form.png) | [candidate](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/warehouse_setup_form_testImage.png) | [difference](../../../build/w5win9r13/preview/apps/jentra_desktop/test/failures/warehouse_setup_form_isolatedDiff.png) | 19711/2473 |

## Gates and next action

The actual r13 desktop suite remains 1,921 pass / 83 fail / zero skipped. The root agent is preparing the combined 83-case visual gallery and an isolated strict suite using exact proposed candidate images. That result can validate candidate consistency, but cannot authorize replacing approved PNGs or accept any of the 109 requirements. Only an explicit owner decision on the concrete exact-image set can authorize the corresponding baseline update.

This slice changes only the new MD/JSON review records. Production sources, test fixtures, approved PNGs, comparator, all runtime 92a68a58 artifacts, migrations, roles, accounts and sessions are preserved. After any approved baseline replacement, collect fresh strict-suite/source/build bindings and compose a superseding runtime review if its bound inputs change. Genuine native keyboard/MFA, actual delivery, contention/load and owner acceptance remain separate.

## Reviewed source and contracts

- [apps/jentra_desktop/lib/src/shell/navigation.dart](../../../apps/jentra_desktop/lib/src/shell/navigation.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/lib/src/shell/jentra_shell.dart](../../../apps/jentra_desktop/lib/src/shell/jentra_shell.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/lib/src/shell/quick_create_dialog.dart](../../../apps/jentra_desktop/lib/src/shell/quick_create_dialog.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/lib/src/app_providers.dart](../../../apps/jentra_desktop/lib/src/app_providers.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/test/jentra_app_test.dart](../../../apps/jentra_desktop/test/jentra_app_test.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/test/crm_workspace_test.dart](../../../apps/jentra_desktop/test/crm_workspace_test.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/test/quick_create_test.dart](../../../apps/jentra_desktop/test/quick_create_test.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/test/warehouse_setup_test.dart](../../../apps/jentra_desktop/test/warehouse_setup_test.dart), matched frozen r13 base-source hash.
- [packages/jentra_domain/lib/src/business_setup.dart](../../../packages/jentra_domain/lib/src/business_setup.dart), matched frozen r13 base-source hash.
- [packages/jentra_domain/lib/src/stock_opening.dart](../../../packages/jentra_domain/lib/src/stock_opening.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/lib/src/features/people/private_hr_controller.dart](../../../apps/jentra_desktop/lib/src/features/people/private_hr_controller.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/test/private_hr_workspace_test.dart](../../../apps/jentra_desktop/test/private_hr_workspace_test.dart), matched frozen r13 base-source hash.
- [apps/jentra_desktop/test/quotation_navigation_test.dart](../../../apps/jentra_desktop/test/quotation_navigation_test.dart), matched frozen r13 base-source hash.
- [docs/blueprint/04_DESIGN_SYSTEM.md](../../blueprint/04_DESIGN_SYSTEM.md).
- [docs/blueprint/05_TEST_AND_DELIVERY.md](../../blueprint/05_TEST_AND_DELIVERY.md).
- [docs/blueprint/06_WAVE2_SHARED_FOUNDATION_SPEC.md](../../blueprint/06_WAVE2_SHARED_FOUNDATION_SPEC.md).
- [docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md](../../blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md).
- [docs/blueprint/19_WAREHOUSE_SETUP_CONTRACT.md](../../blueprint/19_WAREHOUSE_SETUP_CONTRACT.md).
- [docs/blueprint/42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md](../../blueprint/42_WAVE4_PRIVATE_HR_ORGANIZATION_CALENDAR_CONTRACT.md).
- [docs/blueprint/47_WAVE4_PRIVATE_HR_DELIVERY_CONTRACT.md](../../blueprint/47_WAVE4_PRIVATE_HR_DELIVERY_CONTRACT.md).

[Retained 83-case investigation](continuation-goldens-native-20261009.md), [exact r13 comparison](continuation-goldens-comparison-20261009-r13.json) and [current native report](windows-test-verification-20261009-r13.md).
