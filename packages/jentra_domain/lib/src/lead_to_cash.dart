import 'exact_decimal.dart';
import 'money.dart';
import 'validation.dart';

enum OperationalDocumentType {
  salesQuotation('sales_quotation'),
  salesOrder('sales_order');

  const OperationalDocumentType(this.apiValue);
  final String apiValue;
}

enum OperationalDocumentAction {
  submit('submit'),
  accept('accept'),
  expire('expire'),
  recall('recall'),
  confirm('confirm'),
  cancel('cancel');

  const OperationalDocumentAction(this.apiValue);
  final String apiValue;
}

enum ApprovalDecision {
  approved('approved'),
  rejected('rejected');

  const ApprovalDecision(this.apiValue);
  final String apiValue;
}

final class CommercialQuantity {
  CommercialQuantity({
    required this.quantity,
    required this.unitId,
    required this.baseQuantity,
    required this.conversionNumerator,
    required this.conversionDenominator,
  });

  final ExactDecimal quantity;
  final String unitId;
  final ExactDecimal baseQuantity;
  final BigInt conversionNumerator;
  final BigInt conversionDenominator;

  ValidationResult validate({String field = 'quantity'}) {
    final issues = <ValidationIssue>[];
    if (quantity.scale != 6 || !quantity.isPositive) {
      issues.add(
        ValidationIssue(
          field: field,
          message: 'Quantity must be a positive six-place decimal.',
        ),
      );
    }
    if (baseQuantity.scale != 6 || !baseQuantity.isPositive) {
      issues.add(
        ValidationIssue(
          field: '${field}_base',
          message: 'Base quantity must be a positive six-place decimal.',
        ),
      );
    }
    if (unitId.trim().isEmpty) {
      issues.add(
        ValidationIssue(
          field: '${field}_unit_id',
          message: 'Unit is required.',
        ),
      );
    }
    if (conversionNumerator <= BigInt.zero ||
        conversionDenominator <= BigInt.zero ||
        baseQuantity.scaledValue * conversionDenominator !=
            quantity.scaledValue * conversionNumerator) {
      issues.add(
        ValidationIssue(
          field: '${field}_conversion',
          message: 'Base quantity does not match the exact unit conversion.',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'quantity': quantity.toDecimalString(),
    'unit_id': unitId,
    'base_quantity': baseQuantity.toDecimalString(),
    'conversion_numerator': conversionNumerator.toString(),
    'conversion_denominator': conversionDenominator.toString(),
  };
}

final class QuotationTaxSnapshot {
  const QuotationTaxSnapshot({
    required this.definitionId,
    required this.code,
    required this.name,
    required this.kind,
    required this.rate,
    required this.inclusive,
    required this.definitionVersion,
  });

  final String definitionId;
  final String code;
  final String name;
  final String kind;
  final ExactDecimal rate;
  final bool inclusive;
  final int definitionVersion;
}

final class QuotationLineDraft {
  const QuotationLineDraft({
    required this.lineId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.productId,
    this.discountAmount,
    this.discountPercent,
    this.taxDefinitionId,
    this.previewTax,
  });

  final String lineId;
  final String? productId;
  final String description;
  final CommercialQuantity quantity;
  final Money unitPrice;
  final Money? discountAmount;
  final ExactDecimal? discountPercent;
  final String? taxDefinitionId;

  /// Optional client preview only. The server always re-reads and snapshots
  /// the governed tax definition when the command is executed.
  final QuotationTaxSnapshot? previewTax;

  ValidationResult validate({required String currencyCode}) {
    final issues = <ValidationIssue>[...quantity.validate().issues];
    if (lineId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          field: 'line_id',
          message: 'Line identity is required.',
        ),
      );
    }
    if (description.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          field: 'description',
          message: 'Description is required.',
        ),
      );
    }
    if (unitPrice.currencyCode != currencyCode ||
        unitPrice.minorUnits < BigInt.zero) {
      issues.add(
        const ValidationIssue(
          field: 'unit_price',
          message: 'Unit price must be non-negative and use document currency.',
        ),
      );
    }
    if (discountAmount != null && discountPercent != null) {
      issues.add(
        const ValidationIssue(
          field: 'discount',
          message: 'Choose an amount or percentage discount, not both.',
        ),
      );
    }
    if (discountAmount != null &&
        (discountAmount!.currencyCode != currencyCode ||
            discountAmount!.minorUnits < BigInt.zero)) {
      issues.add(
        const ValidationIssue(
          field: 'discount_amount',
          message: 'Discount amount must be non-negative document currency.',
        ),
      );
    }
    final percent = discountPercent;
    if (percent != null &&
        (percent.scale != 6 ||
            percent.isNegative ||
            percent.scaledValue > BigInt.from(100000000))) {
      issues.add(
        const ValidationIssue(
          field: 'discount_percent',
          message: 'Discount percentage must be between zero and one hundred.',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'line_id': lineId,
    if (productId != null) 'product_id': productId,
    'description': description.trim(),
    ...quantity.toJson(),
    'unit_price': unitPrice.toDecimalString(),
    if (discountAmount != null)
      'discount_amount': discountAmount!.toDecimalString(),
    if (discountPercent != null)
      'discount_percent': discountPercent!.toDecimalString(),
    if (taxDefinitionId != null) 'tax_definition_id': taxDefinitionId,
  };

  QuotationLineDraft copyWith({
    String? lineId,
    String? productId,
    String? description,
    CommercialQuantity? quantity,
    Money? unitPrice,
    Money? discountAmount,
    ExactDecimal? discountPercent,
    String? taxDefinitionId,
    QuotationTaxSnapshot? previewTax,
  }) => QuotationLineDraft(
    lineId: lineId ?? this.lineId,
    productId: productId ?? this.productId,
    description: description ?? this.description,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    discountAmount: discountAmount ?? this.discountAmount,
    discountPercent: discountPercent ?? this.discountPercent,
    taxDefinitionId: taxDefinitionId ?? this.taxDefinitionId,
    previewTax: previewTax ?? this.previewTax,
  );
}

final class PricedQuotationLine {
  const PricedQuotationLine({
    required this.source,
    required this.grossAmount,
    required this.lineDiscountAmount,
    required this.headerDiscountAmount,
    required this.netAmount,
    required this.taxAmount,
    required this.lineTotal,
  });

  final QuotationLineDraft source;
  final Money grossAmount;
  final Money lineDiscountAmount;
  final Money headerDiscountAmount;
  final Money netAmount;
  final Money taxAmount;
  final Money lineTotal;
}

final class QuotationPricing {
  const QuotationPricing({
    required this.lines,
    required this.subtotal,
    required this.lineDiscountTotal,
    required this.headerDiscountTotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.baseTotal,
  });

  final List<PricedQuotationLine> lines;
  final Money subtotal;
  final Money lineDiscountTotal;
  final Money headerDiscountTotal;
  final Money discountTotal;
  final Money taxTotal;
  final Money grandTotal;
  final Money baseTotal;
}

abstract final class QuotationPricingCalculator {
  static QuotationPricing calculate({
    required String currencyCode,
    required String baseCurrencyCode,
    required ExactDecimal exchangeRate,
    required int roundingScale,
    required List<QuotationLineDraft> lines,
    Money? headerDiscountAmount,
    ExactDecimal? headerDiscountPercent,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError.value(
        lines,
        'lines',
        'At least one line is required.',
      );
    }
    if (roundingScale < 0 || roundingScale > Money.scale) {
      throw RangeError.range(roundingScale, 0, Money.scale, 'roundingScale');
    }
    if (exchangeRate.scale != 10 || !exchangeRate.isPositive) {
      throw ArgumentError.value(
        exchangeRate,
        'exchangeRate',
        'A positive ten-place rate is required.',
      );
    }
    if (headerDiscountAmount != null && headerDiscountPercent != null) {
      throw ArgumentError('Choose an amount or percentage header discount.');
    }
    if (headerDiscountAmount != null &&
        (headerDiscountAmount.currencyCode != currencyCode ||
            headerDiscountAmount.minorUnits < BigInt.zero)) {
      throw ArgumentError.value(
        headerDiscountAmount,
        'headerDiscountAmount',
        'Expected a non-negative document-currency amount.',
      );
    }
    if (headerDiscountPercent != null &&
        (headerDiscountPercent.scale != 6 ||
            headerDiscountPercent.isNegative ||
            headerDiscountPercent.scaledValue > BigInt.from(100000000))) {
      throw ArgumentError.value(
        headerDiscountPercent,
        'headerDiscountPercent',
        'Expected zero through one hundred.',
      );
    }

    final grossUnits = <BigInt>[];
    final lineDiscountUnits = <BigInt>[];
    final bases = <BigInt>[];
    var subtotalUnits = BigInt.zero;
    var lineDiscountTotalUnits = BigInt.zero;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final validation = line.validate(currencyCode: currencyCode);
      if (!validation.isValid) {
        throw ArgumentError.value(
          line,
          'lines[$index]',
          validation.issues.map((issue) => issue.message).join(' '),
        );
      }
      final gross = _roundMoneyUnits(
        _divideRounded(
          line.quantity.quantity.scaledValue * line.unitPrice.minorUnits,
          _pow10(6),
        ),
        roundingScale,
      );
      final lineDiscount = line.discountAmount != null
          ? _roundMoneyUnits(line.discountAmount!.minorUnits, roundingScale)
          : line.discountPercent != null
          ? _roundMoneyUnits(
              _divideRounded(
                gross * line.discountPercent!.scaledValue,
                BigInt.from(100) * _pow10(6),
              ),
              roundingScale,
            )
          : BigInt.zero;
      if (lineDiscount > gross) {
        throw ArgumentError.value(
          lineDiscount,
          'discount',
          'Exceeds line gross.',
        );
      }
      grossUnits.add(gross);
      lineDiscountUnits.add(lineDiscount);
      bases.add(gross - lineDiscount);
      subtotalUnits += gross;
      lineDiscountTotalUnits += lineDiscount;
    }

    final totalBasis = bases.fold(BigInt.zero, (sum, value) => sum + value);
    final headerTotal = headerDiscountAmount != null
        ? _roundMoneyUnits(headerDiscountAmount.minorUnits, roundingScale)
        : headerDiscountPercent != null
        ? _roundMoneyUnits(
            _divideRounded(
              totalBasis * headerDiscountPercent.scaledValue,
              BigInt.from(100) * _pow10(6),
            ),
            roundingScale,
          )
        : BigInt.zero;
    if (headerTotal > totalBasis) {
      throw ArgumentError.value(
        headerTotal,
        'headerDiscount',
        'Exceeds the post-line-discount basis.',
      );
    }

    var allocated = BigInt.zero;
    var cumulativeBasis = BigInt.zero;
    var taxTotalUnits = BigInt.zero;
    var grandTotalUnits = BigInt.zero;
    final priced = <PricedQuotationLine>[];
    for (var index = 0; index < lines.length; index++) {
      final isLast = index == lines.length - 1;
      cumulativeBasis += bases[index];
      final headerAllocation = headerTotal == BigInt.zero
          ? BigInt.zero
          : isLast
          ? headerTotal - allocated
          : _roundMoneyUnits(
                  _divideRounded(headerTotal * cumulativeBasis, totalBasis),
                  roundingScale,
                ) -
                allocated;
      allocated += headerAllocation;
      final discountedBasis = bases[index] - headerAllocation;
      final tax = lines[index].previewTax;
      final taxUnits = tax == null || tax.rate.isZero
          ? BigInt.zero
          : _roundMoneyUnits(
              _divideRounded(
                discountedBasis * tax.rate.scaledValue,
                tax.inclusive
                    ? BigInt.from(100) * _pow10(6) + tax.rate.scaledValue
                    : BigInt.from(100) * _pow10(6),
              ),
              roundingScale,
            );
      final netUnits = tax?.inclusive ?? false
          ? discountedBasis - taxUnits
          : discountedBasis;
      final totalUnits = tax?.inclusive ?? false
          ? discountedBasis
          : discountedBasis + taxUnits;
      taxTotalUnits += taxUnits;
      grandTotalUnits += totalUnits;
      priced.add(
        PricedQuotationLine(
          source: lines[index],
          grossAmount: Money.fromMinorUnits(grossUnits[index], currencyCode),
          lineDiscountAmount: Money.fromMinorUnits(
            lineDiscountUnits[index],
            currencyCode,
          ),
          headerDiscountAmount: Money.fromMinorUnits(
            headerAllocation,
            currencyCode,
          ),
          netAmount: Money.fromMinorUnits(netUnits, currencyCode),
          taxAmount: Money.fromMinorUnits(taxUnits, currencyCode),
          lineTotal: Money.fromMinorUnits(totalUnits, currencyCode),
        ),
      );
    }

    final baseUnits = _roundMoneyUnits(
      _divideRounded(grandTotalUnits * exchangeRate.scaledValue, _pow10(10)),
      roundingScale,
    );
    return QuotationPricing(
      lines: List.unmodifiable(priced),
      subtotal: Money.fromMinorUnits(subtotalUnits, currencyCode),
      lineDiscountTotal: Money.fromMinorUnits(
        lineDiscountTotalUnits,
        currencyCode,
      ),
      headerDiscountTotal: Money.fromMinorUnits(headerTotal, currencyCode),
      discountTotal: Money.fromMinorUnits(
        lineDiscountTotalUnits + headerTotal,
        currencyCode,
      ),
      taxTotal: Money.fromMinorUnits(taxTotalUnits, currencyCode),
      grandTotal: Money.fromMinorUnits(grandTotalUnits, currencyCode),
      baseTotal: Money.fromMinorUnits(baseUnits, baseCurrencyCode),
    );
  }
}

final class QuotationDraft {
  const QuotationDraft({
    required this.customerId,
    required this.quotationDate,
    required this.validUntil,
    required this.currencyCode,
    required this.exchangeRate,
    required this.rateDate,
    required this.salespersonId,
    required this.lines,
    this.id,
    this.contactId,
    this.opportunityId,
    this.exchangeRateId,
    this.paymentTermsDays = 0,
    this.deliveryTerms,
    this.headerDiscountAmount,
    this.headerDiscountPercent,
    this.notes,
    this.createRevision = false,
    this.revisionReason,
  });

  final String? id;
  final String customerId;
  final String? contactId;
  final String? opportunityId;
  final DateTime quotationDate;
  final DateTime validUntil;
  final String currencyCode;
  final String? exchangeRateId;
  final ExactDecimal exchangeRate;
  final DateTime rateDate;
  final int paymentTermsDays;
  final String? deliveryTerms;
  final String salespersonId;
  final Money? headerDiscountAmount;
  final ExactDecimal? headerDiscountPercent;
  final String? notes;
  final bool createRevision;
  final String? revisionReason;
  final List<QuotationLineDraft> lines;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    if (customerId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(field: 'customer_id', message: 'Required.'),
      );
    }
    if (_dateOnly(validUntil).isBefore(_dateOnly(quotationDate))) {
      issues.add(
        const ValidationIssue(
          field: 'valid_until',
          message: 'Validity cannot end before the quotation date.',
        ),
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
      issues.add(
        const ValidationIssue(
          field: 'currency_code',
          message: 'Use an ISO currency code.',
        ),
      );
    }
    if (exchangeRate.scale != 10 || !exchangeRate.isPositive) {
      issues.add(
        const ValidationIssue(
          field: 'exchange_rate',
          message: 'A positive ten-place exact rate is required.',
        ),
      );
    }
    if (salespersonId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(field: 'salesperson_id', message: 'Required.'),
      );
    }
    if (paymentTermsDays < 0 || paymentTermsDays > 3650) {
      issues.add(
        const ValidationIssue(
          field: 'payment_terms_days',
          message: 'Expected zero through 3650 days.',
        ),
      );
    }
    if (headerDiscountAmount != null && headerDiscountPercent != null) {
      issues.add(
        const ValidationIssue(
          field: 'header_discount',
          message: 'Choose an amount or percentage, not both.',
        ),
      );
    }
    if (headerDiscountAmount != null &&
        (headerDiscountAmount!.currencyCode != currencyCode ||
            headerDiscountAmount!.minorUnits.isNegative)) {
      issues.add(
        const ValidationIssue(
          field: 'header_discount_amount',
          message: 'Header discount must be non-negative document currency.',
        ),
      );
    }
    final headerPercent = headerDiscountPercent;
    if (headerPercent != null &&
        (headerPercent.scale != 6 ||
            headerPercent.isNegative ||
            headerPercent.scaledValue > BigInt.from(100000000))) {
      issues.add(
        const ValidationIssue(
          field: 'header_discount_percent',
          message:
              'Header discount percentage must be between zero and one hundred.',
        ),
      );
    }
    if (createRevision && (revisionReason?.trim().isEmpty ?? true)) {
      issues.add(
        const ValidationIssue(
          field: 'revision_reason',
          message: 'A revision reason is required.',
        ),
      );
    }
    if (lines.isEmpty) {
      issues.add(const ValidationIssue(field: 'lines', message: 'Required.'));
    }
    for (var index = 0; index < lines.length; index++) {
      for (final issue
          in lines[index].validate(currencyCode: currencyCode).issues) {
        issues.add(
          ValidationIssue(
            field: 'lines[$index].${issue.field}',
            message: issue.message,
          ),
        );
      }
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null) 'id': id,
    'customer_id': customerId,
    if (contactId != null) 'contact_id': contactId,
    if (opportunityId != null) 'opportunity_id': opportunityId,
    'quotation_date': _formatDate(quotationDate),
    'valid_until': _formatDate(validUntil),
    'currency_code': currencyCode,
    if (exchangeRateId != null) 'exchange_rate_id': exchangeRateId,
    'exchange_rate': exchangeRate.toDecimalString(),
    'rate_date': _formatDate(rateDate),
    'payment_terms_days': paymentTermsDays,
    if (deliveryTerms != null) 'delivery_terms': deliveryTerms,
    'salesperson_id': salespersonId,
    if (headerDiscountAmount != null)
      'header_discount_amount': headerDiscountAmount!.toDecimalString(),
    if (headerDiscountPercent != null)
      'header_discount_percent': headerDiscountPercent!.toDecimalString(),
    if (notes != null) 'notes': notes,
    'create_revision': createRevision,
    if (revisionReason != null) 'revision_reason': revisionReason,
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
  };
}

final class SalesQuotation {
  const SalesQuotation({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.branchId,
    required this.currentRevision,
    required this.customerId,
    required this.quotationDate,
    required this.validUntil,
    required this.currencyCode,
    required this.baseCurrencyCode,
    required this.exchangeRate,
    required this.rateDate,
    required this.salespersonId,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.baseTotal,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.documentNumber,
    this.contactId,
    this.opportunityId,
    this.exchangeRateId,
    this.paymentTermsDays = 0,
    this.deliveryTerms,
    this.notes,
    this.workflowDefinitionId,
    this.workflowRevision,
    this.submittedAt,
    this.approvedAt,
    this.acceptedAt,
    this.lines = const <SalesQuotationLine>[],
  });

  final String id;
  final String tenantId;
  final String legalEntityId;
  final String branchId;
  final String? documentNumber;
  final int currentRevision;
  final String customerId;
  final String? contactId;
  final String? opportunityId;
  final DateTime quotationDate;
  final DateTime validUntil;
  final String currencyCode;
  final String baseCurrencyCode;
  final String? exchangeRateId;
  final ExactDecimal exchangeRate;
  final DateTime rateDate;
  final int paymentTermsDays;
  final String? deliveryTerms;
  final String salespersonId;
  final Money subtotal;
  final Money discountTotal;
  final Money taxTotal;
  final Money grandTotal;
  final Money baseTotal;
  final String? notes;
  final String status;
  final String? workflowDefinitionId;
  final int? workflowRevision;
  final int version;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final DateTime? acceptedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SalesQuotationLine> lines;

  factory SalesQuotation.fromJson(Map<String, Object?> json) {
    final currency = _requiredString(json, 'currency_code');
    final baseCurrency = _requiredString(json, 'base_currency_code');
    return SalesQuotation(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      legalEntityId: _requiredString(json, 'legal_entity_id'),
      branchId: _requiredString(json, 'branch_id'),
      documentNumber: _optionalString(json, 'document_number'),
      currentRevision: _requiredInt(json, 'current_revision'),
      customerId: _requiredString(json, 'customer_id'),
      contactId: _optionalString(json, 'contact_id'),
      opportunityId: _optionalString(json, 'opportunity_id'),
      quotationDate: _requiredDate(json, 'quotation_date'),
      validUntil: _requiredDate(json, 'valid_until'),
      currencyCode: currency,
      baseCurrencyCode: baseCurrency,
      exchangeRateId: _optionalString(json, 'exchange_rate_id'),
      exchangeRate: ExactDecimal.parse(
        _decimalString(json, 'exchange_rate'),
        scale: 10,
      ),
      rateDate: _requiredDate(json, 'rate_date'),
      paymentTermsDays: _requiredInt(json, 'payment_terms_days'),
      deliveryTerms: _optionalString(json, 'delivery_terms'),
      salespersonId: _requiredString(json, 'salesperson_id'),
      subtotal: Money.parse(_decimalString(json, 'subtotal'), currency),
      discountTotal: Money.parse(
        _decimalString(json, 'discount_total'),
        currency,
      ),
      taxTotal: Money.parse(_decimalString(json, 'tax_total'), currency),
      grandTotal: Money.parse(_decimalString(json, 'grand_total'), currency),
      baseTotal: Money.parse(_decimalString(json, 'base_total'), baseCurrency),
      notes: _optionalString(json, 'notes'),
      status: _requiredString(json, 'status'),
      workflowDefinitionId: _optionalString(json, 'workflow_definition_id'),
      workflowRevision: _optionalInt(json, 'workflow_revision'),
      version: _requiredInt(json, 'version'),
      submittedAt: _optionalTimestamp(json, 'submitted_at'),
      approvedAt: _optionalTimestamp(json, 'approved_at'),
      acceptedAt: _optionalTimestamp(json, 'accepted_at'),
      createdAt: _requiredTimestamp(json, 'created_at'),
      updatedAt: _requiredTimestamp(json, 'updated_at'),
      lines: _optionalMaps(
        json,
        'lines',
      ).map(SalesQuotationLine.fromJson).toList(growable: false),
    );
  }
}

final class SalesQuotationLine {
  const SalesQuotationLine({
    required this.id,
    required this.quotationId,
    required this.revisionNumber,
    required this.lineNumber,
    required this.description,
    required this.currencyCode,
    required this.lineTotal,
  });

  final String id;
  final String quotationId;
  final int revisionNumber;
  final int lineNumber;
  final String description;
  final String currencyCode;
  final Money lineTotal;

  factory SalesQuotationLine.fromJson(Map<String, Object?> json) {
    final currency = _requiredString(json, 'currency_code');
    return SalesQuotationLine(
      id: _requiredString(json, 'id'),
      quotationId: _requiredString(json, 'quotation_id'),
      revisionNumber: _requiredInt(json, 'revision_number'),
      lineNumber: _requiredInt(json, 'line_number'),
      description: _requiredString(json, 'description'),
      currencyCode: currency,
      lineTotal: Money.parse(_decimalString(json, 'line_total'), currency),
    );
  }
}

final class SalesQuotationRevision {
  const SalesQuotationRevision({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.branchId,
    required this.quotationId,
    required this.revisionNumber,
    required this.status,
    required this.snapshot,
    required this.createdBy,
    required this.createdAt,
    this.documentNumber,
    this.reason,
  });

  final String id;
  final String tenantId;
  final String legalEntityId;
  final String branchId;
  final String quotationId;
  final int revisionNumber;
  final String? documentNumber;
  final String status;
  final String? reason;
  final Map<String, Object?> snapshot;
  final String createdBy;
  final DateTime createdAt;

  factory SalesQuotationRevision.fromJson(Map<String, Object?> json) =>
      SalesQuotationRevision(
        id: _requiredString(json, 'id'),
        tenantId: _requiredString(json, 'tenant_id'),
        legalEntityId: _requiredString(json, 'legal_entity_id'),
        branchId: _requiredString(json, 'branch_id'),
        quotationId: _requiredString(json, 'quotation_id'),
        revisionNumber: _requiredInt(json, 'revision_number'),
        documentNumber: _optionalString(json, 'document_number'),
        status: _requiredString(json, 'status'),
        reason: _optionalString(json, 'reason'),
        snapshot: _requiredMap(json, 'snapshot'),
        createdBy: _requiredString(json, 'created_by'),
        createdAt: _requiredTimestamp(json, 'created_at'),
      );
}

final class OperationalDocumentTransition {
  const OperationalDocumentTransition({
    required this.documentType,
    required this.documentId,
    required this.action,
    this.reason,
    this.overrideCredit = false,
    this.overrideReason,
  });

  final OperationalDocumentType documentType;
  final String documentId;
  final OperationalDocumentAction action;
  final String? reason;
  final bool overrideCredit;
  final String? overrideReason;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    if (documentId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(field: 'document_id', message: 'Required.'),
      );
    }
    if (overrideCredit && (overrideReason?.trim().isEmpty ?? true)) {
      issues.add(
        const ValidationIssue(
          field: 'override_reason',
          message: 'Credit override reason is required.',
        ),
      );
    }
    if (action == OperationalDocumentAction.recall &&
        (reason?.trim().isEmpty ?? true)) {
      issues.add(
        const ValidationIssue(
          field: 'reason',
          message: 'A recall reason is required.',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'document_type': documentType.apiValue,
    'document_id': documentId,
    'action': action.apiValue,
    if (reason != null) 'reason': reason,
    if (overrideCredit) 'override_credit': true,
    if (overrideReason != null) 'override_reason': overrideReason,
  };
}

final class OperationalApprovalDecision {
  const OperationalApprovalDecision({
    required this.documentType,
    required this.documentId,
    required this.decision,
    this.note,
  });

  final OperationalDocumentType documentType;
  final String documentId;
  final ApprovalDecision decision;
  final String? note;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    if (documentId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(field: 'document_id', message: 'Required.'),
      );
    }
    if (decision == ApprovalDecision.rejected &&
        (note?.trim().isEmpty ?? true)) {
      issues.add(
        const ValidationIssue(
          field: 'note',
          message: 'Rejection note is required.',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'document_type': documentType.apiValue,
    'document_id': documentId,
    'decision': decision.apiValue,
    if (note != null) 'note': note,
  };
}

final class QuotationConversionDraft {
  const QuotationConversionDraft({
    required this.quotationId,
    required this.quotationRevision,
    required this.promisedDate,
    required this.warehouseId,
    this.shipTo = const <String, Object?>{},
  });

  final String quotationId;
  final int quotationRevision;
  final DateTime promisedDate;
  final String warehouseId;
  final Map<String, Object?> shipTo;

  ValidationResult validate() => ValidationResult([
    if (quotationId.trim().isEmpty)
      const ValidationIssue(field: 'quotation_id', message: 'Required.'),
    if (quotationRevision < 1)
      const ValidationIssue(
        field: 'quotation_revision',
        message: 'Must be positive.',
      ),
    if (warehouseId.trim().isEmpty)
      const ValidationIssue(field: 'warehouse_id', message: 'Required.'),
  ]);

  Map<String, Object?> toJson() => <String, Object?>{
    'quotation_id': quotationId,
    'quotation_revision': quotationRevision,
    'promised_date': _formatDate(promisedDate),
    'warehouse_id': warehouseId,
    'ship_to': shipTo,
  };
}

final class SalesOrderDraft {
  const SalesOrderDraft({
    required this.customerId,
    required this.orderDate,
    required this.promisedDate,
    required this.currencyCode,
    required this.exchangeRate,
    required this.rateDate,
    required this.warehouseId,
    required this.lines,
    this.id,
    this.contactId,
    this.paymentTermsDays = 0,
    this.deliveryTerms,
    this.shipTo = const <String, Object?>{},
    this.exchangeRateId,
    this.headerDiscountAmount,
    this.headerDiscountPercent,
    this.notes,
  });

  final String? id;
  final String customerId;
  final String? contactId;
  final DateTime orderDate;
  final DateTime promisedDate;
  final String currencyCode;
  final String? exchangeRateId;
  final ExactDecimal exchangeRate;
  final DateTime rateDate;
  final String warehouseId;
  final int paymentTermsDays;
  final String? deliveryTerms;
  final Map<String, Object?> shipTo;
  final Money? headerDiscountAmount;
  final ExactDecimal? headerDiscountPercent;
  final String? notes;
  final List<QuotationLineDraft> lines;

  ValidationResult validate() {
    final quotation = QuotationDraft(
      id: id,
      customerId: customerId,
      contactId: contactId,
      quotationDate: orderDate,
      validUntil: promisedDate,
      currencyCode: currencyCode,
      exchangeRateId: exchangeRateId,
      exchangeRate: exchangeRate,
      rateDate: rateDate,
      paymentTermsDays: paymentTermsDays,
      deliveryTerms: deliveryTerms,
      salespersonId: 'server-derived',
      headerDiscountAmount: headerDiscountAmount,
      headerDiscountPercent: headerDiscountPercent,
      notes: notes,
      lines: lines,
    );
    return ValidationResult([
      ...quotation.validate().issues,
      if (warehouseId.trim().isEmpty)
        const ValidationIssue(field: 'warehouse_id', message: 'Required.'),
      for (var i = 0; i < lines.length; i++)
        if (lines[i].productId?.trim().isEmpty ?? true)
          ValidationIssue(
            field: 'lines[$i].product_id',
            message: 'A governed product is required.',
          ),
    ]);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null) 'id': id,
    'customer_id': customerId,
    if (contactId != null) 'contact_id': contactId,
    'order_date': _formatDate(orderDate),
    'promised_date': _formatDate(promisedDate),
    'currency_code': currencyCode,
    if (exchangeRateId != null) 'exchange_rate_id': exchangeRateId,
    'exchange_rate': exchangeRate.toDecimalString(),
    'rate_date': _formatDate(rateDate),
    'warehouse_id': warehouseId,
    'payment_terms_days': paymentTermsDays,
    if (deliveryTerms != null) 'delivery_terms': deliveryTerms,
    'ship_to': shipTo,
    if (headerDiscountAmount != null)
      'header_discount_amount': headerDiscountAmount!.toDecimalString(),
    if (headerDiscountPercent != null)
      'header_discount_percent': headerDiscountPercent!.toDecimalString(),
    if (notes != null) 'notes': notes,
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
  };
}

final class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.branchId,
    required this.customerId,
    required this.currencyCode,
    required this.exchangeRate,
    required this.rateDate,
    required this.promisedDate,
    required this.shipTo,
    required this.warehouseId,
    required this.paymentTermsDays,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.baseTotal,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.documentNumber,
    this.sourceQuotationId,
    this.sourceQuotationRevision,
    this.contactId,
    this.deliveryTerms,
    this.confirmedAt,
    this.lines = const <SalesOrderLine>[],
  });

  final String id;
  final String tenantId;
  final String legalEntityId;
  final String branchId;
  final String? documentNumber;
  final String? sourceQuotationId;
  final int? sourceQuotationRevision;
  final String customerId;
  final String? contactId;
  final String currencyCode;
  final ExactDecimal exchangeRate;
  final DateTime rateDate;
  final DateTime promisedDate;
  final Map<String, Object?> shipTo;
  final String warehouseId;
  final int paymentTermsDays;
  final String? deliveryTerms;
  final Money subtotal;
  final Money discountTotal;
  final Money taxTotal;
  final Money grandTotal;
  final Money baseTotal;
  final String status;
  final int version;
  final DateTime? confirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SalesOrderLine> lines;

  factory SalesOrder.fromJson(Map<String, Object?> json) {
    final currency = _requiredString(json, 'currency_code');
    final baseCurrency =
        _optionalString(json, 'base_currency_code') ?? currency;
    return SalesOrder(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      legalEntityId: _requiredString(json, 'legal_entity_id'),
      branchId: _requiredString(json, 'branch_id'),
      documentNumber: _optionalString(json, 'document_number'),
      sourceQuotationId: _optionalString(json, 'source_quotation_id'),
      sourceQuotationRevision: _optionalInt(json, 'source_quotation_revision'),
      customerId: _requiredString(json, 'customer_id'),
      contactId: _optionalString(json, 'contact_id'),
      currencyCode: currency,
      exchangeRate: ExactDecimal.parse(
        _decimalString(json, 'exchange_rate'),
        scale: 10,
      ),
      rateDate: _requiredDate(json, 'rate_date'),
      promisedDate: _requiredDate(json, 'promised_date'),
      shipTo: _requiredMap(json, 'ship_to'),
      warehouseId: _requiredString(json, 'warehouse_id'),
      paymentTermsDays: _requiredInt(json, 'payment_terms_days'),
      deliveryTerms: _optionalString(json, 'delivery_terms'),
      subtotal: Money.parse(_decimalString(json, 'subtotal'), currency),
      discountTotal: Money.parse(
        _decimalString(json, 'discount_total'),
        currency,
      ),
      taxTotal: Money.parse(_decimalString(json, 'tax_total'), currency),
      grandTotal: Money.parse(_decimalString(json, 'grand_total'), currency),
      baseTotal: Money.parse(_decimalString(json, 'base_total'), baseCurrency),
      status: _requiredString(json, 'status'),
      version: _requiredInt(json, 'version'),
      confirmedAt: _optionalTimestamp(json, 'confirmed_at'),
      createdAt: _requiredTimestamp(json, 'created_at'),
      updatedAt: _requiredTimestamp(json, 'updated_at'),
      lines: _optionalMaps(
        json,
        'lines',
      ).map(SalesOrderLine.fromJson).toList(growable: false),
    );
  }
}

final class SalesOrderLine {
  const SalesOrderLine({
    required this.id,
    required this.salesOrderId,
    required this.productId,
    required this.description,
    required this.unitId,
    required this.conversionNumerator,
    required this.conversionDenominator,
    required this.orderedQuantity,
    required this.baseOrderedQuantity,
    required this.cancelledQuantity,
    required this.allocatedQuantity,
    required this.deliveredQuantity,
    required this.invoicedQuantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.version,
    this.sourceQuotationLineId,
    this.sourceQuotationRevision,
  });

  final String id;
  final String salesOrderId;
  final String? sourceQuotationLineId;
  final int? sourceQuotationRevision;
  final String productId;
  final String description;
  final String unitId;
  final BigInt conversionNumerator;
  final BigInt conversionDenominator;
  final ExactDecimal orderedQuantity;
  final ExactDecimal baseOrderedQuantity;
  final ExactDecimal cancelledQuantity;
  final ExactDecimal allocatedQuantity;
  final ExactDecimal deliveredQuantity;
  final ExactDecimal invoicedQuantity;
  final Money unitPrice;
  final Money lineTotal;
  final int version;

  ExactDecimal get remainingToReserve => ExactDecimal.fromScaledValue(
    baseOrderedQuantity.scaledValue -
        cancelledQuantity.scaledValue -
        allocatedQuantity.scaledValue -
        deliveredQuantity.scaledValue,
    scale: 6,
  );

  factory SalesOrderLine.fromJson(Map<String, Object?> json) {
    final currency = _requiredString(json, 'currency_code');
    return SalesOrderLine(
      id: _requiredString(json, 'id'),
      salesOrderId: _requiredString(json, 'sales_order_id'),
      sourceQuotationLineId: _optionalString(json, 'source_quotation_line_id'),
      sourceQuotationRevision: _optionalInt(json, 'source_quotation_revision'),
      productId: _requiredString(json, 'product_id'),
      description: _requiredString(json, 'description'),
      unitId: _requiredString(json, 'unit_id'),
      conversionNumerator: BigInt.parse(
        _requiredString(json, 'conversion_numerator'),
      ),
      conversionDenominator: BigInt.parse(
        _requiredString(json, 'conversion_denominator'),
      ),
      orderedQuantity: ExactDecimal.parse(
        _decimalString(json, 'ordered_quantity'),
        scale: 6,
      ),
      baseOrderedQuantity: ExactDecimal.parse(
        _decimalString(json, 'base_ordered_quantity'),
        scale: 6,
      ),
      cancelledQuantity: ExactDecimal.parse(
        _decimalString(json, 'cancelled_quantity'),
        scale: 6,
      ),
      allocatedQuantity: ExactDecimal.parse(
        _decimalString(json, 'allocated_quantity'),
        scale: 6,
      ),
      deliveredQuantity: ExactDecimal.parse(
        _decimalString(json, 'delivered_quantity'),
        scale: 6,
      ),
      invoicedQuantity: ExactDecimal.parse(
        _decimalString(json, 'invoiced_quantity'),
        scale: 6,
      ),
      unitPrice: Money.parse(_decimalString(json, 'unit_price'), currency),
      lineTotal: Money.parse(_decimalString(json, 'line_total'), currency),
      version: _requiredInt(json, 'version'),
    );
  }
}

final class CreditDecisionSnapshot {
  CreditDecisionSnapshot({
    required this.currencyCode,
    required this.creditLimit,
    required this.dueExposure,
    required this.overdueExposure,
    required this.existingOrderExposure,
    required this.currentOrderExposure,
    required this.overrideApplied,
  }) {
    for (final amount in <Money>[
      creditLimit,
      dueExposure,
      overdueExposure,
      existingOrderExposure,
      currentOrderExposure,
    ]) {
      if (amount.currencyCode != currencyCode) {
        throw StateError('Credit exposure currencies must never be combined.');
      }
    }
  }

  final String currencyCode;
  final Money creditLimit;
  final Money dueExposure;
  final Money overdueExposure;
  final Money existingOrderExposure;
  final Money currentOrderExposure;
  final bool overrideApplied;

  Money get totalExposure =>
      dueExposure + existingOrderExposure + currentOrderExposure;
}

final class StockReservationLineDraft {
  const StockReservationLineDraft({
    required this.salesOrderLineId,
    required this.requestedBaseQuantity,
  });

  final String salesOrderLineId;
  final ExactDecimal requestedBaseQuantity;

  ValidationResult validate() => ValidationResult([
    if (salesOrderLineId.trim().isEmpty)
      const ValidationIssue(field: 'sales_order_line_id', message: 'Required.'),
    if (requestedBaseQuantity.scale != 6 || !requestedBaseQuantity.isPositive)
      const ValidationIssue(
        field: 'requested_base_quantity',
        message: 'A positive six-place quantity is required.',
      ),
  ]);

  Map<String, Object?> toJson() => <String, Object?>{
    'sales_order_line_id': salesOrderLineId,
    'requested_base_quantity': requestedBaseQuantity.toDecimalString(),
  };
}

final class StockReservationDraft {
  const StockReservationDraft({
    required this.salesOrderId,
    required this.expiresAt,
    required this.lines,
  });

  final String salesOrderId;
  final DateTime expiresAt;
  final List<StockReservationLineDraft> lines;

  ValidationResult validate() => ValidationResult([
    if (salesOrderId.trim().isEmpty)
      const ValidationIssue(field: 'sales_order_id', message: 'Required.'),
    if (lines.isEmpty)
      const ValidationIssue(field: 'lines', message: 'Required.'),
    for (var index = 0; index < lines.length; index++)
      for (final issue in lines[index].validate().issues)
        ValidationIssue(
          field: 'lines[$index].${issue.field}',
          message: issue.message,
        ),
  ]);

  Map<String, Object?> toJson() => <String, Object?>{
    'sales_order_id': salesOrderId,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
  };
}

BigInt _roundMoneyUnits(BigInt units, int roundingScale) {
  final divisor = _pow10(Money.scale - roundingScale);
  return _divideRounded(units, divisor) * divisor;
}

BigInt _divideRounded(BigInt numerator, BigInt denominator) {
  if (denominator <= BigInt.zero) {
    throw ArgumentError.value(denominator, 'denominator');
  }
  final quotient = numerator ~/ denominator;
  final remainder = numerator.remainder(denominator).abs();
  if (remainder * BigInt.two < denominator) return quotient;
  return quotient + BigInt.from(numerator.sign);
}

BigInt _pow10(int exponent) => BigInt.from(10).pow(exponent);

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected string for $key.', value);
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Expected string for $key.', value);
  }
  return value;
}

String _decimalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected decimal string for $key.', value);
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw FormatException('Expected integer for $key.', value);
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw FormatException('Expected integer for $key.', value);
}

DateTime _requiredDate(Map<String, Object?> json, String key) =>
    DateTime.parse(_requiredString(json, key)).toUtc();

DateTime _requiredTimestamp(Map<String, Object?> json, String key) =>
    DateTime.parse(_requiredString(json, key)).toUtc();

DateTime? _optionalTimestamp(Map<String, Object?> json, String key) {
  final value = _optionalString(json, key);
  return value == null ? null : DateTime.parse(value).toUtc();
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('Expected object for $key.', value);
  return value.cast<String, Object?>();
}

List<Map<String, Object?>> _optionalMaps(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value == null) return const <Map<String, Object?>>[];
  if (value is! List) throw FormatException('Expected array for $key.', value);
  return value
      .map((item) {
        if (item is! Map) {
          throw FormatException('Expected object in $key.', item);
        }
        return item.cast<String, Object?>();
      })
      .toList(growable: false);
}

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
