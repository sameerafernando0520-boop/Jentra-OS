import 'dart:convert';

import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '40000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final eng = uid(1);
final d = 'c' * 64;

Map<String, Object?> manifest() => {
  'format': 'jentra.assurance.audit_pack.v1',
  'engagement': {'id': eng, 'evidence_cutoff_digest': 'a' * 64},
  'report': {'id': uid(2), 'report_version': 1, 'digest': 'b' * 64},
  'evidence': [
    {
      'id': uid(3),
      'sha256': d,
      'byte_size': 512,
      'source_module': 'finance',
      'source_reference': 'finance.control_reconciliation/${uid(4)}',
    },
  ],
};

Map<String, Object?> response([Map<String, Object?>? m, String? text]) {
  final man = m ?? manifest();
  final t = text ?? jsonEncode(man);
  return {
    'export_id': uid(5),
    'manifest': man,
    'manifest_text': t,
    'manifest_sha256': 'e' * 64,
    'manifest_bytes': utf8.encode(t).length,
  };
}

void main() {
  test('collection commands mirror server rules', () {
    expect(
      AssuranceEvidenceCommands.capability('export_pack'),
      'assurance.report.export',
    );
    expect(AssuranceEvidenceCommands.requiresRecentMfa('export_pack'), isTrue);
    expect(
      AssuranceEvidenceCommands.requiresRecentMfa('collect_system_evidence'),
      isFalse,
    );
    final collect = {
      'action': 'collect_system_evidence',
      'engagement_id': eng,
      'request_id': uid(6),
      'evidence_id': uid(7),
      'source_kind': 'finance.control_reconciliation',
      'source_id': uid(4),
    };
    AssuranceEvidenceCommands.validate('collect_system_evidence', collect);
    AssuranceEvidenceCommands.validate('collect_system_evidence', {
      ...collect,
      'source_kind': 'it_control.access_review',
      'source_id': null,
    });
    for (final patch in <Map<String, Object?>>[
      {'source_kind': 'finance.general_ledger'},
      {'source_id': null},
      {'source_kind': 'it_control.access_review'},
      {'sha256': d},
      {'storage_ref': 'anything'},
    ]) {
      expect(
        () => AssuranceEvidenceCommands.validate('collect_system_evidence', {
          ...collect,
          ...patch,
        }),
        throwsFormatException,
        reason: '$patch',
      );
    }
  });

  test('period snapshots take no source id', () {
    for (final kind in assuranceSnapshotKinds) {
      final p = {
        'action': 'collect_system_evidence',
        'engagement_id': eng,
        'request_id': uid(6),
        'evidence_id': uid(7),
        'source_kind': kind,
      };
      AssuranceEvidenceCommands.validate('collect_system_evidence', p);
      expect(
        () => AssuranceEvidenceCommands.validate('collect_system_evidence', {
          ...p,
          'source_id': uid(4),
        }),
        throwsFormatException,
        reason: kind,
      );
    }
  });

  test('monitoring command and rules mirror the server', () {
    expect(
      AssuranceEvidenceCommands.capability('run_monitoring'),
      'assurance.test.perform',
    );
    expect(
      AssuranceEvidenceCommands.requiresRecentMfa('run_monitoring'),
      isFalse,
    );
    final run = {
      'action': 'run_monitoring',
      'engagement_id': eng,
      'evidence_id': uid(7),
      'control_id': uid(8),
    };
    AssuranceEvidenceCommands.validate('run_monitoring', run);
    for (final patch in <Map<String, Object?>>[
      {'control_id': null},
      {'evidence_id': 'x'},
      {'severity': 'low'},
      {'rule_code': 'P2P_MATCH_OVERRIDE'},
    ]) {
      expect(
        () => AssuranceEvidenceCommands.validate('run_monitoring', {
          ...run,
          ...patch,
        }),
        throwsFormatException,
        reason: '$patch',
      );
    }
    expect(
      assuranceMonitoringRules.values.every(
        (r) =>
            assuranceSnapshotKinds.contains(r.kind) &&
            AssuranceSeverity.values.any((s) => s.name == r.severity),
      ),
      isTrue,
    );
  });

  test('source kinds carry module, query version and classification', () {
    expect(
      assuranceSourceKinds['it_control.access_review']!.classification,
      'restricted',
    );
    expect(
      assuranceSourceKinds['workforce.attendance_approvals']!.classification,
      'restricted',
    );
    expect(
      assuranceSourceKinds['procurement.three_way_match']!.queryVersion,
      'proc.supplier_bill_match.v1',
    );
    expect(
      assuranceSnapshotKinds.every(assuranceSourceKinds.containsKey),
      isTrue,
    );
    expect(
      assuranceSourceKinds.values.every(
        (k) => assuranceSourceModules.contains(k.module),
      ),
      isTrue,
    );
  });

  test('verification result must be internally consistent', () {
    final ok = EvidenceVerification.fromJson({
      'evidence_id': uid(3),
      'recorded_sha256': d,
      'current_sha256': d,
      'matches': true,
    });
    expect(ok.matches, isTrue);
    expect(
      () => EvidenceVerification.fromJson({
        'evidence_id': uid(3),
        'recorded_sha256': d,
        'current_sha256': 'f' * 64,
        'matches': true,
      }),
      throwsFormatException,
    );
  });

  test('audit pack parses and exposes exact bytes to hash', () {
    final r = response();
    final pack = AuditPackManifest.fromResponse(r);
    expect(pack.bytes, utf8.encode(r['manifest_text']! as String));
    expect(pack.evidence.single.byteSize, 512);
    expect(pack.verifies('e' * 64), isTrue);
    expect(pack.verifies('0' * 64), isFalse);
  });

  test('audit pack fails closed on tampering or unexpected content', () {
    final base = response();
    final tampered = jsonEncode({
      ...manifest(),
      'report': {'id': uid(2), 'report_version': 1, 'digest': '9' * 64},
    });
    for (final bad in <Map<String, Object?>>[
      {...base, 'manifest_text': tampered, 'manifest_bytes': tampered.length},
      {...base, 'manifest_bytes': 1},
      response({...manifest(), 'format': 'other'}),
      response({
        ...manifest(),
        'evidence': [
          {
            'id': uid(3),
            'sha256': d,
            'byte_size': 512,
            'source_module': 'finance',
            'storage_ref': 'assurance/x',
          },
        ],
      }),
      response({
        ...manifest(),
        'evidence': [
          {
            'id': uid(3),
            'sha256': 'nope',
            'byte_size': 1,
            'source_module': 'finance',
          },
        ],
      }),
    ]) {
      expect(() => AuditPackManifest.fromResponse(bad), throwsFormatException);
    }
  });
}
