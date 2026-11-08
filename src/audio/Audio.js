// STUB — to be replaced by the audio module (see ARCHITECTURE.md §Audio).
// Procedural Web Audio (no audio files). Positional sounds use PannerNode HRTF; the listener follows game.camera.
// Public API (must be kept):
//   constructor(game); init(); unlock() (call from a user gesture); update(dt)
//   play(name, { position?, volume?, rate? }) -> handle { stop(fade?), setVolume(v), setPosition(v3) }
//   loop(name, { position?, volume? })        -> same handle (looping until stop())
//   setFear(v 0..1)      heartbeat + low drone intensity
//   setPaused(bool)      duck everything while paused
//   setMasterVolume(v)
// Sound names: see ARCHITECTURE.md §Audio (all must exist; unknown names log a warning once and do nothing).
export class AudioEngine {
  constructor(game) { this.game = game; }
  init() {}
  unlock() {}
  update() {}
  play() { return { stop() {}, setVolume() {}, setPosition() {} }; }
  loop() { return { stop() {}, setVolume() {}, setPosition() {} }; }
  setFear() {}
  setPaused() {}
  setMasterVolume() {}
}
