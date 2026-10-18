import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '71000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final me = uid(1), owner = uid(2), eng = uid(3), ctl = uid(4);
final digest = 'a' * 64;

Map<String, Object?> view({
  String status = 'fieldwork',
  bool frozen = false,
  String? collectedBy,
  String exceptionStatus = 'candidate',
  List<Map<String, Object?>> reports = const [],
}) => {
  'engagement': {
    'id': eng,
    'name': 'FY27 Treasury',
    'status': status,
    'version': 7,
    'evidence_frozen_at': frozen ? '2026-10-10T00:00:00Z' : null,
  },
  'controls': [
    {
      'id': ctl,
      'control_code': 'TRS-SIGN',
      'title': 'Dual signatories',
      'owner_id': owner,
      'risk': 'high',
    },
  ],
  'requests': <Map<String, Object?>>[
    {
      'id': uid(10),
      'control_id': ctl,
      'owner_id': owner,
      'due_date': '2026-10-25',
      'status': collectedBy == null ? 'open' : 'submitted',
      'rework_count': 0,
      'evidence': collectedBy == null
          ? null
          : {'id': uid(11), 'sha256': digest, 'collected_by': collectedBy},
    },
  ],
  'exceptions': <Map<String, Object?>>[
    {
      'id': uid(20),
      'control_id': ctl,
      'severity': 'high',
      'status': exceptionStatus,
      'source': 'continuous_monitoring',
    },
  ],
  'findings': [],
  'reports': reports,
  'events': [],
};

const all = {
  'assurance.evidence.request',
  'assurance.test.review',
  'assurance.test.perform',
  'assurance.finding.issue',
  'assurance.report.export',
};

void main() {
  test('actions route to their API and reuse the server contracts', () {
    expect(AuditorAction.of('export_pack').rpc, AssuranceRpc.evidence);
    expect(AuditorAction.of('export_pack').requiresRecentMfa, isTrue);
    expect(AuditorAction.of('issue_finding').requiresRecentMfa, isTrue);
    expect(AuditorAction.of('review_evidence').requiresRecentMfa, isFalse);
    expect(
      AuditorAction.of('request_evidence').capability,
      'assurance.evidence.request',
    );
    expect(() => AuditorAction.of('submit_evidence'), throwsFormatException);
  });

  test('a receipt confirms only the same aggregate one version later', () {
    final a = AuditorAction.of('record_exception');
    final p = {
      'action': 'record_exception',
      'engagement_id': eng,
      'exception_id': uid(20),
    };
    final r = {
      'action': 'record_exception',
      'engagement_id': eng,
      'aggregate_id': uid(20),
      'version': 8,
    };
    expect(a.confirms(r, p, 7), isTrue);
    expect(a.confirms({...r, 'version': 9}, p, 7), isFalse);
    expect(a.confirms({...r, 'aggregate_id': uid(21)}, p, 7), isFalse);
    expect(a.confirms({...r, 'action': 'dismiss_exception'}, p, 7), isFalse);
  });

  test('fieldwork offers collection, exceptions and finding decisions', () {
    final v = AuditorEngagementView.fromJson(view());
    final r = v.requests.single;
    expect(v.canRequestEvidence(all), isTrue);
    expect(v.canCollect(all, r), isTrue);
    expect(v.canReview(all, r, me), isFalse);
    expect(v.canRecordException(all), isTrue);
    expect(v.canIssueFinding(all, v.exceptions.single), isTrue);
    expect(v.canDismiss(all, v.exceptions.single), isTrue);
    expect(v.canExport(all), isFalse);
    expect(v.control(ctl)!.ownerId, owner);
  });

  test('collectors cannot review what they collected', () {
    final mine = AuditorEngagementView.fromJson(view(collectedBy: me));
    expect(mine.canReview(all, mine.requests.single, me), isFalse);
    final theirs = AuditorEngagementView.fromJson(view(collectedBy: owner));
    expect(theirs.canReview(all, theirs.requests.single, me), isTrue);
    expect(theirs.canReview(const {}, theirs.requests.single, me), isFalse);
  });

  test('freeze, promotion and missing capability withdraw actions', () {
    final frozen = AuditorEngagementView.fromJson(view(frozen: true));
    expect(frozen.canRequestEvidence(all), isFalse);
    expect(frozen.canCollect(all, frozen.requests.single), isFalse);
    final promoted = AuditorEngagementView.fromJson(
      view(exceptionStatus: 'promoted'),
    );
    expect(promoted.canIssueFinding(all, promoted.exceptions.single), isFalse);
    final v = AuditorEngagementView.fromJson(view());
    expect(v.canRecordException({'assurance.evidence.view'}), isFalse);
  });

  test('only the latest issued report is exportable', () {
    final v = AuditorEngagementView.fromJson(
      view(
        status: 'issued',
        reports: [
          {'id': uid(30), 'report_version': 1, 'digest': digest},
          {'id': uid(31), 'report_version': 2, 'digest': 'b' * 64},
        ],
      ),
    );
    expect(v.canExport(all), isTrue);
    expect(v.currentReport!.id, uid(31));
    expect(v.canExport({'assurance.evidence.view'}), isFalse);
  });

  test('malformed detail fails closed', () {
    final bad = view();
    (bad['exceptions']! as List)[0] = {
      ...(bad['exceptions']! as List)[0] as Map<String, Object?>,
      'source': 'guess',
    };
    expect(() => AuditorEngagementView.fromJson(bad), throwsFormatException);
    final badDigest = view(collectedBy: owner);
    ((badDigest['requests']! as List)[0] as Map)['evidence'] = {
      'sha256': 'nope',
      'collected_by': owner,
    };
    expect(
      () => AuditorEngagementView.fromJson(badDigest),
      throwsFormatException,
    );
  });

  test('engagement history accepts test and evidence command events', () {
    Map<String, Object?> ev(int v, String action) => {
      'version': v,
      'action': action,
      'aggregate_type': 'engagement',
      'aggregate_id': eng,
      'from_status': null,
      'to_status': null,
      'actor_id': me,
      'occurred_at': '2026-10-0${v}T00:00:00Z',
    };
    final d = EngagementDetail.fromJson({
      'engagement': {
        'id': eng,
        'name': 'FY27 Treasury',
        'status': 'issued',
        'version': 4,
        'evidence_cutoff_digest': null,
      },
      'requests': <Map<String, Object?>>[],
      'findings': [],
      'events': [
        ev(1, 'create_engagement'),
        ev(2, 'design_test'),
        ev(3, 'collect_system_evidence'),
        ev(4, 'export_pack'),
      ],
    });
    expect(d.events.map((e) => e.action), contains('export_pack'));
    expect(
      () => EngagementDetail.fromJson({
        'engagement': {
          'id': eng,
          'name': 'FY27 Treasury',
          'status': 'issued',
          'version': 1,
          'evidence_cutoff_digest': null,
        },
        'requests': <Map<String, Object?>>[],
        'findings': [],
        'events': [ev(1, 'drop_everything')],
      }),
      throwsFormatException,
    );
  });
}
