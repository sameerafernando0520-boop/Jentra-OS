final class Customer {
  const Customer({
    required this.id,
    required this.companyId,
    required this.name,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.mobile,
    required this.taxNumber,
    required this.creditLimit,
    required this.paymentTermsDays,
    required this.openingBalance,
    required this.notes,
    required this.tags,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String? displayName;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? taxNumber;
  final double creditLimit;
  final int? paymentTermsDays;
  final double openingBalance;
  final String? notes;
  final List<String> tags;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get title {
    final preferred = displayName?.trim();
    return preferred == null || preferred.isEmpty ? name : preferred;
  }

  String get sortName => title.toLowerCase();

  String? get primaryPhone {
    final preferred = mobile?.trim();
    if (preferred != null && preferred.isNotEmpty) return preferred;
    final fallback = phone?.trim();
    return fallback == null || fallback.isEmpty ? null : fallback;
  }
}

final class CustomerInput {
  const CustomerInput({
    required this.name,
    this.displayName,
    this.email,
    this.phone,
    this.mobile,
    this.taxNumber,
    this.creditLimit = 0,
    this.paymentTermsDays,
    this.openingBalance = 0,
    this.notes,
    this.tags = const <String>[],
  });

  final String name;
  final String? displayName;
  final String? email;
  final String? phone;
  final String? mobile;
  final String? taxNumber;
  final double creditLimit;
  final int? paymentTermsDays;
  final double openingBalance;
  final String? notes;
  final List<String> tags;
}

final class CustomerCursor {
  const CustomerCursor({required this.sortName, required this.id});

  final String sortName;
  final String id;
}

final class CustomerPage {
  const CustomerPage({required this.customers, required this.nextCursor});

  final List<Customer> customers;
  final CustomerCursor? nextCursor;
}
