import 'package:jentra_domain/jentra_payroll.dart';
import 'package:test/test.dart';

Map<String, Object?> row(
  String code,
  String name, {
  String? nic = '199012345678',
  String? member = '1234',
}) => {
  'employee_code': code,
  'name': name,
  'nic': nic,
  'epf_member_number': member,
  'epf_base': '200000.000000',
  'etf_base': '200000.000000',
  'apit_base': '200000.000000',
  'epf_employee': '16000.000000',
  'epf_employer': '24000.000000',
  'etf_employer': '6000.000000',
  'apit': '3000.000000',
};

LkStatutoryReturn parse(String kind, List<Map<String, Object?>> rows) =>
    LkStatutoryReturn.fromJson({
      'kind': kind,
      'month': '2026-05-01',
      'employer_epf_number': 'A/12345',
      'employer_etf_number': 'B/67890',
      'employer_tin': '123456789',
      'rows': rows,
      'totals': const {},
    });

void main() {
  test('EPF return CSV has one row per member and a total row', () {
    final r = parse('epf', [
      row('E1', 'Nimal Perera'),
      row('E2', 'Kamala Silva'),
    ]);
    expect(r.totalDue.toDecimalString(), '80000.000000');
    expect(r.toCsv().split('\r\n'), [
      'Employer EPF number,Month,EPF member number,NIC,Employee name,Total earnings,'
          'Employee contribution (8%),Employer contribution (12%),Total contribution',
      'A/12345,2026-05,1234,199012345678,Nimal Perera,200000.00,16000.00,24000.00,40000.00',
      'A/12345,2026-05,1234,199012345678,Kamala Silva,200000.00,16000.00,24000.00,40000.00',
      'A/12345,2026-05,TOTAL,,,400000.00,32000.00,48000.00,80000.00',
      '',
    ]);
  });

  test('ETF and APIT returns use their own employer number and columns', () {
    final etf = parse('etf', [row('E1', 'Nimal')]).toCsv().split('\r\n');
    expect(etf[1], 'B/67890,2026-05,1234,199012345678,Nimal,200000.00,6000.00');
    expect(etf[2], 'B/67890,2026-05,TOTAL,,,200000.00,6000.00');
    final apit = parse('apit', [row('E1', 'Nimal')]).toCsv().split('\r\n');
    expect(
      apit[0],
      'Employer TIN,Month,NIC,Employee name,APIT regular profits,APIT deducted',
    );
    expect(apit[1], '123456789,2026-05,199012345678,Nimal,200000.00,3000.00');
    expect(apit[2], '123456789,2026-05,TOTAL,,200000.00,3000.00');
  });

  test('names are quoted and cannot run as spreadsheet formulas', () {
    final csv = parse('etf', [row('E1', '=HYPERLINK("x"), Perera')]).toCsv();
    expect(csv, contains('"\'=HYPERLINK(""x""), Perera"'));
  });

  test('missing identifiers are reported per return kind', () {
    final rows = [row('E1', 'A', member: null), row('E2', 'B', nic: null)];
    expect(parse('epf', rows).missingIdentifiers, ['E1', 'E2']);
    expect(parse('apit', rows).missingIdentifiers, ['E2']);
  });
}
