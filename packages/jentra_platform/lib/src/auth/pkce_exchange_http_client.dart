import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pkce_transport_stub.dart' if (dart.library.io) 'pkce_transport_io.dart';

/// Bounds only the configured PKCE token exchange, including its response body.
/// A dedicated abortable transport prevents a timed-out exchange from later
/// delivering a session to the SDK or interrupting unrelated API requests.
final class PkceExchangeHttpClient extends http.BaseClient {
  PkceExchangeHttpClient(
    this._inner, {
    required this.tokenUri,
    this.deadline = const Duration(seconds: 45),
    this.maxRequestBytes = 8192,
    this.maxResponseBytes = 65536,
    this.maxHeaderBytes = 16384,
  });

  final http.Client _inner;
  final Uri tokenUri;
  final Duration deadline;
  final int maxRequestBytes;
  final int maxResponseBytes;
  final int maxHeaderBytes;
  final _active = <http.Client, Completer<void>>{};
  bool _closed = false;

  bool _isPkce(http.BaseRequest request) =>
      request.method == 'POST' &&
      request.url.scheme == tokenUri.scheme &&
      request.url.host == tokenUri.host &&
      request.url.port == tokenUri.port &&
      request.url.userInfo.isEmpty &&
      request.url.fragment.isEmpty &&
      request.url.path == tokenUri.path &&
      request.url.queryParametersAll.length == 1 &&
      request.url.queryParametersAll['grant_type']?.length == 1 &&
      request.url.queryParameters['grant_type'] == 'pkce';

  int _headerBytes(Map<String, String> headers) => headers.entries.fold(
    0,
    (count, entry) =>
        count + utf8.encode(entry.key).length + utf8.encode(entry.value).length,
  );

  http.ClientException _failure(String code) => http.ClientException(code);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_isPkce(request)) return _inner.send(request);
    if (_closed) throw _failure('PKCE_TRANSPORT_CLOSED');
    if (request is! http.Request ||
        request.bodyBytes.length > maxRequestBytes ||
        _headerBytes(request.headers) > maxHeaderBytes ||
        deadline <= Duration.zero) {
      throw _failure('PKCE_REQUEST_LIMIT_EXCEEDED');
    }

    final transport = createPkceTransport(deadline);
    final abort = Completer<void>();
    _active[transport] = abort;
    var expired = false;
    final timer = Timer(deadline, () {
      expired = true;
      if (!abort.isCompleted) abort.complete();
      // IOClient attaches abort after openUrl. Closing this dedicated client
      // also interrupts connection establishment without closing the API client.
      transport.close();
    });
    try {
      final outgoing =
          http.AbortableRequest(
              request.method,
              request.url,
              abortTrigger: abort.future,
            )
            ..headers.addAll(request.headers)
            ..bodyBytes = request.bodyBytes
            ..followRedirects = false
            ..persistentConnection = false;
      final response = await transport.send(outgoing);
      if (_headerBytes(response.headers) > maxHeaderBytes ||
          (response.contentLength ?? 0) > maxResponseBytes ||
          response.isRedirect ||
          response.statusCode >= 300 && response.statusCode < 400) {
        throw _failure('PKCE_RESPONSE_LIMIT_EXCEEDED');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw _failure('PKCE_RESPONSE_LIMIT_EXCEEDED');
        }
        bytes.addAll(chunk);
      }
      if (expired || abort.isCompleted) {
        throw _failure('PKCE_EXCHANGE_ABORTED');
      }
      // The SDK receives a complete bounded body only after the request's real
      // transport settled. No abandoned future can later install a session.
      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on Object catch (error) {
      if (expired) throw _failure('PKCE_EXCHANGE_DEADLINE_EXCEEDED');
      if (_closed) throw _failure('PKCE_TRANSPORT_CLOSED');
      if (error is http.ClientException &&
          const {
            'PKCE_RESPONSE_LIMIT_EXCEEDED',
            'PKCE_EXCHANGE_ABORTED',
          }.contains(error.message)) {
        rethrow;
      }
      // Never forward transport URLs, headers, bodies or provider diagnostics.
      throw _failure('PKCE_EXCHANGE_TRANSPORT_FAILED');
    } finally {
      timer.cancel();
      _active.remove(transport);
      transport.close();
    }
  }

  @override
  void close() {
    _closed = true;
    for (final entry in _active.entries) {
      if (!entry.value.isCompleted) entry.value.complete();
      entry.key.close();
    }
    _inner.close();
  }
}
