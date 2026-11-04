import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../confirmation_controller.dart';
import 'components.dart';

class CustomerConfirmationApp extends StatelessWidget {
  const CustomerConfirmationApp(this.controller, {super.key});
  final ConfirmationController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Jentra · Order response',
    debugShowCheckedModeBanner: false,
    theme: salesTheme(Brightness.light),
    home: CustomerConfirmationPage(controller),
  );
}

class CustomerConfirmationPage extends StatefulWidget {
  const CustomerConfirmationPage(this.controller, {super.key});
  final ConfirmationController controller;
  @override
  State<CustomerConfirmationPage> createState() =>
      _CustomerConfirmationPageState();
}

class _CustomerConfirmationPageState extends State<CustomerConfirmationPage>
    with WidgetsBindingObserver {
  final _code = TextEditingController(), _reason = TextEditingController();
  bool _authorized = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_clearPrivateInputs);
  }

  void _clearPrivateInputs() {
    if (widget.controller.stage == ConfirmationStage.unavailable ||
        widget.controller.stage == ConfirmationStage.complete) {
      _code.clear();
      _reason.clear();
      _authorized = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _code.clear();
      // Reading the separately delivered code requires switching to email.
      // Once verified terms are visible, backgrounding clears the whole review.
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
    widget.controller.removeListener(_clearPrivateInputs);
    _code.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(title: const Text('Jentra · Order response')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (c.busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                if (c.error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      c.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ...switch (c.stage) {
                  ConfirmationStage.start => [
                    Text(
                      'Verify your email',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Request a separate code at the email address authorized by the company. Opening this link does not accept an order.',
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: c.busy ? null : c.requestCode,
                      child: const Text('Send email code'),
                    ),
                  ],
                  ConfirmationStage.code => [
                    Text(
                      'Check your email',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Enter the six-digit code sent separately to the authorized email address. If it does not arrive, contact the company.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _code,
                      enabled: !c.busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      autofillHints: const [AutofillHints.oneTimeCode],
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email verification code',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: c.busy
                          ? null
                          : () async {
                              final code = _code.text;
                              _code.clear();
                              await c.verify(code);
                            },
                      child: const Text('Verify email code'),
                    ),
                  ],
                  ConfirmationStage.review => _review(c),
                  ConfirmationStage.complete => [
                    Text(
                      'Response recorded',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      c.recordedResponse == 'accepted'
                          ? 'You accepted the reviewed terms.'
                          : 'You rejected the reviewed terms.',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'The company will follow up about your order. Delivery acknowledgement remains separate.',
                    ),
                  ],
                  ConfirmationStage.unavailable => [
                    Text(
                      'Response unavailable',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This link cannot be used here. It may have expired, changed, or be awaiting the company’s email service. Contact the company for a current request.',
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
  List<Widget> _review(ConfirmationController c) {
    final offer = c.offer!, currency = offer['currency_code'];
    final terms = offer['terms'] as Map, totals = offer['totals'] as Map;
    final address = _addressLines(terms['ship_to']).join('\n');
    return [
      Text(
        'Review the order terms',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 16),
      Text('${offer['company']} · ${offer['customer']}'),
      if ((offer['reference'] as String? ?? '').isNotEmpty)
        Text('Reference: ${offer['reference']}'),
      Text('Ship to: $address'),
      Text('Requested delivery: ${terms['requested_date']}'),
      Text('Payment terms: ${terms['payment_terms_days']} days'),
      Text('Delivery terms: ${terms['delivery_terms']}'),
      Text('Offer valid until: ${offer['valid_until']}'),
      Text('Order discount: ${offer['discount_percent']}%'),
      const SizedBox(height: 16),
      for (final line in offer['lines'] as List)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line['description']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${line['quantity']} ${line['unit']} × $currency ${line['unit_price']}',
                ),
                if (line['line_discount_amount'] != null)
                  Text(
                    'Line discount: $currency ${line['line_discount_amount']}',
                  ),
                if (line['header_discount_amount'] != null)
                  Text(
                    'Allocated order discount: $currency ${line['header_discount_amount']}',
                  ),
                Text('Tax: $currency ${line['tax_amount']}'),
                Text('Line total: $currency ${line['line_total']}'),
                Text(
                  '${line['tax_name'] ?? 'Tax'}: ${line['tax_rate']}% · ${line['tax_inclusive'] == true ? 'included in unit price' : 'added to taxable amount'}',
                ),
              ],
            ),
          ),
        ),
      for (final entry in const {
        'subtotal': 'Subtotal',
        'discount_total': 'Discount',
        'tax_total': 'Tax',
        'grand_total': 'Total',
      }.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('${entry.value}: $currency ${totals[entry.key]}'),
        ),
      const SizedBox(height: 16),
      const Text(
        'Respond only if your company has authorized you to do so. This email check confirms access to the authorized address.',
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _authorized,
        title: Text('I am authorized to respond for ${offer['customer']}'),
        onChanged: c.busy || c.hasPending
            ? null
            : (value) => setState(() => _authorized = value ?? false),
      ),
      TextField(
        controller: _reason,
        enabled: !c.busy && !c.hasPending,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Response note (optional)',
        ),
      ),
      const SizedBox(height: 16),
      if (c.hasPending)
        FilledButton(
          onPressed: c.busy ? null : c.retryOriginal,
          child: const Text('Retry original response'),
        )
      else
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: !_authorized || c.busy
                  ? null
                  : () => c.respond('accept', _reason.text, _authorized),
              child: const Text('Accept these terms'),
            ),
            OutlinedButton(
              onPressed: !_authorized || c.busy
                  ? null
                  : () => c.respond('reject', _reason.text, _authorized),
              child: const Text('Reject these terms'),
            ),
          ],
        ),
      const SizedBox(height: 24),
    ];
  }

  List<String> _addressLines(Object? value, [String label = '']) {
    if (value is Map) {
      return [
        for (final entry in value.entries)
          ..._addressLines(
            entry.value,
            [
              label,
              '${entry.key}'.replaceAll('_', ' '),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
      ];
    }
    if (value is List) {
      return [
        for (var i = 0; i < value.length; i++)
          ..._addressLines(value[i], '$label ${i + 1}'),
      ];
    }
    return ['$label: ${value ?? '—'}'];
  }
}
