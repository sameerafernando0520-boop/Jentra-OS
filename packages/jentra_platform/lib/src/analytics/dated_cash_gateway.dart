import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show ExactDecimal;
import 'process_metric_gateway.dart';
import 'process_metric_hasher.dart';

final class DatedCashBasis {
  const DatedCashBasis(
    this.scope,
    this.hash,
    this.start,
    this.end,
    this.recordedThrough,
    this.controls,
    this.obligations,
    this.providers,
    this.providerStatus, {
    this.contractRevision = 2,
  });
  final ProcessMetricScope scope;
  final String hash, start, end, recordedThrough;
  final List<CashControl> controls;
  final List<CashObligation> obligations;
  final Set<String> providers;
  final Map<String, String> providerStatus;
  final int contractRevision;
  Set<String> get requiredProviders => contractRevision == 3
      ? const {
          'bank_cash',
          'receivables',
          'payables',
          'payroll',
          'project_reimbursements',
        }
      : const {'bank_cash', 'receivables', 'payables'};
  CashScenario project(
    CashScenarioRevision revision, {
    required Set<String> requiredProviders,
  }) {
    if (revision.scope != scope ||
        revision.sourceHash != hash ||
        revision.horizonStart != start ||
        revision.horizonEnd != end ||
        parseProcessMetricUtc(revision.recordedThrough) !=
            parseProcessMetricUtc(recordedThrough)) {
      throw const FormatException('Scenario source basis changed.');
    }
    return CashScenario.calculate(
      scope: scope,
      horizonStart: start,
      horizonEnd: end,
      requiredProviders: requiredProviders,
      completeProviders: providers,
      controls: controls,
      obligations: revision.apply(obligations),
    );
  }
}

final class DatedCashGateway {
  DatedCashGateway(this.rpc);
  final ProcessMetricRpc rpc;
  Map<String, Object?> _scope(ProcessMetricScope s) => {
    'p_tenant_id': s.tenantId,
    'p_legal_entity_id': s.legalEntityId,
    'p_branch_id': s.branchId,
  };
  Future<void> authorize(ProcessMetricScope s, String actor) async {
    if (await rpc('wave5_cash_authorize', _scope(s)) != actor) {
      throw StateError('Current scenario actor required.');
    }
  }

  Future<DatedCashBasis> read(
    ProcessMetricScope s,
    String start,
    String end,
    String recordedThrough,
  ) async {
    final raw = await rpc('wave5_cash_basis', {
      ..._scope(s),
      'p_start': start,
      'p_end': end,
      'p_recorded_through': recordedThrough,
    });
    return _verify(raw, s, start, end, recordedThrough);
  }

  Future<DatedCashBasis> _verify(
    Object? raw,
    ProcessMetricScope s,
    String start,
    String end,
    String through,
  ) async {
    if (raw is! Map ||
        raw['canonicalText'] is! String ||
        raw['sourceHash'] is! String) {
      throw const FormatException('Invalid cash publication.');
    }
    final canonical = raw['canonicalText'] as String;
    if (utf8.encode(canonical).length > 8388608 ||
        await ProcessMetricSha256Hasher().sha256(utf8.encode(canonical)) !=
            raw['sourceHash']) {
      throw const FormatException('Cash publication digest mismatch.');
    }
    final data = jsonDecode(canonical);
    if (data is! Map ||
        data.length != 12 ||
        !{2, 3}.contains(data['contractRevision']) ||
        data['definition'] !=
            (data['contractRevision'] == 3
                ? 'dated_transaction_cash_all_obligations.v3'
                : 'dated_transaction_cash_ar_and_ap.v2') ||
        data['horizonStart'] != start ||
        data['horizonEnd'] != end ||
        parseProcessMetricUtc(data['recordedThrough'] as String) !=
            parseProcessMetricUtc(through) ||
        data['scope'] is! Map ||
        data['scope']['tenantId'] != s.tenantId ||
        data['scope']['legalEntityId'] != s.legalEntityId ||
        data['scope']['branchId'] != s.branchId ||
        data['completeProviders'] is! List ||
        data['providerStatus'] is! Map ||
        data['controls'] is! List ||
        data['obligations'] is! List ||
        data['sources'] is! List ||
        (data['sources'] as List).length > 10000 ||
        (data['controls'] as List).length +
                (data['obligations'] as List).length >
            10000) {
      throw const FormatException('Cash authority contract mismatch.');
    }
    final providers = (data['completeProviders'] as List)
        .cast<String>()
        .toSet();
    final rawStatus = (data['providerStatus'] as Map).cast<String, Object?>();
    const statusKeys = {
      'bank_cash',
      'receivables',
      'payables',
      'payroll',
      'project_reimbursements',
    };
    final v3 = data['contractRevision'] == 3;
    const dateStatuses = {
      'available',
      'source_not_installed',
      'permission_required',
      'mfa_required',
      'missing_payment_date',
    };
    if (providers.length != (data['completeProviders'] as List).length ||
        !statusKeys.containsAll(providers) ||
        !providers.containsAll({'bank_cash', 'receivables'}) ||
        (rawStatus['payables'] != 'available' &&
            rawStatus['payables'] != 'permission_required') ||
        rawStatus['bank_cash'] != 'available' ||
        rawStatus['receivables'] != 'available' ||
        (v3
            ? !dateStatuses.contains(rawStatus['payroll'])
            : rawStatus['payroll'] != 'missing_authoritative_due_date') ||
        (v3
            ? !dateStatuses.contains(rawStatus['project_reimbursements'])
            : rawStatus['project_reimbursements'] !=
                  'missing_authoritative_due_date') ||
        rawStatus.length != statusKeys.length ||
        !rawStatus.keys.toSet().containsAll(statusKeys) ||
        statusKeys.any(
          (k) => providers.contains(k) != (rawStatus[k] == 'available'),
        )) {
      throw const FormatException('Cash provider availability mismatch.');
    }
    ProcessMetricScope rowScope(Map r) => ProcessMetricScope(
      tenantId: s.tenantId,
      legalEntityId: s.legalEntityId,
      branchId: r['branchId'] as String?,
    );
    final controls = <CashControl>[], obligations = <CashObligation>[];
    for (final r in data['controls'] as List) {
      if (r is! Map || r.length != 6) {
        throw const FormatException('Invalid cash control.');
      }
      controls.add(
        CashControl(
          scope: rowScope(r),
          accountId: r['accountId'] as String,
          currency: r['currency'] as String,
          units: _units(r['amount']),
          asOf: '${start}T00:00:00Z',
          publicationId: r['id'] as String,
          sourceVersion: r['version'] as String,
        ),
      );
    }
    for (final r in data['obligations'] as List) {
      if (r is! Map ||
          r.length != (v3 ? 8 : 7) ||
          !{
            'receivables',
            'payables',
            if (v3) 'payroll',
            if (v3) 'project_reimbursements',
          }.contains(r['provider']) ||
          (v3 &&
              (r['inflow'] is! bool ||
                  (r['provider'] != 'payroll' &&
                      r['inflow'] != (r['provider'] == 'receivables')))) ||
          !providers.contains(r['provider'])) {
        throw const FormatException('Invalid remaining obligation.');
      }
      obligations.add(
        CashObligation(
          scope: rowScope(r),
          provider: r['provider'] as String,
          id: r['id'] as String,
          currency: r['currency'] as String,
          dueDate: r['dueDate'] as String,
          remainingUnits: _units(r['amount']),
          inflow: v3 ? r['inflow'] as bool : r['provider'] == 'receivables',
          publicationId: r['id'] as String,
          sourceVersion: r['version'] as String,
        ),
      );
    }
    return DatedCashBasis(
      s,
      raw['sourceHash'] as String,
      start,
      end,
      through,
      List.unmodifiable(controls),
      List.unmodifiable(obligations),
      Set.unmodifiable(providers),
      Map.unmodifiable({for (final k in statusKeys) k: rawStatus[k] as String}),
      contractRevision: data['contractRevision'] as int,
    );
  }

  BigInt _units(Object? raw) {
    if (raw is! String ||
        !RegExp(r'^-?(0|[1-9][0-9]{0,19})(\.[0-9]{1,6})?$').hasMatch(raw)) {
      throw const FormatException('Exact dated cash amount required.');
    }
    return ExactDecimal.parse(raw, scale: 6).scaledValue;
  }

  Future<String> save(CashScenarioRevision r) async {
    final raw = await rpc('wave5_cash_save', {
      ..._scope(r.scope),
      'p_id': r.id,
      'p_source_hash': r.sourceHash,
      'p_parameters': {
        'horizonStart': r.horizonStart,
        'horizonEnd': r.horizonEnd,
        'recordedThrough': r.recordedThrough,
        'overrides': r.overrides,
      },
    });
    if (raw is! Map ||
        raw['id'] != r.id ||
        raw['sourceHash'] != r.sourceHash ||
        raw['version'] != '1') {
      throw const FormatException('Scenario receipt mismatch.');
    }
    return r.id;
  }

  Future<(DatedCashBasis, CashScenarioRevision)> reopen(
    ProcessMetricScope s,
    String id,
  ) async {
    final raw = await rpc('wave5_cash_get', {..._scope(s), 'p_id': id});
    if (raw is! Map ||
        raw.length != 4 ||
        raw['id'] != id ||
        raw['parameters'] is! Map) {
      throw const FormatException('Invalid saved scenario.');
    }
    final p = (raw['parameters'] as Map).cast<String, Object?>();
    final basis = await _verify(
      raw,
      s,
      p['horizonStart'] as String,
      p['horizonEnd'] as String,
      p['recordedThrough'] as String,
    );
    final revision = CashScenarioRevision.fromJson(s, {
      'id': id,
      'sourceHash': basis.hash,
      'horizonStart': basis.start,
      'horizonEnd': basis.end,
      'recordedThrough': basis.recordedThrough,
      'overrides': p['overrides'],
    });
    return (basis, revision);
  }
}
