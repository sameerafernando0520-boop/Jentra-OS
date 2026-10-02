import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_desktop/src/features/operations/operational_controller.dart';
import 'package:jentra_desktop/src/features/operations/operational_screen.dart';

import 'operational_workspace_test.dart' show OperationalFake;

class FileAccessGateway extends OperationalFake {
  Completer<String>? linkReply;
  Object? linkFailure;
  int linkReads = 0;
  @override
  Future<String> signedAttachmentUrl(
    TenantContext scope,
    String kind,
    String sourceId,
    Map<String, Object?> attachment,
  ) async {
    linkReads++;
    if (linkReply != null) return linkReply!.future;
    if (linkFailure != null) throw linkFailure!;
    return 'https://synthetic.invalid/private-link?token=PRIVATE_FILE_TOKEN';
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  const target = (
    tenantId: 't',
    entityId: 'e',
    branchId: 'b',
    kind: 'supplier_bill',
    id: '00000000-0000-4000-8000-000000000001',
  );
  late FileAccessGateway gateway;
  late OperationalController controller;
  bool disposed = false;
  setUp(() {
    gateway = FileAccessGateway();
    controller = OperationalController(
      scope: scope,
      gateway: gateway,
      target: target,
      online: true,
    );
    disposed = false;
  });
  tearDown(() {
    if (!disposed) controller.dispose();
  });

  Future<void> display(
    WidgetTester tester, {
    OperationalController? value,
  }) async {
    final c = value ?? controller;
    await c.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperationalWorkspace(controller: c, canManageFiles: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Private file actions'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }

  Future<void> action(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Private file actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Finder privateLink() => find.textContaining('PRIVATE_FILE_TOKEN');

  testWidgets('private link disappears immediately after disconnect', (
    tester,
  ) async {
    await display(tester);
    await action(tester, 'Get private link');
    expect(privateLink(), findsOneWidget);
    controller.setOnline(false);
    await tester.pumpAndSettle();
    expect(privateLink(), findsNothing);
    expect(find.text('Reference access changed'), findsOneWidget);
    controller.setOnline(true);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(privateLink(), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'disconnect and fresh reconnect cannot accept an older link reply',
    (tester) async {
      await display(tester);
      gateway.linkReply = Completer<String>();
      await action(tester, 'Get private link');
      controller.setOnline(false);
      controller.setOnline(true);
      await controller.refresh();
      gateway.linkReply!.complete(
        'https://synthetic.invalid/PRIVATE_FILE_TOKEN',
      );
      await tester.pumpAndSettle();
      expect(privateLink(), findsNothing);
      expect(find.text('Private attachment link'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('document refresh invalidates an already opened private link', (
    tester,
  ) async {
    await display(tester);
    await action(tester, 'Get private link');
    expect(privateLink(), findsOneWidget);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(privateLink(), findsNothing);
    expect(find.text('Reference access changed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'disposed source cannot leave a private link in the root dialog',
    (tester) async {
      await display(tester);
      await action(tester, 'Get private link');
      expect(privateLink(), findsOneWidget);
      controller.dispose();
      disposed = true;
      await tester.pumpAndSettle();
      expect(privateLink(), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('replaced workspace rejects the previous source link reply', (
    tester,
  ) async {
    await display(tester);
    gateway.linkReply = Completer<String>();
    await action(tester, 'Get private link');
    final replacement = OperationalController(
      scope: scope,
      gateway: FileAccessGateway(),
      target: (
        tenantId: 't',
        entityId: 'e',
        branchId: 'b',
        kind: 'supplier_bill',
        id: 'replacement',
      ),
      online: true,
    );
    try {
      await display(tester, value: replacement);
      gateway.linkReply!.complete(
        'https://synthetic.invalid/PRIVATE_FILE_TOKEN',
      );
      await tester.pumpAndSettle();
      expect(privateLink(), findsNothing);
      expect(find.text('Private attachment link'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      replacement.dispose();
    }
  });

  testWidgets('file rejection dialog cannot revive after disconnect', (
    tester,
  ) async {
    await display(tester);
    await action(tester, 'Reject file with reason');
    await tester.enterText(find.byType(TextField), 'PRIVATE_LOCAL_REASON');
    controller.setOnline(false);
    await tester.pumpAndSettle();
    expect(find.text('Reject private file'), findsNothing);
    expect(find.text('PRIVATE_LOCAL_REASON'), findsNothing);
    expect(find.text('Reference access changed'), findsOneWidget);
    controller.setOnline(true);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Reject file'), findsNothing);
    expect(gateway.rejections, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final code in [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
  ]) {
    testWidgets('current $code file access clears verified source evidence', (
      tester,
    ) async {
      await display(tester);
      gateway.linkFailure = DomainError(
        code: code,
        message: 'PRIVATE_SERVER_DIAGNOSTIC',
      );
      await action(tester, 'Get private link');
      expect(controller.verified, isFalse);
      expect(controller.evidence, isEmpty);
      expect(privateLink(), findsNothing);
      expect(find.textContaining('PRIVATE_SERVER_DIAGNOSTIC'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
