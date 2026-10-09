import 'dart:convert';

import 'package:http/http.dart' as http;

/// Public provider availability only. Never forwards a caller access token.
Future<bool> googleProviderEnabled(
  Uri authorizeUri,
  String publishableKey, {
  http.Client? httpClient,
}) async {
  if (authorizeUri.scheme != 'https' ||
      authorizeUri.userInfo.isNotEmpty ||
      authorizeUri.path != '/auth/v1/authorize' ||
      publishableKey.isEmpty) {
    throw StateError('GOOGLE_PUBLIC_SETTINGS_UNAVAILABLE');
  }
  final client = httpClient ?? http.Client();
  try {
    return await (() async {
      final response = await client.send(
        http.Request(
            'GET',
            Uri.parse('${authorizeUri.origin}/auth/v1/settings'),
          )
          ..followRedirects = false
          ..headers['apikey'] = publishableKey,
      );
      if (response.statusCode != 200) {
        throw StateError('GOOGLE_PUBLIC_SETTINGS_UNAVAILABLE');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 16384) {
          throw StateError('GOOGLE_PUBLIC_SETTINGS_UNAVAILABLE');
        }
        bytes.addAll(chunk);
      }
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map ||
          value['external'] is! Map ||
          value['external']['google'] is! bool) {
        throw StateError('GOOGLE_PUBLIC_SETTINGS_UNAVAILABLE');
      }
      return value['external']['google'] as bool;
    })().timeout(const Duration(seconds: 10));
  } finally {
    if (httpClient == null) client.close();
  }
}
