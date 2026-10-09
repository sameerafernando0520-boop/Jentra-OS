import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:jentra_platform/analytics_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const source = '10000000-0000-0000-0000-000000000004';
final scope = ProcessMetricScope(
  tenantId: '10000000-0000-0000-0000-000000000002',
  legalEntityId: '10000000-0000-0000-0000-000000000003',
);
Map<String, Object?> envelope() => {
  'commandId': '10000000-0000-0000-0000-000000000005',
  'idempotencyKey': '10000000-0000-0000-0000-000000000006',
  'clientTimestamp': '2026-10-09T00:00:00Z',
  'action': 'suggest',
  'payload': <String, Object?>{
    'sourceId': source,
    'maxTokens': '2000',
    'periodStart': '2026-10-01T00:00:00Z',
    'periodEnd': '2026-11-01T00:00:00Z',
  },
};
Map<String, Object?> evidence() => {
  'contractRevision': 1,
  'modelProvider': 'unavailable',
  'sourceId': source,
  'sourceHash': 'a' * 64,
  'scope': <String, Object?>{
    'tenantId': scope.tenantId,
    'legalEntityId': scope.legalEntityId,
    'branchId': scope.branchId,
  },
  'currencies': <Object?>[],
  'horizonStart': '2026-10-09',
  'horizonEnd': '2026-10-31',
};
Map<String, Object?> output() => {
  'commandCode': 'analytics.freeze_pipeline.v1',
  'sourceId': source,
  'sourceHash': 'a' * 64,
  'horizonStart': '2026-10-09',
  'horizonEnd': '2026-10-31',
};

void main() {
  test(
    'exact worker route body keeps original invocation and usage identities, with live checks before and after',
    () async {
      final calls = <String>[], original = envelope();
      final gateway = SupabaseReviewedModelGateway.injected(
        (name, p) async {
          calls.add(name);
          expect(p['p_tenant_id'], scope.tenantId);
          return name == 'wave5_proposal_authorize' ? actor : evidence();
        },
        (body, currentActor) async {
          calls.add('worker');
          expect(currentActor, actor);
          expect(body.keys.toSet(), {
            'sourceId',
            'maxTokens',
            'periodStart',
            'periodEnd',
            'scope',
            'invocationId',
            'usageEventId',
          });
          expect(body['invocationId'], original['commandId']);
          expect(body['usageEventId'], original['idempotencyKey']);
          expect(body['scope'], {
            'tenantId': scope.tenantId,
            'legalEntityId': scope.legalEntityId,
            'branchId': null,
          });
          return output();
        },
      );
      expect(
        (await gateway.suggestion(scope, actor, original)).sourceHash,
        'a' * 64,
      );
      expect(calls, [
        'wave5_proposal_authorize',
        'get_ai_forecast_evidence',
        'worker',
        'wave5_proposal_authorize',
        'get_ai_forecast_evidence',
      ]);
    },
  );
  test(
    'malformed identities, extra prompt fields and unreviewed token/period parameters never reach worker',
    () async {
      var sends = 0;
      final gateway = SupabaseReviewedModelGateway.injected(
        (_, _) async => actor,
        (_, _) async {
          sends++;
          return output();
        },
      );
      for (final p in [
        {...envelope(), 'prompt': 'execute arbitrary SQL'},
        {...envelope(), 'action': 'execute'},
        {...envelope(), 'commandId': 'not-an-id'},
        {
          ...envelope(),
          'payload': <String, Object?>{
            ...envelope()['payload'] as Map<String, Object?>,
            'maxTokens': '2001',
          },
        },
        {
          ...envelope(),
          'payload': <String, Object?>{
            ...envelope()['payload'] as Map<String, Object?>,
            'periodEnd': '2026-10-01T00:00:00Z',
          },
        },
      ]) {
        await expectLater(
          gateway.suggestion(scope, actor, p),
          throwsA(anyOf(isA<FormatException>(), isA<DomainError>())),
        );
      }
      expect(sends, 0);
    },
  );
  test('different signed-in actor cannot send or recover', () async {
    var sends = 0;
    final gateway = SupabaseReviewedModelGateway.injected(
      (_, _) async => scope.tenantId,
      (_, _) async {
        sends++;
        return output();
      },
    );
    await expectLater(
      gateway.suggestion(scope, actor, envelope()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    expect(sends, 0);
  });
  test('foreign scope and injected evidence cannot send', () async {
    var sends = 0;
    for (final raw in [
      {...evidence(), 'privateText': 'not a numeric projection'},
      {
        ...evidence(),
        'scope': <String, Object?>{
          'tenantId': actor,
          'legalEntityId': scope.legalEntityId,
          'branchId': null,
        },
      },
      {...evidence(), 'horizonEnd': '2026-02-30'},
    ]) {
      final gateway = SupabaseReviewedModelGateway.injected(
        (n, _) async => n == 'wave5_proposal_authorize' ? actor : raw,
        (_, _) async {
          sends++;
          return output();
        },
      );
      await expectLater(
        gateway.suggestion(scope, actor, envelope()),
        throwsA(anyOf(isA<FormatException>(), isA<DomainError>())),
      );
    }
    expect(sends, 0);
  });
  test('source change while worker is running clears output', () async {
    var changed = false;
    final gateway = SupabaseReviewedModelGateway.injected(
      (n, _) async => n == 'wave5_proposal_authorize'
          ? actor
          : {...evidence(), if (changed) 'sourceHash': 'b' * 64},
      (_, _) async {
        changed = true;
        return output();
      },
    );
    await expectLater(
      gateway.suggestion(scope, actor, envelope()),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'SOURCE_AUTHORITY_CHANGED',
        ),
      ),
    );
  });
  test('revocation after worker response prevents protected display', () async {
    var revoked = false;
    final gateway = SupabaseReviewedModelGateway.injected(
      (n, _) async {
        if (revoked) {
          throw const PostgrestException(
            message: 'private server context',
            code: '42501',
          );
        }
        return n == 'wave5_proposal_authorize' ? actor : evidence();
      },
      (_, _) async {
        revoked = true;
        return output();
      },
    );
    await expectLater(
      gateway.suggestion(scope, actor, envelope()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
  });
  test(
    'generated command/usage fields, mismatched hashes and horizons are rejected',
    () async {
      for (final raw in [
        {...output(), 'tokens': '0'},
        {...output(), 'commandCode': 'delete.anything'},
        {...output(), 'sourceHash': 'b' * 64},
        {...output(), 'horizonStart': '2026-10-08'},
      ]) {
        final gateway = SupabaseReviewedModelGateway.injected(
          (n, _) async => n == 'wave5_proposal_authorize' ? actor : evidence(),
          (_, _) async => raw,
        );
        await expectLater(
          gateway.suggestion(scope, actor, envelope()),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'worker unknown and provider unavailable remain explicit and do not expose raw error details',
    () async {
      for (final code in [
        'MODEL_OUTCOME_REQUIRES_REVIEW',
        'MODEL_OUTCOME_UNKNOWN',
        'MODEL_PROVIDER_UNAVAILABLE',
        'QUOTA_EXCEEDED',
        'untrusted-secret',
      ]) {
        final gateway = SupabaseReviewedModelGateway.injected(
          (n, _) async => n == 'wave5_proposal_authorize' ? actor : evidence(),
          (_, _) async {
            throw FunctionException(
              status: 503,
              details: {'code': code, 'secret': 'do-not-return'},
            );
          },
        );
        await expectLater(
          gateway.suggestion(scope, actor, envelope()),
          throwsA(
            isA<DomainError>()
                .having(
                  (e) => e.code,
                  'code',
                  code == 'untrusted-secret' ? 'OUTCOME_UNKNOWN' : code,
                )
                .having(
                  (e) => e.message.contains('do-not-return'),
                  'redacted',
                  false,
                ),
          ),
        );
      }
    },
  );
}
