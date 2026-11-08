import * as THREE from 'three';
import * as L from '../config/layout.js';
import { LOOK_RAD_PER_PX } from '../core/Input.js';

// First-person player: movement, collision, stairs, stamina, footsteps/noise, flashlight, hiding, and the
// "horror POV" camera rig (head bob synced to footsteps, sprint FOV kick + lean, strafe roll, breathing,
// fear tremor, flinches, landing dips, crouch dip, flashlight lag/sway/flicker).
//
// Public API (must be kept):
//   constructor(game); init(); update(dt); updateIdleCamera(dt) (menu fallback; no-op while ui.menuCameraActive)
//   .position (Vector3, feet)  .yaw  .pitch  .eyeHeight  .radius
//   .enabled (movement+look)   .cameraOverride (when true, Player does NOT write the camera transform)
//   .crouched  .sprinting  .moving  .stamina 0..1  .onStairs
//   .hidden (bool)  .hideSpot (HideSpot|null)
//   .flashlight { has, on, battery 0..100, light: THREE.SpotLight }
//   giveFlashlight()  setFlashlightOn(on)  addBattery(amount=60)
//   enterHide(spot)  exitHide()      animated camera move into / out of the hide spot; both return a Promise that
//                                    resolves when the camera animation is done (spot.door = Handle, opened/closed here).
//                                    cameraOverride is never set by hiding (only the entity jumpscare uses it).
//   respawn()                        back to layout.SPAWN, standing, flashlight state kept
//   teleport(x, y, z, yawRad, pitchRad)   y = feet; a y clearly above the floor is used as a fixed eye height (debug cams)
//   getVisibility()                  0..1 how visible the player is to the entity right now
//   eyePosition(target?)             world position of the camera eye
// Extra public members:
//   .velocity (Vector3, horizontal m/s)  .speed (m/s)  .exhausted (bool)  .surface ('carpet'|'wood'|'concrete')
//   .breath 0..1 (heavy breathing intensity)  .stress 0..1 (smoothed fear used by the camera)
//   flinch(strength=1)               quick camera jolt (scripted scares can call it)
//   setCrouch(bool)                  isInAlcove()
// Emits: 'noise' {position, loudness, source:'player'}, 'player:flashlight' {has, on, battery},
//        'player:stamina' {value, exhausted, breath}, 'player:hide' {hidden, spotId}, 'player:bump' {tag}
// Settings read: fov, cameraMotion (0..1, default 1; scales bob/roll/tremor/breathing).

const WALK = 1.9, CROUCH = 0.9, SPRINT = 3.3, EXHAUSTED = 1.15;
const EYE_STAND = 1.62, EYE_CROUCH = 0.95;
const STAMINA_TIME = 4, REGEN_DELAY = 1;
const BATTERY_LIFE = 360; // seconds from 100 to 0 while on
const HIDE_YAW = 50 * Math.PI / 180, HIDE_PITCH = 30 * Math.PI / 180;
const FLASH = { color: 0xfff0dc, intensity: 42, distance: 18, angle: 0.42, penumbra: 0.45, decay: 2 };
const FLASH_POS = { x: 0.15, y: -0.16, z: 0.02 }; // camera-local, slightly right / down
const LOUD = { crouch: 0.03, carpet: 0.10, concrete: 0.10, wood: 0.18, sprint: 0.45, bump: 0.3, click: 0.02 };
const STEP_SFX = { carpet: 'footstep_carpet', wood: 'footstep_wood', concrete: 'footstep_concrete' };
const HALF_PI = Math.PI / 2, TWO_PI = Math.PI * 2;
const ABS_SIN_MEAN = 2 / Math.PI;

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const damp = (k, dt) => 1 - Math.exp(-k * dt);
const smooth01 = (t) => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };
const smoothstep = (a, b, v) => smooth01((v - a) / (b - a));
const wrapAngle = (a) => { a = (a + Math.PI) % TWO_PI; if (a < 0) a += TWO_PI; return a - Math.PI; };
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/** Damped spring (semi-implicit Euler, sub-stepped for stability). */
class Spring {
  constructor(x = 0) { this.x = x; this.v = 0; }
  step(target, omega, zeta, dt) {
    const n = dt > 0.016 ? Math.ceil(dt / 0.016) : 1;
    const h = dt / n;
    for (let i = 0; i < n; i++) {
      const a = -2 * zeta * omega * this.v - omega * omega * (this.x - target);
      this.v += a * h;
      this.x += this.v * h;
    }
    return this.x;
  }
  reset(x = 0) { this.x = x; this.v = 0; }
}

/** Procedural flashlight cookie: hot core, smooth body, warm spill, faint reflector ring, lens smudges. */
function makeCookieTexture(size = 256) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  let seed = 1337;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
  const blobs = [];
  for (let i = 0; i < 10; i++) {
    const a = rnd() * TWO_PI, r = Math.sqrt(rnd()) * 0.6;
    blobs.push([Math.cos(a) * r, Math.sin(a) * r, 0.035 + rnd() * 0.08, 0.05 + rnd() * 0.08]);
  }
  const img = g.createImageData(size, size), d = img.data;
  const h = size / 2;
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      const x = (px + 0.5 - h) / h, y = (py + 0.5 - h) / h;
      const r = Math.sqrt(x * x + y * y);
      let v = 0;
      if (r < 1) {
        const hot = 0.32 * Math.exp(-((r / 0.12) ** 2));
        const body = 0.7 * Math.pow(1 - smoothstep(0.2, 0.62, r), 1.4);
        const spill = 0.17 * (1 - smoothstep(0.48, 0.97, r));
        const ring = 0.05 * Math.exp(-(((r - 0.34) / 0.03) ** 2)) - 0.035 * Math.exp(-(((r - 0.43) / 0.05) ** 2));
        v = hot + body + spill + ring;
        // reflector imperfections in the falloff (no concentric banding)
        const th = Math.atan2(y, x);
        const ir = smoothstep(0.18, 0.5, r);
        v *= 1 + ir * (0.04 * Math.sin(3 * th + 0.7) + 0.025 * Math.sin(7 * th + 2.1) + 0.015 * Math.sin(13 * th + 0.3));
        // lens smudges
        for (let i = 0; i < blobs.length; i++) {
          const b = blobs[i], dx = x - b[0], dy = y - b[1];
          const q = (dx * dx + dy * dy) / (b[2] * b[2]);
          if (q < 4) v *= 1 - b[3] * Math.exp(-q);
        }
        v *= 1 + (rnd() - 0.5) * 0.025;
        v = clamp(v, 0, 1);
      }
      // cool-white core, warmer spill
      const w = smoothstep(0.25, 0.8, r);
      const i4 = (py * size + px) * 4;
      d[i4] = Math.round(255 * v);
      d[i4 + 1] = Math.round(255 * v * (0.985 - 0.08 * w));
      d[i4 + 2] = Math.round(255 * v * (0.96 - 0.2 * w));
      d[i4 + 3] = 255;
    }
  }
  g.putImageData(img, 0, 0);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.NoColorSpace;
  tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.generateMipmaps = true;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.needsUpdate = true;
  return tex;
}

export class Player {
  constructor(game) {
    this.game = game;
    this.position = new THREE.Vector3(L.SPAWN.x, 0, L.SPAWN.z);
    this.velocity = new THREE.Vector3();
    this.yaw = L.SPAWN.yaw; this.pitch = 0; this.eyeHeight = EYE_STAND; this.radius = 0.25;
    this.enabled = true; this.cameraOverride = false; this.hidden = false; this.hideSpot = null;
    this.crouched = false; this.sprinting = false; this.moving = false; this.stamina = 1; this.onStairs = false;
    this.exhausted = false; this.speed = 0; this.surface = 'carpet'; this.breath = 0; this.stress = 0;
    this.flashlight = {
      has: false, on: false, battery: 100,
      light: new THREE.SpotLight(FLASH.color, 0, FLASH.distance, FLASH.angle, FLASH.penumbra, FLASH.decay),
    };

    // internal state (all scalars / preallocated objects: no per-frame allocations)
    this._t = 0;
    this._ground = 0; this._y1 = 0; this._y2 = 0;
    this._eye = new THREE.Vector3(L.SPAWN.x, EYE_STAND, L.SPAWN.z);
    this._eyeSpring = new Spring(EYE_STAND);
    this._dip = new Spring(0);              // vertical dips (stairs landing, bump)
    this._fPitch = new Spring(0); this._fYaw = new Spring(0); this._fRoll = new Spring(0);
    this._fY = new Spring(0); this._fFov = new Spring(0);
    this._staminaDelay = 0; this._sprintTime = 0; this._exhaustT = 0; this._hunch = 0;
    this._staminaEvt = { value: 1, exhausted: false, breath: 0 };
    this._lastStaminaQ = -1; this._lastExh = false; this._lastBreathQ = -1;
    this._phase = 0.5; this._stepIdx = 0; this._bobAmp = 0; this._moveBlend = 0;
    this._breathPh = 0; this._sprintBlend = 0; this._strafeRoll = 0;
    this._bumpCd = 0; this._flinchCd = 0; this._strafeVel = 0;
    this._noiseSrcT = Object.create(null);
    this._freeEyeY = null;
    this._anim = null; this._hideBusy = false; this._eyeOverrideY = null; this._hideGen = 0;
    this._hiddenView = 0; this._hiddenViewSent = -1;
    // camera fx outputs (computed in _updateCameraFx, consumed by _applyCamera / flashlight)
    this._oR = 0; this._oU = 0; this._oF = 0; this._oPitch = 0; this._oYaw = 0; this._oRoll = 0; this._fov = 70;
    this._bobV = 0; this._bobL = 0; this._trem = 0; this._tremHand = 0; this._tremHand2 = 0;
    this._camYaw = this.yaw; this._camPitch = 0; this._prevCamYaw = this.yaw; this._prevCamPitch = 0;
    // flashlight lag / flicker
    this._lagYaw = 0; this._lagPitch = 0; this._lagYawV = 0; this._lagPitchV = 0;
    this._flMul = 0; this._flickOn = false; this._flickT = 2; this._flickJ = 0; this._flickLvl = 1;
    this._dieT = 0; this._swapDark = 0; this._lastBatteryInt = 100;
    this._flColor = new THREE.Color(FLASH.color); this._flColorLow = new THREE.Color(0xffb36b);
    this._bounce = null; this._bouncePos = new THREE.Vector3(); this._bounceInit = false;
    this._v1 = new THREE.Vector3(); this._v2 = new THREE.Vector3(); this._v3 = new THREE.Vector3();
    // menu -> gameplay camera blend
    this._idleShown = false; this._blendT = 1;
    this._blendPos = new THREE.Vector3(); this._blendQuat = new THREE.Quaternion(); this._q = new THREE.Quaternion();
    this._reduced = false;
  }

  // ====================================================================== init

  init() {
    const g = this.game, cam = g.camera;
    try { this._reduced = matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (_) { /* ignore */ }

    // ---- flashlight (always in the scene with constant map/shadow config; "off" = intensity 0, no recompiles)
    const light = this.flashlight.light;
    light.name = 'playerFlashlight';
    light.map = makeCookieTexture(256);
    light.position.set(FLASH_POS.x, FLASH_POS.y, FLASH_POS.z);
    light.target.position.set(0, 0, -3);
    light.shadow.camera.near = 0.08;
    light.shadow.camera.updateProjectionMatrix();
    light.shadow.bias = -0.0004;
    light.shadow.normalBias = 0.025;
    light.shadow.focus = 1;
    cam.add(light);
    cam.add(light.target);
    this._applyQuality();

    const ev = g.events;
    ev.on('quality:changed', () => this._applyQuality());
    ev.on('entity:spotted', () => {
      this.flinch(1);
      g.audio?.play?.('player_gasp', { volume: 0.6 });
    });
    ev.on('noise', (n) => this._onNoise(n));
    ev.on('power', ({ on } = {}) => { if (!on && g.state === 'playing') this.flinch(0.55); });
    ev.on('game:state', ({ state, prev } = {}) => {
      if (state === 'playing' && (prev === 'menu' || prev === 'loading') && this._idleShown) this._startBlend();
    });

    const c = g.params?.cam?.split?.(',').map(Number);
    if (c && c.length >= 3 && c.every((v) => Number.isFinite(v))) {
      this.teleport(c[0], c[1], c[2], ((c[3] || 0) * Math.PI) / 180, ((c[4] || 0) * Math.PI) / 180);
    } else {
      this._ground = this._y1 = this._y2 = this.game.world?.groundHeightAt?.(this.position.x, this.position.z, 0) ?? 0;
      this.position.y = this._ground;
    }
    this._prevCamYaw = this._camYaw = this.yaw;
    this._prevCamPitch = this._camPitch = this.pitch;
    this._emitFlashlight();
    this._emitStamina(true);
  }

  _applyQuality() {
    const r = this.game.renderer;
    const pr = r?.preset || {};
    const light = this.flashlight.light;
    light.castShadow = !!pr.shadowsFlashlight;
    const size = Math.min(1024, Math.max(256, pr.shadowMapSize || 512));
    if (light.shadow.mapSize.x !== size) {
      light.shadow.mapSize.set(size, size);
      if (light.shadow.map) { light.shadow.map.dispose(); light.shadow.map = null; }
    }
    // cheap one-bounce fill from the beam's hit point (not on low: one point light less for phones)
    const want = (r?.quality || 'medium') !== 'low';
    if (want && !this._bounce) {
      this._bounce = new THREE.PointLight(0xf0d0aa, 0, 7, 2);
      this._bounce.name = 'flashlightBounce';
      this._bounce.castShadow = false;
      this._bounce.position.copy(this._eye);
      this.game.scene.add(this._bounce);
      this._bounceInit = false;
    } else if (!want && this._bounce) {
      this.game.scene.remove(this._bounce);
      this._bounce.dispose?.();
      this._bounce = null;
    }
  }

  // ====================================================================== main update

  update(dt) {
    if (!(dt > 0)) { this._applyCamera(0); return; }
    const g = this.game;
    const input = g.input;
    this._t += dt;
    this._bumpCd -= dt; this._flinchCd -= dt;
    const cm = this._cameraMotion();
    this._readStress(dt);

    if (this._anim) this._stepAnim(dt);
    else {
      if (this.enabled && !this.cameraOverride) this._applyLook(input);
      if (this.enabled && !this.hidden && input.pressed('crouch')) this.setCrouch(!this.crouched);
      this._updateMovement(input, dt);
    }
    this._updateGround(dt);
    this._updateStamina(dt);
    this._updateSteps(dt);
    this._updateFlashlight(input, dt);
    this._updateCameraFx(dt, cm);
    this._applyCamera(dt);
    this._updateFlashlightPose(dt, cm);
    this._updateHiddenView(dt);
  }

  _cameraMotion() {
    const v = this.game.settings?.get?.('cameraMotion');
    const cm = typeof v === 'number' ? v : (this._reduced ? 0.5 : 1);
    return clamp(cm, 0, 1);
  }

  _readStress(dt) {
    const g = this.game;
    let s = clamp(Number(g.fear) || 0, 0, 1);
    const st = g.entity?.state;
    if (st === 'chasing') s = Math.max(s, 0.7);
    else if (st === 'searching' || st === 'descending') s = Math.max(s, 0.22);
    else if (st === 'jumpscare') s = 1;
    this.stress += (s - this.stress) * damp(s > this.stress ? 3 : 0.6, dt);
  }

  // ---------------------------------------------------------------- look

  _applyLook(input) {
    const k = LOOK_RAD_PER_PX;
    this.yaw -= input.look.dx * k;
    this.pitch -= input.look.dy * k;
    if (this.hidden && this.hideSpot) {
      const base = this._hideYawOf(this.hideSpot);
      const d = clamp(wrapAngle(this.yaw - base), -HIDE_YAW, HIDE_YAW);
      this.yaw = base + d;
      this.pitch = clamp(this.pitch, -HIDE_PITCH, HIDE_PITCH);
    } else {
      this.pitch = clamp(this.pitch, -1.42, 1.42);
    }
    if (this.yaw > 20 || this.yaw < -20) {
      const w = wrapAngle(this.yaw);
      const shift = w - this.yaw;
      this.yaw = w; this._prevCamYaw += shift; this._camYaw += shift;
    }
  }

  // ---------------------------------------------------------------- movement

  setCrouch(on) {
    on = !!on;
    if (on === this.crouched || this.hidden) return;
    this.crouched = on;
    this.game.audio?.play?.('cloth_move', { volume: 0.32, rate: on ? 0.95 : 1.05 });
    // small extra dip when crouching (the spring overshoots a little on its own)
    if (on) this._dip.v -= 0.12;
  }

  _updateMovement(input, dt) {
    const world = this.game.world;
    const canMove = this.enabled && !this.hidden && !this._anim && !this.cameraOverride;
    let mx = canMove ? input.move.x : 0, my = canMove ? input.move.y : 0;
    let m = Math.hypot(mx, my);
    if (m > 1) { mx /= m; my /= m; m = 1; }

    const wantSprint = canMove && input.held('sprint') && my > 0.35 && m > 0.5;
    if (wantSprint && this.crouched) this.setCrouch(false);
    const canSprint = wantSprint && !this.exhausted && this.stamina > 0 && !this.crouched;
    this.sprinting = canSprint;

    let speed = this.crouched ? CROUCH : canSprint ? SPRINT : WALK;
    if (this.exhausted) speed = Math.min(speed, EXHAUSTED);
    if (this.onStairs) speed *= canSprint ? 0.85 : 0.8;
    speed *= (my < -0.1 ? 0.72 : Math.abs(mx) > Math.abs(my) ? 0.9 : 1) * m;

    let tvx = 0, tvz = 0;
    if (m > 1e-3) {
      const s = Math.sin(this.yaw), c = Math.cos(this.yaw);
      const wx = mx * c - my * s, wz = -mx * s - my * c;
      const n = Math.hypot(wx, wz) || 1;
      tvx = (wx / n) * speed; tvz = (wz / n) * speed;
    }
    const v = this.velocity;
    const accel = tvx * tvx + tvz * tvz > v.x * v.x + v.z * v.z ? (canSprint ? 6.5 : 8.5) : 10;
    const a = damp(accel, dt);
    v.x += (tvx - v.x) * a; v.z += (tvz - v.z) * a;
    if (Math.abs(v.x) < 1e-4 && tvx === 0) v.x = 0;
    if (Math.abs(v.z) < 1e-4 && tvz === 0) v.z = 0;

    const p = this.position, px = p.x, pz = p.z;
    const ddx = v.x * dt, ddz = v.z * dt;
    if ((ddx !== 0 || ddz !== 0) && world?.moveCircle) {
      const yMin = this._ground + 0.3, yMax = this._ground + this.eyeHeight + 0.12;
      const res = world.moveCircle(p, ddx, ddz, this.radius, yMin, yMax);
      const ax = p.x - px, az = p.z - pz;
      if (res && res.hit) {
        const want = Math.hypot(ddx, ddz), got = Math.hypot(ax, az);
        if (this.sprinting && want / dt > 2.3 && got < want * 0.55 && this._bumpCd <= 0) this._bump(res.hitTag);
        // keep only the sliding part of the velocity
        v.x = ax / dt; v.z = az / dt;
        const sp = Math.hypot(v.x, v.z);
        if (sp > SPRINT) { v.x *= SPRINT / sp; v.z *= SPRINT / sp; }
      }
      this.speed = Math.hypot(ax, az) / dt;
    } else {
      if (!world?.moveCircle) { p.x += ddx; p.z += ddz; }
      this.speed = Math.hypot(ddx, ddz) / dt;
    }
    this.moving = this.speed > 0.15;
    if (this.moving && this._freeEyeY !== null) this._freeEyeY = null;

    // strafe velocity (camera-local right component) for roll
    const right = v.x * Math.cos(this.yaw) - v.z * Math.sin(this.yaw);
    this._strafeVel = right;
  }

  _bump(tag) {
    const g = this.game;
    this._bumpCd = 0.8;
    g.events.emit('player:bump', { tag: tag || 'wall' });
    g.audio?.play?.('bump', { volume: 0.85, rate: 0.95 + Math.random() * 0.1 });
    this._emitNoise(LOUD.bump);
    this._dip.v -= 0.25;
    this._fPitch.v += 0.45 * (Math.random() < 0.5 ? -1 : 1) * 0.5;
    this._fRoll.v += (Math.random() - 0.5) * 0.6;
    this.game.input?.vibrate?.(25);
  }

  _updateGround(dt) {
    const world = this.game.world;
    const prev = this._ground;
    if (this._anim || this.hidden) {
      // anim / hide spot drive the ground directly
    } else if (world?.groundHeightAt) {
      this._ground = world.groundHeightAt(this.position.x, this.position.z, prev);
    }
    const drop = prev - this._ground;
    if (!this._anim && !this.hidden) {
      // (stair treads: the dip is applied on each footfall, see _footstep)
      if (drop >= 0.6) {
        this._dip.v -= 0.9;
        this.game.audio?.play?.('land_thump', { volume: 0.7 });
        this._emitNoise(0.3);
      }
    }
    const k = damp(this.onStairs ? 15 : 18, dt);
    this._y1 += (this._ground - this._y1) * k;
    this._y2 += (this._y1 - this._y2) * k;
    if (Math.abs(this._ground - this._y2) < 1e-4) { this._y1 = this._y2 = this._ground; }
    this.position.y = this._y1;

    const x = this.position.x, z = this.position.z;
    const S = L.STAIRS;
    this.onStairs = (x >= S.minX && x <= S.maxX && z <= S.bottomZ && z > L.ROOM.minZ - 0.01 && this._ground > 0.01) ||
      (this._ground > 1.5);
    if (this._ground > 0.01 || this.onStairs) this.surface = 'wood';
    else if (this.isInAlcove()) this.surface = 'concrete';
    else this.surface = 'carpet';
  }

  isInAlcove() {
    const p = this.position, A = L.ALCOVE;
    return p.x >= A.minX && p.x <= A.maxX && p.z < L.ROOM.minZ && this._ground < 1;
  }

  // ---------------------------------------------------------------- stamina / breathing

  _updateStamina(dt) {
    const running = this.sprinting && this.speed > 1.6;
    if (running) {
      this.stamina -= dt / STAMINA_TIME;
      this._staminaDelay = REGEN_DELAY;
      this._sprintTime += dt;
    } else {
      this._staminaDelay -= dt;
      this._sprintTime = Math.max(0, this._sprintTime - dt * 1.5);
      if (this._staminaDelay <= 0) this.stamina += dt * (this.moving ? 0.2 : this.crouched || this.hidden ? 0.32 : 0.28);
    }
    this.stamina = clamp(this.stamina, 0, 1);
    if (this.stamina <= 0 && !this.exhausted) {
      this.exhausted = true; this._exhaustT = 0; this.sprinting = false;
      this.breath = Math.max(this.breath, 0.85);
    }
    if (this.exhausted) {
      this._exhaustT += dt;
      if (this._exhaustT > 3 && this.stamina >= 0.4) this.exhausted = false;
    }
    const target = this.exhausted ? 1 : clamp((this._sprintTime - 1.2) / 2.5, 0, 0.55);
    this.breath += (target - this.breath) * damp(target > this.breath ? 1.6 : 0.3, dt);
    if (this.breath < 0.003) this.breath = 0;
    this._hunch += ((this.exhausted ? 1 : 0) - this._hunch) * damp(this.exhausted ? 2.5 : 0.9, dt);
    this._emitStamina(false);
  }

  _emitStamina(force) {
    const q = Math.round(this.stamina * 200);
    const bq = Math.round(this.breath * 20);
    if (!force && q === this._lastStaminaQ && this.exhausted === this._lastExh && bq === this._lastBreathQ) return;
    this._lastStaminaQ = q; this._lastExh = this.exhausted; this._lastBreathQ = bq;
    const e = this._staminaEvt;
    e.value = q / 200; e.exhausted = this.exhausted; e.breath = bq / 20;
    this.game.events.emit('player:stamina', e);
  }

  // ---------------------------------------------------------------- footsteps (synced with the bob)

  _updateSteps(dt) {
    const hs = (this._anim || this.hidden) ? 0 : this.speed;
    this._moveBlend += ((hs > 0.2 ? 1 : 0) - this._moveBlend) * damp(hs > 0.2 ? 5 : 3, dt);
    if (hs > 0.05) {
      const stepLen = this.onStairs ? (this.sprinting ? 0.78 : 0.52) : clamp(0.42 + 0.2 * hs, 0.5, 1.12);
      this._phase += (hs * dt) / stepLen;
      const idx = Math.floor(this._phase);
      if (idx !== this._stepIdx) {
        this._stepIdx = idx;
        if (hs > 0.3) this._footstep(hs);
      }
    } else if (this._moveBlend < 0.03) {
      // at rest: park the phase at the top of the arc so the next step starts naturally
      this._phase = Math.floor(this._phase) + 0.5;
      this._stepIdx = Math.floor(this._phase);
    }
  }

  _footstep(hs) {
    const g = this.game;
    const surf = this.surface;
    const runFast = this.sprinting && hs > 2.2;
    let vol, loud;
    if (this.crouched) { vol = 0.3; loud = LOUD.crouch * (surf === 'wood' ? 1.5 : 1); }
    else if (runFast) { vol = 1.0; loud = LOUD.sprint; }
    else {
      const k = clamp(hs / WALK, 0.5, 1);
      vol = (this.exhausted ? 0.55 : 0.68) * (0.7 + 0.3 * k);
      loud = LOUD[surf] * k;
    }
    g.audio?.play?.(STEP_SFX[surf], { volume: vol, rate: 0.94 + Math.random() * 0.1 + (runFast ? 0.04 : 0) });
    if (surf === 'wood' && this._ground > 0.01 && this._ground < 2.7 && Math.random() < 0.14) {
      g.audio?.play?.('stair_creak', { volume: 0.35 + Math.random() * 0.3 });
      loud += 0.04;
    }
    this._emitNoise(loud);
    // landing dip: each footfall going down the stairs (and the last one onto the floor) sinks the view a little
    if (this._ground < this._y2 - 0.05) this._dip.v -= (this.sprinting ? 0.3 : 0.2) * (this.crouched ? 0.5 : 1);
  }

  _emitNoise(loudness) {
    this.game.events.emit('noise', {
      position: new THREE.Vector3(this.position.x, this.position.y, this.position.z),
      loudness, source: 'player',
    });
  }

  _onNoise(n) {
    if (!n || typeof n.loudness !== 'number') return;
    const src = String(n.source || '');
    if (src.startsWith('player')) return;
    const now = this._t;
    const last = this._noiseSrcT[src];
    this._noiseSrcT[src] = now;
    if (last !== undefined && now - last < 1.5) return; // continuous source (TV static...): only the first burst startles
    if (n.loudness < 0.5 || this.game.state !== 'playing') return;
    let d = 3;
    if (n.position && typeof n.position.x === 'number') {
      const e = this._eye;
      d = Math.hypot(n.position.x - e.x, (n.position.y || 0) - e.y, n.position.z - e.z);
    }
    const eff = n.loudness * clamp(1.4 - d / 6, 0, 1);
    if (eff >= 0.45) this.flinch(Math.min(1, eff));
  }

  /** Quick camera jolt (~0.15 s) — startle reaction. */
  flinch(strength = 1) {
    if (this._flinchCd > 0 && strength < 1) return;
    this._flinchCd = 0.5;
    const s = clamp(strength, 0, 1.5) * (0.35 + 0.65 * this._cameraMotion());
    const side = Math.random() < 0.5 ? -1 : 1;
    this._fPitch.v += 1.4 * s;
    this._fYaw.v += side * (0.25 + Math.random() * 0.35) * s;
    this._fRoll.v += -side * 0.55 * s;
    this._fY.v -= 0.5 * s;
    this._fFov.v -= 30 * s;
    this._lagPitchV += 1.5 * s; // the torch jerks too
    this.game.input?.vibrate?.(30);
  }

  // ---------------------------------------------------------------- flashlight

  giveFlashlight() {
    const fl = this.flashlight;
    if (fl.has) return;
    fl.has = true;
    this.setFlashlightOn(true);
  }

  setFlashlightOn(on) {
    const fl = this.flashlight, g = this.game;
    on = !!on;
    if (on && !fl.has) return;
    if (on && fl.battery <= 0 && !this._swapBattery()) {
      g.audio?.play?.('flashlight_click', { volume: 0.5 });
      g.ui?.subtitle?.('Plus de pile…', 2);
      fl.on = false;
      this._emitFlashlight();
      return;
    }
    if (on === fl.on) { this._emitFlashlight(); return; }
    fl.on = on;
    this._dieT = 0;
    g.audio?.play?.('flashlight_click', { volume: 0.55 });
    this._emitNoise(LOUD.click);
    this._emitFlashlight();
  }

  addBattery(amount = 60) {
    const fl = this.flashlight;
    fl.battery = clamp(fl.battery + amount, 0, 100);
    this._dieT = 0;
    this._emitFlashlight();
  }

  _swapBattery() {
    // inventory.remove() returns true only if a spare battery was available
    if (this.game.inventory?.remove?.('battery') !== true) return false;
    this._swapDark = 0.7; // a moment of darkness while the battery is swapped
    this.game.audio?.play?.('battery_change', { volume: 0.8 });
    this.game.ui?.subtitle?.('Tu changes la pile.', 2);
    this.addBattery(100); // a fresh battery (clamped to 100); emits player:flashlight
    return true;
  }

  _emitFlashlight() {
    const fl = this.flashlight;
    this._lastBatteryInt = Math.ceil(fl.battery);
    this.game.events.emit('player:flashlight', { has: fl.has, on: fl.on, battery: Math.round(fl.battery * 10) / 10 });
  }

  _updateFlashlight(input, dt) {
    const fl = this.flashlight, g = this.game;
    if (this.enabled && fl.has && input.pressed('flashlight')) this.setFlashlightOn(!fl.on);

    let mul = 0;
    if (fl.on && fl.has) {
      if (this._dieT <= 0) {
        fl.battery = Math.max(0, fl.battery - (dt * 100) / BATTERY_LIFE);
        if (fl.battery <= 0 && !this._swapBattery()) this._dieT = 1.1;
        if (Math.ceil(fl.battery) !== this._lastBatteryInt) this._emitFlashlight();
      }
      const b = fl.battery;
      mul = 0.6 + 0.4 * smoothstep(0, 35, b);
      // low battery: random flicker bursts, more frequent as it drains; rare short stutters at extreme fear
      const low = b < 15;
      this._flickT -= dt;
      if (!this._flickOn) {
        if (low ? this._flickT <= 0 : this.stress > 0.8 && Math.random() < dt * 0.12) {
          this._flickOn = true;
          this._flickT = low ? 0.1 + Math.random() * 0.45 : 0.08 + Math.random() * 0.18;
        }
      } else if (this._flickT <= 0) {
        this._flickOn = false;
        this._flickT = low ? (0.7 + 3.5 * (b / 15)) * (0.5 + Math.random()) : 2;
      }
      if (this._flickOn) {
        this._flickJ -= dt;
        if (this._flickJ <= 0) {
          this._flickJ = 0.02 + Math.random() * 0.06;
          this._flickLvl = Math.random() < 0.45 ? 0.04 + Math.random() * 0.2 : 0.55 + Math.random() * 0.45;
        }
        mul *= this._flickLvl;
      }
      // dying: violent flicker then off
      if (this._dieT > 0) {
        this._dieT -= dt;
        mul *= Math.random() < 0.5 ? 0.03 : 0.25 + Math.random() * 0.35 * this._dieT;
        if (this._dieT <= 0) {
          this._dieT = 0;
          fl.on = false;
          mul = 0;
          g.ui?.subtitle?.('La pile est morte…', 2.5);
          this._emitFlashlight();
        }
      }
      if (this._swapDark > 0) { this._swapDark -= dt; mul = 0; }
    } else {
      this._swapDark = 0;
    }
    // filament response (fast but not instant)
    this._flMul += (mul - this._flMul) * damp(this._flickOn || this._dieT > 0 ? 90 : mul > this._flMul ? 45 : 30, dt);
    if (this._flMul < 0.002) this._flMul = 0;
    const light = fl.light;
    light.intensity = FLASH.intensity * this._flMul;
    // an unlit flashlight must not cost a shadow pass every frame
    const shadowLive = light.intensity > 0.01;
    if (light.shadow.autoUpdate !== shadowLive) { light.shadow.autoUpdate = shadowLive; light.shadow.needsUpdate = true; }
    // weak battery = warmer light
    const warm = fl.on ? 1 - smoothstep(4, 30, fl.battery) : 0;
    light.color.copy(this._flColor).lerp(this._flColorLow, warm * 0.6);
  }

  _updateFlashlightPose(dt, cm) {
    const light = this.flashlight.light;
    // the beam lags behind fast camera turns (spring), then catches up with a slight overshoot
    let dYaw = wrapAngle(this._camYaw - this._prevCamYaw), dPitch = this._camPitch - this._prevCamPitch;
    if (Math.abs(dYaw) > 0.8 || Math.abs(dPitch) > 0.8) { dYaw = 0; dPitch = 0; this._lagYaw = this._lagPitch = 0; }
    this._prevCamYaw = this._camYaw; this._prevCamPitch = this._camPitch;
    this._lagYaw -= dYaw; this._lagPitch -= dPitch;
    const w = 13, z = 0.62;
    const n = dt > 0.016 ? Math.ceil(dt / 0.016) : 1, h = dt / n;
    for (let i = 0; i < n; i++) {
      this._lagYawV += (-2 * z * w * this._lagYawV - w * w * this._lagYaw) * h;
      this._lagPitchV += (-2 * z * w * this._lagPitchV - w * w * this._lagPitch) * h;
      this._lagYaw += this._lagYawV * h; this._lagPitch += this._lagPitchV * h;
    }
    const lim = 0.2;
    if (this._lagYaw > lim) { this._lagYaw = lim; if (this._lagYawV > 0) this._lagYawV = 0; }
    if (this._lagYaw < -lim) { this._lagYaw = -lim; if (this._lagYawV < 0) this._lagYawV = 0; }
    if (this._lagPitch > lim) { this._lagPitch = lim; if (this._lagPitchV > 0) this._lagPitchV = 0; }
    if (this._lagPitch < -lim) { this._lagPitch = -lim; if (this._lagPitchV < 0) this._lagPitchV = 0; }

    // hand sway with the bob + hand tremor with fear (the hand shakes more than the head)
    const ay = this._lagYaw + this._bobL * 0.55 + this._tremHand * 1.6;
    const ap = this._lagPitch + this._bobV * 0.45 + this._tremHand2 * 1.6 - this._hunch * 0.04;
    const cp = Math.cos(ap);
    light.target.position.set(-Math.sin(ay) * cp * 3, Math.sin(ap) * 3, -Math.cos(ay) * cp * 3);
    light.position.set(FLASH_POS.x + this._bobL * 0.35, FLASH_POS.y + this._bobV * 0.4, FLASH_POS.z);
    this._updateBounce(dt);
  }

  _updateBounce(dt) {
    const b = this._bounce;
    if (!b) return;
    const I = this.flashlight.light.intensity;
    if (I <= 0.01) { b.intensity = 0; return; }
    const cam = this.game.camera;
    cam.updateMatrixWorld();
    const o = this._v1.copy(this.flashlight.light.position).applyMatrix4(cam.matrixWorld);
    const dir = this._v2.copy(this.flashlight.light.target.position).applyMatrix4(cam.matrixWorld).sub(o).normalize();
    const t = this._castBeam(o, dir, 9);
    const p = this._v3.copy(dir).multiplyScalar(Math.max(0.05, t - 0.3)).add(o);
    if (!this._bounceInit) { this._bouncePos.copy(p); this._bounceInit = true; }
    else this._bouncePos.lerp(p, damp(14, dt));
    b.position.copy(this._bouncePos);
    // reflected flux of a spot is ~independent of distance; fade it a bit when the beam escapes far away
    b.intensity = I * 0.032 * (t >= 9 ? 0.4 : 1);
  }

  /** Cheap beam cast against collider boxes + floor/ceiling (no mesh raycasts). Returns hit distance. */
  _castBeam(o, d, maxT) {
    let best = maxT;
    const cols = this.game.world?.colliders;
    if (cols) {
      for (let i = 0; i < cols.length; i++) {
        const c = cols[i];
        if (!c.enabled) continue;
        let t0 = 0, t1 = best;
        // slab test x
        if (Math.abs(d.x) < 1e-8) { if (o.x < c.minX || o.x > c.maxX) continue; }
        else {
          let a = (c.minX - o.x) / d.x, bb = (c.maxX - o.x) / d.x;
          if (a > bb) { const tmp = a; a = bb; bb = tmp; }
          if (a > t0) t0 = a; if (bb < t1) t1 = bb; if (t0 > t1) continue;
        }
        if (Math.abs(d.y) < 1e-8) { if (o.y < c.minY || o.y > c.maxY) continue; }
        else {
          let a = (c.minY - o.y) / d.y, bb = (c.maxY - o.y) / d.y;
          if (a > bb) { const tmp = a; a = bb; bb = tmp; }
          if (a > t0) t0 = a; if (bb < t1) t1 = bb; if (t0 > t1) continue;
        }
        if (Math.abs(d.z) < 1e-8) { if (o.z < c.minZ || o.z > c.maxZ) continue; }
        else {
          let a = (c.minZ - o.z) / d.z, bb = (c.maxZ - o.z) / d.z;
          if (a > bb) { const tmp = a; a = bb; bb = tmp; }
          if (a > t0) t0 = a; if (bb < t1) t1 = bb; if (t0 > t1) continue;
        }
        if (t0 > 0.02 && t0 < best) best = t0;
      }
    }
    // floor / stairs / ceiling: coarse march
    const step = 0.2;
    for (let t = step; t < best; t += step) {
      const x = o.x + d.x * t, y = o.y + d.y * t, z = o.z + d.z * t;
      const gy = L.groundHeightAt(x, z, this._ground);
      const ceil = (this._ground > 1.5 || (x < L.STAIRS.sideWallX && z < L.STAIRS.ceilingOpeningMaxZ)) ? L.UPPER.ceilingY : L.ROOM.ceilingY;
      if (y <= gy || y >= ceil) { best = t; break; }
    }
    return best;
  }

  // ---------------------------------------------------------------- camera fx

  _updateCameraFx(dt, cm) {
    const hs = (this._anim || this.hidden) ? 0 : this.speed;
    // sprint blend (FOV kick, lean)
    const sprintT = this.sprinting && hs > 2.0 ? 1 : 0;
    this._sprintBlend += (sprintT - this._sprintBlend) * damp(sprintT ? 3.2 : 2.4, dt);
    const se = smooth01(this._sprintBlend);

    // head bob (vertical cusp at each foot strike + lateral figure-8), amplitude scales with speed
    const speedK = clamp(hs / WALK, 0, 1.75);
    let ampT = 0.03 * speedK * (this.crouched ? 0.5 : 1) * (1 + 0.25 * se) * (this.exhausted ? 1.15 : 1);
    if (this.onStairs) ampT *= 0.8;
    this._bobAmp += (ampT * this._moveBlend - this._bobAmp) * damp(7, dt);
    const amp = Math.min(this._bobAmp, 0.058) * cm;
    const ph = this._phase * Math.PI;
    const sAbs = Math.abs(Math.sin(ph)) - ABS_SIN_MEAN;
    const sLat = Math.sin(ph - 0.35);
    const bobV = amp * sAbs;
    const bobL = amp * 0.7 * sLat;
    this._bobV = bobV; this._bobL = bobL;
    const bobRoll = amp * 0.32 * Math.sin(ph);
    const bobPitch = amp * 0.22 * sAbs;
    const bobYaw = amp * 0.12 * Math.sin(ph - 0.6);

    // breathing (calm / scared / exhausted / hidden)
    const st = this.stress, br = this.breath;
    const rate = this.hidden ? 0.15 + 0.1 * st : 0.22 + 0.3 * st + 0.62 * br;
    this._breathPh = (this._breathPh + dt * TWO_PI * rate) % (TWO_PI * 64);
    const quiet = 1 - 0.5 * this._moveBlend;
    const bAmp = (this.hidden ? 0.0022 : (0.0042 + 0.003 * st) * quiet + 0.014 * br) * cm;
    const breathY = bAmp * Math.sin(this._breathPh);
    const breathP = bAmp * 0.85 * Math.sin(this._breathPh - 0.7);
    const breathR = bAmp * 0.25 * Math.sin(this._breathPh * 0.5 + 1.1);

    // fear tremor: low-amplitude quasi-random hand-held shake (no allocations)
    const t = this._t;
    const tr = cm * Math.pow(st, 1.5);
    const hf1 = Math.sin(t * 9.7) * 0.55 + Math.sin(t * 13.3 + 1.7) * 0.3 + Math.sin(t * 17.9 + 0.4) * 0.15;
    const hf2 = Math.sin(t * 10.9 + 2.3) * 0.5 + Math.sin(t * 14.7 + 0.2) * 0.3 + Math.sin(t * 19.3 + 1.1) * 0.2;
    const hf3 = Math.sin(t * 8.3 + 0.9) * 0.6 + Math.sin(t * 15.1 + 2.9) * 0.4;
    const lf1 = Math.sin(t * 1.9 + 0.3) * 0.6 + Math.sin(t * 3.1 + 2.2) * 0.4;
    const lf2 = Math.sin(t * 1.3 + 1.4) * 0.55 + Math.sin(t * 2.7 + 0.6) * 0.45;
    const tremP = tr * (0.0023 * hf1 + 0.0034 * lf1);
    const tremY = tr * (0.0019 * hf2 + 0.0030 * lf2);
    const tremR = tr * (0.0014 * hf3 + 0.0022 * lf1);
    this._trem = tremP;
    this._tremHand = tr * (0.0022 * hf2 + 0.0015 * lf2);
    this._tremHand2 = tr * (0.0022 * hf1 + 0.0015 * lf1);

    // eye height (crouch / stand) with a little undershoot = crouch dip
    const eyeT = this.hidden && this.hideSpot ? this.eyeHeight : this.crouched ? EYE_CROUCH : EYE_STAND;
    if (!this.hidden && !this._anim) this.eyeHeight = this._eyeSpring.step(eyeT, 11, 0.72, dt);
    else this._eyeSpring.reset(this.eyeHeight);

    // dips (stairs, bumps) and flinch springs
    const dip = this._dip.step(0, 14, 0.55, dt);
    const fP = this._fPitch.step(0, 20, 0.42, dt), fYw = this._fYaw.step(0, 20, 0.42, dt);
    const fR = this._fRoll.step(0, 20, 0.42, dt), fY = this._fY.step(0, 20, 0.42, dt);
    const fF = this._fFov.step(0, 20, 0.5, dt);

    // strafe roll (toward the strafe direction)
    const rollT = -clamp((this._strafeVel || 0) / SPRINT, -1, 1) * 0.026 * cm;
    this._strafeRoll += (rollT - this._strafeRoll) * damp(6, dt);

    // compose (camera-local right/up/forward offsets, rotation offsets)
    const leanK = 0.5 + 0.5 * cm;
    this._oR = bobL;
    this._oU = bobV + breathY + Math.max(-0.12, dip) + fY - 0.014 * se * leanK - 0.04 * this._hunch * cm;
    this._oF = 0.05 * se * leanK;
    this._oPitch = bobPitch + breathP + tremP + fP - 0.024 * se * leanK - 0.05 * this._hunch * cm;
    this._oYaw = bobYaw + tremY + fYw;
    this._oRoll = bobRoll + breathR + tremR + fR + this._strafeRoll;

    // FOV: base from settings, sprint kick, fear squeeze, flinch
    const base = Number(this.game.settings?.get?.('fov')) || 70;
    this._fov = base + 7 * se * (0.5 + 0.5 * cm) - 3 * smoothstep(0.55, 0.95, st) + fF;
  }

  _applyCamera(dt) {
    const p = this.position;
    let ex = p.x, ez = p.z;
    let ey = this._eyeOverrideY !== null ? this._eyeOverrideY : this._y2 + this.eyeHeight;
    if (this._freeEyeY !== null && !this._anim && !this.hidden) ey = this._freeEyeY;
    const yaw = this.yaw, s = Math.sin(yaw), c = Math.cos(yaw);
    // right = (c, 0, -s), forward = (-s, 0, -c)
    ex += c * this._oR - s * this._oF;
    ez += -s * this._oR - c * this._oF;
    ey += this._oU;
    this._eye.set(ex, ey, ez);
    this._camYaw = yaw + this._oYaw;
    this._camPitch = this.pitch + this._oPitch;
    if (this.cameraOverride) return;
    const cam = this.game.camera;
    cam.position.set(ex, ey, ez);
    cam.rotation.set(this._camPitch, this._camYaw, this._oRoll, 'YXZ');
    if (this._blendT < 1 && dt > 0) {
      this._blendT = Math.min(1, this._blendT + dt / 1.2);
      const k = easeInOut(this._blendT);
      cam.position.lerpVectors(this._blendPos, this._v1.set(ex, ey, ez), k);
      this._q.setFromEuler(cam.rotation);
      cam.quaternion.copy(this._blendQuat).slerp(this._q, k);
    }
    if (Math.abs(cam.fov - this._fov) > 0.01) { cam.fov = this._fov; cam.updateProjectionMatrix(); }
  }

  _startBlend() {
    const cam = this.game.camera;
    this._blendPos.copy(cam.position);
    this._blendQuat.copy(cam.quaternion);
    this._blendT = 0;
    this._idleShown = false;
  }

  _updateHiddenView(dt) {
    const target = this.hidden ? 1 : 0;
    this._hiddenView += (target - this._hiddenView) * damp(this.hidden ? 2.5 : 4, dt);
    if (Math.abs(this._hiddenView - target) < 0.002) this._hiddenView = target;
    if (Math.abs(this._hiddenView - this._hiddenViewSent) > 0.002 || (this._hiddenView === target && this._hiddenViewSent !== target)) {
      this._hiddenViewSent = this._hiddenView;
      this.game.renderer?.setHiddenView?.(this._hiddenView);
    }
  }

  // ====================================================================== menu camera

  /** Fallback menu camera: the UI's diegetic TV menu owns the camera while ui.menuCameraActive is true. */
  updateIdleCamera(dt) {
    const g = this.game, cam = g.camera;
    if (!cam) return;
    if (g.ui?.menuCameraActive) { this._idleShown = true; return; }
    const t = (g.realTime || 0) + 12;
    const x = 1.35 + 0.42 * Math.sin(t * 0.047);
    const y = 1.47 + 0.03 * Math.sin(t * 0.17) + 0.004 * Math.sin(t * 1.3);
    const z = 1.52 + 0.12 * Math.sin(t * 0.071 + 1.0);
    const yaw = 0.5 + 0.2 * Math.sin(t * 0.041 + 0.5);
    const pitch = -0.075 + 0.03 * Math.sin(t * 0.059) + 0.003 * Math.sin(t * 1.3 - 0.6);
    cam.position.set(x, y, z);
    cam.rotation.set(pitch, yaw, 0.006 * Math.sin(t * 0.09), 'YXZ');
    const base = Number(g.settings?.get?.('fov')) || 70;
    if (Math.abs(cam.fov - base) > 0.01) { cam.fov = base; cam.updateProjectionMatrix(); }
    this._idleShown = true;
    if (this.flashlight.light.intensity !== 0 && !this.flashlight.on) this.flashlight.light.intensity = 0;
  }

  // ====================================================================== hiding

  _hideYawOf(spot) { return typeof spot?.hideYaw === 'number' ? spot.hideYaw : L.CLOSET.hideYaw; }

  _doorOf(spot) {
    const d = spot?.door;
    if (d && typeof d.open === 'function') return d;
    return this.game.world?.handles?.[`door.${spot?.id}`] || null;
  }

  _animTo(x, eyeY, z, yaw, pitch, dur, onMid) {
    return new Promise((resolve) => {
      const fromEye = this._eyeOverrideY !== null ? this._eyeOverrideY : this._y2 + this.eyeHeight;
      this._anim = {
        fx: this.position.x, fy: fromEye, fz: this.position.z, fyaw: this.yaw, fpitch: this.pitch,
        tx: x, ty: eyeY, tz: z, dyaw: yaw - this.yaw, tpitch: pitch,
        dur: Math.max(0.05, dur), t: 0, onMid, midDone: false, resolve,
      };
      this._eyeOverrideY = fromEye;
    });
  }

  _stepAnim(dt) {
    const a = this._anim;
    a.t += dt;
    const k = Math.min(1, a.t / a.dur), e = easeInOut(k);
    this.position.x = a.fx + (a.tx - a.fx) * e;
    this.position.z = a.fz + (a.tz - a.fz) * e;
    this._eyeOverrideY = a.fy + (a.ty - a.fy) * e;
    this.yaw = a.fyaw + a.dyaw * e;
    this.pitch = a.fpitch + (a.tpitch - a.fpitch) * e;
    this.velocity.set(0, 0, 0);
    this.speed = 0; this.moving = false; this.sprinting = false; this._strafeVel = 0;
    if (!a.midDone && k >= 0.5) { a.midDone = true; a.onMid?.(); }
    if (k >= 1) { this._anim = null; a.resolve(); }
  }

  _cancelAnim() {
    this._hideGen++;
    this._hideBusy = false;
    const a = this._anim;
    this._anim = null;
    if (a) a.resolve();
  }

  async _doorAction(door, open, timeout) {
    if (!door) return;
    try {
      if (open ? door.isOpen : !door.isOpen) return;
      const p = open ? door.open?.() : door.close?.();
      if (p && typeof p.then === 'function') await Promise.race([p, new Promise((r) => setTimeout(r, timeout * 1000))]);
    } catch (e) { console.warn('[player] door', e); }
  }

  async enterHide(spot) {
    if (!spot || this.hidden || this._hideBusy) return;
    const g = this.game;
    this._hideBusy = true;
    this.velocity.set(0, 0, 0);
    this.sprinting = false;
    if (this.crouched) this.crouched = false;
    this._freeEyeY = null;
    const door = this._doorOf(spot);
    const hp = spot.hidePos || L.CLOSET.hidePos;
    const hideYaw = this._hideYawOf(spot);
    const ex = spot.exitPos || L.CLOSET.exitPos;
    const faceYaw = this.yaw + wrapAngle(hideYaw + Math.PI - this.yaw);
    const gen = ++this._hideGen;
    try {
      // 1) step in front of the door and face it while it opens
      const opening = this._doorAction(door, true, 1.2);
      await Promise.all([this._animTo(ex.x, EYE_STAND - 0.06, hp.z, faceYaw, -0.06, 0.42), opening]);
      if (gen !== this._hideGen) return; // cancelled (respawn / teleport)
      g.audio?.play?.('closet_enter', { volume: 0.8 });
      // 2) slip inside, turn around (via the left) and crouch down
      this._ground = 0;
      let turn = wrapAngle(hideYaw - this.yaw);
      if (Math.abs(Math.abs(turn) - Math.PI) < 0.3) turn = Math.abs(turn);
      await this._animTo(hp.x, hp.y, hp.z, this.yaw + turn, 0, 0.8, () => this._setHidden(true, spot));
      if (gen !== this._hideGen) return;
      this._setHidden(true, spot);
      this.yaw = hideYaw + wrapAngle(this.yaw - hideYaw);
      this.eyeHeight = hp.y - this._ground;
      this._y1 = this._y2 = this._ground;
      this.position.y = this._ground;
      // 3) pull the door shut (the returned Promise resolves when the camera is in place, not when the door is shut)
      this._doorAction(door, false, 1.2);
    } finally {
      if (gen === this._hideGen) this._hideBusy = false;
    }
  }

  async exitHide() {
    if (!this.hidden || this._hideBusy) return;
    const g = this.game;
    const spot = this.hideSpot;
    this._hideBusy = true;
    const door = this._doorOf(spot);
    const ex = spot?.exitPos || L.CLOSET.exitPos;
    const hideYaw = this._hideYawOf(spot);
    const gen = ++this._hideGen;
    try {
      const opening = this._doorAction(door, true, 1.0);
      await Promise.race([opening, new Promise((r) => setTimeout(r, 250))]);
      if (gen !== this._hideGen) return;
      g.audio?.play?.('closet_exit', { volume: 0.8 });
      await this._animTo(ex.x, EYE_STAND, ex.z, this.yaw + wrapAngle(hideYaw - this.yaw), 0, 0.7, () => this._setHidden(false, spot));
      if (gen !== this._hideGen) return;
      this._setHidden(false, spot);
      this._eyeOverrideY = null;
      this._ground = g.world?.groundHeightAt?.(ex.x, ex.z, 0) ?? 0;
      this._y1 = this._y2 = this.position.y = this._ground;
      this.eyeHeight = EYE_STAND; this._eyeSpring.reset(EYE_STAND);
      this.crouched = false;
      this._doorAction(door, false, 1.2); // close behind (not awaited: control is back immediately)
    } finally {
      if (gen === this._hideGen) this._hideBusy = false;
    }
  }

  _setHidden(v, spot) {
    if (this.hidden === v) return;
    const g = this.game;
    this.hidden = v;
    this.hideSpot = v ? spot : null;
    if (v) { this.crouched = false; this.sprinting = false; }
    g.ui?.setHidden?.(v);
    g.events.emit('player:hide', { hidden: v, spotId: spot?.id ?? null });
  }

  // ====================================================================== misc API

  respawn() {
    this._cancelAnim();
    const wasHidden = this.hidden;
    const spot = this.hideSpot;
    this.position.set(L.SPAWN.x, 0, L.SPAWN.z);
    this.yaw = L.SPAWN.yaw; this.pitch = 0;
    this._resetMotion();
    this._ground = this.game.world?.groundHeightAt?.(L.SPAWN.x, L.SPAWN.z, 0) ?? 0;
    this._y1 = this._y2 = this.position.y = this._ground;
    this.stamina = 1; this.exhausted = false; this.breath = 0; this._hunch = 0; this._sprintTime = 0;
    if (wasHidden) { this._setHidden(false, spot); }
    this.hidden = false; this.hideSpot = null;
    this._hiddenView = 0; this._hiddenViewSent = -1;
    this.game.renderer?.setHiddenView?.(0);
    this._emitStamina(true);
    this._emitFlashlight();
  }

  teleport(x, y, z, yaw = this.yaw, pitch = 0) {
    this._cancelAnim();
    if (this.hidden) this._setHidden(false, this.hideSpot);
    const gy = this.game.world?.groundHeightAt?.(x, z, Number.isFinite(y) ? y : 0) ?? 0;
    this.position.set(x, gy, z);
    this._ground = this._y1 = this._y2 = gy;
    this._freeEyeY = Number.isFinite(y) && y > gy + 0.3 ? y : null;
    this.yaw = yaw; this.pitch = pitch;
    this._resetMotion();
    this._prevCamYaw = this._camYaw = yaw;
    this._prevCamPitch = this._camPitch = pitch;
  }

  _resetMotion() {
    this.velocity.set(0, 0, 0);
    this.speed = 0; this.moving = false; this.sprinting = false; this.crouched = false;
    this.eyeHeight = EYE_STAND; this._eyeSpring.reset(EYE_STAND);
    this._eyeOverrideY = null;
    this._dip.reset(); this._fPitch.reset(); this._fYaw.reset(); this._fRoll.reset(); this._fY.reset(); this._fFov.reset();
    this._lagYaw = this._lagPitch = this._lagYawV = this._lagPitchV = 0;
    this._bobAmp = 0; this._moveBlend = 0; this._sprintBlend = 0; this._strafeRoll = 0; this._strafeVel = 0;
    this._oR = this._oU = this._oF = this._oPitch = this._oYaw = this._oRoll = 0;
    this._bounceInit = false;
  }

  getVisibility() {
    if (this.hidden) return 0;
    const g = this.game;
    let v;
    if (this.flashlight.on && this.flashlight.has) v = 1.0;
    else if (g.world?.power !== false) v = this.isInAlcove() ? 0.5 : 0.7;
    else v = 0.35;
    if (this.crouched) v *= 0.5;
    return v;
  }

  eyePosition(target = new THREE.Vector3()) { return target.copy(this._eye); }
}
