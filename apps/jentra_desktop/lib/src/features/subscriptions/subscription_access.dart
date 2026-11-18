import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../../app_providers.dart';
import '../platform_control/platform_organization_screen.dart';

typedef SubscriptionRow = Map<String, dynamic>;

List<SubscriptionRow> subscriptionRows(Object? value) => [
  for (final row in (value as List<dynamic>?) ?? const [])
    Map<String, dynamic>.from(row as Map),
];

final class SubscriptionAccess {
  SubscriptionAccess(this.actorId, this.data);

  final String actorId;
  final SubscriptionRow data;

  bool get enabled => data['enabled'] == true;
  bool get requiresCheckout => data['requires_checkout'] == true;
  bool get workspacePaused => data['workspace_paused'] == true;
  bool get emailVerified => data['email_verified'] == true;
  String? get email => data['email'] as String?;
  List<SubscriptionRow> get renewable => subscriptionRows(data['renewable']);
  List<String> get pausedTenantIds =>
      ((data['paused_tenant_ids'] as List<dynamic>?) ?? const [])
          .cast<String>();
}

final subscriptionAccessProvider = FutureProvider<SubscriptionAccess?>((
  ref,
) async {
  final gateway = ref.watch(platformOrganizationGatewayProvider);
  ref.watch(authSessionRevisionProvider);
  final actor = ref.watch(foundationGatewayProvider)?.currentUser?.id;
  if (gateway == null || actor == null) return null;

  final timer = Timer(const Duration(seconds: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  try {
    return SubscriptionAccess(
      actor,
      await gateway.rpc<SubscriptionRow>('subscription_checkout_access'),
    );
  } on PlatformOrganizationFailure catch (error) {
    // Older backend releases do not expose subscription checkout.
    if (error.code == 'PGRST202') return null;
    rethrow;
  }
}, retry: (_, _) => null);
