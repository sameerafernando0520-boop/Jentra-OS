import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class CloseReviewGateway {
  Future<Map<String, Object?>> reports(TenantContext scope, {String? after});
  Future<Map<String, Object?>> periods(TenantContext scope, {String? after});
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? componentKey,
  });
}

final class SupabaseCloseReviewGateway implements CloseReviewGateway {
  SupabaseCloseReviewGateway(this.client);
  final SupabaseClient client;
  static const sections = {
    'controls',
    'differences',
    'sources',
    'stock',
    'transit',
    'blockers',
  };
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
        throw const FormatException('Invalid close review response.');
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
            'Complete recent MFA in account security, then retry the saved request.',
          'PERMISSION_DENIED' =>
            'Entity finance, control, stock and cost access is required in every branch.',
          'VERSION_CONFLICT' =>
            'Refresh the selected period and report version.',
          'VALIDATION_ERROR' =>
            e.code == '54000'
                ? 'The review exceeds its supported size. No partial review was saved.'
                : 'Check the period, cutoff and control account basis.',
          _ => 'The outcome is uncertain. Retry the identical saved request.',
        },
      );
    }
  }

  ExactDecimal amount(Object? x) {
    if (x is! String || !RegExp(r'^-?\d{1,20}(\.\d{1,6})?$').hasMatch(x)) {
      throw const FormatException('Amounts must be exact decimal strings.');
    }
    return ExactDecimal.parse(x, scale: 6);
  }

  bool date(Object? x) =>
      x is String &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(x) &&
      DateTime.tryParse(x)?.toIso8601String().substring(0, 10) == x;
  void summary(Map r, TenantContext s) {
    if (r['tenant_id'] != s.tenantId ||
        r['legal_entity_id'] != s.legalEntityId ||
        r['branch_id'] is! String ||
        r['version'] != 1 ||
        r['scope'] != 'all_entity_branches' ||
        !['ready', 'blocked'].contains(r['status'])) {
      throw const FormatException(
        'Close review scope or state does not match.',
      );
    }
    for (final k in [
      'id',
      'entity_name',
      'currency_code',
      'period_id',
      'period_name',
      'period_state',
      'generated_at',
    ]) {
      if (r[k] is! String || (r[k] as String).isEmpty) {
        throw const FormatException('Missing close review identity.');
      }
    }
    if (!date(r['as_of']) ||
        !date(r['period_start']) ||
        (r['as_of'] as String).compareTo(r['period_start'] as String) < 0 ||
        r['period_version'] is! int ||
        r['period_version'] < 1) {
      throw const FormatException('Invalid close review cutoff.');
    }
    for (final k in [
      'control_count',
      'difference_count',
      'blocker_count',
      'branch_count',
    ]) {
      if (r[k] is! int ||
          r[k] < 0 ||
          r[k] > (k == 'branch_count' ? 500 : 50000)) {
        throw const FormatException('Invalid review count.');
      }
    }
    final ids = <String>{};
    if (r['branches'] is! List ||
        (r['branches'] as List).length != r['branch_count'] ||
        (r['branches'] as List).any(
          (b) =>
              b is! Map ||
              b['id'] is! String ||
              b['name'] is! String ||
              !ids.add(b['id'] as String),
        ) ||
        !ids.contains(r['branch_id'])) {
      throw const FormatException('Invalid frozen entity branch basis.');
    }
    if (r['status'] == 'ready' &&
        (r['blocker_count'] != 0 || r['difference_count'] != 0)) {
      throw const FormatException('A blocked review cannot claim readiness.');
    }
  }

  List<Map<String, Object?>> rows(Map r) {
    if (r['items'] is! List || (r['items'] as List).length > 50) {
      throw const FormatException('Invalid review page.');
    }
    final ids = <String>{};
    return [
      for (final x in r['items'] as List)
        if (x is Map && x['id'] is String && ids.add(x['id'] as String))
          x.cast<String, Object?>()
        else
          throw const FormatException('Invalid or duplicate row identity.'),
    ];
  }

  void equation(Map x) {
    if (amount(x['subledger_value']) - amount(x['gl_value']) !=
        amount(x['difference'])) {
      throw const FormatException('Control equation does not reconcile.');
    }
  }

  void row(Map x, String section, Map s) {
    final branches = (s['branches'] as List)
        .map((b) => (b as Map)['id'])
        .toSet();
    if (x['branch_id'] != null && !branches.contains(x['branch_id'])) {
      throw const FormatException(
        'Evidence branch is outside the frozen entity.',
      );
    }
    if (section == 'controls') {
      if (!['AR', 'AP', 'GRNI', 'INVENTORY', 'CASH'].contains(x['kind']) ||
          x['name'] is! String ||
          x['component_key'] != x['id'] ||
          x['currency_code'] is! String ||
          ![
            'reconciled',
            'difference',
            'unavailable',
            'ledger_only',
            'currency_basis_invalid',
            'ambiguous_basis',
            'statement_coverage_required',
          ].contains(x['status']) ||
          x['difference_count'] is! int ||
          x['difference_count'] < 0 ||
          x['difference_count'] > 50000) {
        throw const FormatException('Invalid control row.');
      }
      if (x['status'] == 'unavailable') {
        if (x['reason'] is! String || x['difference_count'] == 0) {
          throw const FormatException('Unavailable control has no blocker.');
        }
      } else {
        equation(x);
        if (x['accounts'] is! List ||
            (x['accounts'] as List).isEmpty ||
            (x['accounts'] as List).length > 50) {
          throw const FormatException('Control account basis is required.');
        }
        final ids = <String>{};
        for (final a in x['accounts'] as List) {
          if (a is! Map ||
              a['id'] is! String ||
              a['code'] is! String ||
              a['name'] is! String ||
              !ids.add(a['id'] as String)) {
            throw const FormatException('Invalid control account basis.');
          }
        }
        if (x['kind'] == 'CASH') {
          final adjusted =
              amount(x['statement_closing']) -
              amount(x['unmatched_bank']) +
              amount(x['unmatched_book']);
          if (x['status'] != 'ledger_only' &&
              adjusted != amount(x['subledger_value'])) {
            throw const FormatException('Invalid bank reconciliation bridge.');
          }
        }
      }
    } else if (section == 'differences') {
      amount(x['difference']);
      if (x['subledger_value'] != null) equation(x);
      if (x['component_key'] is! String) {
        throw const FormatException('Difference component is missing.');
      }
    } else if (section == 'sources') {
      for (final k in [
        'component_key',
        'origin',
        'source_type',
        'source_id',
        'posting_date',
      ]) {
        if (x[k] is! String) {
          throw const FormatException('Source attribution is missing.');
        }
      }
      if (!date(x['posting_date']) ||
          (x['posting_date'] as String).compareTo(s['as_of'] as String) > 0) {
        throw const FormatException('Source is outside the report cutoff.');
      }
      amount(x['value']);
      if (x['origin'] != 'bank' && x['command_id'] is! String) {
        throw const FormatException('Source command identity is missing.');
      }
    } else if (section == 'stock' || section == 'transit') {
      amount(x['quantity']);
      amount(x['value']);
    } else if (section == 'blockers' && x['code'] is! String) {
      throw const FormatException('Close blocker code is missing.');
    }
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final r = await call('generate_close_control_review', c.context, {
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
        throw const FormatException('Invalid review command receipt.');
      }
      final s = (r['entity'] as Map).cast<String, Object?>();
      summary(s, c.context);
      if (s['id'] != c.payload['id'] ||
          s['as_of'] != c.payload['as_of'] ||
          s['period_id'] != c.payload['period_id'] ||
          s['branch_id'] != c.context.branchId) {
        throw const FormatException(
          'Receipt does not match the sealed review request.',
        );
      }
      return s;
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation could not be verified. Retry the saved request.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> reports(TenantContext s, {String? after}) async {
    final r = await call('close_control_reviews', s, {'p_after': after});
    final items = rows(r);
    for (final x in items) {
      summary(x, s);
    }
    if (r['next_cursor'] != null &&
        (items.length != 50 || r['next_cursor'] != items.last['id'])) {
      throw const FormatException('Invalid report cursor.');
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> periods(TenantContext s, {String? after}) async {
    final r = await call('period_governance_options', s, {
      'p_resource': 'periods',
      'p_after': after,
      'p_period_id': null,
    });
    if (r['tenant_id'] != s.tenantId ||
        r['legal_entity_id'] != s.legalEntityId ||
        r['branch_id'] != s.branchId) {
      throw const FormatException('Period scope does not match.');
    }
    final items = rows(r);
    for (final x in items) {
      if (x['name'] is! String ||
          !date(x['start_date']) ||
          !date(x['end_date']) ||
          x['version'] is! int) {
        throw const FormatException('Invalid period.');
      }
    }
    if (r['next_cursor'] != null &&
        (items.length != 50 || r['next_cursor'] != items.last['id'])) {
      throw const FormatException('Invalid period cursor.');
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext s,
    String id,
    String section, {
    String? after,
    String? componentKey,
  }) async {
    if (!sections.contains(section) ||
        (after != null &&
            (!RegExp(r'^\d+$').hasMatch(after) ||
                int.tryParse(after) == null ||
                int.parse(after) > 50000))) {
      throw const FormatException('Invalid close review page request.');
    }
    final offset = after == null ? 0 : int.parse(after);
    final r = await call('close_control_review_page', s, {
      'p_id': id,
      'p_section': section,
      'p_after': offset,
      'p_component_key': componentKey,
    });
    if (r['summary'] is! Map ||
        r['section'] != section ||
        r['component_key'] != componentKey) {
      throw const FormatException('Review page filter does not match.');
    }
    final summaryData = r['summary'] as Map;
    summary(summaryData, s);
    if (summaryData['id'] != id) {
      throw const FormatException('Review identity does not match.');
    }
    final items = rows(r);
    for (final x in items) {
      row(x, section, summaryData);
      if (componentKey != null && x['component_key'] != componentKey) {
        throw const FormatException('Unexpected component evidence.');
      }
    }
    if (r['next_cursor'] != null &&
        (items.length != 50 || r['next_cursor'] != '${offset + 50}')) {
      throw const FormatException('Invalid evidence cursor.');
    }
    return r;
  }
}
