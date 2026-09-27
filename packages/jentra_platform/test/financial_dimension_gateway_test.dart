import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> dimensionBasis({
  String kind = 'cost_centre',
  String id = 'centre',
  String? branch,
}) => {
  'id': id,
  'tenant_id': 't',
  'legal_entity_id': 'e',
  'branch_id': branch,
  'kind': kind,
  'version': 1,
  'code': 'CC-1',
  'name': 'Distribution',
};
Map<String, Object?> dimensionRow() => {
  'id': 'centre',
  'tenant_id': 't',
  'legal_entity_id': 'e',
  'dimension_branch_id': null,
  'kind': 'cost_centre',
  'version': 1,
  'code': 'CC-1',
  'name': 'Distribution',
  'status': 'active',
  'reason': 'Governed attribution',
};
void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'actor',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late SupabaseClient client;
  late SupabaseFinancialDimensionGateway gateway;
  Object response = {};
  var status = 200;
  final requests = <http.Request>[];
  setUp(() async {
    status = 200;
    requests.clear();
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/token')) {
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': 'actor',
                    'role': 'authenticated',
                    'exp': 4102444800,
                  }),
                ),
              )
              .replaceAll('=', '');
          return http.Response(
            jsonEncode({
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': 'actor',
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseFinancialDimensionGateway(client);
    response = {
      'tenant_id': 't',
      'legal_entity_id': 'e',
      'branch_id': 'b',
      'kind': 'cost_centre',
      'items': [dimensionRow()],
      'next_cursor': null,
    };
  });
  tearDown(() => client.dispose());
  test(
    'catalog uses current scope active-only search and bounded continuation',
    () async {
      await gateway.page(scope, 'cost_centre', search: 'CC');
      final p = jsonDecode(requests.single.body) as Map;
      expect(p['p_branch_id'], 'b');
      expect(p['p_search'], 'CC');
      expect(p['p_active_only'], true);
      expect(requests.single.url.path, endsWith('financial_dimensions'));
    },
  );
  test('foreign entity branch or master kind cannot become a choice', () async {
    final base = (response as Map).cast<String, Object?>();
    for (final altered in [
      {...dimensionRow(), 'legal_entity_id': 'other'},
      {...dimensionRow(), 'dimension_branch_id': 'other'},
      {...dimensionRow(), 'kind': 'project'},
    ]) {
      response = {
        ...base,
        'items': [altered],
      };
      await expectLater(
        gateway.page(scope, 'cost_centre'),
        throwsFormatException,
      );
    }
  });
  test(
    'retired duplicate and imprecise version choices are rejected',
    () async {
      final base = (response as Map).cast<String, Object?>();
      for (final rows in [
        [
          {...dimensionRow(), 'status': 'retired'},
        ],
        [dimensionRow(), dimensionRow()],
        [
          {...dimensionRow(), 'version': '1'},
        ],
      ]) {
        response = {...base, 'items': rows};
        await expectLater(
          gateway.page(scope, 'cost_centre'),
          throwsFormatException,
        );
      }
    },
  );
  test('unsupported kind and oversized search send no request', () async {
    await expectLater(gateway.page(scope, 'invented'), throwsFormatException);
    await expectLater(
      gateway.page(scope, 'project', search: 'x' * 101),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test('false continuation cannot manufacture a second page', () async {
    response = {...(response as Map), 'next_cursor': 'other'};
    await expectLater(
      gateway.page(scope, 'cost_centre'),
      throwsFormatException,
    );
  });
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    context: scope,
    commandId: 'command',
    idempotencyKey: 'key',
    clientTimestamp: DateTime.utc(2026, 9, 26),
    expectedEntityVersion: 0,
    payload: {
      for (final k in [
        'id',
        'kind',
        'code',
        'name',
        'reason',
        'status',
        'dimension_branch_id',
      ])
        k: dimensionRow()[k],
    },
  );
  test(
    'sealed dimension confirmation retains requested identity label scope and version',
    () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {...dimensionRow(), 'branch_id': 'b'},
      };
      expect((await gateway.save(command()))['version'], 1);
      for (final changed in [
        {...dimensionRow(), 'branch_id': 'b', 'name': 'Different label'},
        {...dimensionRow(), 'branch_id': 'b', 'dimension_branch_id': 'b'},
        {...dimensionRow(), 'branch_id': 'b', 'version': 2},
      ]) {
        response = {
          'command_id': 'command',
          'request_id': 'request',
          'entity': changed,
        };
        await expectLater(
          gateway.save(command()),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'UNCERTAIN_RESULT',
            ),
          ),
        );
      }
    },
  );
  test(
    'current MFA and permission failure remain actionable access errors',
    () async {
      status = 403;
      response = {
        'code': '42501',
        'message': 'RECENT_MFA_REQUIRED',
        'details': null,
        'hint': null,
      };
      await expectLater(
        gateway.page(scope, 'project'),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'MFA_REQUIRED'),
        ),
      );
      response = {
        'code': '42501',
        'message': 'PERMISSION_DENIED',
        'details': null,
        'hint': null,
      };
      await expectLater(
        gateway.page(scope, 'project'),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
        ),
      );
    },
  );
  test(
    'frozen historical identity accepts original version without consulting current master',
    () {
      FinancialDimensionEvidence.validate({
        'cost_centre_id': 'centre',
        'dimension_snapshot': {'cost_centre': dimensionBasis()},
      }, scope);
    },
  );
  test(
    'foreign or missing frozen basis cannot masquerade as a governed actual',
    () {
      for (final row in [
        {'cost_centre_id': 'centre'},
        {
          'cost_centre_id': 'centre',
          'dimension_snapshot': {
            'cost_centre': {...dimensionBasis(), 'tenant_id': 'other'},
          },
        },
        {
          'cost_centre_id': 'centre',
          'dimension_snapshot': {
            'cost_centre': {...dimensionBasis(), 'id': 'other'},
          },
        },
        {
          'cost_centre_id': null,
          'dimension_snapshot': {'cost_centre': dimensionBasis()},
        },
      ]) {
        expect(
          () => FinancialDimensionEvidence.validate(row, scope),
          throwsFormatException,
        );
      }
    },
  );
  test('entity budget cannot relabel branch attribution as entity-wide', () {
    expect(
      () => FinancialDimensionEvidence.validate(
        {
          'cost_centre_id': 'centre',
          'dimension_snapshot': {'cost_centre': dimensionBasis(branch: 'b')},
        },
        scope,
        entityOnly: true,
      ),
      throwsFormatException,
    );
  });
}
