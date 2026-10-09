# Desktop goldens, cash spacing and native keyboard continuation — October 9

All 83 r10 desktop golden failures have been investigated. This continuation freshly reads and fingerprints the retained approved/current/master/diff files; it is not a new full-suite run. The strict golden gate remains open. Approved PNGs, the comparator and navigation fixtures were preserved. Native keyboard and owner visual acceptance remain unverified.

## Evidence and limits

The [machine record](continuation-goldens-native-20261009.json) contains every case, all retained image paths/hashes, dimensions, changed-pixel counts, bounds, maximum channel deltas, changed 128px tiles, earlier-control identity and inspection/classification notes. Every isolated difference image was visually inspected, including all 13 shared dashboard/setup cases. Pixel comparisons use the complete approved and current image arrays. Detailed master/current inspection of representative semantic changes complements the difference images. It does not claim every master/current pair was read at full native resolution.

Fresh measurements: **83 unchanged dimensions; zero approved-image hash drift; zero retained current/master/diff hash drift; every failure master matches its approved file.** The 65 earlier-control matches remain byte-identical. The r10 full-desktop result remains historical evidence of **1,909 passing tests / 83 failed golden comparisons**; this document does not convert those failures into passes.

The new root-agent serialized r13 full desktop run records **1,921 pass / 83 fail / zero skipped**. An [independent read-only r13 comparison](continuation-goldens-comparison-20261009-r13.json) verifies all **249** current/master/difference PNGs are byte-identical to their already inspected r10 counterparts. All 83 approved hashes remain unchanged and every r13 master matches its approved PNG. The same 65/16/2 classifications therefore apply to the exact new failure images. The extra 12 passing tests include the new cash epoch regression fixture. The strict visual gate remains red; stable bytes and an investigation do not grant visual approval.

| Classification | Cases | Finding | Remaining visual decision |
|---|---:|---|---|
| R: localized border raster | 65 | Sparse rounded field/card/chip/button border and corner pixels; no differing labels/values/icons visible in isolated differences. Each current PNG exactly matches a preserved earlier control. Changed fractions range 0.0083–0.2471%; maximum channel delta at most 61. | Resolve rendering-toolchain baseline policy and review exact images. The preserved SDK border primitive evidence supports this pattern but is not a same-source, two-SDK proof for all 65 complete screens. |
| S: capability navigation plus body border raster | 16 | Approved People/Projects/Service/Analytics rows are absent under current capabilities; Intelligence/Jentra Control moves up. The compact sidebar contributes exactly 5,288 differing pixels in all five compact cases; the expanded sidebar contributes exactly 19,711 in all eleven expanded cases. Sparse body border changes contribute 1,968–4,126 pixels. | Confirm intended capability fixtures and current navigation policy, then review resulting images. Do not restore unauthorized destinations or broaden fixtures just to reproduce a baseline. |
| P: payroll content | 2 | The new `Linked corrections` action moves Reload. Both light/dark cases change 4,025 pixels, confined to `[537,31,905,77)`; the toolbar content matches current Wave 4 source. | Separately owned Wave 4 product/visual review. This is a content change and cannot be accepted as SDK raster drift. |

The 16 S cases comprise the 13 shared dashboard/setup cases plus CRM, quick-create and warehouse setup. They are fresh r10 original-fixture renders. They are not the October 8 capability-experiment images. The earlier experiment exposed an additional Private HR row and still failed all 13; it is not a validated fixture repair.

## Capability fixture and product reconciliation

Current [navigation](../../../apps/jentra_desktop/lib/src/shell/navigation.dart) requires `people.view` plus `people.employees.view` for People, `projects.view` for Projects, `service.view` for Service, and `analytics.view` plus a CRM opportunity view/manage capability for Analytics. `people.view` also reveals Private HR. The Intelligence section is carried to the next permitted destination, so Jentra Control moves when Analytics is absent.

The ordinary `jentra_app_test.dart` golden fixture uses the [preview capability provider](../../../apps/jentra_desktop/lib/src/app_providers.dart), which grants quotation view and business-setup view/manage permissions. It does not grant these four destinations. CRM uses CRM/quotation capabilities; warehouse uses setup capabilities; quick-create uses party/quotation/invoice capabilities. None supplies the missing People/Projects/Service/Analytics combination. Current omissions agree with the implemented capability policy. The approved images encode older visible navigation. Reconciliation must explicitly decide what each fixture is meant to represent, including the Private HR consequence, before approving a new image set. No capability/provider/navigation source was changed in this investigation.

The payroll action is implemented in [PayrollScreen](../../../apps/jentra_desktop/lib/src/features/people/payroll_screen.dart), gated by `people.payroll.view` and opening `PayrollCorrectionScreen`. Its presence is expected under the current payroll fixture. It was not removed or hidden to satisfy an older image.

## Cash floating labels at 200% text

The retained r10 cash date/approval frames show consecutive outlined fields sharing a border line with the next floating label. The Obligation family label also crowds the preceding multiline instructions. This is a product layout defect separate from the 83 approved-golden comparisons.

Layout-only changes add 16 logical pixels between cash scenario horizon/override fields and between date-source/date/reason/proposal fields, with space after instructions and around the corresponding actions. Changes are confined to widget children in [cash_scenario_screen.dart](../../../apps/jentra_desktop/lib/src/features/analytics/cash_scenario_screen.dart) and [cash_payment_dates_section.dart](../../../apps/jentra_desktop/lib/src/features/analytics/cash_payment_dates_section.dart). Concurrent controller/privacy fixes remain separately owned.

The existing [200% capture tests](../../../apps/jentra_desktop/test/wave5_continuation_test.dart) now assert at least 16 logical pixels between horizon fields and between issued obligation, authoritative date and date-authority reason. The 12 variants cover 1024/1440/1920 widths, light/dark and comfortable/compact density. The root agent's serialized r13 run passes **96 cash/workspace tests** and **12 cash capture cases**, producing 60 images. The [explicit inspection record](windows-test-cash-inspections-20261009-r13.json) binds 18 actually inspected images: every date variant and six horizon variants. Those visible fields now have distinct borders and clear space above floating labels. Where visible, the Obligation family label is separated from the instructions. At the narrow comfortable date scroll position, the bottom approval row is partially below the viewport; the fixture separately scrolls to the approval controls. This is controlled widget geometry/render evidence for the spacing correction, not owner visual acceptance or authenticated native behavior. Dart formatting of the three edited files passes. Final source-attributed analysis/build/package reporting remains the root agent's separate serialized work.

## Native keyboard and authenticated acceptance

The retained [r10 keyboard result](windows-test-preview-keyboard-focus-failure-20261009-r10.json) records `OWN_PREVIEW_FOCUS_REQUIRED_NO_KEYS_SENT`, zero keys sent and `verified=false`. The earlier inspected attempt did not show the command palette. The [guarded probe](../../../scripts/wave5/probe_windows_keyboard.ps1) requires an exact isolated binary/process identity and verified own-window foreground before sending keys. Widget keyboard tests do not establish Windows keyboard routing.

No native key sequence was attempted by this continuation. No credentials, Windows profile, acceptance store or sessions were accessed. The reviewed `jentra-w5-runtime` profile remains an approval/private-provisioning dependency under the [runtime protocol](integrated-runtime-protocol-20261006.md). Genuine login/MFA, authenticated command palette/navigation, actor switch, revocation, native process restart/recovery and owner acceptance remain separate open gates. Preview startup and controlled 200% widget renders cannot satisfy them.

## Per-case classification

R/S/P refer to the evidence-bounded categories above. All rows retain a strict failed comparison; none is accepted. Exact per-case hashes, percentages, bounds and earlier-control references are in the machine record.

| # | Golden stem | Class | Differing pixels | Max channel delta |
|---:|---|:---:|---:|---:|
| 1 | crm_1440_light_comfortable | S | 22426 | 166 |
| 2 | catalogue_1024_light_compact | R | 1822 | 61 |
| 3 | catalogue_1440_light_comfortable | R | 1407 | 61 |
| 4 | catalogue_1440_dark_compact | R | 1457 | 57 |
| 5 | catalogue_1920_dark_comfortable | R | 1982 | 57 |
| 6 | goods_receipt_light_200 | R | 93 | 14 |
| 7 | goods_receipt_dark_200 | R | 96 | 15 |
| 8 | inventory_transfer_light_200 | R | 770 | 52 |
| 9 | inventory_transfer_dark_200 | R | 756 | 54 |
| 10 | inventory_valuation_light_200 | R | 1143 | 51 |
| 11 | inventory_valuation_dark_200 | R | 1313 | 53 |
| 12 | setup_1024_light_compact_text_200 | S | 7256 | 166 |
| 13 | dashboard_1024_light_compact | S | 7568 | 166 |
| 14 | dashboard_1024_dark_comfortable | S | 7675 | 166 |
| 15 | dashboard_1440_light_comfortable | S | 22706 | 166 |
| 16 | dashboard_1440_dark_compact | S | 22866 | 166 |
| 17 | dashboard_1920_light_comfortable | S | 23616 | 166 |
| 18 | dashboard_1920_dark_comfortable | S | 23837 | 166 |
| 19 | setup_1024_light_compact | S | 7522 | 166 |
| 20 | setup_1024_dark_comfortable | S | 7584 | 166 |
| 21 | setup_1440_light_comfortable | S | 22659 | 166 |
| 22 | setup_1440_dark_compact | S | 22780 | 166 |
| 23 | setup_1920_light_comfortable | S | 22672 | 166 |
| 24 | setup_1920_dark_comfortable | S | 22784 | 166 |
| 25 | landed_value_light_200 | R | 377 | 50 |
| 26 | landed_value_dark_200 | R | 435 | 52 |
| 27 | payroll_light_200 | P | 4025 | 228 |
| 28 | payroll_dark_200 | P | 4025 | 240 |
| 29 | procurement_editor_light_200 | R | 340 | 57 |
| 30 | procurement_editor_dark_200 | R | 339 | 53 |
| 31 | product_unit_light_200 | R | 502 | 52 |
| 32 | product_unit_dark_200 | R | 475 | 55 |
| 33 | purchase_order_light_200 | R | 873 | 55 |
| 34 | purchase_order_dark_200 | R | 877 | 54 |
| 35 | purchase_return_light_200 | R | 370 | 51 |
| 36 | purchase_return_dark_200 | R | 373 | 53 |
| 37 | quick_create_workspace_links | S | 22158 | 76 |
| 38 | quotation_history_1440_light | R | 1977 | 57 |
| 39 | quotation_conflict_1440_light | R | 932 | 37 |
| 40 | quotation_editor_1440_light | R | 1906 | 57 |
| 41 | quotation_editor_1440_dark | R | 1918 | 44 |
| 42 | quotation_line_1440_light | R | 847 | 55 |
| 43 | receipt_trace_light_200 | R | 446 | 52 |
| 44 | receipt_trace_dark_200 | R | 424 | 53 |
| 45 | receivables_invoice_1440_light | R | 1754 | 55 |
| 46 | receivables_editor_1440_dark | R | 1819 | 44 |
| 47 | receivables_editor_1024_text200 | R | 1427 | 58 |
| 48 | receivables_storage_failure_1440_light | R | 1954 | 58 |
| 49 | receivables_recovery_1440_light | R | 1185 | 18 |
| 50 | receivables_receipt_1440_light | R | 1311 | 57 |
| 51 | receivables_credit_1440_light | R | 1713 | 57 |
| 52 | reservation_report_light_200 | R | 867 | 51 |
| 53 | reservation_light_200 | R | 598 | 50 |
| 54 | reservation_report_dark_200 | R | 1151 | 53 |
| 55 | reservation_dark_200 | R | 603 | 52 |
| 56 | order_editor_1440_light | R | 1756 | 58 |
| 57 | order_editor_1440_dark | R | 1763 | 45 |
| 58 | order_editor_1024_text200 | R | 1025 | 54 |
| 59 | order_credit_1440_light | R | 698 | 18 |
| 60 | order_reservation_1440_light | R | 557 | 18 |
| 61 | order_conflict_1440_light | R | 1336 | 39 |
| 62 | order_conversion_1440_light | R | 666 | 39 |
| 63 | supplier_quote_light_200 | R | 766 | 55 |
| 64 | supplier_quote_dark_200 | R | 766 | 54 |
| 65 | stock_count_serial_light_200 | R | 757 | 51 |
| 66 | stock_count_serial_dark_200 | R | 817 | 53 |
| 67 | stock_count_light_200 | R | 757 | 51 |
| 68 | stock_count_dark_200 | R | 817 | 53 |
| 69 | stock_opening_register_light | R | 1743 | 48 |
| 70 | stock_opening_editor_light | R | 2068 | 57 |
| 71 | stock_opening_editor_dark | R | 2116 | 43 |
| 72 | stock_opening_editor_text200 | R | 1103 | 57 |
| 73 | stock_opening_posted | R | 1462 | 14 |
| 74 | stock_opening_recovery | R | 1923 | 14 |
| 75 | supplier_bill_light_200 | R | 884 | 55 |
| 76 | supplier_bill_dark_200 | R | 829 | 51 |
| 77 | supplier_allocation_light_200 | R | 324 | 50 |
| 78 | supplier_statement_light_200 | R | 627 | 52 |
| 79 | supplier_payment_light_200 | R | 964 | 52 |
| 80 | supplier_allocation_dark_200 | R | 323 | 51 |
| 81 | supplier_statement_dark_200 | R | 655 | 53 |
| 82 | supplier_payment_dark_200 | R | 974 | 54 |
| 83 | warehouse_setup_form | S | 22184 | 76 |

## Reproduction and reviewed inputs

The fresh read-only measurement command is `python scripts/wave5/analyze_r10_goldens.py` using the bundled Python runtime with NumPy/Pillow. It exits 0 and preserves approved/retained image files. The current source formatter command is `dart --suppress-analytics format --output=none --set-exit-if-changed` with the two cash UI files and `wave5_continuation_test.dart`; it exits 0. Flutter jobs are coordinated and serialized by the root agent; none was started by this investigation.

Reviewed inputs: next-session handoff; r10 Windows verification and JSON; full r10 golden investigation and JSON; October 8 shared golden investigation; October 2 approved golden investigation and October 3 SDK/golden cause reports; cash payment-date contract; Wave 5 NFR-508/509 specification; runtime protocol; current remaining-work/status native/cash/acceptance claims; r10 keyboard failure/probe; current navigation, capability fixtures and payroll toolbar source. The current runtime review remains unapproved. This continuation provides no installed-SQL, actual delivery, genuine MFA, independent-session contention/load or owner acceptance claim.
