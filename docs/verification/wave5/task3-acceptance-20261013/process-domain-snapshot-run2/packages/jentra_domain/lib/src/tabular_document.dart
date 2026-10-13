import 'dart:collection';

/// String-only table used by CSV/XLSX import and export boundaries.
/// Exact decimals remain strings from database to spreadsheet and back.
final class TabularDocument {
  const TabularDocument({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;

  int get columnCount => headers.length;
  int get rowCount => rows.length;

  List<Map<String, String>> toRowMaps() => [
    for (final row in rows)
      <String, String>{
        for (var index = 0; index < headers.length; index += 1)
          headers[index]: index < row.length ? row[index] : '',
      },
  ];

  TabularDocument immutableCopy() => TabularDocument(
    headers: UnmodifiableListView(List<String>.from(headers)),
    rows: UnmodifiableListView([
      for (final row in rows) UnmodifiableListView(List<String>.from(row)),
    ]),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TabularDocument || !_sameList(headers, other.headers)) {
      return false;
    }
    if (rows.length != other.rows.length) return false;
    for (var index = 0; index < rows.length; index += 1) {
      if (!_sameList(rows[index], other.rows[index])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(headers),
    Object.hashAll(rows.map(Object.hashAll)),
  );

  static bool _sameList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
