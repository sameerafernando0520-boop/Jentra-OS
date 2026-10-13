import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
const original='tools/wave5/persistent_setup_20261013_r5.mjs';
let source=await fs.readFile(path.join(root,original),'utf8');
if(hashBytes(source)!=='3318912e74ae08f17647dd506cc360c735b0d9db15df17984fefde79b40ed724')throw Error('EXACT_FAILED_SETUP_SOURCE_REQUIRED');
const replace=(before,after)=>{if(source.split(before).length!==2)throw Error('EXACT_SINGLE_SUCCESSOR_REPLACEMENT_REQUIRED');source=source.replace(before,after);};
replace("/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(publicKey)",
  "/^(?:sb_publishable_[A-Za-z0-9_-]+|[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+)$/.test(publicKey)");
replace("base+'persistent-setup-20261013-r5-'+Date.now()+'/'", "base+'persistent-setup-20261013-r5-a2-'+Date.now()+'/'");
replace("base+'persistent-setup-once-20261013-r5.json'", "base+'persistent-setup-once-20261013-r5-a2.json'");
replace("const keys=selectExistingLegacyKeys((await createPrivateKeyReader(config.ownerToken)()).value),sql=reviewedPausedSetup(source,keys.anon);",
 `const keyRows=(await createPrivateKeyReader(config.ownerToken)()).value;
  const matches=keyRows.filter(row=>typeof row.api_key==='string'&&hashBytes(row.api_key)==='e3ea9ff3f18e6bb24be674430cc494a31c4cd7d92482367b60383b5aedd6fa9d');
  must(matches.length===1,'ONE_EXACT_REVIEWED_PUBLIC_KEY_REQUIRED');
  const reviewedPublicKey=matches[0].api_key,sql=reviewedPausedSetup(source,reviewedPublicKey);
  await save(directory+'01-public-key-binding.json',{exactReviewedDigestMatched:true,expectedSha256:hashBytes(reviewedPublicKey),
   returnedKeyName:matches[0].name,returnedKeyType:matches[0].type??null,keyValuePrinted:false,
   retainedPreviousFailure:'persistent-setup-20261013-r5-1791885065132/99-stop.json',previousWriteIntentAbsent:true});`);
replace('publicKeySha256:hashBytes(keys.anon)', 'publicKeySha256:hashBytes(reviewedPublicKey)');
const destination='tools/wave5/persistent_setup_20261013_r5_a2.mjs';
const handle=await fs.open(path.join(root,destination),'wx');try{await handle.writeFile(source);await handle.sync();}finally{await handle.close();}
process.stdout.write(JSON.stringify({source:destination,sha256:hashBytes(source),exactReviewedPublicKeyDigestGuardPreserved:true,
 previousAttemptSourcePreserved:true,networkCalls:0})+'\n');
