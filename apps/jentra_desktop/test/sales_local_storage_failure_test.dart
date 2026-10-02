import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/sales/quotation_controller.dart';
import 'package:jentra_desktop/src/features/sales/sales_order_controller.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'quotation_controller_test.dart' as q;
import 'sales_order_controller_test.dart' as s;

final class _Keys implements SecretKeyStore {
  bool unavailable = true;
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async {
    if (unavailable) throw StateError('private key diagnostic token');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  for (final orders in [false, true]) {
    test(
      'EC-340 ${orders ? 'order' : 'quotation'} autosave preserves storage state and input',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory()), keys = _Keys();
        addTearDown(db.close);
        final encrypted = EncryptedDraftRepository(
          db,
          DraftCipher(keyStore: keys),
        );
        final store = orders
            ? QuotationDraftStore.orders(encrypted)
            : QuotationDraftStore(encrypted);
        final quotes = q.FakeQuotations(), orderRepository = s.FakeOrders();
        final container = ProviderContainer(
          retry: (count, error) => null,
          overrides: [
            activeTenantContextProvider.overrideWithValue(q.scope),
            businessCapabilitiesProvider.overrideWith(
              (ref) async => orders ? s.permissions : q.permissions,
            ),
            connectivityStateProvider.overrideWith(
              (ref) => Stream.value(ConnectivityState.online),
            ),
            quotationWorkspaceRepositoryProvider.overrideWithValue(quotes),
            leadToCashRepositoryProvider.overrideWithValue(quotes),
            quotationDraftStoreProvider.overrideWithValue(store),
            salesOrderRepositoryProvider.overrideWithValue(orderRepository),
            salesOrderDraftStoreProvider.overrideWithValue(store),
          ],
        );
        addTearDown(container.dispose);
        if (orders) {
          container.listen(salesOrderProvider, (_, next) {});
          await container.read(salesOrderProvider.future);
          final c = container.read(salesOrderProvider.notifier);
          await c.selectOrder(q.quoteId);
          final raw = {
            ...container.read(salesOrderProvider).requireValue.form!,
            'notes': 'exact local edits',
          };
          await c.updateForm(raw);
          var state = container.read(salesOrderProvider).requireValue;
          expect(state.error!.code, 'LOCAL_STORAGE_FULL');
          expect(state.error!.message, contains('Keep this editor open'));
          expect(
            jsonEncode(state.error!.toJson()),
            isNot(contains('private key diagnostic token')),
          );
          expect(state.form, raw);
          expect(state.dirty, isTrue);
          await c.save();
          expect(orderRepository.commands, isEmpty);
          expect(container.read(salesOrderProvider).requireValue.form, raw);
          await c.selectOrder(q.nextId);
          state = container.read(salesOrderProvider).requireValue;
          expect(state.form!['id'], q.quoteId);
          expect(state.form!['notes'], 'exact local edits');
          expect(state.error!.code, 'DRAFT_SAVE_FAILED');
          keys.unavailable = false;
          await c.save();
          expect(orderRepository.commands, hasLength(1));
          expect(
            (orderRepository.commands.single.wire['payload'] as Map)['notes'],
            'exact local edits',
          );
        } else {
          container.listen(quotationWorkspaceProvider, (_, next) {});
          await container.read(quotationWorkspaceProvider.future);
          final c = container.read(quotationWorkspaceProvider.notifier);
          await c.selectQuotation(q.quoteId);
          final raw = {
            ...container.read(quotationWorkspaceProvider).requireValue.form!,
            'notes': 'exact local edits',
          };
          await c.updateForm(raw);
          var state = container.read(quotationWorkspaceProvider).requireValue;
          expect(state.error!.code, 'LOCAL_STORAGE_FULL');
          expect(state.error!.message, contains('Keep this editor open'));
          expect(
            jsonEncode(state.error!.toJson()),
            isNot(contains('private key diagnostic token')),
          );
          expect(state.form, raw);
          expect(state.dirty, isTrue);
          await c.save();
          expect(quotes.commands, isEmpty);
          expect(
            container.read(quotationWorkspaceProvider).requireValue.form,
            raw,
          );
          await c.selectQuotation(q.nextId);
          state = container.read(quotationWorkspaceProvider).requireValue;
          expect(state.form!['id'], q.quoteId);
          expect(state.form!['notes'], 'exact local edits');
          expect(state.error!.code, 'DRAFT_SAVE_FAILED');
          keys.unavailable = false;
          await c.save();
          expect(quotes.commands, hasLength(1));
          expect(
            (quotes.commands.single['payload'] as Map)['notes'],
            'exact local edits',
          );
        }
      },
    );
  }
}
