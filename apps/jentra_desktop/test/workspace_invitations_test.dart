import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/tenant/workspace_admin_controller.dart';
import 'package:jentra_desktop/src/features/tenant/workspace_invitations_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_workspace_admin.dart';
import 'package:jentra_platform/jentra_platform.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const group = '10000000-0000-0000-0000-000000000002';
Map<String, Object?> invitation(String name, [int n = 1]) => {
  'id': '20000000-0000-0000-0000-${n.toString().padLeft(12, '0')}',
  'tenant_id': group,
  'tenant_name': name,
  'role_name': 'Sales reader',
  'legal_entity_name': 'Pilot company',
  'branch_name': 'Main branch',
};

final class _Invitations implements WorkspaceAdminRepository {
  bool empty = false, many = false;
  Completer<Map<String, Object?>>? delayed;
  int calls = 0;
  final acceptanceStarted = Completer<void>();
  final acceptedKeys = <String>[];
  Completer<Map<String, Object?>>? delayedAcceptance;
  bool failAcceptance = false;
  @override
  Future<Map<String, Object?>> myInvitations({String? after}) async {
    calls++;
    final wait = delayed;
    if (wait != null) {
      delayed = null;
      return wait.future;
    }
    if (empty) return {'items': [], 'next_cursor': null};
    if (after != null) {
      return {
        'items': [invitation('Private second-page group', 99)],
        'next_cursor': null,
      };
    }
    return {
      'items': many
          ? [for (var n = 1; n <= 50; n++) invitation('First-page group', n)]
          : [invitation('Private invited group')],
      'next_cursor': many ? invitation('', 50)['id'] : null,
    };
  }

  @override
  Future<Map<String, Object?>> acceptInvitation(String id, String key) async {
    acceptedKeys.add(key);
    if (!acceptanceStarted.isCompleted) acceptanceStarted.complete();
    if (delayedAcceptance != null) return delayedAcceptance!.future;
    if (failAcceptance) throw StateError('Unknown result');
    return {
      'entity': {'tenant_id': group},
    };
  }

  @override
  Future<WorkspaceAdminPage> list(
    TenantContext s,
    WorkspaceAdminResource r, {
    String? after,
    int limit = 50,
  }) async => throw UnimplementedError();
  @override
  Future<Map<String, Object?>> command(
    WorkspaceAdminAction a,
    CommandEnvelope<Map<String, Object?>> c,
  ) async => throw UnimplementedError();
}

final class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late StreamController<String?> actors;
  late StreamController<int> sessions;
  late StreamController<ConnectivityState> connections;
  setUp(() {
    actors = StreamController.broadcast();
    sessions = StreamController.broadcast();
    connections = StreamController.broadcast();
  });
  tearDown(() async {
    await actors.close();
    await sessions.close();
    await connections.close();
  });
  Future<void> show(
    WidgetTester tester,
    _Invitations g, {
    EncryptedDraftRepository? drafts,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceAdminGatewayProvider.overrideWithValue(g),
          authenticatedActorProvider.overrideWith((ref) => actors.stream),
          authSessionRevisionProvider.overrideWith((ref) => sessions.stream),
          connectivityStateProvider.overrideWith((ref) => connections.stream),
          if (drafts != null)
            encryptedDraftRepositoryProvider.overrideWithValue(drafts),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WorkspaceInvitationsScreen()),
        ),
      ),
    );
    actors.add(actor);
    sessions.add(0);
    connections.add(ConnectivityState.online);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('CA-10 going offline hides private invitation data', (
    tester,
  ) async {
    final g = _Invitations();
    await show(tester, g);
    await tester.pumpAndSettle();
    expect(find.text('Private invited group'), findsOneWidget);
    connections.add(ConnectivityState.offline);
    await tester.pumpAndSettle();
    expect(find.text('Private invited group'), findsNothing);
    expect(
      find.text('Reconnect to view your company invitations.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'CA-10 actor switch ignores an earlier private invitation response',
    (tester) async {
      final wait = Completer<Map<String, Object?>>(),
          g = _Invitations()..delayed = wait;
      await show(tester, g);
      await tester.pump();
      expect(g.calls, 1);
      g.empty = true;
      actors.add(group);
      await tester.pumpAndSettle();
      wait.complete({
        'items': [invitation('Late private group')],
        'next_cursor': null,
      });
      await tester.pumpAndSettle();
      expect(find.text('Late private group'), findsNothing);
      expect(find.text('No pending invitations on this page.'), findsOneWidget);
    },
  );
  testWidgets('CA-10 session revision clears the private second-page cache', (
    tester,
  ) async {
    final g = _Invitations()..many = true;
    await show(tester, g);
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(WorkspaceInvitationsScreen));
    await state.next(invitation('', 50)['id']);
    await tester.pumpAndSettle();
    expect(find.text('Private second-page group'), findsOneWidget);
    g.empty = true;
    sessions.add(1);
    await tester.pumpAndSettle();
    expect(find.text('Private second-page group'), findsNothing);
    expect(find.text('No pending invitations on this page.'), findsOneWidget);
  });
  testWidgets(
    'CA-A7 invitation retry reuses its sealed key after an unknown result',
    (tester) async {
      final recoveryDatabase = JentraLocalDatabase(NativeDatabase.memory());
      final recovery = EncryptedDraftRepository(
        recoveryDatabase,
        DraftCipher(keyStore: _Keys()),
      );
      final g = _Invitations()..failAcceptance = true;
      try {
        await show(tester, g, drafts: recovery);
        await tester.pumpAndSettle();
        final dynamic state = tester.state(
          find.byType(WorkspaceInvitationsScreen),
        );
        await tester.runAsync(
          () async => await state.accept(invitation('Private invited group')),
        );
        await tester.pumpAndSettle();
        final key = 'workspace-invitation:$actor:${invitation('')['id']}';
        final pending = await tester.runAsync(() => recovery.find(key));
        expect(pending, isNotNull);
        expect(pending!.payload['idempotency_key'], g.acceptedKeys.single);
        g.failAcceptance = false;
        await tester.runAsync(
          () async => await state.accept(invitation('Private invited group')),
        );
        await tester.pumpAndSettle();
        expect(g.acceptedKeys, hasLength(2));
        expect(g.acceptedKeys.first, g.acceptedKeys.last);
        expect(await tester.runAsync(() => recovery.find(key)), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await recoveryDatabase.close();
      }
    },
  );
  testWidgets(
    'CA-10 an auth revision during acceptance retains recovery and ignores late success',
    (tester) async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final recovery = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: _Keys()),
      );
      late final Completer<Map<String, Object?>> wait;
      late final _Invitations g;
      // Transport gates live in the same real async zone as native SQLite.
      // A fake-clock completer cannot progress while runAsync awaits it.
      await tester.runAsync(() async {
        wait = Completer<Map<String, Object?>>();
        g = _Invitations()..delayedAcceptance = wait;
      });
      try {
        await show(tester, g, drafts: recovery);
        await tester.pumpAndSettle();
        final dynamic state = tester.state(
          find.byType(WorkspaceInvitationsScreen),
        );
        late Future<void> accepting;
        await tester.runAsync(() async {
          accepting =
              state.accept(invitation('Private invited group')) as Future<void>;
          await Future.any([
            g.acceptanceStarted.future,
            accepting.then(
              (_) => throw StateError(
                'Acceptance ended before transport: ${state.error}',
              ),
            ),
          ]).timeout(const Duration(seconds: 10));
        });
        sessions.add(1);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          wait.complete({
            'entity': {'tenant_id': group},
          });
          await accepting;
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('Invitation accepted.'), findsNothing);
        final key = 'workspace-invitation:$actor:${invitation('')['id']}';
        expect(await tester.runAsync(() => recovery.find(key)), isNotNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await db.close();
      }
    },
  );
}
