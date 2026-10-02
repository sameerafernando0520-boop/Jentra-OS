import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'wave3_observability_allowlist.dart';

typedef Wave3DiagnosticSink = void Function(Map<String, Object?> event);

/// Transparent bounded observation. Business bodies never leave this adapter.
final class Wave3ObservedHttpClient extends http.BaseClient {
  Wave3ObservedHttpClient(this._inner, {Wave3DiagnosticSink? sink})
    : _sink = sink ?? _log;
  final http.Client _inner;
  final Wave3DiagnosticSink _sink;
  static const metadataByteLimit = 65536;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
  );
  static const _codes = {
    'ACCESS_DENIED',
    'SOURCE_UNAVAILABLE',
    'NOT_FOUND',
    'VERSION_CONFLICT',
    'MATCH_CONFLICT',
    'COMMAND_CONFLICT',
    'IDEMPOTENCY_CONFLICT',
    'STOCK_UNAVAILABLE',
    'INSUFFICIENT_STOCK',
    'SERIAL_UNAVAILABLE',
    'TRANSFER_SERIAL_UNAVAILABLE',
    'PERIOD_CLOSED',
    'PERIOD_LOCKED',
    'CREDIT_HOLD',
    'CREDIT_LIMIT_EXCEEDED',
    'LIMIT_EXCEEDED',
    '40001',
    '42501',
    '23505',
    '55000',
    '54000',
  };

  static void _log(Map<String, Object?> event) =>
      developer.log(jsonEncode(event), name: 'jentra.wave3');
  static String? _id(Object? value) =>
      value is String && _uuid.hasMatch(value) ? value : null;
  static Map<String, Object?> _object(Object? value) =>
      value is Map<String, Object?> ? value : const {};
  static String? _code(Object? value) =>
      value is String &&
          (_codes.contains(value) || wave3ObservedOutcomeCodes.contains(value))
      ? value
      : null;

  Map<String, Object?>? _request(http.BaseRequest request) {
    if (request is! http.Request || request.method != 'POST') return null;
    final profile = request.headers.entries
        .where((e) => e.key.toLowerCase() == 'content-profile')
        .map((e) => e.value)
        .firstOrNull;
    final segments = request.url.pathSegments;
    if (profile != 'api' ||
        segments.length != 4 ||
        segments[0] != 'rest' ||
        segments[1] != 'v1' ||
        segments[2] != 'rpc' ||
        !wave3ObservedRpcs.contains(segments[3]) ||
        request.bodyBytes.length > 1048576) {
      return null;
    }
    try {
      final params = _object(jsonDecode(request.body));
      final payload = _object(params['p_payload']);
      final kinds = [payload['aggregate_type'], params['p_aggregate_type']];
      if (kinds.any(
        (kind) =>
            kind is String &&
            (kind == 'stock_opening' ||
                kind.startsWith('people_') ||
                kind.startsWith('private_hr') ||
                kind.startsWith('wave4')),
      )) {
        return null;
      }
      final command = _id(params['p_command_id']);
      return {
        'operation': segments[3],
        if (_id(params['p_tenant_id']) case final String id) 'tenant_id': id,
        if (_id(params['p_legal_entity_id']) case final String id)
          'legal_entity_id': id,
        if (_id(params['p_branch_id']) case final String id) 'branch_id': id,
        'command_id': ?command,
        if (_id(params['p_correlation_id']) ?? command case final String id)
          'correlation_id': id,
      };
    } on Object {
      return null;
    }
  }

  void _emit(Map<String, Object?> event) {
    try {
      _sink(Map.unmodifiable(event));
    } on Object {
      // Diagnostic failure cannot change authoritative request outcome.
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final metadata = _request(request);
    if (metadata == null) return _inner.send(request);
    final timer = Stopwatch()..start();
    http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } on Object {
      _emit({
        ...metadata,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'elapsed_us': timer.elapsedMicroseconds,
        'outcome': 'transport_uncertain',
      });
      rethrow;
    }
    Stream<List<int>> observed() async* {
      final bytes = <int>[];
      var oversized = false, complete = false;
      try {
        await for (final chunk in response.stream) {
          if (!oversized) {
            if (bytes.length + chunk.length <= metadataByteLimit) {
              bytes.addAll(chunk);
            } else {
              oversized = true;
              bytes.clear();
            }
          }
          yield chunk;
        }
        complete = true;
      } finally {
        Map<String, Object?> result = const {};
        if (complete && !oversized) {
          try {
            result = _object(jsonDecode(utf8.decode(bytes)));
          } on Object {
            // Malformed/non-JSON responses remain unchanged for the gateway.
          }
        }
        final error = _object(result['error']);
        final code =
            _code(error['code']) ??
            _code(result['message']) ??
            _code(result['code']);
        final data = _object(result['data']);
        final entity = _object(result['entity']);
        final summary = _object(
          data['summary'] ?? entity['summary'] ?? result['summary'],
        );
        final event = <String, Object?>{
          ...metadata,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'elapsed_us': timer.elapsedMicroseconds,
          'http_status': response.statusCode,
          'outcome': !complete
              ? 'transport_uncertain'
              : response.statusCode >= 400 || result['success'] == false
              ? 'rejected'
              : 'response_received',
          'outcome_code': ?code,
          if (_id(result['request_id']) case final String id) 'request_id': id,
          if (_id(result['correlation_id']) case final String id)
            'correlation_id': id,
        };
        for (final field in [
          'difference_count',
          'blocker_count',
          'dead_letter_depth',
        ]) {
          final value =
              result[field] ?? data[field] ?? entity[field] ?? summary[field];
          if (value is int && value >= 0) {
            event[field] = value;
          }
          if (value is String && RegExp(r'^[0-9]{1,10}$').hasMatch(value)) {
            event[field] = value;
          }
        }
        _emit(event);
      }
    }

    return http.StreamedResponse(
      observed(),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
