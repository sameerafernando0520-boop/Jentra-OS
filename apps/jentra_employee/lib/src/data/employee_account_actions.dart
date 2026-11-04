import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'employee_storage.dart';

/// Exact PKCE return destinations. Fragments containing bearer sessions are
/// deliberately rejected; this app never enables the implicit OAuth flow.
final class EmployeeAuthCallbackPolicy {
  EmployeeAuthCallbackPolicy.browser(Uri page)
    : callback = _browserCallback(page);
  EmployeeAuthCallbackPolicy.native({required bool development})
    : callback = Uri(
        scheme: development ? 'com.jentra.employee.dev' : 'com.jentra.employee',
        host: 'auth',
        path: '/callback',
      );
  final Uri callback;

  static Uri _browserCallback(Uri page) {
    final approved =
        page.host == 'jentra-os.web.app' ||
        page.host == 'jentra-os.firebaseapp.com' ||
        RegExp(r'^jentra-os--employee-(?:qa|preview)-[a-z0-9-]+\.web\.app$')
            .hasMatch(page.host);
    if (!approved ||
        page.scheme != 'https' ||
        page.userInfo.isNotEmpty ||
        page.port != 443) {
      throw StateError('EMPLOYEE_AUTH_ORIGIN_UNAVAILABLE');
    }
    return Uri.parse('${page.origin}/auth/callback');
  }

  bool allows(Uri uri) {
    if (uri.scheme != callback.scheme ||
        uri.host != callback.host ||
        uri.port != callback.port ||
        uri.path != callback.path ||
        uri.userInfo.isNotEmpty ||
        uri.toString().length > 16384) {
      return false;
    }
    Map<String, List<String>> fragment;
    try {
      fragment = uri.fragment.isEmpty
          ? const {}
          : Uri(query: uri.fragment).queryParametersAll;
    } on FormatException {
      return false;
    }
    final parameters = {...uri.queryParametersAll, ...fragment};
    if (parameters.keys.any(
          (key) => !const {
            'code',
            'error',
            'error_code',
            'error_description',
            'type',
            'state',
          }.contains(key),
        ) ||
        parameters.values.any((values) => values.length != 1)) {
      return false;
    }
    // A successful PKCE return must carry its single code in the query.
    final code = uri.queryParametersAll['code'];
    final hasError =
        parameters.containsKey('error') || parameters.containsKey('error_code');
    if (code != null) {
      return !hasError && fragment.isEmpty && code.single.isNotEmpty;
    }
    return hasError;
  }
}

enum EmployeeAccountFailure {
  googleDisabled,
  unavailable,
  cancelled,
  callbackRejected,
  signInRequired,
  invalidEmail,
  waitBeforeResend,
}

enum EmployeeAccountNotice { googleOpened, confirmationRequested }

abstract interface class EmployeeAccountGateway {
  String? get actorId;
  Future<void> google(Uri callback);
  Future<void> resend(String email, Uri callback);
}

final class SupabaseEmployeeAccountGateway implements EmployeeAccountGateway {
  SupabaseEmployeeAccountGateway(this.client, this.storage);
  final SupabaseClient client;
  final EmployeeAuthStorage storage;
  @override
  String? get actorId => client.auth.currentUser?.id;
  @override
  Future<void> google(Uri callback) async {
    storage.beginSignIn();
    // The locked SDK uses webOnlyWindowName:_self. This is essential: a popup
    // would compete with the originating tab's encrypted-store Web Lock.
    final launched = await SupabaseFoundationGateway(client)
        .signInWithGoogle(redirectTo: callback.toString());
    if (!launched) throw StateError('EMPLOYEE_OAUTH_NOT_OPENED');
  }

  @override
  Future<void> resend(String email, Uri callback) async {
    storage.beginSignIn();
    await client.auth
        .resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: callback.toString(),
        )
        .timeout(const Duration(seconds: 20));
  }
}

/// Account actions do not grant employee membership or bypass the HR link/MFA.
/// Provider response bodies, email addresses and callback URLs are never saved.
final class EmployeeAccountActions extends ChangeNotifier {
  EmployeeAccountActions({
    required this.gateway,
    required this.policy,
    DateTime Function()? now,
    Stream<AuthState>? authEvents,
  }) : _now = now ?? DateTime.now {
    _events = authEvents?.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.signedOut) {
          failure = null;
          notice = null;
          if (!_disposed) notifyListeners();
        }
      },
      onError: (Object error) {
        if (!_disposed && gateway.actorId == null) {
          failure = EmployeeAccountFailure.callbackRejected;
          notice = null;
          notifyListeners();
        }
      },
    );
  }
  final EmployeeAccountGateway gateway;
  final EmployeeAuthCallbackPolicy policy;
  final DateTime Function() _now;
  bool busy = false;
  bool _disposed = false;
  StreamSubscription<AuthState>? _events;
  DateTime? _lastResend;
  EmployeeAccountFailure? failure;
  EmployeeAccountNotice? notice;

  Future<void> google() => _run(() async {
    await gateway.google(policy.callback);
    if (gateway.actorId == null) notice = EmployeeAccountNotice.googleOpened;
  });

  Future<void> resend(String value) async {
    if (busy || _disposed) return;
    final email = value.trim();
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      failure = EmployeeAccountFailure.invalidEmail;
      notice = null;
      notifyListeners();
      return;
    }
    if (_lastResend != null &&
        _now().difference(_lastResend!) < const Duration(seconds: 60)) {
      failure = EmployeeAccountFailure.waitBeforeResend;
      notice = null;
      notifyListeners();
      return;
    }
    await _run(() async {
      // Also limit uncertain/failed sends: a timeout does not prove no email was sent.
      _lastResend = _now();
      await gateway.resend(email, policy.callback);
      if (gateway.actorId == null) {
        notice = EmployeeAccountNotice.confirmationRequested;
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    if (gateway.actorId != null) {
      failure = EmployeeAccountFailure.signInRequired;
      notice = null;
      notifyListeners();
      return;
    }
    busy = true;
    failure = null;
    notice = null;
    notifyListeners();
    try {
      await action();
    } on GoogleSignInException catch (error) {
      if (gateway.actorId == null) {
        failure = switch (error.failure) {
          GoogleSignInFailure.providerDisabled =>
            EmployeeAccountFailure.googleDisabled,
          GoogleSignInFailure.cancelled => EmployeeAccountFailure.cancelled,
          GoogleSignInFailure.callbackRejected =>
            EmployeeAccountFailure.callbackRejected,
          _ => EmployeeAccountFailure.unavailable,
        };
      }
    } on Object {
      if (gateway.actorId == null) failure = EmployeeAccountFailure.unavailable;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events?.cancel());
    super.dispose();
  }
}
