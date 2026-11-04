import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_platform/jentra_platform.dart';

import '../models.dart';

abstract interface class SalesAccountGateway {
  Future<void> signIn(String login, String password);
  Future<void> signOut();
}

/// Password sessions are deliberately memory-only in this initial client.
/// No broad commerce/customer/table API is used as a fallback for field scope.
final class SupabaseSalesAccountGateway implements SalesAccountGateway {
  SupabaseSalesAccountGateway(
    this.client, {
    this.enableCandidate = false,
    this.signInTimeout = const Duration(seconds: 20),
  }) : _passwordSignIn = null,
       _localSignOut = null;
  SupabaseSalesAccountGateway.withAuth({
    required Future<AuthResponse> Function(String, String) signIn,
    required Future<void> Function() signOut,
    this.enableCandidate = false,
    this.signInTimeout = const Duration(seconds: 20),
  }) : client = null,
       _passwordSignIn = signIn,
       _localSignOut = signOut;
  final SupabaseClient? client;
  final Future<AuthResponse> Function(String, String)? _passwordSignIn;
  final Future<void> Function()? _localSignOut;
  final bool enableCandidate;
  final Duration signInTimeout;
  int _generation = 0;
  bool _authInFlight = false;
  Future<void> _logout = Future.value();
  @override
  Future<void> signIn(String login, String password) async {
    if (_authInFlight) {
      throw const SalesFailure(
        'SIGN_IN_PENDING',
        'The previous sign-in is still finishing. Try again shortly.',
      );
    }
    _authInFlight = true;
    final generation = ++_generation;
    try {
      await _logout;
      final authentication = _passwordSignIn != null
          ? _passwordSignIn(login, password)
          : SupabaseFoundationGateway(client!)
                .signInWithLogin(login: login, password: password);
      final result = await authentication
          .then((value) async {
            if (!enableCandidate || generation != _generation) await signOut();
            return value;
          })
          .whenComplete(() => _authInFlight = false)
          .timeout(signInTimeout);
      if (enableCandidate && generation != _generation) {
        throw const SalesFailure(
          'SIGN_IN_CANCELLED',
          'Sign-in was cancelled. Try again.',
        );
      }
      if (result.user == null || result.session == null) {
        throw const SalesFailure(
          'SIGN_IN_FAILED',
          'Sign-in was not completed. Try again.',
        );
      }
    } on SalesFailure {
      await signOut();
      rethrow;
    } on AuthException {
      await signOut();
      throw const SalesFailure(
        'SIGN_IN_FAILED',
        'Check your username or work email, password and account verification, then try again.',
      );
    } on Object {
      await signOut();
      throw const SalesFailure(
        'CONNECTION_UNAVAILABLE',
        'Unable to connect. Check your connection and try again.',
      );
    }
    if (enableCandidate) return;
    // Candidate access is opt-in for a separately reviewed local test build.
    throw const SalesFailure(
      'FIELD_SALES_ROLLOUT_PENDING',
      'Your account was verified. Your company’s Sales workspace is being prepared. Ask your administrator to enable your assigned customer portfolio.',
    );
  }

  @override
  Future<void> signOut() async {
    // Local logout always clears this app's memory-only session. It does not
    // revoke sessions in the existing desktop or Employee application.
    ++_generation;
    final logout = _logout.then(
      (_) => _localSignOut != null
          ? _localSignOut()
          : client!.auth.signOut(scope: SignOutScope.local),
    );
    _logout = logout.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await logout;
  }
}
