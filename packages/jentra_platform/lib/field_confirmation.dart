import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
export 'src/field_confirmation_link.dart';
export 'src/field_confirmation_link_capture.dart';

abstract interface class FieldConfirmationGateway {
  Future<FieldSalesJson> requestCode(String token);
  Future<FieldSalesJson> verify(String token, String code);
  Future<FieldSalesJson> respond(
    String token,
    String proof,
    String response,
    String reason,
    bool authorized,
  );
}

abstract interface class FieldDeliveryGateway {
  Future<FieldSalesJson> requestCode(String token);
  Future<FieldSalesJson> verify(String token, String code);
  Future<FieldSalesJson> respond(
    String token,
    String proof,
    List<FieldSalesJson> quantities,
    String reason,
    bool authorized,
  );
}

/// Separate purpose and RPC names; uses the same anonymous session fencing.
final class SupabaseFieldDeliveryGateway implements FieldDeliveryGateway {
  SupabaseFieldDeliveryGateway(SupabaseClient client)
    : _transport = SupabaseFieldConfirmationGateway(client);
  SupabaseFieldDeliveryGateway.withRpc(
    Future<Object?> Function(String, FieldSalesJson) rpc, {
    String? Function()? currentActor,
  }) : _transport = SupabaseFieldConfirmationGateway.withRpc(
         rpc,
         currentActor: currentActor,
       );
  final SupabaseFieldConfirmationGateway _transport;
  @override
  Future<FieldSalesJson> requestCode(String token) =>
      _transport._call('field_sales_delivery_request_code', {'p_token': token});
  @override
  Future<FieldSalesJson> verify(String token, String code) => _transport._call(
    'field_sales_delivery_verify',
    {'p_token': token, 'p_code': code},
  );
  @override
  Future<FieldSalesJson> respond(
    String token,
    String proof,
    List<FieldSalesJson> quantities,
    String reason,
    bool authorized,
  ) => _transport._call('field_sales_delivery_respond', {
    'p_token': token,
    'p_proof': proof,
    'p_quantities': quantities,
    'p_reason': reason,
    'p_authorized': authorized,
  });
}

/// A dedicated anonymous client. No signed-in Sales/Employee session or broad
/// commerce API is accepted. No token, code, proof or offer enters diagnostics.
final class SupabaseFieldConfirmationGateway
    implements FieldConfirmationGateway {
  SupabaseFieldConfirmationGateway(this.client)
    : _rpc = null,
      currentActor = null;
  SupabaseFieldConfirmationGateway.withRpc(this._rpc, {this.currentActor})
    : client = null;
  final SupabaseClient? client;
  final Future<Object?> Function(String, FieldSalesJson)? _rpc;
  final String? Function()? currentActor;

  Future<FieldSalesJson> _call(String name, FieldSalesJson params) async {
    try {
      if ((currentActor?.call() ?? client?.auth.currentUser?.id) != null) {
        throw const FieldSalesFailure(
          'CONFIRMATION_UNAVAILABLE',
          'Open the original link in a separate browser session.',
        );
      }
      final result =
          await (_rpc != null
                  ? _rpc(name, params)
                  : client!.schema('api').rpc(name, params: params))
              .timeout(const Duration(seconds: 25));
      if ((currentActor?.call() ?? client?.auth.currentUser?.id) != null) {
        throw const FieldSalesFailure(
          'CONFIRMATION_UNAVAILABLE',
          'The browser session changed. Open the original link again.',
        );
      }
      return fieldSalesObject(result);
    } on Object {
      throw const FieldSalesFailure(
        'CONFIRMATION_UNAVAILABLE',
        'The response could not be checked. Keep this page open and try the original action again, or contact the company.',
      );
    }
  }

  @override
  Future<FieldSalesJson> requestCode(String token) =>
      _call('field_sales_confirmation_request_code', {'p_token': token});
  @override
  Future<FieldSalesJson> verify(String token, String code) => _call(
    'field_sales_confirmation_verify',
    {'p_token': token, 'p_code': code},
  );
  @override
  Future<FieldSalesJson> respond(
    String token,
    String proof,
    String response,
    String reason,
    bool authorized,
  ) => _call('field_sales_confirmation_respond', {
    'p_token': token,
    'p_proof': proof,
    'p_response': response,
    'p_reason': reason,
    'p_authorized': authorized,
  });
}
