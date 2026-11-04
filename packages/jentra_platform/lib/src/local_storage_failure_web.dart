import 'package:sqlite3/common.dart' show SqliteException;

bool platformStorageIsFull(Object error) =>
    error is SqliteException && error.resultCode == 13;
