import 'dart:typed_data';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

abstract interface class OperationalFileGateway {
  Future<SetupRecord> register(
    TenantContext scope,
    Map<String, Object?> metadata,
    String idempotencyKey,
  );
  Future<void> upload(SetupRecord staged, Uint8List bytes);
  Future<SetupRecord> complete(
    TenantContext scope,
    SetupRecord staged,
    String checksumSha256,
    String idempotencyKey,
  );
}

final class BusinessSetupOperationalFileGateway
    implements OperationalFileGateway {
  const BusinessSetupOperationalFileGateway(this.gateway);
  final SupabaseBusinessSetupGateway gateway;

  @override
  Future<SetupRecord> register(
    TenantContext scope,
    Map<String, Object?> metadata,
    String idempotencyKey,
  ) async {
    final result = await gateway.upsert(
      BusinessSetupResource.attachments,
      context: scope,
      payload: metadata,
      idempotencyKey: idempotencyKey,
    );
    if (result.isFailure) throw result.error!;
    return result.entity!;
  }

  @override
  Future<void> upload(SetupRecord staged, Uint8List bytes) =>
      gateway.uploadAttachment(attachment: staged, bytes: bytes);

  @override
  Future<SetupRecord> complete(
    TenantContext scope,
    SetupRecord staged,
    String checksumSha256,
    String idempotencyKey,
  ) async {
    final result = await gateway.completeAttachment(
      context: scope,
      attachment: staged,
      checksumSha256: checksumSha256,
      idempotencyKey: idempotencyKey,
    );
    if (result.isFailure) throw result.error!;
    return result.entity!;
  }
}
