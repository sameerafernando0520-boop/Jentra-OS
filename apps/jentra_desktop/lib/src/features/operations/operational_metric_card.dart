import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OperationalMetricCard extends StatelessWidget {
  const OperationalMetricCard({super.key, required this.metric});
  final Map metric;

  @override
  Widget build(BuildContext context) {
    final kind = metric['kind'];
    final data = metric['data'];
    final title = switch (kind) {
      'pipeline' => 'Pipeline and forecast',
      'ar_aging' => 'Receivables aging',
      'ap_aging' => 'Payables aging',
      'cash_bank' => 'Cash and bank reconciliation',
      'periods' => 'Period status',
      'budgets' => 'Budgets and saved variances',
      'close_review' => 'Saved close review',
      'bill_exceptions' => 'Supplier bill exceptions',
      _ => 'Business state',
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
              'Converted ${conversion['converted_leads']} of ${conversion['total_leads']} leads · ${conversion['conversion_rate']}%',
            );
          }
          final decisions = data['win_loss'] as Map?;
          if (decisions != null) {
            lines.add('Won ${decisions['won']} · Lost ${decisions['lost']}');
          }
          final aging = data['aging'] as Map?;
          if (aging != null) {
            lines.add(
              'Open ${aging['open_opportunity_count']} · Stale ${aging['stale_opportunity_count']} · Average age ${aging['average_age_days']} days',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text(
              'As of ${metric['as_of']} · Generated ${metric['generated_at']}',
            ),
            const SizedBox(height: 8),
            if (lines.isEmpty) const Text('No items in this scope.'),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line),
              ),
            TextButton.icon(
              onPressed: () => context.push(metric['destination'] as String),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open workspace'),
            ),
          ],
        ),
      ),
    );
  }
}
