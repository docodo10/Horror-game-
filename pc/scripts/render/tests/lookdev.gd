## Look module look-dev harness: one Godot session renders several tunable variants × camera views (saves the startup and
## shader compiles of one run per variant). Needs a renderer — run it through pc/scripts/render/tests/lookdev.sh:
##   pc/scripts/render/tests/lookdev.sh /abs/prefix "spawn,kids" "base@lowglow:glow_intensity=0.3,fog_ceil=0.06" [frames] [game args]
## Variants are separated by "@", each "name:key=value,key=value" (or just "name"). Keys are looked up in the rig's tune
## (scripts/render/look_rig.gd TUNE_DEFAULTS) then the lighting's (scripts/world/lighting.gd TUNE_DEFAULTS); values are
## floats, "a/b/c" vectors, "a/b/c/d" colours, or "x|y|z" arrays. A variant may also set "quality=low|medium|high|ultra".
## Views: DebugTools.VIEWS + the extra look-dev views below, or "x,y,z,yaw,pitch" literal cameras joined with "+".
## Game args after the frames (e.g. --power=off --flashlight --stage=code) go to DebugTools as usual (autostart implied);
## pass --lookdev-menu to shoot the TV menu instead (no autostart: the UI's menu camera).
## Output: <prefix>_<variant>_<view>.png
extends SceneTree

const EXTRA_VIEWS := {
	"fan": [0.9, 0.0, 1.9, 20.0, 30.0],          # looking up at the fan / ceiling
	"window": [0.6, 0.0, -1.6, -157.0, 5.0],      # facing the high south window, along the moon beam
	"shaft": [-1.2, 0.0, 0.9, -95.0, -12.0],      # side view across the moon beam
	"floor": [0.25, 0.0, 1.5, 15.0, -38.0],       # moon patch / bulb pool on the carpet
	"door": [-3.0, 2.75, -1.6, 0.0, 0.0],         # landing, upstairs door + strip
	"dresser": [-0.55, 0.0, -0.9, 0.0, -18.0],    # close focus (DOF), varnish reflections
	"corner": [2.6, 0.0, 2.1, -140.0, -10.0],     # far corner toward the stairs (falloff to black)
	"nook2": [1.4, 0.0, -2.6, 20.0, 4.0],         # inside the storage nook, tube light
}

## Garderie views (eye positions, scripts/garderie/tests/preview_driver.gd convention; hall floor y -1.05).
const G_VIEWS := {
	"g_corridor": [-4.1, 1.58, 2.05, 90.0, -4.0],
	"g_vestibule": [-11.5, 1.6, 2.4, 96.0, -6.0],
	"g_hall": [-17.9, 1.62, 2.7, 94.0, -11.0],
	"g_wide": [-18.3, 1.62, 3.9, 72.0, -9.0],
	"g_ballpit": [-23.7, 0.25, 5.6, 105.0, -28.0],
	"g_wave": [-19.0, -0.05, -4.2, 92.0, 6.0],
}

var _out := "/tmp/lookdev"
var _views: PackedStringArray = ["spawn"]
var _variants: Array = []
var _frames := 40
var _menu := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.get_slice("=", 1)
		elif a.begins_with("--views="): _views = a.get_slice("=", 1).split(",", false)
		elif a.begins_with("--variants="): _variants = _parse_variants(a.substr(a.find("=") + 1))
		elif a.begins_with("--frames="): _frames = maxi(2, int(a.get_slice("=", 1)))
		elif a == "--lookdev-menu": _menu = true
	if _variants.is_empty(): _variants = [{"name": "base", "tune": {}}]
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	_run.call_deferred()

func _parse_variants(text: String) -> Array:
	var out := []
	for v in text.split("@", false):
		var parts := v.split(":", true, 1)
		var tune := {}
		if parts.size() > 1:
			for kv in parts[1].split(",", false):
				var p := kv.split("=", true, 1)
				if p.size() < 2: continue
				var s := p[1].strip_edges()
				if p[0] == "quality": tune["quality"] = s
				elif s.contains("|"):
					var arr := []
					for x in s.split("|"): arr.append(float(x))
					tune[p[0]] = arr
				elif s.contains("/"):
					var f := s.split("/")
					tune[p[0]] = Vector3(float(f[0]), float(f[1]), float(f[2])) if f.size() == 3 else Color(float(f[0]), float(f[1]), float(f[2]), float(f[3]))
				else: tune[p[0]] = float(s)
		out.append({"name": parts[0], "tune": tune})
	return out

func _frames_wait(n: int) -> void:
	for i in n: await process_frame

func _run() -> void:
	var main: Node = null
	if "--lookdev-no-garderie" in OS.get_cmdline_user_args():
		main = (load("res://scripts/render/tests/lookdev_main.gd") as GDScript).new()
		main.name = "Main"
	else:
		main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var game := root.get_node("Game")
	var want := "menu" if _menu else "playing"
	var t0 := Time.get_ticks_msec()
	while String(game.get(&"state")) != want and Time.get_ticks_msec() - t0 < 180000: await process_frame
	await _frames_wait(20)
	var Q: Script = load("res://scripts/render/quality.gd")
	var rig: Node = Q.call("rig")
	var world: Node = game.get(&"world")
	var lighting: Node = world.get(&"lighting") if world else null
	var dbg := root.get_node("DebugTools")
	var views: Dictionary = (dbg.get(&"VIEWS") as Dictionary).duplicate()
	views.merge(EXTRA_VIEWS)
	var base_rig: Dictionary = (rig.get(&"tune") as Dictionary).duplicate(true) if rig else {}
	var base_light: Dictionary = (lighting.get(&"tune") as Dictionary).duplicate(true) if lighting and lighting.get(&"tune") is Dictionary else {}
	var base_q := String(Q.call("current"))
	for v in _variants:
		var tune: Dictionary = v.tune
		var rt := {}
		var lt := {}
		var raw := {}
		for k in tune:
			if k == "quality": continue
			if String(k).contains("."): raw[k] = tune[k]
			elif base_rig.has(k): rt[k] = tune[k]
			elif base_light.has(k): lt[k] = tune[k]
			else: print("[lookdev] unknown key ", k)
		var q := String(tune.get("quality", base_q))
		if q != String(Q.call("current")): Q.call("apply", q)
		if rig:
			rig.call("set_tune", base_rig.duplicate(true))
			rig.call("set_tune", rt)
		if lighting and lighting.has_method("set_tune"):
			lighting.call("set_tune", base_light.duplicate(true))
			lighting.call("set_tune", lt)
		# raw property overrides: env.<prop> (Environment), cam.<prop> (CameraAttributes), vp.<prop> (root viewport),
		# light.<member>.<prop> (a light of lighting.gd, e.g. light.ceiling.shadow_enabled=0)
		for k in raw:
			var parts := String(k).split(".")
			var target: Object = null
			var prop := parts[parts.size() - 1]
			match parts[0]:
				"env": target = rig.get(&"environment") if rig else null
				"cam": target = rig.get(&"camera_attributes") if rig else null
				"vp": target = root.get_viewport()
				"light": target = lighting.get(parts[1]) if lighting and parts.size() > 2 else null
			if target == null:
				print("[lookdev] no target for ", k)
				continue
			var cur: Variant = target.get(prop)
			var val: Variant = raw[k]
			if cur is bool: val = float(val) > 0.5
			elif cur is int: val = int(val)
			target.set(prop, val)
		for vn in _views:
			if not _menu and vn != "asis":
				# fixed camera: the player body goes there, but the camera is written here (no bob / sway / flinch)
				var c: Array = []
				var eye_y := 1.62
				if G_VIEWS.has(vn):
					c = G_VIEWS[vn]
					eye_y = 0.0
				elif views.has(vn): c = views[vn]
				elif vn.contains("+"):
					for x in vn.split("+"): c.append(float(x))
				var pl: Node = game.get(&"player")
				if c.size() >= 3 and pl != null:
					var yaw := deg_to_rad(float(c[3]) if c.size() > 3 else 0.0)
					var pitch := deg_to_rad(float(c[4]) if c.size() > 4 else 0.0)
					var eye := Vector3(float(c[0]), float(c[1]) + eye_y, float(c[2]))
					var feet := eye - Vector3(0, 1.62, 0)
					var gd = game.get(&"garderie")
					if G_VIEWS.has(vn) and gd != null and gd.has_method("teleport_player"): gd.call("teleport_player", feet, yaw, pitch)
					else: pl.call("teleport", feet + Vector3(0, 0.02, 0), yaw, pitch)
					await process_frame
					pl.set(&"camera_override", true)
					pl.set(&"enabled", false)
					var cam := pl.get(&"camera") as Camera3D
					cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), eye)
					cam.fov = float(root.get_node("Settings").call("get_value", "fov", 72.0))
					if not cam.current: cam.make_current()
					if rig: rig.call("snap_focus")
			await _frames_wait(_frames)
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			var path := "%s_%s_%s.png" % [_out, v.name, vn.replace("+", "_")]
			img.save_png(path)
			var fd := float(rig.get(&"focus_distance")) if rig else -1.0
			print("[lookdev] ", path, " focus=%.2f" % fd)
	quit()
