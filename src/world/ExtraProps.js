import * as THREE from 'three';
import * as L from '../config/layout.js';

// STUB — to be replaced by the extras module.
// Places layout.EXTRA_PROPS (batch-2 Poly Haven set dressing, see assets/NEW_ASSETS.md), the live mirror reflection,
// laundry-basket cloth, the old CRT in the nook (flickers when power returns), glass/reflective material upgrades.
// Public API: constructor(game, world); async build(); update(dt); reset(kind); setPower(on)
export class ExtraProps {
  constructor(game, world) { this.game = game; this.world = world; }
  async build() {
    for (const [key, p] of Object.entries(L.EXTRA_PROPS)) {
      try {
        const o = this.game.assets.instance(p.model);
        o.position.fromArray(p.pos); o.rotation.set(p.rotX || 0, p.rotY || 0, p.rotZ || 0); o.scale.setScalar(p.scale || 1);
        o.name = 'extra_' + key; this.game.scene.add(o);
      } catch (e) { console.warn(e); }
    }
  }
  update() {}
  reset() {}
  setPower() {}
}
