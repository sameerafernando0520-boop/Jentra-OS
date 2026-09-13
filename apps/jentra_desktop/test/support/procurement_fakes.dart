import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class Gateway implements ProcurementGateway {
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  bool uncertain = true, failRefresh = false;
  @override
  Future<Map<String, Object?>> source(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry original command.',
      );
    }
    return {'id': command.payload['id'], 'status': 'issued', 'version': 2};
  }

  @override
  Future<CursorPage<Map<String, Object?>>> rfqs(
    TenantContext scope, {
    String? after,
  }) async {
    if (failRefresh) {
      throw const DomainError(
        code: 'NETWORK_ERROR',
        message: 'Refresh failed.',
      );
    }
    return CursorPage(items: [], limit: 50);
  }

  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async => {'items': [], 'base_currency': 'LKR'};
  @override
  Future<CursorPage<Map<String, Object?>>> page(
    TenantContext scope, {
    String? after,
  }) => rfqs(scope, after: after);
  @override
  Future<List<Map<String, Object?>>> units(TenantContext scope) async => [];
  @override
  Future<Map<String, Object?>> save(CommandEnvelope<Map<String, Object?>> c) =>
      source(c);
  @override
  Future<Map<String, Object?>> transition(
    CommandEnvelope<Map<String, Object?>> c,
  ) => source(c);
}
