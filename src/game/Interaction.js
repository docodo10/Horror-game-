import * as THREE from 'three';

// Interaction (gameplay module): camera-centre raycast against registered objects + world.occluders.
// Public API:
//   constructor(game); init(); update(dt)
//   register({ id, object, prompt, enabled?, onInteract, hold?, maxDistance?, ... }) -> unregister()
//       object: THREE.Object3D whose meshes are ray-tested (recursive)
//       prompt: string | () => string     e.g. 'Ouvrir le tiroir' (a falsy result makes the entry untargetable)
//       enabled: () => boolean            defaults to () => true
//       onInteract: () => void | Promise  the entry (and every other one) is locked until the promise settles
//       hold: seconds (number | () => number) to hold the interact button (progress ring), default 0
//       maxDistance: default 2.1 m
//     additions (optional):
//       onHoldStart / onHoldCancel: () => void   hold-to-use feedback (sound, noise)
//       holdPrompt: string | () => string        text shown while holding (default: prompt)
//       whenHidden: true                         the entry is the only target while the player hides (no raycast)
//   unregister(id)
//   .current   currently targeted entry or null
//   .busy      true while an onInteract promise runs
//   activate(id, { force }) -> Promise   run an entry programmatically (tests / QA), respects the busy lock
//   reset()    cancel holds / locks and clear the prompt (after being caught)
// The interaction ray starts at the camera and is blocked by world.occluders (first visible hit wins).

const DEFAULT_DISTANCE = 2.1;
const RAY_INTERVAL = 1 / 30;   // raycast at most 30x per second (+ immediately on a press)
const LOCK_TIMEOUT = 12;       // safety: a never-settling onInteract releases the lock after this (s, no modal open)

export class Interaction {
  constructor(game) {
    this.game = game;
    this.entries = new Map();
    this.current = null;
    this.busy = false;

    this._byObject = new Map();     // Object3D -> rec { obj, list: entry[] }
    this._recs = [];                // same records as an array (allocation-free iteration)
    this._raycaster = new THREE.Raycaster();
    this._origin = new THREE.Vector3();
    this._dir = new THREE.Vector3();
    this._targets = [];
    this._hits = [];
    this._rayT = 0;
    this._far = DEFAULT_DISTANCE;

    this._holding = null;           // entry being held
    this._holdT = 0;
    this._lockToken = 0;
    this._lockAge = 0;

    this._shownText = null;         // last prompt pushed to the UI
    this._shownHold = -1;
    this._available = false;
  }

  init() {
    this._raycaster.near = 0;
    this.game.events.on('game:state', ({ state }) => {
      if (state !== 'playing') { this._cancelHold(); this._setCurrent(null); this._showPrompt(null); }
    });
  }

  // ------------------------------------------------------------------ registration

  register(e) {
    if (!e || !e.id) { console.warn('[interaction] register: missing id', e); return () => {}; }
    if (!e.object) { console.warn('[interaction] register: missing object for', e.id); return () => {}; }
    if (this.entries.has(e.id)) this.unregister(e.id);
    const entry = {
      enabled: null, hold: 0, maxDistance: DEFAULT_DISTANCE,
      ...e,
    };
    this.entries.set(entry.id, entry);
    let rec = this._byObject.get(entry.object);
    if (!rec) { rec = { obj: entry.object, list: [] }; this._byObject.set(entry.object, rec); this._recs.push(rec); }
    rec.list.push(entry);
    this._recomputeFar();
    return () => this.unregister(entry.id);
  }

  unregister(id) {
    const entry = this.entries.get(id);
    if (!entry) return;
    this.entries.delete(id);
    const rec = this._byObject.get(entry.object);
    if (rec) {
      const i = rec.list.indexOf(entry);
      if (i >= 0) rec.list.splice(i, 1);
      if (!rec.list.length) {
        this._byObject.delete(entry.object);
        const j = this._recs.indexOf(rec);
        if (j >= 0) this._recs.splice(j, 1);
      }
    }
    if (this._holding === entry) this._cancelHold();
    if (this.current === entry) this._setCurrent(null);
    this._recomputeFar();
  }

  _recomputeFar() {
    let far = DEFAULT_DISTANCE;
    for (const e of this.entries.values()) if (e.maxDistance > far) far = e.maxDistance;
    this._far = far;
  }

  // ------------------------------------------------------------------ helpers

  _isEnabled(e) {
    try {
      if (e.enabled && !e.enabled()) return false;
      return !!this._text(e.prompt);
    } catch (err) {
      console.warn('[interaction] enabled/prompt failed for', e.id, err);
      return false;
    }
  }

  _text(p) { return typeof p === 'function' ? p() : p; }

  _holdTime(e) {
    const h = typeof e.hold === 'function' ? e.hold() : e.hold;
    return h > 0 ? h : 0;
  }

  _chainVisible(o) {
    for (let n = o; n; n = n.parent) if (n.visible === false) return false;
    return true;
  }

  /** First enabled entry attached to `obj` or one of its ancestors (most specific first). */
  _entryFor(obj) {
    for (let n = obj; n; n = n.parent) {
      const rec = this._byObject.get(n);
      if (rec) {
        const list = rec.list;
        for (let i = 0; i < list.length; i++) if (!list[i].whenHidden && this._isEnabled(list[i])) return list[i];
      }
    }
    return null;
  }

  // ------------------------------------------------------------------ per-frame

  update(dt) {
    const g = this.game;
    const input = g.input;
    if (this.busy) {
      this._lockAge += dt;
      if (this._lockAge > LOCK_TIMEOUT && !g.ui?.isModalOpen?.()) { console.warn('[interaction] lock timeout'); this._release(this._lockToken); }
    }

    const player = g.player;
    const cinematic = g.entity?.state === 'jumpscare' || (player?.cameraOverride && !player?.hidden);
    const active = g.state === 'playing' && !g.ui?.isModalOpen?.() && !cinematic && !this.busy;
    if (!active) {
      this._cancelHold();
      this._setCurrent(null);
      this._showPrompt(null);
      return;
    }

    const pressed = !!input?.pressed?.('interact');
    this._rayT -= dt;
    if (pressed || this._rayT <= 0 || (this.current && !this._isEnabled(this.current))) {
      this._rayT = RAY_INTERVAL;
      this._setCurrent(this._pick());
    }

    const cur = this.current;
    if (!cur) { this._cancelHold(); this._showPrompt(null); return; }

    const holdTime = this._holdTime(cur);
    if (this._holding && (this._holding !== cur || holdTime <= 0)) this._cancelHold();

    if (holdTime > 0) {
      if (!this._holding && pressed) {
        this._holding = cur; this._holdT = 0;
        try { cur.onHoldStart?.(); } catch (e) { console.warn(e); }
      }
      if (this._holding) {
        if (!input?.held?.('interact')) { this._cancelHold(); }
        else {
          this._holdT += dt;
          const k = Math.min(1, this._holdT / holdTime);
          this._showPrompt(this._text(cur.holdPrompt) || this._text(cur.prompt), k);
          if (k >= 1) { this._holding = null; this._holdT = 0; this._run(cur); }
          return;
        }
      }
      this._showPrompt(this._text(cur.prompt), 0);
      return;
    }

    this._showPrompt(this._text(cur.prompt));
    if (pressed) this._run(cur);
  }

  _pick() {
    const g = this.game;
    const player = g.player;
    if (player?.hidden) {
      for (const e of this.entries.values()) if (e.whenHidden && this._isEnabled(e)) return e;
      return null;
    }
    const cam = g.camera;
    cam.getWorldPosition(this._origin);
    cam.getWorldDirection(this._dir);
    const rc = this._raycaster;
    rc.set(this._origin, this._dir);
    rc.far = this._far;

    const targets = this._targets;
    targets.length = 0;
    const occ = g.world?.occluders;
    if (occ) for (let i = 0; i < occ.length; i++) targets.push(occ[i]);
    const recs = this._recs;
    for (let r = 0; r < recs.length; r++) {
      const list = recs[r].list;
      for (let i = 0; i < list.length; i++) {
        if (!list[i].whenHidden && this._isEnabled(list[i])) { targets.push(recs[r].obj); break; }
      }
    }
    const hits = this._hits;
    hits.length = 0;
    rc.intersectObjects(targets, true, hits);
    for (let i = 0; i < hits.length; i++) {
      const h = hits[i];
      if (!this._chainVisible(h.object)) continue;
      const mat = h.object.material;
      if (mat && !Array.isArray(mat) && mat.visible === false && !h.object.userData.interactProxy) continue;
      const e = this._entryFor(h.object);
      hits.length = 0;
      if (!e) return null;              // blocked by an occluder / non-interactive object
      return h.distance <= e.maxDistance ? e : null;
    }
    hits.length = 0;
    return null;
  }

  _setCurrent(e) {
    if (this.current === e) return;
    this.current = e;
    const avail = !!e;
    if (avail !== this._available || avail) {
      this._available = avail;
      try { this.game.input?.setInteractAvailable?.(avail, avail ? this._text(e.prompt) : undefined); } catch (err) { /* optional */ }
    }
  }

  _showPrompt(text, hold) {
    const t = text || null;
    const hv = hold === undefined ? -1 : Math.round(hold * 50) / 50;
    if (t === this._shownText && hv === this._shownHold) return;
    this._shownText = t; this._shownHold = hv;
    const ui = this.game.ui;
    if (!ui?.setPrompt) return;
    if (!t) { ui.setPrompt(null); return; }
    const touch = !!this.game.input?.isTouch;
    const opts = { key: touch ? '✋' : 'E', touch };
    if (hv >= 0) opts.hold = hv;
    ui.setPrompt(t, opts);
  }

  _cancelHold() {
    if (!this._holding) return;
    const e = this._holding;
    this._holding = null; this._holdT = 0;
    try { e.onHoldCancel?.(); } catch (err) { console.warn(err); }
  }

  // ------------------------------------------------------------------ running entries

  _run(entry) {
    if (this.busy) return Promise.resolve();
    const token = ++this._lockToken;
    this.busy = true; this._lockAge = 0;
    this._setCurrent(null);
    this._showPrompt(null);
    let p;
    try { p = entry.onInteract?.(); }
    catch (e) { console.error('[interaction]', entry.id, e); this._release(token); return Promise.resolve(); }
    return Promise.resolve(p)
      .catch((e) => console.error('[interaction]', entry.id, e))
      .finally(() => this._release(token));
  }

  _release(token) {
    if (token !== this._lockToken) return;
    this.busy = false; this._lockAge = 0;
    this._rayT = 0;
  }

  /** Run an entry by id (tests / QA / scripted). force=true ignores enabled(). */
  activate(id, { force = false } = {}) {
    const e = this.entries.get(id);
    if (!e) return Promise.resolve(false);
    if (!force && !this._isEnabled(e)) return Promise.resolve(false);
    return this._run(e).then(() => true);
  }

  reset() {
    this._cancelHold();
    this._lockToken++;
    this.busy = false; this._lockAge = 0;
    this._setCurrent(null);
    this._showPrompt(null);
  }
}
