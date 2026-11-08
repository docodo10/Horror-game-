## Player-module test world (NOT the game world): builds the basement from Layout with what the player needs to be
## exercised — floors, walls with the laundry-nook doorway, ceiling, stair ramp collider (+ visual treads), landing and
## upper hall, knee wall, the closet under the stairs with a real Handle door, a few real furniture models with box
## colliders, a 40 m running track (stamina test) — plus the subset of the world API the player calls:
## power / set_power(on), handles, hide_spots, items, clues, ground_height_at(), line_blocked().
extends Node3D

const LAYER_WORLD := 1

var power := true
var handles := {}
var items := {}
var clues := {}
var hide_spots: Array = []
var tv: Node = null
var lighting: Node = null
var env: Environment
var _lights: Array[Light3D] = []
var _mats := {}

func build(progress: Callable) -> void:
	progress.call(0.1, "Sandbox joueur…")
	var R: Dictionary = Layout.ROOM
	var S: Dictionary = Layout.STAIRS
	var A: Dictionary = Layout.ALCOVE
	var C: Dictionary = Layout.CLOSET
	var carpet := _mat("carpet016", 0.5)
	var wall := _mat("beige_wall_001", 0.6)
	var ceil_m := _mat("ceiling_interior", 0.5)
	var concrete := _mat("painted_concrete_02", 0.5)
	var wood := _mat("stained_pine", 0.8)
	var white := _mat("white_stucco", 0.6)

	# floors
	_box(Vector3(0, -0.1, 0), Vector3(7.0, 0.2, 5.5), carpet)
	_box(Vector3((A.minX + A.maxX) * 0.5, -0.1, (A.minZ + A.maxZ) * 0.5), Vector3(A.maxX - A.minX, 0.2, A.maxZ - A.minZ), concrete)
	# outer walls (main room)
	_box(Vector3(0, 1.25, R.maxZ + 0.1), Vector3(7.4, 2.5, 0.2), wall)                     # south
	_box(Vector3(R.maxX + 0.1, 1.25, 0), Vector3(0.2, 2.5, 5.9), wall)                     # east
	_box(Vector3(R.minX - 0.1, 2.6, 0), Vector3(0.2, 5.2, 5.9), wall)                      # west (stairwell height)
	# north wall with the nook doorway (x 0.9..1.8, h 2.05) — the stairs/closet part is handled below
	var dw: Dictionary = A.doorway
	_box(Vector3((-2.55 + float(dw.minX)) * 0.5, 1.25, R.minZ - 0.1), Vector3(float(dw.minX) + 2.55, 2.5, 0.2), wall)
	_box(Vector3((float(dw.maxX) + R.maxX) * 0.5, 1.25, R.minZ - 0.1), Vector3(R.maxX - float(dw.maxX), 2.5, 0.2), wall)
	_box(Vector3((float(dw.minX) + float(dw.maxX)) * 0.5, 2.275, R.minZ - 0.1), Vector3(float(dw.maxX) - float(dw.minX), 0.45, 0.2), wall)
	# nook walls
	_box(Vector3(A.minX - 0.1, 1.25, (A.minZ + R.minZ) * 0.5), Vector3(0.2, 2.5, R.minZ - A.minZ), concrete)
	_box(Vector3(A.maxX + 0.1, 1.25, (A.minZ + R.minZ) * 0.5), Vector3(0.2, 2.5, R.minZ - A.minZ), concrete)
	_box(Vector3((A.minX + A.maxX) * 0.5, 1.25, A.minZ - 0.1), Vector3(A.maxX - A.minX + 0.4, 2.5, 0.2), concrete)
	# ceilings (main room minus the stairwell opening, nook)
	_box(Vector3(0.48, 2.6, 0), Vector3(6.06, 0.2, 5.5), ceil_m)
	_box(Vector3(-3.025, 2.6, (1.15 + R.maxZ) * 0.5), Vector3(0.95, 0.2, R.maxZ - 1.15), ceil_m)
	_box(Vector3((A.minX + A.maxX) * 0.5, 2.6, (A.minZ + R.minZ) * 0.5), Vector3(A.maxX - A.minX, 0.2, R.minZ - A.minZ), ceil_m)

	# stairs: invisible ramp collider (like the real world) + visual treads/risers
	var top_y: float = Layout.UPPER.floorY
	var bz: float = S.bottomZ
	var tz: float = S.topZ
	var a := Vector3(0, -0.06, bz + 0.06 * (bz - tz) / top_y)
	var b := Vector3(0, top_y, tz)
	var u := (b - a).normalized()
	var n := Vector3(0, -u.z, u.y)                 # ramp normal (up / toward +z)
	var length := a.distance_to(b)
	var ramp := StaticBody3D.new()
	ramp.name = "StairRamp"
	ramp.collision_layer = LAYER_WORLD
	var rcs := CollisionShape3D.new()
	var rsh := BoxShape3D.new()
	rsh.size = Vector3(S.maxX - S.minX, 0.1, length)
	rcs.shape = rsh
	ramp.add_child(rcs)
	var mid := (a + b) * 0.5 - n * 0.05
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, n, -u), Vector3((S.minX + S.maxX) * 0.5, mid.y, mid.z))
	ramp.set_meta("tag", "stairs")
	add_child(ramp)
	var risers := int(S.risers)
	for k in range(1, risers):
		var z1 := bz - (k - 1) * float(S.treadDepth)
		var z0 := bz - k * float(S.treadDepth)
		var hy := k * float(S.riserHeight)
		_mesh_box(Vector3((S.minX + S.maxX) * 0.5, hy - 0.02, (z0 + z1) * 0.5), Vector3(S.maxX - S.minX, 0.04, z1 - z0 + 0.03), wood)
		_mesh_box(Vector3((S.minX + S.maxX) * 0.5, hy - float(S.riserHeight) * 0.5, z1 - 0.01), Vector3(S.maxX - S.minX, float(S.riserHeight), 0.02), white)
	# landing + upper hall floors
	_box(Vector3((S.minX + S.maxX) * 0.5, top_y - 0.1, (R.minZ + tz) * 0.5), Vector3(S.maxX - S.minX, 0.2, tz - R.minZ), wood)
	var UH: Dictionary = Layout.UPPER_HALL
	_box(Vector3((UH.minX + UH.maxX) * 0.5, top_y - 0.1, (UH.minZ + UH.maxZ) * 0.5), Vector3(UH.maxX - UH.minX, 0.2, UH.maxZ - UH.minZ), wood)
	_box(Vector3((UH.minX + UH.maxX) * 0.5, top_y + 1.2, UH.minZ - 0.1), Vector3(UH.maxX - UH.minX, 2.4, 0.2), wall)
	_box(Vector3(UH.maxX + 0.1, top_y + 1.2, (UH.minZ + UH.maxZ) * 0.5), Vector3(0.2, 2.4, UH.maxZ - UH.minZ), wall)
	_box(Vector3(UH.minX - 0.1, top_y + 1.2, (UH.minZ + UH.maxZ) * 0.5), Vector3(0.2, 2.4, UH.maxZ - UH.minZ), wall)
	# knee wall / railing line x = -2.55 along the stairs (tall invisible collider, short visible wall)
	var kx: float = S.sideWallX
	_collider(Vector3(kx, 1.9, (C.maxZ + bz) * 0.5), Vector3(0.1, 3.8, bz - float(C.maxZ)), "railing")
	_mesh_box(Vector3(kx, 0.5, (C.maxZ + bz) * 0.5), Vector3(0.1, 1.0, bz - float(C.maxZ)), white)
	# landing guard above the closet (x = -2.55, z from the room wall to the top of the stairs)
	_collider(Vector3(kx, top_y + 0.5, (R.minZ + tz) * 0.5), Vector3(0.1, 1.0, tz - R.minZ), "railing")

	# closet under the stairs: front wall with the door opening, back wall, real Handle door
	var door_cfg: Dictionary = C.door
	var dz0: float = float(door_cfg.centerZ) - float(door_cfg.width) * 0.5
	var dz1: float = float(door_cfg.centerZ) + float(door_cfg.width) * 0.5
	var dh: float = door_cfg.height
	_box(Vector3(kx, top_y * 0.5, (R.minZ + dz0) * 0.5), Vector3(0.1, top_y, dz0 - R.minZ), white)
	_box(Vector3(kx, top_y * 0.5, (dz1 + float(C.maxZ)) * 0.5), Vector3(0.1, top_y, float(C.maxZ) - dz1), white)
	_box(Vector3(kx, (dh + top_y) * 0.5, (dz0 + dz1) * 0.5), Vector3(0.1, top_y - dh, dz1 - dz0), white)
	_box(Vector3((R.minX + kx) * 0.5, 0.8, float(C.maxZ) + 0.05), Vector3(kx - R.minX, 1.6, 0.1), white)
	_box(Vector3((R.minX + kx) * 0.5, (top_y - 0.2) * 0.5, R.minZ - 0.1), Vector3(kx - R.minX, top_y - 0.2, 0.2), white)
	var pivot := Node3D.new()
	pivot.name = "ClosetDoor"
	pivot.position = Vector3(kx + 0.03, 0, float(door_cfg.hingeZ))
	add_child(pivot)
	var leaf := AnimatableBody3D.new()
	leaf.collision_layer = LAYER_WORLD
	leaf.sync_to_physics = false
	pivot.add_child(leaf)
	var lcs := CollisionShape3D.new()
	var lsh := BoxShape3D.new()
	lsh.size = Vector3(0.035, dh, float(door_cfg.width))
	lcs.shape = lsh
	lcs.position = Vector3(0, dh * 0.5, float(door_cfg.width) * 0.5)
	leaf.add_child(lcs)
	var lmi := MeshInstance3D.new()
	var lbm := BoxMesh.new()
	lbm.size = lsh.size
	lmi.mesh = lbm
	lmi.material_override = white
	lmi.position = lcs.position
	leaf.add_child(lmi)
	var h := Handle.new()
	h.id = "door.closet"
	h.node = pivot
	h.closed_xform = pivot.transform
	h.open_xform = Transform3D(Basis(Vector3.UP, float(door_cfg.openAngle)), pivot.position)
	h.duration = 0.6
	h.sfx_open = "door_creak_open"
	h.sfx_close = "door_close"
	handles[h.id] = h
	var hp: Dictionary = C.hidePos
	var ep: Dictionary = C.exitPos
	hide_spots.append({"id": "closet", "door": h, "hide_pos": Vector3(hp.x, hp.y, hp.z), "hide_yaw": float(C.hideYaw),
		"exit_pos": Vector3(ep.x, 0.0, ep.z)})

	progress.call(0.5, "Meubles…")
	# real furniture (box colliders from their AABB)
	for id in ["sofa", "coffeeTable", "endTable", "dresser", "tv", "grandfather", "shelves", "console", "chairA", "chairB",
			"rockingChair", "kidTable", "kidChair", "alcoveCabinet", "boxA", "boxB", "boxC"]:
		var pr: Dictionary = Layout.PROPS[id]
		var p: Array = pr.pos
		_model(str(pr.model), Vector3(p[0], p[1], p[2]), float(pr.rotY), float(pr.get("scale", 1.0)), id)

	# running track for the stamina test (outside the house)
	_box(Vector3(30, -0.1, 0), Vector3(42, 0.2, 2.0), carpet)
	_collider(Vector3(30, 1.0, 1.1), Vector3(42, 2.0, 0.2), "wall")
	_collider(Vector3(30, 1.0, -1.1), Vector3(42, 2.0, 0.2), "wall")
	_collider(Vector3(51.1, 1.0, 0), Vector3(0.2, 2.0, 2.4), "wall")

	# lights + environment (a stand-in for the look module, only so screenshots are readable)
	var lamp := OmniLight3D.new()
	lamp.name = "CeilingLamp"
	lamp.position = Vector3(Layout.FAN.x, 2.22, Layout.FAN.z)
	lamp.light_color = Color(1.0, 0.78, 0.52)
	lamp.light_energy = 1.6
	lamp.omni_range = 9.0
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = true
	add_child(lamp)
	_lights.append(lamp)
	var bulb := OmniLight3D.new()
	bulb.name = "NookBulb"
	bulb.position = Vector3(1.8, 2.2, -3.6)
	bulb.light_color = Color(1.0, 0.8, 0.6)
	bulb.light_energy = 0.6
	bulb.omni_range = 4.0
	bulb.shadow_enabled = true
	add_child(bulb)
	_lights.append(bulb)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.3, 0.28)
	env.ambient_light_energy = 0.08
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	if DisplayServer.get_name() != "headless":
		env.ssao_enabled = true
		env.ssao_radius = 0.8
		env.glow_enabled = true
		env.glow_intensity = 0.4
		env.glow_bloom = 0.02
		env.volumetric_fog_enabled = "--no-fog" not in OS.get_cmdline_user_args()
		env.volumetric_fog_density = 0.02
		env.volumetric_fog_albedo = Color(0.85, 0.82, 0.78)
		env.volumetric_fog_length = 16.0
		env.volumetric_fog_anisotropy = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	progress.call(1.0, "Prêt")

func set_power(on: bool) -> void:
	power = on
	for l in _lights:
		l.visible = on
	env.ambient_light_energy = 0.08 if on else 0.012
	Events.power_changed.emit(on)

func ground_height_at(x: float, z: float, prev_y := NAN) -> float:
	return Layout.ground_height_at(x, z, prev_y)

func line_blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func reset_after_caught() -> void:
	pass

# ---------------------------------------------------------------- helpers

func _mat(set_name: String, scale: float, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := "res://assets/textures/%s/" % set_name
	m.albedo_color = tint
	if ResourceLoader.exists(base + "color.jpg"):
		m.albedo_texture = load(base + "color.jpg")
	if ResourceLoader.exists(base + "normal.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "normal.jpg")
	if ResourceLoader.exists(base + "rough.jpg"):
		m.roughness_texture = load(base + "rough.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m

func _box(pos: Vector3, size: Vector3, mat: Material, tag := "wall") -> void:
	_collider(pos, size, tag)
	_mesh_box(pos, size, mat)

func _collider(pos: Vector3, size: Vector3, tag := "wall") -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.position = pos
	body.set_meta("tag", tag)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)

func _mesh_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _model(model: String, pos: Vector3, rot_y: float, scale: float, tag: String) -> void:
	var path := "res://assets/models/%s.glb" % model
	if not ResourceLoader.exists(path):
		return
	var ps := load(path) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	inst.position = pos
	inst.rotation.y = rot_y
	inst.scale = Vector3.ONE * scale
	add_child(inst)
	var box := _world_aabb(inst)
	if box.size.y > 0.05:
		_collider(box.get_center(), box.size, tag)

func _world_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var b: AABB = mi.global_transform * mi.get_aabb()
			if first:
				out = b
				first = false
			else:
				out = out.merge(b)
		for ch in c.get_children():
			stack.append(ch)
	return out
