## Helpers for the exporter outputs (level_meta.json / gardienne_meta.json). Owned by the exporter module
## (tools/export-godot.cjs). Optional reference implementation: the world module may use it as is
## (`const MetaUtil := preload("res://assets/generated/meta_util.gd")`) or copy what it needs.
##
##   MetaUtil.mat16(a) -> Transform3D                     column-major 16 floats (three.js Matrix4.elements)
##   MetaUtil.load_json(path) -> Dictionary
##   MetaUtil.assemble(parent, meta, opts) -> Dictionary  level.glb + every model instance placed/patched like the web
##        build; returns ctx = { level: Node3D, instances: {name: Node3D}, level_nodes: {name: Node3D},
##        shadow_casters: Node3D|null, errors: Array[String] }
##        opts: { "shadow_casters": true, "hints": true }
##   MetaUtil.find(ctx, ref) -> Node3D                    resolves {level} | {instance} | {instance, node[, surface]}
##   MetaUtil.make_handle_xforms(ctx, handle_meta) -> Dictionary  { node, closed: Transform3D, open: Transform3D }
##   MetaUtil.apply_material_override(mi, surface, set)   duplicates the surface material and applies the web overrides
extends RefCounted

static func mat16(a: Array) -> Transform3D:
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[4], a[5], a[6]), Vector3(a[8], a[9], a[10])),
		Vector3(a[12], a[13], a[14]))

static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("meta_util: cannot open %s" % path)
		return {}
	var v: Variant = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func _index_names(root: Node, out: Dictionary) -> void:
	for c in root.get_children():
		if not out.has(c.name):
			out[String(c.name)] = c
		_index_names(c, out)

static func find(ctx: Dictionary, ref: Variant) -> Node3D:
	if not (ref is Dictionary):
		return null
	var r: Dictionary = ref
	if r.has("level"):
		return ctx.level_nodes.get(r.level) as Node3D
	if r.has("instance"):
		var inst: Node3D = ctx.instances.get(r.instance)
		if inst == null:
			return null
		if r.has("node"):
			return inst.get_node_or_null(NodePath(String(r.node))) as Node3D
		return inst
	return null

static func assemble(parent: Node3D, meta: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var ctx := {"level": null, "instances": {}, "level_nodes": {}, "shadow_casters": null, "errors": []}
	var errors: Array = ctx.errors
	# 1. level.glb
	var ps := load(String(meta.files.level)) as PackedScene
	if ps == null:
		errors.append("cannot load %s" % meta.files.level)
		return ctx
	var level := ps.instantiate() as Node3D
	level.name = "GeneratedLevel"
	parent.add_child(level)
	ctx.level = level
	_index_names(level, ctx.level_nodes)
	var lv: Dictionary = meta.get("level", {})
	for n in lv.get("hidden", []):
		var h: Node3D = ctx.level_nodes.get(n)
		if h: h.visible = false
	for n in lv.get("noCastShadow", []):
		var g := ctx.level_nodes.get(n) as GeometryInstance3D
		if g: g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if opts.get("hints", true):
		for hint in lv.get("materialHints", []):
			_apply_hint(ctx.level_nodes.get(hint.node) as MeshInstance3D, hint)
	# 2. shadow-only geometry
	if opts.get("shadow_casters", true) and meta.files.get("shadowCasters"):
		var sc := load(String(meta.files.shadowCasters)) as PackedScene
		if sc:
			var casters := sc.instantiate() as Node3D
			casters.name = "ShadowCasters"
			parent.add_child(casters)
			for m in casters.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			ctx.shadow_casters = casters
	# 3. model instances (placed at their world transform first; parents are fixed in step 6)
	for im in meta.get("instances", []):
		var ips := load(String(im.scene)) as PackedScene
		if ips == null:
			errors.append("missing model %s" % im.scene)
			continue
		var inst := ips.instantiate() as Node3D
		inst.name = String(im.name)
		parent.add_child(inst)
		inst.global_transform = parent.global_transform * mat16(im.transform)
		ctx.instances[im.name] = inst
		if im.get("visible", true) == false:
			inst.visible = false
		for path in im.get("hiddenNodes", []):
			var hn := inst.get_node_or_null(NodePath(String(path)))
			if hn == null:
				errors.append("%s: hidden node not found: %s" % [im.name, path])
				continue
			hn.get_parent().remove_child(hn)
			hn.queue_free()
		for t in im.get("nodeTransforms", []):
			var tn := inst.get_node_or_null(NodePath(String(t.node))) as Node3D
			if tn: tn.transform = mat16(t.local)
			else: errors.append("%s: node not found: %s" % [im.name, t.node])
		for mo in im.get("materialOverrides", []):
			var mi := inst.get_node_or_null(NodePath(String(mo.node))) as MeshInstance3D
			if mi == null:
				errors.append("%s: override node not found: %s" % [im.name, mo.node])
				continue
			apply_material_override(mi, int(mo.surface), mo.set)
		if im.get("castShadow", true) == false:
			for g in inst.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for path in im.get("noCastShadow", []):
			var g := inst.get_node_or_null(NodePath(String(path))) as GeometryInstance3D
			if g: g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 4. procedural level nodes that live inside a model instance (drawer contents, lever, lid pivot, decals...)
	for a in meta.get("attachments", []):
		var node: Node3D = ctx.level_nodes.get(a.level)
		var p := find(ctx, a.parent)
		if node == null or p == null:
			errors.append("attachment %s -> %s unresolved" % [a.level, a.parent])
			continue
		node.reparent(p, false)
		node.transform = mat16(a.local)
	# 5. original model nodes moved under procedural nodes (lid -> hinge pivot, pull chain -> swing pivot)
	for r in meta.get("reparent", []):
		var n := find(ctx, {"instance": r.instance, "node": r.node})
		var p := find(ctx, r.parent)
		if n == null or p == null:
			errors.append("reparent %s/%s -> %s unresolved" % [r.instance, r.node, r.parent])
			continue
		n.reparent(p, false)
		n.transform = mat16(r.local)
	# 6. instances parented to moving / procedural nodes (flashlight in its drawer, rocking chair pivot)
	for im in meta.get("instances", []):
		if im.get("parent") == null:
			continue
		var inst: Node3D = ctx.instances.get(im.name)
		var p := find(ctx, im.parent)
		if inst == null or p == null:
			errors.append("instance %s parent %s unresolved" % [im.name, im.parent])
			continue
		inst.reparent(p, false)
		inst.transform = mat16(im.local)
	return ctx

static func make_handle_xforms(ctx: Dictionary, h: Dictionary) -> Dictionary:
	var moving: Array = h.get("moving", [])
	if moving.is_empty():
		return {}
	var i := int(h.get("primary", 0))
	var mv: Dictionary = moving[clampi(i, 0, moving.size() - 1)]
	return {"node": find(ctx, mv.ref), "closed": mat16(mv.closed), "open": mat16(mv.open)}

static func _base_mat(mi: MeshInstance3D, surface: int) -> BaseMaterial3D:
	var cur := mi.get_surface_override_material(surface)
	if cur == null and mi.mesh and surface < mi.mesh.get_surface_count():
		cur = mi.mesh.surface_get_material(surface)
	if cur is BaseMaterial3D:
		return (cur as BaseMaterial3D).duplicate() as BaseMaterial3D
	return StandardMaterial3D.new()

static func apply_material_override(mi: MeshInstance3D, surface: int, s: Dictionary) -> void:
	var m := _base_mat(mi, surface)
	if s.has("albedo"):
		var c := Color.html(String(s.albedo.srgb))
		c.a = float(s.albedo.get("alpha", 1.0))
		m.albedo_color = c
		if c.a < 0.999:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if s.has("roughness"): m.roughness = float(s.roughness)
	if s.has("metalness"): m.metallic = float(s.metalness)
	if s.has("transparent"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if s.transparent else BaseMaterial3D.TRANSPARENCY_DISABLED
	if s.has("alphaTest") and float(s.alphaTest) > 0.0 and not s.get("transparent", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = float(s.alphaTest)
	if s.get("alphaToCoverage", false):
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	if s.has("doubleSided"):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED if s.doubleSided else BaseMaterial3D.CULL_BACK
	if s.has("depthWrite") and s.depthWrite == false:
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if s.get("blending", "") == "additive":
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if s.has("emissive"):
		m.emission_enabled = true
		m.emission = Color.html(String(s.emissive.srgb))
	if s.has("emissiveIntensity"): m.emission_energy_multiplier = float(s.emissiveIntensity)
	if s.has("clearcoat"):
		m.clearcoat_enabled = float(s.clearcoat) > 0.0
		m.clearcoat = float(s.clearcoat)
	if s.has("clearcoatRoughness"): m.clearcoat_roughness = float(s.clearcoatRoughness)
	if s.has("vertexColors"): m.vertex_color_use_as_albedo = bool(s.vertexColors)
	var tex: Dictionary = s.get("textures", {})
	var slots := {
		"albedo_texture": BaseMaterial3D.TEXTURE_ALBEDO, "normal_texture": BaseMaterial3D.TEXTURE_NORMAL,
		"roughness_texture": BaseMaterial3D.TEXTURE_ROUGHNESS, "metallic_texture": BaseMaterial3D.TEXTURE_METALLIC,
		"ao_texture": BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, "emission_texture": BaseMaterial3D.TEXTURE_EMISSION,
	}
	for k in tex:
		if not slots.has(k):
			continue
		var t: Variant = tex[k]
		if t == null:
			m.set_texture(slots[k], null)
			if k == "normal_texture": m.normal_enabled = false
			if k == "ao_texture": m.ao_enabled = false
			continue
		var tx := load(String(t.path)) as Texture2D
		m.set_texture(slots[k], tx)
		if k == "normal_texture": m.normal_enabled = true
		if k == "ao_texture": m.ao_enabled = true
		if k == "emission_texture": m.emission_enabled = true
		if k == "albedo_texture":
			m.uv1_scale = Vector3(t.uv1_scale[0], t.uv1_scale[1], 1.0)
			m.uv1_offset = Vector3(t.uv1_offset[0], t.uv1_offset[1], 0.0)
	mi.set_surface_override_material(surface, m)

## three.js-only material flags carried as hints (level.materialHints): additive blending, no depth write,
## decal polygon offset (-> render priority), double sided...
static func _apply_hint(mi: MeshInstance3D, hint: Dictionary) -> void:
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if m == null:
			continue
		if hint.get("blending", "") == "additive":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		if hint.has("depthWrite") and hint.depthWrite == false:
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		if hint.has("polygonOffset"):
			m.render_priority = clampi(int(-float(hint.polygonOffset[0])), 1, 8)
		if hint.has("renderOrder"):
			mi.sorting_offset = float(hint.renderOrder) * 0.01
