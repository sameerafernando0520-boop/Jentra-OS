// Default is read-only. Apply requires the exact newly recorded direct owner reply.
// A decision JSON alone is not authority: the calling agent must have received
// that direct human approval in this chat, and record its genuine provenance.
import {copyFile, lstat, mkdir, open, readFile, realpath, rename, unlink} from 'node:fs/promises';
import {constants} from 'node:fs';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {
  auditDecodedGallery, auditEight, auditPacket, base, checkSource, must, ownerPath, parse,
  promotionPath, root, sha,
} from './preview_guidance_review_inputs_20261010_r5.mjs';

const mode = process.argv[2] ?? 'check';
must(['check','apply'].includes(mode) && process.argv.length <= 4, 'EXACT_PROMOTION_MODE_REQUIRED');
must(mode !== 'apply' || process.argv[3] === ownerPath, 'EXACT_R5_DIRECT_OWNER_RECORD_REQUIRED');
const evidence = await auditEight();
const {packet, binding: packetBinding} = await auditPacket(evidence);
const {binding: decodedGallery} = await auditDecodedGallery(evidence, packet, packetBinding);
if (mode === 'check') {
  console.log(JSON.stringify({eligibleForExactOwnerDecision: true, cases: 8, bundleSha256: evidence.candidateBundleSha256, reviewSha256: packet.reviewSha256, packet: packetBinding, decodedGallery, approvedImagesChanged: false, ownerDecisionRequired: true}));
} else {
  const ownerRaw = await evidence.reader.readBound(ownerPath), owner = parse(ownerRaw), ownerHash = sha(ownerRaw);
  must(owner.kind === 'direct-human-owner-decision' && owner.authorizationKind === 'direct-human-message' && owner.submittedByOwner === true && typeof owner.messageVerbatim === 'string' && owner.messageVerbatim.trim() && owner.messageSha256 === sha(Buffer.from(owner.messageVerbatim)), 'DIRECT_HUMAN_APPROVAL_RECORD_REQUIRED');
  must(owner.sourceMessage?.role === 'user' && typeof owner.sourceMessage.messageId === 'string' && owner.sourceMessage.messageId.trim() && typeof owner.sourceMessage.threadId === 'string' && owner.sourceMessage.threadId.trim() && Number.isFinite(Date.parse(owner.sourceMessage.receivedAt)), 'GENUINE_OWNER_MESSAGE_PROVENANCE_REQUIRED');
  must(owner.candidateBundleSha256 === evidence.candidateBundleSha256 && owner.reviewSha256 === packet.reviewSha256 && JSON.stringify(owner.packet) === JSON.stringify(packetBinding), 'EXACT_R5_OWNER_PACKET_BUNDLE_APPROVAL_REQUIRED');
  must(owner.images?.length === 8 && new Set(owner.images.map(i => i.approvedPath)).size === 8, 'EXACT_EIGHT_OWNER_IMAGE_DECISIONS_REQUIRED');
  const decisions = new Map(owner.images.map(i => [i.approvedPath, i]));
  for (const row of evidence.cases) must(decisions.get(row.approvedPath)?.decision === 'accept' && decisions.get(row.approvedPath)?.candidateSha256 === row.candidateSha256, 'EXACT_EIGHT_OWNER_APPROVAL_REQUIRED:' + row.stem);
  const recoveryDirectory = base + 'golden-promotion-recovery-20261010-r5-' + randomUUID();
  const states = evidence.cases.map(row => ({stem: row.stem, path: row.approvedPath, target: path.resolve(root, row.approvedPath), originalSha256: row.approvedSha256, candidateSha256: row.candidateSha256,
    recoveryPath: recoveryDirectory + '/' + path.basename(row.approvedPath),
    recovery: path.resolve(root, recoveryDirectory, path.basename(row.approvedPath)),
    temp: path.resolve(root, recoveryDirectory, path.basename(row.approvedPath) + '.candidate.tmp'), tempOwned: false, claimed: false, published: false, recoverySha256: null}));
  for (const state of states) {
    const targetRelative = path.relative(root, state.target), recoveryRelative = path.relative(root, state.recovery), tempRelative = path.relative(root, state.temp);
    must([targetRelative,recoveryRelative,tempRelative].every(relative => relative && relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative)), 'PROMOTION_PATH_ESCAPES_WORKSPACE');
    must(/^apps\/jentra_desktop\/test\/goldens\/[a-zA-Z0-9_-]+\.png$/.test(state.path), 'TARGET_OUTSIDE_EXACT_GOLDENS');
    const stat = await lstat(state.target);
    must(stat.isFile() && !stat.isSymbolicLink() && await realpath(state.target) === state.target, 'UNLINKED_APPROVED_PNG_REQUIRED');
  }
  const startedAt = new Date().toISOString(), cleanupErrors = [], postVerificationErrors = [];
  let failure = null, sourceAfter = null, bindingsAfter = null, observed = [], recoveries = [];
  const result = await open(path.join(root, promotionPath), 'wx');
  try {
    await result.writeFile(JSON.stringify({status: 'in_progress', startedAt, ownerDecision: {path: ownerPath, sha256: ownerHash}, packet: packetBinding, candidateBundleSha256: evidence.candidateBundleSha256, recoveryDirectory, plannedImages: states.map(s => ({path: s.path, originalSha256: s.originalSha256, candidateSha256: s.candidateSha256, recoveryPath: s.recoveryPath})), boundary: 'An interrupted promotion needs actual destination/recovery reconciliation; no changes are inferred from this initial journal.'}, null, 2) + '\n');
    await mkdir(path.join(root, recoveryDirectory));
    must(await realpath(path.join(root, recoveryDirectory)) === path.join(root, recoveryDirectory), 'OWNED_RECOVERY_DIRECTORY_REQUIRED');
    for (const state of states) {
      const row = evidence.cases.find(c => c.approvedPath === state.path);
      const image = await evidence.reader.readBound(row.candidatePath, row.candidateSha256);
      const temp = await open(state.temp, 'wx'); state.tempOwned = true;
      try {await temp.writeFile(image);} finally {await temp.close();}
      must(sha(await readFile(state.temp)) === state.candidateSha256, 'OWNED_CANDIDATE_TEMP_DRIFT:' + state.path);
    }
    const expected = {...evidence.manifest.sourceHashes};
    for (const state of states) {
      await evidence.reader.recheck();
      await checkSource(expected);
      // Atomically retain the actual approved bytes. If another writer creates
      // a destination afterward, exclusive publication fails without overwrite.
      await rename(state.target, state.recovery); state.claimed = true;
      state.recoverySha256 = sha(await readFile(state.recovery));
      must(state.recoverySha256 === state.originalSha256, 'CONCURRENT_APPROVED_IMAGE_CHANGE:' + state.stem);
      await copyFile(state.temp, state.target, constants.COPYFILE_EXCL); state.published = true;
      expected[state.path] = state.candidateSha256;
      must(sha(await readFile(state.target)) === state.candidateSha256, 'PUBLISHED_CANDIDATE_DRIFT:' + state.path);
    }
  } catch (error) {failure = error.message;}
  finally {
    for (const state of states) if (state.tempOwned) {
      try {await unlink(state.temp);} catch (error) {if (error.code !== 'ENOENT') cleanupErrors.push({path: state.temp, error: error.message});}
    }
    if (cleanupErrors.length) failure ??= 'OWNED_PROMOTION_TEMP_CLEANUP_FAILED';
    for (const state of states) {
      let currentSha256 = null, exists = true, error = null;
      try {currentSha256 = sha(await readFile(state.target));}
      catch (caught) {exists = caught.code !== 'ENOENT'; error = caught.code === 'ENOENT' ? null : caught.message;}
      observed.push({path: state.path, currentSha256, exists, error, matchesOriginal: currentSha256 === state.originalSha256, matchesCandidate: currentSha256 === state.candidateSha256});
      if (state.claimed) {
        let recoverySha256 = null, recoveryError = null;
        try {recoverySha256 = sha(await readFile(state.recovery));} catch (caught) {recoveryError = caught.message;}
        recoveries.push({path: state.recoveryPath, sha256: recoverySha256, error: recoveryError, claimedSha256: state.recoverySha256, originalSha256: state.originalSha256, originalMatched: recoverySha256 === state.originalSha256, published: state.published});
      }
    }
    const afterExpected = {...evidence.manifest.sourceHashes};
    for (const state of states) afterExpected[state.path] = state.candidateSha256;
    try {sourceAfter = await checkSource(afterExpected);} catch (error) {postVerificationErrors.push({gate: 'sourceAfter', error: error.message}); failure ??= error.message;}
    try {bindingsAfter = await evidence.reader.recheck();} catch (error) {postVerificationErrors.push({gate: 'bindingsAfter', error: error.message}); failure ??= error.message;}
    if (observed.some(o => !o.matchesCandidate || o.error)) failure ??= 'EXACT_EIGHT_DESTINATIONS_NOT_PUBLISHED';
    if (recoveries.length !== 8 || recoveries.some(r => r.error || !r.originalMatched || r.sha256 !== r.claimedSha256)) failure ??= 'EXACT_EIGHT_ORIGINAL_RECOVERIES_REQUIRED';
    const observations = new Map(observed.map(o => [o.path, o]));
    const changed = states.filter(s => s.published), fullPromotion = failure === null && changed.length === 8 && sourceAfter !== null && bindingsAfter !== null;
    const report = {startedAt, finishedAt: new Date().toISOString(), ownerDecision: {path: ownerPath, sha256: ownerHash}, packet: packetBinding, decodedGallery, candidateBundleSha256: evidence.candidateBundleSha256,
      status: fullPromotion ? 'complete' : 'failed', failure, cleanupErrors, postVerificationErrors, recoveryDirectory,
      changedImages: changed.map(s => ({path: s.path, originalSha256: s.originalSha256, expectedCandidateSha256: s.candidateSha256, currentSha256: observations.get(s.path).currentSha256, matchesCandidate: observations.get(s.path).matchesCandidate})),
      retainedRecoveries: recoveries, claimedWithoutPublication: states.filter(s => s.claimed && !s.published).map(s => ({path: s.path, recoveryPath: s.recoveryPath, recoverySha256: s.recoverySha256, observedDestination: observations.get(s.path)})),
      remainingImages: states.filter(s => !s.published).map(s => s.path), observedDestinations: observed, sourceAfter, bindingsAfter,
      validatedBindings: [...evidence.reader.boundHashes].map(([path, sha256]) => ({path, sha256})),
      fullPromotion, publishedImageCount: changed.length, sourceEdits: 0, comparatorEdits: 0, fixturePermissionEdits: 0, ownerAcceptanceCriteriaChanged: 0,
      boundary: 'Exactly eight later owner-approved visual PNG replacements. All five source fixes, the earlier 83-image decision and three accepted criteria are preserved. A fresh approved-image full suite is still required. No installed/runtime/native/MFA/delivery/contention/load, additional owner acceptance, production or billing approval is inferred.'};
    try {await result.truncate(0); await result.write(JSON.stringify(report, null, 2) + '\n', 0, 'utf8');}
    finally {await result.close();}
  }
  if (failure) throw Error('PARTIAL_PROMOTION_REQUIRES_NEW_REVIEWED_ATTEMPT:' + failure);
  console.log(JSON.stringify({promoted: 8, criteriaAccepted: 0, requiresFreshVerification: true, recoveryDirectory}));
}
