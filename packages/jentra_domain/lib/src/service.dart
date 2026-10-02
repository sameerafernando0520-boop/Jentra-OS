import 'dart:convert';
import 'calendar_repository.dart';
import 'commands.dart';
import 'errors.dart';
import 'employee.dart';
import 'money.dart';
import 'tenant_context.dart';
import 'workforce.dart';

const serviceCapabilities = {
  'service.view',
  'service.configure',
  'service.triage',
  'service.dispatch',
  'service.work',
  'service.approve',
  'service.cost.view',
  'service.maintenance',
  'service.billing',
};
String serviceText(Object? x, [int max = 160]) {
  if (x is! String ||
      x.isEmpty ||
      x.length > max ||
      x != x.trim() ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(x)) {
    throw const FormatException(
      'Service text must be trimmed and contain no controls.',
    );
  }
  return x;
}

int serviceInt(Object? x, {int max = 9007199254740991, int min = 0}) {
  if (x is! int || x < min || x > max) {
    throw const FormatException('Service integer is outside its exact bound.');
  }
  return x;
}

DateTime serviceUtc(Object? x) {
  if (x is! String) {
    throw const FormatException('UTC instant is required.');
  }
  final instant = DateTime.tryParse(x);
  if (instant == null ||
      x.length < 19 ||
      instant.toUtc().toIso8601String().substring(0, 19) !=
          x.substring(0, 19) ||
      !instant.isUtc ||
      instant.microsecond != 0 ||
      instant.millisecond != 0 ||
      instant.year < 1 ||
      instant.year > 9999) {
    throw const FormatException('Whole-second UTC instant is required.');
  }
  return instant;
}

Money serviceAmount(Object? x, Object? currency) {
  if (x is! String ||
      !RegExp(r'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$').hasMatch(x) ||
      currency is! String ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    throw const FormatException('Exact service money is required.');
  }
  return Money.parse(x, currency);
}

String serviceDigest(Object? x) {
  if (x is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(x)) {
    throw const FormatException('Service digest is required.');
  }
  return x;
}

String serviceCode(Object? x) {
  final s = serviceText(x, 32);
  if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(s)) {
    throw const FormatException('Service code is invalid.');
  }
  return s;
}

String serviceInstant(DateTime x) =>
    '${x.toUtc().toIso8601String().substring(0, 19)}Z';
Map<String, Object?> serviceMap(Object? x) => workforceMap(x);
Map<String, Object?> _copy(Object? x) => serviceMap(jsonDecode(jsonEncode(x)));
void serviceScope(Map<String, Object?> row, TenantContext scope) {
  if (row['tenant_id'] != scope.tenantId ||
      row['legal_entity_id'] != scope.legalEntityId ||
      row['branch_id'] != scope.branchId) {
    throw const FormatException('Service response scope changed.');
  }
}

final class ServiceWindow {
  ServiceWindow(this.start, this.end) {
    if (!start.isUtc ||
        !end.isUtc ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(hours: 36) ||
        start.microsecondsSinceEpoch % 1000000 != 0 ||
        end.microsecondsSinceEpoch % 1000000 != 0) {
      throw const FormatException('Working window is invalid.');
    }
  }
  final DateTime start, end;
}

final class ServiceClock {
  ServiceClock(Iterable<ServiceWindow> input)
    : windows = List.unmodifiable(input) {
    if (windows.isEmpty || windows.length > 2000) {
      throw const FormatException('SLA windows exceed their bounded horizon.');
    }
    for (var i = 1; i < windows.length; i++) {
      if (windows[i].start.isBefore(windows[i - 1].end)) {
        throw const FormatException('SLA windows overlap or are unordered.');
      }
    }
  }
  final List<ServiceWindow> windows;
  int elapsed(DateTime start, DateTime end) {
    if (end.isBefore(start)) {
      throw const FormatException('SLA cannot move backwards.');
    }
    var seconds = 0;
    for (final w in windows) {
      final a = start.isAfter(w.start) ? start : w.start;
      final b = end.isBefore(w.end) ? end : w.end;
      if (b.isAfter(a)) {
        seconds += b.difference(a).inSeconds;
      }
    }
    return seconds;
  }

  DateTime due(DateTime from, int remaining) {
    if (remaining <= 0) {
      return from;
    }
    serviceInt(remaining, max: 31622400);
    for (final w in windows) {
      final a = from.isAfter(w.start) ? from : w.start;
      if (!w.end.isAfter(a)) {
        continue;
      }
      final span = w.end.difference(a).inSeconds;
      if (remaining <= span) {
        return a.add(Duration(seconds: remaining));
      }
      remaining -= span;
    }
    throw const DomainError(
      code: 'SERVICE_SLA_HORIZON_EXHAUSTED',
      message: 'Publish a policy covering the remaining SLA horizon.',
    );
  }
}

Money serviceLaborCost(Money hourly, int seconds, int precision) {
  serviceInt(seconds, max: 129600);
  serviceInt(precision, max: 6);
  if (hourly.minorUnits.isNegative) {
    throw const FormatException('Synthetic rate cannot be negative.');
  }
  final quantum = BigInt.from(10).pow(6 - precision);
  final n = hourly.minorUnits * BigInt.from(seconds),
      d = BigInt.from(3600) * quantum;
  var q = n ~/ d;
  final r = n.remainder(d);
  if (r * BigInt.two > d || r * BigInt.two == d && q.isOdd) {
    q += BigInt.one;
  }
  final amount = q * quantum;
  if (amount >= BigInt.from(10).pow(20)) {
    throw const FormatException('Service cost exceeds exact storage bounds.');
  }
  return Money.fromMinorUnits(amount, hourly.currencyCode);
}

enum ServiceMeterKind { initial, reading, reset, rollover }

final class ServiceMeter {
  ServiceMeter(this.raw, this.logical) {
    serviceInt(raw);
    serviceInt(logical);
  }
  final int raw, logical;
  ServiceMeter next(ServiceMeterKind kind, int value, {int? rolloverMaximum}) {
    serviceInt(value);
    final delta = switch (kind) {
      ServiceMeterKind.initial => throw const FormatException(
        'A meter already has its initial reading.',
      ),
      ServiceMeterKind.reading =>
        value >= raw
            ? value - raw
            : throw const FormatException(
                'Decreased reading requires reset or rollover.',
              ),
      ServiceMeterKind.reset => value,
      ServiceMeterKind.rollover =>
        rolloverMaximum != null && rolloverMaximum >= raw && value < raw
            ? serviceInt(rolloverMaximum) - raw + 1 + value
            : throw const FormatException('Rollover evidence is invalid.'),
    };
    return ServiceMeter(value, serviceInt(logical + delta));
  }
}

enum ServiceKind {
  equipment,
  coverage,
  policy,
  ticket,
  order,
  labor,
  plan,
  reading,
  occurrence,
}

const _common = {
  'id',
  'tenant_id',
  'legal_entity_id',
  'branch_id',
  'version',
  'created_at',
  'created_by',
};
const serviceRecordFields = <ServiceKind, Set<String>>{
  ServiceKind.equipment: {
    'code',
    'name',
    'identity',
    'kind',
    'customer_id',
    'provider_id',
    'status',
  },
  ServiceKind.coverage: {
    'equipment_id',
    'kind',
    'start_date',
    'end_date_exclusive',
    'name',
    'evidence_reference',
  },
  ServiceKind.policy: {
    'name',
    'calendar_version_id',
    'start_date',
    'end_date_exclusive',
    'response_seconds',
    'resolution_seconds',
    'independent_closure',
  },
  ServiceKind.ticket: {
    'code',
    'name',
    'classification',
    'customer_id',
    'contact_id',
    'equipment_id',
    'coverage_id',
    'policy_id',
    'priority',
    'owner_id',
    'status',
    'started_utc',
    'clock_start_utc',
    'consumed_seconds',
    'response_due',
    'resolution_due',
    'response_at',
    'resolution_at',
    'response_breached',
    'resolution_breached',
  },
  ServiceKind.order: {
    'accepted_utc',
    'work_started_utc',
    'completed_utc',
    'closed_at',
    'ticket_id',
    'status',
    'employee_id',
    'accepted_by',
    'completed_by',
    'closed_by',
    'resolution',
    'customer_confirmed',
    'exception_reason',
  },
  ServiceKind.labor: {
    'current_revision_id',
    'start_local',
    'end_local',
    'start_offset_seconds',
    'end_offset_seconds',
    'order_id',
    'employee_id',
    'calendar_version_id',
    'start_utc',
    'end_utc',
    'breaks',
    'seconds',
    'claim_id',
    'allocation_ids',
    'owns_claim',
    'hourly_cost',
    'amount',
    'currency_code',
    'precision',
    'digest',
    'status',
    'submitted_by',
    'approved_by',
    'billing_consumption_id',
    'reason',
    'billing_kind',
    'hourly_billing',
    'billable_amount',
    'billing_reference',
  },
  ServiceKind.plan: {
    'equipment_id',
    'policy_id',
    'name',
    'basis',
    'interval_units',
    'next_date',
    'next_meter',
  },
  ServiceKind.reading: {
    'equipment_id',
    'kind',
    'raw_value',
    'logical_value',
    'previous_id',
    'rollover_max',
    'observed_utc',
    'reason',
    'recorded_by',
  },
  ServiceKind.occurrence: {
    'plan_id',
    'plan_version',
    'occurrence_key',
    'original_due_date',
    'original_due_meter',
    'deferred_until',
    'ticket_id',
    'order_id',
    'reading_id',
    'reason',
  },
};

final class ServiceRecord {
  ServiceRecord.fromJson(this.kind, Map<String, Object?> row)
    : _wire = jsonEncode(row),
      id = calendarUuid(row['id']),
      tenantId = calendarUuid(row['tenant_id']),
      entityId = calendarUuid(row['legal_entity_id']),
      branchId = calendarUuid(row['branch_id']),
      version = serviceInt(row['version'], min: 1) {
    final allowed = {..._common, ...serviceRecordFields[kind]!};
    if (row.keys.any((k) => !allowed.contains(k)) ||
        !row.keys.toSet().containsAll({
          'id',
          'tenant_id',
          'legal_entity_id',
          'branch_id',
          'version',
        })) {
      throw const FormatException('Service projection has unexpected fields.');
    }
    for (final entry in row.entries) {
      if (entry.key.endsWith('_id') ||
          {
            'created_by',
            'recorded_by',
            'submitted_by',
            'approved_by',
            'accepted_by',
            'completed_by',
            'closed_by',
          }.contains(entry.key)) {
        if (entry.value != null) {
          calendarUuid(entry.value);
        }
      }
    }
    switch (kind) {
      case ServiceKind.equipment:
        serviceCode(row['code']);
        serviceText(row['name']);
        serviceText(row['identity']);
        _one(row['kind'], {'customer', 'asset', 'stock'});
        _one(row['status'], {'active', 'retired'});
      case ServiceKind.coverage:
        serviceText(row['name']);
        serviceText(row['evidence_reference']);
        _one(row['kind'], {'contract', 'warranty'});
        _dates(row);
      case ServiceKind.policy:
        serviceText(row['name']);
        _dates(row);
        serviceInt(row['response_seconds'], min: 1, max: 31622400);
        serviceInt(row['resolution_seconds'], min: 1, max: 31622400);
        if ((row['response_seconds'] as int) >
                (row['resolution_seconds'] as int) ||
            row['independent_closure'] is! bool) {
          throw const FormatException('SLA policy is invalid.');
        }
      case ServiceKind.ticket:
        serviceCode(row['code']);
        serviceText(row['name']);
        serviceText(row['classification'], 80);
        _one(row['priority'], {'low', 'normal', 'high', 'urgent'});
        _one(row['status'], {
          'open',
          'paused',
          'resolved',
          'closed',
          'cancelled',
        });
        for (final k in {
          'started_utc',
          'clock_start_utc',
          'response_due',
          'resolution_due',
        }) {
          serviceUtc(row[k]);
        }
        for (final k in {'response_at', 'resolution_at'}) {
          if (row[k] != null) {
            serviceUtc(row[k]);
          }
        }
        serviceInt(row['consumed_seconds']);
        if (row['response_breached'] is! bool ||
            row['resolution_breached'] is! bool) {
          throw const FormatException('SLA breach evidence is invalid.');
        }
      case ServiceKind.order:
        for (final key in {
          'accepted_utc',
          'work_started_utc',
          'completed_utc',
          'closed_at',
        }) {
          if (row[key] != null) {
            serviceUtc(row[key]);
          }
        }
        _one(row['status'], {
          'planned',
          'dispatched',
          'accepted',
          'working',
          'completed',
          'closed',
          'cancelled',
        });
        if (row['resolution'] != null) {
          serviceText(row['resolution'], 1000);
        }
        if ({'completed', 'closed'}.contains(row['status']) &&
            (row['completed_by'] == null ||
                row['customer_confirmed'] is! bool ||
                row['customer_confirmed'] == false &&
                    row['exception_reason'] == null)) {
          throw const FormatException('Completion evidence is incomplete.');
        }
      case ServiceKind.labor:
        final start = serviceUtc(row['start_utc']),
            end = serviceUtc(row['end_utc']);
        serviceInt(
          row['seconds'],
          min: row['status'] == 'cancelled' ? 0 : 1,
          max: 129600,
        );
        serviceInt(row['precision'], max: 6);
        serviceDigest(row['digest']);
        _one(row['status'], {'submitted', 'approved', 'cancelled'});
        if (end.difference(start).inSeconds < (row['seconds'] as int) ||
            row['owns_claim'] is! bool ||
            row['allocation_ids'] is! List ||
            (row['allocation_ids'] as List).length > 17) {
          throw const FormatException('Labor ownership evidence changed.');
        }
        for (final id in row['allocation_ids'] as List) {
          calendarUuid(id);
        }
        if (row.containsKey('amount') != row.containsKey('hourly_cost')) {
          throw const FormatException('Cost projection is incomplete.');
        }
        if (row['amount'] != null &&
            serviceLaborCost(
                  serviceAmount(row['hourly_cost'], row['currency_code']),
                  row['seconds'] as int,
                  row['precision'] as int,
                ) !=
                serviceAmount(row['amount'], row['currency_code'])) {
          throw const FormatException('Labor cost cannot be reproduced.');
        }
        if (row.containsKey('billing_kind')) {
          _one(row['billing_kind'], {'billable', 'nonbillable'});
          serviceText(row['billing_reference']);
          final rate = serviceAmount(
                row['hourly_billing'],
                row['currency_code'],
              ),
              bill = serviceAmount(
                row['billable_amount'],
                row['currency_code'],
              );
          if (serviceLaborCost(
                    rate,
                    row['seconds'] as int,
                    row['precision'] as int,
                  ) !=
                  bill ||
              row['billing_kind'] == 'nonbillable' &&
                  rate.minorUnits != BigInt.zero) {
            throw const FormatException('Billing basis cannot be reproduced.');
          }
        }
        if (row['status'] == 'approved' &&
            (row['claim_id'] == null ||
                (row['allocation_ids'] as List).isEmpty ||
                row['approved_by'] == row['submitted_by'])) {
          throw const FormatException('Labor approval lineage is incomplete.');
        }
      case ServiceKind.plan:
        serviceText(row['name']);
        serviceInt(row['interval_units'], min: 1);
        _one(row['basis'], {'calendar', 'meter'});
        if (row['basis'] == 'calendar') {
          CivilDate.parse(row['next_date'] as String);
        } else {
          serviceInt(row['next_meter'], min: 1);
        }
      case ServiceKind.reading:
        ServiceMeter(
          serviceInt(row['raw_value']),
          serviceInt(row['logical_value']),
        );
        serviceUtc(row['observed_utc']);
        _one(row['kind'], {'initial', 'reading', 'reset', 'rollover'});
      case ServiceKind.occurrence:
        serviceText(row['occurrence_key']);
        serviceInt(row['plan_version'], min: 1);
        if (row['original_due_date'] == null &&
            row['original_due_meter'] == null) {
          throw const FormatException(
            'Occurrence needs original due evidence.',
          );
        }
    }
  }
  final ServiceKind kind;
  final String id, tenantId, entityId, branchId, _wire;
  final int version;
  Map<String, Object?> toJson() => _copy(jsonDecode(_wire));
  String get label {
    final row = toJson();
    return (row['name'] ??
            row['code'] ??
            row['occurrence_key'] ??
            '${kind.name} ${id.substring(0, 8)}')
        as String;
  }

  String? get status => toJson()['status'] as String?;
  static void _one(Object? x, Set<String> values) {
    if (!values.contains(x)) {
      throw const FormatException('Service state is invalid.');
    }
  }

  static void _dates(Map<String, Object?> row) {
    if (CivilDate.parse(
          row['end_date_exclusive'] as String,
        ).compareTo(CivilDate.parse(row['start_date'] as String)) <=
        0) {
      throw const FormatException('Date coverage is invalid.');
    }
  }
}

final class ServiceEvent {
  ServiceEvent.fromJson(Map<String, Object?> row)
    : _wire = jsonEncode(row),
      id = calendarUuid(row['id']),
      aggregateId = calendarUuid(row['aggregate_id']),
      version = serviceInt(row['version'], min: 1) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'aggregate_id',
      'kind',
      'version',
      'action',
      'reason',
      'facts',
      'actor_id',
      'recorded_at',
    });
    calendarUuid(row['actor_id']);
    serviceUtc(
      row['recorded_at']
          .toString()
          .replaceFirst(RegExp(r'\.\d+'), '')
          .replaceFirst('+00:00', 'Z'),
    );
    serviceText(row['reason'], 1000);
    serviceText(row['action']);
    final facts = ServiceRecord.fromJson(
      ServiceKind.values.byName(row['kind'] as String),
      serviceMap(row['facts']),
    );
    if (facts.id != aggregateId ||
        facts.version != version ||
        facts.tenantId != row['tenant_id'] ||
        facts.entityId != row['legal_entity_id'] ||
        facts.branchId != row['branch_id']) {
      throw const FormatException('Service event lineage changed.');
    }
  }
  final String id, aggregateId, _wire;
  final int version;
  Map<String, Object?> toJson() => _copy(jsonDecode(_wire));
}

final class ServicePage<T> {
  const ServicePage(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

final class ServiceDetail {
  const ServiceDetail(this.record, this.events, this.nextCursor);
  final ServiceRecord record;
  final List<ServiceEvent> events;
  final String? nextCursor;
}

final class ServiceChoice {
  ServiceChoice.fromJson(Map<String, Object?> r)
    : id = calendarUuid(r['id']),
      name = serviceText(r['name']),
      version = serviceInt(r['version'], min: 1) {
    calendarFields(r, {'id', 'name', 'version'});
  }
  final String id, name;
  final int version;
}

final class ServiceAuthority {
  const ServiceAuthority(
    this.currency,
    this.precision, {
    required this.parts,
    required this.billing,
    required this.assets,
  });
  final String currency;
  final int precision;
  final bool parts, billing, assets;
}

final class ServiceCommands {
  static const extras = <String, Set<String>>{
    'equipment': {
      'code',
      'name',
      'identity',
      'kind',
      'customer_id',
      'provider_id',
    },
    'coverage': {
      'equipment_id',
      'kind',
      'name',
      'start_date',
      'end_date_exclusive',
      'evidence_reference',
    },
    'policy': {
      'name',
      'calendar_version_id',
      'start_date',
      'end_date_exclusive',
      'response_seconds',
      'resolution_seconds',
      'independent_closure',
      'offsets',
    },
    'ticket': {
      'code',
      'name',
      'classification',
      'customer_id',
      'contact_id',
      'equipment_id',
      'coverage_id',
      'policy_id',
      'priority',
      'owner_id',
      'observed_utc',
    },
    'order': {'ticket_id'},
    'dispatch': {
      'employee_id',
      'calendar_version_id',
      'start_utc',
      'end_utc',
      'booking_id',
    },
    'complete': {
      'observed_utc',
      'resolution',
      'customer_confirmed',
      'exception_reason',
    },
    'accept': {'observed_utc'},
    'start': {'observed_utc'},
    'close': {},
    'cancel_order': {},
    'cancel_ticket': {},
    'approve_labor': {},
    'cancel_labor': {},
    'labor': {
      'order_id',
      'employee_id',
      'calendar_version_id',
      'start_utc',
      'end_utc',
      'breaks',
      'claim_id',
      'hourly_cost',
      'currency_code',
      'precision',
      'billing_kind',
      'hourly_billing',
      'billing_reference',
    },
    'plan': {
      'equipment_id',
      'policy_id',
      'name',
      'basis',
      'interval_units',
      'next_date',
      'next_meter',
    },
    'reading': {
      'equipment_id',
      'kind',
      'raw_value',
      'rollover_max',
      'observed_utc',
    },
    'generate': {'ticket_id', 'order_id', 'occurrence_id', 'observed_utc'},
    'defer': {'deferred_until'},
    'reprioritize': {'policy_id', 'priority', 'observed_utc'},
    'pause': {'observed_utc'},
    'resume': {'observed_utc'},
    'evaluate': {'observed_utc'},
    'parts_reserve': {},
    'parts_issue': {},
    'parts_return': {},
    'bill': {},
  };
  static Set<String> fields(String action) {
    final x = extras[action];
    if (x == null) {
      throw const FormatException('Service action is invalid.');
    }
    return {'action', 'id', 'reason', ...x};
  }

  static String capability(String action) => switch (action) {
    'equipment' || 'coverage' || 'policy' || 'plan' => 'service.configure',
    'ticket' ||
    'pause' ||
    'resume' ||
    'reprioritize' ||
    'evaluate' ||
    'cancel_ticket' => 'service.triage',
    'order' || 'dispatch' || 'cancel_order' => 'service.dispatch',
    'accept' || 'start' || 'complete' || 'labor' => 'service.work',
    'approve_labor' || 'cancel_labor' || 'close' => 'service.approve',
    'reading' || 'generate' || 'defer' => 'service.maintenance',
    _ => 'service.billing',
  };
  static ServiceKind kind(String action) => switch (action) {
    'equipment' => ServiceKind.equipment,
    'coverage' => ServiceKind.coverage,
    'policy' => ServiceKind.policy,
    'order' ||
    'dispatch' ||
    'accept' ||
    'start' ||
    'complete' ||
    'close' ||
    'cancel_order' ||
    'parts_reserve' ||
    'parts_issue' ||
    'parts_return' => ServiceKind.order,
    'labor' || 'approve_labor' || 'cancel_labor' || 'bill' => ServiceKind.labor,
    'plan' || 'generate' => ServiceKind.plan,
    'reading' => ServiceKind.reading,
    'defer' => ServiceKind.occurrence,
    _ => ServiceKind.ticket,
  };
  static void validate(String action, Map<String, Object?> row) {
    if (row['action'] != action ||
        row.keys.any((k) => !fields(action).contains(k)) ||
        utf8.encode(jsonEncode(row)).length > 65536) {
      throw const FormatException('Service command fields are invalid.');
    }
    calendarUuid(row['id']);
    serviceText(row['reason'], 1000);
    for (final entry in row.entries) {
      final k = entry.key, x = entry.value;
      if (k.endsWith('_id') && x != null) {
        calendarUuid(x);
      }
      if (k.endsWith('_utc') && x != null) {
        if (x is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(x)) {
          throw const FormatException(
            'Command instant requires whole-second UTC.',
          );
        }
        serviceUtc(x);
      }
    }
    for (final k in {
      'name',
      'identity',
      'classification',
      'evidence_reference',
      'resolution',
      'exception_reason',
    }) {
      if (row[k] != null) {
        serviceText(
          row[k],
          {'resolution', 'exception_reason'}.contains(k) ? 1000 : 160,
        );
      }
    }
    if (row['code'] != null) {
      serviceCode(row['code']);
    }
    for (final k in extras[action]!) {
      if ({
        'customer_id',
        'provider_id',
        'contact_id',
        'coverage_id',
        'owner_id',
        'claim_id',
        'rollover_max',
        'exception_reason',
        'next_date',
        'next_meter',
        'billing_kind',
        'hourly_billing',
        'billing_reference',
      }.contains(k)) {
        continue;
      }
      if (!row.containsKey(k) || row[k] == null) {
        throw const FormatException('Required service evidence is missing.');
      }
    }
    if ({'coverage', 'policy'}.contains(action)) {
      final a = CivilDate.parse(row['start_date'] as String),
          b = CivilDate.parse(row['end_date_exclusive'] as String);
      if (b.compareTo(a) <= 0) {
        throw const FormatException('Coverage end must follow start.');
      }
    }
    if (action == 'equipment') {
      if (row['kind'] != 'customer' ||
          row['customer_id'] == null ||
          row['provider_id'] != null) {
        throw const DomainError(
          code: 'SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE',
          message:
              'Choose customer equipment until its asset or stock provider is installed.',
        );
      }
    }
    if (action == 'ticket') {
      if (row['customer_id'] == null ||
          !{'low', 'normal', 'high', 'urgent'}.contains(row['priority'])) {
        throw const FormatException('Customer and priority are required.');
      }
    }
    if ({'labor', 'dispatch'}.contains(action)) {
      final a = serviceUtc(row['start_utc']), b = serviceUtc(row['end_utc']);
      if (!b.isAfter(a) || b.difference(a) > const Duration(hours: 36)) {
        throw const FormatException('Work interval is invalid.');
      }
    }
    if (action == 'labor') {
      final a = serviceUtc(row['start_utc']), b = serviceUtc(row['end_utc']);
      final breaks = row['breaks'];
      if (breaks is! List || breaks.length > 16) {
        throw const FormatException('Labor breaks are invalid.');
      }
      var previous = a, total = 0;
      for (final value in breaks) {
        final br = serviceMap(value);
        calendarFields(br, {'start_utc', 'end_utc'});
        final s = serviceUtc(br['start_utc']), e = serviceUtc(br['end_utc']);
        if (s.isBefore(previous) || !e.isAfter(s) || e.isAfter(b)) {
          throw const FormatException(
            'Breaks must be ordered inside the work interval.',
          );
        }
        previous = e;
        total += e.difference(s).inSeconds;
      }
      if (b.difference(a).inSeconds <= total) {
        throw const FormatException(
          'Labor must contain a payable interval outside its breaks.',
        );
      }
      serviceAmount(row['hourly_cost'], row['currency_code']);
      serviceInt(row['precision'], max: 6);
      if (row['billing_kind'] != null) {
        if (!{'billable', 'nonbillable'}.contains(row['billing_kind'])) {
          throw const FormatException('Billing eligibility is required.');
        }
        final rate = serviceAmount(row['hourly_billing'], row['currency_code']);
        serviceText(row['billing_reference']);
        if (row['billing_kind'] == 'nonbillable' &&
            rate.minorUnits != BigInt.zero) {
          throw const FormatException(
            'Nonbillable work requires a zero billing rate.',
          );
        }
      }
    }
    if (action == 'complete' &&
        (row['customer_confirmed'] is! bool ||
            row['customer_confirmed'] == false &&
                (row['exception_reason'] == null ||
                    row['exception_reason'] == ''))) {
      throw const FormatException(
        'Customer confirmation or an exception reason is required.',
      );
    }
    if (action == 'policy') {
      final response = serviceInt(
            row['response_seconds'],
            min: 1,
            max: 31622400,
          ),
          resolution = serviceInt(
            row['resolution_seconds'],
            min: 1,
            max: 31622400,
          );
      if (response > resolution ||
          row['independent_closure'] is! bool ||
          row['offsets'] is! List ||
          (row['offsets'] as List).length > 2000) {
        throw const FormatException('SLA policy is incomplete.');
      }
    }
    if (action == 'reading') {
      serviceInt(row['raw_value']);
      if (!{'initial', 'reading', 'reset', 'rollover'}.contains(row['kind'])) {
        throw const FormatException('Meter transition is required.');
      }
      if (row['kind'] == 'rollover') {
        serviceInt(row['rollover_max'], min: 1);
      }
    }
    if (action == 'plan') {
      serviceInt(row['interval_units'], min: 1);
      if (row['basis'] == 'calendar') {
        CivilDate.parse(row['next_date'] as String);
        if (row['next_meter'] != null ||
            serviceInt(row['interval_units']) > 366) {
          throw const FormatException('Calendar interval is invalid.');
        }
      } else if (row['basis'] == 'meter') {
        serviceInt(row['next_meter'], min: 1);
        if (row['next_date'] != null) {
          throw const FormatException(
            'Meter plan cannot have a calendar threshold.',
          );
        }
      } else {
        throw const FormatException('Maintenance basis is required.');
      }
    }
  }
}

abstract interface class ServiceRepository {
  Future<ServiceAuthority> authorize(TenantContext scope, String capability);
  Future<ServicePage<ServiceRecord>> list(
    TenantContext scope,
    ServiceKind kind, {
    String? after,
    String? parent,
  });
  Future<ServiceDetail> detail(
    TenantContext scope,
    ServiceKind kind,
    String id, {
    String? after,
  });
  Future<ServicePage<ServiceChoice>> choices(
    TenantContext scope,
    String kind, {
    String? after,
    String? parent,
  });
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String action,
    String key,
  );
}
