import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/analytics_platform.dart';

String id(int n) => '20000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
Map<String, Object?> ratio(String n, String d, String? v, String? why) => {
  'numerator': n,
  'denominator': d,
  'exactValue': v,
  'unavailableReason': why,
};
Future<Map<String, Object?>> wire({
  bool foreign = false,
  bool wrong = false,
  bool classified = false,
}) async {
  final text = jsonEncode({
    'contractRevision': 1,
    'formulaVersion': 1,
    'scope': {
      'tenantId': foreign ? id(9) : id(1),
      'legalEntityId': id(2),
      'branchId': id(3),
    },
    'profitLossId': id(4),
    'balanceSheetId': id(5),
    'classificationId': classified ? id(6) : null,
    'profitLossHash': 'a' * 64,
    'balanceSheetHash': 'b' * 64,
    'currency': 'LKR',
    'periodStart': '2026-10-01',
    'asOf': '2026-10-07',
    'ratios': {
      'net_profit_margin': ratio(
        '1.000001',
        '3.000000',
        wrong ? '0.333333' : '0.333334',
        null,
      ),
      'liabilities_to_assets': ratio('0', '1', '0.000000', null),
      'assets_to_equity': ratio('1', '0', null, 'ZERO_DENOMINATOR'),
      if (classified) ...{
        'current_ratio': ratio('4', '2', '2.000000', null),
        'quick_ratio': ratio('3', '2', '1.500000', null),
        'gross_profit_margin': ratio('2', '3', '0.666667', null),
      },
    },
  });
  return {
    'canonicalText': text,
    'sourceHash': await ProcessMetricSha256Hasher().sha256(utf8.encode(text)),
  };
}

void main() {
  final context = TenantContext(
    actorId: id(7),
    tenantId: id(1),
    legalEntityId: id(2),
    branchId: id(3),
  );
  test(
    'statement publication verifies exact rounding, real zero and zero denominator separately',
    () async {
      final rows = await StatementRatioAdapter(
        (_, _) => wire(),
      ).read(context, id(4), id(5));
      expect(rows['net_profit_margin']!.exactValue, '0.333334');
      expect(rows['liabilities_to_assets']!.exactValue, '0.000000');
      expect(rows['assets_to_equity']!.unavailableReason, 'ZERO_DENOMINATOR');
    },
  );
  test(
    'classification-bound publication contains all six named formulas',
    () async {
      final rows = await StatementRatioAdapter(
        (_, _) => wire(classified: true),
      ).read(context, id(4), id(5), classificationId: id(6));
      expect(rows.length, 6);
      expect(rows['quick_ratio']!.exactValue, '1.500000');
    },
  );
  test(
    'foreign scope and plausible arithmetic mismatch are rejected',
    () async {
      for (final w in [wire(foreign: true), wire(wrong: true)]) {
        await expectLater(
          StatementRatioAdapter((_, _) => w).read(context, id(4), id(5)),
          throwsFormatException,
        );
      }
    },
  );
}
