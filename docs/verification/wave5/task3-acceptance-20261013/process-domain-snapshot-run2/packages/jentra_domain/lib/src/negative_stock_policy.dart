import 'exact_decimal.dart';
import 'validation.dart';

/// Immutable authority for an explicit shortage reservation.
final class NegativeStockOverride {
  const NegativeStockOverride({
    required this.policyVersion,
    required this.reason,
  });
  final BigInt policyVersion;
  final String reason;
  ValidationResult validate() => ValidationResult([
    if (policyVersion <= BigInt.zero)
      const ValidationIssue(
        field: 'policy_version',
        message: 'Choose a current active policy.',
      ),
    if (reason.trim().isEmpty || reason.trim().length > 1000)
      const ValidationIssue(
        field: 'reason',
        message: 'Enter a reason of 1 to 1000 characters.',
      ),
  ]);
  Map<String, Object?> toJson() => {
    'policy_version': policyVersion.toString(),
    'reason': reason.trim(),
  };
}

final class NegativeStockPolicy {
  const NegativeStockPolicy({
    required this.tenantId,
    required this.legalEntityId,
    required this.version,
    required this.active,
    this.id,
    this.reason,
    this.createdBy,
    this.createdAt,
  });
  final String tenantId, legalEntityId;
  final BigInt version;
  final bool active;
  final String? id, reason, createdBy;
  final DateTime? createdAt;
  factory NegativeStockPolicy.fromJson(Map<String, Object?> json) {
    final version = negativeStockInteger(json['policy_version']);
    if (json['active'] is! bool ||
        json['basis'] != 'last_authoritative_positive_average' ||
        json['cover_order'] != 'issue_ledger_fifo' ||
        json['tracking_scope'] != 'untracked') {
      throw const FormatException(
        'Negative-stock policy contract is unavailable.',
      );
    }
    final id = _optionalText(json['id']);
    if ((version == BigInt.zero && (id != null || json['active'] == true)) ||
        (version > BigInt.zero && id == null)) {
      throw const FormatException('Policy version and identity disagree.');
    }
    if (version > BigInt.zero &&
        (json['reason'] == null ||
            json['created_by'] == null ||
            json['created_at'] == null)) {
      throw const FormatException('Policy attribution is unavailable.');
    }
    return NegativeStockPolicy(
      tenantId: _text(json['tenant_id']),
      legalEntityId: _text(json['legal_entity_id']),
      version: version,
      active: json['active']! as bool,
      id: id,
      reason: _optionalText(json['reason']),
      createdBy: _optionalText(json['created_by']),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(_text(json['created_at'])),
    );
  }
}

enum NegativeStockEvidenceKind { deficits, covers }

final class NegativeStockEvidence {
  NegativeStockEvidence._(this.kind, this.values, this.ledgerId);
  final NegativeStockEvidenceKind kind;
  final Map<String, Object?> values;
  final BigInt ledgerId;
  factory NegativeStockEvidence.fromJson(
    NegativeStockEvidenceKind kind,
    Map<String, Object?> json,
  ) {
    final id = negativeStockInteger(json['id'], positive: true);
    for (final key in [
      'quantity',
      'provisional_value',
      if (kind == NegativeStockEvidenceKind.deficits)
        'open_quantity'
      else ...[
        'actual_value',
        'variance',
      ],
    ]) {
      final raw = _text(json[key]);
      if (!RegExp(r'^-?\d+(\.\d{1,6})?$').hasMatch(raw)) {
        throw const FormatException('Evidence requires exact decimal strings.');
      }
      ExactDecimal.parse(raw, scale: 6);
    }
    ExactDecimal amount(String key) =>
        ExactDecimal.parse(json[key]! as String, scale: 6);
    if (!amount('quantity').isPositive ||
        amount('provisional_value').scaledValue < BigInt.zero) {
      throw const FormatException('Deficit quantity or cost is invalid.');
    }
    if (kind == NegativeStockEvidenceKind.deficits) {
      if (amount('open_quantity').scaledValue < BigInt.zero ||
          amount('open_quantity').scaledValue >
              amount('quantity').scaledValue) {
        throw const FormatException('Open deficit quantity is invalid.');
      }
    } else if (amount('actual_value').scaledValue < BigInt.zero ||
        amount('actual_value') - amount('provisional_value') !=
            amount('variance')) {
      throw const FormatException('Cover values do not reconcile.');
    }
    for (final key in [
      'posting_date',
      'command_id',
      'created_at',
      'created_by',
      if (kind == NegativeStockEvidenceKind.deficits) ...[
        'issue_movement_line_id',
        'policy_id',
        'basis_id',
        'warehouse_id',
        'product_id',
      ] else ...[
        'deficit_id',
        'movement_line_id',
        'kind',
        'request_id',
      ],
    ]) {
      _text(json[key]);
    }
    if (kind == NegativeStockEvidenceKind.deficits) {
      negativeStockInteger(json['policy_version'], positive: true);
    } else if (!{'receipt', 'customer_return'}.contains(json['kind'])) {
      throw const FormatException('Unknown cover provenance.');
    }
    return NegativeStockEvidence._(kind, Map.unmodifiable(json), id);
  }
}

final class NegativeStockEvidencePage {
  NegativeStockEvidencePage({
    required List<NegativeStockEvidence> items,
    this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<NegativeStockEvidence> items;
  final BigInt? nextCursor;
  factory NegativeStockEvidencePage.fromJson(
    NegativeStockEvidenceKind kind,
    Map<String, Object?> json,
  ) {
    final raw = json['items'];
    if (raw is! List || raw.length > 50) {
      throw const FormatException(
        'Evidence page must contain at most fifty records.',
      );
    }
    final items = raw.map((row) {
      if (row is! Map) {
        throw const FormatException('Evidence record is unavailable.');
      }
      return NegativeStockEvidence.fromJson(kind, row.cast<String, Object?>());
    }).toList();
    for (var i = 1; i < items.length; i++) {
      if (items[i].ledgerId <= items[i - 1].ledgerId) {
        throw const FormatException('Evidence ledger order is invalid.');
      }
    }
    final cursor = json['next_cursor'] == null
        ? null
        : negativeStockInteger(json['next_cursor'], positive: true);
    if (cursor != null && (items.isEmpty || cursor != items.last.ledgerId)) {
      throw const FormatException(
        'Evidence cursor must identify the final record.',
      );
    }
    return NegativeStockEvidencePage(items: items, nextCursor: cursor);
  }
}

BigInt negativeStockInteger(Object? raw, {bool positive = false}) {
  if (raw is! String || !RegExp(r'^(0|[1-9]\d*)$').hasMatch(raw)) {
    throw const FormatException('Expected an exact integer string.');
  }
  final value = BigInt.parse(raw);
  if (positive && value == BigInt.zero) {
    throw const FormatException('Expected a positive ledger identity.');
  }
  return value;
}

String _text(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    throw const FormatException('Evidence identity is unavailable.');
  }
  return raw;
}

String? _optionalText(Object? raw) => raw == null ? null : _text(raw);
