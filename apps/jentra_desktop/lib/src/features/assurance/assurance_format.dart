import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One date style across the assurance screens: "8 Oct 2026".
String auditDate(Object? v) {
  final d = switch (v) {
    final DateTime d => d,
    final String s => DateTime.tryParse(s),
    _ => null,
  };
  return d == null ? 'no date' : DateFormat('d MMM y').format(d);
}

/// Event times in UTC, labelled, so every reviewer reads the same instant.
String auditDateTime(String iso) {
  final d = DateTime.tryParse(iso)?.toUtc();
  return d == null ? iso : '${DateFormat('d MMM y HH:mm').format(d)} UTC';
}

/// `risk_accepted` → "Risk accepted".
String auditLabel(String code) {
  final s = code.replaceAll('_', ' ').trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Asks before an encrypted local draft is deleted, saying what is lost.
Future<bool> confirmDiscardDraft(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text(
          'The text saved on this device is deleted. Nothing has been sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    ) ??
    false;

String shortDigest(String sha) =>
    sha.length > 12 ? '${sha.substring(0, 12)}…' : sha;

/// A SHA-256 shown short; the full value is in the tooltip and can be
/// selected, and screen readers hear its start rather than every character.
class DigestText extends StatelessWidget {
  const DigestText(this.sha256, {super.key, this.style});
  final String sha256;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: sha256,
    excludeFromSemantics: true,
    child: Semantics(
      container: true,
      label:
          'SHA-256 starting ${sha256.substring(0, sha256.length.clamp(0, 8))}',
      excludeSemantics: true,
      child: SelectableText('SHA-256 ${shortDigest(sha256)}', style: style),
    ),
  );
}
