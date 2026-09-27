import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../app_providers.dart';
import 'private_hr_controller.dart';
import 'organization_screen.dart' show organizationPicker, OrganizationChoice;

String hrViewLabel(PrivateHrView view) => switch (view) {
  PrivateHrView.contacts => 'Private contacts',
  PrivateHrView.documents => 'Private documents',
  PrivateHrView.reviews => 'Performance reviews',
  PrivateHrView.links => 'Account links',
  PrivateHrView.retention => 'Retention & holds',
  PrivateHrView.myAccount => 'My account & reviews',
};
String hrActionLabel(String action) => switch (action) {
  'profile_save' => 'Save private contacts',
  'document_reserve' => 'Reserve private document',
  'document_complete' => 'Upload reserved document',
  'review_create' => 'Create review',
  'review_revise' => 'Revise review',
  'review_submit' => 'Submit review',
  'review_decide' => 'Record independent decision',
  'review_acknowledge' => 'Acknowledge receipt',
  'review_close' => 'Close review',
  'link_initiate' => 'Propose exact account link',
  'link_accept' => 'Accept account link',
  'link_reject' => 'Reject account link',
  'link_revoke' => 'Revoke account link',
  'policy_create' => 'Create synthetic policy',
  'cycle_close' => 'Close synthetic test cycle',
  'hold' => 'Place legal hold',
  'release_hold' => 'Release legal hold',
  'erase_request' => 'Request private erasure',
  'export_prepare' => 'Prepare private export',
  _ => 'Private HR action',
};
const hrContactLabels = {
  'personal_email': 'Personal email',
  'personal_phone': 'Personal phone',
  'postal_address': 'Postal address',
  'emergency_name': 'Emergency contact name',
  'emergency_relationship': 'Emergency relationship',
  'emergency_phone': 'Emergency phone',
};

class PrivateHrScreen extends ConsumerWidget {
  const PrivateHrScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry private HR access'),
        ),
      );
    }
    final c = ref.watch(privateHrControllerProvider);
    if (c == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Choose a signed-in entity and branch with People access.',
          ),
        ),
      );
    }
    return PrivateHrWorkspace(key: ValueKey(c), controller: c);
  }
}

class PrivateHrWorkspace extends StatefulWidget {
  const PrivateHrWorkspace({required this.controller, super.key});
  final PrivateHrController controller;
  @override
  State<PrivateHrWorkspace> createState() => _PrivateHrWorkspaceState();
}

class _PrivateHrWorkspaceState extends State<PrivateHrWorkspace> {
  final search = TextEditingController();
  PrivateHrController get c => widget.controller;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Widget _card(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  Widget _button(String text, Future<void> Function() action) => OutlinedButton(
    onPressed: c.busy || !c.online ? null : action,
    child: Text(text),
  );
  Future<HrRecord?> _reviewer() async {
    final choices = <HrRecord>[];
    final result = await organizationPicker(context, 'Independent reviewer', (
      query,
      after,
    ) async {
      final rows = await c.choices(query, after: after);
      choices.addAll(rows);
      return (
        [
          for (final row in rows)
            OrganizationChoice(
              row.id,
              '${row.text('display_name')!} · ${row.text('code')!}',
            ),
        ],
        rows.length == 50 ? rows.last.id : null,
      );
    }, () => c.current && c.online);
    return result == null
        ? null
        : choices.where((row) => row.id == result.id).firstOrNull;
  }

  Future<void> _createReview() async {
    final reviewer = await _reviewer();
    if (reviewer == null || !c.current) return;
    if (reviewer.id == c.subject?.id) {
      await c.begin('review_create', reviewer: reviewer);
      return;
    }
    await c.begin('review_create', reviewer: reviewer);
  }

  Future<void> _link() async {
    final choices = <HrRecord>[];
    final picked = await organizationPicker(context, 'Exact existing account', (
      query,
      after,
    ) async {
      final page = await c.memberships(after: after);
      choices.addAll(page.items);
      final filtered = page.items.where(
        (r) =>
            query.isEmpty ||
            r.id.contains(query) ||
            r.text('user_id')!.contains(query),
      );
      return (
        [
          for (final r in filtered)
            OrganizationChoice(
              r.id,
              'Membership ${r.id}\nUser ${r.text('user_id')!}',
            ),
        ],
        page.nextCursor,
      );
    }, () => c.current && c.online);
    final member = picked == null
        ? null
        : choices.where((r) => r.id == picked.id).firstOrNull;
    if (member != null && c.current) {
      await c.begin('link_initiate', membership: member);
    }
  }

  Widget _body(Map<String, Object?> body, {bool contacts = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (contacts)
        for (final f in hrContactFields)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${hrContactLabels[f]!}: ${body[f] as String? ?? 'Not recorded'}',
            ),
          ),
      if (!contacts) ...[
        for (final text in body['objectives'] as List? ?? [])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('• $text'),
          ),
        if (body['comments'] != null) Text(body['comments'] as String),
      ],
    ],
  );
  Widget _review(HrRecord row, {bool own = false}) {
    final canManage = !own && c.has('people.reviews.manage');
    return _card('Review · ${row.text('status')!}', [
      Text(
        '${row.text('start_date')!} to ${row.text('end_date_exclusive')!} (exclusive)',
      ),
      Text('Revision ${row.text('revision_id')!}'),
      const SizedBox(height: 12),
      _body(row.body!),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (canManage)
            _button('Revise', () => c.begin('review_revise', record: row)),
          if (canManage &&
              row.text('status') == 'draft' &&
              row.text('recorded_by') == c.scope.actorId)
            _button('Submit', () => c.begin('review_submit', record: row)),
          if (canManage &&
              row.text('status') == 'submitted' &&
              row.text('recorded_by') != c.scope.actorId)
            _button(
              'Record decision',
              () => c.begin('review_decide', record: row),
            ),
          if (own && row.text('status') == 'reviewed')
            _button(
              'Acknowledge receipt',
              () => c.begin('review_acknowledge', record: row),
            ),
          if (canManage &&
              row.text('status') == 'acknowledged' &&
              row.text('recorded_by') != c.scope.actorId)
            _button('Close review', () => c.begin('review_close', record: row)),
          if (!own && c.has('people.reviews.view'))
            _button('Revision history', () => c.openReview(row)),
          if (!own && c.has('people.hr.export') && c.has('people.reviews.view'))
            _button('Prepare export', () => c.prepareExport(review: row)),
        ],
      ),
      if (own)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'Acknowledgement records receipt. It does not mean agreement or change pay.',
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.current) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              c.error ?? 'Private HR access changed. Reload current access.',
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Private HR',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              _button('Reload', c.refresh),
              if (!c.online)
                const Chip(
                  label: Text('Offline · connect to verify private access'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final view in c.views)
                ChoiceChip(
                  label: Text(hrViewLabel(view)),
                  selected: c.view == view,
                  onSelected: c.busy ? null : (_) => c.changeView(view),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.message!),
            ),
          if (c.preparedExportId != null)
            _card('Prepared private export', [
              const Text(
                'Save the frozen revision to a file you select. The exported copy is under your control; server erasure cannot recall it.',
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: _button('Save prepared export', c.writePreparedExport),
              ),
            ]),
          if (c.recovery.isNotEmpty)
            _card('Private recovery', [
              const Text(
                'Private text expires after 24 hours. Request identities remain until confirmation is resolved.',
              ),
              for (final item in c.recovery)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        item.expiresAt == null
                            ? 'Expired text · minimal receipt'
                            : 'Encrypted draft · expires ${item.expiresAt!.toIso8601String()}',
                      ),
                      _button('Restore recovery', () => c.resume(item)),
                    ],
                  ),
                ),
            ]),
          if (c.expiredRecovery != null)
            _card('Resolve expired request', [
              const Text(
                'The private body is erased. Check the actor-scoped receipt before replacing the request.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: _button('Check server confirmation', c.resolveExpired),
              ),
            ]),
          if (c.subjectCapability != null)
            _card('Choose employee', [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: search,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Name or employee code',
                      ),
                      onSubmitted: (text) => c.filter(text),
                    ),
                  ),
                  _button('Find employee', () => c.filter(search.text)),
                ],
              ),
              if (c.subjects.isEmpty && !c.busy)
                const Text('No employees match this authorized branch.'),
              for (final row in c.subjects)
                ListTile(
                  title: Text(row.text('display_name')!),
                  subtitle: Text(row.text('code')!),
                  selected: c.subject?.id == row.id,
                  onTap: c.busy ? null : () => c.openSubject(row),
                ),
              if (c.subjectCursor != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _button('More employees', c.moreSubjects),
                ),
            ]),
          if (c.subject != null)
            _card(
              '${c.subject!.text('display_name')!} · ${c.subject!.text('code')!}',
              [
                if (c.view == PrivateHrView.contacts) ...[
                  if (c.contactState?.profile == null)
                    const Text('No private contacts are recorded.'),
                  if (c.contactState?.profile != null)
                    _body(c.contactState!.profile!.body!, contacts: true),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (c.has('people.hr.private.manage'))
                        _button(
                          'Edit private contacts',
                          () => c.begin('profile_save'),
                        ),
                      if (c.contactState?.profile != null &&
                          c.has('people.hr.export'))
                        _button(
                          'Prepare contact export',
                          () => c.prepareExport(),
                        ),
                    ],
                  ),
                  for (final row in c.history)
                    ExpansionTile(
                      title: Text('Contact revision ${row.version}'),
                      subtitle: Text(row.text('recorded_at')!),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Reason: ${row.text('reason')!}'),
                              const SizedBox(height: 12),
                              _body(row.body!, contacts: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (c.historyCursor != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _button('More contact history', c.moreRows),
                    ),
                ],
                if (c.view == PrivateHrView.documents) ...[
                  const Text(
                    'Text, PNG, JPEG or PDF · up to 10 MiB. File bytes stay in memory during upload and preview.',
                  ),
                  if (c.canUpload)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _button(
                        'Choose new private document',
                        c.beginDocument,
                      ),
                    ),
                ],
                if (c.view == PrivateHrView.reviews &&
                    c.has('people.reviews.manage'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _button('Create performance review', _createReview),
                  ),
                if (c.view == PrivateHrView.links) ...[
                  const Text(
                    'Choose an exact active membership and user ID. The target must accept within 24 hours. The link grants no roles or permissions.',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _button('Propose account link', _link),
                  ),
                ],
                if (c.has('people.hr.erase'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _button(
                      'Request private erasure',
                      () => c.begin('erase_request'),
                    ),
                  ),
              ],
            ),
          if (c.view == PrivateHrView.documents && c.subject != null) ...[
            if (c.rows.isEmpty && !c.busy)
              _card('Private documents', [
                const Text('No private documents are recorded.'),
              ]),
            for (final row in c.rows)
              _card(row.text('purpose')!, [
                Text(
                  '${row.text('classification')!} · ${row.text('mime')!} · ${row.toJson()['byte_size'] as int} bytes',
                ),
                Text('Status: ${row.text('status')!}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (row.text('status') == 'active')
                      _button('Preview', () => c.preview(row)),
                    if (row.text('status') == 'active' &&
                        c.has('people.hr.export'))
                      _button('Export document', () => c.exportDocument(row)),
                    if (row.text('status') != 'active' && c.canUpload)
                      _button(
                        'Choose reserved file & upload',
                        () => c.chooseReservedFile(row),
                      ),
                  ],
                ),
              ]),
          ],
          if (c.view == PrivateHrView.reviews && c.subject != null) ...[
            if (c.rows.isEmpty && !c.busy)
              _card('Performance reviews', [
                const Text('No visible reviews are recorded.'),
              ]),
            for (final row in c.rows) _review(row),
            if (c.selectedReview != null)
              _card('Review revision history', [
                for (final row in c.history)
                  ExpansionTile(
                    title: Text(row.text('kind')!),
                    subtitle: Text(row.text('recorded_at')!),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (row.body != null) _body(row.body!),
                            if (row.text('private_text') != null)
                              Text(row.text('private_text')!),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (c.historyCursor != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _button(
                      'More review history',
                      () => c.openReview(c.selectedReview!, more: true),
                    ),
                  ),
              ]),
          ],
          if (c.view == PrivateHrView.links && c.subject != null) ...[
            if (c.rows.isEmpty && !c.busy)
              _card('Account links', [
                const Text('No proposals or account links are recorded.'),
              ]),
            for (final row in c.rows)
              _card('Account link · ${row.text('status')!}', [
                Text('Membership ${row.text('membership_id')!}'),
                Text('User ${row.text('user_id')!}'),
                Text('Expires ${row.text('expires_at')!}'),
                if ({'pending', 'accepted'}.contains(row.text('status')))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _button(
                      'Revoke link',
                      () => c.begin('link_revoke', record: row),
                    ),
                  ),
              ]),
          ],
          if (c.cursor != null &&
              c.subject != null &&
              c.view != PrivateHrView.contacts)
            Align(
              alignment: Alignment.centerLeft,
              child: _button('More records', c.moreRows),
            ),
          if (c.view == PrivateHrView.retention)
            _card('Synthetic retention policy', [
              const Text(
                'The approved development policy erases private content 30 days after explicit test-cycle closure. This is a synthetic cleanup choice.',
              ),
              const SizedBox(height: 12),
              if (c.policyState?.policy == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _button(
                    'Create synthetic policy',
                    () => c.begin('policy_create'),
                  ),
                ),
              if (c.policyState?.policy != null) ...[
                Text(c.policyState!.policy!.text('purpose')!),
                Text(
                  'Retention worker: ${c.policyState!.workerReady
                          ? 'verified within 26 hours'
                          : 'not ready; private content writes are blocked'}',
                ),
                Text(
                  'Cycle closed: ${c.policyState!.policy!.text('closed_at') ??
                          'Not closed'}',
                ),
                if (c.policyState!.policy!.text('hold_reason') != null) ...[
                  Text('Hold: ${c.policyState!.policy!.text('hold_reason')!}'),
                  Text(
                    'Review date: ${c.policyState!.policy!.text('hold_review_date')!}',
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (c.policyState!.policy!.text('closed_at') == null)
                      _button('Close test cycle', () => c.begin('cycle_close')),
                    _button(
                      c.policyState!.policy!.text('hold_reason') == null
                          ? 'Place hold'
                          : 'Release hold',
                      () => c.begin(
                        c.policyState!.policy!.text('hold_reason') == null
                            ? 'hold'
                            : 'release_hold',
                      ),
                    ),
                  ],
                ),
              ],
            ]),
          if (c.view == PrivateHrView.myAccount) ...[
            _card('My account proposals', [
              if (c.inbox.isEmpty && !c.busy)
                const Text('No active proposals for this signed-in account.'),
              for (final row in c.inbox)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.text('employee_name')!),
                      Text('Expires ${row.text('expires_at')!}'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _button(
                            'Accept link',
                            () => c.begin('link_accept', record: row),
                          ),
                          _button(
                            'Reject link',
                            () => c.begin('link_reject', record: row),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (c.cursor != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _button('More proposals', c.moreInbox),
                ),
            ]),
            if (!c.has('people.self.view'))
              _card('My reviews', [
                const Text(
                  'Self-service access is a separate permission. Accepting a link does not grant it.',
                ),
              ]),
            if (c.has('people.self.view') && c.selfIdentity == null)
              _card('My reviews', [
                const Text(
                  'An accepted account link is required for self service.',
                ),
              ]),
            if (c.selfIdentity != null) ...[
              _card(c.selfIdentity!.text('display_name')!, [
                if (c.rows.isEmpty)
                  const Text('No shared reviews are available.'),
              ]),
              for (final row in c.rows) _review(row, own: true),
            ],
          ],
          if (c.previewBytes != null && c.previewDocument != null)
            _card('Private document preview', [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: c.closePreview,
                  child: const Text('Close preview'),
                ),
              ),
              SizedBox(
                height: 480,
                child: PrivateHrPreview(
                  key: ObjectKey(c.previewBytes),
                  bytes: c.previewBytes!,
                  mime: c.previewDocument!.text('mime')!,
                ),
              ),
            ]),
          if (c.form != null)
            PrivateHrEditor(
              key: ValueKey(c.form!['id'].toString() + c.action!),
              controller: c,
            ),
        ],
      );
    },
  );
}

class PrivateHrEditor extends StatefulWidget {
  const PrivateHrEditor({required this.controller, super.key});
  final PrivateHrController controller;
  @override
  State<PrivateHrEditor> createState() => _PrivateHrEditorState();
}

class _PrivateHrEditorState extends State<PrivateHrEditor> {
  PrivateHrController get c => widget.controller;
  final fields = <String, TextEditingController>{};
  final objectives = <TextEditingController>[];
  @override
  void initState() {
    super.initState();
    final f = c.form!;
    for (final entry in f.entries) {
      if (entry.value is String) {
        fields[entry.key] = TextEditingController(text: entry.value as String);
      }
    }
    if (c.action == 'profile_save') {
      for (final key in hrContactFields) {
        fields[key] = TextEditingController(
          text: hrMap(f['body'])[key] as String? ?? '',
        );
      }
    }
    if ({'review_create', 'review_revise'}.contains(c.action)) {
      final body = hrMap(f['body']);
      fields['comments'] = TextEditingController(
        text: body['comments'] as String? ?? '',
      );
      for (final text in body['objectives'] as List) {
        objectives.add(TextEditingController(text: text as String));
      }
    }
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    for (final controller in objectives) {
      controller.dispose();
    }
    super.dispose();
  }

  void _reviewBody() => c.edit('body', {
    'objectives': [for (final controller in objectives) controller.text],
    'comments': fields['comments']!.text.isEmpty
        ? null
        : fields['comments']!.text,
  });
  Widget _field(
    String key,
    String label,
    int limit, {
    bool multiline = false,
    bool contact = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: ValueKey('private-$key'),
      controller: fields.putIfAbsent(
        key,
        () => TextEditingController(text: c.form![key] as String? ?? ''),
      ),
      enabled: !c.locked,
      maxLength: limit,
      maxLines: multiline ? 3 : 1,
      decoration: InputDecoration(labelText: label),
      onChanged: (text) => contact
          ? c.editContact(key, text)
          : key == 'comments'
          ? _reviewBody()
          : c.edit(key, text),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.current || c.form == null) return const SizedBox.shrink();
      final a = c.action!;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                hrActionLabel(a),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (c.local?.pending != null)
                const Text(
                  'Original request sealed. Retry its exact identity and content.',
                ),
              if (a == 'profile_save')
                for (final key in hrContactFields)
                  _field(
                    key,
                    hrContactLabels[key]!,
                    key == 'postal_address' ? 1000 : 160,
                    multiline: key == 'postal_address',
                    contact: true,
                  ),
              if ({'review_create', 'review_revise'}.contains(a)) ...[
                if (a == 'review_create') ...[
                  _field('start_date', 'Review period start (YYYY-MM-DD)', 10),
                  _field(
                    'end_date_exclusive',
                    'Review period end, exclusive (YYYY-MM-DD)',
                    10,
                  ),
                  Text('Reviewer ${c.form!['reviewer_id']}'),
                  const SizedBox(height: 12),
                ],
                for (final controller in objectives)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: ObjectKey(controller),
                          controller: controller,
                          enabled: !c.locked,
                          maxLength: 1000,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText:
                                'Objective ${objectives.indexOf(controller) + 1}',
                          ),
                          onChanged: (_) => _reviewBody(),
                        ),
                        if (objectives.length > 1)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: c.locked
                                  ? null
                                  : () {
                                      setState(
                                        () => objectives.remove(controller),
                                      );
                                      controller.dispose();
                                      _reviewBody();
                                    },
                              child: const Text('Remove objective'),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (objectives.length < 20)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: c.locked
                          ? null
                          : () {
                              setState(
                                () => objectives.add(TextEditingController()),
                              );
                              _reviewBody();
                            },
                      child: const Text('Add objective'),
                    ),
                  ),
                _field('comments', 'Review comments', 4000, multiline: true),
              ],
              if (HrCommands.fields[a]!.contains('reason'))
                _field('reason', 'Reason', 1000, multiline: true),
              if (a == 'review_decide')
                _field(
                  'private_text',
                  'Independent review decision',
                  4000,
                  multiline: true,
                ),
              if (HrCommands.fields[a]!.contains('purpose'))
                _field('purpose', 'Purpose', 160, multiline: true),
              if (a == 'hold')
                _field('review_date', 'Hold review date (YYYY-MM-DD)', 10),
              if (a == 'cycle_close') ...[
                const Text(
                  'Closing the synthetic cycle starts the 30-day cleanup period. The recorded instant must be UTC and no later than now.',
                ),
                _field('closed_at', 'UTC closure instant', 40),
              ],
              if (a == 'link_initiate') ...[
                Text('Membership ${c.form!['membership_id']}'),
                Text('User ${c.form!['user_id']}'),
                const Text(
                  'The exact target account must accept this proposal. No role changes or invitations are created.',
                ),
              ],
              if (a == 'review_acknowledge')
                const Text(
                  'Confirm receipt of this revision. Acknowledgement does not record agreement or affect pay.',
                ),
              if (a == 'erase_request')
                const Text(
                  'This request immediately closes private content access. The worker will remove documents and redact private history. A legal hold blocks erasure.',
                ),
              if (a == 'document_reserve') ...[
                DropdownButtonFormField<String>(
                  initialValue: c.form!['classification'] as String,
                  decoration: const InputDecoration(
                    labelText: 'Document classification',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'contact-support',
                      child: Text('Contact support'),
                    ),
                    DropdownMenuItem(
                      value: 'review-evidence',
                      child: Text('Review evidence'),
                    ),
                  ],
                  onChanged: c.locked
                      ? null
                      : (value) => c.edit('classification', value),
                ),
                const SizedBox(height: 12),
                Text(
                  '${c.form!['mime']} · ${c.form!['byte_size']} bytes',
                ),
                const Text(
                  'Reservation does not confirm a document. Upload the exact file and complete its verification next.',
                ),
              ],
              if (a == 'document_complete') ...[
                Text(
                  c.uploadBytes == null
                      ? 'Choose the exact reserved file. File bytes are never stored in drafts.'
                      : 'Exact reserved file selected in memory.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: c.busy ? null : c.choosePendingFile,
                    child: const Text('Choose exact reserved file'),
                  ),
                ),
              ],
              if (a == 'export_prepare')
                const Text(
                  'Prepare an attributable export of the selected immutable revision. Saving it to a local file requires a separate action.',
                ),
              if (c.conflict) ...[
                const Text(
                  'Version conflict. Compare current private content before retaining edits.',
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: c.busy ? null : c.compare,
                      child: const Text('Compare current version'),
                    ),
                    if (c.comparedContacts != null || c.comparedReview != null)
                      OutlinedButton(
                        onPressed: c.busy ? null : c.retainCompared,
                        child: const Text('Retain compared edits'),
                      ),
                  ],
                ),
                if (c.comparedContacts?.profile?.body != null)
                  Text(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(c.comparedContacts!.profile!.body),
                  ),
                if (c.comparedReview != null)
                  Text(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(c.comparedReview!.body),
                  ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: c.locked ? null : c.save,
                    child: const Text('Save encrypted draft'),
                  ),
                  OutlinedButton(
                    onPressed: c.busy || c.local?.pending != null
                        ? null
                        : c.discard,
                    child: const Text('Discard draft'),
                  ),
                  FilledButton(
                    onPressed: c.busy || !c.online || c.conflict
                        ? null
                        : c.submit,
                    child: Text(
                      c.local?.pending == null
                          ? 'Confirm action'
                          : 'Retry exact request',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A separately owned memory copy is released on unmount; no URL or file cache.
class PrivateHrPreview extends StatefulWidget {
  const PrivateHrPreview({required this.bytes, required this.mime, super.key});
  final Uint8List bytes;
  final String mime;
  @override
  State<PrivateHrPreview> createState() => _PrivateHrPreviewState();
}

class _PrivateHrPreviewState extends State<PrivateHrPreview> {
  late final bytes = Uint8List.fromList(widget.bytes);
  late final image = MemoryImage(bytes);
  late final source = 'hr-memory-${identityHashCode(this)}';
  @override
  void dispose() {
    image.evict();
    bytes.fillRange(0, bytes.length, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mime == 'application/pdf') {
      return PdfViewer.data(
        bytes,
        sourceName: source,
        useProgressiveLoading: false,
        maxSizeToCacheOnMemory: 10485760,
        params: PdfViewerParams(
          textSelectionParams: null,
          maxImageBytesCachedOnMemory: 24 * 1024 * 1024,
          linkHandlerParams: PdfLinkHandlerParams(onLinkTap: (_) {}),
          errorBannerBuilder: (context, error, stack, ref) => const Center(
            child: Text('PDF preview is unavailable for this file.'),
          ),
        ),
      );
    }
    if (widget.mime == 'text/plain') {
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        return const Center(
          child: Text('This text document has unsupported encoding.'),
        );
      }
      return SingleChildScrollView(child: Text(text));
    }
    return InteractiveViewer(
      child: Image(
        image: image,
        fit: BoxFit.contain,
        errorBuilder: (_, error, stack) =>
            const Text('Image preview is unavailable for this file.'),
      ),
    );
  }
}
