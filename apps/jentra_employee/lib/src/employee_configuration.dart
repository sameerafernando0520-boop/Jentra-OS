import 'dart:convert';

class EmployeeConfiguration {
  const EmployeeConfiguration({
    required this.url,
    required this.publishableKey,
  });
  const EmployeeConfiguration.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final String url, publishableKey;
  bool get isValid {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        (parsed.path.isNotEmpty && parsed.path != '/')) {
      return false;
    }
    if (publishableKey.startsWith('sb_publishable_') &&
        RegExp(r'^sb_publishable_[A-Za-z0-9_-]{8,}$')
            .hasMatch(publishableKey)) {
      return true;
    }
    try {
      final parts = publishableKey.split('.');
      if (parts.length != 3 || parts.any((part) => part.isEmpty)) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map && payload['role'] == 'anon';
    } on Object {
      return false;
    }
  }
}
