import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jentra_domain/jentra_field_sales.dart';

import '../confirmation_controller.dart' show ConfirmationStage;
import '../delivery_confirmation_controller.dart';
import 'components.dart';

class CustomerDeliveryApp extends StatelessWidget {
  const CustomerDeliveryApp(this.controller, {super.key});
  final DeliveryConfirmationController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Jentra · Delivery response',
    debugShowCheckedModeBanner: false,
    theme: salesTheme(Brightness.light),
    home: CustomerDeliveryPage(controller),
  );
}

class CustomerDeliveryPage extends StatefulWidget {
  const CustomerDeliveryPage(this.controller, {super.key});
  final DeliveryConfirmationController controller;
  @override
  State<CustomerDeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<CustomerDeliveryPage>
    with WidgetsBindingObserver {
  final _code = TextEditingController(), _reason = TextEditingController();
  final _scroll = ScrollController();
  final _drafts = <String, FieldSalesJson>{};
  bool _authorized = false;
  int _draftRevision = 0;
  ConfirmationStage? _previous;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_observe);
  }

  void _observe() {
    final stage = widget.controller.stage;
    if (stage == ConfirmationStage.complete ||
        stage == ConfirmationStage.unavailable) {
      _code.clear();
      _reason.clear();
      _drafts.clear();
      _authorized = false;
    }
    if (stage != _previous) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    _previous = stage;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _code.clear();
      if (widget.controller.stage == ConfirmationStage.review ||
          widget.controller.stage == ConfirmationStage.code &&
              widget.controller.busy) {
        widget.controller.lock();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_observe);
    _code.dispose();
    _reason.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 80,
          title: const Text('Jentra · Delivery response', maxLines: 2),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
                if (c.busy) const LinearProgressIndicator(),
                if (c.error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      c.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ...switch (c.stage) {
                  ConfirmationStage.start => [
                    const Text(
                      'Review posted delivery quantities',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Opening this page records nothing. Request a code at the company-authorized email address before viewing delivery details.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: c.busy ? null : c.requestCode,
                      child: const Text('Send verification code'),
                    ),
                  ],
                  ConfirmationStage.code => [
                    const Text(
                      'Check your authorized email for the separate six-digit code.',
                    ),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                      ),
                    ),
                    FilledButton(
                      onPressed: c.busy || _code.text.length != 6
                          ? null
                          : () async {
                              await c.verify(_code.text);
                              _code.clear();
                            },
                      child: const Text('Review delivery'),
                    ),
                  ],
                  ConfirmationStage.review => _review(c),
                  ConfirmationStage.complete => [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Delivery response ${c.recordedResponse ?? 'recorded'}.',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Text(
                      'This is recipient evidence. Company review, stock corrections, returns, invoices and payments are separate actions.',
                    ),
                  ],
                  ConfirmationStage.unavailable => [
                    const Text(
                      'This delivery link is unavailable. Ask the company for a new link. No delivery response has been inferred.',
                    ),
                  ],
                },
              ],
            ),
          ),
        ),
      );
    },
  );
  List<Widget> _review(DeliveryConfirmationController c) {
    final offer = c.offer!,
        lines = (offer['lines'] as List).map(fieldSalesObject).toList();
    for (final line in lines) {
      _drafts.putIfAbsent(
        line['id'] as String,
        () => {'id': line['id'], 'received': '0', 'refused': '0', 'short': '0'},
      );
    }
    final enabled = !c.busy && !c.hasPending;
    return [
      Text(
        '${offer['company']} · ${offer['customer']}',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      Text(
        'Posted delivery ${offer['document_number']} · revision ${offer['delivery_version']}',
      ),
      const Text(
        'Report each quantity in the displayed base unit. Received + refused + short must equal the posted quantity. This does not change an order or correct stock.',
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: !enabled
            ? null
            : () => setState(() {
                for (final line in lines) {
                  _drafts[line['id']] = {
                    'id': line['id'],
                    'received': line['posted_base_quantity'],
                    'refused': '0',
                    'short': '0',
                  };
                }
                _draftRevision++;
              }),
        child: const Text('Mark all posted quantities received'),
      ),
      for (final line in lines)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line['description']} · posted ${line['posted_base_quantity']} ${line['base_unit']}',
                ),
                for (final kind in ['received', 'refused', 'short'])
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextFormField(
                      key: ValueKey(
                        'delivery-${line['id']}-$kind-$_draftRevision',
                      ),
                      initialValue: _drafts[line['id']]![kind] as String,
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            '${kind[0].toUpperCase()}${kind.substring(1)} (${line['base_unit']})',
                      ),
                      onChanged: (value) => _drafts[line['id']]![kind] = value,
                    ),
                  ),
              ],
            ),
          ),
        ),
      TextField(
        controller: _reason,
        enabled: enabled,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: 'Note for refused or short quantities',
        ),
      ),
      CheckboxListTile(
        value: _authorized,
        contentPadding: EdgeInsets.zero,
        onChanged: !enabled
            ? null
            : (value) => setState(() => _authorized = value ?? false),
        title: const Text(
          'I am authorized to report these delivery quantities for this customer.',
        ),
      ),
      if (c.hasPending) ...[
        const Text(
          'The original quantities and note are frozen while the response is uncertain.',
        ),
        FilledButton(
          onPressed: c.busy ? null : c.retryOriginal,
          child: const Text('Retry original delivery response'),
        ),
      ] else
        FilledButton(
          onPressed: !enabled || !_authorized
              ? null
              : () => c.respond(
                  lines
                      .map((l) => Map<String, dynamic>.from(_drafts[l['id']]!))
                      .toList(),
                  _reason.text,
                  _authorized,
                ),
          child: const Text('Record delivery quantities'),
        ),
    ];
  }
}
