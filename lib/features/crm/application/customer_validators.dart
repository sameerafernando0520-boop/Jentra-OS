abstract final class CustomerValidators {
  static String? name(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'Enter the customer name.';
    if (normalized.length > 200) {
      return 'Customer name must be 200 characters or fewer.';
    }
    return null;
  }

  static String? email(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    if (normalized.length > 320 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? nonnegativeMoney(String? value, String label) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    if (parsed == null) return 'Enter a valid $label.';
    if (!parsed.isFinite || parsed < 0) {
      return '$label cannot be negative.';
    }
    return null;
  }

  static String? signedMoney(String? value, String label) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    if (parsed == null || !parsed.isFinite) return 'Enter a valid $label.';
    return null;
  }

  static String? paymentTerms(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed < 0 || parsed > 3650) {
      return 'Payment terms must be between 0 and 3650 days.';
    }
    return null;
  }
}
