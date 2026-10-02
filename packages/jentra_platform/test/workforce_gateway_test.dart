import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';

import 'support/wave4_gateway_harness.dart';

Map<String, Object?> attendanceRow() => {
  'id': w4Id,
  'tenant_id': w4Scope.tenantId,
  'legal_entity_id': w4Scope.legalEntityId,
  'branch_id': w4Scope.branchId,
  'employee_id': w4Id,
  'version': 1,
  'status': 'draft',
  'submitted_by': null,
  'decided_by': null,
  'active_claim_id': null,
  'created_by': w4Scope.actorId,
  'created_at': '2026-09-30T01:00:00.123456+00:00',
  'revision': {
    'id': w4Revision,
    'version': 1,
    'calendar_version_id': w4Revision,
    'start_local': '2026-09-30T09:00:00',
    'start_offset_seconds': 19800,
    'end_local': '2026-09-30T17:00:00',
    'end_offset_seconds': 19800,
    'start_utc': '2026-09-30T03:30:00+00:00',
    'end_utc': '2026-09-30T11:30:00+00:00',
    'breaks': [],
    'gross_seconds': 28800,
    'break_seconds': 0,
    'payable_seconds': 28800,
    'raw_start_id': null,
    'raw_end_id': null,
    'reason': 'Synthetic attendance',
    'supersedes_revision_id': null,
    'recorded_by': w4Scope.actorId,
    'recorded_at': '2026-09-30T01:00:00.123456+00:00',
  },
};
Map<String, Object?> attendanceForm() => {
  'action': 'create',
  'id': w4Id,
  'employee_id': w4Id,
  'calendar_version_id': w4Revision,
  'start_local': '2026-09-30T09:00:00',
  'start_offset_seconds': 19800,
  'end_local': '2026-09-30T17:00:00',
  'end_offset_seconds': 19800,
  'breaks': [],
  'reason': 'Synthetic attendance',
};
CommandEnvelope<Map<String, Object?>> command(
  Map<String, Object?> payload, [
  int version = 0,
]) => CommandEnvelope(
  commandId: w4Command,
  idempotencyKey: w4Command,
  context: w4Scope,
  payload: payload,
  expectedEntityVersion: version,
  clientTimestamp: DateTime.utc(2026, 9, 30),
);

void main() {
  late Wave4GatewayHarness h;
  late SupabaseWorkforceGateway gateway;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabaseWorkforceGateway(h.client);
  });
  tearDown(() => h.dispose());
  test(
    'scoped attendance page validates ancestry and exact break totals',
    () async {
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [attendanceRow()],
        'next_cursor': null,
      };
      final rows = await gateway.attendance(w4Scope, w4Id);
      expect(rows.items.single.revision.payableSeconds, 28800);
      final args = jsonDecode(h.requests.last.body) as Map;
      expect(args['p_branch_id'], w4Scope.branchId);
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [
          {...attendanceRow(), 'employee_id': w4Revision},
        ],
        'next_cursor': null,
      };
      await expectLater(
        gateway.attendance(w4Scope, w4Id),
        throwsFormatException,
      );
    },
  );
  test(
    'command body is snapshotted before await and confirmation resolves offsets',
    () async {
      final input = attendanceForm();
      h.gate = Completer<void>();
      h.response = h.confirmed(attendanceRow());
      final future = gateway.execute(
        WorkforceCommandKind.attendance,
        command(input),
      );
      await Future<void>.delayed(Duration.zero);
      input['reason'] = 'Changed after submission';
      h.gate!.complete();
      expect((await future)['version'], 1);
      final body = jsonDecode(h.requests.last.body) as Map;
      expect((body['p_payload'] as Map)['reason'], 'Synthetic attendance');
    },
  );
  test('mismatched resolved interval preserves an uncertain result', () async {
    final row = attendanceRow();
    final revision = Map<String, Object?>.from(row['revision'] as Map);
    revision['calendar_version_id'] = w4Id;
    row['revision'] = revision;
    h.response = h.confirmed(row);
    await expectLater(
      gateway.execute(
        WorkforceCommandKind.attendance,
        command(attendanceForm()),
      ),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test('invalid payload is rejected without network traffic', () async {
    final input = attendanceForm()..['compensation'] = '100.00';
    await expectLater(
      gateway.execute(WorkforceCommandKind.attendance, command(input)),
      throwsFormatException,
    );
    expect(h.requests, isEmpty);
  });
  test('grant uses the current nonzero account version', () async {
    final payload = <String, Object?>{
      'action': 'adjust',
      'id': w4Id,
      'employee_id': w4Id,
      'policy_version_id': w4Revision,
      'effective_date': '2026-09-30',
      'source_key': 'synthetic-adjustment',
      'seconds': 3600,
      'reason': 'Synthetic adjustment',
    };
    h.response = h.confirmed({
      'id': w4Id,
      'employee_id': w4Id,
      'policy_id': w4Id,
      'policy_version_id': w4Revision,
      'source_kind': 'adjust',
      'source_key': 'synthetic-adjustment',
      'effective_date': '2026-09-30',
      'seconds': 3600,
      'account_version': 6,
      'available_seconds': 7200,
    });
    final result = await gateway.execute(
      WorkforceCommandKind.leaveGrant,
      command(payload, 5),
    );
    expect(result['account_version'], 6);
    expect((jsonDecode(h.requests.last.body) as Map)['p_expected_version'], 5);
  });
  test(
    'revoked access is a definite denial without private server text',
    () async {
      h.status = 403;
      h.response = {
        'code': '42501',
        'message': 'SYNTHETIC_PRIVATE_SERVER_TEXT',
      };
      await expectLater(
        gateway.attendance(w4Scope, w4Id),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', 'PERMISSION_DENIED')
              .having(
                (e) => e.message,
                'message',
                isNot(contains('PRIVATE_SERVER_TEXT')),
              ),
        ),
      );
    },
  );
  test(
    'authorization is bound to the requested actor and capability',
    () async {
      h.response = {
        'authorized': true,
        'actor_id': w4Scope.actorId,
        'employee_id': w4Id,
        'capability': 'people.leave.view',
      };
      await gateway.authorize(w4Scope, w4Id, 'people.leave.view');
      expect(h.requests.last.url.path, endsWith('/people_workforce_authorize'));
      h.response = {
        'authorized': true,
        'actor_id': w4Revision,
        'employee_id': w4Id,
        'capability': 'people.leave.view',
      };
      await expectLater(
        gateway.authorize(w4Scope, w4Id, 'people.leave.view'),
        throwsFormatException,
      );
      final before = h.requests.length;
      await expectLater(
        gateway.authorize(w4Scope, w4Id, 'finance.view'),
        throwsFormatException,
      );
      expect(h.requests.length, before);
    },
  );
  test(
    'policy directory stays bounded and history remains scoped to its policy',
    () async {
      final version = {
        'id': w4Revision,
        'version': 1,
        'start_date': '2026-09-01',
        'end_date_exclusive': '2027-09-01',
        'unit': 'hours',
        'day_seconds': 28800,
        'accrual_frequency': 'monthly',
        'accrual_seconds': 28800,
        'carry_cap_seconds': 72000,
        'expiry_days': 365,
        'eligible_types': ['permanent'],
        'allow_unpaid': false,
        'reason': 'Synthetic policy publication',
        'published_by': w4Scope.actorId,
        'published_at': '2026-09-01T00:00:00Z',
      };
      final policy = {
        'id': w4Id,
        'code': 'SYNTHETIC',
        'name': 'Synthetic leave',
        'version': 1,
        'versions': [version],
      };
      h.response = {
        ...h.scope(),
        'items': [policy],
        'next_cursor': null,
      };
      expect(
        (await gateway.policies(w4Scope)).items.single.latest.accrualSeconds,
        28800,
      );
      h.response = {
        ...h.scope(),
        'items': [
          {
            ...policy,
            'versions': [version, version],
          },
        ],
        'next_cursor': null,
      };
      await expectLater(gateway.policies(w4Scope), throwsFormatException);
      h.response = {
        ...h.scope(),
        'policy_id': w4Id,
        'items': [version],
        'next_cursor': null,
      };
      expect(
        (await gateway.policyVersions(w4Scope, w4Id)).items.single.id,
        w4Revision,
      );
      h.response = {
        ...h.scope(),
        'policy_id': w4Revision,
        'items': [version],
        'next_cursor': null,
      };
      await expectLater(
        gateway.policyVersions(w4Scope, w4Id),
        throwsFormatException,
      );
      h.response = {
        ...h.scope(),
        'policy_version_id': w4Revision,
        'policy': policy,
      };
      expect((await gateway.policyForVersion(w4Scope, w4Revision)).id, w4Id);
      h.response = {...h.scope(), 'policy_version_id': w4Id, 'policy': policy};
      await expectLater(
        gateway.policyForVersion(w4Scope, w4Revision),
        throwsFormatException,
      );
    },
  );
  test(
    'attendance detail verifies identity and bounded immutable history',
    () async {
      final history =
          Map<String, Object?>.from(attendanceRow()['revision'] as Map)
            ..remove('calendar_version_id')
            ..remove('start_local')
            ..remove('end_local')
            ..remove('start_offset_seconds')
            ..remove('end_offset_seconds')
            ..remove('gross_seconds')
            ..remove('break_seconds')
            ..remove('raw_start_id')
            ..remove('raw_end_id');
      h.response = {
        ...h.scope(),
        'entry': attendanceRow(),
        'history': [history],
        'next_cursor': null,
      };
      expect(
        (await gateway.attendanceDetail(
          w4Scope,
          w4Id,
        )).history.items.single.payableSeconds,
        28800,
      );
      h.response = {
        ...h.scope(),
        'entry': {...attendanceRow(), 'id': w4Revision},
        'history': [],
        'next_cursor': null,
      };
      await expectLater(
        gateway.attendanceDetail(w4Scope, w4Id),
        throwsFormatException,
      );
    },
  );
  test(
    'raw source and work ownership reject malformed or overlapping page identities',
    () async {
      final raw = {
        'id': w4Id,
        'source_system': 'Synthetic clock',
        'source_key': 'evt1',
        'observed_utc': '2026-09-30T03:30:00Z',
        'checksum': 'a' * 64,
        'imported_by': w4Scope.actorId,
        'imported_at': '2026-09-30T03:31:00Z',
      };
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [raw],
        'next_cursor': null,
      };
      expect(
        (await gateway.rawEvents(w4Scope, w4Id)).items.single.sourceKey,
        'evt1',
      );
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [raw, raw],
        'next_cursor': null,
      };
      await expectLater(
        gateway.rawEvents(w4Scope, w4Id),
        throwsFormatException,
      );
      h.response = {
        ...h.scope(),
        'employee_id': w4Id,
        'items': [
          {
            'id': w4Id,
            'source_kind': 'attendance',
            'source_id': w4Revision,
            'start_utc': '2026-09-30T03:30:00Z',
            'end_utc': '2026-09-30T11:30:00Z',
            'gross_seconds': 28800,
            'break_seconds': 1800,
            'payable_seconds': 27000,
            'active': true,
            'revoked_at': null,
            'calendar_version_id': w4Revision,
          },
        ],
        'next_cursor': null,
      };
      expect(
        (await gateway.workClaims(w4Scope, w4Id)).items.single.payableSeconds,
        27000,
      );
    },
  );
  test(
    'balance retains exact grant sources and rejects overdrawn arithmetic',
    () async {
      final grant = {
        'id': w4Id,
        'source_kind': 'accrual',
        'source_key': 'synthetic-month',
        'effective_date': '2026-09-01',
        'expiry_date': '2027-09-01',
        'seconds': 28800,
        'remaining_seconds': 25200,
        'policy_version_id': w4Revision,
        'recorded_at': '2026-09-01T00:00:00Z',
      };
      final balance = {
        ...h.scope(),
        'employee_id': w4Id,
        'policy_id': w4Revision,
        'as_of': '2026-09-30',
        'recorded_before': null,
        'account_version': 2,
        'available_seconds': 25200,
        'grants': [grant],
        'next_cursor': null,
      };
      h.response = balance;
      expect(
        (await gateway.leaveBalance(
          w4Scope,
          w4Id,
          w4Revision,
          CivilDate.parse('2026-09-30'),
        )).grants.single.remainingSeconds,
        25200,
      );
      h.response = {
        ...balance,
        'grants': [
          {...grant, 'remaining_seconds': 30000},
        ],
      };
      await expectLater(
        gateway.leaveBalance(
          w4Scope,
          w4Id,
          w4Revision,
          CivilDate.parse('2026-09-30'),
        ),
        throwsFormatException,
      );
    },
  );
}
