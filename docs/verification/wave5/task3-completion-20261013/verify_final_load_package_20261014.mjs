import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
const folder=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(folder,'../../../..');
const base='docs/verification/wave5/task3-load-release-20261013';
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const read=async relative=>{assert.ok(!path.win32.isAbsolute(relative)&&!relative.split('/').includes('..'));
 const bytes=await fs.readFile(path.join(root,relative));return{path:relative,bytes:bytes.length,sha256:sha(bytes),document:JSON.parse(bytes)};};
const ref=({document,...binding})=>binding;
const manifestFile=await read(`${base}/source-manifest-a2.json`),manifest=manifestFile.document;
assert.equal(manifestFile.sha256,'41b2fb69a2bfbd491ac52c740c4a6ba150d29ff948329927a5fdcbbbeeffced0');
assert.equal(manifest.files.length,62);const artifacts=[];
for(const binding of manifest.files){const bytes=await fs.readFile(path.join(root,binding.path));
 assert.equal(sha(bytes),binding.sha256,binding.path);assert.equal(bytes.length,binding.bytes,binding.path);artifacts.push(binding);}
const dependencyFile=await read(`${base}/dependency-source-manifest.json`),dependency=dependencyFile.document;
assert.equal(dependencyFile.sha256,'dc09b9a8ce22b6c1aa06ac182705c1b90e58e0f9fcc229d4746d9f98bd9abd8c');
assert.equal(dependency.files.length,139);assert.equal(dependency.providerSourceFiles.length,5);assert.equal(dependency.publicSourceFiles.length,7);
const wrapper=await import(pathToFileURL(path.join(root,base,'provider_operation_wrapper.mjs')).href);
const sourceCheck=await wrapper.verifyProviderManifestFiles(dependency,file=>fs.readFile(path.join(root,file)));
assert.equal(sourceCheck.verified,true);
const harnessFile=await read('docs/verification/wave5/task3-acceptance-20261013/runtime-harness-review-20261014-acceptance-a1.json');
assert.equal(harnessFile.sha256,'5b86ce5ac1b1fdc5877c96ff8efff6dc6021d9aac02cb2f0dcc1169cb2c5f123');
const harness=harnessFile.document;
for(const binding of [...harness.files,...harness.contractSources]){const bytes=await fs.readFile(path.join(root,binding.path));assert.equal(sha(bytes),binding.sha256);}
const protocolFile=await read(`${base}/protocol-result-a2.json`),protocol=protocolFile.document;
assert.equal(protocolFile.sha256,'7a6b2e1d88ec93efeca5163e193bad25ddc10849207bf077b4a004763a63bd18');
assert.equal(protocol.actualLoadPerformed,false);assert.equal(protocol.actualPostgresConnection,false);assert.equal(protocol.productionReleased,false);
const integrationFile=await read('docs/verification/wave5/task3-completion-20261013/provider-integration-independent-review-20261014-a2.json');
assert.equal(integrationFile.sha256,'170ba1a1a81169dafb322c0a03d537627cee273d7595b2b5351bc8be14d1b0ce');
assert.equal(integrationFile.document.passed,true);assert.equal(integrationFile.document.counts.pass,61);
const named=Object.fromEntries(dependency.providerSourceFiles.map(row=>[path.basename(row.path),row.sha256]));
const driverBindings={routerSha256:named['provider_pg_factory.mjs'],readOnlyDriverSha256:named['postgres_transport.mjs'],
 fixtureDriverSha256:named['fixture_writer.mjs'],dependencyManifestSha256:dependencyFile.sha256};
const report={kind:'primary-independent-current-load-preparation-package-review',reviewedAt:new Date().toISOString(),
 technicalVerdict:'approve exact source-bound helper composition for the existing development protocol when its private and live prerequisites are satisfied',
 artifactBindingsVerified:62,dependencyFilesVerified:139,helperSourceFilesVerified:5,publicImportedSourceFilesVerified:7,
 currentHarnessBindingsVerified:18,driverBindings,independentlyReviewedSourceBindings:driverBindings,
 sourceVerification:sourceCheck,sourceManifest:ref(manifestFile),dependencyManifest:ref(dependencyFile),harness:ref(harnessFile),
 integration:ref(integrationFile),protocol:ref(protocolFile),artifactBindings:artifacts,
 personalHumanExactSourceSignatureClaimed:false,privateInputsRead:false,actualNetworkRequests:0,actualPostgresConnections:0,
 actualLoadPassed:false,authenticatedWindowsPassed:false,productionReleaseReady:false,
 remaining:'Private DB and source-bound provider configuration; genuine session capacity and freshness; authentic complete external capture and quiescence; actual seven races/target workload and production operational evidence.'};
const bytes=Buffer.from(JSON.stringify(report,null,2)+'\n'),output=path.join(folder,'load-package-independent-final-review-20261014.json');
await fs.writeFile(output,bytes,{flag:'wx'});
process.stdout.write(JSON.stringify({approved:true,report:{path:path.relative(root,output).replaceAll('\\','/'),bytes:bytes.length,sha256:sha(bytes)},driverBindings})+'\n');
