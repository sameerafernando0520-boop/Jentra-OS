import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

const id = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
Map<String, Object?> department() => {
  'id': id,
  'revision_id': other,
  'code': 'OPS',
  'name': 'Operations',
  'parent_id': null,
  'start_date': '2026-09-26',
  'end_date_exclusive': null,
  'reason': 'Synthetic setup',
};
Map<String, Object?> assign() => {
  'id': id,
  'employee_id': id,
  'spell_id': other,
  'department_id': other,
  'manager_id': null,
  'calendar_version_id': other,
  'role_title': 'Technician',
  'start_date': '2026-09-26',
  'end_date_exclusive': '2026-10-26',
  'reason': 'Synthetic assignment',
};
void main() {
  test(
    'AC-403 open department and finite assignment dates remain distinct',
    () {
      expect(
        OrganizationDates(
          '2026-09-26',
          null,
        ).contains(CivilDate.parse('2027-01-01')),
        isTrue,
      );
      expect(
        OrganizationDates(
          '2026-09-26',
          '2026-09-27',
          finite: true,
        ).contains(CivilDate.parse('2026-09-27')),
        isFalse,
      );
      expect(
        () => OrganizationDates('2026-09-26', null, finite: true),
        throwsFormatException,
      );
    },
  );
  test('AC-403 impossible, empty and excessive coverage rejected', () {
    for (final range in [
      ('2026-02-30', '2026-03-01'),
      ('2026-09-26', '2026-09-26'),
      ('2026-09-26', '2032-01-01'),
    ]) {
      expect(
        () => OrganizationDates(range.$1, range.$2, finite: true),
        throwsFormatException,
      );
    }
  });
  test('AC-401 unknown private and missing command fields rejected', () {
    expect(
      () => validateOrganizationPayload('department_create', {
        ...department(),
        'salary': '10',
      }),
      throwsFormatException,
    );
    expect(
      () => validateOrganizationPayload(
        'assign',
        {...assign()}..remove('calendar_version_id'),
      ),
      throwsFormatException,
    );
  });
  test('AC-403 self department and manager links rejected locally', () {
    expect(
      () => validateOrganizationPayload('department_create', {
        ...department(),
        'parent_id': id,
      }),
      throwsFormatException,
    );
    expect(
      () => validateOrganizationPayload('assign', {
        ...assign(),
        'manager_id': id,
      }),
      throwsFormatException,
    );
  });
  test('AC-401 command and response versions reject unsafe JSON integers', () {
    expect(() => organizationVersion(9007199254740992), throwsFormatException);
    expect(() => organizationVersion(1.0), throwsFormatException);
    expect(organizationVersion(9007199254740991), 9007199254740991);
  });
  test('AC-403 end uses an explicit original revision and bounded prefix', () {
    final end = {
      'id': id,
      'employee_id': other,
      'replace_revision_id': id,
      'start_date': '2026-09-26',
      'end_date_exclusive': '2026-10-01',
      'reason': 'Explicit end',
    };
    validateOrganizationPayload('end_assignment', end);
    expect(
      () => validateOrganizationPayload('end_assignment', {
        ...end,
        'role_title': 'Unrelated edit',
      }),
      throwsFormatException,
    );
  });
  test(
    'AC-401 directory response excludes private fields and normalized dates',
    () {
      final row = {...department(), 'version': 1}..remove('reason');
      expect(DepartmentEntry.fromJson(row).name, 'Operations');
      expect(
        () => DepartmentEntry.fromJson({...row, 'private_email': 'hidden'}),
        throwsFormatException,
      );
      expect(
        () => DepartmentEntry.fromJson({...row, 'start_date': '2026-09-31'}),
        throwsFormatException,
      );
    },
  );
}
