import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_assets.dart';

import '../../app_providers.dart';
import 'assets_controller.dart';

String assetActionLabel(String action, [String? kind]) => switch (action) {
  'location' => 'Create asset location',
  'opening' => 'Prepare opening asset',
  'propose' => switch (kind) {
    'book_revision' => 'Revise future book',
    'transfer' => 'Transfer placement',
    'impair' => 'Prepare impairment',
    'revalue' => 'Prepare revaluation',
    'dispose' => 'Prepare disposal',
    _ => 'Prepare proposal',
  },
  'approve' => 'Approve proposal',
  'post' => 'Post approved proposal',
  'depreciate' => 'Post next depreciation',
  'reverse' => 'Reverse latest effect',
  'cancel' => 'Cancel proposal',
  _ => action,
};

class AssetsScreen extends ConsumerWidget {
  const AssetsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(businessCapabilitiesProvider);
    if (caps.isLoading) return const Center(child: CircularProgressIndicator());
    if (caps.hasError) {
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(businessCapabilitiesProvider),
          child: const Text('Retry asset access'),
        ),
      );
    }
    final c = ref.watch(assetsControllerProvider);
    if (c == null) {
      return const Center(
        child: Text('Choose an entity and branch with asset access.'),
      );
    }
    return AssetsWorkspace(key: ValueKey(c), controller: c);
  }
}

class _AssetSection extends StatelessWidget {
  const _AssetSection(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
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
}

class _ProposalReview extends StatelessWidget {
  const _ProposalReview(this.detail);
  final AssetDetail detail;
  @override
  Widget build(BuildContext context) {
    final p = detail.proposal!, data = p.data, b = p.book?.basis;
    final ids = {
      'cost_account_id': detail.asset.costAccountId,
      'accumulated_account_id': detail.asset.accumulatedAccountId,
      'impairment_account_id': detail.asset.impairmentAccountId,
      if (b != null) 'expense_account_id': p.book!.expenseAccountId,
      for (final k in [
        'offset_account_id',
        'loss_account_id',
        'surplus_account_id',
        'proceeds_account_id',
        'gain_account_id',
      ])
        if (data[k] != null) k: data[k] as String,
      if (p.kind == 'transfer') ...{
        'destination_branch_id': data['branch_id'] as String,
        'destination_location_id': data['location_id'] as String,
        if (data['custodian_id'] != null)
          'destination_custodian_id': data['custodian_id'] as String,
      },
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Posting ${p.postingDate.value} · ${p.reason}'),
        if (b != null) ...[
          Text(
            'Book ${b.method.name} · ${b.convention.name} · starts ${b.firstPeriod.value}',
          ),
          Text(
            'Cost ${b.cost.toDecimalString()} · accumulated ${b.openingAccumulated.toDecimalString()} · impairment ${b.openingImpairment.toDecimalString()} ${b.currency}',
          ),
          Text(
            'Residual ${b.residual.toDecimalString()} · ${b.remainingMonths} months · monthly rate ${b.rateNumerator}/${b.rateDenominator} · half-even precision ${b.precision}',
          ),
        ],
        for (final k in ['amount', 'cost', 'proceeds', 'gain_loss'])
          if (data[k] != null)
            Text(
              '${k.replaceAll('_', ' ')} ${data[k]} ${detail.asset.currency}',
            ),
        if (p.before != null)
          Text(
            'Frozen carrying ${p.before!.carrying.toDecimalString()} ${detail.asset.currency}',
          ),
        for (final entry in ids.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key.replaceAll('_id', '').replaceAll('_', ' ')} · ${detail.labels[entry.key] ?? 'Original reference; current label unavailable'}',
                ),
                SelectableText(entry.value),
              ],
            ),
          ),
        if (p.kind == 'capitalize') ...[
          Text(
            'Opening ${detail.opening.reference} · ${detail.opening.cost.toDecimalString()} ${detail.asset.currency}',
          ),
          for (final row in detail.opening.components)
            Text('${row['code']} · ${row['name']} · ${row['amount']}'),
        ],
      ],
    );
  }
}

class AssetsWorkspace extends StatelessWidget {
  const AssetsWorkspace({required this.controller, super.key});
  final AssetsController controller;
  Future<void> _edit(BuildContext context, Future<void> operation) async {
    await operation;
    if (!context.mounted ||
        controller.form == null ||
        controller.error != null) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssetsEditor(controller: controller),
    );
  }

  Widget _action(
    BuildContext context,
    String action, {
    String? kind,
    bool enabled = true,
  }) {
    final c = controller;
    return OutlinedButton(
      onPressed: c.busy || !c.online || !enabled
          ? null
          : () => _edit(context, c.begin(action, kind: kind)),
      child: Text(assetActionLabel(action, kind)),
    );
  }

  Widget _totals(AssetRecord a) => Wrap(
    spacing: 20,
    runSpacing: 8,
    children: [
      Text('Cost ${a.cost.toDecimalString()} ${a.currency}'),
      Text('Depreciation ${a.accumulated.toDecimalString()}'),
      Text('Impairment ${a.impairment.toDecimalString()}'),
      Text('Carrying ${a.carrying.toDecimalString()}'),
    ],
  );
  List<Widget> _detail(BuildContext context) {
    final c = controller, d = c.selected!, a = d.asset, p = d.proposal;
    return [
      _AssetSection('${a.code} · ${a.name}', [
        Text('${a.status} · version ${a.version} · ${a.ownership}'),
        Text(
          'In service ${a.inService.value} · posted book periods ${a.postedPeriods}',
        ),
        const SizedBox(height: 12),
        _totals(a),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (c.has('assets.prepare'))
              for (final kind in [
                'book_revision',
                'transfer',
                'impair',
                'revalue',
                'dispose',
              ])
                if (kind != 'transfer' || c.has('assets.transfer'))
                  _action(
                    context,
                    'propose',
                    kind: kind,
                    enabled: a.status == 'active' && p == null,
                  ),
            if (c.has('assets.depreciate'))
              _action(
                context,
                'depreciate',
                enabled:
                    a.status == 'active' &&
                    p == null &&
                    a.bookId != null &&
                    c.schedule != null &&
                    a.postedPeriods <
                        c.schedule!.definition.basis.remainingMonths,
              ),
            if (c.has('assets.reverse'))
              _action(
                context,
                'reverse',
                enabled: a.lastEffectId != null && p == null,
              ),
          ],
        ),
      ]),
      if (p != null)
        _AssetSection('Current proposal · ${p.kind}', [
          _ProposalReview(d),
          Text('${p.reason} · posting ${p.postingDate.value}'),
          Text(
            p.approval == null
                ? 'Independent approval required.'
                : 'Independent approval recorded.',
          ),
          if (p.actorId == c.scope.actorId)
            const Text('Another authorized member must approve this proposal.'),
          SelectableText('Proposal digest ${p.digest}'),
          if (p.before != null)
            Text(
              'Frozen carrying ${(p.before!.cost - p.before!.accumulated - p.before!.impairment).toDecimalString()} ${a.currency}',
            ),
          if (p.book != null)
            Text(
              'Proposed book · ${p.book!.basis.remainingMonths} months · residual ${p.book!.basis.residual.toDecimalString()}',
            ),
          for (final k in ['amount', 'cost', 'proceeds', 'gain_loss'])
            if (p.data.containsKey(k)) Text('$k: ${p.data[k]} ${a.currency}'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (c.has('assets.approve'))
                _action(
                  context,
                  'approve',
                  enabled: p.approval == null && p.actorId != c.scope.actorId,
                ),
              if (c.has('assets.post'))
                _action(context, 'post', enabled: p.approval != null),
              if (c.has('assets.prepare')) _action(context, 'cancel'),
            ],
          ),
        ]),
      _AssetSection('Opening evidence', [
        Text(d.opening.reference),
        Text(d.opening.reason),
        Text(
          'Opening cost ${d.opening.cost.toDecimalString()} · accumulated ${d.opening.accumulated.toDecimalString()} ${a.currency}',
        ),
        for (final row in d.opening.components)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${row['code']} · ${row['name']}'),
            subtitle: Text('${row['amount']} ${a.currency}'),
          ),
      ]),
      _AssetSection('Immutable history', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in AssetHistoryKind.values)
              OutlinedButton(
                onPressed: c.busy ? null : () => c.history(kind),
                child: Text(kind.name),
              ),
          ],
        ),
        for (final b in c.books)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Book ${b.version} · ${b.reason}'),
            subtitle: Text(
              '${b.definition.basis.firstPeriod.value} · ${b.definition.basis.remainingMonths} months · residual ${b.definition.basis.residual.toDecimalString()}',
            ),
            onTap: c.busy ? null : () => c.showBook(b.id),
          ),
        for (final e in c.effects)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${e.kind} · ${e.postingDate.value} · ${e.reason}'),
                Text(
                  'Carrying ${(e.before.cost - e.before.accumulated - e.before.impairment).toDecimalString()} → ${(e.after.cost - e.after.accumulated - e.after.impairment).toDecimalString()} ${a.currency}',
                ),
                if (e.journalId != null)
                  SelectableText('Journal ${e.journalId}'),
                if (e.originalEffectId != null)
                  SelectableText('Reverses effect ${e.originalEffectId}'),
              ],
            ),
          ),
        for (final p in c.proposals)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${p.kind} · ${p.reason}'),
            subtitle: Text(
              '${p.postingDate.value} · ${p.approval == null ? 'No approval' : 'Approved exact digest'}',
            ),
          ),
        if (c.books.isEmpty && c.effects.isEmpty && c.proposals.isEmpty)
          const Text('No history in this section.'),
        if (c.historyCursor != null)
          TextButton(
            onPressed: c.busy
                ? null
                : () => c.history(c.historyKind, more: true),
            child: const Text('More history'),
          ),
      ]),
      if (c.schedule != null)
        _AssetSection('Frozen depreciation schedule', [
          Text(
            '${c.schedule!.definition.basis.method.name} · half-even · precision ${c.schedule!.definition.basis.precision}',
          ),
          Text(
            'Separate impairment reserve ${c.schedule!.definition.basis.openingImpairment.toDecimalString()} ${a.currency}',
          ),
          for (final period in c.periods)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Period ${period.index} · ${period.start.value} → ${period.endExclusive.value}',
              ),
              subtitle: Text(
                'Posting ${period.postingDate.value}\nCharge ${period.depreciation.toDecimalString()} · carrying ${period.closingCarrying.toDecimalString()} ${a.currency}',
              ),
            ),
          if (c.scheduleCursor != null)
            TextButton(
              onPressed: c.busy ? null : c.moreSchedule,
              child: const Text('More periods'),
            ),
        ]),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.current) {
        return Center(child: Text(c.error ?? 'Asset access changed.'));
      }
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Fixed assets',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Synthetic development'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: c.busy || !c.online ? null : c.refresh,
                child: const Text('Refresh register'),
              ),
              if (c.has('assets.prepare')) _action(context, 'opening'),
              if (c.has('assets.configure')) _action(context, 'location'),
            ],
          ),
          if (!c.online)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Offline. Existing forms can be saved encrypted; submitting requires a current access check.',
              ),
            ),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.error!),
            ),
          if (c.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.message!),
            ),
          _AssetSection('Source availability', [
            const Text(
              'Governed opening evidence requires independent approval. Procurement, stock and equipment capitalization sources are unavailable in this development version.',
            ),
          ]),
          if (c.recovery.isNotEmpty ||
              c.recoveryCursors.values.any((v) => v != null))
            _AssetSection('Encrypted recovery', [
              for (final d in c.recovery)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    assetActionLabel(d.action, d.draft.form['kind'] as String?),
                  ),
                  subtitle: Text(
                    d.pending == null
                        ? 'Saved editable form · version ${d.draft.version}'
                        : 'Exact request pending · reconcile before another action',
                  ),
                  onTap: c.busy || !c.online
                      ? null
                      : () => _edit(context, c.resume(d)),
                ),
              for (final a in c.recoveryCursors.entries)
                if (a.value != null)
                  TextButton(
                    onPressed: c.busy ? null : () => c.moreRecovery(a.key),
                    child: Text('More ${assetActionLabel(a.key)} recovery'),
                  ),
            ]),
          _AssetSection('Scoped asset register', [
            if (c.records.isEmpty && !c.busy)
              const Text('No assets in this branch.'),
            for (final a in c.records)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${a.code} · ${a.name}'),
                subtitle: Text(
                  '${a.status} · ${a.carrying.toDecimalString()} ${a.currency} · version ${a.version}',
                ),
                onTap: c.busy ? null : () => c.select(a),
              ),
            if (c.cursor != null)
              TextButton(
                onPressed: c.busy ? null : c.more,
                child: const Text('More assets'),
              ),
          ]),
          if (c.selected != null) ..._detail(context),
        ],
      );
    },
  );
}

class AssetsEditor extends StatefulWidget {
  const AssetsEditor({required this.controller, super.key});
  final AssetsController controller;
  @override
  State<AssetsEditor> createState() => _AssetsEditorState();
}

class _AssetsEditorState extends State<AssetsEditor> {
  AssetsController get c => widget.controller;
  Widget _field(
    String key,
    String label, {
    bool integer = false,
    bool book = false,
    int lines = 1,
  }) {
    final values = book ? assetMap(c.form!['book']) : c.form!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('${c.form!['id']}/${c.expectedVersion}/$book/$key'),
        initialValue: '${values[key] ?? ''}',
        enabled: !c.locked,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          final Object value = integer ? (int.tryParse(v) ?? v) : v;
          if (book) {
            c.updateBook(key, value);
          } else {
            c.update(key, value);
          }
        },
      ),
    );
  }

  Widget _enum(
    String key,
    String label,
    Map<String, String> choices, {
    bool book = false,
  }) {
    final values = book ? assetMap(c.form!['book']) : c.form!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('${c.form!['id']}/${c.expectedVersion}/$book/$key'),
        initialValue: values[key] as String?,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in choices.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: c.locked
            ? null
            : (v) {
                if (book) {
                  c.updateBook(key, v);
                } else {
                  c.update(key, v);
                }
              },
      ),
    );
  }

  Widget _picker(
    String key,
    String label,
    String kind, {
    bool book = false,
    bool nullable = false,
  }) {
    final value = (book ? assetMap(c.form!['book']) : c.form!)[key] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: c.locked || !c.online
                ? null
                : () async {
                    final chosen = await showDialog<AssetPicker>(
                      context: context,
                      builder: (_) => _AssetPickerDialog(
                        controller: c,
                        label: label,
                        kind: kind,
                        branchId: c.form?['kind'] == 'transfer'
                            ? c.form!['destination_branch_id'] as String?
                            : null,
                      ),
                    );
                    if (!mounted || chosen == null || c.locked) return;
                    c.labels[chosen.id] = '${chosen.code} · ${chosen.name}';
                    if (book) {
                      c.updateBook(key, chosen.id);
                    } else {
                      c.update(key, chosen.id);
                    }
                  },
            child: Text(
              value == null
                  ? 'Choose $label'
                  : c.labels[value] ?? '$label selected · inspect choices',
            ),
          ),
          if (nullable && value != null)
            TextButton(
              onPressed: c.locked ? null : () => c.update(key, null),
              child: Text('Clear $label'),
            ),
        ],
      ),
    );
  }

  List<Widget> _book() => [
    Text(
      'Future depreciation book',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 12),
    _field('residual', 'Residual value', book: true),
    _field(
      'remaining_months',
      'Remaining whole months (1–1200)',
      book: true,
      integer: true,
    ),
    _enum('method', 'Method', {
      'straight_line': 'Straight line',
      'reducing_balance': 'Reducing balance',
    }, book: true),
    _enum('convention', 'First month convention', {
      'in_service_month': 'In-service month',
      'next_month': 'Next month',
    }, book: true),
    if (assetMap(c.form!['book'])['method'] == 'reducing_balance') ...[
      _field(
        'rate_numerator',
        'Monthly rate numerator',
        book: true,
        integer: true,
      ),
      _field(
        'rate_denominator',
        'Monthly rate denominator',
        book: true,
        integer: true,
      ),
    ],
    _field(
      'precision',
      'Published amount precision (0–6)',
      book: true,
      integer: true,
    ),
    _picker(
      'expense_account_id',
      'depreciation expense account',
      'expense',
      book: true,
    ),
    const Text(
      'Half-even rounding. Approved history is retained; revisions apply to the first unposted period.',
    ),
  ];
  List<Widget> _components() {
    final rows = [
      for (final value in c.form!['cost_components'] as List) assetMap(value),
    ];
    void edit(int i, String field, String value) {
      rows[i] = {...rows[i], field: value};
      c.components(rows);
    }

    return [
      Text(
        'Opening cost components',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      for (var i = 0; i < rows.length; i++) ...[
        const SizedBox(height: 12),
        for (final entry in {
          'code': 'Component ${i + 1} code',
          'name': 'Component ${i + 1} name',
          'amount': 'Component ${i + 1} amount',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              key: ValueKey(
                '${c.form!['id']}/${rows.length}/component/$i/${entry.key}',
              ),
              initialValue: '${rows[i][entry.key] ?? ''}',
              enabled: !c.locked,
              decoration: InputDecoration(labelText: entry.value),
              onChanged: (v) => edit(i, entry.key, v),
            ),
          ),
        if (rows.length > 1)
          TextButton(
            onPressed: c.locked
                ? null
                : () => c.components([...rows]..removeAt(i)),
            child: Text('Remove component ${i + 1}'),
          ),
      ],
      Text('Exact total ${c.form!['cost']} ${c.form!['currency_code']}'),
      if (rows.length < 50)
        OutlinedButton(
          onPressed: c.locked
              ? null
              : () => c.components([
                  ...rows,
                  {'code': '', 'name': '', 'amount': ''},
                ]),
          child: const Text('Add cost component'),
        ),
    ];
  }

  List<Widget> _fields() {
    final f = c.form!, action = c.action!, kind = f['kind'];
    return [
      if (action == 'location' || action == 'opening') ...[
        _field('code', 'Code (uppercase)'),
        _field('name', 'Name'),
      ],
      if (action == 'opening') ...[
        _field(
          'source_reference',
          'Unique opening evidence reference (uppercase)',
        ),
        _field('ownership', 'Ownership'),
        _field('in_service', 'In-service date (YYYY-MM-DD)'),
        Text('Entity currency ${f['currency_code']}'),
        const SizedBox(height: 12),
        _picker('location_id', 'asset location', 'locations'),
        _picker('custodian_id', 'custodian', 'custodians', nullable: true),
        ..._components(),
        const SizedBox(height: 16),
        _field('opening_accumulated', 'Opening accumulated depreciation'),
        _picker('cost_account_id', 'asset cost account', 'asset'),
        _picker(
          'accumulated_account_id',
          'accumulated depreciation account',
          'asset',
        ),
        _picker('impairment_account_id', 'impairment reserve account', 'asset'),
        _picker('offset_account_id', 'opening equity account', 'equity'),
      ],
      if (f.containsKey('posting_date'))
        _field('posting_date', 'Posting date (YYYY-MM-DD)'),
      if (kind == 'transfer') ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
            initialValue: f['destination_branch_id'] as String?,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Destination branch'),
            items: [
              for (final branch in c.branches)
                if (branch.id != c.scope.branchId)
                  DropdownMenuItem(
                    value: branch.id,
                    child: Text('${branch.code} · ${branch.name}'),
                  ),
            ],
            onChanged: c.locked
                ? null
                : (v) {
                    if (v != null) unawaited(c.destination(v));
                  },
          ),
        ),
        if (f['destination_branch_id'] != null) ...[
          _picker('location_id', 'destination location', 'locations'),
          _picker(
            'custodian_id',
            'destination custodian',
            'custodians',
            nullable: true,
          ),
        ],
      ],
      if (kind == 'impair') ...[
        _field('amount', 'Impairment amount'),
        _picker('loss_account_id', 'impairment loss account', 'expense'),
      ],
      if (kind == 'revalue') ...[
        _field('cost', 'Revalued gross cost'),
        _picker('surplus_account_id', 'revaluation surplus account', 'equity'),
        _picker('loss_account_id', 'revaluation loss account', 'expense'),
      ],
      if (kind == 'dispose') ...[
        _field('proceeds', 'Synthetic disposal proceeds'),
        _picker('proceeds_account_id', 'proceeds account', 'asset'),
        _picker('gain_account_id', 'disposal gain account', 'revenue'),
        _picker('loss_account_id', 'disposal loss account', 'expense'),
        if (c.selected != null)
          Text(
            'Original carrying ${c.selected!.asset.carrying.toDecimalString()} ${c.selected!.asset.currency}',
          ),
      ],
      if (f.containsKey('book')) ..._book(),
      if (action == 'depreciate')
        Text(
          'Next frozen book period ${f['period_index']}. The server verifies its original schedule and posting period.',
        ),
      if (action == 'reverse')
        const Text(
          'Reverses the latest original active effect and its journal. Later effects and closed periods block reversal.',
        ),
      if ({'approve', 'post', 'cancel'}.contains(action)) ...[
        Text(
          'Current proposal ${c.selected?.proposal?.kind ?? 'from encrypted recovery'}',
        ),
        SelectableText('Exact digest ${f['digest']}'),
        if (c.selected?.proposal?.digest == f['digest'])
          _ProposalReview(c.selected!),
        if (c.selected?.proposal?.digest != f['digest'])
          const Text(
            'The current proposal differs from the saved digest. This request retains its original proposal and version.',
          ),
      ],
      const SizedBox(height: 16),
      _field('reason', 'Reason', lines: 3),
    ];
  }

  Future<void> _close() async {
    if (!await c.canLeave() || !mounted) return;
    await c.closeEditor();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.current || c.form == null) {
        return AlertDialog(
          title: const Text('Asset access changed'),
          content: const Text('Close and select an authorized scope.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      }
      return PopScope(
        canPop: false,
        child: Dialog(
          child: SizedBox(
            width: 960,
            height: MediaQuery.sizeOf(context).height * .9,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    assetActionLabel(c.action!, c.form!['kind'] as String?),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Synthetic development · expected version ${c.expectedVersion}',
                  ),
                  if (c.busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        if (c.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(c.error!),
                          ),
                        if (c.message != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(c.message!),
                          ),
                        if (c.pending != null)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Exact encrypted request pending. Edits are locked until its result is reconciled.',
                            ),
                          ),
                        if (c.conflict) ...[
                          const Text(
                            'The saved version was rejected. Compare the current asset before choosing a new request.',
                          ),
                          if (c.comparison != null)
                            Text(
                              'Current version ${c.comparison!.asset.version} · ${c.comparison!.asset.status} · carrying ${c.comparison!.asset.carrying.toDecimalString()} ${c.comparison!.asset.currency}',
                            ),
                        ],
                        ..._fields(),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (c.confirmed == null &&
                                c.pending == null &&
                                !c.conflict) ...[
                              OutlinedButton(
                                onPressed: c.busy ? null : c.save,
                                child: const Text('Save encrypted draft'),
                              ),
                              FilledButton(
                                onPressed: c.busy || !c.online ? null : c.send,
                                child: const Text('Submit reviewed request'),
                              ),
                              TextButton(
                                onPressed: c.busy || !c.online
                                    ? null
                                    : () async {
                                        await c.discard();
                                        if (context.mounted && c.form == null) {
                                          Navigator.pop(context);
                                        }
                                      },
                                child: const Text('Discard editable draft'),
                              ),
                            ],
                            if (c.pending != null) ...[
                              FilledButton(
                                onPressed: c.busy || !c.online
                                    ? null
                                    : c.reconcile,
                                child: const Text('Reconcile exact request'),
                              ),
                              OutlinedButton(
                                onPressed: c.busy || !c.online ? null : c.send,
                                child: const Text('Retry exact request'),
                              ),
                            ],
                            if (c.conflict) ...[
                              OutlinedButton(
                                onPressed: c.busy || !c.online
                                    ? null
                                    : c.compare,
                                child: const Text('Compare current version'),
                              ),
                              if (c.comparison != null)
                                FilledButton(
                                  onPressed: c.busy || !c.online
                                      ? null
                                      : c.adoptComparison,
                                  child: const Text('Use compared version'),
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: c.busy ? null : _close,
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AssetPickerDialog extends StatefulWidget {
  const _AssetPickerDialog({
    required this.controller,
    required this.label,
    required this.kind,
    this.branchId,
  });
  final AssetsController controller;
  final String label, kind;
  final String? branchId;
  @override
  State<_AssetPickerDialog> createState() => _AssetPickerDialogState();
}

class _AssetPickerDialogState extends State<_AssetPickerDialog> {
  List<AssetPicker> rows = [];
  String query = '', error = '';
  String? after;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted) {
      setState(() {
        if (!widget.controller.current) {
          rows = [];
          after = null;
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final page = await widget.controller.choices(
        widget.kind,
        after: more ? after : null,
        branchId: widget.branchId,
      );
      if (!mounted || !widget.controller.current) return;
      setState(() {
        rows = [if (more) ...rows, ...page.items];
        after = page.nextCursor;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          rows = [];
          after = null;
          error =
              'Permitted choices could not be verified. Retry when connected.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 640,
      height: MediaQuery.sizeOf(context).height * .8,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose ${widget.label}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Filter loaded choices',
              ),
              onChanged: (v) => setState(() => query = v.toLowerCase()),
            ),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: widget.controller.current
                    ? [
                        if (error.isNotEmpty) Text(error),
                        if (rows.isEmpty && !busy)
                          const Text('No permitted choices in this scope.'),
                        for (final row in rows)
                          if ('${row.code} ${row.name}'.toLowerCase().contains(
                            query,
                          ))
                            ListTile(
                              title: Text('${row.code} · ${row.name}'),
                              subtitle: row.currency == null
                                  ? null
                                  : Text(
                                      '${row.currency} · account version ${row.version}',
                                    ),
                              onTap: busy
                                  ? null
                                  : () {
                                      if (widget.controller.current) {
                                        Navigator.pop(context, row);
                                      }
                                    },
                            ),
                        if (after != null)
                          TextButton(
                            onPressed: busy ? null : () => _load(more: true),
                            child: const Text('More choices'),
                          ),
                        if (error.isNotEmpty)
                          TextButton(
                            onPressed: busy ? null : _load,
                            child: const Text('Retry choices'),
                          ),
                      ]
                    : [const Text('Access changed. Close this picker.')],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}
