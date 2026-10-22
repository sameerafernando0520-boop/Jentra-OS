import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_planning_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_planning_screen.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'assurance_planning_test.dart' as fixtures;
import 'support/procurement_fakes.dart' show Keys;

void main() {
  late JentraLocalDatabase database;
  late fixtures.FakePlanningGateway gateway;
  late AssurancePlanningController controller;
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    gateway = fixtures.FakePlanningGateway();
    controller = AssurancePlanningController(
      scope: TenantContext(
        tenantId: fixtures.uid(90),
        actorId: fixtures.actor,
        legalEntityId: fixtures.uid(91),
        branchId: fixtures.uid(92),
      ),
      gateway: gateway,
      drafts: QuotationDraftStore(
        EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
      ),
      online: true,
      capabilities: const {'assurance.plan.manage', 'assurance.evidence.view'},
      people: fixtures.FakePeople(),
    );
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> start() async {
    await controller.initialize();
    await controller.startCommand('create_template', {
      'code': ' TREASURY ',
      'name': ' Treasury controls ',
      'controls': [
        {
          'control_code': ' TRS-SIGN ',
          'title': ' Dual signatories ',
          'risk': 'high',
        },
      ],
      'requests': [
        {
          'control_code': ' TRS-SIGN ',
          'description': ' Current bank mandate ',
          'due_offset_days': '14',
        },
      ],
    });
  }

  test(
    'template fields produce the existing exact command with whole day offsets',
    () async {
      await start();
      await controller.submit();
      expect(controller.error, isNull);
      final command = gateway.commands.single;
      expect(command.expectedEntityVersion, 0);
      expect(command.payload, {
        'action': 'create_template',
        'template_id': isA<String>(),
        'code': 'TREASURY',
        'name': 'Treasury controls',
        'controls': [
          {
            'control_code': 'TRS-SIGN',
            'title': 'Dual signatories',
            'risk': 'high',
          },
        ],
        'requests': [
          {
            'control_code': 'TRS-SIGN',
            'description': 'Current bank mandate',
            'due_offset_days': 14,
          },
        ],
      });
    },
  );

  test(
    'renaming and removing controls keeps request references consistent',
    () async {
      await start();
      controller.templateControlField(0, 'control_code', 'TRS-NEW');
      expect(controller.templateRequests.single['control_code'], 'TRS-NEW');
      controller.removeTemplateControl(0);
      expect(controller.templateRequests, isEmpty);
      await controller.submit();
      expect(gateway.commands, isEmpty);
      expect(controller.error, contains('template'));
    },
  );

  test(
    'invalid request offsets are rejected before a command is sealed',
    () async {
      await start();
      controller.templateRequestField(0, 'due_offset_days', '14.5');
      await controller.submit();
      expect(gateway.commands, isEmpty);
      expect(controller.pending, isFalse);
      expect(controller.error, contains('template'));
    },
  );

  test('uncertain template saves retry the same immutable command', () async {
    await start();
    gateway.failure = 'UNCERTAIN_RESULT';
    await controller.submit();
    final first = gateway.commands.single;
    expect(controller.pending, isTrue);
    controller.templateControlField(0, 'title', 'Changed after sending');
    expect(controller.templateControls.single['title'], ' Dual signatories ');
    gateway.failure = null;
    await controller.submit();
    expect(gateway.commands.last.commandId, first.commandId);
    expect(gateway.commands.last.payload, first.payload);
  });

  test(
    'template definitions are retained immutably for creating a new version',
    () {
      final definition = {
        'items': [],
        'templates': [
          {
            'id': fixtures.uid(30),
            'code': 'TREASURY',
            'version': 1,
            'name': 'Treasury controls',
            'controls': [
              {
                'control_code': 'TRS-SIGN',
                'title': 'Dual signatories',
                'risk': 'high',
              },
            ],
            'requests': <Object?>[],
          },
        ],
      };
      final universe = AssuranceUniverse.fromJson(definition);
      final saved = universe.definitions[fixtures.uid(30)]!;
      expect(saved.controls.single['title'], 'Dual signatories');
      expect(
        () => saved.controls.single['title'] = 'Changed',
        throwsUnsupportedError,
      );
      (definition['templates'] as List).single['controls'] = [];
      expect(
        () => AssuranceUniverse.fromJson(definition),
        throwsFormatException,
      );
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'template authoring is usable at 200 percent in ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(start);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: AssurancePlanning(controller: controller)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Create engagement template'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('template-control-title-0')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('template-control-title-0')),
          'Independent signatories',
        );
        expect(
          controller.templateControls.single['title'],
          'Independent signatories',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('template-request-days-0')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('JSON'), findsNothing);
      },
    );
  }
}
