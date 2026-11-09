## CPU frame-time probe (headless): runs the real game, stands still, then walks / turns / sprints, and reports the
## per-frame CPU cost (script + physics + audio; nothing is rendered) for each phase, with the worst frames.
##   godot --headless --path pc -s res://tools/perf_walk.gd -- --autostart
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _phase(label: String, secs: float, step: Callable) -> void:
	var ts: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < int(secs * 1e6):
		step.call(float(Time.get_ticks_usec() - t0) / 1e6)
		await process_frame
		var now := Time.get_ticks_usec()
		ts.append(float(now - last) / 1000.0)
		last = now
	ts.sort()
	var n := ts.size()
	var sum := 0.0
	for v in ts: sum += v
	print("[perf] %-22s frames %5d  mean %.2f ms  p50 %.2f  p99 %.2f  max %.2f  >8ms: %d  >16ms: %d  proc %.2f phys %.2f" % [label, n, sum / n,
		ts[n / 2], ts[int(n * 0.99)], ts[n - 1], ts.filter(func(v): return v > 8.0).size(), ts.filter(func(v): return v > 16.0).size(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var G := root.get_node("Game")
	var t0 := Time.get_ticks_msec()
	while String(G.get(&"state")) != "playing" and Time.get_ticks_msec() - t0 < 90000: await process_frame
	var P: Node = G.get(&"player")
	Engine.max_fps = 240
	await _phase("settle", 4.0, func(_t): pass)
	await _phase("idle", 5.0, func(_t): pass)
	Input.action_press("move_forward")
	await _phase("walk forward", 4.0, func(_t): pass)
	await _phase("walk + turn", 6.0, func(_t): P.set("yaw", float(P.get("yaw")) + 0.02))
	Input.action_release("move_forward")
	Input.action_press("move_left")
	await _phase("strafe + turn", 5.0, func(_t): P.set("yaw", float(P.get("yaw")) - 0.015))
	Input.action_release("move_left")
	Input.action_press("move_forward"); Input.action_press("sprint")
	await _phase("sprint + turn", 5.0, func(_t): P.set("yaw", float(P.get("yaw")) + 0.03))
	Input.action_release("sprint")
	var gard: Node = G.get(&"garderie")
	if gard != null and gard.has_method("teleport_player"):
		gard.call("teleport_player", Vector3(-19.0, -1.05, 2.0), deg_to_rad(90.0))
		await _phase("garderie walk + turn", 6.0, func(_t): P.set("yaw", float(P.get("yaw")) + 0.02))
		gard.call("teleport_player", Vector3(-23.7, -1.05, 5.6), deg_to_rad(105.0))
		await _phase("ball pit walk", 6.0, func(_t): P.set("yaw", float(P.get("yaw")) + 0.02))
	Input.action_release("move_forward")
	quit(0)
