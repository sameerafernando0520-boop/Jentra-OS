import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/accounting_state.dart';

final class AccountingScreen extends ConsumerWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final journalsAsync = ref.watch(journalListControllerProvider);
    final accountsAsync = ref.watch(chartOfAccountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Accounting & General Ledger - ${company.name}'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(journalListControllerProvider);
          ref.invalidate(chartOfAccountsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chart of Accounts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              accountsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Error loading accounts: $err'),
                data: (accounts) {
                  if (accounts.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No accounts found. Recording payments will auto-seed standard accounts.'),
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: accounts.map((acc) {
                        return Container(
                          width: 180,
                          margin: const EdgeInsets.only(right: 12),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    acc.code,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    acc.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    acc.type.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Automated Journal Entries (Double-Entry Ledger)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              journalsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Error loading journal entries: $err'),
                data: (journals) {
                  if (journals.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text('No journal entries posted yet.'),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: journals.length,
                    itemBuilder: (context, index) {
                      final jrn = journals[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: jrn.isBalanced
                                ? Colors.blue.shade100
                                : Colors.red.shade100,
                            child: Icon(
                              Icons.book,
                              color: jrn.isBalanced
                                  ? Colors.blue.shade800
                                  : Colors.red.shade800,
                            ),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                jrn.entryNumber,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  jrn.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'Date: ${jrn.entryDate.toString().split(' ').first} • ${jrn.narration ?? ""}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Account',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 80,
                                            child: Text(
                                              'Debit',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                              textAlign: TextAlign.end,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 80,
                                            child: Text(
                                              'Credit',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                              textAlign: TextAlign.end,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const Divider(),
                                  ...jrn.lines.map(
                                    (line) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${line.accountCode} - ${line.accountName}',
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              SizedBox(
                                                width: 80,
                                                child: Text(
                                                  line.debit > 0
                                                      ? '\$${line.debit.toStringAsFixed(2)}'
                                                      : '-',
                                                  textAlign: TextAlign.end,
                                                  style: TextStyle(
                                                    fontWeight: line.debit > 0
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 80,
                                                child: Text(
                                                  line.credit > 0
                                                      ? '\$${line.credit.toStringAsFixed(2)}'
                                                      : '-',
                                                  textAlign: TextAlign.end,
                                                  style: TextStyle(
                                                    fontWeight: line.credit > 0
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Ledger Balance Status:',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        jrn.isBalanced
                                            ? 'BALANCED (Debits \$${jrn.totalDebit.toStringAsFixed(2)} = Credits \$${jrn.totalCredit.toStringAsFixed(2)})'
                                            : 'UNBALANCED',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: jrn.isBalanced ? Colors.green : Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
