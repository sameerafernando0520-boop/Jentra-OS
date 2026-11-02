@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'support/browser_storage_scenarios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in browserStorageScenarios) {
    test(scenario.name, scenario.run);
  }
}
