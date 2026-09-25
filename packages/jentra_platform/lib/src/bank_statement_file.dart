import 'dart:typed_data';
import 'package:jentra_domain/jentra_domain.dart';
import 'tabular_codec.dart';

/// Bounded preview; no amounts or spreadsheet cells pass through double.
final class BankStatementPreview {
  BankStatementPreview._(this.lines, this.total);
  final List<Map<String, String>> lines;
  final ExactDecimal total;
  static BankStatementPreview decode(Uint8List bytes, String extension) {
    const codec = SetupTabularCodec.bankStatement();
    final table = switch (extension.toLowerCase()) {
      'csv' => codec.decodeCsv(bytes),
      'xlsx' => codec.decodeXlsx(bytes),
      _ => throw const FormatException('Choose a CSV or XLSX statement.'),
    };
    const headers = {'date', 'reference', 'description', 'amount'};
    if (table.headers.toSet().difference(headers).isNotEmpty ||
        headers.difference(table.headers.toSet()).isNotEmpty ||
        table.headers.length != 4 ||
        table.rowCount == 0) {
      throw const FormatException(
        'Use date, reference, description and amount columns.',
      );
    }
    final refs = <String>{}, lines = <Map<String, String>>[];
    var total = ExactDecimal.zero(scale: 6);
    for (final raw in table.toRowMaps()) {
      final row = raw.map((k, v) => MapEntry(k, v.trim()));
      final d = row['date']!, a = row['amount']!, reference = row['reference']!;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d) ||
          DateTime.tryParse(d)?.toIso8601String().substring(0, 10) != d ||
          !RegExp(r'^-?\d{1,14}(\.\d{1,6})?$').hasMatch(a) ||
          reference.isEmpty ||
          reference.length > 140 ||
          !refs.add(reference) ||
          row['description']!.length > 500) {
        throw FormatException(
          'Invalid date, exact amount or unique reference on row ${lines.length + 2}.',
        );
      }
      final amount = ExactDecimal.parse(a, scale: 6);
      if (amount.isZero) {
        throw const FormatException('Statement amounts must be nonzero.');
      }
      total += amount;
      lines.add(Map.unmodifiable({...row, 'amount': amount.toDecimalString()}));
    }
    return BankStatementPreview._(List.unmodifiable(lines), total);
  }
}
