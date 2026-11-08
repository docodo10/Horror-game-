## The soft-play hall's content: the 3-level padded play frame (decks with vinyl pads, padded posts with zip ties,
## rails, netting, kick panels, padded flights of steps with invisible ramps), the crawl tube from the landing (hide
## spot), the 4-lane wave slide and the spiral tube slide (glossy rotomoulded plastic swept along curves, with rider
## curves for the rides), the ball pit (MultiMesh balls), scattered balls, the toddler corner and the party tables.
extends RefCounted

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const Shell := preload("res://scripts/garderie/garderie_shell.gd")

const FRAME_BLUE := Color(0.13, 0.3, 0.62)
const FRAME_RED := Color(0.78, 0.16, 0.13)
const FRAME_YELLOW := Color(0.94, 0.72, 0.13)
const PAD_COLS := [Color(0.16, 0.36, 0.7), Color(0.8, 0.2, 0.15)]
const LANE_COLS := [Color(0.86, 0.15, 0.12), Color(0.96, 0.74, 0.1), Color(0.12, 0.42, 0.82), Color(0.15, 0.62, 0.28)]
const BALL_COLS := [Color(0.86, 0.12, 0.1), Color(0.97, 0.78, 0.08), Color(0.1, 0.38, 0.85), Color(0.12, 0.62, 0.25),
	Color(0.95, 0.45, 0.08), Color(0.55, 0.22, 0.68)]
const POST_R := 0.072

## Outline of the frame's footprint (counter-clockwise from the south-east corner): [a, b] segments on the floor plan.
const OUTLINE := [
	[Vector2(-23.8, 2.6), Vector2(-35.0, 2.6)],
	[Vector2(-35.0, 2.6), Vector2(-35.0, -5.4)],
	[Vector2(-35.0, -5.4), Vector2(-31.0, -5.4)],
	[Vector2(-31.0, -5.4), Vector2(-31.0, -1.8)],
	[Vector2(-31.0, -1.8), Vector2(-23.8, -1.8)],
	[Vector2(-23.8, -1.8), Vector2(-23.8, 2.6)],
]
## Railings inside the frame (upper deck edges above a lower deck): [a, b, deck_y]
const INNER := [
	[Vector2(-27.4, -1.8), Vector2(-27.4, 2.6), GL.L2],
	[Vector2(-31.0, -1.8), Vector2(-31.0, 2.6), GL.L3],
]

static func build(c) -> void:
	_frame(c)
	_tube(c)
	_wave(c)
	_spiral(c)
	_pit(c)
	_scatter_balls(c)
	_toddler(c)
	_party(c)

# ====================================================================== play frame

static func _tops_at(p: Vector2) -> float:
	## highest walking surface (deck or flight top) whose footprint contains p, else the floor
	var best := GL.HALL
	for d in GL.DECKS:
		if p.x >= float(d[0]) and p.x <= float(d[1]) and p.y >= float(d[2]) and p.y <= float(d[3]):
			best = maxf(best, float(d[4]))
	for f in GL.FLIGHTS:
		var xa := minf(float(f[0]), float(f[1]))
		var xb := maxf(float(f[0]), float(f[1]))
		if p.x >= xa and p.x <= xb and p.y >= float(f[2]) and p.y <= float(f[3]):
			best = maxf(best, float(f[5]))
	return best

## Openings in the outer netting: [axis_value_check Callable-free form] -> list of [segment index, s0, s1, y0, y1]
static func _opening(p: Vector2, y: float) -> bool:
	var W: Dictionary = GL.WAVE
	# hall floor -> L1 flight arrival
	var f0: Array = GL.FLIGHTS[0]
	if absf(p.x - float(f0[1])) < 0.05 and p.y > float(f0[2]) - 0.02 and p.y < float(f0[3]) + 0.02 and y > GL.L1 - 0.05:
		return true
	# wave slide start (deck L3, east edge of the tower)
	if absf(p.x - float(W.x_start)) < 0.05 and p.y > float(W.z0) and p.y < float(W.z1) and y > GL.L3 - 0.05:
		return true
	# spiral entry (south edge of the tower, L3)
	var S: Dictionary = GL.SPIRAL
	if absf(p.y - float(S.z_entry)) < 0.05 and absf(p.x - float(S.x_entry)) < 0.62 and y > GL.L3 - 0.05:
		return true
	return false

static func _frame(c) -> void:
	var k = c.kit("play")
	var ks = c.kit("play_small")
	var kn = c.kit("nets")
	var cl = c.col("play")
	var F := GL.HALL
	# decks: dark plywood + steel edge + vinyl pads
	for d in GL.DECKS:
		var x0: float = d[0]
		var x1: float = d[1]
		var z0: float = d[2]
		var z1: float = d[3]
		var y: float = d[4]
		k.box("steel", Vector3(x0, y - GL.DECK_T, z0), Vector3(x1, y - 0.05, z1), FRAME_BLUE, 1.0, Kit.ALL)
		cl.box(Vector3(x0, y - GL.DECK_T, z0), Vector3(x1, y, z1))
		var nx := maxi(1, int(round((x1 - x0) / 1.2)))
		var nz := maxi(1, int(round((z1 - z0) / 1.1)))
		for i in nx:
			for j in nz:
				var ax := x0 + (x1 - x0) * float(i) / nx + 0.008
				var bx := x0 + (x1 - x0) * float(i + 1) / nx - 0.008
				var az := z0 + (z1 - z0) * float(j) / nz + 0.008
				var bz := z0 + (z1 - z0) * float(j + 1) / nz - 0.008
				k.box("vinyl_flat", Vector3(ax, y - 0.05, az), Vector3(bx, y, bz), PAD_COLS[(i + j) % 2], 1.0, Kit.FACE_PY | Kit.FACE_PX | Kit.FACE_NX | Kit.FACE_PZ | Kit.FACE_NZ)
	# posts along the outline + inner railings
	var posts := {}
	for seg in OUTLINE:
		_post_points(seg[0], seg[1], 1.8, posts)
	for seg in INNER:
		_post_points(seg[0], seg[1], 1.8, posts)
	var Wv: Dictionary = GL.WAVE
	for key in posts:
		var p: Vector2 = posts[key]
		var top := _tops_at(p + Vector2(0.05, 0.05))
		for o in [Vector2(-0.05, -0.05), Vector2(0.05, -0.05), Vector2(-0.05, 0.05)]:
			top = maxf(top, _tops_at(p + o))
		var ytop := GL.TOP_Y if top >= GL.L3 - 0.01 else top + GL.RAIL_H
		if absf(p.x - float(Wv.x_start)) < 0.1 and p.y > float(Wv.z0) - 0.1 and p.y < float(Wv.z1) + 0.1:
			ytop = GL.L3 - 0.02
		_padded_post(c, k, ks, Vector3(p.x, F, p.y), ytop, FRAME_BLUE)
		c.col_see("play").box(Vector3(p.x - POST_R, F, p.y - POST_R), Vector3(p.x + POST_R, ytop, p.y + POST_R))
	# outer netting (full height from deck L1 to the local top), kick panels below L1, rails at every level
	for seg in OUTLINE:
		_net_wall(c, kn, k, seg[0], seg[1], posts)
	for seg in INNER:
		_rail_net(c, kn, k, seg[0], seg[1], float(seg[2]), posts)
	# flights of padded steps with ramps
	for f in GL.FLIGHTS:
		_flight(c, k, f)
	# side nets of the inner flights
	var f1: Array = GL.FLIGHTS[1]
	_net_panel(kn, Vector3(float(f1[0]), GL.L1, float(f1[2])), Vector3(float(f1[1]), GL.L2 + GL.RAIL_H, float(f1[2])))
	c.col_see("play").box(Vector3(float(f1[1]), GL.L1, float(f1[2]) - 0.03), Vector3(float(f1[0]), GL.L2 + GL.RAIL_H, float(f1[2]) + 0.03))
	var f2: Array = GL.FLIGHTS[2]
	_net_panel(kn, Vector3(float(f2[0]), GL.L2, float(f2[3])), Vector3(float(f2[1]), GL.L3 + GL.RAIL_H, float(f2[3])))
	c.col_see("play").box(Vector3(float(f2[1]), GL.L2, float(f2[3]) - 0.03), Vector3(float(f2[0]), GL.L3 + GL.RAIL_H, float(f2[3]) + 0.03))
	# a few punching bags hanging under the upper decks (soft obstacles), roof canopy over the slide start
	for pb in [Vector3(-29.4, GL.L2 - GL.DECK_T, 0.2), Vector3(-33.2, GL.L2 - GL.DECK_T, -3.4), Vector3(-33.0, GL.L3 - GL.DECK_T, 0.8)]:
		var pts := PackedVector3Array()
		for i in 9:
			pts.append(Vector3(pb.x, pb.y - 0.25 - 0.95 * float(i) / 8.0, pb.z))
		k.tube("vinyl", pts, 0.16, 16, FRAME_RED, 1.0, true, func(i: int, _a: float) -> float: return 0.85 + 0.15 * sin(PI * float(i) / 8.0))
		ks.box("metal", Vector3(pb.x - 0.008, pb.y - 0.26, pb.z - 0.008), Vector3(pb.x + 0.008, pb.y, pb.z + 0.008), Color(0.4, 0.4, 0.4))
	var W: Dictionary = GL.WAVE
	var cz0: float = W.z0
	var cz1: float = W.z1
	k.tube("vinyl", PackedVector3Array([Vector3(-31.0, GL.L3 + 1.9, cz0), Vector3(-31.0, GL.L3 + 1.9, cz1)]), 0.045, 12, FRAME_RED)

static func _post_points(a: Vector2, b: Vector2, step: float, out: Dictionary) -> void:
	var L := a.distance_to(b)
	var n := maxi(1, int(ceil(L / step)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var key := Vector2i(int(round(p.x * 20.0)), int(round(p.y * 20.0)))
		out[key] = p

## Padded vertical post: vinyl wrap with soft wobble, black zip ties, foam cap.
static func _padded_post(c, k, ks, base: Vector3, ytop: float, col: Color) -> void:
	var pts := PackedVector3Array()
	var h := ytop - base.y
	var rows := maxi(4, int(h / 0.18))
	for i in rows + 1:
		pts.append(base + Vector3(0, h * float(i) / float(rows), 0))
	var ph := fmod(absf(base.x * 3.7 + base.z * 1.3), TAU)
	k.tube("vinyl", pts, POST_R, 12, col, 1.0, false, func(i: int, ang: float) -> float:
		var t := float(i) / float(rows)
		return 1.0 + 0.06 * sin(ang * 2.0 + ph + t * 9.0) * sin(t * 31.0 + ph) + 0.03 * sin(ang * 5.0 - ph))
	k.sphere("vinyl", base + Vector3(0, h, 0), POST_R * 1.05, 10, 6, col, Vector3(1.0, 0.6, 1.0))
	var y := base.y + 0.35
	while y < ytop - 0.15:
		ks.tube("rubber", PackedVector3Array([Vector3(base.x, y, base.z), Vector3(base.x, y + 0.012, base.z)]), POST_R * 1.07, 12, Color(0.05, 0.05, 0.06), 1.0)
		y += 0.42

static func _net_panel(kn, a: Vector3, b: Vector3) -> void:
	## vertical net rectangle between the vertical edges at a (bottom) and b (top) — a.y bottom, b.y top
	var p0 := Vector3(a.x, a.y, a.z)
	var p1 := Vector3(b.x, a.y, b.z)
	var p2 := Vector3(b.x, b.y, b.z)
	var p3 := Vector3(a.x, b.y, a.z)
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var L := d.length()
	if L < 0.05:
		return
	var nrm := Vector3(-d.z, 0, d.x).normalized()
	kn.quad("net", p0, p1, p2, p3, nrm, Vector2(0, -a.y), Vector2(L, -a.y), Vector2(L, -b.y), Vector2(0, -b.y))

## Outer wall of the frame along a->b: kick panels from the floor to deck L1, nets from L1 to the local top,
## horizontal padded rails at each level, openings where the tube / flights / slides connect.
static func _net_wall(c, kn, k, a: Vector2, b: Vector2, posts: Dictionary) -> void:
	var cl = c.col("play")
	var cls = c.col_see("play")
	var dir := (b - a).normalized()
	var out := Vector2(dir.y, -dir.x)   # outward normal for the counter-clockwise outline (checked below)
	var mid := (a + b) * 0.5
	if _tops_at(mid + out * 0.2) > GL.HALL + 0.01:
		out = -out
	var L := a.distance_to(b)
	var n := maxi(1, int(ceil(L / 1.8)))
	var F := GL.HALL
	for i in n:
		var pa := a.lerp(b, float(i) / float(n))
		var pb := a.lerp(b, float(i + 1) / float(n))
		var pm := (pa + pb) * 0.5
		var inner := pm - out * 0.2
		var top := _tops_at(inner)
		var ytop := GL.TOP_Y if top >= GL.L3 - 0.01 else top + GL.RAIL_H
		# kick panel (solid vinyl) from the floor to the deck
		if not (_opening(pm, GL.L1 - 0.5) and false):
			var mn := Vector3(minf(pa.x, pb.x), F, minf(pa.y, pb.y))
			var mx := Vector3(maxf(pa.x, pb.x), GL.L1 - 0.02, maxf(pa.y, pb.y))
			mn += Vector3(out.x, 0, out.y) * 0.0
			if absf(dir.x) > 0.5:
				mn.z -= 0.03
				mx.z += 0.03
			else:
				mn.x -= 0.03
				mx.x += 0.03
			k.box("vinyl_flat", mn, mx, FRAME_BLUE.darkened(0.25))
			cl.box(mn, mx)
		# net in vertical bands, skipping openings (sampled every 0.3 m and 0.25 m up)
		var levels := [GL.L1, GL.L2, GL.L3]
		var y0 := GL.L1
		var bands: Array = []
		for yy in [GL.L1, GL.L2, GL.L3, ytop]:
			if float(yy) > y0 + 0.01 and float(yy) <= ytop + 0.001:
				bands.append([y0, float(yy)])
				y0 = float(yy)
		for band in bands:
			var by0: float = band[0]
			var by1: float = band[1]
			if _opening(pm, by0 + 0.1):
				# split along the segment around the opening
				var steps := 12
				var run_start := -1
				for s in steps + 1:
					var t := float(s) / float(steps)
					var q := pa.lerp(pb, t)
					var open := s < steps and _opening(pa.lerp(pb, (float(s) + 0.5) / float(steps)), by0 + 0.1)
					if not open and run_start < 0 and s < steps:
						run_start = s
					if (open or s == steps) and run_start >= 0:
						var qa := pa.lerp(pb, float(run_start) / float(steps))
						_net_panel(kn, Vector3(qa.x, by0, qa.y), Vector3(q.x, by1, q.y))
						_col_strip(cls, qa, q, by0, by1)
						run_start = -1
				continue
			_net_panel(kn, Vector3(pa.x, by0, pa.y), Vector3(pb.x, by1, pb.y))
			_col_strip(cls, pa, pb, by0, by1)
		# horizontal padded rails at deck levels within this segment and at its top
		for lv in levels:
			if float(lv) <= ytop - 0.3 and not _opening(pm, float(lv) + 0.1):
				k.tube("vinyl", PackedVector3Array([Vector3(pa.x, float(lv), pa.y), Vector3(pb.x, float(lv), pb.y)]), 0.05, 10, FRAME_RED)
		k.tube("vinyl", PackedVector3Array([Vector3(pa.x, ytop - 0.06, pa.y), Vector3(pb.x, ytop - 0.06, pb.y)]), 0.055, 10, FRAME_YELLOW)
	posts = posts

static func _col_strip(cl, a: Vector2, b: Vector2, y0: float, y1: float) -> void:
	var mn := Vector3(minf(a.x, b.x) - 0.03, y0, minf(a.y, b.y) - 0.03)
	var mx := Vector3(maxf(a.x, b.x) + 0.03, y1, maxf(a.y, b.y) + 0.03)
	cl.box(mn, mx)

## Railing net along an inner deck edge at deck_y (with openings where flights arrive).
static func _rail_net(c, kn, k, a: Vector2, b: Vector2, deck_y: float, posts: Dictionary) -> void:
	var cl = c.col_see("play")
	var top := deck_y + GL.RAIL_H
	var pieces: Array = [[a, b]]
	for f in GL.FLIGHTS:
		if absf(float(f[5]) - deck_y) < 0.01 and absf(float(f[1]) - a.x) < 0.05:
			var np: Array = []
			for pc in pieces:
				var pa: Vector2 = pc[0]
				var pb: Vector2 = pc[1]
				var lo := minf(pa.y, pb.y)
				var hi := maxf(pa.y, pb.y)
				var f0 := float(f[2])
				var f1 := float(f[3])
				if f1 <= lo or f0 >= hi:
					np.append(pc)
					continue
				if f0 > lo:
					np.append([Vector2(pa.x, lo), Vector2(pa.x, f0)])
				if f1 < hi:
					np.append([Vector2(pa.x, f1), Vector2(pa.x, hi)])
			pieces = np
	for pc in pieces:
		var pa: Vector2 = pc[0]
		var pb: Vector2 = pc[1]
		_net_panel(kn, Vector3(pa.x, deck_y, pa.y), Vector3(pb.x, top, pb.y))
		_col_strip(cl, pa, pb, deck_y, top)
		k.tube("vinyl", PackedVector3Array([Vector3(pa.x, top - 0.06, pa.y), Vector3(pb.x, top - 0.06, pb.y)]), 0.055, 10, FRAME_YELLOW)
	k.tube("vinyl", PackedVector3Array([Vector3(a.x, deck_y, a.y), Vector3(b.x, deck_y, b.y)]), 0.05, 10, FRAME_RED)
	posts = posts

## Padded steps between two levels + invisible ramp collider through the nosings.
static func _flight(c, k, f: Array) -> void:
	var x_low: float = f[0]
	var x_high: float = f[1]
	var z0: float = f[2]
	var z1: float = f[3]
	var y_low: float = f[4]
	var y_high: float = f[5]
	var n: int = f[6]
	var rise := (y_high - y_low) / float(n)
	for i in range(1, n):
		var xa := lerpf(x_low, x_high, float(i) / float(n))
		var xb := lerpf(x_low, x_high, float(i + 1) / float(n))
		var mn := Vector3(minf(xa, xb), y_low, z0 + 0.02)
		var mx := Vector3(maxf(xa, xb), y_low + rise * i, z1 - 0.02)
		k.box("vinyl", mn, mx, PAD_COLS[i % 2] if y_low > GL.HALL else [FRAME_YELLOW, FRAME_RED][i % 2])
	c.col("play").ramp_x(x_low, x_high, y_low, y_high, z0, z1)
	if y_low <= GL.HALL + 0.01:
		# hall floor -> L1: padded side walls
		for zz in [z0 - 0.06, z1]:
			k.box("vinyl", Vector3(minf(x_low, x_high), y_low, zz), Vector3(maxf(x_low, x_high), y_high + 0.45, zz + 0.06), FRAME_BLUE)
			c.col("play").box(Vector3(minf(x_low, x_high), y_low, zz), Vector3(maxf(x_low, x_high), y_high + 0.9, zz + 0.06))

# ====================================================================== crawl tube (hide spot)

static func _tube(c) -> void:
	var T: Dictionary = GL.TUBE
	var k = c.kit("play")
	var kin = c.kit("tube_inner")
	var mx: float = T.mouth_x
	var ex: float = T.end_x
	var z: float = T.z
	var r: float = T.r
	var bell: float = T.bell
	var cy := GL.UP + r
	var rows := 22
	var pts := PackedVector3Array()
	for i in rows + 1:
		pts.append(Vector3(lerpf(mx, ex, float(i) / float(rows)), cy, z))
	var flare := func(i: int, ang: float, inner: bool) -> float:
		var t := float(i) / float(rows)
		var f := maxf(0.0, 1.0 - t / 0.18)                 # the bell: first 18 % of the length, at the mouth
		var up := maxf(0.0, cos(ang))                       # frames: ang 0 = up -> the floor never dips
		var rr := 1.0 + (bell / r - 1.0) * f * f * (0.3 + 0.7 * up)
		return rr * (1.0 if inner else (r + 0.045) / r)
	var yellow := Color(0.96, 0.7, 0.08)
	k.tube("plastic", pts, r, 30, yellow, 1.0, false, func(i: int, ang: float) -> float: return flare.call(i, ang, false))
	kin.tube("plastic", pts, r, 30, yellow * 0.88, 1.0, false, func(i: int, ang: float) -> float: return flare.call(i, ang, true))
	_flip_last(kin, "plastic", rows, 30)
	# red rim at the mouth, closed padded end against the wall
	var rim := PackedVector3Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		var rr: float = r * flare.call(0, a, true) + 0.022
		rim.append(Vector3(mx - 0.01, cy + cos(a) * rr, z + sin(a) * rr))
	k.tube("plastic", rim, 0.03, 8, Color(0.9, 0.2, 0.12))
	k.disc("vinyl_up", Vector3(ex - 0.01, cy, z), Vector3.LEFT, Vector3.UP, r + 0.01, 28, Color(0.8, 0.2, 0.15))
	k.disc("plastic", Vector3(ex, cy, z), Vector3.RIGHT, Vector3.UP, r + 0.045, 28, yellow)
	# cradles holding it on the landing
	for sx in [mx + 0.45, ex - 0.4]:
		for sz in [-1.0, 1.0]:
			k.box("vinyl_up", Vector3(sx - 0.12, GL.UP, z + sz * (r - 0.05) - 0.09), Vector3(sx + 0.12, GL.UP + 0.16, z + sz * (r - 0.05) + 0.09), Color(0.15, 0.36, 0.66))
	# colliders: coarse shell (the landing is the floor inside), end cap
	var faces := PackedVector3Array()
	var cs := 16
	var cr := 8
	for i in cr:
		var xa := lerpf(mx, ex, float(i) / float(cr))
		var xb := lerpf(mx, ex, float(i + 1) / float(cr))
		for j in cs:
			var a0 := TAU * float(j) / float(cs)
			var a1 := TAU * float(j + 1) / float(cs)
			if cos((a0 + a1) * 0.5) < -0.85:
				continue
			var rr := r + 0.02
			var p00 := Vector3(xa, cy + cos(a0) * rr, z + sin(a0) * rr)
			var p01 := Vector3(xa, cy + cos(a1) * rr, z + sin(a1) * rr)
			var p10 := Vector3(xb, cy + cos(a0) * rr, z + sin(a0) * rr)
			var p11 := Vector3(xb, cy + cos(a1) * rr, z + sin(a1) * rr)
			faces.append_array(PackedVector3Array([p00, p10, p11, p00, p11, p01]))
	c.col("play").trimesh(faces)
	c.col("play").box(Vector3(ex - 0.02, GL.UP, z - r), Vector3(ex + 0.06, cy + r, z + r))

## Flips the winding + normals of the last grid emitted in a kit bin (inner faces of a shell).
static func _flip_last(kit, mat: String, rows: int, sides: int) -> void:
	var b = kit.bin(mat)
	var nv := (rows + 1) * (sides + 1)
	var start: int = b.v.size() - nv
	for i in range(start, b.v.size()):
		b.n[i] = -b.n[i]
	var ni := rows * sides * 6
	var s2: int = b.idx.size() - ni
	for t in ni / 3:
		var k := s2 + t * 3
		var tmp: int = b.idx[k + 1]
		b.idx[k + 1] = b.idx[k + 2]
		b.idx[k + 2] = tmp

# ====================================================================== wave slide

## Height of the wave slide's lane bottom at x (descending part + run-out).
static func wave_height(x: float) -> float:
	var W: Dictionary = GL.WAVE
	var xs: float = W.x_start
	var xf: float = W.x_flat
	var xe: float = W.x_end
	var xo: float = W.x_out
	var top: float = W.y_top
	var yend: float = W.y_end
	var yout: float = W.y_out
	if x <= xf:
		return top
	if x >= xe:
		var t := clampf((x - xe) / (xo - xe), 0.0, 1.0)
		return lerpf(yend, yout, t) + 0.04 * pow(maxf(0.0, (t - 0.85) / 0.15), 2.0)
	return top - (top - yend) * _wave_cdf((x - xf) / (xe - xf))

static var _cdf: PackedFloat32Array = PackedFloat32Array()

static func _wave_cdf(s: float) -> float:
	if _cdf.is_empty():
		var W: Dictionary = GL.WAVE
		var n := 400
		var fs := PackedFloat32Array()
		var tot := 0.0
		for i in n + 1:
			var u := float(i) / float(n)
			var base := pow(sin(PI * u), 0.8)
			var w := 1.0 + float(W.amp) * sin(TAU * float(W.waves) * u - PI * 0.5)
			var f := maxf(0.03, base * w)
			fs.append(f)
		var acc := PackedFloat32Array([0.0])
		for i in n:
			tot += fs[i]
			acc.append(tot)
		for i in acc.size():
			acc[i] /= tot
		_cdf = acc
	var x := clampf(s, 0.0, 1.0) * float(_cdf.size() - 1)
	var i0 := int(floor(x))
	var i1 := mini(i0 + 1, _cdf.size() - 1)
	return lerpf(_cdf[i0], _cdf[i1], x - float(i0))

static func _wave(c) -> void:
	var W: Dictionary = GL.WAVE
	var k = c.kit("slides")
	var z0: float = W.z0
	var z1: float = W.z1
	var lanes: int = W.lanes
	var xs: float = W.x_start
	var xo: float = W.x_out
	var lane_w := (z1 - z0 - 0.12) / float(lanes)
	# cross-section (z, dy, lane index for colour): lip, lanes with rounded troughs, double ridges between lanes
	var prof: Array = []
	prof.append([z0, 0.2, 0])
	prof.append([z0 + 0.03, 0.22, 0])
	prof.append([z0 + 0.06, 0.18, 0])
	for li in lanes:
		var a := z0 + 0.06 + li * lane_w
		var steps := 14
		for s in steps + 1:
			var u := float(s) / float(steps)
			var zz := a + u * lane_w
			var d := absf(u - 0.5) * 2.0
			var dy := 0.16 * pow(d, 3.2) + 0.012 * pow(d, 1.2)
			if li > 0 and s == 0:
				continue
			prof.append([zz, dy, li])
		if li < lanes - 1:
			prof.append([a + lane_w + 0.0, 0.2, li])
	prof.append([z1 - 0.06, 0.18, lanes - 1])
	prof.append([z1 - 0.03, 0.22, lanes - 1])
	prof.append([z1, 0.2, lanes - 1])
	var xs_list := PackedFloat32Array()
	var x := xs
	while x < xo:
		xs_list.append(x)
		x += 0.07 if x > float(W.x_flat) - 0.2 and x < float(W.x_end) + 0.3 else 0.12
	xs_list.append(xo)
	var rows := xs_list.size()
	var cols := prof.size()
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	P.resize(rows * cols)
	U.resize(rows * cols)
	C.resize(rows * cols)
	var along := 0.0
	var prev := Vector3.ZERO
	for i in rows:
		var xx := xs_list[i]
		var h := wave_height(xx)
		var ctr := Vector3(xx, h, (z0 + z1) * 0.5)
		if i > 0:
			along += ctr.distance_to(prev)
		prev = ctr
		var acc := 0.0
		for j in cols:
			var pr: Array = prof[j]
			var pz: float = pr[0]
			var dy: float = pr[1]
			if j > 0:
				acc += absf(pz - float(prof[j - 1][0])) + absf(dy - float(prof[j - 1][1]))
			P[i * cols + j] = Vector3(xx, h + dy, pz)
			U[i * cols + j] = Vector2(acc, along)
			C[i * cols + j] = LANE_COLS[int(pr[2])]
	k.grid("plastic", P, rows, cols, U, Color.WHITE, false, false, C)
	_fix_up(k, "plastic", rows * cols)
	# underside (simple flat shell) + edges
	var P2 := PackedVector3Array()
	var U2 := PackedVector2Array()
	P2.resize(rows * 2)
	U2.resize(rows * 2)
	for i in rows:
		var xx := xs_list[i]
		var h := wave_height(xx) - 0.05
		P2[i * 2] = Vector3(xx, h, z0)
		P2[i * 2 + 1] = Vector3(xx, h, z1)
		U2[i * 2] = Vector2(0, xx)
		U2[i * 2 + 1] = Vector2(1, xx)
	k.grid("plastic", P2, rows, 2, U2, Color(0.75, 0.72, 0.68))
	_fix_down(k, "plastic", rows * 2)
	for zz in [z0, z1]:
		var Pe := PackedVector3Array()
		var Ue := PackedVector2Array()
		for i in rows:
			var xx := xs_list[i]
			var h := wave_height(xx)
			Pe.append(Vector3(xx, h - 0.05, zz))
			Pe.append(Vector3(xx, h + 0.2, zz))
			Ue.append(Vector2(xx, 0))
			Ue.append(Vector2(xx, 0.25))
		k.grid("plastic", Pe, rows, 2, Ue, LANE_COLS[0] if zz == z0 else LANE_COLS[lanes - 1])
		_fix_side(k, "plastic", rows * 2, Vector3(0, 0, -1 if zz == z0 else 1))
	# legs (frame blue steel, padded at the bottom) every ~2 m under the slide
	var lx := float(W.x_flat) + 0.6
	while lx < float(W.x_out) - 0.4:
		var hy := wave_height(lx) - 0.06
		for zz in [z0 + 0.1, z1 - 0.1]:
			k.tube("steel", PackedVector3Array([Vector3(lx, GL.HALL, zz), Vector3(lx, hy, zz)]), 0.04, 10, FRAME_BLUE)
		k.tube("steel", PackedVector3Array([Vector3(lx, hy - 0.05, z0 + 0.1), Vector3(lx, hy - 0.05, z1 - 0.1)]), 0.03, 8, FRAME_BLUE)
		c.col("play").box(Vector3(lx - 0.05, GL.HALL, z0), Vector3(lx + 0.05, hy, z0 + 0.15))
		c.col("play").box(Vector3(lx - 0.05, GL.HALL, z1 - 0.15), Vector3(lx + 0.05, hy, z1))
		lx += 1.9
	# colliders: coarse trimesh of the lanes' surface + the side lips
	var faces := PackedVector3Array()
	var cxs := PackedFloat32Array()
	var cx := xs
	while cx < xo:
		cxs.append(cx)
		cx += 0.25
	cxs.append(xo)
	for i in cxs.size() - 1:
		var xa := cxs[i]
		var xb := cxs[i + 1]
		var ha := wave_height(xa)
		var hb := wave_height(xb)
		faces.append_array(PackedVector3Array([Vector3(xa, ha, z0), Vector3(xb, hb, z0), Vector3(xb, hb, z1),
			Vector3(xa, ha, z0), Vector3(xb, hb, z1), Vector3(xa, ha, z1)]))
		for zz in [z0, z1]:
			faces.append_array(PackedVector3Array([Vector3(xa, ha, zz), Vector3(xb, hb, zz), Vector3(xb, hb + 0.35, zz),
				Vector3(xa, ha, zz), Vector3(xb, hb + 0.35, zz), Vector3(xa, ha + 0.35, zz)]))
	c.col("slides").trimesh(faces)
	# rider curve: lane 2 trough
	var lz := z0 + 0.06 + lane_w * 1.5
	var curve := Curve3D.new()
	curve.bake_interval = 0.05
	var cxx := float(W.x_start) + 0.15
	while cxx < xo - 0.05:
		curve.add_point(Vector3(cxx, wave_height(cxx) + 0.02, lz))
		cxx += 0.1
	curve.add_point(Vector3(xo - 0.05, wave_height(xo - 0.05) + 0.02, lz))
	c.slides["wave"] = {"curve": curve, "kind": "wave", "exit_dir": Vector3.RIGHT, "mu": 0.2, "mu_out": 0.62,
		"out_from": curve.get_baked_length() - (xo - float(W.x_end)), "eye": 0.74, "floor_y": GL.HALL,
		"top": Vector3(float(W.x_start) - 0.45, GL.L3 + 0.6, lz), "trigger": Vector3(0.6, 1.2, float(W.z1) - float(W.z0))}

## Normals of the last n vertices of a bin forced upward-facing (slide top) — finite differences can face down.
static func _fix_up(kit, mat: String, n: int) -> void:
	var b = kit.bin(mat)
	var s: int = b.v.size() - n
	var flip := false
	var cnt := 0
	for i in range(s, b.v.size()):
		if b.n[i].y < 0.0:
			cnt += 1
	flip = cnt > n / 2
	if flip:
		_flip_tail(b, s, n)

static func _fix_down(kit, mat: String, n: int) -> void:
	var b = kit.bin(mat)
	var s: int = b.v.size() - n
	if b.n[s].y > 0.0:
		_flip_tail(b, s, n)

static func _fix_side(kit, mat: String, n: int, want: Vector3) -> void:
	var b = kit.bin(mat)
	var s: int = b.v.size() - n
	if b.n[s].dot(want) < 0.0:
		_flip_tail(b, s, n)

## Flips normals of vertices [s, s+n) and the winding of the triangles that use only them.
static func _flip_tail(b, s: int, n: int) -> void:
	for i in range(s, s + n):
		b.n[i] = -b.n[i]
	var k: int = b.idx.size() - 3
	while k >= 0 and b.idx[k] >= s and b.idx[k + 1] >= s and b.idx[k + 2] >= s:
		var tmp: int = b.idx[k + 1]
		b.idx[k + 1] = b.idx[k + 2]
		b.idx[k + 2] = tmp
		k -= 3

# ====================================================================== spiral tube slide

## Rider path (tube bottom) of the spiral: chute south from the deck, helix, run-out east.
static func spiral_points() -> PackedVector3Array:
	var S: Dictionary = GL.SPIRAL
	var xc: float = S.xc
	var zc: float = S.zc
	var R: float = S.radius
	var turns: float = S.turns
	var y0: float = S.y_top
	var y1: float = S.y_end
	var pts := PackedVector3Array()
	var chute := zc - float(S.z_entry)
	var helix_len := TAU * R * turns
	var total := chute + helix_len
	var z := float(S.z_entry) - 0.35
	while z < zc:
		var s := maxf(0.0, z - float(S.z_entry))
		pts.append(Vector3(xc - R, y0 - (y0 - y1) * pow(s / total, 0.95) if z > float(S.z_entry) else y0, z))
		z += 0.1
	var n := int(helix_len / 0.08)
	for i in n + 1:
		var ph := TAU * turns * float(i) / float(n)
		var s := chute + R * ph
		var y := y0 - (y0 - y1) * pow(s / total, 0.95)
		pts.append(Vector3(xc - R * cos(ph), y, zc + R * sin(ph)))
	var end := pts[pts.size() - 1]
	var x := end.x + 0.1
	while x <= float(S.x_out):
		var t := (x - end.x) / (float(S.x_out) - end.x)
		pts.append(Vector3(x, lerpf(y1, GL.HALL + 0.3, t), end.z))
		x += 0.1
	return pts

static func _spiral(c) -> void:
	var S: Dictionary = GL.SPIRAL
	var k = c.kit("slides")
	var kin = c.kit("tube_inner")
	var tr: float = S.tube_r
	var path := spiral_points()
	# tube centre line = rider path + up * tube_r
	var cen := PackedVector3Array()
	for p in path:
		cen.append(p + Vector3(0, tr, 0))
	var red := Color(0.82, 0.12, 0.1)
	var n := cen.size()
	# split: entry hood (open top) / closed tube / open run-out half-pipe
	var i_closed := 6
	var helix_end := n - 1
	for i in range(n - 1, 0, -1):
		if absf(path[i].z - path[n - 1].z) > 0.02:
			helix_end = i
			break
	var closed := cen.slice(i_closed, helix_end + 2)
	k.tube("plastic_tube", closed, tr + 0.035, 30, red, 1.0)
	kin.tube("plastic_tube", closed, tr, 30, red * 0.85, 1.0)
	_flip_last(kin, "plastic_tube", closed.size() - 1, 30)
	# open parts: half-pipe (lower half of the circle), frames' x = up
	for part in [cen.slice(0, i_closed + 1), cen.slice(helix_end, n)]:
		_half_pipe(k, part, tr, red)
	# seams (bolted flanges) every ~1.1 m along the closed tube
	var acc := 0.0
	for i in range(1, closed.size()):
		acc += closed[i].distance_to(closed[i - 1])
		if acc > 1.1:
			acc = 0.0
			var a := closed[i - 1]
			var b := closed[i]
			var dir := (b - a).normalized()
			k.tube("plastic", PackedVector3Array([a + dir * 0.0, a + dir * 0.03]), tr + 0.06, 30, red * 0.92, 1.0, true)
	# central pole + arms
	var xc: float = S.xc
	var zc: float = S.zc
	var ytop := float(S.y_top) + 0.8
	Shell.padded_column(c, "slides", "vinyl", xc, zc, GL.HALL, GL.HALL + 1.0, 0.16, 5)
	k.tube("steel", PackedVector3Array([Vector3(xc, GL.HALL + 1.0, zc), Vector3(xc, ytop, zc)]), 0.09, 12, FRAME_BLUE)
	c.col("slides").box(Vector3(xc - 0.18, GL.HALL, zc - 0.18), Vector3(xc + 0.18, ytop, zc + 0.18))
	for i in range(i_closed, helix_end, 18):
		var p := cen[i]
		k.tube("steel", PackedVector3Array([Vector3(xc, p.y - tr - 0.02, zc), Vector3(p.x, p.y - tr - 0.02, p.z)]), 0.035, 8, FRAME_BLUE)
	# collider: coarse outer shell faces
	var faces := PackedVector3Array()
	var step := 4
	for i in range(0, n - step, step):
		var a := cen[i]
		var b := cen[i + step]
		var d := (b - a)
		d.y = 0.0
		var side := Vector3(-d.z, 0, d.x).normalized() * (tr + 0.04)
		var up := Vector3(0, tr + 0.04, 0)
		for q in [[side, up], [up, -side], [-side, -up], [-up, side]]:
			var o0: Vector3 = q[0]
			var o1: Vector3 = q[1]
			faces.append_array(PackedVector3Array([a + o0, b + o0, b + o1, a + o0, b + o1, a + o1]))
	c.col("slides").trimesh(faces)
	var curve := Curve3D.new()
	curve.bake_interval = 0.05
	for p in path:
		curve.add_point(p + Vector3(0, 0.02, 0))
	c.slides["spiral"] = {"curve": curve, "kind": "spiral", "exit_dir": Vector3.RIGHT, "mu": 0.16, "mu_out": 0.6,
		"out_from": curve.get_baked_length() - (float(S.x_out) - path[helix_end].x), "eye": 0.72, "floor_y": GL.HALL,
		"top": Vector3(float(S.x_entry), GL.L3 + 0.6, float(S.z_entry) - 0.45), "trigger": Vector3(1.0, 1.2, 0.6)}

## Lower half of a tube along `cen` (frames x = up): open chute / run-out.
static func _half_pipe(k, cen: PackedVector3Array, r: float, col: Color) -> void:
	if cen.size() < 2:
		return
	var F := Kit.frames(cen, Vector3.UP)
	var rows := cen.size()
	var cols := 17
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	P.resize(rows * cols * 2)
	U.resize(rows * cols * 2)
	for side in 2:
		var rr := r + (0.035 if side == 0 else 0.0)
		for i in rows:
			var f: Basis = F[i]
			for j in cols:
				var ang := PI * 0.5 + PI * float(j) / float(cols - 1)
				P[side * rows * cols + i * cols + j] = cen[i] + (f.x * cos(ang) + f.y * sin(ang)) * rr
				U[side * rows * cols + i * cols + j] = Vector2(float(j) * 0.1, float(i) * 0.1)
	k.grid("plastic_tube", P.slice(0, rows * cols), rows, cols, U.slice(0, rows * cols), col)
	_fix_down_avg(k, "plastic_tube", rows * cols)
	k.grid("plastic_tube", P.slice(rows * cols), rows, cols, U.slice(rows * cols), col)
	_fix_up(k, "plastic_tube", rows * cols)

static func _fix_down_avg(kit, mat: String, n: int) -> void:
	var b = kit.bin(mat)
	var s: int = b.v.size() - n
	var cnt := 0
	for i in range(s, b.v.size()):
		if b.n[i].y > 0.0:
			cnt += 1
	if cnt > n / 2:
		_flip_tail(b, s, n)

# ====================================================================== ball pit

static func _pit(c) -> void:
	var P: Dictionary = GL.PIT
	var k = c.kit("play")
	var x0: float = P.x0
	var x1: float = P.x1
	var z0: float = P.z0
	var z1: float = P.z1
	var t: float = P.wall_t
	var h: float = P.wall_h
	var F := GL.HALL
	var gz0: float = P.gate_z0
	var gz1: float = P.gate_z1
	var walls := [
		[Vector3(x0, F, z0), Vector3(x1, F + h, z0 + t)],
		[Vector3(x0, F, z1 - t), Vector3(x1, F + h, z1)],
		[Vector3(x0, F, z0 + t), Vector3(x0 + t, F + h, z1 - t)],
		[Vector3(x1 - t, F, z0 + t), Vector3(x1, F + h, gz0)],
		[Vector3(x1 - t, F, gz1), Vector3(x1, F + h, z1 - t)],
	]
	for w in walls:
		k.box("vinyl", w[0], w[1], FRAME_BLUE)
		c.col("play").box(w[0], w[1])
	# rounded top rails
	for seg in [[Vector3(x0, F + h, z0 + t * 0.5), Vector3(x1, F + h, z0 + t * 0.5)], [Vector3(x0, F + h, z1 - t * 0.5), Vector3(x1, F + h, z1 - t * 0.5)],
			[Vector3(x0 + t * 0.5, F + h, z0), Vector3(x0 + t * 0.5, F + h, z1)], [Vector3(x1 - t * 0.5, F + h, z0), Vector3(x1 - t * 0.5, F + h, gz0)],
			[Vector3(x1 - t * 0.5, F + h, gz1), Vector3(x1 - t * 0.5, F + h, z1)]]:
		k.tube("vinyl", PackedVector3Array([seg[0], seg[1]]), t * 0.52, 14, FRAME_RED)
	# low padded step in the gate
	k.box("vinyl", Vector3(x1 - t, F, gz0), Vector3(x1 + 0.3, F + 0.22, gz1), FRAME_YELLOW)
	c.col("play").box(Vector3(x1 - t, F, gz0), Vector3(x1 + 0.3, F + 0.22, gz1))
	# dark ball bed (seen through the gaps between balls)
	var kb = c.kit("balls")
	kb.box("dark", Vector3(x0 + t, F, z0 + t), Vector3(x1 - t, F + float(P.fill) - 0.11, z1 - t), Color.WHITE, 1.0, Kit.FACE_PY)
	# balls: 3 jittered layers, uneven surface
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var rad := 0.037
	var sp := 0.071
	var fill: float = P.fill
	var ax := x0 + t + rad
	var bx := x1 - t - rad
	var az := z0 + t + rad
	var bz := z1 - t - rad
	for layer in 2:
		var off := 0.5 * sp * float(layer % 2)
		var zz := az + off
		var row := 0
		while zz <= bz:
			var xx := ax + off + (0.5 * sp if row % 2 == 1 else 0.0)
			while xx <= bx:
				var mound := 0.05 * sin(xx * 1.7 + zz * 0.9) + 0.03 * sin(xx * 4.1 - zz * 3.3)
				var y := F + fill + mound - float(layer) * sp * 0.82 + rng.randf_range(-0.012, 0.012)
				if layer == 0 or rng.randf() < 0.75:
					var p := Vector3(xx + rng.randf_range(-0.01, 0.01), y, zz + rng.randf_range(-0.01, 0.01))
					var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)).scaled(Vector3.ONE * rng.randf_range(0.96, 1.04))
					xforms.append(Transform3D(b, p))
					var cc: Color = BALL_COLS[rng.randi() % BALL_COLS.size()]
					cols.append(cc.lerp(Color(0.85, 0.85, 0.82), rng.randf() * rng.randf() * 0.3))
				xx += sp
			zz += sp * 0.87
			row += 1
	var mmi := _ball_multimesh(c, xforms, cols, "BallPitBalls")
	mmi.visibility_range_end = 32.0
	mmi.visibility_range_end_margin = 3.0
	c.notes.append("ball pit: %d balls" % xforms.size())

static func _ball_mesh() -> ArrayMesh:
	# icosphere (1 subdivision, 80 triangles), smooth normals, radius 0.037
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var mids := {}
	var nf: Array = []
	for f in faces:
		var m := []
		for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
			var key := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			if not mids.has(key):
				verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
				mids[key] = verts.size() - 1
			m.append(mids[key])
		nf.append([f[0], m[0], m[2]])
		nf.append([f[1], m[1], m[0]])
		nf.append([f[2], m[2], m[1]])
		nf.append([m[0], m[1], m[2]])
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var I := PackedInt32Array()
	for v in verts:
		V.append(v * 0.037)
		N.append(v)
	for f in nf:
		# icosphere faces are counter-clockwise from outside: emit clockwise for Godot
		I.append(f[0]); I.append(f[2]); I.append(f[1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static var _ball_mesh_cache: ArrayMesh = null

static func _ball_multimesh(c, xforms: Array[Transform3D], cols: Array[Color], name: String) -> MultiMeshInstance3D:
	if _ball_mesh_cache == null:
		_ball_mesh_cache = _ball_mesh()
	var mesh := _ball_mesh_cache.duplicate() as ArrayMesh
	mesh.surface_set_material(0, c.mats.mat("balls"))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.region("balls").add_child(mmi)
	return mmi

## Balls that escaped: spilling from the pit gate, at the slide run-outs, under the frame, a trail toward the steps.
static func _scatter_balls(c) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var F := GL.HALL + 0.037
	var clusters := [[Vector3(-24.6, F, 6.6), 0.9, 34], [Vector3(-20.6, F, -3.9), 1.0, 16], [Vector3(-31.0, F, 5.8), 0.8, 10],
		[Vector3(-26.0, F, 3.4), 2.0, 12], [Vector3(-34.0, F, -3.0), 1.5, 8], [Vector3(-21.0, F, 9.0), 1.6, 9]]
	for cl in clusters:
		for i in int(cl[2]):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * float(cl[1])
			var p: Vector3 = cl[0] + Vector3(cos(a) * r, 0, sin(a) * r)
			if GL.ground_height_at(p.x, p.z) > GL.HALL + 0.01:
				continue
			xf.append(Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)), p))
			cols.append(BALL_COLS[rng.randi() % BALL_COLS.size()])
	# a trail of single balls going up the steps and into the vestibule
	for p in [Vector3(-22.8, F, 2.3), Vector3(-21.95, -0.875 + 0.037, 2.0), Vector3(-20.0, 0.037, 2.6), Vector3(-16.2, 0.037, 2.4), Vector3(-13.0, 0.037, 1.4)]:
		xf.append(Transform3D(Basis.IDENTITY, p))
		cols.append(BALL_COLS[0])
	var mmi := _ball_multimesh(c, xf, cols, "ScatterBalls")
	mmi.visibility_range_end = 40.0

# ====================================================================== toddler corner

static func _toddler(c) -> void:
	var T: Dictionary = GL.TODDLER
	var k = c.kit("props_h")
	var cl = c.col("props_h")
	var F := GL.HALL
	var x0: float = T.x0
	var x1: float = T.x1
	var z0: float = T.z0
	var z1: float = T.z1
	# low foam fence (opening on its east side) + its sign
	var fence := [[Vector3(x0, F, z0), Vector3(x1, F + 0.5, z0 + 0.1)], [Vector3(x0, F, z1 - 0.1), Vector3(x1, F + 0.5, z1)],
		[Vector3(x1 - 0.1, F, z0), Vector3(x1, F + 0.5, 6.2)], [Vector3(x1 - 0.1, F, 7.4), Vector3(x1, F + 0.5, z1)]]
	for f in fence:
		k.box("vinyl", f[0], f[1], Color(0.95, 0.55, 0.62))
		cl.box(f[0], f[1])
	Shell.sign_quad(k, "tex_labels.jpg", Vector3(x0 + 0.006, F + 1.35, 7.0), Vector3.RIGHT, 0.6, 0.45, Rect2(2.0 / 3.0, 0.0, 1.0 / 3.0, 0.5))
	# soft blocks: cubes, cylinders, wedges, an arch, a tiny foam slide
	var blocks := [
		["cube", Vector3(-37.6, F, 5.0), 0.4, Color(0.95, 0.75, 0.15), 0.3], ["cube", Vector3(-37.2, F + 0.4, 5.1), 0.3, Color(0.2, 0.55, 0.85), 0.8],
		["cube", Vector3(-36.4, F, 8.9), 0.35, Color(0.85, 0.25, 0.2), 0.1], ["cyl", Vector3(-38.0, F, 9.3), 0.25, Color(0.3, 0.7, 0.35), 0.0],
		["cyl", Vector3(-36.9, F, 6.3), 0.2, Color(0.6, 0.3, 0.7), 0.0], ["wedge", Vector3(-37.4, F, 7.7), 0.6, Color(0.2, 0.55, 0.85), 0.0],
		["cube", Vector3(-36.2, F, 4.4), 0.3, Color(0.3, 0.7, 0.35), 0.5], ["arch", Vector3(-38.0, F, 6.6), 0.9, Color(0.95, 0.75, 0.15), 0.0],
	]
	for b in blocks:
		var p: Vector3 = b[1]
		var s: float = b[2]
		var col: Color = b[3]
		var yaw: float = b[4]
		match String(b[0]):
			"cube":
				k.box("vinyl_flat", Vector3(-s, 0, -s) * 0.5, Vector3(s, 2.0 * s, s) * 0.5, col, 1.0, Kit.ALL, Transform3D(Basis(Vector3.UP, yaw), p))
				cl.box(p - Vector3(s, 0, s) * 0.5, p + Vector3(s * 0.5, s, s * 0.5))
			"cyl":
				k.tube("vinyl_flat", PackedVector3Array([p, p + Vector3(0, s * 1.6, 0)]), s * 0.5, 16, col, 1.0, true)
				cl.box(p - Vector3(s, 0, s) * 0.5, p + Vector3(s * 0.5, s * 1.6, s * 0.5))
			"wedge":
				var w := s
				var hw := w * 0.5
				var q := [p + Vector3(-hw, 0, -0.3), p + Vector3(hw, 0.35, -0.3), p + Vector3(hw, 0.35, 0.3), p + Vector3(-hw, 0, 0.3)]
				k.quad("vinyl_flat", q[0], q[1], q[2], q[3], Vector3(-0.35, w, 0).normalized(), Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
				k.quad("vinyl_flat", p + Vector3(hw, 0, -0.3), p + Vector3(hw, 0.35, -0.3), p + Vector3(hw, 0.35, 0.3), p + Vector3(hw, 0, 0.3), Vector3.RIGHT,
					Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), col)
				for zz in [-0.3, 0.3]:
					k.tri("vinyl_flat", p + Vector3(-hw, 0, zz), p + Vector3(hw, 0, zz), p + Vector3(hw, 0.35, zz), Vector3(0, 0, signf(zz)), Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), col)
				cl.convex(PackedVector3Array([p + Vector3(-hw, 0, -0.3), p + Vector3(hw, 0, -0.3), p + Vector3(hw, 0.35, -0.3),
					p + Vector3(-hw, 0, 0.3), p + Vector3(hw, 0, 0.3), p + Vector3(hw, 0.35, 0.3)]))
			"arch":
				var pts := PackedVector3Array()
				for i in 17:
					var a := PI * float(i) / 16.0
					pts.append(p + Vector3(0, sin(a) * 0.45, cos(a) * 0.45))
				k.tube("vinyl_flat", pts, 0.12, 14, col, 1.0, true)
				cl.box(p + Vector3(-0.12, 0, -0.58), p + Vector3(0.12, 0.58, 0.58))

# ====================================================================== party tables

static func _party(c) -> void:
	var k = c.kit("props_h")
	var cl = c.col("props_h")
	var F := GL.HALL
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var chair_cols := [Color(0.85, 0.2, 0.15), Color(0.15, 0.4, 0.8), Color(0.95, 0.75, 0.12), Color(0.2, 0.6, 0.3)]
	for ti in 2:
		var cz := 7.2 + ti * 1.9
		var cx := -21.0
		var hh := 0.55
		# table top with a plastic tablecloth hanging over the edge, folding legs
		k.box("steel", Vector3(cx - 1.2, F + hh - 0.035, cz - 0.38), Vector3(cx + 1.2, F + hh, cz + 0.38), Color(0.9, 0.9, 0.88))
		k.box("vinyl_flat", Vector3(cx - 1.24, F + hh - 0.16, cz - 0.42), Vector3(cx + 1.24, F + hh + 0.004, cz + 0.42), [Color(0.95, 0.45, 0.55), Color(0.4, 0.75, 0.95)][ti], 1.0, Kit.ALL & ~Kit.FACE_NY)
		for lx in [-1.05, 1.05]:
			for lz in [-0.3, 0.3]:
				k.box("metal", Vector3(cx + lx - 0.015, F, cz + lz - 0.015), Vector3(cx + lx + 0.015, F + hh - 0.03, cz + lz + 0.015), Color(0.5, 0.5, 0.5))
		c.col_see("props_h").box(Vector3(cx - 1.24, F, cz - 0.42), Vector3(cx + 1.24, F + hh, cz + 0.42))
		# kid chairs (some knocked over)
		for ci in 6:
			var side := -1.0 if ci < 3 else 1.0
			var px := cx - 0.8 + float(ci % 3) * 0.8 + rng.randf_range(-0.1, 0.1)
			var pz := cz + side * 0.62
			var fallen := rng.randf() < 0.25
			var bas := Basis(Vector3.UP, (0.0 if side > 0 else PI) + rng.randf_range(-0.3, 0.3))
			var org := Vector3(px, F, pz)
			if fallen:
				bas = bas * Basis(Vector3.RIGHT, -1.45)
				org.y += 0.2
			_kid_chair(k, Transform3D(bas, org), chair_cols[rng.randi() % 4])
			c.col_see("props_h").box(Vector3(px - 0.18, F, pz - 0.18), Vector3(px + 0.18, F + 0.55, pz + 0.18))
		# paper plates, cups, party hats, a cake box
		for pi in 8:
			var px := cx - 1.0 + rng.randf() * 2.0
			var pz := cz + rng.randf_range(-0.28, 0.28)
			var y := F + hh + 0.006
			if rng.randf() < 0.55:
				k.tube("fabric", PackedVector3Array([Vector3(px, y, pz), Vector3(px, y + 0.012, pz)]), 0.1, 18, Color(0.97, 0.96, 0.92), 1.0, true)
				k.tube("fabric", PackedVector3Array([Vector3(px, y + 0.012, pz), Vector3(px, y + 0.016, pz)]), 0.1, 18, [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9)][pi % 2], 1.0, false)
			else:
				var fallen_cup := rng.randf() < 0.4
				var a := Vector3(px, y, pz)
				var b := a + (Vector3(0.09, 0.03, 0.02) if fallen_cup else Vector3(0, 0.1, 0))
				k.tube("fabric", PackedVector3Array([a, b]), 0.035, 12, [Color(0.95, 0.85, 0.2), Color(0.85, 0.3, 0.5), Color(0.35, 0.7, 0.4)][pi % 3], 1.0, true,
					func(i: int, _a: float) -> float: return 0.8 + 0.2 * float(i))
		var hat := Vector3(cx + 0.5, F + hh + 0.005, cz + 0.1)
		var cone := PackedVector3Array()
		for i in 7:
			cone.append(hat + Vector3(0, 0.16 * float(i) / 6.0, 0))
		k.tube("fabric", cone, 0.06, 14, Color(0.6, 0.3, 0.8), 1.0, false, func(i: int, _a: float) -> float: return maxf(0.02, 1.0 - float(i) / 6.0))
		if ti == 0:
			k.box("wood", Vector3(cx - 0.2, F + hh, cz - 0.15), Vector3(cx + 0.15, F + hh + 0.12, cz + 0.17), Color(0.92, 0.88, 0.8))
	# a lone balloon string on the floor? (no balloons: keep the room original) -> a forgotten teddy-ish plush made of spheres
	var plush := Vector3(-19.2, F + 0.13, 9.9)
	k.sphere("fabric", plush, 0.13, 12, 8, Color(0.55, 0.38, 0.25), Vector3(1.0, 1.1, 0.9))
	k.sphere("fabric", plush + Vector3(0, 0.2, 0.02), 0.09, 12, 8, Color(0.55, 0.38, 0.25))
	for ex in [-0.06, 0.06]:
		k.sphere("fabric", plush + Vector3(ex, 0.28, 0.0), 0.035, 8, 6, Color(0.5, 0.34, 0.22))
		k.sphere("rubber", plush + Vector3(ex * 0.6, 0.22, 0.085), 0.012, 6, 4, Color(0.05, 0.05, 0.05))

static func _kid_chair(k, xf: Transform3D, col: Color) -> void:
	k.box("plastic", Vector3(-0.15, 0.28, -0.15), Vector3(0.15, 0.31, 0.15), col, 1.0, Kit.ALL, xf)
	k.box("plastic", Vector3(-0.15, 0.31, 0.12), Vector3(0.15, 0.58, 0.15), col, 1.0, Kit.ALL, xf)
	for lx in [-0.12, 0.12]:
		for lz in [-0.12, 0.12]:
			k.box("plastic", Vector3(lx - 0.015, 0.0, lz - 0.015), Vector3(lx + 0.015, 0.28, lz + 0.015), col * 0.9, 1.0, Kit.ALL, xf)
