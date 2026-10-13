import test from 'node:test';
import assert from 'node:assert/strict';
import { createProviderPgClientFactory, PROVIDER_CLIENT_ROLES } from './provider_pg_factory.mjs';

const bindings = { routerSha256:'a'.repeat(64), readOnlyDriverSha256:'b'.repeat(64),
  fixtureDriverSha256:'c'.repeat(64), dependencyManifestSha256:'d'.repeat(64) };
const options = (readOnlyPgClient, fixturePgClient) => ({ readOnlyPgClient, fixturePgClient,
  actualSourceBindings:bindings, independentlyReviewedSourceBindings:{...bindings} });

test('router creation does not construct drivers or perform their credential callbacks', () => {
  let calls=0;
  const PgClient = createProviderPgClientFactory(options(class {constructor(){calls++;}}, class {constructor(){calls++;}}));
  assert.equal(typeof PgClient,'function'); assert.equal(calls,0);
});
test('read-store role selects read-only driver and preserves config', () => {
  let passed;
  class Reader {constructor(config){passed=config; this.role='read';}}
  const Writer=class {constructor(){assert.fail('writer not expected');}};
  const PgClient=createProviderPgClientFactory(options(Reader,Writer));
  const config={application_name:PROVIDER_CLIENT_ROLES.readOnly, ssl:{rejectUnauthorized:true}};
  const client=new PgClient(config);
  assert.equal(client.role,'read'); assert.equal(passed,config);
});
test('membership fixture role selects the separate required driver', () => {
  class Reader {constructor(){assert.fail('reader not expected');}}
  class Writer {constructor(){this.role='fixture';}}
  const PgClient=createProviderPgClientFactory(options(Reader,Writer));
  assert.equal(new PgClient({application_name:PROVIDER_CLIENT_ROLES.membershipFixture}).role,'fixture');
});
test('missing or unreviewed roles fail before constructing either driver', () => {
  let calls=0;
  const PgClient=createProviderPgClientFactory(options(class {constructor(){calls++;}},class {constructor(){calls++;}}));
  for (const config of [undefined,{},Object.create({application_name:PROVIDER_CLIENT_ROLES.membershipFixture}),
    {application_name:'other'}, {application_name:PROVIDER_CLIENT_ROLES.membershipFixture+' '}]) {
    assert.throws(()=>new PgClient(config),error=>['PROVIDER_CLIENT_ROLE_REQUIRED','PROVIDER_CLIENT_ROLE_NOT_REVIEWED'].includes(error.code));
  }
  assert.equal(calls,0);
});
test('same read-only driver or missing writer cannot be promoted to full provider transport', () => {
  class Reader {}
  assert.throws(()=>createProviderPgClientFactory(options(Reader,Reader)),{code:'SEPARATE_REVIEWED_FIXTURE_DRIVER_REQUIRED'});
  assert.throws(()=>createProviderPgClientFactory(options(Reader,undefined)),{code:'SEPARATE_REVIEWED_FIXTURE_DRIVER_REQUIRED'});
});
test('source drift and added bindings fail closed', () => {
  class Reader {}; class Writer {};
  for (const reviewed of [{...bindings,fixtureDriverSha256:'e'.repeat(64)}, {...bindings,extra:'f'.repeat(64)},null]) {
    assert.throws(()=>createProviderPgClientFactory({...options(Reader,Writer),independentlyReviewedSourceBindings:reviewed}),
      {code:'EXACT_REVIEWED_PROVIDER_DRIVER_SOURCES_REQUIRED'});
  }
});
