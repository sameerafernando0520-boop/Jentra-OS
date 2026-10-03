import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_controller.dart';

import 'goods_receipt_workspace_test.dart' show ReceiptGateway;
import 'product_unit_workspace_test.dart' show UnitGateway;
import 'purchase_order_workspace_test.dart' show OrderGateway;
import 'purchase_return_workspace_test.dart' show ReturnGateway;
import 'security_second_procurement_failure_epoch_test.dart' show modules;
import 'security_review_procurement_sealing_test.dart'
    show controller, seed, send, slot, scope;
import 'supplier_bill_workspace_test.dart' show BillGateway;
import 'supplier_payment_workspace_test.dart' show PaymentGateway;
import 'support/procurement_fakes.dart' show Gateway, Keys;

// Hold an already transmitted command, independently of local encryption/read
// delays. The transport loses its result after the controller's access changes.
mixin HeldCommand on Gateway {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Map<String, Object?>> source(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (commands.length == 1) {
      entered.complete();
      await release.future;
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The obsolete transport cannot confirm this command.',
      );
    }
    return {
      'id': command.payload['id'] ?? command.payload['document_id'],
      'status': 'issued',
      'version': 2,
    };
  }
}

class _Base extends Gateway with HeldCommand {}

class _Order extends OrderGateway with HeldCommand {
  // OrderGateway's private _result bypasses source(), unlike the other fakes.
  @override
  Future<Map<String, Object?>> transitionOrder(
    CommandEnvelope<Map<String, Object?>> command,
  ) => source(command);

  @override
  Future<Map<String, Object?>> saveOrder(
    CommandEnvelope<Map<String, Object?>> command,
  ) => source(command);
}

class _Receipt extends ReceiptGateway with HeldCommand {}

class _Bill extends BillGateway with HeldCommand {}

class _Payment extends PaymentGateway with HeldCommand {}

class _Unit extends UnitGateway with HeldCommand {}

class _Return extends ReturnGateway with HeldCommand {}

dynamic _gateway(String module) => switch (module) {
  'order' => _Order(),
  'receipt' => _Receipt(),
  'bill' => _Bill(),
  'payment' => _Payment(),
  'unit' => _Unit(),
  'return' => _Return(),
  _ => _Base(),
};

dynamic _controller(
  String module,
  dynamic gateway,
  QuotationDraftStore drafts,
) => module == 'receipt'
    ? GoodsReceiptController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: drafts,
        online: true,
        canPost: true,
      )
    : controller(module, gateway, drafts);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final module in modules) {
    for (final replacement in ['reconnect', 'dispose']) {
      test(
        '$module preserves transmitted uncertainty across $replacement and retries original request',
        () async {
          final db = JentraLocalDatabase(NativeDatabase.memory());
          final keys = Keys();
          final store = QuotationDraftStore.procurement(
            EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          );
          final dynamic gateway = _gateway(module);
          final dynamic c = _controller(module, gateway, store);
          var disposed = false;
          try {
            await c.initialize();
            await seed(module, c);
            final sending = send(module, c);
            await (gateway.entered as Completer<void>).future.timeout(
              const Duration(seconds: 5),
            );
            expect(gateway.commands, hasLength(1));
            final original = jsonEncode(
              gateway.commands.single.toJson((x) => x),
            );
            expect((await store.load(scope, slot(module)))?.pending, isNotNull);
            if (replacement == 'dispose') {
              c.dispose();
              disposed = true;
            } else {
              c.setOnline(false);
              c.setOnline(true);
            }
            (gateway.release as Completer<void>).complete();
            await sending;
            expect(
              c.error,
              isNull,
              reason: 'Obsolete failure cannot replace current guidance.',
            );
            expect(c.accessDenied, isFalse);
            expect(c.page.items, isEmpty);
            final retained = (await store.load(scope, slot(module)))!;
            expect(retained.pending, isNotNull);
            expect(
              jsonEncode(retained.pending!.envelope.toJson((x) => x)),
              original,
            );
            expect(retained.errorCode, 'UNCERTAIN_RESULT');
            if (!disposed) {
              c.dispose();
              disposed = true;
            }
            // A new repository and cipher model a genuine encrypted restart.
            final freshStore = QuotationDraftStore.procurement(
              EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
            );
            final dynamic fresh = _controller(module, gateway, freshStore);
            try {
              await fresh.initialize();
              expect(fresh.locked, isTrue);
              await send(module, fresh, retry: true);
              expect(fresh.error, isNull);
              expect(gateway.commands, hasLength(2));
              expect(
                jsonEncode(gateway.commands.last.toJson((x) => x)),
                original,
              );
              expect(
                (await freshStore.load(scope, slot(module)))?.pending,
                isNull,
              );
            } finally {
              fresh.dispose();
            }
          } finally {
            if (!(gateway.release as Completer<void>).isCompleted) {
              (gateway.release as Completer<void>).complete();
            }
            if (!disposed) c.dispose();
            await db.close();
          }
        },
      );
    }
  }
}
