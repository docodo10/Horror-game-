## Architecture of the garderie: doorway casing + the old painted door, the basement corridor (pipes, bare bulb),
## the vestibule ("vestiaire": block walls, wainscot, drop ceiling with troffers, padded columns), the hall shell
## (block walls, roof deck, bar-joist trusses, high-bay fluorescent fixtures, padded columns, emergency exit), the
## entrance landing with its railing and six steps down (invisible ramp collider), signs and the mural.
extends RefCounted

const GL := preload("res://scripts/garderie/garderie_layout.gd")
const Kit := preload("res://scripts/garderie/garderie_kit.gd")
const M := preload("res://scripts/garderie/garderie_mats.gd")

const LAYER_WORLD := 1
## Render layers of the area's geometry and the matching light cull masks: lights without shadows pass through walls,
## so the hall's fixtures never touch the vestibule / corridor meshes and vice versa (bit 1 keeps characters lit).
const VIS_FRONT := 1024        # corridor, door, vestibule
const VIS_HALL := 2048         # hall shell, play frame, slides, balls, hall props
const MASK_FRONT := 1 | 1024
const MASK_HALL := 1 | 2048
const CREAM := Color(0.88, 0.85, 0.76)
const YELLOW := Color(0.93, 0.73, 0.12)
const STEEL_DARK := Color(0.13, 0.13, 0.14)
const COPPER := Color(0.78, 0.5, 0.33)

static func build(c) -> void:
	_doorway(c)
	_corridor(c)
	_vestibule(c)
	_hall(c)
	_landing(c)

# ====================================================================== helpers

## Wall with openings + matching colliders (local pieces mirrored from Kit.wall).
static func wall(c, region: String, mat: String, a: Vector2, b: Vector2, t: float, y0: float, y1: float, openings: Array = [], collide := true, col := Color.WHITE, uvs := 1.0) -> void:
	c.kit(region).wall(mat, a, b, t, y0, y1, openings, col, uvs)
	if not collide:
		return
	var d := b - a
	var L := d.length()
	var yaw := atan2(-d.y, d.x)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(a.x, 0.0, a.y))
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	var s := 0.0
	var cl = c.col(region)
	for o in cuts:
		var s0 := clampf(float(o[0]), 0.0, L)
		var s1 := clampf(float(o[1]), 0.0, L)
		if s0 > s + 1e-4:
			cl.box(Vector3(s, y0, -t * 0.5), Vector3(s0, y1, t * 0.5), xf)
		if float(o[2]) > y0 + 1e-4:
			cl.box(Vector3(s0, y0, -t * 0.5), Vector3(s1, float(o[2]), t * 0.5), xf)
		if float(o[3]) < y1 - 1e-4:
			cl.box(Vector3(s0, float(o[3]), -t * 0.5), Vector3(s1, y1, t * 0.5), xf)
		s = maxf(s, s1)
	if s < L - 1e-4:
		cl.box(Vector3(s, y0, -t * 0.5), Vector3(L, y1, t * 0.5), xf)

## Textured quad on a vertical surface facing `nrm` (horizontal), centred at `ctr`; uv rect in texture space (v down).
static func sign_quad(k, mat: String, ctr: Vector3, nrm: Vector3, w: float, h: float, uv := Rect2(0, 0, 1, 1), col := Color.WHITE) -> void:
	var r := (-nrm).cross(Vector3.UP).normalized()
	var u := Vector3.UP
	var bl := ctr - r * w * 0.5 - u * h * 0.5
	var br := ctr + r * w * 0.5 - u * h * 0.5
	var tr := ctr + r * w * 0.5 + u * h * 0.5
	var tl := ctr - r * w * 0.5 + u * h * 0.5
	k.quad(mat, bl, br, tr, tl, nrm, Vector2(uv.position.x, uv.end.y), uv.end, Vector2(uv.end.x, uv.position.y), uv.position, col)

## Thin board behind a sign (so signs have thickness and cast a contact shadow).
static func board(k, mat: String, ctr: Vector3, nrm: Vector3, w: float, h: float, t: float, col := Color.WHITE) -> void:
	var r := (-nrm).cross(Vector3.UP).normalized()
	var yaw := atan2(r.x, r.z) - PI * 0.5
	var xf := Transform3D(Basis(Vector3.UP, yaw), ctr - nrm * t * 0.5)
	k.box(mat, Vector3(-w * 0.5, -h * 0.5, -t * 0.5), Vector3(w * 0.5, h * 0.5, t * 0.5), col, 1.0, Kit.ALL, xf)

## Padded column: banded bulging vinyl segments between yellow "donut" rings (original design), from y0 to y1.
static func padded_column(c, region: String, mat: String, x: float, z: float, y0: float, y1: float, r: float, seed: int) -> void:
	var k = c.kit(region)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ring_h := 0.16
	var cols := [Color(0.18, 0.5, 0.74), Color(0.85, 0.24, 0.17)]
	var top := y1 - ring_h
	var bot := y0 + ring_h
	var nseg := maxi(1, int(round((top - bot) / 0.8)))
	var seg_h := (top - bot) / float(nseg)
	for s in nseg:
		var a := bot + s * seg_h
		var b := a + seg_h
		var pts := PackedVector3Array()
		var rows := 18
		for i in rows + 1:
			pts.append(Vector3(x, a + (b - a) * float(i) / float(rows), z))
		var ph := rng.randf() * TAU
		var rf := func(i: int, ang: float) -> float:
			var t := float(i) / float(rows)
			var bulge := pow(sin(PI * t), 0.45)
			var wob := 0.06 * sin(ang * 3.0 + ph + t * 2.0) + 0.035 * sin(ang * 7.0 - ph * 2.0 + t * 5.0) + 0.02 * sin(ang * 13.0 + t * 9.0 + ph)
			return 0.8 + 0.2 * bulge + wob * bulge
		k.tube(mat, pts, r, 28, cols[s % 2], 1.0, false, rf)
	for yy in [y0, top]:
		var pts := PackedVector3Array()
		for i in 9:
			pts.append(Vector3(x, yy + ring_h * float(i) / 8.0, z))
		var rf2 := func(i: int, _ang: float) -> float:
			var t := float(i) / 8.0
			return 0.9 + 0.22 * pow(sin(PI * t), 0.7)
		k.tube(mat, pts, r * 1.08, 28, YELLOW, 1.0, true, rf2)
	c.col(region).box(Vector3(x - r * 1.1, y0, z - r * 1.1), Vector3(x + r * 1.1, y1, z + r * 1.1))

## High-bay / troffer light: registers a Light3D (+ its emissive material) in ctx.lights.
static func add_light(c, parent: Node3D, pos: Vector3, state: String, kind: String, emit_mat: Material = null) -> Light3D:
	var l: Light3D
	if kind == "bulb":
		var o := OmniLight3D.new()
		o.omni_range = 6.0
		o.omni_attenuation = 1.0
		o.light_energy = 1.6
		o.light_color = Color(1.0, 0.76, 0.48)
		o.shadow_enabled = true
		o.light_size = 0.04
		l = o
	else:
		var s := SpotLight3D.new()
		var hall := kind == "highbay"
		s.spot_range = 12.5 if hall else 6.5
		s.spot_angle = 74.0 if hall else 80.0
		s.spot_angle_attenuation = 1.7 if hall else 0.6
		s.spot_attenuation = 1.15 if hall else 0.85
		s.light_energy = 10.0 if hall else 6.5
		s.light_color = Color(0.93, 0.97, 1.0) if hall else Color(0.96, 0.98, 1.0)
		s.light_size = 0.5 if hall else 0.3
		s.shadow_enabled = state == "shadow"
		s.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		l = s
		if state == "dim":
			s.light_energy *= 0.45
	l.position = pos
	l.shadow_bias = 0.04
	l.shadow_normal_bias = 1.2
	l.shadow_blur = 1.6
	l.light_volumetric_fog_energy = 1.4
	l.distance_fade_enabled = true
	l.distance_fade_begin = 38.0
	l.distance_fade_length = 6.0
	l.distance_fade_shadow = 26.0
	l.name = "%s_%s" % [kind, state]
	l.light_cull_mask = MASK_HALL if kind == "highbay" else MASK_FRONT
	if state == "dead":
		l.visible = false
	parent.add_child(l)
	c.lights.append({"light": l, "state": state, "kind": kind, "emit": emit_mat, "base": l.light_energy, "pos": pos})
	return l

# ====================================================================== doorway + door

static func _doorway(c) -> void:
	var k = c.kit("door")
	var D: Dictionary = GL.DOOR
	var z0: float = D.z0
	var z1: float = D.z1
	var h: float = D.h
	# jamb lining (covers the cut edges of the wall through its whole thickness)
	k.box("paintwood", Vector3(-3.722, 0.0, z0), Vector3(-3.488, h, z0 + 0.022), CREAM)
	k.box("paintwood", Vector3(-3.722, 0.0, z1 - 0.022), Vector3(-3.488, h, z1), CREAM)
	k.box("paintwood", Vector3(-3.722, h - 0.022, z0), Vector3(-3.488, h, z1), CREAM)
	# door stops (the leaf closes against them, room side)
	k.box("paintwood", Vector3(-3.617, 0.0, z0 + 0.022), Vector3(-3.597, h - 0.022, z0 + 0.034), CREAM)
	k.box("paintwood", Vector3(-3.617, h - 0.034, z0 + 0.022), Vector3(-3.597, h - 0.022, z1 - 0.022), CREAM)
	k.box("paintwood", Vector3(-3.617, 0.0, z1 - 0.034), Vector3(-3.597, h - 0.022, z1 - 0.022), CREAM)
	# casings both sides (moulded: flat board + back band) and plinth blocks
	for side in [[-3.5, -3.478, 1.0], [-3.742, -3.72, -1.0]]:
		var xa: float = side[0]
		var xb: float = side[1]
		var lo := minf(xa, xb)
		var hi := maxf(xa, xb)
		k.box("paintwood", Vector3(lo, 0.0, z0 - 0.066), Vector3(hi, h + 0.075, z0 + 0.012), CREAM)
		k.box("paintwood", Vector3(lo, 0.0, z1 - 0.012), Vector3(hi, h + 0.075, z1 + 0.066), CREAM)
		k.box("paintwood", Vector3(lo, h - 0.012, z0 - 0.066), Vector3(hi, h + 0.085, z1 + 0.066), CREAM)
		var bx0 := lo - 0.006 if float(side[2]) < 0.0 else lo
		var bx1 := hi if float(side[2]) < 0.0 else hi + 0.006
		k.box("paintwood", Vector3(bx0, 0.0, z0 - 0.078), Vector3(bx1, h + 0.097, z0 - 0.064), CREAM)
		k.box("paintwood", Vector3(bx0, 0.0, z1 + 0.064), Vector3(bx1, h + 0.097, z1 + 0.078), CREAM)
		k.box("paintwood", Vector3(bx0, h + 0.083, z0 - 0.078), Vector3(bx1, h + 0.097, z1 + 0.078), CREAM)
		for zz in [z0 - 0.07, z1 - 0.012]:
			k.box("paintwood", Vector3(bx0 - 0.004 if float(side[2]) < 0.0 else bx0, 0.0, zz), Vector3(bx1 + 0.004 if float(side[2]) > 0.0 else bx1, 0.17, zz + 0.082), CREAM * 0.92)
	# oak threshold
	k.box("wood", Vector3(-3.73, 0.0, z0 + 0.022), Vector3(-3.47, 0.011, z1 - 0.022), Color(0.72, 0.56, 0.4))
	var cl = c.col("door")
	cl.box(Vector3(-3.76, 0.0, z0 - 0.03), Vector3(-3.47, h, z0 + 0.022))
	cl.box(Vector3(-3.76, 0.0, z1 - 0.022), Vector3(-3.47, h, z1 + 0.03))
	cl.box(Vector3(-3.76, h - 0.022, z0), Vector3(-3.47, h + 0.1, z1))
	# the leaf on its hinge pivot
	var L: Dictionary = GL.LEAF
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(L.hinge_x, 0.0, L.hinge_z)
	c.region("door").add_child(pivot)
	var lk := Kit.new()
	var w: float = L.w
	var lh: float = L.h
	var t: float = L.t
	var y0 := 0.008
	var paint := Color(0.86, 0.83, 0.74)
	# stiles / rails full thickness, panels recessed (4-panel door)
	lk.box("paintwood", Vector3(0.0, y0, -w), Vector3(t, y0 + lh, -w + 0.11), paint)
	lk.box("paintwood", Vector3(0.0, y0, -0.11), Vector3(t, y0 + lh, 0.0), paint)
	for rr in [[y0, y0 + 0.22], [y0 + 0.86, y0 + 1.04], [y0 + lh - 0.12, y0 + lh]]:
		lk.box("paintwood", Vector3(0.0, rr[0], -w + 0.11), Vector3(t, rr[1], -0.11), paint)
	lk.box("paintwood", Vector3(0.0, y0 + 0.22, -w * 0.5 - 0.04), Vector3(t, y0 + lh - 0.12, -w * 0.5 + 0.04), paint)
	for pz in [[-w + 0.11, -w * 0.5 - 0.04], [-w * 0.5 + 0.04, -0.11]]:
		for py in [[y0 + 0.22, y0 + 0.86], [y0 + 1.04, y0 + lh - 0.12]]:
			lk.box("paintwood", Vector3(0.011, py[0], pz[0]), Vector3(t - 0.011, py[1], pz[1]), paint * 0.97)
			# raised fields on both faces
			lk.box("paintwood", Vector3(0.006, py[0] + 0.05, pz[0] + 0.05), Vector3(t - 0.006, py[1] - 0.05, pz[1] - 0.05), paint)
	# brass knobs + rosettes, hinges
	var brass := Color(0.72, 0.56, 0.3)
	for sx: float in [-1.0, 1.0]:
		var fx := t * 0.5 + sx * (t * 0.5 + 0.004)
		lk.box("metal", Vector3(minf(fx, fx + sx * 0.006), y0 + 0.9, -w + 0.04), Vector3(maxf(fx, fx + sx * 0.006), y0 + 1.0, -w + 0.1), brass)
		lk.sphere("metal", Vector3(t * 0.5 + sx * (t * 0.5 + 0.062), y0 + 0.95, -w + 0.07), 0.029, 12, 8, brass)
		var stem := PackedVector3Array([Vector3(t * 0.5 + sx * t * 0.5, y0 + 0.95, -w + 0.07), Vector3(t * 0.5 + sx * (t * 0.5 + 0.045), y0 + 0.95, -w + 0.07)])
		lk.tube("metal", stem, 0.009, 8, brass)
	for hy in [0.25, 1.75]:
		lk.box("metal", Vector3(-0.004, y0 + hy - 0.05, -0.012), Vector3(0.004, y0 + hy + 0.05, 0.012), Color(0.3, 0.27, 0.22))
	var mats := {}
	for id in lk.bins.keys():
		mats[id] = c.mats.mat(id)
	lk.commit(pivot, mats, "leaf")
	var body := AnimatableBody3D.new()
	body.name = "LeafBody"
	body.collision_layer = LAYER_WORLD | 16
	body.collision_mask = 0
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(t, lh, w - 0.01)
	cs.shape = sh
	cs.position = Vector3(t * 0.5, y0 + lh * 0.5, -w * 0.5)
	body.add_child(cs)
	pivot.add_child(body)
	c.door = {"pivot": pivot, "closed": Transform3D(Basis.IDENTITY, pivot.position),
		"open": Transform3D(Basis(Vector3.UP, float(L.open)), pivot.position), "body": body}

# ====================================================================== corridor

static func _corridor(c) -> void:
	var k = c.kit("corr")
	var C: Dictionary = GL.CORR
	var x0: float = C.x0
	var x1 := -3.56
	var z0: float = C.z0
	var z1: float = C.z1
	var ch: float = C.ceil
	k.box("corr_floor", Vector3(x0, -0.25, z0 - 0.2), Vector3(-3.722, 0.0, z1 + 0.2), Color.WHITE, 0.5, Kit.FACE_PY)
	c.col("corr").box(Vector3(x0 - 0.25, -0.3, z0 - 0.2), Vector3(-3.45, 0.0, z1 + 0.2))
	wall(c, "corr", "corr_wall", Vector2(x0, z0 - 0.1), Vector2(x1, z0 - 0.1), 0.2, 0.0, ch, [], true, Color.WHITE, 1.0)
	wall(c, "corr", "corr_wall", Vector2(x0, z1 + 0.1), Vector2(x1, z1 + 0.1), 0.2, 0.0, ch, [], true, Color.WHITE, 1.0)
	k.box("corr_ceil", Vector3(x0, ch, z0 - 0.2), Vector3(x1, ch + 0.2, z1 + 0.2), Color.WHITE, 1.0)
	c.occluders.append(AABB(Vector3(x0, 0.05, z0 - 0.18), Vector3(x1 - x0 - 0.1, ch - 0.1, 0.16)))
	c.occluders.append(AABB(Vector3(x0, 0.05, z1 + 0.02), Vector3(x1 - x0 - 0.1, ch - 0.1, 0.16)))
	# pipes along the ceiling: two copper water lines, a black iron gas pipe, a cast-iron drain stack, conduit
	for pz in [[z0 + 0.08, ch - 0.1, 0.011], [z0 + 0.15, ch - 0.13, 0.009]]:
		k.tube("metal", PackedVector3Array([Vector3(x1, pz[1], pz[0]), Vector3(x0, pz[1], pz[0])]), pz[2], 10, COPPER)
	k.tube("steel_up", PackedVector3Array([Vector3(x1, ch - 0.08, z1 - 0.09), Vector3(-9.0, ch - 0.08, z1 - 0.09), Vector3(-9.0, 0.6, z1 - 0.09)]), 0.017, 10, STEEL_DARK)
	k.box("steel_up", Vector3(-9.12, 0.45, z1 - 0.2), Vector3(-8.88, 0.62, z1), Color(0.35, 0.33, 0.3))
	var drain := PackedVector3Array([Vector3(-8.85, 0.0, z0 + 0.07), Vector3(-8.85, ch, z0 + 0.07)])
	k.tube("steel_up", drain, 0.052, 14, Color(0.2, 0.18, 0.17))
	for hy in [0.55, 1.4]:
		k.tube("steel_up", PackedVector3Array([Vector3(-8.85, hy, z0 + 0.07), Vector3(-8.85, hy + 0.06, z0 + 0.07)]), 0.06, 14, Color(0.17, 0.16, 0.15))
	k.tube("steel_up", PackedVector3Array([Vector3(x1, ch - 0.015, 2.1), Vector3(GL.BULB.x, ch - 0.015, 2.1)]), 0.01, 8, Color(0.55, 0.55, 0.55))
	for i in range(0, 7):
		var px := -4.4 - i * 1.1
		for pz in [z0 + 0.08, z0 + 0.15]:
			k.box("metal", Vector3(px - 0.012, ch - 0.14, pz - 0.016), Vector3(px + 0.012, ch, pz + 0.016), Color(0.4, 0.38, 0.35))
	# bare bulb: junction box, porcelain socket, bulb, pull chain
	var bx: float = GL.BULB.x
	var bz: float = GL.BULB.z
	k.tube("steel_up", PackedVector3Array([Vector3(bx, ch - 0.045, bz), Vector3(bx, ch, bz)]), 0.055, 10, Color(0.5, 0.5, 0.5), 1.0, true)
	k.tube("enamel", PackedVector3Array([Vector3(bx, ch - 0.11, bz), Vector3(bx, ch - 0.045, bz)]), 0.03, 12, Color.WHITE, 1.0, true)
	k.sphere("bulb_on", Vector3(bx, ch - 0.16, bz), 0.032, 12, 8, Color.WHITE, Vector3(1.0, 1.25, 1.0))
	k.box("metal", Vector3(bx + 0.02, ch - 0.42, bz - 0.002), Vector3(bx + 0.024, ch - 0.1, bz + 0.002), Color(0.6, 0.58, 0.5))
	add_light(c, c.region("corr"), Vector3(bx, ch - 0.2, bz), "shadow", "bulb", c.mats.mat("bulb_on"))
	# fuse box near the door, light switch
	k.box("steel_up", Vector3(-4.75, 1.3, z0), Vector3(-4.38, 1.76, z0 + 0.1), Color(0.48, 0.5, 0.47))
	k.box("enamel", Vector3(-4.0, 1.18, z1 - 0.02), Vector3(-3.92, 1.3, z1), Color.WHITE)
	# folded gym mats leaning on the north wall, cardboard boxes, a toppled kid chair
	for i in 3:
		var bas := Basis(Vector3.RIGHT, -0.11 - i * 0.015)
		var ctr := Vector3(-5.6 - i * 0.04, 0.6, z0 + 0.1 + i * 0.05)
		k.box("vinyl_up", Vector3(-0.6, -0.6, -0.03), Vector3(0.6, 0.6, 0.03), [Color(0.17, 0.4, 0.66), Color(0.86, 0.36, 0.14), Color(0.17, 0.4, 0.66)][i], 1.0, Kit.ALL, Transform3D(bas, ctr))
	c.col("corr").box(Vector3(-6.25, 0.0, z0), Vector3(-4.95, 1.2, z0 + 0.29))
	for bxs in [[-10.3, -9.75, z1 - 0.32, z1 - 0.02, 0.0, 0.42], [-10.25, -9.85, z1 - 0.3, z1 - 0.05, 0.42, 0.72], [-9.7, -9.3, z1 - 0.31, z1 - 0.02, 0.0, 0.36]]:
		k.box("wood", Vector3(bxs[0], bxs[4], bxs[2]), Vector3(bxs[1], bxs[5], bxs[3]), Color(0.62, 0.47, 0.31))
		c.col("corr").box(Vector3(bxs[0], bxs[4], bxs[2]), Vector3(bxs[1], bxs[5], bxs[3]))
	sign_quad(k, "tex_labels.jpg", Vector3(-10.02, 0.24, z1 - 0.325), Vector3(0, 0, -1), 0.3, 0.22, Rect2(1.0 / 3.0, 0.0, 1.0 / 3.0, 0.5))
	var chair := Transform3D(Basis(Vector3.FORWARD, 1.45) * Basis(Vector3.UP, 0.6), Vector3(-8.2, 0.16, 2.56))
	c.col("corr").box(Vector3(-8.5, 0.0, 2.42), Vector3(-7.9, 0.3, z1))
	k.box("plastic", Vector3(-0.15, -0.02, -0.15), Vector3(0.15, 0.02, 0.15), Color(0.8, 0.18, 0.14), 1.0, Kit.ALL, chair)
	k.box("plastic", Vector3(-0.15, 0.02, 0.12), Vector3(0.15, 0.3, 0.15), Color(0.8, 0.18, 0.14), 1.0, Kit.ALL, chair)
	for lx in [-0.12, 0.12]:
		for lz in [-0.12, 0.12]:
			k.box("plastic", Vector3(lx - 0.015, -0.28, lz - 0.015), Vector3(lx + 0.015, -0.02, lz + 0.015), Color(0.8, 0.18, 0.14), 1.0, Kit.ALL, chair)
	# painted sun guiding parents to the daycare + a drawing taped near the vestibule
	sign_quad(k, "cut_sun_decal.png", Vector3(-6.9, 1.45, z1 - 0.004), Vector3(0, 0, -1), 0.55, 0.55)
	sign_quad(k, "tex_drawings.jpg", Vector3(-10.4, 1.35, z0 + 0.004), Vector3(0, 0, 1), 0.36, 0.36, Rect2(0.5, 0.0, 0.5, 0.5))

# ====================================================================== vestibule

static func _vestibule(c) -> void:
	var k = c.kit("vest")
	var V: Dictionary = GL.VEST
	var x0: float = V.x0
	var x1: float = V.x1
	var z0: float = V.z0
	var z1: float = V.z1
	var ch: float = V.ceil
	var top := 3.1
	k.box("mats_vest", Vector3(x0, -0.25, z0), Vector3(x1, 0.0, z1), Color.WHITE, 1.0, Kit.FACE_PY)
	k.box("concrete", Vector3(-11.2, -0.25, 1.6), Vector3(-11.0, 0.0, 2.6), Color.WHITE, 1.0, Kit.FACE_PY)
	k.box("concrete", Vector3(-17.2, -0.25, 1.2), Vector3(-17.0, 0.0, 3.0), Color.WHITE, 1.0, Kit.FACE_PY)
	c.col("vest").box(Vector3(-17.25, -0.3, z0 - 0.2), Vector3(-10.95, 0.0, z1 + 0.2))
	var vi: Dictionary = GL.VEST_IN
	var vo: Dictionary = GL.VEST_OUT
	# east wall: vestibule half + corridor half (two materials), opening to the corridor
	wall(c, "vest", "vest_wall", Vector2(-11.15, z0 - 0.2), Vector2(-11.15, z1 + 0.2), 0.1, 0.0, top,
		[[float(vi.z0) - (z0 - 0.2), float(vi.z1) - (z0 - 0.2), 0.0, float(vi.h)]])
	wall(c, "vest", "corr_wall", Vector2(-11.05, GL.CORR.z0 - 0.2), Vector2(-11.05, GL.CORR.z1 + 0.2), 0.1, 0.0, GL.CORR.ceil,
		[[float(vi.z0) - (GL.CORR.z0 - 0.2), float(vi.z1) - (GL.CORR.z0 - 0.2), 0.0, float(vi.h)]], false, Color.WHITE, 1.0)
	# west wall (vestibule half; the hall half is built with the hall)
	wall(c, "vest", "vest_wall", Vector2(-17.05, z0 - 0.2), Vector2(-17.05, z1 + 0.2), 0.1, 0.0, top,
		[[float(vo.z0) - (z0 - 0.2), float(vo.z1) - (z0 - 0.2), 0.0, float(vo.h)]])
	wall(c, "vest", "vest_wall", Vector2(-17.1, z0 - 0.1), Vector2(-11.0, z0 - 0.1), 0.2, 0.0, top)
	wall(c, "vest", "vest_wall", Vector2(-17.1, z1 + 0.1), Vector2(-11.0, z1 + 0.1), 0.2, 0.0, top)
	c.occluders.append(AABB(Vector3(x0, 0.05, z0 - 0.18), Vector3(x1 - x0, top - 0.1, 0.16)))
	c.occluders.append(AABB(Vector3(x0, 0.05, z1 + 0.02), Vector3(x1 - x0, top - 0.1, 0.16)))
	# opening frames (painted steel)
	for fr in [[-11.2, -11.0, float(vi.z0), float(vi.z1), float(vi.h)], [-17.2, -17.0, float(vo.z0), float(vo.z1), float(vo.h)]]:
		k.box("steel_up", Vector3(fr[0] - 0.01, 0.0, fr[2] - 0.05), Vector3(fr[1] + 0.01, fr[4] + 0.05, fr[2]), Color(0.15, 0.42, 0.45))
		k.box("steel_up", Vector3(fr[0] - 0.01, 0.0, fr[3]), Vector3(fr[1] + 0.01, fr[4] + 0.05, fr[3] + 0.05), Color(0.15, 0.42, 0.45))
		k.box("steel_up", Vector3(fr[0] - 0.01, fr[4], fr[2]), Vector3(fr[1] + 0.01, fr[4] + 0.05, fr[3]), Color(0.15, 0.42, 0.45))
	# wainscot (tongue-and-groove, sunflower) + tomato cap rail
	var wh := 1.0
	var wains := [
		[Vector3(x0, 0.0, z0), Vector3(x1, wh, z0 + 0.016), []],
		[Vector3(x0, 0.0, z1 - 0.016), Vector3(x1, wh, z1), []],
	]
	for wn in wains:
		k.box("wainscot", wn[0], wn[1], Color.WHITE, 0.7)
		k.box("paintwood", Vector3(wn[0].x, wh, wn[0].z - 0.012 if wn[0].z < 0 else wn[0].z - 0.012), Vector3(wn[1].x, wh + 0.05, wn[1].z + 0.012), M.TOMATO)
	for side in [[x1 - 0.016, x1, float(vi.z0), float(vi.z1)], [x0, x0 + 0.016, float(vo.z0), float(vo.z1)]]:
		k.box("wainscot", Vector3(side[0], 0.0, z0), Vector3(side[1], wh, float(side[2])), Color.WHITE, 0.7)
		k.box("wainscot", Vector3(side[0], 0.0, float(side[3])), Vector3(side[1], wh, z1), Color.WHITE, 0.7)
		k.box("paintwood", Vector3(side[0] - 0.012, wh, z0), Vector3(side[1] + 0.012, wh + 0.05, float(side[2])), M.TOMATO)
		k.box("paintwood", Vector3(side[0] - 0.012, wh, float(side[3])), Vector3(side[1] + 0.012, wh + 0.05, z1), M.TOMATO)
	# drop ceiling: 2' x 2' tiles in a T-bar grid, troffers, missing / sagging tiles, dark plenum above
	k.box("dark", Vector3(x0, top, z0), Vector3(x1, top + 0.2, z1), Color.WHITE, 1.0, Kit.FACE_NY)
	var cell := 0.6
	var nx := int(ceil((x1 - x0) / cell))
	var nz := int(ceil((z1 - z0) / cell))
	var troff := {}
	var tlights: Array = []
	for L in GL.VEST_LIGHTS:
		var ti := int(L[0])
		var tj := int(L[1])
		troff[Vector2i(ti, tj)] = true
		troff[Vector2i(ti, tj + 1)] = true
		tlights.append([ti, tj, String(L[2])])
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var missing := {Vector2i(4, 3): true, Vector2i(8, 8): true, Vector2i(1, 8): true}
	for i in nx:
		for j in nz:
			if troff.has(Vector2i(i, j)) or missing.has(Vector2i(i, j)):
				continue
			var ax := x0 + i * cell
			var bx := minf(ax + cell, x1)
			var az := z0 + j * cell
			var bz := minf(az + cell, z1)
			var v := 0
			var r := rng.randf()
			if r > 0.8: v = 1
			if r > 0.92: v = 2
			if Vector2i(i, j) == Vector2i(5, 3) or Vector2i(i, j) == Vector2i(3, 6): v = 3
			var u0 := v * 0.25
			var du := 0.25 * (bx - ax) / cell
			var dv := (bz - az) / cell
			var sag := -0.035 if v == 3 else 0.0
			k.quad("ceiltile", Vector3(ax, ch, az), Vector3(bx, ch, az), Vector3(bx, ch + sag * 0.0, bz), Vector3(ax, ch + sag, bz), Vector3.DOWN,
				Vector2(u0, 0.0), Vector2(u0 + du, 0.0), Vector2(u0 + du, dv), Vector2(u0, dv))
	for i in nx + 1:
		var gx := minf(x0 + i * cell, x1)
		k.box("enamel", Vector3(gx - 0.012, ch - 0.006, z0), Vector3(gx + 0.012, ch + 0.03, z1), Color.WHITE)
	for j in nz + 1:
		var gz := minf(z0 + j * cell, z1)
		k.box("enamel", Vector3(x0, ch - 0.006, gz - 0.012), Vector3(x1, ch + 0.03, gz + 0.012), Color.WHITE)
	for tl in tlights:
		var ax := x0 + int(tl[0]) * cell
		var az := z0 + int(tl[1]) * cell
		var state: String = tl[2]
		k.box("enamel", Vector3(ax + 0.01, ch, az + 0.01), Vector3(ax + cell - 0.01, ch + 0.1, az + cell * 2.0 - 0.01), Color.WHITE)
		var em_id := "fluo_on" if state == "on" or state == "shadow" else "fluo_dead"
		var em: Material = c.mats.mat(em_id)
		if state == "flicker":
			em = c.mats.emissive_instance("fluo_on")
		var lens_k = c.kit("vest") if state != "flicker" else Kit.new()
		lens_k.quad(em_id if state != "flicker" else "flick", Vector3(ax + 0.03, ch - 0.004, az + 0.03), Vector3(ax + cell - 0.03, ch - 0.004, az + 0.03),
			Vector3(ax + cell - 0.03, ch - 0.004, az + cell * 2.0 - 0.03), Vector3(ax + 0.03, ch - 0.004, az + cell * 2.0 - 0.03), Vector3.DOWN,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		if state == "flicker":
			lens_k.commit(c.region("vest"), {"flick": em}, "flicker_lens", {"no_shadow": ["flick"]})
		k.box("enamel", Vector3(ax + 0.03, ch - 0.008, az + cell - 0.015), Vector3(ax + cell - 0.03, ch - 0.002, az + cell + 0.015), Color(0.9, 0.9, 0.88))
		add_light(c, c.region("vest"), Vector3(ax + cell * 0.5, ch - 0.06, az + cell), state, "troffer", em)
		if state != "dead":
			var o := OmniLight3D.new()
			o.name = "troffer_spill_%s" % state
			o.position = Vector3(ax + cell * 0.5, ch - 0.35, az + cell)
			o.omni_range = 2.2
			o.omni_attenuation = 1.6
			o.light_energy = 0.35
			o.light_color = Color(0.92, 0.96, 1.0)
			o.light_specular = 0.0
			o.light_cull_mask = MASK_FRONT
			o.shadow_enabled = false
			c.region("vest").add_child(o)
			c.lights.append({"light": o, "state": state, "kind": "spill", "emit": null, "base": o.light_energy, "pos": o.position})
	# padded columns
	for p in GL.VEST_COLUMNS:
		padded_column(c, "vest", "vinyl_up", p.x, p.y, 0.0, ch, 0.2, int(p.x * 13.0 + p.y * 7.0))

# ====================================================================== hall

static func _hall(c) -> void:
	var k = c.kit("hall")
	var H: Dictionary = GL.HALLB
	var x0: float = H.x0
	var x1: float = H.x1
	var z0: float = H.z0
	var z1: float = H.z1
	var roof: float = H.roof
	var F := GL.HALL
	k.box("mats_hall", Vector3(x0 - 0.3, F - 0.3, z0 - 0.3), Vector3(x1, F, z1 + 0.3), Color.WHITE, 1.0, Kit.FACE_PY)
	c.col("hall").box(Vector3(x0 - 0.3, F - 0.4, z0 - 0.3), Vector3(x1 + 0.05, F, z1 + 0.3))
	var ex: Dictionary = GL.EXIT_DOOR
	wall(c, "hall", "hall_wall", Vector2(x0 - 0.15, z0 - 0.3), Vector2(x0 - 0.15, z1 + 0.3), 0.3, F, roof,
		[[float(ex.z0) - (z0 - 0.3), float(ex.z1) - (z0 - 0.3), F, F + float(ex.h)]])
	wall(c, "hall", "hall_wall", Vector2(x0 - 0.3, z0 - 0.15), Vector2(x1, z0 - 0.15), 0.3, F, roof)
	wall(c, "hall", "hall_wall", Vector2(x0 - 0.3, z1 + 0.15), Vector2(x1, z1 + 0.15), 0.3, F, roof)
	var vo: Dictionary = GL.VEST_OUT
	wall(c, "hall", "hall_wall", Vector2(-17.15, z0 - 0.3), Vector2(-17.15, z1 + 0.3), 0.1, F, roof,
		[[float(vo.z0) - (z0 - 0.3), float(vo.z1) - (z0 - 0.3), GL.UP, GL.UP + float(vo.h)]])
	for ab in [AABB(Vector3(x0 - 0.28, F, z0), Vector3(0.26, roof - F, z1 - z0)), AABB(Vector3(x0, F, z0 - 0.28), Vector3(x1 - x0, roof - F, 0.26)),
			AABB(Vector3(x0, F, z1 + 0.02), Vector3(x1 - x0, roof - F, 0.26))]:
		c.occluders.append(ab)
	c.occluders.append(AABB(Vector3(-17.18, 2.3, z0), Vector3(0.16, roof - 2.3, z1 - z0)))
	c.occluders.append(AABB(Vector3(-17.18, F, z0), Vector3(0.16, -F + 0.0, z1 - z0)))
	# roof deck + bar-joist trusses (no shadows: they sit above every light)
	k.box("roof", Vector3(x0 - 0.3, roof, z0 - 0.3), Vector3(x1, roof + 0.2, z1 + 0.3), Color.WHITE, 0.5)
	var tk = c.kit("trusses")
	var tx := -18.6
	while tx > x0 + 0.5:
		tk.box("steel", Vector3(tx - 0.06, roof - 0.12, z0), Vector3(tx + 0.06, roof - 0.02, z1), STEEL_DARK)
		tk.box("steel", Vector3(tx - 0.05, roof - 0.72, z0), Vector3(tx + 0.05, roof - 0.64, z1), STEEL_DARK)
		var zz := z0
		var up := true
		while zz < z1 - 0.01:
			var zn := minf(zz + 0.75, z1)
			var a := Vector3(tx, roof - 0.68 if up else roof - 0.07, zz)
			var b := Vector3(tx, roof - 0.07 if up else roof - 0.68, zn)
			tk.tube("steel", PackedVector3Array([a, b]), 0.016, 6, STEEL_DARK)
			zz = zn
			up = not up
		tx -= 2.4
	# purlins
	var pz := z0 + 1.2
	while pz < z1:
		tk.box("steel", Vector3(x0, roof - 0.14, pz - 0.04), Vector3(x1, roof - 0.02, pz + 0.04), STEEL_DARK)
		pz += 2.4
	# high-bay fluorescent fixtures on chains
	for L in GL.HALL_LIGHTS:
		_highbay(c, Vector3(float(L[0]), GL.HALL_LIGHT_Y, float(L[1])), String(L[2]))
	# padded building columns
	for p in GL.HALL_COLUMNS:
		padded_column(c, "hall", "vinyl", p.x, p.y, F, F + 2.5, 0.23, int(p.x * 11.0 + p.y * 3.0))
		k.tube("steel", PackedVector3Array([Vector3(p.x, F + 2.45, p.y), Vector3(p.x, roof - 0.64, p.y)]), 0.1, 12, Color(0.2, 0.28, 0.34))
		c.col("hall").box(Vector3(p.x - 0.12, F + 2.4, p.y - 0.12), Vector3(p.x + 0.12, roof, p.y + 0.12))
	# emergency exit (chained) + green SORTIE pictogram
	var ez0: float = ex.z0
	var ez1: float = ex.z1
	var eh: float = ex.h
	k.box("steel", Vector3(x0 - 0.06, F, ez0), Vector3(x0 - 0.02, F + eh, ez1), Color(0.42, 0.16, 0.12))
	k.box("steel", Vector3(x0, F, ez0 - 0.07), Vector3(x0 + 0.03, F + eh + 0.07, ez0), Color(0.25, 0.25, 0.26))
	k.box("steel", Vector3(x0, F, ez1), Vector3(x0 + 0.03, F + eh + 0.07, ez1 + 0.07), Color(0.25, 0.25, 0.26))
	k.box("steel", Vector3(x0, F + eh, ez0), Vector3(x0 + 0.03, F + eh + 0.07, ez1), Color(0.25, 0.25, 0.26))
	k.box("metal", Vector3(x0 - 0.02, F + 0.98, ez0 + 0.1), Vector3(x0 + 0.06, F + 1.06, ez1 - 0.1), Color(0.6, 0.6, 0.6))
	for i in 9:
		var t := float(i) / 8.0
		var cz := lerpf(ez0 + 0.12, ez1 - 0.12, t)
		var cy := F + 1.02 - sin(t * PI) * 0.12
		k.box("metal", Vector3(x0 + 0.06, cy - 0.012, cz - 0.03), Vector3(x0 + 0.075, cy + 0.012, cz + 0.03), Color(0.45, 0.43, 0.4))
	k.box("metal", Vector3(x0 + 0.06, F + 0.78, (ez0 + ez1) * 0.5 - 0.04), Vector3(x0 + 0.1, F + 0.86, (ez0 + ez1) * 0.5 + 0.04), Color(0.7, 0.55, 0.25))
	c.col("hall").box(Vector3(x0 - 0.06, F, ez0), Vector3(x0 + 0.02, F + eh, ez1))
	_exit_sign(c, Vector3(x0 + 0.08, F + eh + 0.32, (ez0 + ez1) * 0.5), Vector3.RIGHT, "green")
	_exit_sign(c, Vector3(-17.2 - 0.08, GL.UP + float(vo.h) + 0.33, (float(vo.z0) + float(vo.z1)) * 0.5), Vector3.LEFT, "red")
	# mural (north wall), birthday banner (south wall, above the party tables), drawings near the toddler corner
	var Mu: Dictionary = GL.MURAL
	sign_quad(k, "mural", Vector3((float(Mu.x0) + float(Mu.x1)) * 0.5, (float(Mu.y0) + float(Mu.y1)) * 0.5, z0 + 0.004), Vector3.BACK,
		float(Mu.x1) - float(Mu.x0), float(Mu.y1) - float(Mu.y0))
	sign_quad(k, "cut_banner.png", Vector3(-20.8, F + 2.55, z1 - 0.012), Vector3.FORWARD, 4.2, 0.53)
	for i in 3:
		sign_quad(k, "tex_drawings.jpg", Vector3(x0 + 0.004, F + 1.25 + (i % 2) * 0.12, 5.2 + i * 0.75), Vector3.RIGHT, 0.42, 0.42,
			Rect2(0.5 * float(i % 2), 0.5 * float(i / 2), 0.5, 0.5))

static func _highbay(c, pos: Vector3, state: String) -> void:
	var k = c.kit("fixtures")
	var top: float = GL.HALLB.roof - 0.68
	for sx: float in [-0.45, 0.45]:
		var cx := pos.x + sx
		var y := top
		while y > pos.y + 0.06:
			k.box("metal", Vector3(cx - 0.006, y - 0.045, pos.z - 0.012), Vector3(cx + 0.006, y, pos.z + 0.012), Color(0.45, 0.45, 0.45))
			y -= 0.05
	k.box("enamel", Vector3(pos.x - 0.64, pos.y + 0.02, pos.z - 0.03), Vector3(pos.x + 0.64, pos.y + 0.08, pos.z + 0.03), Color(0.85, 0.85, 0.82))
	# reflector wings (angled)
	for sz in [-1.0, 1.0]:
		var bas := Basis(Vector3.RIGHT, sz * 0.75)
		var ctr := Vector3(pos.x, pos.y + 0.035, pos.z + sz * 0.1)
		k.box("enamel", Vector3(-0.64, -0.006, -0.1), Vector3(0.64, 0.006, 0.1), Color(0.88, 0.88, 0.85), 1.0, Kit.ALL, Transform3D(bas, ctr))
	var em_id := "fluo_on" if state in ["on", "shadow", "dim"] else "fluo_dead"
	var em: Material = c.mats.mat(em_id)
	var tk = k
	if state == "flicker":
		em = c.mats.emissive_instance("fluo_on")
		tk = Kit.new()
		em_id = "flick"
	for tz in [-0.05, 0.05]:
		tk.tube(em_id, PackedVector3Array([Vector3(pos.x - 0.6, pos.y, pos.z + tz), Vector3(pos.x + 0.6, pos.y, pos.z + tz)]), 0.0135, 10, Color.WHITE)
	for sx in [-0.63, 0.63]:
		k.box("enamel", Vector3(pos.x + sx - 0.02, pos.y - 0.03, pos.z - 0.09), Vector3(pos.x + sx + 0.02, pos.y + 0.03, pos.z + 0.09), Color(0.8, 0.8, 0.78))
	if state == "flicker":
		tk.commit(c.region("fixtures"), {"flick": em}, "flicker_tubes", {"no_shadow": ["flick"]})
	add_light(c, c.region("hall_lights"), pos - Vector3(0, 0.05, 0), state, "highbay", em)

static func _exit_sign(c, pos: Vector3, nrm: Vector3, kind: String) -> void:
	var k = c.kit("hall")
	var w := 0.42 if kind == "red" else 0.46
	var h := 0.16 if kind == "red" else 0.23
	board(k, "steel", pos, nrm, w + 0.05, h + 0.05, 0.08, Color(0.85, 0.85, 0.82) if kind == "green" else Color(0.2, 0.2, 0.2))
	sign_quad(k, "emit_sortie_red.png" if kind == "red" else "emit_sortie_green.png", pos + nrm * 0.002, nrm, w, h)
	var o := SpotLight3D.new()
	o.position = pos + nrm * 0.06 + Vector3(0, -0.12, 0)
	o.light_color = Color(1.0, 0.18, 0.12) if kind == "red" else Color(0.2, 1.0, 0.45)
	o.light_energy = 0.9
	o.spot_range = 3.2
	o.spot_angle = 75.0
	o.spot_angle_attenuation = 1.2
	o.shadow_enabled = false
	o.light_volumetric_fog_energy = 0.8
	o.light_cull_mask = MASK_HALL
	o.name = "Sortie_%s" % kind
	o.basis = Basis.looking_at(nrm + Vector3(0, -0.35, 0), Vector3.UP)
	c.region("hall_lights").add_child(o)
	c.signs.append(o)

# ====================================================================== landing + steps

static func _landing(c) -> void:
	var k = c.kit("hall")
	var Ld: Dictionary = GL.LANDING
	var lx0: float = Ld.x0
	var lx1: float = Ld.x1
	var lz0: float = Ld.z0
	var lz1: float = Ld.z1
	var F := GL.HALL
	k.box("mats_hall", Vector3(lx0, F, lz0), Vector3(lx1, GL.UP, lz1), Color.WHITE, 1.0, Kit.FACE_PY)
	k.box("concrete", Vector3(lx0, F, lz0), Vector3(lx1, GL.UP, lz1), Color.WHITE, 0.6, Kit.FACE_NX | Kit.FACE_PZ | Kit.FACE_NZ)
	c.col("hall").box(Vector3(lx0, F - 0.05, lz0), Vector3(lx1, GL.UP, lz1))
	k.box("steel", Vector3(lx0 - 0.012, -0.03, lz0), Vector3(lx0 + 0.05, 0.003, lz1), YELLOW)
	# railings (yellow steel pipe) + colliders
	var S: Dictionary = GL.STEPS
	var segs := [
		[Vector3(lx0 + 0.03, 0, lz0 + 0.03), Vector3(lx1, 0, lz0 + 0.03)],
		[Vector3(lx0 + 0.03, 0, lz0 + 0.03), Vector3(lx0 + 0.03, 0, float(S.z0))],
		[Vector3(lx0 + 0.03, 0, float(S.z1)), Vector3(lx0 + 0.03, 0, lz1 - 0.03)],
		[Vector3(lx0 + 0.03, 0, lz1 - 0.03), Vector3(lx1, 0, lz1 - 0.03)],
	]
	for sg in segs:
		_rail(c, "hall", sg[0], sg[1], 0.0, YELLOW, true)
	# steps: concrete treads with yellow nosings, ramp collider through the nosings
	var n: int = S.n
	var rise: float = S.rise
	var run: float = S.run
	var sx: float = S.x_top
	for i in n - 1:
		var xa := sx - run * (i + 1)
		var xb := sx - run * i
		var ty := -rise * (i + 1)
		k.box("concrete", Vector3(xa, F, float(S.z0)), Vector3(xb, ty, float(S.z1)), Color(0.92, 0.9, 0.86), 0.6)
		k.box("steel", Vector3(xa - 0.004, ty, float(S.z0) + 0.02), Vector3(xa + 0.05, ty + 0.004, float(S.z1) - 0.02), YELLOW)
	c.col("hall").ramp_x(sx - run * n, sx, F, GL.UP, float(S.z0), float(S.z1))
	for zz in [float(S.z0) + 0.04, float(S.z1) - 0.04]:
		var a := Vector3(sx + 0.05, 0.0, zz)
		var b := Vector3(sx - run * (n - 1) - 0.1, F, zz)
		for pp in [a, b]:
			c.kit("hall").tube("steel", PackedVector3Array([Vector3(pp.x, pp.y, pp.z), Vector3(pp.x, pp.y + 0.92, pp.z)]), 0.022, 10, YELLOW)
		c.kit("hall").tube("steel", PackedVector3Array([a + Vector3(0, 0.9, 0), b + Vector3(0, 0.9, 0)]), 0.022, 10, YELLOW)

## Pipe railing between two points at height y0 (posts every <= 1.3 m, top + mid rail) with a collider wall.
static func _rail(c, region: String, a: Vector3, b: Vector3, y0: float, col: Color, collide: bool) -> void:
	var k = c.kit(region)
	var L := a.distance_to(b)
	var n := maxi(1, int(ceil(L / 1.3)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		k.tube("steel", PackedVector3Array([Vector3(p.x, y0, p.z), Vector3(p.x, y0 + 0.97, p.z)]), 0.022, 10, col)
	for hh in [0.95, 0.5]:
		k.tube("steel", PackedVector3Array([Vector3(a.x, y0 + hh, a.z), Vector3(b.x, y0 + hh, b.z)]), 0.02, 10, col)
	if collide:
		var mn := Vector3(minf(a.x, b.x) - 0.03, y0, minf(a.z, b.z) - 0.03)
		var mx := Vector3(maxf(a.x, b.x) + 0.03, y0 + 1.0, maxf(a.z, b.z) + 0.03)
		c.col_see(region).box(mn, mx)
