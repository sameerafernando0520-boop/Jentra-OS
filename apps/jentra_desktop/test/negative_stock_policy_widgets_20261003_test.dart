import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/negative_stock/negative_stock_policy_controller.dart';
import 'package:jentra_desktop/src/features/negative_stock/negative_stock_policy_screen.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_dialogs.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as q;
import 'sales_order_controller_test.dart' as f;
import 'negative_stock_policy_controller_20261003_test.dart' show PolicyFake;

void main() {
  setUpAll(_fonts);
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      for (final density in JentraDensity.values) {
        final target =
            '${size.width.toInt()}x${size.height.toInt()}_${dark ? 'dark' : 'light'}_${density.name}_text200';
        testWidgets(
          'negative policy loading error empty and populated $target',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            late JentraLocalDatabase db;
            late PolicyFake gateway;
            late Completer<NegativeStockPolicy> read;
            late Completer<void> entered;
            late NegativeStockPolicyController c;
            JentraLocalDatabase? cleanupDb;
            NegativeStockPolicyController? cleanupController;
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.runAsync(() async {
                cleanupController?.dispose();
                await cleanupDb?.close();
              });
            });
            late Future<void> loading;
            final initialized = await tester.runAsync(() async {
              // SQLite, controller futures and read completers all belong to
              // the real zone. A completer created in the fake zone cannot be
              // awaited here while that zone is deliberately not advancing.
              db = JentraLocalDatabase(NativeDatabase.memory());
              cleanupDb = db;
              gateway = PolicyFake();
              read = Completer<NegativeStockPolicy>();
              entered = Completer<void>();
              gateway.onRead = () {
                entered.complete();
                return read.future;
              };
              c = NegativeStockPolicyController(
                scope: q.scope,
                gateway: gateway,
                drafts: QuotationDraftStore(
                  EncryptedDraftRepository(
                    db,
                    DraftCipher(keyStore: q.MemoryKeys()),
                  ),
                ),
                online: true,
                canViewCost: true,
              );
              cleanupController = c;
              loading = c.initialize();
              await Future.any<void>([
                entered.future,
                loading.then((_) {
                  if (!entered.isCompleted) {
                    throw StateError(
                      'Policy initialization ended before the read: ${c.error}',
                    );
                  }
                }),
              ]).timeout(const Duration(seconds: 5));
              return true;
            });
            expect(initialized, isTrue);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark
                    ? JentraTheme.dark(density: density)
                    : JentraTheme.light(density: density),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true,
                    ),
                    child: RepaintBoundary(
                      key: const Key('negative-policy-render'),
                      child: Scaffold(
                        body: NegativeStockPolicyWorkspace(controller: c),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(find.byType(LinearProgressIndicator), findsOneWidget);
            expect(c.locked, isTrue);
            await _capture(tester, '${target}_loading');
            await tester.runAsync(() async {
              read.completeError(
                const DomainError(
                  code: 'READ_UNAVAILABLE',
                  message: 'Policy read unavailable. Refresh policy to retry.',
                ),
              );
              await loading;
            });
            await tester.pumpAndSettle();
            expect(
              find.text('Policy read unavailable. Refresh policy to retry.'),
              findsOneWidget,
            );
            await _capture(tester, '${target}_error');
            await tester.scrollUntilVisible(
              find.text('Review policy change'),
              400,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              _filledButton(tester, 'Review policy change').onPressed,
              isNull,
            );
            gateway.onRead = null;
            await tester.ensureVisible(find.text('Refresh policy'));
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Refresh policy'),
                  )
                  .onPressed,
              isNotNull,
            );
            await tester.runAsync(c.initialize);
            await tester.runAsync(
              () => c.loadEvidence(NegativeStockEvidenceKind.deficits),
            );
            await tester.pumpAndSettle();
            _top(tester);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Negative-stock policy'), findsOneWidget);
            expect(find.text('Current version 0 · Inactive'), findsOneWidget);
            expect(c.rows, isEmpty);
            expect(c.error, isNull);
            await _capture(tester, '${target}_empty');
            gateway.policy = NegativeStockPolicy(
              tenantId: 'tenant',
              legalEntityId: 'entity',
              version: BigInt.one,
              active: true,
              reason: 'Approved authoritative positive average',
            );
            await tester.runAsync(c.initialize);
            await tester.pumpAndSettle();
            expect(find.text('Current version 1 · Active'), findsOneWidget);
            await _capture(tester, '${target}_active');
            gateway.onEvidence = (kind, after) async =>
                NegativeStockEvidencePage(
                  items: [
                    for (
                      var i = (after?.toInt() ?? 0) + 1;
                      i <= (after?.toInt() ?? 0) + 2;
                      i++
                    )
                      _evidence(kind, i),
                  ],
                  nextCursor: after == null ? BigInt.two : null,
                );
            await tester.runAsync(
              () => c.loadEvidence(NegativeStockEvidenceKind.deficits),
            );
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text('Load next fifty records'),
              400,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.textContaining('Deficit 2'), findsOneWidget);
            expect(find.textContaining('Open quantity 1.000000'), findsWidgets);
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, 'Load next fifty records'),
                  )
                  .onPressed,
              isNotNull,
            );
            await _capture(tester, '${target}_deficits');
            await tester.runAsync(
              () => c.loadEvidence(
                NegativeStockEvidenceKind.deficits,
                more: true,
              ),
            );
            expect(gateway.cursors, contains(BigInt.two));
            await tester.runAsync(
              () => c.loadEvidence(NegativeStockEvidenceKind.covers),
            );
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text('Load next fifty records'),
              400,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expect(find.textContaining('Correction 2'), findsOneWidget);
            expect(find.textContaining('Variance 3.000000'), findsWidgets);
            expect(
              find.textContaining('Correction journal journal-2'),
              findsOneWidget,
            );
            await _capture(tester, '${target}_corrections');
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets(
    'policy reason and review are keyboard reachable at 200 percent with reduced motion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late PolicyFake gateway;
      late NegativeStockPolicyController c;
      JentraLocalDatabase? cleanupDb;
      NegativeStockPolicyController? cleanupController;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          cleanupController?.dispose();
          await cleanupDb?.close();
        });
      });
      final initialized = await tester.runAsync(() async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        cleanupDb = db;
        gateway = PolicyFake();
        c = NegativeStockPolicyController(
          scope: q.scope,
          gateway: gateway,
          drafts: QuotationDraftStore(
            EncryptedDraftRepository(db, DraftCipher(keyStore: q.MemoryKeys())),
          ),
          online: true,
          canViewCost: true,
        );
        cleanupController = c;
        await c.initialize().timeout(const Duration(seconds: 5));
        return true;
      });
      expect(initialized, isTrue);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('negative-policy-dialog-render'),
          child: MaterialApp(
            theme: JentraTheme.light(density: JentraDensity.compact),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(body: NegativeStockPolicyWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reason = find.byType(TextFormField);
      await tester.scrollUntilVisible(
        reason,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.enterText(reason, 'Keyboard approved reason');
        await c.initialize();
      });
      await tester.pumpAndSettle();
      expect(c.form['reason'], 'Keyboard approved reason');
      await tester.ensureVisible(find.text('Review policy change'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.text('Review policy change')))
            .hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('Record negative-stock policy?'), findsOneWidget);
      final data = MediaQuery.of(tester.element(find.byType(AlertDialog)));
      expect(data.disableAnimations, isTrue);
      expect(data.textScaler.scale(1), 2);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Keyboard approved reason'),
        ),
        findsOneWidget,
      );
      await _capture(
        tester,
        'keyboard_1024x720_light_compact_text200_review',
        key: const Key('negative-policy-dialog-render'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(gateway.commands, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final active in [false, true]) {
    testWidgets(
      'reservation shortage opt-in active=$active requires reason and current version',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final policy = PolicyFake()
          ..policy = NegativeStockPolicy(
            tenantId: 'tenant',
            legalEntityId: 'entity',
            version: BigInt.one,
            active: active,
          );
        final selected = <StockReservationDraft>[];
        final container = ProviderContainer(
          overrides: [
            activeTenantContextProvider.overrideWithValue(q.scope),
            businessCapabilitiesProvider.overrideWithValue(
              AsyncData({...f.permissions, 'inventory.stock.override'}),
            ),
            connectivityStateProvider.overrideWithValue(
              const AsyncData(ConnectivityState.online),
            ),
            salesOrderRepositoryProvider.overrideWithValue(f.FakeOrders()),
            negativeStockPolicyRepositoryProvider.overrideWithValue(policy),
          ],
        );
        final caps = container.listen(businessCapabilitiesProvider, (_, _) {}),
            connection = container.listen(connectivityStateProvider, (_, _) {});
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          caps.close();
          connection.close();
          container.dispose();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: JentraTheme.light(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      final draft = await showDialog<StockReservationDraft>(
                        context: context,
                        builder: (_) => OrderReservationDialog(
                          scope: q.scope,
                          detail: f.orderDetail(status: 'confirmed'),
                        ),
                      );
                      if (draft != null) selected.add(draft);
                    },
                    child: const Text('Reserve'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Reserve'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('negative-stock-override')),
          active ? findsOneWidget : findsNothing,
        );
        await tester.enterText(
          find.byKey(const Key('order-reservation-expiry')),
          '2099-10-01T12:00:00Z',
        );
        await tester.enterText(find.byKey(const Key('reserve-line')), '6');
        if (active) {
          await tester.tap(find.byKey(const Key('negative-stock-override')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Reserve quantities'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Enter an override reason'),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const Key('negative-stock-override-reason')),
            'Explicit shortage approval',
          );
          await tester.tap(find.text('Reserve quantities'));
          await tester.pumpAndSettle();
          expect(selected.single.negativeStockOverride!.toJson(), {
            'policy_version': '1',
            'reason': 'Explicit shortage approval',
          });
          expect(
            selected.single.lines.single.requestedBaseQuantity
                .toDecimalString(),
            '6.000000',
          );
        } else {
          await tester.tap(find.text('Reserve quantities'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('exceeds current availability'),
            findsOneWidget,
          );
          expect(selected, isEmpty);
        }
      },
    );
  }
  test(
    'policy navigation requires stock-view and policy-management together',
    () {
      for (final caps in [
        <String>{},
        {'inventory.stock.view'},
        {'inventory.stock.policy.manage'},
      ]) {
        expect(
          visibleJentraDestinations(caps)
              .any((d) => d.path == '/inventory/negative-stock-policy'),
          false,
        );
      }
      expect(
        visibleJentraDestinations({
          'inventory.stock.view',
          'inventory.stock.policy.manage',
        }).any((d) => d.path == '/inventory/negative-stock-policy'),
        true,
      );
    },
  );
}

FilledButton _filledButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
void _top(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .jumpTo(0);
NegativeStockEvidence _evidence(NegativeStockEvidenceKind kind, int id) =>
    NegativeStockEvidence.fromJson(kind, {
      'id': '$id',
      'quantity': '3.000000',
      'provisional_value': '6.000000',
      'posting_date': '2026-10-03',
      'command_id': 'original-command-$id',
      'created_at': '2026-10-03T00:00:00Z',
      'created_by': 'actor',
      if (kind == NegativeStockEvidenceKind.deficits) ...{
        'open_quantity': '1.000000',
        'issue_movement_line_id': 'issue-movement-$id',
        'policy_id': 'policy',
        'policy_version': '1',
        'basis_id': '1',
        'warehouse_id': 'warehouse',
        'product_id': 'product',
      } else ...{
        'deficit_id': '$id',
        'movement_line_id': 'receipt-movement-$id',
        'kind': 'receipt',
        'request_id': 'receipt-request-$id',
        'actual_value': '9.000000',
        'variance': '3.000000',
        'journal_entry_id': 'journal-$id',
      },
    });
Future<void> _capture(
  WidgetTester tester,
  String name, {
  Key key = const Key('negative-policy-render'),
}) async {
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      '../../build/remaining-wave3/negative-policy-final-renders-20261004/$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _fonts() async {
  const root = 'packages/jentra_design_system/assets/fonts';
  await (FontLoader(JentraTypography.sansFamily)
        ..addFont(rootBundle.load('$root/Manrope-Regular.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-Medium.ttf'))
        ..addFont(rootBundle.load('$root/Manrope-SemiBold.ttf')))
      .load();
  await (FontLoader(
    JentraTypography.monoFamily,
  )..addFont(rootBundle.load('$root/IBMPlexMono-Regular.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}
