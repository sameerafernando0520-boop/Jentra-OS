import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '96000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

Map<String, Object?> ticket({Map<String, Object?> change = const {}}) => {
  'evidence_id': uid(5),
  'url': 'https://project.supabase.co/storage/v1/object/sign/x?token=t',
  'expires_in': 60,
  'sha256': 'b' * 64,
  'byte_size': 21,
  ...change,
};

void main() {
  test('a download link is parsed with its recorded digest and size', () {
    final t = EvidenceDownloadTicket.fromJson(ticket(), evidenceId: uid(5));
    expect(t.url.scheme, 'https');
    expect(t.expiresIn, const Duration(seconds: 60));
    expect(t.sha256, 'b' * 64);
    expect(t.byteSize, 21);
    expect(assuranceEvidenceDownloadFunction, 'assurance-evidence-download');
  });

  test('anything but a short https link for this evidence fails closed', () {
    for (final bad in [
      {'url': 'http://project.supabase.co/x'},
      {'url': 'not a url'},
      {'evidence_id': uid(6)},
      {'expires_in': 0},
      {'expires_in': 3600},
      {'byte_size': 0},
      {'byte_size': assuranceMaxEvidenceBytes + 1},
      {'sha256': 'B' * 64},
    ]) {
      expect(
        () => EvidenceDownloadTicket.fromJson(
          ticket(change: bad),
          evidenceId: uid(5),
        ),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('a saved file name keeps the original name without paths', () {
    expect(
      assuranceEvidenceFileName('Signed bank letter.pdf', uid(5)),
      'Signed bank letter.pdf',
    );
    expect(
      assuranceEvidenceFileName(r'..\..\C:/Windows/evil?.pdf', uid(5)),
      'evil_.pdf',
    );
    expect(
      assuranceEvidenceFileName(r'C:\scans\Bank letter.pdf', uid(5)),
      'Bank letter.pdf',
    );
    expect(assuranceEvidenceFileName(' ... ', uid(5)), 'evidence-96000000.bin');
  });
}
