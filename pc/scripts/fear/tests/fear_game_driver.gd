## Driver of test_fear_game.gd (loaded at runtime so it can use the autoloads).
extends Node

const FearModule := preload("res://scripts/fear/fear_director.gd")
const Scares := preload("res://scripts/fear/fear_scares.gd")
const Buses := preload("res://scripts/audio/buses.gd")

var _log = null
var fails: Array[String] = []
var checks := 0
var fear = null
var main: Node = null


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("[fear-game] ok   ", what)
	else:
		fails.append(what)
		print("[fear-game] FAIL ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(s: float) -> void:
	await get_tree().create_timer(s, false).timeout


## Player feet at `feet`, camera aimed at `target` (or yaw/pitch when target is null).
func _aim(feet: Vector3, target: Variant, yaw := 0.0, pitch := 0.0) -> void:
	var pl = Game.player
	if target is Vector3:
		var eye := feet + Vector3(0, 1.62, 0)
		var to: Vector3 = target - eye
		yaw = atan2(-to.x, -to.z)
		pitch = atan2(to.y, Vector2(to.x, to.z).length())
	pl.teleport(feet + Vector3(0, 0.02, 0), yaw, pitch)
	await _frames(3)


func _ent() -> Node:
	return Game.entity


func run(log) -> void:
	_log = log
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	var t := 0
	while Game.state != "playing" and t < 3600:
		await get_tree().process_frame
		t += 1
	check(Game.state == "playing", "game reached 'playing' (autostart)")
	# ---- wiring, exactly as main.gd will do it (after puzzles.setup())
	fear = FearModule.new()
	fear.name = "FearDirector"
	main.add_child(fear)
	fear.setup()
	fear.set("_forced", [])
	check(fear.enabled and fear.level == "extreme", "director ready (level %s)" % fear.level)
	check(Game.puzzles.get("ambient_scares") == false, "puzzles' ambient scares handed over")
	check(Game.garderie == null or Game.garderie.get("ambient_scares") == false, "garderie's ambient scares handed over")
	check(Audio.get("heartbeat_external") == true, "audio heartbeat loops handed over")
	check(Buses.find_effect_index("SFX", "fear_lowpass") >= 0 and Buses.is_valid(), "muffle / silence effects on the buses, graph valid")
	var ent := _ent()
	check(ent.has_method("glimpse") and ent.state == "dormant", "entity glimpse hook present, she sleeps")
	ent.set("_patrol_t", 9999.0)        # no patrol during the test
	Game.puzzles.set("stage_time", -100000.0)   # no automatic blowout in the middle of the checks
	await _secs(1.0)

	# ---------------------------------------------------------------- glimpse: top of the stairs
	var landing_head: Vector3 = Scares.LANDING_FEET + Vector3(0, 1.62, 0)
	var clear: Array = []
	for x in [-2.45, -2.2, -1.9, -1.6, -1.2, -0.8, -0.3]:
		for z in [2.5, 2.2, 1.9, 1.6, 1.3, 0.9]:
			var eye := Vector3(x, 1.62, z)
			if eye.distance_to(landing_head) > 3.5 and not Game.world.line_blocked(eye, landing_head):
				clear.append(Vector3(x, 0.0, z))
	print("[fear-game] stairs-top line of sight from %d / 42 basement spots: %s" % [clear.size(), str(clear.slice(0, 8))])
	check(clear.size() > 0, "the landing is visible from part of the basement (stairs glimpse can happen)")
	if clear.size() > 0:
		var spot: Vector3 = clear[0]
		await _aim(spot, null, PI, 0.0)          # back to the stairs
		await _secs(0.3)
		var cx: Dictionary = fear.c.duplicate()
		cx["stage"] = "code"
		cx["stage_i"] = 3
		var w: float = fear.scares.weight("glimpse_stairs", cx)
		check(w > 0.0, "glimpse_stairs eligible (code stage) when the landing is behind the player (w %.2f)" % w)
		check(fear.scares.weight("glimpse_stairs", fear.c) == 0.0, "but not during the intro")
		check(fear.force("glimpse_stairs"), "glimpse_stairs fired")
		await _secs(1.3)
		check(ent.get("glimpsing") == true and ent.root.visible and ent.state == "dormant", "she stands on the landing (visible, still 'dormant')")
		check(ent.global_position.distance_to(Scares.LANDING_FEET) < 0.3, "at the top of the stairs (%s)" % str(ent.global_position))
		await _aim(spot, landing_head)
		await _secs(2.2)
		var g: Dictionary = fear.glimpse.history[-1] if fear.glimpse.history.size() > 0 else {}
		check(not fear.glimpse.active and g.get("seen", false), "seen, then gone (%s)" % str(g))
		check(ent.get("glimpsing") == false and not ent.root.visible and ent.state == "dormant", "she is back home, invisible, asleep")
		check(ent.global_position.distance_to(Vector3(-3.0, 2.75, -3.6)) < 0.5, "home position restored")

	# ---------------------------------------------------------------- glimpse: dark doorway found by the torch
	Game.world.set_power(false)
	Game.player.give_flashlight()
	Game.player.set_flashlight_on(true)
	var spot2 := Vector3.INF
	var from2 := Vector3.ZERO
	for pos in [Vector3(-0.6, 0, 1.4), Vector3(0.3, 0, 0.0), Vector3(1.0, 0, 1.6), Vector3(-1.2, 0, -1.0)]:
		for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
			await _aim(pos, null, yaw, 0.0)
			await _frames(2)
			spot2 = fear.scares.dark_spot(fear.c)
			if spot2 != Vector3.INF:
				from2 = pos
				break
		if spot2 != Vector3.INF:
			break
	print("[fear-game] dark spot: ", spot2, " from ", from2)
	if spot2 != Vector3.INF:
		check(fear.force("glimpse_dark"), "glimpse_dark fired")
		await _secs(0.4)
		check(ent.get("glimpsing") == true, "she stands in the dark")
		await _aim(from2, spot2 + Vector3(0, 1.3, 0))
		await _secs(1.6)
		var g2: Dictionary = fear.glimpse.history[-1]
		check(g2.kind == "dark" and g2.seen and (g2.reason == "torch" or g2.reason == "blink"), "the torch finds her, she is gone (%s)" % str(g2))
	else:
		check(false, "a dark spot exists for glimpse_dark")
	Game.world.set_power(true)
	await _secs(0.5)

	# ---------------------------------------------------------------- glimpse: outside the closet louvers
	var spots: Array = Game.world.get("hide_spots")
	var closet: Dictionary = spots[0] if spots.size() > 0 else {}
	if not closet.is_empty():
		await Game.player.enter_hide(closet)
		await _secs(0.5)
		check(Game.player.hidden, "hidden in the closet")
		check(fear.force("glimpse_louvers"), "glimpse_louvers fired")
		await _secs(2.3)
		check(ent.get("glimpsing") == true and ent.root.visible, "she stands outside the slats")
		await _secs(3.0)
		var g3: Dictionary = fear.glimpse.history[-1]
		check(g3.kind == "louvers" and g3.seen and not fear.glimpse.active, "seen through the louvers, gone after a blink (%s)" % str(g3))
		check(ent.state == "dormant", "her AI never left 'dormant'")
		await Game.player.exit_hide()
		await _secs(0.4)

	# ---------------------------------------------------------------- glimpse: garderie corridor
	if Game.garderie != null:
		var ch: Vector3 = Scares.CORRIDOR_FEET + Vector3(0, 1.62, 0)
		var cc: Array = []
		for x in [-3.3, -2.9, -2.5, -4.2, -4.8, -5.4, -6.0]:
			for z in [1.9, 2.1, 2.3]:
				if not Game.world.line_blocked(Vector3(x, 1.62, z), ch):
					cc.append(Vector3(x, 0, z))
		print("[fear-game] garderie corridor end visible from %d / 21 spots (doorway, corridor): %s" % [cc.size(), str(cc.slice(0, 5))])
		if cc.size() > 0:
			await _aim(cc[0], null, -PI * 0.5, 0.0)          # facing east, back to the corridor end
			check(fear.force("glimpse_corridor"), "glimpse_corridor fired")
			await _secs(1.2)
			check(ent.get("glimpsing") == true, "she stands at the end of the corridor")
			await _aim(cc[0], ch)
			await _secs(1.8)
			var g4: Dictionary = fear.glimpse.history[-1]
			check(g4.kind == "corridor" and g4.seen, "seen at the end of the corridor (%s)" % str(g4))
			check(is_equal_approx(float(Game.garderie.get("light_scale")), 1.0), "garderie lights restored")
		else:
			print("[fear-game] (the garderie door blocks the corridor sight line: glimpse_corridor only from inside)")

	# ---------------------------------------------------------------- physics fake-outs
	await _aim(Vector3(1.4, 0, -0.6), null, PI * 0.5, 0.0)     # shelves / dresser behind-left
	await _secs(0.3)
	var sh: Array = fear.scares.shelf_spot(fear.c)
	check(not sh.is_empty(), "a furniture top to knock a box off (%s)" % str(sh))
	check(fear.force("fake_shelf"), "fake_shelf fired")
	await _secs(1.6)
	var box: Node = main.find_child("FearFallingBox", true, false)
	check(box != null, "the box spawned")
	var y0: float = box.global_position.y if box else 0.0
	await _secs(2.0)
	var falls: Array = fear.get("_props").filter(func(p): return p.kind == "fall")
	check(falls.size() == 1 and falls[0].done, "it fell and hit the floor (box y %.2f -> %.2f)" % [y0, box.global_position.y if is_instance_valid(box) else -1.0])
	check(box == null or box.global_position.y < 0.5, "the box lies on the floor")
	await _secs(1.0)

	await _aim(Vector3(-1.6, 0, 2.2), Vector3(-3.0, 1.2, 0.0))
	await _secs(0.3)
	check(fear.force("fake_ball"), "fake_ball fired")
	await _secs(1.4)
	var ball: Node = main.find_child("FearBall", true, false)
	check(ball != null, "the ball spawned on the landing")
	await _secs(4.0)
	if ball != null:
		print("[fear-game] ball after 4 s: ", ball.global_position)
		check(ball.global_position.y < 0.6 and ball.global_position.z > 0.8, "it bounced down the stairs into the basement (%s)" % str(ball.global_position))
	await _secs(0.5)

	# ---------------------------------------------------------------- the house
	Game.puzzles.flags["rocked"] = true
	for id in ["door_handle", "rocking", "crt_static", "bulb_pop", "ceiling_run", "hum_walls", "giggle", "knock_wall",
			"knock_ceiling", "ceiling_steps", "scratch_wall", "whisper_back", "creak", "distant", "flicker", "window_tap",
			"rumble_swell"]:
		await _aim(Vector3(0.6, 0, 0.4), null, 0.4, 0.0)
		await _frames(2)
		var ok: bool = fear.force(id)
		check(ok, "%s fired" % id)
		await _secs(1.2 if id != "ceiling_run" else 5.0)
		check(ent.state == "dormant", "%s left her asleep" % id)
	await _secs(4.0)
	check(Game.puzzles.stage == "intro" or Game.puzzles.stage == "dark", "scares never advanced the scenario (stage %s)" % Game.puzzles.stage)

	# ---------------------------------------------------------------- the real jumpscare -> caught -> night 2
	await _aim(Vector3(0.25, 0, 1.0), null, 0.0, 0.0)
	var night0: int = Game.night
	ent.call("debug_jumpscare")
	await _frames(12)
	check(Engine.time_scale < 0.99, "slow motion as her face fills the screen (%.2f)" % Engine.time_scale)
	await _secs(1.2)
	check(is_equal_approx(Engine.time_scale, 1.0), "time scale back to 1")
	check(fear.mix.muffle > 0.3, "hearing muffled (%.2f)" % fear.mix.muffle)
	var tw := 0
	while Game.state != "caught" and tw < 300:
		await get_tree().process_frame
		tw += 1
	check(Game.state == "caught", "caught")
	await _secs(1.5)
	check(fear.mix.silence > 0.5, "ringing silence through the caught screen (%.2f)" % fear.mix.silence)
	var tw2 := 0
	while Game.ui.get("_end") is Dictionary and (Game.ui.get("_end") as Dictionary).is_empty() and tw2 < 300:
		await get_tree().process_frame
		tw2 += 1
	Game.ui.call("end_finish")
	var tw3 := 0
	while Game.state != "playing" and tw3 < 600:
		await get_tree().process_frame
		tw3 += 1
	check(Game.state == "playing" and Game.night == night0 + 1, "night %d begins" % Game.night)
	await _secs(4.0)
	check(fear.mix.silence < 0.3, "the silence lifts (%.2f)" % fear.mix.silence)
	check(fear.pacer.phase == "relief", "relief after the catch (%s)" % fear.pacer.phase)

	# ---------------------------------------------------------------- a minute of free play (pacing live)
	ent.set("_patrol_t", 9999.0)
	var n0: int = fear.events.size()
	for i in 30:
		await _aim(Vector3(0.25 + sin(i * 0.4) * 1.5, 0, 0.5 + cos(i * 0.3) * 1.2), null, i * 0.7, 0.0)
		await _secs(2.0)
	print("[fear-game] free play: %d scares in 60 s, BPM %.1f, phase %s" % [fear.events.size() - n0, fear.bpm(), fear.pacer.phase])

	# ---------------------------------------------------------------- errors
	var errs: Array[String] = []
	_log.mutex.lock()
	errs = _log.errors.duplicate()
	_log.mutex.unlock()
	var mine := errs.filter(func(e): return e.contains("/fear/") or e.contains("gardienne.gd") or e.contains("player.gd") or e.contains("audio_manager") or e.contains("puzzles.gd") or e.contains("garderie.gd"))
	for e in errs:
		print("[fear-game] logged error: ", e)
	check(mine.is_empty(), "no error from the fear module or the hooked modules (%d logged in total)" % errs.size())
	print("[fear-game] %d checks, %d failed" % [checks, fails.size()])
	for f in fails:
		print("[fear-game]   FAILED: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)
