import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/finance_opening/finance_opening_controller.dart';
import 'package:jentra_desktop/src/features/finance_opening/finance_opening_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/finance_opening.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'support/procurement_fakes.dart' show Keys;

const scope = TenantContext(
  tenantId: 'tenant',
  legalEntityId: 'entity',
  branchId: 'branch',
  actorId: 'reviewer',
);
const permissions = {
  'finance.openings.view',
  'finance.openings.prepare',
  'finance.openings.approve',
  'finance.openings.post',
  'finance.openings.reverse',
};

Map<String, Object?> batch({
  String status = 'pending_approval',
  String actor = 'maker',
}) => {
  'id': 'batch-id',
  'version': 2,
  'status': status,
  'kind': 'AR',
  'source_system': 'Legacy ledger',
  'cutoff_date': '2026-10-31',
  'currency_code': 'LKR',
  'base_currency_code': 'LKR',
  'prepared_by': actor,
  'submitted_by': actor,
  'totals': {
    'row_count': 1,
    'outstanding_amount': '123.450001',
    'carrying_base_amount': '123.450001',
  },
  'lines': <Object?>[],
};

class OpeningGateway implements FinanceOpeningGateway {
  final requests = <Map<String, Object?>>[];
  final verbs = <String>[];
  Map<String, Object?> selected = batch();
  Map<String, Object?>? previewPayload;
  Map<String, Object?> previewResult = {'valid': true, 'issues': <Object?>[]};
  Completer<Map<String, Object?>>? delayedPreview;
  FinanceOpeningFailure? writeFailure;

  @override
  Future<Map<String, Object?>> batches(
    TenantContext scope, {
    String? after,
  }) async => {
    'items': [selected],
    'next_cursor': null,
  };

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async =>
      selected;

  @override
  Future<Map<String, Object?>> source(TenantContext scope, String id) async =>
      selected;

  @override
  Future<Map<String, Object?>> reversal(TenantContext scope, String id) async =>
      (selected['reversal']! as Map).cast<String, Object?>();

  @override
  Future<Map<String, Object?>> reversals(
    TenantContext scope,
    String batchId, {
    String? after,
  }) async => {
    'items': [if (selected['reversal'] case final Map value) value],
    'next_cursor': null,
  };

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope, {
    required String kind,
    required String currencyCode,
    required String resource,
    String? after,
  }) async => {
    'items': <Object?>[],
    'base_currency_code': 'LKR',
    'next_cursor': null,
  };

  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) async {
    previewPayload = payload;
    return delayedPreview == null
        ? previewResult
        : await delayedPreview!.future;
  }

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    verbs.add(verb);
    requests.add(command.toJson((value) => value));
    if (writeFailure case final failure?) throw failure;
    final id = command.payload['id'] ?? command.payload['document_id'];
    if (verb.endsWith('_reversal')) {
      final old = (selected['reversal'] as Map?)?.cast<String, Object?>();
      final reversal = <String, Object?>{
        ...?old,
        'id': id,
        'batch_id': selected['id'],
        'version': (command.expectedEntityVersion ?? 0) + 1,
        'status': switch (command.payload['action'] ?? verb) {
          'approve' => 'approved',
          'reject' => 'rejected',
          'cancel' => 'cancelled',
          'post_reversal' => 'posted',
          _ => 'pending_approval',
        },
        if (verb == 'request_reversal') ...{
          'created_by': command.context.actorId,
          'posting_date': command.payload['posting_date'],
          'reason': command.payload['reason'],
        },
      };
      selected = {
        ...selected,
        'reversal_supported': true,
        'reversal': reversal,
      };
      return {'entity': reversal};
    }
    final status = switch (command.payload['action'] ?? verb) {
      'submit' => 'pending_approval',
      'approve' => 'approved',
      'post' => 'posted',
      _ => 'draft',
    };
    selected = {
      ...batch(
        status: status,
        actor: verb == 'save'
            ? command.context.actorId
            : selected['prepared_by']! as String,
      ),
      'id': id,
      'version': (command.expectedEntityVersion ?? 0) + 1,
    };
    return {'entity': selected};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late OpeningGateway gateway;
  late FinanceOpeningController controller;

  FinanceOpeningController create({
    Set<String> capabilities = permissions,
    TenantContext context = scope,
  }) => FinanceOpeningController(
    scope: context,
    gateway: gateway,
    drafts: drafts,
    permissions: capabilities,
    online: true,
  );

  setUp(() async {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.financeOpenings(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = OpeningGateway();
    controller = create();
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> loadPreview() async {
    controller.startNew();
    controller.updateField('source_system', 'Legacy ledger');
    controller.updateField('cutoff_date', '2026-10-31');
    controller.selectOption('currencies', {
      'id': 'LKR',
      'code': 'LKR',
    }, baseCurrencyCode: 'LKR');
    controller.selectOption('control_accounts', {
      'id': 'ar-control',
      'code': '1100',
    });
    controller.selectOption('clearing_accounts', {
      'id': 'opening-clearing',
      'code': '3005',
    });
    await controller.previewFile(
      SelectedSetupFile(
        name: 'unpaid.csv',
        extension: 'csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'external_document_key,party_code,document_number,document_date,due_date,currency,outstanding_amount,carrying_base_amount\n'
            'legacy-17,C001,INV-17,2026-10-01,2026-11-07,LKR,123.450001,123.450001\n',
          ),
        ),
      ),
    );
  }

  test('valid local file reaches server preview and uncertain save retries the exact envelope after reopen', () async {
    await loadPreview();
    expect(
      controller.localPreview!.outstandingTotal!.toDecimalString(),
      '123.450001',
    );
    expect(
      (gateway.previewPayload!['lines'] as List).single,
      containsPair('external_document_key', 'legacy-17'),
    );
    expect(gateway.previewPayload!['file_sha256'], matches(r'^[a-f0-9]{64}$'));
    gateway.writeFailure = const FinanceOpeningFailure(
      'UNCONFIRMED',
      'Try again.',
      definite: false,
    );
    await controller.act('save');
    expect(controller.hasPending, isTrue);
    expect(gateway.requests, hasLength(1));

    controller.dispose();
    controller = create();
    await controller.initialize();
    expect(gateway.requests, hasLength(1));
    expect(controller.hasPending, isTrue);
    gateway.writeFailure = const FinanceOpeningFailure(
      'PERMISSION_DENIED',
      'Verify MFA before continuing.',
      definite: true,
    );
    await controller.retry();
    expect(controller.hasPending, isTrue);
    expect(controller.accessDenied, isTrue);

    await controller.refresh();
    gateway.writeFailure = null;
    await controller.retry();
    expect(gateway.requests, List.filled(3, gateway.requests.first));
    expect(controller.hasPending, isFalse);
    expect(controller.document?['status'], 'draft');
  });

  test(
    'preparer and independent approver advance the same opening batch',
    () async {
      await loadPreview();
      await controller.act('save');
      final id = controller.document!['id']! as String;
      expect(controller.document?['status'], 'draft');
      await controller.act('submit');
      expect(controller.document?['status'], 'pending_approval');
      expect(controller.canAct('approve'), isFalse);

      final approver = create(
        context: const TenantContext(
          tenantId: 'tenant',
          legalEntityId: 'entity',
          branchId: 'branch',
          actorId: 'independent-approver',
        ),
      );
      addTearDown(approver.dispose);
      await approver.initialize();
      await approver.openBatch(id);
      expect(approver.canAct('approve'), isTrue);
      await approver.act('approve');
      expect(approver.document?['status'], 'approved');

      await controller.refresh();
      expect(controller.canAct('post'), isTrue);
      await controller.act('post');
      expect(controller.document?['status'], 'posted');
      expect(controller.canAct('post'), isFalse);
      expect(gateway.verbs, ['save', 'transition', 'transition', 'post']);
      expect(
        gateway.requests.map((request) => request['expected_entity_version']),
        [0, 1, 2, 3],
      );
    },
  );

  test('scope epoch change discards a late file validation result', () async {
    gateway.delayedPreview = Completer<Map<String, Object?>>();
    final work = loadPreview();
    while (gateway.previewPayload == null) {
      await Future<void>.delayed(Duration.zero);
    }
    controller.setOnline(false);
    controller.setOnline(true);
    gateway.delayedPreview!.complete({'valid': true, 'issues': <Object?>[]});
    await work;
    expect(controller.localPreview, isNull);
    expect(controller.serverPreview, isNull);
    await controller.act('save');
    expect(gateway.requests, isEmpty);
  });

  test('server row issues prevent draft save', () async {
    gateway.previewResult = {
      'valid': false,
      'issues': [
        {
          'row': 2,
          'field': 'external_document_key',
          'message': 'Already imported.',
        },
      ],
    };
    await loadPreview();
    expect(controller.serverPreview?['valid'], isFalse);
    await controller.act('save');
    expect(gateway.requests, isEmpty);
  });

  test('a rejected save invalidates the previous successful preview', () async {
    await loadPreview();
    gateway.writeFailure = const FinanceOpeningFailure(
      'OPENING_VALIDATION_FAILED',
      'Check updated row issues.',
      definite: true,
      issues: [
        {'row': 2, 'field': 'party_code', 'message': 'Customer is inactive.'},
      ],
    );
    await controller.act('save');
    expect(controller.hasPending, isFalse);
    expect(controller.canAct('save'), isFalse);
    expect(controller.serverPreview?['valid'], isFalse);
    expect(openingRows(controller.serverPreview?['issues']).single['row'], 2);
  });

  test(
    'opening reversal survives uncertain request and a busy replay',
    () async {
      gateway.selected = {
        ...batch(status: 'posted'),
        'reversal_supported': true,
      };
      await controller.openBatch('batch-id');
      gateway.writeFailure = const FinanceOpeningFailure(
        'UNCERTAIN_RESULT',
        'Retry saved request.',
        definite: false,
      );
      await controller.requestReversal(
        postingDate: '2026-11-01',
        reason: 'Wrong legacy amount',
      );
      expect(controller.hasPending, isTrue);
      final request = gateway.requests.single;
      expect(gateway.verbs.single, 'request_reversal');
      expect((request['payload'] as Map)['document_id'], 'batch-id');
      controller.dispose();
      controller = create();
      await controller.initialize();
      gateway.writeFailure = const FinanceOpeningFailure(
        'OPENING_REVERSAL_BUSY',
        'Another action is running.',
        definite: true,
      );
      await controller.retry();
      expect(controller.hasPending, isTrue);
      gateway.writeFailure = null;
      await controller.retry();
      expect(controller.hasPending, isFalse);
      expect(controller.document!['status'], 'posted');
      expect(controller.reversal!['status'], 'pending_approval');
      expect(gateway.requests, everyElement(equals(request)));
    },
  );

  test(
    'reversal review excludes its requester and every original preparer',
    () async {
      final request = <String, Object?>{
        'id': 'reversal',
        'batch_id': 'batch-id',
        'version': 1,
        'status': 'pending_approval',
        'created_by': 'requester',
        'posting_date': '2026-11-01',
        'reason': 'Wrong legacy amount',
      };
      gateway.selected = {
        ...batch(status: 'posted'),
        'reversal_supported': true,
        'preparer_ids': ['prior-maker', scope.actorId],
        'reversal': request,
      };
      await controller.openBatch('batch-id');
      expect(controller.canActReversal('approve'), isFalse);
      await controller.actReversal('approve');
      expect(gateway.requests, isEmpty);
      gateway.selected = {
        ...gateway.selected,
        'preparer_ids': ['maker'],
        'reversal': {...request, 'created_by': scope.actorId},
      };
      await controller.openBatch('batch-id');
      expect(controller.canActReversal('approve'), isFalse);

      gateway.selected = {...gateway.selected, 'reversal': request};
      await controller.openBatch('batch-id');
      expect(controller.canActReversal('approve'), isTrue);
      await controller.actReversal('approve');
      expect(controller.reversal!['status'], 'approved');
      expect(controller.canActReversal('post'), isTrue);
      await controller.actReversal('post');
      expect(controller.reversal!['status'], 'posted');
      expect(controller.canRequestReversal, isFalse);
      expect(gateway.verbs, ['transition_reversal', 'post_reversal']);
    },
  );

  test(
    'original posting permission does not permit reversal posting',
    () async {
      gateway.selected = {
        ...batch(status: 'posted'),
        'reversal_supported': true,
        'reversal': <String, Object?>{
          'id': 'reversal',
          'batch_id': 'batch-id',
          'version': 2,
          'status': 'approved',
          'created_by': 'requester',
        },
      };
      controller.dispose();
      controller = create(
        capabilities: permissions.difference({'finance.openings.reverse'}),
      );
      await controller.initialize();
      await controller.openBatch('batch-id');
      expect(controller.canActReversal('post'), isFalse);
      await controller.actReversal('post');
      expect(gateway.requests, isEmpty);
    },
  );

  test(
    'legacy backend and invalid reversal input cannot send a request',
    () async {
      gateway.selected = batch(status: 'posted');
      await controller.openBatch('batch-id');
      expect(controller.canRequestReversal, isFalse);
      gateway.selected = {...gateway.selected, 'reversal_supported': true};
      await controller.openBatch('batch-id');
      await controller.requestReversal(
        postingDate: '2026-02-30',
        reason: 'Wrong amount',
      );
      expect(gateway.requests, isEmpty);
      await controller.requestReversal(
        postingDate: '2026-10-30',
        reason: 'Wrong amount',
      );
      expect(gateway.requests, isEmpty);
      await controller.requestReversal(postingDate: '2026-11-01', reason: '  ');
      expect(gateway.requests, isEmpty);
    },
  );

  test(
    'finance reversal verbs stay outside ordinary quotation drafts',
    () async {
      final ordinary = QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      );
      await expectLater(
        ordinary.prepare(
          scope,
          'ordinary',
          verb: 'request_reversal',
          payload: {'id': 'reversal'},
        ),
        throwsA(
          isA<DomainError>().having(
            (error) => error.code,
            'code',
            'VALIDATION_ERROR',
          ),
        ),
      );
    },
  );

  testWidgets(
    'reversal review shows the original request at 200 percent and hides maker approval',
    (tester) async {
      tester.view.physicalSize = const Size(960, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final request = <String, Object?>{
        'id': 'reversal',
        'batch_id': 'batch-id',
        'version': 1,
        'status': 'pending_approval',
        'created_by': 'requester',
        'posting_date': '2026-11-01',
        'reason': 'Wrong legacy amount',
      };
      gateway.selected = {
        ...batch(status: 'posted'),
        'reversal_supported': true,
        'preparer_ids': ['maker', scope.actorId],
        'reversal': request,
      };
      await tester.runAsync(() => controller.openBatch('batch-id'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FinanceOpeningWorkspace(controller: controller)),
        ),
      );
      expect(find.text('Approve reversal'), findsNothing);
      expect(find.text('Reason · Wrong legacy amount'), findsOneWidget);
      expect(find.text('Posting date · 2026-11-01'), findsOneWidget);
      gateway.selected = {
        ...gateway.selected,
        'preparer_ids': ['maker'],
      };
      await tester.runAsync(() => controller.openBatch('batch-id'));
      await tester.pumpAndSettle();
      final approve = find.text('Approve reversal');
      await tester.ensureVisible(approve);
      expect(approve.hitTestable(), findsOneWidget);
      expect(find.text('Post reversal'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'approval is independently authorized and reachable at 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(960, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.runAsync(() async {
        gateway.selected = batch(actor: scope.actorId);
        await controller.openBatch('batch-id');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FinanceOpeningWorkspace(controller: controller)),
        ),
      );
      expect(find.text('Approve batch'), findsNothing);

      await tester.runAsync(() async {
        gateway.selected = {
          ...batch(),
          'preparer_ids': ['maker', scope.actorId],
        };
        await controller.openBatch('batch-id');
      });
      await tester.pumpAndSettle();
      expect(find.text('Approve batch'), findsNothing);
      expect(find.text('Return to preparer'), findsNothing);

      await tester.runAsync(() async {
        gateway.selected = batch();
        await controller.openBatch('batch-id');
      });
      await tester.pumpAndSettle();
      final approve = find.text('Approve batch');
      await tester.ensureVisible(approve);
      expect(approve.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
