import '../application/ai_models.dart';

abstract final class BusinessContextBuilder {
  /// Generates context-aware, structured AI assistant responses based on company metrics
  /// with evidence citations and data freshness metadata.
  static String buildContextualResponse({
    required String userPrompt,
    required BusinessSummaryContext summary,
  }) {
    final query = userPrompt.toLowerCase();
    final String body;

    if (query.contains('revenue') || query.contains('sales') || query.contains('income')) {
      body = '''
Based on your current company records:
• Total Revenue: \$${summary.totalRevenue.toStringAsFixed(2)} across ${summary.invoicesCount} issued invoices.
• Outstanding Receivables: \$${summary.outstandingReceivables.toStringAsFixed(2)}.
Tip: Follow up on outstanding invoices to optimize cash flow!''';
    } else if (query.contains('cash') || query.contains('balance') || query.contains('money') || query.contains('bank')) {
      body = '''
Here is your current liquidity breakdown:
• Total Cash & Bank Balance: \$${summary.cashBalance.toStringAsFixed(2)}.
• Outstanding Uncollected Invoices: \$${summary.outstandingReceivables.toStringAsFixed(2)}.
Tip: Recording payments against open invoices automatically updates your cash balance and general ledger!''';
    } else if (query.contains('customer') || query.contains('client')) {
      body = '''
Your business currently has ${summary.customersCount} active customer(s) registered in your CRM directory.
You can create new customer accounts or view order history in the Customers module!''';
    } else if (query.contains('product') || query.contains('stock') || query.contains('inventory')) {
      body = '''
Your catalog contains ${summary.productsCount} active product(s).
You can track stock balances, manage warehouses, and update pricing in the Inventory module!''';
    } else if (query.contains('summary') || query.contains('health') || query.contains('status') || query.contains('overview')) {
      body = '''
Here is your Jentra OS AI Business Summary:
• Revenue: \$${summary.totalRevenue.toStringAsFixed(2)}
• Cash Balance: \$${summary.cashBalance.toStringAsFixed(2)}
• Outstanding Receivables: \$${summary.outstandingReceivables.toStringAsFixed(2)}
• Active Customers: ${summary.customersCount}
• Active Products: ${summary.productsCount}''';
    } else {
      body = '''
I have analyzed your company context:
• ${summary.invoicesCount} Invoices | \$${summary.totalRevenue.toStringAsFixed(2)} Total Revenue
• Cash Balance: \$${summary.cashBalance.toStringAsFixed(2)}
• Outstanding Receivables: \$${summary.outstandingReceivables.toStringAsFixed(2)}

How can I help you analyze your sales, customers, inventory, or cash flow today?''';
    }

    final citation = '\n\n[Evidence: get_company_business_summary | Data Freshness: Live Context]';
    return '$body$citation';
  }
}
