## Geometry of chapter 3, the yard (dehors_layout.gd): the ground and its mask, the house front and the porch, the
## fence and the tree line, the driveway and the dead car, the swing set, the sandbox, the playhouse, the kennel, the
## tool shed, the greenhouse, the root cellar, the gate. Built with the garderie's kit / build context. What moves at
## runtime gets a region of its own, authored around its pivot (door leaves around their hinge, swings around the
## top bar): dehors.gd places and drives those nodes. Things dehors.gd needs are left in c.room_fx (positions,
## lights, the rectangles she walks around).
extends RefCounted

const L := preload("res://scripts/dehors/dehors_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")
const U := preload("res://scripts/dehors/dehors_util.gd")
const Props := preload("res://scripts/dehors/dehors_props.gd")

const MASK := 1 | L.L_DH
const MOON := Color(0.56, 0.68, 1.0)
const GREY := Color(0.8, 0.8, 0.8)
const MASK_RECT := Rect2(98.0, -22.0, 56.0, 44.0)         # world rect (x, z) the ground mask covers

static func build(c) -> void:
	c.room_fx["solids"] = []
	c.room_fx["probes"] = []
	_ground(c)
	_house(c)
	_porch(c)
	_fence(c)
	_trees(c)
	Props.lawn(c)
	Props.garden(c)
	Props.car(c)
	Props.shed(c)
	Props.serre(c)
	_cave(c)
	_gate(c)
	_lights(c)
	_finish(c)

# ====================================================================== the ground

## Writes max(buf, f(x, z)) over the world rectangle x0..x1, z0..z1 of one channel of the ground mask.
static func _mask_put(buf: PackedByteArray, w: int, h: int, x0: float, z0: float, x1: float, z1: float, f: Callable) -> void:
	var px := MASK_RECT.size.x / float(w)
	var pz := MASK_RECT.size.y / float(h)
	var ia := clampi(int(floor((x0 - MASK_RECT.position.x) / px)), 0, w - 1)
	var ib := clampi(int(ceil((x1 - MASK_RECT.position.x) / px)), 0, w - 1)
	var ja := clampi(int(floor((z0 - MASK_RECT.position.y) / pz)), 0, h - 1)
	var jb := clampi(int(ceil((z1 - MASK_RECT.position.y) / pz)), 0, h - 1)
	for j in range(ja, jb + 1):
		var z := MASK_RECT.position.y + (float(j) + 0.5) * pz
		for i in range(ia, ib + 1):
			var x := MASK_RECT.position.x + (float(i) + 0.5) * px
			var v := int(clampf(float(f.call(x, z)), 0.0, 1.0) * 255.0)
			if v > buf[j * w + i]:
				buf[j * w + i] = v

static func _mask_circles(buf: PackedByteArray, w: int, h: int, list: Array, edge: float) -> void:
	for cc in list:
		var cx := float(cc[0])
		var cz := float(cc[1])
		var cr := float(cc[2])
		_mask_put(buf, w, h, cx - cr - edge, cz - cr - edge, cx + cr + edge, cz + cr + edge, func(x: float, z: float) -> float:
			return 0.5 + (cr - Vector2(x - cx, z - cz).length()) / (2.0 * edge))

## The mask the ground shader reads: R gravel, G dead leaves, B bare earth, A standing water. Soft edges; the
## shader breaks them up with noise.
static func _ground_mask() -> ImageTexture:
	var w := 448
	var h := 352
	var c0 := PackedByteArray()
	var c1 := PackedByteArray()
	var c2 := PackedByteArray()
	var c3 := PackedByteArray()
	c0.resize(w * h)
	c1.resize(w * h)
	c2.resize(w * h)
	c3.resize(w * h)
	var soft := 0.35
	for r in L.GRAVEL:
		var rr: Array = r
		_mask_put(c0, w, h, float(rr[0]) - soft, float(rr[1]) - soft, float(rr[2]) + soft, float(rr[3]) + soft, func(x: float, z: float) -> float:
			var d := minf(minf(x - float(rr[0]), float(rr[2]) - x), minf(z - float(rr[1]), float(rr[3]) - z))
			return 0.5 + d / (2.0 * soft))
	for i in L.PATH.size() - 1:
		var a: Vector2 = L.PATH[i]
		var b: Vector2 = L.PATH[i + 1]
		var hw: float = L.PATH_HALF
		_mask_put(c0, w, h, minf(a.x, b.x) - hw - soft, minf(a.y, b.y) - hw - soft, maxf(a.x, b.x) + hw + soft, maxf(a.y, b.y) + hw + soft,
			func(x: float, z: float) -> float: return 0.5 + (hw - L._seg_dist(Vector2(x, z), a, b)) / (2.0 * soft))
	_mask_circles(c1, w, h, L.LEAVES, 0.8)
	_mask_circles(c2, w, h, L.DIRT, 0.7)
	_mask_circles(c3, w, h, L.PUDDLES, 0.25)
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in w * h:
		data[i * 4] = c0[i]
		data[i * 4 + 1] = c1[i]
		data[i * 4 + 2] = c2[i]
		data[i * 4 + 3] = c3[i]
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data))

static func _ground(c) -> void:
	var k = c.kit("dh_ground")
	var cl = c.col("dh_ground")
	var gm: ShaderMaterial = c.mats.mat("dh_ground")
	gm.set_shader_parameter("mask_tex", _ground_mask())
	gm.set_shader_parameter("mask_rect", Vector4(MASK_RECT.position.x, MASK_RECT.position.y, 1.0 / MASK_RECT.size.x, 1.0 / MASK_RECT.size.y))
	# the whole plot and a margin under the trees, minus the mouth of the cellar steps
	var S: Dictionary = L.SHAFT
	var gx0 := 94.0
	var gx1 := 158.0
	var gz0 := -26.0
	var gz1 := 26.0
	var sx0: float = S.x0
	var sx1: float = S.x1
	var sz0: float = S.z0
	var sz1: float = S.z1
	for r in [[gx0, gz0, gx1, sz0], [gx0, sz1, gx1, gz1], [gx0, sz0, sx0, sz1], [sx1, sz0, gx1, sz1]]:
		var a := Vector3(float(r[0]), 0.0, float(r[1]))
		var b := Vector3(float(r[2]), 0.0, float(r[3]))
		# cut into 8 m tiles: lights and decals pick their pieces, and the big quads keep their precision
		var nx := int(ceil((b.x - a.x) / 8.0))
		var nz := int(ceil((b.z - a.z) / 8.0))
		for ix in nx:
			for iz in nz:
				var p0 := Vector3(lerpf(a.x, b.x, float(ix) / nx), 0.0, lerpf(a.z, b.z, float(iz) / nz))
				var p1 := Vector3(lerpf(a.x, b.x, float(ix + 1) / nx), 0.0, lerpf(a.z, b.z, float(iz + 1) / nz))
				k.quad("dh_ground", p0, Vector3(p1.x, 0, p0.z), p1, Vector3(p0.x, 0, p1.z), Vector3.UP,
					Vector2(p0.x, p0.z), Vector2(p1.x, p0.z), Vector2(p1.x, p1.z), Vector2(p0.x, p1.z))
		cl.box(Vector3(a.x, -0.35, a.z), Vector3(b.x, 0.0, b.z))
	# dark earth under the slab, where the cellar is not (seen from the steps, through the gap of the doors)
	k.box("dark", Vector3(sx0 - 0.3, -0.36, sz0 - 0.3), Vector3(sx1, -0.3, sz0), Color.WHITE)
	k.box("dark", Vector3(sx0 - 0.3, -0.36, sz1), Vector3(sx1, -0.3, sz1 + 0.3), Color.WHITE)

# ====================================================================== the house front

## Window in the east facade (the wall face is at x = xf): frame, mullions, sill, shutters, black glass (or lit).
static func _house_window(c, k, xf: float, zc: float, y0: float, y1: float, w: float, lit: bool, shutters: int) -> void:
	var z0 := zc - w * 0.5
	var z1 := zc + w * 0.5
	var fw := 0.06
	var white := Color(0.5, 0.5, 0.48)
	k.box("paintwood", Vector3(xf - 0.12, y0, z0), Vector3(xf + 0.03, y1, z0 + fw), white)
	k.box("paintwood", Vector3(xf - 0.12, y0, z1 - fw), Vector3(xf + 0.03, y1, z1), white)
	k.box("paintwood", Vector3(xf - 0.12, y1 - fw, z0), Vector3(xf + 0.03, y1, z1), white)
	k.box("paintwood", Vector3(xf - 0.12, y0, z0), Vector3(xf + 0.03, y0 + fw, z1), white)
	k.box("paintwood", Vector3(xf - 0.08, y0, zc - 0.02), Vector3(xf - 0.03, y1, zc + 0.02), white)
	k.box("paintwood", Vector3(xf - 0.08, (y0 + y1) * 0.5 - 0.018, z0), Vector3(xf - 0.03, (y0 + y1) * 0.5 + 0.018, z1), white)
	k.box("paintwood", Vector3(xf, y0 - 0.05, z0 - 0.06), Vector3(xf + 0.1, y0, z1 + 0.06), white)
	var ctr := Vector3(xf - 0.1, (y0 + y1) * 0.5, zc)
	Shell.sign_quad(k, "dh_glass_dark", ctr, Vector3.RIGHT, w - 0.06, y1 - y0 - 0.06)
	if lit:
		# drawn curtains with a lamp behind them, in front of the black glass (its own region: it goes dark)
		Shell.sign_quad(c.kit("dh_lit"), "dh_window_lit", ctr + Vector3(0.012, 0, 0), Vector3.RIGHT, w - 0.08, y1 - y0 - 0.08)
		# someone stands behind the curtains (gone with the light)
		var lk = c.kit("dh_lit")
		lk.sphere("dark", ctr + Vector3(0.02, 0.2, 0.13), 0.1, 10, 7, Color.WHITE, Vector3(0.2, 1.2, 0.95))
		lk.rbox("dark", ctr + Vector3(0.016, -0.62, -0.08), ctr + Vector3(0.03, 0.08, 0.34), 0.006, 1, Color.WHITE)
	# louvred shutters, one hanging from a single hinge (shutters: 1 left, 2 right, 3 both)
	var sh := Color(0.16, 0.2, 0.17)
	for side in [1, 2]:
		if shutters & side == 0:
			continue
		var zs := z0 - 0.5 if side == 1 else z1 + 0.04
		# (the right one of a window that has lost its left one hangs from a single hinge)
		var tilt := 0.14 if side == 2 and shutters == 2 else 0.0
		var xf2 := Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(xf + 0.02, y1, zs))
		k.box("paintwood", Vector3(0.0, -(y1 - y0), 0.0), Vector3(0.035, 0.0, 0.46), sh, 1.0, Kit.ALL, xf2)
		for s in 7:
			var yy := -(y1 - y0) * (float(s) + 0.5) / 7.0
			k.box("paintwood", Vector3(0.035, yy - 0.012, 0.04), Vector3(0.045, yy + 0.012, 0.42), sh.darkened(0.3), 1.0, Kit.ALL, xf2)

static func _house(c) -> void:
	var k = c.kit("dh_house")
	var tk = c.kit("dh_trim")
	var cl = c.col("dh_house")
	var H: Dictionary = L.HOUSE
	var P: Dictionary = L.PORCH
	var x0: float = H.x0
	var x1: float = H.x1
	var z0: float = H.z0
	var z1: float = H.z1
	var eave: float = H.eave
	var ridge: float = H.ridge
	var py: float = P.y
	var df: Dictionary = L.DOOR_FRONT
	# east facade: stone footing, clapboard above, the door, eight windows
	var wins_low := [-6.3, -2.05, 2.05, 6.3]
	var wy0 := py + 0.95
	var wy1 := py + 2.3
	var uy0 := 3.55
	var uy1 := 4.9
	# (two walls, one per storey: the openings of a wall may not stand above one another)
	var low_ops: Array = [[float(df.z0) - z0, float(df.z1) - z0, py, py + float(df.h)]]
	var up_ops: Array = []
	for wz in wins_low:
		low_ops.append([float(wz) - 0.55 - z0, float(wz) + 0.55 - z0, wy0, wy1])
		up_ops.append([float(wz) - 0.55 - z0, float(wz) + 0.55 - z0, uy0, uy1])
	k.box("dh_stone", Vector3(x1 - 0.34, 0.0, z0), Vector3(x1 + 0.03, py, z1), Color.WHITE)
	k.wall("dh_clapboard", Vector2(x1 - 0.15, z0), Vector2(x1 - 0.15, z1), 0.3, py, 3.0, low_ops)
	k.wall("dh_clapboard", Vector2(x1 - 0.15, z0), Vector2(x1 - 0.15, z1), 0.3, 3.0, eave, up_ops)
	cl.box(Vector3(x1 - 0.6, 0.0, z0), Vector3(x1, eave, z1))
	# side walls and the gables they carry, the roof, a chimney
	for zz: float in [z0, z1]:
		var za := minf(zz, zz + (0.3 if zz < 0.0 else -0.3))
		k.box("dh_clapboard", Vector3(x0, 0.0, za), Vector3(x1 - 0.3, eave, za + 0.3), Color.WHITE)
		var xm := (x0 + x1) * 0.5
		var zo := zz - 0.001 if zz < 0.0 else zz + 0.001
		var nrm := Vector3.FORWARD if zz < 0.0 else Vector3.BACK
		k.tri("dh_clapboard", Vector3(x0, eave, zo), Vector3(x1, eave, zo), Vector3(xm, ridge, zo), nrm,
			Vector2(x0, -eave) / 1.2, Vector2(x1, -eave) / 1.2, Vector2(xm, -ridge) / 1.2)
		cl.box(Vector3(x0, 0.0, za), Vector3(x1, eave, za + 0.3))
	var xm2 := (x0 + x1) * 0.5
	var oh := 0.45
	var rz0 := z0 - 0.4
	var rz1 := z1 + 0.4
	var drop := (ridge - eave) / (x1 - xm2) * oh
	k.quad("roof", Vector3(xm2, ridge, rz0), Vector3(xm2, ridge, rz1), Vector3(x1 + oh, eave - drop, rz1), Vector3(x1 + oh, eave - drop, rz0),
		Vector3(0.6, 0.8, 0.0).normalized(), Vector2(rz0, 0), Vector2(rz1, 0), Vector2(rz1, 5), Vector2(rz0, 5))
	k.quad("roof", Vector3(xm2, ridge, rz0), Vector3(xm2, ridge, rz1), Vector3(x0 - oh, eave - drop, rz1), Vector3(x0 - oh, eave - drop, rz0),
		Vector3(-0.6, 0.8, 0.0).normalized(), Vector2(rz0, 0), Vector2(rz1, 0), Vector2(rz1, 5), Vector2(rz0, 5))
	# the underside of the east eave, a fascia, a gutter that has come loose at one end
	k.quad("paintwood", Vector3(x1, eave - 0.02, rz0), Vector3(x1 + oh, eave - drop - 0.02, rz0), Vector3(x1 + oh, eave - drop - 0.02, rz1), Vector3(x1, eave - 0.02, rz1),
		Vector3.DOWN, Vector2(0, rz0), Vector2(oh, rz0), Vector2(oh, rz1), Vector2(0, rz1), Color(0.4, 0.4, 0.38))
	tk.box("paintwood", Vector3(x1 + oh - 0.03, eave - drop - 0.16, rz0), Vector3(x1 + oh, eave - drop + 0.02, rz1), Color(0.42, 0.42, 0.4))
	tk.tube("dh_iron", PackedVector3Array([Vector3(x1 + oh + 0.05, eave - drop - 0.1, rz0), Vector3(x1 + oh + 0.05, eave - drop - 0.14, 2.0),
		Vector3(x1 + oh + 0.06, eave - drop - 0.5, rz1 - 0.2)]), 0.06, 8, Color(0.6, 0.6, 0.6))
	tk.tube("dh_iron", PackedVector3Array([Vector3(x1 + 0.08, eave - drop - 0.2, rz0 + 0.5), Vector3(x1 + 0.08, 0.2, rz0 + 0.5)]), 0.04, 8, Color(0.6, 0.6, 0.6))
	k.box("dh_stone", Vector3(xm2 - 0.4, ridge - 1.2, 3.2), Vector3(xm2 + 0.4, ridge + 1.1, 4.1), Color(0.7, 0.6, 0.55))
	# corner boards, the band between the storeys
	for zz: float in [z0, z1 - 0.12]:
		tk.box("paintwood", Vector3(x1 - 0.02, py, zz), Vector3(x1 + 0.03, eave, zz + 0.12), Color(0.45, 0.45, 0.43))
	tk.box("paintwood", Vector3(x1, 2.98, z0), Vector3(x1 + 0.025, 3.1, z1), Color(0.45, 0.45, 0.43))
	# windows: the one above the porch, on the right, is lit until she comes down
	var i := 0
	for wz in wins_low:
		_house_window(c, tk, x1, float(wz), wy0, wy1, 1.1, false, [3, 1, 0, 2][i])
		_house_window(c, tk, x1, float(wz), uy0, uy1, 1.1, i == 2, [1, 3, 3, 2][i])
		i += 1
	c.room_fx["lit_window"] = Vector3(x1 + 0.3, (uy0 + uy1) * 0.5, 2.05)
	# door casing; the leaf turns around its hinge (dehors.gd); the black hall behind it
	var dz0: float = df.z0
	var dz1: float = df.z1
	var dh: float = df.h
	tk.box("paintwood", Vector3(x1 - 0.02, py, dz0 - 0.1), Vector3(x1 + 0.04, py + dh + 0.1, dz0), Color(0.45, 0.45, 0.43))
	tk.box("paintwood", Vector3(x1 - 0.02, py, dz1), Vector3(x1 + 0.04, py + dh + 0.1, dz1 + 0.1), Color(0.45, 0.45, 0.43))
	tk.box("paintwood", Vector3(x1 - 0.02, py + dh, dz0 - 0.1), Vector3(x1 + 0.04, py + dh + 0.12, dz1 + 0.1), Color(0.45, 0.45, 0.43))
	var hk = c.kit("dh_hall")
	hk.box("dark", Vector3(x1 - 2.8, py - 0.1, dz0 - 0.5), Vector3(x1 - 2.7, py + dh + 0.4, dz1 + 0.5), Color.WHITE)
	hk.box("wallpaper_house", Vector3(x1 - 2.7, py, dz0 - 0.5), Vector3(x1 - 0.3, py + dh + 0.3, dz0 - 0.4), Color(0.5, 0.5, 0.5))
	hk.box("wallpaper_house", Vector3(x1 - 2.7, py, dz1 + 0.4), Vector3(x1 - 0.3, py + dh + 0.3, dz1 + 0.5), Color(0.5, 0.5, 0.5))
	hk.box("floorboards", Vector3(x1 - 2.7, py - 0.1, dz0 - 0.4), Vector3(x1 - 0.3, py, dz1 + 0.4), Color.WHITE)
	hk.box("dark", Vector3(x1 - 2.7, py + dh + 0.3, dz0 - 0.4), Vector3(x1 - 0.3, py + dh + 0.4, dz1 + 0.4), Color.WHITE)
	var dk = c.kit("dh_front_door")
	var w := dz1 - dz0 - 0.03
	dk.box("panel", Vector3(0.0, 0.01, -0.025), Vector3(w, dh - 0.02, 0.025), Color(0.42, 0.5, 0.42))
	for pyy in [[0.14, 0.9], [1.02, dh - 0.16]]:
		for pxx in [[0.09, w * 0.5 - 0.035], [w * 0.5 + 0.035, w - 0.09]]:
			dk.box("panel", Vector3(float(pxx[0]), float(pyy[0]), -0.031), Vector3(float(pxx[1]), float(pyy[1]), -0.025), Color(0.3, 0.37, 0.3))
	dk.sphere("brass", Vector3(w - 0.07, 1.0, -0.06), 0.03, 10, 6, Color.WHITE)
	# closed: the leaf runs along +z from the hinge at dz0, its face flush with the wall (local +x -> world +z)
	c.room_fx["front_hinge"] = Vector3(x1 - 0.06, py, dz0 + 0.015)
	c.room_fx["front_yaw"] = -PI * 0.5

# ====================================================================== the porch

static func _porch(c) -> void:
	var k = c.kit("dh_house")
	var tk = c.kit("dh_trim")
	var pk = c.kit("dh_props")
	var cl = c.col("dh_house")
	var cs = c.col_see("dh_house")
	var P: Dictionary = L.PORCH
	var S: Dictionary = L.STEPS
	var x0: float = P.x0
	var x1: float = P.x1
	var z0: float = P.z0
	var z1: float = P.z1
	var py: float = P.y
	var ry: float = P.roof
	var white := Color(0.5, 0.5, 0.48)
	# deck (boards across the walk), skirt of planks, steps
	k.box("dh_deck", Vector3(x0, py - 0.05, z0), Vector3(x1, py, z1), Color.WHITE, 1.0, Kit.FACE_PY)
	k.box("dh_planks", Vector3(x0, 0.0, z0), Vector3(x1, py - 0.05, z1), Color(0.7, 0.7, 0.7), 1.0, Kit.FACE_PX | Kit.FACE_PZ | Kit.FACE_NZ)
	k.box("paintwood", Vector3(x0, py - 0.05, z0 - 0.02), Vector3(x1 + 0.03, py, z1 + 0.02), white, 1.0, Kit.FACE_PX | Kit.FACE_PZ | Kit.FACE_NZ)
	cl.box(Vector3(x0 - 0.2, 0.0, z0), Vector3(x1, py, z1))
	var sx0: float = S.x0
	var sx1: float = S.x1
	var sz0: float = S.z0
	var sz1: float = S.z1
	for i in 2:
		var top := py - 0.12 * float(i + 1)
		var xa := sx0 + 0.35 * float(i)
		k.box("dh_deck", Vector3(xa, top - 0.04, sz0), Vector3(xa + 0.35, top, sz1), Color.WHITE)
		k.box("dh_planks", Vector3(xa, 0.0, sz0), Vector3(xa + 0.32, top - 0.04, sz1), Color(0.6, 0.6, 0.6), 1.0, Kit.FACE_PX | Kit.FACE_PZ | Kit.FACE_NZ)
	cl.ramp_x(sx1, sx0, 0.0, py, sz0, sz1)
	(c.room_fx["solids"] as Array).append(Rect2(x0, z0, sx1 - x0 + 0.1, z1 - z0))
	# posts, the roof they hold, a frieze of fretwork under it
	for pz: float in [z0 + 0.08, sz0 - 0.1, sz1 + 0.1, z1 - 0.08]:
		tk.box("paintwood", Vector3(x1 - 0.14, py, float(pz) - 0.06), Vector3(x1 - 0.02, ry, float(pz) + 0.06), white)
		cl.box(Vector3(x1 - 0.15, py, float(pz) - 0.07), Vector3(x1 - 0.01, ry, float(pz) + 0.07))
	var rxf := Transform3D(Basis(Vector3.BACK, -0.1), Vector3(x0, ry + 0.26, 0.0))
	k.box("roof", Vector3(0.0, 0.0, z0 - 0.3), Vector3(x1 - x0 + 0.5, 0.06, z1 + 0.3), Color.WHITE, 1.0, Kit.ALL, rxf)
	k.box("paintwood", Vector3(x0, ry - 0.02, z0), Vector3(x1, ry + 0.04, z1), Color(0.36, 0.38, 0.4), 1.0, Kit.FACE_NY)
	tk.box("paintwood", Vector3(x1 - 0.12, ry - 0.16, z0), Vector3(x1 - 0.04, ry + 0.02, z1), white)
	tk.box("paintwood", Vector3(x0, ry - 0.16, z0), Vector3(x1, ry + 0.02, z0 + 0.08), white)
	tk.box("paintwood", Vector3(x0, ry - 0.16, z1 - 0.08), Vector3(x1, ry + 0.02, z1), white)
	# railings on the three sides, open at the steps
	var rails := [[Vector3(x0, 0, z0 + 0.04), Vector3(x1 - 0.08, 0, z0 + 0.04)], [Vector3(x0, 0, z1 - 0.04), Vector3(x1 - 0.08, 0, z1 - 0.04)],
		[Vector3(x1 - 0.08, 0, z0 + 0.04), Vector3(x1 - 0.08, 0, sz0 - 0.1)], [Vector3(x1 - 0.08, 0, sz1 + 0.1), Vector3(x1 - 0.08, 0, z1 - 0.04)]]
	for r in rails:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		for hy: float in [py + 0.12, py + 0.92]:
			tk.box("paintwood", Vector3(minf(a.x, b.x) - 0.025, hy - 0.03, minf(a.z, b.z) - 0.025), Vector3(maxf(a.x, b.x) + 0.025, hy + 0.03, maxf(a.z, b.z) + 0.025), white)
		var n := int(a.distance_to(b) / 0.14)
		for i in range(1, n):
			if (i * 7 + int(a.z * 3.0)) % 11 == 0:
				continue                                   # a baluster gone here and there
			var q := a.lerp(b, float(i) / float(n))
			tk.box("paintwood", Vector3(q.x - 0.014, py + 0.15, q.z - 0.014), Vector3(q.x + 0.014, py + 0.9, q.z + 0.014), white)
		cs.box(Vector3(minf(a.x, b.x) - 0.04, py, minf(a.z, b.z) - 0.04), Vector3(maxf(a.x, b.x) + 0.04, py + 0.95, maxf(a.z, b.z) + 0.04))
	# the daycare's sign beside the door, a dead lamp above it, a bench with a letter, the doormat
	var hx: float = L.HOUSE.x1
	Shell.board(pk, "panel", Vector3(hx + 0.03, py + 1.55, -1.25), Vector3.RIGHT, 0.86, 0.52, 0.03, GREY)
	Shell.sign_quad(pk, "tex_sign_garderie.jpg", Vector3(hx + 0.034, py + 1.55, -1.25), Vector3.RIGHT, 0.8, 0.46, Rect2(0, 0, 1, 1), Color(0.5, 0.5, 0.5))
	pk.box("dh_iron", Vector3(hx, py + 2.25, -0.08), Vector3(hx + 0.12, py + 2.3, 0.08), Color.WHITE)
	pk.sphere("fluo_dead", Vector3(hx + 0.12, py + 2.2, 0.0), 0.07, 10, 6, Color.WHITE)
	var bz := z0 + 0.9
	pk.box("dh_planks", Vector3(x0 + 0.1, py + 0.4, bz - 0.7), Vector3(x0 + 0.5, py + 0.44, bz + 0.7), Color.WHITE)
	pk.box("dh_planks", Vector3(x0 + 0.06, py + 0.44, bz - 0.7), Vector3(x0 + 0.1, py + 0.85, bz + 0.7), Color.WHITE)
	for lz: float in [bz - 0.64, bz + 0.6]:
		pk.box("dh_planks", Vector3(x0 + 0.1, py, lz), Vector3(x0 + 0.5, py + 0.4, lz + 0.04), Color.WHITE)
	cl.box(Vector3(x0, py, bz - 0.72), Vector3(x0 + 0.52, py + 0.43, bz + 0.72))
	cl.box(Vector3(x0, py + 0.43, bz - 0.72), Vector3(x0 + 0.12, py + 0.85, bz + 0.72))
	var note := Vector3(x0 + 0.32, py + 0.443, bz + 0.2)
	var nb := Basis(Vector3.UP, 0.35)
	pk.quad("debris_paper", note + nb * Vector3(-0.08, 0, 0.11), note + nb * Vector3(0.08, 0, 0.11), note + nb * Vector3(0.08, 0, -0.11), note + nb * Vector3(-0.08, 0, -0.11),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.84, 0.8, 0.68))
	c.room_fx["note_porch"] = note
	pk.box("fabric", Vector3(x0 + 0.1, py, -0.42), Vector3(x0 + 0.75, py + 0.012, 0.42), Color(0.14, 0.11, 0.08))
	# a pair of small rubber boots left by the door, a broom
	for bx: float in [0.0, 0.14]:
		U.cone(pk, "rubber", Vector3(x0 + 0.2, py, 0.75 + bx), Vector3(x0 + 0.2, py + 0.2, 0.75 + bx), 0.045, 0.05, 8, Color(0.5, 0.42, 0.08), true)
		pk.rbox("rubber", Vector3(x0 + 0.16, py, 0.71 + bx), Vector3(x0 + 0.32, py + 0.06, 0.79 + bx), 0.025, 2, Color(0.5, 0.42, 0.08))
	pk.tube("dh_planks", PackedVector3Array([Vector3(x0 + 0.06, py + 1.4, 2.5), Vector3(x0 + 0.3, py + 0.06, 2.6)]), 0.014, 6, Color.WHITE)
	pk.box("fabric", Vector3(x0 + 0.22, py, 2.48), Vector3(x0 + 0.38, py + 0.12, 2.74), Color(0.3, 0.24, 0.12))
	# wind chimes under the south-east corner of the porch roof (they hang from a node dehors.gd sways)
	var ck = c.kit("dh_chimes")
	ck.tube("dh_iron", PackedVector3Array([Vector3(0, 0, 0), Vector3(0, -0.12, 0)]), 0.003, 5, Color.WHITE)
	ck.disc("dh_planks", Vector3(0, -0.12, 0), Vector3.UP, Vector3.RIGHT, 0.06, 10, Color.WHITE)
	ck.disc("dh_planks", Vector3(0, -0.125, 0), Vector3.DOWN, Vector3.RIGHT, 0.06, 10, Color.WHITE)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var ln := 0.2 + 0.05 * float(i)
		var q := Vector3(cos(a) * 0.045, -0.13, sin(a) * 0.045)
		ck.tube("metal", PackedVector3Array([q - Vector3(0, 0.05, 0), q - Vector3(0, 0.05 + ln, 0)]), 0.007, 6, Color(0.75, 0.75, 0.72))
	ck.tube("dh_iron", PackedVector3Array([Vector3(0, -0.13, 0), Vector3(0, -0.5, 0)]), 0.002, 4, Color.WHITE)
	ck.disc("dh_planks", Vector3(0, -0.3, 0), Vector3.UP, Vector3.RIGHT, 0.025, 8, Color.WHITE)
	ck.box("dh_planks", Vector3(-0.03, -0.58, -0.003), Vector3(0.03, -0.5, 0.003), Color.WHITE)
	c.room_fx["chimes"] = Vector3(x1 - 0.2, ry - 0.16, z1 - 0.3)

# ====================================================================== fence, walls, the tree line

static func _fence_run(c, a: Vector2, b: Vector2, seed_: int) -> void:
	var k = c.kit("dh_fence")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var d := b - a
	var ln := d.length()
	var dir := d / ln
	var n := int(ceil(ln / 2.4))
	var yaw := atan2(-dir.y, dir.x)
	var h: float = L.FENCE_H
	for i in n:
		var s0 := ln * float(i) / float(n)
		var s1 := ln * float(i + 1) / float(n)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(a.x, 0.0, a.y))
		var top := h + rng.randf_range(-0.05, 0.05)
		var lean := rng.randf_range(-0.03, 0.03)
		var pxf := xf * Transform3D(Basis(Vector3.RIGHT, lean), Vector3.ZERO)
		k.box("dh_planks", Vector3(s0 + 0.02, 0.06, -0.015), Vector3(s1 - 0.02, top, 0.015), Color(0.62, 0.62, 0.6), 1.0, Kit.ALL, pxf)
		k.box("dh_planks", Vector3(s0 - 0.05, 0.0, -0.05), Vector3(s0 + 0.05, h + 0.12, 0.05), Color(0.5, 0.5, 0.5), 1.0, Kit.ALL, xf)
		for ry: float in [0.45, h - 0.35]:
			k.box("dh_planks", Vector3(s0, ry, 0.015), Vector3(s1, ry + 0.09, 0.06), Color(0.5, 0.5, 0.5), 1.0, Kit.ALL, xf)
	var mn := Vector3(minf(a.x, b.x) - 0.08, 0.0, minf(a.y, b.y) - 0.08)
	var mx := Vector3(maxf(a.x, b.x) + 0.08, h + 0.6, maxf(a.y, b.y) + 0.08)
	c.col("dh_fence").box(mn, mx)

static func _fence(c) -> void:
	var Y: Dictionary = L.YARD
	var G: Dictionary = L.GATE
	var x0: float = Y.x0
	var x1: float = Y.x1
	var z0: float = Y.z0
	var z1: float = Y.z1
	_fence_run(c, Vector2(x0, z0), Vector2(x1, z0), 11)
	_fence_run(c, Vector2(x1, z1), Vector2(x0, z1), 12)
	_fence_run(c, Vector2(x1, z0), Vector2(x1, float(G.z0) - 0.4), 13)
	_fence_run(c, Vector2(x1, float(G.z1) + 0.4), Vector2(x1, z1), 14)
	# the garden walls that tie the fence to the corners of the house
	var k = c.kit("dh_fence")
	var H: Dictionary = L.HOUSE
	for seg in [[z0, float(H.z0)], [float(H.z1), z1]]:
		k.box("dh_stone", Vector3(x0 - 0.3, 0.0, float(seg[0])), Vector3(x0, 2.1, float(seg[1])), Color(0.8, 0.8, 0.8))
		k.box("dh_stone", Vector3(x0 - 0.36, 2.1, float(seg[0])), Vector3(x0 + 0.06, 2.2, float(seg[1])), Color(0.55, 0.55, 0.55))
		c.col("dh_fence").box(Vector3(x0 - 0.4, 0.0, float(seg[0])), Vector3(x0, 2.6, float(seg[1])))

static func _trees(c) -> void:
	var k = c.kit("dh_trees")
	var bk = c.kit("dh_trunks")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1994
	var Y: Dictionary = L.YARD
	var x0: float = Y.x0
	var x1: float = Y.x1
	var z0: float = Y.z0
	var z1: float = Y.z1
	# the tree line outside the fence: two staggered rows, bare trees and firs, a hedge of bushes at their feet
	var per := [[Vector2(x0 - 4.0, z0), Vector2(x1 + 1.0, z0), Vector2(0, -1)], [Vector2(x1, z0 - 1.0), Vector2(x1, z1 + 1.0), Vector2(1, 0)],
		[Vector2(x1 + 1.0, z1), Vector2(x0 - 4.0, z1), Vector2(0, 1)]]
	for side in per:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var out: Vector2 = side[2]
		var ln := a.distance_to(b)
		var s := 0.6
		while s < ln:
			var p := a.lerp(b, s / ln)
			# leave the lane beyond the gate open
			var lane := out.x > 0.5 and p.y > float(L.GATE.z0) - 1.6 and p.y < float(L.GATE.z1) + 1.6
			if not lane:
				var off := rng.randf_range(1.3, 2.6)
				var q := p + out * off
				var h := rng.randf_range(8.0, 12.5)
				var dark := rng.randf_range(0.55, 1.0)
				if rng.randf() < 0.36:
					U.card(k, Vector3(q.x, -0.1, q.y), h * 0.52, h, U.fir_cell(rng.randi()), rng.randf() * PI, 2, Color(dark, dark, dark))
				else:
					U.card(k, Vector3(q.x, -0.1, q.y), h * 0.62, h, U.bare_cell(rng.randi()), rng.randf() * PI, 2, Color(dark, dark, dark))
				# second row, taller, further out
				var q2 := p + out * rng.randf_range(4.5, 7.5) + Vector2(out.y, -out.x) * rng.randf_range(-1.0, 1.0)
				var h2 := rng.randf_range(11.0, 15.0)
				U.card(k, Vector3(q2.x, -0.1, q2.y), h2 * (0.5 if rng.randf() < 0.5 else 0.62), h2,
					U.fir_cell(rng.randi()) if rng.randf() < 0.5 else U.bare_cell(rng.randi()), rng.randf() * PI, 1 if absf(out.x) > 0.5 else 2, Color(0.5, 0.5, 0.5))
				if rng.randf() < 0.55:
					var q3 := p + out * rng.randf_range(0.5, 1.0)
					U.card(k, Vector3(q3.x, -0.05, q3.y), rng.randf_range(2.0, 3.0), rng.randf_range(1.8, 2.8), U.bush_cell(rng.randi()), rng.randf() * PI, 2)
			s += rng.randf_range(1.7, 3.1)
	# along the lane beyond the gate
	for i in 5:
		for sgn in [-1.0, 1.0]:
			var q := Vector3(x1 + 2.0 + 2.4 * float(i) + rng.randf_range(-0.5, 0.5), -0.1, 8.5 + sgn * rng.randf_range(2.6, 3.6))
			var h := rng.randf_range(9.0, 13.0)
			U.card(k, q, h * 0.6, h, U.bare_cell(rng.randi()), rng.randf() * PI, 2, Color(0.7, 0.7, 0.7))
	# trees of the yard: a trunk one can walk around, bare branches against the sky
	for t in L.YARD_TREES:
		var base := Vector3(float(t[0]), 0.0, float(t[1]))
		var r := float(t[2])
		var h := float(t[3])
		U.cone(bk, "dh_bark", base - Vector3(0, 0.1, 0), base + Vector3(rng.randf_range(-0.1, 0.1), h * 0.34, rng.randf_range(-0.1, 0.1)), r * 1.15, r * 0.8, 9)
		U.card(k, base - Vector3(0, 0.1, 0), h * 0.62, h, U.bare_cell(rng.randi()), rng.randf() * PI, 3, Color(0.85, 0.85, 0.85))
		U.solid(c, "dh_trunks", base + Vector3(-r, 0, -r), base + Vector3(r, 3.0, r))
	# the oak: a thick trunk, four limbs, the fine branches as cards on them
	var o: Vector3 = L.OAK
	var top := o + Vector3(0.1, 3.3, -0.05)
	U.cone(bk, "dh_bark", o - Vector3(0, 0.15, 0), o + Vector3(0.0, 0.5, 0.0), 0.62, 0.46, 12)
	U.cone(bk, "dh_bark", o + Vector3(0, 0.5, 0), top, 0.46, 0.36, 12)
	U.solid(c, "dh_trunks", o + Vector3(-0.42, 0, -0.42), o + Vector3(0.42, 3.2, 0.42))
	var limbs := [Vector3(2.6, 2.3, 0.6), Vector3(-2.2, 2.6, 1.2), Vector3(0.4, 2.9, -2.4), Vector3(-0.8, 3.4, -0.4), Vector3(1.1, 2.0, 2.3)]
	var li := 0
	for lv in limbs:
		var e: Vector3 = top + lv
		var mid: Vector3 = top + lv * 0.5 + Vector3(0, 0.25, 0)
		bk.tube("dh_bark", PackedVector3Array([top - Vector3(0, 0.2, 0), mid, e]), 0.2, 8, Color.WHITE, 1.0, false,
			func(i: int, _a: float) -> float: return [1.0, 0.72, 0.42][i])
		var yaw := atan2(lv.z, lv.x)
		U.card(k, mid - Vector3(0, 0.4, 0), 5.2, 6.0, Rect2(U.bare_cell(li).position + Vector2(0.0, 0.0), Vector2(0.242, 0.34)), yaw, 1, Color(0.9, 0.9, 0.9))
		U.card(k, e - Vector3(0, 0.8, 0), 4.2, 5.0, Rect2(U.bare_cell(li + 1).position, Vector2(0.242, 0.33)), yaw + 1.3, 1, Color(0.9, 0.9, 0.9))
		li += 1
	c.room_fx["oak_top"] = top
	# tufts of long grass and weeds: thick along the fence and around what stands on the lawn, sparse elsewhere
	var tk = c.kit("dh_tufts")
	var tufts := 0
	var tries := 0
	while tufts < 420 and tries < 4000:
		tries += 1
		var p := Vector3(rng.randf_range(x0 + 0.2, x1 - 0.2), 0.0, rng.randf_range(z0 + 0.2, z1 - 0.2))
		var edge := minf(minf(p.x - x0, x1 - p.x), minf(p.z - z0, z1 - p.z))
		if edge > 1.2 and rng.randf() < 0.82:
			continue
		if L.is_gravel(p.x, p.z) or L.in_box(L.PORCH, p, 1.0) or L.in_box(L.SHED, p, 0.2) or L.in_box(L.SERRE, p, 0.2) or L.in_box(L.SHAFT, p, 0.3) \
				or L.in_box(L.SANDBOX, p, 0.1) or p.x < x0 + 0.1:
			continue
		var sc := rng.randf_range(0.35, 0.8) * (1.25 if edge < 1.2 else 1.0)
		var cell := rng.randi() % 4
		var g := rng.randf_range(0.7, 1.0)
		U.card(tk, p - Vector3(0, 0.02, 0), sc * 1.5, sc, Rect2(0.25 * float(cell) + 0.004, 0.02, 0.242, 0.97), rng.randf() * PI, 2, Color(g, g, g * 0.9), "dh_tuft", true)
		tufts += 1

# ====================================================================== le caveau

static func _cave(c) -> void:
	var k = c.kit("dh_cave")
	var pk = c.kit("dh_cave_props")
	var cl = c.col("dh_cave")
	var V: Dictionary = L.CAVE
	var S: Dictionary = L.SHAFT
	var x0: float = V.x0
	var x1: float = V.x1
	var z0: float = V.z0
	var z1: float = V.z1
	var fy: float = V.floor
	var cy: float = V.ceil
	var sx0: float = S.x0
	var sx1: float = S.x1
	var sz0: float = S.z0
	var sz1: float = S.z1
	var dh: float = L.CAVE_DOOR_H
	# the room: flagstones, fieldstone walls, joists under the lawn
	k.box("dh_flag", Vector3(x0 - 0.3, fy - 0.2, z0 - 0.3), Vector3(sx1, fy, z1 + 0.3), Color.WHITE, 1.0, Kit.FACE_PY)
	cl.box(Vector3(x0 - 0.3, fy - 0.3, z0 - 0.3), Vector3(sx1 + 0.3, fy, z1 + 0.3))
	k.box("dh_planks", Vector3(x0, cy, z0), Vector3(x1, cy + 0.05, z1), Color(0.4, 0.4, 0.4), 1.0, Kit.FACE_NY)
	for i in 6:
		var jx := x0 + 0.5 + 0.84 * float(i)
		k.box("dh_planks", Vector3(jx - 0.05, cy - 0.16, z0), Vector3(jx + 0.05, cy, z1), Color(0.5, 0.5, 0.5))
	for w in [[Vector2(x0 - 0.15, z0 - 0.3), Vector2(x0 - 0.15, z1 + 0.3), []], [Vector2(x0 - 0.3, z0 - 0.15), Vector2(x1 + 0.3, z0 - 0.15), []],
			[Vector2(x0 - 0.3, z1 + 0.15), Vector2(x1 + 0.3, z1 + 0.15), []],
			[Vector2(x1 + 0.15, z0 - 0.3), Vector2(x1 + 0.15, z1 + 0.3), [[sz0 - (z0 - 0.3), sz1 - (z0 - 0.3), fy, fy + dh]]]]:
		Shell.wall(c, "dh_cave", "dh_stone", w[0], w[1], 0.3, fy, cy + 0.05, w[2])
	# the steps: stone treads between two walls, down to the west; a lintel over the doorway
	var n := 10
	var run := (sx1 - (sx0 + 0.2)) / float(n)
	var rise := -fy / float(n)
	for i in n:
		var xa := sx1 - run * float(i + 1)
		var top := -rise * float(i + 1)
		k.box("dh_flag", Vector3(xa, fy, sz0), Vector3(xa + run, top, sz1), Color(0.85, 0.85, 0.85), 1.0, Kit.FACE_PY | Kit.FACE_PX)
	cl.ramp_x(sx0 + 0.2, sx1, fy, 0.0, sz0, sz1)
	cl.box(Vector3(sx0 + 0.2, fy - 0.2, sz0), Vector3(sx1, fy, sz1))
	for zz in [[sz0 - 0.3, sz0], [sz1, sz1 + 0.3]]:
		k.box("dh_stone", Vector3(sx0 + 0.3, fy, float(zz[0])), Vector3(sx1 + 0.3, 0.0, float(zz[1])), Color.WHITE)
		cl.box(Vector3(sx0 + 0.3, fy, float(zz[0])), Vector3(sx1 + 0.3, 0.0, float(zz[1])))
	k.box("dh_planks", Vector3(sx0 - 0.02, fy + dh, sz0 - 0.1), Vector3(sx0 + 0.32, fy + dh + 0.16, sz1 + 0.1), Color(0.5, 0.5, 0.5))
	# (east of the last tread the lawn begins; under the lawn, beyond the shaft, earth)
	# a kerb of stone round the mouth, the frame the doors lie on
	var kk = c.kit("dh_cave_top")
	for r in [[sx0 - 0.18, sz0 - 0.18, sx1, sz0], [sx0 - 0.18, sz1, sx1, sz1 + 0.18], [sx0 - 0.18, sz0, sx0, sz1]]:
		kk.box("dh_stone", Vector3(float(r[0]), 0.0, float(r[1])), Vector3(float(r[2]), 0.12, float(r[3])), Color(0.75, 0.75, 0.75))
		c.col("dh_cave_top").box(Vector3(float(r[0]), 0.0, float(r[1])), Vector3(float(r[2]), 0.12, float(r[3])))
	(c.room_fx["solids"] as Array).append(Rect2(sx0 - 0.2, sz0 - 0.2, sx1 - sx0 + 0.3, sz1 - sz0 + 0.4))
	# the two doors: boards on ledges, an iron ring; each authored around its hinge line (the long outer edge)
	var half := (sz1 - sz0) * 0.5
	var ln := sx1 - sx0
	for side in 2:
		var dk = c.kit("dh_trap_%d" % side)
		var sg := 1.0 if side == 0 else -1.0             # 0: the north leaf, reaching +z; 1: the south leaf, reaching -z
		dk.box("dh_deck", Vector3(0.0, 0.0, minf(0.0, sg * (half - 0.008))), Vector3(ln, 0.045, maxf(0.0, sg * (half - 0.008))), Color(0.75, 0.75, 0.75))
		for bx: float in [0.35, ln * 0.5, ln - 0.35]:
			dk.box("dh_planks", Vector3(bx - 0.05, 0.045, minf(sg * 0.04, sg * (half - 0.05))), Vector3(bx + 0.05, 0.075, maxf(sg * 0.04, sg * (half - 0.05))), Color(0.6, 0.6, 0.6))
		dk.tube("dh_iron", PackedVector3Array([Vector3(ln * 0.5 - 0.06, 0.05, sg * (half - 0.1)), Vector3(ln * 0.5 - 0.06, 0.1, sg * (half - 0.1)),
			Vector3(ln * 0.5 + 0.06, 0.1, sg * (half - 0.1)), Vector3(ln * 0.5 + 0.06, 0.05, sg * (half - 0.1))]), 0.008, 6, Color.WHITE)
		for hx: float in [0.5, ln - 0.5]:
			dk.box("dh_iron", Vector3(hx - 0.07, 0.045, minf(0.0, sg * 0.12)), Vector3(hx + 0.07, 0.052, maxf(0.0, sg * 0.12)), Color.WHITE)
	c.room_fx["trap_hinges"] = [Vector3(sx0, 0.12, sz0), Vector3(sx0, 0.12, sz1)]
	# the hasp and the padlock across the two doors (hidden once it is unlocked)
	var lk = c.kit("dh_trap_lock")
	lk.box("dh_iron", Vector3(-0.03, 0.0, -0.09), Vector3(0.03, 0.012, 0.09), Color.WHITE)
	lk.rbox("brass", Vector3(-0.035, 0.012, -0.03), Vector3(0.035, 0.07, 0.03), 0.01, 2, Color(0.8, 0.8, 0.8))
	lk.tube("metal", PackedVector3Array([Vector3(-0.02, 0.07, 0.0), Vector3(-0.02, 0.1, 0.0), Vector3(0.02, 0.1, 0.0), Vector3(0.02, 0.07, 0.0)]), 0.006, 6, Color.WHITE)
	c.room_fx["trap_lock"] = Vector3(sx1 - 0.7, 0.2, (sz0 + sz1) * 0.5)
	# what is kept down here: shelves of preserves, crates, sacks, the mattress she slept on, a table
	for sy: float in [fy + 0.5, fy + 1.0, fy + 1.5]:
		pk.box("dh_planks", Vector3(x0 + 0.4, sy, z0), Vector3(x1 - 0.6, sy + 0.03, z0 + 0.32), Color(0.7, 0.7, 0.7))
	for sx: float in [x0 + 0.4, x0 + 2.2, x1 - 0.64]:
		pk.box("dh_planks", Vector3(sx, fy, z0), Vector3(sx + 0.04, fy + 1.7, z0 + 0.32), Color(0.6, 0.6, 0.6))
	cl.box(Vector3(x0 + 0.4, fy, z0), Vector3(x1 - 0.6, fy + 1.7, z0 + 0.34))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for sy: float in [fy + 0.53, fy + 1.03, fy + 1.53]:
		var jx := x0 + 0.55
		while jx < x1 - 0.8:
			if rng.randf() < 0.75:
				var jr := rng.randf_range(0.04, 0.06)
				var jh := rng.randf_range(0.12, 0.2)
				var jz := z0 + 0.12 + rng.randf_range(0.0, 0.1)
				var tint: Color = [Color(0.35, 0.12, 0.08), Color(0.3, 0.26, 0.1), Color(0.12, 0.2, 0.1), Color(0.4, 0.34, 0.25)][rng.randi() % 4]
				pk.tube("plastic", PackedVector3Array([Vector3(jx, sy, jz), Vector3(jx, sy + jh, jz)]), jr, 9, tint, 1.0, true)
				pk.tube("dh_rust", PackedVector3Array([Vector3(jx, sy + jh, jz), Vector3(jx, sy + jh + 0.02, jz)]), jr * 0.9, 9, Color.WHITE, 1.0, true)
			jx += rng.randf_range(0.11, 0.2)
	for cr in [[x1 - 0.68, z0 + 0.42, 0.6, 0.4, 0.0], [x1 - 0.64, z0 + 0.44, 0.55, 0.38, 0.4], [x1 - 0.7, z0 + 1.0, 0.6, 0.45, 0.0]]:
		var cx := float(cr[0])
		var cz := float(cr[1])
		var by := fy + float(cr[4])
		pk.box("dh_planks", Vector3(cx, by, cz), Vector3(cx + float(cr[2]), by + float(cr[3]), cz + 0.5), Color(0.75, 0.72, 0.66))
		cl.box(Vector3(cx, by, cz), Vector3(cx + float(cr[2]), by + float(cr[3]), cz + 0.5))
	for sk in [[x0 + 0.35, z1 - 0.5], [x0 + 0.9, z1 - 0.42], [x0 + 0.5, z1 - 0.95]]:
		pk.sphere("fabric", Vector3(float(sk[0]), fy + 0.24, float(sk[1])), 0.3, 10, 7, Color(0.36, 0.3, 0.2), Vector3(1.0, 0.8, 1.0))
	cl.box(Vector3(x0 + 0.05, fy, z1 - 1.25), Vector3(x0 + 1.2, fy + 0.5, z1 - 0.1))
	# the mattress, a grey blanket, an enamel bowl
	pk.rbox("fabric", Vector3(x0 + 0.1, fy, z0 + 0.42), Vector3(x0 + 0.95, fy + 0.14, z0 + 2.3), 0.06, 2, Color(0.42, 0.4, 0.34))
	pk.rbox("fabric", Vector3(x0 + 0.12, fy + 0.12, z0 + 1.1), Vector3(x0 + 0.98, fy + 0.2, z0 + 2.32), 0.04, 2, Color(0.2, 0.2, 0.22))
	pk.rbox("fabric", Vector3(x0 + 0.2, fy + 0.13, z0 + 0.47), Vector3(x0 + 0.8, fy + 0.22, z0 + 0.82), 0.05, 2, Color(0.5, 0.48, 0.42))
	U.cone(pk, "enamel", Vector3(x0 + 1.25, fy, z0 + 1.3), Vector3(x0 + 1.25, fy + 0.07, z0 + 1.3), 0.09, 0.13, 12, Color(0.8, 0.8, 0.78))
	cl.box(Vector3(x0 + 0.1, fy, z0 + 0.42), Vector3(x0 + 0.95, fy + 0.14, z0 + 2.3))
	# the table at the west wall: the bolt cutters lie on it (their own region: they are taken), a page, candle ends
	var tx := x0 + 0.5
	var tz := z1 - 1.9
	pk.box("dh_planks", Vector3(x0 + 0.08, fy + 0.72, tz - 0.6), Vector3(x0 + 0.78, fy + 0.76, tz + 0.6), Color(0.8, 0.8, 0.8))
	for lx: float in [x0 + 0.12, x0 + 0.7]:
		for lz: float in [tz - 0.55, tz + 0.51]:
			pk.box("dh_planks", Vector3(lx, fy, lz), Vector3(lx + 0.04, fy + 0.72, lz + 0.04), Color(0.7, 0.7, 0.7))
	cl.box(Vector3(x0 + 0.08, fy, tz - 0.6), Vector3(x0 + 0.78, fy + 0.76, tz + 0.6))
	for cd in [[0.18, -0.42, 0.07], [0.25, -0.36, 0.035], [0.14, -0.3, 0.05]]:
		pk.tube("enamel", PackedVector3Array([Vector3(x0 + float(cd[0]), fy + 0.76, tz + float(cd[1])), Vector3(x0 + float(cd[0]), fy + 0.76 + float(cd[2]), tz + float(cd[1]))]),
			0.012, 7, Color(0.8, 0.76, 0.62), 1.0, true)
	var page := Vector3(tx - 0.08, fy + 0.763, tz + 0.36)
	var pb := Basis(Vector3.UP, -0.3)
	pk.quad("debris_paper", page + pb * Vector3(-0.08, 0, 0.11), page + pb * Vector3(0.08, 0, 0.11), page + pb * Vector3(0.08, 0, -0.11), page + pb * Vector3(-0.08, 0, -0.11),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.84, 0.8, 0.68))
	c.room_fx["note_cave"] = page
	Props.cutters(c.kit("dh_cutters"))
	c.room_fx["cutters_pos"] = Vector3(tx - 0.06, fy + 0.775, tz - 0.05)
	c.room_fx["cutters_yaw"] = 1.35
	# seven small chairs along the south wall, facing the mattress
	for i in 7:
		var cxp := x0 + 1.9 + 0.44 * float(i)
		Props.small_chair(pk, Vector3(cxp, fy, z1 - 0.32), PI + 0.1 * sin(float(i) * 2.3), [Color(0.5, 0.1, 0.08), Color(0.1, 0.2, 0.42), Color(0.5, 0.4, 0.1), Color(0.1, 0.32, 0.14)][i % 4])
	c.room_fx["cave_dust"] = Vector3((x0 + x1) * 0.5, cy - 0.3, (z0 + z1) * 0.5)

# ====================================================================== le portail

static func _gate(c) -> void:
	var k = c.kit("dh_fence")
	var G: Dictionary = L.GATE
	var gx: float = G.x
	var gz0: float = G.z0
	var gz1: float = G.z1
	var gh: float = G.h
	# two stone piers with caps
	for pz: float in [gz0 - 0.2, gz1 + 0.2]:
		k.box("dh_stone", Vector3(gx - 0.22, 0.0, float(pz) - 0.22), Vector3(gx + 0.22, gh + 0.25, float(pz) + 0.22), Color(0.85, 0.85, 0.85))
		k.box("dh_stone", Vector3(gx - 0.28, gh + 0.25, float(pz) - 0.28), Vector3(gx + 0.28, gh + 0.35, float(pz) + 0.28), Color(0.6, 0.6, 0.6))
		c.col("dh_fence").box(Vector3(gx - 0.24, 0.0, float(pz) - 0.24), Vector3(gx + 0.24, gh + 0.4, float(pz) + 0.24))
	# two iron leaves, each authored around its hinge: bars along +z (leaf 0) or -z (leaf 1)
	var w := (gz1 - gz0) * 0.5 - 0.02
	for side in 2:
		var gk = c.kit("dh_gate_%d" % side)
		var sg := 1.0 if side == 0 else -1.0
		for fy: float in [0.12, gh - 0.25]:
			gk.box("dh_iron", Vector3(-0.02, fy, minf(0.0, sg * w)), Vector3(0.02, fy + 0.04, maxf(0.0, sg * w)), Color.WHITE)
		for sz: float in [0.02, w - 0.02]:
			gk.box("dh_iron", Vector3(-0.025, 0.08, sg * sz - 0.025), Vector3(0.025, gh - 0.1, sg * sz + 0.025), Color.WHITE)
		var nb := 10
		for i in range(1, nb):
			var bz := sg * w * float(i) / float(nb)
			var top := gh - 0.02 + 0.12 * sin(PI * float(i) / float(nb))
			gk.tube("dh_iron", PackedVector3Array([Vector3(0, 0.12, bz), Vector3(0, top, bz)]), 0.009, 5, Color.WHITE)
			U.cone(gk, "dh_iron", Vector3(0, top, bz), Vector3(0, top + 0.09, bz), 0.016, 0.002, 5)
		# a diagonal brace
		gk.tube("dh_iron", PackedVector3Array([Vector3(0.0, 0.16, sg * 0.04), Vector3(0.0, gh - 0.25, sg * (w - 0.04))]), 0.008, 5, Color.WHITE)
	c.room_fx["gate_hinges"] = [Vector3(gx, 0.0, gz0), Vector3(gx, 0.0, gz1)]
	# the chain round the two inner stiles, and its padlock (hidden once it is cut)
	var ck = c.kit("dh_chain")
	var links := 9
	for i in links:
		var a := TAU * float(i) / float(links)
		var ctr := Vector3(cos(a) * 0.05, sin(a) * 0.02 + 0.0, sin(a) * 0.09)
		var tang := Vector3(-sin(a) * 0.05, 0.0, cos(a) * 0.09).normalized()
		var up := Vector3.UP if i % 2 == 0 else Vector3.UP.cross(tang).normalized()
		var pts := PackedVector3Array()
		for j in 9:
			var b := TAU * float(j) / 8.0
			pts.append(ctr + tang * cos(b) * 0.028 + up * sin(b) * 0.015)
		ck.tube("dh_iron", pts, 0.005, 5, Color(1.3, 1.3, 1.3))
	for i in 4:
		var pts2 := PackedVector3Array()
		var ctr2 := Vector3(0.05, -0.04 - 0.045 * float(i), 0.0)
		var up2 := Vector3.RIGHT if i % 2 == 0 else Vector3.BACK
		for j in 9:
			var b := TAU * float(j) / 8.0
			pts2.append(ctr2 + Vector3.UP * cos(b) * 0.028 + up2 * sin(b) * 0.015)
		ck.tube("dh_iron", pts2, 0.005, 5, Color(1.3, 1.3, 1.3))
	ck.rbox("brass", Vector3(0.02, -0.3, -0.035), Vector3(0.08, -0.21, 0.035), 0.012, 2, Color(0.8, 0.8, 0.8))
	c.room_fx["chain_pos"] = Vector3(gx, 1.05, (gz0 + gz1) * 0.5)
	# the lane beyond: two ruts between the trees, a milestone
	k.box("dh_stone", Vector3(gx + 1.6, 0.0, gz1 + 0.5), Vector3(gx + 1.85, 0.5, gz1 + 0.75), Color(0.7, 0.7, 0.7))

# ====================================================================== lights

static func _lights(c) -> void:
	var lr: Node3D = c.region("dh_lights")
	# the moon, low in the south-east, through thin cloud
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = MOON
	moon.light_energy = 1.4
	moon.light_specular = 0.9
	moon.light_cull_mask = MASK
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 46.0
	moon.directional_shadow_split_1 = 0.3
	moon.directional_shadow_blend_splits = true
	moon.directional_shadow_fade_start = 0.85
	moon.shadow_bias = 0.06
	moon.shadow_normal_bias = 2.0
	moon.shadow_blur = 1.6
	moon.light_angular_distance = 1.2
	moon.light_volumetric_fog_energy = 1.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	var to_moon := Vector3(0.48, 0.62, 0.62).normalized()
	moon.basis = Basis.looking_at(-to_moon, Vector3.UP)
	lr.add_child(moon)
	c.room_fx["moon"] = moon
	c.room_fx["moon_dir"] = to_moon
	# the hall of the house, seen through the open front door when she comes out: a warm light on the porch boards
	var hx: float = L.HOUSE.x1
	var py: float = L.PORCH.y
	var hall := SpotLight3D.new()
	hall.name = "HallLight"
	hall.position = Vector3(hx - 2.0, py + 1.9, 0.0)
	hall.light_color = Color(1.0, 0.66, 0.34)
	hall.light_energy = 3.2
	hall.spot_range = 9.0
	hall.spot_angle = 26.0
	hall.spot_angle_attenuation = 0.6
	hall.spot_attenuation = 0.9
	hall.shadow_enabled = true
	hall.shadow_bias = 0.05
	hall.shadow_normal_bias = 1.5
	hall.shadow_blur = 1.4
	hall.light_cull_mask = MASK
	hall.light_volumetric_fog_energy = 2.2
	hall.basis = Basis.looking_at(Vector3(1.0, -0.36, 0.0), Vector3.UP)
	hall.visible = false
	lr.add_child(hall)
	c.room_fx["hall_light"] = hall
	# what the lit window upstairs throws on the porch roof and the lawn in front
	var wl := OmniLight3D.new()
	wl.name = "WindowGlow"
	wl.position = c.room_fx["lit_window"]
	wl.light_color = Color(1.0, 0.62, 0.3)
	wl.light_energy = 0.55
	wl.omni_range = 7.0
	wl.omni_attenuation = 1.4
	wl.shadow_enabled = false
	wl.light_specular = 0.2
	wl.light_cull_mask = MASK
	wl.light_volumetric_fog_energy = 2.5
	lr.add_child(wl)
	c.room_fx["window_light"] = wl

# ====================================================================== the last layer

## Dust shaken from the joists (the cellar): off until dehors.gd lets it fall.
static func _dust(c, at: Vector3, extents: Vector3) -> GPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.012)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.66, 0.58, 0.8)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	quad.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, -0.9, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.8
	var e := GPUParticles3D.new()
	e.name = "Dust"
	e.amount = 90
	e.lifetime = 2.6
	e.one_shot = false
	e.explosiveness = 0.5
	e.randomness = 0.7
	e.process_material = pm
	e.draw_pass_1 = quad
	e.position = at
	e.visibility_aabb = AABB(-extents - Vector3(0.5, 3.0, 0.5), extents * 2.0 + Vector3(1.0, 3.5, 1.0))
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	e.emitting = false
	c.region("dh_lights").add_child(e)
	return e

static func _fog(c, ctr: Vector3, size: Vector3, density: float, falloff := 0.0) -> void:
	var fog := FogVolume.new()
	fog.name = "Mist"
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = size
	fog.position = ctr
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = Color(0.72, 0.78, 0.88)
	fm.edge_fade = 0.6
	fm.height_falloff = falloff
	fog.material = fm
	c.region("dh_lights").add_child(fog)

static func _finish(c) -> void:
	var m: int = L.L_DH
	var V: Dictionary = L.CAVE
	var S: Dictionary = L.SHED
	var G: Dictionary = L.SERRE
	# reflections: the cellar and the shed are closed boxes (and shut the sky out); the greenhouse glass, the car
	var cp := Shell.probe(c, "dh_lights", "ProbeCave", Vector3(float(V.x0), float(V.floor), float(V.z0)), Vector3(float(V.x1), float(V.ceil), float(V.z1)),
		Vector3(108.0, -1.3, -13.1), 0.6)
	cp.ambient_mode = ReflectionProbe.AMBIENT_COLOR             # no moonlit air down here
	cp.ambient_color = Color(0.0, 0.0, 0.0)
	cp.ambient_color_energy = 0.0
	cp.cull_mask = m
	var sp := Shell.probe(c, "dh_lights", "ProbeShed", Vector3(float(S.x0), 0.0, float(S.z0)), Vector3(float(S.x1), float(S.ridge), float(S.z1)),
		Vector3(140.4, 1.4, -13.6), 0.7)
	sp.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	sp.ambient_color = Color(0.02, 0.025, 0.035)
	sp.ambient_color_energy = 1.0
	sp.cull_mask = m
	c.room_fx["probes"] = [cp, sp]
	# the stairwell of the cellar belongs to the cellar's darkness too
	var sh: Dictionary = L.SHAFT
	var st := Shell.probe(c, "dh_lights", "ProbeSteps", Vector3(float(sh.x0), float(V.floor), float(sh.z0)), Vector3(float(sh.x1) - 1.2, -0.5, float(sh.z1)),
		Vector3(112.0, -1.6, -13.1), 0.5)
	st.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	st.ambient_color = Color(0.0, 0.0, 0.0)
	st.ambient_color_energy = 0.0
	st.cull_mask = m
	(c.room_fx["probes"] as Array).append(st)
	# mist lying on the lawn, thicker in the hollows; a breath of it in the greenhouse
	_fog(c, Vector3(125.0, 0.5, 0.0), Vector3(46.0, 1.4, 38.0), 0.05, 1.6)
	_fog(c, Vector3(133.0, 0.9, -1.5), Vector3(13.0, 2.4, 12.0), 0.035, 0.8)
	_fog(c, Vector3(145.0, 1.0, 8.5), Vector3(8.0, 2.6, 8.0), 0.045, 0.6)
	_fog(c, Vector3(127.0, 1.2, 14.1), Vector3(5.6, 2.2, 3.4), 0.03)
	c.room_fx["dust"] = _dust(c, c.room_fx["cave_dust"], Vector3(2.2, 0.05, 2.0))
	# dead leaves blown against things, on the porch, on the car, down the cellar steps
	var lf := Color(1.0, 1.0, 1.0, 0.95)
	for d in [[105.2, 0.36, 1.9, 1.3, 0.4], [106.9, 0.2, -0.5, 1.2, 2.1], [108.4, 0.0, -2.6, 1.6, 1.0], [112.9, 0.6, 10.5, 1.5, 0.7], [110.3, 0.0, 12.4, 1.6, 2.6],
			[116.2, 0.0, -5.4, 1.3, 4.0], [121.8, 0.0, -3.6, 1.5, 0.2], [126.6, 0.12, -9.4, 1.4, 1.3], [138.8, 0.0, -11.4, 1.7, 5.1], [141.2, 0.06, -12.8, 1.2, 3.3],
			[126.9, 0.0, 11.6, 1.5, 2.9], [128.9, 0.02, 14.2, 1.3, 0.9], [144.9, 0.0, 6.6, 1.6, 4.4], [144.6, 0.0, 10.6, 1.4, 1.7], [113.6, 0.0, -11.9, 1.5, 3.6],
			[112.6, -1.4, -13.1, 0.9, 0.5], [119.4, 0.0, 6.1, 1.4, 2.2], [131.0, 0.0, 6.2, 1.5, 0.3], [139.0, 0.0, 2.8, 1.2, 1.9], [107.0, 0.0, 7.4, 1.5, 5.5]]:
		Shell.decal(c, "dh_decals", "decal_leaves.png", Vector3(float(d[0]), float(d[1]), float(d[2])), Vector3.UP, Vector2(float(d[3]), float(d[3])), m, lf, float(d[4]))
	# grime where the walls meet the ground, water under the windows, oil under the car, mud at the gate
	var hx: float = L.HOUSE.x1
	for wz: float in [-6.3, 6.3, 2.05]:
		Shell.decal(c, "dh_decals", "decal_water.png", Vector3(hx + 0.02, 2.2, float(wz)), Vector3.RIGHT, Vector2(1.4, 1.8), m, Color(0.12, 0.12, 0.1, 0.8))
	Shell.decal(c, "dh_decals", "decal_water.png", Vector3(hx + 0.02, 4.4, -2.05), Vector3.RIGHT, Vector2(1.5, 2.0), m, Color(0.12, 0.12, 0.1, 0.7))
	Shell.decal(c, "dh_decals", "decal_spill.png", Vector3(112.6, 0.0, 10.7), Vector3.UP, Vector2(1.6, 1.6), m, Color(0.02, 0.02, 0.025, 0.85), 0.7)
	Shell.decal(c, "dh_decals", "decal_grime.png", Vector3(105.3, 0.36, -0.1), Vector3.UP, Vector2(2.0, 1.1), m, Color(0.06, 0.05, 0.04, 0.7), 1.57)
	Shell.decal(c, "dh_decals", "decal_scuffs.png", Vector3(145.2, 0.0, 8.5), Vector3.UP, Vector2(1.6, 2.4), m, Color(0.04, 0.035, 0.03, 0.7), 1.57)
	Shell.decal(c, "dh_decals", "decal_footprints.png", Vector3(113.2, 0.0, -11.2), Vector3.UP, Vector2(0.6, 1.1), m, Color(0.03, 0.025, 0.02, 0.6), 0.5)
	Shell.decal(c, "dh_decals", "decal_footprints.png", Vector3(108.6, 0.0, 0.2), Vector3.UP, Vector2(0.6, 1.1), m, Color(0.03, 0.025, 0.02, 0.5), -1.5)
	Shell.decal(c, "dh_decals", "decal_grime.png", Vector3(108.0, -2.5, -11.0), Vector3.UP, Vector2(2.4, 1.0), m, Color(0.03, 0.03, 0.03, 0.7), 0.0)
	Shell.decal(c, "dh_decals", "decal_water.png", Vector3(105.42, -1.3, -12.2), Vector3.RIGHT, Vector2(1.6, 1.9), m, Color(0.05, 0.06, 0.05, 0.8))
	Shell.decal(c, "dh_decals", "decal_spill.png", Vector3(109.0, -2.5, -14.3), Vector3.UP, Vector2(1.5, 1.5), m, Color(0.02, 0.02, 0.02, 0.6), 1.1)
