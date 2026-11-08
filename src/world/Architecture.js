import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as L from '../config/layout.js';

// Architecture — the static shell of the level (architecture module, see ARCHITECTURE.md §6).
// Builds: floor, ceiling (with stairwell opening + drywall bulkhead), walls with real thickness and openings
// (doorway to the laundry nook, deep window recess), baseboards & door casings (profiled extrusions), stairs
// (carpeted treads, white risers, bullnose nosings, skirt boards), knee wall + shoe rail + balusters + handrail
// + newel post, wall handrail, landing, stairwell walls up to UPPER.ceilingY, upstairs 6-panel door (procedural
// bevelled panels, knob, hinges) + short warm hallway behind it (visible only when it opens), closet under the
// stairs with a LOUVERED door (separate slats, see-through) and an unfinished interior, laundry nook (painted
// concrete floor, block walls, exposed joists, pipes, dryer vent duct, HVAC trunk), barred dirty window with an
// outside ground (soil, dead grass, snow) and a night sky.
// UVs are in world meters (uniform texel density); textures carry their own repeat (= 1 / tile size).
// Grime / ambient occlusion is baked in vertex colours (darker near floors, corners, hand marks, stains).
// Shadows: visible surfaces only RECEIVE; thick closed "shadow caster" boxes (invisible in the colour pass)
// occlude the lights, so there is no light leaking through single-sided walls and no shadow acne.
//
// Registers: world.colliders (walls, knee wall, stairwell, nook, hallway, closed doors), world.occluders
// (invisible proxy boxes for walls/ceiling + door proxies that move with the doors), world.handles
// ['door.upstairs'] (locked=true, hinge west, open angle -1.6) and ['door.closet'] (hinge north, opens to +X),
// world.hideSpots (closet).
// Public API: constructor(game, world), async build(), update(dt), reset(kind)
//   extra: .root (Group), .hall (Group, hallway behind the upstairs door), .upstairsDoorOpen (0..1, read by
//   Lighting), .zoneMaterials ([{mat, zone}] materials that get an explicit, attenuated env map from Lighting),
//   .doors (internal door controllers)
// Perf (phones): one mesh per material key (+ cobwebs / window panes merged), no double-sided transparents, map-less
//   materials share their textured siblings' shader program (1x1 white map), textures loaded once per image (UV_SCALE),
//   small hardware and the nook ceiling services cast no shadows, caster boxes cost ~no fragments in colour passes.
//   Objects that join .hall (e.g. ExtraProps' hallway suitcase) are hidden with it while the upstairs door is shut.

const R = L.ROOM, S = L.STAIRS, UP = L.UPPER, UD = L.UPSTAIRS_DOOR, HALL = L.UPPER_HALL;
const CL = L.CLOSET, AL = L.ALCOVE, WIN = L.WINDOW;

const H = R.ceilingY;                                   // 2.5 room ceiling
const X0 = R.minX, X1 = R.maxX, Z0 = R.minZ, Z1 = R.maxZ;
const TS = 0.3;                                          // south foundation wall (deep window recess)
const TW = R.wallThickness;                              // other exterior walls
const TP = 0.15;                                         // north partition (room | nook / hallway)
const ZN = Z0 - TP;                                      // -2.9 back face of the north partition
const RH = S.riserHeight, TD = S.treadDepth;
const KX0 = S.sideWallX - S.sideWallThickness / 2;      // -2.6 stair-side face of the knee wall
const KX1 = S.sideWallX + S.sideWallThickness / 2;      // -2.5 room-side face of the knee wall
const KZS = 0.15;                                        // knee wall is full height north of this z
const NZ0 = 1.52, NZ1 = 1.64;                            // newel post z range
const LAND = UP.floorY, TOP = UP.ceilingY;               // 2.75, 5.2
const LAND_UNDER = LAND - 0.3;                           // underside of the landing (closet ceiling)
const BZ0 = S.ceilingOpeningMaxZ, BZ1 = BZ0 + 0.15, BY = H - 0.12; // drywall bulkhead at the stair opening
const DX0 = UD.hingeX, DX1 = UD.hingeX + UD.width;      // upstairs door opening x range
const DTOP = UD.bottomY + UD.height;                     // 4.78
const CDZ0 = CL.door.hingeZ, CDZ1 = CL.door.hingeZ + CL.door.width, CDH = CL.door.height; // closet door
const AD0 = AL.doorway.minX, AD1 = AL.doorway.maxX, ADH = AL.doorway.height;
const NN = AL.minZ;                                      // -4.6 nook north wall
const HX0 = HALL.minX, HX1 = HALL.maxX, HZ0 = HALL.minZ; // hallway

const nosingY = (z) => RH * (1 + (S.bottomZ - z) / TD); // line through the stair nosings
const stairTop = (z) => Math.min(nosingY(z), LAND);
const underY = (z) => Math.max(0, stairTop(z) - 0.3);  // underside of the stair structure
const splitY = (z) => Math.max(0, stairTop(z) - 0.18); // finished wall starts here (under the skirt board)
const capY = (z) => nosingY(z) + 0.2;                   // top of the knee wall (under the shoe rail)
const railTop = (z) => nosingY(z) + 0.89;               // top of the handrails

// ------------------------------------------------------------------------------------------------ noise

function fract(x) { return x - Math.floor(x); }
function hash3(x, y, z) { return fract(Math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453); }
function vnoise(x, y, z) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  let u = x - xi, v = y - yi, w = z - zi;
  u = u * u * (3 - 2 * u); v = v * v * (3 - 2 * v); w = w * w * (3 - 2 * w);
  const a = hash3(xi, yi, zi), b = hash3(xi + 1, yi, zi), c = hash3(xi, yi + 1, zi), d = hash3(xi + 1, yi + 1, zi);
  const e = hash3(xi, yi, zi + 1), f = hash3(xi + 1, yi, zi + 1), g = hash3(xi, yi + 1, zi + 1), h = hash3(xi + 1, yi + 1, zi + 1);
  const x1 = a + (b - a) * u, x2 = c + (d - c) * u, x3 = e + (f - e) * u, x4 = g + (h - g) * u;
  const y1 = x1 + (x2 - x1) * v, y2 = x3 + (x4 - x3) * v;
  return y1 + (y2 - y1) * w;
}
function fbm(x, y, z, oct = 3) {
  let s = 0, a = 0.5, n = 0;
  for (let i = 0; i < oct; i++) { s += a * vnoise(x, y, z); n += a; x *= 2.07; y *= 2.07; z *= 2.07; a *= 0.5; }
  return s / n;
}
function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0; let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const smooth01 = (t) => t * t * (3 - 2 * t);
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

/** Tileable 2D value noise (float array size*size, 0..1). period = lattice cells across the tile. */
function tileNoise(size, period, oct, seed) {
  const out = new Float32Array(size * size); const r = rng(seed); let amp = 1, tot = 0;
  for (let o = 0; o < oct; o++) {
    const P = period << o, lat = new Float32Array(P * P);
    for (let i = 0; i < lat.length; i++) lat[i] = r();
    for (let y = 0; y < size; y++) {
      const fy = (y / size) * P, y0 = Math.floor(fy), ty = smooth01(fy - y0), y1 = (y0 + 1) % P;
      for (let x = 0; x < size; x++) {
        const fx = (x / size) * P, x0 = Math.floor(fx), tx = smooth01(fx - x0), x1 = (x0 + 1) % P;
        const a = lat[y0 * P + x0], b = lat[y0 * P + x1], c = lat[y1 * P + x0], d = lat[y1 * P + x1];
        const top = a + (b - a) * tx, bot = c + (d - c) * tx;
        out[y * size + x] += amp * (top + (bot - top) * ty);
      }
    }
    tot += amp; amp *= 0.5;
  }
  for (let i = 0; i < out.length; i++) out[i] /= tot;
  return out;
}

// ------------------------------------------------------------------------------------------------ canvas textures

function mkCanvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function canvasTex(c, { srgb = true, repeat = null, aniso = 8 } = {}) {
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat[0], repeat[1]); }
  t.anisotropy = aniso;
  return t;
}
/** Normal map canvas from a tileable height field (OpenGL convention, +Y up in UV space). */
function normalCanvas(h, size, strength) {
  const c = mkCanvas(size, size), ctx = c.getContext('2d'), img = ctx.createImageData(size, size), d = img.data;
  for (let y = 0; y < size; y++) {
    const yu = ((y - 1 + size) % size) * size, yd = ((y + 1) % size) * size;
    for (let x = 0; x < size; x++) {
      const xl = (x - 1 + size) % size, xr = (x + 1) % size;
      const dx = (h[y * size + xr] - h[y * size + xl]) * strength;
      const dy = (h[yu + x] - h[yd + x]) * strength; // v grows upward (canvas row decreases)
      const il = 1 / Math.sqrt(dx * dx + dy * dy + 1), i = (y * size + x) * 4;
      d[i] = (-dx * il * 0.5 + 0.5) * 255; d[i + 1] = (-dy * il * 0.5 + 0.5) * 255; d[i + 2] = (il * 0.5 + 0.5) * 255; d[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return c;
}

const ProcTex = {
  /** Painted concrete block (CMU) wall: 1.6 m x 1.6 m tile, running bond. Returns {map, normalMap}. */
  block(size = 512) {
    const n1 = tileNoise(size, 8, 4, 11), n3 = tileNoise(size, 3, 3, 13);
    const rows = 8, cols = 4, bh = size / rows, bw = size / cols, mw = 1.4;
    const r = rng(5), tone = []; for (let i = 0; i < rows * cols; i++) tone.push(0.94 + r() * 0.09);
    const hgt = new Float32Array(size * size);
    const c = mkCanvas(size, size), ctx = c.getContext('2d'), img = ctx.createImageData(size, size), d = img.data;
    for (let y = 0; y < size; y++) {
      const row = Math.floor(y / bh), ly = y - row * bh;
      for (let x = 0; x < size; x++) {
        const fx = x / bw + (row % 2) * 0.5, col = Math.floor(fx) % cols, lx = (fx - Math.floor(fx)) * bw;
        const de = Math.min(lx, bw - lx, ly, bh - ly);
        const m = smooth01(clamp01((de - mw) / 1.6));
        const k = y * size + x;
        hgt[k] = m * (0.78 + 0.1 * n1[k]) + (1 - m) * (0.3 + 0.12 * n1[k]);
        const v = (0.86 + 0.1 * n1[k] + 0.06 * (n3[k] - 0.5)) * (m * tone[row * cols + col] + (1 - m) * 0.88);
        const i = k * 4;
        d[i] = 205 * v; d[i + 1] = 203 * v; d[i + 2] = 194 * v; d[i + 3] = 255;
      }
    }
    // round pores (the paint bridges most of them: shallow and soft)
    for (let p = 0, np = Math.round(2600 * (size / 512) ** 2); p < np; p++) {
      const px = r() * size, py = r() * size, pr = (0.5 + r() * r() * 1.8) * Math.max(0.6, size / 512), dep = 0.12 + r() * 0.2;
      for (let yy = Math.floor(py - pr * 2); yy <= py + pr * 2; yy++) {
        for (let xx = Math.floor(px - pr * 2); xx <= px + pr * 2; xx++) {
          const w = Math.exp(-((xx - px) ** 2 + (yy - py) ** 2) / (pr * pr));
          if (w < 0.05) continue;
          const k = ((yy + size) % size) * size + ((xx + size) % size), i = k * 4;
          hgt[k] -= dep * w;
          const f = 1 - 0.44 * dep * w;
          d[i] *= f; d[i + 1] *= f; d[i + 2] *= f;
        }
      }
    }
    ctx.putImageData(img, 0, 0);
    return { map: c, normal: normalCanvas(hgt, size, 5) };
  },
  /** Painted (battleship grey) basement concrete floor, worn through in places. 2 m tile. */
  concrete(size = 512) {
    const wear = tileNoise(size, 4, 5, 21), fine = tileNoise(size, 64, 2, 22), st = tileNoise(size, 6, 4, 23);
    const hgt = new Float32Array(size * size);
    const c = mkCanvas(size, size), ctx = c.getContext('2d'), img = ctx.createImageData(size, size), d = img.data;
    for (let k = 0; k < size * size; k++) {
      const w = smooth01(clamp01((wear[k] - 0.6) / 0.12));             // 1 = paint worn off
      const s = smooth01(clamp01((st[k] - 0.62) / 0.15));              // dark stains
      const f = 0.9 + 0.2 * fine[k];
      let r = (104 * (1 - w) + 146 * w) * f, g = (110 * (1 - w) + 140 * w) * f, b = (104 * (1 - w) + 128 * w) * f;
      const sd = 1 - 0.38 * s; r *= sd; g *= sd; b *= sd * 0.97;
      const i = k * 4; d[i] = r; d[i + 1] = g; d[i + 2] = b; d[i + 3] = 255;
      hgt[k] = 0.5 + 0.35 * fine[k] - 0.25 * w;
    }
    ctx.putImageData(img, 0, 0);
    // a couple of hairline cracks
    const r = rng(77);
    ctx.strokeStyle = 'rgba(30,30,28,0.55)'; ctx.lineWidth = 1;
    for (let k = 0; k < 3; k++) {
      let x = r() * size, y = r() * size, a = r() * Math.PI * 2;
      ctx.beginPath(); ctx.moveTo(x, y);
      for (let s = 0; s < 40; s++) { a += (r() - 0.5) * 0.9; x += Math.cos(a) * 6; y += Math.sin(a) * 6; ctx.lineTo(x, y); }
      ctx.stroke();
    }
    return { map: c, normal: normalCanvas(hgt, size, 3) };
  },
  /** Faded 90s wallpaper (cream, dusty rose stripes, tiny sprigs). 0.53 m tile. */
  wallpaper(size = 512) {
    const n = tileNoise(size, 4, 3, 31);
    const c = mkCanvas(size, size), ctx = c.getContext('2d');
    const img = ctx.createImageData(size, size), d = img.data;
    for (let k = 0; k < size * size; k++) {
      const v = 0.93 + 0.1 * n[k], i = k * 4;
      d[i] = 222 * v; d[i + 1] = 206 * v; d[i + 2] = 172 * v; d[i + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    ctx.fillStyle = 'rgba(160,104,96,0.42)';
    for (const x0 of [0, size / 2]) { ctx.fillRect(x0 + 10, 0, 4, size); ctx.fillRect(x0 + 20, 0, 2, size); }
    const r = rng(9);
    for (let row = 0; row < 6; row++) {
      for (const cx of [size * 0.25, size * 0.75]) {
        const y = (row + (cx > size / 2 ? 0.5 : 0)) * (size / 6) + 20, x = cx + 17;
        ctx.strokeStyle = 'rgba(110,128,92,0.55)'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(x, y + 18); ctx.quadraticCurveTo(x - 6, y + 6, x + 2, y - 8); ctx.stroke();
        ctx.fillStyle = 'rgba(112,132,94,0.5)';
        ctx.beginPath(); ctx.ellipse(x - 6, y + 8, 6, 3, -0.6, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = `rgba(${170 + r() * 20},${108 + r() * 10},${100},0.6)`;
        for (let p = 0; p < 5; p++) { const a = (p / 5) * Math.PI * 2; ctx.beginPath(); ctx.arc(x + 2 + Math.cos(a) * 5, y - 10 + Math.sin(a) * 5, 3.6, 0, Math.PI * 2); ctx.fill(); }
        ctx.fillStyle = 'rgba(214,180,110,0.7)'; ctx.beginPath(); ctx.arc(x + 2, y - 10, 2.2, 0, Math.PI * 2); ctx.fill();
      }
    }
    return { map: c };
  },
  /** Outside ground at night: dark soil, dead grass, snow patches. 3 m tile. */
  ground(size = 512) {
    const sn = tileNoise(size, 3, 5, 41), soil = tileNoise(size, 32, 3, 42);
    const hgt = new Float32Array(size * size);
    const c = mkCanvas(size, size), ctx = c.getContext('2d'), img = ctx.createImageData(size, size), d = img.data;
    for (let k = 0; k < size * size; k++) {
      const s = smooth01(clamp01((sn[k] - 0.56) / 0.08)), f = 0.75 + 0.5 * soil[k], i = k * 4;
      d[i] = (46 * f) * (1 - s) + 214 * s; d[i + 1] = (38 * f) * (1 - s) + 222 * s; d[i + 2] = (29 * f) * (1 - s) + 232 * s; d[i + 3] = 255;
      hgt[k] = 0.3 * soil[k] + 0.6 * s;
    }
    ctx.putImageData(img, 0, 0);
    const r = rng(43);
    for (let k = 0; k < 4200; k++) {
      const x = r() * size, y = r() * size, k2 = Math.floor(y) * size + Math.floor(x);
      if (sn[k2] > 0.6 && r() < 0.8) continue; // mostly under the snow
      const a = r() * Math.PI * 2, l = 4 + r() * 12, t = r();
      ctx.strokeStyle = `rgba(${(120 + 60 * t) | 0},${(100 + 45 * t) | 0},${(62 + 25 * t) | 0},${0.35 + r() * 0.4})`;
      ctx.lineWidth = 0.8 + r();
      for (const ox of [-size, 0, size]) for (const oy of [-size, 0, size]) {
        if ((ox && Math.abs(x + ox - size / 2) > size / 2 + l) || (oy && Math.abs(y + oy - size / 2) > size / 2 + l)) continue;
        ctx.beginPath(); ctx.moveTo(x + ox, y + oy); ctx.lineTo(x + ox + Math.cos(a) * l, y + oy + Math.sin(a) * l); ctx.stroke();
      }
    }
    return { map: c, normal: normalCanvas(hgt, size, 4) };
  },
  /** Grimy window glass: alpha (green channel) — clearer centre, dirt at the edges, rain streaks. */
  glassDirt(size = 256) {
    const n = tileNoise(size, 6, 4, 51), sp = tileNoise(size, 48, 1, 52);
    const c = mkCanvas(size, size), ctx = c.getContext('2d'), img = ctx.createImageData(size, size), d = img.data;
    const r = rng(53), streak = new Float32Array(size);
    for (let x = 0; x < size; x++) streak[x] = r() < 0.12 ? -0.15 * r() : 0;
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const k = y * size + x, ex = Math.min(x, size - 1 - x) / size, ey = Math.min(y, size - 1 - y) / size;
      const edge = Math.exp(-Math.min(ex, ey) * 14) * 0.45 + (y / size) * 0.18;
      let a = 0.26 + edge + 0.22 * (n[k] - 0.5) + streak[x] * (y / size) + (sp[k] > 0.8 ? 0.25 : 0);
      a = clamp01(a) * 255; const i = k * 4;
      d[i] = a; d[i + 1] = a; d[i + 2] = a; d[i + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    return { alpha: c };
  },
  /** Night sky with a hazy moon and a far tree / fence line (seen through the basement window). */
  sky(moonU, moonV) {
    const w = 512, h = 384, c = mkCanvas(w, h), ctx = c.getContext('2d');
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, '#05070d'); g.addColorStop(0.6, '#0d1220'); g.addColorStop(1, '#1b2232');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    const mx = moonU * w, my = (1 - moonV) * h;
    const glow = ctx.createRadialGradient(mx, my, 2, mx, my, 120);
    glow.addColorStop(0, 'rgba(150,170,205,0.55)'); glow.addColorStop(0.15, 'rgba(90,110,150,0.22)'); glow.addColorStop(1, 'rgba(40,50,80,0)');
    ctx.fillStyle = glow; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#e8edf5'; ctx.beginPath(); ctx.arc(mx, my, 6.5, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(160,170,185,0.35)'; ctx.beginPath(); ctx.arc(mx - 2, my + 1, 2.4, 0, Math.PI * 2); ctx.fill();
    // thin clouds
    const r = rng(61);
    for (let i = 0; i < 26; i++) {
      const x = r() * w, y = r() * h * 0.7, rw = 30 + r() * 90;
      const cg = ctx.createRadialGradient(x, y, 1, x, y, rw);
      cg.addColorStop(0, 'rgba(60,70,95,0.18)'); cg.addColorStop(1, 'rgba(60,70,95,0)');
      ctx.fillStyle = cg; ctx.fillRect(x - rw, y - rw, rw * 2, rw * 2);
    }
    // tree line + fence silhouettes at the bottom (horizon)
    ctx.fillStyle = '#040507';
    let x = 0; ctx.beginPath(); ctx.moveTo(0, h);
    while (x <= w) { ctx.lineTo(x, h - 14 - r() * 26 - (r() < 0.15 ? r() * 40 : 0)); x += 3 + r() * 5; }
    ctx.lineTo(w, h); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#07080b'; ctx.fillRect(0, h - 12, w, 12);
    for (let p = 0; p < w; p += 9) ctx.fillRect(p, h - 19, 5, 8);
    return c;
  },
  /** Cobweb (alpha in colour, white threads). */
  web(size = 256) {
    const c = mkCanvas(size, size), ctx = c.getContext('2d'), r = rng(71);
    ctx.strokeStyle = 'rgba(255,255,255,0.75)'; ctx.lineWidth = 0.9;
    const spokes = 9, ang = [];
    for (let i = 0; i < spokes; i++) ang.push((i / (spokes - 1)) * (Math.PI / 2) + (r() - 0.5) * 0.08);
    for (const a of ang) { ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.cos(a) * size * 1.1, Math.sin(a) * size * 1.1); ctx.stroke(); }
    ctx.lineWidth = 0.6;
    for (let rad = 14; rad < size * 0.95; rad += 9 + r() * 7) {
      ctx.beginPath();
      for (let i = 0; i < spokes; i++) {
        const rr = rad * (0.92 + r() * 0.12), x = Math.cos(ang[i]) * rr, y = Math.sin(ang[i]) * rr;
        if (i === 0) ctx.moveTo(x, y); else ctx.quadraticCurveTo(Math.cos((ang[i] + ang[i - 1]) / 2) * rr * 0.9, Math.sin((ang[i] + ang[i - 1]) / 2) * rr * 0.9, x, y);
      }
      ctx.stroke();
    }
    const fade = ctx.createRadialGradient(0, 0, size * 0.2, 0, 0, size);
    fade.addColorStop(0, 'rgba(0,0,0,0)'); fade.addColorStop(1, 'rgba(0,0,0,1)');
    ctx.globalCompositeOperation = 'destination-out'; ctx.fillStyle = fade; ctx.fillRect(0, 0, size, size);
    return c;
  },
  /** Water stain (ceiling) — brownish tide rings, transparent outside. */
  stain(size = 256) {
    const c = mkCanvas(size, size), ctx = c.getContext('2d'), n = tileNoise(size, 6, 3, 81);
    const img = ctx.createImageData(size, size), d = img.data, cx = size / 2;
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const k = y * size + x, dd = Math.hypot(x - cx, y - cx) / cx + (n[k] - 0.5) * 0.35;
      const ring = Math.exp(-((dd - 0.78) ** 2) / 0.0025) * 0.75 + Math.exp(-((dd - 0.55) ** 2) / 0.002) * 0.35;
      const fill = dd < 0.78 ? 0.22 * (1 - dd / 0.78) + 0.16 : 0;
      const a = clamp01(ring + fill) * (dd < 1 ? 1 : 0), i = k * 4;
      d[i] = 120; d[i + 1] = 86; d[i + 2] = 48; d[i + 3] = a * 255;
    }
    ctx.putImageData(img, 0, 0);
    return c;
  },
  /** Faded runner rug (hallway). */
  rug() {
    const w = 256, h = 512, c = mkCanvas(w, h), ctx = c.getContext('2d'), n = tileNoise(256, 8, 3, 91);
    ctx.fillStyle = '#6e2a22'; ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = '#c9a66b'; ctx.lineWidth = 6; ctx.strokeRect(14, 14, w - 28, h - 28);
    ctx.strokeStyle = '#2b3448'; ctx.lineWidth = 10; ctx.strokeRect(30, 30, w - 60, h - 60);
    for (let i = 0; i < 4; i++) {
      const y = 90 + i * 110;
      ctx.fillStyle = '#c9a66b'; ctx.beginPath(); ctx.moveTo(w / 2, y - 40); ctx.lineTo(w / 2 + 50, y); ctx.lineTo(w / 2, y + 40); ctx.lineTo(w / 2 - 50, y); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#2b3448'; ctx.beginPath(); ctx.moveTo(w / 2, y - 22); ctx.lineTo(w / 2 + 26, y); ctx.lineTo(w / 2, y + 22); ctx.lineTo(w / 2 - 26, y); ctx.closePath(); ctx.fill();
    }
    const img = ctx.getImageData(0, 0, w, h), d = img.data;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const v = 0.72 + 0.4 * n[(y % 256) * 256 + x], i = (y * w + x) * 4;
      d[i] = Math.min(255, d[i] * v + 18); d[i + 1] = Math.min(255, d[i + 1] * v + 14); d[i + 2] = Math.min(255, d[i + 2] * v + 10);
    }
    ctx.putImageData(img, 0, 0);
    return c;
  },
  /** Small framed landscape painting for the hallway. */
  painting() {
    const w = 256, h = 192, c = mkCanvas(w, h), ctx = c.getContext('2d');
    const g = ctx.createLinearGradient(0, 0, 0, h); g.addColorStop(0, '#9fb2b8'); g.addColorStop(0.55, '#e3cf9e'); g.addColorStop(1, '#5d6b3c');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#4f6a4a'; ctx.beginPath(); ctx.moveTo(0, 120); ctx.quadraticCurveTo(70, 80, 140, 115); ctx.quadraticCurveTo(200, 140, 256, 100); ctx.lineTo(256, 192); ctx.lineTo(0, 192); ctx.fill();
    ctx.fillStyle = '#7a5b3a'; ctx.fillRect(170, 92, 34, 26); ctx.fillStyle = '#5a2e22'; ctx.beginPath(); ctx.moveTo(166, 94); ctx.lineTo(187, 76); ctx.lineTo(208, 94); ctx.fill();
    const img = ctx.getImageData(0, 0, w, h), d = img.data;
    for (let i = 0; i < d.length; i += 4) { const gr = (d[i] + d[i + 1] + d[i + 2]) / 3; d[i] = gr * 0.35 + d[i] * 0.65 + 10; d[i + 1] = gr * 0.35 + d[i + 1] * 0.65 + 6; d[i + 2] = gr * 0.35 + d[i + 2] * 0.65 - 6; }
    ctx.putImageData(img, 0, 0);
    return c;
  },
  /** Pale construction lumber (spruce/pine), grain along U, a few knots. 1.2 m tile. */
  lumber(size = 512) {
    const n = tileNoise(size, 6, 4, 101), g2 = tileNoise(size, 128, 1, 102);
    const hgt = new Float32Array(size * size);
    const c = mkCanvas(size, size), ctx = c.getContext('2d'), img = ctx.createImageData(size, size), d = img.data;
    const r = rng(103), knots = [];
    for (let i = 0; i < 5; i++) knots.push([r() * size, r() * size, 4 + r() * 7]);
    const ringRow = new Float32Array(size);
    for (let y = 0; y < size;) { const w = 1 + Math.floor(r() * 2); for (let i = 0; i < w && y + i < size; i++) ringRow[y + i] = 0.5 + 0.5 * r(); y += w + 3 + Math.floor(r() * 9); }
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const k = y * size + x;
      // growth rings: thin dark lines along U, irregular spacing, gently wavy
      const gy = y + 6 * Math.sin(x * 0.009 + n[k] * 3) + 3 * n[((y >> 2) & (size - 1)) * size + (x & (size - 1))];
      const ring = ringRow[((Math.floor(gy) % size) + size) % size];
      const grain = ring * (0.6 + 0.4 * g2[k]);
      let kn = 0;
      for (const [kx, ky, kr] of knots) {
        let dx = Math.abs(x - kx); dx = Math.min(dx, size - dx); let dy = Math.abs(y - ky); dy = Math.min(dy, size - dy);
        const dd = Math.hypot(dx * 0.6, dy) / kr; if (dd < 2.2) kn = Math.max(kn, Math.exp(-dd * dd));
      }
      const v = (0.9 + 0.12 * n[k]) * (1 - 0.13 * grain) * (1 - 0.5 * kn);
      const i = k * 4;
      d[i] = 208 * v; d[i + 1] = 184 * v * (1 - 0.06 * kn); d[i + 2] = 142 * v * (1 - 0.15 * kn); d[i + 3] = 255;
      hgt[k] = 0.5 - 0.12 * grain - 0.3 * kn;
    }
    ctx.putImageData(img, 0, 0);
    return { map: c, normal: normalCanvas(hgt, size, 1.5) };
  },
  /** Corrugation normal map for the flexible foil dryer duct (ribs along U). */
  ribs() {
    const s = 64, h = new Float32Array(s * s);
    for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) h[y * s + x] = 0.5 + 0.5 * Math.sin((x / s) * Math.PI * 2) + 0.08 * Math.sin((y / s) * Math.PI * 6 + x * 0.3);
    return normalCanvas(h, s, 5);
  },
};

// ------------------------------------------------------------------------------------------------ geometry builder

const _p = new THREE.Vector3(), _nv = new THREE.Vector3(), _nm = new THREE.Matrix3();
const _U = new THREE.Vector3(), _V = new THREE.Vector3(), _N = new THREE.Vector3(), _D = new THREE.Vector3();
const _M4 = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _s = new THREE.Vector3(), _t = new THREE.Vector3();

/** Sorted break points in [a,b] with a regular step + extra refinements (always contains a and b). */
function brk(a, b, step = 0, extra = null) {
  const v = [];
  if (step > 0) { const n = Math.max(1, Math.round((b - a) / step)); for (let i = 1; i < n; i++) v.push(a + ((b - a) * i) / n); }
  if (extra) for (const e of extra) if (e > a + 0.006 && e < b - 0.006) v.push(e);
  v.sort((p, q) => p - q);
  const out = [a];
  for (const e of v) if (e - out[out.length - 1] > 0.006 && b - e > 0.006) out.push(e);
  out.push(b);
  return out;
}
const EDGE = [0.025, 0.07, 0.15, 0.3];
function edgeRefine(a, b) { const r = []; for (const e of EDGE) r.push(a + e, b - e); return r; }

/** Accumulates indexed triangles (position, normal, uv in meters, colour) for one material. */
class MB {
  constructor() { this.pos = []; this.nor = []; this.uv = []; this.col = []; this.idx = []; }
  get count() { return this.pos.length / 3; }
  _push(x, y, z, nx, ny, nz, u, v, c) {
    this.pos.push(x, y, z); this.nor.push(nx, ny, nz); this.uv.push(u, v);
    if (typeof c === 'number') this.col.push(c, c, c); else this.col.push(c[0], c[1], c[2]);
  }
  /** Planar grid. o origin, U/V unit axes (normal = U x V), su/sv break points in meters along U/V.
   *  opt.pos(s,t) -> [x,y,z] deforms the grid inside its plane; opt.color(x,y,z,s,t) -> number | [r,g,b]. */
  grid(o, U, V, su, sv, opt = {}) {
    const nx = U[1] * V[2] - U[2] * V[1], ny = U[2] * V[0] - U[0] * V[2], nz = U[0] * V[1] - U[1] * V[0];
    const base = this.count, nu = su.length, nvv = sv.length, pf = opt.pos, cf = opt.color;
    const uo = opt.uo || 0, vo = opt.vo || 0;
    for (let j = 0; j < nvv; j++) for (let i = 0; i < nu; i++) {
      let x, y, z;
      if (pf) { const p = pf(su[i], sv[j]); x = p[0]; y = p[1]; z = p[2]; }
      else {
        x = o[0] + U[0] * su[i] + V[0] * sv[j]; y = o[1] + U[1] * su[i] + V[1] * sv[j]; z = o[2] + U[2] * su[i] + V[2] * sv[j];
      }
      const u = x * U[0] + y * U[1] + z * U[2] + uo, v = x * V[0] + y * V[1] + z * V[2] + vo;
      this._push(x, y, z, nx, ny, nz, u, v, typeof cf === 'function' ? cf(x, y, z, su[i], sv[j]) : (cf ?? 1));
    }
    for (let j = 0; j < nvv - 1; j++) for (let i = 0; i < nu - 1; i++) {
      const a = base + j * nu + i; this.idx.push(a, a + 1, a + nu + 1, a, a + nu + 1, a + nu);
    }
  }
  /** Rectangular face [0,lu]x[0,lv] with an optional rectangular hole [s0,s1,t0,t1] (may touch the border). */
  face(o, U, V, lu, lv, opt = {}) {
    const st = opt.step ?? 0.5, vs = opt.vstep ?? 0.5;
    const eu = [...(opt.uEdges || edgeRefine(0, lu))], ev = opt.vEdges || edgeRefine(0, lv);
    const h = opt.hole;
    if (h) for (const e of [0.03, 0.1, 0.25]) eu.push(h[0] - e, h[1] + e);
    const piece = (s0, s1, t0, t1) => {
      if (s1 - s0 < 1e-4 || t1 - t0 < 1e-4) return;
      this.grid(o, U, V, brk(s0, s1, st, eu), brk(t0, t1, vs, ev), opt);
    };
    if (!h) { piece(0, lu, 0, lv); return; }
    piece(0, h[0], 0, lv); piece(h[1], lu, 0, lv); piece(h[0], h[1], 0, h[2]); piece(h[0], h[1], h[3], lv);
  }
  /** Axis-aligned box. opt.faces: array of 'px','nx','py','ny','pz','nz' (default all). */
  box(a, b, opt = {}) {
    const [x0, y0, z0] = a, [x1, y1, z1] = b, f = opt.faces || ['px', 'nx', 'py', 'ny', 'pz', 'nz'], st = opt.step || 0;
    const dx = x1 - x0, dy = y1 - y0, dz = z1 - z0, r = (l) => brk(0, l, st);
    if (f.includes('px')) this.grid([x1, y0, z1], [0, 0, -1], [0, 1, 0], r(dz), r(dy), opt);
    if (f.includes('nx')) this.grid([x0, y0, z0], [0, 0, 1], [0, 1, 0], r(dz), r(dy), opt);
    if (f.includes('py')) this.grid([x0, y1, z1], [1, 0, 0], [0, 0, -1], r(dx), r(dz), opt);
    if (f.includes('ny')) this.grid([x0, y0, z0], [1, 0, 0], [0, 0, 1], r(dx), r(dz), opt);
    if (f.includes('pz')) this.grid([x0, y0, z1], [1, 0, 0], [0, 1, 0], r(dx), r(dy), opt);
    if (f.includes('nz')) this.grid([x1, y0, z0], [-1, 0, 0], [0, 1, 0], r(dx), r(dy), opt);
  }
  /** Append any BufferGeometry transformed by matrix m. opt.uvScale (number|[u,v]), opt.worldUV, opt.color. */
  geo(g, m, opt = {}) {
    const P = g.attributes.position, Nn = g.attributes.normal, UV = g.attributes.uv;
    _nm.getNormalMatrix(m); const flip = m.determinant() < 0;
    const base = this.count, cf = opt.color, us = opt.uvScale ?? 1;
    const su = Array.isArray(us) ? us[0] : us, sv = Array.isArray(us) ? us[1] : us;
    for (let i = 0; i < P.count; i++) {
      _p.fromBufferAttribute(P, i).applyMatrix4(m);
      _nv.fromBufferAttribute(Nn, i).applyMatrix3(_nm).normalize();
      let u, v;
      if (opt.worldUV) {
        const ax = Math.abs(_nv.x), ay = Math.abs(_nv.y), az = Math.abs(_nv.z);
        if (ax >= ay && ax >= az) { u = _p.z; v = _p.y; } else if (ay >= az) { u = _p.x; v = _p.z; } else { u = _p.x; v = _p.y; }
      } else { u = UV ? UV.getX(i) * su : 0; v = UV ? UV.getY(i) * sv : 0; }
      this._push(_p.x, _p.y, _p.z, _nv.x, _nv.y, _nv.z, u, v, typeof cf === 'function' ? cf(_p.x, _p.y, _p.z) : (cf ?? 1));
    }
    if (g.index) {
      for (let i = 0; i < g.index.count; i += 3) {
        const a = base + g.index.getX(i), b = base + g.index.getX(i + 1), c = base + g.index.getX(i + 2);
        if (flip) this.idx.push(a, c, b); else this.idx.push(a, b, c);
      }
    } else {
      for (let i = 0; i < P.count; i += 3) {
        if (flip) this.idx.push(base + i, base + i + 2, base + i + 1); else this.idx.push(base + i, base + i + 1, base + i + 2);
      }
    }
  }
  build() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.setIndex(this.idx);
    g.computeBoundingSphere(); g.computeBoundingBox();
    return g;
  }
}

/** Matrix from position + euler (+ scale). */
function M(x, y, z, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) {
  _e.set(rx, ry, rz, 'XYZ'); _q.setFromEuler(_e); _t.set(x, y, z); _s.set(sx, sy, sz);
  return new THREE.Matrix4().compose(_t, _q, _s);
}
function shapeOf(pts) {
  const s = new THREE.Shape(); s.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) s.lineTo(pts[i][0], pts[i][1]);
  s.closePath(); return s;
}
/** Extrude a closed 2D profile (u across, v out) along the straight run start->end. U,V world dirs ⟂ run. */
function runProfile(mb, pts, start, end, U, V, opt = {}) {
  _D.set(end[0] - start[0], end[1] - start[1], end[2] - start[2]);
  const len = _D.length(); _D.normalize();
  _U.fromArray(U).normalize(); _V.fromArray(V).normalize(); _N.crossVectors(_U, _V);
  const o = _N.dot(_D) >= 0 ? start : end;
  // steps: no long sliver quads (they break depth interpolation when they cross the camera plane)
  const g = new THREE.ExtrudeGeometry(shapeOf(pts), { depth: len, bevelEnabled: false, curveSegments: 2, steps: Math.max(1, Math.ceil(len / 0.5)) });
  _M4.makeBasis(_U, _V, _N).setPosition(o[0], o[1], o[2]);
  mb.geo(g, _M4, opt); g.dispose();
}
/** Insert points so that no contour edge is longer than maxLen. */
function densify(pts, maxLen = 0.4) {
  const out = [];
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i], b = pts[(i + 1) % pts.length], n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / maxLen));
    for (let k = 0; k < n; k++) out.push([a[0] + ((b[0] - a[0]) * k) / n, a[1] + ((b[1] - a[1]) * k) / n]);
  }
  return out;
}
/** Extrude a flat polygon lying on a plane (u,v coords) by depth along n (= U x V). */
function plate(mb, pts, origin, U, V, depth, opt = {}) {
  _U.fromArray(U); _V.fromArray(V); _N.crossVectors(_U, _V);
  const g = new THREE.ExtrudeGeometry(shapeOf(densify(pts)), {
    depth, bevelEnabled: !!opt.bevel, bevelThickness: opt.bevel || 0, bevelSize: opt.bevel || 0, bevelSegments: 1, curveSegments: 2,
  });
  _M4.makeBasis(_U, _V, _N).setPosition(origin[0], origin[1], origin[2]);
  mb.geo(g, _M4, opt); g.dispose();
}
/** Recessed panel: concentric rectangles [inset, z] from the opening (ring 0) to the field (last ring). */
function pocketGeo(w, h, rings) {
  const P = [], quad = (a, c1, c2, d) => P.push(...a, ...c1, ...c2, ...a, ...c2, ...d);
  const rect = ([ins, z]) => [[-w / 2 + ins, -h / 2 + ins, z], [w / 2 - ins, -h / 2 + ins, z], [w / 2 - ins, h / 2 - ins, z], [-w / 2 + ins, h / 2 - ins, z]];
  for (let i = 0; i < rings.length - 1; i++) {
    const A = rect(rings[i]), B2 = rect(rings[i + 1]);
    for (let e = 0; e < 4; e++) { const f = (e + 1) % 4; quad(A[e], A[f], B2[f], B2[e]); }
  }
  const F = rect(rings[rings.length - 1]); quad(F[0], F[1], F[2], F[3]);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(P, 3));
  const uv = []; for (let i = 0; i < P.length; i += 3) uv.push(P[i], P[i + 1]);
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.computeVertexNormals();
  return g;
}
/** Door knob (rosette + neck + ball) lathe, axis +Y, base at y=0. */
function knobGeo(scale = 1) {
  const p = [[0, 0], [0.032, 0], [0.032, 0.004], [0.029, 0.007], [0.012, 0.009], [0.0105, 0.03], [0.016, 0.036],
    [0.024, 0.042], [0.028, 0.051], [0.027, 0.061], [0.021, 0.069], [0.011, 0.074], [0, 0.0755]];
  return new THREE.LatheGeometry(p.map(([r, y]) => new THREE.Vector2(r * scale, y * scale)), 20);
}

// ------------------------------------------------------------------------------------------------ colour (grime) functions

/** Painted wall grime: dust line on the floor, corner AO, ceiling line, mottling, low smudges, hand marks. */
function wallColor({ floor = 0, floorFn = null, ceil = H, len = 0, ao0 = true, ao1 = true, tint = [1, 1, 1], grime = 1, seed = 0, marks = null }) {
  return (x, y, z, s) => {
    const fy = floorFn ? floorFn(x, z) : floor;
    const h = Math.max(0, y - fy), hc = Math.max(0, ceil - y);
    let c = 1 - grime * (0.17 * Math.exp(-h / 0.08) + 0.07 * Math.exp(-h / 0.5));
    c *= 1 - 0.13 * Math.exp(-hc / 0.12);
    if (ao0) c *= 1 - 0.16 * Math.exp(-s / 0.13);
    if (ao1) c *= 1 - 0.16 * Math.exp(-Math.max(0, len - s) / 0.13);
    c *= 0.94 + 0.11 * fbm(x * 0.8 + seed, y * 0.8 + seed * 0.3, z * 0.8, 3);
    const sm = fbm(x * 2.3 + 7 + seed, y * 1.7, z * 2.3 + 3, 2);
    if (h < 1.2 && sm > 0.6) c *= 1 - grime * (sm - 0.6) * 0.8 * (1 - h / 1.2);
    if (marks) for (const m of marks) {
      const d2 = (x - m[0]) ** 2 + ((y - m[1]) * 0.7) ** 2 + (z - m[2]) ** 2;
      c *= 1 - m[4] * Math.exp(-d2 / (m[3] * m[3]));
    }
    return [c * tint[0], c * tint[1], c * tint[2]];
  };
}
function trimColor(dirt = 0.1, seed = 3) {
  return (x, y, z) => {
    let c = 1 - dirt * fbm(x * 3 + seed, y * 3, z * 3, 2);
    c *= 1 - 0.07 * Math.exp(-Math.max(0, y % 2.75) / 0.03); // dust where trims meet a floor
    return c;
  };
}

// ------------------------------------------------------------------------------------------------ Architecture

// Mesh flags per material key. Large surfaces only receive (thick invisible boxes cast for them).
// Perf: small hardware (brass: brackets, valves, threshold strip) and the nook ceiling services (copper pipes, galvanized
// duct / conduits / straps, above the reach of the ceiling light) don't cast into the shadow maps.
const HALLK = { cast: false, receive: false, hall: true };
const KEY_OPTS = {
  trim: { cast: true }, trimStair: { cast: true }, wood: { cast: true }, brass: { cast: false }, iron: { cast: true },
  closetWood: { cast: true }, nookWood: { cast: true }, copper: { cast: false }, galv: { cast: false }, pvc: { cast: true }, foil: { cast: true },
  sky: { cast: false, receive: false },
  hallWall: HALLK, hallFloor: HALLK, hallCeil: HALLK, hallTrim: HALLK, hallWood: HALLK, hallFabric: HALLK, hallBrass: HALLK,
};
// Perf (texture memory / load): some keys reuse a texture loaded for another tile size; their world-metre UVs are
// scaled so the on-screen tiling is unchanged. ratio = (wanted repeat) / (repeat of the shared texture).
const UV_SCALE = {
  nookDrywall: 1.5 / 1.8, closetWall: 1.5 / 1.8,   // white_stucco set: 1.8 m tile, shared with the ceiling (1.5 m)
  trim: 3, trimStair: 3, hallTrim: 3,               // white_stucco normal: 0.5 m tile (repeat 2) from the 1.5 m set
  hallWall: 2.2 / 1.5,                              // beige_wall_001 normal: 1.5 m tile, shared with the walls (2.2 m)
};
function scaleUV(g, k) {
  if (!k || k === 1) return g;
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * k, uv.getY(i) * k);
  uv.needsUpdate = true;
  return g;
}

export class Architecture {
  constructor(game, world) {
    this.game = game;
    this.world = world;
    this.root = new THREE.Group(); this.root.name = 'architecture';
    // The hall stays visible until the first update() so renderer.warmup() compiles its materials (no hitch when the
    // door first opens); after that it is shown only while the door is open.
    this.hall = new THREE.Group(); this.hall.name = 'upperHall'; this.hall.visible = true; this._hallWarm = true;
    this.doors = [];
    this.upstairsDoorOpen = 0;
    this.zoneMaterials = [];
    this._B = new Map();
  }

  async build() {
    const scene = this.game.scene;
    this._materials();
    this._occMat = new THREE.MeshBasicMaterial({ visible: false, side: THREE.DoubleSide });
    // The caster boxes only matter in the shadow passes. In the colour passes they are drawn after the opaque scene
    // (renderOrder 10) with a strict depth test: their faces lie on or behind the visible surfaces, so early-z rejects
    // nearly every fragment (they used to be drawn first, i.e. one invisible full-screen layer of fragments per frame).
    // Same program as before (depthFunc is GL state, not a shader feature); the shadow passes are unchanged.
    this._casterMat = new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false, depthFunc: THREE.LessDepth });
    this._casterMat.name = 'shadowCaster';
    this._unitBox = new THREE.BoxGeometry(1, 1, 1);
    this.occGroup = new THREE.Group(); this.occGroup.name = 'occluders';
    this.root.add(this.occGroup, this.hall);
    this.caster = new MB();

    this._floors();
    this._ceilings();
    this._walls();
    this._stairs();
    this._railing();
    this._closet();
    this._nook();
    this._window();
    this._outside();
    this._trims();
    this._details();
    this._hallway();
    this._solids();
    this._flush();
    this._upstairsDoor();
    this._closetDoor();

    scene.add(this.root);
    this.root.updateMatrixWorld(true);
  }

  // ---------------------------------------------------------------------------------------------- materials

  _materials() {
    const A = this.game.assets;
    const aniso = Math.min(8, this.game.renderer?.maxAnisotropy || 4);
    const TSZ = this.game.renderer?.quality === 'low' ? 256 : 512; // procedural texture size (phones: faster load, less VRAM)
    const rep = (m) => [1 / m, 1 / m];
    const zone = (mat, z) => { mat.userData.envZone = z; this.zoneMaterials.push({ mat, zone: z }); return mat; };
    const tex = (path, m, srgb = false) => A.texture(path, { srgb, repeat: rep(m) });
    const mats = {};
    // Shader programs: a material without a colour map compiles its own program variant. Giving the few map-less ones a
    // 1x1 white map (colour x 1 = unchanged) lets them share the program of their textured siblings (trim -> nook block,
    // foil -> ground, hall curtains -> picture artwork): fewer programs to compile on phones, identical pixels.
    const white = new THREE.DataTexture(new Uint8Array([255, 255, 255, 255]), 1, 1);
    white.colorSpace = THREE.SRGBColorSpace; white.needsUpdate = true; white.name = 'white1x1';
    this._white = white;

    // Painted drywall: the greige scan lifted to a warm cream eggshell paint.
    mats.wall = A.pbr('beige_wall_001', rep(2.2), { vertexColors: true });
    mats.wall.color.setRGB(1.5, 1.6, 1.36);
    mats.wall.normalScale.set(0.7, 0.7); mats.wall.aoMapIntensity = 0.4;
    mats.wallStair = zone(mats.wall.clone(), 0.85);

    // Knockdown ceiling: white stucco albedo + knockdown relief.
    mats.ceil = A.pbr('white_stucco', rep(1.5), { vertexColors: true });
    mats.ceil.normalMap = tex('textures/ceiling_interior/normal.jpg', 1.1);
    mats.ceil.aoMap = tex('textures/ceiling_interior/ao.jpg', 1.1);
    mats.ceil.color.setRGB(0.93, 0.9, 0.8); mats.ceil.normalScale.set(0.55, 0.55); mats.ceil.aoMapIntensity = 0.5;
    mats.ceilStair = zone(mats.ceil.clone(), 0.7);

    mats.carpet = A.pbr('carpet016', rep(1.0), { vertexColors: true });
    mats.carpet.color.setRGB(0.9, 0.87, 0.82); mats.carpet.normalScale.set(1.1, 1.1);
    mats.carpetStair = zone(mats.carpet.clone(), 0.85);

    // White semi-gloss trim paint (slightly yellowed), subtle brush texture (white_stucco normal, 0.5 m tile: the 1.5 m
    // texture of the ceiling set with x3 UVs, see UV_SCALE).
    mats.trim = new THREE.MeshStandardMaterial({
      color: 0xe6dfd0, roughness: 0.36, metalness: 0, vertexColors: true, map: white,
      normalMap: tex('textures/white_stucco/normal.jpg', 1.5), normalScale: new THREE.Vector2(0.18, 0.18),
    });
    mats.trimStair = zone(mats.trim.clone(), 0.85);
    mats.doorPaint = zone(mats.trim.clone(), 0.8);

    // stained pine: colour + normal only (built by hand so the unused rough / ao images are never loaded)
    mats.wood = new THREE.MeshStandardMaterial({
      map: tex('textures/stained_pine/color.jpg', 1.2, true), normalMap: tex('textures/stained_pine/normal.jpg', 1.2),
      aoMapIntensity: 0.8, roughness: 0.4, metalness: 0, vertexColors: true,
    });
    mats.wood.name = 'stained_pine'; mats.wood.color.setRGB(0.82, 0.78, 0.74);

    mats.brass = new THREE.MeshStandardMaterial({ color: 0xb08a45, metalness: 1, roughness: 0.32 });
    mats.iron = new THREE.MeshStandardMaterial({ color: 0x3a2f27, metalness: 0.55, roughness: 0.72, vertexColors: true });

    // Unfinished closet / nook.
    const block = ProcTex.block(TSZ), conc = ProcTex.concrete(TSZ);
    const blockMap = canvasTex(block.map, { repeat: rep(1.6), aniso }), blockN = canvasTex(block.normal, { srgb: false, repeat: rep(1.6), aniso });
    const concMap = canvasTex(conc.map, { repeat: rep(2), aniso }), concN = canvasTex(conc.normal, { srgb: false, repeat: rep(2), aniso });
    mats.nookBlock = zone(new THREE.MeshStandardMaterial({ map: blockMap, normalMap: blockN, roughness: 0.88, vertexColors: true }), 0.45);
    mats.closetBlock = zone(mats.nookBlock.clone(), 0.12);
    mats.nookFloor = zone(new THREE.MeshStandardMaterial({ map: concMap, normalMap: concN, roughness: 0.7, vertexColors: true }), 0.45);
    mats.closetFloor = zone(mats.nookFloor.clone(), 0.12);
    // 1.8 m tile from the ceiling's 1.5 m white_stucco textures (shared, UV_SCALE): no second copy of the set
    mats.nookDrywall = zone(A.pbr('white_stucco', rep(1.5), { vertexColors: true }), 0.45);
    mats.nookDrywall.color.setRGB(0.78, 0.77, 0.74); mats.nookDrywall.normalScale.set(0.4, 0.4);
    mats.closetWall = zone(mats.nookDrywall.clone(), 0.12); mats.closetWall.color.setRGB(0.62, 0.57, 0.5); // drywall back paper
    const lum = ProcTex.lumber(TSZ);
    mats.nookWood = zone(new THREE.MeshStandardMaterial({
      map: canvasTex(lum.map, { repeat: rep(1.2), aniso }), normalMap: canvasTex(lum.normal, { srgb: false, repeat: rep(1.2), aniso }),
      roughness: 0.88, vertexColors: true,
    }), 0.4);
    mats.closetWood = zone(mats.nookWood.clone(), 0.12);
    mats.copper = zone(new THREE.MeshStandardMaterial({ color: 0x9a5a38, metalness: 1, roughness: 0.42 }), 0.45);
    mats.galv = zone(new THREE.MeshStandardMaterial({ color: 0x9da2a4, metalness: 0.9, roughness: 0.5, vertexColors: true }), 0.45);
    mats.pvc = zone(new THREE.MeshStandardMaterial({ color: 0x141414, roughness: 0.55 }), 0.45);
    const ribs = canvasTex(ProcTex.ribs(), { srgb: false, repeat: [1, 1], aniso });
    ribs.wrapS = ribs.wrapT = THREE.RepeatWrapping;
    mats.foil = zone(new THREE.MeshStandardMaterial({ color: 0xc4c6c8, metalness: 1, roughness: 0.33, map: white, normalMap: ribs, normalScale: new THREE.Vector2(1.2, 1.2) }), 0.45);

    // Window + outside.
    const dirt = ProcTex.glassDirt(256);
    mats.glass = new THREE.MeshStandardMaterial({
      color: 0x8d9790, roughness: 0.22, metalness: 0, transparent: true, depthWrite: false,
      alphaMap: canvasTex(dirt.alpha, { srgb: false }), emissive: 0x0b1018, emissiveIntensity: 1,
    });
    const gr = ProcTex.ground(512);
    mats.ground = new THREE.MeshStandardMaterial({
      map: canvasTex(gr.map, { repeat: rep(3), aniso }), normalMap: canvasTex(gr.normal, { srgb: false, repeat: rep(3), aniso }),
      roughness: 0.95, emissive: 0x070a10, envMapIntensity: 0,
    });
    zone(mats.ground, 0.0);
    // grass blades: single-sided material, the blades carry explicit back faces (_outside) — same pixels as DoubleSide,
    // and the program is shared with the other vertex-coloured materials (iron, galvanized)
    mats.grass = zone(new THREE.MeshStandardMaterial({ color: 0x7c6c4a, roughness: 0.9, vertexColors: true }), 0.0);
    mats.snow = zone(new THREE.MeshStandardMaterial({ color: 0xdfe5ee, roughness: 0.85, emissive: 0x0c1220 }), 0.0);
    // sky: unlit, dim. moon direction from the window, see Lighting MOON_POS. (`fog` left at its default: the scene has
    // no fog, and the flag shares the program with the other unlit textured materials.)
    mats.sky = new THREE.MeshBasicMaterial({ map: canvasTex(ProcTex.sky(0.36, 0.77)) });
    mats.sky.color.setRGB(0.55, 0.55, 0.6);

    mats.stain = new THREE.MeshStandardMaterial({
      map: canvasTex(ProcTex.stain()), transparent: true, depthWrite: false, roughness: 0.95,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, opacity: 0.55,
    });
    // cobwebs: one merged mesh with explicit back faces (see _flushWebs) instead of 3 double-sided transparent quads
    // (three.js draws those twice each, with 2 extra programs); same program as the window glass
    mats.web = new THREE.MeshStandardMaterial({
      color: 0xd8d8d0, alphaMap: canvasTex(ProcTex.web(), { srgb: false }), transparent: true, depthWrite: false,
      roughness: 0.8, opacity: 0.55,
    });
    mats.domeOff = new THREE.MeshStandardMaterial({ color: 0xd9d3c4, roughness: 0.35, metalness: 0 });

    // Upstairs hallway (warm, lived-in; only visible when the door opens).
    const wp = ProcTex.wallpaper(512);
    // normal map: the walls' beige_wall_001 normal (2.2 m tile) reused for a 1.5 m tile via x(2.2/1.5) UVs (UV_SCALE);
    // the wallpaper repeat is divided by the same factor so its 0.53 m pattern is unchanged
    const kHall = UV_SCALE.hallWall;
    mats.hallWall = zone(new THREE.MeshStandardMaterial({
      map: canvasTex(wp.map, { repeat: [1 / 0.53 / kHall, 1 / 0.53 / kHall], aniso }), roughness: 0.8, vertexColors: true,
      normalMap: tex('textures/beige_wall_001/normal.jpg', 2.2), normalScale: new THREE.Vector2(0.5, 0.5),
    }), 0.3);
    mats.hallFloor = zone(A.pbr('wood_floor_worn', rep(1.4), { vertexColors: true }), 0.3);
    mats.hallFloor.roughness = 0.55; mats.hallFloor.color.setRGB(0.8, 0.7, 0.6);
    mats.hallCeil = zone(mats.ceil.clone(), 0.3);
    mats.hallTrim = zone(mats.trim.clone(), 0.3);
    mats.hallWood = zone(mats.wood.clone(), 0.3);
    mats.hallGlow = new THREE.MeshStandardMaterial({ color: 0xf3e6cc, emissive: 0xffc98a, emissiveIntensity: 9, roughness: 0.4 });
    mats.hallNight = new THREE.MeshBasicMaterial({ color: 0x0f1a2c });
    mats.hallFabric = zone(new THREE.MeshStandardMaterial({ color: 0x8e665c, roughness: 0.92, side: THREE.DoubleSide, map: white }), 0.3);
    mats.hallRug = zone(new THREE.MeshStandardMaterial({ map: canvasTex(ProcTex.rug(), { aniso }), roughness: 0.95 }), 0.3);
    mats.hallArt = zone(new THREE.MeshStandardMaterial({ map: canvasTex(ProcTex.painting(), { aniso }), roughness: 0.6 }), 0.3);
    mats.hallBrass = zone(mats.brass.clone(), 0.3);

    for (const [k, m] of Object.entries(mats)) if (!m.name) m.name = k;
    this.mats = mats;
  }

  /** Builder for a material key (mesh flags come from KEY_OPTS). */
  B(key) {
    let b = this._B.get(key);
    if (!b) { b = new MB(); this._B.set(key, b); }
    return b;
  }

  _flush() {
    for (const [key, b] of this._B) {
      if (!b.idx.length) continue;
      const o = KEY_OPTS[key] || {};
      const mesh = new THREE.Mesh(scaleUV(b.build(), UV_SCALE[key]), this.mats[key]);
      mesh.name = `arch_${key}`;
      mesh.castShadow = !!o.cast;
      mesh.receiveShadow = o.receive !== false;
      (o.hall ? this.hall : this.root).add(mesh);
    }
    this._flushWebs();
    // invisible thick shadow casters (rendered only into shadow maps)
    const cm = new THREE.Mesh(this.caster.build(), this._casterMat);
    cm.name = 'arch_shadowCasters'; cm.castShadow = true; cm.receiveShadow = false; cm.renderOrder = 10;
    this.root.add(cm);
    this._B.clear();
  }

  // ---------------------------------------------------------------------------------------------- floors & ceilings

  _floors() {
    const segs = [ // obstacles that collect dust at their foot (x0,z0,x1,z1)
      [X0, Z0, X1, Z0], [X0, Z1, X1, Z1], [X1, Z0, X1, Z1], [KX1, Z0, KX1, S.bottomZ], [X0, S.bottomZ, X0, Z1], [X0, S.bottomZ, KX1, S.bottomZ],
    ];
    const lanes = [[-3.0, 2.1, -1.6, 1.55], [-1.6, 1.55, 0.25, 1.45], [0.25, 1.45, 1.3, -0.5], [1.3, -0.5, 1.35, -2.75], [-1.6, 1.55, -2.0, -1.6], [0.25, 1.45, 1.6, 1.2]];
    const segDist = (x, z, s) => {
      const dx = s[2] - s[0], dz = s[3] - s[1], l2 = dx * dx + dz * dz;
      const t = l2 > 0 ? clamp01(((x - s[0]) * dx + (z - s[1]) * dz) / l2) : 0;
      return Math.hypot(x - s[0] - dx * t, z - s[1] - dz * t);
    };
    const col = (x, y, z) => {
      let dw = 9; for (const s of segs) dw = Math.min(dw, segDist(x, z, s));
      let c = 1 - 0.3 * Math.exp(-dw / 0.05) - 0.08 * Math.exp(-dw / 0.35);
      c *= 0.86 + 0.2 * fbm(x * 1.2 + 3.1, 0.5, z * 1.2, 4);
      const st = fbm(x * 2.6 + 11, 1.7, z * 2.6, 3); if (st > 0.58) c *= 1 - (st - 0.58) * 1.7;
      let dl = 9; for (const s of lanes) dl = Math.min(dl, segDist(x, z, s));
      c *= 1 - 0.09 * Math.exp(-(dl * dl) / 0.1);
      return [c, c * 0.985, c * 0.965];
    };
    const B = this.B('carpet');
    const ref = edgeRefine(0, KX1 - X0);
    // A: main area east of the knee wall, B: in front of the first step
    B.grid([KX1, 0, Z1], [1, 0, 0], [0, 0, -1], brk(0, X1 - KX1, 0.25, [...edgeRefine(0, X1 - KX1)]), brk(0, Z1 - Z0, 0.25, [...edgeRefine(0, Z1 - Z0)]), { color: col });
    B.grid([X0, 0, Z1], [1, 0, 0], [0, 0, -1], brk(0, KX1 - X0, 0.25, ref), brk(0, Z1 - S.bottomZ, 0.25, edgeRefine(0, Z1 - S.bottomZ)), { color: col });

    // carpet → concrete transition strip at the nook doorway
    this.B('brass').box([AD0, 0, Z0 - 0.025], [AD1, 0.008, Z0 + 0.02], { faces: ['py', 'pz', 'nz'] });

    const concCol = (x0, x1, z0, z1, amb = 0.35) => (x, y, z) => {
      const dw = Math.min(x - x0, x1 - x, z - z0, z1 - z);
      let c = 1 - amb * Math.exp(-Math.max(0, dw) / 0.12);
      c *= 0.85 + 0.25 * fbm(x * 0.9 + 5, 2, z * 0.9, 3);
      return c;
    };
    const nf = this.B('nookFloor');
    nf.grid([AL.minX, 0, ZN], [1, 0, 0], [0, 0, -1], brk(0, AL.maxX - AL.minX, 0.4, edgeRefine(0, AL.maxX - AL.minX)), brk(0, ZN - NN, 0.4, edgeRefine(0, ZN - NN)), { color: concCol(AL.minX, AL.maxX, NN, ZN) });
    nf.grid([AD0, 0, Z0], [1, 0, 0], [0, 0, -1], brk(0, AD1 - AD0), brk(0, TP), { color: 0.92 });
    // closet floor
    this.B('closetFloor').grid([X0, 0, CL.maxZ], [1, 0, 0], [0, 0, -1], brk(0, KX0 - X0, 0.3, edgeRefine(0, KX0 - X0)), brk(0, CL.maxZ - Z0, 0.3, edgeRefine(0, CL.maxZ - Z0)), { color: concCol(X0, KX0, Z0, CL.maxZ, 0.45) });
  }

  _ceilings() {
    const fan = L.FAN;
    const col = (xa, xb, za, zb) => (x, y, z) => {
      const dw = Math.min(x - xa, xb - x, z - za, zb - z);
      let c = 1 - 0.2 * Math.exp(-Math.max(0, dw) / 0.12);
      c *= 0.95 + 0.08 * fbm(x * 0.7 + 1, 4, z * 0.7, 3);
      const df = Math.hypot(x - fan.x, z - fan.z);
      c *= 1 - 0.06 * Math.exp(-((df - 0.9) ** 2) / 0.08); // dust ring around the fan
      c *= 1 - 0.45 * Math.exp(-(df * df) / 0.05);          // the motor housing shades the ceiling mount
      return [c, c * 0.99, c * 0.96];
    };
    const B = this.B('ceil');
    // grid with U=(1,0,0), V=(0,0,1) faces down
    const ring = (c0, o) => [0, 0.06, 0.13, 0.21, 0.3, 0.42, 0.6, 0.8, 1.0].flatMap((r) => [c0 - o + r, c0 - o - r]);
    B.grid([KX1, H, Z0], [1, 0, 0], [0, 0, 1], brk(0, X1 - KX1, 0.4, [...edgeRefine(0, X1 - KX1), ...ring(fan.x, KX1)]), brk(0, Z1 - Z0, 0.4, [...edgeRefine(0, Z1 - Z0), ...ring(fan.z, Z0)]), { color: col(KX1 - 9, X1, Z0, Z1) });
    B.grid([X0, H, BZ1], [1, 0, 0], [0, 0, 1], brk(0, KX1 - X0, 0.4, edgeRefine(0, KX1 - X0)), brk(0, Z1 - BZ1, 0.4, edgeRefine(0, Z1 - BZ1)), { color: col(X0, X1, BZ1 - 9, Z1) });
    // drywall bulkhead around the stair opening (south edge) + underside of the stairwell east wall
    B.grid([X0, BY, BZ0], [1, 0, 0], [0, 0, 1], brk(0, KX1 - X0), brk(0, BZ1 - BZ0), { color: 0.93 });
    B.grid([KX0, H, KZS], [1, 0, 0], [0, 0, 1], brk(0, KX1 - KX0), brk(0, BZ0 - KZS, 0.4), { color: 0.95 });
    const wc = wallColor({ floor: 0, ceil: H, ao0: false, ao1: false });
    this.B('wall').grid([X0, BY, BZ1], [1, 0, 0], [0, 1, 0], brk(0, KX1 - X0, 0.3), brk(0, H - BY), { color: wc });
    this.B('wall').grid([KX1, BY, BZ1], [0, 0, -1], [0, 1, 0], brk(0, BZ1 - BZ0), brk(0, H - BY), { color: 0.9 }); // bulkhead end
    // stairwell ceiling
    this.B('ceilStair').grid([X0, TOP, Z0], [1, 0, 0], [0, 0, 1], brk(0, KX0 - X0, 0, edgeRefine(0, KX0 - X0)), brk(0, BZ0 - Z0, 0.4, edgeRefine(0, BZ0 - Z0)), { color: col(X0, KX0, Z0, BZ0) });
    // water stain on the ceiling near the window
    const st = new THREE.Mesh(new THREE.PlaneGeometry(0.75, 0.62), this.mats.stain);
    st.rotation.x = Math.PI / 2; st.position.set(2.85, H - 0.002, 2.25); st.rotation.z = 0.7; st.receiveShadow = true;
    this.root.add(st);
  }

  // ---------------------------------------------------------------------------------------------- walls

  _walls() {
    const VE = [0.02, 0.05, 0.1, 0.18, 0.3, 0.5, 0.8, 1.2, H - 0.3, H - 0.14, H - 0.05, H - 0.02];
    const W = this.B('wall'), WS = this.B('wallStair');
    const face = (b, o, U, V, lu, lv, extra = {}) => b.face(o, U, V, lu, lv, {
      vEdges: extra.vEdges || VE, ...extra,
      color: wallColor({ len: lu, ceil: extra.ceil ?? H, ao0: extra.ao0 ?? true, ao1: extra.ao1 ?? true, seed: extra.seed || 0, marks: extra.marks, floor: extra.floor ?? 0 }),
    });

    // South wall (window recess hole)
    face(W, [X1, 0, Z1], [-1, 0, 0], [0, 1, 0], X1 - X0, H, { hole: [X1 - WIN.maxX, X1 - WIN.minX, WIN.minY, WIN.maxY], seed: 1 });
    // East wall
    face(W, [X1, 0, Z0], [0, 0, 1], [0, 1, 0], Z1 - Z0, H, { seed: 2 });
    // North wall (doorway to the nook) — hand marks around the opening
    face(W, [KX1, 0, Z0], [1, 0, 0], [0, 1, 0], X1 - KX1, H, {
      hole: [AD0 - KX1, AD1 - KX1, 0, ADH], seed: 3,
      marks: [[AD0 - 0.04, 1.15, Z0, 0.16, 0.22], [AD1 + 0.04, 1.1, Z0, 0.16, 0.25], [AD1 + 0.05, 0.35, Z0, 0.2, 0.12]],
    });
    // West wall, room part (south of the stairwell opening)
    face(W, [X0, 0, Z1], [0, 0, -1], [0, 1, 0], Z1 - BZ0, H, { ao1: false, seed: 4 });
    // Knee wall, room face: solid part with the closet door hole
    const kneeMarks = [[KX1, 1.0, CDZ1 + 0.06, 0.12, 0.25], [KX1, 0.25, -1.4, 0.25, 0.12]];
    W.face([KX1, 0, KZS], [0, 0, -1], [0, 1, 0], KZS - Z0, H, {
      vEdges: VE, hole: [KZS - CDZ1, KZS - CDZ0, 0, CDH], uEdges: edgeRefine(0, KZS - Z0),
      color: wallColor({ len: KZS - Z0, ao0: false, ao1: true, seed: 5, marks: kneeMarks }),
    });
    // Knee wall, sloped part under the shoe rail
    W.grid([KX1, 0, NZ0], [0, 0, -1], [0, 1, 0], brk(0, NZ0 - KZS, 0.25), [0, 0.04, 0.1, 0.2, 0.35, 0.55, 0.8, 1], {
      pos: (s, t) => { const z = NZ0 - s; return [KX1, t * capY(z), z]; },
      color: wallColor({ len: 9, ao0: false, ao1: false, seed: 5 }),
    });
    // Knee wall end face where the solid wall starts
    W.grid([KX0, capY(KZS), KZS], [1, 0, 0], [0, 1, 0], brk(0, KX1 - KX0), brk(0, H - capY(KZS), 0.4), { color: wallColor({ ao0: false, ao1: false, seed: 6 }) });

    // ---------------- stairwell (finished walls up to UPPER.ceilingY)
    const stairCol = (len, seed, ao0 = false, ao1 = true) => wallColor({ floorFn: (x, z) => stairTop(z) + 0.14, ceil: TOP, len, ao0, ao1, seed, grime: 0.8 });
    const rows = [0, 0.02, 0.05, 0.1, 0.16, 0.25, 0.35, 0.5, 0.65, 0.8, 0.9, 0.95, 0.98, 1];
    const zs = brk(0, BZ0 - Z0, 0.3, edgeRefine(0, BZ0 - Z0));
    // west wall above the stairs (x = X0, faces +X)
    WS.grid([X0, 0, BZ0], [0, 0, -1], [0, 1, 0], zs, rows, {
      pos: (s, t) => { const z = BZ0 - s, y0 = splitY(z); return [X0, y0 + t * (TOP - y0), z]; },
      color: stairCol(BZ0 - Z0, 7),
    });
    // knee wall / stairwell east wall, stair side (x = KX0, faces -X)
    const zs2 = brk(0, KZS - Z0, 0.3, edgeRefine(0, KZS - Z0));
    WS.grid([KX0, 0, Z0], [0, 0, 1], [0, 1, 0], zs2, rows, {
      pos: (s, t) => { const z = Z0 + s, y0 = splitY(z); return [KX0, y0 + t * (TOP - y0), z]; },
      color: stairCol(KZS - Z0, 8, true, false),
    });
    WS.grid([KX0, H, KZS], [0, 0, 1], [0, 1, 0], brk(0, BZ0 - KZS, 0.3), brk(0, TOP - H, 0.5, [0.02, 0.06, TOP - H - 0.1]), { color: stairCol(9, 9, false, false) });
    WS.grid([KX0, 0, KZS], [0, 0, 1], [0, 1, 0], brk(0, NZ0 - KZS, 0.3), [0, 1], {
      pos: (s, t) => { const z = KZS + s, y0 = splitY(z); return [KX0, y0 + t * (capY(z) - y0), z]; },
      color: stairCol(9, 9, false, false),
    });
    // stairwell north wall above the landing (upstairs door hole)
    WS.face([X0, 2.6, Z0], [1, 0, 0], [0, 1, 0], KX0 - X0, TOP - 2.6, {
      hole: [DX0 - X0, KX0 - X0 + 0.01, LAND - 2.6, DTOP - 2.6], step: 0.3, vEdges: [0.15, 0.2, 0.3, TOP - 2.6 - 0.1],
      color: wallColor({ floor: LAND, ceil: TOP, len: KX0 - X0, seed: 10, marks: [[DX1 - 0.02, LAND + 0.95, Z0, 0.1, 0.18]] }),
    });
    // stairwell south wall (north face of the bulkhead)
    WS.grid([KX1, BY, BZ0], [-1, 0, 0], [0, 1, 0], brk(0, KX1 - X0, 0, edgeRefine(0, KX1 - X0)), brk(0, TOP - BY, 0.5, [0.05, 0.12, TOP - BY - 0.1]), {
      color: wallColor({ floor: BY - 9, ceil: TOP, len: KX1 - X0, seed: 11 }),
    });

    // ---------------- reveals (wall thickness visible in openings)
    const rv = wallColor({ ao0: false, ao1: false, seed: 12 });
    // nook doorway (drywall wrapped)
    W.grid([AD0, 0, Z0], [0, 0, -1], [0, 1, 0], brk(0, TP), brk(0, ADH, 0.4, [0.02, 0.06, 0.15]), { color: rv });
    W.grid([AD1, 0, ZN], [0, 0, 1], [0, 1, 0], brk(0, TP), brk(0, ADH, 0.4, [0.02, 0.06, 0.15]), { color: rv });
    W.grid([AD0, ADH, ZN], [1, 0, 0], [0, 0, 1], brk(0, AD1 - AD0, 0.3), brk(0, TP), { color: 0.9 });
    // window recess (sides + head); the sill is a wooden stool (trims)
    W.grid([WIN.minX, WIN.minY, Z1 + TS - 0.05], [0, 0, -1], [0, 1, 0], brk(0, TS - 0.05), brk(0, WIN.maxY - WIN.minY), { color: 0.86 });
    W.grid([WIN.maxX, WIN.minY, Z1], [0, 0, 1], [0, 1, 0], brk(0, TS - 0.05), brk(0, WIN.maxY - WIN.minY), { color: 0.86 });
    W.grid([WIN.minX, WIN.maxY, Z1], [1, 0, 0], [0, 0, 1], brk(0, WIN.maxX - WIN.minX), brk(0, TS - 0.05), { color: 0.8 });
  }

  // ---------------------------------------------------------------------------------------------- stairs

  _stairs() {
    const C = this.B('carpetStair'), T = this.B('trimStair');
    const W = X0, E = KX0, width = E - W;
    const treadCol = (x, y, z) => {
      let c = 1 - 0.1 * Math.exp(-((x + 3.05) ** 2) / 0.05); // traffic path in the middle
      c *= 1 - 0.18 * Math.exp(-Math.min(x - W, E - x) / 0.04);
      c *= 0.9 + 0.15 * fbm(x * 2 + 1, y * 2, z * 2, 2);
      return [c, c * 0.985, c * 0.96];
    };
    const nosing = new THREE.CylinderGeometry(0.016, 0.016, width, 14, 1, true);
    for (let k = 1; k <= S.risers; k++) {
      const zk = S.bottomZ - (k - 1) * TD, yb = (k - 1) * RH, yt = k * RH;
      // white riser face
      T.grid([W, yb, zk], [1, 0, 0], [0, 1, 0], brk(0, width), brk(0, yt - 0.032 - yb), { color: trimColor(0.12, k) });
      // nosing (carpet wrapped bullnose)
      C.geo(nosing, M((W + E) / 2, yt - 0.016, zk + 0.009, 0, 0, Math.PI / 2), { uvScale: [0.1, width], color: 1.05 });
      if (k < S.risers) {
        // carpeted tread
        C.grid([W, yt, zk + 0.009], [1, 0, 0], [0, 0, -1], brk(0, width, 0.2, [0.04, width - 0.04]), brk(0, TD + 0.009), { color: treadCol });
      }
      // shadow caster for the step block
      this.caster.box([W, Math.max(0, yb - 0.25), zk - TD], [E, yt, zk]);
    }
    // landing (carpet) + threshold
    const lz1 = S.topZ + 0.009;
    C.grid([W, LAND, lz1], [1, 0, 0], [0, 0, -1], brk(0, width, 0.2, [0.04, width - 0.04]), brk(0, lz1 - Z0, 0.25, [0.04, lz1 - Z0 - 0.04]), { color: treadCol });
    this.B('wood').box([DX0, LAND - 0.02, ZN], [DX1, LAND + 0.008, Z0 + 0.01], { faces: ['py', 'pz'], color: 0.9 });
    this.caster.box([W, LAND_UNDER, Z0], [E, LAND, S.topZ]);

    // skirt boards (white, 14 mm) on both sides of the flight
    const yb = (z) => nosingY(z) - 0.13, yt = (z) => nosingY(z) + 0.14;
    const zTop = S.topZ, zBot = 1.75;
    // west wall: plane x = X0, u = -z
    const westPts = [[-zBot, 0], [-1.7, 0], [-zTop, yb(zTop)], [-zTop, yt(zTop)], [-zBot, yt(zBot)]];
    plate(T, westPts, [X0, 0, 0], [0, 0, -1], [0, 1, 0], 0.014, { bevel: 0.002, color: trimColor(0.1, 21) });
    // knee wall side: plane x = KX0 facing -X, u = z
    const eastPts = [[zTop, yb(zTop)], [NZ0, yb(NZ0)], [NZ0, yt(NZ0)], [zTop, yt(zTop)]];
    plate(T, eastPts, [KX0, 0, 0], [0, 0, 1], [0, 1, 0], 0.014, { bevel: 0.002, color: trimColor(0.1, 22) });
  }

  // ---------------------------------------------------------------------------------------------- railing

  _railing() {
    const T = this.B('trim'), Wd = this.B('wood');
    const xc = S.sideWallX;
    // shoe rail cap on top of the sloped knee wall
    const capProf = [[-0.067, 0], [0.067, 0], [0.067, 0.015], [0.062, 0.022], [0.052, 0.026], [-0.052, 0.026], [-0.062, 0.022], [-0.067, 0.015]];
    const slopeV = (a, b) => { _D.set(0, b[1] - a[1], b[2] - a[2]).normalize(); _V.set(0, 1, 0).addScaledVector(_D, -_D.y).normalize(); return [_V.x, _V.y, _V.z]; };
    const c0 = [xc, capY(NZ0), NZ0 + 0.06], c1 = [xc, capY(KZS), KZS];
    runProfile(T, capProf, c0, c1, [1, 0, 0], slopeV(c0, c1), { color: trimColor(0.12, 31) });
    // balusters (white, chamfered square)
    const bal = new RoundedBoxGeometry(0.032, 1, 0.032, 1, 0.004);
    const n = 11;
    for (let i = 0; i < n; i++) {
      const z = 1.42 - (i * (1.42 - 0.24)) / (n - 1);
      const y0 = capY(z) + 0.018, y1 = railTop(z) - 0.052, h = y1 - y0;
      T.geo(bal, M(xc, (y0 + y1) / 2, z, 0, 0, 0, 1, h, 1), { uvScale: [0.03, h], color: trimColor(0.08, 40 + i) });
    }
    // handrail on the balusters (stained wood, classic profile)
    const railProf = [[-0.031, 0], [0.031, 0], [0.031, 0.018], [0.023, 0.027], [0.027, 0.038], [0.021, 0.049], [0.009, 0.055],
      [-0.009, 0.055], [-0.021, 0.049], [-0.027, 0.038], [-0.023, 0.027], [-0.031, 0.018]];
    const r0 = [xc, railTop(1.585) - 0.055, 1.585], r1 = [xc, railTop(KZS) - 0.055, KZS];
    runProfile(Wd, railProf, r0, r1, [1, 0, 0], slopeV(r0, r1), { uvScale: 1, color: 1 });
    // newel post
    const nz = (NZ0 + NZ1) / 2;
    Wd.geo(new RoundedBoxGeometry(0.128, 0.24, 0.128, 2, 0.008), M(xc, 0.12, nz), { worldUV: true });
    Wd.geo(new RoundedBoxGeometry(0.104, 0.9, 0.104, 2, 0.01), M(xc, 0.69, nz), { worldUV: true });
    Wd.geo(new RoundedBoxGeometry(0.122, 0.16, 0.122, 2, 0.008), M(xc, 1.16, nz), { worldUV: true });
    Wd.geo(new RoundedBoxGeometry(0.15, 0.028, 0.15, 2, 0.008), M(xc, 1.254, nz), { worldUV: true });
    const fin = new THREE.LatheGeometry([[0, 0], [0.04, 0], [0.04, 0.008], [0.018, 0.016], [0.014, 0.024], [0.03, 0.045], [0.032, 0.058], [0.022, 0.075], [0.008, 0.082], [0, 0.083]].map(([r, y]) => new THREE.Vector2(r, y)), 16);
    Wd.geo(fin, M(xc, 1.268, nz), { worldUV: true });

    // wall handrail (round, on brass brackets) along the west wall
    const B = this.B('brass');
    const rx = X0 + 0.072, zA = 1.42, zB = S.topZ + 0.1;
    const pA = [rx, railTop(zA) - 0.023, zA], pB = [rx, railTop(zB) - 0.023, zB];
    _D.set(pB[0] - pA[0], pB[1] - pA[1], pB[2] - pA[2]); const len = _D.length(); _D.normalize();
    const cyl = new THREE.CylinderGeometry(0.023, 0.023, len, 16, 1, false);
    _q.setFromUnitVectors(new THREE.Vector3(0, 1, 0), _D);
    _M4.compose(new THREE.Vector3((pA[0] + pB[0]) / 2, (pA[1] + pB[1]) / 2, (pA[2] + pB[2]) / 2), _q, new THREE.Vector3(1, 1, 1));
    Wd.geo(cyl, _M4, { uvScale: [0.15, len] });
    const ret = new THREE.CylinderGeometry(0.023, 0.023, 0.075, 12);
    for (const p of [pA, pB]) {
      Wd.geo(ret, M(X0 + 0.036, p[1], p[2], 0, 0, Math.PI / 2), { uvScale: 0.1 });
      Wd.geo(new THREE.SphereGeometry(0.023, 12, 8), M(p[0], p[1], p[2]), { uvScale: 0.1 });
    }
    const plateG = new THREE.CylinderGeometry(0.03, 0.03, 0.008, 16), arm = new THREE.CylinderGeometry(0.0055, 0.0055, 0.07, 8);
    for (const z of [1.05, -0.05, -1.15]) {
      const yr = railTop(z) - 0.023 - 0.045;
      B.geo(plateG, M(X0 + 0.004, yr - 0.02, z, 0, 0, Math.PI / 2));
      B.geo(arm, M(X0 + 0.04, yr + 0.004, z, 0, 0, Math.PI / 2 - 0.45));
    }
  }

  // ---------------------------------------------------------------------------------------------- closet under the stairs

  _closet() {
    const CW = this.B('closetWall'), CB = this.B('closetBlock'), CWd = this.B('closetWood');
    const dark = (x, y, z) => 0.82 + 0.18 * fbm(x * 2, y * 2, z * 2, 2) - 0.25 * Math.exp(-y / 0.1);
    // west (foundation block behind bare studs)
    CB.grid([X0, 0, CL.maxZ], [0, 0, -1], [0, 1, 0], brk(0, CL.maxZ - Z0, 0.3), [0, 0.05, 0.15, 0.4, 0.7, 1], {
      pos: (s, t) => { const z = CL.maxZ - s; return [X0, t * underY(z), z]; }, color: dark,
    });
    // north
    CB.grid([X0, 0, Z0], [1, 0, 0], [0, 1, 0], brk(0, KX0 - X0, 0.3), brk(0, LAND_UNDER, 0.4, [0.05, 0.15]), { color: dark });
    // south partition (drywall back)
    CW.grid([KX0, 0, CL.maxZ], [-1, 0, 0], [0, 1, 0], brk(0, KX0 - X0, 0.3), brk(0, underY(CL.maxZ), 0.4, [0.05, 0.15]), { color: dark });
    // knee wall inner face (drywall back) with the door opening
    const kw = (z0, z1, yb) => CW.grid([KX0, 0, z0], [0, 0, 1], [0, 1, 0], brk(0, z1 - z0, 0.3), [0, 0.05, 0.15, 0.4, 0.7, 1], {
      pos: (s, t) => { const z = z0 + s, y0 = yb(z); return [KX0, y0 + t * (underY(z) - y0), z]; }, color: dark,
    });
    kw(Z0, CDZ0, () => 0); kw(CDZ0, CDZ1, () => CDH); kw(CDZ1, CL.maxZ, () => 0);
    // ceiling: landing underside + sloped stair underside (raw plywood)
    CWd.grid([X0, LAND_UNDER, Z0], [1, 0, 0], [0, 0, 1], brk(0, KX0 - X0, 0.3), brk(0, S.topZ - Z0, 0.3), { color: 0.75 });
    const L0 = S.topZ, L1 = CL.maxZ, slope = Math.hypot(1, RH / TD);
    CWd.grid([X0, 0, L0], [1, 0, 0], [0, -(RH / TD) / slope, 1 / slope], brk(0, KX0 - X0, 0.3), brk(0, (L1 - L0) * slope, 0.3), {
      pos: (s, t) => { const z = L0 + t / slope; return [X0 + s, underY(z), z]; }, color: 0.7,
    });
    // bare studs on the foundation wall, framing of the knee wall (king studs + header), sole plates
    const st = (x0, x1, z) => { const top = underY(z + 0.02); CWd.box([x0, 0, z - 0.02], [x1, top, z + 0.02], { faces: ['px', 'nx', 'pz', 'nz'], color: 0.85 }); };
    for (const z of [-2.66, -2.26, -1.86, -1.46, -1.06, -0.66]) st(X0, X0 + 0.09, z);
    for (const z of [Z0 + 0.04, CDZ0 - 0.04, CDZ1 + 0.04, -1.3, -0.9, CL.maxZ - 0.06]) st(KX0 - 0.09, KX0, z);
    CWd.box([KX0 - 0.09, CDH, CDZ0 - 0.06], [KX0, CDH + 0.18, CDZ1 + 0.06], { faces: ['nx', 'ny'], color: 0.85 });
    CWd.box([KX0 - 0.09, 0, Z0], [KX0, 0.04, CDZ0], { faces: ['nx', 'py'], color: 0.8 });
    CWd.box([KX0 - 0.09, 0, CDZ1], [KX0, 0.04, CL.maxZ], { faces: ['nx', 'py'], color: 0.8 });
    CWd.box([X0, 0, Z0], [X0 + 0.09, 0.04, CL.maxZ], { faces: ['px', 'py'], color: 0.8 });
    // stair stringers visible under the flight
    for (const x of [X0 + 0.04, (X0 + KX0) / 2, KX0 - 0.06]) {
      const pts = [[L0, underY(L0)], [L1, underY(L1)], [L1, underY(L1) - 0.06], [L0, underY(L0) - 0.06]];
      plate(CWd, pts, [x + 0.02, 0, 0], [0, 0, 1], [0, 1, 0], 0.04, { color: 0.78 });
    }
    this.caster.box([X0, 0, CL.maxZ - 0.1], [KX0, underY(CL.maxZ), CL.maxZ]);
  }

  // ---------------------------------------------------------------------------------------------- laundry nook

  _nook() {
    const NB = this.B('nookBlock'), ND = this.B('nookDrywall'), NW = this.B('nookWood');
    const HN = 2.5, top = LAND;
    const damp = (len, seed) => (x, y, z, s) => {
      let c = 1 - 0.32 * Math.exp(-y / 0.12) - 0.12 * Math.exp(-y / 0.6);       // rising damp
      c *= 1 - 0.18 * Math.exp(-s / 0.15) - 0.18 * Math.exp(-Math.max(0, len - s) / 0.15);
      c *= 1 - 0.15 * Math.exp(-(HN - y) / 0.12);
      c *= 0.86 + 0.2 * fbm(x * 0.9 + seed, y * 0.6, z * 0.9, 3);
      const streak = fbm(x * 6 + seed, 0.3, z * 6, 2); if (streak > 0.62 && y < 1.6) c *= 1 - (streak - 0.62) * (1.6 - y) * 0.9;
      return [c, c * 0.985, c * 0.95];
    };
    const VE = [0.03, 0.08, 0.15, 0.3, 0.6, 1.2, HN - 0.2, HN - 0.06];
    NB.face([AL.minX, 0, NN], [1, 0, 0], [0, 1, 0], AL.maxX - AL.minX, HN, { vEdges: VE, color: damp(AL.maxX - AL.minX, 1) });
    NB.face([AL.maxX, 0, NN], [0, 0, 1], [0, 1, 0], ZN - NN, HN, { vEdges: VE, color: damp(ZN - NN, 2) });
    const dw = (len, seed) => wallColor({ len, ceil: top, seed, grime: 1.3, tint: [1, 0.99, 0.96] });
    ND.face([AL.minX, 0, ZN], [0, 0, -1], [0, 1, 0], ZN - NN, top, { vEdges: VE, color: dw(ZN - NN, 3) });
    ND.face([AL.maxX, 0, ZN], [-1, 0, 0], [0, 1, 0], AL.maxX - AL.minX, top, { vEdges: VE, hole: [AL.maxX - AD1, AL.maxX - AD0, 0, ADH], color: dw(AL.maxX - AL.minX, 4) });
    // sill plate + rim joist on the foundation (north + east)
    NW.box([AL.minX, HN, NN], [AL.maxX, top, NN + 0.04], { faces: ['pz', 'ny'], color: 0.8 });
    NW.box([AL.minX, HN, NN], [AL.maxX, HN + 0.04, NN + 0.14], { faces: ['pz', 'py', 'ny'], color: 0.85 });
    NW.box([AL.maxX - 0.04, HN, NN], [AL.maxX, top, ZN], { faces: ['nx', 'ny'], color: 0.8 });
    // joists (2x10, 40 cm o.c.) + blocking over the partition + subfloor
    const jcol = (x, y, z) => 0.85 + 0.15 * fbm(x * 3, y * 9, z * 0.7, 2);
    for (let x = 0.24; x < AL.maxX; x += 0.4) NW.box([x - 0.02, 2.51, NN], [x + 0.02, top, ZN], { faces: ['px', 'nx', 'ny'], color: jcol });
    NW.box([AL.minX, 2.51, ZN], [AL.maxX, top, ZN + 0.04], { faces: ['nz', 'ny'], color: 0.8 });
    NW.grid([AL.minX, top, NN], [1, 0, 0], [0, 0, 1], brk(0, AL.maxX - AL.minX, 0.8), brk(0, ZN - NN, 0.8), { color: 0.62 });
    // cross bridging between joists
    const br = new THREE.BoxGeometry(0.42, 0.02, 0.04);
    for (let x = 0.24; x < AL.maxX - 0.4; x += 0.4) {
      for (const sgn of [-1, 1]) NW.geo(br, M(x + 0.2, 2.63, -3.75 + sgn * 0.025, 0, 0, sgn * 0.5), { worldUV: true, color: 0.8 });
    }
    // copper supply lines under the joists, dropping in the NW corner to the laundry valves
    const Cu = this.B('copper');
    const pipe = (a, b, r, builder, opt = {}) => {
      _D.set(b[0] - a[0], b[1] - a[1], b[2] - a[2]); const len = _D.length(); _D.normalize();
      _q.setFromUnitVectors(new THREE.Vector3(0, 1, 0), _D);
      _M4.compose(new THREE.Vector3((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2), _q, new THREE.Vector3(1, 1, 1));
      builder.geo(new THREE.CylinderGeometry(r, r, len, opt.seg || 10, 1, true), _M4, { uvScale: [0.1, len], color: opt.color });
    };
    const ball = (p, r, builder) => builder.geo(new THREE.SphereGeometry(r, 10, 8), M(p[0], p[1], p[2]));
    for (const [z, yv] of [[-4.42, 2.472], [-4.5, 2.472]]) {
      pipe([3.4, yv, z], [0.33, yv, z], 0.011, Cu);
      ball([0.33, yv, z], 0.014, Cu);
      pipe([0.33, yv, z], [0.33, 1.05, z], 0.011, Cu);
      ball([0.33, 1.05, z], 0.013, Cu);
    }
    const Br = this.B('brass');
    Br.geo(new THREE.CylinderGeometry(0.016, 0.016, 0.06, 10), M(0.33, 1.01, -4.42));
    Br.geo(new THREE.CylinderGeometry(0.016, 0.016, 0.06, 10), M(0.33, 1.01, -4.5));
    // straps
    const G = this.B('galv');
    for (const x of [0.9, 1.9, 2.9]) G.box([x - 0.012, 2.455, -4.53], [x + 0.012, 2.51, -4.39], { faces: ['py', 'ny', 'pz', 'nz'], color: 0.7 });
    // black ABS drain stack near the partition
    const P = this.B('pvc');
    pipe([0.31, 0, -3.2], [0.31, top, -3.2], 0.05, P, { seg: 16 });
    P.geo(new THREE.CylinderGeometry(0.058, 0.058, 0.07, 16), M(0.31, 0.35, -3.2));
    P.geo(new THREE.CylinderGeometry(0.058, 0.058, 0.07, 16), M(0.31, 1.25, -3.2));
    // conduits from the breaker panel to the joists
    for (const x of [2.52, 2.68]) pipe([x, 1.69, NN + 0.025], [x, top, NN + 0.025], 0.011, G, { color: 0.8 });
    // galvanized HVAC trunk crossing under the joists (with seams + hangers)
    const gc = (x, y, z) => 0.75 + 0.25 * fbm(x * 1.5, y * 4, z * 4, 3);
    G.box([AL.minX, 2.3, -3.36], [AL.maxX, 2.51, -2.96], { faces: ['ny', 'pz', 'nz'], step: 0.6, color: gc });
    for (let x = 0.75; x < AL.maxX; x += 1.2) G.box([x - 0.006, 2.295, -3.365], [x + 0.006, 2.51, -2.955], { faces: ['ny', 'pz', 'nz', 'px', 'nx'], color: 0.7 });
    // dryer vent: flexible foil duct hanging from the rim joist down to the floor (dryer long gone)
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(3.15, 2.62, NN + 0.02), new THREE.Vector3(3.17, 2.56, -4.42), new THREE.Vector3(3.27, 2.15, -4.34),
      new THREE.Vector3(3.3, 1.3, -4.38), new THREE.Vector3(3.24, 0.4, -4.32), new THREE.Vector3(3.08, 0.075, -4.08), new THREE.Vector3(2.86, 0.055, -3.98),
    ]);
    const tube = new THREE.TubeGeometry(curve, 90, 0.05, 14, false);
    const pa = tube.attributes.position, na = tube.attributes.normal;
    for (let i = 0; i < pa.count; i++) {
      const k = 1 + 0.08 * (vnoise(pa.getX(i) * 9, pa.getY(i) * 9, pa.getZ(i) * 9) - 0.5);
      const cx = pa.getX(i) - na.getX(i) * 0.05, cy = pa.getY(i) - na.getY(i) * 0.05, cz = pa.getZ(i) - na.getZ(i) * 0.05;
      pa.setXYZ(i, cx + na.getX(i) * 0.05 * k, cy + na.getY(i) * 0.05 * k, cz + na.getZ(i) * 0.05 * k);
    }
    this.B('foil').geo(tube, new THREE.Matrix4(), { uvScale: [curve.getLength() / 0.014, 3] });
    // pendant socket + pull chain for the broken bulb (bulb itself is a prop)
    const bulb = L.PROPS.bulb.pos;
    P.geo(new THREE.CylinderGeometry(0.0035, 0.0035, top - 2.37, 6), M(bulb[0], (top + 2.37) / 2, bulb[2]));
    P.geo(new THREE.CylinderGeometry(0.017, 0.015, 0.045, 14), M(bulb[0], 2.352, bulb[2]));
    P.geo(new THREE.CylinderGeometry(0.018, 0.018, 0.012, 14), M(bulb[0], top - 0.006, bulb[2]));
    Br.geo(new THREE.CylinderGeometry(0.0013, 0.0013, 0.26, 4), M(bulb[0] + 0.016, 2.22, bulb[2]));
    Br.geo(new THREE.SphereGeometry(0.004, 6, 4), M(bulb[0] + 0.016, 2.09, bulb[2]));
    // floor drain
    const dr = this.B('iron');
    dr.geo(new THREE.CylinderGeometry(0.085, 0.09, 0.006, 20), M(2.45, 0.003, -3.45), { color: 0.6 });
    // cobweb in the nook corner
    this._web([AL.maxX - 0.01, 2.49, NN + 0.38], Math.PI * 0.75, 0.55, 0.6);
  }

  // ---------------------------------------------------------------------------------------------- window

  _window() {
    const T = this.B('trim');
    const wx0 = WIN.minX, wx1 = WIN.maxX, wy0 = WIN.minY, wy1 = WIN.maxY;
    const dirty = (x, y, z) => 0.62 + 0.2 * fbm(x * 9, y * 9, z * 9, 2) - 0.15 * Math.exp(-(y - wy0) / 0.03);
    // stool (sill board) + apron
    T.geo(new RoundedBoxGeometry(wx1 - wx0 + 0.08, 0.025, TS - 0.03 + 0.04, 2, 0.005), M((wx0 + wx1) / 2, wy0 - 0.0125, Z1 + (TS - 0.03) / 2 - 0.02), { worldUV: true, color: trimColor(0.16, 51) });
    T.geo(new RoundedBoxGeometry(wx1 - wx0, 0.07, 0.016, 2, 0.004), M((wx0 + wx1) / 2, wy0 - 0.06, Z1 - 0.008), { worldUV: true, color: trimColor(0.12, 52) });
    // frame (old aluminium slider, dirty white) at the outside face
    const fz0 = Z1 + TS - 0.07, fz1 = Z1 + TS - 0.02;
    const fr = (a, b) => T.box(a, b, { color: dirty });
    fr([wx0, wy0, fz0], [wx1, wy0 + 0.035, fz1]); fr([wx0, wy1 - 0.035, fz0], [wx1, wy1, fz1]);
    fr([wx0, wy0, fz0], [wx0 + 0.035, wy1, fz1]); fr([wx1 - 0.035, wy0, fz0], [wx1, wy1, fz1]);
    const mx = (wx0 + wx1) / 2;
    fr([mx - 0.022, wy0, fz0 + 0.005], [mx + 0.022, wy1, fz1]);
    // sash rails
    fr([wx0 + 0.035, wy0 + 0.035, fz0 + 0.012], [mx - 0.022, wy0 + 0.055, fz0 + 0.03]);
    fr([mx + 0.022, wy0 + 0.035, fz0 + 0.022], [wx1 - 0.035, wy0 + 0.055, fz0 + 0.04]);
    // glass panes (dirty): both sashes in one mesh (one draw call); each pane keeps its 0..1 UVs (dirt alpha map)
    const gl = new THREE.PlaneGeometry(1, 1);
    const wc = [mx, (wy0 + wy1) / 2, fz0 + 0.025]; // mesh origin at the window (transparent sorting position)
    const pane = (x, z) => gl.clone().applyMatrix4(M(x - wc[0], 0, z - wc[2], 0, Math.PI, 0, mx - wx0 - 0.06, wy1 - wy0 - 0.07, 1));
    const panes = new THREE.Mesh(mergeGeometries([pane((wx0 + mx) / 2, fz0 + 0.02), pane((mx + wx1) / 2, fz0 + 0.03)], false), this.mats.glass);
    panes.position.set(wc[0], wc[1], wc[2]);
    panes.name = 'arch_windowGlass';
    panes.renderOrder = 2;
    this.root.add(panes);
    // iron security bars (cast the moonlight bar shadows)
    const I = this.B('iron');
    const rust = (x, y, z) => { const n = fbm(x * 14, y * 14, z * 14, 2); return [0.75 + 0.5 * n, 0.68 + 0.3 * n, 0.6 + 0.2 * n]; };
    const bar = new THREE.CylinderGeometry(0.0095, 0.0095, wy1 - wy0 + 0.03, 10);
    const bz = Z1 + 0.09;
    for (let i = 0; i < 6; i++) I.geo(bar, M(wx0 + 0.11 + i * 0.156, (wy0 + wy1) / 2, bz), { color: rust });
    for (const y of [wy0 + 0.12, wy1 - 0.12]) I.box([wx0 - 0.01, y - 0.016, bz - 0.005], [wx1 + 0.01, y + 0.016, bz + 0.005], { color: rust });
    this._web([wx0 + 0.005, wy1 - 0.005, Z1 + 0.13], 0, 0.3, 0);
  }

  /** Cobweb quad anchored at its top-left corner (the web hub), yawed then tilted about its own X axis. */
  _web(pos, yaw, size, tilt = 0) {
    const g = new THREE.PlaneGeometry(size, size);
    g.translate(size / 2, -size / 2, 0);
    _e.set(tilt, yaw, 0, 'YXZ'); _q.setFromEuler(_e);
    g.applyMatrix4(new THREE.Matrix4().compose(new THREE.Vector3(pos[0], pos[1], pos[2]), _q, new THREE.Vector3(1, 1, 1)));
    (this._webs ||= []).push(g);
  }

  /** All cobwebs in one mesh, each quad with an explicit back face (flipped winding + normal): looks like the former
   *  double-sided material, drawn in one call with a single-sided program. */
  _flushWebs() {
    if (!this._webs?.length) return;
    const parts = [];
    for (const g of this._webs) {
      parts.push(g);
      const b = g.clone();
      const n = b.attributes.normal;
      for (let i = 0; i < n.count; i++) n.setXYZ(i, -n.getX(i), -n.getY(i), -n.getZ(i));
      const ix = b.index.array;
      for (let i = 0; i < ix.length; i += 3) { const t = ix[i + 1]; ix[i + 1] = ix[i + 2]; ix[i + 2] = t; }
      parts.push(b);
    }
    const m = new THREE.Mesh(mergeGeometries(parts, false), this.mats.web);
    m.name = 'arch_webs';
    m.renderOrder = 3;
    this.root.add(m);
    this._webs = null;
  }

  // ---------------------------------------------------------------------------------------------- outside (seen through the window)

  _outside() {
    const gy = WIN.minY - 0.06; // ground level, just under the window
    const G = this.B('ground');
    G.grid([-3, gy, 30], [1, 0, 0], [0, 0, -1], brk(0, 14, 7), brk(0, 30 - (Z1 + TS), 9), { color: 1 });
    // snow drift against the glass
    const sn = this.B('snow');
    const drift = new THREE.CylinderGeometry(0.09, 0.09, WIN.maxX - WIN.minX + 0.4, 18, 6, false, 0, Math.PI);
    const dp = drift.attributes.position;
    for (let i = 0; i < dp.count; i++) {
      const y = dp.getY(i); dp.setX(i, dp.getX(i) * (0.8 + 0.35 * vnoise(y * 7, 1, 3)));
    }
    sn.geo(drift, M((WIN.minX + WIN.maxX) / 2, gy - 0.02, Z1 + TS + 0.01, 0, 0, Math.PI / 2, 1, 1, 0.75), { uvScale: 1 });
    // dead grass tufts poking above the ground in front of the window
    const gr = this.B('grass'), r = rng(99);
    const bladeCol = () => { const t = r(); return [0.55 + 0.4 * t, 0.5 + 0.3 * t, 0.38 + 0.2 * t]; };
    for (let i = 0; i < 260; i++) {
      const x = WIN.minX - 0.6 + r() * (WIN.maxX - WIN.minX + 1.2), z = Z1 + TS + 0.03 + r() * r() * 1.2;
      const h = 0.05 + r() * 0.16, a = r() * Math.PI, lean = (r() - 0.5) * 0.08, w = 0.004 + r() * 0.004;
      const ca = Math.cos(a) * w, sa = Math.sin(a) * w, c = bladeCol();
      // front + back face (the material is single-sided; the back copy has the flipped normal DoubleSide would use)
      for (const s of [1, -1]) {
        const base = gr.count;
        gr._push(x - ca, gy, z - sa, 0, 0, -s, 0, 0, c);
        gr._push(x + ca, gy, z + sa, 0, 0, -s, 1, 0, c);
        gr._push(x + lean * 0.5, gy + h * 0.6, z + lean * 0.3, 0, 0, -s, 0.5, 0.6, c);
        gr._push(x + lean, gy + h, z + lean * 0.5, 0, 0, -s, 0.5, 1, c);
        if (s > 0) gr.idx.push(base, base + 1, base + 2, base + 2, base + 1, base + 3);
        else gr.idx.push(base, base + 2, base + 1, base + 2, base + 3, base + 1);
      }
    }
    // night sky backdrop
    const sky = new THREE.Mesh(new THREE.PlaneGeometry(40, 30), this.mats.sky);
    sky.position.set(3, gy + 15, 30); sky.rotation.y = Math.PI;
    this.root.add(sky);
  }

  // ---------------------------------------------------------------------------------------------- trims

  _trims() {
    const T = this.B('trim'), TS2 = this.B('trimStair');
    const base = [[0, 0], [0.0135, 0], [0.0135, 0.07], [0.012, 0.079], [0.0085, 0.087], [0.005, 0.092], [0.0025, 0.097], [0, 0.1]];
    const baseTall = base.map(([d, h]) => [d, h * 1.4]);
    const bb = (b, prof, a, c, out, seed) => runProfile(b, prof, a, c, out, [0, 1, 0], { color: trimColor(0.1, seed) });
    // room
    bb(T, base, [X0, 0, Z1], [X1, 0, Z1], [0, 0, -1], 1);
    bb(T, base, [X1, 0, Z0], [X1, 0, Z1], [-1, 0, 0], 2);
    bb(T, base, [KX1, 0, Z0], [AD0, 0, Z0], [0, 0, 1], 3);
    bb(T, base, [AD1, 0, Z0], [X1, 0, Z0], [0, 0, 1], 4);
    bb(T, base, [X0, 0, 1.75], [X0, 0, Z1], [1, 0, 0], 5);
    bb(T, base, [KX1, 0, Z0], [KX1, 0, CDZ0 - 0.065], [1, 0, 0], 6);
    bb(T, base, [KX1, 0, CDZ1 + 0.065], [KX1, 0, NZ0], [1, 0, 0], 7);
    // landing
    bb(TS2, baseTall.map(([d, h]) => [d, h]), [X0, LAND, Z0], [X0, LAND, S.topZ], [1, 0, 0], 8);
    bb(TS2, baseTall, [KX0, LAND, Z0], [KX0, LAND, S.topZ], [-1, 0, 0], 9);

    // casings
    const cas = [[0, 0], [0.065, 0], [0.065, 0.012], [0.063, 0.0152], [0.058, 0.0165], [0.02, 0.0142], [0.005, 0.0122], [0, 0.009]];
    const casNarrow = cas.map(([u, v]) => [u * 0.75, v]);
    const leg = (b, prof, x, z, y0, y1, across, out, seed) => runProfile(b, prof, [x, y0, z], [x, y1, z], across, out, { color: trimColor(0.1, seed) });
    // closet door (room side of the knee wall)
    leg(T, cas, KX1, CDZ0, 0, CDH, [0, 0, -1], [1, 0, 0], 11);
    leg(T, cas, KX1, CDZ1, 0, CDH, [0, 0, 1], [1, 0, 0], 12);
    runProfile(T, cas, [KX1, CDH, CDZ0 - 0.075], [KX1, CDH, CDZ1 + 0.075], [0, 1, 0], [1, 0, 0], { color: trimColor(0.1, 13) });
    // closet jambs + stop
    T.grid([KX0, 0, CDZ0], [1, 0, 0], [0, 1, 0], brk(0, KX1 - KX0), brk(0, CDH, 0.5), { color: 0.9 });
    T.grid([KX1, 0, CDZ1], [-1, 0, 0], [0, 1, 0], brk(0, KX1 - KX0), brk(0, CDH, 0.5), { color: 0.9 });
    T.grid([KX0, CDH, CDZ0], [1, 0, 0], [0, 0, 1], brk(0, KX1 - KX0), brk(0, CDZ1 - CDZ0), { color: 0.85 });
    T.box([KX1 - 0.047, 0, CDZ0], [KX1 - 0.034, CDH, CDZ0 + 0.012], { faces: ['px', 'pz'] });
    T.box([KX1 - 0.047, 0, CDZ1 - 0.012], [KX1 - 0.034, CDH, CDZ1], { faces: ['px', 'nz'] });
    T.box([KX1 - 0.047, CDH - 0.012, CDZ0], [KX1 - 0.034, CDH, CDZ1], { faces: ['px', 'ny'] });
    // upstairs door, stairwell side (tight against the west wall: narrow west leg, no east leg)
    leg(TS2, casNarrow, DX0, Z0, LAND, DTOP, [-1, 0, 0], [0, 0, 1], 14);
    runProfile(TS2, cas, [X0, DTOP, Z0], [KX0, DTOP, Z0], [0, 1, 0], [0, 0, 1], { color: trimColor(0.1, 15) });
    // upstairs door jambs + stop
    TS2.grid([DX0, LAND, Z0], [0, 0, -1], [0, 1, 0], brk(0, TP), brk(0, DTOP - LAND, 0.5), { color: 0.92 });
    TS2.grid([DX1, LAND, ZN], [0, 0, 1], [0, 1, 0], brk(0, TP), brk(0, DTOP - LAND, 0.5), { color: 0.92 });
    TS2.grid([DX0, DTOP, ZN], [1, 0, 0], [0, 0, 1], brk(0, DX1 - DX0), brk(0, TP), { color: 0.9 });
    TS2.box([DX0, LAND, Z0 - 0.06], [DX0 + 0.012, DTOP, Z0 - 0.046], { faces: ['px', 'pz'] });
    TS2.box([DX1 - 0.012, LAND, Z0 - 0.06], [DX1, DTOP, Z0 - 0.046], { faces: ['nx', 'pz'] });
    TS2.box([DX0, DTOP - 0.012, Z0 - 0.06], [DX1, DTOP, Z0 - 0.046], { faces: ['ny', 'pz'] });
  }

  // ---------------------------------------------------------------------------------------------- misc details

  _details() {
    const T = this.B('trim'), P = this.B('pvc');
    // ceiling supply register (stamped steel, painted)
    const rx = -1.25, rz = 2.25, rw = 0.3, rd = 0.15;
    P.grid([rx - rw / 2, H - 0.004, rz - rd / 2], [1, 0, 0], [0, 0, 1], brk(0, rw), brk(0, rd), { color: 0.3 });
    T.box([rx - rw / 2 - 0.02, H - 0.008, rz - rd / 2 - 0.02], [rx + rw / 2 + 0.02, H, rz - rd / 2], { faces: ['ny', 'pz', 'nz', 'px', 'nx'], color: 0.9 });
    T.box([rx - rw / 2 - 0.02, H - 0.008, rz + rd / 2], [rx + rw / 2 + 0.02, H, rz + rd / 2 + 0.02], { faces: ['ny', 'pz', 'nz', 'px', 'nx'], color: 0.9 });
    T.box([rx - rw / 2 - 0.02, H - 0.008, rz - rd / 2], [rx - rw / 2, H, rz + rd / 2], { faces: ['ny', 'px', 'nx'], color: 0.9 });
    T.box([rx + rw / 2, H - 0.008, rz - rd / 2], [rx + rw / 2 + 0.02, H, rz + rd / 2], { faces: ['ny', 'px', 'nx'], color: 0.9 });
    for (let i = 1; i < 9; i++) {
      const x = rx - rw / 2 + (i * rw) / 9;
      T.geo(new THREE.BoxGeometry(0.003, 0.014, rd), M(x, H - 0.008, rz, 0, 0, 0.5), { color: 0.82 });
    }
    // cold-air return grille low on the east wall
    const gz = -1.85, gw = 0.36, gy0 = 0.16, gy1 = 0.42;
    P.grid([X1 - 0.004, gy0, gz - gw / 2], [0, 0, 1], [0, 1, 0], brk(0, gw), brk(0, gy1 - gy0), { color: 0.25 });
    const gf = { faces: ['nx', 'py', 'ny', 'pz', 'nz'], color: trimColor(0.2, 61) };
    T.box([X1 - 0.01, gy0 - 0.02, gz - gw / 2 - 0.02], [X1, gy0, gz + gw / 2 + 0.02], gf);
    T.box([X1 - 0.01, gy1, gz - gw / 2 - 0.02], [X1, gy1 + 0.02, gz + gw / 2 + 0.02], gf);
    T.box([X1 - 0.01, gy0, gz - gw / 2 - 0.02], [X1, gy1, gz - gw / 2], gf);
    T.box([X1 - 0.01, gy0, gz + gw / 2], [X1, gy1, gz + gw / 2 + 0.02], gf);
    for (let i = 0; i < 9; i++) {
      const y = gy0 + 0.02 + i * ((gy1 - gy0 - 0.04) / 8);
      T.geo(new THREE.BoxGeometry(0.02, 0.003, gw), M(X1 - 0.015, y, gz, 0, 0, -0.6), { color: 0.8 });
    }
    // unlit dome fixture at the top of the stairwell
    const dome = new THREE.Mesh(new THREE.SphereGeometry(0.14, 24, 10, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), this.mats.domeOff);
    dome.scale.set(1, 0.55, 1); dome.position.set((X0 + KX0) / 2, TOP - 0.012, -0.9); dome.castShadow = false; dome.receiveShadow = true;
    this.root.add(dome);
    this.B('brass').geo(new THREE.CylinderGeometry(0.03, 0.03, 0.03, 12), M((X0 + KX0) / 2, TOP - 0.09, -0.9));
    this._web([X0 + 0.01, TOP - 0.01, Z0 + 0.32], Math.PI * 0.25, 0.45, -0.6);
  }

  // ---------------------------------------------------------------------------------------------- upstairs hallway (win view)

  _hallway() {
    const par = this.hall; // hall builders are flagged in KEY_OPTS (parented to the hall group, no shadows)
    const Wl = this.B('hallWall'), F = this.B('hallFloor'), Ce = this.B('hallCeil'), T = this.B('hallTrim');
    const y0 = LAND, hh = TOP - LAND;
    const wc = (len) => wallColor({ floor: y0, ceil: TOP, len, grime: 0.6 });
    const VE = [0.03, 0.1, 0.3, hh - 0.15, hh - 0.04];
    Wl.face([HX0, y0, ZN], [0, 0, -1], [0, 1, 0], ZN - HZ0, hh, { vEdges: VE, color: wc(ZN - HZ0) });
    Wl.face([HX1, y0, HZ0], [0, 0, 1], [0, 1, 0], ZN - HZ0, hh, { vEdges: VE, hole: [0.1, 0.9, 0, DTOP - LAND], color: wc(ZN - HZ0) });
    Wl.face([HX0, y0, HZ0], [1, 0, 0], [0, 1, 0], HX1 - HX0, hh, { vEdges: VE, hole: [0.25, 0.9, 0.95, 2.0], color: wc(HX1 - HX0) });
    Wl.face([HX1, y0, ZN], [-1, 0, 0], [0, 1, 0], HX1 - HX0, hh, { vEdges: VE, hole: [HX1 - DX1, HX1 - DX0, 0, DTOP - LAND], color: wc(HX1 - HX0) });
    F.grid([HX0, y0, HZ0], [0, 0, 1], [1, 0, 0], brk(0, ZN - HZ0, 0.3), brk(0, HX1 - HX0, 0.3), {
      color: (x, y, z) => 1 - 0.3 * Math.exp(-Math.min(x - HX0, HX1 - x, z - HZ0) / 0.06),
    });
    Ce.grid([HX0, TOP, HZ0], [1, 0, 0], [0, 0, 1], brk(0, HX1 - HX0, 0.3), brk(0, ZN - HZ0, 0.3), { color: 0.95 });
    // baseboards
    const base = [[0, 0], [0.013, 0], [0.013, 0.08], [0.01, 0.092], [0.005, 0.1], [0, 0.104]];
    const bb = (a, c, out) => runProfile(T, base, a, c, out, [0, 1, 0], { color: 0.95 });
    bb([HX0, y0, HZ0], [HX0, y0, ZN], [1, 0, 0]);
    bb([HX0, y0, HZ0], [HX1, y0, HZ0], [0, 0, 1]);
    bb([HX1, y0, HZ0], [HX1, y0, HZ0 + 0.1], [-1, 0, 0]);
    bb([HX1, y0, HZ0 + 0.9], [HX1, y0, ZN], [-1, 0, 0]);
    bb([HX0, y0, ZN], [DX0 - 0.065, y0, ZN], [0, 0, -1]);
    bb([DX1 + 0.065, y0, ZN], [HX1, y0, ZN], [0, 0, -1]);
    // casing around the door we came through (hall side)
    const cas = [[0, 0], [0.065, 0], [0.065, 0.012], [0.058, 0.0165], [0.02, 0.0142], [0, 0.009]];
    runProfile(T, cas, [DX0, y0, ZN], [DX0, DTOP, ZN], [-1, 0, 0], [0, 0, -1], { color: 1 });
    runProfile(T, cas, [DX1, y0, ZN], [DX1, DTOP, ZN], [1, 0, 0], [0, 0, -1], { color: 1 });
    runProfile(T, cas, [DX0 - 0.075, DTOP, ZN], [DX1 + 0.075, DTOP, ZN], [0, 1, 0], [0, 0, -1], { color: 1 });
    // a closed bedroom door on the east wall
    const dz0 = HZ0 + 0.1, dz1 = HZ0 + 0.9;
    const bd = this._sixPanelDoor(0.8, DTOP - LAND - 0.015, 0.04, this.mats.hallTrim, this.mats.hallBrass);
    bd.position.set(HX1, LAND, dz0); bd.rotation.y = -Math.PI / 2;
    bd.traverse((m) => { if (m.isMesh) { m.castShadow = false; m.receiveShadow = false; } });
    par.add(bd);
    runProfile(T, cas, [HX1, y0, dz0], [HX1, DTOP, dz0], [0, 0, -1], [-1, 0, 0], { color: 1 });
    runProfile(T, cas, [HX1, y0, dz1], [HX1, DTOP, dz1], [0, 0, 1], [-1, 0, 0], { color: 1 });
    runProfile(T, cas, [HX1, DTOP, dz0 - 0.075], [HX1, DTOP, dz1 + 0.075], [0, 1, 0], [-1, 0, 0], { color: 1 });
    // end window (night) with curtains
    const wx0 = HX0 + 0.25, wx1 = HX0 + 0.9, wy0 = y0 + 0.95, wy1 = y0 + 2.0;
    const night = new THREE.Mesh(new THREE.PlaneGeometry(wx1 - wx0, wy1 - wy0), this.mats.hallNight);
    night.position.set((wx0 + wx1) / 2, (wy0 + wy1) / 2, HZ0 - 0.06); par.add(night);
    T.box([wx0, wy0 - 0.03, HZ0], [wx1, wy0, HZ0 + 0.05], { faces: ['py', 'pz'], color: 1 });
    for (const [a, b] of [[[wx0, wy0, HZ0 - 0.06], [wx1, wy0 + 0.03, HZ0]], [[wx0, wy1 - 0.03, HZ0 - 0.06], [wx1, wy1, HZ0]], [[wx0, wy0, HZ0 - 0.06], [wx0 + 0.03, wy1, HZ0]], [[wx1 - 0.03, wy0, HZ0 - 0.06], [wx1, wy1, HZ0]], [[(wx0 + wx1) / 2 - 0.012, wy0, HZ0 - 0.05], [(wx0 + wx1) / 2 + 0.012, wy1, HZ0 - 0.03]]]) T.box(a, b, { color: 0.97 });
    const Fa = this.B('hallFabric');
    for (const side of [-1, 1]) {
      const cw = 0.42, ch = 1.25, g = new THREE.PlaneGeometry(cw, ch, 24, 1), p = g.attributes.position;
      for (let i = 0; i < p.count; i++) p.setZ(i, Math.sin((p.getX(i) / cw) * Math.PI * 7) * 0.025);
      g.computeVertexNormals();
      Fa.geo(g, M((wx0 + wx1) / 2 + side * 0.36, wy1 + 0.1 - ch / 2, HZ0 + 0.06), { uvScale: 1 });
    }
    this.B('hallBrass').geo(new THREE.CylinderGeometry(0.01, 0.01, 1.2, 10), M((wx0 + wx1) / 2, wy1 + 0.12, HZ0 + 0.06, 0, 0, Math.PI / 2));
    // painting on the west wall
    const art = new THREE.Mesh(new THREE.PlaneGeometry(0.42, 0.32), this.mats.hallArt);
    art.position.set(HX0 + 0.022, y0 + 1.6, -3.7); art.rotation.y = Math.PI / 2; par.add(art);
    const Hw = this.B('hallWood');
    for (const [a, b] of [[[HX0, y0 + 1.42, -3.95], [HX0 + 0.025, y0 + 1.44, -3.45]], [[HX0, y0 + 1.76, -3.95], [HX0 + 0.025, y0 + 1.78, -3.45]], [[HX0, y0 + 1.42, -3.95], [HX0 + 0.025, y0 + 1.78, -3.93]], [[HX0, y0 + 1.42, -3.47], [HX0 + 0.025, y0 + 1.78, -3.45]]]) Hw.box(a, b, { worldUV: true });
    // runner rug
    const rug = new THREE.Mesh(new THREE.PlaneGeometry(0.62, 1.3), this.mats.hallRug);
    rug.rotation.x = -Math.PI / 2; rug.position.set((HX0 + HX1) / 2, y0 + 0.004, -3.6); par.add(rug);
    // flush ceiling fixture (glowing; the light itself is Lighting.doorLight)
    const fx = new THREE.Mesh(new THREE.SphereGeometry(0.15, 24, 10, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), this.mats.hallGlow);
    fx.scale.set(1, 0.45, 1); fx.position.set(UD.centerX, TOP - 0.01, -3.65); par.add(fx);
  }

  /** Procedural 6-panel door. Local frame: x 0..w from the hinge edge, y from 0 (bottom of slab), z -t..0 (front = +Z). */
  _sixPanelDoor(w, h, t, paint, metal, { knobSide = 'both', hinges = true, grime = 0.15 } = {}) {
    const g = new THREE.Group(); g.name = 'sixPanelDoor';
    const b = new MB(), m = new MB();
    const col = (x, y, z) => {
      let c = 1 - grime * 0.6 * Math.exp(-(((x - (w - 0.07)) ** 2) / 0.006 + ((y - 0.95) ** 2) / 0.05)); // hand grime by the knob
      c *= 1 - grime * 0.5 * Math.exp(-y / 0.15);
      c *= 0.97 + 0.04 * fbm(x * 4, y * 4, z * 4, 2);
      return c;
    };
    // slab edges
    b.box([0.002, 0, -t], [w - 0.002, h, 0], { color: col, faces: ['px', 'nx', 'py', 'ny'] });
    // Faces: flat stiles / rails / mullions + recessed "pocket" panels (bevel down, then a raised field). Every visible
    // face normal points mostly outward (±Z), so the unshadowed light behind the door never lights the grooves.
    const face = new MB();
    const st = 0.11, mu = 0.09, pw = (w - 2 * st - mu) / 2;
    const rails = [[0, 0.21], [0.69, 0.87], [1.56, 1.67], [1.9, h]].map(([a, c]) => [a, Math.min(c, h)]);
    const rows = [[0.21, 0.69], [0.87, 1.56], [1.67, 1.9]];
    const q = (x0, x1, y0, y1) => face.grid([x0, y0, 0], [1, 0, 0], [0, 1, 0], brk(0, x1 - x0, 0.3), brk(0, y1 - y0, 0.4));
    q(0.002, st, 0, h); q(w - st, w - 0.002, 0, h);
    for (const [a, c] of rails) q(st, w - st, a, c);
    for (const [a, c] of rows) {
      q(st + pw, st + pw + mu, a, c);
      for (const px of [st + pw / 2, w - st - pw / 2]) face.geo(pocketGeo(pw, c - a, [[0, 0], [0.011, -0.0075], [0.036, -0.0028]]), M(px, (a + c) / 2, 0), { uvScale: 1 });
    }
    const fg = face.build();
    b.geo(fg, new THREE.Matrix4(), { uvScale: 1, color: col });
    b.geo(fg, new THREE.Matrix4().makeRotationY(Math.PI).setPosition(w, 0, -t), { uvScale: 1, color: col }); // back face (mirrored)
    fg.dispose();
    const kn = knobGeo();
    for (const side of knobSide === 'both' ? [1, -1] : [knobSide === 'front' ? 1 : -1]) {
      const zf = side > 0 ? 0 : -t;
      m.geo(kn, M(w - 0.065, 0.93, zf, side * Math.PI / 2, 0, 0));
    }
    if (hinges) {
      const kc = new THREE.CylinderGeometry(0.0065, 0.0065, 0.09, 10);
      for (const y of [0.2, h / 2, h - 0.25]) m.geo(kc, M(-0.001, y, 0.004));
    }
    // slab UVs x3: the paint's white_stucco normal is the shared 1.5 m texture (UV_SCALE.trim); small hardware: no shadow pass
    const slab = new THREE.Mesh(scaleUV(b.build(), UV_SCALE.trim), paint); slab.castShadow = true; slab.receiveShadow = true; slab.name = 'doorSlab';
    const hw = new THREE.Mesh(m.build(), metal); hw.castShadow = false; hw.receiveShadow = true; hw.name = 'doorHardware';
    g.add(slab, hw);
    return g;
  }

  // ---------------------------------------------------------------------------------------------- doors (handles)

  _upstairsDoor() {
    const pivot = new THREE.Group(); pivot.name = 'door.upstairs';
    pivot.position.set(UD.hingeX, UD.bottomY, UD.z);
    const door = this._sixPanelDoor(UD.width - 0.004, UD.height - 0.018, UD.thickness, this.mats.doorPaint, this.mats.brass);
    door.position.set(0.002, 0.015, 0);
    pivot.add(door);
    const proxy = new THREE.Mesh(this._unitBox, this._occMat);
    proxy.scale.set(UD.width, UD.height, 0.06); proxy.position.set(UD.width / 2, UD.height / 2, -UD.thickness / 2);
    pivot.add(proxy);
    const center = new THREE.Object3D(); center.position.set(UD.width / 2, 1.0, -UD.thickness / 2); pivot.add(center);
    this.root.add(pivot);
    const collider = this.world.addCollider([DX0, LAND, ZN], [DX1, DTOP, Z0], 'door');
    this.world.addOccluder(proxy);
    const d = this._door({
      id: 'door.upstairs', pivot, center, openAngle: UD.openAngle, duration: 1.1, locked: true, collider,
      sfx: { open: ['door_creak_open', 1, 1], close: ['door_close', 1, 1] },
      onChange: (t) => { this.upstairsDoorOpen = t; if (!this._hallWarm) this.hall.visible = t > 0.002; },
    });
    this.world.handles['door.upstairs'] = d.handle;
  }

  _closetDoor() {
    const D = CL.door, pivot = new THREE.Group(); pivot.name = 'door.closet';
    pivot.position.set(KX1, 0, D.hingeZ);
    const b = new MB(), w = D.width - 0.006, h = D.height - 0.012, t = 0.032;
    const col = (x, y, z) => (1 - 0.12 * Math.exp(-(((z - (w - 0.06)) ** 2) / 0.004 + ((y - 0.95) ** 2) / 0.04))) * (0.96 + 0.05 * fbm(x * 5, y * 5, z * 5, 2));
    const rb = (x0, x1, y0, y1, z0, z1, r = 0.003) => b.geo(new RoundedBoxGeometry(x1 - x0, y1 - y0, z1 - z0, 1, r), M((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), { uvScale: 0.5, color: col });
    const zs = 0.003, ze = zs + w, sw = 0.056, y0 = 0.012;
    // stiles + rails (local x: -t..0 is the slab thickness, front face (room) at x = 0)
    rb(-t, 0, y0, y0 + h, zs, zs + sw); rb(-t, 0, y0, y0 + h, ze - sw, ze);
    const rails = [[y0, y0 + 0.13], [y0 + 0.94, y0 + 1.02], [y0 + h - 0.085, y0 + h]];
    for (const [a, c] of rails) rb(-t, 0, a, c, zs + sw, ze - sw);
    // louvers: separate thin slats (see-through gaps), sloping down toward the room
    const slat = new THREE.BoxGeometry(0.038, 0.0055, ze - zs - 2 * sw + 0.01);
    const sections = [[rails[0][1], rails[1][0]], [rails[1][1], rails[2][0]]];
    for (const [a, c] of sections) {
      const n = Math.floor((c - a) / 0.044);
      const pitch = (c - a) / n;
      for (let i = 0; i < n; i++) {
        const y = a + pitch * (i + 0.5);
        b.geo(slat, M(-t / 2, y, (zs + ze) / 2, 0, 0, -0.68), { uvScale: 0.4, color: col });
      }
    }
    const leaf = new THREE.Mesh(scaleUV(b.build(), UV_SCALE.trim), this.mats.trim); leaf.castShadow = true; leaf.receiveShadow = true; leaf.name = 'closetLeaf';
    pivot.add(leaf);
    const m = new MB(), kn = knobGeo(0.75);
    m.geo(kn, M(0, 0.95, ze - 0.06, 0, 0, -Math.PI / 2));
    m.geo(kn, M(-t, 0.95, ze - 0.06, 0, 0, Math.PI / 2));
    const kc = new THREE.CylinderGeometry(0.006, 0.006, 0.08, 10);
    for (const y of [0.25, 1.62]) m.geo(kc, M(0.004, y, 0.0));
    const hw = new THREE.Mesh(m.build(), this.mats.brass); hw.castShadow = false; hw.name = 'closetHardware'; // knobs / hinges: too small to cast
    pivot.add(hw);
    const proxy = new THREE.Mesh(this._unitBox, this._occMat);
    proxy.scale.set(0.05, D.height, D.width); proxy.position.set(-t / 2, D.height / 2, D.width / 2);
    pivot.add(proxy);
    const center = new THREE.Object3D(); center.position.set(-t / 2, 0.95, D.width / 2); pivot.add(center);
    this.root.add(pivot);
    this.world.addOccluder(proxy);
    // the closed leaf sits inside the knee wall collider; this one is the swung-open leaf (blocks walking through it)
    const openC = this.world.addCollider([KX1, 0, D.hingeZ - 0.05], [KX1 + D.width, D.height, D.hingeZ + 0.03], 'door');
    openC.enabled = false;
    const d = this._door({
      id: 'door.closet', pivot, center, openAngle: D.openAngle, duration: 0.6, locked: false, collider: null, openCollider: openC,
      sfx: { open: ['door_creak_open', 0.5, 1.3], close: ['door_close', 0.45, 1.35] },
    });
    this.world.handles['door.closet'] = d.handle;
    this.world.hideSpots.push({ ...CL, id: 'closet', doorSpec: CL.door, door: d.handle });
  }

  /** Door controller + Handle. collider: blocking box while closed; openCollider: enabled while open. */
  _door({ id, pivot, center, openAngle, duration, locked, collider, openCollider = null, sfx, onChange = null }) {
    const d = { pivot, openAngle, duration, t: 0, from: 0, target: 0, elapsed: 0, dur: 0, animating: false, waiters: [], collider, openCollider, sfx, onChange, center };
    const self = this;
    const handle = {
      id, object: pivot, isOpen: false, locked: !!locked,
      open() { return self._animDoor(d, 1); },
      close() { return self._animDoor(d, 0); },
      toggle() { return handle.isOpen ? handle.close() : handle.open(); },
      worldPosition(target = new THREE.Vector3()) { return center.getWorldPosition(target); },
    };
    d.handle = handle;
    this.doors.push(d);
    return d;
  }

  _sfx(d, which) {
    const s = d.sfx?.[which]; if (!s) return;
    try { this.game.audio?.play?.(s[0], { position: d.center.getWorldPosition(new THREE.Vector3()), volume: s[1], rate: s[2] }); } catch (e) { /* audio optional */ }
  }

  _animDoor(d, target) {
    if (d.target === target && !d.animating && Math.abs(d.t - target) < 1e-4) return Promise.resolve();
    d.handle.isOpen = target === 1;
    if (target === 1) {
      if (d.collider) d.collider.enabled = false;
      this._sfx(d, 'open');
    } else if (d.openCollider) d.openCollider.enabled = false;
    d.from = d.t; d.target = target; d.elapsed = 0;
    d.dur = Math.max(0.05, d.duration * Math.abs(target - d.t));
    d.animating = true;
    return new Promise((res) => d.waiters.push(res));
  }

  _setDoor(d, t) {
    d.t = t;
    d.pivot.rotation.y = d.openAngle * t;
    d.onChange?.(t);
  }

  update(dt) {
    if (this._hallWarm) { this._hallWarm = false; this.hall.visible = this.upstairsDoorOpen > 0.002; }
    for (const d of this.doors) {
      if (!d.animating) continue;
      d.elapsed += dt;
      const k = Math.min(1, d.elapsed / d.dur);
      // opening: quick start, slow settle; closing: accelerates into the frame
      const e = d.target > d.from ? 1 - (1 - k) ** 3 : k * k * (1.6 - 0.6 * k);
      this._setDoor(d, d.from + (d.target - d.from) * Math.min(1, e));
      if (k >= 1) {
        d.animating = false;
        this._setDoor(d, d.target);
        if (d.target === 0) { if (d.collider) d.collider.enabled = true; this._sfx(d, 'close'); }
        else if (d.openCollider) d.openCollider.enabled = true;
        const w = d.waiters; d.waiters = []; for (const r of w) r();
      }
    }
  }

  /** kind: 'caught' | 'new' — snaps the doors shut (the upstairs door keeps its locked flag unless 'new'). */
  reset(kind) {
    for (const d of this.doors) {
      d.animating = false; d.target = 0; d.from = 0;
      this._setDoor(d, 0);
      d.handle.isOpen = false;
      if (d.collider) d.collider.enabled = true;
      if (d.openCollider) d.openCollider.enabled = false;
      const w = d.waiters; d.waiters = []; for (const r of w) r();
    }
    if (kind === 'new' && this.world.handles['door.upstairs']) this.world.handles['door.upstairs'].locked = true;
  }

  // ---------------------------------------------------------------------------------------------- colliders, occluders, shadow casters

  _solids() {
    const w = this.world, cs = this.caster;
    const occ = (a, b) => {
      const m = new THREE.Mesh(this._unitBox, this._occMat);
      m.scale.set(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
      m.position.set((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2);
      m.name = 'occ'; this.occGroup.add(m); m.updateMatrixWorld(true); w.addOccluder(m);
    };
    const solid = (a, b, { col = true, oc = true, sh = true, tag = 'wall' } = {}) => {
      if (col) w.addCollider(a, b, tag);
      if (oc) occ(a, b);
      if (sh) cs.box([a[0], a[1], a[2]], [b[0], b[1], b[2]]);
    };
    const E = 0.05;
    // south foundation wall with the window hole
    w.addCollider([X0 - TW, 0, Z1], [X1 + TW, H, Z1 + TS], 'wall');
    solid([X0 - TW, -E, Z1], [X1 + TW, WIN.minY, Z1 + TS], { col: false });
    solid([X0 - TW, WIN.maxY, Z1], [X1 + TW, H + 0.25, Z1 + TS], { col: false });
    solid([X0 - TW, WIN.minY, Z1], [WIN.minX, WIN.maxY, Z1 + TS], { col: false });
    solid([WIN.maxX, WIN.minY, Z1], [X1 + TW, WIN.maxY, Z1 + TS], { col: false });
    // east wall (room + nook)
    solid([X1, -E, NN - TW], [X1 + TW, H + 0.25, Z1 + TS]);
    // west wall (room + closet + stairwell)
    solid([X0 - TW, -E, ZN], [X0, H + 0.25, Z1 + TS]);
    solid([X0 - TW, H + 0.25, ZN], [X0, TOP + 0.2, BZ1], { col: true });
    // north partition (doorway to the nook)
    solid([X0 - TW, -E, ZN], [AD0, H + 0.25, Z0]);
    solid([AD1, -E, ZN], [X1 + TW, H + 0.25, Z0]);
    solid([AD0, ADH, ZN], [AD1, H + 0.25, Z0]);
    // knee wall (one tall collider) + its occluder / caster pieces around the closet door
    w.addCollider([KX0 - 0.01, 0, Z0], [KX1 + 0.01, TOP, NZ1], 'wall');
    for (const [a, b] of [
      [[KX0, 0, Z0], [KX1, H, CDZ0]], [[KX0, CDH, CDZ0], [KX1, H, CDZ1]], [[KX0, 0, CDZ1], [KX1, H, KZS]],
      [[KX0, H, ZN], [KX1 + 0.05, TOP + 0.2, BZ0]],
    ]) solid(a, b, { col: false });
    for (let i = 0; i < 6; i++) { // sloped part as steps
      const za = KZS + (i * (NZ0 - KZS)) / 6, zb = KZS + ((i + 1) * (NZ0 - KZS)) / 6;
      solid([KX0, 0, za], [KX1, capY(zb), zb], { col: false, oc: true });
    }
    // stairwell north wall above the landing (door opening), bulkhead / south wall, top
    solid([X0 - TW, LAND, ZN], [DX0, TOP + 0.2, Z0]);
    solid([DX0, DTOP, ZN], [KX1, TOP + 0.2, Z0]);
    solid([X0, BY, BZ0], [KX1, TOP + 0.2, BZ1]);
    solid([X0 - TW, TOP, ZN], [KX1 + 0.05, TOP + 0.2, BZ1], { col: false });
    solid([X0, LAND_UNDER, Z0], [KX0, LAND, S.topZ], { col: false });
    // room ceiling slab (with the stair opening)
    solid([KX1, H, ZN], [X1 + TW, H + 0.25, Z1 + TS], { col: false });
    solid([X0 - TW, H, BZ1], [KX1, H + 0.25, Z1 + TS], { col: false });
    // nook
    solid([AL.minX - 0.12, -E, NN - TW], [X1 + TW, LAND + 0.15, NN]);
    solid([AL.minX - 0.12, -E, NN - TW], [AL.minX, LAND + 0.15, ZN]);
    solid([AL.minX - 0.12, LAND, NN - TW], [X1 + TW, LAND + 0.15, ZN], { col: false });
    w.addCollider([0.25, 0, -3.26], [0.37, LAND, -3.14], 'pipe');
    // upper hallway
    solid([HX0 - 0.2, LAND, HZ0 - 0.2], [HX0, TOP, ZN], { sh: false });
    solid([HX1, LAND, HZ0 - 0.2], [HX1 + 0.2, TOP, ZN], { sh: false });
    solid([HX0 - 0.2, LAND, HZ0 - 0.2], [HX1 + 0.2, TOP, HZ0], { sh: false });
    solid([HX0, LAND, ZN], [DX0, TOP, Z0], { sh: false });
    solid([DX1, LAND, ZN], [HX1, TOP, Z0], { sh: false });
    // closet south partition (occluder only)
    occ([X0, 0, CL.maxZ - 0.1], [KX0, underY(CL.maxZ), CL.maxZ]);
  }
}
