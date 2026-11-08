## Dresser TV (world module) — port of src/world/Props.js `_buildTV` / `_tvSetOn` / `_updateTV` + ProcTextures `TVStatic`.
## The curved screen is the exported level node `tv_screen` (attached to the television_02 instance); its material is a
## GPU static shader (no per-pixel CPU work): 176×132 snow at 30 fps, rolling bar, scanlines, rounded CRT mask, the clue
## digit pulsing through the snow (tv_digit_<d>.png mask) with sync-jitter rows and rare ghost frames, warm-up / collapse.
## Public (world.tv, ARCHITECTURE_PC.md §6): node (television_02 instance), screen (MeshInstance3D), is_on,
##   set_on(on) -> bool (false without power), set_digit(d), screen_position. Gameplay plays tv_on / tv_off itself; this
##   plays only the positional tv_static loop and drives world.lighting.set_tv_light(on, intensity).
## Additions: material (ShaderMaterial), brightness (multiplier, look module may tune), digit (String), phase.
extends Node

const DIGIT_TEX := "res://assets/generated/textures/decals/tv_digit_%s.png"
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D digit_mask : filter_linear, repeat_disable;
uniform float digit_amount = 0.0;
uniform float frame = 0.0;
uniform float time_s = 0.0;
uniform float gain = 1.0;
uniform float fill = -1.0;
uniform float jitter = 0.0;
uniform vec3 tint = vec3(1.35, 1.4, 1.5);
uniform float brightness = 1.0;
uniform vec2 res = vec2(176.0, 132.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 cell = floor(UV * res);
	vec2 d = (cell / (res - 1.0)) * 2.0 - 1.0;
	float r = pow(pow(abs(d.x), 6.0) + pow(abs(d.y), 6.0), 1.0 / 6.0);
	float vig = r > 1.0 ? 0.0 : max(0.0, 1.0 - r * r * r * 0.55) * (r > 0.97 ? (1.0 - r) / 0.03 : 1.0);
	vec3 c;
	if (fill >= 0.0) {
		c = vec3(min(1.0, fill) * step(0.0001, vig));
	} else {
		float fy = cell.y / res.y;
		float bar = mod(time_s * 0.23, 1.4) - 0.2;
		float db = fy - bar;
		float bar_f = 1.0 + 0.35 * exp(-db * db * 90.0) - 0.18 * exp(-(db + 0.08) * (db + 0.08) * 200.0);
		float line = (mod(cell.y, 2.0) > 0.5 ? 0.72 : 1.0) * bar_f * gain;
		float n = hash12(cell + vec2(frame * 17.13, frame * 31.71));
		n = n * n;
		float v = (40.0 / 255.0 + n * 0.85) * line * vig;
		if (digit_amount > 0.0) {
			float jit = mod(cell.y, 23.0) < 0.5 ? jitter : 0.0;
			float m = texture(digit_mask, vec2((cell.x + 0.5 + jit) / res.x, (cell.y + 0.5) / res.y)).a;
			v = v * (1.0 - m * 0.45 * digit_amount) + m * digit_amount * (150.0 / 255.0) * vig;
		}
		c = vec3(v * 0.9, v * 0.97, v * 1.08);
	}
	ALBEDO = srgb_to_linear(clamp(c, 0.0, 1.0)) * tint * brightness;
}
"""

var world: Node = null
var node: Node3D = null
var screen: MeshInstance3D = null
var material: ShaderMaterial = null
var is_on := false
var screen_position := Vector3(-0.55, 1.472, -2.376)
var brightness := 1.0
var digit := ""
var phase := "off"           # off | warm | on | collapse

var _t := 0.0
var _phase_t := 0.0
var _acc := 0.0
var _frame := 0
var _loop = null
var _rng := RandomNumberGenerator.new()
var _base_scale := Vector3.ONE
var _digit_tex: Texture2D = null

static func make_shader() -> Shader:
	var sh := Shader.new()
	sh.code = SHADER
	return sh

func setup(p_world: Node, tv_node: Node3D, screen_node: MeshInstance3D, tv_meta: Dictionary) -> void:
	world = p_world
	node = tv_node
	screen = screen_node
	name = "TV"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 0x9e3779b9
	var sp = tv_meta.get("screenPosition")
	if sp is Array and sp.size() >= 3: screen_position = Vector3(sp[0], sp[1], sp[2])
	material = ShaderMaterial.new()
	material.shader = make_shader()
	var col = tv_meta.get("color")
	if col is Array and col.size() >= 3: material.set_shader_parameter("tint", Vector3(col[0], col[1], col[2]))
	if screen != null:
		screen.material_override = material
		screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		screen.visible = false
		_base_scale = screen.scale
	set_process(false)

## Turns the TV on / off. Returns false (and does nothing) when the power is out.
func set_on(on: bool) -> bool:
	if on and world != null and world.get(&"power") == false: return false
	if on == is_on: return true
	is_on = on
	if screen == null: return true
	if on:
		phase = "warm"
		_phase_t = 0.0
		_t = 0.0
		screen.visible = true
		screen.scale = Vector3(_base_scale.x, _base_scale.y * 0.02, _base_scale.z)
		material.set_shader_parameter("fill", 1.0)
		_stop_loop(0.05)
		_loop = Audio.loop("tv_static", {"position": screen_position, "volume_db": linear_to_db(0.9)})
		_lighting("set_tv_light", [true, 1.0])
	else:
		phase = "collapse"
		_phase_t = 0.0
		_stop_loop(0.08)
		_lighting("set_tv_light", [false, 0.0])
	set_process(true)
	return true

func set_digit(d) -> void:
	digit = "" if d == null else str(d)
	_digit_tex = null
	if digit != "" and digit.is_valid_int():
		var p := DIGIT_TEX % digit.substr(0, 1)
		if ResourceLoader.exists(p): _digit_tex = load(p)
	if material != null:
		material.set_shader_parameter("digit_mask", _digit_tex)
		if _digit_tex == null: material.set_shader_parameter("digit_amount", 0.0)

## Instant off (reset after a catch / power cut): no collapse animation.
func force_off() -> void:
	is_on = false
	phase = "off"
	_stop_loop(0.05)
	if screen != null:
		screen.visible = false
		screen.scale = _base_scale
	_lighting("set_tv_light", [false, 0.0])
	set_process(false)

func _process(dt: float) -> void:
	if screen == null or phase == "off":
		set_process(false)
		return
	_t += dt
	_phase_t += dt
	material.set_shader_parameter("brightness", brightness)
	if phase == "warm":
		var k := minf(1.0, _phase_t / 0.28)
		screen.scale = Vector3(_base_scale.x, _base_scale.y * (0.02 + 0.98 * Handle.ease_curve("out", k)), _base_scale.z)
		if k >= 1.0:
			phase = "on"
			screen.scale = _base_scale
	elif phase == "collapse":
		var t := _phase_t
		if t < 0.12:
			screen.scale = Vector3(_base_scale.x, _base_scale.y * maxf(0.012, 1.0 - t / 0.12), _base_scale.z)
			material.set_shader_parameter("fill", 1.0)
		elif t < 0.3:
			var k := (t - 0.12) / 0.18
			screen.scale = Vector3(_base_scale.x * maxf(0.01, 1.0 - k), _base_scale.y * 0.012, _base_scale.z)
			material.set_shader_parameter("fill", 1.0 - k * 0.5)
		else:
			screen.visible = false
			screen.scale = _base_scale
			phase = "off"
			set_process(false)
		return
	# static frames at 30 fps (the snow pattern is a function of the frame index)
	_acc += dt
	if _acc < 1.0 / 30.0: return
	_acc = 0.0
	_frame += 1
	var amount := 0.0
	if _digit_tex != null:
		var ph := fmod(_t, 1.5)
		if ph < 0.34: amount = sin((ph / 0.34) * PI) * (0.85 if _rng.randf() < 0.75 else 0.2)
		elif _rng.randf() < 0.025: amount = 0.18      # ghost frame
	var jit := float(_rng.randi_range(0, 3)) if _rng.randi() % 4 == 0 else 0.0
	material.set_shader_parameter("fill", -1.0)
	material.set_shader_parameter("frame", float(_frame % 4096))
	material.set_shader_parameter("time_s", _t)
	material.set_shader_parameter("gain", 1.4 if phase == "warm" else 1.0)
	material.set_shader_parameter("digit_amount", amount)
	material.set_shader_parameter("jitter", jit)

func _stop_loop(fade: float) -> void:
	if _loop != null and _loop is Object and (_loop as Object).has_method("stop"): _loop.stop(fade)
	_loop = null

func _lighting(method: String, args: Array) -> void:
	var l = world.get(&"lighting") if world != null else null
	if l is Object and is_instance_valid(l) and (l as Object).has_method(method): (l as Object).callv(method, args)
