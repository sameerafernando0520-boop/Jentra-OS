import { isSha, hashJson } from '../../../../tools/wave5/runtime_contract.mjs';
import { PrivatePgError } from './postgres_transport.mjs';

const must = (value, code) => { if (!value) throw new PrivatePgError(code); };
export const PROVIDER_CLIENT_ROLES = Object.freeze({
  readOnly: 'jentra-wave5-readonly-verification',
  membershipFixture: 'jentra-wave5-exact-new-membership-fixture',
});

// The current public provider uses one constructor for two different roles.
// This router does not implement or authorize a fixture writer. The live owner
// must supply an independently source-reviewed exact-SQL fixture driver.
// Construction performs no credential read, network request or SQL query.
export function createProviderPgClientFactory({ readOnlyPgClient, fixturePgClient,
  actualSourceBindings, independentlyReviewedSourceBindings }) {
  must(typeof readOnlyPgClient === 'function' && typeof fixturePgClient === 'function'
    && readOnlyPgClient !== fixturePgClient, 'SEPARATE_REVIEWED_FIXTURE_DRIVER_REQUIRED');
  const keys = ['routerSha256', 'readOnlyDriverSha256', 'fixtureDriverSha256', 'dependencyManifestSha256'];
  const exact = value => value && Object.keys(value).length === keys.length && keys.every(key => isSha(value[key]));
  must(exact(actualSourceBindings) && exact(independentlyReviewedSourceBindings)
    && hashJson(actualSourceBindings) === hashJson(independentlyReviewedSourceBindings),
    'EXACT_REVIEWED_PROVIDER_DRIVER_SOURCES_REQUIRED');
  return class ProviderPgClient {
    constructor(config) {
      must(config && typeof config === 'object', 'PROVIDER_CLIENT_ROLE_REQUIRED');
      const role = Object.hasOwn(config, 'application_name') ? config.application_name : null;
      const Delegate = role === PROVIDER_CLIENT_ROLES.readOnly ? readOnlyPgClient
        : role === PROVIDER_CLIENT_ROLES.membershipFixture ? fixturePgClient : null;
      must(Delegate, 'PROVIDER_CLIENT_ROLE_NOT_REVIEWED');
      // Preserve database target/TLS options for the chosen driver's own validation.
      // Delegates, not this router, own connect/query/end and cancellation safety.
      return new Delegate(config);
    }
  };
}
