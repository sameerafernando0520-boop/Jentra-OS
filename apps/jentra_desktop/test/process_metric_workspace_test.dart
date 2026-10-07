import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_desktop/src/features/analytics/process_metric_controller.dart';
import 'package:jentra_desktop/src/features/analytics/process_metric_screen.dart';

final wire = Map<String, Object?>.from(
  jsonDecode(
    File(
      '../../packages/jentra_platform/test/analytics/process_sql_snapshot.json',
    ).readAsStringSync(),
  ) as Map,
);
final source = Map<String, Object?>.from(wire['source'] as Map);
final scope = ProcessMetricScope(
  tenantId: source['tenantId'] as String,
  legalEntityId: source['legalEntityId'] as String,
  branchId: source['branchId'] as String,
);
final filter = ProcessMetricFilter.fromJson({
  for (final k in ['windowStart', 'windowEnd', 'asOf', 'recordedThrough'])
    k: source[k],
});

final class Repo implements ProcessMetricRepository {
  @override
  Future<void> authorizeRecovery(ProcessMetricScope s, String actor) =>
      authorize(s);
  Completer<ProcessMetricSnapshot>? delayed;
  bool denied = false;
  @override
  Future<void> authorize(ProcessMetricScope s) async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Source access changed.',
      );
    }
  }

  @override
  Future<ProcessMetricSnapshot> snapshot(
    ProcessMetricScope s,
    ProcessMetricFilter f,
  ) async =>
      delayed?.future ??
      ParsedProcessMetricSnapshot.fromJson(
        wire,
        expectedScope: s,
      ).verify(ProcessMetricSha256Hasher());
  @override
  Future<Map<String, Object?>> event(ProcessMetricScope s, String id) async {
    await authorize(s);
    return {'documentId': 'synthetic'};
  }
}

ProcessMetricController controller(Repo r) => ProcessMetricController(
  scope: scope,
  actorId: '10000000-0000-0000-0000-000000000001',
  repository: r,
  clock: () => DateTime.utc(2026, 10, 3),
);
void main() {
  test('filter replacement rejects late response', () async {
    final r = Repo()..delayed = Completer<ProcessMetricSnapshot>();
    final c = controller(r);
    final pending = c.read(filter);
    await Future<void>.delayed(Duration.zero);
    c.clear();
    r.delayed!.complete(
      await ParsedProcessMetricSnapshot.fromJson(
        wire,
        expectedScope: scope,
      ).verify(ProcessMetricSha256Hasher()),
    );
    await pending;
    expect(c.summary, isNull);
    expect(c.busy, false);
    c.dispose();
  });
  test('revocation and offline clear protected summaries and detail', () async {
    final r = Repo();
    final c = controller(r);
    await c.read(filter);
    expect(c.summary, isNotNull);
    r.denied = true;
    await c.openEvent(c.summary!.source.sourceEventIds.first);
    expect(c.summary, isNull);
    expect(c.detail, isNull);
    r.denied = false;
    await c.read(filter);
    c.setOnline(false);
    expect(c.summary, isNull);
    expect(c.filter, isNull);
    c.dispose();
  });
  test('disposing pending reader rejects all later evidence', () async {
    final r = Repo()..delayed = Completer<ProcessMetricSnapshot>();
    final c = controller(r);
    final pending = c.read(filter);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    r.delayed!.complete(
      await ParsedProcessMetricSnapshot.fromJson(
        wire,
        expectedScope: scope,
      ).verify(ProcessMetricSha256Hasher()),
    );
    await pending;
    expect(c.summary, isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('process workspace ${dark ? 'dark' : 'light'} at 200 percent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controller(Repo());
      await c.read(filter);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1024, 720),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: ProcessMetricWorkspace(controller: c)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.textContaining('P50:'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('P50: 0 microseconds'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
}
