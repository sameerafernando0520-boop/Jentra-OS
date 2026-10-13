// Reconstruct the previously approved bytes in a separate execution tree.
// No source replacement, hard links, network operations or private input reads.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { hashBytes, validateRuntimeReview, validateApproval } from './runtime_contract.mjs';
import { REMAINING_DIRECT_SOURCES } from './prepare_finance_remaining_20261013_r5.mjs';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const BASE = 'docs/verification/wave5/';
const TARGET = 'build/wave5-approved-execution-20261013-r5-a2';
const REVIEW = BASE + 'complete-app-runtime-review-20261010-r5.json';
const REVIEW_SHA = 'b1b0cb94a8aa705b5cc6ff674ed215a8487a960ff0a594f7abffadfbc4e57cc3';
const OWNER = BASE + 'runtime-owner-decision-20261012-r5.json';
const OWNER_SHA = '90daa67a459bd985a1bec824bf0e8e09bf69537c2febdae85238336604c655ab';
const BUNDLE = 'db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
const PEOPLE_NAMES = ['employee', 'payroll', 'payroll_correction', 'private_hr', 'workforce'];
const RECOVERABLE = new Set(PEOPLE_NAMES.flatMap(name => [
  `apps/jentra_desktop/lib/src/features/people/${name}_controller.dart`,
  `apps/jentra_desktop/test/${name}_workspace_test.dart`,
]));
const must = (ok, code) => { if (!ok) { const error = new Error(code); error.publicCode = code; throw error; } };

function contained(relative) {
  must(typeof relative === 'string' && relative.length > 0 && !path.isAbsolute(relative)
    && !relative.includes('\\') && !relative.split('/').some(part => part === '..' || part === '.' || part === ''),
  'CANONICAL_SNAPSHOT_RELATIVE_PATH_REQUIRED');
  const full = path.resolve(ROOT, relative);
  must(full.toLowerCase().startsWith(path.resolve(ROOT).toLowerCase() + path.sep), 'SNAPSHOT_PATH_OUTSIDE_WORKSPACE');
  return full;
}
async function regularBytes(relative) {
  const full = contained(relative);
  const stat = await fs.lstat(full);
  must(stat.isFile() && !stat.isSymbolicLink(), 'REGULAR_SNAPSHOT_SOURCE_REQUIRED');
  must((await fs.realpath(full)).toLowerCase() === full.toLowerCase(), 'SNAPSHOT_SOURCE_REPARSE_FORBIDDEN');
  return fs.readFile(full);
}
async function writeNew(relative, bytes) {
  const full = contained(relative);
  await fs.mkdir(path.dirname(full), { recursive: true });
  must((await fs.realpath(path.dirname(full))).toLowerCase() === path.dirname(full).toLowerCase(),
    'SNAPSHOT_TARGET_REPARSE_FORBIDDEN');
  const handle = await fs.open(full, 'wx');
  try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
  must(hashBytes(await fs.readFile(full)) === hashBytes(bytes), 'SNAPSHOT_COPY_READBACK_MISMATCH');
}
const reviewBytes = await regularBytes(REVIEW);
must(hashBytes(reviewBytes) === REVIEW_SHA, 'ORIGINAL_REVIEW_BYTES_CHANGED');
const review = JSON.parse(reviewBytes); validateRuntimeReview(review);
must(review.bundleSha256 === BUNDLE && review.artifacts.length === 5468 && review.migrations.length === 71,
  'ORIGINAL_APPROVED_BUNDLE_REQUIRED');
const ownerBytes = await regularBytes(OWNER);
must(hashBytes(ownerBytes) === OWNER_SHA, 'ORIGINAL_OWNER_DECISION_CHANGED');
validateApproval(JSON.parse(ownerBytes), review, { runtimeFileSha256: REVIEW_SHA });
await fs.mkdir(contained(TARGET)); // Fail if this snapshot already exists. Never reuse or clean a tree.
const approvedBindings = [...review.artifacts, ...review.migrations];
must(approvedBindings.length === 5539, 'COMPLETE_APPROVED_BINDINGS_REQUIRED');
const uniqueBindings = new Map();
for (const binding of approvedBindings) {
  if (uniqueBindings.has(binding.path)) {
    must(uniqueBindings.get(binding.path).sha256 === binding.sha256, 'CONFLICTING_APPROVED_DUPLICATE_BINDING');
  } else uniqueBindings.set(binding.path, binding);
}
const recoveredBindings = [], bindings = [];
for (const binding of uniqueBindings.values()) {
  const current = await regularBytes(binding.path), currentSha256 = hashBytes(current);
  let bytes = current, sourcePath = binding.path;
  if (currentSha256 !== binding.sha256) {
    must(RECOVERABLE.has(binding.path), 'UNEXPECTED_APPROVED_SOURCE_DRIFT');
    sourcePath = 'build/w5win10r5/connected/' + binding.path;
    bytes = await regularBytes(sourcePath);
    must(hashBytes(bytes) === binding.sha256, 'RECOVERED_APPROVED_BYTES_REQUIRED');
    recoveredBindings.push({ path: binding.path, approvedSha256: binding.sha256,
      currentSha256AtRead: currentSha256, recoveredFrom: sourcePath, sourceReplacementPerformed: false });
  }
  await writeNew(TARGET + '/' + binding.path, bytes);
  bindings.push({ path: binding.path, sha256: binding.sha256, sourcePath });
}
const additionalPaths = new Set([REVIEW, OWNER,
  BASE + 'approved-live-resume-20261013-r5-raw.json',
  BASE + 'complete-live-preflight-20261010-r2.sql',
  BASE + 'installed-baseline-rename-fingerprints-20261012-r5.sql',
  ...REMAINING_DIRECT_SOURCES]);
for (const directory of [BASE + 'genuine-finance-finance-20261013-r5-1791894436593/',
  BASE + 'genuine-finance-finance-20261013-r5-1791894738890/']) {
  for (const file of (await fs.readdir(contained(directory.slice(0, -1)))).sort()) {
    must(/^[a-zA-Z0-9_-]+\.json$/.test(file), 'PUBLIC_FINANCE_EVIDENCE_FILE_REQUIRED');
    additionalPaths.add(directory + file);
  }
}
const approvedPaths = new Set(bindings.map(x => x.path)), additionalBindings = [];
for (const relative of [...additionalPaths].sort()) {
  if (approvedPaths.has(relative)) continue;
  const bytes = await regularBytes(relative);
  await writeNew(TARGET + '/' + relative, bytes);
  additionalBindings.push({ path: relative, sha256: hashBytes(bytes),
    originalBundleMember: false, purpose: 'bounded remaining-finance source or public evidence' });
}
const frozenGuard = await import(pathToFileURL(contained(TARGET + '/tools/wave5/approved_management_installer.mjs')));
const checked = await frozenGuard.loadApprovedInputs();
must(checked.inspectedBindings === 5539 && checked.review.bundleSha256 === BUNDLE,
  'ORIGINAL_UNMODIFIED_FULL_APPROVAL_GUARD_REQUIRED');
const result = { kind: 'exact-approved-isolated-execution-snapshot', createdAt: new Date().toISOString(),
  executionRootRelative: TARGET, projectId: 'xpdoufauvrbdmxgngetv', bundleSha256: BUNDLE,
  originalReview: { path: REVIEW, sha256: REVIEW_SHA }, originalOwnerDecision: { path: OWNER, sha256: OWNER_SHA },
  approvedBindingCount: 5539, uniqueApprovedFileCount: uniqueBindings.size,
  originalApprovedBindingRows: approvedBindings, approvedBindings: bindings, recoveredBindings, additionalBindings,
  originalApprovalValidatorModified: false, originalFullApprovalGuardPassed: true,
  currentWorkspaceIsExactApprovedBundle: false, concurrentChangesPreserved: true,
  approvalOfConcurrentPeopleChangesImplied: false, additionalSourceApprovalImplied: false,
  networkCalls: 0, privateInputsRead: false, liveExecution: false, sourceReplacementPerformed: false,
  ownerAcceptance: false, production: false, realBilling: false };
const bytes = Buffer.from(JSON.stringify(result, null, 2) + '\n');
const evidence = BASE + 'approved-isolated-execution-snapshot-20261013-r5-a2.json';
await writeNew(evidence, bytes);
await writeNew(TARGET + '/' + evidence, bytes);
process.stdout.write(JSON.stringify({ prepared: true, executionRootRelative: TARGET, approvedBindingCount: 5539,
  recoveredBindings: recoveredBindings.length, additionalBindings: additionalBindings.length,
  originalFullApprovalGuardPassed: true, evidence: { path: evidence, sha256: hashBytes(bytes) }, liveExecution: false }) + '\n');
