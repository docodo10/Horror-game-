## Surfaces module — headless self-test (no renderer needed):
##   godot --headless --path pc -s res://scripts/surfaces/tests/surfaces_check.gd
## Assembles the REAL level (MetaUtil.assemble), applies every preset twice (idempotency, timing), checks that every
## required role got a hi-res material, that low restores the exporter materials / web overlays and hides the decals,
## that a re-exported nook (concrete albedo) picks the concrete recipe, that unknown / null inputs only warn.
## Prints "SURFACES CHECK OK" (exit 0) or the failures (exit 1).
extends SceneTree

const MetaUtil := preload("res://assets/generated/meta_util.gd")
const SurfacesScript := preload("res://scripts/surfaces/surfaces.gd")

var _fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)
		printerr("FAIL: ", msg)

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "World"
	get_root().add_child(root)
	var meta := MetaUtil.load_json("res://assets/generated/level_meta.json")
	var ctx := MetaUtil.assemble(root, meta)
	_check(ctx.errors.is_empty(), "assemble errors: %s" % [ctx.errors])
	var wall := root.find_child("arch_wall", true, false) as MeshInstance3D
	_check(wall != null, "arch_wall exists")
	var orig_mat: Material = wall.get_active_material(0) if wall else null

	for q in ["high", "high", "medium", "ultra", "low", "medium", "low"]:
		SurfacesScript.apply(root, q)
		var st: Dictionary = SurfacesScript.stats
		print("[surfaces] %-6s %6.1f ms  materials %d  models %d  roles %d  decals %d  hidden %s  kept %s  missing %s" % [
			q, st.ms, st.materials, st.get("models", 0), st.roles.size(), st.decals, st.hidden, st.kept, st.missing])
		_check(float(st.ms) < 1000.0, "%s apply < 1 s (%.1f ms)" % [q, st.ms])
		var holder := root.get_node_or_null("SurfacesDecals") as Node3D
		if q == "low":
			_check(wall == null or wall.get_active_material(0) == orig_mat, "low restores the exporter material")
			_check(holder == null or not holder.visible, "low hides the decals")
			for n in ["decal", "architecture_mesh"]:
				var hn := root.find_child(n, true, false) as Node3D
				_check(hn == null or hn.visible, "low shows the web overlay %s again" % n)
		else:
			_check(st.missing.is_empty(), "%s: all required roles found (missing %s)" % [q, st.missing])
			_check(wall != null and wall.get_active_material(0) is ShaderMaterial, "%s: arch_wall uses the wall shader" % q)
			_check(holder != null and holder.get_child_count() >= 60, "%s: decals built (%d)" % [q, holder.get_child_count() if holder else 0])
			_check(int(st.decals) > 0 and (q != "medium" or int(st.decals) < holder.get_child_count()), "%s: decal tiers" % q)
			_check(st.hidden.has("decal") and st.hidden.has("architecture_mesh"), "%s: web decal quads hidden" % q)
			_check(int(st.get("models", 0)) >= 12, "%s: hero furniture got its 2K maps (%d surfaces)" % [q, st.get("models", 0)])
	# idempotency: one decal holder, no duplicate children after many applies
	_check(root.find_children("SurfacesDecals", "", true, false).size() == 1, "single decal holder")

	# re-exported nook (web Details pass): concrete albedo -> concrete recipe; unknown node by material name
	var nook := MeshInstance3D.new()
	nook.name = "arch_nookBlock_2"
	var bm := BoxMesh.new()
	var sm := StandardMaterial3D.new()
	sm.resource_name = "nookBlock"
	sm.albedo_texture = load("res://assets/textures/concrete_wall_007/color.jpg") as Texture2D
	bm.material = sm
	nook.mesh = bm
	var test_root := Node3D.new()
	root.add_child(test_root)
	test_root.add_child(nook)
	SurfacesScript.apply(test_root, "high")
	var nm := nook.get_active_material(0)
	_check(nm is ShaderMaterial and String(nm.resource_name) == "surfaces_nook_concrete", "concrete nook variant (%s)" % [nm.resource_name if nm else "null"])
	# bad inputs only warn
	SurfacesScript.apply(null, "high")
	SurfacesScript.apply(test_root, "potato")
	SurfacesScript.restore(test_root)
	_check(nook.get_active_material(0) == sm, "restore() puts the original back")

	if _fails.is_empty():
		print("SURFACES CHECK OK")
		quit(0)
	else:
		print("SURFACES CHECK FAILED (%d)" % _fails.size())
		quit(1)
