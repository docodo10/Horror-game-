## Interactive physics of the garderie (CPU only: Jolt at 60 Hz; nothing simulates unless the player is near it, and
## every body sleeps as soon as it rests):
##  * Ball-pit bubble: a pool of GL.BALL_POOL RigidBody3D balls (collision r 3.5 cm under the 3.7 cm visual, 50 g,
##    bounce 0.45, friction 0.35, linear damp 0.6, no shadows). The pit's top-layer MultiMesh balls within
##    GL.BUBBLE_R of the player's feet (and the balls scattered on the floor within GL.BUBBLE_R_FLOOR) become rigid
##    balls, their MultiMesh instance hidden; a ball asleep farther than GL.BUBBLE_DEMOTE goes back into its
##    MultiMesh where it now lies. The hidden layers under the top one are the pit's trimesh bed (garderie_play.gd).
##    In the pit a ball is damped like a ball nested in the pile (it settles where it lands); on the floor it rolls.
##    The walkers' legs (player, La Gardienne) part the balls with a velocity-matched push measured from their real
##    displacement (forward + outward + a little lift): the balls do not collide with their capsules, which would
##    keep the whole pile awake with contact jitter.
##  * Pushable foam blocks (GL.BLOCKS, 1.2-3 kg from their volume, friction 0.9, bounce 0.05, angular damp 2):
##    WORLD bodies the characters bump into; the push comes from their slide collisions, read right after their own
##    move (CharacterBody3D.get_slide_collision, process_physics_priority after the player's -10): player.gd untouched.
##  * Impact sounds through Audio: velocity / impulse-scaled volume, per-body cooldowns, a global budget per frame.
## Physics layers: balls and their bed on layer 6 (value 32, LAYER_BALLS — unnamed in project.godot); balls collide
## with WORLD (walls, floor, foam blocks), the bed and each other.
## API: setup(garderie, ctx), set_active(on), release_all(), actor (override of Game.player, tests), stats(),
##   active_balls() -> int, awake_balls() -> int, escaped (balls / blocks that left the area: reset, counted).
extends Node3D

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Play := preload("res://scripts/garderie/garderie_play.gd")

const LAYER_WORLD := 1
const LAYER_PLAYER := 4
const LAYER_ENTITY := 8
const LAYER_BALLS := 32
const BALL_R := 0.033                    # under the 3.7 cm visual: the jittered MultiMesh packing never starts overlapped
## In the pit a ball sits nested in the layer under it: it does not roll freely (strong angular damping acts as the
## rolling resistance of the pile, so a promoted ball settles in place); on the open floor it rolls.
const PIT_DAMP := Vector2(1.2, 6.0)       # linear, angular
const FLOOR_DAMP := Vector2(0.5, 0.8)
const BALL_MASS := 0.05
const CELL := 0.25
const SRC_PIT := 0
const SRC_SCATTER := 1
const BLOCK_COLS := [Color(0.6, 0.07, 0.05), Color(0.08, 0.2, 0.52), Color(0.8, 0.58, 0.1), Color(0.07, 0.4, 0.14), Color(0.42, 0.12, 0.5)]
const IMPACT_MAX := 16

## A pooled ball: reports new contacts (impulse) to the manager for the impact sounds.
class GBall extends RigidBody3D:
	var mgr = null
	var slot := -1
	var src := -1
	var idx := -1
	var scale_k := 1.0
	var cd := 0.0
	var _nc := 0
	func _integrate_forces(s: PhysicsDirectBodyState3D) -> void:
		var n := s.get_contact_count()
		if n > _nc and mgr != null:
			var imp := 0.0
			for i in n:
				imp = maxf(imp, s.get_contact_impulse(i).length())
			mgr.queue_impact(self, imp)
		_nc = n

## A pushable foam block.
class GBlock extends RigidBody3D:
	var mgr = null
	var home := Transform3D.IDENTITY
	var cd := 0.0
	var _nc := 0
	func _integrate_forces(s: PhysicsDirectBodyState3D) -> void:
		var n := s.get_contact_count()
		if n > _nc and mgr != null:
			var imp := 0.0
			for i in n:
				imp = maxf(imp, s.get_contact_impulse(i).length())
			mgr.queue_impact(self, imp)
		_nc = n

var actor: Node3D = null                # tests: stands in for Game.player
var escaped := 0
var pushes := 0
var block_pushes := 0
var promoted_total := 0
var demoted_total := 0
var impacts_played := 0

var _g: Node = null
var _active := false
var _pool: Array[GBall] = []
var _free: PackedInt32Array = PackedInt32Array()
var _used: PackedInt32Array = PackedInt32Array()        # slots in use (unordered)
var _src_mm: Array[MultiMesh] = []
var _src_xf: Array = []                                  # per source: Array[Transform3D] (current rest transforms)
var _src_cols: Array = []                                # per source: Array[Color]
var _src_slot: Array = []                                # per source: Array[int] (pool slot or -1; arrays by reference)
var _grid := {}                                          # Vector2i -> PackedInt32Array of ids (src << 20 | idx)
var _blocks: Array[GBlock] = []
var _tick := 0
var _imp_body: Array = []
var _imp_val := PackedFloat32Array()
var _imp_n := 0
var _snd_budget := 0.0
var _bounds := AABB()
var _prev_feet := Vector3.ZERO
var _prev_ent := Vector3.ZERO
var _actor_speed := 0.0
var _ent_speed := 0.0
var _cpu_us_sum := 0
var _cpu_us_max := 0
var _cpu_ticks := 0
var _occ_q: PhysicsShapeQueryParameters3D = null
var _bed: StaticBody3D = null

func setup(g: Node, c) -> void:
	_g = g
	name = "GarderiePhysics"
	process_physics_priority = 20         # after the player (-10) and La Gardienne moved: their slide collisions are fresh
	var H: Dictionary = GL.HALLB
	_bounds = AABB(Vector3(float(H.x0) - 0.2, GL.HALL - 0.5, float(H.z0) - 0.2), Vector3(float(H.x1) - float(H.x0) + 0.4 + 7.0, 9.0, float(H.z1) - float(H.z0) + 0.4))
	_imp_body.resize(IMPACT_MAX)
	_imp_val.resize(IMPACT_MAX)
	_bed = c.region("balls").get_node_or_null("BallBed") as StaticBody3D
	_setup_sources(c)
	_setup_pool(c)
	_setup_blocks(c)

# ====================================================================== balls

func _setup_sources(c) -> void:
	for key in ["pit", "scatter"]:
		var d: Dictionary = c.pit_balls.get(key, {})
		var mmi: MultiMeshInstance3D = d.get("mmi")
		if mmi == null:
			_src_mm.append(null)
			_src_xf.append([])
			_src_cols.append([])
			_src_slot.append([])
			continue
		var s := _src_mm.size()
		_src_mm.append(mmi.multimesh)
		var xfs: Array = (d.get("xforms", []) as Array).duplicate()
		_src_xf.append(xfs)
		_src_cols.append(d.get("cols", []))
		var sl: Array[int] = []
		sl.resize(xfs.size())
		sl.fill(-1)
		_src_slot.append(sl)
		var top: PackedByteArray = d.get("top", PackedByteArray())
		for i in xfs.size():
			if top[i] != 0:
				_grid_add((s << 20) | i, (xfs[i] as Transform3D).origin)

func _setup_pool(c) -> void:
	var shape := SphereShape3D.new()
	shape.radius = BALL_R
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.45
	var mesh: ArrayMesh = Play._ball_mesh()
	mesh.surface_set_material(0, c.mats.mat("balls"))
	var holder := Node3D.new()
	holder.name = "BallPool"
	add_child(holder)
	for i in GL.BALL_POOL:
		var b := GBall.new()
		b.name = "Ball%d" % i
		b.mgr = self
		b.slot = i
		b.collision_layer = LAYER_BALLS
		# not PLAYER / ENTITY: a kinematic capsule resting among the balls would keep the whole pile awake (contact
		# jitter); the walkers part the balls with a scripted, velocity-matched push instead (_push_balls)
		b.collision_mask = LAYER_WORLD | LAYER_BALLS
		b.mass = BALL_MASS
		b.physics_material_override = pm
		b.linear_damp = 0.6
		b.angular_damp = 1.0
		b.can_sleep = true
		b.contact_monitor = true
		b.max_contacts_reported = 2
		b.continuous_cd = true          # Jolt only sweeps a ball moving faster than ~its radius per step: free at rest
		var cs := CollisionShape3D.new()
		cs.shape = shape
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.layers = 2048
		b.add_child(mi)
		b.process_mode = Node.PROCESS_MODE_DISABLED
		b.visible = false
		holder.add_child(b)
		_pool.append(b)
		_free.append(i)

func _grid_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))

func _grid_add(id: int, p: Vector3) -> void:
	var k := _grid_key(p)
	var arr: PackedInt32Array = _grid.get(k, PackedInt32Array())
	arr.append(id)
	_grid[k] = arr

func _grid_remove(id: int, p: Vector3) -> void:
	var k := _grid_key(p)
	if not _grid.has(k):
		return
	var arr: PackedInt32Array = _grid[k]
	var at := arr.find(id)
	if at >= 0:
		arr.remove_at(at)
		_grid[k] = arr

func _promote(src: int, idx: int) -> bool:
	if _free.is_empty():
		return false
	var slot := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	var b := _pool[slot]
	var xf: Transform3D = _src_xf[src][idx]
	var sc := xf.basis.get_scale().x
	b.src = src
	b.idx = idx
	b.scale_k = sc
	b.cd = 0.0
	# a rigid ball pushed into this ball's spot: the promoted one starts on top of it and drops onto the pile
	# (never inside it: an overlapping pair would explode apart and keep the pile awake)
	var origin := xf.origin
	var occupied := _occupied(origin)
	if occupied:
		origin.y += BALL_R * 2.1
	b.transform = Transform3D(xf.basis.orthonormalized(), origin)
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	var damp := PIT_DAMP if src == SRC_PIT else FLOOR_DAMP
	b.linear_damp = damp.x
	b.angular_damp = damp.y
	b.process_mode = Node.PROCESS_MODE_INHERIT
	b.visible = true
	b.sleeping = not occupied
	var col: Color = _src_cols[src][idx]
	(b.get_child(1) as GeometryInstance3D).set_instance_shader_parameter(&"ball_tint", Color(col.r, col.g, col.b, 1.0))
	_src_slot[src][idx] = slot
	_src_mm[src].set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), xf.origin))
	_used.append(slot)
	promoted_total += 1
	return true

## True when an active rigid ball already sits (partly) where a ball would be promoted at p (a broadphase sphere
## query on the balls' layer, the bed excluded).
func _occupied(p: Vector3) -> bool:
	if _used.is_empty() or not is_inside_tree():
		return false
	if _occ_q == null:
		_occ_q = PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = BALL_R * 0.85
		_occ_q.shape = sh
		_occ_q.collision_mask = LAYER_BALLS
		_occ_q.collide_with_areas = false
		if _bed != null:
			_occ_q.exclude = [_bed.get_rid()]
	_occ_q.transform = Transform3D(Basis.IDENTITY, p)
	return not get_world_3d().direct_space_state.intersect_shape(_occ_q, 1).is_empty()

func _demote(slot: int, reset := false) -> void:
	var b := _pool[slot]
	var src := b.src
	var idx := b.idx
	var old: Transform3D = _src_xf[src][idx]
	var xf := Transform3D(b.global_transform.basis.orthonormalized().scaled(Vector3.ONE * b.scale_k), b.global_position)
	if reset:
		xf = old
	_grid_remove((src << 20) | idx, old.origin)
	_src_xf[src][idx] = xf
	_grid_add((src << 20) | idx, xf.origin)
	_src_mm[src].set_instance_transform(idx, xf)
	_src_slot[src][idx] = -1
	b.process_mode = Node.PROCESS_MODE_DISABLED
	b.visible = false
	b.src = -1
	b.idx = -1
	var at := _used.find(slot)
	if at >= 0:
		_used.remove_at(at)
	_free.append(slot)
	demoted_total += 1

## Every rigid ball goes back into its MultiMesh where it lies (leaving the area, caught, tests).
func release_all() -> void:
	while not _used.is_empty():
		_demote(_used[_used.size() - 1])

func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if not on:
		release_all()

func active_balls() -> int:
	return _used.size()

func awake_balls() -> int:
	var n := 0
	for s in _used:
		if not _pool[s].sleeping:
			n += 1
	return n

func _actor() -> Node3D:
	if actor != null and is_instance_valid(actor):
		return actor
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	return p as Node3D

func _physics_process(dt: float) -> void:
	if not _active:
		return
	var t_us := Time.get_ticks_usec()
	_tick_body(dt)
	var us := Time.get_ticks_usec() - t_us
	_cpu_us_sum += us
	_cpu_us_max = maxi(_cpu_us_max, us)
	_cpu_ticks += 1

func _tick_body(dt: float) -> void:
	_tick += 1
	var p := _actor()
	_snd_budget = minf(_snd_budget + dt * 14.0, 3.0)
	var ent: Node3D = Game.entity as Node3D if is_instance_valid(Game.entity) else null
	var keep := exp(-dt / 0.6)
	if p != null:
		var feet := p.global_position
		# the walker's real motion this tick (a teleport reads as standing still) + its recent walking speed
		var vel := (feet - _prev_feet) / dt if dt > 0.0 else Vector3.ZERO
		_prev_feet = feet
		if vel.length_squared() > 36.0:
			vel = Vector3.ZERO
		_actor_speed = maxf(Vector2(vel.x, vel.z).length(), _actor_speed * keep)
		_push_from(p as CharacterBody3D, dt, _actor_speed)
		if not _used.is_empty():
			_push_balls(feet, vel)
		if _tick % 2 == 0:
			# around the legs every other tick; the wider floor ring (scattered balls) every 10 ticks
			_promote_near(feet + Vector3(vel.x, 0.0, vel.z) * 0.15, GL.BUBBLE_R_FLOOR if _tick % 10 == 0 else GL.BUBBLE_R)
	# La Gardienne pushes the blocks and parts the rigid balls too
	if ent != null:
		var ef := ent.global_position
		var ev := (ef - _prev_ent) / dt if dt > 0.0 else Vector3.ZERO
		_prev_ent = ef
		if ev.length_squared() > 36.0:
			ev = Vector3.ZERO
		_ent_speed = maxf(Vector2(ev.x, ev.z).length(), _ent_speed * keep)
		_push_from(ent as CharacterBody3D, dt, _ent_speed)
		if not _used.is_empty():
			_push_balls(ef, ev)
	if _tick % 12 == 0:
		_demote_far(p.global_position if p != null else Vector3(0, -100, 0))
	_flush_impacts()

## Promotes the MultiMesh balls within reach (pit balls within BUBBLE_R, floor balls within BUBBLE_R_FLOOR) of c,
## scanning the grid out to `scan` m; at most PROMOTE_MAX per call (entering the pit fills the bubble over a few
## ticks instead of one long frame).
const PROMOTE_MAX := 28

func _promote_near(c: Vector3, scan: float) -> void:
	var rf := minf(GL.BUBBLE_R_FLOOR, scan)
	var r_pit2 := GL.BUBBLE_R * GL.BUBBLE_R
	var r_floor2 := rf * rf
	var budget := PROMOTE_MAX
	var k0 := _grid_key(c - Vector3(scan, 0, scan))
	var k1 := _grid_key(c + Vector3(scan, 0, scan))
	for gx in range(k0.x, k1.x + 1):
		for gz in range(k0.y, k1.y + 1):
			var key := Vector2i(gx, gz)
			if not _grid.has(key):
				continue
			var arr: PackedInt32Array = _grid[key]
			for id in arr:
				var src := id >> 20
				var idx := id & 0xFFFFF
				if int(_src_slot[src][idx]) >= 0:
					continue
				var o: Vector3 = (_src_xf[src][idx] as Transform3D).origin
				if absf(o.y - c.y) > 1.2:
					continue
				var d2 := Vector2(o.x - c.x, o.z - c.z).length_squared()
				if d2 < (r_pit2 if src == SRC_PIT else r_floor2):
					if _free.is_empty():
						_recycle(c)
					if not _promote(src, idx):
						return
					budget -= 1
					if budget <= 0:
						return

## Pool exhausted while the player wades on: the slowest balls left behind the bubble go back into the MultiMesh
## right away (even if not asleep yet), up to 24 at a time.
func _recycle(c: Vector3) -> void:
	var lim2 := (GL.BUBBLE_R + 0.2) * (GL.BUBBLE_R + 0.2)
	var n := 0
	var i := _used.size() - 1
	while i >= 0 and n < 24:
		var slot := _used[i]
		var b := _pool[slot]
		var bp := b.global_position
		if Vector2(bp.x - c.x, bp.z - c.z).length_squared() > lim2 and b.linear_velocity.length_squared() < 0.09:
			_demote(slot)
			n += 1
		i = mini(i - 1, _used.size() - 1)

func _demote_far(feet: Vector3) -> void:
	var i := _used.size() - 1
	while i >= 0:
		var slot := _used[i]
		var b := _pool[slot]
		var bp := b.global_position
		var lim := GL.BUBBLE_DEMOTE if b.src == SRC_PIT else GL.BUBBLE_R_FLOOR + 0.4
		if not _bounds.has_point(bp) or bp.y < GL.HALL - 0.2:
			escaped += 1
			_demote(slot, true)
		elif b.sleeping and Vector2(bp.x - feet.x, bp.z - feet.z).length() > lim:
			_demote(slot)
		elif not b.sleeping and b.src == SRC_PIT and b.linear_velocity.length_squared() < 0.0036 and b.angular_velocity.length_squared() < 4.0:
			# a nested ball creeping < 6 cm/s: the pile has settled around it (Jolt keeps a whole touching island
			# awake while any member creeps above its threshold)
			b.sleeping = true
		i = mini(i - 1, _used.size() - 1)
	# blocks that escaped (pushed through something): back home
	for bk in _blocks:
		if not _bounds.has_point(bk.global_position) or bk.global_position.y < GL.HALL - 0.3:
			escaped += 1
			bk.global_transform = bk.home
			bk.linear_velocity = Vector3.ZERO
			bk.angular_velocity = Vector3.ZERO

## The legs part the balls: balls within 0.42 m of the walking player get a velocity-matched nudge (forward + out).
func _push_balls(feet: Vector3, vel: Vector3) -> void:
	var hv := Vector3(vel.x, 0.0, vel.z)
	var spd := hv.length()
	if spd < 0.15:
		return
	var fwd := hv / spd
	for slot in _used:
		var b := _pool[slot]
		var bp := b.global_position
		var dx := bp.x - feet.x
		var dz := bp.z - feet.z
		var d2 := dx * dx + dz * dz
		if d2 > 0.42 * 0.42 or bp.y > feet.y + 0.75:
			continue
		var d := sqrt(d2)
		var away := Vector3(dx, 0.0, dz) / maxf(d, 0.001)
		if away.dot(fwd) < -0.3:
			continue                    # behind the legs
		var target := fwd * spd * 0.85 + away * spd * 0.5 + Vector3(0, spd * 0.12, 0)
		var dv := target - b.linear_velocity
		if dv.dot(target) > 0.0:
			b.apply_central_impulse(dv * BALL_MASS * 0.35)
			pushes += 1

# ====================================================================== blocks

func _setup_blocks(c) -> void:
	var holder := Node3D.new()
	holder.name = "FoamBlocks"
	add_child(holder)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	var mat: Material = c.mats.mat("vinyl_flat")
	for i in c.blocks.size():
		var d: Array = c.blocks[i]
		var kind: String = d[0]
		var pos: Vector3 = d[1]
		var size: Vector3 = d[2]
		var col: Color = BLOCK_COLS[int(d[3]) % BLOCK_COLS.size()]
		var yaw: float = d[4]
		var b := GBlock.new()
		b.name = "Block%d_%s" % [i, kind]
		b.mgr = self
		b.collision_layer = LAYER_WORLD
		b.collision_mask = LAYER_WORLD
		var vol := size.x * size.y * size.z * (0.785 if kind == "cyl" else (0.5 if kind == "wedge" else 1.0))
		b.mass = clampf(vol * 28.0, 1.2, 3.0)            # polyurethane foam + vinyl skin ≈ 28 kg/m³
		b.physics_material_override = pm
		b.linear_damp = 0.4
		b.angular_damp = 2.0
		b.can_sleep = true
		b.contact_monitor = true
		b.max_contacts_reported = 2
		var cs := CollisionShape3D.new()
		var k := Kit.new()
		var dark := col.darkened(0.35)
		match kind:
			"cyl":
				var sh := CylinderShape3D.new()
				sh.radius = size.x * 0.5
				sh.height = size.y
				cs.shape = sh
				_soft_cylinder(k, size.x * 0.5, size.y, col, dark)
			"wedge":
				var pts := PackedVector3Array([Vector3(-size.x * 0.5, -size.y * 0.5, -size.z * 0.5), Vector3(size.x * 0.5, -size.y * 0.5, -size.z * 0.5),
					Vector3(size.x * 0.5, size.y * 0.5, -size.z * 0.5), Vector3(-size.x * 0.5, -size.y * 0.5, size.z * 0.5),
					Vector3(size.x * 0.5, -size.y * 0.5, size.z * 0.5), Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.5)])
				var csh := ConvexPolygonShape3D.new()
				csh.points = pts
				cs.shape = csh
				_soft_wedge(k, size, col, dark)
			_:
				var bs := BoxShape3D.new()
				bs.size = size
				cs.shape = bs
				var r := clampf(minf(size.x, minf(size.y, size.z)) * 0.11, 0.03, 0.05)
				k.rbox("vinyl_flat", -size * 0.5, size * 0.5, r, 3, col)
				k.piping("vinyl_flat", -size * 0.5, size * 0.5, r, 0.006, dark)
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = Kit.build_mesh(k.bin("vinyl_flat"))
		mi.mesh.surface_set_material(0, mat)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.layers = 2048
		b.add_child(mi)
		b.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, size.y * 0.5 + 0.002, 0))
		b.home = b.transform
		holder.add_child(b)
		b.sleeping = true
		_blocks.append(b)

static func _soft_cylinder(k, r: float, h: float, col: Color, dark: Color) -> void:
	# lathe: rounded top / bottom edges (4 cm), piping on both edge lines
	var rb := 0.04
	var pts := PackedVector3Array()
	var radii: Array[float] = []
	var steps := 6
	for i in steps + 1:
		var a := PI * 0.5 * float(steps - i) / float(steps)
		pts.append(Vector3(0, -h * 0.5 + rb - sin(a) * rb, 0))
		radii.append(r - rb + cos(a) * rb)
	for i in steps + 1:
		var a := PI * 0.5 * float(i) / float(steps)
		pts.append(Vector3(0, h * 0.5 - rb + sin(a) * rb, 0))
		radii.append(r - rb + cos(a) * rb)
	k.tube("vinyl_flat", pts, r, 32, col, 1.0, false, func(i: int, _a: float) -> float: return radii[i] / r)
	k.disc("vinyl_flat", Vector3(0, h * 0.5, 0), Vector3.UP, Vector3.RIGHT, r - rb, 32, col)
	k.disc("vinyl_flat", Vector3(0, -h * 0.5, 0), Vector3.DOWN, Vector3.RIGHT, r - rb, 32, col)
	for sy: float in [-1.0, 1.0]:
		var ring := PackedVector3Array()
		for i in 33:
			var a := TAU * float(i) / 32.0
			ring.append(Vector3(cos(a), 0, sin(a)) * (r - rb * 0.3) + Vector3(0, sy * (h * 0.5 - rb * 0.3), 0))
		k.tube("vinyl_flat", ring, 0.006, 6, dark)

static func _soft_wedge(k, s: Vector3, col: Color, dark: Color) -> void:
	# rounded right-triangle profile swept along z, flat ends (fan)
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var rr := 0.03
	var corners := [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy)]
	var prof := PackedVector2Array()
	for ci in 3:
		var cp: Vector2 = corners[ci]
		var pa: Vector2 = corners[(ci + 2) % 3]
		var pb: Vector2 = corners[(ci + 1) % 3]
		var da := (pa - cp).normalized()
		var db := (pb - cp).normalized()
		for t in 4:
			var u := float(t) / 3.0
			var q := cp + da * rr * (1.0 - u) + db * rr * u
			var mid := cp + (da + db) * rr * 0.5
			prof.append(q.lerp(mid, sin(PI * u) * 0.35))
	prof.append(prof[0])
	var path: Array = []
	for z in [-s.z * 0.5, s.z * 0.5]:
		path.append(Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK), Vector3(0, 0, z)))
	k.sweep("vinyl_flat", path, prof, col, 1.0, false)
	var b = k.bin("vinyl_flat")
	# outward normals (profile winding is arbitrary): flip if the average normal points inward
	var cen := Vector3((-hx + hx + hx) / 3.0, (-hy - hy + hy) / 3.0, 0)
	var out := 0.0
	for i in range(b.v.size() - prof.size() * 2, b.v.size()):
		out += (b.n[i] as Vector3).dot((b.v[i] as Vector3) - Vector3(cen.x, cen.y, (b.v[i] as Vector3).z))
	if out < 0.0:
		var start: int = b.v.size() - prof.size() * 2
		for i in range(start, b.v.size()):
			b.n[i] = -b.n[i]
		var ti: int = b.idx.size() - (prof.size() - 1) * 6
		while ti < b.idx.size():
			var tmp: int = b.idx[ti + 1]
			b.idx[ti + 1] = b.idx[ti + 2]
			b.idx[ti + 2] = tmp
			ti += 3
	for z: float in [-s.z * 0.5, s.z * 0.5]:
		var nrm := Vector3(0, 0, signf(z))
		for i in prof.size() - 1:
			k.tri("vinyl_flat", Vector3(cen.x, cen.y, z), Vector3(prof[i].x, prof[i].y, z), Vector3(prof[i + 1].x, prof[i + 1].y, z), nrm,
				Vector2.ZERO, prof[i], prof[i + 1], col)
	for z: float in [-s.z * 0.5 + 0.01, s.z * 0.5 - 0.01]:
		var ring := PackedVector3Array()
		for p2 in prof:
			ring.append(Vector3(p2.x, p2.y, z) * Vector3(0.985, 0.985, 1.0))
		k.tube("vinyl_flat", ring, 0.006, 6, dark)

## Pushes the foam blocks the player / La Gardienne walk into: their slide collisions this tick (read right after
## their own move) give the contact and the blocked motion. A walker that keeps pressing (a blocked remainder) pushes
## the block at its recent walking speed (player.gd zeroes its own speed against an obstacle, so the speed it had
## just before is the intent), at least 0.6 m/s; lighter blocks go a little faster than the walker, heavier ones lag.
func _push_from(cb: CharacterBody3D, dt: float, recent_speed: float) -> void:
	if cb == null or _blocks.is_empty() or dt <= 0.0:
		return
	for i in cb.get_slide_collision_count():
		var kc := cb.get_slide_collision(i)
		var body := kc.get_collider() as GBlock
		if body == null:
			continue
		var n := kc.get_normal()
		var d := Vector3(-n.x, 0.0, -n.z)
		if d.length_squared() < 0.04:
			continue                    # standing on it
		d = d.normalized()
		var pressing := kc.get_remainder().dot(d)
		if pressing < 0.0004:
			continue
		# the walker's whole intended motion along d this tick (travel up to the contact + the blocked remainder)
		var walk := maxf((kc.get_travel() + kc.get_remainder()).dot(d), 0.0) / dt
		walk = clampf(maxf(walk, maxf(recent_speed * 0.9, 0.6)), 0.0, 3.5)
		var target := walk * clampf(3.0 / body.mass, 0.85, 1.15)
		var vb := body.linear_velocity.dot(d)
		if target > vb:
			# at the contact's side, but low (near the centre of mass): the foam slides and only rocks a little
			var at := (kc.get_position() - body.global_position) * Vector3(0.25, 0.0, 0.25)
			at.y = clampf(kc.get_position().y - body.global_position.y, -0.04, 0.04)
			body.apply_impulse(d * (target - vb) * body.mass * 0.8, at)
			pushes += 1
			block_pushes += 1

func blocks() -> Array[GBlock]:
	return _blocks

# ====================================================================== impact sounds

func queue_impact(body: Object, imp: float) -> void:
	if _imp_n >= IMPACT_MAX:
		return
	_imp_body[_imp_n] = body
	_imp_val[_imp_n] = imp
	_imp_n += 1

func _flush_impacts() -> void:
	var now := Time.get_ticks_msec() * 0.001
	for i in _imp_n:
		var body: Object = _imp_body[i]
		_imp_body[i] = null
		if not is_instance_valid(body):
			continue
		var imp := _imp_val[i]
		if body is GBall:
			var b := body as GBall
			if imp < 0.02 or now < b.cd or _snd_budget < 1.0:
				continue
			b.cd = now + 0.15
			_snd_budget -= 1.0
			var vol := clampf(imp / 0.09, 0.08, 1.0)
			if _g != null and _g.has_method("play_impact"):
				_g.play_impact("ball_bounce", b.global_position, vol)
				impacts_played += 1
		elif body is GBlock:
			var k := body as GBlock
			if imp < 0.35 or now < k.cd or _snd_budget < 1.0:
				continue
			k.cd = now + 0.25
			_snd_budget -= 1.0
			var v2 := clampf(imp / 2.2, 0.12, 1.0)
			if _g != null and _g.has_method("play_impact"):
				_g.play_impact("foam_thud", k.global_position, v2)
				impacts_played += 1
	_imp_n = 0

func stats() -> Dictionary:
	return {"pool": _pool.size(), "active": _used.size(), "awake": awake_balls(), "blocks": _blocks.size(), "promoted": promoted_total,
		"demoted": demoted_total, "escaped": escaped, "pushes": pushes, "block_pushes": block_pushes, "impacts": impacts_played,
		"script_ms_avg": snappedf(float(_cpu_us_sum) / maxf(1.0, float(_cpu_ticks)) / 1000.0, 0.001), "script_ms_max": snappedf(_cpu_us_max / 1000.0, 0.001)}
