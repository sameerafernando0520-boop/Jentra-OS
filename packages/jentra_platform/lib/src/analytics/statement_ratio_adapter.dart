import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart'
    show ExactDecimal, TenantContext;
import 'process_metric_gateway.dart';
import 'process_metric_hasher.dart';

/// The server consumes frozen Wave 3 publications and, for classified formulas,
/// a separately MFA-reviewed immutable classification publication. No account
/// name, code or current catalog value is interpreted as a financial category.
final class StatementRatioAdapter {
  StatementRatioAdapter(this.rpc);
  final ProcessMetricRpc rpc;
  Future<Map<String, ExactRatio>> read(
    TenantContext context,
    String profitLossId,
    String balanceSheetId, {
    String? classificationId,
  }) async {
    final scope = ProcessMetricScope(
      tenantId: context.tenantId,
      legalEntityId: context.legalEntityId!,
      branchId: context.branchId,
    );
    final wire = await rpc('wave5_financial_ratios', {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
      'p_profit_loss_id': profitLossId,
      'p_balance_sheet_id': balanceSheetId,
      'p_classification_id': classificationId,
    });
    if (wire is! Map ||
        wire.length != 2 ||
        wire['canonicalText'] is! String ||
        wire['sourceHash'] is! String) {
      throw const FormatException('Financial publication envelope required.');
    }
    final text = wire['canonicalText'] as String;
    if (utf8.encode(text).length > 1048576 ||
        await ProcessMetricSha256Hasher().sha256(utf8.encode(text)) !=
            wire['sourceHash']) {
      throw const FormatException('Financial publication digest mismatch.');
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data.length != 12 ||
        data['contractRevision'] != 1 ||
        data['formulaVersion'] != 1 ||
        data['scope'] is! Map ||
        data['scope'].length != 3 ||
        data['scope']['tenantId'] != scope.tenantId ||
        data['scope']['legalEntityId'] != scope.legalEntityId ||
        data['scope']['branchId'] != scope.branchId ||
        data['profitLossId'] != profitLossId ||
        data['balanceSheetId'] != balanceSheetId ||
        data['classificationId'] != classificationId ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(data['currency'] as String) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['profitLossHash'] as String) ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(data['balanceSheetHash'] as String) ||
        data['ratios'] is! Map) {
      throw const FormatException('Financial publication bundle mismatch.');
    }
    final basis = StatementBasis(
      scope: scope,
      publicationId: profitLossId,
      currency: data['currency'] as String,
      periodStart: data['periodStart'] as String,
      periodEnd: parseProcessMetricUtc(
        '${data['asOf']}T00:00:00Z',
      ).add(const Duration(days: 1)).toIso8601String().substring(0, 10),
      formulaVersion: 1,
      complete: true,
    );
    final allowed = {
      'net_profit_margin',
      'liabilities_to_assets',
      'assets_to_equity',
      if (classificationId != null) ...{
        'current_ratio',
        'quick_ratio',
        'gross_profit_margin',
      },
    };
    final rows = data['ratios'] as Map;
    if (rows.length != allowed.length || !allowed.every(rows.containsKey)) {
      throw const FormatException(
        'Named financial formula population mismatch.',
      );
    }
    final result = <String, ExactRatio>{};
    for (final code in allowed) {
      final row = rows[code];
      if (row is! Map || row.length != 4) {
        throw const FormatException('Invalid exact named ratio.');
      }
      final ratio = calculateStatementRatio(
        basis,
        basis,
        _units(row['numerator']),
        _units(row['denominator']),
      );
      if (row['exactValue'] != ratio.exactValue ||
          row['unavailableReason'] != ratio.unavailableReason) {
        throw const FormatException('Named ratio arithmetic mismatch.');
      }
      result[code] = ratio;
    }
    return Map.unmodifiable(result);
  }

  BigInt _units(Object? value) {
    if (value is! String ||
        !RegExp(r'^-?(0|[1-9][0-9]{0,39})(\.[0-9]{1,6})?$').hasMatch(value)) {
      throw const FormatException('Exact publication amount required.');
    }
    return ExactDecimal.parse(value, scale: 6).scaledValue;
  }
}
