import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

// Assignment alone allows the entry point to be shown before verification.
// Every organization operation checks both assignment and AAL2 at the server.
final platformOrganizationAccessProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  ref.watch(authSessionRevisionProvider);
  final gateway = ref.watch(platformOrganizationGatewayProvider);
  final user = ref.watch(foundationGatewayProvider)?.currentUser;
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

class _ControlPanel extends StatefulWidget {
  const _ControlPanel({required this.gateway, super.key});

  final PlatformOrganizationGateway gateway;

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
  bool _showOrders = true;
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

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Subscriptions')),
                ButtonSegment(
                  value: false,
                  label: Text('Organizations & plans'),
                ),
              ],
              selected: {_showOrders},
              onSelectionChanged: (values) =>
                  setState(() => _showOrders = values.single),
            ),
          ),
          Expanded(
            child: _showOrders
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [_SubscriptionControl(gateway: _gateway)],
                  )
                : _management(context),
          ),
        ],
      ),
    ),
  );

  Widget _management(BuildContext context) {
    final title = Theme.of(context).textTheme.titleLarge;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) _Problem(_error!),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Systems', style: title),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await _createSystem(context, _gateway, _packages);
                      if (mounted) await _run(_refresh);
                    },
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Create New System'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _run(_refresh),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: _busy ? null : (_) => _find(),
          decoration: InputDecoration(
            labelText: 'Find by organization name or ID',
            suffixIcon: IconButton(
              tooltip: 'Search organizations',
              onPressed: _busy ? null : _find,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        if (_selection.isNotEmpty)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${_selection.length} selected'),
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
        if (!_busy && _organizations.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No organizations found.'),
          ),
        for (final row in _organizations.take(50))
          Card(
            child: ListTile(
              leading: Checkbox(
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
              ),
              title: Text(row['name'] as String),
              subtitle: Text(
                '${row['system_serial'] == null ? '' : "${row['system_serial']} · "}'
                '${row['slug']} · ${_organizationState(row)} · ${row['plan_code'] ?? 'No package'}'
                '${row['offer_minor'] == null ? '' : ' · Offer ${_price(row['offer_minor'], row['offer_currency_code'])}'}',
              ),
              trailing: const Icon(Icons.chevron_right),
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
          ),
        if (_offset > 0 || _organizations.length > 50)
          Wrap(
            spacing: 12,
            children: [
              TextButton(
                onPressed: _busy || _offset == 0 ? null : () => _page(-1),
                child: const Text('Previous 50'),
              ),
              TextButton(
                onPressed: _busy || _organizations.length <= 50
                    ? null
                    : () => _page(1),
                child: const Text('Next 50'),
              ),
            ],
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Subscription packages', style: title),
            OutlinedButton.icon(
              onPressed: _busy || _packages.isEmpty ? null : () => _package(),
              icon: const Icon(Icons.add),
              label: const Text('Create package'),
            ),
          ],
        ),
        for (final row in _packages)
          ListTile(
            title: Text(row['name'] as String),
            subtitle: Text(
              '${row['code']} · ${row['status']} · ${_price(row['price_minor'], row['currency_code'])}'
              '${row['published'] == true ? ' · Published' : ''}',
            ),
            trailing: IconButton(
              onPressed: _busy ? null : () => _publication(row),
              tooltip: 'Edit catalog listing',
              icon: const Icon(Icons.video_library_outlined),
            ),
            onTap: _busy ? null : () => _package(row),
          ),
        if (_cleanup.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Pending account cleanup', style: title),
          for (final row in _cleanup)
            ListTile(
              title: Text('Organization ${row['tenant_id']}'),
              subtitle: const Text(
                'The organization was purged. Its account cleanup can be resumed.',
              ),
              trailing: OutlinedButton(
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
        ],
        if (_archives.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Archives of deleted organizations', style: title),
          for (final row in _archives)
            ListTile(
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
        ],
      ],
    );
  }
}

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
