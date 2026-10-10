# Localized desktop raster diagnosis — 2026-10-10

All **65 localized raster cases** remain strict failures pending a concrete owner visual decision. This report reads preserved images and hashes; it changes no approved PNG, product source, comparator or runtime-bound artifact.

The controlled text-free rounded-border probe uses identical test bytes under cached Flutter 3.44.7 / Dart 3.12.2 and Flutter 3.47.5 / Dart 3.13.4. Its retained completed logs show one test passed on each SDK. Fresh image measurements reproduce 12,743 / 262,144 changed pixels (4.86%), maximum channel delta 54 and no alpha changes. RoundedRectangleBorder and BorderRadius source files are still byte identical; both invoke `canvas.drawDRRect` at line 136. Engine/tester binary hashes and Skia revisions differ. This establishes an SDK/runtime primitive raster difference; it does not identify the exact engine commit or prove every approved image's producing SDK.

Each of the 65 screen candidates is byte identical to its inspected r10 render and earlier retained control. Differences occupy 0.0083–0.2471% of each image, maximum channel delta 61, with unchanged dimensions and alpha. The isolated diffs show rounded card, field, chip and button border segments/corners; no changed labels, values or icons. The 19 originating test files, imports, font-loading/viewport controls, and all exact image paths/hashes are in the machine report.

An ordinary unchanged current-app old-SDK run is infeasible: desktop and lock require Dart 3.13 / Flutter 3.47, while eight package-config entries require Dart language 3.13. Adjusting constraints, package metadata or dependencies would create an explicitly controlled fixture. No such overlay or new Flutter job was made here. The existing primitive proof is sufficient for this diagnosis; supported current-SDK regression remains the verification gate.

Fresh source attribution reports 1 changed r13 inputs: pubspec.lock. All other selected source inputs—including these Dart tests and font assets—retain their r13 hashes. The 231 exact runtime review artifacts still match bundle `92a68a58d70a1f9061776be1b6416b8124112577b0a0859ed6f389becc2533d4`. Preserve the changed owner/current lock and produce fresh candidate tests under that lock; r13 execution is historical.

The reviewed resolution is a strict baseline transition under the supported pinned SDK, following an explicit owner decision for exact candidate hashes. The coordinator prepares the combined 83-case gallery and frozen candidate, runs it with the current lock, verifies candidate renders against the reviewed images, and then requests the visual decision. Only approved case images may subsequently replace baselines. Run strict tests without `--update-goldens` after replacement. Keep native interaction, authenticated acceptance, runtime operations and the 109 requirement owner decisions separate. CI's Ubuntu quality run also needs its own evidence; Windows rendering does not prove Linux strict comparisons.

[Machine report](raster-golden-diagnosis-20261010.json) · [Retained primitive cause](../remaining-wave3/golden-cause-20261003.md) · [All-case inspection](continuation-goldens-native-20261009.md) · [r13 byte comparison](continuation-goldens-comparison-20261009-r13.json)

| Case | Changed pixels | Changed percent | Candidate SHA-256 |
| --- | ---: | ---: | --- |
| catalogue_1024_light_compact | 1822 | 0.2471% | `dfee21791a49004583fad61d1e33eca2c7c0e0bed84eb76b813a41d9151f813b` |
| catalogue_1440_light_comfortable | 1407 | 0.1086% | `df576e722eda11fae4f5b939726142a63e5166b1f20ca2fcae54981aa04a98b0` |
| catalogue_1440_dark_compact | 1457 | 0.1124% | `33a40efaf7374caf0db57e3a57bf6667f7ffa16fef86a64f994e65c951d678a6` |
| catalogue_1920_dark_comfortable | 1982 | 0.0956% | `f10e42d314ccd2782692814443bf0145402f47eab3e00ae666c9147baf26160f` |
| goods_receipt_light_200 | 93 | 0.0083% | `2cba3fa8d78a744acb359a1ed9c89142db21ae2ed2f0d16a913102b3ce1ebf40` |
| goods_receipt_dark_200 | 96 | 0.0085% | `d42857723962d3d6fff6d54d4446b962c8a3118ee36256e86eba389899551c1e` |
| inventory_transfer_light_200 | 770 | 0.0578% | `9b0c866301381c56b038bbebe822f45c0067e22874c3b62a793af063beaf96d8` |
| inventory_transfer_dark_200 | 756 | 0.0568% | `ed3f47915675ec4e2138a2d35de44d53915f3c5ed117bff1482b997f8ea886d0` |
| inventory_valuation_light_200 | 1143 | 0.0744% | `ae00fb457fb8a35cc8417cd8895d315e9fac83fa7b6e64184df9d1250b877664` |
| inventory_valuation_dark_200 | 1313 | 0.0855% | `c974ec428fc6a00db478cafca19a5af85a1a20ad3d133ea158b30ce0c3a5fee9` |
| landed_value_light_200 | 377 | 0.0205% | `c8bddf286b76273e74894a4d3cdd2ff2316bcbad6d30329b378eec62994f5cc1` |
| landed_value_dark_200 | 435 | 0.0236% | `4d06693a00e2b473ed24c521703ec826c1de3b34fca1db03cae5003776b3a754` |
| procurement_editor_light_200 | 340 | 0.0369% | `335a7454412130196897434aa099fd84eef4e7c462b739bfd028ee3b0b67a1e4` |
| procurement_editor_dark_200 | 339 | 0.0368% | `b5194779d37962b14ac926b9ed03758e56eddbf096440e8000a05eb953e154b2` |
| product_unit_light_200 | 502 | 0.0446% | `cef1bd885c3a4f93ef612e8f678b0b648d0ac0800194662c6d80744da42cee4a` |
| product_unit_dark_200 | 475 | 0.0422% | `298c3f1ff52e12d39367b1dc6c35d7925c1aec57991b2accef5766787fdc1fe2` |
| purchase_order_light_200 | 873 | 0.0775% | `b26704b522961b5849e634d348b39aff188d28385ad931d34d5b78bf17e2d0cc` |
| purchase_order_dark_200 | 877 | 0.0779% | `c7cd6e5c02971cc1724b0b3dafd2315de28e32cdfcb525da9ca15ae597b5abd8` |
| purchase_return_light_200 | 370 | 0.0278% | `a5d3a454fe52575269e666c00b26251566b9f8ae8cd3b87c15a0907b2d83debb` |
| purchase_return_dark_200 | 373 | 0.0280% | `78e7abcaab4dfced10fcec58733646b792c48c8c1efcadc1898bb48d9dbe1961` |
| quotation_history_1440_light | 1977 | 0.1373% | `db8151afd7cc21952e44e77bc2f5dd12d0f01cb7747d422232d17cdef9792afa` |
| quotation_conflict_1440_light | 932 | 0.0647% | `c67c8561b00fa4541be6864c083277ff9b20d69fd91e6069243dc78050de4aeb` |
| quotation_editor_1440_light | 1906 | 0.1324% | `6977403bde5c57f6e27ca144817f48f2d1b9764518b2d09446f8c0d3f7a2574f` |
| quotation_editor_1440_dark | 1918 | 0.1332% | `b11f5a604ee6d3a367297cd064c7bb8737373d12979e15e699ccd77a2efab5e9` |
| quotation_line_1440_light | 847 | 0.0588% | `f780a11a2724e643354238f04a6d216b58a0b3a5d3f5784090203151fb7d44da` |
| receipt_trace_light_200 | 446 | 0.0335% | `a22657f2d0551fb489c6a0866dd87de1bfbc60004cda0eedee1589d8cdfa1751` |
| receipt_trace_dark_200 | 424 | 0.0319% | `d4885d4839ab126662097a925f571eac943231a41945df83fa1511f59a51c636` |
| receivables_invoice_1440_light | 1754 | 0.1218% | `efbfe09ba4eeb78545e91e878643c77cfdd1b480f3479a59e85bacd520231304` |
| receivables_editor_1440_dark | 1819 | 0.1263% | `80c73c1d9aa870d15d2c529c0ea70a47d35c7bde07782d9ed586ebb6c7850fa8` |
| receivables_editor_1024_text200 | 1427 | 0.1394% | `8dbf884baad2f66fc6e353c29e3db930b5209b996b5a6f44df10f5759fa71756` |
| receivables_storage_failure_1440_light | 1954 | 0.1357% | `7bb768fb9df749b75a08d5b5c257a5ce8f5502429134e793a1d9f80d7ff9755b` |
| receivables_recovery_1440_light | 1185 | 0.0823% | `eda146b053c63a3446547ce13bdfbb21b7e0ecd3a1fab470b75a8f763b19896a` |
| receivables_receipt_1440_light | 1311 | 0.0910% | `5778b467a2f9e805c2cb46b23f92082105734eb2b63a77397e03c1dcd38e6cb2` |
| receivables_credit_1440_light | 1713 | 0.1190% | `86b2218b5f882ebff691abc1e0e395ef812a44016258fb091b374455483d93db` |
| reservation_report_light_200 | 867 | 0.0529% | `8760451d7dc9e61074e4a615c083dc8bf203cec0f5da28d1171c84f4be86fa26` |
| reservation_light_200 | 598 | 0.0365% | `781fed0686823c99422efd8302c28df121dfe1378bcfebcec0d73d9b2cb36613` |
| reservation_report_dark_200 | 1151 | 0.0703% | `dac0e1cf5e842e42e47f70faec80be7d4c8c68aefb22eb6d3232e4a927cf431c` |
| reservation_dark_200 | 603 | 0.0368% | `9d6243d610d0de29f2be311b4447074376ec9e366795f0e4f5239e9d3cbda2d9` |
| order_editor_1440_light | 1756 | 0.1219% | `586cffdaf24ecae2b5de3ab2ab37c907ad1ccd4ebfe3fa3646e7794596ad8c8a` |
| order_editor_1440_dark | 1763 | 0.1224% | `b99403f8f38138482fe99021f4c9b03fb143d1b6761a61bde87e609577f2eb17` |
| order_editor_1024_text200 | 1025 | 0.1001% | `555b9ce0286d0f586a412143e276844e229a22e6fa2865147a19c79959cac9ea` |
| order_credit_1440_light | 698 | 0.0485% | `051b9c0eb734204cde0e8153c1d6ef33f7112295c714040b378875a5a57b9b9f` |
| order_reservation_1440_light | 557 | 0.0387% | `54b840d94262a71accd892815d8014b6465e7c63afbe9df3a30c2d5f79e92e43` |
| order_conflict_1440_light | 1336 | 0.0928% | `5cc1724df58a54d9da1d16aef4f4868cd2f8a988f07bd89dd3872d16aa3f6817` |
| order_conversion_1440_light | 666 | 0.0462% | `efda4bddcceed010db947e4d0f2682120173fddf61fa208411ca414ba072b8af` |
| supplier_quote_light_200 | 766 | 0.0680% | `ca34a55e681bc9a86533463d5364ef16f6dc9a6b7147c6bce3c33fd2971ae11c` |
| supplier_quote_dark_200 | 766 | 0.0680% | `15866629d627d870b840d4905e339089fea4109957132dc855aa8ebef32a481c` |
| stock_count_serial_light_200 | 757 | 0.0435% | `5ef6a6799864f44069b41b765673fd6adf52abc448bfe49db298e287118b98ae` |
| stock_count_serial_dark_200 | 817 | 0.0469% | `27404feee65c2f1051ac7fe18df87c6c63c8c6513b0ab614a2b46db39f459d8e` |
| stock_count_light_200 | 757 | 0.0493% | `f062bcd1585a768bf78d74d905f32a1c4d030af5f5ad29f7a61c5def0b977549` |
| stock_count_dark_200 | 817 | 0.0532% | `05bb093469f4cc130cdb4d814b5bf2979515b6d9a1e0b8b607d495e2bea3c7da` |
| stock_opening_register_light | 1743 | 0.1100% | `53301051ec259b6d48be83f0e221b05fe263daeb622ba03072040757d52288e7` |
| stock_opening_editor_light | 2068 | 0.1306% | `93a7564a4cfd55b4410bead3e5e799aa7a5a7e6e26d339826834c6b483f90513` |
| stock_opening_editor_dark | 2116 | 0.1336% | `fb41acff758b8a781fe061bd384576b0f4d31aba1e74b4fb38d96621c34732cd` |
| stock_opening_editor_text200 | 1103 | 0.1077% | `00a459271c4c93367caceeae748ff476c4f7c01450678fdb67639d5b82d6ea59` |
| stock_opening_posted | 1462 | 0.0923% | `4d0f483380f47f064d10cc1f3542a37f330abb4a8cc47f82a4801637179e72c9` |
| stock_opening_recovery | 1923 | 0.1214% | `768451f19959585196fe68b63dc44c53f19c1ab9d6a780254bb1750af58d5896` |
| supplier_bill_light_200 | 884 | 0.0785% | `5065b23fd22fb2a7d34d8d38ce1ac46bf7e29ba80554c8e3b646d9a4f8dd07a5` |
| supplier_bill_dark_200 | 829 | 0.0736% | `db74e8045691756c1586be779976eb0aa0933aef1fa67a6d100cba789a97855a` |
| supplier_allocation_light_200 | 324 | 0.0243% | `bb0cfe0fa9df42f93e1273d01c05d3fbeecad26d6810853f181fdd496527468e` |
| supplier_statement_light_200 | 627 | 0.0471% | `40ce489b6511f401217768f2c1554a65dd00aed9f45e415e66b068954b7d6653` |
| supplier_payment_light_200 | 964 | 0.0856% | `1c5d61ce376cb7b76dba46cc75550db1ac8022e5638dde90e794e0fd61d7750d` |
| supplier_allocation_dark_200 | 323 | 0.0243% | `95697a6738b0af04afbf0c698ee9277ffaf29314c54fdbe92856398de5ee3e8c` |
| supplier_statement_dark_200 | 655 | 0.0492% | `0bd05270084352cf9d8ed054c7d2cde6935f9c90d64089e7e6b1443d78d48e9b` |
| supplier_payment_dark_200 | 974 | 0.0865% | `91f78c49e9d5e6b37d804205a0a7f6958f5a22bc53c79d1bbf23b4220464d04c` |
