final class Account {
  const Account({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    required this.type, // 'asset', 'liability', 'equity', 'revenue', 'expense'
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final String code;
  final String name;
  final String type;
  final bool isActive;
}

final class JournalLine {
  const JournalLine({
    required this.id,
    required this.companyId,
    required this.journalId,
    this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.description,
  });

  final String id;
  final String companyId;
  final String journalId;
  final String? accountId;
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String? description;
}

final class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.companyId,
    required this.entryNumber,
    required this.entryDate,
    required this.sourceType,
    this.sourceId,
    this.narration,
    required this.status,
    this.lines = const [],
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String entryNumber;
  final DateTime entryDate;
  final String sourceType;
  final String? sourceId;
  final String? narration;
  final String status;
  final List<JournalLine> lines;
  final DateTime createdAt;

  double get totalDebit => lines.fold(0.0, (sum, line) => sum + line.debit);
  double get totalCredit => lines.fold(0.0, (sum, line) => sum + line.credit);
  bool get isBalanced => (totalDebit - totalCredit).abs() < 0.001;
}

final class AccountingPeriod {
  const AccountingPeriod({
    required this.id,
    required this.companyId,
    required this.periodName,
    required this.startDate,
    required this.endDate,
    this.isClosed = false,
    this.closedAt,
    this.closedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String periodName;
  final DateTime startDate;
  final DateTime endDate;
  final bool isClosed;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class ManualJournalLineInput {
  const ManualJournalLineInput({
    this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.description,
  });

  final String? accountId;
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String? description;

  Map<String, dynamic> toJson() {
    return {
      if (accountId != null) 'account_id': accountId,
      'account_code': accountCode,
      'account_name': accountName,
      'debit': debit,
      'credit': credit,
      if (description != null) 'description': description,
    };
  }
}

final class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.totalDebit,
    required this.totalCredit,
    required this.netBalance,
  });

  final String accountCode;
  final String accountName;
  final String accountType;
  final double totalDebit;
  final double totalCredit;
  final double netBalance;
}

final class ProfitAndLossReport {
  const ProfitAndLossReport({
    required this.startDate,
    required this.endDate,
    required this.rows,
  });

  final DateTime startDate;
  final DateTime endDate;
  final List<TrialBalanceRow> rows;

  double get totalRevenue => rows
      .where((r) => r.accountType == 'revenue')
      .fold(0.0, (sum, r) => sum + r.netBalance);

  double get totalExpense => rows
      .where((r) => r.accountType == 'expense')
      .fold(0.0, (sum, r) => sum + r.netBalance);

  double get netProfit => totalRevenue - totalExpense;
}

final class BalanceSheetReport {
  const BalanceSheetReport({
    required this.asOfDate,
    required this.rows,
  });

  final DateTime asOfDate;
  final List<TrialBalanceRow> rows;

  double get totalAssets => rows
      .where((r) => r.accountType == 'asset')
      .fold(0.0, (sum, r) => sum + r.netBalance);

  double get totalLiabilities => rows
      .where((r) => r.accountType == 'liability')
      .fold(0.0, (sum, r) => sum + r.netBalance);

  double get totalEquity => rows
      .where((r) => r.accountType == 'equity')
      .fold(0.0, (sum, r) => sum + r.netBalance);

  bool get isBalanced =>
      (totalAssets - (totalLiabilities + totalEquity)).abs() < 0.001;
}
