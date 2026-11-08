## Player in the real game flow (scenes/main.gd + whatever modules are present): menu idle camera, menu -> game camera
## blend, pause freeze, caught -> reset_after_caught (camera released, respawn), noise/flashlight signals.
##   godot --headless --fixed-fps 60 --path pc -s res://scripts/player/tests/main_flow_test.gd [-- --main-script=/abs/main.gd]
## (--main-script runs another copy of main.gd as the Main node, e.g. a locally patched one.)
extends SceneTree

var G: Node
var E: Node
var fails := 0
var passes := 0

func _initialize() -> void:
	_run()

func _check(name: String, ok: bool, details := "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[flow] %s %s: %s" % ["PASS" if ok else "FAIL", name, details])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	G = root.get_node("Game")
	E = root.get_node("Events")
	var main_script := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--main-script="):
			main_script = a.get_slice("=", 1)
	if main_script != "":
		var m := Node3D.new()
		m.name = "Main"
		m.process_mode = Node.PROCESS_MODE_ALWAYS
		m.set_script(load(main_script))
		root.add_child(m)
	else:
		root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	var t := 0
	while G.state != "menu" and t < 1200:
		await process_frame
		t += 1
	_check("reaches the menu", G.state == "menu", "state=%s" % G.state)
	var P = G.player
	var cam: Camera3D = P.camera
	var ui_owns: bool = G.ui != null and G.ui.get("menu_camera_active") == true
	var a: Vector3 = cam.global_position
	await _frames(90)
	var b: Vector3 = cam.global_position
	if ui_owns:
		_check("menu camera left to the UI", true, "ui.menu_camera_active")
	else:
		_check("menu idle drift", a.distance_to(b) > 0.002 and a.distance_to(Vector3(0.25, 1.62, 1.5)) > 0.3, "%s -> %s" % [a, b])
	E.ui_start.emit()
	await _frames(3)
	_check("game starts", G.state == "playing" and cam.current, "state=%s current=%s" % [G.state, cam.current])
	var start_pos: Vector3 = cam.global_position
	await _frames(20)
	var mid_pos: Vector3 = cam.global_position
	await _frames(90)
	var eye: Vector3 = P.eye_position()
	_check("menu -> game camera blend", start_pos.distance_to(eye) > 0.2 and mid_pos.distance_to(eye) > 0.02 and cam.global_position.distance_to(eye) < 0.01,
		"start %s mid %s end %s eye %s" % [start_pos, mid_pos, cam.global_position, eye])
	# pause freezes the player
	Input.action_press("move_forward")
	await _frames(10)
	G.pause()
	var p0: Vector3 = P.global_position
	await _frames(3)
	var was_paused: bool = self.paused
	var p1: Vector3 = P.global_position
	Input.action_release("move_forward")
	var w := 0
	while G.state != "playing" and w < 300:
		await process_frame
		w += 1
	_check("pause freezes movement", was_paused and p0.distance_to(p1) < 0.0001 and G.state == "playing", "paused=%s moved %.4f" % [was_paused, p0.distance_to(p1)])
	# caught: the entity took the camera; Game.on_caught -> reset_after_caught releases it and respawns
	P.give_flashlight()
	await _frames(5)
	P.teleport(Vector3(1.5, 0, -1.0), 1.0)
	P.camera_override = true
	P.enabled = false
	E.entity_caught.emit()
	w = 0
	while (G.state != "playing" or P.camera_override) and w < 900:
		await process_frame
		w += 1
	await _frames(10)
	_check("caught -> reset_after_caught", G.state == "playing" and not P.camera_override and P.enabled and G.night == 2 \
		and P.global_position.distance_to(Vector3(0.25, 0, 1.5)) < 0.05 and P.flashlight.has and P.flashlight.on,
		"state=%s night=%d pos=%s override=%s" % [G.state, G.night, P.global_position, P.camera_override])
	print("[flow] SUMMARY: %d passed, %d failed" % [passes, fails])
	quit(fails)
