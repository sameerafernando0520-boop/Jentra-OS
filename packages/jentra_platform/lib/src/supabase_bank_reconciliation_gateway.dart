import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_control_reconciliation_gateway.dart';

abstract interface class BankReconciliationGateway {
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? bankId,
    String? after,
  });
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseBankReconciliationGateway
    implements BankReconciliationGateway {
  SupabaseBankReconciliationGateway(SupabaseClient client)
    : transport = SupabaseControlReconciliationGateway(client);
  final SupabaseControlReconciliationGateway transport;
  void scopeCheck(Map r, TenantContext s) {
    if (r['tenant_id'] != s.tenantId ||
        r['legal_entity_id'] != s.legalEntityId ||
        r['branch_id'] != s.branchId) {
      throw const FormatException('Bank response scope mismatch.');
    }
  }

  void amounts(Map row) {
    for (final key in [
      'amount',
      'base_amount',
      'opening',
      'closing',
      'total',
      'statement_total',
      'journal_total',
      'difference',
      'rate',
      'tolerance',
    ]) {
      if (row.containsKey(key)) {
        final v = row[key];
        if (v is! String ||
            !RegExp(
              key == 'rate' ? r'^\d+(\.\d{1,10})?$' : r'^-?\d+(\.\d{1,6})?$',
            ).hasMatch(v)) {
          throw const FormatException(
            'Bank financial values must be decimal strings.',
          );
        }
      }
    }
    if (row.containsKey('difference') &&
        transport.decimal(row['statement_total']) -
                transport.decimal(row['journal_total']) !=
            transport.decimal(row['difference'])) {
      throw const FormatException('Inconsistent match amounts.');
    }
    if (row.containsKey('opening') &&
        transport.decimal(row['opening']) + transport.decimal(row['total']) !=
            transport.decimal(row['closing'])) {
      throw const FormatException('Inconsistent statement balances.');
    }
  }

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? bankId,
    String? after,
  }) async {
    final r = await transport.call('bank_reconciliation_options', scope, {
      'p_resource': resource,
      'p_bank_id': bankId,
      'p_after': after,
    });
    scopeCheck(r, scope);
    if (r['resource'] != resource || r['bank_id'] != bankId) {
      throw const FormatException('Bank page context mismatch.');
    }
    transport.rows(r);
    final ids = <String>{};
    for (final row in r['items'] as List) {
      if (!ids.add(row['id'] as String)) {
        throw const FormatException('Duplicate bank page row.');
      }
      amounts(row as Map);
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  ) => transport.command('bank_reconciliation_command', command, (r) {
    scopeCheck(r, command.context);
    final p = command.payload;
    if (r['id'] != p['id'] ||
        r['version'] != 1 ||
        r['status'] !=
            switch (p['action']) {
              'import' => 'imported',
              'match' => 'matched',
              'reverse' => 'reversed',
              'rules' => 'configured',
              _ => '',
            } ||
        (p['bank_id'] != null && r['bank_id'] != p['bank_id'])) {
      throw const FormatException('Bank command receipt mismatch.');
    }
    if (p['action'] == 'reverse' && r['match_id'] != p['match_id']) {
      throw const FormatException('Reversal source mismatch.');
    }
    if (p['action'] == 'rules' &&
        (command.expectedEntityVersion == null ||
            transport.decimal(r['tolerance']) !=
                transport.decimal(p['tolerance']) ||
            r['bank_version'] != command.expectedEntityVersion! + 1)) {
      throw const FormatException('Bank rule receipt mismatch.');
    }
    amounts(r);
  });
}
