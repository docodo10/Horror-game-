import * as THREE from 'three';

// STUB — to be replaced by the render module (see ARCHITECTURE.md §Renderer).
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
export class Renderer {
  constructor(game, canvas) {
    this.game = game;
    this.canvas = canvas;
    this.quality = 'medium';
    this.preset = { pixelRatio: 1, shadowMapSize: 1024, shadowsFlashlight: true, gtao: false, bloom: false, msaa: 0, envSize: 128 };
    this.fps = 60;
  }

  init() {
    this.webgl = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, powerPreference: 'high-performance' });
    this.webgl.outputColorSpace = THREE.SRGBColorSpace;
    this.webgl.toneMapping = THREE.AgXToneMapping;
    this.webgl.shadowMap.enabled = true;
    this.webgl.shadowMap.type = THREE.PCFSoftShadowMap;
    this.maxAnisotropy = this.webgl.capabilities.getMaxAnisotropy();
    this.resize();
  }

  setQuality(q) { this.game.events.emit('quality:changed', { quality: this.quality, preset: this.preset }); }

  resize() {
    const w = window.innerWidth, h = window.innerHeight;
    this.webgl.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    this.webgl.setSize(w, h, false);
    this.game.camera.aspect = w / h;
    this.game.camera.updateProjectionMatrix();
  }

  render(dt) {
    if (dt > 0) this.fps += (1 / dt - this.fps) * 0.05;
    this.webgl.render(this.game.scene, this.game.camera);
  }

  warmup() { this.webgl.compile(this.game.scene, this.game.camera); }
  setFear() {}
  flash() {}
  shake() {}
  setBlur() {}
  setHiddenView() {}
}
