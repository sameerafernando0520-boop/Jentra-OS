import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openLocalDatabase() => LazyDatabase(() async {
  final directory = await getApplicationSupportDirectory();
  final file = File(p.join(directory.path, 'jentra', 'drafts.sqlite'));
  await file.parent.create(recursive: true);
  return NativeDatabase.createInBackground(file);
});
