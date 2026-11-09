## Scripted player test (SceneTree): drives the real input actions (Input.action_press / parse_input_event) in the
## player sandbox and checks movement, stairs, surfaces, footsteps/noise, sprint FOV kick, stamina/exhaustion, crouch,
## bump, look (mouse + gamepad, hide limits), hide spot enter/exit, flashlight battery/flicker/swap/death, flinch,
## visibility, respawn. Deterministic with --fixed-fps:
##   godot --headless --fixed-fps 60 --path pc -s res://scripts/player/tests/movement_test.gd
## Prints "[test] PASS|FAIL name: details", a summary, and exits with the number of failures.
extends SceneTree

var G: Node          # autoloads, fetched at runtime (this script compiles before they are registered)
var E: Node
var P: CharacterBody3D
var W: Node3D
var fails := 0
var passes := 0
var noises: Array = []
var bumps: Array = []
var hides: Array = []
var flashes: Array = []
var stam: Array = []

func _initialize() -> void:
	_run()

func _run() -> void:
	G = root.get_node("Game")
	E = root.get_node("Events")
	var scene: PackedScene = load("res://scripts/player/tests/sandbox.tscn")
	var sb := scene.instantiate()
	root.add_child(sb)
	while not sb.is_built:
		await process_frame
	P = G.player
	W = G.world
	# the checks below are written for the reference rig: 72 deg lens, full camera motion (not saved)
	var S := root.get_node("Settings")
	for kv in [["fov", 72.0], ["camera_motion", 1.0]]:
		(S.get(&"values") as Dictionary)[kv[0]] = kv[1]
		E.emit_signal("settings_changed", kv[0], kv[1])
	E.noise.connect(func(pos, loud, src): noises.append([pos, loud, src]))
	E.player_bump.connect(func(tag): bumps.append(tag))
	E.player_hide.connect(func(h, id): hides.append([h, id]))
	E.player_flashlight.connect(func(has, on, bat): flashes.append([has, on, bat]))
	E.player_stamina.connect(func(v, ex, br): stam.append([v, ex, br]))
	seed(20261108)                                  # deterministic flicker / jitter
	G.start()
	await _ticks(10)
	_check("spawn", P.global_position.distance_to(Vector3(0.25, 0, 1.5)) < 0.05,
		"pos=%s fov=%.2f eye=%s" % [P.global_position, P.camera.fov, P.eye_position()])

	await _test_walk()
	await _test_sprint_fov()
	await _test_nook_concrete()
	await _test_bump()
	await _test_crouch()
	await _test_stairs()
	await _test_look()
	await _test_hide()
	await _test_flashlight()
	await _test_stamina()
	await _test_fear_flinch()
	await _test_visibility_respawn()

	print("[test] SUMMARY: %d passed, %d failed" % [passes, fails])
	quit(fails)

# ---------------------------------------------------------------- helpers

func _ticks(n: int) -> void:
	for i in n:
		await physics_frame

func _check(name: String, ok: bool, details := "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[test] %s %s: %s" % ["PASS" if ok else "FAIL", name, details])

func _press(actions: Array, strength := 1.0) -> void:
	for a in actions:
		Input.action_press(a, strength)

func _release(actions: Array) -> void:
	for a in actions:
		Input.action_release(a)

func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

## Mouse motion; returns once the player has applied it (buffered events are flushed at the end of the next frame).
func _mouse(dx: float, dy: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	ev.screen_relative = Vector2(dx, dy)
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	await process_frame

func _player_noises(from: int) -> Array:
	var out := []
	for i in range(from, noises.size()):
		if str(noises[i][2]) == "player":
			out.append(float(noises[i][1]))
	return out

# ---------------------------------------------------------------- tests

func _test_walk() -> void:
	P.teleport(Vector3(1.5, 0, 1.6), 0.0)
	await _ticks(5)
	var z0 := P.global_position.z
	var n0 := noises.size()
	var max_v := 0.0
	var min_v := 9.0
	_press(["move_forward"])
	for i in 90:
		await physics_frame
		if i > 45:
			max_v = maxf(max_v, P.speed)
			min_v = minf(min_v, P.speed)
	var bob_eye: float = P.eye_position().y
	_release(["move_forward"])
	var dz := P.global_position.z - z0
	var steps := _player_noises(n0)
	_check("walk speed 1.9 m/s", absf(max_v - 1.9) < 0.08 and min_v > 1.75, "speed %.3f..%.3f dz=%.2f" % [min_v, max_v, dz])
	_check("walk footsteps (carpet 0.10)", steps.size() >= 4 and steps.all(func(l): return l > 0.049 and l < 0.1001) and absf(steps.max() - 0.10) < 0.001,
		"%d steps loud=%s surf=%s" % [steps.size(), steps.slice(0, 4), P.surface])
	_check("walk heads north (-Z)", dz < -2.4 and absf(P.global_position.x - 1.5) < 0.02, "dz=%.2f eye=%.3f" % [dz, bob_eye])
	await _ticks(40)
	_check("walk stops", P.speed < 0.05 and not P.moving, "speed=%.3f" % P.speed)

func _test_sprint_fov() -> void:
	P.teleport(Vector3(1.5, 0, 1.6), 0.0)
	await _ticks(5)
	var n0 := noises.size()
	var st0: float = P.stamina
	var max_fov := 0.0
	var max_v := 0.0
	_press(["move_forward", "sprint"])
	for i in 66:
		await physics_frame
		max_fov = maxf(max_fov, P.camera.fov)
		max_v = maxf(max_v, P.speed)
	var sprinting: bool = P.sprinting
	_release(["move_forward", "sprint"])
	var steps := _player_noises(n0)
	_check("sprint speed 3.3", absf(max_v - 3.3) < 0.1 and sprinting, "max %.3f" % max_v)
	_check("sprint FOV kick ~+7", max_fov > 72.0 + 5.5 and max_fov < 72.0 + 7.6, "max fov %.2f" % max_fov)
	_check("sprint drains stamina", P.stamina < st0 - 0.15, "stamina %.3f -> %.3f" % [st0, P.stamina])
	_check("sprint steps loud 0.45", steps.has(0.45), "%s" % [steps])
	await _ticks(60)
	_check("FOV back to base", absf(P.camera.fov - 72.0) < 0.6, "fov %.2f" % P.camera.fov)

func _test_nook_concrete() -> void:
	P.teleport(Vector3(1.35, 0, -2.0), 0.0)
	await _ticks(5)
	var n0 := noises.size()
	_press(["move_forward"])
	await _ticks(70)
	var surf: String = P.surface
	var alc: bool = P.is_in_alcove()
	_release(["move_forward"])
	await _ticks(20)
	_check("nook = concrete", surf == "concrete" and alc, "pos=%s surf=%s alcove=%s steps=%s" % [P.global_position, surf, alc, _player_noises(n0)])

func _test_bump() -> void:
	P.teleport(Vector3(-0.55, 0, 0.3), 0.0)       # 2 m run-up toward the dresser against the north wall
	await _ticks(5)
	var b0 := bumps.size()
	var n0 := noises.size()
	_press(["move_forward", "sprint"])
	await _ticks(50)
	_release(["move_forward", "sprint"])
	var got := bumps.slice(b0)
	_check("bump when sprinting into furniture", got.size() >= 1 and _player_noises(n0).has(0.3), "bumps=%s pos=%s" % [got, P.global_position])
	await _ticks(30)

func _test_crouch() -> void:
	P.teleport(Vector3(1.5, 0, 1.6), 0.0)
	await _ticks(5)
	await _tap("crouch")
	var min_eye := 9.0
	for i in 40:
		await physics_frame
		min_eye = minf(min_eye, P.eye_height)
	_check("crouch eye 0.95 (+dip)", P.crouched and absf(P.eye_height - 0.95) < 0.02 and min_eye < 0.95, "eye %.3f min %.3f" % [P.eye_height, min_eye])
	var n0 := noises.size()
	var max_v := 0.0
	_press(["move_forward"])
	for i in 70:
		await physics_frame
		max_v = maxf(max_v, P.speed)
	_release(["move_forward"])
	var steps := _player_noises(n0)
	_check("crouch walk 0.9 m/s, steps 0.03", absf(max_v - 0.9) < 0.05 and steps.size() >= 1 and steps.all(func(l): return absf(l - 0.03) < 0.005),
		"max %.3f steps %s" % [max_v, steps])
	_check("crouch halves visibility", absf(P.get_visibility() - 0.35) < 0.01, "vis %.2f" % P.get_visibility())
	await _tap("crouch")
	await _ticks(40)
	_check("stand up", not P.crouched and absf(P.eye_height - 1.62) < 0.02, "eye %.3f" % P.eye_height)

func _test_stairs() -> void:
	P.teleport(Vector3(-3.0, 0, 2.2), 0.0)
	await _ticks(5)
	var n0 := noises.size()
	var max_dy := 0.0
	var prev_eye: float = P.eye_position().y
	var max_v := 0.0
	var wood := false
	var stairs := false
	_press(["move_forward"])
	for i in 220:
		await physics_frame
		var e: float = P.eye_position().y
		max_dy = maxf(max_dy, e - prev_eye)
		prev_eye = e
		if P.global_position.y > 0.6 and P.global_position.y < 2.2:
			max_v = maxf(max_v, P.speed)
			wood = wood or P.surface == "wood"
			stairs = stairs or P.on_stairs
	_release(["move_forward"])
	await _ticks(30)
	var pos := P.global_position
	var steps := _player_noises(n0)
	_check("climb stairs to the upper hall", pos.y > 2.7 and pos.y < 2.8 and pos.z < -2.8, "pos=%s eye=%.3f" % [pos, P.eye_position().y])
	_check("stairs speed x0.8 (1.52 horizontal)", absf(max_v - 1.52) < 0.08, "max %.3f" % max_v)
	# web: loudness = 0.18 (wood) x k, k = speed / 1.9 => 0.144 at stair speed (+0.04 when the tread creaks)
	_check("stairs = wood + on_stairs", wood and stairs and steps.any(func(l): return l > 0.13 and l < 0.23), "steps %s" % [steps.slice(0, 6)])
	_check("tread-by-tread eye rise", max_dy > 0.006, "max eye rise per tick %.4f" % max_dy)
	# walk back down: turn around (yaw 180) with the mouse-free API, landing dips on the way down
	P.teleport(Vector3(-3.0, 2.75, -2.3), PI)
	await _ticks(10)
	_press(["move_forward"])
	var min_y := 9.0
	for i in 220:
		await physics_frame
		min_y = minf(min_y, P.global_position.y)
	_release(["move_forward"])
	await _ticks(20)
	_check("walk down to the floor", P.global_position.y < 0.05 and P.global_position.z > 1.6, "pos=%s" % P.global_position)

func _test_look() -> void:
	P.teleport(Vector3(0.9, 0, 0.0), 0.0)
	await _ticks(5)
	var y0: float = P.yaw
	await _mouse(100.0, 0.0)
	await _ticks(2)
	_check("mouse look 0.0022 rad/px", absf((y0 - P.yaw) - 0.22) < 0.002, "dyaw %.4f" % (y0 - P.yaw))
	var p0: float = P.pitch
	await _mouse(0.0, 100.0)
	await _ticks(2)
	_check("mouse down = look down", absf((p0 - P.pitch) - 0.22) < 0.002, "dpitch %.4f" % (p0 - P.pitch))
	var y_big: float = P.yaw
	await _mouse(1500.0, 0.0)                      # fast high-DPI flick: applied in full (no clamping/smoothing)
	await _ticks(2)
	_check("big flick not clamped", absf(wrapf(y_big - P.yaw - 3.3, -PI, PI)) < 0.003, "dyaw %.4f" % wrapf(y_big - P.yaw, -PI, PI))
	var y1: float = P.yaw
	_press(["look_right"], 1.0)
	await _ticks(30)
	_release(["look_right"])
	await _ticks(2)
	var d: float = y1 - P.yaw
	_check("gamepad look (2.7 rad/s + boost)", d > 1.3 and d < 2.0, "dyaw %.3f in 0.5 s" % d)
	# gamepad L3 = sprint toggle (latched until the stick is released)
	P.teleport(Vector3(1.5, 0, 1.6), 0.0)
	await _ticks(5)
	_press(["move_forward"])
	await _ticks(5)
	var l3 := InputEventJoypadButton.new()
	l3.button_index = JOY_BUTTON_LEFT_STICK
	l3.pressed = true
	Input.parse_input_event(l3)
	await _ticks(3)
	var l3_up := InputEventJoypadButton.new()
	l3_up.button_index = JOY_BUTTON_LEFT_STICK
	l3_up.pressed = false
	Input.parse_input_event(l3_up)
	await _ticks(40)
	var sp_latched: bool = P.sprinting
	var v_latched: float = P.speed
	_release(["move_forward"])
	await _ticks(30)
	_press(["move_forward"])
	await _ticks(40)
	var sp_after: bool = P.sprinting
	_release(["move_forward"])
	await _ticks(30)
	_check("gamepad L3 sprint latch", sp_latched and v_latched > 3.0 and not sp_after and P.using_gamepad,
		"latched=%s v=%.2f after_release=%s pad=%s" % [sp_latched, v_latched, sp_after, P.using_gamepad])

func _test_hide() -> void:
	var spot: Dictionary = W.hide_spots[0]
	P.teleport(Vector3(-1.6, 0, -1.9), PI * 0.5)
	await _ticks(5)
	var h0 := hides.size()
	var door = spot.door
	var t0 := Time.get_ticks_msec()
	await P.enter_hide(spot)
	var ok_pos := Vector2(P.global_position.x, P.global_position.z).distance_to(Vector2(-3.05, -2.05)) < 0.05
	_check("enter_hide", P.hidden and ok_pos and absf(P.eye_position().y - 1.35) < 0.05 and hides.size() > h0 and hides[h0][0] == true and hides[h0][1] == "closet",
		"hidden=%s pos=%s eye=%.3f events=%s" % [P.hidden, P.global_position, P.eye_position().y, hides.slice(h0)])
	await _ticks(60)
	_check("closet door closed behind", door.is_open == false and not door.animating, "is_open=%s" % door.is_open)
	# limited look: +-50 deg yaw, +-30 deg pitch around hide_yaw
	await _mouse(1200.0, 0.0)
	await _ticks(2)
	var dy := wrapf(P.yaw - float(spot.hide_yaw), -PI, PI)
	await _mouse(0.0, -1200.0)
	await _ticks(2)
	_check("hidden look limits", absf(absf(dy) - deg_to_rad(50.0)) < 0.01 and absf(P.pitch - deg_to_rad(30.0)) < 0.01, "dyaw %.1f° pitch %.1f°" % [rad_to_deg(dy), rad_to_deg(P.pitch)])
	_check("hidden visibility 0", P.get_visibility() == 0.0, "")
	_press(["move_forward", "sprint"])
	await _ticks(30)
	_release(["move_forward", "sprint"])
	_check("no movement while hidden", Vector2(P.global_position.x, P.global_position.z).distance_to(Vector2(-3.05, -2.05)) < 0.01, "pos=%s" % P.global_position)
	await P.exit_hide()
	var ok_exit := Vector2(P.global_position.x, P.global_position.z).distance_to(Vector2(-2.05, -2.05)) < 0.05
	_check("exit_hide", not P.hidden and ok_exit and hides.back()[0] == false, "pos=%s yaw=%.2f" % [P.global_position, P.yaw])
	await _ticks(60)
	_check("door closed after exit", door.is_open == false, "")
	# respawn while hidden cancels cleanly
	P.enter_hide(spot)
	await _ticks(20)
	P.respawn()
	await _ticks(70)
	_check("respawn cancels hiding", not P.hidden and not P.hide_busy() and P.global_position.distance_to(Vector3(0.25, 0, 1.5)) < 0.05, "pos=%s" % P.global_position)
	print("[test] (hide timings %d ms)" % (Time.get_ticks_msec() - t0))

func _test_flashlight() -> void:
	P.teleport(Vector3(0.9, 0, 0.0), 0.0)
	var f0 := flashes.size()
	P.give_flashlight()
	await _ticks(20)
	var L: SpotLight3D = P.flashlight.light
	_check("give_flashlight -> on", P.flashlight.has and P.flashlight.on and L.visible and absf(L.light_energy - 13.37 * (0.6 + 0.4)) < 0.3 and flashes.size() > f0,
		"energy %.2f events %s" % [L.light_energy, flashes.slice(f0)])
	_check("cookie projector set (shadows on)", L.light_projector != null and L.light_projector.get_width() == 256 and L.shadow_enabled, "")
	P.set_flashlight_shadows(false)
	var fb_ok := L.light_projector == null and not L.shadow_enabled and L.spot_angle_attenuation > 0.2
	P.set_flashlight_shadows(true)
	_check("shadow-off fallback drops the cookie", fb_ok and L.light_projector != null and L.shadow_enabled and L.spot_angle_attenuation < 0.1, "")
	var q0: String = str(root.get_node("Settings").get_value("quality", "high"))
	E.settings_changed.emit("quality", "low")       # (signal only: the user's settings file is left alone)
	_check("low quality keeps the torch shadow (projector needs it)", L.shadow_enabled and L.light_projector != null, "")
	E.settings_changed.emit("quality", q0)
	await _tap("flashlight")
	await _ticks(30)                               # filament fade-out (~0.25 s) then the light is hidden
	_check("F toggles off", not P.flashlight.on and not L.visible, "energy %.3f" % L.light_energy)
	await _tap("flashlight")
	await _ticks(10)
	# drain: 100 % -> 360 s; check rate over 3 s
	var b0: float = P.flashlight.battery
	await _ticks(180)
	var used: float = b0 - float(P.flashlight.battery)
	_check("battery drain 360 s", absf(used - 3.0 * 100.0 / 360.0) < 0.05, "used %.3f %% in 3 s" % used)
	# low battery flicker
	P.flashlight.battery = 6.0
	var lo := 0
	var n := 0
	var bursts := 0
	var was_on := false
	for i in 600:
		await process_frame
		n += 1
		if L.light_energy < 13.37 * 0.75 * 0.5:
			lo += 1
		if P._flick_on and not was_on:
			bursts += 1
		was_on = P._flick_on
	_check("flicker below 15 %", lo > 3 and lo < n * 0.6 and bursts >= 2, "%d/%d dark frames, %d bursts, flick_t %.2f" % [lo, n, bursts, P._flick_t])
	# auto swap with a spare battery
	G.inventory.add("battery", 1)
	P.flashlight.battery = 0.05
	await _ticks(60)
	_check("auto swap battery", P.flashlight.on and float(P.flashlight.battery) > 98.0 and G.inventory.count("battery") == 0, "battery %.2f spares %d" % [P.flashlight.battery, G.inventory.count("battery")])
	# no spare: dies after a violent flicker
	P.flashlight.battery = 0.05
	await _ticks(120)
	_check("battery dies", not P.flashlight.on and float(P.flashlight.battery) == 0.0 and not L.visible, "on=%s" % P.flashlight.on)
	P.set_flashlight_on(true)
	await _ticks(2)
	_check("cannot turn on a dead torch", not P.flashlight.on, "")
	P.add_battery(60.0)
	P.set_flashlight_on(true)
	await _ticks(20)
	_check("add_battery revives", P.flashlight.on and absf(float(P.flashlight.battery) - 60.0) < 0.5, "battery %.2f" % P.flashlight.battery)
	# lag spring: a fast turn leaves the beam behind, then it catches up
	await _mouse(120.0, 0.0)
	var lag := L.rotation.y
	await _ticks(60)
	_check("beam lags fast turns then settles", lag > 0.05 and absf(L.rotation.y) < 0.02, "lag %.3f -> %.4f" % [lag, L.rotation.y])

func _test_stamina() -> void:
	P.teleport(Vector3(10.5, 0, 0.0), -PI * 0.5)    # running track along +X
	await _ticks(5)
	P.stamina = 1.0
	_press(["move_forward", "sprint"])
	var exh_at := -1
	for i in 330:
		await physics_frame
		if P.exhausted and exh_at < 0:
			exh_at = i
	var v_exh: float = P.speed
	_release(["sprint"])
	_check("exhausted after ~4 s sprint", exh_at > 220 and exh_at < 270 and P.breath > 0.8, "at tick %d breath %.2f" % [exh_at, P.breath])
	_check("exhausted speed <= 1.15", v_exh <= 1.16, "speed %.3f" % v_exh)
	await _ticks(60)
	_release(["move_forward"])
	_check("stamina events", stam.size() > 10 and stam.back()[1] == true, "last %s" % [stam.back()])
	await _ticks(300)
	_check("recovers from exhaustion", not P.exhausted and P.stamina >= 0.4, "stamina %.2f" % P.stamina)

func _test_fear_flinch() -> void:
	P.teleport(Vector3(0.9, 0, 0.0), 0.0)
	await _ticks(30)
	# calm: tiny breathing only
	await _cam_jitter()
	var calm: float = _jit
	P._dbg_stress = 1.0
	await _ticks(120)
	await _cam_jitter()
	var scared: float = _jit
	P._dbg_stress = -1.0
	_check("fear tremor", scared > calm * 2.0 and scared > 0.0003, "pitch jitter calm %.5f scared %.5f" % [calm, scared])
	await _ticks(200)
	# flinch = ~2.4 deg pitch jolt + small dip + <1 deg FOV squeeze (web springs)
	var base_pitch: float = P.pitch
	var max_kick := 0.0
	var min_fov := 99.0
	E.entity_spotted.emit()
	for i in 20:
		await process_frame
		max_kick = maxf(max_kick, P.camera.global_transform.basis.get_euler().x - base_pitch)
		min_fov = minf(min_fov, P.camera.fov)
	_check("flinch on entity_spotted", max_kick > 0.025 and min_fov < 72.0 - 0.4, "pitch kick %.3f rad, min fov %.2f" % [max_kick, min_fov])
	await _ticks(60)
	max_kick = 0.0
	E.noise.emit(P.eye_position() + Vector3(1.5, 0, 0), 1.0, "breaker")
	for i in 20:
		await process_frame
		max_kick = maxf(max_kick, P.camera.global_transform.basis.get_euler().x - base_pitch)
	_check("flinch on a loud nearby noise", max_kick > 0.025, "pitch kick %.3f rad" % max_kick)
	await _ticks(60)
	max_kick = 0.0
	E.noise.emit(P.eye_position() + Vector3(1.5, 0, 0), 1.0, "breaker")   # same source again within 1.5 s: ignored
	for i in 20:
		await process_frame
		max_kick = maxf(max_kick, P.camera.global_transform.basis.get_euler().x - base_pitch)
	_check("continuous source does not re-startle", max_kick < 0.01, "pitch kick %.3f rad" % max_kick)

var _jit := 0.0
func _cam_jitter() -> void:
	var prev: float = P.camera.global_transform.basis.get_euler().x
	var acc := 0.0
	for i in 60:
		await process_frame
		var x: float = P.camera.global_transform.basis.get_euler().x
		acc += absf(x - prev)
		prev = x
	_jit = acc / 60.0

func _test_visibility_respawn() -> void:
	P.set_flashlight_on(false)
	await _ticks(5)
	_check("visibility lit room 0.7", absf(P.get_visibility() - 0.7) < 0.001, "%.2f" % P.get_visibility())
	W.set_power(false)
	await _ticks(5)
	_check("visibility dark 0.35", absf(P.get_visibility() - 0.35) < 0.001, "%.2f" % P.get_visibility())
	P.set_flashlight_on(true)
	await _ticks(5)
	_check("visibility torch 1.0", absf(P.get_visibility() - 1.0) < 0.001, "%.2f" % P.get_visibility())
	W.set_power(true)
	P.teleport(Vector3(1.35, 0, -3.6), 0.0)
	P.set_flashlight_on(false)
	await _ticks(5)
	_check("visibility nook 0.5", absf(P.get_visibility() - 0.5) < 0.001, "%.2f" % P.get_visibility())
	P.camera_override = true
	P.enabled = false
	P.reset_after_caught()
	await _ticks(5)
	_check("reset_after_caught", not P.camera_override and P.enabled and P.global_position.distance_to(Vector3(0.25, 0, 1.5)) < 0.05 and P.stamina == 1.0 and P.flashlight.has,
		"pos=%s" % P.global_position)
