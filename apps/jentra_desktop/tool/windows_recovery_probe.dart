// Native verification entry point only. Build explicitly with --target; the
// normal application never imports this file or uses its synthetic gateway.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';

const _scope = TenantContext(
  tenantId: '00000000-0000-4000-8000-000000000011',
  actorId: '00000000-0000-4000-8000-000000000012',
  legalEntityId: '00000000-0000-4000-8000-000000000013',
  branchId: '00000000-0000-4000-8000-000000000014',
);
const _documentId = '00000000-0000-4000-8000-000000000015';
const _postSlot = 'sales_invoice:$_documentId';
const _exact = '90071992547409.123456';
const _marker = 'SYNTHETIC-NATIVE-RECOVERY-CONTENT';
const _permissions = {
  'sales.invoices.view',
  'sales.invoices.manage',
  'sales.invoices.post',
};

void _check(bool passed, String message) {
  if (!passed) throw StateError(message);
}

// Uses the production OS adapter with a unique test-only key name. It never
// reads, replaces, or deletes the application's ordinary draft credential.
final class _ProbeKeys implements SecretKeyStore {
  _ProbeKeys(this.runId);
  final String runId;
  final _native = WindowsCredentialKeyStore();
  int writes = 0;
  String name(String key) => 'jentra-recovery-probe.$runId.$key';
  @override
  Future<String?> read(String key) => _native.read(name(key));
  @override
  Future<void> write(String key, String value) async {
    writes++;
    await _native.write(name(key), value);
  }

  Future<void> remove() => const FlutterSecureStorage().delete(
    key: name('jentra.local-draft-key.v1'),
  );
}

Map<String, Object?> _document({bool posted = false}) => {
  'id': _documentId,
  'document_type': 'sales_invoice',
  'document_number': 'SYNTHETIC-INV-1',
  'customer_id': '00000000-0000-4000-8000-000000000016',
  'document_date': '2026-09-10',
  'currency_code': 'LKR',
  'grand_total': '118000.000000',
  'base_total': '118000.000000',
  'tax_total': '18000.000000',
  'version': posted ? 4 : 3,
  'status': posted ? 'posted' : 'approved',
  'lines': <Object?>[],
};

// A file-backed simulated server records one commit, loses the first response,
// and accepts only a byte-identical command on retry. No network is used. This
// verifies the actual controller/storage path, not live financial posting.
final class _LostResponseGateway implements ReceivablesRepository {
  _LostResponseGateway(this.directory, {this.loseResponse = false});
  final Directory directory;
  final bool loseResponse;
  int calls = 0;
  File get commit => File('${directory.path}/simulated-commit.json');
  @override
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> envelope,
  ) async {
    calls++;
    final encoded = jsonEncode({
      'rpc': rpc,
      'envelope': envelope.toJson((p) => p),
    });
    if (loseResponse) {
      _check(
        !await commit.exists(),
        'A synthetic command was committed twice.',
      );
      await commit.writeAsString(encoded, flush: true);
      throw TimeoutException('Synthetic response dropped after commit');
    }
    _check(
      await commit.readAsString() == encoded,
      'Retry changed saved command.',
    );
    return {
      'request_id': 'synthetic-request-1',
      'command_id': envelope.commandId,
      'entity': _document(posted: true),
    };
  }

  @override
  Future<ReceivableDocument> find(
    TenantContext scope,
    ReceivableKind kind,
    String id,
  ) async => ReceivableDocument(_document());
  @override
  Future<CursorPage<ReceivableDocument>> page(
    TenantContext scope,
    ReceivableKind kind, {
    String? cursor,
    String? status,
  }) async => CursorPage(items: [], limit: 50);
  @override
  Future<CursorPage<Map<String, Object?>>> references(
    TenantContext scope,
    String resource, {
    String? cursor,
    String? customerId,
    String? sourceId,
  }) async => CursorPage(items: [], limit: 50);
  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope,
    String customerId,
    String currency,
    String asOf,
    List<int> buckets,
  ) => throw UnsupportedError(
    'The native recovery probe does not read reports.',
  );
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 3 || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(args[2])) {
    exit(64);
  }
  final phase = args[0], directory = Directory(args[1]), runId = args[2];
  if (!directory.isAbsolute ||
      !directory.path.endsWith('native-recovery-$runId')) {
    exit(64);
  }
  await directory.create(recursive: true);
  final result = File('${directory.path}/$phase.json');
  final keys = _ProbeKeys(runId);
  JentraLocalDatabase? database;
  ReceivablesController? controller;
  try {
    if (phase == 'cleanup') {
      await keys.remove();
      _check(
        await keys.read('jentra.local-draft-key.v1') == null,
        'Test key remains.',
      );
    } else {
      database = JentraLocalDatabase(
        NativeDatabase.createInBackground(
          File('${directory.path}/drafts.sqlite'),
        ),
      );
      final repository = EncryptedDraftRepository(
        database,
        DraftCipher(keyStore: keys),
      );
      final drafts = ReceivableDraftStore(repository);
      final gateway = _LostResponseGateway(
        directory,
        loseResponse: phase == 'interrupt',
      );
      controller = ReceivablesController(
        scope: _scope,
        capabilities: _permissions,
        repository: gateway,
        drafts: drafts,
        online: false,
      );
      final manifest = File('${directory.path}/synthetic-manifest.json');
      if (phase == 'seed') {
        _check(
          await keys.read('jentra.local-draft-key.v1') == null,
          'Probe key already exists.',
        );
        await Future.wait([
          for (var i = 0; i < 8; i++)
            drafts.save(_scope, 'sales_invoice:parallel-$i', {
              'notes': '$_marker $i',
              'amount': _exact,
            }, null),
        ]);
        await controller.create();
        _check(controller.form != null, 'Offline draft was not created.');
        await controller.saveLocal({
          ...controller.form!,
          'notes': _marker,
          'amount': _exact,
        });
        _check(
          !controller.localSaveFailed,
          'Offline draft did not reach disk.',
        );
        await manifest.writeAsString(
          jsonEncode({'slot': controller.slot}),
          flush: true,
        );
        _check(keys.writes == 1, 'Concurrent saves created competing keys.');
        final rows = await database.select(database.encryptedDrafts).get();
        _check(rows.length == 9, 'Missing seed drafts.');
        for (final row in rows) {
          final raw = utf8.decode(row.encryptedPayload, allowMalformed: true);
          _check(
            !raw.contains(_marker) && !raw.contains(_exact),
            'Plaintext in stored payload.',
          );
        }
      } else {
        final metadata = receivableMap(
          jsonDecode(await manifest.readAsString()),
        );
        final draftSlot = metadata['slot']! as String;
        for (var i = 0; i < 8; i++) {
          final restored = await drafts.load(
            _scope,
            'sales_invoice:parallel-$i',
          );
          _check(
            restored?.form['amount'] == _exact,
            'A parallel draft did not decrypt after restart.',
          );
        }
        final offlineDraft = await drafts.load(_scope, draftSlot);
        _check(
          offlineDraft?.form['amount'] == _exact,
          'Exact offline value changed after restart.',
        );
        for (final scope in [
          _scope.copyWith(tenantId: 'other'),
          _scope.copyWith(actorId: 'other'),
          _scope.copyWith(legalEntityId: 'other'),
          _scope.copyWith(branchId: 'other'),
        ]) {
          _check(
            await drafts.load(scope, draftSlot) == null,
            'Cross-scope recovery exposed a draft.',
          );
          _check(
            (await drafts.recovery(scope)).items.isEmpty,
            'Cross-scope recovery listed a draft.',
          );
        }
        if (phase == 'interrupt') {
          await controller.recover(draftSlot);
          _check(
            controller.form?['notes'] == _marker,
            'First offline edits were lost.',
          );
          await controller.saveLocal({
            ...controller.form!,
            'notes': '$_marker after restart',
          });
          await controller.saveServer();
          _check(gateway.calls == 0, 'Offline recovery dispatched a command.');
          await controller.closeEditor();
          controller.setOnline(true);
          await controller.open(ReceivableDocument(_document()));
          await controller.action('post');
          _check(
            gateway.calls == 1 && controller.pending,
            'Lost response did not retain recovery.',
          );
          final saved = (await drafts.load(_scope, _postSlot))!;
          final encoded = jsonEncode({
            'rpc': saved.rpc,
            'envelope': saved.envelope.toJson((p) => p),
          });
          _check(
            encoded == await gateway.commit.readAsString(),
            'Pending command differs from dispatched command.',
          );
        } else if (phase == 'retry') {
          await controller.recover(_postSlot);
          _check(
            controller.pending,
            'Pending command was lost after process termination.',
          );
          await controller.retry();
          _check(
            gateway.calls == 0 && controller.pending,
            'Offline retry dispatched.',
          );
          controller.setOnline(true);
          await controller.retry();
          _check(
            gateway.calls == 1 && !controller.pending,
            'Identical online retry did not finish.',
          );
          _check(
            controller.document?.status == 'posted',
            'Confirmed receipt did not update controller.',
          );
          _check(
            await drafts.load(_scope, _postSlot) == null,
            'Confirmed command remains recoverable.',
          );
        } else if (phase == 'verify') {
          _check(
            await drafts.load(_scope, _postSlot) == null,
            'Completed command returned after restart.',
          );
          _check(
            offlineDraft?.form['notes'] == '$_marker after restart',
            'Later offline edits were lost.',
          );
          _check(
            (await drafts.recovery(_scope)).items.length == 9,
            'Unexpected final recovery inventory.',
          );
        } else {
          throw ArgumentError.value(phase, 'phase');
        }
        _check(keys.writes == 0, 'Restart regenerated the encryption key.');
      }
    }
    // Seed and interrupt intentionally leave SQLite and Flutter running. The
    // parent terminates the exact process only after this flushed ready marker.
    if (phase != 'seed' && phase != 'interrupt') {
      controller?.dispose();
      await database?.close();
    }
    await result.writeAsString(
      jsonEncode({
        'phase': phase,
        'passed': true,
        'pid': pid,
        'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'nativeKeyWrites': keys.writes,
        'databaseClosed': phase != 'seed' && phase != 'interrupt',
        'backend': 'file-backed simulated response loss; no network',
        'authenticatedWorkflowVerified': false,
      }),
      flush: true,
    );
  } catch (error, stack) {
    await result.writeAsString(
      jsonEncode({
        'phase': phase,
        'passed': false,
        'pid': pid,
        'error': error.toString(),
        'stack': stack.toString(),
      }),
      flush: true,
    );
  }
  // Keep the process available for explicit parent-owned termination.
  await Completer<void>().future;
}
