import { PROJECT_ID, PROJECT_URL, requireGuard, isSha, freshId, hashJson, immutableJson, validateRuntimeReview, validatePlan } from './runtime_contract.mjs';
import { RACE_FIXTURES, INVALID_BOUNDARIES, FIXTURE_CAPS, RUNTIME_FIXTURE_BINDING } from './runtime_fixture_spec.mjs';
import { CASE_READ_RECIPES, validateProviderCalendar } from './supabase_runtime_provider.mjs';
import { READ_QUERY_SHA256, committedRecipeHash } from './supabase_read_store.mjs';
import { MEMBERSHIP_FIXTURE_SQL } from './supabase_membership_fixture.mjs';

// Pure preparation only. No secret access, I/O, private import, Auth, SQL or provider execution.
export function makeSupabaseProviderPlan({ review, calendar, sourceBindings, privateFactorySha256,
  postgresDriverSourceSha256, externalObserverSourceSha256, preparationJournalSourceSha256, requestsPerSecond = 20 }) {
  validateRuntimeReview(review); const actualCalendar = validateProviderCalendar(calendar);
  requireGuard([privateFactorySha256, postgresDriverSourceSha256, externalObserverSourceSha256, preparationJournalSourceSha256].every(isSha)
    && sourceBindings && ['supabase_http_transport.mjs', 'supabase_read_store.mjs', 'supabase_membership_fixture.mjs',
      'supabase_runtime_provider.mjs', 'runtime_fixture_spec.mjs', 'supabase_provider_plan.mjs', 'preparation_journal.mjs',
      'preparation_file_sink.mjs'].every(name => isSha(sourceBindings[name]))
    && preparationJournalSourceSha256 === sourceBindings['preparation_journal.mjs'],
    'EXACT_EXECUTION_HASHES_REQUIRED');
  const providerCalendarSha256 = hashJson(actualCalendar), moduleBindingsSha256 = hashJson(sourceBindings);
  const scopeDigestSha256 = hashJson(review.syntheticScopes);
  const prepareBinding = kind => ({ kind, sourceBindings, privateFactorySha256, providerCalendarSha256,
    exactMapping: RACE_FIXTURES[kind], scopeDigestSha256, operationScopeSha256: RUNTIME_FIXTURE_BINDING.operationScopeSha256,
    noExternalSend: true, newSyntheticScopesOnly: true });
  const plan = { kind: 'wave5-runtime-harness-plan', projectId: PROJECT_ID, url: PROJECT_URL, production: false, realBilling: false,
    runtimeBundleSha256: review.bundleSha256, warmupMs: 60000, measuredMs: 300000, maxRunMs: 900000,
    maximumTimedRequests: 100000, maxInflight: 2000, requestsPerSecond, providerCalendarSha256, postgresDriverSourceSha256,
    publicProviderSourceBindings: sourceBindings, publicProviderSourceBindingsSha256: moduleBindingsSha256,
    privateFactorySha256, preparationJournalSourceSha256, sameApprovedOperationScope: true, additionalOwnerDecisionRequired: false,
    cases: Object.entries(RACE_FIXTURES).map(([kind, definition]) => ({ kind, caseId: freshId(), scopeKey: definition.scopeKey,
      participants: definition.participants, noExternalSend: true, fixturePlanSha256: hashJson({ ...prepareBinding(kind), caps: FIXTURE_CAPS }),
      committedQuerySha256: committedRecipeHash(CASE_READ_RECIPES[kind]), preparationSha256: hashJson(prepareBinding(kind)),
      restorationSha256: hashJson({ kind, policy: definition.restoration,
        membershipSql: ['seats', 'admissions'].includes(kind) ? MEMBERSHIP_FIXTURE_SQL : null,
        preserveVersionsAndEvidence: true, noAcceptanceChanges: true, moduleBindingsSha256 }) })),
    boundaries: Object.entries(INVALID_BOUNDARIES).map(([kind, definition]) => ({ kind, scopeKey: 'runtime', caseId: freshId(),
      expectedCode: 'LIMIT_EXCEEDED', fixturePlanSha256: hashJson({ kind, definition, scopeDigestSha256, providerCalendarSha256, moduleBindingsSha256 }),
      committedQuerySha256: READ_QUERY_SHA256.scopeSnapshot, availability: definition.status })),
    loadCommittedQuerySha256: READ_QUERY_SHA256.loadLedgers,
    loadFixturePlanSha256: hashJson({ caps: FIXTURE_CAPS, providerCalendarSha256, scopeDigestSha256, moduleBindingsSha256,
      actualGenuineSessions: 2000, noSeedOrSendFromTimedWorkload: true }), externalObservationSourceSha256: externalObserverSourceSha256 };
  validatePlan(plan, review); return immutableJson(plan);
}
