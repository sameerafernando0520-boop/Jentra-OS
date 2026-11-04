import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:jentra_domain/jentra_field_sales.dart';

import 'data/sales_gateway.dart';
import 'data/sales_store.dart';
import 'demo_data.dart';
import 'models.dart';
import 'field_sales_controller.dart';

final class SalesController extends ChangeNotifier {
  SalesController({
    required this.store,
    this.account,
    this.field,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    field?.addListener(_fieldChanged);
  }
  final SalesKeyValueStore store;
  final SalesAccountGateway? account;
  final FieldSalesController? field;
  void _fieldChanged() {
    if (_disposed) return;
    notice = field?.error;
    if (field?.isOpen == false && field?.error != null && account != null) {
      unawaited(account!.signOut().catchError((Object _) {}));
    }
    notifyListeners();
  }

  final DateTime Function() now;
  bool preview = false, busy = false;
  bool _disposed = false;
  int _epoch = 0;
  SalesPage page = SalesPage.today;
  ThemeMode themeMode = ThemeMode.light;
  String? notice;
  List<SalesCustomer> customers = [];
  List<SalesProduct> products = [];
  List<SalesOrder> orders = [];
  List<SalesVisit> visits = [];
  Future<void> _writes = Future.value();
  static const _draftKey = 'jentra.sales.preview.drafts.v1';
  SalesCustomer customer(String id) => customers.firstWhere((c) => c.id == id);
  void go(SalesPage value) {
    page = value;
    notifyListeners();
  }

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  Future<void> enterPreview() async {
    field?.clear();
    await account?.signOut();
    final epoch = ++_epoch;
    busy = true;
    notice = null;
    notifyListeners();
    final drafts = <SalesOrder>[];
    try {
      final wire = await store.read(_draftKey);
      if (wire != null) {
        if (wire.length > 240000) throw const FormatException();
        final raw = jsonDecode(wire);
        if (raw is! List || raw.length > 50) throw const FormatException();
        for (final value in raw) {
          final draft = SalesOrder.fromDraft(
            Map<String, dynamic>.from(value as Map),
            SalesDemo.products,
          );
          if (!SalesDemo.customers.any((c) => c.id == draft.customerId)) {
            throw const FormatException();
          }
          final age = now().toUtc().difference(draft.date.toUtc());
          if (!age.isNegative && age < const Duration(hours: 24)) {
            drafts.add(draft);
          }
        }
        if (drafts.length != raw.length) {
          await store.write(
            _draftKey,
            jsonEncode(drafts.map((o) => o.toJson()).toList()),
          );
        }
      }
    } on Object {
      drafts.clear();
      notice = 'Saved drafts could not be opened. You can explore the preview; saving requires protected storage.';
    }
    if (_disposed || epoch != _epoch) return;
    customers = List.of(SalesDemo.customers);
    products = List.of(SalesDemo.products);
    orders = [...drafts, ...SalesDemo.orders(now())];
    visits = List.of(SalesDemo.visits);
    page = SalesPage.today;
    preview = true;
    busy = false;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    if (busy) return;
    final epoch = ++_epoch;
    busy = true;
    notice = null;
    notifyListeners();
    try {
      if (account == null) {
        throw const SalesFailure(
          'CONFIG_UNAVAILABLE',
          'Company sign-in is being prepared. Explore the preview while your company workspace is enabled.',
        );
      }
      await account!.signIn(email, password);
      if (_disposed || epoch != _epoch) {
        await account?.signOut();
        return;
      }
      await field?.open();
    } on FieldSalesFailure catch (e) {
      if (epoch == _epoch) {
        field?.clear();
        notice = e.message;
        await account?.signOut();
      }
    } on SalesFailure catch (e) {
      if (epoch == _epoch) notice = e.message;
    } on Object {
      if (epoch == _epoch) {
        notice = 'Sign-in could not complete. Please try again.';
      }
    }
    if (_disposed || epoch != _epoch) return;
    busy = false;
    notifyListeners();
  }

  Future<void> leave() async {
    ++_epoch;
    field?.clear();
    preview = false;
    busy = false;
    notice = null;
    customers = [];
    products = [];
    orders = [];
    visits = [];
    page = SalesPage.today;
    notifyListeners();
    try {
      await account?.signOut();
    } on Object {
      /* No business data is retained. */
    }
  }

  Future<void> saveDraft(SalesOrder draft) {
    final epoch = _epoch;
    final result = _writes.then((_) async {
      if (!preview || epoch != _epoch) {
        throw const SalesFailure(
          'WORKSPACE_CHANGED',
          'Reopen your workspace before saving.',
        );
      }
      if (!draft.local ||
          !customers.any((c) => c.id == draft.customerId) ||
          draft.lines.isEmpty ||
          draft.lines.length > 100 ||
          draft.notes.length > 2000 ||
          draft.reference.length > 120 ||
          draft.discountReason.length > 500) {
        throw const SalesFailure(
          'DRAFT_INVALID',
          'Review the customer, lines and notes before saving.',
        );
      }
      for (final line in draft.lines) {
        parseQuantity(line.quantity);
        if (!products.any((p) => identical(p, line.product))) {
          throw const SalesFailure(
            'CATALOGUE_CHANGED',
            'Reopen the current catalogue.',
          );
        }
      }
      final discount = parseDiscount(draft.discount);
      if (discount.isPositive && draft.discountReason.trim().isEmpty) {
        throw const SalesFailure(
          'REASON_REQUIRED',
          'Add a reason for your discount request.',
        );
      }
      final drafts = [
        ...orders.where((o) => o.local && o.id != draft.id),
        draft,
      ];
      if (drafts.length > 50) {
        throw const SalesFailure(
          'DRAFT_LIMIT',
          'Keep up to 50 local drafts. Remove an older draft first.',
        );
      }
      final wire = jsonEncode(drafts.map((o) => o.toJson()).toList());
      if (wire.length > 240000) {
        throw const SalesFailure(
          'DRAFT_LIMIT',
          'Draft storage is full. Remove an older draft first.',
        );
      }
      await store.write(_draftKey, wire);
      if (_disposed || epoch != _epoch || !preview) return;
      orders = [draft, ...orders.where((o) => o.id != draft.id)];
      notifyListeners();
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> removeDraft(String id) {
    final epoch = _epoch;
    final result = _writes.then((_) async {
      if (!preview || epoch != _epoch) return;
      final drafts = orders.where((o) => o.local && o.id != id).toList();
      await store.write(
        _draftKey,
        jsonEncode(drafts.map((o) => o.toJson()).toList()),
      );
      if (_disposed || epoch != _epoch) return;
      orders = orders.where((o) => !o.local || o.id != id).toList();
      notifyListeners();
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String newId() => const Uuid().v4();
  void recordPreviewVisit(SalesVisit visit, String note) {
    if (!preview) return;
    visits = visits
        .map((v) => v.id == visit.id ? v.complete(note) : v)
        .toList();
    notifyListeners();
  }

  void addPreviewVisit(SalesVisit visit) {
    if (!preview) return;
    visits = [...visits, visit];
    notifyListeners();
  }

  @override
  void dispose() {
    ++_epoch;
    _disposed = true;
    field?.removeListener(_fieldChanged);
    super.dispose();
  }
}
