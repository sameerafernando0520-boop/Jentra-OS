import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation_company.dart';
import 'package:uuid/uuid.dart';

/// Online staff workspace. Every write is sealed before dispatch; only explicit
/// recovery actions can check or retry an uncertain original command.
final class FieldConfirmationCompanyController extends ChangeNotifier {
  FieldConfirmationCompanyController({
    required this.actor,
    required this.scope,
    required this.gateway,
    required this.store,
    required this.isAuthorized,
    this.delivery = false,
  });
  final String actor;
  final FieldSalesScope scope;
  final FieldConfirmationCompanyGateway gateway;
  final FieldConfirmationCompanyStore store;
  final bool Function() isAuthorized;
  final bool delivery;
  List<FieldSalesJson> subjects = [], contacts = [], challenges = [];
  FieldSalesJson? selected;
  FieldConfirmationCompanyCommand? pending;
  String? subjectCursor, contactCursor, challengeCursor, error, notice;
  String providerState = 'unavailable';
  bool busy = false, locked = false, _disposed = false;
  int _epoch = 0;
  bool get _current =>
      !_disposed && !locked && isAuthorized() && gateway.actorId == actor;
  bool get canWrite => _current && !busy && pending == null;
  bool get canIssue =>
      canWrite &&
      providerState == 'configured' &&
      selected != null &&
      (delivery
          ? !const {
              'received',
              'refused',
              'exception',
            }.contains(selected!['delivery_state'])
          : selected!['customer_state'] != 'accepted');
  Future<void> _run(Future<void> Function(int) work) async {
    if (busy || !_current) {
      if (!_current) lock();
      return;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await work(epoch);
    } on Object catch (e) {
      if (_valid(epoch)) {
        if (e is FieldSalesFailure &&
            ['42501', 'ACCESS_REVOKED'].contains(e.code)) {
          lock();
        } else {
          error = e is FieldSalesFailure ? e.message : 'This action could not be completed. Check the original request before trying another action.';
        }
      }
    } finally {
      if (_valid(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  bool _valid(int epoch) => _current && epoch == _epoch;
  Future<void> open() => _run((epoch) => _reload(epoch));
  Future<void> _reload(int epoch) async {
    final page = await gateway.subjects(scope);
    if (!_valid(epoch)) return;
    final saved = await store.load(actor, scope);
    if (!_valid(epoch)) return;
    subjects = List.of(page.items);
    subjectCursor = page.nextCursor;
    providerState = page.providerState ?? 'unavailable';
    pending = saved;
    selected = null;
    contacts = [];
    challenges = [];
    contactCursor = null;
    challengeCursor = null;
  }

  Future<void> moreSubjects() => _run((epoch) async {
    final cursor = subjectCursor;
    if (cursor == null) return;
    final page = await gateway.subjects(scope, after: cursor);
    if (!_valid(epoch)) return;
    _append(subjects, page.items);
    subjectCursor = page.nextCursor;
    providerState = page.providerState ?? 'unavailable';
  });
  void _append(List<FieldSalesJson> existing, List<FieldSalesJson> more) {
    final ids = existing.map((r) => r['id']).toSet();
    if (more.any((r) => r['id'] is! String || !ids.add(r['id']))) {
      throw const FieldSalesFailure(
        'CONTRACT_INVALID',
        'The company page repeated a record. Refresh before continuing.',
      );
    }
    existing.addAll(more);
  }

  Future<void> select(FieldSalesJson row) => _run((epoch) async {
    final frozen = fieldSalesObject(jsonDecode(jsonEncode(row)));
    selected = null;
    contacts = [];
    challenges = [];
    final contactPage = await gateway.contacts(
      scope,
      frozen['customer_id'] as String,
    );
    final history = await gateway.challenges(scope, frozen['id'] as String);
    if (!_valid(epoch)) return;
    selected = frozen;
    contacts = List.of(contactPage.items);
    contactCursor = contactPage.nextCursor;
    challenges = List.of(history.items);
    challengeCursor = history.nextCursor;
    providerState = contactPage.providerState ?? 'unavailable';
  });
  Future<void> moreContacts() => _run((epoch) async {
    final row = selected, cursor = contactCursor;
    if (row == null || cursor == null) return;
    final page = await gateway.contacts(
      scope,
      row['customer_id'] as String,
      after: cursor,
    );
    if (!_valid(epoch)) return;
    _append(contacts, page.items);
    contactCursor = page.nextCursor;
    providerState = page.providerState ?? 'unavailable';
  });
  Future<void> moreChallenges() => _run((epoch) async {
    final row = selected, cursor = challengeCursor;
    if (row == null || cursor == null) return;
    final page = await gateway.challenges(
      scope,
      row['id'] as String,
      after: cursor,
    );
    if (!_valid(epoch)) return;
    _append(challenges, page.items);
    challengeCursor = page.nextCursor;
  });
  Future<void> authorizeContact(
    FieldSalesJson payload, {
    String? expectedVersion,
  }) async {
    if (!canWrite || selected == null) return;
    await _prepare('authorize_contact', {
      'id': payload['id'] ?? const Uuid().v4(),
      ...payload,
      'customer_id': selected!['customer_id'],
    }, expectedVersion);
  }

  Future<void> revokeContact(FieldSalesJson contact) async {
    if (!canWrite) return;
    await _prepare('revoke_contact', {
      'id': contact['id'],
    }, contact['version'] as String);
  }

  Future<void> issue(FieldSalesJson contact) async {
    if (!canIssue) return;
    final row = selected!;
    await _prepare(delivery ? 'issue_delivery' : 'issue_order', {
      'id': const Uuid().v4(),
      if (delivery) ...{
        'delivery_id': row['delivery_id'],
        'delivery_version': row['delivery_version'],
        'delivery_digest': row['delivery_digest'],
      } else ...{
        'request_id': row['id'],
        'request_version': row['version'],
        'source_digest': row['source_digest'],
      },
      'contact_id': contact['id'],
      'contact_version': contact['version'],
    }, null);
  }

  Future<void> revokeChallenge(FieldSalesJson challenge, String reason) async {
    if (!canWrite) return;
    await _prepare(delivery ? 'revoke_delivery' : 'revoke_challenge', {
      'id': challenge['id'],
      'reason': reason,
    }, challenge['version'] as String);
  }

  Future<void> _prepare(
    String action,
    FieldSalesJson payload,
    String? expected,
  ) => _run((epoch) async {
    final command = await store.prepare(
      actor,
      scope,
      action,
      payload,
      expectedVersion: expected,
    );
    if (!_valid(epoch)) return;
    pending = command;
    await _send(command, epoch);
  });
  Future<void> _send(FieldConfirmationCompanyCommand command, int epoch) async {
    try {
      final receipt = await gateway.command(command.params);
      if (!_valid(epoch)) return;
      await _finish(command, receipt, epoch);
    } on FieldSalesFailure catch (e) {
      if (_valid(epoch) &&
          const {'22023', '40001', '55000', '54000'}.contains(e.code)) {
        await store.complete(command);
        if (!_valid(epoch)) return;
        pending = null;
      }
      rethrow;
    }
  }

  Future<void> _finish(
    FieldConfirmationCompanyCommand command,
    FieldSalesJson receipt,
    int epoch,
  ) async {
    command.validate(receipt);
    if (!_valid(epoch)) return;
    await store.complete(command);
    if (!_valid(epoch)) return;
    pending = null;
    await _reload(epoch);
    if (!_valid(epoch)) return;
    notice = command.action == 'issue_delivery'
        ? 'Delivery response request queued. Email delivery and goods receipt are not established.'
        : command.action == 'issue_order'
        ? 'Response request queued. Email delivery is not established.'
        : 'Company change recorded. Customer identity and order progression remain separate.';
  }

  Future<void> recover({bool retry = false}) => _run((epoch) async {
    final original = pending;
    if (original == null) return;
    final saved = await store.load(actor, scope);
    if (!_valid(epoch)) return;
    if (saved == null || saved.commandId != original.commandId) {
      throw const FieldSalesFailure(
        'RECOVERY_CHANGED',
        'The protected original request changed. Reopen this workspace.',
      );
    }
    pending = saved;
    final result = await gateway.receipt(scope, saved.key);
    if (!_valid(epoch)) return;
    if (result['state'] == 'committed') {
      await _finish(saved, fieldSalesObject(result['receipt']), epoch);
    } else if (result['state'] == 'not_found') {
      if (retry && !saved.expired) {
        await _send(saved, epoch);
      } else {
        notice = saved.expired
            ? 'No receipt found. The expired body cannot be sent. Company support must reconcile the original request.'
            : 'No committed receipt found. You may explicitly retry the original request.';
      }
    } else {
      throw const FieldSalesFailure(
        'RECEIPT_INVALID',
        'The original receipt could not be checked.',
      );
    }
  });
  void lock() {
    if (_disposed || locked) return;
    locked = true;
    _epoch++;
    busy = false;
    subjects = [];
    contacts = [];
    challenges = [];
    selected = null;
    pending = null;
    error = null;
    notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    subjects = [];
    contacts = [];
    challenges = [];
    selected = null;
    pending = null;
    super.dispose();
  }
}
