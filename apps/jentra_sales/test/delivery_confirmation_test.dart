import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation.dart';
import 'package:jentra_sales/src/confirmation_controller.dart';
import 'package:jentra_sales/src/delivery_confirmation_controller.dart';
import 'package:jentra_sales/src/ui/delivery_confirmation.dart';

const deliveryId = '11111111-1111-4111-8111-111111111111';
const lineId = '22222222-2222-4222-8222-222222222222';
final deliveryOffer = <String, dynamic>{
  'delivery_id': deliveryId,
  'delivery_version': '9007199254740993',
  'delivery_digest': 'd' * 64,
  'document_number': 'DL-SYNTHETIC-1',
  'posted_at': '2026-11-03T00:00:00Z',
  'company': 'Organization One',
  'customer': 'Authorized Customer',
  'lines': [
    {
      'id': lineId,
      'description': 'Synthetic delivery item',
      'posted_base_quantity': '0.500000',
      'base_unit': 'ea',
    },
  ],
};
List<FieldSalesJson> amounts() => [
  {
    'id': lineId,
    'received': '0.300000',
    'refused': '0.100000',
    'short': '0.100000',
  },
];

class FakeDeliveryGateway implements FieldDeliveryGateway {
  int requests = 0, verifications = 0;
  bool fail = false, wrongVersion = false;
  FieldSalesJson? offer;
  Completer<FieldSalesJson>? gate;
  final responses = <FieldSalesJson>[];
  @override
  Future<FieldSalesJson> requestCode(String token) async {
    requests++;
    return {'state': 'check_email'};
  }

  @override
  Future<FieldSalesJson> verify(String token, String code) {
    verifications++;
    return gate?.future ??
        Future.value({
          'state': 'review',
          'proof': 'a' * 64,
          'offer': offer ?? deliveryOffer,
        });
  }

  @override
  Future<FieldSalesJson> respond(
    String token,
    String proof,
    List<FieldSalesJson> quantities,
    String reason,
    bool authorized,
  ) async {
    responses.add(
      fieldSalesObject(
        jsonDecode(
          jsonEncode({
            'quantities': quantities,
            'reason': reason,
            'authorized': authorized,
          }),
        ),
      ),
    );
    if (fail) throw Exception('synthetic interruption');
    final q = quantities.single;
    return {
      'state': 'recorded',
      'id': '33333333-3333-4333-8333-333333333333',
      'delivery_id': deliveryId,
      'delivery_version': wrongVersion
          ? '1'
          : deliveryOffer['delivery_version'],
      'delivery_digest': deliveryOffer['delivery_digest'],
      'quantities': quantities,
      'response':
          DeliveryConfirmationController.units(q['received'] as String) ==
              DeliveryConfirmationController.units('0.5')
          ? 'received'
          : DeliveryConfirmationController.units(q['refused'] as String) ==
                DeliveryConfirmationController.units('0.5')
          ? 'refused'
          : 'exception',
      'method': 'delivery_email_and_code',
    };
  }
}

(DeliveryConfirmationController, FakeDeliveryGateway) make() {
  final g = FakeDeliveryGateway();
  final controller = DeliveryConfirmationController(
    token: 'f' * 64,
    gateway: g,
  );
  addTearDown(controller.dispose);
  return (controller, g);
}

Future<void> review(DeliveryConfirmationController c) async {
  await c.requestCode();
  await c.verify('123456');
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test('opening a delivery link makes no request and grants no access', () {
    final (c, g) = make();
    expect(g.requests, 0);
    expect(g.verifications, 0);
    expect(g.responses, isEmpty);
    expect(c.offer, isNull);
    expect(c.stage, ConfirmationStage.start);
  });
  for (final defect in ['numeric quantity', 'duplicate line', 'wrong digest']) {
    test('delivery review rejects $defect', () async {
      final (c, g) = make();
      g.offer = fieldSalesObject(jsonDecode(jsonEncode(deliveryOffer)));
      switch (defect) {
        case 'numeric quantity':
          g.offer!['lines'][0]['posted_base_quantity'] = 0.5;
        case 'duplicate line':
          g.offer!['lines'].add(Map.of(g.offer!['lines'][0] as Map));
        case 'wrong digest':
          g.offer!['delivery_digest'] = 'short';
      }
      await review(c);
      expect(c.stage, ConfirmationStage.unavailable);
      expect(c.offer, isNull);
      expect(g.responses, isEmpty);
    });
  }
  test(
    'authority exact totals and an exception note are required before dispatch',
    () async {
      final (c, g) = make();
      await review(c);
      await c.respond(amounts(), 'Short and refused', false);
      expect(g.responses, isEmpty);
      await c.respond(
        [
          {...amounts().single, 'received': '0.500000'},
        ],
        'Mismatch',
        true,
      );
      expect(g.responses, isEmpty);
      await c.respond(amounts(), '', true);
      expect(g.responses, isEmpty);
      await c.respond(amounts(), 'Short and refused', true);
      expect(g.responses, hasLength(1));
      expect(c.stage, ConfirmationStage.complete);
      expect(c.recordedResponse, 'exception');
      expect(c.offer, isNull);
    },
  );
  test('uncertain response freezes the original quantities and note until explicit retry', () async {
    final (c, g) = make();
    await review(c);
    g.fail = true;
    final original = amounts();
    await c.respond(original, 'Original exception', true);
    expect(c.hasPending, isTrue);
    expect(g.responses, hasLength(1));
    original.single['received'] = '0.500000';
    await c.respond(original, 'Different decision', true);
    expect(g.responses, hasLength(1));
    g.fail = false;
    await c.retryOriginal();
    expect(g.responses.last, g.responses.first);
    expect(g.responses.last['reason'], 'Original exception');
    expect(c.stage, ConfirmationStage.complete);
    expect(c.hasPending, isFalse);
  });
  test('receipt must bind the exact posted version even beyond the JavaScript integer range', () async {
    final (c, g) = make();
    await review(c);
    g.wrongVersion = true;
    await c.respond(amounts(), 'Original exception', true);
    expect(c.hasPending, isTrue);
    expect(c.stage, ConfirmationStage.review);
    g.wrongVersion = false;
    await c.retryOriginal();
    expect(c.stage, ConfirmationStage.complete);
  });
  test('locking the page discards a late private delivery review', () async {
    final (c, g) = make();
    await c.requestCode();
    g.gate = Completer();
    final operation = c.verify('123456');
    c.lock();
    g.gate!.complete({
      'state': 'review',
      'proof': 'a' * 64,
      'offer': deliveryOffer,
    });
    await operation;
    expect(c.stage, ConfirmationStage.unavailable);
    expect(c.offer, isNull);
    expect(g.responses, isEmpty);
  });
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets(
      'delivery quantities at $width support 200 percent text and explicit recording',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (c, g) = make();
        await review(c);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: CustomerDeliveryPage(c),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(g.responses, isEmpty);
        await scrollTo(
          tester,
          find.text('Mark all posted quantities received'),
        );
        await tester.tap(find.text('Mark all posted quantities received'));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await scrollTo(tester, find.text('Record delivery quantities'));
        await tester.tap(find.text('Record delivery quantities'));
        await tester.pumpAndSettle();
        expect(g.responses, hasLength(1));
        expect(c.recordedResponse, 'received');
        expect(c.offer, isNull);
        expect(find.text('Synthetic delivery item'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'backgrounding a reviewed delivery clears all private quantities',
    (tester) async {
      final (c, g) = make();
      await review(c);
      await tester.pumpWidget(CustomerDeliveryApp(c));
      await tester.pumpAndSettle();
      expect(find.textContaining('Organization One'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(c.stage, ConfirmationStage.unavailable);
      expect(find.textContaining('Organization One'), findsNothing);
      expect(g.responses, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
