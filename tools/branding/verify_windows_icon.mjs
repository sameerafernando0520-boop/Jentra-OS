// Read PE resources without loading or running the application.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const exePath = path.resolve(root, process.argv[2] ??
  'apps/jentra_desktop/build/windows/x64/runner/Release/jentra_desktop.exe');
const iconPath = path.join(root, 'apps/jentra_desktop/windows/runner/resources/app_icon.ico');
const [exe, ico] = await Promise.all([readFile(exePath), readFile(iconPath)]);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
assert.equal(exe.toString('ascii', 0, 2), 'MZ');
const pe = exe.readUInt32LE(0x3c);
assert.equal(exe.readUInt32LE(pe), 0x00004550);
const sectionCount = exe.readUInt16LE(pe + 6);
const optional = pe + 24;
const magic = exe.readUInt16LE(optional);
assert.ok(magic === 0x20b || magic === 0x10b);
const sectionTable = optional + exe.readUInt16LE(pe + 20);
function offset(rva) {
  for (let i = 0; i < sectionCount; i++) {
    const entry = sectionTable + i * 40;
    const start = exe.readUInt32LE(entry + 12);
    const size = Math.max(exe.readUInt32LE(entry + 8), exe.readUInt32LE(entry + 16));
    if (rva >= start && rva < start + size) {
      return exe.readUInt32LE(entry + 20) + rva - start;
    }
  }
  throw new Error('Resource RVA has no PE section.');
}
const directories = optional + (magic === 0x20b ? 112 : 96);
const resourceRoot = offset(exe.readUInt32LE(directories + 16));
function entries(relative) {
  const start = resourceRoot + relative;
  const count = exe.readUInt16LE(start + 12) + exe.readUInt16LE(start + 14);
  return Array.from({length: count}, (_, i) => {
    const entry = start + 16 + i * 8;
    const name = exe.readUInt32LE(entry);
    const value = exe.readUInt32LE(entry + 4);
    return {id: name & 0x80000000 ? null : name, directory: Boolean(value & 0x80000000), relative: value & 0x7fffffff};
  });
}
function resource(kind, id) {
  const type = entries(0).find(entry => entry.id === kind && entry.directory);
  assert.ok(type, `Missing PE resource type ${kind}.`);
  const item = entries(type.relative).find(entry => entry.id === id && entry.directory);
  assert.ok(item, `Missing PE resource ${kind}/${id}.`);
  const language = entries(item.relative).find(entry => !entry.directory);
  assert.ok(language, 'Missing resource language.');
  const data = resourceRoot + language.relative;
  const start = offset(exe.readUInt32LE(data));
  return exe.subarray(start, start + exe.readUInt32LE(data + 4));
}
assert.equal(ico.readUInt16LE(2), 1);
const expected = new Map();
for (let i = 0; i < ico.readUInt16LE(4); i++) {
  const entry = 6 + i * 16;
  const size = ico[entry] || 256;
  const start = ico.readUInt32LE(entry + 12);
  expected.set(size, ico.subarray(start, start + ico.readUInt32LE(entry + 8)));
}
const groupType = entries(0).find(entry => entry.id === 14 && entry.directory);
assert.ok(groupType, 'Missing PE icon group.');
const iconGroups = entries(groupType.relative).filter(entry => entry.directory);
// Runner.rc uses 101; the C# installer compiler assigns a different group ID.
const groupResourceId = process.argv[3] === undefined
  ? (iconGroups.find(entry => entry.id === 101)?.id ??
      (iconGroups.length === 1 ? iconGroups[0].id : undefined))
  : Number(process.argv[3]);
assert.ok(Number.isInteger(groupResourceId), 'Specify an unambiguous icon group ID.');
const group = resource(14, groupResourceId);
assert.equal(group.readUInt16LE(2), 1);
assert.equal(group.readUInt16LE(4), expected.size);
const verified = [];
for (let i = 0; i < group.readUInt16LE(4); i++) {
  const entry = 6 + i * 14;
  const size = group[entry] || 256;
  assert.equal(group[entry + 1] || 256, size);
  const image = resource(3, group.readUInt16LE(entry + 12));
  assert.deepEqual(image, expected.get(size), `Executable icon differs at ${size}px.`);
  verified.push(size);
}
console.log(JSON.stringify({
  executable: path.relative(root, exePath), exeSha256: sha256(exe),
  iconSha256: sha256(ico), groupResourceId,
  embeddedFramesVerified: verified, matchesSourceIcon: true,
}, null, 2));
