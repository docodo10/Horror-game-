// UI module — every screen, HUD element and modal of "La Gardienne". All player-facing text is French.
//
// Concept: the menu lives ON the old CRT TV of the basement (diegetic, real 3D). A teletext-style page
// ("CANAL 3 · LA GARDIENNE", late-90s Québec TV) is drawn on a canvas, mapped on a curved plane fitted over the TV glass
// with a CRT shader (barrel curvature, scanlines, RGB mask, bleed, rolling bar, noise, vignette, jitter, power-off
// collapse). The same teletext pages are reused full-screen (DOM canvas + CSS CRT) for loading, pause, caught,
// game over and win. Notes stay physical paper; the keypad is the brass combination padlock. The in-game HUD is
// almost empty (dot + prompt, subtitles, objective toast, tiny battery / stamina hints).
//
// Public API (kept; every show* that returns a Promise resolves when the player closes it):
//   constructor(game, root); init(); update(dt)
//   showLoading(progress 0..1, text)            hideLoading() is implicit when showMenu()/start happens
//   showMenu() / hideMenu()                     "NOUVELLE PARTIE" -> CRT power-off (1.2 s) -> game.events.emit('ui:start')
//   showPause() -> Promise (resolves on "Reprendre")   hidePause()
//   showCaught({ night, nightsTotal }) -> Promise      showGameOver() -> Promise      showWin({ time, nightsUsed, nightsTotal }) -> Promise
//   fadeTo(alpha 0..1, seconds) -> Promise       black overlay
//   setPrompt(text|null, { hold?: 0..1, key?: 'E'|'✋', touch? })   prompt under the dot; hold ring when hold is a number
//   subtitle(text, seconds=3.5, { speaker?, critical?, hint? })     critical shows even when subtitles are off
//   setObjective(text)                           objective toast (typewriter), fades after a few seconds
//   alert(text, seconds=2)                       big centered warning (e.g. 'CACHE-TOI !')
//   setInventory(items[], notes?)                shown in the pause page (no permanent HUD)
//   setBattery(v 0..1 | null)  setStamina(v 0..1)  setNight(night, total)
//   setClues({ duck, horse, clock, tv })         digits shown in the pause page and next to the padlock
//   showNote({ title, text, style: 'note'|'child'|'newspaper' }) -> Promise
//   showKeypad({ title, length: 4 }) -> Promise<string|null>   (null = cancelled)
//   setHidden(bool)                              closet hint ('Appuie sur E pour sortir')
//   isModalOpen() -> bool
// Additions (public):
//   menuCameraActive (getter)    true while the TV menu owns the camera (state 'menu', or 'loading' once the TV exists)
//   updateMenuCamera(dt)         writes game.camera (call it INSTEAD of player.updateIdleCamera while menuCameraActive)
//   hideLoading(); showOptions() / showControls() / showCredits() -> Promise (TV pages in the menu, CRT overlay otherwise)
//   showNote({ ..., headline?, masthead?, date? }) newspaper extras
// Emits: 'ui:start' (after the power-off transition), 'ui:quit' (just before reloading from the pause page).
// Settings used: quality, sensitivity, invertY, brightness, volume, subtitles, fov, cameraMotion (0..1, default 1).
// Calls (all optional): world.lighting.setTVLight(on, intensity), world.tv.setOn(on) (only if setTVLight is missing),
//   audio.unlock() on the first gesture in the menu (menu sounds), audio.play/loop('flashlight_click'|'tv_on'|'tv_off'|
//   'tv_static'|'paper'|'lock_wheel').
import * as THREE from 'three';
import { DEFAULT_SETTINGS } from '../core/Settings.js';
import * as LAYOUT from '../config/layout.js';

// ------------------------------------------------------------------ helpers

const NBSP = ' ';
const DOT = '․'; // leader dot glyph (drawn by the teletext renderer)
/** French typography: non-breaking space before ! ? : ; » and after «. */
const fr = (s) => String(s ?? '').replace(/ ([!?:;»])/g, `${NBSP}$1`).replace(/« /g, `«${NBSP}`);
const up = (s) => fr(s).toLocaleUpperCase('fr-FR');
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const clamp01 = (v) => clamp(v, 0, 1);
const now = () => performance.now();
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const h = (html) => {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
};
const cssq = (s) => (globalThis.CSS && typeof globalThis.CSS.escape === 'function' ? globalThis.CSS.escape(String(s)) : String(s).replace(/["\\]/g, '\\$&'));
const visible = (el) => !!el && !el.closest('[hidden]') && el.getClientRects().length > 0;
const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
/** Word wrap on regular spaces only (non-breaking spaces keep words together). */
function wrap(str, width) {
  const out = [];
  for (const para of String(str ?? '').split('\n')) {
    let line = '';
    for (const w of para.split(/ +/)) {
      if (!w) continue;
      if (!line) line = w;
      else if (line.length + 1 + w.length <= width) line += ` ${w}`;
      else { out.push(line); line = w; }
      while (line.length > width) { out.push(line.slice(0, width)); line = line.slice(width); }
    }
    out.push(line);
  }
  return out;
}

const QUALITY = [['auto', 'Auto'], ['low', 'Basse'], ['medium', 'Moyenne'], ['high', 'Haute'], ['ultra', 'Ultra']];
const CLUES = [['duck', 'Canard'], ['horse', 'Cheval'], ['clock', 'Horloge'], ['tv', 'Télé']];
const ITEM_NAMES = { flashlight: 'Lampe', battery: 'Pile', key: 'Clé' };

const TIPS = [
  'Accroupis-toi : tes pas feront moins de bruit.',
  'Elle entend tout. Les tiroirs aussi.',
  'Le placard sous l’escalier est une bonne cachette… si elle ne te voit pas y entrer.',
  'Ta lampe de poche te rend visible. Éteins-la quand elle approche.',
  'Les piles s’usent vite. Garde-en une de côté.',
  'Si elle te voit, cours. Puis cache-toi.',
  'La télé fait beaucoup de bruit quand elle est allumée.',
];
const TICKER_MENU = [
  'MÉTÉO : −24 °C, RESSENTI −33. VERGLAS SUR LA 20',
  'AVIS DE RECHERCHE : GARDIENNE D’ENFANTS, 19 ANS, VUE POUR LA DERNIÈRE FOIS RUE DES ÉRABLES',
  'RAPPEL AUX PARENTS : VERROUILLEZ LA PORTE DU SOUS-SOL',
  'ÉCOLES FERMÉES DEMAIN',
  'BONNE NUIT LES PETITS. PAS UN BRUIT',
].join('   ·   ');

// Teletext palette (slightly softened for the eyes).
const C = { k: '#000000', r: '#ff3b2f', g: '#38f25b', y: '#ffe63c', b: '#2c4bff', m: '#ff4fe2', c: '#40ecff', w: '#f4f2ea', d: '#626a78' };

// Inline SVG icons (24×24 line icons).
const P = {
  hand: '<path d="M7 14.5V7.2a1.6 1.6 0 0 1 3.2 0V12"/><path d="M10.2 11.5V4.9a1.6 1.6 0 0 1 3.2 0v6.6"/><path d="M13.4 11.5V6.1a1.6 1.6 0 0 1 3.2 0v5.9"/><path d="M16.6 12V8.6a1.6 1.6 0 0 1 3.2 0v5.6c0 4.3-3.1 7.3-7.3 7.3h-1.3c-2.2 0-3.8-.8-5.2-2.5L2.9 15.4a1.6 1.6 0 0 1 2.5-2L7 15"/>',
  rotate: '<rect x="3" y="7.5" width="9" height="14" rx="1.8"/><path d="M6.5 18.5h2"/><path d="M14.5 3.2a7 7 0 0 1 6.3 6.8"/><path d="M18.6 8.3l2.2 1.8 1.8-2.3"/>',
  eyeClosed: '<path d="M3 10.5c2.4 3.2 5.5 4.8 9 4.8s6.6-1.6 9-4.8"/><path d="M5.8 13.6l-1.6 2.2M9.6 15.1l-.6 2.6M14.4 15.1l.6 2.6M18.2 13.6l1.6 2.2"/>',
  up: '<path d="M6 14.5l6-6 6 6"/>',
  down: '<path d="M6 9.5l6 6 6-6"/>',
};
const icon = (name, cls = '') =>
  `<svg class="lg-i ${cls}" viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${P[name] || ''}</svg>`;
const cap = (t) => `<kbd class="lg-cap">${t}</kbd>`;

/** Jagged polygon for torn paper edges (bottom edge). */
function tornClip(steps = 16, bottomMin = 93) {
  const pts = ['0% 0%', '100% 0%'];
  for (let i = 0; i <= steps; i++) pts.push(`${(100 - (i * 100) / steps).toFixed(1)}% ${(bottomMin + Math.random() * (100 - bottomMin)).toFixed(1)}%`);
  return `polygon(${pts.join(',')})`;
}

// ------------------------------------------------------------------ procedural textures (canvas, once)

function makeGrain(size = 192) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const img = g.createImageData(size, size);
  const d = img.data;
  for (let i = 0; i < d.length; i += 4) {
    const n = Math.random();
    if (n < 0.5) { d[i] = 72; d[i + 1] = 54; d[i + 2] = 30; d[i + 3] = (0.5 - n) * 64; }
    else { d[i] = 255; d[i + 1] = 248; d[i + 2] = 228; d[i + 3] = (n - 0.5) * 44; }
  }
  g.putImageData(img, 0, 0);
  g.lineCap = 'round';
  for (let i = 0; i < 80; i++) {
    const x = Math.random() * size, y = Math.random() * size, a = Math.random() * Math.PI, l = 3 + Math.random() * 11;
    g.strokeStyle = `rgba(80,60,35,${(0.05 + Math.random() * 0.09).toFixed(3)})`;
    g.lineWidth = 0.6;
    g.beginPath();
    g.moveTo(x, y);
    g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l);
    g.stroke();
  }
  return c.toDataURL('image/png');
}

/** Wax-crayon "tooth" (child notes). */
function makeWax(rgb, size = 128) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  g.lineCap = 'round';
  for (let i = 0; i < 700; i++) {
    const x = Math.random() * size, y = Math.random() * size, l = 1.5 + Math.random() * 6;
    g.strokeStyle = `rgba(${rgb},${(0.25 + Math.random() * 0.6).toFixed(2)})`;
    g.lineWidth = 0.5 + Math.random() * 1.1;
    g.beginPath();
    g.moveTo(x, y);
    g.lineTo(x + l * 0.85, y - l * 0.4);
    g.stroke();
  }
  for (let i = 0; i < 1100; i++) {
    g.fillStyle = `rgba(${rgb},${(Math.random() * 0.75).toFixed(2)})`;
    g.fillRect(Math.random() * size, Math.random() * size, 1 + Math.random() * 1.4, 1);
  }
  return c.toDataURL('image/png');
}

/** Small grey noise tile (CRT overlay grain). */
function makeNoise(size = 128) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const img = g.createImageData(size, size);
  for (let i = 0; i < img.data.length; i += 4) {
    const v = Math.random() * 255;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
    img.data[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  return c.toDataURL('image/png');
}

// ================================================================== teletext renderer

/**
 * Character-grid page renderer. Background blocks are drawn crisp on the main canvas; text is drawn on a separate
 * layer whose alpha is thresholded (no anti-aliasing) to get the bitmap-font look of 90s teletext, then composited.
 */
class Teletext {
  constructor(cols, rows, cw, ch, padX, padY, { mix = false } = {}) {
    this.cols = cols; this.rows = rows; this.cw = cw; this.ch = ch; this.px = padX; this.py = padY; this.mix = mix;
    this.W = cols * cw + padX * 2;
    this.H = rows * ch + padY * 2;
    this.canvas = document.createElement('canvas');
    this.canvas.width = this.W; this.canvas.height = this.H;
    this.ctx = this.canvas.getContext('2d');
    this.layer = document.createElement('canvas');
    this.layer.width = this.W; this.layer.height = this.H;
    this.t = this.layer.getContext('2d', { willReadFrequently: true });
    this.fontPx = Math.round(ch * 0.72);
    this.font = `700 ${this.fontPx}px "Atkinson Hyperlegible", Arial, Helvetica, sans-serif`;
    this._w = new Map();
    this._noise = null;
  }

  begin() {
    const c = this.ctx;
    c.globalAlpha = 1;
    if (this.mix) c.clearRect(0, 0, this.W, this.H);
    else { c.fillStyle = C.k; c.fillRect(0, 0, this.W, this.H); }
    this.t.clearRect(0, 0, this.W, this.H);
    this.t.font = this.font;
    this.t.textBaseline = 'alphabetic';
  }

  X(col) { return this.px + col * this.cw; }
  Y(row) { return this.py + row * this.ch; }

  rect(col, row, w, hgt, color) { this.ctx.fillStyle = color; this.ctx.fillRect(this.X(col), this.Y(row), w * this.cw, hgt * this.ch); }

  /** Full-width band (covers the side margins too; row 0 also covers the top margin). */
  band(row, color, hgt = 1) { this.ctx.fillStyle = color; this.ctx.fillRect(0, this.Y(row) - (row === 0 ? this.py : 0), this.W, hgt * this.ch + (row === 0 ? this.py : 0)); }

  /** Teletext 2×3 mosaic cell (bits 0..5, row-major) with "separated" gaps. */
  mosaic(col, row, bits, color) {
    const c = this.ctx, x = this.X(col), y = this.Y(row), w = this.cw / 2, hh = this.ch / 3;
    c.fillStyle = color;
    for (let k = 0; k < 6; k++) if (bits & (1 << k)) c.fillRect(Math.round(x + (k & 1) * w + 1), Math.round(y + (k >> 1) * hh + 1), Math.ceil(w - 2), Math.ceil(hh - 2));
  }

  _mw(ch) {
    let w = this._w.get(ch);
    if (w === undefined) { w = this.t.measureText(ch).width; this._w.set(ch, w); }
    return w;
  }

  clearMetrics() { this._w.clear(); }

  /** Draw a string from (col,row); ox = pixel offset (ticker). dh = double height (2 rows). */
  text(col, row, str, color, dh = false, ox = 0) {
    const t = this.t;
    t.fillStyle = color;
    let x = this.X(col) + ox;
    const y = this.Y(row), cw = this.cw, hh = dh ? this.ch * 2 : this.ch;
    for (const c of String(str)) {
      if (x > this.W) break;
      if (c !== ' ' && c !== NBSP && x > -cw) this._glyph(c, x, y, cw, hh, dh);
      x += cw;
    }
  }

  _glyph(c, x, y, w, hh, dh) {
    const t = this.t;
    const tri = (ax, ay, bx, by, cx, cy) => { t.beginPath(); t.moveTo(ax, ay); t.lineTo(bx, by); t.lineTo(cx, cy); t.closePath(); t.fill(); };
    switch (c) {
      case '◄': tri(x + w * 0.8, y + hh * 0.3, x + w * 0.8, y + hh * 0.74, x + w * 0.18, y + hh * 0.52); return;
      case '►': tri(x + w * 0.2, y + hh * 0.3, x + w * 0.2, y + hh * 0.74, x + w * 0.82, y + hh * 0.52); return;
      case '▶': tri(x + w * 0.12, y + hh * 0.24, x + w * 0.12, y + hh * 0.8, x + w * 0.92, y + hh * 0.52); return;
      case '▲': tri(x + w * 0.12, y + hh * 0.72, x + w * 0.88, y + hh * 0.72, x + w * 0.5, y + hh * 0.3); return;
      case '▼': tri(x + w * 0.12, y + hh * 0.32, x + w * 0.88, y + hh * 0.32, x + w * 0.5, y + hh * 0.74); return;
      case '█': t.fillRect(x, y, w, hh); return;
      case '▮': t.fillRect(x + w * 0.14, y + hh * 0.26, w * 0.72, hh * 0.54); return;
      case '▯': {
        const lw = Math.max(2, Math.round(w * 0.14));
        t.fillRect(x + w * 0.14, y + hh * 0.26, w * 0.72, lw); t.fillRect(x + w * 0.14, y + hh * 0.8 - lw, w * 0.72, lw);
        t.fillRect(x + w * 0.14, y + hh * 0.26, lw, hh * 0.54); t.fillRect(x + w * 0.86 - lw, y + hh * 0.26, lw, hh * 0.54);
        return;
      }
      case DOT: { const s = Math.max(2, Math.round(w * 0.18)); t.fillRect(Math.round(x + w * 0.42), Math.round(y + hh * 0.68), s, s); return; }
      default: {
        const m = this._mw(c);
        const sx = m > w * 0.9 ? (w * 0.9) / m : 1;
        t.save();
        t.translate(x + w / 2, y + hh * 0.78);
        t.scale(sx, dh ? 2 : 1);
        t.fillText(c, -m / 2, 0);
        t.restore();
      }
    }
  }

  end() {
    const img = this.t.getImageData(0, 0, this.W, this.H);
    const d = img.data;
    for (let i = 3; i < d.length; i += 4) d[i] = d[i] >= 100 ? 255 : 0;
    this.t.putImageData(img, 0, 0);
    this.ctx.drawImage(this.layer, 0, 0);
  }

  /** Blocky static noise drawn over the page (bursts on the full-screen CRT). */
  noise(amount) {
    if (amount <= 0) return;
    if (!this._noise) { this._noise = document.createElement('canvas'); this._noise.width = 160; this._noise.height = 120; }
    const n = this._noise, g = n.getContext('2d');
    const img = g.createImageData(n.width, n.height);
    for (let i = 0; i < img.data.length; i += 4) {
      const v = Math.random() * 255;
      img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
      img.data[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    const c = this.ctx;
    c.save();
    c.globalAlpha = clamp01(amount);
    c.imageSmoothingEnabled = false;
    c.drawImage(n, 0, 0, this.W, this.H);
    c.restore();
  }
}

/** Page builder: draws while recording selectable items (positions for hit testing). */
class TTBuilder {
  constructor(screen) {
    this.s = screen;
    this.tt = screen.tt;
    this.cols = screen.tt.cols;
    this.rows = screen.tt.rows;
    this.items = [];
    this.touch = !!screen.ui._isTouch;
    this.blink = screen.blink;
  }

  bar(row, color, hgt = 1) { this.tt.band(row, color, hgt); }

  /** col: number | 'c' (centered) | 'r' (right aligned). */
  text(row, col, str, color = C.w, { dh = false, bg = null } = {}) {
    const s = up(str);
    const len = [...s].length;
    const x = col === 'c' ? Math.max(0, Math.floor((this.cols - len) / 2)) : col === 'r' ? this.cols - len : col;
    if (bg) this.tt.rect(x, row, len, dh ? 2 : 1, bg);
    this.tt.text(x, row, s, color, dh);
    return x;
  }

  header(title = 'CANAL 3 · LA GARDIENNE', bg = C.b, fg = C.y) {
    this.tt.band(0, bg);
    this.text(0, 0, title, fg);
    const m = this.s.ui._clockMinutes();
    const hh = String(Math.floor(m / 60) % 24).padStart(2, '0'), mm = String(m % 60).padStart(2, '0');
    this.tt.text(this.cols - 5, 0, `${hh}${this.blink ? ':' : ' '}${mm}`, C.w);
  }

  /** Row 1: page number left (or the digits being typed), info right. */
  pnum(num, right = '', rightColor = C.c) {
    const typed = this.s.typed;
    this.tt.text(0, 1, typed ? `P${typed.padEnd(3, '-')}` : `P${num}`, typed ? C.y : C.w);
    if (right) this.text(1, 'r', right, rightColor);
  }

  info(row, label, value, valueColor = C.c) {
    const L = up(label), V = up(value);
    this.tt.text(1, row, L, C.w);
    const x = this.cols - [...V].length;
    for (let i = 1 + [...L].length + 1; i < x - 1; i++) this.tt.text(i, row, DOT, C.b);
    this.tt.text(x, row, V, valueColor);
  }

  /**
   * Selectable line. kind 'link' (right = page number/info), 'value' (◄ value ►; change(dir)), 'action'.
   * on(): activation; change(dir): value change (Enter = +1).
   */
  item(row, { id, label, right = null, kind = 'link', on = null, change = null, color = C.w, sr = '' }) {
    const s = this.s, tt = this.tt, cols = this.cols;
    if (s.selId == null) s.selId = id;
    const sel = s.selId === id;
    const L = up(label);
    if (sel) tt.rect(0, row, cols, 1, C.w);
    const fg = sel ? C.k : color;
    if (sel && this.blink) tt.text(0, row, '▶', C.k);
    tt.text(1, row, L, fg);
    const it = { id, row, kind, on, change, field: null, sr: sr || `${label}${right != null ? ` : ${right}` : ''}` };
    if (kind === 'value') {
      const a = cols - 13;
      const V = up(right ?? '');
      tt.text(a, row, '◄', sel ? C.k : C.y);
      tt.text(a + 1 + Math.max(0, Math.floor((11 - [...V].length) / 2)), row, V, sel ? C.k : C.c);
      tt.text(cols - 1, row, '►', sel ? C.k : C.y);
      it.field = [a, cols - 1];
    } else if (right != null && right !== '') {
      const R = up(right);
      const x = cols - [...R].length;
      for (let i = 1 + [...L].length + 1; i < x - 1; i++) tt.text(i, row, DOT, sel ? C.k : C.b);
      tt.text(x, row, R, sel ? C.k : C.y);
    }
    this.items.push(it);
    return it;
  }

  /** Decorative mosaic band (snowy rooftops). */
  mosaicBand(row, color = C.c, seed = 3) {
    for (let i = 0; i < this.cols; i++) {
      const v = Math.sin(i * 0.9 + seed) + Math.sin(i * 0.37 + seed * 2);
      const bits = v > 0.9 ? 0b111111 : v > 0.1 ? 0b111100 : v > -0.7 ? 0b110000 : 0;
      if (bits) this.tt.mosaic(i, row, bits, color);
    }
  }

  ticker(text, { bg = C.r, fg = C.w, row = this.rows - 1 } = {}) {
    const tt = this.tt;
    tt.band(row, bg);
    const str = `${up(text)}   ·   `;
    const len = [...str].length * tt.cw;
    const ox = -(this.s.tickerX % len);
    tt.text(0, row, str, fg, false, ox - tt.px);
    tt.text(0, row, str, fg, false, ox - tt.px + len);
    if (len < tt.W) tt.text(0, row, str, fg, false, ox - tt.px + len * 2);
    this.s.hasTicker = true;
  }

  hint(text, color = C.g, row = this.rows - 1) { this.text(row, 'c', text, color); }

  back(fn) { this.s.onBack = fn; }
  lr(fn) { this.s.onLR = fn; }
  digits(fn) { this.s.onDigit = fn; }
  wrap(str, width = this.cols - 2) { return wrap(up(str), width); }
}

/** A teletext display (TV mesh or DOM overlay): page, selection, keyboard, hit testing, hidden accessible buttons. */
class TTScreen {
  constructor(ui, tt, srHost) {
    this.ui = ui;
    this.tt = tt;
    this.srHost = srHost;
    this.pageFn = null;
    this.pageName = '';
    this.home = '';
    this.items = [];
    this.selId = null;
    this.dirty = true;
    this.blink = true;
    this.blinkT = 0;
    this.flick = 0;
    this.tickerX = 0;
    this.hasTicker = false;
    this.typed = '';
    this.typedT = 0;
    this.burst = 0;          // static burst remaining (s)
    this.burstMax = 1;
    this.srFocus = false;
    this.onDrawn = null;
    this.onBack = null;
    this.onLR = null;
    this.onDigit = null;
    this.allowE = false;
    this.locked = false;
    this._srSig = '';
    this._keyAt = 0;
    srHost.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-id]');
      if (!b || !this.srFocus || now() - this._keyAt < 450 || this.locked) return;
      this.selId = b.dataset.id;
      this.activate(0);
    });
    srHost.addEventListener('focusin', (e) => {
      const b = e.target.closest('button[data-id]');
      if (b && b.dataset.id !== this.selId) { this.selId = b.dataset.id; this.dirty = true; }
    });
  }

  show(name, fn, sel = null) {
    this.pageName = name;
    this.pageFn = fn;
    this.selId = sel;
    this.items = [];
    this.dirty = true;
    this.typed = '';
    this._lt = 0;
  }

  /** Inputs must act on the page as it is now (a page switch / value change may not be drawn yet). */
  _fresh() { if (this.dirty && this.pageFn) this.draw(); }

  tick(dt) {
    // bursts / flicker are short visual events: decay them on wall-clock time (game dt is clamped at low fps)
    const tn = now();
    const rdt = this._lt ? Math.min(0.25, (tn - this._lt) / 1000) : dt;
    this._lt = tn;
    this.blinkT += dt;
    if (this.blinkT >= 0.5) { this.blinkT -= 0.5; this.blink = !this.blink; this.dirty = true; }
    if (this.flick > 0) this.flick = Math.max(0, this.flick - rdt * 5);
    if (this.hasTicker) {
      const before = Math.floor(this.tickerX / 3);
      this.tickerX += dt * 34;
      if (Math.floor(this.tickerX / 3) !== before) this.dirty = true;
    }
    if (this.typed) { this.typedT -= dt; if (this.typedT <= 0) { this.typed = ''; this.dirty = true; } }
    if (this.burst > 0) { this.burst = Math.max(0, this.burst - rdt); this.dirty = true; }
  }

  draw() {
    const tt = this.tt;
    tt.begin();
    this.onBack = null; this.onLR = null; this.onDigit = null; this.hasTicker = false;
    const b = new TTBuilder(this);
    try { this.pageFn?.(b); } catch (e) { console.error('[ui] teletext page', e); }
    tt.end();
    if (this.burst > 0) tt.noise(clamp01(this.burst / Math.max(0.05, this.burstMax)) * (this.burstMax > 0.5 ? 1.1 : 0.55));
    this.items = b.items;
    if (this.items.length && !this.items.some((i) => i.id === this.selId)) { this.selId = this.items[0].id; this.dirty = true; }
    else this.dirty = false;
    this._syncSr();
    this.onDrawn?.();
  }

  get sel() { return this.items.find((i) => i.id === this.selId) || null; }

  select(id, sound = true) {
    if (id === this.selId) return;
    this.selId = id;
    this.dirty = true;
    this.flick = 1;
    if (sound) this.ui._sfx('select');
    this._focusSr();
  }

  move(d) {
    this._fresh();
    const n = this.items.length;
    if (!n || this.locked) return;
    let i = this.items.findIndex((it) => it.id === this.selId);
    i = i < 0 ? 0 : (i + d + n) % n;
    this.select(this.items[i].id);
  }

  activate(side = 0) {
    this._fresh();
    const it = this.sel;
    if (!it || this.locked) return;
    if (it.change) { it.change(side || 1); this.ui._sfx('value'); this.flick = Math.max(this.flick, 0.5); }
    else if (it.on) it.on();
    this.dirty = true;
    if (it.change) this._fresh();
  }

  key(e) {
    if (this.locked) return true;
    this._fresh();
    const k = e.key;
    if (k === 'ArrowUp' || k === 'ArrowDown') { this.move(k === 'ArrowDown' ? 1 : -1); return true; }
    if (k === 'ArrowLeft' || k === 'ArrowRight') {
      const d = k === 'ArrowRight' ? 1 : -1;
      const it = this.sel;
      if (it?.change) { it.change(d); this.ui._sfx('value'); this.flick = Math.max(this.flick, 0.5); this.dirty = true; this._fresh(); }
      else if (this.onLR) this.onLR(d);
      return true;
    }
    if (k === 'Enter' || k === 'NumpadEnter' || k === ' ' || (this.allowE && e.code === 'KeyE')) {
      if (e.repeat) return true;
      this._keyAt = now();
      this.activate(0);
      return true;
    }
    if (k === 'Escape' || k === 'Backspace') {
      if (this.onBack) { if (!e.repeat) this.onBack(); return true; }
      return false;
    }
    if (/^[0-9]$/.test(k) && this.onDigit) { this.onDigit(k); return true; }
    return false;
  }

  /** u,v in 0..1 with v = 0 at the top of the page. */
  hit(u, v) {
    this._fresh();
    const tt = this.tt;
    const col = Math.floor((u * tt.W - tt.px) / tt.cw), row = Math.floor((v * tt.H - tt.py) / tt.ch);
    const it = this.items.find((i) => i.row === row);
    if (!it) return null;
    let side = 0;
    if (it.field && col >= it.field[0] - 1) side = col < (it.field[0] + it.field[1]) / 2 ? -1 : 1;
    return { it, side };
  }

  _syncSr() {
    const sig = this.items.map((i) => i.id).join('|');
    if (sig !== this._srSig) {
      this._srSig = sig;
      const had = this.srHost.contains(document.activeElement);
      this.srHost.innerHTML = this.items.map((i) => `<button type="button" role="menuitem" data-id="${esc(i.id)}">${esc(fr(i.sr))}</button>`).join('');
      if (had || this.srFocus) this._focusSr();
    } else {
      for (const i of this.items) {
        const b = this.srHost.querySelector(`button[data-id="${cssq(i.id)}"]`);
        const t = fr(i.sr);
        if (b && b.textContent !== t) b.textContent = t;
      }
    }
  }

  _focusSr() {
    if (!this.srFocus) return;
    const b = this.selId != null ? this.srHost.querySelector(`button[data-id="${cssq(this.selId)}"]`) : null;
    if (b && document.activeElement !== b) b.focus({ preventScroll: true });
  }
}

// ================================================================== CRT shader (TV screen)

const CRT_VERT = /* glsl */`
varying vec2 vUv;
void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`;

const CRT_FRAG = /* glsl */`
uniform sampler2D map;
uniform vec2 texSize;
uniform float uTime, uStatic, uCollapse, uBright, uJitter;
varying vec2 vUv;
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
vec2 barrel(vec2 uv) { vec2 c = uv * 2.0 - 1.0; c *= 1.0 + 0.045 * dot(c, c); return c * 0.5 + 0.5; }
vec3 sharp(vec2 uv) {
  vec2 texel = uv * texSize;
  vec2 sc = max(vec2(1.0), 1.0 / max(fwidth(texel), vec2(1e-4)));
  vec2 fl = floor(texel), s = fract(texel), rr = 0.5 - 0.5 / sc, cd = s - 0.5;
  vec2 f = (cd - clamp(cd, -rr, rr)) * sc + 0.5;
  return texture2D(map, (fl + f) / texSize).rgb;
}
void main() {
  vec2 uv = barrel(vUv);
  float t = uTime;
  float jl = floor(uv.y * 70.0);
  uv.x += (hash(vec2(jl, floor(t * 18.0))) - 0.5) * 0.004 * uJitter + sin(uv.y * 38.0 + t * 2.7) * 0.00035;
  vec2 q = abs(uv - 0.5) - (0.5 - 0.05);
  float dmask = length(max(q, 0.0)) - 0.05;
  float mask = 1.0 - smoothstep(-0.006, 0.002, dmask);
  vec2 c = uv - 0.5;
  float sy = mix(1.0, 0.0035, smoothstep(0.0, 0.42, uCollapse));
  float sx = mix(1.0, 0.004, smoothstep(0.42, 0.78, uCollapse));
  vec2 cc = vec2(c.x / sx, c.y / sy);
  vec2 suv = cc + 0.5;
  float inside = step(abs(cc.x), 0.5) * step(abs(cc.y), 0.5);
  vec3 col = sharp(suv);
  vec2 px = vec2(1.6 / texSize.x, 0.0);
  col = col * 0.82 + 0.13 * (texture2D(map, suv + px).rgb + texture2D(map, suv - px).rgb);
  vec2 texel = suv * texSize;
  float scale = 1.0 / max(fwidth(texel.y), 1e-4);
  float sl = 0.5 + 0.5 * cos(6.28318 * (fract(texel.y) - 0.5));
  col *= 1.0 - clamp((scale - 1.3) / 2.0, 0.0, 1.0) * 0.38 * (1.0 - sl);
  float m = mod(gl_FragCoord.x, 3.0);
  vec3 msk = m < 1.0 ? vec3(1.08, 0.95, 0.95) : m < 2.0 ? vec3(0.95, 1.08, 0.95) : vec3(0.95, 0.95, 1.08);
  col *= mix(vec3(1.0), msk, clamp((scale - 1.6) / 2.0, 0.0, 1.0));
  col *= inside;
  float g = exp(-pow(c.y / (sy * 0.5 + 0.0025), 2.0)) * exp(-pow(abs(c.x) / (sx * 0.5 + 0.004), 6.0));
  col = mix(col, vec3(1.0), smoothstep(0.12, 0.42, uCollapse) * inside);
  col += vec3(g) * smoothstep(0.25, 0.45, uCollapse) * 1.4;
  col *= 1.0 - smoothstep(0.8, 1.0, uCollapse);
  float rb = fract(vUv.y * 0.55 - t * 0.075);
  col *= 1.0 + 0.07 * smoothstep(0.0, 0.06, rb) * (1.0 - smoothstep(0.06, 0.2, rb));
  float n = hash(gl_FragCoord.xy * 0.37 + fract(t * 7.3) * 91.7);
  col += (n - 0.5) * 0.045 * (1.0 - uCollapse);
  col = mix(col, vec3(n * n), clamp(uStatic, 0.0, 1.0) * (1.0 - smoothstep(0.3, 0.6, uCollapse)));
  col *= 0.985 + 0.015 * sin(t * 113.0);
  col *= 1.0 - 0.42 * pow(clamp(length(c * vec2(1.0, 1.12)) * 1.25, 0.0, 1.0), 3.0);
  vec3 glass = vec3(0.012, 0.014, 0.017) + 0.035 * smoothstep(0.55, 0.0, length(vUv - vec2(0.27, 0.8)));
  gl_FragColor = vec4(glass + max(col, 0.0) * mask * uBright, 1.0);
  #include <colorspace_fragment>
}`;

// ================================================================== CSS

const STYLE = `
#ui > .lg-root{pointer-events:none}
.lg-root{position:fixed;inset:0;pointer-events:none;color:var(--paper);font-family:var(--font-ui);-webkit-font-smoothing:antialiased;
  --sat:env(safe-area-inset-top,0px);--sar:env(safe-area-inset-right,0px);--sab:env(safe-area-inset-bottom,0px);--sal:env(safe-area-inset-left,0px);
  --pad:clamp(14px,1.6vw,32px);--white:#efece4;--ink2:#211a13;--kh:52px;--touch-clear:210px;
  --ts:0 1px 2px rgba(0,0,0,.95),0 0 10px rgba(0,0,0,.7)}
.lg-root *,.lg-root *::before,.lg-root *::after{box-sizing:border-box}
:where(.lg-root) button{font:inherit;color:inherit;-webkit-tap-highlight-color:transparent;touch-action:manipulation}
.lg-root [hidden]{display:none !important}
.lg-i{width:1em;height:1em;display:inline-block;vertical-align:-.15em;flex:none}
.lg-sr{position:absolute;left:0;top:0;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
.lg-sr button{display:block;width:1px;height:1px;padding:0;border:0}
.lg-crayon{color:var(--crayon)}
@supports ((-webkit-background-clip:text) or (background-clip:text)){
  .lg-crayon{background-color:currentColor;background-image:var(--lg-wax,none);background-size:96px 96px;-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent}
}
.lg-cap{display:inline-grid;place-items:center;min-width:24px;height:22px;padding:0 6px;border:1.3px solid rgba(239,236,228,.7);border-radius:5px;font:700 12px/1 var(--font-ui);color:var(--white);background:rgba(0,0,0,.35)}
.lg-root.is-touch .lg-act .lg-cap{display:none}

/* ---------------- TV menu pointer layer ---------------- */
.lg-tvhit{position:absolute;inset:0;z-index:0;display:none;pointer-events:auto;touch-action:none}
.lg-root.tv-on .lg-tvhit{display:block}

/* ---------------- HUD (almost nothing) ---------------- */
.lg-hud{position:absolute;inset:0;opacity:0;transition:opacity .6s;z-index:1}
.lg-root.hud-on .lg-hud{opacity:1}
.lg-obj{position:absolute;left:calc(var(--sal) + var(--pad));top:calc(var(--sat) + var(--pad));max-width:min(46vw,520px);opacity:0;transform:translateY(-4px);transition:opacity 1.2s,transform 1.2s;text-shadow:var(--ts)}
.lg-obj.is-on{opacity:.92;transform:none;transition:opacity .35s,transform .35s}
.lg-obj .lbl{display:block;margin-bottom:5px;font:700 10px/1 var(--font-ui);letter-spacing:.26em;text-transform:uppercase;color:var(--nightlight);opacity:.85}
.lg-obj .txt{font:400 clamp(13px,.35vw + 10.5px,18px)/1.35 var(--font-type);color:var(--white)}
.lg-obj .rest{visibility:hidden}
.lg-obj .caret{display:inline-block;width:0;height:1em;position:relative}
.lg-obj .caret::after{content:'';position:absolute;left:1px;bottom:-.15em;width:.45em;height:1.05em;background:var(--nightlight);opacity:.8;animation:lg-blink .7s steps(1) infinite}
.lg-obj:not(.is-typing) .caret{display:none}

.lg-center{position:absolute;left:50%;top:50%;width:0;height:0}
.lg-dot{position:absolute;left:-1.5px;top:-1.5px;width:3px;height:3px;border-radius:50%;background:#f3eee2;opacity:.32;box-shadow:0 0 0 1px rgba(0,0,0,.35);transition:opacity .15s,transform .15s}
.lg-root.has-prompt .lg-dot{opacity:.95;transform:scale(1.5)}
.lg-prompt{position:absolute;top:18px;left:0;transform:translateX(-50%);display:flex;align-items:center;gap:9px;white-space:nowrap;opacity:0;transition:opacity .15s;
  font:600 clamp(12.5px,.3vw + 10px,17px)/1.2 var(--font-ui);letter-spacing:.02em;color:var(--white);text-shadow:var(--ts)}
.lg-root.has-prompt .lg-prompt{opacity:.95}
.lg-key{position:relative;width:24px;height:24px;flex:none;display:grid;place-items:center;border:1.3px solid rgba(239,236,228,.75);border-radius:5px;background:rgba(0,0,0,.35);font:700 12px/1 var(--font-ui);text-shadow:none}
.lg-key .h{display:none;font-size:16px}
.lg-key.is-hand{border-radius:50%}
.lg-key.is-hand .k{display:none}
.lg-key.is-hand .h{display:block}
.lg-key .ring{position:absolute;left:50%;top:50%;width:38px;height:38px;transform:translate(-50%,-50%) rotate(-90deg);opacity:0;transition:opacity .15s;overflow:visible}
.lg-key .ring circle{fill:none;stroke-width:2.4;stroke-linecap:round}
.lg-key .ring .bg{stroke:rgba(240,232,214,.2)}
.lg-key .ring .fg{stroke:var(--nightlight);stroke-dasharray:100.5;stroke-dashoffset:100.5}
.lg-root.has-hold .lg-key .ring{opacity:1}
.lg-root.has-hold .lg-prompt{gap:15px}

.lg-alert{position:absolute;left:50%;top:30%;width:0;height:0;opacity:0;transition:opacity .6s;pointer-events:none}
.lg-alert.is-on{opacity:1;transition:opacity .06s}
.lg-alert span{position:absolute;left:0;top:0;display:block;white-space:nowrap;transform:translate(-50%,-50%);font:700 clamp(26px,2.6vw + 10px,60px)/1 var(--font-ui);letter-spacing:.14em;color:#fff3ee;
  text-shadow:0 0 18px rgba(255,40,20,.85),0 0 4px rgba(255,60,40,.9),0 2px 3px #000}
.lg-alert.is-anim span{animation:lg-alert-in .35s cubic-bezier(.2,1.4,.4,1) both,lg-jitter .09s steps(2) .35s 10}

.lg-batt{position:absolute;right:calc(var(--sar) + var(--pad));top:calc(var(--sat) + var(--pad));width:44px;height:3px;border-radius:2px;background:rgba(239,236,228,.16);opacity:0;transition:opacity .5s;box-shadow:0 0 4px rgba(0,0,0,.7)}
.lg-root.is-touch .lg-batt{right:calc(var(--sar) + var(--pad) + 70px);top:calc(var(--sat) + var(--pad) + 10px)}
.lg-batt i{display:block;height:100%;border-radius:2px;background:rgba(239,236,228,.8);transform-origin:0 50%;transition:transform .3s}
.lg-batt.is-on{opacity:.75}
.lg-batt.is-low i{background:#ff5a3c}
.lg-batt.is-low.is-on{animation:lg-low 1s steps(2) infinite}
.lg-stam{position:absolute;left:50%;bottom:calc(var(--sab) + clamp(64px,10vh,110px));width:clamp(90px,8vw,170px);height:2px;transform:translateX(-50%);border-radius:2px;background:rgba(239,236,228,.12);opacity:0;transition:opacity .6s;overflow:hidden}
.lg-stam i{display:block;height:100%;background:rgba(255,120,90,.85);transform-origin:0 50%}
.lg-stam.is-on{opacity:.85;transition:opacity .25s}
.lg-hidehint{position:absolute;left:50%;bottom:calc(var(--sab) + clamp(90px,14vh,160px));transform:translateX(-50%);display:none;align-items:center;gap:8px;white-space:nowrap;font:500 clamp(12.5px,.25vw + 10.5px,16px)/1.2 var(--font-ui);color:var(--white);text-shadow:var(--ts)}
.lg-hidehint .lg-i{font-size:1.3em}
.lg-root.is-hidden .lg-hidehint{display:flex;animation:lg-hint 6s ease-out forwards}
.lg-pulse{position:absolute;inset:0;z-index:2;opacity:0;pointer-events:none;background:radial-gradient(ellipse at center,transparent 42%,rgba(110,12,6,.55) 100%)}
.lg-pulse.is-on{animation:lg-pulse 1.2s ease-out}
.lg-fade{position:absolute;inset:0;z-index:3;background:#000;opacity:0;pointer-events:none;transition-property:opacity;transition-timing-function:linear}

.lg-subs{position:absolute;left:50%;bottom:calc(var(--sab) + clamp(18px,5.5vh,58px));z-index:4;transform:translateX(-50%);width:max-content;max-width:min(86vw,900px);text-align:center;pointer-events:none;opacity:0;transition:opacity .25s}
.lg-subs.is-on{opacity:1}
.lg-root.is-touch .lg-subs{max-width:min(52vw,560px);bottom:calc(var(--sab) + 12px)}
.lg-subs p{margin:0;font:400 clamp(14px,.32vw + 11px,20px)/1.4 var(--font-ui);color:#f6f2ea;text-shadow:0 1px 2px rgba(0,0,0,1),0 0 6px rgba(0,0,0,.9),0 0 16px rgba(0,0,0,.6);
  display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.lg-subs .spk{color:var(--nightlight);margin-right:.35em}
.lg-subs.is-hint p{color:#f2e3b0;font-style:italic}

/* ---------------- layers ---------------- */
.lg-layers{position:absolute;inset:0;z-index:5;pointer-events:none}
.lg-layer{position:absolute;inset:0;display:none;pointer-events:auto;opacity:0;transition:opacity .3s ease;overflow:hidden}
.lg-layer.is-open{display:block}
.lg-layer.is-shown{opacity:1}
.lg-layer:not(.is-shown){pointer-events:none}

/* full-screen CRT (loading, pause, caught, game over, win) */
.lg-crt{background:#000;display:none;align-items:center;justify-content:center}
.lg-crt.is-open{display:flex}
.lg-crt.mix{background:rgba(0,0,0,.62)}
.lg-crt.loading{z-index:40 !important;transition:opacity .9s}
.lg-crt-screen{position:relative;width:min(calc(100vw - 10px),calc((100vh - 10px) * 4 / 3));aspect-ratio:4/3;border-radius:3.2%/4.3%;overflow:hidden;
  box-shadow:0 0 0 1px #090909,0 0 70px rgba(80,120,255,.08);animation:lg-crtflick .14s steps(2) infinite}
@supports (height:100dvh){.lg-crt-screen{width:min(calc(100vw - 10px),calc((100dvh - 10px) * 4 / 3))}}
.lg-crt-screen canvas{display:block;width:100%;height:100%;cursor:default}
.lg-crt-fx{position:absolute;inset:0;pointer-events:none;
  background:repeating-linear-gradient(180deg,rgba(0,0,0,0) 0,rgba(0,0,0,0) 2px,rgba(0,0,0,.26) 3px),
  radial-gradient(ellipse at 50% 50%,rgba(0,0,0,0) 58%,rgba(0,0,0,.5) 100%),
  radial-gradient(ellipse at 26% 16%,rgba(255,255,255,.07),rgba(255,255,255,0) 42%)}
.lg-crt-fx::after{content:'';position:absolute;inset:-50%;background-image:var(--lg-noise,none);background-size:128px 128px;opacity:.045;animation:lg-grain .5s steps(5) infinite}
.lg-crt.mix .lg-crt-fx::after{opacity:.04}

/* note reader */
.lg-notelayer{background:rgba(4,3,2,.82)}
.lg-note-wrap{position:absolute;inset:calc(var(--sat) + 14px) calc(var(--sar) + 16px) calc(var(--sab) + 14px) calc(var(--sal) + 16px);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:clamp(8px,1.8vh,18px)}
.lg-note-label{margin:0;font:700 10.5px/1 var(--font-ui);letter-spacing:.24em;text-transform:uppercase;color:var(--white);opacity:.5;text-align:center}
.lg-note{position:relative;width:min(600px,100%);max-height:calc(100% - 90px);overflow:auto;overscroll-behavior:contain;touch-action:pan-y;-webkit-overflow-scrolling:touch;color:#1d2746;white-space:pre-wrap;
  box-shadow:0 30px 60px rgba(0,0,0,.65),inset 0 0 50px rgba(96,66,28,.28);animation:lg-paperin .45s cubic-bezier(.2,.9,.3,1)}
.lg-note.note{--lh:1.55em;padding:var(--lh) clamp(22px,4vw,46px) var(--lh) clamp(58px,6vw,78px);transform:rotate(-1.1deg);
  font:500 clamp(21px,.9vw + 15px,30px)/var(--lh) var(--font-hand);background-color:#e9dfc6;
  background-image:var(--lg-grain,none),linear-gradient(90deg,transparent clamp(40px,4.4vw,58px),rgba(194,65,45,.38) clamp(40px,4.4vw,58px),rgba(194,65,45,.38) calc(clamp(40px,4.4vw,58px) + 2px),transparent calc(clamp(40px,4.4vw,58px) + 2px)),
    repeating-linear-gradient(180deg,transparent 0,transparent calc(var(--lh) - 1px),rgba(70,100,150,.26) calc(var(--lh) - 1px),rgba(70,100,150,.26) var(--lh)),
    radial-gradient(circle at 88% 14%,rgba(120,85,40,.18),transparent 18%),linear-gradient(176deg,#efe6cf,#dccfae);background-attachment:local}
.lg-note.note p{margin:0}
.lg-note.note p + p{margin-top:var(--lh)}
.lg-note.child{padding:clamp(22px,4vh,40px) clamp(22px,4vw,44px);transform:rotate(1.3deg);color:#333;white-space:normal;font:700 clamp(26px,1.3vw + 18px,40px)/1.32 var(--font-hand);
  background-color:#f0ebdf;background-image:var(--lg-grain,none),radial-gradient(circle at 15% 85%,rgba(120,85,40,.12),transparent 24%),linear-gradient(170deg,#f4efe4,#e2d9c4)}
.lg-note.child p{margin:0 0 .25em}
.lg-note.child .w{display:inline-block;margin-right:.24em;white-space:pre}
.lg-note.child .lg-sun{position:absolute;right:16px;top:12px;width:clamp(44px,6vw,70px);height:auto;opacity:.85}
.lg-note.newspaper{width:min(700px,100%);padding:clamp(16px,3vh,28px) clamp(18px,3vw,34px) clamp(20px,3.4vh,34px);transform:rotate(.7deg);color:#1b1712;font:15px/1.5 Georgia,'Times New Roman',serif;
  background-color:#d2c7ab;background-image:var(--lg-grain,none),radial-gradient(circle at 80% 85%,rgba(120,85,40,.2),transparent 26%),radial-gradient(circle at 6% 10%,rgba(120,85,40,.16),transparent 18%),linear-gradient(176deg,#ddd2b6,#c4b791)}
.lg-np-mast{font:700 clamp(12px,.4vw + 10px,15px)/1 Georgia,'Times New Roman',serif;letter-spacing:.32em;text-transform:uppercase;text-align:center;padding-bottom:7px;border-bottom:3px double #1b1712;white-space:normal}
.lg-np-date{display:flex;justify-content:space-between;gap:12px;padding:4px 0 5px;border-bottom:1px solid #1b1712;font:italic 12px/1.2 Georgia,serif;white-space:normal}
.lg-np-h{margin:12px 0 10px;font:900 clamp(22px,1.3vw + 15px,36px)/1.08 Georgia,'Times New Roman',serif;letter-spacing:-.01em;white-space:normal}
.lg-np-body{columns:2 220px;column-gap:24px;column-rule:1px solid rgba(27,23,18,.25);text-align:justify;-webkit-hyphens:auto;hyphens:auto}
.lg-np-body p{margin:0 0 .7em}
.lg-np-body p:first-child::first-letter{float:left;font-size:3.2em;line-height:.82;padding:5px 7px 0 0;font-weight:700}
.lg-act{display:inline-flex;align-items:center;gap:9px;min-height:44px;padding:6px 14px;border:0;background:none;cursor:pointer;font:700 clamp(14px,.3vw + 11.5px,18px)/1 var(--font-ui);letter-spacing:.12em;text-transform:uppercase;color:var(--white);opacity:.72;text-shadow:var(--ts);transition:opacity .15s;outline:none}
.lg-act:hover,.lg-act:focus{opacity:1}
.lg-act:focus-visible{outline:2px solid var(--nightlight);outline-offset:2px;border-radius:4px}

/* keypad = the brass combination padlock itself */
.lg-kplayer{background:radial-gradient(ellipse at center,rgba(4,3,2,.6),rgba(0,0,0,.9))}
.lg-kp{position:absolute;inset:calc(var(--sat) + 12px) calc(var(--sar) + 16px) calc(var(--sab) + 12px) calc(var(--sal) + 16px);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:clamp(10px,2.2vh,20px)}
.lg-kp-side{display:flex;flex-direction:column;align-items:center;gap:10px}
.lg-kp-lockwrap{position:relative;padding-top:clamp(34px,7vh,60px);filter:drop-shadow(0 24px 30px rgba(0,0,0,.7))}
.lg-kp-shackle{position:absolute;left:50%;top:0;transform:translateX(-50%);width:60%;height:calc(clamp(34px,7vh,60px) + 26px);border:clamp(10px,1.4vh,14px) solid #a7a196;border-bottom:0;border-radius:999px 999px 0 0;
  border-color:#c9c3b4 #8d877b #8d877b #d3cdbf;box-shadow:inset 0 3px 2px rgba(255,255,255,.35)}
.lg-kp-lock{position:relative;padding:clamp(18px,3vh,28px) clamp(14px,2vw,22px) clamp(22px,4vh,36px);border-radius:16px 16px 26px 26px;
  background-color:#a07b34;background-image:var(--lg-grain,none),radial-gradient(ellipse at 28% 16%,rgba(255,238,180,.55),transparent 50%),radial-gradient(ellipse at 80% 90%,rgba(40,24,6,.5),transparent 60%),linear-gradient(160deg,#c9a04b,#8f6726 55%,#5d4219);
  box-shadow:inset 0 2px 0 rgba(255,236,180,.55),inset 0 -5px 12px rgba(0,0,0,.5),inset 0 0 0 1px rgba(60,40,10,.4)}
.lg-kp-lock::after{content:'';position:absolute;left:50%;bottom:clamp(7px,1.3vh,12px);width:16px;height:7px;transform:translateX(-50%);border-radius:50%;background:radial-gradient(#2a1a06,#5d4219);box-shadow:0 1px 0 rgba(255,236,180,.4)}
.lg-kp-stamp{position:absolute;left:0;right:0;top:clamp(5px,.9vh,9px);text-align:center;font:700 9px/1 var(--font-ui);letter-spacing:.35em;color:rgba(50,32,8,.6);text-shadow:0 1px 0 rgba(255,236,180,.35)}
.lg-kp-wheels{position:relative;display:flex;gap:clamp(5px,.8vw,10px);padding:2px clamp(6px,1vw,10px);border-radius:8px;background:linear-gradient(180deg,#140e07,#2a1d0d 50%,#140e07);box-shadow:inset 0 2px 7px rgba(0,0,0,.85),0 1px 0 rgba(255,236,180,.35)}
.lg-kp-wheels::before,.lg-kp-wheels::after{content:'';position:absolute;top:50%;width:0;height:0;border:6px solid transparent;transform:translateY(-50%)}
.lg-kp-wheels::before{left:-1px;border-left-color:var(--nightlight)}
.lg-kp-wheels::after{right:-1px;border-right-color:var(--nightlight)}
.lg-wheel{display:flex;flex-direction:column;align-items:center;outline:none;border-radius:6px}
.lg-wheel-btn{width:clamp(46px,4vw,58px);height:clamp(34px,6vh,46px);display:grid;place-items:center;background:none;border:0;cursor:pointer;color:#f3e6c2;font-size:22px;opacity:.55;transition:opacity .15s}
.lg-wheel-btn:hover,.lg-wheel-btn:focus-visible{opacity:1;outline:none}
.lg-drum{position:relative;width:clamp(46px,4vw,58px);height:calc(var(--kh) * 1.9);overflow:hidden;border-radius:5px;cursor:ns-resize;touch-action:none;
  background:linear-gradient(180deg,#2e2010 0%,#9c7836 22%,#e9cd85 48%,#f3dc98 52%,#9c7836 78%,#2e2010 100%)}
.lg-drum::before{content:'';position:absolute;inset:0;background:repeating-linear-gradient(90deg,rgba(0,0,0,.08) 0 1px,transparent 1px 4px);pointer-events:none;z-index:1}
.lg-drum::after{content:'';position:absolute;inset:0;background:linear-gradient(180deg,rgba(0,0,0,.72),transparent 30%,transparent 70%,rgba(0,0,0,.72));pointer-events:none;z-index:2}
.lg-strip{position:absolute;left:0;right:0;top:0;will-change:transform}
.lg-strip.anim{transition:transform .16s cubic-bezier(.3,.7,.4,1)}
.lg-strip span{display:block;height:var(--kh);line-height:var(--kh);text-align:center;font:700 calc(var(--kh) * .6) var(--font-type);color:#2a1b07;text-shadow:0 1px 0 rgba(255,238,185,.65),0 -1px 0 rgba(0,0,0,.25)}
.lg-wheel.is-active .lg-drum{box-shadow:0 0 0 2px var(--nightlight),0 0 14px rgba(232,198,106,.4)}
.lg-wheel.is-active .lg-wheel-btn{opacity:.95}
.lg-kp-scrap{display:flex;gap:14px;padding:6px 14px 8px;transform:rotate(-1.5deg);font:700 22px/1 var(--font-hand);color:#2a2a48;background-color:#e6dcc2;background-image:var(--lg-grain,none);box-shadow:0 8px 18px rgba(0,0,0,.5)}
.lg-kp-scrap span{display:flex;align-items:baseline;gap:4px}
.lg-kp-scrap small{font:600 15px/1 var(--font-hand);opacity:.7}
.lg-kp-scrap .unk{opacity:.4}
.lg-kp-actions{display:flex;gap:clamp(6px,2vw,24px)}
.lg-kp-help{margin:0;font:12.5px/1.4 var(--font-ui);color:var(--white);opacity:.5;text-align:center;max-width:46ch}
.lg-kp.is-shake .lg-kp-lockwrap{animation:lg-shake .4s}

/* portrait-phone hint */
.lg-rotate{position:absolute;inset:0;z-index:60;display:none;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:24px;text-align:center;background:#000;pointer-events:auto}
@media (orientation:portrait) and (pointer:coarse){.lg-root:not(.rot-ok) .lg-rotate{display:flex}}
.lg-rotate .big{font-size:68px;color:#40ecff;animation:lg-rot 2.6s ease-in-out infinite}
.lg-rotate h2{margin:0;padding:4px 10px;font:700 22px/1.2 var(--font-ui);letter-spacing:.08em;text-transform:uppercase;color:#000;background:#ffe63c}
.lg-rotate p{margin:0;font:600 15px/1.45 var(--font-ui);color:#f4f2ea;opacity:.8;max-width:30ch}

@media (max-height:520px) and (orientation:landscape){
  .lg-root{--kh:38px}
  .lg-kp{flex-direction:row;gap:clamp(20px,4vw,48px)}
  .lg-note{max-height:calc(100% - 56px)}
  .lg-note-wrap{gap:6px}
  .lg-note-label{display:none}
}
@media (min-width:1800px){ .lg-root{--kh:64px} }

@keyframes lg-blink{50%{opacity:0}}
@keyframes lg-alert-in{0%{opacity:0;transform:translate(-50%,-50%) scale(1.5)}100%{opacity:1;transform:translate(-50%,-50%) scale(1)}}
@keyframes lg-jitter{0%{transform:translate(-50%,-50%)}50%{transform:translate(calc(-50% + 2px),calc(-50% - 1px))}100%{transform:translate(calc(-50% - 1px),calc(-50% + 1px))}}
@keyframes lg-pulse{0%{opacity:0}14%{opacity:1}100%{opacity:0}}
@keyframes lg-rot{0%,18%{transform:rotate(0)}46%,72%{transform:rotate(-90deg)}100%{transform:rotate(0)}}
@keyframes lg-hint{0%{opacity:0}8%{opacity:.9}60%{opacity:.9}100%{opacity:.3}}
@keyframes lg-low{50%{opacity:.25}}
@keyframes lg-paperin{from{opacity:0;transform:translateY(18px) rotate(-3deg) scale(.97)}}
@keyframes lg-shake{0%,100%{transform:none}20%{transform:translateX(-8px)}40%{transform:translateX(7px)}60%{transform:translateX(-5px)}80%{transform:translateX(3px)}}
@keyframes lg-crtflick{0%{opacity:1}100%{opacity:.985}}
@keyframes lg-grain{0%{transform:translate(0,0)}20%{transform:translate(-12%,7%)}40%{transform:translate(9%,-11%)}60%{transform:translate(-6%,-4%)}80%{transform:translate(13%,10%)}100%{transform:translate(0,0)}}
`;

// ================================================================== UI

const DEG = Math.PI / 180;
const MENU_FOV = 30;
// television_02 glass (model space, measured from the GLB): centre 0.256 m above the model base, ~0.30 × 0.225 m,
// spherical bulge peaking at z ≈ 0.121 m.
const TV_GLASS = { y: 0.256, hw: 0.148, hh: 0.111, zc: 0.1228, k: 0.8 };

export class UI {
  constructor(game, root) {
    this.game = game;
    this.root = root;
    this._modal = false;
    this._layers = [];
    this._guardUntil = 0;
    this._obj = { text: '', shown: 0, n: -1, delay: 0, typing: false, hideAt: 0 };
    this._subUntil = 0;
    this._subCritical = false;
    this._alertUntil = 0;
    this._promptRaw = null;
    this._promptHold = -2;
    this._promptKey = '';
    this._battery = null;
    this._flashOn = null;
    this._stamina = 1;
    this._night = 1;
    this._nightsTotal = 3;
    this._items = [];
    this._notes = null;
    this._clues = null;
    this._hidden = false;
    this._isTouch = false;
    this._kp = null;
    this._noteResolve = null;
    this._noteOpenedAt = 0;
    this._pause = null;
    this._end = null;
    this._waiters = [];
    this._combo = [0, 0, 0, 0];
    this._keyLabels = null;
    this._loading = { p: 0, text: 'Initialisation…', hidden: false };
    this._tip = TIPS[Math.floor(Math.random() * TIPS.length)];
    this._tv = null;
    this._tvOn = false;
    this._tvTrans = null;
    this._tvHum = null;
    this._tvLightMode = null;
    this._audioUnlocked = false;
    this._fadeSeq = 0;
    this._optSub = 0;
    this._ctlSub = -1;
    this._camFrame = -1;
    this._camMiss = 0;
    this._camHooked = false;
    // scratch objects (no per-frame allocations)
    this._v1 = new THREE.Vector3();
    this._v2 = new THREE.Vector3();
    this._ndc = new THREE.Vector2();
    this._ray = new THREE.Raycaster();
  }

  // ================================================================ init

  init() {
    if (!document.getElementById('lg-ui-style')) {
      const st = document.createElement('style');
      st.id = 'lg-ui-style';
      st.textContent = STYLE;
      document.head.appendChild(st);
    }
    const r = (this.el = document.createElement('div'));
    r.className = 'lg-root';
    this.root.appendChild(r);
    try {
      r.style.setProperty('--lg-grain', `url(${makeGrain()})`);
      r.style.setProperty('--lg-wax', `url(${makeWax('238,232,214')})`);
      r.style.setProperty('--lg-noise', `url(${makeNoise()})`);
    } catch (_) { /* canvas unavailable */ }

    this._buildTvHit();
    this._buildHud();
    this._layersEl = h('<div class="lg-layers"></div>');
    r.appendChild(this._layersEl);
    this._buildCrt();
    this._buildNote();
    this._buildKeypad();
    this._buildRotate();
    this._wire();
    this._syncTouch();
    this._loadKeyLabels();
    this._ovOpen('loading');
    // redraw teletext pages once the webfont is available
    const redraw = () => {
      for (const d of [this._crt, this._tv]) if (d) { d.tt.clearMetrics(); d.screen.dirty = true; }
      if (this._crt?.open) this._crt.screen.draw();
    };
    try {
      document.fonts?.load?.('700 20px "Atkinson Hyperlegible"').then(redraw, () => {});
      document.fonts?.ready?.then(redraw);
    } catch (_) { /* ignore */ }
  }

  _wire() {
    const ev = this.game.events;
    ev.on('game:state', ({ state }) => this._onState(state));
    ev.on('inventory:changed', (p) => this.setInventory(p?.items || [], p?.notes));
    ev.on('player:flashlight', (p) => {
      if (!p) return;
      this._flashOn = !!(p.has && p.on);
      this.setBattery(p.has ? (Number(p.battery) || 0) / 100 : null);
    });
    ev.on('player:stamina', (p) => this.setStamina(p?.value ?? 1));
    ev.on('player:hide', (p) => this.setHidden(!!p?.hidden));
    ev.on('entity:spotted', () => this._pulseSpotted());
    ev.on('settings:changed', ({ key, value }) => {
      if (key === 'subtitles' && value === false && !this._subCritical) this._hideSub();
      if (this._tv) this._tv.screen.dirty = true;
      if (this._crt) this._crt.screen.dirty = true;
    });
    ev.on('quality:changed', () => { if (this._tv) this._tv.screen.dirty = true; if (this._crt) this._crt.screen.dirty = true; });
    window.addEventListener('keydown', (e) => this._onKeyDown(e), true);
    document.addEventListener('fullscreenchange', () => { if (this._tv) this._tv.screen.dirty = true; if (this._crt) this._crt.screen.dirty = true; });
  }

  _syncTouch() {
    const t = !!this.game.input?.isTouch;
    this._isTouch = t;
    this.el.classList.toggle('is-touch', t);
    if (this._hideHintText) this._hideHintText.textContent = t ? 'Caché. Touche la main pour sortir.' : `Caché. Appuie sur ${this._eLabel()} pour sortir.`;
  }

  _eLabel() { return this._keyLabels?.E && this._keyLabels.E.length === 1 ? this._keyLabels.E : 'E'; }

  _onState(s) {
    this._syncTouch();
    this.el.classList.toggle('hud-on', s === 'playing');
    if (s === 'playing') {
      this._hideLoading();
      if (this._tvOn) this._tvDeactivate();
    }
    if (s !== 'playing') this.setPrompt(null);
    if (s === 'caught' || s === 'gameover' || s === 'won') this._hideSub();
  }

  _clockMinutes() { return 3 * 60 + 7 + Math.floor((this.game.realTime || 0) / 60); }

  _sfx(kind) {
    const a = this.game.audio;
    if (!a?.play) return;
    try {
      if (kind === 'select') a.play('flashlight_click', { volume: 0.22, rate: 1.25 });
      else if (kind === 'value') a.play('lock_wheel', { volume: 0.35, rate: 1.1 });
      else if (kind === 'page') a.play('tv_on', { volume: 0.22, rate: 1.15 });
      else if (kind === 'off') a.play('tv_off', { volume: 0.55 });
    } catch (_) { /* ignore */ }
  }

  _unlockAudio() {
    if (this._audioUnlocked) return;
    this._audioUnlocked = true;
    try { this.game.audio?.unlock?.(); } catch (_) { /* ignore */ }
    if (this._tvOn && this._tv && !this._tvHum) {
      try { this._tvHum = this.game.audio?.loop?.('tv_static', { position: this._tv.center, volume: 0.045 }) || null; } catch (_) { this._tvHum = null; }
    }
  }

  // ================================================================ per-frame

  update(dt) {
    const t = now();
    this._updAt = t;
    const o = this._obj;
    if (o.delay > 0) {
      o.delay -= dt;
      if (o.delay <= 0) this._startTyping();
    } else if (o.typing) {
      o.shown += dt * 40;
      const len = o.text.length;
      const n = Math.min(len, Math.floor(o.shown));
      if (n !== o.n) {
        o.n = n;
        this._objTyped.textContent = o.text.slice(0, n);
        this._objRest.textContent = o.text.slice(n);
        if (n >= len) { o.typing = false; this._objEl.classList.remove('is-typing'); o.hideAt = t + 6500; }
      }
    } else if (o.hideAt && t > o.hideAt) { o.hideAt = 0; this._objEl.classList.remove('is-on'); }
    if (this._subUntil && t > this._subUntil) this._hideSub();
    if (this._alertUntil && t > this._alertUntil) { this._alertUntil = 0; this._alertEl.classList.remove('is-on'); }

    const tv = this._tv;
    if (tv && tv.mesh.visible) {
      // self-healing: if Game.js does not call updateMenuCamera(), hook the idle camera once
      if (this.menuCameraActive && this._camFrame !== this.game.realTime) { if (++this._camMiss > 2) this._hookIdleCamera(); }
      else this._camMiss = 0;
      const scr = tv.screen;
      scr.tick(dt);
      if (scr.dirty) scr.draw();
      const u = tv.mat.uniforms;
      u.uTime.value += dt;
      if (this._tvTrans) this._tvTransStep(dt);
      else {
        u.uStatic.value = 0.025 + scr.flick * 0.22;
        u.uJitter.value = 0.2 + scr.flick * 1.1;
      }
    }
    const crt = this._crt;
    if (crt && crt.open) {
      const scr = crt.screen;
      scr.tick(dt);
      if (crt.mode === 'end' && this._end && !this._end.ready && t >= this._end.readyAt) { this._end.ready = true; scr.dirty = true; }
      if (scr.dirty) scr.draw();
    }
  }

  // ================================================================ HUD

  _buildHud() {
    const hud = h(`<div class="lg-hud">
      <div class="lg-obj" aria-live="polite"><span class="lbl">Objectif</span><span class="txt"><span class="typed"></span><span class="caret"></span><span class="rest"></span></span></div>
      <div class="lg-center">
        <span class="lg-dot"></span>
        <div class="lg-prompt">
          <span class="lg-key"><svg class="ring" viewBox="0 0 38 38" aria-hidden="true"><circle class="bg" cx="19" cy="19" r="16"/><circle class="fg" cx="19" cy="19" r="16"/></svg><span class="k">E</span><span class="h">${icon('hand')}</span></span>
          <span class="txt"></span>
        </div>
      </div>
      <div class="lg-alert" role="alert"><span></span></div>
      <div class="lg-batt" title="Pile"><i></i></div>
      <div class="lg-stam"><i></i></div>
      <div class="lg-hidehint">${icon('eyeClosed')}<span></span></div>
    </div>`);
    this.el.appendChild(hud);
    this._pulseEl = h('<div class="lg-pulse"></div>');
    this._fade = h('<div class="lg-fade"></div>');
    this._subsEl = h('<div class="lg-subs" aria-live="polite"><p><span class="spk"></span><span class="t"></span></p></div>');
    this.el.append(this._pulseEl, this._fade, this._subsEl);
    const q = (s) => hud.querySelector(s);
    this._hud = hud;
    this._objEl = q('.lg-obj');
    this._objTyped = q('.lg-obj .typed');
    this._objRest = q('.lg-obj .rest');
    this._promptText = q('.lg-prompt .txt');
    this._keyEl = q('.lg-key');
    this._keyK = q('.lg-key .k');
    this._ringFg = q('.lg-key .ring .fg');
    this._alertEl = q('.lg-alert');
    this._alertText = q('.lg-alert span');
    this._battEl = q('.lg-batt');
    this._battBar = q('.lg-batt i');
    this._stamEl = q('.lg-stam');
    this._stamBar = q('.lg-stam i');
    this._hideHintText = q('.lg-hidehint span');
    this._subSpk = this._subsEl.querySelector('.spk');
    this._subText = this._subsEl.querySelector('.t');
  }

  setPrompt(text, opts) {
    const raw = text || null;
    if (raw !== this._promptRaw) {
      this._promptRaw = raw;
      if (raw) this._promptText.textContent = fr(raw);
      this.el.classList.toggle('has-prompt', !!raw);
    }
    if (raw) {
      const hand = !!(opts && (opts.key === '✋' || opts.touch)) || (!(opts && opts.key) && this._isTouch);
      const key = hand ? '✋' : String((opts && opts.key) || this._eLabel());
      if (key !== this._promptKey) {
        this._promptKey = key;
        this._keyEl.classList.toggle('is-hand', hand);
        if (!hand) this._keyK.textContent = key;
      }
    }
    let hold = -1;
    if (raw && opts && typeof opts.hold === 'number') hold = clamp01(opts.hold);
    if (hold !== this._promptHold) {
      if ((hold >= 0) !== (this._promptHold >= 0)) this.el.classList.toggle('has-hold', hold >= 0);
      this._promptHold = hold;
      if (hold >= 0) this._ringFg.style.strokeDashoffset = (100.5 * (1 - hold)).toFixed(1);
    }
  }

  subtitle(text, seconds = 3.5, opts = {}) {
    if (!text) { this._hideSub(); return; }
    const critical = !!(opts && (opts.critical || opts.force));
    if (!critical && this.game.settings?.get?.('subtitles') === false) return;
    this._subCritical = critical;
    const spk = opts && opts.speaker ? `${fr(opts.speaker)}${NBSP}:` : '';
    this._subSpk.textContent = spk;
    this._subSpk.hidden = !spk;
    this._subText.textContent = fr(text);
    this._subsEl.classList.toggle('is-hint', !!(opts && opts.hint));
    this._subsEl.classList.add('is-on');
    this._subUntil = now() + Math.max(0.8, Number(seconds) || 3.5) * 1000;
  }

  _hideSub() {
    this._subUntil = 0;
    this._subCritical = false;
    this._subsEl.classList.remove('is-on');
  }

  setObjective(text) {
    const t = fr(text || '');
    const o = this._obj;
    if (t === o.text) return;
    o.text = t;
    o.typing = false;
    o.hideAt = 0;
    if (!t) { o.delay = 0; this._objEl.classList.remove('is-on', 'is-typing'); return; }
    const wasOn = this._objEl.classList.contains('is-on');
    this._objEl.classList.remove('is-on');
    o.delay = wasOn ? 0.5 : 0.05;
    if (this._crt?.open && this._crt.mode === 'pause') this._crt.screen.dirty = true;
  }

  _startTyping() {
    const o = this._obj;
    o.delay = 0; o.shown = 0; o.n = 0; o.typing = true;
    this._objTyped.textContent = '';
    this._objRest.textContent = o.text;
    this._objEl.classList.add('is-on', 'is-typing');
  }

  /** Re-show the current objective for a few seconds (Tab). */
  _peekObjective(sec = 4) {
    const o = this._obj;
    if (!o.text || o.typing || o.delay > 0) return;
    this._objTyped.textContent = o.text;
    this._objRest.textContent = '';
    this._objEl.classList.add('is-on');
    o.hideAt = now() + sec * 1000;
  }

  alert(text, seconds = 2) {
    const el = this._alertEl;
    this._alertText.textContent = up(text || '');
    el.classList.remove('is-anim');
    void el.offsetWidth;
    el.classList.add('is-on', 'is-anim');
    this._alertUntil = now() + Math.max(0.5, Number(seconds) || 2) * 1000;
  }

  setInventory(items, notes) {
    this._items = Array.isArray(items) ? items.filter((it) => it && (it.count ?? 1) > 0) : [];
    if (Array.isArray(notes)) this._notes = notes;
    if (this._crt?.open && this._crt.mode === 'pause') this._crt.screen.dirty = true;
  }

  setBattery(v) {
    if (v === null || v === undefined || Number.isNaN(Number(v))) { this._battery = null; this._battEl.classList.remove('is-on'); return; }
    v = clamp01(Number(v));
    this._battery = v;
    this._battBar.style.transform = `scaleX(${v.toFixed(3)})`;
    this._battEl.classList.toggle('is-low', v < 0.15);
    this._battEl.classList.toggle('is-on', this._flashOn !== false);
  }

  setStamina(v) {
    v = clamp01(Number(v));
    if (Number.isNaN(v) || Math.abs(v - this._stamina) < 0.004) return;
    this._stamina = v;
    this._stamBar.style.transform = `scaleX(${v.toFixed(3)})`;
    if (v < 0.3) this._stamEl.classList.add('is-on');
    else if (v > 0.5) this._stamEl.classList.remove('is-on');
  }

  setNight(night, total) {
    this._night = Math.max(1, Number(night) || 1);
    this._nightsTotal = Math.max(1, Number(total) || 3);
  }

  setClues(found = {}) {
    const f = found || {};
    const norm = (v) => (v === null || v === undefined || v === '' ? null : String(v));
    this._clues = { duck: norm(f.duck), horse: norm(f.horse), clock: norm(f.clock), tv: norm(f.tv) };
    if (this._kp) this._renderKpScrap();
    if (this._crt?.open && this._crt.mode === 'pause') this._crt.screen.dirty = true;
  }

  setHidden(b) {
    b = !!b;
    if (b === this._hidden) return;
    this._hidden = b;
    this._syncTouch();
    this.el.classList.toggle('is-hidden', b);
  }

  _pulseSpotted() {
    if (this.game.state !== 'playing') return;
    const el = this._pulseEl;
    el.classList.remove('is-on');
    void el.offsetWidth;
    el.classList.add('is-on');
  }

  fadeTo(alpha, seconds = 1) {
    this._fadeSeq++;
    const el = this._fade;
    const a = clamp01(Number(alpha) || 0);
    const s = Math.max(0, Number(seconds) || 0);
    if (s === 0) {
      el.style.transitionDuration = '0s';
      el.style.opacity = String(a);
      void el.offsetWidth;
      return Promise.resolve();
    }
    void el.offsetWidth;
    el.style.transitionDuration = `${s}s`;
    el.style.opacity = String(a);
    return new Promise((res) => setTimeout(res, s * 1000 + 30));
  }

  // ================================================================ layer stack

  _layer(cls, html) {
    const el = h(`<div class="lg-layer ${cls}" aria-hidden="true">${html}</div>`);
    this._layersEl.appendChild(el);
    const stop = (e) => e.stopPropagation();
    for (const t of ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'touchstart', 'touchmove', 'touchend', 'wheel', 'contextmenu']) el.addEventListener(t, stop, { passive: true });
    return el;
  }

  _open(el, { modal = true, onKey = null, focus = null } = {}) {
    if (this._layers.some((l) => l.el === el)) return null;
    const L = { el, modal, onKey, prevFocus: document.activeElement };
    this._layers.push(L);
    if (!el.classList.contains('loading')) el.style.zIndex = String(10 + this._layers.length);
    else el.style.zIndex = '';
    clearTimeout(el._hideT);
    el.classList.add('is-open');
    el.setAttribute('aria-hidden', 'false');
    void el.offsetWidth;
    el.classList.add('is-shown');
    this._syncModal();
    if (focus) {
      requestAnimationFrame(() => {
        const f = typeof focus === 'function' ? focus() : typeof focus === 'string' ? el.querySelector(focus) : focus;
        if (f && this._layers.includes(L)) f.focus?.({ preventScroll: true });
      });
    }
    return L;
  }

  _close(el, { restoreFocus = true, delay = 320 } = {}) {
    const i = this._layers.findIndex((l) => l.el === el);
    if (i < 0) return;
    const [L] = this._layers.splice(i, 1);
    el.classList.remove('is-shown');
    el.setAttribute('aria-hidden', 'true');
    clearTimeout(el._hideT);
    el._hideT = setTimeout(() => el.classList.remove('is-open'), delay);
    if (el.contains(document.activeElement)) document.activeElement.blur();
    this._syncModal();
    if (!restoreFocus) return;
    const top = this._layers[this._layers.length - 1];
    if (top) {
      if (top.el === this._crt?.el) this._crt.screen._focusSr();
      else if (L.prevFocus && top.el.contains(L.prevFocus) && visible(L.prevFocus)) L.prevFocus.focus({ preventScroll: true });
    } else if (this._tvOn && this._tv) this._tv.screen._focusSr();
    else { try { this.game.canvas?.focus?.({ preventScroll: true }); } catch (_) { /* ignore */ } }
  }

  _syncModal() {
    const m = this._layers.some((l) => l.modal);
    if (!m && this._modal) this._guardUntil = now() + 200;
    this._modal = m;
  }

  isModalOpen() { return this._modal || now() < this._guardUntil; }

  _top() { return this._layers[this._layers.length - 1] || null; }

  _onKeyDown(e) {
    const top = this._top();
    if (top && top.modal) {
      if (e.key === 'Tab') { this._trapTab(e, top.el); e.preventDefault(); e.stopImmediatePropagation(); return; }
      if (top.onKey && top.onKey(e) === true) { e.preventDefault(); e.stopImmediatePropagation(); }
      return;
    }
    if (this._tvOn && this._tv && this.game.state === 'menu') {
      this._unlockAudio();
      if (e.key === 'Tab') return; // native focus walks the hidden buttons (selection follows)
      if (this._tvTrans || this._tv.screen.key(e)) { e.preventDefault(); e.stopImmediatePropagation(); }
      return;
    }
    if (this.game.state === 'playing' && e.code === 'Tab') {
      e.preventDefault(); // keep focus on the game canvas (Input still sees the key)
      if (!e.repeat) this._peekObjective(4);
    }
  }

  _trapTab(e, root) {
    const f = [...root.querySelectorAll('button, input, [tabindex]:not([tabindex="-1"])')].filter((x) => !x.disabled && visible(x) && x.tabIndex >= 0);
    if (!f.length) return;
    const i = f.indexOf(document.activeElement);
    const n = e.shiftKey ? (i <= 0 ? f.length - 1 : i - 1) : (i < 0 || i === f.length - 1 ? 0 : i + 1);
    f[n].focus({ preventScroll: true });
  }

  // ================================================================ TV menu (3D)

  get menuCameraActive() {
    const s = this.game.state;
    return !!(this._tv && this._tvOn && (s === 'menu' || s === 'loading'));
  }

  _buildTvHit() {
    const el = (this._tvHit = h('<div class="lg-tvhit" aria-hidden="true"></div>'));
    this._tvSr = h('<div class="lg-sr" role="menu" aria-label="Menu principal (télétexte)" hidden></div>');
    this.el.append(el, this._tvSr);
    let down = null;
    el.addEventListener('pointerdown', (e) => {
      this._unlockAudio();
      down = { x: e.clientX, y: e.clientY, id: e.pointerId };
      if (e.pointerType !== 'mouse' && !this._tvTrans) { const hit = this._tvPick(e.clientX, e.clientY); if (hit) this._tv.screen.select(hit.it.id); }
    });
    el.addEventListener('pointermove', (e) => {
      if (e.pointerType !== 'mouse' || this._tvTrans || !this._tv) return;
      const hit = this._tvPick(e.clientX, e.clientY);
      el.style.cursor = hit ? 'pointer' : 'default';
      if (hit) this._tv.screen.select(hit.it.id);
    });
    el.addEventListener('pointerup', (e) => {
      if (!down || down.id !== e.pointerId) return;
      const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
      down = null;
      if (moved > 14 || this._tvTrans || !this._tv) return;
      const hit = this._tvPick(e.clientX, e.clientY);
      if (!hit) return;
      const scr = this._tv.screen;
      scr.select(hit.it.id, false);
      if (hit.it.change && !hit.side) { if (e.pointerType === 'mouse') scr.activate(1); return; } // touch on a label: select only
      scr.activate(hit.side);
    });
    el.addEventListener('wheel', (e) => {
      e.preventDefault();
      if (this._tvTrans || !this._tv) return;
      this._wheelAcc = (this._wheelAcc || 0) + (e.deltaMode === 1 ? e.deltaY * 33 : e.deltaY);
      if (Math.abs(this._wheelAcc) >= 60) { this._tv.screen.move(this._wheelAcc > 0 ? 1 : -1); this._wheelAcc = 0; }
    }, { passive: false });
  }

  /** Locate the TV glass: the television_02 mesh (found by its bounding box) gives the model-space frame. */
  _tvFrame() {
    const scene = this.game.scene;
    scene.updateMatrixWorld(true);
    const size = this._v1;
    let found = null;
    const test = (o) => {
      if (found || !o.isMesh || !o.geometry?.attributes?.position) return;
      const g = o.geometry;
      if (!g.boundingBox) g.computeBoundingBox();
      g.boundingBox.getSize(size);
      if (Math.abs(size.x - 0.4) < 0.03 && Math.abs(size.y - 0.411) < 0.03 && Math.abs(size.z - 0.35) < 0.03) found = o;
    };
    this.game.world?.tv?.object?.traverse?.(test);
    if (!found) scene.traverse(test);
    const m = new THREE.Matrix4();
    let ox = -0.002, oy = 0;
    if (found) {
      m.copy(found.matrixWorld);
      const bb = found.geometry.boundingBox;
      ox = (bb.min.x + bb.max.x) / 2;
      oy = bb.min.y;
    } else {
      const p = LAYOUT.PROPS?.tv;
      if (p) m.compose(new THREE.Vector3().fromArray(p.pos), new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), p.rotY || 0), new THREE.Vector3(1, 1, 1).multiplyScalar(p.scale || 1));
      else {
        const sp = this.game.world?.tv?.screenPosition;
        m.makeTranslation(sp ? sp.x : -0.55, sp ? sp.y - TV_GLASS.y : 1.212, sp ? sp.z - TV_GLASS.zc : -2.5);
      }
    }
    return { m, ox, oy, found: !!found };
  }

  _ensureTv() {
    if (this._tv) return this._tv;
    const scene = this.game.scene;
    if (!scene) return null;
    const tt = new Teletext(32, 13, 14, 26, 16, 11);
    const tex = new THREE.CanvasTexture(tt.canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.minFilter = THREE.LinearFilter;
    tex.magFilter = THREE.LinearFilter;
    tex.generateMipmaps = false;
    const mat = new THREE.ShaderMaterial({
      uniforms: {
        map: { value: tex }, texSize: { value: new THREE.Vector2(tt.W, tt.H) }, uTime: { value: 0 },
        uStatic: { value: 0.05 }, uCollapse: { value: 0 }, uBright: { value: 1.55 }, uJitter: { value: 0.4 },
      },
      vertexShader: CRT_VERT,
      fragmentShader: CRT_FRAG,
      toneMapped: false,
      // drawn last and without depth test: the props module may have its own (static) screen plane on the glass;
      // the menu camera always faces the TV, so nothing else can be in front of it.
      depthTest: false,
      depthWrite: false,
    });
    const fr0 = this._tvFrame();
    const G = TV_GLASS;
    const geo = new THREE.PlaneGeometry(G.hw * 2, G.hh * 2, 24, 18);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), y = pos.getY(i);
      pos.setXYZ(i, x + fr0.ox, y + fr0.oy + G.y, G.zc - G.k * (x * x + y * y));
    }
    geo.computeVertexNormals();
    geo.computeBoundingSphere();
    const mesh = new THREE.Mesh(geo, mat);
    mesh.name = 'ui.tvMenu';
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(fr0.m);
    mesh.visible = false;
    mesh.renderOrder = 50;
    mesh.frustumCulled = false;
    scene.add(mesh);
    mesh.updateMatrixWorld(true);
    const center = new THREE.Vector3(fr0.ox, fr0.oy + G.y, G.zc).applyMatrix4(fr0.m);
    const nrm = new THREE.Vector3(0, 0, 1).transformDirection(fr0.m);
    const upv = new THREE.Vector3(0, 1, 0).transformDirection(fr0.m);
    const right = new THREE.Vector3().crossVectors(upv, nrm).normalize();
    const sc = new THREE.Vector3().setFromMatrixScale(fr0.m);
    const screen = new TTScreen(this, tt, this._tvSr);
    screen.home = 'main';
    screen.onDrawn = () => { tex.needsUpdate = true; };
    this._tv = { tt, tex, mat, mesh, screen, center, nrm, up: upv, right, glassW: G.hw * 2 * sc.x, glassH: G.hh * 2 * sc.y, t: 0, found: fr0.found };
    this._goto(screen, 'main', null, false);
    return this._tv;
  }

  _tvActivate() {
    const tv = this._ensureTv();
    if (!tv) return;
    if (!this._tvOn) {
      this._tvOn = true;
      tv.mesh.visible = true;
      tv.mat.uniforms.uCollapse.value = 0;
      this.el.classList.add('tv-on');
      this._tvSr.hidden = false;
      const L = this.game.world?.lighting;
      this._tvLightMode = null;
      try {
        if (typeof L?.setTVLight === 'function') { L.setTVLight(true, 1); this._tvLightMode = 'light'; }
        else if (typeof this.game.world?.tv?.setOn === 'function' && !this.game.world.tv.isOn) { this.game.world.tv.setOn(true); this._tvLightMode = 'tv'; }
      } catch (e) { console.warn('[ui] tv light', e); }
    }
    tv.screen.srFocus = true;
  }

  _tvDeactivate() {
    const tv = this._tv;
    this._tvOn = false;
    this._tvTrans = null;
    this.el.classList.remove('tv-on');
    if (!tv) return;
    tv.mesh.visible = false;
    tv.screen.srFocus = false;
    tv.screen.locked = false;
    this._tvSr.hidden = true;
    if (tv.screen.srHost.contains(document.activeElement)) document.activeElement.blur();
    try {
      if (this._tvLightMode === 'light') { if (!this.game.world?.tv?.isOn) this.game.world?.lighting?.setTVLight?.(false, 0); }
      else if (this._tvLightMode === 'tv') this.game.world?.tv?.setOn?.(false);
    } catch (e) { console.warn('[ui] tv light', e); }
    this._tvLightMode = null;
    try { this._tvHum?.stop?.(0.4); } catch (_) { /* ignore */ }
    this._tvHum = null;
    const cam = this.game.camera;
    const fov = Number(this.game.settings?.get?.('fov')) || 70;
    if (cam && cam.fov !== fov) { cam.fov = fov; cam.updateProjectionMatrix(); }
  }

  /** Writes game.camera while the TV menu is shown (call it instead of player.updateIdleCamera). */
  updateMenuCamera(dt = 0) {
    const tv = this._tv;
    const cam = this.game.camera;
    if (!tv || !cam) return;
    const frame = this.game.realTime;
    if (frame !== this._camFrame) { this._camFrame = frame; tv.t += dt; }
    if (cam.fov !== MENU_FOV) { cam.fov = MENU_FOV; cam.updateProjectionMatrix(); }
    const asp = cam.aspect || 16 / 9;
    // glass height fraction: teletext rows of ~22 CSS px (13 rows), clamped (big screens keep the room visible)
    const frac = clamp((13 * 22) / (window.innerHeight || 720), 0.34, 0.74);
    let H = tv.glassH / frac;
    H = Math.max(H, tv.glassW / (0.86 * asp), (tv.glassW * 1.42) / (0.98 * asp));
    let d = H / (2 * Math.tan((MENU_FOV * DEG) / 2));
    const tr = this._tvTrans;
    if (tr) d *= 1 - 0.14 * smooth(0, 1, tr.t / tr.dur);
    const mm = this.game.settings?.get?.('cameraMotion');
    const m = clamp01(mm === undefined || mm === null ? 1 : Number(mm));
    const t = tv.t;
    const dx = (Math.sin(t * 0.31) * 0.6 + Math.sin(t * 0.77 + 1.3) * 0.4) * 0.012 * m;
    const dy = (Math.sin(t * 0.23 + 0.7) * 0.6 + Math.sin(t * 0.61) * 0.4) * 0.008 * m + Math.sin(t * 1.15) * 0.0025 * m;
    const p = this._v1.copy(tv.center).addScaledVector(tv.nrm, d).addScaledVector(tv.right, 0.085 * d + dx).addScaledVector(tv.up, -0.06 * d + dy);
    cam.position.copy(p);
    const tg = this._v2.copy(tv.center).addScaledVector(tv.right, Math.sin(t * 0.17) * 0.004 * m).addScaledVector(tv.up, Math.cos(t * 0.13) * 0.003 * m - 0.004);
    cam.up.set(0, 1, 0);
    cam.lookAt(tg);
    cam.rotateZ(Math.sin(t * 0.29) * 0.006 * m - 0.004);
  }

  /** Fallback when Game.js was not wired: route player.updateIdleCamera to the menu camera while it is active. */
  _hookIdleCamera() {
    const p = this.game.player;
    if (this._camHooked || !p) return;
    this._camHooked = true;
    const orig = typeof p.updateIdleCamera === 'function' ? p.updateIdleCamera.bind(p) : null;
    p.updateIdleCamera = (dt) => (this.menuCameraActive ? this.updateMenuCamera(dt) : orig?.(dt));
    console.info('[ui] Game.js does not call ui.updateMenuCamera(): using the player.updateIdleCamera fallback hook');
  }

  _tvPick(cx, cy) {
    const tv = this._tv;
    if (!tv || !tv.mesh.visible) return null;
    const cam = this.game.camera;
    const r = this.game.canvas?.getBoundingClientRect?.() || { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
    this._ndc.set(((cx - r.left) / r.width) * 2 - 1, -((cy - r.top) / r.height) * 2 + 1);
    cam.updateMatrixWorld();
    this._ray.setFromCamera(this._ndc, cam);
    const hit = this._ray.intersectObject(tv.mesh, false)[0];
    if (!hit || !hit.uv) return null;
    let x = hit.uv.x * 2 - 1, y = hit.uv.y * 2 - 1;
    const f = 1 + 0.045 * (x * x + y * y);
    x = x * f * 0.5 + 0.5; y = y * f * 0.5 + 0.5;
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    return tv.screen.hit(x, 1 - y);
  }

  /** "Nouvelle partie": static burst + CRT power-off collapse, fade to black, then ui:start. */
  _tvStartGame() {
    if (this._tvTrans || !this._tv) return;
    this._unlockAudio();
    this._tvTrans = { t: 0, dur: 1.2, faded: false, done: false, last: now() };
    this._tv.screen.locked = true;
    this._sfx('off');
  }

  _tvTransStep() {
    const tr = this._tvTrans, tv = this._tv;
    const tn = now();
    tr.t += Math.min(0.25, (tn - tr.last) / 1000); // wall-clock: always ~1.2 s, even at low fps
    tr.last = tn;
    const t = tr.t;
    const u = tv.mat.uniforms;
    u.uStatic.value = t < 0.28 ? 0.9 - t * 1.5 : Math.max(0, 0.5 - t);
    u.uJitter.value = t < 0.28 ? 3 : 1;
    u.uCollapse.value = clamp01((t - 0.22) / 0.78);
    if (this._tvLightMode === 'light') { try { this.game.world?.lighting?.setTVLight?.(true, Math.max(0, 1 - u.uCollapse.value * 1.2)); } catch (_) { /* ignore */ } }
    if (!tr.faded && t >= 0.82) { tr.faded = true; this.fadeTo(1, 0.36); }
    if (!tr.done && t >= tr.dur) {
      tr.done = true;
      const seq = this._fadeSeq;
      this.game.events.emit('ui:start');
      // gameplay usually fades in itself (intro); otherwise reveal the room
      if (this._fadeSeq === seq) setTimeout(() => { if (this._fadeSeq === seq) this.fadeTo(0, 1.6); }, 120);
    }
  }

  // ================================================================ menu API

  showMenu() {
    this._syncTouch();
    this._tvActivate();
    const tv = this._tv;
    if (tv) {
      tv.screen.locked = false;
      if (tv.screen.pageName !== 'main') this._goto(tv.screen, 'main', null, false);
      this.updateMenuCamera(0);
      tv.screen._focusSr();
    } else {
      console.warn('[ui] TV menu unavailable: no scene');
    }
    this._hideLoading();
  }

  hideMenu() {
    this._hideLoading();
    this._tvDeactivate();
    try { this.game.canvas?.focus?.({ preventScroll: true }); } catch (_) { /* ignore */ }
  }

  // ================================================================ teletext pages

  _goto(scr, name, sel = null, sound = true) {
    const prev = scr.pageName;
    if (prev && prev !== name) {
      const keep = [];
      for (const w of this._waiters) { if (w.scr === scr && w.page === prev) w.resolve(); else keep.push(w); }
      this._waiters = keep;
    }
    const fn = this._pages[name];
    if (!fn) return;
    scr.show(name, fn, sel);
    if (sound && prev !== name) { scr.flick = 1; this._sfx('page'); }
    if (scr === this._crt?.screen && prev && prev !== name) { scr.burst = Math.max(scr.burst, 0.12); scr.burstMax = 0.3; }
  }

  _waitPage(scr, page) { return new Promise((resolve) => this._waiters.push({ scr, page, resolve })); }

  _S(key) {
    const v = this.game.settings?.get?.(key);
    if (v === undefined || v === null) return key === 'cameraMotion' ? 1 : DEFAULT_SETTINGS[key];
    return v;
  }

  _set(key, v) { try { this.game.settings?.set?.(key, v); } catch (e) { console.warn(e); } }

  _num(key, d, step, min, max) {
    const v = Number(this._S(key));
    const n = clamp(Math.round(((Number.isFinite(v) ? v : min) + d * step) / step) * step, min, max);
    this._set(key, Number(n.toFixed(3)));
  }

  _barStr(v01, n = 5) { const k = Math.round(clamp01(v01) * n); return '▮'.repeat(k) + '▯'.repeat(n - k); }

  get _pages() {
    if (this.__pages) return this.__pages;
    const PG = {};
    const fsOk = !!(document.fullscreenEnabled || document.webkitFullscreenEnabled);
    const isFs = () => !!(document.fullscreenElement || document.webkitFullscreenElement);
    const homeNum = (b) => (b.s.home === 'pause' ? '150' : '100');
    const backHome = (b) => () => this._goto(b.s, b.s.home || 'main', b.s.pageName); // re-select the line we came from
    const digitEntry = (b) => b.digits((k) => {
      const s = b.s;
      s.typed = (s.typed + k).slice(-3);
      s.typedT = 2.5;
      s.dirty = true;
      if (s.typed.length === 3) {
        const map = { 100: 'main', 150: 'pause', 200: 'options', 201: 'options', 300: 'controls', 301: 'controls', 400: 'credits' };
        const target = map[s.typed];
        if (target === 'options') this._optSub = s.typed === '201' ? 1 : 0;
        if (target === 'controls') this._ctlSub = s.typed === '301' ? 1 : 0;
        const ok = target && (target !== 'main' || s.home === 'main') && (target !== 'pause' || s.home === 'pause');
        s.typed = '';
        if (ok) this._goto(s, target);
        else { this._sfx('value'); s.flick = 1; }
      }
    });

    PG.main = (b) => {
      b.header();
      b.pnum('100', 'INDEX');
      b.bar(2, C.r, 2);
      b.text(2, 'c', 'LA GARDIENNE', C.y, { dh: true });
      b.text(4, 'c', 'CHAPITRE 1 — LE SOUS-SOL', C.c);
      b.mosaicBand(5, C.b, 2);
      let r = 6;
      b.item(r++, { id: 'play', label: 'NOUVELLE PARTIE', right: '101', on: () => this._tvStartGame() });
      b.item(r++, { id: 'options', label: 'OPTIONS', right: '200', on: () => { this._optSub = 0; this._goto(b.s, 'options'); } });
      b.item(r++, { id: 'controls', label: 'CONTRÔLES', right: '300', on: () => { this._ctlSub = -1; this._goto(b.s, 'controls'); } });
      b.item(r++, { id: 'credits', label: 'CRÉDITS', right: '400', on: () => this._goto(b.s, 'credits') });
      if (fsOk && b.touch) b.item(r++, { id: 'fs', label: 'PLEIN ÉCRAN', kind: 'value', right: isFs() ? 'OUI' : 'NON', change: () => this._toggleFullscreen() });
      const alt = Math.floor((this.game.realTime || 0) / 4) % 2 === 1;
      b.hint(alt ? 'JOUE AVEC DES ÉCOUTEURS' : b.touch ? 'TOUCHE UNE LIGNE' : '▲▼ CHOISIR   ENTRÉE OK', alt ? C.m : C.g, b.rows - 2);
      b.ticker(TICKER_MENU);
      digitEntry(b);
    };

    const subSwitch = (b, row, n, get, set) => b.item(row, {
      id: 'sub', label: 'PAGE', kind: 'value', right: `${get() + 1}/${n}`, sr: `Page ${get() + 1} sur ${n}`,
      change: (d) => { set((get() + d + n) % n); b.s.flick = 1; },
    });

    PG.options = (b) => {
      const sub = this._optSub;
      b.header();
      b.pnum(sub ? '201' : '200', `${sub + 1}/2`, C.y);
      b.text(2, 1, 'OPTIONS', C.y, { dh: true });
      b.text(3, 'r', sub ? 'SON ET COMMANDES' : 'IMAGE', C.c);
      let r = 5;
      if (!sub) {
        // phones only get Auto / Basse / Moyenne (high and ultra are capped to medium by the renderer anyway)
        const QL = this._isTouch ? QUALITY.filter(([k]) => k !== 'high' && k !== 'ultra') : QUALITY;
        const qIdx = () => Math.max(0, QL.findIndex(([k]) => k === String(this._S('quality'))));
        b.item(r++, { id: 'quality', label: 'QUALITÉ', kind: 'value', right: QL[qIdx()][1], change: (d) => this._set('quality', QL[(qIdx() + d + QL.length) % QL.length][0]) });
        const br = Number(this._S('brightness'));
        b.item(r++, { id: 'brightness', label: 'LUMINOSITÉ', kind: 'value', right: `${this._barStr(br - 0.6)} ${Math.round(br * 100)}%`, change: (d) => this._num('brightness', d, 0.05, 0.6, 1.6) });
        b.item(r++, { id: 'fov', label: 'CHAMP DE VISION', kind: 'value', right: `${Math.round(Number(this._S('fov')))}°`, change: (d) => this._num('fov', d, 5, 55, 100) });
        const cm = Number(this._S('cameraMotion'));
        b.item(r++, { id: 'cameraMotion', label: 'MOUVEMENT CAMÉRA', kind: 'value', right: `${this._barStr(cm)} ${Math.round(cm * 100)}%`, change: (d) => this._num('cameraMotion', d, 0.1, 0, 1) });
        if (fsOk) b.item(r++, { id: 'fs', label: 'PLEIN ÉCRAN', kind: 'value', right: isFs() ? 'OUI' : 'NON', change: () => this._toggleFullscreen() });
      } else {
        const vol = Number(this._S('volume'));
        b.item(r++, { id: 'volume', label: 'VOLUME', kind: 'value', right: `${this._barStr(vol)} ${Math.round(vol * 100)}%`, change: (d) => { this._num('volume', d, 0.05, 0, 1); this.game.audio?.setMasterVolume?.(Number(this._S('volume'))); } });
        b.item(r++, { id: 'subtitles', label: 'SOUS-TITRES', kind: 'value', right: this._S('subtitles') ? 'OUI' : 'NON', change: () => this._set('subtitles', !this._S('subtitles')) });
        const se = Number(this._S('sensitivity'));
        b.item(r++, { id: 'sensitivity', label: 'SENSIBILITÉ', kind: 'value', right: `${this._barStr((se - 0.3) / 2.7)} ${se.toFixed(1).replace('.', ',')}`, change: (d) => this._num('sensitivity', d, 0.1, 0.3, 3) });
        b.item(r++, { id: 'invertY', label: 'INVERSER Y', kind: 'value', right: this._S('invertY') ? 'OUI' : 'NON', change: () => this._set('invertY', !this._S('invertY')) });
      }
      subSwitch(b, b.rows - 3, 2, () => this._optSub, (v) => { this._optSub = v; });
      b.item(b.rows - 2, { id: 'back', label: 'RETOUR', right: homeNum(b), on: backHome(b) });
      b.hint(b.touch ? 'TOUCHE ◄ OU ► POUR RÉGLER' : '◄► RÉGLER   ÉCHAP RETOUR');
      b.back(backHome(b));
      b.lr((d) => { this._optSub = (this._optSub + d + 2) % 2; b.s.dirty = true; b.s.flick = 1; this._sfx('value'); });
      digitEntry(b);
    };

    PG.controls = (b) => {
      if (this._ctlSub < 0) this._ctlSub = b.touch ? 1 : 0;
      const sub = this._ctlSub;
      b.header();
      b.pnum(sub ? '301' : '300', `${sub ? 'TACTILE' : 'CLAVIER'} ${sub + 1}/2`, C.y);
      b.text(2, 1, 'CONTRÔLES', C.y, { dh: true });
      const K = this._keyLabels || {};
      const move = K.W ? `${K.W}${K.A}${K.S}${K.D}` : 'ZQSD/WASD';
      const lines = sub
        ? [['GAUCHE', 'SE DÉPLACER'], ['DROITE', 'REGARDER'], ['BOUTON MAIN', 'INTERAGIR'], ['MAIN TENUE', 'ACTION LONGUE'], ['BOUTONS', 'LAMPE · ACCROUPI'], ['BOUTON ▲', 'COURIR']]
        : [['SE DÉPLACER', move], ['COURIR', 'MAJ'], ['S’ACCROUPIR', `${K.C || 'C'} / CTRL`], ['INTERAGIR', `${K.E || 'E'} / CLIC`], ['LAMPE', K.F || 'F'], ['PAUSE', `ÉCHAP / ${K.P || 'P'}`]];
      let r = 4;
      for (const [l, v] of lines) b.info(r++, l, v);
      subSwitch(b, b.rows - 3, 2, () => this._ctlSub, (v) => { this._ctlSub = v; });
      b.item(b.rows - 2, { id: 'back', label: 'RETOUR', right: homeNum(b), on: backHome(b) });
      b.hint(b.touch ? 'TOUCHE ◄ OU ► : AUTRE PAGE' : '◄► AUTRE PAGE   ÉCHAP RETOUR');
      b.back(backHome(b));
      b.lr((d) => { this._ctlSub = (this._ctlSub + d + 2) % 2; b.s.dirty = true; b.s.flick = 1; this._sfx('value'); });
      digitEntry(b);
    };

    PG.credits = (b) => {
      b.header();
      b.pnum('400', 'MERCI');
      b.text(2, 1, 'CRÉDITS', C.y, { dh: true });
      let r = 4;
      for (const [l, v] of [['MODÈLES 3D', 'POLY HAVEN'], ['TEXTURES', 'AMBIENTCG, POLY HAVEN'], ['SONS', 'RED LIBRARY, KENNEY'], ['LICENCES', 'CC0 (DOMAINE PUBLIC)'], ['MOTEUR 3D', 'THREE.JS'], ['POLICES', 'GOOGLE FONTS']]) b.info(r++, l, v);
      if (b.rows > 13) b.text(r + 1, 'c', 'UN JEU ORIGINAL. PAS UN BRUIT…', C.m);
      b.item(b.rows - 2, { id: 'back', label: 'RETOUR', right: homeNum(b), on: backHome(b) });
      b.ticker('MERCI D’AVOIR REGARDÉ CANAL 3   ·   TOUTES LES RESSOURCES SONT LIBRES (CC0)', { bg: C.b, fg: C.y });
      b.back(backHome(b));
      digitEntry(b);
    };

    // ---- full-screen CRT pages (40 × 16)
    PG.loading = (b) => {
      const L = this._loading;
      b.header();
      b.pnum('100', 'RECHERCHE DU SIGNAL', C.g);
      b.bar(3, C.r, 2);
      b.text(3, 'c', 'LA GARDIENNE', C.y, { dh: true });
      b.text(5, 'c', 'CHAPITRE 1 — LE SOUS-SOL', C.c);
      b.text(7, 'c', L.text || 'CHARGEMENT…', C.w);
      const n = 24, k = Math.round(clamp01(L.p) * n);
      const x0 = Math.floor((b.cols - n - 5) / 2);
      for (let i = 0; i < n; i++) b.tt.text(x0 + i, 8, i < k ? '█' : '▯', i < k ? C.g : C.d);
      b.tt.text(x0 + n + 1, 8, `${String(Math.round(L.p * 100)).padStart(3, NBSP)}%`, C.w);
      b.text(10, 'c', 'JOUE AVEC DES ÉCOUTEURS,', C.m);
      b.text(11, 'c', 'LUMIÈRES ÉTEINTES.', C.m);
      b.wrap(`CONSEIL : ${this._tip}`, b.cols - 2).slice(0, 3).forEach((l, i) => b.text(12 + i, 'c', l, C.g));
      b.ticker(TICKER_MENU);
    };

    PG.pause = (b) => {
      b.header();
      b.pnum('150', `NUIT ${this._night}/${this._nightsTotal}`, C.c);
      b.text(2, 1, 'PAUSE', C.y, { dh: true });
      let r = 4;
      if (this._obj.text) {
        b.text(r++, 1, 'OBJECTIF', C.g);
        for (const l of b.wrap(this._obj.text, b.cols - 2).slice(0, 2)) b.text(r++, 1, l, C.w);
      }
      const c = this._clues;
      if (c && Object.values(c).some((v) => v != null)) {
        b.text(r, 1, 'CODE', C.g);
        let x = 6;
        for (const [k, name] of CLUES) {
          const nm = up(name);
          b.tt.text(x, r, nm, C.c);
          b.tt.text(x + nm.length + 1, r, c[k] ?? '?', c[k] != null ? C.y : C.d);
          x += nm.length + 3;
        }
        r++;
      }
      const inv = this._items.map((it) => {
        const nm = ITEM_NAMES[it.id] || it.name || it.id;
        return (it.count ?? 1) > 1 ? `${nm} ×${it.count}` : nm;
      });
      if (inv.length) { b.text(r, 1, 'SAC', C.g); b.text(r, 6, inv.join(' · ').slice(0, b.cols - 7), C.c); r++; }
      const notes = this._allNotes();
      r = Math.max(r + 1, b.rows - (notes.length ? 7 : 6));
      b.item(r++, { id: 'resume', label: 'REPRENDRE', right: 'ÉCHAP', on: () => this.hidePause() });
      if (notes.length) b.item(r++, { id: 'notes', label: 'NOTES', right: '160', on: () => this._goto(b.s, 'notes') });
      b.item(r++, { id: 'options', label: 'OPTIONS', right: '200', on: () => { this._optSub = 0; this._goto(b.s, 'options'); } });
      b.item(r++, { id: 'controls', label: 'CONTRÔLES', right: '300', on: () => { this._ctlSub = -1; this._goto(b.s, 'controls'); } });
      b.item(r++, { id: 'quit', label: 'QUITTER', right: '999', color: C.r, on: () => this._goto(b.s, 'quit') });
      b.hint(b.touch ? 'TOUCHE UNE LIGNE' : '▲▼ CHOISIR   ENTRÉE OK   ÉCHAP REPRENDRE');
      digitEntry(b);
    };

    PG.notes = (b) => {
      b.header();
      b.pnum('160', 'NOTES TROUVÉES', C.c);
      b.text(2, 1, 'NOTES', C.y, { dh: true });
      const notes = this._allNotes();
      let r = 5;
      notes.slice(0, b.rows - 8).forEach((n, i) => b.item(r++, { id: `note${i}`, label: String(n?.title || `Note ${i + 1}`).slice(0, b.cols - 2), kind: 'action', on: () => this.showNote(n) }));
      b.item(b.rows - 2, { id: 'back', label: 'RETOUR', right: '150', on: backHome(b) });
      b.back(backHome(b));
    };

    PG.quit = (b) => {
      b.header();
      b.pnum('999', 'FIN DE SOIRÉE', C.r);
      b.text(3, 'c', 'QUITTER LA PARTIE ?', C.y, { dh: true });
      b.text(6, 'c', 'TA PROGRESSION SERA PERDUE.', C.w);
      b.item(9, { id: 'no', label: 'NON, RESTER', kind: 'action', on: backHome(b) });
      b.item(10, { id: 'yes', label: 'OUI, QUITTER', kind: 'action', color: C.r, on: () => { this.game.events.emit('ui:quit'); window.location.reload(); } });
      b.back(backHome(b));
    };

    const nightMarks = (b, row, night, total, allLost) => {
      const x0 = Math.floor((b.cols - total * 3) / 2);
      for (let i = 1; i <= total; i++) {
        const lost = allLost || i < night;
        const cur = !allLost && i === night;
        b.tt.text(x0 + (i - 1) * 3, row, lost ? '█' : cur ? '▮' : '▯', lost ? C.r : cur ? C.w : C.d);
      }
    };
    const endItem = (b, row, label) => {
      if (!this._end?.ready) return;
      b.item(row, { id: 'go', label, kind: 'action', on: () => this._endFinish() });
    };

    PG.caught = (b) => {
      const e = this._end?.cfg || {};
      b.header('CANAL 3 · BULLETIN SPÉCIAL', C.r, C.w);
      b.text(1, 'r', b.blink ? '● EN DIRECT' : '  EN DIRECT', C.r);
      b.text(2, 'c', 'ELLE T’A TROUVÉ.', C.r, { dh: true });
      b.text(4, 'c', `NUIT ${e.night} / ${e.total}`, C.w, { dh: true });
      nightMarks(b, 6, e.night, e.total, false);
      let r = 8;
      for (const l of b.wrap(e.text || '', b.cols - 4).slice(0, 3)) b.text(r++, 'c', l, C.c);
      for (const l of b.wrap(e.rest || '', b.cols - 4).slice(0, 2)) b.text(r++, 'c', l, C.y);
      endItem(b, b.rows - 3, 'CONTINUER');
      b.ticker(`${e.tip || ''}   ·   AVIS À LA POPULATION : NE QUITTEZ PAS VOTRE DOMICILE APRÈS MINUIT`, { bg: C.b, fg: C.w });
    };

    PG.gameover = (b) => {
      const e = this._end?.cfg || {};
      b.header('CANAL 3 · FIN DU SIGNAL', C.r, C.w);
      b.text(2, 'c', 'ELLE T’A GARDÉ.', C.r, { dh: true });
      b.text(5, 'c', ' SIGNAL PERDU ', C.k, { bg: C.w });
      nightMarks(b, 7, e.total + 1, e.total, true);
      let r = 9;
      for (const l of b.wrap(e.text || '', b.cols - 4).slice(0, 3)) b.text(r++, 'c', l, C.c);
      endItem(b, b.rows - 3, 'RECOMMENCER');
      b.ticker('LA PROGRAMMATION REPRENDRA DEMAIN MATIN   ·   BONNE NUIT');
    };

    PG.win = (b) => {
      const e = this._end?.cfg || {};
      const bars = [C.w, C.y, C.c, C.g, C.m, C.r, C.b];
      const bw = b.cols / bars.length;
      for (let i = 0; i < bars.length; i++) b.tt.rect(Math.round(i * bw), 0, Math.round((i + 1) * bw) - Math.round(i * bw), 5, bars[i]);
      for (let i = 0; i < b.cols; i++) b.tt.rect(i, 5, 1, 1, i % 2 ? C.k : C.w);
      b.text(6, 'c', 'FIN DE LA DIFFUSION', C.w, { dh: true });
      b.text(8, 'c', 'TU T’ES ÉCHAPPÉ.', C.y);
      b.info(9, 'TEMPS', e.timeStr || '');
      b.info(10, 'NUITS', `${e.nightsUsed} / ${e.total}`);
      b.wrap(e.text || '', b.cols - 4).slice(0, 2).forEach((l, i) => b.text(11 + i, 'c', l, C.c));
      endItem(b, b.rows - 3, 'REJOUER');
      b.ticker('MERCI D’AVOIR REGARDÉ CANAL 3   ·   CHAPITRE 2 BIENTÔT   ·   BONNE NUIT', { bg: C.b, fg: C.y });
    };

    this.__pages = PG;
    return PG;
  }

  _allNotes() {
    const n = this._notes || this.game.inventory?.notes || [];
    return Array.isArray(n) ? n : [];
  }

  _toggleFullscreen() {
    const d = document, el = d.documentElement;
    const fail = () => this.subtitle('Plein écran indisponible sur cet appareil.', 2.5, { critical: true });
    try {
      if (d.fullscreenElement || d.webkitFullscreenElement) { (d.exitFullscreen || d.webkitExitFullscreen)?.call(d)?.catch?.(() => {}); return; }
      const req = el.requestFullscreen || el.webkitRequestFullscreen;
      if (!req) { fail(); return; }
      const p = req.call(el, { navigationUI: 'hide' });
      const lock = () => { try { screen.orientation?.lock?.('landscape')?.catch?.(() => {}); } catch (_) { /* ignore */ } };
      if (p && p.then) p.then(lock, fail); else lock();
    } catch (_) { fail(); }
  }

  // ================================================================ full-screen CRT (loading, pause, endings)

  _buildCrt() {
    const tt = new Teletext(40, 16, 15, 28, 20, 16);
    const el = this._layer('lg-crt', '<div class="lg-crt-screen"><div class="lg-crt-fx"></div></div><div class="lg-sr" role="menu"></div>');
    el.querySelector('.lg-crt-screen').prepend(tt.canvas);
    const screen = new TTScreen(this, tt, el.querySelector('.lg-sr'));
    this._crt = { tt, el, screen, open: false, mode: '' };
    const cv = tt.canvas;
    const pick = (e) => {
      const r = cv.getBoundingClientRect();
      return screen.hit((e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height);
    };
    let down = null;
    cv.addEventListener('pointerdown', (e) => { down = { x: e.clientX, y: e.clientY, id: e.pointerId }; if (e.pointerType !== 'mouse') { const hit = pick(e); if (hit) screen.select(hit.it.id); } });
    cv.addEventListener('pointermove', (e) => {
      if (e.pointerType !== 'mouse') return;
      const hit = pick(e);
      cv.style.cursor = hit ? 'pointer' : 'default';
      if (hit) screen.select(hit.it.id);
    });
    cv.addEventListener('pointerup', (e) => {
      if (!down || down.id !== e.pointerId) return;
      const moved = Math.hypot(e.clientX - down.x, e.clientY - down.y);
      down = null;
      if (moved > 14) return;
      const hit = pick(e);
      if (!hit) return;
      screen.select(hit.it.id, false);
      if (hit.it.change && !hit.side) { if (e.pointerType === 'mouse') screen.activate(1); return; }
      screen.activate(hit.side);
    });
    cv.addEventListener('wheel', (e) => {
      e.preventDefault();
      this._crtWheel = (this._crtWheel || 0) + (e.deltaMode === 1 ? e.deltaY * 33 : e.deltaY);
      if (Math.abs(this._crtWheel) >= 60) { screen.move(this._crtWheel > 0 ? 1 : -1); this._crtWheel = 0; }
    }, { passive: false });
  }

  /** mode: 'loading' | 'pause' | 'end'. */
  _ovOpen(mode, page, { burst = 0 } = {}) {
    const crt = this._crt;
    const el = crt.el;
    crt.mode = mode;
    crt.tt.mix = mode === 'pause';
    el.classList.toggle('mix', mode === 'pause');
    el.classList.toggle('loading', mode === 'loading');
    const scr = crt.screen;
    scr.home = mode === 'pause' ? 'pause' : '';
    scr.locked = false;
    scr.allowE = mode === 'end';
    scr.burst = burst;
    scr.burstMax = Math.max(0.05, burst);
    scr.srFocus = mode !== 'loading';
    this._goto(scr, page || mode, null, false);
    scr.draw();
    if (!crt.open) {
      crt.open = true;
      this._open(el, {
        modal: mode !== 'loading',
        focus: mode === 'loading' ? null : () => { scr._focusSr(); return null; },
        onKey: (e) => this._crtKey(e),
      });
    }
  }

  _ovClose(delay = 320) {
    const crt = this._crt;
    if (!crt.open) return;
    crt.open = false;
    crt.screen.srFocus = false;
    this._close(crt.el, { restoreFocus: false, delay });
    if (this._tvOn && this._tv && this.game.state === 'menu') this._tv.screen._focusSr();
  }

  _crtKey(e) {
    const crt = this._crt;
    if (crt.mode === 'loading') return false;
    if (crt.mode === 'pause' && crt.screen.pageName === 'pause' && (e.key === 'Escape' || e.code === 'KeyP')) {
      // Input owns Esc/P → 'input:pause' → Game.resume() → hidePause(). Fallback if nothing handled it.
      setTimeout(() => { if (this._pause && this.game.state === 'paused' && this._top()?.el === crt.el) this.hidePause(); }, 160);
      return false;
    }
    if (crt.mode === 'end' && !this._end?.ready) return true;
    return crt.screen.key(e);
  }

  // ================================================================ loading

  showLoading(p, text) {
    const L = this._loading;
    if (L.hidden) return;
    L.p = clamp01(Number(p) || 0);
    if (text) L.text = text;
    this._crt.screen.dirty = true;
    this._loadingLoop();
    this._crt.screen.srHost.textContent = `${fr(L.text)} ${Math.round(L.p * 100)} %`;
    if (L.p >= 0.85 && !this._tvOn && this.game.world && this.game.state === 'loading') {
      try { this._tvActivate(); this.updateMenuCamera(0); } catch (e) { console.warn('[ui] tv init', e); }
    }
  }

  hideLoading() { this._hideLoading(); }

  /** Animates the loading page (blink, ticker) until the game loop runs ui.update(). */
  _loadingLoop() {
    if (this._loadRaf) return;
    let last = now();
    const tick = () => {
      if (this._loading.hidden || this._crt.mode !== 'loading') { this._loadRaf = 0; return; }
      const t = now();
      if (t - (this._updAt || 0) > 150) {
        const scr = this._crt.screen;
        scr.tick(Math.min(0.1, (t - last) / 1000));
        if (scr.dirty) scr.draw();
      }
      last = t;
      this._loadRaf = requestAnimationFrame(tick);
    };
    this._loadRaf = requestAnimationFrame(tick);
  }

  _hideLoading() {
    const L = this._loading;
    if (L.hidden) return;
    L.hidden = true;
    if (this._crt.mode === 'loading') this._ovClose(950);
  }

  // ================================================================ options / controls / credits (public helpers)

  _pageScreen() {
    if (this._tvOn && this._tv && this.game.state === 'menu') return this._tv.screen;
    if (!(this._crt.open && this._crt.mode === 'pause')) this._ovOpen('pause', 'pause');
    return this._crt.screen;
  }

  showOptions() { const s = this._pageScreen(); this._optSub = 0; this._goto(s, 'options'); return this._waitPage(s, 'options'); }
  showControls() { const s = this._pageScreen(); this._ctlSub = -1; this._goto(s, 'controls'); return this._waitPage(s, 'controls'); }
  showCredits() { const s = this._pageScreen(); this._goto(s, 'credits'); return this._waitPage(s, 'credits'); }

  // ================================================================ pause

  showPause() {
    if (this._pause) return this._pause.promise;
    let resolve;
    const promise = new Promise((r) => { resolve = r; });
    this._pause = { promise, resolve };
    this._syncTouch();
    this._ovOpen('pause', 'pause', { burst: 0.12 });
    this._sfx('page');
    return promise;
  }

  hidePause() {
    const overlay = this._crt.open && this._crt.mode === 'pause';
    if (!this._pause && !overlay) return;
    if (this._noteResolve) this._closeNote();
    if (overlay) {
      this._goto(this._crt.screen, 'pause', null, false); // resolves pending option/controls waiters
      this._ovClose(200);
    }
    const p = this._pause;
    this._pause = null;
    try { this.game.canvas?.focus?.({ preventScroll: true }); } catch (_) { /* ignore */ }
    p?.resolve();
  }

  // ================================================================ caught / game over / win

  _showEnd(page, cfg, readyDelay) {
    if (this._end) this._endFinish();
    if (this._pause) this.hidePause();
    this._hideSub();
    this.setPrompt(null);
    const burst = page === 'win' ? 0.45 : 0.8;
    return new Promise((resolve) => {
      this._end = { resolve, ready: false, readyAt: now() + readyDelay, cfg };
      this._ovOpen('end', page, { burst });
      try { this.game.audio?.play?.('tv_static', { volume: 0.25 }); } catch (_) { /* ignore */ }
    });
  }

  _endFinish() {
    const end = this._end;
    if (!end) return;
    this._end = null;
    if (this._crt.mode === 'end') this._ovClose(250);
    end.resolve();
  }

  showCaught({ night = 2, nightsTotal = 3 } = {}) {
    const left = Math.max(0, nightsTotal - night);
    const flavors = [
      'Tu te réveilles en bas de l’escalier. La maison est silencieuse… pour l’instant.',
      'Tu rouvres les yeux sur le tapis. Quelqu’un a rangé tes affaires.',
      'Une berceuse s’éloigne à l’étage. Tu es encore dans le sous-sol.',
    ];
    const rest = left === 0 ? 'C’est ta dernière nuit.' : `Encore ${left} nuit${left > 1 ? 's' : ''} avant qu’elle te garde.`;
    return this._showEnd('caught', {
      night, total: nightsTotal, rest,
      text: flavors[(((night - 2) % flavors.length) + flavors.length) % flavors.length],
      tip: `Conseil : ${TIPS[Math.floor(Math.random() * TIPS.length)]}`,
    }, 1500);
  }

  showGameOver() {
    const total = this.game.nightsTotal ?? 3;
    return this._showEnd('gameover', { total, text: 'Trois nuits. Personne n’est venu te chercher. Tu fais partie du sous-sol, maintenant.' }, 2200);
  }

  showWin({ time = 0, nightsUsed = 1, nightsTotal = 3 } = {}) {
    const s = Math.max(0, Math.round(Number(time) || 0));
    const hh = Math.floor(s / 3600), mm = Math.floor((s % 3600) / 60), ss = s % 60;
    const timeStr = hh ? `${hh} H ${String(mm).padStart(2, '0')} MIN` : `${mm} MIN ${String(ss).padStart(2, '0')} S`;
    return this._showEnd('win', {
      timeStr, nightsUsed, total: nightsTotal,
      text: nightsUsed <= 1 ? 'Sans te faire attraper une seule fois.' : 'En bas, quelqu’un fredonne encore.',
    }, 2000);
  }

  // ================================================================ note reader (paper)

  _buildNote() {
    const el = (this._noteEl = this._layer('lg-notelayer', `
      <div class="lg-note-wrap">
        <p class="lg-note-label"></p>
        <article class="lg-note" role="dialog" aria-modal="true" tabindex="-1"></article>
        <button type="button" class="lg-act" data-act="close">Fermer <span class="lg-kc"></span></button>
      </div>`));
    this._noteLabel = el.querySelector('.lg-note-label');
    this._notePaper = el.querySelector('.lg-note');
    el.addEventListener('click', (e) => {
      if (now() - this._noteOpenedAt < 380) return; // the tap that opened the note must not close it
      if (e.target.closest('[data-act="close"]') || e.target.classList.contains('lg-note-wrap') || e.target === el) this._closeNote();
    });
  }

  showNote({ title = '', text = '', style = 'note', headline, masthead, date } = {}) {
    if (this._noteResolve) this._closeNote();
    this._noteEl.querySelector('.lg-kc').innerHTML = cap(this._eLabel());
    const paper = this._notePaper;
    const st = style === 'child' || style === 'newspaper' ? style : 'note';
    paper.className = `lg-note ${st}`;
    paper.innerHTML = '';
    paper.style.clipPath = '';
    const paras = String(text ?? '').split(/\n[ \t]*\n/);
    if (st === 'newspaper') {
      paper.style.clipPath = tornClip(22, 97);
      const mast = document.createElement('div');
      mast.className = 'lg-np-mast';
      mast.textContent = masthead || 'L’Écho du quartier';
      const dl = document.createElement('div');
      dl.className = 'lg-np-date';
      dl.innerHTML = '<span></span><span>Faits divers</span>';
      dl.firstChild.textContent = date || '';
      const hd = document.createElement('h3');
      hd.className = 'lg-np-h';
      hd.textContent = fr(headline || title || '');
      const body = document.createElement('div');
      body.className = 'lg-np-body';
      for (const p of paras) this._para(body, p);
      paper.append(mast, dl);
      if (hd.textContent) paper.append(hd);
      paper.append(body);
      this._noteLabel.textContent = '';
    } else if (st === 'child') {
      const colors = ['#c2412d', '#2c58a8', '#3d8a3a', '#7a3fa0', '#d9792a', '#1f1a16'];
      let ci = Math.floor(Math.random() * colors.length);
      for (const p of paras) {
        const pe = document.createElement('p');
        for (const line of p.split('\n')) {
          for (const word of fr(line).split(/[ \t]+/).filter(Boolean)) {
            const w = document.createElement('span');
            w.className = 'w lg-crayon';
            w.style.color = colors[ci++ % colors.length];
            w.style.transform = `rotate(${(Math.random() * 6 - 3).toFixed(1)}deg) translateY(${(Math.random() * 4 - 2).toFixed(1)}px)`;
            w.style.fontSize = `${(0.9 + Math.random() * 0.25).toFixed(2)}em`;
            w.textContent = word;
            pe.append(w, ' ');
          }
          pe.append(document.createElement('br'));
        }
        paper.append(pe);
      }
      paper.insertAdjacentHTML('beforeend', '<svg class="lg-sun" viewBox="0 0 60 60" aria-hidden="true" fill="none" stroke="#e0a82e" stroke-width="3" stroke-linecap="round"><circle cx="30" cy="30" r="10" fill="#f1c84b" stroke="#e0a82e"/><path d="M30 6v8M30 46v8M6 30h8M46 30h8M13 13l6 6M41 41l6 6M13 47l6-6M41 19l6-6"/></svg>');
      this._noteLabel.textContent = title ? fr(title) : '';
    } else {
      for (const p of paras) this._para(paper, p);
      this._noteLabel.textContent = title ? fr(title) : '';
    }
    this._noteLabel.hidden = !this._noteLabel.textContent;
    paper.setAttribute('aria-label', title || 'Note');
    paper.scrollTop = 0;
    this._noteOpenedAt = now();
    try { this.game.audio?.play?.('paper', { volume: 0.8 }); } catch (_) { /* ignore */ }
    return new Promise((resolve) => {
      this._noteResolve = resolve;
      this._open(this._noteEl, { modal: true, focus: '[data-act="close"]', onKey: (e) => this._noteKey(e) });
    });
  }

  _para(host, text) {
    const p = document.createElement('p');
    p.textContent = fr(String(text).replace(/^\n+|\n+$/g, ''));
    host.append(p);
  }

  _noteKey(e) {
    const k = e.key;
    if (k === 'Escape' || ((e.code === 'KeyE' || k === 'Enter' || k === ' ') && !e.repeat)) {
      if (now() - this._noteOpenedAt < 250) return true;
      this._closeNote();
      return true;
    }
    if (e.code === 'KeyE' || k === 'Enter' || k === ' ') return true;
    const p = this._notePaper;
    if (k === 'ArrowDown' || k === 'PageDown') { p.scrollBy({ top: k === 'PageDown' ? p.clientHeight * 0.8 : 48, behavior: 'smooth' }); return true; }
    if (k === 'ArrowUp' || k === 'PageUp') { p.scrollBy({ top: k === 'PageUp' ? -p.clientHeight * 0.8 : -48, behavior: 'smooth' }); return true; }
    return false;
  }

  _closeNote() {
    if (!this._noteResolve) return;
    const r = this._noteResolve;
    this._noteResolve = null;
    this._close(this._noteEl);
    r();
  }

  // ================================================================ keypad (the brass combination padlock)

  _buildKeypad() {
    const el = (this._kpEl = this._layer('lg-kplayer', `
      <div class="lg-kp" role="dialog" aria-modal="true" aria-label="Cadenas à combinaison">
        <div class="lg-kp-lockwrap"><div class="lg-kp-shackle"></div><div class="lg-kp-lock"><span class="lg-kp-stamp">LAITON · 4 CHIFFRES</span><div class="lg-kp-wheels"></div></div></div>
        <div class="lg-kp-side">
          <div class="lg-kp-scrap" aria-label="Chiffres trouvés"></div>
          <div class="lg-kp-actions">
            <button type="button" class="lg-act" data-act="try">Essayer ${cap('Entrée')}</button>
            <button type="button" class="lg-act" data-act="cancel">Lâcher ${cap('Échap')}</button>
          </div>
          <p class="lg-kp-help"></p>
        </div>
      </div>`));
    this._kpWheelsEl = el.querySelector('.lg-kp-wheels');
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-act]');
      if (!b || !this._kp) return;
      if (b.dataset.act === 'cancel') this._kpFinish(null);
      else if (b.dataset.act === 'try') this._kpFinish(this._kp.digits.join(''));
      else if (b.dataset.act === 'up' || b.dataset.act === 'down') {
        const i = Number(b.closest('.lg-wheel').dataset.i);
        this._kpActive(i);
        this._kpStep(i, b.dataset.act === 'up' ? 1 : -1);
      }
    });
  }

  _buildWheels(n) {
    const host = this._kpWheelsEl;
    host.innerHTML = '';
    const digits = [];
    for (let k = 0; k < 3; k++) for (let d = 0; d < 10; d++) digits.push(`<span>${d}</span>`);
    const strip = digits.join('');
    this._kpWheelEls = [];
    for (let i = 0; i < n; i++) {
      const w = h(`<div class="lg-wheel" data-i="${i}" tabindex="-1" role="spinbutton" aria-valuemin="0" aria-valuemax="9" aria-label="Molette ${i + 1}">
        <button type="button" class="lg-wheel-btn" data-act="up" tabindex="-1" aria-label="Chiffre suivant">${icon('up')}</button>
        <div class="lg-drum"><div class="lg-strip">${strip}</div></div>
        <button type="button" class="lg-wheel-btn" data-act="down" tabindex="-1" aria-label="Chiffre précédent">${icon('down')}</button>
      </div>`);
      host.appendChild(w);
      this._kpWheelEls.push(w);
      const drum = w.querySelector('.lg-drum');
      drum.addEventListener('wheel', (e) => {
        e.preventDefault();
        const dy = e.deltaMode === 1 ? e.deltaY * 33 : e.deltaY;
        w._acc = (w._acc || 0) + dy;
        if (Math.abs(dy) >= 50 || Math.abs(w._acc) >= 50) { this._kpActive(i); this._kpStep(i, w._acc > 0 ? 1 : -1); w._acc = 0; }
      }, { passive: false });
      drum.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        this._kpActive(i);
        try { drum.setPointerCapture(e.pointerId); } catch (_) { /* ignore */ }
        w._drag = { y: e.clientY, startY: e.clientY, moved: 0, id: e.pointerId };
      });
      drum.addEventListener('pointermove', (e) => {
        const d = w._drag;
        if (!d || d.id !== e.pointerId) return;
        const step = Math.max(18, (drum.clientHeight / 1.9) * 0.55);
        const dy = d.y - e.clientY;
        d.moved = Math.max(d.moved, Math.abs(e.clientY - d.startY));
        if (Math.abs(dy) >= step) {
          const s = Math.trunc(dy / step);
          d.y -= s * step;
          for (let k = 0; k < Math.abs(s); k++) this._kpStep(i, s > 0 ? 1 : -1);
        }
      });
      const end = (e) => {
        const d = w._drag;
        if (!d || d.id !== e.pointerId) return;
        w._drag = null;
        if (d.moved < 6 && e.type === 'pointerup') {
          const r = drum.getBoundingClientRect();
          const rel = (e.clientY - r.top) / r.height;
          if (rel < 0.36) this._kpStep(i, -1);
          else if (rel > 0.64) this._kpStep(i, 1);
        }
      };
      drum.addEventListener('pointerup', end);
      drum.addEventListener('pointercancel', end);
    }
  }

  showKeypad({ title, length = 4 } = {}) {
    if (this._kp) this._kpFinish(null);
    const n = Math.max(1, Math.min(8, Number(length) || 4));
    if (!this._kpWheelEls || this._kpWheelEls.length !== n) this._buildWheels(n);
    if (this._combo.length !== n) this._combo = new Array(n).fill(0);
    const el = this._kpEl;
    el.querySelector('.lg-kp').setAttribute('aria-label', fr(title || 'Cadenas à combinaison'));
    el.querySelector('.lg-kp-stamp').textContent = `LAITON · ${n} CHIFFRES`;
    el.querySelector('.lg-kp-help').textContent = this._isTouch
      ? 'Glisse ou touche les molettes pour tourner.'
      : 'Flèches, molette ou clic pour tourner. Tape les chiffres 0 à 9.';
    this._kp = { digits: this._combo.slice(), pos: [], active: 0, openedAt: now(), resolve: null };
    for (let i = 0; i < n; i++) { this._kp.pos[i] = 10 + this._kp.digits[i]; this._kpApply(i, false); }
    this._kpActive(0);
    this._renderKpScrap();
    return new Promise((resolve) => {
      this._kp.resolve = resolve;
      this._open(el, { modal: true, focus: '[data-act="try"]', onKey: (e) => this._kpKey(e) });
      requestAnimationFrame(() => { if (this._kp) for (let i = 0; i < n; i++) this._kpApply(i, false); });
    });
  }

  _renderKpScrap() {
    const host = this._kpEl.querySelector('.lg-kp-scrap');
    const c = this._clues;
    host.hidden = !c;
    if (!c) return;
    host.innerHTML = CLUES.map(([k, name]) => `<span class="${c[k] == null ? 'unk' : ''}"><small>${esc(name.toLowerCase())}</small>${esc(c[k] ?? '?')}</span>`).join('');
  }

  _kpActive(i) {
    if (!this._kp) return;
    this._kp.active = i;
    this._kpWheelEls.forEach((w, k) => w.classList.toggle('is-active', k === i));
  }

  _kpApply(i, anim = true) {
    const kp = this._kp;
    const w = this._kpWheelEls[i];
    const strip = w.querySelector('.lg-strip');
    const drum = w.querySelector('.lg-drum');
    const kh = strip.firstElementChild?.offsetHeight || 52;
    const off = drum.clientHeight / 2 - kh / 2 - kp.pos[i] * kh;
    strip.classList.toggle('anim', anim);
    strip.style.transform = `translateY(${off.toFixed(1)}px)`;
    w.setAttribute('aria-valuenow', String(kp.digits[i]));
  }

  _kpStep(i, d) {
    const kp = this._kp;
    if (!kp) return;
    const w = this._kpWheelEls[i];
    if (kp.pos[i] < 10 || kp.pos[i] > 19) {
      clearTimeout(w._snap);
      kp.pos[i] = 10 + kp.digits[i];
      this._kpApply(i, false);
      void w.offsetWidth;
    }
    kp.digits[i] = (kp.digits[i] + d + 10) % 10;
    kp.pos[i] += d;
    this._kpApply(i, true);
    clearTimeout(w._snap);
    w._snap = setTimeout(() => {
      if (this._kp !== kp || (kp.pos[i] >= 10 && kp.pos[i] <= 19)) return;
      kp.pos[i] = 10 + kp.digits[i];
      this._kpApply(i, false);
    }, 190);
    try { this.game.audio?.play?.('lock_wheel', { volume: 0.6, rate: 0.96 + Math.random() * 0.08 }); } catch (_) { /* ignore */ }
  }

  _kpSet(i, digit) {
    const kp = this._kp;
    const cur = kp.digits[i];
    if (cur === digit) return;
    let d = digit - cur;
    if (d > 5) d -= 10;
    if (d < -5) d += 10;
    const s = Math.sign(d);
    for (let k = 0; k < Math.abs(d); k++) this._kpStep(i, s);
  }

  _kpKey(e) {
    const kp = this._kp;
    if (!kp) return false;
    const k = e.key;
    const n = this._kpWheelEls.length;
    if (k === 'Escape') { this._kpFinish(null); return true; }
    if (k === 'Enter' || k === 'NumpadEnter') {
      if (e.repeat) return true;
      const t = e.target;
      if (t && t.tagName === 'BUTTON' && t.dataset.act === 'cancel') return false;
      if (now() - kp.openedAt < 250) return true;
      this._kpFinish(kp.digits.join(''));
      return true;
    }
    if (k === 'ArrowLeft') { this._kpActive((kp.active - 1 + n) % n); return true; }
    if (k === 'ArrowRight') { this._kpActive((kp.active + 1) % n); return true; }
    if (k === 'ArrowUp') { this._kpStep(kp.active, 1); return true; }
    if (k === 'ArrowDown') { this._kpStep(kp.active, -1); return true; }
    if (k === 'Backspace') { this._kpActive(Math.max(0, kp.active - 1)); return true; }
    if (/^[0-9]$/.test(k)) { this._kpSet(kp.active, Number(k)); if (kp.active < n - 1) this._kpActive(kp.active + 1); return true; }
    if (e.code === 'KeyE' || k === ' ') return true;
    return false;
  }

  _kpFinish(result) {
    const kp = this._kp;
    if (!kp) return;
    this._kp = null;
    this._combo = kp.digits.slice();
    for (const w of this._kpWheelEls) clearTimeout(w._snap);
    this._close(this._kpEl);
    kp.resolve?.(result);
  }

  // ================================================================ misc

  _loadKeyLabels() {
    try {
      const p = navigator.keyboard?.getLayoutMap?.();
      p?.then?.((m) => {
        const g = (c) => (m.get(c) || '').toUpperCase();
        this._keyLabels = { W: g('KeyW'), A: g('KeyA'), S: g('KeyS'), D: g('KeyD'), E: g('KeyE'), F: g('KeyF'), C: g('KeyC'), P: g('KeyP') };
        this._syncTouch();
        if (this._promptKey && this._promptKey !== '✋') this._promptKey = '';
        if (this._tv) this._tv.screen.dirty = true;
      })?.catch?.(() => {});
    } catch (_) { /* unsupported */ }
  }

  _buildRotate() {
    const el = h(`<div class="lg-rotate" role="alert">
      <span class="big">${icon('rotate')}</span>
      <h2>Tourne ton téléphone</h2>
      <p>La Gardienne se joue à l’horizontale. Active la rotation automatique si besoin.</p>
      <button type="button" class="lg-act" data-act="ok">Continuer quand même</button>
    </div>`);
    this.el.appendChild(el);
    for (const t of ['pointerdown', 'touchstart', 'mousedown']) el.addEventListener(t, (e) => e.stopPropagation(), { passive: true });
    el.querySelector('[data-act="ok"]').addEventListener('click', () => this.el.classList.add('rot-ok'));
  }
}
