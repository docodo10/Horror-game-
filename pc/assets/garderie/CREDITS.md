# Garderie assets — credits and licences

Everything in `textures/` is either CC0 (public domain) material from Poly Haven, or generated for this game by
`pc/scripts/garderie/tools/gen_textures.py` + `gen_signs.py` (original artwork, same licence as the game).

## Poly Haven (CC0 1.0, https://polyhaven.com/license) — files prefixed `ph_`
Downloaded through the Poly Haven API (2K or 1K JPEG), re-encoded at quality 86–90. AO / roughness / metalness are the
`arm` maps (R = AO, G = roughness, B = metalness).

| file prefix | asset | author | used for |
|---|---|---|---|
| `ph_painted_concrete_*_2k` | [painted_concrete](https://polyhaven.com/a/painted_concrete) | Dario Barresi, Dimitrios Savva | corridor walls (two-tone paint) |
| `ph_painted_concrete_02_*_1k` | [painted_concrete_02](https://polyhaven.com/a/painted_concrete_02) | Rob Tuytel | corridor ceiling |
| `ph_concrete_floor_painted_*_2k` | [concrete_floor_painted](https://polyhaven.com/a/concrete_floor_painted) | Rob Tuytel | corridor floor |
| `ph_concrete_block_wall_*_2k` | [concrete_block_wall](https://polyhaven.com/a/concrete_block_wall) | Charlotte Baglioni | painted block walls (vestibule, hall), mural relief |
| `ph_concrete_floor_worn_001_*_1k` | [concrete_floor_worn_001](https://polyhaven.com/a/concrete_floor_worn_001) | Dimitrios Savva, Rico Cilliers | landing, steps, bare floor under missing mats |
| `ph_leather_white_*_1k` | [leather_white](https://polyhaven.com/a/leather_white) | Rob Tuytel | vinyl grain (normal + roughness only) |
| `ph_distressed_painted_planks_*_1k` | [distressed_painted_planks](https://polyhaven.com/a/distressed_painted_planks) | Rob Tuytel | wainscot, painted wood (door, casing, counter) |
| `ph_plywood_*_1k` | [plywood](https://polyhaven.com/a/plywood) | Rob Tuytel | cubbies, boxes, threshold |
| `ph_corrugated_iron_02_*_1k` | [corrugated_iron_02](https://polyhaven.com/a/corrugated_iron_02) | Jenelle van Heerden, Sergej Majboroda | hall roof deck (normal + roughness only) |

(Authors as listed by api.polyhaven.com/info at download time, 2026-11-08; Poly Haven assets are CC0 — attribution is a courtesy.)

## Generated (original, this project)
`noise_rgba.png`, `eva_grain_n.png`, `vinyl_wrinkle_n.png`, `plastic_scratch.png`, `net.png`, `mat_edge.png`,
`ceiling_tiles.jpg`, `ceiling_tiles_n.png`, `cork.jpg`, `decal_scuffs.png`, `decal_spill.png`, `decal_footprints.png`,
`decal_crayon.png`, `decal_grime.png`, `decal_water.png` — procedural (numpy / PIL). `mat_edge.png` is a signed-distance
field of the 7-tooth dovetail edge, `net.png` a 3 mm knotted cord. `neon_text.png` — our own neon lettering
"Les Petits Soleils" (Caveat Bold, OFL, baked into a tube mask). The louver projector of the troffers is generated at
runtime (garderie_shell.gd).
`sign_garderie.jpg`, `sortie_red.png`, `sortie_green.png`, `rules.jpg`, `notice_board.jpg`, `cubby_labels.png`,
`drawings.jpg`, `mural.jpg`, `banner.png`, `signin.jpg`, `labels.jpg`, `sun_decal.png` — original artwork drawn by
`gen_signs.py` (the daycare "Les Petits Soleils", its sun mascot, kids' names, notes, mural). Nothing is copied from
any other game.

## Fonts used to bake the text (not shipped with the game)
| font | licence | source |
|---|---|---|
| Fredoka (variable) | SIL Open Font License 1.1 | Google Fonts (github.com/google/fonts, ofl/fredoka) |
| Chewy | Apache License 2.0 | Google Fonts (apache/chewy) |
| Patrick Hand | SIL OFL 1.1 | Google Fonts (ofl/patrickhand) |
| Gaegu | SIL OFL 1.1 | Google Fonts (ofl/gaegu) |
| Caveat (variable) | SIL OFL 1.1 | Google Fonts (ofl/caveat) |
| Oswald (variable) | SIL OFL 1.1 | Google Fonts (ofl/oswald) |

Re-generate everything (downloads in a scratch folder, see the scripts' headers):
`python3 -I pc/scripts/garderie/tools/gen_textures.py pc/assets/garderie/textures --fonts <fonts dir> --ph <Poly Haven JPEG dir>`
then `python3 -I pc/scripts/garderie/tools/write_imports.py pc/assets/garderie/textures` and `godot --headless --path pc --import`.

## Generated — extra rooms (dortoir, bureau, toilettes)
Original, procedural (numpy / PIL), written by `pc/scripts/garderie/tools/gen_rooms_textures.py` (fixed seeds):
`tiles_wall.jpg` + `tiles_wall_n.png` + `tiles_wall_orm.jpg` (8x8 glazed 15 cm wall tiles, one repeat = 1.2 m),
`tiles_floor.jpg` + `tiles_floor_n.png` + `tiles_floor_orm.jpg` (12x12 matte 10 cm floor tiles, one repeat = 1.2 m),
`wallpaper_nursery.jpg` + `wallpaper_nursery_n.png` (stars / moons / clouds, one repeat = 1.06 m = two 53 cm strips),
`carpet.jpg` + `carpet_n.png` (low-pile carpet, one repeat = 0.6 m), `star_cookie.png` (night-light projector cookie),
`docs_atlas.jpg` (2x2 office papers: presence sheet, nap schedule, notice to parents, phone list — fictional names and
555-01xx numbers), `drawings2.jpg` (2x2 children's crayon drawings). Normal maps are OpenGL (+Y), ORM = R AO, G roughness,
B metal. Nothing is copied from any other work.

Fonts baked into `docs_atlas.jpg` (from `pc/assets/fonts`): Special Elite (Apache License 2.0, Astigmatic) for the typed
text, Caveat (SIL OFL 1.1) for the handwriting.

Re-generate: `python3 -I pc/scripts/garderie/tools/gen_rooms_textures.py`, then `write_imports.py` and
`godot --headless --path pc --import` as above.

## Generated — l'étage (old wooden house, ground floor)
Original, procedural (numpy / scipy / PIL), written by `pc/scripts/etage/tools/gen_etage_textures.py` (fixed seeds), no
fonts, nothing copied from any other work:
`wallpaper_house.jpg` + `wallpaper_house_n.png` (dark bottle-green damask, ochre motif every 26.5 cm in a half-drop, one
repeat = 1.06 m = two 53 cm strips with seams at u = 0.25 and 0.75; grime, water runs, lifted seams, small tears),
`plaster_old.jpg` + `plaster_old_n.png` (off-white ceiling plaster, hairline cracks, water rings, flaked patches, one
repeat = 2 m), `rug_runner.jpg` (512x1024 worn hallway runner, 0.8 m wide x 1.6 m long, seamless along v only),
`night_window.png` (512x768 night sky behind a window: backlit torn clouds, bare branches; max luminance 34 %, lossless
import), `portraits_atlas.jpg` (2x2 sepia photographs: seated woman with the face scratched out, five children at a door
with worn faces, house in winter with one lit window, the same woman water-damaged with burnt eyes — generic drawn
figures, no real person), `sheet_n.png` (512 normal map of a cotton dust sheet). Normal maps are OpenGL (+Y).

Re-generate: `python3 -I pc/scripts/etage/tools/gen_etage_textures.py`, then `write_imports.py` (new files only) and
`godot --headless --path pc --import` as above.

The rooms added to l'étage (kitchen, pantry, bathroom, stairwell): original, procedural, written by
`pc/scripts/etage/tools/gen_etage2_textures.py` (fixed seeds; lettering set in the fonts the game already ships in
`pc/assets/fonts`: Gelasio, Caveat, Special Elite, all OFL): `lino_checker.jpg` (worn kitchen linoleum, 8 x 8 checks of
20 cm, one repeat = 1.6 m), `calendar_1994.jpg` (512x768 wall calendar, "NOVEMBRE 1994", a drawn landscape, days 1-11
crossed in pencil), `digits_hand.png` (5 x 2 atlas of the digits 0-9 drawn by hand, alpha; lossless), `fog_mirror.png`
(condensation on a mirror with runs of drops, alpha; lossless), `steam_puff.png` (one puff of steam, alpha; lossless),
`etage_labels.jpg` (2x2 atlas: the fuse board's card, four jar labels, the tin of fuses, a key tag and a strip of
sticking plaster). The script writes the `.import` presets of its new files itself; then
`godot --headless --path pc --import`.
