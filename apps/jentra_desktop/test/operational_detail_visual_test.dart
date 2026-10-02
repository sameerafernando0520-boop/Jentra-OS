import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/operations/operational_controller.dart';
import 'package:jentra_desktop/src/features/operations/operational_file_gateway.dart';
import 'package:jentra_desktop/src/features/operations/operational_screen.dart';

class _Evidence implements OperationalGateway {
  @override
  Future<Map<String, Object?>> evidence(
    TenantContext scope,
    String kind,
    String id, {
    String? after,
  }) async => {
    'header': {
      'id': id,
      'branch_id': scope.branchId,
      'document_number': 'BILL-0042',
      'status': 'posted',
      'document_date': '2026-09-20',
      'currency_code': 'LKR',
      'total': '900719925474.099999',
      'journal_entry_id': '00000000-0000-4000-8000-000000000010',
    },
    'items': [
      {
        'id': '00000000-0000-4000-8000-000000000002',
        'description': 'Recorded goods receipt line',
        'quantity': '123456.000000',
        'amount': '900719925474.099999',
      },
    ],
    'next_cursor': null,
    'commands': [
      {
        'command_id': '00000000-0000-4000-8000-000000000003',
        'request_id': '00000000-0000-4000-8000-000000000004',
        'completed_at': '2026-09-20T12:00:00Z',
      },
    ],
    'attachments': [
      {
        'id': '00000000-0000-4000-8000-000000000005',
        'file_name': 'signed-supplier-proof.pdf',
        'byte_size': '4096',
        'upload_status': 'ready',
        'version': 2,
      },
    ],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Files implements OperationalFileGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    tenantId: '00000000-0000-4000-8000-000000000100',
    actorId: '00000000-0000-4000-8000-000000000101',
    legalEntityId: '00000000-0000-4000-8000-000000000102',
    branchId: '00000000-0000-4000-8000-000000000103',
  );
  final target = (
    tenantId: scope.tenantId,
    entityId: scope.legalEntityId!,
    branchId: scope.branchId!,
    kind: 'supplier_bill',
    id: '00000000-0000-4000-8000-000000000001',
  );
  for (final (width, height) in [
    (1024.0, 720.0),
    (1440.0, 900.0),
    (1920.0, 1080.0),
    (3840.0, 2160.0),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'operational detail ${width.toInt()} ${dark ? 'dark' : 'light'} 200%',
        (tester) async {
          final controller = OperationalController(
            scope: scope,
            gateway: _Evidence(),
            target: target,
            files: _Files(),
            online: true,
          );
          addTearDown(controller.dispose);
          await controller.refresh();
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final base = dark ? JentraTheme.dark() : JentraTheme.light();
          await tester.pumpWidget(
            MaterialApp(
              theme: base.copyWith(
                visualDensity: dark
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: const Key('operational-detail-golden'),
                child: Scaffold(
                  body: OperationalWorkspace(
                    controller: controller,
                    canReadJournal: true,
                    canManageFiles: true,
                    fileService: const SetupFileService(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (width == 1024) {
            await tester.drag(find.byType(ListView), const Offset(0, -1300));
            await tester.pumpAndSettle();
            expect(find.text('Attachments'), findsOneWidget);
          }
          await expectLater(
            find.byKey(const Key('operational-detail-golden')),
            matchesGoldenFile(
              'goldens/operational_detail_${width.toInt()}_${dark ? 'dark_compact' : 'light_comfortable'}_200.png',
            ),
          );
        },
      );
    }
  }
}
