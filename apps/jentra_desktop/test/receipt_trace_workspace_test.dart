import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/receipt_trace/receipt_trace_controller.dart';
import 'package:jentra_desktop/src/features/receipt_trace/receipt_trace_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

const receipt = <String, Object?>{
  'id': 'receipt-line',
  'document_number': 'GR-0042',
  'product_name': 'Recycled office paper',
  'warehouse_name': 'Colombo warehouse',
  'posting_date': '2026-09-19',
  'received_quantity': '9007199254.740993',
  'covered': true,
};
const trace = <String, Object?>{
  'id': 'receipt-line',
  'covered': true,
  'received_quantity': '9007199254.740993',
  'held_quantity': '9007199250.740993',
  'in_transit_quantity': '1.000000',
  'net_issued_quantity': '3.000000',
  'observed_at': '2026-09-19T12:00:00Z',
  'attribution_rule':
      'Oldest recorded cohort within each lot or untracked pool; exact serial identity. Weighted-average valuation is unchanged.',
  'holdings': [
    {'warehouse_name': 'Colombo warehouse', 'quantity': '9007199250.740993'},
  ],
  'items': [
    {
      'sequence': '9007199254740993',
      'quantity': '-3.000000',
      'warehouse_name': 'Colombo warehouse',
      'posting_date': '2026-09-19',
      'source_type': 'delivery',
      'source_id': 'Delivery 0042',
      'lot_code': 'PAPER-SEP-26',
    },
  ],
  'next_cursor': '9007199254740993',
};

class TraceGateway implements ReceiptTraceGateway {
  Object? failure;
  bool covered = true;
  Completer<Map<String, Object?>>? pending;
  final calls = <String?>[];
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope, {
    String? after,
  }) async {
    if (failure != null) throw failure!;
    return {
      'items': [receipt],
      'next_cursor': after == null ? 'page2' : null,
    };
  }

  @override
  Future<Map<String, Object?>> detail(
    TenantContext scope,
    String id, {
    String? after,
  }) async {
    calls.add(after);
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return {
      ...trace,
      'id': id,
      'covered': covered,
      'next_cursor': after == null ? '9007199254740993' : null,
    };
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late TraceGateway gateway;
  late ReceiptTraceController c;
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
  setUp(() {
    gateway = TraceGateway();
    c = ReceiptTraceController(scope: scope, gateway: gateway, online: true);
  });
  tearDown(() => c.dispose());
  test(
    'history pages pin selected receipt and preserve bigint cursor',
    () async {
      await c.open(receipt);
      await c.refreshDetail(more: true);
      expect(gateway.calls, [null, '9007199254740993']);
      expect(c.history.length, 2);
      expect(c.detail!['received_quantity'], '9007199254.740993');
    },
  );
  test('scope denial removes previously loaded sensitive quantities', () async {
    await c.refresh();
    await c.open(receipt);
    gateway.failure = const DomainError(
      code: 'PERMISSION_DENIED',
      message: 'Revoked',
    );
    await c.refreshDetail();
    expect(c.rows, isEmpty);
    expect(c.detail, isNull);
    expect(c.selected, isNull);
    expect(c.history, isEmpty);
  });
  test('failed different receipt never relabels prior detail', () async {
    await c.open(receipt);
    gateway.failure = StateError('network');
    await c.open({...receipt, 'id': 'different'});
    expect(c.selected!['id'], 'different');
    expect(c.detail, isNull);
    expect(c.history, isEmpty);
  });
  test(
    'offline reads do not send a request and reconnect permits retry',
    () async {
      c.setOnline(false);
      await c.open(receipt);
      expect(gateway.calls, isEmpty);
      c.setOnline(true);
      await c.open(receipt);
      expect(gateway.calls.length, 1);
    },
  );
  test('disposed scope ignores an in-flight response', () async {
    final other = ReceiptTraceController(
      scope: scope,
      gateway: gateway,
      online: true,
    );
    gateway.pending = Completer();
    final work = other.open(receipt);
    other.dispose();
    gateway.pending!.complete(trace);
    await work;
    expect(other.detail, isNull);
  });
  test('navigation requires both valuation and cost capabilities', () {
    bool visible(Set<String> caps) => visibleJentraDestinations(
      caps,
    ).any((x) => x.path == '/inventory/receipt-trace');
    expect(visible({'inventory.valuation.post'}), false);
    expect(visible({'inventory.cost.view'}), false);
    expect(visible({'inventory.valuation.post', 'inventory.cost.view'}), true);
  });
  Future<void> render(
    WidgetTester tester, {
    bool dark = false,
    double height = 1300,
  }) async {
    tester.view.physicalSize = Size(1024, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: ReceiptTraceWorkspace(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('receipt trace ${dark ? 'dark' : 'light'} at 200 percent', (
      tester,
    ) async {
      await c.open(receipt);
      await render(tester, dark: dark);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/receipt_trace_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
  testWidgets('historical coverage is explicit and has no invented totals', (
    tester,
  ) async {
    gateway.covered = false;
    await c.open(receipt);
    await render(tester);
    expect(find.textContaining('attribution is unavailable'), findsOneWidget);
    expect(find.textContaining('In warehouses:'), findsNothing);
  });
  testWidgets('minimum desktop keeps history paging reachable', (tester) async {
    await c.open(receipt);
    await render(tester, height: 720);
    await tester.scrollUntilVisible(
      find.text('More movements'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('More movements'));
    await tester.pumpAndSettle();
    expect(gateway.calls, [null, '9007199254740993']);
    expect(tester.takeException(), isNull);
  });
}
