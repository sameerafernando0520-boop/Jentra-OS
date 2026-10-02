import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/src/wave3_observability.dart';

const tenant = '11111111-1111-1111-1111-111111111111';
const entity = '22222222-2222-2222-2222-222222222222';
const branch = '33333333-3333-3333-3333-333333333333';
const command = '44444444-4444-4444-4444-444444444444';
const correlation = '55555555-5555-5555-5555-555555555555';
http.Request request({
  String rpc = 'post_manual_journal',
  String profile = 'api',
  Object? body,
  String method = 'POST',
}) =>
    http.Request(
        method,
        Uri.parse('https://synthetic.invalid/rest/v1/rpc/$rpc'),
      )
      ..headers.addAll({
        'Content-Profile': profile,
        'Authorization': 'Bearer NEVER_LOG_THIS',
      })
      ..body = jsonEncode(
        body ??
            {
              'p_tenant_id': tenant,
              'p_legal_entity_id': entity,
              'p_branch_id': branch,
              'p_command_id': command,
              'p_payload': {
                'bank_credentials': 'BANK_SECRET',
                'contact': 'person@example.test',
              },
            },
      );

final class StreamClient extends http.BaseClient {
  StreamClient(this.stream);
  final Stream<List<int>> stream;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        stream,
        200,
        reasonPhrase: 'OK',
        headers: {'x-test': 'kept'},
        request: request,
      );
  @override
  void close() {
    closed = true;
  }
}

void main() {
  test(
    'generated receivables posting and drafting RPCs carry scoped latency',
    () async {
      final events = <Map<String, Object?>>[];
      final client = Wave3ObservedHttpClient(
        MockClient((r) async => http.Response('{}', 200)),
        sink: events.add,
      );
      for (final kind in [
        'delivery',
        'sales_invoice',
        'customer_receipt',
        'sales_return',
      ]) {
        for (final action in ['post', 'upsert']) {
          final rpc = '${action}_$kind';
          await http.Response.fromStream(await client.send(request(rpc: rpc)));
          expect(events.last['operation'], rpc);
          expect(events.last['branch_id'], branch);
          expect(events.last['elapsed_us'], isNonNegative);
        }
      }
      for (final rpc in [
        'post_supplier_bill',
        'approve_supplier_bill_match',
        'cancel_supplier_bill',
      ]) {
        await http.Response.fromStream(await client.send(request(rpc: rpc)));
        expect(events.last['operation'], rpc);
        expect(events.last['command_id'], command);
      }
      expect(events, hasLength(11));
      client.close();
    },
  );
  test(
    'diagnostics redact bodies and headers while preserving authoritative response bytes and correlation',
    () async {
      final events = <Map<String, Object?>>[];
      const raw =
          '{"success":true,"correlation_id":"$correlation","request_id":"$correlation",'
          '"data":{"summary":{"difference_count":2,"blocker_count":"3"},'
          '"contact":"person@example.test","secret":"BANK_SECRET"}}';
      final client = Wave3ObservedHttpClient(
        MockClient((r) async => http.Response(raw, 200)),
        sink: events.add,
      );
      final response = await http.Response.fromStream(
        await client.send(request()),
      );
      expect(response.body, raw);
      expect(events, hasLength(1));
      final event = events.single;
      expect(event['tenant_id'], tenant);
      expect(event['legal_entity_id'], entity);
      expect(event['branch_id'], branch);
      expect(event['command_id'], command);
      expect(event['correlation_id'], correlation);
      expect(event['request_id'], correlation);
      expect(event['difference_count'], 2);
      expect(event['blocker_count'], '3');
      expect(event['elapsed_us'], isNonNegative);
      for (final value in [
        'NEVER_LOG_THIS',
        'BANK_SECRET',
        'person@example.test',
        'p_payload',
      ]) {
        expect(jsonEncode(event), isNot(contains(value)));
      }
      expect(() => event['contact'] = 'change', throwsUnsupportedError);
      client.close();
    },
  );

  test(
    'approved conflict and stock codes are observable without arbitrary error text',
    () async {
      for (final code in [
        'MATCH_CONFLICT',
        'TRANSFER_SERIAL_UNAVAILABLE',
        'PERIOD_CLOSED',
        'ACCESS_DENIED',
        'DISPOSITION_SERIAL_REVERSAL_DENIED',
      ]) {
        final events = <Map<String, Object?>>[];
        final client = Wave3ObservedHttpClient(
          MockClient(
            (r) async => http.Response(
              jsonEncode({
                'code': '55000',
                'message': code,
                'details': 'private@example.test',
              }),
              400,
            ),
          ),
          sink: events.add,
        );
        await http.Response.fromStream(await client.send(request()));
        expect(events.single['outcome'], 'rejected');
        expect(events.single['outcome_code'], code);
        expect(jsonEncode(events), isNot(contains('private@example.test')));
      }
      final events = <Map<String, Object?>>[];
      final client = Wave3ObservedHttpClient(
        MockClient(
          (r) async => http.Response(
            jsonEncode({
              'success': false,
              'error': {'code': 'MATCH_CONFLICT', 'message': 'Private reason'},
              'dead_letter_depth': '5',
            }),
            200,
          ),
        ),
        sink: events.add,
      );
      await http.Response.fromStream(await client.send(request()));
      expect(events.single['outcome_code'], 'MATCH_CONFLICT');
      expect(events.single['outcome'], 'rejected');
      expect(events.single['dead_letter_depth'], '5');
      expect(events.single['correlation_id'], command);
      events.clear();
      final posted = Wave3ObservedHttpClient(
        MockClient(
          (r) async => http.Response(
            jsonEncode({
              'entity': {
                'summary': {'difference_count': '2', 'blocker_count': 3},
              },
            }),
            200,
          ),
        ),
        sink: events.add,
      );
      await http.Response.fromStream(await posted.send(request()));
      expect(events.single['difference_count'], '2');
      expect(events.single['blocker_count'], 3);
    },
  );

  test(
    'auth, Storage, opening, Wave 4, invalid and oversized inputs remain unobserved',
    () async {
      final events = <Map<String, Object?>>[];
      var sends = 0;
      final client = Wave3ObservedHttpClient(
        MockClient((r) async {
          sends++;
          return http.Response('{}', 200);
        }),
        sink: events.add,
      );
      final inputs = [
        request(rpc: 'post_stock_opening'),
        request(rpc: 'people_private_hr'),
        request(profile: 'public'),
        request(method: 'GET'),
        request(body: {'p_aggregate_type': 'stock_opening'}),
        request(
          body: {
            'p_payload': {'aggregate_type': 'stock_opening'},
          },
        ),
        request(body: {'p_aggregate_type': 'people_employee'}),
        request(
          body: {
            'p_payload': {'aggregate_type': 'private_hr_request'},
          },
        ),
        request(body: {'p_payload': 'x' * 1048577}),
        request()..body = 'invalid-json',
        http.Request(
          'POST',
          Uri.parse('https://synthetic.invalid/auth/v1/token'),
        ),
        http.MultipartRequest(
          'POST',
          Uri.parse('https://synthetic.invalid/storage/v1/object/private'),
        ),
        http.Request(
          'POST',
          Uri.parse('https://synthetic.invalid/rest/v1/rpc'),
        ),
      ];
      for (final r in inputs) {
        await http.Response.fromStream(await client.send(r));
      }
      expect(sends, inputs.length);
      expect(events, isEmpty);
    },
  );

  test(
    'transport and partial stream failures remain uncertain and are never retried',
    () async {
      final events = <Map<String, Object?>>[];
      var sends = 0;
      final client = Wave3ObservedHttpClient(
        MockClient((r) async {
          sends++;
          throw TimeoutException('secret token and contact');
        }),
        sink: events.add,
      );
      await expectLater(
        client.send(request()),
        throwsA(isA<TimeoutException>()),
      );
      expect(sends, 1);
      expect(events.single['outcome'], 'transport_uncertain');
      expect(jsonEncode(events), isNot(contains('secret token')));
      events.clear();
      final inner = StreamClient(
        Stream<List<int>>.fromIterable([utf8.encode('{')]).asyncExpand((
          c,
        ) async* {
          yield c;
          throw StateError('private body');
        }),
      );
      final streamClient = Wave3ObservedHttpClient(inner, sink: events.add);
      await expectLater(
        http.Response.fromStream(await streamClient.send(request())),
        throwsStateError,
      );
      expect(events.single['outcome'], 'transport_uncertain');
      streamClient.close();
      expect(inner.closed, true);
    },
  );

  test(
    'oversized/non-JSON responses and diagnostic sink failures preserve the result',
    () async {
      for (final raw in [
        'x' * 70000,
        'not-json',
        '[]',
        '{"code":"Private reason","blocker_count":-1}',
      ]) {
        final events = <Map<String, Object?>>[];
        final inner = StreamClient(Stream.value(utf8.encode(raw)));
        final client = Wave3ObservedHttpClient(inner, sink: events.add);
        final response = await http.Response.fromStream(
          await client.send(request(body: {'p_tenant_id': 'not-a-uuid'})),
        );
        expect(response.body, raw);
        expect(response.headers['x-test'], 'kept');
        expect(response.reasonPhrase, 'OK');
        expect(events.single.containsKey('tenant_id'), false);
        expect(events.single.containsKey('outcome_code'), false);
        expect(events.single.containsKey('blocker_count'), false);
      }
      final client = Wave3ObservedHttpClient(
        MockClient((r) async => http.Response('{}', 200)),
        sink: (e) => throw StateError('disk unavailable'),
      );
      expect(
        (await http.Response.fromStream(await client.send(request()))).body,
        '{}',
      );
    },
  );
}
