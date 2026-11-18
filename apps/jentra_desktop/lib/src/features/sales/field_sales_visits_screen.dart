import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

import '../../app_providers.dart';
import 'field_company_review.dart';
import 'field_sales_reps_screen.dart';

Future<void> openFieldSalesVisits(BuildContext context, TenantContext scope) =>
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 900,
          height: 720,
          child: FieldSalesVisits(scope),
        ),
      ),
    );

const _stateLabels = {
  'planned': 'Planned',
  'checked_in': 'Checked in',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
};

/// Read-only list of the branch's Field Sales visits, as recorded by reps.
/// The company reads the same readers' permissions as the rep list.
class FieldSalesVisits extends ConsumerWidget {
  const FieldSalesVisits(this.scope, {super.key});
  final TenantContext scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authenticatedActorProvider).value;
    final revision = ref.watch(authSessionRevisionProvider).value;
    final caps = ref.watch(businessCapabilitiesProvider).value;
    final gateway = ref.watch(fieldSalesCompanyGatewayProvider);
    if (ref.watch(activeTenantContextProvider) != scope ||
        actor == null ||
        actor != scope.actorId ||
        !scope.hasOperationalScope ||
        revision == null ||
        gateway == null ||
        gateway.actorId != actor ||
        caps == null ||
        !caps.any(fieldSalesRepReaders.contains)) {
      return const Center(
        child: Text('Current company authority is required to list visits.'),
      );
    }
    return _VisitsBody(
      key: ValueKey((actor, revision, scope)),
      gateway: gateway,
      scope: FieldSalesScope(
        scope.tenantId,
        scope.legalEntityId!,
        scope.branchId!,
      ),
      today: ref.watch(fieldSalesRepClockProvider),
    );
  }
}

class _VisitsBody extends StatefulWidget {
  const _VisitsBody({
    required this.gateway,
    required this.scope,
    required this.today,
    super.key,
  });
  final FieldSalesCompanyGateway gateway;
  final FieldSalesScope scope;
  final DateTime Function() today;

  @override
  State<_VisitsBody> createState() => _VisitsBodyState();
}

class _VisitsBodyState extends State<_VisitsBody> {
  var _period = FieldSalesRepPeriod.thisMonth;
  List<FieldSalesJson>? _visits;
  String? _error;
  bool _busy = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final (from, to) = _period.range(widget.today());
    setState(() {
      _busy = true;
      _error = null;
      _visits = null;
    });
    try {
      final rows = await widget.gateway.companyVisits(
        widget.scope,
        from: from,
        to: to,
      );
      if (mounted && request == _request) {
        setState(() {
          _visits = rows;
          _busy = false;
        });
      }
    } on Object catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = e is FieldSalesFailure
              ? e.message
              : 'The visit list could not be loaded.';
          _busy = false;
        });
      }
    }
  }

  String _location(Object? value) {
    if (value is! Map) return '';
    return '${value['latitude']}, ${value['longitude']}';
  }

  @override
  Widget build(BuildContext context) {
    final visits = _visits;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Field visits',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Refresh visits',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Close visits',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in FieldSalesRepPeriod.values)
                ChoiceChip(
                  label: Text(period.label),
                  selected: period == _period,
                  onSelected: _busy || period == _period
                      ? null
                      : (_) {
                          _period = period;
                          _load();
                        },
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_error != null) Text(_error!),
              if (visits != null && visits.isEmpty)
                const Text(
                  'No visits were planned or recorded in this period.',
                ),
              if (visits != null)
                for (final v in visits)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${v['customer_name'] ?? 'Customer'} · ${_stateLabels[v['state']] ?? v['state']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('Representative: ${v['rep_label']}'),
                          Text('Purpose: ${v['purpose']}'),
                          if (v['planned_for'] != null)
                            Text('Planned for ${v['planned_for']}'),
                          if (v['checked_in_at'] != null)
                            Text(
                              'Checked in ${v['checked_in_at']}'
                              '${v['check_in_location'] == null ? '' : ' at ${_location(v['check_in_location'])}'}',
                            ),
                          if (v['completed_at'] != null)
                            Text(
                              'Completed ${v['completed_at']}'
                              '${v['complete_location'] == null ? '' : ' at ${_location(v['complete_location'])}'}',
                            ),
                          if (v['outcome'] != null)
                            Text('Outcome: ${v['outcome']}'),
                          if (v['next_action'] != null)
                            Text(
                              'Next action: ${v['next_action']}'
                              '${v['next_action_due'] == null ? '' : ' by ${v['next_action_due']}'}',
                            ),
                          if (v['cancel_reason'] != null)
                            Text('Cancelled: ${v['cancel_reason']}'),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
