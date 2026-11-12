import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { registerHooks } from 'node:module';

// The stock harness builds its own in-memory database and synthetic records.
// Add an export/restore check at its fixture boundary without changing the
// reviewed harness, migrations, or the production release.
assert.equal(process.argv.length, 2, 'This rehearsal takes no database or file targets.');
const runner = new URL('../../supabase/candidates/run-finance-opening-import-test.mjs', import.meta.url);
const original = await readFile(runner, 'utf8');
const sha256 = input => createHash('sha256').update(input).digest('hex');
const gitBlob = source => createHash('sha1')
  .update('blob ' + Buffer.byteLength(source) + '\0').update(source).digest('hex');
assert.equal(gitBlob(original.replaceAll('\r\n', '\n')), '42253f6a8e5d3135719dcb7454a49ff35ec1342a',
  'Opening runner changed; review the rehearsal fixture boundary before rerunning.');

const preflightPath = new URL('../../docs/development/accounting-cutover-restore-check.sql', import.meta.url);
const preflightSource = (await readFile(preflightPath, 'utf8')).replaceAll('\r\n', '\n');
const queryStart = preflightSource.indexOf('\nwith inputs(');
const queryEnd = preflightSource.lastIndexOf('\nrollback;');
const inputRow = 'values (null::uuid, null::uuid, null::date)';
assert.ok(queryStart > 0 && queryEnd > queryStart);
assert.equal(preflightSource.split(inputRow).length, 2);
const preflightQuery = preflightSource.slice(queryStart, queryEnd)
  .replace(inputRow, 'values ($1::uuid, $2::uuid, $3::date)');

async function captureAccounting(db, tenant, entity, cutoff) {
  await db.exec(preflightSource.slice(0, queryStart));
  try {
    const { rows: [row] } = await db.query(preflightQuery, [tenant, entity, cutoff]);
    return row.restore_evidence;
  } finally {
    await db.exec('rollback');
  }
}

const tables = [
  'auth.users', 'auth.sessions', 'core.tenants', 'core.memberships',
  'core.role_assignments', 'core.command_receipts',
  'finance.opening_batches', 'finance.opening_lines', 'finance.opening_reversals',
  'finance.opening_reversal_lines', 'finance.open_items', 'finance.open_item_allocations',
  'finance.allocation_reversals', 'finance.journal_entries', 'finance.journal_lines',
  'finance.fiscal_periods', 'finance.financial_reports', 'finance.control_reports',
  'finance.fx_revaluation_runs', 'inventory.stock_balances', 'storage.objects',
  'inventory.stock_valuations', 'assets.register', 'assets.books', 'assets.schedules',
  'assets.effects', 'audit.events',
];

async function fingerprint(db) {
  const snapshot = {};
  for (const table of tables) {
    const { rows: [entry] } = await db.query(`
      select count(*)::int as rows, encode(extensions.digest(
        coalesce(string_agg(to_jsonb(row)::text, E'\\n' order by to_jsonb(row)::text), ''),
        'sha256'), 'hex') as sha256 from ${table} as row
    `);
    snapshot[table] = entry;
  }
  const { rows: [totals] } = await db.query(`
    select coalesce(sum(base_debit),0)::text as debit, coalesce(sum(base_credit),0)::text as credit
    from finance.journal_lines
  `);
  const { rows: [residuals] } = await db.query(`
    select encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_array(
      id,finance.flow_residual(tenant_id,id,date '2026-09-19'),
      finance.flow_residual(tenant_id,id,date '2026-09-30'),
      finance.flow_residual(tenant_id,id,date '2026-10-02')
    ) order by id)::text,'[]'),'sha256'),'hex') as sha256 from finance.open_items
  `);
  return { tables: snapshot, journalTotals: totals, datedResidualsSha256: residuals.sha256 };
}

async function checkRestoredFacade(db) {
  const { rows: [scope] } = await db.query(`
    select b.tenant_id,b.legal_entity_id,b.branch_id,b.id as batch_id,b.created_by,r.id as reversal_id
    from finance.opening_batches b join finance.opening_reversals r on r.batch_id=b.id
    where r.status='posted' order by r.id limit 1
  `);
  assert.ok(scope);
  const args = [scope.tenant_id, scope.legal_entity_id, scope.branch_id];
  await db.transaction(async tx => {
    await setUserFor(tx, scope.created_by);
    const { rows: [batch] } = await tx.query(
      'select api.finance_opening_batch($1,$2,$3,$4) as entity', [...args, scope.batch_id]);
    const { rows: [reversal] } = await tx.query(
      'select api.finance_opening_reversal($1,$2,$3,$4) as entity', [...args, scope.reversal_id]);
    assert.equal(batch.entity.status, 'posted');
    assert.equal(batch.entity.reversal.id, scope.reversal_id);
    assert.equal(reversal.entity.status, 'posted');
    assert.equal(reversal.entity.lines.length, 2);
  });
  await assert.rejects(db.transaction(async tx => {
    await setUserFor(tx, '00000000-0000-4000-8000-000000000001');
    await tx.query('select api.finance_opening_reversal($1,$2,$3,$4)', [...args, scope.reversal_id]);
  }), { code: '42501' });
  return { scopedBatchAndReversalReadable: true, unauthorizedReadDenied: true };
}

async function setUserFor(tx, user) {
  await tx.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
    sub: user, aal: 'aal2', amr: [{ method: 'totp', timestamp: Math.floor(Date.now() / 1000) }],
  })]);
  await tx.exec('set local role authenticated');
}

async function verifyRestore({ db, PGlite, extensions, checks, reversalRehearsal, sources, excludedMigrations }) {
  assert.equal(checks.length, 100);
  await db.exec('reset role; set constraints all immediate; commit');
  const { rows: scopes } = await db.query(`
    select distinct b.tenant_id,b.legal_entity_id,t.slug from finance.opening_batches b
    join core.tenants t on t.id=b.tenant_id order by t.slug,b.legal_entity_id
  `);
  assert.ok(scopes.length >= 2, 'Capture every populated opening fixture entity.');
  const scope = scopes[0];
  const cutoffs = ['2026-09-14', '2026-09-19', '2026-09-30', '2026-10-02'];
  const accounting = [];
  for (const entityScope of scopes) {
    const snapshots = {};
    for (const date of cutoffs) {
      const evidence = await captureAccounting(db, entityScope.tenant_id, entityScope.legal_entity_id, date);
      assert.equal(evidence.status, 'captured');
      assert.equal(evidence.read_only, true);
      assert.equal(evidence.posted_ledger.base_debit, evidence.posted_ledger.base_credit);
      assert.equal(Object.keys(evidence.fingerprints).length, 20);
      snapshots[date] = evidence;
    }
    assert.ok(snapshots[cutoffs[0]].posted_ledger.line_count < snapshots[cutoffs.at(-1)].posted_ledger.line_count);
    accounting.push({ scope: entityScope, snapshots });
  }
  for (const inputs of [[null, null, null], [scope.tenant_id, randomUUID(), cutoffs[0]],
    [randomUUID(), scope.legal_entity_id, cutoffs[0]],
    [scope.tenant_id, scope.legal_entity_id, 'infinity']]) {
    assert.deepEqual(await captureAccounting(db, ...inputs), { status: 'invalid_or_inaccessible_scope_or_cutoff' });
  }
  await db.exec('begin read only');
  try {
    await assert.rejects(db.exec('delete from finance.open_items'), { code: '25006' });
  } finally {
    await db.exec('rollback');
  }
  await db.exec('set role authenticated');
  try {
    await assert.rejects(captureAccounting(db, scope.tenant_id, scope.legal_entity_id, cutoffs[0]), { code: '42501' });
  } finally {
    await db.exec('reset role');
  }
  const before = await fingerprint(db);
  for (const { snapshots } of accounting) {
    assert.ok(snapshots[cutoffs.at(-1)].fingerprints.journal_entries.row_count <
      before.tables['finance.journal_entries'].rows, 'Fixture must include journals outside each selected entity.');
    assert.notEqual(snapshots[cutoffs.at(-1)].posted_ledger.base_debit, before.journalTotals.debit,
      'Company preflight must exclude other-entity ledger amounts.');
  }
  assert.equal(before.journalTotals.debit, before.journalTotals.credit);
  assert.ok(before.tables['finance.journal_lines'].rows > 0);
  assert.ok(before.tables['finance.opening_reversal_lines'].rows > 0);
  const archive = await db.dumpDataDir('gzip');
  const bytes = new Uint8Array(await archive.arrayBuffer());
  assert.ok(bytes.length > 0);
  await db.close();
  const restored = await PGlite.create({ extensions, loadDataDir: new Blob([bytes]) });
  try {
    const after = await fingerprint(restored);
    assert.deepEqual(after, before);
    for (const { scope: entityScope, snapshots } of accounting) {
      for (const date of cutoffs) {
        assert.deepEqual(await captureAccounting(restored, entityScope.tenant_id, entityScope.legal_entity_id, date), snapshots[date]);
      }
    }
    const facade = await checkRestoredFacade(restored);
    console.log(JSON.stringify({
      status: 'Synthetic backup and isolated restore verified',
      openingFixtureCommit: 'e7d369ca',
      engine: 'PGlite 0.5.12 with simulated Auth and Storage',
      openingAndReversalChecks: checks.length,
      excludedMigrations,
      archive: { bytes: bytes.length, sha256: sha256(bytes), retained: false },
      restore: { matchedTableCount: tables.length, fingerprints: after, ...facade },
      accountingPreflight: { sha256: sha256(preflightSource), scopes: accounting,
        invalidScopesRejected: 4, writeDeniedInReadOnlySnapshot: true, unauthorizedRoleDenied: true,
        otherEntityJournalsExcluded: true, exactSourceAndRestoreMatch: true,
        coverage: 'Opening and reversal ledger fixtures are populated. Asset, bank-statement and Storage object-byte recovery requires separate populated acceptance; empty fingerprints establish only empty-table preservation.' },
      sourcePeriodStatus: reversalRehearsal.sourcePeriodStatus,
      candidateHashes: Object.fromEntries(Object.entries(sources).filter(([name]) => /finance_opening_/.test(name))),
      companyCutover: 'Awaiting approved company backup and signed Finance records',
    }, null, 2));
  } finally {
    await restored.close();
  }
}

const boundary = "  await db.exec('reset role; set constraints all immediate; rollback to savepoint opening_candidate');";
const boundaryIndex = original.indexOf(boundary);
assert.equal(original.split(boundary).length, 2);
const catchIndex = original.indexOf('\n} catch (error) {', boundaryIndex);
assert.ok(boundaryIndex > 0 && catchIndex > boundaryIndex);
const transformed = original.slice(0, boundaryIndex) +
  '  await verifyRestore({ db, PGlite, extensions: { pgcrypto, btree_gist }, checks, reversalRehearsal, sources, excludedMigrations });' +
  original.slice(catchIndex).replace('await db.close();', 'if (!db.closed) await db.close();');
const hooks = registerHooks({
  load(url, context, nextLoad) {
    if (url !== runner.href) return nextLoad(url, context);
    return {
      format: 'module',
      shortCircuit: true,
      source: `const verifyRestore = globalThis[Symbol.for('jentra.cutover.restore')];\n${transformed}`,
    };
  },
});
process.argv[2] = '--run-isolated-with-staff-mfa-and-reversal';
const initialArgvLength = 2;
const restoreHook = Symbol.for('jentra.cutover.restore');
assert.equal(globalThis[restoreHook], undefined);
globalThis[restoreHook] = verifyRestore;
try {
  await import(runner.href);
} finally {
  hooks.deregister();
  delete globalThis[restoreHook];
  process.argv.length = initialArgvLength;
}
