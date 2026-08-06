abstract final class PaymentValidators {
  static String? validateAmount(String? value, double balanceDue) {
    if (value == null || value.trim().isEmpty) {
      return 'Payment amount is required';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a valid amount';
    }
    if (parsed <= 0) {
      return 'Amount must be greater than 0';
    }
    if (parsed > balanceDue + 0.001) {
      return 'Amount cannot exceed outstanding balance (\$${balanceDue.toStringAsFixed(2)})';
    }
    return null;
  }

  static String? validatePaymentMethod(String? method) {
    if (method == null || method.trim().isEmpty) {
      return 'Select a payment method';
    }
    return null;
  }
}
