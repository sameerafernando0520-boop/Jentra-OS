import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:flutter/material.dart';

final class JentraDestination {
  const JentraDestination({
    required this.label,
    required this.path,
    required this.icon,
    this.section,
    this.shortcut,
  });

  final String label;
  final String path;
  final IconData icon;
  final String? section;
  final String? shortcut;
}

const jentraDestinations = <JentraDestination>[
  JentraDestination(
    label: 'Command centre',
    path: '/dashboard',
    icon: Icons.space_dashboard_outlined,
    section: 'WORKSPACE',
    shortcut: 'G D',
  ),
  JentraDestination(
    label: 'Business setup',
    path: '/setup',
    icon: Icons.tune_outlined,
    section: 'FOUNDATION',
    shortcut: 'G S',
  ),
  JentraDestination(
    label: 'CRM & Revenue',
    path: '/crm',
    icon: Icons.handshake_outlined,
    section: 'OPERATIONS',
  ),
  JentraDestination(
    label: 'Sales',
    path: '/sales',
    icon: Icons.receipt_long_outlined,
  ),
  JentraDestination(
    label: 'Procurement',
    path: '/procurement',
    icon: Icons.shopping_bag_outlined,
  ),
  JentraDestination(
    label: 'Fulfillment & receivables',
    path: '/receivables',
    icon: Icons.payments_outlined,
  ),
  JentraDestination(
    label: 'Inventory',
    path: '/inventory',
    icon: Icons.inventory_2_outlined,
  ),
  JentraDestination(
    label: 'Warehouse transfers',
    path: '/inventory/transfers',
    icon: Icons.swap_horiz_outlined,
  ),
  JentraDestination(
    label: 'Stock counts',
    path: '/inventory/counts',
    icon: Icons.fact_check_outlined,
  ),
  JentraDestination(
    label: 'Stock reservations',
    path: '/inventory/reservations',
    icon: Icons.bookmark_border,
  ),
  JentraDestination(
    label: 'Receipt quantity trace',
    path: '/inventory/receipt-trace',
    icon: Icons.account_tree_outlined,
  ),
  JentraDestination(
    label: 'Landed value',
    path: '/inventory/landed-value',
    icon: Icons.price_change_outlined,
  ),
  JentraDestination(
    label: 'Inventory valuation',
    path: '/inventory/valuation',
    icon: Icons.fact_check_outlined,
  ),
  JentraDestination(
    label: 'Finance',
    path: '/finance',
    icon: Icons.account_balance_outlined,
    section: 'MANAGEMENT',
  ),
  JentraDestination(
    label: 'People',
    path: '/people',
    icon: Icons.groups_outlined,
  ),
  JentraDestination(
    label: 'Work calendars',
    path: '/people/calendars',
    icon: Icons.calendar_month_outlined,
  ),
  JentraDestination(
    label: 'Organization',
    path: '/people/organization',
    icon: Icons.account_tree_outlined,
  ),
  JentraDestination(
    label: 'Private HR & account',
    path: '/people/private',
    icon: Icons.privacy_tip_outlined,
  ),
  JentraDestination(
    label: 'Manual journals',
    path: '/finance/journals',
    icon: Icons.menu_book_outlined,
  ),
  JentraDestination(
    label: 'Finance controls',
    path: '/finance/controls',
    icon: Icons.account_balance_outlined,
  ),
  JentraDestination(
    label: 'Control and close review',
    icon: Icons.fact_check_outlined,
    path: '/finance/close-review',
  ),
  JentraDestination(
    label: 'Financial dimensions',
    icon: Icons.category_outlined,
    path: '/finance/dimensions',
  ),
  JentraDestination(
    label: 'Bank reconciliation',
    path: '/finance/bank',
    icon: Icons.account_balance_wallet_outlined,
  ),
  JentraDestination(
    label: 'Period & FX close',
    path: '/finance/periods',
    icon: Icons.event_repeat_outlined,
  ),
  JentraDestination(
    label: 'Financial statements',
    path: '/finance/statements',
    icon: Icons.table_chart_outlined,
  ),
  JentraDestination(
    label: 'Tax review',
    path: '/finance/tax',
    icon: Icons.receipt_long_outlined,
  ),
  JentraDestination(
    label: 'Cash-flow mappings',
    path: '/finance/cash-flow-mappings',
    icon: Icons.alt_route_outlined,
  ),
  JentraDestination(
    label: 'Budgets & variance',
    path: '/finance/budgets',
    icon: Icons.stacked_bar_chart_outlined,
  ),
  JentraDestination(
    label: 'Projects',
    path: '/projects',
    icon: Icons.view_timeline_outlined,
  ),
  JentraDestination(
    label: 'Service',
    path: '/service',
    icon: Icons.support_agent_outlined,
  ),
  JentraDestination(
    label: 'Analytics',
    path: '/analytics',
    icon: Icons.query_stats_outlined,
    section: 'INTELLIGENCE',
  ),
  JentraDestination(
    label: 'Jentra Control',
    path: '/control',
    icon: Icons.admin_panel_settings_outlined,
  ),
];

List<JentraDestination> visibleJentraDestinations(Set<String>? capabilities) {
  final canOpenSetup =
      capabilities != null &&
      BusinessSetupResource.values.any(
        (resource) => capabilities.contains(resource.viewPermission),
      );
  final canOpenCrm =
      capabilities != null &&
      const {
        'crm.leads.view',
        'crm.leads.manage',
        'crm.opportunities.view',
        'crm.opportunities.manage',
      }.any(capabilities.contains);
  final visible = <JentraDestination>[];
  String? pendingSection;
  for (final item in jentraDestinations) {
    pendingSection = item.section ?? pendingSection;
    final permitted =
        (item.path != '/setup' || canOpenSetup) &&
        (item.path != '/finance/journals' ||
            (capabilities?.contains('finance.view') ?? false)) &&
        (item.path != '/finance/bank' ||
            (capabilities?.contains('finance.view') ?? false)) &&
        (item.path != '/finance/periods' ||
            (capabilities?.contains('finance.view') ?? false)) &&
        (item.path != '/finance/statements' ||
            (capabilities?.contains('finance.view') ?? false)) &&
        (item.path != '/finance/tax' ||
            (capabilities?.contains('finance.view') ?? false)) &&
        (item.path != '/finance/budgets' ||
            (capabilities?.contains('finance.view') ?? false)) &&
        (item.path != '/finance/cash-flow-mappings' ||
            const {
              'finance.view',
              'finance.cash_flow.configure',
            }.every((p) => capabilities?.contains(p) ?? false)) &&
        (item.path != '/people' ||
            const [
              'people.view',
              'people.employees.view',
            ].every((p) => capabilities?.contains(p) ?? false)) &&
        (item.path != '/people/calendars' ||
            const [
              'people.view',
              'people.calendars.view',
            ].every((p) => capabilities?.contains(p) ?? false)) &&
        (item.path != '/people/organization' ||
            const ['people.view', 'people.organization.view']
                .every((p) => capabilities?.contains(p) ?? false)) &&
        (item.path != '/people/private' ||
            (capabilities?.contains('people.view') ?? false)) &&
        (item.path != '/finance/controls' ||
            const [
              'finance.view',
              'finance.controls.reconcile',
            ].every((p) => capabilities?.contains(p) ?? false)) &&
        (item.path != '/finance/close-review' ||
            const [
              'finance.view',
              'finance.controls.reconcile',
              'inventory.stock.view',
              'inventory.cost.view',
            ].every((p) => capabilities?.contains(p) ?? false)) &&
        (item.path != '/finance/dimensions' ||
            const [
              'finance.view',
              'finance.dimensions.manage',
            ].every((p) => capabilities?.contains(p) ?? false)) &&
        (item.path != '/inventory/valuation' ||
            const [
              'inventory.stock.view',
              'inventory.cost.view',
              'finance.view',
            ].every((p) => capabilities?.contains(p) ?? false)) &&
        (!{
              '/inventory/receipt-trace',
              '/inventory/landed-value',
            }.contains(item.path) ||
            (capabilities != null &&
                capabilities.contains('inventory.valuation.post') &&
                capabilities.contains('inventory.cost.view'))) &&
        (item.path != '/inventory/reservations' ||
            (capabilities?.contains('inventory.reservations.manage') ??
                false)) &&
        (item.path != '/inventory/counts' ||
            (capabilities != null &&
                capabilities.contains('inventory.cost.view') &&
                const {
                  'inventory.adjustments.post',
                  'workflow.approvals.decide',
                }.any(capabilities.contains))) &&
        (item.path != '/inventory/transfers' ||
            (capabilities?.contains('inventory.transfers.post') ?? false)) &&
        (item.path != '/inventory' ||
            (capabilities != null && canReadStockOpenings(capabilities))) &&
        (item.path != '/crm' || canOpenCrm) &&
        (item.path != '/receivables' ||
            (capabilities != null &&
                const {
                  'sales.deliveries.view',
                  'sales.deliveries.manage',
                  'sales.deliveries.post',
                  'sales.invoices.view',
                  'sales.invoices.manage',
                  'sales.invoices.post',
                  'finance.receipts.view',
                  'finance.receipts.manage',
                  'finance.receipts.post',
                  'sales.returns.view',
                  'sales.returns.manage',
                  'sales.returns.post',
                  'finance.receivables.view',
                  'workflow.approvals.decide',
                }.any(capabilities.contains))) &&
        (item.path != '/sales' ||
            (capabilities != null &&
                const {
                  'sales.quotations.view',
                  'sales.quotations.manage',
                  'sales.orders.view',
                  'sales.orders.manage',
                }.any(capabilities.contains)));
    if (!permitted) continue;
    visible.add(
      JentraDestination(
        label: item.label,
        path: item.path,
        icon: item.icon,
        section: pendingSection,
        shortcut: item.shortcut,
      ),
    );
    pendingSection = null;
  }
  return List.unmodifiable(visible);
}
