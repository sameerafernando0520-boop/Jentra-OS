import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../models.dart';

const salesNavy = Color(0xFF061B31);
const salesBlue = Color(0xFF0064D9);

ThemeData salesTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? JentraTheme.dark()
      : JentraTheme.light();
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 15,
        height: 1.4,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(fontSize: 14),
      hintStyle: const TextStyle(fontSize: 14),
    ),
  );
}

String pageLabel(SalesPage page) => switch (page) {
  SalesPage.today => 'Today',
  SalesPage.customers => 'Customers',
  SalesPage.orders => 'Orders',
  SalesPage.catalogue => 'Catalogue',
  SalesPage.visits => 'Visits',
  SalesPage.deliveries => 'Deliveries',
  SalesPage.more => 'More',
};
IconData pageIcon(SalesPage page) => switch (page) {
  SalesPage.today => Icons.space_dashboard_outlined,
  SalesPage.customers => Icons.people_outline_rounded,
  SalesPage.orders => Icons.receipt_long_outlined,
  SalesPage.catalogue => Icons.inventory_2_outlined,
  SalesPage.visits => Icons.event_available_outlined,
  SalesPage.deliveries => Icons.local_shipping_outlined,
  SalesPage.more => Icons.more_horiz_rounded,
};

class SalesPanel extends StatelessWidget {
  const SalesPanel({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {this.action, super.key});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child:
            box.maxWidth > 620 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5
            ? Row(
                children: [
                  Expanded(child: text),
                  if (action != null) ...[const SizedBox(width: 20), action!],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  text,
                  if (action != null) ...[const SizedBox(height: 16), action!],
                ],
              ),
      );
    },
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {this.action, super.key});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Semantics(
          header: true,
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JentraSemanticColors>()!;
    final positive = ['Accepted', 'Approved', 'Completed'].contains(text);
    final attention =
        text.contains('review') ||
        text.contains('Review') ||
        text.contains('Awaiting') ||
        text.contains('Partial');
    final fg = positive
        ? colors.success
        : attention
        ? colors.warning
        : colors.info;
    final bg = positive
        ? colors.successSurface
        : attention
        ? colors.warningSurface
        : colors.infoSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar(this.customer, {this.size = 44, super.key});
  final SalesCustomer customer;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      customer.initials,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        fontSize: size * .3,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class ProductIcon extends StatelessWidget {
  const ProductIcon(this.product, {this.size = 56, super.key});
  final SalesProduct product;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      switch (product.symbol) {
        'mug' => Icons.coffee_outlined,
        'flask' => Icons.water_drop_outlined,
        'towel' => Icons.dry_cleaning_outlined,
        'basket' => Icons.shopping_basket_outlined,
        'desk' => Icons.desk_outlined,
        _ => Icons.weekend_outlined,
      },
      size: size * .5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class SalesNotice extends StatelessWidget {
  const SalesNotice(this.text, {this.icon = Icons.info_outline, super.key});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SalesEmpty extends StatelessWidget {
  const SalesEmpty(this.title, this.message, {this.action, super.key});
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

void salesToast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

Future<T?> salesDialog<T>(BuildContext context, Widget child) => showDialog<T>(
  context: context,
  builder: (context) => MediaQuery.sizeOf(context).width < 620
      ? Dialog.fullscreen(child: child)
      : Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 860),
            child: child,
          ),
        ),
);
