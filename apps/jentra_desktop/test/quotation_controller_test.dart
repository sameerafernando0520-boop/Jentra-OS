import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

const scope = TenantContext(
  tenantId: 'tenant',
  actorId: 'actor',
  legalEntityId: 'entity',
  branchId: 'branch',
);
const quoteId = '00000000-0000-4000-8000-000000000001';
const nextId = '00000000-0000-4000-8000-000000000002';
const permissions = {
  'sales.quotations.view',
  'sales.quotations.manage',
  'workflow.approvals.decide',
};

void main() {
  late JentraLocalDatabase database;
  late QuotationDraftStore store;
  late FakeQuotations repository;
  late ProviderContainer container;
  var liveCapabilities = permissions;

  Future<QuotationWorkspaceController> start({
    Set<String> capabilities = permissions,
    ConnectivityState connectivity = ConnectivityState.online,
  }) async {
    liveCapabilities = capabilities;
    container = ProviderContainer(
      retry: (count, error) => null,
      overrides: [
        activeTenantContextProvider.overrideWithValue(scope),
        businessCapabilitiesProvider.overrideWith(
          (ref) async => liveCapabilities,
        ),
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(connectivity),
        ),
        quotationWorkspaceRepositoryProvider.overrideWithValue(repository),
        leadToCashRepositoryProvider.overrideWithValue(repository),
        quotationDraftStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    container.listen(quotationWorkspaceProvider, (_, next) {});
    await container.read(quotationWorkspaceProvider.future);
    return container.read(quotationWorkspaceProvider.notifier);
  }

  QuotationWorkspaceState value() =>
      container.read(quotationWorkspaceProvider).requireValue;

  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: MemoryKeys())),
    );
    repository = FakeQuotations();
  });
  tearDown(() => database.close());

  test('AC-303 denies quotation reads without quotation capability', () async {
    await expectLater(
      start(capabilities: {'workflow.approvals.decide'}),
      throwsA(isA<DomainError>()),
    );
    expect(repository.queries, isEmpty);
  });

  test(
    'AC-303 literal search and keyset pagination retain active filters',
    () async {
      final controller = await start();
      repository.page = CursorPage(
        items: [quotation()],
        limit: 50,
        nextCursor: quoteId,
      );
      await controller.search('  QUO%_  ', status: 'draft');
      repository.page = CursorPage(items: [quotation(id: nextId)], limit: 50);
      await controller.loadMore();
      expect(repository.queries.last.search, 'QUO%_');
      expect(repository.queries.last.status, 'draft');
      expect(repository.queries.last.cursor, quoteId);
      expect(value().page.items.map((q) => q.id), [quoteId, nextId]);
      expect(value().page.hasNextPage, false);
    },
  );

  test('AC-303 exact draft is persisted before transport and cleared only on confirmed success', () async {
    final controller = await start();
    await controller.newDraft();
    await controller.updateForm(form());
    repository.onCommand = (wire) async {
      final saved = await store.load(scope, 'new');
      expect(saved!.pending!.envelope.toJson((x) => x), wire);
      expect((wire['payload'] as Map)['exchange_rate'], '1.0000000000');
      expect(
        ((wire['payload'] as Map)['lines'] as List).first['unit_price'],
        '90071992547409.123456',
      );
      return CommandResult.success(
        requestId: 'server-request',
        entity: quotation(),
      );
    };
    await controller.save();
    expect(repository.commands, hasLength(1));
    expect(await store.load(scope, 'new'), isNull);
    expect(value().detail!.quotation.id, quoteId);
    expect(value().error, isNull);
  });

  test('AC-303 unknown outcome survives restart and retries the identical entire envelope', () async {
    var controller = await start();
    await controller.newDraft();
    await controller.updateForm(form());
    repository.onCommand = (wire) async => throw TimeoutException('uncertain');
    await controller.save();
    final first = repository.commands.single;
    expect(value().pending, isNotNull);
    expect(value().form, form());
    controller = await start();
    await controller.newDraft();
    expect(value().recovered, true);
    expect(value().pending, isNotNull);
    await controller.updateForm(form()..['notes'] = 'cannot replace pending');
    expect(value().form, form());
    repository.onCommand = (wire) async =>
        CommandResult.success(requestId: 'confirmed', entity: quotation());
    await controller.retryPending();
    expect(repository.commands.last, first);
    expect(await store.load(scope, 'new'), isNull);
  });

  test('AC-303 confirmed rejection preserves editable raw draft with no pending envelope', () async {
    final controller = await start();
    await controller.newDraft();
    await controller.updateForm(form());
    repository.onCommand = (wire) async => CommandResult.failure(
      requestId: 'denied',
      error: const DomainError(
        code: 'INVALID_REFERENCE',
        message: 'Customer inactive.',
      ),
    );
    await controller.save();
    expect(value().error!.code, 'INVALID_REFERENCE');
    expect(value().pending, isNull);
    expect(value().form, form());
    await controller.updateForm(form()..['notes'] = 'corrected');
    expect((await store.load(scope, 'new'))!.form['notes'], 'corrected');
  });

  test('AC-303 explicit version conflict keeps edits until server comparison resolution', () async {
    final controller = await start();
    await controller.selectQuotation(quoteId);
    await controller.updateForm({...value().form!, 'notes': 'local changes'});
    repository.onCommand = (wire) async => CommandResult.failure(
      requestId: 'stale',
      error: const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'Changed on server.',
      ),
    );
    await controller.save();
    expect(value().conflict, true);
    expect(value().form!['notes'], 'local changes');
    repository.detail = detail(version: 8, notes: 'remote changes');
    await controller.resolveConflict(keepLocal: true);
    expect(value().conflict, false);
    expect(value().form!['notes'], 'local changes');
    expect(value().localDraft!.expectedVersion, 8);
    expect(value().detail!.quotation.version, 8);
    expect(repository.commands, hasLength(1));
  });

  test('AC-303 offline editing is durable while writes and double submission are blocked', () async {
    final controller = await start(connectivity: ConnectivityState.offline);
    await controller.newDraft();
    await controller.updateForm(form());
    await controller.save();
    expect(repository.commands, isEmpty);
    expect(value().error!.code, 'OFFLINE_COMMAND_BLOCKED');
    expect((await store.load(scope, 'new'))!.form, form());
  });

  test('AC-303 double save sends only one persisted command', () async {
    final controller = await start();
    await controller.newDraft();
    await controller.updateForm(form());
    final response = Completer<CommandResult<SalesQuotation>>();
    repository.onCommand = (_) => response.future;
    final first = controller.save();
    await controller.save();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.commands, hasLength(1));
    response.complete(
      CommandResult.success(requestId: 'saved', entity: quotation()),
    );
    await first;
  });

  test('AC-303 new revision and lifecycle decisions retain expected version and reason', () async {
    repository.detail = detail(status: 'submitted');
    final controller = await start();
    await controller.selectQuotation(quoteId);
    await controller.startRevision('Revised delivery');
    expect(value().form!['create_revision'], true);
    expect(value().form!['revision_reason'], 'Revised delivery');
    expect(value().canEditForm, true);
    await controller.save();
    expect(
      (repository.commands.single['payload'] as Map)['revision_reason'],
      'Revised delivery',
    );
    expect(repository.commands.single['expected_entity_version'], 7);
    repository.detail = detail(status: 'pending_approval');
    await controller.selectQuotation(quoteId);
    await controller.decide(approve: false, reason: 'Revise delivery terms');
    expect(
      (repository.commands.last['payload'] as Map)['decision'],
      'rejected',
    );
    expect(
      (repository.commands.last['payload'] as Map)['note'],
      'Revise delivery terms',
    );
  });

  test(
    'AC-303 stale selection read cannot replace a newer selected quotation',
    () async {
      final controller = await start();
      final delayed = Completer<QuotationDetail?>();
      repository.detailRead = (id) =>
          id == quoteId ? delayed.future : Future.value(detail(id: id));
      final first = controller.selectQuotation(quoteId);
      await controller.selectQuotation(nextId);
      delayed.complete(detail());
      await first;
      expect(value().detail!.quotation.id, nextId);
      expect(value().form!['id'], nextId);
    },
  );

  test('AC-303 actor and scope switches ignore stale reads and never reveal old local drafts', () async {
    final controller = await start();
    final delayed = Completer<QuotationDetail?>();
    repository.detailRead = (_) => delayed.future;
    final oldRead = controller.selectQuotation(quoteId);
    container.updateOverrides([
      activeTenantContextProvider.overrideWithValue(
        scope.copyWith(actorId: 'other'),
      ),
      businessCapabilitiesProvider.overrideWith((ref) async => permissions),
      connectivityStateProvider.overrideWith(
        (ref) => Stream.value(ConnectivityState.online),
      ),
      quotationWorkspaceRepositoryProvider.overrideWithValue(repository),
      leadToCashRepositoryProvider.overrideWithValue(repository),
      quotationDraftStoreProvider.overrideWithValue(store),
    ]);
    await container.read(quotationWorkspaceProvider.future);
    delayed.complete(detail());
    await oldRead;
    expect(value().detail, isNull);
    expect(value().form, isNull);
    expect(value().context.actorId, 'other');
  });
  test('AC-303 confirmed success followed by failed refresh cannot create another new quotation', () async {
    final controller = await start();
    await controller.newDraft();
    await controller.updateForm(form());
    repository.onCommand = (_) async {
      repository.detailRead = (_) async =>
          throw TimeoutException('read failed');
      return CommandResult.success(requestId: 'saved', entity: quotation());
    };
    await controller.save();
    expect(await store.load(scope, 'new'), isNull);
    expect(value().form, isNull);
    expect(value().page.items.single.id, quoteId);
    await controller.save();
    expect(repository.commands, hasLength(1));
  });

  test('AC-303 conflict resolution uses the compared version even if remote changes again', () async {
    final controller = await start();
    await controller.selectQuotation(quoteId);
    await controller.updateForm({...value().form!, 'notes': 'local'});
    repository.onCommand = (_) async => CommandResult.failure(
      requestId: 'stale',
      error: const DomainError(code: 'VERSION_CONFLICT', message: 'stale'),
    );
    await controller.save();
    repository.detail = detail(version: 8);
    await controller.inspectConflict();
    repository.detail = detail(version: 9);
    await controller.resolveConflict(keepLocal: true);
    expect(value().localDraft!.expectedVersion, 8);
  });

  test('AC-303 live capability revocation hides in-flight result and retains exact retry authority', () async {
    final controller = await start();
    await controller.newDraft();
    await controller.updateForm(form());
    final result = Completer<CommandResult<SalesQuotation>>();
    repository.onCommand = (_) => result.future;
    final command = controller.save();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    liveCapabilities = <String>{};
    container.invalidate(businessCapabilitiesProvider);
    await container.read(businessCapabilitiesProvider.future);
    expect(
      container.read(businessCapabilitiesProvider).requireValue,
      isEmpty,
      reason: 'new capabilities must be visible before awaiting the workspace',
    );
    await container.pump();
    await expectLater(
      container.read(quotationWorkspaceProvider.future),
      throwsA(isA<DomainError>()),
    );
    result.complete(
      CommandResult.success(requestId: 'saved', entity: quotation()),
    );
    await command;
    expect(container.read(quotationWorkspaceProvider).hasError, true);
    expect(await store.load(scope, 'new'), isNull);
  });

  test(
    'AC-303 pending encryption immediately blocks submission of unsaved edits',
    () async {
      final controller = await start();
      await controller.selectQuotation(quoteId);
      final edited = controller.updateForm({
        ...value().form!,
        'notes': 'new local notes',
      });
      expect(value().allowedActions, isEmpty);
      await controller.transition('submit');
      await edited;
      expect(repository.commands, isEmpty);
    },
  );
  test('AC-303 failed encryption cannot lose edits when another quotation is opened', () async {
    final keys = MemoryKeys()..fail = true;
    store = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: keys)),
    );
    final controller = await start();
    await controller.selectQuotation(quoteId);
    final edit = controller.updateForm({
      ...value().form!,
      'notes': 'retain me',
    });
    await controller.selectQuotation(nextId);
    await edit;
    expect(value().form!['id'], quoteId);
    expect(value().form!['notes'], 'retain me');
    expect(value().error!.code, 'DRAFT_SAVE_FAILED');
    keys.fail = false;
    await controller.save();
    expect(repository.commands, hasLength(1));
  });
}

class MemoryKeys implements SecretKeyStore {
  bool fail = false;
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('Key store unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Map<String, Object?> form({String? id}) => {
  'id': ?id,
  'customer_id': 'customer',
  'quotation_date': '2026-09-06',
  'valid_until': '2099-10-06',
  'currency_code': 'LKR',
  'exchange_rate': '1.0000000000',
  'rate_date': '2026-09-06',
  'payment_terms_days': 30,
  'salesperson_id': 'actor',
  'create_revision': false,
  'lines': [
    {
      'line_id': 'line',
      'description': 'Exact quotation',
      'unit_id': 'unit',
      'quantity': '1.000000',
      'base_quantity': '1.000000',
      'conversion_numerator': '1',
      'conversion_denominator': '1',
      'unit_price': '90071992547409.123456',
    },
  ],
};

Map<String, Object?> snapshot({
  String id = quoteId,
  int version = 7,
  String status = 'draft',
  String? notes,
}) => {
  ...form(id: id),
  'tenant_id': 'tenant',
  'legal_entity_id': 'entity',
  'branch_id': 'branch',
  'current_revision': 1,
  'base_currency_code': 'LKR',
  'subtotal': '90071992547409.123456',
  'discount_total': '0.000000',
  'tax_total': '0.000000',
  'grand_total': '90071992547409.123456',
  'base_total': '90071992547409.123456',
  'status': status,
  'version': version,
  'notes': notes,
  'created_at': '2026-09-06T00:00:00Z',
  'updated_at': '2026-09-06T00:00:00Z',
  'lines': [
    {
      ...(form()['lines'] as List).single as Map<String, Object?>,
      'id': 'line',
      'quotation_id': id,
      'revision_number': 1,
      'line_number': 1,
      'currency_code': 'LKR',
      'line_total': '90071992547409.123456',
    },
  ],
};
QuotationDetail detail({
  String id = quoteId,
  int version = 7,
  String status = 'draft',
  String? notes,
}) => QuotationDetail.fromJson(
  snapshot(id: id, version: version, status: status, notes: notes),
);
SalesQuotation quotation({String id = quoteId}) => detail(id: id).quotation;

class FakeQuotations
    implements QuotationWorkspaceRepository, LeadToCashRepository {
  CursorPage<SalesQuotation> page = CursorPage(items: [], limit: 50);
  QuotationDetail detail = QuotationDetail.fromJson(snapshot());
  final queries = <QuotationListQuery>[];
  final commands = <Map<String, Object?>>[];
  Future<QuotationDetail?> Function(String)? detailRead;
  Future<CommandResult<SalesQuotation>> Function(Map<String, Object?>)?
  onCommand;
  @override
  Future<CursorPage<SalesQuotation>> pageQuotations({
    required TenantContext context,
    required QuotationListQuery query,
  }) async {
    queries.add(query);
    return page;
  }

  @override
  Future<QuotationDetail?> loadQuotationDetail({
    required TenantContext context,
    required String id,
  }) async => detailRead == null ? detail : detailRead!(id);
  @override
  Future<List<SalesQuotationRevision>> quotationRevisions({
    required TenantContext context,
    required String id,
    int beforeRevision = 2147483647,
  }) async => [];
  @override
  Future<List<Map<String, Object?>>> quotationDecisions({
    required TenantContext context,
    required String id,
    String? beforeId,
  }) async => [];
  Future<CommandResult<SalesQuotation>> run(Map<String, Object?> wire) async {
    commands.add(wire);
    return onCommand == null
        ? CommandResult.success(requestId: 'success', entity: detail.quotation)
        : onCommand!(wire);
  }

  @override
  Future<CommandResult<SalesQuotation>> upsertQuotation(
    CommandEnvelope<QuotationDraft> command,
  ) => run(command.toJson((x) => x.toJson()));
  @override
  Future<CommandResult<SalesQuotation>> transitionQuotation(
    CommandEnvelope<OperationalDocumentTransition> command,
  ) => run(command.toJson((x) => x.toJson()));
  @override
  Future<CommandResult<SalesQuotation>> decideQuotationApproval(
    CommandEnvelope<OperationalApprovalDecision> command,
  ) => run(command.toJson((x) => x.toJson()));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
