import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart' show TenantContext;
import '../report_export_file.dart';
import 'process_metric_gateway.dart';

final class GovernedAnalyticsExport {
  GovernedAnalyticsExport(this.rpc, this.files);
  final ProcessMetricRpc rpc;
  final ReportExportFiles files;
  Future<(ReportExportArtifact, Map<String, Object?>)> reopen(
    TenantContext s,
    String id,
  ) async {
    final raw = await rpc('wave5_export_reopen', {
      'p_tenant_id': s.tenantId,
      'p_legal_entity_id': s.legalEntityId,
      'p_branch_id': s.branchId,
      'p_export_id': id,
    });
    if (raw is! Map<String, Object?> ||
        raw.length != 7 ||
        raw['id'] != id ||
        raw['canonicalText'] is! String ||
        !{'csv', 'xlsx'}.contains(raw['format']) ||
        raw['preparedAt'] is! String ||
        raw['fileName'] is! String) {
      throw const FormatException('Invalid governed export receipt.');
    }
    final text = raw['canonicalText'] as String;
    if (utf8.encode(text).length > 8388608 ||
        await ReportExportCodec.hash(utf8.encode(text)) != raw['sourceHash']) {
      throw const FormatException('Governed export basis digest mismatch.');
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data['metadata'] is! Map ||
        data['metadata']['tenant_id'] != s.tenantId ||
        data['metadata']['legal_entity_id'] != s.legalEntityId ||
        data['metadata']['working_branch_id'] != s.branchId ||
        data['metadata']['actor_id'] != s.actorId) {
      throw const FormatException('Export scope or actor changed.');
    }
    final artifact = await const ReportExportCodec().encode(
      data.cast<String, Object?>(),
      format: raw['format'] as String,
      exportId: id,
      preparedAt: raw['preparedAt'] as String,
      sourceHash: raw['sourceHash'] as String,
    );
    if (artifact.sha256 != raw['fileHash']) {
      throw const FormatException(
        'Reopened export bytes differ from registered artifact.',
      );
    }
    return (artifact, raw);
  }

  Future<bool> download(
    TenantContext s,
    String id,
    bool Function() current,
  ) async {
    final first = await reopen(s, id);
    if (!current()) return false;
    final target = await files.choose(first.$2['fileName'] as String);
    if (target == null || !current()) return false;
    // The chooser can remain open while permissions change. Reopen immediately
    // before writing; never use the earlier authorization as a delivery grant.
    final fresh = await reopen(s, id);
    if (!current()) return false;
    if (first.$1.sha256 != fresh.$1.sha256) {
      throw const FormatException('Export changed before delivery.');
    }
    await files.write(
      target,
      fresh.$1.bytes,
      fresh.$2['format'] == 'csv'
          ? 'text/csv'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    return current();
  }
}
