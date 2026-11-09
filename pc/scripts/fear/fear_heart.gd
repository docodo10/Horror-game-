## Fear module — the player's heart (stress model, "beaucoup de BPM"). Pure logic, no scene access: the director feeds
## it a context every tick and reads bpm / stress / beat back. Deterministic for a given RNG seed (tests).
##
## Target heart rate = baseline (72 at rest, +3 per night, +up to 8 late in the scenario) + excess, where excess =
##   La Gardienne: waking (steps above) +16 · descending +20..+50 · searching +15..+50 (+12 when she sees you) ·
##     chasing +62..+82 · returning +8..+30 · jumpscare +110   (the ".." range follows her distance, 8 m -> 0 m)
##   + hiding while she is in the basement +14..+26 · darkness +7 (+6 more with the torch off) · battery < 25 % +4 / < 10 % +9
##   + exertion (1 - stamina) x 18 · adrenaline x 75 (scares: kick(), decays with tau 22 s)
##   with a soft knee above +70 (x 0.45): causes add up, the heart saturates like a real one.
## Dynamics: rises fast (tau 1.1 s, max +45 BPM/s; a startle also jolts it instantly), decays slowly (tau 9 s), ±1.5 BPM
## variability. Clamped to 58..178. stress = (bpm - 72) / (165 - 72) clamped 0..1 (the value every effect is driven by).
## Typical values: wandering in the light 72-80, dark + torch 85-95, she is near and unseen 105-125, chase 150-172,
## jumpscare / big fake-out 165-178, then a slow ~30-40 s walk back down.
extends RefCounted

const REST := 72.0
const MIN_BPM := 58.0
const MAX_BPM := 178.0
const STRESS_LO := 72.0
const STRESS_HI := 165.0
const RISE_TAU := 1.1
const FALL_TAU := 9.0
const MAX_RISE := 45.0          # BPM per second (a startle jolts past it through kick())
const ADRENALINE_TAU := 22.0
const KNEE := 70.0              # BPM above baseline where causes start to saturate

var bpm := REST
var target := REST
var adrenaline := 0.0
var stress := 0.0
var phase := 0.0                # 0..1 position in the current beat
var beats := 0
var since_beat := 10.0          # seconds since the last beat (pulse-synced effects)
var hold_bpm := -1.0            # debug / screenshots: >= 0 pins the rate
var parts := {}                 # last contributions by cause (logs, tests)

var _hrv := 0.0
var _hrv_t := 0.0
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Startle / scare: amount 0..1 (0.15 creak, 0.35 knock, 0.6 glimpse, 0.9 fake-out, 1.0 jumpscare).
func kick(amount: float) -> void:
	var a := clampf(amount, 0.0, 1.2)
	adrenaline = minf(1.2, adrenaline + a)
	bpm = minf(MAX_BPM, bpm + 26.0 * a)      # the jolt: the heart skips and races at once


func reset(to_bpm := REST) -> void:
	bpm = to_bpm
	target = to_bpm
	adrenaline = 0.0
	stress = _stress_of(bpm)
	phase = 0.0
	since_beat = 10.0


static func near(dist: float, rng_m: float) -> float:
	return clampf(1.0 - dist / rng_m, 0.0, 1.0)


## ctx keys (all optional): night, stage_k (0..1), ent_state, ent_dist, ent_sees, ent_on_screen, hidden, dark, torch_on,
## battery (0..100, -1 = no torch), stamina (0..1). Returns true when a beat lands during this tick.
func update(dt: float, ctx: Dictionary) -> bool:
	if dt <= 0.0:
		return false
	var night := float(ctx.get("night", 1))
	var base := REST + 3.0 * maxf(0.0, night - 1.0) + 8.0 * float(ctx.get("stage_k", 0.0))
	var es := String(ctx.get("ent_state", "dormant"))
	var d := float(ctx.get("ent_dist", 99.0))
	var n8 := near(d, 8.0)
	var ent := 0.0
	match es:
		"waking": ent = 16.0
		"descending": ent = 20.0 + 30.0 * n8
		"searching": ent = 15.0 + 35.0 * n8 + (12.0 if ctx.get("ent_sees", false) else 0.0)
		"chasing": ent = 62.0 + 20.0 * near(d, 6.0)
		"returning": ent = 8.0 + 22.0 * n8
		"jumpscare": ent = 110.0
	if ctx.get("ent_on_screen", false) and es != "dormant" and es != "disabled":
		ent += 10.0 * n8
	var hide := 0.0
	if ctx.get("hidden", false) and (es == "searching" or es == "descending" or es == "chasing"):
		hide = 14.0 + 12.0 * n8
	var dark := 0.0
	if ctx.get("dark", false):
		dark = 7.0 + (0.0 if ctx.get("torch_on", false) else 6.0)
		var bat := float(ctx.get("battery", -1.0))
		if bat >= 0.0 and ctx.get("torch_on", false):
			dark += 9.0 if bat < 10.0 else (4.0 if bat < 25.0 else 0.0)
	var exert := (1.0 - clampf(float(ctx.get("stamina", 1.0)), 0.0, 1.0)) * 18.0
	adrenaline *= exp(-dt / ADRENALINE_TAU)
	var adr := 75.0 * minf(adrenaline, 1.0)
	_hrv_t -= dt
	if _hrv_t <= 0.0:
		_hrv_t = _rng.randf_range(1.5, 4.0)
		_hrv = _rng.randf_range(-1.5, 1.5)
	var excess := ent + hide + dark + exert + adr
	if excess > KNEE:
		excess = KNEE + (excess - KNEE) * 0.45
	target = clampf(base + excess + _hrv, MIN_BPM, MAX_BPM)
	parts = {"base": base, "entity": ent, "hide": hide, "dark": dark, "exert": exert, "adrenaline": adr}
	if hold_bpm >= 0.0:
		bpm = hold_bpm
	elif target > bpm:
		bpm = minf(bpm + (target - bpm) * (1.0 - exp(-dt / RISE_TAU)), bpm + MAX_RISE * dt)
	else:
		bpm += (target - bpm) * (1.0 - exp(-dt / FALL_TAU))
	bpm = clampf(bpm, MIN_BPM, MAX_BPM)
	stress = _stress_of(bpm)
	# beat clock
	since_beat += dt
	phase += dt * bpm / 60.0
	if phase >= 1.0:
		phase = fmod(phase, 1.0)
		beats += 1
		since_beat = phase * 60.0 / maxf(bpm, 1.0)
		return true
	return false


## 0..1 pulse that peaks on each beat (pulse-synced vignette / CA).
func pulse() -> float:
	return exp(-since_beat / 0.11)


static func _stress_of(b: float) -> float:
	return clampf((b - STRESS_LO) / (STRESS_HI - STRESS_LO), 0.0, 1.0)
