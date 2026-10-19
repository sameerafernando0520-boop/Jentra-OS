// Corporate Audit & Assurance A9: tenant settings (api.assurance_settings and
// api.assurance_settings_command, candidate APIs). The server remains the
// authority; parsing fails closed.
import 'assurance.dart';
import 'assurance_planning.dart';
import 'assurance_workspace.dart';

/// Continuous-monitoring rules whose thresholds a tenant may change.
const assuranceMonitoringRuleCodes = [
  'ACCESS_PRIVILEGED_NO_MFA',
  'P2P_MATCH_OVERRIDE',
  'P2P_OVERRIDE_BY_CREATOR',
  'HR_ATTENDANCE_SELF_APPROVAL',
];

typedef MonitoringThreshold = ({bool enabled, int minCount});

/// Effective settings: an entity row, else the tenant row, else [defaults].
final class AssuranceSettings {
  const AssuranceSettings({
    required this.source,
    required this.dueSoonDays,
    required this.escalateAfterDays,
    required this.findingResponseDays,
    required this.bands,
    required this.monitoring,
  });

  static final defaults = AssuranceSettings(
    source: 'default',
    dueSoonDays: 3,
    escalateAfterDays: 7,
    findingResponseDays: 14,
    bands: RatingBands.standard,
    monitoring: {
      for (final c in assuranceMonitoringRuleCodes)
        c: (enabled: true, minCount: 1),
    },
  );

  factory AssuranceSettings.fromJson(Map<String, Object?> j) {
    final source = j['source'];
    if (source is! String ||
        !const {'default', 'tenant', 'entity'}.contains(source)) {
      throw const FormatException('Unknown settings source.');
    }
    final b = _map(j['rating_bands']);
    final bands = RatingBands(
      _int(b['critical'], 2, 25),
      _int(b['high'], 2, 25),
      _int(b['medium'], 2, 25),
    );
    if (b.length != 3 || !bands.valid) {
      throw const FormatException('Rating bands must descend.');
    }
    return AssuranceSettings(
      source: source,
      dueSoonDays: _int(j['due_soon_days'], 1, 30),
      escalateAfterDays: _int(j['escalate_after_days'], 1, 90),
      findingResponseDays: _int(j['finding_response_days'], 1, 90),
      bands: bands,
      monitoring: _monitoring(j['monitoring']),
    );
  }

  final String source;
  final int dueSoonDays;
  final int escalateAfterDays;
  final int findingResponseDays;
  final RatingBands bands;
  final Map<String, MonitoringThreshold> monitoring;

  ReminderLevel level(DateTime? due, DateTime today) => assuranceReminderLevel(
    due,
    today,
    dueSoonDays: dueSoonDays,
    escalateAfterDays: escalateAfterDays,
  );

  AssuranceSettings copyWith({
    int? dueSoonDays,
    int? escalateAfterDays,
    int? findingResponseDays,
    RatingBands? bands,
    Map<String, MonitoringThreshold>? monitoring,
  }) => AssuranceSettings(
    source: source,
    dueSoonDays: dueSoonDays ?? this.dueSoonDays,
    escalateAfterDays: escalateAfterDays ?? this.escalateAfterDays,
    findingResponseDays: findingResponseDays ?? this.findingResponseDays,
    bands: bands ?? this.bands,
    monitoring: monitoring ?? this.monitoring,
  );

  /// The `api.assurance_settings_command` payload for [level].
  Map<String, Object?> toPayload(String level) => {
    'level': level,
    'due_soon_days': dueSoonDays,
    'escalate_after_days': escalateAfterDays,
    'finding_response_days': findingResponseDays,
    'rating_bands': bands.toJson(),
    'monitoring': {
      for (final MapEntry(key: code, value: t) in monitoring.entries)
        code: {'enabled': t.enabled, 'min_count': t.minCount},
    },
  };

  static Map<String, MonitoringThreshold> _monitoring(Object? v) {
    final m = _map(v);
    if (m.length != assuranceMonitoringRuleCodes.length ||
        !assuranceMonitoringRuleCodes.every(m.containsKey)) {
      throw const FormatException('Monitoring rules are an allow-list.');
    }
    return {
      for (final c in assuranceMonitoringRuleCodes)
        c: () {
          final t = _map(m[c]);
          final enabled = t['enabled'];
          if (t.length != 2 || enabled is! bool) {
            throw const FormatException('Invalid monitoring threshold.');
          }
          return (enabled: enabled, minCount: _int(t['min_count'], 1, 10000));
        }(),
    };
  }
}

/// `api.assurance_settings`: effective values, row versions and the rules.
final class AssuranceSettingsPage {
  AssuranceSettingsPage.fromJson(Map<String, Object?> j)
    : effective = AssuranceSettings.fromJson(_map(j['effective'])),
      tenantVersion = _version(j['tenant']),
      entityVersion = _version(j['entity']),
      rules = [
        for (final r in _list(j['rules']))
          (
            code: _rule(_map(r)['code']),
            description: assuranceText(_map(r)['description'], 3, 200),
          ),
      ];

  final AssuranceSettings effective;
  final int? tenantVersion;
  final int? entityVersion;
  final List<({String code, String description})> rules;

  /// The version a write at [level] is checked against (0 creates the row).
  int versionFor(String level) =>
      (level == 'entity' ? entityVersion : tenantVersion) ?? 0;

  static int? _version(Object? v) =>
      v == null ? null : _int(_map(v)['version'], 1, 1 << 52);

  static String _rule(Object? v) => assuranceMonitoringRuleCodes.contains(v)
      ? v! as String
      : throw const FormatException('Unknown monitoring rule.');
}

abstract final class AssuranceSettingsCommands {
  static const fields = [
    'level',
    'due_soon_days',
    'escalate_after_days',
    'finding_response_days',
    'rating_bands',
    'monitoring',
  ];

  static void validate(Map<String, Object?> p) {
    if (p.length != fields.length || !fields.every(p.containsKey)) {
      throw const FormatException('Settings carry exactly six fields.');
    }
    final level = p['level'];
    if (level != 'tenant' && level != 'entity') {
      throw const FormatException('Settings apply to the tenant or entity.');
    }
    AssuranceSettings.fromJson({...p, 'source': level});
  }
}

/// True only when the receipt reports [level] one version later.
bool assuranceSettingsReceiptConfirms(
  Map<String, Object?> r,
  String level,
  int expectedVersion,
) => r['level'] == level && r['version'] == expectedVersion + 1;

Map<String, Object?> _map(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw const FormatException('Object expected.');
}

List<Object?> _list(Object? v) {
  if (v is List) return v;
  throw const FormatException('List expected.');
}

int _int(Object? v, int lo, int hi) {
  if (v is! int || v < lo || v > hi) {
    throw FormatException('A whole number from $lo to $hi is required.');
  }
  return v;
}
