import 'dart:convert';
import 'package:jentra_domain/jentra_assets.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Scoped named APIs only; no asset table access or client-side posting.
final class SupabaseAssetGateway implements AssetRepository {
  SupabaseAssetGateway(
    this.client, {
    this.timeout = const Duration(seconds: 30),
  });
  final SupabaseClient client;
  final Duration timeout;
  void _require(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in entity and branch.',
      );
    }
  }

  Future<Object?> _rpc(
    String name,
    TenantContext scope,
    Map<String, Object?> args, {
    bool command = false,
  }) async {
    _require(scope);
    try {
      final raw = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...args,
            },
          )
          .timeout(timeout);
      if (client.auth.currentUser?.id != scope.actorId) {
        throw DomainError(
          code: command ? 'UNCERTAIN_RESULT' : 'AUTHENTICATION_REQUIRED',
          message: command
              ? 'The account changed. Reconcile the exact saved request after signing in.'
              : 'Select a signed-in entity and branch.',
          retryable: command,
        );
      }
      return raw;
    } on PostgrestException catch (cause) {
      final code = switch ((cause.code, cause.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'ASSET_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('55000', 'ASSET_SOURCE_ALREADY_OWNED') => 'ASSET_SOURCE_ALREADY_OWNED',
        ('55000', 'PERIOD_CLOSED') => 'PERIOD_CLOSED',
        ('55000', 'ASSET_REBOOK_AFTER_REVERSAL_REQUIRED') =>
          'ASSET_REBOOK_AFTER_REVERSAL_REQUIRED',
        ('55000', 'ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL') =>
          'ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL',
        ('23505', _) => 'IDENTITY_EXISTS',
        ('22023' || '22007' || '22008' || '22P02' || '23514' || '23503', _) =>
          'VALIDATION_ERROR',
        ('55000', _) => 'STATE_CONFLICT',
        _ => command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Assets needs its reviewed development update.',
          'FEATURE_NOT_ENTITLED' =>
            'Assets is not enabled on this business plan.',
          'PERMISSION_DENIED' =>
            'Current scope, permission and MFA are required.',
          'VERSION_CONFLICT' =>
            'The asset changed. Compare its current version before editing.',
          'RESOURCE_NOT_FOUND' =>
            'This asset or book is unavailable in the selected scope.',
          'IDEMPOTENCY_MISMATCH' =>
            'This saved request key belongs to different content. Reconcile the original request.',
          'ASSET_SOURCE_ALREADY_OWNED' =>
            'This opening evidence is already owned by an asset. No capitalization was duplicated.',
          'PERIOD_CLOSED' =>
            'The original or scheduled posting period is closed.',
          'ASSET_REBOOK_AFTER_REVERSAL_REQUIRED' =>
            'Create an independently approved book revision before reposting this reversed period.',
          'ASSET_DEPENDENT_EFFECT_BLOCKS_REVERSAL' =>
            'A later active effect blocks this reversal. Review its original history.',
          'IDENTITY_EXISTS' =>
            'This asset, location or source identity already exists.',
          'VALIDATION_ERROR' =>
            'Check the named mappings, exact amounts, book, dates and source components.',
          'STATE_CONFLICT' =>
            'The asset cannot make this transition. Refresh its proposal and effect history.',
          'SERVICE_UNAVAILABLE' =>
            'The asset service is unavailable. Retry the scoped read.',
          _ =>
            'The result is uncertain. Reconcile the exact encrypted request.',
        },
        retryable: {'UNCERTAIN_RESULT', 'SERVICE_UNAVAILABLE'}.contains(code),
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String name,
    TenantContext scope,
    Map<String, Object?> args,
  ) async => assetMap(await _rpc(name, scope, args));
  @override
  Future<AssetProviderState> authorize(
    TenantContext scope,
    String capability,
  ) async {
    if (!assetCapabilities.contains(capability)) {
      throw const FormatException('Asset capability is invalid.');
    }
    final row = await _call('assets_authorize', scope, {
      'p_capability': capability,
    });
    calendarFields(row, {
      'actor_id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'capability',
      'authorized',
      'procurement_provider',
      'stock_provider',
      'equipment_provider',
      'currency_code',
      'currency_precision',
      'business_date',
    });
    assertAssetScope(row, scope);
    if (row['actor_id'] != scope.actorId ||
        row['capability'] != capability ||
        row['authorized'] != true ||
        [
          row['procurement_provider'],
          row['stock_provider'],
          row['equipment_provider'],
        ].any((x) => x is! bool)) {
      throw const FormatException('Asset authorization changed.');
    }
    return AssetProviderState(
      procurement: row['procurement_provider'] as bool,
      stock: row['stock_provider'] as bool,
      equipment: row['equipment_provider'] as bool,
      currency: assetAmount('0', row['currency_code'] as String).currencyCode,
      precision: _precision(row['currency_precision']),
      businessDate: CivilDate.parse(row['business_date'] as String),
    );
  }

  int _precision(Object? value) {
    final result = workforceInteger(value);
    if (result > 6) {
      throw const FormatException('Asset currency precision changed.');
    }
    return result;
  }

  AssetPage<T> _page<T>(
    Map<String, Object?> row,
    TenantContext scope,
    String? after,
    T Function(Map<String, Object?>) parse,
  ) {
    assertAssetScope(row, scope);
    final values = row['items'];
    if (values is! List || values.length > 50) {
      throw const FormatException('Asset page exceeds its bound.');
    }
    final result = <T>[];
    var prior = after;
    for (final raw in values) {
      final item = assetMap(raw), id = calendarUuid(item['id']);
      if (prior != null && id.compareTo(prior) <= 0) {
        throw const FormatException('Asset page order changed.');
      }
      result.add(parse(item));
      prior = id;
    }
    final next = row['next_cursor'];
    if (next != null && (result.length != 50 || calendarUuid(next) != prior)) {
      throw const FormatException('Asset continuation changed.');
    }
    return AssetPage(List.unmodifiable(result), next as String?);
  }

  @override
  Future<AssetPage<AssetRecord>> register(
    TenantContext scope, {
    String? after,
  }) async {
    if (after != null) {
      calendarUuid(after);
    }
    final row = await _call('assets_register', scope, {'p_after': after});
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'items',
      'next_cursor',
    });
    return _page(row, scope, after, (item) {
      assertAssetScope(item, scope);
      return AssetRecord.fromJson(item);
    });
  }

  void _child(Map<String, Object?> row, TenantContext scope, String assetId) {
    assertAssetScope(row, scope, branch: false);
    if (row['asset_id'] != assetId) {
      throw const FormatException('Asset history identity changed.');
    }
  }

  @override
  Future<AssetDetail> detail(
    TenantContext scope,
    String assetId,
    AssetHistoryKind kind, {
    String? after,
  }) async {
    calendarUuid(assetId);
    if (after != null) {
      calendarUuid(after);
    }
    final row = await _call('assets_detail', scope, {
      'p_asset_id': assetId,
      'p_kind': kind.name,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'asset',
      'kind',
      'proposal',
      'opening',
      'labels',
      'items',
      'next_cursor',
    });
    assertAssetScope(row, scope);
    if (row['kind'] != kind.name) {
      throw const FormatException('Asset history section changed.');
    }
    final a = assetMap(row['asset']);
    assertAssetScope(a, scope);
    final asset = AssetRecord.fromJson(a);
    if (asset.id != assetId) {
      throw const FormatException('Asset detail identity changed.');
    }
    final source = assetMap(row['opening']);
    _child(source, scope, assetId);
    final opening = AssetOpening.fromJson(source, asset.currency);
    final labels = assetMap(row['labels']);
    calendarFields(labels, assetDetailLabelFields);
    final typedLabels = Map<String, String?>.unmodifiable({
      for (final entry in labels.entries)
        entry.key: entry.value == null ? null : assetText(entry.value, 1000),
    });
    AssetProposal? proposal;
    if (row['proposal'] != null) {
      final raw = assetMap(row['proposal']);
      _child(raw, scope, assetId);
      assertAssetScope(raw, scope);
      proposal = AssetProposal.fromJson(raw, asset.currency);
      if (raw['approval'] != null) {
        _child(assetMap(raw['approval']), scope, assetId);
      }
      if (proposal.id != asset.proposalId) {
        throw const FormatException('Current asset proposal changed.');
      }
      if (proposal.kind == 'capitalize' &&
          (proposal.data['source_id'] != opening.id ||
              proposal.book!.basis.cost != opening.cost ||
              proposal.book!.basis.openingAccumulated != opening.accumulated)) {
        throw const FormatException(
          'Asset opening differs from approved source evidence.',
        );
      }
      final before = proposal.before;
      if (before != null &&
          (before.cost != asset.cost ||
              before.accumulated != asset.accumulated ||
              before.impairment != asset.impairment ||
              before.bookId != asset.bookId ||
              before.postedPeriods != asset.postedPeriods ||
              before.branchId != asset.branchId ||
              before.locationId != asset.locationId ||
              before.custodianId != asset.custodianId ||
              before.status != asset.status ||
              before.lastEffectId != asset.lastEffectId)) {
        throw const FormatException('Asset proposal basis changed.');
      }
    } else if (asset.proposalId != null) {
      throw const FormatException('Current asset proposal is missing.');
    }
    final books = <AssetBook>[],
        effects = <AssetEffect>[],
        proposals = <AssetProposal>[];
    final page = _page<Object>(row, scope, after, (item) {
      _child(item, scope, assetId);
      switch (kind) {
        case AssetHistoryKind.books:
          final b = AssetBook.fromJson(item);
          if (b.definition.basis.currency != asset.currency) {
            throw const FormatException('Asset book currency changed.');
          }
          books.add(b);
          return b;
        case AssetHistoryKind.effects:
          final e = AssetEffect.fromJson(item, asset.currency);
          effects.add(e);
          return e;
        case AssetHistoryKind.proposals:
          final p = AssetProposal.fromJson(item, asset.currency);
          if (p.approval != null) {
            _child(assetMap(item['approval']), scope, assetId);
          }
          proposals.add(p);
          return p;
      }
    });
    return AssetDetail(
      asset: asset,
      kind: kind,
      opening: opening,
      proposal: proposal,
      books: List.unmodifiable(books),
      effects: List.unmodifiable(effects),
      proposals: List.unmodifiable(proposals),
      nextCursor: page.nextCursor,
      labels: typedLabels,
    );
  }

  @override
  Future<AssetSchedulePage> schedule(
    TenantContext scope,
    String assetId,
    String bookId, {
    int after = 0,
  }) async {
    calendarUuid(assetId);
    calendarUuid(bookId);
    if (after < 0 || after > 1200) {
      throw const FormatException('Asset period cursor is invalid.');
    }
    final row = await _call('assets_schedule', scope, {
      'p_asset_id': assetId,
      'p_book_id': bookId,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'asset_id',
      'book_id',
      'basis',
      'items',
      'next_cursor',
    });
    assertAssetScope(row, scope);
    if (row['asset_id'] != assetId || row['book_id'] != bookId) {
      throw const FormatException('Asset schedule identity changed.');
    }
    final definition = AssetBookDefinition.fromJson(assetMap(row['basis'])),
        values = row['items'];
    if (values is! List ||
        values.length > 50 ||
        after > definition.basis.remainingMonths) {
      throw const FormatException('Asset schedule bound changed.');
    }
    final count = (definition.basis.remainingMonths - after).clamp(0, 50);
    if (values.length != count) {
      throw const FormatException('Asset schedule coverage changed.');
    }
    final periods = <AssetSchedulePeriod>[];
    for (var i = 0; i < values.length; i++) {
      final raw = assetMap(values[i]),
          expected = definition.schedule.periods[after + i];
      calendarFields(raw, expected.toJson().keys.toSet());
      if (expected.toJson().entries.any(
        (entry) => raw[entry.key] != entry.value,
      )) {
        throw const FormatException(
          'Asset schedule does not reproduce its frozen book.',
        );
      }
      periods.add(expected);
    }
    final next = row['next_cursor'];
    if (after + values.length < definition.basis.remainingMonths) {
      if (next is! String || int.tryParse(next) != after + values.length) {
        throw const FormatException('Asset schedule continuation changed.');
      }
    } else if (next != null) {
      throw const FormatException('Asset schedule has a false continuation.');
    }
    return AssetSchedulePage(
      bookId,
      definition,
      List.unmodifiable(periods),
      next == null ? null : int.parse(next as String),
    );
  }

  @override
  Future<AssetPage<AssetPicker>> pickers(
    TenantContext scope,
    String kind, {
    String? after,
  }) async {
    if (!{
      'locations',
      'custodians',
      'asset',
      'expense',
      'equity',
      'revenue',
    }.contains(kind)) {
      throw const FormatException('Asset picker kind is invalid.');
    }
    if (after != null) {
      calendarUuid(after);
    }
    final row = await _call('assets_pickers', scope, {
      'p_kind': kind,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'kind',
      'items',
      'next_cursor',
    });
    if (row['kind'] != kind) {
      throw const FormatException('Asset picker section changed.');
    }
    return _page(row, scope, after, (item) => AssetPicker.fromJson(item, kind));
  }

  Map<String, Object?> _response(
    Map<String, Object?> row,
    TenantContext scope, {
    String? commandId,
    Map<String, Object?>? payload,
    int? version,
    String? expectedAction,
  }) {
    calendarFields(row, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    calendarUuid(row['request_id']);
    calendarUuid(row['correlation_id']);
    calendarUuid(row['command_id']);
    if (commandId != null && row['command_id'] != commandId ||
        row['warnings'] is! List ||
        (row['warnings'] as List).isNotEmpty) {
      throw const FormatException('Asset command confirmation changed.');
    }
    final entity = assetMap(row['entity']);
    assertAssetScope(entity, scope);
    calendarUuid(entity['id']);
    final actualVersion = workforceInteger(entity['version'], positive: true);
    if (payload != null && entity['id'] != payload['id'] ||
        version != null && actualVersion != version + 1) {
      throw const FormatException('Asset result identity/version changed.');
    }
    if ((payload?['action'] ?? expectedAction) == 'location') {
      calendarFields(entity, {
        'id',
        'tenant_id',
        'legal_entity_id',
        'branch_id',
        'version',
      });
      if (actualVersion != 1) {
        throw const FormatException('Asset location version changed.');
      }
    } else {
      calendarFields(entity, {
        'id',
        'tenant_id',
        'legal_entity_id',
        'branch_id',
        'current_branch_id',
        'version',
        'status',
        'proposal_id',
        'book_id',
        'last_effect_id',
      });
      calendarUuid(entity['current_branch_id']);
      assetOptionalId(entity['proposal_id']);
      assetOptionalId(entity['book_id']);
      assetOptionalId(entity['last_effect_id']);
      if (!{
        'draft',
        'active',
        'disposed',
        'reversed',
      }.contains(entity['status'])) {
        throw const FormatException('Asset result state changed.');
      }
      final action = payload?['action'] ?? expectedAction;
      if (!{'post', 'reverse', null}.contains(action) &&
          entity['current_branch_id'] != scope.branchId) {
        throw const FormatException('Unexpected asset branch move.');
      }
      if ({'opening', 'propose', 'approve'}.contains(action) &&
              entity['proposal_id'] != payload?['proposal_id'] ||
          {'post', 'cancel'}.contains(action) &&
              entity['proposal_id'] != null ||
          action == 'opening' &&
              (entity['status'] != 'draft' || entity['book_id'] != null) ||
          action == 'depreciate' &&
              (entity['status'] != 'active' ||
                  entity['book_id'] != payload?['book_id'])) {
        throw const FormatException(
          'Asset result does not match the requested transition.',
        );
      }
    }
    return Map<String, Object?>.from(jsonDecode(jsonEncode(row)) as Map);
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String key,
    String action,
  ) async {
    calendarUuid(key);
    AssetCommands.capability(action);
    final raw = await _rpc('assets_own_receipt', scope, {
      'p_idempotency_key': key,
      'p_action': action,
    });
    if (raw == null) {
      return null;
    }
    final row = assetMap(raw);
    calendarFields(row, {
      'command_id',
      'idempotency_key',
      'request_hash',
      'response',
    });
    if (row['idempotency_key'] != key) {
      throw const FormatException('Asset receipt key changed.');
    }
    calendarUuid(row['command_id']);
    assetDigest(row['request_hash']);
    _response(
      assetMap(row['response']),
      scope,
      commandId: row['command_id'] as String,
      expectedAction: action,
    );
    return Map<String, Object?>.from(jsonDecode(jsonEncode(row)) as Map);
  }

  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    _require(command.context);
    final payload = Map<String, Object?>.from(
      jsonDecode(jsonEncode(command.payload)) as Map,
    );
    final action = payload['action'] as String;
    AssetCommands.validate(action, payload);
    calendarUuid(command.commandId);
    calendarUuid(command.idempotencyKey);
    final version = command.expectedEntityVersion;
    if (version == null ||
        version < 0 ||
        version >= 9007199254740991 ||
        {'location', 'opening'}.contains(action) && version != 0 ||
        !{'location', 'opening'}.contains(action) && version == 0) {
      throw const FormatException('Asset expected version is invalid.');
    }
    try {
      final raw = await _rpc('assets_command', command.context, {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_issued_at': command.clientTimestamp.toIso8601String(),
        'p_payload': payload,
        'p_expected_version': version,
      }, command: true);
      return _response(
        assetMap(raw),
        command.context,
        commandId: command.commandId,
        payload: payload,
        version: version,
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The result could not be verified. Reconcile the exact encrypted request.',
        retryable: true,
      );
    }
  }
}
