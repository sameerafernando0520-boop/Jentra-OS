import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';

import 'package:jentra_desktop/src/features/operations/operational_read_access.dart';
import 'package:jentra_desktop/src/features/procurement/conflict_comparison.dart';

const _scope = TenantContext(
  tenantId: 'tenant',
  actorId: 'actor',
  legalEntityId: 'entity',
  branchId: 'branch',
);
const _id = '11111111-1111-4111-8111-111111111111';
final _local = <String, Object?>{
  'id': _id,
  'status': 'draft',
  'version': 1,
  'supplier_reference': 'LOCAL-REF',
  'lines': [
    {
      'line_id': 'line',
      'quantity': '1.000001',
      'unit_price': '9007199254.740993',
      'tax_definition_id': 'local-tax',
      '_secret_ui': 'hidden',
    },
  ],
};
Map<String, Object?> _current() => {
  'id': _id,
  'status': 'draft',
  'version': 2,
  'supplier_reference': 'CURRENT-REF',
  'lines': [
    {
      'line_id': 'line',
      'quantity': '2.000002',
      'unit_price': '9007199254.740994',
      'tax_definition_id': 'current-tax',
    },
  ],
};

class _Access extends ChangeNotifier implements OperationalReadAccess {
  int epoch = 0;
  bool allowed = true;
  @override
  int get readAccessEpoch => epoch;
  @override
  bool currentRead(int value) => allowed && value == epoch;
  @override
  void denyReadAccess() {
    allowed = false;
    epoch++;
    notifyListeners();
  }

  void reconnect() {
    epoch++;
    notifyListeners();
  }
}

class _Gateway implements ProcurementGateway, ProcurementConflictGateway {
  Completer<Map<String, Object?>>? pending;
  Object? failure;
  var calls = 0;
  @override
  Future<Map<String, Object?>> conflictDocument(
    TenantContext scope,
    String kind,
    String id,
  ) async {
    expect(scope, _scope);
    expect(id, _id);
    calls++;
    if (failure != null) throw failure!;
    return pending == null ? _current() : pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected mutation: ${invocation.memberName}');
}

Future<void> _show(
  WidgetTester t,
  _Access access,
  _Gateway gateway, {
  String kind = 'purchase_order',
  bool Function()? hasForm,
  Future<void> Function()? discard,
  void Function(Map<String, Object?>)? select,
  Future<void> Function(Map<String, Object?>)? edit,
  double scale = 1,
  ThemeData? theme,
  GlobalKey? boundary,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: theme ?? JentraTheme.light(),
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: boundary, child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => reviewAndReloadProcurementConflict(
              context,
              access: access,
              gateway: gateway,
              scope: _scope,
              kind: kind,
              local: _local,
              discard: discard ?? () async {},
              hasForm: hasForm ?? () => false,
              select: select ?? (_) {},
              edit: edit ?? (_) async {},
            ),
            child: const Text('Compare'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Compare'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 250));
}

void main() {
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
  for (final kind in [
    'purchase_requisition',
    'purchase_order',
    'supplier_bill',
  ]) {
    testWidgets(
      '$kind compares exact material values and requires explicit reload',
      (t) async {
        final access = _Access(), gateway = _Gateway();
        var discarded = 0, edited = 0;
        Map<String, Object?>? selected;
        await _show(
          t,
          access,
          gateway,
          kind: kind,
          discard: () async {
            discarded++;
          },
          select: (row) => selected = row,
          edit: (row) async {
            edited++;
            expect(row['version'], 2);
          },
        );
        expect(find.text('Local: 1.000001'), findsOneWidget);
        expect(find.text('Current: 2.000002'), findsOneWidget);
        expect(find.text('Local: 9007199254.740993'), findsOneWidget);
        expect(find.text('Current: 9007199254.740994'), findsOneWidget);
        expect(find.textContaining('hidden'), findsNothing);
        expect(discarded, 0);
        expect(edited, 0);
        await t.tap(find.text('Reload current revision'));
        await t.pumpAndSettle();
        expect(discarded, 1);
        expect(edited, 1);
        expect(selected?['version'], 2);
      },
    );
  }
  testWidgets('cancel keeps original local draft and sends no command', (
    t,
  ) async {
    var discarded = false;
    await _show(
      t,
      _Access(),
      _Gateway(),
      discard: () async {
        discarded = true;
      },
    );
    await t.tap(find.text('Keep local draft'));
    await t.pumpAndSettle();
    expect(discarded, false);
    expect(_local['version'], 1);
  });
  testWidgets('failed local removal prevents replacing the retained draft', (
    t,
  ) async {
    var edited = false;
    await _show(
      t,
      _Access(),
      _Gateway(),
      hasForm: () => true,
      edit: (_) async {
        edited = true;
      },
    );
    await t.tap(find.text('Reload current revision'));
    await t.pumpAndSettle();
    expect(edited, false);
  });
  testWidgets(
    'obsolete late read after reconnect cannot reveal current fields or reload',
    (t) async {
      final access = _Access(), gateway = _Gateway()..pending = Completer();
      await _show(t, access, gateway);
      access.reconnect();
      gateway.pending!.complete(_current());
      await t.pumpAndSettle();
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(find.textContaining('CURRENT-REF'), findsNothing);
      expect(find.text('Reload current revision'), findsNothing);
    },
  );
  testWidgets(
    'current permission denial invalidates workspace without raw transport text',
    (t) async {
      final access = _Access(),
          gateway = _Gateway()
            ..failure = const DomainError(
              code: 'PERMISSION_DENIED',
              message: 'private raw detail',
            );
      await _show(t, access, gateway);
      await t.pumpAndSettle();
      expect(access.allowed, false);
      expect(find.text('private raw detail'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
    },
  );
  for (final size in [
    const Size(1024, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
    const Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      for (final density in JentraDensity.values) {
        testWidgets(
          'comparison ${size.width.toInt()} ${dark ? 'dark' : 'light'} ${density.name} renders at 200 percent',
          (t) async {
            t.view.physicalSize = size;
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            final key = GlobalKey();
            await _show(
              t,
              _Access(),
              _Gateway(),
              scale: 2,
              theme: dark
                  ? JentraTheme.dark(density: density)
                  : JentraTheme.light(density: density),
              boundary: key,
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            await t.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final output = File(
                '../../build/remaining-wave3/visual/conflict_${size.width.toInt()}_${dark ? 'dark' : 'light'}_${density.name}_200.png',
              );
              await output.parent.create(recursive: true);
              await output.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await t.tap(find.text('Keep local draft'));
            await t.pumpAndSettle();
          },
        );
      }
    }
  }
}
