/// Base contract for repositories that access tenant-owned business data.
///
/// Repositories must receive a company id rather than relying on mutable global
/// state. PostgreSQL RLS remains the final authorization boundary.
abstract interface class CompanyScopedRepository {
  String get companyId;
}
