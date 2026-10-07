import 'dart:convert';
import 'dart:io';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw =
      (jsonDecode(
                File(
                  'test/analytics/pipeline_sql_snapshot.json',
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, Object?>();
  final e = raw['evidence'] as Map<String, Object?>;
  final scope = ProcessMetricScope(
    tenantId: e['tenantId'] as String,
    legalEntityId: e['legalEntityId'] as String,
    branchId: e['branchId'] as String?,
  );
  test(
    'actual SQL frozen bytes verify and match independent exact forecast',
    () async {
      final gateway = SupabasePipelineForecastGateway.injected(
        (_, _) async => raw,
      );
      final f = await gateway.get(scope, raw['id'] as String);
      expect(f.currencies.map((c) => c.weightedAmount), [
        '10.000002',
        '5.000001',
      ]);
      expect(
        f.observations.any(
          (o) => o.version == BigInt.parse('9007199254740993'),
        ),
        isTrue,
      );
      expect(() => f.observations.clear(), throwsUnsupportedError);
    },
  );
  test('changed captured bytes and scope fail closed', () async {
    final changed = {...raw, 'canonicalText': '${raw['canonicalText']} '};
    expect(
      () => FrozenPipelineForecast.verify(
        changed,
        scope,
        raw['id'] as String,
        ProcessMetricSha256Hasher(),
      ),
      throwsFormatException,
    );
    expect(
      () => FrozenPipelineForecast.verify(
        raw,
        ProcessMetricScope(
          tenantId: scope.tenantId,
          legalEntityId: scope.legalEntityId,
        ),
        raw['id'] as String,
        ProcessMetricSha256Hasher(),
      ),
      throwsFormatException,
    );
  });
  test('evidence cannot diverge from hash-bound bytes', () async {
    final changed = {
      ...raw,
      'evidence': {...e, 'sourceCount': 0},
    };
    expect(
      () => FrozenPipelineForecast.verify(
        changed,
        scope,
        raw['id'] as String,
        ProcessMetricSha256Hasher(),
      ),
      throwsFormatException,
    );
  });
  test(
    'rehashed malformed provider evidence still fails scope, completeness, redaction and exact totals',
    () async {
      final mutations = <void Function(Map<String, Object?>)>[
        (v) => v['complete'] = false,
        (v) => v['sourceCount'] = 4,
        (v) => v['privateReason'] = 'private',
        (v) => v['definitionVersion'] = 2,
        (v) => v['recordedThrough'] = '2026-10-01T00:00:00Z',
        (v) => v['tenantId'] = scope.legalEntityId,
        (v) => (v['observations'] as List)[0] = null,
        (v) => ((v['observations'] as List)[0] as Map)['version'] =
            9007199254740993,
        (v) => ((v['observations'] as List)[0] as Map)['amount'] = 1.5,
        (v) =>
            ((v['observations'] as List)[0] as Map)['privateName'] = 'private',
        (v) => ((v['observations'] as List)[0] as Map)['probability'] =
            '100.000001',
        (v) => ((v['observations'] as List)[0] as Map)['expectedCloseDate'] =
            v['horizonEnd'],
        (v) => (v['currencies'] as List).removeLast(),
        (v) => (v['currencies'] as List)[0] = null,
        (v) => ((v['currencies'] as List)[0] as Map)['weightedAmount'] =
            '999.000000',
        (v) => v['unavailable'] = {'accuracy': 'AVAILABLE'},
      ];
      for (final mutate in mutations) {
        final evidence = (jsonDecode(jsonEncode(e)) as Map)
            .cast<String, Object?>();
        mutate(evidence);
        final text = jsonEncode(evidence), hasher = ProcessMetricSha256Hasher();
        final changed = {
          ...raw,
          'evidence': evidence,
          'canonicalText': text,
          'sourceHash': await hasher.sha256(utf8.encode(text)),
        };
        await expectLater(
          FrozenPipelineForecast.verify(
            changed,
            scope,
            raw['id'] as String,
            hasher,
          ),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}
