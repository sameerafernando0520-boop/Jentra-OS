import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_field_sales.dart';

import '../field_sales_controller.dart';
import '../models.dart';
import 'components.dart';

class FieldSalesWorkspace extends StatefulWidget {
  const FieldSalesWorkspace(
    this.controller, {
    required this.onLeave,
    super.key,
  });
  final FieldSalesController controller;
  final Future<void> Function() onLeave;
  @override
  State<FieldSalesWorkspace> createState() => _FieldSalesWorkspaceState();
}

class _FieldSalesWorkspaceState extends State<FieldSalesWorkspace>
    with WidgetsBindingObserver {
  int _page = 0;
  String _query = '';
  var _composerKey = GlobalKey<_FieldOrderComposerState>();
  Future<bool> _confirmLeave() async {
    final composer = _composerKey.currentState;
    if (composer == null || !composer.dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep your order changes?'),
        content: const Text(
          'Save a protected local draft, keep editing, or discard these changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard changes'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save local draft'),
          ),
        ],
      ),
    );
    if (choice == 'save') return composer.saveLocal();
    return choice == 'discard';
  }

  Future<void> _guarded(Future<void> Function() work) async {
    if (!await _confirmLeave() || !mounted) return;
    widget.controller.invalidateReview();
    setState(() => _composerKey = GlobalKey<_FieldOrderComposerState>());
    await work();
  }

  Future<void> _navigate(int page) async {
    if (page == _page) return;
    await _guarded(() async {
      if (mounted) setState(() => _page = page);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.onLeave();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 700;
          final labels = ['Today', 'Customers', 'Orders', 'More'];
          final icons = [
            Icons.space_dashboard_outlined,
            Icons.people_outline,
            Icons.receipt_long_outlined,
            Icons.more_horiz,
          ];
          return Scaffold(
            appBar: AppBar(
              title: const Text('Jentra Sales'),
              actions: [
                IconButton(
                  tooltip: 'Refresh portfolio',
                  onPressed: c.busy || c.scope == null
                      ? null
                      : () => _guarded(() => c.selectScope(c.scope!)),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Sign out of Sales',
                  onPressed: () => _guarded(widget.onLeave),
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    NavigationRail(
                      extended:
                          box.maxWidth >= 1180 &&
                          MediaQuery.textScalerOf(context).scale(1) < 1.6,
                      selectedIndex: _page,
                      onDestinationSelected: _navigate,
                      labelType:
                          box.maxWidth < 1180 ||
                              MediaQuery.textScalerOf(context).scale(1) >= 1.6
                          ? NavigationRailLabelType.all
                          : null,
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(labels[i]),
                          ),
                      ],
                    ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(wide ? 32 : 16),
                      children: [
                        Text(
                          labels[_page],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 16),
                        if (c.busy)
                          const LinearProgressIndicator(
                            semanticsLabel: 'Checking current Sales authority',
                          ),
                        if (c.error != null) SalesNotice(c.error!),
                        if (c.scopes.length > 1)
                          DropdownButton<String>(
                            value: c.scope?.key,
                            isExpanded: true,
                            hint: const Text('Company and branch'),
                            items: [
                              for (final s in c.scopes)
                                DropdownMenuItem(
                                  value: FieldSalesScope.fromJson(s).key,
                                  child: Text(
                                    '${s['company_name']} · ${s['branch_name']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: c.busy
                                ? null
                                : (key) {
                                    final row = c.scopes.firstWhere(
                                      (s) =>
                                          FieldSalesScope.fromJson(s).key ==
                                          key,
                                    );
                                    _guarded(
                                      () => c.selectScope(
                                        FieldSalesScope.fromJson(row),
                                      ),
                                    );
                                  },
                          ),
                        if (c.pending != null) ...[
                          const SizedBox(height: 16),
                          SalesPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SectionTitle(
                                  'Check your original submission',
                                ),
                                const Text(
                                  'Its outcome is still unconfirmed. Check the saved command before retrying; a new order will not be created automatically.',
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    FilledButton(
                                      onPressed: c.busy
                                          ? null
                                          : () => c.reconcile(),
                                      child: const Text('Check submission'),
                                    ),
                                    OutlinedButton(
                                      onPressed: c.busy
                                          ? null
                                          : () => c.reconcile(retry: true),
                                      child: const Text(
                                        'Retry original request',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (c.scope == null)
                          const SalesEmpty(
                            'Choose your company',
                            'Select a company and branch to open your current customer portfolio.',
                          )
                        else if (_page == 0) ...[
                          SalesPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SectionTitle('Your assigned portfolio'),
                                Text(
                                  '${c.customers.length} assigned customers · ${c.orders.where((r) => r['company_state'] == 'submitted').length} requests awaiting company review',
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => _navigate(1),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Prepare an order'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          const SalesNotice(
                            'Customer email acceptance, company approval and delivery acknowledgement are separate. Verified email links are pending activation.',
                          ),
                        ] else if (_page == 1) ...[
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Search assigned customers',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (q) => setState(() => _query = q),
                          ),
                          const SizedBox(height: 16),
                          for (final row in c.customers.where(
                            (r) => (r['name'] as String).toLowerCase().contains(
                              _query.toLowerCase(),
                            ),
                          ))
                            Card(
                              child: ListTile(
                                title: Text(row['name'] as String),
                                subtitle: Text(
                                  'Payment terms: ${row['payment_terms_days']} days · ${row['delivery_terms']}',
                                ),
                                selected: c.selectedCustomer == row['id'],
                                onTap: c.busy || c.pending != null
                                    ? null
                                    : () => _guarded(
                                        () => c.selectCustomer(
                                          row['id'] as String,
                                        ),
                                      ),
                              ),
                            ),
                          if (c.customers.isEmpty)
                            const SalesEmpty(
                              'No assigned customers',
                              'Ask your company to review your dated customer assignments.',
                            ),
                          if (c.selectedCustomer != null &&
                              c.pending == null) ...[
                            const SizedBox(height: 24),
                            FieldOrderComposer(c, key: _composerKey),
                          ],
                        ] else if (_page == 2) ...[
                          if (c.orders.isEmpty)
                            const SalesEmpty(
                              'No submitted requests',
                              'Prepare an order from your assigned customers.',
                            ),
                          for (final order in c.orders)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: SalesPanel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.customers
                                                  .where(
                                                    (r) =>
                                                        r['id'] ==
                                                        order['customer_id'],
                                                  )
                                                  .firstOrNull?['name']
                                              as String? ??
                                          'Assigned customer',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: 12),
                                    Text('Company: ${order['company_state']}'),
                                    Text(
                                      'Customer: ${order['customer_state'] ?? 'email_link_pending'}',
                                    ),
                                    Text(
                                      'Delivery: ${order['delivery_state'] ?? 'not_requested'}',
                                    ),
                                    if (order['canonical_order_id'] != null)
                                      Text(
                                        'Canonical order: ${order['canonical_state'] ?? 'draft'}',
                                      ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Requested total: ${order['preview']['currency_code']} ${order['preview']['pricing']['grand_total']}',
                                    ),
                                    if (order['decision_reason'] != null)
                                      Text(
                                        'Company reason: ${order['decision_reason']}',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ] else ...[
                          const SalesNotice(
                            'Online review is required for each submission. Backgrounding or signing out locks this Sales workspace. Recovery retains the original protected command.',
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => _guarded(widget.onLeave),
                            child: const Text('Sign out of Sales'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _page,
                    onDestinationSelected: _navigate,
                    destinations: [
                      for (var i = 0; i < labels.length; i++)
                        NavigationDestination(
                          icon: Icon(icons[i]),
                          label: labels[i],
                        ),
                    ],
                  ),
          );
        },
      );
    },
  );
}

class FieldOrderComposer extends StatefulWidget {
  const FieldOrderComposer(this.c, {super.key});
  final FieldSalesController c;
  @override
  State<FieldOrderComposer> createState() => _FieldOrderComposerState();
}

class _FieldOrderComposerState extends State<FieldOrderComposer> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(),
      _discount = TextEditingController(text: '0'),
      _reason = TextEditingController(),
      _reference = TextEditingController(),
      _notes = TextEditingController();
  final _quantities = <String, TextEditingController>{};
  String? _warehouse;
  String? _error;
  late String _savedSignature;
  String get _signature => jsonEncode(_input());
  bool get dirty => _signature != _savedSignature;
  @override
  void initState() {
    super.initState();
    final draft = widget.c.savedDraft;
    if (draft != null && draft['customer_id'] == widget.c.selectedCustomer) {
      _warehouse = draft['warehouse_id'] as String?;
      _date.text = draft['requested_date'] as String? ?? '';
      _discount.text = draft['discount_percent'] as String? ?? '0';
      _reason.text = draft['discount_reason'] as String? ?? '';
      _reference.text = draft['reference'] as String? ?? '';
      _notes.text = draft['notes'] as String? ?? '';
      for (final raw in draft['lines'] as List? ?? []) {
        final line = fieldSalesObject(raw);
        if (widget.c.products.any((p) => p['policy_id'] == line['policy_id'])) {
          _quantities[line['policy_id'] as String] = TextEditingController(
            text: line['quantity'] as String,
          );
        }
      }
    }
    _savedSignature = _signature;
  }

  Future<bool> saveLocal() async {
    final signature = _signature;
    final saved = await widget.c.saveDraft(_input());
    if (mounted) {
      setState(() {
        if (saved) _savedSignature = signature;
        _error = saved
            ? 'Local draft saved for up to 24 hours. Review current company terms before submitting.'
            : 'The protected draft could not be saved. Keep editing and try again.';
      });
    }
    return saved;
  }

  @override
  void dispose() {
    for (final c in [
      _date,
      _discount,
      _reason,
      _reference,
      _notes,
      ..._quantities.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _quantity(String? v) {
    try {
      parseQuantity(v ?? '');
      return null;
    } on Object {
      return 'Use a positive quantity with up to 3 decimals.';
    }
  }

  FieldSalesJson _input() => {
    'customer_id': widget.c.selectedCustomer,
    'warehouse_id': _warehouse,
    'requested_date': _date.text,
    'reference': _reference.text.trim(),
    'notes': _notes.text.trim(),
    'discount_percent': _discount.text,
    'discount_reason': _reason.text.trim(),
    'lines': [
      for (final p in widget.c.products)
        if (_quantities.containsKey(p['policy_id']))
          {
            'policy_id': p['policy_id'],
            'policy_version': p['policy_version'],
            'quantity': _quantities[p['policy_id']]!.text,
          },
    ],
  };
  Future<void> _review() async {
    if (!_form.currentState!.validate()) return;
    if (_quantities.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    setState(() => _error = null);
    await widget.c.preview(_input());
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final scope = c.scopes
        .where((s) => FieldSalesScope.fromJson(s).key == c.scope!.key)
        .first;
    final warehouses = (scope['warehouses'] as List)
        .map(fieldSalesObject)
        .toList();
    final customer = c.customers
        .where((row) => row['id'] == c.selectedCustomer)
        .first;
    final address = customer['ship_to'] is Map
        ? (customer['ship_to'] as Map).values
              .whereType<String>()
              .where((v) => v.isNotEmpty)
              .join(', ')
        : '';
    return SalesPanel(
      child: Form(
        key: _form,
        onChanged: c.invalidateReview,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Prepare a governed order'),
            Text(
              'Delivery address: ${address.isEmpty ? 'Ask your company to provide an approved address' : address}',
            ),
            Text(
              'Payment terms: ${customer['payment_terms_days']} days · ${customer['delivery_terms']}',
            ),
            const Text(
              'Prices and discount ceilings come from your company. Stock availability is currently unavailable.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _warehouse,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Fulfilment warehouse',
              ),
              items: [
                for (final w in warehouses)
                  DropdownMenuItem(
                    value: w['id'] as String,
                    child: Text(w['name'] as String),
                  ),
              ],
              onChanged: c.busy
                  ? null
                  : (v) {
                      setState(() => _warehouse = v);
                      c.invalidateReview();
                    },
              validator: (v) => v == null ? 'Choose a warehouse.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _date,
              enabled: !c.busy,
              decoration: const InputDecoration(
                labelText: 'Requested delivery date',
                hintText: 'YYYY-MM-DD',
              ),
              validator: (v) =>
                  v == null ||
                      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
                      DateTime.tryParse(v) == null
                  ? 'Use YYYY-MM-DD.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reference,
              enabled: !c.busy,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Customer reference',
              ),
            ),
            for (final p in c.products) ...[
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text(
                    '${p['name']} · ${p['currency_code']} ${p['unit_price']} / ${p['unit']}',
                  ),
                  if (!_quantities.containsKey(p['policy_id']))
                    OutlinedButton(
                      onPressed: c.busy || _quantities.length >= 100
                          ? null
                          : () {
                              setState(
                                () => _quantities[p['policy_id'] as String] =
                                    TextEditingController(text: '1'),
                              );
                              c.invalidateReview();
                            },
                      child: const Text('Add product'),
                    ),
                ],
              ),
              if (_quantities.containsKey(p['policy_id']))
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantities[p['policy_id']],
                        enabled: !c.busy,
                        validator: _quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quantity · ${p['name']}',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${p['name']}',
                      onPressed: c.busy
                          ? null
                          : () {
                              final removed = _quantities.remove(
                                p['policy_id'],
                              );
                              setState(() {});
                              removed?.dispose();
                              c.invalidateReview();
                            },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
            ],
            if (c.products.isEmpty && !c.busy)
              const Text(
                'No current governed prices are available for this customer.',
              ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _discount,
              enabled: !c.busy,
              decoration: const InputDecoration(
                labelText: 'Requested discount (%)',
              ),
              validator: (v) {
                try {
                  parseDiscount(v ?? '');
                  return null;
                } on Object {
                  return 'Use 0 to 100 with up to 2 decimals.';
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              enabled: !c.busy,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Discount request reason',
              ),
              validator: (v) {
                try {
                  return parseDiscount(_discount.text).isPositive &&
                          (v ?? '').trim().isEmpty
                      ? 'Add a reason for the company review.'
                      : null;
                } on Object {
                  return null;
                }
              },
            ),
            TextFormField(
              controller: _notes,
              enabled: !c.busy,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Order notes'),
            ),
            if (_error != null) SalesNotice(_error!),
            OutlinedButton.icon(
              onPressed: c.busy ? null : saveLocal,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save protected local draft'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: c.busy ? null : _review,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review current company terms'),
            ),
            if (c.review != null) ...[
              const SizedBox(height: 20),
              const SectionTitle('Online commercial review'),
              Text(
                'Reviewed delivery address: ${(c.review!['terms']['ship_to'] as Map).values.whereType<String>().join(', ')}',
              ),
              Text(
                'Reviewed payment terms: ${c.review!['terms']['payment_terms_days']} days · ${c.review!['terms']['delivery_terms']}',
              ),
              Text(
                'Requested subtotal: ${c.review!['currency_code']} ${c.review!['pricing']['subtotal']}',
              ),
              Text(
                'Requested discount: ${c.review!['discount_percent']}% · company approval required',
              ),
              Text('Tax: ${c.review!['pricing']['tax_total']}'),
              Text(
                'Requested total: ${c.review!['currency_code']} ${c.review!['pricing']['grand_total']}',
              ),
              const SizedBox(height: 12),
              const Text(
                'Company credit review is required. Customer acceptance and delivery acknowledgement remain pending. Submitting does not confirm an order.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: c.busy ? null : c.submit,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Submit for company review'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
