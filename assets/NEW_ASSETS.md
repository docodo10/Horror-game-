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
| `metal_toolbox` | vintage olive metal toolbox, brass latches, lift-out tray | [0.4, 0.305, 0.271] (open) | [-0.2, 0, -0.157] | 9128 / 512 / 428 | `metal_toolbox` (body), `metal_toolbox_tray`, `metal_toolbox_lid` (**authored OPEN**: quaternion (-0.473, 0, 0, 0.881) = -0.985 rad about X, hinge at the node origin (0, 0.12, -0.103) at the back edge; **set its rotation to identity for closed**, checked by rendering), children of the lid: `metal_toolbox_handle`, `metal_toolbox_handle_latch_l`, `metal_toolbox_handle_latch_r`. Closed (lid identity): height 0.225 m, z ∈ [-0.106, 0.115] |
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
Triangles added if every model is placed once: 109k (≈ 122k with the duplicate frame/suitcase of § 3). Draw calls: 38 primitives (≈ 49 with the duplicates).

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


---
---

# Batch 3: storage room, decrepit upstairs hallway, grime decals (Poly Haven + ambientCG)

Mood references (user): grimy concrete corridor with bare bulbs, a filthy stained wall over dirty small tiles, a dim
storage room (steel shelving full of cardboard boxes, fluorescent tube, ladder), and a decrepit house (herringbone
parquet, peeling wallpaper, exposed brick, crackled plaster ceiling, pendant lamps). Goals: the laundry nook becomes a grim
storage/utility room, the closet under the stairs gets grime, the short upstairs hallway (`UPPER_HALL`) gets the
decrepit-house look, and the whole basement gets grime / stain / leak decals.

Everything is **CC0** and, like batch 2, **not wired into the code**: the registry lines, the placement plan and a
ready-to-paste decal list are below.

| | count | size on disk | budget |
|---|---|---|---|
| Surface texture sets (`assets/textures/<id>/`) | 7 | **4.36 MB** | |
| Decal texture sets (`assets/textures/decal_*/`, with `alpha.jpg`) | 10 | **1.29 MB** | |
| **All batch-3 textures** | 17 | **5.65 MB** | ≤ 8 MB |
| Models (`assets/models/<id>.glb`) | 8 | **2.66 MB** | ≤ 6 MB |

Processing (same conventions as batch 2):
* **Surface textures**: source 1K maps (Poly Haven `*_1k.jpg`, ambientCG `*_1K-JPG.zip`) → 1024×1024 JPEG q84,
  `color.jpg` (sRGB), `normal.jpg` (**OpenGL**, PH `nor_gl` / ACG `NormalGL`), `rough.jpg`, `ao.jpg` (all sources had AO).
  Script: `scratchpad/a3/tools/proc_tex.py` (the batch-2 script, unchanged). One deliberate change: the
  `herringbone_parquet` roughness map was **remapped** from the source's lacquer gloss (0.06–0.14, mirror-like) to a worn
  varnish range `0.35 + 3.75·(r − 0.06)` clamped to [0.30, 0.75] (mean 0.49), keeping the per-block variation.
* **Decals**: `scratchpad/a3/tools/proc_decal.py`. Same 5 maps + `alpha.jpg` (grayscale, read by `alphaMap` from the green
  channel). `alpha = source Opacity × a soft mask` so a square decal quad never shows a hard edge: side fades for the
  streak strips (the **top** edge of `decal_leak_streaks` and the **bottom** edge of `decal_rising_damp` are kept hard on
  purpose: they meet the ceiling / floor), a noisy radial falloff for the patches. 512 px except the 1.3 m-wide leak streaks
  (1024) and the rust drip (256×1024, cropped to the central quarter of the source so its texels are not wasted).
  When a source has no roughness map, `rough.jpg` is a constant or `a + b·opacity` (written in the table); no AO →
  flat white `ao.jpg`. Two decals are **derived** (procedural masks applied to CC0 photo data, documented below):
  `decal_water_ring` and `decal_mold`.
* **Models**: Poly Haven glTF 1k → `scratchpad/tools/opt_b3.mjs` (a copy of `opt_new.mjs`: dedup/prune/weld, meshopt simplify
  of meshes > 12k tris to ~9k, WebP textures 512/1024 px q82) run on a raw dir that contains only the new models. Fixes:
  `mounted_fluorescent_lights` keeps 1 of its 7 variants (re-centred); `hanging_industrial_lamp` suspension shortened by
  0.386 m (`scratchpad/tools/lamp_fix.mjs`: four 2-link chain units removed, everything below moved up, the cable compressed;
  checked by rendering); the triangle count is now taken **after** pruning so dropped variants do not trigger the
  simplifier. Every GLB was rendered headless (three r170) to check it. Fronts face **+Z** unless stated.
* **Placement QA**: `scratchpad/tools/placecheck.mjs` computes exact world AABBs (all vertices, node hierarchy, node
  overrides such as the folded ladder) for `PROPS`, `EXTRA_PROPS` and the proposals, and checks overlaps and the distance to
  every `NAV_LINKS` segment. `scratchpad/a3/viewer/scene.html` renders the nook / hallway with the real GLBs, the new
  materials and the decals (screenshots `scratchpad/a3/sheets/scene_a2.png`, `scene_b.png`).

---

## B3.1 Surface texture sets

Tint values are linear RGB multipliers (`color: new THREE.Color(r, g, b)`, values > 1 allowed), checked on a preview.
**"Tile"** = real-world size of one repeat (with world-unit UVs, `repeat = 1 / tile`).

| id | source | use in La Gardienne | tile | maps | notes |
|---|---|---|---|---|---|
| `concrete_wall_007` | Poly Haven concrete_wall_007 | **nook = storage room: walls above the wainscot and the ceiling slab** (raw cast concrete, horizontal formwork lines, tie holes, water/rust stains) | **2.2 m** (source 2.16 m) | c n r ao | Mean sRGB 138,130,110, rough 0.77. Walls `color: (0.85, 0.83, 0.80)`, ceiling `(0.70, 0.70, 0.68)`. Replaces the batch-2 suggestion `paintedbricks004` for the nook. 526 kB |
| `tiles094` | ambientCG Tiles094 | **nook wainscot 0–1.1 m on all four walls** (small beige ceramic tiles with black grime blotches, the "dirty tiles" reference) | **0.8 m** on walls (10 cm tiles); 2 m for a floor (25 cm) | c n r ao | 8 tiles per repeat. Mean 163,148,127, rough 0.42 (glazed). Cap it with a 2 cm bullnose strip at y = 1.1 (`plastic013b` tinted `0xd8ccb0`, or `paintedwood009c`). Largest set: 1077 kB |
| `herringbone_parquet` | Poly Haven herringbone_parquet | **upstairs hallway floor** | **2.5 m** (blocks ≈ 0.6 × 0.07 m; PH says 3.4 m = oversized blocks) | c n r ao | Mean 147,112,77. `color: (0.75, 0.50, 0.38)` gives the reddish aged-varnish brown of the reference. Roughness remapped (see processing). 444 kB |
| `decrepit_wallpaper` | Poly Haven decrepit_wallpaper | **upstairs hallway walls above a 0.85 m chair rail** (stained, flaking, streaked paper) | 2.5 m | c n r ao | Mean 119,107,94, rough 0.93. `color: (1.10, 0.95, 0.75)` (warm, yellowed). The source has **no printed pattern**: for the damask of the reference, multiply a canvas damask print (`map` = canvas, keep this set's normal/rough/ao, or blend both in `onBeforeCompile`). 485 kB |
| `peeling_painted_wall` | Poly Haven peeling_painted_wall | **upstairs hallway wainscot 0–0.85 m**; optional: closet west wall (the foundation wall) | 1.8 m | c n r ao | Source paint is salmon red (150,108,93) with crackle and flakes showing grey render. `color: (0.55, 0.95, 0.90)` → drab olive institutional paint (used in the QA render); `(0.62, 0.85, 0.95)` → dusty mauve-grey. 584 kB |
| `brick_wall_001` | Poly Haven brick_wall_001 | **upstairs hallway north end wall (z = −4.40)**: exposed old brick, straight in the win view through the door | **1.07 m** (measured: 14.2 courses × 0.075 m and 5 bricks × 0.215 m per repeat; PH metadata says 3 m = giant bricks) | c n r ao | Dark red/sooty mixed bricks, mean 100,74,60, rough 0.91. 742 kB |
| `worn_cracked_plaster` | Poly Haven worn_cracked_plaster | **upstairs hallway ceiling** (alligator-crackled old plaster, like the reference ceiling) | 2.5 m | c n r ao | Source is dark olive (126,111,86): `color: (1.6, 1.5, 1.35)` lifts it to a sepia crackle. The crack relief is mostly in color/ao (the normal map is subtle). 607 kB |

Ready-to-paste `TEXTURE_SETS` entries (`src/core/Assets.js`):
```js
  // ---- batch 3 (assets/NEW_ASSETS.md §B3: tile sizes, tints, decal recipe) ----
  concrete_wall_007:    'raw cast concrete, formwork lines + stains (nook walls/ceiling, tile 2.2 m)',
  tiles094:             'dirty small beige tiles (nook wainscot 0-1.1 m, tile 0.8 m)',
  herringbone_parquet:  'herringbone parquet (upstairs hallway floor, tile 2.5 m, tint reddish)',
  decrepit_wallpaper:   'stained peeling wallpaper (upstairs hallway walls, tile 2.5 m)',
  peeling_painted_wall: 'peeling painted concrete, red source: tint (hallway wainscot, closet wall)',
  brick_wall_001:       'old sooty red brick (hallway end wall, true tile 1.07 m)',
  worn_cracked_plaster: 'alligator-crackled plaster (hallway ceiling, tint x1.5)',
  decal_leak_streaks:   'DECAL (alpha.jpg): water/mildew streaks from the ceiling, top edge hard',
  decal_rising_damp:    'DECAL (alpha.jpg): rising damp at the wall foot, bottom edge hard',
  decal_pipe_leak:      'DECAL (alpha.jpg): fan-shaped seep under a pipe penetration',
  decal_rust_drip:      'DECAL (alpha.jpg, 256x1024): rust run under a bolt/screw',
  decal_dirt_patch:     'DECAL (alpha.jpg): floor dirt patch (tint warm)',
  decal_grime:          'DECAL (alpha.jpg): smudgy wall grime patch',
  decal_scuffs:         'DECAL (alpha.jpg): scuff streaks, white source: tint dark',
  decal_hand_smudges:   'DECAL (alpha.jpg): greasy hand/finger smudges',
  decal_water_ring:     'DECAL (alpha.jpg): ceiling water-stain tide rings (derived)',
  decal_mold:           'DECAL (alpha.jpg): black/olive mould patch (derived)',
```

---

## B3.2 Decal texture sets

All 10 have `color/normal/rough/ao/alpha.jpg`. Load them with `assets.texture(path, { wrap: false })` (clamped, no
repeat). Mean colour is alpha-weighted.

| id | source | px | use | rough | notes |
|---|---|---|---|---|---|
| `decal_leak_streaks` | ambientCG **Leaking003** | 1024 | water / mildew run-off from the ceiling or a slab joint, on walls | source (wet, 0.42) | grey-green streaks fading downward; side fades baked; **top edge hard** → align it with the ceiling line. 541 kB |
| `decal_rising_damp` | ambientCG **Leaking008** | 512 | rising damp / tide mark at the foot of basement walls | source | blurry vertical wicking; **bottom edge hard** → sits on the floor line. 68 kB |
| `decal_pipe_leak` | ambientCG **Leaking006** | 512 | fan-shaped yellow-brown seep below a pipe penetration (the dark hole is in the decal, top centre at ~97 % height) | source | 98 kB |
| `decal_rust_drip` | ambientCG **Leaking010C** (central quarter) | 256×1024 | rust run from a screw/bolt (hole at the top) under the breaker panel, pipe hangers, window bars | source | use a 1 : 4 quad (e.g. 0.12 × 0.48 m). 128 kB |
| `decal_dirt_patch` | ambientCG **SurfaceImperfections001** | 512 | floor dirt / traffic patches (concrete, carpet, parquet) | 0.95 const | neutral grey source: tint warm (`#a08a70` concrete, `#8a7660` carpet); alpha ×1.8. 93 kB |
| `decal_grime` | ambientCG **SurfaceImperfections008** | 512 | smudgy grime on walls: around the breaker panel, the closet hiding spot, the dust ghost above the TV | 0.9 const | alpha ×1.3. 126 kB |
| `decal_scuffs` | ambientCG **Smear005** | 512 | horizontal rubber / furniture scuffs near baseboards and chair backs | 0.85 − 0.35·α | **white** source smears: tint dark (`#2b2622`) for rubber scuffs; untinted it reads as scraped paint on dark surfaces. 68 kB |
| `decal_hand_smudges` | ambientCG **Fingerprints009** | 512 | greasy hand smudges: door edges, closet door, stair wall, switch plates | 0.8 − 0.45·α (greasy = shinier) | 76 kB |
| `decal_water_ring` | **derived** from ambientCG SurfaceImperfections002 | 512 | brown **tide-ring water stain on ceilings** (no CC0 ring decal exists on either site) | 0.85 − 0.1·α | irregular annulus (noise-wobbled radius) with broken dark tide line, two older partial rings and a blotchy faint fill; the blotches come from the source opacity; tea-brown colour; flat normal. 39 kB |
| `decal_mold` | **derived** from ambientCG Wallpaper002C (mould-stained paper) | 512 | black/olive mould colonies in damp corners (wall–ceiling, low closet corner) | 0.95 const | alpha = how much darker each texel is than the clean paper × noisy radial falloff × clumping noise; colour pushed to olive-black; flat normal. 82 kB |

Decal material recipe (flat walls/floors/ceilings are planes, so an offset quad is cheaper than `DecalGeometry`):
```js
// d = one entry of DECALS (§B3.5). Decals render after opaque geometry; they receive light/shadow but cast none.
function addDecal(scene, assets, d) {
  const p = `textures/${d.tex}/`, t = f => assets.texture(p + f, { wrap: false });
  const mat = new THREE.MeshStandardMaterial({
    map: assets.texture(p + 'color.jpg', { srgb: true, wrap: false }), alphaMap: t('alpha.jpg'),
    normalMap: t('normal.jpg'), normalScale: new THREE.Vector2(0.5, 0.5), roughnessMap: t('rough.jpg'),
    roughness: 1, metalness: 0, transparent: true, depthWrite: false,
    polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4,
  });
  if (d.tint) mat.color.set(d.tint);           // sRGB hex, converted to linear by three
  if (d.opacity != null) mat.opacity = d.opacity;
  const m = new THREE.Mesh(new THREE.PlaneGeometry(d.size[0], d.size[1]), mat);
  const z = new THREE.Vector3(...d.normal).normalize(), up = new THREE.Vector3(...d.up).normalize();
  const x = new THREE.Vector3().crossVectors(up, z).normalize(), y = new THREE.Vector3().crossVectors(z, x);
  m.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(x, y, z));   // texture top = `up`
  m.position.fromArray(d.pos).addScaledVector(z, 0.004);                        // 4 mm off the surface
  m.renderOrder = 2; m.receiveShadow = true; m.castShadow = false; m.name = 'decal_' + d.id;
  scene.add(m); return m;
}
```
Share one material per (tex, tint, opacity) to keep draw calls/programs low (29 quads ≈ 29 draw calls, 10 textures sets;
merge quads with the same material into one `BufferGeometry` if needed). On `low` quality you can skip the normal and
roughness maps of decals. For a decal that must wrap a corner or an uneven mesh, use
`three/addons/geometries/DecalGeometry.js` with the same orientation (`new THREE.Euler().setFromRotationMatrix(basis)`)
and `size = (w, h, 0.1)`.

---

## B3.3 Models

`size` = bbox [x, y, z] in metres at scale 1, `min` = bbox min corner (same convention as `MODELS`).

| id | what | size [x,y,z] | min | tris / tex / kB | nodes & material notes |
|---|---|---|---|---|---|
| `steel_frame_shelves_02` | black steel-frame shelving unit, 5 pine boards (storage-room shelving) | [0.593, 2.142, 0.502] | [-0.297, -0.001, -0.251] | 4348 / 1024 / 306 | single node, open on both long sides. **Board tops y = 0.133 / 0.639 / 1.145 / 1.651 / 2.130**, usable area x ±0.265, z ±0.246, ≈ 0.48 m clear between boards. The pine boards look new: `color: (0.72, 0.66, 0.58)` dulls them (the black frame stays black) and add dust/dirt decals on the boards if wanted |
| `mounted_fluorescent_lights` | 3 ft surface-mounted **twin-tube fluorescent batten** (variant `b` of the 7 in the source sheet) | [0.912, 0.035, 0.04] | [-0.456, -0.035, -0.02] | 2920 / 512 / 144 | node `mounted_fluorescent_lights_b`, re-centred (its source offset z = 0.2 removed). **Origin = ceiling mount**, long axis X. Materials: body + `mounted_fluorescent_lights_glass` (tubes) with an emissive map and **emissiveFactor 0** → to light it: `glass.emissive.set(0xffffff); glass.emissiveIntensity = 2–4` (+ bloom) |
| `hanging_industrial_lamp` | enamelled industrial pendant: cream shade, wire guard, glass, junction box, chain + cloth cable | [0.55, 0.969, 0.55] | [-0.275, -0.954, -0.275] | 8634 / 512 / 445 | single node, **origin = ceiling mount**. Suspension shortened (source 1.355 m tall). Main material has an emissive map with **factor 1** (bulb always glowing): set `emissiveIntensity = 0` when off. Glass: `hanging_industrial_lamp_glass`. At `scale 0.6` (used in the hallway): 0.33 m shade, 0.58 m drop |
| `wooden_ladder` | weathered wooden step ladder | [0.959, 1.335, 0.5] (open) | [-0.485, 0, -0.25] | 8492 / 512 / 385 | `wooden_ladder_steps` + `wooden_ladder_supports`, both pivot on the **top hinge at their node origin (0, 1.105, 0)**; legs spread along X, treads on the −X side. Authored **open**. **Folded**: `wooden_ladder_supports.rotation.z = -0.70` (render-checked, see §B3.4) |
| `plastic_crate_01` | red "GALLER" milk crate | [0.298, 0.264, 0.408] | [-0.149, 0, -0.204] | 10538 / 512 / 656 | single node, opaque (the lattice is geometry). The simplifier stops at ~10.5k (UV seams on the lattice) |
| `medical_box` | green steel first-aid box | [0.525, 0.098, 0.35] | [-0.263, 0, -0.172] | 3718 / 512 / 219 | `medical_box` (body), `medical_box_lid` (**hinge at its node origin (0, 0.066, −0.169)**, back edge: `rotation.x ≈ -1.9` opens it), `medical_box_latch`, `medical_box_latch_rings`, `medical_box_handle` (front = +Z). Usable later as an item container (e.g. a battery) |
| `Lantern_01` | old brass kerosene hurricane lantern | [0.122, 0.294, 0.097] | [-0.061, 0, -0.048] | 7137 (from 33.9k) / 512 / 289 | `Lantern_01` + `Lantern_01_glass` (alpha **BLEND** chimney). Lit variant: small warm PointLight at local (0, 0.10, 0) |
| `metal_jerrycan` | red 20 L steel jerrycan, chipped paint | [0.35, 0.455, 0.172] | [-0.17, 0, -0.089] | 6000 (from 20k) / 512 / 282 | single node |

Ready-to-paste `MODELS` entries (`src/core/Assets.js`):
```js
  // ---- batch 3 ----
  steel_frame_shelves_02:     { size: [0.593, 2.142, 0.502], min: [-0.297, -0.001, -0.251] }, // board tops y .133/.639/1.145/1.651/2.130
  mounted_fluorescent_lights: { size: [0.912, 0.035, 0.04], min: [-0.456, -0.035, -0.02] },   // origin = ceiling mount; tube glass emissive factor 0
  hanging_industrial_lamp:    { size: [0.55, 0.969, 0.55], min: [-0.275, -0.954, -0.275] },   // origin = ceiling mount; emissive factor 1
  wooden_ladder:              { size: [0.959, 1.335, 0.5], min: [-0.485, 0, -0.25], nodes: ['wooden_ladder_steps', 'wooden_ladder_supports'] }, // hinge (0,1.105,0); folded: supports rotation.z=-0.70
  plastic_crate_01:           { size: [0.298, 0.264, 0.408], min: [-0.149, 0, -0.204] },
  medical_box:                { size: [0.525, 0.098, 0.35], min: [-0.263, 0, -0.172], nodes: ['medical_box', 'medical_box_lid', 'medical_box_latch', 'medical_box_latch_rings', 'medical_box_handle'] }, // lid hinge (0,0.066,-0.169)
  Lantern_01:                 { size: [0.122, 0.294, 0.097], min: [-0.061, 0, -0.048] },      // glass = alpha BLEND
  metal_jerrycan:             { size: [0.35, 0.455, 0.172], min: [-0.17, 0, -0.089] },
```
Triangles if each model is placed once: 51.8k. With the plan below (2 shelves, 4 extra cardboard boxes at 9k tris each,
one of each other model): **+92k triangles, +21 draw calls** (decals: +29 quads). If the triangle budget is tight, drop
`shelfWbox2` and `shelfNbox4` first (−18k).

---

## B3.4 Placement plan (consistent with `src/config/layout.js`)

Surfaces used below: nook walls W x = 0.2, E x = 3.5, N z = −4.6, **S = north face of the room/nook wall at z = −2.95**
(the 0.2 m wall spans z ∈ [−2.95, −2.75], as in the current stub and batch 2), nook ceiling y = 2.5; hallway floor
y = 2.75, ceiling y = 5.2, walls x = −3.6 / −2.45, end wall z = −4.4.

### Shell materials

| area | surface | material (tile, tint) |
|---|---|---|
| nook (storage room) | walls 1.1–2.5 m | `concrete_wall_007` (2.2 m, `(0.85, 0.83, 0.80)`) |
| | walls 0–1.1 m (all four, both sides of the doorway) | `tiles094` (0.8 m → 10 cm tiles) + 2 cm bullnose cap at y = 1.1 |
| | floor | keep `painted_concrete_02` (batch 2) + dirt decals |
| | ceiling | `concrete_wall_007` (2.2 m, `(0.70, 0.70, 0.68)`), pipes/duct of batch 2 §4 still apply |
| | light | `mounted_fluorescent_lights` (below) + the existing broken bulb on `pull_chain_light_socket` |
| closet under the stairs | walls / underside of the stairs | keep `plywood` (batch 2); optional: west wall (foundation) in `peeling_painted_wall` `(0.62, 0.85, 0.95)`; grime/mould decals C1–C5 |
| upstairs hallway | floor | `herringbone_parquet` (2.5 m, `(0.75, 0.50, 0.38)`), baseboard `paintedwood009c` tinted `0x8a7f70` |
| | side walls 0–0.85 m | `peeling_painted_wall` (1.8 m, `(0.55, 0.95, 0.90)`), chair rail 0.85 m (`paintedwood009c` or `stained_pine`) |
| | side walls 0.85–2.45 m | `decrepit_wallpaper` (2.5 m, `(1.10, 0.95, 0.75)`; optional canvas damask multiply) |
| | north end wall (z = −4.4) | `brick_wall_001` (1.07 m), the exposed brick seen straight through the open door |
| | ceiling | `worn_cracked_plaster` (2.5 m, `(1.6, 1.5, 1.35)`) |
| | light | `hanging_industrial_lamp` at scale 0.6 + warm PointLight (~2700 K) at the bulb, replaces the "warm hallway light" |

This replaces the batch-2 suggestions `paintedbricks004` (nook walls) and `wallpaper001a` (hallway), which stay available.

### Props (`EXTRA_PROPS`-style, `pos` = model origin, `rotY` as in layout.js)

New field: `nodeRot: { nodeName: [x, y, z] }` (Euler set on a child node after cloning) for the folded ladder. Items standing
on a shelf board use `noCollider: true` (the shelf carries the collider).
```js
  // ── Nook = storage room ───────────────────────────────────────────────────
  shelfW:      { model: 'steel_frame_shelves_02', pos: [0.547, 0, -3.205], rotY: PI },       // S wall west of the doorway, front faces north; back 4 mm off z=-2.95
  shelfWbox1:  { model: 'cardboard_box_01', pos: [0.547, 0.639, -3.20], rotY: PI / 2 + 0.03, scale: 0.95, noCollider: true }, // board 2
  medkit:      { model: 'medical_box', pos: [0.547, 1.145, -3.19], rotY: PI, noCollider: true },                // board 3, latch toward the room
  milkCrate:   { model: 'plastic_crate_01', pos: [0.48, 1.651, -3.20], rotY: PI, noCollider: true },            // board 4 (eye level)
  shelfWbox2:  { model: 'cardboard_box_01', pos: [0.547, 2.131, -3.21], rotY: PI / 2 + 0.1, scale: 0.8, noCollider: true }, // top board, box top y=2.40
  shelfN:      { model: 'steel_frame_shelves_02', pos: [1.92, 0, -4.346], rotY: 0 },          // N wall between the alcove cabinet (x<=1.60) and the breaker panel (x>=2.31)
  shelfNbox3:  { model: 'cardboard_box_01', pos: [1.93, 1.145, -4.36], rotY: PI / 2 - 0.06, scale: 0.8, noCollider: true },  // board 3
  shelfNbox4:  { model: 'cardboard_box_01', pos: [1.90, 1.651, -4.35], rotY: PI / 2 + 0.12, scale: 0.75, noCollider: true }, // board 4
  jerrycan:    { model: 'metal_jerrycan', pos: [2.965, 0, -4.41], rotY: PI / 2 },              // floor, N wall gap between oldTv (x<=2.85) and toolbox (x>=3.09)
  tubeLight:   { model: 'mounted_fluorescent_lights', pos: [2.55, 2.5, -3.95], rotY: 0, noCollider: true }, // ceiling batten in front of the panel / TV corner
  ladder:      { model: 'wooden_ladder', pos: [2.13, 0.1255, -2.759], rotY: -PI / 2, rotX: -0.25,
                 nodeRot: { wooden_ladder_supports: [0, 0, -0.70] } },                          // FOLDED, leaning ~11° on the S wall east of the doorway
  // ── Upstairs hallway ──────────────────────────────────────────────────────
  hallLamp:    { model: 'hanging_industrial_lamp', pos: [-3.0, 5.2, -4.0], rotY: 0.4, scale: 0.6, noCollider: true }, // shade bottom y=4.63 (1.88 m above the hall floor)
  hallLantern: { model: 'Lantern_01', pos: [-2.62, 2.75, -4.22], rotY: -0.6, noCollider: true },              // floor, NE corner of the hallway
```
Moves of existing entries (the new shelves stand where these were):
```js
  // PROPS (core/props owners): the floor boxes go onto the north shelf
  boxA:      { model: 'cardboard_box_01', pos: [1.92, 0.133, -4.35], rotY: PI / 2 + 0.05 },                // was [2.0, 0, -4.3]: bottom board of shelfN
  boxB:      { model: 'cardboard_box_01', pos: [1.92, 0.639, -4.34], rotY: -PI / 2 + 0.08, scale: 0.85 },  // was on boxA: board 2 of shelfN
  // EXTRA_PROPS
  laundry:   { model: 'plastic_crate_02', pos: [0.547, 0.133, -3.205], rotY: PI + 0.04, noCollider: true }, // was [0.58, 0, -3.22]: bottom board of shelfW
  mousetrap: { model: 'mousetrap', pos: [1.70, 0, -4.03], rotY: 0.3, noCollider: true },                    // was [1.68, 0, -4.50] (now under shelfN): at its front-left foot
```
Everything else of batch 2 stays (stool, broom, bleach, jug on the cabinet, oldTv, toolbox, paintCan on `Shelf_01`, gnome,
socket + bulb). `Shelf_01` (white wooden, east wall) also stays.

Checks (exact AABBs from all vertices, `scratchpad/tools/placecheck.mjs`; nav = distance from the footprint to the nearest
`NAV_LINKS` segment of the same floor; no overlap with any `PROPS` / `EXTRA_PROPS` entry or other proposal, items on a
board excepted from their shelf):

| id | footprint x | y | z | nav clearance |
|---|---|---|---|---|
| shelfW | [0.250, 0.844] | [0, 2.141] | [−3.456, −2.954] | 0.506 (alcoveDoor–alcoveIn); ends 5.6 cm west of the doorway jamb x = 0.9 |
| shelfN | [1.623, 2.217] | [0, 2.141] | [−4.597, −4.095] | 0.529 (alcoveIn–alcoveEast) |
| boxA / boxB / shelfNbox3 / shelfNbox4 | within [1.676, 2.209] | on boards | within [−4.548, −4.157] | ≥ 0.59 |
| laundry / shelfWbox1 / medkit / milkCrate / shelfWbox2 | within [0.284, 0.822] | on boards, top 2.40 | within [−3.416, −2.994] | ≥ 0.53 |
| jerrycan | [2.876, 3.048] | [0, 0.455] | [−4.590, −4.240] | 0.664 |
| mousetrap | [1.661, 1.739] | [0, 0.018] | [−4.085, −3.975] | 0.445 (flat) |
| tubeLight | [2.094, 3.006] | [2.465, 2.5] | [−3.970, −3.930] | overhead |
| ladder (folded, leaning) | [1.880, 2.380] | [−0.005, 1.441] | [−3.229, −2.955] | **0.310** (alcoveIn–alcoveEast); 8 cm east of the doorway jamb x = 1.8 |
| hallLamp | [−3.165, −2.835] | [4.628, 5.209] | [−4.165, −3.835] | overhead; see the note on the entity below |
| hallLantern | [−2.671, −2.570] | [2.75, 3.044] | [−4.268, −4.172] | 0.660 (hall–landing) |

Clearances that matter for gameplay: the **breaker-panel door** (`power_box_01_door`, hinge x ≈ 2.436) opened at its
authored −109° has its free edge at x ≈ 2.29, z ≈ −4.09, i.e. 7 cm east of `shelfN` (x ≤ 2.217): keep the open angle
≤ 110°. The alcove cabinet's right door (hinge x ≈ 1.568) swings in front of `shelfN` (z > −3.95), never into it.
`hallLamp`: La Gardienne is ≈ 1.98 m tall and the shade bottom is 1.88 m above the hall floor; the shade
(z ∈ [−4.165, −3.835]) starts 0.235 m north of the `hall` nav node, so she only meets it if she walks north of the node. Either keep her path south of z = −3.85 or
let the lamp swing when she brushes it (good scare: the light swings, shadows sweep through the doorway).

---

## B3.5 Decal placement plan (29 instances)

`pos` = centre on the surface (walls at their interior face, floors/ceilings at their height; `addDecal` adds the 4 mm
offset), `normal` = surface normal toward the viewer, `up` = world direction of the texture's top edge, `size` = quad
width × height in metres. Ids: N = nook, M = main room / stairwell, C = closet, H = upstairs hallway. Every position was
checked against the layout (no decal crosses a doorway, the window or a picture frame; wall-foot decals stay above
y = 0, ceiling-edge decals end at the ceiling line). In the QA render, the nook decals sit on the tiled wainscot / concrete
of §B3.4.

| id | texture | pos | normal | up | size (m) | tint / opacity | where / why |
|---|---|---|---|---|---|---|---|
| N1 | `decal_leak_streaks` | [0.95, 2.05, -4.598] | [0, 0, 1] | [0, 1, 0] | 1.3 × 0.9 | – | nook N wall above the alcove cabinet, top edge on the ceiling |
| N2 | `decal_pipe_leak` | [2.98, 2, -4.598] | [0, 0, 1] | [0, 1, 0] | 0.45 × 0.6 | – | nook N wall east of the breaker panel: seep from a pipe penetration at y~2.29 |
| N3 | `decal_rust_drip` | [2.66, 0.94, -4.598] | [0, 0, 1] | [0, 1, 0] | 0.12 × 0.48 | – | nook N wall, rust run from the panel bottom screw (top y=1.18) |
| N4 | `decal_grime` | [2.55, 1.45, -4.598] | [0, 0, 1] | [0, 1, 0] | 0.9 × 0.85 | tint `#b8b0a4` | nook N wall, dirty-hand grime around the breaker panel |
| N5 | `decal_mold` | [0.202, 2.2, -4.25] | [1, 0, 0] | [0, 1, 0] | 0.7 × 0.6 | – | nook W wall, NW ceiling corner |
| N6 | `decal_water_ring` | [2.9, 2.498, -3.55] | [0, -1, 0] | [0.4226, 0, -0.9063] | 0.8 × 0.8 | – | nook ceiling |
| N7 | `decal_rising_damp` | [2.65, 0.28, -2.952] | [0, 0, -1] | [0, 1, 0] | 1.6 × 0.56 | – | nook S (partition) face east of the doorway, behind the ladder, bottom edge on the floor |
| N8 | `decal_dirt_patch` | [2.1, 0.002, -3.8] | [0, 1, 0] | [0, 0, -1] | 1.1 × 1 | tint `#a08a70`, opacity 0.85 | nook floor in front of the shelf and panel |
| N9 | `decal_dirt_patch` | [1.35, 0.002, -3.25] | [0, 1, 0] | [-1, 0, 0] | 0.8 × 0.86 | tint `#a08a70`, opacity 0.7 | nook floor, doorway traffic path |
| N10 | `decal_scuffs` | [3.2, 0.2, -2.952] | [0, 0, -1] | [0, 1, 0] | 0.55 × 0.25 | tint `#2b2622` | nook S face near the gnome/jerrycan corner: rubber scuffs |
| M1 | `decal_leak_streaks` | [2.45, 1.35, 2.748] | [0, 0, -1] | [0, 1, 0] | 1.15 × 0.9 | opacity 0.8 | S wall under the window: condensation runs, top edge on the sill y=1.8 |
| M2 | `decal_water_ring` | [-1.55, 2.498, 1.25] | [0, -1, 0] | [-0.2588, 0, -0.9659] | 0.8 × 0.8 | – | main ceiling above the kid corner (bathroom leak upstairs) |
| M3 | `decal_grime` | [-0.55, 1.78, -2.748] | [0, 0, 1] | [0, 1, 0] | 0.9 × 0.6 | tint `#9c958a`, opacity 0.5 | N wall above the small TV: heat/dust ghost |
| M4 | `decal_scuffs` | [-1.85, 0.22, -2.748] | [0, 0, 1] | [0, 1, 0] | 1 × 0.3 | tint `#2b2622` | N wall, baseboard zone west of the dresser |
| M5 | `decal_scuffs` | [3.498, 0.78, -1.05] | [-1, 0, 0] | [0, 1, 0] | 0.6 × 0.25 | tint `#2b2622` | E wall where chairA backrest rubs |
| M6 | `decal_hand_smudges` | [-2.498, 1, -1.58] | [1, 0, 0] | [0, 1, 0] | 0.3 × 0.4 | – | knee wall (room face) beside the closet door handle |
| M7 | `decal_hand_smudges` | [-3.498, 2.77, -0.6] | [1, 0, 0] | [0, 0.798, 0.603] | 1 × 0.3 | – | stairwell W wall, hand slide along the climb (decal tilted to the 37 deg stair slope) |
| M8 | `decal_mold` | [-3.15, 0.45, 2.748] | [0, 0, -1] | [0, 1, 0] | 0.65 × 0.6 | – | S wall, dank SW corner behind the baseball bat |
| M9 | `decal_dirt_patch` | [-3, 0.004, 2.1] | [0, 1, 0] | [0, 0, -1] | 0.9 × 0.7 | tint `#8a7660`, opacity 0.6 | carpet at the foot of the stairs |
| C1 | `decal_grime` | [-3.448, 1.25, -2.15] | [1, 0, 0] | [0, 1, 0] | 0.8 × 0.8 | tint `#8f877c` | closet W wall at the hiding spot |
| C2 | `decal_mold` | [-3.448, 0.3, -0.75] | [1, 0, 0] | [0, 1, 0] | 0.6 × 0.45 | – | closet W wall, low, south end (under the low stair stringer) |
| C3 | `decal_leak_streaks` | [-3.03, 1.85, -2.698] | [0, 0, 1] | [0, 1, 0] | 0.8 × 0.9 | – | closet N wall under the landing: top edge on the closet ceiling (move y so pos.y = ceiling - 0.45) |
| C4 | `decal_hand_smudges` | [-2.602, 1.05, -1.58] | [-1, 0, 0] | [0, 1, 0] | 0.28 × 0.38 | – | knee wall inner face beside the door: where a hand pulls the door shut |
| C5 | `decal_dirt_patch` | [-3.05, 0.002, -1.9] | [0, 1, 0] | [0, 0, -1] | 0.75 × 0.9 | tint `#8a7660`, opacity 0.8 | closet floor |
| H1 | `decal_water_ring` | [-3.03, 5.198, -3.35] | [0, -1, 0] | [0.6428, 0, -0.766] | 0.75 × 0.75 | – | hall ceiling (cracked plaster) |
| H2 | `decal_leak_streaks` | [-2.452, 4.75, -3.75] | [-1, 0, 0] | [0, 1, 0] | 1 × 0.9 | – | hall E wall from the ceiling |
| H3 | `decal_mold` | [-2.75, 4.92, -4.398] | [0, 0, 1] | [0, 1, 0] | 0.6 × 0.55 | – | hall N end wall, top-right corner |
| H4 | `decal_scuffs` | [-3.598, 2.95, -3.2] | [1, 0, 0] | [0, 1, 0] | 0.9 × 0.3 | tint `#2b2622` | hall W wall, baseboard zone |
| H5 | `decal_dirt_patch` | [-3, 2.752, -3.42] | [0, 1, 0] | [0, 0, -1] | 0.9 × 1.3 | tint `#7a6450`, opacity 0.6 | hall parquet, worn traffic lane |

Ready-to-paste list (e.g. `export const DECALS = [...]` in `layout.js`, built with `addDecal` of §B3.2):
```js
export const DECALS = [
  { id: 'N1', tex: 'decal_leak_streaks', pos: [0.95, 2.05, -4.598], normal: [0, 0, 1], up: [0, 1, 0], size: [1.3, 0.9] },
  { id: 'N2', tex: 'decal_pipe_leak', pos: [2.98, 2, -4.598], normal: [0, 0, 1], up: [0, 1, 0], size: [0.45, 0.6] },
  { id: 'N3', tex: 'decal_rust_drip', pos: [2.66, 0.94, -4.598], normal: [0, 0, 1], up: [0, 1, 0], size: [0.12, 0.48] },
  { id: 'N4', tex: 'decal_grime', pos: [2.55, 1.45, -4.598], normal: [0, 0, 1], up: [0, 1, 0], size: [0.9, 0.85], tint: '#b8b0a4' },
  { id: 'N5', tex: 'decal_mold', pos: [0.202, 2.2, -4.25], normal: [1, 0, 0], up: [0, 1, 0], size: [0.7, 0.6] },
  { id: 'N6', tex: 'decal_water_ring', pos: [2.9, 2.498, -3.55], normal: [0, -1, 0], up: [0.4226, 0, -0.9063], size: [0.8, 0.8] },
  { id: 'N7', tex: 'decal_rising_damp', pos: [2.65, 0.28, -2.952], normal: [0, 0, -1], up: [0, 1, 0], size: [1.6, 0.56] },
  { id: 'N8', tex: 'decal_dirt_patch', pos: [2.1, 0.002, -3.8], normal: [0, 1, 0], up: [0, 0, -1], size: [1.1, 1], tint: '#a08a70', opacity: 0.85 },
  { id: 'N9', tex: 'decal_dirt_patch', pos: [1.35, 0.002, -3.25], normal: [0, 1, 0], up: [-1, 0, 0], size: [0.8, 0.86], tint: '#a08a70', opacity: 0.7 },
  { id: 'N10', tex: 'decal_scuffs', pos: [3.2, 0.2, -2.952], normal: [0, 0, -1], up: [0, 1, 0], size: [0.55, 0.25], tint: '#2b2622' },
  { id: 'M1', tex: 'decal_leak_streaks', pos: [2.45, 1.35, 2.748], normal: [0, 0, -1], up: [0, 1, 0], size: [1.15, 0.9], opacity: 0.8 },
  { id: 'M2', tex: 'decal_water_ring', pos: [-1.55, 2.498, 1.25], normal: [0, -1, 0], up: [-0.2588, 0, -0.9659], size: [0.8, 0.8] },
  { id: 'M3', tex: 'decal_grime', pos: [-0.55, 1.78, -2.748], normal: [0, 0, 1], up: [0, 1, 0], size: [0.9, 0.6], tint: '#9c958a', opacity: 0.5 },
  { id: 'M4', tex: 'decal_scuffs', pos: [-1.85, 0.22, -2.748], normal: [0, 0, 1], up: [0, 1, 0], size: [1, 0.3], tint: '#2b2622' },
  { id: 'M5', tex: 'decal_scuffs', pos: [3.498, 0.78, -1.05], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.6, 0.25], tint: '#2b2622' },
  { id: 'M6', tex: 'decal_hand_smudges', pos: [-2.498, 1, -1.58], normal: [1, 0, 0], up: [0, 1, 0], size: [0.3, 0.4] },
  { id: 'M7', tex: 'decal_hand_smudges', pos: [-3.498, 2.77, -0.6], normal: [1, 0, 0], up: [0, 0.798, 0.603], size: [1, 0.3] },
  { id: 'M8', tex: 'decal_mold', pos: [-3.15, 0.45, 2.748], normal: [0, 0, -1], up: [0, 1, 0], size: [0.65, 0.6] },
  { id: 'M9', tex: 'decal_dirt_patch', pos: [-3, 0.004, 2.1], normal: [0, 1, 0], up: [0, 0, -1], size: [0.9, 0.7], tint: '#8a7660', opacity: 0.6 },
  { id: 'C1', tex: 'decal_grime', pos: [-3.448, 1.25, -2.15], normal: [1, 0, 0], up: [0, 1, 0], size: [0.8, 0.8], tint: '#8f877c' },
  { id: 'C2', tex: 'decal_mold', pos: [-3.448, 0.3, -0.75], normal: [1, 0, 0], up: [0, 1, 0], size: [0.6, 0.45] },
  { id: 'C3', tex: 'decal_leak_streaks', pos: [-3.03, 1.85, -2.698], normal: [0, 0, 1], up: [0, 1, 0], size: [0.8, 0.9] },
  { id: 'C4', tex: 'decal_hand_smudges', pos: [-2.602, 1.05, -1.58], normal: [-1, 0, 0], up: [0, 1, 0], size: [0.28, 0.38] },
  { id: 'C5', tex: 'decal_dirt_patch', pos: [-3.05, 0.002, -1.9], normal: [0, 1, 0], up: [0, 0, -1], size: [0.75, 0.9], tint: '#8a7660', opacity: 0.8 },
  { id: 'H1', tex: 'decal_water_ring', pos: [-3.03, 5.198, -3.35], normal: [0, -1, 0], up: [0.6428, 0, -0.766], size: [0.75, 0.75] },
  { id: 'H2', tex: 'decal_leak_streaks', pos: [-2.452, 4.75, -3.75], normal: [-1, 0, 0], up: [0, 1, 0], size: [1, 0.9] },
  { id: 'H3', tex: 'decal_mold', pos: [-2.75, 4.92, -4.398], normal: [0, 0, 1], up: [0, 1, 0], size: [0.6, 0.55] },
  { id: 'H4', tex: 'decal_scuffs', pos: [-3.598, 2.95, -3.2], normal: [1, 0, 0], up: [0, 1, 0], size: [0.9, 0.3], tint: '#2b2622' },
  { id: 'H5', tex: 'decal_dirt_patch', pos: [-3, 2.752, -3.42], normal: [0, 1, 0], up: [0, 0, -1], size: [0.9, 1.3], tint: '#7a6450', opacity: 0.6 },
];
```
Notes: C3 assumes the closet ceiling under the landing is at y ≈ 2.30; set `pos.y = closetCeilingY − 0.45` so the hard top
edge of the streaks meets it. M7 is tilted to the 37° stair slope (`up` ⟂ the stair line in the wall plane) and passes
between `stairPhotoA` (z ≥ −0.08) and `stairPhotoB` (y ≥ 3.22). The scuffs are white smears tinted `#2b2622`
(rubber marks); N9 runs along the doorway → shelf path (`up` = −X). For variety, the same texture can be mirrored with
`scale.x = -1` on the quad.

---

## B3.6 Realism / integration notes

* **Fluorescent tube scare**: the nook is "no working light". When the breaker is flipped, start the batten:
  2–4 fast stutters (emissive 0 ↔ 3, a cold PointLight `0xdfe8ff` at (2.55, 2.35, −3.95) following it, `light_buzz`
  louder near it), then a steady but slightly pulsing light, or let one tube die after 2 s. It lights the panel, the
  rust drip and the shelves from above, as in the storage-room reference.
* **Hallway (win view)**: the warm pendant at scale 0.6 hangs in the middle of the view through the door, with the
  brick wall behind it and the crackled ceiling lit from below (QA render `scene_a2.png`, bottom-left). Light: PointLight
  `0xffb870`, ~2700 K, at (−3.0, 4.55, −4.0), `castShadow` on high/ultra (the shade casts the ceiling crackle into
  shadow), emissive intensity ≈ 1 on the lamp; add bloom. The batch-2 `suitcaseHall` + `hallLantern` give the
  "someone left in a hurry" read.
* **Decal lighting**: the decals use `MeshStandardMaterial`, so they react to the flashlight (the wet leak streaks are
  shinier, rough 0.42, the mould and dirt are matte). Keep `depthWrite: false` + `renderOrder: 2` so they never hide
  props, and `receiveShadow: true`.
* **Shelves look**: the pine boards of `steel_frame_shelves_02` are clean: tint them, or put `decal_dirt_patch`
  quads (0.5 × 0.45 m, opacity 0.5) on the boards at the board-top heights for dust.
* **Ladder**: only `wooden_ladder_supports` rotates; the open ladder (rotation identity) is 0.96 m deep along X, so it
  cannot stand open in the nook without blocking the `alcoveIn–alcoveEast` link. The folded pose of §B3.4 was solved
  numerically (the support feet sink 5 mm into the floor and the step feet float 5 mm above it; the supports' top rests
  5 mm off the wall, the steps lean on them, as a stored ladder does) and render-checked.

---

## B3.7 Considered and not included

* `steel_frame_shelves_01` (1.10 m wide): its source vertices are at 10× scale (fixed in `opt_b3.mjs`), but no free wall
  in the nook takes a 1.1 m unit without moving the toolbox and the gnome; two `_02` units cover the look. `_03` is a
  2.35 m wooden shelf with drawers (too big).
* `drawer_cabinet`: modern black frame + light wood drawers (reads IKEA, not a 90s filing cabinet); 26k tris.
  `metal_office_desk` (a good grey steel desk) is 2.0 m wide: it does not fit the 1.65 m-deep nook.
* `caged_hanging_light` (green caged tube on rods): very on-mood, but it hangs 0.75 m (bottom at 1.75 m, head height) and
  the user asked for the mounted tube. `industrial_wall_lamp` (bulkhead) and `old_military_crate` (two 0.9 m crates,
  619 kB) also skipped for space.
* `wooden_ladder_02` (1.72 m, single mesh: cannot fold), `plastic_crate_03` (783 kB, 14k tris).
* Decal sources: ambientCG `Leaking012`–`019` have no opacity map (they are metal-sheet leak materials),
  `Footsteps00x` have no opacity (deep prints in snow), `Leaking001`–`005` are close variants of `Leaking003`,
  `SurfaceImperfections013` (floor crumbs) dropped to stay at 10 decal sets. Neither site has a CC0 "water ring" or
  "mould patch" decal: both are derived (§B3.2). No handprint decal exists: `Fingerprints009` (smudged prints) is used.
* Poly Haven `dirty_tiles` is dark red (not the beige reference); `concrete_wall_008` (cleaner panels) and the
  ambientCG `Concrete031/033/044B` were darker/flatter than `concrete_wall_007`; `red_brick_plaster_patch_02` (brick
  with plaster remnants) is a good alternative end wall.

## B3.8 Sources (all CC0)

Textures:
* Poly Haven (https://polyhaven.com, CC0): [herringbone_parquet](https://polyhaven.com/a/herringbone_parquet)
  (Jenelle van Heerden, Sergej Majboroda), [decrepit_wallpaper](https://polyhaven.com/a/decrepit_wallpaper) (Rob Tuytel),
  [peeling_painted_wall](https://polyhaven.com/a/peeling_painted_wall) (Dimitrios Savva),
  [concrete_wall_007](https://polyhaven.com/a/concrete_wall_007) (Dario Barresi, Rico Cilliers, Charlotte Baglioni),
  [worn_cracked_plaster](https://polyhaven.com/a/worn_cracked_plaster) (Amal Kumar),
  [brick_wall_001](https://polyhaven.com/a/brick_wall_001) (Rob Tuytel, Dimitrios Savva).
* ambientCG (https://ambientcg.com, CC0): [Tiles094](https://ambientcg.com/a/Tiles094),
  [Leaking003](https://ambientcg.com/a/Leaking003), [Leaking008](https://ambientcg.com/a/Leaking008),
  [Leaking006](https://ambientcg.com/a/Leaking006), [Leaking010C](https://ambientcg.com/a/Leaking010C),
  [SurfaceImperfections001](https://ambientcg.com/a/SurfaceImperfections001),
  [SurfaceImperfections002](https://ambientcg.com/a/SurfaceImperfections002),
  [SurfaceImperfections008](https://ambientcg.com/a/SurfaceImperfections008), [Smear005](https://ambientcg.com/a/Smear005),
  [Fingerprints009](https://ambientcg.com/a/Fingerprints009), [Wallpaper002C](https://ambientcg.com/a/Wallpaper002C).

Models (Poly Haven, CC0; author in parentheses):
[steel_frame_shelves_02](https://polyhaven.com/a/steel_frame_shelves_02) (James Ray Cock),
[mounted_fluorescent_lights](https://polyhaven.com/a/mounted_fluorescent_lights) (Ulan Cabanilla),
[hanging_industrial_lamp](https://polyhaven.com/a/hanging_industrial_lamp) (Kuutti Siitonen),
[wooden_ladder](https://polyhaven.com/a/wooden_ladder) (Miroslav Turura), [plastic_crate_01](https://polyhaven.com/a/plastic_crate_01) (PierreB3D),
[medical_box](https://polyhaven.com/a/medical_box) (Ulan Cabanilla), [Lantern_01](https://polyhaven.com/a/Lantern_01) (Rajil Jose Macatangay),
[metal_jerrycan](https://polyhaven.com/a/metal_jerrycan) (Sean Buckley).
