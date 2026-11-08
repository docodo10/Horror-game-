# New photoreal assets (batch 2): Poly Haven + ambientCG

All items below are **CC0** (public domain). They were downloaded from Poly Haven / ambientCG and picked by looking at
preview contact sheets. They are **not wired into the code yet**: to use them, register them in `src/core/Assets.js`
(`MODELS`, `TEXTURE_SETS`) and place them via `src/config/layout.js` → `Props.js` / `Architecture.js`.
The ready-to-paste registry lines and the placement plan are below.

| | count | size on disk | budget |
|---|---|---|---|
| Texture sets (`assets/textures/<id>/`) | 17 | **8.68 MB** | ≤ 9 MB |
| Models (`assets/models/<id>.glb`) | 18 | **5.56 MB** | ≤ 7 MB |

Processing:
* **Textures**: source 1K maps (Poly Haven `*_1k.jpg`, ambientCG `*_1K-JPG.zip`) → 1024×1024 JPEG q84, same naming as the
  existing sets: `color.jpg` (sRGB), `normal.jpg` (**OpenGL** convention, PH `nor_gl` / ACG `NormalGL`), `rough.jpg`,
  `ao.jpg`, plus `metal.jpg` for metals and `alpha.jpg` for the window-grime overlay. When a source has no AO map,
  `ao.jpg` is flat white (4 kB), like `stained_pine`.
* **Models**: Poly Haven glTF 1k → the existing pipeline (dedup/prune/weld, meshopt simplify of meshes > 12k tris to ~9k,
  WebP textures 512 or 1024 px). Script: `scratchpad/tools/opt_new.mjs` (a copy of `opt.mjs` with per-model texture size,
  a lower triangle target for three tiny over-tessellated props, and a looser error for the broom).
  One asset fix: `hanging_picture_frame_02`'s glass material reused the frame's opaque diffuse/ARM textures in the source
  glTF, which hid the artwork. It is now a clear glass (white, alpha 0.08, metal 0, rough 0.05, no textures).
* Every GLB was rendered headless (three r170, RoomEnvironment) to check it. Fronts face **+Z** like the existing models.

---

## 1. Texture sets

`assets.pbr(id, [u, v], opts)` loads `color/normal/rough/ao`. For metals, also pass
`{ metalness: 1, metalnessMap: assets.texture('textures/<id>/metal.jpg', { repeat: [u, v] }) }`. The metal maps are
nearly uniform except `metal043b`, which has non-metallic oxide spots. With `metalness: 1` alone, the metals are already
good. **"Tile"** is the real-world size of one texture repeat. With world-unit UVs, `repeat = 1 / tile`.

| id | source | use in La Gardienne | tile | maps | notes |
|---|---|---|---|---|---|
| `paintedwood009c` | ambientCG PaintedWood009C | **white painted wood**: upstairs 6-panel door, casings, baseboards, balusters, stair risers, louvered closet door, window frame | ~1.0 m | c n r ao | Worn off-white (mean sRGB 179,166,150) with fine wood grain and a few cracks. For fresher 90s satin paint, use `color: new THREE.Color(1.25, 1.25, 1.3)` (values > 1 are allowed), `roughness: 0.8`. Keep it as is for grimy trims near the floor. 643 kB |
| `painted_concrete_02` | Poly Haven painted_concrete_02 | **laundry nook floor** (grey painted concrete, worn, a few stains) | 4 m (source); use **2–2.5 m** for crisper detail | c n r ao | Mean sRGB 86,83,76. Good with a puddle/water-heater stain decal. 344 kB |
| `paintedbricks004` | ambientCG PaintedBricks004 | **nook walls**: painted concrete block / foundation wall | 1.55 m true scale (blocks 0.29×0.13 m); use **~2.3 m** to read as cinder blocks (≈0.43×0.19 m) | c n r ao | The colour map is an almost flat blue-grey paint (153,165,175). Tint it (e.g. `color: 0xf3ecdf` for old cream paint) or replace it with a flat colour; the relief is in normal/ao/rough. 577 kB |
| `metal048c` | ambientCG Metal048C | **aged brass**: upstairs door key, combination padlock body, door knob + hinges, cabinet hinges, battery contacts | ~0.3 m (small parts: repeat 2–4 per object) | c n r ao **metal** | Gold-brass, impure, dark specks; roughness ~0.28. 326 kB |
| `metal049b` | ambientCG Metal049B | **chrome / nickel with smears**: flashlight bezel and reflector, faucet on the laundry tub, window latch, TV antenna | ~0.5 m | c n r ao **metal** | Near-mirror (rough ~0.12) with fingerprint smears. Nice under the flashlight. 129 kB |
| `metal039` | ambientCG Metal039 | **galvanized steel** (zinc spangle): dryer vent duct, HVAC trunk duct along the nook ceiling, water-heater jacket, joist hangers | ~1.0 m | c n r ao **metal** | Mean grey 125, rough ~0.64. 651 kB |
| `metal043b` | ambientCG Metal043B | **dirty copper**: water supply pipes on the nook ceiling, washer valves | ~0.5–1 m (pipes: repeat along the length) | c n r ao **metal** | The metal map has oxidised non-metal spots (mean 0.96), so use `metalnessMap`. 818 kB |
| `metal055b` | ambientCG Metal055B | **dark iron with rust streaks**: window bars, black gas pipe, furnace parts, padlock shackle, coat hooks | ~1.0 m | c n r ao **metal** | Bright steel colour with rust drips; darken with `color: 0x5a5856` for blackened iron. 307 kB |
| `rusty_metal_02` | Poly Haven rusty_metal_02 | **rusty painted metal**: drain/sewer stack, old washer/dryer base, sump-pit lid, water-heater base, alternative window bars | 1.0 m | c n r ao | White paint with orange rust bloom. No metal map: use `metalness: 0.1`. 617 kB |
| `wallpaper001a` | ambientCG Wallpaper001A | **upstairs hallway wallpaper** (woodchip / textured wallpaper, very 80s–90s) | ~0.6 m | c n r ao | Neither Poly Haven nor ambientCG has a floral or striped CC0 wallpaper. Tint warm (`color: 0xe9dcc0`). For stripes or florals, draw the print in a canvas and use it as `map`, keeping this set's normal/rough/ao for the paper relief. 354 kB |
| `plywood` | Poly Haven plywood | **closet under the stairs**: interior walls, underside of the stair stringers, shelves; studs and patch panels in the nook | 0.5 m | c n r ao | Birch-ish plywood, mean 126,97,65. 849 kB |
| `snow011` | ambientCG Snow011 | **ground outside the barred window**: dirty trampled snow with dark soil and dead-grass patches showing through (Québec winter) | ~2 m | c n r ao | Seen only through the window under moonlight; blue-white (168,171,181). 1054 kB |
| `surfaceimperfections003` | ambientCG SurfaceImperfections003 | **window grime**: dirty glass of the basement window (vertical run-off streaks) | stretch 1 tile over the 1.0×0.5 m pane (`repeat [1, 0.5]`) | c n r ao **alpha** | `alpha.jpg` = grime opacity mask (source Opacity). `rough.jpg` is derived from it (0.06 clean → 0.9 grime). Use it either as an overlay plane just inside the glass (`transparent: true, alphaMap, color: 0x3a3428, depthWrite: false`), or as the glass `roughnessMap` so moonlight highlights break up on the dirt. 534 kB |
| `fabric032` | ambientCG Fabric032 | **off-white woven cotton / linen**: La Gardienne's nightgown, basement window curtain, clothes in the laundry basket, pillowcases | ~0.3 m (fine weave) | c n r ao | Mean 229,223,222 (slightly pink-white). For the stained gown, multiply a procedural grime gradient into `color`. 967 kB |
| `cardboard004` | ambientCG Cardboard004 | **cardboard**: procedural box variants, flattened boxes in the closet, the backing of the child's drawings | ~0.5 m | c n r ao | Kraft brown with vertical flutes and a few scuffs. 310 kB |
| `paper003` | ambientCG Paper003 | **creased paper**: notes 1–3, the child's drawing sheet, newspaper base | 1 tile per sheet (~0.3 m) | c n r ao | Keep the canvas text texture as `map` and use this set's **normal + rough** for the creases (normalScale ~0.6). 76 kB |
| `plastic013b` | ambientCG Plastic013B | **scratched white plastic** (tint with `color`): toys, light-switch / outlet covers, smoke detector, thermostat, flashlight body, laundry tub | ~0.5 m | c n r ao | Mean 236,230,229, rough ~0.45 with fine scratches. 325 kB |

Ready-to-paste `TEXTURE_SETS` entries (`src/core/Assets.js`, core owner):
```js
  paintedwood009c:         'worn white painted wood (door, trims, baseboards, balusters, risers)',
  painted_concrete_02:     'grey painted concrete floor (laundry nook)',
  paintedbricks004:        'painted concrete block wall (nook walls, tint the colour)',
  metal048c:               'aged brass (+metal.jpg): key, padlock, knob, hinges',
  metal049b:               'smeared chrome/nickel (+metal.jpg): flashlight bezel, faucet, latch',
  metal039:                'galvanized steel (+metal.jpg): ducts, water heater',
  metal043b:               'dirty copper (+metal.jpg): water pipes',
  metal055b:               'rusty dark iron (+metal.jpg): window bars, gas pipe',
  rusty_metal_02:          'rusty white-painted metal: drain stack, old appliances',
  wallpaper001a:           'woodchip wallpaper (upstairs hallway, tint warm)',
  plywood:                 'plywood (closet under stairs, shelves, studs)',
  snow011:                 'dirty snow + soil patches (outside the window)',
  surfaceimperfections003: 'window grime (+alpha.jpg opacity mask)',
  fabric032:               'off-white woven cotton (nightgown, curtains, laundry)',
  cardboard004:            'cardboard (boxes)',
  paper003:                'creased paper (notes: use normal+rough under the canvas text)',
  plastic013b:             'scratched white plastic (tint: toys, switch plates, detector)',
```

---

## 2. Models

`size` = bounding box [x, y, z] in metres at scale 1, `min` = bbox min corner (same convention as `MODELS`). Front = +Z.

| id | what | size [x,y,z] | min | tris / tex / kB | animatable child nodes & material notes |
|---|---|---|---|---|---|
| `boombox` | 80s–90s dual-speaker boombox with cassette deck and antenna | [0.724, 0.47, 0.186] | [-0.362, 0, -0.073] | 10168 / 1024 / 754 | single node. Materials `boombox` + `boombox_speakers` (alpha MASK grilles) |
| `gamepad` | retro wired grey gamepad (SNES-era) with coiled cable and plug | [0.404, 0.019, 0.435] | [-0.211, -0.001, -0.214] | 9546 / 512 / 291 | single node; lies flat; no collider needed |
| `baseball_bat` | worn wooden baseball bat | [0.064, 0.913, 0.064] | [-0.032, -0.254, -0.032] | 2672 / 512 / 135 | single node (authored with a 90° X rotation; the knob end is at y = -0.254, the barrel up) |
| `football` | battered soccer ball, **two variants side by side** | [0.509, 0.222, 0.222] | [-0.249, 0, -0.112] | 4296 / 512 / 269 | `football_deflated` (origin at its bottom, node x = -0.15) and `football_inflated` (origin at its centre, node (0.15, 0.111, 0)). Keep one: hide the other and zero the kept node's x |
| `ornate_mirror_01` | Victorian arched mirror, gilded crest, **real mirror glass** | [0.486, 0.744, 0.026] | [-0.243, -0.411, 0] | 9000 / 512 / 297 | single mesh. Origin = hanging point; back at z = 0 (flush to the wall). **Glass**: plane at local z ≈ 0.007, x ∈ [-0.219, 0.219], y ∈ [-0.386, 0.299]; straight sides up to y ≈ 0.19, then an arch to 0.299 at the centre. See § 4 for live reflections |
| `hanging_picture_frame_02` | distressed white wooden frame with a landscape print behind glass | [0.752, 0.5, 0.033] | [-0.376, -0.279, 0.002] | 3678 / 512 / 180 | one node, 3 primitives (three.js splits them into child meshes): `hanging_picture_frame_02_artwork` (photo plane 0.605×0.354 m at z = 0.009), `hanging_picture_frame_02` (frame), `hanging_picture_frame_02_glass` (clear, alpha 0.08). Artwork UVs: u 0.007–0.993, **v 0.223–0.801** (glTF top-left origin). To show a procedural family photo, set `canvasTexture.flipY = false` and draw the photo in the canvas band y ∈ [22.3 %, 80.1 %] (aspect 1.71:1) |
| `garden_gnome` | ceramic garden gnome holding a lantern (creepy smile) | [0.257, 0.599, 0.21] | [-0.144, 0, -0.098] | 9000 (from 28.9k) / 512 / 328 | single node |
| `Television_01` | vintage tabletop CRT TV, wood-grain case, knobs (old/broken TV) | [0.6, 0.457, 0.471] | [-0.3, 0, -0.258] | 1918 / 1024 / 298 | single node; has **vertex colours** (COLOR_0, GLTFLoader enables `vertexColors`). **Screen**: x ∈ [-0.257, 0.126], y ∈ [0.114, 0.404], curved glass up to z = 0.192. For static or a ghost image, put an emissive plane (0.37×0.28) at (-0.066, 0.259, 0.195) |
| `pull_chain_light_socket` | porcelain pull-chain ceiling socket with brass chain | [0.11, 0.165, 0.11] | [-0.055, -0.165, -0.055] | 6184 / 512 / 266 | `pull_chain_light_socket` (base, y ∈ [-0.051, 0]) + `pull_chain_light_socket_chain` (chain hangs from about (-0.023, -0.019, 0) down to y = -0.165). Origin = ceiling mount. For a sway or a pull, put the chain under a pivot at its top |
| `metal_toolbox` | vintage olive metal toolbox, brass latches, lift-out tray | [0.4, 0.305, 0.271] (open) | [-0.2, 0, -0.157] | 9128 / 512 / 428 | `metal_toolbox` (body), `metal_toolbox_tray`, `metal_toolbox_lid` (**authored OPEN**: quaternion (-0.473, 0, 0, 0.881) = -0.985 rad about X, hinge at the node origin (0, 0.12, -0.103) at the back edge; **set its rotation to identity for closed**, checked by rendering), children of the lid: `metal_toolbox_handle`, `metal_toolbox_handle_latch_l`, `metal_toolbox_handle_latch_r`. Closed height ≈ 0.26 m |
| `plastic_crate_02` | yellow vented plastic crate, which reads as a **90s laundry basket** | [0.506, 0.254, 0.406] | [-0.253, 0, -0.203] | 5840 / 512 / 269 | single node. Material is alpha **BLEND** (vent holes in the diffuse alpha, single-sided). For stable sorting with cloth inside, use `transparent = false; alphaTest = 0.5; side = DoubleSide` |
| `bleach_bottle` | purple "thick bleach" bottle | [0.088, 0.294, 0.061] | [-0.044, 0, -0.031] | 4052 / 512 / 142 | single node |
| `plastic_bottle_gallon` | weathered off-white gallon jug (detergent/vinegar) | [0.166, 0.274, 0.126] | [-0.088, 0, -0.065] | 6000 (from 13.7k) / 512 / 167 | single node |
| `can_rusted` | rusted metal can, "water main pipe jointing lubricant" label | [0.125, 0.151, 0.125] | [-0.062, -0.001, -0.061] | 3520 / 512 / 190 | single node |
| `mousetrap` | old wooden snap mousetrap, rusty spring, cheese bait | [0.055, 0.018, 0.1] | [-0.027, 0, -0.05] | 5136 / 512 / 253 | single node (bar not separate). Good for a "snap" scare sfx when stepped near |
| `painted_wooden_stool` | chipped white painted wooden stool | [0.385, 0.579, 0.406] | [-0.187, -0.001, -0.19] | 676 / 512 / 111 | single node; seat top y = 0.578 |
| `wooden_broom` | weathered straw broom | [0.49, 1.453, 0.113] | [-0.245, -0.122, -0.056] | 9311 / 512 / 523 | `wooden_broom_handle`, `wooden_broom_bristles` (alpha BLEND straw), `wooden_broom` (bristle block). Origin is 0.122 above the bristle tips: stand it at `y = 0.122` |
| `vintage_suitcase` | **two** vintage green leather suitcases side by side (01 has travel stickers, 02 is plain) | [1.608, 0.568, 0.239] | [-0.803, 0, -0.129] | 9254 / 1024 / 798 | per suitcase: `vintage_suitcase_0N_top` (front lid half, can open: hinge ≈ node origin (±0.46, 0.014, 0.006), rotate about X), `_bottom`, `_clasp`, `_handle`. Suitcase 01 occupies x ∈ [0.112, 0.805], suitcase 02 x ∈ [-0.803, -0.11]. Each one is 0.69×0.57×0.24 m: to use a single case, hide the other case's four nodes (see § 3) |

Ready-to-paste `MODELS` entries (`src/core/Assets.js`, core owner):
```js
  boombox:                  { size: [0.724, 0.47, 0.186], min: [-0.362, 0, -0.073] },
  gamepad:                  { size: [0.404, 0.019, 0.435], min: [-0.211, -0.001, -0.214] },
  baseball_bat:             { size: [0.064, 0.913, 0.064], min: [-0.032, -0.254, -0.032] },
  football:                 { size: [0.509, 0.222, 0.222], min: [-0.249, 0, -0.112], nodes: ['football_deflated', 'football_inflated'] }, // two variants side by side: keep one
  ornate_mirror_01:         { size: [0.486, 0.744, 0.026], min: [-0.243, -0.411, 0] }, // origin = hang point, back z=0; glass z~0.007 x±0.219 y[-0.386,0.299]
  hanging_picture_frame_02: { size: [0.752, 0.5, 0.033], min: [-0.376, -0.279, 0.002] }, // child meshes by material: _artwork (swap for canvas, v 0.223-0.801), _glass
  garden_gnome:             { size: [0.257, 0.599, 0.21], min: [-0.144, 0, -0.098] },
  Television_01:            { size: [0.6, 0.457, 0.471], min: [-0.3, 0, -0.258] }, // old CRT; screen x[-0.257,0.126] y[0.114,0.404] z~0.19
  pull_chain_light_socket:  { size: [0.11, 0.165, 0.11], min: [-0.055, -0.165, -0.055], nodes: ['pull_chain_light_socket', 'pull_chain_light_socket_chain'] }, // origin = ceiling mount
  metal_toolbox:            { size: [0.4, 0.305, 0.271], min: [-0.2, 0, -0.157], nodes: ['metal_toolbox', 'metal_toolbox_tray', 'metal_toolbox_lid', 'metal_toolbox_handle', 'metal_toolbox_handle_latch_l', 'metal_toolbox_handle_latch_r'] }, // lid authored OPEN -> identity = closed
  plastic_crate_02:         { size: [0.506, 0.254, 0.406], min: [-0.253, 0, -0.203] }, // laundry basket; alpha BLEND vents
  bleach_bottle:            { size: [0.088, 0.294, 0.061], min: [-0.044, 0, -0.031] },
  plastic_bottle_gallon:    { size: [0.166, 0.274, 0.126], min: [-0.088, 0, -0.065] },
  can_rusted:               { size: [0.125, 0.151, 0.125], min: [-0.062, -0.001, -0.061] },
  mousetrap:                { size: [0.055, 0.018, 0.1], min: [-0.027, 0, -0.05] },
  painted_wooden_stool:     { size: [0.385, 0.579, 0.406], min: [-0.187, -0.001, -0.19] },
  wooden_broom:             { size: [0.49, 1.453, 0.113], min: [-0.245, -0.122, -0.056], nodes: ['wooden_broom_handle', 'wooden_broom_bristles', 'wooden_broom'] }, // stand at y=0.122
  vintage_suitcase:         { size: [1.608, 0.568, 0.239], min: [-0.803, 0, -0.129], nodes: ['vintage_suitcase_01_bottom', 'vintage_suitcase_01_top', 'vintage_suitcase_01_clasp', 'vintage_suitcase_01_handle', 'vintage_suitcase_02_bottom', 'vintage_suitcase_02_top', 'vintage_suitcase_02_clasp', 'vintage_suitcase_02_handle'] }, // two cases side by side
```
Triangles added if all are placed once: about 120k. Draw calls: about 30 (most models are 1 mesh / 1 material).

---

## 3. Suggested placement (consistent with `src/config/layout.js`)

`PROPS`-style entries (`pos` = model origin, `rotY` as in layout.js). The footprints were checked against the existing
props and against the `NAV_NODES` / `NAV_LINKS` segments (≥ 0.3 m clearance, except flat props the entity can step over).
If the architecture module builds the room/nook partition wall thicker than 0 at z = -2.75, the nook's south interior face
moves to about -2.95: all nook items below already stay north of -2.97.

```js
  // ── Main room ─────────────────────────────────────────────────────────────
  boombox:      { model: 'boombox', pos: [-2.35, 0, -0.50], rotY: PI / 2 },                // on the carpet against the knee wall, north of the kid table (footprint x[-2.42,-2.24] z[-0.86,-0.14])
  gamepad:      { model: 'gamepad', pos: [-0.30, 0, -1.95], rotY: 0.5 },                    // dropped on the carpet at the foot of the dresser/TV, cable toward it (flat: no collider)
  bat:          { model: 'baseball_bat', pos: [-3.40, 0.254, 2.63], rotY: 0 },              // leaning in the SW corner at the foot of the stairs: add rotZ +0.10 (top toward the west wall) and rotX +0.10 (toward the south wall)
  football:     { model: 'football', pos: [-2.35, 0, 1.15], rotY: 0.7 },                     // deflated ball by the kid corner (keep football_deflated only, set its x to 0)
  mirror:       { model: 'ornate_mirror_01', pos: [0.47, 1.62, -2.749], rotY: 0 },          // north wall between the dresser (x≤0.05) and the nook doorway (x≥0.9): spans x[0.23,0.71], y[1.21,1.95]
  stairPhotoA:  { model: 'hanging_picture_frame_02', pos: [-3.498, 2.55, 0.30], rotY: PI / 2 },  // stairwell west wall, eye level from tread 5 (y 0.98); artwork = procedural family photo
  stairPhotoB:  { model: 'hanging_picture_frame_02', pos: [-3.498, 3.50, -0.75], rotY: PI / 2 }, // higher up the run (tread 10, y 1.96); the photo with the scratched-out face
  // ── Laundry nook (buanderie) ──────────────────────────────────────────────
  oldTv:        { model: 'Television_01', pos: [2.55, 0, -4.33], rotY: 0 },                 // on the floor under the breaker panel (panel bottom y≈1.2), screen facing into the nook: x[2.25,2.85] z[-4.59,-4.12]
  socket:       { model: 'pull_chain_light_socket', pos: [1.80, 2.50, -3.60], rotY: 0 },    // ceiling mount right above the existing `bulb` prop; hang the bulb under it, inverted (rotX PI, y≈2.43)
  toolbox:      { model: 'metal_toolbox', pos: [3.20, 0, -4.38], rotY: -PI / 2 },           // floor, NE corner north of Shelf_01: x[3.09,3.36] z[-4.58,-4.18]; lid closed (identity) or ajar
  laundry:      { model: 'plastic_crate_02', pos: [0.58, 0, -3.22], rotY: 0.15 },           // laundry basket in the west part of the nook (west of the doorway jamb x=0.9), fill with cloth (fabric032)
  stool:        { model: 'painted_wooden_stool', pos: [0.62, 0, -3.72], rotY: 0 },          // between the basket and the alcove cabinet: x[0.43,0.82] z[-3.92,-3.51]
  broom:        { model: 'wooden_broom', pos: [0.29, 0.122, -3.72], rotY: PI / 2 },         // leaning in the west corner: bristles along the wall (z[-3.97,-3.48]), tilt the top ~0.12 rad toward -X
  bleach:       { model: 'bleach_bottle', pos: [0.85, 1.182, -4.30], rotY: -0.3 },          // on top of the alcove cabinet (top y = 1.182)
  jug:          { model: 'plastic_bottle_gallon', pos: [0.60, 1.182, -4.36], rotY: 0.5 },   // on top of the alcove cabinet
  paintCan:     { model: 'can_rusted', pos: [3.36, 0.66, -3.95], rotY: 1.0 },               // Shelf_01 3rd board (boards at y 0.14/0.38/0.66/0.94/1.22/1.51/1.79/2.08, ~0.26 m clear; board depth world x[3.27,3.46], z[-4.13,-3.27])
  gnome:        { model: 'garden_gnome', pos: [3.25, 0, -3.10], rotY: -1.47 },               // SE corner of the nook, staring at the doorway (good for a "it moved" scare between nights)
  mousetrap:    { model: 'mousetrap', pos: [1.68, 0, -4.50], rotY: 0.3 },                   // along the north wall in the gap between the alcove cabinet (x≤1.60) and boxA (x≥1.77)
  // ── Closet under the stairs / upstairs hallway ────────────────────────────
  suitcase:     { model: 'vintage_suitcase', pos: [-3.31, 0, -1.20], rotY: PI / 2 },        // show case 01 only (hide the 4 vintage_suitcase_02_* nodes): stands against the closet's west wall at z[-2.01,-1.31], north of boxC (z≥-1.26), below the hide camera
  suitcaseHall: { model: 'vintage_suitcase', pos: [-3.47, 2.75, -4.356], rotY: PI / 2 },   // optional, upstairs hallway: show case 02 only (hide the 01_* nodes): against the west wall at z[-4.25,-3.55]; "someone packed to leave" seen in the win view
```
(Rotation convention used above: `rotY = +PI/2` → front faces +X, as in layout.js.)

---

## 4. Realism notes for the integrators

* **Live mirror reflections** (`ornate_mirror_01`): the model's glass already reflects `scene.environment` (the baked cube
  map). For live reflections, including La Gardienne passing behind the player, add a `Reflector`
  (`three/addons/objects/Reflector.js`) as a child of the mirror at local `(0, -0.044, 0.008)`, size 0.438×0.68 (or a
  `ShapeGeometry` with the arched top: straight sides to y = 0.19, apex 0.299), `textureWidth/Height` = 512 on high
  and 1024 on ultra, `clipBias: 0.003`, `color: 0x8a8a8a` (aged silvering). Render it only on high/ultra and only when the
  mirror is within ~5 m and in the frustum (`reflector.visible = …` each frame). Low/medium can keep the baked env.
  Scare idea: she shows up in the mirror for a few frames while the room behind the player is empty.
* **Old CRT in the nook** (`Television_01`): it is not plugged in. When the breaker is flipped, an emissive static plane
  on its screen (rect above) flickering for 1–2 s and then dying makes a strong beat. It can reuse the `tv_static` sound
  at a low volume.
* **Laundry basket**: put 2–4 crumpled cloth meshes (procedural, `fabric032` + `dirty_carpet` tinted) inside
  `plastic_crate_02`, and use `alphaTest` (see above).
* **Window**: glass = `MeshPhysicalMaterial` (transmission 0, `opacity` 0.35, `roughnessMap` from
  `surfaceimperfections003/rough.jpg`), plus the grime overlay. Outside ground: a plane with `snow011` about 0.1 m
  below the sill, lit only by the moon SpotLight. Bars: `metal055b` cylinders (tint 0x4a4846).
* **Pipes on the nook ceiling**: `metal043b` copper (Ø 0.02 m), `metal055b` black gas pipe (Ø 0.03 m), `rusty_metal_02`
  drain stack (Ø 0.1 m), `metal039` dryer duct (Ø 0.1 m flex) and trunk duct (0.4×0.2 m). Use `TubeGeometry` /
  `CylinderGeometry` with UV repeat along the length.
* **Brass key / padlock**: `metal048c` with `metalness: 1` and `envMapIntensity` ~1.2. The flashlight specular makes
  them read clearly in the dark.
* **Notes**: canvas text as `map` + `paper003` normal (normalScale 0.5–0.7) + rough. Under the flashlight, the creases
  catch light grazing across the paper.

---

## 5. Considered and not included

* `gaming_console` (Poly Haven): it is a 7th-generation (2006-era) console, which is anachronistic in a 1990s basement.
  Its mesh also could not be simplified (hard-edge seams, 25k tris / 1.3 MB). `gamepad` (SNES-style) covers the "kids
  played video games here" read.
* `wicker_basket_01` / `_02`: 12 cm / 22 cm tall (bread baskets, not laundry baskets) → `plastic_crate_02` instead.
* `withered_grass` (Poly Haven, dead grass): 1.5 MB at 1K for something seen only through a small barred window at
  night. `snow011` already shows soil and dead-grass patches through the snow.
* Fur fabric (ambientCG Fabric084): optional and 1 MB. La Gardienne's hair is procedural strands.
* Duplicates: `metal048b` (cleaner brass), `concrete_floor_worn_001` (bare concrete floor), `plastic_crate_01` (red milk
  crate, 681 kB), `baseball_01`. Swap them in later if the budget allows.

## 6. Sources (all CC0)

Textures:
* ambientCG (https://ambientcg.com, CC0): [PaintedWood009C](https://ambientcg.com/a/PaintedWood009C),
  [PaintedBricks004](https://ambientcg.com/a/PaintedBricks004), [Metal048C](https://ambientcg.com/a/Metal048C),
  [Metal049B](https://ambientcg.com/a/Metal049B), [Metal039](https://ambientcg.com/a/Metal039),
  [Metal043B](https://ambientcg.com/a/Metal043B), [Metal055B](https://ambientcg.com/a/Metal055B),
  [Wallpaper001A](https://ambientcg.com/a/Wallpaper001A), [Snow011](https://ambientcg.com/a/Snow011),
  [SurfaceImperfections003](https://ambientcg.com/a/SurfaceImperfections003), [Fabric032](https://ambientcg.com/a/Fabric032),
  [Cardboard004](https://ambientcg.com/a/Cardboard004), [Paper003](https://ambientcg.com/a/Paper003),
  [Plastic013B](https://ambientcg.com/a/Plastic013B).
* Poly Haven (https://polyhaven.com, CC0): [painted_concrete_02](https://polyhaven.com/a/painted_concrete_02),
  [rusty_metal_02](https://polyhaven.com/a/rusty_metal_02), [plywood](https://polyhaven.com/a/plywood).

Models (Poly Haven, CC0; author in parentheses):
[boombox](https://polyhaven.com/a/boombox) (Thomas Paul Mouilleron), [gamepad](https://polyhaven.com/a/gamepad) (Josh Dean),
[baseball_bat](https://polyhaven.com/a/baseball_bat) (Enrique Martín), [football](https://polyhaven.com/a/football) (Amal Kumar),
[ornate_mirror_01](https://polyhaven.com/a/ornate_mirror_01) (James Ray Cock),
[hanging_picture_frame_02](https://polyhaven.com/a/hanging_picture_frame_02) (James Ray Cock),
[garden_gnome](https://polyhaven.com/a/garden_gnome) (Bhargav Kubal), [Television_01](https://polyhaven.com/a/Television_01) (Gabriel Radić),
[pull_chain_light_socket](https://polyhaven.com/a/pull_chain_light_socket) (Josh Dean),
[metal_toolbox](https://polyhaven.com/a/metal_toolbox) (Mateusz Sadek), [plastic_crate_02](https://polyhaven.com/a/plastic_crate_02) (Fabi_G),
[bleach_bottle](https://polyhaven.com/a/bleach_bottle) (James Ray Cock),
[plastic_bottle_gallon](https://polyhaven.com/a/plastic_bottle_gallon) (Rahul Chaudhary),
[can_rusted](https://polyhaven.com/a/can_rusted) (Rahul Chaudhary), [mousetrap](https://polyhaven.com/a/mousetrap) (GreenPixel),
[painted_wooden_stool](https://polyhaven.com/a/painted_wooden_stool) (Kirill Sannikov),
[wooden_broom](https://polyhaven.com/a/wooden_broom) (Balen), [vintage_suitcase](https://polyhaven.com/a/vintage_suitcase) (Maximilian Schuster).
