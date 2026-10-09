# Fresh Windows test delivery — October 9, revision r10

The [portable Windows ZIP](../../../dist/Jentra OS Windows Test 20261009 r10.zip) contains Preview and Connected x64 apps built from ordinary `lib/main.dart`. Both launched and their fresh Preview workspace and Connected sign-in windows were inspected. All 68 packaged release hashes and each app's 1067 selected desktop dependency input hashes match. Three runner identity overlays exist only in the isolated build copies; preferences, sessions and encrypted drafts use separate identities from acceptance. Existing stores were not copied.

ZIP SHA-256: `3a42db82758049e0797a4f1a374933ae48a17538554704754bce78e091456a28`; 47209403 bytes. Extract the whole ZIP and use `Start Preview.cmd` or `Start Connected.cmd`. Preview supplies the existing sample dashboard; Connected uses the current development backend. Six proposed Wave 5 accounts remain uncreated. The Connected app now includes Create account and Windows Google PKCE return. Follow the [account/Google setup guide](windows-account-google-setup-20261009.md); Google is disabled live until privately configured. 17 loopback, provider availability and transport tests and 15 authentication UI/capability tests pass; two new auth renders were inspected. No real Google session or email confirmation delivery is claimed.

Scoped Dart analysis is clean. Fresh suites pass: 15 model gateway/control, 20 model workspace/controller/render, six command-palette keyboard, 96 cash/analytics workspace and two startup/navigation tests. The separate cash/model image captures rerun 12 variants each at 200% text, producing 60/24 images; these capture tests overlap the workspace suites and are not additional independent feature coverage. Eight cash, four model and two native startup images were visually inspected. [Machine evidence](windows-test-verification-20261009-r10.json) records hashes, source attribution, commands, times, process IDs and inspection lists.

Cash date, scenarios/recovery and reviewed-model request/recovery screens are implemented as source candidates. Recovered model fields show the saved source and UTC horizon. Explicit suggestion selection transfers the source to the human proposal form without issuing a command. Adjacent cash floating labels meet shared borders at 200% text; further visual polish and owner review remain open.

The r10 keyboard images did not show a command palette. The repeat own-window probe could not acquire foreground and aborted before keys. Six widget keyboard tests pass; native keyboard remains open. Native keyboard/restart/revocation, actual login/MFA/export/model/worker behavior, independent contention, target-scale load and owner acceptance remain unverified. The 13 shared golden failures remain open and no approved golden was replaced. Original installed SQL, candidate rollback, controlled tests/renders and authenticated acceptance are separate evidence gates. No new migration, account, entitlement, secret, worker or standard OS profile was provisioned.

## Broader current-source regression suites

[platformAll log](windows-test-preview-platformAll-20261009-r10.log): 1127 passed, 0 failed; exit 0.

[desktopAll log](windows-test-preview-desktopAll-20261009-r10.log): 1909 passed, 83 failed; exit 1.

- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/crm_workspace_test.dart: CRM desktop composition matches its approved visual contract — AC-321
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/design_system_catalogue_test.dart: logo-led catalogue 1024_light_compact
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/design_system_catalogue_test.dart: logo-led catalogue 1440_light_comfortable
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/design_system_catalogue_test.dart: logo-led catalogue 1440_dark_compact
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/design_system_catalogue_test.dart: logo-led catalogue 1920_dark_comfortable
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/goods_receipt_workspace_test.dart: goods receipt light at 200% preserves posting controls
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/goods_receipt_workspace_test.dart: goods receipt dark at 200% preserves posting controls
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/inventory_transfer_workspace_test.dart: transfer editor light at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/inventory_transfer_workspace_test.dart: transfer editor dark at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/inventory_valuation_workspace_test.dart: valuation light 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/inventory_valuation_workspace_test.dart: valuation dark 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: Wave 2 setup remains reachable at 200% text scale — EC-224
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: dashboard golden 1024_light_compact — AC-1 / AC-7
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: dashboard golden 1024_dark_comfortable — AC-1 / AC-7
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: dashboard golden 1440_light_comfortable — AC-1 / AC-7
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: dashboard golden 1440_dark_compact — AC-1 / AC-7
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: dashboard golden 1920_light_comfortable — AC-1 / AC-7
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: dashboard golden 1920_dark_comfortable — AC-1 / AC-7
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: setup golden 1024_light_compact — AC-216
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: setup golden 1024_dark_comfortable — AC-216
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: setup golden 1440_light_comfortable — AC-216
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: setup golden 1440_dark_compact — AC-216
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: setup golden 1920_light_comfortable — AC-216
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/jentra_app_test.dart: setup golden 1920_dark_comfortable — AC-216
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/landed_value_workspace_test.dart: landed preview light 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/landed_value_workspace_test.dart: landed preview dark 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/payroll_workspace_test.dart: payroll workspace light at 200 percent text scale
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/payroll_workspace_test.dart: payroll workspace dark at 200 percent text scale
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/procurement_workspace_test.dart: AC-321 procurement editor light at 200% text
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/procurement_workspace_test.dart: AC-321 procurement editor dark at 200% text
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/product_unit_workspace_test.dart: product unit light at 200%
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/product_unit_workspace_test.dart: product unit dark at 200%
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/purchase_order_workspace_test.dart: purchase order light at 200% retains actions
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/purchase_order_workspace_test.dart: purchase order dark at 200% retains actions
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/purchase_return_workspace_test.dart: return editor light at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/purchase_return_workspace_test.dart: return editor dark at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/quick_create_test.dart: customer quick create opens the party workspace and its create control
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/quotation_workspace_test.dart: AC-303 renders exact saved offer and readable revision decisions
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/quotation_workspace_test.dart: AC-303 explicit conflict comparison retains reviewed local fields
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/quotation_workspace_test.dart: AC-303 editor visual and accessible state 1440_light
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/quotation_workspace_test.dart: AC-303 editor visual and accessible state 1440_dark
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/quotation_workspace_test.dart: AC-303 line editing preserves exact conversion and discount choice
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receipt_trace_workspace_test.dart: receipt trace light at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receipt_trace_workspace_test.dart: receipt trace dark at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receivables_workspace_test.dart: invoice source detail renders exact totals and guarded actions
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receivables_workspace_test.dart: invoice editor dark theme
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receivables_workspace_test.dart: narrow editor at 200 percent text remains scrollable
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receivables_workspace_test.dart: storage failure keeps the offline editor and offers retry
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receivables_workspace_test.dart: uncertain result displays saved-command retry
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receivables_workspace_test.dart: receipt editor offers governed tender and bank fields
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/receivables_workspace_test.dart: return editor requires original source and disposition
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/reservation_workspace_test.dart: dated reservation queue light 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/reservation_workspace_test.dart: reservation light 200 percent review
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/reservation_workspace_test.dart: dated reservation queue dark 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/reservation_workspace_test.dart: reservation dark 200 percent review
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sales_order_workspace_test.dart: AC-304 rendered order_editor_1440_light
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sales_order_workspace_test.dart: AC-304 rendered order_editor_1440_dark
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sales_order_workspace_test.dart: AC-304 rendered order_editor_1024_text200
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sales_order_workspace_test.dart: AC-304 credit dialog explains exact exposure and reasoned override
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sales_order_workspace_test.dart: AC-304 reservation UI bounds demand and available stock
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sales_order_workspace_test.dart: AC-304 conflict UI requires inspection before keeping local edits
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sales_order_workspace_test.dart: AC-304 accepted quotation opens explicit conversion fields
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sourcing_recovery_test.dart: supplier quote editor light retains controls at 200%
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/sourcing_recovery_test.dart: supplier quote editor dark retains controls at 200%
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_count_workspace_test.dart: serial identity count light at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_count_workspace_test.dart: serial identity count dark at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_count_workspace_test.dart: count editor light at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_count_workspace_test.dart: count editor dark at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_opening_workspace_test.dart: opening register shows exact value and status
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_opening_workspace_test.dart: opening editor renders count lot details and exact preview
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_opening_workspace_test.dart: opening editor supports dark theme
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_opening_workspace_test.dart: 200 percent text remains scrollable without overflow
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_opening_workspace_test.dart: posted opening presents immutable stock and journal references
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/stock_opening_workspace_test.dart: uncertain post shows durable retry and blocks replacement
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_bill_workspace_test.dart: supplier bill light at 200% retains match controls
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_bill_workspace_test.dart: supplier bill dark at 200% retains match controls
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_payment_workspace_test.dart: allocation correction light remains usable at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_payment_workspace_test.dart: dated AP statement light retains exact aging
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_payment_workspace_test.dart: payment proposal light at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_payment_workspace_test.dart: allocation correction dark remains usable at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_payment_workspace_test.dart: dated AP statement dark retains exact aging
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/supplier_payment_workspace_test.dart: payment proposal dark at 200 percent
- C:/Users/sheha/Desktop/Jentra OS/build/w5win9r10/preview/apps/jentra_desktop/test/warehouse_setup_test.dart: warehouse form uses selected branch and preserves scope on save

Approved golden images were not changed. These full-suite results do not replace authenticated acceptance.
