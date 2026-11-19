## Geometry of the rooms added to l'étage (etage_layout.gd): the kitchen and its pantry, the bathroom, the stairwell
## and its boarded stairs. Same rules as etage_build.gd: what moves at runtime has a region of its own, authored
## around its pivot (door leaves around their hinge, drawers around their front, the dresser around its corner, the
## bath curtain around the end it gathers at); etage.gd places and drives those nodes and finds what it needs in
## c.room_fx (positions, lights, emissive materials).
extends RefCounted

const L := preload("res://scripts/etage/etage_layout.gd")
const Build := preload("res://scripts/etage/etage_build.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")

const W := Color.WHITE
const MASK := 1 | L.L_ET
const IVORY := Color(0.66, 0.62, 0.52)
const ENAMEL := Color(0.9, 0.89, 0.82)
const CUPBOARD := Color(0.42, 0.5, 0.4)          # the kitchen's painted wood
const MOON := Color(0.52, 0.66, 1.0)
const LABELS := "labels_page"

static func build(c) -> void:
	_cuisine(c)
	_cellier(c)
	_bain(c)
	_escalier(c)
	_coffret(c)
	_finish(c)

# ====================================================================== helpers

static func _xf(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)

## Walls around the box R. sides: {"N" | "S" | "W" | "E": {"open": [[u0, u1, y0, y1], ...] (world coordinate along
## the wall: x for N / S, z for W / E), "liner": true (the wall already stands: only a 12 mm facing on this room's
## side, no collider), "t": thickness (0.1)}}. bands: [[material, y0, y1], ...] from the floor up. rail: height of a
## dado rail on the inside faces (< 0 = none).
static func _walls(c, reg: String, R: Dictionary, bands: Array, sides: Dictionary, rail := -1.0, rail_mat := "panel", rail_col := Color.WHITE) -> void:
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	for s in sides:
		var d: Dictionary = sides[s]
		var liner: bool = d.get("liner", false)
		var t: float = 0.012 if liner else float(d.get("t", 0.1))
		var o := t * 0.5 * (1.0 if liner else -1.0)        # toward the inside for a facing, outside for a wall
		var ext := 0.0 if liner else t
		var a := Vector2.ZERO
		var b := Vector2.ZERO
		var u0 := 0.0
		match s:
			"N":
				a = Vector2(x0 - ext, z0 + o)
				b = Vector2(x1 + ext, z0 + o)
				u0 = a.x
			"S":
				a = Vector2(x0 - ext, z1 - o)
				b = Vector2(x1 + ext, z1 - o)
				u0 = a.x
			"W":
				a = Vector2(x0 + o, z0)
				b = Vector2(x0 + o, z1)
				u0 = a.y
			_:
				a = Vector2(x1 - o, z0)
				b = Vector2(x1 - o, z1)
				u0 = a.y
		var opens: Array = d.get("open", [])
		for bd in bands:
			var by0: float = bd[1]
			var by1: float = bd[2]
			var cuts := []
			for op in opens:
				if float(op[3]) <= by0 + 1e-4 or float(op[2]) >= by1 - 1e-4:
					continue
				cuts.append([float(op[0]) - u0, float(op[1]) - u0, maxf(float(op[2]), by0), minf(float(op[3]), by1)])
			Shell.wall(c, reg, String(bd[0]), a, b, t, by0, by1, cuts, not liner)
		if rail > 0.0:
			# the rail runs between the openings that reach it
			var k = c.kit(reg)
			var lo := (x0 if s in ["N", "S"] else z0)
			var hi := (x1 if s in ["N", "S"] else z1)
			var stops := []
			for op in opens:
				if float(op[2]) < rail + 0.04 and float(op[3]) > rail:
					stops.append([float(op[0]) - 0.09, float(op[1]) + 0.09])
			stops.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
			var at := lo
			stops.append([hi, hi])
			var face := (t if liner else 0.0)
			for st in stops:
				if float(st[0]) > at + 0.02:
					var ua := at
					var ub: float = st[0]
					match s:
						"N": k.box(rail_mat, Vector3(ua, rail, z0 + face), Vector3(ub, rail + 0.045, z0 + face + 0.018), rail_col)
						"S": k.box(rail_mat, Vector3(ua, rail, z1 - face - 0.018), Vector3(ub, rail + 0.045, z1 - face), rail_col)
						"W": k.box(rail_mat, Vector3(x0 + face, rail, ua), Vector3(x0 + face + 0.018, rail + 0.045, ub), rail_col)
						_: k.box(rail_mat, Vector3(x1 - face - 0.018, rail, ua), Vector3(x1 - face, rail + 0.045, ub), rail_col)
				at = maxf(at, float(st[1]))

## Floor and ceiling of the box R.
static func _slabs(c, reg: String, R: Dictionary, floor_mat: String, ceil_col := Color.WHITE) -> void:
	var k = c.kit(reg)
	var ch: float = R.ceil
	k.box(floor_mat, Vector3(float(R.x0), -0.2, float(R.z0)), Vector3(float(R.x1), 0.0, float(R.z1)), W, 1.0, Kit.FACE_PY)
	k.box("plaster", Vector3(float(R.x0), ch, float(R.z0)), Vector3(float(R.x1), ch + 0.2, float(R.z1)), ceil_col, 1.0, Kit.FACE_NY)
	c.col(reg).box(Vector3(float(R.x0), ch, float(R.z0)), Vector3(float(R.x1), ch + 0.2, float(R.z1)))

## A light that only fills (no shadow), masked to the level.
static func _fill(c, light_name: String, at: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.name = light_name
	o.position = at
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.light_specular = 0.0
	o.shadow_enabled = false
	o.light_cull_mask = MASK
	c.region("et_lights").add_child(o)
	return o

## Something that glows by itself (a bulb, a pilot lamp): its own mesh and its own material, so that etage.gd can
## turn it up and down. Returns the material.
static func _glow(c, reg: String, mesh_name: String, id: String, fn: Callable) -> StandardMaterial3D:
	var em: StandardMaterial3D = c.mats.emissive_instance(id)
	var gk = Kit.new()
	fn.call(gk)
	gk.commit(c.region(reg), {"glow": em}, mesh_name, {"no_shadow": ["glow"]})
	return em

## A plain wooden chair around the floor point under its seat, the sitter facing local +z.
static func _chair(k, cl, pos: Vector3, yaw: float, col: Color) -> void:
	var xf := _xf(pos, yaw)
	for sx in [-0.19, 0.19]:
		k.box("panel", Vector3(sx - 0.02, 0.0, 0.17), Vector3(sx + 0.02, 0.44, 0.21), col, 1.0, Kit.ALL, xf)
		k.box("panel", Vector3(sx - 0.02, 0.0, -0.21), Vector3(sx + 0.02, 0.94, -0.17), col, 1.0, Kit.ALL, xf)
	k.box("panel", Vector3(-0.22, 0.44, -0.22), Vector3(0.22, 0.47, 0.22), col, 1.0, Kit.ALL, xf)
	for sy in [0.62, 0.84]:
		k.box("panel", Vector3(-0.19, sy, -0.2), Vector3(0.19, sy + 0.08, -0.18), col, 1.0, Kit.ALL, xf)
	for sz in [-0.19, 0.19]:
		k.box("panel", Vector3(-0.19, 0.2, sz - 0.012), Vector3(0.19, 0.23, sz + 0.012), col, 1.0, Kit.ALL, xf)
	cl.box(Vector3(-0.22, 0.0, -0.22), Vector3(0.22, 0.47, 0.22), xf)

## A preserving jar standing at `at`.
static func _jar(k, at: Vector3, r: float, h: float, col: Color, label := -1) -> void:
	k.tube("jar", PackedVector3Array([at, at + Vector3(0, h * 0.82, 0), at + Vector3(0, h * 0.9, 0)]), r, 10, col, 1.0, true,
		func(i: int, _a: float) -> float: return 1.0 if i < 2 else 0.8)
	k.tube("brass", PackedVector3Array([at + Vector3(0, h * 0.9, 0), at + Vector3(0, h, 0)]), r * 0.84, 10, Color(0.8, 0.8, 0.8), 1.0, true)
	if label >= 0:
		var uv := Rect2(0.5 + 0.25 * float(label % 2), 0.25 * float(label / 2), 0.25, 0.25)
		Shell.sign_quad(k, LABELS, at + Vector3(r + 0.002, h * 0.42, 0), Vector3.RIGHT, r * 1.5, r * 1.5, uv)

## Something seated under a dust sheet, authored around the floor point under the seat, facing local +z: the head
## and shoulders of the standing figures (etage_build.sheet_figure), then the cloth lies over a lap, breaks at the
## knees and falls to the floor; behind, it hangs over the back of the chair.
static func seated_figure(k, seed_: int, tint := Color.WHITE) -> void:
	# y, half width, reach forward, reach back, squareness
	var keys := [[1.3, 0.02, 0.02, 0.02, 2.0], [1.275, 0.078, 0.086, 0.082, 2.0], [1.235, 0.106, 0.118, 0.11, 2.0], [1.185, 0.104, 0.115, 0.108, 2.0],
		[1.14, 0.1, 0.106, 0.1, 2.0], [1.09, 0.17, 0.115, 0.11, 2.2], [1.04, 0.232, 0.128, 0.14, 2.4], [0.97, 0.246, 0.15, 0.215, 2.8],
		[0.8, 0.25, 0.17, 0.235, 3.0], [0.66, 0.255, 0.2, 0.24, 3.0], [0.615, 0.25, 0.4, 0.24, 3.2], [0.585, 0.25, 0.55, 0.242, 3.4],
		[0.52, 0.262, 0.59, 0.246, 3.2], [0.3, 0.285, 0.6, 0.256, 2.8], [0.06, 0.32, 0.63, 0.29, 2.5], [0.012, 0.37, 0.69, 0.34, 2.3], [0.004, 0.43, 0.76, 0.4, 2.2]]
	var rows := 52
	var cols := 49
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	var ph := float(seed_) * 1.7
	var nk := keys.size() - 1
	for r in rows:
		var t := float(r) / float(rows - 1)
		var f := t * float(nk)
		var i := mini(int(f), nk - 1)
		var u := f - float(i)
		u = u * u * (3.0 - 2.0 * u)
		var y := lerpf(float(keys[i][0]), float(keys[i + 1][0]), u)
		var rx := lerpf(float(keys[i][1]), float(keys[i + 1][1]), u)
		var rf := lerpf(float(keys[i][2]), float(keys[i + 1][2]), u)
		var rb := lerpf(float(keys[i][3]), float(keys[i + 1][3]), u)
		var sq := lerpf(float(keys[i][4]), float(keys[i + 1][4]), u)
		var fold := clampf((1.02 - y) / 0.5, 0.0, 1.0)
		var head := clampf((y - 1.1) / 0.1, 0.0, 1.0)
		for cc in cols:
			var a := TAU * float(cc % (cols - 1)) / float(cols - 1)
			var ca := cos(a)
			var sa := sin(a)
			var sup := 1.0 / pow(pow(absf(ca), sq) + pow(absf(sa), sq), 1.0 / sq)
			var w := 0.55 * sin(6.0 * a + ph + t * 2.0) + 0.3 * sin(13.0 * a - ph * 1.3 + t * 4.0) + 0.15 * sin(3.0 * a + ph * 0.6)
			var ff := 1.0 + fold * 0.09 * w
			# the knees: two rounded bumps where the lap ends
			var knee := exp(-pow((y - 0.59) / 0.07, 2.0)) * (exp(-pow((a - PI * 0.5 - 0.38) / 0.22, 2.0)) + exp(-pow((a - PI * 0.5 + 0.38) / 0.22, 2.0)))
			var front := a - PI * 0.5
			var ty := (1.3 - y) / 1.72                 # the same face as the standing ones, at the same scale
			var eyes := exp(-pow((ty - 0.066) / 0.011, 2.0)) * (exp(-pow((front - 0.36) / 0.17, 2.0)) + exp(-pow((front + 0.36) / 0.17, 2.0)))
			var nose := exp(-pow((ty - 0.082) / 0.014, 2.0)) * exp(-pow(front / 0.12, 2.0))
			var mouth := exp(-pow((ty - 0.108) / 0.009, 2.0)) * exp(-pow(front / 0.3, 2.0))
			var face := 1.0 - 0.15 * eyes + 0.07 * nose - 0.07 * mouth
			var rz := rf if sa > 0.0 else rb
			var lean := 0.05 * head                     # the head hangs forward
			P.append(Vector3(ca * sup * rx * ff * face, y, sa * sup * rz * ff * face * (1.0 + 0.06 * knee) + lean))
			U.append(Vector2(float(cc) / float(cols - 1) * 1.6, t * 1.9))
			var shade := clampf(0.76 + 0.24 * w * fold + 0.1 * (1.0 - fold), 0.42, 1.0) * (1.0 - 0.36 * eyes - 0.22 * mouth) * lerpf(1.0, 0.8, clampf((0.3 - y) / 0.3, 0.0, 1.0))
			C.append(Color(tint.r * shade, tint.g * shade, tint.b * shade))
	k.grid("sheet", P, rows, cols, U, tint, true, true, C)

## Window in a wall running along x (centre zc, thickness t; the outside lies toward `out` = -1 north / +1 south):
## frame, a cross of glazing bars, what stands behind the panes (`pane` material on the et_sky kit).
static func _window_frame(c, k, x0: float, x1: float, y0: float, y1: float, zc: float, t: float, out: float, pane: String) -> void:
	var za := zc - t * 0.5
	var zb := zc + t * 0.5
	var fw := 0.045
	k.box("paintwood", Vector3(x0, y0, za), Vector3(x0 + fw, y1, zb), IVORY)
	k.box("paintwood", Vector3(x1 - fw, y0, za), Vector3(x1, y1, zb), IVORY)
	k.box("paintwood", Vector3(x0, y1 - fw, za), Vector3(x1, y1, zb), IVORY)
	k.box("paintwood", Vector3(x0, y0, za), Vector3(x1, y0 + fw, zb), IVORY)
	var xm := (x0 + x1) * 0.5
	var ym := (y0 + y1) * 0.5
	k.box("paintwood", Vector3(xm - 0.016, y0, zc - 0.018), Vector3(xm + 0.016, y1, zc + 0.018), IVORY)
	k.box("paintwood", Vector3(x0, ym - 0.014, zc - 0.018), Vector3(x1, ym + 0.014, zc + 0.018), IVORY)
	var zs := zc - out * (t * 0.5 + 0.06)
	k.box("paintwood", Vector3(x0 - 0.05, y0 - 0.035, minf(zs, zc)), Vector3(x1 + 0.05, y0, maxf(zs, zc)), IVORY)
	var zo := zc + out * (t * 0.5 + 0.05)
	Shell.sign_quad(c.kit("et_sky"), pane, Vector3(xm, ym, zo), Vector3(0, 0, -out), (x1 - x0) + 0.5, (y1 - y0) + 0.4)

# ====================================================================== la cuisine

static func _cuisine(c) -> void:
	var R: Dictionary = L.CUISINE
	var reg := "et_cui"
	var k = c.kit(reg)
	var pk = c.kit("et_cui_props")
	pk.chamfer = 0.006
	var cl = c.col(reg)
	var cs = c.col_see(reg)
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	var top := ch + 0.2
	var fx: Dictionary = c.room_fx
	var dq: Dictionary = L.DOOR_CUISINE
	var dp: Dictionary = L.DOOR_CELLIER
	var wn: Array = L.WIN_CUISINE
	_slabs(c, reg, R, "lino", Color(0.86, 0.8, 0.62))
	_walls(c, reg, R, [["tile_cuisine", 0.0, 1.3], ["plaster_cuisine", 1.3, top]], {
		"N": {"liner": true, "open": [[float(dq.x0) - 0.02, float(dq.x1) + 0.02, 0.0, float(dq.h) + 0.02]]},
		"S": {"open": [[float(wn[0]), float(wn[1]), float(wn[2]), float(wn[3])]]},
		"W": {"open": [[float(dp.z0), float(dp.z1), 0.0, float(dp.h)]]},
		"E": {}}, 1.3, "panel")
	# the pantry door's threshold and casing (the wall is the two rooms' walls back to back)
	k.box("panel", Vector3(x0 - 0.2, -0.02, float(dp.z0)), Vector3(x0, 0.006, float(dp.z1)), Color(0.8, 0.8, 0.8))
	Build._casing_z(k, float(dp.z0), float(dp.z1), x0 - 0.1, 0.2, float(dp.h))
	# ---- the worktop along the south wall: cupboards, three drawers, the sink under the window
	var K: Dictionary = L.COUNTER
	var cz: float = K.z0
	var hk: float = K.h
	pk.box("dark", Vector3(float(K.x0) + 0.04, 0.0, cz + 0.06), Vector3(float(K.x1) - 0.04, 0.1, z1), W)
	pk.box("paintwood", Vector3(float(K.x0), 0.1, cz + 0.02), Vector3(float(K.x1), hk - 0.04, z1), CUPBOARD)
	pk.box("wood", Vector3(float(K.x0) - 0.02, hk - 0.04, cz - 0.02), Vector3(float(K.x1) + 0.02, hk, z1), Color(0.5, 0.4, 0.3))
	cl.box(Vector3(float(K.x0), 0.0, cz), Vector3(float(K.x1), hk, z1))
	var dx: Array = L.DRAWERS
	var secs := [[59.06, 59.5, 0], [59.52, 59.96, 1], [60.0, 60.46, -1], [60.5, 60.89, -1], [60.91, 61.3, -1], [61.5, 61.94, 2], [61.98, 62.26, -1]]
	for sc in secs:
		var sa: float = sc[0]
		var sb: float = sc[1]
		var door_top := hk - 0.06
		if int(sc[2]) >= 0:
			door_top = hk - 0.25
			# the hole the drawer comes out of
			pk.box("dark", Vector3(sa + 0.01, hk - 0.23, cz + 0.014), Vector3(sb - 0.01, hk - 0.06, cz + 0.021), W)
		pk.box("paintwood", Vector3(sa, 0.14, cz), Vector3(sb, door_top, cz + 0.02), CUPBOARD.lightened(0.06))
		pk.box("paintwood", Vector3(sa + 0.05, 0.19, cz - 0.006), Vector3(sb - 0.05, door_top - 0.05, cz), CUPBOARD.darkened(0.12))
		pk.sphere("brass", Vector3(sb - 0.045, door_top - 0.1, cz - 0.02), 0.016, 8, 6, W)
	for i in dx.size():
		# a drawer, around the middle of its front (it slides toward -z): front, tray, what lies in it
		var dk = c.kit("et_drawer_%d" % i)
		dk.box("paintwood", Vector3(-0.22, -0.085, -0.02), Vector3(0.22, 0.085, 0.0), CUPBOARD.lightened(0.06))
		dk.box("brass", Vector3(-0.06, -0.012, -0.045), Vector3(0.06, 0.012, -0.02), W)
		dk.box("wood", Vector3(-0.2, -0.075, 0.0), Vector3(0.2, -0.062, 0.42), Color(0.6, 0.5, 0.38))
		for sx in [-0.2, 0.188]:
			dk.box("wood", Vector3(sx, -0.075, 0.0), Vector3(sx + 0.012, 0.06, 0.42), Color(0.6, 0.5, 0.38))
		dk.box("wood", Vector3(-0.2, -0.075, 0.408), Vector3(0.2, 0.06, 0.42), Color(0.6, 0.5, 0.38))
		if i == 0:
			# cutlery, and a shopping list folded in two
			for j in 5:
				dk.box("metal", Vector3(-0.16 + j * 0.035, -0.06, 0.05), Vector3(-0.145 + j * 0.035, -0.052, 0.27), Color(0.7, 0.7, 0.68), 1.0, Kit.ALL, Transform3D(Basis(Vector3.UP, 0.04 * (j - 2)), Vector3.ZERO))
			dk.quad("debris_paper", Vector3(0.03, -0.058, 0.3), Vector3(0.17, -0.058, 0.3), Vector3(0.17, -0.058, 0.1), Vector3(0.03, -0.058, 0.1), Vector3.UP,
				Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.86, 0.82, 0.68))
		elif i == 1:
			# a mousetrap, set
			dk.box("wood", Vector3(-0.05, -0.062, 0.1), Vector3(0.05, -0.052, 0.27), Color(0.74, 0.62, 0.42))
			dk.tube("metal", PackedVector3Array([Vector3(-0.04, -0.048, 0.2), Vector3(-0.04, -0.044, 0.12), Vector3(0.04, -0.044, 0.12), Vector3(0.04, -0.048, 0.2)]), 0.003, 5, Color(0.6, 0.6, 0.6))
			dk.box("metal", Vector3(-0.045, -0.05, 0.19), Vector3(0.045, -0.042, 0.2), Color(0.6, 0.6, 0.6))
		else:
			# candle ends, a ball of string, a box of matches
			for j in 3:
				dk.tube("enamel", PackedVector3Array([Vector3(-0.14, -0.045, 0.06 + j * 0.05), Vector3(-0.02 - j * 0.02, -0.045, 0.07 + j * 0.05)]), 0.012, 8, Color(0.84, 0.8, 0.66), 1.0, true)
			dk.sphere("fabric", Vector3(0.1, -0.03, 0.28), 0.035, 10, 6, Color(0.62, 0.54, 0.4))
			dk.box("debris_paper", Vector3(0.04, -0.062, 0.08), Vector3(0.1, -0.044, 0.12), Color(0.5, 0.12, 0.1))
	fx["drawers"] = [Vector3(float(dx[0]), hk - 0.145, cz), Vector3(float(dx[1]), hk - 0.145, cz), Vector3(float(dx[2]), hk - 0.145, cz)]
	# the sink: an enamel trough, a brass swan-neck tap
	pk.rbox("enamel", Vector3(60.52, hk - 0.02, cz + 0.06), Vector3(61.28, hk + 0.035, z1 - 0.05), 0.03, 2, ENAMEL)
	k.box("dark", Vector3(60.58, hk + 0.03, cz + 0.12), Vector3(61.22, hk + 0.037, z1 - 0.11), W)
	k.tube("brass", PackedVector3Array([Vector3(60.9, hk + 0.03, z1 - 0.07), Vector3(60.9, hk + 0.3, z1 - 0.07), Vector3(60.9, hk + 0.34, z1 - 0.14), Vector3(60.9, hk + 0.27, z1 - 0.22)]), 0.013, 8, W)
	for sx in [-0.09, 0.09]:
		k.tube("brass", PackedVector3Array([Vector3(60.9 + sx, hk + 0.03, z1 - 0.07), Vector3(60.9 + sx, hk + 0.1, z1 - 0.07)]), 0.016, 8, W, 1.0, true)
	# dishes left to dry, a dishcloth
	for j in 5:
		k.tube("enamel", PackedVector3Array([Vector3(61.5 + j * 0.035, hk + 0.11, z1 - 0.2), Vector3(61.512 + j * 0.035, hk + 0.115, z1 - 0.2)]), 0.105, 14, Color(0.85, 0.84, 0.76), 1.0, true)
	pk.box("wood", Vector3(61.44, hk, z1 - 0.34), Vector3(61.72, hk + 0.02, z1 - 0.06), Color(0.6, 0.5, 0.36))
	pk.rbox("fabric", Vector3(59.2, hk, cz + 0.08), Vector3(59.48, hk + 0.03, cz + 0.3), 0.012, 2, Color(0.62, 0.3, 0.26))
	# the window over the sink: lace half-curtains, the night behind
	_window_frame(c, k, float(wn[0]), float(wn[1]), float(wn[2]), float(wn[3]), z1 + 0.05, 0.1, 1.0, "night_sky")
	for sd in [[float(wn[0]) + 0.02, float(wn[0]) + 0.3], [float(wn[1]) - 0.3, float(wn[1]) - 0.02]]:
		for f in 6:
			var fxp := lerpf(float(sd[0]), float(sd[1]), (float(f) + 0.5) / 6.0)
			k.rbox("fabric", Vector3(fxp - 0.026, float(wn[2]) + 0.03 + 0.012 * (f % 3), z1 - 0.036 - 0.01 * (f % 2)), Vector3(fxp + 0.026, float(wn[3]) - 0.3, z1 - 0.014), 0.01, 2, Color(0.4, 0.39, 0.33))
	k.tube("brass", PackedVector3Array([Vector3(float(wn[0]) - 0.06, float(wn[3]) - 0.3, z1 - 0.03), Vector3(float(wn[1]) + 0.06, float(wn[3]) - 0.3, z1 - 0.03)]), 0.006, 6, W)
	_fill(c, "CuisineNight", Vector3(60.9, 1.5, 4.3), MOON, 0.07, 3.8)
	# a shelf of plates left of the window, a wall cupboard right of it
	pk.box("paintwood", Vector3(59.1, 1.52, z1 - 0.2), Vector3(60.25, 1.55, z1), CUPBOARD)
	for bx in [59.2, 60.15]:
		pk.box("paintwood", Vector3(bx - 0.012, 1.38, z1 - 0.16), Vector3(bx + 0.012, 1.52, z1), CUPBOARD)
	for j in 6:
		var pxp := 59.24 + j * 0.16
		k.tube("enamel", PackedVector3Array([Vector3(pxp, 1.67, z1 - 0.04), Vector3(pxp, 1.675, z1 - 0.052)]), 0.11, 16, Color(0.84, 0.82, 0.72) if j % 3 != 1 else Color(0.5, 0.6, 0.66), 1.0, true)
	for j in 3:
		k.tube("enamel", PackedVector3Array([Vector3(59.3 + j * 0.14, 1.55, z1 - 0.13), Vector3(59.3 + j * 0.14, 1.63, z1 - 0.13)]), 0.04, 10, Color(0.8, 0.5, 0.2), 1.0, true)
	pk.box("paintwood", Vector3(61.62, 1.42, z1 - 0.3), Vector3(62.26, 2.0, z1), CUPBOARD)
	for sx in [61.64, 61.95]:
		pk.box("paintwood", Vector3(sx, 1.45, z1 - 0.315), Vector3(sx + 0.29, 1.97, z1 - 0.3), CUPBOARD.lightened(0.06))
		pk.sphere("brass", Vector3(sx + (0.25 if sx < 61.8 else 0.04), 1.6, z1 - 0.33), 0.014, 8, 6, W)
	# ---- the table, laid for four small people; the chairs
	var T: Vector3 = L.TABLE
	pk.box("panel", T + Vector3(-0.67, 0.71, -0.42), T + Vector3(0.67, 0.75, 0.42), Color(0.95, 0.95, 0.95))
	pk.box("panel", T + Vector3(-0.6, 0.6, -0.35), T + Vector3(0.6, 0.71, 0.35), Color(0.8, 0.8, 0.8))
	for sx in [-0.58, 0.58]:
		for sz in [-0.33, 0.33]:
			pk.box("panel", T + Vector3(sx - 0.035, 0.0, sz - 0.035), T + Vector3(sx + 0.035, 0.6, sz + 0.035), W)
	cl.box(T + Vector3(-0.67, 0.0, -0.42), T + Vector3(0.67, 0.75, 0.42))
	var chairs: Array = L.CHAIRS
	for i in chairs.size():
		_chair(pk, cs, chairs[i][0], float(chairs[i][1]), Color(0.9, 0.9, 0.9) if i % 2 == 0 else Color(0.8, 0.8, 0.8))
		# a bowl and a spoon before each chair
		var cp: Vector3 = chairs[i][0]
		var to := (T - cp).normalized()
		var bp := cp + to * 0.56 + Vector3(0, 0.75, 0)
		k.sphere("enamel", bp + Vector3(0, 0.035, 0), 0.075, 12, 6, [Color(0.8, 0.3, 0.2), Color(0.3, 0.42, 0.62), Color(0.82, 0.66, 0.2), Color(0.3, 0.52, 0.3)][i], Vector3(1.0, 0.5, 1.0))
		k.disc("dark", bp + Vector3(0, 0.068, 0), Vector3.UP, Vector3.RIGHT, 0.06, 12, Color(1.6, 1.4, 1.0))
		var side := Vector3(-to.z, 0, to.x)
		k.tube("metal", PackedVector3Array([bp + side * 0.12 - to * 0.05, bp + side * 0.12 + to * 0.07]), 0.006, 5, Color(0.7, 0.7, 0.68))
	# a note left on the table
	var note := T + Vector3(-0.32, 0.752, -0.08)
	var nb := Basis(Vector3.UP, -0.35)
	k.quad("debris_paper", note + nb * Vector3(-0.08, 0, 0.11), note + nb * Vector3(0.08, 0, 0.11), note + nb * Vector3(0.08, 0, -0.11), note + nb * Vector3(-0.08, 0, -0.11),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.86, 0.82, 0.7))
	fx["table_note"] = note
	# the lamp over the table: its bulb gone, the socket black
	k.tube("rubber", PackedVector3Array([Vector3(T.x, ch, T.z), Vector3(T.x, 1.86, T.z)]), 0.006, 5, Color(0.1, 0.09, 0.08))
	k.sphere("enamel", Vector3(T.x, 1.8, T.z), 0.21, 16, 8, Color(0.2, 0.32, 0.26), Vector3(1.0, 0.42, 1.0))
	k.tube("brass", PackedVector3Array([Vector3(T.x, 1.86, T.z), Vector3(T.x, 1.76, T.z)]), 0.02, 8, Color(0.5, 0.5, 0.5), 1.0, true)
	# a high chair pushed in the corner, a bib hung on it
	var hc := Vector3(x0 + 0.42, 0.0, z0 + 0.42)
	for sx in [-0.2, 0.2]:
		for sz in [-0.2, 0.2]:
			pk.tube("panel", PackedVector3Array([hc + Vector3(sx, 0.0, sz), hc + Vector3(sx * 0.75, 0.62, sz * 0.75)]), 0.016, 6, W)
	pk.box("panel", hc + Vector3(-0.17, 0.62, -0.17), hc + Vector3(0.17, 0.65, 0.17), W)
	pk.box("panel", hc + Vector3(-0.17, 0.65, -0.17), hc + Vector3(0.17, 0.98, -0.15), W)
	pk.box("panel", hc + Vector3(-0.2, 0.82, 0.08), hc + Vector3(0.2, 0.84, 0.3), Color(0.9, 0.9, 0.9))
	pk.rbox("fabric", hc + Vector3(-0.1, 0.72, -0.2), hc + Vector3(0.1, 0.97, -0.17), 0.012, 2, Color(0.8, 0.74, 0.5))
	cs.box(hc + Vector3(-0.22, 0.0, -0.22), hc + Vector3(0.22, 0.98, 0.3))
	# ---- the stove against the east wall: black top, a kettle, its pipe into the wall
	var S: Dictionary = L.STOVE
	pk.box("enamel", Vector3(float(S.x0), 0.14, float(S.z0)), Vector3(x1, float(S.h), float(S.z1)), Color(0.78, 0.76, 0.66))
	pk.box("dark", Vector3(float(S.x0) - 0.01, float(S.h), float(S.z0) - 0.01), Vector3(x1, float(S.h) + 0.025, float(S.z1) + 0.01), Color(1.4, 1.4, 1.4))
	pk.box("dark", Vector3(float(S.x0) - 0.008, 0.3, float(S.z0) + 0.12), Vector3(float(S.x0), 0.68, float(S.z1) - 0.12), Color(1.5, 1.5, 1.5))
	pk.box("metal", Vector3(float(S.x0) - 0.04, 0.7, float(S.z0) + 0.2), Vector3(float(S.x0) - 0.02, 0.72, float(S.z1) - 0.2), Color(0.6, 0.6, 0.6))
	for sx in [float(S.x0) + 0.05, x1 - 0.05]:
		for sz in [float(S.z0) + 0.05, float(S.z1) - 0.05]:
			pk.tube("dark", PackedVector3Array([Vector3(sx, 0.0, sz), Vector3(sx, 0.14, sz)]), 0.022, 6, Color(1.5, 1.5, 1.5), 1.0, true)
	for sz in [float(S.z0) + 0.24, float(S.z1) - 0.24]:
		k.disc("metal", Vector3(float(S.x0) + 0.3, float(S.h) + 0.027, sz), Vector3.UP, Vector3.RIGHT, 0.11, 16, Color(0.16, 0.16, 0.16))
	k.tube("dark", PackedVector3Array([Vector3(x1 - 0.14, float(S.h), float(S.z0) + 0.45), Vector3(x1 - 0.14, 1.9, float(S.z0) + 0.45), Vector3(x1 - 0.02, 2.0, float(S.z0) + 0.45)]), 0.06, 10, Color(1.3, 1.3, 1.3))
	var kt := Vector3(float(S.x0) + 0.3, float(S.h) + 0.03, float(S.z0) + 0.24)
	k.sphere("enamel", kt + Vector3(0, 0.08, 0), 0.1, 14, 8, Color(0.24, 0.34, 0.5), Vector3(1.0, 0.85, 1.0))
	k.tube("enamel", PackedVector3Array([kt + Vector3(-0.08, 0.08, 0.0), kt + Vector3(-0.16, 0.16, 0.0)]), 0.014, 6, Color(0.24, 0.34, 0.5))
	k.tube("dark", PackedVector3Array([kt + Vector3(0.0, 0.16, -0.06), kt + Vector3(0.0, 0.23, 0.0), kt + Vector3(0.0, 0.16, 0.06)]), 0.007, 6, W)
	cl.box(Vector3(float(S.x0), 0.0, float(S.z0)), Vector3(x1, float(S.h) + 0.03, float(S.z1)))
	# ---- the refrigerator in the north-east corner: an open cabinet (its door turns: own region), shelves, what is
	# left in it, the butter dish; its bulb and the light it throws across the room
	var F: Dictionary = L.FRIDGE
	var fa: float = F.x0
	var fb: float = F.x1
	var fz0: float = F.z0
	var fz1: float = F.z1
	var fh: float = F.h
	pk.box("enamel", Vector3(fa, 0.05, fz0), Vector3(fb, 0.2, fz1), ENAMEL)
	pk.box("enamel", Vector3(fa, 0.2, fz0), Vector3(fb, fh, fz0 + 0.04), ENAMEL)
	pk.box("enamel", Vector3(fa, 0.2, fz1 - 0.04), Vector3(fb, fh, fz1), ENAMEL)
	pk.box("enamel", Vector3(fb - 0.04, 0.2, fz0), Vector3(fb, fh, fz1), ENAMEL)
	pk.rbox("enamel", Vector3(fa, fh - 0.05, fz0), Vector3(fb, fh + 0.02, fz1), 0.02, 2, ENAMEL)
	k.box("dark", Vector3(fa + 0.02, 0.0, fz0 + 0.03), Vector3(fb, 0.05, fz1 - 0.03), W)
	# the ice box at the top, furred with frost
	pk.box("metal", Vector3(fa + 0.05, fh - 0.34, fz0 + 0.06), Vector3(fb - 0.06, fh - 0.07, fz1 - 0.06), Color(0.74, 0.78, 0.8))
	pk.box("enamel", Vector3(fa + 0.04, fh - 0.33, fz0 + 0.08), Vector3(fa + 0.05, fh - 0.08, fz1 - 0.08), Color(0.92, 0.95, 0.96))
	for sy in [0.52, 0.86]:
		for j in 8:
			var wz := fz0 + 0.06 + j * (fz1 - fz0 - 0.12) / 7.0
			k.box("metal", Vector3(fa + 0.04, sy, wz - 0.003), Vector3(fb - 0.05, sy + 0.006, wz + 0.003), Color(0.62, 0.62, 0.6))
		k.box("metal", Vector3(fa + 0.04, sy, fz0 + 0.05), Vector3(fa + 0.046, sy + 0.012, fz1 - 0.05), Color(0.62, 0.62, 0.6))
	# a bottle of milk gone solid, a covered plate, two jars, something wrapped in paper
	k.tube("jar", PackedVector3Array([Vector3(fb - 0.2, 0.866, fz0 + 0.14), Vector3(fb - 0.2, 1.02, fz0 + 0.14), Vector3(fb - 0.2, 1.08, fz0 + 0.14), Vector3(fb - 0.2, 1.12, fz0 + 0.14)]), 0.042, 10, Color(0.62, 0.6, 0.46), 1.0, true,
		func(i: int, _a: float) -> float: return 1.0 if i < 2 else 0.5)
	k.tube("enamel", PackedVector3Array([Vector3(fa + 0.28, 0.526, fz1 - 0.24), Vector3(fa + 0.28, 0.534, fz1 - 0.24)]), 0.13, 16, Color(0.82, 0.8, 0.7), 1.0, true)
	k.sphere("enamel", Vector3(fa + 0.28, 0.534, fz1 - 0.24), 0.11, 14, 6, Color(0.7, 0.72, 0.66), Vector3(1.0, 0.6, 1.0))
	_jar(k, Vector3(fb - 0.16, 0.526, fz0 + 0.16), 0.045, 0.15, Color(0.1, 0.16, 0.08))
	_jar(k, Vector3(fb - 0.17, 0.526, fz0 + 0.3), 0.04, 0.12, Color(0.3, 0.05, 0.04))
	k.rbox("debris_paper", Vector3(fa + 0.14, 0.2, fz0 + 0.1), Vector3(fa + 0.4, 0.3, fz0 + 0.3), 0.03, 2, Color(0.7, 0.62, 0.5))
	# the butter dish on the middle shelf: its base stays, its cover lifts (own region, around its middle)
	var bd := Vector3(fa + 0.26, 0.866, fz0 + 0.4)
	k.rbox("enamel", bd + Vector3(-0.06, 0.0, -0.09), bd + Vector3(0.06, 0.014, 0.09), 0.006, 1, Color(0.84, 0.82, 0.7))
	var lk = c.kit("et_butter_lid")
	lk.rbox("enamel", Vector3(-0.05, 0.0, -0.08), Vector3(0.05, 0.055, 0.08), 0.02, 2, Color(0.84, 0.82, 0.7))
	lk.sphere("enamel", Vector3(0, 0.062, 0), 0.014, 8, 6, Color(0.3, 0.42, 0.62))
	fx["butter"] = bd + Vector3(0, 0.014, 0)
	# the bedroom's spare key under it, its paper tag
	var kk = c.kit("et_ckey")
	var ring := PackedVector3Array()
	for j in 13:
		var a := TAU * float(j) / 12.0
		ring.append(Vector3(cos(a) * 0.012, 0.0, sin(a) * 0.012 - 0.034))
	kk.tube("brass", ring, 0.003, 6, Color(0.7, 0.7, 0.72))
	kk.box("brass", Vector3(-0.003, -0.003, -0.022), Vector3(0.003, 0.003, 0.04), Color(0.7, 0.7, 0.72))
	kk.box("brass", Vector3(0.0, -0.002, 0.026), Vector3(0.012, 0.002, 0.04), Color(0.7, 0.7, 0.72))
	kk.quad(LABELS, Vector3(0.012, 0.001, -0.07), Vector3(0.07, 0.001, -0.07), Vector3(0.07, 0.001, -0.04), Vector3(0.012, 0.001, -0.04), Vector3.UP,
		Vector2(0.5, 0.75), Vector2(1.0, 0.75), Vector2(1.0, 0.5), Vector2(0.5, 0.5))
	# the door, around its hinge (the north edge): it runs along local +x, its outer face toward local +z
	var fk = c.kit("et_fridge_door")
	fk.chamfer = 0.006
	var fw := fz1 - fz0
	fk.rbox("enamel", Vector3(0.0, 0.2, 0.0), Vector3(fw, fh + 0.02, 0.055), 0.02, 2, ENAMEL)
	fk.box("enamel", Vector3(0.03, 0.24, -0.03), Vector3(fw - 0.03, fh - 0.04, 0.0), Color(0.92, 0.92, 0.88))
	for sy in [0.4, 0.8, 1.15]:
		fk.box("enamel", Vector3(0.05, sy, -0.09), Vector3(fw - 0.05, sy + 0.012, -0.03), Color(0.92, 0.92, 0.88))
		fk.box("metal", Vector3(0.05, sy + 0.07, -0.09), Vector3(fw - 0.05, sy + 0.076, -0.084), Color(0.62, 0.62, 0.6))
	fk.tube("jar", PackedVector3Array([Vector3(0.2, 0.412, -0.06), Vector3(0.2, 0.6, -0.06)]), 0.028, 8, Color(0.16, 0.2, 0.1), 1.0, true)
	fk.tube("jar", PackedVector3Array([Vector3(0.42, 0.812, -0.06), Vector3(0.42, 0.95, -0.06)]), 0.03, 8, Color(0.36, 0.2, 0.06), 1.0, true)
	fk.rbox("metal", Vector3(fw - 0.1, 0.95, 0.055), Vector3(fw - 0.05, 1.2, 0.085), 0.012, 2, Color(0.7, 0.7, 0.7))
	fk.box("metal", Vector3(0.12, fh - 0.18, 0.055), Vector3(0.4, fh - 0.14, 0.06), Color(0.6, 0.6, 0.6))
	fx["fridge_hinge"] = Vector3(fa, 0.0, fz0)
	fx["fridge_at"] = Vector3(fa - 0.03, 1.0, (fz0 + fz1) * 0.5)
	cl.box(Vector3(fa - 0.05, 0.0, fz0), Vector3(fb, fh + 0.02, fz1))
	var bulb_at := Vector3(fb - 0.07, fh - 0.4, (fz0 + fz1) * 0.5)
	var fem := _glow(c, reg, "et_fridge_bulb", "fridge_glow", func(gk) -> void: gk.sphere("glow", bulb_at, 0.024, 10, 6, W))
	var fl := SpotLight3D.new()
	fl.name = "FridgeLight"
	fl.position = Vector3(fb - 0.16, fh - 0.46, (fz0 + fz1) * 0.5)
	fl.light_color = Color(1.0, 0.96, 0.78)
	fl.light_energy = 5.0
	fl.spot_range = 7.5
	fl.spot_angle = 64.0
	fl.spot_angle_attenuation = 0.7
	fl.spot_attenuation = 1.0
	fl.light_specular = 0.5
	fl.shadow_enabled = true
	fl.shadow_bias = 0.04
	fl.shadow_normal_bias = 1.2
	fl.shadow_blur = 1.4
	fl.light_cull_mask = MASK
	fl.light_volumetric_fog_energy = 0.5
	fl.basis = Basis.looking_at(Vector3(59.3, 0.7, 3.1) - fl.position, Vector3.UP)
	c.region("et_lights").add_child(fl)
	# what the lit floor and the cabinet's enamel send back
	var fb2 := _fill(c, "FridgeBounce", Vector3(fa - 0.7, 0.5, fz1 + 0.3), Color(1.0, 0.94, 0.76), 0.16, 3.6)
	fx["fridge"] = {"light": fl, "fill": fb2, "emit": fem, "energy": 5.0, "fill_energy": 0.16}
	# ---- the dresser pushed across the pantry door (it slides: own region, around its north-west foot)
	var B: Array = L.BUFFET
	var bw := float(B[2]) - float(B[0])
	var bl := float(B[3]) - float(B[1])
	var bh: float = L.BUFFET_H
	var bk = c.kit("et_buffet")
	bk.chamfer = 0.006
	bk.box("panel", Vector3(0.0, 0.08, 0.0), Vector3(bw, bh - 0.03, bl), W)
	bk.box("panel", Vector3(-0.0, bh - 0.03, -0.02), Vector3(bw + 0.03, bh, bl + 0.02), Color(0.86, 0.86, 0.86))
	for sz in [0.03, bl - 0.09]:
		for sx in [0.02, bw - 0.08]:
			bk.box("panel", Vector3(sx, 0.0, sz), Vector3(sx + 0.06, 0.08, sz + 0.06), W)
	for j in 2:
		var da := 0.04 + j * (bl - 0.06) * 0.5
		var db := da + (bl - 0.1) * 0.5
		bk.box("panel", Vector3(bw, 0.14, da), Vector3(bw + 0.014, 0.62, db), Color(0.84, 0.84, 0.84))
		bk.box("panel", Vector3(bw, 0.66, da), Vector3(bw + 0.014, bh - 0.06, db), Color(0.84, 0.84, 0.84))
		bk.sphere("brass", Vector3(bw + 0.028, 0.78, (da + db) * 0.5), 0.016, 8, 6, W)
		bk.sphere("brass", Vector3(bw + 0.028, 0.4, db - 0.05 if j == 0 else da + 0.05), 0.014, 8, 6, W)
	# on it: a soup tureen, a pile of plates, a child's cup
	bk.sphere("enamel", Vector3(bw * 0.5, bh + 0.09, 0.3), 0.14, 16, 8, Color(0.82, 0.8, 0.7), Vector3(1.0, 0.7, 1.15))
	bk.sphere("enamel", Vector3(bw * 0.5, bh + 0.19, 0.3), 0.022, 8, 6, Color(0.3, 0.42, 0.62))
	for j in 6:
		bk.tube("enamel", PackedVector3Array([Vector3(bw * 0.5, bh + j * 0.012, 0.74), Vector3(bw * 0.5, bh + j * 0.012 + 0.008, 0.74)]), 0.1, 16, Color(0.84, 0.82, 0.72), 1.0, true)
	bk.tube("enamel", PackedVector3Array([Vector3(bw * 0.4, bh, 0.95), Vector3(bw * 0.4, bh + 0.07, 0.95)]), 0.03, 10, Color(0.82, 0.66, 0.2), 1.0, true)
	fx["buffet_pos"] = Vector3(float(B[0]), 0.0, float(B[1]))
	fx["buffet_size"] = Vector3(bw, bh, bl)
	# ---- the calendar on the west wall, a nail; the day ringed in red is laid on it by etage.gd (own region)
	var cal: Vector3 = L.CALENDAR
	var cw: Vector2 = L.CAL_SIZE
	Shell.board(k, "debris_paper", cal + Vector3(0.002, 0, 0), Vector3.RIGHT, cw.x + 0.004, cw.y + 0.004, 0.003, Color(0.6, 0.56, 0.46))
	Shell.sign_quad(k, "cal_page", cal + Vector3(0.0045, 0, 0), Vector3.RIGHT, cw.x, cw.y)
	k.sphere("metal", cal + Vector3(0.008, cw.y * 0.5 - 0.016, 0), 0.006, 6, 4, Color(0.3, 0.3, 0.3))
	var rk = c.kit("et_cal_ring")
	var loop := PackedVector3Array()
	for j in 30:
		var a := TAU * 1.12 * float(j) / 29.0 + 0.6
		var rr := 1.0 + 0.1 * sin(a * 1.7) - 0.08 * float(j) / 29.0
		loop.append(Vector3(0.0, sin(a) * 0.019 * rr, cos(a) * 0.021 * rr))
	rk.tube("red_pencil", loop, 0.0016, 5, W)
	# a broom in the corner by the doorway, a pail
	k.tube("wood", PackedVector3Array([Vector3(x1 - 0.12, 0.06, z1 - 0.5), Vector3(x1 - 0.04, 1.4, z1 - 0.12)]), 0.012, 6, Color(0.7, 0.6, 0.44))
	pk.rbox("fabric", Vector3(x1 - 0.26, 0.0, z1 - 0.6), Vector3(x1 - 0.04, 0.14, z1 - 0.42), 0.03, 2, Color(0.5, 0.42, 0.26))
	k.tube("steel_up", PackedVector3Array([Vector3(x1 - 0.3, 0.0, 4.3), Vector3(x1 - 0.3, 0.26, 4.3)]), 0.13, 12, Color(0.4, 0.42, 0.44), 1.0, true,
		func(i: int, _a: float) -> float: return 0.85 if i == 0 else 1.0)
	cl.box(Vector3(x1 - 0.45, 0.0, 4.15), Vector3(x1, 0.3, 4.45))

# ====================================================================== le garde-manger

static func _cellier(c) -> void:
	var R: Dictionary = L.CELLIER
	var reg := "et_cel"
	var k = c.kit(reg)
	var cl = c.col(reg)
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	var top := ch + 0.2
	var fx: Dictionary = c.room_fx
	var dp: Dictionary = L.DOOR_CELLIER
	_slabs(c, reg, R, "stone_floor", Color(0.8, 0.8, 0.78))
	_walls(c, reg, R, [["whitewash", 0.0, top]], {"N": {}, "S": {}, "W": {}, "E": {"open": [[float(dp.z0), float(dp.z1), 0.0, float(dp.h)]]}})
	# the door (it turns: own region, around its hinge at the south jamb, opening into the pantry): on the kitchen
	# side, a strip of sticking plaster across it
	var dk = c.kit("et_door_cellier")
	var dw := float(dp.z1) - float(dp.z0) - 0.04
	Build._leaf(dk, dw, float(dp.h), Color(0.62, 0.66, 0.56))
	dk.quad(LABELS, Vector3(0.1, 1.38, 0.03), Vector3(dw - 0.08, 1.46, 0.03), Vector3(dw - 0.08, 1.6, 0.03), Vector3(0.1, 1.52, 0.03), Vector3(0, 0, 1),
		Vector2(0.5, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.75), Vector2(0.5, 0.75))
	fx["cellier_hinge"] = Vector3(x1 + 0.1, 0.0, float(dp.z1) - 0.02)
	# shelves along the west wall, floor to ceiling: preserves, row after row
	var rng := RandomNumberGenerator.new()
	rng.seed = 1994
	var cols := [Color(0.34, 0.18, 0.04), Color(0.3, 0.04, 0.04), Color(0.1, 0.17, 0.06), Color(0.46, 0.36, 0.1), Color(0.12, 0.05, 0.1), Color(0.4, 0.4, 0.3)]
	var wood := Color(0.56, 0.48, 0.36)
	for uz in [z0 + 0.06, (z0 + z1) * 0.5, z1 - 0.06]:
		k.box("wood", Vector3(x0, 0.0, uz - 0.02), Vector3(x0 + 0.34, 2.05, uz + 0.02), wood)
	var tin: Vector3 = L.FUSE_TIN
	var li := 0
	for sy in [0.42, 0.84, 1.26, 1.68]:
		k.box("wood", Vector3(x0, sy - 0.025, z0 + 0.04), Vector3(x0 + 0.34, sy, z1 - 0.04), wood)
		var z := z0 + 0.16
		while z < z1 - 0.14:
			var r := rng.randf_range(0.042, 0.06)
			if absf(sy - 1.26) < 0.01 and absf(z - tin.z) < 0.26:
				z += 0.1                                  # the tin of fuses stands here
				continue
			if rng.randf() < 0.13:
				z += rng.randf_range(0.08, 0.2)
				continue
			var lab := -1
			if rng.randf() < 0.4:
				lab = li % 4
				li += 1
			_jar(k, Vector3(x0 + 0.17 + rng.randf_range(-0.03, 0.05), sy, z), r, rng.randf_range(0.13, 0.2), cols[rng.randi() % cols.size()].darkened(rng.randf_range(0.0, 0.3)), lab)
			if rng.randf() < 0.35 and r < 0.05:
				_jar(k, Vector3(x0 + 0.07, sy, z + 0.01), 0.04, rng.randf_range(0.12, 0.17), cols[rng.randi() % cols.size()])
			z += r * 2.0 + rng.randf_range(0.012, 0.04)
	cl.box(Vector3(x0, 0.0, z0), Vector3(x0 + 0.34, 2.05, z1))
	# the tin of spare fuses, its lid beside it; one fuse lies ready on the shelf (taken: own region)
	k.box("steel_up", tin + Vector3(-0.07, -0.04, -0.1), tin + Vector3(0.07, 0.045, 0.1), Color(0.42, 0.12, 0.08))
	Shell.sign_quad(k, LABELS, tin + Vector3(0.0705, 0.0, 0.0), Vector3.RIGHT, 0.19, 0.08, Rect2(0.03, 0.56, 0.44, 0.19))
	k.box("dark", tin + Vector3(-0.06, 0.044, -0.09), tin + Vector3(0.06, 0.046, 0.09), W)
	k.box("steel_up", tin + Vector3(-0.07, -0.04, 0.13), tin + Vector3(0.07, -0.028, 0.33), Color(0.42, 0.12, 0.08), 1.0, Kit.ALL, Transform3D(Basis(Vector3.UP, 0.2), Vector3.ZERO))
	for j in 3:
		_fuse(k, tin + Vector3(-0.03 + j * 0.03, 0.046, -0.05 + j * 0.04), Vector3.UP)
	_fuse(c.kit("et_fuse_item"), Vector3.ZERO, Vector3.RIGHT)
	fx["fuse_item"] = tin + Vector3(0.12, -0.018, -0.14)
	# shelves on the south wall: tins, bottles lying down, an enamel pot
	for sy in [0.6, 1.1, 1.6]:
		k.box("wood", Vector3(x0 + 0.4, sy - 0.025, z1 - 0.3), Vector3(x1 - 0.06, sy, z1), wood)
		var xs := x0 + 0.5
		while xs < x1 - 0.2:
			var kind := rng.randi() % 3
			if kind == 0:
				k.tube("steel_up", PackedVector3Array([Vector3(xs, sy, z1 - 0.15), Vector3(xs, sy + 0.12, z1 - 0.15)]), 0.05, 10, Color(0.5, 0.48, 0.42).darkened(rng.randf() * 0.3), 1.0, true)
			elif kind == 1:
				_jar(k, Vector3(xs, sy, z1 - 0.14), 0.05, 0.22, cols[rng.randi() % cols.size()])
			else:
				k.tube("jar", PackedVector3Array([Vector3(xs, sy + 0.04, z1 - 0.28), Vector3(xs, sy + 0.04, z1 - 0.06)]), 0.04, 10, Color(0.05, 0.1, 0.05), 1.0, true)
			xs += rng.randf_range(0.13, 0.22)
	for bx in [x0 + 0.42, x1 - 0.1]:
		k.box("wood", Vector3(bx - 0.015, 0.0, z1 - 0.3), Vector3(bx + 0.015, 1.6, z1 - 0.27), wood)
	cl.box(Vector3(x0 + 0.4, 0.0, z1 - 0.3), Vector3(x1, 1.7, z1))
	# sacks slumped at the north end, a crate of potatoes gone to shoots
	for sk in [[Vector3(x0 + 0.75, 0.0, z0 + 0.3), 0.28, 0.5], [Vector3(x0 + 1.3, 0.0, z0 + 0.28), 0.24, 0.62], [Vector3(x0 + 1.0, 0.0, z0 + 0.62), 0.22, 0.3]]:
		var sp: Vector3 = sk[0]
		var sr: float = sk[1]
		var shh: float = sk[2]
		var burlap := Color(0.2, 0.165, 0.11)
		k.rbox("fabric", sp + Vector3(-sr, 0.0, -sr * 0.8), sp + Vector3(sr, shh, sr * 0.8), sr * 0.62, 3, burlap, 1.0, Transform3D(Basis(Vector3.UP, sp.x * 2.0), Vector3.ZERO).translated(sp - Basis(Vector3.UP, sp.x * 2.0) * sp))
		k.sphere("fabric", sp + Vector3(0.02, shh + 0.02, 0.0), 0.06, 8, 6, burlap.darkened(0.2), Vector3(1.0, 0.8, 1.0))
	k.box("wood", Vector3(x1 - 0.62, 0.0, z0 + 0.1), Vector3(x1 - 0.1, 0.26, z0 + 0.5), wood.darkened(0.2))
	for j in 9:
		k.sphere("fabric", Vector3(x1 - 0.54 + (j % 3) * 0.17, 0.27, z0 + 0.18 + (j / 3) * 0.12), 0.05, 8, 5, Color(0.2, 0.16, 0.1), Vector3(1.0, 0.7, 0.8))
	cl.box(Vector3(x0 + 0.4, 0.0, z0), Vector3(x1, 0.5, z0 + 0.75))
	# a dust sheet on the floor, with nothing under it any more
	var hp := Vector3(x0 + 1.2, 0.0, z0 + 1.35)
	var sh = c.kit(reg)
	sh.sphere("sheet", hp + Vector3(0, 0.02, 0), 0.5, 20, 8, Color(0.92, 0.92, 0.9), Vector3(1.0, 0.16, 0.8))
	sh.sphere("sheet", hp + Vector3(0.12, 0.08, -0.1), 0.2, 14, 8, W, Vector3(1.2, 0.5, 0.9))
	sh.sphere("sheet", hp + Vector3(-0.2, 0.06, 0.14), 0.16, 12, 6, Color(0.9, 0.9, 0.88), Vector3(1.3, 0.5, 0.8))
	for j in 7:
		var a := float(j) * 0.9 + 0.3
		sh.tube("sheet", PackedVector3Array([hp + Vector3(cos(a) * 0.08, 0.1, sin(a) * 0.07), hp + Vector3(cos(a) * 0.3, 0.05, sin(a) * 0.25), hp + Vector3(cos(a) * 0.5, 0.012, sin(a) * 0.4)]), 0.035, 6, Color(0.86, 0.86, 0.84))
	fx["heap"] = hp
	# the bulb on its flex: dead
	k.tube("rubber", PackedVector3Array([Vector3((x0 + x1) * 0.5, ch, 3.6), Vector3((x0 + x1) * 0.5, ch - 0.3, 3.6)]), 0.005, 5, Color(0.1, 0.09, 0.08))
	k.sphere("jar", Vector3((x0 + x1) * 0.5, ch - 0.35, 3.6), 0.034, 10, 8, Color(0.3, 0.3, 0.28), Vector3(1.0, 1.3, 1.0))

## A porcelain fuse (a plug with a brass cap at each end), lying along `axis` from `at`.
static func _fuse(k, at: Vector3, axis: Vector3) -> void:
	k.tube("enamel", PackedVector3Array([at, at + axis * 0.05]), 0.014, 10, Color(0.9, 0.88, 0.8), 1.0, true)
	k.tube("brass", PackedVector3Array([at - axis * 0.004, at + axis * 0.008]), 0.0125, 10, W, 1.0, true)
	k.tube("brass", PackedVector3Array([at + axis * 0.044, at + axis * 0.056]), 0.0155, 10, W, 1.0, true)

# ====================================================================== la salle de bain

static func _bain(c) -> void:
	var R: Dictionary = L.BAIN
	var reg := "et_bain"
	var k = c.kit(reg)
	var pk = c.kit("et_bain_props")
	pk.chamfer = 0.006
	var cl = c.col(reg)
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	var top := ch + 0.2
	var fx: Dictionary = c.room_fx
	var db: Dictionary = L.DOOR_BAIN
	var dado := 1.56
	var green := Color(0.1, 0.2, 0.14)
	var wy := [1.36, 2.04]
	var wx := [53.0, 53.72]
	_slabs(c, reg, R, "tile_bain_floor", Color(0.74, 0.8, 0.72))
	_walls(c, reg, R, [["tile_bain", 0.0, dado], ["plaster_bain", dado, top]], {
		"N": {"liner": true, "open": [[float(db.x0) - 0.02, float(db.x1) + 0.02, 0.0, float(db.h) + 0.02]]},
		"S": {"open": [[wx[0], wx[1], wy[0], wy[1]]]}, "W": {}, "E": {}}, dado, "enamel", green)
	# the door (own region, around its hinge at the east jamb, opening into the bathroom)
	var dk = c.kit("et_door_bain")
	Build._leaf(dk, float(db.x1) - float(db.x0) - 0.04, float(db.h), Color(0.72, 0.76, 0.7))
	fx["bain_hinge"] = Vector3(float(db.x1) - 0.02, 0.0, float(L.HALL.z1) + 0.02)
	# ---- the bath in its alcove: a tiled stub wall at its foot, a rail, the curtain drawn (own region)
	var T: Dictionary = L.TUB
	var ta: float = T.x0
	var tb: float = T.x1
	var tz0: float = T.z0
	var tz1: float = T.z1
	var th: float = T.h
	k.box("tile_bain", Vector3(tb + 0.1, 0.0, tz0 - 0.14), Vector3(tb + 0.2, dado, z1), W)
	k.box("plaster_bain", Vector3(tb + 0.1, dado, tz0 - 0.14), Vector3(tb + 0.2, top, z1), W)
	k.box("enamel", Vector3(tb + 0.09, dado, tz0 - 0.15), Vector3(tb + 0.21, dado + 0.045, z1), green)
	cl.box(Vector3(tb + 0.1, 0.0, tz0 - 0.14), Vector3(tb + 0.2, top, z1))
	pk.rbox("enamel", Vector3(ta, 0.12, tz0), Vector3(tb, th - 0.07, tz1), 0.09, 3, ENAMEL)
	for rm in [[Vector3(ta, th - 0.09, tz0), Vector3(tb, th, tz0 + 0.07)], [Vector3(ta, th - 0.09, tz1 - 0.07), Vector3(tb, th, tz1)],
			[Vector3(ta, th - 0.09, tz0), Vector3(ta + 0.08, th, tz1)], [Vector3(tb - 0.08, th - 0.09, tz0), Vector3(tb, th, tz1)]]:
		pk.rbox("enamel", rm[0], rm[1], 0.03, 2, ENAMEL)
	# black water, to the brim
	k.quad("wet", Vector3(ta + 0.07, th - 0.035, tz1 - 0.06), Vector3(tb - 0.07, th - 0.035, tz1 - 0.06), Vector3(tb - 0.07, th - 0.035, tz0 + 0.06), Vector3(ta + 0.07, th - 0.035, tz0 + 0.06),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	for sx in [ta + 0.16, tb - 0.16]:
		for sz in [tz0 + 0.1, tz1 - 0.1]:
			k.sphere("brass", Vector3(sx, 0.07, sz), 0.07, 10, 6, Color(0.6, 0.6, 0.6), Vector3(0.9, 1.0, 0.9))
	k.tube("brass", PackedVector3Array([Vector3(tb + 0.1, th + 0.2, tz0 + 0.35), Vector3(tb - 0.02, th + 0.2, tz0 + 0.35), Vector3(tb - 0.05, th + 0.12, tz0 + 0.35)]), 0.016, 8, W)
	for sz in [-0.1, 0.1]:
		k.tube("brass", PackedVector3Array([Vector3(tb + 0.1, th + 0.26, tz0 + 0.35 + sz), Vector3(tb + 0.04, th + 0.26, tz0 + 0.35 + sz)]), 0.02, 8, W, 1.0, true)
	cl.box(Vector3(ta, 0.0, tz0), Vector3(tb, th, tz1))
	# a yellow duck on the rim
	var dkp := Vector3(tb - 0.3, th + 0.03, tz0 + 0.035)
	k.sphere("plastic", dkp, 0.04, 10, 8, Color(0.82, 0.62, 0.08), Vector3(1.3, 0.8, 0.9))
	k.sphere("plastic", dkp + Vector3(0.035, 0.04, 0), 0.026, 10, 8, Color(0.82, 0.62, 0.08))
	k.sphere("plastic", dkp + Vector3(0.062, 0.036, 0), 0.01, 6, 4, Color(0.8, 0.3, 0.06), Vector3(1.4, 0.5, 1.0))
	var cu: Dictionary = L.CURTAIN
	var cz: float = cu.z
	k.tube("brass", PackedVector3Array([Vector3(x0, float(cu.y1) + 0.04, cz), Vector3(tb + 0.1, float(cu.y1) + 0.04, cz)]), 0.011, 8, W)
	var ck = c.kit("et_curtain")
	var cw := float(cu.x1) - float(cu.x0)
	var rows := 10
	var cols := 97
	for side in 2:
		var P := PackedVector3Array()
		var U := PackedVector2Array()
		var C := PackedColorArray()
		for r in rows:
			var v := float(r) / float(rows - 1)
			var y := lerpf(float(cu.y1), float(cu.y0), v)
			for cc in cols:
				var u := float(cc) / float(cols - 1)
				var w := sin(u * TAU * 11.0 + 0.5 * sin(u * 9.0))
				var amp := lerpf(0.022, 0.05, v)
				P.append(Vector3(u * cw, y, w * amp + 0.012 * sin(u * 5.0 + v * 2.0) + (0.0025 if side == 0 else -0.0025)))
				U.append(Vector2(u * cw, v * 1.7))
				var shade := 0.8 + 0.2 * w * (1.0 if side == 0 else -1.0)
				C.append(Color(shade, shade, shade))
		ck.grid("curtain", P, rows, cols, U, W, false, side == 1, C)
	for j in 13:
		var rx := (float(j) + 0.5) / 13.0 * cw
		ck.tube("brass", PackedVector3Array([Vector3(rx, float(cu.y1) - 0.01, 0.0), Vector3(rx, float(cu.y1) + 0.065, 0.0)]), 0.005, 5, W)
	fx["curtain_pos"] = Vector3(float(cu.x0), 0.0, cz)
	fx["curtain_w"] = cw
	# the frosted window over the bath, the night behind it
	_window_frame(c, k, wx[0], wx[1], wy[0], wy[1], z1 + 0.05, 0.1, 1.0, "frost_glow")
	_fill(c, "BainNight", Vector3(53.36, 1.9, 3.2), MOON.lerp(Color(0.5, 0.9, 0.7), 0.3), 0.075, 3.6)
	# ---- the lavatory in the south-east corner: bowl, wooden seat, the cistern high on the wall, its chain
	var wc := Vector3(55.32, 0.0, z1 - 0.34)
	pk.box("enamel", wc + Vector3(-0.11, 0.0, -0.1), wc + Vector3(0.11, 0.22, 0.34), ENAMEL)
	k.sphere("enamel", wc + Vector3(0, 0.26, -0.06), 0.21, 14, 8, ENAMEL, Vector3(0.85, 0.55, 1.15))
	var seat := PackedVector3Array()
	for j in 17:
		var a := TAU * float(j) / 16.0
		seat.append(wc + Vector3(cos(a) * 0.15, 0.385, -0.06 + sin(a) * 0.2))
	k.tube("panel", seat, 0.025, 6, W)
	k.disc("dark", wc + Vector3(0, 0.375, -0.06), Vector3.UP, Vector3.RIGHT, 0.12, 14, W)
	pk.box("panel", wc + Vector3(-0.2, 0.38, 0.14), wc + Vector3(0.2, 0.8, 0.17), W, 1.0, Kit.ALL, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3.ZERO))
	pk.rbox("enamel", wc + Vector3(-0.22, 1.84, 0.12), wc + Vector3(0.22, 2.16, 0.34), 0.02, 2, ENAMEL)
	k.tube("brass", PackedVector3Array([wc + Vector3(0.0, 1.84, 0.28), wc + Vector3(0.0, 0.3, 0.28)]), 0.02, 8, W)
	k.tube("metal", PackedVector3Array([wc + Vector3(0.18, 1.9, 0.1), wc + Vector3(0.18, 1.1, 0.1)]), 0.003, 4, Color(0.5, 0.5, 0.5))
	k.tube("enamel", PackedVector3Array([wc + Vector3(0.18, 1.1, 0.1), wc + Vector3(0.18, 1.0, 0.1)]), 0.016, 8, ENAMEL, 1.0, true)
	cl.box(wc + Vector3(-0.24, 0.0, -0.3), wc + Vector3(0.24, 0.42, 0.34))
	# ---- the basin on the west wall, its two taps; the mirror over it, a glass shelf, the lamp
	var bs: Vector3 = L.BASIN
	pk.rbox("enamel", bs + Vector3(0.0, -0.1, -0.3), bs + Vector3(0.46, 0.02, 0.3), 0.04, 3, ENAMEL)
	k.box("dark", bs + Vector3(0.09, 0.016, -0.23), bs + Vector3(0.4, 0.022, 0.23), Color(2.4, 2.4, 2.2))
	k.tube("enamel", PackedVector3Array([Vector3(bs.x + 0.2, 0.0, bs.z), Vector3(bs.x + 0.2, bs.y - 0.1, bs.z)]), 0.07, 12, ENAMEL, 1.0, false,
		func(i: int, _a: float) -> float: return 1.25 if i == 0 else 0.9)
	pk.box("enamel", bs + Vector3(0.0, 0.02, -0.3), bs + Vector3(0.05, 0.16, 0.3), ENAMEL)
	var taps := []
	for hz in [-0.13, 0.13]:
		var tp := bs + Vector3(0.07, 0.02, hz)
		k.tube("brass", PackedVector3Array([tp, tp + Vector3(0, 0.09, 0), tp + Vector3(0.05, 0.12, 0), tp + Vector3(0.11, 0.09, 0)]), 0.012, 8, W)
		k.tube("brass", PackedVector3Array([tp + Vector3(-0.03, 0.13, 0), tp + Vector3(0.03, 0.13, 0)]), 0.007, 6, W)
		k.tube("brass", PackedVector3Array([tp + Vector3(0, 0.13, -0.03), tp + Vector3(0, 0.13, 0.03)]), 0.007, 6, W)
		k.sphere("enamel", tp + Vector3(0, 0.14, 0), 0.012, 8, 6, Color(0.6, 0.08, 0.06) if hz < 0.0 else Color(0.1, 0.2, 0.6))
		taps.append(tp + Vector3(0.02, 0.1, 0))
	fx["tap_hot"] = taps[0]
	fx["tap_cold"] = taps[1]
	cl.box(bs + Vector3(0.0, -bs.y, -0.3), bs + Vector3(0.46, 0.05, 0.3))
	# water running from a tap (shown while it runs): one thin stream each, own regions
	for st in [["et_stream_hot", taps[0]], ["et_stream_cold", taps[1]]]:
		var tpp: Vector3 = st[1]
		c.kit(String(st[0])).tube("jar", PackedVector3Array([tpp + Vector3(0.09, -0.012, 0), tpp + Vector3(0.09, -0.1, 0)]), 0.0045, 6, Color(0.62, 0.7, 0.7))
	var mr: Vector3 = L.MIRROR
	var ms: Vector2 = L.MIRROR_SIZE
	Shell.board(k, "mirror", mr + Vector3(0.016, 0, 0), Vector3.RIGHT, ms.x, ms.y, 0.012)
	Shell.board(k, "panel", mr + Vector3(0.009, 0, 0), Vector3.RIGHT, ms.x + 0.1, ms.y + 0.1, 0.018, Color(0.7, 0.7, 0.7))
	# the steam on the glass and the digit a finger drew in it: own region, shown by etage.gd as the mist comes
	var mk = c.kit("et_mirror_fx")
	Shell.sign_quad(mk, "fog_mirror", mr + Vector3(0.0185, 0, 0), Vector3.RIGHT, ms.x, ms.y)
	Shell.sign_quad(mk, "digit_fog", mr + Vector3(0.0195, 0.04, 0.0), Vector3.RIGHT, 0.34, 0.34)
	pk.box("enamel", Vector3(x0, 1.04, mr.z - 0.3), Vector3(x0 + 0.12, 1.055, mr.z + 0.3), Color(0.8, 0.86, 0.84))
	k.tube("jar", PackedVector3Array([Vector3(x0 + 0.06, 1.055, mr.z - 0.2), Vector3(x0 + 0.06, 1.15, mr.z - 0.2)]), 0.03, 10, Color(0.5, 0.56, 0.54), 1.0, true)
	k.tube("wood", PackedVector3Array([Vector3(x0 + 0.06, 1.06, mr.z - 0.2), Vector3(x0 + 0.075, 1.22, mr.z - 0.215)]), 0.004, 5, Color(0.6, 0.2, 0.2))
	var bn := Vector3(x0 + 0.062, 1.057, mr.z + 0.14)
	k.quad("debris_paper", bn + Vector3(-0.05, 0, 0.08), bn + Vector3(0.05, 0, 0.08), bn + Vector3(0.05, 0, -0.08), bn + Vector3(-0.05, 0, -0.08), Vector3.UP,
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.8, 0.78, 0.66))
	fx["bain_note"] = bn
	var lp := mr + Vector3(0.0, ms.y * 0.5 + 0.2, 0.0)
	k.box("brass", lp + Vector3(0.0, -0.05, -0.05), lp + Vector3(0.012, 0.05, 0.05), W)
	k.tube("brass", PackedVector3Array([lp, lp + Vector3(0.1, 0.0, 0.0), lp + Vector3(0.12, 0.03, 0.0)]), 0.008, 6, W)
	var lem := _glow(c, reg, "et_bain_lamp", "night_glow", func(gk) -> void: gk.sphere("glow", lp + Vector3(0.12, 0.09, 0), 0.07, 12, 8, W, Vector3(1.0, 1.1, 1.0)))
	lem.emission = Color(0.9, 1.0, 0.72)
	lem.albedo_color = Color(0.7, 0.72, 0.64)
	var bl := OmniLight3D.new()
	bl.name = "BainLamp"
	bl.position = lp + Vector3(0.42, 0.02, 0.0)
	bl.light_color = Color(0.86, 1.0, 0.7)
	bl.light_energy = 1.0
	bl.omni_range = 5.5
	bl.omni_attenuation = 1.2
	bl.shadow_enabled = true
	bl.shadow_bias = 0.05
	bl.shadow_normal_bias = 1.2
	bl.light_cull_mask = MASK
	c.region("et_lights").add_child(bl)
	fx["bain_lamp"] = {"light": bl, "emit": lem, "energy": 1.0}
	# ---- the water heater on the north wall: its tank, its pipes, the pilot lamp on its front
	var ht: Vector3 = L.HEATER
	k.tube("enamel", PackedVector3Array([ht + Vector3(0, -0.4, 0), ht + Vector3(0, -0.34, 0), ht + Vector3(0, 0.34, 0), ht + Vector3(0, 0.4, 0)]), 0.2, 16, ENAMEL, 1.0, true,
		func(i: int, _a: float) -> float: return 0.86 if i == 0 or i == 3 else 1.0)
	for sy in [-0.24, 0.24]:
		k.box("steel_up", ht + Vector3(-0.22, sy - 0.015, -0.23), ht + Vector3(0.22, sy + 0.015, -0.2), Color(0.3, 0.3, 0.3))
	k.tube("brass", PackedVector3Array([ht + Vector3(-0.1, -0.4, 0), Vector3(ht.x - 0.1, 0.95, ht.z), Vector3(ht.x - 0.1, 0.95, z0 + 0.05), Vector3(x0 + 0.05, 0.95, z0 + 0.05), Vector3(x0 + 0.05, 0.95, bs.z - 0.13), Vector3(x0 + 0.05, bs.y, bs.z - 0.13)]), 0.011, 6, W)
	k.tube("brass", PackedVector3Array([ht + Vector3(0.1, -0.4, 0), Vector3(ht.x + 0.1, 0.3, ht.z), Vector3(ht.x + 0.1, 0.3, z0 + 0.05)]), 0.011, 6, W)
	k.box("enamel", ht + Vector3(-0.07, -0.2, 0.19), ht + Vector3(0.07, -0.08, 0.21), Color(0.3, 0.3, 0.32))
	var pem := _glow(c, reg, "et_heater_pilot", "pilot_glow", func(gk) -> void: gk.sphere("glow", ht + Vector3(0.0, -0.14, 0.212), 0.012, 8, 6, W))
	fx["pilot"] = pem
	fx["heater"] = ht
	# ---- the east wall: a towel on its rail, the laundry basket; a mat before the bath, a stool
	k.tube("brass", PackedVector3Array([Vector3(x1 - 0.01, 1.2, 2.25), Vector3(x1 - 0.07, 1.2, 2.25), Vector3(x1 - 0.07, 1.2, 2.95), Vector3(x1 - 0.01, 1.2, 2.95)]), 0.009, 6, W)
	pk.rbox("fabric", Vector3(x1 - 0.1, 0.72, 2.36), Vector3(x1 - 0.045, 1.215, 2.72), 0.014, 2, Color(0.6, 0.58, 0.5))
	k.tube("wood", PackedVector3Array([Vector3(x1 - 0.3, 0.0, 3.2), Vector3(x1 - 0.3, 0.5, 3.2)]), 0.2, 14, Color(0.56, 0.44, 0.28), 1.0, true,
		func(i: int, _a: float) -> float: return 0.86 if i == 0 else 1.0)
	k.sphere("sheet", Vector3(x1 - 0.3, 0.5, 3.2), 0.17, 12, 6, Color(0.9, 0.9, 0.86), Vector3(1.0, 0.5, 1.0))
	cl.box(Vector3(x1 - 0.5, 0.0, 3.0), Vector3(x1, 0.52, 3.4))
	k.box("carpet", Vector3(52.9, 0.0, 2.72), Vector3(53.8, 0.014, 3.3), Color(0.5, 0.6, 0.52), 1.0, Kit.FACE_PY | Kit.FACE_NZ | Kit.FACE_PX | Kit.FACE_NX)
	# steam over the basin while the hot water runs
	fx["steam"] = _steam(c, bs + Vector3(0.24, 0.1, -0.1))
	fx["mirror_at"] = mr

## Steam rising from the basin (not emitting until the hot tap has run a while).
static func _steam(c, at: Vector3) -> GPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = c.mats.tex("steam_puff.png")
	m.albedo_color = Color(0.8, 0.86, 0.82, 0.13)
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	quad.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.02, 0.16)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, 0.03, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	var e := GPUParticles3D.new()
	e.name = "Steam"
	e.amount = 28
	e.lifetime = 5.0
	e.randomness = 0.5
	e.process_material = pm
	e.draw_pass_1 = quad
	e.position = at
	e.emitting = false
	e.visibility_aabb = AABB(Vector3(-0.6, -0.2, -0.6), Vector3(1.2, 1.8, 1.2))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	c.region("et_lights").add_child(e)
	return e

# ====================================================================== la cage d'escalier

static func _escalier(c) -> void:
	var R: Dictionary = L.ESCALIER
	var reg := "et_esc"
	var k = c.kit(reg)
	var cl = c.col(reg)
	var cs = c.col_see(reg)
	var x0: float = R.x0
	var x1: float = R.x1
	var z0: float = R.z0
	var z1: float = R.z1
	var ch: float = R.ceil
	var fx: Dictionary = c.room_fx
	var S: Dictionary = L.STAIR
	var sx0: float = S.x0
	var zf: float = S.z_foot
	var run: float = S.run
	var rise: float = S.rise
	var n: int = S.steps
	var ly: float = L.LANDING_Y
	var vt: float = L.VOID_TOP
	var zl := zf - run * float(n)               # where the landing begins
	var wn: Array = L.WIN_ESCALIER
	var dark := Color(0.86, 0.86, 0.86)
	k.box("floorboards", Vector3(x0, -0.2, z0), Vector3(x1, 0.0, z1), W, 1.0, Kit.FACE_PY)
	# ceilings: over the foot of the stairs and the passage beside them; lower under the upper landing
	k.box("plaster", Vector3(x0, ch, zf), Vector3(x1, ch + 0.2, z1), W, 1.0, Kit.FACE_NY)
	k.box("plaster", Vector3(x0, ch, zl), Vector3(sx0, ch + 0.2, zf), W, 1.0, Kit.FACE_NY)
	k.box("plaster", Vector3(x0, ly - 0.2, z0), Vector3(sx0, ly, zl), W, 1.0, Kit.FACE_NY | Kit.FACE_PY)
	k.box("wallpaper_house", Vector3(x0, ly - 0.2, zl - 0.02), Vector3(sx0 - 0.02, ly, zl), W)
	cl.box(Vector3(x0, ch, zf), Vector3(x1, ch + 0.2, z1))
	cl.box(Vector3(x0, ch, zl), Vector3(sx0, ch + 0.2, zf))
	cl.box(Vector3(x0, ly - 0.2, z0), Vector3(sx0, ch + 0.2, zl))
	# east and north walls, all the way up the stair void; the void's own walls above the ceilings
	Shell.wall(c, reg, "wallpaper_house", Vector2(x1 + 0.05, z0 - 0.1), Vector2(x1 + 0.05, z1), 0.1, 0.0, vt + 0.2)
	Shell.wall(c, reg, "wallpaper_house", Vector2(x0, z0 - 0.05), Vector2(x1 + 0.1, z0 - 0.05), 0.1, 0.0, vt + 0.2,
		[[float(wn[0]) - x0, float(wn[1]) - x0, float(wn[2]), float(wn[3])]])
	k.box("wallpaper_house", Vector3(sx0 - 0.1, ch, zl), Vector3(sx0, vt + 0.2, zf), W)
	k.box("wallpaper_house", Vector3(sx0 - 0.1, ch, zf), Vector3(x1, vt + 0.2, zf + 0.1), W)
	k.box("plaster", Vector3(x0, vt, z0), Vector3(x1, vt + 0.2, zf), W, 1.0, Kit.FACE_NY)
	# the upper landing goes on west into the dark: a short passage nobody uses any more
	k.box("wallpaper_house", Vector3(x0, ly, zl - 0.02), Vector3(sx0 - 0.1, vt + 0.2, zl), W)
	k.box("dark", Vector3(x0, ly, z0), Vector3(x0 + 0.02, vt, zl), W)
	k.box("wallpaper_house", Vector3(sx0 - 0.1, ly + 2.05, z0), Vector3(sx0, vt + 0.2, zl), W)
	k.box("panel", Vector3(sx0 - 0.12, ly, zl - 0.07), Vector3(sx0 + 0.02, ly + 2.05, zl + 0.02), W)
	k.box("panel", Vector3(sx0 - 0.12, ly + 2.0, z0), Vector3(sx0 + 0.02, ly + 2.12, zl + 0.04), W)
	# ---- the flight: twelve steps along the east wall, then the landing
	for i in n:
		var za := zf - run * float(i + 1)
		var zb := zf - run * float(i)
		var y1 := rise * float(i + 1)
		k.box("panel", Vector3(sx0, 0.0, za), Vector3(x1, y1 - 0.03, zb), dark)
		k.box("floorboards", Vector3(sx0 - 0.015, y1 - 0.03, za), Vector3(x1, y1, zb + 0.025), W)
		cl.box(Vector3(sx0, 0.0, za), Vector3(x1, y1, zb))
	k.box("panel", Vector3(sx0, 0.0, z0), Vector3(x1, ly - 0.03, zl), dark)
	k.box("floorboards", Vector3(sx0 - 0.015, ly - 0.03, z0), Vector3(x1, ly, zl), W)
	cl.box(Vector3(sx0, 0.0, z0), Vector3(x1, ly, zl))
	# the string along the open side, the newel posts, the handrail, a baluster on every step
	var ang := atan2(rise, run)
	var slope := sqrt(run * run + rise * rise) * float(n)
	var sxf := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(sx0 - 0.04, 0.0, zf))
	k.box("panel", Vector3(0.0, -0.06, -slope), Vector3(0.045, 0.24, 0.0), W, 1.0, Kit.ALL, sxf)
	for nw in [[zf + 0.02, 0.0, 1.16], [zl, ly, 1.1]]:
		var nz: float = nw[0]
		var ny: float = nw[1]
		k.box("panel", Vector3(sx0 - 0.09, 0.0, nz - 0.05), Vector3(sx0 + 0.01, ny + float(nw[2]), nz + 0.05), W)
		k.sphere("panel", Vector3(sx0 - 0.04, ny + float(nw[2]) + 0.05, nz), 0.06, 12, 8, W)
	var rail := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(sx0 - 0.065, 0.98, zf))
	k.box("panel", Vector3(0.0, 0.0, -slope), Vector3(0.05, 0.06, 0.0), Color(0.9, 0.9, 0.9), 1.0, Kit.ALL, rail)
	for i in n:
		var bz := zf - run * (float(i) + 0.5)
		var by := rise * float(i + 1)
		k.box("panel", Vector3(sx0 - 0.052, by, bz - 0.014), Vector3(sx0 - 0.024, by + 0.98 - rise * 0.5, bz + 0.014), dark)
	# nobody walks on to the stairs: from the side (see-through) nor from the foot (the boards)
	cs.box(Vector3(sx0 - 0.07, 0.0, zl), Vector3(sx0, ch, zf))
	cs.box(Vector3(sx0 - 0.07, 0.0, zf), Vector3(x1, ch, zf + 0.07))
	# ---- boards nailed across the foot of the stairs, on a stud; one of them is loose (own regions: up / fallen)
	k.box("wood", Vector3(sx0 - 0.07, 0.0, zf + 0.03), Vector3(sx0, ch, zf + 0.08), Color(0.5, 0.42, 0.32))
	var plank := Color(0.46, 0.4, 0.32)
	var pl := x1 - sx0 + 0.06
	var boards := [[0.4, 0.03, 0.15], [1.36, -0.07, 0.16], [1.84, 0.02, 0.13], [0.95, 0.5, 0.14]]
	for bd in boards:
		var bxf := Transform3D(Basis(Vector3.BACK, float(bd[1])), Vector3((sx0 + x1) * 0.5 - 0.03, float(bd[0]), zf + 0.1))
		var ln := pl / cos(float(bd[1])) * (1.0 if absf(float(bd[1])) < 0.3 else 0.93)
		k.box("wood", Vector3(-ln * 0.5, -float(bd[2]) * 0.5, -0.012), Vector3(ln * 0.5, float(bd[2]) * 0.5, 0.012), plank.darkened(0.1 * absf(float(bd[1])) * 4.0), 1.0, Kit.ALL, bxf)
		for ex in [-ln * 0.5 + 0.05, ln * 0.5 - 0.05]:
			for ey in [-0.03, 0.03]:
				k.disc("metal", bxf * Vector3(ex, ey, 0.013), Vector3.BACK, Vector3.RIGHT, 0.006, 6, Color(0.12, 0.12, 0.12))
	var pu = c.kit("et_plank_up")
	var uxf := Transform3D(Basis(Vector3.BACK, -0.04), Vector3((sx0 + x1) * 0.5 - 0.03, 0.88, zf + 0.125))
	pu.box("wood", Vector3(-pl * 0.5, -0.07, -0.012), Vector3(pl * 0.5, 0.07, 0.012), plank.lightened(0.05), 1.0, Kit.ALL, uxf)
	var pd = c.kit("et_plank_down")
	var dxf := Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(67.25, 0.014, zf + 0.62))
	pd.box("wood", Vector3(-pl * 0.5, -0.07, -0.012), Vector3(pl * 0.5, 0.07, 0.012), plank.lightened(0.05), 1.0, Kit.ALL, dxf)
	for ex in [-pl * 0.5 + 0.05, pl * 0.5 - 0.05]:
		pd.tube("metal", PackedVector3Array([dxf * Vector3(ex, 0.0, -0.012), dxf * Vector3(ex + 0.01, 0.0, -0.06)]), 0.0025, 4, Color(0.2, 0.2, 0.2))
	# a notice pinned to the boards
	var np := Vector3(sx0 + 0.36, 1.36, zf + 0.115)
	Shell.sign_quad(k, "debris_paper", np + Vector3(0, 0, 0.012), Vector3.BACK, 0.17, 0.22, Rect2(0, 0, 1, 1), Color(0.6, 0.56, 0.44))
	k.sphere("metal", np + Vector3(0, 0.09, 0.014), 0.006, 6, 4, Color(0.3, 0.3, 0.3))
	fx["stair_note"] = np + Vector3(0, 0, 0.012)
	# ---- the window above the landing, the moon coming down the stairs through it
	_window_frame(c, k, float(wn[0]), float(wn[1]), float(wn[2]), float(wn[3]), z0 - 0.05, 0.1, -1.0, "night_sky")
	var wc := Vector3((float(wn[0]) + float(wn[1])) * 0.5, (float(wn[2]) + float(wn[3])) * 0.5, z0 - 0.05)
	var target := Vector3(wc.x, 0.1, zf + 0.5)
	var moon := SpotLight3D.new()
	moon.name = "MoonStairs"
	moon.position = wc - (target - wc) * 0.95
	moon.light_color = MOON
	moon.light_energy = 9.0
	moon.spot_range = 15.0
	moon.spot_angle = 10.0
	moon.spot_angle_attenuation = 0.4
	moon.spot_attenuation = 0.2
	moon.light_specular = 0.4
	moon.shadow_enabled = true
	moon.shadow_bias = 0.05
	moon.shadow_normal_bias = 1.5
	moon.shadow_blur = 1.2
	moon.light_cull_mask = MASK
	moon.light_volumetric_fog_energy = 1.0
	moon.basis = Basis.looking_at(target - moon.position, Vector3.UP)
	c.region("et_lights").add_child(moon)
	c.room_fx["moon"].append(moon)
	_fill(c, "StairsBounce", Vector3(wc.x, 1.3, zf - 1.2), MOON.lerp(Color(0.5, 0.42, 0.34), 0.35), 0.22, 4.6)
	_fill(c, "StairsFoot", Vector3(66.6, 0.5, zf + 0.6), MOON.lerp(Color(0.5, 0.42, 0.34), 0.35), 0.1, 3.6)
	Build._motes(c, Vector3(wc.x, 2.6, zf - 1.9), Vector3(0.35, 1.0, 1.4))
	# ---- the door from the hallway (own region, around its hinge at the east jamb, opening into the stairwell)
	var de: Dictionary = L.DOOR_ESCALIER
	Build._leaf(c.kit("et_door_esc"), float(de.x1) - float(de.x0) - 0.04, float(de.h), Color(0.75, 0.75, 0.75))
	fx["esc_hinge"] = Vector3(float(de.x1) - 0.02, 0.0, z1 - 0.02)
	# ---- the fuse board on the west wall: a slate on a wooden back, five porcelain plugs (one missing), the knife
	# switch, the conduit going up; its card beside it
	var fbp: Vector3 = L.FUSE_BOARD
	k.box("panel", fbp + Vector3(0.0, -0.32, -0.3), fbp + Vector3(0.025, 0.32, 0.3), W)
	k.box("dark", fbp + Vector3(0.025, -0.27, -0.25), fbp + Vector3(0.04, 0.27, 0.25), Color(2.2, 2.2, 2.4))
	var sockets := []
	for i in 5:
		var fzp := fbp.z + 0.18 - 0.09 * float(i)
		var sp := Vector3(fbp.x + 0.04, fbp.y + 0.12, fzp)
		k.tube("enamel", PackedVector3Array([sp, sp + Vector3(0.02, 0, 0)]), 0.03, 12, Color(0.84, 0.82, 0.74), 1.0, true)
		if i < 4:
			_fuse(k, sp + Vector3(0.02, 0, 0), Vector3.RIGHT)
		else:
			k.disc("dark", sp + Vector3(0.0205, 0, 0), Vector3.RIGHT, Vector3.UP, 0.018, 10, W)
		sockets.append(sp)
		k.tube("rubber", PackedVector3Array([sp + Vector3(0.0, -0.03, 0), sp + Vector3(0.005, -0.18, 0.0), Vector3(fbp.x + 0.045, fbp.y - 0.2, fbp.z + (fzp - fbp.z) * 0.4)]), 0.004, 5, Color(0.12, 0.1, 0.08))
	_fuse(c.kit("et_fuse_in"), Vector3.ZERO, Vector3.RIGHT)
	fx["fuse_socket"] = (sockets[4] as Vector3) + Vector3(0.02, 0, 0)
	k.box("brass", fbp + Vector3(0.04, -0.2, -0.05), fbp + Vector3(0.055, -0.1, 0.05), W)
	k.box("brass", Vector3(-0.006, 0.0, -0.008), Vector3(0.006, 0.16, 0.008), W, 1.0, Kit.ALL, Transform3D(Basis(Vector3.BACK, -0.9), fbp + Vector3(0.055, -0.15, 0.0)))
	k.sphere("dark", fbp + Vector3(0.185, -0.05, 0.0), 0.02, 8, 6, Color(1.6, 1.6, 1.6))
	k.tube("steel_up", PackedVector3Array([fbp + Vector3(0.02, 0.32, 0.12), Vector3(fbp.x + 0.02, ch, fbp.z + 0.12)]), 0.012, 6, Color(0.2, 0.2, 0.2))
	Shell.sign_quad(k, LABELS, fbp + Vector3(0.004, 0.02, 0.48), Vector3.RIGHT, 0.24, 0.24, Rect2(0.0, 0.0, 0.5, 0.5))
	# pegs by the door: her coat, a scarf; a trunk and a hat box under the landing
	k.box("panel", Vector3(x0, 1.62, -2.5), Vector3(x0 + 0.02, 1.7, -1.5), W)
	for pz in [-2.35, -2.05, -1.75]:
		k.tube("brass", PackedVector3Array([Vector3(x0 + 0.02, 1.66, pz), Vector3(x0 + 0.09, 1.69, pz)]), 0.008, 6, W)
	var coat := Color(0.08, 0.075, 0.07)
	k.rbox("fabric", Vector3(x0 + 0.03, 0.62, -2.55), Vector3(x0 + 0.16, 1.66, -2.15), 0.05, 2, coat)
	k.rbox("fabric", Vector3(x0 + 0.03, 0.9, -2.63), Vector3(x0 + 0.12, 1.58, -2.52), 0.04, 2, coat)
	k.rbox("fabric", Vector3(x0 + 0.03, 0.9, -2.18), Vector3(x0 + 0.12, 1.58, -2.07), 0.04, 2, coat)
	k.rbox("fabric", Vector3(x0 + 0.03, 1.0, -1.8), Vector3(x0 + 0.09, 1.68, -1.7), 0.03, 2, Color(0.3, 0.12, 0.14))
	k.rbox("panel", Vector3(x0 + 0.08, 0.0, z0 + 0.08), Vector3(x0 + 0.98, 0.46, z0 + 0.62), 0.03, 2, Color(0.7, 0.7, 0.7))
	for bz in [z0 + 0.2, z0 + 0.5]:
		k.box("brass", Vector3(x0 + 0.07, 0.0, bz - 0.02), Vector3(x0 + 0.99, 0.47, bz + 0.02), Color(0.5, 0.5, 0.5))
	k.tube("fabric", PackedVector3Array([Vector3(x0 + 0.42, 0.46, z0 + 0.34), Vector3(x0 + 0.42, 0.66, z0 + 0.34)]), 0.19, 16, Color(0.3, 0.16, 0.16), 1.0, true)
	cl.box(Vector3(x0, 0.0, z0), Vector3(x0 + 1.0, 0.7, z0 + 0.66))
	fx["stair_top"] = Vector3((sx0 + x1) * 0.5, ly, (z0 + zl) * 0.5)

# ====================================================================== the box on the salon's mantel

static func _coffret(c) -> void:
	var fx: Dictionary = c.room_fx
	var at: Vector3 = fx.key_pos
	at.y = 1.15
	var k = c.kit("et_props")
	var wood := Color(0.9, 0.9, 0.9)
	# walls and bottom (the inside is lined dark), three brass wheels and a hasp on the front (west)
	k.box("panel", at + Vector3(-0.07, 0.0, -0.12), at + Vector3(0.07, 0.012, 0.12), wood)
	for sd in [[Vector3(-0.07, 0.0, -0.12), Vector3(-0.058, 0.075, 0.12)], [Vector3(0.058, 0.0, -0.12), Vector3(0.07, 0.075, 0.12)],
			[Vector3(-0.07, 0.0, -0.12), Vector3(0.07, 0.075, -0.108)], [Vector3(-0.07, 0.0, 0.108), Vector3(0.07, 0.075, 0.12)]]:
		k.box("panel", at + (sd[0] as Vector3), at + (sd[1] as Vector3), wood)
	k.box("fabric", at + Vector3(-0.058, 0.012, -0.108), at + Vector3(0.058, 0.016, 0.108), Color(0.2, 0.04, 0.05))
	for j in 3:
		var wz := -0.045 + 0.045 * float(j)
		k.tube("brass", PackedVector3Array([at + Vector3(-0.07, 0.04, wz - 0.012), at + Vector3(-0.07, 0.04, wz + 0.012)]), 0.016, 12, Color(1.0, 0.95, 0.8), 1.0, true)
	k.box("brass", at + Vector3(-0.074, 0.02, -0.075), at + Vector3(-0.07, 0.06, 0.075), Color(0.8, 0.76, 0.6))
	for cz in [-0.118, 0.106]:
		k.box("brass", at + Vector3(-0.071, 0.0, cz), at + Vector3(0.071, 0.076, cz + 0.012), Color(0.8, 0.76, 0.6))
	# the lid, around its hinge along the back edge (it opens toward the wall)
	var lk = c.kit("et_box_lid")
	lk.box("panel", Vector3(-0.142, 0.0, -0.122), Vector3(0.0, 0.022, 0.122), wood)
	lk.box("brass", Vector3(-0.146, 0.004, -0.02), Vector3(-0.142, 0.018, 0.02), Color(0.8, 0.76, 0.6))
	lk.box("fabric", Vector3(-0.13, -0.002, -0.108), Vector3(-0.012, 0.0, 0.108), Color(0.2, 0.04, 0.05))
	fx["box_at"] = at
	fx["box_hinge"] = at + Vector3(0.071, 0.076, 0.0)
	fx["key_pos"] = at + Vector3(0.0, 0.022, 0.0)
	# a card slipped under it
	var cd := at + Vector3(-0.02, 0.002, -0.24)
	var cb := Basis(Vector3.UP, 0.25)
	k.quad("debris_paper", cd + cb * Vector3(-0.05, 0, 0.075), cd + cb * Vector3(0.05, 0, 0.075), cd + cb * Vector3(0.05, 0, -0.075), cd + cb * Vector3(-0.05, 0, -0.075),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.88, 0.84, 0.7))
	fx["card"] = cd

# ====================================================================== the figures, the last layer

static func _finish(c) -> void:
	var m: int = L.L_ET
	var fx: Dictionary = c.room_fx
	seated_figure(c.kit("et_seated"), 23, Color(0.97, 0.96, 0.94))
	Build.sheet_figure(c.kit("et_bathfig"), float(L.BATH_FIGURE[1]), 71, Color(0.86, 0.9, 0.86))
	Build.sheet_figure(c.kit("et_stairfig"), float(L.STAIR_FIGURE[1]), 37, Color(0.95, 0.95, 0.95))
	var Q: Dictionary = L.CUISINE
	var P: Dictionary = L.CELLIER
	var B: Dictionary = L.BAIN
	var E: Dictionary = L.ESCALIER
	fx["probes2"] = {
		"cuisine": Shell.probe(c, "et_lights", "ProbeCuisine", Vector3(float(Q.x0), 0.0, float(Q.z0)), Vector3(float(Q.x1), float(Q.ceil), float(Q.z1)), Vector3(61.4, 1.4, 2.0), 0.7),
		"cellier": Shell.probe(c, "et_lights", "ProbeCellier", Vector3(float(P.x0), 0.0, float(P.z0)), Vector3(float(P.x1), float(P.ceil), float(P.z1)), Vector3(57.3, 1.3, 3.7), 0.7),
		"bain": Shell.probe(c, "et_lights", "ProbeBain", Vector3(float(B.x0), 0.0, float(B.z0)), Vector3(float(B.x1), float(B.ceil), float(B.z1)), Vector3(54.4, 1.4, 2.3), 0.9),
		"escalier": Shell.probe(c, "et_lights", "ProbeEscalier", Vector3(float(E.x0), 0.0, float(E.z0)), Vector3(float(E.x1), float(E.ceil), float(E.z1)), Vector3(66.5, 1.4, -1.9), 0.8),
	}
	# haze where the moon comes down the stairs
	var fog := FogVolume.new()
	fog.name = "HazeStairs"
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = Vector3(1.3, 5.0, 4.4)
	fog.position = Vector3(67.45, 2.5, -4.0)
	var fm := FogMaterial.new()
	fm.density = 0.03
	fm.albedo = Color(0.74, 0.78, 0.86)
	fm.edge_fade = 0.4
	fog.material = fm
	c.region("et_lights").add_child(fog)
	# stains and dirt
	var brown := Color(0.2, 0.15, 0.09, 0.75)
	var dirt := Color(0.07, 0.06, 0.05, 0.75)
	var damp := Color(0.1, 0.14, 0.1, 0.7)
	var soot := Color(0.16, 0.12, 0.07, 0.4)
	for d in [[Vector3(float(Q.x1) - 0.01, 1.9, 2.6), Vector3.LEFT, 1.4, 1.4, soot], [Vector3(59.3, 1.95, float(Q.z0) + 0.02), Vector3.BACK, 1.2, 1.3, soot],
			[Vector3(float(Q.x0) + 0.01, 1.95, 4.7), Vector3.RIGHT, 1.0, 1.2, soot], [Vector3(62.5, 1.9, float(Q.z1) - 0.01), Vector3.FORWARD, 1.2, 1.3, Color(0.12, 0.1, 0.08, 0.5)],
			[Vector3(float(B.x0) + 0.01, 1.8, 3.0), Vector3.RIGHT, 1.2, 1.6, damp], [Vector3(54.9, 1.9, float(B.z1) - 0.01), Vector3.FORWARD, 1.3, 1.5, damp],
			[Vector3(float(B.x1) - 0.01, 1.7, 1.7), Vector3.LEFT, 1.0, 1.5, damp], [Vector3(53.4, 1.0, float(B.z0) + 0.02), Vector3.BACK, 1.2, 1.6, damp],
			[Vector3(float(P.x1) - 0.01, 1.5, 2.8), Vector3.LEFT, 1.0, 1.6, brown], [Vector3(57.0, 1.6, float(P.z0) + 0.01), Vector3.BACK, 1.4, 1.4, brown],
			[Vector3(float(E.x1) - 0.01, 3.2, -4.2), Vector3.LEFT, 1.8, 2.2, brown], [Vector3(float(E.x0) + 0.01, 1.9, -3.2), Vector3.RIGHT, 1.2, 1.3, brown],
			[Vector3(66.4, 1.9, float(E.z1) - 0.01), Vector3.FORWARD, 1.0, 1.2, brown]]:
		Shell.decal(c, "et_decals", "decal_water.png", d[0], d[1], Vector2(float(d[2]), float(d[3])), m, d[4])
	for d in [[Vector3(60.4, float(Q.ceil), 2.7), 2.0], [Vector3(62.6, float(Q.ceil), 3.4), 1.5], [Vector3(53.3, float(B.ceil), 3.6), 1.8], [Vector3(54.8, float(B.ceil), 1.9), 1.3],
			[Vector3(57.1, float(P.ceil), 4.2), 1.4], [Vector3(66.3, float(E.ceil), -3.6), 1.3]]:
		Shell.decal(c, "et_decals", "decal_spill.png", d[0], Vector3.DOWN, Vector2(float(d[1]), float(d[1])), m, Color(0.3, 0.22, 0.12, 0.6), float(d[1]) * 2.0)
	for d in [[Vector3(60.6, 0.0, float(Q.z1) - 0.85), 2.6, 0.0], [Vector3(float(Q.x1) - 0.9, 0.0, 2.6), 1.6, 1.57], [Vector3(59.0, 0.0, float(Q.z0) + 0.3), 1.6, 0.0],
			[Vector3(53.6, 0.0, 3.1), 2.0, 0.0], [Vector3(55.4, 0.0, 2.4), 1.6, 1.57], [Vector3(57.2, 0.0, 4.5), 1.6, 0.0], [Vector3(66.2, 0.0, -4.4), 2.4, 1.57],
			[Vector3(67.3, 0.0, -1.3), 1.4, 0.0]]:
		Shell.decal(c, "et_decals", "decal_grime.png", d[0], Vector3.UP, Vector2(float(d[1]), 0.7), m, dirt, float(d[2]))
	# spilled on the kitchen floor before the stove, gone dark; water standing under the basin
	Shell.decal(c, "et_decals", "decal_spill.png", Vector3(62.2, 0.0, 3.5), Vector3.UP, Vector2(1.0, 0.9), m, Color(0.12, 0.07, 0.04, 0.7), 0.6)
	Shell.decal(c, "et_decals", "decal_spill.png", Vector3(53.0, 0.0, 2.2), Vector3.UP, Vector2(0.9, 0.8), m, Color(0.05, 0.06, 0.055, 0.6), 1.2)
	# what the dresser's feet scraped on the lino, long ago, when it was pushed there
	Shell.decal(c, "et_decals", "decal_scuffs.png", Vector3(58.9, 0.0, 3.7), Vector3.UP, Vector2(0.9, 1.3), m, Color(0.06, 0.05, 0.04, 0.6), 0.1)
	# scratches inside the pantry: on the door, low on the wall beside it
	Shell.decal(c, "et_decals", "decal_scuffs.png", Vector3(float(P.x1) - 0.01, 0.9, 3.7), Vector3.LEFT, Vector2(0.8, 1.3), m, Color(0.03, 0.025, 0.02, 0.85))
	Shell.decal(c, "et_decals", "decal_scuffs.png", Vector3(float(P.x1) - 0.01, 0.6, 2.85), Vector3.LEFT, Vector2(0.7, 0.9), m, Color(0.03, 0.025, 0.02, 0.7))
	# wet footprints from the bath to the door (shown by etage.gd once the mirror has been read)
	fx["bain_prints"] = [
		Shell.decal(c, "et_decals", "decal_footprints.png", Vector3(53.9, 0.0, 2.9), Vector3.UP, Vector2(0.5, 0.95), m, Color(0.03, 0.04, 0.035, 0.6), -1.0),
		Shell.decal(c, "et_decals", "decal_footprints.png", Vector3(54.7, 0.0, 2.0), Vector3.UP, Vector2(0.5, 0.95), m, Color(0.03, 0.04, 0.035, 0.5), -0.6),
	]
	Shell.decal(c, "et_decals", "decal_footprints.png", Vector3(66.6, 0.0, -1.9), Vector3.UP, Vector2(0.55, 1.0), m, Color(0.5, 0.48, 0.44, 0.3), 2.4)
	# cobwebs
	var qc: float = Q.ceil
	var bc: float = B.ceil
	var pc: float = P.ceil
	var vt: float = L.VOID_TOP
	for w in [[Vector3(float(Q.x0) + 0.02, qc - 0.01, float(Q.z0) + 0.03), Vector3(1, 0, 1), 0.8], [Vector3(float(Q.x1) - 0.02, qc - 0.01, float(Q.z1) - 0.02), Vector3(-1, 0, -1), 0.9],
			[Vector3(float(Q.x1) - 0.02, qc - 0.01, float(Q.z0) + 0.03), Vector3(-1, 0, 1), 0.6], [Vector3(60.4, 1.86, 3.0), Vector3(1, 0, 0.2), 0.4],
			[Vector3(float(B.x0) + 0.02, bc - 0.01, float(B.z1) - 0.02), Vector3(1, 0, -1), 0.7], [Vector3(float(B.x1) - 0.02, bc - 0.01, float(B.z0) + 0.03), Vector3(-1, 0, 1), 0.6],
			[Vector3(float(P.x0) + 0.02, pc - 0.01, float(P.z0) + 0.02), Vector3(1, 0, 1), 0.7], [Vector3(float(P.x1) - 0.02, pc - 0.01, float(P.z1) - 0.02), Vector3(-1, 0, -1), 0.7],
			[Vector3(float(P.x0) + 0.36, 2.04, float(P.z1) - 0.04), Vector3(0, 0, -1), 0.5], [Vector3(float(E.x0) + 0.02, float(E.ceil) - 0.01, float(E.z1) - 0.02), Vector3(1, 0, -0.4), 0.7],
			[Vector3(float(E.x1) - 0.02, vt - 0.01, float(E.z0) + 0.02), Vector3(-1, 0, 0.3), 1.0], [Vector3(67.02, vt - 0.01, -2.42), Vector3(1, 0, -0.3), 0.9],
			[Vector3(67.0, 2.58, -2.36), Vector3(1, 0, 0), 0.5], [Vector3(float(E.x1) - 0.02, 1.9, -2.36), Vector3(-1, 0, 0), 0.45]]:
		Build._cobweb(c, w[0], w[1], float(w[2]))
