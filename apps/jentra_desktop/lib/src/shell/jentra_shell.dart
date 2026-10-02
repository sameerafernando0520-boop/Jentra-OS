import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../app_providers.dart';
import '../features/auth/mfa_required_screen.dart';
import '../features/operations/operational_link.dart';
import 'navigation.dart';
import 'quick_create_dialog.dart';

class JentraShell extends ConsumerWidget {
  const JentraShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    final gateway = ref.watch(foundationGatewayProvider);
    final tenants = ref.watch(tenantListProvider).value;
    final capabilities = ref.watch(businessCapabilitiesProvider).value;
    final mfaRequired =
        gateway != null &&
        (tenants?.isNotEmpty ?? false) &&
        ref.watch(sessionAssuranceProvider) != MfaAssurance.aal2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
        final collapsed = constraints.maxWidth < 1220 || enlargedText;
        final showInspector = constraints.maxWidth >= 1740 && !enlargedText;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                _showCommandPalette(context),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Row(
                children: [
                  _Sidebar(
                    collapsed: collapsed,
                    currentPath: currentPath,
                    destinations: visibleJentraDestinations(capabilities),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _CommandBar(currentPath: currentPath),
                        Expanded(
                          child: mfaRequired
                              ? const MfaRequiredScreen()
                              : child,
                        ),
                      ],
                    ),
                  ),
                  if (showInspector) const _ContextInspector(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCommandPalette(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => const _CommandPalette());
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.collapsed,
    required this.currentPath,
    required this.destinations,
  });

  final bool collapsed;
  final String currentPath;
  final List<JentraDestination> destinations;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : JentraMotion.standard,
    width: collapsed ? 72 : 248,
    color: JentraColors.navy900,
    child: Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            _SidebarBrand(collapsed: collapsed),
            const Divider(color: JentraColors.darkBorder, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: JentraSpacing.x2,
                  vertical: JentraSpacing.x3,
                ),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  final active = currentPath == item.path;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!collapsed && item.section != null)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            JentraSpacing.x3,
                            index == 0 ? JentraSpacing.x1 : JentraSpacing.x4,
                            JentraSpacing.x3,
                            JentraSpacing.x2,
                          ),
                          child: Text(
                            item.section!,
                            style: const TextStyle(
                              color: JentraColors.darkTextSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      Tooltip(
                        message: collapsed ? item.label : '',
                        child: Semantics(
                          selected: active,
                          button: true,
                          label: item.label,
                          child: InkWell(
                            onTap: () => context.go(item.path),
                            borderRadius: BorderRadius.circular(
                              JentraRadii.control,
                            ),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : JentraMotion.fast,
                              height: 40,
                              padding: EdgeInsets.symmetric(
                                horizontal: collapsed
                                    ? JentraSpacing.x3
                                    : JentraSpacing.x3,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? JentraColors.navy800
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  JentraRadii.control,
                                ),
                                border: active
                                    ? const Border(
                                        left: BorderSide(
                                          color: JentraColors.cyan500,
                                          width: 3,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: collapsed
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 19,
                                    color: active
                                        ? Colors.white
                                        : JentraColors.darkTextSecondary,
                                  ),
                                  if (!collapsed) ...[
                                    const SizedBox(width: JentraSpacing.x3),
                                    Expanded(
                                      child: Text(
                                        item.label,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: active
                                              ? Colors.white
                                              : JentraColors.darkTextSecondary,
                                          fontSize: 13,
                                          fontWeight: active
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (item.shortcut != null)
                                      Text(
                                        item.shortcut!,
                                        style: const TextStyle(
                                          color: JentraColors.darkTextSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Tooltip(
                message: 'Design system',
                child: TextButton(
                  onPressed: () => context.go('/catalogue'),
                  style: TextButton.styleFrom(
                    foregroundColor: JentraColors.darkTextSecondary,
                    backgroundColor: currentPath == '/catalogue'
                        ? JentraColors.navy800
                        : Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      horizontal: collapsed ? 0 : 12,
                    ),
                    minimumSize: const Size(double.infinity, 40),
                  ),
                  child: Row(
                    mainAxisAlignment: collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      const Icon(Icons.design_services_outlined, size: 18),
                      if (!collapsed) ...[
                        const SizedBox(width: 12),
                        const Text('Design system'),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _SidebarFooter(collapsed: collapsed),
          ],
        ),
      ),
    ),
  );
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x4),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: JentraBrandLockup(
              size: collapsed ? 34 : 40,
              compact: collapsed,
              inverse: true,
              showTagline: !collapsed,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(JentraSpacing.x3),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: JentraColors.navy950.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JentraRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JentraSpacing.x3),
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            const Icon(
              Icons.cloud_done_outlined,
              color: JentraColors.green400,
              size: 17,
            ),
            if (!collapsed) ...[
              const SizedBox(width: JentraSpacing.x2),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Development',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Preview data',
                      style: TextStyle(
                        color: JentraColors.darkTextSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _CommandBar extends ConsumerWidget {
  const _CommandBar({required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = jentraDestinations.firstWhere(
      (item) => item.path == currentPath,
      orElse: () => const JentraDestination(
        label: 'Component catalogue',
        path: '/catalogue',
        icon: Icons.widgets_outlined,
      ),
    );
    final tenants = ref.watch(tenantListProvider).value ?? const <dynamic>[];
    final tenantName = tenants.isEmpty ? 'Create business' : tenants.first.name;
    final preferences = ref.watch(appPreferencesProvider).value;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: context.jentraColors.panel,
        border: Border(bottom: BorderSide(color: context.jentraColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1050;
          final tight = constraints.maxWidth < 760;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x4),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 140 : 200),
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!tight) ...[
                  const SizedBox(width: JentraSpacing.x3),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: context.jentraColors.textSecondary,
                  ),
                  const SizedBox(width: JentraSpacing.x3),
                  PopupMenuButton<String>(
                    tooltip: 'Switch company context',
                    onSelected: (_) {},
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'hq',
                        child: Text('Jentra Trading (Pvt) Ltd • HQ'),
                      ),
                      PopupMenuItem(
                        value: 'colombo',
                        child: Text('Jentra Trading (Pvt) Ltd • Colombo'),
                      ),
                    ],
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: compact ? 160 : 220,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              tenantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: context.jentraColors.textSecondary,
                                  ),
                            ),
                          ),
                          const SizedBox(width: JentraSpacing.x1),
                          const Icon(Icons.unfold_more, size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (compact)
                  IconButton(
                    tooltip: 'Search or run a command (Ctrl+K)',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const _CommandPalette(),
                    ),
                    icon: const Icon(Icons.search, size: 19),
                  )
                else
                  SizedBox(
                    width: 330,
                    child: InkWell(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _CommandPalette(),
                      ),
                      borderRadius: BorderRadius.circular(JentraRadii.control),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(
                          horizontal: JentraSpacing.x3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          border: Border.all(
                            color: context.jentraColors.border,
                          ),
                          borderRadius: BorderRadius.circular(
                            JentraRadii.control,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 17,
                              color: context.jentraColors.textSecondary,
                            ),
                            const SizedBox(width: JentraSpacing.x2),
                            Expanded(
                              child: Text(
                                'Search or run a command',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: context.jentraColors.textSecondary,
                                    ),
                              ),
                            ),
                            const SizedBox(width: JentraSpacing.x2),
                            const _KeyHint(label: 'Ctrl K'),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: JentraSpacing.x2),
                if (compact)
                  IconButton.filled(
                    tooltip: 'Quick create',
                    onPressed: () => _showQuickCreate(context),
                    icon: const Icon(Icons.add, size: 17),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => _showQuickCreate(context),
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Create'),
                  ),
                const SizedBox(width: JentraSpacing.x2),
                if (!tight)
                  IconButton(
                    tooltip: preferences?.density == JentraDensity.compact
                        ? 'Use comfortable density'
                        : 'Use compact density',
                    onPressed: () => ref
                        .read(appPreferencesProvider.notifier)
                        .toggleDensity(),
                    icon: const Icon(Icons.density_medium_outlined, size: 19),
                  ),
                IconButton(
                  tooltip: 'Toggle theme',
                  onPressed: () =>
                      ref.read(appPreferencesProvider.notifier).toggleTheme(),
                  icon: Icon(
                    preferences?.themeMode == ThemeMode.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 19,
                  ),
                ),
                if (!tight)
                  const Badge(
                    smallSize: 7,
                    child: IconButton(
                      tooltip: 'Notifications',
                      onPressed: null,
                      icon: Icon(Icons.notifications_none, size: 20),
                    ),
                  ),
                const SizedBox(width: JentraSpacing.x2),
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: JentraColors.navy800,
                  child: Text(
                    'SA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showQuickCreate(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const QuickCreateDialog(),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: context.jentraColors.panel,
      border: Border.all(color: context.jentraColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: const TextStyle(fontSize: 10)),
  );
}

class _CommandPalette extends ConsumerStatefulWidget {
  const _CommandPalette();

  @override
  ConsumerState<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<_CommandPalette> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final documentLocation = parseOperationalDocumentLocation(query);
    final destinations = [
      ...visibleJentraDestinations(
        ref.watch(businessCapabilitiesProvider).value,
      ),
      const JentraDestination(
        label: 'Design system',
        path: '/catalogue',
        icon: Icons.design_services_outlined,
        section: 'SYSTEM',
      ),
    ];
    final matches = destinations
        .where((item) => item.label.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Dialog(
      alignment: const Alignment(0, -0.65),
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                hintText: 'Search modules, records, or commands…',
                prefixIcon: Icon(Icons.search),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(JentraSpacing.x2),
                children: [
                  if (documentLocation != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined, size: 19),
                      title: const Text('Open permitted document'),
                      subtitle: const Text('Access is checked after opening'),
                      trailing: const Icon(Icons.keyboard_return, size: 16),
                      onTap: () {
                        final router = GoRouter.of(context);
                        Navigator.pop(context);
                        router.go(documentLocation);
                      },
                    ),
                  for (final item in matches)
                    ListTile(
                      dense: true,
                      leading: Icon(item.icon, size: 19),
                      title: Text(item.label),
                      subtitle: Text(item.section ?? 'Workspace'),
                      trailing: const Icon(Icons.keyboard_return, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        context.go(item.path);
                      },
                    ),
                  if (matches.isEmpty && documentLocation == null)
                    const Padding(
                      padding: EdgeInsets.all(JentraSpacing.x8),
                      child: Center(
                        child: Text('No commands match your search.'),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(JentraSpacing.x3),
              child: Row(
                children: [
                  const _KeyHint(label: '↑↓'),
                  const SizedBox(width: JentraSpacing.x2),
                  Text(
                    'Navigate',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: JentraSpacing.x4),
                  const _KeyHint(label: 'Enter'),
                  const SizedBox(width: JentraSpacing.x2),
                  Text('Open', style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  const JentraStatusBadge(
                    label: 'Permission-aware',
                    tone: JentraStatusTone.info,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextInspector extends StatelessWidget {
  const _ContextInspector();

  @override
  Widget build(BuildContext context) => Container(
    width: 360,
    decoration: BoxDecoration(
      color: context.jentraColors.panel,
      border: Border(left: BorderSide(color: context.jentraColors.border)),
    ),
    child: const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(JentraSpacing.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            JentraSectionHeader(
              title: 'Context',
              description: 'Illustrative workspace scope',
            ),
            SizedBox(height: JentraSpacing.x5),
            _ContextRow(label: 'Tenant', value: 'Jentra Holdings'),
            _ContextRow(
              label: 'Legal entity',
              value: 'Jentra Trading (Pvt) Ltd',
            ),
            _ContextRow(label: 'Branch', value: 'Head Office'),
            _ContextRow(label: 'Currency', value: 'LKR'),
            _ContextRow(label: 'Time zone', value: 'Asia/Colombo'),
            SizedBox(height: JentraSpacing.x5),
            JentraStatusBadge(
              label: 'Preview context',
              tone: JentraStatusTone.info,
            ),
            Spacer(),
            Text(
              'Every command carries this scope, actor, idempotency key and entity version.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: JentraSpacing.x4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: JentraSpacing.x1),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}
