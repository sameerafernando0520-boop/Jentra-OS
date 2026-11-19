import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../auth/account_security_screen.dart';
import '../platform_control/platform_organization_screen.dart';
import '../tenant/stock_opening_access.dart';
import 'demo_player.dart';
import 'subscription_access.dart';

final _plans = FutureProvider.autoDispose((ref) async {
  final gateway = ref.watch(platformOrganizationGatewayProvider);
  ref.watch(authenticatedActorProvider);
  return subscriptionRows(await gateway?.rpc('subscription_checkout_catalog'));
}, retry: (_, _) => null);

final _orders = FutureProvider.autoDispose
    .family<List<SubscriptionRow>, String>((ref, actorId) async {
      final gateway = ref.watch(platformOrganizationGatewayProvider);
      if (ref.watch(foundationGatewayProvider)?.currentUser?.id != actorId) {
        return const [];
      }
      return subscriptionRows(
        await gateway?.rpc('subscription_checkout_orders'),
      );
    }, retry: (_, _) => null);

String _price(Object? minor) => NumberFormat.currency(
  name: 'LKR',
  symbol: 'LKR ',
  decimalDigits: 2,
).format((minor as num) / 100);

String _localTime(Object? value) {
  final date = value is String ? DateTime.tryParse(value)?.toLocal() : null;
  return date == null ? '—' : DateFormat.yMMMd().add_jm().format(date);
}

class SubscriptionCheckoutScreen extends ConsumerStatefulWidget {
  const SubscriptionCheckoutScreen({super.key});

  @override
  ConsumerState<SubscriptionCheckoutScreen> createState() =>
      _SubscriptionCheckoutScreenState();
}

class _SubscriptionCheckoutScreenState
    extends ConsumerState<SubscriptionCheckoutScreen> {
  final _code = TextEditingController();
  final _quoteIds = <(String, String?, String?), String>{};
  Timer? _refreshOrders;
  bool _codeSent = false;
  bool _busy = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _refreshOrders = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ref.read(subscriptionAccessProvider).value?.enabled == true) {
        ref.invalidate(_orders);
      }
    });
  }

  @override
  void dispose() {
    _refreshOrders?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(subscriptionAccessProvider);
    ref.invalidate(_plans);
    ref.invalidate(_orders);
  }

  Future<void> _run(
    Future<void> Function(PlatformOrganizationGateway) operation,
  ) async {
    final gateway = ref.read(platformOrganizationGatewayProvider);
    if (_busy || gateway == null) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await operation(gateway);
    } on PlatformOrganizationFailure catch (error) {
      if (mounted) {
        setState(() {
          _feedback = switch (error.code) {
            'invalid_code' => 'Enter the most recent code sent to your email.',
            'try_again_later' =>
              'Wait a moment before requesting another code.',
            'DUPLICATE_RECORD' => 'A matching order is already on file.',
            'SUBSCRIPTION_ORDER_OPEN' => 'A pending order already exists. Check your orders before requesting another quote.',
            'SUBSCRIPTION_PLAN_CHANGED' =>
              'The plan has changed. Refresh to review the current offer.',
            'SUBSCRIPTION_BANK_UNAVAILABLE' =>
              'Bank transfer is unavailable. Try again later.',
            _ => 'This action could not be completed. Refresh and try again.',
          };
        });
      }
    } on Exception {
      if (mounted) {
        setState(() => _feedback = 'Could not reach Jentra OS. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run((gateway) async {
    await gateway.identity('request_purchase_email_code', {});
    if (mounted) setState(() => _codeSent = true);
  });

  Future<void> _verifyCode() => _run((gateway) async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      setState(() => _feedback = 'Enter the eight-digit email code.');
      return;
    }
    await gateway.identity('verify_purchase_email_code', {'code': code});
    if (mounted) {
      _code.clear();
      _refresh();
    }
  });

  Future<void> _quote(SubscriptionRow plan, {SubscriptionRow? renewal}) async {
    final name = renewal == null
        ? await showDialog<String>(
            context: context,
            builder: (_) => const _CheckoutInput(isName: true),
          )
        : null;
    if (!mounted || (renewal == null && name == null)) return;
    final planCode = plan['code'] as String;
    final tenant = renewal?['tenant_id'] as String?;
    final key = (planCode, name, tenant);
    await _run((gateway) async {
      await gateway.rpc('subscription_create_order', {
        'p_plan_code': planCode,
        'p_expected_revision': plan['revision'],
        'p_organization_name': name,
        'p_request_id': _quoteIds.putIfAbsent(key, const Uuid().v4),
        'p_renewal_tenant_id': ?tenant,
      });
      if (mounted) {
        _quoteIds.remove(key);
        _refresh();
      }
    });
  }

  Future<void> _report(SubscriptionRow order) async {
    final reference = await showDialog<String>(
      context: context,
      builder: (_) => const _CheckoutInput(),
    );
    if (!mounted || reference == null) return;
    await _run((gateway) async {
      await gateway.rpc('subscription_submit_payment', {
        'p_order_id': order['id'],
        'p_transfer_reference': reference,
      });
      if (mounted) _refresh();
    });
  }

  Future<void> _reissue(SubscriptionRow order) => _run((gateway) async {
    await gateway.rpc('subscription_reissue_handover', {
      'p_order_id': order['id'],
    });
    if (mounted) {
      setState(() => _feedback = 'A new temporary password was requested.');
      _refresh();
    }
  });

  @override
  Widget build(BuildContext context) {
    final gateway = ref.watch(foundationGatewayProvider);
    final actor = gateway?.currentUser?.id;
    if (gateway?.usesManagedUsername == true && actor != null) {
      final profile = ref.watch(accountSecurityProfileProvider(actor));
      if (profile.value == null || profile.value?.mustChangePassword == true) {
        return const Scaffold(body: AccountSecurityScreen());
      }
    }
    final access = ref.watch(subscriptionAccessProvider);
    final state = access.value?.actorId == actor ? access.value : null;
    final canReturn =
        state != null && !state.requiresCheckout && !state.workspacePaused;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jentra OS · Subscriptions'),
        leading: canReturn
            ? BackButton(onPressed: () => context.go('/dashboard'))
            : null,
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: 'Refresh status',
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(foundationGatewayProvider)?.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_feedback case final message?) _notice(message),
                if (state != null)
                  ..._content(state)
                else if (access.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  _notice(
                    'Subscription access is unavailable. Try refreshing.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(SubscriptionAccess access) {
    final email = access.email;
    if (!access.enabled) {
      return [
        _notice(
          access.workspacePaused
              ? 'Your subscription has ended. Contact Jentra OS support for renewal.'
              : 'Subscription checkout is currently unavailable.',
        ),
        if (access.workspacePaused) _securityLink(),
      ];
    }
    final plans = ref.watch(_plans);
    final orders = ref.watch(_orders(access.actorId));
    return [
      if (access.workspacePaused) ...[
        _notice(
          'Workspace access is paused. Access resumes when renewal is confirmed.',
        ),
        _securityLink(),
      ],
      if (access.requiresCheckout) const StockOpeningInvitationInbox(),
      if (email != null && !access.emailVerified) _emailVerification(email),
      if (orders.isLoading && !orders.hasValue)
        const LinearProgressIndicator()
      else if (orders.hasError && (email == null || access.emailVerified))
        _notice('Orders could not be loaded. Try refreshing.')
      else if (orders.value case final items? when items.isNotEmpty) ...[
        _heading('Your orders'),
        for (final order in items)
          _OrderCard(
            order: order,
            report: _busy ? null : () => _report(order),
            reissue: _busy ? null : () => _reissue(order),
          ),
      ],
      if (access.renewable.isNotEmpty) ...[
        _heading('Renew a workspace'),
        for (final workspace in access.renewable)
          _renewalCard(workspace, plans.value ?? const []),
      ],
      if (email != null && access.emailVerified) ...[
        _heading('Choose a subscription plan'),
        if (plans.isLoading && !plans.hasValue)
          const LinearProgressIndicator()
        else if (plans.hasError)
          _notice('Plans could not be loaded. Try refreshing.')
        else if (plans.value?.isEmpty ?? true)
          const Text('There are no published plans available at the moment.')
        else
          for (final plan in plans.value!)
            _PlanCard(plan: plan, select: _busy ? null : () => _quote(plan)),
      ],
    ];
  }

  Widget _securityLink() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () => context.go('/account'),
      child: const Text('Account security'),
    ),
  );

  Widget _emailVerification(String email) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify your purchase email',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text('We’ll send a verification code to $email.'),
          const SizedBox(height: 12),
          if (_codeSent) ...[
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Eight-digit verification code',
              ),
              onSubmitted: _busy ? null : (_) => _verifyCode(),
            ),
            FilledButton(
              onPressed: _busy ? null : _verifyCode,
              child: const Text('Verify email'),
            ),
          ],
          OutlinedButton(
            onPressed: _busy ? null : _sendCode,
            child: Text(_codeSent ? 'Send a new code' : 'Email me a code'),
          ),
        ],
      ),
    ),
  );

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
  );

  Widget _renewalCard(SubscriptionRow workspace, List<SubscriptionRow> plans) {
    final plan = plans
        .where((plan) => plan['code'] == workspace['plan_code'])
        .firstOrNull;
    return Card(
      child: ListTile(
        title: Text(workspace['organization_name'] as String),
        subtitle: Text('Term ends ${_localTime(workspace['term_ends_at'])}'),
        trailing: OutlinedButton(
          onPressed: _busy || plan == null
              ? null
              : () => _quote(plan, renewal: workspace),
          child: const Text('Renew plan'),
        ),
      ),
    );
  }
}

Widget _notice(String text) => Card(
  child: ListTile(leading: const Icon(Icons.info_outline), title: Text(text)),
);

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.select});

  final SubscriptionRow plan;
  final VoidCallback? select;

  @override
  Widget build(BuildContext context) {
    final url = Uri.tryParse(plan['demo_url'] as String? ?? '');
    final transcript = plan['demo_transcript'] as String?;
    final features = (plan['features'] as List<dynamic>?) ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan['name'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${_price(plan['price_minor'])} for ${plan['term_days']} days',
            ),
            const SizedBox(height: 8),
            Text(plan['description'] as String? ?? ''),
            for (final feature in features) Text('• $feature'),
            const SizedBox(height: 16),
            if (url != null && url.scheme == 'https' && url.hasAuthority)
              SizedBox(width: 520, child: DemoPlayer(url: url)),
            if (transcript != null && transcript.isNotEmpty)
              ExpansionTile(
                title: const Text('Demo transcript'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(transcript),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            FilledButton(onPressed: select, child: const Text('Select plan')),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.report,
    required this.reissue,
  });

  final SubscriptionRow order;
  final VoidCallback? report;
  final VoidCallback? reissue;

  @override
  Widget build(BuildContext context) {
    final status = order['status'];
    final bank = order['bank'] as Map?;
    final handover = order['handover_status'];
    final received = order['transfer_reference'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${order['organization_name']} · ${order['plan_name']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${_price(order['price_minor'])} · ${order['term_days']} days',
            ),
            SelectableText('Order reference ${order['id']}'),
            const SizedBox(height: 8),
            Text(switch (status) {
              'awaiting_payment' => 'Waiting for bank transfer',
              'under_review' => 'Transfer submitted for review',
              'payment_rejected' => 'Payment needs attention. Contact Jentra OS support with your order reference.',
              'paid' => 'Order confirmed',
              'expired' => 'The payment window has ended.',
              'cancelled' => 'Order cancelled',
              _ => 'Order status unavailable',
            }),
            if (order['username'] case final String username)
              SelectableText('Username $username'),
            if (received != null) SelectableText('Bank reference $received'),
            if (order['term_ends_at'] != null)
              Text('Term ends ${_localTime(order['term_ends_at'])}'),
            if (status == 'awaiting_payment' && bank != null) ...[
              const SizedBox(height: 12),
              Text('Transfer by ${_localTime(order['expires_at'])}.'),
              SelectableText('Bank ${bank['bank_name']}'),
              SelectableText('Payee ${bank['account_name']}'),
              SelectableText('Account ${bank['account_number']}'),
              if (bank['branch'] case final String branch
                  when branch.isNotEmpty)
                SelectableText('Branch $branch'),
              if (bank['instructions'] case final String instructions)
                Text(instructions),
              const Text(
                'Include the order reference in your transfer description. After paying, submit the reference issued by your bank.',
              ),
            ],
            if (status == 'awaiting_payment' ||
                status == 'payment_rejected' ||
                status == 'expired') ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: report,
                child: Text(
                  status == 'expired'
                      ? 'Report a transfer already made'
                      : 'Submit bank reference',
                ),
              ),
            ],
            if (status == 'paid' && order['kind'] == 'initial') ...[
              const SizedBox(height: 8),
              Text(switch (handover) {
                'sent' => 'Sign out and use the username and temporary password sent to your signup email.',
                'completed' => 'Your workspace account is active.',
                'failed' || 'expired' => 'Your workspace is confirmed. Request a fresh temporary password.',
                _ =>
                  'Preparing your workspace credentials. Refresh for updates.',
              }),
              if (handover == 'sent' && order['handover_expires_at'] != null)
                Text(
                  'Change the temporary password by ${_localTime(order['handover_expires_at'])}.',
                ),
              if (order['handover_can_reissue'] == true)
                OutlinedButton(
                  onPressed: reissue,
                  child: const Text('Request new temporary password'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckoutInput extends StatefulWidget {
  const _CheckoutInput({this.isName = false});

  final bool isName;

  @override
  State<_CheckoutInput> createState() => _CheckoutInputState();
}

class _CheckoutInputState extends State<_CheckoutInput> {
  String _value = '';

  @override
  Widget build(BuildContext context) {
    final name = widget.isName;
    final preview = _value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return AlertDialog(
      title: Text(name ? 'Name your workspace' : 'Submit bank reference'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            autofocus: true,
            maxLength: 160,
            decoration: InputDecoration(
              labelText: name
                  ? 'Organization or personal name'
                  : 'Bank transaction reference',
            ),
            onChanged: (value) => setState(() => _value = value.trim()),
          ),
          if (name) ...[
            const Text(
              'Jentra OS uses this name to generate your sign-in username. Your order will show the final username.',
            ),
            if (preview.length >= 3)
              Text(
                'Username example ${preview.length > 40 ? preview.substring(0, 40) : preview}',
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _value.length < (name ? 2 : 3)
              ? null
              : () => Navigator.pop(context, _value),
          child: Text(name ? 'Continue to checkout' : 'Submit for review'),
        ),
      ],
    );
  }
}
