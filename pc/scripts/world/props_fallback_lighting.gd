## Placeholder lighting (world module) — used ONLY while scripts/world/lighting.gd (look module) builds no light, so the
## level is playable and screenshots are readable. Same public API as lighting.gd (world.lighting points here then):
##   build(world) ; set_power(on) ; blowout() ; flicker(duration := 0.6, depth := 1.0) ; set_stress(v) ;
##   set_tv_light(on, intensity := 1.0) ; door_strip_occluded(v) ; set_menu_mode(on)
## Lights (positions from level_meta.json lights[] / Layout): warm 2700 K bulb in the fan light kit (soft shadows),
## the frosted bowl emission, the nook fluorescent tube light (follows world.nook_tube.level), a cold moon spot through
## the barred window, the TV spill, the warm hallway light leaking under the upstairs door. The fallback Environment
## (World3D.fallback_environment, so any WorldEnvironment of the look module wins automatically) is set by world.gd.
extends Node3D

const CEIL_ENERGY := 2.6
const BOWL_EMISSION := 6.0
const TUBE_ENERGY := 1.1
const TV_ENERGY := 0.9
const DOOR_ENERGY := 0.35

var world: Node = null
var ceiling: OmniLight3D = null
var tube_light: OmniLight3D = null
var moon: SpotLight3D = null
var tv_light: SpotLight3D = null
var door_light: OmniLight3D = null

var _level := 1.0            # ceiling filament level 0..1
var _power := true
var _menu := false
var _flicker_t := 0.0
var _flicker_depth := 0.0
var _flash_t := 0.0
var _tv_target := 0.0
var _tv_level := 0.0
var _door_occ := 0.0
var _bowl_mats: Array[StandardMaterial3D] = []
var _strip_mats: Array[StandardMaterial3D] = []
var _rng := RandomNumberGenerator.new()

func build(p_world: Node) -> void:
	world = p_world
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	var fan := Vector3(Layout.FAN.x, 1.92, Layout.FAN.z)
	var ctx: Dictionary = world.get(&"ctx") if world.get(&"ctx") is Dictionary else {}
	for l in ctx.get("meta", {}).get("lights", []):
		if String(l.get("name", "")) == "ceilingLight":
			fan = Vector3(l.position[0], l.position[1], l.position[2])
	ceiling = OmniLight3D.new()
	ceiling.name = "CeilingBulb"
	ceiling.position = fan
	ceiling.light_color = Color(1.0, 0.8, 0.6)
	ceiling.light_energy = CEIL_ENERGY
	ceiling.omni_range = 10.0
	ceiling.omni_attenuation = 1.2
	ceiling.shadow_enabled = true
	ceiling.light_size = 0.1          # ~ the frosted bowl: soft fan-housing shadow on the ceiling
	ceiling.shadow_bias = 0.03
	ceiling.shadow_normal_bias = 1.0
	add_child(ceiling)
	# nook tube
	var tube = world.get(&"nook_tube")
	tube_light = OmniLight3D.new()
	tube_light.name = "NookTubeLight"
	tube_light.position = (tube.get(&"tube_center") if tube is Node3D else Vector3(2.58, 2.43, -3.9)) + Vector3(0, -0.08, 0)
	tube_light.light_color = Color(0.86, 1.0, 0.92)
	tube_light.light_energy = TUBE_ENERGY
	tube_light.omni_range = 5.0
	tube_light.omni_attenuation = 1.3
	tube_light.shadow_enabled = true
	tube_light.light_size = 0.25
	add_child(tube_light)
	if tube is Node3D and tube.has_signal(&"level_changed"):
		tube.connect(&"level_changed", func(v: float) -> void: tube_light.light_energy = TUBE_ENERGY * v)
	# moonlight through the barred window (narrow, cold, far)
	moon = SpotLight3D.new()
	moon.name = "Moon"
	add_child(moon)
	moon.position = Vector3(4.824, 9.469, 14.383)
	moon.look_at(Vector3(1.794, 0.0, -0.464), Vector3.UP)
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 14.0
	moon.spot_range = 30.0
	moon.spot_angle = 4.5
	moon.spot_attenuation = 0.0
	moon.spot_angle_attenuation = 0.6
	moon.shadow_enabled = true
	moon.light_volumetric_fog_energy = 2.0
	# TV spill
	var tvp := Vector3(-0.55, 1.472, -2.316)
	var tvc = world.get(&"tv")
	if tvc is Object and tvc.get(&"screen_position") is Vector3: tvp = (tvc.get(&"screen_position") as Vector3) + Vector3(0, 0, 0.06)
	tv_light = SpotLight3D.new()
	tv_light.name = "TVSpill"
	add_child(tv_light)
	tv_light.position = tvp
	tv_light.look_at(tvp + Vector3(0, -0.12, 1.0), Vector3.UP)
	tv_light.light_color = Color(0.62, 0.76, 1.0)
	tv_light.light_energy = 0.0
	tv_light.spot_range = 7.0
	tv_light.spot_angle = 68.0
	tv_light.spot_angle_attenuation = 1.6
	tv_light.visible = false
	# hallway light behind the upstairs door (leaks under the 1.5 cm gap)
	door_light = OmniLight3D.new()
	door_light.name = "HallLeak"
	door_light.position = Vector3(-3.025, 2.95, -2.99)
	door_light.light_color = Color(1.0, 0.84, 0.59)
	door_light.light_energy = DOOR_ENERGY
	door_light.omni_range = 1.8
	door_light.shadow_enabled = true
	add_child(door_light)
	# emissive bowl / door strip (level.glb lighting meshes)
	_collect_emissive(ctx, "fanBowl", _bowl_mats)
	_collect_emissive(ctx, "doorStrip", _strip_mats)
	for m in _strip_mats: m.emission_energy_multiplier = 1.5
	_power = world.get(&"power") != false
	_apply_level()

func _collect_emissive(ctx: Dictionary, node_name: String, out: Array[StandardMaterial3D]) -> void:
	var mi = ctx.get("level_nodes", {}).get(node_name)
	if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null: return
	var m3 := mi as MeshInstance3D
	for s in m3.mesh.get_surface_count():
		var base := m3.get_active_material(s)
		if base is StandardMaterial3D:
			var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.emission_enabled = true
			if m.emission == Color(0, 0, 0): m.emission = Color(1.0, 0.75, 0.45)
			m3.set_surface_override_material(s, m)
			out.append(m)

func set_power(on: bool) -> void:
	_power = on
	_flash_t = 0.0
	_apply_level()

func blowout() -> void:
	Audio.play("light_pop", {"position": ceiling.position if ceiling else Vector3(0.25, 2.0, 0.35)})
	_flash_t = 0.07
	for i in 4: await get_tree().process_frame
	if world != null and world.get(&"power") != false: world.call("set_power", false)
	else: set_power(false)

func flicker(duration := 0.6, depth := 1.0) -> void:
	_flicker_t = maxf(_flicker_t, duration)
	_flicker_depth = clampf(depth, 0.0, 1.0)

func set_stress(_v: float) -> void: pass

func set_tv_light(on: bool, intensity := 1.0) -> void:
	_tv_target = intensity if on else 0.0

func door_strip_occluded(v: float) -> void:
	_door_occ = clampf(v, 0.0, 1.0)

func set_menu_mode(on: bool) -> void:
	_menu = on
	_apply_level()

func _process(dt: float) -> void:
	var changed := false
	if _flicker_t > 0.0:
		_flicker_t -= dt
		var lv := 1.0 - _flicker_depth * (0.9 if _rng.randf() < 0.45 else _rng.randf() * 0.5)
		_level = lv if _flicker_t > 0.0 else 1.0
		changed = true
	if _flash_t > 0.0:
		_flash_t -= dt
		changed = true
	if changed: _apply_level()
	if not is_equal_approx(_tv_level, _tv_target):
		_tv_level = move_toward(_tv_level, _tv_target, dt * 8.0)
		tv_light.light_energy = TV_ENERGY * _tv_level * (0.85 + 0.15 * _rng.randf())
		tv_light.visible = _tv_level > 0.001
	elif _tv_level > 0.001:
		tv_light.light_energy = TV_ENERGY * _tv_level * (0.85 + 0.15 * _rng.randf())
	door_light.light_energy = DOOR_ENERGY * (1.0 - 0.8 * _door_occ)

func _apply_level() -> void:
	if ceiling == null: return
	var lv := (_level if _power else 0.0) * (0.1 if _menu else 1.0)
	if _flash_t > 0.0: lv = 3.0
	ceiling.light_energy = CEIL_ENERGY * lv
	ceiling.visible = lv > 0.001
	for m in _bowl_mats: m.emission_energy_multiplier = BOWL_EMISSION * pow(maxf(lv, 0.0), 1.6)
	var tube = world.get(&"nook_tube") if world != null else null
	if tube_light != null:
		var tl := float(tube.get(&"level")) if tube is Node3D else (1.0 if _power else 0.0)
		tube_light.light_energy = TUBE_ENERGY * tl
