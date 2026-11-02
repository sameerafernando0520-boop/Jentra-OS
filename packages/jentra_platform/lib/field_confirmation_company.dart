import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'jentra_field_sales_platform.dart';
export 'src/field_confirmation_company_store.dart';

final class FieldConfirmationPage {
  const FieldConfirmationPage(
    this.items,
    this.nextCursor, {
    this.providerState,
  });
  final List<FieldSalesJson> items;
  final String? nextCursor, providerState;
}

abstract interface class FieldConfirmationCompanyGateway {
  String? get actorId;
  Future<FieldConfirmationPage> subjects(
    FieldSalesScope scope, {
    String? after,
  });
  Future<FieldConfirmationPage> contacts(
    FieldSalesScope scope,
    String customer, {
    String? after,
  });
  Future<FieldConfirmationPage> challenges(
    FieldSalesScope scope,
    String request, {
    String? after,
  });
  Future<FieldSalesJson> command(FieldSalesJson params);
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key);
}

/// Uses only company confirmation RPCs under the caller's current session. The
/// service-only dispatch helper and transport configuration are never exposed.
final class SupabaseFieldConfirmationCompanyGateway
    implements FieldConfirmationCompanyGateway {
  SupabaseFieldConfirmationCompanyGateway(SupabaseClient client)
    : _transport = SupabaseFieldSalesGateway(client);
  SupabaseFieldConfirmationCompanyGateway.withRpc(
    Future<Object?> Function(String, FieldSalesJson) rpc, {
    required String? Function() currentActor,
  }) : _transport = SupabaseFieldSalesGateway.withRpc(
         rpc,
         currentActor: currentActor,
       );
  final SupabaseFieldSalesGateway _transport;
  @override
  String? get actorId => _transport.actorId;
  Future<FieldConfirmationPage> _page(
    String name,
    FieldSalesJson params, {
    String? after,
  }) async {
    final result = await _transport.call(name, {
      ...params,
      'p_after': after,
      'p_limit': 50,
    });
    final rows = result['items'],
        next = result['next_cursor'],
        provider = result['provider_state'];
    if (rows is! List ||
        rows.length > 50 ||
        next != null && (next is! String || next == after) ||
        provider != null &&
            !const {'configured', 'unavailable'}.contains(provider)) {
      throw const FieldSalesFailure(
        'CONTRACT_INVALID',
        'The company confirmation page could not be opened.',
      );
    }
    return FieldConfirmationPage(
      rows.map(fieldSalesObject).toList(growable: false),
      next as String?,
      providerState: provider as String?,
    );
  }

  @override
  Future<FieldConfirmationPage> subjects(
    FieldSalesScope scope, {
    String? after,
  }) => _page('field_sales_confirmation_subjects', scope.params, after: after);
  @override
  Future<FieldConfirmationPage> contacts(
    FieldSalesScope scope,
    String customer, {
    String? after,
  }) => _page('field_sales_confirmation_contacts', {
    ...scope.params,
    'p_customer_id': customer,
  }, after: after);
  @override
  Future<FieldConfirmationPage> challenges(
    FieldSalesScope scope,
    String request, {
    String? after,
  }) => _page('field_sales_confirmation_challenges', {
    ...scope.params,
    'p_request_id': request,
  }, after: after);
  @override
  Future<FieldSalesJson> command(FieldSalesJson params) =>
      _transport.call('field_sales_confirmation_company_command', params);
  @override
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key) =>
      _transport.call('field_sales_confirmation_receipt', {
        ...scope.params,
        'p_idempotency_key': key,
      });
}
