import * as THREE from 'three';
import * as L from '../config/layout.js';

// =====================================================================================================================
// AudioEngine — sample-based 3D horror mixer (Web Audio), procedural synthesis as fallback.
//
// Public API (contract — kept from the stub, extended):
//   constructor(game); init(); unlock() (call from a user gesture); update(dt)
//   play(name, { position?, volume?, rate?, delay?, filterHz?, positional?, noJitter?, synth? })
//        -> handle { stop(fade?), setVolume(v), setPosition(v3), setRate(r, seconds?), setFilter(hz), playing }
//   loop(name, { position?, volume?, rate?, fadeIn?, filterHz?, offset?, unique?, synth? })
//        -> same handle (looping until stop()). Loops are idempotent per name (+ position within 1 m): calling
//           loop('clock_tick') twice returns two refs to ONE voice; the voice stops when every ref is stopped.
//           A loop created with no position whose handle later receives setPosition() becomes positional.
//   setFear(v 0..1)      heartbeat (slow → fast above 0.6), scared breathing, sub drone
//   setPaused(bool)      duck + muffle everything while paused
//   setMasterVolume(v)   0..1 (also driven by settings 'volume')
//   Extras: stopAll(fade), stats(), meter() -> {peakDb, rmsDb}, whenLoaded() -> Promise, names (all sound names)
//
// Sound names: see ARCHITECTURE.md §6 Audio + the recorded library (assets/audio/manifest.json). Unknown names log a
// warning once and do nothing. 'ambience' is an alias of 'room_tone'.
// Samples: manifest fetched at init(); files decoded with an OfflineAudioContext (no user gesture needed) — critical
// sounds during loading, the rest as soon as the level is up (menu) — first variation of every name before the extra
// variations. Anything not decoded yet (or missing) plays a procedural synthesis fallback; loops cross-fade to the
// recording once it is ready. Beds/drone (lo) are decoded at 24 kHz to save memory (~66 MB for the whole library).
//
// Graph: source → fade → volume(×occlusion) → [lowpass] → [HRTF panner] → category bus (sfx|foley|ambience|music|voice)
//        └→ reverb sends (small carpeted basement IR / darker longer IR for laundry nook + stairwell + upstairs hall)
//        buses + reverb returns → mix → pause lowpass → glue compressor → limiter → master volume → analyser → out.
// Self-driven layers (events): power hum + fan (spin up/down), room tone, furnace cycle, wind at the window, alarm
// clock tick, fear heartbeat/breath/drone, sprint panting from 'player:stamina', held breath while hidden, stinger +
// gasp on 'entity:spotted', chase music + ambience ducking on 'entity:state', random house life (creaks, steps above).
// Occlusion: sounds above the ceiling are lowpassed (~600 Hz); sounds in the upstairs hallway are muffled until
// world.handles['door.upstairs'].isOpen; laundry-nook ↔ room goes through the doorway (diffraction approximation).
// =====================================================================================================================

const TAU = Math.PI * 2;
const dbToGain = (d) => Math.pow(10, d / 20);
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const sstep = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;

const R = L.ROOM, ST = L.STAIRS, AL = L.ALCOVE, UH = L.UPPER_HALL, CL = L.CLOSET, WIN = L.WINDOW;

// Acoustic zones
const Z_ROOM = 0, Z_STAIR = 1, Z_NOOK = 2, Z_HALL = 3, Z_CEIL = 4, Z_CLOSET = 5, Z_WALL = 6, Z_OUT = 7;
const ZONE_NAMES = ['room', 'stairwell', 'nook', 'hall', 'ceiling', 'closet', 'wall', 'outside'];
const ZONE_ROOM = [1, 0.6, 0.15, 0.1, 0.35, 0.3, 0.4, 0.2];   // send to the small-room IR per source zone
const ZONE_LONG = [0, 0.5, 1, 0.75, 0, 0, 0, 0.15];           // send to the long/dark IR

const CATS = ['sfx', 'foley', 'ambience', 'music', 'voice'];
const CAT_LEVEL = { sfx: 1.0, foley: 0.92, ambience: 0.9, music: 0.8, voice: 1.0 };
const CAT_PRIO = { ambience: 0, sfx: 1, foley: 1, voice: 3, music: 3 };

// Sound definitions. g = default gain dB (manifest gainDb overrides), max = simultaneous voices, gap = min seconds
// between two plays (dedupe), ref/roll = distance model, rv = reverb send amount, pos = default position key,
// jit = pitch/volume jitter on one-shots, single = one shared loop instance whatever the position, lo = decode at
// 24 kHz (low-content beds: saves memory), mono = downmix to mono, ceil = force above the ceiling, rnd = random loop
// start offset, follow = loop follows the entity when no explicit position was given.
function S(cat, g, o) {
  return { cat, g, max: 4, gap: 0.025, ref: 1, roll: 1.1, rv: 1, jit: true, pos: null, single: false, lo: false, mono: false, ceil: false, rnd: false, follow: false, ...o };
}
const SOUNDS = {
  // ---- player body / foley
  footstep_carpet: S('foley', -6, { max: 3, rv: 0.55 }),
  footstep_wood: S('foley', -3, { max: 3, rv: 0.8 }),
  footstep_concrete: S('foley', 0, { max: 3, rv: 0.9 }),
  cloth_move: S('foley', -6, { max: 2, rv: 0.3 }),
  land_thump: S('foley', -4, { max: 2, rv: 0.8 }),
  player_breath_run: S('foley', 0, { rv: 0.06, jit: false, rnd: true }),
  player_breath_scared: S('foley', -2, { rv: 0.05, jit: false, rnd: true }),
  player_gasp: S('foley', -3, { max: 1, gap: 0.8, rv: 0.25 }),
  heartbeat: S('foley', -4, { rv: 0, jit: false, rnd: true }),
  heartbeat_fast: S('foley', -4, { rv: 0, jit: false, rnd: true }),
  heartbeat_single: S('foley', -3, { max: 2, rv: 0 }),
  pickup: S('foley', -4, { max: 2, rv: 0.5 }),
  paper: S('foley', -5, { max: 2, rv: 0.4 }),
  flashlight_click: S('foley', -6, { max: 2, gap: 0.12, rv: 0.4, ref: 0.5 }),
  battery_change: S('foley', -4, { max: 1, gap: 0.3, rv: 0.4 }),
  key_pickup: S('foley', -3, { max: 1, gap: 0.3, rv: 0.5 }),
  bump: S('foley', -3, { max: 2, gap: 0.25, rv: 1 }),
  // ---- world sfx
  door_creak_open: S('sfx', 0, { max: 2, ref: 1.4 }),
  door_close: S('sfx', -2, { max: 2, ref: 1.4 }),
  door_locked: S('sfx', -2, { max: 1, gap: 0.3, ref: 1.3 }),
  unlock: S('sfx', -2, { max: 1, gap: 0.3, ref: 1.2 }),
  drawer_open: S('sfx', -3, { max: 2 }),
  drawer_close: S('sfx', -3, { max: 2 }),
  cabinet_open: S('sfx', -4, { max: 2 }),
  cabinet_close: S('sfx', -4, { max: 2 }),
  box_open: S('sfx', -4, { max: 1, gap: 0.2 }),
  lock_wheel: S('sfx', -8, { max: 4, gap: 0.03, ref: 0.6 }),
  lock_fail: S('sfx', -3, { max: 1, gap: 0.2 }),
  lock_success: S('sfx', -2, { max: 1, gap: 0.3 }),
  breaker_flip: S('sfx', 0, { max: 1, gap: 0.3, ref: 1.5, pos: 'powerBox' }),
  power_up: S('sfx', -2, { max: 1, gap: 2.0, ref: 2, pos: 'light' }),
  light_pop: S('sfx', 0, { max: 1, gap: 0.4, ref: 1.6, pos: 'light' }),
  tv_static: S('sfx', 2, { ref: 1.1, pos: 'tv', jit: false, single: true, rnd: true }),
  tv_on: S('sfx', 0, { max: 1, gap: 0.2, pos: 'tv' }),
  tv_off: S('sfx', -2, { max: 1, gap: 0.2, pos: 'tv' }),
  rocking_chair: S('sfx', -4, { max: 2, gap: 0.15, pos: 'rocking' }),
  closet_enter: S('sfx', -3, { max: 1, gap: 0.3 }),
  closet_exit: S('sfx', -3, { max: 1, gap: 0.3 }),
  window_tap: S('sfx', -2, { max: 1, gap: 0.5, pos: 'window', ref: 1.2 }),
  clock_chime: S('sfx', 0, { max: 1, gap: 1, pos: 'grandfather', ref: 1.6 }),
  win_door: S('sfx', -2, { max: 1, gap: 1 }),
  stair_creak: S('sfx', -3, { max: 2, gap: 0.1, pos: 'stairs' }),
  house_creak: S('sfx', -6, { max: 2, gap: 0.2, pos: 'house', ref: 1.4 }),
  knock_wall: S('sfx', 0, { max: 1, gap: 1, pos: 'wall', ref: 1.4 }),
  // ---- ambience beds
  room_tone: S('ambience', -12, { rv: 0, jit: false, single: true, lo: true, rnd: true }),
  furnace: S('ambience', -6, { rv: 0.3, jit: false, single: true, pos: 'furnace', ref: 1.6, lo: true, rnd: true }),
  light_buzz: S('ambience', -6, { rv: 0.12, jit: false, single: true, pos: 'light', ref: 0.8, roll: 1.3, rnd: true }),
  fan_hum: S('ambience', -8, { rv: 0.3, jit: false, single: true, pos: 'fan', ref: 1.2, rnd: true }),
  clock_tick: S('ambience', -4, { rv: 0.25, jit: false, pos: 'alarmClock', ref: 0.45, roll: 1.4, rnd: true }),
  wind_outside: S('ambience', -10, { rv: 0.2, jit: false, pos: 'window', ref: 1.5, lo: true, mono: true, rnd: true }),
  ambience_drone: S('ambience', -8, { rv: 0, jit: false, single: true, lo: true, rnd: true }),
  // ---- the creature (never ducked)
  entity_step: S('voice', 0, { max: 3, ref: 1.3, pos: 'entityFeet' }),
  entity_step_stairs: S('voice', 0, { max: 3, ref: 1.3, pos: 'entityFeet' }),
  ceiling_steps: S('voice', 0, { max: 3, pos: 'ceiling', ref: 1.6, ceil: true }),
  ceiling_walk: S('voice', 0, { max: 1, gap: 3, pos: 'ceiling', ref: 1.6, ceil: true }),
  entity_breath: S('voice', -6, { max: 2, gap: 0.3, ref: 0.9, pos: 'entityHead' }),
  entity_croak: S('voice', -2, { max: 1, gap: 0.5, ref: 1.2, pos: 'entityHead' }),
  lullaby_hum: S('voice', 0, { ref: 1.2, jit: false, single: true, pos: 'entityHead', follow: true, lo: true }),
  whisper: S('voice', -4, { max: 2, gap: 0.4, ref: 0.7, pos: 'behind' }),
  giggle: S('voice', -6, { max: 1, gap: 1, pos: 'far' }),
  jumpscare: S('voice', 0, { max: 1, gap: 1.2, ref: 2.5, rv: 0.5 }),
  // ---- music
  stinger: S('music', -3, { max: 1, gap: 2.5, rv: 0, jit: false }),
  chase_music: S('music', -4, { rv: 0, jit: false, single: true }),
};
const ALIASES = { ambience: 'room_tone' };
const LIFE_NAMES = ['house_creak', 'stair_creak', 'ceiling_walk', 'ceiling_steps', 'knock_wall', 'window_tap', 'whisper', 'giggle'];
const DEFAULT_DEF = S('sfx', 0);

// Decode order after unlock(): gameplay-critical first, then the beds and POV layers, then everything else.
const CRITICAL = ['footstep_carpet', 'footstep_wood', 'drawer_open', 'drawer_close', 'door_creak_open', 'door_close', 'door_locked',
  'breaker_flip', 'light_pop', 'flashlight_click', 'heartbeat', 'jumpscare', 'stinger'];
const EARLY = ['room_tone', 'light_buzz', 'fan_hum', 'clock_tick', 'wind_outside', 'furnace', 'player_breath_run', 'player_gasp',
  'heartbeat_fast', 'player_breath_scared', 'ambience_drone', 'footstep_concrete', 'bump', 'pickup', 'paper', 'cloth_move',
  'power_up', 'house_creak', 'ceiling_steps', 'entity_step', 'entity_step_stairs', 'chase_music', 'lullaby_hum'];

const NOOP = Object.freeze({ stop() {}, setVolume() {}, setPosition() {}, setRate() {}, setFilter() {}, playing: false, name: '' });
const EMPTY = Object.freeze({});

// ---------------------------------------------------------------------------------------------------------- voices
class Voice {
  constructor(eng, name, def, rec, loop, entry) {
    this.eng = eng; this.name = name; this.def = def; this.rec = rec; this.loop = loop; this.entry = entry || null;
    this.synth = !!rec.synth;
    this.src = null; this.fade = null; this.vol = null; this.f = null; this.p = null; this.sR = null; this.sL = null;
    this.pos = null; this.zone = -1; this.oHz = 20000; this.occG = 1; this.filterHz = 0; this.v = 1; this.base = 1;
    this.jr = 1; this.rate = 1; this.t0 = 0; this.idx = -1; this.stopping = false; this.dead = false;
  }
  get playing() { return !this.dead && !this.stopping; }
  stop(fade = 0.05) { this.eng._stopVoice(this, fade); }
  setVolume(v) { if (this.dead) return; this.v = Math.max(0, +v || 0); this._gain(false); }
  _gain(init) {
    const g = this.base * this.v * this.occG;
    if (init) this.vol.gain.value = g;
    else this.vol.gain.setTargetAtTime(g, this.eng.ctx.currentTime, 0.05);
  }
  setPosition(p) {
    if (this.dead || !this.p || !p) return;
    const q = this.pos;
    if (Math.abs(p.x - q.x) + Math.abs(p.y - q.y) + Math.abs(p.z - q.z) < 0.004) return;
    q.set(p.x, p.y, p.z);
    this.eng._fixPos(this.def, q);
    this.eng._pannerPos(this.p, q);
  }
  setRate(r, seconds = 0.15) {
    if (this.dead) return;
    this.rate = r;
    this.src.playbackRate.setTargetAtTime(Math.max(0.05, r * this.jr), this.eng.ctx.currentTime, Math.max(0.01, seconds / 3));
  }
  setFilter(hz) {
    if (this.dead || !this.f) return;
    this.filterHz = hz || 0;
    this.f.frequency.setTargetAtTime(Math.min(this.oHz, this.filterHz || 20000), this.eng.ctx.currentTime, 0.08);
  }
}

// A shared looping sound (one voice, many owners).
class LoopEntry {
  constructor(name, def, o) {
    this.name = name; this.def = def; this.refs = 0; this.voice = null; this.stopped = false;
    this.volume = o.volume ?? 1; this.rate = o.rate ?? 1; this.filterHz = o.filterHz || 0;
    this.unique = !!o.unique; this.synthOnly = !!o.synth; this.offset = o.offset; this.fadeIn = o.fadeIn;
    this.grace = o.grace ?? 0.35; this.waitUntil = 0; this.positional = o.positional;
    this.position = o.position ? new THREE.Vector3().copy(o.position) : null;
    this.follow = !o.position && def.follow;
  }
}

// Handle returned by loop(): one per caller.
class LoopRef {
  constructor(eng, e) { this.eng = eng; this.e = e; this.live = true; }
  get playing() { return this.live && !this.e.stopped; }
  get name() { return this.e.name; }
  stop(fade = 0.5) { if (!this.live) return; this.live = false; this.eng._release(this.e, fade); }
  setVolume(v) { if (!this.live) return; this.e.volume = v; this.e.voice?.setVolume(v); }
  setRate(r, s) { if (!this.live) return; this.e.rate = r; this.e.voice?.setRate(r, s); }
  setFilter(hz) { if (!this.live) return; this.e.filterHz = hz || 0; this.e.voice?.setFilter(hz); }
  setPosition(p) {
    if (!this.live || !p) return;
    const e = this.e;
    e.follow = false;
    if (e.position) { e.position.set(p.x, p.y, p.z); e.voice?.setPosition(p); return; }
    e.position = new THREE.Vector3(p.x, p.y, p.z); // first position on a non-positional loop: respawn as positional
    e.positional = undefined;
    this.eng._respawn(e, 0.12);
  }
}

// Self-driven loop layer (volume follows a target with attack/release, auto start/stop).
class Layer {
  constructor(eng, name, opts) { this.eng = eng; this.name = name; this.opts = opts; this.ref = null; this.v = 0; this.sent = -1; this.sentRate = -1; this.sentF = -1; this.idle = 0; }
  update(dt, target, attack, release, rate, filterHz) {
    if (this.ref && !this.ref.playing) this.ref = null; // stopped from outside (stopAll)
    const k = target > this.v ? attack : release;
    this.v += (target - this.v) * Math.min(1, dt * k);
    if (target > 0.004 || this.v > 0.004) {
      this.idle = 0;
      if (!this.ref) {
        this.ref = this.eng.loop(this.name, { ...this.opts, volume: Math.max(this.v, 0.0001), rate: rate ?? 1, unique: true });
        this.sent = this.v; this.sentRate = rate ?? 1; this.sentF = filterHz ?? -1;
        if (this.ref === NOOP) { this.ref = null; return; }
      }
    } else if (this.ref) {
      this.idle += dt;
      if (this.idle > 1.5) { this.ref.stop(0.25); this.ref = null; this.v = 0; }
      return;
    }
    if (!this.ref) return;
    if (Math.abs(this.v - this.sent) > 0.004) { this.ref.setVolume(this.v); this.sent = this.v; }
    if (rate !== undefined && Math.abs(rate - this.sentRate) > 0.006) { this.ref.setRate(rate, 0.4); this.sentRate = rate; }
    if (filterHz !== undefined && Math.abs(filterHz - this.sentF) > this.sentF * 0.04) { this.ref.setFilter(filterHz); this.sentF = filterHz; }
  }
  kill(fade = 0.3) { if (this.ref) { this.ref.stop(fade); this.ref = null; } this.v = 0; this.sent = -1; }
}

// =====================================================================================================================
export class AudioEngine {
  constructor(game) {
    this.game = game;
    this.ctx = null;
    this.unlocked = false;
    this.voices = [];
    this.loops = [];
    this.samples = new Map();          // name -> sample entry (manifest)
    this.manifest = null;
    this.names = [...Object.keys(SOUNDS), ...Object.keys(ALIASES)];
    this._synth = new Map();           // name -> [rec] procedural fallbacks
    this._last = new Map();            // name -> ctx time of last play (dedupe)
    this._warned = new Set();
    this._stats = { decoded: 0, failed: 0, bytes: 0 };
    this._fetchQ = []; this._decQ = []; this._fetching = 0; this._decoding = 0;
    this._allDoneP = null; this._allDoneRes = null;
    this._userVol = 0.85; this._paused = false;
    this._fear = 0; this._stamina = 1; this._hidden = false; this._chase = false; this._entityState = 'dormant';
    this._gameState = 'loading'; this._power = true; this._doorOpen = false; this._flOn = false;
    this._lz = Z_ROOM; this._zoneT = 0; this._lowCpu = false; this._lowMem = false; this._maxVoices = 48;
    this._sendLevel = 0.32;
    this._dk = new Float32Array([1, 1, 1, 1]); this._dkHold = 0; this._dkRel = 1.5; this._chaseDuck = 1; this._catCur = new Float32Array(5).fill(-1);
    this._bedOn = false; this._furnOn = false; this._furnT = 0; this._furn = null;
    this._windT = 0; this._windTarget = 0.6; this._windV = 0.6; this._lifeT = 30;
    this._holdT = 3; this._holding = false; this._lastStairCreak = -10;
    this._room = null; this._clock = null; this._wind = null; this._buzz = null; this._fan = null;
    // scratch (no per-frame allocations)
    this._lpos = new THREE.Vector3(0, 1.6, 0); this._lf = new THREE.Vector3(0, 0, -1); this._lu = new THREE.Vector3(0, 1, 0);
    this._fwd = new THREE.Vector3(); this._up = new THREE.Vector3(); this._tmp = new THREE.Vector3(); this._tmp2 = new THREE.Vector3();
    this._oHz = 20000; this._oG = 1;
    // self-driven layers
    this._Lrun = new Layer(this, 'player_breath_run', { fadeIn: 0.4 });
    this._Lhb = new Layer(this, 'heartbeat', { fadeIn: 0.5 });
    this._Lhbf = new Layer(this, 'heartbeat_fast', { fadeIn: 0.5 });
    this._Lscared = new Layer(this, 'player_breath_scared', { fadeIn: 0.8 });
    this._Lhide = new Layer(this, 'player_breath_scared', { fadeIn: 1.0, filterHz: 1700 });
    this._Ldrone = new Layer(this, 'ambience_drone', { fadeIn: 3, filterHz: 350, grace: 8 });
    this._Lchase = new Layer(this, 'chase_music', { fadeIn: 0.35, offset: 0, grace: 1 });
  }

  // ------------------------------------------------------------------------------------------------ lifecycle
  init() {
    try {
      const g = this.game;
      this._userVol = clamp01(+(g.settings?.get?.('volume') ?? 0.85));
      const dm = navigator.deviceMemory;
      this._lowMem = !!(dm && dm <= 2);
      const ev = g.events;
      if (ev) {
        ev.on('power', (p) => this._setPower(!!p?.on, false));
        ev.on('player:stamina', (p) => { const v = +p?.value; if (Number.isFinite(v)) this._stamina = clamp01(v); });
        ev.on('player:hide', (p) => this._onHide(!!p?.hidden));
        ev.on('player:bump', () => this.play('bump', { volume: 0.85 }));
        ev.on('player:flashlight', (p) => this._onFlashlight(p));
        ev.on('entity:spotted', () => this._onSpotted());
        ev.on('entity:state', (p) => this._onEntityState(p?.state));
        ev.on('game:state', (p) => this._onGameState(p?.state));
        ev.on('settings:changed', (p) => { if (p?.key === 'volume') this.setMasterVolume(p.value); });
        ev.on('quality:changed', (p) => this._setQuality(p?.quality));
      }
      // iOS / Safari: resume (or re-resume after an interruption) on any gesture once unlocked.
      const resume = () => {
        const c = this.ctx;
        if (c && this.unlocked && c.state !== 'running' && c.state !== 'closed' && !document.hidden) c.resume().catch(() => {});
      };
      for (const t of ['pointerdown', 'touchstart', 'touchend', 'mousedown', 'keydown']) window.addEventListener(t, resume, { capture: true, passive: true });
      document.addEventListener('visibilitychange', () => {
        const c = this.ctx;
        if (!c || !this.unlocked) return;
        if (document.hidden) { if (c.state === 'running') { this._hideSuspended = true; c.suspend().catch(() => {}); } }
        else if (this._hideSuspended) { this._hideSuspended = false; c.resume().catch(() => {}); }
      });
      this._loadManifest();
    } catch (e) { this._warnOnce('init', '[audio] init', e); }
  }

  /** Must be called from a user gesture (Game.start). Creates/resumes the AudioContext and starts decoding + beds. */
  unlock() {
    try {
      if (!this.ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch (_) { /* Safari 17+: play even with the mute switch */ }
        this.ctx = new AC({ latencyHint: 'interactive' });
        this._setQuality(this.game.renderer?.quality);
        this._buildGraph();
      }
      const c = this.ctx;
      if (c.state !== 'running') c.resume().catch(() => {});
      // legacy iOS unlock: start a 1-sample silent buffer inside the gesture
      const b = c.createBuffer(1, 1, 22050), s = c.createBufferSource();
      s.buffer = b; s.connect(c.destination); s.start(0);
      if (!this.unlocked) {
        this.unlocked = true;
        this._startDecoding();
        this._applyMaster();
        this._startBed();
        for (let i = 0; i < this.loops.length; i++) this._startEntry(this.loops[i]); // loops requested before unlock
      }
    } catch (e) { this._warnOnce('unlock', '[audio] unlock', e); }
  }

  update(gameDt) {
    if (!this.unlocked || !this.ctx) return;
    try {
      // Internal timing runs on the audio clock (robust to frame drops / the game's dt cap; frozen while suspended).
      const now = this.ctx.currentTime;
      let dt = this._tPrev === undefined ? (gameDt || 0) : now - this._tPrev;
      this._tPrev = now;
      if (!(dt >= 0)) dt = 0;
      if (dt > 0.25) dt = 0.25;
      this._updateListener();
      const door = this.game.world?.handles?.['door.upstairs'];
      const open = !!door?.isOpen;
      if (open !== this._doorOpen) { this._doorOpen = open; this._zoneT = 0; }
      this._zoneT -= dt;
      if (this._zoneT <= 0) { this._zoneT = 0.1; this._updateZones(); }
      // pending loops (waiting for their sample) + entity-following loops
      const ent = this.game.entity;
      for (let i = 0; i < this.loops.length; i++) {
        const e = this.loops[i];
        if (!e.voice) { if (!e.stopped) this._startEntry(e); continue; }
        if (e.follow && ent?.position && e.voice.p) {
          this._tmp.set(ent.position.x, ent.position.y + 1.7, ent.position.z);
          e.voice.setPosition(this._tmp);
        }
      }
      this._updateLayers(dt);
      this._updateBuses(dt);
      this._updateBed(dt);
      this._updateLife(dt);
    } catch (e) { this._warnOnce('update', '[audio] update', e); }
  }

  // ------------------------------------------------------------------------------------------------ public API
  play(name, o = EMPTY) {
    try {
      name = ALIASES[name] || name;
      let def = this._def(name);
      if (!def) return NOOP;
      if (!this.unlocked || !this.ctx) return NOOP;
      const now = this.ctx.currentTime;
      o = o || EMPTY;
      if ((name === 'footstep_carpet' || name === 'footstep_wood') && !o.synth) {
        // surface awareness for player footsteps (laundry nook = painted concrete) + creaky stairs under the player
        const z = o.position ? this._zoneOf(o.position) : this._lz;
        if (z === Z_NOOK) {
          name = 'footstep_concrete'; def = SOUNDS.footstep_concrete;
        } else if (!o.position && name === 'footstep_wood' && this.game.player?.onStairs && Math.random() < 0.22 && now - this._lastStairCreak > 1.8) {
          this._lastStairCreak = now;
          this.play('stair_creak', { position: this._tmp2.set(this._lpos.x, this._lpos.y - 1.45, this._lpos.z), volume: 0.3, delay: 0.04 });
        }
      }
      const last = this._last.get(name);
      if (last !== undefined && now - last < def.gap) return NOOP;
      this._last.set(name, now);
      const rec = o.synth ? this._synthRec(name) : (this._sampleRec(name) || this._synthRec(name));
      if (!rec) return NOOP;
      this._admit(name, def);
      if (name === 'jumpscare') { this._duck(0.08, 0.25, 0.2, 0, 1.8, 1.4); this._Lchase.kill(0.04); }
      else if (name === 'stinger') this._duck(0.3, 0.75, 0.85, 1, 0.8, 2.2);
      else if (name === 'light_pop' || name === 'breaker_flip') this._duck(0.6, 1, 1, 1, 0.25, 1.2);
      return this._spawn(name, def, rec, o, false, null, 0);
    } catch (e) { this._warnOnce('play:' + name, `[audio] play ${name}`, e); return NOOP; }
  }

  loop(name, o = EMPTY) {
    try {
      name = ALIASES[name] || name;
      const def = this._def(name);
      if (!def) return NOOP;
      o = o || EMPTY;
      let e = o.unique ? null : this._findLoop(name, def, o.position);
      if (e) {
        if (o.volume !== undefined) { e.volume = o.volume; e.voice?.setVolume(o.volume); }
        if (o.position) {
          e.follow = false;
          if (e.position) { e.position.copy(o.position); e.voice?.setPosition(o.position); }
        }
      } else {
        e = new LoopEntry(name, def, o);
        if (!e.position && def.pos && o.positional !== false) { e.position = new THREE.Vector3(); this._defaultPos(def.pos, e.position); }
        this.loops.push(e);
        if (this.unlocked) this._startEntry(e);
      }
      e.refs++;
      return new LoopRef(this, e);
    } catch (err) { this._warnOnce('loop:' + name, `[audio] loop ${name}`, err); return NOOP; }
  }

  setFear(v) { const f = +v; if (Number.isFinite(f)) this._fear = clamp01(f); }

  setPaused(p) {
    this._paused = !!p;
    this._applyMaster();
    if (this.pauseF) this.pauseF.frequency.setTargetAtTime(this._paused ? 850 : 20000, this.ctx.currentTime, 0.12);
  }

  setMasterVolume(v) { const x = +v; if (Number.isFinite(x)) { this._userVol = clamp01(x); this._applyMaster(); } }

  stopAll(fade = 0.5) {
    for (let i = this.loops.length - 1; i >= 0; i--) { const e = this.loops[i]; e.refs = 1; this._release(e, fade); }
    for (let i = this.voices.length - 1; i >= 0; i--) this.voices[i].stop(fade);
    for (const l of [this._Lrun, this._Lhb, this._Lhbf, this._Lscared, this._Lhide, this._Ldrone, this._Lchase]) l.kill(fade);
    this._room = this._clock = this._wind = this._buzz = this._fan = this._furn = null;
    this._bedOn = false;
  }

  /** Debug / test helpers. */
  stats() {
    let files = 0, ready = 0;
    for (const s of this.samples.values()) { files += s.files.length; ready += s.ready.length; }
    return {
      unlocked: this.unlocked, state: this.ctx?.state ?? 'none', sampleRate: this.ctx?.sampleRate ?? 0,
      names: this.samples.size, files, decoded: this._stats.decoded, failed: this._stats.failed, ready,
      decodedMB: +(this._stats.bytes / 1048576).toFixed(1), voices: this.voices.length,
      loops: this.loops.map((e) => e.name + (e.voice ? (e.voice.synth ? '*' : '') : '(…)')),
      synth: [...this._synth.keys()], listenerZone: ZONE_NAMES[this._lz], lowMem: this._lowMem,
    };
  }

  meter() {
    if (!this.analyser) return null;
    if (!this._meterBuf) { this.analyser.fftSize = 32768; this._meterBuf = new Float32Array(32768); }
    const d = this._meterBuf;
    this.analyser.getFloatTimeDomainData(d);
    let pk = 0, s = 0;
    for (let i = 0; i < d.length; i++) { const a = Math.abs(d[i]); if (a > pk) pk = a; s += d[i] * d[i]; }
    return { peakDb: +(20 * Math.log10(pk || 1e-9)).toFixed(1), rmsDb: +(10 * Math.log10(s / d.length || 1e-18)).toFixed(1) };
  }

  whenLoaded() {
    if (!this._allDoneP) this._allDoneP = new Promise((res) => { this._allDoneRes = res; });
    this._checkDone();
    return this._allDoneP;
  }

  // ------------------------------------------------------------------------------------------------ graph
  _buildGraph() {
    const c = this.ctx;
    const gain = (v = 1) => { const g = c.createGain(); g.gain.value = v; return g; };
    const lowpass = (hz) => { const f = c.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = hz; f.Q.value = 0.5; return f; };
    this.master = gain(0);
    this.analyser = c.createAnalyser(); this.analyser.fftSize = 2048;
    const glue = c.createDynamicsCompressor();
    glue.threshold.value = -20; glue.knee.value = 10; glue.ratio.value = 2.5; glue.attack.value = 0.012; glue.release.value = 0.28;
    const lim = c.createDynamicsCompressor();
    lim.threshold.value = -2; lim.knee.value = 0; lim.ratio.value = 20; lim.attack.value = 0.001; lim.release.value = 0.1;
    this.pauseF = lowpass(20000);
    this.mix = gain(0.95);
    this.mix.connect(this.pauseF); this.pauseF.connect(glue); glue.connect(lim); lim.connect(this.master);
    this.master.connect(this.analyser); this.analyser.connect(c.destination);
    this.ambF = lowpass(20000); this.ambF.connect(this.mix);
    // reverbs: small carpeted basement + darker/longer (concrete nook, stairwell, hall)
    const low = this._lowCpu;
    this.convRoom = c.createConvolver();
    this.convRoom.buffer = this._makeIR(low ? 0.7 : 1.0, 0.5, 7000, 1500, 0.003, 11, false);
    this.convLong = c.createConvolver();
    this.convLong.buffer = this._makeIR(low ? 1.3 : 1.9, 1.15, 4800, 800, 0.006, 23, true);
    const retRoom = gain(0.9), retLong = gain(0.85);
    this.convRoom.connect(retRoom); retRoom.connect(this.mix);
    this.convLong.connect(retLong); retLong.connect(this.mix);
    this.cats = {};
    for (const n of CATS) {
      const dry = gain(CAT_LEVEL[n]);
      dry.connect(n === 'ambience' ? this.ambF : this.mix);
      const cat = { dry, wR: null, wL: null };
      if (n !== 'music') {
        cat.wR = gain(CAT_LEVEL[n]); cat.wR.connect(this.convRoom);
        cat.wL = gain(CAT_LEVEL[n]); cat.wL.connect(this.convLong);
      }
      this.cats[n] = cat;
    }
  }

  /** Stereo impulse response: pre-delay, early reflections, diffuse tail with frequency-dependent damping. */
  _makeIR(dur, rt60, f0, f1, pre, seed, flutter) {
    const c = this.ctx, sr = c.sampleRate, n = Math.max(1, Math.floor(dur * sr));
    const buf = c.createBuffer(2, n, sr);
    const early = flutter
      ? [[0.0062, 0.55], [0.0105, 0.42], [0.0151, 0.38], [0.0198, 0.3], [0.0246, 0.27], [0.0293, 0.22], [0.0341, 0.2], [0.0389, 0.16], [0.0437, 0.13]]
      : [[0.0034, 0.5], [0.0052, 0.38], [0.0079, 0.33], [0.0101, 0.26], [0.0127, 0.22], [0.0163, 0.18], [0.0198, 0.13], [0.0241, 0.1]];
    for (let ch = 0; ch < 2; ch++) {
      const d = buf.getChannelData(ch), r = rngOf(seed * 977 + ch * 131);
      const ip = Math.floor(pre * sr), ramp = 0.014 * sr, k60 = 6.9078 / rt60;
      let a = 0, b = 0;
      for (let i = 0; i < n; i++) {
        const t = i / sr;
        const fc = f1 + (f0 - f1) * Math.exp(-t / (rt60 * 0.3));
        const cf = 1 - Math.exp(-TAU * fc / sr);
        const w = r() * 2 - 1;
        a += (w - a) * cf; b += (a - b) * cf;
        const env = i < ip ? 0 : Math.exp(-k60 * t) * Math.min(1, (i - ip) / ramp);
        d[i] = b * env * 2.2;
      }
      for (let k = 0; k < early.length; k++) {
        const [tt, g] = early[k];
        const j = Math.floor((tt + (ch ? 0.00041 * (k % 3) : 0.00027 * ((k + 1) % 3))) * sr);
        const sgn = r() < 0.5 ? -1 : 1;
        if (j + 2 < n) { d[j] += sgn * g * 0.6; d[j + 1] += sgn * g * 0.3; d[j + 2] += sgn * g * 0.1; }
      }
      // fade the very end
      const fl = Math.min(n, Math.floor(0.05 * sr));
      for (let i = 0; i < fl; i++) d[n - 1 - i] *= i / fl;
    }
    return buf;
  }

  _applyMaster() {
    if (!this.master || !this.ctx) return;
    const v = Math.pow(this._userVol, 1.5) * (this._paused ? 0.28 : 1);
    this.master.gain.setTargetAtTime(v, this.ctx.currentTime, 0.08);
  }

  _setQuality(q) {
    this._lowCpu = q === 'low';
    this._maxVoices = this._lowCpu ? 30 : 48;
  }

  // ------------------------------------------------------------------------------------------------ sample library
  _base() {
    let b = this.game.assets?.base ?? './assets/';
    if (!b.endsWith('/')) b += '/';
    return b;
  }

  _url(f) {
    if (/^(https?:|\/|\.\/|\.\.\/)/.test(f)) return f;
    if (f.startsWith('assets/')) return this._base() + f.slice(7);
    return './' + f;
  }

  async _loadManifest() {
    try {
      const res = await fetch(this._base() + 'audio/manifest.json');
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const j = await res.json();
      for (const name of Object.keys(j)) {
        const m = j[name];
        if (!m || !Array.isArray(m.files) || !m.files.length) continue;
        this.samples.set(name, {
          name, files: m.files.map((f) => this._url(f)), loop: !!m.loop, gainDb: Number.isFinite(+m.gainDb) ? +m.gainDb : (SOUNDS[name]?.g ?? 0),
          ready: [], last: -1, bytes: null, fs: null, done: 0, nDec: 0, fail: 0,
        });
      }
      this.manifest = j;
    } catch (e) {
      this.manifest = {};
      console.warn('[audio] manifest indisponible — sons procéduraux uniquement.', e?.message || e);
    }
    // network prefetch + decode. Decoding uses an OfflineAudioContext (no user gesture needed), so the library is
    // ready before the first sound: critical sounds now, everything else once the level has loaded (or at unlock).
    for (const n of this._order()) this._fetchQ.push(this.samples.get(n));
    for (const s of this.samples.values()) {
      s.nDec = this._lowMem && s.loop ? Math.min(2, s.files.length) : s.files.length;
      s.fs = new Uint8Array(s.files.length); // 0 idle, 1 queued, 2 decoding, 3 done/failed
    }
    this._queueDecode(CRITICAL);
    if (this.unlocked || this._gameState !== 'loading') this._startDecoding();
    this._pump();
    this._checkDone();
  }

  _order() {
    const out = [], seen = new Set();
    const add = (n) => { if (!seen.has(n) && this.samples.has(n)) { seen.add(n); out.push(n); } };
    CRITICAL.forEach(add); EARLY.forEach(add);
    for (const n of this.samples.keys()) add(n);
    return out;
  }

  /** Queue the first variation of each name (in order), then their remaining variations. */
  _queueDecode(names) {
    for (let pass = 0; pass < 2; pass++) {
      for (const n of names) {
        const s = this.samples.get(n);
        if (!s || !s.fs) continue;
        for (let i = pass ? 1 : 0; i < (pass ? s.nDec : Math.min(1, s.nDec)); i++) {
          if (s.fs[i] === 0) { s.fs[i] = 1; this._decQ.push(s, i); }
        }
      }
    }
  }

  _startDecoding() {
    if (this._decStarted || !this.manifest) return;
    this._decStarted = true;
    this._queueDecode(this._order());
    this._pump();
    this._checkDone();
  }

  _pump() {
    const fetchConc = this.unlocked || this._gameState !== 'loading' ? 4 : 2;
    while (this._fetching < fetchConc && this._fetchQ.length) {
      const s = this._fetchQ.shift();
      if (s.bytes) continue;
      this._fetching++;
      Promise.allSettled(this._fetchEntry(s)).then(() => { this._fetching--; this._pump(); });
    }
    if (!this._decCtx(false)) return;
    const conc = this._gameState === 'loading' ? 1 : 3;
    while (this._decoding < conc && this._decQ.length) {
      const s = this._decQ.shift(), i = this._decQ.shift(); // flat queue of (entry, fileIndex) pairs
      if (s.fs[i] !== 1) continue;
      s.fs[i] = 2;
      this._decoding++;
      this._decodeFile(s, i).then(() => { this._decoding--; this._pump(); this._checkDone(); });
    }
  }

  _fetchEntry(s) {
    if (!s.bytes) {
      s.bytes = s.files.map((url) => {
        const p = fetch(url).then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.arrayBuffer(); });
        p.catch(() => {}); // handled where awaited
        return p;
      });
    }
    return s.bytes;
  }

  async _decodeFile(s, i) {
    try {
      const bytes = this._fetchEntry(s);
      const ab = await bytes[i];
      bytes[i] = null; // decodeAudioData detaches it anyway
      const buf = await this._decode(ab, s.name);
      const rec = this._prep(buf, s);
      s.ready.push(rec);
      this._stats.decoded++;
      this._stats.bytes += rec.buf.length * rec.buf.numberOfChannels * 4;
      if (s.ready.length === 1) this._onDecoded(s);
    } catch (e) {
      s.fail++; this._stats.failed++;
      this._warnOnce('dec:' + s.files[i], `[audio] échec du son ${s.files[i]}`, e);
    }
    s.fs[i] = 3;
    s.done++;
  }

  /** Decode context: an OfflineAudioContext (works before the user gesture), else the realtime one. */
  _decCtx(lo) {
    if (this._dc === undefined) {
      const OAC = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      try { this._dc = OAC ? new OAC(1, 1, 44100) : null; } catch (_) { this._dc = null; }
      try { this._lo = OAC ? new OAC(1, 1, 24000) : null; } catch (_) { this._lo = null; }
    }
    return (lo && this._lo) || this._dc || this.ctx;
  }

  _decode(ab, name) {
    const c = this._decCtx(!!SOUNDS[name]?.lo);
    return new Promise((res, rej) => {
      const p = c.decodeAudioData(ab, res, rej);
      if (p && typeof p.then === 'function') p.then(res, rej);
    });
  }

  /** Post-process a decoded buffer: optional downmix, trims, loop seam safety. */
  _prep(buf, s) {
    const def = SOUNDS[s.name] || DEFAULT_DEF;
    if (buf.numberOfChannels > 1 && (def.mono || (this._lowMem && def.cat !== 'music'))) {
      const m = this._decCtx(false).createBuffer(1, buf.length, buf.sampleRate), d = m.getChannelData(0);
      const a = buf.getChannelData(0), b = buf.getChannelData(1);
      for (let i = 0; i < d.length; i++) d[i] = (a[i] + b[i]) * 0.6;
      buf = m;
    }
    const d0 = buf.getChannelData(0), n = d0.length, sr = buf.sampleRate, nch = buf.numberOfChannels;
    let ls = 0, le = n;
    if (s.loop) {
      // trim digital silence (encoder padding) at both ends
      const lim = Math.min(4096, n >> 3);
      while (ls < lim && Math.abs(d0[ls]) < 2e-5) ls++;
      while (le > n - lim && Math.abs(d0[le - 1]) < 2e-5) le--;
      if (ls >= lim) ls = 0;
      if (le <= n - lim) le = n;
      // seam check: a large jump at the wrap → tiny fade dip (inaudible) to kill the click
      if (Math.abs(d0[le - 1] - d0[ls]) > 0.03) {
        const K = Math.min(160, (le - ls) >> 4);
        for (let ch = 0; ch < nch; ch++) {
          const d = buf.getChannelData(ch);
          for (let k = 0; k < K; k++) { const w = 0.5 - 0.5 * Math.cos(Math.PI * k / K); d[ls + k] *= w; d[le - 1 - k] *= w; }
        }
      }
    } else {
      const lim = Math.min(n >> 2, Math.floor(sr * 0.08));
      while (ls < lim && Math.abs(d0[ls]) < 0.0008) ls++;
      if (ls > 32) ls -= 32; else ls = 0; // keep a hair of pre-roll
    }
    return { buf, ls: ls / sr, le: le / sr, gainDb: s.gainDb, synth: false };
  }

  _onDecoded(s) {
    for (let i = 0; i < this.loops.length; i++) {
      const e = this.loops[i];
      if (e.name !== s.name || e.stopped || e.synthOnly) continue;
      if (!e.voice) this._startEntry(e);
      else if (e.voice.synth) { const old = e.voice; e.voice = null; this._startEntry(e, 1.2); old.stop(1.2); }
    }
  }

  _checkDone() {
    if (!this._allDoneRes || !this.manifest) return;
    if ((this._decStarted && !this._decQ.length && !this._decoding) || !this.samples.size) { this._allDoneRes(this.stats()); this._allDoneRes = null; }
  }

  /** A sound was requested before it was decoded: decode its first variation next. */
  _bump(s) {
    if (!s.fs || s.ready.length || s.fs[0] >= 2) return;
    if (s.fs[0] === 1) {
      for (let k = 0; k < this._decQ.length; k += 2) if (this._decQ[k] === s && this._decQ[k + 1] === 0) { this._decQ.splice(k, 2); break; }
    }
    s.fs[0] = 1;
    this._decQ.unshift(s, 0);
    this._pump();
  }

  _sampleRec(name) {
    const s = this.samples.get(name);
    if (!s) return null;
    const n = s.ready.length;
    if (!n) { this._bump(s); return null; }
    let i = 0;
    if (n > 1) {
      if (s.last >= 0 && s.last < n) { i = Math.floor(Math.random() * (n - 1)); if (i >= s.last) i++; }
      else i = Math.floor(Math.random() * n);
    }
    s.last = i;
    return s.ready[i];
  }

  _synthRec(name) {
    const spec = SYN[name];
    if (!spec || !this.ctx) return null;
    let list = this._synth.get(name);
    if (!list) { list = []; this._synth.set(name, list); }
    const maxVar = spec.loop ? 1 : (spec.vars || 3);
    if (list.length < maxVar) {
      const rec = this._renderSynth(name, spec, list.length);
      if (rec) { list.push(rec); list.last = list.length - 1; return rec; }
    }
    if (!list.length) return null;
    let i = Math.floor(Math.random() * list.length);
    if (list.length > 1 && i === list.last) i = (i + 1) % list.length;
    list.last = i;
    return list[i];
  }

  _renderSynth(name, spec, variant) {
    try {
      const sr = spec.sr || 32000, r = rngOf(hashStr(name) + variant * 7919 + 1);
      const dur = typeof spec.d === 'function' ? spec.d(r) : spec.d;
      const N = Math.max(64, Math.ceil(dur * sr));
      const o = new Float32Array(N);
      WRAP = !!spec.loop;
      try { spec.g(o, sr, r, N, variant); } finally { WRAP = false; }
      // level: one-shots peak-normalized to -1 dBFS, loops to -20 dBFS RMS (like the recorded library)
      let pk = 0, ss = 0;
      for (let i = 0; i < N; i++) { const a = Math.abs(o[i]); if (a > pk) pk = a; ss += o[i] * o[i]; }
      if (pk > 0) {
        let k = spec.loop ? 0.1 / Math.sqrt(ss / N) : 0.89 / pk;
        if (pk * k > 0.95) k = 0.95 / pk;
        for (let i = 0; i < N; i++) o[i] *= k;
      }
      const buf = this.ctx.createBuffer(1, N, sr);
      buf.getChannelData(0).set(o);
      const gainDb = this.samples.get(name)?.gainDb ?? SOUNDS[name]?.g ?? 0;
      return { buf, ls: 0, le: N / sr, gainDb, synth: true };
    } catch (e) { this._warnOnce('syn:' + name, `[audio] synthèse ${name}`, e); return null; }
  }

  _def(name) {
    const d = SOUNDS[name] || (this.samples.has(name) ? DEFAULT_DEF : null);
    if (!d) this._warnOnce('unknown:' + name, `[audio] son inconnu : "${name}"`);
    return d;
  }

  // ------------------------------------------------------------------------------------------------ voices
  _spawn(name, def, rec, o, loop, entry, fadeIn) {
    const c = this.ctx, now = c.currentTime, cat = this.cats[def.cat] || this.cats.sfx;
    const v = new Voice(this, name, def, rec, loop, entry);
    const src = c.createBufferSource();
    src.buffer = rec.buf; v.src = src;
    let jr = 1, jg = 0;
    if (!loop && def.jit && !o.noJitter) { jr = 1 + (Math.random() * 2 - 1) * 0.03; jg = (Math.random() * 2 - 1) * 2; }
    v.jr = jr; v.rate = o.rate ?? 1;
    src.playbackRate.value = Math.max(0.05, v.rate * jr);
    v.base = dbToGain(rec.gainDb + jg);
    v.v = Math.max(0, o.volume ?? 1);
    const fade = c.createGain(), vol = c.createGain();
    v.fade = fade; v.vol = vol;
    src.connect(fade); fade.connect(vol);
    let out = vol;
    const pos = loop ? entry.position : o.position;
    const positional = o.positional !== false && !!(pos || def.pos);
    v.filterHz = o.filterHz || 0;
    if (positional || v.filterHz) {
      const f = c.createBiquadFilter();
      f.type = 'lowpass'; f.Q.value = 0.6; f.frequency.value = v.filterHz || 20000;
      out.connect(f); out = f; v.f = f;
    }
    if (positional) {
      v.pos = new THREE.Vector3();
      if (pos) v.pos.set(pos.x, pos.y, pos.z); else this._defaultPos(def.pos, v.pos);
      this._fixPos(def, v.pos);
      const p = c.createPanner();
      p.panningModel = this._lowCpu && loop && def.cat === 'ambience' ? 'equalpower' : 'HRTF';
      p.distanceModel = 'inverse'; p.refDistance = def.ref; p.rolloffFactor = def.roll; p.maxDistance = 60;
      this._pannerPos(p, v.pos);
      out.connect(p); p.connect(cat.dry); v.p = p;
    } else out.connect(cat.dry);
    if (def.rv > 0 && cat.wR) {
      v.sR = c.createGain(); v.sL = c.createGain();
      out.connect(v.sR); out.connect(v.sL); v.sR.connect(cat.wR); v.sL.connect(cat.wL);
    }
    this._zoneVoice(v, true);
    const t = now + Math.max(0, o.delay || 0);
    v.t0 = t;
    if (loop) {
      src.loop = true;
      src.loopStart = rec.ls; src.loopEnd = rec.le;
      const span = Math.max(0.01, rec.le - rec.ls);
      let off = o.offset;
      if (off === undefined || off === null) off = def.rnd ? Math.random() * span : 0;
      off = rec.ls + (off % span);
      const fi = Math.max(0.01, fadeIn ?? 0.6);
      fade.gain.setValueAtTime(0, t); fade.gain.linearRampToValueAtTime(1, t + fi);
      src.start(t, off);
    } else {
      src.start(t, rec.ls);
    }
    src.onended = () => this._dispose(v);
    v.idx = this.voices.length;
    this.voices.push(v);
    return v;
  }

  _stopVoice(v, fade) {
    if (v.dead || v.stopping) return;
    v.stopping = true;
    try {
      const t = this.ctx.currentTime, g = v.fade.gain, f = Math.max(0.006, +fade || 0);
      g.cancelScheduledValues(t);
      g.setValueAtTime(g.value, t);
      g.linearRampToValueAtTime(0, t + f);
      v.src.stop(Math.max(t + f + 0.02, v.t0 + 0.001));
    } catch (_) { this._dispose(v); }
  }

  _dispose(v) {
    if (v.dead) return;
    v.dead = true;
    try {
      v.src.onended = null; v.src.disconnect(); v.fade.disconnect(); v.vol.disconnect();
      v.f?.disconnect(); v.p?.disconnect(); v.sR?.disconnect(); v.sL?.disconnect();
    } catch (_) { /* already disconnected */ }
    const i = v.idx;
    if (i >= 0 && this.voices[i] === v) {
      const last = this.voices.pop();
      if (last !== v) { this.voices[i] = last; last.idx = i; }
    }
    v.idx = -1;
    if (v.entry && v.entry.voice === v) v.entry.voice = null;
  }

  _admit(name, def) {
    let count = 0, oldest = null, active = 0, victim = null, vp = 99;
    for (let i = 0; i < this.voices.length; i++) {
      const v = this.voices[i];
      if (v.stopping) continue;
      active++;
      if (v.loop) continue;
      if (v.name === name) { count++; if (!oldest || v.t0 < oldest.t0) oldest = v; }
      const pr = CAT_PRIO[v.def.cat] ?? 1;
      if (pr < vp || (pr === vp && victim && v.t0 < victim.t0)) { victim = v; vp = pr; }
    }
    if (count >= def.max && oldest) { oldest.stop(0.04); active--; if (oldest === victim) victim = null; }
    if (active >= this._maxVoices && victim) victim.stop(0.03);
  }

  _findLoop(name, def, pos) {
    for (let i = 0; i < this.loops.length; i++) {
      const e = this.loops[i];
      if (e.name !== name || e.unique || e.stopped) continue;
      if (def.single) return e;
      if (!pos && !e.position) return e;
      if (pos && e.position && e.position.distanceTo(pos) < 1.0) return e;
      if (!pos && e.position && def.pos) return e; // default-positioned sound asked again without a position
    }
    return null;
  }

  _startEntry(e, fadeIn) {
    if (!this.unlocked || e.stopped || e.voice) return;
    let rec = e.synthOnly ? null : this._sampleRec(e.name);
    if (!rec) {
      const s = this.samples.get(e.name);
      if (!e.synthOnly && s && s.done < s.nDec) {
        const now = this.ctx.currentTime;
        if (!e.waitUntil) e.waitUntil = now + e.grace;
        if (now < e.waitUntil) return; // update() retries; _onDecoded() starts it as soon as the sample is ready
      }
      rec = this._synthRec(e.name);
      if (!rec) return;
    }
    if (e.follow && this.game.entity?.position && e.def.pos) {
      const p = this.game.entity.position;
      if (!e.position) e.position = new THREE.Vector3();
      e.position.set(p.x, p.y + 1.7, p.z);
    }
    e.voice = this._spawn(e.name, e.def, rec, e, true, e, fadeIn ?? e.fadeIn ?? 0.6);
  }

  _respawn(e, xf) {
    if (!this.unlocked) return;
    const old = e.voice;
    e.voice = null;
    old?.stop(xf);
    this._startEntry(e, xf);
  }

  _release(e, fade) {
    e.refs--;
    if (e.refs > 0) return;
    e.stopped = true;
    const i = this.loops.indexOf(e);
    if (i >= 0) this.loops.splice(i, 1);
    if (e.voice) e.voice.stop(fade);
  }

  // ------------------------------------------------------------------------------------------------ space
  _pannerPos(p, v) {
    if (p.positionX) { p.positionX.value = v.x; p.positionY.value = v.y; p.positionZ.value = v.z; }
    else p.setPosition(v.x, v.y, v.z);
  }

  _fixPos(def, p) {
    if (def.ceil && p.y < R.ceilingY + 0.05) p.y = R.ceilingY + 0.45; // ceiling sounds live above the ceiling
  }

  _defaultPos(key, t) {
    const P = L.PROPS, rnd = Math.random;
    switch (key) {
      case 'fan': return t.set(L.FAN.x, R.ceilingY - 0.18, L.FAN.z);
      case 'light': return t.set(L.FAN.x, R.ceilingY - 0.48, L.FAN.z);
      case 'alarmClock': { const p = P.alarmClock.pos; return t.set(p[0], p[1] + 0.08, p[2]); }
      case 'grandfather': { const p = P.grandfather.pos; return t.set(p[0], 1.75, p[2] + 0.1); }
      case 'window': return t.set((WIN.minX + WIN.maxX) / 2, (WIN.minY + WIN.maxY) / 2, WIN.z + 0.3);
      case 'tv': { const sp = this.game.world?.tv?.screenPosition; return sp ? t.copy(sp) : t.set(P.tv.pos[0], P.tv.pos[1] + 0.2, P.tv.pos[2] + 0.12); }
      case 'powerBox': { const p = P.powerBox.pos; return t.set(p[0], p[1], p[2] + 0.15); }
      case 'rocking': { const p = P.rockingChair.pos; return t.set(p[0], 0.45, p[2]); }
      case 'furnace': return t.set(2.3, 0.9, AL.minZ - 0.35); // furnace room behind the laundry nook wall
      case 'ceiling': return t.set(-2.2 + rnd() * 5.4, R.ceilingY + 0.45, -2.4 + rnd() * 4.8);
      case 'stairs': {
        const z = ST.topZ + 0.15 + rnd() * (ST.bottomZ - ST.topZ - 0.3), x = -3.0;
        return t.set(x, (L.stairHeightAt(x, z) ?? 1) + 0.05, z);
      }
      case 'house': {
        if (rnd() < 0.55) return t.set(-2.2 + rnd() * 5.5, R.ceilingY - 0.08, -2.5 + rnd() * 5); // joists
        const w = Math.floor(rnd() * 3);
        if (w === 0) return t.set(R.maxX - 0.05, 0.6 + rnd() * 1.6, -2.4 + rnd() * 4.8);
        if (w === 1) return t.set(-2.2 + rnd() * 5.4, 0.6 + rnd() * 1.6, R.maxZ - 0.05);
        return t.set(-2.5 + rnd() * 2.6, 0.6 + rnd() * 1.6, R.minZ + 0.05);
      }
      case 'wall': {
        const w = Math.floor(rnd() * 3);
        if (w === 0) return t.set(R.maxX + 0.3, 1.0 + rnd() * 0.8, -2 + rnd() * 4);
        if (w === 1) return t.set(-2.3 + rnd() * 2.3, 1.0 + rnd() * 0.8, R.minZ - 0.3);
        return t.set(R.minX - 0.3, 1.0 + rnd() * 0.8, 1.7 + rnd() * 0.8);
      }
      case 'entityFeet': case 'entityHead': {
        const p = this.game.entity?.position;
        if (p) return t.set(p.x, p.y + (key === 'entityHead' ? 1.7 : 0.05), p.z);
        return t.set(UH.minX + 0.5, L.UPPER.floorY + 1, (UH.minZ + UH.maxZ) / 2);
      }
      case 'behind': {
        const cam = this.game.camera;
        if (!cam) return t.set(0, 1.6, 0);
        const f = this._tmp2.set(0, 0, -1).applyQuaternion(cam.quaternion);
        f.y = 0; if (f.lengthSq() < 1e-6) f.set(0, 0, -1); f.normalize();
        const side = rnd() < 0.5 ? -1 : 1;
        return t.set(cam.position.x - f.x * 0.5 - f.z * side * 0.32, cam.position.y + 0.04, cam.position.z - f.z * 0.5 + f.x * side * 0.32);
      }
      case 'far': {
        const c = [[-2.3, 1.0, 2.4], [3.2, 1.0, 2.4], [3.2, 1.0, -2.4], [1.35, 1.0, -3.8], [-2.4, 0.6, -1.6]][Math.floor(rnd() * 5)];
        return t.set(c[0], c[1], c[2]);
      }
      default: return t.set(0, 1.2, 0);
    }
  }

  _zoneOf(p) {
    const x = p.x, y = p.y, z = p.z;
    if (y > R.ceilingY + 0.05) {
      if (z < R.minZ - 0.05) return x >= UH.minX && x <= UH.maxX ? Z_HALL : Z_WALL;
      if (x <= ST.maxX + 0.1 && z < ST.ceilingOpeningMaxZ) return Z_STAIR;
      if (x < R.minX || x > R.maxX || z > R.maxZ) return Z_WALL;
      return Z_CEIL;
    }
    if (z < R.minZ - 0.05) return x >= AL.minX && x <= AL.maxX && z >= AL.minZ ? Z_NOOK : Z_WALL;
    if (z > R.maxZ + 0.05) return Z_OUT;
    if (x < R.minX - 0.05 || x > R.maxX + 0.05) return Z_WALL;
    if (x >= CL.minX && x <= CL.maxX && z >= CL.minZ && z <= CL.maxZ) {
      const sh = L.stairHeightAt(x, z) ?? R.ceilingY;
      if (y < sh - 0.05) return Z_CLOSET;
    }
    if (x <= ST.maxX && z < ST.bottomZ && y > 1.0) return Z_STAIR;
    return Z_ROOM;
  }

  /** Occlusion between a source zone/position and the listener: sets this._oHz (lowpass) and this._oG (gain). */
  _occl(sz, sp) {
    let hz = 20000, g = 1;
    const a = sz === Z_STAIR ? Z_ROOM : sz, b = this._lz === Z_STAIR ? Z_ROOM : this._lz;
    if (a !== b) {
      const nook = b === Z_NOOK;
      switch (a) {
        case Z_CEIL: hz = nook ? 420 : 600; g = nook ? 0.4 : 0.62; break;
        case Z_HALL:
          if (this._doorOpen) { hz = nook ? 1600 : 5500; g = nook ? 0.5 : 0.9; } else { hz = nook ? 380 : 520; g = nook ? 0.28 : 0.42; }
          break;
        case Z_WALL: hz = nook ? 650 : 950; g = nook ? 0.5 : 0.68; break;
        case Z_OUT: hz = nook ? 700 : 1500; g = nook ? 0.35 : 0.6; break;
        case Z_CLOSET: hz = nook ? 1200 : 2600; g = nook ? 0.45 : 0.72; break;
        case Z_NOOK: case Z_ROOM:
          if (b === Z_NOOK || b === Z_ROOM) { const o = this._doorway(sp); hz = lerp(1300, 9000, o); g = lerp(0.5, 0.95, o); }
          else if (b === Z_CLOSET) { hz = a === Z_NOOK ? 1200 : 3400; g = a === Z_NOOK ? 0.45 : 0.82; }
          else if (b === Z_HALL) { hz = this._doorOpen ? 5000 : 500; g = this._doorOpen ? 0.85 : 0.4; }
          break;
        default: break;
      }
    }
    this._oHz = hz; this._oG = g;
  }

  /** 0..1 how much of the straight path listener→source goes through the laundry-nook doorway (soft edges). */
  _doorway(sp) {
    const lp = this._lpos, dz = sp.z - lp.z;
    if (Math.abs(dz) < 1e-4) return 0;
    const t = (R.minZ - lp.z) / dz;
    if (t < 0 || t > 1) return 1;
    const x = lp.x + (sp.x - lp.x) * t, y = lp.y + (sp.y - lp.y) * t, D = AL.doorway;
    let o = clamp01((Math.min(x - D.minX, D.maxX - x) + 0.3) / 0.6);
    if (y > D.height) o *= clamp01(1 - (y - D.height) / 0.35);
    return o;
  }

  _zoneVoice(v, init) {
    let z;
    if (v.p) { z = this._zoneOf(v.pos); this._occl(z, v.pos); }
    else { z = this._lz; this._oHz = 20000; this._oG = 1; }
    if (v.f) {
      const hz = Math.min(this._oHz, v.filterHz || 20000);
      const cur = Math.min(v.oHz, v.filterHz || 20000);
      if (init) v.f.frequency.value = hz;
      else if (Math.abs(hz - cur) > cur * 0.04) v.f.frequency.setTargetAtTime(hz, this.ctx.currentTime, 0.08);
    }
    v.oHz = this._oHz;
    if (init) { v.occG = this._oG; v._gain(true); }
    else if (Math.abs(this._oG - v.occG) > 0.02) { v.occG = this._oG; v._gain(false); }
    if (v.sR && (init || z !== v.zone)) {
      const k = this._sendLevel * v.def.rv, r = k * ZONE_ROOM[z], l = k * ZONE_LONG[z];
      if (init) { v.sR.gain.value = r; v.sL.gain.value = l; }
      else { const t = this.ctx.currentTime; v.sR.gain.setTargetAtTime(r, t, 0.15); v.sL.gain.setTargetAtTime(l, t, 0.15); }
    }
    v.zone = z;
  }

  _updateZones() {
    const prev = this._lz;
    this._lz = this._hidden ? Z_CLOSET : this._zoneOf(this._lpos);
    const lzChanged = prev !== this._lz;
    for (let i = 0; i < this.voices.length; i++) {
      const v = this.voices[i];
      if (v.dead) continue;
      if (v.p || lzChanged) this._zoneVoice(v, false);
    }
  }

  _updateListener() {
    const cam = this.game.camera;
    if (!cam) return;
    const p = cam.position, l = this.ctx.listener, lp = this._lpos;
    const f = this._fwd.set(0, 0, -1).applyQuaternion(cam.quaternion), u = this._up.set(0, 1, 0).applyQuaternion(cam.quaternion);
    if (Math.abs(p.x - lp.x) + Math.abs(p.y - lp.y) + Math.abs(p.z - lp.z) > 1e-4 || !this._lset) {
      lp.copy(p);
      if (l.positionX) { l.positionX.value = p.x; l.positionY.value = p.y; l.positionZ.value = p.z; }
      else l.setPosition(p.x, p.y, p.z);
    }
    const lf = this._lf, lu = this._lu;
    if (Math.abs(f.x - lf.x) + Math.abs(f.y - lf.y) + Math.abs(f.z - lf.z) + Math.abs(u.x - lu.x) + Math.abs(u.y - lu.y) + Math.abs(u.z - lu.z) > 1e-4 || !this._lset) {
      lf.copy(f); lu.copy(u);
      if (l.forwardX) {
        l.forwardX.value = f.x; l.forwardY.value = f.y; l.forwardZ.value = f.z;
        l.upX.value = u.x; l.upY.value = u.y; l.upZ.value = u.z;
      } else l.setOrientation(f.x, f.y, f.z, u.x, u.y, u.z);
    }
    this._lset = true;
  }

  // ------------------------------------------------------------------------------------------------ mix / ducking
  _duck(amb, sfx, foley, music, hold, rel) {
    const d = this._dk;
    d[0] = Math.min(d[0], amb); d[1] = Math.min(d[1], sfx); d[2] = Math.min(d[2], foley); d[3] = Math.min(d[3], music);
    this._dkHold = Math.max(this._dkHold, hold); this._dkRel = rel;
  }

  _updateBuses(dt) {
    const d = this._dk;
    if (this._dkHold > 0) this._dkHold -= dt;
    else { const k = Math.min(1, dt / Math.max(0.05, this._dkRel)); for (let i = 0; i < 4; i++) d[i] += (1 - d[i]) * k; }
    this._chaseDuck += ((this._chase ? 0.45 : 1) - this._chaseDuck) * Math.min(1, dt * (this._chase ? 2 : 0.5));
    const hid = this._hidden ? 0.85 : 1;
    this._setCat(0, 'sfx', CAT_LEVEL.sfx * d[1]);
    this._setCat(1, 'foley', CAT_LEVEL.foley * d[2]);
    this._setCat(2, 'ambience', CAT_LEVEL.ambience * d[0] * this._chaseDuck * hid);
    this._setCat(3, 'music', CAT_LEVEL.music * d[3]);
    this._setCat(4, 'voice', CAT_LEVEL.voice);
  }

  _setCat(i, n, v) {
    if (Math.abs(this._catCur[i] - v) < 0.004) return;
    this._catCur[i] = v;
    const c = this.cats[n], t = this.ctx.currentTime;
    c.dry.gain.setTargetAtTime(v, t, 0.04);
    if (c.wR) { c.wR.gain.setTargetAtTime(v, t, 0.04); c.wL.gain.setTargetAtTime(v, t, 0.04); }
  }

  // ------------------------------------------------------------------------------------------------ POV layers
  _live() { const s = this._gameState; return s === 'playing' || s === 'caught' || s === 'paused'; }

  _updateLayers(dt) {
    const f = this._fear, ex = 1 - this._stamina, live = this._live(), hid = this._hidden;
    // sprint exhaustion panting: follows exhaustion, slow release while recovering
    const runT = live ? sstep(0.3, 1.0, ex) * 0.8 * (hid ? 0.25 : 1) : 0;
    this._Lrun.update(dt, runT, 1.6, 0.32, 0.94 + 0.14 * this._Lrun.v);
    // heartbeat (fear, and a little from exertion); crossfade to the fast loop above ~0.6
    const hb = live ? Math.max(sstep(0.12, 0.7, f), sstep(0.55, 1, ex) * 0.32) : 0;
    const fast = sstep(0.55, 0.72, f);
    this._Lhb.update(dt, hb * (1 - fast) * 0.9, 1.4, 0.45, 0.9 + 0.32 * f);
    this._Lhbf.update(dt, hb * fast * 0.95, 1.4, 0.45, 0.95 + 0.22 * sstep(0.6, 1, f));
    // scared breathing (not while panting / hidden)
    const sc = live && !hid ? sstep(0.35, 0.85, f) * 0.55 * (1 - clamp01(this._Lrun.v * 1.4)) : 0;
    this._Lscared.update(dt, sc, 0.8, 0.4);
    // hidden: close, quiet, held breathing (holds it now and then)
    if (hid) {
      this._holdT -= dt;
      if (this._holdT <= 0) { this._holding = !this._holding; this._holdT = this._holding ? 1.6 + Math.random() * 1.6 : 4 + Math.random() * 5; }
    }
    const hb2 = hid && live ? (this._holding ? 0.05 : 0.24 + 0.24 * f) : 0;
    this._Lhide.update(dt, hb2, 1.0, 1.4, 0.86 + 0.12 * f);
    // sub drone: subtle bed, darker when the power is off, opens up with fear
    const dr = this._bedOn ? (this._power ? 0.1 : 0.2) + 0.6 * f + (this._chase ? 0.15 : 0) : 0;
    this._Ldrone.update(dt, dr, 0.6, 0.25, undefined, 300 + 2600 * f);
    // chase music
    this._Lchase.update(dt, this._chase && live ? 0.95 : 0, 3, 0.75);
  }

  _onHide(h) {
    if (h === this._hidden) return;
    this._hidden = h;
    this._zoneT = 0;
    this._holdT = 2 + Math.random() * 2; this._holding = false;
    if (this.unlocked) {
      this.play('cloth_move', { volume: 0.5 });
      this.ambF.frequency.setTargetAtTime(h ? 2200 : 20000, this.ctx.currentTime, 0.2);
    }
  }

  _onFlashlight(p) {
    const on = !!p?.on;
    if (on !== this._flOn) { this._flOn = on; this.play('flashlight_click', { volume: 0.9 }); }
  }

  _onSpotted() {
    this.play('stinger', { volume: 0.95 });
    this.play('heartbeat_single', { delay: 0.04, volume: 0.75 });
    this.play('player_gasp', { delay: 0.16, volume: 0.85 });
  }

  _onEntityState(s) {
    this._entityState = s || 'dormant';
    this._chase = s === 'chasing';
    if (s === 'jumpscare') { this._Lchase.kill(0.04); this._duck(0.1, 0.3, 0.25, 0, 1.8, 1.5); }
  }

  _onGameState(s) {
    const prev = this._gameState;
    this._gameState = s || 'playing';
    if (prev === 'loading' && s !== 'loading') { this._startDecoding(); this._pump(); }
    if (s === 'caught' || s === 'gameover') { this._chase = false; this._Lchase.kill(1.2); }
    if (s === 'won') { this._chase = false; this._Lchase.kill(1.5); this._duck(0.35, 1, 1, 1, 8, 4); }
  }

  // ------------------------------------------------------------------------------------------------ beds & life
  _startBed() {
    if (this._bedOn) return;
    this._bedOn = true;
    this._room = this.loop('room_tone', { volume: 0.8, fadeIn: 3, grace: 8 });
    this._clock = this.loop('clock_tick', { volume: 0.85, fadeIn: 1.5, grace: 6 });
    this._wind = this.loop('wind_outside', { volume: 0.6, fadeIn: 4, grace: 8 });
    this._furnOn = Math.random() < 0.6;
    this._furnT = this._furnOn ? 40 + Math.random() * 60 : 15 + Math.random() * 30;
    if (this._furnOn) this._furn = this.loop('furnace', { volume: 0.9, fadeIn: 4, grace: 8 });
    this._lifeT = 22 + Math.random() * 20;
    this._setPower(this.game.world?.power !== false, true);
  }

  _setPower(on, force) {
    if (!force && on === this._power) return;
    this._power = on;
    if (!this.unlocked || !this._bedOn) return;
    if (on) {
      if (!this._buzz) this._buzz = this.loop('light_buzz', { volume: 0.5, fadeIn: force ? 1.5 : 0.3, grace: force ? 6 : 0.3 });
      if (!this._fan) {
        this._fan = this.loop('fan_hum', { volume: 0.6, fadeIn: force ? 2 : 3.5, rate: force ? 1 : 0.5, grace: force ? 6 : 0.3 });
        if (!force) this._fan.setRate(1, 6);
      }
      if (!force) this.play('power_up', { volume: 0.85 });
    } else {
      if (this._buzz) { this._buzz.stop(0.05); this._buzz = null; }
      if (this._fan) { this._fan.setRate(0.3, 5); this._fan.stop(5); this._fan = null; }
    }
  }

  _updateBed(dt) {
    if (!this._bedOn) return;
    // furnace cycles on/off like a real one
    this._furnT -= dt;
    if (this._furnT <= 0) {
      this._furnOn = !this._furnOn;
      if (this._furnOn) { this._furn = this.loop('furnace', { volume: 0.9, fadeIn: 5 }); this._furnT = 60 + Math.random() * 80; }
      else { this._furn?.stop(6); this._furn = null; this._furnT = 35 + Math.random() * 60; }
    }
    // wind gusts
    this._windT -= dt;
    if (this._windT <= 0) { this._windT = 3 + Math.random() * 6; this._windTarget = 0.3 + Math.random() * 0.55; }
    this._windV += (this._windTarget - this._windV) * Math.min(1, dt * 0.35);
    if (this._wind && Math.abs(this._windV - (this._windSent ?? -1)) > 0.01) { this._wind.setVolume(this._windV); this._windSent = this._windV; }
  }

  _updateLife(dt) {
    if (this._gameState !== 'playing') return;
    const es = this._entityState;
    if (es !== 'dormant' && es !== 'disabled' && es) return; // never confuse real gameplay cues
    if (this._fear > 0.3) return;
    this._lifeT -= dt;
    if (this._lifeT > 0) return;
    this._lifeT = 40 + Math.random() * 55;
    // gameplay runs its own scripted scares with the same sounds: stay quiet if one happened recently
    const now = this.ctx.currentTime;
    for (let i = 0; i < LIFE_NAMES.length; i++) {
      const t = this._last.get(LIFE_NAMES[i]);
      if (t !== undefined && now - t < 25) { this._lifeT = 20 + Math.random() * 20; return; }
    }
    const x = Math.random();
    if (x < 0.42) this.play('house_creak', { volume: 0.55 + Math.random() * 0.4 });
    else if (x < 0.57) this.play('stair_creak', { volume: 0.4 + Math.random() * 0.3 });
    else if (x < 0.73) this.play('ceiling_walk', { volume: 0.65 + Math.random() * 0.3 });
    else if (x < 0.85) this.play('ceiling_steps', { volume: 0.7 });
    else if (x < 0.94) this.play('knock_wall', { volume: 0.45 + Math.random() * 0.25 });
    else this.play('window_tap', { volume: 0.5 });
  }

  _warnOnce(key, msg, err) {
    if (this._warned.has(key)) return;
    this._warned.add(key);
    console.warn(msg, err ? (err.message || err) : '');
  }
}

// =====================================================================================================================
// Procedural synthesis (FALLBACK when a recorded sample is missing or not decoded yet).
// Each recipe renders a mono Float32Array offline (modal impacts, stick-slip creaks, formant voices, filtered noise);
// loops are rendered exactly periodic (events wrap around, noise beds use a periodic noise table) so they loop seamlessly.
// =====================================================================================================================
let WRAP = false;

function rngOf(seed) {
  let s = (seed >>> 0) || 0x9e3779b9;
  return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
}
function hashStr(str) { let h = 2166136261; for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

class BQ {
  constructor(type, f, q, sr, db = 0) { this.type = type; this.q = q; this.sr = sr; this.db = db; this.x1 = this.x2 = this.y1 = this.y2 = 0; this.set(f); }
  set(f, q = this.q) {
    const w = TAU * Math.min(Math.max(f, 10), this.sr * 0.45) / this.sr, cs = Math.cos(w), a = Math.sin(w) / (2 * q);
    let b0, b1, b2, a0, a1, a2;
    switch (this.type) {
      case 'lp': b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = b0; a0 = 1 + a; a1 = -2 * cs; a2 = 1 - a; break;
      case 'hp': b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = b0; a0 = 1 + a; a1 = -2 * cs; a2 = 1 - a; break;
      case 'pk': { const A = Math.pow(10, this.db / 40); b0 = 1 + a * A; b1 = -2 * cs; b2 = 1 - a * A; a0 = 1 + a / A; a1 = -2 * cs; a2 = 1 - a / A; break; }
      default: b0 = a; b1 = 0; b2 = -a; a0 = 1 + a; a1 = -2 * cs; a2 = 1 - a; // band-pass, 0 dB peak
    }
    this.b0 = b0 / a0; this.b1 = b1 / a0; this.b2 = b2 / a0; this.a1 = a1 / a0; this.a2 = a2 / a0;
    this.comp = 1 / Math.max(1e-4, a / (1 + a)); // impulse-response level compensation for band-pass banks
  }
  p(x) {
    const y = this.b0 * x + this.b1 * this.x1 + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y;
    return y;
  }
}

function put(o, i, v) {
  const n = o.length;
  if (i >= n) { if (!WRAP) return false; i %= n; }
  if (i < 0) return true;
  o[i] += v;
  return true;
}

/** Damped sinusoid (one vibration mode) via a recursive oscillator. */
function mode(o, sr, t0, f, tau, amp, ph = 0) {
  if (!(f > 0) || f >= sr * 0.47 || !amp) return;
  const i0 = Math.round(t0 * sr), n = Math.ceil(tau * sr * 7);
  const w = TAU * f / sr, r = Math.exp(-1 / (tau * sr)), c = 2 * r * Math.cos(w), r2 = r * r;
  let y2 = amp * Math.sin(ph - 2 * w) / r2, y1 = amp * Math.sin(ph - w) / r;
  for (let i = 0; i < n; i++) { const y = c * y1 - r2 * y2; y2 = y1; y1 = y; if (!put(o, i0 + i, y)) break; }
}

/** Modal impact: [[freq, tau, amp], ...] with small random detune. */
function hit(o, sr, r, t0, modes, a = 1) {
  for (let k = 0; k < modes.length; k++) {
    const m = modes[k];
    mode(o, sr, t0, m[0] * (1 + (r() - 0.5) * 0.05), m[1] * (0.85 + r() * 0.3), m[2] * a * (0.8 + r() * 0.4), m[0] < 400 ? 0 : r() * TAU);
  }
}

/** Filtered noise burst. opt: lp, hp, bp (+q), atk, tau (exp decay), env(x 0..1). */
function noise(o, sr, r, t0, dur, amp, opt = EMPTY) {
  const lp = opt.lp || 0, hp = opt.hp || 0, bp = opt.bp || 0, q = opt.q || 1, atk = opt.atk ?? 0.002, tau = opt.tau || 0, env = opt.env || null;
  const fl = lp ? new BQ('lp', lp, 0.707, sr) : null, fh = hp ? new BQ('hp', hp, 0.707, sr) : null, fb = bp ? new BQ('bp', bp, q, sr) : null;
  let comp = 1;
  if (bp) comp *= Math.min(8, Math.sqrt(sr * q / (2 * bp)));
  if (lp) comp *= Math.min(6, Math.sqrt(sr / (2 * lp)));
  const i0 = Math.round(t0 * sr), n = Math.round(dur * sr), na = Math.max(1, Math.round(atk * sr)), kt = tau ? 1 / (tau * sr) : 0;
  for (let i = 0; i < n; i++) {
    let x = r() * 2 - 1;
    if (fl) x = fl.p(x);
    if (fh) x = fh.p(x);
    if (fb) x = fb.p(x);
    let e = i < na ? i / na : (kt ? Math.exp(-(i - na) * kt) : 1);
    if (env) e *= env(i / n);
    const rem = n - i;
    if (rem < 96) e *= rem / 96;
    if (!put(o, i0 + i, x * e * amp * comp)) break;
  }
}

/** Stick-slip friction creak: irregular pulse train (rate f0→f1→f2) exciting a resonator bank [[f, q, gain], ...]. */
function creak(o, sr, r, t0, dur, amp, opt) {
  const f = opt.f, rough = opt.rough ?? 0.25, grain = (opt.grain ?? 0.12) * 0.25, swell = opt.swell !== false;
  // each band rings at ~unity level per friction pulse (BQ.comp compensates the band-pass impulse gain)
  const bank = opt.res.map(([fr, q, g]) => { const b = new BQ('bp', fr * (1 + (r() - 0.5) * 0.06), q, sr); return [b, g * b.comp * 0.5]; });
  const i0 = Math.round(t0 * sr), n = Math.round(dur * sr);
  let ph = r(), jit = 1;
  for (let i = 0; i < n; i++) {
    const x = i / n;
    const rate = (1 - x) * (1 - x) * f[0] + 2 * x * (1 - x) * f[1] + x * x * f[2];
    ph += rate * jit / sr;
    let ex = (r() * 2 - 1) * grain;
    if (ph >= 1) { ph -= 1; jit = 1 + (r() * 2 - 1) * rough; ex += 0.7 + r() * 0.6; }
    let y = 0;
    for (let k = 0; k < bank.length; k++) y += bank[k][0].p(ex) * bank[k][1];
    let e = Math.min(1, i / (0.012 * sr)) * Math.min(1, (n - i) / (0.04 * sr));
    if (swell) e *= Math.sqrt(Math.sin(Math.PI * x));
    if (!put(o, i0 + i, y * e * amp)) break;
  }
}

function fgain(form, f) { let g = 0; for (let k = 0; k < form.length; k++) { const F = form[k], d = (f - F[0]) / F[1]; g += F[2] / (1 + d * d); } return g; }

/** Additive voiced source (glottal-like harmonics shaped by formants) + optional breath noise. */
function vox(o, sr, r, t0, dur, amp, opt) {
  const { f0, form, env } = opt, nh = opt.nh || 20, tilt = opt.tilt ?? 1, breath = opt.breath || 0, vib = opt.vib || 0, vibHz = opt.vibHz || 5.5, jit = opt.jit || 0;
  const i0 = Math.round(t0 * sr), n = Math.round(dur * sr), amps = new Float64Array(nh + 1);
  const bf = opt.bf || 1500, bq = opt.bq || 1.2, bb = breath ? new BQ('bp', bf, bq, sr) : null, bcomp = breath ? Math.min(8, Math.sqrt(sr * bq / (2 * bf))) : 0;
  let ph = 0, f = 100, e = 0, cnt = 0, jv = 0;
  for (let i = 0; i < n; i++) {
    const t = i / sr, x = i / n;
    if (cnt-- <= 0) {
      cnt = 32;
      jv += ((r() * 2 - 1) * jit - jv) * 0.35;
      f = f0(x, t) * (1 + vib * Math.sin(TAU * vibHz * t) + jv);
      e = env(x, t);
      for (let k = 1; k <= nh; k++) { const fk = k * f; amps[k] = fk < sr * 0.45 ? fgain(form, fk) / Math.pow(k, tilt) : 0; }
    }
    ph += f / sr; if (ph >= 1) ph -= 1;
    const s1 = Math.sin(TAU * ph), c2 = 2 * Math.cos(TAU * ph);
    let a = 0, b = s1, y = 0;
    for (let k = 1; k <= nh; k++) { y += amps[k] * b; const nb = c2 * b - a; a = b; b = nb; }
    if (bb) y += bb.p(r() * 2 - 1) * breath * bcomp;
    if (!put(o, i0 + i, y * e * amp)) break;
  }
}

/** Periodic bed: fn(j, t, w, w2) -> sample, run with warm-up so filters reach steady state; output loops perfectly. */
function bed(o, sr, r, fn) {
  const N = o.length, W = new Float32Array(N);
  for (let i = 0; i < N; i++) W[i] = r() * 2 - 1;
  const P = Math.min(N, Math.round(sr * 0.6));
  for (let i = 0; i < N + P; i++) {
    const j = i % N;
    const y = fn(j, j / sr, W[j], W[(j * 7 + 101) % N]);
    if (i >= P) o[j] += y;
  }
}

const ad = (atk, tau) => (x, t) => (t < atk ? t / atk : Math.exp(-(t - atk) / tau));

// ---------------------------------------------------------------- reusable recipe parts
function rustle(o, sr, r, t0, dur, a) {
  const hp = new BQ('hp', 1300, 0.7, sr), lp = new BQ('lp', 6500, 0.7, sr), i0 = Math.round(t0 * sr), n = Math.round(dur * sr);
  let g = 0, gt = 0, c = 0;
  for (let i = 0; i < n; i++) {
    if (c-- <= 0) { c = Math.round(sr * (0.006 + r() * 0.02)); gt = r() < 0.3 ? 0.1 : r(); }
    g += (gt - g) * 0.02;
    const x = i / n, e = Math.sin(Math.PI * x);
    if (!put(o, i0 + i, lp.p(hp.p(r() * 2 - 1)) * g * e * a)) break;
  }
}
function stepEntity(o, sr, r, t = 0, a = 1) {
  mode(o, sr, t, 46 + r() * 8, 0.09, 1.0 * a);
  noise(o, sr, r, t, 0.18, 0.5 * a, { lp: 260, atk: 0.003, tau: 0.06 });
  noise(o, sr, r, t + 0.006, 0.05, 0.35 * a, { bp: 1100, q: 0.9, atk: 0.001, tau: 0.012 });
  hit(o, sr, r, t + 0.002, [[120, 0.08, 0.35], [260, 0.05, 0.2]], a);
}
function stepCeiling(o, sr, r, t = 0, a = 1) {
  mode(o, sr, t, 40 + r() * 6, 0.13, 1.0 * a);
  noise(o, sr, r, t, 0.3, 0.6 * a, { lp: 180, atk: 0.004, tau: 0.09 });
  hit(o, sr, r, t, [[95, 0.12, 0.4], [170, 0.08, 0.25]], a);
}
function heartbeatAt(o, sr, r, t, a, dubDt) {
  mode(o, sr, t, 44 + r() * 4, 0.075, 1.0 * a); mode(o, sr, t, 88, 0.045, 0.32 * a); mode(o, sr, t + 0.004, 30, 0.1, 0.35 * a);
  noise(o, sr, r, t, 0.12, 0.25 * a, { lp: 120, atk: 0.006, tau: 0.04 });
  mode(o, sr, t + dubDt, 57 + r() * 4, 0.06, 0.72 * a); mode(o, sr, t + dubDt, 114, 0.035, 0.22 * a);
  noise(o, sr, r, t + dubDt, 0.1, 0.18 * a, { lp: 160, atk: 0.005, tau: 0.035 });
}
function breathCycle(o, sr, r, t, a, inDur, exDur, gap, trem) {
  const tr = trem ? (x) => 0.7 + 0.3 * Math.sin(x * TAU * trem * inDur) : null;
  noise(o, sr, r, t, inDur, 0.35 * a, { bp: 1600 + r() * 300, q: 1.4, atk: 0.01, env: (x) => Math.sin(Math.PI * Math.pow(x, 0.7)) * (tr ? tr(x) : 1) });
  noise(o, sr, r, t, inDur, 0.12 * a, { bp: 2700, q: 2, atk: 0.01, env: (x) => Math.sin(Math.PI * x) });
  const te = t + inDur + gap;
  const tr2 = trem ? (x) => 0.65 + 0.35 * Math.sin(x * TAU * trem * 1.3 * exDur) : null;
  noise(o, sr, r, te, exDur, 0.7 * a, { bp: 650 + r() * 150, q: 1.1, atk: 0.02, env: (x) => Math.pow(Math.sin(Math.PI * Math.pow(x, 0.45)), 1.2) * (tr2 ? tr2(x) : 1) });
  noise(o, sr, r, te, exDur, 0.3 * a, { bp: 1250, q: 1.5, atk: 0.02, env: (x) => Math.sin(Math.PI * Math.pow(x, 0.5)) });
}
function clickAt(o, sr, r, t, a, hi = 1) { hit(o, sr, r, t, [[2400 * hi, 0.006, 0.5], [4100 * hi, 0.004, 0.3], [800 * hi, 0.01, 0.2]], a); }
const WOOD_THUD = [[110, 0.1, 0.6], [230, 0.07, 0.4], [410, 0.05, 0.25], [820, 0.03, 0.1]];
const LATCH = [[2300, 0.015, 0.3], [3500, 0.01, 0.2], [5200, 0.008, 0.1]];

// ---------------------------------------------------------------- recipes: d = seconds (or fn), g = generator
const SYN = {
  footstep_carpet: { d: 0.3, g(o, sr, r) {
    noise(o, sr, r, 0, 0.14, 0.7, { lp: 420, atk: 0.004, tau: 0.03 });
    mode(o, sr, 0.004, 60 + r() * 12, 0.04, 0.4);
    noise(o, sr, r, 0.045 + r() * 0.03, 0.17, 0.22, { bp: 1300 + r() * 700, q: 0.7, atk: 0.025, tau: 0.045 });
    noise(o, sr, r, 0.05, 0.12, 0.05, { hp: 3500, atk: 0.02, tau: 0.035 });
  } },
  footstep_wood: { d: 0.45, g(o, sr, r) {
    noise(o, sr, r, 0, 0.1, 0.6, { lp: 700, atk: 0.002, tau: 0.025 });
    hit(o, sr, r, 0.002, [[150, 0.06, 0.5], [340, 0.045, 0.3], [690, 0.03, 0.15], [1180, 0.02, 0.08]]);
    if (r() < 0.6) creak(o, sr, r, 0.06, 0.22 + r() * 0.15, 0.25, { f: [90, 160, 70], res: [[620, 9, 1], [1350, 12, 0.6], [2400, 14, 0.3]] });
    noise(o, sr, r, 0.07, 0.1, 0.1, { bp: 1800, q: 0.7, atk: 0.01, tau: 0.03 });
  } },
  footstep_concrete: { d: 0.3, g(o, sr, r) {
    noise(o, sr, r, 0, 0.05, 0.8, { hp: 900, atk: 0.001, tau: 0.012 });
    noise(o, sr, r, 0, 0.08, 0.4, { lp: 500, atk: 0.001, tau: 0.02 });
    noise(o, sr, r, 0.03, 0.18, 0.18, { bp: 3800, q: 0.6, atk: 0.015, tau: 0.05 });
  } },
  entity_step: { d: 0.5, g(o, sr, r) { stepEntity(o, sr, r, 0, 1); } },
  entity_step_stairs: { d: 0.9, g(o, sr, r) {
    stepEntity(o, sr, r, 0, 1);
    creak(o, sr, r, 0.05 + r() * 0.05, 0.4 + r() * 0.3, 0.5, { f: [50, 140, 80], res: [[480, 10, 1], [1050, 12, 0.6], [2200, 14, 0.25]] });
  } },
  ceiling_steps: { d: 0.7, sr: 22050, g(o, sr, r) {
    stepCeiling(o, sr, r, 0, 1);
    if (r() < 0.4) creak(o, sr, r, 0.08, 0.35, 0.3, { f: [40, 90, 50], res: [[300, 8, 1], [700, 10, 0.5]] });
  } },
  ceiling_walk: { d: 7.3, sr: 22050, vars: 1, g(o, sr, r) {
    let t = 0.3;
    for (let i = 0; i < 8; i++) {
      stepCeiling(o, sr, r, t, 0.45 + 0.55 * Math.sin(Math.PI * (i + 0.5) / 8));
      if (i === 3 || (i === 6 && r() < 0.5)) creak(o, sr, r, t + 0.05, 0.6, 0.35, { f: [30, 80, 40], res: [[260, 8, 1], [600, 10, 0.5]] });
      t += 0.78 + r() * 0.12;
    }
  } },
  stair_creak: { d: (r) => 0.6 + r() * 0.45, g(o, sr, r) {
    creak(o, sr, r, 0, o.length / sr, 1, { f: [30 + r() * 30, 120 + r() * 120, 40 + r() * 40], res: [[380, 9, 1], [820, 11, 0.7], [1500, 13, 0.4], [2600, 15, 0.2]], rough: 0.3 });
  } },
  house_creak: { d: (r) => 0.9 + r() * 0.7, sr: 22050, g(o, sr, r) {
    const d = o.length / sr;
    creak(o, sr, r, 0, d * 0.7, 1, { f: [18, 60 + r() * 50, 22], res: [[210, 7, 1], [470, 9, 0.8], [980, 11, 0.4], [1900, 12, 0.15]], rough: 0.4 });
    if (r() < 0.6) creak(o, sr, r, d * 0.72, d * 0.26, 0.6, { f: [25, 70, 30], res: [[240, 7, 1], [520, 9, 0.6]], rough: 0.4 });
  } },
  cloth_move: { d: 0.45, g(o, sr, r) { rustle(o, sr, r, 0, 0.42, 1); } },
  land_thump: { d: 0.5, g(o, sr, r) {
    mode(o, sr, 0, 55, 0.14, 1); noise(o, sr, r, 0, 0.3, 0.6, { lp: 350, atk: 0.003, tau: 0.1 }); rustle(o, sr, r, 0.02, 0.3, 0.4);
  } },
  door_creak_open: { d: 2.5, vars: 2, g(o, sr, r) {
    hit(o, sr, r, 0, LATCH, 0.6);
    creak(o, sr, r, 0.08, 2.25, 1, { f: [15, 150 + r() * 40, 45], res: [[310, 10, 1], [650, 12, 0.8], [1240, 14, 0.5], [2150, 16, 0.25]], rough: 0.22, grain: 0.08 });
    noise(o, sr, r, 0.1, 1.6, 0.06, { lp: 400, env: (x) => Math.sin(Math.PI * x) });
  } },
  door_close: { d: 1.0, vars: 2, g(o, sr, r) {
    noise(o, sr, r, 0, 0.25, 0.12, { lp: 500, env: (x) => Math.sin(Math.PI * x) });
    mode(o, sr, 0.22, 70, 0.12, 0.8); hit(o, sr, r, 0.22, WOOD_THUD, 1); noise(o, sr, r, 0.22, 0.1, 0.4, { lp: 900, tau: 0.04 });
    hit(o, sr, r, 0.24, LATCH, 0.7);
  } },
  door_locked: { d: 1.4, vars: 2, g(o, sr, r) {
    for (let k = 0; k < 2; k++) {
      const t = 0.05 + k * 0.6;
      hit(o, sr, r, t, [[1800, 0.02, 0.2], [2900, 0.015, 0.15]]);
      for (const dt of [0.12, 0.2, 0.27]) {
        hit(o, sr, r, t + dt + r() * 0.02, [[140, 0.05, 0.5], [310, 0.035, 0.3], [620, 0.02, 0.15]]);
        hit(o, sr, r, t + dt + 0.005, [[2600, 0.01, 0.15], [4100, 0.008, 0.1]]);
      }
    }
  } },
  unlock: { d: 1.0, vars: 2, g(o, sr, r) {
    noise(o, sr, r, 0, 0.25, 0.3, { bp: 3500, q: 2, env: (x) => (r() < 0.5 ? 0.6 : 1) * Math.sin(Math.PI * x) });
    hit(o, sr, r, 0.3, [[2600, 0.01, 0.3], [4200, 0.008, 0.2]]); hit(o, sr, r, 0.36, [[2400, 0.01, 0.25]]);
    hit(o, sr, r, 0.55, [[850, 0.04, 0.6], [1650, 0.03, 0.4], [2900, 0.02, 0.25]]); mode(o, sr, 0.55, 160, 0.05, 0.4);
  } },
  drawer_open: { d: 0.85, g(o, sr, r) {
    const dur = 0.5 + r() * 0.1;
    const hp = new BQ('bp', 700 + r() * 200, 1.2, sr), i0 = 0, n = Math.round(dur * sr);
    let ph = 0;
    for (let i = 0; i < n; i++) {
      ph += (35 + 25 * r()) / sr; let pulse = 0; if (ph >= 1) { ph -= 1; pulse = 1; }
      const x = i / n, e = Math.sin(Math.PI * Math.pow(x, 0.8));
      put(o, i0 + i, hp.p((r() * 2 - 1) * 0.6 + pulse * 3) * e * 0.9);
    }
    hit(o, sr, r, dur + 0.02, [[160, 0.05, 0.5], [360, 0.04, 0.3], [700, 0.025, 0.15]]);
    hit(o, sr, r, dur + 0.05, [[1900, 0.02, 0.1], [3100, 0.015, 0.08]]);
  } },
  drawer_close: { d: 0.7, g(o, sr, r) {
    noise(o, sr, r, 0, 0.3, 0.5, { bp: 800, q: 1.1, env: (x) => Math.sin(Math.PI * x) });
    hit(o, sr, r, 0.32, [[120, 0.07, 0.8], [270, 0.05, 0.5], [520, 0.03, 0.25]]); noise(o, sr, r, 0.32, 0.08, 0.3, { lp: 900, tau: 0.02 });
  } },
  cabinet_open: { d: 0.6, g(o, sr, r) {
    hit(o, sr, r, 0, [[2100, 0.012, 0.3], [3400, 0.01, 0.2]]);
    creak(o, sr, r, 0.05, 0.45, 0.8, { f: [200, 480, 300], res: [[950, 14, 1], [1900, 16, 0.6], [3100, 18, 0.3]], rough: 0.12 });
  } },
  cabinet_close: { d: 0.6, g(o, sr, r) {
    creak(o, sr, r, 0, 0.25, 0.6, { f: [300, 420, 200], res: [[950, 14, 1], [1900, 16, 0.6]], rough: 0.12 });
    hit(o, sr, r, 0.3, [[170, 0.05, 0.5], [380, 0.04, 0.3], [760, 0.025, 0.15]]); hit(o, sr, r, 0.31, [[2100, 0.012, 0.25]]);
  } },
  box_open: { d: 0.6, vars: 1, g(o, sr, r) {
    creak(o, sr, r, 0, 0.35, 0.7, { f: [250, 600, 380], res: [[1500, 15, 1], [2900, 18, 0.5]], rough: 0.15 });
    hit(o, sr, r, 0.4, [[420, 0.03, 0.3], [900, 0.02, 0.2]]);
  } },
  lock_wheel: { d: 0.08, sr: 44100, g(o, sr, r) {
    hit(o, sr, r, 0, [[3200, 0.008, 0.5], [5100, 0.006, 0.35], [7300, 0.004, 0.2]]); noise(o, sr, r, 0, 0.02, 0.2, { hp: 4000, tau: 0.003 });
  } },
  lock_fail: { d: 0.6, vars: 1, g(o, sr, r) {
    for (const t of [0, 0.18]) { hit(o, sr, r, t, [[620, 0.03, 0.5], [1350, 0.025, 0.35], [2600, 0.02, 0.2], [4200, 0.012, 0.1]]); noise(o, sr, r, t, 0.03, 0.3, { hp: 2000, tau: 0.006 }); }
  } },
  lock_success: { d: 0.9, sr: 44100, vars: 1, g(o, sr, r) {
    hit(o, sr, r, 0, [[2800, 0.01, 0.4], [4600, 0.008, 0.3]]);
    hit(o, sr, r, 0.09, [[1250, 0.25, 0.5], [3050, 0.15, 0.3], [5400, 0.08, 0.2]]); mode(o, sr, 0.09, 600, 0.05, 0.3);
  } },
  key_pickup: { d: 0.9, sr: 44100, g(o, sr, r) {
    for (let k = 0; k < 8; k++) {
      const t = 0.02 + r() * 0.6, m = [];
      for (let j = 0; j < 3; j++) m.push([2200 + r() * 4600, 0.08 + r() * 0.17, 0.2 + r() * 0.3]);
      hit(o, sr, r, t, m, 1 - t);
    }
  } },
  pickup: { d: 0.35, g(o, sr, r) { rustle(o, sr, r, 0, 0.2, 0.6); hit(o, sr, r, 0.05, [[650, 0.02, 0.3], [1500, 0.015, 0.2]]); } },
  paper: { d: 0.65, sr: 44100, g(o, sr, r) {
    const n = o.length, b = new BQ('bp', 3000, 0.7, sr), h = new BQ('hp', 2500, 0.7, sr);
    let g = 0, gt = 0, c = 0;
    for (let i = 0; i < n; i++) {
      if (c-- <= 0) { c = Math.round(sr * (0.01 + r() * 0.03)); gt = r(); }
      g += (gt - g) * 0.01;
      const cr = r() < 0.004 ? (r() * 2 - 1) * 6 : 0;
      o[i] += (b.p(r() * 2 - 1) * 2 * g + h.p(cr)) * Math.sin(Math.PI * i / n);
    }
  } },
  rocking_chair: { d: 0.7, g(o, sr, r) {
    creak(o, sr, r, 0, 0.45, 1, { f: [40, 110, 60], res: [[260, 8, 1], [600, 10, 0.7], [1300, 12, 0.35]] });
    noise(o, sr, r, 0, 0.5, 0.2, { lp: 250, env: (x) => Math.sin(Math.PI * x) });
  } },
  closet_enter: { d: 1.0, vars: 1, g(o, sr, r) {
    creak(o, sr, r, 0, 0.5, 0.8, { f: [60, 220, 90], res: [[700, 12, 1], [1500, 14, 0.6]] });
    for (let k = 0; k < 12; k++) hit(o, sr, r, 0.1 + r() * 0.4, [[1100 + r() * 800, 0.012, 0.15], [2300 + r() * 900, 0.008, 0.1]]);
    rustle(o, sr, r, 0.3, 0.6, 0.5);
  } },
  closet_exit: { d: 1.0, vars: 1, g(o, sr, r) {
    rustle(o, sr, r, 0, 0.4, 0.5);
    creak(o, sr, r, 0.25, 0.45, 0.8, { f: [80, 200, 70], res: [[700, 12, 1], [1500, 14, 0.6]] });
    for (let k = 0; k < 10; k++) hit(o, sr, r, 0.3 + r() * 0.4, [[1100 + r() * 800, 0.012, 0.15], [2300 + r() * 900, 0.008, 0.1]]);
  } },
  bump: { d: 0.5, g(o, sr, r) {
    mode(o, sr, 0, 80, 0.09, 0.8); hit(o, sr, r, 0, [[95, 0.1, 0.5], [185, 0.07, 0.35], [340, 0.05, 0.2]]);
    noise(o, sr, r, 0, 0.08, 0.4, { lp: 600, tau: 0.03 });
    hit(o, sr, r, 0.04, [[1400 + r() * 600, 0.015, 0.12]]); hit(o, sr, r, 0.09, [[1800 + r() * 600, 0.012, 0.08]]);
  } },
  window_tap: { d: 0.7, sr: 44100, vars: 2, g(o, sr, r) {
    for (const t of [0, 0.22 + r() * 0.05, 0.47 + r() * 0.06]) {
      hit(o, sr, r, t, [[2600, 0.04, 0.4], [4100, 0.03, 0.3], [6200, 0.02, 0.15]]); noise(o, sr, r, t, 0.01, 0.2, { hp: 3000, tau: 0.002 });
    }
  } },
  breaker_flip: { d: 0.45, vars: 2, g(o, sr, r) {
    mode(o, sr, 0, 90, 0.06, 0.6); noise(o, sr, r, 0, 0.08, 0.4, { lp: 400, tau: 0.03 });
    hit(o, sr, r, 0.005, [[1100, 0.025, 0.5], [2300, 0.02, 0.35], [3900, 0.015, 0.2]]);
    mode(o, sr, 0.005, 640, 0.12, 0.08); noise(o, sr, r, 0.01, 0.04, 0.25, { bp: 3200, q: 1.5 });
  } },
  power_up: { d: 3.0, vars: 1, g(o, sr, r) {
    hit(o, sr, r, 0, [[1800, 0.015, 0.4], [3000, 0.01, 0.25]]);
    const H = [0.3, 1, 0.4, 0.5, 0.2, 0.25], n = o.length;
    const ph = new Float64Array(H.length);
    for (let i = 0; i < n; i++) {
      const t = i / sr, e = Math.min(1, t / 1.2) * (t < 1.4 ? 1 : 1 - 0.6 * Math.min(1, (t - 1.4) / 1.6)), fm = 0.92 + 0.08 * Math.min(1, t / 1.4);
      let y = 0;
      for (let k = 0; k < H.length; k++) { ph[k] += 60 * (k + 1) * fm / sr; y += H[k] * Math.sin(TAU * ph[k]); }
      o[i] += y * e * 0.25 * Math.min(1, (n - i) / (0.05 * sr));
    }
    noise(o, sr, r, 0.05, 2.9, 0.05, { bp: 4000, q: 2, env: (x) => Math.min(1, x * 3) * (1 - x) });
  } },
  light_pop: { d: 0.9, sr: 44100, vars: 2, g(o, sr, r) {
    noise(o, sr, r, 0, 0.03, 1.2, { atk: 0.0005, tau: 0.006 }); mode(o, sr, 0, 180, 0.03, 0.4);
    noise(o, sr, r, 0.005, 0.15, 0.2, { bp: 4000, q: 1, tau: 0.08 });
    for (let k = 0; k < 10; k++) { const t = 0.05 + r() * 0.55; hit(o, sr, r, t, [[3000 + r() * 6000, 0.02 + r() * 0.04, (0.1 + r() * 0.15) * (1 - t)]]); }
  } },
  flashlight_click: { d: 0.2, sr: 44100, g(o, sr, r) { clickAt(o, sr, r, 0, 1, 1); clickAt(o, sr, r, 0.055 + r() * 0.02, 0.55, 1.15); } },
  battery_change: { d: 1.4, vars: 1, g(o, sr, r) {
    hit(o, sr, r, 0, [[1300, 0.02, 0.4], [2600, 0.015, 0.3]]); noise(o, sr, r, 0.15, 0.15, 0.25, { bp: 2500, q: 1, env: (x) => Math.sin(Math.PI * x) });
    hit(o, sr, r, 0.6, [[1800, 0.03, 0.3], [3300, 0.02, 0.2]]); hit(o, sr, r, 0.75, [[1700, 0.03, 0.3], [3100, 0.02, 0.2]]);
    hit(o, sr, r, 1.2, [[1500, 0.015, 0.5], [3100, 0.01, 0.3]]);
  } },
  tv_on: { d: 2.0, vars: 1, g(o, sr, r) {
    clickAt(o, sr, r, 0, 0.6, 0.7);
    mode(o, sr, 0.02, 60, 0.5, 0.5); mode(o, sr, 0.02, 120, 0.4, 0.35); mode(o, sr, 0.02, 180, 0.3, 0.2); mode(o, sr, 0.03, 110, 0.3, 0.3);
    noise(o, sr, r, 0.3, 1.7, 0.18, { hp: 300, atk: 0.4, env: (x) => Math.min(1, (1 - x) * 8) });
    const n = o.length; let ph = 0;
    for (let i = 0; i < n; i++) { const t = i / sr, f = 12000 + 3600 * Math.min(1, t / 0.5); ph += f / sr; o[i] += Math.sin(TAU * ph) * 0.015 * Math.min(1, t * 4) * Math.min(1, (n - i) / (0.05 * sr)); }
  } },
  tv_off: { d: 0.8, vars: 1, g(o, sr, r) {
    hit(o, sr, r, 0, [[90, 0.05, 0.5]]); noise(o, sr, r, 0, 0.06, 0.6, { hp: 1000, tau: 0.01 });
    const n = o.length; let ph = 0;
    for (let i = 0; i < n; i++) { const t = i / sr, f = 4000 + 11000 * Math.exp(-t / 0.25); ph += f / sr; o[i] += Math.sin(TAU * ph) * 0.03 * Math.exp(-t / 0.3); }
  } },
  clock_chime: { d: 4.5, vars: 1, g(o, sr, r) {
    const f = 196, P = [[0.5, 3, 0.35], [1, 2.2, 1], [1.003, 2.2, 0.6], [1.183, 1.6, 0.5], [1.506, 1.4, 0.4], [2.0, 1.1, 0.45], [2.514, 0.8, 0.25], [2.662, 0.7, 0.2], [3.011, 0.5, 0.15], [4.166, 0.3, 0.1]];
    for (const [k, tau, a] of P) mode(o, sr, 0.01, f * k, tau, a, 0);
    hit(o, sr, r, 0, [[3200, 0.01, 0.2]]);
  } },
  knock_wall: { d: 2.9, sr: 22050, g(o, sr, r) {
    const T = [0.1, 0.38 + r() * 0.05, 1.3 + r() * 0.4];
    for (const t of T) { hit(o, sr, r, t, [[115, 0.05, 0.6], [205, 0.04, 0.45], [390, 0.03, 0.25], [700, 0.02, 0.12]]); noise(o, sr, r, t, 0.02, 0.35, { lp: 1500, tau: 0.006 }); }
  } },
  win_door: { d: 4.4, vars: 1, g(o, sr, r) {
    hit(o, sr, r, 0, [[850, 0.04, 0.6], [1650, 0.03, 0.4]]);
    creak(o, sr, r, 0.25, 2.0, 0.8, { f: [15, 130, 40], res: [[310, 10, 1], [650, 12, 0.8], [1240, 14, 0.5]] });
    const n = o.length;
    for (let i = 0; i < n; i++) {
      const t = i / sr, e = Math.min(1, Math.max(0, t - 0.6) / 1.2) * Math.min(1, (n - i) / (0.8 * sr));
      o[i] += (Math.sin(TAU * 196 * t) + 0.7 * Math.sin(TAU * 246.9 * t) + 0.6 * Math.sin(TAU * 293.7 * t)) * 0.03 * e;
    }
    for (const [k, a] of [[1, 0.2], [2.76, 0.1], [5.4, 0.05]]) mode(o, sr, 1.2, 1046 * k, 1.2, a);
  } },
  // ---- creature
  entity_breath: { d: 2.6, sr: 22050, g(o, sr, r) {
    noise(o, sr, r, 0, 0.9, 0.35, { bp: 900, q: 2, env: (x) => Math.sin(Math.PI * x) });
    noise(o, sr, r, 0, 0.9, 0.15, { bp: 1900, q: 3, env: (x) => Math.sin(Math.PI * x) });
    noise(o, sr, r, 1.1, 1.35, 0.7, { bp: 500, q: 2, env: (x) => Math.sin(Math.PI * Math.pow(x, 0.5)) });
    noise(o, sr, r, 1.1, 1.35, 0.3, { bp: 1200, q: 3, env: (x) => Math.sin(Math.PI * Math.pow(x, 0.5)) });
    creak(o, sr, r, 1.12, 1.3, 0.35, { f: [35, 50, 30], res: [[500, 5, 1], [1300, 7, 0.4]], rough: 0.5, grain: 0.3 });
  } },
  entity_croak: { d: 2.1, sr: 22050, g(o, sr, r) {
    creak(o, sr, r, 0.05, 1.9, 1, { f: [25, 45, 18], res: [[650, 6, 1], [1100, 8, 0.6], [2500, 10, 0.25]], rough: 0.5, grain: 0.25 });
    noise(o, sr, r, 0.05, 1.9, 0.15, { bp: 1200, q: 1, env: (x) => Math.sin(Math.PI * x) });
  } },
  lullaby_hum: { d: 12.0, sr: 22050, loop: true, g(o, sr, r) {
    // "Au clair de la lune" first phrase, slow, hummed, slightly flat and wobbly.
    const beat = 0.6, notes = [[0, 1], [0, 1], [0, 1], [2, 1], [4, 2], [2, 2], [0, 1], [4, 1], [2, 1], [2, 1], [0, 4]];
    const base = 220 * Math.pow(2, -0.3 / 12);
    let t = 0.4;
    for (const [semi, len] of notes) {
      const d = len * beat, f = base * Math.pow(2, semi / 12);
      vox(o, sr, r, t, d + 0.05, 0.5, {
        f0: (x, tt) => f * (1 + 0.006 * Math.sin(TAU * 0.18 * (t + tt)) - 0.01 * Math.max(0, x - 0.8)),
        form: [[270, 90, 1], [2300, 300, 0.07], [3200, 400, 0.04]], nh: 22, tilt: 1.15,
        env: (x) => Math.min(1, x * d / 0.08) * Math.min(1, (1 - x) * d / 0.12),
        breath: 0.06, bf: 1200, vib: 0.011, vibHz: 5.2, jit: 0.002,
      });
      t += d;
    }
  } },
  whisper: { d: (r) => 1.6 + r() * 0.6, g(o, sr, r) {
    const dur = o.length / sr;
    let t = 0.05;
    while (t < dur - 0.15) {
      const sd = 0.1 + r() * 0.15, f1 = 300 + r() * 600, f2 = 900 + r() * 1600;
      noise(o, sr, r, t, sd, 0.6, { bp: f1, q: 4, atk: 0.02, env: (x) => Math.sin(Math.PI * x) });
      noise(o, sr, r, t, sd, 0.45, { bp: f2, q: 6, atk: 0.02, env: (x) => Math.sin(Math.PI * x) });
      if (r() < 0.3) noise(o, sr, r, t + sd * 0.6, 0.08, 0.25, { hp: 5000, atk: 0.01, env: (x) => Math.sin(Math.PI * x) });
      t += sd + 0.02 + r() * 0.05;
    }
  } },
  giggle: { d: 1.4, g(o, sr, r) {
    let t = 0.08;
    for (let k = 0; k < 5; k++) {
      noise(o, sr, r, t, 0.03, 0.15, { hp: 1500, atk: 0.005 });
      const f = 520 - k * 22 + r() * 20;
      vox(o, sr, r, t + 0.02, 0.09, 0.4, { f0: (x) => f * (1 + 0.06 * Math.sin(Math.PI * x)), form: [[320, 80, 1], [2700, 200, 0.5], [3400, 300, 0.3]], nh: 14, tilt: 0.9, env: (x) => Math.sin(Math.PI * x), breath: 0.2, bf: 2600 });
      t += 0.14 + k * 0.012;
    }
  } },
  jumpscare: { d: 1.9, vars: 2, g(o, sr, r) {
    mode(o, sr, 0, 38, 0.5, 1); noise(o, sr, r, 0, 0.6, 0.8, { lp: 250, tau: 0.2 }); noise(o, sr, r, 0, 0.8, 0.3, { hp: 2500, tau: 0.45 });
    for (const fb of [820, 1060, 1350]) {
      const f = fb * (0.95 + r() * 0.1);
      vox(o, sr, r, 0.01, 1.85, 0.35, {
        f0: (x) => f * (1 + 0.05 * Math.min(1, x * 6) - 0.17 * x), form: [[850, 120, 1], [1250, 150, 0.7], [2900, 250, 0.4]], nh: 12, tilt: 0.6,
        env: (x, t) => Math.min(1, t / 0.015) * (t < 1.2 ? 1 : Math.exp(-(t - 1.2) / 0.2)), breath: 0.25, bf: 3000, vib: 0.04, vibHz: 9, jit: 0.02,
      });
    }
    for (let i = 0; i < o.length; i++) o[i] = Math.tanh(o[i] * 2.2);
  } },
  // ---- player body
  player_gasp: { d: 0.6, g(o, sr, r) {
    noise(o, sr, r, 0, 0.45, 0.8, { bp: 1300, q: 1.2, atk: 0.02, env: (x) => Math.pow(1 - x, 1.5) });
    vox(o, sr, r, 0, 0.15, 0.15, { f0: (x) => 380 - 80 * x, form: [[700, 150, 1], [1200, 200, 0.5]], nh: 12, env: (x) => Math.sin(Math.PI * x) });
  } },
  player_breath_run: { d: 3.12, loop: true, g(o, sr, r) { for (let k = 0; k < 4; k++) breathCycle(o, sr, r, k * 0.78, 0.9 + r() * 0.2, 0.3, 0.38, 0.04, 0); } },
  player_breath_scared: { d: 6.2, loop: true, g(o, sr, r) { for (let k = 0; k < 2; k++) breathCycle(o, sr, r, k * 3.1 + 0.1, 0.8, 1.0, 1.4, 0.3, 7); } },
  heartbeat: { d: 4 * 0.909, sr: 22050, loop: true, g(o, sr, r) { for (let k = 0; k < 4; k++) heartbeatAt(o, sr, r, k * 0.909, 0.92 + r() * 0.12, 0.3); } },
  heartbeat_fast: { d: 8 * 0.469, sr: 22050, loop: true, g(o, sr, r) { for (let k = 0; k < 8; k++) heartbeatAt(o, sr, r, k * 0.469, 0.9 + r() * 0.15, 0.2); } },
  heartbeat_single: { d: 0.7, sr: 22050, g(o, sr, r) { heartbeatAt(o, sr, r, 0.02, 1, 0.28); } },
  // ---- music
  stinger: { d: 3.0, vars: 2, g(o, sr, r) {
    mode(o, sr, 0, 42, 0.6, 1); noise(o, sr, r, 0, 0.8, 0.6, { lp: 300, tau: 0.25 }); noise(o, sr, r, 0, 0.3, 0.3, { hp: 2000, tau: 0.08 });
    for (const fb of [146.8, 155.6, 220, 415.3]) {
      const f = fb * (1 + (r() - 0.5) * 0.006);
      vox(o, sr, r, 0.005, 2.9, 0.22, { f0: () => f, form: [[2500, 3000, 1]], nh: 20, tilt: 1, env: ad(0.02, 1.1), vib: 0.006, vibHz: 6 + r() });
    }
    vox(o, sr, r, 0.02, 1.4, 0.08, { f0: (x) => 1250 - 150 * x, form: [[2500, 800, 1]], nh: 6, env: ad(0.05, 0.6), vib: 0.02, vibHz: 7 });
    for (let i = 0; i < o.length; i++) o[i] = Math.tanh(o[i] * 1.5);
  } },
  chase_music: { d: 6.4, sr: 22050, loop: true, g(o, sr, r) {
    const e8 = 0.2, bass = [0, 0, 1, 0, 0, 1, 0, -1, 0, 0, 1, 0, 3, 1, 0, -1];
    for (let k = 0; k < 32; k++) {
      const semi = bass[k % 16] + (k >= 16 ? 1 : 0), f = 73.42 * Math.pow(2, semi / 12), t = k * e8;
      vox(o, sr, r, t, 0.19, 0.5, { f0: () => f, form: [[300, 900, 1]], nh: 30, tilt: 1, env: ad(0.005, 0.09) });
    }
    for (let b = 0; b < 4; b++) {
      for (const e of [0, 3, 4, 6]) { const t = b * 1.6 + e * e8; mode(o, sr, t, 55, 0.18, 0.9); noise(o, sr, r, t, 0.1, 0.3, { lp: 150, tau: 0.04 }); }
      if (b % 2 === 0) hit(o, sr, r, b * 1.6, [[311, 0.6, 0.3], [742, 0.4, 0.2], [1187, 0.3, 0.15], [1730, 0.25, 0.1]], 0.6);
    }
    for (const f of [440, 466.2]) {
      vox(o, sr, r, 3.2, 3.2, 0.1, { f0: () => f, form: [[1800, 2000, 1]], nh: 16, env: (x, t) => (0.3 + 0.7 * x) * (0.6 + 0.4 * Math.sin(TAU * 12 * t)) * Math.min(1, (1 - x) * 20) });
    }
    noise(o, sr, r, 4.8, 1.6, 0.12, { bp: 1500, q: 0.8, env: (x) => x * x });
  } },
  // ---- ambience beds (periodic)
  room_tone: { d: 6, sr: 22050, loop: true, g(o, sr, r) {
    const lp = new BQ('lp', 220, 0.7, sr), hp = new BQ('hp', 3000, 0.7, sr); let br = 0;
    bed(o, sr, r, (j, t, w, w2) => { br = br * 0.998 + w * 0.04; return lp.p(br) * 1.0 + hp.p(w2) * 0.03 + Math.sin(TAU * 60 * t) * 0.012 + Math.sin(TAU * 120 * t) * 0.008; });
  } },
  furnace: { d: 8, sr: 22050, loop: true, g(o, sr, r) {
    const lp = new BQ('lp', 90, 0.7, sr), bp = new BQ('bp', 280, 0.6, sr), af = new BQ('lp', 1400, 0.7, sr), ah = new BQ('hp', 250, 0.7, sr); let br = 0;
    bed(o, sr, r, (j, t, w, w2) => {
      br = br * 0.997 + w * 0.05;
      const fl = 0.85 + 0.08 * Math.sin(TAU * 4.125 * t) + 0.07 * Math.sin(TAU * 6.25 * t + 1);
      return lp.p(br) * 1.2 * (1 + 0.15 * Math.sin(TAU * t * 3 / 8)) + bp.p(w) * 1.5 * fl + ah.p(af.p(w2)) * 0.25 + Math.sin(TAU * 120 * t) * 0.02;
    });
  } },
  ambience_drone: { d: 12, sr: 22050, loop: true, g(o, sr, r) {
    const bp = new BQ('bp', 140, 2.5, sr);
    bed(o, sr, r, (j, t, w) => {
      const s = Math.sin(TAU * 36.75 * t) * 0.5 + Math.sin(TAU * 37 * t) * 0.5 + Math.sin(TAU * 55 * t) * 0.3 + Math.sin(TAU * (662 / 12) * t) * 0.3 + Math.sin(TAU * 73.5 * t) * 0.12;
      const nz = bp.p(w) * 3 * (0.5 + 0.5 * Math.sin(TAU * t / 12));
      const hi = Math.sin(TAU * (5594 / 12) * t) * 0.025 * (0.5 + 0.5 * Math.sin(TAU * 0.25 * t));
      return Math.tanh((s * 0.5 + nz + hi) * 0.9);
    });
  } },
  wind_outside: { d: 10, sr: 22050, loop: true, g(o, sr, r) {
    const bp = new BQ('bp', 500, 1.2, sr), moan = new BQ('bp', 420, 25, sr), lp = new BQ('lp', 120, 0.7, sr); let br = 0, c = 0;
    bed(o, sr, r, (j, t, w, w2) => {
      if (c-- <= 0) { c = 32; bp.set(500 + 250 * Math.sin(TAU * t / 10) + 120 * Math.sin(TAU * 0.3 * t + 1)); moan.set(420 + 60 * Math.sin(TAU * 0.2 * t)); }
      const g = 0.55 + 0.3 * Math.sin(TAU * 0.1 * t + 0.5) + 0.15 * Math.sin(TAU * 0.4 * t + 2);
      br = br * 0.996 + w2 * 0.05;
      return bp.p(w) * 2 * g + moan.p(w) * 5 * g * g + lp.p(br) * g;
    });
  } },
  light_buzz: { d: 4, sr: 32000, loop: true, g(o, sr, r) {
    const H = [0.25, 1, 0.3, 0.55, 0.15, 0.35, 0.1, 0.2, 0.08, 0.12], P = H.map(() => r() * TAU), bp = new BQ('bp', 3000, 0.8, sr);
    bed(o, sr, r, (j, t, w) => {
      let y = 0;
      for (let k = 0; k < H.length; k++) y += H[k] * Math.sin(TAU * 60 * (k + 1) * t + P[k]);
      const arc = Math.pow(Math.abs(Math.sin(TAU * 60 * t)), 12);
      return y * 0.3 * (1 + 0.05 * Math.sin(TAU * 0.25 * t)) + bp.p(w) * arc * 0.5;
    });
  } },
  fan_hum: { d: 6, sr: 22050, loop: true, g(o, sr, r) {
    const lp = new BQ('lp', 700, 0.7, sr), hp = new BQ('hp', 90, 0.7, sr), tk = new BQ('hp', 2000, 0.7, sr);
    bed(o, sr, r, (j, t, w, w2) => {
      const blade = 1 + 0.18 * Math.pow(Math.sin(Math.PI * 25 / 6 * t), 2) + 0.05 * Math.sin(TAU * t * 5 / 6);
      const rev = (t * 5 / 6) % 1, tick = rev < 0.004 ? w2 * 2 : 0;
      return hp.p(lp.p(w)) * blade + Math.sin(TAU * 120 * t) * 0.04 + Math.sin(TAU * 240 * t) * 0.02 + tk.p(tick) * 0.3;
    });
  } },
  tv_static: { d: 3, sr: 44100, loop: true, g(o, sr, r) {
    const hp = new BQ('hp', 250, 0.7, sr), pk = new BQ('pk', 4500, 1, sr, 3);
    bed(o, sr, r, (j, t, w, w2) => {
      const fl = 1 + 0.08 * Math.sin(TAU * 60 * t);
      const crack = Math.abs(w2) > 0.9995 ? w2 * 4 : 0;
      return pk.p(hp.p(w)) * fl + Math.sin(TAU * 60 * t) * 0.03 + Math.sin(TAU * 15734 * t) * 0.012 + crack;
    });
  } },
  clock_tick: { d: 2, sr: 44100, loop: true, g(o, sr, r) {
    for (const [t, k] of [[0, 1], [1, 0.92]]) {
      hit(o, sr, r, t, [[3900 * k, 0.004, 0.6], [5700 * k, 0.003, 0.4], [8200 * k, 0.002, 0.25], [1250 * k, 0.01, 0.25]]);
      noise(o, sr, r, t, 0.01, 0.3, { hp: 5000, tau: 0.002 });
      hit(o, sr, r, t + 0.12, [[4600 * k, 0.002, 0.08]]);
    }
  } },
};
