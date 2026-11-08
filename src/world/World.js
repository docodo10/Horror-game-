import * as THREE from 'three';
import * as L from '../config/layout.js';
import { Architecture } from './Architecture.js';
import { Lighting } from './Lighting.js';
import { Props } from './Props.js';

/**
 * World = level container. Composes Architecture (shell, stairs, doors, window, closet, alcove),
 * Props (furniture, animated handles, items, clues, TV) and Lighting (lights, power, env baking).
 *
 * Shared data other modules rely on:
 *  - colliders:  Array<Collider>  axis-aligned boxes that block the player & entity
 *                Collider = { minX, minY, minZ, maxX, maxY, maxZ, tag: string, enabled: boolean }
 *  - occluders:  Array<THREE.Mesh> meshes that block sight (walls, doors, big furniture) — used for LOS + interaction rays
 *  - handles:    { [id]: Handle } animated openables (drawers, doors, lids, breaker...) — see ARCHITECTURE.md
 *  - items:      { [id]: THREE.Object3D } pickups (flashlight, battery1, battery2, key, note1, note2, note3)
 *  - clues:      { duck, horse, clock, tv } Object3D roots of the clue objects
 *  - tv:         TV controller { object, isOn, setOn(on), setDigit(d), screenPosition: Vector3 }
 *  - hideSpots:  Array<HideSpot>
 *  - nav:        navigation graph (see path())
 */
export class World {
  constructor(game) {
    this.game = game;
    this.scene = game.scene;
    this.layout = L;
    this.colliders = [];
    this.occluders = [];
    this.handles = {};
    this.items = {};
    this.clues = {};
    this.tv = null;
    this.hideSpots = [];
    this.power = true;

    this.architecture = new Architecture(game, this);
    this.props = new Props(game, this);
    this.lighting = new Lighting(game, this);

    this._ray = new THREE.Raycaster();
    this._buildNav();
  }

  async init() {
    await this.architecture.build();
    await this.props.build();
    await this.lighting.build();
    await this.lighting.bakeEnvironment();
    this.scene.updateMatrixWorld(true);
  }

  update(dt) {
    this.architecture.update?.(dt);
    this.props.update?.(dt);
    this.lighting.update?.(dt);
  }

  /** kind: 'caught' (player respawn after being caught) | 'new' */
  reset(kind) {
    this.architecture.reset?.(kind);
    this.props.reset?.(kind);
    this.lighting.reset?.(kind);
  }

  /** Mains power (ceiling light, fan, TV availability). */
  setPower(on) {
    this.power = on;
    this.lighting.setPower(on);
    this.props.setPower?.(on);
    this.game.events.emit('power', { on });
  }

  // ---------------------------------------------------------------- geometry helpers

  groundHeightAt(x, z, prevY) { return L.groundHeightAt(x, z, prevY); }

  /** Register a blocking box. Returns the collider (toggle .enabled for doors). */
  addCollider(min, max, tag = 'wall') {
    const c = { minX: min[0], minY: min[1], minZ: min[2], maxX: max[0], maxY: max[1], maxZ: max[2], tag, enabled: true };
    this.colliders.push(c);
    return c;
  }

  /** Collider from the world-space bounding box of an object (after it is placed & added to the scene). */
  addColliderFromObject(obj, tag = 'prop', pad = 0) {
    obj.updateWorldMatrix(true, true);
    const b = new THREE.Box3().setFromObject(obj);
    return this.addCollider([b.min.x - pad, b.min.y, b.min.z - pad], [b.max.x + pad, b.max.y, b.max.z + pad], tag);
  }

  addOccluder(mesh) { if (mesh && !this.occluders.includes(mesh)) this.occluders.push(mesh); }

  /**
   * Move a vertical circle (radius r) from pos by (dx, dz) with sliding against colliders.
   * Only colliders overlapping the vertical span [yMin, yMax] are considered.
   * Mutates and returns pos (THREE.Vector3; y untouched). Returns { pos, hit: boolean, hitTag }.
   */
  moveCircle(pos, dx, dz, r, yMin, yMax) {
    let hit = false, hitTag = null;
    const steps = Math.max(1, Math.ceil(Math.hypot(dx, dz) / (r * 0.5)));
    const sx = dx / steps, sz = dz / steps;
    for (let s = 0; s < steps; s++) {
      pos.x += sx; pos.z += sz;
      for (let iter = 0; iter < 3; iter++) {
        let any = false;
        for (const c of this.colliders) {
          if (!c.enabled || c.maxY <= yMin || c.minY >= yMax) continue;
          const cx = Math.max(c.minX, Math.min(pos.x, c.maxX));
          const cz = Math.max(c.minZ, Math.min(pos.z, c.maxZ));
          let ox = pos.x - cx, oz = pos.z - cz;
          const d2 = ox * ox + oz * oz;
          if (d2 >= r * r) continue;
          any = true; hit = true; hitTag = c.tag;
          if (d2 > 1e-10) {
            const d = Math.sqrt(d2), push = r - d;
            pos.x += (ox / d) * push; pos.z += (oz / d) * push;
          } else {
            // center inside the box: push out along the smallest axis
            const pl = pos.x - c.minX + r, pr = c.maxX - pos.x + r, pb = pos.z - c.minZ + r, pf = c.maxZ - pos.z + r;
            const m = Math.min(pl, pr, pb, pf);
            if (m === pl) pos.x = c.minX - r; else if (m === pr) pos.x = c.maxX + r;
            else if (m === pb) pos.z = c.minZ - r; else pos.z = c.maxZ + r;
          }
        }
        if (!any) break;
      }
    }
    return { pos, hit, hitTag };
  }

  /** True if the straight 2D segment (inflated by radius r) at height span [yMin,yMax] crosses an enabled collider. */
  segmentBlocked(ax, az, bx, bz, r, yMin, yMax) {
    const len = Math.hypot(bx - ax, bz - az);
    const n = Math.max(2, Math.ceil(len / 0.1));
    for (let i = 0; i <= n; i++) {
      const t = i / n, x = ax + (bx - ax) * t, z = az + (bz - az) * t;
      for (const c of this.colliders) {
        if (!c.enabled || c.maxY <= yMin || c.minY >= yMax) continue;
        if (x > c.minX - r && x < c.maxX + r && z > c.minZ - r && z < c.maxZ + r) return true;
      }
    }
    return false;
  }

  /** Line of sight between two world points against occluder meshes. Returns true if something blocks it. */
  lineBlocked(from, to) {
    const dir = new THREE.Vector3().subVectors(to, from);
    const dist = dir.length();
    if (dist < 1e-4) return false;
    this._ray.set(from, dir.multiplyScalar(1 / dist));
    this._ray.near = 0; this._ray.far = dist - 0.05;
    const hits = this._ray.intersectObjects(this.occluders.filter((m) => m.visible !== false), true);
    return hits.length > 0;
  }

  // ---------------------------------------------------------------- navigation

  _buildNav() {
    const nodes = {};
    for (const [id, n] of Object.entries(L.NAV_NODES)) {
      const y = n.upper ? L.UPPER.floorY : L.groundHeightAt(n.x, n.z);
      nodes[id] = { id, pos: new THREE.Vector3(n.x, y, n.z), links: [] };
    }
    for (const [a, b] of L.NAV_LINKS) {
      if (!nodes[a] || !nodes[b]) { console.warn('bad nav link', a, b); continue; }
      nodes[a].links.push(b); nodes[b].links.push(a);
    }
    this.nav = { nodes };
  }

  /** Nearest nav node id to a world position (prefers same floor level). */
  nearestNode(pos) {
    let best = null, bd = Infinity;
    for (const n of Object.values(this.nav.nodes)) {
      const dy = Math.abs(n.pos.y - pos.y);
      const d = Math.hypot(n.pos.x - pos.x, n.pos.z - pos.z) + dy * 3;
      if (d < bd) { bd = d; best = n.id; }
    }
    return best;
  }

  /** A* path between two world positions. Returns an array of Vector3 waypoints (ends with `to`). */
  path(from, to) {
    const nodes = this.nav.nodes;
    const s = this.nearestNode(from), g = this.nearestNode(to);
    const open = new Set([s]), came = {}, gs = { [s]: 0 }, fs = { [s]: nodes[s].pos.distanceTo(nodes[g].pos) };
    while (open.size) {
      let cur = null, bf = Infinity;
      for (const id of open) if (fs[id] < bf) { bf = fs[id]; cur = id; }
      if (cur === g) break;
      open.delete(cur);
      for (const nb of nodes[cur].links) {
        const t = gs[cur] + nodes[cur].pos.distanceTo(nodes[nb].pos);
        if (t < (gs[nb] ?? Infinity)) {
          came[nb] = cur; gs[nb] = t; fs[nb] = t + nodes[nb].pos.distanceTo(nodes[g].pos); open.add(nb);
        }
      }
    }
    const ids = [g];
    while (ids[0] !== s && came[ids[0]]) ids.unshift(came[ids[0]]);
    const pts = ids.map((id) => nodes[id].pos.clone());
    pts.push(to.clone());
    return pts;
  }

  /** Random nav node position near a point (for searching), optionally excluding upper-floor nodes. */
  randomNodeNear(pos, radius = 3, { lowerOnly = true } = {}) {
    const cands = Object.values(this.nav.nodes).filter((n) =>
      (!lowerOnly || n.pos.y < 1.0) && Math.hypot(n.pos.x - pos.x, n.pos.z - pos.z) <= radius);
    const list = cands.length ? cands : Object.values(this.nav.nodes).filter((n) => n.pos.y < 1.0);
    return list[Math.floor(Math.random() * list.length)].pos.clone();
  }
}
