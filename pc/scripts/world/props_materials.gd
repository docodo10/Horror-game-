## Material pass (world module), after the exporter's overrides: what Godot needs that three.js did implicitly.
##  * Glass that the web left as the scans' atlas glass (round wall frame, cassette window, flashlight lens, the bare
##    bulb): thin clear glass (alpha, low roughness, no metalness from the opaque atlas) — reflections come from the probes.
##  * The bare bulb of the nook is dead ("L'ampoule est grillée"): its filament emission is switched off.
##  * Emissive / decal / glass level meshes listed in level.noReceiveShadow do not receive shadows.
##  * Moving parts (doors, drawers, lids, rocking chair) do not bake into SDFGI as static geometry (GI_MODE_DYNAMIC).
extends RefCounted

const THIN_GLASS := ["hanging_picture_frame_03_glass", "portable_cassette_player_glass", "pastic_torch_6v_glass", "lightbulb_01_glass"]

static func apply(ctx: Dictionary, handles: Dictionary) -> void:
	var instances: Dictionary = ctx.get("instances", {})
	for inst_name in instances:
		var inst = instances[inst_name]
		if not (inst is Node3D) or not is_instance_valid(inst): continue
		for mi in (inst as Node3D).find_children("*", "MeshInstance3D", true, false):
			_fix_mesh(mi as MeshInstance3D, String(inst_name))
	var lv: Dictionary = ctx.get("meta", {}).get("level", {})
	var nodes: Dictionary = ctx.get("level_nodes", {})
	for n in lv.get("noReceiveShadow", []):
		var mi = nodes.get(n)
		if mi is MeshInstance3D: _no_receive(mi as MeshInstance3D)
	for id in handles:
		var h = handles[id]
		var n = h.get(&"node") if h is Object else null
		if n is Node3D:
			for g in (n as Node3D).find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var rc = nodes.get("rockingChair_pivot")
	if rc is Node3D:
		for g in (rc as Node3D).find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC

static func _fix_mesh(mi: MeshInstance3D, inst_name: String) -> void:
	if mi.mesh == null: return
	for s in mi.mesh.get_surface_count():
		if mi.get_surface_override_material(s) != null: continue     # exporter override (photo frame / clock glass…)
		var base := mi.mesh.surface_get_material(s)
		if not (base is BaseMaterial3D): continue
		var mname := base.resource_name
		if THIN_GLASS.has(mname):
			var g := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.albedo_texture = null                 # the scans' atlas glass is whitish: milky veil over the picture
			g.metallic = 0.0
			g.metallic_texture = null
			g.roughness = 0.05
			g.roughness_texture = null
			g.metallic_specular = 0.6
			g.albedo_color = Color(1, 1, 1, 0.14 if mname == "lightbulb_01_glass" else 0.08)
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			g.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			mi.set_surface_override_material(s, g)
		elif inst_name == "bulb" and (base as BaseMaterial3D).emission_enabled:
			var d := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			d.emission_enabled = false
			mi.set_surface_override_material(s, d)

static func _no_receive(mi: MeshInstance3D) -> void:
	if mi.mesh == null: return
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m is BaseMaterial3D and not (m as BaseMaterial3D).disable_receive_shadows:
			var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			d.disable_receive_shadows = true
			mi.set_surface_override_material(s, d)
