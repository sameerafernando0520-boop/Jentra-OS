import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_controller.dart';
import 'package:jentra_desktop/src/features/period_fx/period_fx_screen.dart';

import 'support/procurement_fakes.dart' show Keys;

final class PeriodFxFake implements PeriodFxGateway {
  String? failure, readFailure;
  bool noPeriods = false;
  String state = 'open';
  int version = 1;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];

  @override
  Future<Map<String, Object?>> periodOptions(
    TenantContext scope,
    String resource, {
    String? periodId,
    String? after,
  }) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
    return {
      'items': [
        if (resource == 'periods' && !noPeriods)
          {
            'id': 'period',
            'name': 'September close',
            'start_date': '2026-09-01',
            'end_date': '2026-09-21',
            'state': state,
            'version': version,
          },
      ],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>> fxOptions(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
    return {
      'items': [
        if (resource == 'rates')
          {
            'id': 'rate',
            'source_currency_code': 'USD',
            'target_currency_code': 'LKR',
            'rate': '1.2000000000',
            'effective_date': '2026-09-21',
          },
      ],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>> fxDetail(
    TenantContext scope,
    String runId, {
    int offset = 0,
  }) async => {
    'items': [
      {
        'id': 'open',
        'kind': 'AR',
        'document_number': 'AR-1',
        'open_amount': '100.000000',
        'open_base_amount': '100.000000',
        'control_account_id': 'control',
      },
    ],
    'next_offset': null,
  };

  @override
  Future<Map<String, Object?>> govern(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    if (command.payload['action'] == 'soft_lock') {
      state = 'soft_locked';
      version++;
    }
    return {'id': command.payload['id'], 'status': state};
  }

  @override
  Future<Map<String, Object?>> revalue(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    return {'id': command.payload['id'], 'status': 'posted'};
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
  late PeriodFxFake gateway;
  late PeriodFxController controller;
  PeriodFxController make({bool online = true, Set<String>? caps}) =>
      PeriodFxController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        capabilities:
            caps ??
            {
              'finance.view',
              'finance.period.close',
              'finance.period.reopen',
              'finance.fx.post',
            },
        online: online,
      );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    gateway = PeriodFxFake();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> ready() async {
    await controller.initialize();
    await controller.selectPeriod('period');
    controller.field('reason', 'Exact synthetic period close');
    controller.field('as_of', '2026-09-21');
    controller.field('currency_code', 'USD');
    controller.field('exchange_rate_id', 'rate');
  }

  test(
    'uncertain FX result survives encrypted restart with identical envelope',
    () async {
      await ready();
      gateway.failure = 'UNCERTAIN_RESULT';
      await controller.execute('post');
      expect(controller.pending, true);
      final original = gateway.commands.single.toJson((value) => value);
      controller.dispose();
      controller = make();
      await controller.initialize();
      expect(controller.form['reason'], 'Exact synthetic period close');
      controller.field('reason', 'Cannot replace sealed reason');
      expect(controller.form['reason'], 'Exact synthetic period close');
      gateway.failure = null;
      await controller.retry();
      expect(gateway.commands.last.toJson((value) => value), original);
      expect(controller.pending, false);
    },
  );

  test(
    'period close command uses the current version and refreshes state',
    () async {
      await ready();
      await controller.execute('soft_lock');
      expect(gateway.commands.single.expectedEntityVersion, 1);
      expect(controller.period?['state'], 'soft_locked');
      expect(controller.pending, false);
      expect(controller.message, contains('confirmed'));
    },
  );

  test(
    'offline recovery hides server evidence and disables commands',
    () async {
      await ready();
      controller.dispose();
      controller = make(online: false);
      await controller.initialize();
      expect(controller.verified, false);
      expect(controller.rows('periods'), isEmpty);
      await controller.execute('post');
      expect(gateway.commands, isEmpty);
      controller.setOnline(true);
      await controller.initialize();
      expect(controller.periodId, 'period');
    },
  );

  test('read revocation removes cached evidence and form', () async {
    await ready();
    gateway.readFailure = 'PERMISSION_DENIED';
    await controller.refresh();
    expect(controller.denied, true);
    expect(controller.rows('periods'), isEmpty);
    expect(controller.form, isEmpty);
  });

  test('view-only capability cannot send period or FX command', () async {
    controller.dispose();
    controller = make(caps: {'finance.view'});
    await ready();
    await controller.execute('soft_lock');
    await controller.execute('post');
    expect(gateway.commands, isEmpty);
  });

  testWidgets('empty periods explain setup without posting commands', (
    tester,
  ) async {
    gateway.noPeriods = true;
    await controller.initialize();
    var openedSetup = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: Scaffold(
          body: PeriodFxWorkspace(
            controller: controller,
            onOpenBusinessSetup: () => openedSetup = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No fiscal periods available'), findsOneWidget);
    expect(
      find.textContaining('Create a fiscal period in Business setup'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Open Business setup'));
    await tester.tap(find.text('Open Business setup'));
    expect(openedSetup, isTrue);
    expect(gateway.commands, isEmpty);
    controller.error = 'Period evidence could not be loaded.';
    controller.emit();
    await tester.pump();
    expect(find.text('No fiscal periods available'), findsNothing);
    controller.error = null;
    controller.busy = true;
    controller.emit();
    await tester.pump();
    expect(find.text('No fiscal periods available'), findsNothing);
    controller.busy = false;
    controller.setOnline(false);
    await tester.pump();
    expect(find.text('No fiscal periods available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop workspace exposes period and FX controls at 200% text', (
    tester,
  ) async {
    await ready();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: PeriodFxWorkspace(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Period & FX close'), findsOneWidget);
    expect(find.text('Soft lock'), findsOneWidget);
    expect(find.text('Post revaluation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} period and FX workspace at 200% text',
      (tester) async {
        await ready();
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: PeriodFxWorkspace(controller: controller)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(PeriodFxWorkspace),
          matchesGoldenFile(
            'goldens/period_fx_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}
