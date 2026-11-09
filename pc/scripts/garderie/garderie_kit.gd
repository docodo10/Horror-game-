## Geometry kit of the garderie: per-material bins of triangles (packed arrays) committed to ArrayMesh surfaces
## (MikkTSpace tangents), plus a collider helper. Godot front faces are CLOCKWISE seen from the front: every emitter
## here orients its triangles from the normal it is given, so callers never think about winding.
##
##   var k := Kit.new()
##   k.box("wall", Vector3(-1, 0, -1), Vector3(1, 2, 1), Color.WHITE, 0.5)     # world-planar UVs (0.5 per metre)
##   k.tube("vinyl", pts, 0.07, 12, color)                                       # tube along a polyline
##   k.grid("plastic", positions, rows, cols, uvs, color)                        # any parametric surface
##   k.commit(parent, materials, "corridor")                                     # one MeshInstance3D per material
extends RefCounted

const FACE_PX := 1
const FACE_NX := 2
const FACE_PY := 4
const FACE_NY := 8
const FACE_PZ := 16
const FACE_NZ := 32
const ALL := 63

class Bin:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

var bins := {}             # material id -> Bin
var tri_count := 0
## > 0: every closed box() of this kit becomes a smooth-shaded chamfered box with this radius (furniture, trims:
## the 5-10 mm micro-bevels that catch a highlight on every edge).
var chamfer := 0.0

func bin(id: String) -> Bin:
	var b: Bin = bins.get(id)
	if b == null:
		b = Bin.new()
		bins[id] = b
	return b

func is_empty() -> bool:
	for b in bins.values():
		if (b as Bin).idx.size() > 0:
			return false
	return true

# ---------------------------------------------------------------- primitives

## Quad a-b-c-d (in order around it) facing `nrm`, with explicit UVs.
func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col := Color.WHITE) -> void:
	var bn := bin(mat)
	var i := bn.v.size()
	bn.v.append(a); bn.v.append(b); bn.v.append(c); bn.v.append(d)
	bn.n.append(nrm); bn.n.append(nrm); bn.n.append(nrm); bn.n.append(nrm)
	bn.uv.append(ua); bn.uv.append(ub); bn.uv.append(uc); bn.uv.append(ud)
	bn.c.append(col); bn.c.append(col); bn.c.append(col); bn.c.append(col)
	if (b - a).cross(c - a).dot(nrm) > 0.0:   # counter-clockwise from the front: flip
		bn.idx.append(i); bn.idx.append(i + 2); bn.idx.append(i + 1)
		bn.idx.append(i); bn.idx.append(i + 3); bn.idx.append(i + 2)
	else:
		bn.idx.append(i); bn.idx.append(i + 1); bn.idx.append(i + 2)
		bn.idx.append(i); bn.idx.append(i + 2); bn.idx.append(i + 3)
	tri_count += 2

## Planar quad with UVs projected on (u_axis, v_axis) in metres x uvs (+ offset).
func pquad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, u_axis: Vector3, v_axis: Vector3, uvs := 1.0, col := Color.WHITE, uv_off := Vector2.ZERO) -> void:
	quad(mat, a, b, c, d, nrm,
		Vector2(a.dot(u_axis), a.dot(v_axis)) * uvs + uv_off, Vector2(b.dot(u_axis), b.dot(v_axis)) * uvs + uv_off,
		Vector2(c.dot(u_axis), c.dot(v_axis)) * uvs + uv_off, Vector2(d.dot(u_axis), d.dot(v_axis)) * uvs + uv_off, col)

func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col := Color.WHITE) -> void:
	var bn := bin(mat)
	var i := bn.v.size()
	bn.v.append(a); bn.v.append(b); bn.v.append(c)
	bn.n.append(nrm); bn.n.append(nrm); bn.n.append(nrm)
	bn.uv.append(ua); bn.uv.append(ub); bn.uv.append(uc)
	bn.c.append(col); bn.c.append(col); bn.c.append(col)
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		bn.idx.append(i); bn.idx.append(i + 2); bn.idx.append(i + 1)
	else:
		bn.idx.append(i); bn.idx.append(i + 1); bn.idx.append(i + 2)
	tri_count += 1

## Box mn..mx in the local frame `xf` (rotation + translation only). World-planar UVs from the local coordinates
## (walls: u horizontal, v downward), so adjacent boxes tile seamlessly. `faces` = bit mask of FACE_*.
func box(mat: String, mn: Vector3, mx: Vector3, col := Color.WHITE, uvs := 1.0, faces := ALL, xf := Transform3D.IDENTITY, uv_off := Vector2.ZERO) -> void:
	if chamfer > 0.0 and faces == ALL and uv_off == Vector2.ZERO:
		var lo := mn.min(mx)
		var hi := mn.max(mx)
		rbox(mat, lo, hi, chamfer, 1, col, uvs, xf, faces)
		return
	var B := xf.basis
	var o := xf.origin
	var p000 := xf * Vector3(mn.x, mn.y, mn.z)
	var p100 := xf * Vector3(mx.x, mn.y, mn.z)
	var p010 := xf * Vector3(mn.x, mx.y, mn.z)
	var p110 := xf * Vector3(mx.x, mx.y, mn.z)
	var p001 := xf * Vector3(mn.x, mn.y, mx.z)
	var p101 := xf * Vector3(mx.x, mn.y, mx.z)
	var p011 := xf * Vector3(mn.x, mx.y, mx.z)
	var p111 := xf * Vector3(mx.x, mx.y, mx.z)
	if faces & FACE_PX:
		quad(mat, p101, p100, p110, p111, B.x,
			Vector2(-mx.z, -mn.y) * uvs + uv_off, Vector2(-mn.z, -mn.y) * uvs + uv_off, Vector2(-mn.z, -mx.y) * uvs + uv_off, Vector2(-mx.z, -mx.y) * uvs + uv_off, col)
	if faces & FACE_NX:
		quad(mat, p000, p001, p011, p010, -B.x,
			Vector2(mn.z, -mn.y) * uvs + uv_off, Vector2(mx.z, -mn.y) * uvs + uv_off, Vector2(mx.z, -mx.y) * uvs + uv_off, Vector2(mn.z, -mx.y) * uvs + uv_off, col)
	if faces & FACE_PY:
		quad(mat, p010, p110, p111, p011, B.y,
			Vector2(mn.x, mn.z) * uvs + uv_off, Vector2(mx.x, mn.z) * uvs + uv_off, Vector2(mx.x, mx.z) * uvs + uv_off, Vector2(mn.x, mx.z) * uvs + uv_off, col)
	if faces & FACE_NY:
		quad(mat, p000, p100, p101, p001, -B.y,
			Vector2(mn.x, -mn.z) * uvs + uv_off, Vector2(mx.x, -mn.z) * uvs + uv_off, Vector2(mx.x, -mx.z) * uvs + uv_off, Vector2(mn.x, -mx.z) * uvs + uv_off, col)
	if faces & FACE_PZ:
		quad(mat, p001, p101, p111, p011, B.z,
			Vector2(mn.x, -mn.y) * uvs + uv_off, Vector2(mx.x, -mn.y) * uvs + uv_off, Vector2(mx.x, -mx.y) * uvs + uv_off, Vector2(mn.x, -mx.y) * uvs + uv_off, col)
	if faces & FACE_NZ:
		quad(mat, p100, p000, p010, p110, -B.z,
			Vector2(-mx.x, -mn.y) * uvs + uv_off, Vector2(-mn.x, -mn.y) * uvs + uv_off, Vector2(-mn.x, -mx.y) * uvs + uv_off, Vector2(-mx.x, -mx.y) * uvs + uv_off, col)
	o = o  # (xf origin already applied)

## Box given by centre + size (+ yaw around Y).
func cbox(mat: String, center: Vector3, size: Vector3, col := Color.WHITE, uvs := 1.0, yaw := 0.0, faces := ALL) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), center)
	box(mat, -size * 0.5, size * 0.5, col, uvs, faces, xf)

## Rounded box mn..mx in the frame `xf` ("Nanite" bevels): every edge rounded with radius r, `segs` steps per 45° of
## arc (1 = a smooth-shaded chamfer for trims / furniture, 2-3 = foam blocks and pads). Exact smooth normals
## (inner box + r * direction), world-planar UVs like box() (computed on the unrounded box, so neighbours line up).
## `faces` skips whole faces (their rounded edges stop at the 45° seam shared with the neighbour face).
func rbox(mat: String, mn: Vector3, mx: Vector3, r: float, segs := 2, col := Color.WHITE, uvs := 1.0, xf := Transform3D.IDENTITY, faces := ALL) -> void:
	var h := (mx - mn) * 0.5
	var c := (mx + mn) * 0.5
	r = clampf(r, 0.0, minf(h.x, minf(h.y, h.z)) * 0.98)
	if r < 1e-4:
		box(mat, mn, mx, col, uvs, faces, xf)
		return
	var hi := h - Vector3(r, r, r)
	var B := xf.basis
	var bn := bin(mat)
	# per face: [axis, sign, u axis, v axis, face bit]
	for f in [[0, 1.0, 2, 1, FACE_PX], [0, -1.0, 2, 1, FACE_NX], [1, 1.0, 0, 2, FACE_PY], [1, -1.0, 0, 2, FACE_NY], [2, 1.0, 0, 1, FACE_PZ], [2, -1.0, 0, 1, FACE_NZ]]:
		if not (faces & int(f[4])):
			continue
		var ax: int = f[0]
		var sg: float = f[1]
		var ua: int = f[2]
		var va: int = f[3]
		var su := _rb_samples(h[ua], hi[ua], r, segs)
		var sv := _rb_samples(h[va], hi[va], r, segs)
		var nu := su.size()
		var nv := sv.size()
		var base := bn.v.size()
		for j in nv:
			for i in nu:
				var q := Vector3.ZERO
				q[ax] = sg * h[ax]
				q[ua] = su[i]
				q[va] = sv[j]
				var inner := q.clamp(-hi, hi)
				var d := q - inner
				var n := d.normalized() if d.length_squared() > 1e-12 else Vector3.ZERO
				if n == Vector3.ZERO:
					n[ax] = sg
				var p := c + inner + n * r
				bn.v.append(xf * p)
				bn.n.append((B * n).normalized())
				var lq := c + q
				var uv: Vector2
				match ax:
					0: uv = Vector2(-lq.z * sg, -lq.y)
					1: uv = Vector2(lq.x, lq.z * sg)
					_: uv = Vector2(lq.x * sg, -lq.y)
				bn.uv.append(uv * uvs)
				bn.c.append(col)
		# winding from the first non-degenerate quad vs its normal
		var flip := false
		var fn := Vector3.ZERO
		fn[ax] = sg
		var a := bn.v[base + (nv / 2) * nu + nu / 2]
		var b := bn.v[base + (nv / 2) * nu + nu / 2 + 1]
		var cc := bn.v[base + (nv / 2 + 1) * nu + nu / 2]
		if (b - a).cross(cc - a).dot(B * fn) > 0.0:
			flip = true
		for j in nv - 1:
			for i in nu - 1:
				var i0 := base + j * nu + i
				var i1 := i0 + 1
				var i2 := i0 + nu
				var i3 := i2 + 1
				if flip:
					bn.idx.append(i0); bn.idx.append(i2); bn.idx.append(i1)
					bn.idx.append(i1); bn.idx.append(i2); bn.idx.append(i3)
				else:
					bn.idx.append(i0); bn.idx.append(i1); bn.idx.append(i2)
					bn.idx.append(i1); bn.idx.append(i3); bn.idx.append(i2)
		tri_count += (nu - 1) * (nv - 1) * 2

## Sample positions across one face axis of a rounded box: the arc (tan-spaced so the angles are even) on each side
## of the flat part.
static func _rb_samples(h: float, hi: float, r: float, segs: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(segs, -1, -1):
		out.append(-(hi + r * tan(PI * 0.25 * float(k) / float(segs))))
	for k in range(0, segs + 1):
		out.append(hi + r * tan(PI * 0.25 * float(k) / float(segs)))
	return out

## Seam piping of a soft block (rbox with radius r): a thin cord (radius pr) along the 12 rounded edges, at the 45°
## line of each edge, between the inner corners (+ a little overlap).
func piping(mat: String, mn: Vector3, mx: Vector3, r: float, pr: float, col := Color.WHITE, xf := Transform3D.IDENTITY, sides := 6) -> void:
	var h := (mx - mn) * 0.5
	var c := (mx + mn) * 0.5
	r = clampf(r, 0.0, minf(h.x, minf(h.y, h.z)) * 0.98)
	var hi := h - Vector3(r, r, r)
	var k := r * 0.7071 + pr * 0.35
	for ax in 3:
		var o1 := (ax + 1) % 3
		var o2 := (ax + 2) % 3
		for s1: float in [-1.0, 1.0]:
			for s2: float in [-1.0, 1.0]:
				var p := c
				p[o1] += s1 * (hi[o1] + k)
				p[o2] += s2 * (hi[o2] + k)
				var a := p
				var b := p
				a[ax] -= hi[ax] + r * 0.35
				b[ax] += hi[ax] + r * 0.35
				var up := Vector3.ZERO
				up[o1] = 1.0
				tube(mat, PackedVector3Array([xf * a, xf * b]), pr, sides, col, 1.0, false, Callable(), xf.basis * up)

## Fold displacement of a padded vinyl wrap (metres, signed): two bands of irregular spiral folds (≈11 cm wavelength,
## ±12 mm and ≈5 cm, ±6 mm — the measured Subliminal folds), sharpened into creases (vinyl buckles into ridges with
## soft rounded bulges). ang = angle around the wrap, s = metres along it, k scales the amplitude (thin posts / rails),
## ph = per-wrap phase. Integer frequencies around keep the wrap seamless.
## small: weight of the 5 cm band (0 on thin posts / rails whose rings are too far apart to carry it: it would alias
## into per-vertex normal noise).
static func fold(ang: float, s: float, k: float, ph: float, small_k := 1.0) -> float:
	# near-horizontal compression rings (m = 1) + spiral folds (m = 3..5), their amplitude wandering along / around the
	# wrap (λ ≈ 48 cm) so the pattern never reads as a regular screw thread
	var big := 0.38 * sin(ang + s * 52.0 + ph * 2.1) + 0.36 * sin(3.0 * ang + s * 57.1 + ph) + 0.22 * sin(-4.0 * ang + s * 66.0 + ph * 1.7) \
		+ 0.18 * sin(5.0 * ang + s * 47.6 - ph * 0.6)
	big *= 0.5 + 0.5 * absf(sin(2.0 * ang + s * 13.1 + ph * 3.0) + 0.6 * sin(s * 7.3 - ang + ph))
	big = big - 0.4 * absf(big)             # creases: sharper valleys, rounded bulges
	if small_k <= 0.0:
		return 0.012 * big * k
	var small := 0.5 * sin(9.0 * ang + s * 125.7 + ph * 2.3) + 0.35 * sin(-11.0 * ang + s * 114.2 - ph * 1.1) + 0.25 * sin(7.0 * ang - s * 139.6 + ph * 0.4)
	return (0.012 * big + 0.006 * small * small_k) * k

## Wall slab between two xz points (thickness t, from y0 to y1), with rectangular openings
## [[s0, s1, y0, y1], ...] given as distances along the wall from `a`. UVs continue across the pieces.
func wall(mat: String, a: Vector2, b: Vector2, t: float, y0: float, y1: float, openings: Array = [], col := Color.WHITE, uvs := 1.0, faces := ALL) -> void:
	var d := b - a
	var L := d.length()
	if L < 1e-4:
		return
	var yaw := atan2(-d.y, d.x)          # local +x along a->b
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(a.x, 0.0, a.y))
	# offset UVs by the wall's start so its texture lines up with neighbours along the same axis
	var uo := Vector2(a.x if absf(d.x) >= absf(d.y) else a.y, 0.0) * uvs
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	var s := 0.0
	for o in cuts:
		var s0 := clampf(float(o[0]), 0.0, L)
		var s1 := clampf(float(o[1]), 0.0, L)
		if s0 > s + 1e-4:
			box(mat, Vector3(s, y0, -t * 0.5), Vector3(s0, y1, t * 0.5), col, uvs, faces, xf, uo)
		if float(o[2]) > y0 + 1e-4:
			box(mat, Vector3(s0, y0, -t * 0.5), Vector3(s1, float(o[2]), t * 0.5), col, uvs, faces, xf, uo)
		if float(o[3]) < y1 - 1e-4:
			box(mat, Vector3(s0, float(o[3]), -t * 0.5), Vector3(s1, y1, t * 0.5), col, uvs, faces, xf, uo)
		s = maxf(s, s1)
	if s < L - 1e-4:
		box(mat, Vector3(s, y0, -t * 0.5), Vector3(L, y1, t * 0.5), col, uvs, faces, xf, uo)

# ---------------------------------------------------------------- parametric surfaces

## Emits a rows x cols grid of positions P (row-major) as triangles. Normals by finite differences; `wrap` = the last
## column repeats the first (closed tube). `outward` (optional) picks the side the normals face: a point the normals
## must point away from (e.g. the tube axis), else `flip` flips them. UV array same size as P.
func grid(mat: String, P: PackedVector3Array, rows: int, cols: int, U: PackedVector2Array, col := Color.WHITE, wrap := false, flip := false, colors := PackedColorArray()) -> void:
	if rows < 2 or cols < 2:
		return
	var bn := bin(mat)
	var base := bn.v.size()
	var N := PackedVector3Array()
	N.resize(rows * cols)
	for r in rows:
		var r0 := maxi(r - 1, 0)
		var r1 := mini(r + 1, rows - 1)
		for c in cols:
			var c0 := c - 1
			var c1 := c + 1
			if wrap:
				if c0 < 0: c0 = cols - 2
				if c1 > cols - 1: c1 = 1
			else:
				c0 = maxi(c0, 0)
				c1 = mini(c1, cols - 1)
			var du := P[r * cols + c1] - P[r * cols + c0]
			var dv := P[r1 * cols + c] - P[r0 * cols + c]
			var nn := dv.cross(du)
			if nn.length_squared() < 1e-14:
				nn = Vector3.UP
			nn = nn.normalized()
			N[r * cols + c] = -nn if flip else nn
	bn.v.append_array(P)
	bn.n.append_array(N)
	bn.uv.append_array(U)
	if colors.size() == P.size():
		bn.c.append_array(colors)
	else:
		var cc := PackedColorArray()
		cc.resize(P.size())
		cc.fill(col)
		bn.c.append_array(cc)
	# winding from one representative quad, consistent across the grid
	var rm := rows / 2
	var cm := cols / 2
	if cm >= cols - 1: cm = cols - 2
	if rm >= rows - 1: rm = rows - 2
	var a := P[rm * cols + cm]
	var b := P[rm * cols + cm + 1]
	var c2 := P[(rm + 1) * cols + cm]
	var ccw := (b - a).cross(c2 - a).dot(N[rm * cols + cm]) > 0.0
	for r in rows - 1:
		for c in cols - 1:
			var i0 := base + r * cols + c
			var i1 := i0 + 1
			var i2 := i0 + cols
			var i3 := i2 + 1
			if ccw:
				bn.idx.append(i0); bn.idx.append(i2); bn.idx.append(i1)
				bn.idx.append(i1); bn.idx.append(i2); bn.idx.append(i3)
			else:
				bn.idx.append(i0); bn.idx.append(i1); bn.idx.append(i2)
				bn.idx.append(i1); bn.idx.append(i3); bn.idx.append(i2)
	tri_count += (rows - 1) * (cols - 1) * 2

## Rotation-minimising frames along a polyline: Array of Basis (x = normal, y = binormal, z = tangent).
static func frames(pts: PackedVector3Array, up_hint := Vector3.UP) -> Array[Basis]:
	var out: Array[Basis] = []
	var n := pts.size()
	if n < 2:
		return out
	var t0 := (pts[1] - pts[0]).normalized()
	var ref := up_hint if absf(t0.dot(up_hint)) < 0.95 else Vector3.RIGHT
	var nrm := (ref - t0 * ref.dot(t0)).normalized()
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[n - 1] - pts[n - 2]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		nrm = (nrm - t * nrm.dot(t))
		if nrm.length_squared() < 1e-10:
			nrm = (ref - t * ref.dot(t))
		nrm = nrm.normalized()
		out.append(Basis(nrm, t.cross(nrm), t))
	return out

## Tube along a polyline. rfn(ring: int, ang: float) -> radius multiplier (bulges / wrinkles), optional.
## caps: closes both ends with flat discs. UV: u around (metres x uvs), v along (metres x uvs).
func tube(mat: String, pts: PackedVector3Array, r: float, sides: int, col := Color.WHITE, uvs := 1.0, caps := false, rfn := Callable(), up_hint := Vector3.UP) -> void:
	var F := frames(pts, up_hint)
	var rows := pts.size()
	if rows < 2:
		return
	var cols := sides + 1
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	P.resize(rows * cols)
	U.resize(rows * cols)
	var along := 0.0
	var circ := TAU * r
	for i in rows:
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		var f: Basis = F[i]
		for j in cols:
			var ang := TAU * float(j % sides) / float(sides)
			var rr := r
			if rfn.is_valid():
				rr = r * float(rfn.call(i, ang))
			P[i * cols + j] = pts[i] + (f.x * cos(ang) + f.y * sin(ang)) * rr
			U[i * cols + j] = Vector2(circ * float(j) / float(sides), along) * uvs
	# finite-difference normals: rows along the tube, columns around -> du x dv faces outward when not flipped
	grid(mat, P, rows, cols, U, col, true, _tube_flip(P, rows, cols, pts))
	if caps:
		disc(mat, pts[0], -F[0].z, F[0].x, r if not rfn.is_valid() else r * float(rfn.call(0, 0.0)), sides, col, uvs)
		disc(mat, pts[rows - 1], F[rows - 1].z, F[rows - 1].x, r if not rfn.is_valid() else r * float(rfn.call(rows - 1, 0.0)), sides, col, uvs)

## Decides the flip flag of a tube grid so its normals point away from the axis.
func _tube_flip(P: PackedVector3Array, rows: int, cols: int, axis: PackedVector3Array) -> bool:
	var r := rows / 2
	var c := 0
	var a := P[r * cols + c]
	var du := P[r * cols + c + 1] - P[r * cols + cols - 2]
	var dv := P[mini(r + 1, rows - 1) * cols + c] - P[maxi(r - 1, 0) * cols + c]
	var nn := dv.cross(du)
	return nn.dot(a - axis[r]) < 0.0

## Flat disc (triangle fan as thin quads) centred at c, facing nrm.
func disc(mat: String, c: Vector3, nrm: Vector3, ref: Vector3, r: float, sides: int, col := Color.WHITE, uvs := 1.0) -> void:
	var x := (ref - nrm * ref.dot(nrm)).normalized()
	var y := nrm.cross(x)
	for j in sides:
		var a0 := TAU * float(j) / float(sides)
		var a1 := TAU * float(j + 1) / float(sides)
		var p0 := c + (x * cos(a0) + y * sin(a0)) * r
		var p1 := c + (x * cos(a1) + y * sin(a1)) * r
		tri(mat, c, p0, p1, nrm, Vector2(0.5, 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5) * uvs, Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5) * uvs, col)

## Profile swept along a path. frames_pos: Array of Transform3D (basis x = right, y = up, z = forward), profile:
## PackedVector2Array (x right, y up). UV: u = profile arc length, v = path length (x uvs).
func sweep(mat: String, path: Array, profile: PackedVector2Array, col := Color.WHITE, uvs := 1.0, flip := false) -> void:
	var rows := path.size()
	var cols := profile.size()
	if rows < 2 or cols < 2:
		return
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	P.resize(rows * cols)
	U.resize(rows * cols)
	var pu := PackedFloat32Array()
	pu.resize(cols)
	var acc := 0.0
	for j in cols:
		if j > 0:
			acc += profile[j].distance_to(profile[j - 1])
		pu[j] = acc
	var along := 0.0
	for i in rows:
		var t: Transform3D = path[i]
		if i > 0:
			along += t.origin.distance_to((path[i - 1] as Transform3D).origin)
		for j in cols:
			P[i * cols + j] = t.origin + t.basis.x * profile[j].x + t.basis.y * profile[j].y
			U[i * cols + j] = Vector2(pu[j], along) * uvs
	grid(mat, P, rows, cols, U, col, false, flip)

## UV sphere (bulbs, knobs, balls).
func sphere(mat: String, c: Vector3, r: float, seg := 12, rings := 8, col := Color.WHITE, scale := Vector3.ONE) -> void:
	var rows := rings + 1
	var cols := seg + 1
	var P := PackedVector3Array()
	var U := PackedVector2Array()
	P.resize(rows * cols)
	U.resize(rows * cols)
	for i in rows:
		var th := PI * float(i) / float(rings)
		for j in cols:
			var ph := TAU * float(j) / float(seg)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			P[i * cols + j] = c + d * r * scale
			U[i * cols + j] = Vector2(float(j) / float(seg), float(i) / float(rings))
	# poles: nudge to avoid zero-length tangents in the normal estimate
	grid(mat, P, rows, cols, U, col, true, false)
	# fix pole normals (degenerate rows) and orientation
	var bn := bin(mat)
	var base := bn.v.size() - rows * cols
	for i in rows:
		for j in cols:
			var k := base + i * cols + j
			bn.n[k] = ((bn.v[k] - c) / scale).normalized()
	# orientation: grid() picked the winding from its own normals; recheck against the outward normals
	_reorient_last(mat, (rows - 1) * (cols - 1) * 2, c)

## Re-winds the last `ntri` triangles of a bin so they face away from `center`.
func _reorient_last(mat: String, ntri: int, center: Vector3) -> void:
	var bn := bin(mat)
	var start := bn.idx.size() - ntri * 3
	for t in ntri:
		var k := start + t * 3
		var a := bn.v[bn.idx[k]]
		var b := bn.v[bn.idx[k + 1]]
		var c := bn.v[bn.idx[k + 2]]
		var cr := (b - a).cross(c - a)
		if cr.length_squared() < 1e-16:
			continue
		if cr.dot((a + b + c) / 3.0 - center) > 0.0:     # CCW seen from outside -> flip to clockwise
			var tmp := bn.idx[k + 1]
			bn.idx[k + 1] = bn.idx[k + 2]
			bn.idx[k + 2] = tmp

# ---------------------------------------------------------------- commit

## Mesh of one bin. lods: automatic LOD chain (meshoptimizer through ImporterMesh, also used by the shadow passes):
## the dense fold-displaced vinyl wraps drop to a fraction of their triangles a few metres away.
static func build_mesh(b: Bin, tangents := true, lods := false) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = b.v
	arr[Mesh.ARRAY_NORMAL] = b.n
	arr[Mesh.ARRAY_TEX_UV] = b.uv
	arr[Mesh.ARRAY_COLOR] = b.c
	arr[Mesh.ARRAY_INDEX] = b.idx
	var m: ArrayMesh
	if tangents:
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_tangents()
		m = st.commit()
	else:
		m = ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if lods and b.idx.size() >= 3 * 600:
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
		im.generate_lods(25.0, 60.0, [])
		m = im.get_mesh()
	return m

## Splits a bin into spatial chunks (triangle centroids on an xz grid of `cell` metres): smaller meshes cull and pick
## their LOD independently. Returns Array[Bin] (the bin itself when it fits in one cell).
static func split_bin(b: Bin, cell: float) -> Array:
	var tri_n := b.idx.size() / 3
	var keys := {}
	var tri_key := PackedInt32Array()
	tri_key.resize(tri_n)
	for t in tri_n:
		var c := (b.v[b.idx[t * 3]] + b.v[b.idx[t * 3 + 1]] + b.v[b.idx[t * 3 + 2]]) / 3.0
		var k := Vector2i(int(floor(c.x / cell)), int(floor(c.z / cell)))
		if not keys.has(k):
			keys[k] = keys.size()
		tri_key[t] = int(keys[k])
	if keys.size() <= 1:
		return [b]
	var out: Array = []
	var remap := PackedInt32Array()
	remap.resize(b.v.size())
	for ci in keys.size():
		var nb := Bin.new()
		remap.fill(-1)
		for t in tri_n:
			if tri_key[t] != ci:
				continue
			for e in 3:
				var vi := b.idx[t * 3 + e]
				if remap[vi] < 0:
					remap[vi] = nb.v.size()
					nb.v.append(b.v[vi])
					nb.n.append(b.n[vi])
					nb.uv.append(b.uv[vi])
					nb.c.append(b.c[vi])
				nb.idx.append(remap[vi])
		out.append(nb)
	return out

## One MeshInstance3D per non-empty bin, named "<prefix>_<material>". mats: id -> Material.
## opts: {no_shadow: [ids], shadow_only: [ids], vis_end: float (visibility range end, 0 = off), gi_off: [ids],
##        lods: [ids] (automatic LOD chain), chunk: float (split those LOD'd bins into xz cells of that size, metres)}
func commit(parent: Node3D, mats: Dictionary, prefix: String, opts := {}) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var no_shadow: Array = opts.get("no_shadow", [])
	var shadow_only: Array = opts.get("shadow_only", [])
	var gi_off: Array = opts.get("gi_off", [])
	var lod_ids: Array = opts.get("lods", [])
	var chunk := float(opts.get("chunk", 0.0))
	var vis_end := float(opts.get("vis_end", 0.0))
	var keys := bins.keys()
	keys.sort()
	for id in keys:
		var b: Bin = bins[id]
		if b.idx.is_empty():
			continue
		var lod: bool = id in lod_ids
		var parts: Array = split_bin(b, chunk) if lod and chunk > 0.0 else [b]
		for pi in parts.size():
			var mesh := build_mesh(parts[pi], not (id in opts.get("no_tangents", [])), lod)
			if mats.has(id):
				mesh.surface_set_material(0, mats[id])
			var mi := MeshInstance3D.new()
			mi.name = "%s_%s" % [prefix, id] if parts.size() == 1 else "%s_%s_%d" % [prefix, id, pi]
			mi.mesh = mesh
			if id in no_shadow:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif id in shadow_only:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if id in gi_off:
				mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			if vis_end > 0.0:
				mi.visibility_range_end = vis_end
				mi.visibility_range_end_margin = 2.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mi)
			out.append(mi)
	return out

# ---------------------------------------------------------------- colliders

## Static colliders of one region: boxes, convex hulls (ramps) and trimeshes on a single StaticBody3D.
class Col:
	var body: StaticBody3D

	func _init(parent: Node3D, name: String, layer := 1) -> void:
		body = StaticBody3D.new()
		body.name = name
		body.collision_layer = layer
		body.collision_mask = 0
		parent.add_child(body)

	func box(mn: Vector3, mx: Vector3, xf := Transform3D.IDENTITY, tag := "") -> CollisionShape3D:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = (mx - mn).abs()
		cs.shape = sh
		cs.transform = xf * Transform3D(Basis.IDENTITY, (mn + mx) * 0.5)
		if tag != "":
			cs.set_meta("tag", tag)
		body.add_child(cs)
		return cs

	func cbox(center: Vector3, size: Vector3, yaw := 0.0) -> CollisionShape3D:
		return box(-size * 0.5, size * 0.5, Transform3D(Basis(Vector3.UP, yaw), center))

	func convex(points: PackedVector3Array) -> CollisionShape3D:
		var cs := CollisionShape3D.new()
		var sh := ConvexPolygonShape3D.new()
		sh.points = points
		cs.shape = sh
		body.add_child(cs)
		return cs

	func trimesh(faces: PackedVector3Array) -> CollisionShape3D:
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(faces)
		cs.shape = sh
		body.add_child(cs)
		return cs

	## Stair ramp (wedge) from the bottom nosing line (x_low, y_low) to the top one (x_high, y_high), z0..z1,
	## extended `ext` below the bottom so the foot of the wedge meets the floor.
	func ramp_x(x_low: float, x_high: float, y_low: float, y_high: float, z0: float, z1: float) -> CollisionShape3D:
		var pts := PackedVector3Array([
			Vector3(x_low, y_low, z0), Vector3(x_low, y_low, z1),
			Vector3(x_high, y_high, z0), Vector3(x_high, y_high, z1),
			Vector3(x_high, y_low - 0.05, z0), Vector3(x_high, y_low - 0.05, z1),
			Vector3(x_low, y_low - 0.05, z0), Vector3(x_low, y_low - 0.05, z1),
		])
		return convex(pts)
