import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import '../data/employee_gateway.dart';
import '../employee_controller.dart';
import '../l10n/employee_strings.dart';
import 'employee_components.dart';
import 'onboarding_screens.dart';

String employeeReviewPeriod(EmployeeReview review, String language) {
  final last = DateTime(
    review.endDateExclusive.year,
    review.endDateExclusive.month,
    review.endDateExclusive.day - 1,
  );
  return '${DateFormat.yMMMd(language).format(review.startDate)} – ${DateFormat.yMMMd(language).format(last)}';
}

class EmployeeReviewsScreen extends StatelessWidget {
  const EmployeeReviewsScreen({
    required this.controller,
    this.actionsOnly = false,
    super.key,
  });
  final EmployeeController controller;
  final bool actionsOnly;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final items = controller.reviews
          .where((r) => !actionsOnly || r.canAcknowledge)
          .toList();
      return Scaffold(
        appBar: AppBar(title: Text(s(actionsOnly ? 'inbox' : 'reviews'))),
        body: EmployeePageBody(
          onRefresh: controller.refresh,
          children: [
            Text(s(actionsOnly ? 'inboxCopy' : 'reviewsCopy')),
            if (controller.reviewsLoading) const LinearProgressIndicator(),
            if (controller.reviewsError != null)
              EmployeeMessage(
                title: s.failure(controller.reviewsError!),
                error: true,
                action: OutlinedButton(
                  onPressed: controller.refresh,
                  child: Text(s('retry')),
                ),
              ),
            if (!controller.reviewsLoading &&
                controller.reviewsError == null &&
                items.isEmpty)
              EmployeeMessage(
                title: s(actionsOnly ? 'noActions' : 'noReviews'),
                message: s('noReviewsCopy'),
                icon: Icons.fact_check_outlined,
              ),
            if (controller.hasPendingCommand)
              EmployeePendingAction(controller: controller),
            for (final review in items)
              EmployeeActionTile(
                key: Key('employee-review-${review.id}'),
                title: employeeReviewPeriod(review, s.language),
                subtitle: s(review.status),
                icon: Icons.fact_check_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EmployeeReviewScreen(
                      controller: controller,
                      reviewId: review.id,
                    ),
                  ),
                ),
              ),
            if (controller.reviewsCursor != null)
              OutlinedButton(
                onPressed: controller.reviewsLoading
                    ? null
                    : controller.loadMoreReviews,
                child: Text(s('loadMore')),
              ),
          ],
        ),
      );
    },
  );
}

class EmployeeReviewScreen extends StatefulWidget {
  const EmployeeReviewScreen({
    required this.controller,
    required this.reviewId,
    super.key,
  });
  final EmployeeController controller;
  final String reviewId;
  @override
  State<EmployeeReviewScreen> createState() => _EmployeeReviewScreenState();
}

class _EmployeeReviewScreenState extends State<EmployeeReviewScreen> {
  bool _read = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final review = widget.controller.reviews
          .where((r) => r.id == widget.reviewId)
          .firstOrNull;
      return Scaffold(
        appBar: AppBar(title: Text(s('reviews'))),
        body: EmployeePageBody(
          children: [
            if (review == null)
              EmployeeMessage(title: s('reviewUnavailable'))
            else ...[
              Text(
                s('reviewPeriod'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              EmployeeHeading(employeeReviewPeriod(review, s.language)),
              EmployeeStatus(
                s(review.status),
                icon: review.canAcknowledge
                    ? Icons.mark_email_unread_outlined
                    : Icons.check_circle_outline,
              ),
              JentraPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EmployeeHeading(s('objectives')),
                    const SizedBox(height: 16),
                    for (var i = 0; i < review.objectives.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.jentraColors.textSecondary,
                                ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(review.objectives[i])),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (review.comments != null && review.comments!.isNotEmpty)
                JentraPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EmployeeHeading(s('comments')),
                      const SizedBox(height: 12),
                      Text(review.comments!),
                    ],
                  ),
                ),
              if (widget.controller.error != null)
                EmployeeMessage(
                  title: s.failure(widget.controller.error!),
                  error: true,
                ),
              if (widget.controller.hasPendingCommand)
                EmployeePendingAction(controller: widget.controller),
              if (review.canAcknowledge) ...[
                EmployeeMessage(
                  title: s('acknowledge'),
                  message: s('receiptCopy'),
                  icon: Icons.mark_email_read_outlined,
                ),
                CheckboxListTile(
                  key: const Key('employee-receipt-check'),
                  value: _read,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged:
                      widget.controller.busy ||
                          widget.controller.hasPendingCommand
                      ? null
                      : (value) => setState(() => _read = value ?? false),
                  title: Text(s('receiptCheck')),
                ),
                FilledButton(
                  key: const Key('employee-acknowledge'),
                  onPressed:
                      !_read ||
                          widget.controller.busy ||
                          widget.controller.hasPendingCommand
                      ? null
                      : () => widget.controller.acknowledgeReview(review),
                  child: Text(s('acknowledge')),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}
