final class PartyContact {
  const PartyContact({
    required this.id,
    required this.companyId,
    required this.partyId,
    required this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.jobTitle,
    this.isPrimary = false,
  });

  final String id;
  final String companyId;
  final String partyId;
  final String firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? jobTitle;
  final bool isPrimary;
}

final class PartyAddress {
  const PartyAddress({
    required this.id,
    required this.companyId,
    required this.partyId,
    required this.addressType,
    required this.street,
    this.city,
    this.state,
    this.postalCode,
    required this.country,
    this.isPrimary = false,
  });

  final String id;
  final String companyId;
  final String partyId;
  final String addressType;
  final String street;
  final String? city;
  final String? state;
  final String? postalCode;
  final String country;
  final bool isPrimary;
}

final class Lead {
  const Lead({
    required this.id,
    required this.companyId,
    required this.name,
    this.companyName,
    this.email,
    this.phone,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String? companyName;
  final String? email;
  final String? phone;
  final String status;
  final String? notes;
  final DateTime createdAt;
}

final class Activity {
  const Activity({
    required this.id,
    required this.companyId,
    this.partyId,
    this.leadId,
    required this.activityType,
    required this.subject,
    this.description,
    this.dueDate,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String? partyId;
  final String? leadId;
  final String activityType;
  final String subject;
  final String? description;
  final DateTime? dueDate;
  final String status;
  final DateTime createdAt;
}

final class ReceivablesAgingRow {
  const ReceivablesAgingRow({
    required this.customerId,
    required this.customerName,
    required this.currentAmount,
    required this.days1To30,
    required this.days31To60,
    required this.days61To90,
    required this.days90Plus,
    required this.totalDue,
  });

  final String customerId;
  final String customerName;
  final double currentAmount;
  final double days1To30;
  final double days31To60;
  final double days61To90;
  final double days90Plus;
  final double totalDue;
}
