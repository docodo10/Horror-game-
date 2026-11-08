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
  // ---- batch 2 (see assets/NEW_ASSETS.md for placement notes) ----
  boombox:                  { size: [0.724, 0.47, 0.186], min: [-0.362, 0, -0.073] },
  gamepad:                  { size: [0.404, 0.019, 0.435], min: [-0.211, -0.001, -0.214] },
  baseball_bat:             { size: [0.064, 0.913, 0.064], min: [-0.032, -0.254, -0.032] },
  football:                 { size: [0.509, 0.222, 0.222], min: [-0.249, 0, -0.112], nodes: ['football_deflated', 'football_inflated'] }, // two variants side by side: keep one
  ornate_mirror_01:         { size: [0.486, 0.744, 0.026], min: [-0.243, -0.411, 0] }, // origin = hang point, back z=0; glass z~0.007 x±0.219 y[-0.386,0.299]
  hanging_picture_frame_02: { size: [0.752, 0.5, 0.033], min: [-0.376, -0.279, 0.002] }, // child meshes: _artwork (canvas, v 0.223-0.801, flipY=false), _glass
  garden_gnome:             { size: [0.257, 0.599, 0.21], min: [-0.144, 0, -0.098] },
  Television_01:            { size: [0.6, 0.457, 0.471], min: [-0.3, 0, -0.258] }, // old CRT; screen x[-0.257,0.126] y[0.114,0.404] z~0.19
  pull_chain_light_socket:  { size: [0.11, 0.165, 0.11], min: [-0.055, -0.165, -0.055], nodes: ['pull_chain_light_socket', 'pull_chain_light_socket_chain'] }, // origin = ceiling mount
  metal_toolbox:            { size: [0.4, 0.305, 0.271], min: [-0.2, 0, -0.157], nodes: ['metal_toolbox', 'metal_toolbox_tray', 'metal_toolbox_lid'] }, // lid authored OPEN -> identity = closed
  plastic_crate_02:         { size: [0.506, 0.254, 0.406], min: [-0.253, 0, -0.203] }, // laundry basket; use alphaTest 0.5 + DoubleSide
  bleach_bottle:            { size: [0.088, 0.294, 0.061], min: [-0.044, 0, -0.031] },
  plastic_bottle_gallon:    { size: [0.166, 0.274, 0.126], min: [-0.088, 0, -0.065] },
  can_rusted:               { size: [0.125, 0.151, 0.125], min: [-0.062, -0.001, -0.061] },
  mousetrap:                { size: [0.055, 0.018, 0.1], min: [-0.027, 0, -0.05] },
  painted_wooden_stool:     { size: [0.385, 0.579, 0.406], min: [-0.187, -0.001, -0.19] },
  wooden_broom:             { size: [0.49, 1.453, 0.113], min: [-0.245, -0.122, -0.056], nodes: ['wooden_broom_handle', 'wooden_broom_bristles', 'wooden_broom'] }, // stand at y=0.122
  vintage_suitcase:         { size: [1.608, 0.568, 0.239], min: [-0.803, 0, -0.129] }, // two cases side by side: hide one case's 4 nodes (vintage_suitcase_0N_*)
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
  // ---- batch 2 (assets/NEW_ASSETS.md §1: tile sizes and tint advice) ----
  paintedwood009c:         'worn white painted wood (door, trims, baseboards, balusters, risers) — tint up for fresh paint',
  painted_concrete_02:     'grey painted concrete floor (laundry nook)',
  paintedbricks004:        'painted concrete block wall (nook walls, tint the colour)',
  metal048c:               'aged brass (metal.jpg): key, padlock, knob, hinges',
  metal049b:               'smeared chrome/nickel (metal.jpg): flashlight bezel, faucet, latch',
  metal039:                'galvanized steel (metal.jpg): ducts, water heater',
  metal043b:               'dirty copper (metal.jpg): water pipes',
  metal055b:               'rusty dark iron (metal.jpg): window bars, gas pipe',
  rusty_metal_02:          'rusty white-painted metal: drain stack, old appliances',
  wallpaper001a:           'woodchip wallpaper (upstairs hallway, tint warm)',
  plywood:                 'plywood (closet under stairs, shelves, studs)',
  snow011:                 'dirty snow + soil patches (outside the window)',
  surfaceimperfections003: 'window grime (alpha.jpg opacity mask)',
  fabric032:               'off-white woven cotton (nightgown, curtains, laundry)',
  cardboard004:            'cardboard (boxes)',
  paper003:                'creased paper (use normal+rough under canvas text)',
  plastic013b:             'scratched white plastic (tint: toys, switch plates, detector)',
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
    const { metal = false, ...rest } = opts; // metal: true -> load metal.jpg as metalnessMap (metal sets only)
    if (metal) {
      rest.metalness = rest.metalness ?? 1;
      rest.metalnessMap = this.texture(p + 'metal.jpg', { repeat });
    }
    const mat = new THREE.MeshStandardMaterial({
      map: this.texture(p + 'color.jpg', { srgb: true, repeat }),
      normalMap: this.texture(p + 'normal.jpg', { repeat }),
      roughnessMap: this.texture(p + 'rough.jpg', { repeat }),
      aoMap: this.texture(p + 'ao.jpg', { repeat }),
      aoMapIntensity: 0.8,
      roughness: 1,
      metalness: 0,
      ...rest,
    });
    mat.name = setId;
    return mat;
  }
}
