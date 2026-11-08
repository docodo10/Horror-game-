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
	"hall_wide": [-17.9, 1.62, -1.6, 115.0, -10.0, 0.0],
	"wavetop": [-31.6, GL.L3 + 1.55, -4.16, -90.0, -24.0, 0.0],
	"wavebottom": [-19.0, GL.HALL + 1.0, -4.2, 92.0, 6.0, 0.0],
	"ballpit": [-23.7, GL.HALL + 1.3, 5.6, 105.0, -28.0, 2.2],
	"spiral": [-28.5, GL.HALL + 1.6, 9.6, 125.0, 2.0, 0.0],
	"structure": [-26.0, GL.L1 + 1.5, 1.2, 80.0, -5.0, 0.0],
	"mural": [-27.0, GL.HALL + 1.6, -1.0, 15.0, 8.0, 0.0],
	"party": [-23.4, GL.HALL + 1.6, 5.2, -125.0, -14.0, 0.0],
	"toddler": [-34.6, GL.HALL + 1.6, 6.8, 95.0, -18.0, 0.0],
	"dark": [-22.6, GL.HALL + 1.55, 2.4, 96.0, -6.0, 0.0],
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
	_make_env(root)
	_env.glow_enabled = args.get("glow", "1") == "1"
	_env.sdfgi_enabled = args.get("sdfgi", "1") == "1"
	_env.volumetric_fog_enabled = args.get("fog", "1") == "1"
	_env.ssr_enabled = args.get("ssr", "1") == "1"
	get_viewport().use_taa = args.get("taa", "1") == "1"
	var use_dof: bool = args.get("dof", "1") == "1"
	_cam = Camera3D.new()
	_cam.fov = float(args.get("fov", "72"))
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
	for v in views:
		if not VIEWS.has(v):
			printerr("unknown view ", v)
			continue
		var c: Array = VIEWS[v]
		var dark := v == "dark"
		_g.set_power(not dark)
		_room_light.visible = not dark
		_torch.visible = dark
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
		var path := "%s_%s.png" % [out, v]
		img.save_png(path)
		var info := "draw calls %d, objects %d, primitives %d, video mem %.0f MB" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0]
		print("[preview] saved %s  (%.0f ms/frame software)  %s" % [path, ms, info])
	get_tree().quit(0)

func _make_env(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.52, 0.56)
	_env.ambient_light_energy = 0.03
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
