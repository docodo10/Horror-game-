## Level loader (world module). Reads res://assets/generated/level_meta.json (written by tools/export-godot.cjs from the web
## build), preloads level.glb, the shadow casters, every ORIGINAL res://assets/models/*.glb used by `instances[]` and the
## textures of the material overrides on worker threads (the loading bar keeps moving), then assembles the level exactly
## like the web build with the exporter's MetaUtil: level.glb nodes, model instances at their exact world matrices, hidden
## nodes, node transforms, material overrides, attachments, reparents, instance parents.
## Without the exporter outputs it builds a fallback level from Layout (props_fallback_level.gd) that exposes the same ctx
## and a synthetic meta, so the rest of the world module runs unchanged.
##
## Usage: var ctx: Dictionary = await LevelLoader.new().load_level(world, parent, progress)
##   ctx = {meta, level, instances {name: Node3D}, level_nodes {name: Node3D}, shadow_casters, errors, generated: bool}
##   LevelLoader.find(ctx, ref) -> Node3D   resolves {level} | {instance} | {instance, node} refs (MetaUtil semantics)
##   LevelLoader.mat16(a) -> Transform3D    column-major 16 floats (three.js Matrix4.elements)
extends RefCounted

const META_PATH := "res://assets/generated/level_meta.json"
const META_UTIL_PATH := "res://assets/generated/meta_util.gd"
const LEVEL_PATH := "res://assets/generated/level.glb"
const FallbackLevel := preload("res://scripts/world/props_fallback_level.gd")

var _keep: Array = []     # resources loaded on threads stay cached while referenced (until the level is assembled)

static func has_generated() -> bool:
	return FileAccess.file_exists(META_PATH) and ResourceLoader.exists(META_UTIL_PATH) and ResourceLoader.exists(LEVEL_PATH)

static func mat16(a: Array) -> Transform3D:
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[4], a[5], a[6]), Vector3(a[8], a[9], a[10])),
		Vector3(a[12], a[13], a[14]))

static func find(ctx: Dictionary, ref: Variant) -> Node3D:
	if not (ref is Dictionary): return null
	var r: Dictionary = ref
	if r.has("level"):
		var n = ctx.get("level_nodes", {}).get(String(r.level))
		return n as Node3D if n is Node3D and is_instance_valid(n) else null
	if r.has("instance"):
		var inst = ctx.get("instances", {}).get(String(r.instance))
		if not (inst is Node3D) or not is_instance_valid(inst): return null
		if r.has("node"): return (inst as Node3D).get_node_or_null(NodePath(String(r.node))) as Node3D
		return inst as Node3D
	return null

func load_level(host: Node, parent: Node3D, progress: Callable) -> Dictionary:
	if has_generated() and not "--world-fallback" in OS.get_cmdline_user_args():
		var ctx := await _load_generated(host, parent, progress)
		if ctx.get("level") != null: return ctx
		push_warning("[world] exporter outputs unusable (%s): fallback level from Layout" % str(ctx.get("errors", [])))
		for c in parent.get_children(): c.queue_free()
	else:
		push_warning("[world] %s: fallback level built from Layout" % ("--world-fallback" if has_generated() else "res://assets/generated/ missing"))
	return await FallbackLevel.new().build(host, parent, progress)

func _load_generated(host: Node, parent: Node3D, progress: Callable) -> Dictionary:
	var mu = load(META_UTIL_PATH)
	var meta: Dictionary = mu.load_json(META_PATH)
	if meta.is_empty() or not meta.has("files"):
		return {"level": null, "errors": ["level_meta.json invalid"]}
	var paths: Array[String] = [String(meta.files.level)]
	if meta.files.get("shadowCasters"): paths.append(String(meta.files.shadowCasters))
	for im in meta.get("instances", []):
		paths.append(String(im.scene))
		for mo in im.get("materialOverrides", []):
			var tex: Dictionary = mo.get("set", {}).get("textures", {})
			for k in tex:
				if tex[k] is Dictionary and tex[k].has("path"): paths.append(String(tex[k].path))
	await _preload(host, paths, progress, 0.0, 0.88, "Chargement du sous-sol…")
	progress.call(0.9, "Assemblage du sous-sol…")
	await host.get_tree().process_frame
	var ctx: Dictionary = mu.assemble(parent, meta, {"shadow_casters": true, "hints": true})
	_keep.clear()
	ctx["meta"] = meta
	ctx["generated"] = true
	for e in ctx.get("errors", []):
		push_warning("[world] assemble: " + String(e))
	progress.call(1.0, "Assemblage du sous-sol…")
	return ctx

## Threaded preload of every path (dependencies included), reporting progress between p0 and p1. Headless (dummy
## renderer, whose texture storage is not thread-safe): plain loads, one per frame.
func _preload(host: Node, paths: Array[String], progress: Callable, p0: float, p1: float, text: String) -> void:
	if DisplayServer.get_name() == "headless":
		var todo: Array[String] = []
		for s in paths:
			if s != "" and not todo.has(s) and not ResourceLoader.has_cached(s) and ResourceLoader.exists(s): todo.append(s)
		for i in todo.size():
			_keep.append(load(todo[i]))
			progress.call(lerpf(p0, p1, float(i + 1) / maxf(1.0, todo.size())), text)
			if i % 8 == 7: await host.get_tree().process_frame
		return
	var pending: Array[String] = []
	for s in paths:
		if s == "" or pending.has(s) or ResourceLoader.has_cached(s) or not ResourceLoader.exists(s): continue
		if ResourceLoader.load_threaded_request(s, "", true) == OK: pending.append(s)
	var total := float(maxi(1, pending.size()))
	var t0 := Time.get_ticks_msec()
	var status := []
	while not pending.is_empty():
		var partial := 0.0
		for s in pending.duplicate():
			status.clear()
			var st := ResourceLoader.load_threaded_get_status(s, status)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				_keep.append(ResourceLoader.load_threaded_get(s))
				pending.erase(s)
			elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				partial += float(status[0]) if not status.is_empty() else 0.0
			else:
				push_warning("[world] threaded load failed: " + s)
				pending.erase(s)
		progress.call(lerpf(p0, p1, (total - pending.size() + partial) / total), text)
		if pending.is_empty() or Time.get_ticks_msec() - t0 > 180000: break
		await host.get_tree().process_frame
