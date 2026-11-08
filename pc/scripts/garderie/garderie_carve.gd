## Cuts the garderie doorway through geometry owned by other modules, whatever material or shader they use later:
##  * meshes (the room's `arch_wall`, its baseboard, the stair skirt tip, the shadow-caster boxes, a stub wall BoxMesh…):
##    every triangle is clipped against a world-space box and the parts inside are removed; the remaining pieces are
##    re-triangulated with ALL vertex attributes interpolated (UV, UV2, normal, tangent, colour), so the wall keeps its
##    look and the hole is exact in every pass (colour, depth, shadow maps, SDFGI). Robust to material swaps by the
##    surfaces/look modules (it is geometry, not a shader trick); call `recarve()` again if a module rebuilds meshes.
##  * static colliders and ray blockers: BoxShape3D split into the pieces around the opening (same body, layer, tags;
##    the original shape is disabled), ConcavePolygonShape3D faces clipped;
##  * OccluderInstance3D: boxes split, array/quad/polygon occluders clipped.
## Skips skinned / blend-shape meshes and anything under a CharacterBody3D / RigidBody3D, and the garderie itself.
extends RefCounted

const EPS := 1e-5

## Returns a report {meshes: [names], shapes: [names], occluders: [names], skipped: [notes]}.
static func carve(search_root: Node, exclude: Node, mesh_box: AABB, cut_box: AABB) -> Dictionary:
	var rep := {"meshes": [], "shapes": [], "occluders": [], "skipped": []}
	if search_root == null:
		return rep
	var nodes: Array = [search_root]
	nodes.append_array(search_root.find_children("*", "", true, false))
	for node in nodes:
		if exclude != null and (node == exclude or exclude.is_ancestor_of(node)):
			continue
		if _under_dynamic(node):
			continue
		if node is MeshInstance3D:
			_carve_mesh(node as MeshInstance3D, mesh_box, rep)
		elif node is CollisionShape3D:
			_split_shape(node as CollisionShape3D, cut_box, rep)
		elif node is OccluderInstance3D:
			_split_occluder(node as OccluderInstance3D, cut_box, rep)
	return rep

static func _under_dynamic(n: Node) -> bool:
	var p := n
	while p != null:
		if p is CharacterBody3D or p is RigidBody3D or p is Skeleton3D or p is VehicleBody3D:
			return true
		p = p.get_parent()
	return false

# ---------------------------------------------------------------- meshes

static func _carve_mesh(mi: MeshInstance3D, box: AABB, rep: Dictionary) -> void:
	var src := mi.mesh
	if src == null or not mi.is_inside_tree():
		return
	var gx := mi.global_transform
	if not (gx * mi.get_aabb()).intersects(box):
		return
	if mi.skin != null or src.get_blend_shape_count() > 0:
		rep.skipped.append("%s: skinned/blend shapes" % mi.name)
		return
	var surfaces: Array = []
	var mats: Array = []
	var names: Array = []
	if src is PrimitiveMesh:
		surfaces.append((src as PrimitiveMesh).get_mesh_arrays())
		mats.append((src as PrimitiveMesh).material)
		names.append("")
	elif src is ArrayMesh:
		var am := src as ArrayMesh
		for s in am.get_surface_count():
			if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				rep.skipped.append("%s: surface %d not triangles" % [mi.name, s])
				return
			surfaces.append(am.surface_get_arrays(s))
			mats.append(am.surface_get_material(s))
			names.append(am.surface_get_name(s))
	else:
		rep.skipped.append("%s: unsupported mesh type %s" % [mi.name, src.get_class()])
		return
	var changed := false
	var out_arrays: Array = []
	for s in surfaces.size():
		var res: Variant = _clip_arrays(surfaces[s], gx, box)
		if res == null:
			out_arrays.append(surfaces[s])
		else:
			changed = true
			out_arrays.append(res)
	if not changed:
		return
	var out := ArrayMesh.new()
	var kept := 0
	for s in out_arrays.size():
		var idx: Variant = (out_arrays[s] as Array)[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).is_empty():
			# the whole surface was inside the opening: keep an invisible degenerate triangle so surface
			# indices (and per-surface override materials) stay valid
			var arr: Array = (out_arrays[s] as Array).duplicate()
			arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 0, 0])
			out_arrays[s] = arr
		else:
			kept += 1
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays[s])
		if mats[s] != null:
			out.surface_set_material(s, mats[s])
		if names[s] != "":
			out.surface_set_name(s, names[s])
	if kept == 0:
		mi.visible = false
	out.resource_name = (src.resource_name + "_garderie_cut") if src.resource_name != "" else "garderie_cut"
	mi.mesh = out
	mi.set_meta("garderie_carved", true)
	rep.meshes.append(String(mi.name))

## Clips one surface's arrays against the world box. Returns the new arrays, or null when nothing changed.
static func _clip_arrays(arr: Array, gx: Transform3D, box: AABB) -> Variant:
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if V.is_empty():
		return null
	for k in [Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		if arr[k] != null:
			return null
	var I := PackedInt32Array()
	if arr[Mesh.ARRAY_INDEX] != null and (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() > 0:
		I = arr[Mesh.ARRAY_INDEX]
	else:
		I.resize(V.size())
		for i in V.size():
			I[i] = i
	var W := PackedVector3Array()
	W.resize(V.size())
	for i in V.size():
		W[i] = gx * V[i]
	var bmin := box.position
	var bmax := box.end
	# attribute arrays (copied; new vertices appended)
	var NV := V.duplicate()
	var NN: PackedVector3Array = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var NT: PackedFloat32Array = (arr[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate() if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var NU: PackedVector2Array = (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).duplicate() if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var NU2: PackedVector2Array = (arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).duplicate() if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var NC: PackedColorArray = (arr[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate() if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var has_n := NN.size() == V.size()
	var has_t := NT.size() == V.size() * 4
	var has_u := NU.size() == V.size()
	var has_u2 := NU2.size() == V.size()
	var has_c := NC.size() == V.size()
	var NI := PackedInt32Array()
	var changed := false
	for t in I.size() / 3:
		var ia := I[t * 3]
		var ib := I[t * 3 + 1]
		var ic := I[t * 3 + 2]
		var a := W[ia]
		var b := W[ib]
		var c := W[ic]
		# fast path: entirely outside one face of the box
		if (a.x <= bmin.x + EPS and b.x <= bmin.x + EPS and c.x <= bmin.x + EPS) \
			or (a.x >= bmax.x - EPS and b.x >= bmax.x - EPS and c.x >= bmax.x - EPS) \
			or (a.y <= bmin.y + EPS and b.y <= bmin.y + EPS and c.y <= bmin.y + EPS) \
			or (a.y >= bmax.y - EPS and b.y >= bmax.y - EPS and c.y >= bmax.y - EPS) \
			or (a.z <= bmin.z + EPS and b.z <= bmin.z + EPS and c.z <= bmin.z + EPS) \
			or (a.z >= bmax.z - EPS and b.z >= bmax.z - EPS and c.z >= bmax.z - EPS):
			NI.append(ia); NI.append(ib); NI.append(ic)
			continue
		changed = true
		# polygon = Array of [world_pos, barycentric(Vector3)]
		var rem: Array = [[a, Vector3(1, 0, 0)], [b, Vector3(0, 1, 0)], [c, Vector3(0, 0, 1)]]
		var pieces: Array = []
		for plane in [[0, bmin.x, -1], [0, bmax.x, 1], [2, bmin.z, -1], [2, bmax.z, 1], [1, bmin.y, -1], [1, bmax.y, 1]]:
			if rem.is_empty():
				break
			var outside := _clip_poly(rem, plane[0], plane[1], plane[2])
			if outside.size() >= 3:
				pieces.append(outside)
			rem = _clip_poly(rem, plane[0], plane[1], -plane[2])
		# whatever is left in `rem` lies inside the box: dropped
		for poly in pieces:
			var ids := PackedInt32Array()
			for pv in poly:
				var w: Vector3 = pv[1]
				var k := NV.size()
				NV.append(V[ia] * w.x + V[ib] * w.y + V[ic] * w.z)
				if has_n:
					var nn: Vector3 = NN[ia] * w.x + NN[ib] * w.y + NN[ic] * w.z
					NN.append(nn.normalized() if nn.length_squared() > 1e-12 else NN[ia])
				if has_t:
					var tv := Vector3(NT[ia * 4], NT[ia * 4 + 1], NT[ia * 4 + 2]) * w.x \
						+ Vector3(NT[ib * 4], NT[ib * 4 + 1], NT[ib * 4 + 2]) * w.y \
						+ Vector3(NT[ic * 4], NT[ic * 4 + 1], NT[ic * 4 + 2]) * w.z
					tv = tv.normalized() if tv.length_squared() > 1e-12 else Vector3(NT[ia * 4], NT[ia * 4 + 1], NT[ia * 4 + 2])
					NT.append(tv.x); NT.append(tv.y); NT.append(tv.z); NT.append(NT[ia * 4 + 3])
				if has_u:
					NU.append(NU[ia] * w.x + NU[ib] * w.y + NU[ic] * w.z)
				if has_u2:
					NU2.append(NU2[ia] * w.x + NU2[ib] * w.y + NU2[ic] * w.z)
				if has_c:
					NC.append(NC[ia] * w.x + NC[ib] * w.y + NC[ic] * w.z)
				ids.append(k)
			for f in range(1, ids.size() - 1):
				var p0: Vector3 = poly[0][0]
				var p1: Vector3 = poly[f][0]
				var p2: Vector3 = poly[f + 1][0]
				if (p1 - p0).cross(p2 - p0).length_squared() < 1e-14:
					continue
				NI.append(ids[0]); NI.append(ids[f]); NI.append(ids[f + 1])
	if not changed:
		return null
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = NV
	if has_n: out[Mesh.ARRAY_NORMAL] = NN
	if has_t: out[Mesh.ARRAY_TANGENT] = NT
	if has_u: out[Mesh.ARRAY_TEX_UV] = NU
	if has_u2: out[Mesh.ARRAY_TEX_UV2] = NU2
	if has_c: out[Mesh.ARRAY_COLOR] = NC
	out[Mesh.ARRAY_INDEX] = NI
	return out

## Sutherland–Hodgman against one axis plane. side = -1 keeps the part with coord <= value, +1 keeps coord >= value.
static func _clip_poly(poly: Array, axis: int, value: float, side: int) -> Array:
	var out: Array = []
	var n := poly.size()
	if n == 0:
		return out
	for i in n:
		var cur: Array = poly[i]
		var nxt: Array = poly[(i + 1) % n]
		var pc: Vector3 = cur[0]
		var pn: Vector3 = nxt[0]
		var dc := (pc[axis] - value) * side
		var dn := (pn[axis] - value) * side
		var cin := dc >= -EPS
		var nin := dn >= -EPS
		if cin:
			out.append(cur)
		if cin != nin:
			var t := dc / (dc - dn)
			var bc: Vector3 = cur[1]
			var bn: Vector3 = nxt[1]
			out.append([pc.lerp(pn, t), bc.lerp(bn, t)])
	return out

# ---------------------------------------------------------------- colliders

static func _axis_aligned(b: Basis) -> bool:
	for v in [b.x, b.y, b.z]:
		var a := (v as Vector3).abs()
		var m := maxf(a.x, maxf(a.y, a.z))
		if a.x + a.y + a.z - m > 1e-4:
			return false
	return true

## a minus b as up to 6 boxes (x slabs, then z slabs, then y slabs of what is left).
static func aabb_minus(a: AABB, b: AABB) -> Array[AABB]:
	var out: Array[AABB] = []
	var lo := a.position
	var hi := a.end
	var bl := b.position
	var bh := b.end
	if bl.x > lo.x:
		out.append(AABB(lo, Vector3(minf(bl.x, hi.x) - lo.x, hi.y - lo.y, hi.z - lo.z)))
		lo.x = minf(bl.x, hi.x)
	if bh.x < hi.x:
		out.append(AABB(Vector3(maxf(bh.x, lo.x), lo.y, lo.z), Vector3(hi.x - maxf(bh.x, lo.x), hi.y - lo.y, hi.z - lo.z)))
		hi.x = maxf(bh.x, lo.x)
	if bl.z > lo.z:
		out.append(AABB(lo, Vector3(hi.x - lo.x, hi.y - lo.y, minf(bl.z, hi.z) - lo.z)))
		lo.z = minf(bl.z, hi.z)
	if bh.z < hi.z:
		out.append(AABB(Vector3(lo.x, lo.y, maxf(bh.z, lo.z)), Vector3(hi.x - lo.x, hi.y - lo.y, hi.z - maxf(bh.z, lo.z))))
		hi.z = maxf(bh.z, lo.z)
	if bl.y > lo.y:
		out.append(AABB(lo, Vector3(hi.x - lo.x, minf(bl.y, hi.y) - lo.y, hi.z - lo.z)))
		lo.y = minf(bl.y, hi.y)
	if bh.y < hi.y:
		out.append(AABB(Vector3(lo.x, maxf(bh.y, lo.y), lo.z), Vector3(hi.x - lo.x, hi.y - maxf(bh.y, lo.y), hi.z - lo.z)))
	var keep: Array[AABB] = []
	for p in out:
		if p.size.x > 0.002 and p.size.y > 0.002 and p.size.z > 0.002:
			keep.append(p)
	return keep

static func _split_shape(cs: CollisionShape3D, cut: AABB, rep: Dictionary) -> void:
	if cs.disabled or cs.shape == null or not cs.is_inside_tree():
		return
	var body := cs.get_parent()
	if not (body is StaticBody3D):
		return
	var gx := cs.global_transform
	var sh := cs.shape
	if sh is BoxShape3D:
		var size: Vector3 = (sh as BoxShape3D).size
		var wab := gx * AABB(-size * 0.5, size)
		var inter := wab.intersection(cut)
		if inter.size.x < 0.01 or inter.size.y < 0.01 or inter.size.z < 0.01:
			return
		if not _axis_aligned(gx.basis):
			rep.skipped.append("%s: rotated box collider over the doorway" % cs.name)
			return
		var inv := (body as Node3D).global_transform.affine_inverse()
		for p in aabb_minus(wab, cut):
			var ncs := CollisionShape3D.new()
			var nb := BoxShape3D.new()
			nb.size = p.size
			ncs.shape = nb
			ncs.name = "%s_garderie_%d" % [cs.name, body.get_child_count()]
			for m in cs.get_meta_list():
				ncs.set_meta(m, cs.get_meta(m))
			body.add_child(ncs)
			ncs.transform = inv * Transform3D(Basis.IDENTITY, p.get_center())
		cs.disabled = true
		cs.set_meta("garderie_split", true)
		rep.shapes.append("%s/%s" % [body.name, cs.name])
	elif sh is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (sh as ConcavePolygonShape3D).get_faces()
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = faces
		var res: Variant = _clip_arrays(arr, gx, cut)
		if res == null:
			return
		var NV: PackedVector3Array = res[Mesh.ARRAY_VERTEX]
		var NI: PackedInt32Array = res[Mesh.ARRAY_INDEX]
		var nf := PackedVector3Array()
		for i in NI:
			nf.append(NV[i])
		var ns := ConcavePolygonShape3D.new()
		ns.backface_collision = (sh as ConcavePolygonShape3D).backface_collision
		ns.set_faces(nf)
		cs.shape = ns
		rep.shapes.append("%s/%s (trimesh)" % [body.name, cs.name])
	elif not (sh is WorldBoundaryShape3D):
		var dm := sh.get_debug_mesh()
		if dm != null and (gx * dm.get_aabb()).intersection(cut).has_volume():
			rep.skipped.append("%s: %s over the doorway left as is" % [cs.name, sh.get_class()])

# ---------------------------------------------------------------- occluders

static func _split_occluder(oi: OccluderInstance3D, cut: AABB, rep: Dictionary) -> void:
	var occ := oi.occluder
	if occ == null or not oi.is_inside_tree():
		return
	var gx := oi.global_transform
	if occ is BoxOccluder3D:
		var size: Vector3 = (occ as BoxOccluder3D).size
		var wab := gx * AABB(-size * 0.5, size)
		var inter := wab.intersection(cut)
		if inter.size.x < 0.01 or inter.size.y < 0.01 or inter.size.z < 0.01:
			return
		if not _axis_aligned(gx.basis):
			rep.skipped.append("%s: rotated box occluder over the doorway" % oi.name)
			return
		var parent := oi.get_parent() as Node3D
		var inv := parent.global_transform.affine_inverse() if parent != null else Transform3D.IDENTITY
		for p in aabb_minus(wab, cut):
			var n := OccluderInstance3D.new()
			var b := BoxOccluder3D.new()
			b.size = p.size
			n.occluder = b
			n.name = "%s_garderie" % oi.name
			oi.get_parent().add_child(n)
			n.transform = inv * Transform3D(Basis.IDENTITY, p.get_center())
		oi.occluder = null
		rep.occluders.append(String(oi.name))
	else:
		var verts: PackedVector3Array = occ.get_vertices()
		var idx: PackedInt32Array = occ.get_indices()
		if verts.is_empty():
			return
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_INDEX] = idx
		var res: Variant = _clip_arrays(arr, gx, cut)
		if res == null:
			return
		var ao := ArrayOccluder3D.new()
		ao.set_arrays(res[Mesh.ARRAY_VERTEX], res[Mesh.ARRAY_INDEX])
		oi.occluder = ao
		rep.occluders.append("%s (clipped)" % oi.name)
