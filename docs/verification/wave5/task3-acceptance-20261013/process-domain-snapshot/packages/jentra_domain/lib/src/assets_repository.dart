import 'dart:convert';
import 'calendar_repository.dart';
import 'commands.dart';
import 'employee.dart';
import 'fixed_asset_schedule.dart';
import 'money.dart';
import 'tenant_context.dart';
import 'workforce.dart';

const assetCapabilities = {
  'assets.view',
  'assets.configure',
  'assets.prepare',
  'assets.approve',
  'assets.post',
  'assets.depreciate',
  'assets.reverse',
  'assets.transfer',
};
const assetProposalKinds = {
  'capitalize',
  'book_revision',
  'transfer',
  'impair',
  'revalue',
  'dispose',
};
Map<String, Object?> assetMap(Object? value) => workforceMap(value);
String assetText(Object? value, int max) {
  final text = workforceText(value, max);
  if (text != text.trim() || RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
    throw const FormatException(
      'Asset text must be trimmed and contain no controls.',
    );
  }
  return text;
}

String assetCode(Object? value) {
  final code = assetText(value, 32);
  if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code)) {
    throw const FormatException('Asset code is invalid.');
  }
  return code;
}

String? assetOptionalId(Object? value) =>
    value == null ? null : calendarUuid(value);
String assetDigest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Asset digest is invalid.');
  }
  return value;
}

String _status(Object? value) {
  if (!{'draft', 'active', 'disposed', 'reversed'}.contains(value)) {
    throw const FormatException('Asset status is invalid.');
  }
  return value as String;
}

void assertAssetScope(
  Map<String, Object?> row,
  TenantContext scope, {
  bool branch = true,
}) {
  if (row['tenant_id'] != scope.tenantId ||
      row['legal_entity_id'] != scope.legalEntityId ||
      branch && row['branch_id'] != scope.branchId) {
    throw const FormatException('Asset response scope changed.');
  }
}

Map<String, Object?> _copy(String wire) =>
    Map<String, Object?>.from(jsonDecode(wire) as Map);

final class AssetRecord {
  AssetRecord.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      tenantId = calendarUuid(row['tenant_id']),
      entityId = calendarUuid(row['legal_entity_id']),
      branchId = calendarUuid(row['branch_id']),
      originalBranchId = calendarUuid(row['original_branch_id']),
      code = assetCode(row['code']),
      name = assetText(row['name'], 160),
      ownership = assetText(row['ownership'], 160),
      currency = row['currency_code'] as String,
      inService = CivilDate.parse(row['in_service'] as String),
      locationId = calendarUuid(row['location_id']),
      custodianId = assetOptionalId(row['custodian_id']),
      status = _status(row['status']),
      version = workforceInteger(row['version'], positive: true),
      cost = assetAmount(row['cost'] as String, row['currency_code'] as String),
      accumulated = assetAmount(
        row['accumulated'] as String,
        row['currency_code'] as String,
      ),
      impairment = assetAmount(
        row['impairment'] as String,
        row['currency_code'] as String,
      ),
      carrying = assetAmount(
        row['carrying'] as String,
        row['currency_code'] as String,
      ),
      costAccountId = calendarUuid(row['cost_account_id']),
      accumulatedAccountId = calendarUuid(row['accumulated_account_id']),
      impairmentAccountId = calendarUuid(row['impairment_account_id']),
      bookId = assetOptionalId(row['book_id']),
      proposalId = assetOptionalId(row['proposal_id']),
      lastEffectId = assetOptionalId(row['last_effect_id']),
      postedPeriods = workforceInteger(row['posted_periods']),
      _wire = jsonEncode(row) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'original_branch_id',
      'code',
      'name',
      'ownership',
      'currency_code',
      'in_service',
      'location_id',
      'custodian_id',
      'status',
      'version',
      'cost',
      'accumulated',
      'impairment',
      'carrying',
      'cost_account_id',
      'accumulated_account_id',
      'impairment_account_id',
      'book_id',
      'proposal_id',
      'posted_periods',
      'last_effect_id',
    });
    if (cost.minorUnits < accumulated.minorUnits + impairment.minorUnits ||
        cost - accumulated - impairment != carrying ||
        postedPeriods > 1200 ||
        {costAccountId, accumulatedAccountId, impairmentAccountId}.length !=
            3 ||
        {'active', 'disposed'}.contains(status) &&
            (bookId == null || cost.minorUnits <= BigInt.zero) ||
        {'draft', 'reversed'}.contains(status) &&
            (bookId != null ||
                cost.minorUnits != BigInt.zero ||
                postedPeriods != 0)) {
      throw const FormatException(
        'Asset book/state or exact carrying changed.',
      );
    }
  }
  final String id,
      tenantId,
      entityId,
      branchId,
      originalBranchId,
      code,
      name,
      ownership,
      currency,
      locationId,
      status;
  final String costAccountId, accumulatedAccountId, impairmentAccountId, _wire;
  final String? custodianId, bookId, proposalId, lastEffectId;
  final CivilDate inService;
  final int version, postedPeriods;
  final Money cost, accumulated, impairment, carrying;
  Map<String, Object?> toJson() => _copy(_wire);
}

const assetBookInputFields = {
  'residual',
  'remaining_months',
  'method',
  'convention',
  'rate_numerator',
  'rate_denominator',
  'precision',
  'expense_account_id',
};
AssetBookBasis _bookInput(
  Map<String, Object?> row, {
  required Money cost,
  required Money accumulated,
  required Money impairment,
  required CivilDate inService,
  CivilDate? start,
}) {
  final method = switch (row['method']) {
    'straight_line' => AssetDepreciationMethod.straightLine,
    'reducing_balance' => AssetDepreciationMethod.reducingBalance,
    _ => throw const FormatException('Asset method is unsupported.'),
  };
  final convention = switch (row['convention']) {
    'in_service_month' => AssetMonthConvention.inServiceMonth,
    'next_month' => AssetMonthConvention.nextMonth,
    _ => throw const FormatException('Asset convention is unsupported.'),
  };
  calendarUuid(row['expense_account_id']);
  return AssetBookBasis(
    cost: cost,
    openingAccumulated: accumulated,
    openingImpairment: impairment,
    residual: assetAmount(row['residual'] as String, cost.currencyCode),
    remainingMonths: workforceInteger(row['remaining_months'], positive: true),
    precision: workforceInteger(row['precision']),
    method: method,
    convention: convention,
    inService: inService,
    scheduleStart: start,
    rateNumerator: workforceInteger(row['rate_numerator'], positive: true),
    rateDenominator: workforceInteger(row['rate_denominator'], positive: true),
  );
}

final class AssetBookDefinition {
  AssetBookDefinition.fromJson(Map<String, Object?> row)
    : _wire = jsonEncode(row),
      expenseAccountId = calendarUuid(row['expense_account_id']) {
    calendarFields(row, {
      ...assetBookInputFields,
      'cost',
      'opening_accumulated',
      'opening_impairment',
      'start_date',
      'in_service',
      'currency_code',
    });
    basis = _bookInput(
      row,
      cost: assetAmount(row['cost'] as String, row['currency_code'] as String),
      accumulated: assetAmount(
        row['opening_accumulated'] as String,
        row['currency_code'] as String,
      ),
      impairment: assetAmount(
        row['opening_impairment'] as String,
        row['currency_code'] as String,
      ),
      inService: CivilDate.parse(row['in_service'] as String),
      start: CivilDate.parse(row['start_date'] as String),
    );
    schedule = calculateAssetSchedule(basis);
  }
  final String _wire, expenseAccountId;
  late final AssetBookBasis basis;
  late final AssetSchedule schedule;
  Map<String, Object?> toJson() => _copy(_wire);
}

final class AssetBook {
  AssetBook.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      assetId = calendarUuid(row['asset_id']),
      version = workforceInteger(row['version'], positive: true),
      reason = assetText(row['reason'], 1000),
      actorId = calendarUuid(row['created_by']),
      recordedAt = workforceRecorded(row['created_at']),
      definition = AssetBookDefinition.fromJson(assetMap(row['basis'])) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'asset_id',
      'version',
      'basis',
      'reason',
      'created_by',
      'created_at',
    });
    calendarUuid(row['tenant_id']);
    calendarUuid(row['legal_entity_id']);
  }
  final String id, assetId, reason, actorId;
  final int version;
  final DateTime recordedAt;
  final AssetBookDefinition definition;
}

final class AssetState {
  AssetState.fromJson(Map<String, Object?> row, String currency)
    : branchId = calendarUuid(row['branch_id']),
      locationId = calendarUuid(row['location_id']),
      custodianId = assetOptionalId(row['custodian_id']),
      status = _status(row['status']),
      cost = assetAmount(row['cost'] as String, currency),
      accumulated = assetAmount(row['accumulated'] as String, currency),
      impairment = assetAmount(row['impairment'] as String, currency),
      bookId = assetOptionalId(row['book_id']),
      lastEffectId = assetOptionalId(row['last_effect_id']),
      postedPeriods = workforceInteger(row['posted_periods']) {
    calendarFields(row, {
      'branch_id',
      'location_id',
      'custodian_id',
      'status',
      'cost',
      'accumulated',
      'impairment',
      'book_id',
      'posted_periods',
      'last_effect_id',
    });
    if (cost.minorUnits < accumulated.minorUnits + impairment.minorUnits ||
        postedPeriods > 1200) {
      throw const FormatException('Asset effect balances are invalid.');
    }
  }
  final String branchId, locationId, status;
  final String? custodianId, bookId, lastEffectId;
  final int postedPeriods;
  final Money cost, accumulated, impairment;
  Money get carrying => cost - accumulated - impairment;
}

final class AssetApproval {
  AssetApproval.fromJson(Map<String, Object?> row)
    : proposalId = calendarUuid(row['proposal_id']),
      assetId = calendarUuid(row['asset_id']),
      digest = assetDigest(row['digest']),
      actorId = calendarUuid(row['approved_by']),
      reason = assetText(row['reason'], 1000),
      recordedAt = workforceRecorded(row['approved_at']) {
    calendarFields(row, {
      'proposal_id',
      'tenant_id',
      'legal_entity_id',
      'asset_id',
      'digest',
      'approved_by',
      'reason',
      'approved_at',
    });
    calendarUuid(row['tenant_id']);
    calendarUuid(row['legal_entity_id']);
  }
  final String proposalId, assetId, digest, actorId, reason;
  final DateTime recordedAt;
}

final class AssetProposal {
  AssetProposal.fromJson(Map<String, Object?> row, String currency)
    : id = calendarUuid(row['id']),
      assetId = calendarUuid(row['asset_id']),
      branchId = calendarUuid(row['branch_id']),
      kind = assetText(row['kind'], 20),
      digest = assetDigest(row['digest']),
      postingDate = CivilDate.parse(row['posting_date'] as String),
      reason = assetText(row['reason'], 1000),
      actorId = calendarUuid(row['prepared_by']),
      recordedAt = workforceRecorded(row['prepared_at']),
      approval = row['approval'] == null
          ? null
          : AssetApproval.fromJson(assetMap(row['approval'])),
      _wire = jsonEncode(row['data']) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'asset_id',
      'branch_id',
      'kind',
      'data',
      'digest',
      'posting_date',
      'reason',
      'prepared_by',
      'prepared_at',
      'approval',
    });
    calendarUuid(row['tenant_id']);
    calendarUuid(row['legal_entity_id']);
    if (!assetProposalKinds.contains(kind)) {
      throw const FormatException('Asset proposal kind is invalid.');
    }
    final p = data;
    final fields = switch (kind) {
      'capitalize' => {'book', 'source_id', 'offset_account_id'},
      'book_revision' => {'book', 'before'},
      'transfer' => {'branch_id', 'location_id', 'custodian_id', 'before'},
      'impair' => {'book', 'amount', 'loss_account_id', 'before'},
      'revalue' => {
        'book',
        'cost',
        'surplus_account_id',
        'loss_account_id',
        'before',
      },
      _ => {
        'proceeds',
        'proceeds_account_id',
        'gain_account_id',
        'loss_account_id',
        'cost',
        'accumulated',
        'impairment',
        'carrying',
        'gain_loss',
        'before',
      },
    };
    calendarFields(p, fields);
    for (final field in fields.where((k) => k.endsWith('_id'))) {
      if (field != 'custodian_id' || p[field] != null) {
        calendarUuid(p[field]);
      }
    }
    before = p['before'] == null
        ? null
        : AssetState.fromJson(assetMap(p['before']), currency);
    book = p['book'] == null
        ? null
        : AssetBookDefinition.fromJson(assetMap(p['book']));
    if (book != null) {
      if (book!.basis.currency != currency) {
        throw const FormatException('Asset proposal currency changed.');
      }
    }
    if (kind == 'impair' &&
        assetAmount(p['amount'] as String, currency).minorUnits <=
            BigInt.zero) {
      throw const FormatException('Asset impairment is invalid.');
    }
    if (kind == 'dispose') {
      final calculation = calculateAssetDisposal(
        cost: assetAmount(p['cost'] as String, currency),
        accumulated: assetAmount(p['accumulated'] as String, currency),
        impairment: assetAmount(p['impairment'] as String, currency),
        proceeds: assetAmount(p['proceeds'] as String, currency),
      );
      if (calculation.carrying.toDecimalString() != p['carrying'] ||
          calculation.gainLoss.toDecimalString() != p['gain_loss'] ||
          calculation.cost != before!.cost ||
          calculation.accumulated != before!.accumulated ||
          calculation.impairment != before!.impairment) {
        throw const FormatException(
          'Asset disposal does not reconcile its original basis.',
        );
      }
    }
    if (approval != null &&
        (approval!.proposalId != id ||
            approval!.assetId != assetId ||
            approval!.digest != digest ||
            approval!.actorId == actorId)) {
      throw const FormatException(
        'Asset approval does not match the independent exact proposal.',
      );
    }
  }
  final String id, assetId, branchId, kind, digest, reason, actorId, _wire;
  final CivilDate postingDate;
  final DateTime recordedAt;
  final AssetApproval? approval;
  late final AssetBookDefinition? book;
  late final AssetState? before;
  Map<String, Object?> get data => _copy(_wire);
}

final class AssetEffect {
  AssetEffect.fromJson(Map<String, Object?> row, String currency)
    : id = calendarUuid(row['id']),
      assetId = calendarUuid(row['asset_id']),
      branchId = calendarUuid(row['branch_id']),
      kind = assetText(row['kind'], 20),
      proposalId = assetOptionalId(row['proposal_id']),
      bookId = assetOptionalId(row['book_id']),
      originalEffectId = assetOptionalId(row['original_effect_id']),
      priorEffectId = assetOptionalId(row['prior_effect_id']),
      journalId = assetOptionalId(row['journal_id']),
      periodIndex = row['period_index'] == null
          ? null
          : workforceInteger(row['period_index'], positive: true),
      postingDate = CivilDate.parse(row['posting_date'] as String),
      before = AssetState.fromJson(assetMap(row['before_context']), currency),
      after = AssetState.fromJson(assetMap(row['after_context']), currency),
      reason = assetText(row['reason'], 1000),
      actorId = calendarUuid(row['recorded_by']),
      recordedAt = workforceRecorded(row['recorded_at']) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'asset_id',
      'branch_id',
      'kind',
      'proposal_id',
      'book_id',
      'period_index',
      'posting_date',
      'original_effect_id',
      'prior_effect_id',
      'journal_id',
      'before_context',
      'after_context',
      'reason',
      'recorded_by',
      'recorded_at',
    });
    calendarUuid(row['tenant_id']);
    calendarUuid(row['legal_entity_id']);
    if (!{...assetProposalKinds, 'depreciate', 'reverse'}.contains(kind) ||
        (kind == 'reverse') != (originalEffectId != null) ||
        (kind == 'depreciate') != (periodIndex != null) ||
        (periodIndex ?? 0) > 1200) {
      throw const FormatException('Asset effect attribution is invalid.');
    }
    if (kind == 'depreciate') {
      final amount = after.accumulated - before.accumulated;
      if (before.cost != after.cost ||
          before.impairment != after.impairment ||
          amount.minorUnits < BigInt.zero ||
          after.postedPeriods != before.postedPeriods + 1 ||
          before.bookId != after.bookId ||
          bookId != after.bookId ||
          (amount.minorUnits == BigInt.zero) != (journalId == null)) {
        throw const FormatException(
          'Asset depreciation effect does not conserve its original basis.',
        );
      }
    }
  }
  final String id, assetId, branchId, kind, reason, actorId;
  final String? proposalId, bookId, originalEffectId, priorEffectId, journalId;
  final int? periodIndex;
  final CivilDate postingDate;
  final DateTime recordedAt;
  final AssetState before, after;
}

final class AssetOpening {
  AssetOpening.fromJson(Map<String, Object?> row, String currency)
    : id = calendarUuid(row['id']),
      assetId = calendarUuid(row['asset_id']),
      reference = assetText(row['source_reference'], 160),
      cost = assetAmount(row['cost'] as String, currency),
      accumulated = assetAmount(row['opening_accumulated'] as String, currency),
      reason = assetText(row['reason'], 1000),
      actorId = calendarUuid(row['recorded_by']),
      recordedAt = workforceRecorded(row['recorded_at']),
      _wire = jsonEncode(row['components']) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'asset_id',
      'source_reference',
      'cost',
      'opening_accumulated',
      'components',
      'reason',
      'recorded_by',
      'recorded_at',
    });
    calendarUuid(row['tenant_id']);
    calendarUuid(row['legal_entity_id']);
    AssetCommands.components(row['components'], cost);
    if (reference != reference.toUpperCase() ||
        cost.minorUnits <= BigInt.zero ||
        accumulated.minorUnits > cost.minorUnits) {
      throw const FormatException('Asset opening is invalid.');
    }
  }
  final String id, assetId, reference, reason, actorId, _wire;
  final DateTime recordedAt;
  final Money cost, accumulated;
  List<Map<String, Object?>> get components => List.unmodifiable(
    (jsonDecode(_wire) as List).map((x) => Map<String, Object?>.from(x as Map)),
  );
}

final class AssetPicker {
  AssetPicker.fromJson(Map<String, Object?> row, this.kind)
    : id = calendarUuid(row['id']),
      code = assetCode(row['code']),
      name = assetText(row['name'], 160),
      currency = row['currency_code'] as String?,
      version = row['version'] == null
          ? null
          : workforceInteger(row['version'], positive: true) {
    calendarFields(row, {
      'id',
      'code',
      'name',
      if (!{'locations', 'custodians'}.contains(kind)) ...{
        'kind',
        'currency_code',
        'version',
      },
    });
    if (!{'locations', 'custodians'}.contains(kind) &&
        (row['kind'] != kind ||
            version == null ||
            currency != null && !RegExp(r'^[A-Z]{3}$').hasMatch(currency!))) {
      throw const FormatException('Asset account picker changed.');
    }
  }
  final String id, code, name, kind;
  final String? currency;
  final int? version;
}

enum AssetHistoryKind { books, effects, proposals }

const assetDetailLabelFields = {
  'cost_account_id',
  'accumulated_account_id',
  'impairment_account_id',
  'location_id',
  'custodian_id',
  'branch_id',
  'expense_account_id',
  'offset_account_id',
  'loss_account_id',
  'surplus_account_id',
  'proceeds_account_id',
  'gain_account_id',
  'destination_branch_id',
  'destination_location_id',
  'destination_custodian_id',
};

final class AssetPage<T> {
  const AssetPage(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

final class AssetDetail {
  const AssetDetail({
    required this.asset,
    required this.kind,
    required this.opening,
    this.proposal,
    this.books = const [],
    this.effects = const [],
    this.proposals = const [],
    this.nextCursor,
    this.labels = const {},
  });
  final AssetRecord asset;
  final AssetHistoryKind kind;
  final AssetOpening opening;
  final AssetProposal? proposal;
  final List<AssetBook> books;
  final List<AssetEffect> effects;
  final List<AssetProposal> proposals;
  final String? nextCursor;
  final Map<String, String?> labels;
}

final class AssetSchedulePage {
  const AssetSchedulePage(
    this.bookId,
    this.definition,
    this.periods,
    this.nextCursor,
  );
  final String bookId;
  final AssetBookDefinition definition;
  final List<AssetSchedulePeriod> periods;
  final int? nextCursor;
}

final class AssetProviderState {
  const AssetProviderState({
    required this.procurement,
    required this.stock,
    required this.equipment,
    required this.currency,
    required this.precision,
    required this.businessDate,
  });
  final bool procurement, stock, equipment;
  final String currency;
  final int precision;
  final CivilDate businessDate;
}

final class AssetCommands {
  static const _base = {'action', 'id', 'reason'};
  static const _proposal = {'proposal_id', 'digest'};
  static Set<String> fields(String action) => switch (action) {
    'location' => {..._base, 'code', 'name'},
    'opening' => {
      ..._base,
      'proposal_id',
      'source_id',
      'source_reference',
      'code',
      'name',
      'ownership',
      'in_service',
      'location_id',
      'custodian_id',
      'cost',
      'opening_accumulated',
      'cost_components',
      'cost_account_id',
      'accumulated_account_id',
      'impairment_account_id',
      'offset_account_id',
      'book',
      'posting_date',
      'currency_code',
    },
    'propose' => {
      ..._base,
      'proposal_id',
      'kind',
      'book',
      'destination_branch_id',
      'location_id',
      'custodian_id',
      'amount',
      'cost',
      'surplus_account_id',
      'loss_account_id',
      'proceeds',
      'proceeds_account_id',
      'gain_account_id',
      'posting_date',
    },
    'approve' || 'post' || 'cancel' => {..._base, ..._proposal},
    'depreciate' => {..._base, 'book_id', 'period_index'},
    'reverse' => {..._base, 'effect_id'},
    _ => throw const FormatException('Asset action is unsupported.'),
  };
  static String capability(String action) => switch (action) {
    'location' => 'assets.configure',
    'opening' || 'propose' || 'cancel' => 'assets.prepare',
    'approve' => 'assets.approve',
    'post' => 'assets.post',
    'depreciate' => 'assets.depreciate',
    'reverse' => 'assets.reverse',
    _ => throw const FormatException('Asset action is unsupported.'),
  };
  static void components(Object? raw, Money cost) {
    if (raw is! List || raw.isEmpty || raw.length > 50) {
      throw const FormatException('Asset cost components are bounded to 50.');
    }
    final codes = <String>{};
    var sum = Money.zero(cost.currencyCode);
    for (final item in raw) {
      final row = assetMap(item);
      calendarFields(row, {'code', 'name', 'amount'});
      if (!codes.add(assetCode(row['code']))) {
        throw const FormatException('Asset cost component codes repeat.');
      }
      assetText(row['name'], 160);
      if (row['amount'] is! String) {
        throw const FormatException('Asset amounts require decimal strings.');
      }
      sum += assetAmount(row['amount'] as String, cost.currencyCode);
    }
    if (sum != cost) {
      throw const FormatException(
        'Asset components do not conserve source cost.',
      );
    }
  }

  static void validate(String action, Map<String, Object?> p) {
    final allow = fields(action);
    if (p['action'] != action ||
        p.keys.any((k) => !allow.contains(k)) ||
        utf8.encode(jsonEncode(p)).length > 65536) {
      throw const FormatException('Asset command fields are invalid.');
    }
    calendarUuid(p['id']);
    assetText(p['reason'], 1000);
    var required = allow;
    if (action == 'propose') {
      required = {
        ..._base,
        'proposal_id',
        'kind',
        'posting_date',
        ...switch (p['kind']) {
          'book_revision' => {'book'},
          'transfer' => {
            'destination_branch_id',
            'location_id',
            'custodian_id',
          },
          'impair' => {'amount', 'loss_account_id'},
          'revalue' => {'cost', 'surplus_account_id', 'loss_account_id'},
          'dispose' => {
            'proceeds',
            'proceeds_account_id',
            'gain_account_id',
            'loss_account_id',
          },
          _ => throw const FormatException(
            'Asset proposal kind is unsupported.',
          ),
        },
      };
    }
    calendarFields(p, required);
    for (final key in {
      'amount',
      'cost',
      'opening_accumulated',
      'proceeds',
    }.where(p.containsKey)) {
      if (p[key] is! String) {
        throw const FormatException('Asset amounts require decimal strings.');
      }
    }
    for (final key in required.where((x) => x.endsWith('_id'))) {
      if (key != 'custodian_id' || p[key] != null) {
        calendarUuid(p[key]);
      }
    }
    if (required.contains('posting_date')) {
      CivilDate.parse(p['posting_date'] as String);
    }
    if (action == 'location' || action == 'opening') {
      assetCode(p['code']);
      assetText(p['name'], 160);
    }
    if (action == 'opening') {
      assetAmount('0', p['currency_code'] as String);
      assetText(p['source_reference'], 160);
      assetText(p['ownership'], 160);
      final cost = assetAmount(p['cost'] as String, 'XXX');
      final accum = assetAmount(p['opening_accumulated'] as String, 'XXX');
      components(p['cost_components'], cost);
      final book = assetMap(p['book']);
      calendarFields(book, assetBookInputFields);
      _bookInput(
        book,
        cost: cost,
        accumulated: accum,
        impairment: Money.zero('XXX'),
        inService: CivilDate.parse(p['in_service'] as String),
      );
      if (CivilDate.parse(
                p['posting_date'] as String,
              ).compareTo(CivilDate.parse(p['in_service'] as String)) <
              0 ||
          {
                p['cost_account_id'],
                p['accumulated_account_id'],
                p['impairment_account_id'],
              }.length !=
              3) {
        throw const FormatException(
          'Asset opening date or mappings are invalid.',
        );
      }
    }
    if (action == 'propose') {
      if (p['kind'] == 'book_revision') {
        final book = assetMap(p['book']);
        calendarFields(book, assetBookInputFields);
        final precision = workforceInteger(book['precision']);
        if (precision > 6) {
          throw const FormatException('Asset precision is invalid.');
        }
        final quantum = BigInt.from(10).pow(6 - precision);
        final maximum = BigInt.parse('99999999999999999999');
        _bookInput(
          book,
          cost: Money.fromMinorUnits(maximum ~/ quantum * quantum, 'XXX'),
          accumulated: Money.zero('XXX'),
          impairment: Money.zero('XXX'),
          inService: CivilDate.parse('2000-01-01'),
        );
      }
      for (final key in ['amount', 'cost', 'proceeds'].where(p.containsKey)) {
        final amount = assetAmount(p[key] as String, 'XXX');
        if (key != 'proceeds' && amount.minorUnits <= BigInt.zero) {
          throw const FormatException('Asset change amount must be positive.');
        }
      }
    }
    if (required.contains('digest')) {
      assetDigest(p['digest']);
    }
    if (action == 'depreciate' &&
        workforceInteger(p['period_index'], positive: true) > 1200) {
      throw const FormatException('Asset period index is invalid.');
    }
  }
}

abstract interface class AssetRepository {
  Future<AssetProviderState> authorize(TenantContext scope, String capability);
  Future<AssetPage<AssetRecord>> register(TenantContext scope, {String? after});
  Future<AssetDetail> detail(
    TenantContext scope,
    String assetId,
    AssetHistoryKind kind, {
    String? after,
  });
  Future<AssetSchedulePage> schedule(
    TenantContext scope,
    String assetId,
    String bookId, {
    int after = 0,
  });
  Future<AssetPage<AssetPicker>> pickers(
    TenantContext scope,
    String kind, {
    String? after,
  });
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String key,
    String action,
  );
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  );
}
