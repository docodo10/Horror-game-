## Surfaces module — mesh roles, material recipes and the web overlay meshes that the module replaces.
## Data only (preloaded by surfaces.gd). Colours are sRGB (the shaders declare them source_color).
extends RefCounted

# ---------------------------------------------------------------------------------------------------- roles
## Role by level.glb node name. The web build names architecture meshes "arch_<material key>" (stable across exports);
## a trailing "_<n>" added by the exporter for duplicates is ignored.
const NODE_ROLES := {
	"arch_wall": "wall_room", "arch_wallStair": "wall_stair",
	"arch_nookBlock": "nook_block", "arch_nookDrywall": "nook_drywall",
	"arch_closetWall": "closet_wall", "arch_closetBlock": "closet_block",
	"arch_hallWall": "hall_wall",
	"arch_ceil": "ceil_room", "arch_ceilStair": "ceil_stair", "arch_hallCeil": "ceil_hall",
	"arch_carpet": "carpet_room", "arch_carpetStair": "carpet_stair",
	"arch_trim": "trim", "arch_trimStair": "trim_stair", "arch_hallTrim": "trim_hall",
	"closetLeaf": "door_closet", "doorSlab_2": "door_stair", "doorSlab": "door_hall",
}
## Fallback role by glTF material name, used only when a node was renamed. The exporter names a material after its
## web key or its texture set; "_<n>" suffixes of shared sets (white_stucco_2...) follow the export order, so they are
## only trusted as a fallback (the current export: 2 = room ceiling, 3 = stairwell ceiling, 4 = closet, 5 = nook).
const MATERIAL_ROLES := {
	"beige_wall_001": "wall_room", "beige_wall_001_2": "wall_stair",
	"nookBlock": "nook_block", "closetBlock": "closet_block", "hallWall": "hall_wall",
	"white_stucco_2": "ceil_room", "white_stucco_3": "ceil_stair", "white_stucco": "ceil_hall",
	"white_stucco_4": "closet_wall", "white_stucco_5": "nook_drywall",
	"carpet016": "carpet_room", "carpet016_2": "carpet_stair",
	"trim": "trim", "trimStair": "trim_stair", "hallTrim": "trim_hall", "doorPaint": "door_stair",
}
## Roles that must exist in any export of the level (a warning is printed once when one is missing).
const REQUIRED_ROLES := ["wall_room", "wall_stair", "ceil_room", "ceil_stair", "carpet_room", "carpet_stair", "trim",
	"trim_stair", "nook_block", "nook_drywall", "closet_wall", "closet_block", "hall_wall", "door_closet", "door_stair"]

## Variants picked from the ORIGINAL material's albedo texture path (the exporter copies the web's maps with their set
## name): the re-exported nook (web Details pass) uses raw cast concrete, the re-exported hall ceiling crackled plaster.
## {role: [[substring, recipe], ...]} — first match wins; "" = keep the original material; no match = recipe named
## like the role.
const VARIANTS := {
	"nook_block": [["concrete_wall_007", "nook_concrete"]],
	"nook_drywall": [["concrete_wall_007", "nook_concrete"]],
	"ceil_hall": [["white_stucco", "ceil_hall"], ["ceiling_interior", "ceil_hall"], ["", ""]],
}

# ---------------------------------------------------------------------------------------------------- web overlays
## Web meshes replaced by this module (hidden on medium / high / ultra, shown again on low or restore()):
## the merged web decal quads (now Godot Decals, see decal_table.gd), the canvas carpet-wear overlay (carpet shader
## traffic paths + stains), the lower-wall grime band (wall shader grime / kicks / specks / scratches), the old ceiling
## stain quad by the window (water-ring Decal). Matched by node name or by material name (suffix "_<n>" ignored).
const HIDE_NODES := ["decals_basement", "decals_hall", "details_carpetWear", "details_wallGrime"]
const HIDE_MATERIALS := ["details_decals", "details_carpetWear", "details_wallGrime", "decal_mat", "stain"]

# ---------------------------------------------------------------------------------------------------- recipes
## Shader kind + texture set (res://assets/hires/<set>/{albedo,normal,mask}.jpg) + parameters.
const WALL_BASE := {
	"tile_size": 2.0, "paint_color": Color(0.87, 0.80, 0.66), "tex_mean_lum": 0.375, "highpass": 0.9, "hp_lod": 6.0,
	"detail_contrast": 0.75, "vertex_color_amount": 0.85, "normal_strength": 0.5, "ao_amount": 0.5, "cavity_dirt": 0.2,
	"macro_amount": 0.1, "macro_hue": 0.3, "wave_amp": 0.006, "seam_amount": 1.0, "drip_amount": 0.5,
	"grime_color": Color(0.36, 0.31, 0.25), "floor_grime": 0.7, "floor_grime_height": 0.4, "ceil_grime": 0.3,
	"corner_grime": 0.5, "corner_radius": 0.3, "scuff_amount": 0.6, "smudge_amount": 0.4, "streak_amount": 0.25,
	"speck_amount": 0.8, "scratch_amount": 0.5,
	"streak_tint": Color(0.80, 0.70, 0.52), "rough_base": 0.8, "rough_detail": 1.0, "rough_mid": 0.945, "rough_var": 0.06,
	"rough_grime": 0.95, "rough_smudge": 0.5, "specular_level": 0.4,
}
const BLOCK_BASE := {
	"tile_size": 2.3, "tex_mean_lum": 0.216, "highpass": 0.3, "detail_contrast": 1.0, "normal_strength": 1.0,
	"ao_amount": 0.85, "cavity_dirt": 0.7, "seam_amount": 0.0, "rough_mid": 0.609, "speck_amount": 0.4,
	"scratch_amount": 0.0, "streak_tint": Color(0.72, 0.58, 0.42),
}
const RECIPES := {
	"wall_room": {"kind": "wall", "set": "wall_plaster", "params": {}},
	"wall_stair": {"kind": "wall", "set": "wall_plaster", "params": {"smudge_amount": 0.55, "floor_grime": 0.6, "seam_amount": 0.7, "normal_strength": 0.38}},
	"nook_drywall": {"kind": "wall", "set": "wall_plaster", "params": {
		"paint_color": Color(0.76, 0.74, 0.69), "floor_grime": 0.85, "floor_grime_height": 0.55, "ceil_grime": 0.45,
		"corner_grime": 0.7, "streak_amount": 0.55, "damp_amount": 0.45, "mould_amount": 0.3, "scuff_amount": 0.35,
		"seam_amount": 1.6, "drip_amount": 0.4, "vertex_color_amount": 0.9, "macro_amount": 0.1}},
	"closet_wall": {"kind": "wall", "set": "wall_plaster", "params": {
		"paint_color": Color(0.60, 0.55, 0.48), "detail_contrast": 0.8, "floor_grime": 0.7, "corner_grime": 0.7,
		"mould_amount": 0.35, "damp_amount": 0.3, "seam_amount": 0.0, "drip_amount": 0.0, "scuff_amount": 0.2,
		"rough_base": 0.9}},
	"nook_block": {"kind": "wall", "set": "block_paint", "base": "block", "params": {
		"paint_color": Color(0.68, 0.66, 0.60), "floor_grime": 0.8, "floor_grime_height": 0.55, "damp_amount": 0.9,
		"damp_height": 0.65, "efflorescence": 0.85, "mould_amount": 0.3, "streak_amount": 0.7, "scuff_amount": 0.15,
		"drip_amount": 0.3, "rough_base": 0.75, "corner_grime": 0.7, "macro_amount": 0.18}},
	"closet_block": {"kind": "wall", "set": "block_paint", "base": "block", "params": {
		"paint_color": Color(0.66, 0.63, 0.58), "floor_grime": 0.75, "damp_amount": 0.65, "efflorescence": 0.5,
		"mould_amount": 0.45, "streak_amount": 0.35, "scuff_amount": 0.1, "drip_amount": 0.0, "rough_base": 0.8,
		"corner_grime": 0.7, "macro_amount": 0.12}},
	"nook_concrete": {"kind": "wall", "set": "concrete_wall", "params": {
		"tile_size": 2.2, "paint_color": Color(0.86, 0.84, 0.80), "tex_color_mix": 1.0, "tex_mean_lum": 0.25, "highpass": 0.0,
		"normal_strength": 1.0, "ao_amount": 0.8, "cavity_dirt": 0.3, "floor_grime": 0.7, "floor_grime_height": 0.5,
		"damp_amount": 0.8, "damp_height": 0.6, "efflorescence": 0.6, "mould_amount": 0.25, "streak_amount": 0.5,
		"scuff_amount": 0.15, "seam_amount": 0.0, "drip_amount": 0.0, "speck_amount": 0.2, "scratch_amount": 0.0,
		"rough_base": 0.82, "rough_mid": 0.77, "corner_grime": 0.6, "macro_amount": 0.08}},
	"hall_wall": {"kind": "wall", "set": "wallpaper", "uv_albedo_from_original": true, "params": {
		"tile_size": 1.4, "paint_color": Color(1.0, 0.97, 0.92), "tex_mean_lum": 0.704, "highpass": 0.6,
		"detail_contrast": 1.0, "uv_albedo_mix": 1.0, "floor_grime": 0.45, "ceil_grime": 0.25, "corner_grime": 0.4,
		"smudge_amount": 0.3, "streak_amount": 0.2, "scuff_amount": 0.3, "seam_amount": 0.0, "drip_amount": 0.0,
		"speck_amount": 0.3, "scratch_amount": 0.2, "normal_strength": 0.6, "rough_base": 0.78, "rough_mid": 0.655}},
	"ceil_room": {"kind": "ceiling", "set": "ceiling_knockdown", "params": {
		"room_box": Vector4(-3.5, 3.5, -2.75, 2.75), "heat_center": Vector3(0.25, 2.5, 0.35), "heat_amount": 0.35}},
	"ceil_stair": {"kind": "ceiling", "set": "ceiling_knockdown", "params": {"room_box": Vector4(-3.5, -2.6, -2.75, 1.15)}},
	"ceil_hall": {"kind": "ceiling", "set": "ceiling_knockdown", "params": {"room_box": Vector4(-3.6, -2.45, -4.4, -2.75)}},
	"carpet_room": {"kind": "carpet", "set": "carpet", "params": {}},
	"carpet_stair": {"kind": "carpet", "set": "carpet", "params": {}},
	"trim": {"kind": "trim", "set": "trim_paint", "params": {}},
	"trim_stair": {"kind": "trim", "set": "trim_paint", "params": {"scuff_amount": 0.8, "chip_amount": 0.55}},
	"trim_hall": {"kind": "trim", "set": "trim_paint", "params": {"chip_amount": 0.35, "scuff_amount": 0.4}},
	"door_closet": {"kind": "trim", "set": "trim_paint", "params": {"chip_amount": 0.3, "scuff_amount": 0.3, "dust_amount": 0.35}},
	"door_stair": {"kind": "trim", "set": "trim_paint", "params": {"chip_amount": 0.25, "scuff_amount": 0.25, "dust_amount": 0.25}},
	"door_hall": {"kind": "trim", "set": "trim_paint", "params": {"chip_amount": 0.2, "scuff_amount": 0.2, "dust_amount": 0.2}},
}

## Carpet traffic lanes (x0, z0, x1, z1): spawn, stairs bottom, sofa, dresser / TV, nook doorway, console, closet.
const LANES := [
	Vector4(-3.0, 2.15, -1.6, 1.6), Vector4(-1.6, 1.6, 0.25, 1.5), Vector4(0.25, 1.5, 0.25, 1.95),
	Vector4(0.25, 1.5, 1.3, -0.5), Vector4(1.3, -0.5, 1.35, -2.8), Vector4(1.3, -0.5, -0.55, -1.8),
	Vector4(-1.6, 1.6, -2.05, -1.75), Vector4(1.3, -0.5, 2.4, 0.15), Vector4(0.25, 1.5, 1.7, 1.2),
	Vector4(-3.0, 2.15, -3.05, 1.65),
]

# ---------------------------------------------------------------------------------------------------- hero furniture
## glTF material name -> res://assets/hires/models/<asset>/{albedo,normal,arm|rough}.jpg: the Poly Haven 2K maps of the
## same assets (the game's model GLBs embed 1K WebP). Opaque materials only (glass / fringe keep their alpha maps).
const MODEL_MATERIALS := {
	"GothicCommode_01": "GothicCommode_01", "sofa_03": "sofa_03",
	"vintage_grandfather_clock_01": "vintage_grandfather_clock_01", "ClassicConsole_01": "ClassicConsole_01",
	"painted_wooden_chair_02": "painted_wooden_chair_02", "painted_wooden_chair_01": "painted_wooden_chair_01",
	"painted_wooden_cabinet": "painted_wooden_cabinet", "painted_wooden_shelves": "painted_wooden_shelves",
	"Shelf_01": "Shelf_01", "small_wooden_table_01": "small_wooden_table_01",
	"painted_wooden_nightstand": "painted_wooden_nightstand", "Rockingchair_01": "Rockingchair_01",
	"side_table_01": "side_table_01",
}
