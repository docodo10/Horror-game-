## Chapter 2 (l'étage), played by script in the real game scene.
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/etage/tests/test_etage.gd -- --autostart --mode=etage --no-garderie
## Checks: the level starts (house hidden, player at the top of the stairs, floor under the feet, wooden steps),
## the front door is locked without the key, taking the key wakes the walker behind the player's back, it stands
## still while looked at and comes closer while not, it catches a player who keeps their back turned (and the level
## resets), and the door opens with the key held three seconds -> the game is won.
extends SceneTree

const L := preload("res://scripts/etage/etage_layout.gd")

var _fails: Array[String] = []
var _checks := 0

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		print("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _f(n: int) -> void:
	for i in n: await process_frame

func _look_at(P: Node, target: Vector3) -> void:
	var d: Vector3 = target - (P as Node3D).global_position
	P.set("yaw", atan2(-d.x, -d.z))
	P.set("pitch", 0.0)

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var G := root.get_node("Game")
	var t0 := Time.get_ticks_msec()
	while String(G.get(&"state")) != "playing" and Time.get_ticks_msec() - t0 < 240000: await process_frame
	var E = G.get(&"etage")
	var P: Node = G.get(&"player")
	var I: Node = G.get(&"interaction")
	check(E != null and E.get("built") == true, "the level is built")
	if E == null:
		_finish()
		return
	await _f(20)
	print("[etage] stats ", E.get("stats"))
	check(String(G.get(&"mode")) == "etage" and E.get("active") == true and (E as Node3D).visible, "chapter 2 is running")
	check(not (G.get(&"world") as Node3D).visible, "the house is hidden")
	check((P as Node3D).global_position.distance_to(L.START) < 0.3 and absf((P as Node3D).global_position.y) < 0.05, "the player stands at the top of the stairs, on the floor")
	check((E.get("stats") as Dictionary).get("missing_textures", ["?"]).is_empty(), "no texture missing: %s" % str((E.get("stats") as Dictionary).get("missing_textures")))
	for id in ["etage.front", "etage.chambre", "etage.key", "etage.letter", "etage.bed_note"]:
		check((I.get("entries") as Dictionary).has(id), "registered: %s" % id)
	# a walk down the hallway: wooden floor, the body stays on it
	Input.action_press("move_forward")
	await _f(150)
	Input.action_release("move_forward")
	var pp: Vector3 = (P as Node3D).global_position
	check(pp.x > L.START.x + 2.5 and absf(pp.y) < 0.05 and absf(pp.z) < 0.7, "walked east along the hallway (%s)" % str(pp))
	check(String(P.get("surface")) in ["wood", "carpet"], "steps on wood or on the runner (%s)" % P.get("surface"))
	# the front door without the key
	P.call("teleport", Vector3(67.0, 0.0, 0.0), -PI * 0.5, 0.0)
	await _f(10)
	await I.call("activate", "etage.front", true)
	check(int(E.get("stage")) == 1, "front door locked: stage 1")
	# the bedroom door: a crack, then slammed
	P.call("teleport", Vector3(55.04, 0.0, -0.2), 0.0, 0.0)
	await _f(10)
	I.call("activate", "etage.chambre", true)
	await _f(60)
	var dch: Dictionary = (E.get("_doors") as Dictionary).chambre
	check(float(dch.a) > 0.05, "the bedroom door gives a little")
	await _f(140)
	check(float(dch.a) < 0.01, "and is shut again")
	# the key on the mantel, the player facing the wall
	P.call("teleport", Vector3(64.4, 0.0, -4.3), 0.0, 0.0)
	_look_at(P, L.MANTEL)
	await _f(10)
	await I.call("activate", "etage.key", true)
	check(int(E.get("stage")) == 2, "key taken: stage 2")
	await _f(60 * 6)
	var W: Dictionary = (E.get("_walkers") as Array)[0]
	var sc: Array = E.ctx.room_fx.sconces
	check(sc.all(func(s): return not (s.light as Light3D).visible), "the sconces are out")
	check(W.awake == true, "the walker is awake")
	var d0 := Vector2(W.pos.x - 64.4, W.pos.z + 4.3).length()
	check(d0 < 4.0 and d0 > 0.9, "it stands behind the player (%.2f m)" % d0)
	check(float(dch.a) > 0.9, "the bedroom door stands open")
	# looked at: a statue
	_look_at(P, W.pos)
	await _f(30)
	var p1: Vector3 = W.pos
	await _f(120)
	check((W.pos as Vector3).distance_to(p1) < 0.001, "it does not move while looked at")
	check(W.revealed == true, "and it has been seen")
	# back turned from a distance: it comes closer, creaking
	P.call("teleport", Vector3(57.4, 0.0, -1.8), PI * 0.5, 0.0)          # far west of the salon, facing west
	await _f(5)
	var far: float = Vector2(W.pos.x - 57.4, W.pos.z + 1.8).length()
	await _f(90)
	var near: float = Vector2(W.pos.x - 57.4, W.pos.z + 1.8).length()
	check(near < far - 1.0, "back turned: it came closer (%.2f -> %.2f m)" % [far, near])
	# back kept turned: caught, and the level starts over
	t0 = Time.get_ticks_msec()
	while String(G.get(&"state")) == "playing" and Time.get_ticks_msec() - t0 < 30000: await process_frame
	check(String(G.get(&"state")) != "playing", "it reached the player: caught")
	var ui: Node = G.get(&"ui")
	t0 = Time.get_ticks_msec()
	while String(G.get(&"state")) != "playing" and Time.get_ticks_msec() - t0 < 30000:
		# the "caught" card waits for a key
		var ev := InputEventKey.new(); ev.keycode = KEY_ENTER; ev.physical_keycode = KEY_ENTER; ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		var ev2 := InputEventKey.new(); ev2.keycode = KEY_ENTER; ev2.physical_keycode = KEY_ENTER; ev2.pressed = false
		Input.parse_input_event(ev2)
		await process_frame
	check(String(G.get(&"state")) == "playing", "play goes on after the capture (night %s)" % G.get(&"night"))
	await _f(20)
	check(int(E.get("stage")) == 1 and (P as Node3D).global_position.distance_to(L.START) < 0.4, "the level is reset, the player back at the stairs")
	check(W.awake == false and (W.pos as Vector3).distance_to(L.WALKER[0]) < 0.01, "the walker is back under its sheet")
	# second try: the key, then straight to the door with a head start
	P.call("teleport", Vector3(64.4, 0.0, -4.3), 0.0, 0.0)
	_look_at(P, L.MANTEL)
	await _f(10)
	await I.call("activate", "etage.key", true)
	P.call("teleport", Vector3(67.1, 0.0, 0.0), -PI * 0.5, 0.0)
	await _f(10)
	I.call("activate", "etage.front", true)
	t0 = Time.get_ticks_msec()
	while String(G.get(&"state")) == "playing" and Time.get_ticks_msec() - t0 < 20000: await process_frame
	check(String(G.get(&"state")) == "won", "the door opens with the key: won (state %s)" % G.get(&"state"))
	_finish()

func _finish() -> void:
	print("[etage] %d checks, %d failed" % [_checks, _fails.size()])
	print("ETAGE TEST OK" if _fails.is_empty() else "ETAGE TEST FAILED: %s" % str(_fails))
	quit(0 if _fails.is_empty() else 1)
