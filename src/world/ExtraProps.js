import * as THREE from 'three';
import { Reflector } from 'three/addons/objects/Reflector.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as L from '../config/layout.js';
import { mergeByMaterial, cheapTransparency } from './Props.js';
import { capCanvas } from './ProcTextures.js';

/**
 * ExtraProps — batch-2 Poly Haven set dressing (layout.EXTRA_PROPS, see assets/NEW_ASSETS.md) and the "glass" pass:
 * live mirror reflection, picture-frame glass, procedural family photos, laundry-basket cloth, the old CRT in the nook.
 *
 * Public API (contract): constructor(game, world); async build(); update(dt); reset(kind); setPower(on)
 * Additions:
 *   .objects            { [EXTRA_PROPS key]: Object3D }  placed roots (e.g. objects.gnome for an "it moved" beat)
 *   .mirror             { root, reflector|null, glass, ghost, active }  (active = live reflection rendered this frame)
 *   mirrorGhost(sec=0.9) briefly shows a tall dark silhouette standing behind the player, ONLY in the mirror's live
 *                        reflection (layer GHOST_LAYER: the reflection camera renders it, the main camera does not).
 *                        Returns true when it can actually be seen now (high/ultra, mirror close + in view), else false.
 *   crtFlicker()        plays the old-CRT beat now (static for ~1.5 s then collapse); setPower(true) triggers it.
 *   GHOST_LAYER         (export) layer index used for mirror-only objects.
 * Quality: live reflection on 'high' (512 px) / 'ultra' (1024 px) only; low/medium use env-mapped silvered glass.
 */
export const GHOST_LAYER = 7;

// ---------------------------------------------------------------------------------------------------------------------
// Model-space measurements (NEW_ASSETS.md §2, checked against the GLB vertex data)
const MIRROR_GLASS = { minX: -0.219, maxX: 0.219, minY: -0.386, maxY: 0.299, archY: 0.19, z: 0.0088 };
const TV_SCREEN = { minX: -0.247, maxX: 0.115, minY: 0.124, maxY: 0.394 }; // Television_01 curved glass (inset a little)
const ART_U = [0.007, 0.993], ART_V = [0.223, 0.801];                     // hanging_picture_frame_02 artwork UV band

// Geometric corrections to layout.EXTRA_PROPS found while checking the placements in 3D (reported to the lead):
//  - broom: with the documented 0.12 rad lean toward -X the handle top went 7 cm into the nook's west wall (x = 0.2).
//    The tips now sit 3.5 cm further from the wall and the lean is solved so the handle rests ON the wall.
//  - toolbox: its south end overlapped Shelf_01's north post by 2 cm (both bounding boxes at x > 3.24): 7 cm west.
//  - gnome: its lantern hand reached into Shelf_01's south post (bbox overlap x[3.24,3.36] z[-3.24,-3.2]): 12 cm west.
const FIX = {
  gnome: { pos: [3.13, 0, -3.1] },
  broom: { pos: [0.325, 0.126, -3.72], rotZ: 0.08 },
  toolbox: { pos: [3.13, 0, -4.38] },
};
// Entries that get no collider even without noCollider: the closet interior is not walkable (only the hide interaction
// gets there) and a box there would push the hidden player (hide position 0.16 m from the case).
const NO_COLLIDER = new Set(['suitcase']);
const OCCLUDERS = new Set(['oldTv', 'suitcase']);
// Perf: wall decor, ceiling-mounted and small (< ~25-30 cm) props don't cast into the shadow maps (a cube shadow update
// draws every caster up to 6 times); large props keep casting.
const NO_CAST = new Set(['mirror', 'stairPhotoA', 'stairPhotoB', 'socket', 'gamepad', 'mousetrap', 'paintCan', 'bleach', 'jug']);
// Perf: models whose parts never move relative to each other are merged into one mesh per material (draw calls).
const MERGE_STATIC = new Set(['toolbox', 'suitcase', 'suitcaseHall', 'broom']);

// ---------------------------------------------------------------------------------------------------------------------
// Small deterministic noise / random helpers (build-time only)
function rng(seed) {
  let s = seed | 0;
  return () => {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash3(x, y, z, seed) {
  let h = (Math.imul(x, 374761393) + Math.imul(y, 668265263) + Math.imul(z, 1274126177) + Math.imul(seed, 144665)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967295;
}
function vnoise3(x, y, z, seed = 0) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  const xf = x - xi, yf = y - yi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf), w = zf * zf * (3 - 2 * zf);
  const l = (a, b, t) => a + (b - a) * t;
  return l(
    l(l(hash3(xi, yi, zi, seed), hash3(xi + 1, yi, zi, seed), u), l(hash3(xi, yi + 1, zi, seed), hash3(xi + 1, yi + 1, zi, seed), u), v),
    l(l(hash3(xi, yi, zi + 1, seed), hash3(xi + 1, yi, zi + 1, seed), u), l(hash3(xi, yi + 1, zi + 1, seed), hash3(xi + 1, yi + 1, zi + 1, seed), u), v),
    w);
}
function fbm3(x, y, z, seed = 0, oct = 4) {
  let a = 0.5, f = 1, s = 0, n = 0;
  for (let i = 0; i < oct; i++) { s += a * vnoise3(x * f, y * f, z * f, seed + i * 17); n += a; a *= 0.5; f *= 2.03; }
  return s / n;
}
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };

/** Average normals of coincident vertices (UV seams, poles) so procedural meshes shade without visible seams. */
function weldNormals(g) {
  const p = g.attributes.position, n = g.attributes.normal, map = new Map();
  for (let i = 0; i < p.count; i++) {
    const k = `${Math.round(p.getX(i) * 1e4)},${Math.round(p.getY(i) * 1e4)},${Math.round(p.getZ(i) * 1e4)}`;
    let e = map.get(k);
    if (!e) { e = [0, 0, 0, []]; map.set(k, e); }
    e[0] += n.getX(i); e[1] += n.getY(i); e[2] += n.getZ(i); e[3].push(i);
  }
  for (const e of map.values()) {
    const l = Math.hypot(e[0], e[1], e[2]) || 1;
    for (const i of e[3]) n.setXYZ(i, e[0] / l, e[1] / l, e[2] / l);
  }
  n.needsUpdate = true;
}
function setColor(g, c) {
  const n = g.attributes.position.count, a = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) { a[i * 3] = c[0]; a[i * 3 + 1] = c[1]; a[i * 3 + 2] = c[2]; }
  g.setAttribute('color', new THREE.BufferAttribute(a, 3));
  return g;
}

// ---------------------------------------------------------------------------------------------------------------------
// Procedural cloth (crumpled laundry). All pieces share one fabric032 material with vertex-colour tints (1 draw call).
const TILE = 0.3; // fabric032 real-world tile (m)

/** Crumpled pile: a lumpy flattened ellipsoid with ridged-noise wrinkles and a flat bottom. */
function clothBlob({ sx, sy, sz, seed, amp = 0.012, freq = 11, lumps = 0.22, flat = -0.45, wseg = 44, hseg = 28 }) {
  const g = new THREE.SphereGeometry(1, wseg, hseg);
  const p = g.attributes.position, uv = g.attributes.uv;
  const yFlat = flat * sy;
  for (let i = 0; i < p.count; i++) {
    let x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    const ux = x, uy = y, uz = z;
    const l = 1 + lumps * (fbm3(ux * 1.7 + 3, uy * 1.7, uz * 1.7, seed, 3) - 0.5) * 2.2;
    x *= sx * l; y *= sy * l; z *= sz * l;
    // wrinkles along the outward direction: soft noise + sharp ridged folds
    const n1 = fbm3(x * freq, y * freq, z * freq, seed + 5, 3) - 0.5;
    const r = 1 - Math.abs(2 * vnoise3(x * freq * 0.55 + 7, y * freq * 0.9, z * freq * 0.55, seed + 9) - 1);
    let d = amp * (n1 * 1.3 + Math.pow(r, 4) * 0.9 - 0.15);
    const nl = Math.hypot(ux, uy, uz) || 1;
    let nx = ux / nl, ny = uy / nl, nz = uz / nl;
    if (y < yFlat) { y = yFlat + (y - yFlat) * 0.06; d *= 0.15; ny *= 0.2; }
    p.setXYZ(i, x + nx * d, y + ny * d, z + nz * d);
    uv.setXY(i, uv.getX(i) * (2 * Math.PI * Math.max(sx, sz)) / TILE, uv.getY(i) * (Math.PI * (sy + Math.min(sx, sz))) / TILE);
  }
  g.computeVertexNormals();
  weldNormals(g);
  return g;
}

/** A garment draped over the crate's +X rim: inside part resting on the pile, over the rim, hanging outside. */
function clothDrape({ seed, rimX = 0.253, rimY = 0.254, inY = 0.236, inLen = 0.17, hang = 0.15, z0 = -0.11, z1 = 0.13 }) {
  const ws = 22, ls = 40;
  const g = new THREE.PlaneGeometry(1, 1, ws, ls);
  const p = g.attributes.position, uv = g.attributes.uv;
  const arcR = 0.016, cx = rimX - 0.006, cy = rimY;
  const segIn = inLen, segArc = Math.PI * arcR * 0.5 * 2, segOut = hang;
  const total = segIn + segArc + segOut;
  const tmp = new THREE.Vector3();
  const pathAt = (s, out) => { // s in metres along the cloth -> point (x, y) + outward normal (nx, ny)
    if (s < segIn) {
      const k = s / segIn;
      out.set(cx - segIn + s, inY + (cy + arcR - inY) * smooth(0.55, 1, k), 0);
      return 1;
    }
    if (s < segIn + segArc) {
      const a = Math.PI / 2 - ((s - segIn) / segArc) * (Math.PI / 2 + 0.05);
      out.set(cx + Math.cos(a) * arcR, cy + Math.sin(a) * arcR, 0);
      return 2;
    }
    const k = s - segIn - segArc;
    out.set(rimX + 0.009 + k * 0.03, cy - k, 0);
    return 3;
  };
  for (let i = 0; i < p.count; i++) {
    const u = uv.getX(i), v = 1 - uv.getY(i); // u across (z), v along the length
    const zz = z0 + (z1 - z0) * u;
    // irregular hem: the hanging length varies across the width
    const hemCut = 0.05 * (vnoise3(u * 3.1, 0, 0, seed) - 0.3);
    const s = v * (total - Math.max(0, hemCut));
    const part = pathAt(s, tmp);
    let x = tmp.x, y = tmp.y, z = zz;
    // folds: vertical pleats on the hanging part, lumps inside
    const fold = Math.sin(u * 17 + vnoise3(u * 4, v * 3, 1, seed) * 5) * 0.5 + (vnoise3(u * 9, v * 9, 3, seed + 3) - 0.5);
    if (part === 3) {
      const k = (s - segIn - segArc) / segOut;
      const crumple = fbm3(u * 7, v * 9, 5, seed + 7, 3) - 0.5;
      x += 0.004 + Math.abs(fold) * 0.02 * (0.25 + k) + crumple * 0.01 * k;
      z += fold * 0.012 * k;
      y += crumple * 0.012 * k;
    } else if (part === 1) {
      y += (fbm3(x * 14, 0, zz * 14, seed + 1, 3) - 0.5) * 0.026 + 0.004;
    } else {
      x += Math.abs(fold) * 0.002; y += Math.abs(fold) * 0.002;
    }
    p.setXYZ(i, x, y, z);
    uv.setXY(i, (u * (z1 - z0)) / TILE, (s) / TILE);
  }
  g.computeVertexNormals();
  return g;
}

/** A t-shirt dropped on the floor: a grid clipped to a warped T silhouette, crumpled with ridged folds, edges on the floor. */
function clothFlat({ seed, w = 0.46, d = 0.4, res = 40 }) {
  const g = new THREE.PlaneGeometry(w, d, res, res);
  g.rotateX(-Math.PI / 2);
  const p = g.attributes.position;
  const inside = (x, z) => {
    const u = x / (w / 2), v = z / (d / 2);
    const wu = u + (vnoise3(u * 1.7, v * 1.7, 0, seed) - 0.5) * 0.35, wv = v + (vnoise3(u * 1.7 + 5, v * 1.7, 0, seed) - 0.5) * 0.35;
    return (Math.abs(wu) < 0.52 && wv > -0.62 && wv < 0.92) || (wv > -0.72 && wv < -0.18 && Math.abs(wu) < 0.97 - (wv + 0.72) * 0.25);
  };
  const keep = [], idx = g.index.array;
  for (let i = 0; i < idx.length; i += 3) {
    const a = idx[i], b = idx[i + 1], c = idx[i + 2];
    const cx = (p.getX(a) + p.getX(b) + p.getX(c)) / 3, cz = (p.getZ(a) + p.getZ(b) + p.getZ(c)) / 3;
    if (inside(cx, cz)) keep.push(a, b, c);
  }
  g.setIndex(keep);
  const step = (w / res) * 1.6;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i), z = p.getZ(i);
    let edge = 0;
    for (const [dx, dz] of [[step, 0], [-step, 0], [0, step], [0, -step], [step, step], [-step, -step]]) if (!inside(x + dx, z + dz)) edge++;
    const r = 1 - Math.abs(2 * vnoise3(x * 11 + 3, z * 9, 0.5, seed + 2) - 1);
    const r2 = 1 - Math.abs(2 * vnoise3(x * 23, z * 19 + 7, 1.5, seed + 4) - 1);
    const bunch = Math.exp(-((x + 0.05) * (x + 0.05) + (z - 0.04) * (z - 0.04)) / 0.012);
    let h = 0.003 + 0.028 * Math.pow(r, 5) + 0.009 * Math.pow(r2, 4) + 0.022 * bunch * vnoise3(x * 6, z * 6, 9, seed);
    h *= edge ? 0.12 : 1;
    p.setY(i, h);
  }
  const uv = g.attributes.uv;
  for (let i = 0; i < p.count; i++) uv.setXY(i, p.getX(i) / TILE, p.getZ(i) / TILE);
  g.computeVertexNormals();
  return g;
}

/** A sock lying flat on the floor: bent tube, flattened, closed toe. */
function clothSock({ seed }) {
  const curve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-0.17, 0, 0.02), new THREE.Vector3(-0.08, 0, 0.0), new THREE.Vector3(0.0, 0, -0.01),
    new THREE.Vector3(0.045, 0, -0.04), new THREE.Vector3(0.06, 0, -0.1), new THREE.Vector3(0.052, 0, -0.15),
  ]);
  const ts = 48, rs = 14;
  const g = new THREE.TubeGeometry(curve, ts, 0.036, rs, false);
  const p = g.attributes.position, uv = g.attributes.uv;
  const c = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    const ring = Math.floor(i / (rs + 1)), t = ring / ts;
    curve.getPointAt(t, c);
    let x = p.getX(i) - c.x, y = p.getY(i) - c.y, z = p.getZ(i) - c.z;
    // closed toe + slightly gathered cuff
    let r = 1;
    if (t > 0.86) r = Math.sqrt(Math.max(0, 1 - Math.pow((t - 0.86) / 0.14, 2)));
    if (t < 0.04) r = 0.75 + 0.25 * (t / 0.04);
    const n = 1 + (fbm3(p.getX(i) * 40, p.getY(i) * 40, p.getZ(i) * 40, seed, 3) - 0.5) * 0.5;
    const rib = t < 0.22 ? 1.06 + 0.03 * Math.sin(Math.atan2(y, x) * 18) : 1; // ribbed cuff
    const foot = t > 0.55 ? 1 - (t - 0.55) * 0.35 : 1;
    x *= r * n * rib * foot; y *= r * n * 0.2; z *= r * n * rib * foot;
    p.setXYZ(i, c.x + x, c.y + y + 0.0078 * (0.4 + 0.6 * r), c.z + z);
    uv.setXY(i, (uv.getX(i) * curve.getLength()) / TILE, (uv.getY(i) * 0.2) / TILE);
  }
  g.computeVertexNormals();
  weldNormals(g);
  return g;
}

// ---------------------------------------------------------------------------------------------------------------------
// Canvas helpers: aged mirror silvering + dusty glass + faded 90s photos
function makeCanvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }

/** Mirror aging data: R = silver left (0..1), G = roughness-like haze (0.06 clean .. 0.56), B = foxing (brown spots). */
function mirrorAgeCanvases() {
  const W = 160, H = 250;
  const data = makeCanvas(W, H), col = makeCanvas(W, H);
  const dctx = data.getContext('2d'), cctx = col.getContext('2d');
  const di = dctx.createImageData(W, H), ci = cctx.createImageData(W, H);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const u = x / (W - 1), v = 1 - y / (H - 1); // v up (matches the glass uv)
      const gx = u * 0.438 - 0.219, gy = v * 0.685 - 0.386;
      // distance to the arched outline (approx): sides, bottom, arch
      let edge = Math.min(gx + 0.219, 0.219 - gx, gy + 0.386);
      if (gy > 0.19) edge = Math.min(edge, 0.2745 - Math.hypot(gx, gy - 0.0245));
      const n1 = fbm3(gx * 22, gy * 22, 0.5, 11, 4), n2 = fbm3(gx * 60, gy * 60, 2.5, 23, 3);
      // desilvering creeps in from the edges in a few places only (worse at the bottom corners), mottled front
      const corr = smooth(0.5, 0.72, fbm3(gx * 8, gy * 8, 1.7, 5, 3));
      const band = 0.002 + 0.016 * corr + smooth(-0.25, -0.386, gy) * smooth(0.12, 0.2, Math.abs(gx)) * 0.02;
      const loss = smooth(band, band * 0.25, edge + (n2 - 0.5) * 0.006);
      // rare isolated black specks in the field
      const speck = smooth(0.88, 0.92, fbm3(gx * 95, gy * 95, 7.1, 31, 2));
      const silver = clamp01(1 - loss * 0.9 - speck * 0.7);
      const fox = clamp01(smooth(0.74, 0.84, fbm3(gx * 30, gy * 30, 4.2, 41, 4)) * 0.45 + smooth(0.025, 0.0, edge) * corr * 0.35);
      // haze: soft cloud + a diagonal wipe streak + dust collected near the bottom
      const wipe = Math.exp(-Math.pow((gx * 0.8 + gy * 0.6 - 0.05 + (n1 - 0.5) * 0.08) / 0.05, 2)) * 0.35;
      const haze = clamp01(smooth(0.52, 0.78, n1) * 0.4 + wipe + smooth(-0.25, -0.386, gy) * 0.3 + loss * 0.3);
      const k = (y * W + x) * 4;
      di.data[k] = silver * 255; di.data[k + 1] = (0.06 + haze * 0.5) * 255; di.data[k + 2] = fox * 255; di.data[k + 3] = 255;
      // fallback (env-mapped metal) colour: silver tint, browned by foxing, dark where desilvered
      const s = silver * (1 - fox * 0.45);
      ci.data[k] = 255 * s * 0.9; ci.data[k + 1] = 255 * s * (0.87 - fox * 0.08); ci.data[k + 2] = 255 * s * (0.8 - fox * 0.16); ci.data[k + 3] = 255;
    }
  }
  dctx.putImageData(di, 0, 0); cctx.putImageData(ci, 0, 0);
  return { data, col };
}

/** Dust specks + finger smudges for the frame glass: R/G/B = dust colour (additive glass: only lit dust shows), A unused.
 *  A separate canvas carries roughness in G. */
function glassDustCanvases(seed) {
  const W = 256, H = 160, R = rng(seed);
  const dust = makeCanvas(W, H), rough = makeCanvas(W, H);
  const d = dust.getContext('2d'), r = rough.getContext('2d');
  d.fillStyle = '#000'; d.fillRect(0, 0, W, H);
  r.fillStyle = 'rgb(0,13,0)'; r.fillRect(0, 0, W, H);
  // haze builds up toward the bottom edge (dust settles on the lower frame rail)
  const gd = d.createLinearGradient(0, 0, 0, H);
  gd.addColorStop(0, 'rgba(40,38,34,0.12)'); gd.addColorStop(0.8, 'rgba(40,38,34,0.0)'); gd.addColorStop(1, 'rgba(60,57,50,0.35)');
  d.fillStyle = gd; d.fillRect(0, 0, W, H);
  for (let i = 0; i < 110; i++) { // specks (canvas v grows downward = glass bottom, see uv generation)
    const x = R() * W, y = R() * H, s = 0.3 + R() * 0.7, a = 0.1 + R() * 0.22;
    d.fillStyle = `rgba(120,114,104,${a})`; d.beginPath(); d.arc(x, y, s, 0, Math.PI * 2); d.fill();
  }
  // smudges (rougher + a faint greasy sheen)
  for (let i = 0; i < 5; i++) {
    const x = R() * W, y = R() * H, rad = 8 + R() * 14;
    const g = r.createRadialGradient(x, y, 0, x, y, rad);
    g.addColorStop(0, 'rgba(0,50,0,0.7)'); g.addColorStop(1, 'rgba(0,50,0,0)');
    r.fillStyle = g; r.beginPath(); r.arc(x, y, rad, 0, Math.PI * 2); r.fill();
    const g2 = d.createRadialGradient(x, y, 0, x, y, rad);
    g2.addColorStop(0, 'rgba(50,47,42,0.18)'); g2.addColorStop(1, 'rgba(50,47,42,0)');
    d.fillStyle = g2; d.beginPath(); d.arc(x, y, rad, 0, Math.PI * 2); d.fill();
  }
  return { dust, rough };
}

// --- faded 90s photo painting -------------------------------------------------------------------------------------------
const hexRgb = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const rgbStr = (c, k = 1, a = 1) => `rgba(${Math.round(Math.min(255, c[0] * k))},${Math.round(Math.min(255, c[1] * k))},${Math.round(Math.min(255, c[2] * k))},${a})`;
/** Horizontal light->shadow gradient (key light from one side) for a body part spanning x0..x1. */
function sideShade(c, x0, x1, hex, lightLeft = true, k = 0.22) {
  const base = hexRgb(hex);
  const g = c.createLinearGradient(x0, 0, x1, 0);
  g.addColorStop(0, rgbStr(base, lightLeft ? 1 + k : 1 - k));
  g.addColorStop(0.5, rgbStr(base, 1));
  g.addColorStop(1, rgbStr(base, lightLeft ? 1 - k * 1.4 : 1 + k * 0.6));
  return g;
}
function blob(c, x, y, rx, ry, fill) { c.fillStyle = fill; c.beginPath(); c.ellipse(x, y, Math.max(0.1, rx), Math.max(0.1, ry), 0, 0, Math.PI * 2); c.fill(); }
function limb(c, x0, y0, x1, y1, w, style) { c.strokeStyle = style; c.lineWidth = w; c.lineCap = 'round'; c.beginPath(); c.moveTo(x0, y0); c.lineTo(x1, y1); c.stroke(); }

/**
 * Paint a standing person (photo scale). P = { x, foot, h, headK (head height / h), sh (shoulder width / h), skin, hair,
 * hairStyle: 'short'|'perm'|'pigtails'|'long', top, bottom, dress (hem y ratio), shoes, light: 'left'|'flash', redEye,
 * armL/armR: [dx, dy] hand offsets from the shoulders, beard }
 */
function drawPerson(c, P) {
  const H = P.h, hh = H * P.headK, hw = hh * 0.76;
  const top = P.foot - H, cx = P.x, cy = top + hh * 0.52;
  const lightLeft = P.light !== 'right';
  const shY = top + hh * 1.32, sw = H * P.sh;
  const hipY = P.foot - H * 0.48, hipW = sw * (P.hipK || 0.78);
  const skin = P.skin;
  // long hair behind the body
  if (P.hairStyle === 'long') {
    c.fillStyle = sideShade(c, cx - hw * 1.2, cx + hw * 1.2, P.hair, lightLeft, 0.35);
    c.beginPath();
    c.moveTo(cx - hw * 0.62, top + hh * 0.2);
    c.bezierCurveTo(cx - hw * 1.25, top + hh * 1.4, cx - hw * 1.35, top + hh * 2.6, cx - hw * 1.05, top + hh * 3.6);
    c.lineTo(cx + hw * 1.1, top + hh * 3.5);
    c.bezierCurveTo(cx + hw * 1.35, top + hh * 2.6, cx + hw * 1.25, top + hh * 1.4, cx + hw * 0.62, top + hh * 0.2);
    c.closePath(); c.fill();
  }
  if (P.hairStyle === 'perm') {
    for (let i = 0; i < 26; i++) {
      const a = (i / 26) * Math.PI * 2, rr = hw * (0.95 + 0.25 * Math.sin(i * 2.7));
      blob(c, cx + Math.cos(a) * rr * 0.95, cy - hh * 0.05 + Math.sin(a) * rr * 0.95 + (Math.sin(a) > 0 ? hh * 0.25 : 0), hw * 0.36, hw * 0.36, rgbStr(hexRgb(P.hair), 0.85 + 0.3 * ((i * 37) % 7) / 7));
    }
  }
  // legs or dress
  const shoe = P.shoes || '#e9e6dc';
  if (P.dress) {
    const hemY = P.foot - H * P.dress;
    c.fillStyle = sideShade(c, cx - hipW * 1.3, cx + hipW * 1.3, P.top, lightLeft, 0.18);
    c.beginPath();
    c.moveTo(cx - sw * 0.42, shY); c.lineTo(cx + sw * 0.42, shY);
    c.lineTo(cx + hipW * (P.flare || 0.85), hemY); c.lineTo(cx - hipW * (P.flare || 0.85), hemY); c.closePath(); c.fill();
    // fold shadows
    c.strokeStyle = rgbStr(hexRgb(P.top), 0.82, 0.5); c.lineWidth = Math.max(1, H * 0.006);
    for (let i = -2; i <= 2; i++) { c.beginPath(); c.moveTo(cx + i * sw * 0.08, hipY - H * 0.05); c.lineTo(cx + i * hipW * 0.32, hemY); c.stroke(); }
    const legW = H * 0.035;
    c.fillStyle = sideShade(c, cx - hipW * 0.5, cx + hipW * 0.5, skin, lightLeft);
    c.fillRect(cx - hipW * 0.32 - legW / 2, hemY - 2, legW, P.foot - hemY); c.fillRect(cx + hipW * 0.32 - legW / 2, hemY - 2, legW, P.foot - hemY);
    blob(c, cx - hipW * 0.32, P.foot - H * 0.008, legW * 0.9, H * 0.014, shoe); blob(c, cx + hipW * 0.32, P.foot - H * 0.008, legW * 0.9, H * 0.014, shoe);
  } else {
    const legW = hipW * 0.47;
    c.fillStyle = sideShade(c, cx - hipW, cx + hipW, P.bottom, lightLeft, 0.2);
    c.beginPath();
    c.moveTo(cx - hipW * 0.98, hipY - H * 0.04); c.lineTo(cx + hipW * 0.98, hipY - H * 0.04);
    c.lineTo(cx + hipW * 0.9, P.foot - H * 0.02); c.lineTo(cx + hipW * 0.9 - legW, P.foot - H * 0.02);
    c.lineTo(cx, hipY + H * 0.06); c.lineTo(cx - hipW * 0.9 + legW, P.foot - H * 0.02); c.lineTo(cx - hipW * 0.9, P.foot - H * 0.02);
    c.closePath(); c.fill();
    blob(c, cx - hipW * 0.62, P.foot - H * 0.01, legW * 0.62, H * 0.016, shoe); blob(c, cx + hipW * 0.62, P.foot - H * 0.01, legW * 0.62, H * 0.016, shoe);
    // torso / shirt
    c.fillStyle = sideShade(c, cx - sw / 2, cx + sw / 2, P.top, lightLeft, 0.2);
    c.beginPath();
    c.moveTo(cx - sw * 0.38, shY - H * 0.01);
    c.quadraticCurveTo(cx - sw * 0.52, shY, cx - sw * 0.5, shY + H * 0.05);
    c.lineTo(cx - hipW * 1.0, hipY); c.lineTo(cx + hipW * 1.0, hipY); c.lineTo(cx + sw * 0.5, shY + H * 0.05);
    c.quadraticCurveTo(cx + sw * 0.52, shY, cx + sw * 0.38, shY - H * 0.01);
    c.closePath(); c.fill();
    if (P.plaid) { // flannel shirt
      c.save(); c.clip();
      c.strokeStyle = 'rgba(20,24,40,0.45)'; c.lineWidth = H * 0.012;
      for (let x = cx - sw; x < cx + sw; x += H * 0.035) { c.beginPath(); c.moveTo(x, shY - 5); c.lineTo(x, hipY + 5); c.stroke(); }
      for (let y = shY; y < hipY; y += H * 0.035) { c.beginPath(); c.moveTo(cx - sw, y); c.lineTo(cx + sw, y); c.stroke(); }
      c.restore();
    }
  }
  // arms (sleeve then forearm)
  const arm = (side, hand) => {
    const sx0 = cx + side * sw * 0.45, sy0 = shY + H * 0.02;
    const hx = sx0 + hand[0] * H, hy = sy0 + hand[1] * H;
    const ex = sx0 + (hx - sx0) * 0.5 + side * H * 0.012, ey = sy0 + (hy - sy0) * 0.5;
    const aw = H * (P.armW || 0.05);
    if (P.armShadow) { limb(c, sx0 + side * 3, sy0 + 4, ex + side * 4, ey + 4, aw * 1.5, 'rgba(40,32,24,0.45)'); limb(c, ex + side * 4, ey + 4, hx + side * 3, hy + 3, aw * 1.3, 'rgba(40,32,24,0.45)'); }
    limb(c, sx0, sy0, ex, ey, aw, P.sleeve === 'skin' ? rgbStr(hexRgb(skin), 0.97) : rgbStr(hexRgb(P.top), side < 0 === lightLeft ? 1.1 : 0.82));
    limb(c, ex, ey, hx, hy, aw * 0.8, rgbStr(hexRgb(skin), side < 0 === lightLeft ? 1.05 : 0.86));
    blob(c, hx, hy + aw * 0.2, aw * 0.5, aw * 0.62, rgbStr(hexRgb(skin), 0.95));
    if (P.fingers) { // long fingers draped forward
      c.strokeStyle = rgbStr(hexRgb(skin), 0.9); c.lineWidth = Math.max(1, aw * 0.16); c.lineCap = 'round';
      for (let f = -1.5; f <= 1.5; f++) { c.beginPath(); c.moveTo(hx + f * aw * 0.16, hy + aw * 0.4); c.quadraticCurveTo(hx + f * aw * 0.22 + side * aw * 0.1, hy + aw * 1.2, hx + f * aw * 0.18, hy + aw * 1.75); c.stroke(); }
    }
  };
  arm(-1, P.armL || [-0.03, 0.33]);
  arm(1, P.armR || [0.03, 0.33]);
  // neck + head
  c.fillStyle = rgbStr(hexRgb(skin), 0.85);
  c.fillRect(cx - hw * 0.22, cy + hh * 0.3, hw * 0.44, hh * 0.55);
  const fg = P.light === 'flash' ? c.createRadialGradient(cx, cy - hh * 0.05, hh * 0.05, cx, cy, hh * 0.62)
    : c.createRadialGradient(cx - hw * 0.25, cy - hh * 0.15, hh * 0.05, cx, cy, hh * 0.65);
  fg.addColorStop(0, rgbStr(hexRgb(skin), 1.12)); fg.addColorStop(1, rgbStr(hexRgb(skin), 0.78));
  blob(c, cx, cy, hw * 0.5, hh * 0.52, fg);
  // face
  const eyeY = cy - hh * 0.04, ex = hw * 0.2, er = Math.max(0.9, hh * 0.045);
  c.fillStyle = 'rgba(60,40,30,0.55)';
  c.fillRect(cx - ex - er * 1.6, eyeY - er * 2.6, er * 3.2, Math.max(1, er * 0.7)); c.fillRect(cx + ex - er * 1.6, eyeY - er * 2.6, er * 3.2, Math.max(1, er * 0.7));
  blob(c, cx - ex, eyeY, er * 1.25, er, 'rgba(235,228,215,0.9)'); blob(c, cx + ex, eyeY, er * 1.25, er, 'rgba(235,228,215,0.9)');
  blob(c, cx - ex, eyeY, er * 0.7, er * 0.8, P.redEye ? '#d0201a' : '#2a1d16'); blob(c, cx + ex, eyeY, er * 0.7, er * 0.8, P.redEye ? '#d0201a' : '#2a1d16');
  c.strokeStyle = rgbStr(hexRgb(skin), 0.68); c.lineWidth = Math.max(1, hh * 0.03);
  c.beginPath(); c.moveTo(cx + (lightLeft ? 1 : -1) * hw * 0.04, eyeY + hh * 0.05); c.lineTo(cx + (lightLeft ? 1 : -1) * hw * 0.07, eyeY + hh * 0.2); c.stroke();
  if (P.beard) { c.fillStyle = rgbStr(hexRgb(P.hair), 0.9); c.fillRect(cx - hw * 0.2, eyeY + hh * 0.24, hw * 0.4, hh * 0.07); }
  c.strokeStyle = 'rgba(120,45,40,0.85)'; c.lineWidth = Math.max(1, hh * 0.035);
  c.beginPath(); c.arc(cx, eyeY + hh * 0.2, hw * 0.17, Math.PI * 0.2, Math.PI * 0.8); c.stroke();
  // hair on top / front
  const hc = sideShade(c, cx - hw, cx + hw, P.hair, lightLeft, 0.3);
  if (P.hairStyle === 'short') {
    c.fillStyle = hc; c.beginPath(); c.ellipse(cx, cy - hh * 0.2, hw * 0.55, hh * 0.38, 0, Math.PI, Math.PI * 2); c.fill();
    c.fillRect(cx - hw * 0.55, cy - hh * 0.22, hw * 0.12, hh * 0.3); c.fillRect(cx + hw * 0.43, cy - hh * 0.22, hw * 0.12, hh * 0.3);
  } else if (P.hairStyle === 'perm') {
    c.fillStyle = hc; c.beginPath(); c.ellipse(cx, cy - hh * 0.26, hw * 0.58, hh * 0.3, 0, Math.PI, Math.PI * 2); c.fill();
    for (let i = 0; i < 7; i++) blob(c, cx - hw * 0.45 + i * hw * 0.15, cy - hh * 0.3, hw * 0.12, hh * 0.1, hc);
  } else if (P.hairStyle === 'pigtails') {
    c.fillStyle = hc; c.beginPath(); c.ellipse(cx, cy - hh * 0.15, hw * 0.55, hh * 0.42, 0, Math.PI, Math.PI * 2); c.fill();
    c.fillRect(cx - hw * 0.5, cy - hh * 0.2, hw, hh * 0.13); // bangs
    blob(c, cx - hw * 0.68, cy + hh * 0.05, hw * 0.2, hh * 0.32, hc); blob(c, cx + hw * 0.68, cy + hh * 0.05, hw * 0.2, hh * 0.32, hc);
    blob(c, cx - hw * 0.6, cy - hh * 0.2, hw * 0.08, hh * 0.06, '#d8506a'); blob(c, cx + hw * 0.6, cy - hh * 0.2, hw * 0.08, hh * 0.06, '#d8506a');
  } else if (P.hairStyle === 'long') {
    c.fillStyle = hc; c.beginPath(); c.ellipse(cx, cy - hh * 0.12, hw * 0.6, hh * 0.47, 0, Math.PI, Math.PI * 2); c.fill();
    // curtains of hair over both sides of the face, down over the chest
    c.beginPath();
    c.moveTo(cx - hw * 0.6, cy - hh * 0.14); c.quadraticCurveTo(cx - hw * 0.2, cy, cx - hw * 0.32, cy + hh * 0.6);
    c.lineTo(cx - hw * 0.45, top + hh * 3.1); c.lineTo(cx - hw * 0.9, top + hh * 3.0); c.closePath(); c.fill();
    c.beginPath();
    c.moveTo(cx + hw * 0.6, cy - hh * 0.14); c.quadraticCurveTo(cx + hw * 0.22, cy, cx + hw * 0.3, cy + hh * 0.6);
    c.lineTo(cx + hw * 0.42, top + hh * 3.2); c.lineTo(cx + hw * 0.9, top + hh * 3.1); c.closePath(); c.fill();
    c.strokeStyle = 'rgba(70,64,60,0.35)'; c.lineWidth = 1;
    for (let i = 0; i < 18; i++) { const sx = cx + (i / 17 - 0.5) * hw * 2; c.beginPath(); c.moveTo(sx, top + hh * 0.3); c.quadraticCurveTo(sx + (i % 3 - 1) * 3, top + hh * 1.8, sx + (i % 2 ? 2 : -2), top + hh * 3.0); c.stroke(); }
  }
  return { cx, cy, hh, hw, top };
}

/** Soft focus: downscale + upscale (works everywhere, unlike ctx.filter on older iOS). */
function soften(canvas, k = 0.5) {
  const t = makeCanvas(Math.max(1, Math.round(canvas.width * k)), Math.max(1, Math.round(canvas.height * k)));
  const tc = t.getContext('2d'); tc.imageSmoothingQuality = 'high'; tc.drawImage(canvas, 0, 0, t.width, t.height);
  const c = canvas.getContext('2d'); c.imageSmoothingQuality = 'high'; c.clearRect(0, 0, canvas.width, canvas.height); c.drawImage(t, 0, 0, canvas.width, canvas.height);
}

/** 90s print aging: faded dyes (cyan loss -> warm/magenta), lifted blacks, vignetting, grain, light leak. */
function agePhoto(canvas, seed, { fade = 0.8, lift = 30, warm = [14, 0, -16], desat = 0.25, vign = 0.4, leak = 0.4 } = {}) {
  const c = canvas.getContext('2d'), W = canvas.width, H = canvas.height, R = rng(seed);
  const img = c.getImageData(0, 0, W, H), d = img.data;
  const lx = R() > 0.5 ? 1 : 0;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const k = (y * W + x) * 4;
      let r = d[k], g = d[k + 1], b = d[k + 2];
      const l = r * 0.3 + g * 0.59 + b * 0.11;
      r += (l - r) * desat; g += (l - g) * desat; b += (l - b) * desat;
      r = r * fade + lift + warm[0]; g = g * fade + lift + warm[1]; b = b * fade + lift + warm[2];
      const dx = x / W - 0.5, dy = y / H - 0.5, rr = dx * dx * 1.2 + dy * dy * 1.6;
      const v = 1 - vign * rr * 1.6;
      const lk = leak * Math.exp(-Math.pow((lx ? 1 - x / W : x / W) / 0.09, 2)) * (0.6 + 0.4 * Math.sin(y / H * 3 + seed));
      const gr = (R() - 0.5) * 16;
      d[k] = r * v + gr + lk * 120; d[k + 1] = g * v + gr + lk * 55; d[k + 2] = b * v + gr + lk * 10;
    }
  }
  c.putImageData(img, 0, 0);
  // dust specks and hairs on the print
  for (let i = 0; i < 90; i++) {
    const x = R() * W, y = R() * H;
    c.fillStyle = R() > 0.5 ? 'rgba(250,245,235,0.6)' : 'rgba(30,25,20,0.45)';
    c.fillRect(x, y, 1 + R() * 1.5, 1 + R() * 1.5);
  }
  c.strokeStyle = 'rgba(245,240,230,0.35)'; c.lineWidth = 0.8;
  for (let i = 0; i < 6; i++) { const x = R() * W, y = R() * H; c.beginPath(); c.moveTo(x, y); c.quadraticCurveTo(x + R() * 30 - 15, y + R() * 30 - 15, x + R() * 40 - 20, y + R() * 40 - 20); c.stroke(); }
}

/** Orange date imprint of a 90s point-and-shoot. */
function dateStamp(c, text, x, y, size) {
  c.save();
  c.font = `bold ${size}px "Courier New", Courier, monospace`;
  c.textAlign = 'right'; c.textBaseline = 'alphabetic';
  c.shadowColor = 'rgba(255,120,20,0.9)'; c.shadowBlur = size * 0.35;
  c.fillStyle = 'rgba(255,150,50,0.92)';
  c.fillText(text, x, y);
  c.shadowBlur = 0; c.fillStyle = 'rgba(255,205,120,0.55)'; c.fillText(text, x, y);
  c.restore();
}

/** Mat (passe-partout) around the photo + yellowing + foxing; photo window = [px, py, pw, ph]. */
function drawMat(c, W, H, win, seed) {
  const R = rng(seed);
  c.save();
  c.beginPath(); c.rect(0, 0, W, H); c.rect(win[0], win[1], win[2], win[3]); c.fill('evenodd');
  c.restore();
  const [px, py, pw, ph] = win;
  c.save();
  c.beginPath(); c.rect(0, 0, W, H); c.rect(px, py, pw, ph); c.clip('evenodd');
  const g = c.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, '#ddd2b8'); g.addColorStop(0.5, '#e4dac3'); g.addColorStop(1, '#d6c9ac');
  c.fillStyle = g; c.fillRect(0, 0, W, H);
  for (let i = 0; i < 1800; i++) { c.fillStyle = `rgba(${R() > 0.5 ? '255,250,240' : '120,100,70'},${0.05 + R() * 0.06})`; c.fillRect(R() * W, R() * H, 2, 2); }
  for (let i = 0; i < 26; i++) { const x = R() * W, y = R() * H, r = 1 + R() * 4; blob(c, x, y, r, r * (0.7 + R() * 0.5), `rgba(150,105,60,${0.12 + R() * 0.2})`); }
  // bevelled window edge: lit bottom/right, shaded top/left (light from above)
  c.lineWidth = 6;
  c.strokeStyle = '#f4ecd9'; c.beginPath(); c.moveTo(px - 3, py + ph + 3); c.lineTo(px + pw + 3, py + ph + 3); c.lineTo(px + pw + 3, py - 3); c.stroke();
  c.strokeStyle = '#b9ac90'; c.beginPath(); c.moveTo(px - 3, py + ph + 3); c.lineTo(px - 3, py - 3); c.lineTo(px + pw + 3, py - 3); c.stroke();
  c.restore();
  // the mat casts a thin shadow onto the photo at the top
  const sg = c.createLinearGradient(0, py, 0, py + 10);
  sg.addColorStop(0, 'rgba(0,0,0,0.35)'); sg.addColorStop(1, 'rgba(0,0,0,0)');
  c.fillStyle = sg; c.fillRect(px, py, pw, 10);
}

/** Photo A: family of three (dad, mom, little girl) in front of their house, summer 1993. */
function paintFamilyPhoto() {
  const W = 1024, H = 600, win = [137, 46, 750, 500];
  const canvas = makeCanvas(W, H), cx = canvas.getContext('2d');
  const ph = makeCanvas(win[2], win[3]), c = ph.getContext('2d');
  const PW = win[2], PH = win[3], R = rng(1993);
  // sky
  let g = c.createLinearGradient(0, 0, 0, 230);
  g.addColorStop(0, '#8eaac2'); g.addColorStop(1, '#dfe3dc');
  c.fillStyle = g; c.fillRect(0, 0, PW, 260);
  for (let i = 0; i < 14; i++) blob(c, R() * PW, 20 + R() * 90, 40 + R() * 60, 12 + R() * 14, 'rgba(245,245,240,0.35)');
  // trees behind
  const tree = (x0, x1, y0, y1, n) => {
    for (let i = 0; i < n; i++) blob(c, x0 + R() * (x1 - x0), y0 + R() * (y1 - y0), 22 + R() * 30, 20 + R() * 26, rgbStr(hexRgb('#3b4a2c'), 0.7 + R() * 0.5));
    for (let i = 0; i < n * 40; i++) { const x = x0 + R() * (x1 - x0), y = y0 - 10 + R() * (y1 - y0 + 10); blob(c, x, y, 2 + R() * 4, 2 + R() * 3, rgbStr(hexRgb('#46583a'), 0.45 + R() * 0.9, 0.55)); }
  };
  tree(-20, 130, 60, 260, 40); tree(600, 770, 40, 270, 46);
  // lawn
  g = c.createLinearGradient(0, 380, 0, PH);
  g.addColorStop(0, '#7a8846'); g.addColorStop(1, '#5e6c34');
  c.fillStyle = g; c.fillRect(0, 380, PW, PH - 380);
  for (let i = 0; i < 2600; i++) { const x = R() * PW, y = 385 + R() * (PH - 385); c.fillStyle = rgbStr(hexRgb('#6f7d3c'), 0.75 + R() * 0.55, 0.6); c.fillRect(x, y, 1.2, 2 + R() * 3); }
  // house body (vinyl siding)
  const hx0 = 70, hx1 = 600, hy0 = 150, hy1 = 392;
  c.fillStyle = sideShade(c, hx0, hx1, '#b8c0c2', true, 0.08); c.fillRect(hx0, hy0, hx1 - hx0, hy1 - hy0);
  c.strokeStyle = 'rgba(80,90,95,0.35)'; c.lineWidth = 1;
  for (let y = hy0 + 6; y < hy1; y += 8) { c.beginPath(); c.moveTo(hx0, y); c.lineTo(hx1, y); c.stroke(); }
  // roof
  c.fillStyle = '#4a4440';
  c.beginPath(); c.moveTo(hx0 - 30, hy0 + 6); c.lineTo(335, 42); c.lineTo(hx1 + 30, hy0 + 6); c.closePath(); c.fill();
  c.strokeStyle = 'rgba(25,22,20,0.5)';
  for (let y = 52; y < hy0 + 6; y += 9) { const t = (y - 42) / (hy0 + 6 - 42); c.beginPath(); c.moveTo(335 - t * 335 + 40, y); c.lineTo(335 + t * 295 - 10, y); c.stroke(); }
  c.fillStyle = 'rgba(0,0,0,0.3)'; c.fillRect(hx0, hy0 + 6, hx1 - hx0, 10); // eave shadow
  c.fillStyle = '#e8e6df'; c.beginPath(); c.moveTo(hx0 - 30, hy0 + 6); c.lineTo(335, 42); c.lineTo(hx1 + 30, hy0 + 6); c.lineTo(hx1 + 26, hy0 + 10); c.lineTo(335, 48); c.lineTo(hx0 - 26, hy0 + 10); c.closePath(); c.fill();
  // windows
  const win1 = (x, y, w, h) => {
    c.fillStyle = '#ecebe4'; c.fillRect(x - 7, y - 7, w + 14, h + 14);
    g = c.createLinearGradient(x, y, x + w, y + h); g.addColorStop(0, '#5d6d78'); g.addColorStop(0.6, '#2c343a'); g.addColorStop(1, '#3e4a50');
    c.fillStyle = g; c.fillRect(x, y, w, h);
    c.fillStyle = 'rgba(214,200,170,0.75)'; c.fillRect(x, y, w * 0.18, h); c.fillRect(x + w * 0.82, y, w * 0.18, h); // curtains
    c.fillStyle = '#ecebe4'; c.fillRect(x + w / 2 - 2, y, 4, h); c.fillRect(x, y + h / 2 - 2, w, 4);
    c.fillStyle = 'rgba(255,255,255,0.18)'; c.beginPath(); c.moveTo(x, y); c.lineTo(x + w * 0.4, y); c.lineTo(x, y + h * 0.6); c.fill();
  };
  win1(110, 220, 165, 108); win1(478, 222, 92, 86);
  // door + steps
  c.fillStyle = '#ecebe4'; c.fillRect(352, 222, 86, 172);
  c.fillStyle = sideShade(c, 360, 430, '#7a2e26', true, 0.12); c.fillRect(360, 230, 70, 164);
  c.fillStyle = 'rgba(0,0,0,0.25)'; for (let i = 0; i < 4; i++) c.fillRect(368 + (i % 2) * 30, 245 + Math.floor(i / 2) * 64, 24, 52);
  blob(c, 421, 315, 3, 3, '#c9a65a');
  c.fillStyle = '#a9a398'; c.fillRect(340, 392, 110, 10); c.fillStyle = '#958f84'; c.fillRect(330, 402, 130, 10);
  c.fillStyle = '#8c8578'; c.fillRect(hx0, hy1 - 6, hx1 - hx0, 12); // foundation
  // bushes
  for (let i = 0; i < 30; i++) { const x = hx0 + R() * (hx1 - hx0); if (x > 330 && x < 460) continue; blob(c, x, 372 + R() * 18, 16 + R() * 16, 14 + R() * 10, rgbStr(hexRgb('#34442a'), 0.7 + R() * 0.5)); }
  // walkway (perspective)
  c.fillStyle = '#b0a99b'; c.beginPath(); c.moveTo(352, 412); c.lineTo(438, 412); c.lineTo(560, PH); c.lineTo(250, PH); c.closePath(); c.fill();
  c.strokeStyle = 'rgba(90,85,75,0.5)'; c.lineWidth = 1.5;
  for (const y of [440, 475]) { c.beginPath(); c.moveTo(352 - (y - 412) * 0.6, y); c.lineTo(438 + (y - 412) * 0.7, y); c.stroke(); }
  // soft shadows of the family on the lawn (sun behind the photographer, from the left)
  for (const [x, w] of [[408, 50], [480, 60], [450, 36]]) blob(c, x + 28, 478, w, 9, 'rgba(20,25,10,0.35)');
  // the family
  drawPerson(c, { x: 400, foot: 470, h: 268, headK: 0.135, sh: 0.25, skin: '#d9a888', hair: '#5a3622', hairStyle: 'perm', top: '#79b1ab', bottom: '#8d9fbb', shoes: '#e9e6dc', armR: [0.07, 0.3], light: 'left' });
  drawPerson(c, { x: 480, foot: 472, h: 300, headK: 0.13, sh: 0.27, skin: '#cf9a7a', hair: '#4a2e1c', hairStyle: 'short', top: '#8e3a30', plaid: true, bottom: '#465472', shoes: '#ece9e0', beard: true, armL: [-0.06, 0.3], light: 'left' });
  drawPerson(c, { x: 441, foot: 484, h: 158, headK: 0.19, sh: 0.27, hipK: 0.7, skin: '#e2b498', hair: '#94673a', hairStyle: 'pigtails', top: '#dc7f9c', dress: 0.3, flare: 1.05, shoes: '#f0ece4', armL: [-0.03, 0.3], armR: [0.05, 0.28], armW: 0.055, light: 'left' });
  soften(ph, 0.45);
  agePhoto(ph, 93, { fade: 0.8, lift: 26, warm: [16, 2, -14], desat: 0.22, vign: 0.42, leak: 0.35 });
  dateStamp(c, "'93  7 18", PW - 30, PH - 26, 25);
  // compose: mat + photo
  cx.fillStyle = '#ddd2b8'; cx.fillRect(0, 0, W, H);
  cx.drawImage(ph, win[0], win[1]);
  drawMat(cx, W, H, win, 7);
  return canvas;
}

/** Photo B: the little girl with her babysitter — a very tall thin woman with long black hair standing behind her,
 *  hands on the child's shoulders. Flash photo, indoors. Someone scratched the woman's face out with a key. */
function paintGardiennePhoto() {
  const W = 1024, H = 600, win = [137, 46, 750, 500];
  const canvas = makeCanvas(W, H), cx = canvas.getContext('2d');
  const ph = makeCanvas(win[2], win[3]), c = ph.getContext('2d');
  const PW = win[2], PH = win[3], R = rng(1996);
  // wall lit by the on-camera flash (hot centre, dark falloff), wall corner on the left
  let g = c.createRadialGradient(420, 230, 40, 420, 230, 520);
  g.addColorStop(0, '#c9b896'); g.addColorStop(0.6, '#8f7f62'); g.addColorStop(1, '#3d3426');
  c.fillStyle = g; c.fillRect(0, 0, PW, PH);
  c.fillStyle = 'rgba(0,0,0,0.25)'; c.fillRect(0, 0, 118, 430);
  c.fillStyle = 'rgba(0,0,0,0.25)'; c.fillRect(116, 0, 4, 430);
  // little framed picture + lamp on the left
  c.fillStyle = '#3a2a1c'; c.fillRect(150, 70, 74, 92); c.fillStyle = '#7d8c8a'; c.fillRect(158, 78, 58, 76);
  c.fillStyle = '#5c4a35'; c.fillRect(30, 300, 70, 130);
  c.fillStyle = '#e5d8b4'; c.beginPath(); c.moveTo(38, 230); c.lineTo(92, 230); c.lineTo(104, 300); c.lineTo(26, 300); c.closePath(); c.fill();
  // carpet
  g = c.createLinearGradient(0, 425, 0, PH); g.addColorStop(0, '#8a7a5e'); g.addColorStop(1, '#5a4c36');
  c.fillStyle = g; c.fillRect(0, 425, PW, PH - 425);
  c.fillStyle = '#d8d0bc'; c.fillRect(0, 418, PW, 10); // baseboard
  // hard flash shadow of the two figures on the wall (offset right/down)
  c.save(); c.translate(24, 10); c.filter = 'none';
  c.fillStyle = 'rgba(25,18,10,0.45)';
  c.beginPath(); c.ellipse(422, 74, 34, 44, 0, 0, Math.PI * 2); c.fill();
  c.fillRect(372, 110, 104, 330);
  c.beginPath(); c.ellipse(440, 352, 30, 32, 0, 0, Math.PI * 2); c.fill();
  c.restore();
  // the woman (behind): 8.5 heads tall, very thin, gown, long black hair, arms reaching down to the girl's shoulders
  const woman = drawPerson(c, { x: 420, foot: 560, h: 520, headK: 0.118, sh: 0.17, hipK: 0.7, skin: '#cbc2b6', hair: '#121010', hairStyle: 'long',
    top: '#aaa293', dress: 0.06, flare: 0.95, sleeve: 'skin', armL: [0.067, 0.462], armR: [0.0, 0.462], armW: 0.03, armShadow: true, light: 'flash' });
  // the girl (front)
  drawPerson(c, { x: 438, foot: 520, h: 215, headK: 0.185, sh: 0.27, hipK: 0.72, skin: '#e8baa0', hair: '#94673a', hairStyle: 'pigtails',
    top: '#e3c24e', bottom: '#5a6fa0', shoes: '#efe9df', armL: [0.05, 0.27], armR: [-0.05, 0.27], armW: 0.058, redEye: true, light: 'flash' });
  // teddy bear held against her
  blob(c, 438, 432, 24, 26, '#7a5534'); blob(c, 438, 400, 16, 15, '#86603c'); blob(c, 427, 388, 5, 5, '#6b4a2c'); blob(c, 449, 388, 5, 5, '#6b4a2c');
  // her hands rest on the child's shoulders: long pale fingers draped over them (drawn on top of the girl)
  for (const [hx, side] of [[414, -1], [462, 1]]) {
    blob(c, hx, 366, 8, 6, 'rgba(203,194,182,0.97)');
    c.strokeStyle = 'rgba(200,191,179,0.97)'; c.lineCap = 'round'; c.lineWidth = 2.6;
    for (let f = 0; f < 4; f++) {
      const fx0 = hx - side * 6 + side * f * 3.5;
      c.beginPath(); c.moveTo(fx0, 366); c.quadraticCurveTo(fx0 - side * 4, 378 + f, fx0 - side * (2 + f), 393 + f * 2.5); c.stroke();
    }
    c.strokeStyle = 'rgba(120,105,95,0.4)'; c.lineWidth = 0.8;
    for (let f = 0; f < 4; f++) { const fx0 = hx - side * 6 + side * f * 3.5; c.beginPath(); c.moveTo(fx0 - side * 1.2, 368); c.lineTo(fx0 - side * (3 + f), 392 + f * 2.5); c.stroke(); }
  }
  soften(ph, 0.6);
  agePhoto(ph, 96, { fade: 0.76, lift: 34, warm: [22, 0, -12], desat: 0.3, vign: 0.5, leak: 0.18 });
  dateStamp(c, "'96 11  2", PW - 30, PH - 26, 25);
  // the face scratched out with a key: gouges through the emulsion show the white paper base
  const fx = woman.cx, fy = woman.cy;
  c.save();
  c.lineCap = 'round'; c.lineJoin = 'round';
  for (let i = 0; i < 80; i++) {
    const a = R() * Math.PI * 2, len = 10 + R() * 30;
    let x = fx + (R() - 0.5) * 40, y = fy + 4 + (R() - 0.5) * 44;
    const w = 1 + R() * 3.4;
    c.strokeStyle = `rgba(${236 + R() * 14},${230 + R() * 14},${216 + R() * 14},${0.65 + R() * 0.35})`; c.lineWidth = w;
    c.beginPath(); c.moveTo(x, y);
    const steps = 4 + Math.floor(R() * 5);
    for (let s = 0; s < steps; s++) { x += Math.cos(a + (R() - 0.5) * 0.9) * len / steps; y += Math.sin(a + (R() - 0.5) * 0.9) * len / steps; c.lineTo(x, y); }
    c.stroke();
    if (w > 2.4) { c.strokeStyle = 'rgba(70,50,35,0.35)'; c.lineWidth = 0.8; c.stroke(); }
  }
  // the key slipped: a few long gouges into the hair / shoulders
  for (let i = 0; i < 4; i++) {
    c.strokeStyle = 'rgba(238,232,220,0.75)'; c.lineWidth = 0.8 + R() * 1.4;
    c.beginPath(); c.moveTo(fx + (R() - 0.5) * 20, fy + 10 + (R() - 0.5) * 20);
    c.lineTo(fx + (R() - 0.5) * 160, fy + 60 + R() * 120); c.stroke();
  }
  c.restore();
  cx.fillStyle = '#ddd2b8'; cx.fillRect(0, 0, W, H);
  cx.drawImage(ph, win[0], win[1]);
  drawMat(cx, W, H, win, 11);
  return canvas;
}

// ---------------------------------------------------------------------------------------------------------------------
// Mirror shader: aged silvering on top of a live planar reflection (used through three's Reflector)
const MIRROR_SHADER = {
  name: 'AgedMirrorShader',
  uniforms: {
    color: { value: null },
    tDiffuse: { value: null },
    textureMatrix: { value: null },
    tAge: { value: null },
    texel: { value: new THREE.Vector2(1 / 328, 1 / 512) },
  },
  vertexShader: /* glsl */`
    uniform mat4 textureMatrix;
    varying vec4 vUvP;
    varying vec2 vUv;
    #include <common>
    #include <logdepthbuf_pars_vertex>
    void main() {
      vUv = uv;
      vUvP = textureMatrix * vec4( position, 1.0 );
      gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
      #include <logdepthbuf_vertex>
    }`,
  fragmentShader: /* glsl */`
    uniform vec3 color;
    uniform sampler2D tDiffuse;
    uniform sampler2D tAge;
    uniform vec2 texel;
    varying vec4 vUvP;
    varying vec2 vUv;
    #include <logdepthbuf_pars_fragment>
    void main() {
      #include <logdepthbuf_fragment>
      vec4 age = texture2D( tAge, vUv );
      float silver = age.r;
      float haze = clamp( ( age.g - 0.06 ) * 2.0, 0.0, 1.0 );
      float fox = age.b;
      vec2 uv = vUvP.xy / vUvP.w;
      vec3 c = texture2D( tDiffuse, uv ).rgb;
      vec2 o = texel * ( 1.2 + 3.5 * haze );
      vec3 b = ( texture2D( tDiffuse, uv + o ).rgb + texture2D( tDiffuse, uv - o ).rgb
               + texture2D( tDiffuse, uv + vec2( o.x, -o.y ) ).rgb + texture2D( tDiffuse, uv + vec2( -o.x, o.y ) ).rgb ) * 0.25;
      c = mix( c, b, 0.2 + 0.65 * haze );                  // old glass + dust: slightly soft
      c *= color;                                          // tarnished silver reflectance (warm, ~75 %)
      c = mix( c, c * vec3( 0.6, 0.47, 0.34 ), fox );      // foxing
      c = c * silver + vec3( 0.006, 0.005, 0.004 ) * ( 1.0 - silver ); // desilvered: the dark backing paint shows
      c += b * color * haze * 0.07;                        // dust on the front glass scatters a little light
      gl_FragColor = vec4( c, 1.0 );
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
};

// ---------------------------------------------------------------------------------------------------------------------
export class ExtraProps {
  constructor(game, world) {
    this.game = game;
    this.world = world;
    this.objects = {};
    this.mirror = null;
    this.crt = null;
    this.chain = null;
    this._frame = 0;
    this._reflFrame = -1;
    this._quality = 'medium';
    this._power = true;
    this._t = 0;
    this._v = { a: new THREE.Vector3(), b: new THREE.Vector3(), c: new THREE.Vector3() };
  }

  async build() {
    const { scene } = this.game;
    this._power = this.world.power !== false;
    this._quality = this.game.renderer?.quality || 'medium';
    for (const [key, p] of Object.entries(L.EXTRA_PROPS)) {
      try { this._place(key, p); } catch (e) { console.warn('[extras] could not place', key, e); }
    }
    const step = (name, fn) => { try { fn(); } catch (e) { console.warn(`[extras] ${name} failed`, e); } };
    step('metals', () => this._upgradeMaterials());
    step('laundry', () => this._buildLaundry());
    step('frames', () => this._buildFrames());
    step('mirror', () => this._buildMirror());
    step('crt', () => this._buildCRT());
    step('socket', () => this._buildSocket());
    step('perf', () => this._perfPass());
    this.game.events?.on?.('quality:changed', ({ quality }) => this._applyQuality(quality));
    this.game.events?.on?.('power', ({ on }) => this.setPower(on));
    this._applyQuality(this._quality);
    this._built = true; // from now on _applyQuality never adds / removes lights (shader programs depend on the light count)
    scene.updateMatrixWorld(true);
  }

  /** Draw-call / shadow-pass reductions (no visual change). */
  _perfPass() {
    for (const o of Object.values(this.objects)) cheapTransparency(o);
    for (const k of MERGE_STATIC) mergeByMaterial(this.objects[k]);
    // the hallway suitcase is only visible through the upstairs door: let it follow the hallway group, which the
    // architecture hides while the door is shut (the hall is otherwise drawn whenever it is inside the view frustum)
    const hall = this.world.architecture?.hall, sh = this.objects.suitcaseHall;
    if (hall && sh) hall.attach(sh);
  }

  // ------------------------------------------------------------------------------------------------ placement
  _place(key, p) {
    const { assets, scene } = this.game;
    const fix = FIX[key] || {};
    const o = assets.instance(p.model);
    o.name = 'extra_' + key;
    const removeNode = (n) => { if (n && n !== o) n.parent?.remove(n); };
    for (const n of p.hideNodes || []) removeNode(o.getObjectByName(n));
    if (p.hidePrefix) {
      const rm = [];
      o.traverse((c) => { if (c !== o && c.name.startsWith(p.hidePrefix)) rm.push(c); });
      rm.forEach(removeNode);
    }
    if (p.keepNodes) {
      const keep = new Set(p.keepNodes);
      const holdsKept = (n) => { let k = false; n.traverse((c) => { if (keep.has(c.name)) k = true; }); return k; };
      [...o.children].forEach((ch) => { if (!holdsKept(ch)) removeNode(ch); });
    }
    if (p.zeroNodeX) { const n = o.getObjectByName(p.zeroNodeX); if (n) n.position.x = 0; }
    o.position.fromArray(fix.pos || p.pos);
    // rotY = yaw, then rotX / rotZ tilt about the WORLD axes (Euler 'ZXY' = Rz·Rx·Ry), as documented in NEW_ASSETS §3
    o.rotation.set(fix.rotX ?? p.rotX ?? 0, fix.rotY ?? p.rotY ?? 0, fix.rotZ ?? p.rotZ ?? 0, 'ZXY');
    o.scale.setScalar(p.scale || 1);
    const cast = !NO_CAST.has(key);
    o.traverse((m) => { if (m.isMesh) { m.castShadow = cast; m.receiveShadow = true; } });
    if (key === 'toolbox') { const lid = o.getObjectByName('metal_toolbox_lid'); if (lid) lid.quaternion.identity(); } // authored open
    scene.add(o);
    o.updateMatrixWorld(true);
    if (!p.noCollider && !NO_COLLIDER.has(key)) this.world.addColliderFromObject(o, 'prop');
    if (OCCLUDERS.has(key)) this.world.addOccluder(o);
    this.objects[key] = o;
    return o;
  }

  /** Per-instance material tweaks: alpha-tested straw, metals that read as metal, glossy ceramic. */
  _upgradeMaterials() {
    // one clone per original material of the instance (not per mesh): meshes that shared a material still share it,
    // so they keep sharing GPU state and can be merged into one draw call (_perfPass)
    const each = (key, fn) => {
      const clones = new Map();
      this.objects[key]?.traverse((m) => {
        if (!m.isMesh) return;
        let c = clones.get(m.material);
        if (!c) { c = m.material.clone(); clones.set(m.material, c); fn(c, m); }
        m.material = c;
      });
    };
    each('broom', (mat) => {
      if (mat.name === 'wooden_broom_bristles' || mat.transparent) {
        mat.transparent = false; mat.alphaTest = 0.42; mat.alphaToCoverage = true; mat.depthWrite = true; mat.side = THREE.DoubleSide;
      }
    });
    each('toolbox', (mat) => { mat.envMapIntensity = 1.6; mat.roughness = 0.85; });
    each('paintCan', (mat) => { mat.envMapIntensity = 1.5; });
    each('gnome', (mat) => { mat.envMapIntensity = 1.3; });
    each('socket', (mat) => { mat.envMapIntensity = 1.4; });
    each('mirror', (mat) => { mat.envMapIntensity = 1.35; }); // gilded frame
  }

  // ------------------------------------------------------------------------------------------------ laundry basket
  _buildLaundry() {
    const crate = this.objects.laundry;
    if (!crate) return;
    crate.traverse((m) => {
      if (!m.isMesh) return;
      m.material = m.material.clone();
      Object.assign(m.material, { transparent: false, alphaTest: 0.5, alphaToCoverage: true, depthWrite: true, side: THREE.DoubleSide });
      m.material.needsUpdate = true;
    });
    const T = (g, x, y, z, ry = 0) => { g.rotateY(ry); g.translate(x, y, z); return g; };
    // inside (crate-local: inner walls at |x| < 0.24, |z| < 0.19, floor y 0.008, rim 0.254)
    const inside = [
      setColor(T(clothBlob({ sx: 0.19, sy: 0.11, sz: 0.14, seed: 3, amp: 0.022, freq: 9, lumps: 0.2, flat: -0.82 }), -0.012, 0.115, 0.0, 0.3), [0.86, 0.85, 0.82]), // towels / sheet
      setColor(T(clothBlob({ sx: 0.125, sy: 0.036, sz: 0.1, seed: 8, amp: 0.016, freq: 12, lumps: 0.32, flat: -0.6 }), -0.075, 0.222, 0.035, 1.1), [0.3, 0.38, 0.52]),   // blue shirt
      setColor(T(clothBlob({ sx: 0.09, sy: 0.022, sz: 0.07, seed: 13, amp: 0.012, freq: 14, lumps: 0.35, flat: -0.6 }), 0.07, 0.226, -0.085, -0.4), [0.62, 0.6, 0.55]), // beige top
      setColor(clothDrape({ seed: 21 }), [0.78, 0.4, 0.46]), // pink child's shirt over the rim
    ];
    const fabric = this.game.assets.pbr('fabric032', [1, 1], { vertexColors: true, side: THREE.DoubleSide, roughness: 1 });
    fabric.normalScale.set(0.8, 0.8);
    fabric.name = 'extras_laundry';
    const mesh = new THREE.Mesh(mergeGeometries(inside, false), fabric);
    mesh.name = 'extra_laundry_cloth';
    mesh.castShadow = true; mesh.receiveShadow = true;
    crate.add(mesh);
    // spilled on the floor (world space): a faded red t-shirt and a dark sock
    const floor = [
      setColor(T(clothFlat({ seed: 31 }), 1.19, 0, -3.3, 0.6), [0.5, 0.14, 0.14]),
      setColor(T(clothSock({ seed: 41 }), 0.98, 0, -3.72, 2.2), [0.085, 0.085, 0.095]),
    ];
    for (const g of floor) { g.computeBoundingBox(); g.translate(0, 0.0015 - g.boundingBox.min.y, 0); }
    const fm = new THREE.Mesh(mergeGeometries(floor, false), fabric);
    fm.name = 'extra_laundry_floor';
    fm.castShadow = false; fm.receiveShadow = true; // flat cloth on the floor (≤ 3 cm): no shadow passes
    this.game.scene.add(fm);
    this.objects.laundryFloor = fm;
  }

  // ------------------------------------------------------------------------------------------------ stairwell photos
  _buildFrames() {
    const maxAniso = this.game.renderer?.maxAnisotropy ?? 4;
    const painters = { stairPhotoA: paintFamilyPhoto, stairPhotoB: paintGardiennePhoto };
    const dustTex = {};
    // GPU memory: the 1024 px photo canvases are resampled to 512 px on low/medium (same cap as ProcTextures/Assets)
    const cap = this._quality === 'low' || this._quality === 'medium' ? 512 : 0;
    for (const [key, paint] of Object.entries(painters)) {
      const frame = this.objects[key];
      if (!frame) continue;
      const tex = new THREE.CanvasTexture(capCanvas(paint(), cap));
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.flipY = false;
      tex.anisotropy = maxAniso;
      // map the artwork UV band (u 0.007-0.993, v 0.223-0.801) onto the whole canvas
      tex.repeat.set(1 / (ART_U[1] - ART_U[0]), 1 / (ART_V[1] - ART_V[0]));
      tex.offset.set(-ART_U[0] * tex.repeat.x, -ART_V[0] * tex.repeat.y);
      const art = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.42, metalness: 0, name: 'extras_photo_' + key });
      const d = dustTex[key] = glassDustCanvases(key === 'stairPhotoA' ? 5 : 9);
      const dust = new THREE.CanvasTexture(d.dust); dust.colorSpace = THREE.SRGBColorSpace;
      const rough = new THREE.CanvasTexture(d.rough);
      const glass = new THREE.MeshPhysicalMaterial({
        name: 'extras_frame_glass', color: 0xffffff, map: dust, roughness: 1, roughnessMap: rough, metalness: 0,
        ior: 1.52, specularIntensity: 0.85, envMapIntensity: 1.25,
        transparent: true, blending: THREE.AdditiveBlending, depthWrite: false,
      });
      frame.traverse((m) => {
        if (!m.isMesh) return;
        const n = m.material?.name || '';
        if (n.endsWith('_artwork')) { m.material = art; }
        else if (n.endsWith('_glass')) {
          if (!m.geometry.attributes.uv) { // the glass primitive ships without UVs: planar ones for the dust map
            const g = m.geometry.clone(); g.computeBoundingBox();
            const bb = g.boundingBox, p = g.attributes.position, uv = new Float32Array(p.count * 2);
            for (let i = 0; i < p.count; i++) { uv[i * 2] = (p.getX(i) - bb.min.x) / (bb.max.x - bb.min.x); uv[i * 2 + 1] = (p.getY(i) - bb.min.y) / (bb.max.y - bb.min.y); }
            g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
            m.geometry = g;
          }
          m.material = glass; m.castShadow = false; m.renderOrder = 2;
        }
      });
    }
  }

  // ------------------------------------------------------------------------------------------------ mirror
  _buildMirror() {
    const root = this.objects.mirror;
    if (!root) return;
    const G = MIRROR_GLASS;
    // arched glass outline: straight sides up to archY, then a circular arch to the apex
    const w = G.maxX, s = G.maxY - G.archY, R = (w * w + s * s) / (2 * s), cy = G.maxY - R;
    const a0 = Math.atan2(G.archY - cy, w);
    const shape = new THREE.Shape();
    shape.moveTo(G.minX, G.minY); shape.lineTo(G.maxX, G.minY); shape.lineTo(G.maxX, G.archY);
    shape.absarc(0, cy, R, a0, Math.PI - a0, false);
    shape.lineTo(G.minX, G.minY);
    const geo = new THREE.ShapeGeometry(shape, 28);
    const p = geo.attributes.position, uv = geo.attributes.uv;
    for (let i = 0; i < p.count; i++) uv.setXY(i, (p.getX(i) - G.minX) / (G.maxX - G.minX), (p.getY(i) - G.minY) / (G.maxY - G.minY));
    geo.translate(0, 0, G.z);
    const age = mirrorAgeCanvases();
    const ageData = new THREE.CanvasTexture(age.data);
    ageData.flipY = true;
    const ageCol = new THREE.CanvasTexture(age.col); ageCol.colorSpace = THREE.SRGBColorSpace;
    // fallback (low/medium, far away, or reflection off): env-mapped tarnished silver behind glass
    const glassMat = new THREE.MeshPhysicalMaterial({
      name: 'extras_mirror_glass', color: 0xffffff, map: ageCol, metalness: 1, roughness: 0.3, roughnessMap: ageData,
      envMapIntensity: 1.0, clearcoat: 0.25, clearcoatRoughness: 0.04,
    });
    const glass = new THREE.Mesh(geo, glassMat);
    glass.name = 'extra_mirror_glass';
    root.add(glass);
    // centre + normal (world) for the activation test
    root.updateMatrixWorld(true);
    const center = new THREE.Vector3(0, (G.minY + G.maxY) / 2, G.z).applyMatrix4(root.matrixWorld);
    const normal = new THREE.Vector3(0, 0, 1).transformDirection(root.matrixWorld);
    this.mirror = { root, reflector: null, glass, geo, ageData, ghost: null, active: false, center, normal, ghostT: 0 };
  }

  /** Lazily create the Reflector (only on high/ultra) with a frustum fitted to the glass: full texture resolution on the
   *  glass instead of on the whole screen, and the near plane on the glass plane (no oblique clipping needed). */
  _ensureReflector() {
    const M = this.mirror;
    if (!M || M.reflector) return M?.reflector;
    const G = MIRROR_GLASS;
    const refl = new Reflector(M.geo, {
      textureWidth: 328, textureHeight: 512, clipBias: 0.003, multisample: 4, shader: MIRROR_SHADER,
      color: new THREE.Color().setRGB(0.8, 0.77, 0.7), // aged silvering (≈ 0x8a8a8a-ish in display space, warm)
    });
    refl.name = 'extra_mirror_reflector';
    refl.material.uniforms.tAge.value = M.ageData;
    refl.visible = false;
    M.root.add(refl);
    const rt = refl.getRenderTarget();
    rt.texture.generateMipmaps = false;
    const vcam = refl.camera;
    vcam.matrixAutoUpdate = false;
    vcam.matrixWorldAutoUpdate = false;
    const texMat = refl.material.uniforms.textureMatrix.value;
    const self = this;
    const n = new THREE.Vector3(), p0 = new THREE.Vector3(), eye = new THREE.Vector3(), veye = new THREE.Vector3();
    const pa = new THREE.Vector3(), pb = new THREE.Vector3(), pc = new THREE.Vector3();
    const vr = new THREE.Vector3(), vu = new THREE.Vector3(), vn = new THREE.Vector3();
    const basis = new THREE.Matrix4();
    const bias = new THREE.Matrix4().set(0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0.5, 0.5, 0, 0, 0, 1);
    refl.onBeforeRender = function (renderer, scene, camera) {
      // main view only (not the env bake / cube cameras, not the AO normal pass), once per frame
      if (camera !== self.game.camera || scene.overrideMaterial || self._reflFrame === self._frame) return;
      self._reflFrame = self._frame;
      const mw = refl.matrixWorld;
      n.set(0, 0, 1).transformDirection(mw);
      p0.set(0, 0, G.z).applyMatrix4(mw);
      eye.setFromMatrixPosition(camera.matrixWorld);
      const dist = eye.sub(p0).dot(n);
      if (dist < 0.02) return;
      eye.add(p0);
      veye.copy(eye).addScaledVector(n, -2 * dist); // mirrored eye (behind the wall)
      // virtual screen = the glass rectangle seen from behind: right = -mirror X, up = mirror Y, normal toward the eye = -n
      pa.set(G.maxX, G.minY, G.z).applyMatrix4(mw);   // lower-left as seen by the virtual camera
      pb.set(G.minX, G.minY, G.z).applyMatrix4(mw);   // lower-right
      pc.set(G.maxX, G.maxY, G.z).applyMatrix4(mw);   // upper-left
      vr.subVectors(pb, pa).normalize(); vu.subVectors(pc, pa).normalize(); vn.crossVectors(vr, vu).normalize();
      pa.sub(veye); pb.sub(veye); pc.sub(veye);
      const d = -pa.dot(vn), near = Math.max(0.01, d - 0.0004), k = near / d;
      const l = vr.dot(pa) * k, r = vr.dot(pb) * k, b = vu.dot(pa) * k, t = vu.dot(pc) * k;
      vcam.projectionMatrix.makePerspective(l, r, t, b, near, Math.min(camera.far, 30));
      vcam.projectionMatrixInverse.copy(vcam.projectionMatrix).invert();
      basis.makeBasis(vr, vu, vn).setPosition(veye);
      vcam.matrixWorld.copy(basis);
      vcam.matrixWorldInverse.copy(basis).invert();
      vcam.far = Math.min(camera.far, 30);
      vcam.layers.mask = camera.layers.mask | (1 << GHOST_LAYER);
      texMat.copy(bias).multiply(vcam.projectionMatrix).multiply(vcam.matrixWorldInverse).multiply(mw);
      // render the reflection
      refl.visible = false;
      const curRT = renderer.getRenderTarget(), xr = renderer.xr.enabled, sau = renderer.shadowMap.autoUpdate;
      renderer.xr.enabled = false;
      renderer.shadowMap.autoUpdate = false;
      renderer.setRenderTarget(rt);
      renderer.state.buffers.depth.setMask(true);
      if (renderer.autoClear === false) renderer.clear();
      renderer.render(scene, vcam);
      renderer.xr.enabled = xr;
      renderer.shadowMap.autoUpdate = sau;
      renderer.setRenderTarget(curRT);
      if (camera.viewport !== undefined) renderer.state.viewport(camera.viewport);
      refl.visible = true;
      M.active = true;
    };
    M.reflector = refl;
    return refl;
  }

  _applyQuality(q) {
    this._quality = q || 'medium';
    const live = this._quality === 'high' || this._quality === 'ultra';
    this._reflOK = live;
    const M = this.mirror;
    if (M && live) {
      const refl = this._ensureReflector();
      const h = this._quality === 'ultra' ? 1024 : 512;
      const w = Math.round(h * (MIRROR_GLASS.maxX - MIRROR_GLASS.minX) / (MIRROR_GLASS.maxY - MIRROR_GLASS.minY));
      refl.getRenderTarget().setSize(w, h);
      refl.material.uniforms.texel.value.set(1 / w, 1 / h);
    }
    if (M && !live && M.reflector) { M.reflector.visible = false; M.glass.visible = true; }
    // CRT glow light only where the extra light is affordable. The light set must stay fixed after the build (every
    // lit shader program depends on the light count: adding / removing a light recompiles all of them, e.g. on an
    // automatic quality step-down): the light is created at build time only, later quality changes just gate it.
    if (this.crt) {
      if (live && !this.crt.light && !this._built) {
        const lt = new THREE.PointLight(0xbcd2ff, 0, 3.2, 2);
        lt.name = 'extra_crt_light';
        lt.position.set(-0.066, 0.26, 0.42);
        this.crt.root.add(lt);
        this.crt.light = lt;
      }
      this.crt.lightOK = live;
      if (this.crt.light && !live) this.crt.light.intensity = 0;
    }
  }

  // ------------------------------------------------------------------------------------------------ mirror ghost
  _ensureGhost() {
    const M = this.mirror;
    if (!M) return null;
    if (M.ghost) return M.ghost;
    // A very tall, thin, stooped woman: pale-grey gown, long black hair hanging over the face, arms to the knees.
    const g = new THREE.Group();
    g.name = 'extra_mirror_ghost';
    const gownMat = new THREE.MeshStandardMaterial({ color: 0x4f4a42, roughness: 0.95, name: 'extras_ghost_gown' });
    const skinMat = new THREE.MeshStandardMaterial({ color: 0x67625b, roughness: 0.75, name: 'extras_ghost_skin' });
    const hairMat = new THREE.MeshStandardMaterial({ color: 0x080707, roughness: 0.6, side: THREE.DoubleSide, name: 'extras_ghost_hair' });
    const mesh = (geo, mat, parent, x = 0, y = 0, z = 0) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); parent.add(m); return m; };
    const lathe = (prof, seg, phiStart, phiLen, ripple = 0, seed = 1) => {
      const geo = new THREE.LatheGeometry(prof.map(([r, y]) => new THREE.Vector2(r, y)), seg, phiStart, phiLen);
      const p = geo.attributes.position, y0 = prof[0][1], y1 = prof[prof.length - 1][1];
      for (let i = 0; i < p.count; i++) {
        const x = p.getX(i), y = p.getY(i), z = p.getZ(i), ph = Math.atan2(x, z), t = (y1 - y) / (y1 - y0 || 1);
        const k = 1 + ripple * t * (Math.sin(ph * 7 + y * 4) * 0.6 + (vnoise3(ph * 3, y * 3, 0, seed) - 0.5));
        p.setXYZ(i, x * k, y, z * k);
      }
      geo.computeVertexNormals();
      return geo;
    };
    const tube = (pts, r, seg = 12) => new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts.map(([x, y, z]) => new THREE.Vector3(x, y, z))), seg, r, 6, false);
    // legs + skirt (waist at 1.08)
    mesh(new THREE.CapsuleGeometry(0.021, 0.34, 3, 6), skinMat, g, -0.055, 0.2, 0);
    mesh(new THREE.CapsuleGeometry(0.021, 0.34, 3, 6), skinMat, g, 0.055, 0.2, 0);
    mesh(lathe([[0.2, 0.36], [0.17, 0.55], [0.12, 0.85], [0.085, 1.08], [0.06, 1.1]], 18, 0, Math.PI * 2, 0.12, 3), gownMat, g);
    // stooped upper body, pivot at the waist
    const up = new THREE.Group(); up.position.set(0, 1.08, 0); up.rotation.x = 0.2; g.add(up);
    const torso = mesh(lathe([[0.085, 0], [0.095, 0.22], [0.1, 0.4], [0.07, 0.5], [0.03, 0.53]], 14, 0, Math.PI * 2, 0.05, 5), gownMat, up);
    torso.scale.z = 0.7;
    const sh = mesh(new THREE.CapsuleGeometry(0.042, 0.2, 3, 8), gownMat, up, 0, 0.47, 0); sh.rotation.z = Math.PI / 2; sh.scale.set(1, 1, 0.75);
    mesh(new THREE.CapsuleGeometry(0.028, 0.09, 3, 6), skinMat, up, 0, 0.58, 0.02).rotation.x = 0.35;
    const headG = new THREE.Group(); headG.position.set(0, 0.62, 0.05); up.add(headG);
    const head = mesh(new THREE.SphereGeometry(0.085, 16, 12), skinMat, headG, 0, 0.1, 0.03); head.scale.set(0.85, 1.18, 0.95);
    // hair: back/sides shell (open at the front) + two front curtains leaving a thin slit over the face
    mesh(lathe([[0.02, 0.215], [0.09, 0.16], [0.1, 0.08], [0.11, -0.1], [0.125, -0.35], [0.13, -0.55]], 20, 0.55, Math.PI * 2 - 1.1, 0.25, 7), hairMat, headG, 0, 0, 0.03);
    mesh(lathe([[0.02, 0.215], [0.092, 0.16], [0.105, 0.06], [0.11, -0.15], [0.12, -0.42]], 6, 0.07, 0.5, 0.3, 9), hairMat, headG, 0, 0, 0.03);
    mesh(lathe([[0.02, 0.215], [0.092, 0.16], [0.105, 0.06], [0.11, -0.15], [0.12, -0.45]], 6, -0.57, 0.5, 0.3, 11), hairMat, headG, 0, 0, 0.03);
    // very long thin arms hanging forward to the knees, long hands
    for (const sx of [-1, 1]) {
      mesh(tube([[sx * 0.14, 0.47, 0], [sx * 0.17, 0.12, 0.02], [sx * 0.18, -0.2, 0.09], [sx * 0.17, -0.42, 0.14]], 0.02), skinMat, up);
      const hand = mesh(new THREE.CapsuleGeometry(0.016, 0.15, 3, 6), skinMat, up, sx * 0.165, -0.53, 0.16); hand.rotation.x = -0.25;
    }
    g.traverse((o) => { o.layers.set(GHOST_LAYER); if (o.isMesh) { o.castShadow = false; o.receiveShadow = true; } });
    g.visible = false;
    this.game.scene.add(g);
    M.ghost = g;
    M.ghostHead = headG;
    return g;
  }

  /** Is the mirror reflection live and the mirror inside the current view? */
  _mirrorInView() {
    const M = this.mirror, cam = this.game.camera;
    if (!M?.reflector || !this._reflOK) return false;
    if (cam.position.distanceTo(M.center) > 5) return false;
    const v = this._v.a.copy(M.center).sub(cam.position);
    if (v.dot(M.normal) > -0.05) return false; // behind or edge-on
    cam.updateMatrixWorld();
    v.copy(M.center).applyMatrix4(cam.matrixWorldInverse).applyMatrix4(cam.projectionMatrix);
    return v.z < 1 && Math.abs(v.x) < 1.1 && Math.abs(v.y) < 1.1;
  }

  mirrorGhost(seconds = 0.9) {
    const M = this.mirror;
    if (!M) return false;
    const ghost = this._ensureGhost();
    const cam = this.game.camera, R = L.ROOM;
    const e = this._v.b.copy(cam.position);
    const front = this._v.a.copy(e).sub(M.center).dot(M.normal);
    if (front < 0.3) return false;
    // aim at a point of the glass a little off-centre (over the player's shoulder), follow the reflected ray back
    // into the room and stand her ~0.8 m behind the player on it: her reflection lands on the glass
    const side = (e.x - M.center.x) > 0 ? 1 : -1; // mirror-x offset toward the player's side
    const t = this._v.c.set(M.center.x + side * 0.07 * Math.abs(M.normal.z) , M.center.y, M.center.z + side * 0.07 * Math.abs(M.normal.x));
    const r = this._v.a.copy(t).sub(e);
    r.addScaledVector(M.normal, -2 * r.dot(M.normal)); // reflected direction (points back into the room)
    r.y = 0;
    const rn = r.dot(M.normal);
    if (rn < 1e-3) return false;
    const k = (front + 0.8) / rn;
    let gx = t.x + r.x * k, gz = t.z + r.z * k;
    gx = Math.min(R.maxX - 0.35, Math.max(R.minX + 0.35, gx));
    gz = Math.min(R.maxZ - 0.35, Math.max(R.minZ + 0.35, gz));
    if ((gx - M.center.x) * M.normal.x + (gz - M.center.z) * M.normal.z < front + 0.25) return false;
    ghost.position.set(gx, this.world.groundHeightAt(gx, gz), gz);
    ghost.rotation.set(0, Math.atan2(e.x - gx, e.z - gz), 0);
    ghost.visible = true;
    M.ghostT = Math.max(0.05, seconds);
    return this._mirrorInView();
  }

  // ------------------------------------------------------------------------------------------------ old CRT
  _buildCRT() {
    const tv = this.objects.oldTv;
    if (!tv) return;
    // a curved emissive "phosphor" sheet projected onto the TV's own bulging glass (raycast in model space)
    const S = TV_SCREEN, sx = 14, sy = 10;
    const geo = new THREE.PlaneGeometry(S.maxX - S.minX, S.maxY - S.minY, sx, sy);
    geo.translate((S.minX + S.maxX) / 2, (S.minY + S.maxY) / 2, 0);
    const probe = this.game.assets.instance('Television_01');
    probe.updateMatrixWorld(true);
    const ray = new THREE.Raycaster(), o = new THREE.Vector3(), dir = new THREE.Vector3(0, 0, -1);
    const p = geo.attributes.position;
    for (let i = 0; i < p.count; i++) {
      o.set(p.getX(i), p.getY(i), 0.5);
      ray.set(o, dir); ray.far = 0.45;
      const hit = ray.intersectObject(probe, true)[0];
      p.setZ(i, (hit ? Math.min(hit.point.z, 0.196) : 0.172) + 0.0025);
    }
    geo.computeVertexNormals();
    const W = 128, H = 96;
    const data = new Uint8Array(W * H * 4);
    const tex = new THREE.DataTexture(data, W, H, THREE.RGBAFormat);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.magFilter = THREE.LinearFilter; tex.minFilter = THREE.LinearFilter;
    tex.needsUpdate = true;
    // static rounded-corner phosphor mask + scanlines (computed once)
    const mask = new Float32Array(W * H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const u = (x + 0.5) / W * 2 - 1, v = (y + 0.5) / H * 2 - 1;
      const q = Math.pow(Math.pow(Math.abs(u), 6) + Math.pow(Math.abs(v), 6), 1 / 6); // squircle
      mask[y * W + x] = smooth(1.0, 0.86, q) * (1 - 0.35 * (u * u + v * v) * 0.5) * (y % 2 ? 0.72 : 1);
    }
    const mat = new THREE.MeshBasicMaterial({
      name: 'extras_crt_static', map: tex, color: 0x000000, transparent: true, blending: THREE.AdditiveBlending,
      depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
    });
    const screen = new THREE.Mesh(geo, mat);
    screen.name = 'extra_crt_screen';
    screen.visible = false;
    screen.renderOrder = 3;
    screen.userData.noAO = true;
    tv.add(screen);
    tv.updateMatrixWorld(true);
    const pos = new THREE.Vector3(-0.066, 0.26, 0.2).applyMatrix4(tv.matrixWorld);
    this.crt = { root: tv, screen, mat, tex, data, mask, W, H, pos, light: null, t: -1, delay: 0, snd: null, rnd: rng(77), seed: 1, lvl: 1, lvlT: 0 };
  }

  /** Old CRT comes to life with static for ~1.3 s, then collapses to a line and a dot and dies. */
  crtFlicker(delay = 0) {
    const C = this.crt;
    if (!C) return;
    this._stopCRT();
    C.t = 0; C.delay = delay; C.started = false; C.offPlayed = false;
    if (this.chain) this.chain.kick = Math.max(this.chain.kick, 0.09); // the panel thump shakes the pull-chain a bit
  }

  _stopCRT() {
    const C = this.crt;
    if (!C) return;
    C.t = -1;
    C.screen.visible = false;
    if (C.light) C.light.intensity = 0;
    try { C.snd?.stop?.(0.1); } catch (_) { /* audio stub */ }
    C.snd = null;
  }

  _updateCRT(dt) {
    const C = this.crt;
    if (C.delay > 0) { C.delay -= dt; return; }
    if (!C.started) {
      C.started = true;
      C.screen.visible = true;
      try { C.snd = this.game.audio?.loop?.('tv_static', { position: C.pos, volume: 0.16 }) || null; } catch (_) { C.snd = null; }
    }
    C.t += dt;
    const t = C.t, R = C.rnd;
    // phases: 0-0.1 line opens | 0.1-1.25 static with flicker & drop-outs | 1.25-1.4 collapse to a line | 1.4-1.52 to a dot | -1.9 dot fades
    let b = 1, hExt = 1, wExt = 1;
    if (t < 0.1) { hExt = 0.02 + 0.98 * (t / 0.1); b = 1.5; }
    else if (t < 1.25) {
      C.lvlT -= dt;
      if (C.lvlT <= 0) { C.lvl = 0.55 + R() * 0.6; if (R() < 0.12) C.lvl = 0.12; C.lvlT = 0.04 + R() * 0.08; }
      b = C.lvl;
    } else if (t < 1.4) {
      const k = (t - 1.25) / 0.15; hExt = Math.max(0.012, 1 - k * k); b = 1 + k * 0.9;
      if (!C.offPlayed) {
        C.offPlayed = true;
        try { C.snd?.stop?.(0.12); } catch (_) { /* audio stub */ }
        C.snd = null;
        try { this.game.audio?.play?.('tv_off', { position: C.pos, volume: 0.3 }); } catch (_) { /* audio stub */ }
      }
    } else if (t < 1.52) { hExt = 0.012; wExt = Math.max(0.03, 1 - (t - 1.4) / 0.12); b = 1.9; }
    else if (t < 1.9) { hExt = 0.012; wExt = 0.03; b = 1.9 * (1 - (t - 1.52) / 0.38); }
    else { this._stopCRT(); return; }
    // regenerate the snow (128x96, only during this ~2 s beat)
    const { W, H, data, mask } = C;
    const roll = ((t * 0.7) % 1) * H;
    const hh = hExt * 0.5, ww = wExt * 0.5;
    const line = hExt < 0.05;
    for (let y = 0; y < H; y++) {
      const v = Math.abs((y + 0.5) / H - 0.5);
      const vy = line ? Math.max(0, 1 - v / (hh + 0.012)) : smooth(hh + 0.01, hh - 0.01, v);
      const dr = Math.abs(y - roll);
      const bar = 1 - 0.45 * Math.exp(-Math.min(dr, H - dr) * Math.min(dr, H - dr) / 40);
      for (let x = 0; x < W; x++) {
        const u = Math.abs((x + 0.5) / W - 0.5);
        const vx = smooth(ww + 0.02, ww - 0.01, u);
        const n = line ? 1 : 0.18 + 0.82 * R();
        const s = n * vy * vx * (line ? 1 : mask[y * W + x] * bar) * 255;
        const k = (y * W + x) * 4;
        data[k] = s * 0.9; data[k + 1] = s * 0.95; data[k + 2] = s; data[k + 3] = 255;
      }
    }
    C.tex.needsUpdate = true;
    C.mat.color.setScalar(b * 1.6);
    if (C.light) C.light.intensity = C.lightOK ? b * (line ? 0.4 : 3.0) * Math.max(hExt, 0.05) : 0; // a CRT face is ~10 cd at full white
  }

  // ------------------------------------------------------------------------------------------------ pull-chain socket
  _buildSocket() {
    const s = this.objects.socket;
    const chain = s?.getObjectByName('pull_chain_light_socket_chain');
    if (!chain) return;
    const pivot = new THREE.Object3D();
    pivot.name = 'extra_socket_chain_pivot';
    pivot.position.set(-0.023, -0.019, 0);
    chain.parent.add(pivot);
    pivot.add(chain);
    chain.position.sub(pivot.position);
    this.chain = { pivot, t: Math.random() * 10, kick: 0.04, pos: new THREE.Vector3(1.8, 2.42, -3.6) };
    s.updateMatrixWorld(true);
    this.chain.pos.setFromMatrixPosition(pivot.matrixWorld);
  }

  // ------------------------------------------------------------------------------------------------ contract
  update(dt) {
    this._frame++;
    this._t += dt;
    const cam = this.game.camera;
    const M = this.mirror;
    if (M) {
      M.active = false; // set again by the reflector when it renders this frame
      // live reflection only on high/ultra, in front of the mirror, within ~5 m (hysteresis); frustum culling does the rest
      const dist = cam.position.distanceTo(M.center);
      const front = this._v.a.copy(cam.position).sub(M.center).dot(M.normal) > 0.03;
      const want = !!(this._reflOK && M.reflector && front && dist < (M.reflector.visible ? 5.4 : 5.0));
      if (M.reflector) M.reflector.visible = want;
      M.glass.visible = !want;
      if (M.ghost?.visible) {
        M.ghostT -= dt;
        if (M.ghostHead) M.ghostHead.rotation.z = Math.sin(this._t * 23) * 0.04 + (M.ghostT < 0.25 ? 0.35 : 0);
        if (M.ghostT <= 0) M.ghost.visible = false;
      }
    }
    if (this.crt && this.crt.t >= 0) this._updateCRT(dt);
    const ch = this.chain;
    if (ch && cam.position.distanceToSquared(ch.pos) < 64) {
      ch.t += dt;
      ch.kick = Math.max(0.012, ch.kick * Math.exp(-dt * 0.35));
      const a = ch.kick;
      ch.pivot.rotation.z = Math.sin(ch.t * 8.2) * a + Math.sin(ch.t * 1.3) * 0.006;
      ch.pivot.rotation.x = Math.sin(ch.t * 7.7 + 1.3) * a * 0.55;
    }
  }

  reset(kind) {
    this._stopCRT();
    if (this.mirror?.ghost) { this.mirror.ghost.visible = false; this.mirror.ghostT = 0; }
    this._power = this.world.power !== false;
    void kind;
  }

  setPower(on) {
    const was = this._power;
    this._power = !!on;
    if (on && !was) this.crtFlicker(0.55);
    if (!on) this._stopCRT();
  }
}
