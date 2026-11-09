## Living props (world module) — port of the runtime half of src/world/Props.js + ExtraProps.js, driven by
## level_meta.json `anim{}` (nodes + the web formulas):
##   fan            blades spin 2.4 rad/s with the mains (spin-up rate 0.45, coast-down 0.16)
##   alarm clock    keeps time from 03:07:12, the second hand ticks with an outBack snap (0.09 s)
##   grandfather    stopped clock; set_clue_digits({clock: d}) puts the hour hand on d o'clock (minute hand on 12)
##   rocking chair  rock(seconds): rocks by itself (amp 0.11 rad, period 1.75 s, 0.9 s ease-in, 2.2 s decay) + sound
##   clue decals    digit under the duck (marker) / under the horse's base (tape): textures/decals/digit_<style>_<d>.png
##   pull chain     the nook pull-chain sways (kick decays; kick(a) from the CRT beat)
##   smoke detector red LED blinks 0.09 s every 38–46 s
## Public: setup(world, ctx), set_power(on), rock(seconds) (await), stop_rocking(), set_clue_digits(d), kick_chain(a),
##   clock_hours (current clue hour or -1), rocking (bool), fan_speed, digits (Dictionary)
extends Node

const LevelLoader := preload("res://scripts/world/level_loader.gd")
const DECAL_TEX := "res://assets/generated/textures/decals/digit_%s_%s.png"

signal rock_finished

var world: Node = null
var digits := {}
var clock_hours := -1.0
var rocking := false
var fan_speed := 2.4

var _power := true
var _fan: Node3D = null
var _fan_cfg := {"speed": 2.4, "spinUpRate": 0.45, "spinDownRate": 0.16}
var _ac_hands := {}           # key -> {node, a0, base: Quaternion}
var _ac_time := 3.0 * 3600.0 + 7.0 * 60.0 + 12.0
var _ac_last_sec := -1
var _ac_tick := 1.0
var _gf := {}                 # hour/minute -> {node, a0}
var _rock := {}               # root, pivot, R, base (pivot position)
var _rock_t := 0.0
var _rock_dur := 0.0
var _rock_loop = null
var _chain: Node3D = null
var _chain_t := 0.0
var _chain_kick := 0.04
var _chain_pos := Vector3(1.8, 2.42, -3.6)
var _led_mat: StandardMaterial3D = null
var _led_t := 7.0
var _decals := {}             # duck / horse -> MeshInstance3D
var _decal_style := {"duck": "marker", "horse": "tape"}
var _rng := RandomNumberGenerator.new()

func setup(p_world: Node, ctx: Dictionary) -> void:
	world = p_world
	name = "PropsAnim"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	var anim: Dictionary = ctx.get("meta", {}).get("anim", {})
	# fan
	var fan: Dictionary = anim.get("fan", {})
	_fan = LevelLoader.find(ctx, fan.get("blades"))
	for k in ["speed", "spinUpRate", "spinDownRate"]:
		if fan.has(k): _fan_cfg[k] = float(fan[k])
	fan_speed = float(_fan_cfg.speed)
	# alarm clock
	var ac: Dictionary = anim.get("alarmClock", {}).get("hands", {})
	for k in ac:
		var n := LevelLoader.find(ctx, ac[k].get("node"))
		if n == null: continue
		var b: Array = ac[k].get("base", [0, 0, 0, 1])
		_ac_hands[k] = {"node": n, "a0": float(ac[k].get("a0", 0.0)), "base": Quaternion(b[0], b[1], b[2], b[3]).normalized()}
		# the hands tick every second: as shadow casters they made every light around them re-render its shadow map
		# once a second for a shadow nobody can see (millimetres, behind the glass)
		for g in [n] + n.find_children("*", "GeometryInstance3D", true, false):
			if g is GeometryInstance3D: (g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_alarm_clock(0.0, true)
	# grandfather clock (stopped at 10:10 until the clue digit is set)
	var gf: Dictionary = anim.get("grandfatherClock", {})
	for k in ["hour", "minute"]:
		var hd: Dictionary = gf.get(k, {})
		var n := LevelLoader.find(ctx, hd.get("node"))
		if n != null: _gf[k] = {"node": n, "a0": float(hd.get("a0", 0.0))}
	_set_gf_hands(10.0 + 10.0 / 60.0, 10.0)
	# rocking chair
	var rc: Dictionary = anim.get("rockingChair", {})
	var root := LevelLoader.find(ctx, rc.get("root"))
	var pivot := LevelLoader.find(ctx, rc.get("pivot"))
	if root != null and pivot != null:
		_rock = {"root": root, "pivot": pivot, "R": float(rc.get("radius", 0.95)), "base": pivot.position}
	# pull chain
	var pc: Dictionary = anim.get("pullChain", {})
	_chain = LevelLoader.find(ctx, pc.get("pivot"))
	if _chain != null:
		_chain_t = _rng.randf() * 10.0
		if _chain.is_inside_tree(): _chain_pos = _chain.global_position
	# smoke detector LED
	var led: Dictionary = anim.get("smokeDetectorLed", {})
	var led_node := LevelLoader.find(ctx, led.get("node")) as MeshInstance3D
	if led_node != null and led_node.mesh != null and led_node.mesh.get_surface_count() > 0:
		var base := led_node.get_active_material(0)
		_led_mat = (base.duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()) as StandardMaterial3D
		_led_mat.emission_enabled = true
		_led_mat.emission = Color.html(String(led.get("emissive", "#ff1a0a")))
		_led_mat.emission_energy_multiplier = 0.0
		led_node.material_override = _led_mat
	# clue decals (hidden until set_clue_digits)
	var cd: Dictionary = ctx.get("meta", {}).get("clueDecals", {})
	for key in cd:
		var d: Dictionary = cd[key]
		var parent := LevelLoader.find(ctx, d.get("parent"))
		if parent == null: continue
		var size: Array = d.get("size", [0.05, 0.05])
		var mi := MeshInstance3D.new()
		mi.name = "ClueDigit_" + String(key)
		var qm := QuadMesh.new()
		qm.size = Vector2(float(size[0]), float(size[1]))
		mi.mesh = qm
		mi.transform = LevelLoader.mat16(d.local)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = float(d.get("material", {}).get("roughness", 0.6))
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 4
		mi.material_override = m
		mi.visible = false
		parent.add_child(mi)
		_decals[key] = mi
		_decal_style[key] = String(d.get("style", _decal_style.get(key, "marker")))

func set_power(on: bool) -> void:
	_power = on

## Rocks the chair by itself for `seconds` (min 1.5 s); returns when it is still again.
func rock(seconds := 6.0) -> void:
	if _rock.is_empty(): return
	if rocking: rock_finished.emit()
	_rock_t = 0.0
	_rock_dur = maxf(1.5, seconds)
	rocking = true
	_stop_rock_loop(0.2)
	var p: Vector3 = (_rock.root as Node3D).global_position
	_rock_loop = Audio.loop("rocking_chair", {"position": Vector3(p.x, 0.5, p.z), "volume_db": linear_to_db(0.85)})
	await rock_finished

func stop_rocking() -> void:
	if _rock.is_empty(): return
	var was := rocking
	rocking = false
	(_rock.pivot as Node3D).rotation = Vector3.ZERO
	(_rock.pivot as Node3D).position = _rock.base
	_stop_rock_loop(0.6)
	if was: rock_finished.emit()

func set_clue_digits(d: Dictionary) -> void:
	for key in ["duck", "horse"]:
		if d.get(key) == null or not _decals.has(key): continue
		digits[key] = str(d[key])
		var p := DECAL_TEX % [_decal_style.get(key, "marker"), str(d[key]).substr(0, 1)]
		var mi: MeshInstance3D = _decals[key]
		if ResourceLoader.exists(p):
			(mi.material_override as StandardMaterial3D).albedo_texture = load(p)
			mi.visible = true
	if d.get("clock") != null:
		digits["clock"] = str(d.clock)
		var h := float(str(d.clock).to_int()) if str(d.clock).is_valid_int() else -1.0
		if h >= 0.0:
			clock_hours = h
			_set_gf_hands(h, 0.0)

func kick_chain(a := 0.09) -> void:
	_chain_kick = maxf(_chain_kick, a)

func _process(dt: float) -> void:
	# ceiling fan
	if _fan != null:
		var target: float = _fan_cfg.speed if _power else 0.0
		var rate: float = _fan_cfg.spinUpRate if _power else _fan_cfg.spinDownRate
		fan_speed += (target - fan_speed) * minf(1.0, dt * rate)
		if fan_speed < 0.004 and not _power: fan_speed = 0.0
		if fan_speed > 0.0: _fan.rotate_object_local(Vector3.UP, fan_speed * dt)
	_update_alarm_clock(dt)
	_update_rocking(dt)
	# pull chain (only when the camera is within 8 m)
	if _chain != null:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam == null or cam.global_position.distance_squared_to(_chain_pos) < 64.0:
			_chain_t += dt
			_chain_kick = maxf(0.012, _chain_kick * exp(-dt * 0.35))
			var a := _chain_kick
			_chain.rotation = Vector3(sin(_chain_t * 7.7 + 1.3) * a * 0.55, 0.0, sin(_chain_t * 8.2) * a + sin(_chain_t * 1.3) * 0.006)
	# smoke detector LED
	if _led_mat != null:
		_led_t -= dt
		if _led_t <= 0.0:
			_led_mat.emission_energy_multiplier = 6.0
			if _led_t < -0.09:
				_led_mat.emission_energy_multiplier = 0.0
				_led_t = 38.0 + _rng.randf() * 8.0

# ------------------------------------------------------------------ clocks

func _set_gf_hands(hours: float, minutes: float) -> void:
	var ha := PI / 2.0 - (fmod(hours, 12.0) / 12.0) * TAU
	var ma := PI / 2.0 - (fmod(minutes, 60.0) / 60.0) * TAU
	if _gf.has("hour"): _set_hand_z(_gf.hour.node, ha - float(_gf.hour.a0))
	if _gf.has("minute"): _set_hand_z(_gf.minute.node, ma - float(_gf.minute.a0))

func _set_hand_z(n: Node3D, z: float) -> void:
	n.rotation = Vector3(0.0, 0.0, z)    # web: rotation.z with x = y = 0 (scale kept)

func _set_ac_hand(key: String, angle: float) -> void:
	if not _ac_hands.has(key): return
	var hd: Dictionary = _ac_hands[key]
	var n: Node3D = hd.node
	n.quaternion = Quaternion(Vector3(0, 0, 1), angle - float(hd.a0)) * (hd.base as Quaternion)

func _update_alarm_clock(dt: float, force := false) -> void:
	if _ac_hands.is_empty(): return
	_ac_time += dt
	var t := _ac_time
	var sec := int(floor(t)) % 60
	if sec != _ac_last_sec:
		_ac_last_sec = sec
		_ac_tick = 0.0
		force = true
	if _ac_tick < 1.0:
		_ac_tick = minf(1.0, _ac_tick + dt / 0.09)
		force = true
	if not force: return
	var k := Handle.ease_curve("outBack", _ac_tick)
	var sec_a := PI / 2.0 - ((float(sec) - 1.0 + k) / 60.0) * TAU
	var minutes := fmod(t / 60.0, 60.0)
	var hours := fmod(t / 3600.0, 12.0)
	_set_ac_hand("s", sec_a)
	_set_ac_hand("m", PI / 2.0 - (minutes / 60.0) * TAU)
	_set_ac_hand("h", PI / 2.0 - (hours / 12.0) * TAU)

# ------------------------------------------------------------------ rocking chair

func _update_rocking(dt: float) -> void:
	if not rocking or _rock.is_empty(): return
	_rock_t += dt
	var w := TAU / 1.75
	var decay := 2.2
	var amp := 0.11
	if _rock_t < 0.9: amp = 0.11 * Handle.ease_curve("out", _rock_t / 0.9)
	elif _rock_t > _rock_dur - decay: amp = 0.11 * maxf(0.0, (_rock_dur - _rock_t) / decay)
	var th := amp * sin(w * _rock_t)
	var pivot: Node3D = _rock.pivot
	pivot.rotation = Vector3(th, 0.0, 0.0)
	var base: Vector3 = _rock.base
	pivot.position = Vector3(base.x, base.y, base.z + float(_rock.R) * th)
	if _rock_t >= _rock_dur: stop_rocking()

func _stop_rock_loop(fade: float) -> void:
	if _rock_loop != null and _rock_loop is Object and (_rock_loop as Object).has_method("stop"): _rock_loop.stop(fade)
	_rock_loop = null
