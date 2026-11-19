## The chapters chained into one game: winning chapter 2 shows "FIN DU CHAPITRE 2", then the scene is rebuilt and
## chapter 3 starts by itself (no menu); winning chapter 3 shows the real ending.
##   godot --headless --path pc --fixed-fps 60 -s res://scripts/game/tests/test_chain.gd -- --autostart --mode=etage --no-garderie
extends SceneTree

var _fails: Array[String] = []
var _checks := 0
var G: Node

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		print("FAIL: ", what)

func _initialize() -> void:
	_run.call_deferred()

func _until(fn: Callable, seconds := 240.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		if fn.call(): return true
		await process_frame
	return false

func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _fails.size()])
	print("CHAIN TEST PASSED" if _fails.is_empty() else "CHAIN TEST FAILED")
	quit(0 if _fails.is_empty() else 1)

func _end_cfg() -> Dictionary:
	var ui = G.get(&"ui")
	return ui.end_cfg() if ui != null and is_instance_valid(ui) else {}

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	G = root.get_node("Game")
	if not await _until(func(): return G.get(&"state") == "playing"):
		check(false, "chapter 2 starts")
		_finish()
		return
	check(G.get(&"mode") == "etage" and G.get(&"etage").get(&"active") == true, "mode etage, level active")
	# the order of the story, from every starting point
	for pair in [["normal", "etage"], ["explore", "etage"], ["etage", "dehors"], ["dehors", ""]]:
		G.set(&"mode", pair[0])
		check(G.call(&"next_mode") == pair[1], "after %s comes '%s'" % pair)
	G.set(&"mode", "etage")
	var ui0 = G.get(&"ui")

	# ---- chapter 2 won
	G.set(&"time_played", 125.0)
	G.call(&"on_win")
	if not await _until(func(): return not _end_cfg().is_empty() and ui0.end_ready(), 30.0):
		check(false, "win page of chapter 2 is up")
		_finish()
		return
	var e := _end_cfg()
	check(e.get("title") == "FIN DU CHAPITRE 2" and e.get("next") == "dehors", "it announces chapter 3 (%s)" % str(e.get("title")))
	check(str(e.get("go")).contains("CHAPITRE 3"), "the button continues to chapter 3")
	check(e.get("time_str") == "2 MIN 05 S", "chapter time shown (%s)" % str(e.get("time_str")))
	ui0.end_finish()
	check(await _until(func(): return G.get(&"state") == "loading"), "the scene is rebuilt")
	check(G.get(&"pending_mode") == "dehors", "chapter 3 is pending during the loading")
	check(G.get(&"ui").loading_chapter() == "CHAPITRE 3 — DEHORS", "the loading page names chapter 3")
	if not await _until(func(): return G.get(&"state") == "playing"):
		check(false, "chapter 3 starts by itself (no menu)")
		_finish()
		return
	check(G.get(&"mode") == "dehors" and G.get(&"pending_mode") == "", "mode dehors, nothing pending")
	var dh = G.get(&"dehors")
	check(dh != null and dh.get(&"active") == true, "the yard is active")
	check(G.get(&"etage").get(&"active") != true, "the étage is not")
	check(absf(float(G.get(&"run_time")) - 125.0) < 0.01, "the run's time is carried over")
	check(G.get(&"night") == 1, "nights start again at 1")
	for i in 30: await process_frame
	var p: Node3D = G.get(&"player")
	check(p.global_position.x > 90.0, "the player stands in the yard (x=%.1f)" % p.global_position.x)

	# ---- chapter 3 won: the real ending
	G.set(&"time_played", 60.0)
	G.call(&"on_win")
	var ui1 = G.get(&"ui")
	if not await _until(func(): return not _end_cfg().is_empty() and ui1.end_ready(), 30.0):
		check(false, "final win page is up")
		_finish()
		return
	e = _end_cfg()
	check(e.get("title") == "FIN DE LA DIFFUSION" and e.get("next") == "", "it is the ending")
	check(e.get("time_str") == "3 MIN 05 S" and e.get("time_label") == "TEMPS TOTAL", "total time shown (%s)" % str(e.get("time_str")))
	ui1.end_finish()
	check(await _until(func(): return G.get(&"state") == "loading"), "back to a fresh scene")
	check(G.get(&"pending_mode") == "" and G.get(&"ui").loading_chapter() == "CHAPITRE 1 — LE SOUS-SOL", "nothing pending after the ending")

	_finish()
