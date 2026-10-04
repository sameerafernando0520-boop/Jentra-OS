import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_service.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/service/service_controller.dart';
import 'package:jentra_desktop/src/features/service/service_screen.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const id = '20000000-0000-0000-0000-000000000001';

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Map<String, Object?> equipment(int version) => {
  'id': id,
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
  'version': version,
  'code': 'EQ-1',
  'name': 'Synthetic Pump',
  'identity': 'SERIAL-1',
  'kind': 'customer',
  'customer_id': id,
  'provider_id': null,
  'status': 'active',
};

class Repository implements ServiceRepository {
  bool denied = false, failRefresh = false;
  DomainError? failure;
  Completer<void>? gate;
  int version = 1;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  Map<String, Object?>? receipt;
  @override
  Future<ServiceAuthority> authorize(TenantContext scope, String cap) async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Current service access denied.',
      );
    }
    return const ServiceAuthority(
      'LKR',
      2,
      parts: false,
      billing: false,
      assets: false,
    );
  }

  @override
  Future<ServicePage<ServiceRecord>> list(
    TenantContext scope,
    ServiceKind kind, {
    String? after,
    String? parent,
  }) async {
    await gate?.future;
    if (failRefresh) {
      throw const DomainError(
        code: 'SERVICE_UNAVAILABLE',
        message: 'Optional read unavailable.',
      );
    }
    return ServicePage(
      kind == ServiceKind.equipment
          ? [ServiceRecord.fromJson(kind, equipment(version))]
          : [],
      null,
    );
  }

  @override
  Future<ServiceDetail> detail(
    TenantContext scope,
    ServiceKind kind,
    String selected, {
    String? after,
  }) async => ServiceDetail(
    ServiceRecord.fromJson(ServiceKind.equipment, equipment(version)),
    [],
    null,
  );
  @override
  Future<ServicePage<ServiceChoice>> choices(
    TenantContext scope,
    String kind, {
    String? after,
    String? parent,
  }) async => ServicePage([
    ServiceChoice.fromJson({
      'id': id,
      'name': 'Synthetic customer',
      'version': 1,
    }),
  ], null);
  @override
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) {
      throw failure!;
    }
    version = (command.expectedEntityVersion ?? 0) + 1;
    return receipt = {
      'command_id': command.commandId,
      'request_id': command.commandId,
      'correlation_id': command.commandId,
      'warnings': [],
      'entity': {
        'id': command.payload['id'],
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'version': version,
        'kind': ServiceCommands.kind(action).name,
        'status': 'active',
      },
    };
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String action,
    String key,
  ) async => receipt;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late JentraLocalDatabase db;
  late EncryptedDraftRepository encrypted;
  late Repository repo;
  late Keys keys;
  ServiceController create() => ServiceController(
    scope: scope,
    repository: repo,
    drafts: {
      for (final a in ServiceCommands.extras.keys)
        a: serviceDraftStore(encrypted, a),
    },
    permissions: serviceCapabilities,
    online: true,
    monitor: false,
  );
  setUp(() {
    keys = Keys();
    db = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
    repo = Repository();
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> fill(ServiceController c) async {
    await c.begin('equipment');
    c.edit('code', 'EQ-2');
    c.edit('name', 'Synthetic equipment');
    c.edit('identity', 'SYNTHETIC-0002');
    c.edit('customer_id', id);
    c.edit('reason', 'Synthetic test');
  }

  test(
    'uncertain result freezes exact request across controller restart',
    () async {
      final c = create();
      await fill(c);
      repo.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic timeout',
        retryable: true,
      );
      await c.send();
      final original = c.pending!.toJson();
      c.edit('name', 'Changed');
      expect(c.form!['name'], 'Synthetic equipment');
      c.dispose();
      final restarted = create();
      await restarted.loadRecovery();
      await restarted.resume(restarted.recovery.single);
      expect(restarted.pending!.toJson(), original);
      repo.failure = null;
      await restarted.send();
      expect(
        repo.commands[0].toJson((x) => x),
        repo.commands[1].toJson((x) => x),
      );
      expect(restarted.confirmed, isNotNull);
      expect(restarted.pending, isNull);
      restarted.dispose();
    },
  );
  test('confirmed change survives optional refresh failure', () async {
    final c = create();
    await fill(c);
    repo.failRefresh = true;
    await c.send();
    expect(c.confirmed, isNotNull);
    expect(c.pending, isNull);
    expect(c.error, 'Optional read unavailable.');
    c.dispose();
  });
  test('receipt reconciliation confirms original command', () async {
    final c = create();
    await fill(c);
    repo.failure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'Synthetic timeout',
      retryable: true,
    );
    await c.send();
    final request = c.pending!.envelope;
    repo.failure = null;
    repo.receipt = await repo.execute('equipment', request);
    await c.reconcile();
    expect(c.confirmed, isNotNull);
    expect(c.pending, isNull);
    c.dispose();
  });
  test(
    'revocation clears visible state and preserves encrypted request',
    () async {
      final c = create();
      await fill(c);
      repo.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic timeout',
        retryable: true,
      );
      await c.send();
      final draftId = c.form!['id'] as String;
      repo.denied = true;
      await c.checkAccess();
      expect(c.current, false);
      expect(c.form, isNull);
      expect(c.records, isEmpty);
      expect(
        (await c.drafts['equipment']!.load(scope, draftId))!.pending,
        isNotNull,
      );
      c.dispose();
    },
  );
  test('disposed scope discards late directory response', () async {
    final c = create();
    repo.gate = Completer<void>();
    final pending = c.refresh();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    repo.gate!.complete();
    await pending;
    expect(c.records, isEmpty);
    expect(c.authority, isNull);
  });
  test('stale draft requires explicit comparison and replacement', () async {
    final c = create();
    await c.begin('equipment');
    await fill(c);
    repo.failure = const DomainError(
      code: 'VERSION_CONFLICT',
      message: 'Synthetic stale version',
    );
    await c.send();
    expect(c.conflicted, true);
    expect(c.pending, isNull);
    c.edit('name', 'Changed');
    expect(c.form!['name'], 'Synthetic equipment');
    await c.compare();
    await c.adoptComparison();
    expect(c.expectedVersion, repo.version);
    expect(c.conflicted, false);
    c.dispose();
  });
  testWidgets('keyboard submission and named customer choice', (tester) async {
    final c = create();
    addTearDown(c.dispose);
    await fill(c);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ServiceWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    final customerChoice = find.widgetWithText(
      OutlinedButton,
      'Customer: Recorded choice ${id.substring(0, 8)}',
    );
    await tester.scrollUntilVisible(
      customerChoice,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(customerChoice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic customer'));
    await tester.pumpAndSettle();
    expect(c.labels['customer_id'], 'Synthetic customer');
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Reason'),
      -350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Reason'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.confirmed, isNotNull);
    expect(repo.commands, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('open service picker clears named choices after reconnect', (
    tester,
  ) async {
    final c = create();
    addTearDown(c.dispose);
    await fill(c);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ServiceWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    final customerChoice = find.widgetWithText(
      OutlinedButton,
      'Customer: Recorded choice ${id.substring(0, 8)}',
    );
    await tester.scrollUntilVisible(
      customerChoice,
      350,
      scrollable: find.byType(Scrollable).first,
    );
      await tester.pumpAndSettle();
    await tester.tap(customerChoice);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic customer'), findsOneWidget);
    c.setOnline(false);
    c.setOnline(true);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic customer'), findsNothing);
    expect(
      find.text(
        'Service scope or form changed. Reopen the picker after checking current access.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.form, isNull);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final density in [JentraDensity.comfortable, JentraDensity.compact]) {
      for (final editor in [false, true]) {
        testWidgets(
          'service ${editor ? 'equipment' : 'register'} ${dark ? 'dark' : 'light'} ${density.name} 200 percent preview',
          (tester) async {
            tester.view.physicalSize = const Size(1024, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final c = create();
            addTearDown(c.dispose);
            c.kind = ServiceKind.equipment;
            await c.initialize();
            if (editor) {
              await fill(c);
              c.labels['customer_id'] = 'Synthetic customer';
            }
            final theme = dark
                ? JentraTheme.dark(density: density)
                : JentraTheme.light(density: density);
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(1024, 720),
                    textScaler: TextScaler.linear(2),
                  ),
                  child: Scaffold(
                    body: RepaintBoundary(
                      key: const ValueKey('service_preview'),
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: ServiceWorkspace(controller: c),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (editor) {
              await tester.scrollUntilVisible(
                find.widgetWithText(TextField, 'Reason'),
                350,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(const ValueKey('service_preview')),
              matchesGoldenFile(
                'goldens/service-${editor ? 'equipment' : 'register'}-${dark ? 'dark' : 'light'}-${density.name}-200.png',
              ),
            );
          },
        );
      }
    }
  }
  test(
    'actual SQL labor and occurrence projections are retained immutably',
    () {
      final samples = serviceMap(
        jsonDecode(
          File(
            '../../packages/jentra_platform/test/fixtures/service_rollback_projections.json',
          ).readAsStringSync(),
        ),
      );
      final labor = ServiceRecord.fromJson(
        ServiceKind.labor,
        serviceMap(serviceMap(samples['labor-approved'])['record']),
      );
      final copy = labor.toJson();
      copy['amount'] = '0';
      expect(labor.toJson()['amount'], '123.460000');
    },
  );
}
