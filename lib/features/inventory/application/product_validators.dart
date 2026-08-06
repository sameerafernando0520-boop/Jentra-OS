abstract final class ProductValidators {
  static String? validateName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return 'Product name is required';
    }
    if (trimmed.length > 200) {
      return 'Product name must be 200 characters or less';
    }
    return null;
  }

  static String? validateUnitPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Selling price is required';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid selling price';
    }
    if (parsed < 0) {
      return 'Selling price cannot be negative';
    }
    return null;
  }

  static String? validateCostPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid cost price';
    }
    if (parsed < 0) {
      return 'Cost price cannot be negative';
    }
    return null;
  }

  static String? validateSku(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.length > 100) {
      return 'SKU must be 100 characters or less';
    }
    return null;
  }

  static String? validateBarcode(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.length > 100) {
      return 'Barcode must be 100 characters or less';
    }
    return null;
  }
}
