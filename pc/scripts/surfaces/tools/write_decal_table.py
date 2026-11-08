"""Write pc/scripts/surfaces/decal_table.gd from the converted web DECALS rows. usage: write_decal_table.py ROWS_TXT OUT_GD"""
import sys

rows = open(sys.argv[1]).read().rstrip('\n')
head = '''## Surfaces module — Godot Decal placements (data only, preloaded by surfaces.gd).
## WEB: the web build's curated list (src/config/layout.js DECALS, main 3959e88, src/world/Details.js) that the exporter
## merges into the "decals_basement" / "decals_hall" quad meshes; on medium+ those meshes are hidden and these hi-res
## Godot Decals replace them (Layout.DECALS is used instead when the generated layout.gd carries it).
## STORY: extra storytelling stains of this module (window leak, damp corner, mould behind the laundry, muddy prints
## off the stairs, spills).
## Fields: id, tex (web texture id or our set), pos (centre on the surface), n (surface normal: the decal projects
## against it), up (texture top), size (w, h), a (opacity), tint (web only, informative), flip (mirror), depth, tier.
extends RefCounted

## web texture id -> res://assets/hires/decals/<set>/ ("crayon:<i>" -> crayon_<i>)
const TEX_MAP := {
	"decal_leak_streaks": "leak_streaks", "decal_pipe_leak": "pipe_leak", "decal_rust_drip": "rust_drip",
	"decal_grime": "grime", "decal_mold": "mold", "decal_water_ring": "water_ring", "decal_rising_damp": "rising_damp",
	"decal_dirt_patch": "dirt_patch", "decal_scuffs": "scuffs", "decal_hand_smudges": "hand_smudges",
}
## quality tier per texture set: 1 = medium and up (story-relevant stains), 2 = high / ultra (wear details)
const TIERS := {
	"leak_streaks": 1, "pipe_leak": 1, "rust_drip": 1, "mold": 1, "water_ring": 1, "rising_damp": 1, "hand_smudges": 1,
	"footprints": 1, "crayon": 1, "grime": 2, "scuffs": 2, "dirt_patch": 2,
}

const WEB := [
'''
story = '''
const STORY := [
	# a slow leak at the window well: tide rings on the ceiling corner + a run-down beside the window
	{"id": "S_ceiling_leak", "tex": "water_ring", "pos": Vector3(3.08, 2.5, 2.3), "n": Vector3(0, -1, 0), "up": Vector3(0, 0, -1), "size": Vector2(0.95, 0.9), "a": 0.9},
	{"id": "S_leak_streak", "tex": "leak_streaks", "pos": Vector3(3.24, 1.88, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.48, 1.24), "a": 0.75},
	{"id": "S_damp_corner", "tex": "rising_damp", "pos": Vector3(3.5, 0.2, 2.3), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(1.0, 0.42), "a": 0.9},
	# mould colony behind the laundry basket (nook west wall + the partition corner)
	{"id": "S_mould_laundry", "tex": "mold", "pos": Vector3(0.2, 0.42, -3.18), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.75, 0.8), "a": 0.95, "depth": 0.14},
	{"id": "S_mould_corner", "tex": "mold", "pos": Vector3(0.36, 0.3, -2.9), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.45, 0.55), "a": 0.8, "depth": 0.12, "tier": 2},
	# muddy prints coming off the stairs onto the carpet (over the web dirt patch M9)
	{"id": "S_footprints", "tex": "footprints", "pos": Vector3(-2.72, 0.0, 2.12), "n": Vector3(0, 1, 0), "up": Vector3(-0.83, 0, -0.55), "size": Vector2(0.62, 1.25), "a": 0.75, "depth": 0.1},
	# spills and tracked dirt
	{"id": "S_spill_kids", "tex": "dirt_patch", "pos": Vector3(-1.05, 0.0, 0.55), "n": Vector3(0, 1, 0), "up": Vector3(0, 0, -1), "size": Vector2(0.7, 0.6), "a": 0.8, "depth": 0.1},
	{"id": "S_dirt_doorway", "tex": "dirt_patch", "pos": Vector3(1.35, 0.0, -2.4), "n": Vector3(0, 1, 0), "up": Vector3(0, 0, -1), "size": Vector2(1.0, 0.8), "a": 0.7, "depth": 0.1},
	{"id": "S_mould_closet", "tex": "mold", "pos": Vector3(-3.5, 0.25, -2.45), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.6, 0.5), "a": 0.85, "depth": 0.1, "tier": 2},
	{"id": "S_drain_stain", "tex": "water_ring", "pos": Vector3(2.45, 0.0, -3.45), "n": Vector3(0, 1, 0), "up": Vector3(0, 0, -1), "size": Vector2(1.1, 1.0), "a": 0.6, "depth": 0.08, "tier": 2},
]
'''
open(sys.argv[2], 'w').write(head + rows + '\n]\n' + story)
print('ok')
