import * as THREE from 'three';
import * as L from '../config/layout.js';

// STUB — to be replaced by the architecture/lighting module (see ARCHITECTURE.md §Lighting).
// Public API (must be kept):
//   constructor(game, world); async build(); async bakeEnvironment(); update(dt); reset(kind)
//   .power (bool)
//   setPower(on)                 ceiling light on/off (+ fan light), smooth ramp, flicker on power-up
//   blowout()                    bulb pop + sparks/flash + power off (calls world.setPower(false))
//   flicker(duration=0.6, depth=1)  one-shot flicker burst of the ceiling light
//   setStress(v)                 0..1 continuous flicker probability (entity proximity)
//   setTVLight(on, intensity)    cool flickering light in front of the TV screen
//   doorStrip                    the light leaking under the upstairs door: setOccluded(v 0..1) (feet shadows)
export class Lighting {
  constructor(game, world) { this.game = game; this.world = world; this.power = true; this.doorStrip = { setOccluded() {} }; }

  async build() {
    this.ceiling = new THREE.PointLight(0xffd2a1, 8, 12, 2);
    this.ceiling.position.set(L.FAN.x, 2.0, L.FAN.z);
    this.ceiling.castShadow = true;
    this.game.scene.add(this.ceiling);
    this.hemi = new THREE.HemisphereLight(0x405060, 0x201810, 0.15);
    this.game.scene.add(this.hemi);
  }

  async bakeEnvironment() {}
  setPower(on) { this.power = on; this.ceiling.visible = on; }
  blowout() { this.world.setPower(false); }
  flicker() {}
  setStress() {}
  setTVLight() {}
  update() {}
  reset() {}
}
