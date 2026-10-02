import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_screen.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_screen.dart';

import 'stock_count_workspace_test.dart' show Counts;
import 'disposition_workspace_test.dart' show Dispositions;
import 'support/procurement_fakes.dart' show Keys;

class CountValues extends Counts {
  Completer<Map<String, Object?>>? commandReply, detailReply;
  int detailCalls = 0;
  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async {
    detailCalls++;
    return detailReply?.future ?? Future.value(detailResult!);
  }

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    if (commandReply != null) {
      commands.add(command);
      return commandReply!.future;
    }
    return detailResult = await super.execute(verb, command);
  }
}

class DispositionValues extends Dispositions {
  Map<String, Object?>? current;
  Completer<Map<String, Object?>>? detailReply;
  int detailCalls = 0;
  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async {
    detailCalls++;
    return detailReply?.future ?? Future.value(current!);
  }

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async => current = await super.execute(verb, command);
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
  late JentraLocalDatabase database;
  late QuotationDraftStore drafts;
  late CountValues counts;
  late DispositionValues dispositions;
  late StockCountController count;
  late DispositionController disposition;
  StockCountController makeCount({bool online = true}) => StockCountController(
    scope: scope,
    gateway: counts,
    drafts: drafts,
    online: online,
    permissions: {'inventory.adjustments.post', 'inventory.cost.view'},
  );
  DispositionController makeDisposition({bool online = true}) =>
      DispositionController(
        scope: scope,
        gateway: dispositions,
        drafts: drafts,
        online: online,
        permissions: {'inventory.dispositions.post', 'inventory.cost.view'},
      );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    counts = CountValues();
    dispositions = DispositionValues();
    count = makeCount();
    disposition = makeDisposition();
  });
  tearDown(() async {
    count.dispose();
    disposition.dispose();
    await database.close();
  });
  Future<void> countDraft() async {
    await count.create();
    count.update('warehouse_id', 'w');
    count.update('offset_account_id', 'expense');
    count.update('reason', 'Physical verification');
    count.update('document_date', '2026-09-30');
    count.addProduct({'id': 'p', 'name': 'Paper', 'on_hand_quantity': '10'});
    await count.act('save');
    count.updateLine(0, 'empty_unit_cost', '0.000001');
    await count.saveLocal();
  }

  Future<void> dispositionDraft() async {
    await disposition.create();
    disposition.update('warehouse_id', 'w');
    disposition.update('offset_account_id', 'expense');
    disposition.update('reason', 'Expired stock');
    disposition.update('document_date', '2026-09-30');
    disposition.addProduct({
      'id': 'p',
      'name': 'Paper',
      'base_unit_id': 'u',
      'tracking_mode': 'none',
    });
    disposition.updateLine(0, 'quantity', '3.000001');
    await disposition.act('save');
  }

  test(
    'count recovery keeps exact cost input and omits server value outputs',
    () async {
      await countDraft();
      expect(count.form!['grand_total'], '0.000000');
      final saved = (await drafts.load(scope, StockCountController.slot))!;
      expect(saved.form['grand_total'], isNull);
      expect((saved.form['lines'] as List).single['variance_value'], isNull);
      expect(
        (saved.form['lines'] as List).single['empty_unit_cost'],
        '0.000001',
      );
      expect(saved.expectedVersion, 1);
      expect(saved.pending, isNull);
    },
  );
  test(
    'count disconnect keeps dirty quantities without reviving values',
    () async {
      await countDraft();
      count.updateLine(0, 'counted_quantity', '9007199254.740993');
      count.setOnline(false);
      expect(count.form!['grand_total'], isNull);
      expect((count.form!['lines'] as List).single['variance_value'], isNull);
      expect(
        (count.form!['lines'] as List).single['counted_quantity'],
        '9007199254.740993',
      );
      count.setOnline(true);
      expect(count.form!['grand_total'], isNull);
    },
  );
  test(
    'disposition recovery omits carrying value and retains exact quantity',
    () async {
      await dispositionDraft();
      expect(disposition.form!['grand_total'], '30.037037');
      final saved = (await drafts.load(scope, DispositionController.slot))!;
      expect(saved.form['grand_total'], isNull);
      expect((saved.form['lines'] as List).single['carrying_value'], isNull);
      expect((saved.form['lines'] as List).single['quantity'], '3.000001');
      expect(saved.pending, isNull);
    },
  );
  test(
    'disposition disconnect clears approval values while preserving inputs',
    () async {
      await dispositionDraft();
      disposition.setOnline(false);
      expect(disposition.form!['grand_total'], isNull);
      expect(
        (disposition.form!['lines'] as List).single['carrying_value'],
        isNull,
      );
      expect(
        (disposition.form!['lines'] as List).single['quantity'],
        '3.000001',
      );
      disposition.setOnline(true);
      expect(disposition.form!['grand_total'], isNull);
    },
  );
  test(
    'uncertain count restart preserves the original sealed wire identity',
    () async {
      await countDraft();
      count.updateLine(0, 'counted_quantity', '0.000001');
      counts.uncertain = true;
      await count.act('save');
      final original = jsonEncode(
        count.local!.pending!.envelope.toJson((p) => p),
      );
      count.dispose();
      count = makeCount(online: false);
      await count.initialize();
      expect(
        jsonEncode(count.local!.pending!.envelope.toJson((p) => p)),
        original,
      );
      expect(count.form!['grand_total'], isNull);
      expect(
        (count.form!['lines'] as List).single['counted_quantity'],
        '0.000001',
      );
      count.setOnline(true);
      counts.uncertain = false;
      await count.act('retry');
      expect(jsonEncode(counts.commands.last.toJson((p) => p)), original);
      expect(
        (await drafts.load(scope, StockCountController.slot))!.pending,
        isNull,
      );
    },
  );
  for (final kind in ['count', 'disposition']) {
    final slot = kind == 'count'
        ? StockCountController.slot
        : DispositionController.slot;
    dynamic controller() => kind == 'count' ? count : disposition;
    dynamic gateway() => kind == 'count' ? counts : dispositions;
    Future<void> prepare() =>
        kind == 'count' ? countDraft() : dispositionDraft();
    test(
      '$kind legacy recovery hides values without rewriting the sealed request',
      () async {
        await prepare();
        final dynamic c = controller();
        final legacy = <String, Object?>{
          ...c.form,
          '_dirty': false,
          'post_state': {
            'p': {'carrying_value': '999.000001'},
          },
          'journal_entry_id': 'journal',
          'stock_movement_id': 'movement',
        };
        await drafts.save(scope, slot, legacy, expectedVersion: 1);
        final pending = await drafts.prepare(
          scope,
          slot,
          verb: 'save',
          payload: {'id': legacy['id']},
          expectedVersion: 1,
        );
        final original = jsonEncode(pending.toJson());
        await c.initialize();
        expect(c.form['grand_total'], isNull);
        expect(c.form['post_state'], isNull);
        expect(c.form['journal_entry_id'], isNull);
        expect(
          jsonEncode((await drafts.load(scope, slot))!.pending!.toJson()),
          original,
        );
        await c.reloadEvidence();
        expect(gateway().detailCalls, 0);
        expect(
          jsonEncode((await drafts.load(scope, slot))!.pending!.toJson()),
          original,
        );
      },
    );
    test(
      '$kind unchanged saved recovery reloads scoped server evidence explicitly',
      () async {
        await prepare();
        final dynamic c = controller();
        // A save response omits the local dirty marker, as the public API does.
        await c.act('save');
        c.setOnline(false);
        c.setOnline(true);
        expect(c.form['grand_total'], isNull);
        expect(c.canReloadEvidence, isTrue);
        await c.reloadEvidence();
        expect(c.form['grand_total'], isNotNull);
        expect(gateway().detailCalls, 1);
        expect((await drafts.load(scope, slot))!.form['grand_total'], isNull);
      },
    );
    test(
      '$kind reload cannot discard dirty input or accept a disconnected reply',
      () async {
        await prepare();
        final dynamic c = controller();
        await c.act('save');
        c.setOnline(false);
        c.setOnline(true);
        c.update('reason', 'Exact local reason');
        expect(c.canReloadEvidence, isFalse);
        await c.reloadEvidence();
        expect(gateway().detailCalls, 0);
        await c.act('save');
        gateway().detailReply = Completer<Map<String, Object?>>();
        final loading = c.reloadEvidence() as Future<void>;
        while (gateway().detailCalls == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        c.setOnline(false);
        gateway().detailReply.complete({
          'id': c.form['id'],
          'grand_total': '99.000001',
          'reason': 'Obsolete read',
        });
        await loading;
        expect(c.form['grand_total'], isNull);
        expect(c.form['reason'], 'Exact local reason');
      },
    );
    for (final code in [
      'PERMISSION_DENIED',
      'ACCESS_DENIED',
      'MFA_REQUIRED',
      'AUTHENTICATION_REQUIRED',
    ]) {
      test(
        '$kind $code detail denial clears monetary evidence and preserves local inputs',
        () async {
          await prepare();
          final dynamic c = controller();
          await c.act('save');
          gateway().detailReply = Completer<Map<String, Object?>>();
          final reading = c.reloadEvidence() as Future<void>;
          while (gateway().detailCalls == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          gateway().detailReply.completeError(
            DomainError(code: code, message: 'Read access changed.'),
          );
          await reading;
          expect(c.accessDenied, isTrue);
          expect(c.form['grand_total'], isNull);
          expect(
            (await drafts.load(scope, slot))!.form['reason'],
            kind == 'count' ? 'Physical verification' : 'Expired stock',
          );
          expect(c.canReloadEvidence, isFalse);
        },
      );
    }
    for (final loss in ['disconnect', 'dispose']) {
      test(
        '$kind confirmed reply after $loss acknowledges input-only recovery atomically',
        () async {
          await prepare();
          final dynamic c = controller();
          gateway().commandReply = Completer<Map<String, Object?>>();
          final priorCommands = gateway().commands.length as int;
          final action = c.act('save') as Future<void>;
          while (gateway().commands.length == priorCommands) {
            await Future<void>.delayed(Duration.zero);
          }
          final result = <String, Object?>{
            ...c.form,
            'version': 2,
            'grand_total': '88.000001',
            '_dirty': false,
          };
          if (loss == 'disconnect') {
            c.setOnline(false);
          } else {
            c.dispose();
            if (kind == 'count') {
              count = makeCount(online: false);
            } else {
              disposition = makeDisposition(online: false);
            }
          }
          gateway().commandReply.complete(result);
          await action;
          final saved = (await drafts.load(scope, slot))!;
          expect(saved.pending, isNull);
          expect(saved.expectedVersion, 2);
          expect(saved.form['grand_total'], isNull);
          await controller().initialize();
          expect(controller().form['grand_total'], isNull);
          expect(controller().form['id'], result['id']);
        },
      );
    }
  }
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        for (final kind in ['count', 'disposition']) {
          final tag =
              '${kind}_${size.width.toInt()}_${dark ? 'dark' : 'light'}_${compact ? 'compact' : 'comfortable'}_200';
          testWidgets('input-only recovery and keyboard reload rendered $tag', (
            tester,
          ) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final semantics = tester.ensureSemantics();
            try {
              final dynamic c = kind == 'count' ? count : disposition;
              if (kind == 'count') {
                await countDraft();
              } else {
                await dispositionDraft();
              }
              await c.act('save');
              c.setOnline(false);
              final key = GlobalKey();
              await tester.pumpWidget(
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
                  home: Scaffold(
                    body: kind == 'count'
                        ? StockCountWorkspace(controller: count)
                        : DispositionWorkspace(controller: disposition),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final reload = find.text('Reload permitted value evidence');
              await tester.scrollUntilVisible(
                reload,
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(find.textContaining('30.037037'), findsNothing);
              expect(find.textContaining('20.024691'), findsNothing);
              expect(find.textContaining('null value'), findsNothing);
              expect(
                tester
                    .widget<OutlinedButton>(
                      find
                          .ancestor(
                            of: reload,
                            matching: find.byType(OutlinedButton),
                          )
                          .first,
                    )
                    .onPressed,
                isNull,
              );
              expect(tester.takeException(), isNull);
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                image.dispose();
                final file = File(
                  '../../build/remaining-wave3/visual/inventory_recovery_$tag.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
              });
              c.setOnline(true);
              await tester.pumpAndSettle();
              Focus.of(tester.element(reload)).requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
              expect(c.form['grand_total'], isNotNull);
              expect(reload, findsNothing);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            } finally {
              semantics.dispose();
            }
          });
        }
      }
    }
  }
}
