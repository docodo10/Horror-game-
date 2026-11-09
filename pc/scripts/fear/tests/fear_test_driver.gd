## Driver of test_fear.gd (loaded at runtime so it can use the autoloads). See test_fear.gd.
extends Node

const Fakes := preload("res://scripts/fear/tests/fear_fakes.gd")
const Director := preload("res://scripts/fear/fear_director.gd")
const Pacer := preload("res://scripts/fear/fear_pacer.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Scares := preload("res://scripts/fear/fear_scares.gd")

const DT := 1.0 / 30.0
const DURATION := 600.0
## The scripted play: waypoints of the wander loop (feet, basement floor).
const PATH := [Vector3(0.25, 0, 1.5), Vector3(0.3, 0, 0.2), Vector3(-1.2, 0, -1.2), Vector3(-0.6, 0, -1.6),
	Vector3(1.3, 0, -1.9), Vector3(1.4, 0, -3.4), Vector3(2.6, 0, -3.6), Vector3(1.35, 0, -2.2), Vector3(2.4, 0, 0.1),
	Vector3(1.9, 0, 1.2), Vector3(-1.3, 0, 1.6), Vector3(-2.2, 0, 2.1), Vector3(-0.4, 0, 0.8)]

var fails: Array[String] = []
var checks := 0
var out_dir := ""

# scenario objects
var pl = null
var ent = null
var world = null
var pz = null
var gd = null
var ui = null
var dir = null
var _active_spans: Array = []      # [[t0, t1]] entity awake
var _span_t0 := -1.0
var _wp := 0
var _wp_wait := 0.0
var _rng := RandomNumberGenerator.new()
var _yaw := 0.0
var _look_t := 0.0
var _look_target := 0.0


func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("[fear-test] ok   ", what)
	else:
		fails.append(what)
		print("[fear-test] FAIL ", what)


func run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fear-out="):
			out_dir = a.get_slice("=", 1)
	await get_tree().process_frame
	var res_x: Dictionary = _simulate("extreme", 4242)
	var res_n: Dictionary = _simulate("normal", 4242)
	# the setting is about rates: compare over a few more seeds (quiet runs, summary only)
	var nx: int = res_x.n
	var nn: int = res_n.n
	for sd in [7, 99, 2024]:
		nx += int(_simulate("extreme", sd, true).n)
		nn += int(_simulate("normal", sd, true).n)
	check(nn < nx, "normal fires fewer scares than extreme over 4 seeds (%d < %d)" % [nn, nx])
	_simulate_catalogue()
	var skip_audio := "--fear-skip-audio" in OS.get_cmdline_user_args()
	if not skip_audio:
		await _audio_levels()
	print("[fear-test] %d checks, %d failed" % [checks, fails.size()])
	for f in fails:
		print("[fear-test]   FAILED: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# ================================================================================================ part A
func _setup_scene(sim: bool) -> void:
	_teardown_scene()
	world = Fakes.FakeWorld.new()
	world.name = "FakeWorld"
	add_child(world)
	pl = Fakes.FakePlayer.new()
	pl.name = "FakePlayer"
	add_child(pl)
	ent = Fakes.FakeEntity.new()
	ent.name = "FakeEntity"
	add_child(ent)
	ent.global_position = Fakes.HOME
	pz = Fakes.FakePuzzles.new()
	add_child(pz)
	gd = Fakes.FakeGarderie.new()
	add_child(gd)
	ui = Fakes.FakeUI.new()
	add_child(ui)
	Game.world = world
	Game.player = pl
	Game.camera = pl.camera
	Game.entity = ent
	Game.puzzles = pz
	Game.garderie = gd
	Game.ui = ui
	Game.night = 1
	Game.time_played = 0.0
	pl.place(Vector3(0.25, 0, 1.5), 0.0)
	if not sim:
		pl.camera.current = true


func _teardown_scene() -> void:
	for n in [dir, world, pl, ent, pz, gd, ui]:
		if n != null and is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	dir = null
	Game.world = null
	Game.player = null
	Game.camera = null
	Game.entity = null
	Game.puzzles = null
	Game.garderie = null
	Game.ui = null


func _ent_state(s: String, t: float) -> void:
	var was: bool = ent.active
	ent.set_state(s)
	if ent.active and not was:
		_span_t0 = t
	elif was and not ent.active:
		_active_spans.append([_span_t0, t])


func _simulate(level: String, seed_value: int, quiet := false) -> Dictionary:
	_setup_scene(true)
	_rng.seed = seed_value
	_active_spans.clear()
	_wp = 0
	_wp_wait = 2.0
	_yaw = 0.0
	dir = Director.new()
	dir.name = "FearDirector"
	dir.sim = true
	dir._seed = seed_value
	add_child(dir)
	Game.set_state("playing")
	dir.setup()
	dir.set_level(level)
	check(pz.ambient_scares == false and gd.ambient_scares == false, "[%s] puzzles / garderie schedulers taken over" % level)
	var t := 0.0
	var marks := {}
	var max_bpm := 0.0
	var min_bpm := 999.0
	var chase1_max := 0.0
	var js_bpm := 0.0
	var bpm_at := {}
	var glimpse_bad := 0
	var hunt_ok := true
	while t < DURATION:
		_drive(t, level)
		Game.time_played = t
		dir.tick(DT)
		t += DT
		var b: float = dir.bpm()
		max_bpm = maxf(max_bpm, b)
		min_bpm = minf(min_bpm, b)
		if t > 352.0 and t < 362.0:
			chase1_max = maxf(chase1_max, b)
		if t > 544.0 and t < 547.0:
			js_bpm = maxf(js_bpm, b)
		for k in [20.0, 45.0, 120.0, 160.0, 360.0, 382.0, 395.0, 600.0]:
			if not bpm_at.has(k) and t >= k:
				bpm_at[k] = b
		if dir.glimpse.active and ent.state != "dormant":
			glimpse_bad += 1
		if ent.active and t > 2.0 and dir.pacer.phase != "hunt" and Game.state == "playing":
			hunt_ok = false
	if ent.active:
		_active_spans.append([_span_t0, t])
	Game.set_state("menu")
	var evs: Array = dir.events
	if quiet:
		var nm := evs.filter(func(e): return e.major).size()
		print("[fear-test] seed %d %-7s: %d scares (%d spikes), max %.1f BPM" % [seed_value, level, evs.size(), nm, max_bpm])
		var r := {"n": evs.size(), "majors": nm}
		_teardown_scene()
		return r
	# ---------------------------------------------------------------- report
	var gap: float = float(Pacer.LEVELS[level].gap)
	var per_min: int = int(Pacer.LEVELS[level].per_min)
	var major_gap: float = float(Pacer.LEVELS[level].major_gap)
	print("")
	print("[fear-test] ===== %s: %d scares in %.0f s =====" % [level.to_upper(), evs.size(), DURATION])
	var majors := 0
	var min_gap := INF
	var max_in_min := 0
	var min_major_gap := INF
	var first_t := INF
	var during_active := 0
	var last_t := -INF
	var last_major := -INF
	for e in evs:
		var et := float(e.t)
		first_t = minf(first_t, et)
		if last_t > -INF:
			min_gap = minf(min_gap, et - last_t)
		last_t = et
		if e.major:
			majors += 1
			if last_major > -INF:
				min_major_gap = minf(min_major_gap, et - last_major)
			last_major = et
		var n := 0
		for e2 in evs:
			if float(e2.t) > et - 60.0 and float(e2.t) <= et:
				n += 1
		max_in_min = maxi(max_in_min, n)
		for s in _active_spans:
			if et >= float(s[0]) and et <= float(s[1]):
				during_active += 1
		print("[fear-test]   %6.1f s  %-17s %-5s  bpm %5.1f  stage %-6s phase %s" % [et, e.id, "MAJOR" if e.major else "", float(e.bpm), e.stage, e.phase])
	# quiet stretches: every 4-minute window holds a >= 35 s gap without any scare (nor a visit counted as event)
	var quiet_ok := true
	var w0 := 0.0
	while w0 + 240.0 <= DURATION:
		var ts: Array = [w0]
		for e in evs:
			if float(e.t) >= w0 and float(e.t) <= w0 + 240.0:
				ts.append(float(e.t))
		ts.append(w0 + 240.0)
		var best := 0.0
		for i in range(1, ts.size()):
			best = maxf(best, float(ts[i]) - float(ts[i - 1]))
		if best < 35.0:
			quiet_ok = false
			print("[fear-test]   window %.0f..%.0f: longest quiet %.1f s" % [w0, w0 + 240.0, best])
		w0 += 30.0
	_print_curve(dir.bpm_trace)
	var gl: Array = dir.glimpse.history
	var gl_seen := 0
	for g in gl:
		if g.seen:
			gl_seen += 1
	print("[fear-test]   glimpses: %d started, %d seen, ended: %s" % [gl.size(), gl_seen, ", ".join(PackedStringArray(gl.map(func(g): return "%s/%s" % [g.kind, g.reason])))])
	print("[fear-test]   heartbeats audible: %d   look calls: %d   sounds: %d   subtitles: %d   flinches %d   torch stutters %d" % [
		dir.mix.beats_played, dir.look_log.size(), dir.sounds.size(), ui.subtitles.size(), pl.flinches, pl.stutters])
	var tag := "[%s] " % level
	check(evs.size() >= (10 if level == "extreme" else 6) and evs.size() <= 45, tag + "scare count in range (%d)" % evs.size())
	check(majors >= 2, tag + "at least two spikes (%d)" % majors)
	check(first_t >= 20.0, tag + "calm opening: first scare at %.1f s" % first_t)
	check(min_gap >= gap - 0.01, tag + "min gap between scares %.1f s >= %.0f s" % [min_gap, gap])
	check(max_in_min <= per_min, tag + "at most %d scares in any minute (max %d)" % [per_min, max_in_min])
	check(majors < 2 or min_major_gap >= major_gap - 0.01, tag + "spikes at least %.0f s apart (min %.1f)" % [major_gap, min_major_gap])
	check(during_active == 0, tag + "no scare while La Gardienne is awake (%d)" % during_active)
	check(hunt_ok, tag + "pacer in 'hunt' whenever she is awake")
	check(quiet_ok, tag + "every 4-minute window has a quiet stretch >= 35 s")
	check(glimpse_bad == 0 and ent.bad_glimpses == 0, tag + "glimpses only while she sleeps")
	check(not dir.glimpse.active and not ent.glimpsing, tag + "no glimpse left on stage")
	check(float(bpm_at[20.0]) >= 66.0 and float(bpm_at[20.0]) <= 84.0, tag + "resting heart at 20 s: %.1f BPM" % bpm_at[20.0])
	check(chase1_max >= 145.0 and chase1_max <= 178.0, tag + "chase heart 145..178 BPM (%.1f)" % chase1_max)
	check(js_bpm >= 165.0, tag + "jumpscare heart >= 165 BPM (%.1f)" % js_bpm)
	check(float(bpm_at[382.0]) > 92.0, tag + "slow decay: 20 s after the chase still %.1f BPM" % bpm_at[382.0])
	check(float(bpm_at[395.0]) < float(bpm_at[382.0]), tag + "and lower later (%.1f at 395 s)" % bpm_at[395.0])
	check(max_bpm <= 178.01 and min_bpm >= 57.99, tag + "BPM within 58..178 (%.1f..%.1f)" % [min_bpm, max_bpm])
	check(dir.mix.beats_played > 100, tag + "beat-synced heartbeat audible during the scary parts (%d beats)" % dir.mix.beats_played)
	_write_log(level, dir)
	var res := {"n": evs.size(), "majors": majors}
	_teardown_scene()
	return res


## Applies the scripted play at time t (player, entity, world, puzzles).
func _drive(t: float, _level: String) -> void:
	# ---- story beats
	if t >= 48.0 and pz.stage == "intro":
		world.power = false
		Events.power_changed.emit(false)
		pz.goto("dark")
	if t >= 75.0 and pz.stage == "dark":
		pl.flashlight.has = true
		pl.flashlight.on = true
		Events.inventory_changed.emit([], [])
		pz.goto("power")
	if t >= 95.0 and not pz.flags.rocked:
		pz.flags.rocked = true
	if pl.flashlight.on:
		pl.flashlight.battery = maxf(5.0, 100.0 - (t - 75.0) / 4.0)
	if t >= 150.0 and t < 151.0 and not world.power:
		world.power = true
		Events.power_changed.emit(true)
	if t >= 200.0 and pz.stage == "power":
		pz.goto("code")
	if t >= 225.0 and pz.found.duck == null:
		pz.found.duck = "3"
	if t >= 262.0 and pz.found.horse == null:
		pz.found.horse = "8"
	if t >= 300.0 and pz.found.clock == null:
		pz.found.clock = "9"
	if t >= 480.0 and pz.stage == "code":
		pz.found.tv = "4"
		Events.inventory_changed.emit([], [])
		pz.goto("escape")
	# ---- entity
	var es: String = ent.state
	if t >= 150.0 and t < 154.0: _ent_to("waking", t)
	elif t >= 154.0 and t < 164.0:
		_ent_to("descending", t)
		ent.global_position = Vector3(-3.0, 2.75, -1.8).lerp(Vector3(-3.0, 0.0, 1.6), (t - 154.0) / 10.0)
	elif t >= 164.0 and t < 190.0:
		_ent_to("searching", t)
		ent.global_position = Vector3(-1.8 + sin(t * 0.3) * 1.2, 0.0, -1.0 + cos(t * 0.25) * 1.0)
	elif t >= 190.0 and t < 200.0:
		_ent_to("returning", t)
		ent.global_position = Vector3(-3.0, 0.0, 1.6).lerp(Vector3(-3.0, 2.75, -1.8), (t - 190.0) / 10.0)
	elif t >= 330.0 and t < 333.0: _ent_to("waking", t)
	elif t >= 333.0 and t < 341.0:
		_ent_to("descending", t)
		ent.global_position = Vector3(-3.0, 2.75, -1.8).lerp(Vector3(-3.0, 0.0, 1.6), (t - 333.0) / 8.0)
	elif t >= 341.0 and t < 352.0:
		_ent_to("searching", t)
		ent.seeing = t > 350.0
		ent.global_position = pl.global_position + Vector3(4.0, 0, 1.5)
	elif t >= 352.0 and t < 362.0:
		_ent_to("chasing", t)
		ent.seeing = true
		ent.global_position = pl.global_position + Vector3(2.4 - (t - 352.0) * 0.1, 0, 0.5)
	elif t >= 362.0 and t < 374.0:
		_ent_to("returning", t)
		ent.seeing = false
		ent.global_position = Vector3(-3.0, 0.0, 1.6).lerp(Vector3(-3.0, 2.75, -1.8), (t - 362.0) / 12.0)
	elif t >= 520.0 and t < 523.0: _ent_to("waking", t)
	elif t >= 523.0 and t < 531.0:
		_ent_to("descending", t)
		ent.global_position = Vector3(-3.0, 2.75, -1.8).lerp(Vector3(-3.0, 0.0, 1.6), (t - 523.0) / 8.0)
	elif t >= 531.0 and t < 536.0:
		_ent_to("searching", t)
		ent.seeing = t > 535.0
		ent.global_position = pl.global_position + Vector3(4.5, 0, 0.0)
	elif t >= 536.0 and t < 544.0:
		_ent_to("chasing", t)
		ent.global_position = pl.global_position + Vector3(lerpf(4.0, 0.8, (t - 536.0) / 8.0), 0, 0)
	elif t >= 544.0 and t < 550.0:
		_ent_to("jumpscare", t)
		if t >= 545.5 and Game.state == "playing":
			Game.set_state("caught")
	elif t >= 550.0 and es == "jumpscare":
		Game.night = 2
		_ent_to("dormant", t)
		ent.global_position = Fakes.HOME
		pl.place(Vector3(0.25, 0, 1.5), 0.0)
		Game.set_state("playing")
	elif es != "dormant" and not ((t >= 150.0 and t < 200.0) or (t >= 330.0 and t < 374.0) or (t >= 520.0 and t < 550.0)):
		_ent_to("dormant", t)
		ent.seeing = false
		ent.global_position = Fakes.HOME
	if Game.state != "playing":
		return
	# ---- player
	var modal := t >= 455.0 and t < 462.0
	ui.modal = modal
	world.reflections.mirror_active = t >= 398.0 and t < 407.0
	var hide := (t >= 151.5 and t < 196.0) or (t >= 430.0 and t < 446.0)
	if hide != pl.hidden:
		pl.hidden = hide
		pl.hide_spot = {"id": "closet"} if hide else null
		Events.player_hide.emit(hide, "closet" if hide else "")
	if hide:
		pl.speed = 0.0
		pl.place(Vector3(-3.05, 0.0, -2.05), -PI * 0.5 + sin(t * 0.7) * 0.6, 0.0, 1.35)
		return
	var chase := (t >= 352.0 and t < 364.0) or (t >= 536.0 and t < 544.0)
	pl.stamina = clampf(pl.stamina + (-DT / 4.0 if chase else DT * 0.25), 0.0, 1.0)
	if t >= 270.0 and t < 300.0:
		# a trip down the garderie corridor and back, looking ahead
		var k := (t - 270.0) / 15.0
		var x := lerpf(-3.0, -8.5, k) if k < 1.0 else lerpf(-8.5, -3.0, k - 1.0)
		pl.speed = 1.2
		pl.place(Vector3(x, 0, 2.1), PI * 0.5 if k < 1.0 else -PI * 0.5 + sin(t) * 0.3)
		return
	if t >= 398.0 and t < 407.0:
		pl.speed = 0.0
		pl.place(Vector3(0.47, 0, -1.25), sin(t * 0.4) * 0.05, -0.05)
		return
	_wander(t, 3.3 if chase else 1.2)


func _ent_to(s: String, t: float) -> void:
	if ent.state != s:
		_ent_state(s, t)


func _wander(t: float, spd: float) -> void:
	var p: Vector3 = pl.global_position
	if p.x < -3.4 or p.y > 0.5:
		p = Vector3(0.25, 0, 1.5)
	var target: Vector3 = PATH[_wp]
	var to := target - p
	to.y = 0.0
	if _wp_wait > 0.0 and spd < 2.0:
		_wp_wait -= DT
		pl.speed = 0.0
		# looking around: slow sweeps, now and then a turn to look behind
		_look_t -= DT
		if _look_t <= 0.0:
			_look_t = _rng.randf_range(1.0, 3.0)
			_look_target = _yaw + (_rng.randf_range(2.6, 3.4) if _rng.randf() < 0.2 else _rng.randf_range(-1.4, 1.4))
		_yaw = lerp_angle(_yaw, _look_target, minf(1.0, DT * 2.5))
		pl.place(p, _yaw, sin(t * 0.5) * 0.15)
		return
	if to.length() < 0.15:
		_wp = (_wp + 1) % PATH.size()
		_wp_wait = _rng.randf_range(2.0, 6.0)
		return
	var step := to.normalized() * spd * DT
	if step.length() > to.length():
		step = to
	p += step
	pl.speed = spd
	var want := atan2(-to.x, -to.z)
	_yaw = lerp_angle(_yaw, want, minf(1.0, DT * 4.0))
	pl.place(p, _yaw, 0.0)


func _print_curve(trace: Array) -> void:
	# one line per 20 s: time, BPM bar
	print("[fear-test]   BPM curve (every 20 s):")
	var next := 0.0
	for s in trace:
		if float(s[0]) + 0.001 < next:
			continue
		next = float(s[0]) + 20.0
		var b := float(s[1])
		var bar := "#".repeat(int(clampf((b - 55.0) / 2.5, 0.0, 60.0)))
		print("[fear-test]   %5.0f s %5.1f %-8s %s" % [float(s[0]), b, String(s[3]), bar])


func _write_log(level: String, d) -> void:
	if out_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("fear_timeline_%s.csv" % level), FileAccess.WRITE)
	if f == null:
		return
	f.store_line("kind,t,a,b,c")
	for s in d.bpm_trace:
		f.store_line("bpm,%.2f,%.1f,%.3f,%s" % [s[0], s[1], s[2], s[3]])
	for e in d.events:
		f.store_line("scare,%.2f,%s,%s,%.1f" % [e.t, e.id, "major" if e.major else "minor", e.bpm])
	for g in d.glimpse.history:
		f.store_line("glimpse,%.2f,%s,%s,%s" % [g.t, g.kind, g.reason, "seen" if g.seen else "unseen"])
	for s in _active_spans:
		f.store_line("entity,%.2f,%.2f,awake," % [s[0], s[1]])
	f.close()
	print("[fear-test]   timeline written: ", out_dir.path_join("fear_timeline_%s.csv" % level))


## Every scare of the catalogue runs against the fakes without errors (forced, ignoring pacing).
func _simulate_catalogue() -> void:
	_setup_scene(true)
	dir = Director.new()
	dir.sim = true
	dir._seed = 77
	add_child(dir)
	Game.set_state("playing")
	dir.setup()
	world.power = true
	pz.stage = "escape"
	pz.flags.rocked = true
	pl.flashlight.has = true
	pl.flashlight.on = true
	var ran := 0
	var refused: Array = []
	for id in Scares.CATALOG:
		# put the player where each scare can happen
		match id:
			"glimpse_louvers", "breath_neck":
				pl.hidden = true
				pl.hide_spot = {"id": "closet"}
				pl.place(Vector3(-3.05, 0, -2.05), -PI * 0.5, 0.0, 1.35)
			"glimpse_corridor", "garderie_scare":
				pl.hidden = false
				pl.place(Vector3(-5.0, 0, 2.1), -PI * 0.5)
			"chain_sway":
				pl.hidden = false
				pl.place(Vector3(1.6, 0, -3.4), 0.0)
			_:
				pl.hidden = false
				pl.place(Vector3(-1.5, 0, 2.0), 0.0)
		world.power = id != "glimpse_dark" and id != "torch_stutter"
		for i in 3:
			dir.tick(DT)
		var ok: bool = dir.force(id)
		for i in 600:
			dir.tick(DT)
		if ok:
			ran += 1
		else:
			refused.append(id)
		if dir.glimpse.active:
			dir.glimpse.abort()
	print("[fear-test] catalogue: %d/%d scares ran (refused here: %s)" % [ran, Scares.CATALOG.size(), ", ".join(PackedStringArray(refused))])
	check(ran >= Scares.CATALOG.size() - 4, "the whole repertoire runs against the fakes (%d)" % ran)
	check(world.lighting.calls.get("flicker", 0) > 0 and world.lighting.calls.get("door_strip_occluded", 0) > 0, "lighting hooks called (flicker, door strip)")
	check(world.rocks > 0 and world.crt.flickers > 0, "rocking chair and old CRT driven")
	check(ent.glimpses >= 2, "glimpses placed through the entity hook (%d)" % ent.glimpses)
	Game.set_state("menu")
	_teardown_scene()


# ================================================================================================ part B
var cap: AudioEffectCapture = null


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _peak(secs: float, clear := true) -> Dictionary:
	if clear:
		cap.clear_buffer()
	await _wait(secs)
	var buf := cap.get_buffer(cap.get_frames_available())
	var pk := 0.0
	var e := 0.0
	var e_lo := 0.0
	var prev := 0.0
	for f in buf:
		var x := (f.x + f.y) * 0.5
		pk = maxf(pk, maxf(absf(f.x), absf(f.y)))
		e += x * x
		prev += (x - prev) * 0.02          # one-pole low-pass ~140 Hz
		e_lo += prev * prev
	var n := maxi(1, buf.size())
	return {"peak_db": linear_to_db(maxf(pk, 1e-6)), "rms_db": linear_to_db(maxf(sqrt(e / n), 1e-6)),
		"low_db": linear_to_db(maxf(sqrt(e_lo / n), 1e-6)), "frames": buf.size()}


func _audio_levels() -> void:
	print("")
	print("[fear-test] ===== audio levels (real-time mix, Master output) =====")
	var guard := 0
	while not Audio.is_loaded() and guard < 400:
		await _wait(0.05)
		guard += 1
	var st: Dictionary = Audio.stats()
	check(st.failed == 0, "audio library: every file loads (%d files, %d failed)" % [st.files, st.failed])
	var names := ["fear_heartbeat", "fear_rumble", "fear_drone", "fear_tinnitus", "fear_sub_hit", "fear_stinger",
		"fear_stinger_big", "fear_riser", "fear_crash", "fear_ball", "fear_distant", "fear_scratch"]
	var missing := names.filter(func(n): return not Audio.has_sound(n))
	check(missing.is_empty(), "fear sounds registered with the Audio module (missing: %s)" % ", ".join(PackedStringArray(missing)))
	_setup_scene(false)
	cap = AudioEffectCapture.new()
	cap.buffer_length = 6.0
	AudioServer.add_bus_effect(0, cap)
	dir = Director.new()
	dir.name = "FearDirector"
	add_child(dir)
	Game.set_state("playing")
	dir.setup()
	world.power = true
	await _wait(0.3)
	check(Buses.find_effect_index("SFX", "fear_lowpass") >= 0 and Buses.find_effect_index("Ambience", "fear_gain") >= 0
		and Buses.find_effect_index("Voice", "fear_lowpass") >= 0, "muffle / silence effects installed on the category buses")
	check(Buses.is_valid(), "audio bus graph still valid for the audio module")
	check(Audio.get("heartbeat_external") == true, "audio module heartbeat loops handed over")
	Audio.stop_all(0.05)
	await _wait(0.4)
	var quiet: Dictionary = await _peak(0.6)
	print("[fear-test]   bed (room tone etc.)       peak %6.1f dBFS  rms %6.1f" % [quiet.peak_db, quiet.rms_db])
	# heartbeat at 165 BPM
	dir.heart.hold_bpm = 165.0
	var b0: int = dir.mix.beats_played
	var hb: Dictionary = await _peak(4.0)
	var beats: int = dir.mix.beats_played - b0
	print("[fear-test]   heartbeat 165 BPM, 4 s     peak %6.1f dBFS  rms %6.1f  low %6.1f  beats %d" % [hb.peak_db, hb.rms_db, hb.low_db, beats])
	check(beats >= 9 and beats <= 13, "beat-synced heartbeat: %d beats in 4 s at 165 BPM (expected ~11)" % beats)
	check(hb.peak_db < -9.0 and hb.peak_db > -30.0, "heartbeat audible, under the scares (%.1f dBFS)" % hb.peak_db)
	await _wait(1.5)
	check(dir.mix.get("_rumble") != null and dir.mix.get("_drone") != null, "rumble and drone loops running at high stress")
	var bed: Dictionary = await _peak(2.0)
	print("[fear-test]   heart + rumble + drone     peak %6.1f dBFS  rms %6.1f  low %6.1f" % [bed.peak_db, bed.rms_db, bed.low_db])
	check(bed.peak_db < -1.0, "stress bed below the limiter ceiling (%.1f dBFS)" % bed.peak_db)
	dir.heart.hold_bpm = -1.0
	dir.heart.reset(72.0)
	await _wait(2.5)
	Audio.stop_all(0.05)
	await _wait(0.5)
	# the real jumpscare, layered
	cap.clear_buffer()
	ent.set_state("jumpscare")
	Audio.play("jumpscare", {"volume": 1.0})
	await _wait(0.2)
	check(Engine.time_scale < 0.99, "slow motion during the jumpscare (time scale %.2f)" % Engine.time_scale)
	await _wait(2.3)
	var buf := cap.get_buffer(cap.get_frames_available())
	var pk := 0.0
	for f in buf:
		pk = maxf(pk, maxf(absf(f.x), absf(f.y)))
	var js_db := linear_to_db(maxf(pk, 1e-6))
	print("[fear-test]   jumpscare + layers 2.5 s   peak %6.1f dBFS" % js_db)
	check(js_db <= -0.85 and js_db >= -6.0, "jumpscare peaks loud but limited (%.1f dBFS; limiter -1 dBFS, then user volume)" % js_db)
	check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored")
	check(dir.mix.muffle > 0.3, "hearing muffled after the jumpscare (%.2f)" % dir.mix.muffle)
	Game.set_state("caught")
	await _wait(1.0)
	check(dir.mix.silence > 0.5, "ringing silence through the caught screen (%.2f)" % dir.mix.silence)
	var lp := AudioServer.get_bus_effect(AudioServer.get_bus_index("SFX"), Buses.find_effect_index("SFX", "fear_lowpass")) as AudioEffectLowPassFilter
	check(lp != null and lp.cutoff_hz < 6000.0, "SFX low-pass closed (%.0f Hz)" % (lp.cutoff_hz if lp else -1.0))
	ent.set_state("dormant")
	Game.set_state("playing")
	await _wait(5.5)
	check(dir.mix.silence < 0.2, "silence lifts back in the game (%.2f)" % dir.mix.silence)
	# isolated measurements: calm heart (no beats), beds stopped
	dir.heart.reset(60.0)
	dir.heart.hold_bpm = 60.0
	dir.heart.adrenaline = 0.0
	await _wait(3.0)
	Audio.stop_all(0.05)
	await _wait(0.6)
	var calm: Dictionary = await _peak(0.8)
	print("[fear-test]   calm (heart at rest)       peak %6.1f dBFS" % calm.peak_db)
	# fake-out crash 2.5 m away + sub hit
	var crash: Dictionary = await _measure_fn(func() -> void:
		dir.sfx("fear_crash", pl.camera.global_position + Vector3(2.0, -1.2, -1.2), 1.0)
		dir.mix.sub_hit(0.4), 1.6)
	print("[fear-test]   fake-out crash at 2.5 m    peak %6.1f dBFS  rms %6.1f" % [crash.peak_db, crash.rms_db])
	check(crash.peak_db < -1.0 and crash.peak_db > -20.0, "fake-out crash loud, not clipping (%.1f dBFS)" % crash.peak_db)
	var tin: Dictionary = await _measure_fn(func() -> void: dir.mix.tinnitus(0.6), 1.5)
	print("[fear-test]   tinnitus                   peak %6.1f dBFS  rms %6.1f" % [tin.peak_db, tin.rms_db])
	check(tin.peak_db < -16.0 and tin.peak_db > -45.0, "tinnitus present but gentle (%.1f dBFS)" % tin.peak_db)
	var st2: Dictionary = await _measure_fn(func() -> void: dir.mix.stinger("fear_stinger", 0.9), 1.5)
	print("[fear-test]   glimpse stinger            peak %6.1f dBFS  rms %6.1f" % [st2.peak_db, st2.rms_db])
	check(st2.peak_db < -1.0 and st2.peak_db > -20.0, "glimpse stinger loud, not clipping (%.1f dBFS)" % st2.peak_db)
	Game.set_state("menu")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	_teardown_scene()


func _measure_fn(fn: Callable, secs: float) -> Dictionary:
	await _wait(0.2)
	cap.clear_buffer()
	fn.call()
	var m: Dictionary = await _peak(secs, false)
	Audio.stop_all(0.05)
	await _wait(0.4)
	return m
