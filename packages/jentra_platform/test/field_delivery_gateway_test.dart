import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation.dart';

void main() {
  test(
    'delivery links use an exact distinct raw fragment and every malformed form is scrubbed',
    () {
      final token = 'a' * 64;
      final good = parseFieldConfirmationLink(
        'https://example.invalid/#delivery=$token',
      );
      expect(good.present, isTrue);
      expect(good.delivery, isTrue);
      expect(good.token, token);
      for (final url in [
        'https://example.invalid/?delivery=$token',
        'https://example.invalid/nested#delivery=$token',
        'https://example.invalid/#%64elivery=$token',
        'https://example.invalid/#delivery=$token&delivery=$token',
        'https://example.invalid/#delivery=$token&confirm=$token',
      ]) {
        final link = parseFieldConfirmationLink(url);
        expect(link.present, isTrue, reason: url);
        expect(link.token, isNull, reason: url);
      }
      expect(
        parseFieldConfirmationLink(
          'https://example.invalid/?campaign=delivery',
        ).present,
        isFalse,
      );
      expect(
        parseFieldConfirmationLink(
          'https://example.invalid/#confirm=$token',
        ).delivery,
        isFalse,
      );
    },
  );
  test(
    'delivery recipient calls only its three purpose-specific anonymous facades',
    () async {
      final calls = <(String, FieldSalesJson)>[];
      final gateway = SupabaseFieldDeliveryGateway.withRpc((name, p) async {
        calls.add((name, p));
        return {'state': 'unavailable'};
      });
      await gateway.requestCode('token');
      await gateway.verify('token', '123456');
      await gateway.respond(
        'token',
        'proof',
        [
          {'id': 'line', 'received': '1', 'refused': '0', 'short': '0'},
        ],
        '',
        true,
      );
      expect(calls.map((c) => c.$1), [
        'field_sales_delivery_request_code',
        'field_sales_delivery_verify',
        'field_sales_delivery_respond',
      ]);
      expect(calls.last.$2['p_quantities'], [
        {'id': 'line', 'received': '1', 'refused': '0', 'short': '0'},
      ]);
      expect(calls.last.$2.containsKey('p_response'), isFalse);
    },
  );
  test(
    'a late signed-in actor cannot receive private delivery terms',
    () async {
      String? actor;
      final gate = Completer<Object?>();
      final gateway = SupabaseFieldDeliveryGateway.withRpc(
        (_, _) => gate.future,
        currentActor: () => actor,
      );
      final operation = gateway.verify('token', '123456');
      actor = 'staff';
      gate.complete({'state': 'review', 'private': 'must not return'});
      await expectLater(operation, throwsA(isA<FieldSalesFailure>()));
    },
  );
}
