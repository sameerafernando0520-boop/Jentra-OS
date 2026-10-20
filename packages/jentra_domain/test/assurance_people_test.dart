import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '97000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

void main() {
  test('people are parsed with their user id and label', () {
    final p = AssurancePeople.fromJson({
      'members': [
        {'user_id': uid(1), 'label': 'Nadeesha Perera'},
        {'user_id': uid(2), 'label': 'Unlinked member ····0042'},
      ],
      'truncated': false,
    });
    expect(p.members.first.userId, uid(1));
    expect(p.members.last.label, 'Unlinked member ····0042');
    expect(p.truncated, isFalse);
    expect(p.labelOf(uid(2)), 'Unlinked member ····0042');
    expect(p.labelOf(uid(3)), isNull);
  });

  test('e-mail labels, bad ids and duplicates fail closed', () {
    for (final bad in [
      [
        {'user_id': uid(1), 'label': 'someone@example.com'},
      ],
      [
        {'user_id': 'not-a-uuid', 'label': 'Kasun Silva'},
      ],
      [
        {'user_id': uid(1), 'label': 'Kasun Silva'},
        {'user_id': uid(1), 'label': 'Kasun Silva'},
      ],
    ]) {
      expect(
        () => AssurancePeople.fromJson({'members': bad, 'truncated': false}),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });
}
