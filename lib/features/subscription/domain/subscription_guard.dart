abstract final class SubscriptionGuard {
  /// Evaluates subscription entitlement (fail-closed if status is null or inactive).
  static bool evaluateEntitlement({
    required String? status,
    DateTime? trialEndsAt,
    DateTime? now,
  }) {
    if (status == null) return false;

    final currentTime = now ?? DateTime.now();

    if (status == 'active') {
      return true;
    }

    if (status == 'trialing') {
      if (trialEndsAt == null) return false;
      return currentTime.isBefore(trialEndsAt) || currentTime.isAtSameMomentAs(trialEndsAt);
    }

    // Fail closed for past_due, canceled, expired, or unknown status
    return false;
  }
}
