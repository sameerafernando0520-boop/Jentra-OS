import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = FieldSalesScope('tenant', 'entity', 'branch');
  test(
    'portfolio pages transport only scoped named facades and exact cursors',
    () async {
      final calls = <String>[];
      final g = SupabaseFieldSalesGateway.withRpc((name, params) async {
        calls.add(name);
        expect(name, 'field_sales_customers');
        expect(params['p_tenant_id'], 'tenant');
        expect(params['p_legal_entity_id'], 'entity');
        expect(params['p_branch_id'], 'branch');
        expect(params['p_limit'], 50);
        return params['p_after'] == null
            ? {
                'items': [
                  {'id': 'first'},
                ],
                'next_cursor': 'next',
              }
            : {
                'items': [
                  {'id': 'second'},
                ],
                'next_cursor': null,
              };
      }, currentActor: () => 'rep');
      expect((await g.customers(scope)).map((r) => r['id']), [
        'first',
        'second',
      ]);
      expect(calls, hasLength(2));
    },
  );
  test(
    'missing candidate is unavailable and never falls back to legacy tables',
    () async {
      final calls = <String>[];
      final g = SupabaseFieldSalesGateway.withRpc((name, _) async {
        calls.add(name);
        throw const PostgrestException(message: 'missing', code: 'PGRST202');
      }, currentActor: () => 'rep');
      await expectLater(
        g.workspace(),
        throwsA(
          isA<FieldSalesFailure>().having(
            (e) => e.code,
            'code',
            'FIELD_SALES_ROLLOUT_PENDING',
          ),
        ),
      );
      expect(calls, ['field_sales_workspace']);
    },
  );
  test(
    'expired JWT is access loss and late actor changes discard private results',
    () async {
      final expired = SupabaseFieldSalesGateway.withRpc(
        (_, _) async => throw const PostgrestException(
          message: 'expired',
          code: 'PGRST301',
        ),
        currentActor: () => 'rep',
      );
      await expectLater(
        expired.workspace(),
        throwsA(
          isA<FieldSalesFailure>().having(
            (e) => e.code,
            'code',
            'ACCESS_REVOKED',
          ),
        ),
      );
      String? actor = 'rep';
      final response = Completer<Object?>();
      final g = SupabaseFieldSalesGateway.withRpc(
        (_, _) => response.future,
        currentActor: () => actor,
      );
      final read = g.workspace();
      actor = null;
      response.complete({'private': 'old actor'});
      await expectLater(
        read,
        throwsA(
          isA<FieldSalesFailure>().having(
            (e) => e.code,
            'code',
            'ACCESS_REVOKED',
          ),
        ),
      );
    },
  );
  test(
    'submission keeps original decimal strings, timestamp and identity',
    () async {
      final c = FieldSalesCommand(
        actorId: 'rep',
        scope: scope,
        commandId: 'command',
        key: 'key',
        at: '2026-10-31T00:00:00Z',
        payload: {
          'id': 'request',
          'source_digest': 'a' * 64,
          'input': {
            'customer_id': 'customer',
            'lines': [
              {
                'policy_id': 'policy',
                'policy_version': '9007199254740993',
                'quantity': '1.125',
              },
            ],
          },
        },
      );
      final g = SupabaseFieldSalesGateway.withRpc((name, p) async {
        expect(name, 'field_sales_command');
        expect(p, c.params);
        expect(p['p_payload']['input']['lines'][0]['quantity'], isA<String>());
        return {'command_id': 'command'};
      }, currentActor: () => 'rep');
      await g.submit(c);
      expect(
        c.payload['input']['lines'][0]['policy_version'],
        '9007199254740993',
      );
    },
  );
  test('repeating a server cursor is a contract failure', () async {
    final g = SupabaseFieldSalesGateway.withRpc(
      (_, _) async => {'items': [], 'next_cursor': 'same'},
      currentActor: () => 'rep',
    );
    await expectLater(
      g.customers(scope),
      throwsA(
        isA<FieldSalesFailure>().having(
          (e) => e.code,
          'code',
          'CONTRACT_INVALID',
        ),
      ),
    );
  });
}
