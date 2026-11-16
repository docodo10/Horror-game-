## Side rooms of the garderie, behind doors in the corridor and vestibule walls (garderie_layout.gd DORT / BUR / WC):
##   le dortoir   (north of the corridor)  nap room: little beds, a crib and its mobile, a toy shelf, a music box, a
##                                         battery night-light that throws stars on the ceiling
##   le bureau    (south of the corridor)  the gardienne's office: desk, phone with a cut cord, filing cabinets,
##                                         corkboard, her notebook, a coat on its stand in the corner
##   les toilettes (south of the vestibule) children's washroom: tiled, low sinks, three stalls, a tube that flickers
## Geometry, colliders, occluders and lights only; what moves or reacts (music box, mobile, phone, stall door, notes)
## is garderie_rooms_fx.gd, which reads the positions left in c.room_fx.
## Each room has its own render layer (garderie_ctx.gd ROOM_LAYERS): its light is a shadowed omni masked to its room
## + the corridor / vestibule layer, so it spills through the doorway and nowhere else, on every preset.
extends RefCounted

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")
const M := preload("res://scripts/garderie/garderie_mats.gd")

const L_DORT := 4096
const L_BUR := 8192
const L_WC := 16384
const WHITE_WOOD := Color(0.84, 0.82, 0.76)
const TEAL := Color(0.15, 0.42, 0.45)
const STEEL := Color(0.6, 0.6, 0.62)
const BLANKETS := [Color(0.62, 0.2, 0.16), Color(0.2, 0.32, 0.55), Color(0.72, 0.6, 0.22), Color(0.26, 0.45, 0.3), Color(0.5, 0.36, 0.52)]
const TOYS := [Color(0.75, 0.12, 0.1), Color(0.1, 0.25, 0.6), Color(0.85, 0.65, 0.1), Color(0.1, 0.45, 0.2)]

static func build(c) -> void:
	_dortoir(c)
	_bureau(c)
	_toilettes(c)
	# the corridor's bare bulb is shadowed: let it light what it sees of the two rooms through their doors
	for l in c.lights:
		if l.kind == "bulb" and (l.pos as Vector3).distance_to(GL.BULB) < 0.6:
			(l.light as Light3D).light_cull_mask |= L_DORT | L_BUR

# ====================================================================== helpers

static func _xf(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)

## Floor, ceiling, the three walls of its own, baseboards, occluders. The fourth wall is the corridor / vestibule wall
## (on the +z side when shared_south, else on the -z side); `liner` covers its room face with the room's wall material.
static func _shell(c, R: Dictionary, reg: String, wall_mat: String, floor_mat: String, ceil_mat: String, shared_south: bool, liner: bool, baseboard: bool) -> void:
	var k = c.kit(reg)
	var cl = c.col(reg)
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	var top := ch + 0.15
	k.box(floor_mat, Vector3(x0, -0.2, z0), Vector3(x1, 0.0, z1), Color.WHITE, 1.0, Kit.FACE_PY)
	cl.box(Vector3(x0 - 0.2, -0.3, z0 - 0.2), Vector3(x1 + 0.2, 0.0, z1 + 0.2))
	k.box(ceil_mat, Vector3(x0, ch, z0), Vector3(x1, top, z1), Color.WHITE, 1.0, Kit.FACE_NY | Kit.FACE_PY)
	cl.box(Vector3(x0, ch, z0), Vector3(x1, top, z1))
	var za := (z0 - 0.2) if shared_south else (z0 - 0.1)
	var zb := (z1 + 0.1) if shared_south else (z1 + 0.2)
	Shell.wall(c, reg, wall_mat, Vector2(x0 - 0.1, za), Vector2(x0 - 0.1, zb), 0.2, 0.0, top)
	Shell.wall(c, reg, wall_mat, Vector2(x1 + 0.1, za), Vector2(x1 + 0.1, zb), 0.2, 0.0, top)
	var zf := (z0 - 0.1) if shared_south else (z1 + 0.1)
	Shell.wall(c, reg, wall_mat, Vector2(x0 - 0.2, zf), Vector2(x1 + 0.2, zf), 0.2, 0.0, top)
	var dx0: float = R.door_x0
	var dx1: float = R.door_x1
	var dh: float = R.door_h
	if liner:
		var zl := (z1 - 0.012) if shared_south else (z0 + 0.012)
		k.wall(wall_mat, Vector2(x0, zl), Vector2(x1, zl), 0.024, 0.0, ch, [[dx0 - x0, dx1 - x0, 0.0, dh]])
	if baseboard:
		var bh := 0.09
		var bt := 0.012
		k.box("paintwood", Vector3(x0, 0.0, z0), Vector3(x0 + bt, bh, z1), WHITE_WOOD)
		k.box("paintwood", Vector3(x1 - bt, 0.0, z0), Vector3(x1, bh, z1), WHITE_WOOD)
		var zo := z0 if shared_south else (z1 - bt)
		k.box("paintwood", Vector3(x0, 0.0, zo), Vector3(x1, bh, zo + bt), WHITE_WOOD)
		var zs := (z1 - bt - 0.024) if shared_south else (z0 + 0.024)
		k.box("paintwood", Vector3(x0, 0.0, zs), Vector3(dx0 - 0.07, bh, zs + bt), WHITE_WOOD)
		k.box("paintwood", Vector3(dx1 + 0.07, 0.0, zs), Vector3(x1, bh, zs + bt), WHITE_WOOD)
	c.occluders.append(AABB(Vector3(x0 - 0.18, 0.05, z0), Vector3(0.16, ch - 0.1, z1 - z0)))
	c.occluders.append(AABB(Vector3(x1 + 0.02, 0.05, z0), Vector3(0.16, ch - 0.1, z1 - z0)))
	c.occluders.append(AABB(Vector3(x0, 0.05, (z0 - 0.18) if shared_south else (z1 + 0.02)), Vector3(x1 - x0, ch - 0.1, 0.16)))

## Casing on both faces of the wall (centre z = zc, thickness t) around R's opening, and a leaf standing open by `ang`
## into the room (side = -1: the room lies toward -z, +1: toward +z), hinged on the x1 or the x0 jamb.
static func _door(c, R: Dictionary, zc: float, t: float, side: float, ang: float, col: Color, hinge_x1: bool) -> void:
	var k = c.kit("room_doors")
	var cl = c.col("room_doors")
	var x0: float = R.door_x0
	var x1: float = R.door_x1
	var h: float = R.door_h
	var cw := 0.07
	var za := zc - t * 0.5 - 0.035
	var zb := zc + t * 0.5 + 0.035
	k.box("paintwood", Vector3(x0 - cw, 0.0, za), Vector3(x0 + 0.02, h, zb), col)
	k.box("paintwood", Vector3(x1 - 0.02, 0.0, za), Vector3(x1 + cw, h, zb), col)
	k.box("paintwood", Vector3(x0 - cw, h - 0.02, za), Vector3(x1 + cw, h + cw, zb), col)
	k.box("metal", Vector3(x0 + 0.02, 0.0, zc - t * 0.5), Vector3(x1 - 0.02, 0.006, zc + t * 0.5), Color(0.55, 0.52, 0.45))      # threshold strip
	var w := x1 - x0 - 0.05
	var hx := (x1 - 0.025) if hinge_x1 else (x0 + 0.025)
	var cx := -1.0 if hinge_x1 else 1.0
	var d := Vector3(cos(ang) * cx, 0.0, sin(ang) * side)
	var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)), Vector3(hx, 0.0, zc + side * (t * 0.5 + 0.02)))
	k.box("paintwood", Vector3(0.0, 0.012, -0.02), Vector3(w, h - 0.03, 0.02), col, 1.0, Kit.ALL, xf)
	for pz in [-0.024, 0.02]:
		k.box("paintwood", Vector3(0.1, 0.25, pz), Vector3(w - 0.1, 0.9, pz + 0.004), col.darkened(0.08), 1.0, Kit.ALL, xf)
		k.box("paintwood", Vector3(0.1, 1.05, pz), Vector3(w - 0.1, h - 0.2, pz + 0.004), col.darkened(0.08), 1.0, Kit.ALL, xf)
	for kz in [-0.055, 0.055]:
		k.sphere("metal", xf * Vector3(w - 0.07, 0.98, kz), 0.028, 10, 6, Color(0.7, 0.6, 0.35))
	k.tube("metal", PackedVector3Array([xf * Vector3(w - 0.07, 0.98, -0.055), xf * Vector3(w - 0.07, 0.98, 0.055)]), 0.009, 6, Color(0.7, 0.6, 0.35))
	cl.box(Vector3(0.0, 0.0, -0.02), Vector3(w, h - 0.03, 0.02), xf)

## Shadowed omni of a room (follows the house power like every fixture), masked to its room + the front layer.
static func _room_light(c, reg: String, pos: Vector3, state: String, layer: int, energy: float, rng: float, col: Color, emit: Material) -> Light3D:
	var l := Shell.add_light(c, c.region(reg), pos, state, "bulb", emit) as OmniLight3D
	l.omni_range = rng
	l.light_energy = energy
	l.light_color = col
	l.light_cull_mask = 1 | layer | Shell.VIS_FRONT
	l.name = "%s_light" % reg
	c.lights[c.lights.size() - 1]["base"] = energy
	return l

## Small unshadowed glow that follows the house power (desk lamp, plug-in night-light).
static func _glow(c, reg: String, pos: Vector3, layer: int, energy: float, rng: float, col: Color, emit: Material) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.name = "%s_glow" % reg
	o.position = pos
	o.omni_range = rng
	o.omni_attenuation = 1.4
	o.light_energy = energy
	o.light_color = col
	o.light_specular = 0.3
	o.shadow_enabled = false
	o.light_cull_mask = 1 | layer
	c.region(reg).add_child(o)
	c.lights.append({"light": o, "state": "on", "kind": "spill", "emit": emit, "base": energy, "pos": pos})
	return o

## Weak unshadowed omni near the floor standing in for the light the room would bounce back (ceiling, undersides).
static func _fill(c, reg: String, pos: Vector3, layer: int, energy: float, rng: float, col: Color) -> OmniLight3D:
	var o := _glow(c, reg, pos, layer, energy, rng, col, null)
	o.name = "%s_fill" % reg
	o.omni_attenuation = 0.8
	o.light_specular = 0.0
	return o

## Bare bulb in a porcelain socket under the ceiling (same fixture as the corridor's); returns the bulb centre.
static func _bulb_fixture(c, reg: String, at: Vector3, emit: Material, shade: bool) -> Vector3:
	var k = c.kit(reg)
	k.tube("steel_up", PackedVector3Array([Vector3(at.x, at.y - 0.04, at.z), at]), 0.055, 10, Color(0.5, 0.5, 0.5), 1.0, true)
	k.tube("enamel", PackedVector3Array([Vector3(at.x, at.y - 0.1, at.z), Vector3(at.x, at.y - 0.04, at.z)]), 0.03, 12, Color.WHITE, 1.0, true)
	var bc := Vector3(at.x, at.y - 0.15, at.z)
	var bk = Kit.new()
	bk.sphere("glow", bc, 0.032, 12, 8, Color.WHITE, Vector3(1.0, 1.25, 1.0))
	bk.commit(c.region(reg), {"glow": emit}, "%s_bulb" % reg, {"no_shadow": ["glow"]})
	if shade:
		# enamelled tin shade: a shallow cone of four rings above the bulb
		for i in 4:
			var r0 := 0.06 + i * 0.045
			var y0 := at.y - 0.06 - i * 0.022
			var ring := PackedVector3Array()
			for j in 17:
				var a := TAU * float(j) / 16.0
				ring.append(Vector3(at.x + cos(a) * r0, y0, at.z + sin(a) * r0))
			k.tube("enamel", ring, 0.024, 6, Color(0.25, 0.42, 0.3))
	return bc

static func _flat_quad(k, mat: String, ctr: Vector3, yaw: float, w: float, h: float, uv := Rect2(0, 0, 1, 1), col := Color.WHITE) -> void:
	var b := Basis(Vector3.UP, yaw)
	var r := b * Vector3.RIGHT
	var u := b * Vector3.FORWARD
	var bl := ctr - r * w * 0.5 - u * h * 0.5
	var br := ctr + r * w * 0.5 - u * h * 0.5
	var tr := ctr + r * w * 0.5 + u * h * 0.5
	var tl := ctr - r * w * 0.5 + u * h * 0.5
	k.quad(mat, bl, br, tr, tl, Vector3.UP, Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y), uv.position, col)

static func _doc(i: int) -> Rect2:
	return Rect2(0.5 * float(i % 2), 0.5 * float(i / 2), 0.5, 0.5)

## A plush bear from a few ellipsoids. `lying`: face down on the floor.
static func _teddy(k, pos: Vector3, yaw: float, s: float, col: Color, lying := false) -> void:
	var b := Basis(Vector3.UP, yaw)
	if lying:
		b = b * Basis(Vector3.RIGHT, PI * 0.5)
	var xf := Transform3D(b, pos)
	var dark := col.darkened(0.35)
	k.sphere("fabric", xf * (Vector3(0, 0.13, 0) * s), 0.11 * s, 12, 8, col, Vector3(1.0, 1.15, 0.9))
	k.sphere("fabric", xf * (Vector3(0, 0.31, 0.0) * s), 0.085 * s, 12, 8, col)
	for sx in [-1.0, 1.0]:
		k.sphere("fabric", xf * (Vector3(0.065 * sx, 0.385, 0.0) * s), 0.032 * s, 8, 6, col)
		k.sphere("fabric", xf * (Vector3(0.12 * sx, 0.17, 0.03) * s), 0.04 * s, 8, 6, col, Vector3(0.9, 1.5, 0.9))
		k.sphere("fabric", xf * (Vector3(0.07 * sx, 0.03, 0.09) * s), 0.045 * s, 8, 6, col, Vector3(0.9, 0.8, 1.6))
		k.sphere("dark", xf * (Vector3(0.03 * sx, 0.33, 0.075) * s), 0.011 * s, 6, 4, Color.WHITE)
	k.sphere("fabric", xf * (Vector3(0, 0.295, 0.07) * s), 0.035 * s, 8, 6, col.lightened(0.25))
	k.sphere("dark", xf * (Vector3(0, 0.305, 0.103) * s), 0.011 * s, 6, 4, dark)

## Kid-size wooden chair (seat 30 cm high) in the local frame of xf.
static func _chair(k, xf: Transform3D, col: Color, s := 1.0) -> void:
	for lx in [-0.14, 0.14]:
		for lz in [-0.14, 0.14]:
			k.box("paintwood", Vector3(lx - 0.016, 0.0, lz - 0.016) * s, Vector3(lx + 0.016, 0.3 if lz < 0.0 else 0.62, lz + 0.016) * s, col, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(-0.17, 0.3, -0.17) * s, Vector3(0.17, 0.325, 0.17) * s, col, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(-0.15, 0.48, 0.13) * s, Vector3(0.15, 0.6, 0.15) * s, col, 1.0, Kit.ALL, xf)

# ====================================================================== le dortoir

## Little bed: steel legs, painted frame and headboard (toward local -z), mattress, pillow, blanket.
## mess 0: made, 1: thrown back and hanging off the side, 2: a shape left under the blanket.
static func _cot(k, cl, pos: Vector3, yaw: float, frame: Color, blanket: Color, mess: int) -> void:
	var xf := _xf(pos, yaw)
	for sx in [-0.27, 0.27]:
		for sz in [-0.58, 0.58]:
			k.box("metal", Vector3(sx - 0.014, 0.0, sz - 0.014), Vector3(sx + 0.014, 0.21, sz + 0.014), STEEL, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(-0.3, 0.2, -0.62), Vector3(0.3, 0.25, 0.62), frame, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(-0.3, 0.25, -0.62), Vector3(0.3, 0.54, -0.595), frame, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(-0.3, 0.25, 0.6), Vector3(0.3, 0.38, 0.62), frame, 1.0, Kit.ALL, xf)
	k.rbox("fabric", Vector3(-0.285, 0.25, -0.59), Vector3(0.285, 0.33, 0.595), 0.03, 2, Color(0.78, 0.76, 0.68), 1.0, xf)
	k.rbox("fabric", Vector3(-0.18, 0.32, -0.56), Vector3(0.18, 0.385, -0.3), 0.03, 2, Color(0.84, 0.82, 0.76), 1.0, xf)
	match mess:
		0:
			k.rbox("fabric", Vector3(-0.3, 0.31, -0.22), Vector3(0.3, 0.36, 0.605), 0.02, 2, blanket, 1.0, xf)
		1:
			k.rbox("fabric", Vector3(-0.3, 0.31, 0.12), Vector3(0.3, 0.41, 0.605), 0.03, 2, blanket, 1.0, xf)
			k.rbox("fabric", Vector3(0.285, 0.03, 0.18), Vector3(0.325, 0.37, 0.56), 0.015, 2, blanket, 1.0, xf)
		_:
			k.rbox("fabric", Vector3(-0.3, 0.31, -0.32), Vector3(0.3, 0.36, 0.605), 0.02, 2, blanket, 1.0, xf)
			var along_x := absf(sin(yaw)) > 0.7
			k.sphere("fabric", xf * Vector3(0.0, 0.37, 0.1), 0.2, 12, 8, blanket, Vector3(2.1, 0.5, 0.95) if along_x else Vector3(0.95, 0.5, 2.1))
	cl.box(Vector3(-0.3, 0.0, -0.62), Vector3(0.3, 0.42, 0.62), xf)

static func _crib(k, cl, pos: Vector3, yaw: float) -> void:
	var xf := _xf(pos, yaw)
	var w := 0.34
	var l := 0.62
	for sx in [-w, w]:
		for sz in [-l, l]:
			k.box("paintwood", Vector3(sx - 0.022, 0.0, sz - 0.022), Vector3(sx + 0.022, 1.0, sz + 0.022), WHITE_WOOD, 1.0, Kit.ALL, xf)
	for y in [[0.36, 0.4], [0.94, 0.98]]:
		for sx in [-w, w]:
			k.box("paintwood", Vector3(sx - 0.016, y[0], -l), Vector3(sx + 0.016, y[1], l), WHITE_WOOD, 1.0, Kit.ALL, xf)
		for sz in [-l, l]:
			k.box("paintwood", Vector3(-w, y[0], sz - 0.016), Vector3(w, y[1], sz + 0.016), WHITE_WOOD, 1.0, Kit.ALL, xf)
	for i in 15:
		var bz := -l + 0.08 + i * 0.0775
		for sx in [-w, w]:
			k.box("paintwood", Vector3(sx - 0.008, 0.4, bz - 0.008), Vector3(sx + 0.008, 0.94, bz + 0.008), WHITE_WOOD, 1.0, Kit.ALL, xf)
	for i in 7:
		var bx := -w + 0.085 + i * 0.085
		for sz in [-l, l]:
			k.box("paintwood", Vector3(bx - 0.008, 0.4, sz - 0.008), Vector3(bx + 0.008, 0.94, sz + 0.008), WHITE_WOOD, 1.0, Kit.ALL, xf)
	k.rbox("fabric", Vector3(-w + 0.02, 0.4, -l + 0.02), Vector3(w - 0.02, 0.48, l - 0.02), 0.03, 2, Color(0.8, 0.78, 0.7), 1.0, xf)
	k.rbox("fabric", Vector3(-w + 0.04, 0.47, -0.1), Vector3(w - 0.06, 0.53, l - 0.06), 0.025, 2, Color(0.72, 0.6, 0.22), 1.0, xf)
	cl.box(Vector3(-w - 0.02, 0.0, -l - 0.02), Vector3(w + 0.02, 1.0, l + 0.02), xf)

static func _dortoir(c) -> void:
	var R: Dictionary = GL.DORT
	var reg := "room_dort"
	_shell(c, R, reg, "wallpaper", "carpet", "corr_ceil", true, true, true)
	_door(c, R, float(R.z1) + 0.1, 0.2, -1.0, deg_to_rad(100.0), Color(0.5, 0.62, 0.66), true)
	var k = c.kit("room_dort_props")
	var cl = c.col("room_dort_props")
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	# five little beds along the far wall (heads to the wall), two more along the east wall
	var messes := [0, 2, 1, 0, 2]
	for i in 5:
		_cot(k, cl, Vector3(-9.75 + i * 1.0, 0.0, z0 + 0.66), 0.0, WHITE_WOOD, BLANKETS[i % BLANKETS.size()], messes[i])
	_cot(k, cl, Vector3(x1 - 0.34, 0.0, -1.55), PI, WHITE_WOOD, BLANKETS[3], 1)
	_cot(k, cl, Vector3(x1 - 0.34, 0.0, -0.1), PI, WHITE_WOOD, BLANKETS[0], 0)
	# a bear sitting on the middle bed, watching the door; another face down on the carpet
	_teddy(k, Vector3(-7.75, 0.36, z0 + 0.5), 0.0, 1.0, Color(0.45, 0.3, 0.17))
	_teddy(k, Vector3(-6.4, 0.07, -0.9), 2.2, 0.9, Color(0.62, 0.52, 0.4), true)
	# the crib in the west corner, its mobile hanging from the ceiling (garderie_rooms_fx.gd turns it)
	var crib := Vector3(x0 + 0.42, 0.0, -1.0)
	_crib(k, cl, crib, 0.0)
	var mk = c.kit("room_dort_mobile")
	mk.tube("dark", PackedVector3Array([Vector3.ZERO, Vector3(0, -0.55, 0)]), 0.003, 4, Color(0.6, 0.6, 0.6))
	for a in 2:
		var dir := Vector3(1, 0, 0) if a == 0 else Vector3(0, 0, 1)
		mk.tube("paintwood", PackedVector3Array([Vector3(0, -0.55, 0) - dir * 0.24, Vector3(0, -0.55, 0) + dir * 0.24]), 0.006, 6, WHITE_WOOD)
		for sgn in [-1.0, 1.0]:
			var tip: Vector3 = Vector3(0, -0.55, 0) + dir * 0.24 * sgn
			var drop := 0.16 + 0.07 * (a + (1.0 if sgn > 0.0 else 0.0))
			mk.tube("dark", PackedVector3Array([tip, tip - Vector3(0, drop, 0)]), 0.002, 4, Color(0.6, 0.6, 0.6))
			var tc: Color = TOYS[(a * 2 + (1 if sgn > 0.0 else 0)) % TOYS.size()]
			if a == 0:
				mk.sphere("fabric", tip - Vector3(0, drop + 0.04, 0), 0.045, 10, 6, tc, Vector3(1.0, 1.0, 0.35))
			else:
				mk.cbox("fabric", tip - Vector3(0, drop + 0.04, 0), Vector3(0.075, 0.075, 0.02), tc, 1.0, 0.785)
	mk.sphere("fabric", Vector3(0, -0.66, 0), 0.04, 10, 6, Color(0.9, 0.82, 0.3))
	c.room_fx["mobile_pos"] = Vector3(crib.x, ch, crib.z)
	# a rocking chair beside the crib, turned to the beds
	var rc := Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -0.07), Vector3(x0 + 0.6, 0.05, 0.35))
	for lx in [-0.24, 0.24]:
		k.box("panel", Vector3(lx - 0.02, -0.05, -0.4), Vector3(lx + 0.02, -0.01, 0.42), Color.WHITE, 1.0, Kit.ALL, rc)
		k.box("panel", Vector3(lx - 0.02, -0.01, -0.3), Vector3(lx + 0.02, 0.62, -0.26), Color.WHITE, 1.0, Kit.ALL, rc)
		k.box("panel", Vector3(lx - 0.02, -0.01, 0.24), Vector3(lx + 0.02, 0.4, 0.28), Color.WHITE, 1.0, Kit.ALL, rc)
		k.box("panel", Vector3(lx - 0.025, 0.6, -0.3), Vector3(lx + 0.025, 0.63, 0.3), Color.WHITE, 1.0, Kit.ALL, rc)
	k.box("panel", Vector3(-0.24, 0.38, -0.3), Vector3(0.24, 0.41, 0.28), Color.WHITE, 1.0, Kit.ALL, rc)
	var back := rc * Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.4, 0.26))
	for i in 5:
		var sx := -0.2 + i * 0.1
		k.box("panel", Vector3(sx - 0.02, 0.0, -0.012), Vector3(sx + 0.02, 0.72, 0.012), Color.WHITE, 1.0, Kit.ALL, back)
	k.box("panel", Vector3(-0.25, 0.7, -0.018), Vector3(0.25, 0.78, 0.018), Color.WHITE, 1.0, Kit.ALL, back)
	k.rbox("fabric", Vector3(-0.2, 0.4, -0.24), Vector3(0.2, 0.45, 0.2), 0.02, 2, Color(0.35, 0.16, 0.14), 1.0, rc)
	cl.box(Vector3(x0 + 0.2, 0.0, 0.05), Vector3(x0 + 1.05, 1.1, 0.65))
	# toy shelf against the south wall east of the door
	var sx0 := -6.7
	var sx1 := -5.2
	var sz := z1 - 0.036
	k.box("paintwood", Vector3(sx0, 0.0, sz - 0.32), Vector3(sx1, 0.03, sz), WHITE_WOOD)
	k.box("paintwood", Vector3(sx0, 0.4, sz - 0.32), Vector3(sx1, 0.43, sz), WHITE_WOOD)
	k.box("paintwood", Vector3(sx0, 0.8, sz - 0.32), Vector3(sx1, 0.83, sz), WHITE_WOOD)
	k.box("paintwood", Vector3(sx0, 0.0, sz - 0.012), Vector3(sx1, 0.83, sz), WHITE_WOOD)
	for i in 5:
		var px := sx0 + i * (sx1 - sx0 - 0.02) / 4.0
		k.box("paintwood", Vector3(px, 0.03, sz - 0.32), Vector3(px + 0.02, 0.8, sz), WHITE_WOOD)
	cl.box(Vector3(sx0, 0.0, sz - 0.32), Vector3(sx1, 0.83, sz))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
	for row in 2:
		for cell in 4:
			var cx := sx0 + 0.19 + cell * 0.37
			var cy := 0.03 + row * 0.4
			match (row * 4 + cell) % 4:
				0:
					for b in 3:
						var s := 0.07 + rng.randf() * 0.02
						k.cbox("plastic", Vector3(cx - 0.1 + b * 0.1, cy + s * 0.5, sz - 0.16 + rng.randf_range(-0.05, 0.05)), Vector3(s, s, s), TOYS[rng.randi() % 4], 1.0, rng.randf() * 0.6)
				1:
					k.sphere("plastic", Vector3(cx, cy + 0.09, sz - 0.17), 0.09, 12, 8, TOYS[rng.randi() % 4])
				2:
					for b in 5:
						var bw := 0.018 + rng.randf() * 0.02
						k.box("fabric", Vector3(cx - 0.14 + b * 0.055, cy, sz - 0.26), Vector3(cx - 0.14 + b * 0.055 + bw, cy + 0.2 + rng.randf() * 0.08, sz - 0.05), TOYS[rng.randi() % 4].darkened(0.2))
				_:
					for b in 3:
						k.rbox("fabric", Vector3(cx - 0.15, cy + b * 0.055, sz - 0.28), Vector3(cx + 0.15, cy + 0.05 + b * 0.055, sz - 0.04), 0.015, 2, BLANKETS[(b + cell) % BLANKETS.size()])
	# the night-light, left on a little stool between the beds: a dome that throws stars on the ceiling
	var st := Vector3(-6.55, 0.0, -1.45)
	k.tube("paintwood", PackedVector3Array([st + Vector3(0, 0.27, 0), st + Vector3(0, 0.3, 0)]), 0.16, 16, Color(0.5, 0.62, 0.66), 1.0, true)
	for a in 3:
		var ang := TAU * float(a) / 3.0 + 0.3
		k.tube("paintwood", PackedVector3Array([st + Vector3(cos(ang) * 0.13, 0.0, sin(ang) * 0.13), st + Vector3(cos(ang) * 0.09, 0.28, sin(ang) * 0.09)]), 0.014, 6, Color(0.5, 0.62, 0.66))
	cl.box(st + Vector3(-0.16, 0.0, -0.16), st + Vector3(0.16, 0.3, 0.16))
	var proj := st + Vector3(0, 0.3, 0)
	k.tube("dark", PackedVector3Array([proj, proj + Vector3(0, 0.035, 0)]), 0.06, 14, Color(0.5, 0.5, 0.55), 1.0, true)
	var pk = Kit.new()
	pk.sphere("glow", proj + Vector3(0, 0.035, 0), 0.05, 14, 8, Color.WHITE, Vector3(1.0, 0.8, 1.0))
	pk.commit(c.region(reg), {"glow": c.mats.mat("star_glow")}, "room_dort_projector", {"no_shadow": ["glow"]})
	c.room_fx["projector_pos"] = proj + Vector3(0, 0.1, 0)
	# the dresser with the music box, against the east wall near the door
	var dz := 0.72
	var dx := x1 - 0.012
	k.box("paintwood", Vector3(dx - 0.44, 0.04, dz - 0.45), Vector3(dx, 0.82, dz + 0.45), WHITE_WOOD)
	k.box("paintwood", Vector3(dx - 0.46, 0.82, dz - 0.47), Vector3(dx, 0.85, dz + 0.47), WHITE_WOOD)
	for i in 3:
		var y0 := 0.08 + i * 0.25
		k.box("paintwood", Vector3(dx - 0.452, y0, dz - 0.42), Vector3(dx - 0.44, y0 + 0.22, dz + 0.42), WHITE_WOOD.darkened(0.05))
		for kz in [-0.22, 0.22]:
			k.sphere("paintwood", Vector3(dx - 0.462, y0 + 0.11, dz + kz), 0.016, 8, 6, Color(0.5, 0.62, 0.66))
	cl.box(Vector3(dx - 0.46, 0.0, dz - 0.47), Vector3(dx, 0.85, dz + 0.47))
	var mb := Vector3(dx - 0.24, 0.85, dz + 0.1)
	k.box("panel", mb + Vector3(-0.07, 0.0, -0.05), mb + Vector3(0.07, 0.06, 0.05), Color.WHITE)
	k.box("panel", Vector3(-0.07, 0.0, -0.004), Vector3(0.07, 0.1, 0.004), Color.WHITE, 1.0, Kit.ALL, Transform3D(Basis(Vector3.RIGHT, -0.35), mb + Vector3(0, 0.06, 0.05)))
	k.box("fabric", mb + Vector3(-0.06, 0.06, -0.04), mb + Vector3(0.06, 0.062, 0.04), Color(0.5, 0.1, 0.12))
	k.tube("enamel", PackedVector3Array([mb + Vector3(0.0, 0.06, 0.0), mb + Vector3(0.0, 0.12, 0.0)]), 0.008, 8, Color(0.9, 0.75, 0.8), 1.0, true)
	k.sphere("enamel", mb + Vector3(0.0, 0.132, 0.0), 0.012, 8, 6, Color(0.9, 0.8, 0.75))
	k.tube("metal", PackedVector3Array([mb + Vector3(-0.07, 0.03, 0.0), mb + Vector3(-0.1, 0.03, 0.0), mb + Vector3(-0.1, 0.055, 0.0)]), 0.004, 6, Color(0.75, 0.65, 0.35))
	c.room_fx["music_box"] = mb + Vector3(0, 0.05, 0)
	# a note folded under the pillow of the second bed
	var note := Vector3(-8.75 + 0.16, 0.39, z0 + 0.3)
	_flat_quad(k, "debris_paper", note, 0.5, 0.11, 0.08, Rect2(0, 0, 1, 1), Color(0.88, 0.85, 0.74))
	c.room_fx["dort_note"] = note
	# on the walls: the nap schedule by the door, drawings above the beds, a plug-in night-light
	Shell.sign_quad(k, "tex_docs_atlas.jpg", Vector3(-8.5, 1.45, z1 - 0.03), Vector3.FORWARD, 0.3, 0.3, _doc(1))
	Shell.sign_quad(k, "tex_drawings2.jpg", Vector3(-8.25, 1.4, z0 + 0.004), Vector3.BACK, 0.4, 0.4, _doc(2))
	Shell.sign_quad(k, "tex_drawings2.jpg", Vector3(-6.3, 1.5, z0 + 0.004), Vector3.BACK, 0.38, 0.38, _doc(0))
	Shell.sign_quad(k, "tex_drawings.jpg", Vector3(x1 - 0.004, 1.45, -2.4), Vector3.LEFT, 0.36, 0.36, _doc(1))
	var nl := Vector3(x0 + 0.03, 0.34, -2.2)
	k.box("plastic", nl + Vector3(-0.018, -0.05, -0.035), nl + Vector3(0.0, 0.05, 0.035), Color(0.9, 0.9, 0.86))
	var nk = Kit.new()
	var nle: StandardMaterial3D = c.mats.emissive_instance("night_glow")
	nk.rbox("glow", nl + Vector3(0.0, -0.03, -0.028), nl + Vector3(0.03, 0.045, 0.028), 0.012, 2, Color.WHITE)
	nk.commit(c.region(reg), {"glow": nle}, "room_dort_nightlight", {"no_shadow": ["glow"]})
	_glow(c, reg, nl + Vector3(0.12, 0.05, 0.0), L_DORT, 0.22, 1.9, Color(1.0, 0.7, 0.38), nle)
	# scattered toys on the carpet
	for t in [[Vector3(-8.9, 0.045, -0.6), 0.09, 0], [Vector3(-8.72, 0.04, -0.72), 0.08, 2], [Vector3(-8.8, 0.13, -0.66), 0.08, 1], [Vector3(-5.9, 0.04, -2.1), 0.08, 3]]:
		var p: Vector3 = t[0]
		var s: float = t[1]
		k.cbox("plastic", p, Vector3(s, s, s), TOYS[int(t[2])], 1.0, p.x * 3.0)
	k.sphere("plastic", Vector3(-7.0, 0.1, 0.5), 0.1, 14, 10, TOYS[2])
	# ceiling bulb with a tin shade over the middle of the room
	var em: StandardMaterial3D = c.mats.emissive_instance("bulb_on")
	var bc := _bulb_fixture(c, reg, Vector3(-7.6, ch, -1.3), em, true)
	var l := _room_light(c, reg, bc - Vector3(0, 0.06, 0), "on", L_DORT, 0.85, 6.5, Color(1.0, 0.78, 0.52), em)
	c.room_fx["dort_light"] = l
	c.room_fx["dort_fill"] = _fill(c, reg, Vector3(-7.6, 0.7, -1.3), L_DORT, 0.11, 5.0, Color(1.0, 0.8, 0.6))
	c.room_fx["dort_probe"] = Shell.probe(c, reg, "ProbeRoomDortoir", Vector3(x0, 0.0, z0), Vector3(x1, ch, z1), Vector3(-7.6, 1.3, -1.3), 0.8)
	# what years of naps and a leaking pipe left: crayon on the wallpaper, a spill, stains coming down from the ceiling
	Shell.decal(c, reg, "decal_crayon.png", Vector3(x1 - 0.01, 0.75, -0.95), Vector3.LEFT, Vector2(0.9, 0.7), L_DORT, Color(1, 1, 1, 0.9))
	Shell.decal(c, reg, "decal_crayon.png", Vector3(-9.2, 0.62, z0 + 0.01), Vector3.BACK, Vector2(0.7, 0.55), L_DORT, Color(1, 1, 1, 0.8))
	Shell.decal(c, reg, "decal_spill.png", Vector3(-6.3, 0.0, -0.4), Vector3.UP, Vector2(1.1, 0.9), L_DORT, Color(0.3, 0.24, 0.2, 0.75), 0.7)
	Shell.decal(c, reg, "decal_spill.png", Vector3(-8.9, 0.0, -2.1), Vector3.UP, Vector2(0.7, 0.6), L_DORT, Color(0.24, 0.22, 0.2, 0.6), 2.1)
	Shell.decal(c, reg, "decal_water.png", Vector3(x0 + 0.01, 1.75, -2.9), Vector3.RIGHT, Vector2(1.5, 1.3), L_DORT, Color(0.5, 0.4, 0.26, 0.75))
	Shell.decal(c, reg, "decal_water.png", Vector3(-5.6, 1.8, z0 + 0.01), Vector3.BACK, Vector2(1.2, 1.2), L_DORT, Color(0.5, 0.4, 0.26, 0.65))
	Shell.decal(c, reg, "decal_grime.png", Vector3(-8.6, 0.0, 0.9), Vector3.UP, Vector2(1.8, 0.8), L_DORT, Color(0.2, 0.18, 0.16, 0.7))
	Shell.decal(c, reg, "decal_scuffs.png", Vector3(-7.6, 0.0, 0.7), Vector3.UP, Vector2(1.0, 1.2), L_DORT, Color(0.25, 0.23, 0.2, 0.6), 0.2)

# ====================================================================== le bureau

static func _filing(k, cl, pos: Vector3, yaw: float, open_i: int) -> void:
	var xf := _xf(pos, yaw)
	var col := Color(0.42, 0.46, 0.4)
	k.box("steel_up", Vector3(-0.23, 0.0, -0.31), Vector3(0.23, 1.32, 0.29), col, 1.0, Kit.ALL, xf)
	for i in 4:
		var y0 := 0.03 + i * 0.32
		var out := 0.34 if i == open_i else 0.0
		k.box("steel_up", Vector3(-0.215, y0, 0.29 + out), Vector3(0.215, y0 + 0.3, 0.3 + out), col.lightened(0.06), 1.0, Kit.ALL, xf)
		k.box("metal", Vector3(-0.07, y0 + 0.2, 0.3 + out), Vector3(0.07, y0 + 0.22, 0.325 + out), STEEL, 1.0, Kit.ALL, xf)
		k.box("debris_paper", Vector3(-0.05, y0 + 0.1, 0.3 + out), Vector3(0.05, y0 + 0.15, 0.302 + out), Color(0.85, 0.82, 0.7), 1.0, Kit.ALL, xf)
		if out > 0.0:
			k.box("steel_up", Vector3(-0.2, y0 + 0.01, 0.0), Vector3(0.2, y0 + 0.24, 0.29 + out), col.darkened(0.25), 1.0, Kit.ALL, xf)
			for f in 9:
				var fz := 0.31 + f * 0.033
				k.box("debris_paper", Vector3(-0.19, y0 + 0.05, fz), Vector3(0.19, y0 + 0.27 + 0.012 * (f % 3), fz + 0.004), [Color(0.78, 0.68, 0.42), Color(0.7, 0.72, 0.6), Color(0.8, 0.74, 0.55)][f % 3], 1.0, Kit.ALL, xf)
	cl.box(Vector3(-0.23, 0.0, -0.31), Vector3(0.23, 1.32, 0.64 if open_i >= 0 else 0.3), xf)

static func _bureau(c) -> void:
	var R: Dictionary = GL.BUR
	var reg := "room_bur"
	_shell(c, R, reg, "corr_wall", "floorboards", "corr_ceil", false, false, true)
	_door(c, R, float(R.z0) - 0.1, 0.2, 1.0, deg_to_rad(105.0), Color(0.3, 0.2, 0.12), false)
	var k = c.kit("room_bur_props")
	var cl = c.col("room_bur_props")
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	# the desk, facing the door: top, two pedestals of drawers, modesty panel
	var dc := Vector3(-6.6, 0.0, 5.55)
	k.box("panel", dc + Vector3(-0.78, 0.72, -0.38), dc + Vector3(0.78, 0.76, 0.38), Color.WHITE)
	k.box("panel", dc + Vector3(-0.74, 0.1, -0.34), dc + Vector3(0.74, 0.72, -0.32), Color.WHITE)
	for sx in [-1.0, 1.0]:
		k.box("panel", dc + Vector3(0.55 * sx - 0.2, 0.06, -0.32), dc + Vector3(0.55 * sx + 0.2, 0.72, 0.34), Color.WHITE)
		for i in 3:
			var y0 := 0.1 + i * 0.205
			k.box("panel", dc + Vector3(0.55 * sx - 0.18, y0, 0.34), dc + Vector3(0.55 * sx + 0.18, y0 + 0.19, 0.352), Color(0.9, 0.9, 0.9))
			k.box("metal", dc + Vector3(0.55 * sx - 0.05, y0 + 0.085, 0.352), dc + Vector3(0.55 * sx + 0.05, y0 + 0.1, 0.37), Color(0.7, 0.6, 0.35))
	cl.box(dc + Vector3(-0.78, 0.0, -0.38), dc + Vector3(0.78, 0.76, 0.38))
	# on the desk: the phone (its cord cut), the notebook, loose papers, a lamp with a green shade
	var ph := dc + Vector3(-0.5, 0.76, -0.08)
	var pxf := _xf(ph, 0.35)
	k.rbox("plastic", Vector3(-0.1, 0.0, -0.11), Vector3(0.1, 0.055, 0.11), 0.015, 2, Color(0.08, 0.08, 0.09), 1.0, pxf)
	k.rbox("plastic", Vector3(-0.115, 0.07, -0.085), Vector3(0.115, 0.1, -0.045), 0.014, 2, Color(0.08, 0.08, 0.09), 1.0, pxf)
	for sx in [-0.09, 0.09]:
		k.rbox("plastic", Vector3(sx - 0.03, 0.05, -0.095), Vector3(sx + 0.03, 0.085, -0.035), 0.012, 2, Color(0.08, 0.08, 0.09), 1.0, pxf)
	k.disc("enamel", pxf * Vector3(0.0, 0.056, 0.035), Vector3.UP, Vector3.RIGHT, 0.055, 16, Color(0.8, 0.78, 0.7))
	k.disc("dark", pxf * Vector3(0.0, 0.057, 0.035), Vector3.UP, Vector3.RIGHT, 0.022, 12, Color.WHITE)
	k.tube("rubber", PackedVector3Array([pxf * Vector3(-0.1, 0.02, 0.0), pxf * Vector3(-0.18, 0.01, 0.02), ph + Vector3(-0.27, 0.0, -0.3), ph + Vector3(-0.29, -0.2, -0.33), ph + Vector3(-0.28, -0.42, -0.31)]), 0.004, 6, Color(0.1, 0.1, 0.1))
	c.room_fx["phone"] = ph + Vector3(0, 0.06, 0)
	var nb := dc + Vector3(0.05, 0.76, 0.05)
	var nxf := _xf(nb, -0.2)
	k.box("fabric", Vector3(-0.08, 0.0, -0.11), Vector3(0.08, 0.016, 0.11), Color(0.12, 0.16, 0.3), 1.0, Kit.ALL, nxf)
	k.box("debris_paper", Vector3(-0.076, 0.002, -0.106), Vector3(0.078, 0.014, 0.106), Color(0.86, 0.83, 0.72), 1.0, Kit.ALL, nxf)
	k.box("debris_paper", Vector3(-0.045, 0.016, -0.05), Vector3(0.045, 0.0165, -0.015), Color(0.9, 0.88, 0.8), 1.0, Kit.ALL, nxf)
	c.room_fx["journal"] = nb + Vector3(0, 0.02, 0)
	_flat_quad(k, "tex_docs_atlas.jpg", dc + Vector3(0.4, 0.762, -0.12), 0.25, 0.21, 0.27, _doc(0))
	_flat_quad(k, "tex_docs_atlas.jpg", dc + Vector3(0.52, 0.763, 0.12), -0.4, 0.21, 0.27, _doc(2))
	_flat_quad(k, "debris_paper", dc + Vector3(-0.15, 0.761, -0.2), 0.9, 0.21, 0.27, Rect2(0, 0, 1, 1), Color(0.86, 0.84, 0.76))
	var lp := dc + Vector3(0.62, 0.76, -0.24)
	k.tube("metal", PackedVector3Array([lp, lp + Vector3(0, 0.015, 0)]), 0.07, 14, Color(0.6, 0.5, 0.3), 1.0, true)
	k.tube("metal", PackedVector3Array([lp, lp + Vector3(0, 0.3, 0), lp + Vector3(-0.08, 0.36, 0.0)]), 0.008, 8, Color(0.6, 0.5, 0.3))
	k.rbox("plastic", lp + Vector3(-0.2, 0.33, -0.06), lp + Vector3(0.02, 0.4, 0.06), 0.025, 3, Color(0.06, 0.3, 0.14))
	var lk = Kit.new()
	var lamp_em: StandardMaterial3D = c.mats.emissive_instance("night_glow")
	lk.box("glow", lp + Vector3(-0.18, 0.322, -0.045), lp + Vector3(0.0, 0.33, 0.045), Color.WHITE)
	lk.commit(c.region(reg), {"glow": lamp_em}, "room_bur_lamp", {"no_shadow": ["glow"]})
	_glow(c, reg, lp + Vector3(-0.1, 0.2, 0.0), L_BUR, 0.55, 2.6, Color(1.0, 0.72, 0.4), lamp_em)
	# the chair, knocked over behind the desk
	_chair(k, Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(-6.3, 0.2, 6.25)), Color(0.3, 0.19, 0.11), 1.45)
	cl.box(Vector3(-6.75, 0.0, 5.98), Vector3(-5.6, 0.45, 6.56))
	# filing cabinets along the west wall (one drawer left open), archive boxes in the corner
	_filing(k, cl, Vector3(x0 + 0.33, 0.0, 3.5), PI * 0.5, -1)
	_filing(k, cl, Vector3(x0 + 0.33, 0.0, 4.0), PI * 0.5, 1)
	_filing(k, cl, Vector3(x0 + 0.33, 0.0, 4.5), PI * 0.5, -1)
	for b in [[Vector3(-4.75, 0.0, 6.2), 0.1, 0.0], [Vector3(-4.72, 0.3, 6.22), -0.2, 0.0], [Vector3(-5.25, 0.0, 6.25), 0.3, 0.0]]:
		var bp: Vector3 = b[0]
		var bxf := _xf(bp, float(b[1]))
		k.box("wood", Vector3(-0.2, 0.0, -0.16), Vector3(0.2, 0.28, 0.16), Color(0.62, 0.47, 0.31), 1.0, Kit.ALL, bxf)
		k.box("wood", Vector3(-0.21, 0.28, -0.17), Vector3(0.21, 0.3, 0.17), Color(0.58, 0.44, 0.29), 1.0, Kit.ALL, bxf)
	cl.box(Vector3(-5.5, 0.0, 6.0), Vector3(x1, 0.6, z1))
	# bookshelf on the east wall: binders, a few books lying flat
	var bs := Vector3(x1 - 0.012, 0.0, 3.85)
	k.box("panel", bs + Vector3(-0.3, 0.0, -0.46), bs + Vector3(0.0, 1.9, -0.44), Color.WHITE)
	k.box("panel", bs + Vector3(-0.3, 0.0, 0.44), bs + Vector3(0.0, 1.9, 0.46), Color.WHITE)
	k.box("panel", bs + Vector3(-0.012, 0.0, -0.44), bs + Vector3(0.0, 1.9, 0.44), Color(0.8, 0.8, 0.8))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var binder := [Color(0.06, 0.06, 0.07), Color(0.1, 0.14, 0.3), Color(0.36, 0.08, 0.08), Color(0.3, 0.3, 0.3), Color(0.12, 0.26, 0.16)]
	for i in 6:
		var sy := 0.06 + i * 0.36
		k.box("panel", bs + Vector3(-0.3, sy - 0.02, -0.44), bs + Vector3(0.0, sy, 0.44), Color.WHITE)
		if i == 5:
			continue
		var z := -0.42
		while z < 0.36:
			var w := rng.randf_range(0.035, 0.075)
			if rng.randf() < 0.14:
				z += rng.randf_range(0.06, 0.16)
				continue
			var bh := rng.randf_range(0.26, 0.32)
			k.box("plastic", bs + Vector3(-0.27, sy, z), bs + Vector3(-0.03, sy + bh, z + w), binder[rng.randi() % binder.size()])
			k.box("debris_paper", bs + Vector3(-0.272, sy + 0.14, z + 0.008), bs + Vector3(-0.27, sy + 0.2, z + w - 0.008), Color(0.86, 0.84, 0.76))
			z += w + 0.004
	cl.box(bs + Vector3(-0.3, 0.0, -0.46), bs + Vector3(0.0, 1.9, 0.46))
	# corkboard on the east wall: attendance sheet, notice, numbers, two drawings
	var cb := Vector3(x1 - 0.004, 1.55, 5.3)
	Shell.board(k, "tex_cork.jpg", cb + Vector3(-0.01, 0, 0), Vector3.LEFT, 1.5, 1.0, 0.02)
	for fr in [[-0.5, 0.5, 0.75, 0.77], [-0.5, 0.5, -0.77, -0.75]]:
		k.box("panel", cb + Vector3(-0.036, fr[0], fr[2]), cb + Vector3(-0.004, fr[1], fr[3]), Color.WHITE)
	k.box("panel", cb + Vector3(-0.036, 0.5, -0.77), cb + Vector3(-0.004, 0.52, 0.77), Color.WHITE)
	k.box("panel", cb + Vector3(-0.036, -0.52, -0.77), cb + Vector3(-0.004, -0.5, 0.77), Color.WHITE)
	var pins := [[Vector3(0, 0.2, -0.5), "tex_docs_atlas.jpg", 0, 0.3], [Vector3(0, -0.16, -0.14), "tex_docs_atlas.jpg", 3, 0.3], [Vector3(0, 0.22, 0.48), "tex_docs_atlas.jpg", 2, 0.3],
		[Vector3(0, 0.18, -0.02), "tex_drawings2.jpg", 1, 0.36], [Vector3(0, -0.2, 0.42), "tex_drawings2.jpg", 3, 0.3]]
	for pn in pins:
		var pp: Vector3 = cb + Vector3(-0.032, 0, 0) + (pn[0] as Vector3)
		var sz2: float = pn[3]
		Shell.sign_quad(k, String(pn[1]), pp, Vector3.LEFT, sz2, sz2, _doc(int(pn[2])))
		k.sphere("plastic", pp + Vector3(-0.004, sz2 * 0.5 - 0.02, 0.0), 0.008, 6, 4, Color(0.7, 0.1, 0.08))
	# her coat and hat on the stand in the dark corner
	var cs := Vector3(x0 + 0.38, 0.0, z1 - 0.4)
	k.tube("panel", PackedVector3Array([cs, cs + Vector3(0, 1.78, 0)]), 0.02, 8, Color.WHITE, 1.0, true)
	for a in 4:
		var ang := a * PI * 0.5 + 0.4
		var dir := Vector3(cos(ang), 0, sin(ang))
		k.tube("panel", PackedVector3Array([cs + Vector3(0, 0.04, 0), cs + dir * 0.24 + Vector3(0, 0.01, 0)]), 0.016, 6, Color.WHITE)
		k.tube("panel", PackedVector3Array([cs + Vector3(0, 1.62, 0), cs + dir * 0.1 + Vector3(0, 1.7, 0)]), 0.008, 6, Color.WHITE)
	var coat := Color(0.07, 0.065, 0.06)
	var cxf := _xf(cs + Vector3(0.07, 0.0, -0.07), -0.75)
	k.rbox("fabric", Vector3(-0.22, 1.36, -0.09), Vector3(0.22, 1.62, 0.09), 0.06, 3, coat, 1.0, cxf)
	k.rbox("fabric", Vector3(-0.19, 0.42, -0.07), Vector3(0.19, 1.42, 0.07), 0.04, 2, coat, 1.0, cxf)
	for sx in [-1.0, 1.0]:
		k.rbox("fabric", Vector3(0.2 * sx - 0.05, 0.62, -0.05), Vector3(0.2 * sx + 0.05, 1.5, 0.05), 0.035, 2, coat, 1.0, cxf)
	k.sphere("fabric", cs + Vector3(0, 1.8, 0), 0.105, 14, 8, Color(0.05, 0.05, 0.055), Vector3(1.0, 0.72, 1.0))
	k.tube("fabric", PackedVector3Array([cs + Vector3(0, 1.755, 0), cs + Vector3(0, 1.765, 0)]), 0.16, 16, Color(0.05, 0.05, 0.055), 1.0, true)
	cl.box(cs + Vector3(-0.22, 0.0, -0.22), cs + Vector3(0.24, 1.85, 0.22))
	# her framed certificate, hung crooked; a drawing taped by the door
	Shell.sign_quad(k, "tex_docs_atlas.jpg", Vector3(-7.4, 1.5, z1 - 0.004), Vector3.FORWARD, 0.32, 0.32, _doc(1))
	Shell.sign_quad(k, "tex_drawings.jpg", Vector3(-7.2, 1.4, z0 + 0.004), Vector3.BACK, 0.34, 0.34, _doc(3))
	# ceiling bulb
	var em: StandardMaterial3D = c.mats.emissive_instance("bulb_on")
	var bc := _bulb_fixture(c, reg, Vector3(-6.4, ch, 4.6), em, true)
	_room_light(c, reg, bc - Vector3(0, 0.06, 0), "on", L_BUR, 1.0, 5.5, Color(1.0, 0.76, 0.48), em)
	_fill(c, reg, Vector3(-6.4, 0.7, 4.7), L_BUR, 0.08, 4.0, Color(1.0, 0.74, 0.5))
	c.room_fx["bur_probe"] = Shell.probe(c, reg, "ProbeRoomBureau", Vector3(x0, 0.0, z0), Vector3(x1, ch, z1), Vector3(-6.4, 1.3, 4.6), 0.8)
	Shell.decal(c, reg, "decal_scuffs.png", Vector3(-5.8, 0.0, 3.7), Vector3.UP, Vector2(1.1, 1.4), L_BUR, Color(0.12, 0.1, 0.08, 0.7), 0.1)
	Shell.decal(c, reg, "decal_scuffs.png", Vector3(-6.7, 0.0, 6.1), Vector3.UP, Vector2(1.3, 0.8), L_BUR, Color(0.12, 0.1, 0.08, 0.6), 1.4)
	Shell.decal(c, reg, "decal_water.png", Vector3(x0 + 0.01, 1.7, 5.6), Vector3.RIGHT, Vector2(1.3, 1.2), L_BUR, Color(0.3, 0.26, 0.2, 0.7))
	Shell.decal(c, reg, "decal_grime.png", Vector3(-4.9, 0.0, 5.2), Vector3.UP, Vector2(0.9, 1.6), L_BUR, Color(0.1, 0.09, 0.08, 0.7), 1.57)
	Shell.decal(c, reg, "decal_spill.png", Vector3(-7.4, 0.0, 5.0), Vector3.UP, Vector2(0.6, 0.5), L_BUR, Color(0.08, 0.07, 0.06, 0.7))

# ====================================================================== les toilettes

static func _toilet(k, cl, pos: Vector3) -> void:
	# small bowl against the wall on the +z side of pos
	k.box("enamel", pos + Vector3(-0.1, 0.0, -0.12), pos + Vector3(0.1, 0.2, 0.2), Color.WHITE)
	k.sphere("enamel", pos + Vector3(0, 0.24, -0.05), 0.2, 14, 8, Color.WHITE, Vector3(0.85, 0.5, 1.15))
	var ring := PackedVector3Array()
	for j in 17:
		var a := TAU * float(j) / 16.0
		ring.append(pos + Vector3(cos(a) * 0.14, 0.335, -0.05 + sin(a) * 0.19))
	k.tube("plastic", ring, 0.022, 6, Color(0.8, 0.78, 0.68))
	k.disc("dark", pos + Vector3(0, 0.33, -0.05), Vector3.UP, Vector3.RIGHT, 0.115, 14, Color.WHITE)
	k.rbox("enamel", pos + Vector3(-0.17, 0.3, 0.16), pos + Vector3(0.17, 0.62, 0.3), 0.02, 2, Color.WHITE)
	k.box("enamel", pos + Vector3(-0.18, 0.62, 0.15), pos + Vector3(0.18, 0.645, 0.3), Color.WHITE)
	k.box("steel_up", pos + Vector3(-0.15, 0.55, 0.145), pos + Vector3(-0.09, 0.565, 0.16), STEEL)
	cl.box(pos + Vector3(-0.18, 0.0, -0.28), pos + Vector3(0.18, 0.65, 0.3))

static func _toilettes(c) -> void:
	var R: Dictionary = GL.WC
	var reg := "room_wc"
	_shell(c, R, reg, "tile_wall", "tile_floor", "corr_ceil", false, true, false)
	_door(c, R, float(R.z0) - 0.1, 0.2, 1.0, deg_to_rad(96.0), TEAL, true)
	var k = c.kit("room_wc_props")
	var cl = c.col("room_wc_props")
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	# threshold under the vestibule wall, a "Toilettes" label beside the door on the vestibule side
	c.kit(reg).box("tile_floor", Vector3(float(R.door_x0), -0.2, z0 - 0.2), Vector3(float(R.door_x1), 0.0, z0), Color.WHITE, 1.0, Kit.FACE_PY)
	Shell.sign_quad(c.kit("room_doors"), "tex_labels.jpg", Vector3(float(R.door_x0) - 0.3, 1.6, z0 - 0.2 - 0.004), Vector3.FORWARD, 0.34, 0.26, Rect2(2.0 / 3.0, 0.5, 1.0 / 3.0, 0.5))
	# three stalls along the far wall: partitions, pilasters, a head rail, doors (west: shut, middle: the one that
	# moves, built in its own region around its hinge, east: left open)
	var sw := 0.95
	var zf := z1 - 1.3
	for i in 4:
		var px := x0 + i * sw
		if i > 0:
			k.box("steel_up", Vector3(px - 0.012, 0.15, zf), Vector3(px + 0.012, 1.55, z1), TEAL)
			cl.box(Vector3(px - 0.012, 0.15, zf), Vector3(px + 0.012, 1.55, z1))
		var ppx := px if i > 0 else px + 0.03
		k.box("steel_up", Vector3(ppx - 0.03, 0.0, zf - 0.015), Vector3(ppx + 0.03, 1.7, zf + 0.015), TEAL.darkened(0.1))
	k.box("steel_up", Vector3(x0, 1.7, zf - 0.02), Vector3(x0 + 3 * sw + 0.03, 1.74, zf + 0.02), STEEL)
	for i in 3:
		var sx := x0 + i * sw
		# fixed panel on the hinge side, 0.3 wide
		k.box("steel_up", Vector3(sx + 0.03, 0.15, zf - 0.012), Vector3(sx + 0.31, 1.55, zf + 0.012), TEAL)
		cl.box(Vector3(sx + 0.03, 0.15, zf - 0.012), Vector3(sx + 0.31, 1.55, zf + 0.012))
		_toilet(k, cl, Vector3(sx + sw * 0.5, 0.0, z1 - 0.32))
		k.tube("metal", PackedVector3Array([Vector3(sx + sw - 0.02, 0.62, z1 - 0.5), Vector3(sx + sw - 0.12, 0.62, z1 - 0.5)]), 0.008, 6, STEEL)
		k.tube("debris_paper", PackedVector3Array([Vector3(sx + sw - 0.03, 0.62, z1 - 0.5), Vector3(sx + sw - 0.11, 0.62, z1 - 0.5)]), 0.045, 12, Color(0.88, 0.86, 0.8), 1.0, true)
		var hinge := Vector3(sx + 0.31, 0.0, zf)
		if i == 0:
			k.box("steel_up", Vector3(hinge.x, 0.15, zf - 0.012), Vector3(sx + sw - 0.03, 1.55, zf + 0.012), TEAL.lightened(0.04))
			cl.box(Vector3(hinge.x, 0.15, zf - 0.012), Vector3(sx + sw - 0.03, 1.55, zf + 0.012))
		elif i == 1:
			var dk = c.kit("room_wc_stall")
			dk.box("steel_up", Vector3(0.0, 0.15, -0.012), Vector3(sw - 0.34, 1.55, 0.012), TEAL.lightened(0.04))
			dk.box("metal", Vector3(sw - 0.42, 0.85, -0.03), Vector3(sw - 0.38, 0.95, 0.03), STEEL)
			c.room_fx["stall_hinge"] = hinge
			c.room_fx["stall_w"] = sw - 0.34
		else:
			var oxf := Transform3D(Basis(Vector3.UP, -deg_to_rad(82.0)), hinge)
			k.box("steel_up", Vector3(0.0, 0.15, -0.012), Vector3(sw - 0.34, 1.55, 0.012), TEAL.lightened(0.04), 1.0, Kit.ALL, oxf)
			cl.box(Vector3(0.0, 0.15, -0.012), Vector3(sw - 0.34, 1.55, 0.012), oxf)
			# the drawing taped inside (read in garderie_rooms_fx.gd)
			var dr := Vector3(sx + sw - 0.014, 1.05, z1 - 0.75)
			Shell.sign_quad(k, "tex_drawings2.jpg", dr, Vector3.LEFT, 0.3, 0.3, _doc(3))
			c.room_fx["wc_note"] = dr
	# low counter with three basins along the west wall, taps, a long mirror
	var cz0 := z0 + 0.3
	var cz1 := cz0 + 1.8
	k.box("enamel", Vector3(x0, 0.5, cz0), Vector3(x0 + 0.44, 0.55, cz1), Color(0.86, 0.86, 0.82))
	k.box("tile_wall", Vector3(x0, 0.0, cz0 + 0.02), Vector3(x0 + 0.4, 0.5, cz1 - 0.02), Color(0.8, 0.8, 0.8))
	cl.box(Vector3(x0, 0.0, cz0), Vector3(x0 + 0.44, 0.56, cz1))
	for i in 3:
		var bz := cz0 + 0.3 + i * 0.6
		k.rbox("enamel", Vector3(x0 + 0.06, 0.55, bz - 0.19), Vector3(x0 + 0.42, 0.63, bz + 0.19), 0.03, 3, Color.WHITE)
		k.box("dark", Vector3(x0 + 0.1, 0.626, bz - 0.15), Vector3(x0 + 0.38, 0.632, bz + 0.15), Color.WHITE)
		k.tube("steel_up", PackedVector3Array([Vector3(x0 + 0.05, 0.63, bz), Vector3(x0 + 0.05, 0.78, bz), Vector3(x0 + 0.1, 0.81, bz), Vector3(x0 + 0.17, 0.78, bz)]), 0.011, 8, STEEL)
		for hz in [-0.08, 0.08]:
			k.tube("steel_up", PackedVector3Array([Vector3(x0 + 0.05, 0.63, bz + hz), Vector3(x0 + 0.05, 0.68, bz + hz)]), 0.014, 8, STEEL, 1.0, true)
		k.rbox("plastic", Vector3(x0 + 0.01, 0.9, bz + 0.22), Vector3(x0 + 0.07, 1.04, bz + 0.3), 0.012, 2, Color(0.85, 0.85, 0.8))
	c.room_fx["drip_pos"] = Vector3(x0 + 0.24, 0.6, cz0 + 0.9)
	Shell.board(k, "mirror", Vector3(x0 + 0.012, 1.25, (cz0 + cz1) * 0.5), Vector3.RIGHT, 1.7, 0.55, 0.012)
	for mz in [cz0 + 0.03, cz1 - 0.05]:
		k.box("steel_up", Vector3(x0, 0.96, mz), Vector3(x0 + 0.02, 1.54, mz + 0.02), STEEL)
	k.box("steel_up", Vector3(x0, 0.96, cz0 + 0.03), Vector3(x0 + 0.02, 0.98, cz1 - 0.03), STEEL)
	k.box("steel_up", Vector3(x0, 1.52, cz0 + 0.03), Vector3(x0 + 0.02, 1.54, cz1 - 0.03), STEEL)
	# a plastic step in front of the basins, a puddle under the middle tap, the floor drain
	k.box("plastic", Vector3(x0 + 0.5, 0.0, cz0 + 0.65), Vector3(x0 + 0.82, 0.16, cz0 + 1.15), Color(0.1, 0.25, 0.6))
	cl.box(Vector3(x0 + 0.5, 0.0, cz0 + 0.65), Vector3(x0 + 0.82, 0.16, cz0 + 1.15))
	for pd in [[1.0, 0.95, 0.26], [1.2, 1.12, 0.17], [0.86, 1.14, 0.12], [1.34, 0.9, 0.09]]:
		k.disc("wet", Vector3(x0 + float(pd[0]), 0.003, cz0 + float(pd[1])), Vector3.UP, Vector3.RIGHT, float(pd[2]), 18, Color.WHITE)
	k.disc("metal", Vector3(-13.4, 0.004, 6.9), Vector3.UP, Vector3.RIGHT, 0.07, 12, Color(0.35, 0.35, 0.35))
	# east wall: paper-towel dispenser, a bin overflowing, the mop and its bucket in the corner
	k.rbox("enamel", Vector3(x1 - 0.11, 1.05, 6.6), Vector3(x1, 1.4, 6.9), 0.015, 2, Color(0.82, 0.82, 0.78))
	k.box("debris_paper", Vector3(x1 - 0.08, 0.98, 6.66), Vector3(x1 - 0.06, 1.06, 6.84), Color(0.8, 0.76, 0.66))
	k.tube("steel_up", PackedVector3Array([Vector3(x1 - 0.25, 0.0, 7.3), Vector3(x1 - 0.25, 0.46, 7.3)]), 0.16, 14, Color(0.4, 0.4, 0.42), 1.0, true)
	for i in 5:
		k.sphere("debris_paper", Vector3(x1 - 0.25 + 0.07 * cos(i * 2.3), 0.47 + 0.02 * (i % 2), 7.3 + 0.07 * sin(i * 2.3)), 0.05, 6, 4, Color(0.84, 0.8, 0.7))
	k.sphere("debris_paper", Vector3(x1 - 0.55, 0.04, 7.55), 0.045, 6, 4, Color(0.84, 0.8, 0.7))
	cl.box(Vector3(x1 - 0.42, 0.0, 7.13), Vector3(x1 - 0.08, 0.5, 7.47))
	k.tube("plastic", PackedVector3Array([Vector3(x1 - 0.3, 0.0, z1 - 0.3), Vector3(x1 - 0.3, 0.3, z1 - 0.3)]), 0.15, 14, Color(0.75, 0.6, 0.1), 1.0, true)
	k.tube("wood", PackedVector3Array([Vector3(x1 - 0.3, 0.05, z1 - 0.3), Vector3(x1 - 0.1, 1.35, z1 - 0.08)]), 0.013, 8, Color(0.7, 0.6, 0.45))
	cl.box(Vector3(x1 - 0.47, 0.0, z1 - 0.47), Vector3(x1 - 0.05, 0.5, z1 - 0.05))
	# surface-mounted fluorescent batten: its tube flickers
	var fc := Vector3(-13.5, ch, 6.7)
	k.box("enamel", fc + Vector3(-0.64, -0.05, -0.07), fc + Vector3(0.64, 0.0, 0.07), Color.WHITE)
	var em: StandardMaterial3D = c.mats.emissive_instance("fluo_on")
	var tk = Kit.new()
	tk.tube("glow", PackedVector3Array([fc + Vector3(-0.6, -0.07, 0), fc + Vector3(0.6, -0.07, 0)]), 0.016, 10, Color.WHITE, 1.0, true)
	tk.commit(c.region(reg), {"glow": em}, "room_wc_tube", {"no_shadow": ["glow"]})
	_room_light(c, reg, fc + Vector3(0, -0.22, 0), "flicker", L_WC, 1.5, 6.0, Color(0.86, 1.0, 0.94), em)
	var wf := _fill(c, reg, Vector3(-13.5, 0.6, 6.9), L_WC, 0.12, 4.5, Color(0.86, 1.0, 0.94))
	c.lights[c.lights.size() - 1]["state"] = "flicker"      # the fill follows the flickering tube (see garderie._setup_flicker)
	wf.name = "troffer_spill_flicker"
	c.room_fx["wc_probe"] = Shell.probe(c, reg, "ProbeRoomToilettes", Vector3(x0, 0.0, z0), Vector3(x1, ch, z1), Vector3(-13.4, 1.25, 6.6), 1.0)
	# water everywhere it has been: under the basins, down the tiles, small wet footprints from the stalls to the door
	Shell.decal(c, reg, "decal_water.png", Vector3(x0 + 0.01, 1.0, cz0 + 0.9), Vector3.RIGHT, Vector2(2.0, 1.6), L_WC, Color(0.42, 0.36, 0.24, 0.7))
	Shell.decal(c, reg, "decal_water.png", Vector3(-13.9, 1.6, z1 - 0.01), Vector3.FORWARD, Vector2(1.4, 1.6), L_WC, Color(0.4, 0.34, 0.22, 0.65))
	Shell.decal(c, reg, "decal_water.png", Vector3(x1 - 0.01, 1.5, 8.2), Vector3.LEFT, Vector2(1.2, 1.5), L_WC, Color(0.4, 0.34, 0.22, 0.6))
	Shell.decal(c, reg, "decal_spill.png", Vector3(x0 + 1.15, 0.0, cz0 + 1.05), Vector3.UP, Vector2(1.5, 1.3), L_WC, Color(0.05, 0.06, 0.055, 0.6), 0.5)
	Shell.decal(c, reg, "decal_grime.png", Vector3(-13.4, 0.0, zf - 0.35), Vector3.UP, Vector2(2.9, 0.8), L_WC, Color(0.12, 0.12, 0.1, 0.7))
	Shell.decal(c, reg, "decal_grime.png", Vector3(x1 - 0.4, 0.0, 8.3), Vector3.UP, Vector2(0.8, 1.4), L_WC, Color(0.12, 0.12, 0.1, 0.7), 1.57)
	Shell.decal(c, reg, "decal_footprints.png", Vector3(-13.6, 0.0, 6.9), Vector3.UP, Vector2(0.5, 0.9), L_WC, Color(0.04, 0.05, 0.045, 0.5), -0.9)
	Shell.decal(c, reg, "decal_footprints.png", Vector3(-12.6, 0.0, 6.0), Vector3.UP, Vector2(0.5, 0.9), L_WC, Color(0.04, 0.05, 0.045, 0.38), -0.75)
