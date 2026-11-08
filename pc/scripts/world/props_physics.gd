## World physics (world module).
##  * LAYER_WORLD (1) — movement: level_meta.json `colliders[]` (the web AABBs: foundation / partition / stairwell / hallway
##    walls, the closed upstairs door, the swung-open closet door, furniture, extras) as StaticBody3D boxes (meta "tag"),
##    plus the floors the web build never needed (it used Layout.groundHeightAt): basement + laundry nook floor, the stair
##    RAMP (a thin box through the foot of the first riser and the landing nosing: CharacterBody3D climbs it smoothly, the
##    player eases its camera tread by tread), the landing and the upper hallway floor. Low clutter (< 0.45 m: football,
##    toolbox, laundry crate…) is raised to 0.45 m so the player's 0.3 m step-up never climbs onto it.
##  * LAYER_SIGHT (16) — `occluders[]` (walls, ceiling slab, landing, knee wall pieces, doors, sofa / dresser / clock…
##    sight boxes): what line_blocked() tests, like the web lineBlocked (the railing and chair AABBs do not block sight).
##    Door occluders are children of the door pivots (they swing with the leaves).
##  * LAYER_INTERACT (2) — interaction bodies: interact_box() fits a box to the meshes under a node (child of it, follows
##    drawers / lids / doors), meta_proxy_box() rebuilds the web hit proxies (lid, padlock, lever, batteries, key).
## Every body is unscaled in world space (shapes carry the size): no scaled shapes for Jolt.
extends RefCounted

const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const LAYER_SIGHT := 16
const LOW_PROP_HEIGHT := 0.45
const LOW_PROP_TAGS := ["prop", "boxA", "boxB"]
const LevelLoader := preload("res://scripts/world/level_loader.gd")

## StaticBody3D with one box shape (`xf` = world transform of the box centre, unscaled).
static func box_body(parent: Node, body_name: String, xf: Transform3D, size: Vector3, layer: int, tag := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	if tag != "": body.set_meta(&"tag", tag)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var sh := BoxShape3D.new()
	sh.size = Vector3(maxf(size.x, 0.002), maxf(size.y, 0.002), maxf(size.z, 0.002))
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	if body.is_inside_tree(): body.global_transform = xf
	else: body.transform = xf
	return body

static func aabb_body(parent: Node, body_name: String, mn: Vector3, mx: Vector3, layer: int, tag := "") -> StaticBody3D:
	return box_body(parent, body_name, Transform3D(Basis(), (mn + mx) * 0.5), mx - mn, layer, tag)

## World transform + size of a local box (box min/max in the space of `xf`, which may carry scale).
static func _decompose(xf: Transform3D, bmin: Vector3, bmax: Vector3) -> Dictionary:
	var s := xf.basis.get_scale()
	var c := xf * ((bmin + bmax) * 0.5)
	return {"xf": Transform3D(xf.basis.orthonormalized(), c), "size": (bmax - bmin) * s.abs()}

# ------------------------------------------------------------------ movement colliders + floors

## Returns Array of {body, shape, tag, enabled, min, max} (meta order).
static func build_colliders(root: Node3D, meta: Dictionary) -> Array:
	var out: Array = []
	var i := 0
	for c in meta.get("colliders", []):
		var mn := Vector3(c.min[0], c.min[1], c.min[2])
		var mx := Vector3(c.max[0], c.max[1], c.max[2])
		var tag := String(c.get("tag", "wall"))
		if LOW_PROP_TAGS.has(tag) and mx.y < LOW_PROP_HEIGHT: mx.y = LOW_PROP_HEIGHT
		var body := aabb_body(root, "Col_%02d_%s" % [i, tag], mn, mx, LAYER_WORLD, tag)
		var cs := body.get_node("Shape") as CollisionShape3D
		var enabled := bool(c.get("enabled", true))
		cs.disabled = not enabled
		out.append({"body": body, "shape": cs, "tag": tag, "enabled": enabled, "min": mn, "max": mx})
		i += 1
	return out

## Floors, stair ramp, landing, upper hall (Layout values, identical to the web groundHeightAt).
static func build_floors(root: Node3D) -> Dictionary:
	var R: Dictionary = Layout.ROOM
	var S: Dictionary = Layout.STAIRS
	var A: Dictionary = Layout.ALCOVE
	var H: Dictionary = Layout.UPPER_HALL
	var top: float = Layout.UPPER.floorY
	var wt: float = R.wallThickness
	var out := {}
	# basement (room + closet under the stairs) and laundry nook: 0.5 m slabs whose top is y = 0
	out["floor"] = aabb_body(root, "Floor", Vector3(R.minX - wt, -0.5, R.minZ - 0.15), Vector3(R.maxX + wt, 0.0, R.maxZ + 0.3), LAYER_WORLD, "floor")
	out["nook_floor"] = aabb_body(root, "NookFloor", Vector3(A.minX - 0.12, -0.5, A.minZ - wt), Vector3(A.maxX + wt, 0.0, R.minZ), LAYER_WORLD, "floor")
	# stair ramp: plane through the foot of the first riser (bottomZ, 0) and the landing nosing (topZ, UPPER.floorY),
	# started 6 cm under the floor so the carpet -> ramp transition has no lip. Thickness 0.12 m (top face = the plane).
	var bz: float = S.bottomZ
	var tz: float = S.topZ
	var a := Vector3(0.0, -0.06, bz + 0.06 * (bz - tz) / top)
	var b := Vector3(0.0, top, tz)
	var u := (b - a).normalized()
	var n := Vector3(0.0, -u.z, u.y)          # up / toward +z
	var th := 0.12
	var mid := (a + b) * 0.5 - n * (th * 0.5)
	var ramp_xf := Transform3D(Basis(Vector3.RIGHT, n, -u), Vector3((S.minX + S.maxX) * 0.5, mid.y, mid.z))
	out["ramp"] = box_body(root, "StairRamp", ramp_xf, Vector3(S.maxX - S.minX, th, a.distance_to(b)), LAYER_WORLD, "stairs")
	# landing (top of the stairs, over the closet) + door threshold, and the upper hallway
	out["landing"] = aabb_body(root, "Landing", Vector3(R.minX, top - 0.3, R.minZ - 0.15), Vector3(S.sideWallX + 0.06, top, tz), LAYER_WORLD, "stairs")
	out["hall_floor"] = aabb_body(root, "HallFloor", Vector3(H.minX, top - 0.2, H.minZ), Vector3(H.maxX, top, R.minZ - 0.1), LAYER_WORLD, "floor")
	return out

# ------------------------------------------------------------------ sight occluders

## `occluders[]` -> LAYER_SIGHT boxes. Bodies under door pivots (doors_parents) are children of them (they swing).
static func build_occluders(static_root: Node3D, ctx: Dictionary, moving_parents: Array) -> Array:
	var out: Array = []
	var meta: Dictionary = ctx.get("meta", {})
	var i := 0
	for o in meta.get("occluders", []):
		var body: StaticBody3D = null
		var box = o.get("box")
		if box is Dictionary:
			var parent := LevelLoader.find(ctx, o.get("parent"))
			var pxf := parent.global_transform if parent != null else Transform3D()
			var xf := pxf * LevelLoader.mat16(o.local)
			var d := _decompose(xf, Vector3(box.min[0], box.min[1], box.min[2]), Vector3(box.max[0], box.max[1], box.max[2]))
			var host: Node3D = parent if parent != null and moving_parents.has(parent) else static_root
			body = box_body(host, "Sight_%02d" % i, d.xf, d.size, LAYER_SIGHT, "sight")
		else:
			var inst := LevelLoader.find(ctx, o.get("ref"))
			if inst == null: continue
			var bb := global_aabb(inst)
			if bb.size == Vector3.ZERO: continue
			body = aabb_body(static_root, "Sight_%02d_%s" % [i, inst.name], bb.position, bb.end, LAYER_SIGHT, "sight")
		out.append(body)
		i += 1
	return out

# ------------------------------------------------------------------ interaction bodies

## Invisible LAYER_INTERACT box fitted to the visible meshes under `node` (skipping `skip` subtrees), child of `node`.
## grow: margin (m); min_size: smallest box side (thin notes stay easy to aim at).
static func interact_box(node: Node3D, id: String, skip: Array = [], grow := 0.01, min_size := 0.03) -> StaticBody3D:
	if node == null or not node.is_inside_tree(): return null
	var frame := Transform3D(node.global_basis.orthonormalized(), node.global_position)
	var acc := {"has": false, "box": AABB()}
	_accumulate(node, frame.affine_inverse(), skip, acc, true)
	if not acc["has"]: return null
	var box: AABB = (acc["box"] as AABB).grow(grow)
	var size := Vector3(maxf(box.size.x, min_size), maxf(box.size.y, min_size), maxf(box.size.z, min_size))
	var body := box_body(node, "Interact_" + id.replace(".", "_"), Transform3D(frame.basis, frame * box.get_center()), size, LAYER_INTERACT)
	body.set_meta(&"interact_id", id)
	return body

## Web hit proxy from `proxies[]` ({parent, local, box}) -> LAYER_INTERACT box, child of its parent node.
static func meta_proxy_box(ctx: Dictionary, p: Dictionary, id: String) -> StaticBody3D:
	var parent := LevelLoader.find(ctx, p.get("parent"))
	var box = p.get("box")
	if parent == null or not (box is Dictionary): return null
	var xf := parent.global_transform * LevelLoader.mat16(p.local)
	var d := _decompose(xf, Vector3(box.min[0], box.min[1], box.min[2]), Vector3(box.max[0], box.max[1], box.max[2]))
	var body := box_body(parent, "Hit_" + id.replace(".", "_"), d.xf, d.size, LAYER_INTERACT)
	body.set_meta(&"interact_id", id)
	return body

static func _accumulate(n: Node, inv: Transform3D, skip: Array, acc: Dictionary, root: bool) -> void:
	if not root and skip.has(n): return
	if n is Node3D and not (n as Node3D).visible and not root: return
	if n is MeshInstance3D:
		var vi := n as MeshInstance3D
		var a := vi.get_aabb()
		if a.size != Vector3.ZERO:
			var t := inv * vi.global_transform
			for k in 8:
				var p: Vector3 = t * a.get_endpoint(k)
				if acc["has"]: acc["box"] = (acc["box"] as AABB).expand(p)
				else:
					acc["box"] = AABB(p, Vector3.ZERO)
					acc["has"] = true
	for c in n.get_children():
		if c is CollisionObject3D: continue
		_accumulate(c, inv, skip, acc, false)

## World-space AABB of every visible mesh under `node`.
static func global_aabb(node: Node3D, skip: Array = []) -> AABB:
	var acc := {"has": false, "box": AABB()}
	_accumulate(node, Transform3D(), skip, acc, true)
	return acc["box"] if acc["has"] else AABB()
