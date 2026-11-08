## Debug helper (world module): assembles level.glb + the model instances with the exporter's MetaUtil and prints the
## node tree (world positions, mesh AABBs, material names). Usage:
##   godot --headless --path pc -s res://scripts/world/tests/dump_level.gd [-- --instances]
extends SceneTree

const MetaUtil := preload("res://assets/generated/meta_util.gd")

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var root := Node3D.new()
	get_root().add_child(root)
	var meta := MetaUtil.load_json("res://assets/generated/level_meta.json")
	var ctx := MetaUtil.assemble(root, meta)
	if "--instances" in OS.get_cmdline_user_args():
		for k in ctx.instances:
			_dump(ctx.instances[k], 0)
	else:
		_dump(ctx.level, 0)
	quit()
	return true

func _dump(n: Node, d: int) -> void:
	var s := "  ".repeat(d) + String(n.name) + " [" + n.get_class() + "]"
	if n is Node3D:
		var t := (n as Node3D).global_transform
		s += " pos=(%.3f,%.3f,%.3f)" % [t.origin.x, t.origin.y, t.origin.z]
		if not (n as Node3D).visible:
			s += " HIDDEN"
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var a := mi.global_transform * mi.get_aabb()
		s += " aabb=(%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)" % [a.position.x, a.position.y, a.position.z, a.end.x, a.end.y, a.end.z]
		if mi.mesh:
			var mats := []
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				if m:
					var info := m.resource_name
					if m is BaseMaterial3D:
						var bm := m as BaseMaterial3D
						info += "{tr=%d,met=%.2f,rough=%.2f,em=%s}" % [bm.transparency, bm.metallic, bm.roughness, str(bm.emission_enabled)]
					mats.append(info)
			s += " mats=" + str(mats)
	print(s)
	for c in n.get_children():
		_dump(c, d + 1)
