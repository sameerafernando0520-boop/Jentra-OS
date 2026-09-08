import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'quotation_reference_label.dart';

String quotationLabel(Object? value) => (value ?? '—').toString();
String quotationStatus(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

/// Renders the persisted customer-facing snapshot, including exact line pricing.
/// Never recomputes a monetary value or converts it through double.
class QuotationDocumentView extends StatelessWidget {
  const QuotationDocumentView({
    required this.snapshot,
    this.labels = const {},
    super.key,
  });
  final Map<String, Object?> snapshot;
  final Map<String, Object?> labels;

  String reference(String field) =>
      quotationLabel(labels[field] ?? snapshot[field]);

  @override
  Widget build(BuildContext context) {
    final currency = quotationLabel(snapshot['currency_code']);
    final lines = (snapshot['lines'] as List? ?? const []).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer quotation',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            QuotationFact(
              'Customer',
              reference('customer_id'),
              valueWidget: QuotationReferenceLabel(
                kind: QuotationReferenceKind.customer,
                id: snapshot['customer_id']! as String,
                savedLabel: labels['customer_id'] as String?,
              ),
            ),
            if (snapshot['contact_id'] != null)
              QuotationFact(
                'Contact',
                reference('contact_id'),
                valueWidget: QuotationReferenceLabel(
                  kind: QuotationReferenceKind.contact,
                  id: snapshot['contact_id']! as String,
                  customerId: snapshot['customer_id']! as String,
                  savedLabel: labels['contact_id'] as String?,
                ),
              ),
            QuotationFact(
              'Quotation date',
              quotationLabel(snapshot['quotation_date']),
            ),
            QuotationFact(
              'Valid through',
              quotationLabel(snapshot['valid_until']),
            ),
            QuotationFact(
              'Payment',
              '${snapshot['payment_terms_days'] ?? 0} days',
            ),
            QuotationFact('Salesperson', reference('salesperson_id')),
            QuotationFact(
              'Delivery terms',
              quotationLabel(snapshot['delivery_terms']),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Items & pricing', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: JentraPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${quotationLabel(lines[i]['description'])}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      QuotationFact(
                        'Quantity',
                        quotationLabel(lines[i]['quantity']),
                        numeric: true,
                      ),
                      QuotationFact(
                        'Unit',
                        quotationLabel(
                          lines[i]['unit_code'] ??
                              labels['unit:${lines[i]['unit_id']}'] ??
                              lines[i]['unit_id'],
                        ),
                      ),
                      QuotationFact(
                        'Conversion',
                        '${lines[i]['conversion_numerator']} / ${lines[i]['conversion_denominator']}',
                      ),
                      QuotationFact(
                        'Base quantity',
                        quotationLabel(lines[i]['base_quantity']),
                        numeric: true,
                      ),
                      QuotationFact(
                        'Unit price · $currency',
                        quotationLabel(lines[i]['unit_price']),
                        numeric: true,
                      ),
                      QuotationFact(
                        'Line discount',
                        quotationLabel(lines[i]['line_discount_amount']),
                        numeric: true,
                      ),
                      QuotationFact(
                        'Header discount share',
                        quotationLabel(lines[i]['header_discount_amount']),
                        numeric: true,
                      ),
                      QuotationFact(
                        'Tax',
                        lines[i]['tax_definition_id'] == null
                            ? 'No tax'
                            : '${lines[i]['tax_name']} · ${lines[i]['tax_rate']}% · ${lines[i]['tax_inclusive'] == true ? 'inclusive' : 'exclusive'}',
                      ),
                      QuotationFact(
                        'Tax amount',
                        quotationLabel(lines[i]['tax_amount']),
                        numeric: true,
                      ),
                      QuotationFact(
                        'Line total · $currency',
                        quotationLabel(lines[i]['line_total']),
                        numeric: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        JentraPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Server-calculated totals',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 28,
                runSpacing: 16,
                children: [
                  QuotationFact(
                    'Subtotal · $currency',
                    quotationLabel(snapshot['subtotal']),
                    numeric: true,
                  ),
                  QuotationFact(
                    'Discounts · $currency',
                    quotationLabel(snapshot['discount_total']),
                    numeric: true,
                  ),
                  QuotationFact(
                    'Tax · $currency',
                    quotationLabel(snapshot['tax_total']),
                    numeric: true,
                  ),
                  QuotationFact(
                    'Grand total · $currency',
                    quotationLabel(snapshot['grand_total']),
                    numeric: true,
                    prominent: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Base total ${snapshot['base_currency_code']}: ${snapshot['base_total']}  ·  FX ${snapshot['exchange_rate']}  ·  Rate date ${snapshot['rate_date']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (snapshot['notes'] != null) ...[
          const SizedBox(height: 20),
          Text('Notes', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(quotationLabel(snapshot['notes'])),
        ],
      ],
    );
  }
}

class QuotationFact extends StatelessWidget {
  const QuotationFact(
    this.label,
    this.value, {
    this.numeric = false,
    this.prominent = false,
    this.valueWidget,
    super.key,
  });
  final String label;
  final String value;
  final bool numeric;
  final bool prominent;
  final Widget? valueWidget;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.jentraColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        if (valueWidget != null)
          valueWidget!
        else
          SelectableText(
            value,
            style:
                (prominent
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.bodyMedium)
                    ?.copyWith(
                      fontFamily: numeric ? JentraTypography.monoFamily : null,
                      fontWeight: prominent ? FontWeight.w600 : null,
                    ),
          ),
      ],
    ),
  );
}
