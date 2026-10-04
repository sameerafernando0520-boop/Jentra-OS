import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';

import '../../app_providers.dart';
import '../negative_stock/negative_stock_policy_controller.dart'
    show negativeStockPolicyRepositoryProvider;
import 'sales_order_screen.dart' show orderStatus;

class OrderCreditDialog extends ConsumerStatefulWidget {
  const OrderCreditDialog({
    required this.preview,
    required this.canOverride,
    super.key,
  });
  final SalesOrderCreditPreview preview;
  final bool canOverride;
  @override
  ConsumerState<OrderCreditDialog> createState() => _CreditState();
}

class _CreditState extends ConsumerState<OrderCreditDialog> {
  final _reason = TextEditingController();
  bool _override = false;
  bool _seenOnline = false, _invalidated = false;
  @override
  void initState() {
    super.initState();
    final initial = ref.read(connectivityStateProvider);
    _seenOnline =
        !initial.isLoading &&
        !initial.hasError &&
        initial.value == ConnectivityState.online;
    ref.listenManual(connectivityStateProvider, (_, next) {
      if (!next.isLoading &&
          !next.hasError &&
          next.value == ConnectivityState.online) {
        _seenOnline = true;
      } else if (_seenOnline && !_invalidated) {
        setState(() => _invalidated = true);
      }
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final blocked = {
      'CUSTOMER_INACTIVE',
      'CREDIT_CURRENCY_MISMATCH',
    }.contains(p.reason);
    final connection = ref.watch(connectivityStateProvider);
    final online =
        !connection.isLoading &&
        !connection.hasError &&
        connection.value == ConnectivityState.online;
    if (online) _seenOnline = true;
    if (!online && _seenOnline) _invalidated = true;
    if (!online || _invalidated) {
      return AlertDialog(
        title: const Text('Credit access changed'),
        content: const Text(
          'Close this dialog and review customer credit again in your current connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Review customer credit'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order version ${p.orderVersion}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final (label, amount) in [
                ('Credit limit', p.creditLimit),
                ('Due exposure (includes overdue)', p.dueExposure),
                ('Overdue portion', p.overdueExposure),
                ('Other confirmed orders', p.existingOrderExposure),
                ('This order', p.currentOrderExposure),
                ('Total exposure after confirmation', p.totalExposure),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '$label\n${amount.currencyCode} ${amount.toDecimalString()}',
                  ),
                ),
              if (!p.projectionAvailable)
                const Text(
                  'No receivables projection is available. The server currently treats due and overdue exposure as zero.',
                ),
              if (p.asOf != null)
                Text('Receivables as of ${p.asOf!.toUtc().toIso8601String()}'),
              Text('Checked ${p.checkedAt.toUtc().toIso8601String()}'),
              const SizedBox(height: 12),
              const Text(
                'Confirmation rechecks current exposure under a lock and records the decision.',
              ),
              if (p.reason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(switch (p.reason) {
                    'CUSTOMER_INACTIVE' =>
                      'The customer is inactive. Confirmation is unavailable.',
                    'CREDIT_CURRENCY_MISMATCH' => 'Customer credit currency differs from this order. Correct the governed credit configuration before confirmation.',
                    _ => 'The limit would be exceeded. Confirmation records a credit hold unless an authorized override is applied.',
                  }),
                ),
              if (widget.canOverride &&
                  p.reason == 'CREDIT_LIMIT_EXCEEDED') ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Apply privileged credit override'),
                  value: _override,
                  onChanged: online
                      ? (value) => setState(() => _override = value ?? false)
                      : null,
                ),
                if (_override)
                  TextField(
                    key: const Key('order-override-reason'),
                    controller: _reason,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Override reason',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed:
              !online || blocked || (_override && _reason.text.trim().isEmpty)
              ? null
              : () => Navigator.pop(context, (
                  overrideCredit: _override,
                  reason: _reason.text.trim(),
                )),
          child: Text(
            _override
                ? 'Override & confirm'
                : p.reason == 'CREDIT_LIMIT_EXCEEDED'
                ? 'Record credit hold'
                : 'Confirm order',
          ),
        ),
      ],
    );
  }
}

class CreditDecisionCard extends StatelessWidget {
  const CreditDecisionCard({required this.decision, super.key});
  final Map<String, Object?> decision;
  @override
  Widget build(BuildContext context) {
    final d = decision;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: JentraPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${orderStatus(d['decision']?.toString() ?? '')} · ${d['decided_at']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Currency ${d['currency_code']} · Limit ${d['credit_limit']}\nDue ${d['due_exposure']} (overdue portion ${d['overdue_exposure']})\nExisting orders ${d['existing_order_exposure']} · This order ${d['current_order_exposure']}\nTotal exposure ${d['total_exposure']}',
            ),
            if (d['override_applied'] == true)
              Text(
                'Override: ${d['override_reason']}\nAuthorized by ${d['override_by']}',
              ),
            SelectableText('Decision ${d['id']}'),
          ],
        ),
      ),
    );
  }
}

class OrderCancelDialog extends ConsumerStatefulWidget {
  const OrderCancelDialog({super.key});
  @override
  ConsumerState<OrderCancelDialog> createState() => _CancelState();
}

class _CancelState extends ConsumerState<OrderCancelDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cancel sales order'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Cancellation records cancelled quantities and releases active reservations. Delivered or invoiced orders cannot be cancelled.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Cancellation reason'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep order'),
      ),
      FilledButton(
        onPressed:
            _reason.text.trim().isEmpty ||
                ref.watch(connectivityStateProvider).value !=
                    ConnectivityState.online
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Cancel order'),
      ),
    ],
  );
}

class OrderReservationDialog extends ConsumerStatefulWidget {
  const OrderReservationDialog({
    required this.scope,
    required this.detail,
    super.key,
  });
  final TenantContext scope;
  final SalesOrderDetail detail;
  @override
  ConsumerState<OrderReservationDialog> createState() => _ReservationState();
}

class _ReservationState extends ConsumerState<OrderReservationDialog> {
  final _expires = TextEditingController(
    text: DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
  );
  final _quantities = <String, String>{};
  final _quantityControllers = <String, TextEditingController>{};
  final _availability = <String, Map<String, Object?>>{};
  final _overrideReason = TextEditingController();
  NegativeStockPolicy? _policy;
  bool _override = false;
  bool _invalidated = false;
  bool get _canOverride =>
      _active &&
      _policy?.active == true &&
      (ref
              .read(businessCapabilitiesProvider)
              .value
              ?.contains('inventory.stock.override') ??
          false);
  bool _loading = true;
  String? _error;
  int _generation = 0;
  bool get _active =>
      mounted &&
      !_invalidated &&
      ref.read(activeTenantContextProvider) == widget.scope &&
      !ref.read(businessCapabilitiesProvider).isLoading &&
      !ref.read(businessCapabilitiesProvider).hasError &&
      (ref
              .read(businessCapabilitiesProvider)
              .value
              ?.contains('inventory.reservations.manage') ??
          false) &&
      !ref.read(connectivityStateProvider).isLoading &&
      !ref.read(connectivityStateProvider).hasError &&
      ref.read(connectivityStateProvider).value == ConnectivityState.online;
  List<SalesOrderLine> get _lines {
    final stocked = {
      for (final raw in widget.detail.snapshot['lines']! as List)
        if ((raw as Map)['product_kind'] == 'stocked') raw['id'],
    };
    return widget.detail.order.lines
        .where((l) => stocked.contains(l.id) && l.remainingToReserve.isPositive)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    void observe() {
      if (!_active && !_invalidated) {
        _invalidated = true;
        _generation++;
        _availability.clear();
        _policy = null;
        _override = false;
        if (mounted) setState(() {});
      }
    }

    ref.listenManual(activeTenantContextProvider, (_, _) => observe());
    ref.listenManual(businessCapabilitiesProvider, (_, _) => observe());
    ref.listenManual(connectivityStateProvider, (_, _) => observe());
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _generation++;
    _expires.dispose();
    _overrideReason.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!_active) return;
    setState(() {
      _loading = true;
      _error = null;
      _availability.clear();
      _policy = null;
      _override = false;
    });
    try {
      final reader = ref.read(salesOrderRepositoryProvider);
      if (reader == null) throw StateError('Backend unavailable');
      final products = _lines.map((l) => l.productId).toSet().toList();
      final rows = <Map<String, Object?>>[];
      // At most 500 known order lines, with each request bounded to 100 identities.
      for (var start = 0; start < products.length; start += 100) {
        rows.addAll(
          await reader.availability(
            context: widget.scope,
            warehouseId: widget.detail.order.warehouseId,
            productIds: products.skip(start).take(100).toList(),
          ),
        );
        if (!_active || generation != _generation) return;
      }
      final policyReader = ref.read(negativeStockPolicyRepositoryProvider);
      NegativeStockPolicy? policy;
      if (policyReader != null &&
          (ref
                  .read(businessCapabilitiesProvider)
                  .value
                  ?.contains('inventory.stock.override') ??
              false)) {
        try {
          policy = await policyReader.readPolicy(widget.scope);
          if (!_active || generation != _generation) return;
        } on DomainError catch (error) {
          if (!_active || generation != _generation) return;
          if ({
            'PERMISSION_DENIED',
            'AUTHENTICATION_REQUIRED',
            'MFA_REQUIRED',
            'TENANT_ACCESS_DENIED',
            'ACCESS_DENIED',
          }.contains(error.code)) {
            rethrow;
          }
        } on Object {
          if (!_active || generation != _generation) return;
        }
      }
      setState(() {
        _policy = policy;
        _availability.clear();
        for (final row in rows) {
          _availability[row['product_id']! as String] = row;
        }
        _loading = false;
      });
    } on Object catch (problem) {
      if (_active && generation == _generation) {
        if (problem is DomainError &&
            {
              'PERMISSION_DENIED',
              'AUTHENTICATION_REQUIRED',
              'MFA_REQUIRED',
              'TENANT_ACCESS_DENIED',
              'ACCESS_DENIED',
            }.contains(problem.code)) {
          setState(() {
            _invalidated = true;
            _availability.clear();
            _policy = null;
            _override = false;
            _loading = false;
          });
          return;
        }
        setState(() {
          _loading = false;
          _error = 'Could not load current availability. Try again before reserving.';
        });
      }
    }
  }

  void _submit() {
    if (!_active || _loading) return;
    try {
      final expiry = DateTime.tryParse(_expires.text);
      if (expiry == null ||
          !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(_expires.text) ||
          !expiry.isAfter(DateTime.now().toUtc())) {
        throw const FormatException(
          'Enter a future timestamp with an explicit UTC offset.',
        );
      }
      final demand = <String, BigInt>{};
      final lines = <StockReservationLineDraft>[];
      for (final line in _lines) {
        final raw = (_quantities[line.id] ?? '').trim();
        if (raw.isEmpty) continue;
        if (!RegExp(r'^[0-9]+(?:\.[0-9]{1,6})?$').hasMatch(raw)) {
          throw const FormatException(
            'Enter positive quantities with at most six decimal places.',
          );
        }
        final quantity = ExactDecimal.parse(raw, scale: 6);
        if (!quantity.isPositive ||
            quantity.scaledValue > line.remainingToReserve.scaledValue) {
          throw FormatException(
            'Quantity exceeds remaining demand for ${line.description}.',
          );
        }
        demand[line.productId] =
            (demand[line.productId] ?? BigInt.zero) + quantity.scaledValue;
        final available = ExactDecimal.parse(
          _availability[line.productId]?['available_quantity']?.toString() ??
              '0',
          scale: 6,
        );
        if (demand[line.productId]! > available.scaledValue && !_override) {
          throw FormatException(
            'Requested total exceeds current availability for ${line.description}.',
          );
        }
        lines.add(
          StockReservationLineDraft(
            salesOrderLineId: line.id,
            requestedBaseQuantity: quantity,
          ),
        );
      }
      if (lines.isEmpty) {
        throw const FormatException('Enter at least one quantity to reserve.');
      }
      NegativeStockOverride? override;
      if (_override) {
        if (!_canOverride) {
          throw const FormatException(
            'Reopen this dialog under the current active policy and stock-override capability.',
          );
        }
        override = NegativeStockOverride(
          policyVersion: _policy!.version,
          reason: _overrideReason.text,
        );
        if (!override.validate().isValid) {
          throw const FormatException(
            'Enter an override reason of 1 to 1000 characters.',
          );
        }
      }
      Navigator.pop(
        context,
        StockReservationDraft(
          salesOrderId: widget.detail.order.id,
          expiresAt: expiry,
          lines: lines,
          negativeStockOverride: override,
        ),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(connectivityStateProvider);
    ref.watch(businessCapabilitiesProvider);
    ref.watch(activeTenantContextProvider);
    return AlertDialog(
      title: const Text('Reserve available stock'),
      content: SizedBox(
        width: 720,
        height: 500,
        child: ListView(
          children: [
            const Text(
              'Enter quantities in base units. The server rechecks availability and remaining demand; another reservation may reduce the final allocation.',
            ),
            const SizedBox(height: 16),
            if (_canOverride) ...[
              CheckboxListTile(
                key: const Key('negative-stock-override'),
                title: const Text('Authorize a shortage reservation'),
                subtitle: Text(
                  'Policy version ${_policy!.version}. The server blocks unknown cost basis and lot or serial shortages; later receipts record linked cost corrections.',
                ),
                value: _override,
                onChanged: (value) => setState(() => _override = value == true),
              ),
              if (_override)
                TextField(
                  key: const Key('negative-stock-override-reason'),
                  controller: _overrideReason,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Shortage override reason',
                  ),
                ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const Key('order-reservation-expiry'),
              controller: _expires,
              enabled: _active && !_loading,
              decoration: const InputDecoration(
                labelText: 'Reservation expiry · UTC',
                helperText: 'ISO timestamp, for example 2026-10-01T12:00:00Z',
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (!_active)
              const Text(
                'Connection or access changed. Reopen this dialog when ready.',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_loading && _lines.isEmpty)
              const Text('There is no remaining stocked demand to reserve.'),
            for (final line in _lines)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.description,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Remaining demand ${line.remainingToReserve.toDecimalString()}\nOn hand ${_availability[line.productId]?['on_hand_quantity'] ?? '0.000000'} · Available ${_availability[line.productId]?['available_quantity'] ?? '0.000000'}',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: Key('reserve-${line.id}'),
                      controller: _quantityControllers.putIfAbsent(
                        line.id,
                        () => TextEditingController(
                          text: _quantities[line.id] ?? '',
                        ),
                      ),
                      enabled: _active && !_loading,
                      decoration: const InputDecoration(
                        labelText: 'Reserve base quantity',
                      ),
                      onChanged: (text) => _quantities[line.id] = text,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        TextButton(
          onPressed: _active && !_loading ? _load : null,
          child: const Text('Refresh availability'),
        ),
        FilledButton(
          onPressed: _active && !_loading ? _submit : null,
          child: const Text('Reserve quantities'),
        ),
      ],
    );
  }
}
