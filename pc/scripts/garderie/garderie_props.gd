## Props of the garderie: the vestibule's name-labelled cubbies with abandoned boots / mittens / tuques, the
## sign-in counter (attendance sheet, phone, bell, lost-and-found box), the notice board, the rules board, the
## hand-painted "Garderie Les Petits Soleils" sign, kids' drawings, painted suns, a stopped wall clock, the baby gate,
## the hall double doors (propped open) and a couple of signs in the hall.
extends RefCounted

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")
const M := preload("res://scripts/garderie/garderie_mats.gd")

const BOOT_COLS := [Color(0.85, 0.15, 0.12), Color(0.95, 0.75, 0.1), Color(0.15, 0.45, 0.25), Color(0.18, 0.3, 0.7), Color(0.9, 0.45, 0.6)]
const WOOL_COLS := [Color(0.75, 0.15, 0.2), Color(0.2, 0.35, 0.7), Color(0.9, 0.7, 0.2), Color(0.25, 0.55, 0.3), Color(0.55, 0.3, 0.6), Color(0.85, 0.85, 0.82)]

static func build(c) -> void:
	_cubbies(c)
	_counter(c)
	_walls(c)
	_gate_and_doors(c)
	_hall_signs(c)

static func _cubbies(c) -> void:
	var k = c.kit("props_v")
	var cl = c.col("props_v")
	var x0 := -16.5
	var ncol := 8
	var cw := 0.55
	var x1 := x0 + ncol * cw
	var zb: float = GL.VEST.z0 + 0.016
	var zf := zb + 0.38
	var wood := Color(0.86, 0.74, 0.58)
	k.box("wood", Vector3(x0, 0.0, zb), Vector3(x1, 1.55, zb + 0.014), wood)
	for i in ncol + 1:
		var xx := x0 + i * cw
		k.box("wood", Vector3(xx - 0.009, 0.0, zb), Vector3(xx + 0.009, 1.55, zf), wood)
	for sh in [[0.06, 0.08, zf], [0.34, 0.37, zf + 0.12], [1.22, 1.24, zf], [1.53, 1.55, zf]]:
		k.box("wood", Vector3(x0, float(sh[0]), zb), Vector3(x1, float(sh[1]), float(sh[2])), wood)
	k.box("wood", Vector3(x0, 0.0, zf + 0.08), Vector3(x1, 0.34, zf + 0.12), wood * 0.9)
	cl.box(Vector3(x0, 0.0, zb), Vector3(x1, 1.55, zf + 0.12))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	for i in ncol:
		var cx := x0 + (i + 0.5) * cw
		# name label (masking tape) on the top shelf edge, two coat hooks
		var li := (i * 2 + 1) % 16 if i < 7 else 15
		var uv := Rect2(float(li % 4) * 0.25, float(li / 4) * 0.25, 0.25, 0.25)
		Shell.sign_quad(k, "cut_cubby_labels.png", Vector3(cx, 1.385, zf + 0.004), Vector3.BACK, 0.27, 0.135, uv)
		for hx in [-0.12, 0.12]:
			k.box("metal", Vector3(cx + hx - 0.008, 1.0, zb + 0.014), Vector3(cx + hx + 0.008, 1.09, zb + 0.07), Color(0.62, 0.6, 0.55))
			k.sphere("metal", Vector3(cx + hx, 1.1, zb + 0.07), 0.012, 8, 6, Color(0.62, 0.6, 0.55))
		var r := rng.randf()
		# boots on the bottom shelf
		if r < 0.6:
			var bc: Color = BOOT_COLS[rng.randi() % BOOT_COLS.size()]
			for bxo in [-0.07, 0.07]:
				_boot(k, Vector3(cx + bxo + rng.randf_range(-0.02, 0.02), 0.08, zb + 0.18), rng.randf_range(-0.3, 0.3), bc, rng.randf() < 0.15)
		# mittens / tuque on the bench or the top shelf, a coat on a hook
		if rng.randf() < 0.55:
			var wc: Color = WOOL_COLS[rng.randi() % WOOL_COLS.size()]
			for mx in [-0.06, 0.06]:
				_mitten(k, Vector3(cx + mx, 0.37, zf + rng.randf_range(-0.05, 0.05)), rng.randf_range(-0.6, 0.6), wc)
		if rng.randf() < 0.5:
			_tuque(k, Vector3(cx + rng.randf_range(-0.08, 0.08), 1.24, zb + 0.2), WOOL_COLS[rng.randi() % WOOL_COLS.size()])
		if i == 2 or i == 5:
			var cc: Color = [Color(0.2, 0.4, 0.75), Color(0.8, 0.3, 0.35)][i % 2]
			k.box("fabric", Vector3(cx - 0.16, 0.5, zb + 0.07), Vector3(cx + 0.16, 1.1, zb + 0.16), cc)
			k.box("fabric", Vector3(cx - 0.2, 0.75, zb + 0.06), Vector3(cx - 0.14, 1.06, zb + 0.15), cc * 0.92)
			k.box("fabric", Vector3(cx + 0.14, 0.75, zb + 0.06), Vector3(cx + 0.2, 1.06, zb + 0.15), cc * 0.92)
		if i == 6:
			k.box("vinyl_up", Vector3(cx - 0.13, 0.38, zb + 0.06), Vector3(cx + 0.13, 0.7, zb + 0.24), Color(0.95, 0.55, 0.15))
			k.box("vinyl_up", Vector3(cx - 0.1, 0.45, zb + 0.24), Vector3(cx + 0.1, 0.62, zb + 0.29), Color(0.9, 0.5, 0.12))
	# a pair of boots left on the mats, a lone mitten
	_boot(k, Vector3(-13.6, 0.0, 0.6), 0.9, BOOT_COLS[0], true)
	_boot(k, Vector3(-13.35, 0.0, 0.75), 2.4, BOOT_COLS[0], false)
	_mitten(k, Vector3(-15.2, 0.0, 1.5), 0.4, WOOL_COLS[1])

static func _boot(k, p: Vector3, yaw: float, col: Color, fallen: bool) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	if fallen:
		xf = xf * Transform3D(Basis(Vector3.RIGHT, 1.45), Vector3(0, 0.045, 0))
	k.box("rubber", Vector3(-0.04, 0.0, -0.05), Vector3(0.04, 0.2, 0.03), col, 1.0, Kit.ALL, xf)
	k.box("rubber", Vector3(-0.042, 0.0, 0.03), Vector3(0.042, 0.065, 0.12), col, 1.0, Kit.ALL, xf)
	k.box("rubber", Vector3(-0.044, 0.0, -0.055), Vector3(0.044, 0.012, 0.125), Color(0.12, 0.12, 0.12), 1.0, Kit.ALL, xf)

static func _mitten(k, p: Vector3, yaw: float, col: Color) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	k.box("fabric", Vector3(-0.045, 0.0, -0.06), Vector3(0.045, 0.025, 0.06), col, 1.0, Kit.ALL, xf)
	k.box("fabric", Vector3(0.045, 0.0, -0.01), Vector3(0.07, 0.022, 0.03), col, 1.0, Kit.ALL, xf)
	k.box("fabric", Vector3(-0.047, 0.0, -0.085), Vector3(0.047, 0.027, -0.06), Color(0.9, 0.9, 0.88), 1.0, Kit.ALL, xf)

static func _tuque(k, p: Vector3, col: Color) -> void:
	k.sphere("fabric", p + Vector3(0, 0.0, 0), 0.085, 12, 6, col, Vector3(1.0, 0.75, 1.0))
	k.box("fabric", Vector3(p.x - 0.088, p.y, p.z - 0.088), Vector3(p.x + 0.088, p.y + 0.03, p.z + 0.088), col * 0.85)
	k.sphere("fabric", p + Vector3(0, 0.075, 0), 0.03, 8, 6, Color(0.95, 0.95, 0.92))

static func _counter(c) -> void:
	var k = c.kit("props_v")
	var cl = c.col("props_v")
	var x0 := -15.6
	var x1 := -12.6
	var zf := 4.35
	var zb: float = GL.VEST.z1 - 0.016
	k.box("paintwood", Vector3(x0, 0.0, zf), Vector3(x1, 1.0, zf + 0.04), M.TOMATO)
	k.box("paintwood", Vector3(x0, 0.0, zf), Vector3(x0 + 0.04, 1.0, zb), M.TOMATO)
	k.box("paintwood", Vector3(x1 - 0.04, 0.0, zf), Vector3(x1, 1.0, zb), M.TOMATO)
	k.box("wood", Vector3(x0 - 0.03, 1.0, zf - 0.06), Vector3(x1 + 0.03, 1.04, zb), Color(0.8, 0.66, 0.48))
	k.box("paintwood", Vector3(x0, 0.0, zf - 0.005), Vector3(x1, 0.09, zf + 0.04), Color(0.2, 0.2, 0.2))
	Shell.sign_quad(k, "cut_sun_decal.png", Vector3((x0 + x1) * 0.5, 0.58, zf - 0.006), Vector3.FORWARD, 0.55, 0.55)
	cl.box(Vector3(x0 - 0.03, 0.0, zf - 0.06), Vector3(x1 + 0.03, 1.04, zb))
	# attendance sheet on a clipboard, pen, phone, bell, cup of crayons
	var cb := Vector3(-14.4, 1.045, 4.62)
	var cxf := Transform3D(Basis(Vector3.UP, 0.12), cb)
	k.box("wood", Vector3(-0.13, 0.0, -0.17), Vector3(0.13, 0.008, 0.17), Color(0.55, 0.4, 0.25), 1.0, Kit.ALL, cxf)
	var a := cxf * Vector3(-0.115, 0.0095, -0.155)
	var b := cxf * Vector3(0.115, 0.0095, -0.155)
	var cc := cxf * Vector3(0.115, 0.0095, 0.165)
	var d := cxf * Vector3(-0.115, 0.0095, 0.165)
	k.quad("tex_signin.jpg", a, b, cc, d, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	k.box("metal", Vector3(-0.05, 0.008, -0.17), Vector3(0.05, 0.022, -0.14), Color(0.7, 0.7, 0.7), 1.0, Kit.ALL, cxf)
	k.tube("plastic", PackedVector3Array([cb + Vector3(0.16, 0.012, -0.05), cb + Vector3(0.27, 0.012, 0.03)]), 0.005, 6, Color(0.1, 0.2, 0.7))
	var ph := Vector3(-13.2, 1.04, 4.75)
	k.box("plastic", ph + Vector3(-0.1, 0, -0.09), ph + Vector3(0.1, 0.07, 0.09), Color(0.88, 0.84, 0.74))
	k.tube("plastic", PackedVector3Array([ph + Vector3(-0.1, 0.09, -0.02), ph + Vector3(0.1, 0.09, -0.02)]), 0.022, 10, Color(0.88, 0.84, 0.74), 1.0, true)
	k.sphere("metal", Vector3(-12.9, 1.04, 4.5), 0.045, 12, 6, Color(0.75, 0.6, 0.3), Vector3(1.0, 0.75, 1.0))
	k.tube("plastic", PackedVector3Array([Vector3(-15.2, 1.04, 4.6), Vector3(-15.2, 1.14, 4.6)]), 0.035, 12, Color(0.3, 0.6, 0.9), 1.0, true)
	for i in 5:
		var ang := float(i) * 1.25
		k.tube("plastic", PackedVector3Array([Vector3(-15.2 + cos(ang) * 0.015, 1.1, 4.6 + sin(ang) * 0.015), Vector3(-15.2 + cos(ang) * 0.03, 1.2, 4.6 + sin(ang) * 0.03)]),
			0.004, 6, [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.1), Color(0.2, 0.7, 0.3), Color(0.6, 0.3, 0.7)][i])
	# lost-and-found box with mittens spilling
	var lb := Vector3(-12.2, 0.0, 4.55)
	k.box("wood", lb + Vector3(-0.22, 0, -0.18), lb + Vector3(0.22, 0.32, 0.18), Color(0.64, 0.5, 0.34))
	Shell.sign_quad(k, "tex_labels.jpg", lb + Vector3(0, 0.18, -0.183), Vector3.FORWARD, 0.3, 0.22, Rect2(0, 0, 1.0 / 3.0, 0.5))
	cl.box(lb + Vector3(-0.22, 0, -0.18), lb + Vector3(0.22, 0.32, 0.18))
	var rng := RandomNumberGenerator.new()
	rng.seed = 135
	for i in 7:
		_mitten(k, lb + Vector3(rng.randf_range(-0.18, 0.18), 0.32, rng.randf_range(-0.14, 0.14)), rng.randf() * TAU, WOOL_COLS[i % WOOL_COLS.size()])
	for i in 3:
		_mitten(k, lb + Vector3(rng.randf_range(-0.5, -0.25), 0.0, rng.randf_range(-0.4, 0.0)), rng.randf() * TAU, WOOL_COLS[(i + 3) % WOOL_COLS.size()])

static func _framed(k, mat: String, ctr: Vector3, nrm: Vector3, w: float, h: float, frame_col: Color) -> void:
	Shell.board(k, "wood", ctr - nrm * 0.004, nrm, w + 0.08, h + 0.08, 0.025, frame_col)
	Shell.sign_quad(k, mat, ctr + nrm * 0.0105, nrm, w, h)

static func _walls(c) -> void:
	var k = c.kit("props_v")
	var V: Dictionary = GL.VEST
	var wx: float = V.x0 + 0.002
	# notice board above the counter, rules board, the hand-painted sign, drawings, painted suns, clock
	_framed(k, "tex_notice_board.jpg", Vector3(-14.1, 1.86, float(V.z1) - 0.03), Vector3.FORWARD, 2.0, 1.25, Color(0.6, 0.45, 0.3))
	_framed(k, "tex_rules.jpg", Vector3(wx + 0.03, 1.83, 0.15), Vector3.RIGHT, 0.98, 1.34, Color(0.9, 0.9, 0.88))
	Shell.board(k, "wood", Vector3(wx + 0.025, 1.98, 4.03), Vector3.RIGHT, 1.68, 0.53, 0.04, Color(0.7, 0.55, 0.38))
	Shell.sign_quad(k, "tex_sign_garderie.jpg", Vector3(wx + 0.046, 1.98, 4.03), Vector3.RIGHT, 1.66, 0.52)
	var dr := [[Vector3(wx + 0.004, 1.42, 3.45), 0], [Vector3(wx + 0.004, 1.38, 4.6), 1], [Vector3(float(V.x1) - 0.018, 1.45, 3.4), 3],
		[Vector3(float(V.x1) - 0.018, 1.4, 0.7), 2], [Vector3(-15.8, 1.42, float(V.z0) + 0.018), 1]]
	for d in dr:
		var p: Vector3 = d[0]
		var nrm := Vector3.RIGHT if p.x < -16.0 else (Vector3.LEFT if p.x > -12.0 else Vector3.BACK)
		var i: int = d[1]
		Shell.sign_quad(k, "tex_drawings.jpg", p, nrm, 0.36, 0.36, Rect2(0.5 * float(i % 2), 0.5 * float(i / 2), 0.5, 0.5))
	for sp in [[Vector3(-12.4, 1.85, float(V.z0) + 0.003), Vector3.BACK, 0.5], [Vector3(-16.4, 2.05, float(V.z1) - 0.003), Vector3.FORWARD, 0.42],
			[Vector3(float(V.x1) - 0.003, 1.8, 4.3), Vector3.LEFT, 0.55]]:
		Shell.sign_quad(k, "cut_sun_decal.png", sp[0], sp[1], sp[2], sp[2])
	# wall clock above the corridor opening, stopped at 3 h 17
	var cp := Vector3(float(V.x1) - 0.03, 2.35, 2.1)
	k.tube("plastic", PackedVector3Array([cp + Vector3(0.02, 0, 0), cp + Vector3(-0.02, 0, 0)]), 0.15, 24, Color(0.9, 0.2, 0.15), 1.0, true)
	k.disc("fabric", cp + Vector3(-0.021, 0, 0), Vector3.LEFT, Vector3.UP, 0.13, 24, Color(0.95, 0.94, 0.9))
	for hand in [[0.06, 0.012, 0.95 * TAU * (3.28 / 12.0)], [0.105, 0.007, TAU * (17.0 / 60.0)]]:
		var ang: float = hand[2]
		var dir := Vector3(0, cos(ang), -sin(ang))
		var hc: Vector3 = cp + Vector3(-0.024, 0, 0) + dir * float(hand[0]) * 0.5
		var bas := Basis(Vector3.RIGHT, ang)
		k.box("metal", Vector3(-0.002, -float(hand[0]) * 0.5, -float(hand[1]) * 0.5), Vector3(0.002, float(hand[0]) * 0.5, float(hand[1]) * 0.5), Color(0.08, 0.08, 0.08), 1.0, Kit.ALL, Transform3D(bas, hc))
	# a red SORTIE sign over the way back to the house (inside the vestibule, over the corridor opening)
	Shell.board(k, "steel_up", Vector3(float(V.x1) - 0.06, 2.42, 1.35), Vector3.LEFT, 0.42, 0.17, 0.08, Color(0.2, 0.2, 0.2))
	Shell.sign_quad(k, "emit_sortie_red.png", Vector3(float(V.x1) - 0.101, 2.42, 1.35), Vector3.LEFT, 0.38, 0.14)

static func _gate_and_doors(c) -> void:
	var k = c.kit("props_v")
	var cl = c.col("props_v")
	var vo: Dictionary = GL.VEST_OUT
	var z0: float = vo.z0
	var z1: float = vo.z1
	# double steel doors (teal) propped open into the hall, narrow wired-glass windows, push plates
	var teal := Color(0.13, 0.42, 0.45)
	for leaf in [[z0, 1.0], [z1, -1.0]]:
		var hz: float = leaf[0]
		var s: float = leaf[1]
		var hinge := Vector3(-17.21, GL.UP, hz)
		var ang := -s * (PI * 0.5 + 0.06)
		var xf := Transform3D(Basis(Vector3.UP, ang), hinge)
		var w := (z1 - z0) * 0.5 - 0.01
		var zlo := 0.0 if s > 0 else -w
		var zhi := w if s > 0 else 0.0
		k.box("steel_up", Vector3(-0.045, 0.0, zlo), Vector3(0.0, 2.17, zhi), teal, 1.0, Kit.ALL, xf)
		var wz := (zlo + zhi) * 0.5
		k.box("dark", Vector3(-0.05, 1.25, wz - 0.07), Vector3(0.005, 1.95, wz + 0.07), Color.WHITE, 1.0, Kit.ALL, xf)
		k.box("metal", Vector3(-0.06, 1.0, wz - 0.12 + s * 0.2), Vector3(0.015, 1.25, wz + 0.0 + s * 0.2), Color(0.7, 0.7, 0.68), 1.0, Kit.ALL, xf)
		var p0: Vector3 = xf * Vector3(-0.045, 0.0, zlo)
		var p1: Vector3 = xf * Vector3(0.0, 0.0, zhi)
		cl.box(Vector3(minf(p0.x, p1.x) - 0.01, 0.0, minf(p0.z, p1.z) - 0.01), Vector3(maxf(p0.x, p1.x) + 0.01, 2.17, maxf(p0.z, p1.z) + 0.01))
	# baby gate, unlatched and swung into the vestibule (white plastic bars)
	var gxf := Transform3D(Basis(Vector3.UP, 1.25), Vector3(-16.98, 0.0, z0 + 0.02))
	var white := Color(0.92, 0.92, 0.9)
	k.box("plastic", Vector3(0.0, 0.02, -0.02), Vector3(0.88, 0.06, 0.02), white, 1.0, Kit.ALL, gxf)
	k.box("plastic", Vector3(0.0, 0.7, -0.02), Vector3(0.88, 0.75, 0.02), white, 1.0, Kit.ALL, gxf)
	for i in 12:
		var bx := 0.04 + i * 0.072
		k.box("plastic", Vector3(bx, 0.06, -0.012), Vector3(bx + 0.022, 0.7, 0.012), white, 1.0, Kit.ALL, gxf)
	k.box("plastic", Vector3(0.84, 0.3, -0.03), Vector3(0.9, 0.45, 0.03), Color(0.3, 0.3, 0.3), 1.0, Kit.ALL, gxf)

static func _hall_extras(c) -> void:
	var k = c.kit("props_h")
	var cl = c.col("props_h")
	# cardboard suns hanging from the trusses on strings (double-sided cut-outs), slowly turned
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var top: float = GL.HALLB.roof - 0.68
	for p in [Vector2(-21.0, -1.0), Vector2(-24.6, 5.0), Vector2(-28.2, 9.0), Vector2(-33.0, -6.2), Vector2(-37.0, 2.4),
			Vector2(-26.0, -6.3), Vector2(-21.6, 9.4), Vector2(-36.6, 8.6)]:
		var y := rng.randf_range(4.2, 5.1)
		var s := rng.randf_range(0.7, 1.05)
		var yaw := rng.randf_range(-PI, PI)
		var n := Vector3(sin(yaw), 0.0, cos(yaw))
		Shell.sign_quad(k, "cut_sun_decal.png", Vector3(p.x, y, p.y), n, s, s)
		k.box("metal", Vector3(p.x - 0.003, y + s * 0.38, p.y - 0.003), Vector3(p.x + 0.003, top, p.y + 0.003), Color(0.75, 0.75, 0.7))
	# low shoe rack on the landing ("Pas de souliers dans les modules") with forgotten kids' shoes
	var x0 := -19.5
	var x1 := -17.7
	var z0 := 3.85
	var z1 := 4.2
	k.box("wood", Vector3(x0, 0.0, z0), Vector3(x1, 0.45, z1), Color(0.85, 0.72, 0.55), 1.0, Kit.ALL & ~Kit.FACE_PZ)
	for i in 4:
		var xx := lerpf(x0, x1, float(i) / 3.0)
		k.box("wood", Vector3(xx - 0.01, 0.0, z0), Vector3(xx + 0.01, 0.45, z1), Color(0.8, 0.66, 0.5))
	k.box("wood", Vector3(x0, 0.2, z0), Vector3(x1, 0.22, z1), Color(0.8, 0.66, 0.5))
	cl.box(Vector3(x0, 0.0, z0), Vector3(x1, 0.45, z1))
	var shoe_cols := [Color(0.9, 0.2, 0.3), Color(0.2, 0.5, 0.9), Color(0.95, 0.85, 0.2), Color(0.3, 0.75, 0.4), Color(0.95, 0.95, 0.95), Color(0.6, 0.35, 0.75)]
	for i in 9:
		var bay := i % 3
		var shelf := 0.0 if i < 5 else 0.22
		var sx := lerpf(x0, x1, (float(bay) + 0.5) / 3.0) + rng.randf_range(-0.12, 0.12)
		var col: Color = shoe_cols[rng.randi() % shoe_cols.size()]
		_shoe(k, Vector3(sx, shelf + 0.005, (z0 + z1) * 0.5), rng.randf_range(-0.4, 0.4), col)
	for p in [Vector3(-18.4, 0.0, 3.4), Vector3(-18.25, 0.0, 3.3)]:
		_shoe(k, p, rng.randf_range(0.0, TAU), shoe_cols[1])

static func _shoe(k, p: Vector3, yaw: float, col: Color) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	k.box("rubber", Vector3(-0.035, 0.0, -0.075), Vector3(0.035, 0.018, 0.075), Color(0.92, 0.92, 0.9), 1.0, Kit.ALL, xf)
	k.box("fabric", Vector3(-0.033, 0.018, -0.07), Vector3(0.033, 0.06, 0.02), col, 1.0, Kit.ALL, xf)
	k.box("fabric", Vector3(-0.031, 0.018, 0.02), Vector3(0.031, 0.045, 0.072), col, 1.0, Kit.ALL, xf)

static func _hall_signs(c) -> void:
	_hall_extras(c)
	var k = c.kit("props_h")
	# "Ne pas grimper sur les filets" on the frame near its entrance steps, "Toilettes" by the vestibule doors
	Shell.board(k, "steel", Vector3(-23.77, 0.45, -1.62), Vector3.RIGHT, 0.4, 0.3, 0.02, Color(0.9, 0.9, 0.88))
	Shell.sign_quad(k, "tex_labels.jpg", Vector3(-23.757, 0.45, -1.62), Vector3.RIGHT, 0.38, 0.28, Rect2(1.0 / 3.0, 0.5, 1.0 / 3.0, 0.5))
	Shell.sign_quad(k, "tex_labels.jpg", Vector3(-17.205 - 0.006, 1.55, 4.2), Vector3.LEFT, 0.34, 0.26, Rect2(2.0 / 3.0, 0.5, 1.0 / 3.0, 0.5))
