import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';
import 'package:uuid/uuid.dart';

import 'data/sales_store.dart';

final class FieldSalesController extends ChangeNotifier {
  FieldSalesController({
    required this.gateway,
    required this.store,
    Stream<String?>? authChanges,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    _authChanges = authChanges?.listen((actor) {
      if (actorId != null && actor != actorId) {
        clear();
        error = 'Your session changed. Sign in to recheck your portfolio.';
        notifyListeners();
      }
    });
  }
  final FieldSalesGateway gateway;
  final SalesKeyValueStore store;
  final DateTime Function() now;
  StreamSubscription<String?>? _authChanges;
  Timer? _expiryTimer;
  Timer? _leaseTimer;
  int _epoch = 0;
  int _reviewRevision = 0;
  Future<void> _storageWrites = Future.value();
  Future<void> _persist(Future<void> Function() action) {
    final operation = _storageWrites.then((_) => action());
    _storageWrites = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  bool isOpen = false, busy = false;
  bool catalogueReady = false;
  String? actorId, error, selectedCustomer;
  FieldSalesScope? scope;
  List<FieldSalesJson> scopes = [], customers = [], products = [], orders = [];
  FieldSalesJson? review;
  FieldSalesJson? _reviewInput;
  FieldSalesJson? savedDraft;
  FieldSalesCommand? pending;
  String get _recoveryKey => 'jentra.sales.command.v1.$actorId.${scope!.key}';
  String get _draftKey => 'jentra.sales.order-draft.v1.$actorId.${scope!.key}';
  bool _current(int epoch) {
    if (epoch != _epoch) return false;
    if (actorId != gateway.actorId) {
      clear();
      error = 'Your session changed. Sign in again.';
      notifyListeners();
      return false;
    }
    return true;
  }

  bool _expired(FieldSalesCommand command) {
    final age = now().toUtc().difference(DateTime.parse(command.at).toUtc());
    return age.isNegative || age >= const Duration(hours: 24);
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final command = pending;
    if (command == null || command.bodyExpired) return;
    final remaining = DateTime.parse(command.at)
        .toUtc()
        .add(const Duration(hours: 24))
        .difference(now().toUtc());
    final epoch = _epoch;
    final key = _recoveryKey;
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () async {
        if (!_current(epoch) || pending?.commandId != command.commandId) return;
        final expired = command.expireBody();
        pending = expired;
        try {
          await _persist(() => store.write(key, jsonEncode(expired.toJson())));
        } on Object {
          if (_current(epoch)) error = 'Protected recovery could not be updated. Keep the original reference for company reconciliation.';
        }
        if (_current(epoch)) notifyListeners();
      },
    );
  }

  Future<void> open() async {
    clear();
    final epoch = _epoch;
    actorId = gateway.actorId;
    if (actorId == null) {
      throw const FieldSalesFailure(
        'SIGN_IN_REQUIRED',
        'Sign in to your company.',
      );
    }
    final workspace = await gateway.workspace();
    if (!_current(epoch)) return;
    if (workspace['contract_version'] != '1' || workspace['scopes'] is! List) {
      throw const FieldSalesFailure(
        'CONTRACT_INVALID',
        'Your company’s Sales contract needs review.',
      );
    }
    scopes = (workspace['scopes'] as List).map(fieldSalesObject).toList();
    if (scopes.isEmpty) {
      throw const FieldSalesFailure(
        'ASSIGNMENT_REQUIRED',
        'Ask your company to assign your customer portfolio.',
      );
    }
    // A single scope can open directly; multiple companies require explicit choice.
    isOpen = true;
    _leaseTimer = Timer(const Duration(minutes: 15), () {
      _fail(
        const FieldSalesFailure(
          'ACCESS_REVOKED',
          'Your Sales access lease expired. Sign in to recheck your portfolio.',
        ),
      );
    });
    if (scopes.length == 1) {
      await selectScope(FieldSalesScope.fromJson(scopes.single));
    }
    notifyListeners();
  }

  Future<void> selectScope(FieldSalesScope value) async {
    final epoch = ++_epoch;
    scope = value;
    customers = [];
    products = [];
    orders = [];
    review = null;
    _reviewInput = null;
    pending = null;
    selectedCustomer = null;
    catalogueReady = false;
    busy = true;
    error = null;
    notifyListeners();
    final recoveryKey = _recoveryKey;
    final draftKey = _draftKey;
    final actor = actorId;
    try {
      final rows = await gateway.customers(value);
      final subjects = await gateway.subjects(value);
      await _storageWrites;
      if (!_current(epoch)) return;
      final stored = await store.read(recoveryKey);
      FieldSalesCommand? recovered;
      if (stored != null) {
        if (stored.length > 240000) throw const FormatException();
        final json = fieldSalesObject(jsonDecode(stored));
        if (json['schema'] != 1) throw const FormatException();
        recovered = FieldSalesCommand.fromJson(json);
        if (recovered.actorId != actor || recovered.scope.key != value.key) {
          throw const FormatException();
        }
        if (_expired(recovered) ||
            !rows.any(
              (row) =>
                  row['id'] ==
                  (recovered!.payload['input'] as Map)['customer_id'],
            )) {
          recovered = recovered.expireBody();
          final expired = recovered;
          await _persist(
            () => store.write(recoveryKey, jsonEncode(expired.toJson())),
          );
        }
      }
      if (!_current(epoch)) return;
      customers = rows;
      orders = subjects;
      pending = recovered;
      _scheduleExpiry();
      final draftWire = await store.read(draftKey);
      if (!_current(epoch)) return;
      savedDraft = null;
      if (draftWire != null) {
        if (draftWire.length > 240000) throw const FormatException();
        final draft = fieldSalesObject(jsonDecode(draftWire));
        final age = now().toUtc().difference(
          DateTime.parse(draft['saved_at'] as String).toUtc(),
        );
        if (draft['actor_id'] == actor &&
            draft['scope'] == value.key &&
            !age.isNegative &&
            age < const Duration(hours: 24) &&
            rows.any((c) => c['id'] == draft['input']['customer_id'])) {
          savedDraft = fieldSalesObject(draft['input']);
        } else {
          await _persist(() => store.delete(draftKey));
        }
      }
    } on Object catch (e) {
      if (_current(epoch)) _fail(e);
    }
    if (_current(epoch)) {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> selectCustomer(String id) async {
    if (busy || pending != null) return;
    final epoch = ++_epoch;
    selectedCustomer = id;
    catalogueReady = false;
    products = [];
    review = null;
    _reviewInput = null;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final rows = await gateway.catalogue(scope!, id);
      if (_current(epoch)) {
        products = rows;
        catalogueReady = true;
      }
    } on Object catch (e) {
      if (_current(epoch)) _fail(e);
    }
    if (_current(epoch)) {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> preview(FieldSalesJson input) async {
    if (busy || pending != null) return;
    final epoch = _epoch;
    final revision = ++_reviewRevision;
    busy = true;
    review = null;
    _reviewInput = null;
    error = null;
    notifyListeners();
    final frozen = fieldSalesObject(jsonDecode(jsonEncode(input)));
    try {
      final result = await gateway.preview(scope!, frozen);
      if (!_current(epoch)) return;
      if (revision != _reviewRevision) {
        busy = false;
        notifyListeners();
        return;
      }
      if (result['source_digest'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$')
              .hasMatch(result['source_digest'] as String) ||
          result['pricing'] is! Map ||
          result['terms'] is! Map ||
          !['subtotal', 'tax_total', 'grand_total'].every((key) {
            final value = (result['pricing'] as Map)[key];
            return value is String &&
                RegExp(r'^\d{1,14}(?:\.\d{1,6})?$').hasMatch(value);
          })) {
        throw const FieldSalesFailure(
          'CONTRACT_INVALID',
          'The server total could not be verified.',
        );
      }
      review = result;
      _reviewInput = frozen;
    } on Object catch (e) {
      if (_current(epoch)) _fail(e);
    }
    if (_current(epoch)) {
      busy = false;
      notifyListeners();
    }
  }

  void invalidateReview() {
    ++_reviewRevision;
    review = null;
    _reviewInput = null;
    notifyListeners();
  }

  Future<bool> saveDraft(FieldSalesJson input) async {
    if (busy ||
        !isOpen ||
        pending != null ||
        scope == null ||
        !customers.any((c) => c['id'] == input['customer_id'])) {
      return false;
    }
    final epoch = _epoch;
    final key = _draftKey;
    final frozen = fieldSalesObject(jsonDecode(jsonEncode(input)));
    final wire = jsonEncode({
      'schema': 1,
      'actor_id': actorId,
      'scope': scope!.key,
      'saved_at': now().toUtc().toIso8601String(),
      'input': frozen,
    });
    if (wire.length > 240000) return false;
    try {
      await _persist(() => store.write(key, wire));
      if (!_current(epoch)) return false;
      savedDraft = frozen;
      notifyListeners();
      return true;
    } on Object catch (e) {
      if (_current(epoch)) {
        _fail(e);
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> submit() async {
    if (busy || pending != null || review == null || _reviewInput == null) {
      return;
    }
    final command = FieldSalesCommand(
      actorId: actorId!,
      scope: scope!,
      commandId: const Uuid().v4(),
      key: const Uuid().v4(),
      at: now().toUtc().toIso8601String(),
      payload: {
        'id': const Uuid().v4(),
        'input': _reviewInput,
        'source_digest': review!['source_digest'],
      },
    );
    final epoch = _epoch;
    final recoveryKey = _recoveryKey;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _persist(
        () => store.write(recoveryKey, jsonEncode(command.toJson())),
      );
      if (!_current(epoch)) return;
      pending =
          command; // Never dispatch before encrypted persistence succeeds.
      _scheduleExpiry();
      await _dispatch(command, epoch);
    } on Object catch (e) {
      if (_current(epoch)) _fail(e);
    }
    if (_current(epoch)) {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _dispatch(FieldSalesCommand command, int epoch) async {
    final recoveryKey = _recoveryKey;
    FieldSalesJson response;
    try {
      response = await gateway.submit(command);
    } on FieldSalesFailure catch (e) {
      if (['40001', '55000'].contains(e.code) && _current(epoch)) {
        await _persist(() => store.delete(recoveryKey));
        if (_current(epoch)) {
          pending = null;
          review = null;
          _reviewInput = null;
        }
      }
      rethrow;
    }
    command.validateReceipt(response);
    if (!_current(epoch)) return;
    final currentOrders = await gateway.subjects(command.scope);
    if (!_current(epoch)) return;
    await _acknowledge(command, epoch, currentOrders);
  }

  Future<void> _acknowledge(
    FieldSalesCommand command,
    int epoch,
    List<FieldSalesJson> currentOrders,
  ) async {
    final recoveryKey = _recoveryKey;
    final draftKey = _draftKey;
    final consumeDraft =
        savedDraft?['customer_id'] ==
        (command.payload['input'] as Map)['customer_id'];
    await _persist(() async {
      if (consumeDraft) await store.delete(draftKey);
      await store.delete(recoveryKey);
    });
    if (!_current(epoch)) return;
    pending = null;
    review = null;
    _reviewInput = null;
    selectedCustomer = null;
    products = [];
    _expiryTimer?.cancel();
    orders = currentOrders;
    if (consumeDraft) savedDraft = null;
  }

  Future<void> reconcile({bool retry = false}) async {
    final command = pending;
    if (busy || command == null) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await gateway.receipt(scope!, command.key);
      if (!_current(epoch)) return;
      if (result['state'] == 'committed') {
        final receipt = fieldSalesObject(result['receipt']);
        command.validateReceipt(receipt);
        final currentOrders = await gateway.subjects(command.scope);
        if (!_current(epoch)) return;
        await _acknowledge(command, epoch, currentOrders);
      } else if (result['state'] == 'not_found' && retry) {
        if (!command.bodyExpired && _expired(command)) {
          final expired = command.expireBody();
          final recoveryKey = _recoveryKey;
          await _persist(
            () => store.write(recoveryKey, jsonEncode(expired.toJson())),
          );
          if (!_current(epoch)) return;
          pending = expired;
          throw const FieldSalesFailure(
            'RECOVERY_EXPIRED',
            'The order body expired. Ask your company to reconcile the saved reference.',
          );
        }
        if (command.bodyExpired) {
          throw const FieldSalesFailure(
            'RECOVERY_EXPIRED',
            'The saved order body expired. Keep its recovery reference and ask your company to reconcile it.',
          );
        }
        await _dispatch(
          command,
          epoch,
        ); // Explicit retry; identical bytes/key only.
      } else {
        error = 'No receipt is visible yet. This does not prove the submission failed. You can retry the original request explicitly.';
      }
    } on Object catch (e) {
      if (_current(epoch)) _fail(e);
    }
    if (_current(epoch)) {
      busy = false;
      notifyListeners();
    }
  }

  void _fail(Object e) {
    error = e is FieldSalesFailure
        ? e.message
        : 'The Sales service could not complete this action.';
    if (e is FieldSalesFailure &&
        ['42501', 'ACCESS_REVOKED', 'ASSIGNMENT_CHANGED'].contains(e.code)) {
      // Keep only encrypted recovery metadata for later authorized reconciliation.
      customers = [];
      products = [];
      orders = [];
      review = null;
      _reviewInput = null;
      isOpen = false;
      _leaseTimer?.cancel();
      _expiryTimer?.cancel();
      ++_epoch;
      busy = false;
      scopes = [];
      selectedCustomer = null;
      pending = null;
      savedDraft = null;
      notifyListeners();
    }
  }

  void clear() {
    _expiryTimer?.cancel();
    _leaseTimer?.cancel();
    ++_epoch;
    isOpen = false;
    catalogueReady = false;
    busy = false;
    actorId = null;
    scope = null;
    scopes = [];
    customers = [];
    products = [];
    orders = [];
    review = null;
    _reviewInput = null;
    pending = null;
    savedDraft = null;
    selectedCustomer = null;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_epoch;
    _expiryTimer?.cancel();
    _leaseTimer?.cancel();
    _authChanges?.cancel();
    super.dispose();
  }
}
