import 'package:flutter/material.dart';

import '../models.dart';
import '../sales_controller.dart';
import 'components.dart';
import 'orders.dart';
import 'order_editor.dart';

class SalesCustomers extends StatefulWidget {
  const SalesCustomers(this.c, {super.key});
  final SalesController c;
  @override
  State<SalesCustomers> createState() => _SalesCustomersState();
}

class _SalesCustomersState extends State<SalesCustomers> {
  String _query = '';
  SalesCustomer? _selected;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final items = c.customers
        .where(
          (v) => '${v.name} ${v.area} ${v.contact}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'Your customers',
          '${c.customers.length} customers in your sample portfolio. Every connection counts.',
        ),
        LayoutBuilder(
          builder: (context, box) {
            final split =
                box.maxWidth >= 820 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5;
            final selected = items.any((item) => item.id == _selected?.id)
                ? _selected
                : items.firstOrNull;
            final list = SalesPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search customers',
                      hintText: 'Name, area or contact',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${items.length} customers',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const SalesEmpty(
                      'No matching customers',
                      'Try a different name, area or contact.',
                    ),
                  for (final customer in items)
                    Material(
                      color: selected?.id == customer.id && split
                          ? Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: .45)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => split
                            ? setState(() => _selected = customer)
                            : openCustomer(context, c, customer),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              CustomerAvatar(customer),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customer.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${customer.area} · ${customer.contact}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
            return split
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: list),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 6,
                        child: selected == null
                            ? const SalesEmpty(
                                'Select a customer',
                                'Choose a customer to see their details.',
                              )
                            : CustomerDetail(c, selected),
                      ),
                    ],
                  )
                : list;
          },
        ),
      ],
    );
  }
}

Future<void> openCustomer(
  BuildContext context,
  SalesController c,
  SalesCustomer customer,
) => salesDialog<void>(
  context,
  Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Customer details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Close customer',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: CustomerDetail(c, customer),
        ),
      ),
    ],
  ),
);

class CustomerDetail extends StatelessWidget {
  const CustomerDetail(this.c, this.customer, {super.key});
  final SalesController c;
  final SalesCustomer customer;
  @override
  Widget build(BuildContext context) => SalesPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomerAvatar(customer, size: 64),
        const SizedBox(height: 20),
        Text(
          customer.name,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 8),
        Text(
          customer.area,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => openOrderEditor(context, c, customer: customer),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New order'),
            ),
            OutlinedButton.icon(
              onPressed: () => salesToast(
                context,
                'Preview contact: ${customer.contact}. Contact sharing is available with company access.',
              ),
              icon: const Icon(Icons.contact_mail_outlined, size: 18),
              label: const Text('Contact details'),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Divider(),
        ),
        const SectionTitle('Customer information'),
        _DetailLine(Icons.person_outline, 'Primary contact', customer.contact),
        _DetailLine(Icons.mail_outline, 'Email', customer.email),
        _DetailLine(
          Icons.location_on_outlined,
          'Delivery address',
          customer.address,
        ),
        _DetailLine(
          Icons.credit_card_outlined,
          'Payment terms',
          customer.terms,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(),
        ),
        Text(
          'Sample outstanding balance',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          money(customer.outstanding),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Illustrative only. Posted invoices and allocations determine a real balance.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 28),
        const SectionTitle('Recent orders'),
        if (!c.orders.any((o) => o.customerId == customer.id))
          const Text(
            'No orders yet. Start a conversation and build your first order.',
          ),
        for (final order
            in c.orders.where((o) => o.customerId == customer.id).take(5))
          OrderRow(c, order),
      ],
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              SelectableText(value),
            ],
          ),
        ),
      ],
    ),
  );
}
