import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

void main() {
  Uint8List csv(String s) => Uint8List.fromList(utf8.encode(s));
  const header = 'date,reference,description,amount\n';
  test('CSV preserves signed amounts beyond binary precision', () {
    final p = BankStatementPreview.decode(
      csv(
        '${header}2026-09-21,A,"Fee, bank",9007199254.740993\n2026-09-21,B,Return,-0.000001',
      ),
      'csv',
    );
    expect(p.total.toDecimalString(), '9007199254.740992');
    expect(p.lines.first['description'], 'Fee, bank');
  });
  test('XLSX and CSV retain the same normalized exact values', () {
    const table = TabularDocument(
      headers: ['date', 'reference', 'description', 'amount'],
      rows: [
        ['2026-09-21', 'A', 'Bank credit', '-123.000001'],
      ],
    );
    const codec = SetupTabularCodec.bankStatement();
    expect(
      BankStatementPreview.decode(codec.encodeXlsx(table), 'xlsx').lines,
      BankStatementPreview.decode(codec.encodeCsv(table), 'csv').lines,
    );
  });
  test('2,000 rows accepted while setup retains its 500-row bound', () {
    final rows = List.generate(
      2000,
      (i) => ['2026-09-21', 'R$i', 'Line', '0.01'],
    );
    final table = TabularDocument(
      headers: ['date', 'reference', 'description', 'amount'],
      rows: rows,
    );
    const codec = SetupTabularCodec.bankStatement();
    for (final ext in ['csv', 'xlsx']) {
      final bytes = ext == 'csv'
          ? codec.encodeCsv(table)
          : codec.encodeXlsx(table);
      expect(BankStatementPreview.decode(bytes, ext).lines.length, 2000);
      expect(
        () => ext == 'csv'
            ? const SetupTabularCodec().decodeCsv(bytes)
            : const SetupTabularCodec().decodeXlsx(bytes),
        throwsA(isA<TabularFileException>()),
      );
    }
    expect(
      () => BankStatementPreview.decode(
        csv(
          header +
              List.generate(2001, (i) => '2026-09-21,R$i,line,1').join('\n'),
        ),
        'csv',
      ),
      throwsA(isA<TabularFileException>()),
    );
  });
  for (final line in [
    '2026-02-30,A,Invalid date,1',
    '2026-09-21,A,Exponent,1e2',
    '2026-09-21,A,Precision,0.0000001',
    '2026-09-21,A,Zero,0',
    '2026-09-21,,Reference,1',
  ]) {
    test(
      'reject $line',
      () => expect(
        () => BankStatementPreview.decode(csv(header + line), 'csv'),
        throwsFormatException,
      ),
    );
  }
  test(
    'duplicate trimmed references rejected',
    () => expect(
      () => BankStatementPreview.decode(
        csv('${header}2026-09-21,A,first,1\n2026-09-21, A ,second,2'),
        'csv',
      ),
      throwsFormatException,
    ),
  );
}
