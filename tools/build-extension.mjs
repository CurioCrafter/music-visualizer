// Copies the shared WGSL into extension/shaders/, writes looks.json and generates the PNG icons.
// Run: node tools/build-extension.mjs
import { readFileSync, writeFileSync, readdirSync, mkdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { deflateSync, crc32 } from 'node:zlib';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(root, 'extension');
const sh = path.join(out, 'shaders');
const ORDER = ['bass_drop', 'ferrofluid', 'data_bus', 'pulse_ring', 'neon_horizon', 'reef_arcade',
  'deep_wreck', 'moonlight_piano', 'aurora', 'classic_bars', 'storm_front', 'volcano_forge', 'hyperspace',
  'neon_city', 'kaleido_temple', 'ink_bloom'];
const read = (p) => readFileSync(p, 'utf8').replace(/^\uFEFF/, '');

rmSync(sh, { recursive: true, force: true });
mkdirSync(path.join(sh, 'looks'), { recursive: true });
for (const f of ['common.wgsl', 'post.wgsl']) writeFileSync(path.join(sh, f), read(path.join(root, 'shaders', f)));

const files = readdirSync(path.join(root, 'shaders', 'looks')).filter((f) => f.endsWith('.wgsl') && !f.startsWith('_'));
const rank = (f) => { const i = ORDER.indexOf(f.replace('.wgsl', '')); return i < 0 ? 999 : i; };
files.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
const looks = files.map((f) => {
  const src = read(path.join(root, 'shaders', 'looks', f));
  writeFileSync(path.join(sh, 'looks', f), src);
  const name = /^\s*\/\/\s*name:\s*(.+?)\s*$/m.exec(src)?.[1] ?? f.replace('.wgsl', '');
  const pal = /^\s*\/\/\s*palette:\s*(.+?)\s*$/m.exec(src)?.[1].match(/#[0-9a-fA-F]{6}/g);
  return { file: f, name, palette: pal?.length === 3 ? pal : ['#ff28c8', '#9628ff', '#28dcff'] };
});
writeFileSync(path.join(sh, 'looks.json'), JSON.stringify(looks, null, 2));

// ---------- icons: dark rounded square with glowing spectrum bars ----------
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
function pixel(u, v) { // -> [r,g,b,a] 0..1
  const q = [Math.abs(u - 0.5) - 0.28, Math.abs(v - 0.5) - 0.28];
  const d = Math.hypot(Math.max(q[0], 0), Math.max(q[1], 0)) + Math.min(Math.max(q[0], q[1]), 0) - 0.22;
  if (d > 0) return [0, 0, 0, 0];
  let c = mix([0.16, 0.06, 0.3], [0.04, 0.09, 0.22], v);
  const H = [0.35, 0.6, 0.85, 0.5, 0.7];
  for (let i = 0; i < 5; i++) {
    const x0 = 0.2 + i * 0.13;
    const top = 0.78 - H[i] * 0.56;
    if (u > x0 && u < x0 + 0.09 && v > top && v < 0.78) c = mix([1, 0.16, 0.78], [0.16, 0.86, 1], (v - top) / (0.78 - top));
  }
  c = mix(c, [1, 1, 1], Math.max(0, 0.18 - v * 0.4)); // top gloss
  return [...c, 1];
}
function png(size) {
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0;
    for (let x = 0; x < size; x++) {
      const acc = [0, 0, 0, 0];
      for (let j = 0; j < 3; j++) for (let i = 0; i < 3; i++) {
        const p = pixel((x + (i + 0.5) / 3) / size, (y + (j + 0.5) / 3) / size);
        for (let k = 0; k < 3; k++) acc[k] += p[k] * p[3];
        acc[3] += p[3];
      }
      const o = y * (size * 4 + 1) + 1 + x * 4;
      for (let k = 0; k < 3; k++) raw[o + k] = acc[3] ? Math.round((acc[k] / acc[3]) * 255) : 0;
      raw[o + 3] = Math.round((acc[3] / 9) * 255);
    }
  }
  const chunk = (type, data) => {
    const b = Buffer.concat([Buffer.from(type), data]);
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(b) >>> 0);
    return Buffer.concat([len, b, crc]);
  };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
mkdirSync(path.join(out, 'icons'), { recursive: true });
for (const s of [16, 48, 128]) writeFileSync(path.join(out, 'icons', `icon${s}.png`), png(s));

console.log(`extension built: ${looks.length} looks (${looks.map((l) => l.name).join(', ')}), icons 16/48/128`);
