## Driver of interact_test.gd (see there). Aims Game.camera from an eye position at a target point and reads
## Game.interaction.current after a few ray ticks.
extends Node

## [label, eye, target, expected entry id(s), handle to open first ("" = none)]
const CASES := [
	["dresser top drawer", Vector3(-0.75, 1.62, -1.55), Vector3(-0.75, 0.99, -2.2), ["dresser.drawerTop"], ""],
	["dresser bottom drawer", Vector3(-0.4, 1.62, -1.5), Vector3(-0.4, 0.36, -2.2), ["dresser.drawerBottom"], ""],
	["flashlight in the open drawer", Vector3(-0.75, 1.62, -1.45), Vector3(-0.75, 0.97, -2.12), ["item.flashlight"], "dresser.drawerTop"],
	["note on the coffee table", Vector3(0.05, 1.62, 1.75), Vector3(0.05, 0.53, 1.0), ["note1"], ""],
	["child drawing on the kid table", Vector3(-2.05, 1.62, 1.05), Vector3(-2.05, 0.55, 0.3), ["note2"], ""],
	["duck", Vector3(-1.35, 1.62, 1.75), Vector3(-1.35, 0.04, 0.95), ["clue.duck"], ""],
	["horse on the shelves", Vector3(2.15, 1.62, -1.55), Vector3(2.15, 0.8, -2.63), ["clue.horse"], ""],
	["grandfather clock", Vector3(2.95, 1.62, -1.5), Vector3(2.95, 1.6, -2.45), ["clue.clock"], ""],
	["TV", Vector3(-0.55, 1.62, -1.45), Vector3(-0.55, 1.45, -2.4), ["tv"], ""],
	["end table drawer", Vector3(-1.5, 1.62, 1.45), Vector3(-1.5, 0.5, 2.2), ["endTable.drawer"], ""],
	["locked box", Vector3(2.35, 1.62, 0.35), Vector3(3.12, 1.0, 0.2), ["lockedBox", "lockedBox.lock"], ""],
	["padlock", Vector3(2.4, 1.45, 0.15), Vector3(3.017, 0.985, 0.15), ["lockedBox.lock"], ""],
	["closet door", Vector3(-1.6, 1.62, -2.05), Vector3(-2.52, 1.0, -2.05), ["closet.hide"], ""],
	["window", Vector3(1.9, 1.62, 1.55), Vector3(2.45, 2.05, 2.72), ["window"], ""],
	["laundry cabinet drawer", Vector3(0.72, 1.62, -3.35), Vector3(0.72, 1.05, -4.05), ["alcoveCabinet.drawer_01"], ""],
	["laundry cabinet door", Vector3(0.72, 1.62, -3.35), Vector3(0.72, 0.55, -4.08), ["alcoveCabinet.door_01"], ""],
	["power box door", Vector3(2.6, 1.62, -3.75), Vector3(2.6, 1.45, -4.5), ["powerBox.door"], ""],
	["upstairs door (landing)", Vector3(-3.0, 4.37, -2.05), Vector3(-3.0, 3.8, -2.75), ["door.upstairs"], ""],
	["rocking chair", Vector3(1.8, 1.62, 1.0), Vector3(2.5, 0.6, 1.9), ["look.rocking"], ""],
	["mirror", Vector3(0.47, 1.62, -1.6), Vector3(0.47, 1.6, -2.74), ["look.mirror"], ""],
]

var fails: Array[String] = []

func _ready() -> void:
	_run()

func _run() -> void:
	await get_tree().process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var t := 0
	while Game.state != "playing" and t < 1200:
		await get_tree().process_frame
		t += 1
	if Game.state != "playing":
		_fail("the game never reached 'playing' (%s)" % Game.state)
		_end()
		return
	for i in 10: await get_tree().physics_frame
	var player: Node3D = Game.player
	for c in CASES:
		if String(c[4]) != "":
			var h = Game.world.handles.get(c[4])
			if h != null: h.set_state(true)
		var eye: Vector3 = c[1]
		var target: Vector3 = c[2]
		var d := target - eye
		var yaw := atan2(-d.x, -d.z)
		var pitch := atan2(d.y, Vector2(d.x, d.z).length())
		var floor_y: float = float(Game.world.ground_height_at(eye.x, eye.z, eye.y - 1.62))
		player.call("teleport", Vector3(eye.x, floor_y + 0.02, eye.z), yaw, pitch)
		for i in 12: await get_tree().physics_frame
		# the camera may lag one frame behind the body: re-aim exactly from where it is
		var cam := Game.camera
		if cam != null:
			var cd := target - cam.global_position
			player.call("teleport", player.global_position, atan2(-cd.x, -cd.z), atan2(cd.y, Vector2(cd.x, cd.z).length()))
		for i in 8: await get_tree().physics_frame
		var cur = Game.interaction.get(&"current")
		var got := String(cur.get("id", "")) if cur is Dictionary else "(none)"
		var want: Array = c[3]
		if want.has(got): print("ok   %-30s -> %s" % [c[0], got])
		else:
			var body = Game.interaction.get(&"target_body")
			_fail("%s: got %s (want %s, body %s, cam %s)" % [c[0], got, want, body.name if body is Node else "-", cam.global_position if cam else "-"])
		if String(c[4]) != "":
			var h = Game.world.handles.get(c[4])
			if h != null: h.set_state(false)
	_end()

func _fail(s: String) -> void:
	fails.append(s)
	printerr("FAIL ", s)

func _end() -> void:
	print("interact test: %d cases, %d failures" % [CASES.size(), fails.size()])
	print("INTERACT TEST OK" if fails.is_empty() else "INTERACT TEST FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)
