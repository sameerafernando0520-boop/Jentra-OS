// Read-only validation of actual r5 SDK evidence. No process arguments or writes.
import {sources} from './cash_ui_evidence.mjs';
import {
  auditStage, base, bytes, declaredGoldenFailures, eq, mapEq, must, parse,
  root, selected, sha, sourcePath,
} from './desktop_verification_inputs_20261010_r5.mjs';

export {base, root, sha, must, parse};
export const packetPath = base + 'golden-owner-review-20261010-r5.json';
export const markdownPath = base + 'golden-owner-review-20261010-r5.md';
export const galleryPath = 'dist/Jentra OS Preview Guidance Review 20261010 r5.html';
export const ownerPath = base + 'owner-golden-decision-20261010-r5.json';
export const promotionPath = base + 'golden-promotion-result-20261010-r5.json';
export const publicationPath = base + 'preview-guidance-review-publication-20261010-r5.json';
export const decodedGalleryPath = base + 'preview-guidance-gallery-verification-20261010-r5.json';
export const ownScripts = [
  'scripts/wave5/preview_guidance_review_inputs_20261010_r5.mjs',
  'scripts/wave5/preview_guidance_gallery_20261010_r5.mjs',
  'scripts/wave5/build_preview_guidance_review_20261010_r5.mjs',
  'scripts/wave5/promote_preview_guidance_goldens_20261010_r5.mjs',
  'scripts/wave5/verify_preview_guidance_gallery_20261010_r5.mjs',
];
export const earlierRecords = [
  base + 'owner-golden-decision-20261010-r2.json',
  base + 'golden-promotion-result-20261010-r2.json',
  base + 'golden-review-approvedAll-20261010-r2.json',
  base + 'owner-criterion-decision-20261010-r2.json',
  base + 'owner-criterion-acceptance-after-20261010-r2-serial.json',
];
export const supersededR4Bindings = [
  {path: base + 'desktop-verification-source-20261010-r4.json', sha256: '66b9af11a424dc7dd2fa4ba9da8caeaeedcfe2875b82f8bf1e45840e29be24a5'},
  {path: base + 'desktop-verification-focusedNonGolden-20261010-r4.json', sha256: '635a9442fbd3f8cedac0e951e4a48ce50ba6bf77171cc5da9e41449e60130f72'},
  {path: base + 'desktop-verification-focusedNonGolden-20261010-r4.log', sha256: '75acee6c905502a359c5f256a90be70fd1476a4f995a2967eaeb94e6722246e3'},
  {path: base + 'desktop-verification-focusedNonGolden-20261010-r4.sdk-exit.json', sha256: '1a5aee46d232cc29a5b169ebc2ac37991ed55d4056f5fac149e005b54a01d750'},
  {path: 'scripts/wave5/desktop_verification_inputs_20261010_r4.mjs', sha256: '6dffc81714c04b6d934307f92d558ee0c91760bc5771f1a334351d18262b7f69'},
  {path: 'scripts/wave5/prepare_desktop_verification_20261010_r4.mjs', sha256: '6546e48cf3628b4713606f97965387697bfb440df2b9cf86b67a78b5e2a2075e'},
  {path: 'scripts/wave5/run_desktop_verification_20261010_r4.mjs', sha256: '8204c9e6c4084de2614fb6f87249ab52f6f20205a7d7b8efb387103bd533d9ec'},
  {path: 'scripts/wave5/preview_guidance_gallery_20261010_r4.mjs', sha256: 'e0b9477e3afdd3120519595ddfb2ccde601133b09368f997b00b8e12967d8a7f'},
  {path: 'scripts/wave5/preview_guidance_review_inputs_20261010_r4.mjs', sha256: '240f1641c873061510dcb997b2496673dcadd9884c2dfc06aa72b1712cdd0637'},
  {path: 'scripts/wave5/build_preview_guidance_review_20261010_r4.mjs', sha256: 'ff9a40204ccf439d5ba00d18834ad88a4a8b5f00ea75e09e55abfdc62944e218'},
  {path: 'scripts/wave5/promote_preview_guidance_goldens_20261010_r4.mjs', sha256: '4e2b4bf55793f2d280db1305295a14bbd3665688815174a1b1d75ab6f8d0e4f3'},
  {path: 'scripts/wave5/verify_preview_guidance_gallery_20261010_r4.mjs', sha256: '917aabc972f86d19143083bf7bf14f69e3f300877b13699b9648f84760421a72'},
];

export async function auditSupersededR4(reader) {
  for (const ref of supersededR4Bindings) await reader.readBound(ref.path, ref.sha256);
  const failed = parse(await reader.readBound(supersededR4Bindings[1].path));
  const log = (await reader.readBound(supersededR4Bindings[2].path)).toString('utf8');
  const exit = parse(await reader.readBound(supersededR4Bindings[3].path));
  must(failed.revision === 'r4' && failed.exitCode === 1 && failed.counts === null && exit.revision === 'r4' && exit.sdkExitCode === 1, 'RETAINED_R4_FAILURE_MUST_NOT_BECOME_PASS_EVIDENCE');
  must(log.includes('GoTrueClient.startAutoRefresh') && log.includes('A Timer is still pending even after the widget tree was disposed.') && log.includes('did not complete'), 'RETAINED_R4_TIMER_FAILURE_DIAGNOSTIC_REQUIRED');
  return {
    revision: 'r4', sourceManifest: supersededR4Bindings[0],
    focusedResult: supersededR4Bindings[1], focusedLog: supersededR4Bindings[2], sdkExit: supersededR4Bindings[3],
    retainedBindings: supersededR4Bindings, exitCode: 1, completePassClaimed: false,
    recovery: 'The configured-gateway presentation fixture now disables token auto-refresh and creates/disposes its real JSON isolate outside the fake test clock. New r5 stages must pass independently; the failed r4 bytes are retained.',
  };
}

export function createBindingReader() {
  const boundHashes = new Map();
  async function readBound(relative, expectedHash) {
    const raw = await bytes(root, relative), hash = sha(raw);
    must(!expectedHash || hash === expectedHash, 'BOUND_INPUT_HASH_MISMATCH:' + relative);
    must(!boundHashes.has(relative) || boundHashes.get(relative) === hash, 'INPUT_CHANGED_DURING_VALIDATION:' + relative);
    boundHashes.set(relative, hash);
    return raw;
  }
  async function recheck() {
    for (const [relative, hash] of boundHashes) must(sha(await bytes(root, relative)) === hash, 'REVIEW_INPUT_DRIFT:' + relative);
    return {checkedAt: new Date().toISOString(), bindings: [...boundHashes].map(([path, sha256]) => ({path, sha256}))};
  }
  return {readBound, recheck, boundHashes};
}

export async function checkSource(expected) {
  const actual = selected(await sources(root));
  must(Object.keys(actual).length === 1068 && mapEq(actual, expected), 'CURRENT_R5_SELECTED_SOURCE_DRIFT');
  return {checkedAt: new Date().toISOString(), selectedSources: 1068, sha256: sha(Buffer.from(JSON.stringify(actual)))};
}

export function pngDimensions(raw) {
  must(raw.length >= 33 && raw.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) && raw.toString('ascii', 12, 16) === 'IHDR', 'PNG_IMAGE_REQUIRED');
  const result = [raw.readUInt32BE(16), raw.readUInt32BE(20)];
  must(result.every(value => value > 0 && value <= 10000), 'BOUNDED_PNG_DIMENSIONS_REQUIRED');
  return result;
}

export async function auditEight({checkCurrent = true} = {}) {
  const reader = createBindingReader();
  const supersededEvidence = await auditSupersededR4(reader);
  const sourceRaw = await reader.readBound(sourcePath), manifest = parse(sourceRaw);
  const stages = [];
  for (const stage of ['analyzer', 'focusedNonGolden', 'goldens83', 'candidate8', 'candidate8Strict']) {
    const validated = await auditStage(stage, {checkCurrent});
    await reader.readBound(validated.record.path, validated.record.sha256);
    await reader.readBound(validated.log.path, validated.log.sha256);
    await reader.readBound(validated.recordData.sdkExitRecord, validated.recordData.sdkExitRecordSha256);
    stages.push(validated);
  }
  const generated = stages.find(s => s.stage === 'candidate8'), strict = stages.find(s => s.stage === 'candidate8Strict');
  const control = stages.find(s => s.stage === 'goldens83'), candidate = generated.recordData;
  must(eq(candidate.fullControl, control.record), 'CANDIDATE_APPROVED_CONTROL_BINDING_REQUIRED');
  must(eq(strict.recordData.candidateGeneration, generated.record), 'STRICT_CANDIDATE_GENERATION_BINDING_REQUIRED');
  must(candidate.cases.length === 8 && eq(strict.actualTestIdentities, candidate.cases.map(c => c.testIdentity).sort()), 'STRICT_EXACT_EIGHT_CANDIDATE_IDENTITIES_REQUIRED');
  must(eq(candidate.sourceManifest, generated.sourceManifest) && candidate.sourceManifest.sha256 === sha(sourceRaw), 'EXACT_CANDIDATE_SOURCE_REQUIRED');
  must(eq(candidate.cases.map(c => ({testIdentity: c.testIdentity, goldenPath: c.approvedPath})).sort((a,b) => a.testIdentity.localeCompare(b.testIdentity)), declaredGoldenFailures), 'ONLY_EIGHT_DECLARED_GUIDANCE_IMAGES_ALLOWED');
  for (const ref of manifest.bindings) await reader.readBound(ref.path, ref.sha256);
  for (const relative of [...ownScripts, ...earlierRecords]) await reader.readBound(relative);
  const oldPromotion = parse(await reader.readBound(earlierRecords[1]));
  const oldSuite = parse(await reader.readBound(earlierRecords[2]));
  const accepted = parse(await reader.readBound(earlierRecords[4]));
  must(oldPromotion.status === 'complete' && oldPromotion.fullPromotion === true && oldPromotion.publishedImageCount === 83, 'EARLIER_EXACT_83_APPROVAL_PRESERVED');
  must(oldSuite.exitCode === 0 && oldSuite.counts?.passed === 2004 && oldSuite.counts.failed === 0 && oldSuite.counts.skipped === 0, 'EARLIER_2004_POSTAPPROVAL_SUITE_REQUIRED');
  must(accepted.fullPublication === true && eq(accepted.criterionIds, ['AC-551','AC-552','AC-553']) && accepted.plannedOwnerAcceptedCriteria === 3, 'EXISTING_THREE_OWNER_ACCEPTANCES_REQUIRED');
  const cases = [], embedded = [];
  for (const row of candidate.cases) {
    must(row.approvedPath === row.goldenPath || row.goldenPath === undefined, 'CANDIDATE_GOLDEN_DESTINATION_MISMATCH');
    const approved = await reader.readBound(row.approvedBackup, row.approvedSha256);
    // The approved destinations are mutable only after the exact owner decision.
    // Keep them in the source guard, not the immutable evidence binding list.
    if (checkCurrent) must(sha(await bytes(root, row.approvedPath)) === row.approvedSha256, 'APPROVED_DESTINATION_DRIFT:' + row.approvedPath);
    const proposed = await reader.readBound(row.candidatePath, row.candidateSha256);
    const diff = await reader.readBound(row.diffPath, row.diffSha256);
    const dimensions = pngDimensions(approved);
    must(eq(dimensions, pngDimensions(proposed)) && eq(dimensions, pngDimensions(diff)), 'COMPARISON_IMAGE_DIMENSIONS_CHANGED');
    must(!row.dimensions || eq(row.dimensions, dimensions), 'DECLARED_COMPARISON_DIMENSIONS_CHANGED');
    const metadata = {...row, dimensions};
    cases.push(metadata);
    embedded.push({...metadata, approved: 'data:image/png;base64,' + approved.toString('base64'), candidate: 'data:image/png;base64,' + proposed.toString('base64'), diff: 'data:image/png;base64,' + diff.toString('base64')});
  }
  await reader.recheck();
  if (checkCurrent) await checkSource(manifest.sourceHashes);
  return {checkedAt: new Date().toISOString(), reader, manifest, candidate, cases, embedded, stages, supersededEvidence,
    sourceManifest: {path: sourcePath, sha256: sha(sourceRaw)}, candidateResult: generated.record, strictCandidateResult: strict.record,
    candidateBundleSha256: candidate.candidateBundleSha256, approvedControl: {...control.record, counts: control.counts},
    currentSourceChecked: checkCurrent};
}

export async function auditPacket(eight) {
  const raw = await eight.reader.readBound(packetPath), packet = parse(raw);
  must(packet.kind === 'exact-eight-preview-guidance-owner-review' && packet.revision === 'r5' && packet.reviewSha256 === sha(Buffer.from(JSON.stringify(packet.reviewCore))), 'EXACT_R5_REVIEW_CORE_REQUIRED');
  must(eq(packet.reviewCore.images, eight.cases) && packet.reviewCore.candidateBundleSha256 === eight.candidateBundleSha256 && eq(packet.reviewCore.candidateResult, eight.candidateResult) && eq(packet.reviewCore.strictCandidateResult, eight.strictCandidateResult), 'OWNER_REVIEW_CANDIDATE_BINDINGS_CHANGED');
  must(eq(packet.reviewCore.sourceManifest, eight.sourceManifest) && eq(packet.reviewCore.approvedControl, eight.approvedControl), 'OWNER_REVIEW_SOURCE_CONTROL_CHANGED');
  must(eq(packet.reviewCore.supersededEvidence, eight.supersededEvidence), 'FAILED_R4_PROVENANCE_CHANGED');
  must(packet.html.path === galleryPath && packet.markdown.path === markdownPath, 'EXACT_R5_REVIEW_OUTPUT_PATHS_REQUIRED');
  await eight.reader.readBound(packet.html.path, packet.html.sha256);
  await eight.reader.readBound(packet.markdown.path, packet.markdown.sha256);
  for (const ref of packet.reviewCore.refs) await eight.reader.readBound(ref.path, ref.sha256);
  await eight.reader.recheck();
  return {packet, binding: {path: packetPath, sha256: sha(raw)}};
}

export async function auditDecodedGallery(eight, packet, packetBinding) {
  const raw = await eight.reader.readBound(decodedGalleryPath), record = parse(raw);
  must(record.kind === 'decoded-eight-image-gallery-integrity' && record.revision === 'r5' && record.verified === true && eq(record.packet, packetBinding) && eq(record.gallery, packet.html) && record.reviewSha256 === packet.reviewSha256 && record.candidateBundleSha256 === eight.candidateBundleSha256, 'EXACT_DECODED_GALLERY_PACKET_REQUIRED');
  must(record.imageCases === 8 && record.embeddedImages === 24 && record.allDecodedImagesMatchBoundSourceBytes === true && record.inlineRenderScriptSyntaxValid === true && record.noExternalAssetOrNetworkCode === true && record.currentSourceMatchesFrozenInputs === true && record.approvedRepositoryImagesChanged === false && record.actualOwnerDecisionsRecorded === 0 && record.ownerAcceptanceCriteriaChanged === 0, 'COMPLETE_READ_ONLY_GALLERY_INTEGRITY_REQUIRED');
  must(record.decodedImages?.length === 24 && new Set(record.decodedImages.map(i => i.stem + ':' + i.kind)).size === 24, 'EXACT_24_UNIQUE_DECODED_IMAGES_REQUIRED');
  for (const row of eight.cases) for (const [kind, hash] of [['approved',row.approvedSha256],['candidate',row.candidateSha256],['diff',row.diffSha256]]) {
    const decoded = record.decodedImages.find(i => i.stem === row.stem && i.kind === kind);
    must(decoded && decoded.sha256 === hash && eq([decoded.width,decoded.height], row.dimensions) && [1,2,3,4].includes(decoded.channels) && decoded.decodedBytes === decoded.width * decoded.height * decoded.channels && /^[0-9a-f]{64}$/.test(decoded.pixelSha256), 'EXACT_DECODED_COMPARISON_IMAGE_REQUIRED:' + row.stem + ':' + kind);
  }
  must(record.verifier?.path === ownScripts.at(-1), 'EXACT_DECODED_GALLERY_VERIFIER_REQUIRED');
  await eight.reader.readBound(record.verifier.path, record.verifier.sha256);
  must(record.summary?.path === decodedGalleryPath.replace(/\.json$/,'.md'), 'EXACT_DECODED_GALLERY_SUMMARY_REQUIRED');
  await eight.reader.readBound(record.summary.path, record.summary.sha256);
  await eight.reader.recheck();
  return {record, binding: {path: decodedGalleryPath, sha256: sha(raw)}};
}
