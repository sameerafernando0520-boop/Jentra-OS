import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'src/features/procurement/procurement_controller.dart';

import 'package:jentra_platform/jentra_stock_opening_platform.dart';
import 'src/features/stock_opening/stock_opening_controller.dart';
import 'src/app.dart';
import 'src/app_providers.dart';
import 'src/features/receivables/receivables_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = RuntimeConfig.fromEnvironment();
  final client = await SupabasePlatform.initialize(config);
  final foundationGateway = client == null
      ? null
      : SupabaseFoundationGateway(client);
  final businessSetupGateway = client == null
      ? null
      : SupabaseBusinessSetupGateway(client);
  final crmRepository = client == null ? null : SupabaseCrmGateway(client);
  final quotations = client == null ? null : SupabaseLeadToCashGateway(client);

  runApp(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(config),
        foundationGatewayProvider.overrideWithValue(foundationGateway),
        stockOpeningAccessGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseStockOpeningAccessGateway(client),
        ),
        businessSetupGatewayProvider.overrideWithValue(businessSetupGateway),
        crmRepositoryProvider.overrideWithValue(crmRepository),
        leadToCashRepositoryProvider.overrideWithValue(quotations),
        quotationWorkspaceRepositoryProvider.overrideWithValue(quotations),
        salesOrderRepositoryProvider.overrideWithValue(quotations),
        quotationReferenceRepositoryProvider.overrideWithValue(quotations),
        stockOpeningRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseStockOpeningGateway(client),
        ),
        receivablesRepositoryProvider.overrideWithValue(
          client == null ? null : SupabaseReceivablesGateway(client),
        ),
        procurementGatewayProvider.overrideWithValue(
          client == null ? null : SupabaseProcurementGateway(client),
        ),
      ],
      child: const JentraApp(),
    ),
  );
}
