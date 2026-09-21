import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_controller.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_screen.dart';
import 'support/procurement_fakes.dart' show Keys;

class Transfers implements InventoryTransferGateway {
  @override
  Future<Map<String, Object?>> holdings(
    TenantContext scope,
    String asOf, {
    String? after,
  }) async => {'items': [], 'as_of': asOf};
  bool uncertain = true, failRefresh = false;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry saved request.',
      );
    }
    return {'id': command.payload['id'], 'status': 'in_transit', 'version': 1};
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope, {
    String? after,
  }) async {
    if (failRefresh) throw StateError('offline');
    return {'items': []};
  }

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
    String search = '',
  }) async => {'items': []};
}

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
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late Transfers gateway;
  late InventoryTransferController c;
  InventoryTransferController make({TenantContext context = scope}) =>
      InventoryTransferController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = Transfers();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> draft() async {
    await c.initialize();
    await c.create();
    c.update('source_warehouse_id', 'source');
    c.update('destination_warehouse_id', 'destination');
    c.update('_source_name', 'Colombo dispatch');
    c.update('_destination_name', 'Kandy receiving');
    c.update('reference', 'TR-0042');
    c.update('reason', 'Replenish receiving warehouse');
    c.update('document_date', '2026-09-15');
    c.addProduct({
      'id': 'paper',
      'name': 'Recycled office paper',
      'base_unit_id': 'each',
      'tracking_mode': 'none',
      'units': [
        {'id': 'each', 'name': 'Each', 'numerator': '1', 'denominator': '1'},
      ],
    });
    c.updateLine(0, 'quantity', '9007199254.740993');
  }

  test(
    'uncertain dispatch remains byte-identical across controller restart',
    () async {
      await draft();
      await c.submit();
      expect(c.local?.pending, isNotNull);
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = make();
      await c.initialize();
      c.updateLine(0, 'quantity', '2');
      expect(
        (c.form!['lines'] as List).single['quantity'],
        '9007199254.740993',
      );
      await c.discard();
      expect(c.local?.pending, isNotNull);
      gateway.uncertain = false;
      await c.submit();
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form, isNull);
    },
  );
  for (final operation in ['receive', 'reverse']) {
    test(
      '$operation retains expected version and operation across restart',
      () async {
        await c.initialize();
        await c.prepare({
          'id': 'existing',
          'version': 7,
          'status': 'in_transit',
          'reference': 'TR-7',
          'lines': [],
        }, operation);
        c.update('reason', 'Verified warehouse action');
        await c.submit();
        expect(gateway.commands.single.expectedEntityVersion, 7);
        final original = jsonEncode(gateway.commands.single.toJson((p) => p));
        c.dispose();
        c = make();
        await c.initialize();
        gateway.uncertain = false;
        await c.submit();
        expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
        expect(gateway.commands.last.payload['operation'], operation);
      },
    );
  }
  test('offline edits persist on navigation without dispatch', () async {
    await draft();
    c.setOnline(false);
    await c.submit();
    expect(gateway.commands, isEmpty);
    expect(await c.canLeave(), isTrue);
    c.dispose();
    c = make();
    await c.initialize();
    expect((c.form!['lines'] as List).single['quantity'], '9007199254.740993');
  });
  test('branch isolation hides another branch draft', () async {
    await draft();
    await c.save();
    c.dispose();
    c = make(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await c.initialize();
    expect(c.form, isNull);
  });
  test('invalid tracking never seals a command', () async {
    await draft();
    c.updateLine(0, 'tracking_mode', 'serial');
    await c.submit();
    expect(c.error, contains('serial'));
    expect(c.local?.pending, isNull);
    expect(gateway.commands, isEmpty);
  });
  test('posting success survives register refresh failure', () async {
    await draft();
    gateway.uncertain = false;
    gateway.failRefresh = true;
    await c.submit();
    expect(c.form, isNull);
    expect(c.message, contains('posted'));
    expect(c.error, contains('Posted successfully'));
  });
  test('dated holdings do not overwrite an edited local draft', () async {
    await draft();
    final before = jsonEncode(c.form);
    c.holdingsDate = '2026-09-14';
    await c.loadHoldings();
    expect(c.loadedHoldingsDate, '2026-09-14');
    expect(jsonEncode(c.form), before);
    expect(gateway.commands, isEmpty);
  });
  testWidgets('posting controls remain reachable at minimum desktop height', (
    tester,
  ) async {
    await draft();
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: InventoryTransferWorkspace(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Dispatch shipment'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('transfer editor ${dark ? 'dark' : 'light'} at 200 percent', (
      tester,
    ) async {
      await draft();
      c.updateLine(0, 'quantity', '12.5');
      tester.view.physicalSize = const Size(1024, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: InventoryTransferWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/inventory_transfer_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Dispatch shipment'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dispatch shipment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
