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

  /// The rep's own visits to customers it is currently assigned.
  Future<List<FieldSalesJson>> visits(FieldSalesScope scope);

  /// Plans, checks in, completes or cancels a visit. Returns the receipt.
  Future<FieldSalesJson> visitCommand(FieldSalesVisitCommand command);

  /// `{state: committed, receipt}` or `{state: not_found}` for a visit key.
  Future<FieldSalesJson> visitReceipt(FieldSalesScope scope, String key);
}

abstract interface class FieldSalesCompanyGateway {
  String? get actorId;
  Future<List<FieldSalesJson>> subjects(FieldSalesScope scope);
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key);
  Future<FieldSalesJson> decide(FieldSalesJson params);

  /// Reps of the branch with HR-derived labels and their order requests
  /// submitted from [from] to [to], both company local dates.
  Future<FieldSalesRepList> reps(
    FieldSalesScope scope, {
    required DateTime from,
    required DateTime to,
  });

  /// The branch's visits planned for, or recorded on, [from] to [to].
  Future<List<FieldSalesJson>> companyVisits(
    FieldSalesScope scope, {
    required DateTime from,
    required DateTime to,
  });
}

/// Visit refusals that need their own wording.
const _visitMessages = {
  'VISIT_STATE_INVALID':
      'This visit has already moved on. Refresh your visits and check its state.',
  'VISIT_NOT_FOUND': 'This visit is not one of yours in this company.',
  'VISIT_FIELDS_INVALID':
      'Add a purpose, an outcome or a reason, and a next action for a follow-up date.',
  'VISIT_COMMAND_INVALID': 'This visit update could not be accepted.',
  'LOCATION_INVALID':
      'Your location could not be used. Try again or continue without it.',
};

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
      final visitMessage = _visitMessages[e.message];
      if (visitMessage != null &&
          ['22023', '55000', '42501'].contains(e.code)) {
        throw FieldSalesFailure(e.code!, visitMessage);
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
  Future<FieldSalesRepList> reps(
    FieldSalesScope s, {
    required DateTime from,
    required DateTime to,
  }) async => FieldSalesRepList.fromJson(
    await call('field_sales_reps', {
      ...s.params,
      'p_from': fieldSalesDate(from),
      'p_to': fieldSalesDate(to),
    }),
  );
  @override
  Future<List<FieldSalesJson>> visits(FieldSalesScope s) =>
      _pages('field_sales_visits', s.params);
  @override
  Future<FieldSalesJson> visitCommand(FieldSalesVisitCommand c) =>
      call('field_sales_visit_command', c.params);
  @override
  Future<FieldSalesJson> visitReceipt(FieldSalesScope s, String key) => call(
    'field_sales_visit_receipt',
    {...s.params, 'p_idempotency_key': key},
  );
  @override
  Future<List<FieldSalesJson>> companyVisits(
    FieldSalesScope s, {
    required DateTime from,
    required DateTime to,
  }) => _pages('field_sales_company_visits', {
    ...s.params,
    'p_from': fieldSalesDate(from),
    'p_to': fieldSalesDate(to),
  });
  @override
  Future<FieldSalesJson> receipt(FieldSalesScope s, String key) => call(
    'field_sales_command_receipt',
    {...s.params, 'p_idempotency_key': key},
  );
}
