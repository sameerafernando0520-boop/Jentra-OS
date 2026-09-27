import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_desktop/src/features/people/calendar_resolution_dialog.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const versionId = '20000000-0000-0000-0000-000000000001';
final version = CalendarVersionDetail.fromJson({
  'id': versionId,
  'calendar_id': '30000000-0000-0000-0000-000000000001',
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'start_date': '2026-01-01',
  'end_date_exclusive': '2027-01-01',
  'timezone': 'America/New_York',
  'published_by': scope.actorId,
  'published_at': '2026-01-01T00:00:00Z',
  'weekly_intervals': [],
  'date_overrides': [],
});

class Resolver implements CalendarInstantResolver {
  bool gap = false;
  Completer<void>? gate;
  @override
  Future<CalendarLocalResolution> localCandidates(
    TenantContext scope,
    CalendarVersionDetail version,
    CivilDate date,
    int minute,
  ) async {
    await gate?.future;
    return CalendarLocalResolution.fromJson({
      'calendar_version_id': versionId,
      'date': date.value,
      'minute': minute,
      'timezone': 'America/New_York',
      'local_datetime': '${date.value}T01:30:00',
      'algorithm': 'pg-iana-roundtrip-v1',
      'candidates': gap
          ? []
          : [
              {'utc': '${date.value}T05:30:00Z', 'offset_seconds': -14400},
              {'utc': '${date.value}T06:30:00Z', 'offset_seconds': -18000},
            ],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  late Resolver resolver;
  var current = true;
  setUp(() {
    resolver = Resolver();
    current = true;
  });
  Widget app({bool dark = false, double scale = 1}) => MaterialApp(
    theme: dark ? JentraTheme.dark() : JentraTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: RepaintBoundary(
          key: const Key('resolution-preview'),
          child: CalendarResolutionDialog(
            resolver: resolver,
            scope: scope,
            version: version,
            isCurrent: () => current,
          ),
        ),
      ),
    ),
  );
  Future<void> enter(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '2026-11-01');
    await tester.enterText(find.byType(TextField).last, '01:30');
    await tester.tap(find.text('Resolve time'));
    await tester.pumpAndSettle();
  }

  testWidgets('AC-405 fold requires a deliberate offset selection', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await enter(tester);
    expect(find.textContaining('occurs twice'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    await tester.tap(find.textContaining('-18000 offset seconds'));
    await tester.pump();
    expect(find.textContaining('UTC 2026-11-01T06:30:00.000Z'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '01:31');
    await tester.pump();
    expect(find.byType(SelectableText), findsNothing);
  });
  testWidgets('AC-405 gap exposes a correction without an instant', (
    tester,
  ) async {
    resolver.gap = true;
    await tester.pumpWidget(app());
    await enter(tester);
    expect(find.textContaining('does not exist'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });
  testWidgets('AC-401 access loss hides current and in-flight evidence', (
    tester,
  ) async {
    resolver.gate = Completer<void>();
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField).first, '2026-11-01');
    await tester.enterText(find.byType(TextField).last, '01:30');
    await tester.tap(find.text('Resolve time'));
    await tester.pump();
    current = false;
    await tester.pumpWidget(app());
    expect(find.text('Calendar access changed'), findsOneWidget);
    resolver.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
    expect(find.textContaining('-18000'), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'AC-419 ${dark ? 'dark' : 'light'} resolution preview at 200 percent',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(app(dark: dark, scale: 2));
        await enter(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Resolve time').hitTestable(), findsOneWidget);
        expect(find.text('Close').hitTestable(), findsOneWidget);
        await expectLater(
          find.byKey(const Key('resolution-preview')),
          matchesGoldenFile(
            'goldens/calendar_resolution_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.ensureVisible(
          find.textContaining('-18000 offset seconds'),
        );
        await tester.tap(find.textContaining('-18000 offset seconds'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(SelectableText));
        expect(find.byType(SelectableText).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
