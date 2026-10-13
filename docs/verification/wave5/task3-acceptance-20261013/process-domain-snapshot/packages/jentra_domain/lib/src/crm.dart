import 'exact_decimal.dart';
import 'money.dart';
import 'validation.dart';

enum CrmEntryType {
  lead('lead'),
  opportunity('opportunity');

  const CrmEntryType(this.apiValue);

  final String apiValue;

  static CrmEntryType fromApi(Object? value) => values.firstWhere(
    (item) => item.apiValue == value,
    orElse: () => throw FormatException('Invalid CRM entry type.', value),
  );
}

enum CrmAggregateType {
  lead('lead'),
  opportunity('opportunity'),
  party('party'),
  contact('contact');

  const CrmAggregateType(this.apiValue);

  final String apiValue;

  static CrmAggregateType fromApi(Object? value) => values.firstWhere(
    (item) => item.apiValue == value,
    orElse: () => throw FormatException('Invalid CRM aggregate type.', value),
  );
}

final class CrmPipelineQuery {
  CrmPipelineQuery({
    this.search = '',
    this.entryType,
    this.stage,
    this.status,
    this.closingFrom,
    this.closingTo,
    this.cursor,
    this.limit = 50,
  }) {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Expected a value from 1 to 200.',
      );
    }
    if (closingFrom != null &&
        closingTo != null &&
        _dateOnly(closingFrom!).isAfter(_dateOnly(closingTo!))) {
      throw ArgumentError.value(
        closingTo,
        'closingTo',
        'Closing-to date must not precede closing-from date.',
      );
    }
  }

  final String search;
  final CrmEntryType? entryType;
  final String? stage;
  final String? status;
  final DateTime? closingFrom;
  final DateTime? closingTo;
  final String? cursor;
  final int limit;

  String get normalizedSearch => search.trim();

  bool get hasFilters =>
      normalizedSearch.isNotEmpty ||
      entryType != null ||
      (stage?.isNotEmpty ?? false) ||
      (status?.isNotEmpty ?? false) ||
      closingFrom != null ||
      closingTo != null;

  CrmPipelineQuery copyWith({
    String? search,
    CrmEntryType? entryType,
    String? stage,
    String? status,
    DateTime? closingFrom,
    DateTime? closingTo,
    String? cursor,
    int? limit,
    bool clearEntryType = false,
    bool clearStage = false,
    bool clearStatus = false,
    bool clearClosingFrom = false,
    bool clearClosingTo = false,
    bool clearCursor = false,
  }) => CrmPipelineQuery(
    search: search ?? this.search,
    entryType: clearEntryType ? null : entryType ?? this.entryType,
    stage: clearStage ? null : stage ?? this.stage,
    status: clearStatus ? null : status ?? this.status,
    closingFrom: clearClosingFrom ? null : closingFrom ?? this.closingFrom,
    closingTo: clearClosingTo ? null : closingTo ?? this.closingTo,
    cursor: clearCursor ? null : cursor ?? this.cursor,
    limit: limit ?? this.limit,
  );
}

final class CrmPipelineEntry {
  CrmPipelineEntry({
    required this.entryType,
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.code,
    required this.name,
    required this.stage,
    required this.status,
    required this.expectedValue,
    required this.expectedCloseDate,
    required this.stageEnteredAt,
    required this.createdAt,
    this.branchId,
    this.ownerId,
    this.probability,
    this.weightedValue,
    this.lastActivityAt,
  });

  final CrmEntryType entryType;
  final String id;
  final String tenantId;
  final String legalEntityId;
  final String? branchId;
  final String code;
  final String name;
  final String? ownerId;
  final String stage;
  final String status;
  final ExactDecimal? probability;
  final Money expectedValue;
  final Money? weightedValue;
  final DateTime expectedCloseDate;
  final DateTime stageEnteredAt;
  final DateTime createdAt;
  final DateTime? lastActivityAt;

  bool get hasActivity => lastActivityAt != null;

  factory CrmPipelineEntry.fromJson(Map<String, Object?> json) {
    final currencyCode = _requiredString(json, 'currency_code');
    final probability = _optionalDecimalString(json, 'probability');
    final weighted = _optionalDecimalString(json, 'weighted_value');
    return CrmPipelineEntry(
      entryType: CrmEntryType.fromApi(json['entry_type']),
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      legalEntityId: _requiredString(json, 'legal_entity_id'),
      branchId: _optionalString(json, 'branch_id'),
      code: _requiredString(json, 'code'),
      name: _requiredString(json, 'name'),
      ownerId: _optionalString(json, 'owner_id'),
      stage: _requiredString(json, 'stage'),
      status: _requiredString(json, 'status'),
      probability: probability == null
          ? null
          : ExactDecimal.parse(probability, scale: 2),
      expectedValue: Money.parse(
        _decimalString(json, 'expected_value'),
        currencyCode,
      ),
      weightedValue: weighted == null
          ? null
          : Money.parse(weighted, currencyCode),
      expectedCloseDate: _requiredDate(json, 'expected_close_date'),
      stageEnteredAt: _requiredTimestamp(json, 'stage_entered_at'),
      createdAt: _requiredTimestamp(json, 'created_at'),
      lastActivityAt: _optionalTimestamp(json, 'last_activity_at'),
    );
  }
}

final class CrmLead {
  CrmLead({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.code,
    required this.leadType,
    required this.name,
    required this.source,
    required this.ownerId,
    required this.stage,
    required this.expectedValue,
    required this.expectedCloseDate,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.branchId,
    this.contactName,
    this.email,
    this.phone,
    this.partyId,
    this.contactId,
    this.lossReason,
    this.convertedOpportunityId,
  });

  final String id;
  final String tenantId;
  final String legalEntityId;
  final String? branchId;
  final String code;
  final String leadType;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? partyId;
  final String? contactId;
  final String source;
  final String ownerId;
  final String stage;
  final Money expectedValue;
  final DateTime expectedCloseDate;
  final String? lossReason;
  final String status;
  final String? convertedOpportunityId;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CrmLead.fromJson(Map<String, Object?> json) {
    final currencyCode = _requiredString(json, 'currency_code');
    return CrmLead(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      legalEntityId: _requiredString(json, 'legal_entity_id'),
      branchId: _optionalString(json, 'branch_id'),
      code: _requiredString(json, 'code'),
      leadType: _requiredString(json, 'lead_type'),
      name: _requiredString(json, 'name'),
      contactName: _optionalString(json, 'contact_name'),
      email: _optionalString(json, 'email'),
      phone: _optionalString(json, 'phone'),
      partyId: _optionalString(json, 'party_id'),
      contactId: _optionalString(json, 'contact_id'),
      source: _requiredString(json, 'source'),
      ownerId: _requiredString(json, 'owner_id'),
      stage: _requiredString(json, 'stage'),
      expectedValue: Money.parse(
        _decimalString(json, 'expected_value'),
        currencyCode,
      ),
      expectedCloseDate: _requiredDate(json, 'expected_close_date'),
      lossReason: _optionalString(json, 'loss_reason'),
      status: _requiredString(json, 'status'),
      convertedOpportunityId: _optionalString(json, 'converted_opportunity_id'),
      version: _requiredInt(json, 'version'),
      createdAt: _requiredTimestamp(json, 'created_at'),
      updatedAt: _requiredTimestamp(json, 'updated_at'),
    );
  }
}

final class CrmOpportunity {
  CrmOpportunity({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.code,
    required this.ownerId,
    required this.stage,
    required this.probability,
    required this.expectedValue,
    required this.weightedValue,
    required this.expectedCloseDate,
    required this.forecastBucket,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.branchId,
    this.sourceLeadId,
    this.partyId,
    this.contactId,
    this.prospectName,
    this.nextAction,
    this.wonLossReason,
  });

  final String id;
  final String tenantId;
  final String legalEntityId;
  final String? branchId;
  final String code;
  final String? sourceLeadId;
  final String? partyId;
  final String? contactId;
  final String? prospectName;
  final String ownerId;
  final String stage;
  final ExactDecimal probability;
  final Money expectedValue;
  final Money weightedValue;
  final DateTime expectedCloseDate;
  final String? nextAction;
  final String forecastBucket;
  final String? wonLossReason;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CrmOpportunity.fromJson(Map<String, Object?> json) {
    final currencyCode = _requiredString(json, 'currency_code');
    return CrmOpportunity(
      id: _requiredString(json, 'id'),
      tenantId: _requiredString(json, 'tenant_id'),
      legalEntityId: _requiredString(json, 'legal_entity_id'),
      branchId: _optionalString(json, 'branch_id'),
      code: _requiredString(json, 'code'),
      sourceLeadId: _optionalString(json, 'source_lead_id'),
      partyId: _optionalString(json, 'party_id'),
      contactId: _optionalString(json, 'contact_id'),
      prospectName: _optionalString(json, 'prospect_name'),
      ownerId: _requiredString(json, 'owner_id'),
      stage: _requiredString(json, 'stage'),
      probability: ExactDecimal.parse(
        _decimalString(json, 'probability'),
        scale: 2,
      ),
      expectedValue: Money.parse(
        _decimalString(json, 'expected_value'),
        currencyCode,
      ),
      weightedValue: Money.parse(
        _decimalString(json, 'weighted_value'),
        currencyCode,
      ),
      expectedCloseDate: _requiredDate(json, 'expected_close_date'),
      nextAction: _optionalString(json, 'next_action'),
      forecastBucket: _requiredString(json, 'forecast_bucket'),
      wonLossReason: _optionalString(json, 'won_loss_reason'),
      status: _requiredString(json, 'status'),
      version: _requiredInt(json, 'version'),
      createdAt: _requiredTimestamp(json, 'created_at'),
      updatedAt: _requiredTimestamp(json, 'updated_at'),
    );
  }
}

final class CrmActivity {
  CrmActivity({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.aggregateType,
    required this.aggregateId,
    required this.activityType,
    required this.subject,
    required this.ownerId,
    required this.activityAt,
    required this.status,
    required this.version,
    required this.createdAt,
    this.branchId,
    this.dueAt,
    this.completedAt,
    this.outcome,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String legalEntityId;
  final String? branchId;
  final CrmAggregateType aggregateType;
  final String aggregateId;
  final String activityType;
  final String subject;
  final String ownerId;
  final DateTime activityAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? outcome;
  final String? notes;
  final String status;
  final int version;
  final DateTime createdAt;

  factory CrmActivity.fromJson(Map<String, Object?> json) => CrmActivity(
    id: _requiredString(json, 'id'),
    tenantId: _requiredString(json, 'tenant_id'),
    legalEntityId: _requiredString(json, 'legal_entity_id'),
    branchId: _optionalString(json, 'branch_id'),
    aggregateType: CrmAggregateType.fromApi(json['aggregate_type']),
    aggregateId: _requiredString(json, 'aggregate_id'),
    activityType: _requiredString(json, 'activity_type'),
    subject: _requiredString(json, 'subject'),
    ownerId: _requiredString(json, 'owner_id'),
    activityAt: _requiredTimestamp(json, 'activity_at'),
    dueAt: _optionalTimestamp(json, 'due_at'),
    completedAt: _optionalTimestamp(json, 'completed_at'),
    outcome: _optionalString(json, 'outcome'),
    notes: _optionalString(json, 'notes'),
    status: _requiredString(json, 'status'),
    version: _requiredInt(json, 'version'),
    createdAt: _requiredTimestamp(json, 'created_at'),
  );
}

final class CrmLeadConversion {
  CrmLeadConversion({
    required this.leadId,
    required this.partyId,
    required this.contactId,
    required this.opportunityId,
    required this.stage,
    required this.status,
    required this.version,
    this.expectedValue,
  });

  final String leadId;
  final String partyId;
  final String contactId;
  final String opportunityId;
  final String stage;
  final String status;
  final int version;
  final Money? expectedValue;

  factory CrmLeadConversion.fromJson(Map<String, Object?> json) {
    final amount = _optionalDecimalString(json, 'expected_value');
    final currency = _optionalString(json, 'currency_code');
    return CrmLeadConversion(
      leadId: _requiredString(json, 'lead_id'),
      partyId: _requiredString(json, 'party_id'),
      contactId: _requiredString(json, 'contact_id'),
      opportunityId: _requiredString(json, 'opportunity_id'),
      stage: _requiredString(json, 'stage'),
      status: _requiredString(json, 'status'),
      version: _requiredInt(json, 'version'),
      expectedValue: amount == null || currency == null
          ? null
          : Money.parse(amount, currency),
    );
  }
}

final class CrmCurrencyTotal {
  CrmCurrencyTotal({
    required this.currencyCode,
    required this.opportunityCount,
    required this.expectedValue,
    required this.weightedValue,
  });

  final String currencyCode;
  final int opportunityCount;
  final Money expectedValue;
  final Money weightedValue;

  factory CrmCurrencyTotal.fromJson(Map<String, Object?> json) {
    final currency = _requiredString(json, 'currency_code');
    return CrmCurrencyTotal(
      currencyCode: currency,
      opportunityCount: _requiredInt(json, 'opportunity_count'),
      expectedValue: Money.parse(
        _decimalString(json, 'expected_value'),
        currency,
      ),
      weightedValue: Money.parse(
        _decimalString(json, 'weighted_value'),
        currency,
      ),
    );
  }
}

final class CrmStageTotal {
  CrmStageTotal({required this.stage, required this.total});

  final String stage;
  final CrmCurrencyTotal total;

  factory CrmStageTotal.fromJson(Map<String, Object?> json) => CrmStageTotal(
    stage: _requiredString(json, 'stage'),
    total: CrmCurrencyTotal.fromJson(json),
  );
}

final class CrmForecastTotal {
  CrmForecastTotal({required this.forecastBucket, required this.total});

  final String forecastBucket;
  final CrmCurrencyTotal total;

  factory CrmForecastTotal.fromJson(Map<String, Object?> json) =>
      CrmForecastTotal(
        forecastBucket: _requiredString(json, 'forecast_bucket'),
        total: CrmCurrencyTotal.fromJson(json),
      );
}

final class CrmConversionMetrics {
  CrmConversionMetrics({
    required this.totalLeads,
    required this.convertedLeads,
    required this.rate,
  });

  final int totalLeads;
  final int convertedLeads;
  final ExactDecimal rate;

  factory CrmConversionMetrics.fromJson(Map<String, Object?> json) =>
      CrmConversionMetrics(
        totalLeads: _requiredInt(json, 'total_leads'),
        convertedLeads: _requiredInt(json, 'converted_leads'),
        rate: ExactDecimal.parse(
          _decimalString(json, 'conversion_rate'),
          scale: 6,
        ),
      );
}

final class CrmWinLossMetrics {
  CrmWinLossMetrics({
    required this.won,
    required this.lost,
    required this.decided,
  });

  final int won;
  final int lost;
  final int decided;

  factory CrmWinLossMetrics.fromJson(Map<String, Object?> json) =>
      CrmWinLossMetrics(
        won: _requiredInt(json, 'won'),
        lost: _requiredInt(json, 'lost'),
        decided: _requiredInt(json, 'decided'),
      );
}

final class CrmActivityRecency {
  CrmActivityRecency({
    required this.activityCount,
    required this.latestActivityAt,
  });

  final int activityCount;
  final DateTime? latestActivityAt;

  factory CrmActivityRecency.fromJson(Map<String, Object?> json) =>
      CrmActivityRecency(
        activityCount: _requiredInt(json, 'activity_count'),
        latestActivityAt: _optionalTimestamp(json, 'latest_activity_at'),
      );
}

final class CrmAgingMetrics {
  CrmAgingMetrics({
    required this.ageBasis,
    required this.staleAfterDays,
    required this.openOpportunityCount,
    required this.averageAgeDays,
    required this.oldestAgeDays,
    required this.staleOpportunityCount,
  });

  final String ageBasis;
  final int staleAfterDays;
  final int openOpportunityCount;
  final ExactDecimal averageAgeDays;
  final int oldestAgeDays;
  final int staleOpportunityCount;

  factory CrmAgingMetrics.fromJson(Map<String, Object?> json) =>
      CrmAgingMetrics(
        ageBasis: _requiredString(json, 'age_basis'),
        staleAfterDays: _requiredInt(json, 'stale_after_days'),
        openOpportunityCount: _requiredInt(json, 'open_opportunity_count'),
        averageAgeDays: ExactDecimal.parse(
          _decimalString(json, 'average_age_days'),
          scale: 6,
        ),
        oldestAgeDays: _requiredInt(json, 'oldest_age_days'),
        staleOpportunityCount: _requiredInt(json, 'stale_opportunity_count'),
      );
}

final class CrmPipelineSummary {
  CrmPipelineSummary({
    required this.asOfDate,
    required this.currencyTotals,
    required this.stageTotals,
    required this.forecastTotals,
    required this.conversion,
    required this.winLoss,
    required this.activityRecency,
    required this.aging,
  });

  final DateTime asOfDate;
  final List<CrmCurrencyTotal> currencyTotals;
  final List<CrmStageTotal> stageTotals;
  final List<CrmForecastTotal> forecastTotals;
  final CrmConversionMetrics conversion;
  final CrmWinLossMetrics winLoss;
  final CrmActivityRecency activityRecency;
  final CrmAgingMetrics aging;

  CrmCurrencyTotal? currencyTotalFor(String currencyCode) {
    final normalized = currencyCode.trim().toUpperCase();
    for (final total in currencyTotals) {
      if (total.currencyCode == normalized) return total;
    }
    return null;
  }

  factory CrmPipelineSummary.fromJson(Map<String, Object?> json) =>
      CrmPipelineSummary(
        asOfDate: _requiredDate(json, 'as_of_date'),
        currencyTotals: _listOfMaps(
          json,
          'currency_totals',
        ).map(CrmCurrencyTotal.fromJson).toList(growable: false),
        stageTotals: _listOfMaps(
          json,
          'stage_totals',
        ).map(CrmStageTotal.fromJson).toList(growable: false),
        forecastTotals: _listOfMaps(
          json,
          'forecast_totals',
        ).map(CrmForecastTotal.fromJson).toList(growable: false),
        conversion: CrmConversionMetrics.fromJson(_map(json, 'conversion')),
        winLoss: CrmWinLossMetrics.fromJson(_map(json, 'win_loss')),
        activityRecency: CrmActivityRecency.fromJson(
          _map(json, 'activity_recency'),
        ),
        aging: CrmAgingMetrics.fromJson(_map(json, 'aging')),
      );
}

final class CrmLeadDraft {
  CrmLeadDraft({
    required this.code,
    required this.leadType,
    required this.name,
    required this.source,
    required this.ownerId,
    required this.stage,
    required this.expectedValue,
    required this.expectedCloseDate,
    this.id,
    this.contactName,
    this.email,
    this.phone,
    this.partyId,
    this.contactId,
    this.qualificationData = const <String, Object?>{},
    this.lossReason,
    this.transitionReason,
    this.status = 'active',
    this.sourceContext = const {'source': 'jentra_desktop'},
  });

  final String? id;
  final String code;
  final String leadType;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? partyId;
  final String? contactId;
  final String source;
  final String ownerId;
  final String stage;
  final Money expectedValue;
  final DateTime expectedCloseDate;
  final Map<String, Object?> qualificationData;
  final String? lossReason;
  final String? transitionReason;
  final String status;
  final Map<String, Object?> sourceContext;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    final normalizedCode = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_.-]{1,31}$').hasMatch(normalizedCode)) {
      issues.add(
        const ValidationIssue(
          field: 'code',
          message: 'Use 2–32 letters, numbers, dots, dashes, or underscores.',
        ),
      );
    }
    if (!const {'person', 'organization'}.contains(leadType)) {
      issues.add(
        const ValidationIssue(
          field: 'lead_type',
          message: 'Choose person or organization.',
        ),
      );
    }
    if (name.trim().length < 2 || name.trim().length > 180) {
      issues.add(
        const ValidationIssue(
          field: 'name',
          message: 'Enter a name from 2 to 180 characters.',
        ),
      );
    }
    if (source.trim().isEmpty || source.trim().length > 100) {
      issues.add(
        const ValidationIssue(field: 'source', message: 'Enter a lead source.'),
      );
    }
    if (ownerId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(field: 'owner_id', message: 'Choose an owner.'),
      );
    }
    if (!const {
      'draft',
      'submitted',
      'approved',
      'rejected',
      'cancelled',
    }.contains(stage)) {
      issues.add(
        const ValidationIssue(
          field: 'stage',
          message: 'Choose a valid editable lead stage.',
        ),
      );
    }
    if (id == null && stage != 'draft') {
      issues.add(
        const ValidationIssue(
          field: 'stage',
          message: 'A new lead must start in Draft.',
        ),
      );
    }
    if (stage == 'approved' && qualificationData.isEmpty) {
      issues.add(
        const ValidationIssue(
          field: 'qualification_data',
          message: 'Qualification details are required.',
        ),
      );
    }
    if (const {'rejected', 'cancelled'}.contains(stage) &&
        (lossReason?.trim().isEmpty ?? true)) {
      issues.add(
        const ValidationIssue(
          field: 'loss_reason',
          message: 'Explain why this lead was lost.',
        ),
      );
    }
    if (contactId != null && partyId == null) {
      issues.add(
        const ValidationIssue(
          field: 'contact_id',
          message: 'A contact requires its party.',
        ),
      );
    }
    if (email != null && !email!.contains('@')) {
      issues.add(
        const ValidationIssue(
          field: 'email',
          message: 'Enter a valid email address.',
        ),
      );
    }
    if (expectedValue.minorUnits.isNegative) {
      issues.add(
        const ValidationIssue(
          field: 'expected_value',
          message: 'Expected value cannot be negative.',
        ),
      );
    }
    if (!const {'active', 'inactive'}.contains(status)) {
      issues.add(
        const ValidationIssue(
          field: 'status',
          message: 'Choose active or inactive.',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null) 'id': id,
    'code': code.trim().toUpperCase(),
    'lead_type': leadType,
    'name': name.trim(),
    if (contactName?.trim().isNotEmpty ?? false)
      'contact_name': contactName!.trim(),
    if (email?.trim().isNotEmpty ?? false) 'email': email!.trim(),
    if (phone?.trim().isNotEmpty ?? false) 'phone': phone!.trim(),
    if (partyId != null) 'party_id': partyId,
    if (contactId != null) 'contact_id': contactId,
    'source': source.trim(),
    'owner_id': ownerId,
    'stage': stage,
    'expected_value': expectedValue.toDecimalString(),
    'currency_code': expectedValue.currencyCode,
    'expected_close_date': _formatDate(expectedCloseDate),
    'qualification_data': qualificationData,
    if (lossReason?.trim().isNotEmpty ?? false)
      'loss_reason': lossReason!.trim(),
    if (transitionReason?.trim().isNotEmpty ?? false)
      'transition_reason': transitionReason!.trim(),
    'status': status,
    'source_context': sourceContext,
  };
}

final class CrmOpportunityDraft {
  CrmOpportunityDraft({
    required this.code,
    required this.ownerId,
    required this.stage,
    required this.probability,
    required this.expectedValue,
    required this.expectedCloseDate,
    required this.forecastBucket,
    required this.status,
    this.id,
    this.sourceLeadId,
    this.partyId,
    this.contactId,
    this.prospectName,
    this.nextAction,
    this.productsOfInterest = const <Object?>[],
    this.wonLossReason,
    this.transitionReason,
    this.sourceContext = const {'source': 'jentra_desktop'},
  });

  final String? id;
  final String code;
  final String? sourceLeadId;
  final String? partyId;
  final String? contactId;
  final String? prospectName;
  final String ownerId;
  final String stage;
  final ExactDecimal probability;
  final Money expectedValue;
  final DateTime expectedCloseDate;
  final String? nextAction;
  final List<Object?> productsOfInterest;
  final String forecastBucket;
  final String? wonLossReason;
  final String? transitionReason;
  final String status;
  final Map<String, Object?> sourceContext;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    if (!RegExp(
      r'^[A-Z0-9][A-Z0-9_.-]{1,31}$',
    ).hasMatch(code.trim().toUpperCase())) {
      issues.add(
        const ValidationIssue(
          field: 'code',
          message: 'Use a valid opportunity code.',
        ),
      );
    }
    if (partyId == null && (prospectName?.trim().isEmpty ?? true)) {
      issues.add(
        const ValidationIssue(
          field: 'prospect_name',
          message: 'Choose a party or enter a prospect.',
        ),
      );
    }
    if (contactId != null && partyId == null) {
      issues.add(
        const ValidationIssue(
          field: 'contact_id',
          message: 'A contact requires its party.',
        ),
      );
    }
    if (ownerId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(field: 'owner_id', message: 'Choose an owner.'),
      );
    }
    final zero = ExactDecimal.zero(scale: 2);
    final hundred = ExactDecimal.parse('100', scale: 2);
    if (probability.compareTo(zero) < 0 || probability.compareTo(hundred) > 0) {
      issues.add(
        const ValidationIssue(
          field: 'probability',
          message: 'Probability must be from 0 to 100.',
        ),
      );
    }
    if (expectedValue.minorUnits.isNegative) {
      issues.add(
        const ValidationIssue(
          field: 'expected_value',
          message: 'Expected value cannot be negative.',
        ),
      );
    }
    if (!const {
      'pipeline',
      'best_case',
      'commit',
      'closed',
    }.contains(forecastBucket)) {
      issues.add(
        const ValidationIssue(
          field: 'forecast_bucket',
          message: 'Choose a valid forecast bucket.',
        ),
      );
    }
    if (!const {'open', 'won', 'lost', 'inactive'}.contains(status)) {
      issues.add(
        const ValidationIssue(
          field: 'status',
          message: 'Choose a valid opportunity status.',
        ),
      );
    }
    if (const {'won', 'lost'}.contains(status) &&
        (wonLossReason?.trim().isEmpty ?? true)) {
      issues.add(
        const ValidationIssue(
          field: 'won_loss_reason',
          message: 'A won/lost reason is required.',
        ),
      );
    }
    if (status == 'won' &&
        (stage != 'closed' ||
            probability != hundred ||
            forecastBucket != 'closed')) {
      issues.add(
        const ValidationIssue(
          field: 'status',
          message: 'Won opportunities must be closed at 100%.',
        ),
      );
    }
    if (status == 'lost' &&
        (!const {'closed', 'rejected', 'cancelled'}.contains(stage) ||
            probability != zero ||
            forecastBucket != 'closed')) {
      issues.add(
        const ValidationIssue(
          field: 'status',
          message: 'Lost opportunities must be closed at 0%.',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null) 'id': id,
    'code': code.trim().toUpperCase(),
    if (sourceLeadId != null) 'source_lead_id': sourceLeadId,
    if (partyId != null) 'party_id': partyId,
    if (contactId != null) 'contact_id': contactId,
    if (prospectName?.trim().isNotEmpty ?? false)
      'prospect_name': prospectName!.trim(),
    'owner_id': ownerId,
    'stage': stage,
    'probability': probability.toDecimalString(),
    'expected_value': expectedValue.toDecimalString(),
    'currency_code': expectedValue.currencyCode,
    'expected_close_date': _formatDate(expectedCloseDate),
    if (nextAction?.trim().isNotEmpty ?? false)
      'next_action': nextAction!.trim(),
    'products_of_interest': productsOfInterest,
    'forecast_bucket': forecastBucket,
    if (wonLossReason?.trim().isNotEmpty ?? false)
      'won_loss_reason': wonLossReason!.trim(),
    if (transitionReason?.trim().isNotEmpty ?? false)
      'transition_reason': transitionReason!.trim(),
    'status': status,
    'source_context': sourceContext,
  };
}

final class CrmActivityDraft {
  CrmActivityDraft({
    required this.aggregateType,
    required this.aggregateId,
    required this.activityType,
    required this.subject,
    required this.ownerId,
    required this.activityAt,
    required this.status,
    this.id,
    this.dueAt,
    this.completedAt,
    this.outcome,
    this.notes,
    this.sourceContext = const {'source': 'jentra_desktop'},
  });

  final String? id;
  final CrmAggregateType aggregateType;
  final String aggregateId;
  final String activityType;
  final String subject;
  final String ownerId;
  final DateTime activityAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? outcome;
  final String? notes;
  final String status;
  final Map<String, Object?> sourceContext;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    if (aggregateId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          field: 'aggregate_id',
          message: 'Choose a CRM record.',
        ),
      );
    }
    if (!RegExp(r'^[a-z][a-z0-9_.-]{1,39}$').hasMatch(activityType)) {
      issues.add(
        const ValidationIssue(
          field: 'activity_type',
          message: 'Use a valid activity type.',
        ),
      );
    }
    if (subject.trim().length < 2 || subject.trim().length > 180) {
      issues.add(
        const ValidationIssue(
          field: 'subject',
          message: 'Enter a subject from 2 to 180 characters.',
        ),
      );
    }
    if (ownerId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(field: 'owner_id', message: 'Choose an owner.'),
      );
    }
    if (dueAt != null && dueAt!.isBefore(activityAt)) {
      issues.add(
        const ValidationIssue(
          field: 'due_at',
          message: 'Due time cannot precede activity time.',
        ),
      );
    }
    if (!const {'planned', 'completed', 'cancelled'}.contains(status)) {
      issues.add(
        const ValidationIssue(
          field: 'status',
          message: 'Choose planned, completed, or cancelled.',
        ),
      );
    }
    if (status == 'completed') {
      if (completedAt == null) {
        issues.add(
          const ValidationIssue(
            field: 'completed_at',
            message: 'Completion time is required.',
          ),
        );
      }
      if (outcome?.trim().isEmpty ?? true) {
        issues.add(
          const ValidationIssue(
            field: 'outcome',
            message: 'Outcome is required.',
          ),
        );
      }
    } else if (completedAt != null) {
      issues.add(
        const ValidationIssue(
          field: 'completed_at',
          message: 'Only completed activities have a completion time.',
        ),
      );
    }
    if (completedAt != null && completedAt!.isBefore(activityAt)) {
      issues.add(
        const ValidationIssue(
          field: 'completed_at',
          message: 'Completion cannot precede activity time.',
        ),
      );
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (id != null) 'id': id,
    'aggregate_type': aggregateType.apiValue,
    'aggregate_id': aggregateId,
    'activity_type': activityType,
    'subject': subject.trim(),
    'owner_id': ownerId,
    'activity_at': activityAt.toUtc().toIso8601String(),
    if (dueAt != null) 'due_at': dueAt!.toUtc().toIso8601String(),
    if (completedAt != null)
      'completed_at': completedAt!.toUtc().toIso8601String(),
    if (outcome?.trim().isNotEmpty ?? false) 'outcome': outcome!.trim(),
    if (notes?.isNotEmpty ?? false) 'notes': notes,
    'status': status,
    'source_context': sourceContext,
  };
}

final class CrmLeadConversionDraft {
  CrmLeadConversionDraft({
    required this.leadId,
    this.partyId,
    this.contactId,
    this.partyCode,
    this.contactName,
    this.contactRole,
    this.opportunityCode,
    this.probability,
    this.nextAction,
    this.productsOfInterest = const <Object?>[],
    this.conversionReason,
    this.sourceContext = const {'source': 'jentra_desktop'},
  });

  final String leadId;
  final String? partyId;
  final String? contactId;
  final String? partyCode;
  final String? contactName;
  final String? contactRole;
  final String? opportunityCode;
  final ExactDecimal? probability;
  final String? nextAction;
  final List<Object?> productsOfInterest;
  final String? conversionReason;
  final Map<String, Object?> sourceContext;

  ValidationResult validate() {
    final issues = <ValidationIssue>[];
    if (leadId.trim().isEmpty) {
      issues.add(
        const ValidationIssue(
          field: 'lead_id',
          message: 'Choose a qualified lead.',
        ),
      );
    }
    if (contactId != null && partyId == null) {
      issues.add(
        const ValidationIssue(
          field: 'contact_id',
          message: 'A selected contact requires its party.',
        ),
      );
    }
    if (opportunityCode != null &&
        !RegExp(
          r'^[A-Z0-9][A-Z0-9_.-]{1,31}$',
        ).hasMatch(opportunityCode!.trim().toUpperCase())) {
      issues.add(
        const ValidationIssue(
          field: 'opportunity_code',
          message: 'Use a valid opportunity code.',
        ),
      );
    }
    if (probability != null) {
      final zero = ExactDecimal.zero(scale: 2);
      final hundred = ExactDecimal.parse('100', scale: 2);
      if (probability!.compareTo(zero) < 0 ||
          probability!.compareTo(hundred) > 0) {
        issues.add(
          const ValidationIssue(
            field: 'opportunity_probability',
            message: 'Probability must be from 0 to 100.',
          ),
        );
      }
    }
    return ValidationResult(issues);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'lead_id': leadId,
    if (partyId != null) 'party_id': partyId,
    if (contactId != null) 'contact_id': contactId,
    if (partyCode?.trim().isNotEmpty ?? false)
      'party_code': partyCode!.trim().toUpperCase(),
    if (contactName?.trim().isNotEmpty ?? false)
      'contact_name': contactName!.trim(),
    if (contactRole?.trim().isNotEmpty ?? false)
      'contact_role': contactRole!.trim(),
    if (opportunityCode?.trim().isNotEmpty ?? false)
      'opportunity_code': opportunityCode!.trim().toUpperCase(),
    if (probability != null)
      'opportunity_probability': probability!.toDecimalString(),
    if (nextAction?.trim().isNotEmpty ?? false)
      'next_action': nextAction!.trim(),
    'products_of_interest': productsOfInterest,
    if (conversionReason?.trim().isNotEmpty ?? false)
      'conversion_reason': conversionReason!.trim(),
    'source_context': sourceContext,
  };
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected non-empty string for $key.', value);
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Expected string or null for $key.', value);
  }
  return value.isEmpty ? null : value;
}

String _decimalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected decimal string for $key.', value);
  }
  return value;
}

String? _optionalDecimalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Expected decimal string or null for $key.', value);
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Expected integer for $key.', value);
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected YYYY-MM-DD string for $key.', value);
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw FormatException('Expected YYYY-MM-DD string for $key.', value);
  }
  final date = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (_formatDate(date) != value) {
    throw FormatException('Invalid calendar date for $key.', value);
  }
  return date;
}

DateTime _requiredTimestamp(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('Expected RFC 3339 timestamp for $key.', value);
}

DateTime? _optionalTimestamp(Map<String, Object?> json, String key) {
  if (json[key] == null) return null;
  return _requiredTimestamp(json, key);
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('Expected object for $key.', value);
  }
  return value.cast<String, Object?>();
}

List<Map<String, Object?>> _listOfMaps(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Expected array for $key.', value);
  }
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
