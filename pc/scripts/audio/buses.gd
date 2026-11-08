## Audio module — the bus graph (single source of truth). res://default_bus_layout.tres is generated from build() by
## `godot --headless --path pc -s res://scripts/audio/tools/make_bus_layout.gd`; Godot loads that file at startup
## (project setting audio/buses/default_bus_layout keeps its default value). At runtime ensure() rebuilds the graph in
## code if the file is missing or does not match, so the game never runs without its mix.
##
##   Master  [pause_lowpass, glue (compressor), limiter (hard limiter -1 dBFS), user_volume (amplify)]
##   ├─ ReverbRoom  [room_reverb: small carpeted basement, wet only]   <- SFX_Room, Foley_Room, Ambience_Room, Voice_Room
##   ├─ ReverbDark  [dark_reverb: laundry-nook concrete / stairwell / upstairs hall, longer + darker, wet only] <- *_Dark
##   └─ SFX, Foley, Ambience, Music, Voice  (the direct sound of every voice)
## Web topology: every voice plays its direct sound (distance, panning, occlusion) on its category bus; a reverberant
## voice also plays a synced "send" copy (no distance attenuation = uniform reverberant field, so far sources sound
## wetter) on <Category>_Room / _Dark, which feed the wet-only reverbs. The reverbs' `wet` calibrates Godot's reverb
## gain against the web's normalized impulse responses (tail energy of a tick matched at 1.5 m and in the nook).
## Every category bus carries [duck (amplify)] (ambience: [hidden_lowpass, duck]) and +HEADROOM_DB of gain: voices run
## HEADROOM_DB lower so Godot's per-voice high-shelf (AudioStreamPlayer3D attenuation filter, used for occlusion) stays
## fully controllable (see audio_manager._apply). A bus only sends to a bus with a lower index.
extends RefCounted

const HEADROOM_DB := 12.0
const LAYOUT_PATH := "res://default_bus_layout.tres"

const CAT_BUS := {"sfx": "SFX", "foley": "Foley", "ambience": "Ambience", "music": "Music", "voice": "Voice"}
const SPACE_SUFFIX := ["_Room", "_Dark"]
const REVERB_BUS := ["ReverbRoom", "ReverbDark"]
## Reverb return levels, calibrated in scripts/audio/tests/audio_test.gd against the web version's reverb: Godot's
## reverb has ~+8 dB of energy gain (8 combs x 0.6) where the web's Web-Audio-normalised impulse responses have about
## -18 dB (room) / -15 dB (long), so with the web's send levels the returns sit ~25 dB lower.
const ROOM_WET := 0.066
const DARK_WET := 0.15


## [name, send, volume_db] in bus order.
static func spec() -> Array:
	var out := [["Master", "", 0.0], ["ReverbRoom", "Master", 0.0], ["ReverbDark", "Master", 0.0]]
	for c in ["SFX", "Foley", "Ambience", "Music", "Voice"]:
		out.append([c, "Master", HEADROOM_DB])
	for s in 2:
		for c in ["SFX", "Foley", "Ambience", "Voice"]:
			out.append([c + SPACE_SUFFIX[s], REVERB_BUS[s], HEADROOM_DB])
	return out


## Bus of a category: space -1 = dry, 0 = room reverb, 1 = dark reverb (music is always dry).
static func leaf(cat: String, space: int) -> StringName:
	var base: String = CAT_BUS.get(cat, "SFX")
	if space < 0 or cat == "music":
		return StringName(base)
	return StringName(base + SPACE_SUFFIX[space])


## Every bus of a category (dry + reverb leaves).
static func leaves_of(cat: String) -> Array:
	var base: String = CAT_BUS.get(cat, "SFX")
	if cat == "music":
		return [base]
	return [base, base + SPACE_SUFFIX[0], base + SPACE_SUFFIX[1]]


static func _named(e: AudioEffect, n: String) -> AudioEffect:
	e.resource_name = n
	return e


static func make_room_reverb() -> AudioEffectReverb:
	# ~7 x 5.5 x 2.5 m basement, carpet + sofa + curtains: short (RT60 ~0.55 s), damped highs, no slap.
	# Godot's reverb: comb feedback = 0.7 + 0.28 * room_size; in-loop low-pass corner = (damping/2 + 0.5)^2 * 10 kHz.
	var r := AudioEffectReverb.new()
	r.room_size = 0.0
	r.damping = 0.12
	r.spread = 0.85
	r.hipass = 0.025
	r.predelay_msec = 5.0
	r.predelay_feedback = 0.0
	r.dry = 0.0
	r.wet = ROOM_WET
	return _named(r, "room_reverb") as AudioEffectReverb


static func make_dark_reverb() -> AudioEffectReverb:
	# Painted-concrete laundry nook + narrow wooden stairwell: longer (RT60 ~1 s at 1 kHz), darker tail, faint slap.
	var r := AudioEffectReverb.new()
	r.room_size = 0.5
	r.damping = 0.15
	r.spread = 1.0
	r.hipass = 0.03
	r.predelay_msec = 11.0
	r.predelay_feedback = 0.08
	r.dry = 0.0
	r.wet = DARK_WET
	return _named(r, "dark_reverb") as AudioEffectReverb


static func make_lowpass(n: String) -> AudioEffectLowPassFilter:
	var f := AudioEffectLowPassFilter.new()
	f.cutoff_hz = 20500.0
	f.resonance = 0.6
	f.db = AudioEffectFilter.FILTER_12DB
	return _named(f, n) as AudioEffectLowPassFilter


static func make_amplify(n: String) -> AudioEffectAmplify:
	var a := AudioEffectAmplify.new()
	a.volume_db = 0.0
	return _named(a, n) as AudioEffectAmplify


static func make_glue() -> AudioEffectCompressor:
	# Gentle glue on the whole mix. Godot's compressor applies 2.08 x the nominal gain reduction (its "overdb" is scaled
	# by 1/ln(2)^2): ratio 1.4 behaves like ~2.5:1 (slope 1 - 2.081 * (1 - 1/ratio) = 0.41).
	var c := AudioEffectCompressor.new()
	c.threshold = -18.0
	c.ratio = 1.4
	c.attack_us = 2000.0
	c.release_ms = 280.0
	c.gain = 0.0
	c.mix = 1.0
	return _named(c, "glue") as AudioEffectCompressor


static func make_limiter() -> AudioEffectHardLimiter:
	var l := AudioEffectHardLimiter.new()
	l.ceiling_db = -1.0
	l.pre_gain_db = 0.0
	l.release = 0.12
	return _named(l, "limiter") as AudioEffectHardLimiter


static func effects_for(bus: String) -> Array:
	match bus:
		"Master":
			return [make_lowpass("pause_lowpass"), make_glue(), make_limiter(), make_amplify("user_volume")]
		"ReverbRoom":
			return [make_room_reverb()]
		"ReverbDark":
			return [make_dark_reverb()]
	if bus.begins_with("Ambience"):
		return [make_lowpass("hidden_lowpass"), make_amplify("duck")]
	return [make_amplify("duck")]


## (Re)creates every bus and effect.
static func build() -> void:
	var sp := spec()
	AudioServer.bus_count = sp.size()
	# set_bus_name() de-duplicates ("SFX 2") when the name exists on another bus: go through unique temporary names.
	for i in range(1, sp.size()):
		AudioServer.set_bus_name(i, "__audio_tmp_%d" % i)
	for i in sp.size():
		var b: Array = sp[i]
		AudioServer.set_bus_name(i, b[0])
	for i in sp.size():
		var b: Array = sp[i]
		if i > 0:
			AudioServer.set_bus_send(i, StringName(b[1]))
		AudioServer.set_bus_volume_db(i, b[2])
		AudioServer.set_bus_mute(i, false)
		AudioServer.set_bus_solo(i, false)
		AudioServer.set_bus_bypass_effects(i, false)
		while AudioServer.get_bus_effect_count(i) > 0:
			AudioServer.remove_bus_effect(i, 0)
		for e in effects_for(b[0]):
			AudioServer.add_bus_effect(i, e)


## True when the live bus graph has every bus (names, order, sends) and named effect build() creates.
static func is_valid() -> bool:
	var sp := spec()
	if AudioServer.bus_count != sp.size():
		return false
	for i in sp.size():
		var b: Array = sp[i]
		if AudioServer.get_bus_name(i) != b[0]:
			return false
		if i > 0 and String(AudioServer.get_bus_send(i)) != b[1]:
			return false
		for e in effects_for(b[0]):
			if find_effect_index(b[0], e.resource_name) < 0:
				return false
	# the send topology needs wet-only reverbs (a dry path there would double the direct sound)
	for n in REVERB_BUS:
		var r := find_effect(n, "room_reverb" if n == "ReverbRoom" else "dark_reverb") as AudioEffectReverb
		if r == null or r.dry > 0.001:
			return false
	return true


## Validates the graph and rebuilds it when needed. Returns true when it had to rebuild.
static func ensure() -> bool:
	if is_valid():
		return false
	build()
	return true


## Index of the effect named `n` on bus `bus` (-1 when absent).
static func find_effect_index(bus: String, n: String) -> int:
	var bi := AudioServer.get_bus_index(bus)
	if bi < 0:
		return -1
	for j in AudioServer.get_bus_effect_count(bi):
		var e := AudioServer.get_bus_effect(bi, j)
		if e != null and e.resource_name == n:
			return j
	return -1


static func find_effect(bus: String, n: String) -> AudioEffect:
	var j := find_effect_index(bus, n)
	if j < 0:
		return null
	return AudioServer.get_bus_effect(AudioServer.get_bus_index(bus), j)
