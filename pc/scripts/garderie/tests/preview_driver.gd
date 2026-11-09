## Driver of preview.gd (loaded at runtime so it can use the autoloads). Views: name -> [x, y, z, yaw°, pitch°, focus m]
## (y = eye height above the level frame; focus 0 = no depth of field).
extends Node

const TestWorld := preload("res://scripts/garderie/tests/garderie_test_world.gd")
const GL := preload("res://scripts/garderie/garderie_layout.gd")

const VIEWS := {
	"doorway": [-1.0, 1.55, 1.1, 112.0, -9.0, 0.0],
	"doorway_close": [-2.3, 1.5, 2.5, 97.0, -6.0, 0.0],
	"corridor": [-4.1, 1.58, 2.05, 90.0, -4.0, 0.0],
	"corridor_back": [-10.4, 1.58, 2.2, -88.0, -4.0, 0.0],
	"vestibule": [-11.5, 1.6, 2.4, 96.0, -6.0, 0.0],
	"cubbies": [-13.0, 1.35, 1.6, 140.0, -14.0, 1.6],
	"hall": [-17.9, 1.62, 2.7, 94.0, -11.0, 0.0],
	"hall_wide": [-18.3, 1.62, 3.9, 72.0, -9.0, 0.0],
	"wavetop": [-31.75, GL.L3 + 1.2, -4.16, -90.0, -20.0, 0.0],
	"wavebottom": [-19.0, GL.HALL + 1.0, -4.2, 92.0, 6.0, 0.0],
	"ballpit": [-23.7, GL.HALL + 1.3, 5.6, 105.0, -28.0, 2.2],
	"spiral": [-27.6, GL.HALL + 1.6, 9.8, 48.0, 6.0, 0.0],
	"structure": [-26.0, GL.L1 + 1.5, 1.2, 80.0, -5.0, 0.0],
	"mural": [-27.0, GL.HALL + 1.6, -1.0, 15.0, 8.0, 0.0],
	"party": [-23.4, GL.HALL + 1.6, 5.2, -125.0, -14.0, 0.0],
	"toddler": [-34.6, GL.HALL + 1.6, 6.8, 95.0, -18.0, 0.0],
	"dark": [-22.6, GL.HALL + 1.55, 2.4, 96.0, -6.0, 0.0],
	"poweroff": [-21.9, GL.HALL + 1.62, 5.4, 189.0, 8.0, 0.0],
	"poweroff_hall": [-18.3, 1.62, 3.9, 72.0, -9.0, 0.0],
	"pit_close": [-25.2, GL.HALL + 1.15, 5.4, 118.0, -38.0, 1.4],
	"column": [-12.85, 1.45, 3.1, 114.6, -6.0, 1.3],
	"blocks": [-35.9, GL.HALL + 1.2, 6.8, 118.0, -30.0, 1.6],
	"tube": [-18.7, 0.66, -1.2, 90.0, -2.0, 0.0],
	"vest_up": [-13.6, 1.5, 2.2, 90.0, 55.0, 0.0],
}

var _cam: Camera3D
var _env: Environment
var _attr: CameraAttributesPractical
var _g: Node3D
var _world: Node3D
var _torch: SpotLight3D
var _room_light: OmniLight3D

func run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out: String = args.get("out", "/tmp/garderie")
	var views: PackedStringArray = String(args.get("views", "hall")).split(",")
	var frames := int(args.get("frames", "40"))
	var root := Node3D.new()
	root.name = "Main"
	get_tree().root.add_child(root)
	_world = TestWorld.new()
	_world.name = "World"
	root.add_child(_world)
	_world.build_level()
	await get_tree().process_frame
	_g = Garderie.new()
	root.add_child(_g)
	await _g.build(_world)
	print("[preview] garderie built in %.0f ms, %s" % [_g.build_ms, _g.stats])
	_g.set_door_open(args.get("door", "open") == "open")
	if args.get("env", "look") == "look":
		_make_look_env(root)
	else:
		_make_env(root)
	_env.glow_enabled = args.get("glow", "1") == "1"
	_env.sdfgi_enabled = args.get("sdfgi", "1") == "1"
	_env.volumetric_fog_enabled = args.get("fog", "1") == "1"
	_env.ssr_enabled = args.get("ssr", "1") == "1"
	get_viewport().use_taa = args.get("taa", "1") == "1"
	var use_dof: bool = args.get("dof", "1") == "1"
	_cam = Camera3D.new()
	_cam.fov = float(args.get("fov", "72"))
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.04
	_cam.far = 120.0
	_cam.attributes = _attr
	root.add_child(_cam)
	_cam.current = true
	_torch = SpotLight3D.new()
	_torch.light_color = Color(1.0, 0.94, 0.86)
	_torch.light_energy = 13.37
	_torch.spot_range = 18.0
	_torch.spot_angle = 26.0
	_torch.spot_angle_attenuation = 0.4
	_torch.spot_attenuation = 2.0
	_torch.shadow_enabled = true
	_torch.position = Vector3(0.15, -0.16, 0.02)
	_torch.visible = false
	_cam.add_child(_torch)
	for vv in views:
		# "view@tweak": look-dev A/B on the same frame (nonormal | noclear | noshadow | nogi)
		var v: String = vv.get_slice("@", 0)
		var tweak: String = vv.get_slice("@", 1) if vv.contains("@") else ""
		var c: Array = []
		if v.begins_with("ride_"):
			# camera on a slide (sitting eye height), `ride_wave_0.35` = 35 % down the wave slide
			var parts := v.split("_")
			var sl: Dictionary = _g.ctx.slides.get(parts[1], {})
			if sl.is_empty():
				continue
			var cv: Curve3D = sl.curve
			var L := cv.get_baked_length()
			var d := L * (float(parts[2]) if parts.size() > 2 else 0.3)
			var p := cv.sample_baked(d) + Vector3(0, 0.74, 0)
			var ahead := cv.sample_baked(minf(d + 2.2, L)) + Vector3(0, 0.3, 0)
			var dir := (ahead - p).normalized()
			c = [p.x, p.y, p.z, rad_to_deg(atan2(-dir.x, -dir.z)), rad_to_deg(asin(dir.y)), 0.0]
		elif VIEWS.has(v):
			c = VIEWS[v]
		else:
			printerr("unknown view ", v)
			continue
		var dark := v == "dark"
		var off := dark or v.begins_with("poweroff")
		_g.set_power(not off)
		_tweak(tweak)
		_room_light.visible = not off
		_torch.visible = dark
		# the camera stands in for the player: the area's zone logic (lights per room, motes, physics) follows it
		_g.set("_zone_t", 0.0)
		_cam.position = Vector3(c[0], c[1], c[2])
		_cam.rotation = Vector3(deg_to_rad(c[4]), deg_to_rad(c[3]), 0.0)
		var focus := float(c[5]) if use_dof else 0.0
		_attr.dof_blur_far_enabled = focus > 0.0
		_attr.dof_blur_far_distance = focus * 1.6 + 1.0
		_attr.dof_blur_far_transition = focus * 2.5 + 2.0
		_attr.dof_blur_near_enabled = focus > 0.0 and focus < 3.0
		_attr.dof_blur_near_distance = maxf(0.25, focus * 0.35)
		_attr.dof_blur_near_transition = 0.3
		var t0 := Time.get_ticks_msec()
		for i in frames:
			await get_tree().process_frame
		var ms := float(Time.get_ticks_msec() - t0) / float(frames)
		var img := get_viewport().get_texture().get_image()
		if img == null:
			printerr("no image (run with a real renderer, not --headless)")
			get_tree().quit(1)
			return
		var path := "%s_%s.png" % [out, vv.replace("@", "-")]
		img.save_png(path)
		var info := "draw calls %d, objects %d, primitives %d, video mem %.0f MB" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0]
		print("[preview] saved %s  (%.0f ms/frame software)  %s" % [path, ms, info])
	get_tree().quit(0)

var _tweaked := ""

func _tweak(t: String) -> void:
	_tweaked = t
	var mats: Dictionary = _g.ctx.mats.ids()
	for id in mats:
		var m = mats[id]
		if m is ShaderMaterial and String(id).begins_with("vinyl"):
			var sm := m as ShaderMaterial
			if not sm.has_meta("orig"):
				sm.set_meta("orig", [sm.get_shader_parameter("grain_strength"), sm.get_shader_parameter("wrinkle_strength"), sm.get_shader_parameter("clearcoat_amt")])
			var o: Array = sm.get_meta("orig")
			sm.set_shader_parameter("grain_strength", 0.0 if t == "nonormal" else o[0])
			sm.set_shader_parameter("wrinkle_strength", 0.0 if t == "nonormal" else o[1])
			sm.set_shader_parameter("clearcoat_amt", 0.0 if t == "noclear" else o[2])
	# energy scales per fixture kind: "hb1.3" (high-bays), "tr0.6" (troffers), combinable with "+"
	var ks := {"highbay": 1.0, "troffer": 1.0}
	for part in t.split("+"):
		if part.begins_with("hb"):
			ks["highbay"] = float(part.substr(2))
		elif part.begins_with("tr"):
			ks["troffer"] = float(part.substr(2))
	for l in _g.ctx.lights:
		var lt: Light3D = l.light
		if not lt.has_meta("sh"):
			lt.set_meta("sh", lt.shadow_enabled)
		lt.shadow_enabled = false if t == "noshadow" else bool(lt.get_meta("sh"))
		if ks.has(l.kind):
			lt.light_energy = float(l.base) * float(ks[l.kind])
	_env.sdfgi_enabled = t != "nogi"
	_env.ssil_enabled = t != "nogi"
	_env.volumetric_fog_enabled = t != "nofog"

## The look module's "high" preset (scripts/render/look_rig.gd TUNE_DEFAULTS + look_presets.gd, worktree of the look
## agent, mirrored here so the garderie can be judged under the game's exposure without the full game): AgX at
## exposure 1, no ambient fill, SDFGI 4 cascades 0.1 m / 16 rays half-res, SSIL low half-res 0.9, SSAO medium 1.9,
## SSR 32 steps, glow levels [0, .35, .55, .3, .1] threshold 1.15 screen, volumetric fog 0.014 with the 28 m length
## the look module uses inside the garderie, TAA, soft-low shadows, 4096 atlas [1, 4, 4, 16]. The look's display-space
## post grade (sat, toe, contrast, vignette, lift) is applied by the measuring script (tools/garderie_measure.py).
func _make_look_env(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var e := _env
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.58, 0.53)
	e.ambient_light_energy = 0.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.tonemap_white = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.75
	e.ssao_intensity = 1.9
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	e.ssao_horizon = 0.06
	e.ssao_sharpness = 0.98
	e.ssao_light_affect = 0.15
	e.ssao_ao_channel_affect = 0.4
	e.ssil_enabled = true
	e.ssil_radius = 3.0
	e.ssil_intensity = 0.9
	e.ssil_sharpness = 0.98
	e.ssil_normal_rejection = 1.0
	e.ssr_enabled = true
	e.ssr_max_steps = 32
	e.ssr_fade_in = 0.12
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 0.12
	e.sdfgi_enabled = true
	e.sdfgi_cascades = 4
	e.sdfgi_min_cell_size = 0.1
	e.sdfgi_use_occlusion = false
	e.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_100_PERCENT
	e.sdfgi_read_sky_light = false
	e.sdfgi_bounce_feedback = 0.45
	e.sdfgi_energy = 1.0
	e.sdfgi_normal_bias = 2.0
	e.sdfgi_probe_bias = 2.5
	e.glow_enabled = true
	var gl := [0.0, 0.35, 0.55, 0.3, 0.1, 0.0, 0.0]
	for i in 7:
		e.set_glow_level(i, gl[i])
	e.glow_normalized = false
	e.glow_intensity = 0.26
	e.glow_strength = 1.0
	e.glow_mix = 0.05
	e.glow_bloom = 0.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.glow_hdr_threshold = 1.15
	e.glow_hdr_scale = 2.6
	e.glow_hdr_luminance_cap = 14.0
	e.fog_enabled = false
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.014
	e.volumetric_fog_albedo = Color(0.86, 0.85, 0.83)
	e.volumetric_fog_emission = Color(0, 0, 0)
	e.volumetric_fog_gi_inject = 0.35
	e.volumetric_fog_anisotropy = 0.45
	e.volumetric_fog_length = 28.0
	e.volumetric_fog_detail_spread = 2.0
	e.volumetric_fog_ambient_inject = 0.0
	e.volumetric_fog_sky_affect = 0.0
	e.volumetric_fog_temporal_reprojection_enabled = true
	e.volumetric_fog_temporal_reprojection_amount = 0.85
	e.adjustment_enabled = false
	we.environment = e
	_attr = CameraAttributesPractical.new()
	_attr.dof_blur_amount = 0.018
	_attr.auto_exposure_enabled = false
	_attr.exposure_multiplier = 1.0
	we.camera_attributes = _attr
	root.add_child(we)
	_room_light = OmniLight3D.new()
	_room_light.position = Vector3(0.25, 1.92, 0.35)
	_room_light.light_color = Color(1.0, 0.72, 0.4)
	_room_light.light_energy = 2.2
	_room_light.omni_range = 9.0
	_room_light.shadow_enabled = true
	root.add_child(_room_light)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.use_taa = true
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 4096
	vp.positional_shadow_atlas_16_bits = true
	vp.set_positional_shadow_atlas_quadrant_subdiv(0, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1)
	vp.set_positional_shadow_atlas_quadrant_subdiv(1, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4)
	vp.set_positional_shadow_atlas_quadrant_subdiv(2, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4)
	vp.set_positional_shadow_atlas_quadrant_subdiv(3, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, false, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.gi_set_use_half_resolution(true)
	RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_16)
	RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES)
	RenderingServer.environment_set_sdfgi_frames_to_update_light(RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES)
	RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	RenderingServer.screen_space_roughness_limiter_set_active(true, 0.25, 0.18)
	RenderingServer.light_projectors_set_filter(RenderingServer.LIGHT_PROJECTOR_FILTER_LINEAR_MIPMAPS_ANISOTROPIC)
	RenderingServer.decals_set_filter(RenderingServer.DECAL_FILTER_LINEAR_MIPMAPS_ANISOTROPIC)

func _make_env(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.52, 0.56)
	_env.ambient_light_energy = 0.06
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.tonemap_exposure = 1.0
	_env.sdfgi_enabled = true
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.15
	_env.sdfgi_energy = 1.0
	_env.sdfgi_bounce_feedback = 0.5
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 1.6
	_env.ssil_enabled = true
	_env.ssil_intensity = 0.8
	_env.ssr_enabled = true
	_env.ssr_max_steps = 56
	_env.ssr_fade_in = 0.1
	_env.ssr_fade_out = 2.0
	_env.ssr_depth_tolerance = 0.2
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.set_glow_level(1, 0.0)
	_env.set_glow_level(2, 0.6)
	_env.set_glow_level(3, 1.0)
	_env.set_glow_level(4, 0.8)
	_env.set_glow_level(5, 0.4)
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.004
	_env.volumetric_fog_albedo = Color(0.85, 0.85, 0.85)
	_env.volumetric_fog_length = 48.0
	_env.volumetric_fog_gi_inject = 0.6
	_env.volumetric_fog_anisotropy = 0.35
	_env.volumetric_fog_temporal_reprojection_enabled = true
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.04
	we.environment = _env
	_attr = CameraAttributesPractical.new()
	_attr.dof_blur_amount = 0.018
	we.camera_attributes = _attr
	root.add_child(we)
	# stand-in for the look module's warm ceiling light in the main room (reference: web lighting/ceilingLight)
	_room_light = OmniLight3D.new()
	_room_light.position = Vector3(0.25, 1.92, 0.35)
	_room_light.light_color = Color(1.0, 0.72, 0.4)
	_room_light.light_energy = 2.2
	_room_light.omni_range = 9.0
	_room_light.shadow_enabled = true
	root.add_child(_room_light)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.use_taa = true
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
