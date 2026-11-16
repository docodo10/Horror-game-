## Trailer footage: plays scripted first-person shots in the real game, to be recorded with Godot's movie writer
## (offline rendering: every frame is drawn, 60 per second of game time, with the game's own audio).
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path pc --rendering-driver vulkan --resolution 1920x1080 \
##       --fixed-fps 60 --write-movie /abs/run_etage.avi -s res://tools/trailer/trailer_shots.gd -- \
##       --run=etage --autostart --mode=etage --no-garderie --quality=high --no-warmup --no-auto-quality
##   --run=basement : no --autostart (the shot starts on the TV menu), --no-garderie --no-etage --quality=high
##   --run=garderie : --autostart --no-etage --quality=low
##   --only=a,b     : only these shots of the run
##
## The movie is MJPEG: for a clean master put a temporary pc/override.cfg (not committed) with
##   [editor]
##   movie_writer/mjpeg_quality=0.97
## One rendered run at a time: a 1080p run on the high preset takes about 10 GB of memory on a software renderer.
##
## Each shot prints "[shot] <name> <first frame> <last frame>" (movie frame numbers): tools/trailer/build_trailer.py
## cuts the movie there.
extends SceneTree

var G: Node
var P: Node3D
var I: Node
var _fc := 0
var _only: PackedStringArray = []
var _args := {}

func _initialize() -> void:
	process_frame.connect(func() -> void: _fc += 1)
	_run()

# ---------------------------------------------------------------------------------------------- helpers

func hold(n: int) -> void:
	for i in n: await process_frame

func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

## Turns the head to (yaw, pitch) over n frames, the short way round, eased in and out.
func look(yaw_to: float, pitch_to: float, n: int) -> void:
	var y0 := float(P.get("yaw"))
	var p0 := float(P.get("pitch"))
	var dy := wrapf(yaw_to - y0, -PI, PI)
	for i in n:
		var k := _ease(float(i + 1) / float(n))
		P.set("yaw", y0 + dy * k)
		P.set("pitch", p0 + (pitch_to - p0) * k)
		await process_frame

func yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))

func look_at_point(target: Vector3, n: int, pitch_bias := 0.0) -> void:
	var eye: Vector3 = P.global_position + Vector3(0, 1.6, 0)
	var d := target - eye
	await look(yaw_to(eye, target), atan2(d.y, Vector2(d.x, d.z).length()) + pitch_bias, n)

## Walks to (x, z): forward key held, the heading eased toward the target (turn_rate rad/s).
func walk(x: float, z: float, max_n := 400, turn_rate := 2.4, stop := 0.3, pitch_to := 0.0) -> void:
	Input.action_press("move_forward")
	for i in max_n:
		var p: Vector3 = P.global_position
		var dx := x - p.x
		var dz := z - p.z
		if dx * dx + dz * dz < stop * stop: break
		var want := atan2(-dx, -dz)
		var cur := float(P.get("yaw"))
		var dy := wrapf(want - cur, -PI, PI)
		P.set("yaw", cur + clampf(dy, -turn_rate / 60.0, turn_rate / 60.0))
		P.set("pitch", lerpf(float(P.get("pitch")), pitch_to, 0.04))
		await process_frame
	Input.action_release("move_forward")

func tp(x: float, z: float, yaw := 0.0, pitch := 0.0, y := 0.0) -> void:
	P.call("teleport", Vector3(x, y, z), yaw, pitch)

func want(shot: String) -> bool:
	return _only.is_empty() or _only.has(shot)

var _open := ""
var _open_at := 0

func begin(shot: String) -> void:
	_open = shot
	_open_at = _fc

func mark(what: String) -> void:
	print("[mark] %s %s %d" % [_open, what, _fc])

func end() -> void:
	print("[shot] %s %d %d" % [_open, _open_at, _fc])
	_open = ""

func _playing() -> bool:
	return String(G.get(&"state")) == "playing"

# ---------------------------------------------------------------------------------------------- runs

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	G = root.get_node("Game")
	for a in OS.get_cmdline_user_args():     # (the DebugTools autoload has not read them yet at this point)
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("only"): _only = String(_args["only"]).split(",")
	seed(1994)
	var run := String(_args.get("run", "etage"))
	var guard := 0
	while not (String(G.get(&"state")) in ["playing", "menu"]) and guard < 200000:
		await process_frame
		guard += 1
	P = G.get(&"player")
	I = G.get(&"interaction")
	var fear := main.get_node_or_null("FearDirector")
	if fear != null and run != "etage":
		fear.set_process(false)             # no random scare walks into a shot
		fear.set_physics_process(false)
	print("[trailer] run %s ready at frame %d (state %s)" % [run, _fc, String(G.get(&"state"))])
	match run:
		"etage": await _etage()
		"basement": await _basement()
		"garderie": await _garderie()
	print("[trailer] done at frame %d" % _fc)
	await hold(4)
	quit()

# ------------------------------------------------------------------ chapter 2: the hallway, her door, the salon, it

func _etage() -> void:
	var E = G.get(&"etage")
	var east := -PI * 0.5
	if want("e_hall"):
		await hold(110)                      # the loading card has faded
		begin("e_hall")
		await walk(59.6, 0.05, 360, 1.2)
		await look(-0.35, 0.03, 70)          # the salon's double door, open on the dark
		await hold(40)
		end()
	if want("e_door"):
		tp(57.6, 0.45, PI * 0.5)
		await hold(20)
		begin("e_door")
		await walk(56.45, 0.45, 200, 2.0, 0.2)
		await look_at_point(Vector3(55.04, 1.25, -0.8), 40)
		mark("door")
		I.call("activate", "etage.chambre", true)
		await hold(215)
		end()
	if want("e_salon"):
		tp(60.7, -0.15, 0.0)
		await hold(20)
		begin("e_salon")
		await walk(60.7, -2.3, 200, 1.5)
		await look(0.95, 0.02, 110)          # west: the piano, the tall shapes by the window
		await hold(25)
		await look(-0.75, 0.0, 190)          # east, slowly, across the room: one of them is nearer than the others
		await hold(50)
		end()
	if want("e_key"):
		var key_at := Vector3(65.3, 1.18, -4.4)
		tp(63.9, -3.55, east, -0.1)
		await hold(10)
		await look_at_point(key_at, 20)
		begin("e_key")
		await hold(50)
		mark("key")
		I.call("activate", "etage.key", true)
		await look(float(P.get("yaw")), 0.0, 90)
		# the clock stops; the sconces die one by one out in the hallway; then something stands behind
		var w: Dictionary = (E.get("_walkers") as Array)[0]
		var n := 0
		while n < 500 and not bool(w.get("awake", false)):
			await process_frame
			n += 1
		mark("awake")
		var head := func() -> Vector3: return (w.pos as Vector3) + Vector3(0, 1.45, 0)
		await look_at_point(head.call(), 26) # turn around
		mark("seen1 d=%.2f" % (w.pos as Vector3).distance_to(P.global_position))
		await hold(100)
		var y := float(P.get("yaw"))
		await look(y - 1.8, 0.0, 15)         # look away ...
		await hold(30)
		await look_at_point(head.call(), 12) # ... and back: closer
		mark("seen2 d=%.2f" % (w.pos as Vector3).distance_to(P.global_position))
		await hold(64)
		y = float(P.get("yaw"))
		await look(y + 1.9, 0.0, 15)         # away again
		n = 0
		while n < 240 and not bool(E.get("_catching")):
			await process_frame
			n += 1
		mark("caught after %d" % n)
		await hold(50)
		end()

# ------------------------------------------------------------------ chapter 1: the television, the basement, her

func _basement() -> void:
	var W = G.get(&"world")
	var ENT = G.get(&"entity")
	if String(G.get(&"state")) == "menu":
		var keep := want("b_menu")
		if keep: begin("b_menu")
		await hold(130 if keep else 2)
		(G.get(&"ui") as Node).call("tv_start_game", "normal")
		var g := 0
		while not _playing() and g < 900:
			await process_frame
			g += 1
		await hold(330 if keep else 30)
		if keep: end()
	if ENT != null: ENT.call("set_enabled", false)
	if want("b_walk"):
		tp(0.25, 1.5, 0.0)
		await hold(20)
		begin("b_walk")
		await walk(0.85, -0.5, 300, 1.4)
		await look(1.25, -0.06, 120)         # the wall of drawings
		await hold(30)
		await look(-0.9, 0.0, 150)
		await hold(20)
		end()
	if want("b_dark"):
		tp(0.6, 0.3, 0.35, 0.12)
		await hold(40)
		begin("b_dark")
		await hold(50)
		W.call("set_power", false)
		await hold(95)
		P.call("give_flashlight")
		P.call("set_flashlight_on", true)
		await hold(30)
		await look(-0.7, -0.05, 150)
		await look(1.1, -0.1, 190)
		await hold(20)
		end()
	if want("b_her") and ENT != null and ENT.has_method("debug_place"):
		W.call("set_power", false)
		P.call("give_flashlight")
		P.call("set_flashlight_on", true)
		tp(0.25, 1.5, 1.35, -0.08)
		await hold(40)
		ENT.call("set_enabled", true)
		var at := Vector3(0.55, 0.0, -1.75)
		var pp: Vector3 = P.global_position
		ENT.call("debug_place", at, atan2(pp.x - at.x, pp.z - at.z), "idle", -1.0, "camera")
		begin("b_her")
		await hold(50)
		await look(0.0, 0.0, 46)             # the beam comes back across the room: she is standing in it
		await hold(75)
		if P.has_method("flashlight_stutter"): P.call("flashlight_stutter", 0.6)
		await hold(40)
		ENT.call("debug_jumpscare")
		await hold(85)
		end()
		ENT.call("debug_release")
		ENT.call("set_enabled", false)

# ------------------------------------------------------------------ the garderie: dortoir, bureau, toilettes, hall

func _garderie() -> void:
	var GA = G.get(&"garderie")
	if GA == null:
		return
	if GA.has_method("set_door_open"): GA.call("set_door_open", true)
	var fx = GA.get("rooms_fx")
	var rfx: Dictionary = GA.get("ctx").room_fx
	var subs := root.find_child("Subtitles", true, false)
	if subs is CanvasItem: (subs as CanvasItem).visible = false      # the basement's hints do not belong in these shots
	await hold(110)                          # the loading card has faded
	if want("g_dortoir"):
		GA.call("teleport_player", Vector3(-7.6, 0.0, 2.25), 0.0, 0.0)
		await hold(30)
		begin("g_dortoir")
		await walk(-7.6, -0.7, 240, 1.4)
		await look(0.5, 0.42, 110)           # the stars on the ceiling
		await hold(30)
		await look(-0.45, 0.3, 120)
		await hold(30)
		end()
	if want("g_bureau"):
		GA.call("teleport_player", Vector3(-5.75, 0.0, 3.6), PI, 0.0)
		await hold(30)
		begin("g_bureau")
		await walk(-5.75, 4.35, 120, 1.4)
		if fx != null: fx.call("_ring")
		await hold(25)
		await look_at_point(rfx.phone, 55)
		await hold(150)
		if fx != null: fx.call("_ring")
		await hold(70)
		end()
	if want("g_wc"):
		var hinge: Vector3 = rfx.stall_hinge
		var GL = load("res://scripts/garderie/garderie_layout.gd")
		var sx := float(GL.WC.x0) + 1.55
		var sz := hinge.z - 1.75
		GA.call("teleport_player", Vector3(sx, 0.0, sz), 0.0, 0.0)
		await hold(20)
		var stall := hinge + Vector3(0.3, 1.0, 0.0)
		P.set("yaw", yaw_to(P.global_position, stall) + 1.2)
		await hold(20)
		begin("g_wc")
		if fx != null: fx.set("_wc_t", 3.2)
		await hold(70)                       # the creak, behind
		await look_at_point(stall, 60)
		await hold(110)                      # the stall door swings open on nothing
		await walk(hinge.x + 0.3, hinge.z - 0.2, 160, 1.6, 0.9)
		await hold(120)                      # it slams
		end()
	if want("g_hall"):
		GA.call("teleport_player", Vector3(-15.4, 0.0, 2.5), PI * 0.5, 0.0)
		await hold(30)
		begin("g_hall")
		await walk(-18.6, 2.9, 300, 1.4)
		await look(PI * 0.5 + 0.55, 0.12, 110)
		await look(PI * 0.5 - 0.5, 0.05, 150)
		await hold(20)
		end()
	if want("g_slide") and GA.has_method("ride"):
		GA.call("teleport_player", Vector3(-18.3, -1.05, 3.9), deg_to_rad(72.0), 0.0)
		await hold(20)
		begin("g_slide")
		GA.call("ride", "wave")
		await hold(270)
		end()
