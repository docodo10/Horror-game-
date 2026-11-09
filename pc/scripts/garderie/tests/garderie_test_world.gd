## Test world for the garderie: the REAL exported level (MetaUtil.assemble: level.glb + model instances + shadow
## casters) plus what the world module builds from level_meta.json — WORLD box colliders from colliders[], WORLD ray
## blockers from the occluder proxies, the main floor and the stair ramp — and the world API the garderie touches
## (power, ground_height_at, hide_spots, handles). Used by test_garderie.gd and preview.gd.
extends Node3D

const MetaUtil := preload("res://assets/generated/meta_util.gd")
const LAYER_WORLD := 1
const LAYER_SIGHT := 16

var power := true
var handles := {}
var hide_spots: Array = []
var ctx := {}
var errors: Array = []

func build_level() -> void:
	var meta := MetaUtil.load_json("res://assets/generated/level_meta.json")
	ctx = MetaUtil.assemble(self, meta)
	errors = ctx.get("errors", [])
	var body := StaticBody3D.new()
	body.name = "WorldColliders"
	body.collision_layer = LAYER_WORLD
	add_child(body)
	for c in meta.get("colliders", []):
		if c.get("enabled", true) == false:
			continue
		var mn := Vector3(c.min[0], c.min[1], c.min[2])
		var mx := Vector3(c.max[0], c.max[1], c.max[2])
		_box(body, mn, mx, String(c.get("tag", "")))
	# occluder proxies (sight blockers) on LAYER_SIGHT, like the world module's line_blocked bodies
	var sight := StaticBody3D.new()
	sight.name = "SightOccluders"
	sight.collision_layer = LAYER_SIGHT
	add_child(sight)
	for p in meta.get("proxies", []):
		if p.get("occluder", false) != true or p.get("box") == null:
			continue
		if p.get("owner") != null:
			continue
		var xf := MetaUtil.mat16(p.local)
		var parent_ref = p.get("parent")
		if parent_ref is Dictionary and parent_ref.has("level") and parent_ref.level != "occluders":
			continue
		var b: Dictionary = p.box
		var ab := xf * AABB(Vector3(b.min[0], b.min[1], b.min[2]), Vector3(b.max[0] - b.min[0], b.max[1] - b.min[1], b.max[2] - b.min[2]))
		var cs := _box(sight, ab.position, ab.end, "occ")
		cs.name = "Occ_%d" % sight.get_child_count()
	# floors: main room, stairs ramp (like the real world module)
	var R: Dictionary = Layout.ROOM
	_box(body, Vector3(R.minX, -0.2, R.minZ), Vector3(R.maxX, 0.0, R.maxZ), "floor")
	var S: Dictionary = Layout.STAIRS
	var ramp := CollisionShape3D.new()
	var cv := ConvexPolygonShape3D.new()
	var top: float = Layout.UPPER.floorY
	cv.points = PackedVector3Array([
		Vector3(S.minX, 0.0, S.bottomZ), Vector3(S.maxX, 0.0, S.bottomZ),
		Vector3(S.minX, top, S.topZ), Vector3(S.maxX, top, S.topZ),
		Vector3(S.minX, 0.0, S.topZ), Vector3(S.maxX, 0.0, S.topZ)])
	ramp.shape = cv
	body.add_child(ramp)

func _box(body: StaticBody3D, mn: Vector3, mx: Vector3, tag: String) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = (mx - mn).abs()
	cs.shape = sh
	cs.position = (mn + mx) * 0.5
	cs.set_meta("tag", tag)
	body.add_child(cs)
	return cs

func ground_height_at(x: float, z: float, prev_y := NAN) -> float:
	return Layout.ground_height_at(x, z, prev_y)

func line_blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_SIGHT)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func set_power(on: bool) -> void:
	power = on
	Events.power_changed.emit(on)
