import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:jentra_employee/src/data/employee_document_export.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_self_service.dart';

import 'employee_fixture.dart';

const selfIdentity = EmployeeIdentity(
  workspace: fixtureWorkspace,
  actorId: fixtureActor,
  employeeId: fixtureEmployee,
  displayName: 'Employee',
);
const selfRecordId = '30000000-0000-4000-8000-000000000001';
const selfSecondId = '30000000-0000-4000-8000-000000000002';
const selfCommandId = '30000000-0000-4000-8000-000000000003';

Map<String, Object?> selfEnvelope([EmployeeIdentity identity = selfIdentity]) =>
    {
      'tenant_id': identity.workspace.tenantId,
      'legal_entity_id': identity.workspace.legalEntityId,
      'branch_id': identity.workspace.branchId,
      'employee_id': identity.employeeId,
    };

Map<String, Object?> serviceRow(EmployeeService service) => switch (service) {
  EmployeeService.attendance => {
    'id': selfRecordId,
    'version': 1,
    'status': 'approved',
    'revision': {
      'start_local': '2026-10-25T09:00:00',
      'end_local': '2026-10-25T17:00:00',
    },
  },
  EmployeeService.attendanceRequests => {
    'id': selfRecordId,
    'version': 1,
    'action': 'capture',
    'status': 'pending_evidence',
    'observed_at': '2026-10-25T03:30:00Z',
    'reason': 'Clock evidence',
  },
  EmployeeService.leavePolicies => {
    'id': selfRecordId,
    'version': 1,
    'policy_version_id': selfSecondId,
    'calendar_version_id': selfSecondId,
    'name': 'Annual leave',
    'timezone': 'Asia/Colombo',
    'as_of': '2026-10-25',
  },
  EmployeeService.leaveRequests => {
    'id': selfRecordId,
    'version': 1,
    'status': 'submitted',
    'start_local': '2026-10-27T09:00:00',
    'end_local': '2026-10-27T17:00:00',
    'charge_seconds': 28800,
    'reason': 'Family leave',
  },
  EmployeeService.payslips => {
    'id': selfRecordId,
    'run_id': selfSecondId,
    'calculation_id': selfSecondId,
    'employee_id': fixtureEmployee,
    'synthetic': true,
    'currency_code': 'LKR',
    'revision_digest': List.filled(64, 'a').join(),
    'input_digest': List.filled(64, 'b').join(),
    'issued_at': '2026-10-25T03:30:00Z',
    'start_date': '2026-10-01',
    'end_date_exclusive': '2026-11-01',
    'gross': '100000.000000',
    'deductions': '10000.000000',
    'employer_cost': '12000.000000',
    'net': '90000.000000',
    'payslip_revision_id': selfSecondId,
    'lines': [
      {'code': 'BASIC', 'classification': 'earning', 'amount': '100000.000000'},
    ],
  },
  EmployeeService.cases => {
    'id': selfRecordId,
    'version': 1,
    'category': 'general',
    'status': 'open',
    'subject': 'HR question',
    'owner_user_id': null,
    'payslip_id': null,
    'payslip_revision_id': null,
    'created_at': '2026-10-25T03:30:00Z',
    'updated_at': '2026-10-25T03:30:00Z',
    'messages': [
      {
        'id': selfSecondId,
        'body': 'Private question',
        'author_kind': 'employee',
        'created_at': '2026-10-25T03:30:00Z',
      },
    ],
    'history': [
      {
        'id': selfSecondId,
        'status': 'open',
        'created_at': '2026-10-25T03:30:00Z',
      },
    ],
  },
  EmployeeService.documents => {
    'id': selfRecordId,
    'version': 2,
    'publication_version': 3,
    'label': 'Published document',
    'mime': 'application/pdf',
    'byte_size': 3,
    'checksum': sha256.convert([1, 2, 3]).toString(),
    'published_at': '2026-10-25T03:30:00Z',
  },
  EmployeeService.inbox => {
    'id': selfRecordId,
    'version': 1,
    'notification_type': 'people.employee.leave',
    'recipient_id': fixtureActor,
    'status': 'unread',
    'created_at': '2026-10-25T03:30:00Z',
    'source_context': {'destination': 'leave'},
  },
};

EmployeeServicePage servicePage(EmployeeService service) =>
    EmployeeServicePage([EmployeeServiceRecord(serviceRow(service))], null);

Map<String, Object?> serviceReceipt(
  EmployeeIdentity identity,
  String rpc,
  Map<String, Object?> parameters,
) {
  final payload = parameters['p_payload'] == null
      ? <String, Object?>{}
      : selfMap(parameters['p_payload']);
  final target = parameters['p_request_id'] ?? payload['id'];
  return {
    ...selfEnvelope(identity),
    'command_id': parameters['p_command_id'],
    if (rpc == 'employee_case_command') 'id': target else 'request_id': target,
    'version': rpc == 'employee_self_leave_intent'
        ? (parameters['p_expected_version']! as int) +
              (parameters['p_action'] == 'withdraw' ? 1 : 0)
        : rpc == 'employee_case_command' && parameters['p_action'] == 'reply'
        ? (payload['expected_version']! as int) + 1
        : 1,
    'status': switch (rpc) {
      'employee_self_attendance_request' => 'pending_evidence',
      'employee_self_leave_submit' => 'submitted',
      'employee_self_leave_intent' =>
        parameters['p_action'] == 'withdraw'
            ? 'withdrawn'
            : 'cancellation_requested',
      _ => 'open',
    },
    if (rpc == 'employee_self_attendance_request')
      'payable_time_changed': false,
    if (rpc == 'employee_self_leave_submit') ...{
      'approval_required': true,
      'charge_seconds': 28800,
    },
    if (rpc == 'employee_self_leave_intent')
      'approval_required': parameters['p_action'] != 'withdraw',
  };
}

class SelfGateway implements EmployeeSelfServiceGateway {
  Future<EmployeeServicePage> Function(
    EmployeeIdentity,
    EmployeeService,
    String?,
  )?
  onPage;
  Future<EmployeeLeaveBalance> Function(String, String)? onBalance;
  Future<EmployeeServiceRecord> Function(EmployeeService, String)? onDetail;
  Future<Map<String, Object?>> Function(
    EmployeeIdentity,
    String,
    Map<String, Object?>,
  )?
  onCommand;
  Future<EmployeeReceiptLookup> Function(String, String, String)? onReceipt;
  int sends = 0, reads = 0, documentReads = 0;
  String? sentRpc;
  Map<String, Object?>? sent;
  EmployeeReceiptLookup lookup = const EmployeeReceiptLookup(
    receipt: null,
    abandoned: false,
  );
  @override
  Future<EmployeeServicePage> page(
    EmployeeIdentity identity,
    EmployeeService service, {
    String? after,
  }) async {
    reads++;
    return onPage == null
        ? servicePage(service)
        : await onPage!(identity, service, after);
  }

  @override
  Future<EmployeeLeaveBalance> balance(
    EmployeeIdentity identity,
    String policyId,
    String asOf,
  ) async => onBalance == null
      ? EmployeeLeaveBalance(
          policyId: policyId,
          asOf: asOf,
          availableSeconds: 288000,
          reservedSeconds: 0,
          version: 1,
        )
      : await onBalance!(policyId, asOf);
  @override
  Future<EmployeeServiceRecord> detail(
    EmployeeIdentity identity,
    EmployeeService service,
    String id,
  ) async => onDetail == null
      ? EmployeeServiceRecord(serviceRow(service))
      : await onDetail!(service, id);
  @override
  Future<Map<String, Object?>> command(
    EmployeeIdentity identity,
    String rpc,
    Map<String, Object?> parameters, {
    bool Function()? stillAuthorized,
  }) async {
    sends++;
    sentRpc = rpc;
    sent = parameters;
    return onCommand == null
        ? serviceReceipt(identity, rpc, parameters)
        : await onCommand!(identity, rpc, parameters);
  }

  @override
  Future<EmployeeReceiptLookup> receipt(
    EmployeeIdentity identity,
    String rpc,
    String commandId,
    String requestId, {
    bool Function()? stillAuthorized,
  }) async =>
      onReceipt == null ? lookup : await onReceipt!(rpc, commandId, requestId);
  @override
  Future<void> markNoticeRead(
    EmployeeIdentity identity,
    EmployeeServiceRecord notice,
    String commandId, {
    bool Function()? stillAuthorized,
  }) async {}
  @override
  Future<EmployeePrivateDocument> document(
    EmployeeIdentity identity,
    EmployeeServiceRecord document,
  ) async {
    documentReads++;
    return EmployeePrivateDocument(
      Uint8List.fromList([1, 2, 3]),
      'application/pdf',
    );
  }
}

class TestDocumentExporter implements EmployeeDocumentExporter {
  Future<void> Function()? onChooser;
  void Function()? afterAuthorization;
  bool cancelled = false;
  int writes = 0;
  @override
  bool get supported => true;
  @override
  Future<bool> save({
    required Uint8List bytes,
    required String mimeType,
    required Future<bool> Function() reauthorize,
    required bool Function() stillAuthorized,
  }) async {
    await onChooser?.call();
    if (cancelled) return false;
    if (!await reauthorize()) return false;
    afterAuthorization?.call();
    if (!stillAuthorized()) return false;
    writes++;
    return true;
  }
}
