import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_assurance_gateway.dart';

/// Active members to choose people from by name (A14 `api.assurance_people`).
abstract interface class AssurancePeopleGateway {
  Future<AssurancePeople> people(TenantContext scope);
}

final class SupabaseAssurancePeopleGateway implements AssurancePeopleGateway {
  SupabaseAssurancePeopleGateway(this.client);
  final SupabaseClient client;

  @override
  Future<AssurancePeople> people(TenantContext s) async {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    final Object? r;
    try {
      r = await client
          .schema('api')
          .rpc(
            'assurance_people',
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
            },
          );
    } on PostgrestException catch (e) {
      throw SupabaseAssuranceGateway.assuranceDenial(e);
    }
    if (r is! Map) throw const FormatException('Invalid people response.');
    return AssurancePeople.fromJson(r.cast<String, Object?>());
  }
}
