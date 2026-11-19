## Materials of l'étage: the garderie's factory (garderie_mats.gd) plus the ones of the rooms added to the chapter
## (kitchen, pantry, bathroom, stairwell). Textures: tools/gen_etage2_textures.py.
extends "res://scripts/garderie/garderie_mats.gd"

func _make(id: String) -> Material:
	match id:
		"lino":
			# kitchen linoleum, 8 checks of 20 cm per tile of texture
			return _paint("lino_checker.jpg", "", "", {
				"uv_scale": 1.0 / 1.6, "floor_y": -10.0, "grime": 0.0, "blotch": 0.25, "rough_mul": 0.42,
				"tint_low": Color(0.8, 0.8, 0.78), "tint_high": Color(0.8, 0.8, 0.78)})
		"tile_bain":
			# glazed wall tiles gone a sick green
			return _paint("tiles_wall.jpg", _opt("tiles_wall_n.png"), _opt("tiles_wall_orm.jpg"), {
				"uv_scale": 1.0 / 1.2, "floor_y": 0.0, "grime": 0.55, "grime_h": 0.5, "blotch": 0.2, "normal_strength": 0.9,
				"tint_low": Color(0.6, 0.72, 0.62), "tint_high": Color(0.66, 0.76, 0.66)})
		"tile_cuisine":
			# the same tiles, cream, behind the worktop and up to the dado of the kitchen
			return _paint("tiles_wall.jpg", _opt("tiles_wall_n.png"), _opt("tiles_wall_orm.jpg"), {
				"uv_scale": 1.0 / 1.2, "floor_y": 0.0, "grime": 0.5, "grime_h": 0.5, "blotch": 0.2, "normal_strength": 0.9,
				"tint_low": Color(0.8, 0.74, 0.58), "tint_high": Color(0.82, 0.76, 0.6)})
		"tile_bain_floor":
			return _paint("tiles_floor.jpg", _opt("tiles_floor_n.png"), _opt("tiles_floor_orm.jpg"), {
				"uv_scale": 1.0 / 1.2, "floor_y": -10.0, "grime": 0.0, "blotch": 0.3, "tint_low": Color(0.56, 0.62, 0.58), "tint_high": Color(0.56, 0.62, 0.58)})
		"stone_floor":
			# the pantry's flags
			return _paint("ph_concrete_floor_worn_001_diff_1k.jpg", "ph_concrete_floor_worn_001_nor_gl_1k.jpg", "ph_concrete_floor_worn_001_arm_1k.jpg", {
				"uv_scale": 0.7, "floor_y": -10.0, "grime": 0.0, "blotch": 0.3, "tint_low": Color(0.6, 0.56, 0.5), "tint_high": Color(0.6, 0.56, 0.5)})
		"plaster_cuisine":
			# distemper gone yellow with the years of cooking
			return _paint("plaster_old.jpg", _opt("plaster_old_n.png"), "", {
				"uv_scale": 0.5, "floor_y": 0.0, "grime": 0.35, "grime_h": 2.4, "blotch": 0.3, "rough_add": 0.85,
				"tint_low": Color(0.62, 0.55, 0.36), "tint_high": Color(0.62, 0.55, 0.36)})
		"plaster_bain":
			return _paint("plaster_old.jpg", _opt("plaster_old_n.png"), "", {
				"uv_scale": 0.5, "floor_y": 1.5, "grime": 0.5, "grime_h": 1.0, "blotch": 0.35, "rough_add": 0.8,
				"grime_color": Color(0.16, 0.2, 0.14), "tint_low": Color(0.52, 0.58, 0.5), "tint_high": Color(0.52, 0.58, 0.5)})
		"whitewash":
			return _paint("plaster_old.jpg", _opt("plaster_old_n.png"), "", {
				"uv_scale": 0.6, "floor_y": 0.0, "grime": 0.6, "grime_h": 1.2, "blotch": 0.4, "rough_add": 0.9,
				"tint_low": Color(0.5, 0.49, 0.45), "tint_high": Color(0.5, 0.49, 0.45)})
		"jar":
			# preserving jars: dark glass, what is inside gives the colour (vertex colours)
			var j := StandardMaterial3D.new()
			j.vertex_color_use_as_albedo = true
			j.vertex_color_is_srgb = true
			j.roughness = 0.08
			j.metallic_specular = 0.9
			j.clearcoat_enabled = true
			j.clearcoat = 0.6
			j.clearcoat_roughness = 0.1
			return j
		"curtain":
			# the bath curtain: waxed cotton, stiff, stained along its hem (vertex colours carry the folds)
			return _paint("", _opt("sheet_n.png"), "", {
				"uv_scale": 2.0, "floor_y": 0.2, "grime": 0.7, "grime_h": 0.7, "grime_color": Color(0.14, 0.17, 0.1), "blotch": 0.3, "rough_mul": 0.55,
				"normal_strength": 0.6, "tint_low": Color(0.5, 0.52, 0.44), "tint_high": Color(0.56, 0.57, 0.5)})
		"frost_glow":
			# frosted panes with the night behind them
			return _emit(Color(0.2, 0.25, 0.33), 0.4)
		"fridge_glow":
			return _emit(Color(1.0, 0.97, 0.8), 5.0)
		"pilot_glow":
			return _emit(Color(1.0, 0.4, 0.1), 3.0)
		"fog_mirror":
			return _alpha_tex("fog_mirror.png", Color(0.42, 0.46, 0.45, 0.0), 0)
		"digit_fog":
			# the digit a finger left in the steam: clear glass, so darker than the mist around it
			return _alpha_tex("digits_hand.png", Color(0.03, 0.04, 0.04, 0.0), 1)
		"digit_ink":
			var di := _alpha_tex("digits_hand.png", Color(0.1, 0.1, 0.24, 0.92), 1)
			di.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			return di
		"cal_page":
			# printed paper that does not burn white in the torch's beam
			var cp := _paper("calendar_1994.jpg", false)
			cp.albedo_color = Color(0.56, 0.54, 0.48)
			return cp
		"labels_page":
			var lp := _paper("etage_labels.jpg", false)
			lp.albedo_color = Color(0.6, 0.58, 0.52)
			return lp
		"red_pencil":
			var rp := StandardMaterial3D.new()
			rp.albedo_color = Color(0.5, 0.05, 0.04)
			rp.roughness = 0.9
			return rp
	return super._make(id)

## Texture with alpha laid over a surface (steam on the mirror, a digit): never in a shadow pass, drawn after the
## glass (`prio` orders the layers).
func _alpha_tex(name: String, col: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name)
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.render_priority = prio
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m
