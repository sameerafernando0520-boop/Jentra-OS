import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
export 'src/field_sales_decision_store.dart';

abstract interface class FieldSalesGateway {
  String? get actorId;
  Future<FieldSalesJson> workspace();
  Future<List<FieldSalesJson>> customers(FieldSalesScope scope);
  Future<List<FieldSalesJson>> catalogue(
    FieldSalesScope scope,
    String customerId,
  );
  Future<List<FieldSalesJson>> subjects(FieldSalesScope scope);
  Future<FieldSalesJson> preview(FieldSalesScope scope, FieldSalesJson input);
  Future<FieldSalesJson> submit(FieldSalesCommand command);
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key);
}

abstract interface class FieldSalesCompanyGateway {
  String? get actorId;
  Future<List<FieldSalesJson>> subjects(FieldSalesScope scope);
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key);
  Future<FieldSalesJson> decide(FieldSalesJson params);
}

/// Named candidate facades only. Missing endpoints fail closed; no table or
/// broad commerce/CRM RPC fallback exists.
final class SupabaseFieldSalesGateway
    implements FieldSalesGateway, FieldSalesCompanyGateway {
  SupabaseFieldSalesGateway(this.client) : _rpc = null, currentActor = null;
  SupabaseFieldSalesGateway.withRpc(this._rpc, {required this.currentActor})
    : client = null;
  final SupabaseClient? client;
  final Future<Object?> Function(String, FieldSalesJson)? _rpc;
  final String? Function()? currentActor;
  @override
  Future<FieldSalesJson> decide(FieldSalesJson params) =>
      call('field_sales_company_decide', params);
  @override
  String? get actorId => currentActor?.call() ?? client?.auth.currentUser?.id;
  Future<FieldSalesJson> call(String name, FieldSalesJson params) async {
    final actor = actorId;
    if (actor == null) {
      throw const FieldSalesFailure(
        'ACCESS_REVOKED',
        'Sign in to recheck your portfolio.',
      );
    }
    try {
      final response =
          await (_rpc != null
                  ? _rpc(name, params)
                  : client!.schema('api').rpc(name, params: params))
              .timeout(const Duration(seconds: 25));
      if (actorId != actor) {
        throw const FieldSalesFailure(
          'ACCESS_REVOKED',
          'Your session changed. Sign in again.',
        );
      }
      return fieldSalesObject(response);
    } on PostgrestException catch (e) {
      if (['PGRST301', 'PGRST302', 'PGRST303', '401', '403'].contains(e.code)) {
        throw const FieldSalesFailure(
          'ACCESS_REVOKED',
          'Your session expired. Sign in to recheck your portfolio.',
        );
      }
      final unavailable = [
        'PGRST202',
        'PGRST204',
        '42883',
        '42P01',
      ].contains(e.code);
      throw FieldSalesFailure(
        unavailable
            ? 'FIELD_SALES_ROLLOUT_PENDING'
            : e.code ?? 'SERVER_REJECTED',
        unavailable
            ? 'Your company’s governed Sales service is not enabled yet.'
            : e.code == '42501'
            ? 'Your portfolio access changed. Sign in again.'
            : e.code == '40001'
            ? 'The commercial source changed. Review current prices and terms.'
            : e.code == '22023'
            ? 'Review the order fields, discount reason and company limits.'
            : e.code == '55000' && e.message == 'CREDIT_PROVIDER_UNAVAILABLE'
            ? 'Current credit data is unavailable. Ask Finance to refresh it before company approval.'
            : e.code == '55000' && e.message == 'CREDIT_HOLD'
            ? 'Current credit policy holds this request. Finance must review it.'
            : 'The company could not complete this action. Keep the original submission for checking.',
      );
    } on FieldSalesFailure {
      rethrow;
    } on Object {
      throw const FieldSalesFailure(
        'OUTCOME_UNKNOWN',
        'The response was interrupted. Check the original submission before retrying.',
      );
    }
  }

  Future<List<FieldSalesJson>> _pages(
    String name,
    FieldSalesJson params,
  ) async {
    final rows = <FieldSalesJson>[];
    String? cursor;
    final seen = <String>{};
    do {
      final page = await call(name, {
        ...params,
        'p_after': cursor,
        'p_limit': 50,
      });
      final items = page['items'];
      if (items is! List || items.length > 50) {
        throw const FieldSalesFailure(
          'CONTRACT_INVALID',
          'The company page could not be opened.',
        );
      }
      rows.addAll(items.map(fieldSalesObject));
      cursor = page['next_cursor'] as String?;
      if (cursor != null && !seen.add(cursor)) {
        throw const FieldSalesFailure(
          'CONTRACT_INVALID',
          'The company page cursor repeated.',
        );
      }
    } while (cursor != null);
    return rows;
  }

  @override
  Future<FieldSalesJson> workspace() => call('field_sales_workspace', {});
  @override
  Future<List<FieldSalesJson>> customers(FieldSalesScope s) =>
      _pages('field_sales_customers', s.params);
  @override
  Future<List<FieldSalesJson>> catalogue(FieldSalesScope s, String c) =>
      _pages('field_sales_catalogue', {...s.params, 'p_customer_id': c});
  @override
  Future<List<FieldSalesJson>> subjects(FieldSalesScope s) =>
      _pages('field_sales_subject_page', s.params);
  @override
  Future<FieldSalesJson> preview(FieldSalesScope s, FieldSalesJson input) =>
      call('field_sales_preview', {...s.params, 'p_input': input});
  @override
  Future<FieldSalesJson> submit(FieldSalesCommand c) =>
      call('field_sales_command', c.params);
  @override
  Future<FieldSalesJson> receipt(FieldSalesScope s, String key) => call(
    'field_sales_command_receipt',
    {...s.params, 'p_idempotency_key': key},
  );
}
