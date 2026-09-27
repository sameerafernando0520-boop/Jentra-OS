import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'report_export_file.dart';

abstract interface class ReportExportGateway {
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> selection,
  );
  Future<Map<String, Object?>> record(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseReportExportGateway implements ReportExportGateway {
  SupabaseReportExportGateway(this.client);
  final SupabaseClient client;
  Future<Map<String, Object?>> call(
    String rpc,
    TenantContext s,
    Map<String, Object?> p,
  ) async {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    try {
      final r = await client
          .schema('api')
          .rpc(
            rpc,
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
              ...p,
            },
          );
      if (r is! Map) {
        throw const FormatException('Invalid report export response.');
      }
      return r.cast<String, Object?>();
    } on PostgrestException catch (e) {
      final code = e.message == 'RECENT_MFA_REQUIRED'
          ? 'MFA_REQUIRED'
          : e.code == '42501'
          ? 'PERMISSION_DENIED'
          : e.code == '40001'
          ? 'VERSION_CONFLICT'
          : RegExp(r'^(22|23|54|55|P0)').hasMatch(e.code ?? '')
          ? 'VALIDATION_ERROR'
          : 'UNCERTAIN_RESULT';
      throw DomainError(
        code: code,
        message: switch (code) {
          'MFA_REQUIRED' =>
            'Complete recent MFA in account security, then retry.',
          'PERMISSION_DENIED' =>
            'Current source-report and export access is required.',
          'VALIDATION_ERROR' =>
            e.code == '54000'
                ? 'The filtered report exceeds its supported export size. No partial job was saved.'
                : 'Check the report, section and export filters.',
          'VERSION_CONFLICT' => 'The export request version changed.',
          _ =>
            'The outcome is uncertain. Retry the identical saved export request.',
        },
      );
    }
  }

  @override
  Future<Map<String, Object?>> preview(
    TenantContext s,
    Map<String, Object?> selection,
  ) async {
    final r = await call('report_export_preview', s, {
      'p_source_type': selection['source_type'],
      'p_source_id': selection['source_id'],
      'p_section': selection['section'],
      'p_filters': selection['filters'],
    });
    if (r['canonical_text'] is! String ||
        utf8.encode(r['canonical_text'] as String).length > 8 * 1024 * 1024 ||
        r['source_hash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['source_hash'] as String) ||
        await ReportExportCodec.hash(
              utf8.encode(r['canonical_text'] as String),
            ) !=
            r['source_hash']) {
      throw const FormatException(
        'Export evidence hash could not be verified.',
      );
    }
    final data = jsonDecode(r['canonical_text'] as String);
    if (data is! Map ||
        data['version'] != 1 ||
        data['metadata'] is! Map ||
        data['rows'] is! List ||
        (data['rows'] as List).length > 10000) {
      throw const FormatException('Invalid export document.');
    }
    final m = data['metadata'] as Map;
    if (m['tenant_id'] != s.tenantId ||
        m['legal_entity_id'] != s.legalEntityId ||
        m['actor_id'] != s.actorId ||
        m['working_branch_id'] != s.branchId ||
        m['source_type'] != selection['source_type'] ||
        m['source_id'] != selection['source_id'] ||
        m['section'] != selection['section'] ||
        !_same(m['filters'], selection['filters']) ||
        m['row_count'] != (data['rows'] as List).length ||
        m['as_of'] is! String ||
        m['generated_at'] is! String ||
        m['version'] is! int) {
      throw const FormatException(
        'Export evidence scope or source does not match.',
      );
    }
    return {...data.cast<String, Object?>(), 'source_hash': r['source_hash']};
  }

  static bool _same(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
    }
    return a == b;
  }

  @override
  Future<Map<String, Object?>> record(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final r = await call('record_report_export', c.context, {
      'p_command_id': c.commandId,
      'p_idempotency_key': c.idempotencyKey,
      'p_client_timestamp': c.clientTimestamp.toUtc().toIso8601String(),
      'p_payload': c.payload,
      'p_expected_entity_version': c.expectedEntityVersion,
    });
    try {
      if (r['command_id'] != c.commandId ||
          r['request_id'] is! String ||
          r['entity'] is! Map) {
        throw const FormatException('Invalid export receipt.');
      }
      final e = (r['entity'] as Map).cast<String, Object?>();
      if (e['tenant_id'] != c.context.tenantId ||
          e['legal_entity_id'] != c.context.legalEntityId ||
          e['branch_id'] != c.context.branchId ||
          e['actor_id'] != c.context.actorId ||
          e['status'] != 'registered' ||
          e['version'] != 1) {
        throw const FormatException('Export receipt scope does not match.');
      }
      for (final k in [
        'id',
        'source_type',
        'source_id',
        'section',
        'filters',
        'source_hash',
        'file_sha256',
        'file_format',
        'file_name',
        'file_size',
        'row_count',
      ]) {
        if (!_same(e[k], c.payload[k])) {
          throw const FormatException(
            'Export receipt does not match sealed request.',
          );
        }
      }
      return e;
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Export registration could not be verified. Retry the saved request.',
      );
    }
  }
}
