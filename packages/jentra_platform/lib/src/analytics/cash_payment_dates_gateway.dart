import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show ExactDecimal;
import 'process_metric_gateway.dart';

const cashDateSourceKinds = {
  'payroll_obligation',
  'payroll_correction',
  'project_reimbursement',
};

final class CashPaymentDateSource {
  CashPaymentDateSource(Map row, this.kind) {
    if (!cashDateSourceKinds.contains(kind) ||
        row['sourceKind'] != kind ||
        row['sourceId'] is! String ||
        row['sourceHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['sourceHash'] as String) ||
        row['inflow'] is! bool ||
        row['branchId'] is! String ||
        row['currency'] is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(row['currency'] as String)) {
      throw const FormatException('Invalid authoritative payment-date source.');
    }
    id = row['sourceId'] as String;
    branch = row['branchId'] as String;
    ProcessMetricScope(tenantId: id, legalEntityId: branch);
    hash = row['sourceHash'] as String;
    currency = row['currency'] as String;
    original = _amount(row['originalAmount']);
    remaining = _amount(row['remainingAmount']);
    inflow = row['inflow'] as bool;
    issueDate = row['issueDate'] as String;
    parseProcessMetricUtc('${issueDate}T00:00:00Z');
    if (remaining == BigInt.zero ||
        original == BigInt.zero ||
        remaining.isNegative != original.isNegative ||
        remaining.abs() > original.abs() ||
        inflow != original.isNegative ||
        (kind != 'payroll_correction' && inflow)) {
      throw const FormatException('Invalid signed remaining obligation.');
    }
    final approved = row['approved'];
    version = '0';
    if (approved != null) {
      if (approved is! Map ||
          approved['sourceHash'] != hash ||
          approved['version'] is! String ||
          !RegExp(
            r'^[1-9][0-9]{0,15}$',
          ).hasMatch(approved['version'] as String) ||
          BigInt.parse(approved['version'] as String) >
              BigInt.parse('9007199254740991')) {
        throw const FormatException('Invalid approved payment-date revision.');
      }
      version = approved['version'] as String;
      approvedDate = approved['dueDate'] as String;
      parseProcessMetricUtc('${approvedDate}T00:00:00Z');
    }
  }
  final String kind;
  late final String id, hash, branch, currency, version, issueDate;
  String? approvedDate;
  late final BigInt original, remaining;
  late final bool inflow;
  static BigInt _amount(Object? raw) {
    if (raw is! String ||
        !RegExp(r'^-?(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$').hasMatch(raw)) {
      throw const FormatException('Exact obligation amount required.');
    }
    return ExactDecimal.parse(raw, scale: 6).scaledValue;
  }
}

final class CashPaymentDatesGateway {
  const CashPaymentDatesGateway(this.rpc);
  final ProcessMetricRpc rpc;
  Map<String, Object?> _scope(ProcessMetricScope s) => {
    'p_tenant_id': s.tenantId,
    'p_legal_entity_id': s.legalEntityId,
    'p_branch_id': s.branchId,
  };
  Future<void> authorize(
    ProcessMetricScope scope,
    String actor,
    String kind,
  ) async {
    if (scope.branchId == null ||
        !cashDateSourceKinds.contains(kind) ||
        await rpc('wave5_cash_date_authorize', {
              ..._scope(scope),
              'p_kind': kind,
            }) !=
            actor) {
      throw StateError('Current MFA payment-date authority required.');
    }
  }

  Future<(List<CashPaymentDateSource>, String?)> sources(
    ProcessMetricScope scope,
    String kind, {
    String? after,
  }) async {
    if (after != null) {
      ProcessMetricScope(tenantId: after, legalEntityId: after);
    }
    final raw = await rpc('wave5_cash_date_sources', {
      ..._scope(scope),
      'p_kind': kind,
      'p_after': after,
    });
    if (raw is! Map ||
        raw.length != 2 ||
        raw['rows'] is! List ||
        (raw['rows'] as List).length > 50 ||
        (raw['next'] != null && raw['next'] is! String)) {
      throw const FormatException('Invalid payment-date page.');
    }
    final rows = <CashPaymentDateSource>[];
    final ids = <String>{};
    String? prior = after;
    for (final row in raw['rows'] as List) {
      if (row is! Map) {
        throw const FormatException('Invalid payment-date source.');
      }
      final source = CashPaymentDateSource(row, kind);
      if (source.branch != scope.branchId ||
          !ids.add(source.id) ||
          (prior != null && source.id.compareTo(prior) <= 0)) {
        throw const FormatException(
          'Payment-date source scope or ordering changed.',
        );
      }
      prior = source.id;
      rows.add(source);
    }
    final next = raw['next'] as String?;
    if (next != null && (rows.length != 50 || rows.last.id != next)) {
      throw const FormatException('Invalid payment-date cursor.');
    }
    return (List<CashPaymentDateSource>.unmodifiable(rows), next);
  }

  Future<Map<String, Object?>> proposal(
    ProcessMetricScope scope,
    String kind,
    String id,
  ) async {
    ProcessMetricScope(tenantId: id, legalEntityId: id);
    final raw = await rpc('wave5_cash_date_get', {
      ..._scope(scope),
      'p_id': id,
    });
    if (raw is! Map ||
        raw['id'] != id ||
        raw['sourceKind'] != kind ||
        raw['proposalHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['proposalHash'] as String) ||
        raw['expectedVersion'] is! String ||
        raw['preparedBy'] is! String ||
        raw['dueDate'] is! String ||
        !{null, 'approved', 'rejected'}.contains(raw['decision'])) {
      throw const FormatException('Payment-date proposal changed.');
    }
    ProcessMetricScope(
      tenantId: raw['sourceId'] as String,
      legalEntityId: raw['preparedBy'] as String,
    );
    parseProcessMetricUtc('${raw['dueDate']}T00:00:00Z');
    parseProcessMetricUtc(raw['preparedAt'] as String);
    return Map.unmodifiable(raw.cast<String, Object?>());
  }

  Future<Map<String, Object?>> command(
    ProcessMetricScope scope,
    Map<String, Object?> envelope,
  ) async {
    final raw = await rpc('wave5_cash_date_command', {
      ..._scope(scope),
      'p_command_id': envelope['commandId'],
      'p_idempotency_key': envelope['idempotencyKey'],
      'p_issued_at': envelope['clientTimestamp'],
      'p_action': envelope['action'],
      'p_payload': envelope['payload'],
    });
    final receipt = raw is Map ? raw['entity'] : null;
    final payload = envelope['payload'] as Map;
    if (receipt is! Map ||
        receipt['id'] != payload['id'] ||
        receipt['version'] is! String ||
        receipt['proposalHash'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(receipt['proposalHash'] as String) ||
        receipt['status'] !=
            switch (envelope['action']) {
              'prepare' => 'prepared',
              'approve' => 'approved',
              'reject' => 'rejected',
              _ => null,
            } ||
        (envelope['action'] != 'prepare' &&
            receipt['proposalHash'] != payload['proposalHash'])) {
      throw const FormatException('Payment-date command receipt mismatch.');
    }
    return Map.unmodifiable(receipt.cast<String, Object?>());
  }
}
