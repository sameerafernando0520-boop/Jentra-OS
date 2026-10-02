import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_controller.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_screen.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_controller.dart';

import 'landed_value_workspace_test.dart' show LandedGateway, allocation;
import 'inventory_transfer_workspace_test.dart' show Transfers;
import 'support/procurement_fakes.dart' show Keys;

class HeldLandedReads extends LandedGateway {
  Completer<Map<String, Object?>>? previewReply, optionReply, postReply;
  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) => previewReply?.future ?? super.preview(scope, payload);
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) => optionReply?.future ?? super.options(scope, resource, after: after);
  @override
  Future<Map<String, Object?>> post(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    if (postReply != null) {
      commands.add(command);
      return postReply!.future;
    }
    return super.post(command);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late HeldLandedReads gateway;
  late LandedValueController c;
  late InventoryTransferController transfer;
  LandedValueController make() => LandedValueController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = HeldLandedReads();
    c = make();
    transfer = InventoryTransferController(
      scope: scope,
      gateway: Transfers(),
      drafts: drafts,
      online: true,
    );
  });
  tearDown(() async {
    c.dispose();
    transfer.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    await c.create();
    for (final entry in {
      'receipt_line_id': 'receipt',
      'offset_account_id': 'expense',
      'variance_account_id': 'expense',
      'amount': '10.000001',
      'document_date': '2026-09-30',
      'reference': 'FREIGHT-42',
      'reason': 'Reclassify freight',
    }.entries) {
      c.update(entry.key, entry.value);
    }
    await c.calculate();
  }

  Future<void> render(WidgetTester t) async {
    t.view.physicalSize = const Size(1440, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LandedValueWorkspace(controller: c)),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String text) async {
    final f = find.text(text);
    await t.scrollUntilVisible(
      f,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'landed confirmation clears earlier preview across disconnect and reconnect',
    (t) async {
      await ready();
      await render(t);
      await tap(t, 'Post adjustment');
      expect(find.text('Confirm posting'), findsOneWidget);
      c.setOnline(false);
      await t.pumpAndSettle();
      expect(find.text('Confirm posting'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      c.setOnline(true);
      await t.pumpAndSettle();
      expect(find.text('Confirm posting'), findsNothing);
      expect(gateway.commands, isEmpty);
    },
  );
  testWidgets(
    'open landed dropdown hides obsolete choices after access epoch changes',
    (t) async {
      await ready();
      await render(t);
      final picker = find.byType(DropdownButtonFormField<String>).first;
      await t.ensureVisible(picker);
      await t.tap(picker);
      await t.pumpAndSettle();
      expect(find.text('GR-0042 · Office paper'), findsWidgets);
      c.setOnline(false);
      await t.pumpAndSettle();
      expect(find.text('GR-0042 · Office paper'), findsNothing);
      c.setOnline(true);
      await t.pumpAndSettle();
      expect(find.text('GR-0042 · Office paper'), findsNothing);
      expect(c.form!['receipt_line_id'], 'receipt');
    },
  );
  testWidgets(
    'restored linked reversal confirms original identity without invented preview amounts',
    (t) async {
      await ready();
      await c.post();
      final original = c.form!['id'];
      await c.reverse();
      c.update('reason', 'Wrong receipt allocation');
      await c.save();
      c.dispose();
      c = make();
      await c.initialize();
      await render(t);
      expect(c.preview, isNull);
      await tap(t, 'Post adjustment');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('null'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('$original'),
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Confirm posting'));
      await t.pumpAndSettle();
      expect(gateway.commands.last.payload['reverse_of'], original);
      expect(gateway.commands.last.expectedEntityVersion, 1);
    },
  );
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        final tag =
            '${size.width.toInt()}_${dark ? 'dark' : 'light'}_${compact ? 'compact' : 'comfortable'}_200';
        testWidgets('landed input-only recovery rendered $tag', (t) async {
          await ready();
          c.setOnline(false);
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final semantics = t.ensureSemantics();
          final key = GlobalKey();
          try {
            await t.pumpWidget(
              MaterialApp(
                theme: (dark ? JentraTheme.dark() : JentraTheme.light())
                    .copyWith(
                      visualDensity: compact
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                    ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: RepaintBoundary(key: key, child: child!),
                ),
                home: Scaffold(body: LandedValueWorkspace(controller: c)),
              ),
            );
            await t.pumpAndSettle();
            await t.scrollUntilVisible(
              find.text('Preview exact allocation'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            expect(find.textContaining('6.666667'), findsNothing);
            expect(find.textContaining('3.333334'), findsNothing);
            expect(t.takeException(), isNull);
            await t.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final img = await boundary.toImage();
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              img.dispose();
              final f = File(
                '../../build/remaining-wave3/visual/landed_recovery_$tag.png',
              );
              await f.parent.create(recursive: true);
              await f.writeAsBytes(bytes!.buffer.asUint8List());
            });
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }

  test('landed recovery stores exact user amount but no server allocation or posted evidence', () async {
    await ready();
    final saved = (await drafts.load(scope, LandedValueController.slot))!;
    expect(saved.form['amount'], '10.000001');
    expect(saved.form['preview'], isNull);
    c.setOnline(false);
    expect(c.preview, isNull);
    expect(c.options, isEmpty);
    c.setOnline(true);
    expect(c.preview, isNull);
    await c.calculate();
    await c.post();
    expect(c.form!['status'], 'posted');
    expect(await drafts.load(scope, LandedValueController.slot), isNull);
    c.setOnline(false);
    expect(c.form, isNull);
    expect(c.preview, isNull);
  });
  for (final kind in ['preview', 'options']) {
    test('landed late $kind cannot revive a disconnected workspace', () async {
      await ready();
      final reply = Completer<Map<String, Object?>>();
      if (kind == 'preview') {
        gateway.previewReply = reply;
      } else {
        gateway.optionReply = reply;
      }
      final pending = kind == 'preview' ? c.calculate() : c.refresh('posted');
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      reply.complete(
        kind == 'preview'
            ? allocation
            : {
                'items': [
                  {'id': 'private'},
                ],
              },
      );
      await pending;
      expect(c.preview, isNull);
      expect(c.options, isEmpty);
      expect(c.form!['amount'], '10.000001');
    });
  }
  for (final code in [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
  ]) {
    test(
      'landed current $code clears reads and retains input recovery',
      () async {
        await ready();
        gateway.previewReply = Completer();
        final reading = c.calculate();
        gateway.previewReply!.completeError(
          DomainError(code: code, message: 'Recheck access'),
        );
        await reading;
        expect(c.accessDenied, isTrue);
        expect(c.options, isEmpty);
        expect(c.preview, isNull);
        expect(
          (await drafts.load(
            scope,
            LandedValueController.slot,
          ))!.form['amount'],
          '10.000001',
        );
        gateway.previewReply = null;
        await c.initialize();
        expect(c.accessDenied, isFalse);
        expect(c.preview, isNull);
        await c.calculate();
        expect(c.preview, isNotNull);
      },
    );
  }
  test(
    'obsolete landed preview denial cannot lock a reconnected workspace',
    () async {
      await ready();
      gateway.previewReply = Completer();
      final reading = c.calculate();
      c.setOnline(false);
      c.setOnline(true);
      gateway.previewReply!.completeError(
        const DomainError(code: 'MFA_REQUIRED', message: 'old'),
      );
      await reading;
      expect(c.accessDenied, isFalse);
      expect(c.error, isNull);
      expect(c.preview, isNull);
    },
  );
  test('legacy posted landed envelope is not presented or rewritten during uncertain retry', () async {
    await ready();
    final legacy = {...c.form!, 'preview': allocation};
    await drafts.save(
      scope,
      LandedValueController.slot,
      legacy,
      expectedVersion: 0,
    );
    final pending = await drafts.prepare(
      scope,
      LandedValueController.slot,
      verb: 'accept',
      payload: {...c.form!, 'basis_hash': 'basis'},
      expectedVersion: 0,
    );
    final original = jsonEncode(pending.toJson());
    c.dispose();
    c = make();
    c.setOnline(false);
    await c.initialize();
    expect(c.preview, isNull);
    expect(c.form!['preview'], isNull);
    expect(jsonEncode(c.local!.pending!.toJson()), original);
    c.setOnline(true);
    await c.post();
    expect(
      jsonEncode(gateway.commands.last.toJson((p) => p)),
      jsonEncode(pending.envelope.toJson((p) => p)),
    );
  });
  test('confirmed late landed post completes original receipt without restoring offline ledger evidence', () async {
    await ready();
    gateway.postReply = Completer();
    final posting = c.post();
    while (gateway.commands.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    c.setOnline(false);
    gateway.postReply!.complete({
      ...allocation,
      'id': c.form!['id'],
      'status': 'posted',
      'version': 1,
    });
    await posting;
    expect(await drafts.load(scope, LandedValueController.slot), isNull);
    expect(c.preview, isNull);
    expect(c.form, isNull);
  });
  test('transfer receive recovery omits copied cost and history while retaining exact identity', () async {
    await transfer.prepare({
      'id': 'transfer',
      'version': 4,
      'status': 'in_transit',
      'reference': 'TR-4',
      'grand_total': '9007199254.740993',
      'events': [
        {'journal_entry_id': 'j'},
      ],
      'lines': [
        {
          'product_id': 'p',
          'quantity': '0.000001',
          'base_quantity': '0.000001',
          'carrying_value': '10.000001',
        },
      ],
    }, 'receive');
    final saved = (await drafts.load(scope, InventoryTransferController.slot))!;
    expect(saved.form['id'], 'transfer');
    expect(saved.expectedVersion, 4);
    expect(saved.form['grand_total'], isNull);
    expect(saved.form['events'], isNull);
    expect((saved.form['lines'] as List).single['carrying_value'], isNull);
    expect((saved.form['lines'] as List).single['quantity'], '0.000001');
  });
}
