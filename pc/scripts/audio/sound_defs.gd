## Audio module — sound definitions (port of src/audio/Audio.js `SOUNDS`).
## One SoundDef per engine sound name. The recorded files / loop flag / gainDb come from res://assets/audio/manifest.json
## (manifest gainDb overrides `g`). Fields:
##   cat    category bus: sfx | foley | ambience | music | voice (voice = the creature, never ducked)
##   g      default gain dB          max   simultaneous voices of this name      gap  min seconds between two plays
##   ref    distance (m) under which the sound is at full level   roll  inverse-distance rolloff (Web Audio "inverse")
##   rv     reverb amount 0..1 (< 0.15 = dry bus)                 jit   pitch ±3 % / gain ±2 dB jitter on one-shots
##   pos    default position key (see audio_manager._default_pos) single one shared loop instance whatever the position
##   ceil   force the source above the ceiling                     rnd   random loop start offset
##   follow loop follows the creature when no explicit position was given
extends RefCounted


class SoundDef:
	var cat := "sfx"
	var g := 0.0
	var max_voices := 4
	var gap := 0.025
	var ref := 1.0
	var roll := 1.1
	var rv := 1.0
	var jit := true
	var pos := ""
	var single := false
	var ceil := false
	var rnd := false
	var follow := false


## name -> [category, gain dB, overrides]
const TABLE := {
	# ---- player body / foley
	"footstep_carpet": ["foley", -6.0, {"max": 3, "rv": 0.55}],
	"footstep_wood": ["foley", -3.0, {"max": 3, "rv": 0.8}],
	"footstep_concrete": ["foley", 0.0, {"max": 3, "rv": 0.9}],
	"cloth_move": ["foley", -6.0, {"max": 2, "rv": 0.3}],
	"land_thump": ["foley", -4.0, {"max": 2, "rv": 0.8}],
	"player_breath_run": ["foley", 0.0, {"rv": 0.06, "jit": false, "rnd": true}],
	"player_breath_scared": ["foley", -2.0, {"rv": 0.05, "jit": false, "rnd": true}],
	"player_gasp": ["foley", -3.0, {"max": 1, "gap": 0.8, "rv": 0.25}],
	"heartbeat": ["foley", -4.0, {"rv": 0.0, "jit": false, "rnd": true}],
	"heartbeat_fast": ["foley", -4.0, {"rv": 0.0, "jit": false, "rnd": true}],
	"heartbeat_single": ["foley", -3.0, {"max": 2, "rv": 0.0}],
	"pickup": ["foley", -4.0, {"max": 2, "rv": 0.5}],
	"paper": ["foley", -5.0, {"max": 2, "rv": 0.4}],
	"flashlight_click": ["foley", -6.0, {"max": 2, "gap": 0.12, "rv": 0.4, "ref": 0.5}],
	"battery_change": ["foley", -4.0, {"max": 1, "gap": 0.3, "rv": 0.4}],
	"key_pickup": ["foley", -3.0, {"max": 1, "gap": 0.3, "rv": 0.5}],
	"bump": ["foley", -3.0, {"max": 2, "gap": 0.25, "rv": 1.0}],
	# ---- world sfx
	"door_creak_open": ["sfx", 0.0, {"max": 2, "ref": 1.4}],
	"door_close": ["sfx", -2.0, {"max": 2, "ref": 1.4}],
	"door_locked": ["sfx", -2.0, {"max": 1, "gap": 0.3, "ref": 1.3}],
	"unlock": ["sfx", -2.0, {"max": 1, "gap": 0.3, "ref": 1.2}],
	"drawer_open": ["sfx", -3.0, {"max": 2}],
	"drawer_close": ["sfx", -3.0, {"max": 2}],
	"cabinet_open": ["sfx", -4.0, {"max": 2}],
	"cabinet_close": ["sfx", -4.0, {"max": 2}],
	"box_open": ["sfx", -4.0, {"max": 1, "gap": 0.2}],
	"lock_wheel": ["sfx", -8.0, {"max": 4, "gap": 0.03, "ref": 0.6}],
	"lock_fail": ["sfx", -3.0, {"max": 1, "gap": 0.2}],
	"lock_success": ["sfx", -2.0, {"max": 1, "gap": 0.3}],
	"breaker_flip": ["sfx", 0.0, {"max": 1, "gap": 0.3, "ref": 1.5, "pos": "powerBox"}],
	"power_up": ["sfx", -2.0, {"max": 1, "gap": 2.0, "ref": 2.0, "pos": "light"}],
	"light_pop": ["sfx", 0.0, {"max": 1, "gap": 0.4, "ref": 1.6, "pos": "light"}],
	"tv_static": ["sfx", 2.0, {"ref": 1.1, "pos": "tv", "jit": false, "single": true, "rnd": true}],
	"tv_on": ["sfx", 0.0, {"max": 1, "gap": 0.2, "pos": "tv"}],
	"tv_off": ["sfx", -2.0, {"max": 1, "gap": 0.2, "pos": "tv"}],
	"rocking_chair": ["sfx", -4.0, {"max": 2, "gap": 0.15, "pos": "rocking"}],
	"closet_enter": ["sfx", -3.0, {"max": 1, "gap": 0.3}],
	"closet_exit": ["sfx", -3.0, {"max": 1, "gap": 0.3}],
	"window_tap": ["sfx", -2.0, {"max": 1, "gap": 0.5, "pos": "window", "ref": 1.2}],
	"clock_chime": ["sfx", 0.0, {"max": 1, "gap": 1.0, "pos": "grandfather", "ref": 1.6}],
	"win_door": ["sfx", -2.0, {"max": 1, "gap": 1.0}],
	"stair_creak": ["sfx", -3.0, {"max": 2, "gap": 0.1, "pos": "stairs"}],
	"house_creak": ["sfx", -6.0, {"max": 2, "gap": 0.2, "pos": "house", "ref": 1.4}],
	"knock_wall": ["sfx", 0.0, {"max": 1, "gap": 1.0, "pos": "wall", "ref": 1.4}],
	# ---- ambience beds
	"room_tone": ["ambience", -12.0, {"rv": 0.0, "jit": false, "single": true, "rnd": true}],
	"furnace": ["ambience", -6.0, {"rv": 0.3, "jit": false, "single": true, "pos": "furnace", "ref": 1.6, "rnd": true}],
	"light_buzz": ["ambience", -6.0, {"rv": 0.12, "jit": false, "single": true, "pos": "light", "ref": 0.8, "roll": 1.3, "rnd": true}],
	"fan_hum": ["ambience", -8.0, {"rv": 0.3, "jit": false, "single": true, "pos": "fan", "ref": 1.2, "rnd": true}],
	"clock_tick": ["ambience", -4.0, {"rv": 0.25, "jit": false, "pos": "alarmClock", "ref": 0.45, "roll": 1.4, "rnd": true}],
	"wind_outside": ["ambience", -10.0, {"rv": 0.2, "jit": false, "pos": "window", "ref": 1.5, "rnd": true}],
	"ambience_drone": ["ambience", -8.0, {"rv": 0.0, "jit": false, "single": true, "rnd": true}],
	# ---- the creature (never ducked)
	"entity_step": ["voice", 0.0, {"max": 3, "ref": 1.3, "pos": "entityFeet"}],
	"entity_step_stairs": ["voice", 0.0, {"max": 3, "ref": 1.3, "pos": "entityFeet"}],
	"ceiling_steps": ["voice", 0.0, {"max": 3, "pos": "ceiling", "ref": 1.6, "ceil": true}],
	"ceiling_walk": ["voice", 0.0, {"max": 1, "gap": 3.0, "pos": "ceiling", "ref": 1.6, "ceil": true}],
	"entity_breath": ["voice", -6.0, {"max": 2, "gap": 0.3, "ref": 0.9, "pos": "entityHead"}],
	"entity_croak": ["voice", -2.0, {"max": 1, "gap": 0.5, "ref": 1.2, "pos": "entityHead"}],
	"lullaby_hum": ["voice", 0.0, {"ref": 1.2, "jit": false, "single": true, "pos": "entityHead", "follow": true}],
	"whisper": ["voice", -4.0, {"max": 2, "gap": 0.4, "ref": 0.7, "pos": "behind"}],
	"giggle": ["voice", -6.0, {"max": 1, "gap": 1.0, "pos": "far"}],
	"jumpscare": ["voice", 0.0, {"max": 1, "gap": 1.2, "ref": 2.5, "rv": 0.5}],
	# ---- music
	"stinger": ["music", -3.0, {"max": 1, "gap": 2.5, "rv": 0.0, "jit": false}],
	"chase_music": ["music", -4.0, {"rv": 0.0, "jit": false, "single": true}],
	# ---- fear module (res://assets/audio/fear/manifest.json, synthesized CC0 by scripts/fear/tools/make_fear_sounds.py).
	# The head-locked layers (heartbeat, rumble, drone, tinnitus, hits, stingers, riser) are played by scripts/fear on the
	# Master bus (+12 dB = Buses.HEADROOM_DB, never muffled / silenced by the fear effects); the others are world sounds.
	"fear_heartbeat": ["foley", -2.0, {"max": 3, "rv": 0.0, "jit": false}],
	"fear_rumble": ["ambience", -6.0, {"rv": 0.0, "jit": false, "rnd": true}],
	"fear_drone": ["ambience", -14.0, {"rv": 0.0, "jit": false, "rnd": true}],
	"fear_tinnitus": ["foley", -24.0, {"max": 1, "gap": 2.0, "rv": 0.0, "jit": false}],
	"fear_sub_hit": ["sfx", -3.0, {"max": 2, "gap": 0.3, "rv": 0.0, "jit": false}],
	"fear_stinger": ["music", -2.0, {"max": 1, "gap": 2.0, "rv": 0.0, "jit": false}],
	"fear_stinger_big": ["music", -3.0, {"max": 1, "gap": 1.5, "rv": 0.0, "jit": false}],
	"fear_riser": ["music", -8.0, {"max": 1, "gap": 2.0, "rv": 0.0, "jit": false}],
	"fear_crash": ["sfx", 3.0, {"max": 1, "gap": 0.5, "ref": 1.5}],
	"fear_ball": ["sfx", -5.0, {"max": 3, "gap": 0.05, "ref": 1.0, "rv": 0.8}],
	"fear_distant": ["sfx", -6.0, {"max": 1, "gap": 2.0, "ref": 2.0, "rv": 0.4}],
	"fear_scratch": ["sfx", -8.0, {"max": 1, "gap": 1.0, "ref": 0.8, "pos": "wall"}],
}

## Alternative names (web contract): 'ambience' is the room tone.
const ALIASES := {"ambience": "room_tone"}

## Random "house life" sounds (also used by gameplay scares): the ambient scheduler stays quiet after any of them.
const LIFE_NAMES := ["house_creak", "stair_creak", "ceiling_walk", "ceiling_steps", "knock_wall", "window_tap", "whisper", "giggle"]

const CAT_LEVEL := {"sfx": 1.0, "foley": 0.92, "ambience": 0.9, "music": 0.8, "voice": 1.0}
const CAT_PRIO := {"ambience": 0, "sfx": 1, "foley": 1, "voice": 3, "music": 3}


static func make(entry: Array) -> SoundDef:
	var d := SoundDef.new()
	d.cat = entry[0]
	d.g = entry[1]
	var o: Dictionary = entry[2]
	d.max_voices = int(o.get("max", 4))
	d.gap = float(o.get("gap", 0.025))
	d.ref = float(o.get("ref", 1.0))
	d.roll = float(o.get("roll", 1.1))
	d.rv = float(o.get("rv", 1.0))
	d.jit = bool(o.get("jit", true))
	d.pos = String(o.get("pos", ""))
	d.single = bool(o.get("single", false))
	d.ceil = bool(o.get("ceil", false))
	d.rnd = bool(o.get("rnd", false))
	d.follow = bool(o.get("follow", false))
	return d


## All definitions, keyed by sound name.
static func build_all() -> Dictionary:
	var out := {}
	for n in TABLE:
		out[n] = make(TABLE[n])
	return out


## Definition used for a manifest name missing from TABLE (plays as a plain sfx).
static func default_def() -> SoundDef:
	return make(["sfx", 0.0, {}])
