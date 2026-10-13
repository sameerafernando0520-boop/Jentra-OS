import 'dart:convert';

import '../errors.dart';
import '../exact_decimal.dart';

/// Reported event durations, never certified stage dwell or process throughput.
abstract final class ProcessMetricDefinition {
  static const code = 'process.event_duration';
  static const version = 1;
  static const unit = 'microseconds';
  static const sourceContract = 'workflow.process_events.v1';
  static const documentType = 'crm_opportunity';
  static const maxSourceRows = 10000;
  static const maxCohortDays = 366;
  static const maxSerializedBytes = 8 * 1024 * 1024;
  static const unsupportedMeasures = <String, String>{
    'stage_dwell': 'UNCERTIFIED_PROCESS_SEMANTICS',
    'process_throughput': 'UNCERTIFIED_PROCESS_SEMANTICS',
    'handoff_wait': 'UNCERTIFIED_PROCESS_SEMANTICS',
    'productive_work_ratio': 'UNCERTIFIED_PROCESS_SEMANTICS',
    'rework': 'UNCERTIFIED_PROCESS_SEMANTICS',
  };
}

/// Implemented with the existing platform cryptography library. A digest is
/// evidence consistency, not permission or proof that a provider is trusted.
abstract interface class ProcessMetricHasher {
  Future<String> sha256(List<int> bytes);
}

final class ProcessMetricScope {
  ProcessMetricScope({
    required String tenantId,
    required String legalEntityId,
    String? branchId,
  }) : tenantId = _uuid(tenantId),
       legalEntityId = _uuid(legalEntityId),
       branchId = branchId == null ? null : _uuid(branchId);

  final String tenantId;
  final String legalEntityId;
  final String? branchId;

  bool contains(ProcessMetricObservation row) =>
      row.tenantId == tenantId &&
      row.legalEntityId == legalEntityId &&
      (branchId == null || row.branchId == branchId);

  @override
  bool operator ==(Object other) =>
      other is ProcessMetricScope &&
      tenantId == other.tenantId &&
      legalEntityId == other.legalEntityId &&
      branchId == other.branchId;

  @override
  int get hashCode => Object.hash(tenantId, legalEntityId, branchId);
}

/// Strictly parses UTC without DateTime.parse's invalid-date normalization.
DateTime parseProcessMetricUtc(String input) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$',
  ).firstMatch(input);
  if (match == null) _invalid('A valid UTC instant is required.');
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    _invalid('A valid UTC instant is required.');
  }
  final fraction = int.parse((match.group(7) ?? '').padRight(6, '0'));
  final result = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    fraction ~/ 1000,
    fraction % 1000,
  );
  if (result.year != year || result.month != month || result.day != day) {
    _invalid('A valid UTC instant is required.');
  }
  return result;
}

String _utc(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}T'
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}:'
    '${value.second.toString().padLeft(2, '0')}.'
    '${(value.millisecond * 1000 + value.microsecond).toString().padLeft(6, '0')}Z';

BigInt _micros(DateTime value) =>
    BigInt.from(value.millisecondsSinceEpoch) * BigInt.from(1000) +
    BigInt.from(value.microsecond);

final class ProcessMetricObservation {
  ProcessMetricObservation._({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.branchId,
    required this.documentType,
    required this.documentId,
    required this.enteredAt,
    required this.completedAt,
    required this.recordedAt,
    required this.activeMinutes,
    required this.waitMinutes,
  });

  factory ProcessMetricObservation.fromJson(Map<String, Object?> json) {
    _shape(json, const {
      'id',
      'tenantId',
      'legalEntityId',
      'branchId',
      'documentType',
      'documentId',
      'enteredAt',
      'completedAt',
      'recordedAt',
      'activeMinutes',
      'waitMinutes',
    });
    final kind = _text(json['documentType']);
    if (kind != ProcessMetricDefinition.documentType) {
      _contractMismatch();
    }
    return ProcessMetricObservation._(
      id: _uuid(json['id']),
      tenantId: _uuid(json['tenantId']),
      legalEntityId: _nullableUuid(json['legalEntityId']),
      branchId: _nullableUuid(json['branchId']),
      documentType: kind,
      documentId: _uuid(json['documentId']),
      enteredAt: parseProcessMetricUtc(_text(json['enteredAt'])),
      completedAt: json['completedAt'] == null
          ? null
          : parseProcessMetricUtc(_text(json['completedAt'])),
      recordedAt: parseProcessMetricUtc(_text(json['recordedAt'])),
      activeMinutes: _minutes(json['activeMinutes']),
      waitMinutes: _minutes(json['waitMinutes']),
    );
  }

  final String id, tenantId, documentType, documentId;
  final String? legalEntityId, branchId;
  final DateTime enteredAt, recordedAt;
  final DateTime? completedAt;
  final ExactDecimal activeMinutes, waitMinutes;

  bool get isInvalid =>
      activeMinutes.isNegative ||
      waitMinutes.isNegative ||
      (completedAt != null && completedAt!.isBefore(enteredAt));

  /// Field insertion order is part of manifest format v1.
  Map<String, Object?> toJson() => {
    'id': id,
    'tenantId': tenantId,
    'legalEntityId': legalEntityId,
    'branchId': branchId,
    'documentType': documentType,
    'documentId': documentId,
    'enteredAt': _utc(enteredAt),
    'completedAt': completedAt == null ? null : _utc(completedAt!),
    'recordedAt': _utc(recordedAt),
    'activeMinutes': activeMinutes.toDecimalString(),
    'waitMinutes': waitMinutes.toDecimalString(),
  };
}

final class ProcessSnapshotManifest {
  ProcessSnapshotManifest._({
    required this.snapshotId,
    required this.sourceManifestHash,
    required Iterable<String> sourceEventIds,
    required this.scope,
    required this.windowStart,
    required this.windowEnd,
    required this.asOf,
    required this.recordedThrough,
    required this.sourceCount,
  }) : sourceEventIds = List.unmodifiable(sourceEventIds);

  factory ProcessSnapshotManifest.fromJson(Map<String, Object?> json) {
    _shape(json, const {
      'snapshotId',
      'sourceManifestHash',
      'sourceEventIds',
      'sourceContractVersion',
      'tenantId',
      'legalEntityId',
      'branchId',
      'documentType',
      'windowStart',
      'windowEnd',
      'asOf',
      'recordedThrough',
      'sourceCount',
      'complete',
    });
    if (json['sourceContractVersion'] !=
            ProcessMetricDefinition.sourceContract ||
        json['documentType'] != ProcessMetricDefinition.documentType) {
      _contractMismatch();
    }
    if (json['complete'] != true) {
      throw const DomainError(
        code: 'INSUFFICIENT_EVIDENCE',
        message: 'A complete source snapshot is required.',
      );
    }
    final count = json['sourceCount'];
    if (count is! int || count < 0) {
      _invalid('A valid source count is required.');
    }
    if (count > ProcessMetricDefinition.maxSourceRows) _limit();
    final rawIds = json['sourceEventIds'];
    if (rawIds is! List) _invalid('A source selection is required.');
    if (rawIds.length > ProcessMetricDefinition.maxSourceRows) _limit();
    final ids = rawIds.map(_uuid).toList(growable: false);
    if (ids.length != count) _invalid('Source selection and count must match.');
    for (var index = 1; index < ids.length; index++) {
      if (ids[index - 1].compareTo(ids[index]) >= 0) {
        _invalid('Source identities must be unique and sorted.');
      }
    }
    final windowStart = parseProcessMetricUtc(_text(json['windowStart']));
    final windowEnd = parseProcessMetricUtc(_text(json['windowEnd']));
    final asOf = parseProcessMetricUtc(_text(json['asOf']));
    final recordedThrough = parseProcessMetricUtc(
      _text(json['recordedThrough']),
    );
    if (!windowEnd.isAfter(windowStart) ||
        asOf.isBefore(windowEnd) ||
        asOf.isAfter(recordedThrough)) {
      _invalid('The cohort and cutoff instants must be ordered.');
    }
    if (_micros(windowEnd) - _micros(windowStart) >
        BigInt.from(
          ProcessMetricDefinition.maxCohortDays * Duration.microsecondsPerDay,
        )) {
      _limit();
    }
    final hash = _text(json['sourceManifestHash']);
    if (!_isHash(hash)) _invalid('A valid source manifest digest is required.');
    return ProcessSnapshotManifest._(
      snapshotId: _uuid(json['snapshotId']),
      sourceManifestHash: hash,
      sourceEventIds: ids,
      scope: ProcessMetricScope(
        tenantId: _text(json['tenantId']),
        legalEntityId: _text(json['legalEntityId']),
        branchId: json['branchId'] == null ? null : _text(json['branchId']),
      ),
      windowStart: windowStart,
      windowEnd: windowEnd,
      asOf: asOf,
      recordedThrough: recordedThrough,
      sourceCount: count,
    );
  }

  final String snapshotId, sourceManifestHash;
  final List<String> sourceEventIds;
  final ProcessMetricScope scope;
  final DateTime windowStart, windowEnd, asOf, recordedThrough;
  final int sourceCount;

  Map<String, Object?> toJson() => {
    'snapshotId': snapshotId,
    'sourceManifestHash': sourceManifestHash,
    'sourceEventIds': sourceEventIds.toList(),
    'sourceContractVersion': ProcessMetricDefinition.sourceContract,
    'tenantId': scope.tenantId,
    'legalEntityId': scope.legalEntityId,
    'branchId': scope.branchId,
    'documentType': ProcessMetricDefinition.documentType,
    'windowStart': _utc(windowStart),
    'windowEnd': _utc(windowEnd),
    'asOf': _utc(asOf),
    'recordedThrough': _utc(recordedThrough),
    'sourceCount': sourceCount,
    'complete': true,
  };
}

/// Structurally validated projection. Calculation requires digest verification.
/// It cannot authorize reads, certify completeness, or trust a client provider.
final class ParsedProcessMetricSnapshot {
  ParsedProcessMetricSnapshot._(
    this.source,
    Iterable<ProcessMetricObservation> rows,
  ) : observations = List.unmodifiable(rows);

  factory ParsedProcessMetricSnapshot.fromJson(
    Map<String, Object?> json, {
    required ProcessMetricScope expectedScope,
  }) {
    _shape(json, const {'source', 'observations'});
    final source = ProcessSnapshotManifest.fromJson(_map(json['source']));
    if (source.scope != expectedScope) _denied();
    final raw = json['observations'];
    if (raw is! List) _invalid('A complete observation list is required.');
    if (raw.length > ProcessMetricDefinition.maxSourceRows) _limit();
    if (raw.length != source.sourceCount) {
      throw const DomainError(
        code: 'INSUFFICIENT_EVIDENCE',
        message: 'The retrieved source selection is incomplete.',
      );
    }
    final rows = raw
        .map((row) => ProcessMetricObservation.fromJson(_map(row)))
        .toList();
    final ids = <String>{};
    for (final row in rows) {
      if (!source.scope.contains(row)) _denied();
      if (!ids.add(row.id)) _invalid('Source event identities must be unique.');
    }
    if (source.sourceEventIds.any((id) => !ids.contains(id))) {
      throw const DomainError(
        code: 'INSUFFICIENT_EVIDENCE',
        message: 'The source selection does not match its manifest.',
      );
    }
    rows.sort((a, b) => a.id.compareTo(b.id));
    final parsed = ParsedProcessMetricSnapshot._(source, rows);
    if (parsed.canonicalBytes.length >
        ProcessMetricDefinition.maxSerializedBytes) {
      _limit();
    }
    return parsed;
  }

  final ProcessSnapshotManifest source;
  final List<ProcessMetricObservation> observations;

  /// Canonical UTF-8 payload; neither snapshot ID nor generation time is hashed.
  List<int> get canonicalBytes => List.unmodifiable(
    utf8.encode(
      jsonEncode({
        'definitionCode': ProcessMetricDefinition.code,
        'definitionVersion': ProcessMetricDefinition.version,
        'sourceContractVersion': ProcessMetricDefinition.sourceContract,
        'tenantId': source.scope.tenantId,
        'legalEntityId': source.scope.legalEntityId,
        'branchId': source.scope.branchId,
        'documentType': ProcessMetricDefinition.documentType,
        'windowStart': _utc(source.windowStart),
        'windowEnd': _utc(source.windowEnd),
        'asOf': _utc(source.asOf),
        'recordedThrough': _utc(source.recordedThrough),
        'observations': observations.map((row) => row.toJson()).toList(),
      }),
    ),
  );

  Future<ProcessMetricSnapshot> verify(ProcessMetricHasher hasher) async {
    final String computed;
    try {
      computed = await hasher.sha256(canonicalBytes);
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'PROVIDER_UNAVAILABLE',
        message: 'The source digest verifier is unavailable.',
        retryable: true,
      );
    }
    if (!_isHash(computed) || computed != source.sourceManifestHash) {
      throw const DomainError(
        code: 'INSUFFICIENT_EVIDENCE',
        message: 'The source snapshot does not match its captured digest.',
      );
    }
    return ProcessMetricSnapshot._(source, observations);
  }
}

/// Frozen, digest-verified source values. Server authorization remains external.
final class ProcessMetricSnapshot {
  ProcessMetricSnapshot._(this.source, this._observations);
  final ProcessSnapshotManifest source;
  final List<ProcessMetricObservation> _observations;

  ProcessMetricSummary summarize({required String generatedAt}) {
    final generated = parseProcessMetricUtc(generatedAt);
    if (generated.isBefore(source.recordedThrough)) {
      _invalid('Generation must not precede the captured recorded cutoff.');
    }
    final durations = <BigInt>[];
    var open = 0, invalid = 0, excluded = 0;
    for (final row in _observations) {
      if (row.enteredAt.isBefore(source.windowStart) ||
          !row.enteredAt.isBefore(source.windowEnd) ||
          row.recordedAt.isAfter(source.recordedThrough)) {
        excluded++;
      } else if (row.isInvalid) {
        invalid++;
      } else if (row.completedAt == null ||
          row.completedAt!.isAfter(source.asOf)) {
        open++;
      } else {
        durations.add(_micros(row.completedAt!) - _micros(row.enteredAt));
      }
    }
    durations.sort();
    final count = durations.length;
    final summary = ProcessMetricSummary._(
      source: source,
      cohortCount: count + open + invalid,
      excludedCount: excluded,
      completedCount: count,
      openCount: open,
      invalidCount: invalid,
      p50Microseconds: count == 0 ? null : durations[(count + 1) ~/ 2 - 1],
      p90Microseconds: count == 0 ? null : durations[(9 * count + 9) ~/ 10 - 1],
      generatedAt: generated,
    );
    if (utf8.encode(jsonEncode(summary.toJson())).length >
        ProcessMetricDefinition.maxSerializedBytes) {
      _limit();
    }
    return summary;
  }
}

final class ProcessMetricSummary {
  ProcessMetricSummary._({
    required this.source,
    required this.cohortCount,
    required this.excludedCount,
    required this.completedCount,
    required this.openCount,
    required this.invalidCount,
    required this.p50Microseconds,
    required this.p90Microseconds,
    required this.generatedAt,
  });

  final ProcessSnapshotManifest source;
  final int cohortCount, excludedCount, completedCount, openCount, invalidCount;
  final BigInt? p50Microseconds, p90Microseconds;
  final DateTime generatedAt;
  String get completeness => invalidCount == 0 ? 'complete' : 'partial';
  String? get emptyDurationReason =>
      completedCount == 0 ? 'NO_COMPLETED_OBSERVATIONS' : null;
  Map<String, String> get unsupportedMeasures =>
      ProcessMetricDefinition.unsupportedMeasures;

  Map<String, Object?> toJson() => {
    'definitionCode': ProcessMetricDefinition.code,
    'definitionVersion': ProcessMetricDefinition.version,
    'source': source.toJson(),
    'cohortCount': cohortCount,
    'excludedCount': excludedCount,
    'completedCount': completedCount,
    'openCount': openCount,
    'invalidCount': invalidCount,
    'completeness': completeness,
    'p50Microseconds': p50Microseconds?.toString(),
    'p90Microseconds': p90Microseconds?.toString(),
    'emptyDurationReason': emptyDurationReason,
    'unsupportedMeasures': Map<String, String>.from(unsupportedMeasures),
    'generatedAt': _utc(generatedAt),
  };
}

ExactDecimal _minutes(Object? value) {
  final text = _text(value);
  if (!RegExp(r'^-?\d{1,14}(?:\.\d{1,6})?$').hasMatch(text)) {
    _invalid('An exact numeric(20,6) minute value is required.');
  }
  return ExactDecimal.parse(text, scale: 6);
}

String _uuid(Object? value) {
  final text = _text(value);
  if (!RegExp(
    r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
  ).hasMatch(text)) {
    _invalid('A valid scoped identifier is required.');
  }
  return text.toLowerCase();
}

String? _nullableUuid(Object? value) => value == null ? null : _uuid(value);

String _text(Object? value) {
  if (value is! String) _invalid('A required text field is invalid.');
  return value;
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    _invalid('A valid source object is required.');
  }
  return Map<String, Object?>.from(value);
}

void _shape(Map<String, Object?> value, Set<String> fields) {
  if (value.length != fields.length ||
      fields.any((field) => !value.containsKey(field))) {
    _invalid('The source projection does not match its allowlisted contract.');
  }
}

bool _isHash(String input) => RegExp(r'^[0-9a-f]{64}$').hasMatch(input);

Never _invalid(String message) =>
    throw DomainError(code: 'VALIDATION_ERROR', message: message);
Never _limit() => throw const DomainError(
  code: 'LIMIT_EXCEEDED',
  message: 'The process metric snapshot exceeds an allowed bound.',
);
Never _denied() => throw const DomainError(
  code: 'PERMISSION_DENIED',
  message: 'This process metric snapshot is unavailable in the selected scope.',
);
Never _contractMismatch() => throw const DomainError(
  code: 'CONTRACT_MISMATCH',
  message: 'The process source contract is unsupported.',
);
