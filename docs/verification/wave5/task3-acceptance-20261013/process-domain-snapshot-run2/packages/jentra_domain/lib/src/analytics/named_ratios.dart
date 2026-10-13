import 'forecast_metrics.dart';

/// Named formula revision 1. The adapter must establish one complete publication
/// bundle with matching period, scope and currency before constructing this basis.
Map<String, ExactRatio> calculateNamedRatios(
  StatementBasis basis, {
  required BigInt revenue,
  required BigInt netProfit,
  required BigInt assets,
  required BigInt liabilities,
  required BigInt equity,
}) {
  if (!basis.complete || basis.formulaVersion != 1) {
    throw const FormatException('Complete reviewed statement basis required.');
  }
  return Map.unmodifiable({
    'net_profit_margin': calculateStatementRatio(
      basis,
      basis,
      netProfit,
      revenue,
    ),
    'liabilities_to_assets': calculateStatementRatio(
      basis,
      basis,
      liabilities,
      assets,
    ),
    'assets_to_equity': calculateStatementRatio(basis, basis, assets, equity),
  });
}
