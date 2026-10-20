import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_metrics_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_metrics_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';

String uid(int n) => '95000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

String day(DateTime d) => d.toIso8601String().substring(0, 10);

Map<String, Object?> spread(double? p50, double? p90, int n) => {
  'p50': p50,
  'p90': p90,
  'samples': n,
};
Map<String, Object?> rate(double? v, int n) => {'value': v, 'samples': n};

class FakeMetricsGateway implements AssuranceMetricsGateway {
  final calls = <(DateTime, DateTime)>[];
  String? failure;
  int engagements = 3;
  bool workload = true;
  Completer<void>? hold;

  @override
  Future<AssuranceMetrics> metrics(
    TenantContext s,
    DateTime from,
    DateTime to,
  ) async {
    calls.add((from, to));
    final wait = hold;
    if (wait != null) await wait.future;
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Refused: $failure');
    }
    return AssuranceMetrics.fromJson({
      'from': day(from),
      'to': day(to),
      'engagements': engagements,
      'metrics': {
        'stage_planning_days': spread(2, 4, 3),
        'stage_fieldwork_days': spread(null, null, 0),
        'stage_reporting_days': spread(2.5, 3, 2),
        'report_issuance_days': spread(1, 1.5, 2),
        'evidence_waiting_days': spread(2, 6, 5),
        'evidence_review_days': spread(1, 2, 4),
        'evidence_first_time_right': rate(0.75, 4),
        'request_ageing': {'d0_7': 2, 'd8_30': 1, 'd31_plus': 1, 'samples': 4},
        'test_completion': rate(0.5, 6),
        'control_coverage': rate(0.4, 5),
        'retest_pass_rate': rate(null, 0),
        'recurrence': rate(0.25, 4),
        'finding_ageing_days': {
          'low': rate(null, 0),
          'medium': rate(12, 1),
          'high': rate(10, 1),
          'critical': rate(6, 1),
        },
        'overdue_remediation': {'value': 1},
        'open_high_risk_findings': {'value': 2},
        'workload': workload
            ? [
                {
                  'label': 'Nadeesha Perera',
                  'open_requests': 3,
                  'open_findings': 1,
                },
                {
                  'label': 'Unlinked member ····0042',
                  'open_requests': 1,
                  'open_findings': 0,
                },
              ]
            : <Object?>[],
      },
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = TenantContext(
    tenantId: uid(90),
    actorId: uid(1),
    legalEntityId: uid(91),
    branchId: uid(92),
  );
  late FakeMetricsGateway gateway;
  late AssuranceMetricsController c;
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(JentraTypography.monoFamily)
          ..addFont(rootBundle.load('${base}IBMPlexMono-Regular.ttf'))
          ..addFont(rootBundle.load('${base}IBMPlexMono-SemiBold.ttf')))
        .load();
  });
  setUp(() {
    gateway = FakeMetricsGateway();
    c = AssuranceMetricsController(
      scope: scope,
      gateway: gateway,
      online: true,
      clock: () => DateTime(2026, 10, 20, 10),
    );
  });
  tearDown(() => c.dispose());

  test('navigation shows audit metrics to evidence viewers', () {
    bool shown(Set<String> caps) =>
        visibleJentraDestinations(caps)
            .any((d) => d.path == '/governance/audit/metrics');
    expect(shown({'assurance.plan.manage'}), isFalse);
    expect(shown({'assurance.evidence.view'}), isTrue);
  });

  test('the default period is the last 90 days, today included', () async {
    await c.load();
    expect(c.period, MetricsPeriod.quarter);
    expect(gateway.calls.single, (
      DateTime.utc(2026, 7, 23),
      DateTime.utc(2026, 10, 20),
    ));
    expect(c.metrics!.engagements, 3);
  });

  test('changing the period reloads with its dates', () async {
    await c.load();
    await c.choose(MetricsPeriod.month);
    expect(gateway.calls.last, (
      DateTime.utc(2026, 9, 21),
      DateTime.utc(2026, 10, 20),
    ));
    await c.choose(MetricsPeriod.year);
    expect(gateway.calls.last, (
      DateTime.utc(2025, 10, 21),
      DateTime.utc(2026, 10, 20),
    ));
    expect(c.metrics!.from, DateTime.utc(2025, 10, 21));
  });

  test('a slower answer for an earlier period is discarded', () async {
    final hold = gateway.hold = Completer();
    final first = c.load();
    gateway.hold = null;
    await c.choose(MetricsPeriod.month);
    expect(c.metrics!.from, DateTime.utc(2026, 9, 21));
    hold.complete();
    await first;
    expect(c.metrics!.from, DateTime.utc(2026, 9, 21));
    expect(c.busy, isFalse);
  });

  test('losing access clears the metrics', () async {
    await c.load();
    gateway.failure = 'PERMISSION_DENIED';
    await c.load();
    expect(c.accessDenied, isTrue);
    expect(c.metrics, isNull);
  });

  test('offline clears the metrics and reconnecting reloads', () async {
    await c.load();
    c.setOnline(false);
    expect(c.metrics, isNull);
    c.setOnline(true);
    await pumpEventQueue();
    expect(gateway.calls, hasLength(2));
    expect(c.metrics, isNotNull);
  });

  Future<void> render(WidgetTester t, {bool dark = false}) async {
    t.view.physicalSize = const Size(1024, 4200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: AssuranceMetricsView(controller: c)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('values, units and unmeasured metrics are shown', (t) async {
    await c.load();
    await render(t);
    expect(find.text('2 days'), findsWidgets);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('Not measured'), findsNWidgets(2));
    expect(find.text('1 over 30 days'), findsOneWidget);
    expect(find.text('No samples in this period'), findsNWidgets(2));
    expect(find.text('Nadeesha Perera'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('23 Jul 2026'), findsOneWidget);
  });

  testWidgets('a period with no engagements says so', (t) async {
    gateway.engagements = 0;
    gateway.workload = false;
    await c.load();
    await render(t);
    expect(find.text('No engagements in this period'), findsOneWidget);
    expect(find.text('Not measured'), findsNothing);
  });

  testWidgets('keyboard focus reaches every period choice', (t) async {
    await c.load();
    await render(t);
    final reached = <String>{};
    for (var i = 0; i < 12; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) continue;
      for (final p in MetricsPeriod.values) {
        if (find
            .ancestor(
              of: find.byWidget(focused.widget),
              matching: find.widgetWithText(ChoiceChip, p.label),
            )
            .evaluate()
            .isNotEmpty) {
          reached.add(p.label);
        }
      }
    }
    expect(reached, MetricsPeriod.values.map((p) => p.label).toSet());
  });

  for (final dark in [false, true]) {
    testWidgets('audit metrics ${dark ? 'dark' : 'light'} 200 percent', (
      t,
    ) async {
      await c.load();
      await render(t, dark: dark);
      await expectLater(
        find.byType(AssuranceMetricsView),
        matchesGoldenFile(
          'goldens/audit_metrics_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
}
