import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_domain.dart';

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
    label: 'Inventory',
    path: '/inventory',
    icon: Icons.inventory_2_outlined,
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
  return jentraDestinations
      .where((item) => item.path != '/setup' || canOpenSetup)
      .toList(growable: false);
}
