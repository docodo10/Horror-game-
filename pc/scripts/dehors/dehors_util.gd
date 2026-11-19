## Small building helpers shared by the builders of chapter 3 (dehors_build.gd, dehors_props.gd).
extends RefCounted

## A collider box that she walks around too.
static func solid(c, region: String, mn: Vector3, mx: Vector3, see := false) -> void:
	if see:
		c.col_see(region).box(mn, mx)
	else:
		c.col(region).box(mn, mx)
	(c.room_fx["solids"] as Array).append(Rect2(mn.x, mn.z, mx.x - mn.x, mx.z - mn.z))

## Truncated cone between two points (pots, buckets, trunks).
static func cone(k, mat: String, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col := Color.WHITE, caps := false) -> void:
	var q := r1 / maxf(r0, 1e-5)
	k.tube(mat, PackedVector3Array([a, b]), r0, sides, col, 1.0, caps, func(i: int, _ang: float) -> float: return 1.0 if i == 0 else q)

## One cell of the tree atlas as a card standing at `base`, turned by yaw; `planes` crossed quads.
## lit_up: both faces are emitted with the normal pointing up (grass tufts take the light like the lawn they stand
## on, whichever side they are seen from; their material culls back faces).
static func card(k, base: Vector3, w: float, h: float, cell: Rect2, yaw: float, planes := 2, tint := Color.WHITE, mat := "dh_trees", lit_up := false) -> void:
	for i in planes:
		var a := yaw + PI * float(i) / float(planes)
		var r := Vector3(cos(a), 0.0, sin(a)) * w * 0.5
		var n := Vector3(-sin(a), 0.0, cos(a))
		for side in (2 if lit_up else 1):
			k.quad(mat, base - r, base + r, base + r + Vector3(0, h, 0), base - r + Vector3(0, h, 0), n if side == 0 else -n,
				Vector2(cell.position.x, cell.end.y), cell.end, Vector2(cell.end.x, cell.position.y), cell.position, tint)
			if lit_up:
				var bn = k.bin(mat)
				for j in 4:
					bn.n[bn.n.size() - 1 - j] = Vector3(0.0, 1.0, 0.0)

static func bare_cell(i: int) -> Rect2:
	return Rect2(0.25 * float(i % 4) + 0.004, 0.004, 0.242, 0.494)

static func fir_cell(i: int) -> Rect2:
	return Rect2(0.25 * float(i % 2) + 0.004, 0.504, 0.242, 0.492)

static func bush_cell(i: int) -> Rect2:
	return Rect2(0.504, 0.504 + 0.25 * float(i % 2), 0.242, 0.242)

static func hedge_cell(i: int) -> Rect2:
	return Rect2(0.754, 0.504 + 0.25 * float(i % 2), 0.242, 0.242)
