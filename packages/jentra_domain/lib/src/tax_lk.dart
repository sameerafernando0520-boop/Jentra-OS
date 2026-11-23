import 'money.dart';
import 'tenant_context.dart';

/// IRD VAT return lines a tax code can map to.
enum LkVatLine {
  standardRatedSupply('standard_rated_supply', 'Standard-rated supplies'),
  zeroRatedSupply('zero_rated_supply', 'Zero-rated supplies'),
  exemptSupply('exempt_supply', 'Exempt supplies'),
  inputClaimable('input_claimable', 'Input tax claimable'),
  inputNotClaimable('input_not_claimable', 'Input tax not claimable'),
  outsideVat('outside_vat', 'Outside VAT');

  const LkVatLine(this.wire, this.label);
  final String wire, label;

  static LkVatLine parse(Object? value) => values.firstWhere(
    (l) => l.wire == value,
    orElse: () => throw FormatException('Unknown VAT line $value.'),
  );

  bool get isSupply =>
      this == standardRatedSupply ||
      this == zeroRatedSupply ||
      this == exemptSupply;

  /// Mirrors finance.lk_vat_line_valid: which lines suit a tax code.
  bool suits(String kind, Money rate) => switch (this) {
    standardRatedSupply => kind == 'output' && rate.minorUnits > BigInt.zero,
    zeroRatedSupply =>
      (kind == 'zero' || kind == 'output') && rate.minorUnits == BigInt.zero,
    exemptSupply => kind == 'exempt',
    inputClaimable || inputNotClaimable => kind == 'input',
    outsideVat => true,
  };
}

String _text(Object? value, String field) => value is String && value.isNotEmpty
    ? value
    : throw FormatException('Tax field $field is missing.');

Money _lkr(Object? value, String field) =>
    Money.parse(_text(value, field), 'LKR');

final class LkVatMapping {
  LkVatMapping.fromJson(Map<String, Object?> json)
    : id = _text(json['id'], 'id'),
      line = LkVatLine.parse(json['vat_line']),
      reason = _text(json['reason'], 'reason'),
      status = _text(json['status'], 'status'),
      proposedBy = _text(json['proposed_by'], 'proposed_by');

  final String id, reason, status, proposedBy;
  final LkVatLine line;
}

/// A tax definition with its approved and pending VAT return mappings.
final class LkVatMappingRow {
  LkVatMappingRow.fromJson(Map<String, Object?> json)
    : taxDefinitionId = _text(json['tax_definition_id'], 'tax_definition_id'),
      code = _text(json['code'], 'code'),
      name = _text(json['name'], 'name'),
      kind = _text(json['kind'], 'kind'),
      rate = Money.parse(_text(json['rate'], 'rate'), 'LKR'),
      approved = json['approved'] == null
          ? null
          : LkVatMapping.fromJson(
              Map<String, Object?>.from(json['approved']! as Map),
            ),
      pending = List.unmodifiable([
        for (final m in json['pending'] as List<Object?>? ?? const [])
          LkVatMapping.fromJson(Map<String, Object?>.from(m! as Map)),
      ]);

  final String taxDefinitionId, code, name, kind;

  /// Percent, held as an exact decimal.
  final Money rate;
  final LkVatMapping? approved;
  final List<LkVatMapping> pending;
}

final class LkVatLineTotal {
  LkVatLineTotal.fromJson(Map<String, Object?> json)
    : line = LkVatLine.parse(json['line']),
      value = _lkr(json['value'], 'value'),
      tax = _lkr(json['tax'], 'tax');

  final LkVatLine line;
  final Money value, tax;
}

final class LkVatScheduleRow {
  LkVatScheduleRow.fromJson(Map<String, Object?> json)
    : line = LkVatLine.parse(json['line']),
      sourceType = _text(json['source_type'], 'source_type'),
      postingDate = _text(json['posting_date'], 'posting_date'),
      documentNumber = json['document_number'] as String? ?? '',
      counterpartyName = json['counterparty_name'] as String?,
      counterpartyTin = json['counterparty_tin'] as String?,
      taxCode = json['tax_code'] as String? ?? '',
      value = _lkr(json['value'], 'value'),
      tax = _lkr(json['tax'], 'tax');

  final LkVatLine line;
  final String sourceType, postingDate, documentNumber, taxCode;
  final String? counterpartyName, counterpartyTin;
  final Money value, tax;
}

final class LkTaxBlocker {
  LkTaxBlocker.fromJson(Map<String, Object?> json)
    : reason = _text(json['reason'], 'reason'),
      documentNumber = json['document_number'] as String?,
      taxCode = json['tax_code'] as String?;

  final String reason;
  final String? documentNumber, taxCode;

  String get message => switch (reason) {
    'VAT_TAX_CODE_MISSING' => 'A posted tax line has no tax code.',
    'VAT_MAPPING_REQUIRED' =>
      'Tax code ${taxCode ?? ''} has no approved VAT return line.',
    'VAT_MAPPING_DIRECTION_MISMATCH' =>
      'Tax code ${taxCode ?? ''} is mapped to the wrong side (a sale on an input line or a purchase on a supply line).',
    'VAT_RETURN_BASE_UNVERIFIED' =>
      'A return has no verified original tax base.',
    'VAT_JOURNAL_MISSING' => 'A taxed document has no posted journal.',
    'VAT_BASE_CURRENCY_LKR_REQUIRED' => 'The entity base currency must be LKR.',
    _ => 'Review this line before filing.',
  };
}

/// A non-certified VAT return workpaper for one month or quarter, in LKR.
final class LkVatReturn {
  LkVatReturn.fromJson(Map<String, Object?> json)
    : from = _text(json['from'], 'from'),
      toExclusive = _text(json['to_exclusive'], 'to_exclusive'),
      entityTin = json['entity_tin'] as String?,
      lines = List.unmodifiable([
        for (final l in json['lines'] as List<Object?>? ?? const [])
          LkVatLineTotal.fromJson(Map<String, Object?>.from(l! as Map)),
      ]),
      outputTax = _lkr(json['output_tax'] ?? '0', 'output_tax'),
      inputTaxClaimable = _lkr(
        json['input_tax_claimable'] ?? '0',
        'input_tax_claimable',
      ),
      netPayable = _lkr(json['net_payable'] ?? '0', 'net_payable'),
      blockers = List.unmodifiable([
        for (final b in json['blockers'] as List<Object?>? ?? const [])
          LkTaxBlocker.fromJson(Map<String, Object?>.from(b! as Map)),
      ]),
      outputSchedule = _schedule(json['output_schedule']),
      inputSchedule = _schedule(json['input_schedule']);

  static List<LkVatScheduleRow> _schedule(Object? raw) => List.unmodifiable([
    for (final r in raw as List<Object?>? ?? const [])
      LkVatScheduleRow.fromJson(Map<String, Object?>.from(r! as Map)),
  ]);

  final String from, toExclusive;
  final String? entityTin;
  final List<LkVatLineTotal> lines;
  final Money outputTax, inputTaxClaimable, netPayable;
  final List<LkTaxBlocker> blockers;
  final List<LkVatScheduleRow> outputSchedule, inputSchedule;

  /// Negative when input tax exceeds output tax (a refund position).
  bool get refundable => netPayable.minorUnits.isNegative;

  /// One CSV: return lines, then the output and input schedules, then blockers.
  String toCsv() {
    final rows = <List<String>>[
      [
        'Section',
        'Line',
        'Date',
        'Document',
        'Counterparty',
        'Counterparty TIN',
        'Tax code',
        'Value (LKR)',
        'VAT (LKR)',
      ],
      for (final l in lines)
        [
          'Return',
          l.line.label,
          '',
          '',
          '',
          '',
          '',
          lkTaxTwo(l.value),
          lkTaxTwo(l.tax),
        ],
      ['Return', 'Output tax', '', '', '', '', '', '', lkTaxTwo(outputTax)],
      [
        'Return',
        'Input tax claimable',
        '',
        '',
        '',
        '',
        '',
        '',
        lkTaxTwo(inputTaxClaimable),
      ],
      [
        'Return',
        refundable ? 'Net refundable' : 'Net payable',
        '',
        '',
        '',
        '',
        '',
        '',
        lkTaxTwo(netPayable),
      ],
      for (final (section, schedule) in [
        ('Output schedule', outputSchedule),
        ('Input schedule', inputSchedule),
      ])
        for (final s in schedule)
          [
            section,
            s.line.label,
            s.postingDate,
            s.documentNumber,
            s.counterpartyName ?? '',
            s.counterpartyTin ?? '',
            s.taxCode,
            lkTaxTwo(s.value),
            lkTaxTwo(s.tax),
          ],
      for (final b in blockers)
        [
          'Blocker',
          b.reason,
          '',
          b.documentNumber ?? '',
          '',
          '',
          b.taxCode ?? '',
          '',
          '',
        ],
    ];
    return lkTaxCsv(rows);
  }
}

/// Two decimals, half away from zero.
String lkTaxTwo(Money value) {
  final units = value.minorUnits.abs();
  final cents = (units + BigInt.from(5000)) ~/ BigInt.from(10000);
  final text =
      '${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
  return value.minorUnits.isNegative && cents != BigInt.zero ? '-$text' : text;
}

/// CSV with CRLF lines. Text cells a spreadsheet could run as a formula are
/// prefixed with an apostrophe; plain negative numbers stay numbers.
String lkTaxCsv(List<List<String>> rows) {
  String cell(String value) {
    final number = RegExp(r'^-?[0-9]+(\.[0-9]+)?$').hasMatch(value);
    final safe = !number && RegExp(r'^[=+\-@\t\r]').hasMatch(value)
        ? "'$value"
        : value;
    return RegExp(r'[",\r\n]').hasMatch(safe)
        ? '"${safe.replaceAll('"', '""')}"'
        : safe;
  }

  return '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
}

/// Server API for the Sri Lanka tax schedule candidates
/// (supabase/candidates/20261121090000_lk_vat_workpaper.sql).
abstract interface class LkTaxRepository {
  Future<List<LkVatMappingRow>> vatMappings(TenantContext scope);
  Future<LkVatMapping> proposeVatMapping(
    TenantContext scope, {
    required String id,
    required String taxDefinitionId,
    required LkVatLine line,
    required String reason,
  });

  /// [action] is `approve` or `retire`. Approval needs a second person with MFA.
  Future<LkVatMapping> decideVatMapping(
    TenantContext scope,
    String id,
    String action,
  );

  /// One calendar month or quarter. Needs report export and MFA (counterparty TINs).
  Future<LkVatReturn> vatReturn(
    TenantContext scope, {
    required String from,
    required String toExclusive,
  });
}
