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
    if (!scope.hasOperationalScope ||
        transport.client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your current authenticated finance scope.',
      );
    }
    try {
      final raw = await transport.client
          .schema('api')
          .rpc(
            'bank_reconciliation_options',
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              'p_resource': resource,
              'p_bank_id': bankId,
              'p_after': after,
            },
          );
      if (raw is! Map) throw const FormatException('Invalid bank evidence.');
      final r = raw.cast<String, Object?>();
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
    } on PostgrestException catch (e) {
      const denied = {
        'PERMISSION_DENIED',
        'ACCESS_DENIED',
        'MFA_REQUIRED',
        'AUTHENTICATION_REQUIRED',
      };
      final code = denied.contains(e.message)
          ? e.message
          : e.message == 'RECENT_MFA_REQUIRED'
          ? 'MFA_REQUIRED'
          : e.code == '42501'
          ? 'PERMISSION_DENIED'
          : const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(e.code)
          ? 'AUTHENTICATION_REQUIRED'
          : RegExp(r'^(22|23|54|55|P0)').hasMatch(e.code ?? '')
          ? 'READ_REJECTED'
          : 'READ_UNAVAILABLE';
      throw DomainError(
        code: code,
        message: denied.contains(code)
            ? 'Bank evidence is unavailable with your current access. Recheck your role and scope.'
            : 'Bank evidence could not be loaded. Retry after checking the connection and scope.',
      );
    } on FormatException {
      throw const DomainError(
        code: 'READ_INVALID',
        message:
            'Bank evidence could not be verified. Reload the current scope.',
      );
    } catch (_) {
      throw const DomainError(
        code: 'READ_UNAVAILABLE',
        message:
            'Bank evidence could not be loaded. Retry after checking the connection and scope.',
      );
    }
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
