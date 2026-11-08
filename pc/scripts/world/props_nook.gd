## Laundry-nook fluorescent batten (world module) — the "fluorescent batten that flickers with the power" the web Details
## pass planned for the nook (ARCHITECTURE_PC.md §4 World). A 4 ft single-tube batten (white enamel channel, two lamp
## holders, T8 tube with blackened ends) screwed across the joists at the back of the nook, over the breaker panel.
## Behaviour: lit while the mains are on; when the power comes back the starter struggles (clicks + 3–4 strikes) before
## the tube catches and warms up; an ageing tube dips now and then. The light itself belongs to the look module:
## it reads `level` / `level_changed` (or sets auto = false and drives set_level itself).
## Public: level (0..1), auto (true: power / flicker logic here), color, tube_center (world), length,
##   set_level(v), set_power(on), signal level_changed(level)
extends Node3D

signal level_changed(level: float)

const LENGTH := 1.22
const CENTER := Vector3(2.58, 2.5, -3.9)      # under the joists (bottom y 2.50), between the duct and the back pipes
const TUBE_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform float level = 1.0;
uniform vec3 glow = vec3(0.85, 1.0, 0.9);
uniform float energy = 5.0;
uniform float t_s = 0.0;
uniform float half_len = 0.575;
varying float axial;

void vertex() {
	axial = clamp(VERTEX.y / (2.0 * half_len) + 0.5, 0.0, 1.0);
}

void fragment() {
	float ends = smoothstep(0.0, 0.05, axial) * smoothstep(1.0, 0.95, axial);
	float burn = mix(0.35, 1.0, smoothstep(0.02, 0.09, axial) * smoothstep(0.98, 0.91, axial));
	ALBEDO = mix(vec3(0.16), vec3(0.9, 0.92, 0.9), burn);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
	float ripple = 1.0 - 0.04 * level * (0.5 + 0.5 * sin(t_s * 37.0 + axial * 9.0));
	EMISSION = glow * energy * level * ends * burn * ripple;
}
"""

var world: Node = null
var level := 1.0
var auto := true
var color := Color(0.85, 1.0, 0.9)          # linear: old "cool white" tube, slightly green
var tube_center := CENTER
var length := LENGTH

var _mat: ShaderMaterial = null
var _power := true
var _seq: Array = []            # [[duration, level], ...] starter / flicker sequence being played
var _seq_t := 0.0
var _flicker_t := 40.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func setup(p_world: Node) -> void:
	world = p_world
	name = "NookTube"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_flicker_t = _rng.randf_range(25.0, 60.0)
	position = CENTER
	var enamel := StandardMaterial3D.new()
	enamel.albedo_color = Color(0.86, 0.85, 0.8)
	enamel.roughness = 0.42
	var holder_mat := StandardMaterial3D.new()
	holder_mat.albedo_color = Color(0.82, 0.8, 0.74)
	holder_mat.roughness = 0.55
	# channel (top flush with the joist bottoms)
	_box("Channel", Vector3(LENGTH, 0.045, 0.07), Vector3(0, -0.0225, 0), enamel)
	# lamp holders
	for sx in [-1.0, 1.0]:
		_box("Holder", Vector3(0.03, 0.04, 0.045), Vector3(sx * (LENGTH * 0.5 - 0.02), -0.06, 0.0), holder_mat)
	# tube along X
	var tube := MeshInstance3D.new()
	tube.name = "Tube"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0135
	cyl.bottom_radius = 0.0135
	cyl.height = LENGTH - 0.07
	cyl.radial_segments = 16
	cyl.rings = 1
	tube.mesh = cyl
	tube.rotation = Vector3(0, 0, PI / 2.0)
	tube.position = Vector3(0, -0.068, 0)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TUBE_SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("half_len", cyl.height * 0.5)
	tube.material_override = _mat
	add_child(tube)
	tube_center = CENTER + Vector3(0, -0.068, 0)
	_apply()

func _box(n: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)

func set_level(v: float) -> void:
	v = clampf(v, 0.0, 1.5)
	if is_equal_approx(v, level): return
	level = v
	_apply()
	level_changed.emit(level)

func set_power(on: bool) -> void:
	var was := _power
	_power = on
	if not auto: return
	if not on:
		_seq.clear()
		set_level(0.0)
	elif not was:
		_start_sequence()

func _start_sequence() -> void:
	# starter: clicks and failed strikes, then the tube catches dim and warms up
	_seq = [[0.6, 0.0]]
	var strikes := _rng.randi_range(2, 4)
	for i in strikes:
		_seq.append([_rng.randf_range(0.04, 0.09), _rng.randf_range(0.5, 1.0)])
		_seq.append([_rng.randf_range(0.18, 0.45), 0.0])
	_seq.append([0.12, 0.55])
	_seq.append([0.06, 0.1])
	_seq.append([0.9, -1.0])        # -1 = warm-up ramp 0.6 -> 1
	_seq_t = 0.0

func _start_flicker() -> void:
	_seq = []
	for i in _rng.randi_range(2, 5):
		_seq.append([_rng.randf_range(0.03, 0.08), _rng.randf_range(0.05, 0.4)])
		_seq.append([_rng.randf_range(0.04, 0.15), 1.0])
	_seq_t = 0.0

func _process(dt: float) -> void:
	_t += dt
	if _mat != null: _mat.set_shader_parameter("t_s", _t)
	if not auto: return
	if not _seq.is_empty():
		_seq_t += dt
		var step: Array = _seq[0]
		var lv := float(step[1])
		if lv < 0.0: set_level(lerpf(0.6, 1.0, Handle.ease_curve("out", minf(1.0, _seq_t / float(step[0])))))
		else:
			if not is_equal_approx(lv, level) and lv > 0.3 and level < 0.05: _click()
			set_level(lv)
		if _seq_t >= float(step[0]):
			_seq_t = 0.0
			_seq.pop_front()
			if _seq.is_empty() and _power: set_level(1.0)
		return
	if _power and level > 0.5:
		_flicker_t -= dt
		if _flicker_t <= 0.0:
			_flicker_t = _rng.randf_range(25.0, 70.0)
			_start_flicker()

func _click() -> void:
	Audio.play("flashlight_click", {"position": tube_center, "volume_db": -10.0, "pitch": 0.62})

func _apply() -> void:
	if _mat == null: return
	_mat.set_shader_parameter("level", level)
	_mat.set_shader_parameter("glow", Vector3(color.r, color.g, color.b))
