import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class DemoPlayer extends StatelessWidget {
  const DemoPlayer({super.key, required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: HtmlElementView.fromTagName(
      key: ValueKey(url),
      tagName: 'video',
      onElementCreated: (element) {
        final video = element as web.HTMLVideoElement;
        video
          ..controls = true
          ..preload = 'metadata'
          ..src = url.toString()
          ..style.width = '100%'
          ..style.height = '100%'
          ..setAttribute('playsinline', '')
          ..setAttribute('aria-label', 'Subscription plan demo');
      },
    ),
  );
}
