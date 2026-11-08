## Gameplay end-to-end test (loaded by test_gameplay.gd, a SceneTree script). Builds a fake basement with the real Layout
## positions — handles (drawers, cabinet doors, power box, lever, box lid + padlock, closet door, upstairs door), items, clues,
## TV, walls, furniture colliders — then plays the whole scenario through the REAL Interaction ray + simulated "interact"
## presses (Input.action_press), with the real Inventory and Puzzles, and asserts the stage sequence up to the win.
## Exercised ray paths: interact bodies under the node, auto proxies (meshes only), WORLD bodies under the node (doors, clock),
## a world-tagged body outside the node (TV, metadata interact_id), nested entries (item in an open drawer), interactables
## contained in furniture AABB colliders (horse on the shelves, note 3 in the cabinet, key in the box), walls blocking.
extends Node

const Fakes := preload("res://scripts/game/tests/gameplay_fakes.gd")
const InventoryScript := preload("res://scripts/game/inventory.gd")
const InteractionScript := preload("res://scripts/game/interaction.gd")
const PuzzlesScript := preload("res://scripts/game/puzzles.gd")
const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const FRAME_LIMIT := 60000

var world: Node3D
var ui: CanvasLayer
var player: Node3D
var entity: Node3D
var lighting: Node3D
var tv_tagged: Node3D
var inventory: Node
var interaction: Node
var puzzles: Node
var stages: Array[String] = []
var noises: Array = []
var failures: Array[String] = []
var checks := 0
var won := false
var gtime := 0.0
var _frames := 0
var _done := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _process(delta: float) -> void:
	gtime += delta
	_frames += 1
	if _frames > FRAME_LIMIT and not _done:
		fail("watchdog: scenario did not finish in %d frames (stage %s)" % [FRAME_LIMIT, puzzles.stage if puzzles else "?"])
		_finish()

# ------------------------------------------------------------------ assertions

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond: fail(msg)

func fail(msg: String) -> bool:
	failures.append(msg)
	printerr("[test] FAIL: ", msg)
	return false

func _finish() -> void:
	if _done: return
	_done = true
	print("[test] stages: ", stages, "  game time %.1fs, %d frames" % [gtime, _frames])
	var code := 0
	if failures.is_empty():
		print("[test] PASS gameplay scenario (%d checks)" % checks)
	else:
		print("[test] FAILED %d/%d checks" % [failures.size(), checks])
		code = 1
	for n in [puzzles, interaction, inventory, entity, player, ui, world]:
		if n != null and is_instance_valid(n): n.queue_free()
	for k in ["world", "ui", "player", "camera", "entity", "interaction", "inventory", "puzzles"]: Game.set(k, null)
	await frames(2)
	get_tree().quit(code)

# ------------------------------------------------------------------ helpers

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func game_time(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()

func until(cond: Callable, max_sec: float, what: String) -> bool:
	var t := 0.0
	while not cond.call():
		if t > max_sec: return fail("timeout waiting for " + what)
		await get_tree().process_frame
		t += get_process_delta_time()
	return true

func cur_id() -> String:
	var c = interaction.current
	return str(c.id) if c != null else "none"

func target_point(e: Dictionary) -> Vector3:
	var n: Node3D = e.node
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_front()
		if x is CollisionShape3D: return (x as Node3D).global_position
		for c in x.get_children(): stack.append(c)
	return n.global_position

## Aim the camera from `eye` at the entry (or at `at`), wait until the ray targets it, press interact (held `hold` s), wait done.
func use(id: String, eye: Vector3, at: Variant = null, hold := 0.0) -> bool:
	var e = interaction.entries.get(id)
	if e == null: return fail("no interaction entry '%s'" % id)
	if not player.hidden:
		player.aim(eye, at if at is Vector3 else target_point(e))
	var ok := false
	for i in 30:
		await get_tree().process_frame
		if cur_id() == id:
			ok = true
			break
	if not ok: return fail("cannot target '%s' (current: %s, prompt: '%s')" % [id, cur_id(), ui.prompt_text])
	Input.action_press("interact")
	if hold > 0.0: await game_time(hold)
	else: await get_tree().process_frame
	Input.action_release("interact")
	await get_tree().process_frame
	for i in 6000:
		if not interaction.busy: break
		await get_tree().process_frame
	await frames(2)
	return true

## Aim and assert what the ray resolves to ("none" = nothing / blocked).
func expect_target(eye: Vector3, at: Vector3, want: String, why: String) -> void:
	player.aim(eye, at)
	await frames(4)
	check(cur_id() == want, "%s: expected target '%s', got '%s'" % [why, want, cur_id()])

func heard(source: String, loudness: float) -> bool:
	for n in noises:
		if n[0] == source and is_equal_approx(float(n[1]), loudness): return true
	return false

# ------------------------------------------------------------------ fake level

func box(parent: Node, name_: String, pos: Vector3, size: Vector3, layer: int, mesh: bool, rot_y := 0.0, local_center := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	n.position = pos
	n.rotation.y = rot_y
	parent.add_child(n)
	if mesh:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = local_center
		n.add_child(mi)
	if layer != 0:
		var b := StaticBody3D.new()
		b.collision_layer = layer
		b.collision_mask = 0
		b.position = local_center
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)
		n.add_child(b)
	return n

func handle(id: String, node: Node3D, open_xf: Transform3D, contents: Node3D = null, h: Handle = null) -> Handle:
	if h == null: h = Handle.new()
	h.id = id
	h.node = node
	h.closed_xform = node.transform
	h.open_xform = open_xf
	h.duration = 0.35
	h.contents = contents
	world.handles[id] = h
	return h

## Sliding drawer: front face at `pos` (local +Z = out), box behind it, contents inside, opens 0.3 m.
func drawer(id: String, parent: Node, pos: Vector3, rot_y: float, size: Vector3) -> Handle:
	var n := box(parent, id.replace(".", "_"), pos, size, LAYER_INTERACT, true, rot_y, Vector3(0, 0, -size.z * 0.5))
	var c := Node3D.new()
	c.name = "contents"
	c.position = Vector3(0, -size.y * 0.5 + 0.04, -0.12)
	n.add_child(c)
	var t := n.transform
	return handle(id, n, Transform3D(t.basis, t.origin + t.basis.z * 0.3), c)

## Hinged door: hinge at `pos`, panel extends along local +X (sign) — opens by rotating `angle` around Y.
func hinged(id: String, parent: Node, pos: Vector3, size: Vector3, panel_center: Vector3, angle: float, layer: int, h: Handle = null) -> Handle:
	var n := box(parent, id.replace(".", "_"), pos, size, layer, true, 0.0, panel_center)
	var t := n.transform
	return handle(id, n, Transform3D(t.basis.rotated(Vector3.UP, angle), t.origin), null, h)

func item(id: String, parent: Node, local_pos: Vector3, size: Vector3, with_body: bool) -> Node3D:
	var n := box(parent, id, Vector3.ZERO, size, LAYER_INTERACT if with_body else 0, true)
	n.position = local_pos
	world.items[id] = n
	return n

func build_level() -> void:
	world = Fakes.FakeWorld.new()
	world.name = "World"
	add_child(world)
	lighting = Fakes.FakeLighting.new()
	lighting.name = "Lighting"
	world.add_child(lighting)
	world.lighting = lighting
	var W := world

	# north wall of the main room with the nook doorway (x 0.9..1.8, h 2.05)
	box(W, "wallNorthA", Vector3(-1.3, 1.25, -2.85), Vector3(4.4, 2.5, 0.2), LAYER_WORLD, true)
	box(W, "wallNorthB", Vector3(2.65, 1.25, -2.85), Vector3(1.7, 2.5, 0.2), LAYER_WORLD, true)
	box(W, "wallNorthLintel", Vector3(1.35, 2.275, -2.85), Vector3(0.9, 0.45, 0.2), LAYER_WORLD, true)

	# dresser (furniture AABB collider) + 3 drawers flush with its front; flashlight in the top drawer (meshes only -> auto proxy)
	box(W, "dresser", Vector3(-0.55, 0.6, -2.44), Vector3(1.0, 1.2, 0.5), LAYER_WORLD, true)
	var top := drawer("dresser.drawerTop", W, Vector3(-0.55, 0.95, -2.19), 0.0, Vector3(0.8, 0.16, 0.4))
	drawer("dresser.drawerMid", W, Vector3(-0.55, 0.65, -2.19), 0.0, Vector3(0.8, 0.16, 0.4))
	drawer("dresser.drawerBottom", W, Vector3(-0.55, 0.35, -2.19), 0.0, Vector3(0.8, 0.16, 0.4))
	item("flashlight", top.contents, Vector3.ZERO, Vector3(0.2, 0.05, 0.05), false)

	# TV on the dresser; its interact body is NOT under the TV node: a world body tagged interact_id = "tv"
	var tv := Fakes.FakeTV.new()
	tv.name = "tv"
	tv.position = Vector3(-0.55, 1.2, -2.44)
	tv.world = world
	W.add_child(tv)
	var tvm := MeshInstance3D.new()
	var tvb := BoxMesh.new()
	tvb.size = Vector3(0.5, 0.4, 0.4)
	tvm.mesh = tvb
	tvm.position = Vector3(0, 0.2, 0)
	tv.add_child(tvm)
	tv.screen_position = Vector3(-0.55, 1.42, -2.23)
	world.tv = tv
	world.clues["tv"] = tv
	tv_tagged = box(W, "tvInteractBody", Vector3(-0.55, 1.4, -2.44), Vector3(0.52, 0.42, 0.42), LAYER_INTERACT, false)
	(tv_tagged.get_child(0) as Node).set_meta(&"interact_id", "tv")

	# coffee table + note 1; kid table + note 2
	box(W, "coffeeTable", Vector3(0.25, 0.26, 0.95), Vector3(1.0, 0.52, 0.6), LAYER_WORLD, true)
	item("note1", W, Vector3(0.05, 0.536, 1.0), Vector3(0.21, 0.01, 0.28), true)
	box(W, "kidTable", Vector3(-2.0, 0.27, 0.2), Vector3(0.6, 0.54, 0.6), LAYER_WORLD, true)
	item("note2", W, Vector3(-2.05, 0.552, 0.3), Vector3(0.21, 0.01, 0.28), true)

	# end table (faces -Z) + drawer + battery 1
	box(W, "endTable", Vector3(-1.5, 0.3, 2.42), Vector3(0.5, 0.6, 0.4), LAYER_WORLD, true)
	var et := drawer("endTable.drawer", W, Vector3(-1.5, 0.48, 2.22), PI, Vector3(0.4, 0.1, 0.3))
	item("battery1", et.contents, Vector3.ZERO, Vector3(0.05, 0.015, 0.015), true)

	# nook: alcove cabinet (AABB collider) with drawers / doors; note 3 in the static compartment behind door_01
	box(W, "alcoveCabinet", Vector3(1.0, 0.6, -4.28), Vector3(1.0, 1.2, 0.4), LAYER_WORLD, true)
	var d1 := drawer("alcoveCabinet.drawer_01", W, Vector3(1.0, 1.02, -4.08), 0.0, Vector3(0.8, 0.12, 0.35))
	item("battery2", d1.contents, Vector3.ZERO, Vector3(0.05, 0.015, 0.015), true)
	drawer("alcoveCabinet.drawer_02", W, Vector3(1.0, 0.86, -4.08), 0.0, Vector3(0.8, 0.12, 0.35))
	hinged("alcoveCabinet.door_01", W, Vector3(0.55, 0.42, -4.07), Vector3(0.4, 0.6, 0.02), Vector3(0.2, 0, 0), -1.7, LAYER_INTERACT)
	hinged("alcoveCabinet.door_02", W, Vector3(1.45, 0.42, -4.07), Vector3(0.4, 0.6, 0.02), Vector3(-0.2, 0, 0), 1.7, LAYER_INTERACT)
	item("note3", W, Vector3(0.75, 0.25, -4.25), Vector3(0.15, 0.01, 0.2), true)

	# power box (AABB collider) on the nook wall: door in front, lever (Handle with set_on) behind it
	box(W, "powerBox", Vector3(2.6, 1.45, -4.5), Vector3(0.35, 0.45, 0.1), LAYER_WORLD, true)
	hinged("powerBox.door", W, Vector3(2.425, 1.45, -4.44), Vector3(0.35, 0.45, 0.02), Vector3(0.175, 0, 0.005), -1.9, LAYER_INTERACT)
	var lv_node := box(W, "powerBox_lever", Vector3(2.6, 1.45, -4.47), Vector3(0.05, 0.12, 0.05), LAYER_INTERACT, true)
	var lever := Fakes.FakeLever.new()
	lever.world = world
	var down := lv_node.transform
	handle("powerBox.lever", lv_node, Transform3D(down.basis.rotated(Vector3.RIGHT, 0.9), down.origin), null, lever)
	lever.is_open = true   # starts ON (power on), like the web lever

	# console + Léa's locked box: lid (hinge at the back edge, box faces -X), brass padlock in front, key inside
	box(W, "console", Vector3(3.18, 0.47, 0.15), Vector3(0.4, 0.94, 1.2), LAYER_WORLD, true)
	var lb := box(W, "lockedBox", Vector3(3.12, 0.949, 0.15), Vector3(0.22, 0.1, 0.32), LAYER_WORLD, true, 0.0, Vector3(0, 0.05, 0))
	var lid_n := box(W, "lockedBox_lid", Vector3(3.23, 1.05, 0.15), Vector3(0.22, 0.01, 0.32), LAYER_INTERACT, true, 0.0, Vector3(-0.11, 0.005, 0))
	var lt := lid_n.transform
	var box_contents := Node3D.new()
	box_contents.name = "contents"
	box_contents.position = Vector3(0, 0.06, 0)
	lb.add_child(box_contents)
	handle("lockedBox.lid", lid_n, Transform3D(lt.basis.rotated(Vector3.BACK, -1.8), lt.origin), box_contents)
	var lock_n := box(W, "lockedBox_lock", Vector3(2.995, 1.0, 0.15), Vector3(0.03, 0.06, 0.05), LAYER_INTERACT, true)
	handle("lockedBox.lock", lock_n, Transform3D(lock_n.transform.basis, lock_n.position + Vector3(0, 0.015, 0)))
	item("key", box_contents, Vector3.ZERO, Vector3(0.08, 0.02, 0.04), true)

	# clues: duck (scaled, meshes only), horse on the shelves (inside the shelves' AABB collider), clock (its WORLD body only)
	var duck := box(W, "duck", Vector3(-1.35, 0.0, 0.95), Vector3(0.15, 0.15, 0.15), 0, true, 0.8, Vector3(0, 0.075, 0))
	duck.scale = Vector3.ONE * 0.6
	world.clues["duck"] = duck
	box(W, "shelves", Vector3(2.15, 0.9, -2.6), Vector3(0.8, 1.8, 0.35), LAYER_WORLD, true)
	world.clues["horse"] = box(W, "horse", Vector3(2.15, 1.125, -2.58), Vector3(0.12, 0.15, 0.05), 0, true, 0.5, Vector3(0, 0.075, 0))
	world.clues["clock"] = box(W, "grandfather", Vector3(2.95, 0.0, -2.52), Vector3(0.5, 2.0, 0.4), LAYER_WORLD, true, 0.0, Vector3(0, 1.0, 0))

	# upstairs door (WORLD collider under the door node, locked), closet door + hide spot
	var up := hinged("door.upstairs", W, Vector3(-3.45, 2.75, -2.75), Vector3(0.85, 2.03, 0.045), Vector3(0.425, 1.015, 0), -1.6, LAYER_WORLD)
	up.locked = true
	var cd := hinged("door.closet", W, Vector3(-2.55, 0.0, -2.36), Vector3(0.04, 1.9, 0.62), Vector3(0, 0.95, 0.31), 1.5, LAYER_WORLD | LAYER_INTERACT)
	var C: Dictionary = Layout.CLOSET
	world.hide_spots.append({"id": "closet", "door": cd, "hide_pos": Vector3(C.hidePos.x, C.hidePos.y, C.hidePos.z),
		"hide_yaw": float(C.hideYaw), "exit_pos": Vector3(C.exitPos.x, 0.0, C.exitPos.z)})

	# flavour props found by name
	box(W, "rockingChair", Vector3(2.55, -0.102, 1.95), Vector3(0.6, 1.1, 0.9), LAYER_WORLD, true, -2.2, Vector3(0, 0.55, 0))
	box(W, "extra_gnome", Vector3(3.25, 0.0, -3.1), Vector3(0.2, 0.4, 0.2), 0, true, -1.47, Vector3(0, 0.2, 0))
	box(W, "extra_mirror", Vector3(0.47, 1.62, -2.73), Vector3(0.6, 0.9, 0.04), 0, true)

# ------------------------------------------------------------------ scenario

func _run() -> void:
	InputSetup.setup()
	build_level()
	ui = Fakes.FakeUI.new()
	ui.name = "UI"
	add_child(ui)
	player = Fakes.FakePlayer.new()
	player.name = "Player"
	add_child(player)
	entity = Fakes.FakeEntity.new()
	entity.name = "Gardienne"
	add_child(entity)
	Game.world = world
	Game.ui = ui
	Game.player = player
	Game.camera = player.camera
	Game.entity = entity
	if Events.game_win.is_connected(Game.on_win): Events.game_win.disconnect(Game.on_win)   # no scene reload in the test
	Events.game_win.connect(func() -> void: won = true)
	Events.stage_changed.connect(func(s: String, _p: String) -> void:
		stages.append(s)
		print("[test] t=%.1fs stage -> %s" % [gtime, s]))
	Events.noise.connect(func(_pos: Vector3, l: float, src: String) -> void: noises.append([src, l]))

	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	add_child(inventory)
	Game.inventory = inventory
	interaction = InteractionScript.new()
	interaction.name = "Interaction"
	add_child(interaction)
	Game.interaction = interaction
	puzzles = PuzzlesScript.new()
	puzzles.name = "Puzzles"
	add_child(puzzles)
	Game.puzzles = puzzles
	await puzzles.setup()
	await frames(3)
	var code: String = puzzles.code
	check(code.length() == 4 and not code.contains("0"), "code is 4 digits 1-9: " + code)
	check(world.digits.get("duck") == code[0] and world.digits.get("tv") == code[3], "world.set_clue_digits got the code")
	check(world.tv.digit == code[3], "tv.set_digit got the 4th digit")
	for id in ["dresser.drawerTop", "item.flashlight", "note1", "note3", "powerBox.lever", "lockedBox", "lockedBox.lock", "item.key",
			"clue.duck", "clue.horse", "clue.clock", "tv", "door.upstairs", "closet.hide", "closet.exit", "window", "look.bulb",
			"look.rocking", "look.gnome", "look.mirror"]:
		check(interaction.entries.has(id), "registered: " + id)
	var bat_body: Node = world.items["battery1"].get_child(1)
	check(bat_body.get_meta(&"interact_id", "") == "item.battery1", "body tag = deepest entry (got %s)" % bat_body.get_meta(&"interact_id", ""))
	check(tv_tagged.get_child(0).get_meta(&"interact_id", "") == "tv", "world tag kept")
	check(world.items["flashlight"].find_child("InteractProxy_*", false, false) != null, "auto proxy built for a mesh-only item")

	Game.start()
	await frames(2)
	check(puzzles.stage == "intro", "starts in intro")
	check(ui.objectives.has("Explore le sous-sol."), "intro objective")

	# ---------------- intro
	var landing := Vector3(-3.0, 4.37, -1.95)
	await use("door.upstairs", landing)
	check(ui.said("Verrouillée."), "locked door rattles")
	check(heard("door.rattle", 0.35), "rattle noise 0.35")
	check(ui.prompts_seen.has("Ouvrir la porte"), "door prompt without key")
	await use("window", Vector3(2.45, 1.62, 1.5))
	check(ui.said("barreaux"), "window line")
	await use("look.mirror", Vector3(0.47, 1.62, -1.8))
	check(ui.said("Je ne me reconnais presque pas."), "mirror line")
	await use("note1", Vector3(0.05, 1.6, 1.85))
	check(ui.notes_shown.size() == 1 and ui.notes_shown[0].title == "Note pliée", "note 1 shown in a modal")
	check(inventory.get_note("note1").size() > 0, "note 1 kept in the inventory")
	await until(func() -> bool: return puzzles.stage == "dark", 5.0, "blowout after note 1")
	check(lighting.blowouts == 1 and world.power == false, "blowout: lighting.blowout + power off")
	check(world.handles["powerBox.lever"].is_on == false, "breaker tripped with the blowout")
	check(ui.objectives.back() == "Trouve une lumière.", "dark objective")

	# ---------------- dark
	await use("tv", Vector3(-0.55, 1.62, -1.4), Vector3(-0.55, 1.4, -2.44))
	check(ui.said("Pas de courant"), "TV needs power")
	check(not world.tv.is_on, "TV stays off without power")
	var dresser_eye := Vector3(-0.55, 1.6, -1.25)
	await expect_target(dresser_eye, world.items["flashlight"].global_position, "dresser.drawerTop", "closed drawer hides the flashlight")
	await use("dresser.drawerTop", dresser_eye, Vector3(-0.55, 0.95, -2.2))
	check(world.handles["dresser.drawerTop"].is_open, "top drawer open")
	check(heard("dresser.drawerTop", 0.15), "drawer noise 0.15")
	await use("item.flashlight", dresser_eye, world.items["flashlight"].global_position)
	check(puzzles.stage == "power", "flashlight -> power stage (got %s)" % puzzles.stage)
	check(player.flashlight["has"] and player.flashlight["on"], "flashlight given and switched on")
	check(inventory.has("flashlight"), "flashlight in the inventory")
	check(not world.items["flashlight"].visible, "flashlight hidden after pickup")
	# rocking chair beat: first look at it with light after the blowout
	player.aim(Vector3(1.6, 1.62, 0.8), Vector3(2.55, 0.5, 1.95))
	await game_time(0.6)
	check(world.rock_calls == 1 and puzzles.flags.rocked, "rocking chair rocks by itself")

	# ---------------- power
	await use("endTable.drawer", Vector3(-1.5, 1.5, 1.4), Vector3(-1.5, 0.48, 2.23))
	await use("item.battery1", Vector3(-1.5, 1.5, 1.3), world.items["battery1"].global_position)
	check(inventory.count("battery") == 1, "battery 1 picked up")
	await expect_target(Vector3(2.6, 1.6, -2.62), Vector3(2.6, 1.45, -4.43), "none", "nook wall blocks the power box from the room")
	var nook := Vector3(2.6, 1.6, -3.5)
	await expect_target(nook, Vector3(2.6, 1.45, -4.47), "powerBox.door", "closed panel door covers the lever")
	await use("powerBox.door", nook, Vector3(2.6, 1.45, -4.435))
	await use("powerBox.lever", nook, Vector3(2.6, 1.45, -4.47))
	check(puzzles.flags.breaker and world.power, "breaker on, power back")
	check(heard("breaker", 1.0), "breaker noise 1.0")
	check(entity.summons.size() == 1 and entity.summons[0][1] == "breaker", "entity summoned to the panel")
	await game_time(1.0)
	check(ui.alerts.has("CACHE-TOI\u00a0!"), "CACHE-TOI alert (French typography)")
	check(ui.objectives.back().begins_with("Cache-toi"), "hide objective")
	await use("closet.hide", Vector3(-1.6, 1.62, -2.05), Vector3(-2.55, 0.95, -2.05))
	check(player.hidden and player.hide_spot != null and player.hide_spot.door == world.handles["door.closet"], "hidden in the closet (spot carries the door Handle)")
	check(ui.said("Ne bouge plus"), "hide tip")
	await until(func() -> bool: return puzzles.stage == "code", 8.0, "her visit to end")
	check(ui.said("Elle est remontée"), "she went back upstairs")
	check(ui.objectives.back() == "Trouve le code du coffret (4 chiffres)", "code objective")
	await use("closet.exit", Vector3.ZERO)
	check(not player.hidden, "out of the closet")

	# ---------------- code
	var console := Vector3(2.4, 1.6, 0.15)
	await use("lockedBox", console, Vector3(3.12, 1.055, 0.15))
	check(puzzles.flags.box_note and ui.notes_shown.back().title == "Le coffret de Léa", "box note read")
	var duck: Node3D = world.clues["duck"]
	var duck_xf := duck.transform
	await use("clue.duck", Vector3(-1.35, 1.4, 1.75))
	check(puzzles.found.duck == code[0], "duck digit found")
	check(duck.transform.is_equal_approx(duck_xf), "duck put back exactly after the tilt")
	await use("clue.horse", Vector3(2.15, 1.6, -1.6), Vector3(2.15, 1.17, -2.58))
	check(puzzles.found.horse == code[1], "horse digit found (inside the shelves' collider)")
	await use("clue.clock", Vector3(2.95, 1.6, -1.6), Vector3(2.95, 1.2, -2.52))
	check(puzzles.found.clock == code[2], "clock digit found")
	await use("tv", Vector3(-0.55, 1.62, -1.4), Vector3(-0.55, 1.4, -2.44))
	check(world.tv.is_on, "TV on")
	player.aim(Vector3(-0.55, 1.62, -1.4), world.tv.screen_position)
	await game_time(1.3)
	check(puzzles.found.tv == code[3], "TV digit found by looking at the static")
	check(heard("tv", 0.55), "TV noise 0.55 while on")
	await use("tv", Vector3(-0.55, 1.62, -1.4), Vector3(-0.55, 1.4, -2.44))
	check(not world.tv.is_on, "TV off")
	check(ui.objectives.back() == "Ouvre le cadenas du coffret.", "all digits objective")
	check(ui.clues.get("tv") == code[3], "UI carnet updated")
	var cab := Vector3(0.9, 1.4, -3.3)
	await use("alcoveCabinet.door_01", cab, Vector3(0.75, 0.42, -4.07))
	await use("note3", cab, Vector3(0.75, 0.25, -4.25))
	check(ui.notes_shown.back().get("style") == "newspaper", "newspaper read (inside the cabinet collider)")
	await use("alcoveCabinet.drawer_01", cab, Vector3(1.0, 1.02, -4.09))
	await use("item.battery2", Vector3(1.0, 1.6, -3.4), world.items["battery2"].global_position)
	check(inventory.count("battery") == 2, "battery 2 picked up")
	check(inventory.list()[1].name == "Piles", "plural item name")

	# caught once: progress kept, gnome turned toward the spawn
	var gnome: Node3D = world.find_child("extra_gnome", true, false)
	var gnome_yaw := gnome.rotation.y
	Game.night = 2
	puzzles.reset_after_caught()
	check(puzzles.stage == "code" and ui.objectives.back() == "Ouvre le cadenas du coffret.", "progress kept after a catch")
	check(puzzles.flags.gnome_moved and absf(gnome.rotation.y - gnome_yaw) > 0.3, "gnome turned after the catch")
	check(ui.night == 2, "night 2 shown")
	await game_time(2.0)
	check(ui.said("Encore ici"), "caught line")
	await use("look.gnome", Vector3(2.5, 1.62, -3.1), Vector3(3.25, 0.2, -3.1))
	check(ui.said("pas tourné comme ça"), "gnome line after it moved")

	# keypad: a wrong code first, then the right one
	var wrong := ""
	for i in 4: wrong += str((int(code[i]) % 9) + 1)
	ui.keypad_answers.assign([wrong, code])
	var lock_at := Vector3(2.995, 1.0, 0.15)
	await use("lockedBox.lock", Vector3(2.4, 1.5, 0.15), lock_at)
	check(puzzles.stats.code_attempts == 1 and not puzzles.flags.box_open, "wrong code refused")
	check(heard("lock", 0.15), "wrong code noise 0.15")
	check(ui.said("L’ordre\u00a0: canard"), "wrong code line")
	await use("lockedBox.lock", Vector3(2.4, 1.5, 0.15), lock_at)
	check(puzzles.flags.box_open and world.handles["lockedBox.lid"].is_open, "right code opens the box")
	check(ui.keypad_titles.size() == 2 and ui.keypad_titles[0] == "Cadenas du coffret", "keypad title")
	await use("item.key", console, world.items["key"].global_position)
	check(puzzles.stage == "escape", "key -> escape stage (got %s)" % puzzles.stage)
	check(entity.aggression == 2, "aggression after the key")
	check(inventory.has("key"), "key in the inventory")

	# ---------------- escape: hold 2 s on the door with the key
	player.aim(landing, Vector3(-3.025, 3.765, -2.75))
	await frames(4)
	check(ui.prompt_text == "Déverrouiller (maintenir)" and ui.prompt_opts.get("hold") == 0.0, "hold prompt with the key")
	await use("door.upstairs", landing, Vector3(-3.025, 3.765, -2.75), 2.3)
	check(ui.prompts_seen.has("Déverrouillage…"), "hold progress prompt")
	check(heard("door.unlock", 0.35), "unlock noise 0.35")
	await until(func() -> bool: return won, 4.0, "the win")
	check(world.handles["door.upstairs"].is_open and not world.handles["door.upstairs"].locked, "door unlocked and open")
	check(puzzles.stage == "win", "win stage")
	check(stages == ["dark", "power", "code", "escape", "win"], "stage sequence")
	check(not interaction.busy and interaction.current == null, "interaction reset at the win")
	_finish()
