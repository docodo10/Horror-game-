import * as THREE from 'three';
import { FullScreenQuad } from 'three/addons/postprocessing/Pass.js';

// Single full-screen "camera" pass, last in the chain (renders to the screen).
//
// Input: the OutputPass result (tone-mapped, sRGB-encoded = DISPLAY space) on medium+, or — on the low preset where
// the composer chain is skipped — the raw linear HDR scene; in that case the shader tone-maps + sRGB-encodes itself
// (define TONEMAP_IN_FX) with exactly the same three.js chunks OutputPass uses. Everything after `toDisplay()` works in
// display space. The shader never includes <colorspace_fragment>/<tonemapping_fragment>, so there is no double gamma.
//
// Effects: slight barrel lens distortion, edge chromatic aberration, FXAA (presets without MSAA), lens edge softness
// (high/ultra), radial/defocus blur (setBlur), warm/greenish lift-gamma-gain grade + saturation + soft S-curve,
// brightness (display gamma; exposure is handled by the Renderer), natural cos^4-like vignette, fear response (grain,
// CA, desaturation, vignette, heartbeat pulse), closet view (dark edges + soft slat shadows), flash, screen shake
// (UV offset + roll, with an auto zoom margin so borders never show), animated luminance-aware film grain + chroma noise.
//
// Public (used by Renderer): configure(opts), setSize(w, h, pixelRatio), update(dt), render(webgl, inputTexture),
// setFear(v), flash(color, amount, duration), shake(amount, duration), setBlur(v), setHiddenView(v), setBrightness(b),
// plus tunables: distortion, chromatic, vignette, grain, saturation, contrast, lift, gamma, gain (THREE.Vector3),
// slatAxis (0 = horizontal louvers stacked vertically (default), 1 = vertical slats).

const VERT = /* glsl */`
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}`;

const FRAG = /* glsl */`
#ifdef TONEMAP_IN_FX
#include <tonemapping_pars_fragment>
#endif

uniform sampler2D tDiffuse;
uniform vec2 uRes;          // input size in px
uniform float uAspect;
uniform float uInvCorner;   // 1 / squared aspect-corrected corner radius
uniform float uFrame;
uniform float uZoom;
uniform float uDistort;
uniform vec3 uShake;        // uv offset xy, roll (rad)
uniform float uCA;
uniform float uVignette;
uniform float uGrain;
uniform float uGrainScale;
uniform float uFear;
uniform float uPulse;
uniform float uBlur;
uniform float uEdgeSoft;
uniform float uHidden;
uniform float uSlatPhase;
uniform float uSlatAxis;
uniform vec4 uFlash;        // rgb + amount
uniform float uFlashMode;   // 1 = screen (bright flash), 0 = mix (dark flash)
uniform vec3 uLift;
uniform vec3 uGammaV;       // per-channel exponent
uniform vec3 uGain;
uniform float uSat;
uniform float uContrast;
uniform float uBrightGamma;

varying vec2 vUv;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 fetch(vec2 uv) { return textureLod(tDiffuse, uv, 0.0).rgb; }

vec3 toDisplay(vec3 c) {
#ifdef TONEMAP_IN_FX
  c = TONEMAP_FN(c);
  return sRGBTransferOETF(vec4(c, 1.0)).rgb;
#else
  return c;
#endif
}

float pLuma(vec3 c) {
#ifdef TONEMAP_IN_FX
  float l = dot(c, LUMA) * toneMappingExposure;
  return sqrt(l / (1.0 + l));
#else
  return dot(c, LUMA);
#endif
}

#ifdef USE_FXAA
vec3 fxaa(vec2 uv, vec2 px) {
  vec3 rgbM  = fetch(uv);
  vec3 rgbNW = fetch(uv + vec2(-1.0, -1.0) * px);
  vec3 rgbNE = fetch(uv + vec2( 1.0, -1.0) * px);
  vec3 rgbSW = fetch(uv + vec2(-1.0,  1.0) * px);
  vec3 rgbSE = fetch(uv + vec2( 1.0,  1.0) * px);
  float lM = pLuma(rgbM), lNW = pLuma(rgbNW), lNE = pLuma(rgbNE), lSW = pLuma(rgbSW), lSE = pLuma(rgbSE);
  float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
  float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));
  if (lMax - lMin < max(0.0312, lMax * 0.125)) return rgbM;
  vec2 dir = vec2(-((lNW + lNE) - (lSW + lSE)), ((lNW + lSW) - (lNE + lSE)));
  float dirReduce = max((lNW + lNE + lSW + lSE) * (0.25 / 8.0), 1.0 / 128.0);
  float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
  dir = clamp(dir * rcpDirMin, vec2(-8.0), vec2(8.0)) * px;
  vec3 rgbA = 0.5 * (fetch(uv + dir * (1.0 / 3.0 - 0.5)) + fetch(uv + dir * (2.0 / 3.0 - 0.5)));
  vec3 rgbB = rgbA * 0.5 + 0.25 * (fetch(uv - dir * 0.5) + fetch(uv + dir * 0.5));
  float lB = pLuma(rgbB);
  return (lB < lMin || lB > lMax) ? rgbA : rgbB;
}
#endif

vec3 tap(vec2 uv, vec2 ca) {
#ifdef USE_CA
  return vec3(fetch(uv + ca).r, fetch(uv).g, fetch(uv - ca).b);
#else
  return fetch(uv);
#endif
}

// PCG3D hash (integer, no precision issues on mobile GPUs).
highp uvec3 pcg3d(highp uvec3 v) {
  v = v * 1664525u + 1013904223u;
  v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
  v ^= v >> 16u;
  v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
  return v;
}
vec3 hash3(vec2 p) {
  return vec3(pcg3d(uvec3(uvec2(p + 8192.0), uint(uFrame)))) * (1.0 / 4294967295.0);
}
vec3 grainNoise(vec2 fc) {
#ifdef GRAIN_SMOOTH
  // value noise on a lattice slightly coarser than a pixel: softer, more "filmic" than per-pixel white noise
  vec2 p = fc / uGrainScale;
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  vec3 a = hash3(i), b = hash3(i + vec2(1.0, 0.0)), c = hash3(i + vec2(0.0, 1.0)), d = hash3(i + vec2(1.0, 1.0));
  vec3 n = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
  return 0.5 + (n - 0.5) * 1.45; // restore the variance lost by interpolation
#else
  return hash3(fc);
#endif
}

void main() {
  // ---- lens geometry: shake roll + zoom margin + barrel distortion + shake offset
  vec2 d = vUv - 0.5;
  d.x *= uAspect;
  float cr = cos(uShake.z), sr = sin(uShake.z);
  d = vec2(cr * d.x - sr * d.y, sr * d.x + cr * d.y);
  d *= uZoom;
  float r2 = dot(d, d) * uInvCorner;       // 0 at center, ~1 at the corners
  d *= 1.0 + uDistort * r2;
  d.x /= uAspect;
  vec2 base = 0.5 + uShake.xy;
  vec2 uv = base + d;
  vec2 px = 1.0 / uRes;

  // chromatic aberration grows with the squared radius (real lenses: lateral CA)
  vec2 ca = d * (uCA * r2);

  // ---- base color
#ifdef USE_FXAA
  vec3 col = fxaa(uv, px);
  #ifdef USE_CA
  float caPx = length(ca * uRes);
  if (caPx > 0.35) {
    float w = clamp(caPx - 0.35, 0.0, 1.0);
    col.r = mix(col.r, fetch(uv + ca).r, w);
    col.b = mix(col.b, fetch(uv - ca).b, w);
  }
  #endif
#else
  vec3 col = tap(uv, ca);
#endif

  // ---- blur: defocus disc + radial zoom (setBlur), lens edge softness (high/ultra)
  float edge = uEdgeSoft * r2 * r2;
  float blurR = uBlur * 0.011 + edge * 0.0022;
  if (blurR * uRes.x > 1.2) { // only where the blur radius exceeds ~1 px
    vec3 acc = col;
    float zoomK = uBlur * 0.06;
    // per-pixel rotation of the spiral turns discrete ghost copies into fine noise (hidden by the grain)
    float jit = hash3(gl_FragCoord.xy + 17.0).x * 6.2831853;
    for (int i = 0; i < BLUR_TAPS; i++) {
      float t = (float(i) + 0.5) / float(BLUR_TAPS);
      float a = float(i) * 2.39996323 + jit;
      vec2 o = vec2(cos(a), sin(a)) * (sqrt(t) * blurR);
      o.x /= uAspect;
      acc += tap(base + d * (1.0 - zoomK * t) + o, ca);
    }
    col = acc / float(BLUR_TAPS + 1);
  }

  col = max(toDisplay(col), 0.0);

  // ---- grade (display space)
  float L = dot(col, LUMA);
  float sat = uSat * (1.0 - 0.45 * uFear) * (1.0 - 0.25 * uHidden);
  col = max(mix(vec3(L), col, sat), 0.0);
  col = pow(col * uGain, uGammaV);
  col = clamp(col, 0.0, 1.0);
  col = mix(col, col * col * (3.0 - 2.0 * col), uContrast);
  col = pow(col, vec3(uBrightGamma));

  // ---- vignette (cos^4-like falloff), fear pulse, closet view
  float vigA = uVignette + 0.22 * uFear + 0.35 * uPulse + 0.8 * uHidden;
  float vq = 1.0 + vigA * r2;
  col *= 1.0 / (vq * vq);
  col.r += uPulse * 0.03 * r2 * (1.0 - col.r);
  if (uHidden > 0.001) {
    // out-of-focus louver shadows (very close to the eye): soft cosine bands, weaker where the eye looks through
    float s = mix(vUv.y, vUv.x * uAspect, uSlatAxis) * 6.5 + uSlatPhase;
    float slat = 0.5 + 0.5 * cos(s * 6.2831853);
    slat = slat * slat * mix(0.45, 1.0, smoothstep(0.0, 0.7, r2));
    col *= 1.0 - uHidden * (0.32 * slat + 0.30 * smoothstep(0.15, 1.0, r2));
  }

  // ---- camera black level (after the lens vignette): warm-greenish lifted shadows, never pure digital black
  col += uLift * (1.0 - col);

  // ---- flash
  vec3 fc = uFlash.rgb;
  col = mix(col, mix(fc, col + fc * (1.0 - col), uFlashMode), uFlash.a);

  // ---- film grain: luminance-aware (strongest in low mids, weaker in highlights), mostly mono + a bit of chroma
  vec3 h = grainNoise(gl_FragCoord.xy);
  float g = h.x + h.y - 1.0;
  L = dot(col, LUMA);
  float gw = mix(1.0, 0.3, smoothstep(0.2, 0.9, L)) * (0.55 + 0.45 * smoothstep(0.0, 0.06, L));
  float amt = uGrain * (1.0 + 1.0 * uFear + 0.6 * uHidden);
  col += amt * gw * (vec3(g) + (h.z - 0.5) * vec3(0.30, -0.12, -0.24));

  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;

const TONEMAP_FN = {
  [THREE.AgXToneMapping]: 'AgXToneMapping',
  [THREE.ACESFilmicToneMapping]: 'ACESFilmicToneMapping',
  [THREE.NeutralToneMapping]: 'NeutralToneMapping',
  [THREE.CineonToneMapping]: 'CineonToneMapping',
  [THREE.ReinhardToneMapping]: 'ReinhardToneMapping',
  [THREE.LinearToneMapping]: 'LinearToneMapping',
};

const smooth01 = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

export class PostFX {
  constructor() {
    // ---- tunables (look). Grade values are display-space.
    this.distortion = 0.045;   // barrel k (at the corners)
    this.chromatic = 0.0035;   // CA strength (uv units at the corners)
    this.vignette = 0.32;
    this.grain = 0.032;
    this.saturation = 0.9;
    this.contrast = 0.1;
    this.lift = new THREE.Vector3(0.014, 0.016, 0.009);   // black level: warm-greenish shadows
    this.gamma = new THREE.Vector3(0.99, 0.975, 1.05);    // exponent: <1 brightens. Blue mids down = warm, green up = sickly
    this.gain = new THREE.Vector3(1.035, 1.0, 0.92);      // warm highlights
    this.slatAxis = 0;

    // ---- state
    this.fear = 0;
    this.time = 0;
    this._frame = 0;
    this._beat = 0;
    this._pulse = 0;
    this._blur = 0; this._blurTarget = 0;
    this._hidden = 0; this._hiddenTarget = 0;
    this._flashColor = new THREE.Color(1, 1, 1);
    this._flashAmt = 0; this._flashT = 0; this._flashDur = 0;
    this._shakeAmt = 0; this._shakeT = 0; this._shakeDur = 0;
    this._shakePh = new Float32Array(6);
    this._brightness = 1;
    this._aspect = 1;
    this._config = '';

    this.uniforms = {
      tDiffuse: { value: null },
      toneMappingExposure: { value: 1 },
      uRes: { value: new THREE.Vector2(1, 1) },
      uAspect: { value: 1 },
      uInvCorner: { value: 2 },
      uFrame: { value: 0 },
      uZoom: { value: 1 },
      uDistort: { value: this.distortion },
      uShake: { value: new THREE.Vector3() },
      uCA: { value: this.chromatic },
      uVignette: { value: this.vignette },
      uGrain: { value: this.grain },
      uGrainScale: { value: 1 },
      uFear: { value: 0 },
      uPulse: { value: 0 },
      uBlur: { value: 0 },
      uEdgeSoft: { value: 0 },
      uHidden: { value: 0 },
      uSlatPhase: { value: 0 },
      uSlatAxis: { value: 0 },
      uFlash: { value: new THREE.Vector4(1, 1, 1, 0) },
      uFlashMode: { value: 1 },
      uLift: { value: new THREE.Vector3() },
      uGammaV: { value: new THREE.Vector3(1, 1, 1) },
      uGain: { value: new THREE.Vector3(1, 1, 1) },
      uSat: { value: 1 },
      uContrast: { value: 0 },
      uBrightGamma: { value: 1 },
    };
    this.material = new THREE.ShaderMaterial({
      name: 'LaGardiennePostFX',
      uniforms: this.uniforms,
      vertexShader: VERT,
      fragmentShader: FRAG,
      depthTest: false,
      depthWrite: false,
      toneMapped: false, // we include the tone mapping chunk ourselves when needed (never applied twice)
    });
    this.quad = new FullScreenQuad(this.material);
    this.configure({});
  }

  /**
   * opts: { tonemapInFx: false, toneMapping: THREE.AgXToneMapping, fxaa: false, ca: true, edgeSoft: false,
   *         grainSmooth: false, blurTaps: 8 }
   */
  configure(opts) {
    const o = { tonemapInFx: false, toneMapping: THREE.AgXToneMapping, fxaa: false, ca: true, edgeSoft: false, grainSmooth: false, blurTaps: 8, ...opts };
    const defines = { BLUR_TAPS: Math.max(2, o.blurTaps | 0) };
    if (o.tonemapInFx) { defines.TONEMAP_IN_FX = ''; defines.TONEMAP_FN = TONEMAP_FN[o.toneMapping] || 'AgXToneMapping'; }
    if (o.fxaa) defines.USE_FXAA = '';
    if (o.ca) defines.USE_CA = '';
    if (o.grainSmooth) defines.GRAIN_SMOOTH = '';
    const key = JSON.stringify(defines);
    this.uniforms.uEdgeSoft.value = o.edgeSoft ? 1 : 0;
    if (key === this._config) return;
    this._config = key;
    this.material.defines = defines;
    this.material.needsUpdate = true;
  }

  setSize(w, h, pixelRatio = 1) {
    this.uniforms.uRes.value.set(Math.max(1, w), Math.max(1, h));
    const aspect = w / Math.max(1, h);
    this._aspect = aspect;
    this.uniforms.uAspect.value = aspect;
    this.uniforms.uInvCorner.value = 1 / (0.25 * aspect * aspect + 0.25);
    // grain cell ≈ 1 CSS px on hi-dpi screens (per-pixel noise becomes invisible at 2-3x)
    this.uniforms.uGrainScale.value = Math.max(1, pixelRatio * 0.8);
  }

  setFear(v) { this.fear = Math.min(1, Math.max(0, +v || 0)); }

  /** Brightness setting (0.6..1.6); the Renderer multiplies the tone-mapping exposure by it. */
  get brightness() { return this._brightness; }

  setBrightness(b) {
    this._brightness = Math.min(2, Math.max(0.3, +b || 1));
    // display gamma: >1 brightness lifts the darks more than the highlights (phones outdoors), <1 crushes slightly
    this.uniforms.uBrightGamma.value = 1 / (1 + (this._brightness - 1) * 0.35);
  }

  flash(color = 0xffffff, amount = 0.8, duration = 0.35) {
    const a = Math.min(1, Math.max(0, +amount || 0));
    const cur = this._flashDur > 0 ? this._flashAmt * Math.pow(1 - Math.min(1, this._flashT / this._flashDur), 2) : 0;
    if (a < cur) return; // a stronger flash is still running
    try { this._flashColor.set(color ?? 0xffffff); } catch (_) { this._flashColor.setRGB(1, 1, 1); }
    this._flashAmt = a; this._flashT = 0; this._flashDur = Math.max(0.02, +duration || 0.35);
    const c = this._flashColor;
    this.uniforms.uFlashMode.value = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.12 ? 1 : 0;
  }

  shake(amount = 0.5, duration = 0.4) {
    const a = Math.max(0, +amount || 0);
    const cur = this._shakeDur > 0 ? this._shakeAmt * Math.pow(1 - Math.min(1, this._shakeT / this._shakeDur), 2) : 0;
    if (a < cur) return;
    this._shakeAmt = a; this._shakeT = 0; this._shakeDur = Math.max(0.05, +duration || 0.4);
    for (let i = 0; i < 6; i++) this._shakePh[i] = Math.random() * Math.PI * 2;
  }

  setBlur(v) { this._blurTarget = Math.min(1, Math.max(0, +v || 0)); }
  setHiddenView(v) { this._hiddenTarget = Math.min(1, Math.max(0, +v || 0)); }

  update(dt) {
    dt = Math.min(Math.max(dt || 0, 0), 0.1);
    const u = this.uniforms;
    this.time += dt;
    this._frame = (this._frame + 1) % 65536;
    u.uFrame.value = this._frame;

    // smoothed state
    this._blur += (this._blurTarget - this._blur) * Math.min(1, dt * 10);
    if (Math.abs(this._blur - this._blurTarget) < 1e-3) this._blur = this._blurTarget;
    this._hidden += (this._hiddenTarget - this._hidden) * Math.min(1, dt * 4);
    if (Math.abs(this._hidden - this._hiddenTarget) < 1e-3) this._hidden = this._hiddenTarget;

    // heartbeat pulse: "lub-dub", 54 bpm calm → ~130 bpm terrified, only visible when fear is high-ish
    const f = this.fear;
    this._beat = (this._beat + dt * (0.9 + 1.25 * f)) % 1;
    const p = this._beat;
    const lub = Math.exp(-(((p - 0.06) / 0.05) ** 2));
    const dub = 0.6 * Math.exp(-(((p - 0.3) / 0.06) ** 2));
    this._pulse = (lub + dub) * smooth01(0.25, 0.8, f);

    // flash
    let fa = 0;
    if (this._flashDur > 0) {
      this._flashT += dt;
      const k = Math.min(1, this._flashT / this._flashDur);
      fa = this._flashAmt * (1 - k) * (1 - k);
      if (k >= 1) { this._flashDur = 0; fa = 0; }
    }
    u.uFlash.value.set(this._flashColor.r, this._flashColor.g, this._flashColor.b, fa);

    // shake (smooth multi-sine noise, decaying envelope)
    let sx = 0, sy = 0, sr = 0, amp = 0;
    if (this._shakeDur > 0) {
      this._shakeT += dt;
      const k = Math.min(1, this._shakeT / this._shakeDur);
      const env = this._shakeAmt * (1 - k) * (1 - k);
      if (k >= 1) this._shakeDur = 0;
      const t = this.time, ph = this._shakePh;
      amp = 0.011 * env;
      sx = amp * (0.62 * Math.sin(t * 37.1 + ph[0]) + 0.38 * Math.sin(t * 17.3 + ph[1]));
      sy = amp * (0.62 * Math.sin(t * 31.7 + ph[2]) + 0.38 * Math.sin(t * 13.9 + ph[3]));
      sr = 0.014 * env * (0.6 * Math.sin(t * 23.3 + ph[4]) + 0.4 * Math.sin(t * 9.7 + ph[5]));
    }
    u.uShake.value.set(sx, sy, sr);

    const distort = this.distortion + this._pulse * 0.02 * f;
    u.uDistort.value = distort;
    // zoom so the distorted / shaken image always covers the screen (no clamped borders)
    u.uZoom.value = 1 / ((1 + distort) * (1 + 2.2 * amp + 1.2 * Math.abs(sr) * Math.max(1, this._aspect)));

    u.uCA.value = this.chromatic * (1 + 2.5 * f + 0.8 * this._pulse);
    u.uVignette.value = this.vignette;
    u.uGrain.value = this.grain;
    u.uFear.value = f;
    u.uPulse.value = this._pulse;
    u.uBlur.value = this._blur;
    u.uHidden.value = this._hidden;
    u.uSlatPhase.value = 0.08 * Math.sin(this.time * 1.6);
    u.uSlatAxis.value = this.slatAxis;
    u.uLift.value.copy(this.lift);
    u.uGammaV.value.copy(this.gamma);
    u.uGain.value.copy(this.gain);
    u.uSat.value = this.saturation;
    u.uContrast.value = this.contrast;
  }

  /** Render the FX pass from `texture` to the screen. */
  render(webgl, texture, exposure = 1) {
    this.uniforms.tDiffuse.value = texture;
    this.uniforms.toneMappingExposure.value = exposure;
    webgl.setRenderTarget(null);
    this.quad.render(webgl);
  }

  dispose() { this.material.dispose(); this.quad.dispose(); }
}
