import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../../app_providers.dart';
import '../tenant/tenant_onboarding_screen.dart';

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
    if (tenants.value?.isEmpty ?? true) return const TenantOnboardingScreen();
    return const _DashboardContent();
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(JentraSpacing.x6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DashboardHeader(),
        const SizedBox(height: JentraSpacing.x6),
        const _KpiGrid(),
        const SizedBox(height: JentraSpacing.x5),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 960;
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
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: JentraSpacing.x3,
              runSpacing: JentraSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Good morning, Shehan',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const JentraStatusBadge(
                  label: 'Preview metrics',
                  tone: JentraStatusTone.info,
                ),
              ],
            ),
            const SizedBox(height: JentraSpacing.x2),
            Text(
              'Here is the operating pulse across your business today.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: context.jentraColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.calendar_today_outlined, size: 16),
        label: const Text('01 Aug – 31 Aug 2026'),
      ),
      const SizedBox(width: JentraSpacing.x2),
      IconButton.outlined(
        tooltip: 'Refresh dashboard',
        onPressed: () {},
        icon: const Icon(Icons.refresh, size: 18),
      ),
    ],
  );
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000 ? 4 : 2;
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
        JentraSectionHeader(
          title: 'Cash position',
          description: '13-week actual and forecast',
          trailing: PopupMenuButton<String>(
            tooltip: 'Chart options',
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cash', child: Text('Cash position')),
              PopupMenuItem(value: 'revenue', child: Text('Revenue trend')),
            ],
            child: const JentraStatusBadge(
              label: 'LKR',
              tone: JentraStatusTone.neutral,
            ),
          ),
        ),
        const SizedBox(height: JentraSpacing.x5),
        SizedBox(
          height: 222,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final label in const ['8M', '6M', '4M', '2M', '0'])
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: context.jentraColors.textSecondary,
                        fontFamily: JentraTypography.monoFamily,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: JentraSpacing.x3),
              Expanded(
                child: CustomPaint(
                  painter: _CashChartPainter(
                    lineColor: JentraColors.green500,
                    gridColor: context.jentraColors.border,
                    fillColor: JentraColors.green400.withValues(alpha: 0.16),
                  ),
                  child: const Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('W1'),
                          Text('W3'),
                          Text('W5'),
                          Text('W7'),
                          Text('W9'),
                          Text('W11'),
                          Text('W13'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: JentraSpacing.x3),
        Wrap(
          spacing: JentraSpacing.x3,
          runSpacing: JentraSpacing.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _Legend(color: JentraColors.green500, label: 'Actual'),
            _Legend(
              color: context.jentraColors.textSecondary,
              label: 'Forecast',
              dashed: true,
            ),
            Text(
              'Forecast updated 08:32',
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
    required this.gridColor,
    required this.fillColor,
  });

  final Color lineColor;
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
    final graphHeight = size.height - 28;
    final gridPaint = Paint()..color = gridColor.withValues(alpha: .7);
    for (var i = 0; i < 5; i++) {
      final y = graphHeight * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = graphHeight * (1 - values[i]);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, graphHeight)
      ..lineTo(0, graphHeight)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillColor, fillColor.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, graphHeight)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final forecastPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final start = Offset(size.width * .67, graphHeight * .37);
    final end = Offset(size.width, graphHeight * .18);
    for (var x = start.dx; x < end.dx; x += 9) {
      final ratio = (x - start.dx) / (end.dx - start.dx);
      final y = start.dy + (end.dy - start.dy) * ratio;
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 5, end.dx), y - 1),
        forecastPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CashChartPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor || oldDelegate.gridColor != gridColor;
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
      Container(
        width: 18,
        height: dashed ? 2 : 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
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
          description: '7 approvals and exceptions',
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
        const SizedBox(height: JentraSpacing.x2),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {},
            child: const Text('Open approval centre'),
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
  Widget build(BuildContext context) => InkWell(
    onTap: () {},
    borderRadius: BorderRadius.circular(JentraRadii.control),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: JentraSpacing.x3),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.jentraColors.infoSurface,
              borderRadius: BorderRadius.circular(JentraRadii.control),
            ),
            child: Icon(icon, size: 17, color: JentraColors.navy700),
          ),
          const SizedBox(width: JentraSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  reference,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.jentraColors.textSecondary,
                    fontFamily: JentraTypography.monoFamily,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontFamily: JentraTypography.monoFamily,
            ),
          ),
          const SizedBox(width: JentraSpacing.x2),
          const Icon(Icons.chevron_right, size: 17),
        ],
      ),
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
              'P50 cycle time and handoff health across canonical processes',
          trailing: JentraStatusBadge(
            label: 'Live model',
            tone: JentraStatusTone.success,
          ),
        ),
        const SizedBox(height: JentraSpacing.x5),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - JentraSpacing.x6) / 4;
            return Wrap(
              spacing: JentraSpacing.x2,
              runSpacing: JentraSpacing.x3,
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
                    width: math.max(width, 210),
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
            description: 'Attributable, scoped events across the workspace',
            trailing: JentraStatusBadge(
              label: 'Audit linked',
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
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x5),
    color: Theme.of(context).scaffoldBackgroundColor,
    child: const Row(
      children: [
        SizedBox(width: 146, child: Text('REFERENCE')),
        Expanded(flex: 3, child: Text('EVENT')),
        Expanded(flex: 2, child: Text('PARTY / SOURCE')),
        SizedBox(width: 134, child: Text('VALUE')),
        SizedBox(width: 110, child: Text('ACTOR')),
        SizedBox(width: 58, child: Text('TIME')),
      ],
    ),
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
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x5),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.jentraColors.border)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 146,
          child: Text(
            reference,
            style: const TextStyle(
              fontFamily: JentraTypography.monoFamily,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: tone == JentraStatusTone.warning
                      ? JentraColors.warning
                      : JentraColors.green500,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: JentraSpacing.x2),
              Flexible(child: Text(event, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        Expanded(flex: 2, child: Text(party, overflow: TextOverflow.ellipsis)),
        SizedBox(
          width: 134,
          child: Text(
            value,
            style: const TextStyle(fontFamily: JentraTypography.monoFamily),
          ),
        ),
        SizedBox(width: 110, child: Text(actor)),
        SizedBox(width: 58, child: Text(time)),
      ],
    ),
  );
}
