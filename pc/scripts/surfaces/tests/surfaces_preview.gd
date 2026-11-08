## Surfaces module — rendered before/after preview of the REAL level (needs a display: xvfb + Vulkan; use run_preview.sh,
## which also takes the machine-wide render lock).
## Assembles level.glb + every model instance (MetaUtil.assemble), adds a neutral warm TEST light rig that resembles the
## web lighting (the look module owns the final lighting), renders the standard views, calls Surfaces.apply() and
## renders them again.
##   godot --path pc --rendering-driver vulkan --resolution 960x540 -s res://scripts/surfaces/tests/surfaces_preview.gd -- \
##     --out=/abs/prefix [--views=spawn,stairs,kids,nook,tv,console,landing] [--quality=high] [--mode=both|before|after]
##     [--frames=12] [--cams="name:x,y,z,yaw,pitch|..."] (y = feet height, eye = y + 1.6) [--hall] [--switch=low,high]
## Output: <prefix>_<view>_before.png / _after.png, plus "[surfaces] apply <quality>: N ms" lines.
extends SceneTree

const MetaUtil := preload("res://assets/generated/meta_util.gd")
const SurfacesScript := preload("res://scripts/surfaces/surfaces.gd")
const EYE := 1.6
## Same poses as DebugTools.VIEWS (autoload/debug_tools.gd: x, feet y, z, yawDeg, pitchDeg; eye = y + 1.6). Copied
## because preloading the autoload script from a -s SceneTree fails to compile (it references the Settings autoload).
const VIEWS := {
	"spawn": [0.25, 0.0, 1.6, 0.0, -3.0],
	"stairs": [2.3, 0.0, 1.6, 49.0, -2.0],
	"kids": [-0.6, 0.0, -0.4, 132.0, -14.0],
	"nook": [1.35, 0.0, -2.2, 0.0, -3.0],
	"tv": [-0.55, 0.0, -1.1, 0.0, -8.0],
	"console": [2.2, 0.0, 0.15, -90.0, -18.0],
	"landing": [-3.0, 2.75, -2.1, 180.0, -25.0],
}

var _args := {}
var _root: Node3D
var _cam: Camera3D
var _views: Array = []   # [[name, [x, y, z, yaw, pitch]], ...]
var _phases: PackedStringArray = []
var _phase := 0
var _vi := 0
var _frames := 0
var _wait := 12
var _built := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_wait = int(_args.get("frames", "12"))
	var all_views: Dictionary = VIEWS
	for v in String(_args.get("views", "spawn,stairs,kids,nook,tv,console,landing")).split(",", false):
		if all_views.has(v):
			_views.append([v, all_views[v]])
	if _args.has("cams"):
		for c in String(_args.cams).split("|", false):
			var nv := c.split(":", true, 1)
			var p := nv[1].split(",")
			_views.append([nv[0], [float(p[0]), float(p[1]), float(p[2]), float(p[3]), float(p[4])]])
	var mode := String(_args.get("mode", "both"))
	if mode == "both" or mode == "before":
		_phases.append("before")
	if mode == "both" or mode == "after":
		_phases.append("after")
	for q in String(_args.get("switch", "")).split(",", false):
		_phases.append("q_" + q)
	_root = Node3D.new()
	_root.name = "World"
	get_root().add_child(_root)

func _build() -> void:
	var meta := MetaUtil.load_json("res://assets/generated/level_meta.json")
	var t0 := Time.get_ticks_msec()
	var ctx := MetaUtil.assemble(_root, meta)
	print("[surfaces] assemble: %d ms, %d errors" % [Time.get_ticks_msec() - t0, ctx.errors.size()])
	for e in ctx.errors:
		printerr("assemble: ", e)
	if _args.has("hall"):   # show the upstairs hallway (hidden until the door opens) with a stand-in ceiling light
		var hall := _root.find_child("upperHall", true, false) as Node3D
		if hall: hall.visible = true
		var hl := OmniLight3D.new()
		hl.position = Vector3(-3.02, 4.85, -3.6)
		hl.light_color = Color(1.0, 0.78, 0.55)
		hl.light_energy = 1.4
		hl.omni_range = 5.0
		hl.shadow_enabled = true
		_root.add_child(hl)
	_add_test_rig()
	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.near = 0.03
	_root.add_child(_cam)
	_cam.current = true

## Neutral warm test rig (NOT the game's lighting): 2700 K ceiling bowl light with soft shadows (the web's light sits in
## the fan's glass bowl at y 1.92), a dim bare bulb in the nook, a weak warm fill and AgX.
func _add_test_rig() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.55, 0.47)
	e.ambient_light_energy = float(_args.get("fill", "0.16"))
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = float(_args.get("exposure", "1.0"))
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.2
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.04
	env.environment = e
	_root.add_child(env)
	var warm := Color(1.0, 0.76, 0.52)
	var ceil_l := OmniLight3D.new()
	ceil_l.name = "TestCeilingLight"
	ceil_l.position = Vector3(0.25, 1.92, 0.35)
	ceil_l.light_color = warm
	ceil_l.light_energy = float(_args.get("energy", "2.6"))
	ceil_l.omni_range = 12.0
	ceil_l.omni_attenuation = 1.2
	ceil_l.shadow_enabled = true
	ceil_l.light_size = 0.12
	ceil_l.shadow_blur = 1.5
	ceil_l.shadow_normal_bias = 1.0
	_root.add_child(ceil_l)
	var nook := OmniLight3D.new()
	nook.name = "TestNookBulb"
	nook.position = Vector3(1.8, 2.2, -3.6)
	nook.light_color = Color(1.0, 0.72, 0.45)
	nook.light_energy = 0.9
	nook.omni_range = 5.0
	nook.omni_attenuation = 1.2
	nook.shadow_enabled = true
	nook.light_size = 0.05
	_root.add_child(nook)
	var stairwell := OmniLight3D.new()   # stand-in for the light spilling up the stairwell
	stairwell.name = "TestStairwellLight"
	stairwell.position = Vector3(-3.05, 4.7, -0.4)
	stairwell.light_color = warm
	stairwell.light_energy = 0.7
	stairwell.omni_range = 6.0
	stairwell.omni_attenuation = 1.2
	stairwell.shadow_enabled = true
	_root.add_child(stairwell)

func _set_view(v: Array) -> void:
	var c: Array = v[1]
	_cam.position = Vector3(c[0], c[1] + EYE, c[2])
	_cam.rotation = Vector3(deg_to_rad(c[4]), deg_to_rad(c[3]), 0.0)

func _apply_phase(p: String) -> void:
	var q := String(_args.get("quality", "high"))
	if p == "before":
		return
	if p.begins_with("q_"):
		q = p.substr(2)
	var t0 := Time.get_ticks_usec()
	SurfacesScript.apply(_root, q)
	print("[surfaces] apply %s: %.1f ms" % [q, (Time.get_ticks_usec() - t0) / 1000.0])
	if p == "after" and _args.has("twice"):
		t0 = Time.get_ticks_usec()
		SurfacesScript.apply(_root, q)
		print("[surfaces] re-apply %s: %.1f ms" % [q, (Time.get_ticks_usec() - t0) / 1000.0])

func _process(_dt: float) -> bool:
	if not _built:
		_built = true
		_build()
		if _phases.is_empty() or _views.is_empty():
			return true
		_apply_phase(_phases[0])
		_set_view(_views[0])
		return false
	_frames += 1
	if _frames < _wait:
		return false
	var img := get_root().get_texture().get_image()
	if img == null:
		printerr("surfaces_preview needs a real renderer (xvfb + --rendering-driver vulkan)")
		return true
	var out := "%s_%s_%s.png" % [_args.get("out", "/tmp/surfaces"), _views[_vi][0], _phases[_phase]]
	img.save_png(out)
	print("[surfaces] saved ", out)
	_frames = 0
	_vi += 1
	if _vi >= _views.size():
		_vi = 0
		_phase += 1
		if _phase >= _phases.size():
			return true
		_apply_phase(_phases[_phase])
	_set_view(_views[_vi])
	return false
