import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/accounting/application/accounting_models.dart';

void main() {
  group('Accounting Reports & Ledger Reconciliation', () {
    test('JournalEntry isBalanced correctly checks debit == credit sum', () {
      final balancedEntry = JournalEntry(
        id: 'jrn-1',
        companyId: 'comp-1',
        entryNumber: 'JRN-1001',
        entryDate: DateTime(2026, 8, 1),
        sourceType: 'manual',
        status: 'posted',
        lines: const [
          JournalLine(
            id: 'jl-1',
            companyId: 'comp-1',
            journalId: 'jrn-1',
            accountCode: '1010',
            accountName: 'Cash',
            debit: 500.00,
            credit: 0.00,
          ),
          JournalLine(
            id: 'jl-2',
            companyId: 'comp-1',
            journalId: 'jrn-1',
            accountCode: '4000',
            accountName: 'Sales Revenue',
            debit: 0.00,
            credit: 500.00,
          ),
        ],
        createdAt: DateTime.now(),
      );

      expect(balancedEntry.totalDebit, equals(500.00));
      expect(balancedEntry.totalCredit, equals(500.00));
      expect(balancedEntry.isBalanced, isTrue);

      final unbalancedEntry = JournalEntry(
        id: 'jrn-2',
        companyId: 'comp-1',
        entryNumber: 'JRN-1002',
        entryDate: DateTime(2026, 8, 1),
        sourceType: 'manual',
        status: 'posted',
        lines: const [
          JournalLine(
            id: 'jl-3',
            companyId: 'comp-1',
            journalId: 'jrn-2',
            accountCode: '1010',
            accountName: 'Cash',
            debit: 500.00,
            credit: 0.00,
          ),
          JournalLine(
            id: 'jl-4',
            companyId: 'comp-1',
            journalId: 'jrn-2',
            accountCode: '4000',
            accountName: 'Sales Revenue',
            debit: 0.00,
            credit: 450.00,
          ),
        ],
        createdAt: DateTime.now(),
      );

      expect(unbalancedEntry.isBalanced, isFalse);
    });

    test('ProfitAndLossReport calculates net profit correctly from revenue and expenses', () {
      final pnl = ProfitAndLossReport(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        rows: const [
          TrialBalanceRow(
            accountCode: '4000',
            accountName: 'Sales Revenue',
            accountType: 'revenue',
            totalDebit: 0.0,
            totalCredit: 10000.00,
            netBalance: 10000.00,
          ),
          TrialBalanceRow(
            accountCode: '5000',
            accountName: 'Cost of Goods Sold',
            accountType: 'expense',
            totalDebit: 4000.00,
            totalCredit: 0.0,
            netBalance: 4000.00,
          ),
          TrialBalanceRow(
            accountCode: '5100',
            accountName: 'Rent Expense',
            accountType: 'expense',
            totalDebit: 1500.00,
            totalCredit: 0.0,
            netBalance: 1500.00,
          ),
        ],
      );

      expect(pnl.totalRevenue, equals(10000.00));
      expect(pnl.totalExpense, equals(5500.00));
      expect(pnl.netProfit, equals(4500.00));
    });

    test('BalanceSheetReport verifies fundamental accounting equation Assets == Liabilities + Equity', () {
      final balanceSheet = BalanceSheetReport(
        asOfDate: DateTime(2026, 12, 31),
        rows: const [
          TrialBalanceRow(
            accountCode: '1010',
            accountName: 'Cash',
            accountType: 'asset',
            totalDebit: 8000.00,
            totalCredit: 0.0,
            netBalance: 8000.00,
          ),
          TrialBalanceRow(
            accountCode: '1100',
            accountName: 'Accounts Receivable',
            accountType: 'asset',
            totalDebit: 2000.00,
            totalCredit: 0.0,
            netBalance: 2000.00,
          ),
          TrialBalanceRow(
            accountCode: '2000',
            accountName: 'Accounts Payable',
            accountType: 'liability',
            totalDebit: 0.0,
            totalCredit: 3000.00,
            netBalance: 3000.00,
          ),
          TrialBalanceRow(
            accountCode: '3000',
            accountName: 'Owner Equity',
            accountType: 'equity',
            totalDebit: 0.0,
            totalCredit: 7000.00,
            netBalance: 7000.00,
          ),
        ],
      );

      expect(balanceSheet.totalAssets, equals(10000.00));
      expect(balanceSheet.totalLiabilities, equals(3000.00));
      expect(balanceSheet.totalEquity, equals(7000.00));
      expect(balanceSheet.isBalanced, isTrue);
    });
  });
}
