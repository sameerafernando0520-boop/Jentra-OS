import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../company/application/company_state.dart';
import '../../../company/presentation/widgets/company_context_gate.dart';
import '../../application/payment_state.dart';

final class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(selectedCompanyProvider);
    if (company == null) {
      return const CompanyRouteRedirect(location: '/company/select');
    }

    final moneyAccountsAsync = ref.watch(moneyAccountListProvider);
    final paymentsAsync = ref.watch(paymentListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Finance & Cash - ${company.name}'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(moneyAccountListProvider);
          ref.invalidate(paymentListControllerProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Money Accounts (Cash & Bank)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              moneyAccountsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Error loading accounts: $err'),
                  ),
                ),
                data: (accounts) {
                  if (accounts.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No money accounts found. Payments will auto-seed default accounts.'),
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: accounts.map((acc) {
                        return Container(
                          width: 220,
                          margin: const EdgeInsets.only(right: 12),
                          child: Card(
                            color: acc.accountType == 'cash'
                                ? Colors.green.shade50
                                : Colors.blue.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        acc.accountType == 'cash'
                                            ? Icons.payments
                                            : Icons.account_balance,
                                        color: acc.accountType == 'cash'
                                            ? Colors.green.shade800
                                            : Colors.blue.shade800,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          acc.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Balance',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  Text(
                                    '\$${acc.balance.toStringAsFixed(2)} ${acc.currency}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: acc.accountType == 'cash'
                                          ? Colors.green.shade900
                                          : Colors.blue.shade900,
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
                'Recent Payment Transactions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              paymentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Error loading payments: $err'),
                data: (payments) {
                  if (payments.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text('No payments recorded yet.'),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payments.length,
                    itemBuilder: (context, index) {
                      final pmt = payments[index];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.greenAccent,
                            child: Icon(Icons.arrow_downward, color: Colors.green),
                          ),
                          title: Text(
                            '${pmt.paymentNumber} • ${pmt.partyName ?? "Customer"}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Method: ${pmt.paymentMethod.toUpperCase()} • '
                            '${pmt.moneyAccountName ?? "Cash Account"} • '
                            'Date: ${pmt.paymentDate.toString().split(' ').first}',
                          ),
                          trailing: Text(
                            '+\$${pmt.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.green,
                            ),
                          ),
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
