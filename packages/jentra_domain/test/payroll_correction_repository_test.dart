import 'package:jentra_domain/jentra_payroll.dart';
import 'package:test/test.dart';

const id = '10000000-0000-0000-0000-000000000001';
Map<String, Object?> form() => {
  'action': 'prepare',
  'id': id,
  'original_calculation_id': id,
  'posting_date': '2026-10-02',
  'reason': 'Synthetic',
  'replacements': [
    {
      'seal_id': id,
      'before_revision_id': id,
      'expected_version': 1,
      'paid_seconds': 3600,
      'impact': {
        'mode': 'geometry',
        'expected_source_version': 3,
        'start_local': '2026-10-01T09:00:00',
        'end_local': '2026-10-01T10:00:00',
        'start_offset_seconds': 19800,
        'end_offset_seconds': 19800,
        'breaks': <Object?>[],
      },
    },
  ],
};
void main() {
  test(
    'legitimate geometry keeps whole seconds, version and original identity',
    () {
      PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        form(),
        0,
      );
    },
  );
  test('duplicate or foreign fields fail before source side effects', () {
    final p = form();
    (p['replacements'] as List).add((p['replacements'] as List).first);
    expect(
      () => PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        p,
        0,
      ),
      throwsFormatException,
    );
    final private = form()..['bank_number'] = 'PRIVATE';
    expect(
      () => PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        private,
        0,
      ),
      throwsFormatException,
    );
  });
  test('fractional seconds and unselected offsets are rejected', () {
    final p = form(),
        r = (p['replacements'] as List).single as Map<String, Object?>;
    r['paid_seconds'] = 3600.5;
    expect(
      () => PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        p,
        0,
      ),
      throwsFormatException,
    );
    r['paid_seconds'] = 3600;
    (r['impact'] as Map)['start_offset_seconds'] = 64801;
    expect(
      () => PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        p,
        0,
      ),
      throwsFormatException,
    );
  });
  test('geometry breaks preserve exact whole-second ordered UTC evidence', () {
    final p = form();
    final impact = ((p['replacements'] as List).single as Map)['impact'] as Map;
    impact['breaks'] = [
      {'start_utc': '2026-10-01T04:00:00Z', 'end_utc': '2026-10-01T04:15:00Z'},
    ];
    PayrollCorrectionCommands.validate(
      PayrollCorrectionCommandKind.correction,
      p,
      0,
    );
    (impact['breaks'] as List).single['start_utc'] = '2026-10-01T04:00:00.5Z';
    expect(
      () => PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        p,
        0,
      ),
      throwsFormatException,
    );
    (impact['breaks'] as List).single['start_utc'] = '2026-10-01T04:30:00Z';
    expect(
      () => PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        p,
        0,
      ),
      throwsFormatException,
    );
  });
  test(
    'leave cancellation cannot retain pay and allocations retain unique identities',
    () {
      final p = form(), r = (p['replacements'] as List).single as Map;
      r['impact'] = {'mode': 'cancel_leave', 'expected_source_version': 3};
      expect(
        () => PayrollCorrectionCommands.validate(
          PayrollCorrectionCommandKind.correction,
          p,
          0,
        ),
        throwsFormatException,
      );
      r['paid_seconds'] = 0;
      PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        p,
        0,
      );
      r['impact'] = {
        'mode': 'geometry',
        'expected_source_version': 3,
        'start_local': '2026-10-01T09:00:00',
        'end_local': '2026-10-01T10:00:00',
        'start_offset_seconds': 19800,
        'end_offset_seconds': 19800,
        'breaks': [],
        'allocation_changes': [
          {'entry_id': id, 'mode': 'retain'},
          {'entry_id': id, 'mode': 'remove'},
        ],
      };
      expect(
        () => PayrollCorrectionCommands.validate(
          PayrollCorrectionCommandKind.correction,
          p,
          0,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'settlement allocations have explicit signed direction and exact positive amounts',
    () {
      final p = {
        'action': 'record',
        'id': id,
        'correction_id': id,
        'posting_date': '2026-10-02',
        'bank_id': id,
        'bank_version': 1,
        'direction': 'recover',
        'evidence_reference': 'SYNTHETIC',
        'reason': 'Synthetic',
        'allocations': [
          {'balance_id': id, 'amount': '12.340000'},
        ],
      };
      PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.settlement,
        p,
        0,
      );
      (p['allocations'] as List).single['amount'] = '-12.34';
      expect(
        () => PayrollCorrectionCommands.validate(
          PayrollCorrectionCommandKind.settlement,
          p,
          0,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'reversal separates current billing identity from frozen original proof',
    () {
      final p = <String, Object?>{
        'action': 'reverse',
        'id': id,
        'digest': 'a' * 64,
        'posting_date': '2026-10-02',
        'reason': 'Synthetic current original credit',
        'current_billing_impacts': [
          {
            'seal_id': id,
            'source_revision_id': id,
            'expected_source_version': 4,
            'billing_credit_line_ids': <String>[],
            'allocation_credits': [
              {
                'entry_id': id,
                'source_revision_id': id,
                'expected_source_version': 5,
                'billing_credit_line_ids': [id],
              },
            ],
          },
        ],
      };
      PayrollCorrectionCommands.validate(
        PayrollCorrectionCommandKind.correction,
        p,
        3,
      );
      final credits =
          ((p['current_billing_impacts'] as List).single
                  as Map)['allocation_credits']
              as List;
      credits.add(Map<String, Object>.from(credits.single as Map));
      expect(
        () => PayrollCorrectionCommands.validate(
          PayrollCorrectionCommandKind.correction,
          p,
          3,
        ),
        throwsFormatException,
      );
    },
  );
}
