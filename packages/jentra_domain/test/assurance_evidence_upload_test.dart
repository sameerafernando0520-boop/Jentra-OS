import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '30000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final now = DateTime.utc(2026, 10, 19, 9);
final tenant = uid(90), eng = uid(1), req = uid(2), ev = uid(3);
final digest = 'b' * 64;

Map<String, Object?> payload({
  String name = 'bank-letter.pdf',
  int size = 21,
}) => manualEvidencePayload(
  tenantId: tenant,
  engagementId: eng,
  requestId: req,
  evidenceId: ev,
  fileName: name,
  sha256: digest,
  byteSize: size,
  sourceAsOf: now,
  now: now,
);

Map<String, Object?> verification([Map<String, Object?> patch = const {}]) => {
  'evidence_id': ev,
  'outcome': 'verified',
  'observed_sha256': digest,
  'observed_byte_size': 21,
  'verified_at': '2026-10-19T09:00:01Z',
  'verifier': 'assurance-evidence-verify/v1',
  ...patch,
};

void main() {
  group('manual evidence payload', () {
    test('is a manual submission on the generated path', () {
      final p = payload();
      expect(p['action'], 'submit_evidence');
      expect(p['source_module'], 'manual');
      expect(p['collection_method'], 'manual');
      expect(p['storage_ref'], 'assurance/$tenant/$eng/$ev');
      expect(p['query_version'], isNull);
      expect(p['source_reference'], 'bank-letter.pdf');
      final m = EvidenceMetadata.fromCommand(
        p,
        tenantId: tenant,
        engagementId: eng,
        now: now,
      );
      expect(m.storageRef, assuranceStorageRef(tenant, eng, ev));
    });

    test(
      'bounds the source reference and refuses empty or oversized files',
      () {
        expect(
          (payload(name: '${'a' * 240}.pdf')['source_reference']! as String)
              .length,
          200,
        );
        expect(() => payload(size: 0), throwsFormatException);
        expect(
          () => payload(size: assuranceMaxEvidenceBytes + 1),
          throwsFormatException,
        );
        expect(() => payload(name: '   '), throwsFormatException);
      },
    );

    test('accepts only the bucket file types', () {
      expect(assuranceEvidenceMime('Letter.PDF'), 'application/pdf');
      expect(assuranceEvidenceMime('ledger.xlsx'), contains('spreadsheetml'));
      expect(() => assuranceEvidenceMime('script.exe'), throwsFormatException);
      expect(() => assuranceEvidenceMime('noextension'), throwsFormatException);
    });
  });

  group('verification', () {
    test('confirms only a verified record matching the proposal', () {
      final v = StoredEvidenceVerification.fromJson(
        verification(),
        evidenceId: ev,
      );
      expect(v.verified, isTrue);
      expect(v.confirms(sha256: digest, byteSize: 21), isTrue);
      expect(v.confirms(sha256: 'c' * 64, byteSize: 21), isFalse);
      final m = StoredEvidenceVerification.fromJson(
        verification({'outcome': 'mismatch', 'observed_sha256': 'c' * 64}),
      );
      expect(m.verified, isFalse);
      expect(m.confirms(sha256: digest, byteSize: 21), isFalse);
    });

    test('rejects unknown outcomes, verifiers and other evidence', () {
      for (final patch in [
        {'outcome': 'probably'},
        {'verifier': 'client'},
        {'observed_sha256': 'NOT'},
        {'observed_byte_size': -1},
      ]) {
        expect(
          () => StoredEvidenceVerification.fromJson(verification(patch)),
          throwsFormatException,
        );
      }
      expect(
        () => StoredEvidenceVerification.fromJson(
          verification(),
          evidenceId: uid(9),
        ),
        throwsFormatException,
      );
    });

    test('status cannot claim verified bytes without a matching record', () {
      Map<String, Object?> status(bool verified, Object? record) => {
        'engagement_id': eng,
        'evidence_id': ev,
        'sha256': digest,
        'byte_size': 21,
        'upload_required': true,
        'stored': true,
        'bytes_verified': verified,
        'verification': record,
      };
      final ok = EvidenceVerificationStatus.fromJson(
        status(true, verification()),
      );
      expect(ok.acceptable, isTrue);
      final waiting = EvidenceVerificationStatus.fromJson(status(false, null));
      expect(waiting.acceptable, isFalse);
      expect(
        () => EvidenceVerificationStatus.fromJson(status(true, null)),
        throwsFormatException,
      );
      expect(
        () => EvidenceVerificationStatus.fromJson(
          status(true, verification({'outcome': 'mismatch'})),
        ),
        throwsFormatException,
      );
    });
  });

  test('only the owner of an open request may upload its evidence', () {
    AssuranceWorkItem item(String owner, String status) =>
        AssuranceWorkItem.fromJson({
          'engagement_id': eng,
          'engagement_name': 'FY27 Treasury',
          'engagement_version': 4,
          'kind': 'evidence_request',
          'item_id': req,
          'title': 'Bank confirmation',
          'owner_id': owner,
          'status': status,
          'due_date': null,
          'level': 'on_track',
        }, DateTime.utc(2026, 10, 19));
    expect(item(uid(5), 'open').canSubmitEvidence(uid(5)), isTrue);
    expect(item(uid(5), 'open').canSubmitEvidence(uid(6)), isFalse);
  });
}
