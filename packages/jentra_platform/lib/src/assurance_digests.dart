import 'dart:convert';

import 'package:jentra_domain/jentra_assurance.dart';

import 'assurance_evidence_files.dart';

/// The evidence cutoff digest `freeze_evidence` records, recomputed here.
Future<String> assuranceFreezeDigest(Iterable<FrozenEvidence> items) =>
    assuranceSha256(utf8.encode(assuranceFreezeDigestText(items)));

/// The digest `issue_report` records for a report version, recomputed here.
Future<String> assuranceReportDigest({
  required String engagementId,
  required int reportVersion,
  required String? cutoff,
  required String periodStart,
  required String periodEnd,
  required Iterable<ReportFinding> findings,
  required String summary,
}) => assuranceSha256(
  utf8.encode(
    assuranceReportDigestText(
      engagementId: engagementId,
      reportVersion: reportVersion,
      cutoff: cutoff,
      periodStart: periodStart,
      periodEnd: periodEnd,
      findings: findings,
      summary: summary,
    ),
  ),
);
