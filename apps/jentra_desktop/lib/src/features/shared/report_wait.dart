import 'package:flutter/material.dart';

/// Presentation cancellation preserves an already dispatched command's authority.
final class ReportWaitState {
  bool active = false, cancelled = false;
  String stage = 'Preparing report request';
  void begin() {
    active = true;
    cancelled = false;
    stage = 'Preparing report request';
  }

  void generating() => stage = 'Generating report';
  void reading() => stage = 'Loading report evidence';
  bool cancel() {
    if (!active || cancelled) return false;
    cancelled = true;
    return true;
  }

  void finish() => active = false;
}

class ReportWaitIndicator extends StatelessWidget {
  const ReportWaitIndicator({
    super.key,
    required this.state,
    required this.onCancel,
  });
  final ReportWaitState state;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.cancelled
              ? 'Report waiting cancelled. A dispatched request may still complete. Its saved identity is retained for recovery.'
              : state.stage,
        ),
        if (!state.cancelled) ...[
          LinearProgressIndicator(semanticsLabel: state.stage),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel report waiting'),
          ),
        ],
      ],
    ),
  );
}
