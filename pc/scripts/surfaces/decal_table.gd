## Surfaces module — Godot Decal placements (data only, preloaded by surfaces.gd).
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
	{"id": "N1", "tex": "decal_leak_streaks", "pos": Vector3(0.95, 2.05, -4.6), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(1.3, 0.9)},
	{"id": "N2", "tex": "decal_pipe_leak", "pos": Vector3(2.98, 2, -4.6), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.45, 0.6)},
	{"id": "N3", "tex": "decal_rust_drip", "pos": Vector3(2.66, 0.94, -4.6), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.12, 0.48)},
	{"id": "N4", "tex": "decal_grime", "pos": Vector3(2.55, 1.45, -4.6), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.9, 0.85), "tint": "#b8b0a4"},
	{"id": "N5", "tex": "decal_mold", "pos": Vector3(0.2, 2.2, -4.25), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.7, 0.6)},
	{"id": "N6", "tex": "decal_water_ring", "pos": Vector3(2.9, 2.75, -3.55), "n": Vector3(0, -1, 0), "up": Vector3(0.4226, 0, -0.9063), "size": Vector2(0.8, 0.8)},
	{"id": "N7", "tex": "decal_rising_damp", "pos": Vector3(2.65, 0.28, -2.9), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(1.6, 0.56)},
	{"id": "N8", "tex": "decal_dirt_patch", "pos": Vector3(2.1, 0, -3.8), "n": Vector3(0, 1, 0), "up": Vector3(0, 0, -1), "size": Vector2(1.1, 1), "a": 0.85, "tint": "#a08a70"},
	{"id": "N9", "tex": "decal_dirt_patch", "pos": Vector3(1.35, 0, -3.25), "n": Vector3(0, 1, 0), "up": Vector3(-1, 0, 0), "size": Vector2(0.8, 0.86), "a": 0.7, "tint": "#a08a70"},
	{"id": "N10", "tex": "decal_scuffs", "pos": Vector3(3.2, 0.2, -2.9), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.55, 0.25), "tint": "#2b2622"},
	{"id": "N11", "tex": "decal_mold", "pos": Vector3(3.5, 0.3, -3.05), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.5, 0.45), "flip": true},
	{"id": "M1", "tex": "decal_leak_streaks", "pos": Vector3(2.45, 1.35, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(1.15, 0.9), "a": 0.8},
	{"id": "M2", "tex": "decal_water_ring", "pos": Vector3(-2, 2.5, 1.62), "n": Vector3(0, -1, 0), "up": Vector3(-0.2588, 0, -0.9659), "size": Vector2(0.85, 0.85)},
	{"id": "M3", "tex": "decal_grime", "pos": Vector3(-0.55, 1.78, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.9, 0.6), "a": 0.5, "tint": "#9c958a"},
	{"id": "M4", "tex": "decal_scuffs", "pos": Vector3(-1.85, 0.22, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(1, 0.3), "tint": "#2b2622"},
	{"id": "M5", "tex": "decal_scuffs", "pos": Vector3(3.5, 0.78, -1.05), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.6, 0.25), "a": 0.6, "tint": "#2b2622"},
	{"id": "M6", "tex": "decal_hand_smudges", "pos": Vector3(-2.5, 1, -1.58), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.3, 0.4)},
	{"id": "M7", "tex": "decal_hand_smudges", "pos": Vector3(-3.5, 2.77, -0.6), "n": Vector3(1, 0, 0), "up": Vector3(0, 0.798, 0.603), "size": Vector2(1, 0.3)},
	{"id": "M8", "tex": "decal_mold", "pos": Vector3(-3.15, 0.45, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.65, 0.6)},
	{"id": "M9", "tex": "decal_dirt_patch", "pos": Vector3(-3, 0, 2.1), "n": Vector3(0, 1, 0), "up": Vector3(0, 0, -1), "size": Vector2(0.9, 0.7), "a": 0.6, "tint": "#8a7660"},
	{"id": "G1", "tex": "decal_scuffs", "pos": Vector3(0.62, 0.17, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.5, 0.22), "a": 0.85, "tint": "#2b2622"},
	{"id": "G2", "tex": "decal_scuffs", "pos": Vector3(3.5, 0.16, -1.95), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.6, 0.22), "a": 0.8, "tint": "#2b2622", "flip": true},
	{"id": "G3", "tex": "decal_scuffs", "pos": Vector3(3.5, 0.17, -0.45), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.6, 0.24), "a": 0.75, "tint": "#2b2622"},
	{"id": "G4", "tex": "decal_scuffs", "pos": Vector3(3.5, 0.15, 2.2), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.7, 0.2), "a": 0.7, "tint": "#2b2622", "flip": true},
	{"id": "G5", "tex": "decal_scuffs", "pos": Vector3(-2, 0.16, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.5, 0.22), "a": 0.8, "tint": "#2b2622"},
	{"id": "G6", "tex": "decal_scuffs", "pos": Vector3(-2.5, 0.19, -0.95), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.8, 0.25), "a": 0.8, "tint": "#2b2622"},
	{"id": "G7", "tex": "decal_scuffs", "pos": Vector3(2.35, 0.14, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.45, 0.2), "a": 0.7, "tint": "#2b2622", "flip": true},
	{"id": "G8", "tex": "decal_hand_smudges", "pos": Vector3(-3.5, 1.2, 2.08), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.34, 0.4)},
	{"id": "G9", "tex": "decal_hand_smudges", "pos": Vector3(0.77, 1.15, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.24, 0.5), "flip": true},
	{"id": "G10", "tex": "decal_hand_smudges", "pos": Vector3(1.93, 1.2, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.24, 0.5)},
	{"id": "G12", "tex": "decal_grime", "pos": Vector3(1.98, 1.52, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.3, 0.26), "a": 0.55, "tint": "#8f877c"},
	{"id": "G13", "tex": "decal_leak_streaks", "pos": Vector3(-2.7, 2.05, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.7, 0.9), "a": 0.55, "flip": true},
	{"id": "G14", "tex": "decal_grime", "pos": Vector3(3.1, 0.5, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.7, 0.6), "a": 0.45, "tint": "#8f877c"},
	{"id": "G15", "tex": "decal_hand_smudges", "pos": Vector3(-2.5, 1.35, -0.2), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.3, 0.32), "a": 0.7, "flip": true},
	{"id": "K1", "tex": "crayon:0", "pos": Vector3(-2.5, 0.62, -0.95), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.7, 0.55)},
	{"id": "K2", "tex": "crayon:1", "pos": Vector3(-2.5, 0.95, -0.1), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.42, 0.4)},
	{"id": "K3", "tex": "crayon:2", "pos": Vector3(-1.95, 0.64, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.6, 0.5)},
	{"id": "K4", "tex": "crayon:3", "pos": Vector3(-2.62, 0.55, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.44, 0.6)},
	{"id": "K5", "tex": "crayon:4", "pos": Vector3(-1.45, 0.88, 2.75), "n": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "size": Vector2(0.3, 0.25)},
	{"id": "K6", "tex": "crayon:5", "pos": Vector3(-2.5, 0.35, 0.95), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.3, 0.22)},
	{"id": "K7", "tex": "crayon:6", "pos": Vector3(-1.95, 0.48, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.34, 0.28)},
	{"id": "C1", "tex": "decal_grime", "pos": Vector3(-3.5, 1.25, -2.15), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.8, 0.8), "tint": "#8f877c"},
	{"id": "C2", "tex": "decal_mold", "pos": Vector3(-3.5, 0.3, -0.75), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.6, 0.45)},
	{"id": "C3", "tex": "decal_leak_streaks", "pos": Vector3(-3.03, 2, -2.75), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.8, 0.9)},
	{"id": "C4", "tex": "decal_hand_smudges", "pos": Vector3(-2.6, 1.05, -1.58), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.28, 0.38)},
	{"id": "C5", "tex": "decal_dirt_patch", "pos": Vector3(-3.05, 0, -1.9), "n": Vector3(0, 1, 0), "up": Vector3(0, 0, -1), "size": Vector2(0.75, 0.9), "a": 0.8, "tint": "#8a7660"},
	{"id": "H1", "tex": "decal_water_ring", "pos": Vector3(-3.03, 5.2, -3.35), "n": Vector3(0, -1, 0), "up": Vector3(0.6428, 0, -0.766), "size": Vector2(0.75, 0.75)},
	{"id": "H2", "tex": "decal_leak_streaks", "pos": Vector3(-2.45, 4.75, -3.165), "n": Vector3(-1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.5, 0.9)},
	{"id": "H3", "tex": "decal_mold", "pos": Vector3(-2.68, 4.98, -4.4), "n": Vector3(0, 0, 1), "up": Vector3(0, 1, 0), "size": Vector2(0.45, 0.44)},
	{"id": "H4", "tex": "decal_scuffs", "pos": Vector3(-3.6, 2.95, -3.2), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.9, 0.3), "tint": "#2b2622"},
	{"id": "H5", "tex": "decal_dirt_patch", "pos": Vector3(-2.6, 2.75, -3.15), "n": Vector3(0, 1, 0), "up": Vector3(0, 0, -1), "size": Vector2(0.3, 0.75), "a": 0.6, "tint": "#7a6450"},
	{"id": "H6", "tex": "decal_dirt_patch", "pos": Vector3(-2.7, 2.75, -4.05), "n": Vector3(0, 1, 0), "up": Vector3(1, 0, 0), "size": Vector2(0.5, 0.3), "a": 0.55, "tint": "#7a6450", "flip": true},
	{"id": "H7", "tex": "decal_grime", "pos": Vector3(-3.6, 3.3, -3), "n": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "size": Vector2(0.5, 0.7), "a": 0.5, "tint": "#8f877c"},
]

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
