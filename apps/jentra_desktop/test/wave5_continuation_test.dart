import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/analytics/cash_scenario_screen.dart';
import 'package:jentra_desktop/src/features/analytics/cash_payment_dates_section.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/analytics/integration_screen.dart';
import 'package:jentra_desktop/src/features/analytics/financial_analytics_screen.dart';
import 'package:jentra_desktop/src/features/analytics/historical_pipeline_screen.dart';
import 'package:jentra_desktop/src/features/analytics/governed_export_screen.dart';

String id(int n) => '30000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final scope = ProcessMetricScope(
  tenantId: id(1),
  legalEntityId: id(2),
  branchId: id(3),
);

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Future<Map<String, Object?>> cashWire(
  String start,
  String end,
  String through, {
  bool full = false,
}) async {
  final text = jsonEncode({
    'contractRevision': full ? 3 : 2,
    'definition': full
        ? 'dated_transaction_cash_all_obligations.v3'
        : 'dated_transaction_cash_ar_and_ap.v2',
    'scope': {
      'tenantId': scope.tenantId,
      'legalEntityId': scope.legalEntityId,
      'branchId': scope.branchId,
    },
    'horizonStart': start,
    'horizonEnd': end,
    'recordedThrough': through,
    'completeProviders': [
      'bank_cash',
      'receivables',
      'payables',
      if (full) 'payroll',
      if (full) 'project_reimbursements',
    ],
    'providerStatus': {
      'bank_cash': 'available',
      'receivables': 'available',
      'payables': 'available',
      'payroll': full ? 'available' : 'missing_authoritative_due_date',
      'project_reimbursements': full
          ? 'available'
          : 'missing_authoritative_due_date',
    },
    'controls': [
      {
        'id': id(4),
        'accountId': id(5),
        'branchId': id(3),
        'currency': 'LKR',
        'version': '1',
        'amount': '10.000001',
      },
    ],
    'obligations': [
      {
        'id': id(6),
        'branchId': id(3),
        'currency': 'LKR',
        'dueDate': start,
        'version': '1',
        'amount': '5.000001',
        'provider': 'receivables',
        if (full) 'inflow': true,
      },
      {
        'id': id(7),
        'branchId': id(3),
        'currency': 'LKR',
        'dueDate': start,
        'version': '1',
        'amount': '2.000000',
        'provider': 'payables',
        if (full) 'inflow': false,
      },
      if (full) ...[
        {
          'id': id(30),
          'branchId': id(3),
          'currency': 'LKR',
          'dueDate': start,
          'version': '2',
          'amount': '7.000001',
          'provider': 'payroll',
          'inflow': false,
        },
        {
          'id': id(31),
          'branchId': id(3),
          'currency': 'LKR',
          'dueDate': start,
          'version': '1',
          'amount': '2.000002',
          'provider': 'payroll',
          'inflow': true,
        },
        {
          'id': id(32),
          'branchId': id(3),
          'currency': 'LKR',
          'dueDate': start,
          'version': '1',
          'amount': '4.000000',
          'provider': 'project_reimbursements',
          'inflow': false,
        },
      ],
    ],
    'sources': [],
    'exclusions': full
        ? ['overdue_before_horizon', 'unallocated_credits']
        : ['payroll', 'project_reimbursements'],
  });
  return {
    'canonicalText': text,
    'sourceHash': await ProcessMetricSha256Hasher().sha256(utf8.encode(text)),
  };
}

EncryptedDraftRepository drafts(JentraLocalDatabase db) =>
    EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const root = 'packages/jentra_design_system/assets/fonts';
    final sans = FontLoader(JentraTypography.sansFamily)
      ..addFont(rootBundle.load('$root/Manrope-Regular.ttf'))
      ..addFont(rootBundle.load('$root/Manrope-Medium.ttf'))
      ..addFont(rootBundle.load('$root/Manrope-SemiBold.ttf'))
      ..addFont(rootBundle.load('$root/Manrope-Bold.ttf'));
    final mono = FontLoader(JentraTypography.monoFamily)
      ..addFont(rootBundle.load('$root/IBMPlexMono-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([sans.load(), mono.load(), icons.load()]);
  });
  testWidgets(
    'integration selection captures its original revision and switching actor clears scoped fields',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Future<void> authorize(ProcessMetricScope s, String actor) async {}
      IntegrationController controller(String actor) => IntegrationController(
        scope,
        actor,
        (_, _) async => null,
        Wave5CommandStore(drafts(db), authorize, namespace: 'integration'),
        authorize,
      );
      final first = controller(id(7)), second = controller(id(77));
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final listing = integrationListProvider.overrideWith(
        (ref, cursors) async => {
          'contractRevision': 1,
          'subscriptionNext': null,
          'deliveryNext': null,
          'subscriptions': [
            {
              'id': id(8),
              'url': 'https://events.jentra.test/hook',
              'version': '5',
              'keyVersion': 2,
              'enabled': true,
            },
          ],
          'deliveries': [],
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            integrationControllerProvider.overrideWithValue(first),
            listing,
          ],
          child: MaterialApp(
            theme: JentraTheme.light(),
            home: const Scaffold(body: IntegrationScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selected = find.text('https://events.jentra.test/hook');
      await tester.scrollUntilVisible(
        selected,
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(selected);
      await tester.pump();
      TextField field(String label) => tester.widget<TextField>(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        ),
      );
      expect(
        field('Subscription ID for rotation/revocation').controller!.text,
        id(8),
      );
      expect(field('Expected subscription revision').controller!.text, '5');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(IntegrationScreen)),
      );
      container.updateOverrides([
        integrationControllerProvider.overrideWithValue(second),
        listing,
      ]);
      await tester.pumpAndSettle();
      expect(field('Reviewed HTTPS destination').controller!.text, isEmpty);
      expect(
        field('Subscription ID for rotation/revocation').controller!.text,
        isEmpty,
      );
      expect(field('Expected subscription revision').controller!.text, '0');
      expect(tester.takeException(), isNull);
    },
  );
  test('native cash restart retains the original uncertain scenario identity and source cutoff', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final saved = drafts(db), requests = <Map<String, Object?>>[];
    var unknown = true;
    final gateway = DatedCashGateway((name, p) async {
      if (name == 'wave5_cash_authorize') return id(7);
      if (name == 'wave5_cash_basis') {
        return cashWire(
          p['p_start'] as String,
          p['p_end'] as String,
          p['p_recorded_through'] as String,
        );
      }
      requests.add(Map.of(p));
      if (unknown) throw StateError('unknown');
      return {
        'id': p['p_id'],
        'sourceHash': p['p_source_hash'],
        'version': '1',
      };
    });
    CashScenarioController create() => CashScenarioController(
      scope,
      id(7),
      gateway,
      CashScenarioStore(saved, gateway.authorize),
    );
    final first = create();
    await first.read('2026-10-08', '2026-10-10');
    await first.freeze();
    expect(requests.length, 1);
    expect(first.error, isNotNull);
    first.dispose();
    final second = create();
    await second.read('2026-10-09', '2026-10-11');
    await second.freeze();
    expect(requests.length, 1);
    expect(second.revision!.id, requests.single['p_id']);
    unknown = false;
    await second.freeze();
    expect(requests[1], requests.first);
    expect(second.savedId, requests.first['p_id']);
    second.dispose();
  });
  test('late dated cash completion cannot restore evidence after connectivity revocation', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final response = Completer<Object?>(), entered = Completer<void>();
    final gateway = DatedCashGateway((name, p) async {
      if (name == 'wave5_cash_authorize') return id(7);
      entered.complete();
      return response.future;
    });
    final c = CashScenarioController(
      scope,
      id(7),
      gateway,
      CashScenarioStore(drafts(db), gateway.authorize),
    );
    final work = c.read('2026-10-08', '2026-10-10');
    await entered.future;
    c.setOnline(false);
    // The old response has a different cutoff as well; neither path may publish.
    response.complete(
      await cashWire('2026-10-08', '2026-10-10', '2026-10-08T00:00:00Z'),
    );
    await work;
    expect(c.basis, isNull);
    expect(c.revision, isNull);
    expect(c.busy, isFalse);
    c.dispose();
  });
  test('payment-date native restart preserves original uncertain approval identity and immutable digest', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final saved = drafts(db), calls = <Map<String, Object?>>[];
    var unknown = true, denied = false;
    final gateway = CashPaymentDatesGateway((name, p) async {
      if (denied) throw StateError('revoked');
      if (name == 'wave5_cash_date_authorize') return id(7);
      if (name == 'wave5_cash_date_get') {
        return {
          'id': id(33),
          'sourceKind': 'payroll_obligation',
          'sourceId': id(30),
          'sourceHash': 'a' * 64,
          'dueDate': '2026-10-09',
          'reasonCode': 'payroll_calendar',
          'proposalHash': 'b' * 64,
          'expectedVersion': '1',
          'preparedBy': id(8),
          'preparedAt': '2026-10-08T00:00:00Z',
          'decision': null,
        };
      }
      calls.add(Map.of(p));
      if (unknown) throw StateError('response uncertain');
      return {
        'entity': {
          'id': id(33),
          'version': '2',
          'status': 'approved',
          'proposalHash': 'b' * 64,
        },
      };
    });
    CashPaymentDatesController create() => CashPaymentDatesController(
      scope,
      id(7),
      'payroll_obligation',
      gateway,
      Wave5CommandStore(
        saved,
        (s, a) => gateway.authorize(s, a, 'payroll_obligation'),
        namespace: 'cash_dates_payroll_obligation',
      ),
    );
    final first = create();
    await first.inspect(id(33));
    await first.decide(true);
    expect(calls.length, 1);
    expect(first.error, isNotNull);
    first.dispose();
    final second = create();
    await second.restore();
    expect(second.pending, isNotNull);
    await second.inspect(id(33));
    await second.decide(false);
    expect(calls.length, 1);
    expect(second.pending!['action'], 'approve');
    unknown = false;
    await second.retry();
    expect(calls[1], calls.first);
    expect(second.receipt!['version'], '2');
    second.setOnline(false);
    expect(second.receipt, isNull);
    denied = true;
    second.setOnline(true);
    await second.restore();
    expect(second.pending, isNull);
    second.dispose();
  });
  test('late payment-date private response is discarded after scope connectivity revocation', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final response = Completer<Object?>(), entered = Completer<void>();
    final gateway = CashPaymentDatesGateway((name, p) async {
      if (name == 'wave5_cash_date_authorize') return id(7);
      entered.complete();
      return response.future;
    });
    final c = CashPaymentDatesController(
      scope,
      id(7),
      'payroll_obligation',
      gateway,
      Wave5CommandStore(
        drafts(db),
        (s, a) => gateway.authorize(s, a, 'payroll_obligation'),
        namespace: 'cash_dates_payroll_obligation',
      ),
    );
    final work = c.inspect(id(33));
    await entered.future;
    c.setOnline(false);
    response.complete({
      'id': id(33),
      'sourceKind': 'payroll_obligation',
      'sourceId': id(30),
      'sourceHash': 'a' * 64,
      'dueDate': '2026-10-09',
      'reasonCode': 'payroll_calendar',
      'proposalHash': 'b' * 64,
      'expectedVersion': '1',
      'preparedBy': id(8),
      'preparedAt': '2026-10-08T00:00:00Z',
      'decision': null,
    });
    await work;
    expect(c.proposal, isNull);
    expect(c.pending, isNull);
    expect(c.busy, false);
    c.dispose();
  });
  test('integration native restart retries the exact encrypted request and clears results on revocation', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final saved = drafts(db), calls = <Map<String, Object?>>[];
    var denied = false, unknown = true;
    Future<void> auth(ProcessMetricScope s, String a) async {
      if (denied) throw StateError('revoked');
    }

    Future<Object?> rpc(String name, Map<String, Object?> p) async {
      calls.add(Map.of(p));
      if (unknown) throw StateError('unknown');
      return <String, Object?>{'id': p['p_id'], 'version': '1'};
    }

    IntegrationController create() => IntegrationController(
      scope,
      id(7),
      rpc,
      Wave5CommandStore(saved, auth, namespace: 'integration'),
      auth,
    );
    final first = create();
    await first.submit('register', {
      'id': id(8),
      'url': 'https://events.jentra.test/hook',
      'keyRef': 'synthetic/reviewed',
      'expectedVersion': '0',
    });
    final original = Map.of(first.pending!);
    first.dispose();
    final second = create();
    await second.submit('register', {
      'id': id(10),
      'url': 'https://events.jentra.test/new',
      'keyRef': 'synthetic/new',
      'expectedVersion': '0',
    });
    expect(calls.length, 1);
    expect(second.pending, original);
    unknown = false;
    await second.retry();
    expect(calls.length, 2);
    expect(calls[1], calls.first);
    expect(second.receipt, isNotNull);
    second.setOnline(false);
    expect(second.receipt, isNull);
    denied = true;
    second.setOnline(true);
    await second.restore();
    expect(second.pending, isNull);
    second.dispose();
  });
  for (final width in [1024.0, 1440.0, 1920.0]) {
    for (final dark in [false, true]) {
      for (final density in JentraDensity.values) {
        for (final workspace in [
          'cash',
          'integrations',
          'financial',
          'historical',
          'exports',
        ]) {
          if (width == 1920 && workspace != 'cash') continue;
          final height = workspace == 'cash'
              ? switch (width) {
                  1024 => 720.0,
                  1920 => 1080.0,
                  _ => 900.0,
                }
              : 900.0;
          testWidgets(
            '$workspace fresh render $width ${dark ? 'dark' : 'light'} ${density.name} at 200% and keyboard focus',
            (tester) async {
              await tester.binding.setSurfaceSize(Size(width, height));
              addTearDown(() => tester.binding.setSurfaceSize(null));
              final db = JentraLocalDatabase(NativeDatabase.memory());
              addTearDown(db.close);
              final gateway = DatedCashGateway(
                (name, p) async => name == 'wave5_cash_authorize'
                    ? id(7)
                    : cashWire(
                        p['p_start'] as String,
                        p['p_end'] as String,
                        p['p_recorded_through'] as String,
                        full: true,
                      ),
              );
              final c = CashScenarioController(
                scope,
                id(7),
                gateway,
                CashScenarioStore(drafts(db), gateway.authorize),
              );
              await c.read('2026-10-08', '2026-10-10');
              final dateGateway = CashPaymentDatesGateway((name, params) async {
                if (name == 'wave5_cash_date_authorize') return id(7);
                if (name == 'wave5_cash_date_sources') {
                  return {
                    'rows': [
                      {
                        'sourceKind': 'payroll_obligation',
                        'sourceId': id(30),
                        'sourceHash': 'a' * 64,
                        'branchId': id(3),
                        'currency': 'LKR',
                        'originalAmount': '10.000001',
                        'remainingAmount': '7.000001',
                        'inflow': false,
                        'issueDate': '2026-10-01',
                        'approved': null,
                      },
                    ],
                    'next': null,
                  };
                }
                return {
                  'id': id(33),
                  'sourceKind': 'payroll_obligation',
                  'sourceId': id(30),
                  'sourceHash': 'a' * 64,
                  'dueDate': '2026-10-09',
                  'reasonCode': 'payroll_calendar',
                  'proposalHash': 'b' * 64,
                  'expectedVersion': '1',
                  'preparedBy': id(8),
                  'preparedAt': '2026-10-08T00:00:00Z',
                  'decision': null,
                };
              });
              final dc = CashPaymentDatesController(
                scope,
                id(7),
                'payroll_obligation',
                dateGateway,
                Wave5CommandStore(
                  drafts(db),
                  (s, a) => dateGateway.authorize(s, a, 'payroll_obligation'),
                  namespace: 'cash_dates_payroll_obligation',
                ),
              );
              await dc.read();
              await dc.inspect(id(33));
              Future<void> auth(ProcessMetricScope s, String a) async {}
              final ic = IntegrationController(
                scope,
                id(7),
                (_, _) async => null,
                Wave5CommandStore(drafts(db), auth, namespace: 'integration'),
                auth,
              );
              final key = GlobalKey();
              final screen = switch (workspace) {
                'cash' => const CashScenarioScreen(),
                'integrations' => const IntegrationScreen(),
                'financial' => const FinancialAnalyticsScreen(),
                'historical' => const HistoricalPipelineScreen(),
                _ => const GovernedExportScreen(),
              };
              await tester.pumpWidget(
                ProviderScope(
                  overrides: [
                    cashScenarioControllerProvider.overrideWithValue(c),
                    cashPaymentDatesControllerProvider('payroll_obligation')
                        .overrideWithValue(dc),
                    businessCapabilitiesProvider.overrideWith(
                      (ref) async => {
                        'analytics.cash_dates.prepare',
                        'analytics.cash_dates.approve',
                      },
                    ),
                    integrationControllerProvider.overrideWithValue(ic),
                    integrationListProvider.overrideWith(
                      (ref, cursors) async => {
                        'contractRevision': 1,
                        'subscriptionNext': null,
                        'deliveryNext': null,
                        'subscriptions': [
                          {
                            'id': id(8),
                            'url': 'https://events.jentra.test/hook',
                            'version': '1',
                            'keyVersion': 1,
                            'enabled': true,
                          },
                        ],
                        'deliveries': [
                          {
                            'id': id(9),
                            'state': 'unknown',
                            'attempt': 1,
                            'generation': 0,
                          },
                        ],
                      },
                    ),
                  ],
                  child: MaterialApp(
                    theme: dark
                        ? JentraTheme.dark(density: density)
                        : JentraTheme.light(density: density),
                    home: MediaQuery(
                      data: MediaQueryData(
                        size: Size(width, height),
                        textScaler: const TextScaler.linear(2),
                      ),
                      child: RepaintBoundary(
                        key: key,
                        child: Scaffold(body: screen),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pump();
              expect(
                tester
                    .widgetList<EditableText>(find.byType(EditableText))
                    .any((field) => field.focusNode.hasFocus),
                isTrue,
              );
              final frames = Platform.environment['W5_CONTINUATION_FRAME_DIR'];
              final cashFrames = Platform.environment['W5_CASH_FRAME_DIR'];
              Future<void> capture(String location) async {
                final cashCapture = workspace == 'cash' && cashFrames != null;
                if (!cashCapture &&
                    (frames == null ||
                        width != 1440 ||
                        density != JentraDensity.comfortable)) {
                  return;
                }
                final directory = cashCapture ? cashFrames : frames!;
                final name = cashCapture
                    ? 'cash-${width.toInt()}-${height.toInt()}-${dark ? 'dark' : 'light'}-${density.name}-$location'
                    : '$workspace-${dark ? 'dark' : 'light'}-$location';
                await tester.runAsync(() async {
                  final im =
                      await (key.currentContext!.findRenderObject()
                              as RenderRepaintBoundary)
                          .toImage();
                  final bytes = await im.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  im.dispose();
                  await Directory(directory).create(recursive: true);
                  await File('$directory/$name.png')
                      .writeAsBytes(bytes!.buffer.asUint8List());
                });
              }

              await capture('top');
              if (workspace == 'cash') {
                final providerStatus = find.textContaining('Provider status');
                await tester.scrollUntilVisible(
                  providerStatus,
                  300,
                  scrollable: find
                      .descendant(
                        of: find.byType(ListView).first,
                        matching: find.byType(Scrollable),
                      )
                      .first,
                );
                await tester.pumpAndSettle();
                expect(
                  find.textContaining('payables: available'),
                  findsOneWidget,
                );
                expect(
                  find.textContaining('payroll: available'),
                  findsOneWidget,
                );
                expect(tester.takeException(), isNull);
                await capture('providers');
              }
              await tester.drag(
                find.byType(ListView).first,
                const Offset(0, -1800),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              if (workspace == 'cash') {
                // The displayed closing balance must include the exact AP outflow.
                expect(
                  find.text('2026-10-09 · LKR · 4.000003'),
                  findsOneWidget,
                );
              }
              await capture('lower');
              if (workspace == 'cash') {
                await tester.ensureVisible(
                  find.text('Authoritative payment dates'),
                );
                await tester.tap(find.text('Authoritative payment dates'));
                await tester.pumpAndSettle();
                await tester.ensureVisible(
                  find.text('Read issued obligations'),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                await capture('dates');
                await tester.ensureVisible(
                  find.text('Approve exact payment date'),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                await capture('approval');
              }
              await tester.pumpWidget(const SizedBox());
              c.dispose();
              dc.dispose();
              ic.dispose();
            },
          );
        }
      }
    }
  }
}
