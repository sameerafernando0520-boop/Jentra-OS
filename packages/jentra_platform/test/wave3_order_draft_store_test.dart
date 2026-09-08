import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'wave3_quotation_draft_store_test.dart' show MemoryKeys;

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late JentraLocalDatabase database;
  late EncryptedDraftRepository encrypted;
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(
      database,
      DraftCipher(keyStore: MemoryKeys()),
    );
  });
  tearDown(() => database.close());
  test(
    'AC-304 encrypted order namespace cannot overwrite or recover quotations',
    () async {
      final orders = QuotationDraftStore.orders(encrypted),
          quotes = QuotationDraftStore(encrypted);
      await orders.save(scope, 'new', {'notes': 'order terms'});
      await quotes.save(scope, 'new', {'notes': 'quotation terms'});
      expect((await orders.load(scope, 'new'))!.form['notes'], 'order terms');
      expect(
        (await quotes.load(scope, 'new'))!.form['notes'],
        'quotation terms',
      );
      expect(
        (await orders.pageDrafts(scope)).items.single.draft.form['notes'],
        'order terms',
      );
      expect(
        (await orders.pageDrafts(scope.copyWith(actorId: 'other'))).items,
        isEmpty,
      );
    },
  );
  test(
    'AC-304 reservation envelopes survive store recreation and block discard',
    () async {
      var orders = QuotationDraftStore.orders(encrypted);
      await orders.save(scope, 'order:one', {'id': 'one'}, expectedVersion: 4);
      final original = await orders.prepare(
        scope,
        'order:one',
        verb: 'reserve',
        payload: {
          'sales_order_id': 'one',
          'expires_at': '2099-01-01T00:00:00Z',
          'lines': [
            {
              'sales_order_line_id': 'line',
              'requested_base_quantity': '0.000001',
            },
          ],
        },
        expectedVersion: 4,
      );
      orders = QuotationDraftStore.orders(encrypted);
      expect(
        (await orders.load(scope, 'order:one'))!.pending!.toJson(),
        original.toJson(),
      );
      await expectLater(
        orders.discard(scope, 'order:one'),
        throwsA(isA<DomainError>()),
      );
      await orders.recordFailure(
        scope,
        'order:one',
        const DomainError(code: 'CONTRACT_ERROR', message: 'Unknown success'),
        commandId: original.envelope.commandId,
      );
      expect((await orders.load(scope, 'order:one'))!.pending, isNotNull);
    },
  );
  test(
    'AC-304 definite order state rejection restores editable fields',
    () async {
      final orders = QuotationDraftStore.orders(encrypted);
      await orders.save(scope, 'order:one', {'id': 'one'}, expectedVersion: 4);
      final pending = await orders.prepare(
        scope,
        'order:one',
        verb: 'confirm',
        payload: {'document_id': 'one'},
        expectedVersion: 4,
      );
      await orders.recordFailure(
        scope,
        'order:one',
        const DomainError(
          code: 'SALES_ORDER_NOT_CONFIRMABLE',
          message: 'State changed',
        ),
        commandId: pending.envelope.commandId,
      );
      expect((await orders.load(scope, 'order:one'))!.pending, isNull);
    },
  );
}
