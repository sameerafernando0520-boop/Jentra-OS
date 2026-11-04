import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

import '../../app_providers.dart';

final fieldSalesCompanyGatewayProvider = Provider<FieldSalesCompanyGateway?>(
  (ref) => null,
);
Future<void> openFieldCompanyReview(
  BuildContext context,
  TenantContext scope,
) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    child: SizedBox(width: 900, height: 720, child: FieldCompanyReview(scope)),
  ),
);

class FieldCompanyReview extends ConsumerWidget {
  const FieldCompanyReview(this.scope, {super.key});
  final TenantContext scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actorState = ref.watch(authenticatedActorProvider);
    final actor = actorState.value;
    final revision = ref.watch(authSessionRevisionProvider);
    final current = ref.watch(activeTenantContextProvider);
    final caps = ref.watch(businessCapabilitiesProvider);
    final gateway = ref.watch(fieldSalesCompanyGatewayProvider);
    if (current != scope ||
        actorState.isLoading ||
        actorState.hasError ||
        actor == null ||
        actor != scope.actorId ||
        !scope.hasOperationalScope ||
        revision.isLoading ||
        revision.hasError ||
        revision.value == null ||
        gateway == null ||
        gateway.actorId != actor ||
        caps.isLoading ||
        caps.hasError ||
        caps.value == null ||
        !caps.value!.contains('sales.field.discounts.decide') ||
        !caps.value!.contains('sales.orders.manage')) {
      return const Center(
        child: Text(
          'Current company authority is required to review field orders.',
        ),
      );
    }
    return _CompanyReviewBody(
      key: ValueKey((actor, revision.value, scope)),
      actor: actor,
      contextScope: scope,
      sessionRevision: revision.value!,
      capabilities: Set.unmodifiable(caps.value!),
      scope: FieldSalesScope(
        scope.tenantId,
        scope.legalEntityId!,
        scope.branchId!,
      ),
      gateway: gateway,
      store: FieldSalesDecisionStore(
        ref.watch(encryptedDraftRepositoryProvider),
      ),
    );
  }
}

class _CompanyReviewBody extends StatefulWidget {
  const _CompanyReviewBody({
    required this.actor,
    required this.contextScope,
    required this.sessionRevision,
    required this.capabilities,
    required this.scope,
    required this.gateway,
    required this.store,
    super.key,
  });
  final String actor;
  final TenantContext contextScope;
  final int sessionRevision;
  final Set<String> capabilities;
  final FieldSalesScope scope;
  final FieldSalesCompanyGateway gateway;
  final FieldSalesDecisionStore store;
  @override
  State<_CompanyReviewBody> createState() => _CompanyReviewBodyState();
}

class _CompanyReviewBodyState extends State<_CompanyReviewBody> {
  List<FieldSalesJson> _items = [];
  FieldSalesDecision? _pending;
  bool _busy = true;
  String? _error;
  late final _CompanyReviewAuthority _authority;
  bool get _current => mounted && _authority.current;
  @override
  void initState() {
    super.initState();
    _authority = _CompanyReviewAuthority(
      ProviderScope.containerOf(context, listen: false),
      scope: widget.contextScope,
      actor: widget.actor,
      revision: widget.sessionRevision,
      capabilities: widget.capabilities,
      gateway: widget.gateway,
    );
    _authority.addListener(_clearRevokedContent);
    _load();
  }

  void _clearRevokedContent() {
    if (!_authority.current) {
      _items = [];
      _pending = null;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _authority.removeListener(_clearRevokedContent);
    _authority.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_current) {
      return;
    }
    if (mounted) {
      setState(() {
        _busy = true;
        _items = [];
        _error = null;
      });
    }
    try {
      final rows = await widget.gateway.subjects(widget.scope);
      final pending = await widget.store.load(widget.actor, widget.scope);
      if (!_current) {
        return;
      }
      setState(() {
        _items = rows;
        _pending = pending;
        _busy = false;
      });
    } on Object catch (e) {
      if (_current) {
        setState(() {
          _error = e is FieldSalesFailure
              ? e.message
              : 'Company review could not be loaded.';
          _busy = false;
        });
      }
    }
  }

  Future<void> _decide(FieldSalesJson row, String decision) async {
    if (!_current) {
      return;
    }
    final reviewed = fieldSalesObject(jsonDecode(jsonEncode(row)));
    final note = await showDialog<String>(
      context: context,
      builder: (_) => FieldCompanyDecisionDialog(
        scope: widget.contextScope,
        actor: widget.actor,
        sessionRevision: widget.sessionRevision,
        capabilities: widget.capabilities,
        gateway: widget.gateway,
        row: reviewed,
        decision: decision,
      ),
    );
    if (note == null || !_current) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final command = await widget.store.prepare(
        widget.actor,
        widget.scope,
        reviewed,
        decision,
        note,
      );
      if (!_current) {
        return;
      }
      _pending = command;
      await _send(command);
    } on Object catch (e) {
      if (_current) {
        setState(() {
          _error = e is FieldSalesFailure
              ? e.message
              : 'The outcome is unknown. Check the original company decision.';
          _busy = false;
        });
      }
    }
  }

  Future<void> _send(FieldSalesDecision command) async {
    FieldSalesJson result;
    try {
      result = await widget.gateway.decide(command.params);
    } on FieldSalesFailure catch (e) {
      if (['40001', '55000'].contains(e.code) && _current) {
        await widget.store.complete(command);
        _pending = null;
        await _load();
      }
      rethrow;
    }
    command.validate(result);
    if (!_current) {
      return;
    }
    await widget.store.complete(command);
    if (!_current) {
      return;
    }
    _pending = null;
    await _load();
  }

  Future<void> _check({bool retry = false}) async {
    final command = _pending;
    if (command == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.store.load(widget.actor, widget.scope);
      if (!_current) {
        return;
      }
      if (saved == null || saved.commandId != command.commandId) {
        throw const FieldSalesFailure(
          'RECOVERY_CHANGED',
          'The original company decision changed. Refresh your review.',
        );
      }
      _pending = saved;
      final result = await widget.gateway.receipt(widget.scope, command.key);
      if (!_current) {
        return;
      }
      if (result['state'] == 'committed') {
        command.validate(fieldSalesObject(result['receipt']));
        await widget.store.complete(command);
        _pending = null;
        await _load();
      } else if (result['state'] == 'not_found' && retry && !saved.expired) {
        await _send(saved);
      } else {
        setState(() {
          _error = command.expired
              ? 'The decision body expired. Keep its reference for company reconciliation.'
              : 'No receipt is visible. This does not prove the decision failed.';
          _busy = false;
        });
      }
    } on Object catch (e) {
      if (_current) {
        setState(() {
          _error = e is FieldSalesFailure
              ? e.message
              : 'The original decision could not be checked.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _authority,
    builder: (context, _) => !_authority.current
        ? const Center(
            child: Text(
              'Current company authority changed. Close this review and reopen it.',
            ),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Field order company review',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh company requests',
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Close company review',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
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
                    if (_pending != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Original company decision has an unconfirmed outcome.',
                              ),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  TextButton(
                                    onPressed: _busy ? null : () => _check(),
                                    child: const Text('Check decision receipt'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _busy || _pending!.expired
                                        ? null
                                        : () => _check(retry: true),
                                    child: const Text(
                                      'Retry original company decision',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_busy && _items.isEmpty)
                      const Text(
                        'No field order requests are available in this company and branch.',
                      ),
                    for (final row in _items)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Request ${row['id']} · revision ${row['version']}',
                              ),
                              Text(
                                'Company: ${row['company_state']} · Customer: ${row['customer_state'] ?? 'email_link_pending'}',
                              ),
                              Text(
                                'Requested discount: ${row['input']['discount_percent']}%',
                              ),
                              Text(
                                'Representative reason: ${row['input']['discount_reason']}',
                              ),
                              Text(
                                'Requested total: ${row['preview']['currency_code']} ${row['preview']['pricing']['grand_total']}',
                              ),
                              Text(
                                'Delivery requested: ${row['input']['requested_date']}',
                              ),
                              for (final line
                                  in row['preview']['pricing']['lines'] as List)
                                Text(
                                  '${line['description']} · ${line['quantity']} × ${line['unit_price']}',
                                ),
                              if (row['decision_reason'] != null)
                                Text(
                                  'Company reason: ${row['decision_reason']}',
                                ),
                              if (row['company_state'] == 'submitted')
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    FilledButton(
                                      onPressed: _busy || _pending != null
                                          ? null
                                          : () => _decide(row, 'approve'),
                                      child: const Text(
                                        'Approve company terms',
                                      ),
                                    ),
                                    OutlinedButton(
                                      onPressed: _busy || _pending != null
                                          ? null
                                          : () => _decide(row, 'reject'),
                                      child: const Text('Reject request'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
  );
}

/// A nested navigator route keeps its own authority observer. Losing and then
/// restoring authority never revives a previous company's confirmation form.
class FieldCompanyDecisionDialog extends StatefulWidget {
  const FieldCompanyDecisionDialog({
    required this.scope,
    required this.actor,
    required this.sessionRevision,
    required this.capabilities,
    required this.gateway,
    required this.row,
    required this.decision,
    super.key,
  });
  final TenantContext scope;
  final String actor;
  final int sessionRevision;
  final Set<String> capabilities;
  final FieldSalesCompanyGateway gateway;
  final FieldSalesJson row;
  final String decision;

  @override
  State<FieldCompanyDecisionDialog> createState() =>
      _FieldCompanyDecisionDialogState();
}

class _FieldCompanyDecisionDialogState
    extends State<FieldCompanyDecisionDialog> {
  late final _CompanyReviewAuthority _authority;

  @override
  void initState() {
    super.initState();
    _authority = _CompanyReviewAuthority(
      ProviderScope.containerOf(context, listen: false),
      scope: widget.scope,
      actor: widget.actor,
      revision: widget.sessionRevision,
      capabilities: widget.capabilities,
      gateway: widget.gateway,
    );
  }

  @override
  void dispose() {
    _authority.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _authority,
    builder: (context, _) => _authority.current
        ? _CompanyDecisionForm(
            row: widget.row,
            decision: widget.decision,
            isCurrent: () => _authority.current,
          )
        : AlertDialog(
            title: const Text('Company access changed'),
            content: const Text(
              'Close this dialog and review the request again in your current company and session.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
  );
}

class _CompanyDecisionForm extends StatefulWidget {
  const _CompanyDecisionForm({
    required this.row,
    required this.decision,
    required this.isCurrent,
  });
  final FieldSalesJson row;
  final String decision;
  final bool Function() isCurrent;

  @override
  State<_CompanyDecisionForm> createState() => _CompanyDecisionFormState();
}

class _CompanyDecisionFormState extends State<_CompanyDecisionForm> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.decision == 'approve'
          ? 'Approve requested company terms?'
          : 'Reject this request?',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Requested discount: ${widget.row['input']['discount_percent']}%',
            ),
            Text(
              'Requested total: ${widget.row['preview']['currency_code']} ${widget.row['preview']['pricing']['grand_total']}',
            ),
            const Text(
              'Approval creates a canonical draft after current price and credit checks. Verified customer acceptance is still pending.',
            ),
            TextFormField(
              controller: _reason,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Company decision reason',
              ),
              validator: (value) {
                final reason = (value ?? '').trim();
                return reason.isEmpty || reason.length > 500
                    ? 'Add a company decision reason of up to 500 characters.'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep reviewing'),
      ),
      FilledButton(
        onPressed: () {
          if (widget.isCurrent() && _form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('Confirm company decision'),
      ),
    ],
  );
}

final class _CompanyReviewAuthority extends ChangeNotifier {
  _CompanyReviewAuthority(
    this.container, {
    required this.scope,
    required this.actor,
    required this.revision,
    required Set<String> capabilities,
    required this.gateway,
  }) : capabilities = Set.unmodifiable(capabilities) {
    _active = _matches();
    _close.addAll([
      container.listen(activeTenantContextProvider, (_, _) => _observe()).close,
      container.listen(authenticatedActorProvider, (_, _) => _observe()).close,
      container.listen(authSessionRevisionProvider, (_, _) => _observe()).close,
      container
          .listen(businessCapabilitiesProvider, (_, _) => _observe())
          .close,
      container
          .listen(fieldSalesCompanyGatewayProvider, (_, _) => _observe())
          .close,
    ]);
  }
  final ProviderContainer container;
  final TenantContext scope;
  final String actor;
  final int revision;
  final Set<String> capabilities;
  final FieldSalesCompanyGateway gateway;
  final _close = <VoidCallback>[];
  bool _active = false, _disposed = false;

  bool _matches() {
    final currentActor = container.read(authenticatedActorProvider);
    final currentRevision = container.read(authSessionRevisionProvider);
    final currentCaps = container.read(businessCapabilitiesProvider);
    return container.read(activeTenantContextProvider) == scope &&
        scope.actorId == actor &&
        !currentActor.isLoading &&
        !currentActor.hasError &&
        currentActor.value == actor &&
        !currentRevision.isLoading &&
        !currentRevision.hasError &&
        currentRevision.value == revision &&
        !currentCaps.isLoading &&
        !currentCaps.hasError &&
        currentCaps.value != null &&
        currentCaps.value!.length == capabilities.length &&
        currentCaps.value!.containsAll(capabilities) &&
        currentCaps.value!.containsAll({
          'sales.field.discounts.decide',
          'sales.orders.manage',
        }) &&
        identical(container.read(fieldSalesCompanyGatewayProvider), gateway) &&
        gateway.actorId == actor;
  }

  bool get current => !_disposed && _active && _matches();

  void _observe() {
    if (_disposed || !_active || _matches()) {
      return;
    }
    _active = false;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          notifyListeners();
        }
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final close in _close) {
      close();
    }
    super.dispose();
  }
}
