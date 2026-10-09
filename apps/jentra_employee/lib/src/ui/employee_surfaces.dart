import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

class EmployeeSurface extends StatelessWidget {
  const EmployeeSurface({
    required this.child,
    this.padding = 20,
    this.tint = false,
    super.key,
  });
  final Widget child;
  final double padding;
  final bool tint;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: tint
          ? context.jentraColors.infoSurface
          : context.jentraColors.panel,
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
}

class EmployeeSectionHeader extends StatelessWidget {
  const EmployeeSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    final action = onAction == null
        ? null
        : TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel ?? '',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          );
    if (MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          if (action != null)
            Align(alignment: Alignment.centerLeft, child: action),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: heading),
        ?action,
      ],
    );
  }
}
