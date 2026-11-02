import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import '../../../packages/jentra_platform/test/support/browser_storage_scenarios.dart';

Future<void> main() async {
  final results = <Map<String, Object>>[];
  for (final scenario in browserStorageScenarios) {
    web.window.setProperty(
      'jentraStorageProbeProgress'.toJS,
      scenario.name.toJS,
    );
    try {
      await scenario.run();
      results.add({'name': scenario.name, 'passed': true});
    } on Object catch (error) {
      results.add({
        'name': scenario.name,
        'passed': false,
        'error': error.toString(),
      });
    }
  }
  final report = jsonEncode({
    'passed': results.every((result) => result['passed'] == true),
    'scenarios': results,
    'realLoginPerformed': false,
    'backendMutations': false,
  });
  final element = web.document.createElement('pre')..textContent = report;
  web.document.body!.append(element);
  web.window.setProperty('jentraStorageProbeResult'.toJS, report.toJS);
}
