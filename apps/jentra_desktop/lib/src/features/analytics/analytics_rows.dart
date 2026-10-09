import 'package:flutter/material.dart';

/// Bounded local pages for already verified analytic publications.
class AnalyticsRows<T> extends StatefulWidget {
  const AnalyticsRows({super.key, required this.rows, required this.row});
  final List<T> rows;
  final Widget Function(T) row;
  @override
  State<AnalyticsRows<T>> createState() => _AnalyticsRowsState<T>();
}

class _AnalyticsRowsState<T> extends State<AnalyticsRows<T>> {
  int offset = 0;
  @override
  void didUpdateWidget(covariant AnalyticsRows<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows != widget.rows) offset = 0;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final value in widget.rows.skip(offset).take(50)) widget.row(value),
      if (widget.rows.length > 50)
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${offset + 1}–${(offset + 50).clamp(0, widget.rows.length)} of ${widget.rows.length}',
            ),
            TextButton(
              onPressed: offset == 0
                  ? null
                  : () => setState(() => offset -= 50),
              child: const Text('Previous 50'),
            ),
            TextButton(
              onPressed: offset + 50 >= widget.rows.length
                  ? null
                  : () => setState(() => offset += 50),
              child: const Text('Next 50'),
            ),
          ],
        ),
    ],
  );
}
