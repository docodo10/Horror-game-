import * as THREE from 'three';

/**
 * La Gardienne — procedural creature model + procedural animation (no external mesh assets).
 *
 * Build: a THREE.Bone skeleton (pelvis/spine/chest/neck/head/jaw, clavicles/arms/forearms/hands + 3-phalanx fingers,
 * thighs/shins/feet/toes, a skirt sway bone and 9 simulated hair chains) shared by several SkinnedMeshes:
 *   - body skin   one continuous-tube mesh per limb (seamless elbows/knees through skin weights), noise displaced,
 *                 bony landmarks (clavicles, ribs, neck tendons, knuckles, ankle bones), tiling pore/vein detail maps
 *   - head        deformed dense sphere: gaunt long face, deep eye sockets, cheekbones, thin hooked nose, a too-wide
 *                 mouth whose slit is rigged to a jaw + "mouth depth" bone (+ an upper-lip snarl bone, mouth corners
 *                 dragged down with the jaw: an oval scream, not a grin) so it really opens; unique painted
 *                 colour/normal canvases (black tear streaks, cracked lips, temple veins, dark scalp)
 *   - teeth       yellowed, uneven, too many — upper row on the head bone, lower row on the jaw
 *   - gown        slip nightgown (fabric032 CC0 woven cotton via game.assets.pbr, procedural grime/stains in vertex
 *                 colours), vertical folds, ragged/torn hem (geometry + alpha tears), skinned to hips/thighs/sway bone
 *   - hair        several hundred wet clumped ribbons (alpha-tested fibre texture, low matte specular), draped at
 *                 build time against head/body colliders, then driven by 9 verlet-simulated bone chains; a few short
 *                 stray wisps stay rigid on the face (break the hairline, remain across the face when the curtain parts)
 * Eyes: wet dark eyeballs deep in the sockets with tiny emissive pinpoint glints (eyeshine).
 *
 * Model space: feet at the origin, faces +Z, ~1.98 m tall when upright. `root` is the object to place in the world.
 *
 * Animation (update(dt, ctx)): layered procedural pose — heavy slow limping walk, stair walk, listening/search idle
 * with jerky head tilts, fast predatory chase gait, door reach, jumpscare lunge (arms rising, head snap, jaw drop,
 * hair parting) and random "glitch" twitches (pose freezes, head snaps, spasms).
 * ctx = { speed, mode: 'idle'|'walk'|'search'|'chase'|'reach'|'jumpscare', stairs: -1|0|1, look: Vector3|null,
 *         jumpT: seconds since the jumpscare started (or -1), aggression: 0..2, eyeshine: 0..1,
 *         duck: 0..1 (folds the upper body down under low headroom, e.g. the stairwell bulkhead) }
 * onFootstep(side 'L'|'R', worldPos) is called at each heel strike.
 */

const TAU = Math.PI * 2;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const lerp = (a, b, t) => a + (b - a) * t;
const sstep = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };
const dampTo = (cur, target, rate, dt) => cur + (target - cur) * (1 - Math.exp(-rate * dt));
const gauss = (d2, s) => Math.exp(-d2 / (s * s));

// ------------------------------------------------------------------------------------------------ noise helpers
function hash3i(x, y, z, s) {
  let h = Math.imul(x | 0, 0x27d4eb2d) ^ Math.imul(y | 0, 0x165667b1) ^ Math.imul(z | 0, 0x1b873593) ^ Math.imul(s | 0, 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 15), 0x2c1b3c6d);
  h = Math.imul(h ^ (h >>> 12), 0x297a2d39);
  h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
}
function vnoise3(x, y, z, s = 0) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  let fx = x - xi, fy = y - yi, fz = z - zi;
  fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy); fz = fz * fz * (3 - 2 * fz);
  const a = hash3i(xi, yi, zi, s), b = hash3i(xi + 1, yi, zi, s), c = hash3i(xi, yi + 1, zi, s), d = hash3i(xi + 1, yi + 1, zi, s);
  const e = hash3i(xi, yi, zi + 1, s), f = hash3i(xi + 1, yi, zi + 1, s), g = hash3i(xi, yi + 1, zi + 1, s), h = hash3i(xi + 1, yi + 1, zi + 1, s);
  const x1 = a + (b - a) * fx, x2 = c + (d - c) * fx, x3 = e + (f - e) * fx, x4 = g + (h - g) * fx;
  const y1 = x1 + (x2 - x1) * fy, y2 = x3 + (x4 - x3) * fy;
  return y1 + (y2 - y1) * fz;
}
function fbm3(x, y, z, oct = 3, s = 0) {
  let a = 0.5, f = 1, sum = 0, n = 0;
  for (let i = 0; i < oct; i++) { sum += a * vnoise3(x * f, y * f, z * f, s + i * 31); n += a; a *= 0.5; f *= 2.07; }
  return sum / n;
}
function mulberry32(seed) {
  let a = seed | 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Periodic fBm value-noise tile (tileable textures). sample(u, v) with u, v in tile units (1 = one tile). */
class NoiseTile {
  constructor(size, cells, octaves, seed) {
    this.size = size;
    const d = (this.data = new Float32Array(size * size));
    let amp = 1, norm = 0;
    for (let o = 0; o < octaves; o++) {
      const n = cells << o;
      const lat = new Float32Array(n * n);
      for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) lat[j * n + i] = hash3i(i, j, o, seed);
      for (let y = 0; y < size; y++) {
        const gy = (y / size) * n, y0 = Math.floor(gy);
        let ty = gy - y0; ty = ty * ty * (3 - 2 * ty);
        const r0 = (y0 % n) * n, r1 = ((y0 + 1) % n) * n;
        for (let x = 0; x < size; x++) {
          const gx = (x / size) * n, x0 = Math.floor(gx);
          let tx = gx - x0; tx = tx * tx * (3 - 2 * tx);
          const c0 = x0 % n, c1 = (x0 + 1) % n;
          const a = lat[r0 + c0] + (lat[r0 + c1] - lat[r0 + c0]) * tx;
          const b = lat[r1 + c0] + (lat[r1 + c1] - lat[r1 + c0]) * tx;
          d[y * size + x] += (a + (b - a) * ty) * amp;
        }
      }
      norm += amp; amp *= 0.5;
    }
    let mn = Infinity, mx = -Infinity;
    for (let i = 0; i < d.length; i++) { d[i] /= norm; if (d[i] < mn) mn = d[i]; if (d[i] > mx) mx = d[i]; }
    const k = 1 / Math.max(1e-6, mx - mn);
    for (let i = 0; i < d.length; i++) d[i] = (d[i] - mn) * k;
  }
  sample(u, v) {
    const s = this.size;
    const fx = (u - Math.floor(u)) * s, fy = (v - Math.floor(v)) * s;
    const x0 = fx | 0, y0 = fy | 0, tx = fx - x0, ty = fy - y0;
    const x1 = (x0 + 1) % s, y1 = (y0 + 1) % s, d = this.data;
    const a = d[y0 * s + x0] + (d[y0 * s + x1] - d[y0 * s + x0]) * tx;
    const b = d[y1 * s + x0] + (d[y1 * s + x1] - d[y1 * s + x0]) * tx;
    return a + (b - a) * ty;
  }
}

function heightToNormal(h, w, hh, strength, wrap = true) {
  const out = new Uint8ClampedArray(w * hh * 4);
  for (let y = 0; y < hh; y++) {
    const ym = wrap ? (y - 1 + hh) % hh : Math.max(0, y - 1), yp = wrap ? (y + 1) % hh : Math.min(hh - 1, y + 1);
    for (let x = 0; x < w; x++) {
      const xm = wrap ? (x - 1 + w) % w : Math.max(0, x - 1), xp = wrap ? (x + 1) % w : Math.min(w - 1, x + 1);
      const dx = (h[y * w + xp] - h[y * w + xm]) * strength;
      const dy = (h[yp * w + x] - h[ym * w + x]) * strength;
      let nx = -dx, ny = dy, nz = 1;
      const l = Math.hypot(nx, ny, nz); nx /= l; ny /= l; nz /= l;
      const i = (y * w + x) * 4;
      out[i] = (nx * 0.5 + 0.5) * 255; out[i + 1] = (ny * 0.5 + 0.5) * 255; out[i + 2] = (nz * 0.5 + 0.5) * 255; out[i + 3] = 255;
    }
  }
  return out;
}

function dataTexture(rgba, w, h, { srgb = false, repeat = true } = {}) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  ctx.putImageData(new ImageData(rgba, w, h), 0, 0);
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 4;
  t.needsUpdate = true;
  return t;
}

// ------------------------------------------------------------------------------------------------ geometry builder
class GeoBuilder {
  constructor() {
    this.pos = []; this.uv = []; this.col = []; this.si = []; this.sw = []; this.idx = []; this.seams = []; this.poles = [];
  }
  get count() { return this.pos.length / 3; }
  vert(x, y, z, u, v, c, w) {
    this.pos.push(x, y, z); this.uv.push(u, v); this.col.push(c[0], c[1], c[2]);
    // keep the 4 strongest influences, normalised
    const ws = w.slice().sort((a, b) => b[1] - a[1]).slice(0, 4);
    let sum = 0; for (const e of ws) sum += e[1];
    for (let i = 0; i < 4; i++) {
      const e = ws[i];
      this.si.push(e ? e[0] : 0); this.sw.push(e && sum > 0 ? e[1] / sum : 0);
    }
    return this.count - 1;
  }
  tri(a, b, c) { this.idx.push(a, b, c); }
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(this.si, 4));
    g.setAttribute('skinWeight', new THREE.Float32BufferAttribute(this.sw, 4));
    g.setIndex(this.idx);
    g.computeVertexNormals();
    const n = g.attributes.normal;
    const t = new THREE.Vector3();
    for (const [a, b] of this.seams) {
      t.set(n.getX(a) + n.getX(b), n.getY(a) + n.getY(b), n.getZ(a) + n.getZ(b)).normalize();
      n.setXYZ(a, t.x, t.y, t.z); n.setXYZ(b, t.x, t.y, t.z);
    }
    for (const grp of this.poles) {
      t.set(0, 0, 0);
      for (const i of grp) t.x += n.getX(i), t.y += n.getY(i), t.z += n.getZ(i);
      t.normalize();
      for (const i of grp) n.setXYZ(i, t.x, t.y, t.z);
    }
    g.computeBoundingSphere();
    return g;
  }
}

const _tv1 = new THREE.Vector3(), _tv2 = new THREE.Vector3(), _tv3 = new THREE.Vector3();

/**
 * Generalised tube (limbs, torso, fingers, feet, gown). keys: [{p:[x,y,z], rx, rz}] along the axis.
 * rx = half-size along `side` (= front × tangent), rz = along `front`.
 */
function addTube(B, keys, o) {
  const pts = keys.map((k) => new THREE.Vector3(k.p[0], k.p[1], k.p[2]));
  const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal', 0.5);
  const cum = [0];
  for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + pts[i].distanceTo(pts[i - 1]));
  const total = cum[cum.length - 1];
  const radAt = (s) => {
    const d = s * total;
    let i = 0;
    while (i < cum.length - 2 && cum[i + 1] < d) i++;
    const t = sstep(0, 1, (d - cum[i]) / Math.max(1e-6, cum[i + 1] - cum[i]));
    return [lerp(keys[i].rx, keys[i + 1].rx, t), lerp(keys[i].rz, keys[i + 1].rz, t)];
  };
  const len = curve.getLength();
  const segs = o.segs ?? 16;
  const nR = o.rings ?? Math.max(3, Math.ceil(len / (o.step ?? 0.012)));
  const front = new THREE.Vector3().fromArray(o.front ?? [0, 0, 1]);
  const rings = [];
  const capN = o.capN ?? 4;
  const mk = (s, shrink, along) => {
    const c = curve.getPointAt(clamp(s, 0, 1));
    const t = curve.getTangentAt(clamp(s, 0, 1)).normalize();
    const [rx, rz] = radAt(clamp(s, 0, 1));
    const f = front.clone().addScaledVector(t, -front.dot(t));
    if (f.lengthSq() < 1e-6) f.set(1, 0, 0).addScaledVector(t, -t.x);
    f.normalize();
    const side = new THREE.Vector3().crossVectors(f, t).normalize();
    f.crossVectors(t, side).normalize();
    const r = Math.max(rx, rz);
    c.addScaledVector(t, along * r * (o.capLen ?? 0.85));
    rings.push({ c, t, f, side, rx: rx * shrink, rz: rz * shrink, s: clamp(s, 0, 1), pole: shrink < 1e-3 });
  };
  if (o.capStart) for (let k = capN; k >= 1; k--) { const b = (k / capN) * Math.PI / 2; mk(0, Math.cos(b), -Math.sin(b)); }
  for (let i = 0; i <= nR; i++) mk(i / nR, 1, 0);
  if (o.capEnd) for (let k = 1; k <= capN; k++) { const b = (k / capN) * Math.PI / 2; mk(1, Math.cos(b), Math.sin(b)); }

  const tile = o.tile ?? 0.1;
  const avgR = (keys.reduce((a, k) => a + (k.rx + k.rz) * 0.5, 0) / keys.length);
  const tilesAround = Math.max(1, Math.round((TAU * avgR) / tile));
  const base = B.count;
  const P = new THREE.Vector3(), N = new THREE.Vector3();
  for (let ri = 0; ri < rings.length; ri++) {
    const R = rings[ri];
    const pole = [];
    const w = o.weights(R.c, R.s);
    for (let j = 0; j <= segs; j++) {
      const a = (j / segs) * TAU, ca = Math.cos(a), sa = Math.sin(a);
      P.copy(R.c).addScaledVector(R.side, ca * R.rx).addScaledVector(R.f, sa * R.rz);
      N.copy(R.side).multiplyScalar(ca / Math.max(1e-4, R.rx)).addScaledVector(R.f, sa / Math.max(1e-4, R.rz)).normalize();
      if (o.disp && !R.pole) P.addScaledVector(N, o.disp(P, N, R.s, a));
      if (o.post) o.post(P, R.s, a, ri, rings.length);
      const ww = o.weightsP ? o.weightsP(P, R.s, w) : w;
      const col = o.color ? o.color(P, R.s, a, N) : [1, 1, 1];
      const u = o.uvU ? o.uvU(a, R.s) : (j / segs) * tilesAround;
      const v = o.uvV ? o.uvV(R.s, P) : (R.s * len) / tile;
      const idx = B.vert(P.x, P.y, P.z, u, v, col, ww);
      if (R.pole) pole.push(idx);
    }
    B.seams.push([base + ri * (segs + 1), base + ri * (segs + 1) + segs]);
    if (pole.length) B.poles.push(pole);
  }
  // triangles, oriented outward (auto-checked on the first quad of the main body)
  const triList = [];
  for (let ri = 0; ri < rings.length - 1; ri++) {
    for (let j = 0; j < segs; j++) {
      const a = base + ri * (segs + 1) + j, b = a + 1, c = a + segs + 1, d = c + 1;
      triList.push(a, b, c, b, d, c);
    }
  }
  const mid = (o.capStart ? capN : 0) + Math.floor(nR / 2);
  const ia = base + mid * (segs + 1), ib = ia + 1, ic = ia + segs + 1;
  _tv1.fromArray(B.pos, ia * 3); _tv2.fromArray(B.pos, ib * 3).sub(_tv1); _tv3.fromArray(B.pos, ic * 3).sub(_tv1);
  const nrm = new THREE.Vector3().crossVectors(_tv2, _tv3);
  const out = _tv1.clone().sub(rings[mid].c);
  const flip = (nrm.dot(out) < 0) !== !!o.inward;
  for (let i = 0; i < triList.length; i += 3) {
    if (flip) B.tri(triList[i], triList[i + 2], triList[i + 1]);
    else B.tri(triList[i], triList[i + 1], triList[i + 2]);
  }
  return { rings, segs, base };
}

const SIDES2 = [['L', 1], ['R', -1]];
const SIDES3 = [['L', 0, 1], ['R', Math.PI, -1]];
/** Did a wrapping gait phase (0..2π) pass angle a between two frames? */
const phaseCrossed = (prev, cur, a) => (prev < a && cur >= a) || (prev > cur && (a > prev || a <= cur));

// ------------------------------------------------------------------------------------------------ skeleton layout
// [name, parent, x, y, z] — model-space rest positions (all rest rotations are identity).
const SKEL = [
  ['root', null, 0, 0, 0],
  ['hips', 'root', 0, 1.06, 0],
  ['skirt', 'hips', 0, 1.02, 0],
  ['spine1', 'hips', 0, 1.18, -0.008],
  ['spine2', 'spine1', 0, 1.32, -0.012],
  ['chest', 'spine2', 0, 1.46, -0.012],
  ['neck', 'chest', 0, 1.615, -0.018],
  ['head', 'neck', 0, 1.8, -0.004],
  ['jaw', 'head', 0, 1.838, -0.016],
  ['mouth', 'head', 0, 1.81, 0.075],
  ['lipU', 'head', 0, 1.818, 0.085],   // upper lip: lifts into a snarl as the jaw drops (oval scream, not a grin)
];
for (const [S, sx] of [['L', 1], ['R', -1]]) {
  SKEL.push(
    ['clav' + S, 'chest', 0.02 * sx, 1.585, 0.0],
    ['arm' + S, 'clav' + S, 0.165 * sx, 1.585, -0.02],
    ['fore' + S, 'arm' + S, 0.165 * sx, 1.225, -0.02],
    ['hand' + S, 'fore' + S, 0.165 * sx, 0.895, -0.02],
    ['thigh' + S, 'hips', 0.085 * sx, 1.02, 0],
    ['shin' + S, 'thigh' + S, 0.085 * sx, 0.55, 0],
    ['foot' + S, 'shin' + S, 0.085 * sx, 0.075, 0],
    ['toe' + S, 'foot' + S, 0.085 * sx, 0.02, 0.145],
  );
}
// fingers: [name, dz, rootY, length, dxRoot]
const FINGERS = [
  ['index', 0.026, 0.793, 0.118, 0.0],
  ['middle', 0.009, 0.789, 0.134, 0.0],
  ['ring', -0.008, 0.792, 0.124, 0.0],
  ['pinky', -0.024, 0.801, 0.1, 0.0],
];
const PHAL = [0.44, 0.31, 0.25];
for (const [S, sx] of [['L', 1], ['R', -1]]) {
  for (const [fn, dz, ry, L] of FINGERS) {
    const x = 0.165 * sx, z = -0.02 + dz;
    let y = ry;
    let parent = 'hand' + S;
    for (let k = 0; k < 3; k++) {
      const name = `${fn}${k}${S}`;
      SKEL.push([name, parent, x, y, z]);
      parent = name; y -= L * PHAL[k];
    }
  }
  // thumb: starts at the front of the wrist, points down-forward
  const tx = 0.161 * sx, ty = 0.872, tz = 0.012;
  const dir = new THREE.Vector3(-0.12 * sx, -0.78, 0.6).normalize();
  const lens = [0.036, 0.03, 0.026];
  let p = new THREE.Vector3(tx, ty, tz), parent = 'hand' + S;
  for (let k = 0; k < 3; k++) {
    const name = `thumb${k}${S}`;
    SKEL.push([name, parent, p.x, p.y, p.z]);
    parent = name; p = p.clone().addScaledVector(dir, lens[k]);
  }
}

// Head layout (head-local, head pivot = model (0, 1.80, -0.004)): base ellipsoid
const HEAD_C = new THREE.Vector3(0, 0.07, 0.005);
const HEAD_R = new THREE.Vector3(0.074, 0.124, 0.096);
const MOUTH_PHI = THREE.MathUtils.degToRad(118);
const MOUTH_SPAN = THREE.MathUtils.degToRad(46);
const EYE_THETA = THREE.MathUtils.degToRad(26);
const EYE_PHI = THREE.MathUtils.degToRad(80);

function headBase(theta, phi, out) {
  const sp = Math.sin(phi);
  out.set(sp * Math.sin(theta) * HEAD_R.x, Math.cos(phi) * HEAD_R.y, sp * Math.cos(theta) * HEAD_R.z).add(HEAD_C);
  const yy = out.y;
  const jawN = sstep(0.075, -0.06, yy);
  out.x *= 1 - 0.3 * jawN;
  if (out.z < HEAD_C.z) out.z = HEAD_C.z + (out.z - HEAD_C.z) * (1 - 0.32 * jawN);
  out.x *= 1 + 0.075 * sstep(0.07, 0.17, yy) - 0.03 * sstep(0.17, 0.2, yy);   // wide parietal dome
  const cran = sstep(0.0, 0.12, yy) * sstep(0.0, -0.06, out.z - HEAD_C.z);
  out.z -= 0.013 * cran; out.y += 0.004 * cran;
  if (out.z > 0.055) out.z = 0.055 + (out.z - 0.055) * 0.82;
  // chin forward + long
  const chin = sstep(-0.01, -0.055, yy) * sstep(0.02, 0.07, out.z);
  out.z += 0.009 * chin; out.y -= 0.012 * chin;
  return out;
}
const _hb = new THREE.Vector3();
function headAnchor(thDeg, phDeg) { return headBase(THREE.MathUtils.degToRad(thDeg), THREE.MathUtils.degToRad(phDeg), new THREE.Vector3()); }

// bumps along the head normal: [anchor, amplitude(m), sigma(m)]
function headBumps() {
  const B = [];
  const add = (p, a, s) => B.push([p, a, s]);
  for (const sx of [1, -1]) {
    const e = headAnchor(26 * sx, 80);
    add(e, -0.026, 0.02);                                   // deep eye sockets
    add(headAnchor(30 * sx, 76), -0.008, 0.016);           // upper lid hollow
    add(headAnchor(27 * sx, 88), -0.007, 0.015);           // under-eye hollow
    add(headAnchor(24 * sx, 69), 0.0055, 0.016);           // brow ridge
    add(headAnchor(48 * sx, 92), 0.006, 0.016);            // cheekbones
    add(headAnchor(42 * sx, 108), -0.012, 0.022);          // hollow cheeks
    add(headAnchor(62 * sx, 66), -0.006, 0.022);           // temples
    add(headAnchor(66 * sx, 120), 0.004, 0.014);           // jaw angle
    add(headAnchor(9 * sx, 101), -0.0035, 0.0055);         // nostrils
    add(headAnchor(11 * sx, 99), 0.003, 0.006);            // alae
  }
  add(headAnchor(0, 72), 0.0035, 0.011);                    // glabella
  add(headAnchor(0, 80), 0.0058, 0.0068);                   // nose bridge
  add(headAnchor(0, 87), 0.0088, 0.0068);
  add(headAnchor(0, 94), 0.0152, 0.0078);
  add(headAnchor(0, 99.5), 0.0105, 0.0066);                 // nose tip (hooked down)
  add(headAnchor(0, 104), -0.002, 0.007);                   // philtrum
  add(headAnchor(0, 116), 0.004, 0.028);                    // teeth arch / muzzle
  add(headAnchor(0, 140), 0.006, 0.016);                    // chin
  return B;
}

// ------------------------------------------------------------------------------------------------ the model
export class GardienneModel {
  constructor(game, opts = {}) {
    this.game = game;
    const q = opts.quality ?? game?.renderer?.quality ?? 'high';
    this.q = q;
    this.lowQ = q === 'low';
    this.rand = mulberry32(1337);
    this.root = new THREE.Group();
    this.root.name = 'Gardienne';

    this.onFootstep = null;
    this.time = 0;
    this._v = { a: new THREE.Vector3(), b: new THREE.Vector3(), c: new THREE.Vector3(), d: new THREE.Vector3() };
    this._q = { a: new THREE.Quaternion(), b: new THREE.Quaternion(), c: new THREE.Quaternion() };
    this._hq = new THREE.Quaternion(); this._pq = new THREE.Quaternion(); this._rq = new THREE.Quaternion(); this._lq = new THREE.Quaternion();
    this._m = new THREE.Matrix4();

    this._buildSkeleton();
    this._buildTextures();
    this._buildMaterials();
    this._buildBody();
    this._buildHead();
    this._buildTeeth();
    this._buildEyes();
    this._buildGown();
    this._buildHair();
    this._bindAll();
    this._initPose();
  }

  // ---------------------------------------------------------------------------------------- skeleton
  _buildSkeleton() {
    this.b = {};
    this.restW = {};
    this.boneList = [];
    this.boneIndex = {};
    for (const [name, parent, x, y, z] of SKEL) this._addBone(name, parent, x, y, z);
    this.root.add(this.b.root);
  }

  _addBone(name, parent, x, y, z) {
    const bone = new THREE.Bone();
    bone.name = name;
    const w = new THREE.Vector3(x, y, z);
    this.restW[name] = w;
    if (parent) {
      const pw = this.restW[parent];
      bone.position.set(x - pw.x, y - pw.y, z - pw.z);
      this.b[parent].add(bone);
    } else bone.position.copy(w);
    this.b[name] = bone;
    this.boneIndex[name] = this.boneList.length;
    this.boneList.push(bone);
    return bone;
  }

  bi(name) { return this.boneIndex[name]; }

  // ---------------------------------------------------------------------------------------- textures
  _buildTextures() {
    const hi = !this.lowQ;
    const T = (this.tiles = {
      A: new NoiseTile(128, 4, 4, 11),
      B: new NoiseTile(256, 8, 5, 23),
      C: new NoiseTile(256, 32, 3, 37),
    });
    // ---- tiling skin detail (albedo modulation + normal)
    {
      const S = hi ? 512 : 256;
      const col = new Uint8ClampedArray(S * S * 4), h = new Float32Array(S * S);
      for (let y = 0; y < S; y++) {
        const v = y / S;
        for (let x = 0; x < S; x++) {
          const u = x / S;
          const mott = T.A.sample(u * 2, v * 2), mid = T.B.sample(u, v), hiF = T.C.sample(u * 2, v * 2);
          const pore = sstep(0.6, 0.8, T.C.sample(u * 4 + 0.37, v * 4 + 0.11));
          const wr = Math.abs(T.B.sample(u * 1, v * 4 + 0.3) - 0.5);
          const wrinkle = 1 - sstep(0.0, 0.05, wr);
          const vein = (1 - sstep(0.0, 0.03, Math.abs(T.B.sample(u + 0.5, v + 0.21) - 0.5))) * sstep(0.5, 0.7, T.A.sample(u + 0.3, v + 0.6));
          const spot = sstep(0.74, 0.88, T.B.sample(u * 2 + 0.1, v * 2 + 0.7));
          const base = 0.9 + (mott - 0.5) * 0.16 + (hiF - 0.5) * 0.06 - pore * 0.05;
          const i = (y * S + x) * 4;
          col[i] = 255 * clamp(base * (1 - vein * 0.2) * (1 - spot * 0.14), 0, 1);
          col[i + 1] = 255 * clamp(base * (1 - vein * 0.12) * (1 - spot * 0.17), 0, 1);
          col[i + 2] = 255 * clamp(base * (1 + vein * 0.03) * (1 - spot * 0.22), 0, 1);
          col[i + 3] = 255;
          h[y * S + x] = -pore * 0.55 + wrinkle * 0.3 + vein * 0.45 + (mid - 0.5) * 0.9 + (hiF - 0.5) * 0.35;
        }
      }
      this.texSkin = dataTexture(col, S, S, { srgb: true });
      this.texSkinN = dataTexture(heightToNormal(h, S, S, hi ? 1.3 : 0.8), S, S);
    }
    // ---- hair fibres (RGBA)
    {
      const W = 64, H = 256;
      const col = new Uint8ClampedArray(W * H * 4);
      const r = mulberry32(99);
      const fibres = [];
      for (let i = 0; i < 30; i++) {
        const c = r();
        const x0 = 0.5 + (c - 0.5) * (r() < 0.75 ? 0.66 : 0.98);
        fibres.push({ x0, w: 0.008 + r() * 0.014, ph: r() * TAU, fr: 1 + Math.floor(r() * 3), amp: 0.01 + r() * 0.04, b: 0.01 + r() * r() * 0.16, a: 0.6 + r() * 0.4 });
      }
      for (let y = 0; y < H; y++) {
        const v = y / H;
        for (let x = 0; x < W; x++) {
          const u = x / W;
          let a = 0, c = 0, best = 0;
          for (const f of fibres) {
            const fx = f.x0 + Math.sin(v * TAU * f.fr + f.ph) * f.amp;
            const d = Math.abs(u - fx);
            const k = Math.exp(-(d * d) / (f.w * f.w));
            if (k > 0.02) { a = Math.max(a, k * f.a); if (k > best) { best = k; c = f.b * k; } }
          }
          const edge = sstep(0.0, 0.12, u) * sstep(1.0, 0.88, u);
          const i = (y * W + x) * 4;
          const cc = clamp(0.035 + c * 0.3, 0, 0.17);
          col[i] = 255 * cc; col[i + 1] = 255 * cc * 0.93; col[i + 2] = 255 * cc * 0.88;
          col[i + 3] = 255 * clamp(a * 1.25 * edge, 0, 1);
        }
      }
      this.texHair = dataTexture(col, W, H, { srgb: true });
      this.texHair.wrapS = THREE.ClampToEdgeWrapping;
    }
    // ---- gown tears (alpha) — u around, v from hem (0) to neckline (1)
    {
      const W = 512, H = 128;
      const col = new Uint8ClampedArray(W * H * 4);
      const r = mulberry32(7);
      const tears = [];
      for (let i = 0; i < 9; i++) tears.push({ u: r(), w: 0.004 + r() * 0.01, len: 0.06 + r() * 0.16 });
      const holes = [];
      for (let i = 0; i < 7; i++) holes.push({ u: r(), v: 0.04 + r() * 0.2, rx: 0.004 + r() * 0.01, ry: 0.01 + r() * 0.025 });
      for (let y = 0; y < H; y++) {
        const v = 1 - y / H; // canvas top = v 1
        for (let x = 0; x < W; x++) {
          const u = x / W;
          let a = 1;
          for (const t of tears) {
            let du = Math.abs(u - t.u); du = Math.min(du, 1 - du);
            const ww = t.w * (1 - v / t.len) + 0.0015 * Math.sin(v * 220 + t.u * 40);
            if (v < t.len && du < ww) a = 0;
          }
          for (const hl of holes) {
            let du = Math.abs(u - hl.u); du = Math.min(du, 1 - du);
            const n = 0.6 + 0.4 * vnoise3(u * 300, v * 300, 0, 3);
            if ((du / hl.rx) ** 2 + ((v - hl.v) / hl.ry) ** 2 < n) a = 0;
          }
          // fraying near the bottom edge
          if (v < 0.03 && vnoise3(u * 900, v * 400, 1, 5) > 0.55 + v * 10) a = 0;
          const i = (y * W + x) * 4;
          col[i] = col[i + 1] = col[i + 2] = a * 255; col[i + 3] = 255;
        }
      }
      this.texTear = dataTexture(col, W, H, {});
      this.texTear.wrapT = THREE.ClampToEdgeWrapping;
    }
  }

  // Unique head texture (colour + normal), painted procedurally in head UV space.
  _buildHeadTextures(phiOfRow) {
    const hi = !this.lowQ;
    const W = hi ? 1024 : 512, H = hi ? 512 : 256;
    const col = new Uint8ClampedArray(W * H * 4), hgt = new Float32Array(W * H);
    const T = this.tiles;
    const thetaOfU = new Float32Array(W);
    for (let x = 0; x < W; x++) thetaOfU[x] = this._headUInv((x + 0.5) / W);
    const P = new THREE.Vector3();
    const eyes = [headAnchor(26, 80), headAnchor(-26, 80)];
    const lerp3 = (c, t, k) => { c[0] += (t[0] - c[0]) * k; c[1] += (t[1] - c[1]) * k; c[2] += (t[2] - c[2]) * k; };
    const c = [0, 0, 0];
    const SKIN = [0.31, 0.335, 0.295], SOCKET = [0.03, 0.022, 0.026], BRUISE = [0.26, 0.17, 0.22], LIP = [0.24, 0.16, 0.18];
    const SCALP = [0.04, 0.035, 0.03], DIRT = [0.2, 0.17, 0.14], BLOT = [0.33, 0.32, 0.28], TEAR = [0.03, 0.025, 0.025];
    const CRACK = [0.07, 0.03, 0.035], SLIT = [0.02, 0.004, 0.006], SCAR = [0.09, 0.045, 0.05], NOSE = [0.36, 0.27, 0.27];
    const NOSTRIL = [0.05, 0.03, 0.03], VEIN = [0.22, 0.27, 0.3];
    const noseTip = headAnchor(0, 98), nostrils = [headAnchor(9, 101), headAnchor(-9, 101)];
    const streaks = [];
    const r = mulberry32(4242);
    for (const sx of [1, -1]) for (let k = 0; k < 4; k++) streaks.push({ sx, dx: (r() - 0.5) * 0.016, len: 0.03 + r() * 0.07, w: 0.0012 + r() * 0.002, k: 0.5 + r() * 0.5 });
    for (let y = 0; y < H; y++) {
      const v = 1 - (y + 0.5) / H;
      const phi = (1 - v) * Math.PI;
      for (let x = 0; x < W; x++) {
        const theta = thetaOfU[x];
        headBase(theta, phi, P);
        const u = x / W;
        const mott = T.A.sample(u * 6, v * 3), mid = T.B.sample(u * 4, v * 2), hf = T.C.sample(u * 8, v * 4);
        c[0] = SKIN[0]; c[1] = SKIN[1]; c[2] = SKIN[2];
        const m = 0.86 + (mott - 0.5) * 0.3 + (hf - 0.5) * 0.08;
        c[0] *= m; c[1] *= m * 1.01; c[2] *= m;
        let h = (mid - 0.5) * 0.25 + (hf - 0.5) * 0.2 - sstep(0.66, 0.82, T.C.sample(u * 16 + 0.3, v * 8 + 0.2)) * 0.25;
        // grey-brown blotches
        const blot = sstep(0.62, 0.8, T.B.sample(u * 3 + 0.4, v * 2 + 0.1));
        lerp3(c, BLOT, blot * 0.45);
        // sockets: dark + bruised rim
        for (const e of eyes) {
          const d = Math.sqrt(P.distanceToSquared(e));
          lerp3(c, BRUISE, gauss((d - 0.031) ** 2, 0.012) * 0.6);
          lerp3(c, SOCKET, gauss(d * d, 0.026) * 0.98);
          h += gauss((d - 0.022) ** 2, 0.006) * 0.4;               // orbital rim
          h += Math.sin(d * 900) * gauss((d - 0.03) ** 2, 0.008) * 0.12; // crow's feet rings
        }
        // black tear streaks running from the lower lids
        for (const s of streaks) {
          const e = eyes[s.sx > 0 ? 0 : 1];
          const dy = e.y - 0.012 - P.y;
          if (dy > 0 && dy < s.len && P.z > 0.02) {
            const xs = e.x + s.dx + Math.sin(dy * 90 + s.dx * 300) * 0.0018;
            const k = gauss((P.x - xs) ** 2, s.w) * (1 - dy / s.len) * s.k;
            lerp3(c, TEAR, k * 0.9);
          }
        }
        // lips + cracks + mouth slit
        const dphi = phi - MOUTH_PHI;
        const span = sstep(MOUTH_SPAN + 0.05, MOUTH_SPAN - 0.12, Math.abs(theta));
        const lipBand = gauss(dphi * dphi, 0.055) * span;
        lerp3(c, LIP, lipBand * 0.8);
        const crack = (1 - sstep(0.0, 0.07, Math.abs(T.B.sample(u * 24, v * 2 + 0.5) - 0.5))) * lipBand;
        lerp3(c, CRACK, crack * 0.85);
        h -= crack * 0.8;
        h += Math.sin(theta * 160) * lipBand * 0.08;
        const slit = gauss(dphi * dphi, 0.02) * span;
        lerp3(c, SLIT, slit);
        // scars / cracks continuing from the mouth corners toward the ears
        const beyond = Math.abs(theta) - MOUTH_SPAN;
        if (beyond > -0.05 && beyond < 0.5) {
          const cy = dphi + beyond * beyond * 0.25;
          const k = gauss(cy * cy, 0.006 + beyond * 0.004) * sstep(0.5, 0.05, beyond);
          lerp3(c, SCAR, k * 0.9);
          h -= k * 0.7;
        }
        // nose tip / nostrils
        lerp3(c, NOSE, gauss(P.distanceToSquared(noseTip), 0.012) * 0.35);
        for (const n of nostrils) lerp3(c, NOSTRIL, gauss(P.distanceToSquared(n), 0.0045) * 0.85);
        // temple / forehead veins
        const vm = sstep(0.04, 0.065, Math.abs(P.x)) * sstep(0.03, 0.08, P.y) * sstep(0.17, 0.12, P.y);
        const fv = sstep(0.1, 0.13, P.y) * sstep(0.03, 0.0, Math.abs(P.x) - 0.03) * 0.6;
        const vein = (1 - sstep(0.0, 0.025, Math.abs(T.B.sample(u * 5 + 0.2, v * 3 + 0.7) - 0.5))) * Math.max(vm, fv);
        lerp3(c, VEIN, vein * 0.55);
        h += vein * 0.5;
        // forehead lines
        h += Math.sin(P.y * 520) * sstep(0.12, 0.15, P.y) * sstep(0.18, 0.16, P.y) * sstep(0.05, 0.0, Math.abs(P.x)) * 0.15;
        // grime around the hairline, the mouth and under the chin
        lerp3(c, DIRT, sstep(0.55, 0.85, T.A.sample(u * 3, v * 3 + 0.5)) * 0.35);
        lerp3(c, DIRT, gauss(dphi * dphi, 0.16) * span * sstep(0.3, 0.7, T.B.sample(u * 6, v * 6)) * 0.5);
        // dark scalp under the hair
        const hl = this._hairlinePhi(theta) + (T.B.sample(u * 9 + 0.3, 0.37) - 0.5) * 0.22 + (T.C.sample(u * 30, 0.61) - 0.5) * 0.08;
        lerp3(c, SCALP, sstep(hl + 0.1, hl - 0.05, phi) * (0.75 + 0.25 * sstep(0.4, 0.6, T.C.sample(u * 40, v * 20))));
        const i = (y * W + x) * 4;
        col[i] = 255 * Math.sqrt(clamp(c[0], 0, 1)); col[i + 1] = 255 * Math.sqrt(clamp(c[1], 0, 1)); col[i + 2] = 255 * Math.sqrt(clamp(c[2], 0, 1));
        col[i + 3] = 255;
        hgt[y * W + x] = h;
      }
    }
    this.texHead = dataTexture(col, W, H, { srgb: true, repeat: false });
    this.texHeadN = dataTexture(heightToNormal(hgt, W, H, hi ? 1.35 : 0.8, false), W, H, { repeat: false });
  }

  _hairlinePhi(theta) {
    // front forehead hairline ~42°, above the ears ~84°, nape ~118°
    return THREE.MathUtils.degToRad(42 + 76 * (1 - Math.cos(theta)) * 0.5);
  }
  // head u mapping concentrates texels on the face
  _headU(theta) { const x = theta / Math.PI; return 0.5 + 0.5 * (x + (0.6 * Math.sin(Math.PI * x)) / Math.PI); }
  _headUInv(u) {
    let lo = -Math.PI, hi = Math.PI;
    for (let i = 0; i < 30; i++) { const m = (lo + hi) * 0.5; if (this._headU(m) < u) lo = m; else hi = m; }
    return (lo + hi) * 0.5;
  }

  // ---------------------------------------------------------------------------------------- materials
  _buildMaterials() {
    const skinParams = {
      color: 0xffffff, vertexColors: true, roughness: 0.58, metalness: 0, specularIntensity: 0.7,
      clearcoat: 0.12, clearcoatRoughness: 0.45,
    };
    this.matSkin = new THREE.MeshPhysicalMaterial({ ...skinParams, map: this.texSkin, normalMap: this.texSkinN, normalScale: new THREE.Vector2(0.6, 0.6) });
    this.matSkin.name = 'gardienne_skin';
    this.matHead = new THREE.MeshPhysicalMaterial({ ...skinParams, roughness: 0.5, normalScale: new THREE.Vector2(0.9, 0.9) });
    this.matHead.name = 'gardienne_face';
    this.matHair = new THREE.MeshPhysicalMaterial({
      color: 0xffffff, vertexColors: true, map: this.texHair, alphaTest: 0.42, side: THREE.DoubleSide,
      roughness: 0.6, metalness: 0, specularIntensity: 0.08, clearcoat: 0.05, clearcoatRoughness: 0.4,
    });
    this.matHair.name = 'gardienne_hair';
    this.matTeeth = new THREE.MeshPhysicalMaterial({ color: 0xffffff, vertexColors: true, roughness: 0.32, clearcoat: 0.7, clearcoatRoughness: 0.15 });
    this.matEye = new THREE.MeshPhysicalMaterial({ color: 0x080706, roughness: 0.12, clearcoat: 1, clearcoatRoughness: 0.04, sheen: 0.5, sheenColor: new THREE.Color(0.3, 0.32, 0.3) });
    this.matGlint = new THREE.MeshStandardMaterial({ color: 0x000000, emissive: 0xfff2dc, emissiveIntensity: 0.6, roughness: 1 });
    this.matMouth = new THREE.MeshStandardMaterial({ color: 0x080203, roughness: 0.6 });

    // Nightgown: CC0 woven cotton (fabric032) from the asset pipeline, upgraded to a physical cloth material.
    let base = null;
    try { base = this.game?.assets?.pbr?.('fabric032', [7, 5]); } catch (e) { base = null; }
    this.matGown = new THREE.MeshPhysicalMaterial({
      color: 0xffffff, vertexColors: true, side: THREE.DoubleSide,
      map: base?.map ?? null, normalMap: base?.normalMap ?? null, roughnessMap: base?.roughnessMap ?? null,
      aoMap: base?.aoMap ?? null, aoMapIntensity: 0.7, normalScale: new THREE.Vector2(0.9, 0.9),
      roughness: 1, metalness: 0, alphaMap: this.texTear, alphaTest: 0.5,
      sheen: 0.7, sheenColor: new THREE.Color(0.8, 0.78, 0.7), sheenRoughness: 0.75,
    });
    this.matGown.name = 'gardienne_gown';
    base?.dispose?.();
  }

  // ---------------------------------------------------------------------------------------- body skin
  _buildBody() {
    const B0 = new GeoBuilder();
    // phones: coarser tubes (the silhouette survives, the vertex count drops ~45%)
    const sk = this.lowQ ? 0.68 : 1, st = this.lowQ ? 1.45 : 1;
    const tube = (keys, o) => addTube(B0, keys, { ...o, segs: Math.max(6, Math.round((o.segs ?? 16) * sk)), step: (o.step ?? 0.012) * st });
    const bi = (n) => this.bi(n);
    const R = this.restW;
    const SKIN = [0.3, 0.33, 0.29];
    const mix = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
    const skinNoise = (P) => {
      const n = fbm3(P.x * 18, P.y * 18, P.z * 18, 3, 5);
      return mix(SKIN, [0.27, 0.27, 0.25], sstep(0.55, 0.75, n) * 0.6);
    };
    const blend = (y, y0, y1, a, b) => { const t = sstep(y0, y1, y); return [[bi(a), 1 - t], [bi(b), t]]; };
    const ridge = (P, a, b, amp, s) => {
      // distance from P to segment ab
      _tv1.subVectors(b, a); _tv2.subVectors(P, a);
      const t = clamp(_tv2.dot(_tv1) / _tv1.lengthSq(), 0, 1);
      _tv3.copy(a).addScaledVector(_tv1, t);
      return amp * gauss(P.distanceToSquared(_tv3), s);
    };

    // ---- torso + neck (one tube, pelvis -> skull base)
    const clavA = { L: new THREE.Vector3(0.018, 1.592, 0.05), R: new THREE.Vector3(-0.018, 1.592, 0.05) };
    const clavB = { L: new THREE.Vector3(0.15, 1.605, 0.0), R: new THREE.Vector3(-0.15, 1.605, 0.0) };
    const tendA = { L: new THREE.Vector3(0.042, 1.79, -0.008), R: new THREE.Vector3(-0.042, 1.79, -0.008) };
    const tendB = { L: new THREE.Vector3(0.013, 1.62, 0.036), R: new THREE.Vector3(-0.013, 1.62, 0.036) };
    tube([
      { p: [0, 0.94, 0.0], rx: 0.115, rz: 0.088 },
      { p: [0, 1.06, 0.0], rx: 0.128, rz: 0.094 },
      { p: [0, 1.16, 0.0], rx: 0.112, rz: 0.084 },
      { p: [0, 1.24, 0.0], rx: 0.094, rz: 0.074 },
      { p: [0, 1.32, 0.0], rx: 0.104, rz: 0.081 },
      { p: [0, 1.42, 0.0], rx: 0.116, rz: 0.088 },
      { p: [0, 1.5, -0.005], rx: 0.122, rz: 0.086 },
      { p: [0, 1.555, -0.01], rx: 0.15, rz: 0.075 },
      { p: [0, 1.583, -0.014], rx: 0.158, rz: 0.066 },
      { p: [0, 1.607, -0.017], rx: 0.134, rz: 0.058 },
      { p: [0, 1.632, -0.018], rx: 0.094, rz: 0.052 },
      { p: [0, 1.652, -0.018], rx: 0.058, rz: 0.047 },
      { p: [0, 1.67, -0.018], rx: 0.044, rz: 0.042 },
      { p: [0, 1.71, -0.016], rx: 0.039, rz: 0.04 },
      { p: [0, 1.765, -0.014], rx: 0.036, rz: 0.038 },
      { p: [0, 1.83, -0.022], rx: 0.03, rz: 0.034 },
    ], {
      segs: 40, step: 0.008, capStart: true, capEnd: true, tile: 0.12,
      weights: (c) => {
        const y = c.y;
        if (y < 1.12) return [[bi('hips'), 1]];
        if (y < 1.2) return blend(y, 1.12, 1.2, 'hips', 'spine1');
        if (y < 1.26) return [[bi('spine1'), 1]];
        if (y < 1.34) return blend(y, 1.26, 1.34, 'spine1', 'spine2');
        if (y < 1.4) return [[bi('spine2'), 1]];
        if (y < 1.47) return blend(y, 1.4, 1.47, 'spine2', 'chest');
        if (y < 1.625) return [[bi('chest'), 1]];
        if (y < 1.665) return blend(y, 1.625, 1.665, 'chest', 'neck');
        if (y < 1.76) return [[bi('neck'), 1]];
        if (y < 1.81) return blend(y, 1.76, 1.81, 'neck', 'head');
        return [[bi('head'), 1]];
      },
      weightsP: (P, s, w) => {
        // shoulders follow the clavicles
        const k = sstep(0.06, 0.15, Math.abs(P.x)) * sstep(1.5, 1.56, P.y) * sstep(1.66, 1.62, P.y) * 0.85;
        if (k <= 0) return w;
        const out = w.map(([i, ww]) => [i, ww * (1 - k)]);
        out.push([bi(P.x > 0 ? 'clavL' : 'clavR'), k]);
        return out;
      },
      disp: (P, N) => {
        let d = (fbm3(P.x * 30, P.y * 30, P.z * 30, 2, 9) - 0.5) * 0.003;
        for (const S of ['L', 'R']) {
          d += ridge(P, clavA[S], clavB[S], 0.0048, 0.0065);
          _tv3.copy(clavA[S]).add(clavB[S]).multiplyScalar(0.5); _tv3.y += 0.018; _tv3.z -= 0.005;
          d -= 0.0055 * gauss(P.distanceToSquared(_tv3), 0.016);
          d += ridge(P, tendA[S], tendB[S], 0.0042, 0.0055);
        }
        d -= 0.006 * gauss(P.distanceToSquared(_tv3.set(0, 1.598, 0.048)), 0.011);   // sternal notch
        if (P.z > 0.0 && P.y > 1.36 && P.y < 1.56) {                                   // upper ribs
          const yy = P.y + 0.6 * P.x * P.x;
          d += 0.0026 * Math.max(0, Math.sin(((yy - 1.36) / 0.027) * TAU)) * sstep(0.015, 0.035, Math.abs(P.x)) * sstep(1.56, 1.52, P.y);
        }
        if (P.z < -0.02 && P.y > 1.52) {                                               // vertebrae
          const k = Math.max(0, Math.sin(((P.y - 1.52) / 0.03) * TAU));
          d += 0.004 * k * gauss(P.x * P.x, 0.012);
        }
        return d;
      },
      color: (P) => {
        let c = skinNoise(P);
        // bruised neck (finger marks)
        const nb = sstep(1.68, 1.72, P.y) * sstep(1.78, 1.74, P.y) * sstep(0.45, 0.7, fbm3(P.x * 60, P.y * 60, P.z * 60, 2, 3));
        c = mix(c, [0.32, 0.26, 0.3], nb * 0.6);
        return c;
      },
    });

    // ---- arms (shoulder -> knuckles: one tube per arm, palm flattens at the end)
    for (const [S, sx] of [['L', 1], ['R', -1]]) {
      const x = 0.165 * sx, z = -0.02;
      const elbow = new THREE.Vector3(x, 1.232, z - 0.022);
      tube([
        { p: [x, 1.612, z], rx: 0.033, rz: 0.035 },
        { p: [x, 1.578, z], rx: 0.037, rz: 0.039 },
        { p: [x, 1.5, z], rx: 0.032, rz: 0.033 },
        { p: [x, 1.4, z], rx: 0.027, rz: 0.029 },
        { p: [x, 1.3, z], rx: 0.025, rz: 0.026 },
        { p: [x, 1.235, z - 0.002], rx: 0.028, rz: 0.03 },
        { p: [x, 1.18, z], rx: 0.027, rz: 0.029 },
        { p: [x, 1.1, z], rx: 0.027, rz: 0.027 },
        { p: [x, 1.0, z], rx: 0.021, rz: 0.023 },
        { p: [x, 0.925, z], rx: 0.0155, rz: 0.021 },
        { p: [x, 0.898, z], rx: 0.015, rz: 0.024 },
        { p: [x, 0.862, z + 0.002], rx: 0.0125, rz: 0.034 },
        { p: [x, 0.82, z + 0.002], rx: 0.0115, rz: 0.04 },
        { p: [x, 0.798, z + 0.002], rx: 0.0105, rz: 0.042 },
      ], {
        segs: 22, step: 0.009, capStart: true, capEnd: true, capLen: 0.5, tile: 0.1,
        weights: (c) => {
          const y = c.y;
          if (y > 1.28) return [[bi('arm' + S), 1]];
          if (y > 1.18) return blend(-y, -1.28, -1.18, 'arm' + S, 'fore' + S);
          if (y > 0.93) return [[bi('fore' + S), 1]];
          if (y > 0.875) return blend(-y, -0.93, -0.875, 'fore' + S, 'hand' + S);
          return [[bi('hand' + S), 1]];
        },
        disp: (P) => {
          let d = (fbm3(P.x * 40, P.y * 40, P.z * 40, 2, 13) - 0.5) * 0.0025;
          d += 0.006 * gauss(P.distanceToSquared(elbow), 0.012);                                   // elbow knob
          d += 0.003 * gauss(P.distanceToSquared(_tv3.set(x + 0.012 * sx, 0.905, z - 0.012)), 0.007); // ulna head
          d += 0.003 * gauss(P.distanceToSquared(_tv3.set(x + 0.018 * sx, 1.59, z + 0.012)), 0.014);  // acromion
          // metacarpal ridges on the back of the hand
          if (P.y < 0.88 && (P.x - x) * sx > 0.004) d += 0.0012 * Math.max(0, Math.sin((P.z - z + 0.04) * 120));
          return d;
        },
        color: (P) => {
          let c = skinNoise(P);
          c = mix(c, [0.36, 0.3, 0.33], gauss(P.distanceToSquared(elbow), 0.03) * 0.5);
          c = mix(c, [0.3, 0.27, 0.22], sstep(0.9, 0.8, P.y) * 0.35);  // dirty hands
          return c;
        },
      });
      // fingers
      for (const [fn, dz, ry, L] of FINGERS) {
        const fz = -0.02 + dz;
        const y0 = ry + 0.01, j1 = ry - L * PHAL[0], j2 = j1 - L * PHAL[1], tip = j2 - L * PHAL[2];
        const r0 = fn === 'pinky' ? 0.0068 : 0.0078;
        tube([
          { p: [x, y0, fz], rx: r0 * 1.05, rz: r0 * 1.1 },
          { p: [x, ry - 0.004, fz], rx: r0 * 1.12, rz: r0 * 1.12 },
          { p: [x, (ry + j1) / 2, fz], rx: r0 * 0.88, rz: r0 * 0.9 },
          { p: [x, j1, fz], rx: r0 * 1.04, rz: r0 * 1.05 },
          { p: [x, (j1 + j2) / 2, fz], rx: r0 * 0.82, rz: r0 * 0.84 },
          { p: [x, j2, fz], rx: r0 * 0.9, rz: r0 * 0.92 },
          { p: [x, (j2 + tip) / 2, fz], rx: r0 * 0.72, rz: r0 * 0.78 },
          { p: [x + 0.0012 * sx, tip, fz], rx: r0 * 0.5, rz: r0 * 0.62 },
        ], {
          segs: 10, step: 0.006, capStart: false, capEnd: true, capN: 3, capLen: 1.1, tile: 0.05,
          weights: (c) => {
            const y = c.y;
            const h = [bi('hand' + S), bi(`${fn}0${S}`), bi(`${fn}1${S}`), bi(`${fn}2${S}`)];
            if (y > ry + 0.004) return [[h[0], 1]];
            if (y > ry - 0.006) { const t = sstep(ry + 0.004, ry - 0.006, y); return [[h[0], 1 - t], [h[1], t]]; }
            if (y > j1 + 0.004) return [[h[1], 1]];
            if (y > j1 - 0.004) { const t = sstep(j1 + 0.004, j1 - 0.004, y); return [[h[1], 1 - t], [h[2], t]]; }
            if (y > j2 + 0.003) return [[h[2], 1]];
            if (y > j2 - 0.003) { const t = sstep(j2 + 0.003, j2 - 0.003, y); return [[h[2], 1 - t], [h[3], t]]; }
            return [[h[3], 1]];
          },
          color: (P) => {
            let c = skinNoise(P);
            c = mix(c, [0.36, 0.3, 0.3], (gauss((P.y - j1) ** 2, 0.004) + gauss((P.y - j2) ** 2, 0.003)) * 0.5);
            const dist = sstep(j2, tip, P.y);
            c = mix(c, [0.16, 0.13, 0.1], dist * 0.7);                         // dirt in the fingertips
            if ((P.x - x) * sx > 0.002 && P.y < (j2 + tip) / 2 + 0.004) c = [0.2, 0.17, 0.11]; // long dirty nails
            return c;
          },
        });
      }
      // thumb
      {
        const t0 = this.restW[`thumb0${S}`], t1 = this.restW[`thumb1${S}`], t2 = this.restW[`thumb2${S}`];
        const dir = _tv1.subVectors(t2, t1).normalize().clone();
        const tip = t2.clone().addScaledVector(dir, 0.026);
        const st = t0.clone().addScaledVector(dir, -0.012);
        tube([
          { p: st.toArray(), rx: 0.0105, rz: 0.011 },
          { p: t1.toArray(), rx: 0.0088, rz: 0.009 },
          { p: t2.toArray(), rx: 0.0082, rz: 0.0085 },
          { p: tip.toArray(), rx: 0.0055, rz: 0.006 },
        ], {
          segs: 10, step: 0.006, capStart: true, capEnd: true, capN: 3, tile: 0.05, front: [sx, 0, 0],
          weights: (c) => {
            const d0 = c.distanceTo(t1), d1 = c.distanceTo(t2);
            if (c.distanceTo(t0) < 0.012) return [[bi('hand' + S), 0.6], [bi(`thumb0${S}`), 0.4]];
            if (d0 < d1 && c.distanceTo(st) < t0.distanceTo(t1) + 0.012) return [[bi(`thumb0${S}`), 1]];
            if (d1 > 0.004 && c.distanceTo(st) < st.distanceTo(t2)) return [[bi(`thumb1${S}`), 1]];
            return [[bi(`thumb2${S}`), 1]];
          },
          color: (P) => mix(skinNoise(P), [0.18, 0.15, 0.12], sstep(t2.distanceTo(tip) * 0.2, 0, P.distanceTo(tip)) * 0.8),
        });
      }
    }

    // ---- legs (hip -> ankle) + feet + toes
    for (const [S, sx] of [['L', 1], ['R', -1]]) {
      const x = 0.085 * sx;
      const knee = new THREE.Vector3(x, 0.555, 0.04);
      tube([
        { p: [x, 1.1, 0], rx: 0.062, rz: 0.066 },
        { p: [x, 0.96, 0.004], rx: 0.054, rz: 0.058 },
        { p: [x, 0.76, 0.006], rx: 0.044, rz: 0.046 },
        { p: [x, 0.62, 0.006], rx: 0.039, rz: 0.04 },
        { p: [x, 0.555, 0.006], rx: 0.042, rz: 0.044 },
        { p: [x, 0.5, 0.0], rx: 0.036, rz: 0.039 },
        { p: [x, 0.4, -0.008], rx: 0.033, rz: 0.038 },
        { p: [x, 0.26, -0.004], rx: 0.027, rz: 0.03 },
        { p: [x, 0.12, 0.0], rx: 0.021, rz: 0.023 },
        { p: [x, 0.075, 0.0], rx: 0.023, rz: 0.025 },
        { p: [x, 0.045, -0.006], rx: 0.024, rz: 0.03 },
      ], {
        segs: 24, step: 0.012, capStart: true, capEnd: true, capLen: 0.6, tile: 0.12,
        weights: (c) => {
          const y = c.y;
          if (y > 0.62) return [[bi('thigh' + S), 1]];
          if (y > 0.5) return blend(-y, -0.62, -0.5, 'thigh' + S, 'shin' + S);
          if (y > 0.1) return [[bi('shin' + S), 1]];
          if (y > 0.06) return blend(-y, -0.1, -0.06, 'shin' + S, 'foot' + S);
          return [[bi('foot' + S), 1]];
        },
        disp: (P) => {
          let d = (fbm3(P.x * 35, P.y * 35, P.z * 35, 2, 17) - 0.5) * 0.003;
          d += 0.007 * gauss(P.distanceToSquared(knee), 0.016);                                     // kneecap
          for (const m of [1, -1]) d += 0.0035 * gauss(P.distanceToSquared(_tv3.set(x + 0.021 * m, 0.075, -0.004)), 0.008); // malleoli
          if (P.z > 0.015 && P.y < 0.5 && P.y > 0.12) d += 0.0025 * gauss((P.x - x) ** 2, 0.006);   // shin bone ridge
          return d;
        },
        color: (P) => {
          let c = skinNoise(P);
          c = mix(c, [0.34, 0.28, 0.31], gauss(P.distanceToSquared(knee), 0.035) * 0.6);
          const mud = sstep(0.3, 0.05, P.y + (fbm3(P.x * 30, P.y * 8, P.z * 30, 2, 41) - 0.5) * 0.14);
          c = mix(c, [0.31, 0.24, 0.27], sstep(0.6, 0.75, fbm3(P.x * 22, P.y * 9, P.z * 22, 2, 43)) * 0.45); // bruises
          return mix(c, [0.17, 0.14, 0.11], mud * 0.7);
        },
      });
      // foot
      tube([
        { p: [x, 0.034, -0.062], rx: 0.022, rz: 0.028 },
        { p: [x, 0.044, -0.025], rx: 0.027, rz: 0.038 },
        { p: [x - 0.004 * sx, 0.042, 0.04], rx: 0.031, rz: 0.03 },
        { p: [x - 0.006 * sx, 0.024, 0.122], rx: 0.037, rz: 0.019 },
        { p: [x - 0.006 * sx, 0.016, 0.16], rx: 0.036, rz: 0.014 },
      ], {
        segs: 20, step: 0.01, capStart: true, capEnd: true, capLen: 0.5, tile: 0.1, front: [0, 1, 0],
        weights: (c) => (c.z < 0.1 ? [[bi('foot' + S), 1]] : c.z < 0.14 ? blend(c.z, 0.1, 0.14, 'foot' + S, 'toe' + S) : [[bi('toe' + S), 1]]),
        disp: (P) => (fbm3(P.x * 50, P.y * 50, P.z * 50, 2, 19) - 0.5) * 0.003 + 0.0025 * Math.max(0, Math.sin((P.x * sx - 0.05) * 160)) * sstep(0.02, 0.04, P.y) * sstep(0.02, 0.1, P.z),
        color: (P) => {
          const sole = sstep(0.024, 0.008, P.y + (fbm3(P.x * 60, P.z * 60, 1, 2, 47) - 0.5) * 0.01);
          let c = mix(skinNoise(P), [0.17, 0.14, 0.11], 0.3 + 0.4 * fbm3(P.x * 40, P.y * 40, P.z * 40, 2, 43));
          return mix(c, [0.05, 0.04, 0.03], sole);
        },
      });
      // toes (long, knobbly)
      const toes = [[-0.022, 0.066, 0.0098], [-0.008, 0.06, 0.0072], [0.005, 0.054, 0.0068], [0.016, 0.047, 0.0064], [0.026, 0.038, 0.006]];
      for (const [ox, len, r] of toes) {
        const tx = x + ox * sx;
        const z0 = 0.14 + Math.abs(ox) * 0.15;
        tube([
          { p: [tx, 0.016, z0 - 0.02], rx: r, rz: r * 0.9 },
          { p: [tx, 0.013, z0 + len * 0.4], rx: r * 0.92, rz: r * 0.82 },
          { p: [tx, 0.011, z0 + len * 0.7], rx: r * 1.02, rz: r * 0.86 },
          { p: [tx, 0.008, z0 + len], rx: r * 0.75, rz: r * 0.62 },
        ], {
          segs: 9, step: 0.008, capStart: false, capEnd: true, capN: 3, tile: 0.05, front: [0, 1, 0],
          weights: () => [[bi('toe' + S), 1]],
          color: (P) => (P.y > 0.013 && P.z > z0 + len * 0.75 ? [0.14, 0.12, 0.07] : mix([0.2, 0.17, 0.14], [0.05, 0.04, 0.03], sstep(0.012, 0.004, P.y))),
        });
      }
    }
    this.geoBody = B0.build();
  }

  // ---------------------------------------------------------------------------------------- head
  _buildHead() {
    const NS = this.lowQ ? 72 : 96, NR = this.lowQ ? 60 : 78;
    // ring distribution: dense around the mouth slit, the eyes and the nose
    const dens = (p) => 1 + 3.2 * gauss((p - MOUTH_PHI) ** 2, 0.08) + 1.3 * gauss((p - EYE_PHI) ** 2, 0.2) + 0.5 * gauss((p - 1.72) ** 2, 0.25);
    const STEPS = 2000, cdf = new Float32Array(STEPS + 1);
    for (let i = 1; i <= STEPS; i++) cdf[i] = cdf[i - 1] + dens(((i - 0.5) / STEPS) * Math.PI);
    const phis = [];
    for (let i = 0; i <= NR; i++) {
      const target = (i / NR) * cdf[STEPS];
      let k = 0; while (k < STEPS && cdf[k + 1] < target) k++;
      const t = (target - cdf[k]) / Math.max(1e-9, cdf[k + 1] - cdf[k]);
      phis.push(((k + t) / STEPS) * Math.PI);
    }
    let m = 0;
    for (let i = 0; i <= NR; i++) if (Math.abs(phis[i] - MOUTH_PHI) < Math.abs(phis[m] - MOUTH_PHI)) m = i;
    phis[m] = MOUTH_PHI;
    this.mouthRing = m;

    const bumps = headBumps();
    const eyeA = [headAnchor(26, 80), headAnchor(-26, 80)];
    const B = new GeoBuilder();
    const H = this.restW.head;
    const iHead = this.bi('head'), iJaw = this.bi('jaw'), iMouth = this.bi('mouth'), iLipU = this.bi('lipU');
    const P = new THREE.Vector3(), N = new THREE.Vector3();
    const grid = [];
    for (let i = 0; i <= NR; i++) {
      const phi = phis[i];
      const row = [];
      for (let j = 0; j <= NS; j++) {
        const theta = -Math.PI + (j / NS) * TAU;
        headBase(theta, phi, P);
        N.copy(P).sub(HEAD_C).divide(HEAD_R).divide(HEAD_R).normalize();
        let d = 0;
        for (const [a, amp, s] of bumps) d += amp * gauss(P.distanceToSquared(a), s);
        // lips
        const span = sstep(MOUTH_SPAN + 0.02, MOUTH_SPAN - 0.1, Math.abs(theta));
        const di = i - m;
        if (di < 0 && di >= -5) d += 0.0017 * span * Math.sin(((di + 5.5) / 5.5) * Math.PI);
        if (di > 0 && di <= 6) d += 0.0022 * span * Math.sin(((6.5 - di) / 6.5) * Math.PI);
        if (di === 0) d -= 0.0018 * span;
        d += (fbm3(P.x * 60, P.y * 60, P.z * 60, 2, 71) - 0.5) * 0.0016;
        P.addScaledVector(N, d);
        // grin: mouth corners pulled up
        const near = gauss(di * di, 7);
        P.y -= 0.0022 * (Math.abs(theta) / MOUTH_SPAN) ** 2 * near * sstep(MOUTH_SPAN + 0.5, MOUTH_SPAN, Math.abs(theta));
        // weights
        let w;
        const aTh = Math.abs(theta);
        if (di < 0) {
          // upper lip centre follows the snarl bone; the mouth corners are dragged down with the jaw
          const up = -di;
          const lw = up <= 4 ? sstep(MOUTH_SPAN - 0.02, MOUTH_SPAN - 0.42, aTh) * (1 - (up - 1) / 4) : 0;
          const cj = up <= 3 ? sstep(MOUTH_SPAN - 0.42, MOUTH_SPAN - 0.08, aTh) * sstep(MOUTH_SPAN + 0.42, MOUTH_SPAN + 0.02, aTh) * (1 - (up - 1) / 3) * 0.42 : 0;
          w = [[iHead, Math.max(0, 1 - lw - cj)], [iLipU, lw], [iJaw, cj]];
        }
        else if (di === 0) {
          const k = sstep(MOUTH_SPAN, MOUTH_SPAN - 0.12, aTh);
          w = [[iMouth, k], [iHead, (1 - k) * 0.55], [iJaw, (1 - k) * 0.45 * sstep(MOUTH_SPAN + 0.6, MOUTH_SPAN, aTh)]];
        } else {
          const jw = sstep(MOUTH_SPAN + 0.75, MOUTH_SPAN - 0.05, aTh) * (P.z > -0.03 ? 1 : sstep(-0.06, -0.03, P.z));
          w = [[iJaw, jw], [iHead, 1 - jw]];
        }
        // AO-ish vertex colour: sockets, slit, nostrils
        let ao = 1;
        for (const e of eyeA) ao -= 0.7 * gauss(P.distanceToSquared(e), 0.016);
        if (di === 0) ao *= lerp(1, 0.03, span);
        else if (Math.abs(di) === 1) ao *= lerp(1, 0.3, span);
        else if (Math.abs(di) === 2) ao *= lerp(1, 0.8, span);
        const u = this._headU(theta), v = 1 - phi / Math.PI;
        const idx = B.vert(P.x + H.x, P.y + H.y, P.z + H.z, u, v, [ao, ao, ao], w);
        row.push(idx);
      }
      grid.push(row);
      B.seams.push([row[0], row[NS]]);
      if (i === 0 || i === NR) B.poles.push(row.slice());
    }
    for (let i = 0; i < NR; i++) for (let j = 0; j < NS; j++) {
      const a = grid[i][j], b = grid[i][j + 1], c = grid[i + 1][j], d = grid[i + 1][j + 1];
      B.tri(a, c, b); B.tri(b, c, d);
    }
    this.geoHead = B.build();
    this._headGrid = grid;
    this._headNS = NS;
    this._buildHeadTextures(phis);
    this.matHead.map = this.texHead;
    this.matHead.normalMap = this.texHeadN;
    this.matHead.needsUpdate = true;
  }

  _headVertex(i, j, out) {
    const idx = this._headGrid[i][j];
    return out.fromBufferAttribute(this.geoHead.attributes.position, idx);
  }

  // ---------------------------------------------------------------------------------------- teeth
  _buildTeeth() {
    const B = new GeoBuilder();
    const r = mulberry32(555);
    const NS = this._headNS, m = this.mouthRing;
    const iHead = this.bi('head'), iJaw = this.bi('jaw');
    const P = new THREE.Vector3(), Q = new THREE.Vector3(), C = new THREE.Vector3();
    const headW = this.restW.head;
    C.set(0, HEAD_C.y, 0).add(headW);
    const rows = [{ ring: m - 1, dir: -1, bone: iHead, n: 17 }, { ring: m + 1, dir: 1, bone: iJaw, n: 15 }];
    for (const row of rows) {
      for (let k = 0; k < row.n; k++) {
        if (r() < 0.16) continue; // missing teeth
        const th = (k / (row.n - 1) - 0.5) * 2 * (MOUTH_SPAN - 0.14) + (r() - 0.5) * 0.04;
        const j = Math.round(((th + Math.PI) / TAU) * NS);
        this._headVertex(row.ring, j, P);
        // inward (toward the head axis) a little
        Q.set(P.x - C.x, 0, P.z - C.z).normalize();
        P.addScaledVector(Q, -0.0075);
        P.y += row.dir * 0.0015;
        const len = (0.006 + r() * 0.006) * (r() < 0.22 ? 0.5 : 1);
        const wid = 0.0026 + r() * 0.0018;
        const tilt = (r() - 0.5) * 0.5;
        const tipP = P.clone().add(new THREE.Vector3(Math.sin(tilt) * len * 0.3, row.dir * len, (r() - 0.5) * 0.002));
        const base = P.clone().add(new THREE.Vector3(0, -row.dir * 0.004, 0));
        const yel = 0.55 + r() * 0.3, br = r() < 0.12 ? 0.45 : 1;
        addTube(B, [
          { p: base.toArray(), rx: wid, rz: wid * 0.7 },
          { p: P.toArray(), rx: wid * 1.05, rz: wid * 0.75 },
          { p: P.clone().lerp(tipP, 0.6).toArray(), rx: wid * 0.95, rz: wid * 0.6 },
          { p: tipP.toArray(), rx: wid * (r() < 0.2 ? 0.4 : 0.85), rz: wid * 0.55 },
        ], {
          segs: 7, rings: 4, capStart: false, capEnd: true, capN: 2, tile: 0.02, front: [Q.x, 0, Q.z],
          weights: () => [[row.bone, 1]],
          color: (V) => {
            const t = clamp(Math.abs(V.y - base.y) / len, 0, 1);
            const gum = sstep(0.3, 0.0, t);
            const tip = sstep(0.5, 1, t);
            const rot = sstep(0.0, 0.45, t) * (1 - sstep(0.45, 0.9, t)) * 0.35; // brown decay band near the gum line
            return [lerp(0.46 * yel * br, 0.12, gum) * (1 - tip * 0.2 - rot), lerp(0.37 * yel * br, 0.035, gum) * (1 - tip * 0.25 - rot * 1.2), lerp(0.2 * yel * br, 0.03, gum) * (1 - tip * 0.35 - rot * 1.5)];
          },
        });
      }
    }
    this.geoTeeth = B.build();
  }

  // ---------------------------------------------------------------------------------------- eyes
  _buildEyes() {
    this.eyes = [];
    this.glints = [];
    const NS = this._headNS;
    const head = this.b.head, hw = this.restW.head;
    const eyeGeo = new THREE.SphereGeometry(0.0118, 24, 16);
    {
      // milky, bloodshot eyeball with a pale iris and a pinpoint pupil (front of the sphere = u 0.25, v 0.5)
      const W = 128, H = 64, col = new Uint8ClampedArray(W * H * 4);
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const du = (x + 0.5) / W - 0.25, dv = (y + 0.5) / H - 0.5;
        const ang = Math.hypot(du * TAU, dv * Math.PI);           // angular distance from the front
        let r = 0.3, g = 0.27, b = 0.2;                            // dirty yellow sclera
        const vein = (1 - sstep(0.0, 0.08, Math.abs(vnoise3(x * 0.22, y * 0.22, 3, 61) - 0.5))) * sstep(0.5, 1.1, ang);
        r = lerp(r, 0.32, vein * 0.8); g = lerp(g, 0.05, vein * 0.8); b = lerp(b, 0.04, vein * 0.8);
        const iris = sstep(0.5, 0.44, ang);
        const ir = 0.36 + 0.08 * vnoise3(Math.atan2(dv, du) * 9, ang * 30, 1, 63);
        r = lerp(r, ir * 0.92, iris); g = lerp(g, ir * 0.95, iris); b = lerp(b, ir, iris);
        const limbus = gauss((ang - 0.47) ** 2, 0.03);
        r *= 1 - limbus * 0.6; g *= 1 - limbus * 0.6; b *= 1 - limbus * 0.6;
        const pupil = sstep(0.1, 0.07, ang);
        r = lerp(r, 0.005, pupil); g = lerp(g, 0.005, pupil); b = lerp(b, 0.005, pupil);
        const i = (y * W + x) * 4;
        col[i] = 255 * Math.sqrt(r); col[i + 1] = 255 * Math.sqrt(g); col[i + 2] = 255 * Math.sqrt(b); col[i + 3] = 255;
      }
      this.texEye = dataTexture(col, W, H, { srgb: true, repeat: false });
      this.matEye.map = this.texEye;
      this.matEye.color.set(0xffffff);
      this.matEye.needsUpdate = true;
    }
    const glintGeo = new THREE.SphereGeometry(0.0013, 8, 6);
    const P = new THREE.Vector3();
    for (const sx of [1, -1]) {
      // socket floor: the front head vertex nearest (in x/y) to the socket anchor
      const anchor = headAnchor(26 * sx, 80);
      const best = new THREE.Vector3();
      let bd = Infinity;
      for (let i = 0; i < this._headGrid.length; i++) for (let j = 0; j <= NS; j++) {
        this._headVertex(i, j, P).sub(hw);
        if (P.z < 0.02) continue;
        const d = (P.x - anchor.x) ** 2 + (P.y - anchor.y) ** 2;
        if (d < bd) { bd = d; best.copy(P); }
      }
      const center = best.clone();
      center.z -= 0.0058;
      const eye = new THREE.Mesh(eyeGeo, this.matEye);
      eye.name = 'eye';
      eye.position.copy(center); // head-local
      eye.castShadow = false; eye.receiveShadow = true;
      head.add(eye);
      const glint = new THREE.Mesh(glintGeo, this.matGlint);
      glint.position.set(center.x - 0.0018 * sx, center.y + 0.0014, center.z + 0.0108);
      glint.castShadow = false;
      head.add(glint);
      this.eyes.push(eye); this.glints.push(glint);
    }
  }

  // ---------------------------------------------------------------------------------------- gown
  _buildGown() {
    const B = new GeoBuilder();
    const bi = (n) => this.bi(n);
    const TOP = 1.505, HEM = 0.36;
    const r = mulberry32(31);
    const tears = [];
    for (let i = 0; i < 7; i++) tears.push({ a: r() * TAU, w: 0.04 + r() * 0.08, d: 0.03 + r() * 0.07 });
    const hemShift = (a) => {
      let s = (vnoise3(Math.cos(a) * 3 + 5, Math.sin(a) * 3 + 5, 0.5, 77) - 0.5) * 0.07 + (vnoise3(Math.cos(a) * 9, Math.sin(a) * 9, 2, 79) - 0.5) * 0.025;
      for (const t of tears) { let da = Math.abs(a - t.a); da = Math.min(da, TAU - da); s += t.d * Math.max(0, 1 - da / t.w); }
      return s;
    };
    const foldPhase = [r() * TAU, r() * TAU, r() * TAU];
    const keys = [
      { p: [0, TOP, 0.0], rx: 0.139, rz: 0.104 },
      { p: [0, 1.45, 0.0], rx: 0.136, rz: 0.104 },
      { p: [0, 1.38, 0.002], rx: 0.13, rz: 0.1 },
      { p: [0, 1.3, 0.004], rx: 0.131, rz: 0.1 },
      { p: [0, 1.2, 0.004], rx: 0.141, rz: 0.105 },
      { p: [0, 1.1, 0.004], rx: 0.153, rz: 0.114 },
      { p: [0, 0.95, 0.008], rx: 0.163, rz: 0.122 },
      { p: [0, 0.8, 0.012], rx: 0.172, rz: 0.13 },
      { p: [0, 0.6, 0.014], rx: 0.185, rz: 0.142 },
      { p: [0, 0.42, 0.014], rx: 0.196, rz: 0.15 },
      { p: [0, HEM, 0.014], rx: 0.2, rz: 0.152 },
    ];
    const yOfS = (s) => lerp(TOP, HEM, s);
    const foldAmp = (y) => lerp(0.003, 0.028, sstep(1.42, 0.45, y));
    const fold = (a, y) => {
      const k = y * 2.0;
      const f = 0.55 * Math.sin(9 * a + foldPhase[0] + 1.3 * Math.sin(3 * a + k)) + 0.3 * Math.sin(15 * a + foldPhase[1] + k * 2) + 0.25 * Math.sin(5 * a + foldPhase[2]) +
        0.18 * Math.sin(23 * a + foldPhase[0] * 2 + k * 3);
      return f < 0 ? f * 1.3 : f * 0.7; // hanging cloth: soft rounded crests, sharp creased valleys
    };
    // between the legs (front and back) the cotton falls in; over the thighs / knees it is pushed out
    const legShape = (a, y) => {
      let df = Math.abs(a - Math.PI / 2); df = Math.min(df, TAU - df);
      let db = Math.abs(a - 3 * Math.PI / 2); db = Math.min(db, TAU - db);
      const low = sstep(0.98, 0.62, y);
      return low * (-0.024 * gauss(df * df, 0.2) - 0.016 * gauss(db * db, 0.24) + 0.008 * gauss((df - 0.62) ** 2, 0.3));
    };
    addTube(B, keys, {
      segs: this.lowQ ? 72 : 104, step: this.lowQ ? 0.022 : 0.015, tile: 0.2,
      uvU: (a) => a / TAU, uvV: (s) => 1 - s,
      weights: (c) => {
        const y = c.y;
        if (y > 1.47) return [[bi('chest'), 1]];
        if (y > 1.38) return [[bi('chest'), sstep(1.38, 1.47, y)], [bi('spine2'), 1 - sstep(1.38, 1.47, y)]];
        if (y > 1.26) return [[bi('spine2'), sstep(1.26, 1.38, y)], [bi('spine1'), 1 - sstep(1.26, 1.38, y)]];
        if (y > 1.12) return [[bi('spine1'), sstep(1.12, 1.26, y)], [bi('hips'), 1 - sstep(1.12, 1.26, y)]];
        return [[bi('hips'), 1]];
      },
      weightsP: (P, s, w) => {
        if (P.y > 1.0) return w;
        const leg = sstep(1.0, 0.55, P.y) * 0.5;
        const sk = sstep(0.95, 0.4, P.y) * 0.45;
        const side = sstep(-0.06, 0.06, P.x);
        return [[bi('hips'), 1 - leg - sk], [bi('thighL'), leg * side], [bi('thighR'), leg * (1 - side)], [bi('skirt'), sk]];
      },
      disp: (P, N, s, a) => {
        const y = P.y;
        const f = fold(a, y) * foldAmp(y);
        const n = (fbm3(P.x * 14, P.y * 14, P.z * 14, 3, 91) - 0.5) * lerp(0.004, 0.012, s);
        const drape = -0.006 * gauss((y - 1.24) ** 2, 0.05); // fabric falls in at the waist a little
        return f + n + drape + legShape(a, y);
      },
      post: (P, s, a, ri, nr) => {
        // neckline scoops (front & back) and armholes
        let da = Math.abs(a - Math.PI / 2); // front (+Z) is a = π/2 with side=+X, front=+Z frame
        da = Math.min(da, TAU - da);
        let db = Math.abs(a - 3 * Math.PI / 2); db = Math.min(db, TAU - db);
        const topK = sstep(0.12, 0.0, s);
        P.y -= topK * (0.042 * gauss(da * da, 0.55) + 0.055 * gauss(db * db, 0.7) + 0.012);
        // ragged hem
        const hemK = sstep(0.82, 1.0, s);
        P.y += hemK * hemShift(a);
      },
      color: (P, s, a) => {
        const y = P.y;
        const n1 = fbm3(P.x * 6, P.y * 6, P.z * 6, 3, 101), n2 = fbm3(P.x * 22, P.y * 22, P.z * 22, 2, 103);
        let c = [0.64, 0.585, 0.48];                                        // old yellowed cotton
        const stain = sstep(0.52, 0.7, n1);
        c = [lerp(c[0], 0.47, stain * 0.7), lerp(c[1], 0.38, stain * 0.7), lerp(c[2], 0.27, stain * 0.7)];
        const damp = sstep(0.58, 0.75, n2) * 0.3;
        c = c.map((v) => v * (1 - damp));
        // long drip / sweat streaks running down the cloth
        const drip = sstep(0.62, 0.8, fbm3(P.x * 34, P.y * 2.2, P.z * 34, 2, 107)) * sstep(1.45, 1.1, y);
        c = [lerp(c[0], 0.36, drip * 0.5), lerp(c[1], 0.31, drip * 0.5), lerp(c[2], 0.24, drip * 0.5)];
        const hem = sstep(0.95, 0.38, y + (n2 - 0.5) * 0.2);
        c = [lerp(c[0], 0.27, hem * 0.8), lerp(c[1], 0.235, hem * 0.8), lerp(c[2], 0.19, hem * 0.8)];
        // old rust-brown stain on the front of the chest
        const front = Math.sin(a);
        const rust = sstep(0.4, 0.8, front) * gauss((y - 1.33) ** 2 + (P.x + 0.03) ** 2 * 0.6, 0.07) * sstep(0.35, 0.6, n2);
        c = [lerp(c[0], 0.45, rust * 0.65), lerp(c[1], 0.27, rust * 0.65), lerp(c[2], 0.22, rust * 0.65)];
        // fold AO
        const f = fold(a, y);
        const ao = 1 - clamp(-f, 0, 1) * 0.28 * sstep(1.4, 0.8, y);
        return c.map((v) => v * ao);
      },
    });
    // straps over the shoulders (thin cords)
    for (const sx of [1, -1]) {
      addTube(B, [
        { p: [0.075 * sx, 1.468, 0.092], rx: 0.0042, rz: 0.003 },
        { p: [0.1 * sx, 1.585, 0.06], rx: 0.0042, rz: 0.003 },
        { p: [0.112 * sx, 1.64, 0.0], rx: 0.0042, rz: 0.003 },
        { p: [0.1 * sx, 1.59, -0.066], rx: 0.0042, rz: 0.003 },
        { p: [0.078 * sx, 1.45, -0.092], rx: 0.0042, rz: 0.003 },
      ], {
        segs: 6, step: 0.01, tile: 0.2, front: [sx, 0.3, 0],
        uvU: (a) => a / TAU * 0.02 + 0.5, uvV: () => 0.95,
        weights: (c) => (c.y > 1.56 ? [[bi(sx > 0 ? 'clavL' : 'clavR'), 0.6], [bi('chest'), 0.4]] : [[bi('chest'), 1]]),
        color: () => [0.82, 0.78, 0.68],
      });
    }
    this.geoGown = B.build();
    // aoMap uses uv channel 0 already (same attribute)
  }

  // ---------------------------------------------------------------------------------------- hair
  _buildHair() {
    const r = mulberry32(2024);
    const lowQ = this.lowQ;
    const nGuides = lowQ ? 46 : this.q === 'medium' ? 62 : 74;
    const perGuide = lowQ ? 5 : this.q === 'medium' ? 6 : 8;
    const H = this.restW.head;
    const HC = new THREE.Vector3().copy(HEAD_C).add(H);
    const HR = new THREE.Vector3(0.081, 0.134, 0.101);
    // body collision shapes (model space, rest pose)
    const ell = [
      { c: new THREE.Vector3(0, 1.52, -0.015), r: new THREE.Vector3(0.205, 0.105, 0.118) },
      { c: new THREE.Vector3(0, 1.3, -0.006), r: new THREE.Vector3(0.158, 0.3, 0.125) },
      { c: new THREE.Vector3(0, 1.0, 0.0), r: new THREE.Vector3(0.18, 0.22, 0.14) },
    ];
    const sph = [
      { c: new THREE.Vector3(0, 1.72, -0.012), r: 0.052 },  // neck
      { c: new THREE.Vector3(0, 1.85, 0.108), r: 0.02 },     // nose
      { c: new THREE.Vector3(0, 1.765, 0.075), r: 0.03 },    // chin
      { c: new THREE.Vector3(0.0, 1.81, 0.05), r: 0.05 },    // lower face / jaw
    ];
    const T = new THREE.Vector3();
    const collide = (p, inflate) => {
      // head ellipsoid
      T.subVectors(p, HC);
      let qx = T.x / (HR.x + inflate), qy = T.y / (HR.y + inflate), qz = T.z / (HR.z + inflate);
      let l = Math.hypot(qx, qy, qz);
      if (l < 1) { p.set(HC.x + (qx / l) * (HR.x + inflate), HC.y + (qy / l) * (HR.y + inflate), HC.z + (qz / l) * (HR.z + inflate)); }
      for (const e of ell) {
        T.subVectors(p, e.c);
        qx = T.x / (e.r.x + inflate); qy = T.y / (e.r.y + inflate); qz = T.z / (e.r.z + inflate);
        l = Math.hypot(qx, qy, qz);
        if (l < 1) p.set(e.c.x + (qx / l) * (e.r.x + inflate), e.c.y + (qy / l) * (e.r.y + inflate), e.c.z + (qz / l) * (e.r.z + inflate));
      }
      for (const s of sph) {
        T.subVectors(p, s.c);
        l = T.length();
        const rr = s.r + inflate;
        if (l < rr) p.copy(s.c).addScaledVector(T, rr / Math.max(1e-6, l));
      }
    };
    // guide roots: fibonacci directions inside the hairline
    const roots = [];
    const total = Math.round(nGuides / 0.42);
    for (let i = 0; i < total && roots.length < nGuides * 1.3; i++) {
      const y = 1 - (2 * (i + 0.5)) / total;
      const phi = Math.acos(y);
      const theta = ((i * 2.399963) % TAU) - Math.PI;
      if (phi < this._hairlinePhi(theta) - 0.02) roots.push({ theta, phi });
    }
    while (roots.length > nGuides) roots.splice(Math.floor(r() * roots.length), 1);
    // extra dense curtain roots along the front hairline
    const curtainN = lowQ ? 10 : 14;
    for (let k = 0; k < curtainN; k++) {
      const th = (k / (curtainN - 1) - 0.5) * 1.15 + (r() - 0.5) * 0.06;
      roots.push({ theta: th, phi: this._hairlinePhi(th) - 0.05 - r() * 0.12, curtain: true });
    }

    const N = 22;
    const guides = [];
    const P = new THREE.Vector3(), D = new THREE.Vector3(), nrm = new THREE.Vector3(), comb = new THREE.Vector3();
    const down = new THREE.Vector3(0, -1, 0);
    for (const rt of roots) {
      headBase(rt.theta, rt.phi, P);
      P.add(H);
      nrm.copy(P).sub(HC).divide(HR).divide(HR).normalize();
      const front = Math.cos(rt.theta) > 0.55 && rt.phi < 1.2;
      const curtain = rt.curtain || (front && r() < 0.55);
      if (curtain) comb.set(Math.sin(rt.theta) * 0.35, -0.15, 1);
      else {
        const sx = Math.sign(P.x) * Math.min(1, Math.abs(P.x) / 0.025);
        comb.set(sx * 0.75, -0.9, -0.4);
      }
      comb.addScaledVector(nrm, -comb.dot(nrm)).normalize();
      const inflate = 0.003 + r() * (curtain ? 0.01 : 0.016);
      let L;
      if (curtain) L = 0.5 + r() * 0.18;
      else L = Math.cos(rt.theta) > 0.2 ? 0.62 + r() * 0.2 : 0.78 + r() * 0.2;
      const seg = L / (N - 1);
      const pts = [P.clone().addScaledVector(nrm, 0.002)];
      const wave = { a: 0.004 + r() * 0.012, f: 6 + r() * 10, ph: r() * TAU, ax: new THREE.Vector3(r() - 0.5, 0, r() - 0.5).normalize() };
      let s = 0;
      const turn0 = curtain ? 0.035 : 0.0, turn1 = curtain ? 0.08 : 0.06;
      for (let k = 1; k < N; k++) {
        s += seg;
        D.copy(comb).lerp(down, sstep(turn0, turn1, s)).normalize();
        const q = pts[k - 1].clone().addScaledVector(D, seg);
        q.addScaledVector(wave.ax, Math.sin(s * wave.f + wave.ph) * wave.a * sstep(0.08, 0.3, s) * seg * 8);
        collide(q, inflate);
        // keep segment length
        T.subVectors(q, pts[k - 1]).setLength(seg);
        q.copy(pts[k - 1]).add(T);
        collide(q, inflate);
        pts.push(q);
      }
      // departure: first point falling steeply below the upper head
      let dep = N - 2;
      for (let k = 1; k < N - 1; k++) {
        T.subVectors(pts[k + 1], pts[k]).normalize();
        if (T.y < -0.75 && pts[k].y < HC.y + 0.07) { dep = k; break; }
      }
      guides.push({ pts, curtain, inflate, L, dep, theta: rt.theta, nrm: nrm.clone() });
    }

    // ---- chains: anchors + rest polylines from the guides
    const chainDefs = [
      { id: 'FL', curtain: 1 }, { id: 'FR', curtain: -1 },
      { id: 'FSL', az: 0.85 }, { id: 'SL', az: 1.45 }, { id: 'BL', az: 2.2 }, { id: 'BC', az: Math.PI },
      { id: 'BR', az: -2.2 }, { id: 'SR', az: -1.45 }, { id: 'FSR', az: -0.85 },
    ];
    const azOf = (p) => Math.atan2(p.x - HC.x, p.z - HC.z);
    const angDist = (a, b) => { let d = Math.abs(a - b) % TAU; return d > Math.PI ? TAU - d : d; };
    for (const g of guides) {
      const dp = g.pts[g.dep];
      g.az = azOf(dp);
      if (g.curtain && Math.cos(g.az) > 0.2) { g.chainA = dp.x >= HC.x ? 0 : 1; g.chainB = -1; g.wA = 1; continue; }
      let best = -1, bd = Infinity, second = -1, sd = Infinity;
      for (let c = 2; c < chainDefs.length; c++) {
        const d = angDist(g.az, chainDefs[c].az);
        if (d < bd) { second = best; sd = bd; best = c; bd = d; } else if (d < sd) { second = c; sd = d; }
      }
      g.chainA = best; g.chainB = second;
      const wA = sd / Math.max(1e-6, bd + sd);
      g.wA = clamp(lerp(1, wA, 0.85), 0.5, 1);
    }
    const NB = 4;
    const chains = [];
    for (let c = 0; c < chainDefs.length; c++) {
      const mine = guides.filter((g) => g.chainA === c);
      if (!mine.length) { chains.push(null); continue; }
      const rest = [];
      for (let k = 0; k <= NB; k++) {
        const f = k / NB;
        const acc = new THREE.Vector3();
        for (const g of mine) {
          const last = g.pts.length - 1;
          const t = g.dep + f * (last - g.dep);
          const i0 = Math.floor(t), i1 = Math.min(last, i0 + 1);
          acc.add(T.copy(g.pts[i0]).lerp(g.pts[i1], t - i0));
        }
        rest.push(acc.multiplyScalar(1 / mine.length));
      }
      const bones = [];
      let parent = 'head';
      for (let k = 0; k < NB; k++) {
        const name = `hair${chainDefs[c].id}${k}`;
        this._addBone(name, parent, rest[k].x, rest[k].y, rest[k].z);
        bones.push(this.b[name]);
        parent = name;
      }
      chains.push({ id: chainDefs[c].id, rest, bones, idx: bones.map((b) => this.boneIndex[b.name]), lens: [] });
    }
    for (const ch of chains) if (ch) for (let k = 0; k < NB; k++) ch.lens.push(ch.rest[k].distanceTo(ch.rest[k + 1]));
    this.hairChains = chains.filter(Boolean);
    this._chainByIndex = chains;

    // ---- strands (clumped members around each guide) -> ribbons
    const B = new GeoBuilder();
    const iHead = this.bi('head');
    const out = new THREE.Vector3(), side = new THREE.Vector3(), tan = new THREE.Vector3();
    const weightFor = (g, k, fr) => {
      // fr: 0..1 along the strand after departure ; k: point index
      if (k <= g.dep) {
        const before = g.dep - k;
        if (before > 1.5) return [[iHead, 1]];
      }
      const ff = clamp(fr, 0, 1) * NB;
      const b0 = Math.min(NB - 1, Math.floor(ff)), t = ff - b0;
      const res = [];
      const add = (chainI, wc) => {
        const ch = chains[chainI];
        if (!ch || wc <= 0) return;
        const tb = sstep(0.55, 1.0, t);
        res.push([ch.idx[b0], wc * (1 - tb)]);
        if (b0 + 1 < NB) res.push([ch.idx[b0 + 1], wc * tb]); else res[res.length - 1][1] = wc;
      };
      const headK = k <= g.dep ? sstep(g.dep + 0.5, g.dep - 1.5, k) : 0;
      add(g.chainA, (1 - headK) * g.wA);
      if (g.chainB >= 0) add(g.chainB, (1 - headK) * (1 - g.wA));
      if (headK > 0) res.push([iHead, headK]);
      if (!res.length) res.push([iHead, 1]);
      return res;
    };
    const strandsPts = [];
    for (const g of guides) {
      const members = g.curtain ? perGuide - 1 : perGuide;
      for (let mI = 0; mI < members; mI++) {
        const off = new THREE.Vector3((r() - 0.5) * 2, (r() - 0.5) * 0.6, (r() - 0.5) * 2).multiplyScalar(0.006 + r() * 0.006);
        const lenK = 0.8 + r() * 0.2;
        const pts = [];
        const last = Math.max(3, Math.round((g.pts.length - 1) * lenK));
        for (let k = 0; k <= last; k++) {
          const gp = g.pts[Math.min(k, g.pts.length - 1)];
          const s = k / (g.pts.length - 1);
          tan.subVectors(g.pts[Math.min(g.pts.length - 1, k + 1)], g.pts[Math.max(0, k - 1)]).normalize();
          T.copy(off).addScaledVector(tan, -off.dot(tan)).multiplyScalar(lerp(1, 0.3, sstep(0, 1, s)));
          const q = gp.clone().add(T);
          q.x += Math.sin(s * 23 + mI * 1.7) * 0.0025 * s;
          q.z += Math.cos(s * 19 + mI * 2.3) * 0.0025 * s;
          if (k < 6) collide(q, g.inflate * 0.7);
          pts.push(q);
        }
        const layer = clamp(g.inflate / 0.019, 0, 1);
        if (g.curtain && r() < 0.16) {
          const cut = Math.max(4, Math.round(pts.length * (0.26 + r() * 0.14)));
          strandsPts.push({ g, pts: pts.slice(0, cut), stray: true, w0: 0.0032 + r() * 0.002, tone: 0.8 + r() * 0.3 });
          continue;
        }
        strandsPts.push({ g, pts, w0: (lowQ ? 0.009 : 0.0065) + r() * 0.007, tone: (r() < 0.05 ? 1.5 + r() * 0.5 : 0.7 + r() * 0.5) * (0.55 + 0.45 * layer) });
      }
    }
    const hairNormals = [];
    const jit = new THREE.Vector3(), nOut = new THREE.Vector3();
    for (const st of strandsPts) {
      const { g, pts } = st;
      const n = pts.length;
      const lastG = g.pts.length - 1;
      const base = B.count;
      const tiltA = (r() - 0.5) * 1.4, tiltB = (r() - 0.5) * 0.8;
      let facing = 0;
      for (let k = 0; k < n; k++) {
        const p = pts[k];
        tan.subVectors(pts[Math.min(n - 1, k + 1)], pts[Math.max(0, k - 1)]).normalize();
        // outward: from the head centre near the head, from the body axis lower down
        const hk = sstep(HC.y - 0.12, HC.y - 0.02, p.y);
        out.subVectors(p, HC).normalize();
        T.set(p.x, 0, p.z + 0.01).normalize();
        out.lerp(T, 1 - hk).normalize();
        side.crossVectors(tan, out).normalize();
        const s = k / (n - 1);
        const w = st.w0 * (1 - 0.85 * Math.pow(s, 1.6)) * (k === 0 ? 0.6 : 1);
        const fr = (k - g.dep) / Math.max(1, lastG - g.dep);
        const wts = st.stray ? [[iHead, 1]] : weightFor(g, k, fr);
        const tone = st.tone * (0.45 + 0.55 * sstep(0.0, 0.12, s * g.L)), c = [tone, tone, tone];
        const v = (k * (g.L / (g.pts.length - 1))) / 0.22;
        B.vert(p.x - side.x * w * 0.5, p.y - side.y * w * 0.5, p.z - side.z * w * 0.5, 0, v, c, wts);
        B.vert(p.x + side.x * w * 0.5, p.y + side.y * w * 0.5, p.z + side.z * w * 0.5, 1, v, c, wts);
        // "volume" normal: outward from the hair mass, jittered per strand (breaks the specular into strands)
        jit.crossVectors(side, tan).normalize();
        if (jit.dot(out) < 0) jit.negate();
        nOut.copy(out).multiplyScalar(0.65).addScaledVector(jit, 0.35).addScaledVector(side, tiltA * 0.5).addScaledVector(tan, tiltB * 0.3).normalize();
        hairNormals.push(nOut.x, nOut.y, nOut.z, nOut.x, nOut.y, nOut.z);
        // card winding check: triangle (a, c, b) normal = cross(c - a, b - a) ≈ cross(tan, side)
        facing += T.crossVectors(tan, side).dot(out);
      }
      for (let k = 0; k < n - 1; k++) {
        const a = base + k * 2, b = a + 1, c = a + 2, d = a + 3;
        if (facing >= 0) { B.tri(a, c, b); B.tri(b, c, d); } else { B.tri(a, b, c); B.tri(b, d, c); }
      }
    }
    this.geoHair = B.build();
    this.geoHair.setAttribute('normal', new THREE.Float32BufferAttribute(hairNormals, 3));
    this.hairStrandCount = strandsPts.length;
  }

  // ---------------------------------------------------------------------------------------- binding
  _bindAll() {
    this.root.updateMatrixWorld(true);
    this.skeleton = new THREE.Skeleton(this.boneList);
    const mk = (geo, mat, name, cast = true) => {
      const m = new THREE.SkinnedMesh(geo, mat);
      m.name = name;
      m.castShadow = cast; m.receiveShadow = true;
      // generous fixed bounds (covers every pose incl. reaching arms / lunges): keeps per-face culling for the
      // point-light shadow cube instead of drawing her into all 6 faces
      m.frustumCulled = true;
      m.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 1.0, 0.1), 1.45);
      this.root.add(m);
      m.bind(this.skeleton, m.matrixWorld);
      return m;
    };
    this.meshBody = mk(this.geoBody, this.matSkin, 'gardienne_body');
    this.meshHead = mk(this.geoHead, this.matHead, 'gardienne_head');
    this.meshTeeth = mk(this.geoTeeth, this.matTeeth, 'gardienne_teeth', false);
    this.meshGown = mk(this.geoGown, this.matGown, 'gardienne_gown');
    this.meshHair = mk(this.geoHair, this.matHair, 'gardienne_hair');
    this.meshes = [this.meshBody, this.meshHead, this.meshTeeth, this.meshGown, this.meshHair];
    // the closed mouth hides the teeth anyway; render teeth after the head
    this.meshTeeth.renderOrder = 1;
  }

  // ---------------------------------------------------------------------------------------- animation
  _initPose() {
    this.pose = {
      phase: 0, moveW: 0, chaseW: 0, searchW: 0, reachW: 0, stairs: 0, speed: 0,
      lookYaw: 0, lookPitch: 0, tiltT: 0, tilt: 0, tiltTarget: 0, scanT: 0, scanYaw: 0, scanPitch: 0,
      glitchT: 3 + Math.random() * 5, freeze: 0, snapT: 0, snapYaw: 0, snapRoll: 0, spasmT: 0,
      bobV: 0, bob: 0, jaw: 0, part: 0, eyeshine: 0.15, duck: 0,
      skirtX: 0, skirtZ: 0, skirtVX: 0, skirtVZ: 0,
      lastRootPos: new THREE.Vector3(), rootVel: new THREE.Vector3(), rootAcc: new THREE.Vector3(), init: false,
      twitch: new Float32Array(10), twitchT: 0,
    };
    this.rot = {};
    for (const b of this.boneList) this.rot[b.name] = new THREE.Euler();
    // hair particles
    this._hairState = this.hairChains.map((ch) => ({
      ch, p: ch.rest.map((v) => v.clone()), prev: ch.rest.map((v) => v.clone()),
      restLocal: ch.rest.map((v) => v.clone().sub(this.restW.head)),
      noise: Math.random() * 100, force: new THREE.Vector3(),
      // jumpscare parting: curtain chains slide outward toward the temples
      partDir: ch.id === 'FL' ? 1 : ch.id === 'FR' ? -1 : ch.id === 'FSL' ? 0.55 : ch.id === 'FSR' ? -0.55 : 0,
      anchor: ch.rest[0].clone().sub(this.restW.head),
    }));
    this._hairInit = false;
    this._headInv = new THREE.Matrix4();
    this._colliders = [
      { bone: this.b.head, c: new THREE.Vector3(0, 0.07, 0.0), r: new THREE.Vector3(0.088, 0.136, 0.105), inv: new THREE.Matrix4() },
      { bone: this.b.head, c: new THREE.Vector3(0, 0.03, 0.065), r: new THREE.Vector3(0.06, 0.07, 0.062), inv: new THREE.Matrix4() },
      { bone: this.b.neck, c: new THREE.Vector3(0, 0.09, 0.0), r: new THREE.Vector3(0.055, 0.1, 0.055), inv: new THREE.Matrix4() },
      { bone: this.b.chest, c: new THREE.Vector3(0, 0.06, -0.004), r: new THREE.Vector3(0.205, 0.11, 0.12), inv: new THREE.Matrix4() },
      { bone: this.b.spine1, c: new THREE.Vector3(0, 0.06, 0.0), r: new THREE.Vector3(0.158, 0.26, 0.128), inv: new THREE.Matrix4() },
    ];
    this.root.updateMatrixWorld(true);
  }

  /** World position of the face centre (for the jumpscare camera). */
  getFaceWorld(target = new THREE.Vector3()) { return this.b.head.localToWorld(target.set(0, 0.06, 0.1)); }
  /** World position between the eyes (line-of-sight checks). */
  getEyeWorld(target = new THREE.Vector3()) { return this.b.head.localToWorld(target.set(0, 0.09, 0.07)); }
  getHeadWorld(target = new THREE.Vector3()) { return this.b.head.localToWorld(target.set(0, 0.07, 0)); }

  setVisible(v) { this.root.visible = v; }

  /**
   * Scales the albedo of every material (1 = normal). Used during the jumpscare: her face is ~0.45 m from the
   * flashlight, which would blow it out to white without a camera-style exposure compensation.
   */
  setExposure(k) {
    if (Math.abs(k - (this._expo ?? 1)) < 0.01) return;
    this._expo = k;
    // specular / clearcoat do not depend on the albedo: scale them too, or the hair turns into a white wig at
    // point-blank flashlight range
    const mats = [this.matSkin, this.matHead, this.matGown, this.matTeeth, this.matEye, this.matHair];
    if (!this._specBase) this._specBase = mats.map((m) => [m.specularIntensity, m.clearcoat, m.sheen]);
    mats.forEach((m, i) => {
      const b = this._specBase[i];
      m.color.setScalar(k);
      m.specularIntensity = b[0] * k; m.clearcoat = b[1] * k; m.sheen = b[2] * k;
    });
  }

  /** Instantly snap the hair simulation to the current pose (after teleports). */
  resetSimulation() { this._hairInit = false; this.pose.init = false; }

  update(dt, ctx = {}) {
    dt = Math.min(dt, 0.05);
    this.time += dt;
    const p = this.pose, R = this.rot;
    const t = this.time;
    const mode = ctx.mode || 'idle';
    const speed = ctx.speed ?? 0;
    const jumpT = ctx.jumpT ?? -1;
    const jumping = jumpT >= 0 || mode === 'jumpscare';
    const aggr = ctx.aggression ?? 0;

    // ---- smoothed blend weights
    p.speed = dampTo(p.speed, speed, 8, dt);
    p.moveW = dampTo(p.moveW, clamp(speed / 0.45, 0, 1), 6, dt);
    p.chaseW = dampTo(p.chaseW, mode === 'chase' ? 1 : 0, mode === 'chase' ? 5 : 2, dt);
    p.searchW = dampTo(p.searchW, mode === 'search' ? 1 : 0, 3, dt);
    p.reachW = dampTo(p.reachW, mode === 'reach' ? 1 : 0, 5, dt);
    p.stairs = dampTo(p.stairs, ctx.stairs ?? 0, 5, dt);
    p.duck = dampTo(p.duck, ctx.duck ?? 0, 5, dt);
    const mw = p.moveW, cw = p.chaseW;

    // ---- gait phase + footsteps
    const stepLen = lerp(0.6, 1.0, cw) * (Math.abs(p.stairs) > 0.3 ? 0.62 : 1);
    const prevPhase = p.phase;
    if (p.speed > 0.03) p.phase = (p.phase + (dt * Math.PI * p.speed) / stepLen) % TAU;
    if (this.onFootstep && p.speed > 0.15) {
      if (phaseCrossed(prevPhase, p.phase, Math.PI / 2)) { this._footstep('L'); p.bobV -= 0.18 * (0.5 + mw); }
      if (phaseCrossed(prevPhase, p.phase, 3 * Math.PI / 2)) { this._footstep('R'); p.bobV -= 0.22 * (0.5 + mw); }
    }
    p.bobV += (-p.bob * 90 - p.bobV * 12) * dt;
    p.bob += p.bobV * dt;

    // ---- glitches
    p.glitchT -= dt;
    if (p.glitchT <= 0 && !jumping) {
      p.glitchT = (mode === 'chase' ? 1.8 : 4) + Math.random() * (mode === 'chase' ? 3 : 8) - aggr * 0.6;
      const kind = Math.random();
      if (kind < 0.38) p.freeze = 0.07 + Math.random() * 0.16;
      else if (kind < 0.78) { p.snapT = 0.1 + Math.random() * 0.22; p.snapYaw = (Math.random() - 0.5) * 1.3; p.snapRoll = (Math.random() < 0.5 ? -1 : 1) * (0.4 + Math.random() * 0.5); }
      else p.spasmT = 0.18 + Math.random() * 0.2;
    }
    if (p.freeze > 0) { p.freeze -= dt; this._postPose(dt, ctx, false); return; }

    // ---- look target (head yaw/pitch relative to the body)
    let lookYaw = 0, lookPitch = 0;
    if (ctx.look) {
      const L = this._v.a.copy(ctx.look);
      this.root.worldToLocal(L);
      lookYaw = clamp(Math.atan2(L.x, Math.max(0.05, L.z)), -1.15, 1.15);
      const hy = 1.75 - (0.12 * (1 - cw));
      lookPitch = clamp(Math.atan2(L.y - hy, Math.hypot(L.x, L.z)), -0.7, 0.6);
    }
    // search: jerky scanning + strong tilts
    if (p.searchW > 0.05) {
      p.scanT -= dt;
      if (p.scanT <= 0) {
        p.scanT = 0.45 + Math.random() * 1.6;
        p.scanYaw = (Math.random() - 0.5) * 1.6;
        p.scanPitch = (Math.random() - 0.4) * 0.5;
        p.tiltTarget = (Math.random() < 0.5 ? -1 : 1) * (0.15 + Math.random() * 0.55);
        if (Math.random() < 0.25) p.tiltTarget *= 0.2;
      }
      if (!ctx.look) { lookYaw = p.scanYaw; lookPitch = p.scanPitch; }
    } else p.tiltTarget = 0;
    const lookRate = p.searchW > 0.5 ? 16 : cw > 0.5 ? 10 : 4;
    p.lookYaw = dampTo(p.lookYaw, lookYaw, lookRate, dt);
    p.lookPitch = dampTo(p.lookPitch, lookPitch, lookRate, dt);
    p.tilt = dampTo(p.tilt, p.tiltTarget * p.searchW, 20, dt);

    // ---- base: stooped, hunched
    const breath = Math.sin(t * 1.25) * (1 - cw * 0.5);
    const lean = lerp(0.3, 0.66, cw) + p.stairs * 0.12 + p.reachW * 0.1;
    const sw = Math.sin(p.phase), cwv = Math.cos(p.phase);
    R.hips.set(lean * 0.16 + Math.abs(sw) * 0.03 * mw * cw, 0.1 * sw * mw, 0.045 * cwv * mw);
    R.spine1.set(lean * 0.2 + breath * 0.008, -0.03 * sw * mw, -0.02 * cwv * mw);
    R.spine2.set(lean * 0.28 + breath * 0.012, -0.05 * sw * mw, -0.015 * cwv * mw);
    R.chest.set(lean * 0.24 - breath * 0.02, -0.1 * sw * mw - p.lookYaw * 0.12, -0.03 * cwv * mw + p.tilt * 0.08);
    R.neck.set(lerp(0.34, 0.1, cw) - p.lookPitch * 0.3, p.lookYaw * 0.35, p.tilt * 0.25);
    R.head.set(lerp(0.2, -0.62, cw) - p.lookPitch * 0.75 + p.searchW * 0.05, p.lookYaw * 0.55, p.tilt * 0.9);
    if (p.duck > 0.002) {
      const d = p.duck;
      R.spine2.x += 0.2 * d; R.chest.x += 0.2 * d; R.neck.x += 0.22 * d; R.head.x -= 0.3 * d;
    }
    R.skirt.set(p.skirtX, 0, p.skirtZ);
    R.jaw.set(0.02 + 0.01 * Math.sin(t * 0.7), 0, 0);

    // ---- legs
    const legLean = R.hips.x;
    for (const [S, off, sx] of SIDES3) {
      const ps = p.phase + off, s = Math.sin(ps), c = Math.cos(ps);
      const limp = S === 'R' ? 0.78 : 1;
      const A = lerp(0.34, 0.62, cw) * mw * limp;
      const swing = Math.max(0, c);
      let hip = -A * s - legLean;
      let knee = 0.11 + 0.18 * p.duck + (lerp(0.55, 1.2, cw) * Math.pow(swing, 1.5) * limp + 0.08 * Math.max(0, -s)) * mw;
      hip -= 0.04 + 0.09 * p.duck;
      // stairs: lift the swing leg higher when going up, reach down when going down
      if (p.stairs > 0) { hip -= p.stairs * 0.45 * swing * mw; knee += p.stairs * 0.75 * swing * mw; }
      if (p.stairs < 0) { knee += -p.stairs * 0.3 * Math.max(0, -c) * mw; hip -= -p.stairs * 0.15 * swing * mw; }
      const ankle = -(hip + legLean) * 0.6 - knee * 0.72 + 0.32 * Math.max(0, -s) * Math.max(0, -c) * mw;
      R['thigh' + S].set(hip, sx * 0.02 + (S === 'R' ? -0.04 * mw : 0), sx * (0.025 + 0.02 * mw));
      R['shin' + S].set(knee, 0, 0);
      R['foot' + S].set(ankle, S === 'R' ? 0.22 * mw : 0, -sx * 0.03);
      R['toe' + S].set(-0.25 * Math.max(0, -s) * Math.max(0, -c) * mw + (S === 'R' ? 0.15 * mw : 0), 0, 0);
    }

    // ---- arms (dangling in the walk, reaching in the chase)
    const spineLean = R.hips.x + R.spine1.x + R.spine2.x + R.chest.x;
    for (const [S, off, sx] of SIDES3) {
      const ps = p.phase + off;
      const dangle = Math.sin(ps - 0.7) * 0.13 * mw;
      const chaseSwing = Math.sin(ps) * 0.75;
      let ax = -spineLean * 0.62 - 0.04 + dangle;
      ax = lerp(ax, -0.55 - spineLean * 0.3 + chaseSwing, cw);
      let az = sx * (0.115 + 0.02 * Math.sin(t * 0.9 + off));
      az = lerp(az, sx * 0.3, cw);
      const ay = lerp(-sx * 0.38, sx * 0.1, cw);
      let fx = -0.36 - 0.08 * Math.sin(ps - 1.2) * mw - 0.12 * p.searchW;
      fx = lerp(fx, -0.75 - 0.35 * Math.max(0, Math.sin(ps)), cw);
      R['clav' + S].set(0, sx * -0.2, sx * (-0.05 + 0.15 * cw));
      R['arm' + S].set(ax, ay, az);
      R['fore' + S].set(fx, sx * lerp(-0.25, 0.1, cw), 0);
      R['hand' + S].set(0.2 - 0.1 * cw, sx * 0.15 * (1 - cw), sx * -0.1);
    }
    // reach (right arm toward a door / the player)
    if (p.reachW > 0.01) {
      const k = p.reachW;
      R.armR.x = lerp(R.armR.x, -1.25 - spineLean * 0.4, k);
      R.armR.z = lerp(R.armR.z, -0.18, k);
      R.foreR.x = lerp(R.foreR.x, -0.22, k);
      R.handR.x = lerp(R.handR.x, -0.2, k);
    }

    // ---- fingers: limp curl + twitches; claws in the chase
    p.twitchT -= dt;
    if (p.twitchT <= 0) {
      p.twitchT = 0.15 + Math.random() * (p.searchW > 0.5 ? 0.5 : 1.4);
      const i = Math.floor(Math.random() * 10);
      p.twitch[i] = (Math.random() - 0.3) * 0.9;
    }
    for (let i = 0; i < 10; i++) p.twitch[i] = dampTo(p.twitch[i], 0, 3, dt);
    let fi = 0;
    for (const [S, sx] of SIDES2) {
      const curlBase = lerp(0.26, 0.5, cw);
      for (const [fn, , , , ] of FINGERS) {
        const tw = p.twitch[fi++];
        const spread = fn === 'index' ? -0.07 : fn === 'pinky' ? 0.1 : fn === 'ring' ? 0.04 : 0;
        const c = curlBase + tw + (fn === 'pinky' ? 0.08 : 0);
        R[`${fn}0${S}`].set(spread * (1 + cw), 0, -sx * c * 0.8);
        R[`${fn}1${S}`].set(0, 0, -sx * c * 1.1);
        R[`${fn}2${S}`].set(0, 0, -sx * c * 0.9);
      }
      const tw = p.twitch[fi++];
      R[`thumb0${S}`].set(-0.1, 0, -sx * (0.12 + tw * 0.4));
      R[`thumb1${S}`].set(0, 0, -sx * (0.2 + curlBase * 0.4));
      R[`thumb2${S}`].set(0, 0, -sx * 0.25);
    }

    // ---- glitch head snap / spasm
    if (p.snapT > 0) {
      p.snapT -= dt;
      R.head.y += p.snapYaw; R.head.z += p.snapRoll; R.neck.z += p.snapRoll * 0.3;
    }
    if (p.spasmT > 0) {
      p.spasmT -= dt;
      const j = Math.sin(t * 61) * 0.35;
      R.armL.x += j; R.foreL.x -= j * 0.8; R.clavL.z += 0.2; R.chest.y += Math.sin(t * 47) * 0.08;
    }

    // ---- jumpscare: lunge, arms rise, head snap, jaw drop, hair parting
    if (jumping) {
      const jt = Math.max(0, jumpT);
      const rise = sstep(0.0, 0.2, jt);
      const claw = sstep(0.3, 0.9, jt);
      R.hips.set(0.12, 0, 0);
      R.spine1.set(0.12, 0, 0);
      R.spine2.set(0.16, 0, 0);
      R.chest.set(0.12 - 0.08 * rise, 0, 0);
      R.neck.set(0.2 + 0.1 * rise, 0, 0);
      const snap = jt < 0.06 ? 0.75 : 0;
      R.head.set(-0.25 - 0.15 * rise + Math.sin(t * 71) * 0.035, Math.sin(t * 53) * 0.05, snap + Math.sin(t * 37) * 0.04);
      for (const [S, sx] of SIDES2) {
        R['clav' + S].set(0, -sx * 0.25 * rise, sx * 0.25 * rise);
        R['arm' + S].set(lerp(R['arm' + S].x, -1.15, rise), sx * 0.35, lerp(R['arm' + S].z, sx * 0.95, rise));
        R['fore' + S].set(lerp(R['fore' + S].x, -0.75, rise), sx * 0.35, 0);
        R['hand' + S].set(-0.35 * rise, 0, -sx * 0.2 * rise);
        for (const [fn] of FINGERS) {
          const c = lerp(-0.18, 0.75, claw) + Math.sin(t * 40 + fn.length) * 0.05;
          R[`${fn}0${S}`].set(fn === 'index' ? -0.2 : fn === 'pinky' ? 0.25 : 0, 0, -sx * c * 0.7);
          R[`${fn}1${S}`].set(0, 0, -sx * c);
          R[`${fn}2${S}`].set(0, 0, -sx * c * 0.9);
        }
      }
      for (const [S] of SIDES2) { R['thigh' + S].set(-0.25, 0, 0); R['shin' + S].set(0.35, 0, 0); R['foot' + S].set(-0.1, 0, 0); }
      p.jaw = sstep(0.03, 0.22, jt) * (0.82 + 0.05 * Math.sin(t * 43));
      p.part = sstep(0.0, 0.18, jt);
      p.eyeshine = 0.3;
    } else {
      p.jaw = dampTo(p.jaw, mode === 'chase' ? 0.12 + 0.06 * Math.sin(t * 9) : 0, 6, dt);
      p.part = dampTo(p.part, 0, 2, dt);
      p.eyeshine = dampTo(p.eyeshine, ctx.eyeshine ?? 0.15, 6, dt);
    }
    R.jaw.x += p.jaw;

    // ---- write bones
    for (const b of this.boneList) {
      const e = R[b.name];
      if (b.name.startsWith('hair')) continue;
      b.rotation.set(e.x, e.y, e.z);
    }
    // mouth slit recedes into the head as the jaw opens
    const mb = this.b.mouth, mr = this.restW.mouth, hr = this.restW.head;
    mb.position.set(mr.x - hr.x, mr.y - hr.y - p.jaw * 0.034, mr.z - hr.z - p.jaw * 0.075);
    const lu = this.b.lipU, lr = this.restW.lipU, snarl = clamp(p.jaw / 0.8, 0, 1.1);
    lu.position.set(lr.x - hr.x, lr.y - hr.y + snarl * 0.0068, lr.z - hr.z + snarl * 0.0012);
    this._postPose(dt, ctx, true);
  }

  _postPose(dt, ctx, posed) {
    const p = this.pose;
    // root bob (heavy footfalls) + crouch
    const rb = this.b.root;
    rb.position.y = p.bob - 0.012 * p.moveW - 0.03 * p.chaseW;
    this.root.updateMatrixWorld(true);
    // root velocity/acceleration for secondary motion
    const wp = this._v.b.setFromMatrixPosition(this.root.matrixWorld);
    if (!p.init) { p.lastRootPos.copy(wp); p.rootVel.set(0, 0, 0); p.init = true; }
    const vel = this._v.c.subVectors(wp, p.lastRootPos).divideScalar(Math.max(dt, 1e-3));
    if (vel.lengthSq() > 100) vel.set(0, 0, 0); // teleport
    p.rootAcc.subVectors(vel, p.rootVel).divideScalar(Math.max(dt, 1e-3)).clampLength(0, 25);
    p.rootVel.copy(vel);
    p.lastRootPos.copy(wp);
    if (posed) {
      // skirt sway spring (local frame): lags behind accelerations, swings with the gait
      const acc = this._v.d.copy(p.rootAcc).applyQuaternion(this._q.a.copy(this.root.quaternion).invert());
      const gx = 0.06 * Math.sin(p.phase * 2) * p.moveW;
      p.skirtVX += (-(p.skirtX - gx) * 45 - p.skirtVX * 7 + acc.z * 0.5) * dt;
      p.skirtVZ += (-p.skirtZ * 45 - p.skirtVZ * 7 - acc.x * 0.5 + Math.cos(p.phase) * 0.6 * p.moveW) * dt;
      p.skirtX = clamp(p.skirtX + p.skirtVX * dt, -0.3, 0.3);
      p.skirtZ = clamp(p.skirtZ + p.skirtVZ * dt, -0.25, 0.25);
      this.b.skirt.rotation.set(p.skirtX, 0, p.skirtZ);
      this.b.skirt.updateMatrixWorld(true);
    }
    this._simHair(dt);
    // eyeshine glints
    this.matGlint.emissiveIntensity = 0.25 + p.eyeshine * 7;
  }

  _footstep(side) {
    const pos = this.b['foot' + side].getWorldPosition(this._v.d);
    try { this.onFootstep(side, pos); } catch (e) { /* ignore */ }
  }

  _simHair(dt) {
    const g = this._v.a, tmp = this._v.b, tmp2 = this._v.c;
    const head = this.b.head;
    const hq = this._hq; head.getWorldQuaternion(hq);
    for (const col of this._colliders) col.inv.copy(col.bone.matrixWorld).invert();
    const p = this.pose;
    const steps = dt > 0.03 ? 2 : 1;
    const h = dt / steps;
    const damp = Math.exp(-(2.6 + 7 * p.part) * h);
    if (!this._hairInit) {
      for (const hs of this._hairState) {
        for (let k = 0; k < hs.p.length; k++) {
          head.localToWorld(hs.p[k].copy(hs.restLocal[k]));
          hs.prev[k].copy(hs.p[k]);
        }
      }
      this._hairInit = true;
    }
    for (let st = 0; st < steps && h > 0; st++) {
      for (const hs of this._hairState) {
        const ch = hs.ch;
        const P = hs.p, Q = hs.prev;
        hs.anchor.copy(hs.restLocal[0]);
        if (hs.partDir !== 0 && p.part > 0.001) hs.anchor.x += hs.partDir * 0.05 * p.part, hs.anchor.z -= Math.abs(hs.partDir) * 0.012 * p.part;
        ch.bones[0].position.copy(hs.anchor);
        head.localToWorld(P[0].copy(hs.anchor));
        Q[0].copy(P[0]);
        // external force: gravity + gentle air drift
        hs.noise += h;
        const nx = Math.sin(hs.noise * 1.3 + ch.idx[0]) * 0.25, nz = Math.cos(hs.noise * 1.1 + ch.idx[0] * 0.7) * 0.25;
        g.set(nx, -9.8, nz);
        // jumpscare parting: the face curtain is pulled (stiffly) toward a parted shape beside the cheeks
        const parting = hs.partDir !== 0 && p.part > 0.001;
        const ks = parting ? 5 + 40 * p.part : 5 + 14 * p.part;
        for (let k = 1; k < P.length; k++) {
          // verlet + soft return to the rest shape (head space)
          tmp.copy(hs.restLocal[k]);
          tmp.x += hs.anchor.x - hs.restLocal[0].x; tmp.z += hs.anchor.z - hs.restLocal[0].z;
          if (parting) { tmp.x += hs.partDir * p.part * 0.022 * k; tmp.z -= Math.abs(hs.partDir) * p.part * 0.012 * k; }
          head.localToWorld(tmp);
          tmp2.copy(P[k]);
          const vx = (P[k].x - Q[k].x) * damp, vy = (P[k].y - Q[k].y) * damp, vz = (P[k].z - Q[k].z) * damp;
          P[k].x += vx + (g.x + (tmp.x - P[k].x) * ks) * h * h;
          P[k].y += vy + (g.y + (tmp.y - P[k].y) * ks) * h * h;
          P[k].z += vz + (g.z + (tmp.z - P[k].z) * ks) * h * h;
          Q[k].copy(tmp2);
        }
        for (let it = 0; it < 3; it++) {
          for (let k = 1; k < P.length; k++) {
            tmp.subVectors(P[k], P[k - 1]);
            const d = tmp.length() || 1e-6;
            tmp.multiplyScalar((d - ch.lens[k - 1]) / d);
            if (k === 1) P[k].sub(tmp);
            else { P[k].addScaledVector(tmp, -0.5); P[k - 1].addScaledVector(tmp, 0.5); }
          }
          for (let k = 1; k < P.length; k++) {
            this._collideHair(P[k]);
            if (parting) this._clearFace(P[k], hs.partDir, p.part);
          }
        }
      }
    }
    // orient chain bones along the simulated particles
    const parentQ = this._pq, rq = this._rq, local = this._lq;
    for (const hs of this._hairState) {
      const ch = hs.ch, P = hs.p;
      parentQ.copy(hq);
      for (let k = 0; k < ch.bones.length; k++) {
        const restDir = tmp.subVectors(ch.rest[k + 1], ch.rest[k]).normalize().applyQuaternion(parentQ);
        const want = tmp2.subVectors(P[k + 1], P[k]).normalize();
        rq.setFromUnitVectors(restDir, want).multiply(parentQ); // desired world orientation of bone k
        local.copy(parentQ).invert().multiply(rq);
        ch.bones[k].quaternion.copy(local);
        parentQ.copy(rq);
      }
    }
  }

  /** Jumpscare: keep the parted curtain chains out of a face-wide strip in front of the face (head space). */
  _clearFace(pt, dir, part) {
    const L = this._v.d, head = this._colliders[0];
    L.copy(pt).applyMatrix4(head.inv);
    if (L.z < -0.02 || L.y < -0.16 || L.y > 0.17) return;
    const W = (0.05 + 0.045 * Math.abs(dir)) * part;
    if (Math.abs(L.x) >= W) return;
    L.x = Math.sign(dir) * W;
    pt.copy(L.applyMatrix4(head.bone.matrixWorld));
  }

  _collideHair(pt) {
    const L = this._v.d;
    for (const col of this._colliders) {
      L.copy(pt).applyMatrix4(col.inv);
      const qx = (L.x - col.c.x) / col.r.x, qy = (L.y - col.c.y) / col.r.y, qz = (L.z - col.c.z) / col.r.z;
      const l = Math.hypot(qx, qy, qz);
      if (l < 1 && l > 1e-5) {
        L.set(col.c.x + (qx / l) * col.r.x, col.c.y + (qy / l) * col.r.y, col.c.z + (qz / l) * col.r.z);
        pt.copy(L.applyMatrix4(col.bone.matrixWorld));
      }
    }
  }

  dispose() {
    for (const m of this.meshes) m.geometry.dispose();
    for (const mat of [this.matSkin, this.matHead, this.matHair, this.matTeeth, this.matEye, this.matGlint, this.matGown, this.matMouth]) mat.dispose();
    for (const t of [this.texSkin, this.texSkinN, this.texHair, this.texTear, this.texHead, this.texHeadN, this.texEye]) t?.dispose();
    this.skeleton.dispose();
  }
}
