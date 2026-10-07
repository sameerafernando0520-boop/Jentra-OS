import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_asset_equipment.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_asset_equipment_platform.dart';
import 'package:jentra_desktop/src/features/service/asset_equipment_controller.dart';
import 'package:jentra_desktop/src/features/service/asset_equipment_screen.dart';
import 'package:jentra_desktop/src/features/service/service_controller.dart';

import 'service_acknowledgement_test.dart' show ServiceFake, scope, id;
import 'support/service_paused_keys.dart';

AssetEquipmentSource source() {
  final samples = serviceMap(
        jsonDecode(
          File(
            '../../packages/jentra_platform/test/fixtures/asset_equipment_rollback_projections.json',
          ).readAsStringSync(),
        ),
      ),
      link = serviceMap(samples['link']);
  return AssetEquipmentSource.fromJson({
    ...serviceMap(link['source_basis']),
    'tenant_id': scope.tenantId,
    'legal_entity_id': scope.legalEntityId,
    'branch_id': scope.branchId,
  }, scope);
}

class AssetFake extends ServiceFake implements AssetEquipmentRepository {
  Completer<void>? sourceGate, detailGate;
  bool customerEquipment = false, empty = false;
  @override
  Future<ServicePage<AssetEquipmentSource>> sources(
    TenantContext s, {
    String? after,
  }) async {
    await sourceGate?.future;
    return ServicePage(empty ? [] : [source()], null);
  }

  @override
  Future<AssetEquipmentLink> link(TenantContext s, String equipmentId) async {
    final samples = serviceMap(
      jsonDecode(
        File(
          '../../packages/jentra_platform/test/fixtures/asset_equipment_rollback_projections.json',
        ).readAsStringSync(),
      ),
    );
    return AssetEquipmentLink.fromJson({
      ...serviceMap(samples['link']),
      'equipment_id': equipmentId,
      'tenant_id': s.tenantId,
      'legal_entity_id': s.legalEntityId,
      'branch_id': s.branchId,
      'created_by': s.actorId,
      'source_basis': source().toJson(),
    }, s);
  }

  @override
  Future<ServicePage<ServiceRecord>> list(
    TenantContext s,
    ServiceKind kind, {
    String? after,
    String? parent,
  }) async => ServicePage(
    empty
        ? []
        : [
            ServiceRecord.fromJson(ServiceKind.equipment, {
              'id': id,
              'tenant_id': s.tenantId,
              'legal_entity_id': s.legalEntityId,
              'branch_id': s.branchId,
              'code': 'INTERNAL',
              'name': 'Internal fixed asset equipment',
              'identity': 'PUMP',
              'kind': 'asset',
              'customer_id': null,
              'provider_id': source().id,
              'version': 1,
              'status': 'active',
              'created_at': '2026-10-05T00:00:00Z',
              'created_by': s.actorId,
            }),
          ],
    null,
  );
  @override
  Future<ServiceDetail> detail(
    TenantContext s,
    ServiceKind kind,
    String equipmentId, {
    String? after,
  }) async {
    await detailGate?.future;
    final r = (await list(s, ServiceKind.equipment)).items.single.toJson();
    return ServiceDetail(
      ServiceRecord.fromJson(ServiceKind.equipment, {
        ...r,
        'id': equipmentId,
        'kind': customerEquipment ? 'customer' : 'asset',
        'customer_id': customerEquipment ? source().id : null,
        'provider_id': customerEquipment ? null : source().id,
      }),
      [],
      null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late EncryptedDraftRepository encrypted;
  late AssetFake repo;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(
      db,
      DraftCipher(keyStore: PausedKeys()),
    );
    repo = AssetFake();
  });
  tearDown(() async => db.close());
  ScopedCommandDraftStore store() => ScopedCommandDraftStore(
    encrypted,
    entityType: 'service.asset_equipment.command',
    fields: AssetEquipmentCommands.fields,
    validate: AssetEquipmentCommands.validate,
    definiteFailures: {
      'STATE_CONFLICT',
      'VERSION_CONFLICT',
      'IDENTITY_EXISTS',
      'VALIDATION_ERROR',
    },
  );
  AssetEquipmentController controller() => AssetEquipmentController(
    scope: scope,
    repository: repo,
    draft: store(),
    permissions: {'service.view', 'service.configure', 'assets.view'},
    online: true,
    monitor: false,
  );
  Future<void> ready(AssetEquipmentController c) async {
    await c.initialize();
    await c.begin();
    await c.loadSources();
    c.choose(c.sources.single);
    c.service.edit('code', 'INTERNAL');
    c.service.edit('reason', 'Governed internal maintenance');
  }

  test('AC-401 late asset choice is cleared after disconnect', () async {
    final c = controller();
    await c.initialize();
    await c.begin();
    repo.sourceGate = Completer<void>();
    final work = c.loadSources();
    await Future<void>.delayed(Duration.zero);
    c.service.setOnline(false);
    repo.sourceGate!.complete();
    await work;
    expect(c.sources, isEmpty);
    expect(c.service.form, isNull);
    c.dispose();
  });
  test(
    'AC-401 fresh asset permission revocation clears original form',
    () async {
      final c = controller();
      await ready(c);
      repo.authorizationFailure = const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Asset access revoked.',
      );
      await c.service.checkAccess();
      expect(c.service.denied, isTrue);
      expect(c.selected, isNull);
      expect(c.service.form, isNull);
      c.dispose();
    },
  );
  test('AC-401 immutable link history is cleared after disconnect', () async {
    final c = controller();
    await c.initialize();
    await c.inspect(id);
    expect(c.history!.source.name, source().name);
    c.service.setOnline(false);
    expect(c.history, isNull);
    c.dispose();
  });
  ServiceController tickets() => ServiceController(
    scope: scope,
    repository: repo,
    drafts: {
      'ticket': ScopedCommandDraftStore(
        encrypted,
        entityType: 'service.ticket.command',
        fields: ServiceCommands.fields,
        validate: ServiceCommands.validate,
        definiteFailures: {'VERSION_CONFLICT'},
      ),
    },
    permissions: {'service.view', 'service.triage', 'assets.view'},
    online: true,
    monitor: false,
  );
  test('AC-414 named equipment retains real customer or clears internal customer and contact', () async {
    final c = tickets();
    await c.initialize();
    await c.begin('ticket');
    c.edit('customer_id', source().id);
    c.edit('contact_id', source().id);
    final choice = ServiceChoice.fromJson({
      'id': id,
      'name': 'Internal equipment',
      'version': 1,
    });
    await c.choose('equipment_id', choice);
    expect(c.form!['customer_id'], isNull);
    expect(c.form!['contact_id'], isNull);
    expect(c.form!['equipment_id'], id);
    repo.customerEquipment = true;
    await c.choose('equipment_id', choice);
    expect(c.form!['customer_id'], source().id);
    expect(c.form!['contact_id'], isNull);
    c.dispose();
  });
  test(
    'AC-401 late equipment detail cannot populate a disconnected ticket',
    () async {
      final c = tickets();
      await c.initialize();
      await c.begin('ticket');
      repo.detailGate = Completer<void>();
      final choice = ServiceChoice.fromJson({
            'id': id,
            'name': 'Internal equipment',
            'version': 1,
          }),
          work = c.choose('equipment_id', choice);
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      repo.detailGate!.complete();
      await work;
      expect(c.form, isNull);
      expect(c.labels, isEmpty);
      c.dispose();
    },
  );
  test('AC-414 exact internal source survives encrypted restart and uncertain retry', () async {
    final c = controller();
    await ready(c);
    repo.commandFailure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'Synthetic uncertain transport.',
      retryable: true,
    );
    await c.service.send();
    final original = repo.commands.single.toJson((p) => p);
    expect(c.service.pending, isNotNull);
    c.dispose();
    repo.commandFailure = null;
    final fresh = controller();
    await fresh.initialize();
    await fresh.service.resume(fresh.service.recovery.single);
    await fresh.service.send();
    expect(repo.commands.last.toJson((p) => p), original);
    expect(repo.commands.last.payload['customer_id'], isNull);
    expect(repo.commands.last.payload['provider_digest'], source().digest);
    expect(
      await store().load(scope, repo.commands.last.payload['id'] as String),
      isNull,
    );
    fresh.dispose();
  });
  test(
    'AC-414 late known asset link is durably acknowledged for original scope',
    () async {
      final c = controller();
      await ready(c);
      repo.commandGate = Completer<void>();
      final work = c.service.send();
      while (repo.commands.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final request = c.service.pending!;
      c.service.setOnline(false);
      repo.commandGate!.complete();
      await work;
      expect(
        await ServiceCommandAcknowledgements(store()).contains(request),
        isTrue,
      );
      expect(c.service.form, isNull);
      c.dispose();
    },
  );
  testWidgets(
    'AC-415 empty register and eligible choices have explicit states',
    (tester) async {
      repo.empty = true;
      final c = controller();
      await c.initialize();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: AssetEquipmentWorkspace(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No internal asset equipment links in this branch.'),
        findsOneWidget,
      );
      await c.begin();
      await c.loadSources();
      await tester.pumpAndSettle();
      final empty = find.text(
        'No active, unlinked assets are eligible in this branch.',
      );
      await tester.ensureVisible(empty);
      expect(empty, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('AC-415 a named asset can be selected with the keyboard', (
    tester,
  ) async {
    final c = controller();
    await c.initialize();
    await c.begin();
    await c.loadSources();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: AssetEquipmentWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(
      ListTile,
      '${source().code} • ${source().name}',
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    final ink = find.descendant(of: tile, matching: find.byType(InkWell)),
        mouse = find
            .descendant(of: ink, matching: find.byType(MouseRegion))
            .first;
    Focus.of(tester.element(mouse)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(c.service.form!['provider_id'], source().id);
    expect(c.service.form!['provider_digest'], source().digest);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      for (final form in [false, true]) {
        testWidgets(
          'AC-415 internal asset ${form ? 'link form' : 'register'} ${dark ? 'dark' : 'light'} ${compact ? 'compact' : 'comfortable'}200 percent',
          (tester) async {
            tester.view.physicalSize = const Size(1024, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final font = FontLoader(JentraTypography.sansFamily)
              ..addFont(
                rootBundle.load(
                  'packages/jentra_design_system/assets/fonts/Manrope-Regular.ttf',
                ),
              )
              ..addFont(
                rootBundle.load(
                  'packages/jentra_design_system/assets/fonts/Manrope-SemiBold.ttf',
                ),
              );
            await font.load();
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
            final c = controller();
            if (form) {
              await ready(c);
            } else {
              await c.initialize();
            }
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: JentraTheme.light(
                    density: compact
                        ? JentraDensity.compact
                        : JentraDensity.comfortable,
                  ),
                  darkTheme: JentraTheme.dark(
                    density: compact
                        ? JentraDensity.compact
                        : JentraDensity.comfortable,
                  ),
                  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: RepaintBoundary(
                    key: const ValueKey('asset-link'),
                    child: AssetEquipmentWorkspace(controller: c),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (form) {
              await tester.ensureVisible(find.text('Create equipment link'));
              await tester.pumpAndSettle();
              expect(
                tester.getCenter(find.text('Create equipment link')).dy,
                lessThan(720),
              );
            }
            await expectLater(
              find.byKey(const ValueKey('asset-link')),
              matchesGoldenFile(
                'goldens/asset-equipment-${form ? 'form' : 'register'}-${dark ? 'dark' : 'light'}-${compact ? 'compact' : 'comfortable'}-200.png',
              ),
            );
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          },
        );
      }
    }
  }
}
