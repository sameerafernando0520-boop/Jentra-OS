import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:jentra_domain/jentra_domain.dart';

/// Only call at a local encrypted persistence boundary, never for server errors.
DomainError localDraftStorageFailure(Object error) {
  if (error is DomainError) return error;
  final full = _full(error);
  return DomainError(
    code: 'LOCAL_STORAGE_FULL',
    message: full
        ? 'LOCAL_STORAGE_FULL · Secure local storage is full. Keep this editor '
              'open, free local space and retry saving. No local save was confirmed.'
        : 'LOCAL_STORAGE_FULL · Secure local storage is unavailable. Keep this '
              'editor open, restore secure storage and retry saving. No local '
              'save was confirmed.',
    fieldDetails: {'storage': full ? 'full' : 'unavailable'},
    retryable: true,
  );
}

/// Allows module-specific catches to retain the safe, actionable storage state.
bool isLocalDraftStorageFailure(Object error) =>
    error is DomainError && error.code == 'LOCAL_STORAGE_FULL';

bool _full(Object error) {
  if (error is SqliteException) return error.resultCode == 13;
  if (error is FileSystemException) {
    // Windows ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL and POSIX ENOSPC.
    return Platform.isWindows
        ? const {112, 39}.contains(error.osError?.errorCode)
        : error.osError?.errorCode == 28;
  }
  if (error is DriftWrappedException && error.cause != null) {
    return _full(error.cause!);
  }
  if (error is CouldNotRollBackException) {
    return _full(error.cause) || _full(error.exception);
  }
  if (isLocalDraftStorageFailure(error)) {
    return (error as DomainError).fieldDetails['storage'] == 'full';
  }
  return false;
}
