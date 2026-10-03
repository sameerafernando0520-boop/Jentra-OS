import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/budgets/budget_screen.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_screen.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/financial_dimensions/financial_dimension_controller.dart';
import 'package:jentra_desktop/src/features/financial_dimensions/financial_dimension_screen.dart';
import 'package:jentra_desktop/src/features/budgets/budget_controller.dart';
import 'package:jentra_desktop/src/features/manual_journal/manual_journal_controller.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;
import 'budget_workspace_test.dart' show BudgetFake;
import 'manual_journal_workspace_test.dart' show JournalGateway, journal;

Map<String, Object?> dimension(
  TenantContext s, {
  String kind = 'cost_centre',
  String id = 'centre',
}) => {
  'id': id,
  'tenant_id': s.tenantId,
  'legal_entity_id': s.legalEntityId,
  'kind': kind,
  'code': 'CC-1',
  'name': 'Distribution and logistics',
  'status': 'active',
  'version': 1,
  'dimension_branch_id': null,
  'reason': 'Governed exact financial attribution',
};

class DimensionFake implements FinancialDimensionGateway {
  String? failure, readFailure;
  Completer<void>? pause, readPause;
  final entered = Completer<void>(), readEntered = Completer<void>();
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<Map<String, Object?>> page(
    TenantContext s,
    String kind, {
    String? after,
    String search = '',
    bool activeOnly = true,
  }) async {
    if (!readEntered.isCompleted) readEntered.complete();
    await readPause?.future;
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Access needs rechecking');
    }
    return {
      'items': [dimension(s, kind: kind)],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>> save(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (!entered.isCompleted) entered.complete();
    await pause?.future;
    if (failure != null) {
      throw DomainError(
        code: failure!,
        message: 'Saved result needs verification',
      );
    }
    return {
      ...c.payload,
      'tenant_id': c.context.tenantId,
      'legal_entity_id': c.context.legalEntityId,
      'branch_id': c.context.branchId,
      'version': (c.expectedEntityVersion ?? 0) + 1,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late DimensionFake gateway;
  late FinancialDimensionController c;
  bool disposed = false;
  FinancialDimensionController make({TenantContext context = scope}) =>
      FinancialDimensionController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
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
    disposed = false;
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = DimensionFake();
    c = make();
  });
  tearDown(() async {
    if (!disposed) c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    c.create();
    c.field('code', 'CC-NEW');
    c.field('name', 'Warehouse and distribution');
    c.field('reason', 'Approved master configuration');
  }

  test('navigation requires both current finance and management access', () {
    expect(
      visibleJentraDestinations({'finance.view'})
          .any((x) => x.path == '/finance/dimensions'),
      false,
    );
    expect(
      visibleJentraDestinations({'finance.view', 'finance.dimensions.manage'})
          .any((x) => x.path == '/finance/dimensions'),
      true,
    );
  });
  test('invalid inputs remain local and send no command', () async {
    await ready();
    c.field('code', 'bad code');
    await c.save();
    expect(gateway.commands, isEmpty);
    expect(c.error, isNotNull);
  });
  test(
    'uncertain dimension replays the identical encrypted command after restart',
    () async {
      await ready();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.save();
      final original = jsonEncode(gateway.commands.single.toJson((v) => v));
      expect(c.pending, true);
      c.dispose();
      c = make();
      await c.initialize();
      c.field('name', 'Forbidden change');
      gateway.failure = null;
      await c.save();
      expect(jsonEncode(gateway.commands.last.toJson((v) => v)), original);
      expect(c.pending, false);
      expect(c.version, 1);
    },
  );
  test('confirmation survives optional catalog read failure', () async {
    await ready();
    gateway.readFailure = 'UNCERTAIN_RESULT';
    await c.save();
    expect(c.version, 1);
    expect(c.pending, false);
    final saved = await drafts.load(scope, FinancialDimensionController.slot);
    expect(saved!.form['version'], 1);
    expect(saved.pending, isNull);
  });
  test(
    'scope or MFA denial clears evidence and blocks further changes',
    () async {
      await ready();
      gateway.readFailure = 'MFA_REQUIRED';
      await c.refresh();
      expect(c.items, isEmpty);
      expect(c.denied, true);
      expect(c.verified, false);
      await c.save();
      expect(gateway.commands, isEmpty);
      gateway.readFailure = null;
      await c.refresh();
      expect(c.verified, true);
      expect(c.denied, false);
    },
  );
  test('late catalog cannot reverify an earlier connection epoch', () async {
    gateway.readPause = Completer<void>();
    final pending = c.initialize();
    await gateway.readEntered.future;
    c.setOnline(false);
    c.setOnline(true);
    gateway.readPause!.complete();
    await pending;
    expect(c.verified, false);
    expect(c.items, isEmpty);
  });
  test(
    'confirmation after route disposal retains server identity for reopening',
    () async {
      await ready();
      gateway.pause = Completer<void>();
      final pending = c.save();
      await gateway.entered.future;
      c.dispose();
      disposed = true;
      gateway.pause!.complete();
      await pending;
      final saved = await drafts.load(scope, FinancialDimensionController.slot);
      expect(saved!.form['version'], 1);
      expect(saved.pending, isNull);
    },
  );
  test('confirmation during disconnect remains encrypted and requires fresh access', () async {
    await ready();
    gateway.pause = Completer<void>();
    final pending = c.save();
    await gateway.entered.future;
    c.setOnline(false);
    gateway.pause!.complete();
    await pending;
    expect(c.verified, false);
    expect(c.items, isEmpty);
    expect(
      (await drafts.load(scope, FinancialDimensionController.slot))!.pending,
      isNull,
    );
    c.setOnline(true);
    expect(c.verified, false);
    await c.refresh();
    expect(c.verified, true);
  });
  test(
    'failed encrypted confirmation retains the sealed request for exact retry',
    () async {
      await ready();
      gateway.pause = Completer<void>();
      final pending = c.save();
      await gateway.entered.future;
      await db.customStatement(
        "create trigger fail_dimension_confirmation before update on encrypted_drafts begin select raise(abort,'CONFIRMATION_WRITE_FAILURE'); end;",
      );
      gateway.pause!.complete();
      await pending;
      final original = gateway.commands.single;
      expect(
        (await drafts.load(scope, FinancialDimensionController.slot))!.pending,
        isNotNull,
      );
      await db.customStatement('drop trigger fail_dimension_confirmation');
      gateway.pause = null;
      await c.save();
      expect(gateway.commands.last.commandId, original.commandId);
      expect(c.pending, false);
    },
  );
  test('encrypted master draft cannot cross actor or branch', () async {
    await ready();
    await c.saveInputs();
    for (final other in [
      scope.copyWith(actorId: 'other'),
      scope.copyWith(branchId: 'other'),
    ]) {
      final otherController = make(context: other);
      await otherController.initialize();
      expect(otherController.form, isEmpty);
      otherController.dispose();
    }
  });
  test('existing master identity and branch cannot be edited', () async {
    await c.initialize();
    await c.open(dimension(scope));
    c.field('code', 'CHANGED');
    c.field('dimension_branch_id', 'b');
    c.field('name', 'Renamed distribution');
    expect(c.form['code'], 'CC-1');
    expect(c.form['dimension_branch_id'], isNull);
    await c.save();
    expect(gateway.commands.last.expectedEntityVersion, 1);
    expect(c.version, 2);
  });
  test(
    'journal chooses governed identities without changing exact money',
    () async {
      final j = ManualJournalController(
        scope: scope,
        gateway: JournalGateway(),
        drafts: drafts,
        permissions: {'finance.view', 'finance.journals.post'},
        online: true,
      );
      await j.initialize();
      j.form = journal();
      j.financialDimension(0, 'cost_centre', dimension(scope));
      final line = (j.form!['lines'] as List).first as Map;
      expect(line['cost_centre_id'], 'centre');
      expect(line['debit'], '123.456789');
      j.financialDimension(0, 'cost_centre', {
        ...dimension(scope),
        'legal_entity_id': 'other',
      });
      expect((j.form!['lines'] as List).first['cost_centre_id'], 'centre');
      j.dispose();
    },
  );
  test('budget accepts disjoint account plans and rejects wildcard overlap locally', () async {
    final b = BudgetController(
      scope: scope,
      gateway: BudgetFake(),
      drafts: drafts,
      permissions: {'finance.view', 'finance.budgets.manage'},
      online: true,
    );
    await b.initialize();
    await b.newBudget();
    b.field('reason', 'Dimension plan');
    b.addLine('account');
    b.financialDimension(0, 'cost_centre', dimension(scope, id: 'first'));
    b.addLine('account', allowDuplicate: true);
    b.financialDimension(1, 'cost_centre', dimension(scope, id: 'second'));
    b.amount(0, '9007199254.740993');
    b.amount(1, '0.000001');
    await b.act('create');
    expect((b.gateway as BudgetFake).commands.length, 1);
    await b.newBudget();
    b.field('reason', 'Overlapping plan');
    b.addLine('account');
    b.financialDimension(0, 'cost_centre', dimension(scope, id: 'first'));
    b.addLine('account', allowDuplicate: true);
    await b.act('create');
    expect((b.gateway as BudgetFake).commands.length, 1);
    expect(b.error, contains('overlap'));
    b.dispose();
  });

  testWidgets(
    'named picker rejects late choices and requires a fresh selector after reconnect',
    (tester) async {
      final connection = StreamController<ConnectivityState>.broadcast();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await connection.close();
      });
      Map<String, Object?>? chosen;
      gateway.readPause = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeTenantContextProvider.overrideWithValue(scope),
            businessCapabilitiesProvider.overrideWith(
              (ref) async => {'finance.view'},
            ),
            connectivityStateProvider.overrideWith((ref) async* {
              yield ConnectivityState.online;
              yield* connection.stream;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: FinancialDimensionButton(
                scope: scope,
                gateway: gateway,
                kind: 'cost_centre',
                label: 'Pick centre',
                enabled: true,
                onSelected: (row) => chosen = row,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FinancialDimensionButton)),
        listen: false,
      );
      final networkSubscription = container
          .listen<AsyncValue<ConnectivityState>>(
            connectivityStateProvider,
            (_, next) {},
          );
      final capabilitySubscription = container.listen<AsyncValue<Set<String>>>(
        businessCapabilitiesProvider,
        (_, next) {},
      );
      addTearDown(() {
        networkSubscription.close();
        capabilitySubscription.close();
      });
      await tester.runAsync(() async {
        await container.read(businessCapabilitiesProvider.future);
        await container.read(connectivityStateProvider.future);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick centre'));
      for (
        var attempt = 0;
        attempt < 10 && !gateway.readEntered.isCompleted;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(gateway.readEntered.isCompleted, true);
      connection.add(ConnectivityState.offline);
      await tester.pump();
      gateway.readPause!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(find.text('CC-1 · Distribution and logistics'), findsNothing);
      expect(chosen, isNull);
      gateway.readPause = null;
      connection.add(ConnectivityState.online);
      await tester.pumpAndSettle();
      expect(find.text('CC-1 · Distribution and logistics'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick centre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CC-1 · Distribution and logistics'));
      await tester.pumpAndSettle();
      expect(chosen!['id'], 'centre');
      networkSubscription.close();
      capabilitySubscription.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'named picker can clear a governed selection without inventing an identity',
    (tester) async {
      var called = false;
      Map<String, Object?>? chosen;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeTenantContextProvider.overrideWithValue(scope),
            businessCapabilitiesProvider.overrideWith(
              (ref) async => {'finance.view'},
            ),
            connectivityStateProvider.overrideWith(
              (ref) => Stream.value(ConnectivityState.online),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: FinancialDimensionButton(
                scope: scope,
                gateway: gateway,
                kind: 'project',
                label: 'Pick project',
                enabled: true,
                onSelected: (row) {
                  called = true;
                  chosen = row;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FinancialDimensionButton)),
        listen: false,
      );
      final networkSubscription = container
          .listen<AsyncValue<ConnectivityState>>(
            connectivityStateProvider,
            (_, next) {},
          );
      final capabilitySubscription = container.listen<AsyncValue<Set<String>>>(
        businessCapabilitiesProvider,
        (_, next) {},
      );
      addTearDown(() {
        networkSubscription.close();
        capabilitySubscription.close();
      });
      await tester.runAsync(() async {
        await container.read(businessCapabilitiesProvider.future);
        await container.read(connectivityStateProvider.future);
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick project'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear dimension'));
      await tester.pumpAndSettle();
      expect(called, true);
      expect(chosen, isNull);
      networkSubscription.close();
      capabilitySubscription.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('governed budget ${brightness.name} 200 percent exact amount', (
      tester,
    ) async {
      final b = BudgetController(
        scope: scope,
        gateway: BudgetFake(),
        drafts: drafts,
        permissions: {'finance.view', 'finance.budgets.manage'},
        online: true,
      );
      addTearDown(b.dispose);
      await b.initialize();
      await b.newBudget();
      // Keep the approved visual fixture stable across UTC date changes.
      b.field('budget_year', 2026);
      b.varianceField('as_of', '2026-09-26');
      b.addLine('account');
      b.financialDimension(0, 'cost_centre', dimension(scope));
      b.amount(0, '9007199254.740993');
      tester.view.physicalSize = const Size(1024, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          darkTheme: JentraTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: BudgetWorkspace(controller: b, financialDimensions: gateway),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/budget_dimensions_${brightness.name}_200.png',
        ),
      );
    });
    testWidgets('governed journal ${brightness.name} 200 percent labels', (
      tester,
    ) async {
      final j = ManualJournalController(
        scope: scope,
        gateway: JournalGateway(),
        drafts: drafts,
        permissions: {'finance.view', 'finance.journals.post'},
        online: true,
      );
      addTearDown(j.dispose);
      await j.initialize();
      j.form = journal();
      j.financialDimension(0, 'cost_centre', dimension(scope));
      tester.view.physicalSize = const Size(1024, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          darkTheme: JentraTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ManualJournalWorkspace(
              controller: j,
              financialDimensions: gateway,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/journal_dimensions_${brightness.name}_200.png',
        ),
      );
    });
  }
  for (final brightness in Brightness.values) {
    testWidgets('dimension catalog ${brightness.name} 200 percent text', (
      tester,
    ) async {
      await c.initialize();
      await c.open(dimension(scope));
      tester.view.physicalSize = const Size(1024, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          darkTheme: JentraTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: FinancialDimensionWorkspace(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/financial_dimensions_${brightness.name}_200.png',
        ),
      );
    });
  }
}
