import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/landed_extension.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_controller.dart';

import '../../../packages/jentra_domain/test/support/landed_extension_fixture.dart';
import 'landed_extension_workspace_test.dart' show Landed;
import 'support/procurement_fakes.dart' show Keys;

class HeldExtension extends Landed {
  Completer<Map<String, Object?>>? previewReply;
  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) => previewReply?.future ?? super.preview(scope, payload);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: '10000000-0000-0000-0000-000000000001',
    legalEntityId: '10000000-0000-0000-0000-000000000002',
    branchId: '10000000-0000-0000-0000-000000000003',
    actorId: '10000000-0000-0000-0000-000000000004',
  );
  late JentraLocalDatabase db;
  late LandedExtensionDraftStore drafts;
  late HeldExtension gateway;
  late LandedExtensionController c;
  setUp(() async {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = LandedExtensionDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = HeldExtension();
    c = LandedExtensionController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
    );
    c.form = landedInput();
    await c.calculate();
    c.options['receipts'] = [
      {'id': landedReceipt},
    ];
    c.posted = landedEvidence();
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
      'multi-receipt $code hides server evidence and retains sealed inputs',
      () async {
        c.posted = null;
        gateway.previewReply = Completer();
        final reading = c.calculate();
        gateway.previewReply!.completeError(
          DomainError(code: code, message: 'Recheck access'),
        );
        await reading;
        expect(c.accessDenied, isTrue);
        expect(c.preview, isNull);
        expect(c.posted, isNull);
        expect(c.options, isEmpty);
        expect(
          (await drafts.store.load(scope, landedId))!.form['total_amount'],
          landedInput()['total_amount'],
        );
        gateway.previewReply = null;
        await c.initialize();
        expect(c.accessDenied, isFalse);
        expect(c.preview, isNull);
      },
    );
  }
  test(
    'obsolete preview denial cannot lock a reconnected multi-receipt workspace',
    () async {
      c.posted = null;
      gateway.previewReply = Completer();
      final reading = c.calculate();
      c.setOnline(false);
      c.setOnline(true);
      gateway.previewReply!.completeError(
        const DomainError(code: 'PERMISSION_DENIED', message: 'old'),
      );
      await reading;
      expect(c.accessDenied, isFalse);
      expect(c.error, isNull);
      expect(c.preview, isNull);
    },
  );
  test(
    'disposed multi-receipt controller rejects further input edits',
    () async {
      final original = c.form!['total_amount'];
      c.dispose();
      c.update('total_amount', '0.000001');
      expect(c.form?['total_amount'], anyOf(isNull, original));
      c = LandedExtensionController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: false,
      );
    },
  );
}
