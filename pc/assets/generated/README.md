# `res://assets/generated/` — exporter outputs (web build → Godot)

Everything in this folder (except the `.gd` helpers and this README) is produced by
**`node tools/export-godot.cjs`** from the web reference build (`src/**`). Do not edit the outputs by hand: change
the web code and re-run the exporter (see [Re-running](#re-running)). Owner: the *exporter* module
(`pc/ARCHITECTURE_PC.md` §1/§4).

| File | What it is |
|---|---|
| `level.glb` | every **procedural** mesh of the web level (architecture shell, stairs, doors, closet, laundry nook, window + outside, hallway, procedural props, items, decals, canvas-textured planes, clutter, cloth, frames…) — **not** the instances of `res://assets/models/*.glb` (Godot instances the originals itself, best fidelity) |
| `level_shadow_casters.glb` | the web build's invisible thick boxes that only cast shadows (single-sided walls never leak light) → `cast_shadow = SHADOWS_ONLY` |
| `level_meta.json` | how to rebuild the level exactly: model instances, attachments, handles (closed/open transforms), items, clues, TV, hide spots, digit decals, colliders, occluders, interaction proxies, lights (reference), runtime helper nodes |
| `gardienne.glb` | La Gardienne: `SkinnedMesh` × 5 + eyes on one skeleton (bones incl. 9 simulated hair chains + skirt spring) with **baked animation clips** (30 fps) |
| `gardienne_meta.json` | clip list (loop, duration, in-place speed, gait cycle, footstep times), bones (rest pose), attach points, material notes |
| `textures/shared/*.jpg` | byte-exact copies of the `assets/textures/<set>/*.jpg` maps used by the procedural materials |
| `textures/level/*`, `textures/gardienne/*` | procedural canvas textures (PNG when they have alpha or are small normal maps, else JPEG) |
| `textures/notes/*.png` | note 1, the child drawing (note 2), the newspaper clipping (note 3), the child's code note, the 4 wall drawings — for the UI |
| `textures/decals/*.png` | `digit_marker_<d>` (under the duck), `digit_tape_<d>` (under the horse), `tv_digit_<d>` (white glyph mask, TV static) |
| `*.import` | import presets: textures **VRAM compressed + mipmaps** (normal maps RGTC), scenes with name-suffix hints **off**, `gardienne.glb` loop modes + `RESET` |
| `meta_util.gd` | reference loader: `assemble(parent, meta)` rebuilds the whole level from the meta (used by the checks below) |
| `_check.gd` | headless self-test: `godot --headless --path pc -s res://assets/generated/_check.gd` → `EXPORT CHECK OK` |
| `_preview.gd` | rendered check (xvfb + Vulkan), stand-in lights only |

## Conventions

* **Coordinates**: metres, +Y up, north = −Z — identical in the web build, glTF and Godot. No conversion anywhere.
* **Matrices** in the meta: 16 floats, **column-major** (three.js `Matrix4.elements`).
  `MetaUtil.mat16(a)` = `Transform3D(Basis(Vector3(a[0],a[1],a[2]), Vector3(a[4],a[5],a[6]), Vector3(a[8],a[9],a[10])), Vector3(a[12],a[13],a[14]))`.
  `transform` = world (global) transform; `local` = transform relative to the stated `parent`.
* **Refs** (`ref`, `parent`, `object`, `node`…): `{ "level": "<node name in level.glb>" }` |
  `{ "instance": "<instances[].name>" }` (the instance root) |
  `{ "instance": "…", "node": "<NodePath inside the model scene>", "surface"?: n }`.
  Model node paths are the Godot names of the glTF nodes (Godot 4.5 naming v2: `. : @ / " %` → `_`,
  duplicates get `2`, `3`…); they were validated against the imported scenes by `_check.gd`.
* **Level node names** are unique in the file and already Godot-safe (`[A-Za-z0-9_]`; `dresser.drawerTop.contents`
  becomes `dresser_drawerTop_contents`), so `find_child(name)` / a name index works (see `meta_util.gd`).
* **Colours**: `srgb` = hex as authored (use it for `albedo_color` / `light_color`), `linear` = three.js working values.

## How the level is rebuilt (what `MetaUtil.assemble()` does — the world module may copy it)

1. Instantiate `level.glb`. Hide `level.hidden` (e.g. `upperHall` — shown while `door.upstairs` is open —,
   `tv_screen`, `extra_crt_screen`), set `cast_shadow = OFF` on `level.noCastShadow` (the web build lets the big
   surfaces only *receive* and casts with the invisible boxes), apply `level.materialHints` (additive blending,
   no depth write → `TRANSPARENCY_ALPHA` + `DEPTH_DRAW_DISABLED`, polygon-offset decals → `render_priority`).
2. Instantiate `level_shadow_casters.glb`, every mesh `SHADOWS_ONLY`.
3. For each `instances[]`: instantiate `scene` (`res://assets/models/<model>.glb`), set the **exact** world
   transform, remove `hiddenNodes` (variants the web build deletes: deflated/inflated football, second suitcase…),
   apply `nodeTransforms` (original nodes the web build moved, e.g. a cabinet drawer authored half open, the power
   box door authored open, the clock hands), `materialOverrides` (duplicate the surface material and set the listed
   fields — kid chair paint, picture-frame artwork/glass, broom straw alpha, …), shadow flags.
4. `attachments[]`: procedural level nodes that belong to a model node (drawer `contents` groups, the breaker lever,
   the box lid hinge, digit decals, TV/CRT screens, laundry cloth…) → `reparent(parent, false)` then `transform = local`.
5. `reparent[]`: original model nodes the web build moved under a procedural pivot (box lid → `lockedBox_lid` hinge,
   pull chain → its swing pivot) → same.
6. Instances with a `parent` (the flashlight inside the top dresser drawer, the rocking chair inside its rocking
   pivot) → same.

After that every handle, item, clue… ref resolves with `MetaUtil.find(ctx, ref)`.

## `level_meta.json` reference

* `instances[]`: `{ name, model, scene, path (web scene path), transform, parent?, local?, visible?, hiddenNodes[],
  mergedNodes[]? (nodes the web build only merged into one draw call — keep them), nodeTransforms[{node, local}],
  materialOverrides[{node, surface, material, set:{albedo{srgb,linear,alpha}, roughness, metalness, alphaTest,
  transparent, doubleSided, depthWrite, blending, emissive, emissiveIntensity, clearcoat…, textures{albedo_texture:
  {path, uv1_scale, uv1_offset} | null, normal_texture…}}}], noCastShadow[], castShadow? }`.
* `handles{id}`: `{ id, kind (door|drawer|cabinetDoor|lever|lid|padlock), object (the web Handle.object), moving[{ref,
  closed, open}] (LOCAL transforms of every node that moves, **measured by opening and closing the handle in the
  page**), primary (index of the node to tween), contents?, contentsParent?, locked, initiallyOpen (the breaker
  lever starts ON = open), duration[open, close] (s), sfx{open:[name, volume, rate], close}, ease?, note? }`.
  `Handle.closed_xform/open_xform` = `mat16(moving[primary].closed/open)`. The padlock moves 2 nodes (shackle +
  body): see `anim.padlock` for the fall animation.
* `items{id}`: `{ ref, inside (handle id whose contents hold it), parent, local, transform, name }`.
* `clues` (`duck`, `horse`, `clock`, `tv` → instance refs), `tv` (`object`, `screen` = curved screen mesh,
  `screenPosition`, …), `hideSpots[]` (closet bounds, `hidePos`, `hideYaw`, `exitPos`, `door` handle id),
  `clueDecals{duck, horse}` (parent instance, `local`, `size`, style → `textures/decals/digit_<style>_<d>.png`).
* `colliders[]` (`min`, `max`, `tag`, `enabled` — the web build's AABBs: walls, furniture, doors…),
  `occluders[]` (sight blockers: transform + local box), `proxies[]` (invisible ray-test boxes: interaction proxies
  `interact_*`, handle/item hit boxes, door/wall occluders; `owner` = handle/item they belong to).
* `lights[]` (reference only — the look module owns lighting): type, colour, intensity (three.js physical units ×
  the web exposure), distance, decay, angle, penumbra, shadow, position/target, `owner` (world | player | entity).
* `anim{}`: nodes the world module animates + the web formulas: `fan`, `grandfatherClock` (clue digit = hour hand),
  `alarmClock`, `rockingChair`, `padlock` (wheels, shackle, fall), `lever`, `smokeDetectorLed`, `codeNote`,
  `mirror` (glass + plane), `oldCrt`, `pullChain`, `ceilingBowl`, `doorStrip`, `upperHall`.
* `level.skipped[]`: web objects not exported (see below). `warnings[]`: exporter notes (re-sampled textures…).

## Materials & textures

The exporter converts the three.js materials itself (GLTFExporter only writes the geometry/nodes):

* All texture UV transforms (repeat/offset/rotation) **and `flipY` are baked into the exported UVs** — Godot only
  honours one `uv1` transform per material (`KHR_texture_transform` of the base colour), the web materials often
  had several. When the maps of one material used different transforms (e.g. rug colour vs carpet normal, gown
  fabric ×7×5 vs the hem tears), they are re-sampled into the UV space of the least-repeating map (`warnings[]`).
* `alphaMap` (not in glTF) is merged into the base-colour alpha (laundry shirt, window grime, gown tears).
* Roughness/metalness maps are packed glTF-style (G = roughness, B = metalness); AO stays separate (Godot reads R).
* Vertex colours (baked grime/AO of the architecture) are exported only when the web material used them; Godot
  imports them as `vertex_color_use_as_albedo` (linear multiply, same as three.js).
* Colour factors above 1 (the web lifts the wall albedo ×1.5) are kept (`extras.overbright`); emissive intensities
  use `KHR_materials_emissive_strength` (imported by Godot as `emission_energy_multiplier`).
* three.js-only flags travel in each material's glTF `extras` (Godot imports them as material metadata `extras`)
  and in `level.materialHints`: `polygonOffset`, `depthWrite`, `blending`, `toneMapped`, `envMapIntensity`, `envZone`.
* Images are external files next to the GLBs (no duplicated embedded copies). Godot imports them with the presets
  in their `.import` files (VRAM compressed, mipmaps, normal maps as normal maps).

## La Gardienne (`gardienne.glb`, `gardienne_meta.json`)

Built in the page from `src/entity/GardienneModel.js` (the procedural skinned creature: body, head with rigged jaw /
mouth / snarl, teeth, eyes + glints, nightgown, ~hundreds of wet hair ribbons), exported in its **rest pose**
(Godot bone rests = the web bind pose). Clips are baked by stepping `model.update(dt, ctx)` at 60 Hz and sampling
every bone's local TRS at **30 fps** — the hair verlet chains, the skirt spring, the mouth/lip bones and the root
bob are all in the clips. Glitch twitches (pose freezes, head snaps, arm spasms) are disabled while baking (they
are random one-shots: do them procedurally on top), `Math.random` is seeded (deterministic export).

| clip | ctx | loop |
|---|---|---|
| `idle` | idle, one breathing period | yes |
| `walk` | walk 0.95 m/s, 2 gait cycles | yes |
| `walk_stairs` / `walk_stairs_down` | walk 0.78 m/s, stairs ±1 (shorter steps, leg lift / reach) | yes |
| `duck_walk` | walk under the stairwell bulkhead (`duck = 1`) | yes |
| `search` | listening: jerky scans + head tilts | yes |
| `chase` | chase 2.9 m/s, 4 cycles (claws out, jaw working) | yes |
| `reach` | door / closet reach (right arm) | yes |
| `jumpscare` | lunge, arms rise, head snap, jaw drop, hair parting (from a chase pose) | no |

* Loops: gait clips contain a whole number of gait cycles (speed nudged < 2 % so a cycle is a whole number of
  frames); the last frames are cross-faded into the first (`loopBlend`), last key = first key. The loop modes are
  set by `gardienne.glb.import` (`_subresources`), `RESET` = rest pose.
* All clips are **in place** (no root motion). `speed` (m/s) and `cycle` (s) in the meta give the speed the clip
  was baked for: `AnimationPlayer.speed_scale = actual_speed / clip.speed`. `footsteps[]` = heel strikes (`t`,
  `side`) for the footstep sounds.
* Head look-at (`ctx.look`) is not baked: add it on top (e.g. `LookAtModifier3D` / bone override on `neck` + `head`;
  the web split: chest 0.12, neck 0.35, head 0.55 of the yaw).
* Attach points (`attach`): face = head bone (0, 0.06, 0.1), eyes = (0, 0.09, 0.07), head = (0, 0.07, 0).
* Eye shine: the glint material emission energy = 0.25 + eyeshine × 7 (eyeshine 0.08 … 1).

## Not exported (listed in `level_meta.json → level.skipped`)

* **Custom shaders** (no glTF equivalent — rebuild them in Godot): the moonlight volumetric shaft (`Lighting.beam`,
  `ShaderMaterial`), the dust motes and the bulb sparks (`THREE.Points` + `ShaderMaterial`), the live mirror
  reflection (`Reflector`: use a planar mirror / `ReflectionProbe`; the silvered fallback glass *is* exported as
  `extra_mirror_glass`), the diegetic teletext menu screen on the TV (`ui.tvMenu`, owned by the UI module).
* Invisible helper meshes: interaction / handle hit boxes and occluder boxes (→ `proxies[]`, `occluders[]`), the
  shadow casters (→ `level_shadow_casters.glb`).
* The duck / horse **digit decals** (random code each game) → `clueDecals` + `textures/decals/`.
* Meshes the web build merged from model nodes (`_mergeStatic`: books, cassette player): the original model
  nodes are kept instead (`mergedNodes`).
* La Gardienne is not part of `level.glb` (her own file); the player's flashlight and the camera rig are not exported.

## Re-running

```bash
THREE_DIR=/path/to/node_modules/three \            # three@0.170.0 (offline); else the CDN is used
FONTS_DIR=/path/to/saved/google-fonts \            # fonts.css + s_<family>_<version>_<file>.woff2 (real handwriting fonts in the notes)
node tools/export-godot.cjs [--only level,gardienne,textures] [--out pc/assets/generated]
godot --headless --path pc --import
godot --headless --path pc -s res://assets/generated/_check.gd
```

The run takes the same machine-wide browser lock as `tools/shot.cjs` (`NO_LOCK=1` skips it). Nothing is rendered
(`Renderer.render/warmup` and `Lighting.bakeEnvironment` are stubbed in the page), so it is fast even in software GL.
