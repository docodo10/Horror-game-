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
	await _test_deferred_registration(fake)
	_test_ground_api()
	_test_lighting()
	_test_dressing()
	await _test_physics()
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

## main.gd builds the garderie BEFORE it creates the Interaction node: the entries must be registered the moment that
## node is ready (before the puzzles register the closet, so the tunnel's "Sortir" entry comes first).
func _test_deferred_registration(first: Node) -> void:
	first.get_parent().remove_child(first)
	first.queue_free()
	Game.interaction = null
	_g.set("_registered_with", null)
	_g.call("_register_or_wait")
	var late := FakeInteraction.new()
	late.name = "Interaction"
	_g.get_parent().add_child(late)
	await get_tree().process_frame
	check(late.entries.has("garderie.door") and late.entries.has("garderie.tunnel.exit"), "entries registered when the Interaction node appears later")

# ---------------------------------------------------------------- lighting, dressing

func _test_lighting() -> void:
	var working := 0
	var shadowed := 0
	for l in _g.ctx.lights:
		var lt: Light3D = l.light
		if l.state == "dead" or l.kind == "spill":
			continue
		working += 1
		if lt.shadow_enabled:
			shadowed += 1
		if lt is SpotLight3D and l.kind == "highbay":
			var s := lt as SpotLight3D
			check(s.spot_angle >= 58.0 and s.spot_angle <= 62.0, "high-bay cone 58-62° (%.0f)" % s.spot_angle)
		if lt is SpotLight3D and l.kind == "troffer":
			var s := lt as SpotLight3D
			check(absf(s.spot_angle - 65.0) < 0.5 and absf(s.spot_angle_attenuation - 1.2) < 0.01 and s.light_projector != null, "troffer 65°, attenuation 1.2, louver projector")
		if l.kind != "bulb":
			check(absf(lt.light_size - 0.2) < 0.001 and absf(lt.shadow_blur - 1.0) < 0.001, "%s light_size 0.2, shadow_blur 1.0" % l.kind)
			check(lt.distance_fade_enabled and absf(lt.distance_fade_begin - 20.0) < 0.01 and absf(lt.distance_fade_shadow - 12.0) < 0.01, "%s distance fade 20 / shadow 12 m" % l.kind)
			var lc := lt.light_color
			check(lc.r >= lc.b and lc.r >= lc.g, "%s white is neutral-warm, not bluish (%s)" % [l.kind, lc])
	check(working > 0 and shadowed == working, "every working fixture casts shadows (%d / %d)" % [shadowed, working])
	# key lights of the dark state: SORTIE signs + our neon, shadowed, energy 1.5-2.5, range 4-6 m once the power is cut
	_g.set_power(false)
	var keys := 0
	for s in _g.ctx.signs:
		var sl := s as SpotLight3D
		if sl == null:
			continue
		keys += 1
		check(sl.shadow_enabled and sl.light_energy >= 1.5 and sl.light_energy <= 2.5 and sl.spot_range >= 4.0 and sl.spot_range <= 6.0,
			"key light %s: shadows, energy %.1f, range %.1f" % [sl.name, sl.light_energy, sl.spot_range])
	check(keys >= 4 and not _g.ctx.neon.is_empty(), "SORTIE signs + neon key lights (%d)" % keys)
	var lit_after := 0
	for l in _g.ctx.lights:
		if (l.light as Light3D).visible:
			lit_after += 1
	var signs_on: bool = _g.ctx.signs.all(func(s): return (s as Light3D).visible)
	check(lit_after == 0 and signs_on, "power cut: fixtures off (%d left), key lights on" % lit_after)
	_g.set_power(true)
	var fog := _g.find_child("HallDust", true, false) as FogVolume
	check(fog != null and absf((fog.material as FogMaterial).density - 0.025) < 0.0005, "HallDust density 0.025")

func _test_dressing() -> void:
	var counts: Dictionary = _g.dressing.counts
	check(int(counts.get("debris", 0)) >= 300 and int(counts.get("debris", 0)) <= 600, "300-600 debris instances (%d)" % counts.get("debris", 0))
	check(int(counts.get("decals", 0)) >= 25 and int(counts.get("decals", 0)) <= 45, "25-40ish decals (%d)" % counts.get("decals", 0))
	check(int(counts.get("motes", 0)) >= 3, "dust motes under 3-4 fixtures (%d)" % counts.get("motes", 0))
	var decals: Array = _g.find_children("*", "Decal", true, false)
	check(decals.all(func(d): return (d as Decal).texture_albedo != null and (d as Decal).distance_fade_enabled), "decals textured, distance-faded")
	var mmis: Array = _g.find_children("Debris_*", "MultiMeshInstance3D", true, false)
	check(mmis.all(func(m): return (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and (m as GeometryInstance3D).visibility_range_end > 0.0), "debris MultiMeshes: no shadows, visibility range")
	var wraps: Array = _g.find_children("*_wraps_*", "MeshInstance3D", true, false)
	var lods := 0
	for w in wraps:
		var m := (w as MeshInstance3D).mesh as ArrayMesh
		if m != null and m.get_surface_count() > 0:
			lods += 1
	check(wraps.size() >= 6, "hero padded columns built as LOD'd meshes (%d)" % wraps.size())
	_g.apply_quality("low")
	var low_ok: bool = not _g.ctx.signs.any(func(s): return (s as Light3D).shadow_enabled and String((s as Node).name) != "NeonSign")
	_g.apply_quality("high")
	var high_ok: bool = _g.ctx.signs.all(func(s): return (s as Light3D).shadow_enabled)
	check(low_ok and high_ok, "apply_quality low / high")

# ---------------------------------------------------------------- physics

var _fake: CharacterBody3D = null

func _make_fake() -> CharacterBody3D:
	var f := CharacterBody3D.new()
	f.name = "FakePlayer"
	f.collision_layer = 4
	f.collision_mask = LAYER_WORLD
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.25
	sh.height = 1.75
	cs.shape = sh
	cs.position = Vector3(0, 0.875, 0)
	f.add_child(cs)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.62, 0)
	f.add_child(cam)
	_g.get_parent().add_child(f)
	cam.current = true
	return f

var _body_hits := 0

func _walk(v: Vector3, frames: int) -> void:
	for i in frames:
		_fake.velocity = v + Vector3(0, -2.0, 0)
		_fake.move_and_slide()
		for k in _fake.get_slide_collision_count():
			var kc := _fake.get_slide_collision(k)
			if kc.get_collider() is RigidBody3D:
				_body_hits += 1
				if _body_hits < 4:
					print("[dbg] hit %s n %s rem %s vel %s script %s" % [(kc.get_collider() as Node).name, kc.get_normal(), kc.get_remainder(), _fake.velocity, (kc.get_collider() as Object).get_script()])
		await get_tree().physics_frame

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func _test_physics() -> void:
	var ph = _g.physics
	check(ph != null, "physics module built")
	if ph == null:
		return
	var P: Dictionary = GL.PIT
	_fake = _make_fake()
	ph.actor = _fake
	# balls never cast shadows
	var meshes: Array = ph.get_node("BallPool").find_children("Mesh", "MeshInstance3D", true, false)
	check(not meshes.is_empty() and meshes.all(func(m): return (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "physics balls cast no shadows")
	check(ph.stats().pool >= 160 and ph.stats().pool <= 240, "ball pool 160-240 (%d)" % ph.stats().pool)
	# into the pit: the bubble promotes the balls around the legs
	_fake.global_position = Vector3(-27.6, GL.HALL, 6.6)
	await _wait(45)
	var promoted: int = ph.active_balls()
	print("[garderie] physics: %d balls promoted around the feet" % promoted)
	check(promoted >= 60 and promoted <= GL.BALL_POOL, "ball bubble around the player (%d rigid balls)" % promoted)
	# wade 1.6 m east through the pit
	var sample := _first_active_ball_pos(ph)
	await _walk(Vector3(1.0, 0, 0), 96)
	var s1 = ph.stats()
	print("[garderie] physics after wading: ", s1)
	check(int(s1.pushes) > 0, "the legs push the balls (%d nudges)" % s1.pushes)
	check(int(s1.promoted) > promoted, "the bubble follows the player (%d promotions)" % s1.promoted)
	# settle
	_fake.velocity = Vector3.ZERO
	await _wait(300)
	var awake: int = ph.awake_balls()
	if awake > 0:
		var speeds: Array = []
		for slot in ph._used:
			var b: RigidBody3D = ph._pool[slot]
			if not b.sleeping:
				speeds.append([snappedf(b.linear_velocity.length(), 0.001), snappedf(b.angular_velocity.length(), 0.01), b.global_position, b.get_contact_count()])
		speeds.sort_custom(func(a, b): return a[0] > b[0])
		print("[dbg] awake balls (v, w, pos, contacts): ", speeds.slice(0, 6), " ... ", speeds.slice(speeds.size() - 3))
	check(awake == 0, "balls settle and sleep (%d still awake after 5 s)" % awake)
	check(_balls_inside(ph, P), "no ball below the pit bed / floor or through a wall after wading")
	# tunnelling stress: slam balls into the bed and into the pit's north wall
	var thrown := 0
	for slot in ph._used:
		var b: RigidBody3D = ph._pool[slot]
		if thrown < 10:
			b.global_position = Vector3(b.global_position.x, GL.HALL + 0.75, b.global_position.z)
			b.linear_velocity = Vector3(0.0, -9.0, 0.0)
		elif thrown < 20:
			b.global_position = Vector3(clampf(b.global_position.x, float(P.x0) + 0.5, float(P.x1) - 0.5), GL.HALL + 0.47, float(P.z0) + 0.6)
			b.linear_velocity = Vector3(0.0, 0.0, -8.0)
		else:
			break
		b.sleeping = false
		thrown += 1
	await _wait(150)
	check(_balls_inside(ph, P), "no tunnelling: balls slammed at 8-9 m/s stay in the pit (escaped %d)" % ph.escaped)
	check(ph.escaped == 0, "no ball reset for leaving the area (%d)" % ph.escaped)
	check(int(ph.stats().impacts) > 0, "impacts play sounds (%d)" % ph.stats().impacts)
	# leave the pit (still in the hall): every rigid ball sleeps and goes back into its MultiMesh
	_fake.global_position = Vector3(-21.0, GL.HALL, -0.5)
	await _wait(240)
	check(ph.active_balls() == 0, "bodies sleep and return to the MultiMesh when the player leaves (%d left)" % ph.active_balls())
	# foam blocks: pushable, never through a wall, asleep afterwards
	var blocks: Array = ph.blocks()
	check(blocks.size() >= 6, "pushable foam blocks (%d)" % blocks.size())
	var big: RigidBody3D = null
	for b in blocks:
		if (b as Node).name.begins_with("Block6"):
			big = b
	check(big != null and big.mass >= 1.2 and big.mass <= 3.0 and absf(big.physics_material_override.friction - 0.9) < 0.01 and absf(big.angular_damp - 2.0) < 0.01,
		"foam block 1.2-3 kg, friction 0.9, angular damp 2")
	if big != null:
		var z0b := big.global_position.z
		_fake.global_position = Vector3(big.global_position.x, GL.HALL, z0b + 0.95)
		await _wait(3)
		await _walk(Vector3(0, 0, -1.4), 90)
		var moved := z0b - big.global_position.z
		print("[garderie] physics: block pushed %.2f m (%d contacts with rigid bodies, fake at %s)" % [moved, _body_hits, _fake.global_position])
		check(moved > 0.4, "the player pushes a foam block (%.2f m)" % moved)
	# jam a toddler block against the west wall: it must not go through
	var tb: RigidBody3D = blocks[0]
	_fake.global_position = Vector3(tb.global_position.x + 0.8, GL.HALL, tb.global_position.z)
	await _wait(3)
	await _walk(Vector3(-1.9, 0, 0), 150)
	check(tb.global_position.x > float(GL.HALLB.x0) + 0.1 and tb.global_position.y > GL.HALL - 0.02, "a block jammed against the wall stays in the hall (x %.2f)" % tb.global_position.x)
	await _wait(240)
	check(blocks.all(func(b): return (b as RigidBody3D).sleeping), "blocks sleep once at rest")
	# out of the hall: everything released
	_fake.global_position = Vector3(-8.0, 0.0, 2.1)
	await _wait(30)
	check(ph.active_balls() == 0 and not ph._active, "physics idle outside the hall")
	ph.actor = null
	_fake.queue_free()

func _first_active_ball_pos(ph) -> Vector3:
	for slot in ph._used:
		return (ph._pool[slot] as Node3D).global_position
	return Vector3.ZERO

## Pit balls stay inside the pit's walls (or spilled through the gate onto the floor east of it), floor balls on
## the floor inside the hall; none below the floor / bed.
func _balls_inside(ph, P: Dictionary) -> bool:
	var H: Dictionary = GL.HALLB
	for slot in ph._used:
		var b = ph._pool[slot]
		var p: Vector3 = (b as Node3D).global_position
		var bad := p.y < GL.HALL + 0.02 or p.x < float(H.x0) or p.z < float(H.z0) or p.z > float(H.z1)
		var t: float = P.wall_t
		var in_outer := p.x > float(P.x0) and p.x < float(P.x1) and p.z > float(P.z0) and p.z < float(P.z1)
		var in_inner := p.x > float(P.x0) + t and p.x < float(P.x1) - t and p.z > float(P.z0) + t and p.z < float(P.z1) - t
		if in_inner and p.y < GL.HALL + 0.2:
			bad = true              # under the bed
		var in_gate := p.z > float(P.gate_z0) and p.z < float(P.gate_z1)
		if in_outer and not in_inner and not in_gate and p.y < GL.HALL + float(P.wall_h) - 0.01:
			bad = true              # inside a pit wall
		if bad:
			printerr("  ball outside: %s (source %d)" % [p, b.src])
			return false
	return true

func _test_ground_api() -> void:
	check(absf(_g.ground_height_at(-8.0, 2.1) - 0.0) < 0.001, "ground_height_at corridor")
	check(absf(_g.ground_height_at(-28.0, 6.0) - GL.HALL) < 0.001, "ground_height_at hall")
	check(absf(_g.ground_height_at(1.0, 1.0) - 0.0) < 0.001, "ground_height_at falls back to the house")
	check(absf(_g.ground_height_at(-26.0, 0.0, 0.2) - GL.L1) < 0.001, "ground_height_at deck L1 with prev_y")
	check(_g.surface_at(Vector3(-6, 0, 2.1)) == "concrete" and _g.surface_at(Vector3(-28, GL.HALL, 6)) == "foam", "surface_at")
