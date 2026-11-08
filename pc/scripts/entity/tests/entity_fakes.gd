## Test doubles for the entity tests (entity_test_driver.gd). They implement the public API of the other modules (world,
## player, puzzles, lighting) just enough for La Gardienne; nothing here is used by the game itself.
extends RefCounted

const LAYER_WORLD := 1
const META := "res://assets/generated/level_meta.json"

## World double: the web level's collision boxes (level_meta.json colliders[]), the two doors as real Handles whose leaves
## carry a collision box, Layout nav graph, Layout ground heights, physics LOS.
class FakeWorld extends Node3D:
	var power := true
	var handles := {}
	var items := {}
	var clues := {}
	var tv: Node = null
	var hide_spots: Array = []
	var lighting: Node = null
	var nav := AStar3D.new()
	var nav_ids := {}
	var extra_bodies: Array[StaticBody3D] = []

	func build() -> void:
		var meta := {}
		var f := FileAccess.open(META, FileAccess.READ)
		if f: meta = JSON.parse_string(f.get_as_text())
		var n := 0
		for c in meta.get("colliders", []):
			if not c.get("enabled", true) or String(c.get("tag", "")) == "door": continue
			var mn := Vector3(c.min[0], c.min[1], c.min[2])
			var mx := Vector3(c.max[0], c.max[1], c.max[2])
			add_box((mn + mx) * 0.5, mx - mn, "col_%s_%d" % [c.tag, n])
			n += 1
		# floors (only the player double would need them; kept for LOS realism under the stairs)
		add_box(Vector3(0, -0.05, 0), Vector3(7.4, 0.1, 5.9), "floor")
		var H := load("res://scripts/world/handle.gd")
		# upstairs door: hinge (-3.45, 2.75, -2.75), leaf 0.85 x 2.03, opens toward the landing (meta closed/open transforms)
		var up := _door("door_upstairs", Transform3D(Basis.IDENTITY, Vector3(-3.45, 2.75, -2.75)),
			Transform3D(Basis(Vector3(-0.0292, 0, 0.999574), Vector3(0, 1, 0), Vector3(-0.999574, 0, -0.0292)), Vector3(-3.45, 2.75, -2.75)),
			Vector3(0.425, 1.015, -0.0225), Vector3(0.85, 2.03, 0.045))
		var hu = H.new()
		hu.id = "door.upstairs"
		hu.node = up
		hu.closed_xform = up.transform
		hu.open_xform = up.get_meta("open")
		hu.duration = 1.1
		hu.locked = true
		handles["door.upstairs"] = hu
		# closet door: hinge (-2.5, 0, -2.36), leaf 0.62 wide along +Z when closed
		var cl := _door("door_closet", Transform3D(Basis.IDENTITY, Vector3(-2.5, 0, -2.36)),
			Transform3D(Basis(Vector3(0.070737, 0, -0.997495), Vector3(0, 1, 0), Vector3(0.997495, 0, 0.070737)), Vector3(-2.5, 0, -2.36)),
			Vector3(0.0, 0.95, 0.31), Vector3(0.04, 1.9, 0.62))
		var hc = H.new()
		hc.id = "door.closet"
		hc.node = cl
		hc.closed_xform = cl.transform
		hc.open_xform = cl.get_meta("open")
		hc.duration = 0.6
		handles["door.closet"] = hc
		var C: Dictionary = Layout.CLOSET
		hide_spots = [{"id": "closet", "door": hc, "hide_pos": Vector3(C.hidePos.x, 0.0, C.hidePos.z), "hide_yaw": C.hideYaw,
			"exit_pos": Vector3(C.exitPos.x, 0.0, C.exitPos.z)}]
		for id in Layout.NAV_NODES:
			var nd: Dictionary = Layout.NAV_NODES[id]
			var y := float(Layout.UPPER.floorY) if nd.get("upper", false) else Layout.ground_height_at(nd.x, nd.z)
			var i := nav_ids.size()
			nav_ids[id] = i
			nav.add_point(i, Vector3(nd.x, y, nd.z))
		for l in Layout.NAV_LINKS: nav.connect_points(nav_ids[l[0]], nav_ids[l[1]])

	func _door(nm: String, closed: Transform3D, open: Transform3D, center: Vector3, size: Vector3) -> Node3D:
		var d := Node3D.new()
		d.name = nm
		d.transform = closed
		d.set_meta("open", open)
		add_child(d)
		var b := StaticBody3D.new()
		b.collision_layer = LAYER_WORLD
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = center
		b.add_child(cs)
		d.add_child(b)
		return d

	func add_box(center: Vector3, size: Vector3, nm := "box") -> StaticBody3D:
		var b := StaticBody3D.new()
		b.name = nm
		b.collision_layer = LAYER_WORLD
		b.collision_mask = 0
		b.position = center
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)
		add_child(b)
		return b

	func set_power(on: bool) -> void:
		power = on
		Events.power_changed.emit(on)
	func set_clue_digits(_d: Dictionary) -> void: pass
	func ground_height_at(x: float, z: float, prev_y := NAN) -> float: return Layout.ground_height_at(x, z, prev_y)
	func line_blocked(from: Vector3, to: Vector3) -> bool:
		var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
		return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	func nearest_nav_id(pos: Vector3) -> int: return nav.get_closest_point(pos)
	func nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		var p := nav.get_point_path(nearest_nav_id(from), nearest_nav_id(to))
		p.append(to)
		return p
	func random_nav_near(pos: Vector3, r := 3.0) -> Vector3:
		var c := []
		for id in nav.get_point_ids():
			var p := nav.get_point_position(id)
			if p.y < 1.0 and Vector2(p.x - pos.x, p.z - pos.z).length() <= r: c.append(p)
		return c.pick_random() if not c.is_empty() else pos
	func reset_after_caught() -> void: pass

class FakeLighting extends Node3D:
	var stress := 0.0
	var max_stress := 0.0
	var strip := 0.0
	var strip_calls := 0
	func set_stress(v: float) -> void:
		stress = v
		max_stress = maxf(max_stress, v)
	func door_strip_occluded(v: float) -> void:
		strip = v
		strip_calls += 1

## Player double: feet at global_position, camera at eye height, scripted motion (walk_to) instead of input.
class FakePlayer extends Node3D:
	var camera := Camera3D.new()
	var yaw := 0.0
	var pitch := 0.0
	var enabled := true
	var camera_override := false
	var hidden := false
	var hide_spot = null
	var visibility := 0.7
	var flashlight := {"has": true, "on": false, "battery": 100.0, "light": SpotLight3D.new()}
	var goal := Vector3.INF
	var goal_speed := 1.9
	var override_frames := 0

	func _ready() -> void:
		camera.position = Vector3(0, 1.62, 0)
		add_child(camera)
		camera.current = true
		camera.add_child(flashlight.light)
		flashlight.light.position = Vector3(0.15, -0.16, 0.02)
		flashlight.light.light_energy = 0.0
		flashlight.light.spot_angle = 24.0

	func _process(dt: float) -> void:
		if camera_override: override_frames += 1
		if not enabled or hidden or goal == Vector3.INF: return
		var to := goal - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.05:
			goal = Vector3.INF
			return
		global_position += to / d * minf(d, goal_speed * dt)
		global_position.y = Layout.ground_height_at(global_position.x, global_position.z, global_position.y)
		if not camera_override: camera.rotation = Vector3(pitch, 0, 0)
		rotation.y = atan2(-to.x, -to.z)

	func walk_to(p: Vector3, spd := 1.9) -> void:
		goal = p
		goal_speed = spd
	func teleport(pos: Vector3, y: float, p := 0.0) -> void:
		global_position = pos
		yaw = y
		pitch = p
		rotation.y = y
		goal = Vector3.INF
	func get_visibility() -> float: return 0.0 if hidden else visibility
	func eye_position() -> Vector3: return camera.global_position
	func give_flashlight() -> void: flashlight.has = true
	func set_flashlight_on(on: bool) -> void:
		flashlight.on = on
		flashlight.light.light_energy = 13.37 if on else 0.0
	func enter_hide(spot) -> void:
		hidden = true
		hide_spot = spot
		goal = Vector3.INF
		global_position = spot.hide_pos
		Events.player_hide.emit(true, String(spot.id))
	func exit_hide() -> void:
		hidden = false
		hide_spot = null
		Events.player_hide.emit(false, "")
	func respawn() -> void:
		teleport(Vector3(Layout.SPAWN.x, 0.0, Layout.SPAWN.z), Layout.SPAWN.yaw)
		hidden = false
		hide_spot = null
	func flinch(_s := 1.0) -> void: pass
	func reset_after_caught() -> void:
		respawn()
		camera_override = false
		enabled = true
		camera.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.62, 0))

class FakePuzzles extends Node:
	var flags := {"door_unlocked": false, "door_opened": false, "won": false}
	var resets := 0
	func reset_after_caught() -> void: resets += 1
