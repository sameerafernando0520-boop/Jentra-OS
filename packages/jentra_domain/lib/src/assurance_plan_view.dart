// Corporate Audit & Assurance: desktop planning views over
// api.assurance_universe, api.assurance_plans (candidate) and
// api.assurance_plan, plus receipt confirmation and availability rules for
// api.assurance_plan_command. The server remains the authority.
import 'assurance.dart';
import 'assurance_planning.dart';

typedef UniverseItem = ({
  String id,
  String code,
  String name,
  String category,
  String ownerId,
  bool active,
  int version,
  AssuranceSeverity? rating,
  int? score,
});
typedef PlanTemplate = ({String id, String code, int version, String name});
typedef PlanTemplateDefinition = ({
  List<Map<String, Object?>> controls,
  List<Map<String, Object?>> requests,
});

/// The audit universe and engagement templates in a scope.
final class AssuranceUniverse {
  AssuranceUniverse.fromJson(Map<String, Object?> j)
    : items = [
        for (final x in _l(j['items']))
          (
            id: assuranceId(_m(x)['id']),
            code: assuranceText(_m(x)['code'], 2, 40),
            name: assuranceText(_m(x)['name'], 1, 160),
            category: _category(_m(x)['category']),
            ownerId: assuranceId(_m(x)['owner_id']),
            active: _itemStatus(_m(x)['status']),
            version: _positive(_m(x)['version']),
            rating: _m(x)['assessment'] == null
                ? null
                : AssuranceSeverity.parse(_m(_m(x)['assessment'])['rating']),
            score: _m(x)['assessment'] == null
                ? null
                : _positive(_m(_m(x)['assessment'])['score']),
          ),
      ],
      definitions = _templateDefinitions(j['templates']),
      templates = [
        for (final t in _l(j['templates']))
          (
            id: assuranceId(_m(t)['id']),
            code: assuranceText(_m(t)['code'], 2, 40),
            version: _positive(_m(t)['version']),
            name: assuranceText(_m(t)['name'], 1, 160),
          ),
      ];

  final List<UniverseItem> items;
  final List<PlanTemplate> templates;
  final Map<String, PlanTemplateDefinition> definitions;

  /// The newest version of each template code; older versions stay readable
  /// but new plan items should reference the current one.
  List<PlanTemplate> get currentTemplates {
    final latest = <String, PlanTemplate>{};
    for (final t in templates) {
      final seen = latest[t.code];
      if (seen == null || t.version > seen.version) latest[t.code] = t;
    }
    return latest.values.toList()..sort((a, b) => a.code.compareTo(b.code));
  }

  bool canRegister(Set<String> caps) => caps.contains('assurance.plan.manage');

  /// Area owners never assess their own risk.
  bool canAssess(Set<String> caps, UniverseItem i, String actorId) =>
      caps.contains('assurance.plan.manage') &&
      i.active &&
      i.ownerId != actorId;

  /// Retiring an area in an open plan is refused server-side.
  bool canRetire(Set<String> caps, UniverseItem i) =>
      caps.contains('assurance.plan.manage') && i.active;
}

Map<String, PlanTemplateDefinition> _templateDefinitions(Object? value) {
  final definitions = <String, PlanTemplateDefinition>{};
  for (final entry in _l(value)) {
    final template = _m(entry);
    // Older recorded read fixtures contain only the template summary.
    if (!template.containsKey('controls') &&
        !template.containsKey('requests')) {
      continue;
    }
    if (!assuranceTemplateValid(template['controls'], template['requests'])) {
      throw const FormatException('Invalid engagement template definition.');
    }
    definitions[assuranceId(template['id'])] = (
      controls: List.unmodifiable([
        for (final control in _l(template['controls']))
          Map<String, Object?>.unmodifiable(_m(control)),
      ]),
      requests: List.unmodifiable([
        for (final request in _l(template['requests']))
          Map<String, Object?>.unmodifiable(_m(request)),
      ]),
    );
  }
  return Map.unmodifiable(definitions);
}

typedef PlanSummary = ({
  String id,
  String name,
  PlanStatus status,
  int version,
  String periodStart,
  String periodEnd,
  int activeItems,
});

/// One page of `api.assurance_plans`.
final class AssurancePlanPage {
  AssurancePlanPage.fromJson(Map<String, Object?> j)
    : items = [
        for (final p in _l(j['items']))
          (
            id: assuranceId(_m(p)['id']),
            name: assuranceText(_m(p)['name'], 1, 160),
            status: PlanStatus.parse(_m(p)['status']),
            version: _positive(_m(p)['version']),
            periodStart: assuranceDate(_m(p)['period_start']),
            periodEnd: assuranceDate(_m(p)['period_end']),
            activeItems: _count(_m(p)['active_items']),
          ),
      ],
      nextCursor = j['next_cursor'] == null
          ? null
          : assuranceId(j['next_cursor']);

  final List<PlanSummary> items;
  final String? nextCursor;
}

typedef PlanOccurrence = ({int occurrence, String engagementId});
typedef PlanItem = ({
  String id,
  String universeItemId,
  String code,
  String name,
  AssuranceSeverity rating,
  AuditFrequency frequency,
  String? templateId,
  String leadAuditorId,
  bool active,
  List<PlanOccurrence> occurrences,
});

/// `api.assurance_plan`: one plan with its items and the high-risk areas it
/// does not yet cover.
final class AssurancePlanDetail {
  AssurancePlanDetail.fromJson(Map<String, Object?> j)
    : id = assuranceId(_m(j['plan'])['id']),
      name = assuranceText(_m(j['plan'])['name'], 1, 160),
      status = PlanStatus.parse(_m(j['plan'])['status']),
      version = _positive(_m(j['plan'])['version']),
      periodStart = assuranceDate(_m(j['plan'])['period_start']),
      periodEnd = assuranceDate(_m(j['plan'])['period_end']),
      createdBy = assuranceId(_m(j['plan'])['created_by']),
      submittedBy = _optionalId(_m(j['plan'])['submitted_by']),
      approvedDigest = _m(j['plan'])['approved_digest'] == null
          ? null
          : assuranceDigest(_m(j['plan'])['approved_digest']),
      items = [
        for (final i in _l(j['items']))
          (
            id: assuranceId(_m(i)['id']),
            universeItemId: assuranceId(_m(i)['universe_item_id']),
            code: assuranceText(_m(i)['code'], 2, 40),
            name: assuranceText(_m(i)['name'], 1, 160),
            rating: AssuranceSeverity.parse(_m(i)['rating']),
            frequency: AuditFrequency.parse(_m(i)['frequency']),
            templateId: _optionalId(_m(i)['template_id']),
            leadAuditorId: assuranceId(_m(i)['lead_auditor_id']),
            active: _planItemStatus(_m(i)['status']),
            occurrences: [
              for (final o in _l(_m(i)['occurrences']))
                (
                  occurrence: _positive(_m(o)['occurrence']),
                  engagementId: assuranceId(_m(o)['engagement_id']),
                ),
            ],
          ),
      ],
      uncovered = [
        for (final u in _l(j['uncovered_high_risk']))
          (
            itemId: assuranceId(_m(u)['item_id']),
            code: assuranceText(_m(u)['code'], 2, 40),
            rating: AssuranceSeverity.parse(_m(u)['rating']),
          ),
      ];

  final String id;
  final String name;
  final PlanStatus status;
  final int version;
  final String periodStart;
  final String periodEnd;
  final String createdBy;
  final String? submittedBy;
  final String? approvedDigest;
  final List<PlanItem> items;
  final List<({String itemId, String code, AssuranceSeverity rating})>
  uncovered;

  List<PlanItem> get activeItems => items.where((i) => i.active).toList();

  bool _manage(Set<String> caps) => caps.contains('assurance.plan.manage');

  bool canEdit(Set<String> caps) => _manage(caps) && status == PlanStatus.draft;

  bool canSubmit(Set<String> caps) =>
      canEdit(caps) && items.any((i) => i.active);

  /// Neither the maker nor the submitter approves (maker-checker).
  bool canDecide(Set<String> caps, String actorId) =>
      _manage(caps) &&
      status == PlanStatus.submitted &&
      actorId != createdBy &&
      actorId != submittedBy;

  bool canCancel(Set<String> caps) =>
      _manage(caps) &&
      (status == PlanStatus.draft || status == PlanStatus.submitted);

  /// An approved plan is changed through a superseding draft (A9); the server
  /// refuses a second open revision.
  bool canRevise(Set<String> caps) =>
      _manage(caps) && status == PlanStatus.approved;

  /// Assessed, active areas not already planned, whose owner is not the
  /// prospective lead.
  List<UniverseItem> plannable(AssuranceUniverse u) => [
    for (final i in u.items)
      if (i.active &&
          i.rating != null &&
          !items.any((p) => p.active && p.universeItemId == i.id))
        i,
  ];

  /// The first planned occurrence not yet instantiated, if any.
  int? nextOccurrence(PlanItem i) {
    final done = {for (final o in i.occurrences) o.occurrence};
    for (var k = 1; k <= i.frequency.occurrences; k++) {
      if (!done.contains(k)) return k;
    }
    return null;
  }

  bool canInstantiate(Set<String> caps, PlanItem i) =>
      caps.contains('assurance.engagement.manage') &&
      status == PlanStatus.approved &&
      i.active &&
      nextOccurrence(i) != null;
}

/// The payload id a plan command's receipt echoes as `aggregate_id`.
String assurancePlanAggregateKey(String action) {
  AssurancePlanCommands.capability(action);
  return switch (action) {
    'register_item' || 'assess_risk' || 'retire_item' => 'item_id',
    'create_template' => 'template_id',
    _ => 'plan_id',
  };
}

/// True when [receipt] confirms this exact plan command advanced its
/// aggregate by one version (an instantiation also names its engagement).
bool assurancePlanReceiptConfirms(
  Map<String, Object?> receipt,
  Map<String, Object?> payload,
  int expectedVersion,
) {
  final action = payload['action'] as String? ?? '';
  return receipt['action'] == action &&
      receipt['aggregate_id'] == payload[assurancePlanAggregateKey(action)] &&
      receipt['version'] == expectedVersion + 1 &&
      (action != 'instantiate_engagement' ||
          receipt['engagement_id'] == payload['engagement_id']);
}

Map<String, Object?> _m(Object? v) => v is Map
    ? v.cast<String, Object?>()
    : throw const FormatException('Object expected.');

List<Object?> _l(Object? v) =>
    v is List ? v : throw const FormatException('List expected.');

int _positive(Object? v) =>
    v is int && v > 0 ? v : throw const FormatException('Positive number.');

int _count(Object? v) =>
    v is int && v >= 0 ? v : throw const FormatException('Count expected.');

String? _optionalId(Object? v) => v == null ? null : assuranceId(v);

String _category(Object? v) => assuranceUniverseCategories.contains(v)
    ? v! as String
    : throw const FormatException('Unknown universe category.');

bool _itemStatus(Object? v) => switch (v) {
  'active' => true,
  'retired' => false,
  _ => throw const FormatException('Unknown universe item status.'),
};

bool _planItemStatus(Object? v) => switch (v) {
  'active' => true,
  'removed' => false,
  _ => throw const FormatException('Unknown plan item status.'),
};
