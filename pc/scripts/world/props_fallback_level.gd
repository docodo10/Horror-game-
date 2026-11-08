## Fallback level (world module): only used when res://assets/generated/ (exporter outputs) is missing or unusable.
## Builds the basement from Layout with textured boxes (floors, walls with the nook doorway, ceilings, stair treads, landing,
## knee wall with the closet door hole, upper hallway, six-panel / louvred doors as slabs), places Layout.PROPS /
## EXTRA_PROPS models directly from res://assets/models/<model>.glb (web names, transforms, hidden variants), and returns
## the same ctx as the exporter path plus a SYNTHETIC level_meta (colliders, occluders, handles with the web offsets and
## angles, items, clues, TV, hide spot, clue decals, anim refs) — the rest of the world module runs unchanged.
extends RefCounted

const MODELS := "res://assets/models/%s.glb"
const TEX := "res://assets/textures/%s/%s.jpg"
const NOTES := "res://assets/generated/textures/notes/%s"
## web Props.js: furniture that gets an AABB collider (+ every EXTRA_PROPS entry without noCollider, except the suitcase)
const COLLIDE := ["sofa", "coffeeTable", "endTable", "dresser", "grandfather", "shelves", "console", "chairA", "chairB",
	"rockingChair", "kidTable", "kidChair", "alcoveCabinet", "alcoveShelf", "boxA", "boxB"]
const ROT := {"photoFrame": -1.27}

var _ctx := {}
var _meta := {}
var _level: Node3D = null
var _mats := {}

func build(host: Node, parent: Node3D, progress: Callable) -> Dictionary:
	_level = Node3D.new()
	_level.name = "FallbackLevel"
	parent.add_child(_level)
	_meta = {"colliders": [], "occluders": [], "handles": {}, "items": {}, "clues": {}, "tv": {}, "hideSpots": [],
		"clueDecals": {}, "anim": {}, "proxies": [], "attachments": [], "instances": []}
	_ctx = {"meta": _meta, "level": _level, "instances": {}, "level_nodes": {}, "shadow_casters": null, "errors": [], "generated": false}
	progress.call(0.1, "Sous-sol (secours)…")
	_architecture()
	_doors()
	var keys: Array = []
	for k in Layout.PROPS: keys.append([k, Layout.PROPS[k], false])
	for k in Layout.EXTRA_PROPS: keys.append(["extra_" + k, Layout.EXTRA_PROPS[k], true])
	for i in keys.size():
		_place(keys[i][0], keys[i][1], keys[i][2])
		if i % 6 == 5:
			progress.call(0.1 + 0.8 * float(i) / keys.size(), "Sous-sol (secours)…")
			await host.get_tree().process_frame
	_rocking_chair()
	_handles()
	_items()
	_tv_and_clues()
	_anim()
	progress.call(1.0, "Sous-sol (secours)…")
	return _ctx

# ------------------------------------------------------------------ helpers

func _mat(set_name: String, tile: float, tint := Color(1, 1, 1)) -> StandardMaterial3D:
	var key := "%s_%.2f" % [set_name, tile]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	var col := TEX % [set_name, "color"]
	if ResourceLoader.exists(col): m.albedo_texture = load(col)
	var nrm := TEX % [set_name, "normal"]
	if ResourceLoader.exists(nrm):
		m.normal_enabled = true
		m.normal_texture = load(nrm)
	var rough := TEX % [set_name, "rough"]
	if ResourceLoader.exists(rough): m.roughness_texture = load(rough)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	_mats[key] = m
	return m

func _box(parent: Node3D, n: String, mn: Vector3, mx: Vector3, mat: Material, collide := true, occlude := true, tag := "wall") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = mx - mn
	mi.mesh = bm
	mi.position = (mn + mx) * 0.5
	mi.material_override = mat
	parent.add_child(mi)
	_ctx.level_nodes[n] = mi
	if collide: _meta.colliders.append({"min": [mn.x, mn.y, mn.z], "max": [mx.x, mx.y, mx.z], "tag": tag, "enabled": true})
	if occlude: _occluder(mn, mx)
	return mi

func _occluder(mn: Vector3, mx: Vector3, parent := {"level": "architecture"}) -> void:
	var c := (mn + mx) * 0.5
	var s := mx - mn
	_meta.occluders.append({"name": "occ", "box": {"min": [-0.5, -0.5, -0.5], "max": [0.5, 0.5, 0.5]}, "ref": null, "parent": parent,
		"local": [s.x, 0, 0, 0, 0, s.y, 0, 0, 0, 0, s.z, 0, c.x, c.y, c.z, 1]})

static func _m16(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, 0, b.y.x, b.y.y, b.y.z, 0, b.z.x, b.z.y, b.z.z, 0, t.origin.x, t.origin.y, t.origin.z, 1]

func _ref(inst_name: String, node: Node = null) -> Dictionary:
	var inst: Node3D = _ctx.instances.get(inst_name)
	if node == null or inst == null: return {"instance": inst_name}
	return {"instance": inst_name, "node": String(inst.get_path_to(node))}

func _level_node(n: Node3D, node_name: String) -> Dictionary:
	n.name = node_name
	_ctx.level_nodes[node_name] = n
	return {"level": node_name}

# ------------------------------------------------------------------ architecture

func _architecture() -> void:
	var R: Dictionary = Layout.ROOM
	var S: Dictionary = Layout.STAIRS
	var A: Dictionary = Layout.ALCOVE
	var H: Dictionary = Layout.UPPER_HALL
	var C: Dictionary = Layout.CLOSET
	var top: float = Layout.UPPER.floorY
	var ceil_up: float = Layout.UPPER.ceilingY
	var arch := Node3D.new()
	arch.name = "architecture"
	_level.add_child(arch)
	_ctx.level_nodes["architecture"] = arch
	var carpet := _mat("carpet016", 1.2, Color(0.85, 0.8, 0.72))
	var wall := _mat("beige_wall_001", 1.5)
	var ceil := _mat("white_stucco", 1.2)
	var conc := _mat("painted_concrete_02", 1.5)
	var block := _mat("concrete_wall_007", 1.5)
	var wood := _mat("stained_pine", 0.8)
	var floorw := _mat("wood_floor_worn", 1.5)
	var dw: Dictionary = A.doorway
	var kx0: float = S.sideWallX - 0.05
	var kx1: float = S.sideWallX + 0.05
	var cdz0: float = C.door.hingeZ
	var cdz1: float = C.door.hingeZ + C.door.width
	# floors (visual only: world physics builds the floors)
	_box(arch, "arch_carpet", Vector3(R.minX, -0.05, R.minZ), Vector3(R.maxX, 0.0, R.maxZ), carpet, false, false)
	_box(arch, "arch_nookFloor", Vector3(A.minX, -0.05, A.minZ), Vector3(A.maxX, 0.0, R.minZ), conc, false, false)
	# outer walls
	_box(arch, "wall_south", Vector3(R.minX - 0.2, 0.0, R.maxZ), Vector3(R.maxX + 0.2, R.ceilingY, R.maxZ + 0.3), wall)
	_box(arch, "wall_east", Vector3(R.maxX, 0.0, A.minZ - 0.2), Vector3(R.maxX + 0.2, 2.75, R.maxZ + 0.3), wall)
	_box(arch, "wall_west", Vector3(R.minX - 0.2, 0.0, R.minZ - 0.15), Vector3(R.minX, ceil_up, R.maxZ + 0.3), wall)
	# north partition with the nook doorway
	_box(arch, "wall_north_w", Vector3(R.minX - 0.2, 0.0, R.minZ - 0.15), Vector3(dw.minX, 2.75, R.minZ), wall)
	_box(arch, "wall_north_e", Vector3(dw.maxX, 0.0, R.minZ - 0.15), Vector3(R.maxX + 0.2, 2.75, R.minZ), wall)
	_box(arch, "wall_north_lintel", Vector3(dw.minX, dw.height, R.minZ - 0.15), Vector3(dw.maxX, 2.75, R.minZ), wall)
	# laundry nook
	_box(arch, "nook_west", Vector3(A.minX - 0.12, 0.0, A.minZ - 0.2), Vector3(A.minX, 2.9, R.minZ - 0.15), block)
	_box(arch, "nook_north", Vector3(A.minX - 0.12, 0.0, A.minZ - 0.2), Vector3(R.maxX + 0.2, 2.9, A.minZ), block)
	_box(arch, "nook_ceiling", Vector3(A.minX - 0.12, 2.75, A.minZ - 0.2), Vector3(R.maxX + 0.2, 2.9, R.minZ), wood, false)
	# ceilings (stair opening over the stairs)
	_box(arch, "arch_ceil", Vector3(kx1, R.ceilingY, R.minZ - 0.15), Vector3(R.maxX + 0.2, R.ceilingY + 0.25, R.maxZ + 0.3), ceil, false)
	_box(arch, "arch_ceil_stairfoot", Vector3(R.minX - 0.2, R.ceilingY, 1.3), Vector3(kx1, R.ceilingY + 0.25, R.maxZ + 0.3), ceil, false)
	_box(arch, "stair_ceiling", Vector3(R.minX - 0.2, ceil_up, R.minZ - 0.15), Vector3(kx1 + 0.05, ceil_up + 0.2, 1.3), ceil, false)
	_box(arch, "stair_bulkhead", Vector3(R.minX, 2.38, 1.15), Vector3(kx1 + 0.01, ceil_up + 0.2, 1.3), ceil, true)
	# knee wall: closet door hole, sloped part beside the lower flight (movement: one tall collider like the web)
	_meta.colliders.append({"min": [kx0 - 0.01, 0, R.minZ], "max": [kx1 + 0.01, ceil_up, S.bottomZ + 0.04], "tag": "wall", "enabled": true})
	_box(arch, "knee_a", Vector3(kx0, 0.0, R.minZ), Vector3(kx1, R.ceilingY, cdz0), wall, false)
	_box(arch, "knee_over_door", Vector3(kx0, C.door.height, cdz0), Vector3(kx1, R.ceilingY, cdz1), wall, false)
	_box(arch, "knee_b", Vector3(kx0, 0.0, cdz1), Vector3(kx1, R.ceilingY, 0.15), wall, false)
	_box(arch, "knee_up", Vector3(kx0, R.ceilingY, R.minZ - 0.15), Vector3(kx1, ceil_up, 1.15), wall, false)
	for i in 6:
		var za: float = 0.15 + i * (float(S.bottomZ) - 0.15) / 6.0
		var zb: float = 0.15 + (i + 1) * (float(S.bottomZ) - 0.15) / 6.0
		var h := maxf(0.2, Layout.stair_height_at(-3.0, za + 0.01) + 0.85)
		_box(arch, "knee_rail_%d" % i, Vector3(kx0, 0.0, za), Vector3(kx1, h, zb), wall, false)
	# stairs: treads + risers (visual), landing
	for k in range(1, int(S.risers)):
		var z1: float = S.bottomZ - (k - 1) * S.treadDepth
		var z0: float = S.bottomZ - k * S.treadDepth
		var hy: float = k * S.riserHeight
		_box(arch, "tread_%d" % k, Vector3(S.minX, hy - 0.035, z0), Vector3(kx0, hy, z1 + 0.02), carpet, false, false)
		_box(arch, "riser_%d" % k, Vector3(S.minX, hy - S.riserHeight, z1 - 0.02), Vector3(kx0, hy - 0.035, z1), ceil, false, false)
	_box(arch, "landing", Vector3(R.minX, top - 0.3, R.minZ), Vector3(kx0, top, S.topZ), carpet, false, true)
	# closet under the stairs (back partition)
	_box(arch, "closet_south", Vector3(R.minX, 0.0, C.maxZ - 0.1), Vector3(kx0, 1.4, C.maxZ), wall, false)
	# stairwell north wall with the upstairs door opening
	var UD: Dictionary = Layout.UPSTAIRS_DOOR
	_box(arch, "door_jamb_w", Vector3(R.minX - 0.2, top, R.minZ - 0.15), Vector3(UD.hingeX, ceil_up, R.minZ), wall)
	_box(arch, "door_jamb_e", Vector3(UD.hingeX + UD.width, top, R.minZ - 0.15), Vector3(kx1 + 0.05, ceil_up, R.minZ), wall)
	_box(arch, "door_head", Vector3(UD.hingeX, top + UD.height, R.minZ - 0.15), Vector3(UD.hingeX + UD.width, ceil_up, R.minZ), wall)
	# upper hallway (shown while the door is open)
	var hall := Node3D.new()
	hall.visible = false
	arch.add_child(hall)
	_level_node(hall, "upperHall")
	_box(hall, "hall_floor", Vector3(H.minX, top - 0.2, H.minZ), Vector3(H.maxX, top, R.minZ), floorw, false, false)
	_box(hall, "hall_west", Vector3(H.minX - 0.2, top, H.minZ - 0.2), Vector3(H.minX, ceil_up, R.minZ - 0.15), wall)
	_box(hall, "hall_east", Vector3(H.maxX, top, H.minZ - 0.2), Vector3(H.maxX + 0.2, ceil_up, R.minZ - 0.15), wall)
	_box(hall, "hall_end", Vector3(H.minX - 0.2, top, H.minZ - 0.2), Vector3(H.maxX + 0.2, ceil_up, H.minZ), wall)
	_box(hall, "hall_ceiling", Vector3(H.minX - 0.2, ceil_up, H.minZ - 0.2), Vector3(H.maxX + 0.2, ceil_up + 0.2, R.minZ), ceil, false)
	var lighting := Node3D.new()
	_level.add_child(lighting)
	_level_node(lighting, "lighting")

func _doors() -> void:
	var UD: Dictionary = Layout.UPSTAIRS_DOOR
	var C: Dictionary = Layout.CLOSET
	var paint := _mat("paintedwood009c", 1.0, Color(0.92, 0.9, 0.85))
	# upstairs door: pivot on the west hinge, slab toward +x, front face +z
	var up := Node3D.new()
	up.position = Vector3(UD.hingeX, UD.bottomY, UD.z)
	_level.add_child(up)
	var r_up := _level_node(up, "door_upstairs")
	_box(up, "doorSlab", Vector3(0.002, 0.015, -UD.thickness), Vector3(UD.width - 0.002, UD.height - 0.003, 0.0), paint, false, false)
	_occluder(Vector3(0, 0, -0.0525), Vector3(UD.width, UD.height, 0.0075), r_up)
	_meta.colliders.append({"min": [UD.hingeX, UD.bottomY, UD.z - 0.15], "max": [UD.hingeX + UD.width, UD.bottomY + UD.height, UD.z], "tag": "door", "enabled": true})
	_door_handle("door.upstairs", up, UD.openAngle, 1.1, true, ["door_creak_open", 1, 1], ["door_close", 1, 1])
	# closet door: pivot on the north hinge (knee wall face), leaf toward +z, opens into the room (+x)
	var cl := Node3D.new()
	cl.position = Vector3(Layout.STAIRS.sideWallX + 0.05, 0.0, C.door.hingeZ)
	_level.add_child(cl)
	var r_cl := _level_node(cl, "door_closet")
	_box(cl, "closetLeaf", Vector3(-0.032, 0.012, 0.003), Vector3(0.0, C.door.height - 0.012, C.door.width - 0.003), paint, false, false)
	_occluder(Vector3(-0.041, 0.0, 0.0), Vector3(0.009, C.door.height, C.door.width), r_cl)
	var x0: float = cl.position.x
	_meta.colliders.append({"min": [x0, 0, C.door.hingeZ - 0.05], "max": [x0 + C.door.width, C.door.height, C.door.hingeZ + 0.03], "tag": "door", "enabled": false})
	_door_handle("door.closet", cl, C.door.openAngle, 0.6, false, ["door_creak_open", 0.5, 1.3], ["door_close", 0.45, 1.35])

func _door_handle(id: String, pivot: Node3D, angle: float, dur: float, locked: bool, sfx_open: Array, sfx_close: Array) -> void:
	var closed := pivot.transform
	var open := Transform3D(Basis(Vector3.UP, angle), pivot.position)
	_meta.handles[id] = {"id": id, "kind": "door", "object": {"level": pivot.name}, "moving": [{"ref": {"level": pivot.name}, "closed": _m16(closed), "open": _m16(open)}],
		"primary": 0, "locked": locked, "initiallyOpen": false, "duration": [dur, dur], "sfx": {"open": sfx_open, "close": sfx_close}, "contents": null}

# ------------------------------------------------------------------ models

func _place(n: String, p: Dictionary, extra: bool) -> void:
	var path: String = MODELS % p.model
	if not ResourceLoader.exists(path):
		_ctx.errors.append("missing model " + path)
		return
	var ps := load(path) as PackedScene
	if ps == null: return
	var inst := ps.instantiate() as Node3D
	inst.name = n
	var pos: Array = p.pos
	inst.position = Vector3(pos[0], pos[1], pos[2])
	var s := float(p.get("scale", 1.0))
	if extra:
		inst.basis = Basis.from_euler(Vector3(p.get("rotX", 0.0), p.get("rotY", 0.0), p.get("rotZ", 0.0)), EULER_ORDER_ZXY).scaled(Vector3(s, s, s))
	else:
		inst.basis = Basis(Vector3.UP, float(ROT.get(n, p.get("rotY", 0.0)))).scaled(Vector3(s, s, s))
	_level.add_child(inst)
	for hn in p.get("hideNodes", []):
		var h := inst.find_child(String(hn), true, false)
		if h != null: h.free()
	if p.has("hidePrefix"):
		for c in inst.find_children(String(p.hidePrefix) + "*", "", true, false):
			if is_instance_valid(c) and c != inst: c.free()
	if p.has("zeroNodeX"):
		var z := inst.find_child(String(p.zeroNodeX), true, false) as Node3D
		if z != null: z.position.x = 0.0
	_ctx.instances[n] = inst
	var key: String = n.trim_prefix("extra_")
	var collide: bool = COLLIDE.has(n) if not extra else (not p.get("noCollider", false) and key != "suitcase")
	if collide:
		var bb := _aabb(inst)
		if bb.size != Vector3.ZERO:
			_meta.colliders.append({"min": [bb.position.x, bb.position.y, bb.position.z], "max": [bb.end.x, bb.end.y, bb.end.z], "tag": n if not extra else "prop", "enabled": true})

static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var has := false
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		out = out.merge(b) if has else b
		has = true
	return out

func _rocking_chair() -> void:
	var chair: Node3D = _ctx.instances.get("rockingChair")
	if chair == null: return
	var root := Node3D.new()
	root.position = Vector3(chair.position.x, 0.0, chair.position.z)
	root.rotation.y = chair.rotation.y
	_level.add_child(root)
	_level_node(root, "rockingChair_root")
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 0.95, 0.0)
	root.add_child(pivot)
	_level_node(pivot, "rockingChair_pivot")
	var y0 := chair.position.y
	chair.reparent(pivot, false)
	chair.transform = Transform3D(Basis(), Vector3(0.0, y0 - 0.95, 0.0))
	_meta.anim["rockingChair"] = {"root": {"level": "rockingChair_root"}, "pivot": {"level": "rockingChair_pivot"}, "radius": 0.95}

# ------------------------------------------------------------------ handles (web offsets / angles)

func _contents(parent: Node3D, n: String, pos: Vector3) -> Dictionary:
	var c := Node3D.new()
	c.position = pos
	parent.add_child(c)
	return _level_node(c, n)

func _slide(id: String, inst_name: String, node_name: String, dz: float, dur: Array, contents_pos: Vector3, z_closed := NAN) -> void:
	var inst: Node3D = _ctx.instances.get(inst_name)
	var node := inst.find_child(node_name, true, false) as Node3D if inst else null
	if node == null: return
	if not is_nan(z_closed): node.position.z = z_closed
	var closed := node.transform
	var open := closed.translated(Vector3(0, 0, dz))
	var cref := _contents(node, id.replace(".", "_") + "_contents", contents_pos)
	_meta.handles[id] = {"id": id, "kind": "drawer", "object": _ref(inst_name, node), "moving": [{"ref": _ref(inst_name, node), "closed": _m16(closed), "open": _m16(open)}],
		"primary": 0, "locked": false, "initiallyOpen": false, "duration": dur, "sfx": {"open": ["drawer_open", 1, 1], "close": ["drawer_close", 1, 1]}, "contents": cref}

func _swing(id: String, inst_name: String, node_name: String, angle: float, dur: Array, sfx_vol: float, contents: Variant) -> void:
	var inst: Node3D = _ctx.instances.get(inst_name)
	var node := inst.find_child(node_name, true, false) as Node3D if inst else null
	if node == null: return
	var closed := node.transform
	var open := Transform3D(Basis(Vector3.UP, angle) * closed.basis, closed.origin)
	_meta.handles[id] = {"id": id, "kind": "cabinetDoor", "object": _ref(inst_name, node), "moving": [{"ref": _ref(inst_name, node), "closed": _m16(closed), "open": _m16(open)}],
		"primary": 0, "locked": false, "initiallyOpen": false, "duration": dur, "sfx": {"open": ["cabinet_open", sfx_vol, 1], "close": ["cabinet_close", sfx_vol, 1]}, "contents": contents}

func _handles() -> void:
	_slide("dresser.drawerTop", "dresser", "GothicCommode_01_door01", 0.3, [0.55, 0.45], Vector3(0, -0.088, -0.27))
	_slide("dresser.drawerMid", "dresser", "GothicCommode_01_door02", 0.3, [0.55, 0.45], Vector3(0, -0.086, -0.27))
	_slide("dresser.drawerBottom", "dresser", "GothicCommode_01_door03", 0.3, [0.55, 0.45], Vector3(0, -0.085, -0.27))
	_slide("endTable.drawer", "endTable", "painted_wooden_nightstand_drawer", 0.22, [0.5, 0.4], Vector3(0, -0.042, -0.17))
	_slide("alcoveCabinet.drawer_01", "alcoveCabinet", "painted_wooden_cabinet_drawer_01", 0.24, [0.55, 0.45], Vector3(0, -0.13, -0.17), 0.235)
	_slide("alcoveCabinet.drawer_02", "alcoveCabinet", "painted_wooden_cabinet_drawer_02", 0.24, [0.55, 0.45], Vector3(0, -0.13, -0.17), 0.235)
	var cab: Node3D = _ctx.instances.get("alcoveCabinet")
	if cab != null:
		_swing("alcoveCabinet.door_01", "alcoveCabinet", "painted_wooden_cabinet_door_01", -1.85, [0.75, 0.6], 1.0, _contents(cab, "alcoveCabinet_door_01_contents", Vector3(-0.3, 0.17, 0.02)))
		_swing("alcoveCabinet.door_02", "alcoveCabinet", "painted_wooden_cabinet_door_02", 1.85, [0.75, 0.6], 1.0, _contents(cab, "alcoveCabinet_door_02_contents", Vector3(0.3, 0.17, 0.02)))
	_swing("powerBox.door", "powerBox", "power_box_01_door", -1.9, [0.7, 0.55], 0.9, null)
	# breaker lever (procedural): group on the panel, pivot rotates about x (0.6 = OFF .. -0.6 = ON)
	var pb: Node3D = _ctx.instances.get("powerBox")
	if pb != null:
		var g := Node3D.new()
		pb.add_child(g)
		_level_node(g, "powerBox_lever")
		var pivot := Node3D.new()
		pivot.position = Vector3(0.105, 0.05, 0.024)
		g.add_child(pivot)
		_level_node(pivot, "powerBox_lever_pivot")
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.56, 0.11, 0.09)
		red.roughness = 0.42
		_box(pivot, "powerBox_lever_arm", Vector3(-0.017, -0.0045, 0.0), Vector3(0.017, 0.0045, 0.02), red, false, false)
		var closed := Transform3D(Basis(Vector3.RIGHT, 0.6), pivot.position)
		var open := Transform3D(Basis(Vector3.RIGHT, -0.6), pivot.position)
		_meta.handles["powerBox.lever"] = {"id": "powerBox.lever", "kind": "lever", "object": {"level": "powerBox_lever"},
			"moving": [{"ref": {"level": "powerBox_lever_pivot"}, "closed": _m16(closed), "open": _m16(open)}], "primary": 0, "locked": false,
			"initiallyOpen": true, "duration": [0.2, 0.2], "sfx": {"open": ["breaker_flip", 1, 1], "close": ["breaker_flip", 1, 1]}, "contents": null}
	# locked box: lid hinge + contents + a simple brass padlock
	var box: Node3D = _ctx.instances.get("lockedBox")
	if box != null:
		var s := box.scale.x if box.scale.x > 0.0 else 1.0
		var hinge := Node3D.new()
		hinge.position = Vector3(0.0, 0.066, -0.0527)
		box.add_child(hinge)
		_level_node(hinge, "lockedBox_lid")
		var lid := box.find_child("CheeseBox_01_lid", true, false) as Node3D
		if lid != null:
			lid.reparent(hinge, false)
			lid.position = Vector3(0.0, 0.002 - 0.066, 0.0527)
		var cref := _contents(box, "lockedBox_contents", Vector3(-0.055, 0.0045, 0.0))
		(_ctx.level_nodes["lockedBox_contents"] as Node3D).scale = Vector3.ONE / s
		_meta.handles["lockedBox.lid"] = {"id": "lockedBox.lid", "kind": "lid", "object": {"level": "lockedBox_lid"},
			"moving": [{"ref": {"level": "lockedBox_lid"}, "closed": _m16(hinge.transform), "open": _m16(Transform3D(Basis(Vector3.RIGHT, -1.92), hinge.position))}],
			"primary": 0, "locked": false, "initiallyOpen": false, "duration": [0.85, 0.5], "sfx": {"open": ["box_open", 0.8, 1], "close": ["cabinet_close", 0.8, 1]}, "contents": cref}
		var frame := Node3D.new()
		frame.scale = Vector3.ONE / s
		box.add_child(frame)
		_level_node(frame, "lockedBox_frame")
		var lock := Node3D.new()
		frame.add_child(lock)
		_level_node(lock, "lockedBox_lock")
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.76, 0.6, 0.28)
		brass.metallic = 1.0
		brass.roughness = 0.32
		_box(lock, "lockedBox_lock_body", Vector3(-0.017, -0.0645, -0.007), Vector3(0.017, -0.0205, 0.007), brass, false, false)
		var shackle := Node3D.new()
		lock.add_child(shackle)
		_level_node(shackle, "lockedBox_lock_shackle")
		_box(shackle, "shackle_mesh", Vector3(-0.0105, -0.03, -0.002), Vector3(0.0105, 0.0, 0.002), brass, false, false)
		var wheels: Array = []
		for i in 4:
			var w := Node3D.new()
			w.position = Vector3(-0.0105 + i * 0.007, -0.0485, 0.0047)
			lock.add_child(w)
			wheels.append(_level_node(w, "lockedBox_lock_dial%d" % i))
		var rest := Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0.0, 0.068, 0.053 * s + 0.0066))
		lock.transform = rest
		var fallen := Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.5), EULER_ORDER_XYZ), Vector3(0.05, 0.0075, 0.053 * s + 0.022))
		_meta.handles["lockedBox.lock"] = {"id": "lockedBox.lock", "kind": "padlock", "object": {"level": "lockedBox_lock"},
			"moving": [{"ref": {"level": "lockedBox_lock"}, "closed": _m16(rest), "open": _m16(fallen)},
				{"ref": {"level": "lockedBox_lock_shackle"}, "closed": _m16(Transform3D()), "open": _m16(Transform3D(Basis(), Vector3(0, 0.0095, 0)))}],
			"primary": 0, "locked": false, "initiallyOpen": false, "duration": [0.68, 0.0], "sfx": {"open": ["unlock", 1, 1], "close": null}, "contents": null}
		_meta.anim["padlock"] = {"wheels": wheels}

# ------------------------------------------------------------------ items, TV, clues

func _note(n: String, file: String, size: Vector2, parent: Node3D, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(NOTES % file): m.albedo_texture = load(NOTES % file)
	mi.material_override = m
	parent.add_child(mi)
	mi.transform = xf
	_level_node(mi, n)
	_meta.items[n] = {"ref": {"level": n}, "inside": null, "transform": _m16(mi.global_transform)}

func _items() -> void:
	var ln: Dictionary = _ctx.level_nodes
	# flashlight model in the top drawer
	var top = ln.get("dresser_drawerTop_contents")
	if top is Node3D and ResourceLoader.exists(MODELS % "pastic_torch_6v"):
		var fl := (load(MODELS % "pastic_torch_6v") as PackedScene).instantiate() as Node3D
		fl.name = "flashlight"
		(top as Node3D).add_child(fl)
		fl.transform = Transform3D(Basis(Vector3.UP, 1.15), Vector3(-0.2, 0.07, 0.02))
		_ctx.instances["flashlight"] = fl
		_meta.items["flashlight"] = {"ref": {"instance": "flashlight"}, "inside": "dresser.drawerTop", "transform": _m16(fl.global_transform)}
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.12, 0.12, 0.13)
	metal.metallic = 0.4
	metal.roughness = 0.35
	for spec in [["battery1", "endTable_drawer_contents", Vector3(0.06, 0.0, 0.03), "endTable.drawer"], ["battery2", "alcoveCabinet_drawer_01_contents", Vector3(-0.04, 0.0, 0.04), "alcoveCabinet.drawer_01"]]:
		var parent = ln.get(spec[1])
		if not (parent is Node3D): continue
		var g := Node3D.new()
		(parent as Node3D).add_child(g)
		g.position = spec[2]
		_box(g, spec[0] + "_mesh", Vector3(-0.029, 0.0, -0.034), Vector3(0.029, 0.034, 0.034), metal, false, false)
		_level_node(g, spec[0])
		_meta.items[spec[0]] = {"ref": {"level": spec[0]}, "inside": spec[3], "transform": _m16(g.global_transform)}
	var kc = ln.get("lockedBox_contents")
	if kc is Node3D:
		var k := Node3D.new()
		(kc as Node3D).add_child(k)
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.78, 0.62, 0.3)
		brass.metallic = 1.0
		brass.roughness = 0.28
		_box(k, "key_mesh", Vector3(-0.012, 0.0, -0.006), Vector3(0.06, 0.003, 0.006), brass, false, false)
		_level_node(k, "key")
		_meta.items["key"] = {"ref": {"level": "key"}, "inside": "lockedBox.lid", "transform": _m16(k.global_transform)}
	var I: Dictionary = Layout.ITEMS
	_note("note1", "note1.jpg", Vector2(0.148, 0.203), _level, Transform3D(Basis(Vector3.UP, I.note1.rotY), Vector3(I.note1.pos[0], I.note1.pos[1] - 0.01, I.note1.pos[2])))
	_note("note2", "note2_child_drawing.jpg", Vector2(0.297, 0.21), _level, Transform3D(Basis(Vector3.UP, I.note2.rotY), Vector3(I.note2.pos[0], I.note2.pos[1] - 0.004, I.note2.pos[2])))
	var n3 = ln.get("alcoveCabinet_door_01_contents")
	if n3 is Node3D:
		_note("note3", "note3_newspaper.png", Vector2(0.16, 0.219), n3, Transform3D(Basis(Vector3.UP, 0.25), Vector3(0, 0.002, 0.02)))
		_meta.items["note3"]["inside"] = "alcoveCabinet.door_01"

func _tv_and_clues() -> void:
	var tv: Node3D = _ctx.instances.get("tv")
	if tv != null:
		var scr := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.292, 0.212)
		scr.mesh = qm
		scr.position = Vector3(0.0, 0.26, 0.124)
		scr.visible = false
		tv.add_child(scr)
		_level_node(scr, "tv_screen")
		var sp := scr.global_position
		_meta.tv = {"object": {"instance": "tv"}, "screen": {"level": "tv_screen"}, "screenPosition": [sp.x, sp.y, sp.z], "color": [1.35, 1.4, 1.5]}
	_meta.clues = {"duck": {"instance": "duck"}, "horse": {"instance": "horse"}, "clock": {"instance": "grandfather"}, "tv": {"instance": "tv"}}
	for key in ["duck", "horse"]:
		var inst: Node3D = _ctx.instances.get(key)
		if inst == null: continue
		var s := inst.scale.x if inst.scale.x > 0.0 else 1.0
		var size := Vector2(0.055, 0.055) if key == "duck" else Vector2(0.05, 0.04)
		var local := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, 0.0012 / s, (0.01 if key == "duck" else 0.0) / s))
		_meta.clueDecals[key] = {"parent": {"instance": key}, "local": _m16(local), "size": [size.x / s, size.y / s], "style": "marker" if key == "duck" else "tape"}
	var C: Dictionary = Layout.CLOSET
	_meta.hideSpots = [{"id": "closet", "door": "door.closet", "hidePos": C.hidePos, "hideYaw": C.hideYaw, "exitPos": C.exitPos,
		"minX": C.minX, "maxX": C.maxX, "minZ": C.minZ, "maxZ": C.maxZ, "doorSpec": C.door}]

func _anim() -> void:
	var fan: Node3D = _ctx.instances.get("fan")
	var blades := fan.find_child("ceiling_fan_blades", true, false) if fan else null
	if blades != null: _meta.anim["fan"] = {"blades": _ref("fan", blades), "speed": 2.4, "spinUpRate": 0.45, "spinDownRate": 0.16}
	var gf: Node3D = _ctx.instances.get("grandfather")
	if gf != null:
		var g := {}
		for spec in [["hour", "vintage_grandfather_clock_01_HourHand"], ["minute", "vintage_grandfather_clock_01_MinuteHand"]]:
			var h := gf.find_child(spec[1], true, false)
			if h != null: g[spec[0]] = {"node": _ref("grandfather", h), "a0": PI / 2.0}
		_meta.anim["grandfatherClock"] = g
	var mirror: Node3D = _ctx.instances.get("extra_mirror")
	if mirror != null:
		var glass := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.438, 0.685)
		glass.mesh = qm
		glass.position = Vector3(0.0, -0.0435, 0.0088)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.85, 0.83, 0.78)
		gm.metallic = 1.0
		gm.roughness = 0.12
		glass.material_override = gm
		mirror.add_child(glass)
		_level_node(glass, "extra_mirror_glass")
		_meta.anim["mirror"] = {"glass": {"level": "extra_mirror_glass"}, "root": {"instance": "extra_mirror"}}
	var crt: Node3D = _ctx.instances.get("extra_oldTv")
	if crt != null:
		var scr := MeshInstance3D.new()
		var qm2 := QuadMesh.new()
		qm2.size = Vector2(0.36, 0.27)
		scr.mesh = qm2
		scr.position = Vector3(-0.066, 0.259, 0.2)
		scr.visible = false
		crt.add_child(scr)
		_level_node(scr, "extra_crt_screen")
		var sp := crt.global_transform * Vector3(-0.066, 0.26, 0.2)
		_meta.anim["oldCrt"] = {"screen": {"level": "extra_crt_screen"}, "tv": {"instance": "extra_oldTv"}, "soundPos": [sp.x, sp.y, sp.z]}
