import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

final class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(Icons.menu_book_rounded, color: colors.onPrimary),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConstants.appName,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              Text(AppConstants.appTagline, style: TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ],
    );
  }
}
