import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_domain/jentra_payroll_readiness.dart';
import 'package:jentra_domain/jentra_people.dart';

import 'payroll_controller.dart';

class PayrollReadinessDialog extends StatelessWidget {
  const PayrollReadinessDialog({required this.controller, super.key});
  final PayrollController controller;

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 1000,
      height: 760,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            controller.current &&
                (controller.has('people.payroll.configure') ||
                    controller.has('people.payroll.settle'))
            ? const PayrollReadinessWorkspace()
            : const Center(child: Text('Payroll review access changed.')),
      ),
    ),
  );
}

String _caseLabel(SriLankaApitCase value) => switch (value) {
  SriLankaApitCase.regularPrimary => 'Regular primary employment',
  SriLankaApitCase.lumpSumOrArrears => 'Lump sum or salary arrears',
  SriLankaApitCase.terminalBenefit => 'Terminal benefit',
  SriLankaApitCase.secondaryEmployment => 'Secondary employment',
  SriLankaApitCase.employerPaidTax => 'Employer pays employee tax',
  SriLankaApitCase.foreignEmployer => 'Foreign employer',
};

enum _BankScenario {
  awaiting,
  pending,
  settled,
  rejected,
  returned,
  mismatch,
  upload,
}

String _scenarioLabel(_BankScenario value) => switch (value) {
  _BankScenario.awaiting => 'No bank evidence',
  _BankScenario.pending => 'Transfer pending',
  _BankScenario.settled => 'Matching settled transfer',
  _BankScenario.rejected => 'Transfer rejected',
  _BankScenario.returned => 'Transfer returned after settlement',
  _BankScenario.mismatch => 'Amount differs',
  _BankScenario.upload => 'Unverified statement upload',
};

String _matchLabel(PayrollBankMatch value) => switch (value) {
  PayrollBankMatch.awaitingEvidence => 'Awaiting evidence',
  PayrollBankMatch.unverified => 'Source verification required',
  PayrollBankMatch.pending => 'Pending',
  PayrollBankMatch.matched => 'Evidence matches',
  PayrollBankMatch.rejected => 'Rejected',
  PayrollBankMatch.returned => 'Returned',
  PayrollBankMatch.reviewRequired => 'Review required',
};

/// Entirely synthetic fixtures. The UI cannot ingest or verify live bank data.
PayrollBankReport _rehearseBank(_BankScenario scenario) {
  String id(int value) =>
      '10000000-0000-0000-0000-${value.toString().padLeft(12, '0')}';
  final expected = PayrollBankExpectation(
    tenantId: id(1),
    entityId: id(2),
    branchId: id(3),
    runId: id(4),
    revisionId: id(5),
    runDigest: 'a' * 64,
    obligationId: id(6),
    instructionId: id(7),
    bankConnectionId: id(8),
    sourceAccountToken: 'sample.company',
    beneficiaryToken: 'sample.employee',
    paymentReference: 'SAMPLE-2026-10',
    amount: Money.parse('260500', 'LKR'),
    requestedDate: CivilDate.parse('2026-10-28'),
    preparedBy: id(9),
    approvedBy: id(10),
  );
  PayrollBankObservation observation(
    PayrollBankStatus status,
    int sequence,
  ) => PayrollBankObservation(
    bankConnectionId: id(8),
    eventId: 'sample.$sequence',
    transactionId: 'sample.transfer',
    sequence: sequence,
    sourceAccountToken: 'sample.company',
    beneficiaryToken: 'sample.employee',
    paymentReference: 'SAMPLE-2026-10',
    amount: Money.parse(
      scenario == _BankScenario.mismatch ? '260499' : '260500',
      'LKR',
    ),
    valueDate: CivilDate.parse('2026-10-28'),
    status: status,
    direction: PayrollBankDirection.debit,
    // Models a verified feed only inside this explicitly synthetic rehearsal.
    origin: scenario == _BankScenario.upload
        ? PayrollBankOrigin.unverifiedUpload
        : PayrollBankOrigin.verifiedLiveFeed,
    evidenceDigest: 'b' * 64,
  );
  return matchPayrollBankEvidence(
    expectations: [expected],
    observations: switch (scenario) {
      _BankScenario.awaiting => [],
      _BankScenario.pending => [observation(PayrollBankStatus.pending, 1)],
      _BankScenario.rejected => [observation(PayrollBankStatus.rejected, 1)],
      _BankScenario.returned => [
        observation(PayrollBankStatus.settled, 1),
        observation(PayrollBankStatus.returned, 2),
      ],
      _ => [observation(PayrollBankStatus.settled, 1)],
    },
    asOf: CivilDate.parse('2026-10-31'),
  );
}

class PayrollReadinessWorkspace extends StatefulWidget {
  const PayrollReadinessWorkspace({super.key});

  @override
  State<PayrollReadinessWorkspace> createState() =>
      _PayrollReadinessWorkspaceState();
}

class _PayrollReadinessWorkspaceState extends State<PayrollReadinessWorkspace> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    'month': TextEditingController(text: '2026-10-01'),
    'cash': TextEditingController(text: '300000'),
    'epf': TextEditingController(text: '250000'),
    'etf': TextEditingController(text: '260000'),
    'apit': TextEditingController(text: '300000'),
    'cumulative': TextEditingController(text: '2100000'),
    'deductions': TextEditingController(text: '1000'),
  };
  bool _resident = false,
      _primary = false,
      _fullYear = false,
      _coverage = false,
      _classified = false;
  SriLankaApitCase _case = SriLankaApitCase.regularPrimary;
  SriLankaPayrollPreview? _preview;
  _BankScenario _bank = _BankScenario.awaiting;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.clear();
      field.dispose();
    }
    super.dispose();
  }

  void _estimate() {
    if (!_form.currentState!.validate()) return;
    Money amount(String name) => payrollAmount(_fields[name]!.text, 'LKR');
    setState(
      () => _preview = previewSriLankaPayroll(
        SriLankaPayrollInput(
          month: CivilDate.parse(_fields['month']!.text),
          cashEarnings: amount('cash'),
          epfEarnings: amount('epf'),
          etfEarnings: amount('etf'),
          apitRegularProfits: amount('apit'),
          cumulativeRegularProfits: amount('cumulative'),
          otherDeductions: amount('deductions'),
          apitCase: _case,
          residentOrCitizen: _resident,
          primaryDeclarationOrOnlyEmployment: _primary,
          joinedOrLeftDuringTaxYear: !_fullYear,
          contributionCoverageConfirmed: _coverage,
          earningsClassificationConfirmed: _classified,
        ),
      ),
    );
  }

  Widget _field(String name, String label) => SizedBox(
    width: 290,
    child: TextFormField(
      key: ValueKey('statutory-$name'),
      controller: _fields[name],
      decoration: InputDecoration(
        labelText: label,
        suffixText: name == 'month' ? null : 'LKR',
      ),
      onChanged: (_) => setState(() => _preview = null),
      keyboardType: name == 'month'
          ? TextInputType.datetime
          : const TextInputType.numberWithOptions(decimal: true),
      validator: (text) {
        try {
          if (name == 'month') {
            if (CivilDate.parse(text ?? '').utc.day != 1)
              return 'Use the first day of the month.';
          } else {
            payrollAmount(text ?? '', 'LKR');
          }
          return null;
        } on FormatException {
          return name == 'month'
              ? 'Use YYYY-MM-01.'
              : 'Enter a nonnegative decimal, up to six places.';
        }
      },
    ),
  );

  Widget _check(
    String key,
    String label,
    bool value,
    void Function(bool) update,
  ) => CheckboxListTile(
    key: ValueKey(key),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    value: value,
    title: Text(label),
    onChanged: (next) => setState(() {
      update(next!);
      _preview = null;
    }),
  );

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

  Widget _total(String label, Money? amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text(
      '$label: ${amount == null ? 'Review required' : '${amount.toDecimalString()} LKR'}',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = _preview, bank = _rehearseBank(_bank).lines.single;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Statutory & bank review',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close review',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey('payroll-readiness-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              const Text('Development preview · sample amounts only'),
              const SizedBox(height: 8),
              const Text(
                'Estimates stay on this screen. A qualified reviewer must approve the policy before production payroll.',
              ),
              const SizedBox(height: 12),
              _card('Sri Lanka payroll review', [
                const Text(
                  'EPF: employee 8%, employer 12%. ETF: employer 3%. APIT uses regular taxable profits before employee EPF deductions.',
                ),
                const SizedBox(height: 12),
                Form(
                  key: _form,
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _field('month', 'Payable month (YYYY-MM-01)'),
                      _field('cash', 'Sample cash earnings'),
                      _field('epf', 'EPF contribution earnings'),
                      _field('etf', 'ETF contribution earnings'),
                      _field('apit', 'APIT regular taxable profits'),
                      _field(
                        'cumulative',
                        'Cumulative profits including this month',
                      ),
                      _field('deductions', 'Other employee deductions'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<SriLankaApitCase>(
                  key: const ValueKey('statutory-case'),
                  initialValue: _case,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'APIT payment case',
                  ),
                  items: [
                    for (final value in SriLankaApitCase.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_caseLabel(value)),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _case = value!;
                    _preview = null;
                  }),
                ),
                _check(
                  'statutory-resident',
                  'Resident employee or Sri Lankan citizen',
                  _resident,
                  (value) => _resident = value,
                ),
                _check(
                  'statutory-primary',
                  'Primary declaration supplied or only one employment',
                  _primary,
                  (value) => _primary = value,
                ),
                _check(
                  'statutory-year',
                  'Employee has worked throughout this assessment year',
                  _fullYear,
                  (value) => _fullYear = value,
                ),
                _check(
                  'statutory-coverage',
                  'Standard EPF and ETF coverage applies to this sample',
                  _coverage,
                  (value) => _coverage = value,
                ),
                _check(
                  'statutory-classification',
                  'EPF, ETF and APIT earnings have been classified separately',
                  _classified,
                  (value) => _classified = value,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _estimate,
                    child: const Text('Calculate review estimate'),
                  ),
                ),
                if (result != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    result.hasEstimate ? 'Review estimate' : 'Review required',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final blocker in result.blockers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(blocker),
                    ),
                  if (result.apitFormula != null) ...[
                    _total('Employee EPF', result.employeeEpf),
                    _total('Employer EPF', result.employerEpf),
                    _total('Employer ETF', result.employerEtf),
                    _total('APIT formula estimate', result.apitFormula),
                    _total('Employee net cash estimate', result.netCash),
                    _total(
                      'Combined EPF remittance estimate',
                      result.epfRemittance,
                    ),
                    const Text(
                      'Draft rounding: cents, half away from zero. The official APIT lookup and contribution rounding still require review.',
                    ),
                  ],
                ],
              ]),
              _card('Bank-transfer acceptance rehearsal', [
                const Text(
                  'No live bank connected. This synthetic transfer is 260500.00 LKR; changing the scenario does not send or record a payment.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_BankScenario>(
                  key: const ValueKey('bank-scenario'),
                  initialValue: _bank,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Synthetic bank scenario',
                  ),
                  items: [
                    for (final value in _BankScenario.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_scenarioLabel(value)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _bank = value!),
                ),
                const SizedBox(height: 12),
                Text(
                  'Rehearsal outcome: ${_matchLabel(bank.match)}',
                  key: const ValueKey('bank-outcome'),
                ),
                const SizedBox(height: 6),
                Text(bank.reason),
                const SizedBox(height: 12),
                const Text(
                  'Live acceptance must bind the approved payroll revision, source account, beneficiary, exact amount, currency and bank reference. Duplicate or conflicting evidence requires investigation.',
                ),
              ]),
              _card('Before real payroll and payment acceptance', [
                for (final item in SriLankaPayrollPreview.reviewRequirements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Pending · $item'),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Pending · Selected bank, verified feed, protected beneficiary mapping, return handling and independently approved live transfer acceptance',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Official source snapshot checked 31 October 2026. Future months require a refreshed review.',
                ),
                const SizedBox(height: 8),
                const SelectableText(
                  'APIT Table 01: ${SriLankaPayrollSources.apitTable}\nEPF: ${SriLankaPayrollSources.epf}\nETF: ${SriLankaPayrollSources.etf}',
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
