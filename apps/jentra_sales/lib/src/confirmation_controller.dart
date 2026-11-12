import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation.dart';

enum ConfirmationStage { start, code, review, complete, unavailable }

/// Recipient secrets live only in this short-lived page, never in draft stores.
final class ConfirmationController extends ChangeNotifier {
  ConfirmationController({required String? token, required this.gateway})
    : _token = token {
    if (gateway == null ||
        token == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      stage = ConfirmationStage.unavailable;
      _token = null;
    }
    if (stage != ConfirmationStage.unavailable) {
      _lease = Timer(const Duration(minutes: 15), lock);
    }
  }
  final FieldConfirmationGateway? gateway;
  String? _token, _proof;
  FieldSalesJson? offer;
  ConfirmationStage stage = ConfirmationStage.start;
  bool busy = false, _closed = false;
  String? error, recordedResponse;
  (String, String)? _pending;
  int _epoch = 0;
  Timer? _lease;
  bool get hasPending => _pending != null;

  Future<void> _run(Future<void> Function(int) work) async {
    if (busy ||
        _closed ||
        _token == null ||
        gateway == null ||
        stage == ConfirmationStage.unavailable) {
      return;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await work(epoch);
    } on Object {
      if (!_closed && epoch == _epoch) {
        error = hasPending
            ? 'The response is uncertain. Retry only the original response, or contact the company.'
            : 'This action could not be checked. Try again, or ask the company for a new link.';
      }
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  bool _current(int epoch) => !_closed && epoch == _epoch;
  void _unavailable() {
    lock();
  }

  Future<void> requestCode() async {
    if (stage != ConfirmationStage.start) return;
    await _run((epoch) async {
      final result = await gateway!.requestCode(_token!);
      if (!_current(epoch)) return;
      if (result['state'] == 'check_email') {
        stage = ConfirmationStage.code;
      } else {
        _unavailable();
      }
    });
  }

  Future<void> verify(String code) async {
    if (stage != ConfirmationStage.code || !RegExp(r'^\d{6}$').hasMatch(code)) {
      return;
    }
    await _run((epoch) async {
      final result = await gateway!.verify(_token!, code);
      if (!_current(epoch)) return;
      if (result['state'] == 'already_recorded') {
        _clearPrivate();
        recordedResponse = 'already recorded';
        stage = ConfirmationStage.complete;
        return;
      }
      if (result['state'] != 'review') {
        _unavailable();
        return;
      }
      final terms = fieldSalesObject(result['offer']);
      final proof = result['proof'];
      if (proof is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(proof) ||
          !_validOffer(terms)) {
        _unavailable();
        return;
      }
      _proof = proof;
      offer = fieldSalesObject(jsonDecode(jsonEncode(terms)));
      stage = ConfirmationStage.review;
    });
  }

  Future<void> respond(String decision, String reason, bool authorized) async {
    if (busy ||
        stage != ConfirmationStage.review ||
        hasPending ||
        !authorized ||
        !const {'accept', 'reject'}.contains(decision) ||
        reason.length > 500) {
      return;
    }
    _pending = (decision, reason.trim());
    await retryOriginal();
  }

  Future<void> retryOriginal() async {
    if (stage != ConfirmationStage.review ||
        _pending == null ||
        _proof == null) {
      return;
    }
    final original = _pending!;
    await _run((epoch) async {
      final result = await gateway!.respond(
        _token!,
        _proof!,
        original.$1,
        original.$2,
        true,
      );
      if (!_current(epoch)) return;
      final expected = original.$1 == 'accept' ? 'accepted' : 'rejected';
      if (result['state'] == 'recorded' &&
          result['response'] == expected &&
          result['method'] == 'email_link_and_code' &&
          result['request_id'] == offer!['request_id'] &&
          result['request_version'] == offer!['request_version'] &&
          result['source_digest'] == offer!['source_digest'] &&
          result['id'] is String) {
        recordedResponse = expected;
        _clearPrivate();
        stage = ConfirmationStage.complete;
      } else if (result['state'] == 'unavailable' ||
          result['state'] == 'conflict') {
        _unavailable();
      } else {
        throw const FieldSalesFailure(
          'RECEIPT_INVALID',
          'Response could not be confirmed.',
        );
      }
    });
  }

  void _clearPrivate() {
    _token = null;
    _proof = null;
    offer = null;
    _pending = null;
    _lease?.cancel();
  }

  bool _validOffer(FieldSalesJson value) {
    final terms = value['terms'],
        totals = value['totals'],
        lines = value['lines'];
    final decimal = RegExp(r'^\d{1,20}(\.\d{1,6})?$');
    bool exact(Object? amount) => amount is String && decimal.hasMatch(amount);
    return value['request_id'] is String &&
        (value['reference'] == null ||
            value['reference'] is String &&
                (value['reference'] as String).length <= 120) &&
        exact(value['discount_percent']) &&
        value['request_version'] is String &&
        RegExp(r'^[1-9]\d*$').hasMatch(value['request_version'] as String) &&
        value['source_digest'] is String &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(value['source_digest'] as String) &&
        value['company'] is String &&
        value['customer'] is String &&
        value['currency_code'] is String &&
        RegExp(r'^[A-Z]{3}$').hasMatch(value['currency_code'] as String) &&
        value['valid_until'] is String &&
        DateTime.tryParse(value['valid_until'] as String) != null &&
        terms is Map &&
        terms['ship_to'] is Map &&
        terms['payment_terms_days'] is String &&
        terms['delivery_terms'] is String &&
        terms['requested_date'] is String &&
        totals is Map &&
        const [
          'subtotal',
          'discount_total',
          'tax_total',
          'grand_total',
        ].every((key) => exact(totals[key])) &&
        lines is List &&
        lines.isNotEmpty &&
        lines.length <= 100 &&
        lines.every(
          (line) =>
              line is Map &&
              line['description'] is String &&
              line['unit'] is String &&
              (line['tax_name'] == null || line['tax_name'] is String) &&
              const [
                'line_discount_amount',
                'header_discount_amount',
              ].every((key) => line[key] == null || exact(line[key])) &&
              const [
                'quantity',
                'unit_price',
                'line_total',
                'tax_amount',
                'tax_rate',
              ].every((key) => exact(line[key])) &&
              line['tax_inclusive'] is bool,
        );
  }

  void lock() {
    if (_closed) return;
    _epoch++;
    busy = false;
    _clearPrivate();
    stage = ConfirmationStage.unavailable;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _clearPrivate();
    super.dispose();
  }
}
