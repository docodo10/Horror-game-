## Old CRT in the laundry nook (world module) — port of src/world/ExtraProps.js `_buildCRT` / `crtFlicker` / `_updateCRT`.
## When the mains come back the unplugged Television_01 wakes up anyway: a line opens, ~1.2 s of flickering snow with
## drop-outs and a rolling bar, then it collapses to a line, a dot, and dies (≈1.9 s, after a 0.55 s delay). The phosphor
## sheet is the exported `extra_crt_screen` mesh (additive); the snow is a GPU shader. Its own small blue-white
## OmniLight3D (web extra_crt_light: high / ultra only) lights the nook during the beat.
## Public: flicker(delay := 0.0), stop(), active (bool), light (OmniLight3D or null), sound_position.
extends Node

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float time_s = 0.0;
uniform float frame = 0.0;
uniform float level = 1.0;
uniform float h_ext = 1.0;
uniform float w_ext = 1.0;
uniform float line_mode = 0.0;
const vec2 RES = vec2(128.0, 96.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float smooth_web(float a, float b, float x) { float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
vec3 srgb_to_linear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }

void fragment() {
	vec2 cell = floor(UV * RES);
	float u2 = (cell.x + 0.5) / RES.x * 2.0 - 1.0;
	float v2 = (cell.y + 0.5) / RES.y * 2.0 - 1.0;
	float q = pow(pow(abs(u2), 6.0) + pow(abs(v2), 6.0), 1.0 / 6.0);
	float mask = smooth_web(1.0, 0.86, q) * (1.0 - 0.35 * (u2 * u2 + v2 * v2) * 0.5) * (mod(cell.y, 2.0) > 0.5 ? 0.72 : 1.0);
	float hh = h_ext * 0.5;
	float ww = w_ext * 0.5;
	float v = abs((cell.y + 0.5) / RES.y - 0.5);
	float u = abs((cell.x + 0.5) / RES.x - 0.5);
	bool is_line = line_mode > 0.5;
	float vy = is_line ? max(0.0, 1.0 - v / (hh + 0.012)) : smooth_web(hh + 0.01, hh - 0.01, v);
	float roll = fract(time_s * 0.7) * RES.y;
	float dr = abs(cell.y - roll);
	float dm = min(dr, RES.y - dr);
	float bar = 1.0 - 0.45 * exp(-dm * dm / 40.0);
	float vx = smooth_web(ww + 0.02, ww - 0.01, u);
	float n = is_line ? 1.0 : 0.18 + 0.82 * hash12(cell + vec2(frame * 13.7, frame * 29.3));
	float s = n * vy * vx * (is_line ? 1.0 : mask * bar);
	ALBEDO = srgb_to_linear(clamp(vec3(s * 0.9, s * 0.95, s), 0.0, 1.0)) * level * 1.6;
}
"""

var world: Node = null
var tv: Node3D = null
var screen: MeshInstance3D = null
var material: ShaderMaterial = null
var light: OmniLight3D = null
var sound_position := Vector3(2.484, 0.26, -4.13)
var active := false
var on_kick := Callable()       # called when the beat starts (the panel thump shakes the pull chain)

var _t := -1.0
var _delay := 0.0
var _started := false
var _off_played := false
var _snd = null
var _lvl := 1.0
var _lvl_t := 0.0
var _acc := 0.0
var _frame := 0
var _rng := RandomNumberGenerator.new()

func setup(p_world: Node, tv_node: Node3D, screen_node: MeshInstance3D, crt_meta: Dictionary) -> void:
	world = p_world
	tv = tv_node
	screen = screen_node
	name = "OldCRT"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.seed = 77
	var sp = crt_meta.get("soundPos")
	if sp is Array and sp.size() >= 3: sound_position = Vector3(sp[0], sp[1], sp[2])
	material = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	material.shader = sh
	if screen != null:
		screen.material_override = material
		screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		screen.visible = false
	if tv != null:
		light = OmniLight3D.new()
		light.name = "CRTLight"
		light.light_color = Color(0.737, 0.824, 1.0)      # #bcd2ff
		light.light_energy = 0.0
		light.omni_range = 3.2
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.visible = false
		light.position = Vector3(-0.066, 0.26, 0.42)
		tv.add_child(light)
	set_process(false)

## Plays the beat (after `delay` s). Restarts it if already running.
func flicker(delay := 0.0) -> void:
	stop()
	_t = 0.0
	_delay = delay
	_started = false
	_off_played = false
	active = true
	if on_kick.is_valid(): on_kick.call()
	set_process(true)

func stop() -> void:
	_t = -1.0
	active = false
	if screen != null: screen.visible = false
	if light != null:
		light.light_energy = 0.0
		light.visible = false
	_stop_snd(0.1)
	set_process(false)

func _process(dt: float) -> void:
	if _t < 0.0:
		set_process(false)
		return
	if _delay > 0.0:
		_delay -= dt
		return
	if not _started:
		_started = true
		if screen != null: screen.visible = true
		_snd = Audio.loop("tv_static", {"position": sound_position, "volume_db": linear_to_db(0.16)})
	_t += dt
	var t := _t
	var b := 1.0
	var h_ext := 1.0
	var w_ext := 1.0
	if t < 0.1:
		h_ext = 0.02 + 0.98 * (t / 0.1)
		b = 1.5
	elif t < 1.25:
		_lvl_t -= dt
		if _lvl_t <= 0.0:
			_lvl = 0.55 + _rng.randf() * 0.6
			if _rng.randf() < 0.12: _lvl = 0.12
			_lvl_t = 0.04 + _rng.randf() * 0.08
		b = _lvl
	elif t < 1.4:
		var k := (t - 1.25) / 0.15
		h_ext = maxf(0.012, 1.0 - k * k)
		b = 1.0 + k * 0.9
		if not _off_played:
			_off_played = true
			_stop_snd(0.12)
			Audio.play("tv_off", {"position": sound_position, "volume_db": linear_to_db(0.3)})
	elif t < 1.52:
		h_ext = 0.012
		w_ext = maxf(0.03, 1.0 - (t - 1.4) / 0.12)
		b = 1.9
	elif t < 1.9:
		h_ext = 0.012
		w_ext = 0.03
		b = 1.9 * (1.0 - (t - 1.52) / 0.38)
	else:
		stop()
		return
	var line := h_ext < 0.05
	_acc += dt
	if _acc >= 1.0 / 30.0:
		_acc = 0.0
		_frame += 1
	material.set_shader_parameter("time_s", t)
	material.set_shader_parameter("frame", float(_frame % 4096))
	material.set_shader_parameter("level", b)
	material.set_shader_parameter("h_ext", h_ext)
	material.set_shader_parameter("w_ext", w_ext)
	material.set_shader_parameter("line_mode", 1.0 if line else 0.0)
	if light != null:
		var q := String(Settings.get_value("quality", "high"))
		light.visible = q == "high" or q == "ultra"
		light.light_energy = b * (0.4 if line else 3.0) * maxf(h_ext, 0.05) * 0.35

func _stop_snd(fade: float) -> void:
	if _snd != null and _snd is Object and (_snd as Object).has_method("stop"): _snd.stop(fade)
	_snd = null
