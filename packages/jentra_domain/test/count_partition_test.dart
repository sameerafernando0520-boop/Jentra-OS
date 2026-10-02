import 'package:jentra_domain/count_partitions.dart';
import 'package:test/test.dart';

Map<String, Object?> progress({bool complete = true}) => {
  'id': 'group',
  'cutoff_at': '2026-09-30T08:00:00Z',
  'expected_identity_count': 501,
  'captured_identity_count': 501,
  'expected_partition_count': 2,
  'captured_partition_count': 2,
  'posted_partition_count': complete ? 2 : 1,
  'cancelled_partition_count': 0,
  'missing_partition_ordinals': <int>[],
  'capture_complete': true,
  'posting_complete': complete,
  'baseline_quantity': '90071992547409.123456',
  'counted_quantity': '90071992547409.123455',
  'variance_quantity': '-0.000001',
  'grand_total': '0.000001',
};

void main() {
  test(
    'progress conserves exact values beyond binary floating point precision',
    () {
      final p = CountPartitionProgress.fromJson(progress());
      expect(p.baseline.toDecimalString(), '90071992547409.123456');
      expect(p.counted.toDecimalString(), '90071992547409.123455');
      expect((p.counted - p.baseline).scaledValue, BigInt.from(-1));
      expect(p.postingComplete, isTrue);
      expect(
        CountPartitionProgress.fromJson(
          progress(complete: false),
        ).postingComplete,
        isFalse,
      );
    },
  );
  test(
    'missing and duplicate partition identities cannot claim completion',
    () {
      expect(
        () => CountPartitionProgress.fromJson({
          ...progress(),
          'captured_identity_count': 500,
        }),
        throwsFormatException,
      );
      expect(
        () => CountPartitionProgress.fromJson({
          ...progress(),
          'posted_partition_count': 1,
        }),
        throwsFormatException,
      );
      expect(
        () => CountPartitionProgress.fromJson({
          ...progress(),
          'missing_partition_ordinals': [2, 2],
        }),
        throwsFormatException,
      );
      expect(
        () => CountPartitionProgress.fromJson({
          ...progress(),
          'variance_quantity': '0',
        }),
        throwsFormatException,
      );
      expect(
        () => CountPartitionProgress.fromJson({
          ...progress(),
          'grand_total': 0.000001,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'capture request includes exact approved scope fields without caller baseline',
    () {
      final p = countPartitionCapturePayload({
        'id': 'group',
        'warehouse_id': 'warehouse',
        'product_id': 'product',
        'offset_account_id': 'account',
        'document_date': '2026-09-30',
        'reason': 'Review physical count',
        'lines': ['stale'],
      });
      expect(p.containsKey('lines'), isFalse);
      expect(
        () =>
            countPartitionCapturePayload({...p, 'document_date': '2026-02-30'}),
        throwsFormatException,
      );
    },
  );
}
