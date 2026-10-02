import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';
import '../operations/operational_dashboard.dart';
import '../tenant/tenant_onboarding_screen.dart';
import '../tenant/stock_opening_access.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(tenantListProvider);
    if (tenants.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tenants.hasError) {
      return Center(
        child: JentraEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your businesses',
          description:
              'Check the connection and try loading your tenant context again.',
          action: JentraPrimaryButton(
            label: 'Try again',
            onPressed: () => ref.invalidate(tenantListProvider),
          ),
        ),
      );
    }
    if (tenants.value?.isEmpty ?? true) {
      return const SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(24),
              child: StockOpeningInvitationInbox(),
            ),
            TenantOnboardingScreen(),
          ],
        ),
      );
    }
    return ref.watch(foundationGatewayProvider) == null
        ? const _DashboardContent()
        : const OperationalDashboard();
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    padding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 700
          ? JentraSpacing.x4
          : JentraSpacing.x6,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StockOpeningInvitationInbox(
          key: ValueKey(ref.watch(authenticatedActorProvider).value),
        ),
        const _DashboardHeader(),
        const SizedBox(height: JentraSpacing.x6),
        const _KpiGrid(),
        const SizedBox(height: JentraSpacing.x5),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final stacked = constraints.maxWidth < 1020 * textScale;
            final chart = const _CashPositionPanel();
            final approvals = const _ApprovalQueue();
            if (stacked) {
              return Column(
                children: [
                  chart,
                  SizedBox(height: JentraSpacing.x5),
                  approvals,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: chart),
                SizedBox(width: JentraSpacing.x5),
                Expanded(child: approvals),
              ],
            );
          },
        ),
        const SizedBox(height: JentraSpacing.x5),
        const _OperatingFlows(),
        const SizedBox(height: JentraSpacing.x5),
        const _RecentActivity(),
        const SizedBox(height: JentraSpacing.x6),
      ],
    ),
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: JentraColors.brandNavy,
      borderRadius: BorderRadius.circular(JentraRadii.card),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(
          height: 3,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: JentraColors.brandGradient),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(JentraSpacing.x6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR BUSINESS, IN PERSPECTIVE',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: JentraColors.darkTextSecondary,
                                letterSpacing: 1.8,
                              ),
                        ),
                        const SizedBox(height: JentraSpacing.x3),
                        Text(
                          'Good morning, Shehan',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: JentraSpacing.x2),
                        Text(
                          'One connected view of cash, decisions, and daily operations.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: JentraColors.darkTextSecondary),
                        ),
                        const SizedBox(height: JentraSpacing.x5),
                        Wrap(
                          spacing: JentraSpacing.x3,
                          runSpacing: JentraSpacing.x3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const JentraStatusBadge(
                              label: 'Preview metrics',
                              tone: JentraStatusTone.info,
                            ),
                            Text(
                              'Sample data · 01 Aug – 31 Aug 2026',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: JentraColors.darkTextSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (constraints.maxWidth > 700 * textScale) ...[
                    const SizedBox(width: JentraSpacing.x8),
                    const ExcludeSemantics(
                      child: JentraBrandMark(size: 88, inverse: true),
                    ),
                    const SizedBox(width: JentraSpacing.x3),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth >= 1000 * textScale
          ? 4
          : constraints.maxWidth >= 480 * textScale
          ? 2
          : 1;
      const gap = JentraSpacing.x4;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final kpi in const [
            (
              'Net revenue',
              'LKR 12.84M',
              '+8.4% vs last month',
              Icons.trending_up,
              JentraStatusTone.success,
            ),
            (
              'Cash available',
              'LKR 6.28M',
              '14.2 weeks runway',
              Icons.account_balance_wallet_outlined,
              JentraStatusTone.success,
            ),
            (
              'Receivables due',
              'LKR 3.41M',
              'LKR 620K overdue',
              Icons.schedule_outlined,
              JentraStatusTone.warning,
            ),
            (
              'Gross margin',
              '31.8%',
              '+1.9 pts this month',
              Icons.donut_large_outlined,
              JentraStatusTone.success,
            ),
          ])
            SizedBox(
              width: width,
              child: JentraKpiCard(
                label: kpi.$1,
                value: kpi.$2,
                helper: kpi.$3,
                icon: kpi.$4,
                tone: kpi.$5,
              ),
            ),
        ],
      );
    },
  );
}

class _CashPositionPanel extends StatelessWidget {
  const _CashPositionPanel();

  @override
  Widget build(BuildContext context) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JentraSectionHeader(
          title: 'Cash position',
          description: '13-week actual and forecast · sample series',
          trailing: JentraStatusBadge(
            label: 'LKR',
            tone: JentraStatusTone.neutral,
          ),
        ),
        const SizedBox(height: JentraSpacing.x5),
        Semantics(
          label:
              'Illustrative cash position in LKR millions. '
              'Solid blue shows actual values through week 8. '
              'Dashed teal shows the forecast from week 8 to week 13. '
              'This is sample data, not a live business forecast.',
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final labels = constraints.maxWidth < 500 * scale
                    ? const ['W1', 'W7', 'W13']
                    : const ['W1', 'W3', 'W5', 'W7', 'W9', 'W11', 'W13'];
                return Column(
                  children: [
                    SizedBox(
                      height: 190 + 24 * scale,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final label in const [
                                '8M',
                                '6M',
                                '4M',
                                '2M',
                                '0',
                              ])
                                Text(
                                  label,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color:
                                            context.jentraColors.textSecondary,
                                        fontFamily: JentraTypography.monoFamily,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(width: JentraSpacing.x3),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 7 * scale,
                              ),
                              child: CustomPaint(
                                painter: _CashChartPainter(
                                  lineColor: context.jentraColors.action,
                                  forecastColor:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? JentraColors.cyan500
                                      : JentraColors.teal600,
                                  gridColor: context.jentraColors.border,
                                  fillColor: context.jentraColors.action
                                      .withValues(alpha: .14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: JentraSpacing.x3),
                    Padding(
                      padding: EdgeInsets.only(left: 32 * scale),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final label in labels)
                            Text(
                              label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: context.jentraColors.textSecondary,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: JentraSpacing.x5),
        Wrap(
          spacing: JentraSpacing.x5,
          runSpacing: JentraSpacing.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Legend(color: context.jentraColors.action, label: 'Actual'),
            _Legend(
              color: Theme.of(context).brightness == Brightness.dark
                  ? JentraColors.cyan500
                  : JentraColors.teal600,
              label: 'Forecast',
              dashed: true,
            ),
            Text(
              'Illustrative forecast',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: context.jentraColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CashChartPainter extends CustomPainter {
  const _CashChartPainter({
    required this.lineColor,
    required this.forecastColor,
    required this.gridColor,
    required this.fillColor,
  });

  final Color lineColor;
  final Color forecastColor;
  final Color gridColor;
  final Color fillColor;

  static const values = <double>[
    .38,
    .45,
    .42,
    .55,
    .61,
    .58,
    .68,
    .63,
    .71,
    .75,
    .70,
    .78,
    .82,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = gridColor;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Offset point(int index) => Offset(
      size.width * index / (values.length - 1),
      size.height * (1 - values[index]),
    );

    final actual = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i <= 7; i++) {
      actual.lineTo(point(i).dx, point(i).dy);
    }
    final fill = Path.from(actual)
      ..lineTo(point(7).dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillColor, fillColor.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      actual,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final forecast = Path()..moveTo(point(7).dx, point(7).dy);
    for (var i = 8; i < values.length; i++) {
      forecast.lineTo(point(i).dx, point(i).dy);
    }
    final forecastPaint = Paint()
      ..color = forecastColor
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final metric in forecast.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 11) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 5, metric.length)),
          forecastPaint,
        );
      }
    }
    canvas.drawCircle(point(7), 4, Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant _CashChartPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.forecastColor != forecastColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.fillColor != fillColor;
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 20,
        child: Row(
          children: [
            for (var i = 0; i < (dashed ? 3 : 1); i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: JentraSpacing.x2),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

class _ApprovalQueue extends StatelessWidget {
  const _ApprovalQueue();

  @override
  Widget build(BuildContext context) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JentraSectionHeader(
          title: 'Needs your attention',
          description: 'Example approvals and exceptions',
          trailing: JentraStatusBadge(
            label: '7 open',
            tone: JentraStatusTone.warning,
          ),
        ),
        const SizedBox(height: JentraSpacing.x3),
        for (final item in const [
          (
            'Purchase order',
            'PO-2026-00842',
            'LKR 486,250',
            Icons.shopping_bag_outlined,
          ),
          (
            'Supplier payment',
            'PAY-2026-00318',
            'LKR 218,900',
            Icons.payments_outlined,
          ),
          (
            'Expense claim',
            'EXP-2026-00194',
            'LKR 42,700',
            Icons.receipt_outlined,
          ),
          (
            'Stock adjustment',
            'ADJ-2026-00027',
            '14 items',
            Icons.inventory_2_outlined,
          ),
        ])
          _ApprovalItem(
            type: item.$1,
            reference: item.$2,
            amount: item.$3,
            icon: item.$4,
          ),
        const SizedBox(height: JentraSpacing.x3),
        Text(
          'Preview queue · 4 of 7 example items',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.jentraColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _ApprovalItem extends StatelessWidget {
  const _ApprovalItem({
    required this.type,
    required this.reference,
    required this.amount,
    required this.icon,
  });

  final String type;
  final String reference;
  final String amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: JentraSpacing.x3),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.jentraColors.border)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final stackAmount = constraints.maxWidth < 410 * scale;
        final amountLabel = Text(
          amount,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontFamily: JentraTypography.monoFamily,
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.jentraColors.infoSurface,
                borderRadius: BorderRadius.circular(JentraRadii.control),
              ),
              child: Icon(icon, size: 18, color: context.jentraColors.info),
            ),
            const SizedBox(width: JentraSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    reference,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.jentraColors.textSecondary,
                      fontFamily: JentraTypography.monoFamily,
                    ),
                  ),
                  if (stackAmount) ...[
                    const SizedBox(height: JentraSpacing.x1),
                    amountLabel,
                  ],
                ],
              ),
            ),
            if (!stackAmount) ...[
              const SizedBox(width: JentraSpacing.x3),
              amountLabel,
            ],
          ],
        );
      },
    ),
  );
}

class _OperatingFlows extends StatelessWidget {
  const _OperatingFlows();

  @override
  Widget build(BuildContext context) => JentraPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const JentraSectionHeader(
          title: 'Operating flows',
          description:
              'Median cycle time and handoff health across the business',
          trailing: JentraStatusBadge(
            label: 'Sample model',
            tone: JentraStatusTone.neutral,
          ),
        ),
        const SizedBox(height: JentraSpacing.x5),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = constraints.maxWidth >= 1000 * scale
                ? 4
                : constraints.maxWidth >= 480 * scale
                ? 2
                : 1;
            const gap = JentraSpacing.x3;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final flow in const [
                  ('Lead to cash', '4.8 days', '92%', JentraStatusTone.success),
                  (
                    'Procure to pay',
                    '6.2 days',
                    '84%',
                    JentraStatusTone.warning,
                  ),
                  (
                    'Inventory to ledger',
                    '18 min',
                    '98%',
                    JentraStatusTone.success,
                  ),
                  (
                    'Service to resolution',
                    '7.4 hrs',
                    '89%',
                    JentraStatusTone.info,
                  ),
                ])
                  SizedBox(
                    width: width,
                    child: _FlowTile(
                      label: flow.$1,
                      time: flow.$2,
                      health: flow.$3,
                      tone: flow.$4,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({
    required this.label,
    required this.time,
    required this.health,
    required this.tone,
  });

  final String label;
  final String time;
  final String health;
  final JentraStatusTone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(JentraSpacing.x4),
    decoration: BoxDecoration(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(JentraRadii.control),
      border: Border.all(color: context.jentraColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: JentraSpacing.x3),
        Wrap(
          spacing: JentraSpacing.x3,
          runSpacing: JentraSpacing.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              time,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: JentraTypography.monoFamily,
              ),
            ),
            JentraStatusBadge(label: health, tone: tone),
          ],
        ),
        const SizedBox(height: JentraSpacing.x3),
        Text(
          'Successful handoffs',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.jentraColors.textSecondary,
          ),
        ),
        const SizedBox(height: JentraSpacing.x2),
        Semantics(
          label: '$label successful handoffs',
          value: health,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: double.parse(health.replaceAll('%', '')) / 100,
              minHeight: 4,
              backgroundColor: context.jentraColors.border,
              color: switch (tone) {
                JentraStatusTone.warning => context.jentraColors.warning,
                JentraStatusTone.info => context.jentraColors.info,
                _ => context.jentraColors.success,
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context) => JentraPanel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(JentraSpacing.x5),
          child: JentraSectionHeader(
            title: 'Recent business activity',
            description:
                'A preview of how activity connects across your workspace',
            trailing: JentraStatusBadge(
              label: 'Sample events',
              tone: JentraStatusTone.neutral,
            ),
          ),
        ),
        Divider(height: 1, color: context.jentraColors.border),
        const _ActivityHeader(),
        for (final row in const [
          (
            'INV-2026-01084',
            'Sales invoice posted',
            'Lanka Office Mart',
            'LKR 328,400',
            'S. Perera',
            '09:42',
            JentraStatusTone.success,
          ),
          (
            'GRN-2026-00471',
            'Goods receipt completed',
            'Ceylon Parts Co.',
            '42 units',
            'N. Fernando',
            '09:18',
            JentraStatusTone.info,
          ),
          (
            'PAY-2026-00318',
            'Payment submitted',
            'Metro Logistics',
            'LKR 218,900',
            'A. Silva',
            '08:56',
            JentraStatusTone.warning,
          ),
          (
            'SRV-2026-00149',
            'Work order fulfilled',
            'Serendib Foods',
            '3.2 hours',
            'R. Iqbal',
            '08:31',
            JentraStatusTone.success,
          ),
        ])
          _ActivityRow(
            reference: row.$1,
            event: row.$2,
            party: row.$3,
            value: row.$4,
            actor: row.$5,
            time: row.$6,
            tone: row.$7,
          ),
      ],
    ),
  );
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (constraints.maxWidth < 1000 * scale) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: JentraSpacing.x5,
          vertical: JentraSpacing.x3,
        ),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: context.jentraColors.textSecondary,
            letterSpacing: .8,
          ),
          child: const Row(
            children: [
              Expanded(flex: 18, child: Text('REFERENCE')),
              Expanded(flex: 25, child: Text('EVENT')),
              Expanded(flex: 21, child: Text('PARTY / SOURCE')),
              Expanded(
                flex: 16,
                child: Text('VALUE', textAlign: TextAlign.right),
              ),
              SizedBox(width: JentraSpacing.x5),
              Expanded(flex: 14, child: Text('ACTOR')),
              Expanded(
                flex: 6,
                child: Text('TIME', textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.reference,
    required this.event,
    required this.party,
    required this.value,
    required this.actor,
    required this.time,
    required this.tone,
  });

  final String reference;
  final String event;
  final String party;
  final String value;
  final String actor;
  final String time;
  final JentraStatusTone tone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final compact = constraints.maxWidth < 1000 * scale;
      final referenceText = Text(
        reference,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: context.jentraColors.textSecondary,
          fontFamily: JentraTypography.monoFamily,
        ),
      );
      final amountText = Text(
        value,
        textAlign: compact ? TextAlign.start : TextAlign.right,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontFamily: JentraTypography.monoFamily,
        ),
      );
      final eventText = Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: switch (tone) {
                JentraStatusTone.warning => context.jentraColors.warning,
                JentraStatusTone.info => context.jentraColors.info,
                _ => context.jentraColors.success,
              },
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: JentraSpacing.x2),
          Expanded(child: Text(event)),
        ],
      );
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: JentraSpacing.x5,
          vertical: JentraSpacing.x4,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.jentraColors.border),
          ),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  referenceText,
                  const SizedBox(height: JentraSpacing.x2),
                  eventText,
                  const SizedBox(height: JentraSpacing.x2),
                  Wrap(
                    spacing: JentraSpacing.x4,
                    runSpacing: JentraSpacing.x2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(party),
                      amountText,
                      Text(
                        '$actor · $time',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.jentraColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 18, child: referenceText),
                  Expanded(
                    flex: 25,
                    child: Padding(
                      padding: const EdgeInsets.only(right: JentraSpacing.x3),
                      child: eventText,
                    ),
                  ),
                  Expanded(flex: 21, child: Text(party)),
                  Expanded(flex: 16, child: amountText),
                  const SizedBox(width: JentraSpacing.x5),
                  Expanded(flex: 14, child: Text(actor)),
                  Expanded(
                    flex: 6,
                    child: Text(time, textAlign: TextAlign.right),
                  ),
                ],
              ),
      );
    },
  );
}
