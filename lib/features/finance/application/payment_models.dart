final class MoneyAccount {
  const MoneyAccount({
    required this.id,
    required this.companyId,
    required this.name,
    required this.accountType, // 'cash', 'bank'
    this.accountNumber,
    this.currency = 'USD',
    required this.balance,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String accountType;
  final String? accountNumber;
  final String currency;
  final double balance;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class PaymentAllocation {
  const PaymentAllocation({
    required this.id,
    required this.companyId,
    required this.paymentId,
    required this.documentId,
    required this.allocatedAmount,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String paymentId;
  final String documentId;
  final double allocatedAmount;
  final DateTime createdAt;
}

final class Payment {
  const Payment({
    required this.id,
    required this.companyId,
    required this.paymentNumber,
    required this.paymentType, // 'incoming', 'outgoing'
    this.partyId,
    this.partyName,
    this.moneyAccountId,
    this.moneyAccountName,
    required this.paymentMethod, // 'cash', 'bank_transfer', 'check', 'card'
    required this.amount,
    required this.paymentDate,
    this.reference,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String paymentNumber;
  final String paymentType;
  final String? partyId;
  final String? partyName;
  final String? moneyAccountId;
  final String? moneyAccountName;
  final String paymentMethod;
  final double amount;
  final DateTime paymentDate;
  final String? reference;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class RecordPaymentInput {
  const RecordPaymentInput({
    required this.invoiceId,
    this.moneyAccountId,
    required this.paymentMethod, // 'cash', 'bank_transfer', 'check', 'card'
    required this.amount,
    required this.paymentDate,
    this.reference,
    this.notes,
  });

  final String invoiceId;
  final String? moneyAccountId;
  final String paymentMethod;
  final double amount;
  final DateTime paymentDate;
  final String? reference;
  final String? notes;
}

final class PaymentResult {
  const PaymentResult({
    required this.success,
    required this.paymentId,
    required this.paymentNumber,
    required this.journalId,
    required this.journalNumber,
    required this.invoiceStatus,
    required this.paidAmount,
    required this.balanceDue,
  });

  final bool success;
  final String paymentId;
  final String paymentNumber;
  final String journalId;
  final String journalNumber;
  final String invoiceStatus;
  final double paidAmount;
  final double balanceDue;
}
