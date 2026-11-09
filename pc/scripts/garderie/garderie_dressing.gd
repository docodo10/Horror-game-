## Set dressing of the garderie (the reference's prop density without draw-call cost):
##  * ~450 pieces of small debris as MultiMeshes (one per kind: crumpled candy wrappers, crayons, socks, paper cups,
##    popcorn, paper scraps, toy foam cubes): drifted against the walls, around the frame and the party tables, a few
##    in the vestibule; random yaw, ±15 % scale, lying / tilted; no shadows (SSAO gives the contact), visibility range.
##  * ~38 Decals (dusty footprints along the walked paths, rubber scuffs, dried juice spills, crayon on the floor and
##    walls, grime in the corners, water stains on the ceiling tiles): restricted cull masks, distance fade at 15 m.
##  * Dust motes (GPUParticles3D, 140 lit specks each) drifting in the cones of 4 working high-bays, emitting only
##    while the camera is in the hall (set_motes).
##  * A few lifted corners of EVA mats (real geometry in the mats' own material, 3-8 mm curl + a dark gap).
## build(ctx) -> void, set_motes(on), motes: Array[GPUParticles3D], counts: Dictionary
extends RefCounted

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")

const VIS_FRONT := 1024
const VIS_HALL := 2048
const WRAP_COLS := [Color(0.85, 0.62, 0.12), Color(0.62, 0.08, 0.06), Color(0.1, 0.24, 0.6), Color(0.1, 0.45, 0.16),
	Color(0.75, 0.75, 0.72), Color(0.75, 0.25, 0.45), Color(0.9, 0.42, 0.06)]
const CRAYON_COLS := [Color(0.62, 0.06, 0.05), Color(0.08, 0.2, 0.55), Color(0.82, 0.6, 0.06), Color(0.08, 0.42, 0.14),
	Color(0.85, 0.35, 0.05), Color(0.4, 0.12, 0.48), Color(0.08, 0.06, 0.05), Color(0.62, 0.32, 0.16)]
const SOCK_COLS := [Color(0.85, 0.85, 0.82), Color(0.75, 0.3, 0.45), Color(0.15, 0.3, 0.6), Color(0.8, 0.6, 0.15)]
const CUP_COLS := [Color(0.9, 0.88, 0.82), Color(0.82, 0.25, 0.2), Color(0.2, 0.42, 0.75), Color(0.85, 0.7, 0.2)]
const PAPER_COLS := [Color(0.92, 0.9, 0.84), Color(0.85, 0.8, 0.62), Color(0.78, 0.86, 0.9), Color(0.9, 0.75, 0.8)]

var motes: Array[GPUParticles3D] = []
var counts := {}
var _decals := 0

func build(c) -> void:
	_debris(c)
	_decals_all(c)
	_motes(c)
	_lifted_corners(c)
	counts["decals"] = _decals
	counts["motes"] = motes.size()

## Starts / stops the dust motes (only while the camera is in the hall).
func set_motes(on: bool) -> void:
	for m in motes:
		if is_instance_valid(m):
			m.emitting = on
			m.visible = on

# ====================================================================== debris meshes

static func _mesh_of(k, mat_id: String, mats) -> ArrayMesh:
	var m := Kit.build_mesh(k.bin(mat_id))
	m.surface_set_material(0, mats.mat(mat_id))
	return m

static func _wrapper_mesh(mats) -> ArrayMesh:
	var k := Kit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var nx := 6
	var nz := 4
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	for j in nz + 1:
		for i in nx + 1:
			var x := (float(i) / nx - 0.5) * 0.075
			var z := (float(j) / nz - 0.5) * 0.045
			var crumple := rng.randf_range(0.0, 0.012) * (1.0 - absf(float(i) / nx - 0.5)) + (0.006 if (i + j) % 2 == 0 else 0.0)
			# twisted ends (candy wrapper)
			if i == 0 or i == nx:
				z *= 0.35
				crumple += 0.004
			P.append(Vector3(x, crumple, z))
			U.append(Vector2(float(i) / nx, float(j) / nz))
	k.grid("debris_film", P, nz + 1, nx + 1, U, Color.WHITE)
	return _mesh_of(k, "debris_film", mats)

static func _crayon_mesh(mats) -> ArrayMesh:
	var k := Kit.new()
	var pts := PackedVector3Array()
	for i in 10:
		pts.append(Vector3(-0.045 + 0.09 * float(i) / 9.0, 0.0045, 0))
	k.tube("debris", pts, 0.0045, 6, Color.WHITE, 1.0, true, func(i: int, _a: float) -> float:
		return 1.0 if i < 7 else maxf(0.15, 1.0 - float(i - 6) / 3.0 * 0.85), Vector3.UP)
	return _mesh_of(k, "debris", mats)

static func _sock_mesh(mats) -> ArrayMesh:
	var k := Kit.new()
	var pts := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		var a := clampf((t - 0.45) / 0.25, 0.0, 1.0) * PI * 0.5
		pts.append(Vector3(sin(a) * 0.05 + (t if t < 0.45 else 0.45) * 0.2, 0.014, -cos(a) * 0.0 + (maxf(t - 0.45, 0.0)) * 0.16))
	k.tube("fabric", pts, 0.022, 10, Color.WHITE, 1.0, true, func(i: int, ang: float) -> float:
		return 0.75 + 0.25 * absf(sin(ang)) + 0.06 * sin(float(i) * 1.7 + ang * 3.0))
	return _mesh_of(k, "fabric", mats)

static func _cup_mesh(mats) -> ArrayMesh:
	var k := Kit.new()
	var pts := PackedVector3Array()
	for i in 7:
		pts.append(Vector3(0, 0.09 * float(i) / 6.0, 0))
	k.tube("debris", pts, 0.035, 16, Color.WHITE, 1.0, false, func(i: int, _a: float) -> float: return 0.74 + 0.26 * float(i) / 6.0)
	k.disc("debris", Vector3(0, 0.001, 0), Vector3.DOWN, Vector3.RIGHT, 0.026, 16, Color.WHITE)
	# inner wall (open cup)
	var kin := Kit.new()
	kin.tube("debris", pts, 0.034, 16, Color.WHITE, 1.0, false, func(i: int, _a: float) -> float: return 0.74 + 0.26 * float(i) / 6.0)
	var b = kin.bin("debris")
	for i in b.n.size():
		b.n[i] = -b.n[i]
	for t in b.idx.size() / 3:
		var tmp: int = b.idx[t * 3 + 1]
		b.idx[t * 3 + 1] = b.idx[t * 3 + 2]
		b.idx[t * 3 + 2] = tmp
	var kb = k.bin("debris")
	var base: int = kb.v.size()
	kb.v.append_array(b.v)
	kb.n.append_array(b.n)
	kb.uv.append_array(b.uv)
	kb.c.append_array(b.c)
	for ix in b.idx:
		kb.idx.append(ix + base)
	return _mesh_of(k, "debris", mats)

static func _popcorn_mesh(mats) -> ArrayMesh:
	var k := Kit.new()
	k.sphere("debris", Vector3(0, 0.008, 0), 0.009, 7, 5, Color.WHITE, Vector3(1.2, 0.9, 1.0))
	k.sphere("debris", Vector3(0.006, 0.011, 0.003), 0.006, 6, 4, Color.WHITE)
	return _mesh_of(k, "debris", mats)

static func _paper_mesh(mats) -> ArrayMesh:
	var k := Kit.new()
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	for j in 4:
		for i in 4:
			var x := (float(i) / 3.0 - 0.5) * 0.11
			var z := (float(j) / 3.0 - 0.5) * 0.09
			P.append(Vector3(x, 0.002 + 0.012 * pow(absf(x) / 0.055, 2.0) + 0.004 * float((i * 7 + j * 3) % 3), z))
			U.append(Vector2(float(i) / 3.0, float(j) / 3.0))
	k.grid("debris_paper", P, 4, 4, U, Color.WHITE)
	return _mesh_of(k, "debris_paper", mats)

static func _toycube_mesh(mats) -> ArrayMesh:
	var k := Kit.new()
	k.rbox("debris", Vector3(-0.024, 0.0, -0.024), Vector3(0.024, 0.048, 0.024), 0.008, 2, Color.WHITE)
	return _mesh_of(k, "debris", mats)

# ====================================================================== scatter

static func _in_frame(x: float, z: float) -> bool:
	for d in GL.DECKS:
		if x > float(d[0]) - 0.15 and x < float(d[1]) + 0.15 and z > float(d[2]) - 0.15 and z < float(d[3]) + 0.15:
			return true
	return false

static func _blocked(x: float, z: float) -> bool:
	var P: Dictionary = GL.PIT
	if x > float(P.x0) - 0.05 and x < float(P.x1) + 0.35 and z > float(P.z0) - 0.05 and z < float(P.z1) + 0.05:
		return true
	if _in_frame(x, z):
		return true
	var S: Dictionary = GL.STEPS
	if x > float(S.x_top) - 2.0 and x < float(S.x_top) + 0.1 and z > float(S.z0) - 0.1 and z < float(S.z1) + 0.1:
		return true
	# party table tops / spiral pole / columns
	for p in GL.HALL_COLUMNS:
		if Vector2(x, z).distance_to(p) < 0.35:
			return true
	if Vector2(x, z).distance_to(Vector2(float(GL.SPIRAL.xc), float(GL.SPIRAL.zc))) < 0.3:
		return true
	return false

## A floor point of the hall for debris: drifted along the walls (55 %), along the frame outline (20 %), around the
## party (15 %) or anywhere (10 %).
static func _hall_point(rng: RandomNumberGenerator) -> Vector3:
	var H: Dictionary = GL.HALLB
	for attempt in 30:
		var r := rng.randf()
		var x := 0.0
		var z := 0.0
		if r < 0.55:
			var side := rng.randi() % 3
			var d := pow(rng.randf(), 2.0) * 0.9 + 0.05
			match side:
				0:
					x = rng.randf_range(float(H.x0), -17.6)
					z = float(H.z0) + d
				1:
					x = rng.randf_range(float(H.x0), -17.6)
					z = float(H.z1) - d
				_:
					x = float(H.x0) + d
					z = rng.randf_range(float(H.z0), float(H.z1))
		elif r < 0.75:
			var segs := [[Vector2(-23.8, 2.6), Vector2(-35.0, 2.6)], [Vector2(-35.0, 2.6), Vector2(-35.0, -5.4)], [Vector2(-31.0, -1.8), Vector2(-23.8, -1.8)],
				[Vector2(-23.8, -1.8), Vector2(-23.8, 2.6)], [Vector2(-35.0, -5.4), Vector2(-31.0, -5.4)]]
			var sg: Array = segs[rng.randi() % segs.size()]
			var t := rng.randf()
			var p: Vector2 = (sg[0] as Vector2).lerp(sg[1], t)
			var dir: Vector2 = ((sg[1] as Vector2) - (sg[0] as Vector2)).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var off := rng.randf_range(0.25, 0.9)
			var q := p + nrm * off
			if _in_frame(q.x, q.y):
				q = p - nrm * off
			x = q.x
			z = q.y
		elif r < 0.9:
			var Pa: Dictionary = GL.PARTY
			x = rng.randf_range(float(Pa.x0), float(Pa.x1))
			z = rng.randf_range(float(Pa.z0), float(Pa.z1))
		else:
			x = rng.randf_range(float(H.x0) + 0.3, -21.0)
			z = rng.randf_range(float(H.z0) + 0.3, float(H.z1) - 0.3)
		if _blocked(x, z):
			continue
		var gy := GL.ground_height_at(x, z)
		if is_nan(gy) or absf(gy - GL.HALL) > 0.01:
			continue
		return Vector3(x, gy, z)
	return Vector3(-38.4, GL.HALL, -6.4)

static func _vest_point(rng: RandomNumberGenerator) -> Vector3:
	var V: Dictionary = GL.VEST
	for attempt in 20:
		var x := rng.randf_range(float(V.x0) + 0.15, float(V.x1) - 0.15)
		var z := rng.randf_range(float(V.z0) + 0.5, float(V.z1) - 0.7)
		if z > 4.2 and x > -15.7 and x < -12.0:
			continue                # counter
		if Vector2(x, z).distance_to(Vector2(-14.1, 0.55)) < 0.3 or Vector2(x, z).distance_to(Vector2(-14.1, 3.65)) < 0.3:
			continue
		return Vector3(x, GL.UP, z)
	return Vector3(-12.0, GL.UP, 0.0)

func _debris(c) -> void:
	var mats = c.mats
	var kinds := [
		["wrapper", _wrapper_mesh(mats), 100, WRAP_COLS, 0.0, 0.15],
		["crayon", _crayon_mesh(mats), 70, CRAYON_COLS, 0.0, 0.12],
		["sock", _sock_mesh(mats), 14, SOCK_COLS, 0.0, 0.1],
		["cup", _cup_mesh(mats), 26, CUP_COLS, 0.65, 0.12],
		["popcorn", _popcorn_mesh(mats), 140, [Color(0.95, 0.88, 0.65), Color(0.92, 0.82, 0.55)], 0.0, 0.05],
		["paper", _paper_mesh(mats), 50, PAPER_COLS, 0.0, 0.15],
		["toycube", _toycube_mesh(mats), 50, [Color(0.62, 0.08, 0.05), Color(0.08, 0.22, 0.56), Color(0.82, 0.6, 0.08), Color(0.08, 0.42, 0.15)], 0.0, 0.1],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	var total := 0
	for kd in kinds:
		var name: String = kd[0]
		var n: int = kd[2]
		var palette: Array = kd[3]
		var lying_p: float = kd[4]
		for room in ["h", "v"]:
			var cnt := n if room == "h" else maxi(2, n / 9)
			if name == "popcorn" and room == "v":
				cnt = 12
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = kd[1]
			mm.instance_count = cnt
			var prev := Vector3.ZERO
			for i in cnt:
				var p := _hall_point(rng) if room == "h" else _vest_point(rng)
				# popcorn comes in small spills
				if name == "popcorn" and i % 6 != 0 and i > 0:
					p = Vector3(prev.x + rng.randf_range(-0.12, 0.12), prev.y, prev.z + rng.randf_range(-0.12, 0.12))
				else:
					prev = p
				var b := Basis(Vector3.UP, rng.randf() * TAU)
				if name == "cup" and rng.randf() < lying_p:
					b = b * Basis(Vector3.RIGHT, PI * 0.5)
					p.y += 0.03
				elif name != "cup":
					b = b * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)) * Basis(Vector3.FORWARD, rng.randf_range(-0.12, 0.12))
				var s := 1.0 + rng.randf_range(-float(kd[5]), float(kd[5]))
				mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(s, s, s)), p))
				var col: Color = palette[rng.randi() % palette.size()]
				mm.set_instance_color(i, col.darkened(rng.randf() * 0.25))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Debris_%s_%s" % [name, room]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mmi.visibility_range_end = 16.0 if name != "cup" and name != "sock" else 22.0
			mmi.visibility_range_end_margin = 2.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			c.region("dress_" + room).add_child(mmi)
			total += cnt
	counts["debris"] = total

# ====================================================================== decals

func _decal(c, room: String, tex_name: String, pos: Vector3, size: Vector3, basis := Basis.IDENTITY, modulate := Color.WHITE) -> void:
	var t: Texture2D = c.mats.tex(tex_name)
	if t == null:
		return
	var d := Decal.new()
	d.name = "Decal_%s_%d" % [tex_name.get_basename(), _decals]
	d.texture_albedo = t
	d.size = size
	d.modulate = modulate
	d.albedo_mix = 1.0
	d.upper_fade = 0.25
	d.lower_fade = 0.25
	d.normal_fade = 0.45
	d.cull_mask = VIS_HALL if room == "h" else VIS_FRONT
	d.distance_fade_enabled = true
	d.distance_fade_begin = 15.0
	d.distance_fade_length = 3.0
	d.transform = Transform3D(basis, pos)
	c.region("dress_" + room).add_child(d)
	_decals += 1

func _decals_all(c) -> void:
	var F := GL.HALL
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var yaw := func() -> Basis: return Basis(Vector3.UP, rng.randf() * TAU)
	# dusty footprints along the walked paths (hall)
	for fp in [[Vector3(-21.6, F, 1.2), -2.8], [Vector3(-22.1, F, -0.2), -2.9], [Vector3(-22.6, F, 3.6), 2.6], [Vector3(-23.6, F, 5.6), 2.8],
			[Vector3(-21.3, F, 4.6), 0.1], [Vector3(-26.0, F, 3.3), 1.6], [Vector3(-30.5, F, 3.2), 1.5], [Vector3(-20.6, F, -2.6), 3.3]]:
		_decal(c, "h", "decal_footprints.png", fp[0], Vector3(0.75, 0.3, 0.75), Basis(Vector3.UP, float(fp[1])))
	# rubber scuffs: frame entrance, pit gate, slide run-out, steps, party
	for sp in [Vector3(-22.6, F, -1.0), Vector3(-24.2, F, 6.6), Vector3(-20.6, F, -4.2), Vector3(-21.5, F, 2.4), Vector3(-21.8, F, 8.2),
			Vector3(-31.3, F, 6.2), Vector3(-34.2, F, 3.3)]:
		_decal(c, "h", "decal_scuffs.png", sp, Vector3(1.2, 0.3, 1.2), yaw.call())
	# dried juice spills
	for sp in [Vector3(-21.4, F, 7.6), Vector3(-20.2, F, 9.3), Vector3(-35.2, F, 8.9)]:
		_decal(c, "h", "decal_spill.png", sp, Vector3(0.7, 0.3, 0.7) * rng.randf_range(0.8, 1.3), yaw.call())
	# grime in the corners / along the walls
	for gp in [Vector3(-38.4, F, -6.4), Vector3(-38.4, F, 10.4), Vector3(-18.0, F, 10.4), Vector3(-27.0, F, -6.5), Vector3(-38.4, F, -2.0),
			Vector3(-33.0, F, 10.5)]:
		_decal(c, "h", "decal_grime.png", gp, Vector3(1.8, 0.4, 1.8) * rng.randf_range(0.8, 1.2), yaw.call())
	# crayon on the toddler mats and on the walls (west wall by the drawings, south wall by the party)
	for cp in [Vector3(-37.0, F, 5.8), Vector3(-36.6, F, 8.2)]:
		_decal(c, "h", "decal_crayon.png", cp, Vector3(0.6, 0.3, 0.6), yaw.call())
	var x0: float = GL.HALLB.x0
	var z1: float = GL.HALLB.z1
	_decal(c, "h", "decal_crayon.png", Vector3(x0, F + 0.7, 6.1), Vector3(0.6, 0.2, 0.5), Basis(Vector3.BACK, -PI * 0.5))
	_decal(c, "h", "decal_crayon.png", Vector3(-22.6, F + 0.55, z1), Vector3(0.7, 0.2, 0.5), Basis(Vector3.RIGHT, -PI * 0.5))
	# kick scuffs low on the walls
	_decal(c, "h", "decal_scuffs.png", Vector3(-25.0, F + 0.3, z1), Vector3(1.4, 0.2, 0.5), Basis(Vector3.RIGHT, -PI * 0.5))
	_decal(c, "h", "decal_scuffs.png", Vector3(x0, F + 0.3, -4.0), Vector3(1.4, 0.2, 0.5), Basis(Vector3.BACK, -PI * 0.5))
	# vestibule + corridor (front layer)
	var U := GL.UP
	_decal(c, "v", "decal_footprints.png", Vector3(-12.6, U, 2.0), Vector3(0.75, 0.3, 0.75), Basis(Vector3.UP, PI * 0.5))
	_decal(c, "v", "decal_footprints.png", Vector3(-15.8, U, 2.2), Vector3(0.75, 0.3, 0.75), Basis(Vector3.UP, PI * 0.5))
	_decal(c, "v", "decal_scuffs.png", Vector3(-14.6, U, 1.4), Vector3(1.1, 0.3, 1.1), yaw.call())
	_decal(c, "v", "decal_scuffs.png", Vector3(-16.6, U, 2.0), Vector3(1.0, 0.3, 1.0), yaw.call())
	_decal(c, "v", "decal_grime.png", Vector3(-16.7, U, -0.5), Vector3(1.4, 0.4, 1.4), yaw.call())
	_decal(c, "v", "decal_spill.png", Vector3(-13.4, U, 3.9), Vector3(0.55, 0.3, 0.55), yaw.call())
	var ch: float = GL.VEST.ceil
	var up_side := Basis(Vector3.RIGHT, PI)
	for wp in [Vector3(-13.5, ch, 1.1), Vector3(-15.9, ch, 3.3), Vector3(-12.3, ch, 4.3)]:
		_decal(c, "v", "decal_water.png", wp, Vector3(0.9, 0.3, 0.9) * rng.randf_range(0.7, 1.2), up_side * Basis(Vector3.UP, rng.randf() * TAU))
	var cc: float = GL.CORR.ceil
	_decal(c, "v", "decal_water.png", Vector3(-8.4, cc, 2.3), Vector3(1.1, 0.3, 1.1), up_side)
	_decal(c, "v", "decal_grime.png", Vector3(-9.8, U, 1.6), Vector3(1.2, 0.4, 1.0), yaw.call())
	_decal(c, "v", "decal_grime.png", Vector3(-5.0, U, 2.6), Vector3(1.4, 0.4, 0.9), yaw.call())
	_decal(c, "v", "decal_scuffs.png", Vector3(-7.0, U, 2.1), Vector3(1.2, 0.3, 1.0), yaw.call())

# ====================================================================== dust motes

func _motes(c) -> void:
	var picks: Array = []
	for L in GL.HALL_LIGHTS:
		if String(L[2]) in ["on", "shadow"] and picks.size() < 4 and (Vector2(float(L[0]), float(L[1])) in [Vector2(-25.4, -4.6), Vector2(-25.4, 1.4), Vector2(-19.8, 1.4), Vector2(-25.4, 7.4)]):
			picks.append(Vector3(float(L[0]), GL.HALL, float(L[1])))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.005, 0.005)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.92, 0.9, 0.84, 0.7)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.shadow_to_opacity = false
	quad.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.7, 1.6, 1.7)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.025
	pm.gravity = Vector3(0, -0.003, 0)
	pm.damping_min = 0.0
	pm.damping_max = 0.01
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed = Vector3(0.02, 0.01, 0.02)
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	for p in picks:
		var e := GPUParticles3D.new()
		e.name = "DustMotes"
		e.amount = 140
		e.lifetime = 14.0
		e.preprocess = 10.0
		e.explosiveness = 0.0
		e.randomness = 0.6
		e.process_material = pm
		e.draw_pass_1 = quad
		e.position = (p as Vector3) + Vector3(0, 2.4, 0)
		e.visibility_aabb = AABB(Vector3(-2.2, -2.2, -2.2), Vector3(4.4, 4.4, 4.4))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		e.visibility_range_end = 14.0
		e.visibility_range_end_margin = 2.0
		e.layers = VIS_HALL
		e.emitting = false
		e.visible = false
		c.region("dress_h").add_child(e)
		motes.append(e)

# ====================================================================== lifted mat corners

func _lifted_corners(c) -> void:
	var k = c.kit("dress_h")
	var kv = c.kit("dress_v")
	var tile := 0.6
	# [x, z near the wanted tile corner, sx, sz (into the lifted tile), lift metres]
	var hall := [[-24.0, 8.4, -1, 1, 0.007], [-27.6, 9.6, 1, -1, 0.005], [-33.6, -6.0, 1, 1, 0.008], [-37.2, -4.8, 1, -1, 0.004],
		[-19.2, 5.4, -1, -1, 0.006], [-30.0, 9.6, -1, -1, 0.006], [-36.0, -1.2, 1, 1, 0.005], [-21.0, -6.0, -1, 1, 0.007],
		[-28.8, -6.0, -1, 1, 0.004], [-34.8, 1.2 + 9.0, 1, -1, 0.006]]
	for e in hall:
		var cx := roundf(float(e[0]) / tile) * tile
		var cz := roundf(float(e[1]) / tile) * tile
		if _blocked(cx + float(e[2]) * 0.1, cz + float(e[3]) * 0.1):
			continue
		_corner(k, "mats_hall", Vector3(cx, GL.HALL, cz), float(e[2]), float(e[3]), float(e[4]))
	# vestibule mats (offset 0.37, 0.12 tile units)
	for e in [[-15.0, 0.4, 1, 1, 0.006], [-12.4, 3.6, -1, -1, 0.005]]:
		var cx := (roundf(float(e[0]) / tile + 0.37) - 0.37) * tile
		var cz := (roundf(float(e[1]) / tile + 0.12) - 0.12) * tile
		_corner(kv, "mats_vest", Vector3(cx, GL.UP, cz), float(e[2]), float(e[3]), float(e[4]))

## A tile corner curling up (hmax metres at the tip, flat 22 cm in along the diagonal) + the dark gap under it.
static func _corner(k, mat: String, corner: Vector3, sx: float, sz: float, hmax: float) -> void:
	var L := 0.22
	var n := 8
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	var lift := func(a: float, b: float) -> float:
		var t := maxf(0.0, 1.0 - (a + b) / L)
		return hmax * t * t
	for j in n + 1:
		for i in n + 1:
			var a := L * float(i) / n
			var b := L * float(j) / n
			P.append(corner + Vector3(sx * a, 0.0015 + lift.call(a, b), sz * b))
			U.append(Vector2(a, b))
	k.grid(mat, P, n + 1, n + 1, U, Color.WHITE)
	# make the patch face up (the grid's winding follows its parametrisation)
	var bn = k.bin(mat)
	var s: int = bn.v.size() - P.size()
	if (bn.n[s + n + 2] as Vector3).y < 0.0:
		for i in range(s, bn.v.size()):
			bn.n[i] = -bn.n[i]
		var ti: int = bn.idx.size() - n * n * 6
		while ti < bn.idx.size():
			var tmp: int = bn.idx[ti + 1]
			bn.idx[ti + 1] = bn.idx[ti + 2]
			bn.idx[ti + 2] = tmp
			ti += 3
	# dark gap under the two lifted edges
	for edge in 2:
		for i in n:
			var a0 := L * float(i) / n
			var a1 := L * float(i + 1) / n
			var h0: float = lift.call(a0, 0.0)
			var h1: float = lift.call(a1, 0.0)
			if h0 < 0.0005 and h1 < 0.0005:
				continue
			var p0: Vector3
			var p1: Vector3
			var nrm: Vector3
			if edge == 0:
				p0 = corner + Vector3(sx * a0, 0.0, 0.0)
				p1 = corner + Vector3(sx * a1, 0.0, 0.0)
				nrm = Vector3(0, 0, -sz)
			else:
				p0 = corner + Vector3(0.0, 0.0, sz * a0)
				p1 = corner + Vector3(0.0, 0.0, sz * a1)
				nrm = Vector3(-sx, 0, 0)
			k.quad("dark", p0, p1, p1 + Vector3(0, 0.0015 + h1, 0), p0 + Vector3(0, 0.0015 + h0, 0), nrm, Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
