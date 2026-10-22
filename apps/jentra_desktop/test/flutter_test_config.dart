import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keep each run's pixel differences separate from preserved review evidence.
/// Golden loading, exact comparison and explicit updates retain SDK behavior.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    final output = Directory(
      '${Directory.current.path}/build/golden-failures/'
      '${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    goldenFileComparator = _RunComparator(
      comparator.basedir.resolve('_golden_session.dart'),
      output,
    );
  }
  await testMain();
}

class _RunComparator extends LocalFileComparator {
  _RunComparator(super.testFile, this.output);

  final Directory output;

  @override
  Future<String> generateFailureOutput(
    ComparisonResult result,
    Uri golden,
    Uri basedir, {
    String key = '',
  }) => super.generateFailureOutput(result, golden, output.uri, key: key);
}
