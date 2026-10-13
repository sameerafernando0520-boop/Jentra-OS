import 'exact_decimal.dart';

/// Bounded progress for independent documents sharing one physical cutoff.
/// Quantities and approval values remain exact decimal strings/BigInt.
final class CountPartitionProgress {
  CountPartitionProgress._(
    this.id,
    this.cutoff,
    this.expectedIdentities,
    this.capturedIdentities,
    this.expectedPartitions,
    this.capturedPartitions,
    this.postedPartitions,
    this.cancelledPartitions,
    this.baseline,
    this.counted,
    this.variance,
    this.approvalValue,
    this.captureComplete,
    this.postingComplete,
    this.missingOrdinals,
    this.items,
    this.nextCursor,
  );

  final String id;
  final DateTime cutoff;
  final int expectedIdentities,
      capturedIdentities,
      expectedPartitions,
      capturedPartitions,
      postedPartitions,
      cancelledPartitions;
  final ExactDecimal baseline, counted, variance, approvalValue;
  final bool captureComplete, postingComplete;
  final List<int> missingOrdinals;
  final List<Map<String, Object?>> items;
  final int? nextCursor;

  factory CountPartitionProgress.fromJson(Map<String, Object?> json) {
    Never invalid() =>
        throw const FormatException('Invalid count partition progress.');
    int count(String key, int max) {
      final v = json[key];
      if (v is! int || v < 0 || v > max) {
        invalid();
      }
      return v;
    }

    ExactDecimal decimal(String key, {bool signed = false}) {
      final v = json[key];
      if (v is! String ||
          !RegExp(
            signed ? r'^-?\d{1,14}(\.\d{1,6})?$' : r'^\d{1,14}(\.\d{1,6})?$',
          ).hasMatch(v)) {
        invalid();
      }
      return ExactDecimal.parse(v, scale: 6);
    }

    final id = json['id'], timestamp = json['cutoff_at'];
    if (id is! String || id.isEmpty || timestamp is! String) {
      invalid();
    }
    final cutoff = DateTime.tryParse(timestamp);
    if (cutoff == null) {
      invalid();
    }
    final expectedIds = count('expected_identity_count', 10000);
    final capturedIds = count('captured_identity_count', 10000);
    final expected = count('expected_partition_count', 20);
    final captured = count('captured_partition_count', 20);
    final posted = count('posted_partition_count', 20);
    final cancelled = count('cancelled_partition_count', 20);
    final complete = json['capture_complete'],
        finished = json['posting_complete'];
    if (expectedIds == 0 ||
        expected != (expectedIds + 499) ~/ 500 ||
        captured > expected ||
        capturedIds > expectedIds ||
        posted + cancelled > captured ||
        complete is! bool ||
        finished is! bool) {
      invalid();
    }
    final missing = json['missing_partition_ordinals'];
    if (missing is! List ||
        missing.any((x) => x is! int || x < 1 || x > expected)) {
      invalid();
    }
    final absent = missing.cast<int>();
    if (absent.toSet().length != absent.length ||
        absent.length != expected - captured ||
        (complete &&
            (capturedIds != expectedIds ||
                captured != expected ||
                absent.isNotEmpty)) ||
        (finished && (!complete || posted != expected || cancelled != 0))) {
      invalid();
    }
    final baseline = decimal('baseline_quantity'),
        counted = decimal('counted_quantity');
    final variance = decimal('variance_quantity', signed: true),
        approval = decimal('grand_total');
    if (counted - baseline != variance) {
      invalid();
    }
    final rawItems = json['items'] ?? const [];
    if (rawItems is! List || rawItems.length > 50) {
      invalid();
    }
    final ids = <String>{}, ordinals = <int>{};
    var previous = 0;
    final items = <Map<String, Object?>>[];
    for (final raw in rawItems) {
      if (raw is! Map) {
        invalid();
      }
      final item = raw.cast<String, Object?>();
      final itemId = item['id'],
          ordinal = item['partition_ordinal'],
          quantity = item['identity_count'];
      if (itemId is! String ||
          itemId.isEmpty ||
          !ids.add(itemId) ||
          ordinal is! int ||
          ordinal <= previous ||
          ordinal < 1 ||
          ordinal > expected ||
          !ordinals.add(ordinal) ||
          quantity is! int ||
          quantity < 1 ||
          quantity > 500 ||
          item['status'] is! String ||
          item['version'] is! int ||
          (item['version'] as int) < 1) {
        invalid();
      }
      for (final key in [
        'baseline_quantity',
        'counted_quantity',
        'variance_quantity',
        'grand_total',
      ]) {
        final value = item[key];
        if (value is! String ||
            !RegExp(r'^-?\d{1,14}(\.\d{1,6})?$').hasMatch(value)) {
          invalid();
        }
      }
      previous = ordinal;
      items.add(Map.unmodifiable(item));
    }
    final cursor = json['next_cursor'];
    if (cursor != null &&
        (cursor is! int ||
            items.isEmpty ||
            cursor != previous ||
            cursor >= expected)) {
      invalid();
    }
    return CountPartitionProgress._(
      id,
      cutoff.toUtc(),
      expectedIds,
      capturedIds,
      expected,
      captured,
      posted,
      cancelled,
      baseline,
      counted,
      variance,
      approval,
      complete,
      finished,
      List.unmodifiable(absent),
      List.unmodifiable(items),
      cursor as int?,
    );
  }
}

Map<String, Object?> countPartitionCapturePayload(Map<String, Object?> form) {
  final result = <String, Object?>{};
  for (final key in [
    'id',
    'warehouse_id',
    'product_id',
    'offset_account_id',
    'document_date',
    'reason',
  ]) {
    final value = form[key];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException(
        'Select a warehouse, tracked product and variance account, then enter a date and reason.',
      );
    }
    result[key] = value;
  }
  final date = DateTime.tryParse(result['document_date'] as String);
  if (date == null ||
      date.toIso8601String().substring(0, 10) != result['document_date'] ||
      (result['reason'] as String).trim().length < 3 ||
      (result['reason'] as String).length > 1000) {
    throw const FormatException(
      'Enter a valid YYYY-MM-DD date and a reason of 3–1,000 characters.',
    );
  }
  return Map.unmodifiable(result);
}
