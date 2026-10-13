// Persist only the actual browser observations supplied by root in this turn.
// This recorder does not operate a browser, create a decision, or run an SDK.
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const sha=raw=>createHash('sha256').update(raw).digest('hex');
const must=(ok,message)=>{if(!ok)throw Error(message);};
const pins=[
  {path:base+'golden-owner-review-20261010-r5.json',sha256:'f1c0d705106fa3516748d7484b7747dd431e87ec27992990fc2ee1fe807a8fa7'},
  {path:base+'preview-guidance-gallery-verification-20261010-r5.json',sha256:'a8e0c2fb347f738226a555d92578c56bbfb7fcb690b51a8dedad26497ff2bae6'},
];
const values=[];
for(const pin of pins){const raw=await readFile(path.join(root,pin.path));must(sha(raw)===pin.sha256,'ACTUAL_REVIEW_BINDING_CHANGED');values.push(JSON.parse(raw));}
const [packet,decoded]=values;
must(packet.imageCount===8&&packet.embeddedImages===24&&decoded.verified===true&&decoded.embeddedImages===24&&
  decoded.packet.path===pins[0].path&&decoded.packet.sha256===pins[0].sha256&&
  packet.candidateBundleSha256==='91069e594cf9f34b062806f7efd19b7f3f9d0133285c5c39794557dc474a9cf4'&&
  packet.reviewSha256==='7900babfc98e362e2d5b2589b7b4d4aa7e29a8064628e8a526fd729a685f8280','EXACT_ACTUAL_EIGHT_IMAGE_REVIEW_REQUIRED');
const gallery=await readFile(path.join(root,packet.html.path));
must(sha(gallery)===packet.html.sha256&&gallery.length===packet.html.bytes,'PUBLISHED_HTML_CHANGED');
const record={kind:'actual-preview-guidance-browser-observations',revision:'r5',recordedAt:new Date().toISOString(),
  provider:'mcp__cua_repl',browser:{id:'2',name:'Codex In-app Browser',tabId:'2',url:'http://127.0.0.1:8777/',title:'Jentra OS · Preview guidance review r5'},
  packet:pins[0],decodedGallery:pins[1],html:packet.html,candidateBundleSha256:packet.candidateBundleSha256,reviewSha256:packet.reviewSha256,
  observedControls:[
    {action:'Create visible tab after moving the exact loopback-only viewer outside the socket sandbox',observed:'Published title, exact bundle/core hashes, eight comparison choices and owner acceptance 3/109 were returned by the browser accessibility API',result:'pass'},
    {action:'Click Side by side on the initial setup_1024_dark_comfortable case',observed:'Current approved image and Proposed candidate are both labelled for the selected first case',result:'pass'},
    {action:'Select the eighth warehouse_setup_form comparison',observed:'Heading is 8 / 8 · warehouse_setup_form, both image labels and approved/candidate hashes change to the exact selected form',result:'pass'},
    {action:'Click Difference for warehouse_setup_form',observed:'Difference is selected and the displayed image is labelled diff · warehouse_setup_form',result:'pass'},
    {action:'Return to Side by side and capture the actual browser state and screenshot',observed:'Both warehouse images render under Current approved image and Proposed candidate with the exact bundle/core hashes visible',result:'pass'},
    {action:'Click Next from the eighth case',observed:'The heading wraps to 1 / 8 · setup_1024_dark_comfortable and both image labels/hashes match that case',result:'pass'},
    {action:'Click Previous from the first case',observed:'The heading returns to 8 / 8 · warehouse_setup_form and both image labels/hashes match that case',result:'pass'},
  ],
  preservedFailures:[
    {action:'First in-app-browser navigation while the viewer was sandboxed',result:'failed',diagnostic:'net::ERR_CONNECTION_TIMED_OUT'},
    {action:'Sandboxed HEAD request, actual exec chunk d707ea and exit chunk 08d136',result:'failed',actualExitCode:1,diagnostic:'An attempt was made to access a socket in a way forbidden by its access permissions. (127.0.0.1:8777)'},
    {action:'HEAD request outside the sandbox to the first sandboxed listener, actual exit chunk 512fdf',result:'failed',actualExitCode:1,diagnostic:'The request was canceled due to the configured HttpClient.Timeout of 8 seconds elapsing.'},
  ],
  recovery:{oldOwnedViewerSession:'88211',oldViewerStoppedUsingExactSession:true,oldViewerExitCode:1,newOwnedViewerSession:'47920',
    addressUnchanged:'127.0.0.1:8777',servedFileUnchanged:packet.html.path,otherServersOrSessionsTouched:false,broaderNetworkAddressExposed:false},
  browserScreenshotCaptured:true,browserScreenshotPersistedToWorkspace:false,
  independentRenderReview:{rootCandidateImagesInspected:8,peerCandidateImagesInspected:8,peerDifferenceImagesInspected:8,
    finding:'The six normal setup differences are limited to the Preview badge and description. At 200% text the additional description line moves the cards down; the guidance and Create account remain readable in the captured viewport. The warehouse changes are limited to Preview descriptions and its wider Save preview example action, with HQ · Head Office visible.',
    boundary:'Controlled Flutter renders and visible viewport inspection; no additional owner acceptance or full native claim.'},
  ownerDecisionsSubmitted:0,approvedImagesChanged:false,ownerAcceptedCriteriaChanged:0,authenticatedNative:false,nativeKeyboardVerified:false,
  SDKJobsExecuted:false,SupabaseOperations:false,privateSecretsRead:false,acceptanceStoresTouched:false,
  boundary:'Actual interactions with the self-contained image-review page only. These browser observations do not verify the accounting application, authenticate a user, approve a baseline, accept a criterion or establish an installed runtime/native/MFA/delivery/model/contention/load gate.'};
const output=base+'preview-guidance-browser-observations-20261010-r5.json';
const raw=Buffer.from(JSON.stringify(record,null,2)+'\n');
await writeFile(path.join(root,output),raw,{flag:'wx'});
must(sha(await readFile(path.join(root,output)))===sha(raw),'ACTUAL_BROWSER_OBSERVATION_RECORD_DRIFT');
console.log(JSON.stringify({output,sha256:sha(raw),observedControls:record.observedControls.length,preservedFailureAttempts:record.preservedFailures.length,
  ownerDecisionsSubmitted:0,approvedImagesChanged:false,authenticatedNative:false}));
