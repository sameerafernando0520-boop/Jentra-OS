import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/financial_statements/cash_flow_mapping_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/cash_flow_mapping_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;

final class CashFlowMappingFake implements CashFlowMappingGateway {
  String? failure, readFailure;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String asOf, {
    String? after,
  }) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
    return {
      'items': [
        {
          'id': 'cash',
          'account_id': 'cash',
          'code': '1000',
          'name': 'Cash at bank',
          'account_type': 'asset',
          'status': 'active',
          'category': commands.isEmpty ? null : 'cash',
          'effective_date': commands.isEmpty ? null : asOf,
          'version': commands.isEmpty ? 0 : 1,
        },
      ],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>> configure(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    return {...command.payload, 'version': 1, 'status': 'configured'};
  }
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
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late JentraLocalDatabase database;
  late QuotationDraftStore drafts;
  late CashFlowMappingFake gateway;
  late CashFlowMappingController controller;
  CashFlowMappingController make({bool online = true}) =>
      CashFlowMappingController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: online,
        clock: () => DateTime.utc(2026, 9, 25),
      );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    gateway = CashFlowMappingFake();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'uncertain mapping survives encrypted restart with exact envelope',
    () async {
      await controller.initialize();
      await controller.select('cash');
      controller.field('category', 'cash');
      controller.field('reason', 'Bank account mapped');
      gateway.failure = 'UNCERTAIN_RESULT';
      await controller.configure();
      expect(controller.pending, true);
      final sealed = gateway.commands.single.toJson((value) => value);
      controller.dispose();
      controller = make();
      await controller.initialize();
      controller.field('category', 'financing');
      expect(controller.form['category'], 'cash');
      gateway.failure = null;
      await controller.retry();
      expect(gateway.commands.last.toJson((value) => value), sealed);
      expect(controller.pending, false);
    },
  );

  test('invalid reason and date remain local', () async {
    await controller.initialize();
    await controller.select('cash');
    controller.field('category', 'cash');
    controller.field('reason', 'x');
    await controller.configure();
    expect(controller.error, contains('reason'));
    expect(gateway.commands, isEmpty);
    controller.field('reason', 'Mapped cash account');
    controller.field('effective_date', '2030-01-01');
    await controller.configure();
    expect(controller.error, contains('effective date'));
    expect(gateway.commands, isEmpty);
  });

  test('offline restart hides accounts until verified read', () async {
    await controller.initialize();
    await controller.select('cash');
    controller.field('reason', 'Mapped cash account');
    await controller.save();
    controller.dispose();
    controller = make(online: false);
    await controller.initialize();
    expect(controller.accounts, isEmpty);
    expect(controller.verified, false);
    controller.setOnline(true);
    await controller.initialize();
    expect(controller.form['reason'], 'Mapped cash account');
  });

  test('revoked access clears account evidence and editor', () async {
    await controller.initialize();
    await controller.select('cash');
    gateway.readFailure = 'PERMISSION_DENIED';
    await controller.refresh();
    expect(controller.denied, true);
    expect(controller.accounts, isEmpty);
    expect(controller.form, isEmpty);
  });

  test('mapping navigation requires view and configure', () {
    const route = '/finance/cash-flow-mappings';
    expect(
      visibleJentraDestinations({'finance.view'}).any((x) => x.path == route),
      false,
    );
    expect(
      visibleJentraDestinations({
        'finance.view',
        'finance.cash_flow.configure',
      }).any((x) => x.path == route),
      true,
    );
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'} mapping workspace at 200% text', (
      tester,
    ) async {
      await controller.initialize();
      await controller.select('cash');
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: CashFlowMappingWorkspace(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(CashFlowMappingWorkspace),
        matchesGoldenFile(
          'goldens/cash_flow_mappings_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
}
