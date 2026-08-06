abstract final class InvoiceValidators {
  static String? validateCustomer(String? customerId) {
    if (customerId == null || customerId.trim().isEmpty) {
      return 'Please select a customer';
    }
    return null;
  }

  static String? validateQuantity(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Quantity is required';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid quantity';
    }
    if (parsed <= 0) {
      return 'Quantity must be greater than 0';
    }
    return null;
  }

  static String? validateUnitPrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Unit price is required';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid price';
    }
    if (parsed < 0) {
      return 'Unit price cannot be negative';
    }
    return null;
  }

  static String? validateDiscount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid discount';
    }
    if (parsed < 0) {
      return 'Discount cannot be negative';
    }
    return null;
  }

  static String? validateTaxRate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid tax rate';
    }
    if (parsed < 0 || parsed > 100) {
      return 'Tax rate must be between 0% and 100%';
    }
    return null;
  }

  static String? validateItems(List<Object> items) {
    if (items.isEmpty) {
      return 'Please add at least one line item to the invoice';
    }
    return null;
  }
}
