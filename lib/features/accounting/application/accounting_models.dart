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
