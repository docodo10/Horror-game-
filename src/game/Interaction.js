// STUB — to be replaced by the gameplay module (see ARCHITECTURE.md §Interaction).
// Public API (must be kept):
//   constructor(game); init(); update(dt)
//   register({ id, object, prompt, enabled?, onInteract, hold?, maxDistance? }) -> unregister()
//       object: THREE.Object3D whose meshes are ray-tested (recursive)
//       prompt: string | () => string     e.g. 'Ouvrir le tiroir'
//       enabled: () => boolean            defaults to () => true
//       onInteract: () => void
//       hold: seconds to hold the interact button (shows a progress ring), default 0
//       maxDistance: default 2.1 m
//   unregister(id)
//   .current   currently targeted entry or null
// The interaction ray starts at the camera and is blocked by world.occluders (first hit wins).
export class Interaction {
  constructor(game) { this.game = game; this.entries = new Map(); this.current = null; }
  init() {}
  register(e) { this.entries.set(e.id, e); return () => this.unregister(e.id); }
  unregister(id) { this.entries.delete(id); }
  update() {}
}
