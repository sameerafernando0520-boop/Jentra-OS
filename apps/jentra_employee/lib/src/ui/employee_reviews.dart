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

class EmployeeReviewsScreen extends StatefulWidget {
  const EmployeeReviewsScreen({
    required this.controller,
    this.actionsOnly = false,
    super.key,
  });
  final EmployeeController controller;
  final bool actionsOnly;
  @override
  State<EmployeeReviewsScreen> createState() => _EmployeeReviewsScreenState();
}

class _EmployeeReviewsScreenState extends State<EmployeeReviewsScreen> {
  final _search = TextEditingController();
  String _filter = 'all';
  EmployeeController get controller => widget.controller;

  @override
  void dispose() {
    _search.clear();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final s = EmployeeStrings.of(context);
      final query = _search.text.trim().toLowerCase();
      final items =
          controller.reviews
              .where((r) => !widget.actionsOnly || r.canAcknowledge)
              .where((r) => _filter == 'all' || r.status == _filter)
              .where(
                (r) =>
                    query.isEmpty ||
                    '${r.objectives.join(' ')} ${r.comments ?? ''} ${employeeReviewPeriod(r, s.language)}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList()
            ..sort((a, b) => b.startDate.compareTo(a.startDate));
      final filtered = query.isNotEmpty || _filter != 'all';
      return Scaffold(
        appBar: AppBar(
          title: Text(s(widget.actionsOnly ? 'inbox' : 'reviews')),
        ),
        body: EmployeePageBody(
          onRefresh: controller.refresh,
          children: [
            Text(s(widget.actionsOnly ? 'inboxCopy' : 'reviewsCopy')),
            TextField(
              key: const Key('employee-review-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: s('searchReviews'),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: context.jentraColors.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('employee-review-search-clear'),
                        tooltip: s('clearSearch'),
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            if (!widget.actionsOnly)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in const [
                    'all',
                    'reviewed',
                    'acknowledged',
                    'closed',
                  ])
                    ChoiceChip(
                      key: Key('employee-review-filter-$filter'),
                      label: Text(
                        s(switch (filter) {
                          'all' => 'allReviews',
                          'reviewed' => 'needsReceipt',
                          'acknowledged' => 'receipts',
                          _ => 'closed',
                        }),
                      ),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
            if (controller.reviewsCursor != null)
              Text(
                s('loadedReviewsHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
                title: s(
                  filtered
                      ? 'noMatchingReviews'
                      : widget.actionsOnly
                      ? 'noActions'
                      : 'noReviews',
                ),
                message: s(filtered ? 'noMatchingCopy' : 'noReviewsCopy'),
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
