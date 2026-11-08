import * as THREE from 'three';

// Procedural canvas textures for the props module (no external images).
// Everything is drawn once at build time (except the TV static, which is animated by TVStatic.draw()).
// Conventions: functions return a THREE.CanvasTexture (sRGB, mipmapped) unless noted; `.image` is the canvas (a
// downscaled copy when the setMaxSize() cap applies — low/medium: 512 px).
// Kid writing uses an internal stroke font (capital letters, wobbly crayon strokes) so it looks hand-made even
// when the web fonts are unavailable; adult handwriting uses Caveat (loaded by index.html) with per-glyph jitter.

export const FONT = {
  hand: "'Caveat', 'Bradley Hand', 'Segoe Print', 'Comic Sans MS', cursive",
  type: "'Special Elite', 'Courier New', Courier, monospace",
  serif: "'Times New Roman', Times, Georgia, serif",
  sans: "'Arial Black', 'Arial Bold', Arial, Helvetica, sans-serif",
};

let _fontsReady = null;
/** Resolve when the handwriting / typewriter fonts are loaded (or after `timeout` ms). Never rejects. */
export function waitFonts(timeout = 2500) {
  if (_fontsReady) return _fontsReady;
  const fonts = typeof document !== 'undefined' ? document.fonts : null;
  if (!fonts || !fonts.load) { _fontsReady = Promise.resolve(); return _fontsReady; }
  const list = ['500 48px Caveat', '700 48px Caveat', '32px "Special Elite"', '32px "Rock Salt"'];
  const all = Promise.all(list.map((f) => fonts.load(f).catch(() => null)));
  _fontsReady = Promise.race([all, new Promise((r) => setTimeout(r, timeout))]).then(() => {}, () => {});
  return _fontsReady;
}

/** Small deterministic PRNG (mulberry32). Returns () => [0,1). */
export function makeRng(seed = 1) {
  let s = (seed >>> 0) || 1;
  return () => {
    s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function makeCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(w)); c.height = Math.max(1, Math.round(h));
  return c;
}

let _aniso = 4;
export function setAnisotropy(a) { _aniso = a || 4; }

// GPU memory cap for the generated canvases (px, longest side; 0 = none). Props sets 512 on low/medium, like the
// downscale of the model textures in Assets. Textures are still drawn at full size (same strokes, same text layout)
// and then resampled, so the look only loses resolution, never layout.
let _maxSize = 0;
export function setMaxSize(px) { _maxSize = px > 0 ? Math.round(px) : 0; }

/** Downscaled copy of `c` when it exceeds the cap (high-quality smoothing), else `c` itself. */
export function capCanvas(c, max = _maxSize) {
  const m = Math.max(c.width, c.height);
  if (!max || m <= max) return c;
  const k = max / m;
  const d = makeCanvas(c.width * k, c.height * k), g = d.getContext('2d');
  g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
  g.drawImage(c, 0, 0, d.width, d.height);
  return d;
}

/**
 * CanvasTexture factory. Mipmaps: on by default (trilinear: the props are mostly seen small / at grazing angles);
 * textures that are redrawn at runtime pass { mipmaps: false, cap: false } (no per-update mip chain rebuild and the
 * texture must keep using the canvas that gets redrawn).
 */
export function canvasTexture(c, { srgb = true, mipmaps = true, repeat = false, cap = true } = {}) {
  if (cap) c = capCanvas(c);
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = _aniso;
  t.generateMipmaps = mipmaps;
  t.minFilter = mipmaps ? THREE.LinearMipmapLinearFilter : THREE.LinearFilter;
  if (repeat) t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.needsUpdate = true;
  return t;
}

// ------------------------------------------------------------------------------------------------ helpers

const TAU = Math.PI * 2;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);

function ellipsePts(cx, cy, rx, ry, n = 18, start = -Math.PI / 2, sweep = TAU * 1.06) {
  const p = [];
  for (let i = 0; i <= n; i++) {
    const a = start + (sweep * i) / n;
    p.push(cx + Math.cos(a) * rx, cy + Math.sin(a) * ry);
  }
  return p;
}

/** Fill with a base color + fibre grain + aging. */
function paperBase(g, w, h, R, { base = [241, 236, 222], grain = 14, age = 0.22, blotches = 3, wrinkles = 0 } = {}) {
  const img = g.createImageData(w, h);
  const d = img.data;
  // low-frequency mottling via a tiny value grid
  const gw = 8, gh = 8, grid = new Float32Array((gw + 1) * (gh + 1));
  for (let i = 0; i < grid.length; i++) grid[i] = R() - 0.5;
  for (let y = 0; y < h; y++) {
    const fy = (y / h) * gh, iy = Math.floor(fy), ty = fy - iy;
    for (let x = 0; x < w; x++) {
      const fx = (x / w) * gw, ix = Math.floor(fx), tx = fx - ix;
      const a = grid[iy * (gw + 1) + ix], b = grid[iy * (gw + 1) + ix + 1];
      const c = grid[(iy + 1) * (gw + 1) + ix], e = grid[(iy + 1) * (gw + 1) + ix + 1];
      const m = (a + (b - a) * tx) * (1 - ty) + (c + (e - c) * tx) * ty;
      const n = (R() - 0.5) * grain + m * 10;
      const i = (y * w + x) * 4;
      d[i] = clamp(base[0] + n, 0, 255);
      d[i + 1] = clamp(base[1] + n, 0, 255);
      d[i + 2] = clamp(base[2] + n * 1.1 - m * 6, 0, 255);
      d[i + 3] = 255;
    }
  }
  g.putImageData(img, 0, 0);
  // yellowed edges
  const rg = g.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.25, w / 2, h / 2, Math.hypot(w, h) * 0.55);
  rg.addColorStop(0, 'rgba(160,120,50,0)');
  rg.addColorStop(1, `rgba(160,118,48,${age})`);
  g.fillStyle = rg; g.fillRect(0, 0, w, h);
  // faint blotches (water / fingers)
  for (let k = 0; k < blotches; k++) {
    const x = R() * w, y = R() * h, r = (0.04 + R() * 0.12) * Math.min(w, h);
    const bg = g.createRadialGradient(x, y, r * 0.2, x, y, r);
    bg.addColorStop(0, `rgba(140,105,50,${0.04 + R() * 0.05})`);
    bg.addColorStop(0.85, `rgba(130,95,40,${0.05 + R() * 0.05})`);
    bg.addColorStop(1, 'rgba(130,95,40,0)');
    g.fillStyle = bg; g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill();
  }
  // wrinkles / fold creases: thin light+dark line pairs
  for (let k = 0; k < wrinkles; k++) {
    const vertical = R() < 0.5;
    const p = (0.3 + R() * 0.4) * (vertical ? w : h);
    g.lineWidth = 1.2;
    for (let s = 0; s < 2; s++) {
      g.strokeStyle = s ? 'rgba(255,255,255,0.35)' : 'rgba(90,70,40,0.18)';
      g.beginPath();
      for (let t = 0; t <= 1.0001; t += 0.1) {
        const j = (R() - 0.5) * 3 + s * 1.6;
        if (vertical) g.lineTo(p + j, t * h); else g.lineTo(t * w, p + j);
      }
      g.stroke();
    }
  }
}

/** Speckle noise pattern used to "break" crayon strokes (paper tooth). */
function grainPattern(g, R, density = 0.5) {
  const c = makeCanvas(96, 96), x = c.getContext('2d');
  const img = x.createImageData(96, 96);
  for (let i = 0; i < img.data.length; i += 4) {
    img.data[i] = img.data[i + 1] = img.data[i + 2] = 255;
    img.data[i + 3] = R() < density ? Math.floor(R() * 255) : 0;
  }
  x.putImageData(img, 0, 0);
  return g.createPattern(c, 'repeat');
}

// ------------------------------------------------------------------------------------------------ stroke font
// Capital letters / digits as polylines in a unit box (x: 0..w, y: 0 top .. 1 baseline).

const OVAL = (w) => ellipsePts(w / 2, 0.5, w / 2, 0.5, 16, -Math.PI * 0.6, TAU * 1.05);
const E_ = [[0.6, 0, 0, 0, 0, 1, 0.6, 1], [0, 0.5, 0.45, 0.5]];
const A_ = [[0, 1, 0.4, 0, 0.8, 1], [0.16, 0.62, 0.66, 0.62]];
const GLYPHS = {
  A: { w: 0.8, s: A_ },
  B: { w: 0.7, s: [[0, 1, 0, 0, 0.45, 0, 0.65, 0.1, 0.65, 0.36, 0.45, 0.47, 0, 0.47], [0.45, 0.47, 0.7, 0.58, 0.7, 0.88, 0.48, 1, 0, 1]] },
  C: { w: 0.7, s: [[0.7, 0.15, 0.5, 0, 0.25, 0.02, 0.05, 0.22, 0, 0.5, 0.06, 0.8, 0.28, 1, 0.52, 1, 0.72, 0.86]] },
  D: { w: 0.72, s: [[0, 0, 0, 1, 0.35, 1, 0.62, 0.85, 0.72, 0.5, 0.62, 0.16, 0.35, 0, 0, 0]] },
  E: { w: 0.6, s: E_ },
  F: { w: 0.58, s: [[0.6, 0, 0, 0, 0, 1], [0, 0.48, 0.45, 0.48]] },
  G: { w: 0.75, s: [[0.72, 0.14, 0.52, 0, 0.26, 0.02, 0.06, 0.22, 0, 0.5, 0.06, 0.8, 0.28, 1, 0.55, 1, 0.75, 0.85, 0.75, 0.56, 0.42, 0.56]] },
  H: { w: 0.7, s: [[0, 0, 0, 1], [0.7, 0, 0.7, 1], [0, 0.5, 0.7, 0.5]] },
  I: { w: 0.16, s: [[0.08, 0, 0.08, 1]] },
  J: { w: 0.55, s: [[0.55, 0, 0.55, 0.75, 0.42, 0.97, 0.2, 1, 0, 0.82]] },
  K: { w: 0.66, s: [[0, 0, 0, 1], [0.62, 0, 0, 0.58], [0.2, 0.42, 0.66, 1]] },
  L: { w: 0.55, s: [[0, 0, 0, 1, 0.55, 1]] },
  M: { w: 0.9, s: [[0, 1, 0.05, 0, 0.45, 0.62, 0.85, 0, 0.9, 1]] },
  N: { w: 0.72, s: [[0, 1, 0, 0, 0.72, 1, 0.72, 0]] },
  O: { w: 0.8, s: [OVAL(0.8)] },
  P: { w: 0.62, s: [[0, 1, 0, 0, 0.42, 0, 0.62, 0.12, 0.62, 0.36, 0.42, 0.5, 0, 0.5]] },
  Q: { w: 0.8, s: [OVAL(0.8), [0.5, 0.72, 0.85, 1.05]] },
  R: { w: 0.65, s: [[0, 1, 0, 0, 0.42, 0, 0.62, 0.12, 0.62, 0.36, 0.42, 0.5, 0, 0.5], [0.3, 0.5, 0.66, 1]] },
  S: { w: 0.62, s: [[0.6, 0.12, 0.4, 0, 0.18, 0.02, 0.03, 0.16, 0.06, 0.38, 0.32, 0.5, 0.56, 0.6, 0.62, 0.82, 0.46, 0.98, 0.2, 1, 0, 0.86]] },
  T: { w: 0.7, s: [[0, 0, 0.7, 0], [0.35, 0, 0.35, 1]] },
  U: { w: 0.7, s: [[0, 0, 0, 0.72, 0.12, 0.95, 0.35, 1, 0.58, 0.95, 0.7, 0.72, 0.7, 0]] },
  V: { w: 0.72, s: [[0, 0, 0.36, 1, 0.72, 0]] },
  W: { w: 1.0, s: [[0, 0, 0.22, 1, 0.5, 0.3, 0.78, 1, 1, 0]] },
  X: { w: 0.7, s: [[0, 0, 0.7, 1], [0.7, 0, 0, 1]] },
  Y: { w: 0.7, s: [[0, 0, 0.35, 0.5, 0.7, 0], [0.35, 0.5, 0.35, 1]] },
  Z: { w: 0.66, s: [[0, 0, 0.66, 0, 0, 1, 0.66, 1]] },
  'É': { w: 0.6, s: [...E_, [0.18, -0.12, 0.42, -0.3]] },
  'È': { w: 0.6, s: [...E_, [0.18, -0.3, 0.42, -0.12]] },
  'Ê': { w: 0.6, s: [...E_, [0.12, -0.12, 0.3, -0.3, 0.48, -0.12]] },
  'À': { w: 0.8, s: [...A_, [0.25, -0.3, 0.5, -0.12]] },
  'Ç': { w: 0.7, s: [[0.7, 0.15, 0.5, 0, 0.25, 0.02, 0.05, 0.22, 0, 0.5, 0.06, 0.8, 0.28, 1, 0.52, 1, 0.72, 0.86], [0.36, 1, 0.4, 1.15, 0.28, 1.25]] },
  0: { w: 0.6, s: [OVAL(0.6)] },
  1: { w: 0.42, s: [[0.04, 0.3, 0.34, 0, 0.34, 1]] },
  2: { w: 0.6, s: [[0.02, 0.22, 0.2, 0.03, 0.42, 0, 0.58, 0.15, 0.55, 0.4, 0, 1, 0.62, 1]] },
  3: { w: 0.58, s: [[0.02, 0.12, 0.25, 0, 0.5, 0.04, 0.56, 0.24, 0.42, 0.44, 0.2, 0.48], [0.42, 0.48, 0.6, 0.64, 0.58, 0.88, 0.38, 1, 0.12, 0.98, 0, 0.86]] },
  4: { w: 0.62, s: [[0.48, 1, 0.48, 0, 0, 0.68, 0.62, 0.68]] },
  5: { w: 0.58, s: [[0.56, 0, 0.1, 0, 0.06, 0.44, 0.3, 0.38, 0.52, 0.48, 0.6, 0.72, 0.48, 0.94, 0.25, 1, 0, 0.88]] },
  6: { w: 0.58, s: [[0.52, 0.04, 0.3, 0, 0.1, 0.2, 0, 0.55, 0.06, 0.85, 0.28, 1, 0.5, 0.94, 0.58, 0.72, 0.48, 0.52, 0.26, 0.46, 0.06, 0.58]] },
  7: { w: 0.6, s: [[0, 0, 0.6, 0, 0.22, 1], [0.14, 0.52, 0.54, 0.52]] },
  8: { w: 0.58, s: [[0.29, 0.47, 0.08, 0.36, 0.06, 0.13, 0.26, 0, 0.46, 0.04, 0.52, 0.24, 0.29, 0.47, 0.04, 0.66, 0.04, 0.9, 0.26, 1, 0.5, 0.95, 0.56, 0.72, 0.29, 0.47]] },
  9: { w: 0.58, s: [[0.55, 0.42, 0.32, 0.55, 0.08, 0.48, 0.02, 0.24, 0.18, 0.03, 0.4, 0, 0.56, 0.15, 0.58, 0.45, 0.52, 0.8, 0.36, 1, 0.08, 0.95]] },
  '.': { w: 0.16, s: [[0.07, 0.94, 0.09, 0.97]] },
  ',': { w: 0.16, s: [[0.1, 0.9, 0.04, 1.1]] },
  '·': { w: 0.34, s: [[0.15, 0.5, 0.18, 0.53]] },
  '!': { w: 0.16, s: [[0.08, 0, 0.08, 0.68], [0.08, 0.93, 0.09, 0.96]] },
  '?': { w: 0.5, s: [[0.02, 0.2, 0.18, 0.02, 0.38, 0.02, 0.5, 0.18, 0.45, 0.38, 0.25, 0.55, 0.25, 0.72], [0.25, 0.93, 0.26, 0.96]] },
  ':': { w: 0.16, s: [[0.08, 0.35, 0.09, 0.38], [0.08, 0.9, 0.09, 0.93]] },
  '-': { w: 0.4, s: [[0.02, 0.55, 0.38, 0.55]] },
  "'": { w: 0.16, s: [[0.1, 0, 0.06, 0.22]] },
  '♥': { w: 0.8, s: [[0.4, 1, 0.05, 0.55, 0, 0.25, 0.15, 0.05, 0.32, 0.05, 0.4, 0.25, 0.48, 0.05, 0.65, 0.05, 0.8, 0.25, 0.75, 0.55, 0.4, 1]] },
  '→': { w: 0.8, s: [[0, 0.55, 0.75, 0.55], [0.52, 0.32, 0.78, 0.55, 0.52, 0.78]] },
  ' ': { w: 0.5, s: [] },
};

/** Width (in px) of a kid-written string at letter height h. */
export function strokeTextWidth(text, h, spacing = 0.22) {
  let w = 0;
  for (const ch of text.toUpperCase()) w += ((GLYPHS[ch] || GLYPHS[' ']).w + spacing) * h;
  return w;
}

// ------------------------------------------------------------------------------------------------ crayon / marker layer

/**
 * A transparent drawing layer with crayon / felt-pen tools. finish() breaks the strokes with paper "tooth"
 * and multiplies the layer onto a paper canvas.
 */
class Pen {
  constructor(w, h, seed) {
    this.w = w; this.h = h;
    this.c = makeCanvas(w, h);
    this.g = this.c.getContext('2d');
    this.R = makeRng(seed);
    this.g.lineCap = 'round'; this.g.lineJoin = 'round';
  }

  /** Wobbly crayon polyline (flat [x,y,...] array). */
  line(pts, color, width = 5, passes = 3, alpha = 1) {
    const g = this.g, R = this.R;
    g.save();
    g.strokeStyle = color; g.lineCap = 'round'; g.lineJoin = 'round';
    for (let p = 0; p < passes; p++) {
      g.globalAlpha = (0.4 + R() * 0.3) * alpha;
      g.lineWidth = width * (0.65 + R() * 0.5);
      const ox = (R() - 0.5) * width * 0.5, oy = (R() - 0.5) * width * 0.5;
      g.beginPath();
      for (let i = 0; i < pts.length; i += 2) {
        const x = pts[i] + ox + (R() - 0.5) * width * 0.45, y = pts[i + 1] + oy + (R() - 0.5) * width * 0.45;
        if (i === 0) g.moveTo(x, y); else g.lineTo(x, y);
      }
      g.stroke();
    }
    g.restore();
  }

  /** Smooth felt-pen stroke (solid, slight ink bleed). */
  marker(pts, color, width = 4, alpha = 0.95) {
    const g = this.g;
    g.save();
    g.strokeStyle = color; g.globalAlpha = alpha; g.lineWidth = width;
    g.shadowColor = color; g.shadowBlur = width * 0.6;
    g.beginPath();
    for (let i = 0; i < pts.length; i += 2) {
      const x = pts[i] + (this.R() - 0.5) * width * 0.15, y = pts[i + 1] + (this.R() - 0.5) * width * 0.15;
      if (i === 0) g.moveTo(x, y); else g.lineTo(x, y);
    }
    g.stroke();
    g.restore();
  }

  oval(cx, cy, rx, ry, color, width = 5, passes = 2) {
    this.line(ellipsePts(cx, cy, rx * (0.96 + this.R() * 0.08), ry * (0.96 + this.R() * 0.08), 22, -Math.PI / 2 + this.R(), TAU * (1.04 + this.R() * 0.08)), color, width, passes);
  }

  /** Kid-style back-and-forth coloring inside a path (pathFn(ctx) builds it). */
  fill(pathFn, color, { angle = 0.6, spacing = 7, width = 8, alpha = 0.75, bbox = null } = {}) {
    const g = this.g, R = this.R;
    g.save();
    g.beginPath(); pathFn(g); g.clip();
    const [x0, y0, x1, y1] = bbox || [0, 0, this.w, this.h];
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, D = Math.hypot(x1 - x0, y1 - y0) / 2 + width;
    const ux = Math.cos(angle), uy = Math.sin(angle), vx = -uy, vy = ux;
    g.strokeStyle = color; g.lineCap = 'round'; g.lineJoin = 'round';
    for (let pass = 0; pass < 2; pass++) {
      g.globalAlpha = alpha * (pass ? 0.45 : 0.85);
      g.lineWidth = width * (pass ? 0.7 : 1);
      g.beginPath();
      let first = true;
      const off = pass * spacing * 0.5;
      for (let d = -D; d <= D; d += spacing) {
        const s = (Math.round((d + D) / spacing) % 2) ? 1 : -1;
        const j = (R() - 0.5) * spacing * 0.5;
        const ax = cx + ux * (d + off + j) - vx * D * s, ay = cy + uy * (d + off + j) - vy * D * s;
        if (first) { g.moveTo(ax, ay); first = false; } else g.lineTo(ax, ay);
      }
      g.stroke();
    }
    g.restore();
  }

  /** Kid capitals with the stroke font. Returns the end x. */
  text(str, x, y, h, color, { width = Math.max(2.5, h * 0.11), spacing = 0.22, wobble = 1, tilt = 0, marker = false, colors = null } = {}) {
    const R = this.R;
    let cx = x, i = 0;
    for (const ch of str.toUpperCase()) {
      const gl = GLYPHS[ch] || GLYPHS[' '];
      const sz = h * (1 + (R() - 0.5) * 0.22 * wobble);
      const rot = (R() - 0.5) * 0.22 * wobble + tilt;
      const by = y + (R() - 0.5) * h * 0.12 * wobble + (cx - x) * Math.sin(tilt);
      const cs = Math.cos(rot), sn = Math.sin(rot);
      const col = colors ? colors[i % colors.length] : color;
      for (const st of gl.s) {
        const pts = new Array(st.length);
        for (let k = 0; k < st.length; k += 2) {
          const lx = st[k] * sz, ly = (st[k + 1] - 1) * sz;
          pts[k] = cx + lx * cs - ly * sn;
          pts[k + 1] = by + lx * sn + ly * cs;
        }
        if (marker) this.marker(pts, col, width); else this.line(pts, col, width, 2);
      }
      cx += (gl.w + spacing) * h * (0.9 + R() * 0.2);
      i++;
    }
    return cx;
  }

  /** Break strokes with paper tooth, then multiply onto `dst` context. */
  finish(dst, { tooth = 0.55, mode = 'multiply', x = 0, y = 0 } = {}) {
    const g = this.g;
    if (tooth > 0) {
      g.save();
      g.globalCompositeOperation = 'destination-out';
      g.globalAlpha = tooth;
      g.fillStyle = grainPattern(g, this.R, 0.55);
      g.fillRect(0, 0, this.w, this.h);
      g.restore();
    }
    dst.save();
    dst.globalCompositeOperation = mode;
    dst.drawImage(this.c, x, y);
    dst.restore();
  }
}

function tape(g, x, y, w, h, rot, R) {
  g.save();
  g.translate(x, y); g.rotate(rot);
  g.fillStyle = 'rgba(222,205,160,0.62)';
  g.beginPath();
  // torn short edges
  g.moveTo(-w / 2, -h / 2);
  for (let i = 0; i <= 6; i++) g.lineTo(-w / 2 + (w * i) / 6, -h / 2 + (R() - 0.5) * 2);
  for (let i = 0; i <= 5; i++) g.lineTo(w / 2 + (R() - 0.5) * 4, -h / 2 + (h * i) / 5);
  for (let i = 6; i >= 0; i--) g.lineTo(-w / 2 + (w * i) / 6, h / 2 + (R() - 0.5) * 2);
  for (let i = 5; i >= 0; i--) g.lineTo(-w / 2 + (R() - 0.5) * 4, -h / 2 + (h * i) / 5);
  g.fill();
  g.strokeStyle = 'rgba(160,140,100,0.25)'; g.lineWidth = 1; g.stroke();
  g.restore();
}

/** Handwritten adult text line (Caveat with per-glyph jitter). */
function handLine(g, str, x, y, size, color, R, { slant = -0.02, jitter = 1 } = {}) {
  g.save();
  g.fillStyle = color;
  g.font = `600 ${size}px ${FONT.hand}`;
  g.textBaseline = 'alphabetic';
  let cx = x;
  for (const ch of str) {
    const w = g.measureText(ch).width;
    g.save();
    g.translate(cx, y + (R() - 0.5) * size * 0.06 * jitter);
    g.rotate(slant + (R() - 0.5) * 0.08 * jitter);
    g.globalAlpha = 0.78 + R() * 0.2;
    g.fillText(ch, 0, 0);
    g.restore();
    cx += w * (0.98 + (R() - 0.5) * 0.06);
  }
  g.restore();
  return cx;
}

// ------------------------------------------------------------------------------------------------ kids rug

/** Road-map play rug (1.8 x 1.3 m). Returns a texture of 1024x740. */
export function rugTexture(seed = 7) {
  const W = 1024, H = 740, R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  // base: grass green felt
  g.fillStyle = '#5f8a4a'; g.fillRect(0, 0, W, H);
  // patches of lighter/darker green, a blue pond, a park, a sandy beach
  const blob = (x, y, rx, ry, col) => { g.fillStyle = col; g.beginPath(); g.ellipse(x, y, rx, ry, R() * 3, 0, TAU); g.fill(); };
  for (let i = 0; i < 18; i++) blob(R() * W, R() * H, 30 + R() * 90, 20 + R() * 60, R() < 0.5 ? 'rgba(120,160,80,0.35)' : 'rgba(60,100,50,0.3)');
  blob(830, 560, 120, 80, '#d7c48a');
  blob(840, 565, 95, 60, '#3f86b8');
  blob(830, 560, 60, 34, '#5aa0cf');
  // river with bridge
  g.strokeStyle = '#3d7fb0'; g.lineWidth = 46; g.lineCap = 'round';
  g.beginPath(); g.moveTo(-20, 120); g.bezierCurveTo(200, 160, 260, 40, 430, 90); g.bezierCurveTo(560, 130, 600, 20, 700, -20); g.stroke();
  g.strokeStyle = 'rgba(140,190,230,0.5)'; g.lineWidth = 8;
  g.beginPath(); g.moveTo(-20, 116); g.bezierCurveTo(200, 156, 260, 36, 430, 86); g.stroke();
  // blocks (city): beige plots
  const plots = [];
  const rx = [40, 300, 560], ry = [210, 470];
  for (const x of rx) for (const y of ry) plots.push([x + 20, y + 22, 200, 180]);
  for (const [x, y, w, h] of plots) {
    g.fillStyle = R() < 0.5 ? '#c9b98f' : '#b5c08a';
    g.fillRect(x, y, w, h);
  }
  // roads (grey, white dashed center lines, sidewalks)
  const road = (x0, y0, x1, y1) => {
    g.lineCap = 'butt';
    g.strokeStyle = '#a7a39a'; g.lineWidth = 64; g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
    g.strokeStyle = '#55575a'; g.lineWidth = 52; g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke();
    g.setLineDash([22, 18]); g.strokeStyle = '#efe9d6'; g.lineWidth = 4;
    g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke(); g.setLineDash([]);
  };
  road(0, 200, W, 200); road(0, 460, W, 460); road(0, 705, 760, 705);
  road(30, 160, 30, H); road(290, 160, 290, H); road(550, 160, 550, H); road(810, 160, 810, 470);
  // ring road / curve around the pond
  g.strokeStyle = '#a7a39a'; g.lineWidth = 64; g.beginPath(); g.arc(810, 600, 140, Math.PI, Math.PI * 1.5); g.stroke();
  g.strokeStyle = '#55575a'; g.lineWidth = 52; g.beginPath(); g.arc(810, 600, 140, Math.PI, Math.PI * 1.5); g.stroke();
  g.setLineDash([22, 18]); g.strokeStyle = '#efe9d6'; g.lineWidth = 4; g.beginPath(); g.arc(810, 600, 140, Math.PI, Math.PI * 1.5); g.stroke(); g.setLineDash([]);
  // intersections: crosswalk stripes
  for (const x of [30, 290, 550, 810]) for (const y of [200, 460]) {
    g.fillStyle = '#55575a'; g.fillRect(x - 26, y - 26, 52, 52);
    g.fillStyle = '#e9e4d3';
    for (let k = -2; k <= 2; k++) { g.fillRect(x - 26 + 10 + k * 8 + 16, y - 36, 4, 10); g.fillRect(x - 40, y - 6 + k * 8, 10, 4); }
  }
  // bridge over the river
  g.fillStyle = '#8b6b4a'; g.fillRect(270, 40, 40, 120); g.fillStyle = '#6e5238'; g.fillRect(266, 40, 6, 120); g.fillRect(308, 40, 6, 120);
  g.fillStyle = '#55575a'; g.fillRect(274, 40, 32, 120);
  // houses: little top-view roofs
  const roofCols = ['#b8483a', '#3b6fa8', '#d19a2a', '#7b4a8c', '#2f8a6a', '#c46a2a'];
  for (const [x, y, w, h] of plots) {
    const n = 2 + Math.floor(R() * 3);
    for (let k = 0; k < n; k++) {
      const hw = 46 + R() * 30, hh = 40 + R() * 26;
      const hx = x + 12 + R() * (w - hw - 24), hy = y + 12 + R() * (h - hh - 24);
      g.fillStyle = 'rgba(0,0,0,0.25)'; g.fillRect(hx + 5, hy + 5, hw, hh);
      const col = roofCols[Math.floor(R() * roofCols.length)];
      g.fillStyle = col; g.fillRect(hx, hy, hw, hh);
      g.strokeStyle = 'rgba(0,0,0,0.35)'; g.lineWidth = 2;
      g.beginPath(); g.moveTo(hx, hy + hh / 2); g.lineTo(hx + hw, hy + hh / 2); g.stroke();
      g.strokeRect(hx, hy, hw, hh);
    }
    // trees
    for (let k = 0; k < 4; k++) {
      const tx = x + R() * w, ty = y + R() * h, tr = 9 + R() * 8;
      g.fillStyle = 'rgba(0,0,0,0.25)'; g.beginPath(); g.arc(tx + 3, ty + 3, tr, 0, TAU); g.fill();
      g.fillStyle = R() < 0.5 ? '#2e6b35' : '#3d7f3a'; g.beginPath(); g.arc(tx, ty, tr, 0, TAU); g.fill();
    }
  }
  // parking lot + fire station-like building + railway
  g.fillStyle = '#6b6d70'; g.fillRect(860, 230, 140, 200);
  g.strokeStyle = '#e9e4d3'; g.lineWidth = 3;
  for (let k = 0; k < 6; k++) { g.beginPath(); g.moveTo(870, 245 + k * 30); g.lineTo(920, 245 + k * 30); g.stroke(); }
  g.fillStyle = '#c23b2e'; g.fillRect(930, 250, 60, 90); g.fillStyle = '#ffffff'; g.font = 'bold 22px Arial'; g.fillText('+', 950, 302);
  g.strokeStyle = '#5a4a3a'; g.lineWidth = 14; g.beginPath(); g.moveTo(0, 30); g.lineTo(W, 30); g.stroke();
  g.strokeStyle = '#3b3b3b'; g.lineWidth = 3;
  for (let x = 0; x < W; x += 16) { g.beginPath(); g.moveTo(x, 22); g.lineTo(x, 38); g.stroke(); }
  g.strokeStyle = '#9a9a9a'; g.lineWidth = 2;
  g.beginPath(); g.moveTo(0, 26); g.lineTo(W, 26); g.moveTo(0, 34); g.lineTo(W, 34); g.stroke();
  // border band
  g.strokeStyle = '#2d4f7c'; g.lineWidth = 28; g.strokeRect(14, 14, W - 28, H - 28);
  g.strokeStyle = '#d9cfa8'; g.lineWidth = 3; g.strokeRect(30, 30, W - 60, H - 60);
  // wear: fibre noise, faded center path, dirt
  const img = g.getImageData(0, 0, W, H), d = img.data;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    const n = (R() - 0.5) * 34;
    const dx = (x - W * 0.55) / (W * 0.5), dy = (y - H * 0.5) / (H * 0.6);
    const wear = 0.18 * Math.max(0, 1 - (dx * dx + dy * dy));
    for (let ch = 0; ch < 3; ch++) d[i + ch] = clamp(d[i + ch] * 0.86 + n + wear * (205 - d[i + ch]), 0, 255);
  }
  g.putImageData(img, 0, 0);
  for (let k = 0; k < 10; k++) {
    const x = R() * W, y = R() * H, r = 20 + R() * 60;
    const sg = g.createRadialGradient(x, y, 0, x, y, r);
    sg.addColorStop(0, `rgba(60,45,30,${0.08 + R() * 0.1})`); sg.addColorStop(1, 'rgba(60,45,30,0)');
    g.fillStyle = sg; g.fillRect(x - r, y - r, r * 2, r * 2);
  }
  return canvasTexture(c);
}

// ------------------------------------------------------------------------------------------------ kids drawings

/**
 * Crayon drawings. kind: 'gardienne' | 'maison' | 'mer' | 'arcenciel' | 'chut'
 * Returns { texture, aspect } (aspect = width / height).
 */
export function kidDrawing(kind, seed = 11, res = 1) {
  const portrait = kind === 'gardienne' || kind === 'arcenciel';
  const W = Math.round((portrait ? 512 : 724) * res), H = Math.round((portrait ? 724 : 512) * res);
  const R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  paperBase(g, W, H, R, { base: [244, 241, 232], grain: 10, age: 0.16, blotches: 2, wrinkles: 1 });
  const p = new Pen(W, H, seed + 1);
  g.save();
  const s = res; // scale factor for coordinates authored at res=1
  p.g.scale(s, s);
  const C = { red: '#c8352a', blue: '#2f5fb3', sky: '#3f8fd0', green: '#3f9a3c', yellow: '#f2c624', orange: '#ec8a24', black: '#1c1a1d', brown: '#7a4a26', pink: '#e86a9a', purple: '#7d4ab0', grey: '#8a8a8f', skin: '#f0b98e' };

  if (kind === 'gardienne') {
    p.text('MA GARDIENNE', 34, 92, 46, C.red, { width: 6 });
    // night sky band + moon
    p.fill((x) => { x.rect(0, 112, 512, 70); }, C.blue, { angle: 0.15, spacing: 9, width: 10, alpha: 0.45 });
    p.oval(440, 150, 22, 22, C.yellow, 5);
    p.fill((x) => { x.arc(440, 150, 22, 0, TAU); }, C.yellow, { spacing: 6, width: 7 });
    // ground
    p.line([0, 646, 90, 638, 200, 650, 330, 640, 512, 648], C.green, 8, 3);
    p.fill((x) => { x.rect(0, 645, 512, 80); }, C.green, { angle: 1.4, spacing: 10, width: 8, alpha: 0.5 });
    // the tall woman (thin, long arms, long black hair over her face)
    const hx = 190, hy = 230;
    p.oval(hx, hy, 26, 33, C.grey, 4);
    p.line([hx - 5, hy + 33, hx - 6, hy + 52], C.grey, 4); // neck
    // gown: long narrow trapezoid
    const gown = (x) => { x.moveTo(hx - 22, hy + 52); x.lineTo(hx + 22, hy + 52); x.lineTo(hx + 44, hy + 345); x.lineTo(hx - 44, hy + 345); x.closePath(); };
    p.fill(gown, '#d9d6cf', { angle: -1.2, spacing: 8, width: 8, alpha: 0.65 });
    p.line([hx - 22, hy + 52, hx - 44, hy + 345, hx + 44, hy + 345, hx + 22, hy + 52, hx - 22, hy + 52], C.grey, 4, 2);
    // legs + bare feet
    p.line([hx - 18, hy + 345, hx - 20, hy + 412], C.grey, 4); p.line([hx + 18, hy + 345, hx + 21, hy + 412], C.grey, 4);
    p.line([hx - 20, hy + 412, hx - 36, hy + 414], C.grey, 4); p.line([hx + 21, hy + 412, hx + 38, hy + 413], C.grey, 4);
    // very long arms + long fingers
    p.line([hx - 22, hy + 60, hx - 52, hy + 170, hx - 66, hy + 300], C.grey, 4);
    for (let f = 0; f < 5; f++) p.line([hx - 66, hy + 300, hx - 74 + f * 4, hy + 330 + (f % 2) * 6], C.grey, 3, 1);
    p.line([hx + 22, hy + 60, hx + 70, hy + 160, hx + 128, hy + 268], C.grey, 4); // reaching to the child
    for (let f = 0; f < 5; f++) p.line([hx + 128, hy + 268, hx + 142 + f * 2, hy + 288 + f * 4], C.grey, 3, 1);
    // hair: long black strands covering the face, down to the waist
    for (let k = 0; k < 42; k++) {
      const sx = hx - 30 + R() * 60, sy = hy - 36 + R() * 14;
      const ex = sx + (R() - 0.5) * 30 + (sx - hx) * 0.6, ey = hy + 120 + R() * 110;
      p.line([sx, sy, (sx + ex) / 2 + (R() - 0.5) * 14, (sy + ey) / 2, ex, ey], C.black, 4 + R() * 3, 1);
    }
    // two tiny eyes through the hair
    p.line([hx - 10, hy + 2, hx - 8, hy + 3], '#f7f3e8', 4, 1); p.line([hx + 9, hy + 2, hx + 11, hy + 3], '#f7f3e8', 4, 1);
    // the child (Léa)
    const cx = 350, cy = 530;
    p.oval(cx, cy, 24, 24, C.skin, 4);
    p.fill((x) => { x.arc(cx, cy, 22, 0, TAU); }, C.skin, { spacing: 6, width: 6, alpha: 0.5 });
    for (let k = 0; k < 9; k++) p.line([cx - 24 + k * 6, cy - 22, cx - 30 + k * 7, cy - 36 - R() * 6], C.yellow, 5, 1);
    p.line([cx - 26, cy - 14, cx - 44, cy + 6], C.yellow, 6, 2); p.line([cx + 26, cy - 14, cx + 44, cy + 6], C.yellow, 6, 2);
    p.line([cx - 9, cy - 4, cx - 8, cy - 3], C.black, 5, 1); p.line([cx + 8, cy - 4, cx + 9, cy - 3], C.black, 5, 1);
    p.line([cx - 10, cy + 8, cx, cy + 14, cx + 10, cy + 8], C.red, 3, 2);
    const dress = (x) => { x.moveTo(cx, cy + 24); x.lineTo(cx + 34, cy + 90); x.lineTo(cx - 34, cy + 90); x.closePath(); };
    p.fill(dress, C.pink, { angle: 0.9, spacing: 7, width: 8 });
    p.line([cx, cy + 24, cx + 34, cy + 90, cx - 34, cy + 90, cx, cy + 24], C.pink, 4, 2);
    p.line([cx - 10, cy + 90, cx - 12, cy + 116], C.skin, 4); p.line([cx + 10, cy + 90, cx + 12, cy + 116], C.skin, 4);
    p.line([cx - 8, cy + 40, cx - 30, cy + 2], C.skin, 4); // hand up to her
    p.line([cx + 8, cy + 40, cx + 30, cy + 60], C.skin, 4);
    p.text('LÉA', cx - 34, cy + 160, 26, C.purple, { width: 4 });
    p.text('♥', 410, 470, 30, C.red, { width: 5 });
  } else if (kind === 'maison') {
    p.text('MA MAISON', 210, 70, 40, C.blue, { width: 6 });
    // sun
    p.oval(80, 80, 40, 40, C.yellow, 6);
    p.fill((x) => x.arc(80, 80, 38, 0, TAU), C.yellow, { spacing: 6, width: 8 });
    for (let k = 0; k < 10; k++) { const a = (k / 10) * TAU; p.line([80 + Math.cos(a) * 52, 80 + Math.sin(a) * 52, 80 + Math.cos(a) * 76, 80 + Math.sin(a) * 76], C.orange, 5, 2); }
    // house
    const hx = 250, hy = 200, hw = 250, hh = 200;
    p.line([hx, hy, hx + hw, hy, hx + hw, hy + hh, hx, hy + hh, hx, hy], C.brown, 6, 3);
    p.fill((x) => { x.moveTo(hx - 20, hy); x.lineTo(hx + hw / 2, hy - 110); x.lineTo(hx + hw + 20, hy); x.closePath(); }, C.red, { angle: 0.4, spacing: 7, width: 9 });
    p.line([hx - 20, hy, hx + hw / 2, hy - 110, hx + hw + 20, hy], C.red, 6, 2);
    p.line([hx + 105, hy + hh, hx + 105, hy + 110, hx + 150, hy + 110, hx + 150, hy + hh], C.brown, 5, 2);
    for (const wx of [hx + 30, hx + 180]) {
      p.fill((x) => x.rect(wx, hy + 40, 45, 45), C.yellow, { spacing: 6, width: 7 });
      p.line([wx, hy + 40, wx + 45, hy + 40, wx + 45, hy + 85, wx, hy + 85, wx, hy + 40, wx + 22, hy + 40, wx + 22, hy + 85], C.blue, 4, 2);
    }
    // ground + basement window with two eyes
    p.line([0, 420, 724, 416], C.green, 8, 3);
    p.fill((x) => x.rect(0, 418, 724, 100), C.green, { angle: 1.3, spacing: 9, width: 8, alpha: 0.5 });
    p.fill((x) => x.rect(hx + 60, hy + hh + 2, 50, 22), C.black, { spacing: 4, width: 6, alpha: 0.9 });
    p.line([hx + 76, hy + hh + 12, hx + 77, hy + hh + 13], '#f4f0e4', 4, 1); p.line([hx + 92, hy + hh + 12, hx + 93, hy + hh + 13], '#f4f0e4', 4, 1);
    // family of stick figures
    const fig = (x, y, h, col, label, hair) => {
      p.oval(x, y, h * 0.14, h * 0.14, C.skin, 4);
      p.line([x - h * 0.12, y - h * 0.1, x, y - h * 0.2, x + h * 0.12, y - h * 0.1], hair, 5, 2);
      p.line([x, y + h * 0.14, x, y + h * 0.6], col, 5); p.line([x, y + h * 0.6, x - h * 0.14, y + h], col, 5); p.line([x, y + h * 0.6, x + h * 0.14, y + h], col, 5);
      p.line([x - h * 0.25, y + h * 0.3, x + h * 0.25, y + h * 0.3], col, 5);
      p.text(label, x - strokeTextWidth(label, 16) / 2, y + h + 26, 16, col, { width: 3 });
    };
    fig(560, 300, 110, C.blue, 'PAPA', C.brown); fig(630, 300, 100, C.purple, 'MAMAN', C.orange); fig(690, 340, 60, C.pink, 'LÉA', C.yellow);
    p.text('♥', 600, 260, 22, C.red, { width: 4 });
  } else if (kind === 'mer') {
    // sunset sky, dark hills with drips, sea
    p.fill((x) => x.rect(0, 0, 724, 210), C.red, { angle: 0.1, spacing: 8, width: 10, alpha: 0.7 });
    p.fill((x) => x.rect(0, 120, 724, 110), C.orange, { angle: -0.1, spacing: 8, width: 10, alpha: 0.6 });
    p.oval(380, 215, 60, 34, C.yellow, 6);
    p.fill((x) => x.ellipse(380, 222, 60, 30, 0, Math.PI, TAU), C.yellow, { spacing: 6, width: 8 });
    const hills = (x) => { x.moveTo(0, 260); x.bezierCurveTo(120, 180, 220, 200, 330, 240); x.bezierCurveTo(450, 280, 560, 190, 724, 230); x.lineTo(724, 330); x.lineTo(0, 330); x.closePath(); };
    p.fill(hills, C.blue, { angle: 0.3, spacing: 7, width: 10, alpha: 0.85 });
    for (let k = 0; k < 26; k++) { const x = 10 + k * 28 + R() * 10; p.line([x, 320, x + (R() - 0.5) * 4, 350 + R() * 70], C.blue, 4, 1); }
    p.fill((x) => x.rect(0, 330, 724, 190), C.sky, { angle: 0.05, spacing: 9, width: 10, alpha: 0.6 });
    for (let k = 0; k < 4; k++) { const bx = 120 + k * 90 + R() * 30, by = 70 + R() * 50; p.line([bx - 16, by, bx - 6, by - 10, bx, by, bx + 6, by - 10, bx + 16, by], C.black, 4, 2); }
    p.text('LÉA 6 ANS', 500, 492, 26, C.black, { width: 4 });
  } else if (kind === 'arcenciel') {
    const cols = [C.red, C.orange, C.yellow, C.green, C.blue, C.purple];
    for (let k = 0; k < cols.length; k++) p.line(ellipsePts(256, 360, 210 - k * 22, 200 - k * 22, 30, Math.PI, Math.PI), cols[k], 18, 3);
    p.oval(70, 380, 50, 26, C.grey, 4); p.oval(440, 380, 56, 28, C.grey, 4);
    p.text("JE T'AIME", 90, 520, 52, C.red, { width: 7 });
    p.text('MAMAN', 120, 600, 56, C.pink, { width: 7 });
    p.text('♥', 400, 600, 50, C.red, { width: 7 });
    for (let k = 0; k < 4; k++) {
      const fx = 70 + k * 120, fy = 680;
      p.line([fx, fy, fx, fy - 40], C.green, 4);
      for (let q = 0; q < 5; q++) { const a = (q / 5) * TAU; p.oval(fx + Math.cos(a) * 10, fy - 50 + Math.sin(a) * 10, 7, 7, [C.red, C.yellow, C.pink, C.purple][k], 4, 1); }
    }
  } else if (kind === 'chut') {
    // cross-section of the house: a tall dark woman upstairs in bed, a child in the basement, the stairs between.
    p.text('ELLE DORT EN HAUT', 40, 64, 34, C.black, { width: 5 });
    p.line([60, 110, 664, 110, 664, 470, 60, 470, 60, 110], C.brown, 6, 3);
    p.line([60, 290, 664, 290], C.brown, 6, 3); // floor between
    p.line([360, 470, 360, 450, 390, 450, 390, 430, 420, 430, 420, 410, 450, 410, 450, 390, 480, 390, 480, 370, 510, 370, 510, 350, 540, 350, 540, 330, 570, 330, 570, 310, 600, 310, 600, 290], C.brown, 5, 2);
    // bed upstairs + the woman lying, black hair spread on the pillow
    p.line([110, 250, 330, 250, 330, 280], C.brown, 6, 2); p.line([110, 230, 110, 280], C.brown, 6, 2);
    p.fill((x) => x.rect(140, 228, 180, 22), '#c9c6c0', { spacing: 6, width: 7 });
    p.oval(135, 222, 16, 14, C.grey, 4);
    for (let k = 0; k < 18; k++) p.line([126 + R() * 18, 210 + R() * 10, 100 + R() * 40, 238 + R() * 18], C.black, 4, 1);
    p.line([120, 196, 128, 188, 136, 196], C.black, 3, 1); // z z z
    p.text('Z Z Z', 160, 190, 22, C.blue, { width: 3 });
    // door upstairs, light under it
    p.line([600, 290, 600, 170, 650, 170, 650, 290], C.brown, 5, 2);
    // the child in the basement with a speech bubble
    const cx = 180, cy = 380;
    p.oval(cx, cy, 20, 20, C.skin, 4);
    for (let k = 0; k < 7; k++) p.line([cx - 18 + k * 6, cy - 18, cx - 22 + k * 7, cy - 30], C.yellow, 5, 1);
    p.line([cx - 8, cy, cx - 7, cy + 1], C.black, 4, 1); p.line([cx + 7, cy, cx + 8, cy + 1], C.black, 4, 1);
    p.line([cx - 6, cy + 10, cx + 6, cy + 10], C.red, 3, 1);
    p.fill((x) => { x.moveTo(cx, cy + 20); x.lineTo(cx + 28, cy + 74); x.lineTo(cx - 28, cy + 74); x.closePath(); }, C.pink, { spacing: 6, width: 7 });
    p.line([cx - 12, cy + 74, cx - 12, cy + 88], C.skin, 4); p.line([cx + 12, cy + 74, cx + 12, cy + 88], C.skin, 4);
    p.oval(290, 345, 62, 32, C.black, 4);
    p.line([250, 370, 228, 392], C.black, 4, 2);
    p.text('CHUT !', 248, 358, 26, C.red, { width: 5 });
    p.text('PAS DE BRUIT', 90, 506, 30, C.purple, { width: 5 });
  }
  p.g.setTransform(1, 0, 0, 1, 0, 0);
  p.finish(g, { tooth: 0.5 });
  // tape at the top corners (wall drawings) — also fine for loose sheets (old tape)
  if (kind !== 'chut') {
    tape(g, W * 0.12, H * 0.025, W * 0.18, H * 0.045, -0.5, R);
    tape(g, W * 0.88, H * 0.025, W * 0.18, H * 0.045, 0.45, R);
  }
  g.restore();
  return { texture: canvasTexture(c), aspect: W / H };
}

// ------------------------------------------------------------------------------------------------ family photos

/**
 * Faded family photos packed into one atlas. Returns { texture, cells: [{u0,v0,u1,v1,aspect}] }.
 * Photo 3 shows a young woman with long dark hair holding the child — her face is scratched out.
 */
export function photoAtlas(seed = 23) {
  const W = 1024, H = 512, R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  g.fillStyle = '#1a1612'; g.fillRect(0, 0, W, H);
  const cells = [
    { x: 0, y: 0, w: 200, h: 250, scene: 'studio' },
    { x: 205, y: 0, w: 250, h: 190, scene: 'lake' },
    { x: 460, y: 0, w: 190, h: 230, scene: 'baby' },
    { x: 655, y: 0, w: 200, h: 255, scene: 'sitter' },
    { x: 0, y: 260, w: 260, h: 195, scene: 'xmas' },
  ];
  for (const cell of cells) drawPhoto(g, cell, R);
  return {
    texture: canvasTexture(c),
    cells: cells.map((k) => ({ u0: k.x / W, u1: (k.x + k.w) / W, v0: 1 - (k.y + k.h) / H, v1: 1 - k.y / H, aspect: k.w / k.h })),
  };
}

function drawPhoto(g, { x, y, w, h, scene }, R) {
  // draw the scene small, upscale with smoothing (soft 90s focus), then grade + grain
  const sw = Math.round(w / 4.2), sh = Math.round(h / 4.2);
  const s = makeCanvas(sw, sh), q = s.getContext('2d');
  const person = (px, py, sc, shirt, hair, longHair = false, faceTone = '#e7b48f') => {
    q.fillStyle = shirt; q.beginPath(); q.ellipse(px, py + sc * 1.6, sc * 1.25, sc * 1.1, 0, Math.PI, TAU); q.fill();
    q.fillRect(px - sc * 1.25, py + sc * 1.6, sc * 2.5, sc * 2);
    if (longHair) { q.fillStyle = hair; q.fillRect(px - sc * 0.85, py - sc * 0.3, sc * 1.7, sc * 2.1); }
    q.fillStyle = faceTone; q.beginPath(); q.ellipse(px, py, sc * 0.62, sc * 0.78, 0, 0, TAU); q.fill();
    q.fillStyle = hair; q.beginPath(); q.ellipse(px, py - sc * 0.45, sc * 0.72, sc * 0.48, 0, Math.PI * 0.95, Math.PI * 2.05); q.fill();
    q.fillStyle = 'rgba(40,25,20,0.7)'; q.fillRect(px - sc * 0.3, py - sc * 0.05, sc * 0.14, sc * 0.1); q.fillRect(px + sc * 0.16, py - sc * 0.05, sc * 0.14, sc * 0.1);
    q.fillStyle = 'rgba(150,60,60,0.6)'; q.fillRect(px - sc * 0.2, py + sc * 0.38, sc * 0.4, sc * 0.08);
  };
  let face = null;
  if (scene === 'studio') {
    const bg = q.createRadialGradient(sw / 2, sh * 0.4, 2, sw / 2, sh / 2, sw);
    bg.addColorStop(0, '#7f96b6'); bg.addColorStop(1, '#2c3a55'); q.fillStyle = bg; q.fillRect(0, 0, sw, sh);
    person(sw * 0.3, sh * 0.36, sw * 0.12, '#7a2f3a', '#3a2418');
    person(sw * 0.7, sh * 0.34, sw * 0.13, '#2d3f6a', '#5a3a22');
    person(sw * 0.5, sh * 0.62, sw * 0.09, '#d9a3b8', '#e1c06a');
  } else if (scene === 'lake') {
    const bg = q.createLinearGradient(0, 0, 0, sh); bg.addColorStop(0, '#9fc3dd'); bg.addColorStop(0.45, '#cfe0e6'); bg.addColorStop(0.5, '#3f6b4a'); bg.addColorStop(0.62, '#2f5b7a'); bg.addColorStop(1, '#6f8f4a');
    q.fillStyle = bg; q.fillRect(0, 0, sw, sh);
    for (let k = 0; k < 9; k++) { q.fillStyle = `rgba(40,${70 + R() * 30},40,0.9)`; q.beginPath(); q.arc(R() * sw, sh * 0.47, 3 + R() * 5, 0, TAU); q.fill(); }
    person(sw * 0.45, sh * 0.45, sw * 0.08, '#e6e0d0', '#4a3020');
    person(sw * 0.45, sh * 0.25, sw * 0.055, '#e05a5a', '#e1c06a');
    person(sw * 0.72, sh * 0.5, sw * 0.075, '#3a6aa8', '#2a1a10', true);
  } else if (scene === 'baby') {
    q.fillStyle = '#e8dccb'; q.fillRect(0, 0, sw, sh);
    q.fillStyle = '#bcd2e8'; q.beginPath(); q.ellipse(sw * 0.5, sh * 0.62, sw * 0.38, sh * 0.3, 0.2, 0, TAU); q.fill();
    q.fillStyle = '#f0c3a0'; q.beginPath(); q.ellipse(sw * 0.5, sh * 0.42, sw * 0.17, sh * 0.15, 0, 0, TAU); q.fill();
    q.fillStyle = 'rgba(60,40,30,0.6)'; q.fillRect(sw * 0.43, sh * 0.41, 2, 1); q.fillRect(sw * 0.55, sh * 0.41, 2, 1);
  } else if (scene === 'sitter') {
    q.fillStyle = '#c9b48f'; q.fillRect(0, 0, sw, sh); // beige basement wall
    q.fillStyle = '#6a4a35'; q.fillRect(0, sh * 0.62, sw, sh * 0.38); // sofa
    q.fillStyle = '#7d5a42'; q.fillRect(0, sh * 0.55, sw, sh * 0.1);
    person(sw * 0.45, sh * 0.3, sw * 0.13, '#d8d4c8', '#121010', true, '#e2c0a8');
    person(sw * 0.62, sh * 0.62, sw * 0.085, '#e48aa8', '#e1c06a');
    face = { x: x + (sw * 0.45 / sw) * w, y: y + (sh * 0.3 / sh) * h, r: (sw * 0.13 / sw) * w * 1.15 };
  } else if (scene === 'xmas') {
    q.fillStyle = '#5a3e2c'; q.fillRect(0, 0, sw, sh);
    q.fillStyle = '#1f4a2a'; q.beginPath(); q.moveTo(sw * 0.75, sh * 0.05); q.lineTo(sw * 0.95, sh * 0.8); q.lineTo(sw * 0.55, sh * 0.8); q.closePath(); q.fill();
    for (let k = 0; k < 12; k++) { q.fillStyle = ['#ff5a4a', '#ffd34a', '#7ac0ff'][k % 3]; q.fillRect(sw * (0.6 + R() * 0.3), sh * (0.2 + R() * 0.55), 1.5, 1.5); }
    q.fillStyle = '#b8352a'; q.fillRect(sw * 0.2, sh * 0.62, sw * 0.22, sh * 0.2);
    q.fillStyle = '#e8d06a'; q.fillRect(sw * 0.3, sh * 0.62, sw * 0.03, sh * 0.2);
    person(sw * 0.35, sh * 0.4, sw * 0.08, '#e6e6f0', '#e1c06a');
  }
  g.save();
  g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
  g.drawImage(s, x + 8, y + 8, w - 16, h - 16);
  // grade: faded, warm/magenta cast, lifted blacks
  g.globalCompositeOperation = 'screen'; g.fillStyle = 'rgba(70,45,40,0.35)'; g.fillRect(x, y, w, h);
  g.globalCompositeOperation = 'multiply'; g.fillStyle = 'rgba(255,226,190,0.9)'; g.fillRect(x, y, w, h);
  g.globalCompositeOperation = 'source-over';
  // flash hot spot / vignette
  const vg = g.createRadialGradient(x + w / 2, y + h * 0.45, Math.min(w, h) * 0.2, x + w / 2, y + h / 2, Math.max(w, h) * 0.7);
  vg.addColorStop(0, 'rgba(255,240,220,0.08)'); vg.addColorStop(1, 'rgba(30,15,10,0.45)');
  g.fillStyle = vg; g.fillRect(x + 8, y + 8, w - 16, h - 16);
  if (face) {
    // scratched-out face: violent pen/key scratches through the emulsion (white) + ink
    g.lineCap = 'round';
    const Rr = makeRng(91);
    for (let k = 0; k < 70; k++) {
      const a = Rr() * TAU, r0 = Rr() * face.r * 0.5;
      const x0 = face.x + Math.cos(a) * r0, y0 = face.y + Math.sin(a) * r0 * 1.2;
      const ang = -0.9 + (Rr() - 0.5) * 0.9 + (k % 3 === 0 ? 1.6 : 0), len = face.r * (0.6 + Rr() * 0.9);
      g.strokeStyle = k % 4 === 0 ? 'rgba(20,18,30,0.75)' : `rgba(${235 + Rr() * 20},${232 + Rr() * 20},${225},${0.6 + Rr() * 0.4})`;
      g.lineWidth = 0.8 + Rr() * 2.2;
      g.beginPath(); g.moveTo(x0 - Math.cos(ang) * len / 2, y0 - Math.sin(ang) * len / 2);
      g.lineTo(x0 + Math.cos(ang) * len / 2 + (Rr() - 0.5) * 3, y0 + Math.sin(ang) * len / 2 + (Rr() - 0.5) * 3); g.stroke();
    }
  }
  // grain
  const img = g.getImageData(x, y, w, h), d = img.data;
  for (let i = 0; i < d.length; i += 4) { const n = (R() - 0.5) * 26; d[i] = clamp(d[i] + n, 0, 255); d[i + 1] = clamp(d[i + 1] + n, 0, 255); d[i + 2] = clamp(d[i + 2] + n, 0, 255); }
  g.putImageData(img, x, y);
  // white print border, slightly yellowed
  g.strokeStyle = '#e9e1cf'; g.lineWidth = 16; g.strokeRect(x + 4, y + 4, w - 8, h - 8);
  // dust specks and a crease
  for (let k = 0; k < 14; k++) { g.fillStyle = `rgba(255,255,245,${0.3 + R() * 0.4})`; g.fillRect(x + 8 + R() * (w - 16), y + 8 + R() * (h - 16), 1 + R() * 1.5, 1 + R() * 1.5); }
  g.strokeStyle = 'rgba(255,250,235,0.18)'; g.lineWidth = 1.2; g.beginPath(); g.moveTo(x + 8, y + h * (0.3 + R() * 0.4)); g.lineTo(x + w - 8, y + h * (0.3 + R() * 0.4)); g.stroke();
  g.restore();
}

// ------------------------------------------------------------------------------------------------ notes

/** Note 1 (from "M."): torn notebook page, blue ballpoint. */
export function note1Texture(seed = 31) {
  const W = 512, H = 700, R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  paperBase(g, W, H, R, { base: [246, 243, 233], grain: 9, age: 0.14, blotches: 2, wrinkles: 2 });
  // ruled lines + margin
  g.strokeStyle = 'rgba(90,140,200,0.45)'; g.lineWidth = 1.5;
  for (let y = 101; y < H - 20; y += 57) { g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke(); }
  g.strokeStyle = 'rgba(210,80,90,0.5)'; g.beginPath(); g.moveTo(62, 0); g.lineTo(62, H); g.stroke();
  // torn perforated top edge (spiral notebook)
  g.globalCompositeOperation = 'destination-out';
  g.beginPath(); g.moveTo(0, 0); g.lineTo(W, 0);
  for (let x = W; x >= 0; x -= 6) g.lineTo(x, 12 + R() * 9);
  g.closePath(); g.fill();
  for (let x = 24; x < W; x += 28) { g.beginPath(); g.arc(x, 24, 5, 0, TAU); g.fill(); }
  g.globalCompositeOperation = 'source-over';
  const ink = '#1f2b63';
  const lines = ['Reste en bas.', 'Pas un bruit.', 'Elle a le sommeil léger…', '', 'La clé de la porte', "d'en haut est dans le", 'coffret de Léa.', '', '              — M.'];
  let y = 154;
  const lh = 57;
  for (const l of lines) {
    if (l) {
      g.font = `600 54px ${FONT.hand}`;
      const size = Math.min(54, 54 * (420 / Math.max(1, g.measureText(l).width)));
      handLine(g, l, 74 + (R() - 0.5) * 6, y, size, ink, R, { slant: -0.03 });
    }
    y += lh;
  }
  // underline "Pas un bruit."
  g.strokeStyle = ink; g.globalAlpha = 0.8; g.lineWidth = 2.4;
  g.beginPath(); g.moveTo(76, 154 + lh + 10); g.bezierCurveTo(160, 154 + lh + 15, 240, 154 + lh + 6, 320, 154 + lh + 12); g.stroke();
  g.globalAlpha = 1;
  return canvasTexture(c);
}

/** Child's code note for the box lid: "LE CODE" + duck · horse · clock · TV doodles (Seyès school paper). */
export function codeNoteTexture(seed = 41) {
  const W = 512, H = 340, R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  paperBase(g, W, H, R, { base: [247, 245, 238], grain: 8, age: 0.12, blotches: 1, wrinkles: 1 });
  // Seyès ruling
  for (let y = 10; y < H; y += 8) { g.strokeStyle = (Math.round((y - 10) / 8) % 4 === 0) ? 'rgba(80,110,190,0.42)' : 'rgba(150,160,220,0.25)'; g.lineWidth = 1; g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke(); }
  for (let x = 40; x < W; x += 32) { g.strokeStyle = 'rgba(150,160,220,0.22)'; g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke(); }
  g.strokeStyle = 'rgba(220,70,80,0.55)'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(30, 0); g.lineTo(30, H); g.stroke();
  const p = new Pen(W, H, seed + 3);
  const C = { red: '#c8352a', blue: '#2f5fb3', yellow: '#f0c020', brown: '#7a4a26', black: '#1c1a1d', grey: '#77777c', green: '#3f9a3c', orange: '#ec8a24' };
  p.text('LE CODE :', 46, 62, 34, C.red, { width: 5 });
  // lay the four words out left to right, doodles centred above each word
  const words = ['CANARD', 'CHEVAL', 'HORLOGE', 'TÉLÉ'];
  const wh = 19, gap = 26;
  const widths = words.map((w) => strokeTextWidth(w, wh) * 1.02);
  const total = widths.reduce((a, b) => a + b, 0) + gap * 3;
  let wx = 40 + Math.max(0, (W - 52 - total) / 2);
  const wordX = [], cx = [];
  for (let k = 0; k < 4; k++) { wordX.push(wx); cx.push(wx + widths[k] / 2); wx += widths[k] + gap; }
  const cy = 150;
  // duck
  p.oval(cx[0], cy + 6, 30, 20, C.yellow, 4); p.oval(cx[0] + 18, cy - 20, 14, 14, C.yellow, 4);
  p.fill((x) => { x.ellipse(cx[0], cy + 6, 28, 18, 0, 0, TAU); x.moveTo(cx[0] + 32, cy - 20); x.arc(cx[0] + 18, cy - 20, 13, 0, TAU); }, C.yellow, { spacing: 5, width: 6 });
  p.line([cx[0] + 30, cy - 22, cx[0] + 42, cy - 18, cx[0] + 30, cy - 14], C.orange, 4, 2);
  p.line([cx[0] + 21, cy - 24, cx[0] + 22, cy - 23], C.black, 4, 1);
  // horse
  p.line([cx[1] - 30, cy, cx[1] + 18, cy, cx[1] + 30, cy - 30, cx[1] + 40, cy - 22], C.brown, 4, 2);
  p.oval(cx[1] - 6, cy + 4, 26, 14, C.brown, 4);
  for (const lx of [-24, -12, 8, 18]) p.line([cx[1] + lx, cy + 14, cx[1] + lx, cy + 38], C.brown, 4, 1);
  p.line([cx[1] - 32, cy, cx[1] - 42, cy + 22], C.brown, 4, 1);
  p.line([cx[1] + 24, cy - 26, cx[1] + 18, cy - 40], C.black, 4, 1);
  // clock (grandfather clock-ish face)
  p.oval(cx[2], cy, 30, 30, C.black, 4);
  p.line([cx[2], cy, cx[2], cy - 22], C.red, 4, 2); p.line([cx[2], cy, cx[2] + 14, cy + 8], C.blue, 4, 2);
  for (let k = 0; k < 12; k++) { const a = (k / 12) * TAU; p.line([cx[2] + Math.cos(a) * 24, cy + Math.sin(a) * 24, cx[2] + Math.cos(a) * 27, cy + Math.sin(a) * 27], C.black, 3, 1); }
  // TV with antenna
  p.line([cx[3] - 32, cy - 22, cx[3] + 32, cy - 22, cx[3] + 32, cy + 26, cx[3] - 32, cy + 26, cx[3] - 32, cy - 22], C.grey, 4, 2);
  p.fill((x) => x.rect(cx[3] - 24, cy - 15, 40, 34), C.blue, { spacing: 5, width: 6, alpha: 0.6 });
  p.line([cx[3] - 10, cy - 22, cx[3] - 24, cy - 48], C.black, 3, 1); p.line([cx[3] + 6, cy - 22, cx[3] + 20, cy - 50], C.black, 3, 1);
  p.oval(cx[3] + 25, cy - 4, 3, 3, C.red, 3, 1);
  // words + separators
  for (let k = 0; k < 4; k++) {
    p.text(words[k], wordX[k], 236, wh, k % 2 ? C.blue : C.black, { width: 3.2, wobble: 0.7 });
    p.text(String(k + 1), cx[k] - 6, 286, 26, C.red, { width: 4 });
    if (k < 3) p.text('→', (cx[k] + cx[k + 1]) / 2 - 12, 160, 22, C.grey, { width: 3 });
  }
  p.finish(g, { tooth: 0.45 });
  tape(g, 30, 18, 90, 26, -0.4, R); tape(g, W - 30, H - 20, 90, 26, -0.35, R);
  return canvasTexture(c);
}

/** The child drawing left on the kid table (note 2). */
export function note2Texture(seed = 53) { return kidDrawing('chut', seed, 1); }

/**
 * Newspaper clipping (fictional 1996 local paper): a babysitter is missing. Irregular scissor-cut edges (alpha).
 */
export function newspaperTexture(seed = 61) {
  const W = 512, H = 700, R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  paperBase(g, W, H, R, { base: [226, 214, 182], grain: 16, age: 0.4, blotches: 5, wrinkles: 2 });
  const ink = 'rgba(28,24,20,0.92)';
  g.fillStyle = ink; g.textBaseline = 'alphabetic';
  g.font = `bold 15px ${FONT.serif}`; g.fillText("L'ÉCHO DU VALLON", 28, 38);
  g.font = `12px ${FONT.serif}`; g.fillText('Saint-Aubin — jeudi 14 novembre 1996', 260, 38);
  g.fillRect(24, 46, W - 48, 2); g.fillRect(24, 50, W - 48, 1);
  g.font = `bold 40px ${FONT.serif}`;
  g.fillText('Une gardienne', 28, 98); g.fillText("d'enfants disparue", 28, 140);
  g.font = `italic 17px ${FONT.serif}`;
  g.fillText("Odile Ferron, 23 ans, n'a pas été revue depuis samedi", 28, 170);
  // halftone portrait
  const px = 28, py = 186, pw = 180, ph = 220;
  const s = makeCanvas(45, 55), q = s.getContext('2d');
  q.fillStyle = '#b8b8b8'; q.fillRect(0, 0, 45, 55);
  q.fillStyle = '#151515'; q.fillRect(9, 9, 27, 46); // long hair
  q.beginPath(); q.ellipse(22.5, 15, 12, 10, 0, Math.PI, TAU); q.fill();
  q.fillStyle = '#d0d0d0'; q.beginPath(); q.ellipse(22.5, 20, 8, 10.5, 0, 0, TAU); q.fill();
  q.fillStyle = '#3a3a3a'; q.fillRect(18, 18, 3, 1.5); q.fillRect(24.5, 18, 3, 1.5); q.fillRect(20, 26, 5, 1);
  q.fillStyle = '#6a6a6a'; q.beginPath(); q.ellipse(22.5, 52, 20, 14, 0, Math.PI, TAU); q.fill();
  const sd = q.getImageData(0, 0, 45, 55).data;
  g.fillStyle = '#d9cdae'; g.fillRect(px, py, pw, ph);
  g.fillStyle = 'rgba(20,18,16,0.9)';
  const cell = 4;
  for (let yy = 0; yy < ph; yy += cell) for (let xx = 0; xx < pw; xx += cell) {
    const sx = Math.floor((xx / pw) * 45), sy = Math.floor((yy / ph) * 55);
    const lum = sd[(sy * 45 + sx) * 4] / 255;
    const r = (1 - lum) * cell * 0.62 + (R() - 0.5) * 0.4;
    if (r > 0.2) { g.beginPath(); g.arc(px + xx + cell / 2, py + yy + cell / 2, r, 0, TAU); g.fill(); }
  }
  g.strokeStyle = ink; g.lineWidth = 1; g.strokeRect(px, py, pw, ph);
  g.font = `italic 12px ${FONT.serif}`; g.fillStyle = ink; g.fillText('Odile Ferron, photographiée en 1995.', px, py + ph + 16);
  // body text columns
  const body = [
    "La police de Saint-Aubin demande l'aide",
    'du public pour retrouver Odile Ferron,',
    "23 ans, gardienne d'enfants bien connue",
    'dans le quartier des Érables.',
    "Samedi soir, la jeune femme gardait une",
    "fillette de six ans dans une maison de",
    "la rue des Érables. Les parents, rentrés",
    "vers minuit, ont trouvé l'enfant endormie",
    "au sous-sol, seule. La porte d'entrée",
    "était verrouillée de l'intérieur.",
    "« Elle adorait les enfants. Elle leur",
    "chantait des berceuses pendant des",
    "heures », confie sa mère, très inquiète.",
    "Selon un voisin, une femme très grande",
    "aux longs cheveux noirs aurait été vue",
    "à la fenêtre du sous-sol vers 23 h.",
    "Les recherches se poursuivent dans le",
    "secteur du ruisseau. Toute personne qui",
    "aurait des informations est priée de",
    "communiquer avec la Sûreté au 555-0142.",
  ];
  g.font = `13px ${FONT.serif}`; g.fillStyle = ink;
  let yy = 202;
  for (let i = 0; i < 11; i++) { g.fillText(body[i] || '', 222, yy); yy += 17.5; }
  yy = py + ph + 34;
  for (let i = 11; i < body.length; i++) { g.fillText(body[i], 28, yy); yy += 17.5; }
  // neighbouring article (cut off)
  g.fillRect(24, H - 100, W - 48, 1);
  g.font = `bold 18px ${FONT.serif}`; g.fillText('Bingo paroissial : record de', 28, H - 76);
  g.font = `13px ${FONT.serif}`; g.fillText('participation au sous-sol de l\'église, où plus de deux cents', 28, H - 56);
  g.fillText('joueurs se sont réunis vendredi pour la soirée annuelle…', 28, H - 39);
  // foxing spots + ink offset
  for (let k = 0; k < 40; k++) { g.fillStyle = `rgba(150,100,40,${0.05 + R() * 0.12})`; g.beginPath(); g.arc(R() * W, R() * H, 1 + R() * 5, 0, TAU); g.fill(); }
  // scissor-cut irregular border (transparent outside)
  g.globalCompositeOperation = 'destination-in';
  g.beginPath();
  const m = 6;
  g.moveTo(m + R() * 4, m + R() * 4);
  for (let x = 40; x < W; x += 40) g.lineTo(x, m + (R() - 0.5) * 6 + x * 0.004);
  for (let y = 40; y < H; y += 40) g.lineTo(W - m + (R() - 0.5) * 5, y);
  for (let x = W - 40; x > 0; x -= 40) g.lineTo(x, H - m + (R() - 0.5) * 6);
  for (let y = H - 40; y > 0; y -= 40) g.lineTo(m + (R() - 0.5) * 5, y);
  g.closePath(); g.fillStyle = '#000'; g.fill();
  g.globalCompositeOperation = 'source-over';
  return canvasTexture(c);
}

// ------------------------------------------------------------------------------------------------ decals

/** Felt-pen digit on transparent background (or on a scrap of masking tape). */
export function digitDecal(digit, { seed = 71, onTape = false, color = '#14131a' } = {}) {
  const S = 128, R = makeRng(seed + Number(digit) * 7);
  const c = makeCanvas(S, S), g = c.getContext('2d');
  if (onTape) {
    g.fillStyle = 'rgba(226,210,165,0.95)';
    g.beginPath(); g.moveTo(10, 22); g.lineTo(118, 18); g.lineTo(120, 108); g.lineTo(8, 112); g.closePath(); g.fill();
  }
  const p = new Pen(S, S, seed);
  const h = 84;
  const str = String(digit);
  const w = strokeTextWidth(str, h, 0);
  p.text(str, S / 2 - w / 2 + 4, S / 2 + h / 2 - 6, h, color, { width: 8, marker: true, wobble: 0.4 });
  // underline so 6 / 9 can't be confused
  p.marker([S / 2 - 26, S / 2 + h / 2 + 4, S / 2 + 28, S / 2 + h / 2 + 2], color, 6);
  p.finish(g, { tooth: 0, mode: 'source-over' });
  return canvasTexture(c);
}

/** Crayon scribbles on the wall near the kids corner (transparent). Returns { texture, aspect }. */
export function wallScribbles(seed = 81) {
  const W = 768, H = 384, R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  const p = new Pen(W, H, seed);
  const cols = ['#2f5fb3', '#c8352a', '#3f9a3c', '#7d4ab0', '#ec8a24', '#1c1a1d'];
  // zigzags
  for (let k = 0; k < 5; k++) {
    const x0 = R() * W * 0.8, y0 = H * 0.3 + R() * H * 0.6, col = cols[Math.floor(R() * cols.length)];
    const pts = [];
    for (let i = 0; i < 9 + R() * 8; i++) pts.push(x0 + i * (10 + R() * 8), y0 + (i % 2 ? -1 : 1) * (14 + R() * 26));
    p.line(pts, col, 5, 2, 0.8);
  }
  // spirals
  for (let k = 0; k < 3; k++) {
    const cx = 80 + R() * (W - 160), cy = 90 + R() * (H - 180), col = cols[Math.floor(R() * cols.length)];
    const pts = [];
    for (let a = 0; a < TAU * 3.2; a += 0.3) pts.push(cx + Math.cos(a) * a * 5, cy + Math.sin(a) * a * 4.2);
    p.line(pts, col, 4, 2, 0.75);
  }
  // a stick figure with long hair and a sun
  p.oval(560, 120, 22, 22, '#1c1a1d', 5);
  for (let i = 0; i < 9; i++) p.line([546 + i * 3.5, 104, 540 + i * 4, 170 + R() * 30], '#1c1a1d', 3, 1, 0.9);
  p.line([560, 142, 560, 250], '#1c1a1d', 5); p.line([560, 250, 535, 320], '#1c1a1d', 5); p.line([560, 250, 585, 320], '#1c1a1d', 5);
  p.line([560, 170, 500, 245], '#1c1a1d', 5); p.line([560, 170, 622, 245], '#1c1a1d', 5);
  p.text('LÉA', 120, 340, 40, '#c8352a', { width: 6 });
  // hard scribble clouds
  for (let k = 0; k < 3; k++) {
    const cx = 120 + R() * (W - 240), cy = 80 + R() * (H - 160), col = cols[Math.floor(R() * cols.length)];
    const pts = [];
    for (let i = 0; i < 26; i++) pts.push(cx + (R() - 0.5) * 90, cy + (R() - 0.5) * 50);
    p.line(pts, col, 3, 1, 0.7);
  }
  p.finish(g, { tooth: 0.6, mode: 'source-over' });
  return { texture: canvasTexture(c), aspect: W / H };
}

/** Wall/ceiling stain atlas (transparent): [water ring, grime smudge, scuffs, finger marks] in 4 cells. */
export function stainAtlas(seed = 91) {
  const S = 256, W = S * 4, H = S, R = makeRng(seed);
  const c = makeCanvas(W, H), g = c.getContext('2d');
  // 0: water stain with tide rings
  for (let k = 0; k < 4; k++) {
    const r = S * (0.42 - k * 0.08);
    const rg = g.createRadialGradient(S / 2 + (R() - 0.5) * 20, S / 2 + (R() - 0.5) * 20, r * 0.5, S / 2, S / 2, r);
    rg.addColorStop(0, 'rgba(120,85,40,0.0)'); rg.addColorStop(0.86, `rgba(120,85,40,${0.12 + k * 0.03})`); rg.addColorStop(0.93, `rgba(95,62,25,${0.28 + k * 0.04})`); rg.addColorStop(1, 'rgba(95,62,25,0)');
    g.fillStyle = rg; g.beginPath(); g.ellipse(S / 2, S / 2, r, r * (0.8 + R() * 0.2), R(), 0, TAU); g.fill();
  }
  // 1: grime smudge (soft dark)
  for (let k = 0; k < 18; k++) {
    const x = S + S * 0.2 + R() * S * 0.6, y = S * 0.2 + R() * S * 0.6, r = 20 + R() * 50;
    const rg = g.createRadialGradient(x, y, 0, x, y, r);
    rg.addColorStop(0, `rgba(55,45,35,${0.05 + R() * 0.07})`); rg.addColorStop(1, 'rgba(55,45,35,0)');
    g.fillStyle = rg; g.fillRect(x - r, y - r, 2 * r, 2 * r);
  }
  // 2: scuffs (shoe / chair marks)
  g.lineCap = 'round';
  for (let k = 0; k < 26; k++) {
    const x = S * 2 + 20 + R() * (S - 40), y = 30 + R() * (S - 60), l = 10 + R() * 50, a = (R() - 0.5) * 0.6;
    g.strokeStyle = `rgba(${40 + R() * 30},${35 + R() * 25},${30},${0.12 + R() * 0.3})`; g.lineWidth = 1 + R() * 3;
    g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke();
  }
  // 3: finger marks around a switch
  for (let k = 0; k < 14; k++) {
    const x = S * 3 + S * 0.5 + (R() - 0.5) * S * 0.5, y = S * 0.5 + (R() - 0.5) * S * 0.6, r = 8 + R() * 12;
    const rg = g.createRadialGradient(x, y, 0, x, y, r);
    rg.addColorStop(0, `rgba(70,55,40,${0.12 + R() * 0.1})`); rg.addColorStop(1, 'rgba(70,55,40,0)');
    g.fillStyle = rg; g.beginPath(); g.ellipse(x, y, r * 0.7, r, R(), 0, TAU); g.fill();
  }
  return canvasTexture(c);
}

// ------------------------------------------------------------------------------------------------ small labels / faces

/** Generic small canvas painter: returns a texture of w x h drawn by fn(ctx, w, h, R). */
export function painted(w, h, fn, seed = 5, opts = {}) {
  const c = makeCanvas(w, h), g = c.getContext('2d'), R = makeRng(seed);
  fn(g, w, h, R);
  return canvasTexture(c, opts);
}

/** Digit strip for a combination-lock wheel (u wraps around the cylinder, 10 digits). */
export function lockWheelTexture() {
  return painted(320, 48, (g, w, h) => {
    const grad = g.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, '#5a4518'); grad.addColorStop(0.5, '#b8963e'); grad.addColorStop(1, '#5a4518');
    g.fillStyle = grad; g.fillRect(0, 0, w, h);
    g.fillStyle = '#1a140a'; g.font = `bold 30px ${FONT.sans}`; g.textAlign = 'center'; g.textBaseline = 'middle';
    for (let d = 0; d < 10; d++) {
      g.save(); g.translate((d + 0.5) * (w / 10), h / 2); g.rotate(Math.PI / 2); g.fillText(String(d), 0, 1); g.restore();
      g.fillStyle = 'rgba(0,0,0,0.35)'; g.fillRect(d * (w / 10), 0, 1.5, h); g.fillStyle = '#1a140a';
    }
  }, 3, { srgb: true });
}

/** Labels for D-cell batteries (u around, v along). */
export function batteryLabelTexture() {
  return painted(256, 128, (g, w, h) => {
    g.fillStyle = '#121212'; g.fillRect(0, 0, w, h);
    const cu = g.createLinearGradient(0, 0, 0, h * 0.34);
    cu.addColorStop(0, '#6e4214'); cu.addColorStop(0.5, '#d29a48'); cu.addColorStop(1, '#8a561c');
    g.fillStyle = cu; g.fillRect(0, 0, w, h * 0.34);
    g.fillStyle = '#e8e2d2'; g.font = `bold 26px ${FONT.sans}`; g.fillText('VOLTEX', 14, h * 0.62);
    g.font = '14px Arial'; g.fillText('ALCALINE  LR20  1,5 V', 14, h * 0.84);
    g.fillStyle = '#d29a48'; g.font = 'bold 30px Arial'; g.fillText('+', w - 40, h * 0.7);
  }, 4);
}

/** Thermostat face (90s beige, small LCD). */
export function thermostatTexture() {
  return painted(256, 160, (g, w, h) => {
    g.fillStyle = '#d8d0bc'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#c9c0aa'; g.fillRect(8, 8, w - 16, h - 16);
    g.fillStyle = '#9ea88f'; g.fillRect(36, 36, 120, 56);
    g.fillStyle = '#2d3428'; g.font = 'bold 40px "Courier New", monospace'; g.fillText('18°', 52, 80);
    g.font = '13px Arial'; g.fillStyle = '#6a6455'; g.fillText('CHAUFFAGE', 40, 120); g.fillText('▲  ▼', 176, 70);
    g.strokeStyle = '#9e9682'; g.lineWidth = 2; g.strokeRect(172, 40, 50, 46);
    g.fillStyle = 'rgba(0,0,0,0.08)'; g.fillRect(0, h - 10, w, 10);
  }, 6);
}

/** Duplex receptacle cover plate (North American, ivory). */
export function outletTexture(withCover = false) {
  return painted(128, 208, (g, w, h) => {
    g.fillStyle = '#e6dcc4'; g.fillRect(0, 0, w, h);
    const grad = g.createLinearGradient(0, 0, w, 0); grad.addColorStop(0, 'rgba(0,0,0,0.08)'); grad.addColorStop(0.5, 'rgba(255,255,255,0.05)'); grad.addColorStop(1, 'rgba(0,0,0,0.1)');
    g.fillStyle = grad; g.fillRect(0, 0, w, h);
    for (const cy of [62, 146]) {
      g.fillStyle = '#ddd2b8'; g.beginPath(); g.ellipse(w / 2, cy, 34, 36, 0, 0, TAU); g.fill();
      g.strokeStyle = 'rgba(0,0,0,0.25)'; g.lineWidth = 2; g.stroke();
      if (withCover) { g.fillStyle = '#f2efe6'; g.beginPath(); g.ellipse(w / 2, cy, 24, 26, 0, 0, TAU); g.fill(); g.strokeStyle = 'rgba(0,0,0,0.2)'; g.stroke(); continue; }
      g.fillStyle = '#1b1712';
      g.fillRect(w / 2 - 17, cy - 16, 5, 18); g.fillRect(w / 2 + 12, cy - 16, 5, 22);
      g.beginPath(); g.arc(w / 2, cy + 16, 5, Math.PI, TAU); g.lineTo(w / 2 + 5, cy + 22); g.lineTo(w / 2 - 5, cy + 22); g.fill();
    }
    g.fillStyle = '#b8ad94'; g.beginPath(); g.arc(w / 2, h / 2 + 0, 5, 0, TAU); g.fill();
    g.strokeStyle = '#8e846e'; g.lineWidth = 1.5; g.beginPath(); g.moveTo(w / 2 - 4, h / 2); g.lineTo(w / 2 + 4, h / 2); g.stroke();
  }, 8);
}

/** Toggle switch plate. */
export function switchTexture() {
  return painted(128, 208, (g, w, h) => {
    g.fillStyle = '#e6dcc4'; g.fillRect(0, 0, w, h);
    const grad = g.createLinearGradient(0, 0, w, 0); grad.addColorStop(0, 'rgba(0,0,0,0.08)'); grad.addColorStop(1, 'rgba(0,0,0,0.1)');
    g.fillStyle = grad; g.fillRect(0, 0, w, h);
    g.fillStyle = '#cfc4a8'; g.fillRect(w / 2 - 12, h / 2 - 34, 24, 68);
    g.strokeStyle = 'rgba(0,0,0,0.3)'; g.lineWidth = 2; g.strokeRect(w / 2 - 12, h / 2 - 34, 24, 68);
    for (const y of [30, h - 30]) { g.fillStyle = '#b8ad94'; g.beginPath(); g.arc(w / 2, y, 5, 0, TAU); g.fill(); }
  }, 9);
}

/** VHS sleeve atlas (3 spines/faces). */
export function vhsTexture() {
  return painted(512, 256, (g, w, h, R) => {
    const cols = ['#1a1a1c', '#2a3f78', '#b8b0a0'];
    for (let k = 0; k < 3; k++) {
      const y = (k * h) / 3;
      g.fillStyle = cols[k]; g.fillRect(0, y, w, h / 3);
      g.fillStyle = k === 2 ? '#1b1b1b' : '#efe8d8';
      g.fillRect(30, y + 18, w * 0.62, h / 3 - 36);
      g.fillStyle = '#2a2a6a';
      g.font = `28px ${FONT.hand}`;
      g.fillText(['Dessins animés', 'Noël 95', 'NE PAS EFFACER'][k], 44, y + h / 6 + 10);
      g.fillStyle = 'rgba(255,255,255,0.1)'; g.fillRect(0, y, w, 3);
      for (let q = 0; q < 30; q++) { g.fillStyle = `rgba(255,255,255,${R() * 0.06})`; g.fillRect(R() * w, y + R() * h / 3, 3, 1); }
    }
  }, 10);
}

/** TV remote: buttons texture for the top face. */
export function remoteTexture() {
  return painted(96, 256, (g, w, h) => {
    g.fillStyle = '#1d1d1f'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#b8352a'; g.beginPath(); g.arc(w * 0.75, 26, 9, 0, TAU); g.fill();
    g.fillStyle = '#4a4a4f';
    for (let r = 0; r < 4; r++) for (let q = 0; q < 3; q++) { g.beginPath(); g.ellipse(22 + q * 26, 70 + r * 26, 9, 7, 0, 0, TAU); g.fill(); }
    g.fillStyle = '#6a6a70';
    g.fillRect(36, 180, 24, 50); g.fillRect(24, 196, 48, 18);
    g.fillStyle = '#9a9aa0'; g.font = '9px Arial';
    for (let r = 0; r < 3; r++) for (let q = 0; q < 3; q++) g.fillText(String(r * 3 + q + 1), 19 + q * 26, 74 + r * 26);
  }, 12);
}

/** Paint can labels atlas (3 cells horizontally). */
export function paintLabelTexture() {
  return painted(512, 128, (g, w, h, R) => {
    const cols = [['#e9e2cf', '#7a2a2a', 'BEIGE SABLE'], ['#d9d9d6', '#2a4a7a', 'BLANC CASSÉ'], ['#c9c09a', '#3a5a2a', 'APPRÊT']];
    for (let k = 0; k < 3; k++) {
      const x = (k * w) / 3, cw = w / 3;
      g.fillStyle = cols[k][0]; g.fillRect(x, 0, cw, h);
      g.fillStyle = cols[k][1]; g.fillRect(x, 16, cw, 30);
      g.fillStyle = '#f4efe2'; g.font = 'bold 15px Arial'; g.fillText('PEINTURE', x + 20, 37);
      g.fillStyle = '#222'; g.font = 'bold 13px Arial'; g.fillText(cols[k][2], x + 18, 72);
      g.font = '10px Arial'; g.fillText('3,78 L  · LATEX', x + 18, 92);
      // drips
      for (let q = 0; q < 4; q++) { g.fillStyle = cols[k][0] === '#e9e2cf' ? '#cdbf9a' : '#b9b9b4'; g.fillRect(x + R() * cw, 0, 3, 8 + R() * 22); }
      g.fillStyle = 'rgba(0,0,0,0.12)'; g.fillRect(x + cw - 2, 0, 2, h);
    }
  }, 13);
}

/** Toy blocks letter atlas: 8 cells (letter on colored face). */
export function blocksTexture() {
  return painted(512, 64, (g, w, h) => {
    const letters = ['A', 'B', 'C', 'L', 'É', 'A', '7', '★'];
    const cols = ['#c8352a', '#2f5fb3', '#3f9a3c', '#e3b21c', '#7d4ab0', '#ec8a24', '#2f8a8a', '#c8352a'];
    for (let k = 0; k < 8; k++) {
      const x = k * 64;
      g.fillStyle = '#d9b98a'; g.fillRect(x, 0, 64, 64);
      g.fillStyle = cols[k]; g.fillRect(x + 6, 6, 52, 52);
      g.fillStyle = '#f3ead6'; g.font = `bold 40px ${FONT.sans}`; g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(letters[k], x + 32, 34);
      g.fillStyle = 'rgba(0,0,0,0.15)'; g.fillRect(x, 60, 64, 4);
    }
  }, 14);
}

/** Crayon box (cardboard, 8 crayons). */
export function crayonBoxTexture() {
  return painted(256, 128, (g, w, h) => {
    g.fillStyle = '#2f8a3a'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#f2c624'; g.fillRect(0, 0, w, 34);
    g.fillStyle = '#1b3b1e'; g.font = `bold 22px ${FONT.sans}`; g.fillText('CRAYONS', 18, 70);
    g.font = 'bold 16px Arial'; g.fillText('DE CIRE · 8 COULEURS', 18, 96);
    const cs = ['#c8352a', '#2f5fb3', '#3f9a3c', '#f2c624', '#7d4ab0', '#ec8a24', '#1c1a1d', '#e86a9a'];
    for (let k = 0; k < 8; k++) { g.fillStyle = cs[k]; g.fillRect(150 + k * 12, 104, 10, 18); }
  }, 15);
}

/** Main breaker label + circuit list (hand-written on masking tape). */
export function breakerLabelTexture() {
  return painted(256, 128, (g, w, h, R) => {
    g.fillStyle = '#e4d6ac'; g.fillRect(0, 0, w, h);
    for (let k = 0; k < 300; k++) { g.fillStyle = `rgba(120,100,60,${R() * 0.12})`; g.fillRect(R() * w, R() * h, 2, 1); }
    g.fillStyle = '#1d1d26';
    g.font = `600 30px ${FONT.hand}`;
    g.fillText('PRINCIPAL', 16, 40);
    g.font = `600 24px ${FONT.hand}`;
    g.fillText('sous-sol / salon', 16, 74);
    g.fillText('↑ marche   ↓ arrêt', 16, 108);
  }, 16);
}

/** Small cardboard key tag: "porte d'en haut". */
export function keyTagTexture() {
  return painted(128, 80, (g, w, h, R) => {
    g.fillStyle = '#d8c39a'; g.fillRect(0, 0, w, h);
    for (let k = 0; k < 120; k++) { g.fillStyle = `rgba(120,90,50,${R() * 0.15})`; g.fillRect(R() * w, R() * h, 2, 1); }
    g.strokeStyle = '#9a7a4a'; g.lineWidth = 2; g.beginPath(); g.arc(16, h / 2, 6, 0, TAU); g.stroke();
    g.fillStyle = '#26242e'; g.font = `700 26px ${FONT.hand}`;
    g.fillText('en haut', 30, h / 2 + 9);
  }, 17);
}

/** Slotted plastic texture for the laundry basket (alpha in the slots). */
export function basketTexture() {
  return painted(256, 128, (g, w, h) => {
    g.fillStyle = '#f2f0ea'; g.fillRect(0, 0, w, h);
    g.globalCompositeOperation = 'destination-out';
    for (let r = 0; r < 3; r++) for (let k = 0; k < 10; k++) {
      const x = 10 + k * 24.5, y = 18 + r * 34;
      g.beginPath(); g.moveTo(x + 4, y); g.lineTo(x + 14, y); g.arc(x + 14, y + 10, 4, -Math.PI / 2, Math.PI / 2); g.lineTo(x + 4, y + 20); g.arc(x + 4, y + 10, 4, Math.PI / 2, Math.PI * 1.5); g.fill();
    }
    g.globalCompositeOperation = 'source-over';
  }, 18);
}

/** Air return grille (alpha slots). */
export function grilleTexture() {
  return painted(256, 128, (g, w, h) => {
    g.fillStyle = '#e8e2d4'; g.fillRect(0, 0, w, h);
    g.globalCompositeOperation = 'destination-out';
    for (let k = 0; k < 13; k++) g.fillRect(14, 12 + k * 8, w - 28, 4.5);
    g.globalCompositeOperation = 'source-over';
    g.strokeStyle = 'rgba(0,0,0,0.25)'; g.lineWidth = 3; g.strokeRect(2, 2, w - 4, h - 4);
  }, 19);
}

// ------------------------------------------------------------------------------------------------ TV static

/**
 * Animated CRT static: noise, scanlines, rolling bar, vignette and a faint digit that flickers in now and then.
 * draw(time, digitAmount) updates the canvas and flags the texture. No per-frame allocations.
 */
export class TVStatic {
  constructor(w = 160, h = 120) {
    this.w = w; this.h = h;
    this.canvas = makeCanvas(w, h);
    this.ctx = this.canvas.getContext('2d', { willReadFrequently: true });
    this.img = this.ctx.createImageData(w, h);
    this.u32 = new Uint32Array(this.img.data.buffer);
    this.vig = new Float32Array(w * h);
    this.mask = new Float32Array(w * h);
    this.hasDigit = false;
    this._seed = 0x9e3779b9 | 0;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const dx = (x / (w - 1)) * 2 - 1, dy = (y / (h - 1)) * 2 - 1;
      // rounded-rect CRT mask + vignette
      const r = Math.pow(Math.pow(Math.abs(dx), 6) + Math.pow(Math.abs(dy), 6), 1 / 6);
      this.vig[y * w + x] = r > 1 ? 0 : Math.max(0, 1 - Math.pow(r, 3) * 0.55) * (r > 0.97 ? (1 - r) / 0.03 : 1);
    }
    this.texture = canvasTexture(this.canvas, { mipmaps: false, cap: false }); // redrawn every frame: same canvas, no mips
    this.texture.magFilter = THREE.LinearFilter;
  }

  setDigit(d) {
    this.mask.fill(0);
    this.hasDigit = d !== null && d !== undefined && d !== '';
    if (!this.hasDigit) return;
    const c = makeCanvas(this.w, this.h), g = c.getContext('2d');
    g.fillStyle = '#fff'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.font = `bold ${Math.round(this.h * 0.72)}px ${FONT.sans}`;
    g.fillText(String(d), this.w / 2, this.h * 0.54);
    const data = g.getImageData(0, 0, this.w, this.h).data;
    for (let i = 0; i < this.mask.length; i++) this.mask[i] = data[i * 4 + 3] / 255;
  }

  _rand() { // xorshift32
    let x = this._seed; x ^= x << 13; x ^= x >>> 17; x ^= x << 5; this._seed = x; return (x >>> 0) & 255;
  }

  draw(time, digitAmount = 0, power = 1) {
    const { w, h, u32, vig, mask } = this;
    const bar = (time * 0.23) % 1.4 - 0.2; // rolling bar position (0..1 screen)
    const shift = (this._rand() & 3) === 0 ? (this._rand() & 3) : 0; // horizontal sync jitter rows
    for (let y = 0; y < h; y++) {
      const fy = y / h;
      const db = fy - bar;
      const barF = 1 + 0.35 * Math.exp(-db * db * 90) - 0.18 * Math.exp(-(db + 0.08) * (db + 0.08) * 200);
      const line = ((y & 1) ? 0.72 : 1) * barF * power;
      const jitter = (y % 23 === 0) ? shift : 0;
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        const v0 = vig[i];
        if (v0 === 0) { u32[i] = 0xff000000; continue; }
        let n = this._rand();
        n = (n * n) >> 8; // bias toward dark speckle
        let v = (40 + n * 0.85) * line * v0;
        if (digitAmount > 0) {
          const m = mask[(i + jitter) % mask.length];
          if (m > 0) v = v * (1 - m * 0.45 * digitAmount) + m * digitAmount * 150 * v0;
        }
        const r = v * 0.9, gg = v * 0.97, b = v * 1.08;
        u32[i] = 0xff000000 | ((b > 255 ? 255 : b) << 16) | ((gg > 255 ? 255 : gg) << 8) | (r > 255 ? 255 : r);
      }
    }
    this.ctx.putImageData(this.img, 0, 0);
    this.texture.needsUpdate = true;
  }

  /** Solid frame (CRT warm-up / collapse): brightness 0..1 */
  fill(v) {
    const { u32, vig } = this;
    for (let i = 0; i < u32.length; i++) { const c = Math.min(255, v * 255 * (vig[i] > 0 ? 1 : 0)) | 0; u32[i] = 0xff000000 | (c << 16) | (c << 8) | c; }
    this.ctx.putImageData(this.img, 0, 0);
    this.texture.needsUpdate = true;
  }
}
