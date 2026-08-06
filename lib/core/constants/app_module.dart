import 'package:flutter/material.dart';

enum AppModule {
  dashboard('/dashboard', 'Dashboard', Icons.dashboard_outlined),
  company('/company/settings', 'Company', Icons.business_outlined),
  crm('/crm', 'CRM', Icons.groups_outlined),
  sales('/sales', 'Sales', Icons.receipt_long_outlined),
  inventory('/inventory', 'Inventory', Icons.inventory_2_outlined),
  finance('/finance', 'Finance', Icons.account_balance_wallet_outlined),
  accounting('/accounting', 'Accounting', Icons.calculate_outlined),
  aiAssistant('/ai-assistant', 'AI Assistant', Icons.auto_awesome_outlined),
  subscription(
    '/subscription',
    'Subscription',
    Icons.workspace_premium_outlined,
  ),
  settings('/settings', 'Settings', Icons.settings_outlined);

  const AppModule(this.route, this.label, this.icon);

  final String route;
  final String label;
  final IconData icon;

  static AppModule fromPath(String path) {
    return values.firstWhere(
      (module) => path == module.route || path.startsWith('${module.route}/'),
      orElse: () => dashboard,
    );
  }
}
