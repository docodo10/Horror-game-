## Looked-at feedback without any HUD (the default: Settings "hud" = "none"). The targeted interactable gets a faint
## brightening relative to its own lit colour (+~15–35 %, stronger at the rim, so nothing glows in total darkness) that
## fades in and out; holding a hold-to-use interaction makes it swell. Owned by Interaction (scripts/game/interaction.gd).
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
		(m as GeometryInstance3D).material_overlay = _mat_cur

## Call every frame. hold_k: hold-to-use progress 0..1, or < 0 when not holding.
func update(dt: float, hold_k := -1.0) -> void:
	var want := 0.0 if _cur.is_empty() else (1.0 if hold_k < 0.0 else 1.0 + 0.8 * hold_k)
	_cur_s = move_toward(_cur_s, want, dt / FADE_IN)
	_mat_cur.set_shader_parameter("strength", _cur_s)
	if not _old.is_empty():
		_old_s = move_toward(_old_s, 0.0, dt / FADE_OUT)
		_mat_old.set_shader_parameter("strength", _old_s)
		if _old_s <= 0.0:
			_clear(_old, _mat_old)
			_old = []

func clear() -> void:
	_clear(_cur, _mat_cur)
	_clear(_old, _mat_old)
	_cur = []
	_old = []
	_cur_s = 0.0
	_old_s = 0.0

func _clear(meshes: Array, mat: Material) -> void:
	for m in meshes:
		if is_instance_valid(m) and (m as GeometryInstance3D).material_overlay == mat:
			(m as GeometryInstance3D).material_overlay = null

func _collect(node: Variant) -> Array:
	var out: Array = []
	if node == null or not (node is Node) or not is_instance_valid(node):
		return out
	var n := node as Node
	if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
		out.append(n)
	for c in n.find_children("*", "MeshInstance3D", true, false):
		if out.size() >= MAX_MESHES: break
		if (c as MeshInstance3D).is_visible_in_tree():
			out.append(c)
	return out
