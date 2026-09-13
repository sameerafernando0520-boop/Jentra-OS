import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_controller.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_screen.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Gateway implements ProcurementGateway {
  @override
  Future<CursorPage<Map<String, Object?>>> rfqs(
    TenantContext scope, {
    String? after,
  }) => page(scope, after: after);
  @override
  Future<Map<String, Object?>> source(
    CommandEnvelope<Map<String, Object?>> command,
  ) => save(command);
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  bool uncertain = false;
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async => {
    'base_currency': 'LKR',
    'items': await units(scope),
    'next_cursor': null,
  };
  @override
  Future<Map<String, Object?>> transition(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    return {
      'id': command.payload['document_id'],
      'version': 2,
      'status': 'pending_approval',
    };
  }

  @override
  Future<CursorPage<Map<String, Object?>>> page(
    TenantContext scope, {
    String? after,
  }) async => CursorPage(items: [], limit: 50);
  @override
  Future<List<Map<String, Object?>>> units(TenantContext scope) async => [
    {'id': 'unit', 'code': 'EA', 'name': 'Each'},
  ];
  @override
  Future<Map<String, Object?>> save(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry the saved command.',
      );
    }
    return {...command.payload, 'version': 1, 'status': 'draft'};
  }
}

void main() {
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('${base}IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late JentraLocalDatabase database;
  late ProcurementController controller;
  late _Gateway gateway;
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    gateway = _Gateway();
    controller = ProcurementController(
      scope: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'b',
      ),
      gateway: gateway,
      store: QuotationDraftStore.procurement(
        EncryptedDraftRepository(database, DraftCipher(keyStore: _Keys())),
      ),
      online: true,
    );
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> draft() async {
    await controller.initialize();
    await controller.create('LKR');
    controller.update('justification', 'Replenish office paper');
    controller.update('need_by', '2026-09-30');
    controller.update('lines', [
      {
        'line_id': 'line',
        'description': 'Paper',
        'unit_id': 'unit',
        'quantity': '3',
        'estimated_unit_price': '123.456789',
        'conversion_numerator': '1',
        'conversion_denominator': '1',
      },
    ]);
  }

  test(
    'AC-309 uncertain save freezes exact payload until confirmed retry',
    () async {
      await draft();
      gateway.uncertain = true;
      await controller.saveServer();
      expect(controller.recovery!.pending, isNotNull);
      controller.update('justification', 'changed');
      expect(controller.form!['justification'], 'Replenish office paper');
      gateway.uncertain = false;
      await controller.saveServer();
      expect(gateway.commands.length, 2);
      expect(
        gateway.commands[1].toJson((p) => p),
        gateway.commands[0].toJson((p) => p),
      );
      expect(controller.form, isNull);
    },
  );
  test(
    'AC-309 offline saves retain local fields and never issue a command',
    () async {
      await draft();
      controller.setOnline(false);
      await controller.saveServer();
      expect(gateway.commands, isEmpty);
      expect(await controller.canLeave(), isTrue);
      final local = await controller.store.load(
        controller.scope,
        ProcurementController.slot,
      );
      expect(local!.form['justification'], 'Replenish office paper');
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'AC-321 procurement editor ${dark ? 'dark' : 'light'} at 200% text',
      (tester) async {
        await tester.runAsync(draft);
        tester.view.physicalSize = const Size(1024, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: ProcurementWorkspace(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Replenish office paper'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/procurement_editor_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}
