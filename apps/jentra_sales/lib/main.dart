import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';
import 'package:jentra_platform/field_confirmation.dart';

import 'src/data/sales_gateway.dart';
import 'src/data/sales_store_factory.dart';
import 'src/sales_app.dart';
import 'src/sales_controller.dart';
import 'src/field_sales_controller.dart';
import 'src/confirmation_controller.dart';
import 'src/ui/customer_confirmation.dart';
import 'src/delivery_confirmation_controller.dart';
import 'src/ui/delivery_confirmation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the browser semantics tree available for keyboards and assistive tools.
  SemanticsBinding.instance.ensureSemantics();
  const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xpdoufauvrbdmxgngetv.supabase.co',
  );
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  const enableCandidate = bool.fromEnvironment('FIELD_SALES_CANDIDATE_ENABLED');
  final confirmationLink = captureFieldConfirmationLink();
  if (confirmationLink.present) {
    const enableConfirmation = bool.fromEnvironment(
      'FIELD_SALES_EMAIL_CONFIRMATION_ENABLED',
    );
    final recipientClient =
        enableCandidate &&
            enableConfirmation &&
            (!confirmationLink.delivery ||
                const bool.fromEnvironment(
                  'FIELD_SALES_DELIVERY_CONFIRMATION_ENABLED',
                )) &&
            key.isNotEmpty &&
            Uri.tryParse(url)?.scheme == 'https'
        ? SupabaseClient(
            url,
            key,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          )
        : null;
    if (confirmationLink.delivery) {
      runApp(
        CustomerDeliveryApp(
          DeliveryConfirmationController(
            token: confirmationLink.token,
            gateway: recipientClient == null
                ? null
                : SupabaseFieldDeliveryGateway(recipientClient),
          ),
        ),
      );
      return;
    }
    runApp(
      CustomerConfirmationApp(
        ConfirmationController(
          token: confirmationLink.token,
          gateway: recipientClient == null
              ? null
              : SupabaseFieldConfirmationGateway(recipientClient),
        ),
      ),
    );
    return;
  }
  final store = createSalesStore(projectUrl: url);
  final client = key.isNotEmpty && Uri.tryParse(url)?.scheme == 'https'
      ? SupabaseClient(
          url,
          key,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        )
      : null;
  final account = client == null
      ? null
      : SupabaseSalesAccountGateway(client, enableCandidate: enableCandidate);
  runApp(
    SalesApp(
      controller: SalesController(
        store: store,
        account: account,
        field: enableCandidate && client != null
            ? FieldSalesController(
                gateway: SupabaseFieldSalesGateway(client),
                store: store,
                authChanges: client.auth.onAuthStateChange.map(
                  (event) => event.session?.user.id,
                ),
              )
            : null,
      ),
    ),
  );
}
