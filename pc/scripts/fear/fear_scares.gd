## Fear module — the scare repertoire: catalogue (pacing data) + eligibility/weights by context + executors.
## Minor = cheap false alarm (most of them); major = spike (glimpses, fake-out jump scares, big ceiling run).
## weight(id, c) -> 0 when the scare cannot happen now (wrong place, entity awake, cooldown handled by the pacer...).
## run(id, c) -> spike length in seconds for majors (0 for minors). Every effect goes through the director's helpers
## (sfx / after / kick / flinch / look_call / light_call / mix), so tests can run the whole catalogue against fakes.
extends RefCounted

const STAGES := ["intro", "dark", "power", "code", "escape", "win"]

## id: major, w = base weight, cd = cooldown (s), st = first stage index, modal = may fire while a note / keypad is open
const CATALOG := {
	# ---- false alarms
	"creak": {"major": false, "w": 3.0, "cd": 25.0, "st": 0, "modal": true},
	"distant": {"major": false, "w": 1.6, "cd": 60.0, "st": 0, "modal": true},
	"flicker": {"major": false, "w": 1.4, "cd": 50.0, "st": 0},
	"rumble_swell": {"major": false, "w": 1.0, "cd": 90.0, "st": 0, "modal": true},
	"knock_wall": {"major": false, "w": 2.0, "cd": 55.0, "st": 1, "modal": true},
	"knock_ceiling": {"major": false, "w": 1.5, "cd": 70.0, "st": 1, "modal": true},
	"ceiling_steps": {"major": false, "w": 1.8, "cd": 80.0, "st": 1, "modal": true},
	"giggle": {"major": false, "w": 1.2, "cd": 110.0, "st": 1},
	"whisper_back": {"major": false, "w": 1.4, "cd": 120.0, "st": 1, "modal": true},
	"door_handle": {"major": false, "w": 1.0, "cd": 150.0, "st": 1},
	"breath_neck": {"major": false, "w": 2.5, "cd": 110.0, "st": 1},
	"rocking": {"major": false, "w": 1.0, "cd": 150.0, "st": 1},
	"torch_stutter": {"major": false, "w": 1.0, "cd": 70.0, "st": 1},
	"chain_sway": {"major": false, "w": 0.6, "cd": 120.0, "st": 1},
	"garderie_scare": {"major": false, "w": 2.2, "cd": 70.0, "st": 1},
	"scratch_wall": {"major": false, "w": 1.0, "cd": 120.0, "st": 2, "modal": true},
	"hum_walls": {"major": false, "w": 0.9, "cd": 160.0, "st": 2},
	"window_tap": {"major": false, "w": 0.6, "cd": 120.0, "st": 2},
	"crt_static": {"major": false, "w": 0.8, "cd": 160.0, "st": 2},
	# ---- spikes
	"glimpse_stairs": {"major": true, "w": 2.0, "cd": 260.0, "st": 1},
	"glimpse_corridor": {"major": true, "w": 2.0, "cd": 260.0, "st": 1},
	"glimpse_mirror": {"major": true, "w": 3.0, "cd": 320.0, "st": 2},
	"glimpse_louvers": {"major": true, "w": 4.0, "cd": 220.0, "st": 1},
	"glimpse_dark": {"major": true, "w": 2.0, "cd": 220.0, "st": 1},
	"fake_shelf": {"major": true, "w": 2.0, "cd": 330.0, "st": 1},
	"fake_ball": {"major": true, "w": 1.6, "cd": 330.0, "st": 1},
	"bulb_pop": {"major": true, "w": 1.2, "cd": 380.0, "st": 2},
	"ceiling_run": {"major": true, "w": 1.2, "cd": 300.0, "st": 2},
}

const R := Layout.ROOM
const LANDING_FEET := Vector3(-3.0, 2.75, -2.22)
const CORRIDOR_FEET := Vector3(-10.25, 0.0, 2.1)
const MIRROR_C := Vector3(0.47, 1.62, -2.72)
const MIRROR_N := Vector3(0.0, 0.0, 1.0)
const CLOSET_OUT := Vector3(-1.72, 0.0, -2.05)
const TUNNEL_OUT := Vector3(-20.9, 0.0, -1.2)
const STAIRS_TOP_BALL := Vector3(-3.0, 2.97, -2.05)
const STAIRS_BOTTOM := Vector3(-3.0, 0.0, 1.95)
const CEILING_LIGHT := Vector3(0.25, 2.02, 0.35)
const OLD_CRT := Vector3(2.55, 0.45, -4.2)
const CHAIN := Vector3(1.8, 2.3, -3.6)
const HALL_UP := Vector3(-3.0, 3.9, -3.7)
## dark spots for glimpse_dark: nav nodes of the basement floor (doorways and corners first)
const DARK_SPOTS := [Vector3(1.35, 0.0, -2.45), Vector3(2.6, 0.0, -1.75), Vector3(2.35, 0.0, 0.15), Vector3(-2.2, 0.0, 2.1),
	Vector3(-1.0, 0.0, 0.0), Vector3(1.95, 0.0, 1.0), Vector3(1.55, 0.0, 1.25), Vector3(-0.6, 0.0, -1.55),
	Vector3(-3.0, 0.0, 2.05), Vector3(1.35, 0.0, -3.5), Vector3(2.7, 0.0, -3.6), Vector3(-2.0, 0.0, -1.9)]
## furniture tops a box can be knocked off: [top point, push direction (into the room)]
const SHELVES := [
	[Vector3(2.15, 1.5, -2.6), Vector3(0.0, 0.0, 1.0)],      # painted shelves (north wall)
	[Vector3(-0.15, 1.22, -2.42), Vector3(0.0, 0.0, 1.0)],   # dresser top, beside the TV
	[Vector3(3.15, 0.97, -0.55), Vector3(-1.0, 0.0, 0.0)],   # console (east wall)
	[Vector3(-1.5, 0.62, 2.45), Vector3(0.0, 0.0, -1.0)],    # end table by the sofa
	[Vector3(0.75, 1.2, -4.3), Vector3(0.0, 0.0, 1.0)],      # nook cabinet top
	[Vector3(3.36, 1.1, -3.4), Vector3(-1.0, 0.0, 0.0)],     # nook shelf
]

var d = null
var _rng := RandomNumberGenerator.new()


func _init(director, seed_value := 0) -> void:
	d = director
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func is_major(id: String) -> bool:
	return bool(CATALOG.get(id, {}).get("major", false))


func cooldown(id: String) -> float:
	return float(CATALOG.get(id, {}).get("cd", 60.0))


# ================================================================================================ eligibility
## 0 = not now. c = director context.
func weight(id: String, c: Dictionary) -> float:
	var e: Dictionary = CATALOG.get(id, {})
	if e.is_empty() or int(c.get("stage_i", 0)) < int(e.st):
		return 0.0
	if c.get("modal", false) and not e.get("modal", false):
		return 0.0
	if c.get("ent_state", "dormant") != "dormant":
		return 0.0                                   # never blur the real cues of a visit
	var w := float(e.w)
	var house: bool = c.get("in_house", false)
	var garderie: bool = c.get("in_garderie", false)
	var hidden: bool = c.get("hidden", false)
	var dark: bool = c.get("dark", false)
	var sk := float(c.get("stage_k", 0.0))
	if hidden and not (id in ["breath_neck", "glimpse_louvers", "knock_wall", "knock_ceiling", "ceiling_steps", "creak",
			"scratch_wall", "distant", "hum_walls", "rumble_swell"]):
		return 0.0
	match id:
		"creak", "distant", "rumble_swell":
			pass
		"flicker":
			if not ((c.get("power", true) and house) or (dark and c.get("torch_on", false))):
				return 0.0
		"knock_wall", "knock_ceiling", "ceiling_steps", "scratch_wall", "window_tap":
			if not house:
				return 0.0
		"giggle":
			if not (house or garderie) or d.garderie() == null and not house:
				return 0.0
		"whisper_back":
			if not (house or garderie):
				return 0.0
			if float(c.get("still_t", 0.0)) < 1.2 or not (c.get("wall_ahead", false) or c.get("modal", false)):
				return 0.0
			w *= 2.0
		"door_handle":
			var door = d.handle("door.upstairs")
			if not house or door == null or door.get("is_open") == true or float(c.get("feet", Vector3.ZERO).y) > 1.0:
				return 0.0
		"breath_neck":
			if hidden:
				if float(c.get("hidden_t", 0.0)) < 4.0:
					return 0.0
				w *= 2.5
			elif not (dark and not c.get("torch_on", false) and float(c.get("still_t", 0.0)) > 6.0):
				return 0.0
		"rocking":
			if not house or not d.pflag("rocked") or d.world_anim_bool("rocking"):
				return 0.0
			var rp: Vector3 = Vector3(2.55, 0.6, 1.95)
			if c.eye.distance_to(rp) > 7.0 or d.looks_at(rp, 0.6, 9.0, false):
				return 0.0
		"torch_stutter":
			if not (dark and c.get("torch_on", false)) or not d.player_has("flashlight_stutter"):
				return 0.0
		"chain_sway":
			if not c.get("in_nook", false):
				return 0.0
		"garderie_scare":
			if not garderie or d.garderie() == null:
				return 0.0
		"hum_walls":
			if not (house or garderie):
				return 0.0
		"crt_static":
			var crt = d.world_get("crt")
			if not house or not c.get("power", true) or crt == null or crt.get("active") == true or c.eye.distance_to(OLD_CRT) > 8.0:
				return 0.0
		"glimpse_stairs":
			if not house or float(c.get("feet", Vector3.ZERO).y) > 0.5:
				return 0.0
			var hd := LANDING_FEET + Vector3(0, 1.62, 0)
			var dist: float = c.eye.distance_to(hd)
			if dist < 3.5 or dist > 9.0 or d.looks_at(hd, 0.55, 99.0, false) or d.line_blocked(c.eye, hd):
				return 0.0
		"glimpse_corridor":
			if d.garderie() == null:
				return 0.0
			var hd := CORRIDOR_FEET + Vector3(0, 1.62, 0)
			var e2: Vector3 = c.eye
			if not ((house and e2.x < -1.2 and e2.z > 0.9) or (garderie and e2.x > -7.0 and e2.z > 1.3 and e2.z < 2.9)):
				return 0.0
			if d.looks_at(hd, 0.55, 99.0, false) or d.line_blocked(e2, hd) or e2.distance_to(hd) < 4.0:
				return 0.0
		"glimpse_mirror":
			var refl = d.world_get("reflections")
			if not house or refl == null or refl.get("mirror_active") != true:
				return 0.0
			if not d.looks_at(MIRROR_C, 0.9, 3.4, false) or float(c.get("still_t", 0.0)) < 0.5:
				return 0.0
			if mirror_spot(c) == Vector3.INF:
				return 0.0
			w *= 3.0
		"glimpse_louvers":
			if not hidden or float(c.get("hidden_t", 0.0)) < 3.0:
				return 0.0
			w *= 3.0
		"glimpse_dark":
			if not house or not dark or not c.get("torch_on", false) or dark_spot(c) == Vector3.INF:
				return 0.0
			w *= 1.5
		"fake_shelf":
			if not house or shelf_spot(c).is_empty():
				return 0.0
		"fake_ball":
			if not house or float(c.get("feet", Vector3.ZERO).y) > 0.5:
				return 0.0
			var to_st: float = Vector2(c.eye.x - STAIRS_BOTTOM.x, c.eye.z - STAIRS_BOTTOM.z).length()
			if to_st < 1.3 or to_st > 5.5 or d.line_blocked(c.eye, Vector3(-3.0, 1.3, 0.2)):
				return 0.0
		"bulb_pop":
			if not house or not c.get("power", true) or c.eye.distance_to(CEILING_LIGHT) > 4.5 or c.get("in_nook", false):
				return 0.0
		"ceiling_run":
			if not house or float(c.get("feet", Vector3.ZERO).y) > 1.0:
				return 0.0
	# context: darker, later and nastier for the spikes; audio false alarms like the player's back turned
	if e.major:
		w *= 0.6 + sk
		if float(c.get("solved_t", 99.0)) < 12.0:
			w *= 1.6
		if dark:
			w *= 1.3
	elif dark:
		w *= 1.2
	return w


# ================================================================================================ executors
func run(id: String, c: Dictionary) -> float:
	match id:
		"creak": return _creak(c)
		"distant": return _distant(c)
		"flicker": return _flicker(c)
		"rumble_swell": return _rumble_swell(c)
		"knock_wall": return _knock_wall(c)
		"knock_ceiling": return _knock_ceiling(c)
		"ceiling_steps": return _ceiling_steps(c)
		"giggle": return _giggle(c)
		"whisper_back": return _whisper_back(c)
		"door_handle": return _door_handle(c)
		"breath_neck": return _breath_neck(c)
		"rocking": return _rocking(c)
		"torch_stutter": return _torch_stutter(c)
		"chain_sway": return _chain_sway(c)
		"garderie_scare": return _garderie_scare(c)
		"scratch_wall": return _scratch_wall(c)
		"hum_walls": return _hum_walls(c)
		"window_tap": return _window_tap(c)
		"crt_static": return _crt_static(c)
		"glimpse_stairs": return _glimpse_stairs(c)
		"glimpse_corridor": return _glimpse_corridor(c)
		"glimpse_mirror": return _glimpse_mirror(c)
		"glimpse_louvers": return _glimpse_louvers(c)
		"glimpse_dark": return _glimpse_dark(c)
		"fake_shelf": return _fake_shelf(c)
		"fake_ball": return _fake_ball(c)
		"bulb_pop": return _bulb_pop(c)
		"ceiling_run": return _ceiling_run(c)
	return -1.0


# ------------------------------------------------------------------------------------------------ positions
func _rf(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


func _clamp_room(p: Vector3, margin := 0.3) -> Vector3:
	return Vector3(clampf(p.x, float(R.minX) + margin, float(R.maxX) - margin), p.y,
		clampf(p.z, float(R.minZ) + margin, float(R.maxZ) - margin))


## A point just inside a wall of the basement (Z_WALL zone: muffled), behind the player when possible.
func _wall_point(c: Dictionary, behind: bool) -> Vector3:
	var e: Vector3 = c.eye
	var f: Vector3 = c.fwd
	var cands := [
		Vector3(float(R.maxX) + 0.22, _rf(0.7, 1.7), clampf(e.z + _rf(-1.0, 1.0), -2.4, 2.4)),
		Vector3(float(R.minX) - 0.22, _rf(0.7, 1.7), clampf(e.z + _rf(-1.0, 1.0), 1.7, 2.5)),
		Vector3(clampf(e.x + _rf(-1.0, 1.0), -2.3, 3.2), _rf(0.7, 1.7), float(R.maxZ) + 0.22),
		Vector3(clampf(e.x + _rf(-1.0, 1.0), -2.4, 0.6), _rf(0.7, 1.7), float(R.minZ) - 0.22),
	]
	var best := Vector3.INF
	var best_s := INF
	for p in cands:
		var to: Vector3 = p - e
		var s: float = to.length()
		if behind and Vector2(f.x, f.z).dot(Vector2(to.x, to.z).normalized()) > -0.1:
			s += 6.0
		if s < best_s:
			best_s = s
			best = p
	return best


func _ceiling_above(c: Dictionary, spread: float) -> Vector3:
	var e: Vector3 = c.eye
	return _clamp_room(Vector3(e.x + _rf(-spread, spread), float(R.ceilingY) + 0.35, e.z + _rf(-spread, spread)), 0.4)


func _behind(c: Dictionary, dist: float, side: float, dy := 0.0) -> Vector3:
	var f: Vector3 = c.fwd
	var fl := Vector3(f.x, 0.0, f.z).normalized() if Vector2(f.x, f.z).length() > 0.05 else Vector3(0, 0, -1)
	var right := Vector3(-fl.z, 0.0, fl.x)
	return c.eye - fl * dist + right * side + Vector3(0.0, dy, 0.0)


func mirror_spot(c: Dictionary) -> Vector3:
	var e: Vector3 = c.eye
	var away := Vector3(e.x - MIRROR_C.x, 0.0, e.z - MIRROR_C.z)
	if away.length() < 0.2:
		return Vector3.INF
	away = away.normalized()
	for k in [1.1, 1.4, 1.7]:
		var p: Vector3 = Vector3(e.x, 0.0, e.z) + away * float(k)
		if p.x < -2.4 or p.x > 3.1 or p.z < -2.2 or p.z > 2.3:
			continue
		if d.line_blocked(p + Vector3(0, 1.6, 0), MIRROR_C):
			continue
		return p
	return Vector3.INF


func dark_spot(c: Dictionary) -> Vector3:
	var e: Vector3 = c.eye
	var best := Vector3.INF
	var best_s := -INF
	for p in DARK_SPOTS:
		var hd: Vector3 = p + Vector3(0, 1.62, 0)
		var dist := e.distance_to(hd)
		if dist < 3.0 or dist > 7.5:
			continue
		if d.looks_at(hd, 0.3, 99.0, false) or d.line_blocked(e, hd):
			continue
		var s := -absf(dist - 5.0) + _rf(0.0, 1.5)
		if s > best_s:
			best_s = s
			best = p
	return best


func shelf_spot(c: Dictionary) -> Array:
	var e: Vector3 = c.eye
	var best: Array = []
	var best_s := INF
	for sp in SHELVES:
		var p: Vector3 = sp[0]
		var dist := Vector2(p.x - e.x, p.z - e.z).length()
		if dist < 1.8 or dist > 4.8:
			continue
		if (p.z < float(R.minZ) - 0.1) != c.get("in_nook", false):
			continue
		var s := absf(dist - 3.0)
		if d.looks_at(p, 0.7, 99.0, false):
			s += 2.0                             # prefer it falling off-screen (side / behind)
		if s < best_s:
			best_s = s
			best = sp
	return best


# ------------------------------------------------------------------------------------------------ false alarms
func _creak(c: Dictionary) -> float:
	var p: Vector3 = _ceiling_above(c, 2.5) if _rng.randf() < 0.6 else _wall_point(c, _rng.randf() < 0.6)
	if c.get("in_garderie", false):
		p = c.eye + Vector3(_rf(-4, 4), _rf(0.5, 2.0), _rf(-3, 3))
	d.sfx("house_creak", p, _rf(0.55, 0.95))
	if _rng.randf() < 0.4:
		var p2 := p + Vector3(_rf(-0.8, 0.8), 0.0, _rf(-0.8, 0.8))
		d.after(_rf(1.1, 2.6), func() -> void: d.sfx("house_creak", p2, _rf(0.4, 0.6)))
	d.kick(0.1)
	return 0.0


func _distant(c: Dictionary) -> float:
	var spots := [HALL_UP, Vector3(1.0, 3.7, 0.6), Vector3(-1.5, 3.6, -1.0), Vector3(3.9, 1.0, 3.3)]
	if d.garderie() != null:
		spots.append(Vector3(-14.0, 1.2, 2.0))
	if c.get("in_garderie", false):
		spots = [Vector3(-30.0, 0.5, 6.0), Vector3(-36.0, 0.0, -3.0), HALL_UP, Vector3(-7.4, 1.0, 2.1)]
	d.sfx("fear_distant", spots[_rng.randi() % spots.size()], _rf(0.6, 0.9))
	d.kick(0.12)
	return 0.0


func _flicker(c: Dictionary) -> float:
	if c.get("power", true) and c.get("in_house", false):
		d.light_call("flicker", [_rf(0.35, 0.9), _rf(0.6, 1.0)])
		if _rng.randf() < 0.35:
			d.after(_rf(1.0, 2.2), func() -> void: d.light_call("flicker", [_rf(0.2, 0.4), 1.0]))
	else:
		d.torch_stutter(_rf(0.3, 0.6))
	d.kick(0.15)
	return 0.0


func _rumble_swell(_c: Dictionary) -> float:
	d.mix.swell_for(0.85, 7.0)
	d.mix.silence_for(0.55, 1.6, 3.5, 3.0)
	d.kick(0.06)
	return 0.0


func _knock_wall(c: Dictionary) -> float:
	var p := _wall_point(c, true)
	var n := 1 + _rng.randi() % 2
	var dt := 0.0
	for i in n:
		var pi := p + Vector3(0.0, _rf(-0.1, 0.1), _rf(-0.2, 0.2))
		var v := _rf(0.55, 0.8) * (1.0 if i == 0 else 0.85)
		d.after(dt, func() -> void:
			d.sfx("knock_wall", pi, v, {"filter_hz": 1500.0})
			d.kick(0.3))
		dt += _rf(2.6, 3.6)
	return 0.0


func _knock_ceiling(c: Dictionary) -> float:
	var p := _ceiling_above(c, 0.6)
	d.sfx("knock_wall", p, _rf(0.75, 0.95))
	d.kick(0.32)
	if _rng.randf() < 0.45:
		var p2 := p + Vector3(_rf(-0.5, 0.5), 0.0, _rf(-0.5, 0.5))
		d.after(_rf(3.0, 4.5), func() -> void: d.sfx("knock_wall", p2, 0.7))
	return 0.0


func _ceiling_steps(c: Dictionary) -> float:
	var e: Vector3 = c.eye
	var ang := _rf(0.0, TAU)
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var y := float(R.ceilingY) + 0.4
	var a := _clamp_room(Vector3(e.x, y, e.z) + dir * 2.8, 0.4)
	var b := _clamp_room(Vector3(e.x, y, e.z) - dir * 2.8, 0.4)
	var stop_above := _rng.randf() < 0.45
	var n := 6 + _rng.randi() % 3
	var t := 0.0
	for i in n:
		var k := float(i) / float(n - 1)
		if stop_above:
			k *= 0.5                                   # walks to right above the player... and stops
		var p := a.lerp(b, k)
		var v := 0.6 + 0.3 * (1.0 - absf(k - 0.5) * 2.0)
		d.after(t, func() -> void:
			d.sfx("ceiling_steps", p, v)
			d.kick(0.06))
		t += _rf(0.58, 0.74)
	if stop_above:
		d.after(t + 0.2, func() -> void: d.mix.silence_for(0.6, 0.4, 2.5, 2.5))
	return 0.0


func _giggle(c: Dictionary) -> float:
	if c.get("in_garderie", false) and d.garderie() != null and d.garderie().has_method("scare"):
		d.garderie().call("scare", "giggle_slide")
	else:
		var p: Vector3 = Vector3(-4.6, 0.9, 2.1) if d.garderie() != null else [Vector3(-2.3, 1.0, 2.4), Vector3(3.2, 1.0, -2.4), Vector3(1.35, 1.0, -3.8)][_rng.randi() % 3]
		d.sfx("giggle", p, _rf(0.45, 0.6))
	d.say("(Un rire d’enfant…)", 2.5)
	d.kick(0.35)
	return 0.0


func _whisper_back(c: Dictionary) -> float:
	var side := -0.16 if _rng.randf() < 0.5 else 0.16
	d.sfx("whisper", _behind(c, 0.42, side, 0.02), _rf(0.55, 0.7))
	d.say("(Un chuchotement, juste derrière…)", 2.5)
	d.kick(0.45)
	d.after(0.25, func() -> void: d.flinch(0.35))
	return 0.0


func _door_handle(_c: Dictionary) -> float:
	var door = d.handle("door.upstairs")
	var p := Vector3(-3.0, 3.75, -2.78)
	if door != null and door.has_method("world_position"):
		p = door.call("world_position")
	d.light_call("door_strip_occluded", [0.55])
	d.after(0.5, func() -> void: d.light_call("door_strip_occluded", [0.85]))
	d.after(1.1, func() -> void:
		d.sfx("door_locked", p, 0.5, {"pitch": 0.86})
		d.say("(La poignée de la porte, en haut…)", 2.5)
		d.kick(0.45))
	d.after(1.9, func() -> void: d.light_call("door_strip_occluded", [0.7]))
	d.after(2.6, func() -> void: d.sfx("door_locked", p, 0.35, {"pitch": 0.8}))
	d.after(3.4, func() -> void: d.light_call("door_strip_occluded", [0.3]))
	d.after(4.0, func() -> void: d.light_call("door_strip_occluded", [0.0]))
	return 0.0


func _breath_neck(c: Dictionary) -> float:
	var side := -0.1 if _rng.randf() < 0.5 else 0.1
	d.sfx("entity_breath", _behind(c, 0.22, side, 0.03), _rf(0.75, 0.95))
	d.kick(0.55)
	d.after(0.2, func() -> void: d.flinch(0.3))
	if _rng.randf() < 0.5:
		d.after(_rf(2.4, 3.4), func() -> void: d.sfx("entity_breath", _behind(d.c, 0.2, -side, 0.02), 0.6))
	return 0.0


func _rocking(_c: Dictionary) -> float:
	d.world_call("rock_chair", [_rf(3.0, 4.5)])
	d.kick(0.3)
	return 0.0


func _torch_stutter(_c: Dictionary) -> float:
	d.torch_stutter(_rf(0.35, 0.8))
	d.kick(0.25)
	return 0.0


func _chain_sway(_c: Dictionary) -> float:
	var anim = d.world_get("anim")
	if anim != null and anim.has_method("kick_chain"):
		anim.call("kick_chain", 0.14)
	d.sfx("house_creak", CHAIN + Vector3(0.0, 0.4, 0.0), 0.45)
	d.kick(0.1)
	return 0.0


func _garderie_scare(c: Dictionary) -> float:
	var g = d.garderie()
	var kinds := ["giggle_slide", "hum"]
	if float(c.eye.x) < -17.0:
		kinds.append_array(["tube_dies", "ball_roll", "tube_dies"])
	var k: String = kinds[_rng.randi() % kinds.size()]
	if g != null and g.has_method("scare"):
		g.call("scare", k)
	if k == "giggle_slide":
		d.say("(Un rire d’enfant…)", 2.5)
	d.kick(0.35)
	return 0.0


func _scratch_wall(c: Dictionary) -> float:
	d.sfx("fear_scratch", _wall_point(c, false), _rf(0.55, 0.75), {"filter_hz": 2600.0})
	d.say("(Ça gratte… dans le mur.)", 2.5)
	d.kick(0.35)
	return 0.0


func _hum_walls(c: Dictionary) -> float:
	var p := _wall_point(c, true)
	var h = d.sfx("lullaby_hum", p, 0.42, {"filter_hz": 950.0})
	var dur := _rf(5.0, 7.5)
	d.after(dur, func() -> void:
		if h != null and h.has_method("stop"):
			h.stop(2.5))
	d.say("(Quelqu’un fredonne… dans les murs.)", 3.0)
	d.kick(0.4)
	return 0.0


func _window_tap(_c: Dictionary) -> float:
	d.sfx("window_tap", null, _rf(0.5, 0.7))
	d.kick(0.25)
	return 0.0


func _crt_static(_c: Dictionary) -> float:
	var crt = d.world_get("crt")
	if crt != null and crt.has_method("flicker"):
		crt.call("flicker", 0.0)
	d.kick(0.4)
	return 0.0


# ------------------------------------------------------------------------------------------------ spikes
## Silence pre-roll then the glimpse; the cue sound draws the eye where she stands.
func _glimpse_stairs(_c: Dictionary) -> float:
	d.mix.silence_for(0.85, 0.8, 3.0, 3.0)
	d.after(0.9, func() -> void:
		if d.glimpse.start("stairs", LANDING_FEET, 0.0, {"hold": _rf(0.7, 1.1), "timeout": 12.0}):
			d.after(0.9, func() -> void: d.sfx("stair_creak", Vector3(-3.0, 2.6, -1.65), 0.8)))
	return 15.0


func _glimpse_corridor(_c: Dictionary) -> float:
	d.mix.silence_for(0.8, 0.8, 3.0, 3.0)
	var g = d.garderie()
	d.after(0.9, func() -> void:
		if d.glimpse.start("corridor", CORRIDOR_FEET, PI * 0.5, {"hold": _rf(0.7, 1.0), "timeout": 12.0}):
			if g != null and g.has_method("set_light_scale"):
				g.call("set_light_scale", 0.35)
			d.after(1.0, func() -> void: d.sfx("house_creak", CORRIDOR_FEET + Vector3(0.3, 0.3, 0.0), 0.75)))
	return 15.0


func _glimpse_mirror(c: Dictionary) -> float:
	var p := mirror_spot(c)
	if p == Vector3.INF:
		return -1.0
	if not d.glimpse.start("mirror", p, PI, {"hold": _rf(1.0, 1.4), "timeout": 4.0, "mirror_c": MIRROR_C, "mirror_n": MIRROR_N}):
		return -1.0
	d.mix.silence_for(0.7, 0.3, 2.0, 2.5)
	return 8.0


func _glimpse_louvers(c: Dictionary) -> float:
	var spot := String(c.get("spot_id", "closet"))
	var feet := CLOSET_OUT + Vector3(0.0, 0.0, _rf(-0.2, 0.2))
	var yaw := -PI * 0.5
	if spot.begins_with("garderie"):
		feet = TUNNEL_OUT
		yaw = PI * 0.5
	d.mix.silence_for(0.8, 0.8, 4.0, 3.0)
	d.after(0.4, func() -> void: d.sfx("entity_step", feet + Vector3(0.9, 0.05, 0.4), 0.55))
	d.after(1.2, func() -> void: d.sfx("entity_step", feet + Vector3(0.4, 0.05, 0.15), 0.62))
	d.after(1.9, func() -> void:
		if d.glimpse.start("louvers", feet, yaw, {"hold": _rf(1.6, 2.2), "timeout": 6.0, "louvers": true, "mode": "search"}):
			d.mix.stinger("fear_riser", 0.35))
	return 12.0


func _glimpse_dark(c: Dictionary) -> float:
	var p := dark_spot(c)
	if p == Vector3.INF:
		return -1.0
	var to: Vector3 = c.eye - p
	var yaw := atan2(to.x, to.z)
	d.mix.silence_for(0.7, 0.6, 2.5, 3.0)
	if not d.glimpse.start("dark", p, yaw, {"hold": _rf(0.8, 1.1), "timeout": 12.0}):
		return -1.0
	d.after(0.8, func() -> void: d.sfx("house_creak", p + Vector3(0.0, 0.1, 0.0), 0.55))
	return 14.0


## Fake-out: a box full of toys falls off a shelf with a bang (not her).
func _fake_shelf(c: Dictionary) -> float:
	var sp := shelf_spot(c)
	if sp.is_empty():
		return -1.0
	var top: Vector3 = sp[0]
	var push: Vector3 = sp[1]
	d.mix.silence_for(0.75, 0.9, 1.8, 2.0)
	d.after(1.4, func() -> void:
		var hit := func(pos: Vector3, speed: float) -> void:
			d.sfx("fear_crash", pos, clampf(0.75 + speed * 0.08, 0.75, 1.0))
			d.mix.sub_hit(0.4)
			d.kick(0.9)
			d.flinch(1.0)
			d.look_call("shake", [0.35, 0.35])
			d.daze(0.06, 0.9)
			d.mix.muffle_hit(0.45, 0.3, 2.5)
			d.mix.release_silence(1.5)
		d.spawn_fall(top, push, hit))
	return 6.0


## Fake-out: a child's rubber ball comes bouncing down the dark stairs toward the player.
func _fake_ball(_c: Dictionary) -> float:
	d.mix.silence_for(0.7, 0.8, 2.5, 3.0)
	d.after(1.0, func() -> void: d.spawn_ball(STAIRS_TOP_BALL, Vector3(0.05, -0.2, 1.7)))
	return 8.0


func _bulb_pop(_c: Dictionary) -> float:
	d.light_call("flicker", [0.9, 0.7])
	d.after(0.85, func() -> void:
		d.sfx("light_pop", CEILING_LIGHT, 1.0)
		d.mix.sub_hit(0.65)
		d.look_call("flash", [Color(1.0, 0.94, 0.82), 0.55, 0.14])
		d.look_call("shake", [0.3, 0.3])
		d.daze(0.08, 1.2)
		d.light_call("flicker", [2.2, 1.0])
		d.kick(0.85)
		d.flinch(1.0)
		d.mix.muffle_hit(0.55, 0.4, 3.0)
		d.after(0.35, func() -> void: d.mix.tinnitus(0.45)))
	return 6.0


func _ceiling_run(c: Dictionary) -> float:
	var e: Vector3 = c.eye
	var y := float(R.ceilingY) + 0.4
	var a := _clamp_room(Vector3(e.x + 2.6, y, e.z + _rf(1.0, 2.0)), 0.4)
	var b := Vector3(-3.0, y, -2.4)
	d.mix.silence_for(0.85, 0.5, 2.0, 2.0)
	var t := 1.3
	d.after(t, func() -> void: d.kick(0.4))
	for i in 9:
		var k := float(i) / 8.0
		var p := a.lerp(b, k)
		d.after(t, func() -> void: d.sfx("ceiling_steps", p, 0.95, {"pitch": 1.12}))
		t += _rf(0.25, 0.31)
	d.after(t + 0.15, func() -> void:
		d.sfx("fear_distant", HALL_UP, 1.0)
		d.sfx("door_close", HALL_UP, 0.9)
		d.say("(Quelqu’un court, là-haut !)", 2.5)
		d.kick(0.75)
		d.flinch(0.6)
		d.mix.silence_for(0.9, 0.2, 2.5, 3.5))
	return t + 4.0
