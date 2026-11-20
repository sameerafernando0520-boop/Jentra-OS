import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_tax_lk.dart';
import 'package:test/test.dart';

Map<String, Object?> line(String wire, String value, String tax) => {
  'line': wire,
  'value': value,
  'tax': tax,
};

Map<String, Object?> scheduleRow(
  String doc,
  String wire,
  String value,
  String tax, {
  String name = 'Lanka Traders',
}) => {
  'line': wire,
  'source_type': 'sales_invoice',
  'posting_date': '2026-05-10',
  'document_number': doc,
  'counterparty_name': name,
  'counterparty_tin': '114567890',
  'tax_code': 'VAT18',
  'value': value,
  'tax': tax,
};

/// Shaped like api.lk_vat_return for the SQL harness's worked month.
Map<String, Object?> workpaper({String net = '100800.000000'}) => {
  'from': '2026-05-01',
  'to_exclusive': '2026-06-01',
  'entity_tin': '114000001',
  'lines': [
    line('standard_rated_supply', '900000.000000', '162000.000000'),
    line('zero_rated_supply', '500000.000000', '0.000000'),
    line('exempt_supply', '200000.000000', '0.000000'),
    line('input_claimable', '340000.000000', '61200.000000'),
    line('input_not_claimable', '100000.000000', '18000.000000'),
    line('outside_vat', '0.000000', '0.000000'),
  ],
  'output_tax': '162000.000000',
  'input_tax_claimable': '61200.000000',
  'net_payable': net,
  'blockers': [
    {
      'reason': 'VAT_MAPPING_REQUIRED',
      'document_number': 'BILL-3',
      'tax_code': 'VAT18',
    },
  ],
  'output_schedule': [
    scheduleRow(
      'INV-1',
      'standard_rated_supply',
      '1000000.000000',
      '180000.000000',
    ),
    scheduleRow(
      'SR-1',
      'standard_rated_supply',
      '-100000.000000',
      '-18000.000000',
      name: '=HYPERLINK("x")',
    ),
  ],
  'input_schedule': const [],
};

void main() {
  test('the workpaper CSV has return lines, schedules and blockers', () {
    final csv = LkVatReturn.fromJson(workpaper()).toCsv().split('\r\n');
    expect(
      csv.first,
      'Section,Line,Date,Document,Counterparty,Counterparty TIN,Tax code,Value (LKR),VAT (LKR)',
    );
    expect(
      csv,
      contains('Return,Standard-rated supplies,,,,,,900000.00,162000.00'),
    );
    expect(csv, contains('Return,Net payable,,,,,,,100800.00'));
    expect(
      csv,
      contains(
        'Output schedule,Standard-rated supplies,2026-05-10,INV-1,Lanka Traders,114567890,VAT18,1000000.00,180000.00',
      ),
    );
    expect(csv, contains('Blocker,VAT_MAPPING_REQUIRED,,BILL-3,,,VAT18,,'));
  });

  test('negative amounts stay numbers while formula names are neutralized', () {
    final csv = LkVatReturn.fromJson(workpaper()).toCsv();
    expect(csv, contains(',-100000.00,-18000.00'));
    expect(csv, contains('"\'=HYPERLINK(""x"")"'));
  });

  test('a refund position is labelled', () {
    final r = LkVatReturn.fromJson(workpaper(net: '-2500.000000'));
    expect(r.refundable, isTrue);
    expect(r.toCsv(), contains('Return,Net refundable,,,,,,,-2500.00'));
  });

  test('blockers explain themselves', () {
    final r = LkVatReturn.fromJson(workpaper());
    expect(
      r.blockers.single.message,
      contains('VAT18 has no approved VAT return line'),
    );
  });

  test('VAT line rules match the server', () {
    Money pct(String v) => Money.parse(v, 'LKR');
    expect(LkVatLine.standardRatedSupply.suits('output', pct('18')), isTrue);
    expect(LkVatLine.standardRatedSupply.suits('output', pct('0')), isFalse);
    expect(LkVatLine.zeroRatedSupply.suits('zero', pct('0')), isTrue);
    expect(LkVatLine.inputClaimable.suits('output', pct('18')), isFalse);
    expect(LkVatLine.exemptSupply.suits('input', pct('0')), isFalse);
    expect(LkVatLine.outsideVat.suits('withholding', pct('5')), isTrue);
  });

  Map<String, Object?> sscl({bool settings = true}) => {
    'quarter_start': '2026-04-01',
    'quarter_end_exclusive': '2026-07-01',
    'entity_tin': '114000002',
    'turnover': {
      'standard_rated': '3600000.000000',
      'zero_rated': '1000000.000000',
      'exempt': '500000.000000',
      'untaxed': '2000000.000000',
      'outside_vat': '0.000000',
    },
    'included_turnover': '7100000.000000',
    'liable_turnover': settings ? '3550000.000000' : null,
    'sscl_due': settings ? '88750.000000' : null,
    'settings': settings
        ? {
            'id': '80000000-0000-0000-0000-000000000001',
            'effective_from': '2026-04-01',
            'effective_to_exclusive': '2027-04-01',
            'rate_percent': '2.500000',
            'liable_portion_percent': '50.000000',
            'include_zero_rated': true,
            'include_exempt': true,
            'activity': 'Wholesale and retail',
            'status': 'approved',
            'proposed_by': '10000000-0000-0000-0000-000000000009',
            'sources': {'ird': 'https://www.ird.gov.lk'},
          }
        : null,
    'blockers': settings
        ? const []
        : [
            {'reason': 'SSCL_SETTINGS_REQUIRED'},
          ],
  };

  test(
    'the SSCL workpaper CSV shows turnover, settings and the amount due',
    () {
      final csv = LkSsclReturn.fromJson(sscl()).toCsv().split('\r\n');
      expect(csv, contains('Turnover,Sales without a tax code,2000000.00'));
      expect(csv, contains('Result,Turnover counted,7100000.00'));
      expect(csv, contains('Settings,Liable portion 50.000000%,'));
      expect(csv, contains('Result,Liable turnover,3550000.00'));
      expect(csv, contains('Result,SSCL due,88750.00'));
    },
  );

  test('without approved settings no SSCL is computed', () {
    final r = LkSsclReturn.fromJson(sscl(settings: false));
    expect(r.ssclDue, isNull);
    expect(r.blockers.single.message, contains('No approved SSCL settings'));
    expect(r.toCsv(), contains('Result,SSCL due,\r\n'));
  });
}
