final class TaxRate {
  const TaxRate({
    required this.id,
    required this.companyId,
    required this.name,
    required this.rate,
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final String name;
  final double rate;
  final bool isActive;
}
