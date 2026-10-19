// Corporate Audit & Assurance A3: audit universe, risk assessment,
// maker-checker plans, engagement templates and recurring engagements.
//
// Mirrors api.assurance_plan_command in
// supabase/candidates/20261018190000_assurance_universe_plans.sql. The server
// remains the authority; nothing here grants access.
import 'assurance.dart';

final _code = RegExp(r'^[A-Z0-9][A-Z0-9._-]{1,39}$');

const assuranceUniverseCategories = {
  'process',
  'entity',
  'system',
  'compliance',
  'project',
};

/// Score cut-offs for a risk rating (likelihood × impact, 1–25). The tenant
/// may change them (A9 settings); [standard] is the default.
final class RatingBands {
  const RatingBands(this.critical, this.high, this.medium);

  /// ≥ 20 critical, ≥ 10 high, ≥ 5 medium, otherwise low.
  static const standard = RatingBands(20, 10, 5);

  final int critical;
  final int high;
  final int medium;

  /// Each 2–25 and strictly descending, as `api.assurance_settings_command`.
  bool get valid =>
      critical <= 25 && medium >= 2 && critical > high && high > medium;

  AssuranceSeverity rate(int score) {
    if (score >= critical) return AssuranceSeverity.critical;
    if (score >= high) return AssuranceSeverity.high;
    if (score >= medium) return AssuranceSeverity.medium;
    return AssuranceSeverity.low;
  }

  Map<String, Object?> toJson() => {
    'critical': critical,
    'high': high,
    'medium': medium,
  };
}

/// Likelihood × impact (each 1–5) rated with [bands].
AssuranceSeverity assuranceRiskRating(
  int likelihood,
  int impact, {
  RatingBands bands = RatingBands.standard,
}) {
  if (likelihood < 1 || likelihood > 5 || impact < 1 || impact > 5) {
    throw const FormatException('Likelihood and impact are 1 to 5.');
  }
  return bands.rate(likelihood * impact);
}

enum AuditFrequency {
  once(1),
  semiannual(2),
  quarterly(4),
  monthly(12);

  const AuditFrequency(this.occurrences);

  final int occurrences;

  static AuditFrequency parse(Object? v) => values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw const FormatException('Unknown audit frequency.'),
  );
}

/// Occurrence [occurrence] of [count] splits the plan period into contiguous
/// parts by day count, exactly as `assurance.occurrence_period`.
({DateTime start, DateTime end}) assuranceOccurrencePeriod(
  DateTime planStart,
  DateTime planEnd,
  int count,
  int occurrence,
) {
  final start = DateTime.utc(planStart.year, planStart.month, planStart.day);
  final end = DateTime.utc(planEnd.year, planEnd.month, planEnd.day);
  final days = end.difference(start).inDays + 1;
  if (count < 1 || occurrence < 1 || occurrence > count || days < count) {
    throw const FormatException('Occurrence outside the plan period.');
  }
  return (
    start: start.add(Duration(days: (occurrence - 1) * days ~/ count)),
    end: start.add(Duration(days: occurrence * days ~/ count - 1)),
  );
}

enum PlanStatus {
  draft,
  submitted,
  approved,
  cancelled,
  superseded;

  static PlanStatus parse(Object? v) => values.firstWhere(
    (s) => s.name == v,
    orElse: () => throw const FormatException('Unknown plan status.'),
  );

  /// Transitions the server allows. An approved plan changes only when an
  /// approved revision supersedes it.
  Set<PlanStatus> get next => switch (this) {
    draft => {submitted, cancelled},
    submitted => {approved, draft, cancelled},
    approved => {superseded},
    cancelled || superseded => const {},
  };
}

/// Exact allow-list check of a template's controls and PBC requests, matching
/// `assurance.template_valid`.
bool assuranceTemplateValid(Object? controls, Object? requests) {
  if (controls is! List || requests is! List) return false;
  if (controls.isEmpty || controls.length > 50 || requests.length > 100) {
    return false;
  }
  final codes = <String>{};
  for (final c in controls) {
    if (c is! Map || !_sameKeys(c, const {'control_code', 'title', 'risk'})) {
      return false;
    }
    final code = c['control_code'];
    final title = c['title'];
    if (code is! String || !_code.hasMatch(code) || !codes.add(code)) {
      return false;
    }
    if (title is! String ||
        title.trim().length < 3 ||
        title.trim().length > 160) {
      return false;
    }
    if (!AssuranceSeverity.values.any((s) => s.name == c['risk'])) return false;
  }
  for (final r in requests) {
    if (r is! Map ||
        !_sameKeys(r, const {
          'control_code',
          'description',
          'due_offset_days',
        })) {
      return false;
    }
    final description = r['description'];
    final offset = r['due_offset_days'];
    if (!codes.contains(r['control_code'])) return false;
    if (description is! String ||
        description.trim().length < 3 ||
        description.trim().length > 2000) {
      return false;
    }
    if (offset is! int || offset < 1 || offset > 365) return false;
  }
  return true;
}

bool _sameKeys(Map m, Set<String> keys) =>
    m.length == keys.length && m.keys.every(keys.contains);

/// Commands served by `api.assurance_plan_command`.
abstract final class AssurancePlanCommands {
  static const _capabilities = <String, String>{
    'register_item': 'assurance.plan.manage',
    'assess_risk': 'assurance.plan.manage',
    'retire_item': 'assurance.plan.manage',
    'create_template': 'assurance.plan.manage',
    'create_plan': 'assurance.plan.manage',
    'add_plan_item': 'assurance.plan.manage',
    'remove_plan_item': 'assurance.plan.manage',
    'submit_plan': 'assurance.plan.manage',
    'decide_plan': 'assurance.plan.manage',
    'cancel_plan': 'assurance.plan.manage',
    'supersede_plan': 'assurance.plan.manage',
    'instantiate_engagement': 'assurance.engagement.manage',
  };
  static const _fields = <String, List<String>>{
    'register_item': ['item_id', 'code', 'name', 'category', 'owner_id'],
    'assess_risk': [
      'item_id',
      'assessment_id',
      'likelihood',
      'impact',
      'rationale',
    ],
    'retire_item': ['item_id', 'reason'],
    'create_template': ['template_id', 'code', 'name', 'controls', 'requests'],
    'create_plan': ['plan_id', 'name', 'period_start', 'period_end'],
    'add_plan_item': [
      'plan_id',
      'plan_item_id',
      'item_id',
      'frequency',
      'template_id',
      'lead_auditor_id',
      'scope_summary',
    ],
    'remove_plan_item': ['plan_id', 'plan_item_id', 'reason'],
    'submit_plan': ['plan_id'],
    'decide_plan': ['plan_id', 'decision', 'reason'],
    'cancel_plan': ['plan_id', 'reason'],
    'supersede_plan': ['plan_id', 'supersedes_plan_id', 'name'],
    'instantiate_engagement': [
      'plan_id',
      'plan_item_id',
      'occurrence',
      'engagement_id',
    ],
  };

  static String capability(String action) =>
      _capabilities[action] ??
      (throw const FormatException('Unknown assurance plan action.'));

  static Set<String> fields(String action) {
    capability(action);
    return {'action', ..._fields[action]!};
  }

  static bool requiresRecentMfa(String action) {
    capability(action);
    return action == 'decide_plan';
  }

  /// Creation actions use expected version 0; others the aggregate version.
  static bool creates(String action) {
    capability(action);
    return const {
      'register_item',
      'create_template',
      'create_plan',
      'supersede_plan',
    }.contains(action);
  }

  static void validate(String action, Map<String, Object?> p) {
    final allowed = fields(action);
    for (final k in p.keys) {
      if (!allowed.contains(k)) {
        throw FormatException('Unexpected assurance field $k.');
      }
    }
    if (p['action'] != action) {
      throw const FormatException('Assurance action changed.');
    }
    switch (action) {
      case 'register_item':
        assuranceId(p['item_id']);
        _requireCode(p['code']);
        assuranceText(p['name'], 3, 160);
        if (!assuranceUniverseCategories.contains(p['category'])) {
          throw const FormatException('Unknown universe category.');
        }
        assuranceId(p['owner_id']);
      case 'assess_risk':
        assuranceId(p['item_id']);
        assuranceId(p['assessment_id']);
        final l = p['likelihood'];
        final i = p['impact'];
        if (l is! int || i is! int) {
          throw const FormatException('Likelihood and impact are 1 to 5.');
        }
        assuranceRiskRating(l, i);
        assuranceText(p['rationale'], 3, 2000);
      case 'retire_item':
        assuranceId(p['item_id']);
        assuranceText(p['reason'], 3, 1000);
      case 'create_template':
        assuranceId(p['template_id']);
        _requireCode(p['code']);
        assuranceText(p['name'], 3, 160);
        if (!assuranceTemplateValid(p['controls'], p['requests'])) {
          throw const FormatException('Invalid engagement template.');
        }
      case 'create_plan':
        assuranceId(p['plan_id']);
        assuranceText(p['name'], 3, 160);
        final start = assuranceDate(p['period_start']);
        final end = assuranceDate(p['period_end']);
        if (end.compareTo(start) < 0) {
          throw const FormatException('Plan period must be ordered.');
        }
      case 'add_plan_item':
        assuranceId(p['plan_id']);
        assuranceId(p['plan_item_id']);
        assuranceId(p['item_id']);
        AuditFrequency.parse(p['frequency']);
        if (p['template_id'] != null) assuranceId(p['template_id']);
        assuranceId(p['lead_auditor_id']);
        assuranceText(p['scope_summary'], 3, 2000);
      case 'remove_plan_item':
        assuranceId(p['plan_id']);
        assuranceId(p['plan_item_id']);
        assuranceText(p['reason'], 3, 1000);
      case 'submit_plan':
        assuranceId(p['plan_id']);
      case 'decide_plan':
        assuranceId(p['plan_id']);
        if (p['decision'] != 'approve' && p['decision'] != 'return') {
          throw const FormatException('Decision is approve or return.');
        }
        assuranceText(p['reason'], 3, 1000);
      case 'cancel_plan':
        assuranceId(p['plan_id']);
        assuranceText(p['reason'], 3, 1000);
      case 'supersede_plan':
        assuranceId(p['plan_id']);
        assuranceId(p['supersedes_plan_id']);
        assuranceText(p['name'], 3, 160);
      case 'instantiate_engagement':
        assuranceId(p['plan_id']);
        assuranceId(p['plan_item_id']);
        final k = p['occurrence'];
        if (k is! int || k < 1 || k > 12) {
          throw const FormatException('Occurrence is 1 to 12.');
        }
        assuranceId(p['engagement_id']);
    }
  }

  static void _requireCode(Object? v) {
    if (v is! String || !_code.hasMatch(v)) {
      throw const FormatException('Invalid code.');
    }
  }
}
