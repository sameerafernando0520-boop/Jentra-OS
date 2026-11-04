import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation.dart';

void main() {
  final token = 'ab' * 32;
  test('only an exact fragment link at the secure root is accepted', () {
    expect(
      parseFieldConfirmationLink('https://sales.example/#confirm=$token').token,
      token,
    );
    expect(
      parseFieldConfirmationLink('http://localhost/#confirm=$token').token,
      token,
    );
    for (final url in [
      'https://sales.example/?confirm=$token',
      'https://sales.example/other#confirm=$token',
      'http://sales.example/#confirm=$token',
      'https://sales.example/#confirm=$token&confirm=$token',
      'https://sales.example/#confirm=$token&other=value',
      'https://sales.example/#other=value&confirm=$token',
      'https://sales.example/#%63onfirm=$token',
      'https://sales.example/?%63onfirm=$token',
      'https://sales.example/#confirm=malformed',
    ]) {
      final link = parseFieldConfirmationLink(url);
      expect(link.present, isTrue);
      expect(link.token, isNull);
    }
    expect(
      parseFieldConfirmationLink('https://sales.example/#/login').present,
      isFalse,
    );
  });
  test('ordinary campaign values do not enter the recipient surface', () {
    expect(
      parseFieldConfirmationLink(
        'https://sales.example/?campaign=confirmation',
      ).present,
      isFalse,
    );
  });
  test(
    'recipient actions use only the three named confirmation facades',
    () async {
      final calls = <(String, FieldSalesJson)>[];
      final gateway = SupabaseFieldConfirmationGateway.withRpc((
        name,
        params,
      ) async {
        calls.add((name, params));
        return {'state': 'unavailable'};
      });
      await gateway.requestCode(token);
      await gateway.verify(token, '482619');
      await gateway.respond(token, 'cd' * 32, 'accept', '', true);
      expect(calls.map((c) => c.$1), [
        'field_sales_confirmation_request_code',
        'field_sales_confirmation_verify',
        'field_sales_confirmation_respond',
      ]);
      expect(calls.last.$2, {
        'p_token': token,
        'p_proof': 'cd' * 32,
        'p_response': 'accept',
        'p_reason': '',
        'p_authorized': true,
      });
    },
  );
  test(
    'a signed-in or late-changing actor cannot open recipient terms',
    () async {
      String? actor = 'staff';
      var calls = 0;
      final pending = Completer<Object?>();
      final gateway = SupabaseFieldConfirmationGateway.withRpc((_, _) {
        calls++;
        return pending.future;
      }, currentActor: () => actor);
      await expectLater(
        gateway.requestCode(token),
        throwsA(isA<FieldSalesFailure>()),
      );
      expect(calls, 0);
      actor = null;
      final operation = gateway.verify(token, '482619');
      actor = 'staff';
      pending.complete({
        'state': 'review',
        'offer': {'private': 'terms'},
      });
      await expectLater(operation, throwsA(isA<FieldSalesFailure>()));
    },
  );
}
