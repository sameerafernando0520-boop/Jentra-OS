// Root received the direct human reply in this chat before this record was made.
// This script records that genuine reply for exactly eight already reviewed PNGs.
// It does not infer authority from a file or accept any requirement criterion.
import {open, readFile} from 'node:fs/promises';
import path from 'node:path';
import {
  auditEight, auditPacket, auditDecodedGallery, checkSource, must, ownerPath, root, sha,
} from './preview_guidance_review_inputs_20261010_r5.mjs';

must(process.argv.length === 2, 'NO_OWNER_RECORD_ARGUMENTS_ALLOWED');
const evidence = await auditEight();
const {packet, binding} = await auditPacket(evidence);
await auditDecodedGallery(evidence, packet, binding);
const approvedBundle = '91069e594cf9f34b062806f7efd19b7f3f9d0133285c5c39794557dc474a9cf4';
must(evidence.candidateBundleSha256 === approvedBundle && evidence.cases.length === 8 &&
  binding.sha256 === 'f1c0d705106fa3516748d7484b7747dd431e87ec27992990fc2ee1fe807a8fa7' &&
  packet.reviewSha256 === '7900babfc98e362e2d5b2589b7b4d4aa7e29a8064628e8a526fd729a685f8280',
  'EXACT_HUMAN_REVIEW_BINDINGS_REQUIRED');
const messageVerbatim = 'Approve all 8 proposed images (Recommended)';
const record = {
  kind: 'direct-human-owner-decision',
  authorizationKind: 'direct-human-message',
  submittedByOwner: true,
  recordedAt: new Date().toISOString(),
  reviewSha256: packet.reviewSha256,
  candidateBundleSha256: approvedBundle,
  packet: binding,
  provenanceNote: 'The human replied to the exact eight-image question in this chat. messageId is the verbatim questionItemId supplied by the reply UI; an opaque platform message ID was not exposed. receivedAt is the root observation timestamp, not an inferred earlier send time.',
  messageVerbatim,
  messageSha256: sha(Buffer.from(messageVerbatim)),
  sourceMessage: {
    role: 'user',
    messageId: '["request_user_input_async","call_RfJdzMiD1HhBGJkOZ4XlUrEg",0]',
    threadId: '01a121e1-81f0-76c1-8060-699f36ec225e',
    receivedAt: '2026-10-10T15:06:45Z',
  },
  question: 'I tested the eight later Preview guidance images and their differences. Please review [the eight-image comparisons](http://127.0.0.1:8777/) or [the saved HTML](<C:/Users/sheha/Desktop/Jentra OS/dist/Jentra OS Preview Guidance Review 20261010 r5.html>). Do you approve replacing exactly these eight approved baselines with the proposed candidates? Bundle SHA-256: 91069e594cf9f34b062806f7efd19b7f3f9d0133285c5c39794557dc474a9cf4. Your earlier approval covered the original 83 candidates; these eight contain later fixes and need a separate image decision. This does not approve runtime installation or additional requirement acceptance.',
  images: evidence.cases.map(row => ({
    approvedPath: row.approvedPath,
    candidateSha256: row.candidateSha256,
    decision: 'accept',
  })),
  ownerAcceptanceCriteriaChanged: 0,
  runtimeInstallationApproved: false,
  boundary: 'Exactly eight later approved Preview guidance PNG replacements. The original 83-image decision and three criterion acceptances remain separate and preserved. No additional criterion, runtime installation, authenticated native, MFA, delivery, model usage, contention, load, production or real billing approval is inferred.',
};
await evidence.reader.recheck();
await checkSource(evidence.manifest.sourceHashes);
const raw = Buffer.from(JSON.stringify(record, null, 2) + '\n');
const output = await open(path.resolve(root, ownerPath), 'wx');
try {await output.writeFile(raw); await output.sync();} finally {await output.close();}
must(sha(await readFile(path.resolve(root, ownerPath))) === sha(raw), 'OWNER_RECORD_WRITE_DRIFT');
console.log(JSON.stringify({path: ownerPath, sha256: sha(raw), imageDecisions: 8,
  criteriaAccepted: 0, runtimeInstallationApproved: false, approvedImagesChanged: false}));
