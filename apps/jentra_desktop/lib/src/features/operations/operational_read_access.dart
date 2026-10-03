import 'package:flutter/material.dart';

/// Current read access for dialogs that may outlive their workspace route.
abstract interface class OperationalReadAccess implements Listenable {
  int get readAccessEpoch;
  bool currentRead(int epoch);
  void denyReadAccess();
}

Future<T?> showOperationalReadDialog<T>(
  BuildContext context,
  OperationalReadAccess access,
  WidgetBuilder builder,
) async {
  final epoch = access.readAccessEpoch;
  if (!access.currentRead(epoch)) return null;
  final result = await showDialog<T>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: access,
      builder: (context, _) => access.currentRead(epoch)
          ? builder(context)
          : AlertDialog(
              title: const Text('Reference access changed'),
              content: const Text(
                'Close this selector and recheck your business scope and connection.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
    ),
  );
  return access.currentRead(epoch) ? result : null;
}
