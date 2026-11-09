## Look module — the node behind Quality (scripts/render/quality.gd). Child of the main scene, PROCESS_MODE_ALWAYS.
## Owns: the WorldEnvironment (Environment + CameraAttributesPractical: exposure + depth of field — the UI's menu camera and
## the player camera both use them, neither sets its own attributes), the per-preset viewport / RenderingServer settings,
## the autofocus (5 physics rays around the centre of the CURRENT camera, centre-weighted log average with a pull toward
## the nearest hit, eased like a camera focus pull; La Gardienne's face during the jumpscare), and the post pass
## (CanvasLayer 10 < the UI's 20, ColorRect + shaders/look_postfx.gdshader) with its effect state (fear pulse, flash,
## shake, blur, closet view). Brightness (Settings) = exposure × b and a display gamma, applied live.
extends Node

const Presets := preload("res://scripts/render/look_presets.gd")
const POST_SHADER := preload("res://shaders/look_postfx.gdshader")

# ---- look tunables (scripts/render/tests/lookdev.gd overrides them per variant: set_tune({...}); --look-tune=k:v;k:v)
const TUNE_DEFAULTS := {
	# exposure / tone (light energies carry the camera exposure: lighting.gd EXPOSURE; the tonemapper sees ~1)
	"tonemap_exposure": 1.0,
	"ambient_color": Color(0.62, 0.58, 0.53),       # sRGB: warm grey bounce stand-in (low / medium only)
	# bloom (Godot glow, first pass: smoothstep(threshold, threshold + scale, max(rgb)) after exposure)
	"glow_threshold": 1.15, "glow_scale": 2.6, "glow_intensity": 0.26, "glow_cap": 14.0, "glow_mix": 0.05,
	"glow_levels": [0.0, 0.35, 0.55, 0.3, 0.1, 0.0, 0.0],
	# volumetric fog (dust in the air: shafts under the bulb, through the window, along the torch beam)
	"fog_density": 0.014, "fog_albedo": Color(0.86, 0.85, 0.83), "fog_anisotropy": 0.45, "fog_length": 14.0,
	"fog_gi_inject": 0.35, "fog_spread": 1.6,
	# screen-space / GI
	"ssao_radius": 0.75, "ssao_intensity": 1.9, "ssao_power": 1.6, "ssao_detail": 0.6, "ssao_light_affect": 0.15,
	"ssil_radius": 3.0, "ssil_intensity": 0.9, "sdfgi_energy": 1.0, "sdfgi_bounce": 0.45, "sdfgi_probe_bias": 2.5,
	"sdfgi_normal_bias": 2.0,
	# lens / film (display space, look_postfx.gdshader)
	"distort": 0.0, "vignette": 0.24, "grain": 0.012, "sat": 0.92, "contrast": 0.1,
	"lift": Vector3(0.010, 0.0088, 0.0072), "gamma": Vector3(1.0, 0.99, 1.0), "gain": Vector3(1.02, 1.0, 0.97),
	"toe_k": 1.0, "ca_k": 1.0, "sharpen_k": 1.0,
	# depth of field (multiplier of the preset dof_amount)
	"dof_k": 1.0, "menu_dof_k": 1.7,     # the TV menu: CRT in focus at ~1 m, the room behind it softly blurred
}
# ---- depth of field: Godot's physically based bokeh (far CoC = amount*64 px * (1 - zf/z), near = amount*64 * (zf/z - 1))
const DOF_REF_HEIGHT := 1080.0     # preset dof_amount is for a 1080-pixel tall DOF buffer (scaled with the resolution)
const FOCUS_SPEED := 3.5           # 1/s, log space
const FOCUS_MIN := 0.22
const FOCUS_MAX := 30.0
const FOCUS_OFFS: Array[Vector2] = [Vector2.ZERO, Vector2(-0.03, 0.0), Vector2(0.03, 0.0), Vector2(0.0, -0.04), Vector2(0.0, 0.04)]
const FOCUS_W: Array[float] = [3.0, 1.0, 1.0, 1.0, 1.0]
const FOCUS_NEAR_K := 0.94         # near blur starts a little in front of the focus plane
const FOCUS_FAR_K := 1.06          # far blur a little behind it (in-focus slab)
const FOCUS_MASK := 1 | 2 | 8 | 16  # world, interact, entity, sight occluders

var quality := "high"
var preset: Dictionary = {}
var environment: Environment = null
var camera_attributes: CameraAttributesPractical = null
var world_environment: WorldEnvironment = null
var post_layer: CanvasLayer = null
var post_rect: ColorRect = null
var post_material: ShaderMaterial = null
var focus_distance := 3.0          # current (eased) autofocus distance, m
var focus_target := 3.0
var dof_amount := 0.0              # current eased DOF envelope 0..1
var brightness := 1.0
var tune: Dictionary = TUNE_DEFAULTS.duplicate(true)

var _fill := 1.0
var _fear_set := 0.0
var _fear := 0.0
var _beat := 0.0
var _pulse := 0.0
var _blur := 0.0
var _blur_target := 0.0
var _hidden := 0.0
var _hidden_target := 0.0
var _flash_color := Color(1, 1, 1)
var _flash_amt := 0.0
var _flash_t := 0.0
var _flash_dur := 0.0
var _shake_amt := 0.0
var _shake_t := 0.0
var _shake_dur := 0.0
var _shake_ph := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _time := 0.0
var _frame := 0
var _dof_enabled := true
var _focus_snap := true
var _rays: Array[PhysicsRayQueryParameters3D] = []
var _dbg := {}
var _dof_height := 1080.0
var _stats_printed := false
var _ca_on := true
var _exclude: Array[RID] = []
var _exclude_player: Object = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100            # after the player / entity / UI wrote their cameras
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0].begins_with("look-"): _dbg[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _dbg.has("look-tune"): tune.merge(parse_tune(String(_dbg["look-tune"])), true)
	if _dbg.has("look-upscale"): Settings.values["upscale"] = String(_dbg["look-upscale"])   # test only, never saved
	_build()
	Events.settings_changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_update_dof_height)

func _build() -> void:
	environment = Environment.new()
	camera_attributes = CameraAttributesPractical.new()
	camera_attributes.auto_exposure_enabled = false
	camera_attributes.exposure_multiplier = 1.0
	world_environment = WorldEnvironment.new()
	world_environment.name = "LookEnvironment"
	world_environment.environment = environment
	world_environment.camera_attributes = camera_attributes
	add_child(world_environment)
	post_layer = CanvasLayer.new()
	post_layer.name = "LookPost"
	post_layer.layer = 10
	add_child(post_layer)
	post_rect = ColorRect.new()
	post_rect.name = "Post"
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_material = ShaderMaterial.new()
	post_material.shader = POST_SHADER
	post_rect.material = post_material
	post_layer.add_child(post_rect)
	post_layer.visible = not _dbg.has("look-nopost")
	for i in 5:
		var q := PhysicsRayQueryParameters3D.new()
		q.collision_mask = FOCUS_MASK
		q.collide_with_areas = false
		q.collide_with_bodies = true
		_rays.append(q)
	if _dbg.has("look-fear"): _fear_set = clampf(float(_dbg["look-fear"]), 0.0, 1.0)
	if _dbg.has("look-hidden"): _hidden_target = clampf(float(_dbg["look-hidden"]), 0.0, 1.0); _hidden = _hidden_target
	if _dbg.has("look-blur"): _blur_target = clampf(float(_dbg["look-blur"]), 0.0, 1.0); _blur = _blur_target

# =================================================================== presets

func apply_preset(q: String) -> void:
	quality = Presets.valid(String(q).to_lower())
	preset = Presets.get_preset(quality)
	brightness = clampf(float(Settings.get_value("brightness", 1.0)), 0.3, 2.0)
	_apply_viewport()
	_apply_rendering_server()
	_apply_environment()
	_apply_post_static()
	_update_dof_height()
	_focus_snap = true
	# lights (shadow quality, fog energies, bounce stand-ins) and the player's torch
	var w = Game.world
	if w != null and is_instance_valid(w):
		var l = w.get(&"lighting")
		if l != null and is_instance_valid(l) and l.has_method("apply_quality"): l.call("apply_quality", quality)
	if _dbg.has("look-stats") and not _stats_printed:
		_stats_printed = true
		var vp := get_viewport()
		print("[look] preset=%s scale_mode=%d scale=%.2f taa=%s msaa=%d ssaa=%d atlas=%d sdfgi=%s vfog=%s dof=%s" % [quality,
			vp.scaling_3d_mode, vp.scaling_3d_scale, str(vp.use_taa), vp.msaa_3d, vp.screen_space_aa,
			vp.positional_shadow_atlas_size, str(environment.sdfgi_enabled), str(environment.volumetric_fog_enabled),
			str(preset.get("dof", false))])

func _apply_viewport() -> void:
	var p := preset
	var vp := get_viewport()
	if vp == null: return
	vp.msaa_3d = p.msaa
	vp.screen_space_aa = p.ssaa
	# Settings "upscale": off | fsr2_quality | fsr2_balanced | fsr2_performance (FSR 2.2: temporal upscaling with its own
	# anti-aliasing, so TAA and screen-space AA are switched off; it also feeds the DOF jitter). With "off", Settings
	# "render_scale" (0.5..1.0) below 1 uses FSR 1 (spatial) — handy on low / medium.
	var up := String(Settings.get_value("upscale", "off"))
	var fsr2 := Presets.UPSCALE.has(up) and up != "off"
	var scale := clampf(float(Settings.get_value("render_scale", 1.0)), 0.5, 1.0)
	if fsr2:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = Presets.upscale_scale(up)
		vp.use_taa = false
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif scale < 0.999:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = scale
		vp.use_taa = bool(p.taa)
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.use_taa = bool(p.taa)
	vp.fsr_sharpness = 0.35
	vp.use_debanding = true
	vp.anisotropic_filtering_level = int(p.aniso)
	vp.mesh_lod_threshold = float(p.lod)
	vp.positional_shadow_atlas_size = int(p.atlas)
	vp.positional_shadow_atlas_16_bits = true
	var quads: Array = p.quads
	for i in 4:
		vp.set_positional_shadow_atlas_quadrant_subdiv(i, _subdiv(int(quads[i])))

static func _subdiv(n: int) -> Viewport.PositionalShadowAtlasQuadrantSubdiv:
	match n:
		1: return Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1
		4: return Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
		16: return Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
		64: return Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64
	return Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4

func _apply_rendering_server() -> void:
	var p := preset
	RenderingServer.positional_soft_shadow_filter_set_quality(p.soft)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.soft)
	RenderingServer.environment_set_ssao_quality(p.ssao_q, bool(p.ssao_half), 0.5, 2, 50.0, 300.0)
	if p.has("ssil_q"): RenderingServer.environment_set_ssil_quality(p.ssil_q, bool(p.get("ssil_half", false)), 0.5, 2, 50.0, 300.0)
	RenderingServer.gi_set_use_half_resolution(bool(p.get("gi_half", true)))
	if p.has("ssr_rough"): RenderingServer.environment_set_ssr_roughness_quality(p.ssr_rough)
	if p.has("sdfgi_rays"):
		RenderingServer.environment_set_sdfgi_ray_count(p.sdfgi_rays)
		RenderingServer.environment_set_sdfgi_frames_to_converge(p.sdfgi_converge)
		RenderingServer.environment_set_sdfgi_frames_to_update_light(p.sdfgi_update)
	if bool(p.vfog):
		RenderingServer.environment_set_volumetric_fog_volume_size(int(p.vfog_size), int(p.vfog_depth))
		RenderingServer.environment_set_volumetric_fog_filter_active(true)
	RenderingServer.environment_glow_set_use_bicubic_upscale(bool(p.glow_bicubic))
	var jitter := get_viewport().use_taa or get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2
	RenderingServer.camera_attributes_set_dof_blur_quality(p.dof_q, jitter)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.sub_surface_scattering_set_quality(p.sss)
	RenderingServer.screen_space_roughness_limiter_set_active(true, 0.25, 0.18)
	RenderingServer.light_projectors_set_filter(RenderingServer.LIGHT_PROJECTOR_FILTER_LINEAR_MIPMAPS_ANISOTROPIC)
	RenderingServer.decals_set_filter(RenderingServer.DECAL_FILTER_LINEAR_MIPMAPS_ANISOTROPIC)

func _apply_environment() -> void:
	var p := preset
	var e := environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = tune.ambient_color
	e.ambient_light_energy = float(p.ambient) * _fill
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED   # interior probes (world) + SSR
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = float(tune.tonemap_exposure) * brightness
	e.tonemap_white = 1.0
	# ---- SSAO: contact shadows under / behind furniture like the photos
	e.ssao_enabled = bool(p.ssao)
	e.ssao_radius = float(tune.ssao_radius)
	e.ssao_intensity = float(tune.ssao_intensity)
	e.ssao_power = float(tune.ssao_power)
	e.ssao_detail = float(tune.ssao_detail)
	e.ssao_horizon = 0.06
	e.ssao_sharpness = 0.98
	e.ssao_light_affect = float(tune.ssao_light_affect)
	e.ssao_ao_channel_affect = 0.4
	# ---- SSIL: screen-space one-bounce (torch, flicker: what SDFGI updates late)
	e.ssil_enabled = bool(p.ssil)
	e.ssil_radius = float(tune.ssil_radius)
	e.ssil_intensity = float(tune.ssil_intensity)
	e.ssil_sharpness = 0.98
	e.ssil_normal_rejection = 1.0
	# ---- SSR: crisp glossy reflections on varnish / plastic / glass (+ world's box-projected probes)
	e.ssr_enabled = bool(p.ssr)
	e.ssr_max_steps = int(p.get("ssr_steps", 64))
	e.ssr_fade_in = 0.12
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 0.12
	# ---- SDFGI: real-time bounce for the small closed basement (fine cells, full Y resolution, no sky)
	e.sdfgi_enabled = bool(p.sdfgi)
	if bool(p.sdfgi):
		e.sdfgi_cascades = int(p.sdfgi_cascades)
		e.sdfgi_min_cell_size = float(p.sdfgi_cell)
		e.sdfgi_use_occlusion = bool(p.sdfgi_occlusion)
		e.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_100_PERCENT
		e.sdfgi_read_sky_light = false
		e.sdfgi_bounce_feedback = float(tune.sdfgi_bounce)
		e.sdfgi_energy = float(tune.sdfgi_energy)
		e.sdfgi_normal_bias = float(tune.sdfgi_normal_bias)
		e.sdfgi_probe_bias = float(tune.sdfgi_probe_bias)
	# ---- glow: soft photographic halos on real highlights only (bulb bowl, tube, TV glass, torch hot spot)
	e.glow_enabled = bool(p.glow)
	var gl: Array = tune.glow_levels
	for i in 7: e.set_glow_level(i, float(gl[i]))
	e.glow_normalized = false
	e.glow_intensity = float(tune.glow_intensity)
	e.glow_strength = 1.0
	e.glow_mix = float(tune.glow_mix)
	e.glow_bloom = 0.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.glow_hdr_threshold = float(tune.glow_threshold)
	e.glow_hdr_scale = float(tune.glow_scale)
	e.glow_hdr_luminance_cap = float(tune.glow_cap)
	# ---- volumetric fog: dust (light shafts), lights opt in with light_volumetric_fog_energy (lighting.gd)
	e.fog_enabled = false
	e.volumetric_fog_enabled = bool(p.vfog)
	e.volumetric_fog_density = float(tune.fog_density)
	e.volumetric_fog_albedo = tune.fog_albedo
	e.volumetric_fog_emission = Color(0, 0, 0)
	e.volumetric_fog_emission_energy = 0.0
	e.volumetric_fog_gi_inject = float(tune.fog_gi_inject)
	e.volumetric_fog_anisotropy = float(tune.fog_anisotropy)
	e.volumetric_fog_length = float(tune.fog_length)
	e.volumetric_fog_detail_spread = float(tune.fog_spread)
	e.volumetric_fog_ambient_inject = 0.0
	e.volumetric_fog_sky_affect = 0.0
	e.volumetric_fog_temporal_reprojection_enabled = true
	e.volumetric_fog_temporal_reprojection_amount = 0.85
	e.adjustment_enabled = false
	if _dbg.has("look-nogi"):
		e.sdfgi_enabled = false
		e.ssil_enabled = false
	if _dbg.has("look-nofog"): e.volumetric_fog_enabled = false
	if _dbg.has("look-noglow"): e.glow_enabled = false

func _apply_post_static() -> void:
	var p := preset
	var m := post_material
	m.set_shader_parameter("distort", float(tune.distort))
	m.set_shader_parameter("sharpen", float(p.sharpen) * float(tune.sharpen_k))
	m.set_shader_parameter("vignette", float(tune.vignette))
	m.set_shader_parameter("grain", float(tune.grain) * (1.0 if _setting_on("film_grain") else 0.0))
	m.set_shader_parameter("grain_smooth", 1.0 if bool(p.grain_smooth) else 0.0)
	m.set_shader_parameter("edge_soft", float(p.edge_soft))
	m.set_shader_parameter("blur_taps", int(p.blur_taps))
	m.set_shader_parameter("lift", tune.lift)
	m.set_shader_parameter("gamma_v", tune.gamma)
	m.set_shader_parameter("gain", tune.gain)
	m.set_shader_parameter("sat", float(tune.sat))
	m.set_shader_parameter("contrast", float(tune.contrast))
	m.set_shader_parameter("toe", float(p.toe) * float(tune.toe_k))
	_ca_on = _setting_on("chromatic_aberration")
	_apply_brightness()

## Player toggles (Settings, default on): "depth_of_field", "film_grain", "chromatic_aberration".
func _setting_on(key: String) -> bool:
	return Settings.get_value(key, true) != false

func _apply_brightness() -> void:
	brightness = clampf(float(Settings.get_value("brightness", 1.0)), 0.3, 2.0)
	if environment != null: environment.tonemap_exposure = float(tune.tonemap_exposure) * brightness
	# display gamma: > 1 lifts the darks more than the highlights, < 1 crushes slightly (web PostFX.setBrightness)
	if post_material != null: post_material.set_shader_parameter("bright_gamma", 1.0 / (1.0 + (brightness - 1.0) * 0.35))

func _update_dof_height() -> void:
	var vp := get_viewport()
	if vp == null: return
	var h := float(vp.get_visible_rect().size.y)
	if vp is Window: h = float((vp as Window).size.y)
	if vp.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2: h *= vp.scaling_3d_scale
	_dof_height = maxf(h, 120.0)

func _on_settings_changed(key: String, value: Variant) -> void:
	match key:
		"quality": apply_preset(String(value))
		"brightness": _apply_brightness()
		"film_grain", "chromatic_aberration": _apply_post_static()
		"render_scale", "upscale":
			_apply_viewport()
			_apply_rendering_server()
			_update_dof_height()

# =================================================================== look-dev tunables

## Merges look tunables (TUNE_DEFAULTS keys) and re-applies the environment + post (look-dev; not needed in game).
func set_tune(d: Dictionary) -> void:
	tune.merge(d, true)
	if preset.is_empty(): return
	_apply_environment()
	_apply_post_static()

## "k:v;k:v" -> Dictionary. Values: float, "a/b/c" (Vector3), "a/b/c/d" (Color), "x|y|..." (Array of floats).
static func parse_tune(text: String) -> Dictionary:
	var out := {}
	for pair in text.split(";", false):
		var kv := pair.split(":", true, 1)
		if kv.size() < 2: continue
		var v := kv[1].strip_edges()
		if v.contains("|"):
			var arr := []
			for x in v.split("|"): arr.append(float(x))
			out[kv[0].strip_edges()] = arr
		elif v.contains("/"):
			var f := v.split("/")
			out[kv[0].strip_edges()] = Vector3(float(f[0]), float(f[1]), float(f[2])) if f.size() == 3 else Color(float(f[0]), float(f[1]), float(f[2]), float(f[3]) if f.size() > 3 else 1.0)
		else:
			out[kv[0].strip_edges()] = float(v)
	return out

# =================================================================== effect API (Quality statics)

func set_fill(v: float) -> void:
	_fill = maxf(0.0, v)
	if environment != null and not preset.is_empty(): environment.ambient_light_energy = float(preset.ambient) * _fill

func set_fear(v: float) -> void:
	_fear_set = clampf(v, 0.0, 1.0)

func set_blur(v: float) -> void:
	_blur_target = clampf(v, 0.0, 1.0)

func set_hidden_view(v: float) -> void:
	_hidden_target = clampf(v, 0.0, 1.0)

func snap_focus() -> void:
	_focus_snap = true

func set_dof_enabled(on: bool) -> void:
	_dof_enabled = on

func flash(color: Variant, amount: float, dur: float) -> void:
	var a := clampf(amount, 0.0, 1.0)
	var cur := 0.0
	if _flash_dur > 0.0: cur = _flash_amt * pow(1.0 - minf(1.0, _flash_t / _flash_dur), 2.0)
	if a < cur: return    # a stronger flash is still running
	var c := Color(1, 1, 1)
	if color is Color: c = color
	elif color is int: c = Color.hex((int(color) << 8) | 0xff)
	elif color is String: c = Color.from_string(String(color), Color(1, 1, 1))
	_flash_color = c
	_flash_amt = a
	_flash_t = 0.0
	_flash_dur = maxf(0.02, dur)
	var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	post_material.set_shader_parameter("flash_mode", 1.0 if lum > 0.12 else 0.0)

func shake(amount: float, dur: float) -> void:
	var a := maxf(0.0, amount)
	var cur := 0.0
	if _shake_dur > 0.0: cur = _shake_amt * pow(1.0 - minf(1.0, _shake_t / _shake_dur), 2.0)
	if a < cur: return
	_shake_amt = a
	_shake_t = 0.0
	_shake_dur = maxf(0.05, dur)
	for i in 6: _shake_ph[i] = randf() * TAU

# =================================================================== frame

func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	_time += dt
	_frame = (_frame + 1) % 65536
	_update_effects(dt)
	_update_focus(dt)

func _update_effects(dt: float) -> void:
	var m := post_material
	# fear: Game.fear (smoothed entity fear) or an explicit Quality.set_fear(), the stronger wins
	var gf := 0.0
	var gfv = Game.get(&"fear")
	if gfv != null: gf = float(gfv)
	_fear = clampf(maxf(_fear_set, gf), 0.0, 1.0)
	_blur += (_blur_target - _blur) * minf(1.0, dt * 10.0)
	if absf(_blur - _blur_target) < 1e-3: _blur = _blur_target
	_hidden += (_hidden_target - _hidden) * minf(1.0, dt * 4.0)
	if absf(_hidden - _hidden_target) < 1e-3: _hidden = _hidden_target
	# heartbeat pulse: "lub-dub", 54 bpm calm -> ~130 bpm terrified, visible only when fear is high-ish
	var f := _fear
	_beat = fmod(_beat + dt * (0.9 + 1.25 * f), 1.0)
	var p := _beat
	var lub := exp(-pow((p - 0.06) / 0.05, 2.0))
	var dub := 0.6 * exp(-pow((p - 0.3) / 0.06, 2.0))
	_pulse = (lub + dub) * smoothstep(0.25, 0.8, f)
	# flash
	var fa := 0.0
	if _flash_dur > 0.0:
		_flash_t += dt
		var k := minf(1.0, _flash_t / _flash_dur)
		fa = _flash_amt * (1.0 - k) * (1.0 - k)
		if k >= 1.0:
			_flash_dur = 0.0
			fa = 0.0
	m.set_shader_parameter("flash", Vector4(_flash_color.r, _flash_color.g, _flash_color.b, fa))
	# shake (smooth multi-sine noise, decaying envelope)
	var sx := 0.0
	var sy := 0.0
	var sr := 0.0
	var amp := 0.0
	if _shake_dur > 0.0:
		_shake_t += dt
		var k2 := minf(1.0, _shake_t / _shake_dur)
		var env := _shake_amt * (1.0 - k2) * (1.0 - k2)
		if k2 >= 1.0: _shake_dur = 0.0
		var t := _time
		var ph := _shake_ph
		amp = 0.011 * env
		sx = amp * (0.62 * sin(t * 37.1 + ph[0]) + 0.38 * sin(t * 17.3 + ph[1]))
		sy = amp * (0.62 * sin(t * 31.7 + ph[2]) + 0.38 * sin(t * 13.9 + ph[3]))
		sr = 0.014 * env * (0.6 * sin(t * 23.3 + ph[4]) + 0.4 * sin(t * 9.7 + ph[5]))
	m.set_shader_parameter("shake", Vector3(sx, sy, sr))
	var distort := float(tune.distort) + _pulse * 0.02 * f
	m.set_shader_parameter("distort", distort)
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(1.0, vs.y)
	# zoom so the distorted / shaken image always covers the screen (no clamped borders)
	m.set_shader_parameter("zoom", 1.0 / ((1.0 + distort) * (1.0 + 2.2 * amp + 1.2 * absf(sr) * maxf(1.0, aspect))))
	var ca_on := 1.0 if _ca_on else 0.25   # off = only the fear response keeps a trace of it
	m.set_shader_parameter("ca", float(preset.get("ca", 0.003)) * float(tune.ca_k) * ca_on * (1.0 + 2.5 * f + 0.8 * _pulse))
	m.set_shader_parameter("fear", f)
	m.set_shader_parameter("pulse", _pulse)
	m.set_shader_parameter("blur", _blur)
	m.set_shader_parameter("hidden", _hidden)
	m.set_shader_parameter("slat_phase", 0.08 * sin(_time * 1.6))
	m.set_shader_parameter("frame", float(_frame))

## Autofocus: rays around the screen centre of the current camera -> eased focus distance -> physically based DOF.
func _update_focus(dt: float) -> void:
	var want := bool(preset.get("dof", false)) and _dof_enabled and _setting_on("depth_of_field") and not _dbg.has("look-nodof")
	var target_env := 1.0 if want else 0.0
	var was := dof_amount
	dof_amount += (target_env - dof_amount) * minf(1.0, dt * 5.0)
	if absf(dof_amount - target_env) < 2e-3: dof_amount = target_env
	if was == 0.0 and dof_amount > 0.0: _focus_snap = true
	var ca := camera_attributes
	if dof_amount <= 0.0:
		if ca.dof_blur_far_enabled or ca.dof_blur_near_enabled:
			ca.dof_blur_far_enabled = false
			ca.dof_blur_near_enabled = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree(): return
	var z := -1.0
	if _focus_snap or (_frame & 1) == 0: z = _measure_focus(cam)
	if _dbg.has("look-focus"): z = clampf(float(_dbg["look-focus"]), FOCUS_MIN, FOCUS_MAX)
	if z > 0.0: focus_target = z
	if _focus_snap:
		focus_distance = focus_target
		_focus_snap = false
	else:
		var k := 1.0 - exp(-FOCUS_SPEED * dt)
		focus_distance = exp(lerpf(log(focus_distance), log(focus_target), k))
	var zf := clampf(focus_distance, FOCUS_MIN, FOCUS_MAX)
	ca.dof_blur_far_enabled = true
	ca.dof_blur_near_enabled = true
	ca.dof_blur_far_distance = zf * FOCUS_FAR_K
	ca.dof_blur_far_transition = -1.0         # physically based
	ca.dof_blur_near_distance = zf * FOCUS_NEAR_K
	ca.dof_blur_near_transition = -1.0
	var gs := String(Game.state)
	var k_menu := float(tune.menu_dof_k) if (gs == "menu" or gs == "loading") else 1.0
	ca.dof_blur_amount = clampf(float(preset.get("dof_amount", 0.07)) * float(tune.dof_k) * k_menu * (_dof_height / DOF_REF_HEIGHT) * dof_amount, 0.0, 1.0)

## Focus distance (camera depth, m) or -1 when nothing was hit. Five rays: centre + 4 at ±3 % / ±4 % of the screen;
## centre-weighted log average with an extra pull toward the nearest hit (web autofocus). Jumpscare: her face.
func _measure_focus(cam: Camera3D) -> float:
	var ent = Game.entity
	if ent != null and is_instance_valid(ent) and String(ent.get(&"state")) == "jumpscare" and ent.has_method("face_position"):
		var fp: Vector3 = ent.call("face_position")
		return maxf(FOCUS_MIN, (fp - cam.global_position).dot(-cam.global_basis.z))
	var space := cam.get_world_3d().direct_space_state if cam.get_world_3d() != null else null
	if space == null: return -1.0
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	var vs := get_viewport().get_visible_rect().size
	var c := vs * 0.5
	# hidden in the closet: look through the louvers (ignore what is right in front of the eye)
	var start := 0.05 + 0.75 * _hidden
	var lsum := 0.0
	var wsum := 0.0
	var zn := INF
	var pl = Game.player
	if pl is CollisionObject3D and is_instance_valid(pl) and _exclude_player != pl:
		_exclude_player = pl
		_exclude.clear()
		_exclude.append((pl as CollisionObject3D).get_rid())
		for rq in _rays: rq.exclude = _exclude
	for i in 5:
		var dir: Vector3 = fwd if i == 0 else cam.project_ray_normal(c + FOCUS_OFFS[i] * vs)
		var q := _rays[i]
		q.from = origin + dir * start
		q.to = origin + dir * FOCUS_MAX
		var hit := space.intersect_ray(q)
		var z := FOCUS_MAX
		if not hit.is_empty():
			z = clampf(((hit.position as Vector3) - origin).dot(fwd), FOCUS_MIN, FOCUS_MAX)
		lsum += log(z) * FOCUS_W[i]
		wsum += FOCUS_W[i]
		zn = minf(zn, z)
	lsum += 2.0 * log(zn)
	wsum += 2.0
	return exp(lsum / wsum)
