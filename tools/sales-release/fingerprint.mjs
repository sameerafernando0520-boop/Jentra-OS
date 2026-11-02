import { readFile, readdir, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
const root = process.cwd();
const selected = ['pubspec.yaml','pubspec.lock','apps/jentra_sales/pubspec.yaml'];
async function walk(directory) {
  for (const entry of await readdir(path.join(root,directory), {withFileTypes:true})) {
    const relative = `${directory}/${entry.name}`;
    if (/^(build|\.dart_tool|\.gradle|\.idea)$/.test(entry.name) || /local.properties|\.log$/.test(entry.name)) continue;
    if (entry.isDirectory()) await walk(relative); else if (entry.isFile()) selected.push(relative);
  }
}
for (const directory of ['apps/jentra_sales/lib','apps/jentra_sales/web','apps/jentra_sales/android/app/src/main','packages/jentra_domain/lib','packages/jentra_design_system/lib','packages/jentra_design_system/assets']) await walk(directory);
selected.push('apps/jentra_sales/android/app/build.gradle.kts','apps/jentra_sales/android/gradle.properties','packages/jentra_domain/pubspec.yaml','packages/jentra_design_system/pubspec.yaml');
selected.push('apps/jentra_sales/android/settings.gradle.kts','apps/jentra_sales/android/build.gradle.kts','apps/jentra_sales/android/gradle/wrapper/gradle-wrapper.properties','build/sales-release/public-client.json');
const files = [];
for (const file of [...new Set(selected)].sort()) {
  const bytes = await readFile(path.join(root,file));
  files.push({path:file, size:bytes.length, sha256:createHash('sha256').update(bytes).digest('hex')});
}
const digest = createHash('sha256').update(JSON.stringify(files)).digest('hex');
await mkdir('build/sales-release',{recursive:true});
const result = {version:'0.1.0+1', channel:'development', sourceSha256:digest, files};
const output = process.argv[2] || 'build/sales-release/input-manifest.json';
await writeFile(output,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({sourceSha256:digest, files:files.length, output}));
