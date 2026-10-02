import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/wave4_gateway_harness.dart';

Map<String, Object?> run(Wave4GatewayHarness h) => {
  ...h.scope(),
  'id': w4Id,
  'name': 'Synthetic payroll',
  'start_date': '2026-09-01',
  'end_date_exclusive': '2026-10-01',
  'posting_date': '2026-09-30',
  'currency_code': 'LKR',
  'version': 1,
  'status': 'draft',
  'current_revision_id': null,
  'digest': null,
  'employee_count': null,
  'prepared_by': null,
  'submitted_by': null,
  'approved_by': null,
  'posted_journal_id': null,
  'reversal_journal_id': null,
  'created_by': w4Scope.actorId,
};
Map<String, Object?> create() => {
  'action': 'create',
  'id': w4Id,
  'name': 'Synthetic payroll',
  'start_date': '2026-09-01',
  'end_date_exclusive': '2026-10-01',
  'posting_date': '2026-09-30',
  'employee_ids': [w4Id],
  'reason': 'Synthetic run',
};
CommandEnvelope<Map<String, Object?>> command(Map<String, Object?> p) =>
    CommandEnvelope(
      commandId: w4Command,
      idempotencyKey: w4Command,
      context: w4Scope,
      payload: p,
      expectedEntityVersion: 0,
      clientTimestamp: DateTime.utc(2026, 9, 30),
    );
void main() {
  late Wave4GatewayHarness h;
  late SupabasePayrollGateway gateway;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabasePayrollGateway(h.client);
  });
  tearDown(() => h.dispose());
  test(
    'run reads use a named scoped API and reject ancestry changes',
    () async {
      h.response = {
        ...h.scope(),
        'items': [run(h)],
        'next_cursor': null,
      };
      final page = await gateway.runs(w4Scope);
      expect(page.items.single.name, 'Synthetic payroll');
      expect(h.requests.last.url.path, endsWith('/rpc/people_payroll_runs'));
      final args = jsonDecode(h.requests.last.body) as Map;
      expect(args['p_legal_entity_id'], w4Scope.legalEntityId);
      h.response = {
        ...h.scope(),
        'items': [
          {...run(h), 'branch_id': w4Revision},
        ],
        'next_cursor': null,
      };
      await expectLater(gateway.runs(w4Scope), throwsFormatException);
      h.response = {
        ...h.scope(),
        'items': [run(h)],
        'next_cursor': w4Id,
      };
      await expectLater(gateway.runs(w4Scope), throwsFormatException);
    },
  );
  test(
    'commands snapshot before awaiting and verify minimal scoped confirmation',
    () async {
      final payload = create();
      h.gate = Completer<void>();
      h.response = h.confirmed({...run(h)}..remove('name'));
      final work = gateway.execute(PayrollCommandKind.run, command(payload));
      payload['name'] = 'Changed';
      (payload['employee_ids'] as List).add(w4Revision);
      h.gate!.complete();
      final result = await work;
      final sent = jsonDecode(h.requests.last.body) as Map;
      expect((sent['p_payload'] as Map)['name'], 'Synthetic payroll');
      expect((sent['p_payload'] as Map)['employee_ids'], [w4Id]);
      expect((result['entity'] as Map).containsKey('net'), isFalse);
    },
  );
  test(
    'forged confirmation is uncertain and cannot silently discard sealed request',
    () async {
      h.response = h.confirmed(
        {...run(h), 'net': '900.000000'}..remove('name'),
      );
      await expectLater(
        gateway.execute(PayrollCommandKind.run, command(create())),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
      h.response = h.confirmed(
        {...run(h), 'created_by': w4Revision}..remove('name'),
      );
      await expectLater(
        gateway.execute(PayrollCommandKind.run, command(create())),
        throwsA(
          isA<DomainError>().having((e) => e.retryable, 'retryable', true),
        ),
      );
    },
  );
  test('account changes during awaited write keep outcome uncertain', () async {
    h.gate = Completer<void>();
    h.response = h.confirmed({...run(h)}..remove('name'));
    final work = gateway.execute(PayrollCommandKind.run, command(create()));
    await Future<void>.delayed(Duration.zero);
    await h.client.auth.signOut(scope: SignOutScope.local);
    h.gate!.complete();
    await expectLater(
      work,
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test(
    'read errors sanitize private values and expose useful stale-input state',
    () async {
      h.status = 400;
      h.response = {
        'code': '40001',
        'message': 'PAYROLL_INPUTS_CHANGED',
        'details': 'PRIVATE_PAYROLL_AMOUNT_12345',
        'hint': 'private',
      };
      await expectLater(
        gateway.runs(w4Scope),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', 'PAYROLL_INPUTS_CHANGED')
              .having(
                (e) => e.message.contains('12345'),
                'private text',
                false,
              ),
        ),
      );
      h.status = 404;
      h.response = {
        'code': 'PGRST202',
        'message': 'private provider payload',
        'details': 'private',
        'hint': 'private',
      };
      await expectLater(
        gateway.runs(w4Scope),
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'FEATURE_NOT_INSTALLED',
          ),
        ),
      );
    },
  );
  test(
    'obligations preserve decimal strings and reject over-due or foreign employee metadata',
    () async {
      final obligation = {
        'id': w4Id,
        'run_id': w4Id,
        'employee_id': w4Id,
        'kind': 'net',
        'currency_code': 'LKR',
        'amount': '900.000000',
        'account_id': w4Revision,
        'outstanding': '700.000000',
      };
      h.response = {
        ...h.scope(),
        'run_id': w4Id,
        'items': [obligation],
        'next_cursor': null,
      };
      expect(
        (await gateway.obligations(w4Scope, w4Id)).items.single['outstanding'],
        '700.000000',
      );
      h.response = {
        ...h.scope(),
        'run_id': w4Id,
        'items': [
          {...obligation, 'outstanding': '901.000000'},
        ],
        'next_cursor': null,
      };
      await expectLater(
        gateway.obligations(w4Scope, w4Id),
        throwsFormatException,
      );
      h.response = {
        ...h.scope(),
        'run_id': w4Id,
        'items': [
          {...obligation, 'bank_number': 'PRIVATE'},
        ],
        'next_cursor': null,
      };
      await expectLater(
        gateway.obligations(w4Scope, w4Id),
        throwsFormatException,
      );
    },
  );
  test(
    'own receipt is scoped to the requested command and excludes monetary bodies',
    () async {
      h.response = h.confirmed({...run(h)}..remove('name'));
      expect(
        await gateway.ownReceipt(w4Scope, w4Command, 'people.payroll.prepare'),
        isNotNull,
      );
      h.response = {
        ...h.confirmed({...run(h)}..remove('name')),
        'command_id': w4Revision,
      };
      await expectLater(
        gateway.ownReceipt(w4Scope, w4Command, 'people.payroll.prepare'),
        throwsFormatException,
      );
      h.response = h.confirmed({...run(h), 'amount': '1.25'}..remove('name'));
      await expectLater(
        gateway.ownReceipt(w4Scope, w4Command, 'people.payroll.prepare'),
        throwsFormatException,
      );
    },
  );
  test(
    'frozen calendar snapshot rejects forged duration, index and private fields',
    () async {
      final slot = {
        'date': '2026-09-30',
        'start_local': '2026-09-30T09:00:00',
        'end_local': '2026-09-30T17:00:00',
        'start_utc': '2026-09-30T03:30:00Z',
        'end_utc': '2026-09-30T11:30:00Z',
        'seconds': 28800,
      };
      final row = {
        ...h.scope(),
        'id': w4Id,
        'run_id': w4Id,
        'revision_id': w4Revision,
        'employee_id': w4Id,
        'input_digest': 'a' * 64,
        'section': 'planned_slots',
        'items': [
          {'position': 1, 'value': slot},
        ],
        'next_position': null,
      };
      h.response = row;
      expect(
        (await gateway.snapshot(w4Scope, w4Id, 'planned_slots'))['items'],
        hasLength(1),
      );
      expect(
        h.requests.last.url.path,
        endsWith('/rpc/people_payroll_snapshot'),
      );
      h.response = {
        ...row,
        'items': [
          {
            'position': 1,
            'value': {...slot, 'seconds': 28799},
          },
        ],
      };
      await expectLater(
        gateway.snapshot(w4Scope, w4Id, 'planned_slots'),
        throwsFormatException,
      );
      h.response = {
        ...row,
        'items': [
          {'position': 2, 'value': slot},
        ],
      };
      await expectLater(
        gateway.snapshot(w4Scope, w4Id, 'planned_slots'),
        throwsFormatException,
      );
      h.response = {
        ...row,
        'items': [
          {
            'position': 1,
            'value': {...slot, 'bank_number': 'private'},
          },
        ],
      };
      await expectLater(
        gateway.snapshot(w4Scope, w4Id, 'planned_slots'),
        throwsFormatException,
      );
    },
  );
  test(
    'assignment reads enforce exact employee identity and immutable date bounds',
    () async {
      final assignment = {
        'id': w4Id,
        'employee_id': w4Id,
        'component_id': w4Revision,
        'component_code': 'BASE',
        'component_name': 'Synthetic base',
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
        'reason': 'Synthetic assignment',
        'recorded_by': w4Scope.actorId,
        'recorded_at': '2026-09-30T00:00:00Z',
      };
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [assignment],
        'next_cursor': null,
      };
      expect(
        (await gateway.assignments(
          w4Scope,
          w4Id,
        )).items.single['component_code'],
        'BASE',
      );
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [
          {...assignment, 'employee_id': w4Revision},
        ],
        'next_cursor': null,
      };
      await expectLater(
        gateway.assignments(w4Scope, w4Id),
        throwsFormatException,
      );
    },
  );
  test(
    'minimal receipt requires the complete original command family',
    () async {
      h.response = h.confirmed({...h.scope(), 'id': w4Id, 'version': 1});
      await expectLater(
        gateway.ownReceipt(w4Scope, w4Command, 'people.payroll.prepare'),
        throwsA(anything),
      );
      h.response = h.confirmed({
        ...h.scope(),
        'id': w4Id,
        'version': 1,
        'kind': 'settings',
      });
      expect(
        await gateway.ownReceipt(
          w4Scope,
          w4Command,
          'people.payroll.configure',
        ),
        isNotNull,
      );
      await expectLater(
        gateway.ownReceipt(w4Scope, w4Command, 'people.payroll.view'),
        throwsFormatException,
      );
    },
  );
  test(
    'authorization validates actor and exact capability before private recovery',
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
    },
  );
}
