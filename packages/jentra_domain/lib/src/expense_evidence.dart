import 'dart:convert';
import 'dart:typed_data';

import 'calendar_repository.dart';
import 'employee.dart';
import 'commands.dart';
import 'organization.dart';
import 'tenant_context.dart';
import 'workforce.dart';

const expenseEvidenceView = 'projects.expenses.evidence.view';
const expenseEvidenceExport = 'projects.expenses.evidence.export';
const expenseEvidenceRetention = 'projects.expenses.retention.manage';
const expenseEvidenceManage = 'projects.expenses.manage';
const expenseEvidenceMaxBytes = 10 * 1024 * 1024;
const expenseEvidenceMimes = {
  'text/plain',
  'image/png',
  'image/jpeg',
  'application/pdf',
};

String expenseEvidenceDigest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Evidence digest is invalid.');
  }
  return value;
}

final class ExpenseEvidenceProof {
  ExpenseEvidenceProof.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      digest = expenseEvidenceDigest(row['digest']) {
    calendarFields(row, {'id', 'version', 'digest'});
    if (row['version'] != 1) {
      throw const FormatException('Evidence content version is invalid.');
    }
  }
  final String id, digest;
  int get version => 1;
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'digest': digest,
  };
}

List<ExpenseEvidenceProof> expenseEvidenceProofs(Object? raw) {
  if (raw is! List || raw.length > 10) {
    throw const FormatException('Select at most ten evidence documents.');
  }
  final result = raw
      .map((x) => ExpenseEvidenceProof.fromJson(workforceMap(x)))
      .toList();
  if (result.map((x) => x.id).toSet().length != result.length) {
    throw const FormatException('Each evidence document can be selected once.');
  }
  result.sort((a, b) => a.id.compareTo(b.id));
  return List.unmodifiable(result);
}

final class ExpenseEvidenceDocument {
  ExpenseEvidenceDocument.fromJson(Map<String, Object?> row)
    : _wire = jsonEncode(row),
      proof = ExpenseEvidenceProof.fromJson({
        'id': row['id'],
        'version': row['version'],
        'digest': row['digest'],
      }) {
    calendarFields(row, {
      'id',
      'version',
      'digest',
      'record_version',
      'status',
      'purpose',
      'mime',
      'byte_size',
      'checksum',
      'policy_id',
      'retired_at',
      'purge_after',
      'hold_review_date',
    });
    organizationVersion(row['record_version']);
    organizationText(row['purpose'], 160);
    calendarUuid(row['policy_id']);
    expenseEvidenceDigest(row['checksum']);
    if (!expenseEvidenceMimes.contains(row['mime']) ||
        row['byte_size'] is! int ||
        (row['byte_size'] as int) < 1 ||
        (row['byte_size'] as int) > expenseEvidenceMaxBytes ||
        !{
          'reserved',
          'verified',
          'active',
          'retired',
          'purging',
          'purged',
        }.contains(row['status'])) {
      throw const FormatException('Evidence metadata is invalid.');
    }
    for (final key in ['retired_at', 'purge_after']) {
      if (row[key] != null) organizationTimestamp(row[key]);
    }
    if (row['hold_review_date'] != null) {
      CivilDate.parse(row['hold_review_date'] as String);
    }
  }
  final String _wire;
  final ExpenseEvidenceProof proof;
  Map<String, Object?> toJson() => workforceMap(jsonDecode(_wire));
  String get id => proof.id;
  int get recordVersion => toJson()['record_version'] as int;
  String get status => toJson()['status'] as String;
  String get purpose => toJson()['purpose'] as String;
  String get mime => toJson()['mime'] as String;
  int get byteSize => toJson()['byte_size'] as int;
  String get checksum => toJson()['checksum'] as String;
  bool get isActive => status == 'active';
}

final class ExpenseEvidencePage {
  const ExpenseEvidencePage(this.items, this.nextAfter);
  final List<ExpenseEvidenceDocument> items;
  final String? nextAfter;
}

final class ExpenseEvidenceConfirmation {
  ExpenseEvidenceConfirmation.fromJson(Map<String, Object?> row)
    : commandId = calendarUuid(row['command_id']),
      _wire = jsonEncode(row) {
    calendarFields(row, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    calendarUuid(row['request_id']);
    calendarUuid(row['correlation_id']);
    if (row['warnings'] is! List || (row['warnings'] as List).isNotEmpty) {
      throw const FormatException(
        'Evidence confirmation warnings are invalid.',
      );
    }
    final e = entity;
    calendarFields(e, {
      'id',
      'version',
      'action',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      if (e['action'] != 'policy_create') ...{
        'digest',
        'record_version',
        'status',
        'project_id',
        'expense_id',
      },
    });
    for (final key in ['id', 'tenant_id', 'legal_entity_id', 'branch_id']) {
      calendarUuid(e[key]);
    }
    final action = e['action'];
    if (!ExpenseEvidenceCommands.fields.containsKey(action)) {
      throw const FormatException('Evidence confirmation action is invalid.');
    }
    if (action == 'policy_create') {
      if (e['version'] != 1 ||
          e.keys.any(
            (k) => !{
              'id',
              'version',
              'action',
              'tenant_id',
              'legal_entity_id',
              'branch_id',
            }.contains(k),
          )) {
        throw const FormatException('Retention confirmation is invalid.');
      }
    } else {
      calendarUuid(e['project_id']);
      calendarUuid(e['expense_id']);
      organizationVersion(e['record_version']);
      ExpenseEvidenceProof.fromJson({
        'id': e['id'],
        'version': e['version'],
        'digest': e['digest'],
      });
      if (!{
        'reserved',
        'verified',
        'active',
        'retired',
        'purging',
        'purged',
      }.contains(e['status'])) {
        throw const FormatException('Evidence confirmation state is invalid.');
      }
    }
  }
  final String commandId, _wire;
  Map<String, Object?> toJson() => workforceMap(jsonDecode(_wire));
  Map<String, Object?> get entity => workforceMap(toJson()['entity']);
  int get recordVersion => entity['record_version'] as int? ?? 1;
  ExpenseEvidenceProof? get proof => entity['action'] == 'policy_create'
      ? null
      : ExpenseEvidenceProof.fromJson({
          'id': entity['id'],
          'version': entity['version'],
          'digest': entity['digest'],
        });
}

abstract final class ExpenseEvidenceCommands {
  static const fields = <String, Set<String>>{
    'policy_create': {'action', 'id', 'retention_days', 'purpose'},
    'reserve': {
      'action',
      'id',
      'project_id',
      'expense_id',
      'mime',
      'byte_size',
      'checksum',
      'purpose',
    },
    'complete': {'action', 'id', 'project_id', 'expense_id'},
    'hold': {
      'action',
      'id',
      'project_id',
      'expense_id',
      'reason',
      'review_date',
    },
    'release_hold': {'action', 'id', 'project_id', 'expense_id', 'reason'},
    'retire': {'action', 'id', 'project_id', 'expense_id', 'reason'},
  };
  static String capability(String action) {
    if (!fields.containsKey(action)) {
      throw const FormatException('Unknown evidence action.');
    }
    return action == 'reserve' || action == 'complete'
        ? expenseEvidenceManage
        : expenseEvidenceRetention;
  }

  static Map<String, Object?> validate(Map<String, Object?> raw) {
    final p = workforceMap(jsonDecode(jsonEncode(raw)));
    final action = p['action'];
    if (action is! String || !fields.containsKey(action)) {
      throw const FormatException('Unknown evidence action.');
    }
    calendarFields(p, fields[action]!);
    if (!p.keys.toSet().containsAll(fields[action]!)) {
      throw const FormatException('Evidence request fields are missing.');
    }
    calendarUuid(p['id']);
    if (action != 'policy_create') {
      calendarUuid(p['project_id']);
      calendarUuid(p['expense_id']);
    }
    if (action == 'policy_create') {
      if (p['retention_days'] is! int ||
          (p['retention_days'] as int) < 1 ||
          (p['retention_days'] as int) > 3650) {
        throw const FormatException(
          'Choose an explicit bounded retention interval.',
        );
      }
    }
    if (action == 'reserve') {
      if (!expenseEvidenceMimes.contains(p['mime']) ||
          p['byte_size'] is! int ||
          (p['byte_size'] as int) < 1 ||
          (p['byte_size'] as int) > expenseEvidenceMaxBytes) {
        throw const FormatException(
          'Choose a permitted file of at most ten MiB.',
        );
      }
      expenseEvidenceDigest(p['checksum']);
    }
    if (p.containsKey('purpose')) organizationText(p['purpose'], 160);
    if (p.containsKey('reason')) organizationText(p['reason'], 1000);
    if (action == 'hold') CivilDate.parse(p['review_date'] as String);
    return p;
  }
}

abstract interface class ExpenseEvidenceRepository {
  Future<bool> authorize(
    TenantContext scope,
    String? projectId,
    String? expenseId,
    String capability,
  );
  Future<ExpenseEvidencePage> documents(
    TenantContext scope,
    String projectId,
    String expenseId, {
    String? after,
  });
  Future<ExpenseEvidenceConfirmation> command(
    CommandEnvelope<Map<String, Object?>> input,
  );
  Future<ExpenseEvidenceConfirmation?> receipt(
    TenantContext scope,
    String commandId,
  );
  Future<ExpenseEvidenceConfirmation> upload(
    CommandEnvelope<Map<String, Object?>> completion,
    ExpenseEvidenceDocument document,
    Uint8List bytes,
  );
  Future<Uint8List> document(
    TenantContext scope,
    String projectId,
    String expenseId,
    ExpenseEvidenceDocument document, {
    bool export = false,
  });
}
