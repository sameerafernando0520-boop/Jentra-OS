import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

const employee = '00000000-0000-4000-8000-000000000001';
const revision = '00000000-0000-4000-8000-000000000002';
Map<String, Object?> contact() => {for (final f in hrContactFields) f: null};
Map<String, Object?> profile() => {
  'action': 'profile_save',
  'id': employee,
  'employee_id': employee,
  'revision_id': revision,
  'body': contact(),
  'reason': 'Synthetic reason',
};
void main() {
  test(
    'private contact allowlist excludes compensation, identity and bank fields',
    () {
      HrCommands.validate('profile_save', profile());
      for (final field in [
        'salary',
        'bank_account',
        'government_id',
        'health',
      ]) {
        expect(
          () => HrCommands.validate(
            'profile_save',
            profile()..['body'] = {...contact(), field: 'value'},
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('private text is bounded and review decisions are explicit actions', () {
    expect(
      () => HrCommands.validate(
        'profile_save',
        profile()..['reason'] = 'x' * 1001,
      ),
      throwsFormatException,
    );
    expect(
      () =>
          HrCommands.validate('approve', {'action': 'approve', 'id': employee}),
      throwsFormatException,
    );
    expect(HrCommands.capability('review_acknowledge'), 'people.self.view');
    expect(HrCommands.capability('erase_request'), 'people.hr.erase');
  });
  test('review objective bounds, dated eligibility and no automatic score', () {
    final p = {
      'action': 'review_create',
      'id': revision,
      'employee_id': employee,
      'reviewer_id': revision,
      'revision_id': revision,
      'start_date': '2026-09-01',
      'end_date_exclusive': '2026-10-01',
      'body': {
        'objectives': ['Synthetic objective'],
        'comments': null,
      },
      'reason': 'Synthetic review',
    };
    HrCommands.validate('review_create', p);
    expect(
      () =>
          HrCommands.validate('review_create', {...p, 'reviewer_id': employee}),
      throwsFormatException,
    );
    expect(
      () => HrCommands.validate('review_create', {
        ...p,
        'body': {
          'objectives': ['one'],
          'score': 50,
        },
      }),
      throwsFormatException,
    );
    expect(
      () => HrCommands.validate('review_create', {
        ...p,
        'body': {'objectives': List.filled(21, 'one'), 'comments': null},
      }),
      throwsFormatException,
    );
  });
  test(
    'operational subject cannot contain a private contact or a document path',
    () {
      final row = {
        'id': employee,
        'code': 'EMP',
        'display_name': 'Synthetic Employee',
      };
      final record = HrRecord.fromJson(HrRecordKind.subject, row);
      row['display_name'] = 'Changed';
      expect(record.text('display_name'), 'Synthetic Employee');
      expect(
        () => HrRecord.fromJson(HrRecordKind.subject, {
          ...row,
          'personal_email': 'private',
        }),
        throwsFormatException,
      );
      expect(
        () => HrRecord.fromJson(HrRecordKind.subject, {
          ...row,
          'object_path': 'path',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'document metadata has exact checksum/size and cannot accept content URLs',
    () {
      final p = {
        'action': 'document_reserve',
        'id': revision,
        'employee_id': employee,
        'classification': 'contact-support',
        'purpose': 'Synthetic support',
        'mime': 'text/plain',
        'byte_size': 3,
        'checksum': 'a' * 64,
      };
      HrCommands.validate('document_reserve', p);
      expect(
        () => HrCommands.validate('document_reserve', {
          ...p,
          'byte_size': 10485761,
        }),
        throwsFormatException,
      );
      expect(
        () => HrCommands.validate('document_reserve', {
          ...p,
          'url': 'https://example.test/private',
        }),
        throwsFormatException,
      );
      expect(
        () => HrCommands.validate('document_reserve', {
          ...p,
          'mime': 'text/html',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'contact reads reject unexpected fields and freeze nested caller aliases',
    () {
      final body = contact()..['emergency_name'] = 'Synthetic Friend';
      final row = {
        'employee_id': employee,
        'version': 1,
        'revision_id': revision,
        'body': body,
        'recorded_by': employee,
        'recorded_at': '2026-09-28T00:00:00Z',
      };
      final record = HrRecord.fromJson(HrRecordKind.profile, row);
      body['emergency_name'] = 'Changed';
      expect(record.body!['emergency_name'], 'Synthetic Friend');
      final copy = record.toJson();
      (copy['body'] as Map)['emergency_name'] = 'Another';
      expect(record.body!['emergency_name'], 'Synthetic Friend');
      expect(
        () => HrRecord.fromJson(HrRecordKind.profile, {...row, 'payroll': {}}),
        throwsFormatException,
      );
    },
  );
}
