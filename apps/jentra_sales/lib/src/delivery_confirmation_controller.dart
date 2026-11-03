import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation.dart';

import 'confirmation_controller.dart' show ConfirmationStage;

/// A distinct verified delivery flow. No durable store, order acceptance action,
/// automatic response, stock correction or accounting operation is available.
final class DeliveryConfirmationController extends ChangeNotifier {
  DeliveryConfirmationController({
    required String? token,
    required this.gateway,
  }) : _token = token {
    if (gateway == null || token == null || !_hex.hasMatch(token)) {
      stage = ConfirmationStage.unavailable;
      _token = null;
    } else {
      _lease = Timer(const Duration(minutes: 15), lock);
    }
  }
  static final _hex = RegExp(r'^[0-9a-f]{64}$');
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _decimal = RegExp(r'^\d{1,20}(?:\.\d{1,6})?$');
  final FieldDeliveryGateway? gateway;
  String? _token, _proof, _pending, error, recordedResponse;
  FieldSalesJson? offer;
  ConfirmationStage stage = ConfirmationStage.start;
  bool busy = false, _closed = false;
  int _epoch = 0;
  Timer? _lease;
  bool get hasPending => _pending != null;
  static BigInt units(String value) {
    if (!_decimal.hasMatch(value)) {
      throw const FormatException('Use an exact non-negative quantity.');
    }
    final parts = value.split('.');
    return BigInt.parse(parts[0]) * BigInt.from(1000000) +
        BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(6, '0'));
  }

  bool _current(int epoch) => !_closed && epoch == _epoch;
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
      if (_current(epoch)) {
        error = hasPending
            ? 'This response is uncertain. Retry only the original quantities or contact the company.'
            : 'This action could not be checked. Try again or ask the company for a new delivery link.';
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> requestCode() async {
    if (stage != ConfirmationStage.start) return;
    await _run((epoch) async {
      final result = await gateway!.requestCode(_token!);
      if (!_current(epoch)) return;
      if (result['state'] == 'check_email') {
        stage = ConfirmationStage.code;
      } else {
        lock();
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
        _clear();
        stage = ConfirmationStage.complete;
        recordedResponse = 'already recorded';
        return;
      }
      final value = result['offer'], proof = result['proof'];
      if (result['state'] != 'review' ||
          proof is! String ||
          !_hex.hasMatch(proof) ||
          !_validOffer(value)) {
        lock();
        return;
      }
      offer = fieldSalesObject(jsonDecode(jsonEncode(value)));
      _proof = proof;
      stage = ConfirmationStage.review;
    });
  }

  bool _validOffer(Object? value) {
    if (value is! Map ||
        value['delivery_id'] is! String ||
        !_uuid.hasMatch(value['delivery_id'] as String) ||
        value['delivery_version'] is! String ||
        !RegExp(r'^[1-9]\d*$').hasMatch(value['delivery_version'] as String) ||
        value['delivery_digest'] is! String ||
        !_hex.hasMatch(value['delivery_digest'] as String) ||
        value['company'] is! String ||
        value['customer'] is! String ||
        value['document_number'] is! String ||
        value['posted_at'] is! String ||
        DateTime.tryParse(value['posted_at'] as String) == null) {
      return false;
    }
    final lines = value['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 500) return false;
    final ids = <String>{};
    return lines.every(
      (line) =>
          line is Map &&
          line['id'] is String &&
          _uuid.hasMatch(line['id'] as String) &&
          ids.add(line['id'] as String) &&
          line['description'] is String &&
          line['base_unit'] is String &&
          line['posted_base_quantity'] is String &&
          _decimal.hasMatch(line['posted_base_quantity'] as String) &&
          units(line['posted_base_quantity'] as String) > BigInt.zero,
    );
  }

  String _outcome(List<FieldSalesJson> quantities) {
    var allReceived = true, allRefused = true;
    final lines = offer!['lines'] as List;
    if (quantities.length != lines.length) {
      throw const FormatException('Complete every delivery line.');
    }
    final ids = <String>{};
    for (final line in lines) {
      final matches = quantities.where((q) => q['id'] == line['id']);
      if (matches.length != 1 || !ids.add(line['id'] as String)) {
        throw const FormatException('Review the original delivery lines.');
      }
      final q = matches.single;
      if (q.keys.toSet().difference({
            'id',
            'received',
            'refused',
            'short',
          }).isNotEmpty ||
          ['received', 'refused', 'short'].any((k) => q[k] is! String)) {
        throw const FormatException('Use exact quantity strings.');
      }
      final posted = units(line['posted_base_quantity'] as String),
          received = units(q['received'] as String),
          refused = units(q['refused'] as String),
          short = units(q['short'] as String);
      if (received + refused + short != posted) {
        throw const FormatException(
          'Received, refused and short must total the posted quantity.',
        );
      }
      allReceived = allReceived && received == posted;
      allRefused = allRefused && refused == posted;
    }
    return allReceived
        ? 'received'
        : allRefused
        ? 'refused'
        : 'exception';
  }

  Future<void> respond(
    List<FieldSalesJson> quantities,
    String reason,
    bool authorized,
  ) async {
    if (stage != ConfirmationStage.review ||
        busy ||
        hasPending ||
        !authorized ||
        reason.length > 500) {
      return;
    }
    try {
      final outcome = _outcome(quantities);
      if (outcome != 'received' && reason.trim().isEmpty) {
        throw const FormatException('Explain any refused or short quantities.');
      }
      _pending = jsonEncode({
        'quantities': quantities,
        'reason': reason.trim(),
        'outcome': outcome,
      });
    } on FormatException catch (e) {
      error = e.message;
      notifyListeners();
      return;
    }
    await retryOriginal();
  }

  Future<void> retryOriginal() async {
    if (stage != ConfirmationStage.review ||
        _pending == null ||
        _proof == null) {
      return;
    }
    final original = fieldSalesObject(jsonDecode(_pending!));
    final quantities = (original['quantities'] as List)
        .map(fieldSalesObject)
        .toList();
    await _run((epoch) async {
      final result = await gateway!.respond(
        _token!,
        _proof!,
        quantities,
        original['reason'] as String,
        true,
      );
      if (!_current(epoch)) return;
      final actual = result['quantities'];
      final matches =
          actual is List &&
          actual.length == quantities.length &&
          List.generate(quantities.length, (i) => i).every(
            (i) =>
                actual[i] is Map &&
                [
                  'id',
                  'received',
                  'refused',
                  'short',
                ].every((k) => actual[i][k] == quantities[i][k]),
          );
      if (result['state'] == 'recorded' &&
          result['method'] == 'delivery_email_and_code' &&
          result['response'] == original['outcome'] &&
          result['id'] is String &&
          _uuid.hasMatch(result['id'] as String) &&
          matches &&
          [
            'delivery_id',
            'delivery_version',
            'delivery_digest',
          ].every((k) => result[k] == offer![k])) {
        recordedResponse = result['response'] as String;
        _clear();
        stage = ConfirmationStage.complete;
      } else if (const {
        'unavailable',
        'already_recorded',
        'review_required',
        'quantities_invalid',
      }.contains(result['state'])) {
        lock();
      } else {
        throw const FieldSalesFailure(
          'RECEIPT_INVALID',
          'The delivery result did not match the original quantities.',
        );
      }
    });
  }

  void _clear() {
    _token = null;
    _proof = null;
    _pending = null;
    offer = null;
    _lease?.cancel();
  }

  void lock() {
    if (_closed) return;
    _epoch++;
    busy = false;
    _clear();
    stage = ConfirmationStage.unavailable;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _clear();
    super.dispose();
  }
}
