## Things standing in the yard of chapter 3 (dehors_build.gd calls these): what the daycare left on the lawn, the
## dead car, the tool shed, the greenhouse, and the small objects the player takes or moves.
extends RefCounted

const L := preload("res://scripts/dehors/dehors_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")
const U := preload("res://scripts/dehors/dehors_util.gd")

const MASK := 1 | L.L_DH
const TERRA := Color(0.42, 0.2, 0.11)
const STEEL_BLUE := Color(0.14, 0.2, 0.28)

# ====================================================================== small objects

## An old key lying flat, authored around its middle (the ring toward -z).
static func key(k, col := Color(1.0, 0.95, 0.8)) -> void:
	var ring := PackedVector3Array()
	for j in 13:
		var a := TAU * float(j) / 12.0
		ring.append(Vector3(cos(a) * 0.016, 0.0, sin(a) * 0.016 - 0.045))
	k.tube("brass", ring, 0.004, 6, col)
	k.box("brass", Vector3(-0.004, -0.004, -0.03), Vector3(0.004, 0.004, 0.05), col)
	k.box("brass", Vector3(0.0, -0.003, 0.03), Vector3(0.018, 0.003, 0.05), col)

## Long-handled bolt cutters lying flat along x, authored around their pivot.
static func cutters(k) -> void:
	for sg: float in [-1.0, 1.0]:
		k.tube("dh_iron", PackedVector3Array([Vector3(0.0, 0.012, 0.0), Vector3(-0.2, 0.012, sg * 0.03), Vector3(-0.55, 0.012, sg * 0.075)]), 0.011, 6, Color(1.4, 1.4, 1.4))
		k.tube("rubber", PackedVector3Array([Vector3(-0.4, 0.012, sg * 0.056), Vector3(-0.57, 0.012, sg * 0.078)]), 0.016, 7, Color(0.5, 0.08, 0.06), 1.0, true)
		k.box("dh_iron", Vector3(0.0, 0.0, minf(0.0, sg * 0.03)), Vector3(0.12, 0.024, maxf(0.0, sg * 0.03)), Color(1.6, 1.6, 1.6))
	k.tube("metal", PackedVector3Array([Vector3(0.02, 0.0, 0.0), Vector3(0.02, 0.03, 0.0)]), 0.014, 8, Color.WHITE, 1.0, true)

## A child's chair (the daycare's), authored at `at`, turned by yaw.
static func small_chair(k, at: Vector3, yaw: float, col: Color) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	k.box("paintwood", Vector3(-0.13, 0.27, -0.13), Vector3(0.13, 0.295, 0.13), col, 1.0, Kit.ALL, xf)
	for lx: float in [-0.12, 0.095]:
		for lz: float in [-0.12, 0.095]:
			k.box("paintwood", Vector3(lx, 0.0, lz), Vector3(lx + 0.025, 0.27, lz + 0.025), col, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(-0.13, 0.295, 0.105), Vector3(-0.105, 0.56, 0.13), col, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(0.105, 0.295, 0.105), Vector3(0.13, 0.56, 0.13), col, 1.0, Kit.ALL, xf)
	k.box("paintwood", Vector3(-0.13, 0.44, 0.108), Vector3(0.13, 0.56, 0.127), col, 1.0, Kit.ALL, xf)

## A clay pot standing on y = 0 (authored around the centre of its base), with what is left of a plant.
static func pot(k, r: float, h: float, col: Color, plant := true, seed_ := 0) -> void:
	U.cone(k, "fabric", Vector3.ZERO, Vector3(0, h, 0), r * 0.68, r, 10, col, true)
	k.tube("fabric", PackedVector3Array([Vector3(0, h - 0.02, 0), Vector3(0, h, 0)]), r * 1.08, 10, col.darkened(0.15), 1.0, false)
	k.disc("dark", Vector3(0, h - 0.015, 0), Vector3.UP, Vector3.RIGHT, r * 0.94, 10, Color.WHITE)
	if plant:
		var rng := RandomNumberGenerator.new()
		rng.seed = 991 + seed_
		for i in 2 + rng.randi() % 3:
			var a := rng.randf() * TAU
			var ln := rng.randf_range(0.12, 0.34)
			var e := Vector3(cos(a) * ln * 0.5, h + ln, sin(a) * ln * 0.5)
			k.tube("fabric", PackedVector3Array([Vector3(0, h - 0.02, 0), Vector3(e.x * 0.5, h + ln * 0.6, e.z * 0.5), e + Vector3(cos(a) * 0.06, -0.05, sin(a) * 0.06)]),
				0.004, 4, Color(0.22, 0.17, 0.09))

## A torch battery lying on its side along x, authored around its middle.
static func battery(k) -> void:
	k.tube("plastic", PackedVector3Array([Vector3(-0.028, 0.016, 0.0), Vector3(0.022, 0.016, 0.0)]), 0.016, 9, Color(0.12, 0.2, 0.42), 1.0, true)
	k.tube("metal", PackedVector3Array([Vector3(0.022, 0.016, 0.0), Vector3(0.03, 0.016, 0.0)]), 0.016, 9, Color(0.7, 0.7, 0.7), 1.0, true)
	k.tube("metal", PackedVector3Array([Vector3(0.03, 0.016, 0.0), Vector3(0.034, 0.016, 0.0)]), 0.006, 6, Color(0.7, 0.7, 0.7), 1.0, true)

## A hurricane lantern hanging from its wire handle: authored around the top of the handle (the light is at y = -0.2).
## Returns nothing; the flame goes into the "flame" bin so its material can be dimmed alone.
static func lantern(k) -> void:
	var iron := Color(1.2, 1.1, 1.0)
	for sg: float in [-1.0, 1.0]:
		k.tube("dh_iron", PackedVector3Array([Vector3(0, 0, 0), Vector3(sg * 0.05, -0.03, 0), Vector3(sg * 0.062, -0.1, 0), Vector3(sg * 0.062, -0.28, 0)]), 0.003, 5, iron)
	k.tube("dh_rust", PackedVector3Array([Vector3(0, -0.105, 0), Vector3(0, -0.075, 0)]), 0.03, 9, Color.WHITE, 1.0, true)
	U.cone(k, "dh_rust", Vector3(0, -0.135, 0), Vector3(0, -0.105, 0), 0.05, 0.03, 9)
	k.tube("dh_rust", PackedVector3Array([Vector3(0, -0.3, 0), Vector3(0, -0.262, 0)]), 0.056, 10, Color.WHITE, 1.0, true)
	k.tube("dh_rust", PackedVector3Array([Vector3(0, -0.262, 0), Vector3(0, -0.25, 0)]), 0.04, 9, Color.WHITE, 1.0, true)
	# the chimney glass and its two guard wires; the flame inside
	k.tube("lantern_glass", PackedVector3Array([Vector3(0, -0.25, 0), Vector3(0, -0.2, 0), Vector3(0, -0.14, 0)]), 0.036, 10, Color.WHITE, 1.0, false,
		func(i: int, _a: float) -> float: return [0.9, 1.15, 0.85][i])
	k.sphere("flame", Vector3(0, -0.2, 0), 0.016, 8, 6, Color.WHITE, Vector3(1.0, 1.9, 1.0))

# ====================================================================== the lawn

static func lawn(c) -> void:
	var pk = c.kit("dh_props")
	var S: Dictionary = L.SWING
	var sx: float = S.x
	var sz: float = S.z
	var half: float = S.half
	var sh: float = S.h
	# ---- the swing set: two A frames, a top bar
	for ex: float in [-half, half]:
		for ez: float in [-0.95, 0.95]:
			pk.tube("steel_up", PackedVector3Array([Vector3(sx + ex, 0.0, sz + ez), Vector3(sx + ex, sh, sz)]), 0.028, 8, STEEL_BLUE)
			c.col_see("dh_props").box(Vector3(sx + ex - 0.05, 0.0, sz + ez - 0.05), Vector3(sx + ex + 0.05, 0.9, sz + ez + 0.05))
		pk.tube("steel_up", PackedVector3Array([Vector3(sx + ex, 0.95, sz - 0.55), Vector3(sx + ex, 0.95, sz + 0.55)]), 0.016, 6, STEEL_BLUE)
	pk.tube("steel_up", PackedVector3Array([Vector3(sx - half - 0.12, sh, sz), Vector3(sx + half + 0.12, sh, sz)]), 0.03, 8, STEEL_BLUE, 1.0, true)
	(c.room_fx["solids"] as Array).append(Rect2(sx - half - 0.1, sz - 0.6, half * 2.0 + 0.2, 1.2))
	# the seats hang from nodes dehors.gd swings; the second has lost a chain
	var pivots: Array = []
	var seats: Array = S.seats
	for i in seats.size():
		var sk = c.kit("dh_swing_%d" % i)
		if i == 0:
			for cx: float in [-0.2, 0.2]:
				sk.tube("dh_iron", PackedVector3Array([Vector3(cx, 0.0, 0.0), Vector3(cx, -1.72, 0.0)]), 0.006, 5, Color(1.3, 1.3, 1.3))
			sk.rbox("plastic", Vector3(-0.24, -1.76, -0.085), Vector3(0.24, -1.725, 0.085), 0.012, 2, Color(0.5, 0.08, 0.06))
		else:
			sk.tube("dh_iron", PackedVector3Array([Vector3(-0.2, 0.0, 0.0), Vector3(-0.2, -1.4, 0.0)]), 0.006, 5, Color(1.3, 1.3, 1.3))
			sk.tube("dh_iron", PackedVector3Array([Vector3(0.2, 0.0, 0.0), Vector3(0.2, -0.5, 0.0)]), 0.006, 5, Color(1.3, 1.3, 1.3))
			sk.rbox("plastic", Vector3(-0.285, -1.88, -0.085), Vector3(-0.25, -1.4, 0.085), 0.012, 2, Color(0.1, 0.2, 0.44),
				1.0, Transform3D(Basis(Vector3.BACK, 0.1), Vector3(0.06, 0.0, 0.0)))
		pivots.append(Vector3(sx + float(seats[i]), sh - 0.03, sz))
	c.room_fx["swing_pivots"] = pivots
	# an overturned tricycle in the long grass, a ball that has lost its air
	var tx := sx + 2.3
	var tz := sz + 1.6
	for w in [[Vector3(tx, 0.16, tz), 0.16], [Vector3(tx + 0.5, 0.1, tz - 0.18), 0.1], [Vector3(tx + 0.52, 0.1, tz + 0.2), 0.1]]:
		var wc: Vector3 = w[0]
		var wr: float = w[1]
		var ring := PackedVector3Array()
		for j in 13:
			var a := TAU * float(j) / 12.0
			ring.append(wc + Vector3(cos(a) * wr, sin(a) * wr * 0.35, sin(a) * wr * 0.93))
		pk.tube("rubber", ring, 0.02, 6, Color(0.05, 0.05, 0.05))
	pk.tube("steel_up", PackedVector3Array([Vector3(tx, 0.16, tz), Vector3(tx + 0.22, 0.3, tz), Vector3(tx + 0.5, 0.12, tz)]), 0.014, 6, Color(0.5, 0.08, 0.06))
	pk.tube("steel_up", PackedVector3Array([Vector3(tx + 0.5, 0.1, tz - 0.2), Vector3(tx + 0.5, 0.1, tz + 0.22)]), 0.01, 6, Color(0.5, 0.08, 0.06))
	pk.tube("steel_up", PackedVector3Array([Vector3(tx + 0.02, 0.2, tz - 0.2), Vector3(tx + 0.02, 0.3, tz + 0.2)]), 0.01, 6, Color(0.4, 0.4, 0.4))
	pk.sphere("plastic", Vector3(sx - 2.4, 0.08, sz - 1.3), 0.11, 12, 8, Color(0.55, 0.42, 0.08), Vector3(1.0, 0.72, 1.0))
	# ---- the sandbox: a frame of boards, damp sand, a bucket, a spade, a truck
	var B: Dictionary = L.SANDBOX
	var bx0: float = B.x0
	var bx1: float = B.x1
	var bz0: float = B.z0
	var bz1: float = B.z1
	pk.box("dh_sand", Vector3(bx0, 0.0, bz0), Vector3(bx1, 0.1, bz1), Color.WHITE, 1.0, Kit.FACE_PY)
	for r in [[bx0 - 0.07, bz0 - 0.07, bx1 + 0.07, bz0], [bx0 - 0.07, bz1, bx1 + 0.07, bz1 + 0.07], [bx0 - 0.07, bz0, bx0, bz1], [bx1, bz0, bx1 + 0.07, bz1]]:
		pk.box("dh_planks", Vector3(float(r[0]), 0.0, float(r[1])), Vector3(float(r[2]), 0.2, float(r[3])), Color(0.75, 0.7, 0.6))
		c.col("dh_props").box(Vector3(float(r[0]), 0.0, float(r[1])), Vector3(float(r[2]), 0.2, float(r[3])))
	c.col("dh_props").box(Vector3(bx0, 0.0, bz0), Vector3(bx1, 0.1, bz1))
	U.cone(pk, "plastic", Vector3(bx0 + 0.7, 0.1, bz0 + 0.8), Vector3(bx0 + 0.7, 0.28, bz0 + 0.8), 0.07, 0.1, 10, Color(0.5, 0.08, 0.06), true)
	pk.sphere("dh_sand", Vector3(bx0 + 1.3, 0.1, bz0 + 1.5), 0.24, 10, 6, Color.WHITE, Vector3(1.0, 0.55, 1.0))
	pk.box("plastic", Vector3(bx0 + 1.6, 0.1, bz0 + 0.5), Vector3(bx0 + 1.9, 0.19, bz0 + 0.66), Color(0.55, 0.42, 0.08))
	pk.box("plastic", Vector3(bx0 + 1.62, 0.19, bz0 + 0.52), Vector3(bx0 + 1.74, 0.27, bz0 + 0.64), Color(0.1, 0.2, 0.44))
	pk.tube("plastic", PackedVector3Array([Vector3(bx0 + 0.4, 0.12, bz0 + 1.8), Vector3(bx0 + 0.75, 0.14, bz0 + 2.0)]), 0.012, 6, Color(0.1, 0.32, 0.14))
	pk.box("plastic", Vector3(bx0 + 0.72, 0.11, bz0 + 1.94), Vector3(bx0 + 0.9, 0.13, bz0 + 2.1), Color(0.1, 0.32, 0.14))
	# ---- the playhouse: four walls of boards the height of a child, a roof, a door for small people
	var C: Dictionary = L.CABANE
	var cx: float = C.x
	var cz: float = C.z
	var ch: float = C.half
	var wh: float = C.h
	var yel := Color(0.8, 0.66, 0.34)
	var ck = c.kit("dh_cabane")
	var t := 0.04
	ck.wall("dh_planks", Vector2(cx - ch, cz - ch), Vector2(cx - ch, cz + ch), t, 0.0, wh, [], yel)
	ck.wall("dh_planks", Vector2(cx - ch, cz - ch), Vector2(cx + ch, cz - ch), t, 0.0, wh, [[ch - 0.25, ch + 0.25, 0.62, 1.0]], yel)
	ck.wall("dh_planks", Vector2(cx - ch, cz + ch), Vector2(cx + ch, cz + ch), t, 0.0, wh, [[ch - 0.25, ch + 0.25, 0.62, 1.0]], yel)
	ck.wall("dh_planks", Vector2(cx + ch, cz - ch), Vector2(cx + ch, cz + ch), t, 0.0, wh, [[ch - 0.3, ch + 0.3, 0.0, 1.05]], yel)
	for zz: float in [cz - ch, cz + ch]:
		for s in 3:
			ck.box("dh_planks", Vector3(cx - 0.25, 0.68 + 0.11 * float(s), zz - 0.03), Vector3(cx + 0.25, 0.72 + 0.11 * float(s), zz + 0.03), Color(0.5, 0.42, 0.3),
				1.0, Kit.ALL, Transform3D.IDENTITY)
	ck.box("dh_deck", Vector3(cx - ch, 0.0, cz - ch), Vector3(cx + ch, 0.03, cz + ch), Color(0.5, 0.5, 0.5), 1.0, Kit.FACE_PY)
	# gables east and west, two roof slopes with their ridge along x
	var rh := 0.5
	for xx: float in [cx - ch - 0.02, cx + ch + 0.02]:
		var nrm := Vector3.LEFT if xx < cx else Vector3.RIGHT
		ck.tri("dh_planks", Vector3(xx, wh, cz - ch), Vector3(xx, wh, cz + ch), Vector3(xx, wh + rh, cz), nrm,
			Vector2(cz - ch, -wh) / 0.9, Vector2(cz + ch, -wh) / 0.9, Vector2(cz, -wh - rh) / 0.9, yel)
		ck.tri("dh_planks", Vector3(xx, wh, cz - ch), Vector3(xx, wh, cz + ch), Vector3(xx, wh + rh, cz), -nrm,
			Vector2(cz - ch, -wh) / 0.9, Vector2(cz + ch, -wh) / 0.9, Vector2(cz, -wh - rh) / 0.9, Color(0.2, 0.18, 0.14))
	var slope := atan2(rh, ch)
	var sl := sqrt(rh * rh + ch * ch) + 0.16
	for sg: float in [-1.0, 1.0]:
		var rx := Transform3D(Basis(Vector3.RIGHT, sg * slope), Vector3(cx, wh + rh + 0.02, cz))
		ck.box("paintwood", Vector3(-ch - 0.14, -0.03, minf(0.0, sg * sl)), Vector3(ch + 0.14, 0.0, maxf(0.0, sg * sl)), Color(0.42, 0.13, 0.1), 1.0, Kit.ALL, rx)
	Shell.sign_quad(ck, "cut_sun_decal.png", Vector3(cx + ch + 0.024, 1.24, cz), Vector3.RIGHT, 0.34, 0.34, Rect2(0, 0, 1, 1), Color(0.6, 0.6, 0.55))
	U.solid(c, "dh_cabane", Vector3(cx - ch - 0.03, 0.0, cz - ch - 0.03), Vector3(cx + ch + 0.03, wh + rh, cz + ch + 0.03))
	# a drawing pinned beside the door
	var dn := Vector3(cx + ch + 0.024, 0.78, cz + 0.56)
	ck.quad("debris_paper", dn + Vector3(0, -0.11, 0.08), dn + Vector3(0, -0.11, -0.08), dn + Vector3(0, 0.11, -0.08), dn + Vector3(0, 0.11, 0.08), Vector3.RIGHT,
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.84, 0.82, 0.72))
	c.room_fx["note_cabane"] = dn
	c.room_fx["hide_cabane"] = {"door": Vector3(cx + ch, 0.6, cz), "hide_pos": Vector3(cx - 0.15, 0.86, cz), "hide_yaw": -PI * 0.5,
		"exit_pos": Vector3(cx + ch + 0.75, 0.0, cz)}
	# ---- the kennel: a box of boards with a felt roof, its mouth to the west
	var N: Dictionary = L.NICHE
	var nx: float = N.x
	var nz: float = N.z
	var hx: float = N.hx
	var hz: float = N.hz
	var nh: float = N.h
	var nk = c.kit("dh_niche")
	nk.wall("dh_planks", Vector2(nx - hx, nz - hz), Vector2(nx - hx, nz + hz), t, 0.0, nh, [[hz - 0.3, hz + 0.3, 0.0, 0.62]], Color(0.6, 0.6, 0.6))
	nk.wall("dh_planks", Vector2(nx + hx, nz - hz), Vector2(nx + hx, nz + hz), t, 0.0, nh, [], Color(0.6, 0.6, 0.6))
	nk.wall("dh_planks", Vector2(nx - hx, nz - hz), Vector2(nx + hx, nz - hz), t, 0.0, nh, [], Color(0.6, 0.6, 0.6))
	nk.wall("dh_planks", Vector2(nx - hx, nz + hz), Vector2(nx + hx, nz + hz), t, 0.0, nh, [], Color(0.6, 0.6, 0.6))
	nk.box("dark", Vector3(nx - hx, 0.0, nz - hz), Vector3(nx + hx, 0.02, nz + hz), Color.WHITE, 1.0, Kit.FACE_PY)
	for sg: float in [-1.0, 1.0]:
		var rx := Transform3D(Basis(Vector3.RIGHT, sg * 0.5), Vector3(nx, nh + 0.3, nz))
		nk.box("roof", Vector3(-hx - 0.12, -0.03, minf(0.0, sg * 0.72)), Vector3(hx + 0.12, 0.0, maxf(0.0, sg * 0.72)), Color.WHITE, 1.0, Kit.ALL, rx)
	for xx: float in [nx - hx - 0.02, nx + hx + 0.02]:
		for nrm in [Vector3.LEFT, Vector3.RIGHT]:
			nk.tri("dh_planks", Vector3(xx, nh, nz - hz), Vector3(xx, nh, nz + hz), Vector3(xx, nh + 0.3, nz), nrm,
				Vector2(nz - hz, -nh) / 0.9, Vector2(nz + hz, -nh) / 0.9, Vector2(nz, -nh - 0.3) / 0.9, Color(0.6, 0.6, 0.6))
	U.solid(c, "dh_niche", Vector3(nx - hx - 0.03, 0.0, nz - hz - 0.03), Vector3(nx + hx + 0.03, nh + 0.3, nz + hz + 0.03))
	# a stake, a length of chain lying in the grass, an empty collar; a tin bowl
	pk.tube("dh_planks", PackedVector3Array([Vector3(nx - hx - 0.9, 0.0, nz + 0.7), Vector3(nx - hx - 0.9, 0.3, nz + 0.7)]), 0.03, 6, Color.WHITE)
	var chain := PackedVector3Array()
	for j in 12:
		var u := float(j) / 11.0
		chain.append(Vector3(nx - hx - 0.9 + 0.75 * u, maxf(0.012, 0.26 * (1.0 - u * 3.0)), nz + 0.7 - 0.5 * u + 0.12 * sin(u * 9.0)))
	pk.tube("dh_iron", chain, 0.009, 5, Color(1.3, 1.3, 1.3))
	U.cone(pk, "metal", Vector3(nx - hx - 0.5, 0.0, nz - 0.5), Vector3(nx - hx - 0.5, 0.06, nz - 0.5), 0.09, 0.13, 10, Color(0.7, 0.7, 0.7))
	c.room_fx["hide_niche"] = {"door": Vector3(nx - hx, 0.35, nz), "hide_pos": Vector3(nx + 0.12, 0.6, nz), "hide_yaw": PI * 0.5,
		"exit_pos": Vector3(nx - hx - 0.75, 0.0, nz)}
	# ---- a clothes line between two posts: one sheet left on it since that autumn
	var lz := 3.4
	for px: float in [122.2, 126.4]:
		pk.tube("dh_planks", PackedVector3Array([Vector3(px, 0.0, lz), Vector3(px, 1.95, lz)]), 0.035, 7, Color.WHITE)
		pk.box("dh_planks", Vector3(px - 0.03, 1.86, lz - 0.4), Vector3(px + 0.03, 1.92, lz + 0.4), Color.WHITE)
		U.solid(c, "dh_props", Vector3(px - 0.06, 0.0, lz - 0.06), Vector3(px + 0.06, 1.95, lz + 0.06), true)
	pk.tube("dh_iron", PackedVector3Array([Vector3(122.2, 1.9, lz), Vector3(124.3, 1.8, lz), Vector3(126.4, 1.9, lz)]), 0.003, 4, Color(2.0, 2.0, 2.0))
	var shk = c.kit("dh_linen")
	var P := PackedVector3Array()
	var UV := PackedVector2Array()
	var rows := 9
	var cols := 12
	for r in rows:
		var v := float(r) / float(rows - 1)
		for q in cols:
			var u := float(q) / float(cols - 1)
			var fold := 0.05 * sin(u * 11.0 + v * 2.0) * v + 0.025 * sin(u * 23.0 + 1.0) * v
			P.append(Vector3(123.3 + 1.7 * u, 1.82 - 1.25 * v - 0.03 * sin(u * PI), lz + fold))
			UV.append(Vector2(u * 1.7, v * 1.25))
	shk.grid("sheet", P, rows, cols, UV, Color(0.9, 0.9, 0.9))
	# ---- heaps of pebbles at the edge of the gravel (to pick up and throw)
	var heaps := [Vector3(118.6, 0.0, 6.2), Vector3(143.2, 0.0, 10.9), Vector3(125.4, 0.0, 10.8)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for hp in heaps:
		for i in 16:
			var a := rng.randf() * TAU
			var rr := rng.randf() * 0.2
			var pr := rng.randf_range(0.022, 0.04)
			var g := rng.randf_range(0.5, 1.0)
			pk.sphere("dh_stone", (hp as Vector3) + Vector3(cos(a) * rr, pr * 0.6 + 0.05 * (1.0 - rr / 0.2), sin(a) * rr), pr, 6, 4, Color(g, g, g), Vector3(1.0, 0.7, 1.0))
	c.room_fx["pebbles"] = heaps
	# the pebble that flies (dehors.gd): one small stone of its own
	c.kit("dh_pebble").sphere("dh_stone", Vector3.ZERO, 0.03, 6, 4, Color(1.6, 1.6, 1.6), Vector3(1.0, 0.75, 1.0))

## What else has been left in the garden: a rain barrel under the downpipe, the wood for a winter that was not
## spent here, a wheelbarrow, a bench under the oak, and the scarecrow of the kitchen garden.
static func garden(c) -> void:
	var pk = c.kit("dh_props")
	var hx: float = L.HOUSE.x1
	# rain barrel at the north corner of the house
	var rb := Vector3(hx + 0.55, 0.0, float(L.HOUSE.z0) + 0.9)
	pk.tube("dh_rust", PackedVector3Array([rb, rb + Vector3(0, 0.45, 0), rb + Vector3(0, 0.92, 0)]), 0.3, 14, Color(0.5, 0.8, 1.0), 1.0, false,
		func(i: int, _a: float) -> float: return [0.92, 1.05, 0.95][i])
	pk.disc("wet", rb + Vector3(0, 0.86, 0), Vector3.UP, Vector3.RIGHT, 0.27, 14, Color.WHITE)
	U.solid(c, "dh_props", rb + Vector3(-0.32, 0.0, -0.32), rb + Vector3(0.32, 0.92, 0.32))
	# the wood pile against the north fence: split logs, their pale ends to the yard
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var wz: float = float(L.YARD.z0) + 0.22
	for row in 4:
		var lx := 120.1 + 0.11 * float(row % 2)
		while lx < 123.0 - 0.1 * float(row):
			var r := rng.randf_range(0.085, 0.12)
			var ly := 0.1 + 0.2 * float(row) + rng.randf_range(-0.01, 0.01)
			var ln := rng.randf_range(0.42, 0.52)
			pk.tube("dh_bark", PackedVector3Array([Vector3(lx, ly, wz), Vector3(lx, ly, wz + ln)]), r, 7, Color.WHITE)
			pk.disc("dh_planks", Vector3(lx, ly, wz + ln), Vector3.BACK, Vector3.UP, r, 7, Color(1.3, 1.2, 1.0))
			lx += r * 2.0 + rng.randf_range(0.0, 0.03)
	U.solid(c, "dh_props", Vector3(120.0, 0.0, wz - 0.1), Vector3(123.0, 0.85, wz + 0.55))
	# a wheelbarrow tipped on its nose by the shed
	var wb := Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.BACK, 0.28), Vector3(136.6, 0.18, -11.4))
	pk.box("dh_rust", Vector3(-0.42, 0.12, -0.3), Vector3(0.42, 0.16, 0.3), Color(0.7, 0.9, 0.8), 1.0, Kit.ALL, wb)
	for sz in [-0.3, 0.28]:
		pk.box("dh_rust", Vector3(-0.42, 0.16, sz), Vector3(0.42, 0.42, sz + 0.02), Color(0.7, 0.9, 0.8), 1.0, Kit.ALL, wb)
	pk.box("dh_rust", Vector3(-0.44, 0.16, -0.3), Vector3(-0.42, 0.42, 0.3), Color(0.7, 0.9, 0.8), 1.0, Kit.ALL, wb)
	pk.box("dh_rust", Vector3(0.42, 0.16, -0.3), Vector3(0.44, 0.36, 0.3), Color(0.7, 0.9, 0.8), 1.0, Kit.ALL, wb)
	pk.tube("rubber", PackedVector3Array([wb * Vector3(-0.62, 0.0, -0.04), wb * Vector3(-0.62, 0.0, 0.04)]), 0.17, 10, Color(0.05, 0.05, 0.05), 1.0, true)
	for sz in [-0.26, 0.26]:
		pk.tube("dh_planks", PackedVector3Array([wb * Vector3(-0.62, 0.0, sz * 0.3), wb * Vector3(0.3, 0.1, sz), wb * Vector3(1.0, 0.2, sz)]), 0.018, 6, Color.WHITE)
	U.solid(c, "dh_props", Vector3(136.0, 0.0, -11.95), Vector3(137.3, 0.6, -10.85))
	# the bench under the oak, turned to the house
	var bx: float = L.OAK.x - 1.7
	var bz: float = L.OAK.z + 1.9
	for sz in [-0.7, 0.66]:
		pk.box("dh_iron", Vector3(bx - 0.2, 0.0, bz + sz), Vector3(bx + 0.24, 0.42, bz + sz + 0.04), Color(1.2, 1.2, 1.2))
		pk.box("dh_iron", Vector3(bx + 0.2, 0.42, bz + sz), Vector3(bx + 0.24, 0.86, bz + sz + 0.04), Color(1.2, 1.2, 1.2))
	for i in 3:
		pk.box("dh_planks", Vector3(bx - 0.2 + 0.14 * float(i), 0.42, bz - 0.75), Vector3(bx - 0.08 + 0.14 * float(i), 0.45, bz + 0.75), Color(0.75, 0.75, 0.72))
	for i in 2:
		pk.box("dh_planks", Vector3(bx + 0.2, 0.56 + 0.16 * float(i), bz - 0.75), Vector3(bx + 0.23, 0.68 + 0.16 * float(i), bz + 0.75), Color(0.75, 0.75, 0.72))
	U.solid(c, "dh_props", Vector3(bx - 0.22, 0.0, bz - 0.76), Vector3(bx + 0.26, 0.86, bz + 0.76))
	# the kitchen garden east of the greenhouse: rows gone to weed, and what was meant to keep the birds off
	var sc := Vector3(135.4, 0.0, 13.3)
	var sxf := Transform3D(Basis(Vector3.UP, 2.5) * Basis(Vector3.BACK, 0.06), sc)
	var k = c.kit("dh_scarecrow")
	k.tube("dh_planks", PackedVector3Array([sxf * Vector3(0, -0.1, 0), sxf * Vector3(0, 1.9, 0)]), 0.03, 6, Color.WHITE)
	k.tube("dh_planks", PackedVector3Array([sxf * Vector3(-0.78, 1.42, 0), sxf * Vector3(0.78, 1.46, 0)]), 0.025, 6, Color.WHITE)
	k.rbox("fabric", Vector3(-0.23, 0.78, -0.1), Vector3(0.23, 1.5, 0.1), 0.07, 2, Color(0.11, 0.1, 0.1), 1.0, sxf)
	for sg in [-1.0, 1.0]:
		k.rbox("fabric", Vector3(minf(sg * 0.2, sg * 0.74), 1.3, -0.07), Vector3(maxf(sg * 0.2, sg * 0.74), 1.52, 0.07), 0.05, 2, Color(0.11, 0.1, 0.1), 1.0, sxf)
		# empty cuffs hanging, a glove on one
		k.rbox("fabric", Vector3(sg * 0.74 - 0.05, 1.06, -0.05), Vector3(sg * 0.74 + 0.05, 1.34, 0.05), 0.03, 2, Color(0.1, 0.09, 0.09), 1.0, sxf)
	k.rbox("fabric", Vector3(-0.2, 0.4, -0.09), Vector3(0.2, 0.8, 0.09), 0.06, 2, Color(0.09, 0.09, 0.1), 1.0, sxf)          # the tails of the coat
	k.sphere("fabric", sxf * Vector3(0, 1.67, 0.0), 0.135, 12, 8, Color(0.5, 0.45, 0.34), Vector3(0.95, 1.15, 0.95))        # a sack for a head
	k.disc("fabric", sxf * Vector3(0, 1.79, 0), sxf.basis * Vector3.UP, sxf.basis * Vector3.RIGHT, 0.25, 12, Color(0.07, 0.07, 0.07))
	k.disc("fabric", sxf * Vector3(0, 1.788, 0), sxf.basis * Vector3.DOWN, sxf.basis * Vector3.RIGHT, 0.25, 12, Color(0.07, 0.07, 0.07))
	U.cone(k, "fabric", sxf * Vector3(0, 1.79, 0), sxf * Vector3(0, 1.93, 0), 0.13, 0.1, 10, Color(0.07, 0.07, 0.07), true)
	U.solid(c, "dh_scarecrow", sc + Vector3(-0.12, 0.0, -0.12), sc + Vector3(0.12, 1.9, 0.12), true)
	var tk = c.kit("dh_tufts")
	for i in 22:
		var p := Vector3(133.4 + rng.randf() * 4.2, -0.02, 12.2 + 0.75 * float(i % 4) + rng.randf_range(-0.1, 0.1))
		if p.distance_to(sc) > 0.5:
			U.card(tk, p, 0.7, rng.randf_range(0.35, 0.7), Rect2(0.754, 0.02, 0.242, 0.97), rng.randf() * PI, 2, Color(0.8, 0.75, 0.6), "dh_tuft", true)

# ====================================================================== the dead car

static func car(c) -> void:
	var k = c.kit("dh_car")
	var gk = c.kit("dh_car_glass")
	var C: Dictionary = L.CAR
	var node: Node3D = c.region("dh_car")
	var cx: float = C.x
	var cz: float = C.z
	node.position = Vector3(cx, 0.0, cz)
	node.rotation = Vector3(0.012, 0.0, -0.014)            # it sits on a flat tyre
	c.region("dh_car_glass").transform = node.transform
	var red := Color.WHITE
	# lower body, sills, bumpers
	k.rbox("dh_car", Vector3(-2.08, 0.3, -0.83), Vector3(2.08, 0.84, 0.83), 0.07, 3, red, 0.9)
	k.box("dark", Vector3(-1.9, 0.2, -0.78), Vector3(1.9, 0.32, 0.78), Color.WHITE)
	for bx in [[2.06, 2.18], [-2.18, -2.06]]:
		k.rbox("metal", Vector3(float(bx[0]), 0.36, -0.82), Vector3(float(bx[1]), 0.49, 0.82), 0.025, 2, Color(0.55, 0.55, 0.55))
	# cabin of an estate car: a long roof, pillars, glass (none left in the driver's door), an upright tailgate
	k.rbox("dh_car", Vector3(-2.0, 1.31, -0.69), Vector3(0.3, 1.37, 0.69), 0.025, 2, red, 0.9)
	for sg: float in [-1.0, 1.0]:
		k.tube("dh_car", PackedVector3Array([Vector3(0.78, 0.83, sg * 0.77), Vector3(0.29, 1.33, sg * 0.67)]), 0.03, 6, red)
		k.tube("dh_car", PackedVector3Array([Vector3(-0.3, 0.83, sg * 0.79), Vector3(-0.3, 1.33, sg * 0.68)]), 0.03, 6, red)
		k.tube("dh_car", PackedVector3Array([Vector3(-1.34, 0.83, sg * 0.79), Vector3(-1.34, 1.33, sg * 0.68)]), 0.03, 6, red)
		k.tube("dh_car", PackedVector3Array([Vector3(-2.04, 0.83, sg * 0.77), Vector3(-1.97, 1.33, sg * 0.67)]), 0.035, 6, red)
		# side glass behind the front doors on both sides, front side glass on the right only
		for gx in [[-1.31, -0.33], [-2.0, -1.37]]:
			gk.quad("dh_glass", Vector3(float(gx[0]), 0.84, sg * 0.785), Vector3(float(gx[1]), 0.84, sg * 0.79), Vector3(float(gx[1]), 1.31, sg * 0.685),
				Vector3(float(gx[0]), 1.31, sg * 0.68), Vector3(0, 0.2, sg).normalized(), Vector2(0, 0.6), Vector2(1, 0.6), Vector2(1, 0), Vector2(0, 0))
		if sg > 0.0:
			gk.quad("dh_glass", Vector3(-0.27, 0.84, sg * 0.79), Vector3(0.75, 0.84, sg * 0.775), Vector3(0.28, 1.31, sg * 0.675), Vector3(-0.27, 1.31, sg * 0.685),
				Vector3(0, 0.2, sg).normalized(), Vector2(0, 0.6), Vector2(1, 0.6), Vector2(0.55, 0), Vector2(0, 0))
		# door seams and handles
		for dx: float in [-1.34, -0.3, 0.78]:
			k.box("dark", Vector3(dx - 0.004, 0.34, sg * 0.832 - 0.003), Vector3(dx + 0.004, 0.84, sg * 0.832 + 0.003), Color.WHITE)
		for dx: float in [-0.5, 0.56]:
			k.box("metal", Vector3(dx, 0.72, sg * 0.835 - 0.012), Vector3(dx + 0.12, 0.745, sg * 0.835 + 0.012), Color(0.6, 0.6, 0.6))
	gk.quad("dh_glass", Vector3(0.78, 0.84, -0.75), Vector3(0.78, 0.84, 0.75), Vector3(0.3, 1.32, 0.66), Vector3(0.3, 1.32, -0.66), Vector3(0.7, 0.7, 0).normalized(),
		Vector2(0, 0.5), Vector2(1.4, 0.5), Vector2(1.3, 0), Vector2(0.1, 0))
	gk.quad("dh_glass", Vector3(-2.06, 0.86, -0.72), Vector3(-2.06, 0.86, 0.72), Vector3(-1.99, 1.3, 0.64), Vector3(-1.99, 1.3, -0.64), Vector3(-1.0, 0.15, 0).normalized(),
		Vector2(0, 0.5), Vector2(1.4, 0.5), Vector2(1.3, 0), Vector2(0.1, 0))
	k.box("dark", Vector3(-2.085, 0.5, -0.7), Vector3(-2.078, 0.84, 0.7), Color.WHITE)             # the seam of the tailgate
	k.box("metal", Vector3(-2.1, 0.74, -0.1), Vector3(-2.08, 0.77, 0.1), Color(0.6, 0.6, 0.6))
	# inside: two front seats, a bench, the dashboard, the wheel
	for sz: float in [-0.4, 0.4]:
		k.rbox("fabric", Vector3(-0.2, 0.5, sz - 0.26), Vector3(0.32, 0.64, sz + 0.26), 0.05, 2, Color(0.2, 0.17, 0.13))
		k.rbox("fabric", Vector3(-0.3, 0.6, sz - 0.25), Vector3(-0.16, 1.18, sz + 0.25), 0.05, 2, Color(0.2, 0.17, 0.13),
			1.0, Transform3D(Basis(Vector3.BACK, 0.16), Vector3(0.1, 0.0, 0.0)))
	k.rbox("fabric", Vector3(-1.2, 0.5, -0.7), Vector3(-0.68, 0.64, 0.7), 0.05, 2, Color(0.2, 0.17, 0.13))
	k.rbox("fabric", Vector3(-1.34, 0.6, -0.7), Vector3(-1.2, 1.12, 0.7), 0.05, 2, Color(0.2, 0.17, 0.13))
	k.box("fabric", Vector3(-2.02, 0.5, -0.74), Vector3(-1.34, 0.56, 0.74), Color(0.12, 0.11, 0.1))          # the boot: a blanket, room to lie down
	k.rbox("fabric", Vector3(-1.95, 0.56, 0.2), Vector3(-1.45, 0.64, 0.7), 0.03, 2, Color(0.3, 0.14, 0.12))
	k.rbox("rubber", Vector3(0.62, 0.72, -0.74), Vector3(0.92, 0.9, 0.74), 0.04, 2, Color(0.06, 0.06, 0.06))
	k.box("dark", Vector3(-2.02, 0.3, -0.76), Vector3(0.9, 0.5, 0.76), Color.WHITE, 1.0, Kit.FACE_PY)
	var wheel := PackedVector3Array()
	for j in 13:
		var a := TAU * float(j) / 12.0
		wheel.append(Vector3(0.56 + sin(a) * 0.05, 0.98 + cos(a) * 0.16, -0.4 + sin(a) * 0.16))
	k.tube("rubber", wheel, 0.013, 6, Color(0.05, 0.05, 0.05))
	k.tube("rubber", PackedVector3Array([Vector3(0.56, 0.98, -0.4), Vector3(0.72, 0.86, -0.4)]), 0.02, 6, Color(0.05, 0.05, 0.05))
	# wheels (the front left is flat), hub caps
	for w in [[1.3, -0.74, 0.27], [1.3, 0.74, 0.31], [-1.3, -0.74, 0.31], [-1.3, 0.74, 0.31]]:
		var wx := float(w[0])
		var wz := float(w[1])
		var wr := float(w[2])
		k.tube("rubber", PackedVector3Array([Vector3(wx, wr, wz - 0.1), Vector3(wx, wr, wz + 0.1)]), wr, 14, Color(0.05, 0.05, 0.05), 1.0, true)
		k.disc("metal", Vector3(wx, wr, wz + signf(wz) * 0.102), Vector3(0, 0, signf(wz)), Vector3.UP, wr * 0.55, 12, Color(0.5, 0.5, 0.5))
	# face: grille, two round lamps (one gone), plate; tail lamps
	k.box("dark", Vector3(2.075, 0.52, -0.45), Vector3(2.09, 0.72, 0.45), Color.WHITE)
	k.disc("enamel", Vector3(2.092, 0.63, -0.62), Vector3.RIGHT, Vector3.UP, 0.1, 14, Color(0.9, 0.9, 0.86))
	k.disc("dark", Vector3(2.092, 0.63, 0.62), Vector3.RIGHT, Vector3.UP, 0.1, 14, Color.WHITE)
	k.box("enamel", Vector3(2.182, 0.38, -0.24), Vector3(2.19, 0.48, 0.24), Color(0.7, 0.68, 0.4))
	for tz: float in [-0.62, 0.62]:
		k.box("plastic", Vector3(-2.09, 0.58, tz - 0.14), Vector3(-2.075, 0.7, tz + 0.14), Color(0.42, 0.04, 0.03))
	k.box("metal", Vector3(0.68, 0.86, -0.92), Vector3(0.76, 0.93, -0.83), Color(0.5, 0.5, 0.5))
	# a newspaper on the driver's seat
	var paper := Vector3(0.08, 0.645, -0.4)
	k.quad("debris_paper", paper + Vector3(-0.14, 0, 0.1), paper + Vector3(0.14, 0, 0.1), paper + Vector3(0.14, 0, -0.1), paper + Vector3(-0.14, 0, -0.1),
		Vector3.UP, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.62, 0.6, 0.52))
	var cl = c.col("dh_car")
	cl.box(Vector3(-2.16, 0.0, -0.85), Vector3(2.16, 0.86, 0.85))
	cl.box(Vector3(-2.06, 0.86, -0.76), Vector3(0.78, 1.38, 0.76))
	(c.room_fx["solids"] as Array).append(Rect2(cx - 2.2, cz - 0.87, 4.4, 1.74))
	c.room_fx["note_car"] = node.transform * (paper + Vector3(0.0, 0.06, 0.0))
	c.room_fx["horn"] = node.transform * Vector3(0.52, 1.0, -0.42)
	# the tailgate: the way into the boot (a hiding place; the player looks out through the rear window)
	c.room_fx["hide_car"] = {"door": node.transform * Vector3(-2.1, 0.8, 0.0), "hide_pos": Vector3(cx - 1.6, 1.0, cz), "hide_yaw": PI * 0.5,
		"exit_pos": Vector3(cx - 2.85, 0.0, cz)}

# ====================================================================== la remise

static func shed(c) -> void:
	var k = c.kit("dh_shed")
	var pk = c.kit("dh_shed_props")
	var cl = c.col("dh_shed")
	var S: Dictionary = L.SHED
	var D: Dictionary = L.SHED_DOOR
	var x0: float = S.x0
	var x1: float = S.x1
	var z0: float = S.z0
	var z1: float = S.z1
	var eave: float = S.eave
	var ridge: float = S.ridge
	var t := 0.1
	var dx0: float = D.x0
	var dx1: float = D.x1
	var dh: float = D.h
	k.box("dh_deck", Vector3(x0 - t, 0.0, z0 - t), Vector3(x1 + t, 0.05, z1 + t), Color(0.6, 0.6, 0.6), 1.0, Kit.FACE_PY | Kit.FACE_PZ)
	cl.box(Vector3(x0 - t, 0.0, z0 - t), Vector3(x1 + t, 0.05, z1 + t))
	var wx0 := x0 - t
	Shell.wall(c, "dh_shed", "dh_planks", Vector2(wx0, z1 + t * 0.5), Vector2(x1 + t, z1 + t * 0.5), t, 0.05, eave, [[dx0 - wx0, dx1 - wx0, 0.05, dh]])
	Shell.wall(c, "dh_shed", "dh_planks", Vector2(wx0, z0 - t * 0.5), Vector2(x1 + t, z0 - t * 0.5), t, 0.05, eave)
	Shell.wall(c, "dh_shed", "dh_planks", Vector2(x1 + t * 0.5, z0 - t), Vector2(x1 + t * 0.5, z1 + t), t, 0.05, eave)
	# west wall: a small window looking over the lawn
	var wz0 := z0 + 1.2
	var wz1 := z0 + 1.95
	Shell.wall(c, "dh_shed", "dh_planks", Vector2(x0 - t * 0.5, z0 - t), Vector2(x0 - t * 0.5, z1 + t), t, 0.05, eave, [[wz0 - (z0 - t), wz1 - (z0 - t), 1.15, 1.7]])
	Shell.sign_quad(c.kit("dh_shed_glass"), "dh_glass", Vector3(x0 - t * 0.5, 1.425, (wz0 + wz1) * 0.5), Vector3.LEFT, wz1 - wz0, 0.55)
	for fz: float in [wz0, wz1 - 0.03]:
		k.box("paintwood", Vector3(x0 - t - 0.015, 1.12, fz), Vector3(x0 + 0.015, 1.73, fz + 0.03), Color(0.4, 0.4, 0.38))
	for fy: float in [1.12, 1.7]:
		k.box("paintwood", Vector3(x0 - t - 0.015, fy, wz0), Vector3(x0 + 0.015, fy + 0.03, wz1), Color(0.4, 0.4, 0.38))
	cl.box(Vector3(x0 - t, 1.15, wz0), Vector3(x0, 1.7, wz1))
	var sol: Array = c.room_fx["solids"]
	sol.append(Rect2(x0 - t, z0 - t, x1 - x0 + 2 * t, t))
	sol.append(Rect2(x0 - t, z0 - t, t, z1 - z0 + 2 * t))
	sol.append(Rect2(x1, z0 - t, t, z1 - z0 + 2 * t))
	sol.append(Rect2(x0 - t, z1, dx0 - x0 + t, t))
	sol.append(Rect2(dx1, z1, x1 + t - dx1, t))
	c.room_fx["shed_gap"] = Rect2(dx0, z1 - 0.45, dx1 - dx0, t + 0.9)
	# gables (east, west), the roof with its ridge along x, a sheet of iron lifted by the wind
	var zm := (z0 + z1) * 0.5
	for xx: float in [x0 - t, x1 + t]:
		for nrm in [Vector3.LEFT, Vector3.RIGHT]:
			k.tri("dh_planks", Vector3(xx, eave, z0 - t), Vector3(xx, eave, z1 + t), Vector3(xx, ridge, zm), nrm,
				Vector2(z0, -eave) / 0.9, Vector2(z1, -eave) / 0.9, Vector2(zm, -ridge) / 0.9)
	var hw := (z1 - z0) * 0.5 + t
	var slope := atan2(ridge - eave, hw)
	var sl := sqrt(hw * hw + (ridge - eave) * (ridge - eave)) + 0.3
	for sg: float in [-1.0, 1.0]:
		var rx := Transform3D(Basis(Vector3.RIGHT, sg * slope), Vector3(0.0, ridge + 0.03, zm))
		k.box("roof", Vector3(x0 - 0.35, -0.035, minf(0.0, sg * sl)), Vector3(x1 + 0.35, 0.0, maxf(0.0, sg * sl)), Color.WHITE, 1.0, Kit.ALL, rx)
	for bx: float in [x0 + 1.4, x1 - 1.4]:
		k.box("dh_planks", Vector3(bx - 0.04, eave - 0.04, z0), Vector3(bx + 0.04, eave + 0.06, z1), Color(0.5, 0.5, 0.5))
	# the door: boards on a Z of battens, a hasp; it turns around its hinge (dehors.gd)
	var dk = c.kit("dh_shed_door")
	var dw := dx1 - dx0 - 0.02
	dk.box("dh_planks", Vector3(0.0, 0.0, -0.02), Vector3(dw, dh - 0.07, 0.02), Color(0.72, 0.72, 0.7))
	for by: float in [0.22, dh - 0.36]:
		dk.box("dh_planks", Vector3(0.03, by, 0.02), Vector3(dw - 0.03, by + 0.1, 0.045), Color(0.55, 0.55, 0.55))
	dk.box("dh_planks", Vector3(0.0, 0.0, 0.02), Vector3(dw * 1.6, 0.09, 0.04), Color(0.55, 0.55, 0.55), 1.0, Kit.ALL,
		Transform3D(Basis(Vector3.BACK, 1.02), Vector3(dw - 0.06, 0.3, 0.0)))
	dk.box("dh_iron", Vector3(dw - 0.16, 1.0, 0.045), Vector3(dw + 0.02, 1.05, 0.052), Color.WHITE)
	dk.rbox("brass", Vector3(dw - 0.06, 0.9, 0.045), Vector3(dw - 0.0, 0.99, 0.075), 0.01, 2, Color(0.8, 0.8, 0.8))
	c.room_fx["shed_hinge"] = Vector3(dx0 + 0.01, 0.05, z1 + t * 0.5)
	# a label wired to the hasp
	c.room_fx["shed_door_spot"] = Vector3((dx0 + dx1) * 0.5, 1.05, z1 + t + 0.02)
	# inside. The bench along the north wall, the tool board above it, the radio
	pk.box("dh_planks", Vector3(x0 + 0.25, 0.86, z0), Vector3(x1 - 0.3, 0.91, z0 + 0.62), Color(0.8, 0.8, 0.8))
	for lx: float in [x0 + 0.3, x0 + 2.1, x1 - 0.4]:
		pk.box("dh_planks", Vector3(lx, 0.05, z0 + 0.04), Vector3(lx + 0.06, 0.86, z0 + 0.1), Color(0.6, 0.6, 0.6))
		pk.box("dh_planks", Vector3(lx, 0.05, z0 + 0.52), Vector3(lx + 0.06, 0.86, z0 + 0.58), Color(0.6, 0.6, 0.6))
	pk.box("dh_planks", Vector3(x0 + 0.3, 0.3, z0 + 0.04), Vector3(x1 - 0.34, 0.33, z0 + 0.58), Color(0.6, 0.6, 0.6))
	U.solid(c, "dh_shed", Vector3(x0 + 0.25, 0.05, z0), Vector3(x1 - 0.3, 0.91, z0 + 0.62))
	var tb := Vector3(x0 + 1.75, 1.62, z0 + 0.012)
	Shell.board(pk, "dh_planks", tb, Vector3.BACK, 2.1, 1.06, 0.02, Color(0.5, 0.5, 0.5))
	Shell.sign_quad(pk, "tex_toolboard.jpg", tb + Vector3(0, 0, 0.003), Vector3.BACK, 2.0, 1.0)
	c.room_fx["toolboard"] = tb
	# (real tools hanging over the painted ones would need their meshes; the board's own silhouettes do)
	var rp := Vector3(x1 - 0.85, 0.91, z0 + 0.3)
	pk.rbox("plastic", rp + Vector3(-0.15, 0.0, -0.06), rp + Vector3(0.15, 0.19, 0.06), 0.012, 2, Color(0.3, 0.2, 0.1))
	pk.box("dark", rp + Vector3(-0.13, 0.03, 0.06), rp + Vector3(0.02, 0.16, 0.063), Color.WHITE)
	pk.box("enamel", rp + Vector3(0.04, 0.09, 0.06), rp + Vector3(0.13, 0.15, 0.063), Color(0.75, 0.72, 0.6))
	for kx: float in [0.06, 0.11]:
		pk.tube("metal", PackedVector3Array([rp + Vector3(kx, 0.05, 0.06), rp + Vector3(kx, 0.05, 0.075)]), 0.012, 8, Color(0.6, 0.6, 0.6), 1.0, true)
	pk.tube("metal", PackedVector3Array([rp + Vector3(0.13, 0.19, 0.0), rp + Vector3(0.24, 0.52, -0.02)]), 0.003, 4, Color.WHITE)
	c.room_fx["radio"] = rp + Vector3(0.0, 0.1, 0.0)
	battery(c.kit("dh_battery_0"))
	c.room_fx["battery_0"] = Vector3(rp.x - 0.45, 0.91, z0 + 0.36)
	c.room_fx["radio_listen"] = Vector3(rp.x - 0.4, 0.0, z0 + 1.35)      # where one stands to reach it
	c.kit("dh_radio_led").sphere("bulb_on", rp + Vector3(-0.115, 0.175, 0.064), 0.007, 6, 4, Color.WHITE)
	# jars of nails, a vice, a coil of rope, an oil can
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 5:
		var jx := x0 + 0.5 + 0.2 * float(i) + rng.randf_range(-0.03, 0.03)
		pk.tube("plastic", PackedVector3Array([Vector3(jx, 0.91, z0 + 0.14), Vector3(jx, 0.91 + rng.randf_range(0.09, 0.14), z0 + 0.14)]), 0.04, 8,
			Color(0.3, 0.32, 0.3), 1.0, true)
	pk.box("dh_iron", Vector3(x0 + 2.0, 0.91, z0 + 0.3), Vector3(x0 + 2.2, 1.03, z0 + 0.55), Color(1.2, 1.2, 1.3))
	pk.box("dh_iron", Vector3(x0 + 2.04, 1.03, z0 + 0.3), Vector3(x0 + 2.16, 1.1, z0 + 0.38), Color(1.2, 1.2, 1.3))
	U.cone(pk, "dh_rust", Vector3(x0 + 2.6, 0.91, z0 + 0.22), Vector3(x0 + 2.6, 1.02, z0 + 0.22), 0.05, 0.02, 8)
	# shelves on the east wall: paint tins; the key board by the door with one key on it (its own region)
	for sy: float in [1.1, 1.55]:
		pk.box("dh_planks", Vector3(x1 - 0.26, sy, z0 + 0.9), Vector3(x1, sy + 0.03, z1 - 1.3), Color(0.7, 0.7, 0.7))
		var tz := z0 + 1.05
		while tz < z1 - 1.45:
			var tr := rng.randf_range(0.055, 0.08)
			var tint: Color = [Color(0.5, 0.5, 0.48), Color(0.4, 0.1, 0.08), Color(0.12, 0.2, 0.32), Color(0.5, 0.42, 0.1)][rng.randi() % 4]
			pk.tube("enamel", PackedVector3Array([Vector3(x1 - 0.13, sy + 0.03, tz), Vector3(x1 - 0.13, sy + 0.03 + tr * 1.9, tz)]), tr, 10, tint, 1.0, true)
			tz += tr * 2.0 + rng.randf_range(0.02, 0.12)
	var kb := Vector3(x1 - 0.012, 1.45, z1 - 0.7)
	Shell.board(pk, "dh_planks", kb, Vector3.LEFT, 0.5, 0.22, 0.02, Color(0.5, 0.5, 0.5))
	for i in 3:
		var hk := kb + Vector3(-0.012, 0.03, -0.15 + 0.15 * float(i))
		pk.tube("metal", PackedVector3Array([hk, hk + Vector3(-0.03, 0.0, 0.0), hk + Vector3(-0.03, 0.025, 0.0)]), 0.003, 4, Color.WHITE)
	c.room_fx["key_cave"] = kb + Vector3(-0.045, -0.03, 0.0)
	key(c.kit("dh_key_cave"), Color(0.9, 0.9, 1.0))
	# the mower in the corner, a spade and a rake against the wall, sacks, a dead bulb on its flex
	var mx := x1 - 0.75
	var mz := z1 - 0.62
	pk.rbox("dh_rust", Vector3(mx - 0.3, 0.12, mz - 0.26), Vector3(mx + 0.3, 0.3, mz + 0.26), 0.04, 2, Color(0.6, 1.1, 0.6))
	pk.rbox("dark", Vector3(mx - 0.12, 0.3, mz - 0.12), Vector3(mx + 0.12, 0.44, mz + 0.12), 0.03, 2, Color.WHITE)
	for wz: float in [mz - 0.28, mz + 0.28]:
		for wx: float in [mx - 0.22, mx + 0.22]:
			pk.tube("rubber", PackedVector3Array([Vector3(wx, 0.13, wz - 0.02), Vector3(wx, 0.13, wz + 0.02)]), 0.08, 9, Color(0.05, 0.05, 0.05), 1.0, true)
	pk.tube("dh_iron", PackedVector3Array([Vector3(mx - 0.28, 0.3, mz - 0.2), Vector3(mx - 0.7, 0.95, mz - 0.2), Vector3(mx - 0.7, 0.95, mz + 0.2), Vector3(mx - 0.28, 0.3, mz + 0.2)]),
		0.012, 6, Color(1.2, 1.2, 1.2))
	U.solid(c, "dh_shed", Vector3(mx - 0.72, 0.05, mz - 0.3), Vector3(mx + 0.32, 0.95, mz + 0.3))
	pk.tube("dh_planks", PackedVector3Array([Vector3(x0 + 0.12, 0.05, z1 - 0.5), Vector3(x0 + 0.05, 1.5, z1 - 0.42)]), 0.016, 6, Color.WHITE)
	pk.box("dh_iron", Vector3(x0 + 0.06, 0.05, z1 - 0.6), Vector3(x0 + 0.09, 0.36, z1 - 0.4), Color(1.2, 1.2, 1.2))
	pk.tube("dh_planks", PackedVector3Array([Vector3(x0 + 0.14, 0.05, z1 - 0.9), Vector3(x0 + 0.05, 1.6, z1 - 0.85)]), 0.014, 6, Color.WHITE)
	pk.box("dh_iron", Vector3(x0 + 0.1, 0.05, z1 - 1.1), Vector3(x0 + 0.13, 0.1, z1 - 0.7), Color(1.2, 1.2, 1.2))
	for sk in [[x0 + 0.5, z0 + 1.1], [x0 + 0.55, z0 + 1.7]]:
		pk.sphere("fabric", Vector3(float(sk[0]), 0.26, float(sk[1])), 0.3, 10, 7, Color(0.4, 0.34, 0.22), Vector3(1.0, 0.75, 1.0))
	pk.tube("dark", PackedVector3Array([Vector3(x0 + 2.2, ridge - 0.05, zm), Vector3(x0 + 2.2, eave - 0.12, zm)]), 0.004, 4, Color.WHITE)
	pk.sphere("fluo_dead", Vector3(x0 + 2.2, eave - 0.17, zm), 0.04, 8, 6, Color.WHITE)

# ====================================================================== la serre

static func serre(c) -> void:
	var k = c.kit("dh_serre")
	var gk = c.kit("dh_glass")
	var pk = c.kit("dh_serre_props")
	var cl = c.col("dh_serre")
	var cs = c.col_see("dh_serre")
	var G: Dictionary = L.SERRE
	var D: Dictionary = L.SERRE_DOOR
	var x0: float = G.x0
	var x1: float = G.x1
	var z0: float = G.z0
	var z1: float = G.z1
	var eave: float = G.eave
	var ridge: float = G.ridge
	var base: float = G.base
	var dx0: float = D.x0
	var dx1: float = D.x1
	var dh: float = D.h
	var t := 0.2
	var white := Color(0.5, 0.52, 0.5)
	k.box("concrete", Vector3(x0, 0.0, z0), Vector3(x1, 0.02, z1), Color(0.7, 0.7, 0.7), 1.0, Kit.FACE_PY)
	# low walls of stone under the glass (a gap for the door in the north one)
	Shell.wall(c, "dh_serre", "dh_stone", Vector2(x0 - t, z0 - t * 0.5), Vector2(x1 + t, z0 - t * 0.5), t, 0.0, base, [[dx0 - (x0 - t), dx1 - (x0 - t), 0.0, base]])
	Shell.wall(c, "dh_serre", "dh_stone", Vector2(x0 - t, z1 + t * 0.5), Vector2(x1 + t, z1 + t * 0.5), t, 0.0, base)
	Shell.wall(c, "dh_serre", "dh_stone", Vector2(x0 - t * 0.5, z0 - t), Vector2(x0 - t * 0.5, z1 + t), t, 0.0, base)
	Shell.wall(c, "dh_serre", "dh_stone", Vector2(x1 + t * 0.5, z0 - t), Vector2(x1 + t * 0.5, z1 + t), t, 0.0, base)
	var zn := z0 - t * 0.5
	var zs := z1 + t * 0.5
	var xw := x0 - t * 0.5
	var xe := x1 + t * 0.5
	var sol: Array = c.room_fx["solids"]
	sol.append(Rect2(x0 - t, z0 - t, dx0 - x0 + t, t))
	sol.append(Rect2(dx1, z0 - t, x1 + t - dx1, t))
	sol.append(Rect2(x0 - t, z1, x1 - x0 + 2 * t, t))
	sol.append(Rect2(x0 - t, z0 - t, t, z1 - z0 + 2 * t))
	sol.append(Rect2(x1, z0 - t, t, z1 - z0 + 2 * t))
	c.room_fx["serre_gap"] = Rect2(dx0 + 0.05, z0 - t - 0.4, dx1 - dx0 - 0.1, t + 0.8)      # the doorway: she can come in
	# the frame: posts every metre, plates, the ridge, rafters; glass between (some panes gone)
	var f := 0.022
	var bays := int(round(x1 - x0))
	var zm := (z0 + z1) * 0.5
	for i in bays + 1:
		var px := lerpf(xw, xe, float(i) / float(bays))
		for zz: float in [zn, zs]:
			if zz == zn and px > dx0 + 0.05 and px < dx1 - 0.05:
				continue
			k.box("paintwood", Vector3(px - f, base, zz - f), Vector3(px + f, eave, zz + f), white)
		for sg: float in [-1.0, 1.0]:
			var e := Vector3(px, eave, zn if sg < 0.0 else zs)
			k.tube("paintwood", PackedVector3Array([e, Vector3(px, ridge, zm)]), f, 4, white)
	for zz: float in [zn, zs]:
		k.box("paintwood", Vector3(xw, eave - f, zz - f), Vector3(xe, eave + f, zz + f), white)
		k.box("paintwood", Vector3(xw, 1.25 - f * 0.7, zz - f * 0.7), Vector3(xe, 1.25 + f * 0.7, zz + f * 0.7), white)
	k.box("paintwood", Vector3(xw, ridge - f, zm - f), Vector3(xe, ridge + f, zm + f), white)
	var nz := 4
	for xx: float in [xw, xe]:
		for j in nz + 1:
			var pz := lerpf(zn, zs, float(j) / float(nz))
			var top := eave + (ridge - eave) * (1.0 - absf(pz - zm) / (zs - zm))
			k.box("paintwood", Vector3(xx - f, base, pz - f), Vector3(xx + f, top, pz + f), white)
		k.box("paintwood", Vector3(xx - f, eave - f, zn), Vector3(xx + f, eave + f, zs), white)
	# door frame, and the door left open against the wall outside
	k.box("paintwood", Vector3(dx0 - f, 0.0, zn - f), Vector3(dx0 + f, eave, zn + f), white)
	k.box("paintwood", Vector3(dx1 - f, 0.0, zn - f), Vector3(dx1 + f, eave, zn + f), white)
	k.box("paintwood", Vector3(dx0, dh - f, zn - f), Vector3(dx1, dh + f, zn + f), white)
	var dxf := Transform3D(Basis(Vector3.UP, 1.95), Vector3(dx1 + 0.03, 0.03, zn - 0.03))
	for b in [[0.0, 0.0, 0.04, dh - 0.06], [0.9, 0.0, 0.94, dh - 0.06], [0.0, 0.0, 0.94, 0.05], [0.0, dh - 0.1, 0.94, dh - 0.06], [0.0, 0.9, 0.94, 0.94]]:
		k.box("paintwood", Vector3(float(b[0]), float(b[1]), -0.015), Vector3(float(b[2]), float(b[3]), 0.015), white, 1.0, Kit.ALL, dxf)
	gk.quad("dh_glass", dxf * Vector3(0.04, 0.05, 0.0), dxf * Vector3(0.9, 0.05, 0.0), dxf * Vector3(0.9, dh - 0.1, 0.0), dxf * Vector3(0.04, dh - 0.1, 0.0),
		dxf.basis.z, Vector2(0, 1.8), Vector2(0.9, 1.8), Vector2(0.9, 0), Vector2(0, 0))
	# glass: walls (two panes high), gable ends, the roof slopes
	var gone := [3, 10, 17, 22]
	var pane := 0
	for i in bays:
		var pa := lerpf(xw, xe, float(i) / float(bays))
		var pb := lerpf(xw, xe, float(i + 1) / float(bays))
		for zz: float in [zn, zs]:
			var nrm := Vector3.FORWARD if zz == zn else Vector3.BACK
			if zz == zn and pa > dx0 - 0.5 and pb < dx1 + 0.5:
				gk.quad("dh_glass", Vector3(pa, dh, zz), Vector3(pb, dh, zz), Vector3(pb, eave, zz), Vector3(pa, eave, zz), nrm,
					Vector2(pa, 0.1), Vector2(pb, 0.1), Vector2(pb, 0.0), Vector2(pa, 0.0))
				continue
			pane += 1
			if not (pane in gone):
				gk.quad("dh_glass", Vector3(pa, base, zz), Vector3(pb, base, zz), Vector3(pb, eave, zz), Vector3(pa, eave, zz), nrm,
					Vector2(pa, eave - base) * 0.7, Vector2(pb, eave - base) * 0.7, Vector2(pb, 0.0) * 0.7, Vector2(pa, 0.0) * 0.7)
		for sg: float in [-1.0, 1.0]:
			pane += 1
			if pane in gone:
				continue
			var ze := zn if sg < 0.0 else zs
			gk.quad("dh_glass", Vector3(pa, eave, ze), Vector3(pb, eave, ze), Vector3(pb, ridge, zm), Vector3(pa, ridge, zm), Vector3(0.0, 0.9, sg * 0.42).normalized(),
				Vector2(pa, 2.2) * 0.7, Vector2(pb, 2.2) * 0.7, Vector2(pb, 0.0) * 0.7, Vector2(pa, 0.0) * 0.7)
	for xx: float in [xw, xe]:
		var nrm2 := Vector3.LEFT if xx == xw else Vector3.RIGHT
		gk.quad("dh_glass", Vector3(xx, base, zn), Vector3(xx, base, zs), Vector3(xx, eave, zs), Vector3(xx, eave, zn), nrm2,
			Vector2(zn, 1.5) * 0.7, Vector2(zs, 1.5) * 0.7, Vector2(zs, 0.0) * 0.7, Vector2(zn, 0.0) * 0.7)
		gk.tri("dh_glass", Vector3(xx, eave, zn), Vector3(xx, eave, zs), Vector3(xx, ridge, zm), nrm2, Vector2(zn, 1.0) * 0.7, Vector2(zs, 1.0) * 0.7, Vector2(zm, 0.0) * 0.7)
	# what stops the player (and her) above the stone: the glass, as see-through colliders
	cs.box(Vector3(x0 - t, base, z0 - t), Vector3(dx0, eave, z0))
	cs.box(Vector3(dx1, base, z0 - t), Vector3(x1 + t, eave, z0))
	cs.box(Vector3(dx0, dh, z0 - t), Vector3(dx1, eave, z0))
	cs.box(Vector3(x0 - t, base, z1), Vector3(x1 + t, eave, z1 + t))
	cs.box(Vector3(x0 - t, base, z0 - t), Vector3(x0, eave, z1 + t))
	cs.box(Vector3(x1, base, z0 - t), Vector3(x1 + t, eave, z1 + t))
	# benches: one along the south glass (the four pots that can be lifted stand on it), one at the west end
	var by := 0.8
	var bz0 := z1 - 0.82
	var bz1 := z1 - 0.12
	for bench in [[x0 + 0.3, bz0, x1 - 0.3, bz1], [x0 + 0.12, z0 + 0.5, x0 + 0.82, bz0 - 0.5]]:
		var ax := float(bench[0])
		var az := float(bench[1])
		var bx := float(bench[2])
		var bz := float(bench[3])
		var slats := int((bz - az) / 0.12) if (bx - ax) > (bz - az) else int((bx - ax) / 0.12)
		for s in slats:
			if (bx - ax) > (bz - az):
				var sz := lerpf(az, bz, (float(s) + 0.5) / float(slats))
				pk.box("dh_planks", Vector3(ax, by - 0.025, sz - 0.045), Vector3(bx, by, sz + 0.045), Color(0.7, 0.7, 0.68))
			else:
				var sx := lerpf(ax, bx, (float(s) + 0.5) / float(slats))
				pk.box("dh_planks", Vector3(sx - 0.045, by - 0.025, az), Vector3(sx + 0.045, by, bz), Color(0.7, 0.7, 0.68))
		for lx: float in [ax + 0.04, (ax + bx) * 0.5, bx - 0.1]:
			for lz: float in [az + 0.04, bz - 0.1]:
				pk.box("dh_planks", Vector3(lx, 0.02, lz), Vector3(lx + 0.06, by - 0.025, lz + 0.06), Color(0.6, 0.6, 0.6))
		U.solid(c, "dh_serre", Vector3(ax, 0.0, az), Vector3(bx, by, bz))
	# pots that stay where they are, trays, a watering can, sacks of compost, a hose
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var pots: Array = L.POTS
	var px2 := x0 + 0.5
	var n := 0
	while px2 < x1 - 0.5:
		var near := false
		for lp in pots:
			if absf(px2 - float(lp)) < 0.3:
				near = true
		if not near:
			var r := rng.randf_range(0.07, 0.12)
			var sub = Kit.new()
			pot(sub, r, r * 1.6, TERRA.darkened(rng.randf_range(0.0, 0.3)), rng.randf() < 0.8, n)
			_merge(pk, sub, Vector3(px2, by, bz0 + rng.randf_range(0.2, 0.52)))
			n += 1
		px2 += rng.randf_range(0.26, 0.5)
	for i in 6:
		var sub2 = Kit.new()
		var r2 := rng.randf_range(0.08, 0.14)
		pot(sub2, r2, r2 * 1.5, TERRA.darkened(rng.randf_range(0.0, 0.3)), rng.randf() < 0.7, 40 + i)
		_merge(pk, sub2, Vector3(x0 + 0.47 + rng.randf_range(-0.2, 0.2), by, z0 + 0.75 + 0.33 * float(i)))
	for i in 3:
		var sub3 = Kit.new()
		pot(sub3, 0.16, 0.26, TERRA.darkened(0.2), true, 60 + i)
		_merge(pk, sub3, Vector3(x1 - 0.5 - 0.5 * float(i), 0.02, z0 + 0.4 + 0.1 * float(i % 2)))
	pk.rbox("fabric", Vector3(x1 - 0.9, 0.02, z0 + 1.0), Vector3(x1 - 0.2, 0.2, z0 + 1.5), 0.07, 2, Color(0.3, 0.32, 0.2))
	pk.rbox("fabric", Vector3(x1 - 0.85, 0.2, z0 + 1.05), Vector3(x1 - 0.22, 0.36, z0 + 1.5), 0.07, 2, Color(0.34, 0.3, 0.2))
	U.solid(c, "dh_serre", Vector3(x1 - 0.9, 0.0, z0 + 1.0), Vector3(x1 - 0.2, 0.36, z0 + 1.5))
	U.cone(pk, "dh_rust", Vector3(x0 + 1.6, 0.02, z0 + 0.5), Vector3(x0 + 1.6, 0.3, z0 + 0.5), 0.13, 0.11, 10, Color(0.6, 1.0, 0.8), true)
	pk.tube("dh_rust", PackedVector3Array([Vector3(x0 + 1.7, 0.1, z0 + 0.5), Vector3(x0 + 2.0, 0.34, z0 + 0.5)]), 0.02, 6, Color(0.6, 1.0, 0.8))
	var hose := PackedVector3Array()
	for j in 26:
		var a := float(j) * 0.55
		hose.append(Vector3(x0 + 3.4 + cos(a) * (0.2 + 0.006 * float(j)), 0.04 + 0.002 * float(j % 3), z0 + 0.55 + sin(a) * (0.2 + 0.006 * float(j))))
	pk.tube("rubber", hose, 0.013, 5, Color(0.08, 0.2, 0.1))
	battery(c.kit("dh_battery_1"))
	c.room_fx["battery_1"] = Vector3(x0 + 0.5, by, z0 + 0.62)
	# the four pots that can be lifted (their own regions, authored around their base), the key under the blue one
	var spots: Array = []
	for i in pots.size():
		var pkk = c.kit("dh_pot_%d" % i)
		pot(pkk, 0.115, 0.19, Color(0.12, 0.2, 0.42) if i == L.POT_KEY else TERRA.darkened(0.1 * float(i % 2)), i != L.POT_KEY, 80 + i)
		spots.append(Vector3(float(pots[i]), by, bz0 + 0.36))
	c.room_fx["pots"] = spots
	key(c.kit("dh_key_shed"), Color(1.0, 0.95, 0.8))
	c.room_fx["key_shed"] = (spots[L.POT_KEY] as Vector3) + Vector3(0.0, 0.006, 0.0)
	# hand prints on the inside... no: on the outside of the south glass, in front of the pots (shown by dehors.gd)
	var hk = c.kit("dh_hands")
	Shell.sign_quad(hk, "dh_handprint", Vector3.ZERO, Vector3.FORWARD, 0.62, 0.62)
	c.room_fx["hands"] = Vector3(float(pots[L.POT_KEY]) + 0.25, 1.42, zs - 0.012)
	# a tube lamp on two chains under the ridge: the last of a row, greenish, never switched off
	var lp2 := Vector3((x0 + x1) * 0.5 + 0.5, ridge - 0.42, zm)
	for cx2: float in [-0.5, 0.5]:
		pk.tube("dh_iron", PackedVector3Array([lp2 + Vector3(cx2, 0.03, 0.0), Vector3(lp2.x + cx2, ridge, zm)]), 0.003, 4, Color(1.5, 1.5, 1.5))
	pk.box("enamel", lp2 + Vector3(-0.62, 0.0, -0.05), lp2 + Vector3(0.62, 0.035, 0.05), Color(0.6, 0.62, 0.6))
	var lk = c.kit("dh_serre_lamp")
	lk.tube("dh_tube_cold", PackedVector3Array([lp2 + Vector3(-0.58, -0.02, 0.0), lp2 + Vector3(0.58, -0.02, 0.0)]), 0.016, 8, Color.WHITE, 1.0, true)
	var o := OmniLight3D.new()
	o.name = "SerreLamp"
	o.position = lp2 + Vector3(0.0, -0.12, 0.0)
	o.light_color = Color(0.62, 1.0, 0.76)
	o.light_energy = 1.3
	o.omni_range = 9.0
	o.omni_attenuation = 1.3
	o.shadow_enabled = true
	o.shadow_bias = 0.06
	o.shadow_normal_bias = 1.5
	o.shadow_blur = 1.2
	o.light_cull_mask = MASK
	o.light_volumetric_fog_energy = 2.2
	c.region("dh_lights").add_child(o)
	c.room_fx["serre_lamp"] = o

## Appends every bin of a small kit to `k`, moved to `at` (pots built once around the origin).
static func _merge(k, sub, at: Vector3) -> void:
	for id in (sub.bins as Dictionary).keys():
		var s = sub.bins[id]
		var d = k.bin(id)
		var base: int = d.v.size()
		for v in s.v:
			d.v.append(v + at)
		d.n.append_array(s.n)
		d.uv.append_array(s.uv)
		d.c.append_array(s.c)
		for i in s.idx:
			d.idx.append(i + base)
	k.tri_count += int(sub.tri_count)
