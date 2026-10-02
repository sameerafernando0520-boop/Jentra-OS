import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_screen.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_controller.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_screen.dart';
import 'package:jentra_desktop/src/features/operations/notification_admin_controller.dart';
import 'package:jentra_desktop/src/features/operations/notification_admin_screen.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_screen.dart';

import '../../../packages/jentra_domain/test/support/landed_extension_fixture.dart';
import 'support/procurement_fakes.dart' show Keys;
import 'disposition_workspace_test.dart' show Dispositions;
import 'landed_extension_workspace_test.dart' show Landed;
import 'notification_admin_workspace_test.dart' show Notifications;
import 'count_partition_workspace_test.dart' show Partitions;
import 'stock_count_workspace_test.dart' show Counts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  const scope = TenantContext(
    tenantId: '10000000-0000-0000-0000-000000000001',
    legalEntityId: '10000000-0000-0000-0000-000000000002',
    branchId: '10000000-0000-0000-0000-000000000003',
    actorId: '10000000-0000-0000-0000-000000000004',
  );
  const caps = {
    'inventory.stock.view',
    'inventory.cost.view',
    'inventory.valuation.post',
    'inventory.dispositions.post',
    'inventory.adjustments.post',
    'finance.view',
    'core.roles.manage',
    'finance.payments.manage',
  };
  for (final (width, height) in [
    (1024.0, 720.0),
    (1440.0, 900.0),
    (1920.0, 1080.0),
    (3840.0, 2160.0),
  ]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        for (final module in [
          'landed',
          'disposition',
          'partitions',
          'notifications',
        ]) {
          final mode =
              '${dark ? 'dark' : 'light'}_${compact ? 'compact' : 'comfortable'}';
          testWidgets('$module ${width.toInt()} $mode 200%', (tester) async {
            final db = JentraLocalDatabase(NativeDatabase.memory());
            final repository = EncryptedDraftRepository(
              db,
              DraftCipher(keyStore: Keys()),
            );
            final drafts = QuotationDraftStore(repository);
            late Widget workspace;
            late VoidCallback dispose;
            if (module == 'landed') {
              final c = LandedExtensionController(
                scope: scope,
                gateway: Landed(),
                drafts: LandedExtensionDraftStore(repository),
                online: true,
              );
              c.posted = {
                ...landedEvidence(),
                'id': landedId,
                'status': 'posted',
                'reference': 'FREIGHT-01',
                'reason': 'Recorded freight allocation',
                'journal_ids': [landedAccount],
              };
              c.preview = c.posted;
              workspace = LandedExtensionWorkspace(
                controller: c,
                capabilities: caps,
              );
              dispose = c.dispose;
            } else if (module == 'disposition') {
              final gateway = Dispositions();
              final c = DispositionController(
                scope: scope,
                gateway: gateway,
                drafts: drafts,
                online: true,
                permissions: caps,
              );
              c.form = {
                ...await gateway.detail(
                  scope,
                  '10000000-0000-0000-0000-000000000005',
                ),
                'document_number': 'DISP-000012',
                'journal_entry_id': '10000000-0000-0000-0000-000000000006',
                'warehouse_name': 'Colombo stock warehouse',
                'offset_account_name': 'Inventory variance',
                'currency_code': 'LKR',
                'grand_total': '30.037037',
              };
              workspace = DispositionWorkspace(
                controller: c,
                capabilities: caps,
              );
              dispose = c.dispose;
            } else if (module == 'partitions') {
              final c = StockCountController(
                scope: scope,
                gateway: Counts(),
                partitionGateway: Partitions(),
                drafts: drafts,
                online: true,
                permissions: caps,
              );
              c.partitionProgress = Partitions().progress(
                '10000000-0000-0000-0000-000000000007',
              );
              workspace = StockCountWorkspace(controller: c);
              dispose = c.dispose;
            } else {
              final c = NotificationAdminController(
                scope: scope,
                gateway: Notifications(),
                drafts: drafts,
                online: true,
                permissions: caps,
              );
              c.pages['members'] = [
                {
                  'id': '10000000-0000-0000-0000-000000000008',
                  'status': 'active',
                },
              ];
              c.pages['subscriptions'] = [
                {
                  'id': '10000000-0000-0000-0000-000000000009',
                  'event_class': 'reconciliation',
                  'enabled': true,
                  'recipient_id': '10000000-0000-0000-0000-000000000008',
                  'recipient_status': 'active',
                  'version': 3,
                },
              ];
              c.scanResult = {
                'kind': 'AP',
                'as_of': '2026-09-29',
                'examined': 100,
                'emitted': 2,
                'has_more': true,
                'next_after': '10000000-0000-0000-0000-000000000010',
              };
              workspace = NotificationAdminWorkspace(controller: c);
              dispose = c.dispose;
            }
            addTearDown(() async {
              dispose();
              await db.close();
            });
            tester.view.physicalSize = Size(width, height);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final theme = dark ? JentraTheme.dark() : JentraTheme.light();
            await tester.pumpWidget(
              MaterialApp(
                theme: theme.copyWith(
                  visualDensity: compact
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const Key('current-workspace'),
                  child: Scaffold(body: workspace),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (module == 'notifications') {
              // Keep the reviewed dated scan and its continuation controls stable
              // when the real UTC day advances. Preserve the approved images.
              final cutoff = find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'As of (YYYY-MM-DD)',
              );
              await tester.scrollUntilVisible(
                cutoff,
                400,
                scrollable: find.byType(Scrollable).first,
              );
              final field = tester.widget<TextField>(cutoff);
              field.controller!.text = '2026-09-29';
              field.onChanged?.call('2026-09-29');
              tester
                  .state<ScrollableState>(find.byType(Scrollable).first)
                  .position
                  .jumpTo(0);
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            final key = find.byKey(const Key('current-workspace'));
            await expectLater(
              key,
              matchesGoldenFile(
                'goldens/current_${module}_${width.toInt()}_${mode}_200.png',
              ),
            );
            final scroll = find.byType(Scrollable).first;
            final state = tester.state<ScrollableState>(scroll);
            state.position.jumpTo(state.position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (state.position.maxScrollExtent > 0) {
              await expectLater(
                key,
                matchesGoldenFile(
                  'goldens/current_${module}_${width.toInt()}_${mode}_200_lower.png',
                ),
              );
            }
          });
        }
      }
    }
  }
}
