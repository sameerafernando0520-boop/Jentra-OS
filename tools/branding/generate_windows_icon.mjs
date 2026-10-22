// Convert the supplied Jentra mark to Windows icon frames; never redraw it.
// Run: node tools/branding/generate_windows_icon.mjs
// Requires sharp, resolved from normal Node modules or the bundled Codex runtime.
import { createHash } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let sharp;
try {
  sharp = require('sharp');
} catch {
  sharp = require(path.join(homedir(), '.cache', 'codex-runtimes',
    'codex-primary-runtime', 'dependencies', 'node', 'node_modules', 'sharp'));
}

const root = fileURLToPath(new URL('../../', import.meta.url));
const sourcePath = path.join(root, 'packages/jentra_design_system/assets/brand/jentra-mark.png');
const iconPath = path.join(root, 'apps/jentra_desktop/windows/runner/resources/app_icon.ico');
const previewPath = path.join(root, 'build/branding/jentra-windows-icon.png');
const sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
// Same transparent-only crop used by JentraBrandMark in brand.dart.
const crop = { left: 246, top: 188, width: 762, height: 924 };
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const source = await readFile(sourcePath);
const sourceHash = digest(source);
const original = await sharp(source).metadata();
if (original.width !== 1254 || original.height !== 1254 || !original.hasAlpha) {
  throw new Error('Unexpected source mark dimensions or transparency; review the crop before regenerating.');
}

const frames = [];
for (const size of sizes) {
  const inner = Math.round(size * 0.9);
  const leading = Math.floor((size - inner) / 2);
  const trailing = size - inner - leading;
  const frame = await sharp(source)
    .extract(crop)
    .resize(inner, inner, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
      kernel: sharp.kernel.lanczos3,
    })
    .extend({
      top: leading, bottom: trailing, left: leading, right: trailing,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .ensureAlpha()
    .png({ compressionLevel: 9, adaptiveFiltering: false, palette: false })
    .toBuffer();
  frames.push(frame);
}

// ICO directory followed by PNG payloads (supported by Windows Vista and newer).
const directory = Buffer.alloc(6 + sizes.length * 16);
directory.writeUInt16LE(0, 0); // Reserved.
directory.writeUInt16LE(1, 2); // ICO, not a cursor.
directory.writeUInt16LE(sizes.length, 4);
let offset = directory.length;
for (let index = 0; index < sizes.length; index++) {
  const entry = 6 + index * 16;
  directory[entry] = sizes[index] === 256 ? 0 : sizes[index];
  directory[entry + 1] = directory[entry];
  directory.writeUInt16LE(1, entry + 4); // Planes.
  directory.writeUInt16LE(32, entry + 6); // RGBA bit depth.
  directory.writeUInt32LE(frames[index].length, entry + 8);
  directory.writeUInt32LE(offset, entry + 12);
  offset += frames[index].length;
}
const icon = Buffer.concat([directory, ...frames]);

// Validate the actual serialized frames before replacing the runner resource.
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
for (let index = 0; index < sizes.length; index++) {
  const entry = 6 + index * 16;
  const length = icon.readUInt32LE(entry + 8);
  const start = icon.readUInt32LE(entry + 12);
  const frame = icon.subarray(start, start + length);
  const metadata = await sharp(frame).metadata();
  if (!frame.subarray(0, 8).equals(pngSignature) ||
      metadata.width !== sizes[index] || metadata.height !== sizes[index] ||
      !metadata.hasAlpha) {
    throw new Error(`Invalid ICO frame at ${sizes[index]} pixels.`);
  }
}
if (digest(await readFile(sourcePath)) !== sourceHash) {
  throw new Error('The source artwork changed during conversion.');
}
await mkdir(path.dirname(previewPath), { recursive: true });
await writeFile(iconPath, icon);
await writeFile(previewPath, frames.at(-1));
console.log(JSON.stringify({
  source: path.relative(root, sourcePath),
  sourceSha256: sourceHash,
  originalPixels: [original.width, original.height],
  crop,
  icon: path.relative(root, iconPath),
  iconSha256: digest(icon),
  frames: sizes,
  preview: path.relative(root, previewPath),
}, null, 2));
