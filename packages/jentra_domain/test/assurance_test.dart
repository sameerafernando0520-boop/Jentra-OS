import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '20000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final now = DateTime.utc(2026, 10, 18, 9);
final digest = 'a' * 64;
final tenant = uid(90);
final eng = uid(1);

Map<String, Object?> evidence([Map<String, Object?> patch = const {}]) => {
  'action': 'submit_evidence',
  'engagement_id': eng,
  'request_id': uid(2),
  'evidence_id': uid(3),
  'source_module': 'procurement',
  'source_reference': 'three_way_match.v1',
  'source_as_of': '2026-10-17T23:59:59Z',
  'collection_method': 'system',
  'query_version': 'p2p.3wm.1',
  'sha256': digest,
  'byte_size': 2048,
  'storage_ref': 'assurance/$tenant/$eng/${uid(3)}',
  'classification': 'confidential',
  ...patch,
};

void validate(String a, Map<String, Object?> p) =>
    AssuranceCommands.validate(a, p, now: now, tenantId: tenant);

void main() {
  group('lifecycle', () {
    test('engagement transitions are explicit; no skipping to issued', () {
      expect(
        canTransitionEngagement(
          EngagementStatus.planning,
          EngagementStatus.fieldwork,
        ),
        isTrue,
      );
      expect(
        canTransitionEngagement(
          EngagementStatus.planning,
          EngagementStatus.issued,
        ),
        isFalse,
      );
      expect(
        canTransitionEngagement(
          EngagementStatus.issued,
          EngagementStatus.reporting,
        ),
        isTrue,
        reason: 'reopen_report',
      );
      for (final s in [EngagementStatus.archived, EngagementStatus.cancelled]) {
        expect(engagementTransitions[s], isEmpty);
        expect(s.closed, isTrue);
      }
      expect(() => EngagementStatus.parse('done'), throwsFormatException);
    });

    test('finding lifecycle requires retest to close and allows reopening', () {
      expect(
        canTransitionFinding(FindingStatus.remediating, FindingStatus.closed),
        isFalse,
      );
      expect(
        canTransitionFinding(FindingStatus.retestPending, FindingStatus.closed),
        isTrue,
      );
      expect(
        canTransitionFinding(FindingStatus.closed, FindingStatus.remediating),
        isTrue,
      );
      expect(
        canTransitionFinding(FindingStatus.issued, FindingStatus.riskAccepted),
        isFalse,
        reason: 'risk acceptance needs an independent decision',
      );
      expect(FindingStatus.parse('risk_pending'), FindingStatus.riskPending);
      expect(() => FindingStatus.parse('riskPending'), throwsFormatException);
    });

    test('every transition map covers every state', () {
      expect(
        engagementTransitions.keys.toSet(),
        EngagementStatus.values.toSet(),
      );
      expect(findingTransitions.keys.toSet(), FindingStatus.values.toSet());
    });
  });

  group('commands', () {
    test('capabilities and MFA mirror the server contract', () {
      expect(AssuranceCommands.actions.length, 22);
      expect(
        AssuranceCommands.capability('retest'),
        'assurance.retest.perform',
      );
      expect(AssuranceCommands.requiresRecentMfa('issue_report'), isTrue);
      expect(AssuranceCommands.requiresRecentMfa('submit_evidence'), isFalse);
      expect(
        () => AssuranceCommands.capability('delete_finding'),
        throwsFormatException,
      );
    });

    test('unexpected fields such as injected status are rejected', () {
      expect(
        () => validate('transition', {
          'action': 'transition',
          'engagement_id': eng,
          'to_status': 'fieldwork',
          'reason': 'Planning approved',
          'status': 'issued',
        }),
        throwsFormatException,
      );
    });

    test('reports cannot be issued through a transition', () {
      expect(
        () => validate('transition', {
          'action': 'transition',
          'engagement_id': eng,
          'to_status': 'issued',
          'reason': 'Skip ahead',
        }),
        throwsFormatException,
      );
    });

    test('engagement period and impossible dates', () {
      Map<String, Object?> c(String start, String end) => {
        'action': 'create_engagement',
        'engagement_id': eng,
        'name': 'FY26 Procure-to-pay',
        'period_start': start,
        'period_end': end,
        'scope_summary': 'P2P controls',
        'lead_auditor_id': uid(5),
      };
      validate('create_engagement', c('2026-04-01', '2027-03-31'));
      expect(
        () => validate('create_engagement', c('2026-04-01', '2026-03-31')),
        throwsFormatException,
      );
      expect(
        () => validate('create_engagement', c('2026-02-30', '2027-03-31')),
        throwsFormatException,
      );
    });

    test('external access must be time-bound within 90 days', () {
      Map<String, Object?> t(String role, [String? exp]) => {
        'action': 'add_team_member',
        'engagement_id': eng,
        'user_id': uid(6),
        'role': role,
        'expires_at': ?exp,
      };
      validate('add_team_member', t('auditor'));
      validate(
        'add_team_member',
        t('external', now.add(const Duration(days: 30)).toIso8601String()),
      );
      for (final bad in [
        t('external'),
        t('external', now.add(const Duration(days: 91)).toIso8601String()),
        t(
          'external',
          now.subtract(const Duration(minutes: 1)).toIso8601String(),
        ),
        t('auditor', now.add(const Duration(days: 1)).toIso8601String()),
        t('lead'),
      ]) {
        expect(() => validate('add_team_member', bad), throwsFormatException);
      }
    });

    test('risk acceptance must be an explicit boolean', () {
      final p = {
        'action': 'respond',
        'engagement_id': eng,
        'finding_id': uid(7),
        'response': 'Block payment without GRN',
        'due_date': '2026-11-18',
        'accept_risk': false,
      };
      validate('respond', p);
      expect(
        () => validate('respond', {...p, 'accept_risk': 'false'}),
        throwsFormatException,
      );
      expect(
        () => validate('respond', {...p, 'due_date': '2026-10-17'}),
        throwsFormatException,
      );
    });
  });

  group('evidence provenance', () {
    test('valid system evidence carries metadata and digest only', () {
      validate('submit_evidence', evidence());
      final m = EvidenceMetadata.fromCommand(
        evidence(),
        tenantId: tenant,
        engagementId: eng,
        now: now,
      );
      expect(m.sha256, digest);
      expect(m.byteSize, 2048);
      expect(m.storageRef, 'assurance/$tenant/$eng/${uid(3)}');
    });

    test('rejects client paths, bad digests, sizes and future cutoffs', () {
      for (final patch in <Map<String, Object?>>[
        {'storage_ref': 'public/anything'},
        {'storage_ref': 'assurance/${uid(91)}/$eng/${uid(3)}'},
        {'sha256': 'A' * 64},
        {'sha256': 'abc'},
        {'byte_size': 0},
        {'byte_size': assuranceMaxEvidenceBytes + 1},
        {'byte_size': 2048.0},
        {'source_as_of': '2026-10-19T00:00:00Z'},
        {'collection_method': 'manual'},
        {'source_module': 'hr_private'},
        {'classification': 'public'},
        {'query_version': 'Has Spaces'},
        {'document_bytes': 'SGVsbG8='},
      ]) {
        expect(
          () => validate('submit_evidence', evidence(patch)),
          throwsFormatException,
          reason: '$patch',
        );
      }
    });

    test('manual evidence requires manual source', () {
      validate(
        'submit_evidence',
        evidence({'source_module': 'manual', 'collection_method': 'manual'}),
      );
    });
  });

  group('independence', () {
    test('segregation of duties', () {
      expect(
        AssuranceIndependence.canReviewEvidence(actor: 'a', submitter: 'a'),
        isFalse,
      );
      expect(
        AssuranceIndependence.canIssueFinding(
          actor: 'a',
          exceptionRecorder: 'b',
        ),
        isTrue,
      );
      expect(
        AssuranceIndependence.canRetest(
          actor: 'o',
          findingOwner: 'x',
          remediationSubmitter: 'y',
          controlOwner: 'o',
        ),
        isFalse,
        reason: 'control owner cannot retest',
      );
      expect(
        AssuranceIndependence.canRetest(
          actor: 'r',
          findingOwner: 'x',
          remediationSubmitter: null,
          controlOwner: 'o',
        ),
        isTrue,
      );
      expect(
        AssuranceIndependence.canDecideRisk(
          actor: 'i',
          findingOwner: 'x',
          issuer: 'i',
        ),
        isFalse,
      );
      expect(
        AssuranceIndependence.canIssueReport(actor: 'l', leadAuditor: 'l'),
        isFalse,
      );
      expect(
        AssuranceIndependence.canReleaseHold(actor: 'p', placedBy: 'p'),
        isFalse,
      );
      expect(
        AssuranceIndependence.canJoinTeam(
          user: 'o',
          controlOwners: {'o'},
          evidenceOwners: {},
        ),
        isFalse,
      );
    });
  });

  group('sampling', () {
    test('risk-based sizes cap at population', () {
      expect(assuranceSampleSize(1000, AssuranceSeverity.low), 10);
      expect(assuranceSampleSize(1000, AssuranceSeverity.critical), 60);
      expect(assuranceSampleSize(12, AssuranceSeverity.high), 12);
      expect(assuranceSampleSize(0, AssuranceSeverity.medium), 0);
      expect(
        () => assuranceSampleSize(-1, AssuranceSeverity.low),
        throwsFormatException,
      );
    });

    test('systematic sample is deterministic, unique and in range', () {
      final s = assuranceSystematicSample(100, 25, 7);
      expect(s, assuranceSystematicSample(100, 25, 7));
      expect(s.toSet().length, 25);
      expect(s.every((i) => i >= 1 && i <= 100), isTrue);
      expect(s.first, 7);
      expect(assuranceSystematicSample(5, 5, 3).toSet(), {1, 2, 3, 4, 5});
      expect(() => assuranceSystematicSample(5, 6, 1), throwsFormatException);
      expect(() => assuranceSystematicSample(5, 2, 0), throwsFormatException);
    });
  });

  group('typed response and metrics', () {
    Map<String, Object?> ev(
      int v,
      String action,
      String type,
      String agg,
      String to,
      String at,
    ) => {
      'version': v,
      'action': action,
      'aggregate_type': type,
      'aggregate_id': agg,
      'from_status': null,
      'to_status': to,
      'actor_id': uid(50),
      'occurred_at': at,
    };

    Map<String, Object?> detail({List<Map<String, Object?>>? events}) => {
      'engagement': {
        'id': eng,
        'name': 'FY26 Procure-to-pay',
        'status': 'fieldwork',
        'version': 4,
        'evidence_cutoff_digest': null,
      },
      'requests': [
        {
          'status': 'accepted',
          'rework_count': 1,
          'evidence': {'sha256': digest},
        },
        {'status': 'accepted', 'rework_count': 0, 'evidence': null},
      ],
      'findings': [
        {'id': uid(7), 'severity': 'high', 'status': 'remediating'},
        {'id': uid(8), 'severity': 'critical', 'status': 'closed'},
      ],
      'events':
          events ??
          [
            ev(
              1,
              'create_engagement',
              'engagement',
              eng,
              'planning',
              '2026-10-01T00:00:00Z',
            ),
            ev(
              2,
              'request_evidence',
              'evidence_request',
              uid(2),
              'open',
              '2026-10-02T00:00:00Z',
            ),
            ev(
              3,
              'submit_evidence',
              'evidence_request',
              uid(2),
              'submitted',
              '2026-10-05T00:00:00Z',
            ),
            ev(
              4,
              'review_evidence',
              'evidence_request',
              uid(2),
              'accepted',
              '2026-10-06T12:00:00Z',
            ),
          ],
    };

    test('parses and derives first-time-right and open high-risk counts', () {
      final d = EngagementDetail.fromJson(detail());
      expect(d.status, EngagementStatus.fieldwork);
      expect(d.openHighRiskFindings, 1);
      expect(d.evidenceFirstTimeRight, 0.5);
    });

    test('fails closed on gaps, unknown states or bad digests', () {
      expect(
        () => EngagementDetail.fromJson(
          detail(
            events: [
              ev(
                1,
                'create_engagement',
                'engagement',
                eng,
                'planning',
                '2026-10-01T00:00:00Z',
              ),
              ev(
                3,
                'submit_evidence',
                'evidence_request',
                uid(2),
                'submitted',
                '2026-10-05T00:00:00Z',
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
      final badStatus = detail();
      (badStatus['findings']! as List)[0] = {
        'id': uid(7),
        'severity': 'high',
        'status': 'resolved',
      };
      expect(() => EngagementDetail.fromJson(badStatus), throwsFormatException);
      final badDigest = detail();
      (badDigest['requests']! as List)[0] = {
        'status': 'accepted',
        'rework_count': 0,
        'evidence': {'sha256': 'not-a-digest'},
      };
      expect(() => EngagementDetail.fromJson(badDigest), throwsFormatException);
    });

    test('stage durations come from immutable events', () {
      final d = EngagementDetail.fromJson(detail());
      final s = assuranceEvidenceStages(d.events);
      expect(s.waiting, [const Duration(days: 3)]);
      expect(s.review, [const Duration(hours: 36)]);
    });

    test('nearest-rank percentiles; unmeasured stays null', () {
      final xs = [for (var i = 1; i <= 10; i++) Duration(hours: i)];
      expect(assurancePercentile(xs, 50), const Duration(hours: 5));
      expect(assurancePercentile(xs, 90), const Duration(hours: 9));
      expect(assurancePercentile(const [], 50), isNull);
      expect(() => assurancePercentile(xs, 0), throwsFormatException);
    });
  });
}
