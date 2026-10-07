import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_assets.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_assets_platform.dart';
import 'package:jentra_desktop/src/features/assets/assets_controller.dart';
import 'package:jentra_desktop/src/features/assets/assets_screen.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const id = '20000000-0000-0000-0000-000000000001',
    bookId = '30000000-0000-0000-0000-000000000001';

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String k) async => values[k];
  @override
  Future<void> write(String k, String v) async {
    values[k] = v;
  }
}

Map<String, Object?> recordWire([int version = 3]) => {
  'id': id,
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
  'original_branch_id': scope.branchId,
  'code': 'SYN-1',
  'name': 'Synthetic equipment',
  'ownership': 'Synthetic owned',
  'currency_code': 'LKR',
  'in_service': '2026-01-01',
  'location_id': bookId,
  'custodian_id': null,
  'status': 'active',
  'version': version,
  'cost': '1000.000000',
  'accumulated': '200.000000',
  'impairment': '300.000000',
  'carrying': '500.000000',
  'cost_account_id': id,
  'accumulated_account_id': bookId,
  'impairment_account_id': '40000000-0000-0000-0000-000000000001',
  'book_id': bookId,
  'posted_periods': 0,
  'proposal_id': null,
  'last_effect_id': id,
};
AssetBookDefinition definition() => AssetBookDefinition.fromJson({
  'residual': '100.000000',
  'remaining_months': 2,
  'method': 'straight_line',
  'convention': 'in_service_month',
  'rate_numerator': 1,
  'rate_denominator': 1,
  'precision': 2,
  'expense_account_id': id,
  'cost': '1000.000000',
  'opening_accumulated': '200.000000',
  'opening_impairment': '300.000000',
  'start_date': '2026-02-01',
  'in_service': '2026-01-01',
  'currency_code': 'LKR',
});
AssetOpening opening() => AssetOpening.fromJson({
  'id': bookId,
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'asset_id': id,
  'source_reference': 'SYNTHETIC-OPENING',
  'cost': '1000.000000',
  'opening_accumulated': '200.000000',
  'components': [
    {'code': 'OPENING', 'name': 'Synthetic opening', 'amount': '1000'},
  ],
  'reason': 'Governed synthetic opening',
  'recorded_by': scope.actorId,
  'recorded_at': '2026-09-30T00:00:00Z',
}, 'LKR');

class Repository implements AssetRepository {
  int version = 3;
  bool deny = false, failRefresh = false;
  String? refreshFailure;
  DomainError? failure;
  Completer<void>? registerGate;
  Completer<void>? authorizationGate, executeGate;
  Completer<Map<String, Object?>?>? receiptGate;
  String? authorizationFailure;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<AssetProviderState> authorize(
    TenantContext s,
    String capability,
  ) async {
    await authorizationGate?.future;
    if (authorizationFailure != null) {
      throw DomainError(
        code: authorizationFailure!,
        message: 'Access changed.',
      );
    }
    if (deny) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Access changed.',
      );
    }
    return AssetProviderState(
      procurement: false,
      stock: false,
      equipment: false,
      currency: 'LKR',
      precision: 2,
      businessDate: CivilDate.parse('2026-10-01'),
    );
  }

  @override
  Future<AssetPage<AssetRecord>> register(
    TenantContext s, {
    String? after,
  }) async {
    await registerGate?.future;
    if (failRefresh) {
      throw DomainError(
        code: refreshFailure ?? 'SERVICE_UNAVAILABLE',
        message: 'Refresh unavailable.',
      );
    }
    return AssetPage([AssetRecord.fromJson(recordWire(version))], null);
  }

  @override
  Future<AssetDetail> detail(
    TenantContext s,
    String assetId,
    AssetHistoryKind kind, {
    String? after,
  }) async => AssetDetail(
    asset: AssetRecord.fromJson(recordWire(version)),
    kind: kind,
    opening: opening(),
  );
  @override
  Future<AssetSchedulePage> schedule(
    TenantContext s,
    String assetId,
    String book, {
    int after = 0,
  }) async => AssetSchedulePage(
    bookId,
    definition(),
    definition().schedule.periods,
    null,
  );
  @override
  Future<AssetPage<AssetPicker>> pickers(
    TenantContext s,
    String kind, {
    String? after,
  }) async => AssetPage([
    AssetPicker.fromJson({
      'id': after == null ? bookId : id,
      'code': after == null ? 'LAB' : 'SECOND',
      'name': after == null ? 'Synthetic named choice' : 'Another named choice',
      if (!{'locations', 'custodians'}.contains(kind)) ...{
        'kind': kind,
        'currency_code': 'LKR',
        'version': 1,
      },
    }, kind),
  ], after == null ? bookId : null);
  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext s,
    String key,
    String action,
  ) async => receiptGate == null ? null : await receiptGate!.future;
  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    await executeGate?.future;
    if (failure != null) {
      throw failure!;
    }
    return {
      'request_id': command.commandId,
      'command_id': command.commandId,
      'correlation_id': command.commandId,
      'warnings': [],
      'entity': {
        'id': command.payload['id'],
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'version': 1,
      },
    };
  }
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
  late Repository repository;
  AssetsController create({Set<String>? permissions}) => AssetsController(
    scope: scope,
    repository: repository,
    drafts: {for (final a in assetActions) a: assetDrafts(encrypted, a)},
    permissions: permissions ?? assetCapabilities,
    online: true,
    branches: const [],
    monitor: false,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));
    repository = Repository();
  });
  tearDown(() async {
    await db.close();
  });
  Future<String> location(AssetsController c) async {
    await c.begin('location');
    c.update('code', 'LAB');
    c.update('name', 'Synthetic location');
    c.update('reason', 'Synthetic configuration');
    return c.form!['id'] as String;
  }

  test(
    'late confirmation survives disposal without another dispatch',
    () async {
      final c = create();
      await c.initialize();
      final localId = await location(c);
      repository.executeGate = Completer<void>();
      final sending = c.send();
      while (repository.commands.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final sealed = c.pending!;
      c.dispose();
      repository.executeGate!.complete();
      await sending;
      expect(await c.drafts['location']!.load(scope, localId), isNull);
      expect(
        await AssetCommandAcknowledgements(c.drafts['location']!)
            .contains(sealed),
        isTrue,
      );
      expect(c.confirmed, isNull);
      expect(repository.commands, hasLength(1));
    },
  );
  test(
    'confirmed cleanup failure survives restart and prevents reissue',
    () async {
      final c = create();
      await c.initialize();
      await location(c);
      await db.customStatement(
        "CREATE TEMP TRIGGER fail_asset_cleanup BEFORE DELETE ON encrypted_drafts BEGIN SELECT RAISE(ABORT, 'synthetic cleanup failure'); END",
      );
      await c.send();
      final sealed = c.pending!;
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNotNull);
      expect(
        await AssetCommandAcknowledgements(c.drafts['location']!)
            .contains(sealed),
        isTrue,
      );
      c.dispose();
      final restarted = create();
      await restarted.initialize();
      await restarted.resume(restarted.recovery.single);
      expect(restarted.confirmed, isNotNull);
      await restarted.send();
      expect(repository.commands, hasLength(1));
      expect(restarted.pending!.envelope.commandId, sealed.envelope.commandId);
      restarted.dispose();
    },
  );
  test(
    'confirmation storage failure retains known success and exact uncertainty',
    () async {
      final c = create();
      await c.initialize();
      await location(c);
      await db.customStatement(
        "CREATE TEMP TRIGGER fail_asset_ack BEFORE INSERT ON encrypted_drafts WHEN NEW.entity_type = 'assets.command.acknowledgement' BEGIN SELECT RAISE(ABORT, 'synthetic acknowledgement failure'); END",
      );
      await c.send();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNotNull);
      expect(c.message, contains('Saving the encrypted confirmation failed'));
      await c.send();
      expect(repository.commands, hasLength(1));
      c.dispose();
    },
  );
  test('old authority response cannot authorize a reconnected send', () async {
    final c = create();
    await c.initialize();
    await location(c);
    repository.authorizationGate = Completer<void>();
    final sending = c.send();
    await Future<void>.delayed(Duration.zero);
    c.setOnline(false);
    c.setOnline(true);
    repository.authorizationGate!.complete();
    await sending;
    expect(c.error, contains('Recheck before continuing'));
    expect(repository.commands, isEmpty);
    expect(c.pending, isNull);
    expect(c.current, isTrue);
    c.dispose();
  });
  test('old authority denial cannot clear a replacement connection', () async {
    final c = create();
    await c.initialize();
    await location(c);
    repository.authorizationGate = Completer<void>();
    repository.authorizationFailure = 'PERMISSION_DENIED';
    final checking = c.checkAccess();
    await Future<void>.delayed(Duration.zero);
    c.setOnline(false);
    c.setOnline(true);
    repository.authorizationGate!.complete();
    await checking;
    expect(c.current, isTrue);
    expect(c.form, isNotNull);
    c.dispose();
  });
  test(
    'MFA loss clears decrypted recovery and financial projections',
    () async {
      final c = create();
      await c.initialize();
      final localId = await location(c);
      await c.save();
      repository.authorizationFailure = 'MFA_REQUIRED';
      await c.checkAccess();
      expect(c.current, isFalse);
      expect(c.records, isEmpty);
      expect(c.recovery, isEmpty);
      expect(c.form, isNull);
      expect(await c.drafts['location']!.load(scope, localId), isNotNull);
      c.dispose();
    },
  );
  test(
    'old directory response cannot populate a replacement connection',
    () async {
      final c = create();
      repository.registerGate = Completer<void>();
      final loading = c.initialize();
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      c.setOnline(true);
      repository.registerGate!.complete();
      await loading;
      expect(c.records, isEmpty);
      expect(c.current, isTrue);
      c.dispose();
    },
  );
  test(
    'permission loss during optional confirmed refresh clears all visible data',
    () async {
      final c = create();
      await c.initialize();
      await c.begin('location');
      c.update('code', 'LAB');
      c.update('name', 'Synthetic location');
      c.update('reason', 'Synthetic configuration');
      final localId = c.form!['id'] as String;
      repository.failRefresh = true;
      repository.refreshFailure = 'PERMISSION_DENIED';
      await c.send();
      expect(c.current, isFalse);
      expect(c.records, isEmpty);
      expect(c.form, isNull);
      expect(c.confirmed, isNull);
      expect(await c.drafts['location']!.load(scope, localId), isNull);
      c.dispose();
    },
  );
  testWidgets(
    'independent approval review shows actual scoped mappings and whole book',
    (tester) async {
      final samples = jsonDecode(
        File(
          '../../packages/jentra_platform/test/fixtures/assets_rollback_projections.json',
        ).readAsStringSync(),
      ) as Map;
      final row = assetMap(samples['opening.books']),
          asset = AssetRecord.fromJson(assetMap(row['asset']));
      final c = create();
      addTearDown(c.dispose);
      await c.initialize();
      c.selected = AssetDetail(
        asset: asset,
        kind: AssetHistoryKind.books,
        opening: AssetOpening.fromJson(
          assetMap(row['opening']),
          asset.currency,
        ),
        proposal: AssetProposal.fromJson(
          assetMap(row['proposal']),
          asset.currency,
        ),
        labels: {
          for (final entry in assetMap(row['labels']).entries)
            entry.key: entry.value as String?,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          home: Scaffold(body: AssetsWorkspace(controller: c)),
        ),
      );
      await tester.scrollUntilVisible(
        find.textContaining('monthly rate 1/1'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('half-even precision 2'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('offset account · OFFSET'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('OFFSET · Synthetic asset offset'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('asset navigation requires the current view permission', () {
    expect(
      visibleJentraDestinations({}).any((d) => d.path == '/assets'),
      isFalse,
    );
    expect(
      visibleJentraDestinations({'assets.view'})
          .any((d) => d.path == '/assets'),
      isTrue,
    );
  });
  test('a failed action leaves no partial form or invented currency', () async {
    final c = create();
    await c.initialize();
    await c.select(c.records.single);
    await c.begin('propose', kind: 'unsupported');
    expect(c.form, isNull);
    await c.begin('opening');
    expect(c.form!['currency_code'], 'LKR');
    c.update('currency_code', 'USD');
    expect(c.form!['currency_code'], 'LKR');
    c.dispose();
  });
  test(
    'an incomplete financial confirmation cannot clear encrypted recovery',
    () async {
      final c = create();
      await c.initialize();
      await c.select(c.records.single);
      await c.begin('depreciate');
      c.update('reason', 'Synthetic asset action');
      await c.send();
      expect(c.confirmed, isNull);
      expect(c.pending, isNotNull);
      expect(c.local!.errorCode, 'UNCERTAIN_RESULT');
      c.dispose();
    },
  );
  testWidgets('opening editor chooses named locations and loads another page', (
    tester,
  ) async {
    final c = create();
    addTearDown(c.dispose);
    await c.initialize();
    await c.begin('opening');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AssetsEditor(controller: c)),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Choose asset location'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Choose asset location'));
    await tester.pumpAndSettle();
    expect(find.text('LAB · Synthetic named choice'), findsOneWidget);
    await tester.tap(find.text('More choices'));
    await tester.pumpAndSettle();
    expect(find.text('SECOND · Another named choice'), findsOneWidget);
    await tester.tap(find.text('SECOND · Another named choice'));
    await tester.pumpAndSettle();
    expect(c.form!['location_id'], id);
    expect(find.textContaining('UUID'), findsNothing);
    expect(find.textContaining('JSON'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('location editor keeps submit reachable by keyboard and scroll', (
    tester,
  ) async {
    final c = create();
    addTearDown(c.dispose);
    await c.initialize();
    await c.begin('location');
    c.update('code', 'LAB');
    c.update('name', 'Synthetic location');
    c.update('reason', 'Synthetic configuration');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AssetsEditor(controller: c)),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Discard editable draft'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Submit reviewed request').hitTestable(), findsOneWidget);
    bool submitFocused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilledButton>() !=
        null;
    for (var i = 0; i < 12 && !submitFocused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(submitFocused(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.text('Confirmed. The original request succeeded.'),
      findsOneWidget,
    );
    expect(find.text('Submit reviewed request'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      for (final editor in [false, true]) {
        testWidgets(
          'assets ${editor ? 'editor' : 'workspace'} ${dark ? 'dark' : 'light'} ${compact ? 'compact' : 'comfortable'} at 200 percent',
          (tester) async {
            final size = compact
                ? const Size(1024, 720)
                : const Size(1920, 1080);
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final c = create();
            addTearDown(c.dispose);
            await c.initialize();
            await c.select(c.records.single);
            if (editor) await c.begin('opening');
            final density = compact
                ? JentraDensity.compact
                : JentraDensity.comfortable;
            await tester.pumpWidget(
              MaterialApp(
                theme: dark
                    ? JentraTheme.dark(density: density)
                    : JentraTheme.light(density: density),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(2),
                  ),
                  child: Scaffold(
                    body: RepaintBoundary(
                      key: const ValueKey('asset-preview'),
                      child: ColoredBox(
                        color:
                            (dark
                                    ? JentraTheme.dark(density: density)
                                    : JentraTheme.light(density: density))
                                .scaffoldBackgroundColor,
                        child: editor
                            ? AssetsEditor(controller: c)
                            : AssetsWorkspace(controller: c),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(const ValueKey('asset-preview')),
              matchesGoldenFile(
                'goldens/assets_${editor ? 'editor' : 'workspace'}_${dark ? 'dark' : 'light'}_${compact ? 'compact' : 'comfortable'}_200.png',
              ),
            );
            if (editor) {
              await tester.scrollUntilVisible(
                find.text('Discard editable draft'),
                350,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(
                find.text('Submit reviewed request').hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }
  test('uncertain command survives controller restart with its original body and identity', () async {
    final c = create();
    await c.initialize();
    await c.begin('location');
    c.update('code', 'LAB');
    c.update('name', 'Synthetic location');
    c.update('reason', 'Synthetic configuration');
    repository.failure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'Synthetic lost response',
      retryable: true,
    );
    await c.send();
    final pending = c.pending!.envelope;
    expect(c.form!['name'], 'Synthetic location');
    c.update('name', 'Changed');
    expect(c.form!['name'], 'Synthetic location');
    c.dispose();
    final resumed = create();
    await resumed.initialize();
    expect(
      resumed.recovery.single.pending!.envelope.commandId,
      pending.commandId,
    );
    await resumed.resume(resumed.recovery.single);
    repository.failure = null;
    await resumed.send();
    expect(repository.commands.last.commandId, pending.commandId);
    expect(repository.commands.last.clientTimestamp, pending.clientTimestamp);
    expect(repository.commands.last.payload, pending.payload);
    expect(resumed.confirmed, isNotNull);
    resumed.dispose();
  });
  test(
    'confirmed writes stay confirmed if the optional register refresh fails',
    () async {
      final c = create();
      await c.initialize();
      await c.begin('location');
      c.update('code', 'LAB');
      c.update('name', 'Synthetic location');
      c.update('reason', 'Synthetic configuration');
      repository.failRefresh = true;
      await c.send();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNull);
      expect(c.message, contains('Confirmed'));
      expect(
        await c.drafts['location']!.load(scope, c.form!['id'] as String),
        isNull,
      );
      c.dispose();
    },
  );
  test(
    'late data cannot restore disposed or revoked controller state',
    () async {
      final c = create();
      repository.registerGate = Completer<void>();
      final work = c.initialize();
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      repository.registerGate!.complete();
      await work;
      expect(c.records, isEmpty);
      repository.registerGate = null;
      final revoked = create();
      await revoked.initialize();
      expect(revoked.records, isNotEmpty);
      repository.deny = true;
      await revoked.checkAccess();
      expect(revoked.records, isEmpty);
      expect(revoked.current, isFalse);
      revoked.dispose();
    },
  );
  test('read-only asset access does not expose write forms', () async {
    final c = create(permissions: {'assets.view'});
    await c.initialize();
    await c.begin('opening');
    expect(c.form, isNull);
    expect(repository.commands, isEmpty);
    c.dispose();
  });
  test('definite version conflict requires current comparison before another command', () async {
    final c = create();
    await c.initialize();
    await c.select(c.records.single);
    await c.begin('depreciate');
    c.update('reason', 'Synthetic asset action');
    repository.failure = const DomainError(
      code: 'VERSION_CONFLICT',
      message: 'Synthetic stale version',
    );
    await c.send();
    expect(c.conflict, isTrue);
    expect(c.pending, isNull);
    c.update('reason', 'Changed without comparison');
    expect(c.form!['reason'], 'Synthetic asset action');
    repository.version = 5;
    await c.compare();
    expect(c.comparison!.asset.version, 5);
    await c.adoptComparison();
    expect(c.expectedVersion, 5);
    expect(c.conflict, isFalse);
    expect(c.form!['book_id'], bookId);
    c.dispose();
  });
}
