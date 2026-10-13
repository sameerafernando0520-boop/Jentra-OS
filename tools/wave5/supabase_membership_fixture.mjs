import { PROJECT_ID, GuardError, requireGuard, isUuid, hashJson, immutableJson, reviewedExecutionContext, safeCode, freshId, hashBytes } from './runtime_contract.mjs';
import { snapshotPrivateDatabaseConfig, exactInteger } from './supabase_read_store.mjs';
import { requireBoundPreparationJournal } from './preparation_journal.mjs';

// Exact new synthetic memberships only. Preparation/restoration are admin fixture
// actions, never reported as genuine user commands or acceptance outcomes.
export const MEMBERSHIP_FIXTURE_SQL = immutableJson({
  subscription: `SELECT id,seats,version::text FROM billing.tenant_subscriptions WHERE tenant_id=$1::uuid FOR UPDATE`,
  memberships: `SELECT id,user_id,status,version::text FROM core.memberships
WHERE tenant_id=$1::uuid AND user_id=ANY($2::uuid[]) ORDER BY user_id FOR UPDATE`,
  assignments: `SELECT a.id,a.membership_id,a.role_id,a.legal_entity_id,a.branch_id
FROM core.role_assignments a JOIN core.memberships m ON m.id=a.membership_id AND m.tenant_id=a.tenant_id
WHERE m.tenant_id=$1::uuid AND m.user_id=ANY($2::uuid[]) ORDER BY a.id`,
  occupied: `SELECT count(*)::text AS occupied FROM core.memberships WHERE tenant_id=$1::uuid AND status IN ('active','invited')`,
  suspend: `UPDATE core.memberships SET status='suspended' WHERE tenant_id=$1::uuid AND id=$2::uuid AND user_id=$3::uuid
AND status='active' AND version=$4::bigint RETURNING id`,
  seats: `UPDATE billing.tenant_subscriptions SET seats=$2::integer WHERE tenant_id=$1::uuid AND id=$3::uuid
AND version=$4::bigint RETURNING id,seats,version::text`,
  restoreMember: `UPDATE core.memberships SET status='active' WHERE tenant_id=$1::uuid AND id=$2::uuid AND user_id=$3::uuid
AND status IN ('suspended','active') AND version=$4::bigint RETURNING id`,
  revokeExactUnused: `UPDATE core.invitations SET status='revoked' WHERE tenant_id=$1::uuid AND id=ANY($2::uuid[])
AND status='pending' AND invited_by=$3::uuid AND email=ANY($4::text[]) RETURNING id`,
});

export function createMembershipFixture({ executionContext, authIds, PgClient, databaseConfig, preparationJournal }) {
  const context = reviewedExecutionContext(executionContext), { review, plan } = context;
  const journal = requireBoundPreparationJournal(preparationJournal, context);
  const privateDatabase = snapshotPrivateDatabaseConfig(databaseConfig);
  const target = review.syntheticScopes.find(scope => scope.key === 'load-001');
  const actors = [authIds?.approver, authIds?.executor];
  requireGuard(typeof PgClient === 'function' && review.accounts.every(actor => isUuid(authIds?.[actor.label]))
    && Object.keys(authIds).length === 6 && new Set(Object.values(authIds)).size === 6, 'EXACT_REAL_AUTH_IDS_REQUIRED');
  let baseline = null, unknown = false, lastCaseId = null; const ownInvitations = new Set();
  const invitationEmails = review.accounts.filter(actor => ['approver', 'executor'].includes(actor.label)).map(actor => actor.email);
  async function transaction(operation, signal, action, caseId) {
    journal.assertHealthy();
    requireGuard(!unknown && !signal?.aborted, 'UNCERTAIN_MUTATION_REQUIRES_REVIEW');
    const preparedCase = plan.cases.find(value => value.caseId === caseId);
    requireGuard(preparedCase?.scopeKey === 'load-001' && ['seats', 'admissions'].includes(preparedCase.kind), 'REVIEWED_CASE_BINDING_REQUIRED');
    const client = new PgClient({ ...snapshotPrivateDatabaseConfig(privateDatabase), connectionTimeoutMillis: 25000,
      statement_timeout: 25000, application_name: 'jentra-wave5-exact-new-membership-fixture' });
    let connected = false, begun = false, committing = false;
    const transactionId = freshId(), write = async (name, values, journalAction) => journal.perform({ caseId, scopeKey: target.key,
      action: journalAction, intent: { transactionId, sqlName: name, querySha256: hashBytes(MEMBERSHIP_FIXTURE_SQL[name]), values },
      operation: async () => { requireGuard(!signal?.aborted, 'RUN_ABORTED');
        const result = await client.query(MEMBERSHIP_FIXTURE_SQL[name], values);
        return { rowCount: result.rowCount, rows: result.rows, commitPending: true }; } });
    try {
      await client.connect(); connected = true; await client.query('BEGIN'); begun = true;
      const result = await operation(client, { caseId, transactionId, write }); requireGuard(!signal?.aborted, 'RUN_ABORTED');
      await journal.perform({ caseId, scopeKey: target.key, action: 'membership-commit', intent: { transactionId, fixtureAction: action },
        operation: async () => { requireGuard(!signal?.aborted, 'RUN_ABORTED');
          committing = true; await client.query('COMMIT'); begun = false;
          return { transactionId, commitReturned: true, fixtureAction: action, result }; } });
      return result;
    } catch (error) {
      if (committing) unknown = true;
      if (connected && begun) { try { await client.query('ROLLBACK'); } catch {} }
      throw new GuardError(committing ? 'UNCERTAIN_MUTATION_REQUIRES_REVIEW' : error instanceof GuardError ? safeCode(error.code) : 'PROVIDER_FAILURE');
    } finally { try { await client.end(); } catch {} }
  }
  async function state(client) {
    const subscription = (await client.query(MEMBERSHIP_FIXTURE_SQL.subscription, [target.tenantId])).rows;
    const memberships = (await client.query(MEMBERSHIP_FIXTURE_SQL.memberships, [target.tenantId, actors])).rows;
    const assignments = (await client.query(MEMBERSHIP_FIXTURE_SQL.assignments, [target.tenantId, actors])).rows;
    requireGuard(subscription.length === 1 && memberships.length === 2 && memberships.every(row => isUuid(row.id)
      && actors.includes(row.user_id)) && new Set(memberships.map(row => row.user_id)).size === 2,
      'EXACT_RACE_PREPARATION_REQUIRED');
    return { subscription: subscription[0], memberships, assignments };
  }
  function validateOriginalRows(current) {
    requireGuard(baseline && current.memberships.every(row => baseline.memberships.some(original => original.id === row.id
      && original.user_id === row.user_id)) && hashJson(current.assignments) === hashJson(baseline.assignments), 'EXACT_RESTORATION_PROOF_REQUIRED');
  }
  return Object.freeze({ async prepare({ signal, caseId = plan.cases.find(value => value.kind === 'seats').caseId }) {
    lastCaseId = caseId;
    return transaction(async (client, tx) => {
      const current = await state(client);
      requireGuard(current.subscription.seats === 4 && current.memberships.every(row => row.status === 'active'), 'EXACT_RACE_PREPARATION_REQUIRED');
      requireGuard(current.assignments.length === 2 && new Set(current.assignments.map(row => row.role_id)).size === 1
        && current.assignments.every(row => row.legal_entity_id === target.entityId
        && row.branch_id === target.branchId && isUuid(row.role_id)), 'EXACT_RACE_PREPARATION_REQUIRED');
      if (!baseline) baseline = immutableJson(current); else validateOriginalRows(current);
      await journal.append({ caseId, scopeKey: target.key, action: 'membership-baseline', phase: 'checkpoint',
        details: { transactionId: tx.transactionId, original: baseline, currentBefore: current, fixtureAction: 'prepare' } });
      for (const row of current.memberships) {
        requireGuard((await tx.write('suspend', [target.tenantId, row.id, row.user_id, row.version], 'membership-suspend')).rowCount === 1,
          'EXACT_RACE_PREPARATION_REQUIRED');
      }
      const occupied = exactInteger((await client.query(MEMBERSHIP_FIXTURE_SQL.occupied, [target.tenantId])).rows[0]?.occupied);
      requireGuard(occupied === 2, 'EXACT_RACE_PREPARATION_REQUIRED');
      requireGuard((await tx.write('seats', [target.tenantId, 3, current.subscription.id, current.subscription.version], 'membership-cap')).rowCount === 1,
        'EXACT_RACE_PREPARATION_REQUIRED');
      if (ownInvitations.size) await tx.write('revokeExactUnused', [target.tenantId, [...ownInvitations], authIds['billing-admin'], invitationEmails], 'membership-revoke-unused');
      return { committed: true, scopeKey: target.key, originalRoleId: baseline.assignments[0].role_id,
        fixtureEvidenceSha256: hashJson({ action: 'prepare-exact-load-001-memberships', baseline, occupied, seats: 3 }) };
    }, signal, 'prepare', caseId);
  }, recordReturnedInvitation(id) {
    requireGuard(isUuid(id) && baseline && !unknown, 'EXACT_RACE_PREPARATION_REQUIRED'); ownInvitations.add(id);
  }, async restore({ signal, caseId = lastCaseId }) {
    return transaction(async (client, tx) => {
      const current = await state(client); validateOriginalRows(current);
      await journal.append({ caseId, scopeKey: target.key, action: 'membership-baseline', phase: 'checkpoint',
        details: { transactionId: tx.transactionId, original: baseline, currentBefore: current, fixtureAction: 'restore' } });
      // Seat trigger counts admissions. Raising to original4 precedes both reactivations.
      requireGuard((await tx.write('seats',
        [target.tenantId, 4, current.subscription.id, current.subscription.version], 'membership-cap')).rowCount === 1, 'EXACT_RESTORATION_PROOF_REQUIRED');
      for (const row of current.memberships) requireGuard((await tx.write('restoreMember',
        [target.tenantId, row.id, row.user_id, row.version], 'membership-reactivate')).rowCount === 1, 'EXACT_RESTORATION_PROOF_REQUIRED');
      if (ownInvitations.size) await tx.write('revokeExactUnused', [target.tenantId, [...ownInvitations], authIds['billing-admin'], invitationEmails], 'membership-revoke-unused');
      const restored = await state(client), occupied = exactInteger((await client.query(MEMBERSHIP_FIXTURE_SQL.occupied, [target.tenantId])).rows[0]?.occupied);
      validateOriginalRows(restored);
      requireGuard(restored.subscription.seats === 4 && occupied === 4 && restored.memberships.every(row => row.status === 'active'), 'EXACT_RESTORATION_PROOF_REQUIRED');
      return { evidenceSha256: hashJson({ action: 'restore-exact-memberships-and-cap', original: baseline, restored, occupied,
        versionRewound: false, immutableEvidenceDeleted: false }), committed: true, noAcceptanceChanges: true };
    }, signal, 'restore', caseId);
  } });
}
