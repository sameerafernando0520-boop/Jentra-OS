// Offline preparation only. This module never opens a database connection.
// Reviewed files remain frozen; every output uses exclusive creation.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const reviewPath = 'docs/verification/wave5/complete-app-runtime-review-20261010-r5.json';
const reviewFileHash = 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3';
const bundleHash = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
const scopeHash = 'fcdab89d242dc578793eba1d520ea0251699b70b7730c02aea94232805286e63';
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const lf = value => value.replace(/\r\n/g, '\n');
const sqlString = value => "'" + value.replace(/'/g, "''") + "'";
const exactRead = (root, relative) => fs.readFileSync(path.join(root, relative));

// Split only at top-level semicolons. Dollar bodies, strings, quoted identifiers
// and nested block comments are kept intact. This is a narrow source inventory,
// not a general PostgreSQL parser or a SQL execution mechanism.
export function splitSqlStatements(source) {
  const output = [];
  let start = 0, quote = null, dollar = null, block = 0, lineComment = false;
  for (let i = 0; i < source.length; i++) {
    const c = source[i], next = source[i + 1];
    if (lineComment) { if (c === '\n') lineComment = false; continue; }
    if (block) {
      if (c === '/' && next === '*') { block++; i++; }
      else if (c === '*' && next === '/') { block--; i++; }
      continue;
    }
    if (dollar) {
      if (source.startsWith(dollar, i)) { i += dollar.length - 1; dollar = null; }
      continue;
    }
    if (quote) {
      if (c === quote && next === quote) { i++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '-' && next === '-') { lineComment = true; i++; continue; }
    if (c === '/' && next === '*') { block = 1; i++; continue; }
    if (c === "'" || c === '"') { quote = c; continue; }
    if (c === '$') {
      const token = /^(?:\$\$|\$[a-z_][a-z0-9_]*\$)/i.exec(source.slice(i));
      if (token) { dollar = token[0]; i += dollar.length - 1; continue; }
    }
    if (c === ';') { output.push(source.slice(start, i + 1)); start = i + 1; }
  }
  assert.equal(quote, null, 'Unterminated source quote');
  assert.equal(dollar, null, 'Unterminated source dollar body');
  assert.equal(block, 0, 'Unterminated source block comment');
  if (source.slice(start).trim()) output.push(source.slice(start));
  return output;
}

function withoutLeadingComments(statement) {
  let current = statement.trimStart();
  for (;;) {
    if (current.startsWith('--')) {
      const end = current.indexOf('\n');
      if (end === -1) return '';
      current = current.slice(end + 1).trimStart();
    } else if (current.startsWith('/*')) {
      const end = current.indexOf('*/');
      assert.notEqual(end, -1);
      current = current.slice(end + 2).trimStart();
    } else return current;
  }
}

function parameterTypes(argumentsText) {
  // A comma in ARRAY defaults or type modifiers is not an argument separator.
  const segments = [];
  let start = 0, nesting = 0, quote = false;
  for (let i = 0; i < argumentsText.length; i++) {
    const c = argumentsText[i];
    if (quote) {
      if (c === "'" && argumentsText[i + 1] === "'") { i++; continue; }
      if (c === "'") quote = false;
      continue;
    }
    if (c === "'") quote = true;
    else if (c === '(' || c === '[') nesting++;
    else if (c === ')' || c === ']') nesting--;
    else if (c === ',' && nesting === 0) { segments.push(argumentsText.slice(start, i)); start = i + 1; }
  }
  if (argumentsText.slice(start).trim()) segments.push(argumentsText.slice(start));
  return segments.map(segment => {
    const definition = segment.replace(/\s+(?:default\b|=)[\s\S]*$/i, '').trim();
    const match = /^(?:in\s+)?[a-z_][a-z0-9_]*\s+((?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*(?:\[\])?)$/i.exec(definition);
    assert.ok(match, 'Unsupported reviewed function parameter: ' + definition);
    return match[1].toLowerCase();
  }).join(',');
}

const schemas = ['analytics', 'api', 'assets', 'core', 'expense_private', 'finance', 'intelligence_control', 'inventory', 'people', 'people_payroll', 'procurement', 'projects', 'sales', 'service'];
const historical = [
  { path: 'docs/verification/wave5/complete-app-candidate-20261009.sql', sha256: '3a4471dee274816d80fb2c40cad9e456f707ff501a03d9621df08d6c70ee2a66', assertions: 105, directR5Artifact: true },
  { path: 'docs/verification/wave5/complete-app-bootstrap-probe-20261009.sql', sha256: '04211f203e3429583ed187afcdd2b3deca3f1d3627669ab8fb7f3cd633864930', assertions: 25, directR5Artifact: true },
  { path: 'docs/verification/wave5/installed-strict-checks-20261008.sql', sha256: 'c089e95598c507b13c0dfda93f77330813274441efa694d68ad7a359e6834ab4', assertions: 126, directR5Artifact: false },
  { path: 'docs/verification/wave5/complete-live-preflight-20261010-r2.sql', sha256: 'cf886dbb2fac359b530626b50d99312c14b5398a7d620b22100852154594e250', assertions: null, directR5Artifact: true },
];

const grantChecks = [
  ['api.wave5_runtime_worker(uuid,text,jsonb)', 'authenticated', false, 'Reviewed 105 probe: clients cannot call trusted runtime worker'],
  ['api.wave5_runtime_worker(uuid,text,jsonb)', 'service_role', true, 'Reviewed 105 probe: trusted service can call scoped runtime worker'],
  ['api.wave5_edge_control(uuid,text,jsonb)', 'authenticated', false, 'Reviewed 105 probe: clients cannot access Edge control or secrets'],
  ['api.wave5_edge_control(uuid,text,jsonb)', 'service_role', true, 'Reviewed 105 probe: trusted runtime can access scoped Edge control'],
  ['intelligence_control.edge_schedule_tick(text)', 'service_role', false, 'Reviewed 105 probe: only database-owned scheduler can issue a tick'],
  ['analytics.cash_source_rows(uuid,uuid,uuid,text,date,timestamptz)', 'authenticated', false, 'Reviewed 105 probe: private cash source adapter is not client callable'],
  ['api.get_pipeline_forecast(uuid,uuid,uuid,uuid)', 'authenticated', true, 'Current fixture source contract'],
  ['api.get_wave5_subscription(uuid)', 'authenticated', true, 'Current fixture source contract'],
  ['api.freeze_pipeline_forecast(uuid,uuid,uuid,uuid,uuid,timestamptz,date,date)', 'authenticated', true, 'Current fixture source contract'],
  ['api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz)', 'authenticated', true, 'Current fixture source contract'],
  ['api.accept_invitation(text)', 'authenticated', true, 'Current fixture source contract; installed baseline function'],
  ['api.wave5_reserve_usage(uuid,uuid,text,timestamptz,timestamptz,text)', 'service_role', true, 'Current fixture source contract; installed baseline function'],
  ['api.apply_synthetic_subscription(uuid,uuid)', 'service_role', true, 'Current fixture source contract; installed baseline function'],
  ['api.wave5_proposal_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb)', 'authenticated', true, 'Current fixture source contract; installed baseline function'],
  ['api.wave5_runtime_delivery_worker(uuid,text,jsonb)', 'service_role', true, 'Current fixture source contract'],
  ['api.schedule_synthetic_subscription(uuid,uuid,uuid,timestamptz,bigint,text,integer,timestamptz,timestamptz)', 'authenticated', true, 'Current fixture source contract; installed baseline function'],
  ['api.create_invitation(uuid,text,uuid,uuid,uuid,integer)', 'authenticated', true, 'Current fixture source contract; installed baseline function'],
  ['api.wave5_integration_manage(uuid,uuid,uuid,text,uuid,bigint,jsonb)', 'authenticated', true, 'Current fixture source contract'],
];

const reviewedRls = [
  'analytics.cash_date_proposals', 'analytics.cash_date_decisions',
  'intelligence_control.runtime_worker_scopes', 'intelligence_control.runtime_operator_authorities',
  'intelligence_control.edge_authorities', 'intelligence_control.edge_key_refs', 'intelligence_control.edge_ticks',
  'intelligence_control.edge_tick_outcomes', 'intelligence_control.edge_receiver_receipts',
  'analytics.pipeline_forecasts', 'intelligence_control.health_probes', 'intelligence_control.operator_access_events',
  'intelligence_control.operator_tenant_grants', 'intelligence_control.operators', 'intelligence_control.proposal_decisions',
  'intelligence_control.proposal_executions', 'intelligence_control.proposals', 'intelligence_control.quota_periods',
  'intelligence_control.subscription_activations', 'intelligence_control.subscription_revisions', 'intelligence_control.synthetic_tenants',
  'intelligence_control.usage_corrections', 'intelligence_control.usage_events', 'intelligence_control.usage_reservations',
];

export function prepareInstalledVerification(root) {
  const bytes = exactRead(root, reviewPath);
  assert.equal(digest(bytes), reviewFileHash, 'Frozen review drift');
  const review = JSON.parse(bytes);
  assert.equal(review.projectId, 'xpdoufauvrbdmxgngetv');
  assert.equal(review.bundleSha256, bundleHash);
  assert.equal(review.migrations.length, 71);
  const artifacts = new Map(review.artifacts.map(item => [item.path, item.sha256]));
  const bindings = [];
  const definitions = new Map();
  const tables = new Map();
  const forced = new Set(reviewedRls);
  const transforms = [];
  const grants = [];
  const dynamicFunctionStatements = [];
  const renames = [];
  const unknownRenames = [];
  for (let i = 0; i < review.migrations.length; i++) {
    const migration = review.migrations[i];
    assert.equal(migration.order, i + 1);
    const raw = exactRead(root, migration.path);
    assert.equal(digest(raw), migration.sha256, 'Reviewed migration drift: ' + migration.path);
    const source = lf(raw.toString('utf8'));
    bindings.push({ path: migration.path, sha256: migration.sha256, bytes: raw.length, order: migration.order, directR5Artifact: artifacts.get(migration.path) === migration.sha256 });
    const statements = splitSqlStatements(source).map(withoutLeadingComments).filter(Boolean);
    for (const statement of statements) {
      const rename = /^alter\s+function\s+([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)\s*\(([^)]*)\)\s+(rename\s+to|set\s+schema)\s+([a-z_][a-z0-9_]*)\s*;/i.exec(statement);
      if (rename) {
        const argumentsTypes = rename[2].split(',').map(value => value.trim().toLowerCase()).join(',');
        const before = rename[1].toLowerCase() + '(' + argumentsTypes + ')';
        const after = /^set\s+schema$/i.test(rename[3])
          ? rename[4].toLowerCase() + '.' + rename[1].split('.')[1].toLowerCase() + '(' + argumentsTypes + ')'
          : before.slice(0, before.indexOf('.') + 1) + rename[4].toLowerCase() + '(' + argumentsTypes + ')';
        const previous = definitions.get(before);
        const renameEvidence = { before, after, source: migration.path, sourceSha256: migration.sha256, order: migration.order, bodyMappedFromReviewedPendingSource: !!previous };
        renames.push(renameEvidence);
        if (previous) {
          assert.equal(definitions.has(after), false, 'Reviewed rename destination already exists: ' + after);
          definitions.set(after, { ...previous, signature: after,
            renames: [...(previous.renames ?? []), renameEvidence],
            derivation: previous.derivation + '; exact reviewed function rename preserves literal body' });
          definitions.delete(before);
        } else unknownRenames.push(renameEvidence);
      } else if (/^alter\s+function\b/i.test(statement)) {
        const volatility = /^alter\s+function\s+([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)\s*\(([^)]*)\)\s+(stable|immutable|volatile)\s*;/i.exec(statement);
        assert.ok(volatility, 'Unsupported reviewed ALTER FUNCTION inventory: ' + migration.path);
        const signature = volatility[1].toLowerCase() + '(' + volatility[2].split(',').map(value => value.trim().toLowerCase()).join(',') + ')';
        const previous = definitions.get(signature);
        assert.ok(previous, 'Volatility source prerequisite absent: ' + signature);
        previous.volatility = volatility[3].slice(0, 1).toLowerCase();
        previous.metadataTransforms = [...(previous.metadataTransforms ?? []), { source: migration.path, sourceSha256: migration.sha256, order: migration.order, volatility: previous.volatility }];
      }
      if (/^drop\s+(?:function|table)\b/i.test(statement)) {
        assert.fail('Unmapped reviewed DROP inventory: ' + migration.path);
      }
      const header = /^create\s+(?:or\s+replace\s+)?function\s+([a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\)\s+returns\s/i.exec(statement);
      if (header) {
        const signature = header[1].toLowerCase() + '(' + parameterTypes(header[2]) + ')';
        const quoted = /\bas\s+(\$\$|\$[a-z_][a-z0-9_]*\$)/i.exec(statement.slice(header[0].length));
        assert.ok(quoted, 'Non-dollar reviewed body: ' + signature);
        const beginning = header[0].length + quoted.index + quoted[0].length;
        const ending = statement.indexOf(quoted[1], beginning);
        assert.notEqual(ending, -1, 'Missing body terminator: ' + signature);
        const body = statement.slice(beginning, ending);
        const language = /\blanguage\s+([a-z_]+)/i.exec(statement.slice(0, beginning));
        assert.ok(language, 'Missing reviewed language: ' + signature);
        definitions.set(signature, { signature, source: migration.path, sourceSha256: migration.sha256, order: migration.order,
          bodyLfSha256: digest(body), body, securityDefiner: /\bsecurity\s+definer\b/i.test(statement.slice(0, beginning)), language: language[1].toLowerCase(),
          volatility: /\bimmutable\b/i.test(statement.slice(header[0].length, beginning)) ? 'i' : /\bstable\b/i.test(statement.slice(header[0].length, beginning)) ? 's' : 'v',
          derivation: 'final top-level literal CREATE FUNCTION body with CRLF-to-LF only' });
      } else if (/^create\s+(?:or\s+replace\s+)?function\b/i.test(statement)) {
        assert.fail('Uninventoried top-level reviewed function: ' + migration.path);
      }
      const table = /^create\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_]+\.[a-z_][a-z0-9_]*)\b/i.exec(statement);
      if (table) tables.set(table[1], { name: table[1], source: migration.path, sourceSha256: migration.sha256, order: migration.order });
      const force = /^alter\s+table\s+([a-z_]+\.[a-z_][a-z0-9_]*)\s+force\s+row\s+level\s+security\s*;/i.exec(statement);
      if (force) forced.add(force[1]);
      if (/^(?:grant\s+execute|revoke\s+(?:all|execute))\s+on\s+function\b/i.test(statement)) {
        grants.push({ source: migration.path, order: migration.order, statementSha256: digest(statement), statement });
      }
      if (/^do\b/i.test(statement) && /execute\s+format\(['"]create\s+function/i.test(statement)) dynamicFunctionStatements.push({ source: migration.path, order: migration.order, statementSha256: digest(statement) });
    }
    // The exact reviewed return migration patches two bodies with guarded literal
    // replacements. Account for these in serial order, without executing SQL.
    if (migration.path === 'supabase/migrations/20260915002000_procurement_purchase_returns.sql') {
      const patches = [
        { signature: 'procurement.normalize_bill(uuid,uuid,uuid,jsonb)', old: 'v_available:=v_rl.accepted_quantity-v_already;', replacement: "v_already:=v_already+coalesce((select sum(quantity) from procurement.purchase_return_lines where receipt_line_id=v_rl.id and bill_line_id is null),0);\n   v_available:=v_rl.accepted_quantity-v_already;" },
        { signature: 'api.reverse_goods_receipt(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)', old: 'if exists(select 1 from procurement.purchase_order_lines l join procurement.goods_receipt_lines r', replacement: "if exists(select 1 from procurement.purchase_return_lines l join procurement.goods_receipt_lines r on r.id=l.receipt_line_id where r.receipt_id=v_id) then\n raise exception using errcode='55000',message='RETURNED_RECEIPT_CANNOT_REVERSE';end if;\n if exists(select 1 from procurement.purchase_order_lines l join procurement.goods_receipt_lines r" },
      ];
      for (const patch of patches) {
        assert.ok(source.includes('v_old:=' + sqlString(patch.old)), 'Reviewed transform match drift');
        assert.ok(source.includes('$s$' + patch.replacement + '$s$'), 'Reviewed transform replacement drift');
        const row = definitions.get(patch.signature);
        assert.ok(row, 'Transform prerequisite absent: ' + patch.signature);
        assert.ok(row.body.includes(patch.old), 'Transform source no longer matches: ' + patch.signature);
        row.body = row.body.split(patch.old).join(patch.replacement);
        row.bodyLfSha256 = digest(row.body);
        row.transforms = [...(row.transforms ?? []), { source: migration.path, sourceSha256: migration.sha256, order: migration.order, oldSha256: digest(patch.old), replacementSha256: digest(patch.replacement) }];
        row.derivation = 'literal body plus exact guarded source replacements, CRLF-to-LF only';
        transforms.push({ signature: patch.signature, source: migration.path, sourceSha256: migration.sha256, order: migration.order });
      }
    }
    // One exact DO loop creates three SQL wrappers. No other dynamic function
    // generator is accepted by this narrow offline inventory.
    if (migration.path === 'supabase/migrations/20260913007000_procurement_supplier_bills.sql') {
      assert.ok(source.includes("('post_supplier_bill','post'),('approve_supplier_bill_match','approve'),('cancel_supplier_bill','cancel')"));
      assert.ok(source.includes('$fn$select procurement.bill_action(%L,p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version)$fn$'));
      for (const [name, action] of [['post_supplier_bill', 'post'], ['approve_supplier_bill_match', 'approve'], ['cancel_supplier_bill', 'cancel']]) {
        const signature = 'api.' + name + '(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)';
        const body = 'select procurement.bill_action(' + sqlString(action) + ',p_tenant_id,p_legal_entity_id,p_branch_id,p_command_id,p_idempotency_key,p_client_timestamp,p_payload,p_expected_entity_version)';
        definitions.set(signature, { signature, source: migration.path, sourceSha256: migration.sha256, order: migration.order, body, bodyLfSha256: digest(body), securityDefiner: true, language: 'sql', volatility: 'v', derivation: 'exact three-row reviewed DO-loop format expansion; no SQL execution' });
      }
    }
  }
  assert.equal(dynamicFunctionStatements.length, 1, 'Unmapped dynamic reviewed function generator');
  const functionInventory = [...definitions.values()].map(({ body, ...row }) => row).sort((a, b) => a.signature.localeCompare(b.signature));
  assert.ok(functionInventory.length > 400);
  const historicalInventory = historical.map(row => {
    const raw = exactRead(root, row.path), source = raw.toString('utf8'), lines = source.split(/\r?\n/);
    assert.equal(digest(raw), row.sha256, 'Historical SQL drift: ' + row.path);
    if (row.directR5Artifact) assert.equal(artifacts.get(row.path), row.sha256);
    const authMutations = lines.flatMap((line, index) => /\b(?:insert\s+into|update|delete\s+from)\s+auth\./i.test(line) ? [index + 1] : []);
    return { ...row, bytes: raw.length, authMutationLines: authMutations,
      postinstallExecution: authMutations.length ? 'prohibited unchanged: historical synthetic Auth fixtures; first two also replay all 71 schema migrations' : 'read-only exact preflight, refreshed actual result required' };
  });
  const catalogSql = makeCatalogSql(functionInventory, [...tables.values()], [...forced].sort());
  const strictSql = makeStrictSql([...forced].sort());
  const preservationSql = makePreservationSql();
  const renameSql = makeRenameSql(unknownRenames);
  const plan = {
    kind: 'offline_prepared_installed_verification_plan', preparedAt: new Date().toISOString(), projectId: review.projectId,
    review: { path: reviewPath, fileSha256: reviewFileHash, bundleSha256: bundleHash, operationScopeSha256: scopeHash },
    preparationTool: { path: 'tools/wave5/prepare_installed_verification_20261012_r5.mjs', sha256: digest(exactRead(root, 'tools/wave5/prepare_installed_verification_20261012_r5.mjs')) },
    authorization: 'Exact human runtime setup decision is recorded separately by root; this plan adds no live operation, account, fixture, secret, job, or migration authority.',
    migrationInputs: bindings, migrationReplayIncluded: false, expectedFinalMigrationCount: 114, actualLiveLedger: null,
    sourceFunctionInventory: functionInventory, sourceTableInventory: [...tables.values()],
    forcedRlsPredicates: [...forced].sort(), grantPredicates: grantChecks.map(([signature, role, expectedExecute, provenance]) => ({ signature, role, expectedExecute, provenance })),
    transformations: transforms, dynamicFunctionGenerators: dynamicFunctionStatements, functionRenames: renames, baselineBodyRenamePrerequisites: unknownRenames,
    literalFunctionGrantStatementHashes: grants.map(({ statement, ...row }) => row),
    historicalSql: historicalInventory,
    queries: [
      { order: 0, id: 'baseline-renames', path: 'docs/verification/wave5/installed-baseline-rename-fingerprints-20261012-r5.sql', sha256: digest(renameSql), bytes: Buffer.byteLength(renameSql), mode: 'BEGIN REPEATABLE READ READ ONLY; hash-only SELECT; ROLLBACK', phases: ['before order58', 'after installation'], expectedChecks: ['three original installed baseline function bodies hashed before their rename; compare to preserved *_without_negative_policy bodies after installation', 'a postinstall original name points to an approved new wrapper and is not the preserved body', 'if genuine before fingerprints are absent, preservation remains incomplete'] },
      { order: 1, id: 'catalog', path: 'docs/verification/wave5/installed-catalog-verification-20261012-r5.sql', sha256: digest(catalogSql), bytes: Buffer.byteLength(catalogSql), mode: 'BEGIN REPEATABLE READ READ ONLY; metadata SELECT; ROLLBACK', expectedChecks: ['every inventoried signature/body LF hash/language/security matches final approved source', 'every directly created table exists', 'capture all target-schema grants/policies/constraints/triggers/body hashes; review dynamic RLS coverage separately'] },
      { order: 2, id: 'strict', path: 'docs/verification/wave5/installed-strict-metadata-20261012-r5.sql', sha256: digest(strictSql), bytes: Buffer.byteLength(strictSql), mode: 'BEGIN READ ONLY; metadata assertions with DO raising on false; ROLLBACK', expectedChecks: ['actual final ledger count114', 'explicit source/review force-RLS predicates', 'required and forbidden function grants', 'anon/public runtime entrypoint denial', 'private cash table grants'] },
      { order: 3, id: 'preservation', path: 'docs/verification/wave5/installed-preservation-fingerprints-20261012-r5.sql', sha256: digest(preservationSql), bytes: Buffer.byteLength(preservationSql), mode: 'BEGIN REPEATABLE READ READ ONLY; hash-only SELECT; ROLLBACK', expectedChecks: ['compare protected access row fingerprints to immediate preinstall live preflight', 'compare old120 providers by exact identity to actual preinstall baseline, allowing only explicitly approved replacements', 'existing confirmed desktop account retained; no password or token columns read'] },
    ],
    serialExecution: [
      'Root binds actual immediately preinstall metadata/ledger/collision records; frozen Oct10 and narrow Oct12 counts are not an immediate preflight.',
      'Before order58 run the baseline-renames query and preserve the three original actual installed body hashes; run it again after installation and compare the three preserved renamed aliases. No hypothetical before hash can replace a missing actual observation.',
      'Root installs exactly the71 approved missing sources once, in reviewed order. Record actual connector name/version and submitted bytes for each; never replay original six.',
      'Run catalog SQL once as one complete connector query. Save full raw result and context. Any absent signature/body mismatch is a failed installed gate, not a source repair or automatic reinstallation.',
      'Run strict metadata SQL as one complete query. BEGIN/ROLLBACK belong to this one connection. The DO assertion raises on false; a connector failure is retained and must not be turned into a pass.',
      'Run preservation SQL and requery migration ledger. Compare exact old43 rows and original six versions, protected four access fingerprints, account identity, provider revisions, and explicit approved modifications.',
      'Only after genuine private Auth Admin account creation and returned-ID binding prepare account-bound rollback cases over exactly reviewed synthetic tenants. Do not replay historical Auth inserts or manufacture MFA factors/claims/session proof.',
      'For every behavior batch use one caller-owned BEGIN...ROLLBACK, real actor/request context and exact new IDs. Preserve raw error/result and immediately verify protected before/after fingerprints. Do not invoke network, Vault creation, or scheduler registration inside a rollback probe.',
    ],
    rollbackBehaviorBatches: [
      { id: 'bootstrap-mapping', status: 'blocked-until-six-genuine-AuthAdmin-returned-IDs', historicalSource: historical[1].path, historicalAssertions: 25, required: ['remove71-migration prefix; do not execute Auth fixture insert/constant account IDs', 'bind all six actual new Auth IDs to jentra.w5.created_auth_ids on same connection', 'exact bootstrap body only in a caller-owned rollback if not already persisted; do not duplicate a committed bootstrap', 'no injected jwt AAL2 claim treated as actual MFA; real membership and policy capabilities rechecked'], reusableUnchanged: false },
      { id: 'cash-and-scenario-behavior', status: 'blocked-until-genuine-Auth-and-bounded-source-fixtures', historicalSource: historical[0].path, required: ['genuine proposer/approver/executor identities and real AAL2', 'source caps200/800/100/200 retained', 'rollback-only business mutations limited to exact new synthetic runtime scope', 'fresh actual payroll/project/statement provider metadata and nonempty fixture source dates'], reusableUnchanged: false },
      { id: 'worker-lease-model-policy', status: 'blocked-until-exact-real-synthetic-bootstrap', historicalSource: historical[0].path, required: ['actual trusted service authority; scoped runtime APIs only', 'activation before runtime usage buckets; accept-only subscription for lease phase', 'no real model/transport/cron work in rollback-only SQL', 'claim-only effect is lease1/usage0; actual reserve/send is a separate gate'], reusableUnchanged: false },
      { id: 'actual-setup-and-delivery', status: 'separate-reviewed-persistent-runtime-stage', historicalSource: 'supabase/tests/wave5_supabase_setup_test.sql', required: ['exact reviewed persistent setup outside rollback probes when authority is genuine', 'no arbitrary Vault key names or test scheduler jobs', 'actual transport observation and real delivery/MFA required independently'], reusableUnchanged: false },
    ],
    transactionSemantics: [
      'No inner COMMIT, migration DDL, permission-registration shim, Auth DML, fabricated MFA, constructed JWT, Vault write, cron write, net.http_post, or persistent business fixture is included in the new SQL.',
      'Do not split a rollback batch into separate connector calls: a new connection would lose temp tables, local settings and transaction ownership.',
      'On error PostgreSQL may abort the transaction and the connector may discard the connection; preserve the error. Do not assume a second connection can roll back the first. Save fresh after-state fingerprints before claiming preservation.',
      'The read-only metadata batches issue no side-effectful application function. Function definition, source-body, policy, grant and access-row outputs are hashes, never secrets or private bodies.',
    ],
    execution: { databaseCalls: 0, sqlExecuted: false, installedSchemaVerified: false, fixturesCreated: false, authChanged: false, secretRead: false, networkCalls: 0, sdkJobs: 0, statusesChanged: false },
    gates: { sourceMappingPrepared: true, installationVerified: false, authenticatedNative: false, realMfa: false, actualDelivery: false, actualModelUsage: false, independentContention: false, targetScaleLoad: false, ownerAccepted: 3, ownerCriteria: 109, wholeSystemAccepted: false },
  };
  return { plan, catalogSql, strictSql, preservationSql, renameSql };
}

function makeCatalogSql(functions, tables, forced) {
  const functionValues = functions.map(row => '(' + [row.signature, row.bodyLfSha256, row.language, row.volatility].map(sqlString).join(',') + ',' + row.securityDefiner + ')').join(',\n');
  const tableValues = tables.map(row => '(' + sqlString(row.name) + ')').join(',\n');
  return `-- Prepared offline from the exact approved r5 sources. This is not migration SQL.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
WITH expected_functions(signature,body_lf_sha256,language,volatility,security_definer) AS (VALUES
${functionValues}
), expected_tables(name) AS (VALUES
${tableValues}
), function_checks AS (
 SELECT e.signature,e.body_lf_sha256 AS expected_body_lf_sha256,p.oid IS NOT NULL AS present,
  CASE WHEN p.oid IS NOT NULL THEN encode(extensions.digest(replace(p.prosrc,E'\\r\\n',E'\\n'),'sha256'),'hex') END AS installed_body_lf_sha256,
  e.language AS expected_language,l.lanname AS installed_language,
  e.volatility AS expected_volatility,p.provolatile AS installed_volatility,
  e.security_definer AS expected_security_definer,p.prosecdef AS installed_security_definer,
  coalesce(p.oid IS NOT NULL AND e.body_lf_sha256=encode(extensions.digest(replace(p.prosrc,E'\\r\\n',E'\\n'),'sha256'),'hex') AND l.lanname=e.language AND p.provolatile=e.volatility AND p.prosecdef=e.security_definer,false) AS matches
 FROM expected_functions e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
 LEFT JOIN pg_language l ON l.oid=p.prolang
), table_checks AS (SELECT name,to_regclass(name) IS NOT NULL AS present FROM expected_tables)
SELECT jsonb_build_object('observedAt',statement_timestamp(),'database',current_database(),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'apiFunctionCount',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api'),
 'expectedFunctions',(SELECT count(*) FROM function_checks),
 'matchingFunctions',(SELECT count(*) FROM function_checks WHERE matches),
 'functionChecks',(SELECT jsonb_agg(to_jsonb(f) ORDER BY f.signature) FROM function_checks f),
 'expectedTables',(SELECT count(*) FROM table_checks),
 'presentTables',(SELECT count(*) FROM table_checks WHERE present),
 'tableChecks',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.name) FROM table_checks t),
 'functions',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
  'definitionSha256',encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'),
  'bodyLfSha256',encode(extensions.digest(replace(p.prosrc,E'\\r\\n',E'\\n'),'sha256'),'hex'),
  'language',l.lanname,'securityDefiner',p.prosecdef,'volatility',p.provolatile,'config',p.proconfig,
  'grantFingerprint',encode(extensions.digest(coalesce(p.proacl::text,''),'sha256'),'hex'),
  'publicExecute',EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE'),
  'anonExecute',has_function_privilege('anon',p.oid,'EXECUTE'),'authenticatedExecute',has_function_privilege('authenticated',p.oid,'EXECUTE'),'serviceExecute',has_function_privilege('service_role',p.oid,'EXECUTE'))
  ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
  WHERE n.nspname IN (${schemas.map(sqlString).join(',')}) AND p.prokind='f'),
 'tables',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'name',c.relname,'rlsEnabled',c.relrowsecurity,'rlsForced',c.relforcerowsecurity,
  'explicitRlsPredicate',n.nspname||'.'||c.relname IN (${forced.map(sqlString).join(',')}),
  'policyCount',(SELECT count(*) FROM pg_policy p WHERE p.polrelid=c.oid),
  'policyFingerprint',encode(extensions.digest(coalesce((SELECT jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname)::text FROM pg_policy p WHERE p.polrelid=c.oid),'[]'),'sha256'),'hex'),
  'grantFingerprint',encode(extensions.digest(coalesce(c.relacl::text,''),'sha256'),'hex'),
  'constraintFingerprint',encode(extensions.digest(coalesce((SELECT jsonb_agg(jsonb_build_object('name',x.conname,'type',x.contype,'validated',x.convalidated,'definition',pg_get_constraintdef(x.oid)) ORDER BY x.conname)::text FROM pg_constraint x WHERE x.conrelid=c.oid),'[]'),'sha256'),'hex'),
  'triggerFingerprint',encode(extensions.digest(coalesce((SELECT jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid)) ORDER BY t.tgname)::text FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'[]'),'sha256'),'hex')) ORDER BY n.nspname,c.relname)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN (${schemas.filter(x => x !== 'api').map(sqlString).join(',')}) AND c.relkind IN ('r','p'))
) AS installed_catalog;
ROLLBACK;
`;
}

function makeStrictSql(forced) {
  const values = grantChecks.map(([signature, role, allowed]) => '(' + sqlString(signature) + ',' + sqlString(role) + ',' + allowed + ')').join(',\n');
  return `-- Installed metadata assertions only: no pgtap install, fixture, Auth DML or JWT claims.
BEGIN READ ONLY;
DO $installed_metadata$
DECLARE failed integer;
BEGIN
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations)<>114 THEN RAISE EXCEPTION 'FINAL_LEDGER_COUNT_MISMATCH'; END IF;
 SELECT count(*) INTO failed FROM (VALUES ${forced.map(name => '(' + sqlString(name) + ')').join(',')}) e(name)
 LEFT JOIN pg_class c ON c.oid=to_regclass(e.name) WHERE NOT coalesce(c.relrowsecurity AND c.relforcerowsecurity,false);
 IF failed<>0 THEN RAISE EXCEPTION 'INSTALLED_FORCED_RLS_MISMATCH:%',failed; END IF;
 WITH expected(signature,role_name,allowed) AS (VALUES
${values}
 ) SELECT count(*) INTO failed FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
 WHERE p.oid IS NULL OR has_function_privilege(e.role_name,p.oid,'EXECUTE') IS DISTINCT FROM e.allowed;
 IF failed<>0 THEN RAISE EXCEPTION 'INSTALLED_FUNCTION_GRANT_MISMATCH:%',failed; END IF;
 SELECT count(*) INTO failed FROM (VALUES ${[...new Set(grantChecks.map(x => x[0]))].map(name => '(' + sqlString(name) + ')').join(',')}) e(signature)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
 WHERE p.oid IS NULL OR has_function_privilege('anon',p.oid,'EXECUTE') OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE');
 IF failed<>0 THEN RAISE EXCEPTION 'INSTALLED_ANON_PUBLIC_GRANT_MISMATCH:%',failed; END IF;
 IF has_table_privilege('authenticated','analytics.cash_date_proposals','SELECT') OR has_table_privilege('authenticated','analytics.cash_date_decisions','SELECT') THEN RAISE EXCEPTION 'PRIVATE_CASH_DIRECT_READ_GRANTED'; END IF;
END
$installed_metadata$;
SELECT jsonb_build_object('observedAt',statement_timestamp(),'strictMetadataPredicatesPassed',true,
 'ledgerCount',114,'forcedRlsPredicates',${forced.length},'functionGrantPredicates',${grantChecks.length},
 'behaviorFixturesExecuted',false,'realAuthVerified',false,'realMfaVerified',false,'actualDeliveryVerified',false) AS strict_metadata;
ROLLBACK;
`;
}

function makePreservationSql() {
  return `-- Hash-only preservation query. Compare to the immediately preinstall live read.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'accessCounts',jsonb_build_object('rolePermissions',(SELECT count(*) FROM core.role_permissions),'roleAssignments',(SELECT count(*) FROM core.role_assignments),'entitlements',(SELECT count(*) FROM billing.plan_entitlements),'memberships',(SELECT count(*) FROM core.memberships)),
 'accessRowFingerprints',(SELECT jsonb_object_agg(x.name,x.fingerprint ORDER BY x.name) FROM (
 SELECT 'core.role_permissions' AS name,encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tenant_id,t.role_id,t.permission_code)::text FROM core.role_permissions t),'[]'),'sha256'),'hex') AS fingerprint
 UNION ALL SELECT 'core.role_assignments',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)::text FROM core.role_assignments t),'[]'),'sha256'),'hex')
 UNION ALL SELECT 'billing.plan_entitlements',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.plan_code,t.entitlement_code)::text FROM billing.plan_entitlements t),'[]'),'sha256'),'hex')
 UNION ALL SELECT 'core.memberships',encode(extensions.digest(coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)::text FROM core.memberships t),'[]'),'sha256'),'hex')
 ) x),
 'protectedProviders',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),'definitionSha256',encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex')) ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.prokind='f' AND (n.nspname='api' OR (n.nspname='core' AND p.proname IN ('has_permission','require_permission','wave2_assert_expected_version','wave2_derived_uuid','wave2_finish_command','wave2_permission','wave2_replay','wave2_request_hash','wave3_assert_expected_version','wave3_finish_command','wave3_replay','wave3_request_hash','wave3_require_scope')))),
 'existingDesktopAccount',(SELECT jsonb_build_object('authId',u.id,'confirmed',u.email_confirmed_at IS NOT NULL,'membershipCount',(SELECT count(*) FROM core.memberships m WHERE m.user_id=u.id)) FROM auth.users u WHERE u.id='c0ab44a9-7385-4d9c-94f2-4df3efaa453f'::uuid AND u.email='desktop-test-20261009@jentra.invalid'),
 'plannedRuntimeAccountCount',(SELECT count(*) FROM auth.users WHERE email IN ('w5-proposer@jentra.invalid','w5-approver@jentra.invalid','w5-executor@jentra.invalid','w5-billing-admin@jentra.invalid','w5-operator@jentra.invalid','w5-foreign-member@jentra.invalid')),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations)
) AS installed_preservation;
ROLLBACK;
`;
}

function makeRenameSql(renames) {
  assert.equal(renames.length, 3, 'Unexpected installed-baseline rename set');
  return `-- Read once BEFORE migration order58 and once after installation. Hashes only.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
WITH expected(original_signature,preserved_signature) AS (VALUES
${renames.map(row => '(' + sqlString(row.before) + ',' + sqlString(row.after) + ')').join(',\n')}
)
SELECT jsonb_build_object('observedAt',statement_timestamp(),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'functions',(SELECT jsonb_agg(jsonb_build_object('originalSignature',e.original_signature,'preservedSignature',e.preserved_signature,
  'originalPresent',o.oid IS NOT NULL,'preservedPresent',p.oid IS NOT NULL,
  'originalBodyLfSha256',CASE WHEN o.oid IS NOT NULL THEN encode(extensions.digest(replace(o.prosrc,E'\\r\\n',E'\\n'),'sha256'),'hex') END,
  'originalDefinitionSha256',CASE WHEN o.oid IS NOT NULL THEN encode(extensions.digest(pg_get_functiondef(o.oid),'sha256'),'hex') END,
  'preservedBodyLfSha256',CASE WHEN p.oid IS NOT NULL THEN encode(extensions.digest(replace(p.prosrc,E'\\r\\n',E'\\n'),'sha256'),'hex') END,
  'preservedDefinitionSha256',CASE WHEN p.oid IS NOT NULL THEN encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex') END)
  ORDER BY e.original_signature) FROM expected e LEFT JOIN pg_proc o ON o.oid=to_regprocedure(e.original_signature) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.preserved_signature))
) AS baseline_rename_fingerprints;
ROLLBACK;
`;
}

function markdown(plan) {
  return `# Prepared installed verification, 2026-10-12 r5

This is offline preparation for the exact approved runtime bundle \`${bundleHash}\`. The 71 migration inputs are freshly hashed; the original six are not included for replay. No SQL, fixture, account, secret, native session, SDK job or installation was executed by this preparation.

Read the three baseline rename fingerprints before migration order58 and again after installation. Then run the three postinstall queries serially after root records the actual71 connector-installed ledger rows. Each query has one complete caller-owned read-only transaction ending in ROLLBACK. Keep the raw connector result and live context. Strict metadata raises on a missing/incorrect grant, forced RLS or ledger count; catalog table/body mismatches are separate failures. These are not business behavior tests.

| Order | Query | SHA-256 |
|---|---|---|
${plan.queries.map(query => '| ' + query.order + ' | [' + query.path.split('/').at(-1) + '](' + query.path.split('/').at(-1) + ') | `' + query.sha256 + '` |').join('\n')}

There are ${plan.sourceFunctionInventory.length} final function-body expectations, ${plan.sourceTableInventory.length} directly created tables, ${plan.forcedRlsPredicates.length} explicit/reviewed forced-RLS predicates and ${plan.grantPredicates.length} exact function grant predicates. Function expectations include the three concrete supplier-bill wrappers, the exact guarded return-aware transforms and30 reviewed body-mapped rename/schema moves. Three other renamed bodies originate in the already installed baseline and require actual before/after fingerprints. CRLF is normalized to LF; no other source-body normalization is allowed. These are source mappings until an actual installed result matches them. Catalog fingerprints capture other policy/grant/constraint/trigger and dynamically forced table details for independent comparison; the explicit forced-RLS predicate subset is not claimed as all dynamic RLS coverage.

Compare the protected four access-row fingerprints and the old provider identities against the immediately preinstall full live read, with only source-bound approved replacements allowed. The frozen October 10 snapshot and October 12 count-only read do not establish current preservation. Read the actual ledger again and retain all old43 name/version pairs and the original six exact versions. Existing desktop account identity and confirmation are checked without selecting password/session/token fields.

The reviewed historical 105/25 SQL probes prepend all71 schema migrations and insert synthetic Auth rows. The older126 installed probe also inserts/deletes test MFA factors. Preserve these files and their historical results; do not run them unchanged or call their results fresh installed evidence. Their successful source probes do not override the current no fabricated Auth/MFA rule.

Account-bound rollback behavior remains incomplete until all six private Auth Admin creates return genuine IDs and actual MFA is available. Use only exact reviewed new tenant scopes, no permission-registration shim, no constructed JWT proof, and no existing acceptance role/store/session change. An already committed bootstrap cannot be repeated as a rollback fixture. Cash/provider/scenario/lease/model cases require fresh bounded nonempty source fixtures and exact committed-state evidence. Actual persistent setup, real delivery/model calls and independent-session contention/load remain separate stages.

Do not split a transaction over connector calls. On an error preserve the failed raw result; a new connection cannot roll back an old connection. Obtain fresh after-state fingerprints before reporting preservation. No real HTTP/Vault/cron work belongs in a rollback-only probe.

Owner acceptance remains3/109, with106 open. This plan supplies no additional acceptance and leaves installed behavior, authenticated native/MFA, actual delivery/model, contention/load and full owner acceptance open.
`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv[2], '--prepare', 'Only --prepare is supported; no database execution mode exists');
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  const prepared = prepareInstalledVerification(root);
  const reportPath = 'docs/verification/wave5/installed-verification-plan-20261012-r5.json';
  const textPath = 'docs/verification/wave5/installed-verification-plan-20261012-r5.md';
  const outputs = [
    [prepared.plan.queries[0].path, prepared.renameSql],
    [prepared.plan.queries[1].path, prepared.catalogSql],
    [prepared.plan.queries[2].path, prepared.strictSql],
    [prepared.plan.queries[3].path, prepared.preservationSql],
    [reportPath, JSON.stringify(prepared.plan, null, 2) + '\n'],
    [textPath, markdown(prepared.plan)],
  ];
  for (const [relative] of outputs) assert.equal(fs.existsSync(path.join(root, relative)), false, 'Existing publication must remain frozen: ' + relative);
  for (const [relative, content] of outputs) fs.writeFileSync(path.join(root, relative), content, { flag: 'wx' });
  console.log(JSON.stringify({ prepared: true, databaseCalls: 0, queries: prepared.plan.queries,
    functionBodyExpectations: prepared.plan.sourceFunctionInventory.length, directlyCreatedTables: prepared.plan.sourceTableInventory.length,
    artifacts: outputs.map(([relative, content]) => ({ path: relative, sha256: digest(content), bytes: Buffer.byteLength(content) })) }, null, 2));
}
