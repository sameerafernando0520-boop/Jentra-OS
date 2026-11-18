import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

import '../../app_providers.dart';
import 'field_company_review.dart';

/// Company permissions that may read the rep list.
const fieldSalesRepReaders = {
  'sales.field.portfolios.manage',
  'sales.field.discounts.decide',
};

/// Today's date for the rep list periods. Tests replace it.
final fieldSalesRepClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

Future<void> openFieldSalesReps(BuildContext context, TenantContext scope) =>
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(width: 900, height: 720, child: FieldSalesReps(scope)),
      ),
    );

enum FieldSalesRepPeriod {
  thisMonth('This month'),
  last30('Last 30 days'),
  last90('Last 90 days');

  const FieldSalesRepPeriod(this.label);
  final String label;

  (DateTime, DateTime) range(DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    return switch (this) {
      thisMonth => (DateTime(day.year, day.month), day),
      last30 => (day.subtract(const Duration(days: 29)), day),
      last90 => (day.subtract(const Duration(days: 89)), day),
    };
  }
}

/// Read-only list of the branch's Field Sales reps. Labels come from HR
/// account links; targets and commission are not shown.
class FieldSalesReps extends ConsumerWidget {
  const FieldSalesReps(this.scope, {super.key});
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
        child: Text('Current company authority is required to list reps.'),
      );
    }
    return _RepsBody(
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

class _RepsBody extends StatefulWidget {
  const _RepsBody({
    required this.gateway,
    required this.scope,
    required this.today,
    super.key,
  });
  final FieldSalesCompanyGateway gateway;
  final FieldSalesScope scope;
  final DateTime Function() today;

  @override
  State<_RepsBody> createState() => _RepsBodyState();
}

class _RepsBodyState extends State<_RepsBody> {
  var _period = FieldSalesRepPeriod.thisMonth;
  FieldSalesRepList? _list;
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
      _list = null;
    });
    try {
      final list = await widget.gateway.reps(widget.scope, from: from, to: to);
      if (mounted && request == _request) {
        setState(() {
          _list = list;
          _busy = false;
        });
      }
    } on Object catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = e is FieldSalesFailure
              ? e.message
              : 'The rep list could not be loaded.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Field sales reps',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Refresh reps',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Close reps',
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
              if (list != null)
                Text(
                  'Order requests submitted ${list.from} to ${list.to}, by current state. '
                  'Names come from HR employee links.',
                ),
              if (list != null && list.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('No reps work in this company and branch.'),
                ),
              if (list != null)
                for (final rep in list.items)
                  Card(
                    child: ListTile(
                      title: Text(rep.label),
                      subtitle: Text(
                        '${rep.linked ? 'Linked to an HR employee' : 'Not linked to an HR employee'}'
                        ' · ${rep.activeCustomerCount} current customers\n'
                        'Submitted ${rep.submittedCount} · Awaiting ${rep.pendingCount}'
                        ' · Approved ${rep.approvedCount} · Rejected ${rep.rejectedCount}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        'Approved ${list.currencyCode} ${rep.approvedTotal}',
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
