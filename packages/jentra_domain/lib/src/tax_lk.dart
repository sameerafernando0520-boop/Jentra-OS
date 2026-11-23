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
      taxCode = json['tax_code'] as String?,
      manualJournalId = json['manual_journal_id'] as String?,
      lineId = json['line_id'] as String?,
      postingDate = json['posting_date'] as String?,
      supplierName = json['supplier_name'] as String?,
      wht = json['wht'] == null ? null : _lkr(json['wht'], 'wht'),
      taxableBase = json['taxable_base'] == null
          ? null
          : _lkr(json['taxable_base'], 'taxable_base');

  final String reason;
  final String? documentNumber, taxCode;

  /// Set on WHT_REGISTER_REQUIRED: the journal line to register.
  final String? manualJournalId, lineId, postingDate, supplierName;
  final Money? wht, taxableBase;

  String get message => switch (reason) {
    'VAT_TAX_CODE_MISSING' => 'A posted tax line has no tax code.',
    'VAT_MAPPING_REQUIRED' =>
      'Tax code ${taxCode ?? ''} has no approved VAT return line.',
    'VAT_MAPPING_DIRECTION_MISMATCH' =>
      'Tax code ${taxCode ?? ''} is mapped to the wrong side (a sale on an input line or a purchase on a supply line).',
    'VAT_RETURN_BASE_UNVERIFIED' =>
      'A return has no verified original tax base.',
    'VAT_JOURNAL_MISSING' => 'A taxed document has no posted journal.',
    'VAT_BASE_CURRENCY_LKR_REQUIRED' || 'SSCL_BASE_CURRENCY_LKR_REQUIRED' =>
      'The entity base currency must be LKR.',
    'SSCL_SETTINGS_REQUIRED' =>
      'No approved SSCL settings cover this quarter. Approve the rate and liable portion first.',
    'SSCL_VAT_MAPPING_REQUIRED' =>
      'Sale with tax code ${taxCode ?? ''} has no approved VAT line, so its turnover is not counted.',
    'SSCL_VAT_MAPPING_DIRECTION_MISMATCH' =>
      'Sale with tax code ${taxCode ?? ''} is mapped to an input line, so its turnover is not counted.',
    'WHT_REGISTER_REQUIRED' =>
      'WHT on ${documentNumber ?? 'a journal'} has no supplier, payment type or gross amount. Register it.',
    'WHT_AMOUNT_MISMATCH' =>
      'WHT on ${documentNumber ?? 'a journal'} differs from the gross amount at the code rate.',
    'WHT_SUPPLIER_TIN_MISSING' =>
      '${supplierName ?? 'A supplier'} has no TIN for the certificate.',
    'WHT_JOURNAL_MISSING' => 'A WHT line has no posted journal.',
    'WHT_BASE_CURRENCY_LKR_REQUIRED' => 'The entity base currency must be LKR.',
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

final class LkSsclSettings {
  LkSsclSettings.fromJson(Map<String, Object?> json)
    : id = _text(json['id'], 'id'),
      effectiveFrom = _text(json['effective_from'], 'effective_from'),
      effectiveToExclusive = _text(
        json['effective_to_exclusive'],
        'effective_to_exclusive',
      ),
      ratePercent = Money.parse(
        _text(json['rate_percent'], 'rate_percent'),
        'LKR',
      ),
      liablePortionPercent = Money.parse(
        _text(json['liable_portion_percent'], 'liable_portion_percent'),
        'LKR',
      ),
      includeZeroRated = json['include_zero_rated'] == true,
      includeExempt = json['include_exempt'] == true,
      activity = _text(json['activity'], 'activity'),
      status = _text(json['status'], 'status'),
      proposedBy = _text(json['proposed_by'], 'proposed_by'),
      sources = Map.unmodifiable({
        for (final MapEntry(:key, :value)
            in (json['sources'] as Map? ?? const {}).entries)
          '$key': '$value',
      });

  final String id,
      effectiveFrom,
      effectiveToExclusive,
      activity,
      status,
      proposedBy;

  /// Percentages held as exact decimals.
  final Money ratePercent, liablePortionPercent;
  final bool includeZeroRated, includeExempt;
  final Map<String, String> sources;
}

/// A non-certified SSCL workpaper for one calendar quarter, in LKR.
final class LkSsclReturn {
  LkSsclReturn.fromJson(Map<String, Object?> json)
    : quarterStart = _text(json['quarter_start'], 'quarter_start'),
      quarterEndExclusive = _text(
        json['quarter_end_exclusive'],
        'quarter_end_exclusive',
      ),
      entityTin = json['entity_tin'] as String?,
      turnover = {
        for (final MapEntry(:key, :value)
            in (json['turnover'] as Map? ?? const {}).entries)
          '$key': _lkr(value, 'turnover'),
      },
      includedTurnover = _lkr(
        json['included_turnover'] ?? '0',
        'included_turnover',
      ),
      liableTurnover = json['liable_turnover'] == null
          ? null
          : _lkr(json['liable_turnover'], 'liable_turnover'),
      ssclDue = json['sscl_due'] == null
          ? null
          : _lkr(json['sscl_due'], 'sscl_due'),
      settings = json['settings'] == null
          ? null
          : LkSsclSettings.fromJson(
              Map<String, Object?>.from(json['settings']! as Map),
            ),
      blockers = List.unmodifiable([
        for (final b in json['blockers'] as List<Object?>? ?? const [])
          LkTaxBlocker.fromJson(Map<String, Object?>.from(b! as Map)),
      ]);

  final String quarterStart, quarterEndExclusive;
  final String? entityTin;

  /// Turnover by VAT treatment: standard_rated, zero_rated, exempt, untaxed, outside_vat.
  final Map<String, Money> turnover;
  final Money includedTurnover;

  /// Null until approved settings cover the quarter.
  final Money? liableTurnover, ssclDue;
  final LkSsclSettings? settings;
  final List<LkTaxBlocker> blockers;

  static const _labels = {
    'standard_rated': 'Standard-rated sales',
    'zero_rated': 'Zero-rated sales (exports)',
    'exempt': 'Exempt sales',
    'untaxed': 'Sales without a tax code',
    'outside_vat': 'Sales outside VAT',
  };

  String toCsv() {
    final s = settings;
    return lkTaxCsv([
      ['Section', 'Item', 'Amount (LKR)'],
      ['Quarter', '$quarterStart to $quarterEndExclusive (exclusive)', ''],
      ['Entity', 'TIN ${entityTin ?? 'not recorded'}', ''],
      for (final MapEntry(:key, :value) in turnover.entries)
        ['Turnover', _labels[key] ?? key, lkTaxTwo(value)],
      ['Result', 'Turnover counted', lkTaxTwo(includedTurnover)],
      if (s != null) ...[
        ['Settings', 'Activity: ${s.activity}', ''],
        [
          'Settings',
          'Liable portion ${s.liablePortionPercent.toDecimalString()}%',
          '',
        ],
        ['Settings', 'Rate ${s.ratePercent.toDecimalString()}%', ''],
        [
          'Settings',
          'Exports counted: ${s.includeZeroRated ? 'yes' : 'no'}; exempt sales counted: ${s.includeExempt ? 'yes' : 'no'}',
          '',
        ],
      ],
      [
        'Result',
        'Liable turnover',
        liableTurnover == null ? '' : lkTaxTwo(liableTurnover!),
      ],
      ['Result', 'SSCL due', ssclDue == null ? '' : lkTaxTwo(ssclDue!)],
      for (final b in blockers)
        ['Blocker', '${b.reason} ${b.documentNumber ?? ''}'.trim(), ''],
    ]);
  }
}

/// IRD payment types for withholding tax.
enum LkWhtPaymentType {
  serviceFee('service_fee', 'Service fees'),
  rent('rent', 'Rent'),
  interest('interest', 'Interest'),
  dividend('dividend', 'Dividends'),
  royalty('royalty', 'Royalties'),
  other('other', 'Other payments');

  const LkWhtPaymentType(this.wire, this.label);
  final String wire, label;

  static LkWhtPaymentType parse(Object? value) => values.firstWhere(
    (t) => t.wire == value,
    orElse: () => throw FormatException('Unknown WHT payment type $value.'),
  );
}

final class LkWhtSupplier {
  LkWhtSupplier.fromJson(Map<String, Object?> json)
    : id = _text(json['supplier_id'], 'supplier_id'),
      name = _text(json['supplier_name'], 'supplier_name'),
      tin = json['supplier_tin'] as String?;

  final String id, name;
  final String? tin;
}

final class LkWhtRegisterEntry {
  LkWhtRegisterEntry.fromJson(Map<String, Object?> json)
    : id = _text(json['id'], 'id'),
      manualJournalId = _text(json['manual_journal_id'], 'manual_journal_id'),
      lineId = _text(json['line_id'], 'line_id'),
      supplierId = _text(json['supplier_id'], 'supplier_id'),
      paymentType = LkWhtPaymentType.parse(json['payment_type']),
      grossAmount = _lkr(json['gross_amount'], 'gross_amount'),
      note = _text(json['note'], 'note'),
      status = _text(json['status'], 'status');

  final String id, manualJournalId, lineId, supplierId, note, status;
  final LkWhtPaymentType paymentType;
  final Money grossAmount;
}

/// One registered WHT payment. Supplier fields are null inside a certificate.
final class LkWhtPayment {
  LkWhtPayment.fromJson(Map<String, Object?> json)
    : postingDate = _text(json['posting_date'], 'posting_date'),
      documentNumber = _text(json['document_number'], 'document_number'),
      paymentType = LkWhtPaymentType.parse(json['payment_type']),
      rate = _text(json['rate'], 'rate'),
      gross = _lkr(json['gross'], 'gross'),
      wht = _lkr(json['wht'], 'wht'),
      supplierName = json['supplier_name'] as String?,
      supplierTin = json['supplier_tin'] as String?;

  final String postingDate, documentNumber, rate;
  final LkWhtPaymentType paymentType;
  final Money gross, wht;
  final String? supplierName, supplierTin;
}

/// Certificate data: every registered payment to one supplier in the month.
final class LkWhtCertificate {
  LkWhtCertificate.fromJson(Map<String, Object?> json)
    : supplierId = _text(json['supplier_id'], 'supplier_id'),
      supplierName = _text(json['supplier_name'], 'supplier_name'),
      supplierTin = json['supplier_tin'] as String?,
      gross = _lkr(json['gross'], 'gross'),
      wht = _lkr(json['wht'], 'wht'),
      payments = List.unmodifiable([
        for (final p in json['payments'] as List<Object?>? ?? const [])
          LkWhtPayment.fromJson(Map<String, Object?>.from(p! as Map)),
      ]);

  final String supplierId, supplierName;
  final String? supplierTin;
  final Money gross, wht;
  final List<LkWhtPayment> payments;
}

/// A non-certified monthly WHT schedule with certificate data, in LKR.
final class LkWhtSchedule {
  LkWhtSchedule.fromJson(Map<String, Object?> json)
    : month = _text(json['month'], 'month'),
      entityTin = json['entity_tin'] as String?,
      totals = {
        for (final line in (json['lines'] as List<Object?>? ?? const []).map(
          (l) => Map<String, Object?>.from(l! as Map),
        ))
          LkWhtPaymentType.parse(line['payment_type']): (
            gross: _lkr(line['gross'], 'gross'),
            wht: _lkr(line['wht'], 'wht'),
          ),
      },
      totalGross = _lkr(json['total_gross'] ?? '0', 'total_gross'),
      totalWht = _lkr(json['total_wht'] ?? '0', 'total_wht'),
      schedule = List.unmodifiable([
        for (final r in json['schedule'] as List<Object?>? ?? const [])
          LkWhtPayment.fromJson(Map<String, Object?>.from(r! as Map)),
      ]),
      certificates = List.unmodifiable([
        for (final c in json['certificates'] as List<Object?>? ?? const [])
          LkWhtCertificate.fromJson(Map<String, Object?>.from(c! as Map)),
      ]),
      blockers = List.unmodifiable([
        for (final b in json['blockers'] as List<Object?>? ?? const [])
          LkTaxBlocker.fromJson(Map<String, Object?>.from(b! as Map)),
      ]),
      suppliers = List.unmodifiable([
        for (final s in json['suppliers'] as List<Object?>? ?? const [])
          LkWhtSupplier.fromJson(Map<String, Object?>.from(s! as Map)),
      ]),
      register = List.unmodifiable([
        for (final g in json['register'] as List<Object?>? ?? const [])
          LkWhtRegisterEntry.fromJson(Map<String, Object?>.from(g! as Map)),
      ]);

  final String month;
  final String? entityTin;
  final Map<LkWhtPaymentType, ({Money gross, Money wht})> totals;
  final Money totalGross, totalWht;
  final List<LkWhtPayment> schedule;
  final List<LkWhtCertificate> certificates;
  final List<LkTaxBlocker> blockers;

  /// Suppliers that can be chosen when registering a line.
  final List<LkWhtSupplier> suppliers;

  /// Active register entries for journals dated in the month.
  final List<LkWhtRegisterEntry> register;

  /// Lines still waiting for a register entry.
  List<LkTaxBlocker> get unregistered => [
    for (final b in blockers)
      if (b.reason == 'WHT_REGISTER_REQUIRED') b,
  ];

  /// One CSV: totals by payment type, the schedule, certificates, then blockers.
  String toCsv() => lkTaxCsv([
    [
      'Section',
      'Supplier',
      'Supplier TIN',
      'Date',
      'Document',
      'Payment type',
      'Rate %',
      'Gross (LKR)',
      'WHT (LKR)',
    ],
    ['Month', month, '', '', '', '', '', '', ''],
    ['Entity', entityTin ?? 'TIN not recorded', '', '', '', '', '', '', ''],
    for (final MapEntry(:key, :value) in totals.entries)
      [
        'Total',
        '',
        '',
        '',
        '',
        key.label,
        '',
        lkTaxTwo(value.gross),
        lkTaxTwo(value.wht),
      ],
    [
      'Total',
      '',
      '',
      '',
      '',
      'All',
      '',
      lkTaxTwo(totalGross),
      lkTaxTwo(totalWht),
    ],
    for (final p in schedule)
      [
        'Schedule',
        p.supplierName ?? '',
        p.supplierTin ?? '',
        p.postingDate,
        p.documentNumber,
        p.paymentType.label,
        p.rate,
        lkTaxTwo(p.gross),
        lkTaxTwo(p.wht),
      ],
    for (final c in certificates) ...[
      for (final p in c.payments)
        [
          'Certificate',
          c.supplierName,
          c.supplierTin ?? '',
          p.postingDate,
          p.documentNumber,
          p.paymentType.label,
          p.rate,
          lkTaxTwo(p.gross),
          lkTaxTwo(p.wht),
        ],
      [
        'Certificate total',
        c.supplierName,
        c.supplierTin ?? '',
        '',
        '',
        '',
        '',
        lkTaxTwo(c.gross),
        lkTaxTwo(c.wht),
      ],
    ],
    for (final b in blockers)
      ['Blocker', b.reason, '', '', b.documentNumber ?? '', '', '', '', ''],
  ]);
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

  Future<List<LkSsclSettings>> ssclSettings(TenantContext scope);

  /// Percentages as exact decimal strings; dates are first days of months.
  Future<LkSsclSettings> proposeSsclSettings(
    TenantContext scope, {
    required String id,
    required String effectiveFrom,
    required String effectiveToExclusive,
    required String ratePercent,
    required String liablePortionPercent,
    required bool includeZeroRated,
    required bool includeExempt,
    required String activity,
    required String reason,
  });

  /// [action] is `approve` or `retire`. Approval needs a second person with MFA.
  Future<LkSsclSettings> decideSsclSettings(
    TenantContext scope,
    String id,
    String action,
  );

  /// One calendar quarter starting in January, April, July or October.
  Future<LkSsclReturn> ssclReturn(
    TenantContext scope, {
    required String quarterStart,
  });

  /// One calendar month; [month] is its first day. Needs report export and MFA.
  Future<LkWhtSchedule> whtSchedule(
    TenantContext scope, {
    required String month,
  });

  /// Links a posted WHT journal line to a supplier, payment type and gross
  /// amount (an exact decimal string). Needs journal posting and MFA.
  Future<LkWhtRegisterEntry> recordWht(
    TenantContext scope, {
    required String id,
    required String manualJournalId,
    required String lineId,
    required String supplierId,
    required LkWhtPaymentType paymentType,
    required String grossAmount,
    required String note,
  });

  /// Retires an entry so it can be recorded again correctly.
  Future<LkWhtRegisterEntry> retireWht(TenantContext scope, String id);
}
