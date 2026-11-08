import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import * as L from '../config/layout.js';
import * as PT from './ProcTextures.js';

// Props module — furniture, animated handles, pickups, clues, TV, procedural set dressing.
// Places every model from layout.PROPS, registers colliders/occluders, builds animated Handles,
// pickup items, clue decals, the TV controller, procedural textures (rug, kid drawings, photos, notes).
// Public API: constructor(game, world); async build(); update(dt); reset(kind); setPower(on)
//   world.setClueDigits(d) is implemented here via props.setClueDigits({duck, horse, clock, tv}) — World forwards it.
//   props.rockChair(seconds)  make the rocking chair rock by itself for a while (scare beat)
// Extra (optional) API:
//   props.revealClue(id)      'duck' | 'horse': lift & tilt the object so the digit under it faces the camera (~2.6 s)
//   props.objects             { [layout PROPS key]: Object3D }
//   handles['lockedBox.lock'].setDigits('1234')  rotate the 4 number wheels (animated, lock_wheel ticks)
//   world.codeNote            the child's code note mesh on the box lid (moves with the lid)
// Notes: every placed root is named by its layout.PROPS key. handles['powerBox.lever'] starts isOn=true and follows
// world.setPower silently (tripped at the blowout, no sfx); setOn(on) animates + breaker_flip + world.setPower(on).
// The TV light is driven only through lighting.setTVLight(on, intensity). Batch-2 models (layout.EXTRA_PROPS: laundry
// crate, stool, pull-chain socket, mirror, big stairwell frames…) are placed by ExtraProps.js, not here — the
// procedural dressing below is laid out around them.

const UP = new THREE.Vector3(0, 1, 0);
const DOWN = new THREE.Vector3(0, -1, 0);
const Z_AXIS = new THREE.Vector3(0, 0, 1);

const E = {
  inOut: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  out: (t) => 1 - Math.pow(1 - t, 3),
  in: (t) => t * t * t,
  sine: (t) => -(Math.cos(Math.PI * t) - 1) / 2,
  outBack: (t) => { const c1 = 1.3, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); },
  inQuad: (t) => t * t,
};

// The standing photo frame's picture faces its local +X: turn it toward the room.
const ROT = { photoFrame: -1.27 };

// Small nudges (≤ 10 cm) applied to layout positions: keep nav links clear / sit things correctly.
const NUDGE = {
  endTable: [0, 0, 0.06],
  kidChair: [-0.06, 0, 0],
  horse: [0, 0, -0.05], // the shelf boards are only ~20 cm deep
};

/** Value animator 0..1 with easing, promise-based. */
class Anim {
  constructor(apply, { v = 0, easeUp = E.inOut, easeDown = E.inOut } = {}) {
    this.apply = apply; this.v = v; this.from = v; this.target = v; this.t = 0; this.dur = 0.5;
    this.easeUp = easeUp; this.easeDown = easeDown; this.active = false; this.waiters = [];
    apply(v);
  }

  to(target, dur) {
    if (!this.active && this.v === target) return Promise.resolve();
    this.from = this.v; this.target = target; this.t = 0;
    this.dur = Math.max(0.05, dur * Math.min(1, Math.abs(target - this.v) + 0.15));
    this.active = true;
    return new Promise((r) => this.waiters.push(r));
  }

  set(v) {
    this.v = this.from = this.target = v; this.active = false; this.apply(v);
    const w = this.waiters; this.waiters = []; for (const r of w) r();
  }

  update(dt) {
    if (!this.active) return;
    this.t += dt;
    const p = Math.min(1, this.t / this.dur);
    const e = (this.target >= this.from ? this.easeUp : this.easeDown)(p);
    this.v = this.from + (this.target - this.from) * e;
    this.apply(this.v);
    if (p >= 1) {
      this.v = this.target; this.active = false; this.apply(this.v);
      const w = this.waiters; this.waiters = []; for (const r of w) r();
    }
  }
}

/** Merge geometries (mixing indexed / non-indexed), optionally painting a flat vertex color per part. */
function mergeGeos(list, colors = null) {
  const anyNonIndexed = list.some((g) => !g.index);
  const parts = list.map((g, i) => {
    let q = anyNonIndexed && g.index ? g.toNonIndexed() : g;
    for (const k of Object.keys(q.attributes)) if (k !== 'position' && k !== 'normal' && k !== 'uv') q.deleteAttribute(k);
    if (!q.attributes.uv) q.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(q.attributes.position.count * 2), 2));
    if (colors) {
      const c = colors[i], n = q.attributes.position.count, arr = new Float32Array(n * 3);
      for (let j = 0; j < n; j++) { arr[j * 3] = c.r; arr[j * 3 + 1] = c.g; arr[j * 3 + 2] = c.b; }
      q.setAttribute('color', new THREE.BufferAttribute(arr, 3));
    }
    return q;
  });
  return mergeGeometries(parts, false);
}

function remapUV(geo, u0, v0, u1, v1) {
  const uv = geo.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, u0 + uv.getX(i) * (u1 - u0), v0 + uv.getY(i) * (v1 - v0));
  uv.needsUpdate = true;
  return geo;
}

function shadows(obj, cast, receive = true) {
  obj.traverse((o) => { if (o.isMesh) { o.castShadow = cast; o.receiveShadow = receive; } });
  return obj;
}

const col = (hex) => new THREE.Color(hex);

export class Props {
  constructor(game, world) {
    this.game = game; this.world = world;
    this.objects = {};
    this._anims = [];
    this._ray = new THREE.Raycaster();
    this._v1 = new THREE.Vector3(); this._v2 = new THREE.Vector3(); this._v3 = new THREE.Vector3();
    this._q1 = new THREE.Quaternion(); this._q2 = new THREE.Quaternion();
    this._box = new THREE.Box3();
    this._time = 0;
    this._power = true;
    this._fanSpeed = 2.4;
    this._loopsStarted = false;
    this._proxyMat = new THREE.MeshBasicMaterial({ visible: false });
    this._digits = {};
    world.setClueDigits = (d) => this.setClueDigits(d);
  }

  // =========================================================================================== build

  async build() {
    const { scene } = this.game;
    PT.setAnisotropy(this.game.renderer?.maxAnisotropy ?? 4);
    this._preset = this.game.renderer?.preset || {};
    await PT.waitFonts(2200);
    this._archOcc = this.world.occluders.slice(); // architecture shell (walls, ceiling, knee wall…)
    scene.updateMatrixWorld(true);

    this._buildRug();
    this._placeModels();
    scene.updateMatrixWorld(true);
    this._settle();
    scene.updateMatrixWorld(true);

    const steps = [
      '_buildDrawers', '_buildCabinet', '_buildPowerBox', '_buildLockedBox', '_buildItems', '_buildTV',
      '_buildClocks', '_buildFan', '_buildRocking', '_buildClueDecals', '_buildWallArt', '_buildPhotos',
      '_buildFixtures', '_buildKidsCorner', '_buildNook', '_buildDresserTop', '_buildDecals',
    ];
    for (const s of steps) {
      try { this[s](); } catch (e) { console.error(`[props] ${s} failed`, e); }
    }
    this._ensureContract();
    scene.updateMatrixWorld(true);
    this._registerColliders();
    this._registerOccluders();
    this._wireEvents();
    if (this.world.power === false) this.setPower(false);
  }

  // ------------------------------------------------------------------------------------------- placement

  _placeModels() {
    const { assets, scene } = this.game;
    for (const [key, p] of Object.entries(L.PROPS)) {
      let o;
      try { o = assets.instance(p.model, { uniqueMaterials: key === 'kidChair' }); } catch (e) { console.warn('[props]', e.message); continue; }
      const n = NUDGE[key] || [0, 0, 0];
      o.name = key;
      o.position.set(p.pos[0] + n[0], p.pos[1] + n[1], p.pos[2] + n[2]);
      o.rotation.y = ROT[key] ?? (p.rotY || 0);
      o.scale.setScalar(p.scale || 1);
      scene.add(o);
      this.objects[key] = o;
    }
    for (const k of ['grandfather', 'alarmClock', 'photoFrame']) this._fixGlass(this.objects[k]);
    // the kid's chair: worn teal paint (like the reference photos)
    this.objects.kidChair?.traverse((o) => { if (o.isMesh && o.material?.color) o.material.color.setRGB(0.42, 0.68, 0.72); });
    // static multi-mesh scans: one draw call per material (the encyclopedia set alone is 40 meshes)
    for (const k of ['books', 'cassette']) this._mergeStatic(this.objects[k]);
    // tiny scans: no shadow casting (saves 6 cube-shadow passes each)
    for (const k of ['alarmClock', 'cassette', 'bulb', 'photoFrame', 'books']) if (this.objects[k]) shadows(this.objects[k], false, true);
  }

  /** Merge all meshes of a static model into one mesh per material (keeps the root transform). */
  _mergeStatic(root) {
    if (!root) return;
    root.updateWorldMatrix(true, true);
    const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
    const meshes = [];
    root.traverse((o) => { if (o.isMesh && !Array.isArray(o.material)) meshes.push(o); });
    if (meshes.length < 2) return;
    const byMat = new Map();
    const m4 = new THREE.Matrix4();
    for (const m of meshes) {
      const geo = m.geometry.clone().applyMatrix4(m4.multiplyMatrices(inv, m.matrixWorld));
      if (!byMat.has(m.material)) byMat.set(m.material, []);
      byMat.get(m.material).push(geo);
    }
    for (const m of meshes) m.parent?.remove(m);
    for (const [mat, geos] of byMat) {
      const mesh = new THREE.Mesh(mergeGeos(geos), mat);
      mesh.castShadow = true; mesh.receiveShadow = true;
      root.add(mesh);
    }
  }

  /** The scanned glass panes share the opaque body atlas: give them a real thin-glass look. */
  _fixGlass(obj) {
    if (!obj) return;
    if (!this._glassMat) {
      this._glassMat = new THREE.MeshStandardMaterial({
        color: 0xffffff, roughness: 0.04, metalness: 0, transparent: true, opacity: 0.1, depthWrite: false, side: THREE.DoubleSide,
      });
      this._glassMat.name = 'props_glass';
    }
    obj.traverse((o) => {
      if (!o.isMesh) return;
      if (Array.isArray(o.material)) o.material = o.material.map((m) => (/glass/i.test(m.name) ? this._glassMat : m));
      else if (/glass/i.test(o.material?.name || '')) o.material = this._glassMat;
      if (o.material === this._glassMat || (Array.isArray(o.material) && o.material.includes(this._glassMat))) o.castShadow = false;
    });
  }

  /** Raycast straight down onto `targets`; returns the highest hit y (or null). */
  _downHit(targets, x, z, fromY, far = 4) {
    this._ray.set(this._v1.set(x, fromY, z), DOWN);
    this._ray.near = 0; this._ray.far = far;
    const hits = this._ray.intersectObjects(targets, true);
    for (const h of hits) if (h.object.isMesh && h.object.material?.visible !== false) return h.point.y;
    return null;
  }

  /** Put obj on top of `supports` (sampling its footprint). */
  _dropOnto(obj, supports, { from = null, sink = 0, samples = 5 } = {}) {
    if (!obj) return false;
    const sup = supports.filter(Boolean);
    if (!sup.length) return false;
    obj.updateWorldMatrix(true, true);
    const b = this._box.setFromObject(obj);
    const fromY = from ?? b.max.y + 0.02;
    const cx = (b.min.x + b.max.x) / 2, cz = (b.min.z + b.max.z) / 2;
    const hx = (b.max.x - b.min.x) * 0.3, hz = (b.max.z - b.min.z) * 0.3;
    const pts = samples === 1 ? [[cx, cz]] : [[cx, cz], [cx - hx, cz - hz], [cx + hx, cz - hz], [cx - hx, cz + hz], [cx + hx, cz + hz]];
    let best = -Infinity;
    for (const [x, z] of pts) { const y = this._downHit(sup, x, z, fromY); if (y !== null && y > best) best = y; }
    if (best === -Infinity) return false;
    obj.position.y += best - b.min.y - sink;
    obj.updateWorldMatrix(false, true);
    return true;
  }

  _settle() {
    const O = this.objects;
    this._dropOnto(O.tv, [O.dresser]);
    this._dropOnto(O.photoFrame, [O.dresser]);
    // painted_wooden_shelves: arched back panel on top, boards at ~0.74 and ~0.46 m
    const shY = O.shelves ? O.shelves.position.y : 0;
    this._dropOnto(O.horse, [O.shelves], { from: shY + 1.0 });
    this._dropOnto(O.lockedBox, [O.console]);
    this._dropOnto(O.alarmClock, [O.coffeeTable]);
    this._dropOnto(O.cassette, [O.kidTable]);
    this._dropOnto(O.boxB, [O.boxA]);
    this._dropOnto(O.pillows, [O.sofa], { samples: 1, sink: 0.012 });
    this._dropOnto(O.duck, [this.rug]);
    this._dropOnto(O.books, [O.shelves], { from: shY + 0.69 });
    // wall frames: back flush against the wall (+3 mm)
    this._hangOnWall(O.sofaPainting, 'S');
    this._hangOnWall(O.roundFrame, 'E');
  }

  _hangOnWall(obj, dir) {
    if (!obj) return;
    obj.updateWorldMatrix(true, true);
    const b = this._box.setFromObject(obj);
    const d = this._dirVec(dir);
    const c = this._v2.set((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, (b.min.z + b.max.z) / 2);
    const wall = this._wallHit(c, d, 0.5);
    if (!wall) return;
    // current back extent along d
    const back = d.x > 0 ? b.max.x : d.x < 0 ? b.min.x : d.z > 0 ? b.max.z : b.min.z;
    const wallCoord = d.x !== 0 ? wall.x : wall.z;
    const delta = (wallCoord - back) - Math.sign(d.x + d.z) * 0.003;
    if (Math.abs(delta) > 0.08) return;
    if (d.x !== 0) obj.position.x += delta; else obj.position.z += delta;
  }

  // ------------------------------------------------------------------------------------------- wall helpers

  _dirVec(dir) {
    switch (dir) {
      case 'N': return new THREE.Vector3(0, 0, -1);
      case 'S': return new THREE.Vector3(0, 0, 1);
      case 'W': return new THREE.Vector3(-1, 0, 0);
      case 'E': return new THREE.Vector3(1, 0, 0);
      case 'U': return new THREE.Vector3(0, 1, 0);
      default: return new THREE.Vector3(0, -1, 0);
    }
  }

  /** Hit point on the architecture shell from p along d (within maxDist), or null. */
  _wallHit(p, d, maxDist = 0.6) {
    this._ray.set(this._v3.copy(p).addScaledVector(d, -maxDist), d);
    this._ray.near = 0; this._ray.far = maxDist * 2;
    const hits = this._ray.intersectObjects(this._archOcc, true);
    return hits.length ? hits[0].point.clone() : null;
  }

  /**
   * Mount `obj` (local +Z = front, back face at local z = 0) on the wall/ceiling nearest to the nominal point.
   * dir: which way the surface is from the point ('N','S','E','W','U'). Falls back to the nominal plane.
   */
  _mount(obj, x, y, z, dir, { gap = 0.002, tol = 0.14, rotZ = 0, attach = true } = {}) {
    const d = this._dirVec(dir);
    const p = new THREE.Vector3(x, y, z);
    let surf = null;
    const hit = this._wallHit(p, d, 0.45);
    if (hit) {
      const along = (hit.x - p.x) * d.x + (hit.y - p.y) * d.y + (hit.z - p.z) * d.z;
      if (Math.abs(along) <= tol) surf = hit;
    }
    if (!surf) surf = p.clone();
    obj.position.copy(surf).addScaledVector(d, -gap);
    if (dir === 'U') { obj.rotation.set(Math.PI / 2, 0, rotZ); }
    else { obj.rotation.set(0, Math.atan2(-d.x, -d.z), rotZ, 'YXZ'); }
    if (attach && !obj.parent) this.game.scene.add(obj);
    return obj;
  }

  // ------------------------------------------------------------------------------------------- handles

  _anim(apply, opts) { const a = new Anim(apply, opts); this._anims.push(a); return a; }

  _sfx(name, obj, opts = {}) {
    try {
      const position = obj?.isVector3 ? obj.clone() : obj ? obj.getWorldPosition(new THREE.Vector3()) : undefined;
      return this.game.audio?.play?.(name, { position, ...opts });
    } catch (e) { return null; }
  }

  /**
   * Generic openable. anim: Anim (0 closed .. 1 open). sfx: [openName, closeName].
   */
  _handle(id, { object, anim, contents = null, openDur = 0.5, closeDur = 0.45, sfx = [], volume = 1, extra = {} }) {
    const props = this;
    const h = {
      id, object, contents, isOpen: false,
      open() {
        if (h.isOpen) return anim.active ? new Promise((r) => anim.waiters.push(r)) : Promise.resolve();
        h.isOpen = true;
        if (sfx[0]) props._sfx(sfx[0], object, { volume });
        return anim.to(1, openDur);
      },
      close() {
        if (!h.isOpen) return anim.active ? new Promise((r) => anim.waiters.push(r)) : Promise.resolve();
        h.isOpen = false;
        if (sfx[1]) props._sfx(sfx[1], object, { volume });
        return anim.to(0, closeDur);
      },
      toggle() { return h.isOpen ? h.close() : h.open(); },
      worldPosition(target = new THREE.Vector3()) { return object.getWorldPosition(target); },
      ...extra,
    };
    this.world.handles[id] = h;
    return h;
  }

  /** Raycast inside a node (straight down) to find an inner floor; returns node-local y. */
  _innerFloor(node, lx, lz, ly, fallback) {
    node.updateWorldMatrix(true, false);
    const o = this._v1.set(lx, ly, lz).applyMatrix4(node.matrixWorld);
    this._ray.set(o, DOWN); this._ray.near = 0; this._ray.far = 1.2;
    const hit = this._ray.intersectObject(node, false)[0];
    if (!hit) return fallback;
    return node.worldToLocal(this._v2.copy(hit.point)).y;
  }

  /** Invisible raycast/occlusion box (local coords of parent). */
  _proxy(parent, x0, y0, z0, x1, y1, z1, name = 'proxy') {
    const m = new THREE.Mesh(new THREE.BoxGeometry(x1 - x0, y1 - y0, z1 - z0), this._proxyMat);
    m.position.set((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
    m.name = name; m.castShadow = false; m.receiveShadow = false;
    parent.add(m);
    return m;
  }

  _buildDrawers() {
    const O = this.objects;
    if (O.dresser) {
      const map = [['dresser.drawerTop', 'GothicCommode_01_door01'], ['dresser.drawerMid', 'GothicCommode_01_door02'], ['dresser.drawerBottom', 'GothicCommode_01_door03']];
      for (const [id, nodeName] of map) {
        const node = O.dresser.getObjectByName(nodeName);
        if (!node) continue;
        const z0 = node.position.z;
        const anim = this._anim((v) => { node.position.z = z0 + v * 0.3; }, { easeUp: E.out, easeDown: E.inOut });
        const contents = new THREE.Group(); contents.name = id + '.contents';
        contents.position.set(0, this._innerFloor(node, 0, -0.27, 0.1, -0.1), -0.27);
        node.add(contents);
        this._handle(id, { object: node, anim, contents, openDur: 0.55, closeDur: 0.45, sfx: ['drawer_open', 'drawer_close'] });
      }
    }
    if (O.endTable) {
      const node = O.endTable.getObjectByName('painted_wooden_nightstand_drawer');
      if (node) {
        const z0 = node.position.z;
        const anim = this._anim((v) => { node.position.z = z0 + v * 0.22; }, { easeUp: E.out });
        const contents = new THREE.Group();
        contents.position.set(0, this._innerFloor(node, 0, -0.17, 0.04, -0.035), -0.17);
        node.add(contents);
        this._handle('endTable.drawer', { object: node, anim, contents, openDur: 0.5, closeDur: 0.4, sfx: ['drawer_open', 'drawer_close'] });
      }
    }
  }

  _buildCabinet() {
    const cab = this.objects.alcoveCabinet;
    if (!cab) return;
    for (const k of ['01', '02']) {
      const node = cab.getObjectByName('painted_wooden_cabinet_drawer_' + k);
      if (!node) continue;
      node.position.z = 0.235; // drawer_01 is authored slightly open
      const anim = this._anim((v) => { node.position.z = 0.235 + v * 0.24; }, { easeUp: E.out });
      const contents = new THREE.Group();
      contents.position.set(0, this._innerFloor(node, 0, -0.17, 0.06, -0.11), -0.17);
      node.add(contents);
      this._handle('alcoveCabinet.drawer_' + k, { object: node, anim, contents, openDur: 0.55, closeDur: 0.45, sfx: ['drawer_open', 'drawer_close'] });
    }
    for (const [k, sign, cx] of [['01', -1, -0.3], ['02', 1, 0.3]]) {
      const node = cab.getObjectByName('painted_wooden_cabinet_door_' + k);
      if (!node) continue;
      const anim = this._anim((v) => { node.quaternion.setFromAxisAngle(UP, sign * 1.85 * v); }, { easeUp: E.out, easeDown: E.inOut });
      // contents: static compartment behind this door (not moving with the door)
      const contents = new THREE.Group();
      contents.position.set(cx, this._innerFloor(cab.getObjectByName('painted_wooden_cabinet') || cab, cx, 0.02, 0.8, 0.16), 0.02);
      contents.name = 'alcoveCabinet.door_' + k + '.contents';
      cab.add(contents);
      this._handle('alcoveCabinet.door_' + k, { object: node, anim, contents, openDur: 0.75, closeDur: 0.6, sfx: ['cabinet_open', 'cabinet_close'] });
    }
  }

  _buildPowerBox() {
    const pb = this.objects.powerBox;
    if (!pb) return;
    const door = pb.getObjectByName('power_box_01_door');
    const body = pb.getObjectByName('power_box_01_box');
    if (door) {
      const anim = this._anim((v) => { door.quaternion.setFromAxisAngle(UP, -1.9 * v); }, { easeUp: E.out });
      this._handle('powerBox.door', { object: door, anim, openDur: 0.7, closeDur: 0.55, sfx: ['cabinet_open', 'cabinet_close'], volume: 0.9 });
    }
    // find the back plate of the panel (local z) to mount the main breaker on it
    // the panel has an inner cover ("dead front") ~3 cm behind the door: mount the main breaker on it
    let zBack = 0.014;
    if (body) {
      pb.updateWorldMatrix(true, true);
      const o = this._v1.set(0.105, 0.05, 0.2).applyMatrix4(pb.matrixWorld);
      const d = this._v2.set(0, 0, -1).transformDirection(pb.matrixWorld);
      this._ray.set(o, d); this._ray.near = 0; this._ray.far = 0.4;
      const hit = this._ray.intersectObject(body, false)[0];
      if (hit) zBack = Math.max(-0.03, Math.min(0.02, pb.worldToLocal(this._v3.copy(hit.point)).z));
    }
    const g = new THREE.Group(); g.name = 'powerBox.lever'; pb.add(g);
    const bakelite = new THREE.MeshStandardMaterial({ color: 0x141414, roughness: 0.38, metalness: 0 });
    const red = new THREE.MeshStandardMaterial({ color: 0x8e1b16, roughness: 0.42 });
    const LX = 0.105, LY = 0.05;
    const block = new THREE.Mesh(new RoundedBoxGeometry(0.05, 0.085, 0.012, 2, 0.003), bakelite);
    block.position.set(LX, LY, zBack + 0.006);
    g.add(block);
    const slot = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.04, 0.002), new THREE.MeshStandardMaterial({ color: 0x050505, roughness: 0.9 }));
    slot.position.set(LX, LY, zBack + 0.0121); g.add(slot);
    const pivot = new THREE.Group(); pivot.position.set(LX, LY, zBack + 0.01); g.add(pivot);
    const armGeo = mergeGeos([
      new THREE.BoxGeometry(0.02, 0.008, 0.012).translate(0, 0, 0.006),
      new RoundedBoxGeometry(0.034, 0.009, 0.009, 2, 0.0025).translate(0, 0, 0.0145),
    ]);
    const arm = new THREE.Mesh(armGeo, red); pivot.add(arm);
    const labelMat = new THREE.MeshStandardMaterial({ map: PT.breakerLabelTexture(), roughness: 0.85, polygonOffset: true, polygonOffsetFactor: -2 });
    const label = new THREE.Mesh(new THREE.PlaneGeometry(0.058, 0.029), labelMat);
    label.position.set(LX + 0.006, LY - 0.074, zBack + 0.001); label.rotation.z = 0.04; g.add(label);
    this._proxy(g, LX - 0.035, LY - 0.05, zBack, LX + 0.035, LY + 0.05, zBack + 0.026, 'lever.hit');
    shadows(g, false, true);
    const anim = this._anim((v) => { pivot.rotation.x = 0.6 - 1.2 * v; }, { v: 1, easeUp: E.inQuad, easeDown: E.inQuad });
    const props = this;
    const lever = this._handle('powerBox.lever', { object: g, anim, openDur: 0.2, closeDur: 0.2 });
    lever.isOn = true; lever.isOpen = true;
    lever.setOn = async (on) => {
      on = !!on;
      if (lever.isOn === on && !anim.active) return;
      lever.isOn = on; lever.isOpen = on;
      await anim.to(on ? 1 : 0, 0.2);
      props._sfx('breaker_flip', g);
      if (props.world.power !== on) props.world.setPower(on);
    };
    lever.open = () => lever.setOn(true);
    lever.close = () => lever.setOn(false);
    lever.toggle = () => lever.setOn(!lever.isOn);
    this._lever = { handle: lever, anim };
  }

  _buildLockedBox() {
    const box = this.objects.lockedBox;
    if (!box) return;
    const S = box.scale.x || 1, inv = 1 / S;
    const lidNode = box.getObjectByName('CheeseBox_01_lid');
    // --- lid hinge at the top back edge
    const pivot = new THREE.Group(); pivot.name = 'lockedBox.lid';
    pivot.position.set(0, 0.066, -0.0527);
    box.add(pivot);
    if (lidNode) { pivot.add(lidNode); lidNode.position.set(0, 0.002 - 0.066, 0.0527); }
    const lidFrame = new THREE.Group(); lidFrame.scale.setScalar(inv); pivot.add(lidFrame); // real meters, hinge at origin
    const boxFrame = new THREE.Group(); boxFrame.scale.setScalar(inv); box.add(boxFrame);    // real meters, box origin
    const depth = 0.1057 * S; // hinge → front edge
    // the child's code note, taped on the lid
    const noteMat = new THREE.MeshStandardMaterial({ map: PT.codeNoteTexture(), roughness: 0.9, side: THREE.DoubleSide });
    const note = new THREE.Mesh(this._paperGeo(0.215, 0.143, { curl: 0.0015 }), noteMat);
    note.position.set(0.035, 0.0006, depth / 2 - 0.004); note.rotation.y = 0.04;
    note.name = 'codeNote'; note.receiveShadow = true;
    lidFrame.add(note);
    this.world.codeNote = note; this.codeNote = note;
    // hasp plate hinged on the lid front edge
    const iron = new THREE.MeshStandardMaterial({ color: 0x2b2722, metalness: 0.85, roughness: 0.5 });
    const hasp = new THREE.Mesh(mergeGeos([
      new THREE.BoxGeometry(0.022, 0.016, 0.002).translate(0, -0.01, 0),
      new THREE.BoxGeometry(0.022, 0.012, 0.002).translate(0, -0.046, 0),
      new THREE.BoxGeometry(0.005, 0.03, 0.002).translate(-0.0085, -0.028, 0),
      new THREE.BoxGeometry(0.005, 0.03, 0.002).translate(0.0085, -0.028, 0),
      new THREE.CylinderGeometry(0.0022, 0.0022, 0.024, 8).rotateZ(Math.PI / 2).translate(0, 0, 0.0004),
    ]), iron);
    hasp.position.set(0, -0.001, depth + 0.0011);
    lidFrame.add(hasp);
    // lid hit proxy covering the whole box while closed (easy to target on phones)
    this._proxy(lidFrame, -0.205, -0.112, 0.0, 0.205, 0.004, depth, 'lid.hit');
    // staple on the box front (the padlock shackle passes through it)
    const steel = new THREE.MeshStandardMaterial({ color: 0x8d8a84, metalness: 1, roughness: 0.35 });
    const staple = new THREE.Mesh(new THREE.TorusGeometry(0.0062, 0.0013, 8, 14, Math.PI).rotateZ(-Math.PI / 2).rotateY(-Math.PI / 2), steel);
    staple.scale.set(1, 1, 2);
    const frontZ = 0.053 * S;
    staple.position.set(0, 0.07, frontZ);
    boxFrame.add(staple);
    shadows(boxFrame, false, true);
    shadows(lidFrame, false, true);

    const lidAnim = this._anim((v) => { pivot.rotation.x = -1.92 * v; }, { easeUp: E.outBack, easeDown: E.inOut });
    const contents = new THREE.Group(); contents.name = 'lockedBox.contents';
    contents.scale.setScalar(inv);
    contents.position.set(-0.055, this._innerFloor(box.getObjectByName('CheeseBox_01') || box, -0.055, 0, 0.05, 0.0045) + 0.0003, 0);
    box.add(contents);
    const props = this;
    const lid = this._handle('lockedBox.lid', { object: pivot, anim: lidAnim, contents, openDur: 0.85, closeDur: 0.5, sfx: ['box_open', 'cabinet_close'], volume: 0.8 });
    const baseOpen = lid.open;
    lid.open = () => { if (!props._lockRemoved) props._removeLock(true); return baseOpen(); };
    this._lid = lid;
    this._boxFrame = boxFrame;

    // --- combination padlock (brass, 4 number wheels)
    const lock = this._buildPadlock();
    lock.position.set(0, 0.068, frontZ + 0.0066);
    lock.rotation.x = -0.12;
    boxFrame.add(lock);
    this._lock = lock;
    this._lockRest = { p: lock.position.clone(), q: lock.quaternion.clone() };
    this._lockRemoved = false;
    const lockAnim = this._anim((v) => this._applyLockFall(v));
    const shackleAnim = this._anim((v) => { lock.userData.shackle.position.y = 0.0095 * v; }, { easeUp: E.outBack });
    this._lockAnim = lockAnim; this._shackleAnim = shackleAnim;
    const lh = this._handle('lockedBox.lock', { object: lock, anim: shackleAnim });
    lh.open = async () => {
      if (lh.isOpen) return;
      lh.isOpen = true;
      props._sfx('unlock', lock);
      await shackleAnim.to(1, 0.18);
      await props._removeLock(false);
    };
    lh.close = async () => {
      if (!lh.isOpen) return;
      lh.isOpen = false;
      props._lockRemoved = false;
      lockAnim.set(0); shackleAnim.set(0);
    };
    lh.toggle = () => (lh.isOpen ? lh.close() : lh.open());
    lh.setDigits = (s) => props._setLockDigits(s, true);
    this._setLockDigits('0000', false);
  }

  _buildPadlock() {
    const lock = new THREE.Group(); lock.name = 'lockedBox.lock';
    const brass = new THREE.MeshStandardMaterial({ color: 0xc29a48, metalness: 1, roughness: 0.32 });
    const steel = new THREE.MeshStandardMaterial({ color: 0xb9b6ae, metalness: 1, roughness: 0.25 });
    const inner = new THREE.Group(); inner.position.y = -0.0425; lock.add(inner); // origin = shackle top (hanging point)
    const body = new THREE.Mesh(mergeGeos([
      new RoundedBoxGeometry(0.034, 0.044, 0.014, 3, 0.003),
      // dividers between the wheels
      ...[-0.014, -0.007, 0, 0.007, 0.014].map((x) => new THREE.BoxGeometry(0.0011, 0.016, 0.0034).translate(x, -0.006, 0.0068)),
    ]), brass);
    inner.add(body);
    const wheelMat = new THREE.MeshStandardMaterial({ map: PT.lockWheelTexture(), metalness: 0.9, roughness: 0.35 });
    const wheelGeo = new THREE.CylinderGeometry(0.0062, 0.0062, 0.0058, 20).rotateZ(Math.PI / 2);
    const wheels = [];
    for (let i = 0; i < 4; i++) {
      const w = new THREE.Mesh(wheelGeo, wheelMat);
      w.position.set(-0.0105 + i * 0.007, -0.006, 0.0047);
      inner.add(w); wheels.push(w);
    }
    // shackle: U tube, legs at x = ±0.0085
    const r = 0.0085, top = 0.034;
    const pts = [];
    pts.push(new THREE.Vector3(-r, 0.012, 0), new THREE.Vector3(-r, top, 0));
    for (let i = 1; i < 12; i++) { const a = Math.PI - (i / 12) * Math.PI; pts.push(new THREE.Vector3(Math.cos(a) * r, top + Math.sin(a) * r, 0)); }
    pts.push(new THREE.Vector3(r, top, 0), new THREE.Vector3(r, 0.012, 0));
    const curve = new THREE.CatmullRomCurve3(pts, false, 'centripetal');
    const shackle = new THREE.Mesh(new THREE.TubeGeometry(curve, 40, 0.0022, 8, false), steel);
    inner.add(shackle);
    // generous hit box for phones
    this._proxy(inner, -0.022, -0.026, -0.01, 0.022, 0.046, 0.014, 'lock.hit');
    shadows(lock, false, true);
    lock.userData = { wheels, shackle, digits: [0, 0, 0, 0], animating: false };
    return lock;
  }

  _setLockDigits(str, animate) {
    const lock = this._lock;
    if (!lock) return;
    const s = String(str ?? '').padStart(4, '0').slice(-4);
    const ud = lock.userData;
    for (let i = 0; i < 4; i++) {
      const d = Number(s[i]) || 0;
      if (d !== ud.digits[i] && animate) this._sfx('lock_wheel', lock, { volume: 0.6 });
      ud.digits[i] = d;
      if (!animate) ud.wheels[i].rotation.x = this._wheelAngle(d);
    }
    ud.animating = !!animate;
  }

  _wheelAngle(d) { return ((d + 0.5) / 10) * Math.PI * 2; }

  /** Pop the padlock off the staple and drop it on the console. */
  _removeLock(fast) {
    if (this._lockRemoved) return this._lockFallPromise || Promise.resolve();
    this._lockRemoved = true;
    const lh = this.world.handles['lockedBox.lock'];
    if (lh) lh.isOpen = true;
    this._shackleAnim?.set(1);
    // end pose: lying on its back on the console, in front of the box
    const lock = this._lock;
    this._lockEnd = {
      p: new THREE.Vector3(0.05, 0.0075, 0.053 * (this.objects.lockedBox?.scale.x || 1) + 0.022),
      q: new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, 0.5)),
    };
    this._lockFallPromise = this._lockAnim.to(1, fast ? 0.35 : 0.5).then(() => this._sfx('bump', lock, { volume: 0.35 }));
    return this._lockFallPromise;
  }

  _applyLockFall(v) {
    const lock = this._lock;
    if (!lock || !this._lockRest) return;
    if (v <= 0 || !this._lockEnd) { lock.position.copy(this._lockRest.p); lock.quaternion.copy(this._lockRest.q); return; }
    const a = this._lockRest, b = this._lockEnd;
    // lift up off the staple, then arc forward/down
    const lift = Math.sin(Math.min(1, v * 2.2) * Math.PI) * 0.012;
    lock.position.lerpVectors(a.p, b.p, E.inQuad(v));
    lock.position.y += lift;
    lock.position.z = a.p.z + (b.p.z - a.p.z) * E.out(v);
    lock.quaternion.slerpQuaternions(a.q, b.q, E.inOut(v));
  }

  // ------------------------------------------------------------------------------------------- items

  _paperGeo(w, h, { curl = 0.003, fold = 0, lift = 0.0008 } = {}) {
    const g = new THREE.PlaneGeometry(w, h, 10, 12);
    g.rotateX(-Math.PI / 2);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i) / (w / 2), z = p.getZ(i) / (h / 2);
      const y = lift + curl * (Math.pow(Math.abs(x), 4) * 0.7 + Math.pow(Math.abs(z), 5)) + fold * (1 - Math.abs(z)) * 0.5 + curl * 0.3 * Math.sin(x * 2.1 + z * 1.3);
      p.setY(i, Math.max(lift * 0.5, y));
    }
    g.computeVertexNormals();
    return g;
  }

  _wallPaperGeo(w, h, { curl = 0.006 } = {}) {
    const g = new THREE.PlaneGeometry(w, h, 6, 8);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i) / (w / 2), y = p.getY(i) / (h / 2);
      const bottom = Math.max(0, -y);
      p.setZ(i, curl * (Math.pow(bottom, 2) * (0.4 + 0.6 * Math.abs(x)) + 0.25 * Math.abs(x) * (1 - Math.abs(y))));
    }
    g.computeVertexNormals();
    return g;
  }

  _buildItems() {
    const { assets } = this.game;
    const H = this.world.handles;
    const items = this.world.items;
    // flashlight (top drawer)
    try {
      const fl = assets.instance('pastic_torch_6v');
      fl.name = 'flashlight';
      const c = H['dresser.drawerTop']?.contents;
      if (c) { c.add(fl); fl.position.set(-0.2, 0.07, 0.02); fl.rotation.y = 1.15; }
      else { this.game.scene.add(fl); fl.position.set(-0.55, 0.95, -2.2); }
      shadows(fl, false, true);
      items.flashlight = fl;
    } catch (e) { console.warn('[props] flashlight', e); }
    // batteries
    const bat1 = this._makeBatteries(); bat1.name = 'battery1';
    const c1 = H['endTable.drawer']?.contents;
    if (c1) { c1.add(bat1); bat1.position.set(0.06, 0, 0.03); bat1.rotation.y = 0.35; }
    items.battery1 = bat1;
    const bat2 = this._makeBatteries(); bat2.name = 'battery2';
    const c2 = H['alcoveCabinet.drawer_01']?.contents;
    if (c2) { c2.add(bat2); bat2.position.set(-0.04, 0, 0.04); bat2.rotation.y = -0.6; }
    items.battery2 = bat2;
    // key inside the box (under the lid)
    const key = this._makeKey(); key.name = 'key';
    const ck = this.world.handles['lockedBox.lid']?.contents;
    if (ck) { ck.add(key); key.position.set(0.0, 0, 0.0); key.rotation.y = 0.5; }
    else { this.game.scene.add(key); key.position.set(3.1, 0.96, 0.15); }
    items.key = key;
    // note 1 on the coffee table
    const n1 = new THREE.Mesh(this._paperGeo(0.148, 0.203, { curl: 0.004, fold: 0.004 }), new THREE.MeshStandardMaterial({ map: PT.note1Texture(), roughness: 0.88, side: THREE.DoubleSide }));
    n1.name = 'note1'; n1.receiveShadow = true;
    const p1 = L.ITEMS.note1;
    n1.position.set(p1.pos[0], p1.pos[1], p1.pos[2]); n1.rotation.y = p1.rotY;
    this.game.scene.add(n1);
    const y1 = this._downHit([this.objects.coffeeTable].filter(Boolean), p1.pos[0], p1.pos[2], 1.2);
    if (y1 !== null) n1.position.y = y1;
    items.note1 = n1;
    // note 2: the child's drawing on the kid table
    const d2 = PT.note2Texture();
    const n2 = new THREE.Mesh(this._paperGeo(0.297, 0.21, { curl: 0.005 }), new THREE.MeshStandardMaterial({ map: d2.texture, roughness: 0.9, side: THREE.DoubleSide }));
    n2.name = 'note2'; n2.receiveShadow = true;
    const p2 = L.ITEMS.note2;
    n2.position.set(p2.pos[0], p2.pos[1], p2.pos[2]); n2.rotation.y = p2.rotY;
    this.game.scene.add(n2);
    const y2 = this._downHit([this.objects.kidTable].filter(Boolean), p2.pos[0], p2.pos[2], 1.2);
    if (y2 !== null) n2.position.y = y2;
    items.note2 = n2;
    // note 3: newspaper clipping inside the alcove cabinet (left door)
    const n3 = new THREE.Mesh(this._paperGeo(0.16, 0.219, { curl: 0.003, fold: 0.003 }), new THREE.MeshStandardMaterial({ map: PT.newspaperTexture(), roughness: 0.92, alphaTest: 0.5, side: THREE.DoubleSide }));
    n3.name = 'note3'; n3.receiveShadow = true;
    const c3 = H['alcoveCabinet.door_01']?.contents;
    if (c3) { c3.add(n3); n3.position.set(0.0, 0.0, 0.02); n3.rotation.y = 0.25; }
    else { this.game.scene.add(n3); n3.position.set(0.7, 0.2, -4.2); }
    items.note3 = n3;
  }

  _makeBatteries() {
    if (!this._batGeo) {
      // D cells lying side by side; the copper band (texture top) ends up at -x = positive terminal
      const cell = (z) => new THREE.CylinderGeometry(0.0168, 0.0168, 0.058, 24, 1, true).rotateZ(Math.PI / 2).translate(0, 0.0168, z);
      const caps = (z) => [
        new THREE.CircleGeometry(0.0168, 24).rotateY(Math.PI / 2).translate(0.029, 0.0168, z),
        new THREE.CircleGeometry(0.0168, 24).rotateY(-Math.PI / 2).translate(-0.029, 0.0168, z),
        new THREE.CylinderGeometry(0.0048, 0.0052, 0.0024, 14).rotateZ(Math.PI / 2).translate(-0.0302, 0.0168, z),
      ];
      const body = mergeGeos([cell(0), cell(0.0342)]);
      const metal = mergeGeos([...caps(0), ...caps(0.0342)]);
      this._batGeo = { body, metal };
      this._batMat = {
        label: new THREE.MeshStandardMaterial({ map: PT.batteryLabelTexture(), roughness: 0.4, metalness: 0.2 }),
        metal: new THREE.MeshStandardMaterial({ color: 0xb8b4ac, roughness: 0.3, metalness: 1 }),
      };
    }
    const g = new THREE.Group();
    const a = new THREE.Mesh(this._batGeo.body, this._batMat.label);
    const b = new THREE.Mesh(this._batGeo.metal, this._batMat.metal);
    a.position.z = b.position.z = -0.0171;
    g.add(a, b);
    this._proxy(g, -0.04, 0, -0.04, 0.04, 0.04, 0.04, 'battery.hit');
    shadows(g, false, true);
    return g;
  }

  _makeKey() {
    const brass = new THREE.MeshStandardMaterial({ color: 0xc79d4c, metalness: 1, roughness: 0.28 });
    const steel = new THREE.MeshStandardMaterial({ color: 0x9a9890, metalness: 1, roughness: 0.3 });
    const ex = { depth: 0.0022, bevelEnabled: true, bevelThickness: 0.0005, bevelSize: 0.0005, bevelSegments: 2, curveSegments: 20 };
    // bow: rounded trefoil head with a hole
    const bow = new THREE.Shape();
    const N = 48;
    for (let i = 0; i <= N; i++) {
      const a = (i / N) * Math.PI * 2;
      const r = 0.0118 + 0.0016 * Math.cos(a * 3);
      const x = Math.cos(a) * r, y = Math.sin(a) * r;
      if (i === 0) bow.moveTo(x, y); else bow.lineTo(x, y);
    }
    const hole = new THREE.Path(); hole.absarc(-0.003, 0, 0.0042, 0, Math.PI * 2, true); bow.holes.push(hole);
    const bowGeo = new THREE.ExtrudeGeometry(bow, ex);
    // shank + bit with teeth
    const blade = new THREE.Shape();
    blade.moveTo(0.0105, -0.0028);
    blade.lineTo(0.034, -0.0028);
    const teeth = [[0.036, -0.0085], [0.039, -0.0085], [0.041, -0.006], [0.044, -0.006], [0.046, -0.0092], [0.049, -0.0092], [0.051, -0.0065], [0.054, -0.0075], [0.057, -0.0045], [0.059, -0.0028]];
    for (const [x, y] of teeth) blade.lineTo(x, y);
    blade.lineTo(0.0615, -0.0015); blade.lineTo(0.0615, 0.0022); blade.lineTo(0.0105, 0.0028); blade.closePath();
    const bladeGeo = new THREE.ExtrudeGeometry(blade, { ...ex, depth: 0.0018 });
    bladeGeo.translate(0, 0, 0.0002);
    const collar = new THREE.CylinderGeometry(0.0038, 0.0038, 0.0035, 16).rotateZ(Math.PI / 2).translate(0.0125, 0, 0.0011);
    const keyGeo = mergeGeos([bowGeo, bladeGeo, collar]);
    keyGeo.rotateX(-Math.PI / 2); // lie flat (extrusion now along +y)
    keyGeo.translate(0, 0.0005, 0);
    const key = new THREE.Group();
    const km = new THREE.Mesh(keyGeo, brass);
    key.add(km);
    // split ring through the bow + cardboard tag
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.0105, 0.0009, 6, 28), steel);
    ring.rotation.x = -Math.PI / 2; ring.rotation.y = 0.18; ring.position.set(-0.012, 0.0022, 0);
    key.add(ring);
    const tagMat = new THREE.MeshStandardMaterial({ map: PT.keyTagTexture(), roughness: 0.9, side: THREE.DoubleSide });
    const tag = new THREE.Mesh(new THREE.PlaneGeometry(0.046, 0.029).rotateX(-Math.PI / 2), tagMat);
    tag.position.set(-0.039, 0.0012, 0.008); tag.rotation.y = 0.35;
    key.add(tag);
    this._proxy(key, -0.065, 0, -0.02, 0.065, 0.02, 0.025, 'key.hit');
    shadows(key, false, true);
    return key;
  }

  // ------------------------------------------------------------------------------------------- TV

  _buildTV() {
    const tvObj = this.objects.tv;
    const props = this;
    const low = (this._preset?.pixelRatio ?? 1) <= 1 && this._preset?.bloom === false;
    const stat = new PT.TVStatic(low ? 128 : 176, low ? 96 : 132);
    this._static = stat;
    // curved screen following the CRT glass bulge (measured: z = 0.1225 - 1.07 (x² + dy²))
    const geo = new THREE.PlaneGeometry(0.292, 0.212, 20, 14);
    const p = geo.attributes.position;
    for (let i = 0; i < p.count; i++) { const x = p.getX(i), y = p.getY(i); p.setZ(i, 0.1237 - 0.9 * (x * x + y * y)); }
    geo.computeVertexNormals();
    const mat = new THREE.MeshBasicMaterial({ map: stat.texture, color: new THREE.Color(1.35, 1.4, 1.5), toneMapped: true });
    const screen = new THREE.Mesh(geo, mat);
    screen.name = 'tv.screen'; screen.visible = false; screen.castShadow = false; screen.receiveShadow = false;
    screen.position.set(0, 0.26, 0);
    if (tvObj) tvObj.add(screen);
    const screenPosition = new THREE.Vector3();
    if (tvObj) { tvObj.updateWorldMatrix(true, true); screen.localToWorld(screenPosition.set(0, 0, 0.124)); }
    this._tvState = { screen, mat, t: 0, phase: 'off', phaseT: 0, acc: 0, loop: null, lightT: 0 };
    this.tv = {
      object: tvObj || screen,
      isOn: false,
      screenPosition,
      setOn: (on) => props._tvSetOn(!!on),
      setDigit: (d) => { props._digits.tv = d; stat.setDigit(d); },
    };
    this.world.tv = this.tv;
  }

  _tvSetOn(on) {
    const tv = this.tv, s = this._tvState;
    if (!tv || !s) return false;
    if (on && this.world.power === false) return false;
    if (on === tv.isOn) return true;
    tv.isOn = on;
    if (on) {
      s.phase = 'warm'; s.phaseT = 0; s.screen.visible = true; s.screen.scale.set(1, 0.02, 1);
      this._static.fill(1);
      try { s.loop?.stop?.(0.05); } catch (e) { /* ignore */ }
      s.loop = this.game.audio?.loop?.('tv_static', { position: tv.screenPosition.clone(), volume: 0.9 }) || null;
      this.world.lighting?.setTVLight?.(true, 1);
    } else {
      s.phase = 'collapse'; s.phaseT = 0;
      try { s.loop?.stop?.(0.08); } catch (e) { /* ignore */ }
      s.loop = null;
      this._sfx('tv_off', tv.screenPosition);
      this.world.lighting?.setTVLight?.(false, 0);
    }
    return true;
  }

  _updateTV(dt) {
    const s = this._tvState;
    if (!s || s.phase === 'off') return;
    s.t += dt; s.phaseT += dt;
    const scr = s.screen;
    if (s.phase === 'warm') {
      const k = Math.min(1, s.phaseT / 0.28);
      scr.scale.set(1, 0.02 + 0.98 * E.out(k), 1);
      if (k >= 1) { s.phase = 'on'; scr.scale.set(1, 1, 1); }
    } else if (s.phase === 'collapse') {
      const t = s.phaseT;
      if (t < 0.12) { scr.scale.set(1, Math.max(0.012, 1 - t / 0.12), 1); this._static.fill(1); }
      else if (t < 0.3) { const k = (t - 0.12) / 0.18; scr.scale.set(Math.max(0.01, 1 - k), 0.012, 1); this._static.fill(1 - k * 0.5); }
      else { scr.visible = false; scr.scale.set(1, 1, 1); s.phase = 'off'; }
      return;
    }
    // static at ~30 fps (20 on low)
    s.acc += dt;
    const step = (this._preset?.bloom === false) ? 1 / 20 : 1 / 30;
    if (s.acc < step) return;
    s.acc = 0;
    let amount = 0;
    if (this._static.hasDigit) {
      const ph = s.t % 1.5;
      if (ph < 0.34) amount = Math.sin((ph / 0.34) * Math.PI) * (Math.random() < 0.75 ? 0.85 : 0.2);
      else if (Math.random() < 0.025) amount = 0.18; // ghost frame
    }
    this._static.draw(s.t, amount, s.phase === 'warm' ? 1.4 : 1);
  }

  // ------------------------------------------------------------------------------------------- clocks / fan / rocking

  _buildClocks() {
    const gf = this.objects.grandfather;
    if (gf) {
      const hand = (name) => {
        const n = gf.getObjectByName(name);
        if (!n) return null;
        return { node: n, a0: this._handAngleLocal(n), base: n.quaternion.clone() };
      };
      this._gfHands = { hour: hand('vintage_grandfather_clock_01_HourHand'), minute: hand('vintage_grandfather_clock_01_MinuteHand') };
      this._setGFHands(10 + 10 / 60, 10); // stopped at an arbitrary time until the clue digit is set
    }
    const ac = this.objects.alarmClock;
    if (ac) {
      const hand = (name) => {
        const n = ac.getObjectByName(name);
        if (!n) return null;
        return { node: n, base: n.quaternion.clone(), a0: this._handAngleParent(n) };
      };
      this._acHands = { h: hand('houd_hand'), m: hand('minute_hand'), s: hand('second_hand') };
      this._acTime = 3 * 3600 + 7 * 60 + 12; // 3:07:12 — the night it happens
      this._acLastSec = -1; this._acTick = 1;
      this._updateAlarmClock(0, true);
    }
  }

  /** Angle (atan2 in node-local XY) of the farthest vertex from the pivot. */
  _handAngleLocal(node) {
    const p = node.geometry?.attributes?.position;
    if (!p) return Math.PI / 2;
    let best = -1, ang = 0;
    for (let i = 0; i < p.count; i++) { const x = p.getX(i), y = p.getY(i), d = x * x + y * y; if (d > best) { best = d; ang = Math.atan2(y, x); } }
    return ang;
  }

  /** Same, but in the parent (model) space after the node's own rotation, projected on the XY plane. */
  _handAngleParent(node) {
    const p = node.geometry?.attributes?.position;
    if (!p) return Math.PI / 2;
    let best = -1, ang = 0;
    const v = new THREE.Vector3();
    for (let i = 0; i < p.count; i++) {
      v.fromBufferAttribute(p, i).applyQuaternion(node.quaternion);
      const d = v.x * v.x + v.y * v.y;
      if (d > best) { best = d; ang = Math.atan2(v.y, v.x); }
    }
    return ang;
  }

  _setGFHands(hours, minutes) {
    const H = this._gfHands;
    if (!H) return;
    const ha = Math.PI / 2 - ((hours % 12) / 12) * Math.PI * 2;
    const ma = Math.PI / 2 - ((minutes % 60) / 60) * Math.PI * 2;
    if (H.hour) H.hour.node.rotation.z = ha - H.hour.a0;
    if (H.minute) H.minute.node.rotation.z = ma - H.minute.a0;
  }

  _setACHand(hd, angle) {
    if (!hd) return;
    this._q1.setFromAxisAngle(Z_AXIS, angle - hd.a0);
    hd.node.quaternion.copy(this._q1).multiply(hd.base);
  }

  _updateAlarmClock(dt, force = false) {
    const H = this._acHands;
    if (!H) return;
    this._acTime += dt;
    const t = this._acTime;
    const sec = Math.floor(t) % 60;
    if (sec !== this._acLastSec) { this._acLastSec = sec; this._acTick = 0; force = true; }
    if (this._acTick < 1) { this._acTick = Math.min(1, this._acTick + dt / 0.09); force = true; }
    if (!force) return;
    const k = E.outBack(this._acTick);
    const secA = Math.PI / 2 - ((sec - 1 + k) / 60) * Math.PI * 2;
    const minutes = (t / 60) % 60, hours = (t / 3600) % 12;
    this._setACHand(H.s, secA);
    this._setACHand(H.m, Math.PI / 2 - (minutes / 60) * Math.PI * 2);
    this._setACHand(H.h, Math.PI / 2 - (hours / 12) * Math.PI * 2);
  }

  _buildFan() {
    const fan = this.objects.fan;
    this._fanBlades = fan?.getObjectByName('ceiling_fan_blades') || null;
    if (fan) shadows(fan, true, false);
  }

  _buildRocking() {
    const chair = this.objects.rockingChair;
    if (!chair) return;
    const R = 0.95;
    const root = new THREE.Group(); root.name = 'rockingChair.root';
    root.position.set(chair.position.x, 0, chair.position.z);
    root.rotation.y = chair.rotation.y;
    const pivot = new THREE.Group(); pivot.position.y = R; root.add(pivot);
    const y0 = chair.position.y;
    chair.position.set(0, y0 - R, 0); chair.rotation.set(0, 0, 0);
    pivot.add(chair);
    this.game.scene.add(root);
    this._rock = { root, pivot, R, t: 0, dur: 0, amp: 0, active: false, loop: null, resolve: null, theta: 0 };
  }

  /** Make the rocking chair rock by itself for `seconds` (returns a promise resolved when it is still again). */
  rockChair(seconds = 6) {
    const r = this._rock;
    if (!r) return Promise.resolve();
    r.resolve?.();
    r.t = 0; r.dur = Math.max(1.5, seconds); r.active = true;
    try { r.loop?.stop?.(0.2); } catch (e) { /* ignore */ }
    r.loop = this.game.audio?.loop?.('rocking_chair', { position: r.root.getWorldPosition(new THREE.Vector3()).setY(0.5), volume: 0.85 }) || null;
    return new Promise((res) => { r.resolve = res; });
  }

  _updateRocking(dt) {
    const r = this._rock;
    if (!r || !r.active) return;
    r.t += dt;
    const w = (Math.PI * 2) / 1.75;
    const decay = 2.2;
    let amp;
    if (r.t < 0.9) amp = 0.11 * E.out(r.t / 0.9);
    else if (r.t < r.dur - decay) amp = 0.11;
    else amp = 0.11 * Math.max(0, (r.dur - r.t) / decay);
    const th = amp * Math.sin(w * r.t);
    r.theta = th;
    r.pivot.rotation.x = th;
    r.pivot.position.z = r.R * th;
    if (r.t >= r.dur) this._stopRocking();
  }

  _stopRocking() {
    const r = this._rock;
    if (!r) return;
    r.active = false; r.pivot.rotation.x = 0; r.pivot.position.z = 0;
    try { r.loop?.stop?.(0.6); } catch (e) { /* ignore */ }
    r.loop = null;
    const res = r.resolve; r.resolve = null; res?.();
  }

  // ------------------------------------------------------------------------------------------- clues

  _buildClueDecals() {
    const O = this.objects;
    const mk = (parent, w, h, y, name) => {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshStandardMaterial({ transparent: true, roughness: 0.6, polygonOffset: true, polygonOffsetFactor: -4, depthWrite: false }));
      m.rotation.x = Math.PI / 2; // facing down
      m.position.y = y; m.visible = false; m.name = name;
      parent.add(m);
      return m;
    };
    if (O.duck) {
      const s = O.duck.scale.x || 1;
      this._duckDecal = mk(O.duck, 0.055 / s, 0.055 / s, 0.0012 / s, 'duck.digit');
      this._duckDecal.position.z = 0.01 / s;
    }
    if (O.horse) {
      const s = O.horse.scale.x || 1;
      this._horseDecal = mk(O.horse, 0.05 / s, 0.04 / s, 0.0012 / s, 'horse.digit');
    }
    this.world.clues = {
      duck: O.duck || new THREE.Object3D(),
      horse: O.horse || new THREE.Object3D(),
      clock: O.grandfather || new THREE.Object3D(),
      tv: O.tv || this.tv?.object || new THREE.Object3D(),
    };
  }

  setClueDigits(d = {}) {
    if (!d) return;
    const set = (decal, digit, onTape) => {
      if (!decal) return;
      decal.material.map?.dispose?.();
      decal.material.map = PT.digitDecal(digit, { onTape });
      decal.material.needsUpdate = true;
      decal.visible = true;
    };
    if (d.duck != null) { this._digits.duck = d.duck; set(this._duckDecal, d.duck, false); }
    if (d.horse != null) { this._digits.horse = d.horse; set(this._horseDecal, d.horse, true); }
    if (d.clock != null) { this._digits.clock = d.clock; const h = Number(d.clock); if (Number.isFinite(h)) this._setGFHands(h, 0); }
    if (d.tv != null) this.tv?.setDigit(d.tv);
  }

  /** Lift & tilt the duck / horse so the digit underneath faces the camera, then put it back (~2.6 s). */
  revealClue(id) {
    const obj = id === 'duck' ? this.objects.duck : id === 'horse' ? this.objects.horse : null;
    if (!obj || this._reveal?.active) return Promise.resolve();
    const restP = obj.position.clone(), restQ = obj.quaternion.clone();
    const cam = this.game.camera.getWorldPosition(new THREE.Vector3());
    const dir = cam.clone().sub(restP); dir.y = 0;
    if (dir.lengthSq() < 1e-6) dir.set(0, 0, 1);
    dir.normalize();
    const axis = new THREE.Vector3().crossVectors(DOWN, dir).normalize();
    const tilt = new THREE.Quaternion().setFromAxisAngle(axis, 1.95);
    const upP = restP.clone().addScaledVector(dir, 0.12); upP.y += id === 'duck' ? 0.32 : 0.12;
    const upQ = tilt.multiply(restQ.clone());
    const st = { active: true };
    this._reveal = st;
    this._sfx('pickup', obj, { volume: 0.5 });
    const a = this._anim((v) => { obj.position.lerpVectors(restP, upP, v); obj.quaternion.slerpQuaternions(restQ, upQ, v); }, { easeUp: E.inOut, easeDown: E.inOut });
    return a.to(1, 0.6)
      .then(() => new Promise((r) => setTimeout(r, 1500)))
      .then(() => a.to(0, 0.55))
      .then(() => { st.active = false; this._anims.splice(this._anims.indexOf(a), 1); obj.position.copy(restP); obj.quaternion.copy(restQ); });
  }

  // ------------------------------------------------------------------------------------------- set dressing

  _buildRug() {
    const { assets, scene } = this.game;
    const mat = new THREE.MeshStandardMaterial({ map: PT.rugTexture(), roughness: 0.96 });
    try {
      mat.normalMap = assets.texture('textures/carpet016/normal.jpg', { repeat: [6, 4.3] });
      mat.normalScale = new THREE.Vector2(0.7, 0.7);
    } catch (e) { /* ignore */ }
    const rug = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.007, 1.3), mat);
    rug.position.set(-1.55, 0.0035, 0.55); rug.rotation.y = 0.04;
    rug.receiveShadow = true; rug.castShadow = false; rug.name = 'kidsRug';
    scene.add(rug);
    this.rug = rug;
  }

  _buildWallArt() {
    const { scene } = this.game;
    const art = [
      { kind: 'gardienne', x: -2.5, y: 1.13, z: -0.55, dir: 'W', w: 0.21, rot: 0.03 },
      { kind: 'maison', x: -2.5, y: 0.6, z: 0.38, dir: 'W', w: 0.297, rot: -0.04 },
      { kind: 'mer', x: -2.32, y: 1.12, z: 2.75, dir: 'S', w: 0.297, rot: 0.02 },
      { kind: 'arcenciel', x: -1.78, y: 1.16, z: -2.75, dir: 'N', w: 0.21, rot: -0.05 },
    ];
    this._drawTex = {};
    let seed = 101;
    for (const a of art) {
      const d = PT.kidDrawing(a.kind, seed++, this._preset?.bloom === false ? 0.75 : 1);
      this._drawTex[a.kind] = d.texture;
      const h = a.w / d.aspect;
      const m = new THREE.Mesh(this._wallPaperGeo(a.w, h), new THREE.MeshStandardMaterial({ map: d.texture, roughness: 0.92 }));
      m.name = 'drawing.' + a.kind; m.receiveShadow = true; m.castShadow = false;
      this._mount(m, a.x, a.y, a.z, a.dir, { gap: 0.0015, rotZ: a.rot });
    }
    // crayon scribbles on the knee wall, low (kid height)
    const sc = PT.wallScribbles();
    const sm = new THREE.Mesh(new THREE.PlaneGeometry(0.72, 0.72 / sc.aspect), new THREE.MeshStandardMaterial({ map: sc.texture, transparent: true, depthWrite: false, roughness: 0.62, polygonOffset: true, polygonOffsetFactor: -2 }));
    sm.name = 'wallScribbles'; sm.receiveShadow = true;
    this._mount(sm, -2.5, 0.42, 0.05, 'W', { gap: 0.001 });
  }

  _buildPhotos() {
    const atlas = PT.photoAtlas();
    // Gallery wall up the stairwell (west wall). The two big batch-2 frames (layout.EXTRA_PROPS stairPhotoA at
    // z 0.3 / y 2.52 and stairPhotoB at z -0.75 / y 3.47, ~0.75 x 0.5 m) are placed by ExtraProps: fill around them.
    const frames = [
      { z: 1.3, y: 1.86, cell: 0, w: 0.18, rotZ: 0.0, frame: 1 },
      { z: 0.92, y: 2.08, cell: 2, w: 0.15, rotZ: -0.02, frame: 0 },
      { z: -0.225, y: 2.98, cell: 3, w: 0.15, rotZ: 0.07, frame: 2 }, // the scratched one, hanging crooked
      { z: -1.45, y: 3.82, cell: 4, w: 0.26, rotZ: -0.01, frame: 0 },
      { z: -2.2, y: 4.27, cell: 1, w: 0.24, rotZ: 0.015, frame: 1 }, // landing
    ];
    const frameGeos = [[], [], []], photoGeos = [];
    const tmp = new THREE.Object3D();
    for (const f of frames) {
      const cell = atlas.cells[f.cell];
      const w = f.w, h = w / cell.aspect, b = 0.022, d = 0.018;
      this._mount(tmp, -3.5, f.y, f.z, 'W', { gap: 0.0, rotZ: f.rotZ, tol: 0.05, attach: false });
      tmp.updateMatrix();
      const parts = [
        new THREE.BoxGeometry(w + 2 * b, b, d).translate(0, h / 2 + b / 2, d / 2),
        new THREE.BoxGeometry(w + 2 * b, b, d).translate(0, -h / 2 - b / 2, d / 2),
        new THREE.BoxGeometry(b, h, d).translate(-w / 2 - b / 2, 0, d / 2),
        new THREE.BoxGeometry(b, h, d).translate(w / 2 + b / 2, 0, d / 2),
        new THREE.BoxGeometry(w, h, 0.003).translate(0, 0, 0.0015), // backing board
      ];
      for (const p of parts) frameGeos[f.frame].push(p.applyMatrix4(tmp.matrix));
      const ph = remapUV(new THREE.PlaneGeometry(w, h), cell.u0, cell.v0, cell.u1, cell.v1).translate(0, 0, 0.0045);
      photoGeos.push(ph.applyMatrix4(tmp.matrix));
    }
    const mats = [
      new THREE.MeshStandardMaterial({ color: 0x3a2516, roughness: 0.55 }),
      new THREE.MeshStandardMaterial({ color: 0xa8843f, roughness: 0.4, metalness: 0.75 }),
      new THREE.MeshStandardMaterial({ color: 0x151313, roughness: 0.5 }),
    ];
    for (let i = 0; i < 3; i++) {
      if (!frameGeos[i].length) continue;
      const m = new THREE.Mesh(mergeGeos(frameGeos[i]), mats[i]);
      m.castShadow = true; m.receiveShadow = true; m.name = 'stairPhotos.frames' + i;
      this.game.scene.add(m);
    }
    const pm = new THREE.Mesh(mergeGeos(photoGeos), new THREE.MeshStandardMaterial({ map: atlas.texture, roughness: 0.3 }));
    pm.receiveShadow = true; pm.name = 'stairPhotos';
    this.game.scene.add(pm);
  }

  _buildFixtures() {
    const { scene } = this.game;
    const ivory = new THREE.MeshStandardMaterial({ color: 0xe3d8bf, roughness: 0.45 });
    const plateMats = new Map();
    const plate = (tex) => {
      const g = new RoundedBoxGeometry(0.07, 0.115, 0.006, 1, 0.0015).translate(0, 0, 0.003);
      if (!plateMats.has(tex)) plateMats.set(tex, new THREE.MeshStandardMaterial({ map: tex, roughness: 0.42 }));
      const m = new THREE.Mesh(g, plateMats.get(tex));
      m.receiveShadow = true; m.castShadow = false;
      return m;
    };
    const outletTex = PT.outletTexture(false), coverTex = PT.outletTexture(true);
    // outlets
    const o1 = plate(outletTex); this._mount(o1, -1.45, 0.3, -2.75, 'N', { gap: 0 }); o1.name = 'outlet.tv';
    const o2 = plate(coverTex); this._mount(o2, 3.5, 0.3, -1.65, 'E', { gap: 0 }); o2.name = 'outlet.east';
    const o3 = plate(outletTex); this._mount(o3, 2.05, 0.3, 2.75, 'S', { gap: 0 }); o3.name = 'outlet.south';
    const o4 = plate(outletTex); this._mount(o4, 1.7, 0.32, -4.6, 'N', { gap: 0 }); o4.name = 'outlet.nook';
    // TV plug + cable down behind the dresser to the outlet
    this._buildTVCable(o1);
    // light switch at the bottom of the stairs
    const sw = plate(PT.switchTexture()); this._mount(sw, -3.5, 1.22, 2.08, 'W', { gap: 0 }); sw.name = 'lightSwitch';
    const tog = new THREE.Mesh(new THREE.BoxGeometry(0.009, 0.022, 0.012).translate(0, 0.006, 0.006), ivory);
    tog.rotation.x = -0.35; tog.position.set(0, 0, 0.006); sw.add(tog);
    // smoke detector (ceiling) with a blinking red LED
    const det = new THREE.Group(); det.name = 'smokeDetector';
    const white = new THREE.MeshStandardMaterial({ color: 0xe9e6dc, roughness: 0.5 });
    const dg = mergeGeos([
      new THREE.CylinderGeometry(0.066, 0.07, 0.03, 32).rotateX(Math.PI / 2).translate(0, 0, 0.015),
      new THREE.CylinderGeometry(0.045, 0.05, 0.008, 32).rotateX(Math.PI / 2).translate(0, 0, 0.033),
      ...[0, 1, 2, 3, 4, 5, 6, 7].map((k) => new THREE.BoxGeometry(0.004, 0.03, 0.004).translate(0, 0.055, 0.031).rotateZ((k / 8) * Math.PI * 2)),
    ]);
    det.add(new THREE.Mesh(dg, white));
    this._ledMat = new THREE.MeshStandardMaterial({ color: 0x300000, emissive: 0xff1a0a, emissiveIntensity: 0, roughness: 0.3 });
    const led = new THREE.Mesh(new THREE.SphereGeometry(0.0035, 8, 6), this._ledMat);
    led.position.set(0.025, -0.02, 0.031); det.add(led);
    shadows(det, false, true);
    this._mount(det, -1.05, 2.5, -0.55, 'U', { gap: 0, tol: 0.3 });
    this._ledT = 7;
    // thermostat beside the laundry nook doorway (east side: the batch-2 mirror hangs on the west side)
    const th = new THREE.Mesh(
      new RoundedBoxGeometry(0.125, 0.082, 0.026, 2, 0.006).translate(0, 0, 0.013),
      new THREE.MeshStandardMaterial({ color: 0xd8d0bc, roughness: 0.55 }),
    );
    const face = new THREE.Mesh(new THREE.PlaneGeometry(0.115, 0.072).translate(0, 0, 0.0262), new THREE.MeshStandardMaterial({ map: PT.thermostatTexture(), roughness: 0.4 }));
    th.add(face); th.name = 'thermostat'; th.receiveShadow = true; th.castShadow = true;
    this._mount(th, 1.98, 1.52, -2.75, 'N', { gap: 0 });
    // air return grille, low on the south wall
    const gr = new THREE.Group(); gr.name = 'vent';
    const back = new THREE.Mesh(new THREE.PlaneGeometry(0.29, 0.14).translate(0, 0, 0.001), new THREE.MeshBasicMaterial({ color: 0x050505 }));
    const grille = new THREE.Mesh(new THREE.PlaneGeometry(0.31, 0.155).translate(0, 0, 0.006), new THREE.MeshStandardMaterial({ map: PT.grilleTexture(), alphaTest: 0.5, roughness: 0.5, metalness: 0.2, side: THREE.DoubleSide }));
    gr.add(back, grille);
    this._mount(gr, 3.05, 0.2, 2.75, 'S', { gap: 0 });
    shadows(gr, false, true);
    this._outlets = { o1, o2, o3, o4 };
    void scene;
  }

  _buildTVCable(outlet) {
    const tv = this.objects.tv;
    if (!tv || !outlet) return;
    outlet.updateWorldMatrix(true, false);
    const plugPos = outlet.localToWorld(new THREE.Vector3(0, 0.023, 0.016));
    const wallZ = outlet.getWorldPosition(new THREE.Vector3()).z;
    const blk = new THREE.MeshStandardMaterial({ color: 0x141414, roughness: 0.55 });
    const plug = new THREE.Mesh(new RoundedBoxGeometry(0.026, 0.03, 0.022, 2, 0.004), blk);
    plug.position.copy(plugPos); plug.position.z = wallZ + 0.006 + 0.011;
    plug.castShadow = false; plug.receiveShadow = true;
    this.game.scene.add(plug);
    const tvp = tv.getWorldPosition(new THREE.Vector3());
    const dresserTop = tvp.y;
    const pts = [
      new THREE.Vector3(tvp.x + 0.06, dresserTop + 0.09, tvp.z - 0.215),
      new THREE.Vector3(tvp.x + 0.02, dresserTop + 0.02, wallZ + 0.012),
      new THREE.Vector3(tvp.x - 0.12, dresserTop - 0.25, wallZ + 0.01),
      new THREE.Vector3(tvp.x - 0.4, 0.35, wallZ + 0.01),
      new THREE.Vector3(-1.13, 0.06, wallZ + 0.012),
      new THREE.Vector3(-1.2, 0.012, wallZ + 0.07),
      new THREE.Vector3(-1.33, 0.011, wallZ + 0.06),
      new THREE.Vector3(plugPos.x + 0.012, 0.03, wallZ + 0.03),
      new THREE.Vector3(plugPos.x + 0.004, plugPos.y - 0.12, wallZ + 0.018),
      new THREE.Vector3(plugPos.x, plugPos.y - 0.025, wallZ + 0.017),
    ];
    const curve = new THREE.CatmullRomCurve3(pts, false, 'catmullrom', 0.4);
    const cable = new THREE.Mesh(new THREE.TubeGeometry(curve, 90, 0.0028, 6, false), blk);
    cable.castShadow = false; cable.receiveShadow = true; cable.name = 'tvCable';
    this.game.scene.add(cable);
  }

  _buildDresserTop() {
    const O = this.objects;
    if (!O.dresser) return;
    // stack of VHS tapes left of the TV
    const tex = PT.vhsTexture();
    const geos = [];
    const sizes = [[0.188, 0.025, 0.104], [0.188, 0.025, 0.104], [0.188, 0.025, 0.104]];
    let y = 0;
    for (let k = 0; k < 3; k++) {
      const [w, h, d] = sizes[k];
      const g = new THREE.BoxGeometry(w, h, d);
      remapUV(g, 0, 1 - (k + 1) / 3, 1, 1 - k / 3);
      g.rotateY((k - 1) * 0.06 + (k === 2 ? 0.12 : 0)).translate((k - 1) * 0.004, y + h / 2, k * 0.003);
      geos.push(g); y += h;
    }
    const vhs = new THREE.Mesh(mergeGeos(geos), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.45 }));
    vhs.position.set(-0.95, 1.4, -2.47); vhs.rotation.y = 0.18; vhs.name = 'vhsTapes';
    shadows(vhs, true, true);
    this.game.scene.add(vhs);
    this._dropOnto(vhs, [O.dresser]);
    // TV remote on the coffee table
    if (O.coffeeTable) {
      const rem = new THREE.Mesh(new RoundedBoxGeometry(0.052, 0.02, 0.18, 2, 0.006), new THREE.MeshStandardMaterial({ color: 0x1d1d1f, roughness: 0.5 }));
      const top = new THREE.Mesh(new THREE.PlaneGeometry(0.046, 0.17).rotateX(-Math.PI / 2).translate(0, 0.0101, 0), new THREE.MeshStandardMaterial({ map: PT.remoteTexture(), roughness: 0.45, polygonOffset: true, polygonOffsetFactor: -1 }));
      rem.add(top);
      rem.position.set(0.36, 0.7, 1.04); rem.rotation.y = 0.62; rem.name = 'remote';
      shadows(rem, false, true);
      this.game.scene.add(rem);
      this._dropOnto(rem, [O.coffeeTable]);
    }
  }

  _buildKidsCorner() {
    const O = this.objects;
    const scene = this.game.scene;
    const rugTop = (this.rug ? this.rug.position.y + 0.0035 : 0.007);
    // toy blocks (one draw call)
    const bt = PT.blocksTexture();
    const blocks = [
      [-1.12, 0.28, 0.4, 0], [-1.02, 0.36, 1.1, 1], [-0.98, 0.24, 0.2, 2], [-0.98, 0.24, 0.5, 3, 1],
      [-1.3, 0.62, 0.9, 4], [-0.86, 0.72, 2.0, 5],
    ];
    const S = 0.045, bg = [];
    for (const [x, z, ry, cell, stack = 0] of blocks) {
      const g = new THREE.BoxGeometry(S, S, S);
      // per-face cells: +x,-x,+y,-y,+z,-z (4 verts each)
      const uv = g.attributes.uv;
      for (let f = 0; f < 6; f++) {
        const c = (cell + [1, 3, 0, 5, 2, 4][f]) % 8;
        for (let v = 0; v < 4; v++) { const i = f * 4 + v; uv.setX(i, (c + uv.getX(i)) / 8); }
      }
      g.rotateY(ry).translate(x, rugTop + S / 2 + stack * S, z);
      bg.push(g);
    }
    const bm = new THREE.Mesh(mergeGeos(bg), new THREE.MeshStandardMaterial({ map: bt, roughness: 0.7 }));
    bm.name = 'toyBlocks'; shadows(bm, false, true); scene.add(bm);
    // crayons (vertex colors, one draw call)
    const kidTop = O.kidTable ? (this._downHit([O.kidTable], -1.85, 0.32, 1.2) ?? 0.551) : 0.551;
    const cray = [
      [-1.83, kidTop, 0.33, 0.3, '#c8352a'], [-1.81, kidTop, 0.37, 1.9, '#2f5fb3'], [-1.86, kidTop, 0.4, 0.8, '#3f9a3c'],
      [-1.47, rugTop, 0.5, 2.6, '#f2c624'], [-1.42, rugTop, 0.42, 0.2, '#7d4ab0'], [-1.2, rugTop, 0.8, 1.2, '#1c1a1d'],
      [-2.12, kidTop, 0.08, 0.1, '#ec8a24'],
    ];
    const cg = [], cc = [];
    for (const [x, y, z, ry, hex] of cray) {
      const body = new THREE.CylinderGeometry(0.0046, 0.0046, 0.072, 8).translate(0, 0, 0);
      const tip = new THREE.ConeGeometry(0.0046, 0.013, 8).translate(0, 0.0425, 0);
      const wrap = new THREE.CylinderGeometry(0.0049, 0.0049, 0.05, 8).translate(0, -0.008, 0);
      for (const g of [body, tip, wrap]) { g.rotateZ(Math.PI / 2).rotateY(ry).translate(x, y + 0.0049, z); cg.push(g); }
      const c = col(hex);
      cc.push(c, c, c.clone().lerp(new THREE.Color(0xffffff), 0.12).multiplyScalar(0.8));
    }
    const cm = new THREE.Mesh(mergeGeos(cg, cc), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.5 }));
    cm.name = 'crayons'; shadows(cm, false, true); scene.add(cm);
    // crayon box on the kid table
    if (O.kidTable) {
      const topM = new THREE.MeshStandardMaterial({ map: PT.crayonBoxTexture(), roughness: 0.8 });
      const cbg = new THREE.BoxGeometry(0.095, 0.02, 0.125);
      const uv = cbg.attributes.uv;
      for (let i = 0; i < uv.count; i++) if (i < 8 || i >= 12) uv.setXY(i, 0.02 + uv.getX(i) * 0.3, 0.3 + uv.getY(i) * 0.1); // sides: plain green
      const cb = new THREE.Mesh(cbg, topM);
      cb.position.set(-2.16, kidTop + 0.0101, 0.36); cb.rotation.y = 1.3; cb.name = 'crayonBox';
      shadows(cb, false, true); scene.add(cb);
    }
    // red rubber ball under the kid table
    const ballTex = PT.painted(128, 64, (g, w, h) => { g.fillStyle = '#b8261c'; g.fillRect(0, 0, w, h); g.fillStyle = '#f0c63a'; g.fillRect(0, h * 0.44, w, h * 0.12); g.fillStyle = '#2f5fb3'; g.beginPath(); g.arc(w * 0.25, h * 0.25, 9, 0, Math.PI * 2); g.fill(); g.beginPath(); g.arc(w * 0.75, h * 0.75, 9, 0, Math.PI * 2); g.fill(); }, 77);
    const ball = new THREE.Mesh(new THREE.SphereGeometry(0.075, 24, 16), new THREE.MeshStandardMaterial({ map: ballTex, roughness: 0.42 }));
    ball.position.set(-2.24, rugTop + 0.075, -0.02); ball.rotation.set(0.4, 1.1, 0.2); ball.name = 'ball';
    shadows(ball, true, true); scene.add(ball);
    // toy car on the road rug
    const carParts = [
      new RoundedBoxGeometry(0.11, 0.032, 0.05, 2, 0.008).translate(0, 0.027, 0),
      new RoundedBoxGeometry(0.06, 0.026, 0.044, 2, 0.008).translate(-0.008, 0.05, 0),
    ];
    const carCols = [col('#2f6fb8'), col('#2f6fb8')];
    for (const [x, z] of [[-0.035, 0.024], [0.035, 0.024], [-0.035, -0.024], [0.035, -0.024]]) {
      carParts.push(new THREE.CylinderGeometry(0.012, 0.012, 0.009, 14).rotateX(Math.PI / 2).translate(x, 0.012, z));
      carCols.push(col('#111111'));
    }
    carParts.push(new THREE.BoxGeometry(0.004, 0.018, 0.04).translate(0.022, 0.05, 0)); carCols.push(col('#9fb6c8'));
    const car = new THREE.Mesh(mergeGeos(carParts, carCols), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.35, metalness: 0.1 }));
    car.position.set(-1.62, rugTop, 0.98); car.rotation.y = -0.7; car.name = 'toyCar';
    shadows(car, false, true); scene.add(car);
    // a drawing that fell on the floor
    if (this._drawTex?.mer) {
      const fl = new THREE.Mesh(this._paperGeo(0.297, 0.21, { curl: 0.006 }), new THREE.MeshStandardMaterial({ map: this._drawTex.mer, roughness: 0.92, side: THREE.DoubleSide }));
      fl.position.set(-0.98, rugTop + 0.0005, 1.05); fl.rotation.y = 0.5; fl.name = 'floorDrawing'; fl.receiveShadow = true;
      scene.add(fl);
    }
  }

  _buildNook() {
    const { scene, assets } = this.game;
    // (the laundry basket, stool, broom, pull-chain socket… are batch-2 models placed by ExtraProps: layout.EXTRA_PROPS)
    const fabricN = (() => { try { return assets.texture('textures/dirty_carpet/normal.jpg', { repeat: [3, 3] }); } catch (e) { return null; } })();
    // a red T-shirt dropped on the floor beside the basket, a sock near the doorway
    const shirtAlpha = PT.painted(128, 128, (g, w, h) => {
      g.fillStyle = '#000'; g.fillRect(0, 0, w, h);
      g.fillStyle = '#fff'; g.beginPath();
      g.moveTo(40, 8); g.quadraticCurveTo(64, 26, 88, 8); g.lineTo(124, 30); g.lineTo(108, 54); g.lineTo(96, 46);
      g.lineTo(98, 122); g.lineTo(30, 122); g.lineTo(32, 46); g.lineTo(20, 54); g.lineTo(4, 30); g.closePath(); g.fill();
    }, 78, { srgb: false });
    const shirtG = new THREE.PlaneGeometry(0.5, 0.5, 18, 18).rotateX(-Math.PI / 2);
    const sp = shirtG.attributes.position;
    for (let i = 0; i < sp.count; i++) {
      const x = sp.getX(i), z = sp.getZ(i);
      const folds = Math.abs(Math.sin(x * 23 + z * 9)) * 0.016 + Math.max(0, Math.sin(z * 17 - x * 6)) * 0.014 + 0.02 * Math.exp(-((x - 0.08) ** 2 + (z + 0.05) ** 2) * 40);
      sp.setY(i, 0.005 + folds);
    }
    shirtG.computeVertexNormals();
    const shirt = new THREE.Mesh(shirtG, new THREE.MeshStandardMaterial({ color: 0x9c2a24, roughness: 1, alphaMap: shirtAlpha, alphaTest: 0.5, side: THREE.DoubleSide, normalMap: fabricN, normalScale: new THREE.Vector2(0.5, 0.5) }));
    shirt.position.set(1.12, 0, -3.4); shirt.rotation.y = 2.4; shirt.name = 'shirt'; // clear of the stool / basket
    shadows(shirt, false, true); scene.add(shirt);
    const sock = new THREE.Mesh(
      new THREE.TubeGeometry(new THREE.CatmullRomCurve3([new THREE.Vector3(0, 0.014, 0), new THREE.Vector3(0.09, 0.016, 0.02), new THREE.Vector3(0.16, 0.014, -0.01), new THREE.Vector3(0.2, 0.02, -0.06)]), 16, 0.014, 8, false),
      new THREE.MeshStandardMaterial({ color: 0xd9d4c8, roughness: 1 }),
    );
    sock.position.set(1.72, 0, -2.55); sock.rotation.y = 0.9; sock.name = 'sock';
    shadows(sock, false, true); scene.add(sock);
    // shelf unit: paint cans + folded towels on its boards
    const shelf = this.objects.alcoveShelf;
    if (shelf) {
      shelf.updateWorldMatrix(true, true);
      const sb = this._box.setFromObject(shelf);
      const cx = (sb.min.x + sb.max.x) / 2, cz = (sb.min.z + sb.max.z) / 2;
      const boards = [];
      let y = sb.max.y + 0.05;
      for (let i = 0; i < 8; i++) {
        const h = this._downHit([shelf], cx, cz - 0.1, y);
        if (h === null) break;
        boards.push(h); y = h - 0.03;
        if (h < 0.05) break;
      }
      boards.sort((a, b) => a - b);
      const lowBoard = boards.find((b) => b > 0.03 && b < 0.6) ?? boards[0] ?? 0.02;
      const midBoard = boards.find((b) => b > 0.7 && b < 1.4) ?? null;
      const labels = PT.paintLabelTexture();
      const canGeos = [], lidGeos = [];
      const cans = [[cz - 0.32, 0], [cz - 0.1, 1], [cz + 0.22, 2]];
      for (const [z, k] of cans) {
        const body = new THREE.CylinderGeometry(0.085, 0.085, 0.19, 24, 1, true);
        remapUV(body, k / 3, 0, (k + 1) / 3, 1);
        body.translate(cx - 0.005, lowBoard + 0.095, z);
        canGeos.push(body);
        lidGeos.push(new THREE.CylinderGeometry(0.086, 0.086, 0.01, 24).translate(cx - 0.005, lowBoard + 0.195, z));
        lidGeos.push(new THREE.TorusGeometry(0.06, 0.003, 4, 20, Math.PI).rotateX(-0.4).translate(cx - 0.005, lowBoard + 0.2, z));
      }
      const canMesh = new THREE.Mesh(mergeGeos(canGeos), new THREE.MeshStandardMaterial({ map: labels, roughness: 0.6, metalness: 0.2 }));
      const lidMesh = new THREE.Mesh(mergeGeos(lidGeos), new THREE.MeshStandardMaterial({ color: 0x9a9890, roughness: 0.35, metalness: 1 }));
      shadows(canMesh, true, true); shadows(lidMesh, true, true);
      scene.add(canMesh, lidMesh);
      if (midBoard !== null) {
        const tg = [], tc = [];
        const towelCols = ['#7aa0b8', '#e6dccb', '#c58a7a', '#e6dccb'];
        let ty = midBoard;
        for (let k = 0; k < 4; k++) {
          const th = 0.035 + (k % 2) * 0.01;
          tg.push(new RoundedBoxGeometry(0.22, th, 0.3, 2, 0.012).rotateY((k - 1.5) * 0.04).translate(cx - 0.01, ty + th / 2, cz - 0.15));
          tc.push(col(towelCols[k])); ty += th;
        }
        const towels = new THREE.Mesh(mergeGeos(tg, tc), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1, normalMap: fabricN, normalScale: new THREE.Vector2(0.8, 0.8) }));
        shadows(towels, true, true); scene.add(towels);
      }
    }
  }

  _buildDecals() {
    const atlas = PT.stainAtlas();
    const mk = (cell, w, h) => {
      const g = remapUV(new THREE.PlaneGeometry(w, h), cell / 4, 0, (cell + 1) / 4, 1);
      const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ map: atlas, transparent: true, depthWrite: false, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -3 }));
      m.receiveShadow = true; m.castShadow = false;
      return m;
    };
    this._mount(mk(0, 0.9, 0.75), 3.0, 2.5, -1.85, 'U', { gap: 0.001, tol: 0.3 });            // ceiling water stain
    this._mount(mk(2, 0.55, 0.3), 3.5, 0.95, -1.05, 'E', { gap: 0.001 });                     // chair-back scuffs
    this._mount(mk(2, 0.5, 0.28), 3.5, 0.95, 1.4, 'E', { gap: 0.001, rotZ: 0.1 });
    this._mount(mk(3, 0.2, 0.2), -3.5, 1.22, 2.08, 'W', { gap: 0.0008 });                     // finger marks around the switch
    this._mount(mk(1, 1.1, 0.5), 0.2, 0.25, -3.7, 'W', { gap: 0.001 });                       // grime in the nook
    this._mount(mk(2, 0.45, 0.18), -2.5, 0.1, 1.32, 'W', { gap: 0.001 });                    // shoe scuffs at the stairs
  }

  // ------------------------------------------------------------------------------------------- physics registration

  _registerColliders() {
    const W = this.world, O = this.objects;
    const list = ['sofa', 'coffeeTable', 'endTable', 'dresser', 'grandfather', 'shelves', 'console', 'chairA', 'chairB',
      'rockingChair', 'kidTable', 'kidChair', 'alcoveCabinet', 'alcoveShelf', 'boxA', 'boxB'];
    this.colliders = {};
    for (const k of list) {
      const o = O[k];
      if (!o) continue;
      try { this.colliders[k] = W.addColliderFromObject(o, k, 0); } catch (e) { console.warn('[props] collider', k, e); }
    }
    // the stacked box B rests on A: merge their vertical spans
    if (this.colliders.boxA && this.colliders.boxB) this.colliders.boxB.minY = 0;
  }

  _registerOccluders() {
    const O = this.objects, W = this.world;
    const add = (obj, ...box) => { if (!obj) return; const m = this._proxy(obj, ...box, 'occluder'); W.addOccluder(m); };
    add(O.sofa, -1.3, 0.08, -0.4, 1.3, 0.4, 0.42);
    add(O.sofa, -1.25, 0.4, -0.44, 1.25, 0.92, -0.22);
    add(O.dresser, -0.57, 0.06, -0.27, 0.57, 1.18, 0.17);
    add(O.grandfather, -0.27, 0.03, -0.17, 0.27, 2.1, 0.09);
    add(O.shelves, -0.24, 0.02, 0.01, 0.24, 1.1, 0.12);
    add(O.console, -0.74, 0.84, -0.31, 0.74, 0.92, 0.22);
    add(O.alcoveCabinet, -0.57, 0.05, -0.27, 0.57, 1.14, -0.1);
    add(O.alcoveShelf, -0.48, 0.03, 0.0, 0.48, 2.04, 0.05);
    add(O.boxA, -0.17, 0.0, -0.2, 0.17, 0.32, 0.27);
    add(O.boxB, -0.17, 0.0, -0.2, 0.17, 0.32, 0.27);
  }

  /** Every handle / item / clue id of the contract must exist even if a model failed to load. */
  _ensureContract() {
    const W = this.world;
    const noop = (id) => {
      const o = new THREE.Object3D(); o.name = id;
      return { id, object: o, isOpen: false, contents: new THREE.Group(), open: async () => {}, close: async () => {}, toggle: async () => {}, worldPosition: (t = new THREE.Vector3()) => t.set(0, 0, 0) };
    };
    for (const id of ['dresser.drawerTop', 'dresser.drawerMid', 'dresser.drawerBottom', 'endTable.drawer', 'alcoveCabinet.drawer_01', 'alcoveCabinet.drawer_02', 'alcoveCabinet.door_01', 'alcoveCabinet.door_02', 'powerBox.door', 'powerBox.lever', 'lockedBox.lid', 'lockedBox.lock']) {
      if (!W.handles[id]) { console.warn('[props] missing handle', id); W.handles[id] = noop(id); }
    }
    const lv = W.handles['powerBox.lever'];
    if (lv && !lv.setOn) { lv.isOn = true; lv.setOn = async (on) => { lv.isOn = !!on; if (W.power !== !!on) W.setPower(!!on); }; }
    for (const id of ['flashlight', 'battery1', 'battery2', 'key', 'note1', 'note2', 'note3']) {
      if (!W.items[id]) { const o = new THREE.Object3D(); o.name = id; this.game.scene.add(o); W.items[id] = o; }
    }
    if (!W.tv) W.tv = { object: new THREE.Object3D(), isOn: false, setOn() { return false; }, setDigit() {}, screenPosition: new THREE.Vector3(-0.55, 1.47, -2.38) };
    if (!W.clues || !W.clues.duck) W.clues = { duck: this.objects.duck || new THREE.Object3D(), horse: this.objects.horse || new THREE.Object3D(), clock: this.objects.grandfather || new THREE.Object3D(), tv: this.objects.tv || new THREE.Object3D() };
  }

  _wireEvents() {
    const ev = this.game.events;
    ev.on('game:state', ({ state }) => { if (state === 'playing') this._startLoops(); });
    ev.on('quality:changed', ({ preset }) => { if (preset) this._preset = preset; });
    if (this.game.state === 'playing') this._startLoops();
  }

  _startLoops() {
    if (this._loopsStarted) return;
    this._loopsStarted = true;
    const ac = this.objects.alarmClock;
    if (ac) {
      try { this._tickLoop = this.game.audio?.loop?.('clock_tick', { position: ac.getWorldPosition(new THREE.Vector3()), volume: 0.45 }) || null; } catch (e) { /* ignore */ }
    }
  }

  // =========================================================================================== runtime

  setPower(on) {
    on = !!on;
    this._power = on;
    if (!on && this.tv?.isOn) this._tvSetOn(false);
    const lv = this._lever;
    if (lv && !lv.anim.active && lv.handle.isOn !== on) {
      lv.handle.isOn = on; lv.handle.isOpen = on;
      lv.anim.set(on ? 1 : 0); // tripped / reset silently (the panel is far away)
    }
  }

  update(dt) {
    this._time += dt;
    for (let i = 0; i < this._anims.length; i++) { const a = this._anims[i]; if (a.active) a.update(dt); }
    // ceiling fan
    if (this._fanBlades) {
      const target = this._power ? 2.4 : 0;
      const rate = this._power ? 0.45 : 0.16;
      this._fanSpeed += (target - this._fanSpeed) * Math.min(1, dt * rate);
      if (this._fanSpeed < 0.004 && !this._power) this._fanSpeed = 0;
      this._fanBlades.rotation.y += this._fanSpeed * dt;
    }
    this._updateAlarmClock(dt);
    this._updateTV(dt);
    this._updateRocking(dt);
    // padlock wheels (smooth roll to the selected digits)
    const lock = this._lock;
    if (lock?.userData.animating) {
      const ud = lock.userData;
      let moving = false;
      for (let i = 0; i < 4; i++) {
        const w = ud.wheels[i], target = this._wheelAngle(ud.digits[i]);
        const diff = target - w.rotation.x;
        if (Math.abs(diff) > 0.002) { w.rotation.x += diff * Math.min(1, dt * 14); moving = true; } else w.rotation.x = target;
      }
      if (!moving) ud.animating = false;
    }
    // smoke detector LED: brief blink every ~40 s
    if (this._ledMat) {
      this._ledT -= dt;
      if (this._ledT <= 0) { this._ledMat.emissiveIntensity = 6; if (this._ledT < -0.09) { this._ledMat.emissiveIntensity = 0; this._ledT = 38 + Math.random() * 8; } }
    }
  }

  reset(kind) {
    if (kind === 'caught') {
      this._stopRocking();
    } else if (kind === 'new') {
      this._stopRocking();
      for (const h of Object.values(this.world.handles)) {
        if (h.id?.startsWith('door.')) continue;
        if (h.isOpen && h.id !== 'powerBox.lever') h.close?.();
      }
    }
  }
}
