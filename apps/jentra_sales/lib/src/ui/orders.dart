import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../sales_controller.dart';
import 'components.dart';
import 'order_editor.dart';

class SalesOrders extends StatefulWidget {
  const SalesOrders(this.c, {this.deliveriesOnly = false, super.key});
  final SalesController c;
  final bool deliveriesOnly;
  @override
  State<SalesOrders> createState() => _SalesOrdersState();
}

class _SalesOrdersState extends State<SalesOrders> {
  String _query = '', _filter = 'All orders';
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final items = c.orders
        .where(
          (o) =>
              (!widget.deliveriesOnly ||
                  [
                    'Dispatched',
                    'Partial delivery',
                  ].contains(o.deliveryState)) &&
              (_filter == 'All orders' || o.status == _filter) &&
              '${o.id} ${c.customer(o.customerId).name}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          widget.deliveriesOnly
              ? 'Every delivery, in view.'
              : 'Orders, without loose ends.',
          widget.deliveriesOnly
              ? 'Track dispatch and partial deliveries. Recipient acknowledgement is a separate step.'
              : 'Follow each order from the first draft to the final handover.',
          action: widget.deliveriesOnly
              ? null
              : FilledButton.icon(
                  onPressed: () => openOrderEditor(context, c),
                  icon: const Icon(Icons.add),
                  label: const Text('New order'),
                ),
        ),
        if (widget.deliveriesOnly) ...[
          const SalesNotice(
            'Sample delivery states are shown below. Verified recipient email links, exact received quantities and acknowledgement become available with the company rollout.',
          ),
          const SizedBox(height: 24),
        ],
        SalesPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search orders',
                  hintText: 'Order number or customer',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 20),
              if (!widget.deliveriesOnly)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in [
                      'All orders',
                      'Awaiting customer',
                      'Company review',
                      'Local draft',
                    ])
                      ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              if (items.isEmpty)
                const SalesEmpty(
                  'Nothing here yet',
                  'Try another filter, or start a new order.',
                ),
              for (final order in items) OrderRow(c, order),
            ],
          ),
        ),
      ],
    );
  }
}

class OrderRow extends StatelessWidget {
  const OrderRow(this.c, this.order, {super.key});
  final SalesController c;
  final SalesOrder order;
  @override
  Widget build(BuildContext context) {
    final customer = c.customer(order.customerId);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openOrder(context, c, order),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final compact =
                box.maxWidth < 580 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final name = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${order.local ? 'DRAFT-${order.id.substring(0, 6).toUpperCase()}' : order.id} · ${DateFormat('d MMM').format(order.date)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name,
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(order.status),
                          Text(
                            money(order.subtotal.toDecimalString()),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      CustomerAvatar(customer, size: 36),
                      const SizedBox(width: 12),
                      Expanded(flex: 5, child: name),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StatusPill(order.status),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        money(order.subtotal.toDecimalString()),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

Future<void> openOrder(
  BuildContext context,
  SalesController c,
  SalesOrder order,
) => salesDialog<void>(context, _OrderDetail(c, order));

class _OrderDetail extends StatelessWidget {
  const _OrderDetail(this.c, this.order);
  final SalesController c;
  final SalesOrder order;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                order.local ? 'Local order draft' : order.id,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Close order',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.customer(order.customerId).name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${DateFormat('d MMM yyyy').format(order.date)} · ${order.local ? 'Saved on this device' : 'Sample order'}',
              ),
              const SizedBox(height: 24),
              if (order.local) ...[
                const SalesNotice(
                  'Saved on this device for up to 24 hours. This draft has not been submitted. Tax, credit, prices and stock require online company review.',
                ),
                const SizedBox(height: 24),
              ],
              LayoutBuilder(
                builder: (context, box) => Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final state in [
                      (
                        'Customer response',
                        order.customerState,
                        Icons.person_outline,
                      ),
                      (
                        'Company decision',
                        order.companyState,
                        Icons.business_outlined,
                      ),
                      (
                        'Delivery',
                        order.deliveryState,
                        Icons.local_shipping_outlined,
                      ),
                    ])
                      SizedBox(
                        width:
                            box.maxWidth > 680 &&
                                MediaQuery.textScalerOf(context).scale(1) < 1.5
                            ? (box.maxWidth - 32) / 3
                            : box.maxWidth,
                        child: SalesPanel(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(state.$3, size: 22),
                              const SizedBox(height: 12),
                              Text(
                                state.$1,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              StatusPill(state.$2),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const SectionTitle('Order lines'),
              for (final line in order.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.product.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          Text(
                            '${line.quantity} ${line.product.unit} × ${money(line.product.price)}',
                          ),
                          Text(
                            money(line.total.toDecimalString()),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Subtotal  ${money(order.subtotal.toDecimalString())}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Tax and final total: determined at online review.'),
              if (parseDiscount(order.discount).isPositive) ...[
                const SizedBox(height: 20),
                SalesNotice(
                  'Discount requested: ${order.discount}%. ${order.discountReason}. A request does not change the approved selling price.',
                ),
              ],
              if (order.reference.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Customer reference: ${order.reference}'),
              ],
              if (order.requestedDate.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Requested delivery: ${order.requestedDate}'),
              ],
              if (order.notes.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionTitle('Notes'),
                Text(order.notes),
              ],
              const SizedBox(height: 28),
              const SectionTitle('What happens next'),
              const Text(
                'Review commercial terms online. The customer responds to the exact revision, the company makes its own approval decision, and the warehouse controls dispatch. Each partial delivery has its own recipient acknowledgement.',
              ),
              const SizedBox(height: 16),
              const SalesNotice(
                'Verified email requests are not active in this preview. No customer has been contacted.',
              ),
            ],
          ),
        ),
      ),
      if (order.local)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final remove = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remove this local draft?'),
                      content: const Text(
                        'The saved draft will be removed from this preview on this device.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Keep draft'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remove draft'),
                        ),
                      ],
                    ),
                  );
                  if (remove != true) return;
                  try {
                    await c.removeDraft(order.id);
                    if (context.mounted) Navigator.pop(context);
                  } on Object {
                    if (context.mounted) {
                      salesToast(
                        context,
                        'The draft could not be removed. Try again.',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove draft'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  openOrderEditor(context, c, draft: order);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Continue editing'),
              ),
            ],
          ),
        ),
    ],
  );
}
