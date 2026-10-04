import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/wave4_gateway_harness.dart';

Map<String, Object?> correctionForm() => {
  'action': 'prepare',
  'id': w4Id,
  'original_calculation_id': w4Revision,
  'posting_date': '2026-10-02',
  'reason': 'SYNTHETIC_PRIVATE',
  'replacements': [
    {
      'seal_id': w4Id,
      'before_revision_id': w4Revision,
      'expected_version': 1,
      'paid_seconds': 1800,
    },
  ],
};
CommandEnvelope<Map<String, Object?>> envelope(Map<String, Object?> p) =>
    CommandEnvelope(
      commandId: w4Command,
      idempotencyKey: w4Command,
      context: w4Scope,
      payload: p,
      expectedEntityVersion: 0,
      clientTimestamp: DateTime.utc(2026, 10, 2),
    );
void main() {
  late Wave4GatewayHarness h;
  late SupabasePayrollCorrectionGateway gateway;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabasePayrollCorrectionGateway(h.client);
  });
  tearDown(() => h.dispose());
  test(
    'named posted credit choices bind exact current revision and posted document lineage',
    () async {
      h.response = {
        ...h.scope(),
        'source_revision_id': w4Revision,
        'kind': 'billing_credits',
        'rows': [
          {
            'id': w4Id,
            'name': 'Posted original credit · 2026-10-02 · 100.00 LKR',
            'code': 'CREDIT',
            'version': 1,
            'amount': '100.000000',
            'currency_code': 'LKR',
            'invoice_line_id': w4Revision,
            'credit_document_id': w4Command,
          },
        ],
        'next_after': null,
      };
      final choices = await gateway.correctionCredits(w4Scope, w4Revision);
      expect(choices.items.single['amount'], '100.000000');
      expect(
        h.requests.last.url.path,
        endsWith('/rpc/projects_payroll_credit_choices'),
      );
      h.response = {...h.response as Map, 'source_revision_id': w4Id};
      await expectLater(
        gateway.correctionCredits(w4Scope, w4Revision),
        throwsFormatException,
      );
      h.response = {
        ...h.response as Map,
        'source_revision_id': w4Revision,
        'rows': [
          {
            'id': w4Id,
            'name': 'Posted original credit',
            'code': 'CREDIT',
            'version': 1,
            'amount': '100.000000',
            'currency_code': 'LKR',
            'invoice_line_id': 'foreign',
            'credit_document_id': w4Command,
          },
        ],
      };
      await expectLater(
        gateway.correctionCredits(w4Scope, w4Revision),
        throwsFormatException,
      );
    },
  );
  test(
    'named source API preserves original calculation and rejects scope/cursor changes',
    () async {
      h.response = {
        ...h.scope(),
        'calculation_id': w4Revision,
        'items': [
          {'id': w4Id, 'seal_id': w4Id},
        ],
        'next_cursor': null,
      };
      expect(
        (await gateway.correctionSources(
          w4Scope,
          w4Revision,
        )).items.single['seal_id'],
        w4Id,
      );
      expect(
        h.requests.last.url.path,
        endsWith('/rpc/people_payroll_correction_sources'),
      );
      h.response = {
        ...h.scope(),
        'calculation_id': w4Id,
        'items': [],
        'next_cursor': null,
      };
      await expectLater(
        gateway.correctionSources(w4Scope, w4Revision),
        throwsFormatException,
      );
      h.response = {
        ...h.scope(),
        'calculation_id': w4Revision,
        'branch_id': w4Revision,
        'items': [],
        'next_cursor': null,
      };
      await expectLater(
        gateway.correctionSources(w4Scope, w4Revision),
        throwsFormatException,
      );
      h.response = {
        ...h.scope(),
        'calculation_id': w4Revision,
        'items': [
          {'id': w4Id},
        ],
        'next_cursor': w4Id,
      };
      await expectLater(
        gateway.correctionSources(w4Scope, w4Revision),
        throwsFormatException,
      );
    },
  );
  test(
    'correction write snapshots before awaited transport and checks exact identity/version',
    () async {
      final p = correctionForm();
      h.gate = Completer<void>();
      h.response = h.confirmed({
        ...h.scope(),
        'id': w4Id,
        'version': 1,
        'status': 'prepared',
      });
      final future = gateway.executeCorrection(
        PayrollCorrectionCommandKind.correction,
        envelope(p),
      );
      p['reason'] = 'mutated';
      (p['replacements'] as List).clear();
      h.gate!.complete();
      await future;
      final body = jsonDecode(h.requests.last.body) as Map;
      expect(body['p_payload']['reason'], 'SYNTHETIC_PRIVATE');
      expect(body['p_payload']['replacements'], hasLength(1));
      h.response = h.confirmed({...h.scope(), 'id': w4Revision, 'version': 1});
      await expectLater(
        gateway.executeCorrection(
          PayrollCorrectionCommandKind.correction,
          envelope(correctionForm()),
        ),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'reverse transport seals current replacement credits and expected source version',
    () async {
      final payload = <String, Object?>{
        'action': 'reverse',
        'id': w4Id,
        'digest': 'a' * 64,
        'posting_date': '2026-10-02',
        'reason': 'Synthetic original-basis reversal',
        'current_billing_impacts': [
          {
            'seal_id': w4Id,
            'source_revision_id': w4Revision,
            'expected_source_version': 5,
            'billing_credit_line_ids': [w4Command],
            'allocation_credits': <Map<String, Object?>>[],
          },
        ],
      };
      h.gate = Completer<void>();
      h.response = h.confirmed({
        ...h.scope(),
        'id': w4Id,
        'version': 4,
        'status': 'reversed',
      });
      final request = CommandEnvelope<Map<String, Object?>>(
        commandId: w4Command,
        idempotencyKey: w4Command,
        context: w4Scope,
        payload: payload,
        expectedEntityVersion: 3,
        clientTimestamp: DateTime.utc(2026, 10, 2),
      );
      final future = gateway.executeCorrection(
        PayrollCorrectionCommandKind.correction,
        request,
      );
      (((payload['current_billing_impacts'] as List).single
                  as Map)['billing_credit_line_ids']
              as List)
          .clear();
      h.gate!.complete();
      await future;
      final sent =
          (jsonDecode(h.requests.last.body) as Map)['p_payload'] as Map;
      expect((sent['current_billing_impacts'] as List).single, {
        'seal_id': w4Id,
        'source_revision_id': w4Revision,
        'expected_source_version': 5,
        'billing_credit_line_ids': [w4Command],
        'allocation_credits': <Object?>[],
      });
      expect(
        (jsonDecode(h.requests.last.body) as Map)['p_expected_version'],
        3,
      );
    },
  );
  test(
    'confirmation cannot leak payroll/private values or silently drop uncertainty',
    () async {
      h.response = h.confirmed({
        ...h.scope(),
        'id': w4Id,
        'version': 1,
        'net': '50.000000',
      });
      await expectLater(
        gateway.executeCorrection(
          PayrollCorrectionCommandKind.correction,
          envelope(correctionForm()),
        ),
        throwsFormatException,
      );
      h.response = h.confirmed({...h.scope(), 'id': w4Id, 'version': 2});
      await expectLater(
        gateway.executeCorrection(
          PayrollCorrectionCommandKind.correction,
          envelope(correctionForm()),
        ),
        throwsA(isA<DomainError>()),
      );
    },
  );
  test(
    'account loss during write is uncertain and private server errors are sanitized',
    () async {
      h.gate = Completer<void>();
      h.response = h.confirmed({...h.scope(), 'id': w4Id, 'version': 1});
      final future = gateway.executeCorrection(
        PayrollCorrectionCommandKind.correction,
        envelope(correctionForm()),
      );
      await Future<void>.delayed(Duration.zero);
      await h.client.auth.signOut(scope: SignOutScope.local);
      h.gate!.complete();
      await expectLater(
        future,
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'stale source and missing linked providers have definite public errors',
    () async {
      h.status = 400;
      h.response = {
        'code': '40001',
        'message': 'PAYROLL_CORRECTION_SOURCE_CHANGED',
        'details': 'PRIVATE_AMOUNT_900',
        'hint': 'PRIVATE',
      };
      await expectLater(
        gateway.corrections(w4Scope),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', 'VERSION_CONFLICT')
              .having((e) => e.message.contains('900'), 'private text', false),
        ),
      );
      h.response = {
        'code': '55000',
        'message': 'WORK_ALLOCATION_IMPACT_REQUIRED',
        'details': 'PRIVATE',
        'hint': 'PRIVATE',
      };
      await expectLater(
        gateway.corrections(w4Scope),
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'PROVIDER_UNAVAILABLE',
          ),
        ),
      );
    },
  );
  test(
    'recovery authorization binds actor and exact original capability',
    () async {
      h.response = {
        ...h.scope(),
        'actor_id': w4Scope.actorId,
        'capability': 'people.payroll.post',
        'authorized': true,
      };
      await gateway.authorize(w4Scope, 'people.payroll.post');
      h.response = {
        ...h.scope(),
        'actor_id': w4Revision,
        'capability': 'people.payroll.post',
        'authorized': true,
      };
      await expectLater(
        gateway.authorize(w4Scope, 'people.payroll.post'),
        throwsFormatException,
      );
      h.response = h.confirmed({...h.scope(), 'id': w4Id, 'version': 1});
      expect(
        await gateway.ownReceipt(w4Scope, w4Command, 'people.payroll.post'),
        isNotNull,
      );
      expect(jsonDecode(h.requests.last.body)['p_action'], 'post');
    },
  );
}
