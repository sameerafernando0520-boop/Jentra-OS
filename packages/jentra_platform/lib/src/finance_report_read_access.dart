import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Only read RPCs: posting, export registration and correction precedence stays
// with its existing command adapter.
DomainError? financeReportReadDenial(String rpc, PostgrestException failure) {
  if (!const {
    'control_reconciliation_reports',
    'control_reconciliation_report_page',
    'period_governance_options',
    'financial_statement_reports',
    'financial_statement_page',
    'cash_flow_mapping_options',
    'manual_journal_options',
    'manual_journal_detail',
    'manual_journal_tax_options',
    'manual_journal_tax_controls',
    'exchange_revaluation_options',
    'exchange_revaluation_detail',
    'budget_options',
    'budget_variance_reports',
    'budget_variance_page',
    'tax_summary_reports',
    'tax_summary_page',
    'tax_control_page',
    'close_control_reviews',
    'close_control_review_page',
    'report_export_preview',
    'inventory_valuation_reports',
    'inventory_valuation_report_page',
  }.contains(rpc)) {
    return null;
  }
  final code = switch (failure.message) {
    'PERMISSION_DENIED' => 'PERMISSION_DENIED',
    'ACCESS_DENIED' => 'ACCESS_DENIED',
    'MFA_REQUIRED' || 'RECENT_MFA_REQUIRED' => 'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED' => 'AUTHENTICATION_REQUIRED',
    _ =>
      const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(failure.code)
          ? 'AUTHENTICATION_REQUIRED'
          : null,
  };
  if (code == null) return null;
  return DomainError(
    code: code,
    message: switch (code) {
      'MFA_REQUIRED' =>
        'Complete recent MFA in account security, then verify report access.',
      'AUTHENTICATION_REQUIRED' =>
        'Restore your authenticated session, then verify report access.',
      _ => 'Current report access is required in the selected scope.',
    },
  );
}
