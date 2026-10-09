# Full desktop rendered investigation — r10

The fresh full desktop suite reports **1909 passed / 83 failed** (exit 1). [Machine evidence](full-desktop-golden-investigation-20261009-r10.json) binds every failure, approved/current/master/diff hashes and the exact full-suite log. Categories: golden=83. Approved goldens were preserved.

65 current golden images exactly match an earlier independently preserved HEAD control image in [the October 2 control](../remaining-wave3/golden-control-20261002.json). This proves that those exact render differences existed earlier. The [October 3 primitive probe](../remaining-wave3/golden-cause-20261003.md) establishes Flutter SDK rounded-border raster differences on identical source; it does not establish that every full-screen mismatch has that cause. Catalogue diff inspection shows rounded-edge pixels. CRM current/master inspection shows omitted People/Projects/Service/Analytics destinations in the current limited-capability fixture. The 13 dashboard/setup cases retain the [earlier focused investigation](shared-golden-investigation-20261008.md). Fixture/navigation reconciliation and any changed approved image still require review.

The earlier run's 26 empty capture-destination failures came from the Windows test runner environment. The capture wrapper omits empty task variables before launching Flutter. Dart source, assertions and approved PNGs were unchanged; earlier failed logs remain preserved at windows-test-preview-desktopAll-capture-env-failure-20261009-r10.log. This runner correction is separate from the remaining visual failures.

- crm_workspace_test.dart: CRM desktop composition matches its approved visual contract — AC-321 — golden
- design_system_catalogue_test.dart: logo-led catalogue 1024_light_compact — golden
- design_system_catalogue_test.dart: logo-led catalogue 1440_light_comfortable — golden
- design_system_catalogue_test.dart: logo-led catalogue 1440_dark_compact — golden
- design_system_catalogue_test.dart: logo-led catalogue 1920_dark_comfortable — golden
- goods_receipt_workspace_test.dart: goods receipt light at 200% preserves posting controls — golden
- goods_receipt_workspace_test.dart: goods receipt dark at 200% preserves posting controls — golden
- inventory_transfer_workspace_test.dart: transfer editor light at 200 percent — golden
- inventory_transfer_workspace_test.dart: transfer editor dark at 200 percent — golden
- inventory_valuation_workspace_test.dart: valuation light 200 percent — golden
- inventory_valuation_workspace_test.dart: valuation dark 200 percent — golden
- jentra_app_test.dart: Wave 2 setup remains reachable at 200% text scale — EC-224 — golden
- jentra_app_test.dart: dashboard golden 1024_light_compact — AC-1 / AC-7 — golden
- jentra_app_test.dart: dashboard golden 1024_dark_comfortable — AC-1 / AC-7 — golden
- jentra_app_test.dart: dashboard golden 1440_light_comfortable — AC-1 / AC-7 — golden
- jentra_app_test.dart: dashboard golden 1440_dark_compact — AC-1 / AC-7 — golden
- jentra_app_test.dart: dashboard golden 1920_light_comfortable — AC-1 / AC-7 — golden
- jentra_app_test.dart: dashboard golden 1920_dark_comfortable — AC-1 / AC-7 — golden
- jentra_app_test.dart: setup golden 1024_light_compact — AC-216 — golden
- jentra_app_test.dart: setup golden 1024_dark_comfortable — AC-216 — golden
- jentra_app_test.dart: setup golden 1440_light_comfortable — AC-216 — golden
- jentra_app_test.dart: setup golden 1440_dark_compact — AC-216 — golden
- jentra_app_test.dart: setup golden 1920_light_comfortable — AC-216 — golden
- jentra_app_test.dart: setup golden 1920_dark_comfortable — AC-216 — golden
- landed_value_workspace_test.dart: landed preview light 200 percent — golden
- landed_value_workspace_test.dart: landed preview dark 200 percent — golden
- payroll_workspace_test.dart: payroll workspace light at 200 percent text scale — golden
- payroll_workspace_test.dart: payroll workspace dark at 200 percent text scale — golden
- procurement_workspace_test.dart: AC-321 procurement editor light at 200% text — golden
- procurement_workspace_test.dart: AC-321 procurement editor dark at 200% text — golden
- product_unit_workspace_test.dart: product unit light at 200% — golden
- product_unit_workspace_test.dart: product unit dark at 200% — golden
- purchase_order_workspace_test.dart: purchase order light at 200% retains actions — golden
- purchase_order_workspace_test.dart: purchase order dark at 200% retains actions — golden
- purchase_return_workspace_test.dart: return editor light at 200 percent — golden
- purchase_return_workspace_test.dart: return editor dark at 200 percent — golden
- quick_create_test.dart: customer quick create opens the party workspace and its create control — golden
- quotation_workspace_test.dart: AC-303 renders exact saved offer and readable revision decisions — golden
- quotation_workspace_test.dart: AC-303 explicit conflict comparison retains reviewed local fields — golden
- quotation_workspace_test.dart: AC-303 editor visual and accessible state 1440_light — golden
- quotation_workspace_test.dart: AC-303 editor visual and accessible state 1440_dark — golden
- quotation_workspace_test.dart: AC-303 line editing preserves exact conversion and discount choice — golden
- receipt_trace_workspace_test.dart: receipt trace light at 200 percent — golden
- receipt_trace_workspace_test.dart: receipt trace dark at 200 percent — golden
- receivables_workspace_test.dart: invoice source detail renders exact totals and guarded actions — golden
- receivables_workspace_test.dart: invoice editor dark theme — golden
- receivables_workspace_test.dart: narrow editor at 200 percent text remains scrollable — golden
- receivables_workspace_test.dart: storage failure keeps the offline editor and offers retry — golden
- receivables_workspace_test.dart: uncertain result displays saved-command retry — golden
- receivables_workspace_test.dart: receipt editor offers governed tender and bank fields — golden
- receivables_workspace_test.dart: return editor requires original source and disposition — golden
- reservation_workspace_test.dart: dated reservation queue light 200 percent — golden
- reservation_workspace_test.dart: reservation light 200 percent review — golden
- reservation_workspace_test.dart: dated reservation queue dark 200 percent — golden
- reservation_workspace_test.dart: reservation dark 200 percent review — golden
- sales_order_workspace_test.dart: AC-304 rendered order_editor_1440_light — golden
- sales_order_workspace_test.dart: AC-304 rendered order_editor_1440_dark — golden
- sales_order_workspace_test.dart: AC-304 rendered order_editor_1024_text200 — golden
- sales_order_workspace_test.dart: AC-304 credit dialog explains exact exposure and reasoned override — golden
- sales_order_workspace_test.dart: AC-304 reservation UI bounds demand and available stock — golden
- sales_order_workspace_test.dart: AC-304 conflict UI requires inspection before keeping local edits — golden
- sales_order_workspace_test.dart: AC-304 accepted quotation opens explicit conversion fields — golden
- sourcing_recovery_test.dart: supplier quote editor light retains controls at 200% — golden
- sourcing_recovery_test.dart: supplier quote editor dark retains controls at 200% — golden
- stock_count_workspace_test.dart: serial identity count light at 200 percent — golden
- stock_count_workspace_test.dart: serial identity count dark at 200 percent — golden
- stock_count_workspace_test.dart: count editor light at 200 percent — golden
- stock_count_workspace_test.dart: count editor dark at 200 percent — golden
- stock_opening_workspace_test.dart: opening register shows exact value and status — golden
- stock_opening_workspace_test.dart: opening editor renders count lot details and exact preview — golden
- stock_opening_workspace_test.dart: opening editor supports dark theme — golden
- stock_opening_workspace_test.dart: 200 percent text remains scrollable without overflow — golden
- stock_opening_workspace_test.dart: posted opening presents immutable stock and journal references — golden
- stock_opening_workspace_test.dart: uncertain post shows durable retry and blocks replacement — golden
- supplier_bill_workspace_test.dart: supplier bill light at 200% retains match controls — golden
- supplier_bill_workspace_test.dart: supplier bill dark at 200% retains match controls — golden
- supplier_payment_workspace_test.dart: allocation correction light remains usable at 200 percent — golden
- supplier_payment_workspace_test.dart: dated AP statement light retains exact aging — golden
- supplier_payment_workspace_test.dart: payment proposal light at 200 percent — golden
- supplier_payment_workspace_test.dart: allocation correction dark remains usable at 200 percent — golden
- supplier_payment_workspace_test.dart: dated AP statement dark retains exact aging — golden
- supplier_payment_workspace_test.dart: payment proposal dark at 200 percent — golden
- warehouse_setup_test.dart: warehouse form uses selected branch and preserves scope on save — golden

No passing focused suite, current/master hash match or prior SDK diagnosis closes native acceptance or owner signoff. Unclassified failures remain open.
