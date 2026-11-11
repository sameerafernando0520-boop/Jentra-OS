part of 'platform_organization_screen.dart';

class _SubscriptionControl extends StatefulWidget {
  const _SubscriptionControl({required this.gateway});

  final PlatformOrganizationGateway gateway;

  @override
  State<_SubscriptionControl> createState() => _SubscriptionControlState();
}

class _SubscriptionControlState extends State<_SubscriptionControl> {
  static const _pageSize = 50;
  late final Timer _poll;
  var _orders = <_Row>[];
  var _offset = 0;
  var _loading = false;
  var _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll.cancel();
    super.dispose();
  }

  Future<void> _refresh([int? offset]) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final target = offset ?? _offset;
      final data = await widget.gateway.rpc<List<dynamic>>(
        'platform_subscription_checkout_queue',
        {'p_offset': target},
      );
      if (!mounted) return;
      setState(() {
        _offset = target;
        _orders = data.map(_row).toList();
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'Could not refresh subscription orders.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loaded = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _bank() async {
    _Row bank;
    try {
      final settings = await widget.gateway.rpc<Map<String, dynamic>>(
        'platform_subscription_checkout_settings',
      );
      bank = settings['bank'] == null ? {} : _row(settings['bank']);
    } on Object {
      if (mounted) {
        _notice(context, 'Could not load bank transfer instructions.');
      }
      return;
    }
    if (!mounted) return;
    final changed = await _edit(
      context,
      'Bank transfer instructions',
      'These LKR deposit instructions appear in new checkout orders. Confirm the account details before saving.',
      [
        _Field(
          'bank',
          'Bank name',
          initial: bank['bank_name'] as String? ?? '',
        ),
        _Field(
          'account',
          'Account holder',
          initial: bank['account_name'] as String? ?? '',
        ),
        _Field(
          'number',
          'Account number',
          initial: bank['account_number'] as String? ?? '',
        ),
        _Field('branch', 'Branch', initial: bank['branch'] as String? ?? ''),
        _Field(
          'instructions',
          'Transfer instructions',
          initial: bank['instructions'] as String? ?? '',
          lines: 3,
          required: false,
        ),
      ],
      (values) async {
        await widget.gateway.rpc<Object?>('platform_save_subscription_bank', {
          'p_bank_name': values['bank'],
          'p_account_name': values['account'],
          'p_account_number': values['number'],
          'p_branch': values['branch'],
          'p_instructions': values['instructions'],
        });
      },
    );
    if (mounted && changed) {
      _notice(context, 'Bank transfer instructions saved.');
    }
  }

  Future<void> _inspect(_Row order) async {
    final reviewable = ['under_review', 'expired'].contains(order['status']);
    final hasReport = order['transfer_reference'] is String;
    final reissuable = order['handover_can_reissue'] == true;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(order['organization_name'] as String),
        content: SizedBox(
          width: 470,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${order['plan_name']} · ${_price(order['price_minor'], order['currency_code'])} · ${order['term_days']} days',
              ),
              Text('Order · ${order['id']}'),
              Text('Status · ${_orderState(order['status'])}'),
              Text(
                'Type · ${order['kind'] == 'renewal' ? 'Renewal' : 'New subscription'}',
              ),
              Text('Signup email · ${order['signup_email'] ?? 'Unavailable'}'),
              Text('Organization username · ${order['username'] ?? 'Pending'}'),
              Text(
                'Reported transfer reference · ${order['transfer_reference'] ?? 'Unavailable'}',
              ),
              Text('Order opened · ${_colomboDate(order['created_at'])}'),
              Text('Payment deadline · ${_colomboDate(order['expires_at'])}'),
              if (order['verified_reference'] != null)
                Text(
                  'Verified transfer · ${order['verified_reference']} · ${_price(order['verified_amount_minor'], order['currency_code'])} · ${_date(order['verified_paid_at'])}',
                ),
              if (order['term_ends_at'] != null)
                Text('Subscription ends · ${_date(order['term_ends_at'])}'),
              if (order['decision_reason'] != null)
                Text('Decision · ${order['decision_reason']}'),
              if (order['exception_reason'] != null)
                Text('Exception · ${order['exception_reason']}'),
              if (order['kind'] != 'renewal')
                Text(
                  'Credentials · ${_handoverState(order['handover_status'])}',
                ),
              if (order['handover_expires_at'] != null)
                Text(
                  'Temporary password expires · ${_date(order['handover_expires_at'])}',
                ),
              if (order['handover_attempts'] case final int attempts
                  when attempts > 0)
                Text('Delivery attempts · $attempts'),
              if (order['handover_error'] != null)
                const Text(
                  'The delivery worker recorded an error. Review the status before reissuing.',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (reissuable)
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'reissue'),
              child: const Text('Reissue credentials'),
            ),
          if (reviewable) ...[
            TextButton(
              onPressed: () => Navigator.pop(context, 'reject'),
              child: const Text('Reject or record exception'),
            ),
            if (hasReport)
              FilledButton(
                onPressed: () => Navigator.pop(context, 'approve'),
                child: const Text('Verify payment'),
              ),
          ],
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reissue') {
      await _reissue(order);
    } else {
      await _review(order, approved: action == 'approve');
    }
  }

  Future<void> _reissue(_Row order) async {
    final changed = await _edit(
      context,
      'Reissue temporary credentials',
      'A new temporary password will be sent to the verified delivery address. Earlier temporary credentials will expire.',
      const [],
      (_) async {
        await widget.gateway.rpc<Object?>('subscription_reissue_handover', {
          'p_order_id': order['id'],
        });
      },
      submit: 'Queue new email',
    );
    if (mounted && changed) {
      _notice(context, 'Credential email queued.');
      await _refresh();
    }
  }

  Future<void> _review(_Row order, {required bool approved}) async {
    final changed = await _edit(
      context,
      approved
          ? 'Verify bank payment'
          : 'Reject payment or record an exception',
      approved
          ? 'Check the bank statement for ${_price(order['price_minor'], order['currency_code'])} with reference ${order['transfer_reference']}. Confirm a matching transfer between ${_colomboDate(order['created_at'])} and ${_colomboDate(order['expires_at'])}.'
          : 'Record why the payment could not be accepted. If a transfer was late, for the wrong amount or had a different reference, enter the details observed on the bank statement.',
      [
        _Field('reference', 'Actual transfer reference', required: approved),
        _Field('amount', 'Actual amount in LKR', required: approved),
        _Field(
          'paid_at',
          'Sri Lanka transfer time (YYYY-MM-DD HH:MM:SS)',
          required: approved,
        ),
        if (!approved)
          const _Field(
            'exception',
            'Transfer exception details',
            required: false,
            lines: 2,
          ),
        _Field(
          'reason',
          approved ? 'Review note' : 'Reason for rejection',
          required: !approved,
          lines: 2,
        ),
      ],
      (values) async {
        final reference = _provided(values['reference']);
        final amount = _provided(values['amount']);
        final timestamp = _provided(values['paid_at']);
        final actualMinor = amount == null ? null : _minor(amount, 'LKR');
        final paidAt = timestamp == null
            ? null
            : _sriLankaTransferTime(timestamp);
        if (approved &&
            !_matchesOrder(order, reference!, actualMinor!, paidAt!)) {
          throw const PlatformOrganizationFailure(
            'SUBSCRIPTION_PAYMENT_NOT_MATCHED',
          );
        }
        await widget.gateway.rpc<Object?>(
          'platform_review_subscription_payment',
          {
            'p_order_id': order['id'],
            'p_approved': approved,
            'p_verified_reference': reference,
            'p_verified_amount_minor': actualMinor,
            'p_verified_paid_at': paidAt?.toIso8601String(),
            'p_reason': values['reason'],
            'p_exception_reason': values['exception'],
          },
        );
      },
      submit: approved ? 'Confirm payment' : 'Reject report',
    );
    if (mounted && changed) {
      _notice(
        context,
        approved ? 'Payment verified.' : 'Payment report rejected.',
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Subscription orders',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          OutlinedButton.icon(
            onPressed: _bank,
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Bank instructions'),
          ),
          IconButton(
            onPressed: _loading ? null : () => _refresh(),
            tooltip: 'Refresh subscription orders',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (!_loaded) const LinearProgressIndicator(),
      if (_error case final error?) _Problem(error),
      if (_loaded && _orders.isEmpty && _error == null)
        const Text('No subscription orders on this page.'),
      for (final order in _orders.take(_pageSize))
        Card(
          child: ListTile(
            title: Text(order['organization_name'] as String),
            subtitle: Text(
              '${order['plan_name']} · ${_price(order['price_minor'], order['currency_code'])} · ${_orderState(order['status'])}'
              '${order['kind'] == 'renewal' ? ' · Renewal' : ''}'
              '${order['handover_status'] == null ? '' : ' · ${_handoverState(order['handover_status'])}'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _inspect(order),
          ),
        ),
      if (_offset > 0 || _orders.length >= _pageSize)
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: _loading || _offset == 0
                  ? null
                  : () => _refresh(_offset - _pageSize),
              child: const Text('Previous orders'),
            ),
            TextButton(
              onPressed: _loading || _orders.length < _pageSize
                  ? null
                  : () => _refresh(_offset + _pageSize),
              child: const Text('More orders'),
            ),
          ],
        ),
    ],
  );
}

const _colomboOffset = Duration(hours: 5, minutes: 30);

String? _provided(String? value) =>
    value == null || value.isEmpty ? null : value;

String _colomboDate(Object? value) {
  final utc = DateTime.tryParse(value?.toString() ?? '')?.toUtc();
  return utc == null
      ? 'Unavailable'
      : '${DateFormat('yyyy-MM-dd HH:mm:ss').format(utc.add(_colomboOffset))} Sri Lanka time';
}

DateTime _sriLankaTransferTime(String value) {
  try {
    return DateFormat('yyyy-MM-dd HH:mm:ss')
        .parseStrict(value, true)
        .subtract(_colomboOffset);
  } on FormatException {
    throw const PlatformOrganizationFailure('INVALID_TRANSFER_DATE');
  }
}

bool _matchesOrder(
  _Row order,
  String reference,
  int amountMinor,
  DateTime paidAt,
) {
  final opened = DateTime.tryParse(order['created_at']?.toString() ?? '');
  final expires = DateTime.tryParse(order['expires_at']?.toString() ?? '');
  return reference.toLowerCase() ==
          (order['transfer_reference'] as String?)?.toLowerCase() &&
      amountMinor == order['price_minor'] &&
      opened != null &&
      expires != null &&
      !paidAt.isBefore(opened) &&
      !paidAt.isAfter(expires);
}

String _orderState(Object? status) => switch (status) {
  'awaiting_payment' => 'Awaiting payment',
  'under_review' => 'Payment reported',
  'payment_rejected' => 'Payment rejected',
  'paid' => 'Paid',
  'expired' => 'Expired',
  'cancelled' => 'Cancelled',
  _ => 'Unknown status',
};

String _handoverState(Object? status) => switch (status) {
  'pending' => 'Credential email queued',
  'processing' => 'Preparing credentials',
  'failed' => 'Credential email failed',
  'sent' => 'Temporary password sent',
  'expired' => 'Temporary password expired',
  'completed' => 'Password changed',
  _ => 'Awaiting activation',
};
