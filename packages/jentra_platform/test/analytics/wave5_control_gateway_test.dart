import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:jentra_platform/analytics_platform.dart';

void main() {
  final raw =
      (jsonDecode(
                File(
                  'test/analytics/proposal_sql_snapshot.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final canonical = jsonDecode(raw['canonicalText'] as String) as Map,
      scopeJson = canonical['scope'] as Map;
  final scope = ProcessMetricScope(
    tenantId: scopeJson['tenantId'] as String,
    legalEntityId: scopeJson['legalEntityId'] as String,
    branchId: scopeJson['branchId'] as String?,
  );
  test(
    'actual subscription SQL wire keeps exact version and excludes injected fields',
    () async {
      final raw =
          (jsonDecode(
                    File(
                      'test/analytics/subscription_sql_snapshot.json',
                    ).readAsStringSync(),
                  )
                  as Map)
              .cast<String, Object?>();
      final tenant = raw['tenantId'] as String;
      final gateway = SupabaseWave5ControlGateway.injected((_, _) async => raw);
      expect((await gateway.subscription(tenant))['version'], '2');
      for (final altered in [
        {...raw, 'secret': 'private'},
        {...raw, 'tenantId': scope.legalEntityId},
        {...raw, 'version': 2},
        {...raw, 'trialEnd': raw['trialStart']},
      ]) {
        await expectLater(
          SupabaseWave5ControlGateway.injected(
            (_, _) async => altered,
          ).subscription(tenant),
          throwsFormatException,
        );
      }
      await expectLater(
        SupabaseWave5ControlGateway.injected(
          (_, _) async => tenant,
        ).authorizeSubscriptionRecovery(scope, scope.legalEntityId),
        throwsA(isA<DomainError>()),
      );
    },
  );
  test(
    'actual SQL human proposal matches independent Dart canonical bytes and policy',
    () async {
      final verified = await VerifiedHumanProposal.verify(raw, scope);
      expect(verified.state, 'proposed');
      expect(verified.revision.evidence.targetVersions, hasLength(3));
      expect(verified.revision.estimatedUnits, BigInt.zero);
    },
  );
  test('edited revision bytes and private field injection rejected', () async {
    expect(
      () => VerifiedHumanProposal.verify({
        ...raw,
        'canonicalText': '${raw['canonicalText']} ',
      }, scope),
      throwsFormatException,
    );
    expect(
      () => VerifiedHumanProposal.verify({
        ...raw,
        'privateReason': 'private',
      }, scope),
      throwsFormatException,
    );
  });
  test(
    'all recovery adapters compare actual server actor before allowing storage',
    () async {
      const wrong = '10000000-0000-0000-0000-000000000001';
      final actor = canonical['proposerId'] as String;
      await SupabaseProcessMetricGateway.injected(
        (_, _) async => actor,
      ).authorizeRecovery(scope, actor);
      expect(
        () => SupabaseProcessMetricGateway.injected(
          (_, _) async => actor,
        ).authorizeRecovery(scope, wrong),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => SupabasePipelineForecastGateway.injected(
          (_, _) async => actor,
        ).authorizeRecovery(scope, wrong),
        throwsA(isA<DomainError>()),
      );
      expect(
        () => SupabaseWave5ControlGateway.injected(
          (_, _) async => actor,
        ).authorizeProposalRecovery(scope, wrong),
        throwsA(isA<DomainError>()),
      );
    },
  );
  final codes = [
    'worker_lag_seconds',
    'retry_count',
    'dead_letter_count',
    'quota_remaining',
  ];
  Map<String, Object?> health() => {
    'contractRevision': 1,
    'generatedAt': '2026-10-06T00:06:00.000000Z',
    'probes': [
      for (final code in codes)
        {
          'code': code,
          'state': 'unknown',
          'exactValue': null,
          'observedAt': null,
        },
    ],
  };
  test(
    'missing probes remain unknown and private substitute field fails',
    () async {
      final gateway = SupabaseWave5ControlGateway.injected(
        (_, _) async => health(),
      );
      expect((await gateway.health())['probes'], hasLength(4));
      final altered = health(), probes = altered['probes'] as List;
      probes[0] = {
        'code': codes[0],
        'state': 'unknown',
        'exactValue': null,
        'privateDiagnostic': 'secret',
      };
      expect(
        () => SupabaseWave5ControlGateway.injected(
          (_, _) async => altered,
        ).health(),
        throwsFormatException,
      );
    },
  );
  test('stale probe cannot be marked observed', () async {
    final altered = health(), probes = altered['probes'] as List;
    probes[0] = {
      'code': codes[0],
      'state': 'observed',
      'exactValue': '0',
      'observedAt': '2026-10-06T00:00:00.000000Z',
    };
    expect(
      () => SupabaseWave5ControlGateway.injected(
        (_, _) async => altered,
      ).health(),
      throwsFormatException,
    );
  });
  test(
    'usage requires exact complete allowance arithmetic and requested period',
    () async {
      final usage = {
        'state': 'available',
        'tenantId': scope.tenantId,
        'metricCode': 'ai.tokens',
        'periodStart': '2026-10-01T00:00:00.000000Z',
        'periodEnd': '2026-11-01T00:00:00.000000Z',
        'limit': '9007199254740993',
        'settled': '9007199254740990',
        'reserved': '2',
        'remaining': '1',
        'generatedAt': '2026-10-06T00:00:00.000000Z',
      };
      final gateway = SupabaseWave5ControlGateway.injected(
        (_, _) async => usage,
      );
      expect(
        (await gateway.usage(
          scope.tenantId,
          'ai.tokens',
          '2026-10-01T00:00:00Z',
        ))['remaining'],
        '1',
      );
      expect(
        () => SupabaseWave5ControlGateway.injected(
          (_, _) async => {...usage, 'remaining': '2'},
        ).usage(scope.tenantId, 'ai.tokens', '2026-10-01T00:00:00Z'),
        throwsFormatException,
      );
    },
  );
}
