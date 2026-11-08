import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as L from '../config/layout.js';
import * as PT from './ProcTextures.js';

/**
 * Details — realism detail pass (runs after Props + ExtraProps, before Lighting; see assets/NEW_ASSETS.md "Batch 3").
 *
 *  - Decals (layout.DECALS): batch-3 leak / damp / rust / mould / water-ring / dirt / grime / scuff / hand-smudge sets
 *    + procedural crayon scribbles, alpha-blended quads with polygonOffset. Quads are merged into ONE mesh per
 *    (texture, lighting zone); per-decal tint and opacity live in an RGBA vertex colour. Zones match Architecture's
 *    env-map zones (nook 0.45, closet 0.12, stairwell 0.85, hall 0.3) so a decal never glows brighter than its wall.
 *  - Carpet wear: one floor-wide overlay (canvas) with the trampled lanes stairs → sofa → nook doorway, dark blotches
 *    and a few spills, carpet normal map on a second UV set so the pile keeps its relief under the stains.
 *  - Laundry nook → storage room: concrete walls + a dirty tiled wainscot, two steel shelving units loaded with boxes,
 *    jerrycan, first-aid box, milk crate, the laundry basket (layout moves), folded ladder, and a fluorescent batten
 *    with ONE non-shadow SpotLight (created at build, intensity-driven) that is on only with mains power, stutters like a
 *    dying tube at power-up, glitches now and then (more with La Gardienne close) and buzzes (positional light_buzz).
 *  - Upstairs hallway (win view): herringbone parquet, decrepit wallpaper with a printed damask, peeling painted
 *    wainscot + chair rail, crackled plaster ceiling, exposed brick behind fallen plaster on the end wall, hanging
 *    industrial lamp (Lighting's hallway light is moved to its bulb) and an old lantern on the floor.
 *  - Floor clutter (merged, 1 draw call per material): children's drawings + crumpled paper, crayons, wooden blocks, a
 *    pull-along toy telephone, a stray sock, the boombox power cord into a knee-wall outlet, dust bunnies.
 *  - Fixes asked by other modules: the broken bulb hangs upside down in the pull-chain socket; boxes on the shelf.
 *
 * Public API (contract): constructor(game, world); async build(); update(dt); reset(kind); setPower(on)
 * Extra: .objects { [DETAIL_PROPS key]: Object3D }, .tube { light, level, mode }, .decalMeshes (Mesh[])
 */

const PI = Math.PI, TAU = PI * 2;
const R = L.ROOM, AL = L.ALCOVE, HALL = L.UPPER_HALL, UP = L.UPPER;
const ZN = R.minZ - 0.15;                 // nook S face / hall S wall = back face of the 0.15 m north partition
const HY0 = UP.floorY, HY1 = UP.ceilingY; // hallway floor / ceiling
const HWIN = { x0: HALL.minX + 0.25, x1: HALL.minX + 0.9, y0: HY0 + 0.95, y1: HY0 + 2.0 }; // hall end-wall window hole

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };

function rng(seed) {
  let s = (seed >>> 0) || 1;
  return () => {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash2(x, y) { const h = Math.sin(x * 127.1 + y * 311.7) * 43758.5453; return h - Math.floor(h); }
function vnoise(x, y) {
  const xi = Math.floor(x), yi = Math.floor(y); let u = x - xi, v = y - yi;
  u = u * u * (3 - 2 * u); v = v * v * (3 - 2 * v);
  const a = hash2(xi, yi), b = hash2(xi + 1, yi), c = hash2(xi, yi + 1), d = hash2(xi + 1, yi + 1);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function fbm(x, y, oct = 4) {
  let s = 0, a = 0.5, n = 0;
  for (let i = 0; i < oct; i++) { s += a * vnoise(x, y); n += a; x *= 2.03; y *= 2.03; a *= 0.5; }
  return s / n;
}
function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function canvasTex(c, { srgb = true, repeat = null, aniso = 4 } = {}) {
  const t = new THREE.CanvasTexture(c);
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat[0], repeat[1]); }
  t.anisotropy = aniso;
  return t;
}
const linColor = (hex) => new THREE.Color(hex); // sRGB hex → linear working space (ColorManagement)

// ------------------------------------------------------------------------------------------------ geometry helpers

/** Rotation basis for a surface quad: z = normal, y = texture up (projected), x = y × z. */
function basis(normal, up, out = new THREE.Matrix4()) {
  const z = new THREE.Vector3(...normal).normalize();
  const u = new THREE.Vector3(...up);
  const x = new THREE.Vector3().crossVectors(u, z).normalize();
  const y = new THREE.Vector3().crossVectors(z, x);
  return out.makeBasis(x, y, z);
}

/** Make a geometry mergeable with the others of a batch: indexed, position/normal/uv/color(itemSize) only. */
function prep(g, rgb = [1, 1, 1], alpha = null) {
  if (!g.index) {
    const n = g.attributes.position.count, idx = new Array(n);
    for (let i = 0; i < n; i++) idx[i] = i;
    g.setIndex(idx);
  }
  for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv', 'uv1', 'color'].includes(k)) g.deleteAttribute(k);
  if (!g.attributes.normal) g.computeVertexNormals();
  if (!g.attributes.uv) g.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
  if (!g.attributes.color) {
    const n = g.attributes.position.count, k = alpha === null ? 3 : 4, a = new Float32Array(n * k);
    for (let i = 0; i < n; i++) { a[i * k] = rgb[0]; a[i * k + 1] = rgb[1]; a[i * k + 2] = rgb[2]; if (k === 4) a[i * k + 3] = alpha; }
    g.setAttribute('color', new THREE.Float32BufferAttribute(a, k));
  }
  return g;
}

/**
 * Planar patch o + U*s + V*t, s in [0,w], t in [0,h] (normal = U × V), nu x nv cells.
 * uv = world projection (p·U, p·V) (textures carry their repeat = 1 / tile); uv1 = 0..1 over the patch when asked
 * (uv1Box = [s0, s1, t0, t1] maps a sub-rectangle of a bigger 0..1 frame). color(x,y,z) -> number | [r,g,b].
 */
function patch(o, U, V, w, h, { nu = 1, nv = 1, color = null, uv1Box = null } = {}) {
  const nx = U[1] * V[2] - U[2] * V[1], ny = U[2] * V[0] - U[0] * V[2], nz = U[0] * V[1] - U[1] * V[0];
  const pos = [], nor = [], uv = [], uv1 = [], col = [], idx = [];
  for (let j = 0; j <= nv; j++) {
    for (let i = 0; i <= nu; i++) {
      const s = (w * i) / nu, t = (h * j) / nv;
      const x = o[0] + U[0] * s + V[0] * t, y = o[1] + U[1] * s + V[1] * t, z = o[2] + U[2] * s + V[2] * t;
      pos.push(x, y, z); nor.push(nx, ny, nz);
      uv.push(x * U[0] + y * U[1] + z * U[2], x * V[0] + y * V[1] + z * V[2]);
      if (uv1Box) uv1.push(uv1Box[0] + (uv1Box[1] - uv1Box[0]) * (i / nu), uv1Box[2] + (uv1Box[3] - uv1Box[2]) * (j / nv));
      const c = typeof color === 'function' ? color(x, y, z) : (color ?? 1);
      if (typeof c === 'number') col.push(c, c, c); else col.push(c[0], c[1], c[2]);
    }
  }
  for (let j = 0; j < nv; j++) for (let i = 0; i < nu; i++) {
    const a = j * (nu + 1) + i, b = a + 1, c = a + nu + 2, d = a + nu + 1;
    idx.push(a, b, c, a, c, d);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  if (uv1Box) g.setAttribute('uv1', new THREE.Float32BufferAttribute(uv1, 2));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}

/** Axis-aligned box with world-projected UVs (scaled by uvScale) and a constant colour. */
function boxGeo(a, b, { uvScale = 1, color = 1 } = {}) {
  const g = new THREE.BoxGeometry(b[0] - a[0], b[1] - a[1], b[2] - a[2]);
  g.translate((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2);
  const p = g.attributes.position, n = g.attributes.normal, uv = g.attributes.uv;
  for (let i = 0; i < p.count; i++) {
    const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i));
    const x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    if (ax > 0.5) uv.setXY(i, z * uvScale, y * uvScale); else if (ay > 0.5) uv.setXY(i, x * uvScale, z * uvScale); else uv.setXY(i, x * uvScale, y * uvScale);
  }
  return prep(g, typeof color === 'number' ? [color, color, color] : color);
}

/** Merge static child meshes of a placed model into one mesh per material (keeps the root transform). */
function mergeStatic(root) {
  root.updateWorldMatrix(true, true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const meshes = [];
  root.traverse((o) => { if (o.isMesh && !Array.isArray(o.material) && !o.isSkinnedMesh) meshes.push(o); });
  if (meshes.length < 2) return;
  const byMat = new Map(), m4 = new THREE.Matrix4();
  for (const m of meshes) {
    const g = m.geometry.clone().applyMatrix4(m4.multiplyMatrices(inv, m.matrixWorld));
    if (!byMat.has(m.material)) byMat.set(m.material, []);
    byMat.get(m.material).push(g);
  }
  // only merge when every geometry of a material has the same attribute set
  for (const [mat, geos] of byMat) {
    const keys = (g) => Object.keys(g.attributes).sort().join(',') + (g.index ? '|i' : '|n');
    if (geos.length < 2 || !geos.every((g) => keys(g) === keys(geos[0]))) { byMat.delete(mat); geos.forEach((g) => g.dispose()); }
  }
  if (!byMat.size) return;
  for (const m of meshes) if (byMat.has(m.material)) m.parent?.remove(m);
  for (const [mat, geos] of byMat) {
    const g = mergeGeometries(geos, false);
    geos.forEach((x) => x.dispose());
    if (!g) continue;
    const mesh = new THREE.Mesh(g, mat);
    mesh.name = root.name + '_merged';
    root.add(mesh);
  }
}

// ------------------------------------------------------------------------------------------------ canvas painters

/** Waxy crayon stroke (several jittered passes), like the children's drawings of ProcTextures. */
function crayon(g, Rn, pts, color, width = 3, passes = 3, alpha = 0.9) {
  g.save();
  g.strokeStyle = color; g.lineCap = 'round'; g.lineJoin = 'round';
  for (let p = 0; p < passes; p++) {
    g.globalAlpha = Math.min(1, (0.6 + Rn() * 0.35) * alpha);
    g.lineWidth = width * (0.7 + Rn() * 0.55);
    const ox = (Rn() - 0.5) * width * 0.6, oy = (Rn() - 0.5) * width * 0.6;
    g.beginPath();
    for (let i = 0; i < pts.length; i += 2) {
      const x = pts[i] + ox + (Rn() - 0.5) * width * 0.5, y = pts[i + 1] + oy + (Rn() - 0.5) * width * 0.5;
      if (i === 0) g.moveTo(x, y); else g.lineTo(x, y);
    }
    g.stroke();
  }
  g.restore();
}

/** Wax skipping over the wall's orange-peel texture: punch random holes in the strokes. */
function waxTooth(g, x, y, w, h, Rn, amount = 0.5) {
  const img = g.getImageData(x, y, w, h), d = img.data;
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const k = (j * w + i) * 4;
      if (!d[k + 3]) continue;
      const n = vnoise(i * 0.45, j * 0.45) * 0.6 + Rn() * 0.4;
      d[k + 3] = Math.round(d[k + 3] * clamp01(1 - amount * smooth(0.35, 0.85, n)));
    }
  }
  g.putImageData(img, x, y);
}

// ------------------------------------------------------------------------------------------------ Details

export class Details {
  constructor(game, world) {
    this.game = game;
    this.world = world;
    this.objects = {};
    this.decalMeshes = [];
    this.tube = null;
    this._powerOn = world.power !== false;
    this._started = false;
    this._hallLightMoved = false;
    this._v = new THREE.Vector3();
  }

  async build() {
    const q = this.game.renderer?.quality || 'medium';
    this._low = q === 'low';
    this._aniso = Math.min(8, this.game.renderer?.maxAnisotropy || 4);
    const steps = [
      ['fixes', () => this._fixes()],
      ['props', () => this._placeProps()],
      ['nookShell', () => this._nookShell()],
      ['tube', () => this._buildTube()],
      ['hall', () => this._hallway()],
      ['decals', () => this._decals()],
      ['wallGrime', () => this._wallGrime()],
      ['carpet', () => this._carpetWear()],
      ['clutter', () => this._clutter()],
      ['papers', () => this._papers()],
      ['fabric', () => this._fabricAndDust()],
    ];
    for (const [name, fn] of steps) {
      try { await fn(); } catch (e) { console.warn(`[details] ${name} failed`, e); }
    }
    this.game.scene.updateMatrixWorld(true);
  }

  // ---------------------------------------------------------------------------------------------- fixes (other modules)

  _fixes() {
    const scene = this.game.scene;
    // the broken bulb: upside down, screwed into the pull-chain socket (socket base bottom at y = 2.449)
    const bulb = this.world.props?.objects?.bulb || scene.getObjectByName('bulb');
    if (bulb) {
      const s = L.EXTRA_PROPS.socket?.pos || L.PROPS.bulb.pos;
      bulb.rotation.set(PI, bulb.rotation.y, 0);
      bulb.position.set(s[0], 2.445, s[2]);
      bulb.updateMatrixWorld(true);
    }
  }

  /** Put obj on a horizontal surface at height y (bbox bottom), keeping x/z. */
  _seat(obj, y) {
    obj.updateWorldMatrix(true, true);
    const b = new THREE.Box3().setFromObject(obj, true);
    obj.position.y += y - b.min.y + 0.0005;
    obj.updateWorldMatrix(false, true);
  }

  // ---------------------------------------------------------------------------------------------- batch-3 props

  _placeProps() {
    const { assets, scene } = this.game;
    const hall = this.world.architecture?.hall || scene;
    const boards = L.STEEL_SHELF_BOARDS;
    for (const [key, p] of Object.entries(L.DETAIL_PROPS)) {
      let o;
      try { o = assets.instance(p.model, { uniqueMaterials: key === 'tubeLight' || key === 'hallLamp' || key === 'shelfW' }); }
      catch (e) { console.warn('[details]', e.message); continue; }
      o.name = 'detail_' + key;
      for (const [n, e] of Object.entries(p.nodeRot || {})) o.getObjectByName(n)?.rotation.set(e[0], e[1], e[2]);
      o.position.fromArray(p.pos);
      o.rotation.set(p.rotX || 0, p.rotY || 0, p.rotZ || 0, 'ZXY'); // yaw, then world-axis tilts (as ExtraProps)
      if (Array.isArray(p.scale)) o.scale.set(p.scale[0], p.scale[1], p.scale[2]); else o.scale.setScalar(p.scale || 1);
      (p.hall ? hall : scene).add(o);
      if (p.on !== undefined && p.board !== undefined) this._seat(o, boards[p.board]);
      const inHall = !!p.hall;
      o.traverse((m) => { if (m.isMesh) { m.castShadow = !inHall && key !== 'tubeLight'; m.receiveShadow = !inHall; } });
      this.objects[key] = o;
    }
    const O = this.objects;
    // shelves: dull the new-looking pine boards (one shared material for both units)
    if (O.shelfW) {
      O.shelfW.traverse((m) => { if (m.isMesh) { m.material.color.setRGB(0.72, 0.66, 0.58); m.material.envMapIntensity = 0.8; } });
      const mat = O.shelfW.getObjectByProperty('isMesh', true)?.material;
      if (mat && O.shelfN) O.shelfN.traverse((m) => { if (m.isMesh && m.material.name === mat.name) m.material = mat; });
    }
    // laundry basket + boxes A/B onto their boards (Props drops boxB onto boxA; ExtraProps places the basket by origin)
    const P = this.world.props?.objects || {};
    if (P.boxA) this._seat(P.boxA, boards[0]);
    if (P.boxB) this._seat(P.boxB, boards[1]);
    const basket = this.world.extras?.objects?.laundry;
    if (basket) this._seat(basket, boards[0]);
    // static scans: one draw call per material
    for (const k of ['shelfW', 'shelfN', 'medkit', 'ladder', 'shelfWcan', 'milkCrate', 'hallLantern']) if (O[k]) mergeStatic(O[k]);
    // colliders: shelf units (boxes on them are inside), folded ladder
    for (const k of ['shelfW', 'shelfN']) if (O[k]) this.world.addColliderFromObject(O[k], 'shelf', 0);
    if (O.ladder) { // exact vertex bounds (the tilted, folded ladder's node boxes give a far too big AABB)
      O.ladder.updateWorldMatrix(true, true);
      const b = new THREE.Box3().setFromObject(O.ladder, true);
      this.world.addCollider([b.min.x, 0, b.min.z], [b.max.x, b.max.y, b.max.z], 'ladder');
    }
    // identical static models baked together in world space: both shelf units = 1 draw call, the 3 boxes = 1
    this._bake(['shelfW', 'shelfN'], 'details_shelves');
    this._bake(['shelfNbox3', 'shelfNbox4', 'shelfNbox5'], 'details_boxes');
    // hallway lamp: glowing bulb (emissive factor 1 in the file), lantern glass
    if (O.hallLamp) {
      O.hallLamp.traverse((m) => {
        if (!m.isMesh) return;
        if (m.material.emissiveMap) { m.material.emissive.set(0xffd9a8); m.material.emissiveIntensity = 7; }
        m.material.envMapIntensity = 0.6;
      });
      // the flush ceiling fixture of the hallway is replaced by the pendant
      this.world.architecture?.hall?.traverse((m) => { if (m.isMesh && m.material?.name === 'hallGlow') m.visible = false; });
    }
  }

  /** Replace several placed static objects by one world-space mesh per material (keeps cast/receive shadow). */
  _bake(keys, name) {
    const objs = keys.map((k) => this.objects[k]).filter(Boolean);
    if (objs.length < 2) return;
    const byMat = new Map();
    for (const o of objs) {
      o.updateWorldMatrix(true, true);
      o.traverse((m) => {
        if (!m.isMesh || Array.isArray(m.material)) return;
        if (!byMat.has(m.material)) byMat.set(m.material, []);
        byMat.get(m.material).push(m.geometry.clone().applyMatrix4(m.matrixWorld));
      });
    }
    const sig = (g) => Object.keys(g.attributes).sort().join(',') + (g.index ? '|i' : '|n');
    for (const geos of byMat.values()) if (!geos.every((g) => sig(g) === sig(geos[0]))) return; // keep the originals
    for (const o of objs) o.parent?.remove(o);
    for (const [mat, geos] of byMat) {
      const g = mergeGeometries(geos, false);
      geos.forEach((x) => x.dispose());
      if (!g) continue;
      const mesh = new THREE.Mesh(g, mat);
      mesh.name = name; mesh.castShadow = true; mesh.receiveShadow = true;
      this.game.scene.add(mesh);
      for (const k of keys) if (this.objects[k]) this.objects[k] = mesh;
    }
  }

  // ---------------------------------------------------------------------------------------------- nook shell

  _nookShell() {
    const A = this.game.assets, mats = this.world.architecture?.mats;
    const rep = (m) => [1 / m, 1 / m];
    const swap = (mat, set, tile, rgb, { ao = true, normalScale = 1 } = {}) => {
      if (!mat) return;
      const r = rep(tile), p = `textures/${set}/`;
      mat.map = A.texture(p + 'color.jpg', { srgb: true, repeat: r });
      mat.normalMap = A.texture(p + 'normal.jpg', { repeat: r });
      mat.normalScale.set(normalScale, normalScale);
      mat.roughnessMap = A.texture(p + 'rough.jpg', { repeat: r }); mat.roughness = 1;
      mat.aoMap = ao && !this._low ? A.texture(p + 'ao.jpg', { repeat: r }) : null; mat.aoMapIntensity = 0.8;
      mat.color.setRGB(rgb[0], rgb[1], rgb[2]);
      mat.needsUpdate = true;
    };
    // walls above the wainscot: raw cast concrete (block walls N/E and the drywall faces W/S alike: storage room)
    swap(mats?.nookBlock, 'concrete_wall_007', 2.2, [0.85, 0.83, 0.8]);
    swap(mats?.nookDrywall, 'concrete_wall_007', 2.2, [0.8, 0.78, 0.75]);

    // tiled wainscot 0..1.1 m on the four walls (3 mm overlay), bullnose cap + jamb edges
    const H = 1.1, off = 0.003, sc = this.game.scene;
    const damp = (x, y, z) => {
      let c = 1 - 0.38 * Math.exp(-y / 0.1) - 0.14 * Math.exp(-y / 0.45);
      c *= 0.82 + 0.3 * fbm(x * 1.7 + z * 1.3, y * 2.1, 3);
      const streak = fbm(x * 9 + z * 7, y * 0.8, 2);
      if (streak > 0.6) c *= 1 - (streak - 0.6) * 1.4 * (1.1 - y);
      return [c, c * 0.97, c * 0.9];
    };
    const geos = [];
    const wall = (o, U, w) => geos.push(patch(o, U, [0, 1, 0], w, H, { nu: Math.max(1, Math.round(w / 0.4)), nv: 6, color: damp }));
    wall([AL.minX, 0, AL.minZ + off], [1, 0, 0], AL.maxX - AL.minX);              // N
    wall([AL.maxX - off, 0, AL.minZ], [0, 0, 1], ZN - AL.minZ);                    // E
    wall([AL.minX + off, 0, ZN], [0, 0, -1], ZN - AL.minZ);                        // W
    wall([AL.maxX, 0, ZN - off], [-1, 0, 0], AL.maxX - AL.doorway.maxX);          // S, east of the doorway
    wall([AL.doorway.minX, 0, ZN - off], [-1, 0, 0], AL.doorway.minX - AL.minX);  // S, west of the doorway
    // bullnose cap (small rounded strip) — UVs squeezed onto a clean bit of a tile
    const cap = (a, b) => { const g = boxGeo(a, b, { uvScale: 0.05, color: [0.95, 0.93, 0.88] }); geos.push(g); };
    const t = 0.012;
    cap([AL.minX, H, AL.minZ], [AL.maxX, H + 0.022, AL.minZ + t]);
    cap([AL.maxX - t, H, AL.minZ], [AL.maxX, H + 0.022, ZN]);
    cap([AL.minX, H, AL.minZ], [AL.minX + t, H + 0.022, ZN]);
    cap([AL.doorway.maxX, H, ZN - t], [AL.maxX, H + 0.022, ZN]);
    cap([AL.minX, H, ZN - t], [AL.doorway.minX, H + 0.022, ZN]);
    cap([AL.doorway.minX - 0.014, 0, ZN - t], [AL.doorway.minX, H, ZN]);          // tile edge on the jambs
    cap([AL.doorway.maxX, 0, ZN - t], [AL.doorway.maxX + 0.014, H, ZN]);
    const tile = A.pbr('tiles094', rep(0.8), { vertexColors: true });
    tile.color.setRGB(0.92, 0.88, 0.8); tile.aoMapIntensity = 0.7;
    if (this._low) tile.aoMap = null;
    tile.userData.envZone = 0.45; tile.name = 'details_nookTiles';
    const mesh = new THREE.Mesh(mergeGeometries(geos.map((g) => { g.deleteAttribute('uv1'); return g; }), false), tile);
    mesh.name = 'details_nookTiles'; mesh.receiveShadow = true; mesh.castShadow = false;
    sc.add(mesh);
  }

  // ---------------------------------------------------------------------------------------------- fluorescent tube

  _buildTube() {
    const o = this.objects.tubeLight;
    const T = L.TUBE_LIGHT;
    const light = new THREE.SpotLight(0xffffff, 0, 7.5, T.angle, T.penumbra, 2);
    light.color.setRGB(0.9, 1.0, 0.93); // cool-white tube, slightly green next to the warm 2700 K bulb (camera ~4300 K)
    light.name = 'tubeLight';
    light.position.fromArray(T.pos);
    light.target.position.fromArray(T.target);
    light.castShadow = false;
    this.game.scene.add(light, light.target);
    let glass = null;
    o?.traverse((m) => {
      if (!m.isMesh) return;
      if (/glass/i.test(m.material.name)) { glass = m.material; m.castShadow = false; }
    });
    if (glass) { glass.emissive.setRGB(0.93, 1.0, 0.96); glass.emissiveIntensity = 0; }
    this.tube = {
      light, glass, mode: this._powerOn ? 'on' : 'off', level: 0, shown: -1, t: 0, seq: null,
      glitchT: 6 + Math.random() * 10, burst: 0, burstTimer: 0, burstVal: 1, buzz: null, buzzSent: -1,
      pos: new THREE.Vector3(T.pos[0], T.pos[1] + 0.03, T.pos[2]),
    };
  }

  /** Dying-tube start: starter clicks, short flashes with dark gaps, an end-glow, then it catches. */
  _tubeSequence() {
    const r = Math.random, seq = [];
    let t = 0.12 + r() * 0.15;
    const n = 3 + Math.floor(r() * 3);
    for (let i = 0; i < n; i++) {
      const d = 0.04 + r() * 0.09;
      seq.push([t, t + d, 0.55 + r() * 0.5, true]);
      t += d + 0.12 + r() * 0.35;
      if (i === 1) { seq.push([t, t + 0.35, 0.05, false]); t += 0.45; } // dim pinkish end glow, no strike
    }
    seq.push([t, t + 0.08, 1, true]); t += 0.08 + 0.1;
    seq.push([t, 1e9, 1, true]);    // caught
    return seq;
  }

  _updateTube(dt) {
    const T = this.tube;
    if (!T) return;
    const power = this.world.power !== false;
    if (!power) T.mode = 'off';
    else if (T.mode === 'off') { T.mode = 'start'; T.t = 0; T.seq = this._tubeSequence(); T.seqI = -1; }
    let lv = 0;
    if (T.mode === 'start') {
      T.t += dt;
      let k = -1;
      for (let i = 0; i < T.seq.length; i++) if (T.t >= T.seq[i][0] && T.t < T.seq[i][1]) { k = i; break; }
      if (k >= 0) {
        lv = T.seq[k][2] * (T.seq[k][2] < 0.2 ? 1 : 0.85 + 0.15 * Math.random());
        if (k !== T.seqI && T.seq[k][3]) this._click(0.25 + 0.2 * Math.random());
        if (k === T.seq.length - 1) { T.mode = 'on'; T.glitchT = 8 + Math.random() * 12; }
      }
      T.seqI = k;
    } else if (T.mode === 'on') {
      lv = 1;
      // entity close → the tube struggles more
      const e = this.game.entity;
      let stress = 0;
      if (e?.position && e.active) stress = clamp01(1 - e.position.distanceTo(T.pos) / 5);
      T.glitchT -= dt * (1 + stress * 6);
      if (T.glitchT <= 0) {
        T.burst = 0.25 + Math.random() * (0.5 + stress * 0.8);
        T.glitchT = 7 + Math.random() * 16;
      }
      if (T.burst > 0) {
        T.burst -= dt; T.burstTimer -= dt;
        if (T.burstTimer <= 0) {
          T.burstTimer = 0.03 + Math.random() * 0.07;
          T.burstVal = Math.random() < 0.55 ? 0.08 + Math.random() * 0.35 : 1;
        }
        lv = T.burstVal;
      }
      lv *= 0.97 + 0.03 * Math.sin(this._time * 7.3) * Math.sin(this._time * 3.1); // slight pulsing of an old ballast
    }
    T.level = lv;
    if (Math.abs(lv - T.shown) > 0.004) {
      T.shown = lv;
      const exp = this.world.lighting?.exposure ?? 0.11;
      T.light.intensity = L.TUBE_LIGHT.cd * exp * lv;
      if (T.glass) T.glass.emissiveIntensity = 95 * exp * Math.pow(lv, 1.2);
    }
    // buzz (positional, only while playing)
    const playing = this.game.state === 'playing' || this.game.state === 'paused' || this.game.state === 'caught';
    const audio = this.game.audio;
    if (power && playing && audio?.loop) {
      if (!T.buzz) { T.buzz = audio.loop('light_buzz', { position: T.pos, volume: 0.0001, unique: true, fadeIn: 0.05 }); T.buzzSent = -1; }
      const v = lv > 0.02 ? 0.25 + 0.55 * lv : 0.04;
      if (Math.abs(v - T.buzzSent) > 0.03) { T.buzz?.setVolume?.(v); T.buzzSent = v; }
    } else if (T.buzz) { T.buzz.stop?.(0.08); T.buzz = null; }
  }

  _click(vol) {
    const T = this.tube;
    try { this.game.audio?.play?.('flashlight_click', { position: T.pos, volume: vol, rate: 0.75 }); } catch (e) { /* optional */ }
  }

  // ---------------------------------------------------------------------------------------------- hallway

  async _hallway() {
    const A = this.game.assets, arch = this.world.architecture, mats = arch?.mats;
    if (!mats || !arch.hall) return;
    const rep = (m) => [1 / m, 1 / m];
    const tex = (set, f, tile, srgb = false) => A.texture(`textures/${set}/${f}`, { srgb, repeat: rep(tile) });
    const swap = (mat, set, tile, rgb, map = null) => {
      mat.map = map || tex(set, 'color.jpg', tile, true);
      mat.normalMap = tex(set, 'normal.jpg', tile); mat.normalScale.set(1, 1);
      mat.roughnessMap = tex(set, 'rough.jpg', tile); mat.roughness = 1;
      mat.aoMap = this._low ? null : tex(set, 'ao.jpg', tile); mat.aoMapIntensity = 0.85;
      mat.color.setRGB(rgb[0], rgb[1], rgb[2]);
      mat.needsUpdate = true;
    };
    swap(mats.hallFloor, 'herringbone_parquet', 2.5, [0.75, 0.5, 0.38]);
    // darker than the NEW_ASSETS tint: the hallway light hangs 0.5 m under it with no shadow from the shade
    swap(mats.hallCeil, 'worn_cracked_plaster', 2.0, [0.92, 0.86, 0.76]);
    mats.hallCeil.aoMapIntensity = 0.5;
    let damask = null;
    try { damask = await this._damask(this._low ? 512 : 1024); } catch (e) { console.warn('[details] damask', e); }
    swap(mats.hallWall, 'decrepit_wallpaper', 2.5, damask ? [1.12, 0.98, 0.8] : [1.1, 0.95, 0.75], damask);

    const hall = arch.hall, x0 = HALL.minX, x1 = HALL.maxX, z0 = HALL.minZ, off = 0.003, WH = 0.85;
    // peeling painted wainscot (0..0.85 m) on the side walls + the two slivers beside the door we came through
    const grime = (x, y, z) => { const c = (1 - 0.35 * Math.exp(-(y - HY0) / 0.12)) * (0.85 + 0.25 * fbm(x * 2 + z * 2.3, y * 3, 3)); return [c, c * 0.98, c * 0.95]; };
    const g1 = [];
    const side = (o, U, w) => g1.push(patch(o, U, [0, 1, 0], w, WH, { nu: Math.max(1, Math.round(w / 0.4)), nv: 4, color: grime }));
    side([x0 + off, HY0, ZN], [0, 0, -1], ZN - z0);                       // W wall
    side([x1 - off, HY0, z0], [0, 0, 1], 0.1);                            // E wall, north of the bedroom door
    side([x1 - off, HY0, z0 + 0.9], [0, 0, 1], ZN - (z0 + 0.9));          // E wall, south of it
    side([L.UPSTAIRS_DOOR.hingeX, HY0, ZN - off], [-1, 0, 0], L.UPSTAIRS_DOOR.hingeX - x0);
    side([x1, HY0, ZN - off], [-1, 0, 0], x1 - (L.UPSTAIRS_DOOR.hingeX + L.UPSTAIRS_DOOR.width));
    const peel = A.pbr('peeling_painted_wall', rep(1.8), { vertexColors: true });
    peel.color.setRGB(0.55, 0.95, 0.9); peel.userData.envZone = 0.3; peel.name = 'details_hallWainscot';
    if (this._low) peel.aoMap = null;
    const wm = new THREE.Mesh(mergeGeometries(g1, false), peel);
    wm.name = 'details_hallWainscot'; wm.castShadow = false; wm.receiveShadow = false;
    hall.add(wm);
    // chair rail (dark stained wood, the hall's own material)
    const rail = [];
    const ry = HY0 + WH;
    rail.push(boxGeo([x0, ry - 0.012, z0], [x0 + 0.022, ry + 0.028, ZN]));
    rail.push(boxGeo([x1 - 0.022, ry - 0.012, z0], [x1, ry + 0.028, z0 + 0.1 - 0.065]));
    rail.push(boxGeo([x1 - 0.022, ry - 0.012, z0 + 0.9 + 0.065], [x1, ry + 0.028, ZN]));
    const rm = new THREE.Mesh(mergeGeometries(rail, false), mats.hallWood);
    rm.name = 'details_hallRail'; rm.castShadow = false; rm.receiveShadow = false;
    hall.add(rm);

    // end wall: wallpaper and plaster fallen off, exposing the old brick (ragged alpha-tested edge)
    const W = x1 - x0, Hh = HY1 - HY0;
    const box = (sx0, sx1, sy0, sy1) => patch([x0 + sx0, HY0 + sy0, z0 + off], [1, 0, 0], [0, 1, 0], sx1 - sx0, sy1 - sy0, {
      nu: 2, nv: 3, color: (x, y) => 0.85 + 0.2 * fbm(x * 3, y * 3, 2), uv1Box: [sx0 / W, sx1 / W, sy0 / Hh, sy1 / Hh],
    });
    const wx0 = HWIN.x0 - x0, wx1 = HWIN.x1 - x0, wy0 = HWIN.y0 - HY0, wy1 = HWIN.y1 - HY0;
    const bg = [box(0, wx0, 0, Hh), box(wx1, W, 0, Hh), box(wx0, wx1, 0, wy0), box(wx0, wx1, wy1, Hh)];
    const brick = A.pbr('brick_wall_001', rep(1.07), { vertexColors: true });
    brick.alphaMap = canvasTex(this._plasterLossMask(), { srgb: false });
    brick.alphaMap.channel = 1;
    brick.alphaTest = 0.5; brick.userData.envZone = 0.3; brick.name = 'details_hallBrick';
    if (this._low) brick.aoMap = null;
    const bm = new THREE.Mesh(mergeGeometries(bg, false), brick);
    bm.name = 'details_hallBrick'; bm.castShadow = false; bm.receiveShadow = false;
    hall.add(bm);
  }

  /** Ragged "plaster fell off" mask for the hall end wall (white = brick shows). 0..1 over the wall, v up. */
  _plasterLossMask() {
    const w = 128, h = 256, c = canvas(w, h), g = c.getContext('2d'), img = g.createImageData(w, h), d = img.data;
    for (let j = 0; j < h; j++) {
      const v = 1 - j / (h - 1); // canvas row 0 = top of the wall (flipY)
      for (let i = 0; i < w; i++) {
        const u = i / (w - 1);
        // a large loss around the lower-middle and the window's right side, a smaller one high on the left
        let f = Math.exp(-(((u - 0.62) / 0.42) ** 2 + ((v - 0.36) / 0.3) ** 2));
        f = Math.max(f, 0.9 * Math.exp(-(((u - 0.2) / 0.16) ** 2 + ((v - 0.82) / 0.1) ** 2)));
        f = Math.max(f, 0.75 * Math.exp(-(((u - 0.85) / 0.12) ** 2 + ((v - 0.7) / 0.14) ** 2)));
        f += (fbm(u * 9, v * 18, 4) - 0.5) * 0.55 + (vnoise(u * 40, v * 80) - 0.5) * 0.12;
        f *= smooth(0.0, 0.06, v); // keep the paper right above the baseboard
        const a = f > 0.42 ? 255 : 0;
        const k = (j * w + i) * 4;
        d[k] = d[k + 1] = d[k + 2] = a; d[k + 3] = 255;
      }
    }
    g.putImageData(img, 0, 0);
    return c;
  }

  /** decrepit_wallpaper photo × a faded printed damask (tiles with the photo: 5 x 6 motifs, half-drop). */
  async _damask(size) {
    const A = this.game.assets;
    const img = await new THREE.ImageLoader().loadAsync(`${A.base}textures/decrepit_wallpaper/color.jpg`);
    const c = canvas(size, size), g = c.getContext('2d');
    g.drawImage(img, 0, 0, size, size);
    const m = canvas(size, size), mg = m.getContext('2d');
    const cols = 10, rows = 12, cw = size / cols, ch = size / rows; // 25 x 21 cm motifs on the 2.5 m tile
    const motif = (cx, cy) => {
      mg.save(); mg.translate(cx, cy); mg.scale(cw * 0.42, ch * 0.46);
      for (const sx of [1, -1]) {
        mg.save(); mg.scale(sx, 1);
        mg.beginPath(); // top fleur petal
        mg.moveTo(0, -0.08); mg.bezierCurveTo(0.2, -0.3, 0.16, -0.62, 0, -0.95); mg.bezierCurveTo(0.05, -0.6, 0.06, -0.3, 0, -0.08); mg.fill();
        mg.beginPath(); // side leaf
        mg.moveTo(0.03, -0.02); mg.bezierCurveTo(0.35, -0.35, 0.85, -0.25, 0.82, 0.1); mg.bezierCurveTo(0.6, -0.05, 0.3, 0.05, 0.03, -0.02); mg.fill();
        mg.beginPath(); // outer feather
        mg.moveTo(0.15, -0.35); mg.bezierCurveTo(0.45, -0.7, 0.75, -0.6, 0.7, -0.35); mg.bezierCurveTo(0.55, -0.48, 0.35, -0.42, 0.15, -0.35); mg.fill();
        mg.lineWidth = 0.06; // lower scroll
        mg.beginPath(); mg.arc(0.38, 0.42, 0.2, -PI * 0.9, PI * 0.7); mg.stroke();
        mg.beginPath(); mg.arc(0.38, 0.42, 0.08, 0, TAU); mg.fill();
        mg.beginPath(); mg.arc(0.62, -0.78, 0.06, 0, TAU); mg.fill();
        mg.restore();
      }
      mg.beginPath(); // bottom drop + stem
      mg.moveTo(0, 0.02); mg.bezierCurveTo(0.14, 0.25, 0.12, 0.55, 0, 0.9); mg.bezierCurveTo(-0.12, 0.55, -0.14, 0.25, 0, 0.02); mg.fill();
      mg.beginPath(); mg.ellipse(0, 0, 0.09, 0.12, 0, 0, TAU); mg.fill();
      mg.restore();
    };
    mg.fillStyle = '#7f6a4a'; mg.strokeStyle = '#7f6a4a';
    for (let r = 0; r < rows; r++) {
      for (let k = 0; k < cols; k++) {
        const cx = (k + 0.5) * cw, cy = (r + 0.5) * ch + (k % 2 ? ch * 0.5 : 0);
        for (const dx of [-size, 0, size]) for (const dy of [-size, 0, size]) {
          if (Math.abs(cx + dx - size / 2) > size / 2 + cw || Math.abs(cy + dy - size / 2) > size / 2 + ch) continue;
          motif(cx + dx, cy + dy);
        }
      }
    }
    // thin pin stripes between the motif columns
    mg.globalAlpha = 0.5; mg.fillStyle = '#7a6443';
    for (let k = 0; k < cols; k++) { mg.fillRect(k * cw - size * 0.0015, 0, size * 0.003, size); mg.fillRect(k * cw + size * 0.006, 0, size * 0.0015, size); }
    g.save(); g.globalCompositeOperation = 'multiply'; g.globalAlpha = 0.3; g.drawImage(m, 0, 0); g.restore();
    // the print faded unevenly (sun, damp): lighten it back in blotches
    g.save(); g.globalCompositeOperation = 'soft-light'; g.globalAlpha = 0.25;
    const R2 = rng(7);
    for (let i = 0; i < 18; i++) {
      const x = R2() * size, y = R2() * size, r = size * (0.05 + R2() * 0.15);
      const gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, '#ffffff'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr; g.fillRect(x - r, y - r, r * 2, r * 2);
    }
    g.restore();
    return canvasTex(c, { repeat: [1 / 2.5, 1 / 2.5], aniso: this._aniso });
  }

  // ---------------------------------------------------------------------------------------------- decals

  /**
   * Env-map zone of a decal, as a multiplier of the scene environment (Architecture's zone materials get an explicit
   * env map of intensity zone × k; the decals scale the IBL terms per vertex instead, so ONE material serves all).
   */
  _zoneOf(d) {
    const [x, y, z] = d.pos;
    if (y > UP.floorY - 0.05 && z < R.minZ - 0.1 && x < HALL.maxX + 0.05) return { name: 'hall', env: 0.3 };
    if (z < R.minZ - 0.1 && x > AL.minX - 0.05 && y < UP.floorY + 0.05) return { name: 'nook', env: 0.45 };
    if (x < L.STAIRS.sideWallX - 0.04 && z < L.CLOSET.maxZ + 0.05 && y < 2.48) return { name: 'closet', env: 0.12 };
    if (x < L.STAIRS.sideWallX && y > R.ceilingY - 0.1 && z > R.minZ) return { name: 'stair', env: 0.85 };
    return { name: 'main', env: 1 };
  }

  /**
   * Decal atlas: every batch-3 decal set + the crayon cells in ONE set of textures, so all decals are one material
   * (two draw calls: the basement, and the hallway group). Layout in 1/4-atlas cells [x, y, w, h] (y from the top).
   * Textures: color (RGB), alpha+roughness (G = alpha for alphaMap, R = roughness, read by a patched chunk), normal.
   */
  async _decalAtlas() {
    const SLOTS = {
      decal_leak_streaks: [0, 0, 2, 2], crayon: [2, 0, 2, 1], decal_grime: [2, 1, 1, 1], decal_scuffs: [3, 1, 1, 1],
      decal_rising_damp: [0, 2, 1, 1], decal_pipe_leak: [1, 2, 1, 1], decal_dirt_patch: [2, 2, 1, 1], decal_hand_smudges: [3, 2, 1, 1],
      decal_water_ring: [0, 3, 1, 1], decal_mold: [1, 3, 1, 1], decal_rust_drip: [2, 3, 0.25, 1],
    };
    const q = this.game.renderer?.quality || 'medium';
    const N = q === 'high' || q === 'ultra' ? 2048 : 1024, cs = N / 4, pad = N / 256;
    const rect = (s) => { const [cx, cy, w, h] = SLOTS[s]; return [cx * cs + pad, cy * cs + pad, w * cs - 2 * pad, h * cs - 2 * pad]; };
    const A = this.game.assets, loader = new THREE.ImageLoader();
    const sets = Object.keys(SLOTS).filter((s) => s !== 'crayon');
    const want = this._low ? ['color', 'alpha'] : ['color', 'alpha', 'rough', 'normal'];
    const imgs = {};
    await Promise.all(sets.flatMap((s) => want.map(async (m) => {
      try { imgs[s + '/' + m] = await loader.loadAsync(`${A.base}textures/${s}/${m}.jpg`); } catch (e) { console.warn('[details] decal map', s, m); }
    })));
    const mk = (fill) => { const c = canvas(N, N), g = c.getContext('2d'); g.fillStyle = fill; g.fillRect(0, 0, N, N); g.imageSmoothingQuality = 'high'; return [c, g]; };
    const [cc, cg] = mk('#6b6259');
    const [ac, ag] = mk('#000000'); // alpha (to be moved to G) — drawn grey first
    const [rc, rg] = this._low ? [null, null] : mk('#d9d9d9');
    const [nc, ng] = this._low ? [null, null] : mk('rgb(128,128,255)');
    for (const s of sets) {
      const [x, y, w, h] = rect(s);
      if (imgs[s + '/color']) cg.drawImage(imgs[s + '/color'], x, y, w, h);
      if (imgs[s + '/alpha']) ag.drawImage(imgs[s + '/alpha'], x, y, w, h);
      if (rg && imgs[s + '/rough']) rg.drawImage(imgs[s + '/rough'], x, y, w, h);
      if (ng && imgs[s + '/normal']) ng.drawImage(imgs[s + '/normal'], x, y, w, h);
    }
    // crayon cells: wax colour over a neutral base, alpha from the canvas, waxy roughness, flat normal
    const cray = this._crayonAtlas();
    { const [x, y, w, h] = rect('crayon'); cg.drawImage(cray, x, y, w, h);
      const tmp = canvas(Math.round(w), Math.round(h)), tg = tmp.getContext('2d'); tg.drawImage(cray, 0, 0, tmp.width, tmp.height);
      const id = tg.getImageData(0, 0, tmp.width, tmp.height), d = id.data;
      for (let i = 0; i < d.length; i += 4) { const a = d[i + 3]; d[i] = d[i + 1] = d[i + 2] = a; d[i + 3] = 255; }
      tg.putImageData(id, 0, 0); ag.drawImage(tmp, x, y);
      if (rg) { rg.fillStyle = 'rgb(140,140,140)'; rg.fillRect(x, y, w, h); } }
    // pack alpha (G) + roughness (R) into one texture
    const ad = ag.getImageData(0, 0, N, N), rd = rg ? rg.getImageData(0, 0, N, N).data : null, d = ad.data;
    for (let i = 0; i < d.length; i += 4) { const a = d[i + 1]; d[i] = rd ? rd[i] : 217; d[i + 1] = a; d[i + 2] = 0; d[i + 3] = 255; }
    ag.putImageData(ad, 0, 0);
    const tex = (c, srgb) => { const t = canvasTex(c, { srgb, aniso: this._aniso }); t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping; return t; };
    // uv rectangle of a slot (flipY: canvas row 0 = v 1)
    const uvRect = (s) => { const [x, y, w, h] = rect(s); return [x / N, 1 - (y + h) / N, (x + w) / N, 1 - y / N]; };
    return { map: tex(cc, true), ar: tex(ac, false), normal: nc ? tex(nc, false) : null, uvRect };
  }

  _decalMaterialAtlas(atlas) {
    const mat = new THREE.MeshStandardMaterial({
      map: atlas.map, alphaMap: atlas.ar, roughnessMap: this._low ? null : atlas.ar, roughness: this._low ? 0.85 : 1, metalness: 0,
      normalMap: atlas.normal, normalScale: new THREE.Vector2(0.5, 0.5),
      transparent: true, depthWrite: false, vertexColors: true, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4,
    });
    mat.name = 'details_decals';
    mat.onBeforeCompile = (sh) => {
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nattribute float aZone;\nvarying float vZone;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvZone = aZone;');
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\nvarying float vZone;')
        .replace('#include <roughnessmap_fragment>', [
          'float roughnessFactor = roughness;',
          '#ifdef USE_ROUGHNESSMAP',
          '  roughnessFactor *= texture2D( roughnessMap, vRoughnessMapUv ).r;', // R = roughness, G = alpha
          '#endif',
        ].join('\n'))
        .replace('#include <lights_fragment_maps>', '#include <lights_fragment_maps>\n  iblIrradiance *= vZone;\n  radiance *= vZone;');
    };
    mat.customProgramCacheKey = () => 'details_decals_zone_v1';
    return mat;
  }

  _decalGeo(d, offset, uvRect, zone) {
    const g = new THREE.PlaneGeometry(d.size[0], d.size[1]);
    const uv = g.attributes.uv;
    const crayon = d.tex.startsWith('crayon:');
    const [u0, v0, u1, v1] = uvRect(crayon ? 'crayon' : d.tex);
    const cell = crayon ? Number(d.tex.split(':')[1]) : -1;
    for (let i = 0; i < uv.count; i++) {
      let u = uv.getX(i), v = uv.getY(i);
      if (d.flip) u = 1 - u;
      if (cell >= 0) { const cx = cell % 4, cy = Math.floor(cell / 4); u = (cx + u) / 4; v = 1 - (cy + 1 - v) / 2; }
      uv.setXY(i, u0 + (u1 - u0) * u, v0 + (v1 - v0) * v);
    }
    const m = basis(d.normal, d.up);
    const n = new THREE.Vector3(...d.normal).normalize();
    m.setPosition(new THREE.Vector3(...d.pos).addScaledVector(n, offset));
    g.applyMatrix4(m);
    const c = d.tint ? linColor(d.tint) : new THREE.Color(1, 1, 1);
    prep(g, [c.r, c.g, c.b], d.opacity ?? 1);
    g.setAttribute('aZone', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count).fill(zone.env), 1));
    return g;
  }

  async _decals() {
    const atlas = await this._decalAtlas();
    const mat = this._decalMaterialAtlas(atlas);
    // blend order inside the merged mesh = buffer order: floors, then broad stains, then marks on top
    const rank = (d) => (d.normal[1] > 0.9 ? 0 : /leak|damp|grime|ring|mold|pipe|rust/.test(d.tex) ? 1 : 2);
    const list = [...L.DECALS].sort((a, b) => rank(a) - rank(b));
    const base = [], hallG = [];
    for (const d of list) {
      const zone = this._zoneOf(d);
      const floor = d.normal[1] > 0.9, ceil = d.normal[1] < -0.9;
      // walls: 6 mm (above the 3 mm tile / wainscot overlays); floors 3 mm (over the carpet wear); ceilings 4 mm
      const off = floor ? 0.003 : ceil ? 0.004 : 0.006;
      (zone.name === 'hall' ? hallG : base).push(this._decalGeo(d, off, atlas.uvRect, zone));
    }
    const hall = this.world.architecture?.hall;
    for (const [geos, name, parent] of [[base, 'decals_basement', this.game.scene], [hallG, 'decals_hall', hall || this.game.scene]]) {
      if (!geos.length) continue;
      const mesh = new THREE.Mesh(mergeGeometries(geos, false), mat);
      mesh.name = name; mesh.renderOrder = 2;
      mesh.castShadow = false; mesh.receiveShadow = name !== 'decals_hall';
      parent.add(mesh);
      this.decalMeshes.push(mesh);
    }
  }

  /** 4 x 2 cells (256 px) of crayon marks on a transparent background (wall scribbles near the kids corner). */
  _crayonAtlas() {
    const S = 256, c = canvas(S * 4, S * 2), g = c.getContext('2d');
    const Rn = rng(4242);
    const col = { red: '#c8352a', blue: '#2f5fb3', green: '#3f9a3c', yellow: '#e8b81e', orange: '#ec8a24', purple: '#6d3fa8', black: '#1c1a1d', pink: '#e06a94' };
    const cellXY = (n) => [(n % 4) * S, Math.floor(n / 4) * S];
    const scribble = (ox, oy, cx, cy, rx, ry, n, color, w = 2.6) => {
      const pts = [];
      for (let i = 0; i < n; i++) pts.push(ox + cx + (Rn() - 0.5) * 2 * rx, oy + cy + (Rn() - 0.5) * 2 * ry);
      crayon(g, Rn, pts, color, w, 2, 0.85);
    };
    const hatch = (ox, oy, cx, cy, rx, ry, n, color, ang = 0.5, w = 2.4) => {
      const pts = [];
      let t = -rx;
      for (let i = 0; i < n && t < rx; i++) {
        t += (2 * rx / n) * (0.4 + Rn() * 1.3);
        const s = (i % 2 ? 1 : -1) * ry * (0.45 + Rn() * 0.6);
        pts.push(ox + cx + t * Math.cos(ang) - s * Math.sin(ang) * 0.4 + (Rn() - 0.5) * 9, oy + cy + t * Math.sin(ang) + s * Math.cos(ang) + (Rn() - 0.5) * 9);
      }
      crayon(g, Rn, pts, color, w, 2, 0.8);
    };
    // 0: chaotic multi-colour scribble cloud
    let [ox, oy] = cellXY(0);
    scribble(ox, oy, 100, 120, 70, 55, 40, col.blue); scribble(ox, oy, 160, 100, 55, 40, 28, col.purple, 2.2);
    hatch(ox, oy, 120, 160, 80, 30, 26, col.red, -0.3); scribble(ox, oy, 70, 80, 30, 25, 14, col.green, 2.2);
    // 1: radial "sun" burst (yellow / orange), like the reference corner
    [ox, oy] = cellXY(1);
    for (let i = 0; i < 26; i++) {
      const a = Rn() * TAU, r0 = 10 + Rn() * 20, r1 = 60 + Rn() * 60;
      crayon(g, Rn, [ox + 128 + Math.cos(a) * r0, oy + 128 + Math.sin(a) * r0, ox + 128 + Math.cos(a) * r1, oy + 128 + Math.sin(a) * r1], i % 3 ? col.yellow : col.orange, 2.4, 2, 0.8);
    }
    scribble(ox, oy, 128, 128, 22, 22, 18, col.orange, 3);
    // 2: "LÉA" + a heart + zigzag
    [ox, oy] = cellXY(2);
    const letter = (pts) => crayon(g, Rn, pts.map((v, i) => (i % 2 ? oy + v : ox + v)), col.red, 4.5, 3, 0.95);
    letter([40, 60, 38, 140, 78, 142]);                                      // L
    letter([100, 62, 98, 140, 136, 140]); letter([100, 62, 134, 60]); letter([100, 100, 128, 100]); letter([112, 50, 128, 38]); // É
    letter([150, 140, 172, 60, 196, 140]); letter([158, 112, 188, 112]);      // A
    crayon(g, Rn, [ox + 128, oy + 230, ox + 92, oy + 196, ox + 94, oy + 172, ox + 112, oy + 168, ox + 128, oy + 186, ox + 144, oy + 168, ox + 162, oy + 172, ox + 164, oy + 196, ox + 128, oy + 230], col.pink, 3.5, 3, 0.9);
    const zz = []; for (let i = 0; i < 12; i++) zz.push(ox + 20 + i * 18, oy + 178 + (i % 2 ? -14 : 14)); crayon(g, Rn, zz, col.green, 3, 2, 0.8);
    // 3: tall thin black figure with long hair (she) + scratched-over face, scribbled hard
    [ox, oy] = cellXY(3);
    crayon(g, Rn, [ox + 128, oy + 30, ox + 112, oy + 40, ox + 110, oy + 58, ox + 124, oy + 70, ox + 140, oy + 62, ox + 142, oy + 42, ox + 128, oy + 30], col.black, 3.5, 3, 0.95);
    for (let i = 0; i < 10; i++) crayon(g, Rn, [ox + 112 + i * 3.4, oy + 34, ox + 104 + i * 4.6, oy + 120 + Rn() * 40], col.black, 2.2, 1, 0.9);
    scribble(ox, oy, 126, 50, 14, 14, 16, col.black, 3);
    crayon(g, Rn, [ox + 126, oy + 70, ox + 128, oy + 190], col.black, 4, 3);
    crayon(g, Rn, [ox + 128, oy + 190, ox + 108, oy + 250], col.black, 4, 3); crayon(g, Rn, [ox + 128, oy + 190, ox + 148, oy + 250], col.black, 4, 3);
    crayon(g, Rn, [ox + 127, oy + 90, ox + 70, oy + 170, ox + 64, oy + 200], col.black, 3.5, 3); crayon(g, Rn, [ox + 127, oy + 90, ox + 186, oy + 170, ox + 192, oy + 200], col.black, 3.5, 3);
    crayon(g, Rn, [ox + 100, oy + 100, ox + 156, oy + 100, ox + 168, oy + 190, ox + 88, oy + 190, ox + 100, oy + 100], col.black, 2.5, 2, 0.7);
    // 4: red zigzags
    [ox, oy] = cellXY(4);
    for (let k = 0; k < 3; k++) { const p = []; for (let i = 0; i < 10; i++) p.push(ox + 24 + i * 21, oy + 70 + k * 55 + (i % 2 ? -18 : 18)); crayon(g, Rn, p, k === 1 ? col.blue : col.red, 3, 2, 0.85); }
    // 5: green spiral
    [ox, oy] = cellXY(5);
    { const p = []; for (let a = 0; a < TAU * 3.4; a += 0.25) p.push(ox + 128 + Math.cos(a) * a * 5.4, oy + 128 + Math.sin(a) * a * 4.6); crayon(g, Rn, p, col.green, 3, 2, 0.85); }
    // 6: tally marks + blue hatch
    [ox, oy] = cellXY(6);
    for (let i = 0; i < 9; i++) crayon(g, Rn, [ox + 30 + i * 18 + (i === 4 || i === 8 ? -60 : 0), oy + 60 + (i === 4 || i === 8 ? 40 : 0), ox + 34 + i * 18, oy + 140], col.blue, 3, 2, 0.9);
    hatch(ox, oy, 150, 190, 80, 25, 24, col.purple, 0.15);
    // 7: spare light scribble
    [ox, oy] = cellXY(7);
    scribble(ox, oy, 128, 128, 90, 70, 40, col.orange, 2);
    waxTooth(g, 0, 0, S * 4, S * 2, Rn, 0.4);
    return c;
  }

  // ---------------------------------------------------------------------------------------------- wall grime band

  /**
   * Lived-in grime along the lower main-room walls (0.1–1.3 m): specks, pencil-like scratches, rubber kicks right above
   * the baseboards, faint smudges — a tileable 2 m × 1.2 m transparent canvas on thin overlay strips (1 draw call).
   */
  _wallGrime() {
    const TW = 2.0, TH = 1.2, W = this._low ? 512 : 1024, H = Math.round((W * TH) / TW);
    const c = canvas(W, H), g = c.getContext('2d'), Rn = rng(2468);
    const wrap = (fn) => { for (const dx of [-W, 0, W]) { g.save(); g.translate(dx, 0); fn(); g.restore(); } };
    const pxm = W / TW; // px per metre
    // faint smudges
    for (let i = 0; i < 16; i++) {
      const x = Rn() * W, y = H * (0.25 + 0.75 * Math.sqrt(Rn())), r = pxm * (0.04 + Rn() * 0.12), a = 0.05 + Rn() * 0.07;
      wrap(() => { const gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, `rgba(60,48,36,${a})`); gr.addColorStop(1, 'rgba(60,48,36,0)'); g.fillStyle = gr; g.fillRect(x - r, y - r, 2 * r, 2 * r); });
    }
    // specks (more near the floor)
    for (let i = 0; i < 520; i++) {
      const x = Rn() * W, y = H * (1 - Math.pow(Rn(), 1.8)), r = (0.4 + Rn() * 1.5) * (W / 1024), a = 0.25 + Rn() * 0.55;
      wrap(() => { g.fillStyle = `rgba(${40 + Rn() * 30},${32 + Rn() * 20},${24 + Rn() * 14},${a})`; g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill(); });
    }
    // scratches / pencil marks
    for (let i = 0; i < 70; i++) {
      const x = Rn() * W, y = H * (0.2 + 0.8 * Rn()), len = pxm * (0.02 + Rn() * 0.12), ang = (Rn() - 0.5) * 0.9 + (Rn() < 0.3 ? PI / 2 : 0);
      wrap(() => {
        g.strokeStyle = `rgba(${55 + Rn() * 40},${50 + Rn() * 30},${45 + Rn() * 30},${0.18 + Rn() * 0.3})`; g.lineWidth = (0.6 + Rn() * 0.8) * (W / 1024);
        g.beginPath(); g.moveTo(x, y); g.quadraticCurveTo(x + Math.cos(ang) * len * 0.5 + (Rn() - 0.5) * 4, y + Math.sin(ang) * len * 0.5, x + Math.cos(ang) * len, y + Math.sin(ang) * len); g.stroke();
      });
    }
    // black rubber kicks just above the baseboard (bottom 12 cm of the band)
    for (let i = 0; i < 26; i++) {
      const x = Rn() * W, y = H - pxm * (0.005 + Rn() * 0.11), len = pxm * (0.03 + Rn() * 0.12);
      wrap(() => {
        g.strokeStyle = `rgba(25,22,20,${0.25 + Rn() * 0.45})`; g.lineCap = 'round'; g.lineWidth = (1 + Rn() * 3.5) * (W / 1024);
        g.beginPath(); g.moveTo(x, y); g.lineTo(x + len, y + (Rn() - 0.5) * pxm * 0.03); g.stroke();
      });
    }
    // a few dried drips (something spilled against the wall long ago)
    for (let i = 0; i < 5; i++) {
      const x = Rn() * W, y0 = H * (0.3 + Rn() * 0.4), len = pxm * (0.08 + Rn() * 0.25);
      wrap(() => {
        const gr = g.createLinearGradient(x, y0, x, y0 + len); gr.addColorStop(0, 'rgba(92,70,40,0.32)'); gr.addColorStop(1, 'rgba(92,70,40,0)');
        g.strokeStyle = gr; g.lineWidth = (1.2 + Rn() * 1.5) * (W / 1024);
        g.beginPath(); g.moveTo(x, y0); g.lineTo(x + (Rn() - 0.5) * 3, y0 + len); g.stroke();
      });
    }
    const map = canvasTex(c, { aniso: this._aniso });
    map.wrapS = THREE.RepeatWrapping; map.wrapT = THREE.ClampToEdgeWrapping;
    const y0 = 0.1, y1 = y0 + TH, off = 0.002, geos = [];
    // strip along a wall: from point a to b (horizontal), normal n; u continues with the world coordinate
    const strip = (a, b, n, top = y1) => {
      const dx = b[0] - a[0], dz = b[1] - a[1];
      const g2 = new THREE.BufferGeometry();
      const ox = n[0] * off, oz = n[1] * off;
      const along = Math.abs(dx) > Math.abs(dz) ? 0 : 1; // u = world coordinate along the wall (continuous at corners)
      const ua = a[along] / TW, ub = b[along] / TW, vt = (top - y0) / TH;
      g2.setAttribute('position', new THREE.Float32BufferAttribute([a[0] + ox, y0, a[1] + oz, b[0] + ox, y0, b[1] + oz, b[0] + ox, top, b[1] + oz, a[0] + ox, top, a[1] + oz], 3));
      g2.setAttribute('normal', new THREE.Float32BufferAttribute([n[0], 0, n[1], n[0], 0, n[1], n[0], 0, n[1], n[0], 0, n[1]], 3));
      g2.setAttribute('uv', new THREE.Float32BufferAttribute([ua, 0, ub, 0, ub, vt, ua, vt], 2));
      // triangle (a, b, b_top) faces (-dz, dx) in xz: keep it when that points along n, else flip the winding
      g2.setIndex(-dz * n[0] + dx * n[1] > 0 ? [0, 1, 2, 0, 2, 3] : [0, 2, 1, 0, 3, 2]);
      geos.push(g2);
    };
    const X0 = R.minX, X1 = R.maxX, Z0 = R.minZ, Z1 = R.maxZ, KX = L.STAIRS.sideWallX + L.STAIRS.sideWallThickness / 2;
    strip([KX, Z0], [AL.doorway.minX, Z0], [0, 1]);             // N wall, west of the nook doorway
    strip([AL.doorway.maxX, Z0], [X1, Z0], [0, 1]);             // N wall, east of it
    strip([X1, Z0], [X1, Z1], [-1, 0]);                         // E wall
    strip([X1, Z1], [X0, Z1], [0, -1]);                         // S wall
    strip([X0, L.STAIRS.bottomZ], [X0, Z1], [1, 0]);           // W wall at the foot of the stairs
    const cd = L.CLOSET.door;
    strip([KX, Z0], [KX, cd.hingeZ - 0.07], [1, 0]);            // knee wall, north of the closet door
    strip([KX, cd.hingeZ + cd.width + 0.07], [KX, 0.15], [1, 0]); // knee wall, south of it (full height part)
    const mat = new THREE.MeshStandardMaterial({ map, transparent: true, depthWrite: false, roughness: 0.9, metalness: 0, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
    mat.name = 'details_wallGrime';
    const mesh = new THREE.Mesh(mergeGeometries(geos, false), mat);
    mesh.name = 'details_wallGrime'; mesh.renderOrder = 1; mesh.receiveShadow = true; mesh.castShadow = false;
    this.game.scene.add(mesh);
  }

  // ---------------------------------------------------------------------------------------------- carpet wear

  async _carpetWear() {
    const x0 = R.minX, x1 = R.maxX, z0 = R.minZ, z1 = R.maxZ, W = x1 - x0, D = z1 - z0;
    const res = this._low ? 0.02 : 0.0135; // m per pixel
    const cw = Math.round(W / res), chh = Math.round(D / res);
    const c = canvas(cw, chh), g = c.getContext('2d'), img = g.createImageData(cw, chh), d = img.data;
    const lanes = [
      [-3.0, 2.15, -1.7, 1.6], [-1.7, 1.6, -0.3, 1.55], [-0.3, 1.55, 0.6, 1.5], [0.6, 1.5, 1.2, 0.4], [1.2, 0.4, 1.3, -0.9],
      [1.3, -0.9, 1.35, -2.75], [-1.7, 1.6, -2.05, -1.55], [0.6, 1.5, 1.7, 1.15], [1.2, 0.4, -0.5, -1.7], [1.3, -0.9, 2.5, -1.6],
    ];
    const segD = (x, z, s) => {
      const dx = s[2] - s[0], dz = s[3] - s[1], l2 = dx * dx + dz * dz;
      const t = l2 > 0 ? clamp01(((x - s[0]) * dx + (z - s[1]) * dz) / l2) : 0;
      return Math.hypot(x - s[0] - dx * t, z - s[1] - dz * t);
    };
    const spills = [ // x, z, radius, strength, ring, colour [r,g,b]
      [0.72, 1.32, 0.13, 0.42, true, [70, 46, 26]],   // coffee by the sofa
      [-0.95, -0.42, 0.16, 0.38, false, [86, 38, 34]], // juice near the kids corner
      [2.2, 0.75, 0.22, 0.3, false, [58, 50, 40]],     // old dark patch
      [-0.2, 0.6, 0.09, 0.32, true, [74, 52, 30]],
      [1.6, -1.5, 0.2, 0.26, false, [60, 52, 42]],
    ];
    for (let j = 0; j < chh; j++) {
      const z = z0 + (j + 0.5) * res;
      for (let i = 0; i < cw; i++) {
        const x = x0 + (i + 0.5) * res;
        let a = 0;
        let dl = 9; for (const s of lanes) dl = Math.min(dl, segD(x, z, s));
        const lane = Math.exp(-(dl * dl) / 0.075);
        const n1 = fbm(x * 1.6 + 11, z * 1.6 - 3, 4), n2 = fbm(x * 7 + 3, z * 7 + 9, 3);
        a += lane * (0.22 + 0.3 * n1) * (0.7 + 0.6 * n2);
        // big soft blotches in the open carpet (like the reference) + fine grime
        const bl = fbm(x * 0.9 - 7, z * 0.9 + 4, 4);
        a += smooth(0.45, 0.72, bl) * 0.24 * (0.6 + 0.8 * n2);
        a += 0.05 + (n2 - 0.5) * 0.08;
        let r = 58, gg = 48, b = 38;
        for (const [sx, sz, sr, st, ring, sc] of spills) {
          const dd = Math.hypot((x - sx) * (1 + 0.25 * Math.sin(z * 9)), z - sz) / sr + (vnoise(x * 40, z * 40) - 0.5) * 0.25;
          if (dd > 1.6) continue;
          let s = (1 - smooth(0.6, 1.05, dd)) * 0.55 + (ring ? Math.exp(-((dd - 1) ** 2) / 0.01) : 0);
          s *= st;
          if (s > 0.01) { const k = s / (a + s + 1e-4); r += (sc[0] - r) * k; gg += (sc[1] - gg) * k; b += (sc[2] - b) * k; a += s; }
        }
        // under the stairs / closet: nothing (other floors)
        if (x < L.STAIRS.sideWallX + 0.05 && z < L.STAIRS.bottomZ) a = 0;
        const k = (j * cw + i) * 4;
        d[k] = r; d[k + 1] = gg; d[k + 2] = b; d[k + 3] = Math.round(clamp01(a) * 255);
      }
    }
    g.putImageData(img, 0, 0);
    const map = canvasTex(c, { aniso: this._aniso });
    map.flipY = false; // canvas row j = z0 + j*res
    const geo = new THREE.PlaneGeometry(W, D, 1, 1).rotateX(-PI / 2).translate((x0 + x1) / 2, 0.002, (z0 + z1) / 2);
    // uv: u = (x - x0)/W, v = (z - z0)/D (flipY=false) ; uv1 = carpet world uv (x, -z), as Architecture's floor grid
    const p = geo.attributes.position, uv = geo.attributes.uv, uv1 = new Float32Array(p.count * 2);
    for (let i = 0; i < p.count; i++) {
      uv.setXY(i, (p.getX(i) - x0) / W, (p.getZ(i) - z0) / D);
      uv1[i * 2] = p.getX(i); uv1[i * 2 + 1] = -p.getZ(i);
    }
    geo.setAttribute('uv1', new THREE.BufferAttribute(uv1, 2));
    const mat = new THREE.MeshStandardMaterial({ map, roughness: 1, metalness: 0, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
    if (!this._low) {
      const n = this.game.assets.texture('textures/carpet016/normal.jpg', { repeat: [1, 1.00001] }); // own Texture object (channel 1)
      n.channel = 1; n.repeat.set(1, 1);
      mat.normalMap = n; mat.normalScale = new THREE.Vector2(1.1, 1.1);
    }
    mat.name = 'details_carpetWear';
    const mesh = new THREE.Mesh(geo, mat);
    mesh.name = 'details_carpetWear'; mesh.renderOrder = 1; mesh.receiveShadow = true; mesh.castShadow = false;
    this.game.scene.add(mesh);
  }

  // ---------------------------------------------------------------------------------------------- floor clutter

  _clutter() {
    const scene = this.game.scene, Rn = rng(777);
    const rugTop = 0.0072;
    const onRug = (x, z) => x > -2.44 && x < -0.66 && z > -0.09 && z < 1.19;
    const floorY = (x, z) => (onRug(x, z) ? rugTop : 0);
    const geos = [];
    const add = (g, rgb) => geos.push(prep(g, rgb));
    const C = (hex) => { const c = linColor(hex); return [c.r, c.g, c.b]; };

    // crayons (lying on their side; some broken in half, wrapper slightly lighter)
    const cray = [
      [-1.72, 0.32, 0.4, '#2f5fb3', 1], [-1.66, 0.14, 2.2, '#c8352a', 0.6], [-2.28, 0.58, 1.1, '#3f9a3c', 1], [-1.32, -0.22, 2.8, '#7d4ab0', 0.55],
      [-2.4, -1.08, 0.3, '#1c1a1d', 1], [-2.34, -1.2, 1.9, '#ec8a24', 0.5], [-1.92, 2.62, 0.9, '#c8352a', 1], [-2.58, 2.6, 2.4, '#2f5fb3', 0.7],
      [-1.05, 0.95, 1.6, '#e8b81e', 1], [-1.9, 0.98, 0.2, '#e06a94', 0.6],
    ];
    for (const [x, z, ry, hex, len] of cray) {
      const y = floorY(x, z) + 0.0049, L0 = 0.072 * len, col = C(hex);
      const body = new THREE.CylinderGeometry(0.0046, 0.0046, L0, 8);
      const parts = [[body, col]];
      if (len > 0.9) parts.push([new THREE.ConeGeometry(0.0046, 0.013, 8).translate(0, L0 / 2 + 0.0065, 0), col]);
      parts.push([new THREE.CylinderGeometry(0.0049, 0.0049, L0 * 0.62, 8).translate(0, -L0 * 0.1, 0), col.map((v) => v * 0.55 + 0.25)]);
      for (const [gm, cc] of parts) { gm.rotateZ(PI / 2).rotateY(ry).translate(x, y, z); add(gm, cc); }
    }
    // wooden blocks: a toppled tower on the rug + strays under the kid table
    const blocks = [
      [-1.86, 1.02, 0.3, '#b98a55', 0, 0], [-1.8, 0.96, 1.1, '#b8261c', 0, 0], [-1.81, 0.96, 1.25, '#2f5fb3', 1, 0], [-1.93, 1.1, 0.7, '#e8b81e', 0, 0.55],
      [-2.18, 0.08, 0.2, '#3f9a3c', 0, 0], [-2.1, -0.02, 0.9, '#b98a55', 0, 0], [-1.42, 0.08, 0.5, '#b8261c', 0, 0.4],
    ];
    const S = 0.045;
    for (const [x, z, ry, hex, stack, tilt] of blocks) {
      const g = new THREE.BoxGeometry(S, S, S, 1, 1, 1);
      g.rotateZ(tilt).rotateY(ry).translate(x, floorY(x, z) + S / 2 + stack * S + (tilt ? 0.009 : 0), z);
      add(g, C(hex).map((v) => v * (0.9 + Rn() * 0.15)));
    }
    add(new THREE.CylinderGeometry(0.022, 0.022, S, 14).rotateZ(PI / 2).rotateY(0.6).translate(-2.0, rugTop + 0.022, 1.12), C('#b98a55'));
    add(new THREE.CylinderGeometry(0.03, 0.03, S, 3).rotateX(PI / 2).rotateY(2.0).translate(-1.7, rugTop + 0.015, 1.1), C('#3f9a3c'));

    // pull-along toy telephone (cream body, red handset, rotary dial, googly eyes, blue wheels, pull string)
    this._toyPhone(add, C, -2.31, 0.9, -0.5, rugTop);

    // boombox power cord into a new outlet low on the knee wall
    const kx = L.STAIRS.sideWallX + L.STAIRS.sideWallThickness / 2; // room face of the knee wall (-2.5)
    const outletZ = -1.15, outletY = 0.3;
    const plug = new THREE.BoxGeometry(0.022, 0.03, 0.026).translate(kx + 0.017, outletY - 0.022, outletZ);
    add(plug, C('#161616'));
    const cord = new THREE.CatmullRomCurve3([
      new THREE.Vector3(kx + 0.03, outletY - 0.03, outletZ), new THREE.Vector3(kx + 0.035, outletY - 0.12, outletZ + 0.01),
      new THREE.Vector3(kx + 0.03, 0.03, outletZ + 0.03), new THREE.Vector3(kx + 0.05, 0.004, outletZ + 0.1),
      new THREE.Vector3(kx + 0.12, 0.004, outletZ + 0.22), new THREE.Vector3(kx + 0.09, 0.005, -0.84),
      new THREE.Vector3(kx + 0.07, 0.03, -0.78),
    ], false, 'catmullrom', 0.4);
    add(new THREE.TubeGeometry(cord, 48, 0.0028, 6, false), C('#141414'));
    try {
      // wall plate: textured face 6 mm proud of the knee wall (same look as Props' outlets)
      const om = new THREE.MeshStandardMaterial({ map: PT.outletTexture(false), roughness: 0.42 });
      const o = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.115, 0.006).translate(0, 0, 0.003), om);
      o.position.set(kx, outletY, outletZ); o.rotation.y = PI / 2; o.name = 'outlet.knee';
      o.receiveShadow = true; o.castShadow = false;
      scene.add(o);
    } catch (e) { console.warn('[details] outlet', e); }

    const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.55, metalness: 0 });
    mat.name = 'details_clutter';
    const mesh = new THREE.Mesh(mergeGeometries(geos, false), mat);
    mesh.name = 'details_clutter'; mesh.castShadow = true; mesh.receiveShadow = true;
    scene.add(mesh);
    // the phone has a footprint: small collider (it sits in the corner between the kid chair and the knee wall)
    this.world.addCollider([-2.43, 0, 0.79], [-2.19, 0.13, 1.01], 'toy');
  }

  _toyPhone(add, C, px, pz, ry, y0) {
    const m = new THREE.Matrix4().makeRotationY(ry).setPosition(px, y0, pz);
    const put = (g, hex) => { g.applyMatrix4(m); add(g, Array.isArray(hex) ? hex : C(hex)); };
    put(new THREE.BoxGeometry(0.17, 0.07, 0.11).translate(0, 0.055, 0), '#e9e0c8');                 // body
    put(new THREE.BoxGeometry(0.15, 0.012, 0.095).translate(0, 0.095, 0), '#d8cfb6');                // deck
    put(new THREE.CylinderGeometry(0.034, 0.034, 0.006, 20).translate(0.035, 0.104, 0), '#f2ede0');  // dial
    put(new THREE.CylinderGeometry(0.011, 0.011, 0.008, 12).translate(0.035, 0.107, 0), '#c42b22');
    for (let i = 0; i < 8; i++) {
      const a = (i / 10) * TAU + 0.6;
      put(new THREE.SphereGeometry(0.0045, 6, 4).translate(0.035 + Math.cos(a) * 0.024, 0.108, Math.sin(a) * 0.024), '#2a2a2a');
    }
    // handset on its cradle (two ear cups + bar)
    put(new THREE.CylinderGeometry(0.012, 0.012, 0.12, 10).rotateX(PI / 2).translate(-0.045, 0.118, 0), '#c42b22');
    put(new THREE.SphereGeometry(0.022, 12, 8).scale(1, 0.7, 1).translate(-0.045, 0.118, 0.06), '#c42b22');
    put(new THREE.SphereGeometry(0.022, 12, 8).scale(1, 0.7, 1).translate(-0.045, 0.118, -0.06), '#c42b22');
    // googly eyes on the front (+x)
    for (const s of [-1, 1]) {
      put(new THREE.SphereGeometry(0.014, 12, 8).scale(0.5, 1, 1).translate(0.086, 0.06, s * 0.026), '#f4f1ea');
      put(new THREE.SphereGeometry(0.007, 8, 6).scale(0.5, 1, 1).translate(0.092, 0.057, s * 0.024), '#141414');
    }
    // wheels
    for (const [x, z] of [[0.055, 0.058], [-0.055, 0.058], [0.055, -0.058], [-0.055, -0.058]]) {
      put(new THREE.CylinderGeometry(0.02, 0.02, 0.012, 16).rotateX(PI / 2).translate(x, 0.02, z), '#2a55b8');
    }
    // pull string trailing on the floor + red bead, coiled handset cord
    const str = new THREE.CatmullRomCurve3([[0.09, 0.03, 0], [0.13, 0.004, 0.02], [0.22, 0.003, 0.0], [0.3, 0.003, 0.06], [0.36, 0.003, 0.03]].map((p) => new THREE.Vector3(...p)));
    put(new THREE.TubeGeometry(str, 24, 0.0018, 5, false), '#e8dfc0');
    put(new THREE.SphereGeometry(0.009, 10, 8).translate(0.362, 0.009, 0.03), '#c42b22');
    const coil = [];
    for (let i = 0; i <= 60; i++) { const t = i / 60, a = t * TAU * 9; coil.push(new THREE.Vector3(-0.07 - t * 0.03 + Math.cos(a) * 0.006, 0.105 - t * 0.05 + Math.sin(a) * 0.006, -0.06 - t * 0.0)); }
    put(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(coil), 120, 0.0016, 4, false), '#b8261c');
  }

  /** Children's drawings + crumpled paper on the floor around the kid table (one atlas, one draw call). */
  _papers() {
    const scene = this.game.scene;
    const CW = 512, CH = 362, atlas = canvas(CW * 2, 768), g = atlas.getContext('2d');
    g.fillStyle = '#f1ede2'; g.fillRect(0, 0, atlas.width, atlas.height);
    const kinds = [['maison', false], ['mer', false], ['gardienne', true], ['arcenciel', true]];
    kinds.forEach(([k, portrait], i) => {
      try {
        const dr = PT.kidDrawing(k, 300 + i * 7, 0.7072);
        const im = dr.texture.image, x = (i % 2) * CW, y = Math.floor(i / 2) * CH;
        g.save();
        if (portrait) { g.translate(x + CW / 2, y + CH / 2); g.rotate(PI / 2); g.drawImage(im, -CH / 2, -CW / 2, CH, CW); }
        else g.drawImage(im, x, y, CW, CH);
        g.restore();
        dr.texture.dispose?.();
      } catch (e) { /* keep the blank paper */ }
    });
    // bottom strip: lined school paper for the crumpled balls
    g.fillStyle = '#eeeadf'; g.fillRect(0, 724, atlas.width, 44);
    g.fillStyle = 'rgba(80,120,190,0.5)'; for (let y = 728; y < 768; y += 8) g.fillRect(0, y, atlas.width, 1);
    const tex = canvasTex(atlas, { aniso: this._aniso });
    const cell = (i) => [(i % 2) * 0.5, 1 - (Math.floor(i / 2) + 1) * (CH / 768), (i % 2) * 0.5 + 0.5, 1 - Math.floor(i / 2) * (CH / 768)];
    const sheets = [ // x, z, rotY, cell, flip (face down = blank back)
      [-1.76, 0.03, 0.42, 0], [-1.42, -0.32, -0.3, 1], [-2.26, 0.44, 1.25, 2], [-1.74, 0.56, 0.95, 3], [-0.48, -0.55, 2.4, 0],
    ];
    const geos = [];
    const Rn = rng(91);
    for (const [x, z, ry, ci] of sheets) {
      const w = 0.297, h = 0.21;
      const gm = new THREE.PlaneGeometry(w, h, 8, 6).rotateX(-PI / 2);
      const p = gm.attributes.position, uv = gm.attributes.uv, uv1 = new Float32Array(p.count * 2);
      const [u0, v0, u1, v1] = cell(ci);
      const curlA = 0.004 + Rn() * 0.01, curlB = Rn() * 0.008, cx = Rn() < 0.5 ? 1 : -1;
      for (let i = 0; i < p.count; i++) {
        const lx = p.getX(i) / (w / 2), lz = p.getZ(i) / (h / 2);
        const yy = curlA * Math.max(0, lx * cx) ** 2 + curlB * lz * lz + 0.0006 * Math.sin(lx * 9 + lz * 5);
        p.setY(i, Math.max(0, yy));
        const u = uv.getX(i), v = uv.getY(i);
        uv1[i * 2] = u; uv1[i * 2 + 1] = v;
        uv.setXY(i, u0 + (u1 - u0) * u, v0 + (v1 - v0) * v);
      }
      const onRug = x > -2.44 && x < -0.66 && z > -0.09 && z < 1.19;
      gm.rotateY(ry).translate(x, (onRug ? 0.0072 : 0) + 0.0012, z);
      gm.setAttribute('uv1', new THREE.BufferAttribute(uv1, 2));
      gm.computeVertexNormals();
      geos.push(gm);
    }
    for (const [x, z, r] of [[-1.15, -0.3, 0.033], [-2.36, 0.18, 0.028], [-0.62, 1.62, 0.03]]) {
      const gm = new THREE.IcosahedronGeometry(r, 2);
      const p = gm.attributes.position, uv = gm.attributes.uv;
      for (let i = 0; i < p.count; i++) {
        const v = new THREE.Vector3().fromBufferAttribute(p, i);
        const k = 1 + (vnoise(v.x * 120 + x * 10, v.y * 120 + v.z * 90) - 0.5) * 0.55;
        p.setXYZ(i, v.x * k, v.y * k * 0.85, v.z * k);
        uv.setXY(i, 0.02 + Rn() * 0.96, 0.005 + Rn() * 0.05);
      }
      gm.deleteAttribute('normal'); gm.computeVertexNormals();
      const onRug = x > -2.44 && x < -0.66 && z > -0.09 && z < 1.19;
      gm.translate(x, (onRug ? 0.0072 : 0) + r * 0.8, z);
      const uv1 = new Float32Array(p.count * 2); for (let i = 0; i < p.count; i++) { uv1[i * 2] = Rn(); uv1[i * 2 + 1] = Rn(); }
      gm.setAttribute('uv1', new THREE.BufferAttribute(uv1, 2));
      geos.push(gm);
    }
    // mergeGeometries needs identical attribute sets (Icosahedron is non-indexed): normalise to non-indexed
    const flat = geos.map((gm) => (gm.index ? gm.toNonIndexed() : gm));
    const mat = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.9, metalness: 0, side: THREE.DoubleSide });
    try {
      const n = this.game.assets.texture('textures/paper003/normal.jpg', { repeat: [1, 1.0001] });
      n.channel = 1; n.repeat.set(1, 1); mat.normalMap = n; mat.normalScale = new THREE.Vector2(0.6, 0.6);
    } catch (e) { /* optional */ }
    mat.name = 'details_papers';
    const mesh = new THREE.Mesh(mergeGeometries(flat, false), mat);
    mesh.name = 'details_papers'; mesh.receiveShadow = true; mesh.castShadow = false;
    scene.add(mesh);
  }

  /** Stray sock (fabric) + dust bunnies (fluffy alpha-tested crossed cards) along furniture feet and wall bases. */
  _fabricAndDust() {
    const scene = this.game.scene, A = this.game.assets, Rn = rng(5150);
    // sock: small striped child's sock near the sofa
    const curve = new THREE.CatmullRomCurve3([[0, 0.012, 0], [0.07, 0.012, 0.01], [0.13, 0.013, -0.005], [0.16, 0.014, -0.04], [0.165, 0.012, -0.07]].map((p) => new THREE.Vector3(...p)));
    const sg = new THREE.TubeGeometry(curve, 24, 0.017, 10, false);
    const sp = sg.attributes.position;
    const cols = new Float32Array(sp.count * 3);
    for (let i = 0; i < sp.count; i++) {
      const t = Math.floor(i / 11) / 24;
      const stripe = t < 0.3 && Math.floor(t * 30) % 2 === 0;
      const c = stripe ? [0.55, 0.06, 0.05] : [0.78, 0.76, 0.7];
      cols[i * 3] = c[0]; cols[i * 3 + 1] = c[1]; cols[i * 3 + 2] = c[2];
      sp.setY(i, Math.max(0.0015, sp.getY(i) * 0.55));
    }
    sg.setAttribute('color', new THREE.BufferAttribute(cols, 3));
    sg.computeVertexNormals();
    sg.rotateY(2.3).translate(-0.42, 0, 1.68);
    const fabric = A.pbr('fabric032', [6, 2], { vertexColors: true, roughness: 1 });
    fabric.name = 'details_sock';
    const sock = new THREE.Mesh(sg, fabric);
    sock.name = 'details_sock'; sock.castShadow = true; sock.receiveShadow = true;
    scene.add(sock);

    // dust bunnies
    const fl = canvas(128, 128), g = fl.getContext('2d');
    g.translate(64, 64);
    // tangled fibres around a small dense core (alpha-tested: only the strands and the core survive)
    for (let i = 0; i < 170; i++) {
      const a = Rn() * TAU, r0 = Rn() * 12, r1 = 18 + Rn() * 42, bend = (Rn() - 0.5) * 1.6;
      g.strokeStyle = `rgba(255,255,255,${0.45 + Rn() * 0.5})`; g.lineWidth = 0.7 + Rn() * 0.9;
      g.beginPath(); g.moveTo(Math.cos(a) * r0, Math.sin(a) * r0 * 0.8);
      g.quadraticCurveTo(Math.cos(a + bend) * r1 * 0.6, Math.sin(a + bend) * r1 * 0.5, Math.cos(a + bend * 1.5) * r1, Math.sin(a + bend * 1.5) * r1 * 0.75);
      g.stroke();
    }
    const gr = g.createRadialGradient(0, 4, 0, 0, 4, 14); gr.addColorStop(0, 'rgba(255,255,255,0.9)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr; g.beginPath(); g.ellipse(0, 4, 16, 11, 0, 0, TAU); g.fill();
    const spots = [ // x, z, size
      [-0.95, 1.83, 0.05], [0.4, 1.84, 0.04], [1.35, 1.82, 0.06], [-1.05, -2.12, 0.045], [-0.1, -2.13, 0.035], [3.15, -0.25, 0.05],
      [3.22, 0.62, 0.04], [2.72, -2.3, 0.04], [-2.46, -1.45, 0.04], [-3.25, 1.64, 0.05], [3.42, 2.66, 0.05], [-1.72, 2.2, 0.035],
      [0.32, -4.5, 0.07], [3.4, -2.98, 0.06], [1.3, -4.02, 0.05], [2.95, -3.7, 0.05], [-3.2, -1.6, 0.06],
    ];
    const geos = [];
    for (const [x, z, s] of spots) {
      const sh = 0.55 + Rn() * 0.2, col = [0.32 * sh + 0.1, 0.3 * sh + 0.09, 0.28 * sh + 0.08];
      for (let k = 0; k < 3; k++) {
        const q = new THREE.PlaneGeometry(s * 1.8, s * 0.75);
        q.translate(0, s * 0.27, 0).rotateX(-0.35 + Rn() * 0.25).rotateY((k / 3) * PI + Rn() * 0.4).translate(x, 0, z);
        geos.push(prep(q, col));
      }
      const flat = new THREE.PlaneGeometry(s * 2.2, s * 2.2).rotateX(-PI / 2).rotateY(Rn() * TAU).translate(x, 0.0025, z);
      geos.push(prep(flat, col.map((v) => v * 0.9)));
    }
    const dm = new THREE.MeshStandardMaterial({ map: canvasTex(fl, { aniso: 2 }), vertexColors: true, alphaTest: 0.32, side: THREE.DoubleSide, roughness: 1, metalness: 0 });
    dm.name = 'details_dust';
    const dust = new THREE.Mesh(mergeGeometries(geos, false), dm);
    dust.name = 'details_dust'; dust.castShadow = false; dust.receiveShadow = true;
    scene.add(dust);
  }

  // ---------------------------------------------------------------------------------------------- contract

  update(dt) {
    this._time = (this._time || 0) + dt;
    if (!this._hallLightMoved) {
      // Lighting builds after us: move its hallway light (doorLight at the open door) into the pendant's bulb
      const lt = this.world.lighting;
      if (lt?._hallPos && this.objects.hallLamp) { lt._hallPos.fromArray(L.HALL_LAMP_BULB); this._hallLightMoved = true; }
      else if (lt?.ceiling) this._hallLightMoved = true;
    }
    this._updateTube(dt);
  }

  reset(kind) {
    void kind;
    this._powerOn = this.world.power !== false;
    if (this.tube) {
      if (this._powerOn && this.tube.mode !== 'on') { this.tube.mode = 'on'; this.tube.burst = 0; }
      if (!this._powerOn) this.tube.mode = 'off';
    }
  }

  setPower(on) {
    on = !!on;
    const was = this._powerOn;
    this._powerOn = on;
    const T = this.tube;
    if (!T) return;
    if (!on) T.mode = 'off';
    else if (!was || T.mode === 'off') { T.mode = 'start'; T.t = 0; T.seq = this._tubeSequence(); T.seqI = -1; }
  }
}
