## La Gardienne AI test (loaded by test_entity.gd, a SceneTree script). Builds the web basement's collision layout
## (level_meta.json colliders + door leaves on real Handles), a scripted player double, then plays scenarios against the
## REAL entity (gardienne.gd + model + AnimationTree) and the REAL Game.on_caught flow, printing each state timeline.
##   A  breaker noise (1.0 at the power box) while the player hides unseen: full visit dormant -> waking -> descending ->
##      searching -> returning -> dormant, door opened then closed + relocked, never stuck.
##   B  summon + chase + catch: spotted, chase, jumpscare (camera takeover, face at the lens), entity_caught, Game reset.
##   C  lose: the player breaks line of sight and hides unseen -> she searches the last known spot and goes home.
##   D  closet: the player slips into the closet while she watches -> she walks to it, opens it -> jumpscare from the closet.
##   E  watchdog: a crate dropped at the bottom of the stairs -> she still reaches the basement (backoff / detour / squeeze).
extends Node

const Fakes := preload("res://scripts/entity/tests/entity_fakes.gd")
const Entity := preload("res://scripts/entity/gardienne.gd")
const BREAKER := Vector3(2.6, 1.45, -4.553)

var world: Fakes.FakeWorld
var lighting: Fakes.FakeLighting
var player: Fakes.FakePlayer
var puzzles: Fakes.FakePuzzles
var entity: Entity
var failures: Array[String] = []
var checks := 0
var gtime := 0.0
var timeline: Array = []
var spotted := 0
var caught := 0
var caught_t := -1.0
var jump_t0 := -1.0
var max_stall := 0.0
var _stall_pos := Vector3.ZERO
var _stall_t := 0.0
var _min_face_dist := INF
var _min_y := INF

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _physics_process(dt: float) -> void:
	gtime += dt
	if entity == null: return
	# stall meter: longest time she meant to walk without moving 0.25 m
	if entity.call("_wants_to_move"):
		if entity.global_position.distance_to(_stall_pos) > 0.25:
			_stall_pos = entity.global_position
			_stall_t = 0.0
		else:
			_stall_t += dt
			max_stall = maxf(max_stall, _stall_t)
	else:
		_stall_pos = entity.global_position
		_stall_t = 0.0
	_min_y = minf(_min_y, entity.global_position.y)
	if entity.state == "jumpscare" and Game.camera:
		_min_face_dist = minf(_min_face_dist, Game.camera.global_position.distance_to(entity.face_position()))

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		printerr("[entity-test] FAIL: ", msg)

func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

## Waits until cond() or timeout (game seconds). Returns true if cond became true.
func _until(cond: Callable, timeout: float) -> bool:
	var t0 := gtime
	while gtime - t0 < timeout:
		if cond.call(): return true
		await get_tree().physics_frame
	return cond.call()

func _run() -> void:
	world = Fakes.FakeWorld.new()
	world.name = "World"
	add_child(world)
	world.build()
	lighting = Fakes.FakeLighting.new()
	world.add_child(lighting)
	world.lighting = lighting
	player = Fakes.FakePlayer.new()
	player.name = "Player"
	add_child(player)
	player.respawn()
	puzzles = Fakes.FakePuzzles.new()
	add_child(puzzles)
	Game.world = world
	Game.player = player
	Game.camera = player.camera
	Game.puzzles = puzzles
	Game.set_state("loading")
	entity = Entity.new()
	entity.name = "Gardienne"
	add_child(entity)
	Game.entity = entity
	var t0 := Time.get_ticks_msec()
	await entity.build()
	print("[entity-test] build %d ms, glb ok=%s, clips=%s" % [Time.get_ticks_msec() - t0, entity.model.ok, entity.model.clips.keys()])
	check(entity.model.ok, "gardienne.glb loaded")
	Events.entity_state.connect(func(s, p): timeline.append([snappedf(gtime, 0.01), p, s, _fmt(entity.global_position)]))
	Events.entity_spotted.connect(func(): spotted += 1)
	Events.entity_caught.connect(func():
		caught += 1
		caught_t = gtime)
	_perf_probe()
	Game.set_state("playing")
	await _frames(5)
	await _scenario_a()
	await _scenario_b()
	await _scenario_c()
	await _scenario_d()
	await _scenario_e()
	_finish()

# ------------------------------------------------------------------ helpers

func _fmt(p: Vector3) -> String: return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]

var _stalls0 := 0

func _stalls() -> int: return entity.stall_events - _stalls0

func _begin(name: String) -> void:
	_stalls0 = entity.stall_events
	timeline.clear()
	spotted = 0
	caught = 0
	caught_t = -1.0
	jump_t0 = -1.0
	max_stall = 0.0
	_min_face_dist = INF
	_min_y = INF
	Game.night = 1
	if Game.state != "playing": Game.set_state("playing")
	print("\n[entity-test] ===== %s (t=%.1f)" % [name, gtime])

func _print_timeline() -> void:
	for e in timeline: print("[entity-test]   %7.2f  %-10s -> %-10s at %s" % [e[0], e[1], e[2], e[3]])

func _states() -> Array:
	var out := []
	for e in timeline: out.append(e[2])
	return out

func _in_order(seq: Array, want: Array) -> bool:
	var i := 0
	for s in seq:
		if i < want.size() and s == want[i]: i += 1
	return i == want.size()

func _home_reset() -> void:
	entity.reset_after_caught()
	entity.set("_grace_t", 0.0)
	entity.set("_patrol_t", 1e6)
	player.reset_after_caught()
	player.visibility = 0.7
	player.set_flashlight_on(false)
	var cd = world.handles["door.closet"]
	if cd.is_open: await cd.close()
	await _frames(10)

func _perf_probe() -> void:
	var m = entity.model
	m.mode = "walk"
	m.speed = 0.95
	var t0 := Time.get_ticks_usec()
	for i in 300: m.update(1.0 / 60.0)
	var per_update := float(Time.get_ticks_usec() - t0) / 300.0
	var p := Vector3(0.9, 0.0, -0.45)
	t0 = Time.get_ticks_usec()
	for i in 300: entity.call("_segment_blocked", p.x, p.z, -2.0, -1.9, 0.27, 0.45, 1.72)
	var per_seg := float(Time.get_ticks_usec() - t0) / 300.0
	print("[entity-test] perf: model.update %.1f us (tree + 93 bones), capsule sweep %.1f us" % [per_update, per_seg])
	m.speed = 0.0
	m.mode = "idle"

# ------------------------------------------------------------------ scenarios

func _scenario_a() -> void:
	_begin("A: breaker noise, player hidden unseen in the closet")
	var spot: Dictionary = world.hide_spots[0]
	player.enter_hide(spot)   # she is dormant upstairs: she cannot have seen it
	await _frames(2)
	var door = world.handles["door.upstairs"]
	check(door.locked and not door.is_open, "A: upstairs door starts closed + locked")
	Events.noise.emit(BREAKER, 1.0, "breaker")
	# (lambdas capture locals by value: shared state lives in a Dictionary)
	var o := {"door_open": false, "near": INF}
	var ft: Vector3 = entity.call("_floor_target", BREAKER)
	var ok := await _until(func():
		if door.is_open: o.door_open = true
		o.near = minf(o.near, Vector2(entity.global_position.x - ft.x, entity.global_position.z - ft.z).length())
		return entity.state == "dormant" and timeline.size() >= 4, 200.0)
	var near_target: float = o.near
	_print_timeline()
	var st := _states()
	check(ok, "A: visit finished (back to dormant) within 200 s")
	check(_in_order(st, ["waking", "descending", "searching", "returning", "dormant"]), "A: state order %s" % [st])
	check(not st.has("chasing") and not st.has("jumpscare"), "A: no chase while the player hides unseen")
	check(o.door_open, "A: she opened the upstairs door")
	await _frames(90)
	check(not door.is_open and door.locked, "A: door closed and relocked behind her (open=%s locked=%s)" % [door.is_open, door.locked])
	check(_min_y < 0.05, "A: she reached the basement floor (min y %.2f)" % _min_y)
	check(near_target < 1.2, "A: she searched near the noise (closest %.2f m to %s)" % [near_target, _fmt(ft)])
	check(max_stall < 3.0, "A: never stalled more than 3 s (max %.2f s)" % max_stall)
	check(lighting.strip_calls > 0, "A: door strip light shadowed by her feet")
	check(not entity.active and entity.fear == 0.0, "A: inactive + fear 0 at the end")
	check(_stalls() == 0, "A: no watchdog intervention in the real layout (%d)" % _stalls())
	print("[entity-test]   A: closest to target %.2f m, max stall %.2f s, max stress %.2f" % [near_target, max_stall, lighting.max_stress])
	player.exit_hide()
	await _home_reset()

func _scenario_b() -> void:
	_begin("B: summon, chase, catch")
	player.teleport(Vector3(0.9, 0.0, -0.45), PI * 0.75)
	entity.summon(Vector3(0.9, 0.0, -0.45), "breaker")
	var o := {"cam": false}
	var ok := await _until(func():
		if entity.state == "jumpscare":
			if jump_t0 < 0.0: jump_t0 = gtime
			if player.camera_override: o.cam = true
		return caught > 0, 120.0)
	var cam_override_seen: bool = o.cam
	var face_d := _min_face_dist
	await _frames(30)
	_print_timeline()
	var st := _states()
	check(ok, "B: caught within 120 s")
	check(_in_order(st, ["waking", "descending", "chasing", "jumpscare", "dormant"]), "B: state order %s" % [st])
	check(spotted == 1, "B: entity_spotted emitted once (%d)" % spotted)
	check(cam_override_seen, "B: camera taken during the jumpscare")
	check(caught_t - jump_t0 > 1.3 and caught_t - jump_t0 < 1.6, "B: entity_caught %.2f s after the jumpscare start" % (caught_t - jump_t0))
	check(face_d < 0.45, "B: her face came to %.2f m from the lens" % face_d)
	check(entity.state == "dormant" and Game.night == 2, "B: Game.on_caught reset everyone (state %s, night %d)" % [entity.state, Game.night])
	check(not player.camera_override and player.enabled, "B: camera given back")
	check(entity.global_position.distance_to(Vector3(-3.0, 2.75, -3.6)) < 0.01, "B: she is back home")
	check(puzzles.resets == 1, "B: puzzles reset once")
	check(_stalls() == 0, "B: no watchdog intervention (%d)" % _stalls())
	print("[entity-test]   B: jumpscare at %.2f, caught after %.2f s, closest face %.2f m" % [jump_t0, caught_t - jump_t0, face_d])
	await _home_reset()

func _scenario_c() -> void:
	_begin("C: chase lost (the player breaks line of sight and hides unseen)")
	player.teleport(Vector3(0.9, 0.0, -0.45), PI)
	entity.summon(Vector3(0.9, 0.0, -0.45), "breaker")
	var ok := await _until(func(): return entity.state == "chasing", 60.0)
	check(ok, "C: she spotted the player")
	# the player vanishes into the laundry nook (behind the wall) and crouches out of sight
	player.teleport(Vector3(2.7, 0.0, -3.9), 0.0)
	player.visibility = 0.0
	ok = await _until(func(): return entity.state == "dormant", 200.0)
	_print_timeline()
	var st := _states()
	check(ok, "C: she gave up and went home")
	check(_in_order(st, ["chasing", "searching", "returning", "dormant"]), "C: state order %s" % [st])
	check(caught == 0, "C: no catch")
	check(max_stall < 3.0, "C: never stalled more than 3 s (max %.2f s)" % max_stall)
	check(_stalls() == 0, "C: no watchdog intervention (%d)" % _stalls())
	await _home_reset()

func _scenario_d() -> void:
	_begin("D: closet (she sees the player slip into it)")
	player.teleport(Vector3(-1.9, 0.0, -1.2), PI)
	entity.summon(Vector3(-1.0, 0.0, 0.0), "breaker")
	var ok := await _until(func(): return entity.state == "chasing", 60.0)
	check(ok, "D: she spotted the player near the closet")
	player.enter_hide(world.hide_spots[0])   # under her eyes
	var cd = world.handles["door.closet"]
	var o := {"opened": false}
	ok = await _until(func():
		if cd.is_open: o.opened = true
		if entity.state == "jumpscare" and jump_t0 < 0.0: jump_t0 = gtime
		return caught > 0, 60.0)
	await _frames(30)
	_print_timeline()
	var st := _states()
	check(ok, "D: caught in the closet")
	check(_in_order(st, ["chasing", "searching", "jumpscare", "dormant"]), "D: state order %s" % [st])
	check(o.opened, "D: she opened the closet door")
	await _frames(60)
	check(not cd.is_open, "D: closet door closed again by the reset")
	check(_stalls() == 0, "D: no watchdog intervention (%d)" % _stalls())
	print("[entity-test]   D: jumpscare at %.2f, caught at %.2f" % [jump_t0, caught_t])
	player.exit_hide()
	await _home_reset()

func _scenario_e() -> void:
	_begin("E: watchdog (crate blocking the bottom of the stairs)")
	var crate := world.add_box(Vector3(-3.0, 0.5, 1.95), Vector3(0.8, 1.0, 0.5), "crate")
	await _frames(2)
	player.teleport(Vector3(3.0, 0.0, -3.9), 0.0)   # far, behind the nook wall
	player.visibility = 0.0
	entity.summon(Vector3(-1.0, 0.0, 1.5), "breaker")
	# past the crate = off the stairs, on the basement floor, out of the stairwell footprint (x > -2.45 or z > 2.25)
	var ok := await _until(func():
		var p := entity.global_position
		return p.y < 0.05 and (p.x > -2.45 or p.z > 2.25), 120.0)
	_print_timeline()
	check(ok, "E: she got past the crate and reached the basement (state %s at %s)" % [entity.state, _fmt(entity.global_position)])
	check(_stalls() >= 3, "E: the watchdog escalated to the squeeze (%d stalls)" % _stalls())
	print("[entity-test]   E: at %s, state %s, %d watchdog stalls" % [_fmt(entity.global_position), entity.state, _stalls()])
	crate.queue_free()
	await _until(func(): return entity.state == "dormant", 200.0)
	check(entity.state == "dormant", "E: she still went home afterwards")

func _finish() -> void:
	if failures.is_empty():
		print("\n[entity-test] PASS %d checks" % checks)
		get_tree().quit(0)
	else:
		print("\n[entity-test] FAIL %d / %d checks:" % [failures.size(), checks])
		for f in failures: print("  - ", f)
		get_tree().quit(1)
