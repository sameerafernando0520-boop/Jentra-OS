import 'dart:async';

enum GoogleSignInFailure {
  providerDisabled,
  settingsUnavailable,
  browserUnavailable,
  callbackUnavailable,
  cancelled,
  callbackRejected,
  exchangeFailed,
  alreadyPending,
}

/// A fixed failure category, never a provider response or callback URL.
final class GoogleSignInException implements Exception {
  const GoogleSignInException(this.failure);

  final GoogleSignInFailure failure;

  @override
  String toString() => 'GoogleSignInException(${failure.name})';
}

/// Cancels a waiting browser return. An accepted exchange must settle normally.
final class GoogleSignInCancellation {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
