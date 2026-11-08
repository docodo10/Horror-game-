## Surfaces module (ARCHITECTURE_PC.md §7, owner: surfaces) — photographic surface pass for the basement level.
## Replaces the web-optimised 1K materials of the architecture (walls, ceilings, carpet, trims, stairs, laundry nook,
## closet, upper hall) with world-space hi-res PBR shaders (res://shaders/surface_*.gdshader, 2K maps in
## res://assets/hires/) that layer non-repeating wear — macro colour / roughness variation, grime over the floor line and
## under the ceiling, dirt in corners, rubber scuffs, hand smudges, specks and scratches, water run-down, damp /
## efflorescence / mould, traffic paths, worn stair treads, chipped paint, drywall joints — and replaces the web build's
## decal quads with hi-res Godot Decal nodes (+ a few storytelling stains). Inventory / recipes: scripts/surfaces/README.md.
##
## API
##   Surfaces.apply(level_root: Node3D, quality: String) -> void
##       level_root = any ancestor of the assembled level (the World node or GeneratedLevel); quality low|medium|high|ultra.
##       Meshes are matched by ROLE (recipes.gd): node name first ("arch_wall"...), glTF material name as a fallback,
##       and the variant from the original albedo map (re-exported nook = concrete, hall ceiling = crackled plaster).
##       Idempotent and fast (materials / textures / decals cached; the first call loads the textures ≈ 0.2 s, later
##       calls re-assign overrides and toggle visibility), never fails on a missing node (one warning per missing role).
##       low: the original exporter materials (restored if a higher preset was applied before), no Godot decals, the
##       web decal / overlay meshes visible; medium: hi-res shaders without the costliest normal layers + tier-1
##       decals; high / ultra: everything. Web overlay meshes covered by the module (Recipes.HIDE_NODES / HIDE_MATERIALS)
##       are hidden on medium+.
##   Surfaces.restore(level_root: Node3D) -> void   original materials, web overlays back, decals removed
##   Surfaces.hidden_web_overlays() -> Dictionary   {nodes, materials} hidden on medium+ (to check a re-export)
##   Surfaces.stats: Dictionary                     last apply(): {quality, ms, materials, roles: {role: [nodes]},
##                                                  kept: [nodes], missing: [roles], hidden: [nodes], decals}
class_name Surfaces
extends RefCounted

const Recipes := preload("res://scripts/surfaces/recipes.gd")
const DecalTable := preload("res://scripts/surfaces/decal_table.gd")

const HIRES := "res://assets/hires/"
const SHADERS := {
	"wall": "res://shaders/surface_wall.gdshader",
	"ceiling": "res://shaders/surface_ceiling.gdshader",
	"carpet": "res://shaders/surface_carpet.gdshader",
	"trim": "res://shaders/surface_trim.gdshader",
}
const META_ORIG := &"_surfaces_orig"
const META_HIDDEN := &"_surfaces_hidden"
const DECALS_NODE := "SurfacesDecals"
const QUALITY_TIER := {"low": 0, "medium": 1, "high": 2, "ultra": 3}

static var stats: Dictionary = {}
static var _materials: Dictionary = {}      # recipe key -> ShaderMaterial
static var _textures: Dictionary = {}       # path -> Texture2D (null cached too)
static var _shaders: Dictionary = {}
static var _warned: Dictionary = {}

# ---------------------------------------------------------------------------------------------------- public API
static func apply(level_root: Node3D, quality: String) -> void:
	var t0 := Time.get_ticks_usec()
	if level_root == null or not is_instance_valid(level_root):
		_warn_once("root", "Surfaces.apply: level_root is null")
		return
	var q := quality.to_lower()
	if not QUALITY_TIER.has(q):
		_warn_once("q_" + q, "Surfaces.apply: unknown quality '%s', using high" % quality)
		q = "high"
	var tier: int = QUALITY_TIER[q]
	var meshes: Array = level_root.find_children("*", "MeshInstance3D", true, false)
	var roles := {}
	var kept: Array[String] = []
	var hidden: Array[String] = []
	var n_mat := 0
	var n_models := 0
	if tier == 0:
		_restore_all(meshes)
	else:
		var detail := 1.0 if tier >= 2 else 0.0
		for node in meshes:
			var mi := node as MeshInstance3D
			if mi.mesh == null or mi.mesh.get_surface_count() == 0:
				continue
			if _is_web_overlay(mi):
				if not mi.has_meta(META_HIDDEN):
					mi.set_meta(META_HIDDEN, mi.visible)
					mi.visible = false
				hidden.append(String(mi.name))
				continue
			var role := _role_of(mi)
			if role == "":
				n_models += _upgrade_model(mi)
				continue
			if not roles.has(role):
				roles[role] = []
			roles[role].append(String(mi.name))
			var recipe := _variant(role, _original_albedo_path(mi))
			if recipe == "" or not Recipes.RECIPES.has(recipe):
				kept.append(String(mi.name))
				_restore_one(mi)
				continue
			var mat := _material_for(recipe, mi)
			if mat == null:
				continue
			mat.set_shader_parameter("detail_level", detail)
			_assign(mi, mat)
			n_mat += 1
	var missing: Array[String] = []
	if tier > 0:
		for r: String in Recipes.REQUIRED_ROLES:
			if not roles.has(r):
				missing.append(r)
				_warn_once("role_" + r, "Surfaces: no mesh for role '%s' under %s (node %s / material %s)" % [
					r, level_root.name, _names_for(Recipes.NODE_ROLES, r), _names_for(Recipes.MATERIAL_ROLES, r)])
	var n_dec := _update_decals(level_root, tier)
	stats = {"quality": q, "ms": (Time.get_ticks_usec() - t0) / 1000.0, "materials": n_mat, "roles": roles,
		"kept": kept, "missing": missing, "hidden": hidden, "decals": n_dec, "models": n_models}

static func restore(level_root: Node3D) -> void:
	if level_root == null or not is_instance_valid(level_root):
		return
	_restore_all(level_root.find_children("*", "MeshInstance3D", true, false))
	var d := level_root.get_node_or_null(DECALS_NODE)
	if d:
		d.queue_free()

## Names of the web meshes this module hides on medium+ (for checking a re-export): node names + material names.
static func hidden_web_overlays() -> Dictionary:
	return {"nodes": Recipes.HIDE_NODES, "materials": Recipes.HIDE_MATERIALS}

# ---------------------------------------------------------------------------------------------------- matching
static func _strip_index(s: String) -> String:
	var i := s.rfind("_")
	if i > 0 and s.substr(i + 1).is_valid_int():
		return s.substr(0, i)
	return s

static func _original_material(mi: MeshInstance3D) -> Material:
	if mi.has_meta(META_ORIG):
		var orig: Array = mi.get_meta(META_ORIG)
		if orig.size() > 0 and orig[0] != null:
			return orig[0]
	elif mi.get_surface_override_material(0) != null:
		return mi.get_surface_override_material(0)
	return mi.mesh.surface_get_material(0)

static func _role_of(mi: MeshInstance3D) -> String:
	var n := String(mi.name)
	if Recipes.NODE_ROLES.has(n):
		return Recipes.NODE_ROLES[n]
	var base := _strip_index(n)
	if base != n and Recipes.NODE_ROLES.has(base) and not _node_name_taken(mi, base):
		return Recipes.NODE_ROLES[base]
	var m := _original_material(mi)
	if m != null:
		var mn := String(m.resource_name)
		if Recipes.MATERIAL_ROLES.has(mn):
			return Recipes.MATERIAL_ROLES[mn]
	return ""

## "arch_wall_2" only stands for "arch_wall" when no sibling already carries the exact name.
static func _node_name_taken(mi: MeshInstance3D, base: String) -> bool:
	var p := mi.get_parent()
	return p != null and p.get_node_or_null(NodePath(base)) != null

static func _variant(role: String, albedo_path: String) -> String:
	for rule: Array in Recipes.VARIANTS.get(role, []):
		if albedo_path.contains(String(rule[0])):
			return String(rule[1])
	return role

static func _original_albedo_path(mi: MeshInstance3D) -> String:
	var t := _original_albedo(mi)
	return t.resource_path if t else ""

static func _original_albedo(mi: MeshInstance3D) -> Texture2D:
	var m := _original_material(mi)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	return null

static func _is_web_overlay(mi: MeshInstance3D) -> bool:
	var n := String(mi.name)
	if Recipes.HIDE_NODES.has(n) or Recipes.HIDE_NODES.has(_strip_index(n)):
		return true
	var m := _original_material(mi)
	if m == null:
		return false
	var mn := String(m.resource_name)
	return Recipes.HIDE_MATERIALS.has(mn) or Recipes.HIDE_MATERIALS.has(_strip_index(mn))

static func _names_for(d: Dictionary, role: String) -> String:
	var out: PackedStringArray = []
	for k: String in d:
		if d[k] == role:
			out.append(k)
	return "/".join(out)

# ---------------------------------------------------------------------------------------------------- materials
static func _assign(mi: MeshInstance3D, mat: Material) -> void:
	var count := mi.mesh.get_surface_count()
	if not mi.has_meta(META_ORIG):
		var orig: Array = []
		for i in count:
			orig.append(mi.get_surface_override_material(i))
		mi.set_meta(META_ORIG, orig)
	for i in count:
		if mi.get_surface_override_material(i) != mat:
			mi.set_surface_override_material(i, mat)

static func _assign_surface(mi: MeshInstance3D, surface: int, mat: Material) -> void:
	if not mi.has_meta(META_ORIG):
		var orig: Array = []
		for i in mi.mesh.get_surface_count():
			orig.append(mi.get_surface_override_material(i))
		mi.set_meta(META_ORIG, orig)
	if mi.get_surface_override_material(surface) != mat:
		mi.set_surface_override_material(surface, mat)

static func _original_surface_material(mi: MeshInstance3D, surface: int) -> Material:
	if mi.has_meta(META_ORIG):
		var orig: Array = mi.get_meta(META_ORIG)
		if surface < orig.size() and orig[surface] != null:
			return orig[surface]
	elif mi.get_surface_override_material(surface) != null:
		return mi.get_surface_override_material(surface)
	return mi.mesh.surface_get_material(surface)

## Hero furniture: swap in the 2K Poly Haven maps of the same asset (opaque materials of Recipes.MODEL_MATERIALS).
static func _upgrade_model(mi: MeshInstance3D) -> int:
	var done := 0
	for i in mi.mesh.get_surface_count():
		var bm := _original_surface_material(mi, i) as BaseMaterial3D
		if bm == null or bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var asset := String(Recipes.MODEL_MATERIALS.get(String(bm.resource_name), ""))
		if asset == "":
			continue
		var up := _model_material(bm, asset)
		if up:
			_assign_surface(mi, i, up)
			done += 1
	return done

static func _model_material(bm: BaseMaterial3D, asset: String) -> BaseMaterial3D:
	var key := "model#%d" % bm.get_instance_id()
	if _materials.has(key):
		return _materials[key]
	var dir := HIRES + "models/" + asset + "/"
	var alb := _tex(dir + "albedo.jpg")
	if alb == null:
		_materials[key] = null
		return null
	var m := bm.duplicate() as BaseMaterial3D
	m.resource_name = String(bm.resource_name) + "_2k"
	m.albedo_texture = alb
	var nrm := _tex(dir + "normal.jpg")
	if nrm:
		m.normal_enabled = true
		m.normal_texture = nrm
	if ResourceLoader.exists(dir + "arm.jpg"):
		var arm := _tex(dir + "arm.jpg")
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if bm.metallic_texture != null:
			m.metallic_texture = arm
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	elif ResourceLoader.exists(dir + "rough.jpg"):
		m.roughness_texture = _tex(dir + "rough.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_materials[key] = m
	return m

static func _restore_one(mi: MeshInstance3D) -> void:
	if mi.has_meta(META_ORIG):
		var orig: Array = mi.get_meta(META_ORIG)
		for i in mini(orig.size(), mi.mesh.get_surface_count() if mi.mesh else 0):
			mi.set_surface_override_material(i, orig[i])
		mi.remove_meta(META_ORIG)

static func _restore_all(meshes: Array) -> void:
	for node in meshes:
		var mi := node as MeshInstance3D
		_restore_one(mi)
		if mi.has_meta(META_HIDDEN):
			mi.visible = bool(mi.get_meta(META_HIDDEN))
			mi.remove_meta(META_HIDDEN)

static func _material_for(recipe: String, sample: MeshInstance3D) -> ShaderMaterial:
	var r: Dictionary = Recipes.RECIPES[recipe]
	var uv_orig: Texture2D = _original_albedo(sample) if r.get("uv_albedo_from_original", false) else null
	var key := recipe + ("#%d" % uv_orig.get_instance_id() if uv_orig else "")
	if _materials.has(key):
		return _materials[key]
	var kind := String(r.kind)
	var sh := _shader(kind)
	if sh == null:
		return null
	var set_dir := HIRES + String(r.set) + "/"
	var albedo := _tex(set_dir + "albedo.jpg")
	var normal := _tex(set_dir + "normal.jpg")
	var mask := _tex(set_dir + "mask.jpg")
	if albedo == null or normal == null or mask == null:
		_warn_once("set_" + String(r.set), "Surfaces: texture set '%s' incomplete (import res://assets/hires?)" % r.set)
		return null
	var m := ShaderMaterial.new()
	m.resource_name = "surfaces_" + recipe
	m.shader = sh
	m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("normal_tex", normal)
	m.set_shader_parameter("mask_tex", mask)
	m.set_shader_parameter("noise_tex", _tex(HIRES + "shared/noise.png"))
	m.set_shader_parameter("grunge_tex", _tex(HIRES + "shared/grunge.jpg"))
	_set_level_uniforms(m)
	if kind == "wall":
		_set_params(m, Recipes.WALL_BASE)
		if r.get("base", "") == "block":
			_set_params(m, Recipes.BLOCK_BASE)
	elif kind == "carpet":
		m.set_shader_parameter("lanes", PackedVector4Array(Recipes.LANES))
		m.set_shader_parameter("lane_count", Recipes.LANES.size())
	_set_params(m, r.params)
	if r.get("uv_albedo_from_original", false):
		if uv_orig:
			m.set_shader_parameter("uv_albedo_tex", uv_orig)
		else:
			m.set_shader_parameter("uv_albedo_mix", 0.0)
	_materials[key] = m
	return m

static func _set_params(m: ShaderMaterial, p: Dictionary) -> void:
	for k: String in p:
		m.set_shader_parameter(k, p[k])

static func _set_level_uniforms(m: ShaderMaterial) -> void:
	var R: Dictionary = Layout.ROOM
	var S: Dictionary = Layout.STAIRS
	var U: Dictionary = Layout.UPPER
	var H: Dictionary = Layout.UPPER_HALL
	var AL: Dictionary = Layout.ALCOVE
	var CL: Dictionary = Layout.CLOSET
	m.set_shader_parameter("lvl_stairs", Vector4(S.minX, S.maxX, S.topZ, S.bottomZ))
	m.set_shader_parameter("lvl_step", Vector3(S.riserHeight, S.treadDepth, S.risers))
	m.set_shader_parameter("lvl_hall", Vector4(H.minX, H.maxX, H.minZ, H.maxZ))
	m.set_shader_parameter("lvl_heights", Vector4(R.ceilingY, U.floorY, U.ceilingY, S.ceilingOpeningMaxZ))
	var kx1: float = S.sideWallX + S.sideWallThickness * 0.5
	var kx0: float = S.sideWallX - S.sideWallThickness * 0.5
	var zn: float = R.minZ - 0.15   # nook side of the 0.15 m north partition
	var c := PackedVector2Array([
		Vector2(R.maxX, R.maxZ), Vector2(R.maxX, R.minZ), Vector2(R.minX, R.maxZ), Vector2(kx1, R.minZ),
		Vector2(R.minX, R.minZ), Vector2(kx0, R.minZ),
		Vector2(AL.minX, AL.minZ), Vector2(AL.maxX, AL.minZ), Vector2(AL.minX, zn), Vector2(AL.maxX, zn),
		Vector2(R.minX, CL.maxZ), Vector2(kx0, CL.maxZ),
		Vector2(H.minX, H.minZ), Vector2(H.maxX, H.minZ), Vector2(H.minX, H.maxZ), Vector2(H.maxX, H.maxZ),
	])
	m.set_shader_parameter("lvl_corners", c)
	m.set_shader_parameter("lvl_corner_count", c.size())

static func _shader(kind: String) -> Shader:
	if _shaders.has(kind):
		return _shaders[kind]
	var sh: Shader = null
	if SHADERS.has(kind) and ResourceLoader.exists(String(SHADERS[kind])):
		sh = load(String(SHADERS[kind])) as Shader
	if sh == null:
		_warn_once("shader_" + kind, "Surfaces: shader for '%s' missing" % kind)
	_shaders[kind] = sh
	return sh

static func _tex(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null:
		_warn_once("tex_" + path, "Surfaces: texture missing: " + path)
	_textures[path] = t
	return t

# ---------------------------------------------------------------------------------------------------- decals
static func _decal_specs() -> Array:
	var web: Array = DecalTable.WEB
	var lay := load("res://scripts/layout.gd") as Script
	if lay:
		var consts: Dictionary = lay.get_script_constant_map()
		if consts.get("DECALS") is Array and not (consts.DECALS as Array).is_empty():
			web = consts.DECALS
	return web + DecalTable.STORY

static func _update_decals(level_root: Node3D, tier: int) -> int:
	var holder := level_root.get_node_or_null(DECALS_NODE) as Node3D
	if tier == 0:
		if holder:
			holder.visible = false
		return 0
	if holder == null:
		holder = Node3D.new()
		holder.name = DECALS_NODE
		level_root.add_child(holder)
		for d: Dictionary in _decal_specs():
			var dec := _make_decal(d)
			if dec:
				holder.add_child(dec)
	holder.visible = true
	var shown := 0
	for dec in holder.get_children():
		var on := int(dec.get_meta(&"tier", 1)) <= tier
		(dec as Node3D).visible = on
		shown += 1 if on else 0
	return shown

static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO

static func _v2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO

static func _make_decal(d: Dictionary) -> Decal:
	var tex_id := String(d.get("tex", ""))
	var set_name := String(DecalTable.TEX_MAP.get(tex_id, tex_id))
	if tex_id.begins_with("crayon:"):
		set_name = "crayon_" + tex_id.substr(7)
	var dir := HIRES + "decals/" + set_name + "/"
	var albedo := _tex(dir + "albedo.png")
	if albedo == null:
		return null
	var pos := _v3(d.get("pos"))
	var y := _v3(d.get("n", d.get("normal"))).normalized()
	var up := _v3(d.get("up")).normalized()
	var size := _v2(d.get("size"))
	if y == Vector3.ZERO or up == Vector3.ZERO or size == Vector2.ZERO:
		return null
	var dec := Decal.new()
	dec.name = "decal_" + String(d.get("id", set_name))
	var tier_key := "crayon" if set_name.begins_with("crayon") else set_name
	dec.set_meta(&"tier", int(d.get("tier", DecalTable.TIERS.get(tier_key, 1))))
	dec.texture_albedo = albedo
	if ResourceLoader.exists(dir + "orm.jpg"):
		dec.texture_orm = _tex(dir + "orm.jpg")
	var on_floor := y.y > 0.9
	dec.size = Vector3(size.x, float(d.get("depth", 0.1 if on_floor else 0.14)), size.y)
	dec.modulate = Color(1, 1, 1, float(d.get("a", d.get("opacity", 1.0))))
	dec.albedo_mix = 1.0
	dec.normal_fade = 0.5
	dec.upper_fade = 0.2
	dec.lower_fade = 0.2
	dec.distance_fade_enabled = true
	dec.distance_fade_begin = 14.0
	dec.distance_fade_length = 4.0
	# basis: Y = surface normal (Godot decals project along -Y), Z = texture down (v grows along +Z), X = Y x Z
	var z := -(up - y * up.dot(y)).normalized()
	var x := y.cross(z).normalized()
	if bool(d.get("flip", false)):
		x = -x
	dec.transform = Transform3D(Basis(x, y, z), pos)
	return dec

static func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)
