// Corporate Audit & Assurance A13: the exact texts the server hashes for the
// evidence cutoff (freeze_evidence) and an issued report (issue_report), so a
// client can recompute both digests (FR-6809, FR-6818). Hashing is done by the
// caller (jentra_platform); this package has no dependencies.
import 'assurance.dart';

typedef FrozenEvidence = ({String id, String sha256, int byteSize});
typedef ReportFinding = ({
  String id,
  String title,
  String severity,
  String status,
  String ownerId,
});

/// `id:sha256:byte_size` of each accepted current evidence item, ordered by
/// id and joined with commas. The server refuses to freeze with none.
String assuranceFreezeDigestText(Iterable<FrozenEvidence> items) {
  final rows = [
    for (final i in items)
      (
        id: assuranceId(i.id),
        sha256: assuranceDigest(i.sha256),
        byteSize: i.byteSize > 0
            ? i.byteSize
            : throw const FormatException('Evidence size must be positive.'),
      ),
  ];
  if (rows.isEmpty) {
    throw const FormatException('A freeze needs accepted evidence.');
  }
  // Canonical lowercase UUID text sorts as PostgreSQL orders uuid values.
  rows.sort((a, b) => a.id.compareTo(b.id));
  return rows.map((i) => '${i.id}:${i.sha256}:${i.byteSize}').join(',');
}

/// The `jsonb::text` of the issued report's digest document.
String assuranceReportDigestText({
  required String engagementId,
  required int reportVersion,
  required String? cutoff,
  required String periodStart,
  required String periodEnd,
  required Iterable<ReportFinding> findings,
  required String summary,
}) {
  final sorted = [...findings]..sort((a, b) => a.id.compareTo(b.id));
  return assuranceJsonbText({
    'engagement_id': assuranceId(engagementId),
    'report_version': reportVersion,
    'cutoff': cutoff == null ? null : assuranceDigest(cutoff),
    'period': [assuranceDate(periodStart), assuranceDate(periodEnd)],
    'findings': [
      for (final f in sorted)
        {
          'id': assuranceId(f.id),
          'title': f.title,
          'severity': f.severity,
          'status': f.status,
          'owner_id': assuranceId(f.ownerId),
        },
    ],
    'summary': summary,
  });
}

/// PostgreSQL `jsonb` output: object keys ordered by byte length, then bytes;
/// `", "` and `": "` separators; strings escaped as `escape_json` does.
String assuranceJsonbText(Object? v) => switch (v) {
  null => 'null',
  final bool b => '$b',
  final int n => '$n',
  final String s => _string(s),
  final List<Object?> l => '[${l.map(assuranceJsonbText).join(', ')}]',
  final Map<String, Object?> m =>
    '{${(m.keys.toList()..sort(_keyOrder)).map((k) => '${_string(k)}: ${assuranceJsonbText(m[k])}').join(', ')}}',
  _ => throw const FormatException('Unsupported jsonb value.'),
};

int _keyOrder(String a, String b) {
  final x = _utf8Length(a), y = _utf8Length(b);
  if (x != y) return x - y;
  return a.compareTo(b);
}

int _utf8Length(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += r < 0x80
        ? 1
        : r < 0x800
        ? 2
        : r < 0x10000
        ? 3
        : 4;
  }
  return n;
}

String _string(String s) {
  final b = StringBuffer('"');
  for (final r in s.runes) {
    b.write(switch (r) {
      0x22 => r'\"',
      0x5c => r'\\',
      0x08 => r'\b',
      0x0c => r'\f',
      0x0a => r'\n',
      0x0d => r'\r',
      0x09 => r'\t',
      < 0x20 => '\\u${r.toRadixString(16).padLeft(4, '0')}',
      _ => String.fromCharCode(r),
    });
  }
  b.write('"');
  return b.toString();
}
