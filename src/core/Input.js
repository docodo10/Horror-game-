// Unified keyboard/mouse (pointer lock) + touch (dynamic virtual joystick, look pad, buttons) input.
// Public API (must be kept):
//   constructor(game, touchRoot); init(); update(dt); endFrame()
//   .enabled            set by Game every frame (false while a modal is open / not playing) -> move/look read as zero
//   .isTouch            true on touch devices (coarse pointer) — touch controls are shown only then
//   .move               {x, y} in -1..1 (y = forward)
//   .look               {dx, dy} pixels this frame (already multiplied by settings.sensitivity; invertY applied)
//   pressed(action)     true only on the frame the action was pressed. Actions:
//                       'interact' (E / left click / hand button), 'flashlight' (F / torch button),
//                       'crouch' (C or Ctrl / crouch button, toggle), 'pause' (Esc / P / pause button —
//                       Input itself emits 'input:pause'), 'next' (Tab / wheel)
//   held(action)        'sprint' (Shift / sprint button hold), 'interact' (for hold-to-use), 'crouch'
//   setInteractAvailable(bool, label?)  highlights the hand touch button
//   lockPointer() / unlockPointer()     desktop pointer lock; emits 'input:pointerlock' {locked}
//   setTouchVisible(bool)
// Extra public members (player module):
//   .pointerLocked      bool
//   .moveSource         'keys' | 'touch' | null   (which device produced .move this frame)
//   .sprintStick        true while the touch joystick is pushed past its rim toward the front (auto-sprint)
//   injectLook(dx, dy)  add raw look pixels (tests / scripted cameras), same units as mouse movement
//   vibrate(ms|pattern) best-effort haptic feedback on phones (no-op elsewhere)
//
// Desktop: WASD/ZQSD (physical keys, so AZERTY works) + arrows, mouse look with pointer lock (raw deltas via
// unadjustedMovement when supported), click on the game to (re)lock, Shift sprint, C/Ctrl crouch toggle,
// E / left click interact, F flashlight, Esc/P pause, Tab/wheel next.
// Touch (landscape phones): left side = dynamic joystick (appears under the thumb, dead zone, analog, push past the
// rim = sprint), right side = drag look (smoothed, ~1:1 with the scene), right-hand button cluster (interact, torch,
// crouch, sprint — drag on sprint also turns the view), pause top-right. Multi-touch via touch identifiers.

const KEYMAP = {
  KeyW: 'fwd', ArrowUp: 'fwd', KeyS: 'back', ArrowDown: 'back',
  KeyA: 'left', ArrowLeft: 'left', KeyD: 'right', ArrowRight: 'right',
  ShiftLeft: 'sprint', ShiftRight: 'sprint',
  KeyC: 'crouch', ControlLeft: 'crouch', ControlRight: 'crouch',
  KeyE: 'interact', KeyF: 'flashlight',
  Escape: 'pause', KeyP: 'pause', Tab: 'next',
};
const ACTIONS = ['fwd', 'back', 'left', 'right', 'sprint', 'crouch', 'interact', 'flashlight', 'pause', 'next'];
const PREVENT = new Set(['Tab', 'Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Backspace']);

// Mouse look reference: Player turns LOOK_RAD_PER_PX radians per "pixel" of look delta at sensitivity 1.
export const LOOK_RAD_PER_PX = 0.0022;
const TOUCH_LOOK_GAIN = 1.35;       // 1.0 = the scene follows the finger exactly; a bit more feels right on small screens
const TOUCH_LOOK_TAU = 0.028;       // s, smoothing of touch look (preserves total distance)
const STICK_R = 54;                 // px, joystick travel radius
const STICK_DEAD = 0.12;            // dead zone (fraction of radius)
const UI_INTERACTIVE = 'button, a, input, select, textarea, label, [role="button"], [role="slider"], [role="dialog"], [data-interactive], [contenteditable="true"]';

const ICONS = {
  interact: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7.2 13.2V6.6a1.55 1.55 0 0 1 3.1 0v5.2M10.3 11.6V4.9a1.55 1.55 0 0 1 3.1 0v6.7M13.4 11.6V5.9a1.55 1.55 0 0 1 3.1 0v6.2M16.5 12.1V8.6a1.55 1.55 0 0 1 3.1 0v5.6c0 4.2-2.7 7.3-6.8 7.3h-1.1c-2.3 0-3.7-.8-4.9-2.2l-3.3-3.9a1.55 1.55 0 0 1 2.3-2.1l1.5 1.5"/></svg>',
  flashlight: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2.6 10.4h9.6l2.6-1.7h.9v6.6h-.9l-2.6-1.7H2.6a.9.9 0 0 1-.9-.9v-1.4a.9.9 0 0 1 .9-.9z"/><path d="M5.6 10.4V9.3h2.6v1.1"/><path class="ray" d="M18.2 9l3.2-1.6M18.6 12h3.4M18.2 15l3.2 1.6"/></svg>',
  crouch: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="13.2" cy="6.6" r="2.1"/><path d="M12.6 9.4l-1.9 7.2 4.9-2.6-.8 6.2M10.7 16.6l-.6 3.8M12.2 11.2l3.9 2.1M4.4 21.6h15.2M4.6 7.4l2.2 2.2 2.2-2.2M6.8 9.6V3.8"/></svg>',
  sprint: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="15.4" cy="4.3" r="2.1"/><path d="M14 7.7l-2.6 5.6M13.6 8.7l3.4 2 2-1.6M13 8.6l-3.2 1-1.8 2.6M11.4 13.3l-3.4 2.2-2.6-.8M11.4 13.3l2.8 2.8-1 4.4M2.2 8.2h3.4M1.4 11.4h3.2M2.2 14.6h2.4"/></svg>',
  pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8.6 6.2v11.6M15.4 6.2v11.6"/></svg>',
};

const CSS = `
.tc-root{position:fixed;inset:0;pointer-events:none;opacity:0;visibility:hidden;transition:opacity .25s ease,visibility 0s linear .25s;
  -webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;contain:layout style;
  --tc-sl:env(safe-area-inset-left,0px);--tc-sr:env(safe-area-inset-right,0px);--tc-st:env(safe-area-inset-top,0px);--tc-sb:env(safe-area-inset-bottom,0px)}
.tc-root.is-visible{opacity:1;visibility:visible;transition:opacity .25s ease,visibility 0s}
.tc-probe{position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;
  padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)}
.tc-btn{position:absolute;box-sizing:border-box;border-radius:50%;display:flex;align-items:center;justify-content:center;
  background:radial-gradient(circle at 50% 38%,rgba(40,34,27,.46),rgba(11,9,7,.40) 70%);
  border:1.5px solid rgba(233,223,201,.26);box-shadow:0 2px 10px rgba(0,0,0,.35),inset 0 1px 0 rgba(233,223,201,.08);
  color:rgba(233,223,201,.80);transform:translateZ(0) scale(1);transition:transform .09s ease,background .12s ease,border-color .2s ease,color .2s ease,opacity .2s ease}
.tc-btn svg{width:46%;height:46%;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round;filter:drop-shadow(0 1px 1px rgba(0,0,0,.6))}
.tc-btn.is-down{transform:translateZ(0) scale(.9);background:radial-gradient(circle at 50% 40%,rgba(233,223,201,.30),rgba(233,223,201,.12) 70%);border-color:rgba(233,223,201,.6);color:#fff}
.tc-btn.is-active{border-color:rgba(232,198,106,.75);color:var(--nightlight,#e8c66a)}
.tc-btn.is-off{opacity:0;transform:translateZ(0) scale(.6)}
.tc-btn .ray{opacity:.25;transition:opacity .15s}
.tc-btn.is-active .ray{opacity:1}
.tc-interact{width:84px;height:84px;right:calc(var(--tc-sr) + 30px);bottom:calc(var(--tc-sb) + 112px)}
.tc-interact svg{width:50%;height:50%}
.tc-interact::after{content:"";position:absolute;inset:-7px;border-radius:50%;border:2px solid rgba(232,198,106,.0);opacity:0;transition:opacity .2s}
.tc-interact.is-available{border-color:rgba(232,198,106,.9);color:var(--nightlight,#e8c66a);
  background:radial-gradient(circle at 50% 40%,rgba(232,198,106,.30),rgba(40,30,12,.42) 72%);box-shadow:0 0 22px rgba(232,198,106,.38),0 2px 10px rgba(0,0,0,.35)}
.tc-interact.is-available::after{border-color:rgba(232,198,106,.55);animation:tc-pulse 1.5s ease-out infinite}
@keyframes tc-pulse{0%{opacity:.85;transform:scale(.92)}100%{opacity:0;transform:scale(1.22)}}
.tc-crouch{width:62px;height:62px;right:calc(var(--tc-sr) + 26px);bottom:calc(var(--tc-sb) + 26px)}
.tc-sprint{width:68px;height:68px;right:calc(var(--tc-sr) + 124px);bottom:calc(var(--tc-sb) + 30px)}
.tc-flash{width:62px;height:62px;right:calc(var(--tc-sr) + 138px);bottom:calc(var(--tc-sb) + 132px)}
.tc-pause{width:56px;height:56px;right:calc(var(--tc-sr) + 14px);top:calc(var(--tc-st) + 12px);background:rgba(11,9,7,.30)}
.tc-pause svg{stroke-width:2.6;width:40%;height:40%}
.tc-root.is-hiding .tc-sprint,.tc-root.is-hiding .tc-crouch,.tc-root.is-hiding .tc-stick{opacity:.18}
.tc-stick{position:absolute;left:0;top:0;width:0;height:0;transition:opacity .2s}
.tc-stick-base{position:absolute;left:0;top:0;width:${STICK_R * 2 + 16}px;height:${STICK_R * 2 + 16}px;margin:-${STICK_R + 8}px 0 0 -${STICK_R + 8}px;border-radius:50%;
  box-sizing:border-box;border:1.5px solid rgba(233,223,201,.22);background:radial-gradient(circle,rgba(11,9,7,.10) 30%,rgba(11,9,7,.34) 72%,rgba(233,223,201,.06) 100%);
  opacity:.35;transition:opacity .18s ease,border-color .15s ease;will-change:transform}
.tc-stick-base::before{content:"";position:absolute;left:50%;top:-1px;width:18px;height:9px;margin-left:-9px;border-top:2px solid rgba(233,223,201,.0);
  border-radius:50% 50% 0 0;transition:border-color .15s}
.tc-stick-knob{position:absolute;left:0;top:0;width:54px;height:54px;margin:-27px 0 0 -27px;border-radius:50%;box-sizing:border-box;
  background:radial-gradient(circle at 50% 35%,rgba(233,223,201,.42),rgba(233,223,201,.16) 70%);border:1.5px solid rgba(233,223,201,.45);
  box-shadow:0 2px 8px rgba(0,0,0,.4);opacity:.35;transition:opacity .18s ease;will-change:transform}
.tc-stick.is-active .tc-stick-base{opacity:1}
.tc-stick.is-active .tc-stick-knob{opacity:.95}
.tc-stick.is-sprint .tc-stick-base{border-color:rgba(232,198,106,.7)}
.tc-stick.is-sprint .tc-stick-base::before{border-color:rgba(232,198,106,.9)}
.tc-hint{position:fixed;left:50%;top:58%;transform:translate(-50%,0);padding:8px 14px;border-radius:18px;background:rgba(11,9,7,.62);
  color:var(--paper,#e9dfc9);font:600 14px/1.2 var(--font-ui,system-ui,sans-serif);letter-spacing:.02em;pointer-events:none;opacity:0;transition:opacity .3s}
.tc-hint.is-visible{opacity:.9}
@media (max-height:360px){.tc-interact{width:74px;height:74px;bottom:calc(var(--tc-sb) + 96px)}.tc-flash{bottom:calc(var(--tc-sb) + 112px)}}
@media (prefers-reduced-motion:reduce){.tc-interact.is-available::after{animation:none;opacity:.6}}
`;

function detectTouch() {
  try {
    const q = new URLSearchParams(location.search);
    if (q.has('touch')) return q.get('touch') !== '0';
  } catch (_) { /* ignore */ }
  const mm = (s) => { try { return matchMedia(s).matches; } catch (_) { return false; } };
  if (mm('(pointer: coarse)')) return true;
  return (navigator.maxTouchPoints || 0) > 0 && mm('(hover: none)');
}

export class Input {
  constructor(game, touchRoot) {
    this.game = game;
    this.touchRoot = touchRoot;
    this.enabled = false;
    this.isTouch = detectTouch();
    this.move = { x: 0, y: 0 };
    this.look = { dx: 0, dy: 0 };
    this.pointerLocked = false;
    this.moveSource = null;
    this.sprintStick = false;

    this._keys = new Set();                 // physical key codes held
    this._keyHeld = Object.create(null);    // action -> count of held keys
    this._pressed = new Set();              // actions pressed since last endFrame
    this._mouseInteract = false;
    this._mdx = 0; this._mdy = 0;           // raw mouse deltas since last update
    this._ldx = 0; this._ldy = 0;           // injected look
    this._tAccX = 0; this._tAccY = 0;       // pending (unsmoothed) touch look
    this._lockFailed = false;
    this._wantLock = false;
    this._unlockedAt = -1e9;
    this._interactAvail = false;
    this._touchAllowed = true;
    this._touchVisible = false;
    this._touches = new Map();              // identifier -> { role, btn?, x, y, sx, sy, moved }
    this._stick = { id: null, cx: 0, cy: 0, x: 0, y: 0, mx: 0, my: 0, sprint: false };
    this._lookId = null;
    this._btnHeld = Object.create(null);    // action -> bool (touch)
    this._safe = { l: 0, r: 0, t: 0, b: 0 };
    this._lastCrouchCls = null; this._lastHideCls = null; this._lastFlashCls = null;
    this._hasFlash = false; this._flashOn = false;
    this._reducedMotion = false;
    for (const a of ACTIONS) this._keyHeld[a] = 0;
  }

  init() {
    const g = this.game;
    this._canvas = g.canvas || document.getElementById('game');
    try { this._reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (_) { /* ignore */ }

    // ---------------- keyboard
    addEventListener('keydown', (e) => this._onKey(e, true), { capture: true });
    addEventListener('keyup', (e) => this._onKey(e, false), { capture: true });
    addEventListener('blur', () => this._releaseAll());
    document.addEventListener('visibilitychange', () => { if (document.hidden) this._releaseAll(); });

    // ---------------- mouse / pointer lock
    document.addEventListener('pointerlockchange', () => this._onLockChange());
    document.addEventListener('pointerlockerror', () => { this._lockFailed = true; });
    this._dragLook = false;
    document.addEventListener('mousemove', (e) => this._onMouseMove(e));
    document.addEventListener('mousedown', (e) => this._onMouseDown(e));
    document.addEventListener('mouseup', (e) => { if (e.button === 0) this._mouseInteract = false; });
    document.addEventListener('wheel', (e) => {
      if (this._isGameTarget(e.target) && this.game.state === 'playing') {
        e.preventDefault();
        if (Math.abs(e.deltaY) > 2) this._pressed.add('next');
      }
    }, { passive: false });
    this._canvas?.addEventListener('contextmenu', (e) => e.preventDefault());

    // ---------------- touch
    this._buildTouchUI();
    const opt = { passive: false, capture: true };
    document.addEventListener('touchstart', (e) => this._onTouchStart(e), opt);
    document.addEventListener('touchmove', (e) => this._onTouchMove(e), opt);
    document.addEventListener('touchend', (e) => this._onTouchEnd(e), opt);
    document.addEventListener('touchcancel', (e) => this._onTouchEnd(e), opt);
    const stopGesture = (e) => e.preventDefault();
    document.addEventListener('gesturestart', stopGesture, { passive: false });
    document.addEventListener('gesturechange', stopGesture, { passive: false });
    document.addEventListener('dblclick', (e) => { if (this._isGameTarget(e.target)) e.preventDefault(); }, { passive: false });
    addEventListener('resize', () => this._measure());
    addEventListener('orientationchange', () => setTimeout(() => this._measure(), 250));

    // Reflect player state on the touch buttons.
    g.events.on('player:flashlight', (p) => { this._hasFlash = !!p?.has; this._flashOn = !!p?.on; });
    g.events.on('game:state', ({ state }) => { if (state !== 'playing') this._releaseTouches(); });
  }

  // ------------------------------------------------------------------ per-frame

  update(dt) {
    const en = this.enabled;
    const s = this.game.settings;
    const sens = Number(s?.get('sensitivity')) || 1;
    const inv = s?.get('invertY') ? -1 : 1;

    // ---- move
    let mx = 0, my = 0, src = null;
    if (en) {
      if (this._stick.id !== null && (this._stick.mx !== 0 || this._stick.my !== 0)) {
        mx = this._stick.mx; my = this._stick.my; src = 'touch';
      } else {
        const h = this._keyHeld;
        mx = (h.right > 0 ? 1 : 0) - (h.left > 0 ? 1 : 0);
        my = (h.fwd > 0 ? 1 : 0) - (h.back > 0 ? 1 : 0);
        if (mx !== 0 && my !== 0) { mx *= Math.SQRT1_2; my *= Math.SQRT1_2; }
        if (mx !== 0 || my !== 0) src = 'keys';
      }
    }
    this.move.x = mx; this.move.y = my; this.moveSource = src;
    this.sprintStick = en && this._stick.id !== null && this._stick.sprint;

    // ---- look (mouse raw + smoothed touch + injected)
    let dx = this._mdx + this._ldx, dy = this._mdy + this._ldy;
    this._mdx = this._mdy = this._ldx = this._ldy = 0;
    if (this._tAccX !== 0 || this._tAccY !== 0) {
      const k = dt > 0 ? 1 - Math.exp(-dt / TOUCH_LOOK_TAU) : 1;
      let ox = this._tAccX * k, oy = this._tAccY * k;
      if (Math.abs(this._tAccX - ox) < 0.05) ox = this._tAccX;   // flush tiny remainders
      if (Math.abs(this._tAccY - oy) < 0.05) oy = this._tAccY;
      this._tAccX -= ox; this._tAccY -= oy;
      // touch px -> mouse-equivalent px so that the scene tracks the finger (vertical FOV per screen height)
      const fov = (this.game.camera?.fov || 70) * Math.PI / 180;
      const conv = (fov / Math.max(200, innerHeight)) * TOUCH_LOOK_GAIN / LOOK_RAD_PER_PX;
      dx += ox * conv; dy += oy * conv;
    }
    if (en) { this.look.dx += dx * sens; this.look.dy += dy * sens * inv; }

    // ---- touch UI
    this._updateTouchUI();
  }

  endFrame() {
    this._pressed.clear();
    this.look.dx = 0; this.look.dy = 0;
  }

  pressed(a) { return this.enabled && this._pressed.has(a); }

  held(a) {
    if (!this.enabled) return false;
    if (this._keyHeld[a] > 0) return true;
    if (a === 'interact' && this._mouseInteract) return true;
    if (this._btnHeld[a]) return true;
    if (a === 'sprint' && this._stick.id !== null && this._stick.sprint) return true;
    return false;
  }

  setInteractAvailable(v, label) {
    v = !!v;
    if (v === this._interactAvail && label === this._interactLabel) return;
    this._interactAvail = v; this._interactLabel = label;
    if (this._btn?.interact) {
      this._btn.interact.classList.toggle('is-available', v);
      this._btn.interact.setAttribute('aria-label', v && label ? String(label) : 'Interagir');
    }
  }

  setTouchVisible(v) { this._touchAllowed = !!v; }

  injectLook(dx = 0, dy = 0) { this._ldx += dx; this._ldy += dy; }

  vibrate(p = 10) {
    if (!this.isTouch) return;
    try { navigator.vibrate?.(p); } catch (_) { /* ignore */ }
  }

  // ------------------------------------------------------------------ pointer lock

  lockPointer() {
    this._wantLock = true;
    if (this.isTouch || this.pointerLocked) return;
    const el = this._canvas;
    if (!el || !el.requestPointerLock) { this._lockFailed = true; return; }
    const gesture = !!this._gestureLock;
    this._gestureLock = false;
    const fail = () => {
      this._lockFailed = true;
      if (gesture && !this.pointerLocked) this._dragLook = true;
    };
    const fallback = () => {
      try {
        const p2 = el.requestPointerLock();
        if (p2 && typeof p2.catch === 'function') p2.catch(fail);
      } catch (_) { fail(); }
    };
    try {
      const p = el.requestPointerLock({ unadjustedMovement: true });
      if (p && typeof p.catch === 'function') {
        p.catch((err) => {
          // unadjustedMovement unsupported (NotSupportedError) -> retry plain; other errors: no user gesture etc.
          if (err && err.name === 'NotSupportedError') fallback();
          else fail();
        });
      }
    } catch (_) { fallback(); }
  }

  unlockPointer() {
    this._wantLock = false;
    if (document.pointerLockElement) { try { document.exitPointerLock(); } catch (_) { /* ignore */ } }
  }

  _onLockChange() {
    const locked = !!document.pointerLockElement && document.pointerLockElement === this._canvas;
    if (locked === this.pointerLocked) return;
    this.pointerLocked = locked;
    if (locked) { this._lockFailed = false; this._dragLook = false; }
    else { this._unlockedAt = performance.now(); this._mouseInteract = false; }
    this.game.events.emit('input:pointerlock', { locked });
  }

  // ------------------------------------------------------------------ keyboard / mouse handlers

  _onKey(e, down) {
    const code = e.code;
    const a = KEYMAP[code];
    // only while actually playing: modals keep native Tab focus navigation / arrow keys
    if (PREVENT.has(code) && this.enabled && this._isGameTarget(e.target)) e.preventDefault();
    if (down && e.ctrlKey && (code === 'KeyW' || code === 'KeyS' || code === 'KeyD')) e.preventDefault(); // crouch+move combos
    if (!a) return;
    if (down) {
      if (this._keys.has(code)) return; // auto-repeat
      this._keys.add(code);
      this._keyHeld[a]++;
      if (a === 'pause') { this._emitPause(code); return; }
      this._pressed.add(a);
    } else {
      if (!this._keys.has(code)) return;
      this._keys.delete(code);
      this._keyHeld[a] = Math.max(0, this._keyHeld[a] - 1);
    }
  }

  _emitPause(code) {
    const g = this.game;
    // Esc while pointer-locked (or just after the browser released it) is handled by the unlock -> pause path.
    if (code === 'Escape' && (this.pointerLocked || performance.now() - this._unlockedAt < 300)) return;
    if (g.state === 'playing' && g.ui?.isModalOpen?.()) return; // the modal handles its own Esc
    g.events.emit('input:pause');
  }

  _onMouseMove(e) {
    if (this.pointerLocked) {
      let mx = e.movementX || 0, my = e.movementY || 0;
      // drop rare browser spikes (known Chromium issue with pointer lock)
      if (Math.abs(mx) > 400 || Math.abs(my) > 400) return;
      this._mdx += mx; this._mdy += my;
    } else if (this._dragLook && (e.buttons & 1)) {
      this._mdx += e.movementX || 0; this._mdy += e.movementY || 0;
    }
  }

  _onMouseDown(e) {
    if (this.isTouch && e.sourceCapabilities?.firesTouchEvents) return;
    if (!this._isGameTarget(e.target)) return;
    const g = this.game;
    if (e.button === 0) {
      if (this.pointerLocked) {
        this._pressed.add('interact');
        this._mouseInteract = true;
      } else if (g.state === 'playing' && !g.ui?.isModalOpen?.()) {
        if (this._dragLook) {
          // pointer lock refused even on a real click: click = interact, drag = look (fallback mode)
          this._pressed.add('interact');
          this._mouseInteract = true;
        }
        this._gestureLock = true;
        this.lockPointer();
      }
    }
  }

  _isGameTarget(t) {
    if (!t || t === document || t === document.body || t === document.documentElement || t === window) return true;
    if (t === this._canvas) return true;
    if (!t.closest) return true;
    if (t.closest(UI_INTERACTIVE)) return false;
    return true;
  }

  _releaseAll() {
    this._keys.clear();
    for (const a of ACTIONS) this._keyHeld[a] = 0;
    this._mouseInteract = false;
    this._mdx = this._mdy = 0;
    this._releaseTouches();
  }

  // ------------------------------------------------------------------ touch UI

  _buildTouchUI() {
    const root = this.touchRoot || document.getElementById('touch');
    if (!root) return;
    if (!document.getElementById('tc-style')) {
      const st = document.createElement('style');
      st.id = 'tc-style';
      st.textContent = CSS;
      document.head.appendChild(st);
    }
    const el = document.createElement('div');
    el.className = 'tc-root';
    el.setAttribute('aria-hidden', 'true');
    const probe = document.createElement('div');
    probe.className = 'tc-probe';
    el.appendChild(probe);
    this._probe = probe;

    const stick = document.createElement('div');
    stick.className = 'tc-stick';
    stick.innerHTML = '<div class="tc-stick-base"></div><div class="tc-stick-knob"></div>';
    el.appendChild(stick);
    this._stickEl = stick;
    this._stickBase = stick.firstChild;
    this._stickKnob = stick.lastChild;

    const mk = (act, cls, label) => {
      const b = document.createElement('div');
      b.className = `tc-btn ${cls}`;
      b.setAttribute('role', 'presentation');
      b.setAttribute('aria-label', label);
      b.dataset.act = act;
      b.innerHTML = ICONS[act];
      el.appendChild(b);
      return b;
    };
    this._btn = {
      interact: mk('interact', 'tc-interact', 'Interagir'),
      flashlight: mk('flashlight', 'tc-flash is-off', 'Lampe de poche'),
      crouch: mk('crouch', 'tc-crouch', 'S’accroupir'),
      sprint: mk('sprint', 'tc-sprint', 'Courir'),
      pause: mk('pause', 'tc-pause', 'Pause'),
    };
    this._btnList = Object.values(this._btn);

    const hint = document.createElement('div');
    hint.className = 'tc-hint';
    hint.textContent = 'Clique pour contrôler la caméra';
    this._hint = hint;
    root.appendChild(el);
    root.appendChild(hint);
    this._touchEl = el;
    this._measure();
  }

  _measure() {
    if (this._probe) {
      try {
        const cs = getComputedStyle(this._probe);
        this._safe.t = parseFloat(cs.paddingTop) || 0;
        this._safe.r = parseFloat(cs.paddingRight) || 0;
        this._safe.b = parseFloat(cs.paddingBottom) || 0;
        this._safe.l = parseFloat(cs.paddingLeft) || 0;
      } catch (_) { /* ignore */ }
    }
    if (this._stick.id === null) this._placeStickIdle();
  }

  _stickHome() {
    const R = STICK_R + 8;
    return {
      x: this._safe.l + 34 + R,
      y: innerHeight - this._safe.b - 30 - R,
    };
  }

  _placeStickIdle() {
    if (!this._stickEl) return;
    const h = this._stickHome();
    this._setStickVisual(h.x, h.y, h.x, h.y);
  }

  _setStickVisual(cx, cy, kx, ky) {
    this._stickBase.style.transform = `translate3d(${cx.toFixed(1)}px,${cy.toFixed(1)}px,0)`;
    this._stickKnob.style.transform = `translate3d(${kx.toFixed(1)}px,${ky.toFixed(1)}px,0)`;
  }

  _updateTouchUI() {
    if (!this._touchEl) return;
    const g = this.game;
    const vis = this.isTouch && this._touchAllowed && this.enabled;
    if (vis !== this._touchVisible) {
      this._touchVisible = vis;
      this._touchEl.classList.toggle('is-visible', vis);
      if (!vis) this._releaseTouches();
      else this._measure();
    }
    // desktop: "click to look" hint when playing without pointer lock (not in automated/debug runs)
    const showHint = !this.isTouch && this.enabled && !this.pointerLocked && !this._dragLook && this._wantLock &&
      !g.params?.autostart && !g.debug && g.state === 'playing';
    if (showHint !== this._hintVisible) { this._hintVisible = showHint; this._hint?.classList.toggle('is-visible', showHint); }
    if (!vis) return;
    const p = g.player;
    const crouch = !!p?.crouched;
    if (crouch !== this._lastCrouchCls) { this._lastCrouchCls = crouch; this._btn.crouch.classList.toggle('is-active', crouch); }
    const hid = !!p?.hidden;
    if (hid !== this._lastHideCls) { this._lastHideCls = hid; this._touchEl.classList.toggle('is-hiding', hid); }
    const fl = (this._hasFlash ? 1 : 0) + (this._flashOn ? 2 : 0);
    if (fl !== this._lastFlashCls) {
      this._lastFlashCls = fl;
      this._btn.flashlight.classList.toggle('is-off', !this._hasFlash);
      this._btn.flashlight.classList.toggle('is-active', this._flashOn);
    }
    const sp = !!(p?.sprinting) || !!this._btnHeld.sprint;
    if (sp !== this._lastSprintCls) { this._lastSprintCls = sp; this._btn.sprint.classList.toggle('is-active', sp); }
  }

  _hitButton(x, y) {
    if (!this._btnList) return null;
    let best = null, bd = Infinity;
    for (const b of this._btnList) {
      if (b.classList.contains('is-off')) continue;
      const r = b.getBoundingClientRect();
      if (r.width === 0) continue;
      const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      const rad = r.width / 2 + 10; // generous hit radius for thumbs
      const d = Math.hypot(x - cx, y - cy);
      if (d <= rad && d < bd) { bd = d; best = b; }
    }
    return best;
  }

  _onTouchStart(e) {
    // A touch anywhere means this is a touch device, even if detection said otherwise (hybrid laptops).
    if (!this.isTouch && e.touches.length && this._isGameTarget(e.target)) this.isTouch = true;
    if (!this._touchVisible) {
      // still allow the update() following this event to show controls if needed
      if (this.isTouch && this.enabled && this._touchAllowed && this._isGameTarget(e.target)) e.preventDefault();
      return;
    }
    let handled = false;
    for (let i = 0; i < e.changedTouches.length; i++) {
      const t = e.changedTouches[i];
      const target = t.target;
      if (target && target.closest && !this._touchEl.contains(target) && target.closest(UI_INTERACTIVE)) continue;
      handled = true;
      const x = t.clientX, y = t.clientY;
      const btn = this._hitButton(x, y);
      if (btn) {
        const act = btn.dataset.act;
        this._touches.set(t.identifier, { role: 'btn', act, el: btn, x, y, sx: x, sy: y, moved: false });
        btn.classList.add('is-down');
        this.vibrate(8);
        if (act === 'pause') { this._emitPause('touch'); continue; }
        if (act === 'sprint') { this._btnHeld.sprint = true; continue; }
        this._pressed.add(act);
        if (act === 'interact') this._btnHeld.interact = true;
        continue;
      }
      if (x < innerWidth * 0.45 && this._stick.id === null) {
        this._startStick(t.identifier, x, y);
        this._touches.set(t.identifier, { role: 'stick', x, y, sx: x, sy: y, moved: false });
        continue;
      }
      if (this._lookId === null) {
        this._lookId = t.identifier;
        this._touches.set(t.identifier, { role: 'look', x, y, sx: x, sy: y, moved: false });
      }
    }
    if (handled) e.preventDefault();
  }

  _onTouchMove(e) {
    if (!this._touchVisible) { if (this.isTouch && this._isGameTarget(e.target)) e.preventDefault(); return; }
    let handled = false;
    for (let i = 0; i < e.changedTouches.length; i++) {
      const t = e.changedTouches[i];
      const rec = this._touches.get(t.identifier);
      if (!rec) continue;
      handled = true;
      const x = t.clientX, y = t.clientY;
      const dx = x - rec.x, dy = y - rec.y;
      rec.x = x; rec.y = y;
      if (rec.role === 'look') {
        this._tAccX += dx; this._tAccY += dy;
      } else if (rec.role === 'stick') {
        this._moveStick(x, y);
      } else if (rec.role === 'btn' && rec.act === 'sprint') {
        // holding sprint while dragging the same thumb also steers the view
        if (!rec.moved && Math.hypot(x - rec.sx, y - rec.sy) > 10) rec.moved = true;
        if (rec.moved) { this._tAccX += dx; this._tAccY += dy; }
      }
    }
    if (handled || this._touches.size) e.preventDefault();
  }

  _onTouchEnd(e) {
    let handled = false;
    for (let i = 0; i < e.changedTouches.length; i++) {
      const t = e.changedTouches[i];
      const rec = this._touches.get(t.identifier);
      if (!rec) continue;
      handled = true;
      this._touches.delete(t.identifier);
      if (rec.role === 'look') this._lookId = null;
      else if (rec.role === 'stick') this._endStick();
      else if (rec.role === 'btn') {
        rec.el.classList.remove('is-down');
        if (rec.act === 'sprint') this._btnHeld.sprint = false;
        if (rec.act === 'interact') this._btnHeld.interact = false;
      }
    }
    if (handled && e.cancelable) e.preventDefault();
  }

  _startStick(id, x, y) {
    const R = STICK_R + 10;
    const s = this._stick;
    s.id = id;
    s.cx = Math.min(Math.max(x, this._safe.l + R), innerWidth - R);
    s.cy = Math.min(Math.max(y, this._safe.t + R), innerHeight - this._safe.b - R);
    s.mx = 0; s.my = 0; s.sprint = false;
    this._stickEl.classList.add('is-active');
    this._moveStick(x, y);
  }

  _moveStick(x, y) {
    const s = this._stick;
    let dx = x - s.cx, dy = y - s.cy;
    let d = Math.hypot(dx, dy);
    // floating base: follow the thumb if it drifts far beyond the rim
    const follow = STICK_R * 1.7;
    if (d > follow) {
      const k = (d - follow) / d;
      s.cx += dx * k; s.cy += dy * k;
      dx = x - s.cx; dy = y - s.cy; d = follow;
    }
    // push past the rim toward the front = sprint
    const up = d > 0 ? -dy / d : 0;
    const wasSprint = s.sprint;
    s.sprint = d > STICK_R * (wasSprint ? 1.12 : 1.28) && up > (wasSprint ? 0.62 : 0.74);
    if (s.sprint !== wasSprint) {
      this._stickEl.classList.toggle('is-sprint', s.sprint);
      if (s.sprint) this.vibrate(12);
    }
    let m = Math.min(1, d / STICK_R);
    if (m < STICK_DEAD) m = 0;
    else { m = (m - STICK_DEAD) / (1 - STICK_DEAD); m = Math.min(1, Math.pow(m, 1.15) * 1.02); }
    if (d > 0 && m > 0) { s.mx = (dx / d) * m; s.my = (-dy / d) * m; } else { s.mx = 0; s.my = 0; }
    const kd = Math.min(d, STICK_R);
    const kx = d > 0 ? s.cx + (dx / d) * kd : s.cx, ky = d > 0 ? s.cy + (dy / d) * kd : s.cy;
    this._setStickVisual(s.cx, s.cy, kx, ky);
  }

  _endStick() {
    const s = this._stick;
    s.id = null; s.mx = 0; s.my = 0;
    if (s.sprint) { s.sprint = false; this._stickEl?.classList.remove('is-sprint'); }
    this._stickEl?.classList.remove('is-active');
    this._placeStickIdle();
  }

  _releaseTouches() {
    for (const rec of this._touches.values()) if (rec.el) rec.el.classList.remove('is-down');
    this._touches.clear();
    this._lookId = null;
    this._btnHeld.sprint = false; this._btnHeld.interact = false;
    this._tAccX = this._tAccY = 0;
    if (this._stick.id !== null) this._endStick();
  }
}
