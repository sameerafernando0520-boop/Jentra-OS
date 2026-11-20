import 'dart:convert';
import 'dart:io';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:test/test.dart';

/// The same worked cases run against the SQL candidate
/// (supabase/candidates/tests/lk_statutory_payroll_test.sql).
void main() {
  final doc =
      jsonDecode(
            File(
              'test/fixtures/lk_statutory_payroll_cases.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final defaultEmployee = doc['employee']! as Map<String, Object?>;
  Money lkr(String value) => Money.parse(value, 'LKR');

  for (final raw in doc['cases']! as List<Object?>) {
    final c = raw! as Map<String, Object?>;
    test(c['name']! as String, () {
      final ruleSetJson = c.containsKey('rule_set')
          ? c['rule_set']
          : doc['rule_set'];
      final employeeJson = c.containsKey('employee')
          ? c['employee']
          : {
              ...defaultEmployee,
              ...?(c['employee_overrides'] as Map<String, Object?>?),
            };
      final codes = c.containsKey('statutory_codes')
          ? {
              for (final code in c['statutory_codes']! as List<Object?>)
                code! as String,
            }
          : {'EPF_EE', 'EPF_ER', 'ETF_ER', 'APIT'};
      final earnings = [
        for (final e
            in (c['earnings']! as List<Object?>).cast<Map<String, Object?>>())
          e['classified'] == false
              ? LkStatutoryEarning(
                  code: e['code']! as String,
                  amount: lkr(e['amount']! as String),
                )
              : LkStatutoryEarning(
                  code: e['code']! as String,
                  amount: lkr(e['amount']! as String),
                  epfLiable: e['epf']! as bool,
                  etfLiable: e['etf']! as bool,
                  apitRegularProfit: e['apit']! as bool,
                ),
      ];
      LkStatutoryResult run() => calculateLkStatutory(
        ruleSet: ruleSetJson == null
            ? null
            : LkStatutoryRuleSet.fromJson(ruleSetJson as Map<String, Object?>),
        employee: employeeJson == null
            ? null
            : LkStatutoryEmployee.fromJson(
                employeeJson as Map<String, Object?>,
              ),
        earnings: earnings,
        statutoryCodes: codes,
        periodStart: (c['start_date'] as String?) ?? '2026-05-01',
        periodEndExclusive:
            (c['end_date_exclusive'] as String?) ?? '2026-06-01',
        cumulativeRegularProfitsBefore: lkr(
          (c['cumulative_regular_profits_before'] as String?) ?? '0',
        ),
      );
      final expect_ = c['expect']! as Map<String, Object?>;
      if (expect_.containsKey('blocked')) {
        expect(
          run,
          throwsA(
            isA<LkStatutoryBlocked>().having(
              (b) => b.reason,
              'reason',
              expect_['blocked'],
            ),
          ),
        );
        return;
      }
      final result = run();
      final lines = expect_['lines']! as Map<String, Object?>;
      expect(result.lines.keys.toSet(), lines.keys.toSet());
      for (final MapEntry(:key, :value) in lines.entries) {
        expect(result.lines[key], lkr(value! as String), reason: key);
      }
      expect(result.gross, lkr(expect_['gross']! as String));
      expect(result.deductions, lkr(expect_['deductions']! as String));
      expect(result.employerCost, lkr(expect_['employer_cost']! as String));
      expect(result.net, lkr(expect_['net']! as String));
    });
  }

  test('only the four statutory codes are accepted', () {
    expect(
      () => calculateLkStatutory(
        ruleSet: null,
        employee: null,
        earnings: const [],
        statutoryCodes: {'SSCL'},
        periodStart: '2026-05-01',
        periodEndExclusive: '2026-06-01',
        cumulativeRegularProfitsBefore: Money.zero('LKR'),
      ),
      throwsFormatException,
    );
  });
}
