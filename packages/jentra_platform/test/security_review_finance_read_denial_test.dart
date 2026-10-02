import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import 'support/wave4_gateway_harness.dart';

// The SDK token and HTTP endpoint are synthetic. These checks never contact Auth
// or the development database and do not constitute authenticated acceptance.
void main() {
  late Wave4GatewayHarness h;
  late SupabaseManualJournalGateway journal;
  late SupabasePeriodFxGateway fx;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    journal = SupabaseManualJournalGateway(h.client);
    fx = SupabasePeriodFxGateway(h.client);
  });
  tearDown(() => h.dispose());

  final denials = <(String, String, String)>[
    ('P0001', 'PERMISSION_DENIED', 'PERMISSION_DENIED'),
    ('P0001', 'ACCESS_DENIED', 'ACCESS_DENIED'),
    ('P0001', 'MFA_REQUIRED', 'MFA_REQUIRED'),
    ('P0001', 'RECENT_MFA_REQUIRED', 'MFA_REQUIRED'),
    ('P0001', 'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_REQUIRED'),
    ('PGRST301', 'private expired JWT', 'AUTHENTICATION_REQUIRED'),
    ('PGRST302', 'private absent JWT', 'AUTHENTICATION_REQUIRED'),
    ('PGRST303', 'private invalid JWT', 'AUTHENTICATION_REQUIRED'),
  ];
  Map<String, (String, Future<Map<String, Object?>> Function())> reads() => {
    'journal accounts': (
      'manual_journal_options',
      () => journal.options(w4Scope, 'accounts', after: w4Id),
    ),
    'journal register': (
      'manual_journal_options',
      () => journal.options(w4Scope, 'reports', after: w4Id),
    ),
    'journal taxes': (
      'manual_journal_tax_options',
      () => journal.options(
        w4Scope,
        'taxes',
        documentDate: '2026-10-02',
        after: w4Id,
      ),
    ),
    'journal tax controls': (
      'manual_journal_tax_controls',
      () => journal.options(w4Scope, 'tax_controls', after: w4Id),
    ),
    'journal detail': (
      'manual_journal_detail',
      () => journal.detail(w4Scope, w4Id),
    ),
    'period options': (
      'period_governance_options',
      () => fx.periodOptions(w4Scope, 'periods', after: w4Id),
    ),
    'period events': (
      'period_governance_options',
      () => fx.periodOptions(
        w4Scope,
        'events',
        periodId: w4Revision,
        after: w4Id,
      ),
    ),
    'period requests': (
      'period_governance_options',
      () => fx.periodOptions(
        w4Scope,
        'reopen_requests',
        periodId: w4Revision,
        after: w4Id,
      ),
    ),
    'FX rates': (
      'exchange_revaluation_options',
      () => fx.fxOptions(w4Scope, 'rates', after: w4Id),
    ),
    'FX runs': (
      'exchange_revaluation_options',
      () => fx.fxOptions(w4Scope, 'runs', after: w4Id),
    ),
    'FX detail': (
      'exchange_revaluation_detail',
      () => fx.fxDetail(w4Scope, w4Id, offset: 50),
    ),
  };
  final labels = [
    'journal accounts',
    'journal register',
    'journal taxes',
    'journal tax controls',
    'journal detail',
    'period options',
    'period events',
    'period requests',
    'FX rates',
    'FX runs',
    'FX detail',
  ];
  for (final label in labels) {
    for (final denial in denials) {
      test(
        '$label normalizes ${denial.$1}/${denial.$2} over real SDK transport',
        () async {
          h.status = 403;
          h.response = {
            'code': denial.$1,
            'message': denial.$2,
            'details': 'private source row',
            'hint': 'private server hint',
          };
          final read = reads()[label]!;
          await expectLater(
            read.$2(),
            throwsA(
              isA<DomainError>()
                  .having((e) => e.code, 'code', denial.$3)
                  .having(
                    (e) => e.message,
                    'fixed redacted guidance',
                    isNot(contains('private')),
                  ),
            ),
          );
          expect(h.requests, hasLength(1));
          final request = h.requests.single;
          expect(request.url.path, '/rest/v1/rpc/${read.$1}');
          expect(
            request.headers.entries
                .where((e) => e.key.toLowerCase() == 'content-profile')
                .single
                .value,
            'api',
          );
          final payload = jsonDecode(request.body) as Map;
          expect(payload['p_tenant_id'], w4Scope.tenantId);
          expect(payload['p_legal_entity_id'], w4Scope.legalEntityId);
          expect(payload['p_branch_id'], w4Scope.branchId);
          expect(payload.containsKey('p_command_id'), isFalse);
        },
      );
    }
  }

  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: w4Command,
    idempotencyKey: w4Command,
    context: w4Scope,
    clientTimestamp: DateTime.utc(2026, 10, 2),
    expectedEntityVersion: 1,
    payload: {
      'document_id': w4Id,
      'id': w4Id,
      'period_id': w4Revision,
      'action': 'soft_lock',
    },
  );
  Map<String, Future<Map<String, Object?>> Function()> commands() => {
    'journal save': () => journal.execute('save', command()),
    'journal transition': () => journal.execute('submit', command()),
    'journal post': () => journal.execute('post', command()),
    'period command': () => fx.govern(command()),
    'FX command': () => fx.revalue(command()),
  };
  final commandLabels = [
    'journal save',
    'journal transition',
    'journal post',
    'period command',
    'FX command',
  ];
  for (final label in commandLabels) {
    for (final denial in denials) {
      test(
        '$label keeps existing command classification for ${denial.$1}/${denial.$2}',
        () async {
          h.status = 403;
          h.response = {
            'code': denial.$1,
            'message': denial.$2,
            'details': 'private',
            'hint': 'private',
          };
          final expected = denial.$1.startsWith('PGRST')
              ? 'UNCERTAIN_RESULT'
              : denial.$2 == 'RECENT_MFA_REQUIRED' &&
                    !label.startsWith('journal')
              ? 'MFA_REQUIRED'
              : 'VALIDATION_ERROR';
          await expectLater(
            commands()[label]!(),
            throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
          );
          final payload = jsonDecode(h.requests.single.body) as Map;
          expect(payload['p_command_id'], w4Command);
          expect(payload['p_idempotency_key'], w4Command);
          expect(payload['p_payload'], command().payload);
          expect(
            payload['p_client_timestamp'],
            command().clientTimestamp.toIso8601String(),
          );
        },
      );
    }
    test(
      '$label preserves SQLSTATE version conflict ahead of denial message',
      () async {
        h.status = 409;
        h.response = {'code': '40001', 'message': 'PERMISSION_DENIED'};
        await expectLater(
          commands()[label]!(),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'VERSION_CONFLICT',
            ),
          ),
        );
      },
    );
  }

  for (final kind in ['journal', 'FX']) {
    test('$kind rejects an actor change after an in-flight read', () async {
      h.gate = Completer<void>();
      h.response = kind == 'journal'
          ? {'items': <Object?>[], 'next_cursor': null}
          : {
              ...h.scope(),
              'resource': 'rates',
              'items': <Object?>[],
              'next_cursor': null,
            };
      final read = kind == 'journal'
          ? journal.options(w4Scope, 'accounts')
          : fx.fxOptions(w4Scope, 'rates');
      for (var i = 0; i < 1000 && h.requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(h.requests, hasLength(1));
      await h.client.auth.signOut();
      h.gate!.complete();
      await expectLater(
        read,
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'AUTHENTICATION_REQUIRED',
          ),
        ),
      );
    });
  }
}
