import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/landed_extension.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_controller.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_screen.dart';

import '../../../packages/jentra_domain/test/support/landed_extension_fixture.dart';
import 'support/procurement_fakes.dart' show Keys;

class Landed implements LandedExtensionGateway {
  bool uncertain = true;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async => {'items': []};
  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) async => landedEvidence();
  @override
  Future<Map<String, Object?>> post(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry sealed landed request.',
      );
    }
    return {
      ...landedEvidence(),
      'id': landedId,
      'status': 'posted',
      'version': 1,
      'reference': command.payload['reference'],
      'reason': command.payload['reason'],
      'journal_ids': [landedAccount],
    };
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
    tenantId: '10000000-0000-0000-0000-000000000001',
    legalEntityId: '10000000-0000-0000-0000-000000000002',
    branchId: '10000000-0000-0000-0000-000000000003',
    actorId: '10000000-0000-0000-0000-000000000004',
  );
  late JentraLocalDatabase database;
  late LandedExtensionDraftStore drafts;
  late Landed gateway;
  late LandedExtensionController c;
  LandedExtensionController make() => LandedExtensionController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
  );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = LandedExtensionDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    gateway = Landed();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await database.close();
  });
  test('uncertain allocation restores exact original envelope and locks manual weights', () async {
    await c.initialize();
    c.form = landedInput();
    await c.calculate();
    await c.post();
    expect(c.local!.pending, isNotNull);
    expect(c.locked, isTrue);
    final original = jsonEncode(gateway.commands.single.toJson((v) => v));
    c.dispose();
    c = make();
    await c.initialize();
    expect(c.recovered, hasLength(1));
    await c.restore(c.recovered.single);
    c.weight(landedReceipt, '999');
    expect(((c.form!['receipts'] as List).single as Map)['weight'], '1.000001');
    gateway.uncertain = false;
    await c.post();
    expect(jsonEncode(gateway.commands.last.toJson((v) => v)), original);
    expect(c.local, isNull);
    expect(c.recovered, isEmpty);
    c.setOnline(false);
    expect(c.preview, isNull);
    expect(c.posted, isNull);
  });
  for (final (width, height) in [
    (1024.0, 720.0),
    (1440.0, 900.0),
    (1920.0, 1080.0),
    (3840.0, 2160.0),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'landed allocation ${width.toInt()} ${dark ? 'dark' : 'light'} 200%',
        (tester) async {
          c.posted = {
            ...landedEvidence(),
            'id': landedId,
            'status': 'posted',
            'reference': 'FREIGHT-01',
            'reason': 'Recorded freight allocation',
            'journal_ids': [landedAccount],
          };
          c.preview = c.posted;
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = dark ? JentraTheme.dark() : JentraTheme.light();
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(
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
                key: const Key('landed-preview'),
                child: Scaffold(body: LandedExtensionWorkspace(controller: c)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const Key('landed-preview')),
            matchesGoldenFile(
              'goldens/landed_extension_${width.toInt()}_${dark ? 'dark_compact' : 'light_comfortable'}_200.png',
            ),
          );
        },
      );
    }
  }
}
