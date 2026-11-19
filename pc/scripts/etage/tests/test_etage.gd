## Chapter 2 (l'étage), played by script in the real game scene, from the top of the basement stairs to the front door.
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/etage/tests/test_etage.gd -- --autostart --mode=etage --no-garderie
## Checks, in the order a player meets them: the level starts (house hidden, player on the floor, every room where
## the plan says); the front door is locked; her door gives and is pulled shut; the box on the mantel refuses a
## wrong code (and a sheet comes closer); the kitchen (the calendar's digit, the figure found on another chair, the
## fridge and its light, the key under the butter dish, the drawers and the mousetrap, the dresser pushed off the
## pantry door); the pantry (the fuse, the door that shuts); the stairwell (the board without / with its fuse, the
## plank that falls, the figure gone from the top of the stairs); the bathroom (cold hot water without the fuse, the
## pipes, the curtain, the mirror misting over and its digit, what stands in the bath afterwards); her bedroom (the
## key, the pillow's digit, the humming in the hallway); the box opening through the padlock view; the key waking
## the walker; the walker standing still while looked at, coming closer when not, opening a shut door on its way,
## catching; the reset that keeps what was found; the front door -> the game is won.
extends SceneTree

const L := preload("res://scripts/etage/etage_layout.gd")

var _fails: Array[String] = []
var _checks := 0
var G: Node
var E
var P: Node
var I: Node

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		print("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _f(n: int) -> void:
	for i in n: await process_frame

func _look_at(target: Vector3) -> void:
	var d: Vector3 = target - (P as Node3D).global_position
	P.set("yaw", atan2(-d.x, -d.z))
	P.set("pitch", 0.0)

func _go(pos: Vector3, yaw_deg: float) -> void:
	P.call("teleport", pos, deg_to_rad(yaw_deg), 0.0)
	await _f(8)

func _enabled(id: String) -> bool:
	var e: Dictionary = (I.get("entries") as Dictionary).get(id, {})
	var fn = e.get("enabled")
	return not e.is_empty() and (not (fn is Callable) or bool((fn as Callable).call()))

## What the interaction ray picks when the player stands at `from` and looks at `target` (the real camera ray).
func _aimed(from: Vector3, target: Vector3) -> String:
	P.call("teleport", from, 0.0, 0.0)
	await _f(6)
	var cam: Camera3D = G.get(&"camera")
	var d: Vector3 = target - cam.global_position
	P.set("yaw", atan2(-d.x, -d.z))
	P.set("pitch", atan2(d.y, Vector2(d.x, d.z).length()))
	await _f(10)
	var cur = I.get("current")
	return String((cur as Dictionary).get("id", "")) if cur is Dictionary else ""

## Walks toward (x, z) with the forward key; true when the player got there.
func _walk(x: float, z: float, max_frames := 420) -> bool:
	Input.action_press("move_forward")
	var ok := false
	for i in max_frames:
		var p: Vector3 = (P as Node3D).global_position
		var dx := x - p.x
		var dz := z - p.z
		if dx * dx + dz * dz < 0.09:
			ok = true
			break
		P.set("yaw", atan2(-dx, -dz))
		await process_frame
	Input.action_release("move_forward")
	await _f(4)
	return ok

func _door_a(id: String) -> float:
	return float(((E.get("_doors") as Dictionary)[id] as Dictionary).a)

func _fig(id: String) -> Dictionary:
	for f in E.get("_figs"):
		if String((f as Dictionary).get("id", "")) == id:
			return f
	return {}

## Opens the padlock view on the box and enters `digits` in it.
func _dial(digits: String) -> void:
	var ui: Node = G.get(&"ui")
	I.call("activate", "etage.box", true)
	await _f(20)
	var kv = ui.get("keypad_view")
	check(kv != null and kv.get("is_open") == true and int(kv.get("n")) == 3, "the padlock view is open with three wheels")
	ui.call("_kp_finish", digits)
	await _f(20)
	# (the UI keeps the game "in a modal" for 0.2 s of real time after one closes; headless frames go much faster)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 260: await process_frame

func _press_enter_until_playing() -> void:
	var t0 := Time.get_ticks_msec()
	while String(G.get(&"state")) != "playing" and Time.get_ticks_msec() - t0 < 30000:
		# the "caught" card waits for a key
		var ev := InputEventKey.new(); ev.keycode = KEY_ENTER; ev.physical_keycode = KEY_ENTER; ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		var ev2 := InputEventKey.new(); ev2.keycode = KEY_ENTER; ev2.physical_keycode = KEY_ENTER; ev2.pressed = false
		Input.parse_input_event(ev2)
		await process_frame

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	G = root.get_node("Game")
	var t0 := Time.get_ticks_msec()
	while String(G.get(&"state")) != "playing" and Time.get_ticks_msec() - t0 < 240000: await process_frame
	E = G.get(&"etage")
	P = G.get(&"player")
	I = G.get(&"interaction")
	check(E != null and E.get("built") == true, "the level is built")
	if E == null:
		_finish()
		return
	await _f(20)
	print("[etage] stats ", E.get("stats"))
	var code: Array = E.get("code")
	var right := "%d%d%d" % [code[0], code[1], code[2]]
	var wrong := "%d%d%d" % [code[0], code[1], (int(code[2]) % 9) + 1]
	print("[etage] code ", right)

	# ---------------------------------------------------------------- the start
	check(String(G.get(&"mode")) == "etage" and E.get("active") == true and (E as Node3D).visible, "chapter 2 is running")
	check(not (G.get(&"world") as Node3D).visible, "the house is hidden")
	check((P as Node3D).global_position.distance_to(L.START) < 0.3 and absf((P as Node3D).global_position.y) < 0.05, "the player stands at the top of the stairs, on the floor")
	check((E.get("stats") as Dictionary).get("missing_textures", ["?"]).is_empty(), "no texture missing: %s" % str((E.get("stats") as Dictionary).get("missing_textures")))
	var ids := ["etage.front", "etage.chambre", "etage.box", "etage.key", "etage.card", "etage.letter", "etage.bed_note", "etage.table_note", "etage.bath_note",
		"etage.stair_note", "etage.list_note", "etage.calendar", "etage.fridge", "etage.butter", "etage.drawer0", "etage.drawer1", "etage.drawer2", "etage.buffet",
		"etage.cellier", "etage.fuse", "etage.esc_door", "etage.fusebox", "etage.bain_door", "etage.tap_hot", "etage.tap_cold", "etage.mirror", "etage.curtain", "etage.pillow"]
	var missing := ids.filter(func(id): return not (I.get("entries") as Dictionary).has(id))
	check(missing.is_empty(), "every interaction of the chapter is registered (missing: %s)" % str(missing))
	check(code.all(func(d): return int(d) >= 1 and int(d) <= 9), "the box has three digits (%s)" % right)
	var rooms := {"cuisine": Vector3(61.0, 0, 2.0), "cellier": Vector3(57.0, 0, 3.7), "bain": Vector3(54.0, 0, 2.5), "escalier": Vector3(66.3, 0, -3.0),
		"salon": Vector3(61.0, 0, -4.0), "chambre": Vector3(54.0, 0, -3.0), "closet": Vector3(57.4, 0, 1.5), "hall": Vector3(60.0, 0, 0.0)}
	check(rooms.keys().all(func(r): return L.room_of(rooms[r]) == r and L.contains(rooms[r])), "every room is where the plan says")
	check(L.surface_at(rooms.bain) == "concrete" and L.surface_at(rooms.cuisine) == "wood" and L.surface_at(Vector3(60, 0, 0)) == "carpet", "tiles in the bathroom, boards in the kitchen, the runner in the hallway")
	check((E.get("_late") as Array).size() >= 9 and (E.get("_late") as Array).all(func(e): return not (e[0] as Node3D).visible), "what appears later is hidden at the start")
	# a walk down the hallway: wooden floor, the body stays on it
	Input.action_press("move_forward")
	await _f(150)
	Input.action_release("move_forward")
	var pp: Vector3 = (P as Node3D).global_position
	check(pp.x > L.START.x + 2.5 and absf(pp.y) < 0.05 and absf(pp.z) < 0.7, "walked east along the hallway (%s)" % str(pp))
	check(String(P.get("surface")) in ["wood", "carpet"], "steps on wood or on the runner (%s)" % P.get("surface"))

	# ---------------------------------------------------------------- the front door, her door, the box
	await _go(Vector3(67.0, 0.0, 0.0), -90.0)
	await I.call("activate", "etage.front", true)
	check(int(E.get("stage")) == 1, "front door locked: stage 1")
	await _go(Vector3(55.04, 0.0, -0.2), 0.0)
	I.call("activate", "etage.chambre", true)
	await _f(60)
	check(_door_a("chambre") > 0.05, "the bedroom door gives a little")
	await _f(140)
	check(_door_a("chambre") < 0.01, "and is shut again")
	await _go(Vector3(64.4, 0.0, -4.3), 0.0)
	_look_at(L.MANTEL)
	await _f(6)
	check(not _enabled("etage.key") and _enabled("etage.box"), "the key is shut in the box")
	check(await _aimed(Vector3(64.35, 0, -4.5), E.get("_fx").box_at + Vector3(-0.03, 0.04, 0)) == "etage.box", "looking at the box on the mantel targets it")
	await _go(Vector3(64.4, 0.0, -4.3), 0.0)
	_look_at(L.MANTEL)
	await _f(6)
	await _dial(wrong)
	check(E.get("_box_seen") == true and E.get("_box_open") == false and int(E.get("_box_tries")) == 1, "a wrong code does not open it")
	check((E.get("_figs") as Array).any(func(f): return f.room == "salon" and f.at_alt), "and a sheet has come closer behind the player")
	await I.call("activate", "etage.key", true)
	check(int(E.get("stage")) == 1, "the key cannot be taken through the lid")

	# ---------------------------------------------------------------- la cuisine
	await _go(Vector3(60.35, 0.0, 1.5), 180.0)
	var seated: Node3D = E.get("_seated")
	check(seated.visible and seated.position.distance_to(L.CHAIRS[0][0]) < 0.01, "someone sits at the kitchen table, facing the doorway")
	await _go(Vector3(59.3, 0.0, 2.15), 90.0)                      # at the calendar, back to the table
	await I.call("activate", "etage.calendar", true)
	check((E.get("found") as Array)[1] == true, "the calendar gives the second digit")
	var ring: Node3D = E.call("_region", "et_cal_ring")
	var day := int(code[1])
	var want_z: float = L.CALENDAR.z - (float(L.CAL_GRID[0]) + (float(day % 7) + 0.5) * float(L.CAL_GRID[2]) - 0.5) * L.CAL_SIZE.x
	check(absf(ring.position.z - want_z) < 0.001 and absf(ring.position.y - L.CALENDAR.y) < L.CAL_SIZE.y * 0.5, "the red ring is on day %d" % day)
	await _f(70)
	check(int(E.get("_seat")) == 1 and seated.position.distance_to(L.CHAIRS[1][0]) < 0.01, "unseen, the figure has changed chair")
	_look_at(seated.position)
	E.set("_seat_want", 2)
	await _f(90)
	check(int(E.get("_seat")) == 1, "and does not move while looked at")
	E.set("_seat_want", 1)
	await _go(Vector3(61.8, 0.0, 1.9), -90.0)
	var fl: Light3D = E.get("_fx").fridge.light
	check(not fl.visible and not _enabled("etage.butter"), "the fridge is shut, its light off")
	var got: String = await _aimed(Vector3(61.8, 0, 1.6), Vector3(62.6, 1.0, 1.5))
	check(got == "etage.fridge", "looking at the fridge door targets it (%s)" % got)
	await I.call("activate", "etage.fridge", true)
	await _f(60)
	check(await _aimed(Vector3(61.8, 0, 1.7), E.get("_fx").butter + Vector3(0, 0.03, 0)) == "etage.butter", "the butter dish can be reached inside the open fridge")
	check(E.get("_fridge_open") == true and fl.visible and float((E.get("_movers") as Dictionary).fridge.a) > 0.95, "the fridge opens and lights the kitchen")
	await I.call("activate", "etage.butter", false)
	check(E.get("_has_ckey") == true and not (E.call("_region", "et_ckey") as Node3D).visible, "the bedroom key was under the butter dish's cover")
	I.call("activate", "etage.fridge", true)
	await _f(60)
	check(not fl.visible and E.get("_fridge_open") == false, "shut again: the kitchen is dark")
	await _go(Vector3(59.5, 0.0, 3.9), 180.0)
	check(not _enabled("etage.list_note"), "the shopping list is in a shut drawer")
	await I.call("activate", "etage.drawer0", true)
	await _f(40)
	check(_enabled("etage.list_note") and (E.call("_region", "et_drawer_0") as Node3D).position.z < float(L.COUNTER.z0) - 0.25, "the drawer slides out, the list can be read")
	var fear0 := float(E.get("fear"))
	await I.call("activate", "etage.drawer1", true)
	await _f(40)
	check(E.get("_trap_done") == true and float(E.get("fear")) > fear0 + 0.15, "the mousetrap in the second drawer goes off (fear %.2f -> %.2f)" % [fear0, float(E.get("fear"))])
	check(not _enabled("etage.cellier") and not E.call("_walkable", Vector3(58.2, 0, 3.7)), "the dresser stands across the pantry door")
	var buffet: Node3D = E.call("_region", "et_buffet")
	var bz := buffet.position.z
	await _go(Vector3(59.3, 0.0, 3.7), 90.0)
	await I.call("activate", "etage.buffet", true)
	check(not _enabled("etage.buffet") and not _enabled("etage.cellier"), "it scrapes along the wall")
	await _f(60 * 3)
	check(E.get("_buffet_pushed") == true and absf(buffet.position.z - bz - L.BUFFET_PUSH) < 0.02, "the dresser is pushed %.2f m along the wall" % (buffet.position.z - bz))
	check(_enabled("etage.cellier") and E.call("_walkable", Vector3(58.2, 0, 3.7)), "the pantry door is free")
	await I.call("activate", "etage.cellier", false)
	await _f(150)
	check(_door_a("cellier") > 0.95, "the pantry door opens")

	# ---------------------------------------------------------------- le garde-manger
	check(await _aimed(Vector3(57.3, 0, 3.65), L.FUSE_TIN) == "etage.fuse", "the tin of fuses can be reached on its shelf")
	await _go(Vector3(57.0, 0.0, 3.7), 90.0)
	await I.call("activate", "etage.fuse", false)
	check(E.get("_has_fuse") == true and not (E.call("_region", "et_fuse_item") as Node3D).visible, "a fuse taken from the tin")
	await _f(60 * 3)
	check(_door_a("cellier") < 0.05 and int(E.get("_seat_want")) == 2, "the pantry door has shut on the player")
	check(_enabled("etage.cellier"), "and can be opened again")
	await I.call("activate", "etage.cellier", false)
	await _f(150)
	check(_door_a("cellier") > 0.95, "it opens")

	# ---------------------------------------------------------------- la salle de bain, before the fuse
	check(not _enabled("etage.mirror") and _door_a("bain") < 0.01, "the bathroom door is shut")
	await I.call("activate", "etage.bain_door", false)
	await _f(120)
	check(_door_a("bain") > 0.95, "the bathroom door opens")
	check(await _aimed(Vector3(53.3, 0, 2.1), E.get("_fx").tap_hot) == "etage.tap_hot" and await _aimed(Vector3(53.3, 0, 2.1), E.get("_fx").tap_cold) == "etage.tap_cold",
		"each tap can be picked on the basin")
	await _go(Vector3(53.3, 0.0, 2.1), 90.0)                       # at the basin, facing the mirror
	await I.call("activate", "etage.tap_hot", true)
	await _f(200)
	check(E.get("_hot") == true and E.get("_hot_tried") == true and float(E.get("_fog")) < 0.001, "without the fuse the hot tap runs cold: no steam")
	check((E.call("_region", "et_stream_hot") as Node3D).visible, "water runs from the tap")
	await I.call("activate", "etage.tap_hot", true)
	check(E.get("_hot") == false and not (E.call("_region", "et_stream_hot") as Node3D).visible, "the tap is shut")
	await I.call("activate", "etage.tap_cold", true)
	check(E.get("_cold_knock") == true, "the pipes answer the cold water")
	await I.call("activate", "etage.tap_cold", true)
	await I.call("activate", "etage.curtain", true)
	await _f(80)
	var curtain: Node3D = E.call("_region", "et_curtain")
	check(E.get("_curtain_open") == true and curtain.scale.x < 0.25, "the bath curtain is pulled aside")
	await I.call("activate", "etage.curtain", true)
	await _f(80)
	check(E.get("_curtain_open") == false and curtain.scale.x > 0.99, "and drawn again")

	# ---------------------------------------------------------------- la cage d'escalier
	await _go(Vector3(67.13, 0.0, -0.3), 0.0)
	await I.call("activate", "etage.esc_door", false)
	await _f(120)
	check(_door_a("esc") > 0.95, "the stairwell door opens")
	var sf := _fig("stairs")
	check(sf.on == true and (sf.node as Node3D).visible and (sf.node as Node3D).position.y > 2.0, "someone stands at the top of the boarded stairs")
	await _go(Vector3(67.3, 0.0, -1.7), 0.0)
	Input.action_press("move_forward")
	await _f(90)
	Input.action_release("move_forward")
	check((P as Node3D).global_position.z > float(L.STAIR.z_foot) and (P as Node3D).global_position.y < 0.05, "the boards keep the player off the stairs (%s)" % str((P as Node3D).global_position))
	await _go(Vector3(66.5, 0.0, -4.3), 90.0)                      # at the fuse board, back to the stairs
	var had: bool = E.get("_has_fuse")
	E.set("_has_fuse", false)
	await I.call("activate", "etage.fusebox", true)
	check(E.get("_board_seen") == true and E.get("_power") == false, "without a fuse the board only tells which one is missing")
	E.set("_has_fuse", had)
	var lamp: Light3D = E.get("_fx").bain_lamp.light
	check(not lamp.visible, "the bathroom lamp is dead")
	await I.call("activate", "etage.fusebox", true)
	await _f(60 * 3)
	check(E.get("_power") == true and E.get("_has_fuse") == false and (E.call("_region", "et_fuse_in") as Node3D).visible, "the fuse is in the board")
	check(lamp.visible and lamp.light_energy > 0.9, "the bathroom lamp is lit")
	check(E.get("_stair_gone") == true and (E.call("_region", "et_plank_down") as Node3D).visible and not (E.call("_region", "et_plank_up") as Node3D).visible, "a board has fallen off the stairs")
	check(sf.on == false and not (sf.node as Node3D).visible, "and nobody stands at the top any more")

	# ---------------------------------------------------------------- la salle de bain, the mirror
	await _go(Vector3(53.3, 0.0, 2.1), 90.0)
	await I.call("activate", "etage.tap_hot", true)
	await _f(60 * 5)
	check(float(E.get("_fog")) > 0.3 and float(E.get("_fog")) < 0.8 and (E.get("found") as Array)[0] == false, "hot water: the mirror mists over, slowly (%.2f)" % float(E.get("_fog")))
	check((E.get("_fx").steam as GPUParticles3D).emitting and (E.call("_region", "et_mirror_fx") as Node3D).visible, "steam rises from the basin")
	await _f(60 * 8)
	check((E.get("found") as Array)[0] == true, "the digit drawn in the steam is read")
	var dm := E.ctx.mats.mat("digit_fog") as StandardMaterial3D
	check(absf(dm.uv1_offset.x - 0.2 * float(int(code[0]) % 5)) < 0.001 and absf(dm.uv1_offset.y - 0.5 * float(int(code[0]) / 5)) < 0.001 and dm.albedo_color.a > 0.6, "it is the first digit of the box")
	await _f(60)
	var bf := _fig("bath")
	check(E.get("_bath_done") == true and E.get("_curtain_open") == true and bf.on == true and (bf.node as Node3D).visible, "behind the player the curtain is open, something stands in the bath")
	check((E.get("_fx").bain_prints as Array).all(func(d): return d == null or (d as Node3D).visible), "wet footprints lead from the bath")
	await I.call("activate", "etage.tap_hot", true)

	# ---------------------------------------------------------------- sa chambre
	await _go(Vector3(55.04, 0.0, -0.2), 0.0)
	await I.call("activate", "etage.chambre", true)
	check(E.get("_chambre_open") == true and _door_a("chambre") > 0.95 and E.get("_hum") == null, "her key opens her door; the humming has stopped")
	await _go(Vector3(55.0, 0.0, -4.4), 45.0)
	var pillow: Node3D = E.call("_region", "et_pillow")
	var pz := pillow.position.z
	await I.call("activate", "etage.pillow", true)
	await _f(60 * 4)
	check((E.get("found") as Array)[2] == true and pillow.position.z > pz + 0.3, "the third digit is under the pillow")
	check(E.get("_hum_hall") == true and (E.get("_hum_at") as Vector3).z > -0.8, "she hums in the hallway, outside her own door")
	await _go(Vector3(56.5, 0.0, 0.0), 90.0)
	await _f(10)
	check(E.get("_hum_hall") == false, "and stops when the player comes out")

	# ---------------------------------------------------------------- on foot through every doorway of the new rooms
	P.call("teleport", Vector3(55.03, 0.0, 0.0), 0.0, 0.0)
	await _f(8)
	var stuck: Array[String] = []
	for w in [["bain", 55.03, 1.7], ["bain basin", 53.5, 2.1], ["bain", 55.03, 1.6], ["hall", 55.03, 0.0], ["hall", 60.35, 0.0], ["cuisine", 60.35, 1.6], ["cuisine w", 59.05, 3.4],
			["cellier", 57.5, 3.7], ["cuisine w", 58.95, 3.7], ["cuisine", 60.35, 1.5], ["hall", 60.35, 0.0], ["hall", 67.13, 0.0], ["escalier", 67.13, -1.6], ["escalier", 66.3, -2.0], ["escalier fuse", 66.4, -4.3],
			["escalier", 66.3, -2.0], ["escalier", 67.13, -1.5], ["hall", 67.13, 0.0]]:
		if not await _walk(float(w[1]), float(w[2])):
			stuck.append("%s %s" % [w[0], str((P as Node3D).global_position)])
	check(stuck.is_empty(), "walked into and out of the bathroom, the kitchen, the pantry and the stairwell (stuck: %s)" % str(stuck))
	check(absf((P as Node3D).global_position.y) < 0.05, "and stayed on the floor")

	# ---------------------------------------------------------------- the box, the key, the walker
	await _go(Vector3(64.4, 0.0, -4.3), 0.0)
	_look_at(L.MANTEL)
	await _dial(right)
	check(E.get("_box_open") == true and _enabled("etage.key") and not _enabled("etage.box"), "the three digits open the box")
	await _f(60)
	await I.call("activate", "etage.key", false)
	check(int(E.get("stage")) == 2, "key taken: stage 2")
	await _f(60 * 6)
	var W: Dictionary = (E.get("_walkers") as Array)[0]
	var sc: Array = E.ctx.room_fx.sconces
	check(sc.all(func(s): return not (s.light as Light3D).visible), "the sconces are out")
	check(W.awake == true, "the walker is awake")
	var d0 := Vector2(W.pos.x - 64.4, W.pos.z + 4.3).length()
	check(d0 < 4.0 and d0 > 0.9, "it stands behind the player (%.2f m)" % d0)
	check(int(E.get("_seat")) == -1 and not seated.visible, "the chair at the kitchen table is empty")
	# looked at: a statue
	_look_at(W.pos)
	await _f(30)
	var p1: Vector3 = W.pos
	await _f(120)
	check((W.pos as Vector3).distance_to(p1) < 0.001, "it does not move while looked at")
	check(W.revealed == true, "and it has been seen")
	# back turned from a distance: it comes closer, creaking
	await _go(Vector3(57.4, 0.0, -1.8), 90.0)                      # far west of the salon, facing west
	var far: float = Vector2(W.pos.x - 57.4, W.pos.z + 1.8).length()
	await _f(90)
	var near: float = Vector2(W.pos.x - 57.4, W.pos.z + 1.8).length()
	check(near < far - 1.0, "back turned: it came closer (%.2f -> %.2f m)" % [far, near])
	# the player hides in the bathroom behind a shut door, back turned: it comes through the rooms, opens the door
	(E.get("_opened") as Dictionary).erase("bain")
	var bd: Dictionary = (E.get("_doors") as Dictionary).bain
	bd.a = 0.0
	bd.goal = 0.0
	(bd.node as Node3D).rotation.y = float(bd.closed)
	E.call("_door_solid", "bain", true)
	await _go(Vector3(53.2, 0.0, 2.8), 90.0)
	t0 = Time.get_ticks_msec()
	var in_room := false
	while String(G.get(&"state")) == "playing" and Time.get_ticks_msec() - t0 < 60000:
		in_room = in_room or L.room_of(W.pos) == "bain"
		await process_frame
	check(float(bd.goal) > 0.5, "the shut bathroom door has opened before it")
	check(in_room, "it came into the bathroom")
	check(String(G.get(&"state")) != "playing", "it reached the player: caught")
	await _press_enter_until_playing()
	check(String(G.get(&"state")) == "playing", "play goes on after the capture (night %s)" % G.get(&"night"))
	await _f(20)
	check(int(E.get("stage")) == 1 and (P as Node3D).global_position.distance_to(L.START) < 0.4, "the level is reset, the player back at the stairs")
	check(W.awake == false and (W.pos as Vector3).distance_to(L.WALKER[0]) < 0.01, "the walker is back under its sheet")
	check(E.get("_box_open") == true and E.get("_power") == true and (E.get("found") as Array).all(func(x): return x) and _door_a("esc") > 0.95 and _door_a("chambre") > 0.95,
		"what was found and opened is kept")
	check((E.get("_key") as Node3D).visible and _enabled("etage.key") and seated.visible, "the key is back in its box, the figure back at the table")
	# second try: the key, then straight to the door with a head start
	await _go(Vector3(64.4, 0.0, -4.3), 0.0)
	_look_at(L.MANTEL)
	await _f(10)
	await I.call("activate", "etage.key", false)
	check(int(E.get("stage")) == 2, "the key again")
	await _go(Vector3(67.1, 0.0, 0.0), -90.0)
	I.call("activate", "etage.front", true)
	t0 = Time.get_ticks_msec()
	while String(G.get(&"state")) == "playing" and Time.get_ticks_msec() - t0 < 20000: await process_frame
	check(String(G.get(&"state")) == "won", "the door opens with the key: won (state %s)" % G.get(&"state"))
	_finish()

func _finish() -> void:
	print("[etage] %d checks, %d failed" % [_checks, _fails.size()])
	print("ETAGE TEST OK" if _fails.is_empty() else "ETAGE TEST FAILED: %s" % str(_fails))
	quit(0 if _fails.is_empty() else 1)
