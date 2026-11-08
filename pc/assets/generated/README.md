# `res://assets/generated/` — exporter outputs (web build → Godot)

Everything in this folder except the `.gd` helpers and this README is produced by **`node tools/export-godot.cjs`**
from the web reference build (`src/**`). Do not edit the outputs by hand: change the web code and re-run the exporter
([Re-running](#re-running)). Owner: the *exporter* module (`pc/ARCHITECTURE_PC.md` §1 / §4).

| File | What it is |
|---|---|
| `level.glb` (3.4 MB) | every **procedural** mesh of the web level: architecture shell, stairs, railing, doors, closet, laundry nook, window + outside, upstairs hallway, procedural props and items (batteries, key, notes, padlock, lever…), decals, canvas-textured planes (drawings, photos, outlets…), clutter, laundry cloth, the lighting meshes (fan bowl, door strip) — 157 nodes, 125 meshes, 61 k triangles. **Not** the instances of `res://assets/models/*.glb`: Godot instances the originals itself (best fidelity) from `level_meta.json`. |
| `level_shadow_casters.glb` | the web build's invisible thick boxes that only cast shadows (the visible walls are single-sided and only *receive*) → `cast_shadow = SHADOWS_ONLY` |
| `level_meta.json` | how to rebuild the level exactly: 52 model instances, attachments, handles (closed/open transforms), items, clues, TV, hide spot, digit decals, colliders, occluders, proxies, lights (reference), runtime helper nodes |
| `gardienne.glb` (7 MB) | La Gardienne: 5 `SkinnedMesh` (body, head, teeth, gown, hair) + eyes/glints on one 93-bone skeleton (incl. 9 simulated hair chains, skirt spring, jaw/mouth/lip bones) with **9 baked clips** (30 fps) |
| `gardienne_meta.json` | clips (loop, duration, in-place speed, gait cycle, footstep times), bones (rest pose), meshes, attach points, material notes |
| `textures/shared/*.jpg` | byte-exact copies of the `assets/textures/<set>/*.jpg` maps the procedural materials use |
| `textures/level/*`, `textures/gardienne/*` | procedural canvas textures (PNG when they have alpha or are ≤ 512² normal maps, JPEG otherwise) |
| `textures/notes/*` | note 1, the child drawing (note 2), the newspaper clipping (note 3, PNG cut-out), the child's code note, the 4 wall drawings — real fonts (Caveat, Special Elite, Rock Salt) — for the UI |
| `textures/decals/*.png` | `digit_marker_<d>` (under the duck), `digit_tape_<d>` (under the horse), `tv_digit_<d>` (white glyph mask for the TV static) |
| `*.import` | import presets: textures **VRAM compressed + mipmaps** (normal maps as RGTC normal maps), scenes with name-suffix hints **off**, `gardienne.glb`: loop modes per clip + `RESET` from the rest pose, GI off |
| `meta_util.gd` | reference loader: `MetaUtil.assemble(parent, meta)` rebuilds the whole level from the meta (used by both checks) |
| `_check.gd` | headless self-test → `EXPORT CHECK OK` |
| `_preview.gd` | rendered check (xvfb + Vulkan) with stand-in lights; `--gardienne --anim=walk` adds her |

Total ≈ 30 MB.

## Conventions

* **Coordinates**: metres, +Y up, north = −Z — identical in the web build, glTF and Godot. No conversion anywhere.
* **Matrices** in the metas: 16 floats, **column-major** (three.js `Matrix4.elements`).
  `MetaUtil.mat16(a)` = `Transform3D(Basis(Vector3(a[0],a[1],a[2]), Vector3(a[4],a[5],a[6]), Vector3(a[8],a[9],a[10])), Vector3(a[12],a[13],a[14]))`.
  `transform` = world (global) transform; `local` = transform relative to the stated `parent`.
* **Refs** (`ref`, `parent`, `object`, `node`…): `{ "level": "<node name in level.glb>" }` |
  `{ "instance": "<instances[].name>" }` (the instance root) | `{ "instance": "…", "node": "<NodePath inside the model scene>",
  "surface"?: n }`. Model node paths are the Godot names of the glTF nodes (Godot 4.5 naming v2: `. : @ / " %` → `_`,
  duplicates get `2`, `3`…), validated against the imported scenes by `_check.gd`.
* **Level node names** are unique in the file and Godot-safe (`[A-Za-z0-9_]`: `dresser.drawerTop.contents` →
  `dresser_drawerTop_contents`); unnamed web objects got role names (`endTable_drawer_contents`,
  `powerBox_lever_pivot`, `lockedBox_lock_shackle`, `rockingChair_pivot`, `decal_N`, `prop_N`…).
* **Colours**: `srgb` = hex as authored (use it for `albedo_color` / `light_color`), `linear` = three.js working values.

## Rebuilding the level (what `MetaUtil.assemble()` does — the world module may use or copy it)

1. Instantiate `level.glb`. Hide `level.hidden` (`upperHall` — shown while `door.upstairs` is open —, `tv_screen`,
   `extra_crt_screen`), `cast_shadow = OFF` on `level.noCastShadow`, apply `level.materialHints` (additive blending,
   no depth write → `TRANSPARENCY_ALPHA` + `DEPTH_DRAW_DISABLED`, polygon-offset decals → `render_priority`).
2. Instantiate `level_shadow_casters.glb`, every mesh `SHADOWS_ONLY`.
3. Each `instances[]`: instantiate `scene` (`res://assets/models/<model>.glb`), set its **exact** world transform
   (checked: 0.000000 m error), remove `hiddenNodes` (variants the web build deletes: inflated football, second
   suitcase…), apply `nodeTransforms` (original nodes the web build moved: cabinet drawers/doors closed, power box door
   closed, toolbox lid closed, clock hands…), `materialOverrides` (duplicate the surface material, set the listed
   fields: kid-chair paint, frame artwork/glass, broom straw & laundry basket alpha, toolbox roughness…), shadow flags.
4. `attachments[]` (17): procedural level nodes that belong to a model node (drawer/cabinet `contents`, breaker lever,
   box lid hinge + frame, TV / CRT screens, mirror glass, laundry cloth, chain pivot) → `reparent(parent, false)`,
   `transform = local`.
5. `reparent[]` (2): original model nodes the web build moved under a procedural pivot (box lid → `lockedBox_lid`
   hinge, pull chain → `extra_socket_chain_pivot`) → same.
6. Instances with a `parent` (the flashlight in the top dresser drawer, the rocking chair in `rockingChair_pivot`).

Then every ref resolves with `MetaUtil.find(ctx, ref)`; `_check.gd` verifies all of them.

## `level_meta.json`

* `instances[]`: `{ name, model, scene, path (web scene path), transform, parent?, local?, visible?, hiddenNodes[],
  mergedNodes[]? (nodes the web build only merged into one draw call — keep them), nodeTransforms[{node, local}],
  materialOverrides[{node, surface, material, set: {albedo{srgb,linear,alpha}, roughness, metalness, alphaTest,
  transparent, doubleSided, depthWrite, blending, alphaToCoverage, emissive…, envMapIntensity (info), geometryChanged?,
  textures{albedo_texture: {path, uv1_scale, uv1_offset} | null, normal_texture: null…}}}], noCastShadow[], castShadow? }`.
* `handles{id}` (14): `{ id, kind (door|drawer|cabinetDoor|lever|lid|padlock), object, moving[{ref, path, closed, open,
  restored}]` — LOCAL transforms of every node that moves, **measured by opening and closing each handle in the page** —
  `primary` (index of the node to tween), `contents?`, `contentsParent?`, `locked`, `initiallyOpen` (the breaker lever
  starts ON = open), `duration[open, close]` (s), `sfx{open: [name, volume, rate], close}`, `ease?`, `note?` }.
  `Handle.node/closed_xform/open_xform` = `find(moving[primary].ref)`, `mat16(closed)`, `mat16(open)`
  (`MetaUtil.make_handle_xforms`). The padlock moves body + shackle: see `anim.padlock` for its fall.
* `items{id}` (7): `{ ref, inside (handle whose contents hold it), parent, local, transform, name }`.
* `clues` (`duck`, `horse`, `clock` → `grandfather`, `tv`), `tv` (`object`, `screen` = the curved screen mesh,
  `screenPosition`, size, curvature, web colour), `hideSpots[]` (closet bounds, `hidePos`, `hideYaw`, `exitPos`, `door`),
  `clueDecals{duck, horse}` (parent instance, `local`, `size`, style → `textures/decals/digit_<style>_<d>.png`).
* `colliders[]` (45 web AABBs: `min`, `max`, `tag`, `enabled`), `occluders[]` (50 sight blockers: transform + local box),
  `proxies[]` (56 invisible ray-test boxes: `interact_*` interaction proxies, handle/item hit boxes, wall/door occluders;
  `owner` = handle / item).
* `lights[]` (reference only — the look module owns lighting): type, colour, intensity (three.js physical units × the
  web exposure 0.11), distance, decay, angle, penumbra, shadow, position/target, `owner` (world | player | entity).
* `anim{}`: nodes the world module animates + the web formulas: `fan`, `grandfatherClock` (clue digit = hour hand),
  `alarmClock`, `rockingChair`, `padlock` (dials, shackle, fall), `lever`, `smokeDetectorLed`, `codeNote`, `mirror`
  (glass + plane), `oldCrt`, `pullChain`, `ceilingBowl`, `doorStrip`, `upperHall`.
* `level.skipped[]`, `warnings[]`: see below.

## Materials & textures

The exporter converts the three.js materials itself (GLTFExporter only writes nodes/geometry/skins/animations):

* Every texture UV transform (repeat/offset/rotation) **and `flipY` is baked into the exported UVs** (Godot honours a
  single `uv1` transform per material). When the maps of one material used different transforms, they are re-sampled
  into the UV space of the least-repeating map: rug colour + carpet normal, shirt alpha + fabric normal, the gown tears
  + fabric ×7×5. When both maps tile, the ratio is **snapped to whole tiles** so the result stays seamless (ceiling
  knockdown normal/AO 1.36 → 1 per stucco tile, hallway wallpaper 2.83 → 3 per plaster tile) — listed in `warnings[]`.
* `alphaMap` (not in glTF) is merged into the base-colour alpha (laundry shirt, window grime, gown tears).
* Roughness/metalness maps are packed glTF-style (G = roughness, B = metalness); AO stays separate.
* Vertex colours (baked grime/AO of the architecture, cloth tints, crayons) are exported only where the web material
  used them; Godot imports them as `vertex_color_use_as_albedo` (linear multiply, like three.js).
* Colour factors above 1 (the wall albedo ×1.5) are kept (Godot reads them, `extras.overbright`); emissive intensity
  → `KHR_materials_emissive_strength` (→ `emission_energy_multiplier`, e.g. fan bowl 8.25).
* three.js-only flags travel in each material's `extras` (Godot: material metadata `extras`) and in
  `level.materialHints`: `polygonOffset`, `depthWrite`, `blending`, `toneMapped`, `envMapIntensity`, `envZone`.
* Godot 4.5 does **not** import `KHR_materials_clearcoat / sheen / specular / ior` (written anyway): set them by hand
  if wanted (skin clearcoat 0.12, teeth 0.7, eyes 1.0, gown sheen 0.7 — see `gardienne_meta.json → materials[].extras`).
* Images are external files next to the GLBs (no embedded duplicates; Godot imports them with the presets in their
  `.import` files and the GLB importer picks the imported textures up). Re-exports keep unchanged files byte-identical.

## La Gardienne

Built in the page from `src/entity/GardienneModel.js` and exported in its **rest pose** (Godot bone rests = the web
bind pose, `RESET` = rest). Clips are baked by stepping `model.update(dt, ctx)` at 60 Hz and sampling every bone's local
position + rotation at **30 fps**: the hair verlet chains, the skirt spring, the jaw / mouth / snarl bones and the root
bob are all in the clips. The random glitches (pose freezes, head snaps, arm spasms) are disabled while baking (do them
procedurally on top) and `Math.random` is seeded (deterministic export).

| clip | baked from | loop | speed (m/s) | cycle (s) |
|---|---|---|---|---|
| `idle` | idle, one breathing period (5.03 s) | yes | 0 | – |
| `walk` | walk, 2 gait cycles | yes | 0.947 | 1.267 |
| `walk_stairs` / `walk_stairs_down` | walk, stairs ±1 (shorter steps, leg lift / reach), 3 cycles | yes | 0.779 | 0.956 |
| `duck_walk` | walk under the stairwell bulkhead (`duck = 1`) | yes | 0.947 | 1.267 |
| `search` | listening: jerky scans + head tilts (4 s) | yes | 0 | – |
| `chase` | chase, 4 cycles (claws, jaw working) | yes | 2.892 | 0.692 |
| `reach` | door / closet reach, right arm (3 s) | yes | 0 | – |
| `jumpscare` | lunge, arms rise, head snap, jaw drop, hair parting (from a chase pose), 1.8 s | no | 0 | – |

* Loops: gait clips hold a whole number of gait cycles (speed nudged < 1 % so a cycle is a whole number of frames);
  the frames after the end are cross-faded into the start (`loopBlend`), last key = first key. Loop modes come from
  `gardienne.glb.import`.
* All clips are **in place** (no root motion): `AnimationPlayer.speed_scale = actual_speed / clip.speed`.
  `footsteps[]` = heel strikes (`t`, `side`) for her footstep sounds.
* Not baked, add on top: head look-at (web split of the look yaw: chest 0.12, neck 0.35, head 0.55; pitch: neck 0.3,
  head 0.75), glitches, the jumpscare root motion (the entity places her face in front of the camera).
* `attach`: face = head bone + (0, 0.06, 0.1), eyes = + (0, 0.09, 0.07), head = + (0, 0.07, 0).
  Eye shine: glint material emission energy = 0.25 + eyeshine × 7.

## Not exported (`level_meta.json → level.skipped`, `warnings`)

* **Custom shaders** — rebuild in Godot: the moonlight volumetric shaft (`lighting/moonShaft`, ShaderMaterial), the
  dust motes and bulb sparks (`THREE.Points`), the live mirror reflection (`Reflector`: use a planar mirror /
  `ReflectionProbe`; the silvered glass `extra_mirror_glass` *is* exported), the teletext menu screen (`ui.tvMenu`, UI),
  the glow billboards (`lighting/bowlGlow`, `lighting/tvGlow` sprites → Godot glow/bloom).
* Invisible helpers → meta only: interaction / hit / occluder boxes (`proxies[]`, `occluders[]`), shadow casters
  (→ `level_shadow_casters.glb`).
* The duck / horse **digit decals** (random code each game) → `clueDecals` + `textures/decals/`.
* Meshes the web build merged from model nodes (books, cassette player): the original nodes are kept (`mergedNodes`).
* The picture-frame glass of `extra_stairPhoto*` got generated UVs in the web build (dust map); Godot keeps the
  original UV-less primitive (`geometryChanged`).
* La Gardienne is not in `level.glb` (her own file); the player's flashlight and camera rig are not exported.

## Re-running

```bash
THREE_DIR=/path/to/node_modules/three \   # three@0.170.0 (offline); without it the CDN is used
FONTS_DIR=/path/to/google-fonts \        # saved Google Fonts CSS (fonts.css) + s_<family>_<version>_<file>.woff2 files:
                                         # real handwriting / typewriter fonts in the notes (else browser fallbacks)
node tools/export-godot.cjs [--only level,gardienne,textures] [--out pc/assets/generated]
godot --headless --path pc --import
godot --headless --path pc -s res://assets/generated/_check.gd          # → EXPORT CHECK OK
xvfb-run -a -s "-screen 0 960x540x24" godot --path pc --rendering-driver vulkan --resolution 960x540 \
  -s res://assets/generated/_preview.gd -- --out=/abs/prefix --views=spawn,overview,kids,nook,landing [--gardienne --anim=walk]
```

The exporter takes the machine-wide browser lock of `tools/shot.cjs` (`NO_LOCK=1` skips it; hold the same lock for
the Vulkan preview). Nothing is drawn in the page (`Renderer.render/warmup` and `Lighting.bakeEnvironment` are stubbed
by a prelude served with `/src/main.js`): a full export takes ≈ 40 s even in software GL.
