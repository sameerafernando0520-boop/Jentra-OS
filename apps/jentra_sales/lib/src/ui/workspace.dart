import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../models.dart';
import '../sales_controller.dart';
import 'components.dart';
import 'today.dart';
import 'customers.dart';
import 'orders.dart';
import 'catalogue.dart';
import 'visits.dart';
import 'order_editor.dart';

class SalesWorkspace extends StatelessWidget {
  const SalesWorkspace(this.controller, {super.key});
  final SalesController controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final phone = box.maxWidth < 700;
      final extended =
          box.maxWidth >= 1180 &&
          MediaQuery.textScalerOf(context).scale(1) < 1.6;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (!phone) _SalesNavigation(controller, extended: extended),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(controller, phone: phone),
                    if (controller.notice != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SalesNotice(controller.notice!),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1560),
                          child: SingleChildScrollView(
                            key: PageStorageKey(controller.page),
                            padding: EdgeInsets.all(phone ? 16 : 32),
                            child: switch (controller.page) {
                              SalesPage.today => SalesToday(controller),
                              SalesPage.customers => SalesCustomers(controller),
                              SalesPage.orders => SalesOrders(controller),
                              SalesPage.catalogue => SalesCatalogue(controller),
                              SalesPage.visits => SalesVisits(controller),
                              SalesPage.deliveries => SalesOrders(
                                controller,
                                deliveriesOnly: true,
                              ),
                              SalesPage.more => _SalesMore(controller),
                            },
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
        bottomNavigationBar: phone
            ? NavigationBar(
                selectedIndex: switch (controller.page) {
                  SalesPage.today => 0,
                  SalesPage.customers => 1,
                  SalesPage.orders => 2,
                  _ => 3,
                },
                onDestinationSelected: (i) => controller.go(
                  [
                    SalesPage.today,
                    SalesPage.customers,
                    SalesPage.orders,
                    SalesPage.more,
                  ][i],
                ),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.space_dashboard_outlined),
                    label: 'Today',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    label: 'Customers',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: 'Orders',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.more_horiz),
                    label: 'More',
                  ),
                ],
              )
            : null,
      );
    },
  );
}

class _SalesNavigation extends StatelessWidget {
  const _SalesNavigation(this.c, {required this.extended});
  final SalesController c;
  final bool extended;
  @override
  Widget build(BuildContext context) => Container(
    width: extended ? 232 : 84,
    color: salesNavy,
    child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(extended ? 24 : 20, 32, 16, 28),
                child: extended
                    ? const JentraBrandLockup(size: 34, inverse: true)
                    : const JentraBrandMark(size: 34, inverse: true),
              ),
              if (extended)
                const Padding(
                  padding: EdgeInsets.fromLTRB(28, 8, 24, 20),
                  child: Text(
                    'SALES WORKSPACE',
                    style: TextStyle(
                      color: Color(0xFFACBECE),
                      letterSpacing: 1.5,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SliverList.list(
          children: [
            for (final page in SalesPage.values)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: extended ? 16 : 12,
                  vertical: 3,
                ),
                child: Tooltip(
                  message: pageLabel(page),
                  child: Material(
                    color: c.page == page
                        ? const Color(0xFF163A5D)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => c.go(page),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: extended ? 14 : 2,
                          vertical: 15,
                        ),
                        child: Flex(
                          direction: extended ? Axis.horizontal : Axis.vertical,
                          children: [
                            Icon(
                              pageIcon(page),
                              size: 22,
                              color: c.page == page
                                  ? const Color(0xFF83C4FF)
                                  : const Color(0xFFACBECE),
                            ),
                            if (!extended) ...[
                              const SizedBox(height: 6),
                              Text(
                                pageLabel(page),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFACBECE),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                            if (extended) ...[
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  pageLabel(page),
                                  style: TextStyle(
                                    color: c.page == page
                                        ? Colors.white
                                        : const Color(0xFFACBECE),
                                    fontWeight: c.page == page
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (page == SalesPage.orders)
                                Text(
                                  '${c.orders.length}',
                                  style: const TextStyle(
                                    color: Color(0xFFACBECE),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (extended)
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF102E49),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.science_outlined,
                            color: Color(0xFF83C4FF),
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Preview workspace',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Sample data. Explore every step without creating real orders.',
                        style: TextStyle(
                          color: Color(0xFFACBECE),
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Tooltip(
                  message: 'Exit preview',
                  child: !extended
                      ? IconButton(
                          tooltip: 'Exit preview',
                          onPressed: c.leave,
                          icon: const Icon(
                            Icons.logout,
                            color: Color(0xFFACBECE),
                            size: 20,
                          ),
                        )
                      : TextButton.icon(
                          onPressed: c.leave,
                          icon: const Icon(
                            Icons.logout,
                            color: Color(0xFFACBECE),
                            size: 18,
                          ),
                          label: Text(
                            extended ? 'Exit preview' : '',
                            style: const TextStyle(
                              color: Color(0xFFACBECE),
                              fontSize: 12,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar(this.c, {required this.phone});
  final SalesController c;
  final bool phone;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: phone ? 16 : 32, vertical: 16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: Row(
      children: [
        if (phone) ...[
          const JentraBrandMark(size: 26),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                phone
                    ? 'Jentra Sales'
                    : 'Sales workspace  /  ${pageLabel(c.page)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Preview · Sample company',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (!phone) ...[
          const Icon(Icons.calendar_today_outlined, size: 16),
          const SizedBox(width: 8),
          Text(
            DateFormat('EEE, d MMM yyyy').format(c.now()),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 20),
        ],
        IconButton(
          tooltip: c.themeMode == ThemeMode.dark
              ? 'Switch to light theme'
              : 'Switch to dark theme',
          onPressed: c.toggleTheme,
          icon: Icon(
            c.themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            size: 20,
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Workspace menu',
          icon: CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              'AP',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          onSelected: (v) {
            if (v == 'exit') {
              c.leave();
            } else {
              c.go(SalesPage.more);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'account',
              child: Text('Preview account & settings'),
            ),
            PopupMenuItem(value: 'exit', child: Text('Exit preview')),
          ],
        ),
      ],
    ),
  );
}

class _SalesMore extends StatelessWidget {
  const _SalesMore(this.c);
  final SalesController c;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const PageHeading(
        'Your workspace',
        'Everything you need for the next conversation.',
      ),
      SalesPanel(
        child: Column(
          children: [
            for (final page in [
              SalesPage.catalogue,
              SalesPage.visits,
              SalesPage.deliveries,
            ])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: Icon(pageIcon(page)),
                title: Text(pageLabel(page)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => c.go(page),
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              leading: const Icon(Icons.drafts_outlined),
              title: const Text('Local order drafts'),
              subtitle: Text(
                '${c.orders.where((o) => o.local).length} saved · expires after 24 hours',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => c.go(SalesPage.orders),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark appearance'),
              value: c.themeMode == ThemeMode.dark,
              onChanged: (_) => c.toggleTheme(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const SalesNotice(
        'This first release is an interactive Sales preview. Company access, live order submission and verified email confirmations will become available after the portfolio backend rollout. Preview visits stay in this session; saved order drafts use protected storage.',
      ),
      const SizedBox(height: 24),
      const SalesPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle('Built around your next step'),
            Text(
              'Customer acceptance, company approval and delivery acknowledgement are tracked separately. A local draft is never a confirmed order. Your discount request is reviewed by your company.',
            ),
            SizedBox(height: 20),
            Text('Jentra Sales · 0.1.3+4 Development'),
            SizedBox(height: 8),
            Text(
              'English interface · Sinhala and Tamil are planned. Collections and return requests follow in a later release.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: c.leave,
        icon: const Icon(Icons.logout),
        label: const Text('Exit preview'),
      ),
    ],
  );
}

Widget newOrderAction(
  BuildContext context,
  SalesController c, {
  SalesCustomer? customer,
}) => FilledButton.icon(
  onPressed: () => openOrderEditor(context, c, customer: customer),
  icon: const Icon(Icons.add, size: 20),
  label: const Text('New order'),
);
