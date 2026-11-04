import 'dart:io';
import 'package:sqlite3/common.dart' show SqliteException;

bool platformStorageIsFull(Object error) {
  if (error is SqliteException) return error.resultCode == 13;
  if (error is FileSystemException) {
    return Platform.isWindows
        ? const {112, 39}.contains(error.osError?.errorCode)
        : error.osError?.errorCode == 28;
  }
  return false;
}
