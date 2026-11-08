import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// Photoscanned CC0 models from Poly Haven, optimized to GLB + webp textures (assets/models/<id>.glb).
// size = bounding box [x, y, z] in meters at scale 1, min = bbox min corner. Front faces +Z.
// Named child nodes are listed when they matter (they can be animated independently).
export const MODELS = {
  sofa_03:                     { size: [2.731, 1.118, 0.925], min: [-1.366, 0.001, -0.464] },
  throw_pillows_01:            { size: [0.94, 0.45, 0.452], min: [-0.464, -0.002, -0.176], nodes: ['throw_pillows_01_pillow01', 'throw_pillows_01_pillow02'] },
  small_wooden_table_01:       { size: [0.916, 0.533, 0.44], min: [-0.458, 0, -0.22] },
  painted_wooden_nightstand:   { size: [0.505, 0.616, 0.509], min: [-0.253, 0, -0.249], nodes: ['painted_wooden_nightstand_drawer'] }, // drawer slides +Z
  GothicCommode_01:            { size: [1.201, 1.212, 0.581], min: [-0.602, 0, -0.289], nodes: ['GothicCommode_01_door01' /*top drawer y~0.99*/, 'GothicCommode_01_door02' /*mid*/, 'GothicCommode_01_door03' /*bottom*/] }, // the "doorNN" nodes are drawers sliding +Z
  television_02:               { size: [0.4, 0.411, 0.35], min: [-0.202, 0, -0.228] }, // small CRT, screen faces +Z (front at z≈0.122)
  standing_picture_frame_01:   { size: [0.1, 0.25, 0.201], min: [-0.062, 0, -0.1] },
  vintage_grandfather_clock_01:{ size: [0.626, 2.191, 0.427], min: [-0.313, 0, -0.188], nodes: ['vintage_grandfather_clock_01_Body', 'vintage_grandfather_clock_01_HourHand', 'vintage_grandfather_clock_01_MinuteHand'] }, // hands pivot at (0,1.732,0.126), rotate around local Z
  painted_wooden_shelves:      { size: [0.511, 1.125, 0.367], min: [-0.256, -0.001, 0] },
  book_encyclopedia_set_01:    { size: [0.551, 0.237, 0.163], min: [-0.019, 0, -0.062] },
  horse_statue_01:             { size: [0.163, 0.22, 0.108], min: [-0.085, 0, -0.054] },
  ClassicConsole_01:           { size: [1.543, 0.949, 0.589], min: [-0.771, 0, -0.338] },
  CheeseBox_01:                { size: [0.24, 0.066, 0.107], min: [-0.12, 0, -0.053], nodes: ['CheeseBox_01', 'CheeseBox_01_lid'] }, // lid is a separate node (origin ~ box origin)
  painted_wooden_chair_02:     { size: [0.639, 1.264, 0.662], min: [-0.335, 0, -0.363] },
  painted_wooden_chair_01:     { size: [0.432, 0.956, 0.54], min: [-0.217, -0.001, -0.301] },
  hanging_picture_frame_03:    { size: [0.385, 0.502, 0.032], min: [-0.192, -0.255, 0] },
  fancy_picture_frame_01:      { size: [0.603, 0.464, 0.02], min: [-0.302, -0.232, 0.002] },
  Rockingchair_01:             { size: [0.708, 0.995, 0.833], min: [-0.354, 0.102, -0.354] },
  side_table_01:               { size: [0.55, 0.551, 0.45], min: [-0.275, -0.002, -0.225] },
  rubber_duck_toy:             { size: [0.214, 0.286, 0.3], min: [-0.107, 0, -0.146] },
  alarm_clock_01:              { size: [0.132, 0.174, 0.067], min: [-0.066, -0.001, -0.024], nodes: ['houd_hand', 'minute_hand', 'second_hand'] },
  ceiling_fan:                 { size: [1.463, 0.516, 1.463], min: [-0.732, -0.516, -0.731], nodes: ['ceiling_fan', 'ceiling_fan_blades'] }, // origin = ceiling mount; light kit at bottom (y≈-0.5)
  painted_wooden_cabinet:      { size: [1.195, 1.182, 0.617], min: [-0.595, 0, -0.282], nodes: ['painted_wooden_cabinet_door_01' /*left, hinge at its node origin x=-0.568*/, 'painted_wooden_cabinet_door_02' /*right, hinge x=+0.568*/, 'painted_wooden_cabinet_drawer_01', 'painted_wooden_cabinet_drawer_02'] },
  power_box_01:                { size: [0.461, 0.503, 0.399], min: [-0.286, -0.252, -0.047], nodes: ['power_box_01_box', 'power_box_01_door' /*hinge at node origin (-0.164,0,0.043); authored OPEN (quat y=-0.815) -> set rotation to identity for closed*/] },
  Shelf_01:                    { size: [1.003, 2.08, 0.257], min: [-0.502, 0, 0] },
  cardboard_box_01:            { size: [0.387, 0.342, 0.516], min: [-0.193, -0.007, -0.225] },
  lightbulb_01:                { size: [0.06, 0.1, 0.06], min: [-0.03, -0.017, -0.03] },
  portable_cassette_player:    { size: [0.172, 0.13, 0.04], min: [-0.064, -0.056, -0.017] },
  pastic_torch_6v:             { size: [0.137, 0.142, 0.224], min: [-0.068, -0.07, -0.095] }, // yellow 6V lantern flashlight, lens toward +Z
  CoffeeTable_01:              { size: [1.54, 0.523, 0.973], min: [-0.77, 0.002, -0.486] },
};

// Tileable PBR texture sets (assets/textures/<id>/{color,normal,rough,ao}.jpg), 1024px.
export const TEXTURE_SETS = {
  carpet016:        'beige plush carpet (main floor, stair treads)',
  dirty_carpet:     'dark worn carpet / fabric',
  beige_wall_001:   'beige painted plaster (walls)',
  white_stucco:     'white orange-peel stucco (ceiling, alt walls)',
  ceiling_interior: 'popcorn ceiling (brownish, tint lighter)',
  wood_floor_worn:  'worn wood planks (stair treads, alcove floor)',
  stained_pine:     'stained pine wood (handrail, trims, door)',
};

export class Assets {
  constructor(game) {
    this.game = game;
    this.base = game.params?.assetBase ?? './assets/';
    this.loader = new GLTFLoader();
    this.texLoader = new THREE.TextureLoader();
    this.models = new Map();   // id -> THREE.Group (pristine)
    this.textures = new Map(); // path -> THREE.Texture
  }

  /** Preload every model in MODELS. onProgress(0..1). */
  async preload(onProgress = () => {}) {
    const ids = Object.keys(MODELS);
    let done = 0;
    await Promise.all(ids.map(async (id) => {
      try { await this.loadModel(id); }
      catch (e) { console.error('model failed', id, e); }
      done++; onProgress(done / ids.length);
    }));
  }

  async loadModel(id) {
    if (this.models.has(id)) return this.models.get(id);
    const gltf = await this.loader.loadAsync(`${this.base}models/${id}.glb`);
    const root = gltf.scene;
    root.name = id;
    root.traverse((o) => {
      if (o.isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) {
          if (m.map) m.map.anisotropy = this.game.renderer?.maxAnisotropy ?? 4;
          m.envMapIntensity = 1.0;
        }
      }
    });
    this.models.set(id, root);
    return root;
  }

  /**
   * Returns a NEW instance of a preloaded model (geometry/materials shared with other instances).
   * Pass { uniqueMaterials: true } when you will tweak materials on this instance only.
   */
  instance(id, { uniqueMaterials = false } = {}) {
    const src = this.models.get(id);
    if (!src) throw new Error(`Model not loaded: ${id}`);
    const obj = src.clone(true);
    if (uniqueMaterials) {
      obj.traverse((o) => {
        if (o.isMesh) o.material = Array.isArray(o.material) ? o.material.map((m) => m.clone()) : o.material.clone();
      });
    }
    return obj;
  }

  /** Load (cached) a texture. srgb=true for color maps. */
  texture(path, { srgb = false, repeat = null, wrap = true } = {}) {
    const key = `${path}|${srgb}|${repeat ? repeat.join('x') : ''}`;
    if (this.textures.has(key)) return this.textures.get(key);
    const t = this.texLoader.load(this.base + path);
    if (srgb) t.colorSpace = THREE.SRGBColorSpace;
    if (wrap) { t.wrapS = t.wrapT = THREE.RepeatWrapping; }
    if (repeat) t.repeat.set(repeat[0], repeat[1]);
    t.anisotropy = this.game.renderer?.maxAnisotropy ?? 4;
    this.textures.set(key, t);
    return t;
  }

  /**
   * Build a MeshStandardMaterial from a texture set id (see TEXTURE_SETS).
   * repeat: [u, v] tiling; opts are passed to MeshStandardMaterial (e.g. color tint, roughness multiplier).
   * The AO map uses uv channel 0 (three r170 supports material.aoMap with any uv via texture.channel).
   */
  pbr(setId, repeat = [1, 1], opts = {}) {
    const p = `textures/${setId}/`;
    const mat = new THREE.MeshStandardMaterial({
      map: this.texture(p + 'color.jpg', { srgb: true, repeat }),
      normalMap: this.texture(p + 'normal.jpg', { repeat }),
      roughnessMap: this.texture(p + 'rough.jpg', { repeat }),
      aoMap: this.texture(p + 'ao.jpg', { repeat }),
      aoMapIntensity: 0.8,
      roughness: 1,
      metalness: 0,
      ...opts,
    });
    mat.name = setId;
    return mat;
  }
}
