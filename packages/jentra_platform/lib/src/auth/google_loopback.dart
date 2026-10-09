import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A single private PKCE return channel for the browser flow that this process
/// starts. Codes and the per-attempt path are never logged or persisted here.
final class GoogleLoopbackSignIn {
  GoogleLoopbackSignIn({
    required this.launch,
    required this.exchange,
    this.port = 56327,
    this.timeout = const Duration(minutes: 5),
  });

  final Future<bool> Function(Uri callback) launch;
  final Future<void> Function(String code) exchange;
  final int port;
  final Duration timeout;
  HttpServer? _server;
  bool _running = false;

  Future<void> _reply(HttpRequest request, int status, String text) async {
    try {
      request.response.statusCode = status;
      request.response.write(text);
      await request.response.close().timeout(const Duration(seconds: 2));
    } on Object {
      // Browser connection loss cannot change the SDK authentication outcome.
    }
  }

  Future<bool> run() async {
    if (_running) throw StateError('GOOGLE_SIGN_IN_ALREADY_PENDING');
    _running = true;
    final completion = Completer<void>();
    final outcome = completion.future;
    // Waiting expires before an exchange begins. Once accepted, wait for the
    // SDK exchange itself: timing out after it begins could hide a late session.
    unawaited(outcome.catchError((Object _) {}));
    Timer? waitingTimer;
    var accepting = false;
    StreamSubscription<HttpRequest>? subscription;
    try {
      final server = _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      final random = Random.secure();
      final nonce = base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', '');
      final callback = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: '/auth/callback/$nonce',
      );
      waitingTimer = Timer(timeout, () {
        if (!completion.isCompleted) {
          completion.completeError(TimeoutException('GOOGLE_RETURN_TIMED_OUT'));
        }
      });
      subscription = server.listen(
        (request) async {
          request.response.headers
            ..contentType = ContentType.html
            ..set('Cache-Control', 'no-store')
            ..set('Referrer-Policy', 'no-referrer')
            ..set('X-Content-Type-Options', 'nosniff')
            ..set('Content-Security-Policy', "default-src 'none'");
          if (request.method != 'GET' ||
              request.uri.path != callback.path ||
              request.uri.toString().length > 4096 ||
              request.connectionInfo?.remoteAddress.isLoopback != true ||
              request.headers.value(HttpHeaders.hostHeader) !=
                  callback.authority ||
              accepting ||
              completion.isCompleted) {
            await _reply(request, HttpStatus.notFound, '');
            return;
          }
          if (request.uri.queryParameters.containsKey('error')) {
            accepting = true;
            waitingTimer?.cancel();
            await _reply(
              request,
              HttpStatus.badRequest,
              'Sign-in was not completed. Return to Jentra OS.',
            );
            completion.completeError(
              StateError('GOOGLE_SIGN_IN_NOT_COMPLETED'),
            );
            return;
          }
          final codes = request.uri.queryParametersAll['code'];
          if (codes == null ||
              codes.length != 1 ||
              codes.single.isEmpty ||
              codes.single.length > 2048 ||
              request.uri.queryParameters.keys.any((key) => key != 'code')) {
            await _reply(
              request,
              HttpStatus.badRequest,
              'Sign-in could not finish. Return to Jentra OS.',
            );
            // A malformed or denied return cannot exchange or install a session.
            return;
          }
          accepting = true;
          waitingTimer?.cancel();
          try {
            await exchange(codes.single);
            await _reply(
              request,
              HttpStatus.ok,
              'Signed in. You can return to Jentra OS.',
            );
            if (!completion.isCompleted) completion.complete();
          } on Object {
            await _reply(
              request,
              HttpStatus.badRequest,
              'Sign-in could not finish. Return to Jentra OS.',
            );
            if (!completion.isCompleted) {
              completion.completeError(
                StateError('GOOGLE_CODE_EXCHANGE_FAILED'),
              );
            }
          }
        },
        onError: (Object _) {
          if (!completion.isCompleted) {
            completion.completeError(StateError('GOOGLE_CALLBACK_FAILED'));
          }
        },
      );
      if (!await launch(callback)) {
        throw StateError('GOOGLE_BROWSER_NOT_OPENED');
      }
      await outcome;
      return true;
    } finally {
      waitingTimer?.cancel();
      await subscription?.cancel();
      await _server?.close(force: true);
      _server = null;
      _running = false;
    }
  }
}
