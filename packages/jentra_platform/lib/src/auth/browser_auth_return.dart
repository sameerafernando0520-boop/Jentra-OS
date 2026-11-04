import 'package:supabase_flutter/supabase_flutter.dart';

import 'email_confirmation.dart';

/// Transient input only. Never format this object or its code into diagnostics.
final class BrowserAuthReturn {
  const BrowserAuthReturn.none() : present = false, code = null, failure = null;
  const BrowserAuthReturn.code(this.code) : present = true, failure = null;
  const BrowserAuthReturn.failure(this.failure) : present = true, code = null;
  final bool present;
  final String? code;
  final EmailConfirmationFailure? failure;
}

EmailConfirmationFailure? _notice;
bool _captured = false;
bool get browserAuthReturnWasCaptured => _captured;

void markBrowserAuthReturnCaptured() {
  _captured = true;
  // Retain a safe notice if initialization fails before the exchange can run.
  _notice = EmailConfirmationFailure.exchangeFailed;
}

EmailConfirmationFailure? takeBrowserAuthReturnFailure() {
  final notice = _notice;
  _notice = null;
  return notice;
}

const _authNames = {
  'code',
  'error',
  'error_code',
  'error_description',
  'access_token',
  'refresh_token',
  'id_token',
  'provider_token',
  'provider_refresh_token',
  'token_type',
  'expires_in',
  'expires_at',
};

String browserVerificationRedirect(Uri location) {
  if (location.userInfo.isNotEmpty ||
      location.host.isEmpty ||
      !(location.scheme == 'https' ||
          location.scheme == 'http' &&
              const {
                '127.0.0.1',
                'localhost',
                '[::1]',
              }.contains(location.host))) {
    throw const EmailConfirmationException(
      EmailConfirmationFailure.callbackUnavailable,
    );
  }
  return '${location.origin}/';
}

BrowserAuthReturn parseBrowserAuthReturn(Uri location) {
  Map<String, List<String>> query, fragment;
  try {
    query = location.queryParametersAll;
    final raw = location.fragment;
    fragment = raw.startsWith('/')
        ? Uri.parse(raw).queryParametersAll
        : Uri.splitQueryString(raw).map((key, value) => MapEntry(key, [value]));
  } on Object {
    return const BrowserAuthReturn.failure(
      EmailConfirmationFailure.invalidLink,
    );
  }
  if (!query.keys.any(_authNames.contains) &&
      !fragment.keys.any(_authNames.contains)) {
    return const BrowserAuthReturn.none();
  }
  try {
    browserVerificationRedirect(location);
    if (location.path != '/' ||
        fragment.keys.any(_authNames.contains) ||
        query.keys.any(
          (key) => !const {
            'code',
            'error',
            'error_code',
            'error_description',
          }.contains(key),
        ) ||
        query.values.any((values) => values.length != 1) ||
        location.toString().length > 8192) {
      return const BrowserAuthReturn.failure(
        EmailConfirmationFailure.invalidLink,
      );
    }
    if (query.containsKey('error') || query.containsKey('error_code')) {
      if (query.containsKey('code')) {
        return const BrowserAuthReturn.failure(
          EmailConfirmationFailure.invalidLink,
        );
      }
      final code = query['error_code']?.single ?? query['error']?.single;
      return BrowserAuthReturn.failure(switch (code) {
        'otp_expired' ||
        'flow_state_expired' ||
        'flow_state_not_found' => EmailConfirmationFailure.expired,
        'access_denied' => EmailConfirmationFailure.cancelled,
        _ => EmailConfirmationFailure.exchangeFailed,
      });
    }
    final code = query['code']?.single;
    if (code == null ||
        code.isEmpty ||
        code.length > 2048 ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(code)) {
      return const BrowserAuthReturn.failure(
        EmailConfirmationFailure.invalidLink,
      );
    }
    return BrowserAuthReturn.code(code);
  } on Object {
    return const BrowserAuthReturn.failure(
      EmailConfirmationFailure.invalidLink,
    );
  }
}

Future<void> completeBrowserAuthReturn(
  SupabaseClient client,
  BrowserAuthReturn pending,
) async {
  _notice = null;
  if (!pending.present) return;
  if (pending.failure case final failure?) {
    _notice = failure;
    return;
  }
  if (client.auth.currentSession != null) {
    _notice = EmailConfirmationFailure.alreadySignedIn;
    return;
  }
  try {
    final response = await client.auth.exchangeCodeForSession(pending.code!);
    if (response.session.user.id.isEmpty) {
      _notice = EmailConfirmationFailure.exchangeFailed;
    }
  } on Object catch (error) {
    final failure = emailConfirmationFailure(error);
    _notice = failure == EmailConfirmationFailure.failed
        ? EmailConfirmationFailure.exchangeFailed
        : failure;
  }
}
