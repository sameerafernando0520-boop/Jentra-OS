import 'dart:convert';
import 'dart:typed_data';
import 'commands.dart';
import 'tenant_context.dart';
import 'calendar_repository.dart';
import 'employee.dart';
import 'organization.dart';

enum HrRecordKind {
  subject,
  membership,
  profile,
  profileRevision,
  document,
  review,
  reviewHistory,
  link,
  inbox,
  self,
  policy,
}

enum HrCollection {
  documents,
  reviews,
  reviewHistory,
  links,
  memberships,
  inbox,
}

const hrContactFields = {
  'personal_email',
  'personal_phone',
  'postal_address',
  'emergency_name',
  'emergency_relationship',
  'emergency_phone',
};
Map<String, Object?> hrMap(Object? raw) {
  if (raw is! Map) {
    throw const FormatException('Private HR response is invalid.');
  }
  return Map<String, Object?>.from(raw);
}

String? hrOptionalText(Object? value, int limit) =>
    value == null ? null : organizationText(value, limit);
void hrContact(Map<String, Object?> body) {
  calendarFields(body, hrContactFields);
  for (final field in hrContactFields) {
    hrOptionalText(body[field], field == 'postal_address' ? 1000 : 160);
  }
}

void hrReviewBody(Map<String, Object?> body) {
  calendarFields(body, {'objectives', 'comments'});
  final objectives = body['objectives'];
  if (objectives is! List || objectives.isEmpty || objectives.length > 20) {
    throw const FormatException('A review needs 1–20 bounded objectives.');
  }
  for (final item in objectives) {
    organizationText(item, 1000);
  }
  if (body['comments'] != null &&
      (body['comments'] is! String ||
          (body['comments'] as String).length > 4000)) {
    throw const FormatException('Review comments exceed their bound.');
  }
}

void hrDigest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Private HR digest is invalid.');
  }
}

/// A frozen, explicitly allowlisted projection. Kinds cannot be interchanged.
final class HrRecord {
  HrRecord.fromJson(this.kind, Map<String, Object?> json)
    : _wire = jsonEncode(json) {
    final fields = switch (kind) {
      HrRecordKind.subject => {'id', 'code', 'display_name'},
      HrRecordKind.membership => {'id', 'user_id'},
      HrRecordKind.profile => {
        'employee_id',
        'version',
        'revision_id',
        'body',
        'recorded_by',
        'recorded_at',
      },
      HrRecordKind.profileRevision => {
        'id',
        'version',
        'body',
        'reason',
        'digest',
        'recorded_by',
        'recorded_at',
      },
      HrRecordKind.document => {
        'id',
        'version',
        'classification',
        'purpose',
        'mime',
        'byte_size',
        'checksum',
        'status',
        'created_by',
        'created_at',
      },
      HrRecordKind.review => {
        'id',
        'version',
        'revision_id',
        'reviewer_id',
        'status',
        'start_date',
        'end_date_exclusive',
        'body',
        'recorded_by',
        'recorded_at',
      },
      HrRecordKind.reviewHistory => {
        'id',
        'kind',
        'revision_id',
        'body',
        'private_text',
        'digest',
        'recorded_by',
        'recorded_at',
      },
      HrRecordKind.link => {
        'id',
        'version',
        'membership_id',
        'user_id',
        'status',
        'initiated_by',
        'initiated_at',
        'expires_at',
        'accepted_at',
      },
      HrRecordKind.inbox => {
        'id',
        'employee_id',
        'employee_name',
        'version',
        'status',
        'initiated_by',
        'expires_at',
      },
      HrRecordKind.self => {'employee_id', 'display_name'},
      HrRecordKind.policy => {
        'id',
        'version',
        'purpose',
        'contract',
        'retention_days',
        'closed_at',
        'hold_reason',
        'hold_review_date',
      },
    };
    calendarFields(json, fields);
    calendarUuid(
      json[kind == HrRecordKind.profile || kind == HrRecordKind.self
          ? 'employee_id'
          : 'id'],
    );
    for (final field in {
      'user_id',
      'employee_id',
      'membership_id',
      'reviewer_id',
      'revision_id',
      'recorded_by',
      'created_by',
      'initiated_by',
    }) {
      if (fields.contains(field)) calendarUuid(json[field]);
    }
    if (fields.contains('version')) organizationVersion(json['version']);
    for (final field in {
      'recorded_at',
      'created_at',
      'initiated_at',
      'expires_at',
    }) {
      if (fields.contains(field)) organizationTimestamp(json[field]);
    }
    for (final field in {'accepted_at', 'closed_at'}) {
      if (fields.contains(field) && json[field] != null) {
        organizationTimestamp(json[field]);
      }
    }
    switch (kind) {
      case HrRecordKind.subject:
        organizationText(json['code'], 32);
        organizationText(json['display_name'], 160);
      case HrRecordKind.self:
        organizationText(json['display_name'], 160);
      case HrRecordKind.membership:
        break;
      case HrRecordKind.profile:
      case HrRecordKind.profileRevision:
        hrContact(hrMap(json['body']));
        if (kind == HrRecordKind.profileRevision) {
          organizationText(json['reason'], 1000);
          hrDigest(json['digest']);
        }
      case HrRecordKind.document:
        if (!{
              'contact-support',
              'review-evidence',
            }.contains(json['classification']) ||
            !{
              'text/plain',
              'image/png',
              'image/jpeg',
              'application/pdf',
            }.contains(json['mime']) ||
            !{'reserved', 'verified', 'active'}.contains(json['status']) ||
            json['byte_size'] is! int ||
            (json['byte_size'] as int) < 1 ||
            (json['byte_size'] as int) > 10485760) {
          throw const FormatException('Private document metadata is invalid.');
        }
        organizationText(json['purpose'], 160);
        hrDigest(json['checksum']);
      case HrRecordKind.review:
        if (!{
          'draft',
          'submitted',
          'reviewed',
          'acknowledged',
          'closed',
        }.contains(json['status'])) {
          throw const FormatException('Review state is invalid.');
        }
        final dates = OrganizationDates(
          json['start_date'],
          json['end_date_exclusive'],
          finite: true,
        );
        if (dates.endExclusive!.utc.difference(dates.start.utc).inDays > 366) {
          throw const FormatException('Review period exceeds 366 days.');
        }
        hrReviewBody(hrMap(json['body']));
      case HrRecordKind.reviewHistory:
        if (!{
          'revision',
          'review_submit',
          'review_decide',
          'review_acknowledge',
          'review_close',
        }.contains(json['kind'])) {
          throw const FormatException('Review history is invalid.');
        }
        if (json['body'] != null) hrReviewBody(hrMap(json['body']));
        hrOptionalText(json['private_text'], 4000);
        hrDigest(json['digest']);
      case HrRecordKind.link:
        if (!{
          'pending',
          'accepted',
          'rejected',
          'expired',
          'revoked',
        }.contains(json['status'])) {
          throw const FormatException('Account link state is invalid.');
        }
        if (json['status'] == 'accepted' && json['accepted_at'] == null) {
          throw const FormatException('Acceptance evidence is missing.');
        }
      case HrRecordKind.inbox:
        organizationText(json['employee_name'], 160);
        if (json['status'] != 'pending') {
          throw const FormatException('Link proposal is invalid.');
        }
      case HrRecordKind.policy:
        organizationText(json['purpose'], 160);
        if (json['contract'] != 'w4-private-hr-v1' ||
            json['retention_days'] != 30) {
          throw const FormatException(
            'Synthetic retention contract is invalid.',
          );
        }
        hrOptionalText(json['hold_reason'], 1000);
        if ((json['hold_reason'] == null) !=
            (json['hold_review_date'] == null)) {
          throw const FormatException('Hold evidence is invalid.');
        }
        if (json['hold_review_date'] != null) {
          CivilDate.parse(json['hold_review_date'] as String);
        }
    }
  }
  final HrRecordKind kind;
  final String _wire;
  Map<String, Object?> toJson() => hrMap(jsonDecode(_wire));
  String get id =>
      toJson()[kind == HrRecordKind.profile || kind == HrRecordKind.self
              ? 'employee_id'
              : 'id']
          as String;
  int get version => toJson()['version'] as int? ?? 0;
  String? text(String field) => toJson()[field] as String?;
  Map<String, Object?>? get body =>
      toJson()['body'] == null ? null : hrMap(toJson()['body']);
}

final class HrPage {
  const HrPage(this.items, this.nextCursor);
  final List<HrRecord> items;
  final String? nextCursor;
}

final class HrProfileState {
  const HrProfileState(this.profile, this.history);
  final HrRecord? profile;
  final HrPage history;
}

final class HrPolicyState {
  const HrPolicyState(this.policy, this.workerReady);
  final HrRecord? policy;
  final bool workerReady;
}

final class HrConfirmation {
  HrConfirmation.fromJson(Map<String, Object?> json)
    : commandId = calendarUuid(json['command_id']),
      entity = hrMap(json['entity']) {
    calendarFields(json, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    calendarUuid(json['request_id']);
    calendarUuid(json['correlation_id']);
    if (json['warnings'] is! List || (json['warnings'] as List).isNotEmpty) {
      throw const FormatException('Unexpected private command warnings.');
    }
    calendarFields(entity, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'version',
      'action',
      'revision_id',
      'digest',
    });
    for (final key in {'id', 'tenant_id', 'legal_entity_id', 'branch_id'}) {
      calendarUuid(entity[key]);
    }
    for (final key in {'employee_id', 'revision_id'}) {
      if (entity[key] != null) calendarUuid(entity[key]);
    }
    organizationVersion(entity['version']);
    if (!HrCommands.fields.containsKey(entity['action'])) {
      throw const FormatException('Private command action is invalid.');
    }
    if (entity['digest'] != null) hrDigest(entity['digest']);
  }
  final String commandId;
  final Map<String, Object?> entity;
  int get version => entity['version'] as int;
}

abstract final class HrCommands {
  static const fields = <String, Set<String>>{
    'policy_create': {'action', 'id', 'purpose'},
    'cycle_close': {'action', 'id', 'closed_at'},
    'hold': {'action', 'id', 'reason', 'review_date'},
    'release_hold': {'action', 'id', 'reason'},
    'profile_save': {
      'action',
      'id',
      'employee_id',
      'revision_id',
      'body',
      'reason',
    },
    'document_reserve': {
      'action',
      'id',
      'employee_id',
      'classification',
      'purpose',
      'mime',
      'byte_size',
      'checksum',
    },
    'document_complete': {'action', 'id', 'employee_id'},
    'review_create': {
      'action',
      'id',
      'employee_id',
      'reviewer_id',
      'revision_id',
      'start_date',
      'end_date_exclusive',
      'body',
      'reason',
    },
    'review_revise': {
      'action',
      'id',
      'employee_id',
      'revision_id',
      'body',
      'reason',
    },
    'review_submit': {'action', 'id', 'employee_id'},
    'review_decide': {'action', 'id', 'employee_id', 'private_text'},
    'review_acknowledge': {'action', 'id', 'employee_id'},
    'review_close': {'action', 'id', 'employee_id'},
    'link_initiate': {
      'action',
      'id',
      'employee_id',
      'membership_id',
      'user_id',
    },
    'link_accept': {'action', 'id', 'employee_id'},
    'link_reject': {'action', 'id', 'employee_id'},
    'link_revoke': {'action', 'id', 'employee_id'},
    'erase_request': {'action', 'id', 'employee_id'},
    'export_prepare': {
      'action',
      'id',
      'employee_id',
      'kind',
      'source_id',
      'source_version',
      'revision_id',
    },
  };
  static String capability(String action) => switch (action) {
    'policy_create' ||
    'cycle_close' ||
    'hold' ||
    'release_hold' => 'people.hr.retention.manage',
    'profile_save' => 'people.hr.private.manage',
    'document_reserve' || 'document_complete' => 'people.hr.documents.manage',
    'review_acknowledge' => 'people.self.view',
    'review_create' ||
    'review_revise' ||
    'review_submit' ||
    'review_decide' ||
    'review_close' => 'people.reviews.manage',
    'link_accept' || 'link_reject' => 'people.view',
    'link_initiate' || 'link_revoke' => 'people.account_links.manage',
    'erase_request' => 'people.hr.erase',
    'export_prepare' => 'people.hr.export',
    _ => throw const FormatException('Private action is invalid.'),
  };
  static void validate(String action, Map<String, Object?> payload) {
    final allowed = fields[action];
    if (allowed == null || payload['action'] != action) {
      throw const FormatException('Private action is invalid.');
    }
    calendarFields(payload, allowed);
    for (final field in {
      'id',
      'employee_id',
      'revision_id',
      'reviewer_id',
      'membership_id',
      'user_id',
      'source_id',
    }) {
      if (allowed.contains(field)) calendarUuid(payload[field]);
    }
    if (allowed.contains('reason')) organizationText(payload['reason'], 1000);
    if (allowed.contains('purpose')) organizationText(payload['purpose'], 160);
    if (allowed.contains('closed_at')) {
      organizationTimestamp(payload['closed_at']);
    }
    if (allowed.contains('review_date')) {
      CivilDate.parse(organizationText(payload['review_date'], 10));
    }
    if (action == 'profile_save') {
      if (payload['id'] != payload['employee_id']) {
        throw const FormatException('Contact identity is invalid.');
      }
      hrContact(hrMap(payload['body']));
    }
    if (action == 'review_create' || action == 'review_revise') {
      hrReviewBody(hrMap(payload['body']));
    }
    if (action == 'review_create') {
      final dates = OrganizationDates(
        payload['start_date'],
        payload['end_date_exclusive'],
        finite: true,
      );
      if (dates.endExclusive!.utc.difference(dates.start.utc).inDays > 366 ||
          payload['employee_id'] == payload['reviewer_id']) {
        throw const FormatException('Review eligibility is invalid.');
      }
    }
    if (action == 'review_decide') {
      organizationText(payload['private_text'], 4000);
    }
    if (action == 'document_reserve') {
      if (!{
            'contact-support',
            'review-evidence',
          }.contains(payload['classification']) ||
          !{
            'text/plain',
            'image/png',
            'image/jpeg',
            'application/pdf',
          }.contains(payload['mime']) ||
          payload['byte_size'] is! int ||
          (payload['byte_size'] as int) < 1 ||
          (payload['byte_size'] as int) > 10485760) {
        throw const FormatException('Document metadata is invalid.');
      }
      hrDigest(payload['checksum']);
    }
    if (action == 'erase_request' && payload['id'] != payload['employee_id']) {
      throw const FormatException('Erasure identity is invalid.');
    }
    if (action == 'export_prepare') {
      if (!{'profile', 'review'}.contains(payload['kind'])) {
        throw const FormatException('Private export kind is invalid.');
      }
      organizationVersion(payload['source_version']);
      if (payload['kind'] == 'profile' &&
          payload['source_id'] != payload['employee_id']) {
        throw const FormatException('Private export source is invalid.');
      }
    }
  }
}

abstract interface class HrRepository {
  Future<void> authorize(
    TenantContext scope,
    String? employee,
    String capability,
  );
  Future<HrPage> subjects(
    TenantContext scope,
    String capability, {
    String search = '',
    String? after,
  });
  Future<HrProfileState> contacts(
    TenantContext scope,
    String employee, {
    String? after,
  });
  Future<HrPage> page(
    TenantContext scope,
    HrCollection collection, {
    String? employee,
    String? reviewId,
    String? after,
  });
  Future<HrPolicyState> policy(TenantContext scope);
  Future<HrRecord> self(TenantContext scope);
  Future<HrConfirmation> command(CommandEnvelope<Map<String, Object?>> command);
  Future<HrConfirmation?> receipt(TenantContext scope, String commandId);
  Future<Map<String, Object?>> exportContent(
    TenantContext scope,
    String exportId,
  );
  Future<Uint8List> document(
    TenantContext scope,
    String employee,
    HrRecord document, {
    bool export = false,
  });
  Future<HrConfirmation> upload(
    CommandEnvelope<Map<String, Object?>> completion,
    HrRecord document,
    Uint8List bytes,
  );
}
