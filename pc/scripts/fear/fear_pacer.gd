## Fear module — pacing: the tension curve build-up -> spike -> relief, cooldowns and budgets. Pure logic (tests drive it
## with a fake clock). The director asks it every tick whether a minor (false alarm) or a major (spike) event is due,
## then reports what it fired with record().
##
## Phases
##   calm    the first seconds of a game (intro): nothing but the scripted beats.
##   build   tension rises 0 -> 1 over build_time (shorter late in the scenario, on later nights, on "extreme"); minor
##           events fire on a timer that shortens as tension rises. At tension 1 a major is due: it waits for a good
##           moment (moment score from the director: looking away, dark, just solved, hiding, standing still) or fires
##           anyway after peak_wait seconds.
##   spike   a major is running (the director sets its length); nothing else fires.
##   relief  after a major, a real visit of La Gardienne, a catch or a scripted beat: no events at all for a while.
##   hunt    La Gardienne is active (waking .. returning): no systemic scare may blur the real cues.
## Budgets (never spam): minimum gap between two events, at most N events per rolling minute, minimum gap between two
## majors, per-scare cooldowns (catalogue), no immediate repeat of the same scare.
extends RefCounted

const LEVELS := {
	# freq: minor timer divisor; build: build-time divisor; gap: min seconds between events; per_min: max events / 60 s;
	# major_gap: min seconds between majors; relief: relief length multiplier; calm: calm phase length (s)
	"normal": {"freq": 0.6, "build": 0.7, "gap": 18.0, "per_min": 2, "major_gap": 150.0, "relief": 1.4, "calm": 40.0},
	"extreme": {"freq": 1.15, "build": 1.0, "gap": 12.0, "per_min": 3, "major_gap": 95.0, "relief": 1.0, "calm": 28.0},
}

var level := "extreme"
var phase := "calm"
var phase_t := 0.0
var tension := 0.0
var t := 0.0                      # pacer clock (s)
var peak_t := 0.0                 # time spent at tension 1 waiting for a moment
var relief_len := 0.0
var spike_len := 0.0
var next_minor := 0.0
var last_event_t := -1000.0
var last_major_t := -1000.0
var last_id := ""
var history: Array = []           # [{t, id, major}] (everything recorded, for budgets and tests)
var cooldown_until := {}          # id -> t

var _rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	next_minor = 30.0


func cfg() -> Dictionary:
	return LEVELS.get(level, LEVELS["extreme"])


## ctx: stage_k 0..1, night 1..3, ent_active bool, game_t (s since start), stage String.
func update(dt: float, ctx: Dictionary) -> void:
	t += dt
	phase_t += dt
	var c := cfg()
	var sk := clampf(float(ctx.get("stage_k", 0.0)), 0.0, 1.0)
	var night := float(ctx.get("night", 1))
	if ctx.get("ent_active", false):
		if phase != "hunt":
			_set_phase("hunt")
		return
	match phase:
		"hunt":
			# she went back upstairs: breathe out first
			start_relief(lerpf(18.0, 10.0, sk) * float(c.relief))
		"calm":
			if phase_t >= float(c.calm) or String(ctx.get("stage", "intro")) != "intro":
				_set_phase("build")
				tension = 0.1
				next_minor = _rng.randf_range(4.0, 14.0)
		"relief":
			if phase_t >= relief_len:
				_set_phase("build")
				tension = 0.25 + 0.15 * sk
				next_minor = _rng.randf_range(6.0, 16.0)
		"spike":
			if phase_t >= spike_len:
				start_relief(_relief_after_major(sk))
		"build":
			var build_time := lerpf(100.0, 55.0, sk) / float(c.build) / (1.0 + 0.2 * (night - 1.0))
			tension = minf(1.0, tension + dt / build_time)
			next_minor -= dt
			if tension >= 1.0:
				peak_t += dt
			else:
				peak_t = 0.0


func _set_phase(p: String) -> void:
	phase = p
	phase_t = 0.0
	if p != "build":
		peak_t = 0.0


func start_relief(seconds: float) -> void:
	_set_phase("relief")
	relief_len = maxf(seconds, 0.0)


func start_spike(seconds: float) -> void:
	_set_phase("spike")
	spike_len = maxf(seconds, 0.5)


func _relief_after_major(sk: float) -> float:
	return lerpf(45.0, 26.0, sk) * float(cfg().relief) * _rng.randf_range(0.85, 1.2)


## Rolling-window budget: may any event fire now?
func budget_ok(major: bool) -> bool:
	var c := cfg()
	if t - last_event_t < float(c.gap):
		return false
	if major and t - last_major_t < float(c.major_gap):
		return false
	var n := 0
	for e in history:
		if t - float(e.t) < 61.0:   # rolling minute (+1 s margin)
			n += 1
	return n < int(c.per_min)


func cooldown_ok(id: String) -> bool:
	return t >= float(cooldown_until.get(id, -1.0)) and id != last_id


## Is a false alarm due now? (the director then picks one and calls record())
func want_minor(ctx: Dictionary) -> bool:
	if phase != "build" or next_minor > 0.0:
		return false
	return budget_ok(false)


## Is the spike due now? moment: 0..1 quality of the moment (director).
func want_major(ctx: Dictionary, moment: float) -> bool:
	if phase != "build" or tension < 1.0 or ctx.get("modal", false):
		return false
	if not budget_ok(true):
		return false
	return moment >= 0.55 or peak_t >= 24.0 or (moment >= 0.3 and peak_t >= 10.0)


## Something fired (id from the catalogue). cooldown: seconds before that id may fire again.
func record(id: String, major: bool, cooldown: float, ctx: Dictionary, spike_seconds := 0.0) -> void:
	history.append({"t": t, "id": id, "major": major})
	if history.size() > 400:
		history.pop_front()
	last_event_t = t
	last_id = id
	cooldown_until[id] = t + cooldown
	var sk := clampf(float(ctx.get("stage_k", 0.0)), 0.0, 1.0)
	if major:
		last_major_t = t
		tension = 0.0
		if spike_seconds > 0.0:
			start_spike(spike_seconds)
		else:
			start_relief(_relief_after_major(sk))
	else:
		tension = minf(1.0, tension + 0.06)
		var base := lerpf(50.0, 20.0, clampf(tension * 0.6 + sk * 0.6, 0.0, 1.0))
		next_minor = base * _rng.randf_range(0.75, 1.3) / float(cfg().freq) / (1.0 + 0.12 * (float(ctx.get("night", 1)) - 1.0))


## Scripted beats of other modules (blowout, breaker visit, key) count as spikes: relief after them.
func external_spike(relief_seconds: float) -> void:
	tension = 0.0
	last_major_t = maxf(last_major_t, t - float(cfg().major_gap) * 0.5)
	start_relief(relief_seconds)


func events_in(window: float) -> int:
	var n := 0
	for e in history:
		if t - float(e.t) < window:
			n += 1
	return n
