import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

void main() {
  test(
    'AC-402 civil dates reject rollover and preserve leap-day boundaries',
    () {
      expect(() => CivilDate.parse('2025-02-29'), throwsFormatException);
      expect(() => CivilDate.parse('2026-2-01'), throwsFormatException);
      expect(CivilDate.parse('2024-02-29').next.toString(), '2024-03-01');
      expect(CivilDate.parse('2026-12-31').next.toString(), '2027-01-01');
    },
  );
  test('AC-403 adjacent employment ranges do not overlap', () {
    final first = EmploymentInterval('2024-02-01', '2024-03-01');
    final second = EmploymentInterval('2024-03-01', null);
    expect(first.overlaps(second), isFalse);
    expect(first.contains(CivilDate.parse('2024-02-29')), isTrue);
    expect(first.contains(CivilDate.parse('2024-03-01')), isFalse);
    expect(
      () => EmploymentInterval('2024-03-01', '2024-03-01'),
      throwsFormatException,
    );
    expect(second.overlaps(EmploymentInterval('2025-01-01', null)), isTrue);
  });
  test(
    'AC-402 input rejects unknown, private and malformed employee fields',
    () {
      final payload = <String, Object?>{
        'id': 'employee',
        'code': 'EMP-01',
        'display_name': 'Synthetic employee',
        'work_email': '',
        'start_date': '2026-09-01',
        'job_title': 'Engineer',
        'employment_type': 'permanent',
      };
      expect(() => validateEmployeePayload('create', payload), returnsNormally);
      expect(
        () =>
            validateEmployeePayload('create', {...payload, 'salary': '50000'}),
        throwsFormatException,
      );
      expect(
        () =>
            validateEmployeePayload('create', {...payload, 'code': 'bad code'}),
        throwsFormatException,
      );
      expect(
        () => validateEmployeePayload('create', {
          ...payload,
          'start_date': '2026-02-30',
        }),
        throwsFormatException,
      );
    },
  );
  test('AC-401 response validation binds exact scope and versions', () {
    final data = <String, Object?>{
      'id': 'employee',
      'tenant_id': 't',
      'legal_entity_id': 'e',
      'branch_id': 'b',
      'code': 'EMP-01',
      'display_name': 'Synthetic',
      'work_email': null,
      'version': 9007199254740991,
      'assignments': <Object?>[],
    };
    expect(EmployeeRecord.fromJson(data).version, 9007199254740991);
    expect(
      () => EmployeeRecord.fromJson({...data, 'version': 1.0}),
      throwsFormatException,
    );
    expect(
      () => EmployeeRecord.fromJson({...data, 'version': 9007199254740992}),
      throwsFormatException,
    );
    expect(
      () => EmployeeRecord.fromJson({...data, 'salary': '10'}),
      throwsFormatException,
    );
    expect(
      () => EmployeeRecord.fromJson({
        ...data,
        'assignments': [
          {
            'id': 'a',
            'spell_id': 's',
            'branch_id': 'b',
            'start_date': '2026-09-20',
            'end_date_exclusive': null,
            'job_title': 'Engineer',
            'employment_type': 'permanent',
            'salary': '10',
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
