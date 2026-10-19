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
  List<Map<String, Object?>> findings = const [],
  String lead = '71000000-0000-0000-0000-000000000005',
}) => {
  'engagement': {
    'id': eng,
    'name': 'FY27 Treasury',
    'status': status,
    'version': 7,
    'lead_auditor_id': lead,
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
  'findings': findings,
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
    final archived = AuditorEngagementView.fromJson(
      view(
        status: 'archived',
        reports: [
          {'id': uid(30), 'report_version': 1, 'digest': digest},
        ],
      ),
    );
    expect(archived.canExport(all), isFalse);
  });

  test('system collection counts as the evidence submission', () {
    Map<String, Object?> ev(int v, String action, String to, String at) => {
      'version': v,
      'action': action,
      'aggregate_type': 'evidence_request',
      'aggregate_id': uid(10),
      'from_status': null,
      'to_status': to,
      'actor_id': me,
      'occurred_at': at,
    };
    final s = assuranceEvidenceStages([
      AssuranceEvent.fromJson(
        ev(1, 'request_evidence', 'open', '2026-10-01T00:00:00Z'),
      ),
      AssuranceEvent.fromJson(
        ev(2, 'collect_system_evidence', 'submitted', '2026-10-02T00:00:00Z'),
      ),
      AssuranceEvent.fromJson(
        ev(3, 'review_evidence', 'accepted', '2026-10-02T06:00:00Z'),
      ),
    ]);
    expect(s.waiting, [const Duration(days: 1)]);
    expect(s.review, [const Duration(hours: 6)]);
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

  const closeCaps = {
    'assurance.engagement.manage',
    'assurance.engagement.close',
    'assurance.retest.perform',
    'assurance.test.perform',
    'assurance.test.review',
  };
  Map<String, Object?> finding(String status, {String? ownerId}) => {
    'id': uid(40),
    'title': 'Single signatory releases',
    'severity': 'high',
    'status': status,
    'owner_id': ownerId ?? owner,
  };
  Map<String, Object?> testRow(String status, {String? runBy}) => {
    'id': uid(50),
    'control_id': ctl,
    'code': 'TRS-SAMPLE',
    'status': status,
    'population_size': 400,
    'sample_size': 25,
    'runs': [
      if (runBy != null) {'id': uid(51), 'performed_by': runBy},
    ],
  };

  test('new actions route to the test and engagement APIs', () {
    expect(AuditorAction.of('design_test').rpc, AssuranceRpc.test);
    expect(
      AuditorAction.of('execute_test').capability,
      'assurance.test.perform',
    );
    expect(AuditorAction.of('freeze_evidence').aggregateKey, 'engagement_id');
    expect(AuditorAction.of('issue_report').requiresRecentMfa, isTrue);
    expect(AuditorAction.of('retest').aggregateKey, 'finding_id');
    expect(AuditorAction.of('review_test').requiresRecentMfa, isFalse);
  });

  test('execute validation enforces the recorded sample size', () {
    final p = {
      'action': 'execute_test',
      'engagement_id': eng,
      'run_id': uid(52),
      'procedure_id': uid(50),
      'items_tested': 24,
      'exceptions_found': 0,
      'conclusion': 'effective',
      'workpaper_sha256': digest,
    };
    final a = AuditorAction.of('execute_test');
    expect(
      () => a.validate(
        p,
        now: DateTime.utc(2026, 10, 19),
        tenantId: uid(9),
        sampleSize: 25,
      ),
      throwsFormatException,
    );
    a.validate(
      {...p, 'items_tested': 25},
      now: DateTime.utc(2026, 10, 19),
      tenantId: uid(9),
      sampleSize: 25,
    );
  });

  test('freeze is the lead auditor\'s, once every request is settled', () {
    final open = AuditorEngagementView.fromJson(view(lead: me));
    expect(open.canFreeze(closeCaps, me), isFalse);
    final settled = view(lead: me);
    ((settled['requests']! as List)[0] as Map)['status'] = 'accepted';
    final v = AuditorEngagementView.fromJson(settled);
    expect(v.canFreeze(closeCaps, me), isTrue);
    expect(v.canFreeze(closeCaps, owner), isFalse);
  });

  test('stage moves follow the server rules', () {
    expect(
      AuditorEngagementView.fromJson(
        view(status: 'planning'),
      ).transitionTargets(closeCaps),
      [EngagementStatus.fieldwork],
    );
    expect(
      AuditorEngagementView.fromJson(view()).transitionTargets(closeCaps),
      isEmpty,
    );
    expect(
      AuditorEngagementView.fromJson(
        view(frozen: true),
      ).transitionTargets(closeCaps),
      [EngagementStatus.reporting],
    );
    expect(
      AuditorEngagementView.fromJson(
        view(status: 'issued', findings: [finding('remediating')]),
      ).transitionTargets(closeCaps),
      isEmpty,
    );
    expect(
      AuditorEngagementView.fromJson(
        view(status: 'issued', findings: [finding('closed')]),
      ).transitionTargets(closeCaps),
      [EngagementStatus.archived],
    );
    expect(
      AuditorEngagementView.fromJson(
        view(status: 'planning'),
      ).transitionTargets(all),
      isEmpty,
    );
  });

  test(
    'reports are issued by someone other than the lead, after exceptions',
    () {
      final v = AuditorEngagementView.fromJson(
        view(status: 'reporting', frozen: true, exceptionStatus: 'promoted'),
      );
      expect(v.canIssueReport(closeCaps, me), isTrue);
      expect(v.canIssueReport(closeCaps, uid(5)), isFalse);
      final pending = AuditorEngagementView.fromJson(
        view(status: 'reporting', frozen: true),
      );
      expect(pending.canIssueReport(closeCaps, me), isFalse);
      expect(
        AuditorEngagementView.fromJson(
          view(status: 'issued'),
        ).canReopenReport(closeCaps),
        isTrue,
      );
    },
  );

  test('finding decisions exclude the owner', () {
    AuditorFinding f(String s) => AuditorEngagementView.fromJson(
      view(findings: [finding(s)]),
    ).findings.single;
    final v = AuditorEngagementView.fromJson(view());
    expect(v.canDecideRisk(closeCaps, f('risk_pending'), me), isTrue);
    expect(v.canDecideRisk(closeCaps, f('risk_pending'), owner), isFalse);
    expect(v.canRetest(closeCaps, f('retest_pending'), me), isTrue);
    expect(v.canRetest(closeCaps, f('remediating'), me), isFalse);
    expect(v.canReopenFinding(closeCaps, f('closed'), me), isTrue);
    expect(v.canReopenFinding(closeCaps, f('issued'), me), isFalse);
  });

  test('tests run on frozen evidence and are reviewed by someone else', () {
    final designed = AuditorEngagementView.fromJson(
      view(frozen: true),
      tests: [testRow('designed')],
    );
    expect(designed.canDesignTest(closeCaps), isTrue);
    expect(designed.canExecuteTest(closeCaps, designed.tests.single), isTrue);
    final unfrozen = AuditorEngagementView.fromJson(
      view(),
      tests: [testRow('designed')],
    );
    expect(unfrozen.canExecuteTest(closeCaps, unfrozen.tests.single), isFalse);
    final executed = AuditorEngagementView.fromJson(
      view(frozen: true),
      tests: [testRow('executed', runBy: me)],
    );
    expect(executed.tests.single.sampleSize, 25);
    expect(
      executed.canReviewTest(closeCaps, executed.tests.single, me),
      isFalse,
    );
    expect(
      executed.canReviewTest(closeCaps, executed.tests.single, owner),
      isTrue,
    );
    expect(
      () =>
          AuditorEngagementView.fromJson(view(), tests: [testRow('approved')]),
      throwsFormatException,
    );
  });
}
