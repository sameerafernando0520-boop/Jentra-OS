import 'package:flutter/material.dart';

import '../models.dart';
import '../sales_controller.dart';
import 'components.dart';
import 'workspace.dart';
import 'orders.dart';
import 'customers.dart';
import 'visits.dart';

class SalesToday extends StatelessWidget {
  const SalesToday(this.c, {super.key});
  final SalesController c;
  @override
  Widget build(BuildContext context) {
    final next = c.visits.where((v) => v.state == 'Scheduled').firstOrNull;
    final customer = next == null ? null : c.customer(next.customerId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          'A good day to connect.',
          'Here’s what’s happening across your sample portfolio.',
          action: newOrderAction(context, c),
        ),
        _Metrics(c),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, box) {
            final main = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: salesNavy,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.north_east_rounded,
                            size: 16,
                            color: Color(0xFF78D5CF),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'YOUR NEXT CONNECTION',
                              style: TextStyle(
                                color: Color(0xFFACBECE),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        customer?.name ?? 'You’re all caught up.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        next == null
                            ? 'Start a new order or get to know your customers.'
                            : '${next.time}  ·  ${customer!.area}  ·  ${next.purpose}',
                        style: const TextStyle(
                          color: Color(0xFFACBECE),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: salesNavy,
                            ),
                            onPressed: () => customer == null
                                ? c.go(SalesPage.customers)
                                : openCustomer(context, c, customer),
                            icon: const Icon(Icons.person_outline, size: 18),
                            label: const Text('View customer'),
                          ),
                          if (next != null)
                            TextButton.icon(
                              onPressed: () => openVisit(context, c, next),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFC8E3FF),
                              ),
                              label: const Text('Visit details'),
                              icon: const Icon(Icons.arrow_forward, size: 16),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SalesPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        'Orders to follow up',
                        action: TextButton(
                          onPressed: () => c.go(SalesPage.orders),
                          child: const Text('View all orders →'),
                        ),
                      ),
                      for (final order in c.orders.take(4)) OrderRow(c, order),
                    ],
                  ),
                ),
              ],
            );
            final aside = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SalesPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        'On your agenda',
                        action: IconButton(
                          tooltip: 'All visits',
                          onPressed: () => c.go(SalesPage.visits),
                          icon: const Icon(Icons.arrow_forward, size: 20),
                        ),
                      ),
                      for (final visit in c.visits.take(3)) VisitRow(c, visit),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => planVisit(context, c),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Plan a visit'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SalesPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle('Pick up where you left off'),
                      const Text(
                        'Keep the details. Come back with a clear next step.',
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.edit_note_rounded),
                        title: const Text('Your local drafts'),
                        subtitle: Text(
                          '${c.orders.where((o) => o.local).length} saved on this device',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => c.go(SalesPage.orders),
                      ),
                    ],
                  ),
                ),
              ],
            );
            return box.maxWidth >= 1000 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.5
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: main),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: aside),
                    ],
                  )
                : Column(children: [main, const SizedBox(height: 24), aside]);
          },
        ),
        const SizedBox(height: 28),
        SalesPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                'Stay close to your customers',
                action: TextButton(
                  onPressed: () => c.go(SalesPage.customers),
                  child: const Text('Open portfolio →'),
                ),
              ),
              LayoutBuilder(
                builder: (context, box) => Wrap(
                  spacing: 20,
                  runSpacing: 16,
                  children: [
                    for (final customer in c.customers.take(3))
                      SizedBox(
                        width:
                            box.maxWidth > 760 &&
                                MediaQuery.textScalerOf(context).scale(1) < 1.5
                            ? (box.maxWidth - 40) / 3
                            : box.maxWidth,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => openCustomer(context, c, customer),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                CustomerAvatar(customer),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        customer.area,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'PREVIEW WORKSPACE  ·  All customers, orders and amounts shown here are samples.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics(this.c);
  final SalesController c;
  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        'Open orders',
        '${c.orders.where((o) => !o.local).length}',
        'Across your sample portfolio',
        Icons.receipt_long_outlined,
      ),
      (
        'Awaiting customer',
        '${c.orders.where((o) => o.customerState == 'Awaiting response').length}',
        'A conversation to follow up',
        Icons.forum_outlined,
      ),
      (
        'Visits planned',
        '${c.visits.where((v) => v.state == 'Scheduled').length}',
        'Your next connections',
        Icons.event_available_outlined,
      ),
      (
        'Local drafts',
        '${c.orders.where((o) => o.local).length}',
        'Ready when you are',
        Icons.edit_note_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 900
            ? 4
            : box.maxWidth >= 300 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.6
            ? 2
            : 1;
        return SalesPanel(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            children: [
              for (final m in metrics)
                SizedBox(
                  width: (box.maxWidth - 18) / columns,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m.$1,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Icon(
                              m.$4,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          m.$2,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          m.$3,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
