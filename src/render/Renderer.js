import * as THREE from 'three';
import { GTAOPass } from 'three/addons/postprocessing/GTAOPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { PostFX } from './PostFX.js';

// Renderer + post-processing (ARCHITECTURE.md §6 Renderer).
// Public API (must be kept):
//   new Renderer(game, canvas)
//   .webgl                 THREE.WebGLRenderer
//   .maxAnisotropy         number
//   .quality               'low'|'medium'|'high'|'ultra' (resolved, never 'auto')
//   .preset                { pixelRatio, shadowMapSize, shadowsFlashlight, gtao, bloom, msaa, envSize }
//   .init()
//   .setQuality(q)         applies a preset (q may be 'auto'), emits 'quality:changed' {quality, preset}
//   .resize()
//   .render(dt)
//   .warmup()              optional: compile shaders before first frame
//   .setFear(v)            0..1 — stronger grain/vignette/chromatic aberration/desaturation, subtle pulse
//   .flash(color, amount, duration)   full-screen flash (e.g. red on jumpscare, white on light pop)
//   .shake(amount, duration)          camera-space screen shake (applied in post, not to the camera)
//   .setBlur(v)            0..1 radial/gaussian blur (jumpscare, waking up)
//   .setHiddenView(v)      0..1 closet vignette (dark edges, slats feeling)
//   .fps                   smoothed frames per second
// Additions:
//   .qualitySetting ('auto'|'low'|...), .auto (bool), .exposure (base tone-mapping exposure, before brightness),
//   .setExposure(v), .fx (PostFX instance: look tunables), .gtao / .bloom (three passes, null when disabled),
//   .renderScale (auto emergency scale on low), .direct (true when post-processing is unavailable),
//   .debugView ('ao'|'denoise'|'normal'|'depth' → raw GTAO buffers on screen; URL ?debug&rview=ao).
//   .look (bloom / AO tunables, see LOOK below; bloom values are read every frame)
//   Meshes with userData.noAO (and additive / no-depth-write FX meshes, points, lines, sprites) are excluded from AO.
//   URL (debug/tuning): ?tonemap=agx|aces|neutral, ?exposure=1.2, ?fx=0 (direct rendering, no post), ?dof=0.
//
// Pipeline (no EffectComposer: fewer copies, MSAA only where it matters):
//   high/ultra: scene → sceneRT (HalfFloat linear HDR, MSAA x4) → GTAO (copy + multiply AO) → rtA
//               → UnrealBloom (additive, in place on rtA) → OutputPass (AgX + sRGB) → rtB → PostFX (+ DOF) → screen
//               DOF reuses the GTAO G-buffer depth (no extra scene pass); a 1x1 autofocus pass eases the focus
//               distance toward the screen-centre depth. DOF fades out while a UI page / note / keypad is open
//               and outside the 'playing' state (menu).
//   medium:     scene → sceneRT → UnrealBloom (in place) → OutputPass → rtA → PostFX → screen
//   low:        scene → sceneRT → PostFX (does the same AgX + sRGB itself) → screen  (no extra full-screen pass;
//               Lighting draws small sprite halos around the bulb / TV instead of bloom)
//   PostFX always works in display space after tone mapping (never double gamma).
// Emissive / bloom contract for other modules: bloom starts at ~2.2 (linear, post-exposure luminance) and is full
//   at ~5.2. Lamps that should glow need emissive luminance ≥ 4 (fan bowl ≈ 6, a fluorescent tube 4–6); lit
//   paint/plaster stays below it except right next to a bulb or in a close flashlight hot spot (a lower threshold
//   turns the bright ceiling around the fan into a milky veil). The CRT (~1 linear) gets its halo from Lighting.tvGlow.

const ORDER = ['low', 'medium', 'high', 'ultra'];

// Base presets (pixelRatio = cap, applied as min(devicePixelRatio, cap)). Extra keys are renderer-internal.
const PRESETS = {
  low:    { pixelRatio: 1,    shadowMapSize: 512,  shadowsFlashlight: false, gtao: false, bloom: false, msaa: 0, envSize: 64,
            fxaa: true,  ca: false, edgeSoft: false, grainSmooth: false, blurTaps: 6,  bloomScale: 0,    gtaoSamples: 0,  maxPixels: 1.1e6, anisotropy: 4, dof: false, toe: 0 },
  medium: { pixelRatio: 1.25, shadowMapSize: 1024, shadowsFlashlight: true,  gtao: false, bloom: true,  msaa: 0, envSize: 128,
            fxaa: true,  ca: true,  edgeSoft: false, grainSmooth: false, blurTaps: 8,  bloomScale: 0.5,  gtaoSamples: 0,  maxPixels: 2.2e6, anisotropy: 8, dof: false, toe: 0.04 },
  high:   { pixelRatio: 1.5,  shadowMapSize: 1024, shadowsFlashlight: true,  gtao: true,  bloom: true,  msaa: 4, envSize: 256,
            fxaa: false, ca: true,  edgeSoft: true,  grainSmooth: true,  blurTaps: 10, bloomScale: 0.75, gtaoSamples: 12, maxPixels: 3.7e6, anisotropy: 16, dof: true, toe: 0.06 },
  ultra:  { pixelRatio: 2,    shadowMapSize: 2048, shadowsFlashlight: true,  gtao: true,  bloom: true,  msaa: 4, envSize: 256,
            fxaa: false, ca: true,  edgeSoft: true,  grainSmooth: true,  blurTaps: 12, bloomScale: 1,    gtaoSamples: 16, maxPixels: 8.3e6, anisotropy: 16, dof: true, toe: 0.06 },
};
// toe: PostFX shadow toe. 0 on low: phones (small screens, bright surroundings) keep every dark tone readable.

// Look-development constants (linear HDR, post-exposure units; see the emissive / bloom contract in the header).
//  Bloom: only real highlights glow — bare bulbs / the fan bowl (~6), a fluorescent tube (4+), a flashlight hot spot
//  on a close wall. The soft knee starts at THRESHOLD and reaches full weight at THRESHOLD + KNEE; RADIUS ~0.6 keeps
//  the wide mips in (soft photographic halo instead of a tight white blob) without veiling the whole frame.
const LOOK = {
  bloomStrength: 0.3, bloomRadius: 0.62, bloomThreshold: 2.2, bloomKnee: 3.0,
  // GTAO: contact shadows under / behind furniture like the reference photos (world-space radius, thin thickness → no halos)
  aoIntensity: 0.95, aoRadius: 0.5, aoDistanceExponent: 1.4, aoThickness: 0.6, aoScale: 1.15,
};

const TONEMAPS = { agx: THREE.AgXToneMapping, aces: THREE.ACESFilmicToneMapping, neutral: THREE.NeutralToneMapping };
const DEBUG_VIEWS = { ao: GTAOPass.OUTPUT.AO, denoise: GTAOPass.OUTPUT.Denoise, normal: GTAOPass.OUTPUT.Normal, depth: GTAOPass.OUTPUT.Depth };

/** GTAO pass that (1) never re-renders shadow maps for its G-buffer pass, (2) hides points/lines/sprites and
 *  additive/no-depth-write FX meshes (light shafts, dust, glows) from the AO G-buffer, (3) does not allocate per frame. */
class GameGTAOPass extends GTAOPass {
  constructor(...args) {
    super(...args);
    this._hiddenList = [];
    this._collect = (o) => {
      if (o.isPoints || o.isLine || o.isSprite || (o.isMesh && (o.userData.noAO || isFxMaterial(o.material)))) {
        o.visible = false;
        this._hiddenList.push(o);
      }
    };
  }

  overrideVisibility() {
    this._hiddenList.length = 0;
    this.scene.traverseVisible(this._collect);
  }

  restoreVisibility() {
    const l = this._hiddenList;
    for (let i = 0; i < l.length; i++) l[i].visible = true;
    l.length = 0;
  }

  render(renderer, writeBuffer, readBuffer, deltaTime, maskActive) {
    const sm = renderer.shadowMap;
    const au = sm.autoUpdate, nu = sm.needsUpdate;
    sm.autoUpdate = false; sm.needsUpdate = false;
    try { super.render(renderer, writeBuffer, readBuffer, deltaTime, maskActive); }
    finally { sm.autoUpdate = au; sm.needsUpdate = nu; }
  }
}

function isFxMaterial(m) {
  if (!m) return false;
  if (Array.isArray(m)) m = m[0];
  if (!m) return false;
  return m.blending === THREE.AdditiveBlending || (m.transparent === true && m.depthWrite === false);
}

export class Renderer {
  constructor(game, canvas) {
    this.game = game;
    this.canvas = canvas;
    this.quality = 'medium';
    this.qualitySetting = 'auto';
    this.auto = true;
    this.preset = this._makePreset('medium');
    this.fps = 60;
    this.maxAnisotropy = 4;
    this.exposure = 1.0;
    this.renderScale = 1;
    this.direct = false;
    this.debugView = null; // 'ao' | 'denoise' | 'normal' | 'depth' (high/ultra only; also ?rview=ao with ?debug)
    this.webgl = null;
    this.fx = null;
    this.gtao = null;
    this.bloom = null;
    this.output = null;
    this.sceneRT = null;
    this.rtA = null;
    this.rtB = null;

    this.look = { ...LOOK };   // look tunables (bloom / AO); bloom values are read every frame
    this._dofAllowed = true;

    this._toneMapping = THREE.AgXToneMapping;
    this._lastT = 0;
    this._size = { w: 0, h: 0, pr: 0, W: 0, H: 0 };
    this._auto = { low: 0, high: 0, grace: 3, downgraded: false, upgraded: false, lowScaleT: 0 };
    this._isTouch = false;
    this._sizeDirty = false;
    this._dprQuery = null;
    this._onDprChange = () => { this._watchDpr(); this.resize(true); };
  }

  // ------------------------------------------------------------------ setup

  init() {
    const game = this.game;
    const url = new URLSearchParams(typeof location !== 'undefined' ? location.search : '');

    this.webgl = new THREE.WebGLRenderer({
      canvas: this.canvas,
      antialias: false,            // AA comes from MSAA render targets (high/ultra) or FXAA in the FX pass
      alpha: false,
      stencil: false,
      powerPreference: 'high-performance',
    });
    const g = this.webgl;
    g.debug.checkShaderErrors = !!game.debug;
    g.outputColorSpace = THREE.SRGBColorSpace;
    this._toneMapping = TONEMAPS[url.get('tonemap')] ?? THREE.AgXToneMapping;
    g.toneMapping = this._toneMapping;
    const ex = parseFloat(url.get('exposure'));
    if (ex > 0) this.exposure = ex;
    if (game.debug && url.get('rview')) this.debugView = url.get('rview');
    if (url.get('dof') === '0') this._dofAllowed = false;
    g.toneMappingExposure = this.exposure;
    g.shadowMap.enabled = true;
    g.shadowMap.type = THREE.PCFSoftShadowMap;
    g.setClearColor(0x000000, 1);

    // Post-processing needs float render targets (WebGL2: EXT_color_buffer_float / _half_float). Without them,
    // fall back to direct rendering with in-material tone mapping (no FX), which still looks correct.
    const ext = g.extensions;
    this.direct = url.get('fx') === '0' || !(ext.has('EXT_color_buffer_float') || ext.has('EXT_color_buffer_half_float'));

    this._isTouch = !!(game.input?.isTouch ?? (typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches));

    this.fx = new PostFX();
    this.fx.setBrightness(game.settings?.get?.('brightness') ?? 1);

    // initial quality: URL param > settings
    const q = game.params?.quality || game.settings?.get?.('quality') || 'auto';
    this.setQuality(q);

    game.events?.on?.('settings:changed', ({ key, value }) => {
      if (key === 'quality') this.setQuality(value);
      else if (key === 'brightness') this.fx.setBrightness(value);
    });

    // orientation / viewport changes (Game already forwards window 'resize')
    addEventListener('orientationchange', () => { this.resize(); setTimeout(() => this.resize(), 250); });
    window.visualViewport?.addEventListener?.('resize', () => this.resize());
    this._watchDpr();
    // canvas resized by CSS without a window resize event (no per-frame clientWidth reads → no forced layouts)
    if (typeof ResizeObserver !== 'undefined') {
      this._ro = new ResizeObserver(() => { this._sizeDirty = true; });
      this._ro.observe(this.canvas);
    }
    this.canvas.addEventListener('webglcontextlost', (e) => { e.preventDefault(); console.warn('[renderer] WebGL context lost'); });
    this.canvas.addEventListener('webglcontextrestored', () => { console.warn('[renderer] WebGL context restored'); this.resize(true); });

    this._lastT = performance.now();
  }

  _watchDpr() {
    try {
      this._dprQuery?.removeEventListener?.('change', this._onDprChange);
      this._dprQuery = matchMedia(`(resolution: ${window.devicePixelRatio || 1}dppx)`);
      this._dprQuery.addEventListener?.('change', this._onDprChange);
    } catch (_) { /* old browsers */ }
  }

  _makePreset(name) {
    const base = PRESETS[name] || PRESETS.medium;
    const dpr = (typeof window !== 'undefined' && window.devicePixelRatio) || 1;
    return { ...base, name, pixelRatioCap: base.pixelRatio, pixelRatio: Math.min(dpr, base.pixelRatio) };
  }

  _autoQuality() {
    if (this.direct) return 'low';
    if (this._isTouch) return 'low';
    return 'high';
  }

  /** Apply a preset. q: 'auto' | 'low' | 'medium' | 'high' | 'ultra'. Emits 'quality:changed'. */
  setQuality(q) {
    const want = typeof q === 'string' ? q.toLowerCase() : 'auto';
    this.auto = !PRESETS[want];
    this.qualitySetting = this.auto ? 'auto' : want;
    const a = this._auto;
    a.low = 0; a.high = 0; a.grace = 3; a.downgraded = false; a.upgraded = false; a.lowScaleT = 0;
    this.renderScale = 1;
    this._apply(this.auto ? this._autoQuality() : want);
  }

  _apply(name) {
    if (!this.webgl) { this.quality = name; this.preset = this._makePreset(name); return; }
    const g = this.webgl;
    this.quality = name;
    this.preset = this._makePreset(name);
    const p = this.preset;
    p.msaa = Math.min(p.msaa, g.capabilities.maxSamples || 0);
    if (this.direct) { p.gtao = false; p.bloom = false; p.msaa = 0; } // no post chain available
    this.maxAnisotropy = Math.max(1, Math.min(g.capabilities.getMaxAnisotropy(), p.anisotropy));

    if (!this.direct) this._buildPipeline();
    this._size.pr = -1; // force resize
    this.resize(true);
    this._auto.grace = 3;
    this.game.events?.emit?.('quality:changed', { quality: this.quality, preset: this.preset });
  }

  _buildPipeline() {
    const p = this.preset;
    const tonemapInFx = !p.bloom && !p.gtao; // low: skip the composer chain, FX tone-maps itself

    // scene target (linear HDR). Recreate when MSAA changes.
    if (!this.sceneRT || this.sceneRT.samples !== p.msaa) {
      this.sceneRT?.dispose();
      this.sceneRT = new THREE.WebGLRenderTarget(4, 4, {
        type: THREE.HalfFloatType, samples: p.msaa, depthBuffer: true, stencilBuffer: false,
      });
      this.sceneRT.texture.name = 'Renderer.scene';
      this.sceneRT.texture.generateMipmaps = false;
    }
    const mk = (n) => {
      const rt = new THREE.WebGLRenderTarget(4, 4, { type: THREE.HalfFloatType, depthBuffer: false, stencilBuffer: false });
      rt.texture.name = n; rt.texture.generateMipmaps = false;
      return rt;
    };
    // rtA: OutputPass target (medium+). rtB: extra ping-pong target, only needed when GTAO writes into rtA.
    if (tonemapInFx) { this.rtA?.dispose(); this.rtA = null; } else this.rtA ||= mk('Renderer.a');
    if (!p.gtao) { this.rtB?.dispose(); this.rtB = null; } else this.rtB ||= mk('Renderer.b');

    // GTAO: contact shadows (world-space radius, thin thickness → no halos behind furniture)
    const lk = this.look;
    if (p.gtao) {
      if (!this.gtao) {
        this.gtao = new GameGTAOPass(this.game.scene, this.game.camera, 4, 4);
        this.gtao.updatePdMaterial({ lumaPhi: 10, depthPhi: 2, normalPhi: 3, radius: 5, radiusExponent: 1, rings: 2 });
      }
      this.gtao.blendIntensity = lk.aoIntensity;
      this.gtao.updateGtaoMaterial({ radius: lk.aoRadius, distanceExponent: lk.aoDistanceExponent, thickness: lk.aoThickness, scale: lk.aoScale, distanceFallOff: 1.0, samples: p.gtaoSamples, screenSpaceRadius: false });
      this.gtao.updatePdMaterial({ samples: p.gtaoSamples >= 16 ? 16 : 12 });
    } else if (this.gtao) {
      this.gtao.dispose(); this.gtao = null;
    }

    // Bloom: only real highlights (bulbs, fan bowl, fluorescent tube, TV, flashlight hot spot), wide soft halos
    if (p.bloom) {
      if (!this.bloom) {
        this.bloom = new UnrealBloomPass(new THREE.Vector2(4, 4), lk.bloomStrength, lk.bloomRadius, lk.bloomThreshold);
      }
    } else if (this.bloom) {
      this.bloom.dispose(); this.bloom = null;
    }

    if (!tonemapInFx) this.output ||= new OutputPass();
    else if (this.output) { this.output.dispose(); this.output = null; }

    // depth of field (high/ultra): needs the GTAO G-buffer depth; ?dof=0 disables it (debug / comparisons)
    const dof = !!(p.dof && this.gtao && this._dofAllowed);
    this.fx.configure({
      tonemapInFx, toneMapping: this._toneMapping, fxaa: p.fxaa || p.msaa === 0, ca: p.ca,
      edgeSoft: p.edgeSoft, grainSmooth: p.grainSmooth, blurTaps: p.blurTaps, dof,
    });
    if (!dof) this.fx.setDepth(null);
    this.fx.toe = p.toe ?? 0;
  }

  /** Base exposure (before the brightness setting). */
  setExposure(v) { if (v > 0) this.exposure = v; }

  // ------------------------------------------------------------------ size

  resize(force = false) {
    const g = this.webgl;
    if (!g) return;
    const w = Math.max(1, Math.round(this.canvas.clientWidth || window.innerWidth || 1));
    const h = Math.max(1, Math.round(this.canvas.clientHeight || window.innerHeight || 1));
    const dpr = window.devicePixelRatio || 1;
    const p = this.preset;
    let pr = Math.min(dpr, p.pixelRatioCap) * this.renderScale;
    if (w * h * pr * pr > p.maxPixels) pr = Math.sqrt(p.maxPixels / (w * h));
    pr = Math.max(0.5, pr);
    p.pixelRatio = pr;

    const s = this._size;
    if (!force && s.w === w && s.h === h && s.pr === pr) return;
    s.w = w; s.h = h; s.pr = pr;

    g.setPixelRatio(pr);
    g.setSize(w, h, false);
    const W = Math.floor(w * pr), H = Math.floor(h * pr);
    s.W = W; s.H = H;

    if (!this.direct) {
      this.sceneRT?.setSize(W, H);
      this.rtA?.setSize(W, H);
      this.rtB?.setSize(W, H);
      this.gtao?.setSize(W, H);
      if (this.bloom) {
        const bs = p.bloomScale || 0.5;
        this.bloom.setSize(Math.max(8, Math.round(W * bs)), Math.max(8, Math.round(H * bs)));
      }
    }
    this.fx?.setSize(W, H, pr);

    const cam = this.game.camera;
    if (cam) { cam.aspect = w / h; cam.updateProjectionMatrix(); }
  }

  // ------------------------------------------------------------------ frame

  render(dt) {
    const g = this.webgl;
    if (!g) return;
    const now = performance.now();
    const ms = now - this._lastT;
    this._lastT = now;
    const realDt = ms > 0 && ms < 250 ? ms / 1000 : Math.min(Math.max(dt || 0, 0), 0.1);
    // ignore only huge gaps (tab switch, debugger); slow frames on weak devices MUST count for auto quality.
    // A single hitch contributes at most 0.5 s of "slow time".
    if (ms > 0 && ms < 2500) {
      const inst = 1000 / ms;
      this.fps += (inst - this.fps) * (1 - Math.exp(-ms / 400));
      this._autoTick(Math.min(ms, 500) / 1000);
    }

    if (this._sizeDirty) { this._sizeDirty = false; this.resize(); }

    const scene = this.game.scene, camera = this.game.camera;
    const exposure = this.exposure * (this.fx?.brightness ?? 1);
    g.toneMappingExposure = exposure;

    if (this.direct) {
      g.setRenderTarget(null);
      g.render(scene, camera);
      return;
    }

    // depth of field only while playing with no UI page / note / keypad over the view
    const st = this.game.state;
    this.fx.setDof(st === 'playing' && !this.game.ui?.isModalOpen?.() ? 1 : 0);
    this.fx.update(realDt);

    g.setRenderTarget(this.sceneRT);
    g.render(scene, camera);

    if (this.debugView && this.gtao && DEBUG_VIEWS[this.debugView] !== undefined) {
      // debug: raw GTAO buffers straight to the screen ('ao' | 'denoise' | 'normal' | 'depth')
      const o = this.gtao.output;
      this.gtao.output = DEBUG_VIEWS[this.debugView];
      this.gtao.renderToScreen = true;
      this.gtao.render(g, null, this.sceneRT, realDt, false);
      this.gtao.output = o;
      this.gtao.renderToScreen = false;
      return;
    }

    let read = this.sceneRT;
    let write = this.rtA;
    if (this.gtao) {
      this.gtao.render(g, write, read, realDt, false);
      read = write; write = this.rtB;
      if (this.fx.dofEnabled) this.fx.setDepth(this.gtao.depthTexture, camera.near, camera.far);
    }
    if (this.bloom) {
      // threshold in linear pre-exposure units, so it tracks the brightness setting
      const lk = this.look;
      this.bloom.threshold = lk.bloomThreshold / exposure;
      this.bloom.highPassUniforms.smoothWidth.value = lk.bloomKnee / exposure;
      this.bloom.strength = lk.bloomStrength;
      this.bloom.radius = lk.bloomRadius;
      this.bloom.render(g, write, read, realDt, false); // additive, in place on `read`
    }
    if (this.output) {
      this.output.render(g, write, read, realDt, false);
      read = write;
      this.fx.render(g, read.texture, exposure);
    } else {
      this.fx.render(g, read.texture, exposure);
    }
  }

  // ------------------------------------------------------------------ auto quality

  _autoTick(sec) {
    if (!this.auto || this.direct) return;
    const game = this.game, a = this._auto;
    if (game.state !== 'playing' || game.ui?.isModalOpen?.() || (typeof document !== 'undefined' && document.hidden)) {
      a.low = 0; a.high = 0;
      return;
    }
    if (a.grace > 0) { a.grace -= sec; a.low = 0; a.high = 0; return; }

    if (this.fps < 40) { a.low += sec; a.high = 0; }
    else { a.low = 0; a.high = this.fps >= 57 ? a.high + sec : 0; }

    if (a.low >= 4) {
      a.low = 0;
      a.downgraded = true;
      const i = ORDER.indexOf(this.quality);
      if (i > 0) {
        if (game.debug) console.info(`[renderer] auto quality: ${this.quality} → ${ORDER[i - 1]} (fps ${this.fps.toFixed(1)})`);
        this._apply(ORDER[i - 1]);
      } else if (this.renderScale > 0.71) {
        // already on low: emergency resolution scale (never below 70 %)
        this.renderScale = Math.max(0.7, this.renderScale - 0.1);
        if (game.debug) console.info(`[renderer] auto render scale → ${this.renderScale.toFixed(2)}`);
        this._size.pr = -1;
        this.resize(true);
        a.grace = 3;
      }
    } else if (a.high >= 6 && !a.upgraded && !a.downgraded && this.quality === 'low' && this._isTouch) {
      // touch devices start on low; one single automatic step up if the device is clearly fast enough
      a.upgraded = true;
      a.high = 0;
      if (game.debug) console.info(`[renderer] auto quality: low → medium (fps ${this.fps.toFixed(1)})`);
      this._apply('medium');
    }
  }

  // ------------------------------------------------------------------ warmup

  /** Compile scene + post shaders before the first visible frame (avoids hitches when play starts). */
  warmup() {
    const g = this.webgl;
    if (!g) return;
    const scene = this.game.scene, camera = this.game.camera;
    try {
      // programs depend on the render target (tone mapping / color space) → compile against the real one
      g.setRenderTarget(this.direct ? null : this.sceneRT);
      g.compile(scene, camera);
    } catch (e) { console.warn('[renderer] compile failed', e); }
    g.setRenderTarget(null);
    try {
      const fps = this.fps;
      this.render(0);
      this.fps = fps;
    } catch (e) { console.warn('[renderer] warmup render failed', e); }
    this._lastT = performance.now();
    this._auto.grace = 3;
  }

  // ------------------------------------------------------------------ effects (delegated to PostFX)

  setFear(v) { this.fx?.setFear(v); }
  flash(color = 0xffffff, amount = 0.8, duration = 0.35) { this.fx?.flash(color, amount, duration); }
  shake(amount = 0.5, duration = 0.4) { this.fx?.shake(amount, duration); }
  setBlur(v) { this.fx?.setBlur(v); }
  setHiddenView(v) { this.fx?.setHiddenView(v); }
}
