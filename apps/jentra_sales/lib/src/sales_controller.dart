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
  bool _draftsReady = false;
  Timer? _draftExpiry;
  final _expiredDraftIds = <String>{};

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  Future<void> _enqueue(Future<void> Function() work) {
    final result = _writes.then((_) => work());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool _unexpired(SalesOrder order) {
    final age = now().toUtc().difference(order.date.toUtc());
    return !age.isNegative && age < const Duration(hours: 24);
  }

  void _requireDraftStorage(int epoch) {
    if (!_current(epoch) || !preview || busy) {
      throw const SalesFailure(
        'WORKSPACE_CHANGED',
        'Reopen your workspace before saving.',
      );
    }
    if (!_draftsReady) {
      throw const SalesFailure(
        'STORAGE_UNAVAILABLE',
        'Saved drafts could not be recovered. Exit and reopen the preview before changing local drafts.',
      );
    }
  }

  void _scheduleDraftExpiry() {
    _draftExpiry?.cancel();
    if (_disposed || !preview) return;
    final drafts = orders.where((o) => o.local).toList();
    if (drafts.isEmpty) return;
    final first = drafts
        .map((o) => o.date.toUtc())
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final remaining = first
        .add(const Duration(hours: 24))
        .difference(now().toUtc());
    final epoch = _epoch;
    _draftExpiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!_current(epoch) || !preview) return;
      final redacted = _redactExpiredDrafts();
      if (!_current(epoch)) return;
      _scheduleDraftExpiry();
      if (redacted && _draftsReady) {
        unawaited(
          _enqueue(() async {
            if (_current(epoch) && preview && _draftsReady) {
              await _persistDraftCleanup(
                epoch,
                orders.where((o) => o.local).toList(),
              );
            }
          }),
        );
      }
    });
  }

  bool _redactExpiredDrafts() {
    final expired = orders.where((o) => o.local && !_unexpired(o)).toList();
    if (expired.isEmpty) return false;
    final ids = expired.map((o) => o.id).toSet();
    _expiredDraftIds.addAll(ids);
    // Memory expiry must never wait for a protected-storage write.
    orders = orders.where((o) => !o.local || !ids.contains(o.id)).toList();
    notice = 'Expired local drafts were removed after 24 hours.';
    notifyListeners();
    return true;
  }

  Future<void> _pruneExpiredDrafts(int epoch) async {
    if (_redactExpiredDrafts() && _current(epoch)) {
      await _persistDraftCleanup(epoch, orders.where((o) => o.local).toList());
    }
  }

  Future<List<SalesOrder>> _writeUnexpiredDrafts(
    int epoch,
    List<SalesOrder> drafts,
  ) async {
    // A write can cross another deadline. Recheck the stored snapshot before
    // returning it, even if the user left while the write was pending.
    do {
      drafts = drafts.where((draft) {
        if (_unexpired(draft)) return true;
        if (_current(epoch)) _expiredDraftIds.add(draft.id);
        return false;
      }).toList();
      await store.write(
        _draftKey,
        jsonEncode(drafts.map((draft) => draft.toJson()).toList()),
      );
    } while (drafts.any((draft) => !_unexpired(draft)));
    return drafts;
  }

  Future<void> _persistDraftCleanup(int epoch, List<SalesOrder> drafts) async {
    try {
      await _writeUnexpiredDrafts(epoch, drafts);
    } on Object {
      if (_current(epoch)) {
        _draftsReady = false;
        notice = 'Expired drafts could not be cleared from protected storage. Exit and reopen the preview before saving.';
        notifyListeners();
      }
    }
  }

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
    if (_disposed) return;
    final epoch = ++_epoch;
    _draftExpiry?.cancel();
    _draftsReady = false;
    busy = true;
    notice = null;
    field?.clear();
    notifyListeners();
    try {
      await account?.signOut();
    } on Object {
      if (_current(epoch)) {
        busy = false;
        notice = 'Your company session could not be closed. Try opening the preview again.';
        notifyListeners();
      }
      return;
    }
    if (!_current(epoch)) return;
    // Recovery and expiry cleanup share the mutation queue, including writes
    // that started before the workspace was reopened.
    await _enqueue(() async {
      if (!_current(epoch)) return;
      var drafts = <SalesOrder>[];
      try {
        final wire = await store.read(_draftKey);
        if (!_current(epoch)) return;
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
            drafts.add(draft);
          }
          if (drafts.any((draft) => !_unexpired(draft))) {
            drafts = await _writeUnexpiredDrafts(epoch, drafts);
          }
        }
        if (!_current(epoch)) return;
        _draftsReady = true;
      } on Object {
        if (!_current(epoch)) return;
        drafts.clear();
        _draftsReady = false;
        notice = 'Saved drafts could not be opened. You can explore the preview; exit and reopen it to recover protected storage before saving.';
      }
      if (!_current(epoch)) return;
      customers = List.of(SalesDemo.customers);
      products = List.of(SalesDemo.products);
      orders = [...drafts, ...SalesDemo.orders(now())];
      visits = List.of(SalesDemo.visits);
      page = SalesPage.today;
      preview = true;
      busy = false;
      _scheduleDraftExpiry();
      notifyListeners();
    });
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
    if (_disposed) return;
    ++_epoch;
    _draftExpiry?.cancel();
    _draftsReady = false;
    _expiredDraftIds.clear();
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
    return _enqueue(() async {
      _requireDraftStorage(epoch);
      await _pruneExpiredDrafts(epoch);
      _requireDraftStorage(epoch);
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
      final original = orders
          .where((o) => o.local && o.id == draft.id)
          .firstOrNull;
      final saved = SalesOrder.fromDraft({
        ...draft.toJson(),
        'date': (original?.date ?? draft.date).toUtc().toIso8601String(),
        'command_id': original?.commandId ?? draft.commandId,
      }, products);
      if (_expiredDraftIds.contains(saved.id) || !_unexpired(saved)) {
        throw const SalesFailure(
          'DRAFT_EXPIRED',
          'This local draft expired. Start a new draft from the current catalogue.',
        );
      }
      final drafts = [
        ...orders.where((o) => o.local && o.id != saved.id),
        saved,
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
      final expiredDuringWrite = drafts.any((o) => !_unexpired(o));
      final savedExpired = !_unexpired(saved);
      if (_current(epoch) && preview) {
        if (savedExpired) _expiredDraftIds.add(saved.id);
        _redactExpiredDrafts();
        if (_current(epoch) && !savedExpired) {
          orders = [saved, ...orders.where((o) => o.id != saved.id)];
        }
        if (_current(epoch)) {
          _scheduleDraftExpiry();
          notifyListeners();
        }
      }
      if (expiredDuringWrite) await _persistDraftCleanup(epoch, drafts);
      if (savedExpired) {
        throw const SalesFailure(
          'DRAFT_EXPIRED',
          'This local draft expired. Start a new draft from the current catalogue.',
        );
      }
    });
  }

  Future<void> removeDraft(String id) {
    final epoch = _epoch;
    return _enqueue(() async {
      _requireDraftStorage(epoch);
      await _pruneExpiredDrafts(epoch);
      _requireDraftStorage(epoch);
      final drafts = orders.where((o) => o.local && o.id != id).toList();
      await store.write(
        _draftKey,
        jsonEncode(drafts.map((o) => o.toJson()).toList()),
      );
      if (_current(epoch) && preview) {
        orders = orders.where((o) => !o.local || o.id != id).toList();
        _redactExpiredDrafts();
        if (_current(epoch)) {
          _scheduleDraftExpiry();
          notifyListeners();
        }
      }
      if (drafts.any((o) => !_unexpired(o))) {
        await _persistDraftCleanup(epoch, drafts);
      }
    });
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
    _draftExpiry?.cancel();
    field?.removeListener(_fieldChanged);
    super.dispose();
  }
}
