import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';

String uid(int n) => '50000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

Future<String> sha(List<int> b) async => (await Sha256().hash(
  b,
)).bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Map<String, Object?> manifest() => {
  'format': 'jentra.assurance.audit_pack.v1',
  'engagement': {'id': uid(1), 'evidence_cutoff_digest': 'a' * 64},
  'report': {'id': uid(2), 'report_version': 2, 'digest': 'b' * 64},
  'evidence': [
    {
      'id': uid(3),
      'sha256': 'c' * 64,
      'byte_size': 77,
      'source_module': 'it_control',
    },
  ],
};

Future<Map<String, Object?>> response({String? recorded}) async {
  // Postgres jsonb text uses ", " and ": "; the verifier must hash the server
  // text exactly rather than re-encode it.
  final text = jsonEncode(
    manifest(),
  ).replaceAll('","', '", "').replaceAll('":', '": ');
  return {
    'export_id': uid(4),
    'manifest': manifest(),
    'manifest_text': text,
    'manifest_sha256': recorded ?? await sha(utf8.encode(text)),
    'manifest_bytes': utf8.encode(text).length,
  };
}

void main() {
  test('verifies the exact server text and allows saving', () async {
    final r = await response();
    final v = await AssurancePackVerifier.verify(r);
    expect(v.verified, isTrue);
    expect(v.computedSha256, r['manifest_sha256']);
    expect(utf8.decode(v.bytes), r['manifest_text']);
    expect(
      await AssurancePackVerifier.verifySaved(
        v.bytes,
        r['manifest_sha256']! as String,
      ),
      isTrue,
    );
  });

  test('mismatched digest is refused and cannot be saved', () async {
    final v = await AssurancePackVerifier.verify(
      await response(recorded: 'd' * 64),
    );
    expect(v.verified, isFalse);
    expect(() => v.bytes, throwsStateError);
  });

  test('reopening detects a modified saved file', () async {
    final r = await response();
    final v = await AssurancePackVerifier.verify(r);
    final edited = [...v.bytes]..[10] ^= 1;
    expect(
      await AssurancePackVerifier.verifySaved(
        edited,
        r['manifest_sha256']! as String,
      ),
      isFalse,
    );
  });
}
