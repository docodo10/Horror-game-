## Stutter hunt: plays a scripted tour of the whole game TWICE in one run and logs every frame to a CSV:
## frame time, draw calls / primitives (they include the shadow passes), pipeline compilations by source (the "draw"
## ones block the frame), video memory. A hitch that only shows in lap 1 is a first-time cost (shader pipeline, upload,
## lazy load) that the loading screen should absorb; one that shows in both laps is a recurring cost.
##   rendered: xvfb-run -a godot --path pc --rendering-driver vulkan --resolution 480x270 --fixed-fps 30 \
##               -s res://tools/hitch_hunt.gd -- --autostart --quality=medium --out=/abs/file.csv [--no-warmup]
##   CPU only: godot --headless --path pc --fixed-fps 60 -s res://tools/hitch_hunt.gd -- --autostart --out=/abs/file.csv
## Analyse with tools/hitch_report.py.
extends SceneTree

const COMPILE_IDS := [9, 8, 7, 10, 6]     # draw, surface, mesh, specialization, canvas

var G: Node
var E: Node
var P: Node
var W: Node
var GA: Node
var ENT: Node
var FEAR: Node
var _lap := 1
var _step := ""
var _last_us := 0
var _prev := [0, 0, 0, 0, 0]
var _rows: PackedStringArray = []
var _n := 0
var _out := ""
var _header_done := false
var _part := "all"       # all | basement | garderie

func _initialize() -> void:
	_run.call_deferred()

func _frame() -> void:
	await process_frame
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_us) / 1000.0
	_last_us = now
	var c: Array = []
	for id in COMPILE_IDS: c.append(int(RenderingServer.get_rendering_info(id)))
	var d: Array = []
	for i in c.size(): d.append(c[i] - _prev[i] if c[i] >= _prev[i] else c[i])
	_prev = c
	var pos: Vector3 = P.global_position if P != null else Vector3.ZERO
	var vp := root.get_viewport_rid()
	var sh_prims := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var sh_calls := RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_rows.append("%d,%s,%d,%.2f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%.2f,%s,%d,%d" % [_lap, _step, _n, ms,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		d[0], d[1], d[2], d[3], d[4],
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576,
		pos.x, pos.z, float(P.get("yaw")) if P != null else 0.0, String(G.get(&"state")), sh_prims, sh_calls])
	_n += 1
	_poll_hidden()
	if _n % 60 == 0: _flush()
	# a caught / game-over screen waits for a key
	var st := String(G.get(&"state"))
	if (st == "caught" or st == "gameover" or st == "won") and _n % 15 == 0:
		for pressed in [true, false]:
			var e := InputEventKey.new()
			e.keycode = KEY_ENTER
			e.pressed = pressed
			root.push_input(e)

var _notes: PackedStringArray = []
var _hidden: Array = []

func _on_node_added(n: Node) -> void:
	if n is VisualInstance3D or n is CanvasItem and _n > 0:
		_notes.append("%d,added,%s,%s,%s" % [_n, n.get_class(), n.name, n.get_parent().name if n.get_parent() else ""])

## Hidden visuals at the start of play; polled every frame to see which ones show up (and when).
func _snapshot_hidden() -> void:
	for n in root.find_children("*", "VisualInstance3D", true, false):
		if not (n as VisualInstance3D).is_visible_in_tree(): _hidden.append(n)

func _poll_hidden() -> void:
	var i := _hidden.size() - 1
	while i >= 0:
		var n = _hidden[i]
		if not is_instance_valid(n):
			_hidden.remove_at(i)
		elif (n as VisualInstance3D).is_visible_in_tree():
			_notes.append("%d,shown,%s,%s,%s" % [_n, (n as Node).get_class(), (n as Node).name, (n as Node).get_parent().name])
			_hidden.remove_at(i)
		i -= 1

func _flush() -> void:
	if _out != "" and not _notes.is_empty():
		var nf := FileAccess.open(_out + ".nodes.txt", FileAccess.READ_WRITE if FileAccess.file_exists(_out + ".nodes.txt") and _header_done else FileAccess.WRITE)
		if nf != null:
			nf.seek_end()
			for l in _notes: nf.store_line(l)
			nf.close()
		_notes.clear()
	if _out == "": return
	var f := FileAccess.open(_out, FileAccess.READ_WRITE if _header_done else FileAccess.WRITE)
	if f == null: return
	if not _header_done:
		f.store_line("lap,step,frame,ms,draw_calls,prims,objects,c_draw,c_surface,c_mesh,c_spec,c_canvas,vmem_mb,x,z,yaw,state,shadow_prims,shadow_calls")
		_header_done = true
	f.seek_end()
	for r in _rows: f.store_line(r)
	f.close()
	_rows.clear()

func idle(label: String, n: int) -> void:
	_step = label
	for i in n: await _frame()

func spin(label: String, n := 26, step := 0.26) -> void:
	_step = label
	for i in n:
		P.set("yaw", float(P.get("yaw")) + step)
		await _frame()

func tp(x: float, z: float, yaw_deg := 0.0, y := 0.0) -> void:
	P.call("teleport", Vector3(x, y, z), deg_to_rad(yaw_deg), 0.0)

func gtp(x: float, y: float, z: float, yaw_deg: float) -> void:
	if GA != null: GA.call("teleport_player", Vector3(x, y, z), deg_to_rad(yaw_deg), 0.0)

func walk_to(label: String, x: float, z: float, max_frames := 150) -> void:
	_step = label
	Input.action_press("move_forward")
	for i in max_frames:
		var p: Vector3 = P.global_position
		var dx := x - p.x
		var dz := z - p.z
		if dx * dx + dz * dz < 0.16: break
		P.set("yaw", atan2(-dx, -dz))
		await _frame()
	Input.action_release("move_forward")

## Short first-time-cost check (a few hundred frames): what the loading screen must have absorbed.
func _tour_quick() -> void:
	tp(0.25, 1.5, 0.0)
	var qargs: Dictionary = root.get_node("DebugTools").get(&"args")
	if qargs.has("switch-pause") and _lap == 1:
		# the player changes the quality in the pause menu, then resumes
		await idle("before pause", 10)
		G.call("pause")
		await idle("paused", 10)
		root.get_node("Settings").call("set_value", "quality", String(qargs["switch-pause"]))
		await idle("paused quality switched", 6)
		G.call("resume")
		var g := 0
		while String(G.get(&"state")) != "playing" and g < 2000:
			await idle("resume prepares", 1)
			g += 1
		await idle("resumed", 15)
	await idle("spawn idle", 25)
	await spin("spawn spin")
	await spin("spawn spin 2", 26, -0.26)
	await walk_to("walk centre", 0.9, -0.45, 60)
	await spin("centre spin")
	tp(-0.6, -1.55, 0.0)
	await idle("tv front idle", 12)
	await spin("tv front spin")
	tp(-2.0, -1.9, 0.0)
	await idle("closet front idle", 12)
	await spin("closet front spin")
	tp(0.25, 1.5, 0.0)
	await idle("back at spawn", 12)
	if FEAR != null:
		for id in ["fake_ball", "crt_static", "fake_shelf"]:
			FEAR.call("force", id)
			await idle("scare " + id, 24)
	if ENT != null and ENT.has_method("debug_place"):
		tp(0.25, 1.5, 0.0)
		ENT.call("set_enabled", true)
		await idle("entity enabled", 8)
		if root.get_node("DebugTools").get(&"args").has("ent-parts"):
			# which of her meshes costs a pipeline: show them one by one
			var parts: Array = ENT.find_children("*", "MeshInstance3D", true, false)
			for m in parts: (m as MeshInstance3D).visible = false
			ENT.call("debug_place", Vector3(0.6, 0.0, -1.0), 0.0, "idle", 4.0)
			await idle("ent none", 6)
			for m in parts:
				(m as MeshInstance3D).visible = true
				await idle("ent part " + String((m as Node).name), 5)
		ENT.call("debug_place", Vector3(0.6, 0.0, -1.0), 0.0, "idle", 4.0)
		await idle("entity appears", 20)
		await spin("entity spin")
		ENT.call("debug_place", Vector3(0.6, 0.0, -1.0), 0.0, "chase", -1.0, "camera")
		await idle("entity animated", 20)
		ENT.call("debug_release")
		ENT.call("set_enabled", false)
	P.call("give_flashlight"); P.call("set_flashlight_on", true)
	await idle("torch on", 10)
	await spin("torch spin")
	W.call("set_power", false)
	await idle("power off", 15)
	W.call("set_power", true)
	await idle("power back", 50)
	P.call("set_flashlight_on", false)

func _lap_tour() -> void:
	if _part == "quick":
		await _tour_quick()
		return
	if _part != "garderie": await _tour_basement()
	if _part != "basement": await _tour_garderie()
	tp(0.25, 1.5, 0.0)
	await idle("lap end", 10)

func _tour_basement() -> void:
	# ---------------- basement: the first room, then every corner, on foot, with fast turns
	tp(0.25, 1.5, 0.0)
	await idle("spawn idle", 15)
	await spin("spawn spin")
	await walk_to("walk centre", 0.9, -0.45)
	await spin("centre spin")
	await walk_to("walk alcove door", 1.35, -2.35)
	await walk_to("walk alcove in", 1.35, -3.5)
	await spin("alcove spin")
	await walk_to("walk alcove east", 2.7, -3.6)
	await spin("alcove east spin")
	await walk_to("walk back alcove door", 1.35, -2.2)
	await walk_to("walk tv front", -0.6, -1.55)
	await spin("tv front spin")
	await walk_to("walk closet front", -2.0, -1.9)
	await spin("closet front spin")
	await walk_to("walk sw corner", -2.2, 2.1)
	await walk_to("walk stairs bottom", -3.0, 2.05)
	await walk_to("walk stairs mid", -3.0, -0.1)
	await walk_to("walk stairs top", -3.0, -1.6)
	await spin("stairs top spin")
	await walk_to("walk landing", -3.0, -2.3, 60)
	await spin("landing spin")
	# ---------------- torch, power cut, power back
	tp(0.25, 1.5, 0.0)
	await idle("back at spawn", 10)
	P.call("give_flashlight"); P.call("set_flashlight_on", true)
	await idle("torch on", 12)
	await spin("torch spin")
	W.call("set_power", false)
	await idle("power off", 20)
	await spin("power off spin")
	await walk_to("dark walk tv front", -0.6, -1.55)
	await spin("dark tv spin")
	W.call("set_power", true)
	await idle("power back", 70)
	await spin("power back spin")
	P.call("set_flashlight_on", false)
	await idle("torch off", 8)
	# ---------------- hide in the closet
	var spots: Array = W.get(&"hide_spots")
	if spots.size() > 0:
		tp(-2.05, -2.05, 90.0)
		await idle("closet approach", 8)
		P.call("enter_hide", spots[0])
		await idle("closet enter", 75)
		await spin("closet look around", 14, 0.08)
		P.call("exit_hide")
		await idle("closet exit", 75)
	# ---------------- pause menu
	tp(0.25, 1.5, 0.0)
	await idle("before pause", 6)
	G.call("pause")
	await idle("paused", 25)
	G.call("resume")
	await idle("resumed", 30)
	# ---------------- scripted scares (fear director)
	if FEAR != null:
		for id in ["flicker", "knock_wall", "giggle", "breath_neck", "rocking", "torch_stutter", "chain_sway", "crt_static",
				"window_tap", "hum_walls", "fake_shelf", "fake_ball", "glimpse_stairs", "glimpse_mirror", "glimpse_dark",
				"ceiling_run", "door_handle"]:
			FEAR.call("force", id)
			await idle("scare " + id, 28)
	# ---------------- La Gardienne in view, then her jumpscare (caught -> next night)
	if ENT != null and ENT.has_method("debug_place"):
		tp(0.25, 1.5, 0.0)
		ENT.call("set_enabled", true)
		ENT.call("debug_place", Vector3(0.6, 0.0, -1.0), 0.0, "idle", 4.0)
		await idle("entity appears", 25)
		await spin("entity spin", 26, 0.26)
		ENT.call("debug_jumpscare", 1.0)
		await idle("jumpscare", 60)
		# the real ending of a jumpscare: caught screen, then everything is reset for the next night
		E.emit_signal("entity_caught")
		var guard := 0
		while (String(G.get(&"state")) != "playing" or bool(P.get("camera_override"))) and guard < 600:
			await idle("caught screen", 1)
			guard += 1
		ENT.call("debug_release")
		ENT.call("set_enabled", false)
		await idle("after caught", 50)
	# ---------------- puzzle stage events
	var PZ: Node = G.get(&"puzzles")
	if PZ != null and PZ.has_method("debug_goto") and _lap == 1:
		tp(0.25, 1.5, 0.0)
		PZ.call("debug_goto", "dark")
		await idle("stage dark", 60)
		await spin("stage dark spin")
		PZ.call("debug_goto", "power")
		await idle("stage power", 80)
		await spin("stage power spin")
		if ENT != null: ENT.call("set_enabled", false)

func _tour_garderie() -> void:
	# ---------------- the garderie: corridor, vestibule, hall on foot, then every corner
	if GA != null:
		if GA.has_method("set_door_open"): GA.call("set_door_open", true)
		tp(-2.4, 2.05, 90.0)
		await idle("garderie door", 20)
		await walk_to("walk into corridor", -4.6, 2.05, 90)
		await spin("corridor start spin")
		await walk_to("walk corridor", -8.0, 2.05, 160)
		await walk_to("walk to vestibule", -11.5, 2.4, 160)
		await spin("vestibule spin")
		await walk_to("walk vestibule end", -15.2, 2.5, 160)
		await walk_to("walk into hall", -17.9, 2.7, 140)
		await spin("hall entry spin")
		for v in [[-18.3, 3.9, 72.0, "hall a"], [-19.0, -4.2, 92.0, "hall b"], [-23.7, 5.6, 105.0, "ball pit"],
				[-27.6, 9.8, 48.0, "hall c"], [-26.0, 1.2, 80.0, "hall d"], [-34.6, 6.8, 95.0, "hall far"]]:
			gtp(v[0], -1.05, v[1], v[2])
			await idle(String(v[3]) + " arrive", 10)
			await spin(String(v[3]) + " spin")
			Input.action_press("move_forward")
			await idle(String(v[3]) + " walk", 20)
			Input.action_release("move_forward")
		for kind in ["tube_dies", "ball_roll", "giggle_slide", "hum"]:
			GA.call("scare", kind)
			await idle("garderie scare " + kind, 30)
		for id in ["wave", "spiral"]:
			GA.call("ride", id)
			await idle("ride " + id, 110)
		gtp(-18.3, -1.05, 3.9, 72.0)
		W.call("set_power", false)
		await idle("hall power off", 30)
		await spin("hall dark spin")
		W.call("set_power", true)
		await idle("hall power back", 70)
		# back out on foot: hall -> vestibule -> corridor -> house
		gtp(-17.5, -1.05, 2.7, -90.0)
		await walk_to("walk out to vestibule", -14.5, 2.5, 140)
		await walk_to("walk out vestibule", -11.5, 2.4, 140)
		await walk_to("walk out corridor", -4.6, 2.05, 220)
		await walk_to("walk back into house", -2.0, 2.05, 120)
		await spin("house return spin")

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	G = root.get_node("Game")
	E = root.get_node("Events")
	var t0 := Time.get_ticks_msec()
	while not (String(G.get(&"state")) in ["playing", "menu"]) and Time.get_ticks_msec() - t0 < 600000: await process_frame
	P = G.get(&"player")
	if String(G.get(&"state")) == "menu":
		# the real path: the TV menu, then JOUER (run without --autostart)
		_out = String(root.get_node("DebugTools").get(&"args").get("out", "user://hitch.csv"))
		for id_i in COMPILE_IDS.size(): _prev[id_i] = int(RenderingServer.get_rendering_info(COMPILE_IDS[id_i]))
		print("[hitch] menu after %d ms; pipeline compilations so far: %s" % [Time.get_ticks_msec() - t0, str(_prev)])
		_last_us = Time.get_ticks_usec()
		_snapshot_hidden()
		node_added.connect(_on_node_added)
		await idle("menu", 30)
		var dargs: Dictionary = root.get_node("DebugTools").get(&"args")
		if dargs.has("switch-menu"):
			# the player lowers / raises the quality on the TV menu before starting
			root.get_node("Settings").call("set_value", "quality", String(dargs["switch-menu"]))
			await idle("menu quality switched", 20)
		(G.get(&"ui") as Node).call("tv_start_game", "normal")
		var g := 0
		while String(G.get(&"state")) != "playing" and g < 300:
			await idle("menu to game", 1)
			g += 1
	W = G.get(&"world")
	GA = G.get(&"garderie")
	ENT = G.get(&"entity")
	FEAR = main.get_node_or_null("FearDirector")
	if ENT != null: ENT.call("set_enabled", false)
	_out = String(root.get_node("DebugTools").get(&"args").get("out", "user://hitch.csv"))
	_part = String(root.get_node("DebugTools").get(&"args").get("part", "all"))
	print("[hitch] game playing after %d ms; quality %s" % [Time.get_ticks_msec() - t0, root.get_node("Settings").call("get_value", "quality", "?")])
	if _hidden.is_empty():
		_snapshot_hidden()
		node_added.connect(_on_node_added)
		_last_us = Time.get_ticks_usec()
		for id_i in COMPILE_IDS.size(): _prev[id_i] = int(RenderingServer.get_rendering_info(COMPILE_IDS[id_i]))
	print("[hitch] pipeline compilations before play (draw, surface, mesh, specialization, canvas): ", _prev)
	await idle("settle", 20)
	for lap in [1, 2]:
		_lap = lap
		await _lap_tour()
		print("[hitch] lap %d done, %d frames" % [lap, _n])
	_flush()
	print("[hitch] wrote ", _out)
	quit(0)
