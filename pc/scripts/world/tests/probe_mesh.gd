## Debug helper (world module): prints the horizontal extents of the downward-facing faces of a level.glb mesh at a
## given height band (used to find the nook joists / ceiling heights).
##   godot --headless --path pc -s res://scripts/world/tests/probe_mesh.gd -- --mesh=arch_nookWood --ymin=2.45 --ymax=2.55
extends SceneTree

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var ps := load("res://assets/generated/level.glb") as PackedScene
	var root := ps.instantiate()
	get_root().add_child(root)
	var mi := root.find_child(String(args.get("mesh", "arch_nookWood")), true, false) as MeshInstance3D
	if mi == null:
		print("mesh not found")
		quit()
		return true
	var ymin := float(args.get("ymin", "2.45"))
	var ymax := float(args.get("ymax", "2.55"))
	var faces := mi.mesh.get_faces()
	var xf := mi.global_transform
	var boxes: Array[AABB] = []
	for i in range(0, faces.size(), 3):
		var a: Vector3 = xf * faces[i]
		var b: Vector3 = xf * faces[i + 1]
		var c: Vector3 = xf * faces[i + 2]
		var n := (b - a).cross(c - a).normalized()
		if absf(n.y) < 0.9:
			continue
		if a.y < ymin or a.y > ymax:
			continue
		var bb := AABB(a, Vector3.ZERO).expand(b).expand(c)
		var merged := false
		for k in boxes.size():
			if boxes[k].grow(0.01).intersects(bb):
				boxes[k] = boxes[k].merge(bb)
				merged = true
				break
		if not merged:
			boxes.append(bb)
	for bb in boxes:
		print("y=%.3f x[%.3f, %.3f] z[%.3f, %.3f]" % [bb.position.y, bb.position.x, bb.end.x, bb.position.z, bb.end.z])
	quit()
	return true
