import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:jentra_platform/analytics_platform.dart';

String id(int i) => '10000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
void main() {
  Future<FrozenPipelineForecast> frozen() async {
    final raw =
        (jsonDecode(
                  File(
                    'test/analytics/pipeline_sql_snapshot.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast<String, Object?>();
    final e = raw['evidence'] as Map<String, Object?>;
    return FrozenPipelineForecast.verify(
      raw,
      ProcessMetricScope(
        tenantId: e['tenantId'] as String,
        legalEntityId: e['legalEntityId'] as String,
        branchId: e['branchId'] as String?,
      ),
      raw['id'] as String,
      ProcessMetricSha256Hasher(),
    );
  }

  Map<String, Object?> realized(
    FrozenPipelineForecast f,
    List<Map<String, Object?>> documents,
  ) => {
    'contractRevision': 1,
    'forecastId': f.id,
    'sourceHash': f.sourceHash,
    'complete': true,
    'definition': 'posted_invoice_less_order_linked_credit_gross.v1',
    'asOf': '2026-11-02T00:00:00Z',
    'documents': documents,
  };
  test(
    'realized documents preserve exact signed invoices and credits within the frozen currency cohort',
    () async {
      final f = await frozen(),
          opportunity = f.observations.firstWhere((r) => r.currency == 'LKR');
      final documents = [
        {
          'id': id(70),
          'opportunityId': opportunity.id,
          'branchId': f.scope.branchId,
          'currency': 'LKR',
          'amount': '12.000003',
          'version': '9007199254740993',
          'kind': 'invoice',
          'postedAt': '2026-10-31T00:00:00Z',
        },
        {
          'id': id(71),
          'opportunityId': opportunity.id,
          'branchId': f.scope.branchId,
          'currency': 'LKR',
          'amount': '-2.000001',
          'version': '2',
          'kind': 'credit_return',
          'postedAt': '2026-10-31T00:00:00Z',
        },
      ];
      final value = await HistoricalPipelineGateway(
        (_, _) async => realized(f, documents),
      ).accuracy(f, '2026-11-02T00:00:00Z');
      expect(value['LKR']!.$1, BigInt.zero);
      expect(value['LKR']!.$2!.exactValue, '0.000000');
      expect(value['USD']!.$2, isNull);
    },
  );
  test(
    'realized mappings reject duplicate IDs, foreign cohorts, signed mismatch and out-of-range SQL revisions',
    () async {
      final f = await frozen(), opportunity = f.observations.first;
      final base = <String, Object?>{
        'id': id(70),
        'opportunityId': opportunity.id,
        'branchId': f.scope.branchId,
        'currency': opportunity.currency,
        'amount': '10.000001',
        'version': '1',
        'kind': 'invoice',
        'postedAt': '2026-10-31T00:00:00Z',
      };
      for (final docs in [
        [base, base],
        [
          {...base, 'opportunityId': id(99)},
        ],
        [
          {...base, 'kind': 'credit_return'},
        ],
        [
          {...base, 'version': '9223372036854775808'},
        ],
        [
          {...base, 'postedAt': '2026-11-03T00:00:00Z'},
        ],
        [
          // Both currencies exist in this forecast. A document must still
          // match the currency of its own frozen opportunity.
          {...base, 'currency': opportunity.currency == 'LKR' ? 'USD' : 'LKR'},
        ],
      ]) {
        await expectLater(
          HistoricalPipelineGateway(
            (_, _) async => realized(f, docs),
          ).accuracy(f, '2026-11-02T00:00:00Z'),
          throwsFormatException,
        );
      }
    },
  );
  final scope = ProcessMetricScope(
    tenantId: id(1),
    legalEntityId: id(2),
    branchId: id(3),
  );
  Future<Map<String, Object?>> wire({
    bool foreign = false,
    bool changed = false,
  }) async {
    final value = {
      'contractRevision': 1,
      'sourceContract': 'crm.pipeline_history.v1',
      'scope': {
        'branchId': scope.branchId,
        'legalEntityId': scope.legalEntityId,
        'tenantId': foreign ? id(9) : scope.tenantId,
      },
      'asOf': '2026-10-03T00:00:00Z',
      'recordedThrough': '2026-10-03T00:00:00Z',
      'complete': true,
      'revisions': [
        {
          'id': id(4),
          'revisionId': id(5),
          'version': '1',
          'tenantId': scope.tenantId,
          'legalEntityId': scope.legalEntityId,
          'branchId': scope.branchId,
          'recordedAt': '2026-10-01T00:00:00Z',
          'createdAt': '2026-10-01T00:00:00Z',
          'stage': 'qualified',
          'status': 'open',
          'ownerId': id(6),
          'amount': '10.000001',
          'probability': '50.00',
          'currency': 'LKR',
        },
      ],
    };
    final canonical = jsonEncode(value);
    return {
      'canonicalText': canonical,
      'sourceHash': changed
          ? 'a' * 64
          : await ProcessMetricSha256Hasher().sha256(utf8.encode(canonical)),
    };
  }

  test(
    'trusted historical wire preserves decimal scale and ignores object key order',
    () async {
      final gateway = HistoricalPipelineGateway((name, params) async {
        expect(name, 'wave5_pipeline_history');
        return wire();
      });
      final value = await gateway.read(
        scope,
        '2026-10-03T00:00:00Z',
        '2026-10-03T00:00:00Z',
      );
      expect(
        value.stageAgeMicroseconds[id(4)],
        BigInt.from(const Duration(days: 2).inMicroseconds),
      );
    },
  );
  test(
    'foreign scope and altered digest fail before exposing a total',
    () async {
      for (final w in [await wire(foreign: true), await wire(changed: true)]) {
        final gateway = HistoricalPipelineGateway((_, _) async => w);
        await expectLater(
          gateway.read(scope, '2026-10-03T00:00:00Z', '2026-10-03T00:00:00Z'),
          throwsFormatException,
        );
      }
    },
  );
  test('reversed history cutoffs fail before invoking the authority', () async {
    var calls = 0;
    final gateway = HistoricalPipelineGateway((_, _) async {
      calls++;
      return wire();
    });
    await expectLater(
      gateway.read(scope, '2026-10-03T00:00:00Z', '2026-10-02T00:00:00Z'),
      throwsFormatException,
    );
    expect(calls, 0);
  });
  test(
    'malformed history cutoffs fail before invoking the authority',
    () async {
      var calls = 0;
      final gateway = HistoricalPipelineGateway((_, _) async {
        calls++;
        return wire();
      });
      for (final dates in [
        ('2026-10-03', '2026-10-03T00:00:00Z'),
        ('2026-10-03T00:00:00Z', '2026-10-03T00:00:00+05:30'),
      ]) {
        await expectLater(
          gateway.read(scope, dates.$1, dates.$2),
          throwsA(
            isA<DomainError>().having(
              (error) => error.code,
              'code',
              'VALIDATION_ERROR',
            ),
          ),
        );
      }
      expect(calls, 0);
    },
  );
}
