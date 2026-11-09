## Look module (ARCHITECTURE_PC.md §4 Look) — the basement's real lights. Port of src/world/Lighting.js (+ the web Details
## fluorescent tube light) on Godot lights. Photometry = the web's: luminous intensity (cd) × a camera exposure (EXPOSURE),
## in Godot's non-physical units (energy = cd × EXPOSURE / PI, inverse-square falloff — the player module's torch uses the
## same calibration), so the tonemapper (AgX, quality.gd) runs at exposure ~1 and the emissive / unshaded content (TV
## static, CRT, tube glass, mirror) keeps its designed level. Light colours: black body white-balanced like a camera at
## 3700 K (a 2700 K bulb reads warm, not orange; a dimming filament drifts toward 1900 K).
##   ceiling   OmniLight3D in the fan light kit (60 W incandescent): cube shadows, PCSS softness (light_size) on high+,
##             + the frosted bowl emission (level node fanBowl); fan blades / body never shadow it (no disc on the ceiling)
##   moon      SpotLight3D far outside through the high south window: bar shadows on the floor, strong volumetric-fog
##             energy (the light shaft on medium+; an analytic shaft mesh on low) + drifting dust motes in the beam
##   door      OmniLight3D behind the upstairs door: leaks under the 1.5 cm gap (+ the emissive strip, level node doorStrip,
##             with the "feet" occlusion of door_strip_occluded), becomes the hall pendant's light as the door opens
##   tv        SpotLight3D in front of the dresser CRT (cool flicker) — set_tv_light (world TV, UI menu)
##   tube      SpotLight3D under the nook fluorescent (follows world.nook_tube.level / level_changed: starter strikes,
##             ageing dips)
##   bounce    unshadowed fill at the bulb (low / medium only: stands in for SDFGI + SSIL)
##   fill      very low flat fill (readability floor in the dark; the environment ambient is replaced by SDFGI on high+)
## Rule: the light set is fixed at build; nothing at runtime adds / removes lights or toggles shadows (quality changes
## aside) — every state (off, flicker, blowout, stress, menu, TV) is energy only.
##
## Public API (keep): build(world) ; set_power(on) ; blowout() ; flicker(duration := 0.6, depth := 1.0) ; set_stress(v) ;
##   set_tv_light(on, intensity := 1.0) ; door_strip_occluded(v) ; set_menu_mode(on)
## Additions:
##   ceiling, moon, door_light, tv_light, tube_light, bounce, fill (lights), power, level (filament 0..1+, 5 at the
##   blowout pop), menu (0..1 eased), stress, apply_quality(q) (Quality.apply calls it), reset_after_caught(),
##   static kelvin(k) -> Color (linear, white-balanced), EXPOSURE (camera exposure folded into the light energies),
##   set_menu_mode(null) = automatic (game state menu / loading)
## Debug args (after --): --look-level=<0..1> (freeze the filament level), --look-menu (force the menu lighting)
extends Node3D

const Presets := preload("res://scripts/render/look_presets.gd")
const STRIP_SHADER := preload("res://shaders/look_doorstrip.gdshader")
const SHAFT_SHADER := preload("res://shaders/look_shaft.gdshader")
const MOTES_SHADER := preload("res://shaders/look_motes.gdshader")
const SPARKS_SHADER := preload("res://shaders/look_sparks.gdshader")
const SHAFT_FOG_SHADER := preload("res://shaders/look_shaftfog.gdshader")

# ---------------------------------------------------------------- photometry (web Lighting.js values)
const EXPOSURE := 0.11          # camera exposure for a ~15 lux room (folded into every light / emissive)
const CEIL_CD := 85.0           # 60 W A19 ≈ 800 lm ≈ 64 cd + the bowl's downward lobe
const BOWL_EMISSIVE := 75.0     # frosted bowl luminance
const MOON_CD := 3000.0         # cinematic moonlight (~9 lux on the floor patch)
const STRIP_CD := 2.4           # light leaking under the upstairs door
const HALL_CD := 30.0           # hall pendant once the door is open
const TV_CD := 7.0              # small CRT
const STRIP_GLOW := 45.0        # emissive gap line under the door
const TUBE_CD := 55.0           # nook fluorescent (web Details TUBE_LIGHT)
const WHITE_BALANCE := 3700.0
const MENU_LEVEL := 0.1         # filament level while the TV menu is up (a dimmed bulb glows orange)
const MENU_TV := 2.6            # TV light boost in the menu (the CRT is the key light)
const MENU_FILL := 0.75
const FILL_ON := 0.004          # flat fill (Godot energy, attenuation 0): power on (GI does the rest)
const FILL_OFF := 0.03          # power off: moonlit readability floor
const FILL_AMBIENT_FLOOR := 0.35  # environment ambient (low / medium) kept when the bulb is off (fraction of the preset)

# ---------------------------------------------------------------- geometry
const FAN_BOTTOM := 2.5 - 0.516                 # ceiling_fan model bottom (light kit)
const LIGHT_Y := FAN_BOTTOM - 0.065             # filament, inside the glass bowl
const MOON_DIR := Vector3(-0.2, -0.625, -0.98)  # direction of travel (normalised in code)
const HALL_LAMP_BULB := Vector3(-3.0, 4.7, -4.0)
const TUBE_POS := Vector3(1.95, 2.46, -3.85)
const GARDERIE_LAYERS := 1024 | 2048           # the soft-play area's render layers (scripts/garderie: corridor, hall)

# power-up flicker of the incandescent (web RAMP)
const RAMP := [[0.0, 0.0], [0.05, 0.9], [0.09, 0.04], [0.26, 0.0], [0.32, 0.65], [0.37, 0.08], [0.52, 0.0], [0.6, 1.0], [0.68, 0.4], [0.75, 1.0], [1.1, 1.0]]
const RAMP_END := 1.1

# volumetric fog energies (per light; the environment density lives in look_rig.gd)
const FOG_CEIL := 0.07
const FOG_MOON := 40.0
const FOG_DOOR := 1.2
const FOG_TV := 0.5
const FOG_TUBE := 14.0
const SHAFT_DUST := 0.35          # FogVolume density in the moonbeam (dust)
const NOOK_DUST := 0.09           # FogVolume density in the storage nook (the tube light reads as a shaft)

## Look-dev tunables (scripts/render/tests/lookdev.gd: set_tune({...}); --look-light=k:v;k:v). Defaults = the constants.
const TUNE_DEFAULTS := {
	"exposure": EXPOSURE, "ceil_cd": CEIL_CD, "bowl": BOWL_EMISSIVE, "moon_cd": MOON_CD, "strip_cd": STRIP_CD,
	"hall_cd": HALL_CD, "tv_cd": TV_CD, "strip_glow": STRIP_GLOW, "tube_cd": TUBE_CD, "fill_on": FILL_ON,
	"fill_off": FILL_OFF, "bounce_k": 1.0, "fog_ceil": FOG_CEIL, "fog_moon": FOG_MOON, "fog_door": FOG_DOOR,
	"fog_tv": FOG_TV, "fog_tube": FOG_TUBE, "ceil_size": 0.12, "moon_size": 0.06, "ceil_spec": 0.9, "wb": WHITE_BALANCE,
	"shaft_dust": SHAFT_DUST, "nook_dust": NOOK_DUST,
}

var world: Node = null
var ceiling: OmniLight3D = null
var moon: SpotLight3D = null
var door_light: OmniLight3D = null
var tv_light: SpotLight3D = null
var tube_light: SpotLight3D = null
var bounce: OmniLight3D = null
var fill: OmniLight3D = null
var power := true
var level := 1.0
var menu := 0.0
var stress := 0.0
var quality := "high"
var tune: Dictionary = TUNE_DEFAULTS.duplicate(true)

var _c2700 := Color(1, 1, 1)
var _c1900 := Color(1, 1, 1)
var _moon_dir := Vector3.ZERO
var _ramp := -1.0
var _flick_t := 0.0
var _flick_depth := 1.0
var _flick_timer := 0.0
var _flick_val := 1.0
var _stress_dip := 1.0
var _stress_timer := 0.0
var _flash_t := 0.0
var _tv_on := false
var _tv_base := 1.0
var _tv_level := 0.0
var _tv_target := 0.0
var _tv_timer := 0.0
var _occ := 0.0
var _occ_target := 0.0
var _menu_force: Variant = null
var _menu_settled := 0.0
var _time := 0.0
var _bowl_mats: Array[BaseMaterial3D] = []
var _fan_glow: Array = []          # [[material, base emission energy]] of the fan model's light kit
var _strip_mat: ShaderMaterial = null
var _hall_mats: Array[BaseMaterial3D] = []
var _strip_pos := Vector3.ZERO
var _tube_level := 1.0
var _bounce_k := 0.0
var _fill_sent := -1.0
var _shaft: MeshInstance3D = null
var _shaft_mat: ShaderMaterial = null
var _shaft_ap := Vector4.ZERO
var _shaft_fog: FogVolume = null
var _shaft_fog_mat: ShaderMaterial = null
var _nook_fog: FogVolume = null
var _nook_fog_mat: FogMaterial = null
var _motes: MultiMeshInstance3D = null
var _motes_mat: ShaderMaterial = null
var _sparks: MultiMeshInstance3D = null
var _sparks_mat: ShaderMaterial = null
var _spk_pos := PackedVector3Array()
var _spk_vel := PackedVector3Array()
var _spk_life := PackedFloat32Array()
var _spk_active := false
var _rng := RandomNumberGenerator.new()
var _dbg := {}
var _refresh_pending := false

# =================================================================== build

func build(p_world: Node) -> void:
	world = p_world
	name = "Lighting"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0].begins_with("look-"): _dbg[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _dbg.has("look-light"):
		var rig_script: Script = load("res://scripts/render/look_rig.gd")
		tune.merge(rig_script.call("parse_tune", String(_dbg["look-light"])), true)
	_c2700 = kelvin(2700.0, float(tune.wb))
	_c1900 = kelvin(1900.0, float(tune.wb))
	_moon_dir = MOON_DIR.normalized()
	quality = Presets.valid(String(Settings.get_value("quality", "high")))
	power = world.get(&"power") != false
	level = 1.0 if power else 0.0

	# ---- ceiling fan light kit (60 W incandescent in a frosted bowl)
	ceiling = OmniLight3D.new()
	ceiling.name = "CeilingBulb"
	ceiling.position = Vector3(Layout.FAN.x, LIGHT_Y, Layout.FAN.z)
	ceiling.omni_range = 14.0
	ceiling.omni_attenuation = 2.0
	ceiling.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	ceiling.shadow_enabled = true
	ceiling.shadow_bias = 0.04
	ceiling.shadow_normal_bias = 1.2
	add_child(ceiling)
	_prepare_fan()

	# ---- moonlight through the high south window (bar shadows, light shaft)
	var W: Dictionary = Layout.WINDOW
	var win_c := Vector3((W.minX + W.maxX) * 0.5, (W.minY + W.maxY) * 0.5, W.z)
	moon = SpotLight3D.new()
	moon.name = "Moon"
	add_child(moon)
	moon.position = win_c - _moon_dir * 14.0
	moon.look_at(win_c + _moon_dir * (win_c.y / -_moon_dir.y), Vector3.UP)
	moon.light_color = Color(0.42, 0.56, 1.0).linear_to_srgb()
	moon.spot_range = 32.0
	moon.spot_attenuation = 2.0
	moon.spot_angle = rad_to_deg(0.068)
	moon.spot_angle_attenuation = 0.55
	moon.shadow_enabled = true
	moon.shadow_bias = 0.02
	moon.shadow_normal_bias = 0.5
	moon.light_specular = 0.6
	_build_shaft(W)
	_build_motes()

	# ---- warm light behind the upstairs door (strip under the door / hall pendant when open)
	var UD: Dictionary = Layout.UPSTAIRS_DOOR
	_strip_pos = Vector3(UD.centerX, UD.bottomY + 0.2, UD.z - 0.24)
	door_light = OmniLight3D.new()
	door_light.name = "DoorLeak"
	door_light.position = _strip_pos
	door_light.light_color = _c2700.linear_to_srgb()
	door_light.omni_range = 1.6
	door_light.omni_attenuation = 2.0
	door_light.shadow_enabled = false
	add_child(door_light)
	_prepare_door_strip()
	_prepare_hall_lamp()

	# ---- TV light (cool, flickering)
	var sp := Vector3(-0.55, 1.472, -2.376)
	var tvc = world.get(&"tv")
	if tvc is Object and is_instance_valid(tvc) and tvc.get(&"screen_position") is Vector3: sp = tvc.get(&"screen_position")
	tv_light = SpotLight3D.new()
	tv_light.name = "TVLight"
	add_child(tv_light)
	tv_light.position = sp + Vector3(0, 0, 0.06)
	tv_light.look_at(Vector3(sp.x, sp.y - 0.35, sp.z + 3.0), Vector3.UP)
	tv_light.light_color = Color(0.62, 0.76, 1.0).linear_to_srgb()
	tv_light.light_energy = 0.0
	tv_light.spot_range = 7.0
	tv_light.spot_attenuation = 2.0
	tv_light.spot_angle = rad_to_deg(1.2)
	tv_light.spot_angle_attenuation = 0.6
	tv_light.shadow_bias = 0.03

	# ---- nook fluorescent (web Details TUBE_LIGHT; follows world.nook_tube)
	var tube = world.get(&"nook_tube")
	var tpos := TUBE_POS
	if tube is Node3D and tube.get(&"tube_center") is Vector3: tpos = (tube.get(&"tube_center") as Vector3) + Vector3(0, -0.04, 0)
	tube_light = SpotLight3D.new()
	tube_light.name = "TubeLight"
	add_child(tube_light)
	tube_light.position = tpos
	tube_light.look_at(Vector3(tpos.x, 0.0, tpos.z - 1.15), Vector3.UP)
	tube_light.light_color = Color(0.9, 1.0, 0.93).linear_to_srgb()
	tube_light.spot_range = 7.5
	tube_light.spot_attenuation = 2.0
	tube_light.spot_angle = rad_to_deg(1.35)
	tube_light.spot_angle_attenuation = 0.35
	tube_light.shadow_bias = 0.03
	tube_light.shadow_normal_bias = 1.0
	_tube_level = float(tube.get(&"level")) if tube is Node3D and tube.get(&"level") != null else (1.0 if power else 0.0)
	if tube is Node3D and tube.has_signal(&"level_changed"):
		tube.connect(&"level_changed", _on_tube_level)

	# ---- bounce stand-in (low / medium) and readability fill
	bounce = OmniLight3D.new()
	bounce.name = "BulbBounce"
	bounce.position = Vector3(Layout.FAN.x, 1.5, Layout.FAN.z)
	bounce.light_color = Color(1.0, 0.84, 0.66)
	bounce.omni_range = 9.0
	bounce.omni_attenuation = 0.9
	bounce.shadow_enabled = false
	bounce.light_specular = 0.0
	bounce.light_bake_mode = Light3D.BAKE_DISABLED
	bounce.light_volumetric_fog_energy = 0.0
	add_child(bounce)
	fill = OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(0.0, 1.5, 0.2)
	fill.light_color = Color(0.78, 0.82, 0.95)
	fill.omni_range = 7.5
	fill.omni_attenuation = 0.0
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	fill.light_bake_mode = Light3D.BAKE_DISABLED
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)
	# lights without shadows (or with shadows only on high+) never reach the garderie's render layers through the walls
	for l in [fill, bounce, door_light, tv_light, tube_light]:
		(l as Light3D).light_cull_mask = 0xFFFFF & ~GARDERIE_LAYERS

	_build_sparks()
	_prepare_emitters_gi()
	# menu lighting at boot (loading / menu), no ramp at the first frame
	var gs := String(Game.state)
	menu = 1.0 if (_dbg.has("look-menu") or ((gs == "menu" or gs == "loading") and not _autostart())) else 0.0
	if _dbg.has("look-menu"): _menu_force = true
	apply_quality(quality)
	_apply_level(level)

func _autostart() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--autostart" or a.begins_with("--shot"): return true
	return false

## Fan: neither the spinning blades nor the motor body shadow the bulb (PCF would turn them into a hard dark disc on the
## ceiling; the web clipped them with a shadow near plane). The bowl encloses the bulb: never a caster.
func _prepare_fan() -> void:
	var fan = _prop("fan")
	if fan is Node3D:
		for n in (fan as Node).find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the fan model's light-kit glass has its own emissive texture: it must follow the filament (dark when off)
		for n in (fan as Node).find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null: continue
			for si in mi.mesh.get_surface_count():
				var fm := mi.get_active_material(si)
				if fm is BaseMaterial3D and (fm as BaseMaterial3D).emission_enabled:
					var dup := (fm as BaseMaterial3D).duplicate() as BaseMaterial3D
					mi.set_surface_override_material(si, dup)
					_fan_glow.append([dup, dup.emission_energy_multiplier])
	var bowl := _level_node("fanBowl") as MeshInstance3D
	if bowl == null or bowl.mesh == null: return
	bowl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in bowl.mesh.get_surface_count():
		var base := bowl.get_active_material(s)
		var m: StandardMaterial3D = (base as StandardMaterial3D).duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
		m.emission_enabled = true
		m.emission_energy_multiplier = 0.0
		m.albedo_color = Color(0.95, 0.91, 0.84)
		m.roughness = 0.45
		bowl.set_surface_override_material(s, m)
		_bowl_mats.append(m)

## Door strip: the exported thin quad under the upstairs door gets an unshaded glow with the "feet" occlusion.
func _prepare_door_strip() -> void:
	var strip := _level_node("doorStrip") as MeshInstance3D
	if strip == null: return
	var UD: Dictionary = Layout.UPSTAIRS_DOOR
	_strip_mat = ShaderMaterial.new()
	_strip_mat.shader = STRIP_SHADER
	_strip_mat.set_shader_parameter("x0", float(UD.hingeX) + 0.025)
	_strip_mat.set_shader_parameter("x1", float(UD.hingeX) + float(UD.width) - 0.025)
	_strip_mat.set_shader_parameter("center_x", float(UD.centerX))
	_strip_mat.set_shader_parameter("tint", Vector3(_c2700.r, _c2700.g, _c2700.b))
	strip.material_override = _strip_mat
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Hall pendant (detail_hallLamp): its bulb carries the hall light; keep its emission in step with the door light.
func _prepare_hall_lamp() -> void:
	var lamp = _prop("detail_hallLamp")
	if not (lamp is Node3D): return
	for n in (lamp as Node).find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null: continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				mi.set_surface_override_material(s, d)
				_hall_mats.append(d)

## Emitters driven at runtime must not be baked into SDFGI's static emission (a dead bulb would keep glowing in the GI).
func _prepare_emitters_gi() -> void:
	var list: Array = [_level_node("fanBowl"), _level_node("doorStrip")]
	var tvc = world.get(&"tv")
	if tvc is Object and is_instance_valid(tvc) and tvc.get(&"screen") is GeometryInstance3D: list.append(tvc.get(&"screen"))
	list.append(_level_node("extra_crt_screen"))
	var tube = world.get(&"nook_tube")
	if tube is Node: list.append_array((tube as Node).find_children("*", "GeometryInstance3D", true, false))
	var web_tube = _prop("detail_tubeLight")
	if web_tube is Node: list.append_array((web_tube as Node).find_children("*", "GeometryInstance3D", true, false))
	for n in list:
		if n is GeometryInstance3D: (n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED

func _prop(key: String) -> Variant:
	var props = world.get(&"props")
	if props is Dictionary and (props as Dictionary).has(key): return (props as Dictionary)[key]
	var root = world.get(&"level_root")
	if root is Node:
		var n := (root as Node).find_child(key, true, false)
		if n != null: return n
	return null

func _level_node(key: String) -> Node:
	var ctx = world.get(&"ctx")
	if ctx is Dictionary:
		var ln = (ctx as Dictionary).get("level_nodes", {})
		if ln is Dictionary and (ln as Dictionary).get(key) is Node: return (ln as Dictionary)[key]
	var p = _prop(key)
	return p if p is Node else null

# ---------------------------------------------------------------- moon shaft (low preset) + dust motes

## Shaft prism: the window aperture (room face of the recess, limited by the stool) extruded along the moonlight down to
## the floor. Rendered with the analytic in-scattering shader (look_shaft.gdshader) only where there is no volumetric fog.
func _build_shaft(W: Dictionary) -> void:
	var d := _moon_dir
	var s := -d.y / -d.z
	var glass_z: float = float(W.z) + 0.25
	var glass_top: float = float(W.maxY) - 0.035
	var recess := glass_z - float(W.z)
	var y_top := glass_top - recess * s
	var y_bot := float(W.minY) + 0.04 * s
	var sx := d.x / -d.z
	var xa := maxf(float(W.minX), float(W.minX) + 0.035 + recess * sx)
	var xb := minf(float(W.maxX), float(W.maxX) - 0.035 + recess * sx)
	var wz := float(W.z)
	var top := [Vector3(xa, y_bot, wz), Vector3(xb, y_bot, wz), Vector3(xb, y_top, wz), Vector3(xa, y_top, wz)]
	var bot := []
	for p in top: bot.append((p as Vector3) + d * ((p as Vector3).y / -d.y))
	_shaft_ap = Vector4(xa, xb, y_bot, y_top)
	var centre := Vector3.ZERO
	for p in top + bot: centre += p
	centre /= 8.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(a: Vector3, b: Vector3, c: Vector3, e: Vector3) -> void:
		var n := (b - a).cross(e - a).normalized()
		var fc := (a + b + c + e) * 0.25
		if n.dot(fc - centre) < 0.0: n = -n
		for v in [a, b, c, a, c, e]:
			st.set_normal(n)
			st.add_vertex(v)
	for f in 4:
		quad.call(top[f], top[(f + 1) % 4], bot[(f + 1) % 4], bot[f])
	var lift := Vector3(0, 0.001, 0)
	quad.call(bot[0] + lift, bot[1] + lift, bot[2] + lift, bot[3] + lift)
	quad.call(top[0], top[1], top[2], top[3])
	_shaft = MeshInstance3D.new()
	_shaft.name = "MoonShaft"
	_shaft.mesh = st.commit()
	_shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shaft.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_shaft.extra_cull_margin = 2.0
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = SHAFT_SHADER
	_shaft_mat.set_shader_parameter("shaft_dir", d)
	_shaft_mat.set_shader_parameter("aperture", _shaft_ap)
	_shaft_mat.set_shader_parameter("win_z", wz)
	_shaft_mat.set_shader_parameter("s_floor", ((y_top + y_bot) * 0.5) / -d.y)
	_shaft_mat.set_shader_parameter("tint", Vector3(0.32, 0.4, 0.62))
	# dust in the beam for the volumetric fog (medium+): the moonlight shadow map carves the shaft out of it
	var bb := AABB(top[0], Vector3.ZERO)
	for p in top + bot: bb = bb.expand(p)
	bb = bb.grow(0.25)
	bb.position.y = maxf(bb.position.y, 0.0)
	_shaft_fog = FogVolume.new()
	_shaft_fog.name = "MoonDust"
	_shaft_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_shaft_fog.size = bb.size
	_shaft_fog.position = bb.get_center()
	_shaft_fog_mat = ShaderMaterial.new()
	_shaft_fog_mat.shader = SHAFT_FOG_SHADER
	_shaft_fog_mat.set_shader_parameter("shaft_dir", d)
	_shaft_fog_mat.set_shader_parameter("aperture", _shaft_ap)
	_shaft_fog_mat.set_shader_parameter("win_z", wz)
	_shaft_fog_mat.set_shader_parameter("s_floor", ((y_top + y_bot) * 0.5) / -d.y)
	_shaft_fog.material = _shaft_fog_mat
	add_child(_shaft_fog)
	# dusty storage nook: the fluorescent tube reads as a soft shaft
	var A: Dictionary = Layout.ALCOVE
	_nook_fog = FogVolume.new()
	_nook_fog.name = "NookDust"
	_nook_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_nook_fog.size = Vector3(float(A.maxX) - float(A.minX), 2.5, float(A.maxZ) - float(A.minZ))
	_nook_fog.position = Vector3((float(A.minX) + float(A.maxX)) * 0.5, 1.25, (float(A.minZ) + float(A.maxZ)) * 0.5)
	_nook_fog_mat = FogMaterial.new()
	_nook_fog_mat.albedo = Color(0.85, 0.86, 0.84)
	_nook_fog_mat.edge_fade = 0.35
	_nook_fog.material = _nook_fog_mat
	add_child(_nook_fog)
	_shaft.material_override = _shaft_mat
	add_child(_shaft)

## Dust motes floating in the moon beam (camera-facing additive specks, animated in the vertex shader).
func _build_motes() -> void:
	var n := 90
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = qm
	mm.instance_count = n
	var d := _moon_dir
	var ap := _shaft_ap
	var wz := float(Layout.WINDOW.z)
	for i in n:
		var t := _rng.randf() * 0.92
		var u := _rng.randf()
		var v := _rng.randf()
		var ptop := Vector3(lerpf(ap.x, ap.y, u), lerpf(ap.z, ap.w, v), wz)
		var pbot := ptop + d * (ptop.y / -d.y)
		var p := ptop.lerp(pbot, t)
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), 0, 0))
	_motes = MultiMeshInstance3D.new()
	_motes.name = "MoonDust"
	_motes.multimesh = mm
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_motes.extra_cull_margin = 1.0
	_motes_mat = ShaderMaterial.new()
	_motes_mat.shader = MOTES_SHADER
	_motes_mat.set_shader_parameter("tint", Vector3(0.55, 0.62, 0.8))
	_motes.material_override = _motes_mat
	add_child(_motes)

## Blowout sparks (CPU-simulated, drawn as small emissive billboards; dead sparks have size 0 — always drawn).
func _build_sparks() -> void:
	var n := 26
	_spk_pos.resize(n)
	_spk_vel.resize(n)
	_spk_life.resize(n)
	_spk_life.fill(0.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = qm
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), ceiling.position))
		mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	_sparks = MultiMeshInstance3D.new()
	_sparks.name = "Sparks"
	_sparks.multimesh = mm
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_sparks.extra_cull_margin = 3.0
	_sparks_mat = ShaderMaterial.new()
	_sparks_mat.shader = SPARKS_SHADER
	_sparks.material_override = _sparks_mat
	add_child(_sparks)

# =================================================================== quality

## Called by Quality.apply (scripts/render/quality.gd) and at build. Shadow softness / extra shadows / stand-ins per preset.
func apply_quality(q: String) -> void:
	quality = Presets.valid(q)
	var p: Dictionary = Presets.get_preset(quality)
	if ceiling == null: return
	var soft := bool(p.light_size)
	ceiling.light_size = float(tune.ceil_size) if soft else 0.0
	ceiling.shadow_blur = 1.0 if soft else 2.2
	moon.light_size = float(tune.moon_size) if soft else 0.0
	moon.shadow_blur = 1.0 if soft else 1.4
	if tv_light.shadow_enabled != bool(p.tv_shadow): tv_light.shadow_enabled = bool(p.tv_shadow)
	tv_light.light_size = 0.15 if soft else 0.0
	if tube_light.shadow_enabled != bool(p.tube_shadow): tube_light.shadow_enabled = bool(p.tube_shadow)
	tube_light.light_size = 0.3 if soft else 0.0
	tube_light.shadow_blur = 1.0 if soft else 2.0
	_bounce_k = float(p.bounce) * float(tune.bounce_k)
	_shaft.visible = bool(p.shaft_mesh)
	_shaft_fog.visible = bool(p.vfog)
	_nook_fog.visible = bool(p.vfog)
	_motes.visible = q != "low"
	_apply_static()
	_fill_sent = -1.0
	_apply_level(level)

## Constant light settings that only change with the tunables (fog energies, moonlight).
func _apply_static() -> void:
	_c2700 = kelvin(2700.0, float(tune.wb))
	_c1900 = kelvin(1900.0, float(tune.wb))
	door_light.light_color = _c2700.linear_to_srgb()
	if _strip_mat != null: _strip_mat.set_shader_parameter("tint", Vector3(_c2700.r, _c2700.g, _c2700.b))
	moon.light_energy = float(tune.moon_cd) * float(tune.exposure) / PI
	ceiling.light_volumetric_fog_energy = float(tune.fog_ceil)
	ceiling.light_specular = float(tune.ceil_spec)
	moon.light_volumetric_fog_energy = float(tune.fog_moon)
	door_light.light_volumetric_fog_energy = float(tune.fog_door)
	tv_light.light_volumetric_fog_energy = float(tune.fog_tv)
	tube_light.light_volumetric_fog_energy = float(tune.fog_tube)
	_shaft_fog_mat.set_shader_parameter("density", float(tune.shaft_dust))
	_nook_fog_mat.density = float(tune.nook_dust)

## Look-dev: merge tunables (TUNE_DEFAULTS keys) and re-apply.
func set_tune(d: Dictionary) -> void:
	tune.merge(d, true)
	apply_quality(quality)

# =================================================================== public API

func set_power(on: bool) -> void:
	var was := power
	power = on
	if ceiling == null: return
	if on and not was:
		_ramp = 0.0
		_refresh_pending = true
	if not on:
		_ramp = -1.0
		_flick_t = 0.0

## Bulb pop: white-hot flash, sparks, light_pop, a warm screen flash. Gameplay calls world.set_power(false) right after
## (the flash survives it); if nobody does within 4 frames, the power is cut here.
func blowout() -> void:
	if ceiling != null and power:
		_flash_t = 0.075
		_burst_sparks()
		Audio.play("light_pop", {"position": ceiling.global_position, "volume_db": 0.0})
		_quality_call("flash", [Color(1.0, 0.94, 0.82), 0.35, 0.22])
	for i in 4: await get_tree().process_frame
	if world != null and is_instance_valid(world) and world.get(&"power") != false and world.has_method("set_power"):
		world.call("set_power", false)

func flicker(d := 0.6, depth := 1.0) -> void:
	_flick_t = maxf(_flick_t, d)
	_flick_depth = clampf(depth, 0.0, 1.0)
	_flick_timer = 0.0

func set_stress(v: float) -> void:
	stress = clampf(v, 0.0, 1.0)

func set_tv_light(on: bool, i := 1.0) -> void:
	_tv_on = on
	_tv_base = maxf(0.0, i)

func door_strip_occluded(v: float) -> void:
	_occ_target = clampf(v, 0.0, 1.0)

## true = menu lighting (bulb on a faint dimmer, the CRT as key light), false = normal, null = automatic (menu / loading).
func set_menu_mode(on: Variant) -> void:
	_menu_force = null if on == null else bool(on)

func reset_after_caught() -> void:
	_flick_t = 0.0
	stress = 0.0
	_stress_dip = 1.0
	_flash_t = 0.0
	_occ_target = 0.0
	_spk_life.fill(0.0)
	_spk_active = false

## Black body -> linear RGB (Tanner Helland fit) divided by the camera white balance, normalised (web kelvin()).
static func kelvin(k: float, wb := WHITE_BALANCE) -> Color:
	var a := _bb(k)
	var w := _bb(wb)
	var r := a.r / w.r
	var g := a.g / w.g
	var b := a.b / w.b
	var m := maxf(r, maxf(g, b))
	return Color(r / m, g / m, b / m)

static func _bb(k: float) -> Color:
	var t := k / 100.0
	var r := 255.0
	var g := 0.0
	var b := 255.0
	if t <= 66.0:
		g = 99.4708 * log(t) - 161.1196
		b = 0.0 if t <= 19.0 else 138.5177 * log(t - 10.0) - 305.0448
	else:
		r = 329.6987 * pow(t - 60.0, -0.1332)
		g = 288.1222 * pow(t - 60.0, -0.0755)
	return Color(_lin(r), _lin(g), _lin(b))

static func _lin(v: float) -> float:
	v = clampf(v, 0.0, 255.0) / 255.0
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)

# =================================================================== frame

func _process(delta: float) -> void:
	if ceiling == null: return
	var dt := minf(delta, 0.1)
	_time += dt

	# ---- menu mode (TV menu): dimmer on the ceiling bulb, TV as the key light
	var gs := String(Game.state)
	var menu_on: bool = bool(_menu_force) if _menu_force != null else (gs == "menu" or gs == "loading")
	var mt := 1.0 if menu_on else 0.0
	menu += (mt - menu) * (1.0 - exp(-dt / (0.25 if mt > menu else 0.45)))
	if absf(menu - mt) < 1e-3: menu = mt
	# the room just came out of the menu lighting: re-capture the reflection probes once it settled
	if menu == 0.0 and _menu_settled > 0.0:
		_refresh_pending = true
	_menu_settled = menu

	# ---- ceiling filament
	var target := (1.0 if power else 0.0) * (1.0 + (MENU_LEVEL - 1.0) * menu)
	if _ramp >= 0.0:
		_ramp += dt
		var v := 1.0
		for i in range(RAMP.size() - 1, -1, -1):
			if _ramp >= float(RAMP[i][0]):
				v = float(RAMP[i][1])
				break
		target = v * (1.0 + (MENU_LEVEL - 1.0) * menu)
		if _ramp >= RAMP_END: _ramp = -1.0
	if power and _flick_t > 0.0:
		_flick_t -= dt
		_flick_timer -= dt
		if _flick_timer <= 0.0:
			_flick_timer = 0.025 + _rng.randf() * 0.09
			_flick_val = 1.0 - _flick_depth * (0.55 + 0.45 * _rng.randf()) if _rng.randf() < 0.55 else 1.0
		if _flick_t > 0.0: target *= _flick_val
	if power and stress > 0.02:
		_stress_timer -= dt
		if _stress_timer <= 0.0:
			var s := stress
			if _rng.randf() < 0.12 + 0.6 * s:
				_stress_dip = 1.0 - (0.25 + 0.75 * _rng.randf()) * s
				_stress_timer = 0.03 + _rng.randf() * 0.11
			else:
				_stress_dip = 1.0 - 0.04 * s * _rng.randf()
				_stress_timer = (0.12 + _rng.randf() * 0.7) * (1.4 - s)
		target *= _stress_dip
	else:
		_stress_dip = 1.0
	var tau := 0.035 if target > level else 0.07
	level += (target - level) * (1.0 - exp(-dt / tau))
	var lv := level
	if _flash_t > 0.0:
		_flash_t -= dt
		lv = 5.0
		if _flash_t <= 0.0: level = 0.3     # the filament is gone: fast fade from here
	if _dbg.has("look-level"): lv = clampf(float(_dbg["look-level"]), 0.0, 5.0)
	_apply_level(lv)

	# ---- moon: shaft (low preset mesh) + dust motes, stronger once the room is dark
	var dark := 1.0 - clampf(lv, 0.0, 1.0)
	if _shaft.visible:
		_shaft_mat.set_shader_parameter("intensity", 0.014 + 0.06 * dark)
		_shaft_mat.set_shader_parameter("time_s", _time)
		_shaft_mat.set_shader_parameter("inside", 1.0 if _camera_in_beam() else 0.0)
	if _motes.visible:
		_motes_mat.set_shader_parameter("time_s", _time)
		_motes_mat.set_shader_parameter("intensity", 0.5 + 1.1 * dark)

	# ---- door strip / hall light
	_occ += (_occ_target - _occ) * (1.0 - exp(-dt / 0.12))
	var open_t := 0.0
	var handles = world.get(&"handles")
	if handles is Dictionary:
		var h = (handles as Dictionary).get("door.upstairs")
		if h != null: open_t = clampf(float(h.get(&"t")), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, clampf(open_t * 1.6, 0.0, 1.0))
	door_light.position = _strip_pos.lerp(HALL_LAMP_BULB, e)
	door_light.omni_range = lerpf(1.6, 6.0, e)
	door_light.light_energy = (float(tune.strip_cd) * (1.0 - 0.7 * _occ) * (1.0 - e) + float(tune.hall_cd) * e) * float(tune.exposure) / PI
	if _strip_mat != null:
		_strip_mat.set_shader_parameter("energy", float(tune.strip_glow) * float(tune.exposure) * (1.0 - e))
		_strip_mat.set_shader_parameter("occ", _occ)
		_strip_mat.set_shader_parameter("time_s", _time)
	for m in _hall_mats: m.emission_energy_multiplier = 7.0

	# ---- TV
	var tv_on: bool = _tv_on and world.get(&"power") != false
	_tv_timer -= dt
	if _tv_timer <= 0.0:
		_tv_timer = 0.035 + _rng.randf() * 0.11
		_tv_target = 1.25 if _rng.randf() < 0.08 else 0.55 + _rng.randf() * 0.45
	_tv_level += ((_tv_target if tv_on else 0.0) - _tv_level) * minf(1.0, dt * 22.0)
	tv_light.light_energy = float(tune.tv_cd) * float(tune.exposure) / PI * _tv_base * _tv_level * (1.0 + (MENU_TV - 1.0) * menu)

	# ---- nook tube (signal-driven; also guard against a missed signal)
	tube_light.light_energy = float(tune.tube_cd) * float(tune.exposure) / PI * _tube_level

	if _dbg.has("look-off"):
		for n in String(_dbg["look-off"]).split(","):
			var lt = get(n)
			if lt is Light3D: (lt as Light3D).light_energy = 0.0
	_update_sparks(dt)
	if _refresh_pending and menu == 0.0 and _ramp < 0.0:
		_refresh_pending = false
		var refl = world.get(&"reflections")
		if refl != null and is_instance_valid(refl) and refl.has_method("refresh"): refl.call("refresh", 0.3)

## Push a filament level (0..1+) into the bulb, the bowl, the stand-ins and the readability fill.
func _apply_level(lv: float) -> void:
	var l := maxf(0.0, lv)
	# incandescent dimming: a cooling filament shifts toward 1900 K
	var col := _c2700.lerp(_c1900, clampf(1.0 - l, 0.0, 1.0) * 0.85)
	var srgb := col.linear_to_srgb()
	ceiling.light_color = srgb
	ceiling.light_energy = float(tune.ceil_cd) * float(tune.exposure) / PI * l
	for fg in _fan_glow: (fg[0] as BaseMaterial3D).emission_energy_multiplier = float(fg[1]) * pow(minf(l, 1.4), 1.6)
	for m in _bowl_mats:
		m.emission = srgb
		m.emission_energy_multiplier = float(tune.bowl) * float(tune.exposure) * pow(l, 1.6)
	bounce.light_color = srgb
	bounce.light_energy = float(tune.ceil_cd) * float(tune.exposure) / PI * minf(l, 1.4) * _bounce_k
	var lit := clampf(l, 0.0, 1.0)
	var menu_k := 1.0 + (MENU_FILL - 1.0) * menu
	fill.light_energy = lerpf(float(tune.fill_off), float(tune.fill_on), lit) * menu_k
	var amb := (FILL_AMBIENT_FLOOR + (1.0 - FILL_AMBIENT_FLOOR) * minf(l, 1.4)) * menu_k
	if absf(amb - _fill_sent) > 0.01:
		_fill_sent = amb
		_quality_call("set_fill", [amb])

func _on_tube_level(v: float) -> void:
	_tube_level = clampf(v, 0.0, 1.5)

func _quality_call(method: String, args: Array) -> void:
	var q := load("res://scripts/render/quality.gd") as Script
	if q != null and q.has_method(method): q.callv(method, args)

## Is the camera inside the moon shaft volume (window aperture extruded along the moonlight down to the floor)?
func _camera_in_beam() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null: return false
	var c := cam.global_position
	var d := _moon_dir
	var s := (c.z - float(Layout.WINDOW.z)) / d.z
	if s < 0.0 or c.y < 0.0: return false
	var u := c.x - s * d.x
	var v := c.y - s * d.y
	return u >= _shaft_ap.x and u <= _shaft_ap.y and v >= _shaft_ap.z and v <= _shaft_ap.w

func _burst_sparks() -> void:
	var c := ceiling.position
	for i in _spk_life.size():
		var a := _rng.randf() * TAU
		var sp := 0.4 + _rng.randf() * 1.4
		_spk_pos[i] = Vector3(c.x + cos(a) * 0.05, FAN_BOTTOM - 0.09, c.z + sin(a) * 0.05)
		_spk_vel[i] = Vector3(cos(a) * sp, -0.2 - _rng.randf() * 1.2, sin(a) * sp)
		_spk_life[i] = 0.5 + _rng.randf() * 0.7
	_spk_active = true

func _update_sparks(dt: float) -> void:
	if not _spk_active: return
	var mm := _sparks.multimesh
	var alive := 0
	for i in _spk_life.size():
		if _spk_life[i] <= 0.0:
			mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
			continue
		_spk_life[i] -= dt * 1.1
		var v := _spk_vel[i]
		v.y -= 9.8 * dt
		var p := _spk_pos[i] + v * dt
		if p.y < 0.01:
			p.y = 0.01
			v = Vector3(v.x * 0.5, -v.y * 0.25, v.z * 0.5)
			_spk_life[i] -= 0.15
		_spk_pos[i] = p
		_spk_vel[i] = v
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		mm.set_instance_custom_data(i, Color(maxf(_spk_life[i], 0.0), 0, 0, 0))
		if _spk_life[i] > 0.0: alive += 1
	if alive == 0: _spk_active = false
