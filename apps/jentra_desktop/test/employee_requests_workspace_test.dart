import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_desktop/src/features/people/employee_requests_controller.dart';
import 'package:jentra_desktop/src/features/people/employee_requests_screen.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const requestId = '20000000-0000-0000-0000-000000000001';
const employeeId = '20000000-0000-0000-0000-000000000002';
const leaveId = '20000000-0000-0000-0000-000000000003';
Map<String, Object?> envelope() => {
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
};

class _Repository implements EmployeeRequestsRepository {
  bool failOnce = false, crossScope = false, denied = false, malformed = false;
  bool alreadyCancelled = false;
  Map<String, Object?> responseChanges = {};
  Completer<Map<String, Object?>>? delayed;
  final sent = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> access(TenantContext scope, String kind) async {
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'private SQL detail',
      );
    }
    return {
      ...envelope(),
      'actor_id': scope.actorId,
      'authorized': true,
      'kind': kind,
    };
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String kind,
    String? after,
  ) async => {
    ...envelope(),
    if (crossScope) 'branch_id': leaveId,
    'actor_id': scope.actorId,
    'kind': kind,
    'items': [
      {
        'id': requestId,
        'kind': kind,
        'employee_id': employeeId,
        'employee_name': 'Test colleague',
        'version': 1,
        'status': kind == 'attendance'
            ? 'pending_evidence'
            : 'cancellation_requested',
        'reason': 'Please review my request',
        'created_at': '2026-10-27T04:00:00Z',
        if (kind == 'attendance') ...{
          'action': 'capture',
          'entry_id': null,
          'source_version': null,
          'observed_at': '2026-10-27T03:30:00Z',
        } else ...{
          'source_id': leaveId,
          'source_version': alreadyCancelled ? 4 : 3,
          'source_status': alreadyCancelled ? 'cancelled' : 'approved',
          'requested_source_version': 3,
          'balance_version': 7,
          'start_local': '2026-10-28T09:00:00',
          'end_local': '2026-10-28T17:00:00',
        },
      },
    ],
    'next_cursor': null,
  };
  Map<String, Object?> acknowledgement(Map<String, Object?> request) => {
    ...envelope(),
    'employee_id': employeeId,
    'command_id': request['p_command_id'],
    'request_id': malformed ? leaveId : requestId,
    'kind': request['p_kind'],
    'version': 2,
    'status': request['p_decision'],
    'canonical_id': request['p_canonical_id'],
    'canonical_version': request['p_decision'] != 'resolved'
        ? null
        : request['p_kind'] == 'attendance'
        ? request['p_expected_canonical_version']
        : 4,
    'canonical_changed':
        request['p_kind'] == 'leave_cancel' &&
        request['p_decision'] == 'resolved' &&
        !alreadyCancelled,
    'payable_time_changed': false,
    ...responseChanges,
  };
  @override
  Future<Map<String, Object?>> resolve(
    TenantContext scope,
    Map<String, Object?> request,
  ) async {
    sent.add(Map.of(request));
    if (failOnce) {
      failOnce = false;
      throw TimeoutException('private transport detail');
    }
    return delayed?.future ?? Future.value(acknowledgement(request));
  }
}

EmployeeRequestsController _controller(
  _Repository repository, {
  bool approve = true,
}) => EmployeeRequestsController(
  scope: scope,
  repository: repository,
  workforce: null,
  online: true,
  monitor: false,
  permissions: {
    'people.attendance.view',
    'people.leave.view',
    if (approve) ...{'people.attendance.approve', 'people.leave.approve'},
  },
);

void main() {
  test(
    'foreign branch page is rejected without exposing employee content',
    () async {
      final repository = _Repository()..crossScope = true;
      final c = _controller(repository);
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.rows, isEmpty);
      expect(c.error, contains('could not be verified'));
    },
  );
  test('uncertain decision retries identical command and preserves target after offline masking', () async {
    final repository = _Repository()..failOnce = true;
    final c = _controller(repository);
    addTearDown(c.dispose);
    await c.refresh();
    await c.open(c.rows.single);
    await c.decide(approve: false, reason: 'Evidence could not be matched');
    final original = Map.of(c.pending!);
    expect(c.message, isNull);
    expect(c.error, isNot(contains('private transport')));
    c.setOnline(false);
    expect(c.selected, isNull);
    expect(c.rows, isEmpty);
    c.setOnline(true);
    await c.retry();
    expect(repository.sent, [original, original]);
    expect(c.pending, isNull);
    expect(c.message, contains('confirmed'));
  });
  test(
    'approved leave cancellation binds live leave and balance versions',
    () async {
      final repository = _Repository();
      final c = _controller(repository);
      addTearDown(c.dispose);
      await c.changeKind('leave_cancel');
      await c.open(c.rows.single);
      await c.decide(approve: true, reason: 'Approved schedule change');
      expect(repository.sent.single, containsPair('p_canonical_id', leaveId));
      expect(
        repository.sent.single,
        containsPair('p_expected_canonical_version', 3),
      );
      expect(
        repository.sent.single,
        containsPair('p_expected_balance_version', 7),
      );
      expect(c.pending, isNull);
      expect(c.message, contains('confirmed'));
    },
  );
  test(
    'malformed acknowledgement stays pending rather than reporting success',
    () async {
      final repository = _Repository()..malformed = true;
      final c = _controller(repository);
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(c.rows.single);
      await c.decide(approve: false, reason: 'No matching record');
      expect(c.pending, isNotNull);
      expect(c.message, isNull);
      await c.decide(approve: false, reason: 'Changed payload');
      expect(repository.sent, hasLength(1));
    },
  );
  test(
    'an earlier success is cleared before another decision becomes uncertain',
    () async {
      final repository = _Repository();
      final c = _controller(repository);
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(c.rows.single);
      await c.decide(approve: false, reason: 'First review complete');
      expect(c.message, contains('confirmed'));
      await c.refresh();
      await c.open(c.rows.single);
      repository.failOnce = true;
      await c.decide(approve: false, reason: 'Another review');
      expect(c.pending, isNotNull);
      expect(c.message, isNull);
    },
  );
  for (final changes in <Map<String, Object?>>[
    {'canonical_version': 99},
    {'canonical_changed': false},
    {'actor_id': employeeId},
  ]) {
    test(
      'contradictory leave acknowledgement remains unconfirmed: $changes',
      () async {
        final repository = _Repository()..responseChanges = changes;
        final c = _controller(repository);
        addTearDown(c.dispose);
        await c.changeKind('leave_cancel');
        await c.open(c.rows.single);
        await c.decide(approve: true, reason: 'Approved schedule change');
        expect(c.pending, isNotNull);
        expect(c.message, isNull);
        expect(c.error, contains('could not be verified'));
      },
    );
  }
  test(
    'decline confirmation cannot claim a canonical revision or effect',
    () async {
      final repository = _Repository()
        ..responseChanges = {'canonical_version': 4, 'canonical_changed': true};
      final c = _controller(repository);
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(c.rows.single);
      await c.decide(approve: false, reason: 'No matching approved record');
      expect(c.pending, isNotNull);
      expect(c.message, isNull);
    },
  );
  test('already cancelled leave links the exact existing revision without another reversal', () async {
    final repository = _Repository()..alreadyCancelled = true;
    final c = _controller(repository);
    addTearDown(c.dispose);
    await c.changeKind('leave_cancel');
    await c.open(c.rows.single);
    await c.decide(approve: true, reason: 'Cancellation was already processed');
    expect(repository.sent.single['p_expected_canonical_version'], 4);
    expect(c.pending, isNull);
    expect(c.message, contains('confirmed'));
  });
  test(
    'approved attendance acknowledgement binds its selected canonical revision',
    () async {
      final repository = _Repository()
        ..responseChanges = {'canonical_version': 4};
      final c = _controller(repository);
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(c.rows.single);
      final entry = AttendanceEntry.fromJson({
        'id': leaveId,
        ...envelope(),
        'employee_id': employeeId,
        'version': 3,
        'status': 'approved',
        'submitted_by': scope.actorId,
        'decided_by': leaveId,
        'active_claim_id': requestId,
        'created_by': scope.actorId,
        'created_at': '2026-10-27T04:01:00Z',
        'revision': {
          'id': requestId,
          'version': 1,
          'calendar_version_id': leaveId,
          'start_local': '2026-10-27T03:00:00',
          'end_local': '2026-10-27T04:00:00',
          'start_offset_seconds': 0,
          'end_offset_seconds': 0,
          'start_utc': '2026-10-27T03:00:00Z',
          'end_utc': '2026-10-27T04:00:00Z',
          'breaks': [],
          'gross_seconds': 3600,
          'break_seconds': 0,
          'payable_seconds': 3600,
          'reason': 'Independent recorded attendance',
          'raw_start_id': null,
          'raw_end_id': null,
          'supersedes_revision_id': null,
          'recorded_by': scope.actorId,
          'recorded_at': '2026-10-27T04:01:00Z',
        },
      });
      c.attendance = [entry];
      c.chooseAttendance(entry);
      await c.decide(
        approve: true,
        reason: 'Matches independently approved record',
      );
      expect(repository.sent.single['p_expected_canonical_version'], 3);
      expect(c.pending, isNotNull);
      expect(c.message, isNull);
      repository.responseChanges = {};
      await c.retry();
      expect(c.pending, isNull);
      expect(c.message, contains('confirmed'));
    },
  );
  test(
    'revoked permission clears bodies and blocks subsequent decisions',
    () async {
      final repository = _Repository();
      final c = _controller(repository);
      addTearDown(c.dispose);
      await c.refresh();
      await c.open(c.rows.single);
      repository.denied = true;
      await c.checkAccess();
      expect(c.current, isFalse);
      expect(c.selected, isNull);
      expect(c.rows, isEmpty);
      expect(c.error, isNot(contains('SQL')));
      await c.decide(approve: false, reason: 'Must not send');
      expect(repository.sent, isEmpty);
    },
  );
  test(
    'late acknowledgement after disposal cannot revive private state',
    () async {
      final repository = _Repository()..delayed = Completer();
      final c = _controller(repository);
      await c.refresh();
      await c.open(c.rows.single);
      final work = c.decide(approve: false, reason: 'Review complete');
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      repository.delayed!.complete(
        repository.acknowledgement(repository.sent.single),
      );
      await work;
      expect(c.selected, isNull);
      expect(c.pending, isNull);
      expect(c.message, isNull);
    },
  );
  testWidgets('view-only reviewer can read but cannot record a decision', (
    tester,
  ) async {
    final c = _controller(_Repository(), approve: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EmployeeRequestsWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test colleague'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A colleague with approval permission must record the decision.',
      ),
      findsOneWidget,
    );
    final decline = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Decline request'),
    );
    expect(decline.onPressed, isNull);
  });
}
