import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

/// Interactive specimens. These actions never submit business commands.
class ComponentCatalogueScreen extends StatefulWidget {
  const ComponentCatalogueScreen({super.key});

  @override
  State<ComponentCatalogueScreen> createState() =>
      _ComponentCatalogueScreenState();
}

class _ComponentCatalogueScreenState extends State<ComponentCatalogueScreen> {
  int _section = 0;
  bool _notifications = true;
  bool _approved = false;
  final _form = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _amount = TextEditingController(text: '125,000.00');
  final _date = TextEditingController(text: '05 Sep 2026');

  @override
  void dispose() {
    _customer.dispose();
    _amount.dispose();
    _date.dispose();
    super.dispose();
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const Key('catalogue-scroll'),
    padding: const EdgeInsets.all(JentraSpacing.x6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const JentraSectionHeader(
          title: 'Design system catalogue',
          description:
              'Jentra Flow / 02 — the language of a connected business.',
          trailing: JentraStatusBadge(
            label: 'Version 2.0',
            tone: JentraStatusTone.info,
          ),
        ),
        const SizedBox(height: 24),
        const _BrandHero(),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, label) in [
              'Foundations',
              'Components',
              'Data patterns',
            ].indexed)
              ChoiceChip(
                key: Key('catalogue-tab-$index'),
                label: Text(label),
                selected: _section == index,
                onSelected: (_) => setState(() => _section = index),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (_section == 0) ..._foundations(),
        if (_section == 1) ..._components(),
        if (_section == 2) ..._patterns(),
        const SizedBox(height: 24),
        Text(
          'OPERATE  ·  CONNECT  ·  GROW',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: context.jentraColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
  );

  List<Widget> _foundations() => [
    _Specimen(
      number: '01',
      title: 'A spectrum with purpose',
      description: 'Navy anchors the workspace. Blue moves work forward. Teal and green connect it to the brand.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 900
              ? 6
              : constraints.maxWidth > 550
              ? 3
              : 2;
          return Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final swatch in const [
                ('Midnight', '#061B31', 'Structure', JentraColors.navy900),
                (
                  'Signal blue',
                  '#0064D9',
                  'Primary action',
                  JentraColors.actionBlue,
                ),
                ('Cyan', '#00B8D9', 'Connection', JentraColors.cyan500),
                ('Teal', '#008C82', 'Progress', JentraColors.teal600),
                ('Growth', '#77E52D', 'Brand accent', JentraColors.lime400),
                ('Cloud', '#F4F7FA', 'Workspace', JentraColors.appBackground),
              ])
                SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                  child: _ColorSwatch(
                    name: swatch.$1,
                    hex: swatch.$2,
                    role: swatch.$3,
                    color: swatch.$4,
                    onCopy: () async {
                      await Clipboard.setData(ClipboardData(text: swatch.$2));
                      if (mounted) _notice('${swatch.$1} copied: ${swatch.$2}');
                    },
                  ),
                ),
            ],
          );
        },
      ),
    ),
    const SizedBox(height: 20),
    _ResponsivePair(
      first: _Specimen(
        number: '02',
        title: 'Clarity in every character',
        description: 'Manrope / interface and language',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Built for what’s next.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 20),
            Text(
              'One business. One clear view.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'From the first conversation to the final payment, every detail has a place.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'IBM PLEX MONO / FINANCIAL DATA',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.3,
                color: context.jentraColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'LKR 1,284,500.00',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: JentraTypography.monoFamily,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'INV-2026-01084',
              style: TextStyle(
                fontFamily: JentraTypography.monoFamily,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      second: _Specimen(
        number: '03',
        title: 'Space to focus',
        description: 'A 4px rhythm. Precise edges. Comfortable work.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final value in [4, 8, 12, 16, 24, 32])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$value',
                        style: const TextStyle(
                          fontFamily: JentraTypography.monoFamily,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Container(
                      width: value * 5,
                      height: 10,
                      decoration: BoxDecoration(
                        color: context.jentraColors.action,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Geometry(label: 'Control / 8', radius: 8),
                _Geometry(label: 'Panel / 14', radius: 14),
                _Geometry(label: 'Dialog / 20', radius: 20),
              ],
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 20),
    _Specimen(
      number: '04',
      title: 'The mark leads. The interface supports.',
      description: 'Use the supplied mark in its original proportions. Give it at least one quarter of its visible height in clear space. Reserve the spectrum for identity moments.',
      child: Wrap(
        spacing: 24,
        runSpacing: 20,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          JentraBrandLockup(
            size: 52,
            inverse: Theme.of(context).brightness == Brightness.dark,
          ),
          const JentraStatusBadge(
            label: 'Light + dark themes',
            tone: JentraStatusTone.info,
          ),
          const JentraStatusBadge(
            label: 'Compact + comfortable',
            tone: JentraStatusTone.neutral,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _components() => [
    _Specimen(
      number: '01',
      title: 'One clear next step',
      description: 'A single blue primary action per task. Secondary actions stay quieter. Try these local specimens.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          JentraPrimaryButton(
            label: _approved ? 'Preview approved' : 'Approve preview',
            icon: Icons.check,
            onPressed: () {
              setState(() => _approved = !_approved);
              _notice(
                _approved
                    ? 'Preview approved. No business record was changed.'
                    : 'Preview reset.',
              );
            },
          ),
          OutlinedButton.icon(
            onPressed: () =>
                _notice('Preview draft saved for this demonstration.'),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save draft'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _approved = false);
              _notice('Preview reset.');
            },
            child: const Text('Reset'),
          ),
          const JentraPrimaryButton(label: 'Unavailable', onPressed: null),
          OutlinedButton.icon(
            onPressed: _showDiscard,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Destructive action'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.jentraColors.danger,
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    const _Specimen(
      number: '02',
      title: 'Meaning beyond color',
      description: 'Each status has a label, an icon, and a readable foreground in both themes.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          JentraStatusBadge(label: 'Draft', tone: JentraStatusTone.neutral),
          JentraStatusBadge(label: 'Approved', tone: JentraStatusTone.success),
          JentraStatusBadge(
            label: 'Needs review',
            tone: JentraStatusTone.warning,
          ),
          JentraStatusBadge(label: 'Rejected', tone: JentraStatusTone.danger),
          JentraStatusBadge(label: 'In progress', tone: JentraStatusTone.info),
        ],
      ),
    ),
    const SizedBox(height: 20),
    _Specimen(
      number: '03',
      title: 'Forms that guide the work',
      description: 'Persistent labels, explicit validation, and visible keyboard focus. Sample inputs only.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResponsivePair(
              first: TextFormField(
                key: const Key('specimen-customer'),
                controller: _customer,
                decoration: const InputDecoration(
                  labelText: 'Customer name',
                  hintText: 'e.g. Ceylon Trading',
                  prefixIcon: Icon(Icons.business_outlined),
                  helperText: 'Required for this preview',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a customer name.'
                    : null,
              ),
              second: TextFormField(
                controller: _amount,
                decoration: const InputDecoration(
                  labelText: 'Invoice amount',
                  prefixText: 'LKR  ',
                  helperText: 'Preview currency · Sri Lankan rupee',
                ),
                style: const TextStyle(fontFamily: JentraTypography.monoFamily),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) =>
                    RegExp(r'^\d+(,\d{3})*(\.\d{1,2})?$')
                        .hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Use an amount such as 125,000.00.',
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _date,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Posting date',
                suffixIcon: IconButton(
                  tooltip: 'Choose preview date',
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: _chooseDate,
                ),
              ),
              onTap: _chooseDate,
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify the document owner'),
              subtitle: const Text(
                'Preference specimen · no notification is sent',
              ),
              value: _notifications,
              onChanged: (value) => setState(() => _notifications = value),
            ),
            const SizedBox(height: 16),
            JentraPrimaryButton(
              label: 'Validate preview',
              icon: Icons.check_circle_outline,
              onPressed: () {
                if (_form.currentState!.validate()) {
                  _notice('Preview is valid. No document was submitted.');
                }
              },
            ),
          ],
        ),
      ),
    ),
  ];

  void _showDiscard() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard this preview?'),
      content: const Text(
        'This is a confirmation specimen. Your business data is unaffected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep preview'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            setState(() => _approved = false);
            _notice('Preview discarded.');
          },
          style: FilledButton.styleFrom(
            backgroundColor: context.jentraColors.danger,
            foregroundColor: Theme.of(context).colorScheme.surface,
          ),
          child: const Text('Discard preview'),
        ),
      ],
    ),
  );

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(2026, 9, 5),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );
    if (date == null || !mounted) return;
    _date.text =
        '${date.day.toString().padLeft(2, '0')} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.year}';
  }

  List<Widget> _patterns() => [
    const _ResponsivePair(
      first: JentraKpiCard(
        label: 'Available balance',
        value: 'LKR 6.28M',
        helper: 'Sample · healthy',
        icon: Icons.account_balance_wallet_outlined,
        tone: JentraStatusTone.success,
      ),
      second: JentraKpiCard(
        label: 'Overdue invoices',
        value: 'LKR 620K',
        helper: 'Sample · 12 need review',
        icon: Icons.receipt_long_outlined,
        tone: JentraStatusTone.warning,
      ),
    ),
    const SizedBox(height: 20),
    _Specimen(
      number: '01',
      title: 'Precision earns trust',
      description: 'Read-only sample invoices. Text aligns left; money aligns right. Identifiers and financial values use tabular numerals.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMaxHeight: 40 * MediaQuery.textScalerOf(context).scale(1),
          headingRowHeight: 40 * MediaQuery.textScalerOf(context).scale(1),
          columns: const [
            DataColumn(label: Text('Invoice')),
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Amount · LKR'), numeric: true),
          ],
          rows: [
            for (final row in const [
              (
                'INV-2026-01084',
                'Ceylon Trading',
                'Approved',
                JentraStatusTone.success,
                '125,000.00',
              ),
              (
                'INV-2026-01085',
                'Lanka Office Co.',
                'Needs review',
                JentraStatusTone.warning,
                '84,750.00',
              ),
              (
                'INV-2026-01086',
                'Southern Supplies',
                'Draft',
                JentraStatusTone.neutral,
                '216,400.00',
              ),
            ])
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      row.$1,
                      style: const TextStyle(
                        fontFamily: JentraTypography.monoFamily,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  DataCell(Text(row.$2)),
                  DataCell(JentraStatusBadge(label: row.$3, tone: row.$4)),
                  DataCell(
                    Text(
                      row.$5,
                      style: const TextStyle(
                        fontFamily: JentraTypography.monoFamily,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 20),
    _Specimen(
      number: '02',
      title: 'Every state deserves a next step',
      description: 'Empty workspaces explain what belongs here and offer a useful action.',
      child: JentraEmptyState(
        title: 'Your next opportunity starts here',
        description: 'Keep conversations, ownership, and progress connected from the first contact.',
        icon: Icons.handshake_outlined,
        action: JentraPrimaryButton(
          label: 'Try a form',
          icon: Icons.add,
          onPressed: () => setState(() => _section = 1),
        ),
      ),
    ),
  ];
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: JentraColors.navy900,
      borderRadius: BorderRadius.circular(20),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  JentraColors.actionBlue,
                  JentraColors.cyan500,
                  JentraColors.teal600,
                  JentraColors.lime400,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showMark =
                    constraints.maxWidth > 620 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.6;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'JENTRA FLOW  /  DESIGN SYSTEM',
                            style: TextStyle(
                              color: JentraColors.darkTextSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'A smarter way forward.',
                            style: Theme.of(context).textTheme.headlineLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 36,
                                  height: 1.18,
                                ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'A clear view. A connected team. Room to grow.',
                            style: TextStyle(
                              color: JentraColors.darkTextSecondary,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Wrap(
                            spacing: 24,
                            runSpacing: 12,
                            children: [
                              _BrandValue(
                                label: 'Operate',
                                color: JentraColors.actionBlue,
                              ),
                              _BrandValue(
                                label: 'Connect',
                                color: JentraColors.cyan500,
                              ),
                              _BrandValue(
                                label: 'Grow',
                                color: JentraColors.lime400,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (showMark) ...[
                      const SizedBox(width: 48),
                      const JentraBrandMark(size: 156),
                      const SizedBox(width: 24),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _BrandValue extends StatelessWidget {
  const _BrandValue({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

class _Specimen extends StatelessWidget {
  const _Specimen({
    required this.number,
    required this.title,
    required this.description,
    required this.child,
  });
  final String number;
  final String title;
  final String description;
  final Widget child;
  @override
  Widget build(BuildContext context) => JentraPanel(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          number,
          style: TextStyle(
            fontFamily: JentraTypography.monoFamily,
            fontSize: 11,
            color: context.jentraColors.action,
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.jentraColors.textSecondary),
        ),
        const SizedBox(height: 24),
        child,
      ],
    ),
  );
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.first, required this.second});
  final Widget first;
  final Widget second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 780 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 20), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 20),
          Expanded(child: second),
        ],
      );
    },
  );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.name,
    required this.hex,
    required this.role,
    required this.color,
    required this.onCopy,
  });
  final String name;
  final String hex;
  final String role;
  final Color color;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Tooltip(
        message: 'Copy $name $hex',
        child: Material(
          color: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: context.jentraColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onCopy,
            child: Semantics(
              button: true,
              label: 'Copy $name $hex',
              child: const SizedBox(height: 72, width: double.infinity),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(name, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        hex,
        style: TextStyle(
          fontFamily: JentraTypography.monoFamily,
          fontSize: 11,
          color: context.jentraColors.textSecondary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        role,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: context.jentraColors.textSecondary),
      ),
    ],
  );
}

class _Geometry extends StatelessWidget {
  const _Geometry({required this.label, required this.radius});
  final String label;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    decoration: BoxDecoration(
      color: context.jentraColors.neutralSurface,
      border: Border.all(color: context.jentraColors.border),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}
