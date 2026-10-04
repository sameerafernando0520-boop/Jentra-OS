import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/negative_stock/negative_stock_policy_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as q;

class PolicyFake implements NegativeStockPolicyRepository {
  NegativeStockPolicy policy = NegativeStockPolicy(
    tenantId: 'tenant',
    legalEntityId: 'entity',
    version: BigInt.zero,
    active: false,
  );
  Future<NegativeStockPolicy> Function()? onRead;
  Future<CommandResult<NegativeStockPolicy>> Function(
    CommandEnvelope<Map<String, Object?>>,
  )?
  onConfigure;
  final commands = <Map<String, Object?>>[], cursors = <BigInt?>[];
  Future<NegativeStockEvidencePage> Function(
    NegativeStockEvidenceKind,
    BigInt?,
  )?
  onEvidence;
  @override
  Future<NegativeStockPolicy> readPolicy(TenantContext scope) async =>
      onRead == null ? policy : onRead!();
  @override
  Future<NegativeStockEvidencePage> evidence(
    TenantContext scope,
    NegativeStockEvidenceKind kind, {
    BigInt? after,
  }) async {
    cursors.add(after);
    return onEvidence == null
        ? NegativeStockEvidencePage(items: [])
        : onEvidence!(kind, after);
  }

  @override
  Future<CommandResult<NegativeStockPolicy>> configure(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command.toJson((x) => x));
    if (onConfigure != null) return onConfigure!(command);
    policy = NegativeStockPolicy(
      tenantId: 'tenant',
      legalEntityId: 'entity',
      version: BigInt.from(command.expectedEntityVersion!) + BigInt.one,
      active: command.payload['active']! as bool,
      id: 'policy',
      reason: command.payload['reason']! as String,
    );
    return CommandResult.success(requestId: 'request', entity: policy);
  }
}

class BlockingKeys implements SecretKeyStore {
  final inner = q.MemoryKeys();
  Completer<void>? pause, entered;
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('synthetic secure storage failure');
    entered?.complete();
    if (pause != null) await pause!.future;
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => inner.write(key, value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late QuotationDraftStore store;
  late PolicyFake gateway;
  late NegativeStockPolicyController c;
  late BlockingKeys keys;
  setUp(() {
    db = JentraLocalDatabase(
      NativeDatabase.memory(
        setup: (native) {
          native.createFunction(
            functionName: 'policy_ack_epoch_loss',
            directOnly: false,
            function: (_) {
              c.setOnline(false);
              c.setOnline(true);
              return 0;
            },
          );
        },
      ),
    );
    keys = BlockingKeys();
    store = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
    );
    gateway = PolicyFake();
    c = NegativeStockPolicyController(
      scope: q.scope,
      gateway: gateway,
      drafts: store,
      online: true,
      canViewCost: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test('refresh waits for queued encryption and preserves dirty original inputs and version', () async {
    await c.initialize();
    keys.pause = Completer<void>();
    keys.entered = Completer<void>();
    final write = c.update({
      'active': true,
      'reason': 'typed during first encryption',
    });
    await keys.entered!.future;
    var reads = 0;
    gateway.onRead = () async {
      reads++;
      return NegativeStockPolicy(
        tenantId: 'tenant',
        legalEntityId: 'entity',
        version: BigInt.from(2),
        active: false,
      );
    };
    final refresh = c.initialize();
    expect(reads, 0);
    keys.pause!.complete();
    await write;
    await refresh;
    expect(reads, 1);
    expect(c.policy!.version, BigInt.from(2));
    expect(c.form['reason'], 'typed during first encryption');
    expect(c.local!.expectedVersion, 0);
    await c.update({'active': true, 'reason': 'edited after refresh'});
    expect(c.local!.expectedVersion, 0);
  });
  test('failed encrypted save and current inputs survive policy refresh until explicit edit retry', () async {
    await c.initialize();
    keys.fail = true;
    await c.update({'active': true, 'reason': 'unsaved exact reason'});
    final savedError = c.error;
    expect(savedError, contains('could not be saved securely'));
    gateway.policy = NegativeStockPolicy(
      tenantId: 'tenant',
      legalEntityId: 'entity',
      version: BigInt.one,
      active: false,
    );
    await c.initialize();
    expect(c.form['reason'], 'unsaved exact reason');
    expect(c.error, savedError);
    await c.configure();
    expect(gateway.commands, isEmpty);
    keys.fail = false;
    await c.update(Map.from(c.form));
    expect(c.error, isNull);
    expect(c.local!.expectedVersion, 0);
    expect(c.local!.form['reason'], 'unsaved exact reason');
  });
  test(
    'recovered version one cannot be silently rebased to current version two',
    () async {
      await store.save(q.scope, NegativeStockPolicyController.slot, {
        'active': true,
        'reason': 'original version one',
      }, expectedVersion: 1);
      gateway.policy = NegativeStockPolicy(
        tenantId: 'tenant',
        legalEntityId: 'entity',
        version: BigInt.from(2),
        active: false,
      );
      await c.initialize();
      expect(c.local!.expectedVersion, 1);
      expect(c.policy!.version, BigInt.from(2));
      gateway.onConfigure = (command) async {
        expect(command.expectedEntityVersion, 1);
        expect(command.payload['reason'], 'original version one');
        return CommandResult.failure(
          requestId: 'conflict',
          error: const DomainError(
            code: 'VERSION_CONFLICT',
            message: 'Original policy version changed.',
          ),
        );
      };
      await c.configure();
      expect(gateway.commands, hasLength(1));
      expect(c.local!.expectedVersion, 1);
      expect(c.local!.pending, isNull);
      expect(c.local!.errorCode, 'VERSION_CONFLICT');
      expect(c.form['reason'], 'original version one');
      await c.configure();
      expect(gateway.commands, hasLength(1));
    },
  );
  test(
    'connection loss during first encryption cannot authorize later configure',
    () async {
      await c.initialize();
      keys.pause = Completer<void>();
      keys.entered = Completer<void>();
      final write = c.update({'active': true, 'reason': 'sealed original'});
      await keys.entered!.future;
      final command = c.configure();
      c.setOnline(false);
      c.setOnline(true);
      keys.pause!.complete();
      await write;
      await command;
      expect(gateway.commands, isEmpty);
      expect(
        (await store.load(
          q.scope,
          NegativeStockPolicyController.slot,
        ))!.form['reason'],
        'sealed original',
      );
    },
  );
  test(
    'first configure is encrypted before transport and confirmed complete',
    () async {
      await c.initialize();
      await c.update({'active': true, 'reason': 'Approved issue basis'});
      gateway.onConfigure = (command) async {
        final saved = await store.load(
          q.scope,
          NegativeStockPolicyController.slot,
        );
        expect(
          saved!.pending!.envelope.toJson((x) => x),
          command.toJson((x) => x),
        );
        expect(command.expectedEntityVersion, 0);
        expect(command.payload, {
          'active': true,
          'reason': 'Approved issue basis',
        });
        gateway.policy = NegativeStockPolicy(
          tenantId: 'tenant',
          legalEntityId: 'entity',
          version: BigInt.one,
          active: true,
        );
        return CommandResult.success(
          requestId: 'request',
          entity: NegativeStockPolicy(
            tenantId: 'tenant',
            legalEntityId: 'entity',
            version: BigInt.one,
            active: true,
          ),
        );
      };
      await c.configure();
      expect(gateway.commands, hasLength(1));
      expect(c.policy!.version, BigInt.one);
      expect(
        await store.load(q.scope, NegativeStockPolicyController.slot),
        isNull,
      );
    },
  );
  test('confirmed reply after transport loss completes original durable request without obsolete presentation', () async {
    await c.initialize();
    await c.update({'active': true, 'reason': 'original'});
    final entered = Completer<void>();
    final reply = Completer<CommandResult<NegativeStockPolicy>>();
    gateway.onConfigure = (_) {
      entered.complete();
      return reply.future;
    };
    final work = c.configure();
    await entered.future;
    c.setOnline(false);
    c.setOnline(true);
    reply.complete(
      CommandResult.success(
        requestId: 'confirmed',
        entity: NegativeStockPolicy(
          tenantId: 'tenant',
          legalEntityId: 'entity',
          version: BigInt.one,
          active: true,
        ),
      ),
    );
    await work;
    expect(
      await store.load(q.scope, NegativeStockPolicyController.slot),
      isNull,
    );
    expect(c.local, isNull);
    expect(c.form, isEmpty);
    expect(c.policy, isNull);
    await c.configure();
    expect(gateway.commands, hasLength(1));
  });
  test('connection change inside durable completion clears acknowledged inputs and leaves no repeat', () async {
    await c.initialize();
    await c.update({'active': true, 'reason': 'original'});
    await db.customStatement(
      "CREATE TRIGGER policy_ack_loss BEFORE DELETE ON encrypted_drafts BEGIN SELECT policy_ack_epoch_loss(); END",
    );
    await c.configure();
    expect(
      await store.load(q.scope, NegativeStockPolicyController.slot),
      isNull,
    );
    expect(c.local, isNull);
    expect(c.form, isEmpty);
    expect(c.policy, isNull);
    await c.configure();
    expect(gateway.commands, hasLength(1));
  });
  test(
    'historical exact replay reloads current policy before another change',
    () async {
      await c.initialize();
      await c.update({'active': true, 'reason': 'original'});
      gateway.onConfigure = (_) async {
        gateway.policy = NegativeStockPolicy(
          tenantId: 'tenant',
          legalEntityId: 'entity',
          version: BigInt.from(7),
          active: false,
        );
        return CommandResult.success(
          requestId: 'historic',
          entity: NegativeStockPolicy(
            tenantId: 'tenant',
            legalEntityId: 'entity',
            version: BigInt.one,
            active: true,
          ),
        );
      };
      await c.configure();
      expect(c.policy!.version, BigInt.from(7));
      expect(c.form['active'], false);
      expect(c.message, 'Policy version 1 recorded.');
    },
  );
  test('confirmed configure with failed refresh keeps current policy unavailable and sealed request complete', () async {
    await c.initialize();
    await c.update({'active': true, 'reason': 'original'});
    gateway.onConfigure = (_) async {
      gateway.onRead = () async => throw TimeoutException('refresh');
      return CommandResult.success(
        requestId: 'confirmed',
        entity: NegativeStockPolicy(
          tenantId: 'tenant',
          legalEntityId: 'entity',
          version: BigInt.one,
          active: true,
        ),
      );
    };
    await c.configure();
    expect(
      await store.load(q.scope, NegativeStockPolicyController.slot),
      isNull,
    );
    expect(c.policy, isNull);
    expect(c.error, contains('was recorded'));
    await c.configure();
    expect(gateway.commands, hasLength(1));
  });
  test(
    'uncertain configuration survives restart and retries exact bytes',
    () async {
      await c.initialize();
      await c.update({'active': true, 'reason': 'Exact original request'});
      gateway.onConfigure = (_) async => CommandResult.failure(
        requestId: 'unknown',
        error: const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'uncertain',
        ),
      );
      await c.configure();
      final original = jsonEncode(gateway.commands.single);
      expect(c.local!.pending, isNotNull);
      await c.update({'active': false, 'reason': 'must not replace'});
      c.dispose();
      c = NegativeStockPolicyController(
        scope: q.scope,
        gateway: gateway,
        drafts: store,
        online: true,
        canViewCost: true,
      );
      await c.initialize();
      expect(c.form['reason'], 'Exact original request');
      gateway.onConfigure = null;
      await c.configure(retry: true);
      expect(jsonEncode(gateway.commands.last), original);
      expect(gateway.commands, hasLength(2));
    },
  );
  test('confirmed validation leaves editable encrypted inputs', () async {
    await c.initialize();
    await c.update({'active': true, 'reason': 'retain'});
    gateway.onConfigure = (_) async => CommandResult.failure(
      requestId: 'reject',
      error: const DomainError(
        code: 'VALIDATION_ERROR',
        message: 'check reason',
      ),
    );
    await c.configure();
    expect(c.local!.pending, isNull);
    expect(c.form['reason'], 'retain');
    expect(c.error, 'check reason');
  });
  test(
    'current typed denial clears presentation but preserves durable input',
    () async {
      await c.initialize();
      await c.update({'active': true, 'reason': 'private approved reason'});
      gateway.onConfigure = (_) async => CommandResult.failure(
        requestId: 'denied',
        error: const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'access denied',
        ),
      );
      await c.configure();
      expect(c.accessDenied, isTrue);
      expect(c.form, isEmpty);
      expect(c.policy, isNull);
      expect(
        (await store.load(
          q.scope,
          NegativeStockPolicyController.slot,
        ))!.form['reason'],
        'private approved reason',
      );
    },
  );
  for (final action in ['dispose', 'reconnect', 'denial']) {
    test('late policy read cannot repaint after $action', () async {
      final pending = Completer<NegativeStockPolicy>();
      final entered = Completer<void>();
      gateway.onRead = () {
        entered.complete();
        return pending.future;
      };
      final work = c.initialize();
      await entered.future;
      if (action == 'dispose') {
        c.dispose();
      } else if (action == 'denial') {
        c.denyReadAccess();
      } else {
        c.setOnline(false);
        c.setOnline(true);
      }
      pending.complete(
        NegativeStockPolicy(
          tenantId: 'tenant',
          legalEntityId: 'entity',
          version: BigInt.one,
          active: true,
        ),
      );
      await work;
      expect(c.policy, isNull);
    });
  }
  test('late denial after reconnect cannot revoke replacement epoch', () async {
    final pending = Completer<NegativeStockPolicy>();
    final entered = Completer<void>();
    gateway.onRead = () {
      entered.complete();
      return pending.future;
    };
    final work = c.initialize();
    await entered.future;
    c.setOnline(false);
    c.setOnline(true);
    pending.completeError(
      const DomainError(code: 'PERMISSION_DENIED', message: 'obsolete'),
    );
    await work;
    expect(c.accessDenied, isFalse);
    expect(c.error, isNull);
  });
  test('invalid reason and overflow version create no command', () async {
    await c.initialize();
    c.form = {'active': true, 'reason': ''};
    await c.configure();
    expect(gateway.commands, isEmpty);
    c.policy = NegativeStockPolicy(
      tenantId: 'tenant',
      legalEntityId: 'entity',
      version: BigInt.parse('9223372036854775808'),
      active: true,
    );
    c.form = {'active': false, 'reason': 'disable'};
    await c.configure();
    expect(gateway.commands, isEmpty);
    expect(c.error, contains('version'));
  });
  test(
    'offline edit remains encrypted without an authoritative command',
    () async {
      await c.initialize();
      c.setOnline(false);
      await c.update({'active': true, 'reason': 'offline draft'});
      await c.configure();
      expect(gateway.commands, isEmpty);
      expect(
        (await store.load(
          q.scope,
          NegativeStockPolicyController.slot,
        ))!.form['reason'],
        'offline draft',
      );
    },
  );
  test('cost denial does not request private evidence', () async {
    c.dispose();
    c = NegativeStockPolicyController(
      scope: q.scope,
      gateway: gateway,
      drafts: store,
      online: true,
      canViewCost: false,
    );
    await c.initialize();
    await c.loadEvidence(NegativeStockEvidenceKind.deficits);
    expect(gateway.cursors, isEmpty);
  });
  test(
    'evidence pagination uses exact last cursor and explicit remaining pages',
    () async {
      await c.initialize();
      gateway.onEvidence = (_, after) async => NegativeStockEvidencePage(
        items: [],
        nextCursor: after == null ? BigInt.parse('9007199254740993') : null,
      );
      await c.loadEvidence(NegativeStockEvidenceKind.deficits);
      await c.loadEvidence(NegativeStockEvidenceKind.deficits, more: true);
      expect(gateway.cursors, [null, BigInt.parse('9007199254740993')]);
      expect(c.cursor, isNull);
    },
  );
  test('late evidence after reconnect is discarded', () async {
    await c.initialize();
    final pending = Completer<NegativeStockEvidencePage>();
    gateway.onEvidence = (_, _) => pending.future;
    final work = c.loadEvidence(NegativeStockEvidenceKind.covers);
    c.setOnline(false);
    c.setOnline(true);
    pending.complete(
      NegativeStockEvidencePage(items: [], nextCursor: BigInt.one),
    );
    await work;
    expect(c.cursor, isNull);
  });
  test(
    'local discard is offline, pending request cannot be discarded',
    () async {
      await c.initialize();
      await c.update({'active': true, 'reason': 'draft'});
      c.setOnline(false);
      await c.discard();
      expect(
        await store.load(q.scope, NegativeStockPolicyController.slot),
        isNull,
      );
      c.setOnline(true);
      await c.initialize();
      await c.update({'active': true, 'reason': 'uncertain'});
      gateway.onConfigure = (_) async => CommandResult.failure(
        requestId: 'unknown',
        error: const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'uncertain',
        ),
      );
      await c.configure();
      await c.discard();
      expect(
        (await store.load(
          q.scope,
          NegativeStockPolicyController.slot,
        ))!.pending,
        isNotNull,
      );
    },
  );
  for (final boundary in ['read', 'encryption', 'receipt']) {
    for (final change in [
      'current',
      'scope actor pulse',
      'scope branch pulse',
      'capability pulse',
      'retained loading',
      'retained error',
      'cost-view pulse',
    ]) {
      test('policy provider $boundary observes $change before continuation', () async {
        const originalCapabilities = {
          'inventory.stock.view',
          'inventory.stock.policy.manage',
          'inventory.cost.view',
        };
        TenantContext? liveScope = q.scope;
        AsyncValue<Set<String>> liveCapabilities = const AsyncData(
          originalCapabilities,
        );
        final encrypted = EncryptedDraftRepository(
          db,
          DraftCipher(keyStore: keys),
        );
        overrides() => [
          activeTenantContextProvider.overrideWithValue(liveScope),
          businessCapabilitiesProvider.overrideWithValue(liveCapabilities),
          connectivityStateProvider.overrideWithValue(
            const AsyncData(ConnectivityState.online),
          ),
          encryptedDraftRepositoryProvider.overrideWithValue(encrypted),
          negativeStockPolicyRepositoryProvider.overrideWithValue(gateway),
        ];
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: overrides(),
        );
        final scopeSubscription = container.listen(
          activeTenantContextProvider,
          (_, _) {},
        );
        final capabilitySubscription = container.listen(
          businessCapabilitiesProvider,
          (_, _) {},
        );
        final workspaceSubscription = container.listen(
          negativeStockPolicyControllerProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(() {
          workspaceSubscription.close();
          capabilitySubscription.close();
          scopeSubscription.close();
          container.dispose();
        });
        final original = container.read(negativeStockPolicyControllerProvider)!;
        final initialized = Completer<void>();
        void observeInitialized() {
          if (!original.busy &&
              original.policy != null &&
              !initialized.isCompleted) {
            initialized.complete();
          }
        }

        original.addListener(observeInitialized);
        observeInitialized();
        await initialized.future.timeout(const Duration(seconds: 5));
        original.removeListener(observeInitialized);
        final epoch = original.readAccessEpoch;
        final order = <String>[];
        final entered = Completer<void>();
        final readReply = Completer<NegativeStockPolicy>();
        final commandReply = Completer<CommandResult<NegativeStockPolicy>>();
        late Future<void> work;
        Future<void>? inputWrite;
        if (boundary == 'read') {
          gateway.onRead = () {
            if (!entered.isCompleted) entered.complete();
            return readReply.future;
          };
          work = original.initialize();
        } else if (boundary == 'encryption') {
          // Initialization has not encrypted anything: the first edit really
          // reaches an unresolved key, rather than a memoized warm cipher.
          keys.pause = Completer<void>();
          keys.entered = entered;
          inputWrite = original.update({
            'active': true,
            'reason': 'original encrypted provider input',
          });
          work = original.configure();
        } else {
          await original.update({
            'active': true,
            'reason': 'original encrypted provider input',
          });
          gateway.onConfigure = (_) {
            entered.complete();
            return commandReply.future;
          };
          work = original.configure();
        }
        await entered.future.timeout(const Duration(seconds: 5));
        order.add('continuation paused');
        void publish() {
          container.updateOverrides(overrides());
          // Read the observed source to publish its actual notification before
          // restoration; do not rebuild the policy provider to hide a gap.
          container.read(activeTenantContextProvider);
          container.read(businessCapabilitiesProvider);
        }

        if (change != 'current') {
          if (change == 'scope actor pulse') {
            liveScope = q.scope.copyWith(actorId: 'replacement-actor');
          } else if (change == 'scope branch pulse') {
            liveScope = q.scope.copyWith(branchId: 'replacement-branch');
          } else if (change == 'capability pulse') {
            liveCapabilities = const AsyncData({'inventory.stock.view'});
          } else if (change == 'cost-view pulse') {
            liveCapabilities = const AsyncData({
              'inventory.stock.view',
              'inventory.stock.policy.manage',
            });
          } else if (change == 'retained loading') {
            const pending = AsyncLoading<Set<String>>();
            const previous = AsyncData(originalCapabilities);
            // ignore: invalid_use_of_internal_member
            liveCapabilities = pending.copyWithPrevious(previous);
          } else {
            final failed = AsyncError<Set<String>>(
              StateError('synthetic capability uncertainty'),
              StackTrace.current,
            );
            const previous = AsyncData(originalCapabilities);
            // ignore: invalid_use_of_internal_member
            liveCapabilities = failed.copyWithPrevious(previous);
          }
          publish();
          order.add('loss published');
          expect(original.currentRead(epoch), isFalse);
          liveScope = q.scope;
          liveCapabilities = const AsyncData(originalCapabilities);
          publish();
          order.add('restoration published');
          expect(original.currentRead(epoch), isFalse);
        } else {
          expect(original.currentRead(epoch), isTrue);
        }
        order.add('continuation released');
        if (boundary == 'read') {
          readReply.complete(gateway.policy);
        } else if (boundary == 'encryption') {
          keys.pause!.complete();
          await inputWrite;
        } else {
          gateway.policy = NegativeStockPolicy(
            tenantId: 'tenant',
            legalEntityId: 'entity',
            version: BigInt.one,
            active: true,
          );
          commandReply.complete(
            CommandResult.success(
              requestId: 'confirmed-original',
              entity: gateway.policy,
            ),
          );
        }
        await work;
        expect(order, [
          'continuation paused',
          if (change != 'current') ...[
            'loss published',
            'restoration published',
          ],
          'continuation released',
        ]);
        if (boundary == 'receipt') {
          expect(gateway.commands, hasLength(1));
          // A matching confirmed receipt completes its original durable request
          // even when presentation authority was lost after transmission.
          expect(
            await original.drafts.load(
              q.scope,
              NegativeStockPolicyController.slot,
            ),
            isNull,
          );
        } else if (boundary == 'encryption') {
          expect(
            gateway.commands,
            change == 'current' ? hasLength(1) : isEmpty,
          );
          if (change != 'current') {
            final saved = await original.drafts.load(
              q.scope,
              NegativeStockPolicyController.slot,
            );
            expect(saved!.form['reason'], 'original encrypted provider input');
            expect(saved.pending, isNull);
          }
        } else {
          expect(gateway.commands, isEmpty);
        }
        if (change == 'current') {
          expect(original.policy, isNotNull);
        } else {
          expect(original.policy, isNull);
          expect(original.form, isEmpty);
        }
      });
    }
  }
}
