## Fear module — what the body feels: beat-synced heartbeat, sub rumble, dissonant drone, muffled hearing + tinnitus after
## the loudest scares, sudden silences before big moments, and the pulse sent to the look module / player.
##   * heartbeat: one "fear_heartbeat" (lub-dub) per simulated beat, so the rate IS the BPM; pitch rises a little with the
##     rate (shorter systole), volume follows stress (inaudible at rest, inside your head from ~110 BPM). Falls back to the
##     recorded "heartbeat_single" when the fear library is missing. Routed to Master (never muffled / silenced).
##   * rumble (felt more than heard) and drone (minor seconds, tritone) loops swell with stress and with swell() bursts.
##   * hearing: named effects added at runtime to the audio module's buses (the bus graph and its validity check are
##     untouched): "fear_lowpass" on SFX / Foley / Ambience / Voice / Music / ReverbRoom / ReverbDark (muffle) and
##     "fear_gain" on SFX(+_Room/_Dark) / Ambience(+_Room/_Dark) / Music (silence). Both stay disabled at rest.
##   * look: Quality.set_fear(stress + pulse), lighting.set_stress (only while La Gardienne is dormant: hers otherwise),
##     player.stress_bias (camera tremor / breathing), Audio.set_fear (scared breathing + the audio module's sub drone).
extends RefCounted

const MASTER_COMP_DB := 12.0     # = Buses.HEADROOM_DB: voices routed straight to Master skip the category bus gain
const MUFFLE_BUSES := ["SFX", "Foley", "Ambience", "Voice", "Music", "ReverbRoom", "ReverbDark"]
const SILENCE_BUSES := ["SFX", "SFX_Room", "SFX_Dark", "Ambience", "Ambience_Room", "Ambience_Dark", "Music"]
const LP_NAME := "fear_lowpass"
const GAIN_NAME := "fear_gain"

var d = null                      # the director (untyped: calls its helpers)
var hb_vol := 0.0                 # last heartbeat volume (tests)
var swell := 0.0                  # 0..1 extra rumble / drone (rumble_swell, glimpses)
var muffle := 0.0                 # 0..1 current hearing loss
var silence := 0.0                # 0..1 current silence depth
var beats_played := 0
var pulse_sent := -1.0

var _swell_t := 0.0
var _muf := {"level": 0.0, "target": 0.0, "hold": 0.0, "attack": 0.05, "release": 3.0}
var _sil := {"level": 0.0, "target": 0.0, "hold": 0.0, "attack": 0.5, "release": 2.0}
var _rumble = null
var _drone = null
var _rumble_v := 0.0
var _drone_v := 0.0
var _idle_rumble := 0.0
var _idle_drone := 0.0
var _lp: Array = []               # [{bus, fx}]
var _gain: Array = []             # [{bus, fx}]
var _lp_on := false
var _gain_on := false
var _cut_sent := -1.0
var _gain_sent := -1.0
var _lstress_sent := -1.0
var _bias_sent := -1.0


func _init(director) -> void:
	d = director


func setup() -> void:
	if d.sim:
		return
	_install_effects()


func teardown() -> void:
	_stop_loop("_rumble", 0.5)
	_stop_loop("_drone", 0.5)
	if not d.sim:
		_set_lp(20500.0, false)
		_set_gain(1.0, false)


# ------------------------------------------------------------------------------------------------ heartbeat
func beat(bpm: float, stress: float) -> void:
	var v := smoothstep(0.1, 0.85, stress) * 0.6
	v *= 1.0 + 0.5 * silence                  # in a silence the heart fills the head
	v = minf(v, 0.9)
	hb_vol = v
	if v < 0.02:
		return
	beats_played += 1
	var rate := clampf(0.94 + (bpm - 72.0) / 300.0, 0.94, 1.3)
	if d.sim:
		d.log_sound("fear_heartbeat", null, v)
		return
	var nm := "fear_heartbeat" if Audio.has_sound("fear_heartbeat") else "heartbeat_single"
	Audio.play(nm, {"bus": "Master", "volume": v, "volume_db": MASTER_COMP_DB if nm == "fear_heartbeat" else MASTER_COMP_DB - 4.0,
		"pitch": rate, "no_jitter": true, "positional": false})


# ------------------------------------------------------------------------------------------------ bursts
## Hearing loss after a very loud event: amount 0..1 (cutoff down to ~450 Hz), hold then release (s).
func muffle_hit(amount: float, hold := 0.6, release := 3.5) -> void:
	_muf.target = maxf(float(_muf.target), clampf(amount, 0.0, 1.0))
	_muf.level = maxf(float(_muf.level), float(_muf.target) * 0.85)   # instant: the ear shuts at the bang
	_muf.hold = maxf(float(_muf.hold), hold)
	_muf.release = release


## Sudden silence: depth 0..1 of everything but the heart / breath / creature, over attack s, held, then released.
func silence_for(depth: float, attack := 0.35, hold := 2.0, release := 2.5) -> void:
	_sil.target = maxf(float(_sil.target), clampf(depth, 0.0, 1.0))
	_sil.attack = maxf(0.05, attack)
	_sil.hold = maxf(float(_sil.hold), hold)
	_sil.release = release


func release_silence(release := 2.5) -> void:
	_sil.hold = 0.0
	_sil.target = 0.0
	_sil.release = release


func tinnitus(volume := 0.6) -> void:
	if d.sim:
		d.log_sound("fear_tinnitus", null, volume)
		return
	if Audio.has_sound("fear_tinnitus"):
		Audio.play("fear_tinnitus", {"bus": "Master", "volume": volume, "volume_db": MASTER_COMP_DB, "positional": false})


func sub_hit(volume := 0.8) -> void:
	_head_sound("fear_sub_hit", volume)


func stinger(sound: String, volume := 0.8) -> void:
	_head_sound(sound, volume)


func swell_for(amount: float, seconds: float) -> void:
	swell = maxf(swell, clampf(amount, 0.0, 1.0))
	_swell_t = maxf(_swell_t, seconds)


func _head_sound(sound: String, volume: float) -> void:
	if d.sim:
		d.log_sound(sound, null, volume)
		return
	if Audio.has_sound(sound):
		Audio.play(sound, {"bus": "Master", "volume": volume, "volume_db": MASTER_COMP_DB, "positional": false})


# ------------------------------------------------------------------------------------------------ per frame
func update(dt: float, stress: float, pulse: float, c: Dictionary) -> void:
	_env(_muf, dt)
	_env(_sil, dt)
	muffle = float(_muf.level)
	silence = float(_sil.level)
	if _swell_t > 0.0:
		_swell_t -= dt
	else:
		swell = maxf(0.0, swell - dt * 0.12)
	var live: bool = c.get("live", true)
	# beds: rumble (felt) and dissonant drone (heard) — both swell with stress and bursts, dip in a silence
	var rv := (smoothstep(0.25, 1.0, stress) * 0.85 + swell * 0.7) if live else 0.0
	var dv := (smoothstep(0.2, 0.95, stress) * 0.6 + swell * 0.55) * (1.0 - 0.75 * silence) if live else 0.0
	_rumble_v += (rv - _rumble_v) * minf(1.0, dt * (1.2 if rv > _rumble_v else 0.35))
	_drone_v += (dv - _drone_v) * minf(1.0, dt * (0.8 if dv > _drone_v else 0.3))
	if not d.sim:
		_layer("_rumble", "fear_rumble", _rumble_v, dt, -1.0)
		_layer("_drone", "fear_drone", _drone_v, dt, 900.0 + 5200.0 * smoothstep(0.2, 1.0, stress + swell * 0.5))
		_apply_buses()
		_feed_others(stress, pulse, c)


func _env(e: Dictionary, dt: float) -> void:
	if float(e.hold) > 0.0:
		e.hold = float(e.hold) - dt
		var a := 1.0 - exp(-dt / maxf(0.02, float(e.attack)))
		e.level = float(e.level) + (float(e.target) - float(e.level)) * a
	else:
		e.target = 0.0
		var r := 1.0 - exp(-dt / maxf(0.05, float(e.release) / 3.0))
		e.level = float(e.level) + (0.0 - float(e.level)) * r
		if float(e.level) < 0.002:
			e.level = 0.0


func _layer(field: String, sound: String, v: float, dt: float, filter_hz: float) -> void:
	var h = get(field)
	if h != null and not h.is_playing():
		h = null
		set(field, null)
	var idle_field := "_idle" + field
	if v > 0.01:
		set(idle_field, 0.0)
		if h == null:
			if not Audio.has_sound(sound):
				return
			var o := {"bus": "Master", "volume": maxf(v, 0.001), "volume_db": MASTER_COMP_DB, "unique": true, "fade_in": 1.5,
				"positional": false}
			if filter_hz > 0.0:
				o["filter_hz"] = filter_hz
			h = Audio.loop(sound, o)
			set(field, h)
		else:
			h.set_volume(v)
			if filter_hz > 0.0:
				h.set_filter(filter_hz)
	elif h != null:
		var idle: float = float(get(idle_field)) + dt
		set(idle_field, idle)
		h.set_volume(maxf(v, 0.0))
		if idle > 2.0:
			_stop_loop(field, 0.4)


func _stop_loop(field: String, fade: float) -> void:
	var h = get(field)
	if h != null:
		h.stop(fade)
	set(field, null)


func _feed_others(stress: float, pulse: float, c: Dictionary) -> void:
	# look: fear vignette / CA pulsing with the heart (only above a calm baseline)
	var gf := float(Game.fear)
	var v := clampf(maxf(gf, stress * 0.9) + pulse * 0.12 * stress, 0.0, 1.0)
	if not c.get("live", true):
		v = 0.0
	if absf(v - pulse_sent) > 0.004:
		pulse_sent = v
		d.look_call("set_fear", [v])
	# lighting stress: hers while she is about, ours (subtle) while she sleeps
	if not c.get("ent_active", false):
		var ls := 0.35 * stress if c.get("live", true) else 0.0
		if absf(ls - _lstress_sent) > 0.01:
			_lstress_sent = ls
			d.light_call("set_stress", [ls])
	else:
		_lstress_sent = -1.0
	# player tremor / breathing
	var pl = c.get("player_node")
	if pl != null and is_instance_valid(pl) and "stress_bias" in pl:
		var b := stress * 0.85 if c.get("live", true) else 0.0
		if absf(b - _bias_sent) > 0.005:
			_bias_sent = b
			pl.set("stress_bias", b)
	# the audio module's own layers (scared breathing, sub drone) follow the max of her fear and ours
	Audio.set_fear(maxf(gf, stress * 0.8) if c.get("live", true) else gf)


# ------------------------------------------------------------------------------------------------ buses
func _install_effects() -> void:
	_lp.clear()
	_gain.clear()
	for b in MUFFLE_BUSES:
		var fx := _ensure_effect(b, LP_NAME)
		if fx != null:
			_lp.append({"bus": b, "fx": fx})
	for b in SILENCE_BUSES:
		var fx := _ensure_effect(b, GAIN_NAME)
		if fx != null:
			_gain.append({"bus": b, "fx": fx})
	_lp_on = true
	_gain_on = true
	_set_lp(20500.0, false)
	_set_gain(1.0, false)


func _ensure_effect(bus: String, fx_name: String) -> AudioEffect:
	var bi := AudioServer.get_bus_index(bus)
	if bi < 0:
		return null
	for j in AudioServer.get_bus_effect_count(bi):
		var e := AudioServer.get_bus_effect(bi, j)
		if e != null and e.resource_name == fx_name:
			return e
	var fx: AudioEffect
	if fx_name == LP_NAME:
		var f := AudioEffectLowPassFilter.new()
		f.cutoff_hz = 20500.0
		f.resonance = 0.7
		f.db = AudioEffectFilter.FILTER_24DB
		fx = f
	else:
		var a := AudioEffectAmplify.new()
		a.volume_db = 0.0
		fx = a
	fx.resource_name = fx_name
	AudioServer.add_bus_effect(bi, fx)
	AudioServer.set_bus_effect_enabled(bi, AudioServer.get_bus_effect_count(bi) - 1, false)
	return fx


func _fx_index(bus: String, fx: AudioEffect) -> Vector2i:
	var bi := AudioServer.get_bus_index(bus)
	if bi < 0:
		return Vector2i(-1, -1)
	for j in AudioServer.get_bus_effect_count(bi):
		if AudioServer.get_bus_effect(bi, j) == fx:
			return Vector2i(bi, j)
	return Vector2i(-1, -1)


func _apply_buses() -> void:
	var cut := 20500.0
	if muffle > 0.001:
		cut = exp(lerpf(log(20500.0), log(420.0), sqrt(clampf(muffle, 0.0, 1.0))))
	_set_lp(cut, muffle > 0.001)
	_set_gain(maxf(0.0005, 1.0 - silence), silence > 0.001)


func _set_lp(cut: float, on: bool) -> void:
	if on == _lp_on and absf(cut - _cut_sent) < maxf(1.0, _cut_sent * 0.01):
		return
	_cut_sent = cut
	for e in _lp:
		(e.fx as AudioEffectLowPassFilter).cutoff_hz = cut
		if on != _lp_on:
			var ix := _fx_index(e.bus, e.fx)
			if ix.x >= 0:
				AudioServer.set_bus_effect_enabled(ix.x, ix.y, on)
	_lp_on = on


func _set_gain(g: float, on: bool) -> void:
	var db := linear_to_db(maxf(g, 1e-5))
	if on == _gain_on and absf(db - _gain_sent) < 0.05:
		return
	_gain_sent = db
	for e in _gain:
		(e.fx as AudioEffectAmplify).volume_db = db
		if on != _gain_on:
			var ix := _fx_index(e.bus, e.fx)
			if ix.x >= 0:
				AudioServer.set_bus_effect_enabled(ix.x, ix.y, on)
	_gain_on = on
