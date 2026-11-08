import * as THREE from 'three';
import * as L from '../config/layout.js';

// STUB — to be replaced by the architecture module (see ARCHITECTURE.md §Architecture).
// Builds the static shell: floor, ceiling (with stairwell opening), walls (with doorway/window openings),
// baseboards & trims, stairs + knee wall + railing, landing, upstairs door + short lit hallway,
// closet under the stairs with a LOUVERED door, alcove (laundry nook), barred basement window.
// Must register: world.colliders (walls, stairs side wall, closed doors), world.occluders (walls, doors),
// world.handles['door.upstairs'], world.handles['door.closet'], world.hideSpots (closet).
// Public API: constructor(game, world), async build(), update(dt), reset(kind)
export class Architecture {
  constructor(game, world) { this.game = game; this.world = world; }

  async build() {
    const { scene } = this.game;
    const R = L.ROOM;
    const mat = new THREE.MeshStandardMaterial({ color: 0xbfae92, roughness: 0.9 });
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(R.maxX - R.minX, R.maxZ - R.minZ), mat);
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor);
    const add = (w, h, d, x, y, z) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
      m.position.set(x, y, z); m.receiveShadow = true; scene.add(m); this.world.addOccluder(m);
      this.world.addCollider([x - w / 2, y - h / 2, z - d / 2], [x + w / 2, y + h / 2, z + d / 2], 'wall');
    };
    const H = R.ceilingY, T = 0.2;
    add(7.4, H, T, 0, H / 2, R.minZ - T / 2);
    add(7.4, H, T, 0, H / 2, R.maxZ + T / 2);
    add(T, H, 5.9, R.minX - T / 2, H / 2, 0);
    add(T, H, 5.9, R.maxX + T / 2, H / 2, 0);
    const ceil = new THREE.Mesh(new THREE.PlaneGeometry(7, 5.5), mat);
    ceil.rotation.x = Math.PI / 2; ceil.position.y = H; scene.add(ceil);
    const noop = { isOpen: false, locked: false, open: async () => {}, close: async () => {}, toggle: async () => {}, object: floor, worldPosition: () => new THREE.Vector3() };
    this.world.handles['door.upstairs'] = { ...noop, id: 'door.upstairs', locked: true };
    this.world.handles['door.closet'] = { ...noop, id: 'door.closet' };
    this.world.hideSpots.push({ id: 'closet', door: this.world.handles['door.closet'], ...L.CLOSET });
  }

  update() {}
  reset() {}
}
