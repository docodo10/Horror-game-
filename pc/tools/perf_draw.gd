## Render-load probe (needs a renderer): draw calls / primitives / objects per frame, standing still vs moving, at a few
## places. These counts include the shadow passes, so they show what is re-rendered when the player moves.
##   xvfb-run -a godot --path pc --rendering-driver vulkan --resolution 640x360 -s res://tools/perf_draw.gd -- --autostart --quality=high
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _stat(label: String, frames: int, step: Callable) -> void:
	var dc := 0.0; var pr := 0.0; var ob := 0.0
	for i in frames:
		step.call()
		await process_frame
		dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		pr += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		ob += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	print("[draw] %-26s draw calls %6d  primitives %8d  objects %6d" % [label, dc / frames, pr / frames, ob / frames])

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var G := root.get_node("Game")
	while String(G.get(&"state")) != "playing": await process_frame
	var P: Node = G.get(&"player")
	for i in 20: await process_frame
	var n := 6
	await _stat("basement idle", n, func(): pass)
	await _stat("basement turning", n, func(): P.set("yaw", float(P.get("yaw")) + 0.05))
	Input.action_press("move_forward")
	await _stat("basement walking", n, func(): pass)
	Input.action_release("move_forward")
	if P.has_method("give_flashlight"):
		P.call("give_flashlight"); P.call("set_flashlight_on", true)
		for i in 4: await process_frame
		await _stat("basement idle + torch", n, func(): pass)
		Input.action_press("move_forward")
		await _stat("basement walk + torch", n, func(): P.set("yaw", float(P.get("yaw")) + 0.05))
		Input.action_release("move_forward")
		P.call("set_flashlight_on", false)
	var gard: Node = G.get(&"garderie")
	if gard != null:
		gard.call("teleport_player", Vector3(-11.5, 0.0, 2.4), deg_to_rad(96.0))
		for i in 6: await process_frame
		await _stat("vestibule idle", n, func(): pass)
		gard.call("teleport_player", Vector3(-17.9, -1.05, 2.7), deg_to_rad(94.0))
		for i in 6: await process_frame
		await _stat("hall idle", n, func(): pass)
		Input.action_press("move_forward")
		await _stat("hall walking", n, func(): P.set("yaw", float(P.get("yaw")) + 0.03))
		Input.action_release("move_forward")
	quit(0)
