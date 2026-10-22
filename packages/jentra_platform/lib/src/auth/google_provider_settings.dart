import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_sign_in.dart';

/// Check availability before any OAuth method can write a PKCE verifier.
Future<void> requireGoogleProvider(
  SupabaseClient client, {
  GoogleSignInCancellation? cancellation,
  http.Client? httpClient,
}) async {
  if (cancellation?.isCancelled ?? false) {
    throw const GoogleSignInException(GoogleSignInFailure.cancelled);
  }
  bool enabled;
  try {
    // In the SDK constructor the Auth and REST URLs share the supplied base.
    // PostgrestClient.url is public; the SDK's Auth URL is private. Validate the
    // exact REST endpoint before deriving the same-origin public Auth endpoint.
    final rest = Uri.parse(client.rest.url);
    if (rest.scheme != 'https' ||
        rest.userInfo.isNotEmpty ||
        rest.path != '/rest/v1' ||
        rest.hasQuery ||
        rest.hasFragment) {
      throw const GoogleSignInException(
        GoogleSignInFailure.settingsUnavailable,
      );
    }
    final lookup = googleProviderEnabled(
      rest.replace(path: '/auth/v1/authorize'),
      client.auth.headers['apikey'] ?? '',
      httpClient: httpClient,
    );
    enabled = cancellation == null
        ? await lookup
        : await Future.any<bool>([
            lookup,
            cancellation.whenCancelled.then<bool>(
              (_) => throw const GoogleSignInException(
                GoogleSignInFailure.cancelled,
              ),
            ),
          ]);
  } on GoogleSignInException {
    rethrow;
  } on Object {
    throw const GoogleSignInException(GoogleSignInFailure.settingsUnavailable);
  }
  if (cancellation?.isCancelled ?? false) {
    throw const GoogleSignInException(GoogleSignInFailure.cancelled);
  }
  if (!enabled) {
    throw const GoogleSignInException(GoogleSignInFailure.providerDisabled);
  }
}

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
