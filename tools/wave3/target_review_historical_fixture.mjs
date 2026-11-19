import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const manifestPath = 'docs/verification/remaining-wave3/migration-order-final-20260930-45.json';
const sourcePaths = [
  manifestPath,
  'docs/verification/remaining-wave3/schema-after-45-20260930.json',
  'docs/blueprint/08_WAVE3_INTEGRATED_COMMERCE_FINANCE_SPEC.md',
  'docs/blueprint/57_WAVE3_TARGET_VERIFICATION_CONTRACT.md',
  'packages/jentra_platform/lib/src/wave3_observability_allowlist.dart',
  ...[
    'verify-target-fixtures.sql',
    'run-independent-sessions.mjs',
    'run-target-load.mjs',
    'prepare-target-verification.mjs',
    'run-target-fixture-generator.mjs',
    'prepare-target-race-invariants.mjs',
    'prepare-target-query-plans.mjs',
    'run-reviewed-target-verification.mjs',
    'target_review_guards.mjs',
    'target_review_aging.mjs',
    'target_review_selection.mjs',
    'strict-candidate-evidence.mjs',
  ].map(file => 'tools/wave3/' + file),
];

// Archived byte representation of the eleven mixed-newline candidates.
// Each row is [normalized SHA-256, inclusive 1-based CRLF line ranges].
// The other 34 candidates were archived as LF. Both the normalized body and
// reconstructed raw bytes must match before a candidate enters the test fixture.
const mixedNewlines = {
  '20260913005000_procurement_order_workflow.sql': [
    'b68f4e3e1d876dab15139ba6d6be15c245d01c1abfdb05041f66869b518fd4cb', [[143, 143]],
  ],
  '20260914001000_procurement_supplier_settlement.sql': [
    '43f7d67b52f0c79be40fa502083ea439b82311002da083c91dc34fcf5fc120cd', [[387, 387], [425, 425], [456, 456]],
  ],
  '20260915001000_payable_allocation_corrections.sql': [
    'b1ae732bf1ff20cee06544aefc21e0aeab8b5261bac3db9fa417f1ce29a00af3',
    [[170, 170], [187, 187], [207, 207], [238, 239], [253, 253], [292, 293]],
  ],
  '20260916001000_inventory_transfers.sql': [
    '30057bc59aea5bcbcee4ea2cbf0be9f950d402445bc324c6e075b6440da52415', [[322, 322]],
  ],
  '20260916002000_inventory_stock_counts.sql': [
    '02e7ab6c92539ebc9309bee4197af782ad3d7f6b8b29c7055c01d20808ce9bd8',
    [[1, 4], [6, 22], [25, 46], [225, 239], [242, 336], [396, 396], [446, 446]],
  ],
  '20260919181407_inventory_receipt_provenance.sql': [
    'efc3cb4fb946b25979ded3bfa862b86e01411bb421b4aa4290ebb3b586b72023', [[226, 227]],
  ],
  '20260919185538_inventory_landed_value.sql': [
    'c7bc0e0536f57d5d2eeee78dfa4a8a275dfed313a145a65564858a424f3f7650', [[225, 225]],
  ],
  '20260921041348_manual_journals.sql': [
    '1154de20409ed51e8fec2e12c82f92d98e9d510d8974f2f96f9e957250b83918', [[162, 176], [178, 254]],
  ],
  '20260922001000_ar_ap_control_reconciliation.sql': [
    '620b8256c8e8218e1539968252ba94cb9cf6196d12f758f5be9c8bb7b0321598', [[289, 289]],
  ],
  '20260927200629_wave3_operational_evidence.sql': [
    '3c43f677b2cb5ee6d0fbbe794397df2e5af1861d3b14ca388a1aedf6bca0cab8', [[94, 167], [191, 200]],
  ],
  '20260930003000_wave3_stock_disposition.sql': [
    'b18b6e35cba464b04d8d9884af1c3133539df1da3e84bdbab3b6f2dd0f6e50e7',
    [[8, 11], [13, 29], [34, 55], [318, 332], [335, 407], [409, 429]],
  ],
};

export const historicalSourceHash = bytes => createHash('sha256').update(bytes).digest('hex');

export function historicalManifest() {
  return JSON.parse(fs.readFileSync(path.join(repo, manifestPath), 'utf8'));
}

function reconstructCandidate(candidate) {
  assert.match(candidate.path, /^supabase\/migrations\/\d{14}_[a-z0-9_]+\.sql$/);
  const [normalizedHash, ranges] = mixedNewlines[path.basename(candidate.path)] ?? [candidate.sha256, []];
  const normalized = fs.readFileSync(path.join(repo, candidate.path), 'utf8').replaceAll('\r\n', '\n');
  assert.equal(historicalSourceHash(normalized), normalizedHash, 'Normalized SQL drift: ' + candidate.path);
  let line = 0;
  const raw = normalized.replace(/\n/g, () => {
    line += 1;
    return ranges.some(([first, last]) => line >= first && line <= last) ? '\r\n' : '\n';
  });
  assert.equal(historicalSourceHash(raw), candidate.sha256, 'Historical byte mismatch: ' + candidate.path);
  return raw;
}

export async function historicalReviewFixture(context) {
  const manifest = historicalManifest();
  assert.equal(manifest.candidates.length, 45);
  const candidates = manifest.candidates.map(candidate => [candidate.path, reconstructCandidate(candidate)]);
  const base = fs.realpathSync(os.tmpdir());
  const prefix = 'jentra-historical-wave3-';
  const directory = fs.mkdtempSync(path.join(base, prefix));
  context.after(() => {
    const resolved = fs.realpathSync(directory);
    if (resolved !== directory || path.dirname(resolved) !== base || !path.basename(resolved).startsWith(prefix)) {
      throw Error('Unsafe historical test fixture cleanup boundary');
    }
    fs.rmSync(resolved, { recursive: true });
  });
  for (const [relative, bytes] of [...sourcePaths.map(file => [file, fs.readFileSync(path.join(repo, file))]), ...candidates]) {
    const destination = path.join(directory, relative);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, bytes, { flag: 'wx' });
  }
  const tool = file => pathToFileURL(path.join(directory, 'tools', 'wave3', file)).href;
  const [preparation, generator] = await Promise.all([
    import(tool('prepare-target-verification.mjs')),
    import(tool('run-target-fixture-generator.mjs')),
  ]);
  return { directory, manifest, preparation, generator };
}
