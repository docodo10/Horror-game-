## Exporter visual check (needs a display: xvfb + Vulkan). Assembles level.glb + the model instances from
## level_meta.json (meta_util.gd), adds rough stand-in lights from the meta (NOT the look module's lighting) and saves
## screenshots.
##   xvfb-run -a -s "-screen 0 960x540x24" godot --path pc --rendering-driver vulkan --resolution 960x540 \
##     -s res://assets/generated/_preview.gd -- --out=/abs/prefix --views=spawn,stairs,nook [--frames=8] [--gardienne]
extends SceneTree

const MetaUtil := preload("res://assets/generated/meta_util.gd")
const VIEWS := {
	"spawn": [0.25, 1.6, 1.6, 0.0, -6.0],
	"stairs": [2.3, 1.6, 1.6, 49.0, -2.0],
	"kids": [-0.6, 1.6, -0.4, 132.0, -14.0],
	"nook": [1.35, 1.6, -2.2, 0.0, -3.0],
	"tv": [-0.55, 1.6, -1.1, 0.0, -8.0],
	"console": [2.2, 1.6, 0.15, -90.0, -18.0],
	"landing": [-3.0, 4.35, -2.1, 180.0, -25.0],
	"overview": [3.2, 2.3, 2.5, 52.0, -24.0],
	"gardienne": [0.25, 1.5, 0.2, 0.0, -4.0],
	"gardienne_head": [0.25, 1.86, -0.2, 0.0, -6.0],
	"gardienne_side": [1.25, 1.3, -0.9, 90.0, -2.0],
}

var _args := {}
var _cam: Camera3D
var _frames := 0
var _views: PackedStringArray
var _vi := 0
var _wait := 8

var _root: Node3D
var _built := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_views = String(_args.get("views", "spawn")).split(",")
	_wait = int(_args.get("frames", "8"))
	_root = Node3D.new()
	_root.name = "Preview"
	get_root().add_child(_root)

func _build(root: Node3D) -> void:
	var meta := MetaUtil.load_json("res://assets/generated/level_meta.json")
	var ctx := MetaUtil.assemble(root, meta)
	for e in ctx.errors:
		printerr("assemble: ", e)
	# stand-in lighting (the look module owns the real one)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.45)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	for l in meta.get("lights", []):
		if l.owner != "world":
			continue
		var p: Array = l.position
		if l.type == "PointLight" and String(l.name).find("ceiling") >= 0 or (l.type == "PointLight" and float(l.position[1]) > 1.8 and float(l.position[1]) < 2.5):
			var o := OmniLight3D.new()
			o.position = Vector3(p[0], p[1], p[2])
			o.light_color = Color.html(String(l.color.srgb))
			o.light_energy = 2.2
			o.omni_range = 9.0
			o.shadow_enabled = true
			root.add_child(o)
		elif l.type == "SpotLight" and l.has("target") and float(l.intensity) > 50.0:
			var s := SpotLight3D.new()
			s.position = Vector3(p[0], p[1], p[2])
			root.add_child(s)
			s.look_at(Vector3(l.target[0], l.target[1], l.target[2]))
			s.light_color = Color.html(String(l.color.srgb))
			s.light_energy = 6.0
			s.spot_range = 30.0
			s.spot_angle = rad_to_deg(float(l.angle)) * 1.4
			s.shadow_enabled = true
	if _args.has("gardienne"):
		var gs := load("res://assets/generated/gardienne.glb") as PackedScene
		if gs:
			var g := gs.instantiate() as Node3D
			g.position = Vector3(0.25, 0, -0.9)  # faces +Z (toward the 'gardienne' view camera)
			root.add_child(g)
			var aps := g.find_children("*", "AnimationPlayer", true, false)
			if aps.size() > 0:
				var ap := aps[0] as AnimationPlayer
				var anim := String(_args.get("anim", "idle"))
				if ap.has_animation(anim):
					ap.play(anim)
					ap.seek(float(_args.get("t", "0.5")), true)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.03
	root.add_child(_cam)
	_cam.current = true
	_set_view(_views[0])

func _set_view(v: String) -> void:
	var c: Array = VIEWS.get(v, VIEWS.spawn)
	_cam.position = Vector3(c[0], c[1], c[2])
	_cam.rotation = Vector3(deg_to_rad(c[4]), deg_to_rad(c[3]), 0.0)

func _process(_dt: float) -> bool:
	if not _built:
		_built = true
		_build(_root)
		return false
	_frames += 1
	if _frames < _wait:
		return false
	var img := get_root().get_texture().get_image()
	if img == null:
		printerr("_preview.gd needs a real renderer (run it under xvfb with --rendering-driver vulkan, not --headless)")
		return true
	var out := "%s_%s.png" % [_args.get("out", "/tmp/preview"), _views[_vi]]
	img.save_png(out)
	print("saved ", out)
	_vi += 1
	_frames = 0
	if _vi >= _views.size():
		return true
	_set_view(_views[_vi])
	return false
