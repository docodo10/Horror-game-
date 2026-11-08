## World module headless test driver (loaded at runtime by world_test.gd: a SceneTree script cannot reference the
## autoloads at compile time). Run:  godot --headless --fixed-fps 60 --path pc -s res://scripts/world/tests/world_test.gd
## Builds the real level (exporter outputs + original models), then:
##  * walk test: a CharacterBody3D with the player's collision setup (capsule r 0.25 h 1.75, floor 50°, snap 0.35) walks
##    spawn -> foot of the stairs -> up the stair ramp (heights sampled against the ramp plane and the tread heights) ->
##    landing -> blocked by the locked door -> door opened -> upper hallway -> back down -> laundry nook; blocked by the
##    sofa, the knee wall (closet), the north wall
##  * ground probes (physics floor vs Layout.ground_height_at), line of sight cases, nav paths
##  * every handle opened / closed onto the exported transforms, door colliders, lever <-> power, padlock wheels + drop,
##    lid pops the lock, TV on / off with power, clue digits (decals, clock hands, TV), rocking chair, interaction bodies,
##    items at their exported world positions
## Prints "WORLD TEST OK" (exit 0) or the failures (exit 1).
extends Node

const World := preload("res://scripts/world/world.gd")

class Walker extends CharacterBody3D:
	var target := Vector3.ZERO
	var speed := 1.9
	var active := false

	func _init() -> void:
		collision_layer = 4
		collision_mask = 1
		floor_max_angle = deg_to_rad(50.0)
		floor_snap_length = 0.35
		floor_stop_on_slope = true
		floor_block_on_wall = true
		floor_constant_speed = true
		max_slides = 6
		safe_margin = 0.002
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.25
		cap.height = 1.75
		cs.shape = cap
		cs.position.y = 0.875
		add_child(cs)

	func _physics_process(dt: float) -> void:
		var to := target - global_position
		to.y = 0.0
		var hv := Vector3.ZERO
		if active and to.length() > 0.04: hv = to.normalized() * speed
		velocity.x = hv.x
		velocity.z = hv.z
		if is_on_floor(): velocity.y = 0.0
		else: velocity.y -= 9.8 * dt
		move_and_slide()

var world: Node3D
var walker: Walker
var fails: Array[String] = []
var checks := 0

func _ready() -> void:
	_run()

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append(what)
		printerr("FAIL: ", what)

func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _run() -> void:
	await get_tree().process_frame
	world = World.new()
	world.name = "World"
	get_tree().root.add_child(world)
	Game.world = world
	await world.build(func(_p: float, _t: String) -> void: pass)
	_check(world.built, "world built")
	var forced_fallback := "--world-fallback" in OS.get_cmdline_user_args()
	_check((world.ctx as Dictionary).get("generated", false) != forced_fallback, "built from the %s" % ("Layout fallback" if forced_fallback else "exporter outputs"))
	await _frames(3)
	_test_static()
	await _test_walk()
	await _test_handles()
	await _test_runtime()
	print("world test: %d checks, %d failures" % [checks, fails.size()])
	if fails.is_empty(): print("WORLD TEST OK")
	else:
		for f in fails: printerr("  - ", f)
		print("WORLD TEST FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)

# ------------------------------------------------------------------ static checks

func _test_static() -> void:
	var meta: Dictionary = world.meta
	# contract
	for id in ["dresser.drawerTop", "dresser.drawerMid", "dresser.drawerBottom", "endTable.drawer", "alcoveCabinet.drawer_01",
			"alcoveCabinet.drawer_02", "alcoveCabinet.door_01", "alcoveCabinet.door_02", "powerBox.door", "powerBox.lever",
			"lockedBox.lid", "lockedBox.lock", "door.upstairs", "door.closet"]:
		var h = world.handles.get(id)
		_check(h is Handle and (h as Handle).node != null and (h as Handle).node.is_inside_tree(), "handle %s bound to a node" % id)
	_check(world.handles["door.upstairs"].locked, "upstairs door starts locked")
	_check(world.handles["powerBox.lever"].is_on and world.handles["powerBox.lever"].is_open, "breaker starts ON")
	for id in world.ITEM_IDS:
		var it = world.items.get(id)
		_check(it is Node3D and (it as Node3D).is_inside_tree(), "item %s" % id)
		if it is Node3D and meta.get("items", {}).has(id):
			var want: Array = meta.items[id].transform
			var d := (it as Node3D).global_position.distance_to(Vector3(want[12], want[13], want[14]))
			_check(d < 0.003, "item %s at its exported position (%.4f m)" % [id, d])
	for k in world.CLUE_IDS:
		_check(world.clues.get(k) is Node3D, "clue %s" % k)
	_check(world.tv != null and world.tv.get(&"node") is Node3D and world.tv.get(&"screen") is MeshInstance3D, "tv controller")
	_check(world.hide_spots.size() == 1 and world.hide_spots[0].door == world.handles["door.closet"], "closet hide spot with its door")
	_check(world.props.get("rockingChair") is Node3D and world.props.get("extra_gnome") is Node3D and world.props.get("photoFrame") is Node3D, "flavour props by web name")
	# interaction bodies
	for id in world.handles:
		_check(_interact_bodies(id) > 0, "interaction body for handle %s" % id)
	for id in world.ITEM_IDS:
		_check(_interact_bodies(id) > 0, "interaction body for item %s" % id)
	for k in world.CLUE_IDS:
		_check(_interact_bodies(k) > 0, "interaction body for clue %s" % k)
	# ground probes: physics floor vs the web groundHeightAt
	var pts := {
		"spawn": [0.25, 1.5, 3.0, 0.0], "center": [0.9, -0.45, 3.0, 0.0], "nook": [1.35, -3.5, 3.0, 0.0], "nook east": [2.7, -3.6, 2.0, 0.0],
		"stairs foot": [-3.0, 2.05, 3.0, 0.0], "landing": [-3.0, -2.3, 4.0, 2.75], "hall": [-3.0, -3.6, 4.5, 2.75],
		"hall end": [-3.0, -4.2, 4.5, 2.75], "door threshold": [-3.0, -2.82, 4.0, 2.75], "closet": [-3.05, -2.05, 1.5, 0.0],
	}
	for k in pts:
		var p: Array = pts[k]
		var y: float = world.ground_probe(p[0], p[1], p[2])
		_check(not is_nan(y) and absf(y - float(p[3])) < 0.02, "ground probe %s: %.3f (want %.2f)" % [k, y, p[3]])
	# stairs: ramp plane between the tread heights
	for i in 13:
		var z := 1.5 - i * 0.26
		var y: float = world.ground_probe(-3.0, z, 4.0)
		var tread := Layout.stair_height_at(-3.0, z)
		var ramp := (Layout.STAIRS.bottomZ - z) * Layout.UPPER.floorY / (Layout.STAIRS.bottomZ - Layout.STAIRS.topZ)
		_check(absf(y - ramp) < 0.02 and absf(y - tread) < 0.22, "stair probe z=%.2f: %.3f (ramp %.3f, tread %.3f)" % [z, y, ramp, tread])
	# line of sight
	_check(world.line_blocked(Vector3(0, 1.5, 0), Vector3(3.0, 1.5, -4.2)), "sight: north wall blocks room -> nook corner")
	_check(not world.line_blocked(Vector3(1.35, 1.5, -1.0), Vector3(1.35, 1.5, -3.8)), "sight: clear through the nook doorway")
	_check(world.line_blocked(Vector3(0, 1.5, 0), Vector3(0, 3.6, 0)), "sight: ceiling blocks room -> upstairs")
	_check(not world.line_blocked(Vector3(-3.0, 1.8, 1.0), Vector3(0.0, 1.0, 1.0)), "sight: through the stair railing (lower flight)")
	_check(world.line_blocked(Vector3(-3.0, 2.4, 0.0), Vector3(0.0, 1.0, 0.5)), "sight: full-height knee wall beside the upper flight")
	_check(world.line_blocked(Vector3(-3.0, 3.9, -2.3), Vector3(-3.0, 3.9, -3.6)), "sight: closed upstairs door blocks")
	_check(world.line_blocked(Vector3(-1.5, 1.0, -2.0), Vector3(-3.05, 1.0, -2.05)), "sight: closed closet door blocks")
	_check(world.line_blocked(Vector3(0.25, 0.5, 1.2), Vector3(0.25, 0.5, 3.0)), "sight: sofa blocks low")
	# nav
	var path: PackedVector3Array = world.nav_path(Vector3(2.5, 0, 1.0), Vector3(-3.0, 2.75, -3.6))
	_check(path.size() >= 6 and path[path.size() - 1].is_equal_approx(Vector3(-3.0, 2.75, -3.6)), "nav path room -> hall (%d points)" % path.size())
	var up: int = world.nearest_nav_id(Vector3(-3.0, 2.75, -2.4))
	var down: int = world.nearest_nav_id(Vector3(-3.0, 0.0, -2.4))
	_check(world.nav.get_point_position(up).y > 2.0 and world.nav.get_point_position(down).y < 3.0 and up != down, "nearest nav prefers the same floor")
	var rn: Vector3 = world.random_nav_near(Vector3(0, 0, 0), 2.5)
	_check(rn.y < 1.0 and Vector2(rn.x, rn.z).length() <= 2.5, "random nav node near the centre")

func _interact_bodies(id: String) -> int:
	var n := 0
	for b in world.find_children("*", "CollisionObject3D", true, false):
		var co := b as CollisionObject3D
		if (co.collision_layer & 2) != 0 and co.has_meta(&"interact_id") and String(co.get_meta(&"interact_id")) == id: n += 1
	return n

# ------------------------------------------------------------------ walk test

func _walk_to(x: float, z: float, max_s := 12.0) -> void:
	walker.target = Vector3(x, 0, z)
	walker.active = true
	var t := 0.0
	var last := walker.global_position
	var still := 0.0
	while t < max_s:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var p := walker.global_position
		if Vector2(p.x - x, p.z - z).length() < 0.06: break
		still = still + 1.0 / 60.0 if p.distance_to(last) < 0.0005 else 0.0
		last = p
		if still > 0.6: break
	walker.active = false
	await _frames(2)

func _teleport(p: Vector3) -> void:
	walker.global_position = p
	walker.velocity = Vector3.ZERO
	await _frames(20)

func _test_walk() -> void:
	walker = Walker.new()
	walker.name = "Walker"
	get_tree().root.add_child(walker)
	await _teleport(Vector3(Layout.SPAWN.x, 0.05, Layout.SPAWN.z))
	_check(absf(walker.global_position.y) < 0.03, "spawn: standing on the floor (y %.3f)" % walker.global_position.y)
	# sofa blocks
	await _walk_to(0.25, 2.6, 3.0)
	_check(walker.global_position.z < 1.6, "sofa blocks (z %.2f)" % walker.global_position.z)
	# to the foot of the stairs
	await _walk_to(-2.2, 1.95)
	await _walk_to(-3.0, 2.2)
	_check(Vector2(walker.global_position.x + 3.0, walker.global_position.z - 2.2).length() < 0.1, "reached the foot of the stairs (%s)" % walker.global_position)
	# climb: sample heights. A capsule resting on a slope of angle a rides r (1 / cos a - 1) above the plane under its axis.
	var slope := atan(Layout.UPPER.floorY / (Layout.STAIRS.bottomZ - Layout.STAIRS.topZ))
	var ride := 0.25 * (1.0 / cos(slope) - 1.0)
	walker.target = Vector3(-3.0, 0, -2.3)
	walker.active = true
	var worst := 0.0
	var t := 0.0
	var reached := false
	while t < 8.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var p := walker.global_position
		if p.z < 1.3 and p.z > -1.5:
			var ramp := (Layout.STAIRS.bottomZ - p.z) * Layout.UPPER.floorY / (Layout.STAIRS.bottomZ - Layout.STAIRS.topZ)
			worst = maxf(worst, absf(p.y - ramp - ride))
			var tread := Layout.stair_height_at(p.x, p.z)
			if absf(p.y - tread) > 0.3: _check(false, "on the stairs: y %.3f vs tread %.3f at z %.2f" % [p.y, tread, p.z])
		if Vector2(p.x + 3.0, p.z + 2.3).length() < 0.06:
			reached = true
			break
	walker.active = false
	await _frames(10)
	_check(reached, "climbed to the landing in %.1f s (%s)" % [t, walker.global_position])
	_check(worst < 0.02, "followed the ramp plane (worst %.3f m off the %.3f m capsule ride)" % [worst, ride])
	_check(absf(walker.global_position.y - 2.75) < 0.03, "standing on the landing (y %.3f)" % walker.global_position.y)
	# the locked door blocks
	await _walk_to(-3.0, -3.6, 3.0)
	_check(walker.global_position.z > -2.6, "closed upstairs door blocks (z %.2f)" % walker.global_position.z)
	# open it (the entity / the win does this) and walk into the hallway
	var door: Handle = world.handles["door.upstairs"]
	await door.open()
	await _frames(3)
	_check((world.upper_hall as Node3D).visible, "upper hallway shown while the door is open")
	await _walk_to(-3.0, -3.6, 5.0)
	_check(walker.global_position.z < -3.4 and absf(walker.global_position.y - 2.75) < 0.03, "walked into the upper hall (%s)" % walker.global_position)
	await _walk_to(-3.0, -2.3)
	await door.close()
	await _frames(3)
	_check(not (world.upper_hall as Node3D).visible, "upper hallway hidden once the door is shut")
	# back down
	await _walk_to(-3.0, 2.2, 10.0)
	_check(absf(walker.global_position.y) < 0.03 and walker.global_position.z > 1.9, "walked back down the stairs (%s)" % walker.global_position)
	# the knee wall: the closet is not walkable, even with its door open
	await _walk_to(-2.2, 1.95)
	await _walk_to(-2.0, -1.9)
	var closet: Handle = world.handles["door.closet"]
	await closet.open()
	await _walk_to(-3.05, -2.05, 3.0)
	_check(walker.global_position.x > -2.3, "knee wall keeps the player out of the closet (x %.2f)" % walker.global_position.x)
	await closet.close()
	# the laundry nook through its doorway
	await _walk_to(-0.6, -1.55)
	await _walk_to(1.35, -2.0)
	await _walk_to(1.35, -3.5)
	_check(walker.global_position.z < -3.4 and absf(walker.global_position.y) < 0.03, "walked into the laundry nook (%s)" % walker.global_position)
	await _walk_to(2.7, -3.6)
	_check(walker.global_position.x > 2.55, "nook east side reachable (%s)" % walker.global_position)
	# the nook back wall blocks
	await _walk_to(2.7, -5.2, 3.0)
	_check(walker.global_position.z > -4.6, "nook back wall blocks (z %.2f)" % walker.global_position.z)
	walker.queue_free()
	await _frames(2)

# ------------------------------------------------------------------ handles

func _close_pose(n: Node3D, want: Transform3D) -> bool:
	return n.transform.origin.distance_to(want.origin) < 0.002 and n.transform.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()) < 0.01

func _test_handles() -> void:
	for id in world.handles:
		var h: Handle = world.handles[id]
		if id in ["powerBox.lever", "lockedBox.lock"]: continue
		_check(_close_pose(h.node, h.closed_xform), "%s starts closed" % id)
		await h.open()
		_check(h.is_open and not h.animating and _close_pose(h.node, h.open_xform), "%s opened onto its exported pose" % id)
		await h.close()
		_check(not h.is_open and _close_pose(h.node, h.closed_xform), "%s closed again" % id)
	# door colliders follow the doors
	var cs: CollisionShape3D = null
	for c in world.colliders:
		if c.tag == "door" and c.enabled: cs = c.shape
	var door: Handle = world.handles["door.upstairs"]
	await door.open()
	await _frames(2)
	_check(cs != null and cs.disabled, "open upstairs door: its collider is off")
	await door.close()
	await _frames(2)
	_check(cs != null and not cs.disabled, "closed upstairs door: its collider is on")
	# breaker lever <-> mains
	var lever = world.handles["powerBox.lever"]
	await lever.set_on(false)
	_check(world.power == false and not lever.is_on, "lever down cuts the power")
	await lever.set_on(true)
	_check(world.power == true and lever.is_on, "lever up restores the power")
	world.set_power(false)
	await _frames(2)
	_check(not lever.is_on and _close_pose(lever.node, lever.closed_xform), "breaker trips silently with the mains")
	world.set_power(true)
	await _frames(2)
	_check(lever.is_on and _close_pose(lever.node, lever.open_xform), "breaker follows a power-on")
	# padlock wheels + lid pops the lock
	var lock = world.handles["lockedBox.lock"]
	lock.set_digits("1234")
	await _frames(30)
	var okw := true
	for i in 4:
		var w: Node3D = lock.wheels[i]
		var a: float = lock.wheel_angle(i + 1)
		okw = okw and absf(angle_difference(w.rotation.x, a)) < 0.02
	_check(lock.wheels.size() == 4 and okw, "padlock wheels show 1234")
	var lid: Handle = world.handles["lockedBox.lid"]
	await lid.open()
	await _frames(40)
	_check(lid.is_open and lock.removed and lock.is_open, "opening the lid pops the padlock off")
	_check(lock.node.transform.origin.distance_to(lock.open_xform.origin) < 0.003, "padlock lies on the console")
	await lid.close()
	await lock.close()
	_check(not lock.is_open and lock.node.transform.origin.distance_to(lock.closed_xform.origin) < 0.002, "padlock reset on the staple")
	await lock.open()
	await _frames(5)
	_check(lock.is_open and lock.node.transform.origin.distance_to(lock.open_xform.origin) < 0.003, "padlock opens (shackle + drop)")
	await lock.close()

# ------------------------------------------------------------------ TV, clues, props

func _test_runtime() -> void:
	var tv = world.tv
	_check(tv.set_on(true) and tv.is_on and (tv.screen as MeshInstance3D).visible, "TV turns on with power")
	await _frames(30)
	world.set_power(false)
	await _frames(30)
	_check(not tv.is_on and not (tv.screen as MeshInstance3D).visible, "TV dies with the power")
	_check(not tv.set_on(true) and not tv.is_on, "TV refuses to turn on without power")
	world.set_power(true)
	await _frames(2)
	world.set_clue_digits({"duck": "3", "horse": "7", "clock": "5", "tv": "9"})
	var anim = world.anim
	_check(anim.clock_hours == 5.0, "grandfather clock set to 5 o'clock")
	var gf_hour: Node3D = (world.ctx.instances.grandfather as Node3D).get_node("vintage_grandfather_clock_01_HourHand")
	var a0 := float(world.meta.anim.grandfatherClock.hour.a0)
	_check(absf(angle_difference(gf_hour.rotation.z, PI / 2.0 - (5.0 / 12.0) * TAU - a0)) < 0.01, "hour hand points at 5")
	var duck_digit := (world.clues.duck as Node3D).find_child("ClueDigit_duck", true, false) as MeshInstance3D
	_check(duck_digit != null and duck_digit.visible and (duck_digit.material_override as StandardMaterial3D).albedo_texture != null, "digit under the duck")
	_check(tv.digit == "9", "TV digit set")
	var f0 := get_tree().get_frame()
	var pivot: Node3D = world.ctx.level_nodes.rockingChair_pivot
	var max_th := [0.0]
	var probe := func() -> void: max_th[0] = maxf(max_th[0], absf(pivot.rotation.x))
	get_tree().process_frame.connect(probe)
	await world.rock_chair(1.6)
	get_tree().process_frame.disconnect(probe)
	var frames := get_tree().get_frame() - f0
	_check(not anim.rocking and frames >= 90 and max_th[0] > 0.05 and pivot.rotation.x == 0.0, "rocking chair rocked (%.3f rad, %d frames) and stopped" % [max_th[0], frames])
	# fan spins with power, coasts down without
	var blades: Node3D = (world.ctx.instances.fan as Node3D).get_node("ceiling_fan_blades")
	var b0 := blades.basis
	await _frames(10)
	_check(not blades.basis.is_equal_approx(b0) and anim.fan_speed > 1.0, "fan spins")
	world.set_power(false)
	await _frames(120)
	_check(anim.fan_speed < 2.2, "fan coasts down without power (%.2f)" % anim.fan_speed)
	_check(world.nook_tube.level < 0.01, "nook tube off without power")
	world.set_power(true)
	await _frames(240)
	_check(world.nook_tube.level > 0.5, "nook tube relit after the starter (%.2f)" % world.nook_tube.level)
	world.reset_after_caught()
	_check(not world.handles["door.upstairs"].is_open and world.handles["door.upstairs"].locked, "reset keeps the door shut and locked")
