import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_controller.dart';

import 'procurement_access_recovery_test.dart'
    show
        Bills,
        Payments,
        Receipts,
        Returns,
        Requisitions,
        Sourcing,
        Orders,
        Units,
        ReadState;
import 'security_review_procurement_sealing_test.dart'
    show controller, seed, send, slot, scope;
import 'support/procurement_fakes.dart' show Keys;

const modules = [
  'requisition',
  'order',
  'receipt',
  'bill',
  'payment',
  'unit',
  'sourcing',
  'return',
];
const denialCodes = [
  'PERMISSION_DENIED',
  'ACCESS_DENIED',
  'MFA_REQUIRED',
  'AUTHENTICATION_REQUIRED',
];

class HeldPayments extends Payments {
  @override
  Future<CursorPage<Map<String, Object?>>> payments(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

dynamic gatewayFor(String name) => switch (name) {
  'requisition' => Requisitions(),
  'order' => Orders(),
  'receipt' => Receipts(),
  'bill' => Bills(),
  'payment' => HeldPayments(),
  'unit' => Units(),
  'sourcing' => Sourcing(),
  _ => Returns(),
};

Future<void> waitForRead(ReadState state) async {
  for (var i = 0; i < 1000 && !state.called; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(
    state.called,
    isTrue,
    reason: 'The controlled register read must be in flight.',
  );
}

void expectCleared(dynamic c, String name) {
  expect(c.accessDenied, isTrue);
  expect(c.page.items, isEmpty);
  if (name != 'unit') expect(c.selected, isNull);
  if (name == 'requisition') {
    expect(c.units, isEmpty);
    expect(c.baseCurrency, isNull);
  }
  if (name == 'return') {
    expect(c.sources, isEmpty);
    expect(c.sourceCursor, isNull);
  }
  if (name == 'payment') {
    expect(c.eligible, isEmpty);
    expect(c.statementReport, isNull);
    expect(c.itemDetail, isNull);
    expect(c.allocationTargets, isEmpty);
    expect(c.allocationRates, isEmpty);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in modules) {
    for (final change in ['reconnect', 'dispose']) {
      test(
        '$name obsolete $change read failure does not change error or revoke replacement',
        () async {
          final db = JentraLocalDatabase(NativeDatabase.memory());
          final drafts = QuotationDraftStore.procurement(
            EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
          );
          final dynamic gateway = gatewayFor(name);
          final ReadState read = gateway.state as ReadState;
          final dynamic c = name == 'receipt'
              ? GoodsReceiptController(
                  scope: scope,
                  gateway: gateway,
                  references: gateway,
                  drafts: drafts,
                  online: true,
                  canPost: true,
                )
              : controller(name, gateway, drafts);
          var disposed = false;
          try {
            read.reply = Completer();
            final loading = c.initialize() as Future<void>;
            await waitForRead(read);
            if (change == 'dispose') {
              c.dispose();
              disposed = true;
            } else {
              c.setOnline(false);
              c.setOnline(true);
            }
            read.reply!.completeError(
              const DomainError(
                code: 'PERMISSION_DENIED',
                message: 'Obsolete rejected reply',
              ),
            );
            await loading;
            expect(c.error, isNull);
            expect(c.accessDenied, isFalse);
          } finally {
            if (!disposed) c.dispose();
            await db.close();
          }
        },
      );
    }
    for (final code in [...denialCodes, 'obsolete', 'unavailable']) {
      test(
        '$name confirmed optional $code failure retains acknowledgement and enforces current epoch',
        () async {
          final db = JentraLocalDatabase(NativeDatabase.memory());
          final drafts = QuotationDraftStore.procurement(
            EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
          );
          final dynamic gateway = gatewayFor(name);
          gateway.uncertain = false;
          final ReadState read = gateway.state as ReadState;
          final dynamic c = name == 'receipt'
              ? GoodsReceiptController(
                  scope: scope,
                  gateway: gateway,
                  references: gateway,
                  drafts: drafts,
                  online: true,
                  canPost: true,
                )
              : controller(name, gateway, drafts);
          try {
            await c.initialize();
            await seed(name, c);
            read.called = false;
            read.reply = Completer();
            final sending = send(name, c);
            await waitForRead(read);
            expect(gateway.commands, hasLength(1));
            expect(
              (await drafts.load(scope, slot(name)))?.pending,
              isNull,
              reason: 'Confirmation must be durable before the optional read.',
            );
            if (code == 'obsolete') {
              c.setOnline(false);
              c.setOnline(true);
            }
            read.reply!.completeError(
              DomainError(
                code: code == 'obsolete'
                    ? 'PERMISSION_DENIED'
                    : code == 'unavailable'
                    ? 'READ_UNAVAILABLE'
                    : code,
                message: code == 'unavailable'
                    ? 'Private transport diagnostic must not be shown.'
                    : 'Recheck current access.',
              ),
            );
            await sending;
            expect(
              gateway.commands,
              hasLength(1),
              reason: 'A refresh failure cannot resend a known confirmation.',
            );
            expect((await drafts.load(scope, slot(name)))?.pending, isNull);
            if (code == 'obsolete') {
              expect(c.error, isNull);
              expect(c.accessDenied, isFalse);
            } else if (code == 'unavailable') {
              expect(c.accessDenied, isFalse);
              expect(c.error, isNotNull);
              expect(c.error, isNot(contains('Private transport')));
              final commandsBeforeRetry = gateway.commands.length;
              await send(name, c, retry: true);
              expect(
                gateway.commands,
                hasLength(commandsBeforeRetry),
                reason: 'Confirmed refresh failure cannot recreate a command.',
              );
            } else {
              expectCleared(c, name);
              expect(c.error, 'Recheck current access.');
            }
          } finally {
            c.dispose();
            await db.close();
          }
        },
      );
    }
  }
}
