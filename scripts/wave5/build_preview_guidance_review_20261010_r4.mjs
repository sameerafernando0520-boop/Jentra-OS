// Default is read-only. --write publishes only this new exact eight-image packet.
import {lstat, open, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {
  auditEight, checkSource, galleryPath, markdownPath, must, packetPath,
  publicationPath, root, sha,
} from './preview_guidance_review_inputs_20261010_r4.mjs';
import {renderGuidanceGallery} from './preview_guidance_gallery_20261010_r4.mjs';

const mode = process.argv[2] ?? 'check';
must(['check','--write'].includes(mode) && process.argv.length <= 3, 'EXACT_REVIEW_MODE_REQUIRED');
const evidence = await auditEight();
const refs = [...evidence.reader.boundHashes].map(([path, sha256]) => ({path, sha256}));
const core = {
  generatedAt: new Date().toISOString(),
  title: 'Jentra OS Preview guidance: exact eight-image owner review',
  candidateBundleSha256: evidence.candidateBundleSha256,
  sourceManifest: evidence.sourceManifest,
  candidateResult: evidence.candidateResult,
  strictCandidateResult: evidence.strictCandidateResult,
  approvedControl: evidence.approvedControl,
  images: evidence.cases,
  stages: evidence.stages.map(s => ({stage: s.stage, record: s.record, log: s.log, counts: s.counts, actualTestIdentities: s.actualTestIdentities})),
  earlierImageApprovalPreserved: 83,
  existingOwnerAcceptedCriterionIds: ['AC-551','AC-552','AC-553'],
  ownerAcceptanceCount: 3,
  exactImageDecisionsPending: 8,
  refs,
  boundary: 'Exactly eight later Preview guidance image candidates await a new direct owner decision. The earlier 83-image approval and three accepted criteria are preserved. This packet authorizes no runtime installation, authenticated native/MFA, delivery, contention/load, additional criterion acceptance, production or real billing.',
};
const reviewSha256 = sha(Buffer.from(JSON.stringify(core)));
const html = Buffer.from(renderGuidanceGallery(core, reviewSha256, evidence.embedded));
const controls = evidence.stages.find(s => s.stage === 'goldens83');
const focused = evidence.stages.find(s => s.stage === 'focusedNonGolden');
const markdown = Buffer.from(`# Jentra OS Preview guidance owner review — r4\n\nEight later visual candidates are awaiting a separate owner decision. The earlier 83 replacements are preserved; AC-551, AC-552 and AC-553 remain the only three accepted criteria.\n\nThe Preview setup header now says Development preview and explains that examples stay in memory and reset when refreshed. Its form action says Save preview example. A configured app without a setup gateway explains the missing connection and disables server confirmation. The connected-gateway presentation and capability gates remain unchanged. Procurement explains why accounting actions are unavailable; the Finance landing identifies its overview and unavailable posting/report controls.\n\nActual r4 evidence: scoped analysis completed successfully; ${focused.counts.passed} focused checks passed; the strict previously approved 83-image subset passed ${controls.counts.passed} and failed exactly ${controls.counts.failed} intended guidance comparisons. The isolated eight-image generation and subsequent strict candidate comparison each passed 8 with no failures or skips. These are controlled Flutter checks, separate from authenticated native and installed accounting behavior.\n\nReview [the self-contained gallery](<${path.join(root, galleryPath).replaceAll('\\', '/')}>). It embeds exactly 24 PNGs and makes no network requests. Every proposed replacement is listed below.\n\n| Candidate | Test | Approved SHA-256 | Candidate SHA-256 |\n|---|---|---|---|\n${evidence.cases.map(c => `| ${c.stem} | ${c.testIdentity.replaceAll('|','\\|')} | ${c.approvedSha256} | ${c.candidateSha256} |`).join('\n')}\n\nCandidate bundle SHA-256: ${evidence.candidateBundleSha256}\n\nReview core SHA-256: ${reviewSha256}\n\n${core.boundary}\n`);
const packet = {
  kind: 'exact-eight-preview-guidance-owner-review', revision: 'r4',
  ...core, reviewCore: core, reviewSha256,
  html: {path: galleryPath, sha256: sha(html), bytes: html.length},
  markdown: {path: markdownPath, sha256: sha(markdown), bytes: markdown.length},
  imageCount: 8, embeddedImages: 24, allDecisionsInitiallyPending: true,
  actualOwnerDecisionsRecorded: 0,
};
const packetBytes = Buffer.from(JSON.stringify(packet, null, 2) + '\n');
if (mode === 'check') {
  console.log(JSON.stringify({eligibleForExactEightReview: true, approvedImagesChanged: false, ownerDecisionRequired: true, imageCount: 8, embeddedImages: 24, candidateBundleSha256: evidence.candidateBundleSha256, reviewSha256}));
} else {
  const outputs = [
    {path: galleryPath, bytes: html},
    {path: markdownPath, bytes: markdown},
    {path: packetPath, bytes: packetBytes},
  ];
  for (const output of [...outputs, {path: publicationPath}]) {
    try {await lstat(path.join(root, output.path)); throw Error('REVIEW_OUTPUT_ALREADY_EXISTS:' + output.path);}
    catch (error) {if (error.code !== 'ENOENT') throw error;}
  }
  const startedAt = new Date().toISOString(), published = [], postVerificationErrors = [];
  let failure = null;
  const journal = await open(path.join(root, publicationPath), 'wx');
  try {
    await journal.writeFile(JSON.stringify({status: 'in_progress', startedAt, candidateBundleSha256: evidence.candidateBundleSha256, plannedOutputs: outputs.map(o => ({path: o.path, sha256: sha(o.bytes)})), boundary: 'An interrupted publication needs actual output reconciliation; this journal is not a completion claim.'}, null, 2) + '\n');
    for (const output of outputs) {
      await evidence.reader.recheck();
      await checkSource(evidence.manifest.sourceHashes);
      await writeFile(path.join(root, output.path), output.bytes, {flag: 'wx'});
      published.push(output.path);
      must(sha(await readFile(path.join(root, output.path))) === sha(output.bytes), 'PUBLISHED_REVIEW_OUTPUT_DRIFT:' + output.path);
    }
  } catch (error) {failure = error.message;}
  finally {
    const observedOutputs = [];
    for (const output of outputs) {
      let currentSha256 = null, exists = true, error = null;
      try {currentSha256 = sha(await readFile(path.join(root, output.path)));}
      catch (caught) {exists = caught.code !== 'ENOENT'; error = caught.code === 'ENOENT' ? null : caught.message;}
      observedOutputs.push({path: output.path, expectedSha256: sha(output.bytes), currentSha256, exists, error, matchesExpected: currentSha256 === sha(output.bytes)});
    }
    try {await evidence.reader.recheck(); await checkSource(evidence.manifest.sourceHashes);}
    catch (error) {postVerificationErrors.push(error.message); failure ??= error.message;}
    const fullPublication = failure === null && published.length === 3 && observedOutputs.every(o => o.matchesExpected && !o.error);
    if (!fullPublication && !failure) failure = 'EXACT_THREE_REVIEW_OUTPUTS_NOT_PUBLISHED';
    const result = {startedAt, finishedAt: new Date().toISOString(), status: fullPublication ? 'complete' : 'failed', failure, postVerificationErrors, fullPublication, publishedOutputs: published, observedOutputs, candidateBundleSha256: evidence.candidateBundleSha256, reviewSha256, imageCount: 8, embeddedImages: 24, approvedRepositoryImagesChanged: false, actualOwnerDecisionsRecorded: 0, ownerAcceptanceCriteriaChanged: 0, validatedBindings: refs, boundary: core.boundary};
    try {await journal.truncate(0); await journal.write(JSON.stringify(result, null, 2) + '\n', 0, 'utf8');}
    finally {await journal.close();}
  }
  if (failure) throw Error('PARTIAL_REVIEW_PUBLICATION_REQUIRES_NEW_ATTEMPT:' + failure);
  console.log(JSON.stringify({fullPublication: true, packetPath, galleryPath, markdownPath, reviewSha256, candidateBundleSha256: evidence.candidateBundleSha256, embeddedImages: 24}));
}
