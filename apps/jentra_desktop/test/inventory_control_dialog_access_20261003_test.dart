import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_screen.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_screen.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_controller.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_screen.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_screen.dart';

import '../../../packages/jentra_domain/test/support/landed_extension_fixture.dart';
import 'support/procurement_fakes.dart' show Keys;
import 'stock_count_workspace_test.dart' as count_fixture;
import 'disposition_workspace_test.dart' as disposition_fixture;
import 'landed_extension_workspace_test.dart' as landed_fixture;
import 'control_reconciliation_workspace_test.dart' as control_fixture;

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);

final class Harness {
  Harness({
    required this.open,
    required this.disconnect,
    required this.reauthorize,
    required this.deny,
    required this.dispose,
    required this.commands,
    required this.confirmLabel,
  });
  final Future<void> Function(BuildContext) open;
  final void Function() disconnect, dispose;
  final Future<void> Function() reauthorize, deny;
  final List<CommandEnvelope<Map<String, Object?>>> commands;
  final String confirmLabel;
  bool disposed = false;
  void close() {
    if (!disposed) {
      dispose();
      disposed = true;
    }
  }
}

final class PausedLandedReads extends landed_fixture.Landed {
  final firstEntered = Completer<void>(), firstReply = Completer<void>();
  final resources = <String>[];
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    resources.add(resource);
    if (resources.length == 1) {
      firstEntered.complete();
      await firstReply.future;
    }
    return {'items': <Object?>[]};
  }
}

Future<Harness> make(String kind, JentraLocalDatabase db) async {
  final repository = EncryptedDraftRepository(
    db,
    DraftCipher(keyStore: Keys()),
  );
  final drafts = QuotationDraftStore(repository);
  final form = <String, Object?>{
    'id': '20000000-0000-0000-0000-000000000001',
    'version': 1,
    'status': 'draft',
    'document_date': '2026-09-29',
    'reason': 'Document cancellation',
    'lines': <Object?>[],
  };
  const failure = DomainError(
    code: 'PERMISSION_DENIED',
    message: 'Current scope denied.',
  );
  if (kind == 'count') {
    final gateway = count_fixture.Counts();
    final c = StockCountController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
      permissions: {'inventory.adjustments.post'},
    );
    c.form = Map.from(form);
    return Harness(
      open: (context) =>
          StockCountWorkspace(controller: c).action(context, 'cancel'),
      disconnect: () => c.setOnline(false),
      reauthorize: () async {
        c.setOnline(true);
        c.accessDenied = false;
        c.form = Map.from(form);
        c.emit();
      },
      deny: () => c.run(() async {
        throw failure;
      }),
      dispose: c.dispose,
      commands: gateway.commands,
      confirmLabel: 'Confirm',
    );
  }
  if (kind == 'disposition') {
    final gateway = disposition_fixture.Dispositions();
    final c = DispositionController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
      permissions: {'inventory.dispositions.post'},
    );
    c.form = Map.from(form);
    return Harness(
      open: (context) =>
          DispositionWorkspace(controller: c).action(context, 'cancel'),
      disconnect: () => c.setOnline(false),
      reauthorize: () async {
        c.setOnline(true);
        c.accessDenied = false;
        c.form = Map.from(form);
        c.emit();
      },
      deny: () => c.run(() async {
        throw failure;
      }),
      dispose: c.dispose,
      commands: gateway.commands,
      confirmLabel: 'Confirm',
    );
  }
  if (kind == 'landed') {
    final gateway = landed_fixture.Landed()..uncertain = false;
    final c = LandedExtensionController(
      scope: scope,
      gateway: gateway,
      drafts: LandedExtensionDraftStore(repository),
      online: true,
    );
    c.form = landedInput();
    await c.calculate();
    return Harness(
      open: (context) =>
          LandedExtensionWorkspace(controller: c).confirm(context),
      disconnect: () => c.setOnline(false),
      reauthorize: () async {
        c.setOnline(true);
        c.accessDenied = false;
        await c.calculate();
      },
      deny: () => c.run(() async {
        throw failure;
      }),
      dispose: c.dispose,
      commands: gateway.commands,
      confirmLabel: 'Confirm posting',
    );
  }
  final gateway = control_fixture.Gateway();
  final c = ControlReconciliationController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
    capabilities: {
      'finance.view',
      'finance.controls.reconcile',
      'finance.receipts.reverse',
    },
  );
  c.verified = true;
  Map<String, Object?> correction() => {
    'kind': 'AR',
    'allocation_id': '20000000-0000-0000-0000-000000000002',
    'posting_date': '2026-09-29',
    'reason': 'Correct original allocation',
  };
  c.correction = correction();
  return Harness(
    open: (context) =>
        ControlReconciliationWorkspace(controller: c).confirm(context),
    disconnect: () => c.setOnline(false),
    reauthorize: () async {
      c.setOnline(true);
      c.accessDenied = false;
      c.verified = true;
      c.correction = correction();
      c.emit();
    },
    deny: () => c.run(() async {
      throw failure;
    }),
    dispose: c.dispose,
    commands: gateway.reversals,
    confirmLabel: 'Reverse allocation',
  );
}

Future<void> open(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => h.open(context),
            child: const Text('Open reviewed action'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open reviewed action'));
  await tester.pumpAndSettle();
  final reason = find.byType(TextField);
  if (reason.evaluate().isNotEmpty) {
    await tester.enterText(reason, 'Reviewed original reason');
  }
  expect(find.text(h.confirmLabel), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final change in ['disconnect', 'reconnect', 'dispose']) {
    test(
      'landed obsolete initialization stops chained reads after $change',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        final gateway = PausedLandedReads();
        final c = LandedExtensionController(
          scope: scope,
          gateway: gateway,
          drafts: LandedExtensionDraftStore(
            EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
          ),
          online: true,
        );
        var disposed = false;
        final initialization = c.initialize();
        try {
          await gateway.firstEntered.future;
          if (change == 'dispose') {
            c.dispose();
            disposed = true;
          } else {
            c.setOnline(false);
            if (change == 'reconnect') c.setOnline(true);
          }
          gateway.firstReply.complete();
          await initialization;
          expect(gateway.resources, ['receipts']);
          expect(c.options, isEmpty);
          expect(c.preview, isNull);
        } finally {
          if (!gateway.firstReply.isCompleted) gateway.firstReply.complete();
          await initialization;
          if (!disposed) c.dispose();
          await db.close();
        }
      },
    );
  }
  for (final kind in ['count', 'disposition', 'landed', 'control']) {
    for (final change in ['disconnect', 'reconnect', 'denial', 'dispose']) {
      testWidgets('$kind root confirmation rejects $change without dispatch', (
        tester,
      ) async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        final h = await make(kind, db);
        try {
          await open(tester, h);
          if (change == 'denial') {
            await h.deny();
          } else if (change == 'dispose') {
            h.close();
          } else {
            h.disconnect();
          }
          await tester.pumpAndSettle();
          if (change == 'reconnect') {
            await h.reauthorize();
            await tester.pumpAndSettle();
          }
          expect(find.text('Reference access changed'), findsOneWidget);
          expect(find.text(h.confirmLabel), findsNothing);
          if (kind == 'landed') {
            expect(find.textContaining('6004799503160.082304'), findsNothing);
          }
          expect(h.commands, isEmpty);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          h.close();
          await db.close();
        }
      });
    }
    testWidgets('$kind fresh permitted confirmation dispatches once', (
      tester,
    ) async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final h = await make(kind, db);
      try {
        await open(tester, h);
        await tester.tap(find.text(h.confirmLabel));
        await tester.pumpAndSettle();
        expect(h.commands, hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        h.close();
        await db.close();
      }
    });
  }
}
