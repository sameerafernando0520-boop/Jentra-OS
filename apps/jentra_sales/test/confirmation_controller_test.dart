import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation.dart';
import 'package:jentra_sales/src/confirmation_controller.dart';

final confirmationOffer = <String, dynamic>{
  'request_id': 'request',
  'request_version': '2',
  'source_digest': List.filled(64, 'a').join(),
  'valid_until': '2026-11-03T12:00:00Z',
  'company': 'Jentra Company',
  'customer': 'Authorized customer',
  'reference': 'ORDER-1',
  'currency_code': 'LKR',
  'discount_percent': '10.000000',
  'terms': {
    'ship_to': {
      'address': {'line1': 'Customer address'},
      'postcode': 12345,
    },
    'payment_terms_days': '30',
    'delivery_terms': 'Company delivery',
    'requested_date': '2026-11-03',
  },
  'totals': {
    'subtotal': '1.410000',
    'discount_total': '0.140000',
    'tax_total': '0.000000',
    'grand_total': '1.270000',
  },
  'lines': [
    {
      'description': 'Product',
      'quantity': '1.125000',
      'unit': 'ea',
      'unit_price': '1.250000',
      'line_total': '1.270000',
      'tax_amount': '0.000000',
      'tax_rate': '0.000000',
      'tax_inclusive': false,
    },
  ],
};

class FakeConfirmationGateway implements FieldConfirmationGateway {
  int requests = 0, verifications = 0;
  bool failResponse = false;
  FieldSalesJson? reviewOffer;
  String receiptVersion = '2';
  Completer<FieldSalesJson>? verification;
  final responses = <(String, String, bool)>[];
  @override
  Future<FieldSalesJson> requestCode(String token) async {
    requests++;
    return {'state': 'check_email'};
  }

  @override
  Future<FieldSalesJson> verify(String token, String code) {
    verifications++;
    return verification?.future ??
        Future.value({
          'state': 'review',
          'proof': List.filled(64, 'a').join(),
          'offer': reviewOffer ?? confirmationOffer,
        });
  }

  @override
  Future<FieldSalesJson> respond(
    String token,
    String proof,
    String response,
    String reason,
    bool authorized,
  ) async {
    responses.add((response, reason, authorized));
    if (failResponse) throw Exception('network');
    return {
      'state': 'recorded',
      'id': 'response',
      'request_id': 'request',
      'request_version': receiptVersion,
      'source_digest': List.filled(64, 'a').join(),
      'response': response == 'accept' ? 'accepted' : 'rejected',
      'method': 'email_link_and_code',
    };
  }
}

void main() {
  for (final defect in [
    'reference',
    'discount',
    'line_discount',
    'numeric_total',
  ]) {
    test('corrupt $defect cannot enter the reviewed recipient terms', () async {
      final corrupt = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(confirmationOffer)) as Map,
      );
      switch (defect) {
        case 'reference':
          corrupt['reference'] = 123;
        case 'discount':
          corrupt['discount_percent'] = 10.0;
        case 'line_discount':
          (corrupt['lines'] as List).first['header_discount_amount'] = 0.14;
        case 'numeric_total':
          corrupt['totals']['grand_total'] = 1.27;
      }
      final gateway = FakeConfirmationGateway()..reviewOffer = corrupt;
      final c = ConfirmationController(token: 'ab' * 32, gateway: gateway);
      addTearDown(c.dispose);
      await c.requestCode();
      await c.verify('482619');
      expect(c.stage, ConfirmationStage.unavailable);
      expect(c.offer, isNull);
      expect(gateway.responses, isEmpty);
    });
  }
  test(
    'receipt for a different revision never acknowledges the original response',
    () async {
      final gateway = FakeConfirmationGateway()..receiptVersion = '3';
      final c = ConfirmationController(token: 'ab' * 32, gateway: gateway);
      addTearDown(c.dispose);
      await c.requestCode();
      await c.verify('482619');
      await c.respond('accept', '', true);
      expect(c.stage, ConfirmationStage.review);
      expect(c.hasPending, isTrue);
      expect(c.recordedResponse, isNull);
      gateway.receiptVersion = '2';
      await c.retryOriginal();
      expect(c.stage, ConfirmationStage.complete);
    },
  );
  test('opening a link performs no request and requires both explicit verification steps', () async {
    final gateway = FakeConfirmationGateway();
    final c = ConfirmationController(
      token: List.filled(64, 'a').join(),
      gateway: gateway,
    );
    addTearDown(c.dispose);
    expect(gateway.requests, 0);
    expect(c.offer, isNull);
    await c.requestCode();
    expect(c.stage, ConfirmationStage.code);
    await c.verify('482619');
    expect(c.stage, ConfirmationStage.review);
    expect(gateway.responses, isEmpty);
    await c.respond('accept', '', false);
    expect(gateway.responses, isEmpty);
    await c.respond('accept', '', true);
    expect(c.stage, ConfirmationStage.complete);
    expect(c.offer, isNull);
  });
  test('uncertain response freezes the original choice and explicit retry recovers it', () async {
    final gateway = FakeConfirmationGateway()..failResponse = true;
    final c = ConfirmationController(
      token: List.filled(64, 'a').join(),
      gateway: gateway,
    );
    addTearDown(c.dispose);
    await c.requestCode();
    await c.verify('482619');
    await c.respond('reject', 'Terms need review', true);
    expect(c.hasPending, isTrue);
    expect(c.stage, ConfirmationStage.review);
    await c.respond('accept', 'Changed choice', true);
    expect(gateway.responses.length, 1);
    gateway.failResponse = false;
    await c.retryOriginal();
    expect(gateway.responses, [
      ('reject', 'Terms need review', true),
      ('reject', 'Terms need review', true),
    ]);
    expect(c.recordedResponse, 'rejected');
  });
  test(
    'background lock fences a late verification and removes private terms',
    () async {
      final gateway = FakeConfirmationGateway()..verification = Completer();
      final c = ConfirmationController(
        token: List.filled(64, 'a').join(),
        gateway: gateway,
      );
      addTearDown(c.dispose);
      await c.requestCode();
      final pending = c.verify('482619');
      c.lock();
      gateway.verification!.complete({
        'state': 'review',
        'proof': List.filled(64, 'a').join(),
        'offer': confirmationOffer,
      });
      await pending;
      expect(c.offer, isNull);
      expect(c.stage, ConfirmationStage.unavailable);
      expect(gateway.responses, isEmpty);
    },
  );
}
