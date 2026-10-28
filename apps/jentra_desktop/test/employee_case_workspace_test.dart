import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_desktop/src/features/people/employee_case_controller.dart';
import 'package:jentra_desktop/src/features/people/employee_case_screen.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const employee = '20000000-0000-0000-0000-000000000001';
const caseId = '30000000-0000-0000-0000-000000000001';
const documentId = '40000000-0000-0000-0000-000000000001';
const caps = {
  'people.view',
  'people.cases.manage',
  'people.hr.documents.view',
  'people.hr.documents.publish',
};
Map<String, Object?> get envelope => {
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
};

class Cases implements EmployeeCaseRepository {
  int version = 1, publicationVersion = 0, writes = 0;
  String status = 'open';
  String? owner, readFailure, commandFailure;
  bool loseCaseAck = false, losePublicationAck = false, crossScope = false;
  bool visible = false;
  bool ownerAvailable = false;
  String? label;
  Completer<Map<String, Object?>>? detailGate;
  final commands = <Map<String, Object?>>[];
  final publications = <Map<String, Object?>>[];
  final receipts = <String, Map<String, Object?>>{};
  final messages = <Map<String, Object?>>[];

  Map<String, Object?> get summary => {
    'id': caseId,
    'employee_id': employee,
    'version': version,
    'category': 'general',
    'subject': 'SYNTHETIC_PRIVATE_ENQUIRY',
    'status': status,
    'owner_user_id': owner,
    'owner_available': ownerAvailable,
    'payslip_id': null,
    'payslip_revision_id': null,
    'created_at': '2026-10-25T06:00:00Z',
    'updated_at': '2026-10-25T06:00:00Z',
  };
  void access() {
    if (readFailure != null) throw DomainError(code: readFailure!, message: '');
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope, {
    String? after,
  }) async {
    access();
    return {
      'items': [summary],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async {
    access();
    if (detailGate != null) return detailGate!.future;
    return {
      ...summary,
      'messages': [...messages],
      'history': <Object>[],
    };
  }

  @override
  Future<Map<String, Object?>> owners(
    TenantContext scope, {
    String? after,
  }) async {
    access();
    return {
      ...envelope,
      'items': [
        {
          'id': '60000000-0000-0000-0000-000000000001',
          'user_id': '10000000-0000-0000-0000-000000000005',
          'label': 'Synthetic HR colleague',
        },
      ],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>> command(
    TenantContext scope,
    Map<String, Object?> request,
  ) async {
    commands.add(Map.of(request));
    if (commandFailure != null) {
      throw DomainError(code: commandFailure!, message: '');
    }
    final id = request['p_command_id']! as String;
    if (receipts[id] case final cached?) return Map.of(cached);
    writes++;
    version++;
    switch (request['p_action']) {
      case 'claim':
        owner = scope.actorId;
        ownerAvailable = true;
        if (status != 'resolved') status = 'in_progress';
      case 'assign':
        owner = request['p_owner_user_id'] as String;
      case 'resolve':
        status = 'resolved';
      case 'close':
        status = 'closed';
      case 'reply':
        messages.add({
          'id': '50000000-0000-0000-0000-000000000001',
          'body': request['p_body'],
          'author_kind': 'hr',
          'created_at': '2026-10-25T06:01:00Z',
        });
    }
    final response = {
      ...envelope,
      'employee_id': employee,
      'id': caseId,
      'version': version,
      'status': status,
      'command_id': id,
    };
    receipts[id] = response;
    if (loseCaseAck) {
      loseCaseAck = false;
      throw TimeoutException('Synthetic lost acknowledgement');
    }
    return response;
  }

  @override
  Future<Map<String, Object?>> publication(
    TenantContext scope,
    String id,
  ) async {
    access();
    return {
      ...envelope,
      if (crossScope) 'branch_id': '10000000-0000-0000-0000-000000000099',
      'document_id': documentId,
      'document_version': 3,
      'publication_version': publicationVersion,
      'visible': visible,
      'label': label,
    };
  }

  @override
  Future<Map<String, Object?>> publish(
    TenantContext scope,
    Map<String, Object?> request,
  ) async {
    publications.add(Map.of(request));
    final id = request['p_command_id']! as String;
    if (receipts[id] case final cached?) return Map.of(cached);
    publicationVersion++;
    visible = request['p_visible']! as bool;
    label = request['p_label'] as String?;
    final response = {
      ...envelope,
      'id': documentId,
      'version': publicationVersion,
      'document_version': 3,
      'visible': visible,
      'command_id': id,
    };
    receipts[id] = response;
    if (losePublicationAck) {
      losePublicationAck = false;
      throw TimeoutException('Synthetic lost acknowledgement');
    }
    return response;
  }
}

void main() {
  late Cases repository;
  late EmployeeCaseController controller;
  setUp(() {
    repository = Cases();
    controller = EmployeeCaseController(
      scope: scope,
      repository: repository,
      permissions: caps,
      online: true,
      monitor: false,
    );
  });
  tearDown(() => controller.dispose());

  test('lost staff acknowledgement retries the sealed command once', () async {
    await controller.initialize();
    await controller.open(caseId);
    repository.loseCaseAck = true;
    await controller.act('claim');
    final sealed = Map.of(controller.pendingCase!);
    expect(controller.locked, isTrue);
    await controller.act('resolve');
    expect(repository.commands, hasLength(1));
    await controller.retryCase();
    expect(repository.commands.last, sealed);
    expect(repository.writes, 1);
    expect(controller.pendingCase, isNull);
    expect(controller.isOwner, isTrue);
    expect(controller.selected!['version'], 2);
  });

  test('conflict requires an explicit reload instead of rebasing', () async {
    await controller.open(caseId);
    repository.commandFailure = 'VERSION_CONFLICT';
    await controller.act('claim');
    expect(controller.conflict, isTrue);
    expect(controller.selected, isNull);
    expect(controller.pendingCase, isNull);
    repository.commandFailure = null;
    await controller.refresh();
    await controller.open(caseId);
    expect(controller.conflict, isFalse);
  });

  test('an active colleague remains the accountable owner', () async {
    repository.owner = '10000000-0000-0000-0000-000000000005';
    repository.ownerAvailable = true;
    await controller.open(caseId);
    await controller.act('claim');
    expect(repository.commands, isEmpty);
    expect(controller.selected, isNull);
    expect(controller.error, contains('accountable owner'));
  });

  test(
    'revoked owner can be replaced while a resolved enquiry stays resolved',
    () async {
      repository.owner = '10000000-0000-0000-0000-000000000005';
      repository.status = 'resolved';
      await controller.open(caseId);
      await controller.act('claim');
      expect(controller.isOwner, isTrue);
      expect(controller.selected!['status'], 'resolved');
      final owners = await controller.ownerChoices();
      expect(owners.$1.single['label'], 'Synthetic HR colleague');
      await controller.act(
        'assign',
        ownerUserId: owners.$1.single['user_id']! as String,
      );
      expect(repository.commands.last['p_action'], 'assign');
    },
  );

  test(
    'publication reads and acknowledgements bind exact document and scope',
    () async {
      await controller.openPublication(documentId, 3);
      expect(controller.publication!['publication_version'], 0);
      repository.losePublicationAck = true;
      await controller.setPublication(
        visible: true,
        label: 'Employment letter',
      );
      final sealed = Map.of(controller.pendingPublication!);
      await controller.retryPublication();
      expect(repository.publications.last, sealed);
      expect(repository.publicationVersion, 1);
      expect(controller.publication!['visible'], isTrue);
      expect(controller.pendingPublication, isNull);
      await controller.setPublication(visible: false);
      expect(controller.publication!['visible'], isFalse);
      expect(controller.publication!['label'], isNull);
      repository.crossScope = true;
      await controller.reloadPublication();
      expect(controller.publication, isNull);
      expect(controller.error, contains('could not be verified'));
    },
  );

  test('scope loss discards delayed private read and pending bodies', () async {
    repository.detailGate = Completer();
    final load = controller.open(caseId);
    controller.setOnline(false);
    repository.detailGate!.complete({
      ...repository.summary,
      'messages': <Object>[],
      'history': <Object>[],
    });
    await load;
    expect(controller.selected, isNull);
    expect(controller.rows, isEmpty);
    controller.setOnline(true);
    repository.detailGate = null;
    await controller.open(caseId);
    repository.loseCaseAck = true;
    await controller.act('claim');
    repository.readFailure = 'MFA_REQUIRED';
    await controller.checkAccess();
    expect(controller.denied, isTrue);
    expect(controller.pendingCase, isNull);
    expect(controller.selected, isNull);
  });

  test('background access checks never rebase a document title edit', () async {
    await controller.openPublication(documentId, 3);
    repository.publicationVersion = 1;
    repository.visible = true;
    repository.label = 'Title changed by another HR publisher';
    await controller.checkAccess();
    expect(controller.conflict, isTrue);
    expect(controller.publication, isNull);
    await controller.setPublication(visible: true, label: 'Old unsaved title');
    expect(repository.publications, isEmpty);
    await controller.reloadPublication();
    expect(controller.conflict, isFalse);
    expect(controller.publication!['label'], repository.label);
  });

  testWidgets('staff claims and replies through the actual enquiry screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EmployeeCaseWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('SYNTHETIC_PRIVATE_ENQUIRY'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Claim enquiry'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Claim enquiry'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('employee-case-reply')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('employee-case-reply')),
      'SYNTHETIC_PRIVATE_REPLY',
    );
    await tester.ensureVisible(find.text('Send reply'));
    await tester.tap(find.text('Send reply'));
    await tester.pumpAndSettle();
    expect(repository.commands.map((r) => r['p_action']), ['claim', 'reply']);
    expect(repository.messages.single['body'], 'SYNTHETIC_PRIVATE_REPLY');
    controller.setOnline(false);
    await tester.pumpAndSettle();
    expect(find.text('SYNTHETIC_PRIVATE_REPLY'), findsNothing);
    expect(find.text('SYNTHETIC_PRIVATE_ENQUIRY'), findsNothing);
  });

  testWidgets('document publisher uses fetched versions at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: EmployeeDocumentPublicationWorkspace(
            controller: controller,
            documentId: documentId,
            documentVersion: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('employee-document-label')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('employee-document-label')),
      'Employment letter',
    );
    await tester.ensureVisible(find.text('Share with employee'));
    await tester.tap(find.text('Share with employee'));
    await tester.pumpAndSettle();
    expect(repository.publications.single['p_expected_version'], 0);
    expect(repository.publications.single['p_document_version'], 3);
    expect(repository.publications.single['p_label'], 'Employment letter');
    expect(tester.takeException(), isNull);
  });
}
