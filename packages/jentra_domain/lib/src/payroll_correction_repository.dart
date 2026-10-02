import 'calendar_repository.dart';
import 'commands.dart';
import 'employee.dart';
import 'money.dart';
import 'payroll_repository.dart';
import 'tenant_context.dart';
import 'workforce.dart';

enum PayrollCorrectionCommandKind { correction, settlement }

final class PayrollCorrectionCommands {
  static const fields =
      <PayrollCorrectionCommandKind, Map<String, Set<String>>>{
        PayrollCorrectionCommandKind.correction: {
          'prepare': {
            'action',
            'id',
            'original_calculation_id',
            'posting_date',
            'replacements',
            'reason',
          },
          'approve': {'action', 'id', 'digest', 'reason'},
          'reject': {'action', 'id', 'digest', 'reason'},
          'post': {'action', 'id', 'digest', 'reason'},
          'reverse': {
            'action',
            'id',
            'digest',
            'posting_date',
            'reason',
            'current_billing_impacts',
          },
        },
        PayrollCorrectionCommandKind.settlement: {
          'record': {
            'action',
            'id',
            'correction_id',
            'posting_date',
            'bank_id',
            'bank_version',
            'direction',
            'evidence_reference',
            'allocations',
            'reason',
          },
          'reverse': {
            'action',
            'id',
            'correction_id',
            'posting_date',
            'reason',
          },
        },
      };
  static String capability(PayrollCorrectionCommandKind kind, String action) =>
      kind == PayrollCorrectionCommandKind.settlement
      ? 'people.payroll.settle'
      : switch (action) {
          'prepare' => 'people.payroll.correction.prepare',
          'approve' || 'reject' => 'people.payroll.correction.approve',
          'post' => 'people.payroll.post',
          'reverse' => 'people.payroll.reverse',
          _ => throw const FormatException(
            'Payroll correction action is invalid.',
          ),
        };
  static void validate(
    PayrollCorrectionCommandKind kind,
    Map<String, Object?> p,
    int version,
  ) {
    final action = p['action'] as String?, allowed = fields[kind]?[action];
    if (allowed == null ||
        p.keys.toSet().difference(allowed).isNotEmpty ||
        version < 0 ||
        version > 9007199254740991) {
      throw const FormatException(
        'Payroll correction fields or version are invalid.',
      );
    }
    calendarUuid(p['id']);
    workforceText(p['reason'], 1000);
    if (p['posting_date'] != null) {
      CivilDate.parse(p['posting_date'] as String);
    }
    if (kind == PayrollCorrectionCommandKind.correction) {
      if (action == 'prepare') {
        calendarUuid(p['original_calculation_id']);
        if (version != 0 || p['posting_date'] == null) {
          throw const FormatException(
            'A new correction requires an explicit posting date.',
          );
        }
        final rows = p['replacements'] as List, ids = <String>{};
        if (rows.isEmpty || rows.length > 200) {
          throw const FormatException('Correction source bound is invalid.');
        }
        for (final value in rows) {
          final r = workforceMap(value);
          calendarFields(r, {
            'seal_id',
            'before_revision_id',
            'expected_version',
            'paid_seconds',
            if (r.containsKey('impact')) 'impact',
          });
          if (!ids.add(calendarUuid(r['seal_id']))) {
            throw const FormatException('Duplicate correction source.');
          }
          calendarUuid(r['before_revision_id']);
          workforceInteger(r['expected_version'], positive: true);
          final seconds = workforceInteger(r['paid_seconds']);
          if (seconds > 129600) {
            throw const FormatException(
              'Correction seconds exceed the source bound.',
            );
          }
          if (r['impact'] != null) {
            final impact = workforceMap(r['impact']);
            calendarFields(impact, {
              'mode',
              'expected_source_version',
              if (impact['mode'] == 'geometry') ...{
                'start_local',
                'end_local',
                'start_offset_seconds',
                'end_offset_seconds',
                'breaks',
              },
              if (impact.containsKey('billing_credit_line_ids'))
                'billing_credit_line_ids',
              if (impact.containsKey('allocation_changes'))
                'allocation_changes',
            });
            if (!{'geometry', 'cancel_leave'}.contains(impact['mode'])) {
              throw const FormatException(
                'Correction source impact is invalid.',
              );
            }
            workforceInteger(impact['expected_source_version'], positive: true);
            if (impact['mode'] == 'geometry') {
              for (final key in ['start_local', 'end_local']) {
                if (impact[key] is! String ||
                    !RegExp(
                      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$',
                    ).hasMatch(impact[key] as String)) {
                  throw const FormatException(
                    'Select whole-second local times.',
                  );
                }
              }
              for (final key in [
                'start_offset_seconds',
                'end_offset_seconds',
              ]) {
                if (impact[key] is! int || (impact[key] as int).abs() > 64800) {
                  throw const FormatException(
                    'Select a valid resolved UTC offset.',
                  );
                }
              }
              if (impact['breaks'] is! List ||
                  (impact['breaks'] as List).length > 100) {
                throw const FormatException('Break bound is invalid.');
              }
            } else if (seconds != 0) {
              throw const FormatException(
                'Cancelled leave has no payroll eligibility.',
              );
            }
            if (impact['billing_credit_line_ids'] != null) {
              final credits = impact['billing_credit_line_ids'] as List;
              if (credits.length > 50 ||
                  credits.map(calendarUuid).toSet().length != credits.length) {
                throw const FormatException(
                  'Billing credit lineage is invalid.',
                );
              }
            }
            if (impact['allocation_changes'] != null) {
              final changes = impact['allocation_changes'] as List,
                  entries = <String>{};
              if (changes.length > 50) {
                throw const FormatException(
                  'Allocation impact bound is invalid.',
                );
              }
              for (final value in changes) {
                final change = workforceMap(value);
                calendarFields(change, {
                  'entry_id',
                  'mode',
                  if (change['mode'] == 'geometry') ...{
                    'start_local',
                    'end_local',
                    'start_offset_seconds',
                    'end_offset_seconds',
                    'breaks',
                  },
                  if (change.containsKey('billing_credit_line_ids'))
                    'billing_credit_line_ids',
                });
                if (!entries.add(calendarUuid(change['entry_id'])) ||
                    !{
                      'retain',
                      'geometry',
                      'remove',
                    }.contains(change['mode'])) {
                  throw const FormatException(
                    'Allocation impact identity or mode is invalid.',
                  );
                }
                if (change['mode'] == 'geometry') {
                  for (final key in ['start_local', 'end_local']) {
                    if (change[key] is! String ||
                        !RegExp(
                          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$',
                        ).hasMatch(change[key] as String)) {
                      throw const FormatException(
                        'Select whole-second allocated local times.',
                      );
                    }
                  }
                  for (final key in [
                    'start_offset_seconds',
                    'end_offset_seconds',
                  ]) {
                    if (change[key] is! int ||
                        (change[key] as int).abs() > 64800) {
                      throw const FormatException(
                        'Select a valid allocated UTC offset.',
                      );
                    }
                  }
                  if (change['breaks'] is! List ||
                      (change['breaks'] as List).length > 100) {
                    throw const FormatException(
                      'Allocated break bound is invalid.',
                    );
                  }
                }
                if (change['billing_credit_line_ids'] != null) {
                  final credits = change['billing_credit_line_ids'] as List;
                  if (credits.length > 50 ||
                      credits.map(calendarUuid).toSet().length !=
                          credits.length) {
                    throw const FormatException(
                      'Allocated billing credit lineage is invalid.',
                    );
                  }
                }
              }
            }
          }
        }
      } else {
        payrollDigest(p['digest']);
        if (action == 'reverse' && p['current_billing_impacts'] != null) {
          final impacts = p['current_billing_impacts'] as List;
          final seals = <String>{};
          if (impacts.length > 50) {
            throw const FormatException(
              'Current billing impact bound is invalid.',
            );
          }
          for (final value in impacts) {
            final impact = workforceMap(value);
            calendarFields(impact, {
              'seal_id',
              'source_revision_id',
              'expected_source_version',
              'billing_credit_line_ids',
              'allocation_credits',
            });
            if (!seals.add(calendarUuid(impact['seal_id']))) {
              throw const FormatException('Duplicate current billing source.');
            }
            _currentCredits(impact);
            final allocations = impact['allocation_credits'] as List;
            final entries = <String>{};
            if (allocations.length > 50) {
              throw const FormatException(
                'Current allocated billing bound is invalid.',
              );
            }
            for (final row in allocations) {
              final allocation = workforceMap(row);
              calendarFields(allocation, {
                'entry_id',
                'source_revision_id',
                'expected_source_version',
                'billing_credit_line_ids',
              });
              if (!entries.add(calendarUuid(allocation['entry_id']))) {
                throw const FormatException(
                  'Duplicate current allocated source.',
                );
              }
              _currentCredits(allocation);
            }
          }
        }
        if (version < 1 || action == 'reverse' && p['posting_date'] == null) {
          throw const FormatException(
            'Correction decision needs the current version.',
          );
        }
      }
    } else {
      calendarUuid(p['correction_id']);
      if (p['posting_date'] == null) {
        throw const FormatException('Settlement date is required.');
      }
      if (action == 'record') {
        calendarUuid(p['bank_id']);
        workforceInteger(p['bank_version'], positive: true);
        workforceText(p['evidence_reference'], 160);
        if (version != 0 || !{'pay', 'recover'}.contains(p['direction'])) {
          throw const FormatException('Settlement direction is invalid.');
        }
        final rows = p['allocations'] as List, ids = <String>{};
        if (rows.isEmpty || rows.length > 200) {
          throw const FormatException(
            'Settlement allocation bound is invalid.',
          );
        }
        for (final value in rows) {
          final r = workforceMap(value);
          calendarFields(r, {'balance_id', 'amount'});
          if (!ids.add(calendarUuid(r['balance_id'])) ||
              Money.parse(r['amount'] as String, 'XXX').minorUnits <=
                  BigInt.zero) {
            throw const FormatException('Settlement allocation is invalid.');
          }
        }
      } else if (version < 1) {
        throw const FormatException(
          'Settlement reversal requires its recorded version.',
        );
      }
    }
  }

  static void _currentCredits(Map<String, Object?> row) {
    calendarUuid(row['source_revision_id']);
    workforceInteger(row['expected_source_version'], positive: true);
    final credits = row['billing_credit_line_ids'] as List;
    if (credits.length > 50 ||
        credits.map(calendarUuid).toSet().length != credits.length) {
      throw const FormatException('Current posted credit identity is invalid.');
    }
  }
}

abstract interface class PayrollCorrectionRepository {
  Future<WorkforcePage<Map<String, Object?>>> correctionCredits(
    TenantContext scope,
    String sourceRevisionId, {
    String? after,
  });
  Future<void> authorize(TenantContext scope, String capability);
  Future<WorkforcePage<Map<String, Object?>>> correctionOriginals(
    TenantContext scope, {
    String? after,
  });
  Future<WorkforcePage<Map<String, Object?>>> correctionSources(
    TenantContext scope,
    String calculationId, {
    String? after,
  });
  Future<WorkforcePage<Map<String, Object?>>> corrections(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> correctionDetail(
    TenantContext scope,
    String id,
    String section, {
    String? after,
  });
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String commandId,
    String capability,
  );
  Future<Map<String, Object?>> executeCorrection(
    PayrollCorrectionCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  );
}
