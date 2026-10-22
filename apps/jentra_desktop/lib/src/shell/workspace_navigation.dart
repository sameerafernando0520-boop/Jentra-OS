import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import 'navigation.dart';

/// Groups only destinations already permitted by the current access read.
class WorkspaceNavigation extends StatelessWidget {
  const WorkspaceNavigation({
    required this.destinations,
    required this.currentPath,
    required this.collapsed,
    super.key,
  });

  final List<JentraDestination> destinations;
  final String currentPath;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final groups = groupWorkspaceDestinations(destinations);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        for (final group in groups)
          _WorkspaceNavigationGroup(
            key: ValueKey('navigation-${group.label}'),
            group: group,
            collapsed: collapsed,
            currentPath: currentPath,
          ),
      ],
    );
  }
}

final class WorkspaceDestinationGroup {
  const WorkspaceDestinationGroup(this.label, this.icon, this.items);
  final String label;
  final IconData icon;
  final List<JentraDestination> items;
}

List<WorkspaceDestinationGroup> groupWorkspaceDestinations(
  List<JentraDestination> permitted,
) {
  final remaining = [...permitted];
  final result = <WorkspaceDestinationGroup>[];
  void take(String label, IconData icon, bool Function(String path) belongs) {
    final items = remaining.where((item) => belongs(item.path)).toList();
    if (items.isEmpty) return;
    remaining.removeWhere((item) => belongs(item.path));
    result.add(
      WorkspaceDestinationGroup(label, icon, List.unmodifiable(items)),
    );
  }

  take(
    'Command centre',
    Icons.space_dashboard_outlined,
    (path) => path == '/dashboard',
  );
  take('Business setup', Icons.tune_outlined, (path) => path == '/setup');
  take(
    'Revenue',
    Icons.handshake_outlined,
    (path) => const {'/crm', '/sales', '/receivables'}.contains(path),
  );
  take(
    'Procurement',
    Icons.shopping_bag_outlined,
    (path) => path == '/procurement' || path.startsWith('/procurement/'),
  );
  take(
    'Inventory',
    Icons.inventory_2_outlined,
    (path) => path == '/inventory' || path.startsWith('/inventory/'),
  );
  take(
    'Finance',
    Icons.account_balance_outlined,
    (path) => path == '/finance' || path.startsWith('/finance/'),
  );
  take(
    'People',
    Icons.groups_outlined,
    (path) => path == '/people' || path.startsWith('/people/'),
  );
  take(
    'Assets',
    Icons.business_outlined,
    (path) => path == '/assets' || path.startsWith('/assets/'),
  );
  take(
    'Projects',
    Icons.view_timeline_outlined,
    (path) => path == '/projects' || path.startsWith('/projects/'),
  );
  take(
    'Service',
    Icons.support_agent_outlined,
    (path) => path == '/service' || path.startsWith('/service/'),
  );
  take(
    'Audit & assurance',
    Icons.verified_user_outlined,
    (path) => path.startsWith('/governance/'),
  );
  take(
    'Analytics',
    Icons.query_stats_outlined,
    (path) => path == '/analytics' || path.startsWith('/analytics/'),
  );
  take(
    'Administration',
    Icons.admin_panel_settings_outlined,
    (path) =>
        path == '/control' || path.startsWith('/operations/notifications'),
  );
  for (final item in remaining) {
    result.add(WorkspaceDestinationGroup(item.label, item.icon, [item]));
  }
  return List.unmodifiable(result);
}

class _WorkspaceNavigationGroup extends StatelessWidget {
  const _WorkspaceNavigationGroup({
    super.key,
    required this.group,
    required this.collapsed,
    required this.currentPath,
  });
  final WorkspaceDestinationGroup group;
  final bool collapsed;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final active = group.items.any(
      (item) =>
          currentPath == item.path || currentPath.startsWith('${item.path}/'),
    );
    const textColor = JentraColors.darkTextSecondary;
    if (collapsed) {
      if (group.items.length == 1) {
        return Tooltip(
          message: group.label,
          child: IconButton(
            tooltip: group.label,
            isSelected: active,
            onPressed: () => context.go(group.items.single.path),
            icon: Icon(group.icon, color: active ? Colors.white : textColor),
          ),
        );
      }
      return PopupMenuButton<String>(
        tooltip: group.label,
        onSelected: (path) => context.go(path),
        itemBuilder: (_) => [
          for (final item in group.items)
            PopupMenuItem(value: item.path, child: Text(item.label)),
        ],
        child: Semantics(
          button: true,
          selected: active,
          label: group.label,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Icon(group.icon, color: active ? Colors.white : textColor),
          ),
        ),
      );
    }
    if (group.items.length == 1) {
      return _NavigationLink(
        item: group.items.single,
        active: active,
        label: group.label,
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('${group.label}-$active'),
        initiallyExpanded: active,
        maintainState: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
        iconColor: Colors.white,
        collapsedIconColor: textColor,
        textColor: Colors.white,
        collapsedTextColor: textColor,
        leading: Icon(
          group.icon,
          size: 20,
          color: active ? Colors.white : textColor,
        ),
        title: Text(
          group.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        children: [
          for (final item in group.items)
            _NavigationLink(
              item: item,
              active: currentPath == item.path,
              compact: true,
            ),
        ],
      ),
    );
  }
}

class _NavigationLink extends StatelessWidget {
  const _NavigationLink({
    required this.item,
    required this.active,
    this.label,
    this.compact = false,
  });
  final JentraDestination item;
  final bool active, compact;
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Semantics(
      selected: active,
      child: ListTile(
        dense: true,
        selected: active,
        selectedColor: Colors.white,
        textColor: JentraColors.darkTextSecondary,
        iconColor: JentraColors.darkTextSecondary,
        selectedTileColor: JentraColors.navy800,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JentraRadii.control),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minLeadingWidth: compact ? 16 : 24,
        leading: Icon(item.icon, size: compact ? 16 : 20),
        title: Text(
          label ?? item.label,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: () => context.go(item.path),
      ),
    ),
  );
}
