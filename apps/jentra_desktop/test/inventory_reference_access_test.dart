import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/operations/operational_read_access.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_controller.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_screen.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_screen.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_screen.dart';

import 'inventory_transfer_workspace_test.dart' show Transfers;
import 'stock_count_workspace_test.dart' show Counts;
import 'disposition_workspace_test.dart' show Dispositions;
import 'support/procurement_fakes.dart' show Keys;

class ChoiceReply {
  Completer<void>? hold;
  Object? failure;
  final reads = <(String, String?, String?, String)>[];
  Future<Map<String, Object?>> read(
    String resource,
    String? warehouse,
    String? after,
    String search,
  ) async {
    reads.add((resource, warehouse, after, search));
    final blocker = hold, rejection = failure;
    if (blocker != null) await blocker.future;
    if (rejection != null) throw rejection;
    return {
      'items': [
        {
          'id': after == null ? 'one' : 'two',
          'name': after == null
              ? 'PRIVATE Warehouse One'
              : 'PRIVATE Warehouse Two',
          'code': after == null ? 'SER-ONE' : 'SER-TWO',
          'status': 'held',
        },
      ],
      'next_cursor': after == null ? 'after-one' : null,
    };
  }
}

class TransferChoices extends Transfers {
  TransferChoices(this.reply);
  final ChoiceReply reply;
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
    String search = '',
  }) => reply.read(resource, warehouse, after, search);
}

class CountChoices extends Counts {
  CountChoices(this.reply);
  final ChoiceReply reply;
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? after,
    String search = '',
  }) => reply.read(resource, warehouse, after, search);
}

class DispositionChoices extends Dispositions {
  DispositionChoices(this.reply);
  final ChoiceReply reply;
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
  }) => reply.read(resource, warehouse, after, '');
}

typedef Access = ({
  OperationalReadAccess access,
  void Function(bool) online,
  VoidCallback dispose,
  bool Function() denied,
  Future<void> Function(BuildContext, void Function(Map<String, Object?>)) open,
});

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late ChoiceReply reply;
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
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    reply = ChoiceReply();
  });
  tearDown(() => db.close());
  final factories = <String, Access Function()>{
    'transfer': () {
      final c = InventoryTransferController(
        scope: scope,
        gateway: TransferChoices(reply),
        drafts: drafts,
        online: true,
      );
      final workspace = InventoryTransferWorkspace(controller: c);
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
        open: (context, select) =>
            workspace.pick(context, 'warehouses', select),
      );
    },
    'count': () {
      final c = StockCountController(
        scope: scope,
        gateway: CountChoices(reply),
        drafts: drafts,
        online: true,
        permissions: {'inventory.adjustments.post', 'inventory.cost.view'},
      );
      final workspace = StockCountWorkspace(controller: c);
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
        open: (context, select) =>
            workspace.pick(context, 'warehouses', select),
      );
    },
    'disposition': () {
      final c = DispositionController(
        scope: scope,
        gateway: DispositionChoices(reply),
        drafts: drafts,
        online: true,
        permissions: {'inventory.dispositions.post', 'inventory.cost.view'},
      );
      final workspace = DispositionWorkspace(controller: c);
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
        open: (context, select) =>
            workspace.pick(context, 'warehouses', select),
      );
    },
  };
  Future<void> open(
    WidgetTester tester,
    Access c, {
    void Function(Map<String, Object?>)? select,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => c.open(context, select ?? (_) {}),
              child: const Text('Open selector'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open selector'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final factory in factories.entries) {
    testWidgets('${factory.key} root choices clear offline and never revive', (
      tester,
    ) async {
      final c = factory.value();
      addTearDown(c.dispose);
      Map<String, Object?>? selected;
      await open(tester, c, select: (row) => selected = row);
      expect(find.text('PRIVATE Warehouse One'), findsOneWidget);
      c.online(false);
      await tester.pump();
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      c.online(true);
      await tester.pump();
      expect(find.text('Reference access changed'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      await tester.tap(find.text('Open selector'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PRIVATE Warehouse One'));
      await tester.pumpAndSettle();
      expect(selected?['id'], 'one');
      expect(reply.reads.length, 2);
    });
    testWidgets(
      '${factory.key} disposal hides root choices and ignores late response',
      (tester) async {
        reply.hold = Completer();
        final c = factory.value();
        await open(tester, c);
        c.dispose();
        await tester.pump();
        expect(find.text('Reference access changed'), findsOneWidget);
        reply.hold!.complete();
        await tester.pumpAndSettle();
        expect(find.textContaining('PRIVATE'), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
    for (final code in [
      'PERMISSION_DENIED',
      'ACCESS_DENIED',
      'MFA_REQUIRED',
      'AUTHENTICATION_REQUIRED',
    ]) {
      testWidgets(
        '${factory.key} $code clears the current selector without diagnostics',
        (tester) async {
          reply.failure = DomainError(
            code: code,
            message: 'PRIVATE internal host SQL diagnostics',
          );
          final c = factory.value();
          addTearDown(c.dispose);
          await open(tester, c);
          await tester.pumpAndSettle();
          expect(c.denied(), isTrue);
          expect(find.text('Reference access changed'), findsOneWidget);
          expect(find.textContaining('PRIVATE'), findsNothing);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '${factory.key} old denied reply cannot poison reconnected access',
      (tester) async {
        reply.hold = Completer();
        reply.failure = const DomainError(
          code: 'MFA_REQUIRED',
          message: 'PRIVATE',
        );
        final c = factory.value();
        addTearDown(c.dispose);
        await open(tester, c);
        c.online(false);
        c.online(true);
        await tester.pump();
        reply.hold!.complete();
        await tester.pumpAndSettle();
        expect(c.denied(), isFalse);
        expect(c.access.currentRead(c.access.readAccessEpoch), isTrue);
        expect(find.textContaining('PRIVATE'), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      },
    );
    testWidgets('${factory.key} paging preserves the scoped cursor', (
      tester,
    ) async {
      final c = factory.value();
      addTearDown(c.dispose);
      await open(tester, c);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE Warehouse Two'), findsOneWidget);
      expect(reply.reads.last.$3, 'after-one');
      if (factory.key != 'disposition') {
        await tester.enterText(find.byType(TextField), 'Depot');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(reply.reads.last.$3, isNull);
        expect(reply.reads.last.$4, 'Depot');
      }
      await tester.tap(
        find.text(factory.key == 'disposition' ? 'Back' : 'Cancel'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('offline selector issues no request or dialog', (tester) async {
    final c = factories['count']!();
    addTearDown(c.dispose);
    c.online(false);
    await open(tester, c);
    await tester.pumpAndSettle();
    expect(reply.reads, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });
  for (final factory in factories.entries) {
    testWidgets(
      '${factory.key} selector supports keyboard dismissal without selecting',
      (tester) async {
        final c = factory.value();
        addTearDown(c.dispose);
        Map<String, Object?>? selected;
        await open(tester, c, select: (row) => selected = row);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(selected, isNull);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${factory.key} access-loss Close is focusable and keyboard operable',
      (tester) async {
        final c = factory.value();
        addTearDown(c.dispose);
        await open(tester, c);
        c.online(false);
        await tester.pumpAndSettle();
        final focus = Focus.of(tester.element(find.text('Close')));
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${factory.key} unknown read failure is redacted and retry uses current access',
      (tester) async {
        reply.failure = StateError('PRIVATE transport host and SQL');
        final c = factory.value();
        addTearDown(c.dispose);
        await open(tester, c);
        await tester.pumpAndSettle();
        expect(c.denied(), isFalse);
        expect(find.textContaining('PRIVATE'), findsNothing);
        reply.failure = null;
        await tester.tap(
          find.text(factory.key == 'disposition' ? 'Retry' : 'Search / retry'),
        );
        await tester.pumpAndSettle();
        expect(find.text('PRIVATE Warehouse One'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(reply.reads.length, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'disposition selected serials clear offline and cannot update the draft',
    (tester) async {
      final c = DispositionController(
        scope: scope,
        gateway: DispositionChoices(reply),
        drafts: drafts,
        online: true,
        permissions: {'inventory.dispositions.post', 'inventory.cost.view'},
      );
      addTearDown(c.dispose);
      await c.create();
      c.update('warehouse_id', 'w');
      c.addProduct({
        'id': 'p',
        'name': 'Tracked asset',
        'tracking_mode': 'serial',
        'base_unit_id': 'u',
      });
      final workspace = DispositionWorkspace(controller: c);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => workspace.serials(
                  context,
                  0,
                  (c.form!['lines'] as List).first as Map,
                ),
                child: const Text('Choose serials'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose serials'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SER-ONE · held'));
      await tester.pump();
      expect(find.text('Use 1 serials'), findsOneWidget);
      c.setOnline(false);
      await tester.pump();
      expect(find.textContaining('SER-'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(((c.form!['lines'] as List).first as Map)['serial_ids'], isEmpty);
      c.setOnline(true);
      await tester.tap(find.text('Choose serials'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SER-ONE · held'));
      await tester.pump();
      await tester.tap(find.text('Use 1 serials'));
      await tester.pumpAndSettle();
      final line = (c.form!['lines'] as List).first as Map;
      expect(line['serial_ids'], ['one']);
      expect(line['quantity'], '1');
      expect(tester.takeException(), isNull);
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
        testWidgets('inventory root access loss rendered $tag', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final c = factories['count']!();
          addTearDown(c.dispose);
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? JentraTheme.dark() : JentraTheme.light()).copyWith(
                visualDensity: compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: RepaintBoundary(key: key, child: child!),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => c.open(context, (_) {}),
                    child: const Text('Open selector'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open selector'));
          await tester.pumpAndSettle();
          c.online(false);
          await tester.pumpAndSettle();
          expect(find.text('Reference access changed'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final file = File(
              '../../build/remaining-wave3/visual/inventory_access_$tag.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        });
      }
    }
  }
}
