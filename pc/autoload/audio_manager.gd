## Audio module — autoload "Audio": sample-based 3D horror mixer (port of src/audio/Audio.js, see ARCHITECTURE_PC.md §Audio).
## Public API (keep):
##   play(name: String, opts := {}) -> SoundHandle with stop(fade := 0.0), set_volume_db(db), set_position(v)
##       opts: position (Vector3, positional 3D sound), volume_db (float), pitch (float), bus (String), delay (float)
##   loop(name: String, opts := {}) -> same handle (looping until stop())
##   set_fear(v: float)  set_paused(paused: bool)  set_master_volume(v: float)  stop_all(fade := 0.3)
## Sound names = keys of res://assets/audio/manifest.json (63 recorded CC0 sounds) — see the web version's list.
##
## Extensions (all optional):
##   opts also accepts the web names: volume (linear), rate (= pitch), filter_hz / filterHz (low-pass), positional (false =
##     never 3D), no_jitter, dry (no reverb, e.g. UI), attach (Node3D to follow) + attach_offset; bus may be a category
##     ("sfx", "foley", "ambience", "music", "voice") or any bus name; loop() also: offset (s), fade_in / fadeIn (s), unique.
##   SoundHandle: set_volume(linear), set_pitch(p, seconds := 0.0) / set_rate(r, seconds := 0.15) (glide), set_filter(hz),
##     attach_to(node, offset), is_playing() / playing, name.
##   names (all sound names), has_sound(name), is_loaded() + signal library_loaded(stats), stats(), meter(),
##   heartbeat_external (fear module beat-synced heartbeat), EXTRA_MANIFESTS (res://assets/audio/fear/manifest.json),
##   debug arg (after --): --audio-test runs res://scripts/audio/tests/audio_selftest.gd once the game is playing.
## Loops are idempotent per name (+ position within 1 m; `single` sounds share one instance): loop('clock_tick') twice
## returns two handles on ONE voice, which stops when every handle has been stopped. 'ambience' = 'room_tone'.
##
## How it maps to the web engine:
##   * samples: manifest-driven AudioStreamMP3 library loaded with threaded requests at startup (loops flagged loop=true),
##     random variation never twice in a row, gainDb + one-shot jitter (pitch ±3 %, gain ±2 dB), leading-silence trim.
##   * voices: pooled AudioStreamPlayer3D (positional, doppler off, equal-power panning) and AudioStreamPlayer (2D);
##     distance = Web Audio "inverse" model per sound (ref/rolloff, fade 20 -> 25 m) computed here (ATTENUATION_DISABLED)
##     so the per-voice high-shelf filter of AudioStreamPlayer3D can be driven exactly for occlusion / air absorption /
##     head shadow; non-positional sounds that need a filter (held breath, drone) are 3D players locked to the listener.
##   * space: zones (scripts/audio/acoustics.gd): ceiling / upstairs hall behind the door (continuous with the door's
##     opening angle) / walls / outside / closet / nook doorway diffraction -> per-voice low-pass + gain.
##   * reverb (web topology): a reverberant voice also plays a synced "send" copy without distance attenuation (uniform
##     reverberant field: far sources sound wetter) into the reverb of the source's zone (listener's zone for 2D sounds):
##     carpeted-basement reverb or the darker, longer laundry-nook / stairwell / hall reverb. Levels and decay times are
##     calibrated against the web version (scripts/audio/tests/audio_test.gd). Bus graph: scripts/audio/buses.gd ->
##     res://default_bus_layout.tres (loaded by Godot at startup, rebuilt in code if missing).
##   * mix: category buses (sfx, foley, ambience, music, voice = the creature, never ducked) with ducking under the
##     jumpscare / stinger / light pop, ambience ducked while chased and muffled while hidden; pause = duck + low-pass;
##     glue compressor + -1 dBFS hard limiter on Master; master volume from Settings 'volume'.
##   * self-driven layers (Events): sprint panting (player_stamina), heartbeat slow/fast + scared breathing + sub drone
##     (fear), held breath while hidden (player_hide), stinger + heartbeat + gasp (entity_spotted), chase music
##     (entity_state), power hum: light buzz + fan (power_changed), beds: room tone, furnace cycle, wind gusts, alarm
##     clock tick; random house life (creaks, steps above, knocks) while the creature sleeps.
extends Node

signal library_loaded(stats: Dictionary)

const Defs := preload("res://scripts/audio/sound_defs.gd")
const Acoustics := preload("res://scripts/audio/acoustics.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Voice := preload("res://scripts/audio/voice.gd")
const LoopEntry := preload("res://scripts/audio/loop_entry.gd")
const PovLayer := preload("res://scripts/audio/pov_layer.gd")

const MANIFEST_PATH := "res://assets/audio/manifest.json"
## Extra manifests merged into the library (same format, new names only): the fear module's synthesized sounds.
const EXTRA_MANIFESTS := ["res://assets/audio/fear/manifest.json"]
const SELFTEST_PATH := "res://scripts/audio/tests/audio_selftest.gd"
const POOL_3D := 64
const POOL_2D := 24
## Web `_sendLevel`: reverb send = SEND_LEVEL x rv x zone send (acoustics.SEND_OF_ZONE). No send below MIN_RV.
const SEND_LEVEL := 0.32
const MIN_RV := 0.1
## × project audio/general/3d_panning_strength (0.5) = 0.7: a source hard left is ~10.5 dB lower in the right ear.
const PANNING := 1.4
## Head-locked 3D voices are panned to the centre (equal power: -3 dB per ear): give it back.
const CENTER_COMP_DB := 3.0103
const MAX_DB_3D := 6.0

const Z_ROOM := Acoustics.Z_ROOM
const Z_NOOK := Acoustics.Z_NOOK
const Z_CLOSET := Acoustics.Z_CLOSET
const R := Layout.ROOM
const ST := Layout.STAIRS
const AL := Layout.ALCOVE
const UH := Layout.UPPER_HALL


## Handle returned by play() / loop(). A finished or refused sound returns a dead handle: every call is a no-op.
class SoundHandle extends RefCounted:
	var name := ""
	var playing: bool:
		get:
			return is_playing()
	var _mgr = null     # the Audio autoload (untyped: calls its private helpers)
	var _voice = null   # one-shot voice (voice.gd)
	var _entry = null   # shared loop (loop_entry.gd): this handle is one of its owners
	var _live := false

	## Stops the sound (fade in seconds; 0 = immediate, still click-free). For a loop: releases this owner only.
	func stop(fade := 0.0) -> void:
		if not _live:
			return
		if _entry != null:
			_live = false
			_mgr._release(_entry, fade)
		elif _voice != null:
			_mgr._stop_voice(_voice, fade)

	## Volume relative to the sound's default level, in dB (0 = default).
	func set_volume_db(db: float) -> void:
		set_volume(db_to_linear(db))

	## Volume relative to the sound's default level, linear (1 = default).
	func set_volume(v: float) -> void:
		if not _live:
			return
		v = maxf(0.0, v)
		if _entry != null:
			_entry.volume = v
			if _entry.voice != null:
				_entry.voice.v = v
		elif _voice != null:
			_voice.v = v

	## Moves a positional sound. A loop started without position becomes positional.
	func set_position(p: Vector3) -> void:
		if not _live:
			return
		if _entry != null:
			_mgr._loop_set_position(_entry, p)
		elif _voice != null and not _voice.dead and _voice.is3d and not _voice.head_locked:
			_voice.pos = p
			_voice.attach = null

	## Follows a node (e.g. the creature's head) every frame.
	func attach_to(node: Node3D, offset := Vector3.ZERO) -> void:
		if not _live or node == null:
			return
		if _entry != null:
			_entry.attach = node
			_entry.attach_offset = offset
			_entry.follow = false
			_mgr._loop_set_position(_entry, node.global_position + offset)
			if _entry.voice != null:
				_entry.voice.attach = node
				_entry.voice.attach_offset = offset
		elif _voice != null and not _voice.dead and _voice.is3d and not _voice.head_locked:
			_voice.attach = node
			_voice.attach_offset = offset

	func set_pitch(p: float, seconds := 0.0) -> void:
		set_rate(p, seconds)

	## Playback rate (pitch + speed), gliding over `seconds`.
	func set_rate(r: float, seconds := 0.15) -> void:
		if not _live:
			return
		if _entry != null:
			_entry.rate = r
			if _entry.voice != null:
				_mgr._voice_set_rate(_entry.voice, r, seconds)
		elif _voice != null:
			_mgr._voice_set_rate(_voice, r, seconds)

	## Low-pass the sound (Hz, 0 = off). Works on positional sounds and on loops created with a filter.
	func set_filter(hz: float) -> void:
		if not _live:
			return
		if _entry != null:
			_entry.filter_hz = maxf(0.0, hz)
			if _entry.voice != null:
				_entry.voice.filter_hz = _entry.filter_hz
		elif _voice != null:
			_voice.filter_hz = maxf(0.0, hz)

	func is_playing() -> bool:
		if not _live:
			return false
		if _entry != null:
			return not _entry.stopped
		return _voice != null and not _voice.dead and not _voice.stopping


## Recorded variations of one sound name.
class Sample:
	var name := ""
	var paths := PackedStringArray()
	var streams: Array = []                  # AudioStream per path (null while loading / failed)
	var alt: Array = []                      # same data with the opposite loop flag (play() of a loop / loop() of a one-shot)
	var ready := PackedInt32Array()          # indices of loaded streams
	var lead := PackedFloat32Array()         # leading silence per file (s), -1 = not analysed yet
	var pending := 0
	var failed := 0
	var loop := false
	var gain_db := 0.0
	var last := -1                           # index in `ready` of the last variation played


var names := PackedStringArray()

var _defs := {}
var _default_def = null
var _samples := {}
var _pending_paths := {}                     # res path -> Sample (threaded loads not collected yet)
var _loaded := false
var _n_files := 0
var _n_loaded := 0
var _n_failed := 0
var _seconds := 0.0
var _warned := {}
var _last := {}                              # name -> time of the last play (dedupe)
var _noop: SoundHandle

var _voices: Array = []                      # voice.gd
var _loops: Array = []                       # loop_entry.gd
var _free3d: Array = []
var _free2d: Array = []

# mix state
var _user_vol := 0.85
var _paused := false
var _fear := 0.0
var _stamina := 1.0
var _hidden := false
var _chase := false
var _entity_state := "dormant"
var _game_state := "loading"
var _power := true
var _fl_on := false
var _low_cpu := false
var _max_voices := 48
var _dk := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])   # ducking: ambience, sfx, foley, music
var _dk_hold := 0.0
var _dk_rel := 1.5
var _chase_duck := 1.0
var _cat_cur := {"sfx": -1.0, "foley": -1.0, "ambience": -1.0, "music": -1.0, "voice": -1.0}
var _master_g := -1.0
var _pause_hz := 20500.0
var _amb_hz := 20500.0

# beds & life
var _bed_on := false
var _room: SoundHandle = null
var _clock: SoundHandle = null
var _wind: SoundHandle = null
var _buzz: SoundHandle = null
var _fan: SoundHandle = null
var _furn: SoundHandle = null
var _furn_on := false
var _furn_t := 0.0
var _wind_t := 0.0
var _wind_target := 0.6
var _wind_v := 0.6
var _wind_sent := -1.0
var _life_t := 30.0
var _hold_t := 3.0
var _holding := false
var _last_stair_creak := -10.0

# listener / acoustics
var _lpos := Vector3(0.0, 1.6, 0.0)
var _lfwd := Vector3(0.0, 0.0, -1.0)
var _has_listener := false
var _lz := Z_ROOM
var _zone_t := 0.0
var _door_t := 0.0

# buses
var _bus_rebuilt := false
var _master_amp: AudioEffectAmplify = null
var _pause_lpf: AudioEffectLowPassFilter = null
var _pause_lpf_loc := Vector2i(-1, -1)
var _cat_amps := {}                          # cat -> Array[AudioEffectAmplify]
var _amb_lpfs: Array = []                    # AudioEffectLowPassFilter
var _amb_lpf_locs: Array = []                # Vector2i(bus, effect)

# POV layers
var _l_run: PovLayer
var _l_hb: PovLayer
var _l_hbf: PovLayer
var _l_scared: PovLayer
var _l_hide: PovLayer
var _l_drone: PovLayer
var _l_chase: PovLayer
var _layers: Array = []

var _args := {}
var _selftest_started := false
## true while an external heartbeat plays (fear module: one beat per simulated heart beat): the fear-driven heartbeat
## loops stay silent (panting, scared / hidden breathing and the drone are unchanged).
var heartbeat_external := false


# ======================================================================================================== lifecycle
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000 # after gameplay has moved things this frame
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_defs = Defs.build_all()
	_default_def = Defs.default_def()
	_noop = SoundHandle.new()
	_setup_buses()
	_build_pools()
	_l_run = PovLayer.new(self, "player_breath_run", {"fade_in": 0.4})
	_l_hb = PovLayer.new(self, "heartbeat", {"fade_in": 0.5})
	_l_hbf = PovLayer.new(self, "heartbeat_fast", {"fade_in": 0.5})
	_l_scared = PovLayer.new(self, "player_breath_scared", {"fade_in": 0.8})
	_l_hide = PovLayer.new(self, "player_breath_scared", {"fade_in": 1.0, "filter_hz": 1700.0})
	_l_drone = PovLayer.new(self, "ambience_drone", {"fade_in": 3.0, "filter_hz": 350.0})
	_l_chase = PovLayer.new(self, "chase_music", {"fade_in": 0.35, "offset": 0.0})
	_layers = [_l_run, _l_hb, _l_hbf, _l_scared, _l_hide, _l_drone, _l_chase]
	_user_vol = clampf(float(Settings.get_value("volume", 0.85)), 0.0, 1.0)
	_set_quality(String(Settings.get_value("quality", "high")))
	Events.power_changed.connect(_on_power)
	Events.player_stamina.connect(_on_stamina)
	Events.player_hide.connect(_on_hide)
	Events.player_bump.connect(_on_bump)
	Events.player_flashlight.connect(_on_flashlight)
	Events.entity_spotted.connect(_on_spotted)
	Events.entity_state.connect(_on_entity_state)
	Events.game_state.connect(_on_game_state)
	Events.settings_changed.connect(_on_setting)
	_load_manifest()


## Quit / scene teardown: stop every playback (the AudioServer would keep the streams alive past the resource check)
## and break the voice <-> loop reference cycles.
func _exit_tree() -> void:
	for p in _pending_paths.keys():
		ResourceLoader.load_threaded_get(p) # never leave loader tasks running at exit
	_pending_paths.clear()
	for v in _voices:
		v.entry = null
		for p in [v.player, v.twin]:
			if p != null:
				p.stop()
				p.stream = null
	for e in _loops:
		e.voice = null
	for p in _free3d + _free2d:
		p.stop()
		p.stream = null
	_voices.clear()
	_loops.clear()
	for l in _layers:
		l.ref = null
	_room = null
	_clock = null
	_wind = null
	_buzz = null
	_fan = null
	_furn = null
	_samples.clear()
	# A stopped playback is only retired by the mixer thread (and freed with the AudioServer); the engine tears the
	# scene down without another mix: wait (once, at quit) until the mixer has run after the stops, so nothing is left
	# "in use" at exit. Capped: with no running driver the wait simply times out.
	var t_stop := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t_stop < 300000:
		var last_mix := Time.get_ticks_usec() - int(AudioServer.get_time_since_last_mix() * 1000000.0)
		if last_mix > t_stop:
			OS.delay_msec(15) # let that mix chunk finish
			break
		OS.delay_msec(2)


func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.25)
	if not _pending_paths.is_empty():
		_poll_loading()
	_update_listener()
	var dt_door := _door_openness()
	if absf(dt_door - _door_t) > 0.004:
		_door_t = dt_door
		_zone_t = 0.0
	_zone_t -= dt
	if _zone_t <= 0.0:
		_zone_t = 0.1
		_update_zones()
	for e in _loops:
		if e.voice == null and not e.stopped:
			e.retry_t -= dt
			if e.retry_t <= 0.0:
				_start_entry(e, 0.3)
	_update_layers(dt)
	_update_buses(dt)
	_update_bed(dt)
	_update_life(dt)
	_update_voices(dt)


# ======================================================================================================== public API
func play(sound_name: String, opts := {}) -> SoundHandle:
	var n: String = Defs.ALIASES.get(sound_name, sound_name)
	var def = _def(n)
	if def == null:
		return _noop
	var o: Dictionary = opts if opts != null else {}
	var now := _now()
	if n == "footstep_carpet" or n == "footstep_wood":
		# surface awareness (laundry nook = painted concrete) + creaky stairs under the player
		var p = o.get("position")
		var z := Acoustics.zone_of(p) if p is Vector3 else _lz
		if z == Z_NOOK:
			n = "footstep_concrete"
			def = _defs[n]
		elif not (p is Vector3) and n == "footstep_wood" and _player_on_stairs() and randf() < 0.22 and now - _last_stair_creak > 1.8:
			_last_stair_creak = now
			play("stair_creak", {"position": Vector3(_lpos.x, _lpos.y - 1.45, _lpos.z), "volume": 0.3, "delay": 0.04})
	var last = _last.get(n)
	if last != null and now - float(last) < def.gap:
		return _noop
	var s: Sample = _samples.get(n)
	if s == null:
		_warn_once("nosample:" + n, "[audio] son sans enregistrement : \"%s\"" % n)
		return _noop
	var si := _pick(s)
	if si < 0:
		return _noop
	_last[n] = now
	_admit(n, def)
	if n == "jumpscare":
		_duck(0.08, 0.25, 0.2, 0.0, 1.8, 1.4)
		_l_chase.kill(0.04)
	elif n == "stinger":
		_duck(0.3, 0.75, 0.85, 1.0, 0.8, 2.2)
	elif n == "light_pop" or n == "breaker_flip":
		_duck(0.6, 1.0, 1.0, 1.0, 0.25, 1.2)
	var v = _spawn(n, def, s, si, o, false, null, 0.0)
	if v == null:
		return _noop
	var h := SoundHandle.new()
	h._mgr = self
	h._voice = v
	h._live = true
	h.name = n
	return h


func loop(sound_name: String, opts := {}) -> SoundHandle:
	var n: String = Defs.ALIASES.get(sound_name, sound_name)
	var def = _def(n)
	if def == null:
		return _noop
	var o: Dictionary = opts if opts != null else {}
	var pv = o.get("position")
	var has_pos := pv is Vector3
	var e = null if bool(o.get("unique", false)) else _find_loop(n, def, has_pos, pv)
	if e != null:
		if o.has("volume"):
			e.volume = maxf(0.0, float(o["volume"]))
			if e.voice != null:
				e.voice.v = e.volume
		if has_pos:
			e.follow = false
			if e.has_position:
				e.position = pv
				if e.voice != null and e.voice.is3d and not e.voice.head_locked:
					e.voice.pos = pv
	else:
		if not _samples.has(n):
			_warn_once("nosample:" + n, "[audio] son sans enregistrement : \"%s\"" % n)
			return _noop
		e = LoopEntry.new()
		e.name = n
		e.def = def
		e.volume = maxf(0.0, float(o.get("volume", 1.0)))
		e.volume_db = float(o.get("volume_db", 0.0))
		e.rate = float(o.get("rate", o.get("pitch", 1.0)))
		e.filter_hz = float(o.get("filter_hz", o.get("filterHz", 0.0)))
		e.unique = bool(o.get("unique", false))
		e.offset = float(o.get("offset", -1.0))
		e.fade_in = float(o.get("fade_in", o.get("fadeIn", 0.6)))
		e.positional = o.get("positional", true) != false
		e.bus = String(o.get("bus", ""))
		e.dry = bool(o.get("dry", false))
		var a = o.get("attach")
		if a is Node3D and is_instance_valid(a):
			e.attach = a
			e.attach_offset = o.get("attach_offset", Vector3.ZERO)
		if has_pos:
			e.has_position = true
			e.position = pv
		elif e.attach != null:
			e.has_position = true
			e.position = e.attach.global_position + e.attach_offset
		e.follow = not has_pos and e.attach == null and def.follow
		if not e.has_position and def.pos != "" and e.positional:
			e.has_position = true
			e.position = _default_pos(def.pos)
		_loops.append(e)
		_start_entry(e, e.fade_in)
	e.refs += 1
	var h := SoundHandle.new()
	h._mgr = self
	h._entry = e
	h._live = true
	h.name = n
	return h


func set_fear(v: float) -> void:
	if not is_nan(v):
		_fear = clampf(v, 0.0, 1.0)


func set_paused(p: bool) -> void:
	_paused = p


func set_master_volume(v: float) -> void:
	if not is_nan(v):
		_user_vol = clampf(v, 0.0, 1.0)


func stop_all(fade := 0.3) -> void:
	for i in range(_loops.size() - 1, -1, -1):
		var e = _loops[i]
		e.refs = 1
		_release(e, fade)
	for i in range(_voices.size() - 1, -1, -1):
		_stop_voice(_voices[i], fade)
	for l in _layers:
		l.kill(fade)
	_room = null
	_clock = null
	_wind = null
	_buzz = null
	_fan = null
	_furn = null
	_bed_on = false


func has_sound(sound_name: String) -> bool:
	return _samples.has(Defs.ALIASES.get(sound_name, sound_name))


func is_loaded() -> bool:
	return _loaded


## Debug / test summary.
func stats() -> Dictionary:
	var loops := PackedStringArray()
	for e in _loops:
		loops.append(e.name + ("" if e.voice != null else "(...)"))
	var playing := 0
	var sends := 0
	for v in _voices:
		if v.started and not v.stopping:
			playing += 1
		if v.twin != null:
			sends += 1
	return {
		"names": _samples.size(), "files": _n_files, "loaded": _n_loaded, "failed": _n_failed,
		"pending": _pending_paths.size(), "seconds": snappedf(_seconds, 0.1), "voices": _voices.size(), "playing": playing, "sends": sends,
		"loops": loops, "free3d": _free3d.size(), "free2d": _free2d.size(), "listener_zone": Acoustics.ZONE_NAMES[_lz],
		"door": snappedf(_door_t, 0.01), "buses": AudioServer.bus_count, "bus_layout_rebuilt": _bus_rebuilt,
		"bed": _bed_on, "low_cpu": _low_cpu, "mix_rate": AudioServer.get_mix_rate(),
	}


## Master output peak (dBFS), both channels.
func meter() -> Dictionary:
	var l := AudioServer.get_bus_peak_volume_left_db(0, 0)
	var r := AudioServer.get_bus_peak_volume_right_db(0, 0)
	return {"peak_db": maxf(l, r), "left_db": l, "right_db": r}


# ======================================================================================================== library
func _res_path(f: String) -> String:
	if f.begins_with("res://"):
		return f
	return "res://" + f.trim_prefix("./").trim_prefix("/")


func _load_manifest() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var j = JSON.parse_string(text) if text != "" else null
	if typeof(j) != TYPE_DICTIONARY:
		push_warning("[audio] manifest indisponible (%s) — aucun son." % MANIFEST_PATH)
		_loaded = true
		return
	for extra in EXTRA_MANIFESTS:
		var ej = JSON.parse_string(FileAccess.get_file_as_string(extra)) if FileAccess.file_exists(extra) else null
		if typeof(ej) == TYPE_DICTIONARY:
			for k in ej:
				if not j.has(k):
					j[k] = ej[k]
	for n in j:
		var m = j[n]
		if typeof(m) != TYPE_DICTIONARY or typeof(m.get("files")) != TYPE_ARRAY or m["files"].is_empty():
			continue
		var s := Sample.new()
		s.name = n
		s.loop = bool(m.get("loop", false))
		var d = _defs.get(n)
		s.gain_db = float(m["gainDb"]) if m.has("gainDb") and m["gainDb"] != null else (d.g if d != null else 0.0)
		for f in m["files"]:
			var p := _res_path(String(f))
			s.paths.append(p)
			s.streams.append(null)
			s.alt.append(null)
			s.lead.append(-1.0)
			_n_files += 1
			if ResourceLoader.load_threaded_request(p, "AudioStream") == OK:
				_pending_paths[p] = s
				s.pending += 1
			else:
				s.failed += 1
				_n_failed += 1
				_warn_once("load:" + p, "[audio] échec du son %s" % p)
		_samples[n] = s
	var all := {}
	for n in _defs:
		all[n] = true
	for n in _samples:
		all[n] = true
	for n in Defs.ALIASES:
		all[n] = true
	names = PackedStringArray(all.keys())
	names.sort()
	if _pending_paths.is_empty():
		_finish_loading()


func _poll_loading() -> void:
	for p in _pending_paths.keys():
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_collect(p)
	if _pending_paths.is_empty():
		_finish_loading()


## Takes a threaded load result (blocks if it is still loading).
func _collect(p: String) -> void:
	var s: Sample = _pending_paths.get(p)
	if s == null:
		return
	_pending_paths.erase(p)
	s.pending -= 1
	var i := s.paths.find(p)
	var res: Resource = null
	var status := ResourceLoader.load_threaded_get_status(p)
	if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		res = ResourceLoader.load_threaded_get(p) # blocks while still in progress
	if res is AudioStream and i >= 0:
		var st := res as AudioStream
		if s.loop:
			_set_loop(st)
		s.streams[i] = st
		s.ready.append(i)
		_n_loaded += 1
		_seconds += st.get_length()
	else:
		s.failed += 1
		_n_failed += 1
		_warn_once("load:" + p, "[audio] échec du son %s" % p)


func _finish_loading() -> void:
	if _loaded:
		return
	_loaded = true
	library_loaded.emit(stats())


func _set_loop(st: AudioStream, on := true) -> void:
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif "loop" in st:
		st.set("loop", on)


## The stream of variation i with the wanted loop flag: the imported resource carries the manifest's flag, a duplicate
## (shares the compressed data) serves the other use — the web plays a loop sample once with play() and loops one-shot
## samples with loop() (e.g. the rocking chair).
func _stream_for(s: Sample, i: int, want_loop: bool) -> AudioStream:
	if want_loop == s.loop:
		return s.streams[i]
	if s.alt[i] == null:
		var d := (s.streams[i] as AudioStream).duplicate() as AudioStream
		_set_loop(d, want_loop)
		s.alt[i] = d
	return s.alt[i]


## Random variation, never the same twice in a row.
func _pick(s: Sample) -> int:
	if s.pending > 0:
		for p in s.paths:
			if _pending_paths.has(p):
				_collect(p)
		if _pending_paths.is_empty():
			_finish_loading()
	var n := s.ready.size()
	if n == 0:
		return -1
	var k := 0
	if n > 1:
		if s.last >= 0 and s.last < n:
			k = randi() % (n - 1)
			if k >= s.last:
				k += 1
		else:
			k = randi() % n
	s.last = k
	return s.ready[k]


## Leading digital silence of a one-shot (s), measured once by decoding its first 80 ms (web: _prep trim).
func _lead(s: Sample, i: int) -> float:
	var l: float = s.lead[i]
	if l >= 0.0:
		return l
	l = 0.0
	var st: AudioStream = s.streams[i]
	var pb := st.instantiate_playback()
	if pb != null:
		var mr := AudioServer.get_mix_rate()
		var lim := mini(int(mr * 0.08), int(st.get_length() * mr * 0.25))
		if lim > 64:
			pb.start(0.0)
			var buf: PackedVector2Array = pb.mix_audio(1.0, lim)
			pb.stop()
			var j := 0
			var nn := buf.size()
			while j < nn:
				var f := buf[j]
				if absf(f.x) > 0.0008 or absf(f.y) > 0.0008:
					break
				j += 1
			if j < nn and j > 32:
				l = float(j - 32) / mr # keep a hair of pre-roll
	s.lead[i] = l
	return l


func _def(n: String):
	var d = _defs.get(n)
	if d == null and _samples.has(n):
		d = _default_def
	if d == null:
		_warn_once("unknown:" + n, "[audio] son inconnu : \"%s\"" % n)
	return d


# ======================================================================================================== buses
func _setup_buses() -> void:
	_bus_rebuilt = Buses.ensure()
	_master_amp = Buses.find_effect("Master", "user_volume") as AudioEffectAmplify
	_pause_lpf = Buses.find_effect("Master", "pause_lowpass") as AudioEffectLowPassFilter
	_pause_lpf_loc = Vector2i(AudioServer.get_bus_index("Master"), Buses.find_effect_index("Master", "pause_lowpass"))
	for cat in Defs.CAT_LEVEL:
		var amps: Array = []
		for b in Buses.leaves_of(cat):
			var a := Buses.find_effect(b, "duck") as AudioEffectAmplify
			if a != null:
				amps.append(a)
		_cat_amps[cat] = amps
	for b in Buses.leaves_of("ambience"):
		var f := Buses.find_effect(b, "hidden_lowpass") as AudioEffectLowPassFilter
		if f != null:
			_amb_lpfs.append(f)
			_amb_lpf_locs.append(Vector2i(AudioServer.get_bus_index(b), Buses.find_effect_index(b, "hidden_lowpass")))
	_set_filter_enabled(_pause_lpf_loc, false)
	for loc in _amb_lpf_locs:
		_set_filter_enabled(loc, false)


func _set_filter_enabled(loc: Vector2i, on: bool) -> void:
	if loc.x < 0 or loc.y < 0:
		return
	if AudioServer.is_bus_effect_enabled(loc.x, loc.y) != on:
		AudioServer.set_bus_effect_enabled(loc.x, loc.y, on)


func _build_pools() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice3D_%02d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.max_distance = 0.0
		p.max_db = MAX_DB_3D
		p.panning_strength = PANNING
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.area_mask = 0
		p.attenuation_filter_cutoff_hz = 16000.0
		p.attenuation_filter_db = 0.0
		p.emission_angle_enabled = false
		add_child(p)
		_free3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Voice2D_%02d" % i
		add_child(p)
		_free2d.append(p)


func _take_player(is3d: bool) -> Node:
	var pool := _free3d if is3d else _free2d
	if pool.is_empty():
		# steal: a voice already fading out first, then the oldest of the lowest priority (never a loop)
		var victim = null
		var vp := 99
		for v in _voices:
			if v.dead or v.loop or v.player == null or v.is3d != is3d:
				continue
			var pr := 0 if v.stopping else 1 + int(Defs.CAT_PRIO.get(v.cat, 1))
			if victim == null or pr < vp or (pr == vp and v.t0 < victim.t0):
				victim = v
				vp = pr
		if victim == null:
			_warn_once("pool:%s" % is3d, "[audio] plus de voix %s libres" % ("3D" if is3d else "2D"))
			return null
		_dispose(victim)
	return pool.pop_back()


func _release_player(p: Node, is3d: bool) -> void:
	p.stop()
	p.stream = null
	if is3d:
		_free3d.append(p)
	else:
		_free2d.append(p)


# ======================================================================================================== voices
func _spawn(n: String, def, s: Sample, si: int, o: Dictionary, is_loop: bool, e, fade_in: float):
	var v := Voice.new()
	v.name = n
	v.def = def
	v.sample = s
	v.stream = _stream_for(s, si, is_loop)
	v.loop = is_loop
	v.entry = e
	v.cat = def.cat
	var jr := 1.0
	var jg := 0.0
	if not is_loop and def.jit and not bool(o.get("no_jitter", o.get("noJitter", false))):
		jr = 1.0 + randf_range(-0.03, 0.03)
		jg = randf_range(-2.0, 2.0)
	v.jr = jr
	var bus_opt := ""
	var has_pos := false
	var pos := Vector3.ZERO
	var att: Node3D = null
	var att_off := Vector3.ZERO
	var positional_ok := true
	if is_loop:
		v.v = e.volume
		v.rate = e.rate
		v.filter_hz = e.filter_hz
		v.base_db = s.gain_db + e.volume_db
		bus_opt = e.bus
		v.force_dry = e.dry
		has_pos = e.has_position
		pos = e.position
		if e.attach != null and is_instance_valid(e.attach):
			att = e.attach
			att_off = e.attach_offset
		positional_ok = e.positional
	else:
		v.v = maxf(0.0, float(o.get("volume", 1.0)))
		v.rate = float(o.get("rate", o.get("pitch", 1.0)))
		v.filter_hz = maxf(0.0, float(o.get("filter_hz", o.get("filterHz", 0.0))))
		v.base_db = s.gain_db + jg + float(o.get("volume_db", 0.0))
		bus_opt = String(o.get("bus", ""))
		v.force_dry = bool(o.get("dry", false))
		var p = o.get("position")
		if p is Vector3:
			has_pos = true
			pos = p
		var a = o.get("attach")
		if a is Node3D and is_instance_valid(a):
			att = a
			att_off = o.get("attach_offset", Vector3.ZERO)
		positional_ok = o.get("positional", true) != false
	v.rate_target = v.rate
	if bus_opt != "":
		var lc := bus_opt.to_lower()
		if Defs.CAT_LEVEL.has(lc):
			v.cat = lc
		elif AudioServer.get_bus_index(bus_opt) >= 0:
			v.bus_override = StringName(bus_opt)
	if positional_ok and (has_pos or att != null or def.pos != ""):
		v.is3d = true
		if att != null:
			v.attach = att
			v.attach_offset = att_off
			v.pos = att.global_position + att_off
		elif has_pos:
			v.pos = pos
		else:
			v.pos = _default_pos(def.pos)
		v.pos = _fix_pos(def, v.pos)
	elif (v.filter_hz > 0.0 or bool(o.get("head_locked", false))) and _has_listener:
		v.is3d = true
		v.head_locked = true
		v.pos = _head_pos()
	var player := _take_player(v.is3d)
	if player == null:
		return null
	v.player = player
	_zone_voice(v, true)
	v.bus = _route(v)
	if v.bus_override == &"" and not v.force_dry and v.cat != "music" and v.def.rv >= MIN_RV:
		var pool := _free3d if v.is3d else _free2d
		if not pool.is_empty(): # the send is optional: never steal a voice for it
			v.twin = pool.pop_back()
			v.twin3d = v.is3d
			v.twin_bus = Buses.leaf(v.cat, v.space)
	if is_loop:
		v.fade = 0.0
		v.fade_speed = 1.0 / maxf(0.01, fade_in)
		var span := v.stream.get_length()
		if e.offset >= 0.0:
			v.offset = fmod(e.offset, maxf(span, 0.01))
		elif def.rnd and span > 0.1:
			v.offset = randf() * span * 0.98
	else:
		v.fade = 1.0
		v.delay = maxf(0.0, float(o.get("delay", 0.0)))
		v.offset = _lead(s, si)
	v.fade_target = 1.0
	v.idx = _voices.size()
	_voices.append(v)
	v.t0 = _now()
	if v.delay <= 0.0:
		_start_voice(v)
	return v


func _start_voice(v) -> void:
	var p = v.player
	p.stream = v.stream
	p.bus = v.bus
	if v.is3d:
		p.panning_strength = 0.0 if v.head_locked else PANNING
	v.last_pos = Vector3(INF, INF, INF)
	v.last_db = 999.0
	v.last_pitch = -1.0
	v.last_shelf_db = 999.0
	v.last_shelf_hz = -1.0
	if v.twin != null:
		v.twin.stream = v.stream
		v.twin.bus = v.twin_bus
		if v.twin3d:
			v.twin.panning_strength = 0.0
		v.twin_last_db = 999.0
		v.twin_last_att = 999.0
		v.twin_last_hz = -1.0
	_apply(v, 0.0, true)
	p.play(v.offset)
	if v.twin != null:
		v.twin.play(v.offset) # same frame: both start on the same mix step (3D: next physics tick)
	v.started = true
	v.grace = 3
	v.t0 = _now()


func _stop_voice(v, fade: float) -> void:
	if v.dead or v.stopping:
		return
	v.stopping = true
	if not v.started:
		return # disposed by the next update
	v.fade_target = 0.0
	v.fade_speed = maxf(v.fade, 0.001) / maxf(0.008, fade)


func _dispose(v) -> void:
	if v.dead:
		return
	v.dead = true
	if v.player != null:
		_release_player(v.player, v.is3d)
		v.player = null
	if v.twin != null:
		_release_player(v.twin, v.twin3d)
		v.twin = null
	var i: int = v.idx
	if i >= 0 and i < _voices.size() and _voices[i] == v:
		var last = _voices.pop_back()
		if last != v:
			_voices[i] = last
			last.idx = i
	v.idx = -1
	if v.entry != null and v.entry.voice == v:
		v.entry.voice = null
		v.entry.retry_t = 0.0


func _voice_set_rate(v, r: float, seconds: float) -> void:
	if v.dead:
		return
	v.rate_target = r
	if seconds <= 0.0:
		v.rate = r
		v.rate_tau = 0.0
	else:
		v.rate_tau = maxf(0.01, seconds / 3.0) # web: setTargetAtTime(r, now, seconds / 3)


## Per-name voice limit + global voice cap (web _admit): stop the oldest of the same name / the least important.
func _admit(n: String, def) -> void:
	var count := 0
	var oldest = null
	var active := 0
	var victim = null
	var vp := 99
	for v in _voices:
		if v.stopping or v.dead:
			continue
		active += 1
		if v.loop:
			continue
		if v.name == n:
			count += 1
			if oldest == null or v.t0 < oldest.t0:
				oldest = v
		var pr := int(Defs.CAT_PRIO.get(v.cat, 1))
		if pr < vp or (pr == vp and victim != null and v.t0 < victim.t0):
			victim = v
			vp = pr
	if count >= def.max_voices and oldest != null:
		_stop_voice(oldest, 0.04)
		active -= 1
		if oldest == victim:
			victim = null
	if active >= _max_voices and victim != null:
		_stop_voice(victim, 0.03)


func _update_voices(dt: float) -> void:
	var i := _voices.size() - 1
	while i >= 0:
		var v = _voices[i]
		i -= 1
		if v.dead:
			continue
		if not v.started:
			if v.stopping:
				_dispose(v)
				continue
			v.delay -= dt
			if v.delay <= 0.0:
				_start_voice(v)
			continue
		if v.grace > 0:
			v.grace -= 1
		elif not v.player.playing:
			_dispose(v) # one-shot finished
			continue
		if v.fade != v.fade_target:
			v.fade = move_toward(v.fade, v.fade_target, v.fade_speed * dt)
		if v.stopping and v.fade <= 0.0:
			_dispose(v)
			continue
		if v.attach != null:
			if is_instance_valid(v.attach) and v.attach.is_inside_tree():
				v.pos = v.attach.global_position + v.attach_offset
			else:
				v.attach = null
		elif v.entry != null and v.entry.follow and v.is3d and not v.head_locked:
			var hp = _entity_head()
			if hp != null:
				v.pos = hp
				v.entry.position = hp
		_apply(v, dt, false)


## Pushes gain, distance, occlusion shelf, position and pitch of one voice to its player.
func _apply(v, dt: float, init: bool) -> void:
	var p = v.player
	var k := 1.0 if init else 1.0 - exp(-dt / 0.08)
	v.occ_g_cur += (v.occ_g - v.occ_g_cur) * k
	var g: float = v.v * v.fade * v.occ_g_cur
	if v.is3d:
		var shelf := Vector2(16000.0, 0.0)
		if v.head_locked:
			v.pos = _head_pos()
			if v.filter_hz > 0.0:
				shelf = Acoustics.shelf_for_lowpass(v.filter_hz)
		else:
			var to: Vector3 = v.pos - _lpos
			var d := to.length()
			g *= Acoustics.distance_gain(v.def.ref, v.def.roll, d)
			var hz: float = v.occ_hz
			if v.filter_hz > 0.0:
				hz = minf(hz, v.filter_hz)
			if hz < 15000.0:
				shelf = Acoustics.shelf_for_lowpass(hz)
			else:
				# no obstacle: air absorption + head shadow for a source behind the listener
				var air := -clampf((d - 1.5) * 0.6, 0.0, 4.0)
				var back := 0.0
				if d > 0.05:
					back = -3.0 * clampf(-_lfwd.dot(to / d), 0.0, 1.0)
				shelf = Vector2(6000.0, air + back)
		v.shelf_db += (shelf.y - v.shelf_db) * k
		v.shelf_lhz += (log(shelf.x) - v.shelf_lhz) * k
		if not v.pos.is_equal_approx(v.last_pos):
			p.global_position = v.pos
			v.last_pos = v.pos
	var db: float = linear_to_db(maxf(g, 1e-5)) + v.base_db - Buses.HEADROOM_DB
	if v.head_locked:
		db += CENTER_COMP_DB
	db = clampf(db, -80.0, MAX_DB_3D - 0.5)
	if absf(db - v.last_db) > 0.01:
		p.volume_db = db
		v.last_db = db
	if v.is3d:
		# Godot applies the shelf as db_to_linear((1 - min(1, m)) * attenuation_filter_db) where m = the voice's linear
		# gain (attenuation disabled, no max distance) and the RBJ shelf squares it: invert that to get shelf_db exactly.
		var m := db_to_linear(db)
		var att: float = (v.shelf_db * 0.5) / maxf(1.0 - minf(1.0, m), 0.05)
		if absf(att - v.last_shelf_db) > 0.02:
			p.attenuation_filter_db = att
			v.last_shelf_db = att
		var hzv := exp(v.shelf_lhz)
		if absf(hzv - v.last_shelf_hz) > v.last_shelf_hz * 0.01:
			p.attenuation_filter_cutoff_hz = hzv
			v.last_shelf_hz = hzv
	if v.twin != null:
		_apply_send(v, k)
	if v.rate_tau > 0.0:
		v.rate += (v.rate_target - v.rate) * (1.0 - exp(-dt / v.rate_tau))
		if absf(v.rate - v.rate_target) < 0.0005:
			v.rate = v.rate_target
			v.rate_tau = 0.0
	var pitch := maxf(0.05, v.rate * v.jr)
	if absf(pitch - v.last_pitch) > 0.0005:
		p.pitch_scale = pitch
		if v.twin != null:
			v.twin.pitch_scale = pitch
		v.last_pitch = pitch


## Reverb send of a voice: same gain chain without distance attenuation (uniform reverberant field), occlusion low-pass
## (+ user filter) but no air absorption / head shadow, centred.
func _apply_send(v, k: float) -> void:
	var t = v.twin
	v.send_cur += (v.send - v.send_cur) * k
	var g: float = v.v * v.fade * v.occ_g_cur * v.send_cur
	var db: float = linear_to_db(maxf(g, 1e-5)) + v.base_db - Buses.HEADROOM_DB
	if v.twin3d:
		db += CENTER_COMP_DB
	db = clampf(db, -80.0, MAX_DB_3D - 0.5)
	if absf(db - v.twin_last_db) > 0.01:
		t.volume_db = db
		v.twin_last_db = db
	if not v.twin3d:
		return
	var hz: float = v.occ_hz
	if v.filter_hz > 0.0:
		hz = minf(hz, v.filter_hz)
	var sh := Acoustics.shelf_for_lowpass(hz)
	v.twin_shelf_db += (sh.y - v.twin_shelf_db) * k
	v.twin_shelf_lhz += (log(sh.x) - v.twin_shelf_lhz) * k
	t.global_position = _head_pos()
	var att: float = (v.twin_shelf_db * 0.5) / maxf(1.0 - minf(1.0, db_to_linear(db)), 0.05)
	if absf(att - v.twin_last_att) > 0.02:
		t.attenuation_filter_db = att
		v.twin_last_att = att
	var hzv := exp(v.twin_shelf_lhz)
	if absf(hzv - v.twin_last_hz) > v.twin_last_hz * 0.01:
		t.attenuation_filter_cutoff_hz = hzv
		v.twin_last_hz = hzv


# ======================================================================================================== loops
func _find_loop(n: String, def, has_pos: bool, pos):
	for e in _loops:
		if e.name != n or e.unique or e.stopped:
			continue
		if def.single:
			return e
		if not has_pos and not e.has_position:
			return e
		if has_pos and e.has_position and e.position.distance_to(pos) < 1.0:
			return e
		if not has_pos and e.has_position and def.pos != "":
			return e # default-positioned sound asked again without a position
	return null


func _start_entry(e, fade_in: float) -> void:
	if e.stopped or e.voice != null:
		return
	var s: Sample = _samples.get(e.name)
	if s == null:
		e.retry_t = 1e9
		return
	var si := _pick(s)
	if si < 0:
		e.retry_t = 1e9
		return
	if e.follow and e.positional:
		var hp = _entity_head()
		if hp != null:
			e.has_position = true
			e.position = hp
	e.voice = _spawn(e.name, e.def, s, si, {}, true, e, fade_in)
	if e.voice == null:
		e.retry_t = 0.25


func _respawn(e, xf: float) -> void:
	var old = e.voice
	e.voice = null
	if old != null:
		_stop_voice(old, xf)
	_start_entry(e, xf)


func _release(e, fade: float) -> void:
	e.refs -= 1
	if e.refs > 0:
		return
	e.stopped = true
	_loops.erase(e)
	if e.voice != null:
		_stop_voice(e.voice, fade)


func _loop_set_position(e, p: Vector3) -> void:
	e.follow = false
	e.has_position = true
	e.position = p
	if e.voice != null and e.voice.is3d and not e.voice.head_locked:
		e.voice.pos = p
		e.voice.attach = null
		return
	e.positional = true
	_respawn(e, 0.12) # first position on a non-positional loop: respawn as positional


# ======================================================================================================== space
func _now() -> float:
	return Time.get_ticks_usec() * 0.000001


func _update_listener() -> void:
	var vp := get_viewport()
	var node: Node3D = vp.get_audio_listener_3d() if vp != null else null
	if node == null and vp != null:
		node = vp.get_camera_3d()
	if node == null and Game.camera != null and is_instance_valid(Game.camera) and Game.camera.is_inside_tree():
		node = Game.camera
	if node == null:
		_has_listener = false
		return
	var t := node.global_transform
	_lpos = t.origin
	_lfwd = -t.basis.z.normalized()
	_has_listener = true


func _head_pos() -> Vector3:
	return _lpos + _lfwd * 0.1


func _fix_pos(def, p: Vector3) -> Vector3:
	if def.ceil and p.y < float(R.ceilingY) + 0.05:
		p.y = float(R.ceilingY) + 0.45 # ceiling sounds live above the ceiling
	return p


func _zone_voice(v, init: bool) -> void:
	if v.is3d and not v.head_locked:
		v.zone = Acoustics.zone_of(v.pos)
		var oc := Acoustics.occlusion(v.zone, _lz, _door_t, v.pos, _lpos)
		v.occ_hz = oc.x
		v.occ_g = oc.y
	else:
		v.zone = _lz
		v.occ_hz = 20000.0
		v.occ_g = 1.0
	v.space = Acoustics.SPACE_OF_ZONE[v.zone]
	v.send = SEND_LEVEL * v.def.rv * Acoustics.SEND_OF_ZONE[v.zone]
	if init:
		v.occ_g_cur = v.occ_g
		v.send_cur = v.send


## Direct-sound bus of a voice: its category (or opts.bus). The reverb send goes to <Category>_Room / _Dark (v.space:
## zone of the source, or of the listener for 2D / head-locked sounds).
func _route(v) -> StringName:
	if v.bus_override != &"":
		return v.bus_override
	return Buses.leaf(v.cat, -1)


func _update_zones() -> void:
	var prev := _lz
	_lz = Z_CLOSET if _hidden else Acoustics.zone_of(_lpos)
	var changed := prev != _lz
	for v in _voices:
		if v.dead:
			continue
		if (v.is3d and not v.head_locked) or changed:
			_zone_voice(v, false)
			if v.twin != null:
				var tb := Buses.leaf(v.cat, v.space)
				if tb != v.twin_bus:
					v.twin_bus = tb
					v.twin.bus = tb


## Upstairs door openness 0..1 (continuous while it swings, from the Handle's node rotation).
func _door_openness() -> float:
	var w = Game.world
	if w == null or not is_instance_valid(w):
		return 0.0
	var hs = w.get("handles")
	if typeof(hs) != TYPE_DICTIONARY:
		return 0.0
	var h = hs.get("door.upstairs")
	if h == null or (h is Object and not is_instance_valid(h)):
		return 0.0
	var open: bool = h.get("is_open") == true
	if h.get("animating") == true:
		var node = h.get("node")
		var xc = h.get("closed_xform")
		var xo = h.get("open_xform")
		if node is Node3D and is_instance_valid(node) and xc is Transform3D and xo is Transform3D:
			var qc: Quaternion = xc.basis.get_rotation_quaternion()
			var full := qc.angle_to(xo.basis.get_rotation_quaternion())
			if full > 0.01:
				return clampf(qc.angle_to(node.transform.basis.get_rotation_quaternion()) / full, 0.0, 1.0)
	return 1.0 if open else 0.0


func _entity_feet():
	var e = Game.entity
	if e == null or not is_instance_valid(e):
		return null
	if e.has_method("get_feet_position"):
		return e.get_feet_position()
	var b = e.get("body")
	if b is Node3D and is_instance_valid(b) and b.is_inside_tree():
		return b.global_position
	if e is Node3D and e.is_inside_tree():
		return e.global_position
	return null


func _entity_head():
	var e = Game.entity
	if e != null and is_instance_valid(e) and e.has_method("get_head_position"):
		return e.get_head_position()
	var f = _entity_feet()
	return null if f == null else f + Vector3(0.0, 1.7, 0.0)


func _player_on_stairs() -> bool:
	var pl = Game.player
	if pl != null and is_instance_valid(pl):
		var s = pl.get("on_stairs")
		if typeof(s) == TYPE_BOOL:
			return s
	if _lpos.x < float(ST.minX) or _lpos.x > float(ST.maxX):
		return false
	if _lpos.z > float(ST.bottomZ) or _lpos.z < float(ST.topZ):
		return false
	return _lpos.y > 1.75 # eyes above standing height on the basement floor -> feet on a tread


func _tv_screen():
	var w = Game.world
	if w == null or not is_instance_valid(w):
		return null
	var tv = w.get("tv")
	if tv == null or not is_instance_valid(tv):
		return null
	var sp = tv.get("screen_position")
	return sp if sp is Vector3 else null


func _world_power() -> bool:
	var w = Game.world
	if w == null or not is_instance_valid(w):
		return true
	var p = w.get("power")
	return p != false


func _prop_pos(id: String) -> Vector3:
	var p: Array = Layout.PROPS[id].pos
	return Vector3(p[0], p[1], p[2])


func _default_pos(key: String) -> Vector3:
	match key:
		"fan":
			return Vector3(Layout.FAN.x, float(R.ceilingY) - 0.18, Layout.FAN.z)
		"light":
			return Vector3(Layout.FAN.x, float(R.ceilingY) - 0.48, Layout.FAN.z)
		"alarmClock":
			return _prop_pos("alarmClock") + Vector3(0.0, 0.08, 0.0)
		"grandfather":
			var p := _prop_pos("grandfather")
			return Vector3(p.x, 1.75, p.z + 0.1)
		"window":
			var w := Layout.WINDOW
			return Vector3((float(w.minX) + float(w.maxX)) * 0.5, (float(w.minY) + float(w.maxY)) * 0.5, float(w.z) + 0.3)
		"tv":
			var sp = _tv_screen()
			if sp != null:
				return sp
			return _prop_pos("tv") + Vector3(0.0, 0.2, 0.12)
		"powerBox":
			return _prop_pos("powerBox") + Vector3(0.0, 0.0, 0.15)
		"rocking":
			var p := _prop_pos("rockingChair")
			return Vector3(p.x, 0.45, p.z)
		"furnace":
			return Vector3(2.3, 0.9, float(AL.minZ) - 0.35) # furnace room behind the laundry-nook wall
		"ceiling":
			return Vector3(-2.2 + randf() * 5.4, float(R.ceilingY) + 0.45, -2.4 + randf() * 4.8)
		"stairs":
			var z := float(ST.topZ) + 0.15 + randf() * (float(ST.bottomZ) - float(ST.topZ) - 0.3)
			var h := Layout.stair_height_at(-3.0, z)
			return Vector3(-3.0, (1.0 if is_nan(h) else h) + 0.05, z)
		"house":
			if randf() < 0.55:
				return Vector3(-2.2 + randf() * 5.5, float(R.ceilingY) - 0.08, -2.5 + randf() * 5.0) # joists
			match randi() % 3:
				0:
					return Vector3(float(R.maxX) - 0.05, 0.6 + randf() * 1.6, -2.4 + randf() * 4.8)
				1:
					return Vector3(-2.2 + randf() * 5.4, 0.6 + randf() * 1.6, float(R.maxZ) - 0.05)
				_:
					return Vector3(-2.5 + randf() * 2.6, 0.6 + randf() * 1.6, float(R.minZ) + 0.05)
		"wall":
			match randi() % 3:
				0:
					return Vector3(float(R.maxX) + 0.3, 1.0 + randf() * 0.8, -2.0 + randf() * 4.0)
				1:
					return Vector3(-2.3 + randf() * 2.3, 1.0 + randf() * 0.8, float(R.minZ) - 0.3)
				_:
					return Vector3(float(R.minX) - 0.3, 1.0 + randf() * 0.8, 1.7 + randf() * 0.8)
		"entityFeet", "entityHead":
			var f = _entity_feet()
			if f != null:
				return f + Vector3(0.0, 1.7 if key == "entityHead" else 0.05, 0.0)
			return Vector3(float(UH.minX) + 0.5, float(Layout.UPPER.floorY) + 1.0, (float(UH.minZ) + float(UH.maxZ)) * 0.5)
		"behind":
			if not _has_listener:
				return Vector3(0.0, 1.6, 0.0)
			var f := Vector3(_lfwd.x, 0.0, _lfwd.z)
			f = f.normalized() if f.length_squared() > 1e-6 else Vector3(0.0, 0.0, -1.0)
			var side := -1.0 if randf() < 0.5 else 1.0
			return Vector3(_lpos.x - f.x * 0.5 - f.z * side * 0.32, _lpos.y + 0.04, _lpos.z - f.z * 0.5 + f.x * side * 0.32)
		"far":
			var c: Array = [[-2.3, 1.0, 2.4], [3.2, 1.0, 2.4], [3.2, 1.0, -2.4], [1.35, 1.0, -3.8], [-2.4, 0.6, -1.6]][randi() % 5]
			return Vector3(c[0], c[1], c[2])
	return Vector3(0.0, 1.2, 0.0)


# ======================================================================================================== mix
func _duck(amb: float, sfx: float, foley: float, music: float, hold: float, rel: float) -> void:
	_dk[0] = minf(_dk[0], amb)
	_dk[1] = minf(_dk[1], sfx)
	_dk[2] = minf(_dk[2], foley)
	_dk[3] = minf(_dk[3], music)
	_dk_hold = maxf(_dk_hold, hold)
	_dk_rel = rel


func _update_buses(dt: float) -> void:
	if _dk_hold > 0.0:
		_dk_hold -= dt
	else:
		var k := minf(1.0, dt / maxf(0.05, _dk_rel))
		for i in 4:
			_dk[i] += (1.0 - _dk[i]) * k
	_chase_duck += ((0.45 if _chase else 1.0) - _chase_duck) * minf(1.0, dt * (2.0 if _chase else 0.5))
	var hid := 0.85 if _hidden else 1.0
	var kc := 1.0 - exp(-dt / 0.04)
	_set_cat("sfx", Defs.CAT_LEVEL.sfx * _dk[1], kc)
	_set_cat("foley", Defs.CAT_LEVEL.foley * _dk[2], kc)
	_set_cat("ambience", Defs.CAT_LEVEL.ambience * _dk[0] * _chase_duck * hid, kc)
	_set_cat("music", Defs.CAT_LEVEL.music * _dk[3], kc)
	_set_cat("voice", Defs.CAT_LEVEL.voice, kc)
	# master: user volume (perceptual curve) x pause duck x mix level, after the glue compressor + limiter
	var mt := pow(_user_vol, 1.5) * (0.28 if _paused else 1.0) * 0.95
	if _master_g < 0.0:
		_master_g = mt
	else:
		_master_g += (mt - _master_g) * (1.0 - exp(-dt / 0.08))
	if _master_amp != null:
		var mdb := linear_to_db(maxf(_master_g, 1e-5))
		if absf(_master_amp.volume_db - mdb) > 0.01:
			_master_amp.volume_db = mdb
	# pause muffle + hidden (closet) ambience muffle
	_pause_hz = _glide_hz(_pause_hz, 850.0 if _paused else 20500.0, dt, 0.12)
	if _pause_lpf != null:
		_pause_lpf.cutoff_hz = _pause_hz
		_set_filter_enabled(_pause_lpf_loc, _pause_hz < 19900.0)
	_amb_hz = _glide_hz(_amb_hz, 2200.0 if _hidden else 20500.0, dt, 0.2)
	for i in _amb_lpfs.size():
		_amb_lpfs[i].cutoff_hz = _amb_hz
		_set_filter_enabled(_amb_lpf_locs[i], _amb_hz < 19900.0)


func _glide_hz(cur: float, target: float, dt: float, tau: float) -> float:
	if absf(cur - target) < 1.0:
		return target
	return exp(lerpf(log(cur), log(target), 1.0 - exp(-dt / tau)))


func _set_cat(cat: String, target: float, k: float) -> void:
	var cur: float = _cat_cur[cat]
	var g := target if cur < 0.0 else cur + (target - cur) * k
	if absf(g - cur) < 0.0005 and cur >= 0.0:
		return
	_cat_cur[cat] = g
	var db := linear_to_db(maxf(g, 1e-5))
	for a in _cat_amps.get(cat, []):
		a.volume_db = db


# ======================================================================================================== POV layers
func _live() -> bool:
	return _game_state == "playing" or _game_state == "caught" or _game_state == "paused"


func _update_layers(dt: float) -> void:
	var f := _fear
	var ex := 1.0 - _stamina
	var live := _live()
	var hid := _hidden
	# sprint exhaustion panting: follows exhaustion, slow release while recovering
	var run_t := smoothstep(0.3, 1.0, ex) * 0.8 * (0.25 if hid else 1.0) if live else 0.0
	_l_run.update(dt, run_t, 1.6, 0.32, 0.94 + 0.14 * _l_run.v)
	# heartbeat (fear, and a little from exertion); crossfade to the fast loop above ~0.6
	var hb := maxf(smoothstep(0.12, 0.7, f), smoothstep(0.55, 1.0, ex) * 0.32) if live and not heartbeat_external else 0.0
	var fast := smoothstep(0.55, 0.72, f)
	_l_hb.update(dt, hb * (1.0 - fast) * 0.9, 1.4, 0.45, 0.9 + 0.32 * f)
	_l_hbf.update(dt, hb * fast * 0.95, 1.4, 0.45, 0.95 + 0.22 * smoothstep(0.6, 1.0, f))
	# scared breathing (not while panting / hidden)
	var sc := smoothstep(0.35, 0.85, f) * 0.55 * (1.0 - clampf(_l_run.v * 1.4, 0.0, 1.0)) if live and not hid else 0.0
	_l_scared.update(dt, sc, 0.8, 0.4)
	# hidden: close, quiet, muffled breathing that holds now and then
	if hid:
		_hold_t -= dt
		if _hold_t <= 0.0:
			_holding = not _holding
			_hold_t = (1.6 + randf() * 1.6) if _holding else (4.0 + randf() * 5.0)
	var hb2 := ((0.05 if _holding else 0.24 + 0.24 * f) if hid and live else 0.0)
	_l_hide.update(dt, hb2, 1.0, 1.4, 0.86 + 0.12 * f)
	# sub drone: subtle bed, darker when the power is off, opens up with fear
	var dr := ((0.1 if _power else 0.2) + 0.6 * f + (0.15 if _chase else 0.0)) if _bed_on else 0.0
	_l_drone.update(dt, dr, 0.6, 0.25, NAN, 300.0 + 2600.0 * f)
	# chase music
	_l_chase.update(dt, 0.95 if _chase and live else 0.0, 3.0, 0.75)


# ======================================================================================================== events
func _on_power(on: bool) -> void:
	_set_power(on, false)


func _on_stamina(value: float, _exhausted: bool, _breath: float) -> void:
	if not is_nan(value):
		_stamina = clampf(value, 0.0, 1.0)


func _on_hide(h: bool, _spot_id: String) -> void:
	if h == _hidden:
		return
	_hidden = h
	_zone_t = 0.0
	_hold_t = 2.0 + randf() * 2.0
	_holding = false
	play("cloth_move", {"volume": 0.5})


func _on_bump(_tag: String) -> void:
	play("bump", {"volume": 0.85})


func _on_flashlight(_has: bool, on: bool, _battery: float) -> void:
	if on != _fl_on:
		_fl_on = on
		play("flashlight_click", {"volume": 0.9})


func _on_spotted() -> void:
	play("stinger", {"volume": 0.95})
	play("heartbeat_single", {"delay": 0.04, "volume": 0.75})
	play("player_gasp", {"delay": 0.16, "volume": 0.85})


func _on_entity_state(s: String, _prev: String) -> void:
	_entity_state = s if s != "" else "dormant"
	_chase = s == "chasing"
	if s == "jumpscare":
		_l_chase.kill(0.04)
		_duck(0.1, 0.3, 0.25, 0.0, 1.8, 1.5)


func _on_game_state(s: String, _prev: String) -> void:
	var prev := _game_state
	_game_state = s
	if s == "loading" and prev != "loading":
		_reset_session() # the scene is being reloaded (game over / win): start from silence
	if (s == "menu" or s == "playing") and not _bed_on:
		_start_bed()
	if s == "caught" or s == "gameover":
		_chase = false
		_l_chase.kill(1.2)
	if s == "won":
		_chase = false
		_l_chase.kill(1.5)
		_duck(0.35, 1.0, 1.0, 1.0, 8.0, 4.0)
	if s == "playing" and _args.has("audio-test") and not _selftest_started:
		_selftest_started = true
		_run_selftest.call_deferred()


func _on_setting(key: String, value: Variant) -> void:
	if key == "volume":
		set_master_volume(float(value))
	elif key == "quality":
		_set_quality(String(value))


func _set_quality(q: String) -> void:
	_low_cpu = q == "low"
	_max_voices = 30 if _low_cpu else 48


func _reset_session() -> void:
	stop_all(0.25)
	_fear = 0.0
	_stamina = 1.0
	_hidden = false
	_chase = false
	_entity_state = "dormant"
	_power = true
	_fl_on = false
	_paused = false
	for i in 4:
		_dk[i] = 1.0
	_dk_hold = 0.0


func _run_selftest() -> void:
	if not ResourceLoader.exists(SELFTEST_PATH):
		push_warning("[audio] self-test introuvable")
		return
	var t = load(SELFTEST_PATH).new()
	await t.run(self, get_tree(), true)


# ======================================================================================================== beds & life
func _start_bed() -> void:
	if _bed_on:
		return
	_bed_on = true
	_room = loop("room_tone", {"volume": 0.8, "fade_in": 3.0})
	_clock = loop("clock_tick", {"volume": 0.85, "fade_in": 1.5})
	_wind = loop("wind_outside", {"volume": 0.6, "fade_in": 4.0})
	_furn_on = randf() < 0.6
	_furn_t = (40.0 + randf() * 60.0) if _furn_on else (15.0 + randf() * 30.0)
	if _furn_on:
		_furn = loop("furnace", {"volume": 0.9, "fade_in": 4.0})
	_life_t = 22.0 + randf() * 20.0
	_set_power(_world_power(), true)


func _set_power(on: bool, force: bool) -> void:
	if not force and on == _power:
		return
	_power = on
	if not _bed_on:
		return
	if on:
		if _buzz == null:
			_buzz = loop("light_buzz", {"volume": 0.5, "fade_in": 1.5 if force else 0.3})
		if _fan == null:
			_fan = loop("fan_hum", {"volume": 0.6, "fade_in": 2.0 if force else 3.5, "rate": 1.0 if force else 0.5})
			if not force:
				_fan.set_rate(1.0, 6.0) # the fan spins up
		if not force:
			play("power_up", {"volume": 0.85})
	else:
		if _buzz != null:
			_buzz.stop(0.05)
			_buzz = null
		if _fan != null:
			_fan.set_rate(0.3, 5.0) # the fan spins down
			_fan.stop(5.0)
			_fan = null


func _update_bed(dt: float) -> void:
	if not _bed_on:
		return
	# the furnace cycles on/off like a real one
	_furn_t -= dt
	if _furn_t <= 0.0:
		_furn_on = not _furn_on
		if _furn_on:
			_furn = loop("furnace", {"volume": 0.9, "fade_in": 5.0})
			_furn_t = 60.0 + randf() * 80.0
		else:
			if _furn != null:
				_furn.stop(6.0)
			_furn = null
			_furn_t = 35.0 + randf() * 60.0
	# wind gusts
	_wind_t -= dt
	if _wind_t <= 0.0:
		_wind_t = 3.0 + randf() * 6.0
		_wind_target = 0.3 + randf() * 0.55
	_wind_v += (_wind_target - _wind_v) * minf(1.0, dt * 0.35)
	if _wind != null and absf(_wind_v - _wind_sent) > 0.01:
		_wind.set_volume(_wind_v)
		_wind_sent = _wind_v


func _update_life(dt: float) -> void:
	if _game_state != "playing":
		return
	if _entity_state != "dormant" and _entity_state != "disabled" and _entity_state != "":
		return # never confuse real gameplay cues
	if _fear > 0.3:
		return
	_life_t -= dt
	if _life_t > 0.0:
		return
	_life_t = 40.0 + randf() * 55.0
	# gameplay runs its own scripted scares with the same sounds: stay quiet if one happened recently
	var now := _now()
	for n in Defs.LIFE_NAMES:
		var t = _last.get(n)
		if t != null and now - float(t) < 25.0:
			_life_t = 20.0 + randf() * 20.0
			return
	var x := randf()
	if x < 0.42:
		play("house_creak", {"volume": 0.55 + randf() * 0.4})
	elif x < 0.57:
		play("stair_creak", {"volume": 0.4 + randf() * 0.3})
	elif x < 0.73:
		play("ceiling_walk", {"volume": 0.65 + randf() * 0.3})
	elif x < 0.85:
		play("ceiling_steps", {"volume": 0.7})
	elif x < 0.94:
		play("knock_wall", {"volume": 0.45 + randf() * 0.25})
	else:
		play("window_tap", {"volume": 0.5})


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)
