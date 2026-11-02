import { readFile, readdir, mkdir, copyFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
const root = process.cwd();
const source = path.resolve(root,process.argv[3] || 'apps/jentra_sales/build/web');
const out = path.resolve(root,process.argv[2] || 'build/sales-release/hosting');
if (!out.startsWith(path.join(root,'build','sales-release')+path.sep)) throw Error('STAGE_MUST_BE_NEW_RELEASE_DIRECTORY');
await mkdir(out, {recursive:false});
await mkdir(path.join(out,'public'));
const files = [];
async function copy(directory='') {
  for (const entry of await readdir(path.join(source,directory),{withFileTypes:true})) {
    const file = [directory,entry.name].filter(Boolean).join('/');
    if(file === '.last_build_id' || file === 'flutter_service_worker.js' || file.endsWith('.symbols')) continue;
    if (/(^|\/)(\.|node_modules)|\.map$|\.env|firebase-adminsdk|service.account/i.test(file)) throw Error('UNEXPECTED_PUBLIC_FILE');
    if (entry.isDirectory()) { await mkdir(path.join(out,'public',file)); await copy(file); }
    else if (entry.isFile()) {
      const bytes=await readFile(path.join(source,file));
      // Supabase's client SDK contains the literal prefix in key validation.
      // Reject credential values while allowing that bare SDK marker.
      if (/sb_secret_[A-Za-z0-9_-]{16,}/.test(bytes.toString('utf8')) || bytes.includes(Buffer.from('-----BEGIN PRIVATE KEY-----'))) throw Error('PRIVILEGED_MATERIAL_REFUSED');
      await copyFile(path.join(source,file),path.join(out,'public',file));
      files.push({path:file,size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
    } else throw Error('REGULAR_FILES_ONLY');
  }
}
await copy();
const downloadRoot = path.join(root,'dist/Jentra-Sales-0.1.0-1-Development');
await mkdir(path.join(out,'public','downloads'));
for (const name of ['Jentra-Sales-0.1.0-1-Development-APK.zip','checksums.sha256','READ-ME.txt']) {
  const bytes=await readFile(path.join(downloadRoot,name));
  const relative=`downloads/${name}`;
  await copyFile(path.join(downloadRoot,name),path.join(out,'public',relative));
  files.push({path:relative,size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
}
for (const config of ['firebase.json','.firebaserc']) await copyFile(path.join(root,'tools/sales-web',config),path.join(out,config));
await writeFile(path.join(out,'public','version.json'),JSON.stringify({name:'Jentra Sales',version:'0.1.0+1',channel:'development',mode:'interactive-preview',liveSalesEnabled:false})+'\n');
const versionIndex = files.findIndex(file=>file.path==='version.json');
if(versionIndex>=0) files.splice(versionIndex,1);
const version=await readFile(path.join(out,'public','version.json'));
files.push({path:'version.json',size:version.length,sha256:createHash('sha256').update(version).digest('hex')});
files.sort((a,b)=>a.path.localeCompare(b.path));
await writeFile(path.join(out,'public-manifest.json'),JSON.stringify({site:'jentra-os-sales',project:'jentra-os',files},null,2)+'\n');
console.log(JSON.stringify({releaseDirectory:out,files:files.length}));
