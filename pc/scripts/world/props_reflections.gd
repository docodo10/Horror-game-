## Reflections (world module): what makes metal, glass and the mirror read right under Godot lighting.
##  * Box-projected interior ReflectionProbes (basement room, laundry nook, stairwell + landing, upper hallway), captured
##    once with the level lit; their intensity follows the mains (a lit-room reflection must not shine in the dark).
##    refresh() re-captures them (game start, power back).
##  * The ornate mirror (web ExtraProps `_buildMirror` + Reflector): on high / ultra a live PLANAR reflection — a
##    SubViewport camera mirrored about the glass with an off-axis frustum fitted to the glass (near plane ON the glass,
##    full resolution where it matters, 512 / 1024 px tall), only while the player stands in front within ~5 m and the
##    glass is on screen; aged silvering (exported tarnish + haze maps: soft, warm, desilvered edges). Low / medium (or
##    far / behind): the exported silvered-glass material reflecting the room probe.
## Public: probes (Array[ReflectionProbe]), mirror_active (bool), set_power(on), set_quality(q), refresh(),
##   MIRROR_LAYER (render layer of the glass, hidden from the mirror / probes)
extends Node3D

const LevelLoader := preload("res://scripts/world/level_loader.gd")
const MIRROR_LAYER := 1 << 19
const GLASS := {"minX": -0.219, "maxX": 0.219, "minY": -0.386, "maxY": 0.299, "z": 0.0088}
const ACTIVE_DIST := 5.0
const MIRROR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D reflection : filter_linear, repeat_disable;
uniform sampler2D tarnish : source_color, filter_linear_mipmap;
uniform sampler2D haze_map : filter_linear_mipmap;
uniform vec4 rect = vec4(-0.219, -0.386, 0.219, 0.299);
uniform vec3 silver = vec3(0.86, 0.83, 0.77);
uniform vec2 texel = vec2(0.003, 0.002);
uniform float exposure_fix = 1.0;
varying vec2 mpos;

void vertex() {
	mpos = VERTEX.xy;
}

void fragment() {
	vec2 size = rect.zw - rect.xy;
	vec2 uv = vec2((rect.z - mpos.x) / size.x, (rect.w - mpos.y) / size.y);
	vec2 auv = vec2((mpos.x - rect.x) / size.x, (rect.w - mpos.y) / size.y);
	vec3 tint = texture(tarnish, auv).rgb;
	float haze = clamp((texture(haze_map, auv).g - 0.06) * 2.0, 0.0, 1.0);
	vec3 c = texture(reflection, uv).rgb;
	vec2 o = texel * (1.2 + 3.5 * haze);
	vec3 b = (texture(reflection, uv + o).rgb + texture(reflection, uv - o).rgb
		+ texture(reflection, uv + vec2(o.x, -o.y)).rgb + texture(reflection, uv + vec2(-o.x, o.y)).rgb) * 0.25;
	c = mix(c, b, 0.2 + 0.65 * haze);
	c *= silver * tint;
	c += b * silver * haze * 0.07;
	ALBEDO = c * exposure_fix;
}
"""

var world: Node = null
var probes: Array[ReflectionProbe] = []
var mirror_active := false
var quality := "high"

var _power := true
var _probe_tween: Tween = null
var _glass: MeshInstance3D = null
var _mirror_root: Node3D = null
var _glass_mat: Material = null            # exported silvered glass (fallback)
var _live_mat: ShaderMaterial = null
var _vp: SubViewport = null
var _cam: Camera3D = null
var _env_src: Environment = null
var _env_check := 0.0
var _live_ok := false

func setup(p_world: Node, ctx: Dictionary) -> void:
	world = p_world
	name = "Reflections"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var R: Dictionary = Layout.ROOM
	var A: Dictionary = Layout.ALCOVE
	var S: Dictionary = Layout.STAIRS
	var H: Dictionary = Layout.UPPER_HALL
	var top: float = Layout.UPPER.floorY
	_add_probe("ProbeRoom", Vector3(R.minX, R.floorY, R.minZ), Vector3(R.maxX, R.ceilingY, R.maxZ), Vector3(0.25, 1.45, 0.4))
	_add_probe("ProbeNook", Vector3(A.minX, 0.0, A.minZ), Vector3(A.maxX, 2.75, R.minZ), Vector3(1.9, 1.4, -3.7))
	_add_probe("ProbeStairs", Vector3(S.minX, 0.0, R.minZ), Vector3(S.sideWallX, Layout.UPPER.ceilingY, S.bottomZ), Vector3(-3.0, 2.9, -1.2))
	_add_probe("ProbeHall", Vector3(H.minX, top, H.minZ), Vector3(H.maxX, Layout.UPPER.ceilingY, R.minZ), Vector3(-3.0, 4.2, -3.6))
	# mirror
	var mm: Dictionary = ctx.get("meta", {}).get("anim", {}).get("mirror", {})
	_glass = LevelLoader.find(ctx, mm.get("glass")) as MeshInstance3D
	_mirror_root = LevelLoader.find(ctx, mm.get("root"))
	if _glass != null:
		_glass.layers = MIRROR_LAYER
		_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glass_mat = _glass.get_active_material(0)
	set_quality(String(Settings.get_value("quality", "high")))
	RenderingServer.frame_pre_draw.connect(_pre_draw)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_pre_draw): RenderingServer.frame_pre_draw.disconnect(_pre_draw)

func _add_probe(n: String, mn: Vector3, mx: Vector3, capture: Vector3) -> void:
	var p := ReflectionProbe.new()
	p.name = n
	var c := (mn + mx) * 0.5
	p.position = c
	p.size = (mx - mn) + Vector3(0.1, 0.1, 0.1)
	p.origin_offset = capture - c
	p.box_projection = true
	p.interior = true
	p.enable_shadows = true
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	p.cull_mask = 0xFFFFF & ~MIRROR_LAYER
	p.blend_distance = 0.4
	add_child(p)
	probes.append(p)

## Mains on / off: the probes hold a capture of the lit level -> fade them out in the dark.
func set_power(on: bool) -> void:
	_power = on
	if _probe_tween != null and _probe_tween.is_valid(): _probe_tween.kill()
	_probe_tween = create_tween().set_parallel(true)
	for p in probes:
		_probe_tween.tween_property(p, "intensity", 1.0 if on else 0.0, 1.2 if on else 0.15)
	if on: refresh(1.5)

## Re-captures every probe (after `delay` s: let the lights settle). Setting UPDATE_ONCE again is enough to queue a new
## capture, and the renderer then spends one cube face per frame on one probe at a time: about 40 slightly heavier
## frames. (Holding the probes on UPDATE_ALWAYS instead renders all 6 faces of all probes every frame: 24 extra
## scene renders per frame, i.e. a hard freeze at game start and each time the power comes back.)
var _refresh_gen := 0

func refresh(delay := 0.0) -> void:
	_refresh_gen += 1
	var gen := _refresh_gen
	var waited := 0.0
	while waited < delay and is_inside_tree():
		await get_tree().process_frame
		if not get_tree().paused: waited += get_process_delta_time()
	if not is_inside_tree() or gen != _refresh_gen: return        # a newer request replaces this one
	for p in probes:
		if is_instance_valid(p): p.update_mode = ReflectionProbe.UPDATE_ONCE

func set_quality(q: String) -> void:
	quality = q
	_live_ok = (q == "high" or q == "ultra") and _glass != null and _mirror_root != null
	if _live_ok:
		_ensure_live()
		var h := 1024 if q == "ultra" else 512
		var w := int(round(h * (GLASS.maxX - GLASS.minX) / (GLASS.maxY - GLASS.minY)))
		_vp.size = Vector2i(w, h)
		_live_mat.set_shader_parameter("texel", Vector2(1.0 / w, 1.0 / h))
		# No MSAA: with the same attachment formats as the main view the mirror pass reuses the main view's pipelines
		# (a multisampled target needs its own set, compiled the first time each object shows up in the glass). The
		# aged silvering blurs the reflection anyway; FXAA takes care of the edges.
		_vp.msaa_3d = Viewport.MSAA_DISABLED
		_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_vp.positional_shadow_atlas_size = 2048 if q == "ultra" else 1024
	else:
		_set_mirror_live(false)

func _ensure_live() -> void:
	if _vp != null: return
	_vp = SubViewport.new()
	_vp.name = "MirrorView"
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_vp.use_hdr_2d = true
	_vp.positional_shadow_atlas_size = 2048
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.name = "MirrorCamera"
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.cull_mask = 0xFFFFF & ~MIRROR_LAYER
	var attrs := CameraAttributesPractical.new()     # neutral: the main camera applies exposure / DOF to the glass
	attrs.auto_exposure_enabled = false
	attrs.exposure_multiplier = 1.0
	_cam.attributes = attrs
	_vp.add_child(_cam)
	_cam.current = true
	_live_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MIRROR_SHADER
	_live_mat.shader = sh
	_live_mat.set_shader_parameter("reflection", _vp.get_texture())
	_live_mat.set_shader_parameter("rect", Vector4(GLASS.minX, GLASS.minY, GLASS.maxX, GLASS.maxY))
	if _glass_mat is BaseMaterial3D:
		var bm := _glass_mat as BaseMaterial3D
		_live_mat.set_shader_parameter("tarnish", bm.albedo_texture)
		_live_mat.set_shader_parameter("haze_map", bm.roughness_texture)
	_refresh_env(true)

## Environment of the mirror camera: the level's own, minus the costly / per-view passes (SDFGI, SSIL, SSR, volumetric
## fog, glow) and with a linear tonemap at exposure 1 (the glass is unshaded: the main pass tonemaps it once).
func _refresh_env(force := false) -> void:
	if _cam == null: return
	var src := get_world_3d().environment if get_world_3d() != null else null
	if src == null and get_world_3d() != null: src = get_world_3d().fallback_environment
	if src == _env_src and not force: return
	_env_src = src
	var e: Environment = src.duplicate() if src != null else Environment.new()
	e.sdfgi_enabled = false
	e.ssil_enabled = false
	e.ssr_enabled = false
	e.volumetric_fog_enabled = false
	e.glow_enabled = false
	e.adjustment_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.tonemap_white = 1.0
	_cam.environment = e

func _set_mirror_live(on: bool) -> void:
	mirror_active = on
	if _glass != null and _glass.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		# flat on the wall: no visible shadow, and as a shadow caster each material switch below would make every
		# light around re-render its shadow map
		_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _vp != null: _vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _glass != null:
		_glass.material_override = _live_mat if on else null

func _process(dt: float) -> void:
	if not _live_ok:
		if mirror_active: _set_mirror_live(false)
		return
	_env_check -= dt
	if _env_check <= 0.0:
		_env_check = 1.0
		_refresh_env()
	var cam := get_viewport().get_camera_3d()
	var want := false
	if cam != null and _glass.is_visible_in_tree():
		var mw := _mirror_root.global_transform
		var n := mw.basis.z.normalized()
		var c := mw * Vector3(0.0, (GLASS.minY + GLASS.maxY) * 0.5, GLASS.z)
		var eye := cam.global_position
		var front := (eye - c).dot(n)
		var dist := eye.distance_to(c)
		if front > 0.03 and dist < (ACTIVE_DIST + 0.4 if mirror_active else ACTIVE_DIST):
			for corner in [Vector3(GLASS.minX, GLASS.minY, GLASS.z), Vector3(GLASS.maxX, GLASS.minY, GLASS.z),
					Vector3(GLASS.minX, GLASS.maxY, GLASS.z), Vector3(GLASS.maxX, GLASS.maxY, GLASS.z), Vector3(0.0, -0.04, GLASS.z)]:
				if cam.is_position_in_frustum(mw * corner):
					want = true
					break
	if want != mirror_active: _set_mirror_live(want)

## Places the mirror camera right before rendering (after the player wrote its camera this frame).
func _pre_draw() -> void:
	if not mirror_active or _cam == null or not is_inside_tree(): return
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var mw := _mirror_root.global_transform
	var mx := mw.basis.x.normalized()
	var my := mw.basis.y.normalized()
	var n := mw.basis.z.normalized()
	var p0 := mw * Vector3(0.0, 0.0, GLASS.z)
	var eye := cam.global_position
	var dist := (eye - p0).dot(n)
	if dist < 0.02: return
	var veye := eye - n * (2.0 * dist)
	var basis := Basis(-mx, my, -n)                  # looks along +n (into the room), right = -mirror X
	_cam.global_transform = Transform3D(basis, veye)
	var cw := mw * Vector3((GLASS.minX + GLASS.maxX) * 0.5, (GLASS.minY + GLASS.maxY) * 0.5, GLASS.z)
	var cl := basis.transposed() * (cw - veye)
	var near := maxf(0.01, -cl.z - 0.0004)
	var k := near / maxf(-cl.z, 0.001)
	var h := (GLASS.maxY - GLASS.minY) * mw.basis.y.length() * k
	_cam.set_frustum(h, Vector2(cl.x * k, cl.y * k), near, minf(cam.far, 30.0))
