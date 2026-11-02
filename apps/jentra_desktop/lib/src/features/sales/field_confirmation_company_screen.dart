import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation_company.dart';

import '../../app_providers.dart';
import 'field_confirmation_company_controller.dart';

final fieldConfirmationCompanyGatewayProvider =
    Provider<FieldConfirmationCompanyGateway?>((ref) => null);
Future<void> openFieldCompanyConfirmations(
  BuildContext context,
  TenantContext scope,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => Dialog(
    child: SizedBox(
      width: 960,
      height: 800,
      child: FieldCompanyConfirmations(scope),
    ),
  ),
);

class FieldCompanyConfirmations extends ConsumerWidget {
  const FieldCompanyConfirmations(this.scope, {super.key});
  final TenantContext scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authenticatedActorProvider),
        revision = ref.watch(authSessionRevisionProvider),
        caps = ref.watch(businessCapabilitiesProvider);
    final gateway = ref.watch(fieldConfirmationCompanyGatewayProvider);
    if (ref.watch(activeTenantContextProvider) != scope ||
        !scope.hasOperationalScope ||
        actor.isLoading ||
        actor.hasError ||
        actor.value != scope.actorId ||
        revision.isLoading ||
        revision.hasError ||
        revision.value == null ||
        caps.isLoading ||
        caps.hasError ||
        caps.value?.contains('sales.field.confirmations.manage') != true ||
        gateway == null ||
        gateway.actorId != scope.actorId) {
      return const _AccessChanged();
    }
    return _ConfirmationBody(
      key: ValueKey((scope, scope.actorId, revision.value, gateway)),
      scope: scope,
      revision: revision.value!,
      caps: caps.value!,
      gateway: gateway,
    );
  }
}

class _AccessChanged extends StatelessWidget {
  const _AccessChanged();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Current company confirmation authority is required. Close this workspace and reopen it after signing in.',
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _ConfirmationBody extends StatefulWidget {
  const _ConfirmationBody({
    super.key,
    required this.scope,
    required this.revision,
    required this.caps,
    required this.gateway,
  });
  final TenantContext scope;
  final int revision;
  final Set<String> caps;
  final FieldConfirmationCompanyGateway gateway;
  @override
  State<_ConfirmationBody> createState() => _ConfirmationBodyState();
}

class _ConfirmationBodyState extends State<_ConfirmationBody>
    with WidgetsBindingObserver {
  late final _CompanyConfirmationAuthority _authority;
  late final FieldConfirmationCompanyController c;
  Timer? _lease;
  FieldSalesJson? _editing, _chosen, _revoking;
  bool _showEditor = false, _dirty = false, _reviewed = false;
  final _revokeReason = TextEditingController();
  final _scroll = ScrollController();
  String? _lastMessage;
  @override
  void initState() {
    super.initState();
    final container = ProviderScope.containerOf(context, listen: false);
    _authority = _CompanyConfirmationAuthority(
      container,
      scope: widget.scope,
      revision: widget.revision,
      capabilities: widget.caps,
      gateway: widget.gateway,
    );
    c = FieldConfirmationCompanyController(
      actor: widget.scope.actorId,
      scope: FieldSalesScope(
        widget.scope.tenantId,
        widget.scope.legalEntityId!,
        widget.scope.branchId!,
      ),
      gateway: widget.gateway,
      store: FieldConfirmationCompanyStore(
        container.read(encryptedDraftRepositoryProvider),
      ),
      isAuthorized: () => _authority.current,
    );
    _authority.addListener(_observe);
    c.addListener(_observeMessage);
    WidgetsBinding.instance.addObserver(this);
    _lease = Timer(const Duration(minutes: 15), c.lock);
    c.open();
  }

  void _observe() {
    if (!_authority.current) c.lock();
  }

  void _observeMessage() {
    final message = c.error ?? c.notice;
    if (message != null && message != _lastMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !c.locked && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    _lastMessage = message;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) c.lock();
  }

  @override
  void dispose() {
    _lease?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _authority.removeListener(_observe);
    _authority.dispose();
    c.removeListener(_observeMessage);
    c.dispose();
    _scroll.dispose();
    _revokeReason.dispose();
    super.dispose();
  }

  Future<bool> _leaveEditor() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Discard contact changes?'),
            content: const Text('These contact edits have not been saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard changes'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _close() async {
    if (await _leaveEditor() && mounted) Navigator.pop(context);
  }

  void _resetEditor() {
    _showEditor = false;
    _editing = null;
    _chosen = null;
    _revoking = null;
    _dirty = false;
    _reviewed = false;
    _revokeReason.clear();
  }

  Future<void> _select(FieldSalesJson row) async {
    if (!await _leaveEditor() || !mounted || !_authority.current) return;
    setState(_resetEditor);
    await c.select(row);
  }

  Future<void> _save(FieldSalesJson payload) async {
    await c.authorizeContact(
      payload,
      expectedVersion: _editing?['version'] as String?,
    );
    if (mounted && !c.locked && (c.pending != null || c.error == null)) {
      setState(_resetEditor);
    }
  }

  Future<void> _issue() async {
    if (!_reviewed || _chosen == null) return;
    final contact = _chosen!;
    setState(() => _reviewed = false);
    await c.issue(contact);
    if (mounted && !c.locked && c.error == null) setState(_resetEditor);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      if (c.locked) {
        _resetEditor();
        return const _AccessChanged();
      }
      return PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _close();
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Customer email requests',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  OutlinedButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            if (await _leaveEditor() &&
                                mounted &&
                                _authority.current) {
                              setState(_resetEditor);
                              await c.open();
                            }
                          },
                    child: const Text('Refresh'),
                  ),
                  TextButton(onPressed: _close, child: const Text('Close')),
                ],
              ),
            ),
            if (c.busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                children: [
                  if (c.error != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        c.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (c.notice != null)
                    Semantics(liveRegion: true, child: Text(c.notice!)),
                  const Text(
                    'Authorize a company contact and request a response to the exact approved order. A queued request is not evidence of email delivery or customer acceptance.',
                  ),
                  const SizedBox(height: 12),
                  if (c.providerState != 'configured')
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Email service unavailable. Contacts can be governed here; response requests remain disabled. Ask the company owner to complete the reviewed sender rollout.',
                        ),
                      ),
                    ),
                  if (c.pending != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Original company action pending: ${c.pending!.action.replaceAll('_', ' ')}',
                            ),
                            const Text(
                              'Check its receipt before preparing another action. Reopening this workspace never resends it.',
                            ),
                            if (c.pending!.expired)
                              const Text(
                                'The private body expired; only receipt checking is available.',
                              ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: c.busy ? null : () => c.recover(),
                                  child: const Text('Check original receipt'),
                                ),
                                if (!c.pending!.expired)
                                  FilledButton(
                                    onPressed: c.busy
                                        ? null
                                        : () => c.recover(retry: true),
                                    child: const Text('Retry original action'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (c.selected == null) ...[
                    Text(
                      'Approved requests',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (c.subjects.isEmpty && !c.busy)
                      const Text(
                        'No approved field orders are available in this company and branch.',
                      ),
                    for (final row in c.subjects)
                      Card(
                        child: ListTile(
                          isThreeLine: true,
                          title: Text('${row['customer_name']}'),
                          subtitle: Text(
                            'Request ${row['id']} · revision ${row['version']}\n${row['preview']['currency_code']} ${row['preview']['pricing']['grand_total']} · Customer: ${row['customer_state']}',
                          ),
                          onTap: c.busy ? null : () => _select(row),
                        ),
                      ),
                    if (c.subjectCursor != null)
                      OutlinedButton(
                        onPressed: c.busy ? null : c.moreSubjects,
                        child: const Text('More approved requests'),
                      ),
                  ] else
                    ..._detail(),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  List<Widget> _detail() {
    final row = c.selected!;
    return [
      Text(
        '${row['customer_name']} · approved revision ${row['version']}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        'Company: ${row['company_state']} · Customer: ${row['customer_state']} · Delivery: ${row['delivery_state']}',
      ),
      Text('Request: ${row['id']}'),
      const SizedBox(height: 12),
      Text(
        'Approved terms: ${row['preview']['currency_code']} ${row['preview']['pricing']['grand_total']}',
      ),
      ..._commercialTerms(row['preview'] as Map),
      if (row['customer_state'] == 'accepted')
        const Text(
          'These terms already have current customer acceptance. Review an explicit revocation before requesting another response.',
        ),
      const Text(
        'A new response request replaces any outstanding request for these terms. Delivery acknowledgement remains separate.',
      ),
      const SizedBox(height: 16),
      Text(
        'Authorized contacts',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const Text(
        'Company authorization records the contact’s scope and authority. The recipient must separately verify email access and explicitly respond.',
      ),
      if (c.contacts.isEmpty && !c.busy)
        const Text('No current company-authorized contact is available.'),
      for (final contact in c.contacts)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${contact['name']} · ${contact['email']}'),
                Text('Authority: ${contact['authority_note']}'),
                Text(
                  'Valid until ${contact['valid_until']} · revision ${contact['version']}',
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: !c.canWrite
                          ? null
                          : () async {
                              if (await _leaveEditor() &&
                                  mounted &&
                                  _authority.current) {
                                setState(() {
                                  _resetEditor();
                                  _chosen = contact;
                                });
                              }
                            },
                      child: Text(
                        _chosen?['id'] == contact['id']
                            ? 'Contact selected'
                            : 'Use this contact',
                      ),
                    ),
                    TextButton(
                      onPressed: !c.canWrite
                          ? null
                          : () async {
                              if (await _leaveEditor() &&
                                  mounted &&
                                  _authority.current) {
                                setState(() {
                                  _resetEditor();
                                  _editing = contact;
                                  _showEditor = true;
                                });
                              }
                            },
                      child: const Text('Edit contact'),
                    ),
                    TextButton(
                      onPressed: !c.canWrite
                          ? null
                          : () async {
                              if (await _leaveEditor() &&
                                  mounted &&
                                  _authority.current) {
                                setState(() {
                                  _resetEditor();
                                  _revoking = {'kind': 'contact', ...contact};
                                });
                              }
                            },
                      child: const Text('Revoke contact'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (c.contactCursor != null)
        OutlinedButton(
          onPressed: c.busy ? null : c.moreContacts,
          child: const Text('More contacts'),
        ),
      if (!_showEditor)
        OutlinedButton(
          onPressed: !c.canWrite
              ? null
              : () async {
                  if (await _leaveEditor() && mounted && _authority.current) {
                    setState(() {
                      _resetEditor();
                      _showEditor = true;
                    });
                  }
                },
          child: const Text('Authorize a new contact'),
        ),
      if (_showEditor && c.pending == null)
        _CompanyContactForm(
          key: ValueKey((_editing?['id'], _editing?['version'])),
          initial: _editing,
          enabled: c.canWrite,
          onDirty: () {
            if (!_dirty) setState(() => _dirty = true);
          },
          onSave: _save,
          onCancel: () async {
            if (await _leaveEditor() && mounted) setState(_resetEditor);
          },
        ),
      if (_chosen != null && c.pending == null) ...[
        const SizedBox(height: 16),
        Text(
          'Request response from ${_chosen!['name']} · ${_chosen!['email']}',
        ),
        CheckboxListTile(
          value: _reviewed,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I reviewed these approved terms and this authorized contact revision.',
          ),
          onChanged: !c.canIssue
              ? null
              : (value) => setState(() => _reviewed = value ?? false),
        ),
        FilledButton(
          onPressed: !c.canIssue || !_reviewed ? null : _issue,
          child: const Text('Queue verified email request'),
        ),
      ],
      if (_revoking != null && c.pending == null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _revoking!['kind'] == 'contact'
                      ? 'Revoke this authorized contact?'
                      : 'Revoke this response request?',
                ),
                const Text(
                  'This invalidates outstanding recipient access. Historical response evidence is retained.',
                ),
                if (_revoking!['kind'] != 'contact')
                  TextField(
                    controller: _revokeReason,
                    enabled: c.canWrite,
                    maxLength: 500,
                    onChanged: (_) {
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Revocation reason',
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: c.busy ? null : () => setState(_resetEditor),
                      child: const Text('Keep current authority'),
                    ),
                    FilledButton(
                      onPressed: !c.canWrite
                          ? null
                          : () async {
                              final item = _revoking!;
                              if (item['kind'] == 'contact') {
                                await c.revokeContact(item);
                              } else {
                                await c.revokeChallenge(
                                  item,
                                  _revokeReason.text,
                                );
                              }
                              if (mounted &&
                                  !c.locked &&
                                  (c.pending != null || c.error == null)) {
                                setState(_resetEditor);
                              }
                            },
                      child: const Text('Confirm revocation'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 24),
      Text(
        'Response request history',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (c.challenges.isEmpty && !c.busy)
        const Text('No response requests have been recorded.'),
      for (final ch in c.challenges)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${ch['recipient_name']} · ${ch['effective_state']}'),
                Text('Challenge ${ch['id']} · revision ${ch['version']}'),
                Text('Link expires: ${ch['expires_at']}'),
                Text(
                  'Commercial response valid until: ${ch['acceptance_valid_until']}',
                ),
                if (ch['state'] != 'revoked')
                  TextButton(
                    onPressed: !c.canWrite
                        ? null
                        : () async {
                            if (await _leaveEditor() &&
                                mounted &&
                                _authority.current) {
                              setState(() {
                                _resetEditor();
                                _revoking = {'kind': 'challenge', ...ch};
                              });
                            }
                          },
                    child: const Text('Revoke response request'),
                  ),
              ],
            ),
          ),
        ),
      if (c.challengeCursor != null)
        OutlinedButton(
          onPressed: c.busy ? null : c.moreChallenges,
          child: const Text('More response requests'),
        ),
    ];
  }

  List<Widget> _commercialTerms(Map preview) {
    final terms = preview['terms'] as Map,
        currency = preview['currency_code'],
        pricing = preview['pricing'] as Map;
    List<String> address(Object? value, [String label = '']) {
      if (value is Map) {
        return [
          for (final entry in value.entries)
            ...address(
              entry.value,
              [
                label,
                '${entry.key}'.replaceAll('_', ' '),
              ].where((s) => s.isNotEmpty).join(' · '),
            ),
        ];
      }
      if (value is List) {
        return [
          for (var i = 0; i < value.length; i++)
            ...address(value[i], '$label ${i + 1}'),
        ];
      }
      return ['$label: ${value ?? '—'}'];
    }

    return [
      Text('Ship to: ${address(terms['ship_to']).join('\n')}'),
      Text('Requested delivery: ${terms['requested_date']}'),
      Text('Payment terms: ${terms['payment_terms_days']} days'),
      Text('Delivery terms: ${terms['delivery_terms']}'),
      for (final line in pricing['lines'] as List)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${line['description']}'),
                Text('${line['quantity']} × $currency ${line['unit_price']}'),
                Text(
                  'Line discount: $currency ${line['line_discount_amount']} · Order discount allocation: $currency ${line['header_discount_amount']}',
                ),
                Text(
                  'Tax: $currency ${line['tax_amount']} · ${line['tax_rate']}% ${line['tax_inclusive'] == true ? 'included' : 'added'}',
                ),
                Text('Line total: $currency ${line['line_total']}'),
              ],
            ),
          ),
        ),
      Text('Subtotal: $currency ${pricing['subtotal']}'),
      Text('Discount: $currency ${pricing['discount_total']}'),
      Text('Tax: $currency ${pricing['tax_total']}'),
      Text('Total: $currency ${pricing['grand_total']}'),
    ];
  }
}

class _CompanyContactForm extends StatefulWidget {
  const _CompanyContactForm({
    super.key,
    required this.initial,
    required this.enabled,
    required this.onDirty,
    required this.onSave,
    required this.onCancel,
  });
  final FieldSalesJson? initial;
  final bool enabled;
  final VoidCallback onDirty;
  final Future<void> Function(FieldSalesJson) onSave;
  final Future<void> Function() onCancel;
  @override
  State<_CompanyContactForm> createState() => _CompanyContactFormState();
}

class _CompanyContactFormState extends State<_CompanyContactForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _email, _note, _until;
  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _name = TextEditingController(text: c?['name'] as String?);
    _email = TextEditingController(text: c?['email'] as String?);
    _note = TextEditingController(text: c?['authority_note'] as String?);
    _until = TextEditingController(
      text: c?['valid_until'] == null
          ? ''
          : DateTime.parse(c!['valid_until'] as String)
                .toUtc()
                .toIso8601String()
                .substring(0, 10),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _note.dispose();
    _until.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _form,
        onChanged: widget.onDirty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.initial == null
                  ? 'Authorize a contact'
                  : 'Update contact authority',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextFormField(
              controller: _name,
              enabled: widget.enabled,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Contact name'),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Add the authorized contact’s name.'
                  : null,
            ),
            TextFormField(
              controller: _email,
              enabled: widget.enabled,
              maxLength: 254,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Authorized email address',
              ),
              validator: (v) =>
                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch((v ?? '').trim())
                  ? 'Add a valid email address.'
                  : null,
            ),
            TextFormField(
              controller: _note,
              enabled: widget.enabled,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Company authority note',
              ),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Record why this contact is authorized.'
                  : null,
            ),
            TextFormField(
              controller: _until,
              enabled: widget.enabled,
              decoration: const InputDecoration(
                labelText: 'Authority valid through (YYYY-MM-DD, UTC)',
              ),
              validator: (v) {
                final d = DateTime.tryParse('${(v ?? '').trim()}T23:59:59Z');
                return !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                            .hasMatch((v ?? '').trim()) ||
                        d == null ||
                        d.toIso8601String().substring(0, 10) !=
                            (v ?? '').trim() ||
                        !d.isAfter(DateTime.now().toUtc()) ||
                        d.difference(DateTime.now().toUtc()) >
                            const Duration(days: 366)
                    ? 'Choose a future date within one year.'
                    : null;
              },
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: widget.enabled ? widget.onCancel : null,
                  child: const Text('Cancel contact edits'),
                ),
                FilledButton(
                  onPressed: !widget.enabled
                      ? null
                      : () async {
                          if (_form.currentState!.validate()) {
                            await widget.onSave({
                              if (widget.initial != null)
                                'id': widget.initial!['id'],
                              'name': _name.text.trim(),
                              'email': _email.text.trim(),
                              'authority_note': _note.text.trim(),
                              'valid_until': '${_until.text.trim()}T23:59:59Z',
                            });
                          }
                        },
                  child: const Text('Save authorized contact'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

final class _CompanyConfirmationAuthority extends ChangeNotifier {
  _CompanyConfirmationAuthority(
    this.container, {
    required this.scope,
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
          .listen(fieldConfirmationCompanyGatewayProvider, (_, _) => _observe())
          .close,
    ]);
  }
  final ProviderContainer container;
  final TenantContext scope;
  final int revision;
  final Set<String> capabilities;
  final FieldConfirmationCompanyGateway gateway;
  final _close = <VoidCallback>[];
  bool _active = false, _disposed = false;
  bool _matches() {
    final actor = container.read(authenticatedActorProvider),
        session = container.read(authSessionRevisionProvider),
        caps = container.read(businessCapabilitiesProvider);
    return container.read(activeTenantContextProvider) == scope &&
        scope.hasOperationalScope &&
        !actor.isLoading &&
        !actor.hasError &&
        actor.value == scope.actorId &&
        !session.isLoading &&
        !session.hasError &&
        session.value == revision &&
        !caps.isLoading &&
        !caps.hasError &&
        caps.value != null &&
        caps.value!.length == capabilities.length &&
        caps.value!.containsAll(capabilities) &&
        caps.value!.contains('sales.field.confirmations.manage') &&
        identical(
          container.read(fieldConfirmationCompanyGatewayProvider),
          gateway,
        ) &&
        gateway.actorId == scope.actorId;
  }

  bool get current => !_disposed && _active && _matches();
  void _observe() {
    if (_disposed || !_active || _matches()) return;
    _active = false;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
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
