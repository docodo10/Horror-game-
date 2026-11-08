## Exporter self-test (headless):  godot --headless --path pc -s res://assets/generated/_check.gd
## Assembles level.glb + every model instance from level_meta.json with meta_util.gd, resolves every reference
## of the meta (handles, items, clues, TV, decals, proxies, runtime helpers), checks that the closed handle
## transforms match the assembled scene, then loads gardienne.glb and lists its skeleton and animations.
## Prints "EXPORT CHECK OK" (exit 0) or the problems (exit 1).
extends SceneTree

const MetaUtil := preload("res://assets/generated/meta_util.gd")
const GEN := "res://assets/generated/"

var problems: Array[String] = []

var _root: Node3D
var _done := false

func _initialize() -> void:
	_root = Node3D.new()
	_root.name = "ExportCheck"
	get_root().add_child(_root)

func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	_run(_root)
	return false

var _level_done := false
var _gardienne_done := false

func _run(root: Node3D) -> void:
	_check_level(root)
	if not _level_done:
		problems.append("level check aborted (script error above)")
	_check_gardienne(root)
	if not _gardienne_done:
		problems.append("gardienne check aborted (script error above)")
	if problems.is_empty():
		print("EXPORT CHECK OK")
	else:
		for p in problems:
			printerr("PROBLEM: ", p)
		print("EXPORT CHECK FAILED (%d problems)" % problems.size())
	quit(0 if problems.is_empty() else 1)

func _count(n: Node, types: Dictionary) -> void:
	types[n.get_class()] = int(types.get(n.get_class(), 0)) + 1
	for c in n.get_children():
		_count(c, types)

func _check_level(root: Node3D) -> void:
	var meta := MetaUtil.load_json(GEN + "level_meta.json")
	if meta.is_empty():
		problems.append("level_meta.json missing/invalid")
		return
	var t0 := Time.get_ticks_msec()
	var ctx := MetaUtil.assemble(root, meta)
	for e in ctx.errors:
		problems.append("assemble: " + String(e))
	if ctx.level == null:
		return
	var types := {}
	_count(ctx.level, types)
	var surfaces := 0
	for mi in ctx.level.find_children("*", "MeshInstance3D", true, false):
		surfaces += (mi as MeshInstance3D).mesh.get_surface_count() if (mi as MeshInstance3D).mesh else 0
	print("level.glb: %d nodes (%d MeshInstance3D, %d surfaces), %d named level nodes, assembled in %d ms" % [
		types.values().reduce(func(a, b): return a + b, 0), int(types.get("MeshInstance3D", 0)), surfaces, ctx.level_nodes.size(), Time.get_ticks_msec() - t0])
	print("instances: %d placed, attachments: %d, reparent: %d" % [ctx.instances.size(), meta.get("attachments", []).size(), meta.get("reparent", []).size()])
	if ctx.shadow_casters:
		print("shadow casters: %d meshes" % ctx.shadow_casters.find_children("*", "MeshInstance3D", true, false).size())
	for n in meta.level.get("roots", []):
		if not ctx.level_nodes.has(n):
			problems.append("level root not found in level.glb: " + String(n))
	# handles
	var hcount := 0
	for id in meta.get("handles", {}):
		var h: Dictionary = meta.handles[id]
		hcount += 1
		if MetaUtil.find(ctx, h.get("object")) == null:
			problems.append("handle %s: object %s" % [id, h.get("object")])
		if h.get("contents") != null and MetaUtil.find(ctx, h.contents) == null:
			problems.append("handle %s: contents %s" % [id, h.contents])
		var moving: Array = h.get("moving", [])
		if moving.is_empty():
			problems.append("handle %s: no moving node" % id)
		for mv in moving:
			var node := MetaUtil.find(ctx, mv.ref)
			if node == null:
				problems.append("handle %s: moving node %s" % [id, mv.ref])
				continue
			var want := MetaUtil.mat16(mv.open if h.get("initiallyOpen", false) else mv.closed)
			var d := (node.transform.origin - want.origin).length() + (node.transform.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()))
			if d > 0.002:
				problems.append("handle %s: node %s rest transform differs from the exported %s state (%.4f)" % [id, mv.ref, "open" if h.get("initiallyOpen", false) else "closed", d])
	print("handles: %d" % hcount)
	# items / clues / tv / decals / proxies / helpers
	for id in meta.get("items", {}):
		var it: Dictionary = meta.items[id]
		var n := MetaUtil.find(ctx, it.ref)
		if n == null:
			problems.append("item %s: %s" % [id, it.ref])
			continue
		if it.get("inside") != null:
			var c := MetaUtil.find(ctx, meta.handles[it.inside].get("contents"))
			if c == null or not c.is_ancestor_of(n):
				problems.append("item %s is not inside the contents of %s" % [id, it.inside])
		var dg := (n.global_transform.origin - MetaUtil.mat16(it.transform).origin).length()
		if dg > 0.002:
			problems.append("item %s world position off by %.4f m" % [id, dg])
	for k in meta.get("clues", {}):
		if MetaUtil.find(ctx, meta.clues[k]) == null:
			problems.append("clue %s: %s" % [k, meta.clues[k]])
	if meta.get("tv") != null:
		for k in ["object", "screen"]:
			if MetaUtil.find(ctx, meta.tv.get(k)) == null:
				problems.append("tv.%s: %s" % [k, meta.tv.get(k)])
	for k in meta.get("clueDecals", {}):
		if MetaUtil.find(ctx, meta.clueDecals[k].parent) == null:
			problems.append("clue decal %s parent: %s" % [k, meta.clueDecals[k].parent])
	var pbad := 0
	for p in meta.get("proxies", []):
		if p.get("parent") != null and MetaUtil.find(ctx, p.parent) == null:
			pbad += 1
	if pbad:
		problems.append("%d proxies with unresolved parents" % pbad)
	for k in meta.get("anim", {}):
		_check_refs_in("anim." + k, meta.anim[k], ctx)
	# world-space spot checks: every instance where the meta says it is
	var worst := 0.0
	var worst_name := ""
	for im in meta.get("instances", []):
		var inst: Node3D = ctx.instances.get(im.name)
		if inst == null:
			continue
		var d := (inst.global_transform.origin - MetaUtil.mat16(im.transform).origin).length()
		if d > worst:
			worst = d
			worst_name = im.name
	print("instances: worst world position error %.6f m (%s)" % [worst, worst_name])
	if worst > 0.001:
		problems.append("instance %s placed %.4f m away from its exported transform" % [worst_name, worst])
	_level_done = true
	print("lights (reference): %d, colliders: %d, occluders: %d, proxies: %d, warnings in meta: %d" % [
		meta.get("lights", []).size(), meta.get("colliders", []).size(), meta.get("occluders", []).size(), meta.get("proxies", []).size(), meta.get("warnings", []).size()])

func _check_refs_in(label: String, v: Variant, ctx: Dictionary) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("level") or (d.has("instance") and d.size() <= 3 and (d.has("node") or d.size() == 1)):
			if MetaUtil.find(ctx, d) == null:
				problems.append("%s: unresolved %s" % [label, d])
			return
		for k in d:
			_check_refs_in(label + "." + String(k), d[k], ctx)
	elif v is Array:
		for i in (v as Array).size():
			_check_refs_in("%s[%d]" % [label, i], v[i], ctx)

func _check_gardienne(root: Node3D) -> void:
	var gm := MetaUtil.load_json(GEN + "gardienne_meta.json")
	var ps := load(GEN + "gardienne.glb") as PackedScene
	if ps == null:
		problems.append("gardienne.glb does not load")
		return
	var g := ps.instantiate() as Node3D
	root.add_child(g)
	var skels := g.find_children("*", "Skeleton3D", true, false)
	var meshes := g.find_children("*", "MeshInstance3D", true, false)
	var players := g.find_children("*", "AnimationPlayer", true, false)
	if skels.size() != 1:
		problems.append("gardienne: %d Skeleton3D (expected 1)" % skels.size())
	var sk: Skeleton3D = null
	if skels.size() > 0:
		sk = skels[0] as Skeleton3D
	var mesh_names := PackedStringArray()
	for m in meshes:
		mesh_names.append(String(m.name))
	print("gardienne.glb: skeleton bones %d, meshes %d (%s)" % [sk.get_bone_count() if sk else 0, meshes.size(), ", ".join(mesh_names)])
	if sk and gm.has("boneCount") and sk.get_bone_count() != int(gm.boneCount):
		problems.append("gardienne: %d bones, meta says %d" % [sk.get_bone_count(), gm.boneCount])
	if players.is_empty():
		problems.append("gardienne: no AnimationPlayer")
		return
	var ap := players[0] as AnimationPlayer
	var names := ap.get_animation_list()
	var lines := PackedStringArray()
	for n in names:
		var a := ap.get_animation(n)
		lines.append("%s %.2fs loop=%d tracks=%d" % [n, a.length, a.loop_mode, a.get_track_count()])
	print("animations: ", " | ".join(lines))
	for c in gm.get("clips", {}):
		if not ap.has_animation(c):
			problems.append("gardienne: animation %s missing" % c)
			continue
		var a := ap.get_animation(c)
		var want_loop: bool = gm.clips[c].loop
		if (a.loop_mode != Animation.LOOP_NONE) != want_loop:
			problems.append("gardienne: %s loop_mode %d (expected loop=%s)" % [c, a.loop_mode, want_loop])
		if absf(a.length - float(gm.clips[c].duration)) > 0.04:
			problems.append("gardienne: %s length %.3f (meta %.3f)" % [c, a.length, gm.clips[c].duration])
	_gardienne_done = true
