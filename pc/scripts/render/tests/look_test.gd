## Look module headless test: runs the real main scene (autostart) and checks the lighting / Quality contract.
##   godot --headless --path pc -s res://scripts/render/tests/look_test.gd -- --autostart
## Prints LOOK TEST OK (exit 0) or the failed checks (exit 1). Never saves settings (writes Settings.values directly).
extends SceneTree

var _fails: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		print("  FAIL: ", what)

func _frames(n: int) -> void:
	for i in n: await process_frame

func _secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0): await process_frame

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var game := root.get_node("Game")
	var t0 := Time.get_ticks_msec()
	while String(game.get(&"state")) != "playing" and Time.get_ticks_msec() - t0 < 60000: await process_frame
	await _frames(10)
	var Q: Script = load("res://scripts/render/quality.gd")
	# ---- static API reachable the way other modules call it (load(...).has_method + call)
	for m in ["apply", "set_fear", "flash", "shake", "set_hidden_view", "set_blur", "current", "rig", "set_fill", "snap_focus"]:
		_check(Q.has_method(m), "Quality.%s exists (has_method on the script)" % m)
	var rig: Node = Q.call("rig")
	_check(rig != null, "Quality rig created by apply()")
	if rig == null: return _finish()
	_check(String(Q.call("current")) == String(root.get_node("Settings").call("get_value", "quality", "high")), "current() = Settings quality")
	var we := rig.get(&"world_environment") as WorldEnvironment
	_check(we != null and we.environment != null and we.camera_attributes != null, "WorldEnvironment with environment + camera attributes")
	_check(get_root().get_viewport().positional_shadow_atlas_size > 0, "positional shadow atlas on")
	var world: Node = game.get(&"world")
	var L: Node = world.get(&"lighting")
	_check(L != null and L.get_script() == load("res://scripts/world/lighting.gd"), "world.lighting is the look module's lighting.gd")
	if L == null: return _finish()
	for n in ["ceiling", "moon", "door_light", "tv_light", "tube_light", "bounce", "fill"]:
		_check(L.get(n) is Light3D, "light %s exists" % n)
	var ceil_l := L.get(&"ceiling") as OmniLight3D
	_check(ceil_l.shadow_enabled, "ceiling bulb casts shadows")
	var top := 0.0       # the intro flickers the bulb now and then: take the peak over a few frames
	for i in 30:
		await process_frame
		top = maxf(top, ceil_l.light_energy)
	_check(top > 2.0 and top < 4.0, "ceiling energy ~ 85 cd x 0.11 / PI (%.2f)" % top)
	var count := world.find_children("*", "Light3D", true, false).size()
	# ---- power off / on (energy only, the light set never changes)
	world.call("set_power", false)
	await _secs(0.6)
	_check(ceil_l.light_energy < 0.05, "power off: bulb dark (%.3f)" % ceil_l.light_energy)
	_check((L.get(&"fill") as Light3D).light_energy > 0.01, "power off: readability fill up")
	world.call("set_power", true)
	await _secs(0.2)
	await _secs(1.4)
	_check(ceil_l.light_energy > 2.0, "power back: bulb at full after the ramp (%.2f)" % ceil_l.light_energy)
	_check(world.find_children("*", "Light3D", true, false).size() == count, "no light added / removed by power changes")
	# ---- flicker + stress stay within [0, full]
	L.call("flicker", 0.6, 1.0)
	var lo := 9.0
	var tf := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tf < 550:
		await process_frame
		lo = minf(lo, ceil_l.light_energy)
	_check(lo < 2.5, "flicker dips the bulb (min %.2f)" % lo)
	L.call("set_stress", 0.9)
	await _secs(0.5)
	L.call("set_stress", 0.0)
	# ---- TV light
	L.call("set_tv_light", true, 1.0)
	await _secs(0.4)
	_check((L.get(&"tv_light") as Light3D).light_energy > 0.05, "TV light on")
	L.call("set_tv_light", false, 0.0)
	await _secs(0.5)
	_check((L.get(&"tv_light") as Light3D).light_energy < 0.02, "TV light off")
	# ---- menu mode: bulb on a dimmer, CRT key light
	L.call("set_menu_mode", true)
	L.call("set_tv_light", true, 1.0)
	await _secs(1.2)
	_check(ceil_l.light_energy < 0.6 and ceil_l.light_energy > 0.05, "menu: bulb dimmed (%.3f)" % ceil_l.light_energy)
	_check((L.get(&"tv_light") as Light3D).light_energy > 0.2, "menu: TV boosted (%.3f)" % (L.get(&"tv_light") as Light3D).light_energy)
	L.call("set_menu_mode", false)
	L.call("set_tv_light", false, 0.0)
	await _secs(1.6)
	_check(ceil_l.light_energy > 2.0, "menu off: bulb back (%.2f)" % ceil_l.light_energy)
	# ---- door strip occlusion
	L.call("door_strip_occluded", 1.0)
	await _secs(0.5)
	var dl := L.get(&"door_light") as Light3D
	_check(dl.light_energy < 0.06, "door strip occluded dims the leak (%.3f)" % dl.light_energy)
	L.call("door_strip_occluded", 0.0)
	# ---- post effects via the static API
	Q.call("flash", Color(0.48, 0.04, 0.02), 0.35, 0.3)
	Q.call("shake", 1.0, 0.6)
	Q.call("set_blur", 0.16)
	Q.call("set_hidden_view", 0.8)
	Q.call("set_fear", 0.9)
	await _frames(12)
	var pm := rig.get(&"post_material") as ShaderMaterial
	_check(float(pm.get_shader_parameter("blur")) > 0.05, "set_blur reaches the post shader")
	_check(float(pm.get_shader_parameter("hidden")) > 0.05, "set_hidden_view reaches the post shader")
	_check((pm.get_shader_parameter("flash") as Vector4).w > 0.0, "flash running")
	_check((pm.get_shader_parameter("shake") as Vector3).length() > 0.0, "shake running")
	Q.call("set_blur", 0.0)
	Q.call("set_hidden_view", 0.0)
	Q.call("set_fear", 0.0)
	# ---- autofocus: a sane distance in front of the camera
	await _secs(0.5)
	var fd := float(rig.get(&"focus_distance"))
	_check(fd >= 0.2 and fd <= 30.0, "autofocus distance in range (%.2f m)" % fd)
	# ---- blowout: flash then dark (gameplay order: blowout(), then world.set_power(false))
	L.call("blowout")
	world.call("set_power", false)
	await process_frame
	await process_frame
	_check(ceil_l.light_energy > 3.0, "blowout pop survives set_power(false) (%.2f)" % ceil_l.light_energy)
	await _secs(0.8)
	_check(ceil_l.light_energy < 0.05, "after the pop the bulb is dead (%.3f)" % ceil_l.light_energy)
	world.call("set_power", true)
	# ---- presets (no save: Settings.values + the signal)
	var settings := root.get_node("Settings")
	var orig: String = String((settings.get(&"values") as Dictionary).get("quality", "high"))
	for q in ["low", "medium", "high", "ultra"]:
		(settings.get(&"values") as Dictionary)["quality"] = q
		root.get_node("Events").emit_signal("settings_changed", "quality", q)
		await _frames(3)
		_check(String(Q.call("current")) == q, "preset %s applied" % q)
		var e := we.environment
		_check(e.sdfgi_enabled == (q == "ultra"), "%s: SDFGI %s" % [q, str(e.sdfgi_enabled)])
		_check(e.volumetric_fog_enabled == (q != "low"), "%s: volumetric fog %s" % [q, str(e.volumetric_fog_enabled)])
		_check(get_root().get_viewport().positional_shadow_atlas_size >= 2048, "%s: positional shadows available" % q)
		_check(world.find_children("*", "Light3D", true, false).size() == count, "%s: light count unchanged" % q)
	(settings.get(&"values") as Dictionary)["quality"] = orig
	root.get_node("Events").emit_signal("settings_changed", "quality", orig)
	await _frames(3)
	# ---- upscaler (Settings "upscale") + render scale
	var vp0 := get_root().get_viewport()
	(settings.get(&"values") as Dictionary)["upscale"] = "fsr2_quality"
	root.get_node("Events").emit_signal("settings_changed", "upscale", "fsr2_quality")
	_check(vp0.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and absf(vp0.scaling_3d_scale - 0.667) < 0.01 and not vp0.use_taa,
		"upscale fsr2_quality -> FSR2 at 0.667, TAA off")
	(settings.get(&"values") as Dictionary)["upscale"] = "off"
	(settings.get(&"values") as Dictionary)["render_scale"] = 0.75
	root.get_node("Events").emit_signal("settings_changed", "render_scale", 0.75)
	_check(vp0.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR and absf(vp0.scaling_3d_scale - 0.75) < 0.01, "render_scale 0.75 -> FSR1")
	(settings.get(&"values") as Dictionary).erase("upscale")
	(settings.get(&"values") as Dictionary).erase("render_scale")
	root.get_node("Events").emit_signal("settings_changed", "render_scale", 1.0)
	_check(vp0.scaling_3d_scale > 0.99, "native again")
	# ---- brightness live
	var b0: float = float((settings.get(&"values") as Dictionary).get("brightness", 1.0))
	(settings.get(&"values") as Dictionary)["brightness"] = 1.4
	root.get_node("Events").emit_signal("settings_changed", "brightness", 1.4)
	_check(absf(we.environment.tonemap_exposure - 1.4) < 0.01, "brightness -> exposure (%.2f)" % we.environment.tonemap_exposure)
	(settings.get(&"values") as Dictionary)["brightness"] = b0
	root.get_node("Events").emit_signal("settings_changed", "brightness", b0)
	_finish()

func _finish() -> void:
	if _fails.is_empty():
		print("LOOK TEST OK (%d checks)" % _checks)
		quit(0)
	else:
		print("LOOK TEST FAILED: %d of %d" % [_fails.size(), _checks])
		quit(1)
