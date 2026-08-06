final class UserProfile {
  const UserProfile({
    required this.id,
    this.fullName,
    this.avatarUrl,
    this.defaultCompanyId,
  });

  final String id;
  final String? fullName;
  final String? avatarUrl;
  final String? defaultCompanyId;
}
