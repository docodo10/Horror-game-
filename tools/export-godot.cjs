#!/usr/bin/env node
/* eslint-disable no-console */
// Godot exporter — La Gardienne PC port (pc/ARCHITECTURE_PC.md §4 "Exporter").
//
// Runs the WEB build headless (same harness as tools/shot.cjs: static server + Playwright + software WebGL + the
// machine-wide browser lock) and exports everything the Godot port cannot rebuild by itself:
//
//   pc/assets/generated/level.glb                 every procedural mesh (architecture, procedural props, decals,
//                                                 canvas-textured planes, clutter) — NOT the instances of
//                                                 assets/models/*.glb (Godot instances the originals itself)
//   pc/assets/generated/level_shadow_casters.glb  the invisible thick shadow-caster boxes (cast_shadow=SHADOWS_ONLY)
//   pc/assets/generated/level_meta.json           model instances (exact world matrices, hidden nodes, node transform
//                                                 and material overrides), attachments, handles with closed/open
//                                                 local transforms (measured by opening every handle in-page), items,
//                                                 clues, TV, hide spots, colliders, occluders, proxies, lights, ...
//   pc/assets/generated/gardienne.glb             La Gardienne (SkinnedMesh + skeleton) with baked animation clips
//   pc/assets/generated/gardienne_meta.json       clips (loop, speed, cycle, footsteps), bones, attach points
//   pc/assets/generated/textures/**               textures referenced by the GLBs (external files + .import presets),
//                                                 UI / decal PNGs (notes, child drawing, newspaper, code note, digits)
//
// Usage:
//   THREE_DIR=/path/to/node_modules/three node tools/export-godot.cjs [options]
//     --out DIR          output folder (default pc/assets/generated)
//     --only LIST        comma list of: level,gardienne,textures (default: all)
//     --fonts DIR        folder with a saved Google Fonts CSS (fonts.css) + its woff2 files named
//                        s_<family>_<version>_<file>.woff2 (else env FONTS_DIR; without it canvas text uses fallbacks)
//     --quality Q        web quality preset used for the build (default high)
//     --size WxH         browser viewport (default 640x360; nothing is rendered)
//     --verbose          forward page console logs
// Env: THREE_DIR (local three@0.170.0, offline), NO_LOCK=1 (skip the machine-wide browser lock), PORT.
//
// How it works (details in pc/assets/generated/README.md):
//   * /src/main.js is served with a small prelude that (a) tags every node of every loaded GLB with its glTF node /
//     mesh / primitive index (userData.__gltf, copied to clones by Object3D.copy), (b) stubs Renderer.render/warmup and
//     Lighting.bakeEnvironment (nothing needs to be drawn: the build is ~10x faster in software GL).
//   * Assets.instance() tags clone roots with userData.modelId: every object under such a root that carries a
//     __gltf tag is an original model node; everything else is procedural and goes to level.glb.
//   * Materials are converted by this tool (not by GLTFExporter): textures become external files with the three.js
//     UV transform + flipY baked into the exported UVs (Godot only honours one uv1 transform per material), alphaMap is
//     merged into the base colour alpha, roughness/metalness maps are packed glTF-style, mismatched texture transforms
//     are re-sampled into one UV space.
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { chromium } = require('playwright');

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? (args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : true) : d; };
const ROOT = path.resolve(__dirname, '..');
const OUT = path.resolve(ROOT, String(opt('out', 'pc/assets/generated')));
const ONLY = new Set(String(opt('only', 'level,gardienne,textures')).split(',').map((s) => s.trim()).filter(Boolean));
const QUALITY = String(opt('quality', 'high'));
const VERBOSE = !!opt('verbose', false);
const FONTS_DIR = opt('fonts', null) || process.env.FONTS_DIR || null;
const THREE_DIR = process.env.THREE_DIR || (() => { try { return path.dirname(require.resolve('three/package.json')); } catch (_) { return null; } })();
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.css': 'text/css', '.woff2': 'font/woff2', '.mp3': 'audio/mpeg' };
const RES_PREFIX = 'res://' + path.relative(path.join(ROOT, 'pc'), OUT).split(path.sep).join('/');

// ------------------------------------------------------------------------------------------------ page prelude
// Prepended to /src/main.js. Runs before `new Game()` (static imports are hoisted, prototypes are patched before use).
const PRELUDE = `
import { GLTFLoader as __GL } from 'three/addons/loaders/GLTFLoader.js';
import { Renderer as __R } from './render/Renderer.js';
import { Lighting as __L } from './world/Lighting.js';
{
  const load = __GL.prototype.load;
  __GL.prototype.load = function (url, onLoad, onProgress, onError) {
    const file = String(url).split('?')[0].split('/').pop() || '';
    const model = file.replace(/\\.glb(\\.[a-z0-9]+)?$/i, '').replace(/\\.gltf$/i, '');
    return load.call(this, url, (gltf) => {
      try {
        const a = gltf.parser.associations;
        gltf.scene.traverse((o) => {
          const t = a.get(o);
          if (t) o.userData.__gltf = { model, n: t.nodes, m: t.meshes, p: t.primitives };
        });
      } catch (e) { console.warn('[export-godot] gltf tagging failed', e); }
      onLoad(gltf);
    }, onProgress, onError);
  };
  // export run: nothing is drawn
  __R.prototype.render = function () {};
  __R.prototype.warmup = function () {};
  __L.prototype.bakeEnvironment = async function () {};
  window.__exportGodot = true;
}
`;

// ------------------------------------------------------------------------------------------------ static server
function fontFile(urlPath) { // /s/<family>/<version>/<file>.woff2 -> s_<family>_<version>_<file>.woff2
  const p = urlPath.replace(/^\//, '').split('/');
  return FONTS_DIR ? path.join(FONTS_DIR, p.join('_')) : null;
}
const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  let f = path.join(ROOT, u === '/' ? 'index.html' : u);
  if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('nf'); }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-store' });
  if (u === '/src/main.js') return res.end(PRELUDE + fs.readFileSync(f, 'utf8'));
  fs.createReadStream(f).pipe(res);
});

// Machine-wide mutex shared with tools/shot.cjs and pc/tools/godot_shot.sh (one heavy renderer at a time).
const LOCK = path.join(os.tmpdir(), 'lagardienne-browser.lock');
async function acquireLock() {
  if (process.env.NO_LOCK) return;
  const t0 = Date.now();
  for (;;) {
    try { fs.mkdirSync(LOCK); fs.writeFileSync(path.join(LOCK, 'pid'), String(process.pid)); break; }
    catch (_) {
      try { if (Date.now() - fs.statSync(LOCK).mtimeMs > 25 * 60e3) { fs.rmSync(LOCK, { recursive: true, force: true }); continue; } } catch (_) { /* gone */ }
      if (Date.now() - t0 > 60 * 60e3) throw new Error('browser lock timeout');
      await new Promise((r) => setTimeout(r, 400));
    }
  }
  console.log(`[export] lock acquired after ${((Date.now() - t0) / 1000).toFixed(0)} s`);
  const release = () => { try { if (fs.readFileSync(path.join(LOCK, 'pid'), 'utf8') === String(process.pid)) fs.rmSync(LOCK, { recursive: true, force: true }); } catch (_) { /* gone */ } };
  process.on('exit', release);
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => { release(); process.exit(130); });
}

// ================================================================================================ IN-PAGE LIBRARY
// Evaluated in the page (serialized with Function.toString): no access to this file's scope.
async function PAGE_LIB() {
  const THREE = await import('three');
  const { GLTFExporter } = await import('three/addons/exporters/GLTFExporter.js');
  const { GLTFLoader } = await import('three/addons/loaders/GLTFLoader.js');
  const game = window.__game;
  const X = (window.__X = { out: {}, warnings: [] });
  const warn = (...a) => { const s = a.map((v) => (typeof v === 'string' ? v : JSON.stringify(v))).join(' '); X.warnings.push(s); console.warn('[export] ' + s); };
  const r6 = (v) => { const r = Math.round(v * 1e6) / 1e6; return Object.is(r, -0) ? 0 : r; };
  const r4 = (v) => { const r = Math.round(v * 1e4) / 1e4; return Object.is(r, -0) ? 0 : r; };
  const m16 = (m) => Array.from(m.elements, r6);
  const v3 = (v) => [r6(v.x), r6(v.y), r6(v.z)];
  const q4 = (q) => [r6(q.x), r6(q.y), r6(q.z), r6(q.w)];
  const srgbHex = (c) => '#' + c.getHexString();
  const lin3 = (c) => [r6(c.r), r6(c.g), r6(c.b)];
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frames = (n = 2) => new Promise((r) => { let k = 0; const f = () => (++k >= n ? r() : requestAnimationFrame(f)); requestAnimationFrame(f); });

  // ---------------------------------------------------------------------------------------------- transfer
  X.store = (key, u8) => { X.out[key] = u8 instanceof Uint8Array ? u8 : new Uint8Array(u8); return X.out[key].byteLength; };
  X.size = (key) => X.out[key]?.byteLength ?? -1;
  X.chunk = (key, off, len) => {
    const u = X.out[key];
    const s = u.subarray(off, Math.min(u.byteLength, off + len));
    let bin = '';
    for (let i = 0; i < s.length; i += 0x8000) bin += String.fromCharCode.apply(null, s.subarray(i, i + 0x8000));
    return btoa(bin);
  };
  X.drop = (key) => { delete X.out[key]; };

  // ---------------------------------------------------------------------------------------------- images
  // rec: { id, name, group, kind: 'file'|'canvas', path?, source? (canvas/img/ImageBitmap/{data,width,height}), usage: Set }
  const IMGS = []; const imgByKey = new Map();
  let imgSeq = 0;
  let curGroup = 'level';
  const sameOriginPath = (src) => { try { const u = new URL(src, location.href); return u.origin === location.origin ? decodeURIComponent(u.pathname) : null; } catch (_) { return null; } };
  const isHTMLImg = (img) => typeof HTMLImageElement !== 'undefined' && img instanceof HTMLImageElement;
  function imgDims(img) {
    if (!img) return { w: 0, h: 0 };
    if (img.data && img.width) return { w: img.width, h: img.height };
    return { w: img.naturalWidth || img.width || 0, h: img.naturalHeight || img.height || 0 };
  }
  function addImage(key, init) {
    let r = imgByKey.get(key);
    if (!r) { r = { id: 'img' + (imgSeq++), group: curGroup, usage: new Set(), ...init }; imgByKey.set(key, r); IMGS.push(r); }
    return r;
  }
  /** Image id for a texture used unchanged (same UV space). */
  function imageOf(tex, usage, nameHint) {
    const img = tex.image;
    const p = isHTMLImg(img) && img.src ? sameOriginPath(img.src) : null;
    let r;
    if (p && /\.(jpe?g|png)$/i.test(p) && img.complete && img.naturalWidth > 0) r = addImage('file:' + p, { kind: 'file', path: p.replace(/^\//, ''), name: nameHint });
    else r = addImage(img, { kind: 'canvas', source: img, name: tex.name || nameHint });
    r.usage.add(usage);
    return r.id;
  }
  function canvasImage(canvas, usage, nameHint) {
    const r = addImage(canvas, { kind: 'canvas', source: canvas, name: nameHint });
    r.usage.add(usage);
    return r.id;
  }
  const imgKeys = new WeakMap(); let imgKeySeq = 0;
  const imgKey = (img) => { if (!img || typeof img !== 'object') return 'none'; let k = imgKeys.get(img); if (!k) { k = 'k' + (imgKeySeq++); imgKeys.set(img, k); } return k; };
  const canvasCache = new Map();
  /** toCanvas() memoized per source image (composites built from the same inputs then share their cache keys). */
  function srcCanvas(img) { const k = imgKey(img); if (!canvasCache.has(k)) canvasCache.set(k, toCanvas(img, 4096)); return canvasCache.get(k); }
  /** Draw any three image source into a canvas at its natural orientation (row 0 = top). */
  function toCanvas(img, maxSize = 4096) {
    let { w, h } = imgDims(img);
    if (!w || !h) return null;
    const k = Math.min(1, maxSize / Math.max(w, h));
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(w * k)); c.height = Math.max(1, Math.round(h * k));
    const g = c.getContext('2d', { willReadFrequently: true });
    g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
    if (img.data) {
      const d = img.data;
      if (!(d instanceof Uint8Array || d instanceof Uint8ClampedArray) || d.length < w * h * 4) { warn('unsupported DataTexture', d?.constructor?.name, w, h); return null; }
      const id = new ImageData(new Uint8ClampedArray(d.buffer, d.byteOffset, w * h * 4).slice(), w, h);
      if (k === 1) g.putImageData(id, 0, 0);
      else { const t = document.createElement('canvas'); t.width = w; t.height = h; t.getContext('2d').putImageData(id, 0, 0); g.drawImage(t, 0, 0, c.width, c.height); }
    } else g.drawImage(img, 0, 0, c.width, c.height);
    return c;
  }
  function canvasHasAlpha(c) {
    const d = c.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, c.width, c.height).data;
    for (let i = 3; i < d.length; i += 4) if (d[i] < 255) return true;
    return false;
  }
  async function encodeCanvas(c, mime, q) {
    const blob = await new Promise((res) => c.toBlob(res, mime, q));
    return new Uint8Array(await blob.arrayBuffer());
  }
  /** Encode every pending canvas image of a group; returns the descriptor list for Node. */
  X.finalizeImages = async (group, maxSize = 2048) => {
    const list = [];
    for (const r of IMGS) {
      if (r.group !== group || r.done) continue;
      r.done = true;
      if (r.kind === 'file') { list.push({ id: r.id, kind: 'file', path: r.path, name: r.name, usage: [...r.usage] }); continue; }
      const c = toCanvas(r.source, maxSize);
      if (!c) { warn('image could not be read', r.name); list.push({ id: r.id, kind: 'missing', name: r.name, usage: [...r.usage] }); continue; }
      const alpha = canvasHasAlpha(c);
      const normal = r.usage.has('normal');
      const png = alpha || (normal && c.width * c.height <= 512 * 512) || r.usage.has('png');
      const bytes = await encodeCanvas(c, png ? 'image/png' : 'image/jpeg', png ? undefined : (normal ? 0.95 : 0.92));
      const key = 'img:' + r.id;
      X.store(key, bytes);
      list.push({ id: r.id, kind: 'data', key, ext: png ? 'png' : 'jpg', w: c.width, h: c.height, alpha, name: r.name, usage: [...r.usage], bytes: bytes.byteLength });
    }
    return list;
  };

  // ---------------------------------------------------------------------------------------------- UV transforms
  const IDENT = new THREE.Matrix3();
  const FLIP = new THREE.Matrix3().set(1, 0, 0, 0, -1, 1, 0, 0, 1); // (u, v) -> (u, 1 - v)
  /** mesh uv -> image coords in glTF convention (v = 0 is the top row of the stored image). */
  function texUV(t) {
    if (t.matrixAutoUpdate !== false) t.updateMatrix();
    const M = t.matrix.clone();
    return t.flipY ? FLIP.clone().multiply(M) : M;
  }
  const m3eq = (a, b) => { for (let i = 0; i < 9; i++) if (Math.abs(a.elements[i] - b.elements[i]) > 1e-6) return false; return true; };
  const det2 = (m) => Math.abs(m.elements[0] * m.elements[4] - m.elements[1] * m.elements[3]);
  const colNorms = (m) => [Math.hypot(m.elements[0], m.elements[1]), Math.hypot(m.elements[3], m.elements[4])];
  const pow2 = (v) => 2 ** Math.round(Math.log2(Math.max(1, v)));
  /** Re-sample texture `tex` at W x H through R (output image coords -> source image coords, both 0..1 = one tile). */
  const rebakeCache = new Map();
  function rebake(tex, R, W, H) {
    const key = `${imgKey(tex.image)}|${Array.from(R.elements, (x) => x.toFixed(6)).join(',')}|${W}x${H}`;
    if (rebakeCache.has(key)) return rebakeCache.get(key);
    const src = srcCanvas(tex.image);
    if (!src) return null;
    if (tex.wrapS !== THREE.RepeatWrapping || tex.wrapT !== THREE.RepeatWrapping) warn('re-sampling a non-repeating texture', tex.name || imgKey(tex.image));
    const A = new THREE.Matrix3().makeScale(src.width, src.height).multiply(R).multiply(new THREE.Matrix3().makeScale(1 / W, 1 / H));
    const e = A.clone().invert().elements;
    const c = document.createElement('canvas'); c.width = W; c.height = H;
    const g = c.getContext('2d', { willReadFrequently: true });
    g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
    const pat = g.createPattern(src, 'repeat');
    pat.setTransform(new DOMMatrix([e[0], e[1], e[3], e[4], e[6], e[7]]));
    g.fillStyle = pat; g.fillRect(0, 0, W, H);
    rebakeCache.set(key, c);
    return c;
  }
  /** Size of a re-sampled map: the source texel density (tiles x source size), power-of-two when that does not
   *  upscale more than 25 %, at most `cap` (2048 for the hero character, else 1024 / twice the base map). */
  function rebakeSize(tex, R, base, cap) {
    const { w, h } = imgDims(tex.image);
    const [sx, sy] = colNorms(R);
    const bw = base ? imgDims(base.image).w : 512, bh = base ? imgDims(base.image).h : 512;
    const fit = (v) => { const p = pow2(v); return p > v * 1.25 ? Math.round(v) : p; };
    let W = fit(Math.max(bw, w * sx)), H = fit(Math.max(bh, h * sy));
    const k = Math.min(1, cap / Math.max(W, H)); W = Math.max(64, Math.round(W * k)); H = Math.max(64, Math.round(H * k));
    return [W, H];
  }
  const composites = new Map();
  const memo = (key, fn) => { if (!composites.has(key)) composites.set(key, fn()); return composites.get(key); };

  // ---------------------------------------------------------------------------------------------- materials -> glTF
  const MAT = new Map(); // three material -> rec { id, def, uv, skip }
  const matNames = new Set();
  let matSeq = 0;
  const uniqueName = (set, n) => { let b = n || 'mat', u = b, k = 2; while (set.has(u)) u = b + '_' + (k++); set.add(u); return u; };
  const GL_WRAP = { [THREE.RepeatWrapping]: 10497, [THREE.ClampToEdgeWrapping]: 33071, [THREE.MirroredRepeatWrapping]: 33648 };
  const GL_FILTER = { [THREE.NearestFilter]: 9728, [THREE.LinearFilter]: 9729, [THREE.NearestMipmapNearestFilter]: 9984, [THREE.LinearMipmapNearestFilter]: 9985, [THREE.NearestMipmapLinearFilter]: 9986, [THREE.LinearMipmapLinearFilter]: 9987 };
  const sampler = (t) => ({ wrapS: GL_WRAP[t.wrapS] ?? 10497, wrapT: GL_WRAP[t.wrapT] ?? 10497, magFilter: GL_FILTER[t.magFilter] ?? 9729, minFilter: GL_FILTER[t.minFilter] ?? 9987 });
  const SLOTS = ['map', 'alphaMap', 'normalMap', 'roughnessMap', 'metalnessMap', 'aoMap', 'emissiveMap'];
  const IGNORED_SLOTS = ['bumpMap', 'displacementMap', 'lightMap', 'clearcoatMap', 'clearcoatNormalMap', 'clearcoatRoughnessMap', 'sheenColorMap', 'sheenRoughnessMap', 'specularIntensityMap', 'specularColorMap', 'transmissionMap', 'thicknessMap', 'iridescenceMap', 'iridescenceThicknessMap', 'anisotropyMap'];

  function skipReason(m) {
    if (!m) return 'no material';
    if (m.isShaderMaterial || m.isRawShaderMaterial) return 'ShaderMaterial';
    if (m.isPointsMaterial || m.isLineBasicMaterial || m.isLineDashedMaterial || m.isSpriteMaterial) return m.type;
    if (m.visible === false) return 'invisible';
    if (m.colorWrite === false) return 'shadowCaster';
    if (m.isMeshDepthMaterial || m.isMeshDistanceMaterial || m.isShadowMaterial || m.isMeshNormalMaterial) return m.type;
    return null;
  }

  function convertMaterial(m, hint, hero = false) {
    let rec = MAT.get(m);
    if (rec) return rec;
    rec = { id: 'mat' + (matSeq++), src: m };
    MAT.set(m, rec);
    rec.skip = skipReason(m);
    if (rec.skip) return rec;
    const label = m.name || m.type;
    const T = {};
    for (const k of SLOTS) if (m[k] && m[k].isTexture && m[k].image) T[k] = m[k];
    const ign = IGNORED_SLOTS.filter((k) => m[k]);
    if (ign.length) warn(`material ${label}: maps not exported (no glTF/Godot equivalent): ${ign.join(', ')}`);
    for (const k of Object.keys(T)) if ((T[k].channel || 0) !== 0) { warn(`material ${label}: ${k} uses uv channel ${T[k].channel} (dropped)`); delete T[k]; }
    for (const k of Object.keys(T)) { const { w, h } = imgDims(T[k].image); if (!w || !h) { warn(`material ${label}: ${k} image not loaded (dropped)`); delete T[k]; } }
    // output UV space = the least-repeating texture (alpha tears / unique art win over tiling detail maps)
    let base = null, bdet = Infinity;
    for (const k of ['map', 'alphaMap', 'emissiveMap', 'aoMap', 'normalMap', 'roughnessMap', 'metalnessMap']) {
      const t = T[k]; if (!t) continue;
      const d = det2(texUV(t));
      if (d < bdet - 1e-6) { bdet = d; base = t; }
    }
    const Tout = base ? texUV(base) : null;
    rec.uv = Tout && !m3eq(Tout, IDENT) ? Tout : null;
    // per-slot canvas in the output space (null = use the image unchanged)
    const same = (t) => m3eq(texUV(t), Tout);
    const periodic = (t) => t.wrapS === THREE.RepeatWrapping && t.wrapT === THREE.RepeatWrapping;
    const resampled = {};
    for (const k of Object.keys(T)) {
      if (same(T[k])) continue;
      const R = new THREE.Matrix3().copy(texUV(T[k])).multiply(Tout.clone().invert()); // output coords -> source coords
      const e = R.elements;
      if (k === 'normalMap' && e[0] * e[4] - e[1] * e[3] < 0) warn(`material ${label}: normal map re-sampled through a mirrored UV mapping (green channel not corrected)`);
      let Rs = R;
      if (Math.abs(e[1]) < 1e-6 && Math.abs(e[3]) < 1e-6 && periodic(T[k]) && periodic(base)) {
        // both maps tile: a non-integer tile ratio would leave a seam at every base tile -> snap to whole tiles
        const sx = Math.sign(e[0]) * Math.max(1, Math.round(Math.abs(e[0]))), sy = Math.sign(e[4]) * Math.max(1, Math.round(Math.abs(e[4])));
        if (Math.abs(sx - e[0]) > 1e-3 || Math.abs(sy - e[4]) > 1e-3) warn(`material ${label}: ${k} tiling snapped from ${r4(e[0])} x ${r4(e[4])} to ${sx} x ${sy} per ${base === T.map ? 'map' : 'base'} tile (seamless)`);
        Rs = new THREE.Matrix3().set(sx, 0, Math.round(e[6]), 0, sy, Math.round(e[7]), 0, 0, 1); // tile phase is irrelevant for detail maps
        if (sx === 1 && sy === 1) continue; // same mapping as the base: use the image as is
      }
      const bd = imgDims(base.image);
      const cap = hero ? 2048 : Math.min(2048, Math.max(1024, 2 * Math.max(bd.w, bd.h)));
      const [W, H] = rebakeSize(T[k], Rs, base, cap);
      resampled[k] = rebake(T[k], Rs, W, H);
      warn(`material ${label}: ${k} re-sampled into the ${base === T.map ? 'map' : 'base'} UV space (${W}x${H})`);
    }
    const pix = (k) => resampled[k] || srcCanvas(T[k].image);
    const unlit = !!m.isMeshBasicMaterial;
    const def = { name: uniqueName(matNames, (m.name || (hint ? hint + '_mat' : 'mat_' + m.type)).replace(/[^A-Za-z0-9_]/g, '_')), pbrMetallicRoughness: {}, extensions: {}, extras: { three: m.type } };
    const pbr = def.pbrMetallicRoughness;
    const c = m.color || new THREE.Color(1, 1, 1);
    pbr.baseColorFactor = [r6(c.r), r6(c.g), r6(c.b), r6(m.opacity ?? 1)];
    if (c.r > 1 || c.g > 1 || c.b > 1) def.extras.overbright = true;
    const ref = (img, tex) => ({ img, sampler: sampler(tex) });
    // base colour (+ alphaMap merged into its alpha)
    if (T.map || T.alphaMap) {
      if (T.alphaMap) {
        const a = pix('alphaMap');
        const col = T.map ? pix('map') : null;
        const out = memo(`alpha|${imgKey(a)}|${imgKey(col)}`, () => {
        const W = Math.max(a.width, col ? col.width : 0), H = Math.max(a.height, col ? col.height : 0);
        const out = document.createElement('canvas'); out.width = W; out.height = H;
        const g = out.getContext('2d', { willReadFrequently: true });
        g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
        if (col) g.drawImage(col, 0, 0, W, H); else { g.fillStyle = '#fff'; g.fillRect(0, 0, W, H); }
        const cd = g.getImageData(0, 0, W, H);
        const ac = document.createElement('canvas'); ac.width = W; ac.height = H;
        const ag = ac.getContext('2d', { willReadFrequently: true }); ag.imageSmoothingEnabled = true; ag.imageSmoothingQuality = 'high';
        ag.drawImage(a, 0, 0, W, H);
        const ad = ag.getImageData(0, 0, W, H).data;
        for (let i = 0; i < cd.data.length; i += 4) cd.data[i + 3] = Math.round((cd.data[i + 3] * ad[i + 1]) / 255); // three: alphaMap.g
        g.putImageData(cd, 0, 0);
        return out;
        });
        pbr.baseColorTexture = ref(canvasImage(out, 'colorAlpha', `${def.name}_basecolor`), base);
      } else if (resampled.map) pbr.baseColorTexture = ref(canvasImage(resampled.map, 'color', `${def.name}_basecolor`), base);
      else pbr.baseColorTexture = ref(imageOf(T.map, 'color', `${def.name}_basecolor`), T.map);
      if (T.map && T.map.colorSpace !== THREE.SRGBColorSpace) def.extras.mapNotSRGB = true;
    }
    if (unlit) {
      def.extensions.KHR_materials_unlit = {};
      pbr.metallicFactor = 0; pbr.roughnessFactor = 1;
    } else {
      pbr.metallicFactor = r6(m.metalness ?? 0);
      pbr.roughnessFactor = r6(m.roughness ?? 1);
      const R = T.roughnessMap, Mt = T.metalnessMap;
      if (R || Mt) {
        const sameImg = R && Mt && R.image === Mt.image && !resampled.roughnessMap && !resampled.metalnessMap;
        if (sameImg || (R && !Mt && !(m.metalness > 0) && !resampled.roughnessMap)) {
          pbr.metallicRoughnessTexture = ref(imageOf(R, 'data', `${def.name}_orm`), R);
        } else { // pack: G = roughness (three reads .g), B = metalness (three reads .b)
          const rc = R ? pix('roughnessMap') : null, mc = Mt ? pix('metalnessMap') : null;
          const out = memo(`orm|${imgKey(rc)}|${imgKey(mc)}`, () => {
          const W = Math.max(rc ? rc.width : 0, mc ? mc.width : 0), H = Math.max(rc ? rc.height : 0, mc ? mc.height : 0);
          const read = (cv) => { if (!cv) return null; const t = document.createElement('canvas'); t.width = W; t.height = H; const g = t.getContext('2d', { willReadFrequently: true }); g.imageSmoothingQuality = 'high'; g.drawImage(cv, 0, 0, W, H); return g.getImageData(0, 0, W, H).data; };
          const rd = read(rc), md = read(mc);
          const out = document.createElement('canvas'); out.width = W; out.height = H;
          const g = out.getContext('2d'); const id = g.createImageData(W, H);
          for (let i = 0; i < id.data.length; i += 4) { id.data[i] = 0; id.data[i + 1] = rd ? rd[i + 1] : 255; id.data[i + 2] = md ? md[i + 2] : 255; id.data[i + 3] = 255; }
          g.putImageData(id, 0, 0);
          return out;
          });
          pbr.metallicRoughnessTexture = ref(canvasImage(out, 'data', `${def.name}_orm`), base);
        }
      }
      if (T.normalMap) {
        const img = resampled.normalMap ? canvasImage(resampled.normalMap, 'normal', `${def.name}_normal`) : imageOf(T.normalMap, 'normal', `${def.name}_normal`);
        def.normalTexture = { ...ref(img, resampled.normalMap ? base : T.normalMap) };
        const ns = m.normalScale ? m.normalScale.x : 1;
        if (Math.abs(ns - 1) > 1e-6) def.normalTexture.scale = r6(ns);
        if (m.normalScale && Math.abs(Math.abs(m.normalScale.y) - Math.abs(m.normalScale.x)) > 1e-6) def.extras.normalScaleY = r6(m.normalScale.y);
      }
      if (T.aoMap) {
        const img = resampled.aoMap ? canvasImage(resampled.aoMap, 'data', `${def.name}_ao`) : imageOf(T.aoMap, 'data', `${def.name}_ao`);
        def.occlusionTexture = { ...ref(img, resampled.aoMap ? base : T.aoMap) };
        if ((m.aoMapIntensity ?? 1) !== 1) def.occlusionTexture.strength = r6(m.aoMapIntensity);
      }
      if (m.emissive) {
        const e = m.emissive, I = m.emissiveIntensity ?? 1;
        const mx = Math.max(e.r, e.g, e.b);
        if (mx > 0) {
          def.extras.emissive = { srgb: srgbHex(e), linear: lin3(e), intensity: r6(I) };
          if (I > 0) {
            const k = mx > 1 ? 1 / mx : 1;
            def.emissiveFactor = [r6(e.r * k), r6(e.g * k), r6(e.b * k)];
            const s = I / k;
            if (Math.abs(s - 1) > 1e-6) def.extensions.KHR_materials_emissive_strength = { emissiveStrength: r6(s) };
          }
        }
        if (T.emissiveMap) {
          const img = resampled.emissiveMap ? canvasImage(resampled.emissiveMap, 'color', `${def.name}_emissive`) : imageOf(T.emissiveMap, 'color', `${def.name}_emissive`);
          def.emissiveTexture = ref(img, resampled.emissiveMap ? base : T.emissiveMap);
          if (!def.emissiveFactor) def.emissiveFactor = [0, 0, 0];
        }
      }
      if (m.isMeshPhysicalMaterial) {
        if (m.clearcoat > 0) def.extensions.KHR_materials_clearcoat = { clearcoatFactor: r6(m.clearcoat), clearcoatRoughnessFactor: r6(m.clearcoatRoughness) };
        if (m.sheen > 0) def.extensions.KHR_materials_sheen = { sheenColorFactor: lin3(m.sheenColor).map((v) => r6(v * m.sheen)), sheenRoughnessFactor: r6(m.sheenRoughness) };
        if (Math.abs((m.specularIntensity ?? 1) - 1) > 1e-6) def.extensions.KHR_materials_specular = { specularFactor: r6(m.specularIntensity) };
        if (Math.abs((m.ior ?? 1.5) - 1.5) > 1e-6) def.extensions.KHR_materials_ior = { ior: r6(m.ior) };
        if (m.transmission > 0) def.extensions.KHR_materials_transmission = { transmissionFactor: r6(m.transmission) };
      }
    }
    if (m.transparent) def.alphaMode = 'BLEND';
    else if (m.alphaTest > 0) { def.alphaMode = 'MASK'; def.alphaCutoff = r6(m.alphaTest); }
    if (m.alphaTest > 0 && m.transparent) def.extras.alphaTest = r6(m.alphaTest);
    if (m.alphaToCoverage) def.extras.alphaToCoverage = true;
    if (m.side === THREE.DoubleSide) def.doubleSided = true;
    if (m.side === THREE.BackSide) { def.extras.side = 'back'; warn(`material ${label}: BackSide (exported single-sided)`); }
    if (m.blending === THREE.AdditiveBlending) def.extras.blending = 'additive';
    else if (m.blending === THREE.MultiplyBlending) def.extras.blending = 'multiply';
    if (m.depthWrite === false) def.extras.depthWrite = false;
    if (m.depthTest === false) def.extras.depthTest = false;
    if (m.polygonOffset) def.extras.polygonOffset = [m.polygonOffsetFactor, m.polygonOffsetUnits];
    if (m.toneMapped === false) def.extras.toneMapped = false;
    if (m.vertexColors) def.extras.vertexColors = true;
    if (m.envMapIntensity !== undefined && Math.abs(m.envMapIntensity - 1) > 1e-6) def.extras.envMapIntensity = r6(m.envMapIntensity);
    if (m.userData?.envZone !== undefined) def.extras.envZone = m.userData.envZone;
    if (m.fog === false) def.extras.fog = false;
    if (!Object.keys(def.extensions).length) delete def.extensions;
    rec.def = def;
    rec.placeholder = new THREE.MeshStandardMaterial({ name: '__mat:' + rec.id });
    return rec;
  }

  // ---------------------------------------------------------------------------------------------- geometry
  const GEO = new Map();
  function copyAttr(a, Type = Float32Array) {
    const n = a.count, s = a.itemSize, arr = new Type(n * s);
    const get = [a.getX, a.getY, a.getZ, a.getW];
    for (let i = 0; i < n; i++) for (let j = 0; j < s; j++) arr[i * s + j] = get[j].call(a, i);
    return new THREE.BufferAttribute(arr, s);
  }
  function exportGeometry(g, uvM, keepColor, skinned) {
    const key = `${g.uuid}|${uvM ? Array.from(uvM.elements, (x) => x.toFixed(7)).join(',') : '-'}|${keepColor ? 1 : 0}|${skinned ? 1 : 0}`;
    if (GEO.has(key)) return GEO.get(key);
    let out = null;
    if (g.attributes.position && g.attributes.position.count > 0) {
      out = new THREE.BufferGeometry();
      out.name = g.name || '';
      out.setAttribute('position', copyAttr(g.attributes.position));
      if (g.attributes.normal) out.setAttribute('normal', copyAttr(g.attributes.normal));
      if (g.attributes.uv) {
        const uv = copyAttr(g.attributes.uv);
        if (uvM) { const v = new THREE.Vector2(); for (let i = 0; i < uv.count; i++) { v.set(uv.getX(i), uv.getY(i)).applyMatrix3(uvM); uv.setXY(i, v.x, v.y); } }
        out.setAttribute('uv', uv);
      }
      if (keepColor && g.attributes.color) out.setAttribute('color', copyAttr(g.attributes.color));
      if (skinned && g.attributes.skinIndex && g.attributes.skinWeight) {
        out.setAttribute('skinIndex', copyAttr(g.attributes.skinIndex, Uint16Array));
        out.setAttribute('skinWeight', copyAttr(g.attributes.skinWeight));
      }
      if (g.index) out.setIndex(new THREE.BufferAttribute(g.index.array.slice(), 1));
      for (const gr of g.groups) out.addGroup(gr.start, gr.count, gr.materialIndex);
      if (!out.attributes.normal) out.computeVertexNormals();
      // glTF wants unit normals
      const nrm = out.attributes.normal, v = new THREE.Vector3();
      for (let i = 0; i < nrm.count; i++) { v.fromBufferAttribute(nrm, i); const l = v.length(); if (l > 1e-8 && Math.abs(l - 1) > 1e-4) { v.multiplyScalar(1 / l); nrm.setXYZ(i, v.x, v.y, v.z); } else if (l <= 1e-8) nrm.setXYZ(i, 0, 1, 0); }
    }
    GEO.set(key, out);
    return out;
  }

  /** Mesh -> exportable (geometry, placeholder materials) or a skip reason. */
  function exportMesh(o) {
    const mats = Array.isArray(o.material) ? o.material : [o.material];
    const hint = o.name || o.parent?.name || '';
    const recs = mats.map((x) => convertMaterial(x, hint, !!o.isSkinnedMesh));
    const sk = recs.find((r) => r.skip);
    if (sk) return { skip: sk.skip };
    const uv = recs[0].uv;
    for (const r of recs) if ((r.uv || IDENT) && !m3eq(r.uv || IDENT, uv || IDENT)) warn(`mesh ${o.name}: materials of one mesh need different UV transforms (first one used)`);
    const keepColor = recs.some((r) => r.src.vertexColors);
    const geo = exportGeometry(o.geometry, uv, keepColor, !!o.isSkinnedMesh);
    if (!geo) return { skip: 'empty geometry' };
    return { geo, material: Array.isArray(o.material) ? recs.map((r) => r.placeholder) : recs[0].placeholder, recs };
  }

  // ---------------------------------------------------------------------------------------------- scene scan
  const tagOf = (o) => o?.userData?.__gltf || null;
  const kindOf = (o) => {
    if (o.userData?.modelId) return 'instance';
    const t = tagOf(o);
    if (t && t.n !== undefined && t.n !== null) return 'orig';
    if (t && (t.p !== undefined || t.m !== undefined)) return 'prim';
    return 'proc';
  };
  const pathNames = (o) => { const a = []; for (let n = o; n && n !== game.scene; n = n.parent) a.unshift(n.name || n.type); return a.join('/'); };

  /** Pristine model info: n -> { obj, parentN, matrix } and m:p -> obj. */
  const PRISTINE = new Map();
  function pristine(modelId) {
    if (PRISTINE.has(modelId)) return PRISTINE.get(modelId);
    const root = game.assets.models.get(modelId);
    const info = { root, nodes: new Map(), prims: new Map() };
    root?.traverse((o) => {
      const t = tagOf(o); if (!t) return;
      if (t.n !== undefined && t.n !== null) {
        let p = o.parent, pn = -1;
        while (p && p !== root) { const pt = tagOf(p); if (pt && pt.n !== undefined && pt.n !== null) { pn = pt.n; break; } p = p.parent; }
        info.nodes.set(t.n, { obj: o, parentN: pn, matrix: o.matrix.clone() });
      }
      if (t.m !== undefined && t.p !== undefined && t.p !== null) info.prims.set(`${t.m}:${t.p}`, o);
    });
    PRISTINE.set(modelId, info);
    return info;
  }

  X.scan = () => {
    const scene = game.scene;
    scene.updateMatrixWorld(true);
    const excluded = new Set([game.camera, game.entity?.root].filter(Boolean));
    const S = {
      instances: [], instByObj: new Map(), procNodes: new Map(), procRoots: [], reparents: [], lights: [], proxies: [],
      casters: [], decals: [], skipped: [], merged: [], origByInst: new Map(),
    };
    const DECALS = new Set(['duck.digit', 'horse.digit']);
    const instOfObj = (o) => { for (let n = o; n; n = n.parent) if (n.userData?.modelId) return S.instByObj.get(n) || null; return null; };
    const instNames = new Set();
    function addInstance(o, parent) {
      const rec = { obj: o, model: o.userData.modelId, name: uniqueName(instNames, (o.name || o.userData.modelId).replace(/[^A-Za-z0-9_]/g, '_')), parentObj: parent, nodes: new Map(), prims: new Map(), merged: [] };
      S.instances.push(rec); S.instByObj.set(o, rec);
      return rec;
    }
    function visit(o, parent) {
      if (excluded.has(o)) return;
      const k = kindOf(o);
      if (k === 'instance') addInstance(o, parent);
      else if (k === 'orig' || k === 'prim') {
        const inst = instOfObj(o);
        if (!inst) warn('model node outside any instance', pathNames(o));
        else if (k === 'orig') inst.nodes.set(tagOf(o).n, o);
        else inst.prims.set(`${tagOf(o).m}:${tagOf(o).p}`, o);
      } else {
        const inst = instOfObj(o);
        const info = { obj: o, inst, parent, kind: 'node' };
        if (o.isLight) info.kind = 'light';
        else if (o.isCamera) info.kind = 'camera';
        else if (o.isPoints || o.isLine || o.isLineSegments || o.isSprite) { info.kind = 'skip'; info.reason = o.type; }
        else if (o.isMesh) {
          const mats = Array.isArray(o.material) ? o.material : [o.material];
          const reasons = mats.map(skipReason);
          if (DECALS.has(o.name)) info.kind = 'decal';
          else if (reasons.includes('invisible')) info.kind = 'proxy';
          else if (reasons.includes('shadowCaster')) info.kind = 'caster';
          else if (reasons.some(Boolean)) { info.kind = 'skip'; info.reason = reasons.find(Boolean); }
          else if (inst && !o.isSkinnedMesh) {
            // a procedural mesh that only uses the instance's own (pristine) materials replaces original nodes
            // (Props._mergeStatic: one draw call per material) -> Godot keeps the original nodes instead
            const pm = new Set(); pristine(inst.model).root?.traverse((p) => { if (p.isMesh) (Array.isArray(p.material) ? p.material : [p.material]).forEach((x) => pm.add(x)); });
            if (mats.every((x) => pm.has(x))) { info.kind = 'merged'; inst.merged.push(o); }
            else info.kind = 'mesh';
          } else info.kind = 'mesh';
        }
        S.procNodes.set(o, info);
        const pk = parent === scene ? 'scene' : kindOf(parent);
        if (pk !== 'proc') S.procRoots.push(o);
      }
      for (const c of o.children) visit(c, o);
    }
    for (const c of scene.children) visit(c, scene);
    X.S = S;
    return { instances: S.instances.length, procNodes: S.procNodes.size, procRoots: S.procRoots.length };
  };

  // ---------------------------------------------------------------------------------------------- refs
  // ref(o): { level: name } for procedural nodes kept in level.glb, { instance: name } for model instance roots,
  //         { instance, n, surface? } for original model nodes (n = glTF node index; Node maps it to the Godot path).
  function ref(o) {
    if (!o) return null;
    const S = X.S;
    if (S.instByObj.has(o)) return { instance: S.instByObj.get(o).name };
    if (X.levelName?.has(o)) return { level: X.levelName.get(o) };
    const t = tagOf(o);
    if (t) {
      let inst = null; for (let n = o; n; n = n.parent) if (S.instByObj.has(n)) { inst = S.instByObj.get(n); break; }
      if (inst) {
        if (t.n !== undefined && t.n !== null) return { instance: inst.name, n: t.n };
        const p = o.parent, pt = tagOf(p);
        if (pt && pt.n !== undefined && pt.n !== null) return { instance: inst.name, n: pt.n, surface: t.p ?? 0 };
      }
    }
    return null;
  }
  X.ref = ref;

  // ---------------------------------------------------------------------------------------------- level export
  X.exportLevel = async () => {
    curGroup = 'level';
    const S = X.S, scene = game.scene, W = game.world, P = W.props, E = W.extras;
    // references that must survive pruning (empty groups used as parents / handles / contents / items)
    const keep = new Set();
    const keepObj = (o) => { if (o && S.procNodes.has(o)) keep.add(o); };
    for (const h of Object.values(W.handles || {})) { keepObj(h.object); keepObj(h.contents); }
    for (const o of Object.values(W.items || {})) keepObj(o);
    for (const o of Object.values(W.clues || {})) keepObj(o);
    keepObj(W.tv?.object);
    for (const rec of S.instances) keepObj(rec.parentObj);
    for (const [o, info] of S.procNodes) {
      if (info.kind === 'proxy' || info.kind === 'decal' || info.kind === 'caster') keepObj(o.parent);
      if (info.kind === 'node' || info.kind === 'mesh') for (const c of o.children) if (kindOf(c) === 'orig') keep.add(o); // reparent targets
    }
    const extraKeep = [P?._rock?.root, P?._rock?.pivot, P?._lid?.object, P?._lock, P?._lock?.userData?.shackle, ...(P?._lock?.userData?.wheels || []),
      P?._tvState?.screen, W.codeNote, E?.mirror?.glass, E?.crt?.screen, E?.chain?.pivot, W.lighting?.bowl, W.lighting?.strip, W.architecture?.hall];
    extraKeep.forEach(keepObj);

    const names = new Set(); const levelName = new Map(); X.levelName = levelName;
    // readable names for unnamed procedural nodes the meta refers to
    const role = new Map();
    for (const [id, h] of Object.entries(W.handles || {})) if (h.contents && !h.contents.name) role.set(h.contents, id + '.contents');
    const lock = P?._lock;
    if (lock) {
      if (lock.userData.shackle) role.set(lock.userData.shackle, 'lockedBox.lock.shackle');
      (lock.userData.wheels || []).forEach((w, i) => role.set(w, `lockedBox.lock.wheel${i}`));
      if (lock.children[0] && !lock.children[0].name) role.set(lock.children[0], 'lockedBox.lock.body');
    }
    if (P?._boxFrame) role.set(P._boxFrame, 'lockedBox.frame');
    const lidPivot = P?._lid?.object;
    if (lidPivot) { const f = lidPivot.children.find((c) => !c.userData?.__gltf && !c.isMesh && !c.name); if (f) role.set(f, 'lockedBox.lid.frame'); }
    const leverG = P?._lever?.handle?.object;
    if (leverG) { const pv = leverG.children.find((c) => !c.isMesh && c.children.some((x) => x.isMesh)); if (pv && !pv.name) role.set(pv, 'powerBox.lever.pivot'); }
    if (P?._rock?.pivot && !P._rock.pivot.name) role.set(P._rock.pivot, 'rockingChair.pivot');
    const HINT = /(^|_)(col|colonly|convcol|convcolonly|rigid|noimp|occ|occonly|navmesh|vehicle|wheel|loop|cycle|skip)$/i;
    const nameFor = (o, parentName) => {
      let n = (o.name || role.get(o) || '').replace(/[^A-Za-z0-9_]/g, '_');
      if (!n) n = `${parentName || 'level'}_${o.isMesh ? 'mesh' : 'node'}`;
      if (HINT.test(n.replace(/\d+$/, ''))) n += '_x';
      return uniqueName(names, n);
    };
    const hidden = [], noCast = [], noReceive = [], hints = [], skipped = [], meshStats = { meshes: 0, tris: 0 };
    // pass 1: decide which nodes exist (bottom-up pruning), then name them top-down
    const exists = new Map();
    const decide = (o) => {
      const info = S.procNodes.get(o);
      let any = false;
      for (const c of o.children) if (S.procNodes.has(c) && decide(c)) any = true;
      let mesh = null;
      if (info.kind === 'mesh') { mesh = exportMesh(o); if (mesh.skip) { skipped.push({ path: pathNames(o), reason: mesh.skip }); mesh = null; } }
      else if (info.kind === 'skip') skipped.push({ path: pathNames(o), reason: info.reason, material: Array.isArray(o.material) ? o.material.map((x) => x?.type) : o.material?.type });
      const has = !!mesh || any || keep.has(o);
      if (info.kind === 'light' || info.kind === 'camera' || info.kind === 'proxy' || info.kind === 'caster' || info.kind === 'decal' || info.kind === 'merged') {
        exists.set(o, any ? { mesh: null } : null);
        return any;
      }
      exists.set(o, has ? { mesh } : null);
      return has;
    };
    const roots = S.procRoots.filter((o) => decide(o));
    const exportScene = new THREE.Scene(); exportScene.name = 'level';
    const attachments = [], levelRoots = [];
    const build = (o, parentName) => {
      const e = exists.get(o); if (!e) return null;
      const name = nameFor(o, parentName);
      levelName.set(o, name);
      let c;
      if (e.mesh) {
        c = o.isSkinnedMesh ? new THREE.Mesh(e.mesh.geo, e.mesh.material) : new THREE.Mesh(e.mesh.geo, e.mesh.material);
        meshStats.meshes++;
        const g = e.mesh.geo; meshStats.tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
        if (!o.castShadow) noCast.push(name);
        if (!o.receiveShadow) noReceive.push(name);
        const mh = {};
        if (o.renderOrder) mh.renderOrder = o.renderOrder;
        for (const r of e.mesh.recs) { const x = r.def.extras; for (const k of ['polygonOffset', 'blending', 'depthWrite', 'depthTest', 'alphaTest', 'side', 'toneMapped']) if (x[k] !== undefined) mh[k] = x[k]; }
        if (Object.keys(mh).length) hints.push({ node: name, ...mh });
      } else c = new THREE.Object3D();
      if (e.mesh && o.isInstancedMesh) { // expand GPU instances into plain child meshes
        const inst = c; c = new THREE.Object3D();
        const m4 = new THREE.Matrix4();
        for (let i = 0; i < o.count; i++) { const k = new THREE.Mesh(inst.geometry, inst.material); k.name = uniqueName(names, `${name}_i${i}`); o.getMatrixAt(i, m4); m4.decompose(k.position, k.quaternion, k.scale); c.add(k); }
        warn(`InstancedMesh ${name} expanded into ${o.count} meshes`);
      }
      c.name = name;
      if (o.matrixAutoUpdate === false) o.matrix.decompose(c.position, c.quaternion, c.scale);
      else { c.position.copy(o.position); c.quaternion.copy(o.quaternion); c.scale.copy(o.scale); }
      if (o.visible === false && o !== E?.mirror?.glass) hidden.push(name);
      for (const ch of o.children) if (S.procNodes.has(ch)) { const cc = build(ch, name); if (cc) c.add(cc); }
      return c;
    };
    for (const o of roots) {
      const c = build(o, null);
      if (!c) continue;
      o.matrixWorld.decompose(c.position, c.quaternion, c.scale); // top level: world placement
      exportScene.add(c);
      levelRoots.push(c.name);
      const p = S.procNodes.get(o).parent;
      if (p !== scene) attachments.push({ level: c.name, parent: ref(p), local: m16(o.matrix), path: pathNames(o) });
    }
    // reparented original nodes (their parent is procedural, or not their glTF parent)
    const reparents = [];
    const instances = [];
    for (const rec of S.instances) {
      const pr = pristine(rec.model);
      const o = rec.obj;
      const inst = { name: rec.name, model: rec.model, path: pathNames(o), transform: m16(o.matrixWorld) };
      if (o.visible === false) inst.visible = false;
      if (rec.parentObj !== scene) { inst.parent = ref(rec.parentObj); inst.local = m16(o.matrix); if (!inst.parent) warn('instance parent not exported', rec.name, pathNames(rec.parentObj)); }
      // hidden (removed) nodes, minus the ones merged into procedural meshes
      const mergedMats = new Set(); for (const mm of rec.merged) (Array.isArray(mm.material) ? mm.material : [mm.material]).forEach((x) => mergedMats.add(x));
      const missing = new Set();
      for (const [n, pn] of pr.nodes) if (!rec.nodes.has(n)) missing.add(n);
      const mergedNodes = [];
      if (mergedMats.size) {
        for (const n of [...missing]) {
          const po = pr.nodes.get(n).obj; const ms = [];
          po.traverse((x) => { if (x.isMesh) (Array.isArray(x.material) ? x.material : [x.material]).forEach((y) => ms.push(y)); });
          if (ms.length && ms.every((y) => mergedMats.has(y))) { missing.delete(n); mergedNodes.push(n); }
        }
        // keep the parents of merged nodes too
        for (const n of mergedNodes) { let p = pr.nodes.get(n).parentN; while (p >= 0) { missing.delete(p); p = pr.nodes.get(p).parentN; } }
      }
      inst.hiddenNodes = [...missing].filter((n) => !missing.has(pr.nodes.get(n).parentN)).map((n) => ({ n }));
      if (mergedNodes.length) inst.mergedNodes = mergedNodes.map((n) => ({ n }));
      // transforms that differ from the pristine model
      inst.nodeTransforms = [];
      for (const [n, no] of rec.nodes) {
        const pi = pr.nodes.get(n); if (!pi) continue;
        const expParent = pi.parentN < 0 ? o : rec.nodes.get(pi.parentN);
        if (no.parent !== expParent) {
          reparents.push({ instance: rec.name, n, parent: ref(no.parent), local: m16(no.matrix), path: pathNames(no) });
          continue;
        }
        let d = 0; for (let i = 0; i < 16; i++) d = Math.max(d, Math.abs(no.matrix.elements[i] - pi.matrix.elements[i]));
        if (d > 1e-5) inst.nodeTransforms.push({ n, local: m16(no.matrix) });
      }
      // material / shadow overrides
      inst.materialOverrides = [];
      const noCastN = new Set(), castN = new Set();
      const meshObjs = [];
      for (const [n, no] of rec.nodes) if (no.isMesh) meshObjs.push({ obj: no, n, surface: 0, pr: pr.nodes.get(n)?.obj });
      for (const [k, po] of rec.prims) { const pn = tagOf(po.parent)?.n; if (pn === undefined || pn === null) continue; meshObjs.push({ obj: po, n: pn, surface: tagOf(po).p ?? 0, pr: pr.prims.get(k) }); }
      for (const mo of meshObjs) {
        (mo.obj.castShadow ? castN : noCastN).add(mo.n);
        const cur = mo.obj.material, orig = mo.pr?.material;
        if (!orig || cur === orig || Array.isArray(cur)) continue;
        const diff = materialDiff(cur, orig, `${rec.name}:${mo.obj.name}`);
        if (diff && mo.pr && mo.obj.geometry !== mo.pr.geometry) { diff.set.geometryChanged = true; warn(`override ${rec.name}:${mo.obj.name}: the web build replaced this primitive's geometry (e.g. generated UVs) — Godot keeps the original mesh`); }
        if (diff) inst.materialOverrides.push({ n: mo.n, surface: mo.surface, material: orig.name || '', ...diff });
      }
      for (const n of castN) noCastN.delete(n);
      if (noCastN.size) inst.noCastShadow = [...noCastN].map((n) => ({ n }));
      if (!castN.size && noCastN.size) inst.castShadow = false;
      instances.push(inst);
    }
    // export
    const exporter = new GLTFExporter();
    const glb = await exporter.parseAsync(exportScene, { binary: true, onlyVisible: false, trs: false, maxTextureSize: 4096 });
    X.store('level.glb', glb);
    // shadow casters (separate file: easy to load as SHADOWS_ONLY geometry)
    const casterScene = new THREE.Scene(); casterScene.name = 'shadow_casters';
    const casterMat = new THREE.MeshStandardMaterial({ name: 'shadow_caster', color: 0x000000 });
    for (const [o, info] of S.procNodes) {
      if (info.kind !== 'caster') continue;
      const g = exportGeometry(o.geometry, null, false, false); if (!g) continue;
      const m = new THREE.Mesh(g, casterMat); m.name = uniqueName(names, (o.name || 'shadow_caster').replace(/[^A-Za-z0-9_]/g, '_'));
      o.matrixWorld.decompose(m.position, m.quaternion, m.scale);
      casterScene.add(m);
    }
    if (casterScene.children.length) X.store('level_shadow_casters.glb', await exporter.parseAsync(casterScene, { binary: true, onlyVisible: false }));
    X.level = {
      roots: levelRoots, hidden, noCastShadow: noCast, noReceiveShadow: noReceive, materialHints: hints, skipped, attachments, reparents, instances,
      stats: { ...meshStats, nodes: levelName.size, materials: [...MAT.values()].filter((r) => r.def).length },
      materials: Object.fromEntries([...MAT.values()].filter((r) => r.def).map((r) => [r.id, r.def])),
    };
    return { roots: levelRoots.length, nodes: levelName.size, ...meshStats, skipped: skipped.length, instances: instances.length, glb: X.size('level.glb'), casters: X.size('level_shadow_casters.glb') };
  };

  /** Differences between an instance material and the pristine model material (Godot: duplicate + set). */
  function materialDiff(cur, orig, where) {
    const set = {};
    const cc = (a, b) => a && b && (Math.abs(a.r - b.r) > 1e-5 || Math.abs(a.g - b.g) > 1e-5 || Math.abs(a.b - b.b) > 1e-5);
    if (cur.type !== orig.type) set.type = cur.type;
    if (cc(cur.color, orig.color) || (cur.opacity ?? 1) !== (orig.opacity ?? 1)) set.albedo = { srgb: srgbHex(cur.color), linear: lin3(cur.color), alpha: r6(cur.opacity ?? 1) };
    for (const k of ['roughness', 'metalness', 'alphaTest', 'envMapIntensity', 'emissiveIntensity', 'clearcoat', 'clearcoatRoughness', 'specularIntensity', 'ior', 'sheen', 'sheenRoughness', 'aoMapIntensity'])
      if (cur[k] !== undefined && (orig[k] === undefined || Math.abs(cur[k] - orig[k]) > 1e-6)) set[k] = r6(cur[k]);
    if (cc(cur.emissive, orig.emissive)) set.emissive = { srgb: srgbHex(cur.emissive), linear: lin3(cur.emissive) };
    if (cur.transparent !== orig.transparent) set.transparent = !!cur.transparent;
    if (cur.side !== orig.side) set.doubleSided = cur.side === THREE.DoubleSide;
    if (cur.depthWrite !== orig.depthWrite) set.depthWrite = cur.depthWrite;
    if (cur.blending !== orig.blending) set.blending = cur.blending === THREE.AdditiveBlending ? 'additive' : cur.blending === THREE.NormalBlending ? 'normal' : String(cur.blending);
    if (cur.alphaToCoverage !== orig.alphaToCoverage) set.alphaToCoverage = !!cur.alphaToCoverage;
    if (cur.vertexColors !== orig.vertexColors) set.vertexColors = !!cur.vertexColors;
    const texSlots = { map: 'albedo_texture', normalMap: 'normal_texture', roughnessMap: 'roughness_texture', metalnessMap: 'metallic_texture', aoMap: 'ao_texture', emissiveMap: 'emission_texture', alphaMap: 'alpha_texture' };
    const tex = {};
    for (const [k, gname] of Object.entries(texSlots)) {
      const a = cur[k], b = orig[k];
      if (a === b) continue;
      if (a && b && a.image === b.image) {
        const ta = texUV(a), tb = texUV(b);
        if (m3eq(ta, tb)) continue;
      }
      if (!a) { tex[gname] = null; continue; }
      const usage = k === 'normalMap' ? 'normal' : (k === 'map' || k === 'emissiveMap') ? 'color' : 'data';
      const T = texUV(a); // Godot samples the original model's UVs (glTF convention) through uv1_scale/offset
      tex[gname] = { img: imageOf(a, usage, `${where}_${k}`.replace(/[^A-Za-z0-9_]/g, '_')), uv1_scale: [r6(T.elements[0]), r6(T.elements[4])], uv1_offset: [r6(T.elements[6]), r6(T.elements[7])] };
      if (Math.abs(T.elements[1]) > 1e-6 || Math.abs(T.elements[3]) > 1e-6) warn(`override ${where}: rotated texture transform not representable`);
    }
    if (Object.keys(tex).length) set.textures = tex;
    if (!Object.keys(set).length) return null;
    return { set };
  }

  // ---------------------------------------------------------------------------------------------- world meta
  X.worldMeta = () => {
    const W = game.world, P = W.props, E = W.extras, Lg = W.lighting, S = X.S, scene = game.scene;
    scene.updateMatrixWorld(true);
    const handleIdOf = new Map(Object.entries(W.handles || {}).map(([id, h]) => [h.object, id]));
    const contentsOf = new Map(); for (const [id, h] of Object.entries(W.handles || {})) if (h.contents) contentsOf.set(h.contents, id);
    const meta = {};
    // items
    meta.items = {};
    for (const [id, o] of Object.entries(W.items || {})) {
      let inside = null; for (let n = o.parent; n; n = n.parent) if (contentsOf.has(n)) { inside = contentsOf.get(n); break; }
      meta.items[id] = { ref: ref(o), inside, parent: o.parent === scene ? null : ref(o.parent), local: m16(o.matrix), transform: m16(o.matrixWorld), name: o.name };
      if (!meta.items[id].ref) warn('item not exported', id);
    }
    meta.clues = Object.fromEntries(Object.entries(W.clues || {}).map(([k, o]) => [k, ref(o)]));
    const tv = W.tv;
    meta.tv = tv ? {
      object: ref(tv.object), screen: ref(P?._tvState?.screen), screenPosition: v3(tv.screenPosition), isOn: !!tv.isOn,
      screenSize: [0.292, 0.212], curvature: 'z = 0.1237 - 0.9 (x^2 + y^2) in screen-local space', color: [1.35, 1.4, 1.5],
    } : null;
    meta.hideSpots = (W.hideSpots || []).map((h) => {
      const o = {};
      for (const [k, v] of Object.entries(h)) {
        if (k === 'door') o.door = handleIdOf.get(v?.object) || null;
        else if (v && typeof v === 'object' && !Array.isArray(v) && !v.isObject3D) o[k] = JSON.parse(JSON.stringify(v));
        else if (typeof v !== 'function' && !v?.isObject3D) o[k] = v;
      }
      return o;
    });
    // digit decals (duck / horse): Godot creates them in set_clue_digits()
    meta.clueDecals = {};
    for (const [clue, d] of [['duck', P?._duckDecal], ['horse', P?._horseDecal]]) {
      if (!d) continue;
      const g = d.geometry?.parameters || {};
      meta.clueDecals[clue] = {
        parent: ref(d.parent), local: m16(d.matrix), transform: m16(d.matrixWorld), size: [r6(g.width ?? 0), r6(g.height ?? 0)],
        style: clue === 'horse' ? 'tape' : 'marker', facing: 'down (plane rotated +90 deg about X)', textures: `textures/decals/digit_${clue === 'horse' ? 'tape' : 'marker'}_<d>.png`,
        material: { roughness: d.material.roughness, transparent: true, depthWrite: false, polygonOffset: [d.material.polygonOffsetFactor, d.material.polygonOffsetUnits] },
      };
    }
    // colliders / occluders / proxies
    meta.colliders = (W.colliders || []).map((c) => ({ min: [r6(c.minX), r6(c.minY), r6(c.minZ)], max: [r6(c.maxX), r6(c.maxY), r6(c.maxZ)], tag: c.tag, enabled: c.enabled !== false }));
    const bbox = (o) => { const g = o.geometry; if (!g) return null; if (!g.boundingBox) g.computeBoundingBox(); return { min: v3(g.boundingBox.min), max: v3(g.boundingBox.max) }; };
    meta.occluders = (W.occluders || []).map((o) => {
      const r = { name: o.name || '', transform: m16(o.matrixWorld), box: bbox(o), ref: ref(o) };
      if (S.procNodes.has(o) && S.procNodes.get(o).kind === 'proxy') { r.parent = o.parent === scene ? null : ref(o.parent); r.local = m16(o.matrix); }
      return r;
    });
    meta.proxies = [];
    for (const [o, info] of S.procNodes) {
      if (info.kind !== 'proxy') continue;
      let owner = null;
      for (let n = o; n && !owner; n = n.parent) { if (handleIdOf.has(n)) owner = { handle: handleIdOf.get(n) }; }
      if (!owner) for (const [id, it] of Object.entries(W.items || {})) { for (let n = o; n; n = n.parent) if (n === it) { owner = { item: id }; break; } if (owner) break; }
      meta.proxies.push({ name: o.name, owner, occluder: (W.occluders || []).includes(o), interact: !!o.userData?.interactProxy, parent: o.parent === scene ? null : ref(o.parent), local: m16(o.matrix), transform: m16(o.matrixWorld), box: bbox(o) });
    }
    // lights (reference values; the look module owns the Godot lights)
    meta.lights = [];
    const camRoot = game.camera, entRoot = game.entity?.root;
    scene.traverse((o) => {
      if (!o.isLight) return;
      let owner = 'world'; for (let n = o; n; n = n.parent) { if (n === camRoot) owner = 'player'; if (n === entRoot) owner = 'entity'; }
      const L = { name: o.name || '', type: o.type, owner, path: pathNames(o), color: { srgb: srgbHex(o.color), linear: lin3(o.color) }, intensity: r6(o.intensity), position: v3(o.getWorldPosition(new THREE.Vector3())), castShadow: !!o.castShadow, visible: o.visible };
      if (o.distance !== undefined) L.distance = r6(o.distance);
      if (o.decay !== undefined) L.decay = r6(o.decay);
      if (o.isSpotLight) { L.angle = r6(o.angle); L.penumbra = r6(o.penumbra); }
      if (o.target) L.target = v3(o.target.getWorldPosition(new THREE.Vector3()));
      if (o.isHemisphereLight) L.groundColor = { srgb: srgbHex(o.groundColor), linear: lin3(o.groundColor) };
      if (o.castShadow && o.shadow) L.shadow = { mapSize: [o.shadow.mapSize.x, o.shadow.mapSize.y], bias: o.shadow.bias, normalBias: o.shadow.normalBias, radius: o.shadow.radius };
      meta.lights.push(L);
    });
    meta.environment = {
      background: scene.background?.isColor ? { srgb: srgbHex(scene.background), linear: lin3(scene.background) } : null,
      fog: scene.fog ? { type: scene.fog.type, color: srgbHex(scene.fog.color), near: scene.fog.near, far: scene.fog.far, density: scene.fog.density } : null,
      toneMapping: game.renderer?.webgl?.toneMapping, exposure: game.renderer?.webgl?.toneMappingExposure, quality: game.renderer?.quality,
    };
    // runtime helpers for the world module (nodes it animates and the parameters the web version uses)
    const A = {};
    const fanBlades = P?._fanBlades;
    if (fanBlades) A.fan = { blades: ref(fanBlades), axis: 'y', speed: 2.4, spinUpRate: 0.45, spinDownRate: 0.16, note: 'speed += (target - speed) * min(1, dt * rate); blades.rotation.y += speed * dt' };
    if (P?._gfHands) A.grandfatherClock = {
      formula: 'hand.rotation.z (Euler XYZ, other axes kept) = (PI/2 - fraction * 2PI) - a0 ; hours: fraction = (h % 12) / 12, minutes: (m % 60) / 60; clue digit d: hours = d, minutes = 0',
      hour: P._gfHands.hour ? { node: ref(P._gfHands.hour.node), a0: r6(P._gfHands.hour.a0), euler: [r6(P._gfHands.hour.node.rotation.x), r6(P._gfHands.hour.node.rotation.y)] } : null,
      minute: P._gfHands.minute ? { node: ref(P._gfHands.minute.node), a0: r6(P._gfHands.minute.a0), euler: [r6(P._gfHands.minute.node.rotation.x), r6(P._gfHands.minute.node.rotation.y)] } : null,
    };
    if (P?._acHands) A.alarmClock = {
      formula: 'node.quaternion = axisAngle(+Z, angle - a0) * base ; angle = PI/2 - fraction * 2PI (second hand ticks with an outBack ease over 0.09 s); starts at 03:07:12',
      hands: Object.fromEntries(Object.entries(P._acHands).filter(([, v]) => v).map(([k, v]) => [k, { node: ref(v.node), a0: r6(v.a0), base: q4(v.base) }])),
    };
    if (P?._rock) A.rockingChair = { root: ref(P._rock.root), pivot: ref(P._rock.pivot), radius: P._rock.R, formula: 'th = amp * sin(2PI/1.75 * t), amp 0.11 (0.9 s ease-in, 2.2 s decay); pivot.rotation.x = th; pivot.position.z = R * th' };
    const lock = P?._lock;
    if (lock) A.padlock = {
      lock: ref(lock), shackle: ref(lock.userData.shackle), shackleLift: 0.0095, wheels: (lock.userData.wheels || []).map(ref),
      wheelFormula: 'wheel.rotation.x = ((digit + 0.5) / 10) * 2PI', rest: { local: m16(lock.matrix) },
      fallen: { position: [0.05, 0.0075, r6(0.053 * (P.objects?.lockedBox?.scale.x || 1) + 0.022)], euler: [-Math.PI / 2, 0, 0.5], note: 'local to the lock parent (box frame, real metres)' },
    };
    if (P?._lever) A.lever = { group: ref(P._lever.handle.object), formula: 'pivot.rotation.x = 0.6 - 1.2 * v (v 1 = ON)' };
    if (P?._ledMat) { let led = null; scene.traverse((o) => { if (!led && o.isMesh && o.material === P._ledMat) led = o; }); A.smokeDetectorLed = { node: ref(led), emissive: srgbHex(P._ledMat.emissive), blink: 'emissiveIntensity 6 for 0.09 s every 38-46 s' }; }
    if (W.codeNote) A.codeNote = { node: ref(W.codeNote) };
    if (E?.mirror) A.mirror = { glass: ref(E.mirror.glass), root: ref(E.mirror.root), center: v3(E.mirror.center), normal: v3(E.mirror.normal) };
    if (E?.crt) A.oldCrt = { screen: ref(E.crt.screen), tv: ref(E.crt.root), soundPos: v3(E.crt.pos), note: 'flickers ~1.9 s when power comes back (ExtraProps.crtFlicker)' };
    if (E?.chain) A.pullChain = { pivot: ref(E.chain.pivot), formula: 'rotation.z = sin(t*8.2)*kick + sin(t*1.3)*0.006; rotation.x = sin(t*7.7+1.3)*kick*0.55; kick decays exp(-0.35 t), min 0.012' };
    if (Lg?.bowl) A.ceilingBowl = { node: ref(Lg.bowl), note: 'emissive bowl of the ceiling fan light (lighting module drives it)' };
    if (Lg?.strip) A.doorStrip = { node: ref(Lg.strip), note: 'emissive light strip under the upstairs door' };
    if (W.architecture?.hall) A.upperHall = { node: ref(W.architecture.hall), note: 'visible only while door.upstairs is open (t > 0.002)' };
    meta.anim = A;
    X.worldMetaOut = meta;
    return meta;
  };

  // ---------------------------------------------------------------------------------------------- handles
  const HANDLE_INFO = {
    'door.upstairs': { kind: 'door', duration: [1.1, 1.1], sfx: { open: ['door_creak_open', 1, 1], close: ['door_close', 1, 1] }, ease: 'open 1-(1-k)^3, close k*k*(1.6-0.6k)' },
    'door.closet': { kind: 'door', duration: [0.6, 0.6], sfx: { open: ['door_creak_open', 0.5, 1.3], close: ['door_close', 0.45, 1.35] }, ease: 'open 1-(1-k)^3, close k*k*(1.6-0.6k)' },
    'dresser.drawerTop': { kind: 'drawer', duration: [0.55, 0.45], sfx: { open: ['drawer_open', 1, 1], close: ['drawer_close', 1, 1] } },
    'dresser.drawerMid': { kind: 'drawer', duration: [0.55, 0.45], sfx: { open: ['drawer_open', 1, 1], close: ['drawer_close', 1, 1] } },
    'dresser.drawerBottom': { kind: 'drawer', duration: [0.55, 0.45], sfx: { open: ['drawer_open', 1, 1], close: ['drawer_close', 1, 1] } },
    'endTable.drawer': { kind: 'drawer', duration: [0.5, 0.4], sfx: { open: ['drawer_open', 1, 1], close: ['drawer_close', 1, 1] } },
    'alcoveCabinet.drawer_01': { kind: 'drawer', duration: [0.55, 0.45], sfx: { open: ['drawer_open', 1, 1], close: ['drawer_close', 1, 1] } },
    'alcoveCabinet.drawer_02': { kind: 'drawer', duration: [0.55, 0.45], sfx: { open: ['drawer_open', 1, 1], close: ['drawer_close', 1, 1] } },
    'alcoveCabinet.door_01': { kind: 'cabinetDoor', duration: [0.75, 0.6], sfx: { open: ['cabinet_open', 1, 1], close: ['cabinet_close', 1, 1] } },
    'alcoveCabinet.door_02': { kind: 'cabinetDoor', duration: [0.75, 0.6], sfx: { open: ['cabinet_open', 1, 1], close: ['cabinet_close', 1, 1] } },
    'powerBox.door': { kind: 'cabinetDoor', duration: [0.7, 0.55], sfx: { open: ['cabinet_open', 0.9, 1], close: ['cabinet_close', 0.9, 1] } },
    'powerBox.lever': { kind: 'lever', duration: [0.2, 0.2], sfx: { open: ['breaker_flip', 1, 1], close: ['breaker_flip', 1, 1] }, note: 'open = ON (initial state); setOn(on) flips it and calls world.set_power(on)' },
    'lockedBox.lid': { kind: 'lid', duration: [0.85, 0.5], sfx: { open: ['box_open', 0.8, 1], close: ['cabinet_close', 0.8, 1] }, ease: 'open outBack(c1=1.3), close inOut', note: 'opening also pops the padlock off (lockedBox.lock)' },
    'lockedBox.lock': { kind: 'padlock', duration: [0.68, 0.0], sfx: { open: ['unlock', 1, 1], close: null }, note: 'open = shackle pops (0.18 s, outBack) then the lock falls onto the console (0.5 s, see anim.padlock); close = reset' },
  };
  function snap(root) { const m = new Map(); root.updateMatrixWorld(true); root.traverse((o) => { if (o.matrixAutoUpdate) o.updateMatrix(); m.set(o, o.matrix.clone()); }); return m; }
  async function runHandle(h, open) {
    const p = open ? h.open() : h.close();
    await Promise.race([Promise.resolve(p), sleep(5000)]);
    await frames(3);
  }
  X.handles = async () => {
    const W = game.world, out = {};
    const order = Object.keys(W.handles || {});
    // the padlock first (the lid pops it off as a side effect)
    order.sort((a, b) => (a === 'lockedBox.lock' ? -1 : b === 'lockedBox.lock' ? 1 : 0));
    for (const id of order) {
      const h = W.handles[id];
      const obj = h.object;
      const info = HANDLE_INFO[id] || { kind: 'unknown' };
      const rec = { id, ...info, object: ref(obj), locked: !!h.locked, initiallyOpen: !!h.isOpen, contents: h.contents ? ref(h.contents) : null };
      if (h.contents) rec.contentsParent = ref(h.contents.parent);
      if (!obj) { out[id] = rec; warn('handle without object', id); continue; }
      const wasOpen = !!h.isOpen;
      const A = snap(obj);
      await runHandle(h, !wasOpen);
      const B = snap(obj);
      await runHandle(h, wasOpen);
      const C = snap(obj);
      const moving = [];
      for (const [o, ma] of A) {
        const mb = B.get(o); if (!mb) continue;
        let d = 0; for (let i = 0; i < 16; i++) d = Math.max(d, Math.abs(ma.elements[i] - mb.elements[i]));
        if (d < 1e-6) continue;
        const r = ref(o);
        if (!r) { warn(`handle ${id}: moving node not exported`, pathNames(o)); continue; }
        const closed = wasOpen ? mb : ma, opened = wasOpen ? ma : mb;
        let back = 0; const mc = C.get(o); for (let i = 0; i < 16; i++) back = Math.max(back, Math.abs(mc.elements[i] - ma.elements[i]));
        moving.push({ ref: r, path: pathNames(o), closed: m16(closed), open: m16(opened), restored: back < 1e-4 });
      }
      // primary = the handle object itself if it moves, else its first moving descendant
      let primary = moving.findIndex((mv) => JSON.stringify(mv.ref) === JSON.stringify(rec.object));
      if (primary < 0 && moving.length) primary = 0;
      rec.moving = moving; rec.primary = primary;
      if (!moving.length) warn('handle with no moving node', id);
      out[id] = rec;
    }
    // undo side effects (lid pops the lock; lever toggled the power twice)
    const lh = W.handles['lockedBox.lock'];
    if (lh?.isOpen) { try { await lh.close(); } catch (_) { /* ignore */ } }
    X.handlesOut = out;
    return out;
  };

  // ---------------------------------------------------------------------------------------------- textures for Godot code (UI, decals)
  X.uiTextures = async () => {
    curGroup = 'ui';
    const PT = await import('/src/world/ProcTextures.js');
    await PT.waitFonts(6000);
    const list = [];
    // PNG when the image has transparency (newspaper cut-out, digit decals, TV digit masks), JPEG otherwise
    const put = async (name, canvas, forcePng = false) => {
      const png = forcePng || canvasHasAlpha(canvas);
      const file = png ? name : name.replace(/\.png$/, '.jpg');
      const bytes = await encodeCanvas(canvas, png ? 'image/png' : 'image/jpeg', png ? undefined : 0.92);
      X.store('ui:' + file, bytes); list.push({ name: file, key: 'ui:' + file, w: canvas.width, h: canvas.height, alpha: png, bytes: bytes.byteLength });
    };
    const imgOf = (t) => (t?.texture ? t.texture.image : t?.image);
    await put('notes/note1.png', imgOf(PT.note1Texture()));
    await put('notes/note2_child_drawing.png', imgOf(PT.note2Texture()));
    await put('notes/note3_newspaper.png', imgOf(PT.newspaperTexture()));
    await put('notes/code_note.png', imgOf(PT.codeNoteTexture()));
    let seed = 101;
    for (const kind of ['gardienne', 'maison', 'mer', 'arcenciel']) await put(`notes/drawing_${kind}.png`, imgOf(PT.kidDrawing(kind, seed++, 1)));
    for (let d = 0; d <= 9; d++) {
      await put(`decals/digit_marker_${d}.png`, imgOf(PT.digitDecal(String(d), { onTape: false })));
      await put(`decals/digit_tape_${d}.png`, imgOf(PT.digitDecal(String(d), { onTape: true })));
      // TV digit mask (white glyph on transparent), same drawing as ProcTextures.TVStatic.setDigit at 176x132
      const c = document.createElement('canvas'); c.width = 176; c.height = 132;
      const g = c.getContext('2d'); g.fillStyle = '#fff'; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.font = `bold ${Math.round(132 * 0.72)}px ${PT.FONT.sans}`; g.fillText(String(d), 88, 132 * 0.54);
      await put(`decals/tv_digit_${d}.png`, c, true);
    }
    const fonts = document.fonts ? [...document.fonts].filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight}`) : [];
    return { list, fonts };
  };

  // ---------------------------------------------------------------------------------------------- La Gardienne
  X.gardienne = async (opt = {}) => {
    curGroup = 'gardienne';
    const { GardienneModel } = await import('/src/entity/GardienneModel.js');
    const model = new GardienneModel(game, { quality: 'high' });
    const root = model.root;
    root.position.set(0, 0, 0); root.rotation.set(0, 0, 0); root.updateMatrixWorld(true);
    const bones = model.boneList;
    const rest = bones.map((b) => ({ p: b.position.clone(), q: b.quaternion.clone(), s: b.scale.clone() }));
    const restore = () => { bones.forEach((b, i) => { b.position.copy(rest[i].p); b.quaternion.copy(rest[i].q); b.scale.copy(rest[i].s); }); root.updateMatrixWorld(true); };
    const origRandom = Math.random;
    const seeded = (seed) => { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; };
    const FPS = 30, SUB = 2, dt = 1 / (FPS * SUB);
    const stepLen = (cw, stairs) => (0.6 + (1.0 - 0.6) * cw) * (Math.abs(stairs) > 0.3 ? 0.62 : 1);
    // gait clips: whole number of gait cycles, speed nudged so that the cycle is a whole number of 30 fps frames
    const SPECS = [
      { name: 'idle', mode: 'idle', speed: 0, loop: true, dur: (2 * Math.PI) / 1.25, blend: 0.8, preroll: 3 },
      { name: 'walk', mode: 'walk', speed: 0.95, cycles: 2, loop: true, blend: 0.5, preroll: 3 },
      { name: 'walk_stairs', mode: 'walk', speed: 0.78, stairs: 1, cycles: 3, loop: true, blend: 0.5, preroll: 3 },
      { name: 'walk_stairs_down', mode: 'walk', speed: 0.78, stairs: -1, cycles: 3, loop: true, blend: 0.5, preroll: 3 },
      { name: 'duck_walk', mode: 'walk', speed: 0.95, duck: 1, cycles: 2, loop: true, blend: 0.5, preroll: 3 },
      { name: 'search', mode: 'search', speed: 0, loop: true, dur: 4.0, blend: 0.8, preroll: 3 },
      { name: 'chase', mode: 'chase', speed: 2.9, cycles: 4, loop: true, blend: 0.4, preroll: 3 },
      { name: 'reach', mode: 'reach', speed: 0, loop: true, dur: 3.0, blend: 0.8, preroll: 3 },
      { name: 'jumpscare', mode: 'jumpscare', speed: 0, loop: false, dur: 1.8, preroll: 1.0, prerollMode: 'chase', prerollSpeed: 2.9 },
    ];
    const clips = [], clipMeta = {};
    let seed = 7001;
    const nb = bones.length;
    for (const s of SPECS) {
      Math.random = seeded(seed++);
      restore();
      model.time = 0; model._initPose(); model.pose.glitchT = 1e9; model._hairInit = false;
      let speed = s.speed, F;
      const cw = s.mode === 'chase' ? 1 : 0;
      if (s.cycles) {
        const L = stepLen(cw, s.stairs || 0);
        const period = (2 * L) / speed;
        F = Math.max(2, Math.round(s.cycles * period * FPS));
        speed = (s.cycles * 2 * L * FPS) / F; // exact: cycles * period == F / FPS
      } else F = Math.max(2, Math.round(s.dur * FPS));
      const B = s.loop ? Math.min(F - 1, Math.round((s.blend || 0.5) * FPS)) : 0;
      const ctx = { mode: s.mode, speed, stairs: s.stairs || 0, look: null, jumpT: -1, aggression: 0, eyeshine: 0.15, duck: s.duck || 0 };
      // pre-roll (blend weights, gait springs and hair settle)
      const pctx = s.prerollMode ? { ...ctx, mode: s.prerollMode, speed: s.prerollSpeed || 0 } : ctx;
      for (let t = 0; t < s.preroll; t += dt) model.update(dt, pctx);
      model.pose.glitchT = 1e9;
      const steps = [];
      let frame = 0;
      model.onFootstep = (side) => steps.push({ frame, side });
      const N = F + B + 1;
      const pos = new Float32Array(N * nb * 3), rot = new Float32Array(N * nb * 4);
      let jt = 0;
      for (frame = 0; frame < N; frame++) {
        if (frame > 0) for (let k = 0; k < SUB; k++) { if (s.mode === 'jumpscare') { ctx.jumpT = jt; jt += dt; } model.update(dt, ctx); model.pose.glitchT = 1e9; }
        else if (s.mode === 'jumpscare') { ctx.jumpT = 0; model.update(1e-4, ctx); }
        for (let i = 0; i < nb; i++) {
          const b = bones[i];
          pos.set([b.position.x, b.position.y, b.position.z], (frame * nb + i) * 3);
          rot.set([b.quaternion.x, b.quaternion.y, b.quaternion.z, b.quaternion.w], (frame * nb + i) * 4);
        }
      }
      model.onFootstep = null;
      // output frames 0..F (loop: crossfade the B frames after F into the start, frame F == frame 0)
      const outN = s.loop ? F + 1 : F + 1;
      const P = new Float32Array(outN * nb * 3), Q = new Float32Array(outN * nb * 4);
      const qa = new THREE.Quaternion(), qb = new THREE.Quaternion();
      for (let f = 0; f < outN; f++) {
        const src = s.loop ? (f === F ? 0 : f) : f;
        for (let i = 0; i < nb; i++) {
          let px = pos[(src * nb + i) * 3], py = pos[(src * nb + i) * 3 + 1], pz = pos[(src * nb + i) * 3 + 2];
          qa.fromArray(rot, (src * nb + i) * 4);
          if (s.loop && src < B) {
            const k = src / B, w = k * k * (3 - 2 * k), j = F + src;
            const ex = pos[(j * nb + i) * 3], ey = pos[(j * nb + i) * 3 + 1], ez = pos[(j * nb + i) * 3 + 2];
            px = ex + (px - ex) * w; py = ey + (py - ey) * w; pz = ez + (pz - ez) * w;
            qb.fromArray(rot, (j * nb + i) * 4);
            qb.slerp(qa, w); qa.copy(qb);
          }
          P.set([px, py, pz], (f * nb + i) * 3);
          Q.set([qa.x, qa.y, qa.z, qa.w], (f * nb + i) * 4);
        }
      }
      const times = new Float32Array(outN); for (let f = 0; f < outN; f++) times[f] = f / FPS;
      const tracks = [];
      for (let i = 0; i < nb; i++) {
        const b = bones[i];
        const pv = new Float32Array(outN * 3), qv = new Float32Array(outN * 4);
        let varies = false;
        const r = rest[i].p;
        for (let f = 0; f < outN; f++) {
          pv[f * 3] = P[(f * nb + i) * 3]; pv[f * 3 + 1] = P[(f * nb + i) * 3 + 1]; pv[f * 3 + 2] = P[(f * nb + i) * 3 + 2];
          if (Math.abs(pv[f * 3] - r.x) > 1e-6 || Math.abs(pv[f * 3 + 1] - r.y) > 1e-6 || Math.abs(pv[f * 3 + 2] - r.z) > 1e-6) varies = true;
          let qx = Q[(f * nb + i) * 4], qy = Q[(f * nb + i) * 4 + 1], qz = Q[(f * nb + i) * 4 + 2], qw = Q[(f * nb + i) * 4 + 3];
          if (f > 0 && qx * qv[(f - 1) * 4] + qy * qv[(f - 1) * 4 + 1] + qz * qv[(f - 1) * 4 + 2] + qw * qv[(f - 1) * 4 + 3] < 0) { qx = -qx; qy = -qy; qz = -qz; qw = -qw; }
          qv.set([qx, qy, qz, qw], f * 4);
        }
        if (varies) tracks.push(new THREE.VectorKeyframeTrack(`${b.name}.position`, times, pv));
        tracks.push(new THREE.QuaternionKeyframeTrack(`${b.name}.quaternion`, times, qv));
      }
      const duration = F / FPS;
      clips.push(new THREE.AnimationClip(s.name, duration, tracks));
      const fs = steps.filter((e) => e.frame >= 1 && e.frame <= F).map((e) => ({ t: r4((e.frame % F) / FPS), side: e.side }));
      clipMeta[s.name] = {
        duration: r6(duration), frames: F + 1, fps: FPS, loop: !!s.loop, mode: s.mode, stairs: s.stairs || 0, duck: s.duck || 0,
        speed: r6(speed), cycle: s.cycles ? r6(duration / s.cycles) : null, footsteps: s.loop ? fs.sort((a, b) => a.t - b.t) : steps.map((e) => ({ t: r4(e.frame / FPS), side: e.side })),
        loopBlend: s.loop ? r6(B / FPS) : 0,
      };
    }
    Math.random = origRandom;
    restore();
    (model.eyes || []).forEach((m, i) => { m.name = i === 0 ? 'eye_L' : 'eye_R'; });
    (model.glints || []).forEach((m, i) => { m.name = i === 0 ? 'glint_L' : 'glint_R'; });
    // materials -> placeholders + glTF defs (UV transforms baked into copies of the skinned geometries)
    const meshes = []; root.traverse((o) => { if (o.isMesh) meshes.push(o); });
    const matIds = new Set();
    for (const o of meshes) {
      const e = exportMesh(o);
      if (e.skip) { warn('gardienne mesh skipped', o.name, e.skip); o.visible = false; continue; }
      o.geometry = e.geo; o.material = e.material;
      for (const r of e.recs) matIds.add(r.id);
    }
    root.updateMatrixWorld(true);
    const exporter = new GLTFExporter();
    const glb = await exporter.parseAsync(root, { binary: true, onlyVisible: true, animations: clips, trs: false });
    X.store('gardienne.glb', glb);
    const defs = {}; for (const r of MAT.values()) if (matIds.has(r.id)) defs[r.id] = r.def;
    const bonesMeta = bones.map((b) => ({ name: b.name, parent: b.parent?.isBone ? b.parent.name : null, rest: { position: v3(b.position), quaternion: q4(b.quaternion) } }));
    X.gardienneOut = {
      materials: defs, clips: clipMeta, bones: bonesMeta, boneCount: nb,
      meshes: meshes.map((m) => ({ name: m.name, skinned: !!m.isSkinnedMesh, parent: m.parent?.name, castShadow: m.castShadow, vertices: m.geometry.attributes.position.count })),
      hairChains: (model.hairChains || []).map((c) => ({ id: c.id, bones: c.bones.map((b) => b.name) })),
      attach: { face: { bone: 'head', offset: [0, 0.06, 0.1] }, eyes: { bone: 'head', offset: [0, 0.09, 0.07] }, head: { bone: 'head', offset: [0, 0.07, 0] } },
      glint: { material: model.matGlint.name || 'gardienne_glint', formula: 'emissive energy = 0.25 + eyeshine * 7 (eyeshine 0.08..1, damped 6/s)' },
    };
    return { clips: Object.keys(clipMeta).length, bones: nb, meshes: meshes.length, glb: X.size('gardienne.glb') };
  };

  // ---------------------------------------------------------------------------------------------- verification (three re-import)
  X.verify = async (url) => {
    const gltf = await new GLTFLoader().loadAsync(url + '?v=' + Date.now());
    let nodes = 0, meshes = 0, skinned = 0, bones = 0, textures = 0, missingTex = 0;
    gltf.scene.traverse((o) => {
      nodes++; if (o.isMesh) meshes++; if (o.isSkinnedMesh) skinned++; if (o.isBone) bones++;
      if (o.isMesh) for (const m of Array.isArray(o.material) ? o.material : [o.material]) for (const k of ['map', 'normalMap', 'roughnessMap', 'aoMap', 'emissiveMap']) if (m[k]) { textures++; if (!m[k].image) missingTex++; }
    });
    return { nodes, meshes, skinned, bones, textures, missingTex, animations: gltf.animations.map((a) => ({ name: a.name, duration: r4(a.duration), tracks: a.tracks.length })) };
  };

  X.images = (group) => IMGS.filter((r) => r.group === group).length;
  return { ok: true };
}

// ================================================================================================ NODE SIDE
const GLB_MAGIC = 0x46546c67, CHUNK_JSON = 0x4e4f534a, CHUNK_BIN = 0x004e4942;
function parseGLB(buf) {
  if (buf.readUInt32LE(0) !== GLB_MAGIC) throw new Error('not a GLB');
  let off = 12, json = null, bin = Buffer.alloc(0);
  while (off < buf.length) {
    const len = buf.readUInt32LE(off), type = buf.readUInt32LE(off + 4);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === CHUNK_JSON) json = JSON.parse(data.toString('utf8'));
    else if (type === CHUNK_BIN) bin = Buffer.from(data);
    off += 8 + len;
  }
  return { json, bin };
}
function writeGLB(json, bin) {
  let js = Buffer.from(JSON.stringify(json), 'utf8');
  const jp = (4 - (js.length % 4)) % 4; if (jp) js = Buffer.concat([js, Buffer.alloc(jp, 0x20)]);
  const bp = (4 - (bin.length % 4)) % 4; if (bp) bin = Buffer.concat([bin, Buffer.alloc(bp, 0)]);
  const head = Buffer.alloc(12); head.writeUInt32LE(GLB_MAGIC, 0); head.writeUInt32LE(2, 4);
  const total = 12 + 8 + js.length + (bin.length ? 8 + bin.length : 0); head.writeUInt32LE(total, 8);
  const jh = Buffer.alloc(8); jh.writeUInt32LE(js.length, 0); jh.writeUInt32LE(CHUNK_JSON, 4);
  const parts = [head, jh, js];
  if (bin.length) { const bh = Buffer.alloc(8); bh.writeUInt32LE(bin.length, 0); bh.writeUInt32LE(CHUNK_BIN, 4); parts.push(bh, bin); }
  return Buffer.concat(parts);
}

/** Godot (4.5, naming v2) node paths of a glTF file: index -> "A/B/C" relative to the imported scene root. */
const MODEL_PATHS = new Map();
function modelNodePaths(modelId) {
  if (MODEL_PATHS.has(modelId)) return MODEL_PATHS.get(modelId);
  const f = path.join(ROOT, 'assets/models', modelId + '.glb');
  const { json } = parseGLB(fs.readFileSync(f));
  const nodes = json.nodes || [];
  const used = new Set(), names = [];
  nodes.forEach((n, i) => {
    let name = n.name || (n.mesh !== undefined ? 'Mesh' : n.camera !== undefined ? 'Camera' : 'Node');
    name = name.replace(/[.:@/"%]/g, '_');
    let u = name, k = 1; while (used.has(u)) { k++; u = name + k; }
    used.add(u); names[i] = u;
  });
  const parent = new Array(nodes.length).fill(-1);
  nodes.forEach((n, i) => (n.children || []).forEach((c) => { parent[c] = i; }));
  const paths = names.map((_, i) => { const a = []; for (let k = i; k >= 0; k = parent[k]) a.unshift(names[k]); return a.join('/'); });
  const r = { paths, names, parent };
  MODEL_PATHS.set(modelId, r);
  return r;
}

const sanitizeFile = (s) => String(s || 'tex').replace(/[^A-Za-z0-9_-]/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '').slice(0, 80) || 'tex';
function importStub(usage) {
  const normal = usage.includes('normal');
  return [
    '[remap]', '', 'importer="texture"', 'type="CompressedTexture2D"', '', '[params]', '',
    'compress/mode=2', 'compress/high_quality=false', 'compress/lossy_quality=0.7', `compress/normal_map=${normal ? 1 : 2}`,
    'mipmaps/generate=true', 'mipmaps/limit=-1', 'roughness/mode=0', 'process/fix_alpha_border=true', 'process/size_limit=0', 'detect_3d/compress_to=0', '',
  ].join('\n');
}
function sceneImportStub({ gi = 1, rest = false, loops = null } = {}) {
  const sub = loops ? `{\n"animations": {\n${Object.entries(loops).map(([n, l]) => `"${n}": {\n"save_to_file/enabled": false,\n"settings/loop_mode": ${l ? 1 : 0}\n}`).join(',\n')}\n}\n}` : '{}';
  return [
    '[remap]', '', 'importer="scene"', 'importer_version=1', 'type="PackedScene"', '', '[params]', '',
    'nodes/root_type=""', 'nodes/root_name=""', 'nodes/apply_root_scale=true', 'nodes/root_scale=1.0', 'nodes/import_as_skeleton_bones=false',
    'nodes/use_name_suffixes=false', 'nodes/use_node_type_suffixes=false',
    'meshes/ensure_tangents=true', 'meshes/generate_lods=true', 'meshes/create_shadow_meshes=true', `meshes/light_baking=${gi}`, 'meshes/lightmap_texel_size=0.2', 'meshes/force_disable_compression=false',
    'skins/use_named_skins=true', 'animation/import=true', 'animation/fps=30', 'animation/trimming=false', 'animation/remove_immutable_tracks=true', `animation/import_rest_as_RESET=${rest}`,
    'import_script/path=""', 'materials/extract=0', 'materials/extract_format=0', 'materials/extract_path=""', `_subresources=${sub}`, 'gltf/naming_version=2', 'gltf/embedded_image_handling=1', '',
  ].join('\n');
}

async function pull(page, key) {
  const size = await page.evaluate((k) => window.__X.size(k), key);
  if (size < 0) return null;
  const parts = [];
  const CH = 4 * 1024 * 1024;
  for (let off = 0; off < size; off += CH) parts.push(Buffer.from(await page.evaluate(([k, o, l]) => window.__X.chunk(k, o, l), [key, off, CH]), 'base64'));
  await page.evaluate((k) => window.__X.drop(k), key);
  return Buffer.concat(parts);
}

function writeFile(rel, data) {
  PRODUCED.add(rel);
  const f = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(f), { recursive: true });
  fs.writeFileSync(f, data);
  return f;
}
const PRODUCED = new Set();
function pruneStale(folderRel) {
  const dir = path.join(OUT, folderRel);
  if (!fs.existsSync(dir)) return 0;
  let n = 0;
  for (const f of fs.readdirSync(dir)) {
    const rel = `${folderRel}/${f}`;
    const base = f.endsWith('.import') ? rel.slice(0, -7) : rel;
    if (PRODUCED.has(base)) continue;
    fs.rmSync(path.join(dir, f), { recursive: true, force: true }); n++;
  }
  return n;
}
function keepImport(rel, stub) { // keep an existing (Godot-rewritten) .import file when its params match our preset
  const f = path.join(OUT, rel + '.import');
  if (fs.existsSync(f)) {
    const cur = fs.readFileSync(f, 'utf8');
    const want = stub.split('\n').filter((l) => /^[a-z_/]+=/.test(l) && !l.startsWith('importer') && !l.startsWith('type='));
    if (want.every((l) => cur.includes(l))) return;
  }
  writeFile(rel + '.import', stub);
}

/** Pull images of a group, write them, return id -> uri (relative to the GLB folder). */
async function writeImages(page, group, folder, used) {
  const list = await page.evaluate(([g]) => window.__X.finalizeImages(g, 2048), [group]);
  const map = {};
  const names = used || new Set();
  for (const im of list) {
    if (im.kind === 'missing') continue;
    let rel;
    if (im.kind === 'file') {
      const src = path.join(ROOT, im.path);
      if (!fs.existsSync(src)) { console.warn('[export] missing source image', im.path); continue; }
      const parts = im.path.split('/');
      const base = sanitizeFile(parts.slice(-2).join('_').replace(/\.[a-z]+$/i, ''));
      rel = `textures/shared/${base}${path.extname(src).toLowerCase()}`;
      if (!names.has(rel)) { const b = fs.readFileSync(src); const dst = path.join(OUT, rel); if (!fs.existsSync(dst) || !b.equals(fs.readFileSync(dst))) writeFile(rel, b); else PRODUCED.add(rel); names.add(rel); }
    } else {
      const bytes = await pull(page, im.key);
      let base = sanitizeFile(im.name || im.id), r = `${folder}/${base}.${im.ext}`, k = 2;
      while (names.has(r)) r = `${folder}/${base}_${k++}.${im.ext}`;
      rel = r; names.add(rel);
      const dst = path.join(OUT, rel);
      if (fs.existsSync(dst) && bytes.equals(fs.readFileSync(dst))) PRODUCED.add(rel); else writeFile(rel, bytes); // unchanged: no reimport
    }
    keepImport(rel, importStub(im.usage));
    map[im.id] = { uri: rel, usage: im.usage };
  }
  return map;
}

/** Replace placeholder materials (named "__mat:<id>") with the converted glTF materials and external images. */
function patchGLB(buf, defs, images) {
  const { json, bin } = parseGLB(buf);
  json.images = []; json.textures = []; json.samplers = [];
  const imgIndex = new Map(), texIndex = new Map(), sampIndex = new Map();
  const tex = (r) => {
    const im = images[r.img];
    if (!im) return null;
    if (!imgIndex.has(r.img)) { imgIndex.set(r.img, json.images.length); json.images.push({ uri: im.uri.split('/').map(encodeURIComponent).join('/'), name: path.basename(im.uri) }); }
    const sk = JSON.stringify(r.sampler);
    if (!sampIndex.has(sk)) { sampIndex.set(sk, json.samplers.length); json.samplers.push(r.sampler); }
    const tk = `${r.img}|${sk}`;
    if (!texIndex.has(tk)) { texIndex.set(tk, json.textures.length); json.textures.push({ source: imgIndex.get(r.img), sampler: sampIndex.get(sk) }); }
    return texIndex.get(tk);
  };
  const used = new Set(json.extensionsUsed || []);
  json.materials = (json.materials || []).map((m) => {
    const id = m.name && m.name.startsWith('__mat:') ? m.name.slice(6) : null;
    const d = id ? defs[id] : null;
    if (!d) return m;
    const out = JSON.parse(JSON.stringify(d));
    const fix = (o, k) => { if (!o || !o[k]) return; const t = tex(o[k]); if (t === null) { delete o[k]; return; } const { scale, strength } = o[k]; o[k] = { index: t }; if (scale !== undefined) o[k].scale = scale; if (strength !== undefined) o[k].strength = strength; };
    fix(out.pbrMetallicRoughness, 'baseColorTexture');
    fix(out.pbrMetallicRoughness, 'metallicRoughnessTexture');
    fix(out, 'normalTexture'); fix(out, 'occlusionTexture'); fix(out, 'emissiveTexture');
    for (const k of Object.keys(out.extensions || {})) used.add(k);
    return out;
  });
  // mesh names: distinct from node names (Godot uniquifies names across a glTF file)
  (json.meshes || []).forEach((m, i) => { m.name = `mesh_${i}_${m.name || ''}`.replace(/_$/, ''); });
  if (!json.images.length) { delete json.images; delete json.textures; delete json.samplers; }
  if (used.size) json.extensionsUsed = [...used];
  json.asset = { ...(json.asset || {}), generator: 'La Gardienne tools/export-godot.cjs (three.js GLTFExporter r170 + material/texture pass)' };
  return writeGLB(json, bin);
}

/** in-page ref {instance, n, surface} -> {instance, node: "Godot/path", surface} */
function makeResolver(instModels) {
  return function resolve(r) {
    if (!r || typeof r !== 'object') return r;
    if (r.instance !== undefined && r.n !== undefined) {
      const model = instModels.get(r.instance);
      const p = model ? modelNodePaths(model).paths[r.n] : null;
      const o = { instance: r.instance, node: p ?? `#${r.n}` };
      if (r.surface !== undefined && r.surface !== null) o.surface = r.surface;
      return o;
    }
    return r;
  };
}
function deepResolve(v, resolve) {
  if (Array.isArray(v)) return v.map((x) => deepResolve(x, resolve));
  if (v && typeof v === 'object') {
    const o = {};
    if (v.instance !== undefined && v.n !== undefined) Object.assign(o, resolve({ instance: v.instance, n: v.n, surface: v.surface }));
    for (const [k, x] of Object.entries(v)) if (!(k in o) && k !== 'n' && !(k === 'surface' && x === undefined)) o[k] = deepResolve(x, resolve);
    return o;
  }
  return v;
}

// ================================================================================================ MAIN
(async () => {
  if (!THREE_DIR) console.warn('[export] THREE_DIR not set: three.js will be fetched from the CDN');
  if (FONTS_DIR && !fs.existsSync(path.join(FONTS_DIR, 'fonts.css'))) console.warn('[export] --fonts: no fonts.css in', FONTS_DIR);
  await acquireLock();
  await new Promise((r) => server.listen(Number(process.env.PORT || 0), '127.0.0.1', r));
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required', '--disable-gpu-watchdog', '--disable-renderer-backgrounding', '--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows'] });
  const size = String(opt('size', '640x360')).split('x').map(Number);
  const ctx = await browser.newContext({ viewport: { width: size[0], height: size[1] } });
  const page = await ctx.newPage();
  page.setDefaultTimeout(0);
  let pageErrors = 0;
  page.on('console', (m) => { if (m.type() === 'error' || (m.type() === 'warning' && !m.text().startsWith('[export]'))) console.log(`[${m.type()}]`, m.text().slice(0, 300)); else if (VERBOSE) console.log('[log]', m.text().slice(0, 300)); });
  page.on('pageerror', (e) => { pageErrors++; console.log('[pageerror]', e.message); });
  const fontsCss = FONTS_DIR && fs.existsSync(path.join(FONTS_DIR, 'fonts.css')) ? fs.readFileSync(path.join(FONTS_DIR, 'fonts.css'), 'utf8') : null;
  await page.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ status: 200, contentType: 'text/css', body: fontsCss || '' }));
  await page.route('https://fonts.gstatic.com/**', (r) => {
    const f = fontFile(new URL(r.request().url()).pathname);
    if (f && fs.existsSync(f)) return r.fulfill({ status: 200, contentType: 'font/woff2', body: fs.readFileSync(f) });
    return r.abort();
  });
  if (THREE_DIR) {
    await page.route('https://cdn.jsdelivr.net/npm/three@0.170.0/**', (route) => {
      const rel = route.request().url().split('three@0.170.0/')[1];
      const f = path.join(THREE_DIR, rel);
      if (!fs.existsSync(f)) return route.fulfill({ status: 404, body: 'nf' });
      route.fulfill({ status: 200, contentType: 'text/javascript', body: fs.readFileSync(f) });
    });
  }
  const t0 = Date.now();
  const url = `http://127.0.0.1:${port}/index.html?debug&noentity&quality=${QUALITY}`;
  console.log('[export] open', url);
  await page.goto(url);
  await page.waitForFunction(() => window.__game && window.__game.state !== 'loading', null, { timeout: 15 * 60e3 });
  console.log(`[export] game ready in ${((Date.now() - t0) / 1000).toFixed(1)} s (state ${await page.evaluate(() => window.__game.state)})`);
  // all textures loaded (the stubbed bakeEnvironment used to wait for them)
  await page.evaluate(async () => {
    const t0 = performance.now();
    const pending = () => { let n = 0; window.__game.scene.traverse((o) => { if (!o.material) return; for (const m of Array.isArray(o.material) ? o.material : [o.material]) for (const k of Object.keys(m)) { const t = m[k]; if (t && t.isTexture && t.image && t.image.complete === false) n++; } }); return n; };
    while (pending() > 0 && performance.now() - t0 < 30000) await new Promise((r) => setTimeout(r, 100));
    await new Promise((r) => setTimeout(r, 500));
  });
  await page.evaluate(PAGE_LIB);
  fs.mkdirSync(OUT, { recursive: true });
  const report = { date: new Date().toISOString(), url: url.replace(/:\d+\//, ':PORT/'), files: {} };
  const usedNames = new Set();

  // ----------------------------------------------------------------------------------------- level
  if (ONLY.has('level')) {
    console.log('[export] scan', JSON.stringify(await page.evaluate(() => window.__X.scan())));
    const lv = await page.evaluate(() => window.__X.exportLevel());
    console.log('[export] level', JSON.stringify(lv));
    const world = await page.evaluate(() => window.__X.worldMeta());
    const handles = await page.evaluate(() => window.__X.handles());
    console.log('[export] handles', Object.keys(handles).length);
    const L = await page.evaluate(() => { const l = window.__X.level; return { ...l }; });
    // textures + GLBs
    const images = await writeImages(page, 'level', 'textures/level', usedNames);
    const glb = await pull(page, 'level.glb');
    writeFile('level.glb', patchGLB(glb, L.materials, images));
    keepImport('level.glb', sceneImportStub({ gi: 1 }));
    const casters = await pull(page, 'level_shadow_casters.glb');
    if (casters) { writeFile('level_shadow_casters.glb', patchGLB(casters, {}, {})); keepImport('level_shadow_casters.glb', sceneImportStub({ gi: 0 })); }
    // override textures referenced by materialOverrides
    const instModels = new Map(L.instances.map((i) => [i.name, i.model]));
    const resolve = makeResolver(instModels);
    const texPath = (id) => (images[id] ? `${RES_PREFIX}/${images[id].uri}` : null);
    const instances = L.instances.map((i) => {
      const o = { ...i, scene: `res://assets/models/${i.model}.glb` };
      const P = modelNodePaths(i.model).paths;
      o.hiddenNodes = (i.hiddenNodes || []).map((h) => P[h.n]);
      if (i.mergedNodes) o.mergedNodes = i.mergedNodes.map((h) => P[h.n]);
      o.nodeTransforms = (i.nodeTransforms || []).map((t) => ({ node: P[t.n], local: t.local }));
      o.materialOverrides = (i.materialOverrides || []).map((m) => {
        const set = { ...m.set };
        if (set.textures) set.textures = Object.fromEntries(Object.entries(set.textures).map(([k, v]) => [k, v ? { path: texPath(v.img), uv1_scale: v.uv1_scale, uv1_offset: v.uv1_offset } : null]));
        return { node: P[m.n], surface: m.surface, material: m.material, set };
      });
      if (i.noCastShadow) o.noCastShadow = i.noCastShadow.map((h) => P[h.n]);
      o.parent = i.parent ? deepResolve(i.parent, resolve) : null;
      return o;
    });
    const meta = {
      version: 1,
      generator: 'tools/export-godot.cjs',
      source: { url: report.url, date: report.date, three: '0.170.0', quality: QUALITY },
      conventions: {
        units: 'metres, +Y up, north = -Z (identical in the web build, glTF and Godot)',
        matrix: '16 floats, column-major (three.js Matrix4.elements): basis columns x=[0,1,2] y=[4,5,6] z=[8,9,10], origin=[12,13,14] — see meta_util.gd mat16()',
        refs: '{level: "<node name in level.glb>"} | {instance: "<instances[].name>"} | {instance, node: "<path inside res://assets/models/<model>.glb>", surface?}',
        colors: 'srgb = hex as authored in three (use for StandardMaterial3D.albedo_color), linear = three.js working values',
      },
      files: { level: `${RES_PREFIX}/level.glb`, shadowCasters: casters ? `${RES_PREFIX}/level_shadow_casters.glb` : null, gardienne: `${RES_PREFIX}/gardienne.glb`, textures: `${RES_PREFIX}/textures/` },
      level: { roots: L.roots, hidden: L.hidden, noCastShadow: L.noCastShadow, noReceiveShadow: L.noReceiveShadow, materialHints: L.materialHints, skipped: L.skipped, stats: L.stats },
      instances,
      attachments: deepResolve(L.attachments, resolve),
      reparent: deepResolve(L.reparents, resolve),
      handles: deepResolve(handles, resolve),
      ...deepResolve(world, resolve),
    };
    meta.warnings = await page.evaluate(() => window.__X.warnings.slice());
    writeFile('level_meta.json', JSON.stringify(meta, null, 1));
    report.files.level = { bytes: fs.statSync(path.join(OUT, 'level.glb')).size, images: Object.keys(images).length };
    console.log('[export] verify level.glb (three)', JSON.stringify(await page.evaluate((u) => window.__X.verify(u), '/' + path.relative(ROOT, path.join(OUT, 'level.glb')).split(path.sep).join('/'))));
  }

  // ----------------------------------------------------------------------------------------- gardienne
  if (ONLY.has('gardienne')) {
    const w0 = await page.evaluate(() => window.__X.warnings.length);
    const g = await page.evaluate(() => window.__X.gardienne());
    console.log('[export] gardienne', JSON.stringify(g));
    const G = await page.evaluate(() => window.__X.gardienneOut);
    const images = await writeImages(page, 'gardienne', 'textures/gardienne', usedNames);
    const glb = await pull(page, 'gardienne.glb');
    writeFile('gardienne.glb', patchGLB(glb, G.materials, images));
    keepImport('gardienne.glb', sceneImportStub({ gi: 0, rest: true, loops: Object.fromEntries(Object.entries(G.clips).map(([k, v]) => [k, v.loop])) }));
    const gm = { version: 1, generator: 'tools/export-godot.cjs', source: { url: report.url, date: report.date, model: 'src/entity/GardienneModel.js' }, file: `${RES_PREFIX}/gardienne.glb`, ...G };
    delete gm.materials;
    gm.materials = Object.values(G.materials).map((d) => ({ name: d.name, extras: d.extras }));
    gm.warnings = await page.evaluate((n) => window.__X.warnings.slice(n), w0);
    writeFile('gardienne_meta.json', JSON.stringify(gm, null, 1));
    console.log('[export] verify gardienne.glb (three)', JSON.stringify(await page.evaluate((u) => window.__X.verify(u), '/' + path.relative(ROOT, path.join(OUT, 'gardienne.glb')).split(path.sep).join('/'))));
  }

  // ----------------------------------------------------------------------------------------- UI / decal textures
  if (ONLY.has('textures')) {
    const t = await page.evaluate(() => window.__X.uiTextures());
    for (const it of t.list) {
      const rel = 'textures/' + it.name;
      const bytes = await pull(page, it.key);
      const dst = path.join(OUT, rel);
      if (fs.existsSync(dst) && bytes.equals(fs.readFileSync(dst))) PRODUCED.add(rel); else writeFile(rel, bytes);
      keepImport(rel, importStub(['color']).replace('compress/mode=2', 'compress/mode=0').replace('detect_3d/compress_to=0', 'detect_3d/compress_to=1'));
    }
    console.log(`[export] ui textures: ${t.list.length} (fonts loaded: ${t.fonts.join(', ') || 'none — fallback fonts'})`);
  }

  const pruned = [...(ONLY.has('level') ? ['textures/level'] : []), ...(ONLY.has('gardienne') ? ['textures/gardienne'] : []),
    ...(ONLY.has('textures') ? ['textures/notes', 'textures/decals'] : []), ...(ONLY.has('level') && ONLY.has('gardienne') ? ['textures/shared'] : [])]
    .reduce((n, d) => n + pruneStale(d), 0);
  if (pruned) console.log(`[export] removed ${pruned} stale files`);
  const warnings = await page.evaluate(() => window.__X.warnings.length);
  console.log(`[export] done in ${((Date.now() - t0) / 1000).toFixed(1)} s — ${warnings} warnings, ${pageErrors} page errors → ${path.relative(ROOT, OUT)}`);
  await browser.close();
  server.close();
  process.exit(pageErrors ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
