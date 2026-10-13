import 'dart:convert';
import 'process_metrics.dart';

String _identity(String value) {
  ProcessMetricScope(tenantId: value, legalEntityId: value);
  return value;
}

String _hash(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid evidence hash.');
  }
  return value;
}

/// Readiness and live permissions come from a trusted server adapter.
final class ProviderContract {
  const ProviderContract({
    required this.code,
    required this.revision,
    required this.ready,
    required this.reason,
  });
  final String code, reason;
  final int revision;
  final bool ready;
  void requireRevision(int expected) {
    if (!ready || revision != expected) {
      throw const FormatException('Compatible provider unavailable.');
    }
  }
}

/// A data allowlist, never a tool-selection channel for retrieved text.
final class RedactedForecastEvidence {
  RedactedForecastEvidence({
    required this.scope,
    required String sourceId,
    required String sourceHash,
    required Map<String, String> targetVersions,
  }) : sourceId = _identity(sourceId),
       sourceHash = _hash(sourceHash),
       targetVersions = Map.unmodifiable(targetVersions) {
    if (this.targetVersions.length > 10000) {
      throw const FormatException('Evidence exceeds source bound.');
    }
    for (final entry in this.targetVersions.entries) {
      _identity(entry.key);
      if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(entry.value) ||
          BigInt.parse(entry.value) > BigInt.parse('9223372036854775807')) {
        throw const FormatException('Invalid exact source revision.');
      }
    }
  }
  final ProcessMetricScope scope;
  final String sourceId, sourceHash;
  final Map<String, String> targetVersions;
  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'sourceHash': sourceHash,
    'tenantId': scope.tenantId,
    'legalEntityId': scope.legalEntityId,
    'branchId': scope.branchId,
    'targetVersions': targetVersions,
  };
}

final class AiProposalRevision {
  AiProposalRevision({
    required String id,
    required String proposerId,
    required String commandId,
    required this.evidence,
    required String createdAt,
    required String expiresAt,
    required this.horizonStart,
    required this.horizonEnd,
    required this.estimatedUnits,
    required String parametersHash,
    required this.revision,
  }) : id = _identity(id),
       proposerId = _identity(proposerId),
       commandId = _identity(commandId),
       parametersHash = _hash(parametersHash),
       createdAt = parseProcessMetricUtc(createdAt),
       expiresAt = parseProcessMetricUtc(expiresAt) {
    final start = parseProcessMetricUtc('${horizonStart}T00:00:00Z'),
        end = parseProcessMetricUtc('${horizonEnd}T00:00:00Z');
    if (revision < 1 ||
        estimatedUnits.isNegative ||
        estimatedUnits > BigInt.from(1000000) ||
        !this.expiresAt.isAfter(this.createdAt) ||
        this.expiresAt.difference(this.createdAt) > const Duration(hours: 24) ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(days: 366)) {
      throw const FormatException('Invalid bounded proposal.');
    }
  }
  static const commandCode = 'analytics.freeze_pipeline.v1';
  final String id,
      proposerId,
      commandId,
      parametersHash,
      horizonStart,
      horizonEnd;
  final int revision;
  final BigInt estimatedUnits;
  final RedactedForecastEvidence evidence;
  final DateTime createdAt, expiresAt;
  List<int> get canonicalBytes => utf8.encode(
    jsonEncode({
      'policyVersion': 1,
      'id': id,
      'revision': revision,
      'proposerId': proposerId,
      'commandId': commandId,
      'commandCode': commandCode,
      'scope': {
        'tenantId': evidence.scope.tenantId,
        'legalEntityId': evidence.scope.legalEntityId,
        'branchId': evidence.scope.branchId,
      },
      'horizonStart': horizonStart,
      'horizonEnd': horizonEnd,
      'sourceId': evidence.sourceId,
      'sourceHash': evidence.sourceHash,
      'targets': {
        for (final key in (evidence.targetVersions.keys.toList()..sort()))
          key: evidence.targetVersions[key],
      },
      'createdAt': _utc(createdAt),
      'expiresAt': _utc(expiresAt),
      'estimatedUnits': estimatedUnits.toString(),
    }),
  );
  Future<void> verifyHash(ProcessMetricHasher hasher) async {
    if (await hasher.sha256(canonicalBytes) != parametersHash) {
      throw const FormatException('Proposal hash does not bind this revision.');
    }
  }
}

String _utc(DateTime value) {
  final base = value.toIso8601String().split('.')[0];
  return '$base.${(value.millisecond * 1000 + value.microsecond).toString().padLeft(6, '0')}Z';
}

final class ProposalApproval {
  ProposalApproval({
    required String proposalId,
    required this.revision,
    required String parametersHash,
    required String approverId,
    required String approvedAt,
  }) : proposalId = _identity(proposalId),
       parametersHash = _hash(parametersHash),
       approverId = _identity(approverId),
       approvedAt = parseProcessMetricUtc(approvedAt);
  final String proposalId, parametersHash, approverId;
  final int revision;
  final DateTime approvedAt;
}

/// Validates a trusted authority observation; it cannot issue an approval or
/// replace online server permission/MFA/entitlement/source checks.
void validateProposalExecution(
  AiProposalRevision p,
  ProposalApproval a, {
  required DateTime now,
  required bool online,
  required bool approverMfa,
  required bool liveApproverPermission,
  required bool liveExecutorPermission,
  required bool entitlement,
  required bool quotaReserved,
  required ProcessMetricScope scope,
  required Map<String, String> liveTargetVersions,
}) {
  if (!now.isUtc ||
      !online ||
      !approverMfa ||
      !liveApproverPermission ||
      !liveExecutorPermission ||
      !entitlement ||
      !quotaReserved ||
      p.evidence.scope != scope ||
      a.proposalId != p.id ||
      a.revision != p.revision ||
      a.parametersHash != p.parametersHash ||
      a.approverId == p.proposerId ||
      a.approvedAt.isBefore(p.createdAt) ||
      !a.approvedAt.isBefore(p.expiresAt) ||
      now.isBefore(a.approvedAt) ||
      !now.isBefore(p.expiresAt)) {
    throw const FormatException(
      'Current distinct approval and live authority required.',
    );
  }
  if (liveTargetVersions.length != p.evidence.targetVersions.length ||
      p.evidence.targetVersions.entries.any(
        (e) => liveTargetVersions[e.key] != e.value,
      )) {
    throw const FormatException('Proposal target revisions changed.');
  }
}

enum InvocationOutcome { pending, unknown, settled }

final class InvocationReservation {
  InvocationReservation({
    required String id,
    required this.reservedUnits,
    required this.outcome,
    BigInt? settledUnits,
  }) : id = _identity(id),
       settledUnits = settledUnits {
    if (reservedUnits.isNegative ||
        (outcome == InvocationOutcome.settled) != (settledUnits != null) ||
        (settledUnits != null &&
            (settledUnits.isNegative || settledUnits > reservedUnits))) {
      throw const FormatException('Invalid usage settlement.');
    }
  }
  final String id;
  final BigInt reservedUnits;
  final BigInt? settledUnits;
  final InvocationOutcome outcome;
  BigInt get outstanding =>
      outcome == InvocationOutcome.settled ? BigInt.zero : reservedUnits;
}

BigInt quotaRemaining(
  BigInt limit,
  BigInt settledUsage,
  Iterable<InvocationReservation> reservations,
) {
  if (limit.isNegative || settledUsage.isNegative) {
    throw const FormatException('Invalid exact quota basis.');
  }
  var used = settledUsage;
  final ids = <String>{};
  for (final r in reservations) {
    if (!ids.add(r.id)) {
      throw const FormatException('Duplicate reservation identity.');
    }
    used += r.outstanding;
  }
  final left = limit - used;
  return left.isNegative ? BigInt.zero : left;
}

final class SyntheticTrial {
  SyntheticTrial({
    required String startsAt,
    required String endsAt,
    required this.planCode,
    required this.seats,
  }) : startsAt = parseProcessMetricUtc(startsAt),
       endsAt = parseProcessMetricUtc(endsAt) {
    if (!this.endsAt.isAfter(this.startsAt) ||
        this.endsAt.difference(this.startsAt) > const Duration(days: 366) ||
        !RegExp(r'^[a-z][a-z0-9_.-]{1,63}$').hasMatch(planCode) ||
        seats < 1 ||
        seats > 10000) {
      throw const FormatException('Invalid bounded synthetic trial.');
    }
  }
  final DateTime startsAt, endsAt;
  final String planCode;
  final int seats;
  bool activeAt(DateTime now) {
    if (!now.isUtc) throw const FormatException('UTC required.');
    return !now.isBefore(startsAt) && now.isBefore(endsAt);
  }
}

final class OperatorTenantGrant {
  OperatorTenantGrant({
    required String id,
    required String operatorId,
    required String tenantId,
    required this.reason,
    required String issuedAt,
    required String expiresAt,
  }) : id = _identity(id),
       operatorId = _identity(operatorId),
       tenantId = _identity(tenantId),
       issuedAt = parseProcessMetricUtc(issuedAt),
       expiresAt = parseProcessMetricUtc(expiresAt) {
    if (reason.trim().length < 10 ||
        reason.length > 500 ||
        !this.expiresAt.isAfter(this.issuedAt) ||
        this.expiresAt.difference(this.issuedAt) > const Duration(hours: 1)) {
      throw const FormatException('Invalid reasoned operator grant.');
    }
  }
  final String id, operatorId, tenantId, reason;
  final DateTime issuedAt, expiresAt;
  void requireAccess(
    String actor,
    String tenant,
    DateTime now, {
    required bool operatorAuthority,
    required bool mfa,
  }) {
    if (!operatorAuthority ||
        !mfa ||
        actor != operatorId ||
        tenant != tenantId ||
        !now.isUtc ||
        now.isBefore(issuedAt) ||
        !now.isBefore(expiresAt)) {
      throw const FormatException('Explicit current operator grant required.');
    }
  }
}

final class HealthProbe {
  HealthProbe({
    required this.code,
    required String observedAt,
    required this.value,
    required this.contractRevision,
  }) : observedAt = parseProcessMetricUtc(observedAt) {
    if (!{
          'worker_lag_seconds',
          'retry_count',
          'dead_letter_count',
          'quota_remaining',
        }.contains(code) ||
        contractRevision != 1 ||
        value.isNegative) {
      throw const FormatException('Invalid redacted health probe.');
    }
  }
  final String code;
  final DateTime observedAt;
  final BigInt value;
  final int contractRevision;
  String stateAt(DateTime generatedAt) =>
      !generatedAt.isUtc ||
          generatedAt.isBefore(observedAt) ||
          generatedAt.difference(observedAt) > const Duration(minutes: 5)
      ? 'unknown'
      : 'observed';
}
