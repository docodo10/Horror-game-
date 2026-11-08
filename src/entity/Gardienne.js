import * as THREE from 'three';
import * as L from '../config/layout.js';
import { GardienneModel } from './GardienneModel.js';

// Public API (kept from the stub contract):
//   constructor(game); async init(); update(dt); reset(kind)
//   .state     'dormant'|'waking'|'descending'|'searching'|'chasing'|'returning'|'jumpscare'|'disabled'
//   .position  Vector3 (feet)   .root  THREE.Object3D (model)
//   .fear      0..1  how scary the current situation is (distance, visibility, chase) — read by Game every frame
//   .active    true when she is in the basement (any state except dormant/disabled)
//   summon(targetPos, { reason, aggressive })  scripted visit: comes down and searches around targetPos
//   setAggression(level)   0 calm (rare visits) .. 2 hunting (frequent visits, longer searches, faster)
//   setEnabled(bool)
// Listens: 'noise' {position, loudness} (suspicion), 'player:hide' (did she see the player hide?)
// Emits:   'entity:state' {state, prev}, 'entity:spotted' (first frame she sees the player), 'entity:caught'
// Extra (debug/tests): .aggression, .suspicion, .log (state transitions when ?debug), debugPlace(x, y, z, yaw, mode)
//
// Behaviour summary
//  dormant    upstairs, invisible. Noise raises suspicion (muffled by the floor, scaled by distance to the stairwell and
//             aggression). After the first scripted visit she also patrols every 90–180 s (shorter when aggressive).
//  waking     heavy steps cross the ceiling toward the stairwell door (ceiling_steps), feet shadows under the door,
//             sometimes a knock (knock_wall) — then she opens the upstairs door (its `locked` flag is preserved).
//  descending walks down the stairs (entity_step_stairs), door left open.
//  searching  goes to the noise, then 3–5 random nodes nearby; pauses with jerky listening head tilts, hums
//             (lullaby_hum). If she saw the player hide in the closet she walks to it, opens it -> jumpscare.
//  chasing    FOV 110°, range 12 m × player visibility, LOS via world.lineBlocked. Spots: freezes, croaks, charges at
//             2.9 m/s (direct when the straight line is free, A* otherwise, repath 0.7 s). Loses the player after 4 s.
//  returning  walks back up, closes the door behind her, dormant again.
//  jumpscare  within 0.85 m + LOS: takes the camera (player.cameraOverride), face 0.45 m away, scream, flash/shake,
//             ~1.4 s, then emits 'entity:caught'.

const TAU = Math.PI * 2;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const rand = (a, b) => a + Math.random() * (b - a);
const dampTo = (cur, target, rate, dt) => cur + (target - cur) * (1 - Math.exp(-rate * dt));
const angWrap = (a) => { while (a > Math.PI) a -= TAU; while (a < -Math.PI) a += TAU; return a; };

const RADIUS = 0.3;
const WALK_SPEED = 0.95;
const STAIR_SPEED = 0.78;
const CHASE_SPEED = 2.9;
const FOV_COS = Math.cos(THREE.MathUtils.degToRad(55));
const SIGHT_RANGE = 12;
const CATCH_DIST = 0.85;
const LOSE_TIME = 4;
const SUSPICION_MAX = 1.6;
const DOOR_EAR = new THREE.Vector3(-3.0, 3.2, -2.75);      // where she "listens" from (stairwell door)
const DOOR_BEHIND = new THREE.Vector3(-3.0, 3.6, -2.95);   // knocks / breath behind the closed door
const CEILING_Y = L.ROOM.ceilingY + 0.45;                  // footsteps above the basement ceiling

export class Gardienne {
  constructor(game) {
    this.game = game;
    this.state = 'dormant';
    this.position = new THREE.Vector3(-3.0, L.UPPER.floorY, -3.6);
    this.fear = 0;
    this.active = false;
    this.root = new THREE.Group();
    this.root.name = 'Gardienne';
    this.model = null;
    this.enabled = true;
    this.aggression = 0;
    this.suspicion = 0;
    this.yaw = 0;
    this.log = [];

    this._t = 0;
    this._stateT = 0;
    this._home = new THREE.Vector3(-3.0, L.UPPER.floorY, -3.6);
    this._target = new THREE.Vector3();
    this._lastNoise = new THREE.Vector3();
    this._lastSeen = new THREE.Vector3();
    this._lastSeenT = -100;
    this._seeing = false;
    this._seeT = 0;
    this._lostT = 0;
    this._path = [];
    this._pathI = 0;
    this._repathT = 0;
    this._speed = 0;
    this._dispY = this.position.y;
    this._prevPos = new THREE.Vector3().copy(this.position);
    this._velY = 0;
    this._moveSpeed = 0;
    this._wpI = -1;
    this._bestD = Infinity;
    this._noImpT = 0;
    this._stuck = 0;
    this._backoffT = 0;
    this._backoff = new THREE.Vector3();
    this._firstVisitDone = false;
    this._visits = 0;
    this._patrolT = rand(90, 180);
    this._graceT = 0;
    this._sawHide = false;
    this._doorBusy = false;
    this._doorOpenedByMe = false;
    this._doorWasLocked = null;
    this._closetOpenedByMe = false;
    this._strip = 0;
    this._hum = null;
    this._breathT = 3;
    this._stairSfxT = 0;
    this._eyeshine = 0.1;
    this._debugHold = null;
    this._caughtSent = false;
    this._jump = null;
    this._sub = null;       // per-state scratch data
    this._spotHold = 0;

    // scratch vectors (no per-frame allocations)
    this._v1 = new THREE.Vector3(); this._v2 = new THREE.Vector3(); this._v3 = new THREE.Vector3();
    this._eye = new THREE.Vector3(); this._pEye = new THREE.Vector3(); this._pChest = new THREE.Vector3();
    this._face = new THREE.Vector3(); this._camPos = new THREE.Vector3(); this._camDir = new THREE.Vector3();
    this._m4 = new THREE.Matrix4(); this._q = new THREE.Quaternion(); this._up = new THREE.Vector3(0, 1, 0);
    this._ctx = { mode: 'idle', speed: 0, stairs: 0, look: null, jumpT: -1, aggression: 0, eyeshine: 0.1 };
    this._lookV = new THREE.Vector3();
    this._humPos = new THREE.Vector3();
  }

  // ===================================================================================== lifecycle
  async init() {
    const g = this.game;
    g.scene.add(this.root);
    const hall = g.world?.nav?.nodes?.hall?.pos;
    if (hall) this._home.copy(hall);
    this.position.copy(this._home);
    try {
      this.model = new GardienneModel(g, { quality: g.renderer?.quality });
      this.root.add(this.model.root);
      this.model.onFootstep = (side, pos) => this._onFootstep(side, pos);
    } catch (e) {
      console.error('[gardienne] model build failed', e);
      this.model = null;
    }
    // Close fill light used only during the jumpscare (always present so the light count never changes -> no
    // shader recompilation hitch at the worst possible moment).
    this.jsLight = new THREE.PointLight(0xc9d6ff, 0, 3, 2);
    this.jsLight.castShadow = false;
    this.jsLight.name = 'gardienne_jumpscare_light';
    g.scene.add(this.jsLight);

    g.events.on('noise', (p) => this._onNoise(p));
    g.events.on('player:hide', (p) => this._onHide(p));
    // Visible during init so renderer.warmup() compiles her shaders; hidden as soon as the game state settles.
    g.events.on('game:state', () => this._applyVisibility());
    this._placeRoot(0);
    this.root.visible = true;
    if (g.params?.noentity) this.setEnabled(false);
  }

  setEnabled(on) {
    if (!on) {
      this._stopSounds();
      this.enabled = false;
      this._setState('disabled');
      this.active = false;
      this.fear = 0;
      this.root.visible = false;
      this._setStrip(0);
      this.game.world?.lighting?.setStress?.(0);
    } else if (!this.enabled || this.state === 'disabled') {
      this.enabled = true;
      this.position.copy(this._home);
      this._setState('dormant');
      this._applyVisibility();
    }
  }

  setAggression(level) {
    this.aggression = clamp(Math.round(level ?? 0), 0, 2);
    if (this.aggression >= 2 && this.state === 'dormant') this._patrolT = Math.min(this._patrolT, rand(18, 32));
  }

  /** Scripted visit (e.g. breaker flipped): she comes down and searches around targetPos. */
  summon(targetPos, { reason = 'script', aggressive = false } = {}) {
    if (!this.enabled || this.state === 'disabled') return;
    if (aggressive) this.aggression = Math.max(this.aggression, 1);
    const target = this._floorTarget(targetPos ?? this.game.player?.position ?? this._home);
    this._summoned = true;
    switch (this.state) {
      case 'dormant': this._wake(target, reason === 'breaker' ? 3.6 : rand(2.4, 3.4), reason); break;
      case 'waking': this._target.copy(target); break;
      case 'chasing': case 'jumpscare': break;
      default: this._beginSearch(target, true); break;
    }
  }

  reset(kind) {
    const g = this.game;
    this._stopSounds();
    this._debugHold = null;
    this._jump = null;
    this._caughtSent = false;
    if (this.jsLight) this.jsLight.intensity = 0;
    this.model?.setExposure(1);
    g.renderer?.setBlur?.(0);
    // put the house back the way she found it
    if (this._closetOpenedByMe) {
      this._closetOpenedByMe = false;
      const cd = g.world?.handles?.['door.closet'];
      if (cd?.isOpen) cd.close?.()?.catch?.(() => {});
    }
    this._closeUpstairsDoor(true);
    this.suspicion = 0;
    this._sawHide = false;
    this._seeing = false;
    this._path.length = 0;
    this.position.copy(this._home);
    this._prevPos.copy(this.position);
    this._dispY = this.position.y;
    this.yaw = 0;
    this.fear = 0;
    if (kind === 'caught') {
      this._graceT = 25;
      this._patrolT = Math.max(this._patrolT, rand(45, 80));
    }
    this._setStrip(0);
    g.world?.lighting?.setStress?.(0);
    if (this.state !== 'disabled') this._setState('dormant');
    this.model?.resetSimulation();
    this._placeRoot(0);
    this._applyVisibility();
  }

  /** Debug/test helper: freeze the AI and show her at a spot in a given animation mode (null = release). */
  debugPlace(x, y, z, yaw = 0, mode = 'idle') {
    if (x === null || x === undefined) { this._debugHold = null; this._applyVisibility(); return; }
    this._debugHold = { mode, jumpT: mode === 'jumpscare' ? 0 : -1 };
    this.position.set(x, y ?? this.game.world.groundHeightAt(x, z), z);
    this._dispY = this.position.y;
    this.yaw = yaw;
    this.model?.resetSimulation();
    this.root.visible = true;
  }

  // ===================================================================================== main update
  update(dt) {
    if (this.state === 'disabled' || !this.enabled) { this.fear = 0; return; }
    dt = Math.min(dt, 0.05);
    this._t += dt;
    this._stateT += dt;
    const g = this.game;
    const player = g.player;

    if (this._debugHold) { this._debugUpdate(dt); return; }

    if (this._graceT > 0) this._graceT -= dt;
    this._updatePerception(dt);

    switch (this.state) {
      case 'dormant': this._updDormant(dt); break;
      case 'waking': this._updWaking(dt); break;
      case 'descending': this._updDescending(dt); break;
      case 'searching': this._updSearching(dt); break;
      case 'chasing': this._updChasing(dt); break;
      case 'returning': this._updReturning(dt); break;
      case 'jumpscare': this._updJumpscare(dt); break;
      default: break;
    }

    // speed / vertical motion bookkeeping
    const dx = this.position.x - this._prevPos.x, dz = this.position.z - this._prevPos.z;
    const hs = Math.hypot(dx, dz) / Math.max(dt, 1e-4);
    this._moveSpeed = hs > 6 ? 0 : dampTo(this._moveSpeed, hs, 10, dt);
    this._velY = dampTo(this._velY, (this.position.y - this._prevPos.y) / Math.max(dt, 1e-4), 6, dt);
    this._prevPos.copy(this.position);

    if (this.state !== 'jumpscare') this._placeRoot(dt);
    if (this.root.visible && this.model && this.state !== 'jumpscare') this._animate(dt);
    this._updateFearAndStress(dt, player);
    this._updateAudio(dt);
  }

  // ===================================================================================== states
  _setState(s) {
    const prev = this.state;
    if (prev === s) return;
    this.state = s;
    this._stateT = 0;
    this.active = !(s === 'dormant' || s === 'disabled');
    if (s !== 'searching') this._stopHum();
    if (this.game.debug) {
      this.log.push({ t: +(this.game.time ?? this._t).toFixed(1), state: s, prev, pos: [+this.position.x.toFixed(2), +this.position.y.toFixed(2), +this.position.z.toFixed(2)] });
      if (this.log.length > 300) this.log.shift();
    }
    this._applyVisibility();
    this.game.events.emit('entity:state', { state: s, prev });
  }

  _applyVisibility() {
    const s = this.state;
    const gs = this.game.state;
    if (this._debugHold) { this.root.visible = true; return; }
    if (gs === 'loading') { this.root.visible = true; return; } // shader warmup
    this.root.visible = this.enabled && !(s === 'dormant' || s === 'waking' || s === 'disabled');
  }

  _wake(target, duration, reason) {
    this._target.copy(target);
    this.suspicion = 0;
    this._visits++;
    const from = this._v1.set(clamp(target.x, L.ROOM.minX + 0.4, L.ROOM.maxX - 0.4), CEILING_Y, clamp(target.z, L.ROOM.minZ + 0.4, L.ROOM.maxZ - 0.4));
    this._sub = {
      reason, dur: duration, stepT: 0.2, stepI: 0,
      from: from.clone(), to: new THREE.Vector3(-3.0, CEILING_Y, -2.4),
      knock: reason === 'breaker' || this._visits === 1 || Math.random() < 0.45, knocked: false,
      walk: null, walkPos: new THREE.Vector3(),
    };
    // slow patrol: one continuous recorded walk across the floor above; urgent wakes: individual heavy steps
    if (reason === 'patrol' && duration >= 2.8) {
      this._sub.walkPos.copy(this._sub.from);
      this._sub.walk = this.game.audio?.play?.('ceiling_walk', { position: this._sub.from.clone(), volume: 0.9 }) ?? null;
    }
    this.position.copy(this._home);
    this._setState('waking');
  }

  _updDormant(dt) {
    this.position.copy(this._home);
    if (this._graceT > 0) { this.suspicion = Math.min(this.suspicion, SUSPICION_MAX * 0.5); return; }
    if (this.suspicion < SUSPICION_MAX) this.suspicion = Math.max(0, this.suspicion - dt * 0.06);
    else {
      this.suspicion = 0;
      this._wake(this._floorTarget(this._lastNoise), rand(2.2, 3.6), 'noise');
      return;
    }
    if (this._firstVisitDone) {
      this._patrolT -= dt * (1 + this.aggression * 0.6);
      if (this._patrolT <= 0) {
        this._patrolT = this._nextPatrolDelay();
        const pp = this.game.player?.position;
        const tgt = pp ? this.game.world.randomNodeNear(pp, 3.5) : this.game.world.randomNodeNear(this._home, 8);
        this._wake(this._floorTarget(tgt), rand(2.5, 4), 'patrol');
      }
    }
  }

  _nextPatrolDelay() {
    const a = this.aggression;
    return a >= 2 ? rand(45, 90) : a === 1 ? rand(70, 140) : rand(90, 180);
  }

  _updWaking(dt) {
    const s = this._sub;
    const audio = this.game.audio;
    const k = clamp(this._stateT / Math.max(0.5, s.dur - 0.9), 0, 1);
    s.stepT -= dt;
    if (s.walk) {
      s.walkPos.copy(s.from).lerp(s.to, k);
      s.walk.setPosition?.(s.walkPos);
      if (k >= 1) { try { s.walk.stop?.(0.6); } catch (e) { /* ignore */ } s.walk = null; }
    } else if (s.stepT <= 0 && k < 1) {
      s.stepT = rand(0.55, 0.72);
      const p = this._v2.copy(s.from).lerp(s.to, k);
      audio?.play?.('ceiling_steps', { position: p.clone(), volume: 0.75 + 0.25 * k });
      s.stepI++;
    }
    // behind the door: feet shadows in the light strip, maybe a knock
    if (this._stateT > s.dur - 1.3) this._setStrip(0.75 + 0.25 * Math.sin(this._t * 9));
    if (s.knock && !s.knocked && this._stateT > s.dur - 1.0) {
      s.knocked = true;
      audio?.play?.('knock_wall', { position: DOOR_BEHIND.clone(), volume: 0.9 });
    }
    if (this._stateT >= s.dur) this._startDescending();
  }

  _startDescending() {
    this.position.copy(this._home);
    this._prevPos.copy(this.position);
    this._dispY = this.position.y;
    this.yaw = 0; // facing the door (south)
    this.model?.resetSimulation();
    this._setState('descending');
    this._sub = { phase: 'door', t: 0 };
    this._openUpstairsDoor();
    this._setPath(this._target);
  }

  _updDescending(dt) {
    const s = this._sub;
    if (s.phase === 'door') {
      s.t += dt;
      this._setStrip(this._doorBusy ? 0.5 : 0);
      if (this._doorBusy && s.t < 2.0) return;   // wait for the door animation (with a safety timeout)
      s.phase = 'walk';
      this._setStrip(0);
    }
    if (this._seeing) { this._startChase(); return; }
    const onStairs = this._onStairs();
    const arrived = this._followPath(onStairs ? STAIR_SPEED : WALK_SPEED, dt);
    // down in the basement, off the stairs -> searching
    if ((this.position.y < 0.05 && !onStairs) || arrived) this._beginSearch(this._target, false);
  }

  _beginSearch(target, reset) {
    const w = this.game.world;
    const n = 3 + this.aggression + (Math.random() < 0.5 ? 1 : 0);
    const pts = [this._floorTarget(target)];
    for (let i = 0; i < n; i++) {
      let p = null;
      for (let tries = 0; tries < 5; tries++) {
        const c = w.randomNodeNear(target, 3.5);
        if (!pts.some((q) => q.distanceToSquared(c) < 0.5)) { p = c; break; }
      }
      if (p) pts.push(p);
    }
    const keepT = (!reset && this.state === 'searching' && this._sub?.total) || 0;
    this._sub = { pts, i: 0, phase: 'go', pauseT: 0, total: keepT, maxT: 50 + this.aggression * 20, closet: false };
    if (this.state !== 'searching') this._setState('searching');
    this._setPath(pts[0]);
  }

  _updSearching(dt) {
    const s = this._sub;
    s.total += dt;
    const player = this.game.player;
    if (this._seeing) { this._startChase(); return; }
    // she saw the player slip into the closet: go straight for it
    if (this._sawHide && player?.hidden && !s.closet) {
      s.closet = true; s.phase = 'closetGo';
      this._setPath(this._closetApproach());
    }
    if (s.phase === 'closetGo' || s.phase === 'closetReach') { this._updClosetCheck(dt); return; }

    if (!this._hum && s.phase !== 'closetGo') this._startHum();
    if (s.phase === 'go') {
      if (s.total > s.maxT + 10) { this._startReturning(); return; }
      const arrived = this._followPath(WALK_SPEED * (1 + this.aggression * 0.06), dt);
      if (arrived) {
        s.phase = 'pause';
        s.pauseT = rand(1.6, 3.4) + this.aggression * 0.4;
        this._onSearchPause();
      }
    } else if (s.phase === 'pause') {
      s.pauseT -= dt;
      // slowly turn in place while listening
      this.yaw = angWrap(this.yaw + Math.sin(this._t * 0.7) * dt * 0.6);
      if (s.pauseT <= 0) {
        s.i++;
        if (s.i >= s.pts.length || s.total > s.maxT) { this._startReturning(); return; }
        s.phase = 'go';
        this._setPath(s.pts[s.i]);
      }
    }
  }

  _onSearchPause() {
    const audio = this.game.audio, player = this.game.player;
    const d = player ? this.position.distanceTo(player.position) : 99;
    if (player?.hidden && d < 3.5 && Math.random() < 0.4) {
      audio?.play?.('whisper', { position: this.model ? this.model.getHeadWorld(this._v2).clone() : this.position.clone(), volume: 0.75 });
    } else if (d > 6 && Math.random() < 0.08) {
      audio?.play?.('giggle', { position: this.position.clone().setY(this.position.y + 1.2), volume: 0.5 });
    }
  }

  _closetApproach() {
    const c = L.CLOSET.door;
    return this._v3.set(c.x + 0.45, 0, c.centerZ).clone();
  }

  _updClosetCheck(dt) {
    const s = this._sub;
    const c = L.CLOSET.door;
    if (s.phase === 'closetGo') {
      this._stopHum();
      const arrived = this._followPath(WALK_SPEED * 1.15, dt);
      const dd = Math.hypot(this.position.x - (c.x + 0.45), this.position.z - c.centerZ);
      if (arrived || dd < 0.25) {
        s.phase = 'closetReach'; s.reachT = 0;
        this.yaw = -Math.PI / 2; // facing west, toward the louvered door
      }
      return;
    }
    // reach for the door, open it, then the jumpscare
    s.reachT += dt;
    this.yaw = dampTo(this.yaw, -Math.PI / 2, 8, dt);
    if (s.reachT > 0.55 && !s.opened) {
      s.opened = true;
      const door = this.game.world?.handles?.['door.closet'];
      if (door && !door.isOpen) { this._closetOpenedByMe = true; door.open?.()?.catch?.(() => {}); }
    }
    if (s.reachT > 0.95) {
      if (this.game.player?.hidden) this._startJumpscare(true);
      else { this._sawHide = false; s.phase = 'pause'; s.pauseT = 1; s.closet = false; }
    }
  }

  _startChase() {
    const first = this.state !== 'chasing';
    this._setState('chasing');
    this._lostT = 0;
    this._repathT = 0;
    this._speed = 0.6;
    if (first) {
      this._spotHold = 0.45;
      this.game.events.emit('entity:spotted', {});
      const head = this.model ? this.model.getHeadWorld(this._v2).clone() : this.position.clone().setY(this.position.y + 1.7);
      this.game.audio?.play?.('entity_croak', { position: head, volume: 1 });
      this._breathT = 1.2;
    }
  }

  _updChasing(dt) {
    const g = this.game, player = g.player, w = g.world;
    if (!player) { this._startReturning(); return; }
    const pp = player.position;
    if (this._seeing) { this._lostT = 0; }
    else {
      this._lostT += dt * (player.hidden && !this._sawHide ? 3 : 1);
      if (this._sawHide && player.hidden) { this._beginSearch(this._lastSeen, true); return; }
      if (this._lostT > LOSE_TIME) { this._beginSearch(this._lastSeen, true); return; }
    }
    // freeze-and-stare moment when she first spots the player
    if (this._spotHold > 0) {
      this._spotHold -= dt;
      const tYaw = Math.atan2(pp.x - this.position.x, pp.z - this.position.z);
      this.yaw = this._turnToward(this.yaw, tYaw, 9, dt);
      return;
    }
    const target = this._seeing ? pp : this._lastSeen;
    const top = CHASE_SPEED + (this.aggression >= 2 ? 0.15 : 0);
    this._speed = Math.min(top, this._speed + dt * 3.2);
    // caught?
    const dy = Math.abs(pp.y - this.position.y);
    const dh = Math.hypot(pp.x - this.position.x, pp.z - this.position.z);
    if (this._seeing && dh < CATCH_DIST && dy < 0.9 && !player.hidden) { this._startJumpscare(false); return; }
    const direct = dy < 0.35 && !this._onStairs() && !w.segmentBlocked(this.position.x, this.position.z, target.x, target.z, RADIUS * 0.9, this.position.y + 0.3, this.position.y + 1.9);
    if (direct) {
      this._path.length = 0;
      this._moveToward(target, this._speed, dt, 7);
    } else {
      this._repathT -= dt;
      if (this._repathT <= 0 || !this._path.length) { this._repathT = 0.7; this._setPath(target); }
      this._followPath(this._onStairs() ? Math.min(this._speed, 2.1) : this._speed, dt, 7);
    }
  }

  _startReturning() {
    this._setState('returning');
    this._sub = { phase: 'walk', t: 0 };
    this._setPath(this._home);
  }

  _updReturning(dt) {
    const s = this._sub;
    if (s.phase === 'walk') {
      if (this._seeing) { this._startChase(); return; }
      const arrived = this._followPath(this._onStairs() ? STAIR_SPEED : WALK_SPEED, dt);
      const atHall = this.position.y > 2.5 && this.position.z < L.ROOM.minZ - 0.45;
      if (arrived && !atHall && this.position.distanceTo(this._home) > 0.8) { this._detour(this._home); return; }
      if (arrived || atHall) {
        s.phase = 'door'; s.t = 0;
        this.yaw = Math.PI; // back to the hallway
        this._closeUpstairsDoor(false);
      }
      return;
    }
    s.t += dt;
    this._setStrip(s.t < 1.6 ? 0.7 + 0.3 * Math.sin(this._t * 7) : 0);
    if (s.t > 1.8 && (!this._doorBusy || s.t > 3.5)) {
      this._firstVisitDone = true;
      this._patrolT = Math.max(this._patrolT, this._nextPatrolDelay() * (this._summoned ? 0.8 : 1));
      this._summoned = false;
      this._setStrip(0);
      this.position.copy(this._home);
      this._setState('dormant');
    }
  }

  // ===================================================================================== jumpscare
  _startJumpscare(fromCloset) {
    const g = this.game, player = g.player, cam = g.camera;
    if (g.state !== 'playing') { this._startReturning(); return; }
    this._stopSounds();
    this._setState('jumpscare');
    if (player) { player.cameraOverride = true; player.enabled = false; }
    cam.getWorldPosition(this._camPos);
    // direction from the camera to her (horizontal)
    const dir = this._camDir.set(this.position.x - this._camPos.x, 0, this.position.z - this._camPos.z);
    if (dir.lengthSq() < 1e-4) cam.getWorldDirection(dir).setY(0);
    dir.normalize();
    const startDist = fromCloset ? 0.75 : clamp(Math.hypot(this.position.x - this._camPos.x, this.position.z - this._camPos.z), 0.6, 1.1);
    this._jump = {
      t: 0, fromCloset, startDist, camPos: this._camPos.clone(), dir: dir.clone(), camQ: cam.quaternion.clone(),
      yaw: Math.atan2(-dir.x, -dir.z), shook: false,
    };
    this.yaw = this._jump.yaw;
    g.audio?.play?.('jumpscare', { volume: 1 });
    g.renderer?.flash?.(0x7a0b05, 0.55, 0.35);
    g.renderer?.shake?.(1, 1.3);
    g.renderer?.setBlur?.(0.22);
    this.root.visible = true;
    this.model?.resetSimulation();
  }

  _updJumpscare(dt) {
    const j = this._jump;
    if (!j) return;
    const g = this.game, cam = g.camera, m = this.model;
    j.t += dt;
    if (g.player && !this._caughtSent) { g.player.cameraOverride = true; g.player.enabled = false; }
    // her body: facing the camera, lunging from startDist to 0.45 m (face distance)
    const k = clamp(j.t / 0.14, 0, 1);
    const faceDist = THREE.MathUtils.lerp(j.startDist, 0.45, 1 - (1 - k) * (1 - k));
    this.yaw = j.yaw;
    this.root.rotation.y = this.yaw;
    if (m) {
      const ctx = this._ctx;
      ctx.mode = 'jumpscare'; ctx.speed = 0; ctx.stairs = 0; ctx.look = null; ctx.jumpT = j.t; ctx.aggression = this.aggression; ctx.eyeshine = 1;
      m.update(dt, ctx);
      m.getFaceWorld(this._face);
      // desired face position: in front of the camera at eye height (slightly low, she looms over)
      const want = this._v1.copy(j.camPos).addScaledVector(j.dir, faceDist);
      want.y = j.camPos.y + 0.05 + Math.sin(j.t * 31) * 0.004;
      this.root.position.add(this._v2.subVectors(want, this._face));
      this.root.updateMatrixWorld(true);
      m.getFaceWorld(this._face);
      // exposure compensation for the flashlight at point-blank range + cold fill light
      const fl = g.player?.flashlight;
      const flI = fl?.on ? (fl.light?.intensity ?? 30) : 0;
      const d2 = Math.max(0.04, this._face.distanceToSquared(j.camPos));
      const Ef = flI / d2;
      m.setExposure(clamp(9 / Math.max(9, Ef + 9), 0.03, 1));
      this.jsLight.position.copy(j.camPos).lerp(this._face, 0.35);
      this.jsLight.position.y -= 0.12;
      this.jsLight.intensity = (0.55 + 0.25 * Math.sin(j.t * 43) * Math.sin(j.t * 17)) * clamp(j.t / 0.05, 0, 1);
    }
    // camera: snaps to her face, trembling
    cam.position.copy(j.camPos);
    cam.position.x += (Math.random() - 0.5) * 0.008; cam.position.y += (Math.random() - 0.5) * 0.008;
    const target = m ? this._face : this._v1.copy(this.position).setY(this.position.y + 1.7);
    this._m4.lookAt(cam.position, target, this._up);
    this._q.setFromRotationMatrix(this._m4);
    j.camQ.slerp(this._q, 1 - Math.exp(-28 * dt));
    cam.quaternion.copy(j.camQ);
    cam.updateMatrixWorld(true);
    this.fear = 1;
    if (j.t > 1.4 && !this._caughtSent) {
      this._caughtSent = true;
      g.events.emit('entity:caught', {});
    }
  }

  // ===================================================================================== perception
  _updatePerception(dt) {
    const s = this.state;
    const canLook = s === 'descending' || s === 'searching' || s === 'chasing' || s === 'returning';
    if (!canLook) { this._seeing = false; return; }
    this._seeT -= dt;
    if (this._seeT > 0) return;
    this._seeT = s === 'chasing' ? 0.08 : 0.12;
    const was = this._seeing;
    this._seeing = this._canSeePlayer();
    if (this._seeing) {
      this._lastSeen.copy(this.game.player.position);
      this._lastSeenT = this._t;
    }
    void was;
  }

  _canSeePlayer() {
    const g = this.game, player = g.player, w = g.world;
    if (!player || player.hidden) return false;
    if (g.state !== 'playing') return false;
    const vis = clamp(player.getVisibility?.() ?? 0.5, 0, 1);
    if (vis <= 0.01) return false;
    const eye = this._eyePos(this._eye);
    const pe = player.eyePosition ? player.eyePosition(this._pEye) : this._pEye.copy(player.position).setY(player.position.y + 1.6);
    const d = eye.distanceTo(pe);
    const sense = 1.4;
    if (d > Math.max(SIGHT_RANGE * vis, sense)) return false;
    if (d > sense) {
      const fx = Math.sin(this.yaw), fz = Math.cos(this.yaw);
      const dx = pe.x - eye.x, dz = pe.z - eye.z, l = Math.hypot(dx, dz) || 1;
      if ((dx * fx + dz * fz) / l < FOV_COS) return false;
    }
    if (!w.lineBlocked(eye, pe)) return true;
    this._pChest.copy(player.position); this._pChest.y += 1.0;
    return !w.lineBlocked(eye, this._pChest);
  }

  _eyePos(out) {
    if (this.model && this.root.visible) return this.model.getEyeWorld(out);
    return out.set(this.position.x + Math.sin(this.yaw) * 0.12, this.position.y + 1.72, this.position.z + Math.cos(this.yaw) * 0.12);
  }

  _onNoise(e) {
    if (!this.enabled || this.state === 'disabled' || this.state === 'jumpscare' || !e?.position) return;
    const lv = clamp(e.loudness ?? 0, 0, 1);
    const pos = e.position;
    const agg = [1, 1.4, 2][this.aggression] ?? 1;
    if (this.state === 'waking') { if (lv >= 0.12) this._target.copy(this._floorTarget(pos)); return; }
    if (this.state === 'dormant') {
      if (lv < 0.12) return;
      const d = DOOR_EAR.distanceTo(pos);
      const fall = clamp(1.35 - d / 8, 0.35, 1.3);
      const gain = agg * (this._firstVisitDone ? 1 : 0.7);
      this.suspicion += (lv - 0.1) * 0.9 * fall * gain * rand(0.8, 1.2);
      this._lastNoise.copy(pos);
      if (lv >= 0.95 && this._graceT <= 0) this.suspicion = SUSPICION_MAX;
      return;
    }
    if (this.state === 'chasing') return;
    // in the basement: does she hear it from where she is?
    const d = this.position.distanceTo(pos);
    const heard = lv * (1 / (1 + (d * d) / 10)) * agg;
    if (heard > 0.05 && lv >= 0.08) {
      this._lastNoise.copy(pos);
      if (this.state === 'descending') { this._target.copy(this._floorTarget(pos)); this._setPath(this._target); }
      else this._beginSearch(pos, false);
    }
  }

  _onHide(e) {
    if (e?.hidden) {
      const recently = this._t - this._lastSeenT < 1.3;
      this._sawHide = this.active && this.state !== 'returning' && (recently || this._seeing) && this.state !== 'jumpscare';
    } else {
      this._sawHide = false;
    }
  }

  // ===================================================================================== movement
  _floorTarget(p) {
    const w = this.game.world;
    const t = new THREE.Vector3(p.x, 0, p.z);
    const prevY = p.y > 2.0 ? L.UPPER.floorY : 0;
    t.y = w.groundHeightAt(t.x, t.z, prevY);
    // pull targets that sit inside furniture/walls toward the nearest nav node
    const id = w.nearestNode(t);
    const n = id ? w.nav.nodes[id].pos : null;
    for (let i = 0; i < 25 && n; i++) {
      if (!w.segmentBlocked(t.x, t.z, t.x, t.z, RADIUS, t.y + 0.3, t.y + 1.9)) break;
      t.lerp(n, 0.15);
    }
    return t;
  }

  _setPath(dest) {
    const w = this.game.world;
    this._path = w.path(this.position, dest);
    this._pathI = 0;
    // skip a first node that is behind us when the next one is directly reachable on the same level
    if (this._path.length > 1) {
      const a = this._path[0], b = this._path[1];
      if (Math.abs(b.y - this.position.y) < 0.25 && Math.abs(a.y - this.position.y) < 0.25 &&
          !w.segmentBlocked(this.position.x, this.position.z, b.x, b.z, RADIUS * 0.9, this.position.y + 0.3, this.position.y + 1.9)) this._pathI = 1;
    }
    this._stuck = 0;
    this._wpI = -1;
  }

  /** Follow the current path. Returns true when the last waypoint is reached (or proved unreachable). */
  _followPath(speed, dt, turnRate = 3.2) {
    const path = this._path;
    if (!path.length) return true;
    const w = this.game.world;
    while (this._pathI < path.length) {
      const wp = path[this._pathI];
      const last = this._pathI === path.length - 1;
      const d = Math.hypot(wp.x - this.position.x, wp.z - this.position.z);
      if (d < (last ? 0.3 : 0.32)) this._pathI++;
      else break;
    }
    if (this._pathI >= path.length) return true;
    // shortcut to the next waypoint when the straight line is free and on the same level
    const nx = path[this._pathI + 1];
    if (nx && Math.abs(nx.y - this.position.y) < 0.2 && Math.abs(path[this._pathI].y - this.position.y) < 0.2 && !this._onStairs() &&
        !w.segmentBlocked(this.position.x, this.position.z, nx.x, nx.z, RADIUS * 0.95, this.position.y + 0.3, this.position.y + 1.9)) this._pathI++;
    const wp = path[this._pathI];
    // never-stuck: watch progress toward the current waypoint
    if (this._pathI !== this._wpI) { this._wpI = this._pathI; this._bestD = Infinity; this._noImpT = 0; this._stuck = 0; }
    const d = Math.hypot(wp.x - this.position.x, wp.z - this.position.z);
    if (d < this._bestD - 0.05) { this._bestD = d; this._noImpT = 0; } else if (this._backoffT <= 0) this._noImpT += dt;
    if (this._noImpT > 1.1) {
      this._noImpT = 0; this._bestD = d; this._stuck++;
      this._startBackoff(wp);
      if (this._stuck >= 3) {
        if (this._pathI < path.length - 1) this._pathI++;   // skip an unreachable waypoint
        else { path.length = 0; return true; }             // goal unreachable: treat as reached
      }
    }
    this._moveToward(wp, speed, dt, turnRate);
    return false;
  }

  _moveToward(target, speed, dt, turnRate = 3.2) {
    const w = this.game.world, p = this.position;
    if (this._backoffT > 0) {
      this._backoffT -= dt;
      w.moveCircle(p, this._backoff.x * dt, this._backoff.z * dt, RADIUS, p.y + 0.3, p.y + 1.9);
      p.y = w.groundHeightAt(p.x, p.z, p.y);
      return;
    }
    let dx = target.x - p.x, dz = target.z - p.z;
    const d = Math.hypot(dx, dz);
    if (d < 1e-3) return;
    dx /= d; dz /= d;
    const want = Math.atan2(dx, dz);
    this.yaw = this._turnToward(this.yaw, want, turnRate, dt);
    // slow down when facing away (no moonwalking), accelerate into the turn
    const face = Math.cos(angWrap(want - this.yaw));
    const sp = speed * clamp(0.35 + 0.65 * face, 0.2, 1);
    const step = Math.min(d, sp * dt);
    w.moveCircle(p, dx * step, dz * step, RADIUS, p.y + 0.3, p.y + 1.9);
    p.y = w.groundHeightAt(p.x, p.z, p.y);
  }

  /** Step back (and a little sideways) away from whatever blocks the way to `toward`. */
  _startBackoff(toward) {
    let dx = toward.x - this.position.x, dz = toward.z - this.position.z;
    const l = Math.hypot(dx, dz) || 1;
    dx /= l; dz /= l;
    const side = Math.random() < 0.5 ? 1 : -1;
    this._backoff.set(-dx * 0.6 - dz * side * 0.7, 0, -dz * 0.6 + dx * side * 0.7);
    this._backoffT = 0.4;
  }

  /** Re-route through a random nearby node (teleport-free fallback when a goal can't be reached directly). */
  _detour(goal) {
    const w = this.game.world;
    const alt = w.randomNodeNear(this.position, 2.5, { lowerOnly: this.position.y < 1.0 });
    this._path = w.path(this.position, alt);
    if (goal) this._path.push(...w.path(alt, goal).slice(1));
    this._pathI = 0;
    this._wpI = -1;
  }

  _turnToward(cur, want, rate, dt) {
    const d = angWrap(want - cur);
    const mx = rate * dt;
    return angWrap(cur + clamp(d, -mx, mx));
  }

  _onStairs() {
    const p = this.position;
    return p.x >= L.STAIRS.minX - 0.05 && p.x <= L.STAIRS.maxX + 0.05 && p.z <= L.STAIRS.bottomZ + 0.05 && p.z > L.STAIRS.topZ - 0.05 && p.y > 0.05 && p.y < L.UPPER.floorY - 0.02;
  }

  // ===================================================================================== presentation
  _placeRoot(dt) {
    // smooth the step-wise stair height into a ramp
    const target = this.position.y;
    if (dt <= 0 || Math.abs(target - this._dispY) > 1.2) this._dispY = target;
    else this._dispY = dampTo(this._dispY, target, 9, dt);
    this.root.position.set(this.position.x, this._dispY, this.position.z);
    this.root.rotation.set(0, this.yaw, 0);
  }

  _animate(dt) {
    const m = this.model, ctx = this._ctx, g = this.game;
    const s = this.state;
    const sub = this._sub;
    let mode = 'walk';
    if (s === 'chasing') mode = this._spotHold > 0 ? 'search' : 'chase';
    else if (s === 'searching') mode = sub?.phase === 'pause' ? 'search' : sub?.phase === 'closetReach' ? 'reach' : 'walk';
    else if (s === 'returning' && sub?.phase === 'door') mode = 'reach';
    else if (s === 'descending' && sub?.phase === 'door') mode = 'idle';
    ctx.mode = mode;
    ctx.speed = this._moveSpeed;
    ctx.stairs = this._onStairs() ? (this._velY > 0.05 ? 1 : this._velY < -0.05 ? -1 : 0) : 0;
    ctx.aggression = this.aggression;
    const player = g.player;
    if (player && (s === 'chasing' || (this._t - this._lastSeenT < 1.5))) {
      ctx.look = player.eyePosition ? player.eyePosition(this._lookV) : this._lookV.copy(player.position).setY(player.position.y + 1.6);
    } else ctx.look = null;
    ctx.jumpT = -1;
    ctx.eyeshine = this._eyeshine;
    m.update(dt, ctx);
  }

  _debugUpdate(dt) {
    const h = this._debugHold;
    this._placeRoot(0);
    this.root.visible = true;
    if (this.model) {
      const ctx = this._ctx;
      ctx.mode = h.mode; ctx.speed = h.mode === 'walk' ? 0.9 : h.mode === 'chase' ? 2.9 : 0; ctx.stairs = 0;
      ctx.look = null; ctx.aggression = this.aggression; ctx.eyeshine = this._eyeshine;
      if (h.mode === 'jumpscare') { h.jumpT += dt; ctx.jumpT = h.jumpT; } else ctx.jumpT = -1;
      this.model.update(dt, ctx);
    }
    this._updateFearAndStress(dt, this.game.player);
  }

  _updateFearAndStress(dt, player) {
    const g = this.game, s = this.state;
    let fear = 0, stress = 0;
    if (player && s !== 'dormant' && s !== 'disabled') {
      const d = this.position.distanceTo(player.position);
      const near = clamp(1 - d / 7, 0, 1);
      switch (s) {
        case 'waking': fear = 0.18; stress = 0.2; break;
        case 'descending': fear = 0.32 + 0.4 * near; break;
        case 'searching': fear = 0.25 + 0.5 * near + (this._seeing ? 0.15 : 0); break;
        case 'chasing': fear = 0.75 + 0.25 * clamp(1 - d / 6, 0, 1); break;
        case 'returning': fear = 0.15 + 0.35 * near; break;
        case 'jumpscare': fear = 1; break;
        default: break;
      }
      if (player.hidden && s === 'searching') fear = Math.min(1, fear + 0.1 * near);
      if (s !== 'waking') stress = clamp(1 - d / 5, 0, 1) * (this.root.visible ? 1 : 0.4);
      // eyeshine: her pupils catch the flashlight beam
      const fl = player.flashlight;
      if (fl?.on && this.root.visible && this.model) {
        const cam = g.camera;
        cam.getWorldDirection(this._camDir);
        const hp = this.model.getEyeWorld(this._v3);
        const to = this._v2.subVectors(hp, cam.position);
        const dd = to.length() || 1;
        const cos = to.dot(this._camDir) / dd;
        this._eyeshine = cos > 0.92 ? clamp((cos - 0.92) / 0.06, 0, 1) * clamp(1.2 - dd / 10, 0.2, 1) : 0.08;
      } else this._eyeshine = 0.08;
    }
    this.fear = clamp(fear, 0, 1);
    if (Math.abs(stress - (this._stress ?? -1)) > 0.01 || (stress === 0 && this._stress !== 0)) {
      this._stress = stress;
      g.world?.lighting?.setStress?.(stress);
    }
  }

  _setStrip(v) {
    if (Math.abs(v - this._strip) < 0.02) return;
    this._strip = v;
    this.game.world?.lighting?.doorStrip?.setOccluded?.(v);
  }

  // ===================================================================================== doors
  _openUpstairsDoor() {
    const door = this.game.world?.handles?.['door.upstairs'];
    if (!door || door.isOpen) return;
    this._doorWasLocked = !!door.locked;
    this._doorOpenedByMe = true;
    this._doorBusy = true;
    door.locked = false;
    this.game.audio?.play?.('door_creak_open', { position: DOOR_BEHIND.clone(), volume: 0.6 });
    let p;
    try { p = door.open?.(); } catch (e) { p = null; }
    const done = () => {
      this._doorBusy = false;
      // keep the lock state the player knows about (gameplay may have unlocked it with the key meanwhile)
      if (!this.game.puzzles?.flags?.doorUnlocked) door.locked = this._doorWasLocked;
    };
    if (p?.then) p.then(done, done); else done();
  }

  _closeUpstairsDoor(instant) {
    const door = this.game.world?.handles?.['door.upstairs'];
    if (!door || !this._doorOpenedByMe) return;
    this._doorOpenedByMe = false;
    const f = this.game.puzzles?.flags;
    if (f?.doorOpened || f?.won) return; // the player opened it to escape: leave it
    if (!door.isOpen) return;
    this._doorBusy = !instant;
    let p;
    try { p = door.close?.(); } catch (e) { p = null; }
    const done = () => {
      this._doorBusy = false;
      if (!this.game.puzzles?.flags?.doorUnlocked && this._doorWasLocked !== null) door.locked = this._doorWasLocked;
    };
    if (p?.then) p.then(done, done); else done();
  }

  // ===================================================================================== audio
  _onFootstep(side, pos) {
    if (!this.root.visible || this.state === 'jumpscare' || this.state === 'dormant') return;
    const audio = this.game.audio;
    if (!audio) return;
    const chase = this.state === 'chasing';
    let name = 'entity_step';
    if (this._onStairs() || (this.position.y > 0.1 && this.position.y < L.UPPER.floorY - 0.05)) {
      if (this._t - this._stairSfxT > 0.75) { name = 'entity_step_stairs'; this._stairSfxT = this._t; }
    }
    audio.play?.(name, { position: pos.clone(), volume: chase ? 1 : 0.72, rate: chase ? 1.08 : 0.94 + Math.random() * 0.06 });
  }

  _updateAudio(dt) {
    const audio = this.game.audio;
    if (!audio) return;
    if (this._hum && this.model) this._hum.setPosition?.(this.model.getHeadWorld(this._humPos));
    const s = this.state;
    if (s === 'descending' || s === 'returning' || s === 'chasing' || (s === 'searching' && !this._hum)) {
      this._breathT -= dt;
      if (this._breathT <= 0) {
        this._breathT = s === 'chasing' ? rand(1.6, 3) : rand(3, 6);
        const p = this.model && this.root.visible ? this.model.getHeadWorld(this._v2).clone() : this.position.clone().setY(this.position.y + 1.7);
        audio.play?.('entity_breath', { position: p, volume: s === 'chasing' ? 1 : 0.7 });
      }
    }
  }

  _startHum() {
    if (this._hum) return;
    const audio = this.game.audio;
    const p = this.model ? this.model.getHeadWorld(this._v2).clone() : this.position.clone().setY(this.position.y + 1.7);
    this._hum = audio?.loop?.('lullaby_hum', { position: p, volume: 0.75 }) ?? null;
  }

  _stopHum() {
    if (!this._hum) return;
    try { this._hum.stop?.(1.2); } catch (e) { /* ignore */ }
    this._hum = null;
  }

  _stopSounds() {
    this._stopHum();
    if (this._sub?.walk) { try { this._sub.walk.stop?.(0.3); } catch (e) { /* ignore */ } this._sub.walk = null; }
  }
}
