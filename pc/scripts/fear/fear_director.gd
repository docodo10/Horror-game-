## Fear module — FearDirector: orchestrates tension and scares across the other modules so La Gardienne is genuinely
## frightening and uncomfortable to play, while staying fair (no scare of this module can hurt, catch or wake her, every
## real cue of a visit stays clean: the director goes quiet while she is awake).
##
## Wiring (scenes/main.gd, right after `await puzzles.setup()`):
##     const FearModule := preload("res://scripts/fear/fear_director.gd")
##     var fear := FearModule.new(); fear.name = "FearDirector"; add_child(fear); fear.setup()
## (a Node of the game scene, not an autoload: it lives and dies with the systems it drives; a scene reload starts a
## fresh one. Others find it at Game.main.get_node("FearDirector").)
##
## Parts:  fear_heart.gd (BPM / stress model) · fear_pacer.gd (tension curve, cooldowns, budgets) · fear_scares.gd
##   (repertoire + eligibility + executors) · fear_glimpse.gd (apparitions through the entity's glimpse hook) ·
##   fear_mix.gd (beat-synced heartbeat, rumble / drone, muffle / silence / tinnitus, look pulse, player tremor).
## Every tick: context (player, torch, hiding, darkness, entity, stage, night, modal, "just solved", looking away) ->
##   heart -> mix -> glimpse -> pacer -> maybe a scare. Reactions: entity spotted (jolt + sub hit), real jumpscare
##   (big stinger + sub-bass hit + short slow motion + muffled hearing + tinnitus + a long ringing silence through the
##   caught screen), scripted beats of the puzzles (blowout, breaker visit, key) count as spikes for pacing.
## Lead checklist: the wiring above; Settings.values gets "fear": "extreme"; Options line PEUR  NORMALE / EXTRÊME ->
##   Settings.set_value("fear", "normal" | "extreme") (applied live through Events.settings_changed); export_presets.cfg
##   include_filter gains "assets/audio/fear/manifest.json" (the Audio module merges it; without it the fear sounds are
##   missing in the .exe and the heartbeat falls back to the recorded heartbeat_single).
## Setting: Settings "fear" = "normal" | "extreme" (default "extreme"). Debug args (after --): --fear=normal|extreme|off,
##   --fear-log, --fear-scare=id[,id...] (forced once playing, 7 s apart), --fear-bpm=N (pins the heart),
##   --fear-hold (once seen, a glimpse stays: screenshots), --fear-seed=N (deterministic picks).
## Public: setup(), tick(dt), force(id) -> bool, kick(amount), set_level(l), bpm(), stress(), level, enabled, sim,
##   events [{t, id, major, bpm, phase, game_t, stage}], bpm_trace [[t, bpm, stress, phase]], glimpse.history,
##   signal scare_fired(id, info).
## Cross-module hooks it uses (all optional, has_method / `in` guarded): entity.glimpse()/end_glimpse()/glimpsing,
##   player.stress_bias / flashlight_stutter() / flinch(), puzzles.ambient_scares, garderie.ambient_scares / scare() /
##   set_light_scale(), Audio.heartbeat_external, world.lighting.flicker / set_stress / door_strip_occluded,
##   world.rock_chair, world.crt.flicker, world.anim.kick_chain, world.reflections.mirror_active, world.line_blocked,
##   world.ground_probe, Quality.set_fear / flash / shake / set_blur (static, look module).
extends Node

const Heart := preload("res://scripts/fear/fear_heart.gd")
const Pacer := preload("res://scripts/fear/fear_pacer.gd")
const Mix := preload("res://scripts/fear/fear_mix.gd")
const Glimpse := preload("res://scripts/fear/fear_glimpse.gd")
const Scares := preload("res://scripts/fear/fear_scares.gd")

const STAGE_K := {"intro": 0.0, "dark": 0.25, "power": 0.4, "code": 0.65, "escape": 1.0, "win": 1.0}
const LAYER_WORLD := 1
const R := Layout.ROOM
const ST := Layout.STAIRS

signal scare_fired(id: String, info: Dictionary)

var enabled := true
var level := "extreme"
var sim := false                  # tests: decisions only (no Audio / AudioServer / Quality calls)
var clock := 0.0
var c := {}                       # context (refreshed every tick)
var heart = null
var pacer = null
var mix = null
var glimpse = null
var scares = null
var events: Array = []
var bpm_trace: Array = []
var sounds: Array = []            # sim: [t, name, volume]
var look_log: Array = []          # sim: [t, method]
var hold_glimpses := false

var _jobs: Array = []             # [{t, fn}]
var _props: Array = []            # physics fake-outs [{node, kind, t, ttl, ...}]
var _ctx_t := 0.0
var _major_try_t := 0.0
var _trace_t := 0.0
var _still_t := 0.0
var _hidden_t := 0.0
var _solved_t := 99.0
var _prev_yaw := 0.0
var _turn := 0.0
var _found_n := 0
var _rocked := false
var _wall_ahead := false
var _forced: Array = []
var _forced_t := 2.0
var _log_on := false
var _seed := 0
var _setup_done := false
var _quality_script: Script = null
var _g_light_scale := -1.0
var _caught_sil := false
var _time_scaled := false
var _prng := RandomNumberGenerator.new()
var _hold_bpm := -1.0


# ================================================================================================ lifecycle
func setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_parse_args()
	if level == "off":
		enabled = false
	heart = Heart.new(_seed)
	pacer = Pacer.new(_seed + 1 if _seed != 0 else 0)
	pacer.level = "normal" if level == "normal" else "extreme"
	mix = Mix.new(self)
	glimpse = Glimpse.new(self)
	scares = Scares.new(self, _seed + 2 if _seed != 0 else 0)
	_refresh_ctx(0.0)
	if not enabled:
		return
	_take_over_schedulers(true)
	mix.setup()
	Events.entity_state.connect(_on_entity_state)
	Events.entity_spotted.connect(_on_spotted)
	Events.game_state.connect(_on_game_state)
	Events.stage_changed.connect(_on_stage)
	Events.inventory_changed.connect(_on_inventory)
	Events.settings_changed.connect(_on_settings)
	if _log_on:
		print("[fear] director ready: level=%s sim=%s" % [level, sim])


func _exit_tree() -> void:
	_restore_time_scale()
	for p in _props:
		if is_instance_valid(p.node):
			p.node.queue_free()
	_props.clear()
	if glimpse != null and glimpse.active:
		glimpse.abort()
	if mix != null:
		mix.teardown()
	if enabled and not sim:
		_take_over_schedulers(false)


## The other modules' own random-scare schedulers stop (the director paces everything), the audio module's fear-driven
## heartbeat loops make way for the beat-synced one. Restored on exit.
func _take_over_schedulers(on: bool) -> void:
	var pz = puzzles()
	if pz != null and "ambient_scares" in pz:
		pz.set("ambient_scares", not on)
	var g = garderie()
	if g != null and "ambient_scares" in g:
		g.set("ambient_scares", not on)
	if not sim and "heartbeat_external" in Audio:
		Audio.set("heartbeat_external", on)


func set_level(l: String) -> void:
	level = l if l in ["normal", "extreme", "off"] else "extreme"
	if pacer != null:
		pacer.level = "normal" if level == "normal" else "extreme"
	var was := enabled
	enabled = level != "off"
	if was != enabled and _setup_done and not sim:
		_take_over_schedulers(enabled)
		if not enabled:
			mix.teardown()


func bpm() -> float:
	return heart.bpm if heart != null else Heart.REST


func stress() -> float:
	return heart.stress if heart != null else 0.0


func kick(amount: float) -> void:
	if heart != null:
		heart.kick(amount * (1.0 if level != "normal" else 0.8))


func _process(delta: float) -> void:
	if sim or not _setup_done:
		return
	tick(delta)


# ================================================================================================ tick
func tick(dt: float) -> void:
	if not enabled or dt <= 0.0:
		return
	dt = minf(dt, 0.1)
	clock += dt
	_run_jobs()
	_refresh_ctx(dt)
	var playing := Game.state == "playing"
	var beat: bool = heart.update(dt, c)
	if beat:
		mix.beat(heart.bpm, heart.stress)
	mix.update(dt, heart.stress, heart.pulse(), c)
	if glimpse.active and not (hold_glimpses and glimpse.seen_t >= 0.0):   # --fear-hold (screenshots): once seen she stays
		glimpse.update(dt, c)
	_update_props(dt)
	_trace_t -= dt
	if _trace_t <= 0.0:
		_trace_t = 0.5
		bpm_trace.append([snappedf(clock, 0.01), snappedf(heart.bpm, 0.1), snappedf(heart.stress, 0.001), pacer.phase])
		if bpm_trace.size() > 4000:
			bpm_trace.pop_front()
	if not playing:
		return
	pacer.update(dt, c)
	_poll_progress()
	if not _forced.is_empty():
		_forced_t -= dt
		if _forced_t <= 0.0:
			_forced_t = 7.0
			force(String(_forced.pop_front()))
		return
	_decide()


func _decide() -> void:
	if glimpse.active or pacer.phase != "build":
		return
	if bool(c.get("grace", false)):
		return
	_major_try_t -= float(c.get("dt", 0.0))
	var moment := _moment()
	if _major_try_t <= 0.0 and pacer.want_major(c, moment):
		_major_try_t = 0.5                        # placement checks cast rays: at most twice a second
		var id := _pick(true)
		if id == "" and pacer.peak_t > 40.0:
			id = _pick(false)                     # no spike fits here: a strong false alarm closes the build-up
			if id != "" and _fire(id, true):
				return
		elif id != "" and _fire(id):
			return
	if pacer.want_minor(c):
		var mid := _pick(false)
		if mid == "" or not _fire(mid):
			pacer.next_minor = 3.0


## How good this moment is for a spike (0..1): darkness, success just now, hiding, standing still, looking around.
func _moment() -> float:
	var m := 0.0
	if c.get("dark", false):
		m += 0.3
	if float(c.get("solved_t", 99.0)) < 12.0:
		m += 0.35
	if c.get("hidden", false) and float(c.get("hidden_t", 0.0)) > 3.0:
		m += 0.35
	if float(c.get("still_t", 0.0)) > 2.0:
		m += 0.15
	if absf(_turn) > 1.6:
		m += 0.15
	var bat := float(c.get("battery", -1.0))
	if bat >= 0.0 and bat < 25.0:
		m += 0.1
	return clampf(m, 0.0, 1.0)


func _pick(major: bool) -> String:
	var pool: Array = []
	var sum := 0.0
	for id in Scares.CATALOG:
		if scares.is_major(id) != major or not pacer.cooldown_ok(id):
			continue
		var w: float = scares.weight(id, c)
		if w <= 0.0:
			continue
		pool.append([id, w])
		sum += w
	if pool.is_empty():
		return ""
	var r := randf() * sum if _seed == 0 else _pick_rand() * sum
	for e in pool:
		r -= float(e[1])
		if r <= 0.0:
			return String(e[0])
	return String(pool[-1][0])


func _pick_rand() -> float:
	return _prng.randf()


## Fires a scare now (as_major: a minor used to close a build-up counts as the spike).
func _fire(id: String, as_major := false) -> bool:
	var major: bool = scares.is_major(id) or as_major
	var spike: float = scares.run(id, c)
	if spike < 0.0:
		return false
	pacer.record(id, major, scares.cooldown(id), c, spike if scares.is_major(id) else 0.0)
	var info := {"t": snappedf(clock, 0.01), "id": id, "major": major, "bpm": snappedf(heart.bpm, 0.1),
		"phase": pacer.phase, "game_t": snappedf(float(c.get("game_t", 0.0)), 0.1), "stage": String(c.get("stage", ""))}
	events.append(info)
	scare_fired.emit(id, info)
	if _log_on:
		print("[fear] %7.1f  %-16s %s bpm %5.1f  stage %s" % [clock, id, "MAJOR" if major else "minor", heart.bpm, info.stage])
	return true


## Debug / tests / other modules: fire one scare now, ignoring the pacing (its own placement checks still apply).
func force(id: String) -> bool:
	if not Scares.CATALOG.has(id) or glimpse.active and id.begins_with("glimpse"):
		return false
	_refresh_ctx(0.0)
	return _fire(id)


# ================================================================================================ context
func _refresh_ctx(dt: float) -> void:
	var pl = player()
	var cam: Camera3D = Game.camera if Game.camera != null and is_instance_valid(Game.camera) else null
	var eye := Vector3(0.25, 1.6, 1.5)
	var fwd := Vector3(0, 0, -1)
	if cam != null and cam.is_inside_tree():
		eye = cam.global_position
		fwd = -cam.global_basis.z.normalized()
	var feet := eye - Vector3(0, 1.6, 0)
	var torch_on := false
	var battery := -1.0
	var beam := fwd
	var hidden := false
	var spot_id := ""
	var stamina := 1.0
	var speed := 0.0
	if pl != null:
		if pl is Node3D and (pl as Node3D).is_inside_tree():
			feet = (pl as Node3D).global_position
		var fl = pl.get("flashlight")
		if fl is Dictionary:
			torch_on = bool(fl.get("on", false)) and bool(fl.get("has", false))
			battery = float(fl.get("battery", 100.0)) if fl.get("has", false) else -1.0
			var L = fl.get("light")
			if L is Node3D and (L as Node3D).is_inside_tree():
				beam = -(L as Node3D).global_basis.z.normalized()
		hidden = pl.get("hidden") == true
		var hs = pl.get("hide_spot")
		spot_id = str((hs as Dictionary).get("id", "closet")) if hs is Dictionary else ""
		stamina = float(pl.get("stamina")) if pl.get("stamina") != null else 1.0
		speed = float(pl.get("speed")) if pl.get("speed") != null else 0.0
	var yaw := atan2(-fwd.x, -fwd.z)
	if dt > 0.0:
		var dy := wrapf(yaw - _prev_yaw, -PI, PI) / dt
		_turn += (dy - _turn) * minf(1.0, dt * 8.0)
		_still_t = _still_t + dt if speed < 0.15 else 0.0
		_hidden_t = _hidden_t + dt if hidden else 0.0
		_solved_t += dt
	_prev_yaw = yaw
	var w = world()
	var power: bool = w == null or w.get("power") != false
	var g = garderie()
	var in_garderie: bool = feet.x < -3.68 and g != null
	var in_house: bool = not in_garderie and feet.y < 2.2
	var in_nook: bool = feet.z < float(R.minZ) - 0.05 and feet.x > 0.1
	var dark: bool = not power
	var ent = entity()
	var es := "dormant"
	var ent_active := false
	var ent_dist := 99.0
	var ent_sees := false
	var ent_on_screen := false
	if ent != null:
		es = String(ent.get("state")) if ent.get("state") != null else "dormant"
		ent_active = ent.get("active") == true
		ent_sees = ent.get("seeing") == true
		if ent_active and ent is Node3D and (ent as Node3D).is_inside_tree():
			var ep := (ent as Node3D).global_position
			ent_dist = ep.distance_to(feet)
			var to := ep + Vector3(0, 1.3, 0) - eye
			ent_on_screen = to.length() < 12.0 and fwd.dot(to.normalized()) > 0.6
	if glimpse != null and glimpse.active:
		es = "dormant"                       # her apparition is not a visit
	var pz = puzzles()
	var stage := String(pz.get("stage")) if pz != null and pz.get("stage") != null else "intro"
	_ctx_t -= dt
	if _ctx_t <= 0.0:
		_ctx_t = 0.1
		_wall_ahead = line_blocked(eye, eye + Vector3(fwd.x, 0.0, fwd.z).normalized() * 1.1) if Vector2(fwd.x, fwd.z).length() > 0.1 else false
	var modal := false
	var ui = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("is_modal_open"):
		modal = bool(ui.call("is_modal_open"))
	# one persistent dictionary (no per-frame allocation)
	c["t"] = clock
	c["dt"] = dt
	c["game_t"] = Game.time_played
	c["live"] = Game.state == "playing" or Game.state == "paused"
	c["stage"] = stage
	c["stage_i"] = maxi(0, Scares.STAGES.find(stage))
	c["stage_k"] = float(STAGE_K.get(stage, 0.0))
	c["night"] = Game.night
	c["eye"] = eye
	c["fwd"] = fwd
	c["feet"] = feet
	c["beam_dir"] = beam
	c["torch_on"] = torch_on
	c["battery"] = battery
	c["hidden"] = hidden
	c["spot_id"] = spot_id
	c["hidden_t"] = _hidden_t
	c["stamina"] = stamina
	c["still_t"] = _still_t
	c["turn"] = _turn
	c["power"] = power
	c["dark"] = dark
	c["in_house"] = in_house
	c["in_nook"] = in_nook
	c["in_garderie"] = in_garderie
	c["ent_state"] = es
	c["ent_active"] = ent_active and not (glimpse != null and glimpse.active)
	c["ent_dist"] = ent_dist
	c["ent_sees"] = ent_sees
	c["ent_on_screen"] = ent_on_screen
	c["modal"] = modal
	c["solved_t"] = _solved_t
	c["wall_ahead"] = _wall_ahead
	c["player_node"] = pl
	c["grace"] = _caught_sil


func _poll_progress() -> void:
	var pz = puzzles()
	if pz == null:
		return
	var f = pz.get("found")
	if f is Dictionary:
		var n := 0
		for k in f:
			if f[k] != null:
				n += 1
		if n > _found_n:
			_solved_t = 0.0
		_found_n = n
	if d_pflag(pz, "rocked") and not _rocked:
		_rocked = true
		pacer.record("scripted_rock", false, 0.0, c)   # the puzzles' first rocking-chair beat counts in the budget


static func d_pflag(pz, flag: String) -> bool:
	var fl = pz.get("flags")
	return fl is Dictionary and (fl as Dictionary).get(flag, false) == true


# ================================================================================================ events
func _on_entity_state(s: String, prev: String) -> void:
	if not enabled:
		return
	if s != "dormant" and glimpse.active:
		glimpse.abort()
	if s == "jumpscare":
		_jumpscare_layers()
	elif s == "waking" and prev == "dormant":
		mix.release_silence(0.8)


func _on_spotted() -> void:
	if not enabled:
		return
	kick(0.6)
	mix.sub_hit(0.35)


## The real jumpscare (the entity plays its scream, red flash, shake and blur): layered stinger + sub-bass hit, a short
## slow motion as her face fills the screen, then muffled hearing, tinnitus and a long ringing silence that holds
## through the caught screen.
func _jumpscare_layers() -> void:
	glimpse.abort()
	kick(1.0)
	heart.bpm = maxf(heart.bpm, 166.0)
	mix.stinger("fear_stinger_big", 1.7)     # +4.6 dB: hits the master limiter with her scream
	mix.sub_hit(1.4)
	look_call("shake", [0.5, 0.5])
	after(0.1, func() -> void: _slow_motion(0.4, 0.32))
	after(0.85, func() -> void:
		mix.muffle_hit(0.85, 2.5, 4.5)
		mix.tinnitus(0.75))
	after(1.25, func() -> void:
		_caught_sil = true
		mix.silence_for(1.0, 0.3, 30.0, 4.0))


func _slow_motion(scale: float, real_seconds: float) -> void:
	if sim or not is_inside_tree():
		return
	_time_scaled = true
	Engine.time_scale = scale
	get_tree().create_timer(real_seconds, true, false, true).timeout.connect(_restore_time_scale)


func _restore_time_scale() -> void:
	if _time_scaled:
		_time_scaled = false
		Engine.time_scale = 1.0


func _on_game_state(s: String, prev: String) -> void:
	if not enabled:
		return
	if s != "playing" and s != "paused":
		_restore_time_scale()
	if s == "caught":
		glimpse.abort()
		_clear_props()
	if s == "playing" and prev == "caught":
		# back at the start of a new night: the silence lifts slowly, no scare for a while
		_caught_sil = false
		mix.release_silence(3.5)
		heart.adrenaline = minf(heart.adrenaline, 0.6)
		pacer.external_spike(40.0)
	if s == "won" or s == "gameover":
		_caught_sil = false
		mix.release_silence(2.0)


func _on_stage(stage: String, _prev: String) -> void:
	match stage:
		"dark":
			kick(0.5)
			pacer.external_spike(28.0)
		"power":
			_solved_t = 0.0
		"code":
			_solved_t = 0.0
		"escape":
			_solved_t = 0.0
			kick(0.3)
			pacer.external_spike(14.0)


func _on_inventory(_items: Array, _notes: Array) -> void:
	_solved_t = 0.0


func _on_settings(key: String, value: Variant) -> void:
	if key == "fear":
		set_level(String(value))


## Glimpse callbacks (fear_glimpse.gd).
func on_glimpse_seen(kind: String, dist: float, _lit: bool) -> void:
	mix.stinger("fear_stinger", clampf(1.05 - dist / 14.0, 0.5, 0.95))
	kick(0.7 if kind != "louvers" else 0.85)
	flinch(clampf(1.1 - dist / 12.0, 0.45, 0.9))
	look_call("shake", [0.15, 0.25])
	mix.swell_for(0.6, 3.0)


func on_glimpse_end(kind: String, why: String, effects: bool) -> void:
	if kind == "corridor":
		var g = garderie()
		if g != null and g.has_method("set_light_scale"):
			g.call("set_light_scale", _g_light_scale if _g_light_scale > 0.0 else 1.0)
	if effects:
		if why == "torch":
			torch_stutter(0.35)
			if c.get("power", true):
				light_call("flicker", [0.3, 1.0])
		else:
			look_call("flash", [Color(0.0, 0.0, 0.0), 0.95, 0.12])   # a blink: and she is gone
		if kind == "mirror":
			var p: Vector3 = c.get("eye", Vector3.ZERO) - Vector3(c.get("fwd", Vector3.FORWARD).x, 0.0, c.get("fwd", Vector3.FORWARD).z).normalized() * 0.3
			after(0.5, func() -> void: sfx("entity_breath", p, 0.7))
	mix.release_silence(2.5)
	if pacer.phase == "spike":
		pacer.start_relief(pacer._relief_after_major(float(c.get("stage_k", 0.0))))
	if _log_on:
		print("[fear] %7.1f  glimpse %s ended: %s" % [clock, kind, why])


# ================================================================================================ helpers (used by scares)
## Schedules fn after delay seconds of director time (advances with tick: pauses with the game, works in tests).
func after(delay: float, fn: Callable) -> void:
	_jobs.append({"t": clock + maxf(delay, 0.0), "fn": fn})


func _run_jobs() -> void:
	if _jobs.is_empty():
		return
	var due: Array = []
	var i := _jobs.size() - 1
	while i >= 0:
		if float(_jobs[i].t) <= clock:
			due.append(_jobs[i])
			_jobs.remove_at(i)
		i -= 1
	due.reverse()
	for j in due:
		var fn: Callable = j.fn
		if fn.is_valid():
			fn.call()


func sfx(sound: String, pos: Variant, volume := 1.0, opts := {}) -> Variant:
	if sim:
		log_sound(sound, pos, volume)
		return null
	var o := opts.duplicate()
	o["volume"] = volume
	if pos is Vector3:
		o["position"] = pos
	return Audio.play(sound, o)


func log_sound(sound: String, _pos: Variant, volume: float) -> void:
	sounds.append([snappedf(clock, 0.01), sound, snappedf(volume, 0.01)])
	if sounds.size() > 6000:
		sounds.pop_front()


func say(text: String, seconds := 2.5) -> void:
	var ui = Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method("subtitle"):
		return
	for ch in ["!", "?", ":", ";", "»"]:
		text = text.replace(" " + ch, " " + ch)
	ui.call("subtitle", text, seconds, {})


func look_call(method: String, args: Array) -> void:
	if sim:
		look_log.append([snappedf(clock, 0.01), method])
		return
	if _quality_script == null:
		_quality_script = load("res://scripts/render/quality.gd")
	if _quality_script != null and _quality_script.has_method(method):
		_quality_script.callv(method, args)


func light_call(method: String, args: Array) -> void:
	var lt = world_get("lighting")
	if lt != null and is_instance_valid(lt) and lt.has_method(method):
		lt.callv(method, args)


func world_get(prop: String) -> Variant:
	var w = world()
	if w == null:
		return null
	var v = w.get(prop)
	if v is Object and not is_instance_valid(v):
		return null
	return v


func world_call(method: String, args: Array) -> void:
	var w = world()
	if w != null and w.has_method(method):
		_fire_async(w, method, args)


## Fire-and-forget a method that may be a coroutine (world.rock_chair awaits the chair).
func _fire_async(obj: Object, method: String, args: Array) -> void:
	await obj.callv(method, args)


func world_anim_bool(prop: String) -> bool:
	var a = world_get("anim")
	return a != null and a.get(prop) == true


func handle(id: String) -> Variant:
	var hs = world_get("handles")
	if hs is Dictionary:
		var h = (hs as Dictionary).get(id)
		if h is Object and is_instance_valid(h):
			return h
	return null


func pflag(flag: String) -> bool:
	var pz = puzzles()
	return pz != null and d_pflag(pz, flag)


func player_has(method: String) -> bool:
	var pl = player()
	return pl != null and pl.has_method(method)


## A short disorienting blur after a bang (look module set_blur), only while she sleeps (her jumpscare owns the blur).
func daze(amount: float, seconds: float) -> void:
	look_call("set_blur", [amount])
	after(seconds, func() -> void:
		var e = entity()
		if e == null or String(e.get("state")) != "jumpscare":
			look_call("set_blur", [0.0]))


func flinch(strength: float) -> void:
	var pl = player()
	if pl != null and pl.has_method("flinch"):
		pl.call("flinch", strength)


func torch_stutter(seconds: float) -> void:
	var pl = player()
	if pl != null and pl.has_method("flashlight_stutter"):
		pl.call("flashlight_stutter", seconds)


func line_blocked(a: Vector3, b: Vector3) -> bool:
	var w = world()
	if w != null and w.has_method("line_blocked"):
		return bool(w.call("line_blocked", a, b))
	return false


func looks_at(p: Vector3, cos_min: float, max_dist: float, los: bool) -> bool:
	var eye: Vector3 = c.get("eye", Vector3.ZERO)
	var to := p - eye
	var dist := to.length()
	if dist > max_dist or dist < 1e-3:
		return false
	if (c.get("fwd", Vector3.FORWARD) as Vector3).dot(to / dist) < cos_min:
		return false
	return not los or not line_blocked(eye, p)


func player() -> Node:
	var p = Game.player
	return p if p != null and is_instance_valid(p) else null


func entity() -> Node:
	var e = Game.entity
	return e if e != null and is_instance_valid(e) else null


func world() -> Node:
	var w = Game.world
	return w if w != null and is_instance_valid(w) else null


func puzzles() -> Node:
	var p = Game.puzzles
	return p if p != null and is_instance_valid(p) else null


func garderie() -> Node:
	var g = Game.get("garderie")
	if g != null and is_instance_valid(g):
		if _g_light_scale < 0.0 and g.get("light_scale") != null:
			_g_light_scale = float(g.get("light_scale"))
		return g
	return null


# ================================================================================================ physics fake-outs
func _prop_parent() -> Node:
	var m = Game.main
	if m != null and is_instance_valid(m) and m is Node3D:
		return m
	var w = world()
	return w if w != null else get_parent()


## A box of toys knocked off a furniture top: on_hit(pos, speed) fires at the first hard impact.
func spawn_fall(top: Vector3, push: Vector3, on_hit: Callable) -> void:
	if sim:
		after(0.55, func() -> void: on_hit.call(Vector3(top.x, 0.1, top.z) + push * 0.45, 4.0))
		return
	var y := top.y
	var w = world()
	if w != null and w.has_method("ground_probe"):
		var g := float(w.call("ground_probe", top.x, top.z, float(R.ceilingY) - 0.05))
		if not is_nan(g) and g > 0.25:
			y = g
	var body := RigidBody3D.new()
	body.name = "FearFallingBox"
	body.collision_layer = 0
	body.collision_mask = LAYER_WORLD
	body.mass = 1.4
	body.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.15
	body.physics_material_override = pm
	var size := Vector3(0.32, 0.2, 0.24)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.31, 0.2)
	mat.roughness = 0.9
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	_prop_parent().add_child(body)
	body.global_position = Vector3(top.x, y + size.y * 0.5 + 0.02, top.z) - push * 0.05
	body.rotation = Vector3(0.0, randf_range(-0.4, 0.4), 0.0)
	body.apply_central_impulse((push * 2.6 + Vector3(0, 0.6, 0)) * body.mass)
	body.apply_torque_impulse(Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2)))
	_props.append({"node": body, "kind": "fall", "t": 0.0, "ttl": 45.0, "hit": on_hit, "done": false, "vy": 0.0,
		"y0": body.global_position.y})
	# a few toy blocks spill out with it
	for i in 3:
		var b := RigidBody3D.new()
		b.collision_layer = 0
		b.collision_mask = LAYER_WORLD
		b.mass = 0.05
		var bs := CollisionShape3D.new()
		var bsh := BoxShape3D.new()
		bsh.size = Vector3.ONE * 0.05
		bs.shape = bsh
		b.add_child(bs)
		var bmi := MeshInstance3D.new()
		var bbm := BoxMesh.new()
		bbm.size = Vector3.ONE * 0.05
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = [Color(0.7, 0.15, 0.1), Color(0.15, 0.3, 0.65), Color(0.85, 0.7, 0.15)][i]
		bbm.material = bmat
		bmi.mesh = bbm
		b.add_child(bmi)
		_prop_parent().add_child(b)
		b.global_position = body.global_position + Vector3(randf_range(-0.1, 0.1), 0.14, randf_range(-0.1, 0.1))
		b.apply_central_impulse((push * randf_range(2.0, 3.2) + Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6))) * b.mass)
		_props.append({"node": b, "kind": "debris", "t": 0.0, "ttl": 45.0})


## A child's rubber ball bouncing down the stairs (tread by tread) and rolling toward the player.
func spawn_ball(pos: Vector3, vel: Vector3) -> void:
	if sim:
		for i in 7:
			after(0.35 * i + 0.2, func() -> void: log_sound("fear_ball", null, 0.6))
		after(0.5, func() -> void: kick(0.5))
		after(2.6, func() -> void:
			kick(0.35)
			flinch(0.45))
		return
	var ball := RigidBody3D.new()
	ball.name = "FearBall"
	ball.collision_layer = 0
	ball.collision_mask = LAYER_WORLD
	ball.mass = 0.12
	ball.continuous_cd = true
	ball.linear_damp = 0.15
	ball.angular_damp = 0.3
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.66
	pm.friction = 0.55
	ball.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.085
	cs.shape = sh
	ball.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.085
	sm.height = 0.17
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.07, 0.06)
	mat.roughness = 0.45
	sm.material = mat
	mi.mesh = sm
	ball.add_child(mi)
	_prop_parent().add_child(ball)
	ball.global_position = pos
	ball.linear_velocity = vel
	_props.append({"node": ball, "kind": "ball", "t": 0.0, "ttl": 70.0, "vy": 0.0, "tread": -99, "bottom": false, "first": true})


func _update_props(dt: float) -> void:
	var i := _props.size() - 1
	while i >= 0:
		var p: Dictionary = _props[i]
		var idx := i
		i -= 1
		var n = p.node
		if not is_instance_valid(n):
			_props.remove_at(idx)
			continue
		p.t = float(p.t) + dt
		if float(p.t) > float(p.ttl):
			n.queue_free()
			_props.remove_at(idx)
			continue
		var b := n as RigidBody3D
		var v := b.linear_velocity
		var pos := b.global_position
		match String(p.kind):
			"fall":
				var fell := pos.y < float(p.y0) - 0.3
				if not p.done and ((float(p.vy) < -1.4 and v.y > float(p.vy) * 0.35) or (float(p.t) > 1.6 and fell)):
					p.done = true
					(p.hit as Callable).call(pos, -float(p.vy))
			"ball":
				var bounced := float(p.vy) < -0.7 and v.y > float(p.vy) * 0.3
				if bounced:
					sfx("fear_ball", pos, clampf(-float(p.vy) / 4.0, 0.25, 1.0))
					if p.first:
						p.first = false
						kick(0.5)
				# the ramp collider is smooth: every tread edge it rolls over is a bounce you hear
				if pos.x < float(ST.maxX) and pos.z > float(ST.topZ) and pos.z < float(ST.bottomZ) and pos.y > 0.15:
					var tr := floori((pos.z - float(ST.topZ)) / float(ST.treadDepth))
					if tr != int(p.tread) and v.length() > 0.5:
						p.tread = tr
						if not bounced:
							sfx("fear_ball", pos, clampf(v.length() / 4.5, 0.25, 0.8))
				if not p.bottom and pos.z > float(ST.bottomZ) and pos.y < 0.3:
					p.bottom = true
					var to: Vector3 = c.get("feet", pos) - pos
					to.y = 0.0
					if to.length() > 0.3:
						b.apply_central_impulse(to.normalized() * 0.14)
					kick(0.35)
					flinch(0.45)
		p.vy = v.y


func _clear_props() -> void:
	for p in _props:
		if is_instance_valid(p.node):
			p.node.queue_free()
	_props.clear()


# ================================================================================================ debug
func _parse_args() -> void:
	var lv := String(Settings.get_value("fear", "extreme"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fear="):
			lv = a.get_slice("=", 1)
		elif a == "--fear-log":
			_log_on = true
		elif a.begins_with("--fear-scare="):
			for s in a.get_slice("=", 1).split(",", false):
				_forced.append(s)
		elif a.begins_with("--fear-bpm="):
			_hold_bpm = a.get_slice("=", 1).to_float()
		elif a == "--fear-hold":
			hold_glimpses = true
		elif a.begins_with("--fear-seed="):
			_seed = a.get_slice("=", 1).to_int()
	level = lv if lv in ["normal", "extreme", "off"] else "extreme"
	if _seed != 0:
		_prng.seed = _seed + 3
	if _hold_bpm > 0.0:
		after(0.0, func() -> void: heart.hold_bpm = _hold_bpm)

