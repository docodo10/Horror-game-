# Surfaces module (`pc/scripts/surfaces/`) — photographic surfaces for the basement level

Owner: **surfaces** (ARCHITECTURE_PC.md §7). Files: `scripts/surfaces/**`, `shaders/surface_*.gdshader` (+ the shared
include `shaders/surface_common.gdshaderinc`), `assets/hires/**` (+ their `.import`).

Why: the web build's 1K, web-optimised maps applied almost without variation make the walls read like flat colour
("la texture des murs est mal travaillée"). This module swaps the architecture's materials for world-space **2K PBR
shaders with layered, non-repeating wear**, replaces the web decal quads with **hi-res Godot Decals**, and gives the hero
furniture the **2K maps** of the same Poly Haven assets.

## API and wiring

```gdscript
# scenes/main.gd (core) — right after the world is built, and again whenever the quality preset changes
await world.build(...)
Surfaces.apply(world, Settings.get_value("quality", "high"))          # low | medium | high | ultra
# Events.settings_changed: if key == "quality": Surfaces.apply(Game.world, value)
```

* `Surfaces.apply(level_root, quality)` — `level_root` = any ancestor of the assembled level (World or GeneratedLevel).
  Idempotent: materials, textures and decals are cached in static vars; a re-apply only re-assigns overrides and toggles
  visibility (≈ 2 ms); the first call loads ~80 textures (0.15–0.3 s headless, 0.4–0.7 s under software Vulkan).
  Never fails on a missing node / texture: one `push_warning` per missing role, set or texture.
* `Surfaces.restore(level_root)` — original materials and web overlays back, decals freed.
* `Surfaces.hidden_web_overlays()` → `{nodes, materials}` hidden on medium+ (for checking a re-export).
* `Surfaces.stats` — last apply: `{quality, ms, materials, models, roles: {role: [nodes]}, kept, missing, hidden, decals}`.

### Matching by role (robust to re-exports)
`recipes.gd` maps meshes to **roles**: node name first (`arch_<web material key>`, stable across exports; a duplicate
suffix `_2` is tolerated), the glTF **material name** as a fallback, then a **variant** chosen from the original albedo
map path: the re-exported nook (web Details pass: `concrete_wall_007`) gets the `nook_concrete` recipe instead of the
painted block; the re-exported hall ceiling (`worn_cracked_plaster`) keeps its web material (listed in `stats.kept`).
`REQUIRED_ROLES` missing from the level are warned once.

### Web meshes replaced on medium+ (shown again on low)
`Recipes.HIDE_NODES = ["decals_basement", "decals_hall", "details_carpetWear", "details_wallGrime"]` and any mesh whose
material is `details_decals`, `details_carpetWear`, `details_wallGrime`, `decal_mat*` or `stain` (current export:
`decal`, `decal_2`…`decal_6`, `architecture_mesh` = the ceiling stain by the window). The 53 web decals
(`src/config/layout.js DECALS`, main `3959e88`) are re-created as Godot Decals (`decal_table.gd`, or `Layout.DECALS`
when the generated layout carries it); the carpet-wear overlay and the lower-wall grime band are covered by the carpet
and wall shaders (traffic paths / stains; grime band, kicks, specks, scratches).

## Inventory of the assembled level (current export, commit 9147b03)

UVs of `level.glb` are world metres × the web repeat (baked by the exporter); the shaders ignore them and project in
world space (except the hall wallpaper print). "Recipe" = what this module does on medium+.

### Architecture / procedural materials (`level.glb`)

| material | nodes | web maps (1K) / tile | covers | recipe (2K set, tile) |
|---|---|---|---|---|
| `beige_wall_001` | `arch_wall` | beige_wall_001 colour/rough/normal/ao, 2.2 m, ×(1.5,1.6,1.36), vertex AO/grime | main room walls, bulkhead, reveals | `wall_room`: wall shader, `wall_plaster` 2 m |
| `beige_wall_001_2` | `arch_wallStair` | same, envZone 0.85 | stairwell walls (to 5.2 m) | `wall_stair` (+ hand smudges, grime follows the nosing line) |
| `white_stucco_2` | `arch_ceil` | white_stucco colour/rough 1.5 m + ceiling_interior normal/ao 1.1 m | room ceiling + bulkhead | `ceil_room`: ceiling shader, `ceiling_knockdown` 1.25 m, heat stain over the fan light |
| `white_stucco_3` | `arch_ceilStair` | same | stairwell ceiling (5.2 m) | `ceil_stair` |
| `white_stucco` | `arch_hallCeil` | same | upper-hall ceiling | `ceil_hall` (kept if re-materialed by the web) |
| `carpet016` | `arch_carpet` | Carpet016 colour/rough/normal/ao 1 m, ×(0.9,0.87,0.82), vertex dust | room carpet | `carpet_room`: carpet shader, `carpet` 0.9 m, 10 traffic lanes |
| `carpet016_2` | `arch_carpetStair` | same | treads, bullnose nosings, landing | `carpet_stair`: worn tread centre (x −3.05), dirty nosings |
| `trim` | `arch_trim`, `closetLeaf` | white semi-gloss 0xe6dfd0 r 0.36 + white_stucco normal 0.5 m | baseboards, casings, window, shoe rail, balusters, louvred closet door | `trim` / `door_closet`: trim shader, `trim_paint` 1 m |
| `trimStair` | `arch_trimStair` | same | risers + skirt boards | `trim_stair` (more chips / scuffs) |
| `doorPaint` | `doorSlab_2` | same | upstairs door (stair side) | `door_stair` |
| `hallTrim` | `doorSlab`, `arch_hallTrim` | same | hall trims, door (hall side) | `door_hall`, `trim_hall` |
| `nookBlock` | `arch_nookBlock` | canvas block map/normal 1.6 m, envZone 0.45 | nook N/E foundation walls | `nook_block`: wall shader, `block_paint` 2.3 m, damp + efflorescence + mould + rust streaks (`nook_concrete` after the re-export) |
| `white_stucco_5` | `arch_nookDrywall` | white_stucco 1.8 m ×0.78 | nook W/S drywall | `nook_drywall` (heavy grime, damp, tape joints) (`nook_concrete` after the re-export) |
| `closetBlock` | `arch_closetBlock` | canvas block | closet foundation wall | `closet_block` |
| `white_stucco_4` | `arch_closetWall` | white_stucco ×(0.62,0.57,0.5) | closet drywall back paper | `closet_wall` |
| `hallWall` | `arch_hallWall` | canvas wallpaper print (UV 0.53 m) + beige normal | upper-hall walls | `hall_wall`: wall shader, print kept (mesh UV) × `wallpaper` relief/stains 1.4 m |
| `stain`, `decal_mat*` | `architecture_mesh`, `decal…decal_6` | canvas stain / grime quads | web decals | hidden (Godot Decals) |
| `stained_pine(_2)`, `wood_floor_worn` | `arch_wood`, `arch_hallWood`, `arch_hallFloor` | stained_pine 1.2 m / wood_floor_worn 1.4 m | handrail, newel, threshold / hall floor | kept |
| `nookFloor`, `closetFloor`, `nookWood`, `closetWood` | `arch_nookFloor`, `arch_closetFloor`, `arch_nookWood`, `arch_closetWood` | canvas concrete 2 m / lumber 1.2 m | nook & closet floors, joists | kept (Decals add dirt / drain stain) |
| `brass`, `copper`, `galv`, `pvc`, `foil`, `iron`, `glass`, `web`, `sky`, `ground`, `snow`, `grass` | `arch_*` | flat / canvas | hardware, pipes, ducts, window, cobwebs, outside | kept |
| props (`*_mat`) | notes, drawings, outlets, switch, toys, batteries, key, lever, TV / CRT screens… | canvas | small procedural props | kept |

The complete per-material dump (108 materials, factors, extras) is reproducible with
`scratchpad/surfaces/scripts/inventory_md.py` (see § Rebuilding).

### Hero furniture (model instances, `res://assets/models/*.glb`, embedded 1K WebP)

| instance(s) | model / material | game maps | upgrade (medium+) |
|---|---|---|---|
| `dresser` | GothicCommode_01 | 1024² webp albedo, metal-rough, normal | Poly Haven 2K diff / nor_gl / arm |
| `sofa` | sofa_03 (+ `sofa_03_fringe`, alpha) | 1024² webp | 2K diff / nor_gl / rough (fringe kept: alpha) |
| `grandfather` | vintage_grandfather_clock_01 (+ `_glass`, alpha) | 1024² webp | 2K (glass kept) |
| `console` | ClassicConsole_01 | 1024² webp | 2K |
| `chairA`, `chairB` | painted_wooden_chair_02 | 1024² webp | 2K |
| `kidChair` | painted_wooden_chair_01 (paint override kept) | 1024² webp | 2K |
| `shelves` | painted_wooden_shelves | 1024² webp | 2K |
| `alcoveShelf` | Shelf_01 | 1024² webp | 2K |
| `alcoveCabinet` | painted_wooden_cabinet | 1024² webp | 2K |
| `coffeeTable` | small_wooden_table_01 | 1024² webp | 2K |
| `endTable` | painted_wooden_nightstand | 1024² webp | 2K |
| `kidTable` | side_table_01 | 1024² webp | 2K |
| `rockingChair` | Rockingchair_01 | 1024² webp | 2K |
| `tv` | television_02 | 512² webp | kept (small, CRT shader owned by world/ui) |

Upgraded materials are duplicates (cached per original material, `<name>_2k`); `assets/models/*` are untouched; metal
maps follow the original (arm B only where the original had a metallic map); AO from arm R.

## Shaders (world-space, dominant-axis planar projection, OpenGL normal maps rebuilt into a world TBN)

| shader | layers | fetches / px (high) |
|---|---|---|
| `surface_wall` | paint colour × high-passed texture detail (`textureLod` low-pass = anti-tiling), vertex AO, world macro value/hue, cavity dirt (AO / height), rising grime + dust line over the **walkable floor line** (room 0 m, stair nosing line, landing / hall 2.75 m), dust under the **ceiling line** (2.5 / 5.2 m), dirt in **inner corners** (16 corners from Layout, only those on the wall's own plane), rubber scuffs at kick and furniture height, greasy hand smudges (0.75–1.8 m), specks, pencil scratches, water run-down streaks from the top, rising damp + tide line + efflorescence, mould, drywall tape joints (1.22 m / 2.44 m), roller waviness and paint drips in the normal, roughness breakup | 14 (+6 waviness / drips on high) |
| `surface_ceiling` | off-white × knockdown luminance, cavity dust, edge / corner greying (room box), heat-smoke stain above the light, yellowed blotches, macro waviness | 8 (+3) |
| `surface_carpet` | 2-sample anti-tiling (2nd sample rotated 90° and scaled, blended by low-frequency noise), traffic lanes (darker, greyer, flattened pile, rougher), ground-in dirt, old spills, stair tread wear + dirty nosings, fabric rim | 11 |
| `surface_trim` | blended triplanar painted wood (grain / cracks through the paint), chips on worn spots + sharp edges (screen-space curvature), dust on top faces, dirt + scuffs near the floor, yellowing | 8–16 (axes with weight < 1 % skipped) |

`detail_level` (uniform) = 0 on medium: no waviness / joints / drips (saves 6 fetches on walls, 3 on ceilings). All
textures are VRAM-compressed with mipmaps and sampled with anisotropic filtering; no loops over textures (the corner
loop is 16 ALU iterations, the lane loop 10).

## Decals (`decal_table.gd`)

* **WEB** (53, from layout.js `DECALS`): leaks / pipe leak / rust drip / mould / water rings / rising damp in the nook,
  closet, stairwell and hall, rubber scuffs along the baseboards, hand smudges (closet door both sides, light switch, nook
  jambs, stair wall along the handrail), thermostat grime, dust ghost over the vent, crayon drawings (K1–K7, ours:
  `crayon_0..6`), dirt patches.
* **STORY** (10, ours): tide rings in the ceiling corner by the window + a run-down beside it, damp in the SE corner,
  mould behind the laundry basket and in the partition corner, **muddy footprints coming off the stairs**, a spill by the
  kids' corner, tracked dirt at the nook doorway, mould low in the closet, rust-water stain around the nook floor drain.
* Tier 1 (medium+, 35): leaks, rings, damp, rust, mould, hand smudges, crayons, footprints. Tier 2 (high / ultra, all 63):
  + scuffs, grime, dirt patches. Decals: albedo (straight alpha) + ORM (roughness: wet / greasy = glossier, mould = matte),
  `normal_fade` 0.5 (no smearing on perpendicular faces), box depth 0.1–0.14 m, distance fade 14–18 m.

## Quality presets and cost

| preset | materials | decals | VRAM added (computed) | GPU cost (estimate) |
|---|---|---|---|---|
| low | exporter originals (1K) | none (the web decal quads stay visible) | 0 | baseline |
| medium | 18 surface materials (4 shaders) + 24 furniture surfaces with 2K maps | 35 (tier 1) | ≈ 220 MB: 7 surface sets × 10.7 MB (BC1 albedo / mask + BC5 normal, mips) + shared 4 MB + 13 furniture sets × 10.7 MB, + the decal atlas (Godot keeps decals in one RGBA8 atlas: ≈ 6 M texels, 4096×2048 ≈ 45 MB with mips) | walls 14 fetches, carpet 11, ceiling 8 — roughly +0.2–0.4 ms at 1080p on a GTX 1060-class GPU, ×4 at 4K |
| high / ultra | + waviness, tape joints, paint drips | 63 (all) | same | walls 20 fetches — ≈ +0.3–0.6 ms at 1080p |

`apply()` timing: first call 0.15–0.3 s headless / 0.4–0.7 s under software Vulkan (texture loads + uploads, ~80
textures); re-apply / preset switch 1–3 ms. Ultra = high for this module (no further surface cost worth paying).

## Texture budget (`pc/assets/hires`, on disk)

| folder | MB | content |
|---|---|---|
| `wall_plaster`, `ceiling_knockdown`, `carpet`, `trim_paint`, `block_paint`, `concrete_wall`, `wallpaper` | 3.5 + 5.0 + 4.5 + 3.6 + 2.9 + 2.5 + 3.0 = 25.0 | 7 surface sets, 2048², 3 JPEG each |
| `shared` | 2.1 | fbm noise (512² PNG) + grunge masks (2K) |
| `decals` | 3.9 | 19 decal textures (straight-alpha PNG + ORM JPEG), 256–1024 px |
| `models` | 29.3 | 13 furniture assets × 3 maps, 2048² |
| **total** | **60.2** | 96 images, largest 2.4 MB (all < 20 MB) |

## Tests

```bash
godot --headless --path pc -s res://scripts/surfaces/tests/surfaces_check.gd          # -> SURFACES CHECK OK
pc/scripts/surfaces/tests/run_preview.sh -- --out=/abs/prefix --mode=both \
  [--views=spawn,stairs,kids,nook,tv,console,landing] [--quality=high] [--cams="name:x,y,z,yaw,pitch|..."]
```
`surfaces_check.gd`: real level, every preset twice (timing < 1 s, idempotency, single decal holder), all required roles,
low restores the exporter materials + web overlays, concrete-nook variant, null / unknown inputs.
`surfaces_preview.gd` (via `run_preview.sh`, render lock + xvfb): assembles the real level, a neutral warm TEST rig (2700 K
bowl light at the web's filament position (0.25, 1.92, 0.35) — the fan housing would shadow a light at y 2.3 — soft
shadows, low fill, nook bulb, a stairwell spill light, AgX, SSAO), renders before / after.

## Rebuilding the textures

Python 3 + Pillow + numpy scripts in `pc/scripts/surfaces/tools/` (run them with `python3 -I`, raw downloads in a
scratch dir outside the repo):

```bash
T=pc/scripts/surfaces/tools; RAW=/tmp/surf_raw; OUT=/tmp/surf_build/hires
python3 -I $T/download.py $RAW --res 2k ph:painted_plaster_wall ph:ceiling_interior ph:concrete_wall_007 acg:Carpet016 \
  acg:PaintedWood009C acg:PaintedBricks004 acg:Wallpaper002B acg:Wallpaper002C acg:Leaking003 acg:Leaking006 acg:Leaking008 \
  acg:Leaking010C acg:SurfaceImperfections001 acg:SurfaceImperfections002 acg:SurfaceImperfections008 acg:Smear005 \
  acg:Fingerprints009 acg:Footsteps004
python3 -I $T/download_models.py $RAW GothicCommode_01 sofa_03 vintage_grandfather_clock_01 ClassicConsole_01 \
  painted_wooden_chair_02 painted_wooden_cabinet painted_wooden_shelves Shelf_01 small_wooden_table_01 \
  painted_wooden_nightstand Rockingchair_01 side_table_01 painted_wooden_chair_01
python3 -I $T/process_surfaces.py $RAW $OUT && python3 -I $T/process_decals.py $RAW $OUT/decals
python3 -I $T/process_models.py $RAW $OUT && python3 -I $T/install_hires.py $OUT pc/assets/hires
godot --headless --path pc --import
```
`install_hires.py` writes the `.import` presets (VRAM compressed + mipmaps, normal-map mode for `normal.jpg`,
`noise.png` lossless). `inventory_md.py` dumps the material inventory of a level GLB; `write_decal_table.py` regenerates
`decal_table.gd` from the web DECALS list. Sources and licences: `pc/assets/hires/CREDITS.md`.

## Requests to other modules

* **core** — wire `Surfaces.apply(world, quality)` after `world.build()` and on every quality change (see top). Project
  settings that the hi-res surfaces need for grazing views of walls / carpet / decals:
  `rendering/textures/default_filters/anisotropic_filtering_level = 4` (16×) and
  `rendering/textures/decals/filter = 5` (Linear Mipmaps Anisotropic; default blurs the decals at grazing angles).
* **world** — keep the exporter's node names for the architecture meshes (`arch_*`, `closetLeaf`, `doorSlab*`) and the
  model instances; if the world assigns its own surface overrides to those meshes or rebuilds / re-instances the level
  (reset), call `Surfaces.apply` again afterwards (idempotent, 1–3 ms).
* **look** — tuned under a 2700 K bowl light at the web filament position (y 1.92) with a weak fill: grazing light from
  the bulb is what reveals the relief; a strong flat ambient (fill energy ≳ 0.3) washes the grime out. SSAO / SSIL /
  SDFGI and a reflection probe make the roughness breakup visible.
* **exporter / lead** — after the re-export (web Details pass), check `Surfaces.stats`: `hidden` must list
  `decals_basement`, `decals_hall`, `details_carpetWear`, `details_wallGrime`; `roles` must contain every required role;
  `kept` should list `arch_hallCeil` (crackled plaster kept) and the nook walls must report `surfaces_nook_concrete`.

## Known issues / limits

* The web stair treads are **carpeted** (Architecture.js: carpet treads, white risers, carpet-wrapped bullnose), not
  varnished wood: they get the carpet shader with a worn walking line and dirty nosings; the handrail / newel / threshold
  (`arch_wood`) and the hall floor keep their 1K stained wood.
* Godot Decals project onto everything inside their box (a character pressed against a wall / standing on a floor stain
  may catch it) and skip transparent surfaces: boxes are 10–14 cm thick, `normal_fade` 0.5.
* The re-export variants (concrete nook, kept hall ceiling) and `Layout.DECALS` support are tested synthetically
  (`surfaces_check.gd`) — the current export predates the web Details pass.
* The upper hall (win view) uses the current export's wallpaper print + our relief; the nook tiles / hall wainscot /
  brick of the Details pass will keep their web 1K materials until a recipe is added for them.
* Test renders use lavapipe (no SDFGI / SSIL, 960×540); the final balance depends on the look module's lighting.
