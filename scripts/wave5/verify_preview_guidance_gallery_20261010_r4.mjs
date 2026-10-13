// Read-only by default. --write records the actual decoded published gallery.
// This is artifact integrity, not visual owner acceptance or native UI testing.
import {readFile, writeFile} from 'node:fs/promises';
import {inflateSync} from 'node:zlib';
import path from 'node:path';
import {
  auditEight, auditPacket, base, checkSource, must, root, sha,
} from './preview_guidance_review_inputs_20261010_r4.mjs';

const mode = process.argv[2] ?? 'check';
must(['check','--write'].includes(mode) && process.argv.length <= 3, 'EXACT_GALLERY_VERIFICATION_MODE_REQUIRED');
const evidence = await auditEight(), {packet, binding} = await auditPacket(evidence);
const htmlBytes = await evidence.reader.readBound(packet.html.path, packet.html.sha256), html = htmlBytes.toString('utf8');
const payload = html.match(/<script id="review-data" type="application\/json">([\s\S]*?)<\/script>/)?.[1];
must(payload, 'SELF_CONTAINED_REVIEW_DATA_REQUIRED');
const data = JSON.parse(payload);
must(data.reviewSha256 === packet.reviewSha256 && data.candidateBundleSha256 === evidence.candidateBundleSha256 && data.cases?.length === 8, 'EMBEDDED_REVIEW_PACKET_CHANGED');
const core = {...data}; delete core.reviewSha256; delete core.cases;
must(sha(Buffer.from(JSON.stringify(core))) === packet.reviewSha256, 'EMBEDDED_REVIEW_CORE_HASH_MISMATCH');
must(!/<(?:link|iframe|object|embed)\b/i.test(html) && !/<(?:script|img)\b[^>]*\bsrc\s*=/i.test(html) && !/\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\s*\(/.test(html), 'NETWORK_ASSET_OR_REQUEST_CODE_FOUND');
must(html.includes("connect-src 'none'") && html.includes('img-src data:') && html.includes("font-src 'none'") && html.includes("form-action 'none'"), 'NO_NETWORK_CSP_REQUIRED');
const scriptBlocks = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
must(scriptBlocks.length === 2, 'EXACT_DATA_AND_RENDER_SCRIPT_REQUIRED');
const renderScript = scriptBlocks.find(match => !match[1].includes('application/json'))?.[2];
must(renderScript && !renderScript.includes('localStorage') && !renderScript.includes('sessionStorage'), 'READ_ONLY_REVIEW_RENDER_SCRIPT_REQUIRED');
// Compile the inline script for syntax only; do not execute a mock browser DOM.
new Function(renderScript);
const crcTable = new Uint32Array(256);
for (let n=0;n<256;n++) {let c=n;for(let k=0;k<8;k++)c=(c&1)?0xedb88320^(c>>>1):c>>>1;crcTable[n]=c>>>0;}
function crc32(bytes) {let crc=0xffffffff;for(const b of bytes)crc=crcTable[(crc^b)&255]^(crc>>>8);return (crc^0xffffffff)>>>0;}
function decodePng(raw) {
  must(raw.length >= 33 && raw.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])), 'PNG_REQUIRED');
  let offset=8, width, height, channels, headerCount=0, endCount=0;const idat=[];
  while(offset<raw.length) {
    must(offset+12<=raw.length, 'TRUNCATED_PNG_CHUNK');
    const length=raw.readUInt32BE(offset),type=raw.toString('ascii',offset+4,offset+8),end=offset+12+length;
    must(end<=raw.length && crc32(raw.subarray(offset+4,offset+8+length))===raw.readUInt32BE(offset+8+length), 'PNG_CHUNK_LENGTH_OR_CRC_INVALID');
    const contents=raw.subarray(offset+8,offset+8+length);
    if(type==='IHDR') {headerCount++;must(offset===8&&length===13,'EXACT_FIRST_IHDR_REQUIRED');width=contents.readUInt32BE(0);height=contents.readUInt32BE(4);channels=contents[9]===6?4:contents[9]===2?3:contents[9]===0?1:contents[9]===4?2:0;must(width>0&&height>0&&width<=10000&&height<=10000&&contents[8]===8&&channels>0&&contents[10]===0&&contents[11]===0&&contents[12]===0,'SUPPORTED_8BIT_NONINTERLACED_PNG_REQUIRED');}
    else if(type==='IDAT')idat.push(contents);
    else if(type==='IEND') {endCount++;must(length===0&&end===raw.length,'EXACT_FINAL_IEND_REQUIRED');}
    offset=end;
  }
  must(headerCount===1&&endCount===1&&idat.length>0,'PNG_HEADER_DATA_END_REQUIRED');
  const stride=width*channels,scanlines=inflateSync(Buffer.concat(idat)),pixels=Buffer.alloc(stride*height);
  must(scanlines.length===(stride+1)*height,'DECODED_SCANLINE_BYTE_COUNT_MISMATCH');
  for(let row=0;row<height;row++) {
    const filter=scanlines[row*(stride+1)];must(filter<=4,'PNG_FILTER_INVALID');
    for(let x=0;x<stride;x++) {
      const i=row*stride+x,left=x>=channels?pixels[i-channels]:0,above=row>0?pixels[i-stride]:0,upperLeft=row>0&&x>=channels?pixels[i-stride-channels]:0;
      let predictor=0;
      if(filter===1)predictor=left;else if(filter===2)predictor=above;else if(filter===3)predictor=Math.floor((left+above)/2);else if(filter===4){const p=left+above-upperLeft,a=Math.abs(p-left),b=Math.abs(p-above),c=Math.abs(p-upperLeft);predictor=a<=b&&a<=c?left:b<=c?above:upperLeft;}
      pixels[i]=(scanlines[row*(stride+1)+1+x]+predictor)&255;
    }
  }
  return {width,height,channels,decodedBytes:pixels.length,pixelSha256:sha(pixels)};
}
const decoded=[];
for(let i=0;i<data.cases.length;i++) {
  const row=data.cases[i],expected=evidence.cases[i],metadata={...row};delete metadata.approved;delete metadata.candidate;delete metadata.diff;
  must(JSON.stringify(metadata)===JSON.stringify(expected),'EMBEDDED_IMAGE_METADATA_MISMATCH');
  for(const [kind,expectedHash] of [['approved',expected.approvedSha256],['candidate',expected.candidateSha256],['diff',expected.diffSha256]]) {
    const uri=row[kind];must(/^data:image\/png;base64,[A-Za-z0-9+/]+={0,2}$/.test(uri),'CANONICAL_EMBEDDED_PNG_DATA_URI_REQUIRED');
    const base64=uri.slice('data:image/png;base64,'.length),raw=Buffer.from(base64,'base64');must(raw.toString('base64')===base64&&sha(raw)===expectedHash,'EMBEDDED_PNG_BYTE_HASH_MISMATCH');
    const pixels=decodePng(raw);must(JSON.stringify([pixels.width,pixels.height])===JSON.stringify(expected.dimensions),'EMBEDDED_IMAGE_DIMENSIONS_CHANGED');
    decoded.push({stem:row.stem,kind,sha256:sha(raw),bytes:raw.length,...pixels});
  }
}
must(decoded.length===24&&(html.match(/data:image\/png;base64,/g)??[]).length===24,'EXACT_24_EMBEDDED_IMAGES_REQUIRED');
await evidence.reader.recheck();
await checkSource(evidence.manifest.sourceHashes);
const result={kind:'decoded-eight-image-gallery-integrity',revision:'r4',checkedAt:new Date().toISOString(),verified:true,packet:binding,gallery:packet.html,reviewSha256:packet.reviewSha256,candidateBundleSha256:evidence.candidateBundleSha256,imageCases:8,embeddedImages:24,allDecodedImagesMatchBoundSourceBytes:true,inlineRenderScriptSyntaxValid:true,noExternalAssetOrNetworkCode:true,decodedImages:decoded,currentSourceMatchesFrozenInputs:true,approvedRepositoryImagesChanged:false,actualOwnerDecisionsRecorded:0,ownerAcceptanceCriteriaChanged:0,verifier:{path:'scripts/wave5/verify_preview_guidance_gallery_20261010_r4.mjs',sha256:sha(await readFile(path.join(root,'scripts/wave5/verify_preview_guidance_gallery_20261010_r4.mjs')))},boundary:'Decoded file integrity and script syntax only. Interactive browser behavior, visual owner acceptance, authenticated native and runtime gates remain separate.'};
if(mode==='--write') {
  const output=base+'preview-guidance-gallery-verification-20261010-r4.json',summary=output.replace(/\.json$/,'.md');
  const markdown=`# Eight-image gallery integrity — r4\n\nThe exact [gallery](<${path.join(root,packet.html.path).replaceAll('\\','/')}>), SHA-256 ${packet.html.sha256}, contains 8 comparisons and 24 embedded PNGs. All 24 images were decoded, their CRCs and byte hashes checked, and their dimensions and pixel hashes recorded. They match the exact approved backups, candidates and diagnostic differences in the owner packet.\n\nThe inline script compiles, no external asset or network request code is present, and the CSP disables network access. This verifies file integrity and syntax; it does not report interactive browser acceptance or approve any image. No approved root PNG or owner acceptance store was changed.\n\nReview core SHA-256: ${packet.reviewSha256}\n\nCandidate bundle SHA-256: ${evidence.candidateBundleSha256}\n\n${result.boundary}\n`;
  await writeFile(path.join(root,summary),markdown,{flag:'wx'});
  must(sha(await readFile(path.join(root,summary)))===sha(Buffer.from(markdown)),'PUBLISHED_GALLERY_SUMMARY_DRIFT');
  await evidence.reader.recheck();
  await checkSource(evidence.manifest.sourceHashes);
  result.summary={path:summary,sha256:sha(Buffer.from(markdown))};
  const resultBytes=Buffer.from(JSON.stringify(result,null,2)+'\n');
  await writeFile(path.join(root,output),resultBytes,{flag:'wx'});
  must(sha(await readFile(path.join(root,output)))===sha(resultBytes),'PUBLISHED_GALLERY_RESULT_DRIFT');
  console.log(JSON.stringify({verified:true,output,summary,embeddedImages:24,approvedImagesChanged:false,ownerAcceptanceCriteriaChanged:0}));
} else console.log(JSON.stringify({verified:true,embeddedImages:24,gallerySha256:packet.html.sha256,reviewSha256:packet.reviewSha256,approvedImagesChanged:false,ownerAcceptanceCriteriaChanged:0}));
