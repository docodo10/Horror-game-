import * as THREE from 'three';

// STUB — to be replaced by the entity module (see ARCHITECTURE.md §Gardienne).
// Public API (must be kept):
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
export class Gardienne {
  constructor(game) { this.game = game; this.state = 'dormant'; this.position = new THREE.Vector3(-3, 2.75, -3.6); this.fear = 0; this.active = false; this.root = new THREE.Group(); }
  async init() { this.game.scene.add(this.root); this.root.visible = false; }
  update() {}
  reset() { this.state = 'dormant'; this.active = false; }
  summon() {}
  setAggression() {}
  setEnabled() {}
}
