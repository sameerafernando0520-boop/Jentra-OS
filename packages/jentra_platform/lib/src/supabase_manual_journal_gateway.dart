import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'finance_report_read_access.dart';
import 'supabase_financial_dimension_gateway.dart';

abstract interface class ManualJournalGateway {
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
    String? documentDate,
  });
  Future<Map<String, Object?>> detail(TenantContext scope, String id);
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseManualJournalGateway implements ManualJournalGateway {
  SupabaseManualJournalGateway(this.client);
  final SupabaseClient client;
  Future<Map<String, Object?>> call(
    String rpc,
    TenantContext scope,
    Map<String, Object?> params,
  ) async {
    final read = const {
      'manual_journal_options',
      'manual_journal_detail',
      'manual_journal_tax_options',
      'manual_journal_tax_controls',
    }.contains(rpc);
    if (read && client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message:
            'Restore your authenticated session, then verify journal access.',
      );
    }
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your current authenticated entity and branch.',
      );
    }
    try {
      final r = await client
          .schema('api')
          .rpc(
            rpc,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...params,
            },
          );
      if (read && client.auth.currentUser?.id != scope.actorId) {
        throw const DomainError(
          code: 'AUTHENTICATION_REQUIRED',
          message:
              'Restore your authenticated session, then verify journal access.',
        );
      }
      if (r is! Map) throw const FormatException('Invalid journal response.');
      return r.cast<String, Object?>();
    } on PostgrestException catch (e) {
      final denial = financeReportReadDenial(rpc, e);
      if (denial != null) throw denial;
      final code = e.code == '42501'
          ? 'PERMISSION_DENIED'
          : e.code == '40001'
          ? 'VERSION_CONFLICT'
          : RegExp(r'^(22|23|54|55|P0)').hasMatch(e.code ?? '')
          ? 'VALIDATION_ERROR'
          : 'UNCERTAIN_RESULT';
      throw DomainError(
        code: code,
        message: switch (code) {
          'PERMISSION_DENIED' =>
            'Current permission, independent approval or MFA verification failed.',
          'VERSION_CONFLICT' =>
            'This journal changed. Close the local copy and reopen the current document.',
          'VALIDATION_ERROR' =>
            e.message == 'JOURNAL_REAPPROVAL_REQUIRED'
                ? 'The approved basis changed. Recall, save and obtain fresh approval.'
                : e.message == 'SUBLEDGER_CONTROL_REQUIRES_SOURCE'
                ? 'AR/AP control accounts require a governed source document.'
                : 'Check the balanced amounts, active accounts, period, attachment scope and approval configuration.',
          _ => 'Result uncertain. Retry the saved command.',
        },
      );
    }
  }

  static BigInt decimal(Object? value, {bool signed = false}) {
    if (value is! String ||
        !RegExp(
          signed ? r'^-?\d{1,14}(\.\d{1,6})?$' : r'^\d{1,14}(\.\d{1,6})?$',
        ).hasMatch(value)) {
      throw const FormatException('Amounts must be exact decimal strings.');
    }
    return ExactDecimal.parse(value, scale: 6).scaledValue;
  }

  static void validate(Map<String, Object?> d, TenantContext scope, String id) {
    if (d['id'] != id ||
        d['tenant_id'] != scope.tenantId ||
        d['legal_entity_id'] != scope.legalEntityId ||
        d['branch_id'] != scope.branchId ||
        d['version'] is! int ||
        (d['version'] as int) < 1 ||
        ![
          'draft',
          'pending_approval',
          'approved',
          'rejected',
          'cancelled',
          'posted',
        ].contains(d['status']) ||
        d['lines'] is! List ||
        (d['lines'] as List).length < 2 ||
        (d['lines'] as List).length > 200) {
      throw const FormatException('Journal identity or state is invalid.');
    }
    var deb = BigInt.zero,
        cred = BigInt.zero,
        base = BigInt.zero,
        baseDeb = BigInt.zero;
    final ids = <String>{};
    for (final raw in d['lines'] as List) {
      if (raw is! Map ||
          raw['line_id'] is! String ||
          !ids.add(raw['line_id'] as String) ||
          raw['account_id'] is! String) {
        throw const FormatException('Journal source lines are invalid.');
      }
      FinancialDimensionEvidence.validate(raw, scope);
      final a = decimal(raw['debit']),
          b = decimal(raw['credit']),
          v = decimal(raw['base_amount'], signed: true);
      if ((a > BigInt.zero) == (b > BigInt.zero) ||
          v == BigInt.zero ||
          v.sign != (a - b).sign ||
          decimal(raw['amount'], signed: true) != a - b) {
        throw const FormatException('Journal line sides do not match.');
      }
      if (raw['tax_control_movement'] != null) {
        if (!const [
              'settlement',
              'adjustment',
              'transfer',
            ].contains(raw['tax_control_movement']) ||
            raw['tax_definition_id'] != null ||
            raw['taxable_amount'] != null ||
            raw['is_tax_control'] != true ||
            !const ['asset', 'liability'].contains(raw['tax_account_type']) ||
            raw['tax_direction'] != (a - b).sign ||
            decimal(raw['expected_tax_base']) != v.abs()) {
          throw const FormatException('Invalid governed tax-control movement.');
        }
      } else if (raw['tax_definition_id'] != null) {
        final scale = raw['tax_rounding_scale'];
        final direction = raw['tax_direction'];
        final rate = decimal(raw['tax_rate']);
        final basis = decimal(raw['taxable_amount']);
        if (raw['tax_definition_id'] is! String ||
            raw['tax_definition_version'] is! int ||
            raw['tax_definition_version'] < 1 ||
            raw['tax_code'] is! String ||
            !const [
              'input',
              'output',
              'withholding',
            ].contains(raw['tax_kind']) ||
            raw['tax_inclusive'] is! bool ||
            raw['tax_basis_date'] is! String ||
            scale is! int ||
            scale < 0 ||
            scale > 6 ||
            !const [1, -1].contains(direction) ||
            direction != (a - b).sign ||
            rate <= BigInt.zero ||
            rate > BigInt.from(100000000) ||
            basis <= BigInt.zero ||
            decimal(raw['expected_tax_base']) != v.abs()) {
          throw const FormatException(
            'Invalid immutable journal tax declaration.',
          );
        }
        final divisor = BigInt.from(10).pow(14 - scale);
        final expected = (basis * rate + divisor ~/ BigInt.two) ~/ divisor;
        if (expected * BigInt.from(10).pow(6 - scale) != (a - b).abs() ||
            (d['reversal_of_id'] == null &&
                (raw['tax_basis_date'] != d['document_date'] ||
                    direction != (raw['tax_kind'] == 'input' ? 1 : -1)))) {
          throw const FormatException(
            'Journal tax basis does not match the posted amount.',
          );
        }
      } else if (raw['taxable_amount'] != null) {
        throw const FormatException('Missing journal tax definition.');
      }
      deb += a;
      cred += b;
      base += v;
      if (v > BigInt.zero) baseDeb += v;
    }
    if (deb != cred ||
        base != BigInt.zero ||
        decimal(d['grand_total']) != deb ||
        decimal(d['base_total']) != baseDeb ||
        (d['status'] == 'posted' && d['journal_entry_id'] is! String)) {
      throw const FormatException('Journal confirmation does not balance.');
    }
  }

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
    String? documentDate,
  }) async {
    if (resource == 'taxes' && documentDate == null) {
      throw const FormatException('Select a journal posting date first.');
    }
    final r = await call(
      switch (resource) {
        'taxes' => 'manual_journal_tax_options',
        'tax_controls' => 'manual_journal_tax_controls',
        _ => 'manual_journal_options',
      },
      scope,
      {
        if (resource == 'taxes')
          'p_document_date': documentDate
        else if (resource != 'tax_controls')
          'p_resource': resource,
        'p_after': after,
        'p_search': search,
      },
    );
    if (r['items'] is! List ||
        (r['items'] as List).length > 50 ||
        (r['next_cursor'] != null && r['next_cursor'] is! String)) {
      throw const FormatException('Invalid bounded journal page.');
    }
    if (resource == 'reports') {
      for (final raw in r['items'] as List) {
        decimal((raw as Map)['grand_total']);
      }
    } else if (resource == 'tax_controls') {
      if (r['tenant_id'] != scope.tenantId ||
          r['legal_entity_id'] != scope.legalEntityId ||
          r['branch_id'] != scope.branchId) {
        throw const FormatException(
          'Tax-control choices have a different scope.',
        );
      }
      final ids = <String>{};
      for (final row in r['items'] as List) {
        if (row is! Map ||
            row['id'] is! String ||
            !ids.add(row['id']) ||
            row['code'] is! String ||
            row['name'] is! String ||
            row['is_tax_control'] != true ||
            !const ['asset', 'liability'].contains(row['account_type'])) {
          throw const FormatException('Invalid proven tax-control account.');
        }
      }
    } else if (resource == 'taxes') {
      final scale = r['rounding_scale'];
      if (r['tenant_id'] != scope.tenantId ||
          r['legal_entity_id'] != scope.legalEntityId ||
          r['branch_id'] != scope.branchId ||
          r['document_date'] != documentDate ||
          scale is! int ||
          scale < 0 ||
          scale > 6) {
        throw const FormatException(
          'Tax definition choices have a different scope or date.',
        );
      }
      final ids = <String>{};
      for (final row in r['items'] as List) {
        if (row is! Map ||
            row['id'] is! String ||
            !ids.add(row['id']) ||
            row['code'] is! String ||
            row['name'] is! String ||
            !const ['input', 'output', 'withholding'].contains(row['kind']) ||
            row['version'] is! int ||
            row['version'] < 1 ||
            row['inclusive'] is! bool ||
            row['valid_from'] is! String ||
            row['valid_from'].compareTo(documentDate) > 0 ||
            row['valid_to'] != null &&
                (row['valid_to'] is! String ||
                    row['valid_to'].compareTo(documentDate) < 0) ||
            decimal(row['rate']) <= BigInt.zero ||
            decimal(row['rate']) > BigInt.from(100000000)) {
          throw const FormatException(
            'Invalid effective journal tax definition.',
          );
        }
      }
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async {
    final r = await call('manual_journal_detail', scope, {'p_id': id});
    validate(r, scope, id);
    if (r['status'] == 'posted') {
      final ledger = r['ledger_lines'];
      if (ledger is! List || ledger.length < 2 || ledger.length > 200) {
        throw const FormatException('Missing posted source lines.');
      }
      var debit = BigInt.zero, credit = BigInt.zero;
      final sourceIds = (r['lines'] as List)
          .map((x) => (x as Map)['line_id'])
          .toSet();
      for (final raw in ledger) {
        if (raw is! Map ||
            !sourceIds.contains(raw['source_line_id']) ||
            raw['journal_entry_id'] != r['journal_entry_id']) {
          throw const FormatException('Invalid posted source identity.');
        }
        debit += decimal(raw['base_debit']);
        final source = (r['lines'] as List).cast<Map>().firstWhere(
          (x) => x['line_id'] == raw['source_line_id'],
        );
        if (raw['cost_centre_id'] != source['cost_centre_id'] ||
            raw['project_id'] != source['project_id'] ||
            !FinancialDimensionEvidence.same(
              raw['dimension_snapshot'],
              source['dimension_snapshot'],
            )) {
          throw const FormatException('Posted dimension source mismatch.');
        }
        credit += decimal(raw['base_credit']);
        decimal(raw['transaction_debit']);
        decimal(raw['transaction_credit']);
      }
      if (debit != credit || debit != decimal(r['base_total'])) {
        throw const FormatException('Posted source totals do not reconcile.');
      }
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final rpc = switch (verb) {
      'save' => 'upsert_manual_journal',
      'post' => 'post_manual_journal',
      'submit' ||
      'recall' ||
      'cancel' ||
      'approve' ||
      'reject' => 'transition_manual_journal',
      _ => throw ArgumentError.value(verb),
    };
    try {
      final r = await call(rpc, command.context, {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_client_timestamp': command.clientTimestamp.toIso8601String(),
        'p_expected_entity_version': command.expectedEntityVersion,
        'p_payload': command.payload,
      });
      if (r['command_id'] != command.commandId ||
          r['request_id'] is! String ||
          r['entity'] is! Map) {
        throw const FormatException();
      }
      final d = (r['entity'] as Map).cast<String, Object?>();
      validate(
        d,
        command.context,
        (command.payload[verb == 'save' ? 'id' : 'document_id']) as String,
      );
      if (verb == 'save') {
        final p = command.payload;
        for (final k in ['document_date', 'reason', 'description']) {
          if (p[k] is String && d[k] != (p[k] as String).trim()) {
            throw const FormatException();
          }
        }
        if (d['reversal_of_id'] != p['reversal_of_id']) {
          throw const FormatException();
        }
        if (p['reversal_of_id'] == null && p['lines'] is List) {
          final expected = p['lines'] as List, actual = d['lines'] as List;
          if (actual.length != expected.length) throw const FormatException();
          for (var i = 0; i < expected.length; i++) {
            final a = actual[i] as Map, e = expected[i] as Map;
            FinancialDimensionEvidence.validate(a, command.context);
            if (a['cost_centre_id'] != e['cost_centre_id'] ||
                a['project_id'] != e['project_id']) {
              throw const FormatException('Journal dimension changed.');
            }
            if (a['line_id'] != e['line_id'] ||
                a['account_id'] != e['account_id'] ||
                decimal(a['debit']) != decimal(e['debit']) ||
                decimal(a['credit']) != decimal(e['credit'])) {
              throw const FormatException();
            }
            if (a['tax_definition_id'] != e['tax_definition_id'] ||
                e['tax_definition_id'] != null &&
                    decimal(a['taxable_amount']) !=
                        decimal(e['taxable_amount'])) {
              throw const FormatException();
            }
            if (a['tax_control_movement'] != e['tax_control_movement']) {
              throw const FormatException();
            }
          }
        }
      }
      if (d['version'] != (command.expectedEntityVersion ?? 0) + 1 ||
          (verb == 'post' && d['status'] != 'posted')) {
        throw const FormatException();
      }
      return d;
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Journal confirmation could not be verified. Retry the saved command.',
      );
    }
  }
}
