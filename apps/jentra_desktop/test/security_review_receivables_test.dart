import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';

import 'receivables_controller_test.dart' as f;
import 'security_review_sealing_test.dart' show PausedKeys;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final change in ['disconnect', 'reconnect', 'dispose']) {
    test(
      'AR sealing across $change retains exact original posting request',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory()),
            keys = PausedKeys();
        final drafts = ReceivableDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
        );
        final repo = f.FakeReceivables()
          ..doc = ReceivableDocument(f.snapshot(status: 'approved'));
        ReceivablesController make() => ReceivablesController(
          scope: f.scope,
          capabilities: f.permissions,
          repository: repo,
          drafts: drafts,
          online: true,
        );
        final c = make();
        var disposed = false;
        try {
          await c.open(repo.doc);
          final slot = c.slot!;
          keys.armed = true;
          final sending = c.action('post');
          await keys.entered.future.timeout(const Duration(seconds: 5));
          if (change == 'dispose') {
            c.dispose();
            disposed = true;
          } else {
            c.setOnline(false);
            if (change == 'reconnect') c.setOnline(true);
          }
          keys.release.complete();
          await sending;
          expect(repo.commands, isEmpty);
          final saved = await drafts.load(f.scope, slot);
          expect(saved?.pending, isTrue);
          final original = saved!.envelope.toJson((x) => x);
          if (!disposed) {
            c.dispose();
            disposed = true;
          }
          final fresh = make();
          try {
            await fresh.recover(slot);
            await fresh.retry();
            expect(repo.commands, hasLength(1));
            expect(repo.commands.single.toJson((x) => x), original);
            expect(await drafts.load(f.scope, slot), isNull);
          } finally {
            fresh.dispose();
          }
        } finally {
          if (!keys.release.isCompleted) keys.release.complete();
          if (!disposed) c.dispose();
          await db.close();
        }
      },
    );
  }
  for (final code in [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
  ]) {
    test(
      'late AR $code records original failure without revoking replacement epoch',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        final drafts = ReceivableDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: f.MemoryKeys())),
        );
        final repo = f.FakeReceivables()
          ..doc = ReceivableDocument(f.snapshot(status: 'approved'));
        final c = ReceivablesController(
          scope: f.scope,
          capabilities: f.permissions,
          repository: repo,
          drafts: drafts,
          online: true,
        );
        try {
          await c.open(repo.doc);
          repo.gate = Completer<void>();
          final sending = c.action('post');
          for (var i = 0; i < 1000 && repo.commands.isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          expect(repo.commands, hasLength(1));
          c.setOnline(false);
          c.setOnline(true);
          final current = c.readAccessEpoch;
          repo.failure = ReceivableFailure(
            code,
            'Original access was removed.',
            definite: true,
          );
          repo.gate!.complete();
          await sending;
          expect(c.readAccessEpoch, current);
          expect(c.error, isNull);
          expect(c.document, isNull);
        } finally {
          c.dispose();
          await db.close();
        }
      },
    );
  }
}
