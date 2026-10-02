import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  final requests = <http.Request>[];
  var errorCode = 'P0001', errorMessage = 'ACCESS_DENIED';
  setUp(() async {
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
              'access_token':
                  'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': 'actor',
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-19T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(r);
        return http.Response(
          jsonEncode({
            'code': errorCode,
            'message': errorMessage,
            'details': 'synthetic-read-denial',
            'hint': null,
          }),
          403,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
  });
  tearDown(() => client.dispose());

  Map<String, Future<Map<String, Object?>> Function()> reads() => {
    'reconciliation reports': () =>
        SupabaseControlReconciliationGateway(client).reports(scope),
    'reconciliation page': () => SupabaseControlReconciliationGateway(
      client,
    ).page(scope, 'report', 'items'),
    'financial periods': () =>
        SupabaseFinancialStatementGateway(client).periods(scope),
    'financial reports': () =>
        SupabaseFinancialStatementGateway(client).reports(scope),
    'financial page': () => SupabaseFinancialStatementGateway(
      client,
    ).page(scope, 'report', 'accounts'),
    'cash flow mapping': () =>
        SupabaseCashFlowMappingGateway(client).options(scope, '2026-09-20'),
    'tax periods': () => SupabaseTaxSummaryGateway(client).periods(scope),
    'tax reports': () => SupabaseTaxSummaryGateway(client).reports(scope),
    'tax page': () => SupabaseTaxSummaryGateway(client).page(scope, 'report'),
    'tax controls': () =>
        SupabaseTaxSummaryGateway(client).controls(scope, 'report', 'controls'),
    'budget accounts': () => SupabaseBudgetGateway(client).accounts(scope),
    'budget periods': () => SupabaseBudgetGateway(client).periods(scope),
    'budget options': () => SupabaseBudgetGateway(client).budgets(scope),
    'budget reports': () => SupabaseBudgetGateway(client).reports(scope),
    'budget page': () =>
        SupabaseBudgetGateway(client).page(scope, 'report', 'lines'),
    'close periods': () => SupabaseCloseReviewGateway(client).periods(scope),
    'close reports': () => SupabaseCloseReviewGateway(client).reports(scope),
    'close page': () =>
        SupabaseCloseReviewGateway(client).page(scope, 'report', 'controls'),
    'export preview': () => SupabaseReportExportGateway(client).preview(scope, {
      'source_type': 'close',
      'source_id': 'report',
      'section': 'sources',
      'filters': <String, Object?>{},
    }),
    'inventory options': () =>
        SupabaseInventoryValuationGateway(client).options(scope, 'reports'),
    'inventory page': () => SupabaseInventoryValuationGateway(
      client,
    ).page(scope, 'report', 'stock'),
  };
  final denials = <(String, String, String)>[
    ('P0001', 'PERMISSION_DENIED', 'PERMISSION_DENIED'),
    ('P0001', 'ACCESS_DENIED', 'ACCESS_DENIED'),
    ('P0001', 'MFA_REQUIRED', 'MFA_REQUIRED'),
    ('P0001', 'RECENT_MFA_REQUIRED', 'MFA_REQUIRED'),
    ('P0001', 'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_REQUIRED'),
    ('PGRST301', 'JWT expired', 'AUTHENTICATION_REQUIRED'),
    ('PGRST302', 'JWT required', 'AUTHENTICATION_REQUIRED'),
    ('PGRST303', 'JWT invalid', 'AUTHENTICATION_REQUIRED'),
  ];
  // Exercise each public adapter method over HTTP, including the shared transport.
  for (final label in [
    'reconciliation reports',
    'reconciliation page',
    'financial periods',
    'financial reports',
    'financial page',
    'cash flow mapping',
    'tax periods',
    'tax reports',
    'tax page',
    'tax controls',
    'budget accounts',
    'budget periods',
    'budget options',
    'budget reports',
    'budget page',
    'close periods',
    'close reports',
    'close page',
    'export preview',
    'inventory options',
    'inventory page',
  ]) {
    for (final denial in denials) {
      test('$label normalizes ${denial.$1}/${denial.$2}', () async {
        errorCode = denial.$1;
        errorMessage = denial.$2;
        await expectLater(
          reads()[label]!(),
          throwsA(isA<DomainError>().having((e) => e.code, 'code', denial.$3)),
        );
        expect(requests, hasLength(1));
        expect(
          requests.single.headers.entries
              .where((e) => e.key.toLowerCase() == 'content-profile')
              .single
              .value,
          'api',
        );
        final payload = jsonDecode(requests.single.body) as Map;
        expect(payload['p_tenant_id'], 'tenant');
        expect(payload['p_legal_entity_id'], 'entity');
        expect(payload['p_branch_id'], 'branch');
      });
    }
  }
  final command = CommandEnvelope<Map<String, Object?>>(
    commandId: 'command',
    idempotencyKey: 'original-key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 20),
    expectedEntityVersion: 0,
    payload: const {
      'id': 'report',
      'kind': 'trial_balance',
      'as_of': '2026-09-20',
    },
  );
  Map<String, Future<Map<String, Object?>> Function()> commands() => {
    'reconciliation': () =>
        SupabaseControlReconciliationGateway(client).generate(command),
    'financial': () =>
        SupabaseFinancialStatementGateway(client).generate(command),
    'tax': () => SupabaseTaxSummaryGateway(client).generate(command),
    'budget': () => SupabaseBudgetGateway(client).generate(command),
    'close': () => SupabaseCloseReviewGateway(client).generate(command),
    'export': () => SupabaseReportExportGateway(client).record(command),
    'inventory': () =>
        SupabaseInventoryValuationGateway(client).generate(command),
  };
  for (final label in [
    'reconciliation',
    'financial',
    'tax',
    'budget',
    'close',
    'export',
    'inventory',
  ]) {
    for (final denial in denials) {
      test(
        '$label command preserves existing classification for ${denial.$1}/${denial.$2}',
        () async {
          errorCode = denial.$1;
          errorMessage = denial.$2;
          final expected = errorCode.startsWith('PGRST')
              ? 'UNCERTAIN_RESULT'
              : errorMessage == 'RECENT_MFA_REQUIRED' && label != 'inventory'
              ? 'MFA_REQUIRED'
              : 'VALIDATION_ERROR';
          await expectLater(
            commands()[label]!(),
            throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
          );
          expect(requests, hasLength(1));
          final payload = jsonDecode(requests.single.body) as Map;
          expect(payload['p_command_id'], command.commandId);
          expect(payload['p_idempotency_key'], command.idempotencyKey);
          expect(payload['p_payload'], command.payload);
        },
      );
    }
  }
}
