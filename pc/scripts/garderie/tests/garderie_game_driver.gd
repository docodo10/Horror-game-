## Driver of test_garderie_game.gd (loaded at runtime so it can use the autoloads).
extends Node

const GL := preload("res://scripts/garderie/garderie_layout.gd")

var _log = null
var _fails: Array[String] = []
var _checks := 0
var _noises: Array = []
var g: Node3D = null

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func run(log) -> void:
	_log = log
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	var t := 0
	while Game.state != "playing" and t < 3600:
		await get_tree().process_frame
		t += 1
	check(Game.state == "playing", "game reached 'playing' (autostart)")
	Events.noise.connect(func(p: Vector3, l: float, s: String) -> void: _noises.append([p, l, s]))
	var t0 := Time.get_ticks_msec()
	g = Garderie.new()
	main.add_child(g)
	await g.build(Game.world)
	print("[game] garderie build ", Time.get_ticks_msec() - t0, " ms ", g.stats)
	var it: Node = Game.interaction
	var pl: Node3D = Game.player
	check(it != null and pl != null, "real interaction + player present")
	if it == null or pl == null:
		_finish()
		return
	for id in ["garderie.door", "garderie.tunnel.hide", "garderie.tunnel.exit", "garderie.slide.wave", "garderie.slide.spiral"]:
		check((it.get("entries") as Dictionary).has(id), "registered with Game.interaction: " + id)
	# door through the interaction system
	await it.call("activate", "garderie.door", true)
	await _frames(80)
	check(g.door.is_open, "door opened through Game.interaction")
	check(_noises.any(func(n): return n[2] == "door"), "door emits a noise")
	# floors: corridor, vestibule, landing, hall, deck L3 (teleport with the area's ground)
	for spot in [[Vector3(-6.0, 0.0, 2.1), 0.0], [Vector3(-14.0, 0.0, 2.1), 0.0], [Vector3(-19.0, 0.0, 2.0), 0.0],
			[Vector3(-24.0, GL.HALL, 3.5), GL.HALL], [Vector3(-33.0, GL.L3, -1.0), GL.L3]]:
		g.teleport_player(spot[0], PI * 0.5)
		await _frames(40)
		check(absf(pl.global_position.y - float(spot[1])) < 0.06, "player stands at y %.2f at %s (y %.3f)" % [spot[1], spot[0], pl.global_position.y])
	# rides
	for id in ["wave", "spiral"]:
		var s: Dictionary = g.ctx.slides[id]
		g.teleport_player(s.top, PI if id == "spiral" else -PI * 0.5)
		await _frames(20)
		_noises.clear()
		var tr := Time.get_ticks_msec()
		await g.ride(id)
		var dur := (Time.get_ticks_msec() - tr) / 1000.0
		await _frames(30)
		var p: Vector3 = pl.global_position
		print("[game] ride %s: %.1f s, player at %s, cam %s" % [id, dur, p, (pl.get("camera") as Camera3D).global_position])
		check(absf(p.y - GL.HALL) < 0.06, "%s ride: player on the hall floor (y %.3f)" % [id, p.y])
		check(pl.get("camera_override") == false and not g.ride_active, "%s ride: camera handed back" % id)
		check(_noises.any(func(n): return n[2] == "slide" and float(n[1]) >= 0.8), "%s ride: landing noise 0.8 for La Gardienne" % id)
		var cam_y: float = (pl.get("camera") as Camera3D).global_position.y
		check(cam_y > GL.HALL + 1.3 and cam_y < GL.HALL + 1.9, "%s ride: camera back at standing eye height (%.2f)" % [id, cam_y])
	# hide in the tunnel through the interaction, then get out
	var H: Dictionary = GL.HIDE
	g.teleport_player(H.exit_pos, -PI * 0.5)
	await _frames(20)
	await it.call("activate", "garderie.tunnel.hide", true)
	await _frames(90)
	check(pl.get("hidden") == true, "hidden in the tunnel")
	var spot_now: Variant = pl.get("hide_spot")
	check(spot_now is Dictionary and (spot_now as Dictionary).get("id") == H.id, "hide spot is the tunnel")
	var cy: float = (pl.get("camera") as Camera3D).global_position.y
	check(absf(cy - float(H.hide_pos.y)) < 0.25, "camera at the hiding eye height (%.2f)" % cy)
	await it.call("activate", "garderie.tunnel.exit", true)
	await _frames(90)
	check(pl.get("hidden") == false, "out of the tunnel")
	check(pl.global_position.distance_to(H.exit_pos) < 0.3, "standing at the tunnel exit (%s)" % pl.global_position)
	# ball pit
	g.teleport_player(Vector3(-27.0, GL.HALL, 6.6), PI * 0.5)
	await _frames(30)
	check(g.in_ball_pit, "ball pit detects the player")
	g.teleport_player(Vector3(-22.0, GL.HALL, 5.0), PI * 0.5)
	await _frames(30)
	check(not g.in_ball_pit, "ball pit releases the player")
	_finish()

func _finish() -> void:
	var mine: Array = []
	for e in _log.errors:
		if String(e).contains("garderie"):
			mine.append(e)
		print("[game] logged error: ", e)
	check(mine.is_empty(), "no error logged by the garderie (%d, %d in total)" % [mine.size(), _log.errors.size()])
	print("[game] %d checks, %d failed" % [_checks, _fails.size()])
	if _fails.is_empty():
		print("GARDERIE GAME TEST OK")
		get_tree().quit(0)
	else:
		print("GARDERIE GAME TEST FAILED: ", _fails)
		get_tree().quit(1)
