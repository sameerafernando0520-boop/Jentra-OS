import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final wire = Map<String, Object?>.from(
    jsonDecode(
          File('test/analytics/process_sql_snapshot.json').readAsStringSync(),
        )
        as Map,
  );
  final source = Map<String, Object?>.from(wire['source'] as Map);
  final scope = ProcessMetricScope(
    tenantId: source['tenantId'] as String,
    legalEntityId: source['legalEntityId'] as String,
    branchId: source['branchId'] as String,
  );
  final filter = ProcessMetricFilter(
    windowStart: source['windowStart'] as String,
    windowEnd: source['windowEnd'] as String,
    asOf: source['asOf'] as String,
    recordedThrough: source['recordedThrough'] as String,
  );
  test(
    'actual SQL wire verifies against independent Dart canonical SHA256 and exact summary',
    () async {
      final gateway = SupabaseProcessMetricGateway.injected((name, p) async {
        expect(name, 'analytics_process_snapshot');
        expect(p['p_tenant_id'], scope.tenantId);
        return wire;
      });
      final snapshot = await gateway.snapshot(scope, filter);
      final summary = snapshot.summarize(generatedAt: '2026-10-03T00:00:00Z');
      expect(summary.completedCount, 2);
      expect(summary.openCount, 1);
      expect(summary.p50Microseconds, BigInt.zero);
      expect(summary.p90Microseconds, BigInt.one);
      expect(
        summary.unsupportedMeasures['stage_dwell'],
        'UNCERTIFIED_PROCESS_SEMANTICS',
      );
    },
  );
  test('changed observations cannot pass digest verification', () async {
    final changed = jsonDecode(jsonEncode(wire)) as Map<String, dynamic>;
    (changed['observations'] as List).first['waitMinutes'] = '1.000000';
    final gateway = SupabaseProcessMetricGateway.injected(
      (n, p) async => changed,
    );
    await expectLater(
      gateway.snapshot(scope, filter),
      throwsA(isA<DomainError>()),
    );
  });
  test('different valid cutoff response rejected before calculation', () async {
    final other = ProcessMetricFilter(
      windowStart: '2026-09-02T00:00:00Z',
      windowEnd: '2026-10-01T00:00:00Z',
      asOf: '2026-10-01T00:00:00Z',
      recordedThrough: '2026-10-02T00:00:00Z',
    );
    final gateway = SupabaseProcessMetricGateway.injected((n, p) async => wire);
    await expectLater(
      gateway.snapshot(scope, other),
      throwsA(isA<DomainError>()),
    );
  });
  test(
    'server diagnostics are sanitized and missing RPC is unavailable',
    () async {
      for (final code in ['42501', 'PGRST202']) {
        final gateway = SupabaseProcessMetricGateway.injected(
          (n, p) async => throw PostgrestException(
            message: 'PRIVATE diagnostic',
            code: code,
          ),
        );
        try {
          await gateway.authorize(scope);
          fail('expected denial');
        } on DomainError catch (e) {
          expect(e.message, isNot(contains('PRIVATE')));
          expect(
            e.code,
            code == '42501' ? 'PERMISSION_DENIED' : 'PROVIDER_UNAVAILABLE',
          );
        }
      }
    },
  );
  test('detail rejects injected private fields and foreign event', () async {
    final gateway = SupabaseProcessMetricGateway.injected(
      (n, p) async => {
        'eventId': source['sourceEventIds'] is List
            ? (source['sourceEventIds'] as List).first
            : null,
        'reason': 'secret',
      },
    );
    await expectLater(
      gateway.event(scope, (source['sourceEventIds'] as List).first as String),
      throwsA(isA<DomainError>()),
    );
  });
}
