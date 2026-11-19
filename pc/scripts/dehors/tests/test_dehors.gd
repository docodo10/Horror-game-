## Chapter 3 (dehors), played by script in the real game scene.
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/dehors/tests/test_dehors.gd -- --autostart --mode=dehors --no-garderie --no-etage
## Plays the whole chapter: the level starts on the porch under the night look; steps sound of what is underfoot;
## the letter; the chained gate brings her out of the house; she does not hear a crouched walk on the grass and
## does hear a walk on the gravel, comes to the noise, listens, goes back to her round; the wind chimes, a thrown
## pebble, the horn and the radio pull her away; a hiding place is safe; the pots, the shed key, the shed, the
## cellar key, the cellar doors, the steps down, the bolt cutters, the doors slammed shut and pushed open again;
## she catches a player she walks into (progress is kept, she comes out again); the chain is cut, the gate pushed
## open -> the game is won.
extends SceneTree

const L := preload("res://scripts/dehors/dehors_layout.gd")

var _fails: Array[String] = []
var _checks := 0
var G: Node
var D
var H
var P: Node
var I: Node
var EV: Node

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		print("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _f(n: int) -> void:
	for i in n: await process_frame

func _tp(x: float, y: float, z: float, yaw_deg := -90.0) -> void:
	D.call("teleport_player", Vector3(x, y, z), deg_to_rad(yaw_deg), 0.0)
	await _f(6)

func _pp() -> Vector3:
	return (P as Node3D).global_position

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Waits (game frames) until fn() is true; false on timeout.
func _until(fn: Callable, frames: int) -> bool:
	for i in frames:
		if fn.call():
			return true
		await process_frame
	return fn.call()

func _her_at(x: float, z: float) -> void:
	H.call("spawn", Vector3(x, 0.0, z))
	await _f(2)

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	G = root.get_node("Game")
	EV = root.get_node("Events")
	var t0 := Time.get_ticks_msec()
	while String(G.get(&"state")) != "playing" and Time.get_ticks_msec() - t0 < 240000: await process_frame
	D = G.get(&"dehors")
	P = G.get(&"player")
	I = G.get(&"interaction")
	check(D != null and D.get("built") == true, "the level is built")
	if D == null:
		_finish()
		return
	H = D.get("her")
	await _f(20)
	var st: Dictionary = D.get("stats")
	print("[dehors] stats ", st)
	# ---------------------------------------------------------------- the start
	check(String(G.get(&"mode")) == "dehors" and D.get("active") == true and (D as Node3D).visible, "chapter 3 is running")
	check(not (G.get(&"world") as Node3D).visible, "the house of chapter 1 is hidden")
	check(_flat(_pp(), L.START) < 0.3 and absf(_pp().y - float(L.PORCH.y)) < 0.06, "the player stands on the porch (%s)" % str(_pp()))
	check((st.get("missing_textures", ["?"]) as Array).is_empty(), "no texture missing: %s" % str(st.get("missing_textures")))
	check(st.get("her_model") == true, "her body is La Gardienne's model")
	check(int(st.get("triangles", 0)) > 15000 and int(st.get("triangles", 0)) < 120000, "a modest triangle count (%d)" % int(st.get("triangles", 0)))
	var ids := ["dehors.gate", "dehors.shed_door", "dehors.key_shed", "dehors.key_cave", "dehors.trap", "dehors.trap_in", "dehors.cutters", "dehors.chimes",
		"dehors.horn", "dehors.radio", "dehors.pot_0", "dehors.pot_3", "dehors.note_porch", "dehors.note_cabane", "dehors.note_car", "dehors.note_cave",
		"dehors.hide_cabane", "dehors.exit_cabane", "dehors.hide_car", "dehors.hide_niche", "dehors.pebbles_0", "dehors.toolboard", "dehors.front"]
	var missing: Array = ids.filter(func(id): return not (I.get("entries") as Dictionary).has(id))
	check(missing.is_empty(), "interactions registered (missing: %s)" % str(missing))
	var rig = main.get_node_or_null("Look")
	check(rig != null and (rig.environment as Environment).background_mode == Environment.BG_SKY and (rig.environment as Environment).fog_enabled,
		"the night look is on (sky, fog)")
	check(String(P.get("surface")) == "wood", "the porch boards underfoot (%s)" % P.get("surface"))
	check(H.get("state") == "away" and not (H as Node3D).visible, "she is not in the yard yet")
	# down the steps, on foot
	Input.action_press("move_forward")
	await _f(130)
	Input.action_release("move_forward")
	await _f(10)
	check(_pp().x > 108.0 and absf(_pp().y) < 0.06, "walked down the porch steps (%s)" % str(_pp()))
	check(String(P.get("surface")) == "gravel", "on the gravel path (%s)" % P.get("surface"))
	await _tp(120.0, 0.0, 1.0)
	check(String(P.get("surface")) == "grass", "the lawn is grass (%s)" % P.get("surface"))
	await _tp(133.0, 0.0, 1.5)
	check(String(P.get("surface")) == "leaves", "dead leaves under the oak (%s)" % P.get("surface"))
	# ---------------------------------------------------------------- the letter on the porch
	await _tp(104.9, float(L.PORCH.y), -1.6, 90.0)
	I.call("activate", "dehors.note_porch")
	await _f(40)
	(G.get(&"ui") as Node).call("_close_note")
	await _f(20)
	check(D.flags.know_cutters == true and D.flags.know_cave_key == true, "the letter tells where the bolt cutters and the cellar key are")
	# ---------------------------------------------------------------- the gate: chained; she comes out
	await _tp(144.6, 0.0, 8.5)
	check(await I.call("activate", "dehors.gate"), "the gate can be tried")
	check(int(D.get("stage")) == 1 and D.flags.gate_seen == true, "the gate is chained: stage 1")
	check(await _until(func() -> bool: return D.get("_her_out") == true, 60 * 12), "she comes out of the house")
	check(H.get("state") == "enter" and (H as Node3D).visible and H.get("lantern_on") == true, "she walks out of the door, lantern lit")
	check(await _until(func() -> bool: return H.get("state") == "patrol", 60 * 8) and absf((H.get("pos") as Vector3).y) < 0.01, "down the steps, and her round begins")
	check(not (D.get("_nodes").lit as Node3D).visible, "the window upstairs has gone dark")
	# ---------------------------------------------------------------- what she hears
	await _her_at(121.0, 1.0)
	await _tp(126.0, 0.0, 1.0, 0.0)
	P.call("set_crouch", true)
	await _f(20)
	Input.action_press("move_forward")
	await _f(90)
	Input.action_release("move_forward")
	check(H.get("state") != "seek" and float(H.get("alert")) < 0.05, "crouched on the grass, 5 m from her: not heard (%s, alert %.2f)" % [H.get("state"), float(H.get("alert"))])
	P.call("set_crouch", false)
	await _f(20)
	await _her_at(114.0, 3.0)
	await _tp(126.0, 0.0, 8.5)
	Input.action_press("move_forward")
	await _f(70)
	Input.action_release("move_forward")
	check(H.get("state") == "seek" and float(H.get("alert")) > 0.2, "walking on the gravel 12 m from her: heard (%s, alert %.2f)" % [H.get("state"), float(H.get("alert"))])
	var heard_at := _pp()
	check(_flat(H.get("target"), heard_at) < 4.0, "she goes to where the steps were (%.1f m off)" % _flat(H.get("target"), heard_at))
	# the player slips away on the grass, crouched; she reaches the place, listens, then goes back to her round
	await _tp(134.0, 0.0, 14.0)
	check(await _until(func() -> bool: return H.get("state") == "listen", 60 * 20), "she reaches the place and listens")
	check(_flat(H.get("pos"), heard_at) < 4.5, "she stands where the noise was (%.1f m)" % _flat(H.get("pos"), heard_at))
	check(await _until(func() -> bool: return H.get("state") == "patrol", 60 * 12), "then she goes back to her round")
	# ---------------------------------------------------------------- pulling her away
	var fx: Dictionary = D.ctx.room_fx
	await _her_at(119.0, -3.0)
	await I.call("activate", "dehors.chimes")
	await _f(40)
	check(H.get("state") == "seek" and _flat(H.get("target"), fx.chimes) < 4.0, "the wind chimes: she turns to the porch")
	check(await _until(func() -> bool: return H.get("state") == "listen", 60 * 25) and _flat(H.get("pos"), fx.chimes) < 4.5, "and goes there")
	await _f(60 * 8)                                # (until the chimes are still)
	await I.call("activate", "dehors.pebbles_0")
	check(int(D.get("pebbles")) == 3, "three pebbles picked up")
	await _her_at(124.0, -2.0)
	await _tp(121.0, 0.0, 8.5)
	var land: Vector3 = D.call("throw_pebble")
	check(land != Vector3.ZERO and _flat(land, _pp()) > 6.0 and int(D.get("pebbles")) == 2, "a pebble thrown %.1f m" % _flat(land, _pp()))
	await _f(150)
	check(H.get("state") in ["seek", "listen"] and _flat(H.get("target"), land) < 4.0, "she goes to where the pebble fell (%.1f m off)" % _flat(H.get("target"), land))
	await _her_at(128.0, -6.0)
	await I.call("activate", "dehors.horn")
	await _f(50)
	check(H.get("state") == "seek" and _flat(H.get("target"), fx.horn) < 4.5 and float(H.get("alert")) > 0.6, "the horn of the car: she comes fast (alert %.2f)" % float(H.get("alert")))
	await _f(60 * 5)                                # (until the horn has died)
	# ---------------------------------------------------------------- a hiding place
	var cab: Dictionary = (D.get("hide_spots") as Array)[0]
	await _her_at(121.0, -9.0)
	await _tp(cab.exit_pos.x, 0.0, cab.exit_pos.z, 90.0)
	await I.call("activate", "dehors.hide_cabane")
	check(P.get("hidden") == true, "hidden in the playhouse")
	check(await _until(func() -> bool: return H.get("state") == "listen", 60 * 20), "she heard the door of the playhouse and comes")
	check(_flat(H.get("pos"), cab.exit_pos) < 3.0, "she stands in front of it (%.1f m)" % _flat(H.get("pos"), cab.exit_pos))
	await _f(60 * 9)
	check(String(G.get(&"state")) == "playing" and P.get("hidden") == true, "and does not find the player")
	await _her_at(140.0, 6.0)
	await I.call("activate", "dehors.exit_cabane")
	check(P.get("hidden") != true, "out of the playhouse again")
	# ---------------------------------------------------------------- the greenhouse: four pots, a key
	await _tp(127.0, 0.0, 14.2, 180.0)
	check(String(P.get("surface")) == "concrete", "paving in the greenhouse (%s)" % P.get("surface"))
	await I.call("activate", "dehors.pot_0")
	check(not await I.call("activate", "dehors.key_shed"), "no key to take before the blue pot is lifted")
	await I.call("activate", "dehors.pot_%d" % L.POT_KEY)
	check(await I.call("activate", "dehors.key_shed") and D.flags.shed_key == true and int(D.get("stage")) == 2, "the shed key, under the blue pot: stage 2")
	await _f(90)
	check((D.get("_nodes").hands as Node3D).visible, "two hand prints on the glass")
	# ---------------------------------------------------------------- the shed
	await _her_at(110.0, 4.0)
	await _tp(140.05, 0.0, -11.2, 0.0)
	await I.call("activate", "dehors.shed_door")
	check(D.flags.shed_open == true, "the shed is unlocked")
	await _f(150)
	Input.action_press("move_forward")
	await _f(80)
	Input.action_release("move_forward")
	await _f(10)
	check(L.in_box(L.SHED, _pp()) and String(P.get("surface")) == "wood", "walked into the shed (%s)" % str(_pp()))
	check(await I.call("activate", "dehors.key_cave") and int(D.get("stage")) == 3, "the cellar key: stage 3")
	check(await I.call("activate", "dehors.battery_0") and int((G.get(&"inventory") as Node).call("count", "battery")) == 1, "a spare battery from the bench")
	await _her_at(134.0, -8.0)
	await I.call("activate", "dehors.radio")
	check(D.get("_radio_on") == true, "the radio plays")
	await _tp(120.0, 0.0, 2.0)
	check(await _until(func() -> bool: return D.get("_radio_on") == false, 60 * 30), "she goes into the shed and turns it off")
	check(L.in_box(L.SHED, H.get("pos"), 0.6), "she stands in the shed (%s)" % str(H.get("pos")))
	# ---------------------------------------------------------------- the cellar
	await _her_at(142.0, 9.0)
	await _tp(115.4, 0.0, -13.1, 90.0)
	await I.call("activate", "dehors.trap")
	check(D.flags.cave_unlocked == true and D.flags.cave_open != true, "the padlock is off")
	await I.call("activate", "dehors.trap")
	check(D.flags.cave_open == true and int(D.get("stage")) == 4, "the cellar doors are open: stage 4")
	await _f(150)
	Input.action_press("move_forward")
	await _f(330)
	Input.action_release("move_forward")
	await _f(10)
	check(_pp().y < -2.3 and _pp().x < 111.6, "walked down the steps into the cellar (%s)" % str(_pp()))
	check(String(P.get("surface")) == "concrete", "stone underfoot (%s)" % P.get("surface"))
	await _tp(106.6, -2.5, -12.5, 90.0)
	check(await I.call("activate", "dehors.cutters") and D.flags.cutters == true and int(D.get("stage")) == 5, "the bolt cutters: stage 5")
	check(await _until(func() -> bool: return D.get("_shut_in") == true, 60 * 5), "the doors fall shut over the steps")
	check(H.get("late") == true and H.get("state") in ["seek", "listen"], "she heard it and comes")
	# she walks on the lawn above: that is not a catch
	H.set("pos", Vector3(_pp().x, 0.0, _pp().z))
	await _f(60)
	check(String(G.get(&"state")) == "playing", "she stands on the lawn right above the player: nothing happens")
	await _her_at(140.0, 8.0)
	check(await I.call("activate", "dehors.trap_in") and D.get("_shut_in") == false, "the doors pushed open from below")
	# ---------------------------------------------------------------- caught
	await _f(120)
	await _tp(127.0, 0.0, 2.0)
	await _her_at(124.5, 2.0)
	EV.emit_signal("noise", _pp(), 0.5, "test")
	t0 = Time.get_ticks_msec()
	while String(G.get(&"state")) == "playing" and Time.get_ticks_msec() - t0 < 30000: await process_frame
	check(String(G.get(&"state")) != "playing", "she walks into the player: caught")
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
	check(_flat(_pp(), L.START) < 0.4 and absf(_pp().y - float(L.PORCH.y)) < 0.08, "the player is back on the porch")
	check(D.flags.cutters == true and int(D.get("stage")) == 5 and H.get("state") == "away", "what was done stays done; she is back inside")
	await _tp(135.0, 0.0, 12.0)
	check(await _until(func() -> bool: return D.get("_her_out") == true, 60 * 25), "and she comes out again")
	# ---------------------------------------------------------------- the gate
	await _her_at(110.0, -4.0)
	await _tp(144.6, 0.0, 8.5)
	await I.call("activate", "dehors.gate")
	check(D.flags.chain_cut == true and int(D.get("stage")) == 6, "the chain is cut: stage 6")
	check(H.get("lantern_on") == false and H.get("state") == "seek", "her lantern goes out and she comes")
	I.call("activate", "dehors.gate")
	t0 = Time.get_ticks_msec()
	while String(G.get(&"state")) == "playing" and Time.get_ticks_msec() - t0 < 20000: await process_frame
	check(String(G.get(&"state")) == "won" and int(D.get("stage")) == 7, "the gate opens: won (state %s)" % G.get(&"state"))
	_finish()

func _finish() -> void:
	print("[dehors] %d checks, %d failed" % [_checks, _fails.size()])
	print("DEHORS TEST OK" if _fails.is_empty() else "DEHORS TEST FAILED: %s" % str(_fails))
	quit(0 if _fails.is_empty() else 1)
