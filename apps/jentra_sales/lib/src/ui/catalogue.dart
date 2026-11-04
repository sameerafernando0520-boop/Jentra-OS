import 'package:flutter/material.dart';

import '../sales_controller.dart';
import 'components.dart';
import 'order_editor.dart';
import '../models.dart';

class SalesCatalogue extends StatefulWidget {
  const SalesCatalogue(this.c, {super.key});
  final SalesController c;
  @override
  State<SalesCatalogue> createState() => _SalesCatalogueState();
}

class _SalesCatalogueState extends State<SalesCatalogue> {
  String _query = '', _category = 'All products';
  @override
  Widget build(BuildContext context) {
    final items = widget.c.products
        .where(
          (p) =>
              (_category == 'All products' || p.category == _category) &&
              '${p.name} ${p.code}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          'A catalogue worth knowing.',
          'Find the right product for your next customer conversation.',
        ),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search catalogue',
            hintText: 'Product name or code',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in [
              'All products',
              ...widget.c.products.map((p) => p.category).toSet(),
            ])
              ChoiceChip(
                label: Text(category),
                selected: category == _category,
                onSelected: (_) => setState(() => _category = category),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const SalesNotice(
          'Preview catalogue · Sample prices and stock. Availability is advisory and is not a reservation. Current company prices and stock must be reviewed online.',
        ),
        const SizedBox(height: 24),
        if (items.isEmpty)
          const SalesEmpty(
            'No matching products',
            'Search by name or product code, or change the category.',
          ),
        LayoutBuilder(
          builder: (context, box) {
            final count = MediaQuery.textScalerOf(context).scale(1) > 1.5
                ? 1
                : box.maxWidth > 1050
                ? 3
                : box.maxWidth > 620
                ? 2
                : 1;
            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                for (final p in items)
                  SizedBox(
                    width: (box.maxWidth - 20 * (count - 1)) / count,
                    child: SalesPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ProductIcon(p, size: 72),
                              const Spacer(),
                              Text(
                                p.category,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            p.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${p.code} · ${p.unit}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            money(p.price),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${p.availability} · sample',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => openOrderEditor(
                                context,
                                widget.c,
                                product: p,
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text(
                                'Start order with this product',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
