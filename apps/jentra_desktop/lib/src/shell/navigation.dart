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
    label: 'Manual journals',
    path: '/finance/journals',
    icon: Icons.menu_book_outlined,
  ),
  JentraDestination(
    label: 'AR / AP controls',
    path: '/finance/controls',
    icon: Icons.account_balance_outlined,
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
        (item.path != '/finance/controls' ||
            const [
              'finance.view',
              'finance.controls.reconcile',
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
