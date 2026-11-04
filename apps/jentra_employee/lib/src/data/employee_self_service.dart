import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'employee_gateway.dart';

/// These endpoints derive the employee from the authenticated account link.
/// An employee ID is never a selector sent by this client.
enum EmployeeService {
  attendance,
  attendanceRequests,
  leavePolicies,
  leaveRequests,
  payslips,
  cases,
  documents,
  inbox,
}

final class EmployeeServiceRecord {
  EmployeeServiceRecord(Map<String, Object?> value)
    : values = selfImmutableMap(value) {
    selfUuid(value['id']);
    if (value['version'] != null) selfInteger(value['version'], minimum: 1);
  }
  final Map<String, Object?> values;
  String get id => values['id']! as String;
  int get version => selfInteger(values['version'], minimum: 1);
  String text(String key, {int max = 4000}) => selfText(values[key], max: max);
  String? optionalText(String key, {int max = 4000}) =>
      values[key] == null ? null : selfText(values[key], max: max);
  int integer(String key) => selfInteger(values[key]);
  Map<String, Object?> toJson() => Map.of(values);
}

final class EmployeeServicePage {
  const EmployeeServicePage(this.items, this.nextCursor);
  final List<EmployeeServiceRecord> items;
  final String? nextCursor;
}

final class EmployeeLeaveBalance {
  const EmployeeLeaveBalance({
    required this.policyId,
    required this.asOf,
    required this.availableSeconds,
    required this.reservedSeconds,
    required this.version,
  });
  final String policyId, asOf;
  final int availableSeconds, reservedSeconds, version;
}

final class EmployeePrivateDocument {
  const EmployeePrivateDocument(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

final class EmployeeReceiptLookup {
  const EmployeeReceiptLookup({required this.receipt, required this.abandoned});
  final Map<String, Object?>? receipt;
  final bool abandoned;
}

abstract interface class EmployeeSelfServiceGateway {
  Future<EmployeeServicePage> page(
    EmployeeIdentity identity,
    EmployeeService service, {
    String? after,
  });
  Future<EmployeeLeaveBalance> balance(
    EmployeeIdentity identity,
    String policyId,
    String asOf,
  );
  Future<EmployeeServiceRecord> detail(
    EmployeeIdentity identity,
    EmployeeService service,
    String id,
  );
  Future<Map<String, Object?>> command(
    EmployeeIdentity identity,
    String rpc,
    Map<String, Object?> parameters, {
    bool Function()? stillAuthorized,
  });
  Future<EmployeeReceiptLookup> receipt(
    EmployeeIdentity identity,
    String rpc,
    String commandId,
    String requestId, {
    bool Function()? stillAuthorized,
  });
  Future<void> markNoticeRead(
    EmployeeIdentity identity,
    EmployeeServiceRecord notice,
    String commandId, {
    bool Function()? stillAuthorized,
  });
  Future<EmployeePrivateDocument> document(
    EmployeeIdentity identity,
    EmployeeServiceRecord document,
  );
}

Map<String, Object?> selfMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected an object.');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?> selfImmutableMap(Map<String, Object?> value) =>
    Map.unmodifiable({
      for (final entry in value.entries)
        entry.key: _immutableValue(entry.value),
    });

Object? _immutableValue(Object? value) => switch (value) {
  Map() => selfImmutableMap(selfMap(value)),
  List() => List<Object?>.unmodifiable(value.map(_immutableValue)),
  _ => value,
};

String selfUuid(Object? value) {
  if (value is! String ||
      !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(value)) {
    throw const FormatException('Expected a UUID.');
  }
  return value;
}

String selfText(Object? value, {int max = 4000}) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw const FormatException('Expected bounded text.');
  }
  return value;
}

int selfInteger(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum || value > 9007199254740991) {
    throw const FormatException('Expected a bounded integer.');
  }
  return value;
}

String selfDate(Object? value) {
  final text = selfText(value, max: 10);
  final parsed = DateTime.tryParse(text);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
      parsed == null ||
      parsed.toIso8601String().substring(0, 10) != text) {
    throw const FormatException('Invalid calendar date.');
  }
  return text;
}

String selfTimestamp(Object? value, {bool local = false}) {
  final text = selfText(value, max: 40);
  if (DateTime.tryParse(text) == null ||
      !text.contains('T') ||
      (!local && !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(text))) {
    throw const FormatException('Invalid timestamp.');
  }
  selfDate(text.substring(0, 10));
  return text;
}

String selfMoney(Object? value) {
  final text = selfText(value, max: 24);
  if (!RegExp(r'^-?(?:0|[1-9]\d{0,13})(?:\.\d{1,6})?$').hasMatch(text)) {
    throw const FormatException('Invalid decimal amount.');
  }
  return text;
}

void validateEmployeeServiceRecord(
  EmployeeServiceRecord record,
  EmployeeService service,
  EmployeeIdentity identity, {
  bool detail = false,
}) {
  final row = record.values;
  if (row['employee_id'] != null && row['employee_id'] != identity.employeeId ||
      row['tenant_id'] != null &&
          row['tenant_id'] != identity.workspace.tenantId ||
      row['legal_entity_id'] != null &&
          row['legal_entity_id'] != identity.workspace.legalEntityId ||
      row['branch_id'] != null &&
          row['branch_id'] != identity.workspace.branchId) {
    throw const FormatException('Foreign employee scope.');
  }
  switch (service) {
    case EmployeeService.leavePolicies:
      selfUuid(row['policy_version_id']);
      selfUuid(row['calendar_version_id']);
      selfInteger(row['version'], minimum: 1);
      record.text('name', max: 160);
      record.text('timezone', max: 100);
      selfDate(row['as_of']);
    case EmployeeService.leaveRequests:
      selfInteger(row['version'], minimum: 1);
      if (!{
        'created',
        'submitted',
        'approved',
        'rejected',
        'cancelled',
        'withdrawn',
      }.contains(row['status'])) {
        throw const FormatException('Unknown leave state.');
      }
      selfTimestamp(row['start_local'], local: true);
      selfTimestamp(row['end_local'], local: true);
      record.integer('charge_seconds');
      record.optionalText('reason', max: 1000);
      if (row['cancellation_request'] != null) {
        final intent = selfMap(row['cancellation_request']);
        selfUuid(intent['id']);
        selfTimestamp(intent['requested_at']);
        if (!{
          'cancellation_requested',
          'resolved',
          'declined',
        }.contains(intent['status'])) {
          throw const FormatException('Unknown cancellation state.');
        }
        if (intent['resolution'] != null) {
          validateEmployeeResolution(intent['resolution']);
        }
      }
    case EmployeeService.payslips:
      if (row['employee_id'] != identity.employeeId ||
          row['synthetic'] != true ||
          !RegExp(r'^[A-Z]{3}$')
              .hasMatch(record.text('currency_code', max: 3))) {
        throw const FormatException('Invalid payslip source.');
      }
      for (final key in ['run_id', 'calculation_id']) {
        selfUuid(row[key]);
      }
      for (final key in ['revision_digest', 'input_digest']) {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(record.text(key, max: 64))) {
          throw const FormatException('Invalid payslip digest.');
        }
      }
      selfDate(row['start_date']);
      selfDate(row['end_date_exclusive']);
      selfTimestamp(row['issued_at']);
      for (final key in ['gross', 'deductions', 'employer_cost', 'net']) {
        selfMoney(row[key]);
      }
      if (detail) {
        selfUuid(row['payslip_revision_id']);
        final lines = row['lines'];
        if (lines is! List || lines.length > 1000) {
          throw const FormatException('Invalid payslip components.');
        }
        for (final value in lines) {
          final line = selfMap(value);
          selfText(line['code'], max: 80);
          selfMoney(line['amount']);
          if (!{
            'earning',
            'deduction',
            'employer_cost',
          }.contains(line['classification'])) {
            throw const FormatException('Invalid payslip component type.');
          }
        }
      }
    case EmployeeService.cases:
      selfInteger(row['version'], minimum: 1);
      record.text('subject', max: 160);
      if (!{
            'open',
            'in_progress',
            'resolved',
            'closed',
          }.contains(row['status']) ||
          !{'general', 'payroll'}.contains(row['category'])) {
        throw const FormatException('Unknown case state.');
      }
      if (row['owner_user_id'] != null) selfUuid(row['owner_user_id']);
      selfTimestamp(row['created_at']);
      selfTimestamp(row['updated_at']);
      if (row['category'] == 'payroll') {
        selfUuid(row['payslip_id']);
        selfUuid(row['payslip_revision_id']);
      }
      if (detail) {
        final messages = row['messages'];
        final history = row['history'];
        if (messages is! List ||
            messages.length > 200 ||
            history is! List ||
            history.length > 1000) {
          throw const FormatException('Invalid case thread.');
        }
        for (final value in messages) {
          final message = selfMap(value);
          selfUuid(message['id']);
          selfTimestamp(message['created_at']);
          selfText(message['body'], max: 4000);
          if (!{'employee', 'hr'}.contains(message['author_kind'])) {
            throw const FormatException('Unknown case author.');
          }
        }
        for (final value in history) {
          final event = selfMap(value);
          selfUuid(event['id']);
          selfTimestamp(event['created_at']);
          if (!{
            'open',
            'in_progress',
            'resolved',
            'closed',
          }.contains(event['status'])) {
            throw const FormatException('Unknown case history.');
          }
        }
      }
    case EmployeeService.documents:
      selfInteger(row['version'], minimum: 1);
      record.text('label', max: 160);
      selfInteger(row['publication_version'], minimum: 1);
      if (!{
        'application/pdf',
        'image/png',
        'image/jpeg',
        'text/plain',
      }.contains(row['mime'])) {
        throw const FormatException('Unsupported document type.');
      }
      selfInteger(row['byte_size'], minimum: 1);
      if (record.integer('byte_size') > 10 * 1024 * 1024) {
        throw const FormatException('Oversized document.');
      }
      if (!RegExp(r'^[a-f0-9]{64}$')
          .hasMatch(record.text('checksum', max: 64))) {
        throw const FormatException('Invalid document checksum.');
      }
      selfTimestamp(row['published_at']);
    case EmployeeService.attendance:
      selfInteger(row['version'], minimum: 1);
      if (!{
        'draft',
        'submitted',
        'approved',
        'rejected',
        'cancelled',
      }.contains(row['status'])) {
        throw const FormatException('Unknown attendance state.');
      }
      final revision = selfMap(row['revision']);
      selfTimestamp(revision['start_local'], local: true);
      selfTimestamp(revision['end_local'], local: true);
    case EmployeeService.attendanceRequests:
      if (!{
        'pending_evidence',
        'resolved',
        'declined',
      }.contains(row['status'])) {
        throw const FormatException('Unknown attendance request state.');
      }
      selfInteger(row['version'], minimum: 1);
      if (!{'capture', 'correction'}.contains(row['action'])) {
        throw const FormatException('Unknown evidence type.');
      }
      selfTimestamp(row['observed_at']);
      record.text('reason', max: 1000);
      if (row['resolution'] != null) {
        validateEmployeeResolution(row['resolution']);
      }
    case EmployeeService.inbox:
      selfInteger(row['version'], minimum: 1);
      selfTimestamp(row['created_at']);
      if (!record.text('notification_type', max: 80).startsWith('people.') ||
          row['recipient_id'] != identity.actorId ||
          !{'read', 'unread'}.contains(row['status'])) {
        throw const FormatException('Foreign or invalid HR notice.');
      }
      if (row['source_context'] != null) selfMap(row['source_context']);
  }
}

void validateEmployeeResolution(Object? value) {
  final resolution = selfMap(value);
  selfUuid(resolution['id']);
  if (!{'resolved', 'declined'}.contains(resolution['status'])) {
    throw const FormatException('Unknown request resolution.');
  }
  selfText(resolution['reason'], max: 1000);
  selfTimestamp(resolution['recorded_at']);
  if (resolution['canonical_id'] != null) selfUuid(resolution['canonical_id']);
  if (resolution['canonical_version'] != null) {
    selfInteger(resolution['canonical_version'], minimum: 1);
  }
}

Map<String, Object?> selfScope(EmployeeIdentity identity) => {
  'p_tenant_id': identity.workspace.tenantId,
  'p_legal_entity_id': identity.workspace.legalEntityId,
  'p_branch_id': identity.workspace.branchId,
};

void validateSelfScope(Map<String, Object?> json, EmployeeIdentity identity) {
  if (json['tenant_id'] != identity.workspace.tenantId ||
      json['legal_entity_id'] != identity.workspace.legalEntityId ||
      json['branch_id'] != identity.workspace.branchId ||
      json['employee_id'] != identity.employeeId) {
    throw const FormatException('Employee response scope mismatch.');
  }
}

EmployeeServicePage parseEmployeeServicePage(
  Object? value,
  EmployeeIdentity identity,
  EmployeeService service, {
  String? after,
}) {
  final json = selfMap(value);
  validateSelfScope(json, identity);
  final raw = json['items'];
  if (raw is! List || raw.length > 100) {
    throw const FormatException('Invalid employee page.');
  }
  final items = <EmployeeServiceRecord>[];
  for (final item in raw) {
    final row = selfMap(item);
    if (row['employee_id'] != null &&
        row['employee_id'] != identity.employeeId) {
      throw const FormatException('Foreign employee record.');
    }
    if (row['tenant_id'] != null &&
            row['tenant_id'] != identity.workspace.tenantId ||
        row['legal_entity_id'] != null &&
            row['legal_entity_id'] != identity.workspace.legalEntityId ||
        row['branch_id'] != null &&
            row['branch_id'] != identity.workspace.branchId) {
      throw const FormatException('Foreign employee scope.');
    }
    final record = EmployeeServiceRecord(row);
    validateEmployeeServiceRecord(record, service, identity);
    items.add(record);
  }
  final cursor = json['next_cursor'] == null
      ? null
      : selfUuid(json['next_cursor']);
  if (items.map((item) => item.id).toSet().length != items.length ||
      cursor != null && cursor == after) {
    throw const FormatException('Inconsistent employee page.');
  }
  return EmployeeServicePage(List.unmodifiable(items), cursor);
}

final class SupabaseEmployeeSelfServiceGateway
    implements EmployeeSelfServiceGateway {
  SupabaseEmployeeSelfServiceGateway(
    this.client, {
    EmployeeGateway? identityGateway,
  }) : identityGateway = identityGateway ?? SupabaseEmployeeGateway(client);
  final SupabaseClient client;
  final EmployeeGateway identityGateway;

  Future<void> _authorize(EmployeeIdentity identity) async {
    if (client.auth.currentUser?.id != identity.actorId) {
      throw const EmployeeFailure('SESSION_CHANGED', 'Your account changed.');
    }
    final accepted = await identityGateway.resolveIdentity(identity.workspace);
    if (client.auth.currentUser?.id != identity.actorId ||
        accepted.key != identity.key) {
      throw const EmployeeFailure(
        'SESSION_CHANGED',
        'Your employee link changed.',
      );
    }
  }

  void _same(EmployeeIdentity identity) {
    if (client.auth.currentUser?.id != identity.actorId) {
      throw const EmployeeFailure('SESSION_CHANGED', 'Your account changed.');
    }
  }

  Future<T> _safe<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on PostgrestException catch (error) {
      throw switch (error.code) {
        '42501' when error.message == 'EMPLOYEE_MFA_REQUIRED' =>
          const EmployeeFailure(
            'MFA_REQUIRED',
            'Verify your authenticator to use this employee service.',
          ),
        '42501' when error.message == 'EMPLOYEE_SESSION_REQUIRED' =>
          const EmployeeFailure(
            'AUTHENTICATION_REQUIRED',
            'Sign in again to verify this session.',
          ),
        '40001' => const EmployeeFailure(
          'VERSION_CONFLICT',
          'Refresh the changed record.',
        ),
        '22023' when error.message.contains('COMMAND_REUSED') =>
          const EmployeeFailure(
            'IDEMPOTENCY_MISMATCH',
            'Keep the original request for reconciliation.',
          ),
        '22023' || '23514' => const EmployeeFailure(
          'VALIDATION_ERROR',
          'Check the request and current policy.',
        ),
        _ => employeeFailure(error),
      };
    } on Object catch (error) {
      throw employeeFailure(error);
    }
  }

  @override
  Future<EmployeeServicePage> page(
    EmployeeIdentity identity,
    EmployeeService service, {
    String? after,
  }) => _safe(() async {
    await _authorize(identity);
    _same(identity);
    if (after != null) selfUuid(after);
    if (service == EmployeeService.inbox) {
      var query = client
          .schema('api')
          .from('my_notifications')
          .select()
          .eq('tenant_id', identity.workspace.tenantId)
          .eq('legal_entity_id', identity.workspace.legalEntityId)
          .eq('branch_id', identity.workspace.branchId)
          .eq('recipient_id', identity.actorId)
          .like('notification_type', 'people.%');
      if (after != null) query = query.lt('id', after);
      final rows = await query.order('id', ascending: false).limit(25);
      _same(identity);
      return parseEmployeeServicePage(
        {
          'tenant_id': identity.workspace.tenantId,
          'legal_entity_id': identity.workspace.legalEntityId,
          'branch_id': identity.workspace.branchId,
          'employee_id': identity.employeeId,
          'items': rows,
          'next_cursor': rows.length == 25 ? rows.last['id'] : null,
        },
        identity,
        service,
        after: after,
      );
    }
    final rpc = switch (service) {
      EmployeeService.attendance => 'employee_self_attendance',
      EmployeeService.attendanceRequests => 'employee_self_attendance_requests',
      EmployeeService.leavePolicies => 'employee_self_leave_policies',
      EmployeeService.leaveRequests => 'employee_self_leave_requests',
      EmployeeService.payslips => 'employee_self_payslips',
      EmployeeService.cases => 'employee_cases_list',
      EmployeeService.documents => 'employee_documents_list',
      EmployeeService.inbox => throw StateError('Handled above.'),
    };
    // The server derives the workplace-local applicability date for policies.
    final result = await client
        .schema('api')
        .rpc(rpc, params: {...selfScope(identity), 'p_after': after});
    _same(identity);
    return parseEmployeeServicePage(result, identity, service, after: after);
  });

  @override
  Future<EmployeeLeaveBalance> balance(
    EmployeeIdentity identity,
    String policyId,
    String asOf,
  ) => _safe(() async {
    await _authorize(identity);
    _same(identity);
    selfUuid(policyId);
    final json = selfMap(
      await client
          .schema('api')
          .rpc(
            'employee_self_leave_balance',
            params: {
              ...selfScope(identity),
              'p_policy_id': policyId,
              'p_as_of': asOf,
            },
          ),
    );
    _same(identity);
    validateSelfScope(json, identity);
    if (json['policy_id'] != policyId ||
        json['as_of'] != asOf ||
        json['approval_required'] != true) {
      throw const FormatException('Balance scope mismatch.');
    }
    return EmployeeLeaveBalance(
      policyId: policyId,
      asOf: asOf,
      availableSeconds: selfInteger(json['available_seconds']),
      reservedSeconds: selfInteger(json['reserved_seconds']),
      version: selfInteger(json['account_version']),
    );
  });

  @override
  Future<EmployeeServiceRecord> detail(
    EmployeeIdentity identity,
    EmployeeService service,
    String id,
  ) => _safe(() async {
    await _authorize(identity);
    _same(identity);
    selfUuid(id);
    final rpc = switch (service) {
      EmployeeService.cases => 'employee_case_detail',
      EmployeeService.payslips => 'employee_self_payslip',
      _ => throw const FormatException('Unsupported detail.'),
    };
    final json = selfMap(
      await client
          .schema('api')
          .rpc(
            rpc,
            params: {
              ...selfScope(identity),
              service == EmployeeService.cases ? 'p_case_id' : 'p_payslip_id':
                  id,
            },
          ),
    );
    _same(identity);
    validateSelfScope(json, identity);
    final row = selfMap(
      json[service == EmployeeService.cases ? 'case' : 'payslip'],
    );
    if (row['id'] != id ||
        row['employee_id'] != null &&
            row['employee_id'] != identity.employeeId) {
      throw const FormatException('Detail subject mismatch.');
    }
    final record = EmployeeServiceRecord(row);
    validateEmployeeServiceRecord(record, service, identity, detail: true);
    return record;
  });

  @override
  Future<Map<String, Object?>> command(
    EmployeeIdentity identity,
    String rpc,
    Map<String, Object?> parameters, {
    bool Function()? stillAuthorized,
  }) => _safe(() async {
    if (!employeeSelfCommandRpcs.contains(rpc)) {
      throw const FormatException('Unsupported employee command.');
    }
    validateEmployeeCommandParameters(rpc, parameters);
    await _authorize(identity);
    _same(identity);
    if (stillAuthorized != null && !stillAuthorized()) {
      throw const EmployeeFailure('SESSION_CHANGED', 'Your account changed.');
    }
    final result = selfMap(
      await client
          .schema('api')
          .rpc(rpc, params: {...selfScope(identity), ...parameters}),
    );
    _same(identity);
    return validateEmployeeCommandReceipt(result, identity, rpc, parameters);
  });

  @override
  Future<EmployeeReceiptLookup> receipt(
    EmployeeIdentity identity,
    String rpc,
    String commandId,
    String requestId, {
    bool Function()? stillAuthorized,
  }) => _safe(() async {
    if (!employeeSelfCommandRpcs.contains(rpc)) {
      throw const FormatException('Unsupported employee receipt.');
    }
    await _authorize(identity);
    _same(identity);
    if (stillAuthorized != null && !stillAuthorized()) {
      throw const EmployeeFailure('SESSION_CHANGED', 'Your account changed.');
    }
    final result = await client
        .schema('api')
        .rpc(
          rpc == 'employee_case_command'
              ? 'employee_case_receipt'
              : 'employee_self_receipt',
          params: {
            ...selfScope(identity),
            'p_command_id': selfUuid(commandId),
            'p_request_id': selfUuid(requestId),
            'p_rpc': rpc,
          },
        );
    _same(identity);
    return parseEmployeeReceiptLookup(
      result,
      identity,
      rpc,
      commandId,
      requestId,
    );
  });

  @override
  Future<void> markNoticeRead(
    EmployeeIdentity identity,
    EmployeeServiceRecord notice,
    String commandId, {
    bool Function()? stillAuthorized,
  }) => _safe(() async {
    await _authorize(identity);
    _same(identity);
    if (stillAuthorized != null && !stillAuthorized()) {
      throw const EmployeeFailure('SESSION_CHANGED', 'Your account changed.');
    }
    await client
        .schema('api')
        .rpc(
          'mark_notification_read',
          params: {
            'p_tenant_id': identity.workspace.tenantId,
            'p_notification_id': notice.id,
            'p_expected_version': notice.version,
            'p_idempotency_key': selfUuid(commandId),
          },
        );
    _same(identity);
  });

  @override
  Future<EmployeePrivateDocument> document(
    EmployeeIdentity identity,
    EmployeeServiceRecord document,
  ) => _safe(() async {
    await _authorize(identity);
    _same(identity);
    final metadata = {
      ...selfScope(identity)
          .map((key, value) => MapEntry(key.substring(2), value)),
      'document_id': document.id,
      'document_version': document.version,
      'publication_version': selfInteger(
        document.values['publication_version'],
        minimum: 1,
      ),
      'operation': 'employee_download',
    };
    final response = await client.functions.invoke(
      'people-private-documents',
      headers: {
        'x-jentra-hr-request': base64Encode(utf8.encode(jsonEncode(metadata))),
      },
    );
    _same(identity);
    final data = response.data;
    if (response.status != 200 ||
        data is! List<int> ||
        data.length != document.integer('byte_size') ||
        data.length > 10 * 1024 * 1024 ||
        sha256.convert(data).toString() != document.values['checksum']) {
      throw const FormatException('Document response mismatch.');
    }
    return EmployeePrivateDocument(
      Uint8List.fromList(data),
      document.text('mime', max: 100),
    );
  });
}

const employeeSelfCommandRpcs = {
  'employee_self_leave_submit',
  'employee_self_leave_intent',
  'employee_self_attendance_request',
  'employee_case_command',
};

void validateEmployeeCommandParameters(
  String rpc,
  Map<String, Object?> parameters,
) {
  final allowed = switch (rpc) {
    'employee_self_leave_submit' => {
      'p_command_id',
      'p_request_id',
      'p_payload',
      'p_expected_balance_version',
    },
    'employee_self_leave_intent' => {
      'p_command_id',
      'p_request_id',
      'p_action',
      'p_expected_version',
      'p_reason',
    },
    'employee_self_attendance_request' => {
      'p_command_id',
      'p_request_id',
      'p_payload',
    },
    'employee_case_command' => {'p_command_id', 'p_action', 'p_payload'},
    _ => throw const FormatException('Unsupported employee command.'),
  };
  if (parameters.length != allowed.length ||
      parameters.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Invalid employee parameters.');
  }
  selfUuid(parameters['p_command_id']);
  if (parameters['p_request_id'] != null) selfUuid(parameters['p_request_id']);
  if (parameters['p_payload'] != null) selfMap(parameters['p_payload']);
}

Map<String, Object?> validateEmployeeCommandReceipt(
  Object? value,
  EmployeeIdentity identity,
  String rpc,
  Map<String, Object?> parameters,
) {
  final result = selfMap(value);
  validateSelfScope(result, identity);
  if (result['command_id'] != parameters['p_command_id']) {
    throw const FormatException('Command receipt mismatch.');
  }
  final expected =
      parameters['p_request_id'] ?? selfMap(parameters['p_payload'])['id'];
  if (result['request_id'] != expected && result['id'] != expected) {
    throw const FormatException('Command target mismatch.');
  }
  final version = selfInteger(result['version'], minimum: 1);
  switch (rpc) {
    case 'employee_self_attendance_request':
      if (version != 1 ||
          result['status'] != 'pending_evidence' ||
          result['payable_time_changed'] != false) {
        throw const FormatException('Invalid attendance receipt.');
      }
    case 'employee_self_leave_submit':
      if (version != 1 ||
          result['status'] != 'submitted' ||
          result['approval_required'] != true) {
        throw const FormatException('Invalid leave receipt.');
      }
      selfInteger(result['charge_seconds'], minimum: 1);
    case 'employee_self_leave_intent':
      final withdraw = parameters['p_action'] == 'withdraw';
      if (version !=
              selfInteger(parameters['p_expected_version'], minimum: 1) +
                  (withdraw ? 1 : 0) ||
          result['status'] !=
              (withdraw ? 'withdrawn' : 'cancellation_requested') ||
          result['approval_required'] != !withdraw) {
        throw const FormatException('Invalid leave intent receipt.');
      }
    case 'employee_case_command':
      final creating = parameters['p_action'] == 'create';
      final expectedVersion = creating
          ? 1
          : selfInteger(
                  selfMap(parameters['p_payload'])['expected_version'],
                  minimum: 1,
                ) +
                1;
      if (version != expectedVersion ||
          !(creating ? {'open'} : {'open', 'in_progress'}).contains(
            result['status'],
          )) {
        throw const FormatException('Invalid case receipt.');
      }
    default:
      throw const FormatException('Unsupported receipt.');
  }
  return selfImmutableMap(result);
}

EmployeeReceiptLookup parseEmployeeReceiptLookup(
  Object? value,
  EmployeeIdentity identity,
  String rpc,
  String commandId,
  String requestId,
) {
  final json = selfMap(value);
  validateSelfScope(json, identity);
  if (!employeeSelfCommandRpcs.contains(rpc) ||
      json['command_id'] != commandId ||
      json['request_id'] != requestId ||
      json['rpc'] != rpc ||
      json['abandoned'] is! bool) {
    throw const FormatException(
      'Receipt lookup does not match the saved request.',
    );
  }
  final abandoned = json['abandoned']! as bool;
  if (json['receipt'] == null) {
    return EmployeeReceiptLookup(receipt: null, abandoned: abandoned);
  }
  if (abandoned) throw const FormatException('Inconsistent receipt outcome.');
  final receipt = selfMap(json['receipt']);
  validateSelfScope(receipt, identity);
  if (receipt['command_id'] != commandId ||
      (receipt['request_id'] != requestId && receipt['id'] != requestId)) {
    throw const FormatException('Receipt target mismatch.');
  }
  selfInteger(receipt['version'], minimum: 1);
  final allowed = switch (rpc) {
    'employee_self_leave_submit' => {'submitted'},
    'employee_self_leave_intent' => {'withdrawn', 'cancellation_requested'},
    'employee_self_attendance_request' => {'pending_evidence'},
    'employee_case_command' => {'open', 'in_progress'},
    _ => const <String>{},
  };
  if (!allowed.contains(receipt['status']) ||
      rpc == 'employee_self_attendance_request' &&
          receipt['payable_time_changed'] != false ||
      rpc == 'employee_self_leave_submit' &&
          receipt['approval_required'] != true) {
    throw const FormatException('Invalid receipt outcome.');
  }
  return EmployeeReceiptLookup(
    receipt: selfImmutableMap(receipt),
    abandoned: false,
  );
}
