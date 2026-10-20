import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '81000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final entity = uid(2), linked = uid(10), unlinked = uid(11);

Map<String, Object?> access({
  Object? members,
  bool canManage = true,
  Object? cursor,
}) => {
  'can_manage': canManage,
  'roles': [
    for (final r in AssuranceRole.values)
      {
        'code': r.code,
        'name': r.label,
        'description': r.summary,
        'requires_mfa': r.requiresMfa,
        'permissions': <String>[],
      },
  ],
  'members':
      members ??
      [
        {
          'membership_id': linked,
          'label': 'Nadeesha Perera',
          'linked': true,
          'version': 2,
          'assignments': [
            {
              'role_code': 'assurance_auditor',
              'scope': 'entity',
              'legal_entity_id': entity,
              'branch_id': null,
            },
          ],
        },
        {
          'membership_id': unlinked,
          'label': 'Unlinked member ····0011',
          'linked': false,
          'version': 0,
          'assignments': <Object?>[],
        },
      ],
  'next_cursor': cursor,
};

void main() {
  test('the five roles match the role table', () {
    expect(AssuranceRole.values.map((r) => r.code), [
      'assurance_lead',
      'assurance_auditor',
      'assurance_reviewer',
      'assurance_process_owner',
      'assurance_external',
    ]);
    expect(
      {for (final r in AssuranceRole.values) r.code: r.requiresMfa},
      {
        'assurance_lead': true,
        'assurance_auditor': true,
        'assurance_reviewer': true,
        'assurance_process_owner': false,
        'assurance_external': false,
      },
    );
    for (final r in AssuranceRole.values) {
      expect(r.summary.trim(), isNotEmpty);
      expect(AssuranceRole.parse(r.code), r);
    }
    expect(() => AssuranceRole.parse('tenant_owner'), throwsFormatException);
  });

  test('members, labels and assignments are parsed', () {
    final a = AssuranceAccess.fromJson(access(cursor: unlinked));
    expect(a.canManage, isTrue);
    expect(a.nextCursor, unlinked);
    expect(a.members.map((m) => m.label), [
      'Nadeesha Perera',
      'Unlinked member ····0011',
    ]);
    final m = a.members.first;
    expect(m.linked, isTrue);
    expect(m.version, 2);
    expect(m.assignments.single.role, AssuranceRole.auditor);
    expect(m.assignments.single.scope, AccessScope.entity);
    expect(m.assignments.single.legalEntityId, entity);
    expect(m.assignments.single.branchId, isNull);
    expect(a.holds(m, AssuranceRole.auditor, AccessScope.entity), isTrue);
    expect(a.holds(m, AssuranceRole.auditor, AccessScope.tenant), isFalse);
    expect(a.members.last.assignments, isEmpty);
  });

  test('untrusted read models fail closed', () {
    Map<String, Object?> member(Map<String, Object?> change) => {
      'membership_id': linked,
      'label': 'Someone',
      'linked': false,
      'version': 0,
      'assignments': <Object?>[],
      ...change,
    };
    for (final bad in [
      access(members: 'not a list'),
      access(
        members: [
          member({'label': 'someone@example.com'}),
        ],
      ),
      access(
        members: [
          member({'version': -1}),
        ],
      ),
      access(
        members: [
          member({'membership_id': 'x'}),
        ],
      ),
      access(
        members: [
          member({
            'assignments': [
              {'role_code': 'tenant_owner', 'scope': 'tenant'},
            ],
          }),
        ],
      ),
      access(
        members: [
          member({
            'assignments': [
              {'role_code': 'assurance_lead', 'scope': 'region'},
            ],
          }),
        ],
      ),
    ]) {
      expect(() => AssuranceAccess.fromJson(bad), throwsFormatException);
    }
  });

  test('commands carry exactly the access fields', () {
    final ok = {
      'membership_id': linked,
      'role_code': 'assurance_lead',
      'granted': true,
      'scope': 'tenant',
    };
    expect(AssuranceAccessCommands.fields, [
      'membership_id',
      'role_code',
      'granted',
      'scope',
    ]);
    AssuranceAccessCommands.validate(ok);
    for (final bad in [
      {...ok, 'extra': 1},
      {...ok, 'granted': 'yes'},
      {...ok, 'scope': 'region'},
      {...ok, 'role_code': 'tenant_owner'},
      {...ok}..remove('scope'),
    ]) {
      expect(
        () => AssuranceAccessCommands.validate(bad),
        throwsFormatException,
      );
    }
  });

  test('a receipt confirms only the same change one version later', () {
    final p = {
      'membership_id': linked,
      'role_code': 'assurance_lead',
      'granted': false,
      'scope': 'branch',
    };
    final r = {...p, 'version': 4};
    expect(assuranceAccessReceiptConfirms(r, p, 3), isTrue);
    expect(assuranceAccessReceiptConfirms(r, p, 4), isFalse);
    expect(
      assuranceAccessReceiptConfirms({...r, 'granted': true}, p, 3),
      isFalse,
    );
    expect(
      assuranceAccessReceiptConfirms({...r, 'membership_id': unlinked}, p, 3),
      isFalse,
    );
  });
}
