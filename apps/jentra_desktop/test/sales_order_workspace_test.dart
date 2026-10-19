import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_controller.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_screen.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_dialogs.dart';
import 'package:jentra_desktop/src/features/sales/quotation_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as q;
import 'sales_order_controller_test.dart' as f;

class Harness {
  Harness(this.repository, this.store, this.container);
  final f.FakeOrders repository;
  final QuotationDraftStore store;
  final ProviderContainer container;
  SalesOrderState get state => container.read(salesOrderProvider).requireValue;
  SalesOrderController get controller =>
      container.read(salesOrderProvider.notifier);
}

Future<Harness> pump(
  WidgetTester tester, {
  String status = 'draft',
  bool converted = false,
  bool dark = false,
  double scale = 1,
  Size size = const Size(1440, 1000),
  Set<String> caps = f.permissions,
  Future<Set<String>> Function()? capabilitySource,
  bool select = true,
  bool offline = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final database = JentraLocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final store = QuotationDraftStore.orders(
    EncryptedDraftRepository(database, DraftCipher(keyStore: q.MemoryKeys())),
  );
  final repository = f.FakeOrders();
  final snapshot = f.orderSnapshot(status: status, converted: converted)
    ..addAll({
      'subtotal': '100000.000000',
      'grand_total': '118000.000000',
      'base_total': '118000.000000',
      'tax_total': '18000.000000',
      'customer_id': 'customer',
      'notes': 'Supply and install at the customer site.',
    });
  (snapshot['lines']! as List).first['description'] =
      'Managed workplace installation';
  repository.detail = SalesOrderDetail.fromJson(snapshot);
  repository.credit = SalesOrderCreditPreview.fromJson({
    'sales_order_id': q.quoteId,
    'order_version': 7,
    'currency_code': 'LKR',
    'credit_currency_code': 'LKR',
    'credit_limit': '500000.000000',
    'due_exposure': '450000.000000',
    'overdue_exposure': '20000.000000',
    'existing_order_exposure': '0.000000',
    'current_order_exposure': '118000.000000',
    'total_exposure': '568000.000000',
    'projection_available': true,
    'credit_as_of_at': '2026-09-07T00:00:00Z',
    'checked_at': '2026-09-07T01:00:00Z',
    'reason': 'CREDIT_LIMIT_EXCEEDED',
  });
  await tester.pumpWidget(
    ProviderScope(
      retry: (count, error) => null,
      overrides: [
        activeTenantContextProvider.overrideWithValue(q.scope),
        businessCapabilitiesProvider.overrideWith(
          (ref) async =>
              capabilitySource == null ? caps : await capabilitySource(),
        ),
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(
            offline ? ConnectivityState.offline : ConnectivityState.online,
          ),
        ),
        salesOrderRepositoryProvider.overrideWithValue(repository),
        salesOrderDraftStoreProvider.overrideWithValue(store),
        quotationReferenceRepositoryProvider.overrideWithValue(References()),
        quotationWorkspaceRepositoryProvider.overrideWithValue(
          q.FakeQuotations()..detail = q.detail(status: 'accepted'),
        ),
      ],
      child: RepaintBoundary(
        key: const Key('order-golden'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: const Scaffold(body: SalesOrderScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SalesOrderScreen)),
  );
  await tester.runAsync(() async {
    await container.read(salesOrderProvider.future);
    if (select) {
      await container.read(salesOrderProvider.notifier).selectOrder(q.quoteId);
    }
  });
  await tester.pumpAndSettle();
  return Harness(repository, store, container);
}

Future<void> flush(WidgetTester tester, Harness h) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final s = h.state;
      if (!s.busy && !s.loading && !s.savingLocal) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return;
      }
    }
  });
  await tester.pumpAndSettle();
}

class References implements QuotationReferenceRepository {
  @override
  Future<CursorPage<QuotationReference>> pageReferences({
    required TenantContext context,
    required QuotationReferenceKind kind,
    required QuotationReferenceQuery query,
  }) async => CursorPage(
    items: [
      QuotationReference(
        id: query.id ?? 'warehouse',
        label: kind == QuotationReferenceKind.warehouse
            ? 'WH-HQ · Main warehouse'
            : 'CUST-001 · Acme Distribution',
        values: {},
      ),
    ],
    limit: query.limit,
  );
}

void main() {
  setUpAll(() async {
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
  });
  testWidgets('AC-304 order-only role reaches sales workspace', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessCapabilitiesProvider.overrideWith(
            (ref) async => {'sales.orders.view'},
          ),
          activeTenantContextProvider.overrideWithValue(q.scope),
          salesOrderRepositoryProvider.overrideWithValue(f.FakeOrders()),
        ],
        child: MaterialApp(
          theme: JentraTheme.light(),
          home: const Scaffold(body: QuotationScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sales orders'), findsOneWidget);
    expect(find.text('New quotation'), findsNothing);
  });
  testWidgets('AC-304 direct route denies unauthorized role', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessCapabilitiesProvider.overrideWith((ref) async => {}),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesOrderScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Your current role cannot open sales orders.'),
      findsOneWidget,
    );
  });
  for (final (name, dark, scale, size) in [
    ('order_editor_1440_light', false, 1.0, const Size(1440, 1000)),
    ('order_editor_1440_dark', true, 1.0, const Size(1440, 1000)),
    ('order_editor_1024_text200', false, 2.0, const Size(1024, 1000)),
  ]) {
    testWidgets('AC-304 rendered $name', (tester) async {
      await pump(tester, dark: dark, scale: scale, size: size);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('order-golden')),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
  testWidgets(
    'AC-304 delivery edits persist and converted source remains fixed',
    (tester) async {
      final h = await pump(tester, converted: true);
      expect(find.text('Save delivery details'), findsOneWidget);
      expect(find.byKey(const Key('quote-add-line')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('order-promised-date')),
        '2099-11-01',
      );
      await flush(tester, h);
      expect(h.state.form!['promised_date'], '2099-11-01');
      await tester.tap(find.text('Save delivery details'));
      await flush(tester, h);
      expect(h.repository.commands.single.verb, 'fulfillment');
      expect(
        (h.repository.commands.single.wire['payload'] as Map)['promised_date'],
        '2099-11-01',
      );
    },
  );
  testWidgets(
    'AC-304 credit dialog explains exact exposure and reasoned override',
    (tester) async {
      final h = await pump(tester);
      await tester.tap(find.text('Review credit & confirm'));
      await flush(tester, h);
      expect(find.byType(OrderCreditDialog), findsOneWidget);
      expect(
        find.text('Total exposure after confirmation\nLKR 568000.000000'),
        findsOneWidget,
      );
      await expectLater(
        find.byKey(const Key('order-golden')),
        matchesGoldenFile('goldens/order_credit_1440_light.png'),
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Override & confirm'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('order-override-reason')),
        'Finance approved this exception',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Override & confirm'));
      await flush(tester, h);
      expect(
        (h.repository.commands.single.wire['payload']
            as Map)['override_credit'],
        true,
      );
    },
  );
  testWidgets('AC-304 reservation UI bounds demand and available stock', (
    tester,
  ) async {
    final h = await pump(tester, status: 'confirmed');
    await tester.tap(find.text('Reserve stock'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderReservationDialog), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('order-reservation-expiry')),
      '2099-10-01T12:00:00Z',
    );
    await tester.enterText(find.byKey(const Key('reserve-line')), '6');
    await tester.tap(find.text('Reserve quantities'));
    await tester.pumpAndSettle();
    expect(find.textContaining('exceeds current availability'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('reserve-line')))
          .controller!
          .text,
      '6',
    );
    expect(h.repository.commands, isEmpty);
    await expectLater(
      find.byKey(const Key('order-golden')),
      matchesGoldenFile('goldens/order_reservation_1440_light.png'),
    );
    await tester.enterText(find.byKey(const Key('reserve-line')), '5');
    await tester.tap(find.text('Reserve quantities'));
    await flush(tester, h);
    expect(h.repository.commands.single.verb, 'reserve');
  });
  testWidgets('AC-304 unknown command offers identical explicit retry', (
    tester,
  ) async {
    final h = await pump(tester);
    h.repository.onCommand = (_, _) async =>
        throw TimeoutException('uncertain');
    await tester.tap(find.text('Save order'));
    await flush(tester, h);
    expect(find.text('Retry saved request'), findsOneWidget);
    final first = h.repository.commands.single.wire;
    h.repository.onCommand = null;
    await tester.tap(find.text('Retry saved request'));
    await flush(tester, h);
    expect(h.repository.commands.last.wire, first);
  });
  testWidgets(
    'AC-304 conflict UI requires inspection before keeping local edits',
    (tester) async {
      final h = await pump(tester);
      await tester.enterText(
        find.byKey(const Key('order-promised-date')),
        '2099-12-01',
      );
      await flush(tester, h);
      h.repository.onCommand = (_, _) async => CommandResult.failure(
        requestId: 'conflict',
        error: const DomainError(
          code: 'VERSION_CONFLICT',
          message: 'Order changed.',
        ),
      );
      await tester.tap(find.text('Save order'));
      await flush(tester, h);
      expect(find.text('Order changed on the server'), findsOneWidget);
      h.repository.detail = f.orderDetail(version: 8);
      await tester.tap(find.text('Inspect current server version'));
      await flush(tester, h);
      await tester.ensureVisible(find.text('Order changed on the server'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('order-golden')),
        matchesGoldenFile('goldens/order_conflict_1440_light.png'),
      );
      await tester.ensureVisible(find.text('Keep local edits for review'));
      await tester.tap(find.text('Keep local edits for review'));
      await flush(tester, h);
      expect(h.state.localDraft?.expectedVersion, 8);
      expect(h.state.form!['promised_date'], '2099-12-01');
    },
  );
  testWidgets('AC-304 accepted quotation opens explicit conversion fields', (
    tester,
  ) async {
    final h = await pump(tester, select: false);
    await tester.runAsync(() => h.controller.startConversion(q.quoteId));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('order-promised-date')),
      '2099-10-01',
    );
    await flush(tester, h);
    expect(find.text('Convert accepted quotation'), findsOneWidget);
    expect(find.text('Convert to order'), findsOneWidget);
    expect(find.byKey(const Key('quote-add-line')), findsNothing);
    await expectLater(
      find.byKey(const Key('order-golden')),
      matchesGoldenFile('goldens/order_conversion_1440_light.png'),
    );
  });
  testWidgets('AC-304 offline recovery remains visible and sending disabled', (
    tester,
  ) async {
    final h = await pump(tester, offline: true, select: false);
    await tester.runAsync(() => h.controller.newDraft());
    await tester.pumpAndSettle();
    expect(find.text('Offline · drafts available'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save order'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('AC-304 permission refresh hides an open credit dialog', (
    tester,
  ) async {
    var response = Future<Set<String>>.value(f.permissions);
    final h = await pump(tester, capabilitySource: () => response);
    await tester.tap(find.text('Review credit & confirm'));
    await flush(tester, h);
    final pending = Completer<Set<String>>();
    response = pending.future;
    h.container.invalidate(businessCapabilitiesProvider);
    await tester.pump();
    await tester.pump();
    expect(find.text('Business scope or access changed'), findsOneWidget);
    expect(find.byType(OrderCreditDialog), findsNothing);
    pending.complete({'sales.orders.view'});
    await tester.pumpAndSettle();
    expect(h.repository.commands, isEmpty);
  });
  testWidgets('AC-304 contact removal keeps delivery edits and stays removed', (
    tester,
  ) async {
    final h = await pump(tester);
    await tester.runAsync(
      () =>
          h.controller.updateForm({...h.state.form!, 'contact_id': 'contact'}),
    );
    // Reopen to reconstruct both editors from the persisted combined form.
    await tester.runAsync(() => h.controller.selectOrder(q.quoteId));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('order-promised-date')),
      '2099-12-02',
    );
    await flush(tester, h);
    final clear = find.byTooltip('Clear Contact');
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await flush(tester, h);
    expect(h.state.form!['contact_id'], isNull);
    expect(h.state.form!['promised_date'], '2099-12-02');
  });
}
