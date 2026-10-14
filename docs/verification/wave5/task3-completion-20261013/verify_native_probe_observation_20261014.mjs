import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const evidence=[];
async function read(relative,expected){const b=await fs.readFile(path.join(root,relative));if(expected)assert.equal(sha(b),expected);
 evidence.push({path:relative,bytes:b.length,sha256:sha(b)});return b;}
const relative='docs/verification/wave5/keyboard-audit-20261014/actual-probe-input-observation-a3.json';
const observation=JSON.parse(await read(relative,'d1454ed40d675b15ada96c3004826d099b1cf62f4dc5fe2ada806df283727672'));
await read(observation.probeExecutable,observation.probeExecutableSha256);
assert.equal(observation.trials.length,6);assert.equal(observation.actualFocusedFindings.singleKText,'k');
assert.equal(observation.actualFocusedFindings.singleKLogicalId,'0x6b');
assert.equal(observation.actualFocusedFindings.controlKCounter,0);
assert.equal(observation.actualFocusedFindings.controlSynthesizedKeyUpBeforeK,true);
assert.equal(observation.actualFocusedFindings.controlStateOnKDown,false);
assert.equal(observation.actualFocusedFindings.physicalKeysAllCollapseToSameUsage,true);
assert.equal(observation.actualFocusedFindings.typeTextFinanceResult,'k');
assert.equal(observation.rawWindowsScanCodesCaptured,false);assert.equal(observation.productSourceChanged,false);
assert.equal(observation.authenticatedNative,false);assert.equal(observation.fullNativeKeyboardAccepted,false);
const report={kind:'independent-saved-native-keyboard-probe-observation-review',reviewedAt:new Date().toISOString(),
 actualSavedObservationIntegrityPassed:true,standaloneNativeReceiverBuilt:true,actualTrialCount:6,
 automatedChordControlLost:true,automatedTextEntryNotEstablished:true,
 inference:'Same physical identity and synthesized Control-up before K in the focused standalone receiver corroborate an automation/Flutter input compatibility issue.',
 humanJentraShortcutFailureEstablished:false,productShortcutChangeJustified:false,
 rawNativeScanCodeEvidencePresent:false,authenticatedWindowsAcceptance:false,fullNativeKeyboardAcceptance:false,
 nativeRestartRecoveryAcceptance:false,productionReleaseReady:false,reviewerSdkJobs:0,reviewerNativeActions:0,evidence};
const b=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'native-keyboard-independent-observation-20261014.json');
await fs.writeFile(output,b,{flag:'wx'});process.stdout.write(JSON.stringify({passed:true,path:path.relative(root,output).replaceAll('\\','/'),sha256:sha(b)})+'\n');
