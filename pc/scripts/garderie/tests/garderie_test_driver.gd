## Checks of test_garderie.gd (loaded at runtime so it can use the autoloads). See test_garderie.gd.
extends Node

const TestWorld := preload("res://scripts/garderie/tests/garderie_test_world.gd")
const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Ride := preload("res://scripts/garderie/garderie_ride.gd")
const LAYER_WORLD := 1
const LAYER_INTERACT := 2

class FakeInteraction extends Node:
	var entries := {}
	func register(e: Dictionary) -> Callable:
		entries[e.id] = e
		return func() -> void: entries.erase(e.id)

var _log = null
var _tree: SceneTree = null
var _fails: Array[String] = []
var _checks := 0
var _world: Node3D
var _g: Node3D

func run(tree: SceneTree, log) -> void:
	_tree = tree
	_log = log
	_run()

func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(what)
		printerr("FAIL: ", what)

func _run() -> void:
	var root := Node3D.new()
	root.name = "Main"
	get_tree().root.add_child(root)
	_world = TestWorld.new()
	_world.name = "World"
	root.add_child(_world)
	_world.build_level()
	await get_tree().process_frame
	var fake := FakeInteraction.new()
	fake.name = "Interaction"
	root.add_child(fake)
	Game.interaction = fake
	var t0 := Time.get_ticks_msec()
	_g = Garderie.new()
	root.add_child(_g)
	await _g.build(_world)
	var ms := Time.get_ticks_msec() - t0
	print("[garderie] build ", ms, " ms  stats ", _g.stats)
	print("[garderie] carve ", _g.carve_report)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_test_carve()
	await _test_doorway()
	await get_tree().physics_frame
	_test_path()
	_test_nav()
	_test_slides()
	_test_hide()
	_test_interact(fake)
	_test_ground_api()
	check(ms < 3000, "build() under 3 s (%d ms)" % ms)
	for e in _log.errors:
		print("logged error: ", e)
	check(_log.errors.is_empty(), "no error logged (%d)" % _log.errors.size())
	print("[garderie] %d checks, %d failed, %d warnings logged (exporter assemble warnings included)" % [_checks, _fails.size(), _log.warnings])
	if _fails.is_empty():
		print("GARDERIE TEST OK")
		get_tree().quit(0)
	else:
		print("GARDERIE TEST FAILED: ", _fails)
		get_tree().quit(1)

# ---------------------------------------------------------------- doorway

func _test_carve() -> void:
	var rep: Dictionary = _g.carve_report
	for n in ["arch_wall", "arch_trim", "arch_shadowCasters"]:
		check(n in rep.get("meshes", []), "mesh carved: %s" % n)
	check(not (rep.get("shapes", []) as Array).is_empty(), "west wall collider split")
	# no triangle of a carved mesh left inside the opening
	var box := AABB(GL.CARVE_MIN + Vector3(0.002, 0.01, 0.002), GL.CARVE_MAX - GL.CARVE_MIN - Vector3(0.004, 0.02, 0.004))
	var inside := 0
	for mi in _world.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.has_meta("garderie_carved"):
			continue
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in I.size() / 3:
				var c := (m.global_transform * V[I[t * 3]] + m.global_transform * V[I[t * 3 + 1]] + m.global_transform * V[I[t * 3 + 2]]) / 3.0
				if box.has_point(c):
					inside += 1
	check(inside == 0, "no wall triangle left in the doorway (%d)" % inside)
	# idempotent re-carve
	var rep2: Dictionary = _g.recarve()
	check((rep2.get("meshes", []) as Array).is_empty() and (rep2.get("shapes", []) as Array).is_empty(), "recarve() is idempotent")

func _ray(a: Vector3, b: Vector3, mask := LAYER_WORLD) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	return _g.get_world_3d().direct_space_state.intersect_ray(q)

func _test_doorway() -> void:
	_g.set_door_open(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for y in [0.15, 0.8, 1.5, 1.9]:
		for z in [1.82, 2.1, 2.36]:
			var hit := _ray(Vector3(-3.0, y, z), Vector3(-4.3, y, z))
			check(hit.is_empty(), "ray through the doorway at y %.2f z %.2f (hit %s)" % [y, z, hit.get("collider")])
	for p in [Vector2(0.6, 1.55), Vector2(1.6, 1.6), Vector2(0.6, 2.62), Vector2(1.5, 2.66), Vector2(2.2, 2.1), Vector2(2.4, 1.9)]:
		var hit := _ray(Vector3(-3.0, p.x, p.y), Vector3(-4.3, p.x, p.y))
		check(not hit.is_empty() and float(hit.position.x) > -3.8, "wall blocks beside / above the doorway at y %.2f z %.2f" % [p.x, p.y])
	# La Gardienne's sight (LAYER_SIGHT): through the open doorway, not through the wall beside it nor our walls
	check(not _world.line_blocked(Vector3(-2.0, 1.5, 2.1), Vector3(-6.0, 1.5, 2.1)), "sight through the open doorway")
	check(_world.line_blocked(Vector3(-2.0, 1.5, 1.3), Vector3(-6.0, 1.5, 1.3)), "sight blocked by the wall beside the doorway")
	check(_world.line_blocked(Vector3(-14.0, 1.5, 2.1), Vector3(-14.0, 1.5, 7.0)), "sight blocked by the vestibule wall")
	check(_world.line_blocked(Vector3(-8.0, 1.5, 2.1), Vector3(-8.0, 1.5, 4.0)), "sight blocked by the corridor wall")
	check(not _world.line_blocked(Vector3(-22.6, 0.6, 3.0), Vector3(-28.0, 0.6, 3.0)), "sight through the play frame netting")
	_g.set_door_open(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := _ray(Vector3(-3.0, 1.0, 2.1), Vector3(-4.3, 1.0, 2.1))
	check(not hit.is_empty(), "closed door blocks the doorway")
	check(_world.line_blocked(Vector3(-2.0, 1.5, 2.1), Vector3(-6.0, 1.5, 2.1)), "closed door blocks sight")
	_g.set_door_open(true)

# ---------------------------------------------------------------- floors along the path

func _ground(x: float, z: float, from_y: float) -> float:
	var hit := _ray(Vector3(x, from_y + 0.9, z), Vector3(x, from_y - 2.5, z))
	return float(hit.position.y) if not hit.is_empty() else NAN

func _path_points() -> Array:
	var ids := ["gd_door", "gd_corrMid", "gd_corrEnd", "gd_vestIn", "gd_vest", "gd_vestOut", "gd_landing", "gd_stepsTop", "gd_stepsBottom",
		"gd_hallMidEast", "gd_hallEast", "gd_neCorner", "gd_waveBottom", "gd_neNorth", "gd_northAisle", "gd_nwCorner", "gd_westAisle", "gd_exitDoor"]
	var pts: Array = [Vector3(-2.2, 0.0, 2.1)]
	for id in ids:
		pts.append(_g.nav_nodes[id])
	return pts

func _test_path() -> void:
	var pts := _path_points()
	var bad := 0
	var prev := 0.0
	var n := 0
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var L := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		var steps := maxi(1, int(ceil(L / 0.5)))
		for s in steps:
			var p := a.lerp(b, float(s) / float(steps))
			var expect: float = _g.ground_height_at(p.x, p.z)
			var gy := _ground(p.x, p.z, maxf(p.y, expect))
			n += 1
			if is_nan(gy) or absf(gy - expect) > 0.06 or absf(gy - prev) > 0.32:
				bad += 1
				if bad < 8:
					printerr("  ground at (%.2f, %.2f): %.3f expected %.3f prev %.3f" % [p.x, p.z, gy, expect, prev])
			prev = gy if not is_nan(gy) else prev
	check(bad == 0, "floor heights along the path (%d probes, %d bad)" % [n, bad])
	# player capsule clearance along the same path (no collider blocking the corridor, doorway, steps, aisles)
	var blocked := _capsule_sweep(pts, 0.25, 1.75, 0.3)
	check(blocked.is_empty(), "player capsule clear along the path %s" % [blocked.slice(0, 6)])

func _capsule_sweep(pts: Array, r: float, h: float, step: float) -> Array:
	var shape := CapsuleShape3D.new()
	shape.radius = r
	shape.height = h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = LAYER_WORLD
	var out: Array = []
	var space := _g.get_world_3d().direct_space_state
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var L := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		var steps := maxi(1, int(ceil(L / step)))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / float(steps))
			var gy: float = _g.ground_height_at(p.x, p.z)
			# on ramps the capsule's round bottom needs a little more lift than on flat floors
			var lift := 0.16 if absf(gy - _g.ground_height_at(p.x + 0.3, p.z)) > 0.02 or absf(gy - _g.ground_height_at(p.x - 0.3, p.z)) > 0.02 else 0.04
			q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, gy + lift + h * 0.5, p.z))
			var hits := space.intersect_shape(q, 4)
			if not hits.is_empty():
				out.append("(%.2f, %.2f): %s" % [p.x, p.z, (hits[0].collider as Node).get_path() if hits[0].collider is Node else hits[0].collider])
	return out

# ---------------------------------------------------------------- navigation

func _test_nav() -> void:
	var nodes: Dictionary = _g.nav_nodes.duplicate()
	for id in ["stairsBottom", "swCorner"]:
		var n: Dictionary = Layout.NAV_NODES[id]
		nodes[id] = Vector3(n.x, 0.0, n.z)
	var bad: Array = []
	for l in _g.nav_links:
		var a: Variant = nodes.get(l[0])
		var b: Variant = nodes.get(l[1])
		if a == null or b == null:
			bad.append("%s-%s unknown node" % l)
			continue
		var blocked := _capsule_sweep([a, b], 0.3, 1.72, 0.25)
		if not blocked.is_empty():
			bad.append("%s-%s blocked %s" % [l[0], l[1], blocked[0]])
		# floor continuity along the link
		var steps := maxi(1, int(ceil((a as Vector3).distance_to(b) / 0.25)))
		var prev: float = (a as Vector3).y
		for s in steps + 1:
			var p: Vector3 = (a as Vector3).lerp(b, float(s) / float(steps))
			var gy := _ground(p.x, p.z, p.y)
			if is_nan(gy) or absf(gy - prev) > 0.32:
				bad.append("%s-%s floor gap at (%.2f, %.2f) %.2f" % [l[0], l[1], p.x, p.z, gy])
				break
			prev = gy
	for id in _g.nav_nodes:
		var p: Vector3 = _g.nav_nodes[id]
		var gy := _ground(p.x, p.z, p.y)
		if absf(gy - p.y) > 0.05:
			bad.append("node %s y %.2f floor %.2f" % [id, p.y, gy])
	for b in bad:
		printerr("  nav: ", b)
	check(bad.is_empty(), "every nav link walkable (%d links, %d problems)" % [_g.nav_links.size(), bad.size()])
	var linked := {}
	for l in _g.nav_links:
		linked[l[0]] = true
		linked[l[1]] = true
	check(linked.has("stairsBottom") and linked.has("swCorner"), "nav links into the main room graph")
	for id in _g.nav_nodes:
		check(linked.has(id), "nav node %s linked" % id)

# ---------------------------------------------------------------- slides, hide spot, interaction

func _test_slides() -> void:
	for id in ["wave", "spiral"]:
		check(_g.ctx.slides.has(id), "slide %s exists" % id)
		if not _g.ctx.slides.has(id):
			continue
		var s: Dictionary = _g.ctx.slides[id]
		var sim := Ride.simulate(s)
		print("[garderie] slide %s: %.1f m, %.1f s, vmax %.1f m/s, v_end %.1f, exit %s" % [id, (s.curve as Curve3D).get_baked_length(), sim.duration, sim.vmax, sim.v_end, sim.exit_pos])
		var ex: Vector3 = sim.exit_pos
		var gy := _ground(ex.x, ex.z, ex.y + 0.3)
		check(absf(gy - GL.HALL) < 0.03, "%s ride ends on the hall floor (%.3f)" % [id, gy])
		check(_capsule_sweep([ex, ex], 0.25, 1.75, 1.0).is_empty(), "%s exit position clear for the player" % id)
		check(float(sim.duration) > 1.5 and float(sim.duration) < 12.0, "%s ride duration %.1f s" % [id, sim.duration])
		check(float(sim.vmax) > 2.0, "%s ride gets some speed (%.1f m/s)" % [id, sim.vmax])
		# the rider's path stays above the slide surface collider (no clipping through)
		var curve: Curve3D = s.curve
		var L := curve.get_baked_length()
		var under := 0
		var d := 0.3
		while d < L - 0.3:
			var p := curve.sample_baked(d)
			var hit := _ray(p + Vector3(0, 0.25, 0), p - Vector3(0, 0.6, 0))
			if hit.is_empty() or float(hit.position.y) > p.y + 0.12:
				under += 1
			d += 0.5
		check(under == 0, "%s rider curve rests on the slide (%d bad samples)" % [id, under])
		var top: Vector3 = s.top
		var gtop := _ground(top.x, top.z, top.y)
		check(absf(gtop - GL.L3) < 0.05, "%s start reachable on deck L3 (%.2f)" % [id, gtop])

func _test_hide() -> void:
	check(_g.hide_spots.size() == 1, "one hide spot")
	if _g.hide_spots.is_empty():
		return
	var s: Dictionary = _g.hide_spots[0]
	for k in ["id", "door", "hide_pos", "hide_yaw", "exit_pos"]:
		check(s.has(k), "hide spot has %s" % k)
	var ex: Vector3 = s.exit_pos
	check(absf(_ground(ex.x, ex.z, 0.5)) < 0.03, "hide exit on the landing floor (y 0)")
	check(_capsule_sweep([ex, ex], 0.25, 1.75, 1.0).is_empty(), "hide exit clear")
	var hp: Vector3 = s.hide_pos
	check(hp.y >= 0.6, "hide eye height >= 0.6 (player convention)")
	var up := _ray(hp, hp + Vector3(0, 1.0, 0))
	var dn := _ray(hp, hp - Vector3(0, 1.0, 0))
	check(not up.is_empty() and float(up.position.y) < hp.y + 0.8 and not dn.is_empty(), "hide position inside the tube")
	check(absf(hp.z - ex.z) < 0.01, "hide pos and exit pos aligned (player hide animation)")

func _test_interact(fake: FakeInteraction) -> void:
	for id in ["garderie.door", "garderie.tunnel.hide", "garderie.tunnel.exit", "garderie.slide.wave", "garderie.slide.spiral"]:
		check(fake.entries.has(id), "interactable registered: %s" % id)
	if fake.entries.has("garderie.door"):
		var p: Variant = fake.entries["garderie.door"].prompt
		check(p is Callable and String((p as Callable).call()) in ["Ouvrir la porte", "Fermer la porte"], "door prompt in French")
	for id in ["garderie.slide.wave", "garderie.slide.spiral", "garderie.tunnel.hide"]:
		if not fake.entries.has(id):
			continue
		var node: Node3D = fake.entries[id].node
		var bodies := node.find_children("*", "CollisionObject3D", true, false)
		check(bodies.any(func(b): return (b as CollisionObject3D).collision_layer & LAYER_INTERACT), "%s has an INTERACT body" % id)

func _test_ground_api() -> void:
	check(absf(_g.ground_height_at(-8.0, 2.1) - 0.0) < 0.001, "ground_height_at corridor")
	check(absf(_g.ground_height_at(-28.0, 6.0) - GL.HALL) < 0.001, "ground_height_at hall")
	check(absf(_g.ground_height_at(1.0, 1.0) - 0.0) < 0.001, "ground_height_at falls back to the house")
	check(absf(_g.ground_height_at(-26.0, 0.0, 0.2) - GL.L1) < 0.001, "ground_height_at deck L1 with prev_y")
	check(_g.surface_at(Vector3(-6, 0, 2.1)) == "concrete" and _g.surface_at(Vector3(-28, GL.HALL, 6)) == "foam", "surface_at")
