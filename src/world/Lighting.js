import * as THREE from 'three';
import * as L from '../config/layout.js';

// Lighting (architecture module, see ARCHITECTURE.md §6 Lighting).
// Physically based units (candela, inverse-square decay). Light colours come from a black-body approximation,
// white-balanced like a camera set to ~4300 K, so a 2700 K bulb reads warm without turning orange.
//   ceiling   PointLight in the fan light kit (60 W incandescent, castShadow, cube map size from renderer.preset)
//             + a frosted glass bowl that glows with the filament level
//   moon      cool SpotLight from outside through the barred window (castShadow → bar shadows on the floor),
//             with a faint volumetric shaft + drifting dust motes (more visible when the power is off)
//   doorLight warm PointLight behind the upstairs door: leaks under the 1.5 cm gap (+ emissive strip) while the
//             door is closed, becomes the hallway ceiling light as the door opens
//   tvLight   cool flickering SpotLight in front of the CRT (only while the TV is on)
//   hemi      very low HemisphereLight so pitch darkness stays readable on phones
// bakeEnvironment(): CubeCamera + PMREMGenerator.fromCubemap → two-bounce "power on" environment and a
//   "power off" (moonlight only) one; swapped on setPower, intensity follows the filament level.
//
// Public API (kept from the contract):
//   constructor(game, world); async build(); async bakeEnvironment(); update(dt); reset(kind)
//   .power (bool)
//   setPower(on)                 ceiling light on/off (+ fan light), smooth ramp, flicker on power-up
//   blowout()                    bulb pop + sparks/flash + power off (calls world.setPower(false))
//   flicker(duration=0.6, depth=1)  one-shot flicker burst of the ceiling light
//   setStress(v)                 0..1 continuous flicker probability (entity proximity)
//   setTVLight(on, intensity)    cool flickering light in front of the TV screen
//   doorStrip                    the light leaking under the upstairs door: setOccluded(v 0..1) (feet shadows)
// Extra: .ceiling .moon .doorLight .tvLight .hemi .level (filament 0..1+) .envOn .envOff
//
// Performance rule: the light set is fixed at build (5 lights, 2 shadow casters). Nothing at runtime changes
// light.visible, castShadow or the light count — every state (off, flicker, blowout, TV) is intensity only
// (0 when off), so no shader program is ever recompiled after renderer.warmup().

const R = L.ROOM, UD = L.UPSTAIRS_DOOR, WIN = L.WINDOW;
const FAN_BOTTOM = R.ceilingY - 0.516;           // ceiling_fan model bottom (light kit)
const LIGHT_Y = FAN_BOTTOM - 0.065;              // filament position, inside the glass bowl

// Moonlight direction: ~32° elevation, from the south-south-east, through the window centre.
const WIN_C = new THREE.Vector3((WIN.minX + WIN.maxX) / 2, (WIN.minY + WIN.maxY) / 2, WIN.z);
const MOON_DIR = new THREE.Vector3(-0.2, -0.625, -0.98).normalize();      // direction of travel
const MOON_POS = WIN_C.clone().addScaledVector(MOON_DIR, -14);
const MOON_TARGET = WIN_C.clone().addScaledVector(MOON_DIR, WIN_C.y / -MOON_DIR.y);

// Photometry: physical luminous intensities (cd) × a camera exposure. The renderer is expected to keep
// toneMappingExposure ≈ 1 (AgX/ACES); the dim-room camera exposure lives here (setExposure()).
const EXPOSURE = 0.11;       // ≈ a camera exposed for a ~15 lux room
const CEIL_CD = 85;          // 60 W A19 ≈ 800 lm ≈ 64 cd + the bowl's downward lobe
const BOWL_EMISSIVE = 75;    // frosted bowl luminance (× exposure → hot white with a gentle bloom)
const MOON_CD = 3000;        // ≈ 9 lux on the floor patch (cinematic moonlight, ~30× a real full moon)
const STRIP_CD = 2.4;        // light leaking under the upstairs door
const HALL_CD = 30;          // hallway ceiling fixture when the door is open
const TV_CD = 7;             // small CRT
const STRIP_GLOW = 45;       // emissive gap line under the door
const HEMI_ON = 0.06, HEMI_OFF = 0.17;  // not exposure-scaled: a readability floor in the dark
const ENV_ON = 0.45;         // two-bounce capture; < 1 keeps the falloff moody
const ENV_OFF = 2.2;         // moonlit bounce is very dim; lift a little for readability

const RAMP = [[0, 0], [0.05, 0.9], [0.09, 0.04], [0.26, 0], [0.32, 0.65], [0.37, 0.08], [0.52, 0], [0.6, 1], [0.68, 0.4], [0.75, 1], [1.1, 1]];
const RAMP_END = 1.1;

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const smooth01 = (t) => t * t * (3 - 2 * t);

/** Black body → linear RGB (Tanner Helland fit), divided by the white-balance colour. */
function kelvin(k, target, wb = 3900) {
  const f = (t) => {
    t /= 100; let r, g, b;
    if (t <= 66) { r = 255; g = 99.4708 * Math.log(t) - 161.1196; b = t <= 19 ? 0 : 138.5177 * Math.log(t - 10) - 305.0448; }
    else { r = 329.6987 * Math.pow(t - 60, -0.1332); g = 288.1222 * Math.pow(t - 60, -0.0755); b = 255; }
    const c = (v) => { v = Math.min(255, Math.max(0, v)) / 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
    return [c(r), c(g), c(b)];
  };
  const a = f(k), w = f(wb);
  const r = a[0] / w[0], g = a[1] / w[1], b = a[2] / w[2], m = Math.max(r, g, b);
  return target.setRGB(r / m, g / m, b / m); // linear working space
}

// ------------------------------------------------------------------------------------------------ FX shaders

const BEAM_VS = /* glsl */`
  attribute vec2 aBeam;           // x: across 0..1 (face), y: along 0 (window) .. 1 (floor)
  varying vec2 vBeam; varying vec3 vW; varying vec3 vN;
  void main() {
    vBeam = aBeam;
    vec4 w = modelMatrix * vec4(position, 1.0);
    vW = w.xyz; vN = normalize(mat3(modelMatrix) * normal);
    gl_Position = projectionMatrix * viewMatrix * w;
  }`;
const BEAM_FS = /* glsl */`
  uniform float uIntensity; uniform float uTime; uniform vec3 uColor;
  varying vec2 vBeam; varying vec3 vW; varying vec3 vN;
  void main() {
    vec3 V = normalize(cameraPosition - vW);
    float facing = abs(dot(V, normalize(vN)));
    float edge = sin(3.14159 * clamp(vBeam.x, 0.0, 1.0));
    float along = smoothstep(0.0, 0.08, vBeam.y) * pow(1.0 - vBeam.y, 0.7);
    float dust = 0.75 + 0.25 * sin(vW.x * 23.0 + uTime * 0.6) * sin(vW.y * 17.0 - uTime * 0.45) * sin(vW.z * 19.0 + uTime * 0.3);
    float a = uIntensity * edge * along * pow(facing, 1.3) * dust;
    gl_FragColor = vec4(uColor * a, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;
const DUST_VS = /* glsl */`
  attribute float aSeed;
  uniform float uTime; uniform float uScale;
  varying float vA;
  void main() {
    vec3 p = position;
    float s = aSeed * 6.2831;
    p += vec3(sin(uTime * 0.21 + s) * 0.05, sin(uTime * 0.13 + s * 1.7) * 0.06 - mod(uTime * 0.004 + aSeed, 0.08), cos(uTime * 0.17 + s * 2.3) * 0.05);
    vec4 mv = modelViewMatrix * vec4(p, 1.0);
    gl_Position = projectionMatrix * mv;
    gl_PointSize = clamp(uScale * (0.5 + aSeed) / -mv.z, 1.0, 2.6);
    vA = 0.5 + 0.5 * sin(uTime * (0.7 + aSeed) + s * 3.0);
  }`;
const DUST_FS = /* glsl */`
  uniform float uIntensity; uniform vec3 uColor;
  varying float vA;
  void main() {
    vec2 c = gl_PointCoord - 0.5;
    float d = 1.0 - smoothstep(0.15, 0.5, length(c));
    gl_FragColor = vec4(uColor * d * vA * uIntensity, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;
const SPARK_VS = /* glsl */`
  attribute float aLife;
  uniform float uScale;
  varying float vL;
  void main() {
    vL = aLife;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    gl_Position = projectionMatrix * mv;
    gl_PointSize = aLife > 0.0 ? clamp(uScale * (0.5 + aLife) / -mv.z, 1.0, 8.0) : 0.0;
  }`;
const SPARK_FS = /* glsl */`
  varying float vL;
  void main() {
    if (vL <= 0.0) discard;
    vec2 c = gl_PointCoord - 0.5;
    float d = 1.0 - smoothstep(0.0, 0.5, length(c));
    vec3 col = mix(vec3(4.0, 1.2, 0.25), vec3(12.0, 9.0, 5.0), clamp(vL, 0.0, 1.0));
    gl_FragColor = vec4(col * d * vL, 1.0);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

const _v = new THREE.Vector3(), _v2 = new THREE.Vector3();

export class Lighting {
  constructor(game, world) {
    this.game = game;
    this.world = world;
    this.power = true;
    this.level = 1;
    this.envOn = null; this.envOff = null;
    this._ramp = -1;
    this._flickT = 0; this._flickDepth = 1; this._flickTimer = 0; this._flickVal = 1;
    this._stress = 0; this._stressDip = 1; this._stressTimer = 0;
    this._flashT = 0;
    this._tvOn = false; this._tvBase = 1; this._tvLevel = 0; this._tvTarget = 0; this._tvTimer = 0;
    this._occ = 0; this._occTarget = 0; this._occDrawn = -1;
    this._frame = 0; this._shadowDirty = 2;
    this._every = { ceil: 1, moon: 2 };
    this._time = 0;
    this.exposure = EXPOSURE;
    this._envApplied = null; this._envIntensity = -1;
    this._c2700 = kelvin(2700, new THREE.Color());
    this._c1900 = kelvin(1900, new THREE.Color());
    this._cTmp = new THREE.Color();
    this.doorStrip = { setOccluded: (v) => { this._occTarget = clamp01(+v || 0); } };
  }

  async build() {
    const scene = this.game.scene;
    this.group = new THREE.Group(); this.group.name = 'lighting';
    scene.add(this.group);

    // ---- ceiling fan light kit
    const c = this.ceiling = new THREE.PointLight(this._c2700, CEIL_CD * EXPOSURE, 0, 2);
    c.name = 'ceilingLight';
    c.position.set(L.FAN.x, LIGHT_Y, L.FAN.z);
    c.castShadow = true;
    // The near plane clips the whole fan (bowl, housing, blades): a 13 cm frosted bowl gives the blades only a
    // faint, very soft shadow in reality, which PCF would turn into hard CG stars. The ceiling mount darkening is
    // baked in the ceiling vertex colours instead. Nothing else ever comes within 0.78 m of the bulb.
    c.shadow.camera.near = 0.78; c.shadow.camera.far = 14;
    c.shadow.bias = -0.0012; c.shadow.normalBias = 0.025; c.shadow.radius = 3; c.shadow.blurSamples = 8;
    this.group.add(c);
    this.bowlMat = new THREE.MeshStandardMaterial({ color: 0xf2e8d6, roughness: 0.5, metalness: 0, emissive: this._c2700.clone(), emissiveIntensity: BOWL_EMISSIVE });
    this.bowlMat.name = 'fanBowlGlass';
    const bowl = this.bowl = new THREE.Mesh(new THREE.SphereGeometry(0.13, 28, 12, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), this.bowlMat);
    bowl.scale.set(1, 0.82, 1); bowl.position.set(L.FAN.x, FAN_BOTTOM + 0.002, L.FAN.z);
    bowl.castShadow = false; bowl.receiveShadow = false; bowl.name = 'fanBowl';
    this.group.add(bowl);

    // ---- moonlight through the window
    const m = this.moon = new THREE.SpotLight(0xffffff, MOON_CD * EXPOSURE, 0, 0.068, 0.35, 2);
    m.color.setRGB(0.42, 0.56, 1.0);
    m.name = 'moonLight';
    m.position.copy(MOON_POS); m.target.position.copy(MOON_TARGET);
    m.castShadow = true;
    m.shadow.camera.near = 9; m.shadow.camera.far = 32; // the lit ellipse on the floor reaches ~21 m
    m.shadow.bias = -0.0004; m.shadow.normalBias = 0.012; m.shadow.radius = 2; m.shadow.blurSamples = 8;
    this.group.add(m, m.target);

    // ---- warm light behind the upstairs door (strip under the door / hallway light)
    const d = this.doorLight = new THREE.PointLight(this._c2700, STRIP_CD * EXPOSURE, 1.6, 2);
    d.name = 'doorLight';
    this._stripPos = new THREE.Vector3(UD.centerX, UD.bottomY + 0.2, UD.z - 0.24);
    this._hallPos = new THREE.Vector3(UD.centerX, L.UPPER.ceilingY - 0.2, -3.65);
    d.position.copy(this._stripPos);
    this.group.add(d);
    this._buildStrip();

    // ---- TV light (cool, flickering)
    const sp = this.world.tv?.screenPosition || new THREE.Vector3(-0.55, 1.42, -2.38);
    const tv = this.tvLight = new THREE.SpotLight(0xffffff, 0, 7, 1.2, 0.85, 2);
    tv.color.setRGB(0.62, 0.76, 1.0);
    tv.name = 'tvLight';
    tv.position.set(sp.x, sp.y, sp.z + 0.06); tv.target.position.set(sp.x, sp.y - 0.35, sp.z + 3);
    this.group.add(tv, tv.target);

    // ---- ambient readability
    this.hemi = new THREE.HemisphereLight(0x8090b0, 0x40302a, HEMI_OFF);
    this.hemi.name = 'ambientHemi';
    this.group.add(this.hemi);

    this._buildBeam();
    this._buildSparks();

    this._applyQuality(this.game.renderer?.preset, this.game.renderer?.quality);
    this.game.events?.on?.('quality:changed', ({ quality, preset } = {}) => this._applyQuality(preset, quality));
    this._applyLevel(this.power ? 1 : 0);
  }

  // ---------------------------------------------------------------------------------------------- FX builders

  _buildStrip() {
    const n = 24, x0 = UD.hingeX + 0.025, x1 = UD.hingeX + UD.width - 0.025, y0 = UD.bottomY + 0.008, y1 = UD.bottomY + 0.0155;
    const pos = [], col = [], idx = [];
    for (let i = 0; i <= n; i++) {
      const x = x0 + ((x1 - x0) * i) / n;
      pos.push(x, y0, UD.z + 0.0015, x, y1, UD.z + 0.0015);
      col.push(1, 1, 1, 1, 1, 1);
      if (i < n) { const a = i * 2; idx.push(a, a + 2, a + 3, a, a + 3, a + 1); }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
    g.setIndex(idx);
    this.stripMat = new THREE.MeshBasicMaterial({ vertexColors: true, color: this._c2700.clone().multiplyScalar(5) });
    this.stripMat.name = 'doorStripGlow';
    this.strip = new THREE.Mesh(g, this.stripMat);
    this.strip.name = 'doorStrip';
    this._stripN = n; this._stripX0 = x0; this._stripX1 = x1;
    this.group.add(this.strip);
  }

  _buildBeam() {
    // aperture at the room face of the recess, limited by the stool (light must clear the sill edge)
    const s = -MOON_DIR.y / -MOON_DIR.z, glassZ = WIN.z + 0.25, glassTop = WIN.maxY - 0.035, recess = glassZ - WIN.z;
    const yTop = glassTop - recess * s, yBot = WIN.minY + 0.04 * s;
    const sx = MOON_DIR.x / -MOON_DIR.z;
    const xa = Math.max(WIN.minX, WIN.minX + 0.035 + recess * sx), xb = Math.min(WIN.maxX, WIN.maxX - 0.035 + recess * sx);
    const top = [new THREE.Vector3(xa, yBot, WIN.z), new THREE.Vector3(xb, yBot, WIN.z), new THREE.Vector3(xb, yTop, WIN.z), new THREE.Vector3(xa, yTop, WIN.z)];
    const bot = top.map((p) => p.clone().addScaledVector(MOON_DIR, p.y / -MOON_DIR.y));
    this._beamTop = top; this._beamBot = bot;
    const pos = [], beam = [], idx = [];
    for (let f = 0; f < 4; f++) {
      const a = f, b = (f + 1) % 4, base = pos.length / 3;
      for (const [p, u, v] of [[top[a], 0, 0], [top[b], 1, 0], [bot[b], 1, 1], [bot[a], 0, 1]]) { pos.push(p.x, p.y, p.z); beam.push(u, v); }
      idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('aBeam', new THREE.Float32BufferAttribute(beam, 2));
    g.setIndex(idx); g.computeVertexNormals();
    this.beamMat = new THREE.ShaderMaterial({
      vertexShader: BEAM_VS, fragmentShader: BEAM_FS,
      uniforms: { uIntensity: { value: 0 }, uTime: { value: 0 }, uColor: { value: new THREE.Color(0.32, 0.4, 0.62) } },
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
    });
    this.beamMat.name = 'moonShaft';
    this.beam = new THREE.Mesh(g, this.beamMat);
    this.beam.name = 'moonShaft'; this.beam.renderOrder = 5; this.beam.frustumCulled = false;
    this.group.add(this.beam);

    // dust motes floating in the shaft
    const N = 90, dp = new Float32Array(N * 3), seed = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const t = Math.random() * 0.92, u = Math.random(), v = Math.random();
      const a = _v.copy(top[0]).lerp(top[1], u), b = _v2.copy(top[3]).lerp(top[2], u);
      const pt = a.lerp(b, v);
      const a2 = new THREE.Vector3().copy(bot[0]).lerp(bot[1], u), b2 = new THREE.Vector3().copy(bot[3]).lerp(bot[2], u);
      const pb = a2.lerp(b2, v);
      pt.lerp(pb, t);
      dp[i * 3] = pt.x; dp[i * 3 + 1] = pt.y; dp[i * 3 + 2] = pt.z; seed[i] = Math.random();
    }
    const dg = new THREE.BufferGeometry();
    dg.setAttribute('position', new THREE.BufferAttribute(dp, 3));
    dg.setAttribute('aSeed', new THREE.BufferAttribute(seed, 1));
    this.dustMat = new THREE.ShaderMaterial({
      vertexShader: DUST_VS, fragmentShader: DUST_FS,
      uniforms: { uTime: { value: 0 }, uScale: { value: 300 }, uIntensity: { value: 0 }, uColor: { value: new THREE.Color(0.55, 0.62, 0.8) } },
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    this.dustMat.name = 'moonDust';
    this.dust = new THREE.Points(dg, this.dustMat);
    this.dust.name = 'moonDust'; this.dust.frustumCulled = false; this.dust.renderOrder = 6;
    this.group.add(this.dust);
  }

  _buildSparks() {
    const N = 26;
    this._spk = { n: N, pos: new Float32Array(N * 3), vel: new Float32Array(N * 3), life: new Float32Array(N), active: false };
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this._spk.pos, 3));
    g.setAttribute('aLife', new THREE.BufferAttribute(this._spk.life, 1));
    this.sparkMat = new THREE.ShaderMaterial({
      vertexShader: SPARK_VS, fragmentShader: SPARK_FS, uniforms: { uScale: { value: 260 } },
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    this.sparkMat.name = 'sparks';
    this.sparks = new THREE.Points(g, this.sparkMat);
    // always drawn (dead sparks have gl_PointSize 0): renderer.warmup() compiles it, no visibility toggles at runtime
    this.sparks.name = 'sparks'; this.sparks.frustumCulled = false; this.sparks.renderOrder = 7;
    this.group.add(this.sparks);
  }

  _burstSparks() {
    const s = this._spk; if (!s) return;
    for (let i = 0; i < s.n; i++) {
      const a = Math.random() * Math.PI * 2, sp = 0.4 + Math.random() * 1.4;
      s.pos[i * 3] = L.FAN.x + Math.cos(a) * 0.05; s.pos[i * 3 + 1] = FAN_BOTTOM - 0.09; s.pos[i * 3 + 2] = L.FAN.z + Math.sin(a) * 0.05;
      s.vel[i * 3] = Math.cos(a) * sp; s.vel[i * 3 + 1] = -0.2 - Math.random() * 1.2; s.vel[i * 3 + 2] = Math.sin(a) * sp;
      s.life[i] = 0.5 + Math.random() * 0.7;
    }
    s.active = true;
    this.sparks.geometry.attributes.position.needsUpdate = true; this.sparks.geometry.attributes.aLife.needsUpdate = true;
  }

  _updateSparks(dt) {
    const s = this._spk; if (!s || !s.active) return;
    let alive = 0;
    for (let i = 0; i < s.n; i++) {
      if (s.life[i] <= 0) continue;
      s.life[i] -= dt * 1.1;
      const k = i * 3;
      s.vel[k + 1] -= 9.8 * dt;
      s.pos[k] += s.vel[k] * dt; s.pos[k + 1] += s.vel[k + 1] * dt; s.pos[k + 2] += s.vel[k + 2] * dt;
      if (s.pos[k + 1] < 0.01) { s.pos[k + 1] = 0.01; s.vel[k + 1] *= -0.25; s.vel[k] *= 0.5; s.vel[k + 2] *= 0.5; s.life[i] -= 0.15; }
      if (s.life[i] > 0) alive++;
    }
    this.sparks.geometry.attributes.position.needsUpdate = true; this.sparks.geometry.attributes.aLife.needsUpdate = true;
    if (!alive) s.active = false;
  }

  // ---------------------------------------------------------------------------------------------- quality

  _applyQuality(preset, quality) {
    if (!this.ceiling) return;
    const p = preset || {};
    const q = quality || 'medium';
    const sz = Math.min(1024, Math.max(256, p.shadowMapSize || 1024));
    const setSize = (light, s) => {
      if (light.shadow.mapSize.x === s) return;
      light.shadow.mapSize.set(s, s);
      if (light.shadow.map) { light.shadow.map.dispose(); light.shadow.map = null; }
    };
    setSize(this.ceiling, sz);
    setSize(this.moon, Math.max(512, sz));
    this._every = q === 'low' ? { ceil: 3, moon: 6 } : q === 'medium' ? { ceil: 2, moon: 3 } : q === 'ultra' ? { ceil: 1, moon: 1 } : { ceil: 1, moon: 2 };
    if (this.dust) this.dust.visible = q !== 'low';
    this.ceiling.shadow.autoUpdate = false; this.moon.shadow.autoUpdate = false;
    this._shadowDirty = 2;
  }

  // ---------------------------------------------------------------------------------------------- environment

  async _waitTextures(timeoutMs = 8000) {
    const pending = () => {
      let n = 0;
      this.game.scene.traverse((o) => {
        if (!o.material) return;
        for (const m of Array.isArray(o.material) ? o.material : [o.material]) {
          for (const k of ['map', 'normalMap', 'roughnessMap', 'aoMap', 'emissiveMap', 'alphaMap', 'metalnessMap']) {
            const t = m[k];
            if (t && t.isTexture && !t.isRenderTargetTexture && (t.image == null || (t.image.complete === false))) n++;
          }
        }
      });
      return n;
    };
    const t0 = performance.now();
    while (pending() > 0 && performance.now() - t0 < timeoutMs) await new Promise((r) => setTimeout(r, 60));
  }

  async bakeEnvironment() {
    const r = this.game.renderer?.webgl, scene = this.game.scene;
    if (!r || !this.ceiling) return;
    await this._waitTextures();
    const size = Math.min(256, Math.max(32, THREE.MathUtils.ceilPowerOfTwo(this.game.renderer?.preset?.envSize || 128)));
    const rt = new THREE.WebGLCubeRenderTarget(size, { type: THREE.HalfFloatType, generateMipmaps: false });
    const cam = new THREE.CubeCamera(0.05, 40, rt);
    cam.position.set(0.3, 1.35, 0.05);
    cam.updateMatrixWorld(true);
    const pmrem = new THREE.PMREMGenerator(r);
    const hide = [this.beam, this.dust, this.sparks].filter(Boolean);
    const vis = hide.map((o) => o.visible);
    hide.forEach((o) => { o.visible = false; });
    const zones = this._zoneMats();
    const setZones = (tex, k) => { for (const z of zones) { z.mat.envMap = tex; z.mat.envMapIntensity = z.zone * k; } };
    const tvWas = this.tvLight.intensity;
    this.tvLight.intensity = 0;
    const capture = () => {
      this.ceiling.shadow.needsUpdate = true; this.moon.shadow.needsUpdate = true;
      scene.updateMatrixWorld(true);
      cam.update(r, scene);
      return pmrem.fromCubemap(rt.texture);
    };
    try {
      // power ON: one bounce, then a second bounce lit by the first
      this._applyLevel(1, 0.6);
      scene.environment = null; setZones(null, 1);
      const on1 = capture();
      scene.environment = on1.texture; scene.environmentIntensity = ENV_ON; setZones(on1.texture, ENV_ON);
      const on2 = capture();
      on1.dispose();
      this.envOn = on2.texture; this._envOnRT = on2;
      // power OFF: moonlight + door strip only
      this._applyLevel(0);
      scene.environment = null; setZones(null, 1);
      const off = capture();
      this.envOff = off.texture; this._envOffRT = off;
    } catch (e) {
      console.warn('[lighting] environment bake failed', e);
    } finally {
      pmrem.dispose(); rt.dispose();
      hide.forEach((o, i) => { o.visible = vis[i]; });
      this.tvLight.intensity = tvWas;
    }
    this._envApplied = null; this._envIntensity = -1;
    if (this.game.params?.power === 'off' && this.world.power) this.world.setPower(false);
    if (!this.power) { this.level = 0; this._ramp = -1; }
    this._applyLevel(this.power ? 1 : 0);
    this._applyEnv(this.power ? 1 : 0);
    this._shadowDirty = 2;
  }

  _zoneMats() {
    if (!this._zones) {
      const list = (this.world.architecture?.zoneMaterials || []).slice();
      const seen = new Set(list.map((z) => z.mat));
      this.game.scene.traverse((o) => {
        if (!o.material) return;
        for (const m of Array.isArray(o.material) ? o.material : [o.material]) {
          if (m.userData?.envZone !== undefined && !seen.has(m)) { seen.add(m); list.push({ mat: m, zone: m.userData.envZone }); }
        }
      });
      this._zones = list;
    }
    return this._zones;
  }

  /** Switch the environment (only when the power state changes — avoids per-frame program lookups). */
  _applyEnv(lv) {
    if (!this.envOn) return;
    const scene = this.game.scene;
    const env = this.power ? this.envOn : this.envOff;
    const k = this.power ? ENV_ON * Math.min(1.4, lv) : ENV_OFF;
    if (this._envApplied !== env) {
      scene.environment = env;
      for (const z of this._zoneMats()) z.mat.envMap = env;
      this._envApplied = env;
    }
    if (Math.abs(k - this._envIntensity) > 1e-3) {
      scene.environmentIntensity = k;
      for (const z of this._zoneMats()) z.mat.envMapIntensity = z.zone * k;
      this._envIntensity = k;
    }
  }

  // ---------------------------------------------------------------------------------------------- level application

  /** Push a filament level (0..1+) into the light, the bowl glow and the colour temperature. */
  _applyLevel(lv, bowlScale = 1) {
    if (!this.ceiling) return;
    const l = Math.max(0, lv);
    this.ceiling.intensity = CEIL_CD * this.exposure * l;
    // incandescent dimming: a cooling filament shifts toward 1900 K
    this._cTmp.copy(this._c2700).lerp(this._c1900, clamp01(1 - l) * 0.85);
    this.ceiling.color.copy(this._cTmp);
    this.bowlMat.emissive.copy(this._cTmp);
    this.bowlMat.emissiveIntensity = BOWL_EMISSIVE * this.exposure * Math.pow(l, 1.6) * bowlScale;
  }

  // ---------------------------------------------------------------------------------------------- public API

  setPower(on) {
    on = !!on;
    const was = this.power;
    this.power = on;
    if (!this.ceiling) return;
    if (on && !was) { this._ramp = 0; }
    if (!on) { this._ramp = -1; this._flickT = 0; }
    this._applyEnv(this.level);
  }

  blowout() {
    if (this.ceiling && this.power) {
      this._flashT = 0.075;
      this._burstSparks();
      try { this.game.audio?.play?.('light_pop', { position: this.bowl.position.clone(), volume: 1 }); } catch (e) { /* optional */ }
      this.game.renderer?.flash?.(0xfff0d0, 0.35, 0.22);
    }
    this.world.setPower(false);
  }

  flicker(duration = 0.6, depth = 1) {
    this._flickT = Math.max(this._flickT, duration);
    this._flickDepth = clamp01(depth);
    this._flickTimer = 0;
  }

  setStress(v) { this._stress = clamp01(+v || 0); }

  /** Camera exposure multiplier applied to every light / emissive (default EXPOSURE). Re-bake to update the env. */
  setExposure(k) { if (k > 0 && isFinite(k)) this.exposure = k; }

  setTVLight(on, intensity) {
    this._tvOn = !!on;
    if (typeof intensity === 'number' && isFinite(intensity)) this._tvBase = Math.max(0, intensity);
  }

  // ---------------------------------------------------------------------------------------------- frame update

  update(dt) {
    if (!this.ceiling) return;
    this._time += dt;
    this._frame++;

    // ---- ceiling filament
    let target = this.power ? 1 : 0;
    if (this._ramp >= 0) {
      this._ramp += dt;
      let v = 1;
      for (let i = RAMP.length - 1; i >= 0; i--) if (this._ramp >= RAMP[i][0]) { v = RAMP[i][1]; break; }
      target = v;
      if (this._ramp >= RAMP_END) this._ramp = -1;
    }
    if (this.power && this._flickT > 0) {
      this._flickT -= dt; this._flickTimer -= dt;
      if (this._flickTimer <= 0) {
        this._flickTimer = 0.025 + Math.random() * 0.09;
        this._flickVal = Math.random() < 0.55 ? 1 - this._flickDepth * (0.55 + 0.45 * Math.random()) : 1;
      }
      target *= this._flickT > 0 ? this._flickVal : 1;
    }
    if (this.power && this._stress > 0.02) {
      this._stressTimer -= dt;
      if (this._stressTimer <= 0) {
        const s = this._stress;
        if (Math.random() < 0.12 + 0.6 * s) { this._stressDip = 1 - (0.25 + 0.75 * Math.random()) * s; this._stressTimer = 0.03 + Math.random() * 0.11; }
        else { this._stressDip = 1 - 0.04 * s * Math.random(); this._stressTimer = (0.12 + Math.random() * 0.7) * (1.4 - s); }
      }
      target *= this._stressDip;
    } else this._stressDip = 1;
    const tau = target > this.level ? 0.035 : 0.07;
    this.level += (target - this.level) * (1 - Math.exp(-dt / tau));
    let lv = this.level;
    if (this._flashT > 0) {
      this._flashT -= dt; lv = 5;
      if (this._flashT <= 0) this.level = 0.3; // the filament is gone: fast fade from here
    }
    this._applyLevel(lv);
    this._applyEnv(Math.min(lv, 1.4));
    this.hemi.intensity = HEMI_OFF + (HEMI_ON - HEMI_OFF) * clamp01(lv);
    this._updateSparks(dt);

    // ---- moon shaft (stronger once the room is dark)
    const dark = 1 - clamp01(lv);
    if (this.beamMat) {
      this.beamMat.uniforms.uTime.value = this._time;
      this.beamMat.uniforms.uIntensity.value = 0.02 + 0.075 * dark;
      this.dustMat.uniforms.uTime.value = this._time;
      this.dustMat.uniforms.uIntensity.value = 0.12 + 0.3 * dark;
      const h = this.game.renderer?.webgl?.domElement?.height || 720;
      this.dustMat.uniforms.uScale.value = h * 0.006;
      this.sparkMat.uniforms.uScale.value = h * 0.45;
    }

    // ---- door strip / hallway light
    this._occ += (this._occTarget - this._occ) * (1 - Math.exp(-dt / 0.12));
    const open = this.world.architecture?.upstairsDoorOpen ?? 0;
    const e = smooth01(clamp01(open * 1.6));
    const d = this.doorLight;
    d.position.copy(this._stripPos).lerp(this._hallPos, e);
    d.distance = 1.6 + (6 - 1.6) * e;
    d.intensity = (STRIP_CD * (1 - 0.7 * this._occ) * (1 - e) + HALL_CD * e) * this.exposure;
    const sv = 1 - e;
    this.strip.visible = sv > 0.01;
    this.stripMat.color.copy(this._c2700).multiplyScalar(STRIP_GLOW * this.exposure * sv);
    if (Math.abs(this._occ - this._occDrawn) > 0.01) this._drawFeet();

    // ---- TV
    const tvOn = this._tvOn && this.world.power !== false;
    this._tvTimer -= dt;
    if (this._tvTimer <= 0) {
      this._tvTimer = 0.035 + Math.random() * 0.11;
      this._tvTarget = Math.random() < 0.08 ? 1.25 : 0.55 + Math.random() * 0.45;
    }
    this._tvLevel += ((tvOn ? this._tvTarget : 0) - this._tvLevel) * Math.min(1, dt * 22);
    this.tvLight.intensity = TV_CD * this.exposure * this._tvBase * this._tvLevel;
    this.moon.intensity = MOON_CD * this.exposure;

    // ---- motion-gated shadow map updates (cube shadow = 6 scene passes: never re-render a static room).
    // Shadows are re-rendered only while something that casts them moves (doors, drawers, lids, lever,
    // rocking chair, the entity), at the preset's throttle rate, plus one final update when motion stops.
    let moving = false;
    const doors = this.world.architecture?.doors;
    if (doors) for (let i = 0; i < doors.length; i++) if (doors[i].animating) { moving = true; break; }
    if (!moving) moving = this._dynamicCastersMoved();
    if (moving) this._shadowDirty = Math.max(this._shadowDirty, 1);
    const ev = this._every;
    const tick = (n) => this._shadowDirty > 0 && (n <= 1 || this._frame % n === 0 || !moving);
    if (lv > 0.003 && tick(ev.ceil)) this.ceiling.shadow.needsUpdate = true;
    if (tick(ev.moon)) this.moon.shadow.needsUpdate = true;
    if (this._shadowDirty > 0 && !moving) this._shadowDirty--;
  }

  /** True when any dynamic shadow caster moved since the last frame (cheap matrix comparison, no allocations). */
  _dynamicCastersMoved() {
    if (!this._dyn) {
      this._dyn = [];
      const add = (o) => { if (o && o.isObject3D && !this._dyn.includes(o)) this._dyn.push(o); };
      add(this.game.entity?.root);
      for (const h of Object.values(this.world.handles || {})) add(h?.object);
      add(this.world.props?.objects?.rockingChair);
      add(this.game.scene.getObjectByName('rockingChair'));
      this._dynSnap = new Float32Array(this._dyn.length * 6);
      // spinning fan blades would invalidate the cube shadow every frame: they don't cast shadows
      this.game.scene.getObjectByName('ceiling_fan_blades')?.traverse((o) => { if (o.isMesh) o.castShadow = false; });
    }
    let moved = false;
    const snap = this._dynSnap;
    for (let i = 0; i < this._dyn.length; i++) {
      const o = this._dyn[i];
      if (!o.visible) continue;
      const e = o.matrixWorld.elements, k = i * 6;
      const v0 = e[12], v1 = e[13], v2 = e[14], v3 = e[0], v4 = e[2], v5 = e[5];
      if (Math.abs(snap[k] - v0) + Math.abs(snap[k + 1] - v1) + Math.abs(snap[k + 2] - v2)
        + Math.abs(snap[k + 3] - v3) + Math.abs(snap[k + 4] - v4) + Math.abs(snap[k + 5] - v5) > 1e-4) moved = true;
      snap[k] = v0; snap[k + 1] = v1; snap[k + 2] = v2; snap[k + 3] = v3; snap[k + 4] = v4; snap[k + 5] = v5;
    }
    return moved;
  }

  _drawFeet() {
    this._occDrawn = this._occ;
    const col = this.strip.geometry.attributes.color, n = this._stripN;
    const cx = UD.centerX + Math.sin(this._time * 0.7) * 0.03;
    for (let i = 0; i <= n; i++) {
      const x = this._stripX0 + ((this._stripX1 - this._stripX0) * i) / n;
      const f = Math.exp(-((x - (cx - 0.1)) ** 2) / 0.0018) + Math.exp(-((x - (cx + 0.11)) ** 2) / 0.0018);
      const v = 1 - this._occ * Math.min(1, f * 1.1);
      col.setXYZ(i * 2, v, v, v); col.setXYZ(i * 2 + 1, v, v, v);
    }
    col.needsUpdate = true;
  }

  reset() {
    this._flickT = 0; this._stress = 0; this._stressDip = 1; this._flashT = 0;
    this._occTarget = 0;
    if (this._spk) { this._spk.active = false; this._spk.life.fill(0); if (this.sparks) this.sparks.geometry.attributes.aLife.needsUpdate = true; }
    this._shadowDirty = 2;
  }
}
