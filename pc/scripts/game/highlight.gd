## Looked-at feedback without any HUD (the default: Settings "hud" = "none"). The targeted interactable gets a faint
## brightening relative to its own lit colour (+~15–35 %, stronger at the rim, so nothing glows in total darkness) that
## fades in and out; holding a hold-to-use interaction makes it swell. Owned by Interaction (scripts/game/interaction.gd).
##
## The glow is drawn by PROXIES, never on the real meshes: for each highlighted mesh a copy (same Mesh resource, the
## highlight material, no shadow, no GI) lives under `holder` and follows the mesh's transform. Reason, read in Godot
## 4.5's RendererSceneCull::_update_instance: any change to a shadow-casting instance — a material overlay included —
## marks every light around it shadow-dirty. With `material_overlay` each time the crosshair crossed an interactable
## the ceiling bulb re-rendered its whole shadow cube twice (tools/hitch_hunt.gd: 100-300 k shadow triangles on a third
## of the frames of a look around the room).
extends RefCounted

const SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.0;

void fragment() {
	// Relative brightening: add a fraction of the object's own lit colour (nothing appears in darkness).
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 base = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	ALBEDO = base * strength * (0.14 + 0.20 * rim);
}
"""
const FADE_IN := 0.18
const FADE_OUT := 0.15
const MAX_MESHES := 64

var _shader: Shader = null
var _mat_cur: ShaderMaterial = null
var _mat_old: ShaderMaterial = null
var _cur: Array = []
var _old: Array = []
var _cur_s := 0.0
var _old_s := 0.0

func _init() -> void:
	_shader = Shader.new()
	_shader.code = SHADER_CODE
	_mat_cur = _new_mat()
	_mat_old = _new_mat()

func _new_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("strength", 0.0)
	return m

var holder: Node3D = null           # parent of the proxies (set by the owner before the first target)
var late_proxies := 0               # proxies that had to be built during play (each one is a new instance for the GPU)
var log_late := false               # debug: print them (set by a test script)
var _prewarming := false
var _proxies := {}                  # MeshInstance3D instance id -> proxy MeshInstance3D

func _proxy_of(m: MeshInstance3D) -> MeshInstance3D:
	var id := m.get_instance_id()
	var p = _proxies.get(id)
	if p != null and is_instance_valid(p):
		return p
	if holder == null or not is_instance_valid(holder):
		return null
	var px := MeshInstance3D.new()
	px.name = "Glow"
	px.mesh = m.mesh
	px.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	px.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	px.layers = m.layers
	px.extra_cull_margin = m.extra_cull_margin
	px.visible = false
	holder.add_child(px)
	_proxies[id] = px
	late_proxies += 0 if _prewarming else 1
	if not _prewarming and log_late:
		print("[highlight] proxy built during play for %s (%s)" % [m.name, m.get_parent().name if m.get_parent() else ""])
	return px

func _show(meshes: Array, mat: Material) -> void:
	for m in meshes:
		if not is_instance_valid(m): continue
		var px := _proxy_of(m as MeshInstance3D)
		if px == null: continue
		px.material_override = mat
		px.global_transform = (m as MeshInstance3D).global_transform
		px.visible = true

func _follow(meshes: Array) -> void:
	for m in meshes:
		if not is_instance_valid(m): continue
		var px = _proxies.get((m as Object).get_instance_id())
		if px != null and is_instance_valid(px):
			var xf: Transform3D = (m as MeshInstance3D).global_transform
			if not (px as MeshInstance3D).global_transform.is_equal_approx(xf):
				(px as MeshInstance3D).global_transform = xf

## Highlight `node` (and its visible meshes); null clears. The previous target fades out.
func set_target(node: Variant) -> void:
	_clear(_old, _mat_old)
	_old = _cur
	_old_s = _cur_s
	var t := _mat_old
	_mat_old = _mat_cur
	_mat_cur = t
	_cur = _collect(node)
	_cur_s = 0.0
	_mat_cur.set_shader_parameter("strength", 0.0)
	for m in _cur:
		_old.erase(m)
	_show(_cur, _mat_cur)

## Call every frame. hold_k: hold-to-use progress 0..1, or < 0 when not holding.
func update(dt: float, hold_k := -1.0) -> void:
	var want := 0.0 if _cur.is_empty() else (1.0 if hold_k < 0.0 else 1.0 + 0.8 * hold_k)
	_cur_s = move_toward(_cur_s, want, dt / FADE_IN)
	_mat_cur.set_shader_parameter("strength", _cur_s)
	_follow(_cur)        # drawers and doors move while they are looked at
	if not _old.is_empty():
		_follow(_old)
		_old_s = move_toward(_old_s, 0.0, dt / FADE_OUT)
		_mat_old.set_shader_parameter("strength", _old_s)
		if _old_s <= 0.0:
			_clear(_old, _mat_old)
			_old = []

## Loading screen: builds the proxy of every mesh the glow can ever land on and shows them (invisible, strength 0), so
## the GPU builds those pipelines before play and no node is created during it. Returns the meshes for prewarm_end().
func prewarm_begin(nodes: Array) -> Array:
	var out: Array = []
	_mat_old.set_shader_parameter("strength", 0.0)
	for n in nodes:
		# hidden meshes too: a whole area can be hidden while the camera is elsewhere (the garderie hall from the house),
		# and its interactables would otherwise get their proxies, and their pipelines, at the first look in play
		for m in _collect(n, true):
			if not _cur.has(m): out.append(m)
	_prewarming = true
	_show(out, _mat_old)
	_prewarming = false
	return out

func prewarm_end(meshes: Array) -> void:
	_clear(meshes, _mat_old)

func clear() -> void:
	_clear(_cur, _mat_cur)
	_clear(_old, _mat_old)
	_cur = []
	_old = []
	_cur_s = 0.0
	_old_s = 0.0

func _clear(meshes: Array, mat: Material) -> void:
	for m in meshes:
		if not is_instance_valid(m): continue
		var px = _proxies.get((m as Object).get_instance_id())
		if px != null and is_instance_valid(px) and (px as MeshInstance3D).material_override == mat:
			(px as MeshInstance3D).visible = false

func _collect(node: Variant, include_hidden := false) -> Array:
	var out: Array = []
	if node == null or not (node is Node) or not is_instance_valid(node):
		return out
	var n := node as Node
	if n is MeshInstance3D and (include_hidden or (n as MeshInstance3D).is_visible_in_tree()) and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.find_children("*", "MeshInstance3D", true, false):
		if out.size() >= MAX_MESHES: break
		if (include_hidden or (c as MeshInstance3D).is_visible_in_tree()) and (c as MeshInstance3D).mesh != null:
			out.append(c)
	return out
