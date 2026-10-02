import 'package:flutter/material.dart';

class OperationalAccessChanged extends StatelessWidget {
  const OperationalAccessChanged({
    super.key,
    required this.retry,
    required this.enabled,
  });
  final VoidCallback retry;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Access changed. Saved work is retained securely.'),
        TextButton(
          onPressed: enabled ? retry : null,
          child: const Text('Recheck access'),
        ),
      ],
    ),
  );
}
