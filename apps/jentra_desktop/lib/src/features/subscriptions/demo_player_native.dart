import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DemoPlayer extends StatelessWidget {
  const DemoPlayer({super.key, required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.play_circle_outline),
    label: const Text('Play demo in browser'),
    onPressed: () async {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The demo could not be opened.')),
        );
      }
    },
  );
}
