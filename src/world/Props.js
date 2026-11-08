import * as THREE from 'three';
import * as L from '../config/layout.js';

// STUB — to be replaced by the props module (see ARCHITECTURE.md §Props).
// Places every model from layout.PROPS, registers colliders/occluders, builds animated Handles,
// pickup items, clue decals, the TV controller, procedural textures (rug, kid drawings, photos, notes).
// Public API: constructor(game, world); async build(); update(dt); reset(kind); setPower(on)
//   world.setClueDigits(d) is implemented here via props.setClueDigits({duck, horse, clock, tv}) — World forwards it.
//   props.rockChair(seconds)  make the rocking chair rock by itself for a while (scare beat)
export class Props {
  constructor(game, world) {
    this.game = game; this.world = world;
    world.setClueDigits = (d) => this.setClueDigits(d);
  }

  async build() {
    const { assets, scene } = this.game;
    for (const [key, p] of Object.entries(L.PROPS)) {
      try {
        const o = assets.instance(p.model);
        o.position.fromArray(p.pos); o.rotation.y = p.rotY || 0; o.scale.setScalar(p.scale || 1);
        o.name = key; scene.add(o);
      } catch (e) { console.warn(e); }
    }
    const mk = (id) => { const m = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.05, 0.1), new THREE.MeshStandardMaterial({ color: 0xffffff })); m.name = id; scene.add(m); return m; };
    for (const id of ['flashlight', 'battery1', 'battery2', 'key', 'note1', 'note2', 'note3']) this.world.items[id] = mk(id);
    this.world.items.note1.position.fromArray(L.ITEMS.note1.pos);
    const noop = (id) => ({ id, isOpen: false, open: async () => {}, close: async () => {}, toggle: async () => {}, object: mk(id), worldPosition: () => new THREE.Vector3(), contents: new THREE.Group() });
    for (const id of ['dresser.drawerTop', 'dresser.drawerMid', 'dresser.drawerBottom', 'endTable.drawer', 'alcoveCabinet.drawer_01', 'alcoveCabinet.drawer_02', 'alcoveCabinet.door_01', 'alcoveCabinet.door_02', 'powerBox.door', 'lockedBox.lid']) this.world.handles[id] = noop(id);
    this.world.handles['powerBox.lever'] = { ...noop('powerBox.lever'), isOn: false, setOn: async () => {} };
    this.world.handles['lockedBox.lock'] = noop('lockedBox.lock');
    this.world.clues = { duck: mk('duck'), horse: mk('horse'), clock: mk('clock'), tv: mk('tvclue') };
    this.world.tv = { object: mk('tv'), isOn: false, setOn(on) { this.isOn = on; }, setDigit() {}, screenPosition: new THREE.Vector3(-0.55, 1.42, -2.38) };
  }

  setClueDigits() {}
  rockChair() {}
  setPower() {}
  update() {}
  reset() {}
}
