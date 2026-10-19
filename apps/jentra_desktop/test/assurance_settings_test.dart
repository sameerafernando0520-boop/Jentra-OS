import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_settings_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_settings_panel.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'support/procurement_fakes.dart' show Keys;

String uid(int n) => '95000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

class FakeSettingsGateway implements AssuranceSettingsGateway {
  String? failure;
  int? tenantVersion;
  AssuranceSettings effective = AssuranceSettings.defaults;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];

  Map<String, Object?> _effective() => effective.toPayload('x')
    ..remove('level')
    ..['source'] = effective.source;

  @override
  Future<AssuranceSettingsPage> settings(TenantContext s) async =>
      AssuranceSettingsPage.fromJson({
        'effective': _effective(),
        'tenant': tenantVersion == null ? null : {'version': tenantVersion},
        'entity': null,
        'rules': [
          for (final c in assuranceMonitoringRuleCodes)
            {'code': c, 'description': 'Rule ${c.toLowerCase()}'},
        ],
      });

  @override
  Future<Map<String, Object?>> saveSettings(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Refused: $failure');
    }
    tenantVersion = (tenantVersion ?? 0) + 1;
    effective = AssuranceSettings.fromJson({
      ...c.payload,
      'source': c.payload['level'],
    });
    return {'level': c.payload['level'], 'version': tenantVersion};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = TenantContext(
    tenantId: uid(90),
    actorId: uid(1),
    legalEntityId: uid(91),
    branchId: uid(92),
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late FakeSettingsGateway gateway;
  late AssuranceSettingsController c;
  AssuranceSettingsController make({
    Set<String> caps = const {'assurance.plan.manage'},
  }) => AssuranceSettingsController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    online: true,
    capabilities: caps,
  );
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
    gateway = FakeSettingsGateway();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('defaults are shown until a tenant row exists', () async {
    await c.initialize();
    expect(c.page!.effective.source, 'default');
    expect(c.page!.versionFor('tenant'), 0);
  });

  test('a tenant edit is sealed at version 0 with whole numbers', () async {
    await c.initialize();
    await c.edit('tenant');
    c.field('due_soon_days', '5');
    c.field('escalate_after_days', '10');
    c.field('band_high', '12');
    c.field('enabled.P2P_MATCH_OVERRIDE', false);
    c.field('min.P2P_OVERRIDE_BY_CREATOR', '3');
    expect(c.errors, isEmpty);
    await c.submit();
    expect(c.error, isNull);
    final sent = gateway.commands.single;
    expect(sent.expectedEntityVersion, 0);
    expect(sent.payload['due_soon_days'], 5);
    expect(sent.payload['rating_bands'], {
      'critical': 20,
      'high': 12,
      'medium': 5,
    });
    expect((sent.payload['monitoring']! as Map)['P2P_MATCH_OVERRIDE'], {
      'enabled': false,
      'min_count': 1,
    });
    expect((sent.payload['monitoring']! as Map)['P2P_OVERRIDE_BY_CREATOR'], {
      'enabled': true,
      'min_count': 3,
    });
    expect(c.page!.effective.source, 'tenant');
    expect(c.editing, isFalse);
  });

  test('invalid values are explained inline and never sent', () async {
    await c.initialize();
    await c.edit('tenant');
    c.field('band_critical', '10');
    c.field('due_soon_days', '0');
    expect(c.errors.keys, containsAll(['band_critical', 'due_soon_days']));
    expect(c.preview, isNull);
    await c.submit();
    expect(gateway.commands, isEmpty);
    expect(c.error, isNotNull);
  });

  test('the live preview follows edited days', () async {
    await c.initialize();
    await c.edit('tenant');
    c.field('due_soon_days', '5');
    final today = DateTime.utc(2026, 10, 20);
    expect(
      c.preview!.level(today.add(const Duration(days: 5)), today),
      ReminderLevel.dueSoon,
    );
  });

  test('an MFA refusal keeps the sealed request for the same retry', () async {
    await c.initialize();
    await c.edit('tenant');
    gateway.failure = 'MFA_REQUIRED';
    await c.submit();
    expect(c.pending, isTrue);
    gateway.failure = null;
    await c.submit();
    expect(gateway.commands, hasLength(2));
    expect(
      gateway.commands.first.idempotencyKey,
      gateway.commands.last.idempotencyKey,
    );
    expect(c.pending, isFalse);
  });

  test('viewers read settings but cannot edit', () async {
    c.dispose();
    c = make(caps: {'assurance.evidence.view'});
    await c.initialize();
    await c.edit('tenant');
    expect(c.editing, isFalse);
  });

  Future<void> render(WidgetTester t, bool dark) async {
    t.view.physicalSize = const Size(1024, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AssuranceSettingsPanel(controller: c),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('an invalid field shows its reason next to it', (t) async {
    await c.initialize();
    await c.edit('tenant');
    await render(t, false);
    await t.enterText(
      find.byKey(const ValueKey('settings-band_critical')),
      '10',
    );
    await t.pump();
    expect(find.text('Each band must be higher than the next.'), findsWidgets);
  });

  testWidgets('keyboard focus reaches every settings field', (t) async {
    await c.initialize();
    await c.edit('tenant');
    await render(t, false);
    final total = t.widgetList(find.byType(EditableText)).length;
    expect(total, greaterThanOrEqualTo(10));
    final reached = <FocusNode>{};
    for (var i = 0; i < 80; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      for (final e in t.widgetList<EditableText>(find.byType(EditableText))) {
        if (e.focusNode.hasFocus) reached.add(e.focusNode);
      }
    }
    expect(reached.length, total);
  });

  for (final dark in [false, true]) {
    testWidgets('audit settings ${dark ? 'dark' : 'light'} 200 percent', (
      t,
    ) async {
      gateway.tenantVersion = 2;
      gateway.effective = AssuranceSettings.fromJson({
        ...AssuranceSettings.defaults.toPayload('tenant'),
        'source': 'tenant',
        'due_soon_days': 5,
      });
      await c.initialize();
      await c.edit('tenant');
      c.field('escalate_after_days', '10');
      await render(t, dark);
      await expectLater(
        find.byType(AssuranceSettingsPanel),
        matchesGoldenFile(
          'goldens/audit_settings_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
}
