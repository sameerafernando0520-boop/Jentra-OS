import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/receivables/receivable_picker.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';

import 'receivables_controller_test.dart' as ar;

void main() {
  for (final change in ['reconnect', 'denial', 'dispose', 'unchanged']) {
    testWidgets('AR root dialog result binds original access: $change', (
      tester,
    ) async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final controller = ReceivablesController(
        scope: ar.scope,
        capabilities: ar.permissions,
        repository: ar.FakeReceivables(),
        drafts: ReceivableDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: ar.MemoryKeys())),
        ),
        online: true,
      );
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        if (controller.active) controller.dispose();
        await db.close();
      });
      late BuildContext origin;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (context) {
              origin = context;
              return const Scaffold(body: Text('Receivables origin'));
            },
          ),
        ),
      );
      final result = showScopedReceivableDialog<String>(
        context: origin,
        controller: controller,
        builder: (_) =>
            const AlertDialog(content: Text('Original document confirmation')),
      );
      await tester.pumpAndSettle();
      // A synchronous access notification after pop precedes the caller's await.
      navigator.currentState!.pop('original-document-choice');
      switch (change) {
        case 'reconnect':
          controller.setOnline(false);
          controller.setOnline(true);
        case 'denial':
          controller.invalidateReadEvidence();
        case 'dispose':
          controller.dispose();
        case 'unchanged':
          break;
      }
      await tester.pumpAndSettle();
      expect(
        await result,
        change == 'unchanged' ? 'original-document-choice' : isNull,
      );
    });
  }
}
