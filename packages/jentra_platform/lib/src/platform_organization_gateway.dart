import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class PlatformOrganizationFailure implements Exception {
  const PlatformOrganizationFailure(this.code);

  final String code;
}

final class PlatformOrganizationGateway {
  const PlatformOrganizationGateway(this._client);

  final SupabaseClient _client;

  Future<T> rpc<T>(
    String function, [
    Map<String, Object?> parameters = const {},
  ]) async {
    try {
      return await _client.schema('api').rpc<T>(function, params: parameters);
    } on PostgrestException catch (error) {
      throw PlatformOrganizationFailure(switch (error.code) {
        '23505' => 'DUPLICATE_RECORD',
        'PGRST202' => 'PGRST202',
        _ => error.message,
      });
    }
  }

  Future<Object?> identity(String action, Map<String, Object?> fields) =>
      _invoke('org-identity', {'action': action, ...fields});

  Future<Object?> lifecycle(String action, Map<String, Object?> fields) =>
      _invoke('platform-organization-lifecycle', {'action': action, ...fields});

  Future<Object?> systemOwnerVerification(
    String action,
    Map<String, Object?> fields,
  ) => identity('system_owner_$action', fields);

  Future<Object?> _invoke(String function, Map<String, Object?> body) async {
    try {
      return (await _client.functions.invoke(function, body: body)).data;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] ?? details['code'] : null;
      throw PlatformOrganizationFailure(
        code is String ? code : 'REQUEST_FAILED',
      );
    }
  }

  Future<bool> downloadArchive({
    required String tenantId,
    required String backupId,
    required String organizationSlug,
    required String expectedSha256,
  }) async {
    final location = await getSaveLocation(
      suggestedName: '$organizationSlug-$backupId.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Organization archive', extensions: ['json']),
      ],
    );
    if (location == null) return false;
    final bytes = await lifecycle('download', {
      'tenant_id': tenantId,
      'backup_id': backupId,
    });
    if (bytes is! Uint8List) {
      throw const PlatformOrganizationFailure('INVALID_BACKUP_CONTENT');
    }
    final digest = await Sha256().hash(bytes);
    final actual = digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    if (actual != expectedSha256) {
      throw const PlatformOrganizationFailure('BACKUP_CHECKSUM_MISMATCH');
    }
    await XFile.fromData(
      bytes,
      mimeType: 'application/json',
    ).saveTo(location.path);
    return true;
  }
}
