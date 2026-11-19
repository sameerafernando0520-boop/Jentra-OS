import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

class OperationalMetricCard extends StatefulWidget {
  const OperationalMetricCard({super.key, required this.metric});
  final Map metric;

  @override
  State<OperationalMetricCard> createState() => _OperationalMetricCardState();
}

class _OperationalMetricCardState extends State<OperationalMetricCard> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final metric = widget.metric;
    final kind = metric['kind'];
    final data = metric['data'];
    final (title, icon, accent) = switch (kind) {
      'pipeline' => (
        'Pipeline and forecast',
        Icons.trending_up,
        JentraColors.blue600,
      ),
      'ar_aging' => (
        'Receivables aging',
        Icons.payments_outlined,
        JentraColors.teal600,
      ),
      'ap_aging' => (
        'Payables aging',
        Icons.receipt_long_outlined,
        JentraColors.blue600,
      ),
      'cash_bank' => (
        'Cash and bank reconciliation',
        Icons.account_balance_outlined,
        JentraColors.teal600,
      ),
      'periods' => (
        'Period status',
        Icons.calendar_month_outlined,
        JentraColors.green500,
      ),
      'budgets' => (
        'Budgets and saved variances',
        Icons.bar_chart_outlined,
        JentraColors.blue600,
      ),
      'close_review' => (
        'Saved close review',
        Icons.fact_check_outlined,
        JentraColors.teal600,
      ),
      'bill_exceptions' => (
        'Supplier bill exceptions',
        Icons.rule_outlined,
        JentraColors.green500,
      ),
      _ => ('Business state', Icons.insights_outlined, JentraColors.blue600),
    };
    final lines = <String>[];
    switch (kind) {
      case 'pipeline':
        if (data is Map) {
          for (final row in (data['currency_totals'] as List? ?? [])) {
            lines.add(
              '${row['currency_code']} · Expected ${row['expected_value']} · Weighted ${row['weighted_value']}',
            );
          }
          for (final row in (data['stage_totals'] as List? ?? [])) {
            lines.add(
              'Stage ${row['stage']} · ${row['currency_code']} · ${row['opportunity_count']} opportunities · ${row['expected_value']}',
            );
          }
          for (final row in (data['forecast_totals'] as List? ?? [])) {
            lines.add(
              'Forecast ${row['forecast_bucket']} · ${row['currency_code']} · ${row['weighted_value']}',
            );
          }
          final conversion = data['conversion'] as Map?;
          if (conversion != null) {
            lines.add(
              'Converted ${conversion['converted_leads']} of ${conversion['total_leads']} leads · ${_trimDecimal(conversion['conversion_rate'])}%',
            );
          }
          final decisions = data['win_loss'] as Map?;
          if (decisions != null) {
            lines.add('Won ${decisions['won']} · Lost ${decisions['lost']}');
          }
          final aging = data['aging'] as Map?;
          if (aging != null) {
            lines.add(
              'Open ${aging['open_opportunity_count']} · Stale ${aging['stale_opportunity_count']} · Average age ${_trimDecimal(aging['average_age_days'])} days',
            );
          }
          final activity = data['activity_recency'] as Map?;
          if (activity != null) {
            lines.add(
              'Activities ${activity['activity_count']} · Latest ${activity['latest_activity_at'] ?? 'none'}',
            );
          }
        }
      case 'ar_aging' || 'ap_aging':
        if (data is Map) {
          for (final row in (data['buckets'] as List? ?? [])) {
            lines.add(
              '${row['currency_code']} · ${row['bucket']} · ${row['amount']} · ${row['item_count']} open items',
            );
          }
        }
      case 'cash_bank':
        if (data is List) {
          for (final row in data.take(20)) {
            lines.add(
              '${row['name']} · ${row['currency_code']} · Book ${row['gl_value']} · ${row['status']}',
            );
            lines.add(
              'Unmatched book ${row['unmatched_book']} · Bank ${row['unmatched_bank']} · Difference ${row['difference']}',
            );
          }
          if (data.length > 20) {
            lines.add(
              'Showing 20 of ${data.length} accounts. Open the workspace for the complete list.',
            );
          }
        }
      case 'periods':
        if (data is List) {
          for (final row in data.take(20)) {
            lines.add(
              '${row['name']} · ${row['state']} · ${row['start_date']} to ${row['end_date']}',
            );
          }
          if (data.length > 20) {
            lines.add(
              'Showing 20 of ${data.length} periods. Open the workspace for the complete list.',
            );
          }
        }
      case 'budgets':
        if (data is List) {
          for (final row in data.take(20)) {
            lines.add(
              '${row['year']} · Revision ${row['revision']} · ${row['status']} · ${row['currency_code']}',
            );
            final review = row['review'];
            if (review is Map) {
              lines.add(
                'Saved as of ${review['as_of']} · Generated ${review['generated_at']} · Budget ${review['budget_total']} · Actual ${review['actual_total']} · Variance ${review['variance_total']}',
              );
            } else {
              lines.add('No saved variance review for this version.');
            }
          }
          if (data.length > 20) {
            lines.add(
              'Showing 20 of ${data.length} versions. Open the workspace for the complete list.',
            );
          }
        }
      case 'close_review':
        if (data is Map) {
          lines.add(
            '${data['period_name']} · ${data['status']} · All entity branches',
          );
          lines.add(
            'Saved as of ${data['as_of']} · Generated ${data['generated_at']}',
          );
          lines.add(
            'Controls ${data['control_count']} · Differences ${data['difference_count']} · Blockers ${data['blocker_count']}',
          );
        } else {
          lines.add('No saved close review for this scope.');
        }
      case 'bill_exceptions':
        if (data is Map) {
          lines.add('${data['exception_count']} draft bills need match review');
        }
    }
    final cutoff = DateTime.tryParse('${metric['as_of']}');
    final dateLabel = cutoff == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(cutoff);
    const previewLines = 4;
    return OperationalOverviewCard(
      title: title,
      icon: icon,
      accent: accent,
      detail: dateLabel == null
          ? null
          : Tooltip(
              message: 'Generated ${metric['generated_at']}',
              child: Text('As of $dateLabel'),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty) const Text('No items in this scope.'),
          for (final line in _showDetails ? lines : lines.take(previewLines))
            Padding(
              padding: const EdgeInsets.only(bottom: JentraSpacing.x1),
              child: Text(line),
            ),
          if (lines.length > previewLines)
            TextButton(
              onPressed: () => setState(() => _showDetails = !_showDetails),
              child: Text(
                _showDetails
                    ? 'Show fewer details'
                    : 'Show more details (${lines.length - previewLines})',
              ),
            ),
        ],
      ),
      action: TextButton.icon(
        onPressed: () => context.push(metric['destination'] as String),
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Open workspace'),
      ),
    );
  }

  String _trimDecimal(Object? value) => '$value'.replaceFirstMapped(
    RegExp(r'(\.\d*?[1-9])0+$|\.0+$'),
    (match) => match[1] ?? '',
  );
}

class OperationalOverviewCard extends StatelessWidget {
  const OperationalOverviewCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.body,
    required this.action,
    this.detail,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget? detail;
  final Widget body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.jentraColors;
    final isDark = theme.brightness == Brightness.dark;
    final tint = Color.alphaBlend(accent.withValues(alpha: .08), colors.panel);
    return Material(
      color: tint,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: BorderRadius.circular(JentraRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JentraSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(JentraSpacing.x2),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          accent.withValues(alpha: .16),
                          colors.panel,
                        ),
                        borderRadius: BorderRadius.circular(
                          JentraRadii.control,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: isDark
                            ? colors.textPrimary
                            : JentraColors.navy800,
                      ),
                    ),
                    const SizedBox(width: JentraSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (detail != null)
                            DefaultTextStyle(
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: colors.textSecondary,
                              ),
                              child: detail!,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: JentraSpacing.x4),
                body,
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: JentraSpacing.x2),
              child: action,
            ),
          ],
        ),
      ),
    );
  }
}
