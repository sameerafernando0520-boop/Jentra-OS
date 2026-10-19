import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as q;

const permissions = {
  'sales.orders.view',
  'sales.orders.manage',
  'inventory.reservations.manage',
  'sales.credit.override',
};
Map<String, Object?> orderForm() => {
  ...q.form()
    ..remove('quotation_date')
    ..remove('valid_until')
    ..remove('salesperson_id')
    ..remove('create_revision'),
  'order_date': '2026-09-06',
  'promised_date': '2099-10-01',
  'warehouse_id': 'warehouse',
  'ship_to': {'city': 'Colombo'},
  'lines': [
    for (final raw in q.form()['lines']! as List)
      {...(raw as Map).cast<String, Object?>(), 'product_id': 'product'},
  ],
};
Map<String, Object?> orderSnapshot({
  int version = 7,
  String status = 'draft',
  bool converted = false,
}) => {
  ...q.snapshot(version: version, status: status),
  ...orderForm(),
  'id': q.quoteId,
  'document_number': 'SO-2026-0001',
  if (converted) ...{
    'source_quotation_id': 'source-quote',
    'source_quotation_revision': 1,
  },
  'lines': [
    for (final raw in q.snapshot()['lines']! as List)
      {
        ...(raw as Map).cast<String, Object?>(),
        'sales_order_id': q.quoteId,
        'product_id': 'product',
        'product_kind': 'stocked',
        'version': 1,
        'ordered_quantity': '10.000000',
        'base_ordered_quantity': '10.000000',
        'allocated_quantity': '0.000000',
        'cancelled_quantity': '0.000000',
        'delivered_quantity': '4.000000',
        'invoiced_quantity': '0.000000',
        if (converted) ...{
          'source_quotation_line_id': 'source-line',
          'source_quotation_revision': 1,
        },
      },
  ],
};
SalesOrderDetail orderDetail({
  int version = 7,
  String status = 'draft',
  bool converted = false,
}) => SalesOrderDetail.fromJson(
  orderSnapshot(version: version, status: status, converted: converted),
);
SalesOrderCreditPreview preview({int version = 7}) =>
    SalesOrderCreditPreview.fromJson({
      'sales_order_id': q.quoteId,
      'order_version': version,
      'currency_code': 'LKR',
      'credit_currency_code': 'LKR',
      'credit_limit': '500.000000',
      'due_exposure': '450.000000',
      'overdue_exposure': '20.000000',
      'existing_order_exposure': '0.000000',
      'current_order_exposure': '100.000000',
      'total_exposure': '550.000000',
      'projection_available': true,
      'credit_as_of_at': '2026-09-07T00:00:00Z',
      'checked_at': '2026-09-07T01:00:00Z',
      'reason': 'CREDIT_LIMIT_EXCEEDED',
    });

class FakeOrders implements SalesOrderWorkspaceRepository {
  SalesOrderDetail detail = orderDetail();
  final commands = <({String verb, Map<String, Object?> wire})>[];
  final queries = <SalesOrderListQuery>[];
  Future<CommandResult<SalesOrder>> Function(
    String,
    CommandEnvelope<Map<String, Object?>>,
  )?
  onCommand;
  Future<SalesOrderDetail?> Function()? onRead;
  SalesOrderCreditPreview credit = preview();
  @override
  Future<CursorPage<SalesOrder>> pageOrders({
    required TenantContext context,
    required SalesOrderListQuery query,
  }) async {
    queries.add(query);
    return CursorPage(items: [detail.order], limit: query.limit);
  }

  @override
  Future<SalesOrderDetail?> loadOrder({
    required TenantContext context,
    required String id,
  }) async => onRead == null ? detail : onRead!();
  @override
  Future<SalesOrderCreditPreview> creditPreview({
    required TenantContext context,
    required String id,
  }) async => credit;
  @override
  Future<List<Map<String, Object?>>> creditDecisions({
    required TenantContext context,
    required String id,
    String? beforeId,
  }) async => [];
  @override
  Future<List<Map<String, Object?>>> reservations({
    required TenantContext context,
    required String id,
    String? afterId,
  }) async => [];
  @override
  Future<List<Map<String, Object?>>> availability({
    required TenantContext context,
    required String warehouseId,
    required List<String> productIds,
  }) async => [
    {
      'product_id': 'product',
      'on_hand_quantity': '20.000000',
      'allocated_quantity': '15.000000',
      'available_quantity': '5.000000',
    },
  ];
  @override
  Future<CommandResult<SalesOrder>> executeOrder(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add((verb: verb, wire: command.toJson((x) => x)));
    return onCommand == null
        ? CommandResult.success(requestId: 'ok', entity: detail.order)
        : onCommand!(verb, command);
  }
}

void main() {
  late JentraLocalDatabase database;
  late QuotationDraftStore store;
  late FakeOrders repository;
  late ProviderContainer container;
  var caps = permissions;
  var scope = q.scope;
  Future<SalesOrderController> start({
    Set<String> capabilities = permissions,
    ConnectivityState connectivity = ConnectivityState.online,
  }) async {
    caps = capabilities;
    container = ProviderContainer(
      retry: (count, error) => null,
      overrides: [
        activeTenantContextProvider.overrideWith((ref) => scope),
        businessCapabilitiesProvider.overrideWith((ref) async => caps),
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(connectivity),
        ),
        salesOrderRepositoryProvider.overrideWithValue(repository),
        salesOrderDraftStoreProvider.overrideWithValue(store),
        quotationWorkspaceRepositoryProvider.overrideWithValue(
          q.FakeQuotations()..detail = q.detail(status: 'accepted'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(salesOrderProvider, (_, next) {});
    await container.read(salesOrderProvider.future);
    return container.read(salesOrderProvider.notifier);
  }

  SalesOrderState value() => container.read(salesOrderProvider).requireValue;
  setUp(() {
    scope = q.scope;
    database = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore.orders(
      EncryptedDraftRepository(database, DraftCipher(keyStore: q.MemoryKeys())),
    );
    repository = FakeOrders();
  });
  tearDown(() => database.close());
  test('AC-304 denies order reads without order capability', () async {
    await expectLater(
      start(capabilities: {'sales.quotations.manage'}),
      throwsA(isA<DomainError>()),
    );
    expect(repository.queries, isEmpty);
  });
  test('AC-304 saves encrypted exact envelope before transport', () async {
    final c = await start();
    await c.newDraft();
    await c.updateForm(orderForm());
    repository.onCommand = (verb, wire) async {
      expect(
        (await store.load(q.scope, 'new'))!.pending!.envelope.toJson((x) => x),
        wire.toJson((x) => x),
      );
      return CommandResult.success(
        requestId: 'ok',
        entity: repository.detail.order,
      );
    };
    await c.save();
    expect(repository.commands.single.verb, 'save');
    expect(await store.load(q.scope, 'new'), isNull);
    expect(value().detail?.order.id, q.quoteId);
  });
  test(
    'AC-304 uncertain conversion survives restart with identical envelope',
    () async {
      var c = await start();
      await c.startConversion(q.quoteId);
      await c.updateForm({...value().form!, 'warehouse_id': 'warehouse'});
      repository.onCommand = (verb, wire) async =>
          throw TimeoutException('unknown');
      await c.save();
      expect(value().pending?.verb, 'convert');
      final first = repository.commands.single;
      c = await start();
      await c.recoverLocal('convert:${q.quoteId}');
      repository.onCommand = null;
      await c.retryPending();
      expect(repository.commands.last.verb, first.verb);
      expect(repository.commands.last.wire, first.wire);
      expect(await store.load(q.scope, 'convert:${q.quoteId}'), isNull);
    },
  );
  test('AC-304 converted order sends only delivery fields', () async {
    repository.detail = orderDetail(converted: true);
    final c = await start();
    await c.selectOrder(q.quoteId);
    await c.updateForm({
      ...value().form!,
      'ship_to': {'city': 'Galle'},
      'notes': 'cannot change source price',
    });
    await c.save();
    expect(repository.commands.single.verb, 'fulfillment');
    expect((repository.commands.single.wire['payload'] as Map).keys.toSet(), {
      'id',
      'promised_date',
      'warehouse_id',
      'ship_to',
    });
  });
  test('AC-304 confirmation requires credit review and distinct override permission', () async {
    final c = await start(capabilities: {'sales.orders.manage'});
    await c.selectOrder(q.quoteId);
    await c.confirm();
    expect(repository.commands, isEmpty);
    await c.reviewCredit();
    await c.confirm(overrideCredit: true, reason: 'Approved exception');
    expect(repository.commands, isEmpty);
    expect(value().error?.code, 'PERMISSION_DENIED');
    await c.confirm();
    expect(repository.commands.single.verb, 'confirm');
  });
  test(
    'AC-304 privileged override retains its reason and reviewed version',
    () async {
      final c = await start();
      await c.selectOrder(q.quoteId);
      await c.reviewCredit();
      await c.confirm(overrideCredit: true, reason: '');
      expect(repository.commands, isEmpty);
      await c.confirm(
        overrideCredit: true,
        reason: 'Finance approved this order',
      );
      expect(
        (repository.commands.single.wire['payload'] as Map)['override_reason'],
        'Finance approved this order',
      );
      expect(repository.commands.single.wire['expected_entity_version'], 7);
    },
  );
  test(
    'AC-304 remaining reservation demand excludes delivered quantities',
    () async {
      repository.detail = orderDetail(status: 'confirmed');
      final c = await start();
      await c.selectOrder(q.quoteId);
      expect(
        repository.detail.order.lines.single.remainingToReserve
            .toDecimalString(),
        '6.000000',
      );
      StockReservationDraft draft(String qty) => StockReservationDraft(
        salesOrderId: q.quoteId,
        expiresAt: DateTime.utc(2099),
        lines: [
          StockReservationLineDraft(
            salesOrderLineId: 'line',
            requestedBaseQuantity: ExactDecimal.parse(qty, scale: 6),
          ),
        ],
      );
      await c.reserve(draft('7'));
      expect(repository.commands, isEmpty);
      await c.reserve(draft('6'));
      expect(repository.commands.single.verb, 'reserve');
    },
  );
  test('AC-304 offline drafts do not send commands', () async {
    final c = await start(connectivity: ConnectivityState.offline);
    await c.newDraft();
    await c.updateForm(orderForm());
    await c.save();
    expect(repository.commands, isEmpty);
    expect(await store.load(q.scope, 'new'), isNotNull);
  });
  test(
    'AC-304 inventory operator can reserve but cannot edit or confirm',
    () async {
      repository.detail = orderDetail(status: 'confirmed');
      final c = await start(
        capabilities: {'sales.orders.view', 'inventory.reservations.manage'},
      );
      await c.selectOrder(q.quoteId);
      await c.updateForm({...value().form!, 'notes': 'denied'});
      expect(value().form?['notes'], isNull);
      await c.confirm();
      expect(repository.commands, isEmpty);
      await c.reserve(
        StockReservationDraft(
          salesOrderId: q.quoteId,
          expiresAt: DateTime.utc(2099),
          lines: [
            StockReservationLineDraft(
              salesOrderLineId: 'line',
              requestedBaseQuantity: ExactDecimal.parse('1', scale: 6),
            ),
          ],
        ),
      );
      expect(repository.commands.single.verb, 'reserve');
    },
  );
  test('AC-304 changed credit preview version prevents confirmation', () async {
    repository.credit = preview(version: 8);
    final c = await start();
    await c.selectOrder(q.quoteId);
    await c.reviewCredit();
    expect(value().credit, isNull);
    expect(value().error?.code, 'STALE_PREVIEW');
    await c.confirm();
    expect(repository.commands, isEmpty);
  });
  test(
    'AC-304 source-order lookup stays bounded to the requested quotation',
    () async {
      final c = await start();
      await c.openConvertedOrder(q.quoteId);
      expect(repository.queries.last.sourceQuotationId, q.quoteId);
      expect(repository.queries.last.limit, 2);
      expect(value().detail?.order.id, q.quoteId);
    },
  );
  test('AC-304 conflict retains local edits and resolves against inspected version', () async {
    final c = await start();
    await c.selectOrder(q.quoteId);
    await c.updateForm({...value().form!, 'notes': 'local'});
    repository.onCommand = (verb, wire) async => CommandResult.failure(
      requestId: 'conflict',
      error: const DomainError(code: 'VERSION_CONFLICT', message: 'Changed'),
    );
    await c.save();
    expect(value().conflict, true);
    expect(value().pending, isNull);
    repository.detail = orderDetail(version: 8);
    await c.inspectConflict();
    repository.detail = orderDetail(version: 9);
    await c.resolveConflict(keepLocal: true);
    expect(value().localDraft?.expectedVersion, 8);
    expect(value().form?['notes'], 'local');
    expect(value().conflict, false);
  });
  test('AC-304 capability changes discard late reads', () async {
    final c = await start();
    final pending = Completer<SalesOrderDetail?>();
    repository.onRead = () => pending.future;
    final selecting = c.selectOrder(q.quoteId);
    await Future<void>.delayed(Duration.zero);
    caps = {'sales.orders.view'};
    container.invalidate(businessCapabilitiesProvider);
    await container.read(businessCapabilitiesProvider.future);
    pending.complete(orderDetail());
    await selecting;
    await container.read(salesOrderProvider.future);
    expect(value().detail, isNull);
  });
  test('AC-304 double action emits a single command', () async {
    final c = await start();
    await c.newDraft();
    await c.updateForm(orderForm());
    final done = Completer<CommandResult<SalesOrder>>();
    repository.onCommand = (_, _) => done.future;
    final saving = c.save();
    await c.save();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repository.commands, hasLength(1));
    done.complete(
      CommandResult.success(requestId: 'ok', entity: repository.detail.order),
    );
    await saving;
  });
  test(
    'AC-304 post-commit read failure does not retain duplicate new draft',
    () async {
      final c = await start();
      await c.newDraft();
      await c.updateForm(orderForm());
      repository.onRead = () async => throw TimeoutException('read');
      await c.save();
      expect(await store.load(q.scope, 'new'), isNull);
      expect(value().form, isNull);
      await c.save();
      expect(repository.commands, hasLength(1));
    },
  );
}
