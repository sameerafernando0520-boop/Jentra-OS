import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../auth/managed_staff_dialog.dart';
import '../auth/mfa_required_screen.dart';
import 'operator_security_dialog.dart';

part 'subscription_control.dart';
part 'system_control.dart';

typedef _Row = Map<String, Object?>;

final platformOrganizationGatewayProvider =
    Provider<PlatformOrganizationGateway?>((ref) => null);

// The signed-in actor, recomputed on every auth event but only notifying
// listeners when the actor itself changes. Token refreshes (which
// supabase's mfa.listFactors triggers) must not reload the assignment check,
// or the MFA screen is torn down and rebuilt in an endless refresh loop.
final _platformActorIdProvider = Provider.autoDispose<String?>((ref) {
  ref.watch(authSessionRevisionProvider);
  return ref.watch(foundationGatewayProvider)?.currentUser?.id;
});

// Assignment alone allows the entry point to be shown before verification.
// Every organization operation checks both assignment and AAL2 at the server.
final platformOrganizationAccessProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final user = ref.watch(_platformActorIdProvider);
  final gateway = ref.watch(platformOrganizationGatewayProvider);
  if (gateway == null || user == null) return false;
  try {
    return await gateway.rpc<bool>('platform_organization_assignment');
  } on PlatformOrganizationFailure {
    return false;
  }
});

class PlatformOrganizationScreen extends ConsumerWidget {
  const PlatformOrganizationScreen({this.standalone = false, super.key});

  final bool standalone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(platformOrganizationAccessProvider);
    final assurance = ref.watch(sessionAssuranceProvider);
    final gateway = ref.watch(platformOrganizationGatewayProvider);
    final foundation = ref.watch(foundationGatewayProvider);
    final actor = foundation?.currentUser?.id;
    // The standalone J panel gives a verified operator the full rail layout,
    // which carries its own brand, account, security and sign-out controls.
    if (standalone &&
        access.value == true &&
        assurance == MfaAssurance.aal2 &&
        gateway != null &&
        foundation != null &&
        actor != null) {
      return Scaffold(
        body: _ControlPanel(
          key: ValueKey(actor),
          gateway: gateway,
          foundation: foundation,
          standalone: true,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !standalone,
        leading: standalone
            ? null
            : IconButton(
                tooltip: 'Return to workspace',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/dashboard'),
              ),
        title: const Text('J panel'),
        actions: [
          if (access.value == true &&
              assurance == MfaAssurance.aal2 &&
              gateway != null &&
              foundation != null)
            IconButton(
              tooltip: 'Account security',
              icon: const Icon(Icons.manage_accounts_outlined),
              onPressed: () => showOperatorSecurityDialog(
                context,
                foundation: foundation,
                gateway: gateway,
              ),
            ),
          if (standalone && foundation != null)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                try {
                  await foundation.signOut();
                } on Object {
                  if (context.mounted) {
                    _notice(context, 'Could not sign out. Try again.');
                  }
                }
              },
            ),
        ],
      ),
      body: access.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        data: (assigned) {
          if (!assigned || gateway == null || actor == null) {
            return const Center(
              child: Text('Platform operator access required.'),
            );
          }
          if (assurance == MfaAssurance.unauthenticated) {
            return const Center(child: CircularProgressIndicator());
          }
          if (assurance != MfaAssurance.aal2) {
            return const MfaRequiredScreen(
              description: 'Verify your platform operator session to manage organizations.',
            );
          }
          return _ControlPanel(key: ValueKey(actor), gateway: gateway);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not check operator access.')),
      ),
    );
  }
}

/// The J panel sections shown in the navigation rail, in display order.
enum _Section {
  overview('Overview', Icons.dashboard_outlined, Icons.dashboard),
  organizations('Organizations', Icons.apartment_outlined, Icons.apartment),
  packages('Packages', Icons.inventory_2_outlined, Icons.inventory_2),
  subscriptions(
    'Subscriptions',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
  ),
  archives('Archives', Icons.archive_outlined, Icons.archive);

  const _Section(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Client-side status filter over the organizations on the current page.
enum _StatusFilter { all, active, trial, other }

class _ControlPanel extends StatefulWidget {
  const _ControlPanel({
    required this.gateway,
    this.foundation,
    this.standalone = false,
    super.key,
  });

  final PlatformOrganizationGateway gateway;

  /// Signed-in foundation gateway. When [standalone], the rail shows the
  /// operator account, Account security and Sign out.
  final SupabaseFoundationGateway? foundation;
  final bool standalone;

  @override
  State<_ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<_ControlPanel> {
  final _search = TextEditingController();
  final _selection = <String, _Row>{};
  List<_Row> _organizations = [];
  List<_Row> _packages = [];
  List<_Row> _cleanup = [];
  List<_Row> _archives = [];
  int _offset = 0;
  bool _busy = false;
  _Section _section = _Section.overview;
  _StatusFilter _filter = _StatusFilter.all;
  String? _error;

  PlatformOrganizationGateway get _gateway => widget.gateway;

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final data = await Future.wait([
      _gateway.rpc<List<dynamic>>('platform_list_organizations', {
        'p_query': _search.text.trim(),
        'p_offset': _offset,
      }),
      _gateway.rpc<List<dynamic>>('platform_list_packages'),
      _gateway.rpc<List<dynamic>>('platform_organization_cleanup_pending'),
      _gateway.rpc<List<dynamic>>('platform_organization_archive_history'),
    ]);
    if (!mounted) return;
    setState(() {
      _organizations = data[0].map(_row).toList();
      _packages = data[1].map(_row).toList();
      _cleanup = data[2].map(_row).toList();
      _archives = data[3].map(_row).toList();
      for (final row in _organizations.take(50)) {
        final id = row['id'] as String;
        if (_selection.containsKey(id)) _selection[id] = row;
      }
    });
  }

  Future<void> _run(Future<void> Function() action, [String? success]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && success != null) _notice(context, success);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _package([_Row? current]) async {
    final currency = current?['currency_code'] as String? ?? 'LKR';
    final amount = current?['price_minor'] as int?;
    await _edit(
      context,
      current == null ? 'Create package' : 'Edit package',
      'Enter 0 to offer this package free of charge. Existing payment records keep their original amounts.',
      [
        if (current == null) const _Field('code', 'Package code'),
        const _Field(
          'name',
          'Package name',
        ).filled(current?['name'] as String?),
        _Field('currency', 'Price currency', initial: currency),
        _Field(
          'price',
          'Price',
          initial: amount == null ? '' : _decimal(amount, currency),
        ),
        const _Field(
          'trial_days',
          'Trial days',
          initial: '30',
        ).filled(current?['trial_days']?.toString()),
        _Field(
          'status',
          'Status',
          initial: current?['status'] as String? ?? 'active',
          choices: const {'active': 'Active', 'retired': 'Retired'},
        ),
        if (current == null)
          _Field(
            'template',
            'Copy package entitlements from',
            choices: _packageChoices(_packages),
          ),
      ],
      (values) async {
        final code = values['currency']!.toUpperCase();
        await _gateway.rpc<Object?>('platform_save_package', {
          'p_code': current?['code'] ?? values['code']!.toLowerCase(),
          'p_name': values['name'],
          'p_price_minor': _minor(values['price']!, code),
          'p_currency_code': code,
          'p_trial_days': int.tryParse(values['trial_days']!),
          'p_status': values['status'],
          'p_expected_revision': current?['revision'],
          'p_copy_from_code': values['template'],
        });
      },
    );
    if (mounted) await _run(_refresh);
  }

  Future<void> _modules(_Row package) async {
    _Row current;
    try {
      final rows = await _gateway.rpc<List<dynamic>>(
        'platform_package_modules',
      );
      current = rows.map(_row).firstWhere((r) => r['code'] == package['code']);
    } on Object {
      if (mounted) _notice(context, 'Could not load the package modules.');
      return;
    }
    if (!mounted) return;
    final modules = _row(current['modules']);
    final changed = await _edit(
      context,
      'Modules for ${package['name']}',
      'Every organization on this package gets the modules switched on here. To give one organization a different set, move it to another package.',
      [
        for (final entry in _moduleLabels.entries)
          _Field(
            entry.key,
            entry.value,
            initial: modules[entry.key] == true ? 'on' : 'off',
            choices: const {'on': 'On', 'off': 'Off'},
          ),
      ],
      (values) async {
        await _gateway.rpc<Object?>('platform_save_package_modules', {
          'p_code': package['code'],
          'p_modules': {
            for (final code in _moduleLabels.keys) code: values[code] == 'on',
          },
          'p_expected_revision': current['revision'],
        });
      },
    );
    if (mounted && changed) await _run(_refresh, 'Package modules saved.');
  }

  Future<void> _publication(_Row package) async {
    final changed = await _edit(
      context,
      'Catalog listing for ${package['name']}',
      'Published plans appear in checkout. Use an HTTPS demo video and provide captions or a transcript for the plan.',
      [
        _Field(
          'description',
          'Description',
          initial: package['description'] as String? ?? '',
          lines: 3,
          required: false,
        ),
        _Field(
          'features',
          'Features, one per line',
          initial: (package['features'] as List?)?.join('\n') ?? '',
          lines: 4,
          required: false,
        ),
        _Field(
          'term',
          'Term in days',
          initial: '${package['term_days'] ?? 30}',
        ),
        _Field(
          'demo',
          'HTTPS demo video URL',
          initial: package['demo_url'] as String? ?? '',
          required: false,
        ),
        _Field(
          'transcript',
          'Demo captions or transcript',
          initial: package['demo_transcript'] as String? ?? '',
          lines: 4,
          required: false,
        ),
        _Field(
          'published',
          'Catalog status',
          initial: package['published'] == true ? 'published' : 'hidden',
          choices: const {'hidden': 'Hidden', 'published': 'Published'},
        ),
      ],
      (values) async {
        final term = int.tryParse(values['term']!);
        if (term == null || term < 1) {
          throw const PlatformOrganizationFailure('INVALID_SUBSCRIPTION_TERM');
        }
        await _gateway.rpc<Object?>('platform_save_subscription_publication', {
          'p_plan_code': package['code'],
          'p_expected_revision': package['revision'],
          'p_description': values['description'],
          'p_features': values['features']!
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList(),
          'p_demo_url': values['demo'],
          'p_demo_transcript': values['transcript'],
          'p_term_days': term,
          'p_published': values['published'] == 'published',
        });
      },
    );
    if (mounted && changed) await _run(_refresh, 'Catalog listing saved.');
  }

  Future<void> _offer({required bool withdraw}) async {
    final packages = {
      for (final row in _packages.where(_availablePackage)) row['code']: row,
    };
    final targets = <_Row>[];
    final currencies = <String>{};
    for (final organization in _selection.values) {
      final plan = packages[organization['plan_code']];
      if (plan == null) {
        _notice(context, 'Select organizations on active, priced packages.');
        return;
      }
      targets.add({
        'tenant_id': organization['id'],
        'plan_code': plan['code'],
        'revision': plan['revision'],
      });
      currencies.add(plan['currency_code'] as String);
    }
    final currency = currencies.length == 1 ? currencies.single : null;
    final changed = await _edit(
      context,
      withdraw ? 'Withdraw offer' : 'Apply offer',
      '${targets.length} selected organization(s).'
      '${!withdraw && currency == null ? ' The selected packages use different currencies. You can apply a free offer to all.' : ''}',
      [
        if (!withdraw) ...[
          if (currency != null)
            _Field('price', 'Offer price ($currency)', initial: '0'),
          const _Field(
            'expires',
            'Expires on (YYYY-MM-DD, end of UTC day)',
            required: false,
          ),
        ],
        const _Field('reason', 'Reason'),
      ],
      (values) async {
        final expires = values['expires'];
        String? expiresAt;
        if (expires != null && expires.isNotEmpty) {
          final date = DateTime.tryParse('${expires}T00:00:00Z');
          if (date == null ||
              date.toIso8601String().substring(0, 10) != expires) {
            throw const PlatformOrganizationFailure('INVALID_DATE');
          }
          expiresAt = date.add(const Duration(days: 1)).toIso8601String();
        }
        await _gateway.rpc<int>('platform_apply_organization_offer', {
          'p_targets': targets,
          'p_currency_code': currency,
          'p_price_minor': withdraw
              ? null
              : currency == null
              ? 0
              : _minor(values['price']!, currency),
          'p_expires_at': expiresAt,
          'p_reason': values['reason'],
        });
      },
      submit: withdraw ? 'Withdraw' : 'Apply to selected',
    );
    if (mounted && changed) {
      setState(_selection.clear);
      await _run(
        _refresh,
        'Offer updated for ${targets.length} organization(s).',
      );
    }
  }

  void _find() {
    _offset = 0;
    _run(_refresh);
  }

  void _page(int direction) {
    _offset += direction * 50;
    _run(_refresh);
  }

  Future<void> _downloadDeletedArchive(_Row row) => _run(() async {
    final saved = await _gateway.downloadArchive(
      tenantId: row['tenant_id'] as String,
      backupId: row['backup_id'] as String,
      organizationSlug: 'organization-${row['tenant_id']}',
      expectedSha256: row['sha256'] as String,
    );
    if (saved && mounted) _notice(context, 'Verified backup saved.');
  });

  void _go(_Section section) => setState(() => _section = section);

  Future<void> _newSystem(BuildContext context) async {
    await _createSystem(context, _gateway, _packages);
    if (mounted) await _run(_refresh);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final extended = constraints.maxWidth >= 1100;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: extended ? 248 : 88,
            child: Material(
              color: JentraColors.panel,
              // Scrolls when the window is short; otherwise the account
              // block stays pinned to the bottom of the sidebar.
              child: CustomScrollView(
                key: const ValueKey('jpanel-navigation'),
                slivers: [
                  SliverList.list(children: _sidebar(context, extended)),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: widget.standalone && widget.foundation != null
                          ? _account(context, widget.foundation!, extended)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 3,
                  child: _busy ? const LinearProgressIndicator() : null,
                ),
                Expanded(child: _sectionPage(context)),
              ],
            ),
          ),
        ],
      );
    },
  );

  List<Widget> _sidebar(BuildContext context, bool extended) {
    final text = Theme.of(context).textTheme;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(
          extended ? JentraSpacing.x5 : JentraSpacing.x2,
          JentraSpacing.x5,
          JentraSpacing.x4,
          JentraSpacing.x5,
        ),
        child: extended
            ? Row(
                children: [
                  const JentraBrandMark(size: 36),
                  const SizedBox(width: JentraSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'J panel',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Jentra OS control panel',
                          style: text.bodySmall?.copyWith(
                            color: JentraColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const Center(
                child: JentraBrandMark(size: 36, semanticsLabel: 'J panel'),
              ),
      ),
      for (final section in _Section.values)
        _destination(context, section, extended),
    ];
  }

  Widget _destination(BuildContext context, _Section section, bool extended) {
    final selected = section == _section;
    final color = selected
        ? JentraColors.actionBlue
        : JentraColors.textSecondary;
    final icon = _railIcon(
      section,
      selected ? section.selectedIcon : section.icon,
      color,
    );
    final label = Text(
      section.label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected ? JentraColors.textPrimary : JentraColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: extended ? 14 : 11,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: JentraSpacing.x2,
        vertical: 2,
      ),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? JentraColors.infoSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _go(section),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: extended ? JentraSpacing.x3 : JentraSpacing.x1,
                vertical: extended ? JentraSpacing.x3 : JentraSpacing.x2,
              ),
              child: extended
                  ? Row(
                      children: [
                        icon,
                        const SizedBox(width: JentraSpacing.x3),
                        Expanded(child: label),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(height: 2), label],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _railIcon(_Section section, IconData icon, Color color) =>
      section == _Section.archives && _cleanup.isNotEmpty
      ? Badge.count(
          count: _cleanup.length,
          child: Icon(icon, color: color),
        )
      : Icon(icon, color: color);

  Widget _account(
    BuildContext context,
    SupabaseFoundationGateway foundation,
    bool extended,
  ) {
    final email = foundation.currentUser?.email ?? 'Platform operator';
    Future<void> security() => showOperatorSecurityDialog(
      context,
      foundation: foundation,
      gateway: _gateway,
    );
    Future<void> signOut() async {
      try {
        await foundation.signOut();
      } on Object {
        if (context.mounted) _notice(context, 'Could not sign out. Try again.');
      }
    }

    return Padding(
      padding: const EdgeInsets.all(JentraSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          if (extended) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JentraSpacing.x2,
                vertical: JentraSpacing.x2,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: JentraColors.infoSurface,
                    child: Text(
                      email.characters.first.toUpperCase(),
                      style: const TextStyle(color: JentraColors.info),
                    ),
                  ),
                  const SizedBox(width: JentraSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'Platform operator',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: JentraColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Account security',
              child: TextButton.icon(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: security,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Password & recovery'),
              ),
            ),
            Tooltip(
              message: 'Sign out',
              child: TextButton.icon(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Account security',
              onPressed: security,
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: signOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionPage(BuildContext context) {
    final (title, description, actions, body) = switch (_section) {
      _Section.overview => (
        'Overview',
        'A summary of every Jentra OS system you manage.',
        <Widget>[_refreshButton()],
        _overview(context),
      ),
      _Section.organizations => (
        'Organizations',
        'Customer systems on Jentra OS. Open one to manage its package, administrators, lock and backups.',
        <Widget>[_newSystemButton(context), _refreshButton()],
        _organizationsSection(context),
      ),
      _Section.packages => (
        'Packages',
        'Subscription packages, their modules and how they appear in checkout.',
        <Widget>[
          FilledButton.icon(
            onPressed: _busy || _packages.isEmpty ? null : () => _package(),
            icon: const Icon(Icons.add),
            label: const Text('Create package'),
          ),
          _refreshButton(),
        ],
        _packagesSection(context),
      ),
      _Section.subscriptions => (
        'Subscriptions',
        'Checkout orders, payment verification and handover of new systems.',
        const <Widget>[],
        <Widget>[_SubscriptionControl(gateway: _gateway)],
      ),
      _Section.archives => (
        'Archives',
        'Account cleanup for purged organizations and their retained encrypted archives.',
        <Widget>[_refreshButton()],
        _archivesSection(context),
      ),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            JentraSpacing.x8,
            JentraSpacing.x6,
            JentraSpacing.x8,
            JentraSpacing.x10,
          ),
          children: [
            JentraSectionHeader(
              title: title,
              description: description,
              trailing: actions.isEmpty
                  ? null
                  : Wrap(
                      spacing: JentraSpacing.x2,
                      runSpacing: JentraSpacing.x2,
                      children: actions,
                    ),
            ),
            const SizedBox(height: JentraSpacing.x5),
            if (_error != null) ...[
              _Problem(_error!),
              const SizedBox(height: JentraSpacing.x4),
            ],
            ...body,
          ],
        ),
      ),
    );
  }

  Widget _refreshButton() => OutlinedButton.icon(
    onPressed: _busy ? null : () => _run(_refresh),
    icon: const Icon(Icons.refresh),
    label: const Text('Refresh'),
  );

  Widget _newSystemButton(BuildContext context) => FilledButton.icon(
    onPressed: _busy ? null : () => _newSystem(context),
    icon: const Icon(Icons.add_business_outlined),
    label: const Text('Create New System'),
  );

  List<Widget> _overview(BuildContext context) {
    final shown = _organizations.take(50).toList();
    final more = _organizations.length > 50 || _offset > 0;
    final active = shown.where((row) => row['status'] == 'active').length;
    final trial = shown.where((row) => row['status'] == 'trial').length;
    final awaiting = shown
        .where((row) => _organizationState(row) == 'Awaiting activation')
        .length;
    final livePackages = _packages
        .where((row) => row['status'] == 'active')
        .length;
    final published = _packages.where((row) => row['published'] == true).length;
    Widget kpi(JentraKpiCard card) => SizedBox(width: 248, child: card);
    return [
      Wrap(
        spacing: JentraSpacing.x4,
        runSpacing: JentraSpacing.x4,
        children: [
          kpi(
            JentraKpiCard(
              label: 'Organizations',
              value: '${shown.length}${more ? '+' : ''}',
              helper: more ? 'Showing the first 50' : 'All customer systems',
              icon: Icons.apartment_outlined,
              tone: JentraStatusTone.info,
            ),
          ),
          kpi(
            JentraKpiCard(
              label: 'Active',
              value: '$active',
              helper: 'Paid or activated systems',
              icon: Icons.check_circle_outline,
              tone: JentraStatusTone.success,
            ),
          ),
          kpi(
            JentraKpiCard(
              label: 'On trial',
              value: '$trial',
              helper: awaiting == 0
                  ? 'No trials waiting'
                  : '$awaiting awaiting activation',
              icon: Icons.hourglass_bottom,
              tone: awaiting == 0
                  ? JentraStatusTone.neutral
                  : JentraStatusTone.warning,
            ),
          ),
          kpi(
            JentraKpiCard(
              label: 'Active packages',
              value: '$livePackages',
              helper: '$published shown in checkout',
              icon: Icons.inventory_2_outlined,
            ),
          ),
          if (_cleanup.isNotEmpty)
            kpi(
              JentraKpiCard(
                label: 'Needs attention',
                value: '${_cleanup.length}',
                helper: 'Account cleanup to resume',
                icon: Icons.warning_amber_outlined,
                tone: JentraStatusTone.warning,
              ),
            ),
        ],
      ),
      const SizedBox(height: JentraSpacing.x6),
      JentraPanel(
        padding: const EdgeInsets.all(JentraSpacing.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: JentraSpacing.x3),
            Wrap(
              spacing: JentraSpacing.x3,
              runSpacing: JentraSpacing.x3,
              children: [
                _newSystemButton(context),
                OutlinedButton.icon(
                  onPressed: () => _go(_Section.subscriptions),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Review subscription orders'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _go(_Section.packages),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Manage packages'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _go(_Section.organizations),
                  icon: const Icon(Icons.search),
                  label: const Text('Find an organization'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: JentraSpacing.x6),
      Row(
        children: [
          Expanded(
            child: Text(
              'Recent organizations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (shown.isNotEmpty)
            TextButton(
              onPressed: () => _go(_Section.organizations),
              child: const Text('View all'),
            ),
        ],
      ),
      const SizedBox(height: JentraSpacing.x2),
      if (shown.isEmpty && !_busy)
        JentraEmptyState(
          title: 'No organizations yet',
          description: 'Create the first customer system. Its administrator gets a username and a temporary password.',
          icon: Icons.apartment_outlined,
          action: _newSystemButton(context),
        )
      else
        for (final row in shown.take(5))
          _organizationTile(context, row, selectable: false),
    ];
  }

  bool _matchesFilter(_Row row) => switch (_filter) {
    _StatusFilter.all => true,
    _StatusFilter.active => row['status'] == 'active',
    _StatusFilter.trial => row['status'] == 'trial',
    _StatusFilter.other => !['active', 'trial'].contains(row['status']),
  };

  List<Widget> _organizationsSection(BuildContext context) {
    final rows = _organizations.take(50).where(_matchesFilter).toList();
    return [
      TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onSubmitted: _busy ? null : (_) => _find(),
        decoration: InputDecoration(
          labelText: 'Find by organization name or ID',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'Search organizations',
            onPressed: _busy ? null : _find,
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
      ),
      const SizedBox(height: JentraSpacing.x3),
      Wrap(
        spacing: JentraSpacing.x2,
        runSpacing: JentraSpacing.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (filter, label) in const [
            (_StatusFilter.all, 'All'),
            (_StatusFilter.active, 'Active'),
            (_StatusFilter.trial, 'Trial'),
            (_StatusFilter.other, 'Locked or other'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _filter == filter,
              onSelected: (_) => setState(() => _filter = filter),
            ),
        ],
      ),
      const SizedBox(height: JentraSpacing.x3),
      if (_selection.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: JentraSpacing.x3),
          child: Material(
            color: JentraColors.infoSurface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JentraSpacing.x4,
                vertical: JentraSpacing.x2,
              ),
              child: Wrap(
                spacing: JentraSpacing.x3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${_selection.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _offer(withdraw: false),
                    child: const Text('Apply offer'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _offer(withdraw: true),
                    child: const Text('Withdraw offer'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(_selection.clear),
                    child: const Text('Clear selection'),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (!_busy && rows.isEmpty && _error == null)
        JentraEmptyState(
          title: _organizations.isEmpty
              ? 'No organizations found'
              : 'No organizations match this filter',
          description: _search.text.trim().isNotEmpty
              ? 'Check the name or ID, or clear the search.'
              : 'Create a system, or choose another status filter.',
          icon: Icons.apartment_outlined,
          action: _organizations.isEmpty ? _newSystemButton(context) : null,
        ),
      for (final row in rows) _organizationTile(context, row),
      if (_offset > 0 || _organizations.length > 50)
        Padding(
          padding: const EdgeInsets.only(top: JentraSpacing.x3),
          child: Wrap(
            spacing: JentraSpacing.x3,
            children: [
              OutlinedButton(
                onPressed: _busy || _offset == 0 ? null : () => _page(-1),
                child: const Text('Previous 50'),
              ),
              OutlinedButton(
                onPressed: _busy || _organizations.length <= 50
                    ? null
                    : () => _page(1),
                child: const Text('Next 50'),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _organizationTile(
    BuildContext context,
    _Row row, {
    bool selectable = true,
  }) {
    final state = _organizationState(row);
    final details = [
      if (row['system_serial'] != null) row['system_serial'],
      row['slug'],
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: JentraSpacing.x2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JentraSpacing.x4,
          vertical: JentraSpacing.x1,
        ),
        leading: selectable
            ? Checkbox(
                semanticLabel: 'Select ${row['name']} for a package offer',
                value: _selection.containsKey(row['id']),
                onChanged: _busy || !['active', 'trial'].contains(row['status'])
                    ? null
                    : (selected) => setState(() {
                        final id = row['id'] as String;
                        if (selected == true && _selection.length < 50) {
                          _selection[id] = row;
                        } else if (selected == false) {
                          _selection.remove(id);
                        }
                      }),
              )
            : const CircleAvatar(
                backgroundColor: JentraColors.neutralSurface,
                child: Icon(Icons.apartment, color: JentraColors.textSecondary),
              ),
        title: Text(
          row['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(details),
        trailing: Wrap(
          spacing: JentraSpacing.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              row['plan_code'] as String? ?? 'No package',
              style: const TextStyle(color: JentraColors.textSecondary),
            ),
            if (row['offer_minor'] != null)
              JentraStatusBadge(
                label:
                    'Offer ${_price(row['offer_minor'], row['offer_currency_code'])}',
                tone: JentraStatusTone.info,
                icon: Icons.local_offer_outlined,
              ),
            JentraStatusBadge(
              label: _stateLabel(state),
              tone: _stateTone(state),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: _busy
            ? null
            : () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => _OrganizationDetails(
                    gateway: _gateway,
                    organization: row,
                  ),
                );
                if (mounted) await _run(_refresh);
              },
      ),
    );
  }

  List<Widget> _packagesSection(BuildContext context) => [
    if (!_busy && _packages.isEmpty && _error == null)
      const JentraEmptyState(
        title: 'No packages',
        description: 'Packages come from the billing setup. Refresh after a package is added.',
        icon: Icons.inventory_2_outlined,
      ),
    for (final row in _packages)
      Card(
        margin: const EdgeInsets.only(bottom: JentraSpacing.x2),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: JentraSpacing.x4,
            vertical: JentraSpacing.x1,
          ),
          leading: const CircleAvatar(
            backgroundColor: JentraColors.infoSurface,
            child: Icon(Icons.inventory_2_outlined, color: JentraColors.info),
          ),
          title: Text(
            row['name'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${row['code']} · ${_price(row['price_minor'], row['currency_code'])}'
            '${row['trial_days'] == null ? '' : ' · ${row['trial_days']}-day trial'}',
          ),
          trailing: Wrap(
            spacing: JentraSpacing.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              JentraStatusBadge(
                label: row['status'] == 'active' ? 'Active' : 'Retired',
                tone: row['status'] == 'active'
                    ? JentraStatusTone.success
                    : JentraStatusTone.neutral,
              ),
              JentraStatusBadge(
                label: row['published'] == true ? 'In checkout' : 'Hidden',
                tone: row['published'] == true
                    ? JentraStatusTone.info
                    : JentraStatusTone.neutral,
              ),
              IconButton(
                onPressed: _busy ? null : () => _modules(row),
                tooltip: 'Edit modules',
                icon: const Icon(Icons.extension_outlined),
              ),
              IconButton(
                onPressed: _busy ? null : () => _publication(row),
                tooltip: 'Edit catalog listing',
                icon: const Icon(Icons.storefront_outlined),
              ),
              IconButton(
                onPressed: _busy ? null : () => _package(row),
                tooltip: 'Edit package',
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          onTap: _busy ? null : () => _package(row),
        ),
      ),
  ];

  List<Widget> _archivesSection(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return [
      if (_cleanup.isEmpty && _archives.isEmpty && !_busy && _error == null)
        const JentraEmptyState(
          title: 'Nothing archived',
          description: 'When an organization is backed up and purged, its encrypted archive appears here.',
          icon: Icons.archive_outlined,
        ),
      if (_cleanup.isNotEmpty) ...[
        Text('Pending account cleanup', style: title),
        const SizedBox(height: JentraSpacing.x2),
        for (final row in _cleanup)
          Card(
            margin: const EdgeInsets.only(bottom: JentraSpacing.x2),
            child: ListTile(
              leading: const Icon(
                Icons.warning_amber_outlined,
                color: JentraColors.warning,
              ),
              title: Text('Organization ${row['tenant_id']}'),
              subtitle: const Text(
                'The organization was purged. Its account cleanup can be resumed.',
              ),
              trailing: FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await _gateway.lifecycle('finish_cleanup', {
                          'tenant_id': row['tenant_id'],
                          'backup_id': row['backup_id'],
                        });
                        await _refresh();
                      }, 'Account cleanup completed.'),
                child: const Text('Resume'),
              ),
            ),
          ),
        const SizedBox(height: JentraSpacing.x5),
      ],
      if (_archives.isNotEmpty) ...[
        Text('Archives of deleted organizations', style: title),
        const SizedBox(height: JentraSpacing.x2),
        for (final row in _archives)
          Card(
            margin: const EdgeInsets.only(bottom: JentraSpacing.x2),
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text('Organization ${row['tenant_id']}'),
              subtitle: Text(
                'Deleted ${_date(row['deleted_at'])} · ${row['bytes']} bytes',
              ),
              trailing: IconButton(
                tooltip: 'Download verified archive',
                icon: const Icon(Icons.download),
                onPressed: _busy ? null : () => _downloadDeletedArchive(row),
              ),
            ),
          ),
      ],
    ];
  }
}

String _stateLabel(String state) =>
    state.isEmpty ? state : state[0].toUpperCase() + state.substring(1);

JentraStatusTone _stateTone(String state) => switch (state) {
  'active' => JentraStatusTone.success,
  'trial' => JentraStatusTone.info,
  'Awaiting activation' => JentraStatusTone.warning,
  'locked' || 'suspended' || 'deleting' => JentraStatusTone.danger,
  _ => JentraStatusTone.neutral,
};

class _OrganizationDetails extends StatefulWidget {
  const _OrganizationDetails({
    required this.gateway,
    required this.organization,
  });

  final PlatformOrganizationGateway gateway;
  final _Row organization;

  @override
  State<_OrganizationDetails> createState() => _OrganizationDetailsState();
}

class _OrganizationDetailsState extends State<_OrganizationDetails> {
  late _Row _organization = widget.organization;
  List<_Row> _admins = [];
  List<_Row> _activity = [];
  List<_Row> _backups = [];
  String? _purgeBackupId;
  String? _error;
  bool _busy = false;
  bool _locked = false;

  PlatformOrganizationGateway get _gateway => widget.gateway;
  String get _id => _organization['id'] as String;
  String get _slug => _organization['slug'] as String;

  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final data = await Future.wait([
      _gateway.rpc<List<dynamic>>('platform_list_organizations', {
        'p_tenant_id': _id,
      }),
      _gateway.rpc<Map<String, dynamic>>('platform_organization_activity', {
        'p_tenant_id': _id,
      }),
      _gateway.rpc<Map<String, dynamic>>('platform_organization_backups', {
        'p_tenant_id': _id,
      }),
    ]);
    if (!mounted) return;
    final organization = (data[0] as List)
        .map(_row)
        .where((row) => row['id'] == _id)
        .firstOrNull;
    if (organization == null) {
      throw const PlatformOrganizationFailure('ORGANIZATION_UNAVAILABLE');
    }
    final activity = _row(data[1]);
    final backups = _row(data[2]);
    setState(() {
      _organization = organization;
      _admins = _rows(activity['administrators']);
      _activity = _rows(activity['recent_activity']);
      _backups = _rows(backups['backups']);
      _locked = backups['locked'] == true;
      _purgeBackupId = backups['purge_backup_id'] as String?;
    });
  }

  Future<void> _administrator({bool activate = false, _Row? existing}) async {
    final storedEmail = _organization['signup_email'] as String?;
    final primary = activate || (existing == null && _admins.isEmpty);
    final paid = _organization['price_minor'] as int?;
    final currency = _organization['price_currency_code'] as String?;
    final assignedEmail = primary ? storedEmail : null;
    final intro = activate
        ? 'Confirm ${_price(paid, currency)} and email the credentials to the signup address.'
        : existing != null
        ? 'This rotates the credential and emails a new temporary password to the account’s recovery or original signup address.'
        : 'A temporary password will be emailed to the address below. The administrator will choose a new password at sign-in.';
    final changed = await _edit(
      context,
      activate
          ? 'Confirm activation and send credentials'
          : existing == null
          ? 'Add administrator'
          : 'Reissue temporary password',
      intro,
      [
        if (existing == null)
          _Field(
            'name',
            'Name',
            initial: _organization['name'] as String? ?? '',
          ),
        if (existing == null) const _Field('username', 'Username'),
        const _Field('password', 'Temporary password', secret: true),
        const _Field('confirm_password', 'Confirm password', secret: true),
        if (existing == null)
          _Field(
            'email',
            'Signup email',
            initial: assignedEmail ?? '',
            readOnly: assignedEmail != null,
            email: true,
          ),
        if (activate && paid != null && paid > 0)
          const _Field(
            'payment_reference',
            'Confirmed external payment reference',
          ),
      ],
      (values) async {
        final password = values['password']!;
        final username =
            existing?['username'] ??
            organizationUsername(values['username'] ?? '');
        final email = values['email'];
        if (!isOrganizationPassword(password)) {
          throw const PlatformOrganizationFailure('TEMPORARY_PASSWORD_LENGTH');
        }
        if (values['confirm_password'] != password) {
          throw const PlatformOrganizationFailure('PASSWORD_MISMATCH');
        }
        if (existing == null &&
            (username is! String ||
                !RegExp(r'^[a-z0-9][a-z0-9._-]{2,47}$').hasMatch(username) ||
                username.endsWith('.') ||
                username.contains('..'))) {
          throw const PlatformOrganizationFailure('INVALID_USERNAME');
        }
        if (existing == null &&
            (email == null ||
                email.length > 254 ||
                !RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(email) ||
                email.toLowerCase().endsWith('@admin.jentra.invalid'))) {
          throw const PlatformOrganizationFailure('invalid_email');
        }
        if (activate) {
          await _gateway.rpc<Map<String, dynamic>>(
            'platform_confirm_organization_activation',
            {
              'p_tenant_id': _id,
              'p_signup_email': email,
              'p_payment_reference': values['payment_reference'],
              'p_expected_amount_minor': paid,
              'p_expected_currency_code': currency,
            },
          );
        }
        await _gateway.identity(
          existing == null ? 'provision_admin' : 'reissue_admin',
          {
            'tenant_id': _id,
            'username': username,
            'password': password,
            'confirm_password': values['confirm_password'],
            if (existing == null) 'name': values['name'],
            if (existing == null) 'signup_email': email,
          },
        );
      },
      submit: 'Send credentials',
    );
    if (!mounted) return;
    if (changed) _notice(context, 'Temporary credentials sent.');
    await _run(_refresh);
  }

  Future<void> _toggleLock() async {
    final locked = _locked;
    final changed = await _edit(
      context,
      locked ? 'Unlock organization' : 'Lock organization',
      locked
          ? 'Members will regain online access if the organization was previously active.'
          : 'This suspends online access to ${_organization['name']} for its members.',
      [const _Field('reason', 'Reason')],
      (values) async {
        await _gateway.rpc<Map<String, dynamic>>(
          'platform_set_organization_lock',
          {
            'p_tenant_id': _id,
            'p_locked': !locked,
            'p_reason': values['reason'],
          },
        );
      },
      submit: locked ? 'Unlock' : 'Lock',
    );
    if (mounted && changed) await _run(_refresh);
  }

  Future<void> _rename() async {
    final changed = await _edit(
      context,
      'Edit organization name',
      'The new display name will appear in the organization. Its existing login continues to work.',
      [
        _Field(
          'name',
          'Organization name',
          initial: _organization['name'] as String,
        ),
        const _Field('reason', 'Reason for change'),
      ],
      (values) async {
        await _gateway.rpc<Object?>(
          'platform_rename_subscription_organization',
          {
            'p_tenant_id': _id,
            'p_name': values['name'],
            'p_reason': values['reason'],
          },
        );
      },
    );
    if (mounted && changed) await _run(_refresh);
  }

  Future<void> _changePackage() async {
    Map<String, String> choices;
    try {
      final rows = await _gateway.rpc<List<dynamic>>('platform_list_packages');
      choices = _packageChoices(
        rows
            .map(_row)
            .where((r) => r['status'] == 'active' && r['price_minor'] != null),
      );
    } on Object {
      if (mounted) setState(() => _error = 'Could not load the packages.');
      return;
    }
    if (!mounted) return;
    final current = _organization['plan_code'] as String?;
    final changed = await _edit(
      context,
      'Change package',
      'The organization gets the modules of the new package at once. Its price, offers and recorded payments are not changed here.',
      [
        _Field(
          'package',
          'Package',
          initial: choices.containsKey(current) ? current! : '',
          choices: choices,
        ),
        const _Field('reason', 'Reason for change'),
      ],
      (values) async {
        await _gateway.rpc<Object?>('platform_set_organization_package', {
          'p_tenant_id': _id,
          'p_plan_code': values['package'],
          'p_reason': values['reason'],
        });
      },
    );
    if (mounted && changed) await _run(_refresh);
  }

  Future<void> _archive() => _run(() async {
    await _gateway.lifecycle('backup', {'tenant_id': _id});
    if (mounted) _notice(context, 'Backup created.');
    await _refresh();
  });

  Future<void> _download(_Row backup) => _run(() async {
    final saved = await _gateway.downloadArchive(
      tenantId: _id,
      backupId: backup['backup_id'] as String,
      organizationSlug: _slug,
      expectedSha256: backup['sha256'] as String,
    );
    if (mounted && saved) _notice(context, 'Verified backup saved.');
  });

  Future<void> _purge(_Row backup) async {
    final resumed = _purgeBackupId != null;
    final completed = await _edit(
      context,
      resumed ? 'Resume permanent deletion' : 'Permanently delete organization',
      'This removes ${_organization['name']} and its online data. The private archive is retained. '
      'Type the organization ID “$_slug” to continue.',
      [const _Field('slug', 'Confirm organization ID')],
      (values) async {
        if (values['slug'] != _slug) {
          throw const PlatformOrganizationFailure('CONFIRM_ORGANIZATION_ID');
        }
        await _gateway.lifecycle('purge', {
          'tenant_id': _id,
          'backup_id': backup['backup_id'],
          'confirmation_slug': _slug,
        });
      },
      submit: resumed ? 'Resume deletion' : 'Permanently delete',
      destructive: true,
    );
    if (!mounted) return;
    if (completed) {
      Navigator.pop(context);
    } else {
      await _run(_refresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = ['active', 'trial'].contains(_organization['status']);
    final activated = _organization['activated_at'] != null;
    final priced = _organization['price_minor'] != null;
    final title = Theme.of(context).textTheme.titleMedium;
    return AlertDialog(
      scrollable: true,
      title: Text(_organization['name'] as String),
      content: SizedBox(
        width: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) _Problem(_error!),
            Text('$_slug · ${_organizationState(_organization)}'),
            if (_organization['system_serial'] case final String serial)
              _SystemActions(
                gateway: _gateway,
                tenantId: _id,
                serial: serial,
                username: _organization['system_username'] as String?,
              ),
            Text('Package · ${_organization['plan_code'] ?? 'Unassigned'}'),
            if (activated)
              Text(
                'Activation recorded ${_date(_organization['activated_at'])} · '
                '${_price(_organization['paid_minor'], _organization['paid_currency_code'])}',
              ),
            if (_organization['term_ends_at'] != null)
              Text(
                '${_organization['term_expired'] == true ? 'Subscription expired' : 'Subscription ends'} · ${_date(_organization['term_ends_at'])}',
              ),
            if (priced)
              Text(
                'Current package price · ${_price(_organization['price_minor'], _organization['price_currency_code'])}',
              ),
            if (_organization['offer_minor'] != null)
              Text(
                _organization['offer_expires_at'] == null
                    ? 'Offer has no expiry'
                    : 'Offer ends ${_date(_organization['offer_expires_at'])}',
              ),
            if (_organization['signup_email'] != null)
              Text('Signup email · ${_organization['signup_email']}'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy || !available ? null : _rename,
                label: const Text('Edit organization name'),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy || !available ? null : _changePackage,
                label: const Text('Change package'),
                icon: const Icon(Icons.swap_horiz),
              ),
            ),
            const SizedBox(height: 16),
            Text('Administrators', style: title),
            if (_admins.isEmpty) const Text('No assigned username accounts.'),
            for (final admin in _admins)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(admin['username'] as String),
                subtitle: Text(
                  'Password updated ${_date(admin['password_changed_at'])}\n'
                  '${admin['status']} · '
                  '${admin['handover_sent_at'] == null ? 'Credentials not sent' : 'Credentials sent'}'
                  '${admin['must_change_password'] == true ? ' · Password change required' : ''}',
                ),
                trailing: admin['checkout_order_id'] != null
                    ? null
                    : TextButton(
                        onPressed:
                            _busy || !available || admin['status'] != 'active'
                            ? null
                            : () => _administrator(existing: admin),
                        child: const Text('Reissue'),
                      ),
              ),
            if (available &&
                (_organization['checkout_managed'] != true ||
                    _admins.isNotEmpty))
              Wrap(
                children: [
                  FilledButton(
                    onPressed: _busy || (!activated && !priced)
                        ? null
                        : () => _administrator(activate: !activated),
                    child: Text(
                      !activated
                          ? 'Confirm activation'
                          : _admins.isEmpty
                          ? 'Send first administrator credentials'
                          : 'Add administrator',
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Text('Access and backups', style: title),
            Wrap(
              spacing: 8,
              children: [
                if (available || _locked)
                  OutlinedButton(
                    onPressed: _busy || _purgeBackupId != null
                        ? null
                        : _toggleLock,
                    child: Text(_locked ? 'Unlock access' : 'Lock access'),
                  ),
                if (_locked)
                  OutlinedButton(
                    onPressed: _busy || _purgeBackupId != null
                        ? null
                        : _archive,
                    child: const Text('Create backup'),
                  ),
              ],
            ),
            for (final backup in _backups)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Backup · ${_date(backup['created_at'])}'),
                subtitle: Text(
                  '${backup['bytes']} bytes · ${backup['backup_id']}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      onPressed: _busy ? null : () => _download(backup),
                      tooltip: 'Download verified backup',
                      icon: const Icon(Icons.download),
                    ),
                    if (_locked &&
                        backup['deleted'] != true &&
                        (_purgeBackupId == backup['backup_id'] ||
                            (_purgeBackupId == null &&
                                backup['current'] == true)))
                      IconButton(
                        onPressed: _busy ? null : () => _purge(backup),
                        tooltip: _purgeBackupId == null
                            ? 'Permanently delete organization'
                            : 'Resume deletion',
                        color: Theme.of(context).colorScheme.error,
                        icon: const Icon(Icons.delete_forever_outlined),
                      ),
                  ],
                ),
              ),
            if (_activity.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Recent activity', style: title),
              for (final activity in _activity)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (activity['event_type'] as String)
                        .replaceFirst('organization.', '')
                        .replaceAll('_', ' '),
                  ),
                  subtitle: Text(_date(activity['occurred_at'])),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _run(_refresh),
          child: const Text('Refresh'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

String _usernameAlias(String value) {
  final username = organizationUsername(value);
  if (username.isEmpty) return 'The sign-in alias appears here.';
  return 'Supabase sign-in alias: $username@admin.jentra.invalid';
}

class _Field {
  const _Field(
    this.key,
    this.label, {
    this.initial = '',
    this.choices,
    this.required = true,
    this.readOnly = false,
    this.secret = false,
    this.email = false,
    this.lines = 1,
  });

  final String key;
  final String label;
  final String initial;
  final Map<String, String>? choices;
  final bool required;
  final bool readOnly;
  final bool secret;
  final bool email;
  final int lines;

  _Field filled(String? value) => _Field(key, label, initial: value ?? initial);
}

Future<bool> _edit(
  BuildContext context,
  String title,
  String description,
  List<_Field> fields,
  Future<void> Function(Map<String, String> values) save, {
  String submit = 'Save',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ActionDialog(
        title: title,
        description: description,
        fields: fields,
        save: save,
        submit: submit,
        destructive: destructive,
      ),
    ) ??
    false;

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.title,
    required this.description,
    required this.fields,
    required this.save,
    required this.submit,
    required this.destructive,
  });

  final String title;
  final String description;
  final List<_Field> fields;
  final Future<void> Function(Map<String, String>) save;
  final String submit;
  final bool destructive;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  final _form = GlobalKey<FormState>();
  late final _values = {
    for (final field in widget.fields)
      field.key: field.initial.isEmpty && field.choices != null
          ? field.choices!.keys.first
          : field.initial,
  };
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(_values);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      for (final field in widget.fields.where((field) => field.secret)) {
        _values[field.key] = '';
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.description),
              if (_error != null) _Problem(_error!),
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: field.choices == null
                      ? TextFormField(
                          initialValue: field.initial,
                          decoration: InputDecoration(
                            labelText: field.label,
                            helperText: field.key == 'username'
                                ? _usernameAlias(_values[field.key] ?? '')
                                : null,
                          ),
                          onChanged: field.key == 'username'
                              ? (value) =>
                                    setState(() => _values[field.key] = value)
                              : null,
                          enabled: !_busy,
                          readOnly: field.readOnly,
                          obscureText: field.secret,
                          maxLines: field.lines,
                          autocorrect: !field.secret,
                          enableSuggestions: !field.secret,
                          keyboardType: field.email
                              ? TextInputType.emailAddress
                              : null,
                          validator: (text) =>
                              field.required && (text?.trim().isEmpty ?? true)
                              ? 'Enter ${field.label.toLowerCase()}.'
                              : null,
                          onSaved: (value) => _values[field.key] = field.secret
                              ? value!
                              : value!.trim(),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: _values[field.key],
                          decoration: InputDecoration(labelText: field.label),
                          isExpanded: true,
                          items: [
                            for (final item in field.choices!.entries)
                              DropdownMenuItem(
                                value: item.key,
                                child: Text(item.value),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => _values[field.key] = value!,
                        ),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          child: Text(widget.submit),
        ),
      ],
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

_Row _row(Object? value) => (value as Map).cast<String, Object?>();
List<_Row> _rows(Object? value) => (value as List).map(_row).toList();
bool _availablePackage(_Row row) =>
    row['status'] == 'active' && row['price_minor'] != null;

/// Module switches an operator may change, in display order. Keep the codes
/// identical to billing.platform_module_codes().
const _moduleLabels = <String, String>{
  'module.people': 'People (HR)',
  'module.field_sales': 'Field Sales',
  'module.finance': 'Finance',
  'module.assets': 'Assets',
  'module.projects': 'Projects',
  'module.service': 'Service',
  'analytics': 'Analytics',
  'module.ai': 'AI',
};

Map<String, String> _packageChoices(Iterable<_Row> rows) => {
  for (final row in rows) row['code'] as String: row['name'] as String,
};

String _organizationState(_Row row) =>
    row['status'] == 'trial' &&
        row['activated_at'] == null &&
        row['signup_email'] != null
    ? 'Awaiting activation'
    : (row['status'] as String);

String _date(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return date == null
      ? 'Unavailable'
      : DateFormat.yMMMd().add_jm().format(date);
}

int _currencyDigits(String code) =>
    NumberFormat.currency(name: code).decimalDigits!;

String _decimal(int amount, String currency) {
  final digits = _currencyDigits(currency);
  if (digits == 0) return amount.toString();
  final padded = amount.toString().padLeft(digits + 1, '0');
  final split = padded.length - digits;
  return '${padded.substring(0, split)}.${padded.substring(split)}';
}

String _price(Object? minor, Object? code) => switch ((minor, code)) {
  (0, String _) => 'Free',
  (int amount, String currency) => '$currency ${_decimal(amount, currency)}',
  _ => 'Price not set',
};

int _minor(String value, String currency) {
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
      !RegExp(r'^\d{1,12}(\.\d{1,4})?$').hasMatch(value)) {
    throw const PlatformOrganizationFailure('INVALID_PRICE');
  }
  final digits = _currencyDigits(currency);
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts.last : '';
  if (fraction.length > digits) {
    throw const PlatformOrganizationFailure('INVALID_PRICE');
  }
  final amount = int.parse('${parts.first}${fraction.padRight(digits, '0')}');
  if (amount > 999999999999) {
    throw const PlatformOrganizationFailure('INVALID_PRICE');
  }
  return amount;
}

void _notice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

String _message(Object error) {
  final code = error is PlatformOrganizationFailure ? error.code : '';
  return switch (code) {
    'OPERATOR_ACCESS_REQUIRED' => 'Platform operator verification is required.',
    'ORGANIZATION_UNAVAILABLE' =>
      'This organization is unavailable. Refresh the panel.',
    'PACKAGE_PRICE_REQUIRED' =>
      'Set an active package price before continuing.',
    'PACKAGE_CHANGED' || 'ORGANIZATION_QUOTE_CHANGED' =>
      'Pricing changed. Close this form and refresh before confirming.',
    'SIGNUP_EMAIL_REQUIRED' => 'Use the registered signup email.',
    'INVALID_PAYMENT_CONFIRMATION' =>
      'Enter the confirmed external payment reference.',
    'DUPLICATE_RECORD' => 'An organization ID, package code or payment reference is already in use.',
    'OFFER_ORGANIZATIONS_CHANGED' => 'The selection changed. Clear it, refresh and select the organizations again.',
    'INVALID_OFFER_PACKAGE_OR_PRICE' => 'Refresh the package and enter an offer price at or below its current price.',
    'INVALID_OFFER' =>
      'Enter a valid date and a reason of 5 to 250 characters.',
    'INVALID_DATE' => 'Enter a valid date in YYYY-MM-DD format.',
    'INVALID_PRICE' =>
      'Enter a valid price using the currency’s allowed decimal places.',
    'INVALID_PACKAGE' => 'Check the package code, name, price and trial days.',
    'INVALID_PACKAGE_MODULES' =>
      'The module list is out of date. Close this form and refresh.',
    'INVALID_PACKAGE_CHANGE' => 'Enter a reason of 5 to 500 characters.',
    'PACKAGE_UNAVAILABLE' => 'Choose an active package that has a price.',
    'INVALID_CHECKOUT_ENFORCEMENT' => 'Enter a reason of 5 to 500 characters.',
    'INVALID_SUBSCRIPTION_TERM' => 'Enter the subscription term in whole days.',
    'INVALID_SUBSCRIPTION_PUBLICATION' => 'Publishing requires an active LKR plan, a description, features, an HTTPS demo and a transcript.',
    'SUBSCRIPTION_PAYMENT_NOT_MATCHED' => 'The amount, reference or transfer time does not match this order. Use Reject or record exception to record the transfer.',
    'SUBSCRIPTION_REJECTION_REASON_REQUIRED' =>
      'Enter a rejection reason of 5 to 500 characters.',
    'SUBSCRIPTION_ORDER_NOT_REVIEWABLE' =>
      'The order has changed. Close the form and refresh the queue.',
    'INVALID_TRANSFER_DATE' =>
      'Enter a real transfer date and time in the indicated Sri Lanka format.',
    'INVALID_ORGANIZATION' =>
      'Check the organization name, ID, signup email, currency and time zone.',
    'TEMPORARY_PASSWORD_LENGTH' || 'weak_password' => 'Enter at least 12 characters, including uppercase and lowercase letters and a number. The password must fit within 72 bytes.',
    'PASSWORD_MISMATCH' => 'The passwords must match.',
    'handover_failed' => 'Email delivery failed. Close this form and use Reissue on the administrator after one minute.',
    'try_again_later' => 'Wait one minute before reissuing credentials.',
    'username_unavailable' => 'This username is already in use.',
    'INVALID_USERNAME' =>
      'Use 3 to 48 lowercase letters, numbers, dots, underscores or hyphens.',
    'invalid_email' => 'Enter a valid signup email address.',
    'delivery_unavailable' => 'Email delivery is unavailable. Retry after the delivery service is available.',
    'handover_unavailable' =>
      'Set a verified recovery address before reissuing these credentials.',
    'CONFIRM_ORGANIZATION_ID' => 'Enter the exact organization ID shown above.',
    'ORGANIZATION_BACKUP_STALE' =>
      'Create a new backup for the current lock before deleting.',
    'BACKUP_CHECKSUM_MISMATCH' || 'INVALID_BACKUP_CONTENT' =>
      'The downloaded archive did not match its receipt.',
    _ => 'The action could not be completed. Refresh to check its current status before retrying.',
  };
}
