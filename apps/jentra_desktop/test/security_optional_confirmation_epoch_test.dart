import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_controller.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';

import 'landed_value_workspace_test.dart' show LandedGateway;
import 'receivables_controller_test.dart' as ar;
import 'support/procurement_fakes.dart' show Keys;

class _Landed extends LandedGateway {
  final entered = Completer<void>();
  final reply = Completer<Map<String, Object?>>();
  bool armed = false;
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    if (armed && resource == 'posted') {
      entered.complete();
      return reply.future;
    }
    return super.options(scope, resource, after: after);
  }
}

class _Receivables extends ar.FakeReceivables {
  Object? pageFailure;
  Completer<void>? hold;
  final entered = Completer<void>();
  @override
  Future<CursorPage<ReceivableDocument>> page(
    TenantContext scope,
    ReceivableKind kind, {
    String? cursor,
    String? status,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await hold?.future;
    if (pageFailure != null) throw pageFailure!;
    return super.page(scope, kind, cursor: cursor, status: status);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('single receipt confirmed refresh', () {
    late JentraLocalDatabase db;
    late QuotationDraftStore drafts;
    late _Landed gateway;
    late LandedValueController c;
    const scope = TenantContext(
      tenantId: 't',
      actorId: 'a',
      legalEntityId: 'e',
      branchId: 'b',
    );
    setUp(() async {
      db = JentraLocalDatabase(NativeDatabase.memory());
      drafts = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      );
      gateway = _Landed();
      c = LandedValueController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
      await c.initialize();
      await c.create();
      for (final entry in {
        'receipt_line_id': 'receipt',
        'offset_account_id': 'expense',
        'variance_account_id': 'expense',
        'amount': '10.000001',
        'document_date': '2026-09-19',
        'reference': 'FREIGHT-42',
        'reason': 'Reclassify recorded freight expense',
      }.entries) {
        c.update(entry.key, entry.value);
      }
      await c.calculate();
      gateway.armed = true;
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });
    for (final code in [
      'PERMISSION_DENIED',
      'ACCESS_DENIED',
      'MFA_REQUIRED',
      'AUTHENTICATION_REQUIRED',
    ]) {
      test(
        'current $code retains typed guidance after durable posting',
        () async {
          final work = c.post();
          await gateway.entered.future;
          gateway.reply.completeError(
            DomainError(
              code: code,
              message: 'Current authority required: $code',
            ),
          );
          await work;
          expect(c.accessDenied, true);
          expect(c.options, isEmpty);
          expect(c.preview, isNull);
          expect(c.form, isNull);
          expect(c.error, contains(code));
          expect(c.message, contains('confirmed'));
          expect(
            (await drafts.load(scope, LandedValueController.slot))?.pending,
            isNull,
          );
          expect(gateway.commands, hasLength(1));
        },
      );
    }
    test('obsolete denial cannot revoke replacement connection after durable posting', () async {
      final work = c.post();
      await gateway.entered.future;
      expect(
        (await drafts.load(scope, LandedValueController.slot))?.pending,
        isNull,
      );
      c.setOnline(false);
      c.setOnline(true);
      gateway.reply.completeError(
        const DomainError(code: 'MFA_REQUIRED', message: 'Old authority'),
      );
      await work;
      expect(c.accessDenied, false);
      expect(c.error, isNull);
      expect(c.preview, isNull);
      expect(gateway.commands, hasLength(1));
      expect(c.message, contains('confirmed'));
    });
  });
  group('AR confirmed optional refresh', () {
    late JentraLocalDatabase db;
    late ReceivableDraftStore drafts;
    late _Receivables repo;
    late ReceivablesController c;
    setUp(() async {
      db = JentraLocalDatabase(NativeDatabase.memory());
      drafts = ReceivableDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: ar.MemoryKeys())),
      );
      repo = _Receivables();
      repo.doc = ReceivableDocument(ar.snapshot(status: 'approved'));
      c = ReceivablesController(
        scope: ar.scope,
        capabilities: ar.permissions,
        repository: repo,
        drafts: drafts,
        online: true,
      );
      await c.open(repo.doc);
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });
    for (final code in [
      'PERMISSION_DENIED',
      'ACCESS_DENIED',
      'MFA_REQUIRED',
      'AUTHENTICATION_REQUIRED',
    ]) {
      test(
        'current $code hides confirmed document and retains durable acknowledgement',
        () async {
          repo.pageFailure = ReceivableFailure(
            code,
            'Current authority required',
            definite: true,
          );
          await c.action('post');
          expect(repo.commands, hasLength(1));
          expect((await drafts.load(ar.scope, c.slot!))?.pending, isNot(true));
          expect(c.document, isNull);
          expect(c.page.items, isEmpty);
          expect(c.message, contains('Confirmed'));
          expect(c.error, contains(code));
        },
      );
    }
    test(
      'obsolete failed refresh does not annotate a replacement connection',
      () async {
        repo.hold = Completer();
        repo.pageFailure = const ReceivableFailure(
          'MFA_REQUIRED',
          'Old authority',
          definite: true,
        );
        final work = c.action('post');
        await repo.entered.future;
        expect((await drafts.load(ar.scope, c.slot!))?.pending, isNot(true));
        c.setOnline(false);
        c.setOnline(true);
        final confirmed = c.message;
        repo.hold!.complete();
        await work;
        expect(c.message, confirmed);
        expect(c.error, isNull);
        expect(c.document, isNull);
        expect(repo.commands, hasLength(1));
      },
    );
  });
}
