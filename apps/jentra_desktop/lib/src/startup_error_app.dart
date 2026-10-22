import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

/// A startup failure never constructs the workspace, local stores, or gateways.
class JentraStartupErrorApp extends StatelessWidget {
  const JentraStartupErrorApp({required this.failure, this.onRetry, super.key});

  final RuntimeStartupFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Jentra OS',
    debugShowCheckedModeBanner: false,
    theme: JentraTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(JentraSpacing.x6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: JentraPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const JentraBrandLockup(size: 44, showTagline: true),
                      const SizedBox(height: JentraSpacing.x6),
                      const Icon(Icons.cloud_off_outlined, size: 36),
                      const SizedBox(height: JentraSpacing.x4),
                      Text(
                        'Jentra OS could not start',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: JentraSpacing.x3),
                      Semantics(liveRegion: true, child: Text(_message)),
                      const SizedBox(height: JentraSpacing.x4),
                      Text(_recovery),
                      const SizedBox(height: JentraSpacing.x4),
                      SelectableText('Support code: ${failure.name}'),
                      if (failure ==
                              RuntimeStartupFailure.initializationFailed &&
                          onRetry != null) ...[
                        const SizedBox(height: JentraSpacing.x6),
                        JentraPrimaryButton(
                          label: 'Try again',
                          icon: Icons.refresh,
                          onPressed: onRetry,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  String get _message => switch (failure) {
    RuntimeStartupFailure.missingConnection =>
      'This installation is missing its workspace connection.',
    RuntimeStartupFailure.initializationFailed =>
      'Jentra could not prepare your secure workspace connection.',
    RuntimeStartupFailure.projectMismatch =>
      'The workspace connection does not match this installation.',
    _ => 'This installation has an invalid workspace configuration.',
  };

  String get _recovery => failure == RuntimeStartupFailure.initializationFailed
      ? 'Check your connection and try again. If this continues, share the support code with your administrator.'
      : 'Ask your administrator for a correctly configured Jentra OS installation and share the support code below.';
}
