# `res://assets/hires/` — sources and licences (surfaces module)

Every source below is **CC0 1.0** (public domain, no attribution required; credited anyway). Downloaded on
2026-11-08 from the official APIs (Poly Haven `api.polyhaven.com`, ambientCG `ambientcg.com/api/v2`) at **2K**, then
re-encoded by the module's build scripts (see `pc/scripts/surfaces/README.md` § Rebuilding). Nothing here is a copy of
`assets/textures/` (the web build's 1K sets stay untouched).

## Surface sets (`<set>/albedo.jpg`, `normal.jpg` OpenGL Y+, `mask.jpg` = R ambient occlusion, G height, B roughness)

| set | source | author(s) | real tile | used for |
|---|---|---|---|---|
| `wall_plaster` | Poly Haven [painted_plaster_wall](https://polyhaven.com/a/painted_plaster_wall) | Amal Kumar | 2 m | painted drywall / plaster: main room, stairwell, nook drywall, closet |
| `ceiling_knockdown` | Poly Haven [ceiling_interior](https://polyhaven.com/a/ceiling_interior) | Dimitrios Savva | 2 m (used at 1.25 m) | knockdown ceilings (albedo = normalised luminance variation, grey RGB) |
| `carpet` | ambientCG [Carpet016](https://ambientcg.com/a/Carpet016) | ambientCG (Lennart Demes) | ~1 m (used at 0.9 m) | wall-to-wall carpet, carpeted stairs |
| `trim_paint` | ambientCG [PaintedWood009C](https://ambientcg.com/a/PaintedWood009C) | ambientCG (Lennart Demes) | ~1 m | baseboards, casings, risers, doors, balusters |
| `block_paint` | ambientCG [PaintedBricks004](https://ambientcg.com/a/PaintedBricks004) | ambientCG (Lennart Demes) | 1.55 m (used at 2.3 m) | painted block walls (nook, closet); albedo = normalised luminance |
| `concrete_wall` | Poly Haven [concrete_wall_007](https://polyhaven.com/a/concrete_wall_007) | Charlotte Baglioni (photo), Rico Cilliers (tiling), Dario Barresi (processing) | 2.16 m | nook walls of the re-exported level (web Details pass = cast concrete) |
| `wallpaper` | ambientCG [Wallpaper002B](https://ambientcg.com/a/Wallpaper002B) | ambientCG (Lennart Demes) | ~1.4 m | upper-hall wallpaper relief + damp stains (the web print stays the colour) |

## Shared masks (`shared/`)

| file | content |
|---|---|
| `noise.png` (512², RGBA, lossless import) | tileable FFT fbm: R large clouds, G medium mottling, B fine grain, A sparse blotches — generated (numpy, seeds 11-15), no source |
| `grunge.jpg` (2K) | R = ambientCG [SurfaceImperfections008](https://ambientcg.com/a/SurfaceImperfections008) opacity (smudges / spots), G = generated run-down streaks (170 procedural lines, tileable), B = ambientCG [Smear005](https://ambientcg.com/a/Smear005) opacity (scuff strokes) |

## Decals (`decals/<id>/albedo.png` straight-alpha RGBA, `orm.jpg` R occlusion / G roughness / B metallic)

Processed from the 2K sources and shipped at the resolution their size in the level needs (≈ 0.5–1.5 mm per texel):
Godot copies every decal texture into one uncompressed RGBA8 atlas, so oversized decals cost VRAM for nothing.

| id | px | source | processing |
|---|---|---|---|
| `leak_streaks` | 1024² | ambientCG [Leaking003](https://ambientcg.com/a/Leaking003) (2K, central half at full res) | opacity × side fades (top edge hard), tea-brown recolour |
| `rising_damp` | 1024×256 | ambientCG [Leaking008](https://ambientcg.com/a/Leaking008) | opacity × side fades (bottom edge hard), dark damp brown, glossier when wet |
| `pipe_leak` | 512×1024 | ambientCG [Leaking006](https://ambientcg.com/a/Leaking006) | central half × fan mask (narrow at the pipe), yellow-brown seep |
| `rust_drip` | 256×1024 | ambientCG [Leaking010C](https://ambientcg.com/a/Leaking010C) | central quarter, opacity × 1.6, rust brown |
| `hand_smudges` | 512² | ambientCG [Fingerprints009](https://ambientcg.com/a/Fingerprints009) | 1024 crop of the 2K, opacity × 1.35 × radial falloff, greasy = glossier ORM |
| `grime` | 512² | ambientCG [SurfaceImperfections008](https://ambientcg.com/a/SurfaceImperfections008) | (opacity − 0.15) × 1.5 × radial falloff |
| `scuffs` | 512×256 | ambientCG [Smear005](https://ambientcg.com/a/Smear005) | band crop, dark rubber |
| `dirt_patch` | 512² | ambientCG [SurfaceImperfections001](https://ambientcg.com/a/SurfaceImperfections001) | opacity × 1.6 × radial falloff, warm dirt |
| `footprints` | 256×1024 | ambientCG [Footsteps004](https://ambientcg.com/a/Footsteps004) | 4-print crop, print mask = darker than the ground, fades along the trail, mud brown |
| `water_ring` | 768² | derived from ambientCG [SurfaceImperfections002](https://ambientcg.com/a/SurfaceImperfections002) | procedural tide rings × source blotches, tea-brown |
| `mold` | 512² | derived from ambientCG [Wallpaper002C](https://ambientcg.com/a/Wallpaper002C) | darkness vs clean paper × noisy radial falloff, olive-black |
| `crayon_0..6` | 256² | generated (PIL) | children's crayon drawings (scribble, sun, house, stick family, zigzags, spiral, tally marks) with waxy grain dropout |

## Hero furniture (`models/<asset>/albedo.jpg`, `normal.jpg`, `arm.jpg` = AO / rough / metal, or `rough.jpg`)

The 2K maps of the **same Poly Haven assets** the game already ships (their GLBs in `assets/models/` embed 1K WebP and
stay untouched); re-encoded JPEG q86 (normals q88, 4:4:4), applied at runtime to the opaque materials only.

| asset | source | author(s) |
|---|---|---|
| `GothicCommode_01` | [Gothic Commode 01](https://polyhaven.com/a/GothicCommode_01) | Kirill Sannikov |
| `sofa_03` | [Sofa 03](https://polyhaven.com/a/sofa_03) | Fran Calvente |
| `vintage_grandfather_clock_01` | [Vintage Grandfather Clock 01](https://polyhaven.com/a/vintage_grandfather_clock_01) | Yann Kervran, James Ray Cock |
| `ClassicConsole_01` | [Classic Console 01](https://polyhaven.com/a/ClassicConsole_01) | Kirill Sannikov |
| `painted_wooden_chair_02` | [Painted Wooden Chair 02](https://polyhaven.com/a/painted_wooden_chair_02) | Kirill Sannikov |
| `painted_wooden_chair_01` | [Painted Wooden Chair 01](https://polyhaven.com/a/painted_wooden_chair_01) | Kuutti Siitonen |
| `painted_wooden_cabinet` | [Painted Wooden Cabinet](https://polyhaven.com/a/painted_wooden_cabinet) | Kirill Sannikov |
| `painted_wooden_shelves` | [Painted Wooden Shelves](https://polyhaven.com/a/painted_wooden_shelves) | Kirill Sannikov |
| `Shelf_01` | [Shelf 01](https://polyhaven.com/a/Shelf_01) | Gabriel Radić |
| `small_wooden_table_01` | [Small Wooden Table 01](https://polyhaven.com/a/small_wooden_table_01) | Ulan Cabanilla |
| `painted_wooden_nightstand` | [Painted Wooden Nightstand](https://polyhaven.com/a/painted_wooden_nightstand) | Kirill Sannikov |
| `Rockingchair_01` | [Rockingchair 01](https://polyhaven.com/a/Rockingchair_01) | Jorge Camacho |
| `side_table_01` | [Side Table 01](https://polyhaven.com/a/side_table_01) | James Ray Cock |

Licences: Poly Haven — <https://polyhaven.com/license> (CC0); ambientCG — <https://docs.ambientcg.com/license/> (CC0).
