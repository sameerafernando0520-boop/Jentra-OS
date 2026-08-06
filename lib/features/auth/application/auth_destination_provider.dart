import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import 'auth_state_provider.dart';

enum AuthDestination {
  login('/login'),
  companyOnboarding('/company/onboarding'),
  companySelection('/company/select'),
  dashboard('/dashboard');

  const AuthDestination(this.route);

  final String route;
}

/// Resolves the first authenticated destination without placing tenant queries
/// in a screen or router callback.
final authDestinationProvider = FutureProvider.autoDispose<AuthDestination>((
  ref,
) async {
  final session = await ref.watch(authSessionProvider.future);
  if (session == null) return AuthDestination.login;

  final companyState = await ref.watch(companyControllerProvider.future);
  if (!companyState.hasCompanies) {
    return AuthDestination.companyOnboarding;
  }
  if (companyState.selectedCompany == null) {
    return AuthDestination.companySelection;
  }
  return AuthDestination.dashboard;
});
