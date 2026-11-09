## Fear module — glimpses of La Gardienne: she is somewhere she cannot be (top of the stairs, end of the dark corridor,
## behind you in the mirror, outside the closet louvers, in a dark doorway), seen for a fraction of a second, gone when
## the torch finds her, when you blink / look away, or if you never turn around. Uses the entity's glimpse hook
## (gardienne.gd glimpse() / end_glimpse(): a silent, AI-frozen apparition, only while she sleeps upstairs: her state
## machine never leaves "dormant" and she never sees, hears or catches anybody from there).
## Lifecycle: start() places her out of view (+ a cue sound drawing the eye) -> update() watches the camera / torch ->
## first sight: stinger + heart jolt + flinch -> vanish (torch | blink | away | close | timeout | woke) -> end_glimpse().
extends RefCounted

const SEEN_COS := 0.88            # ~28° from the view axis + clear line of sight = she is seen
const TORCH_COS := 0.982          # ~11° inside the beam
const TORCH_RANGE := 9.0

var d = null                      # director
var active := false
var kind := ""
var feet := Vector3.ZERO
var head := Vector3.ZERO
var t := 0.0
var seen_t := -1.0
var hold := 0.6
var timeout := 11.0
var mirror := false
var louvers := false
var reason := ""                  # why the last one ended
var count := 0
var seen_count := 0
var history: Array = []           # [{t, kind, seen, reason, dur}]

var _mirror_c := Vector3.ZERO
var _mirror_n := Vector3.FORWARD
var _away_t := 0.0


func _init(director) -> void:
	d = director


## Places her. opts: hold (seconds once seen), timeout, mirror (Vector3 centre + normal), louvers, mode, look.
func start(p_kind: String, p_feet: Vector3, yaw: float, opts := {}) -> bool:
	if active:
		return false
	var ent = d.entity()
	if ent == null:
		return false
	var mode := String(opts.get("mode", "idle"))
	var look = opts.get("look", "camera")
	var ok := false
	if ent.has_method("glimpse"):
		ok = bool(ent.call("glimpse", p_feet, yaw, mode, look))
	if not ok:
		return false
	active = true
	kind = p_kind
	feet = p_feet
	head = p_feet + Vector3(0.0, 1.62, 0.0)
	t = 0.0
	seen_t = -1.0
	_away_t = 0.0
	hold = float(opts.get("hold", 0.6))
	timeout = float(opts.get("timeout", 11.0))
	mirror = opts.has("mirror_c")
	louvers = bool(opts.get("louvers", false))
	if mirror:
		_mirror_c = opts.mirror_c
		_mirror_n = opts.mirror_n
	count += 1
	return true


## Returns true while she is out.
func update(dt: float, c: Dictionary) -> bool:
	if not active:
		return false
	t += dt
	var ent = d.entity()
	if ent == null or String(ent.get("state")) != "dormant" or ent.get("glimpsing") == false:
		_end("woke", false)
		return false
	if ent.has_method("get_head_position"):
		head = ent.call("get_head_position")
	var eye: Vector3 = c.get("eye", Vector3.ZERO)
	var fwd: Vector3 = c.get("fwd", Vector3.FORWARD)
	var to := head - eye
	var dist := to.length()
	if dist < (0.75 if (louvers or mirror) else 2.2):
		_end("close", true)                    # never let the player walk into her
		return false
	var dir := to / maxf(dist, 1e-4)
	var direct := false
	if louvers:
		direct = fwd.dot(dir) > 0.8          # through the slats (the closed door blocks the sight ray)
	else:
		direct = fwd.dot(dir) > SEEN_COS and dist < 16.0 and not d.line_blocked(eye, head)
	var on_screen := direct
	if mirror:
		# seen in the glass only: looking at the mirror, she stands behind. Turning around finds nobody: she must be
		# gone before the camera can frame her directly.
		if fwd.dot(dir) > 0.25:
			_end("turned", true)
			return false
		var tm := _mirror_c - eye
		on_screen = fwd.dot(tm.normalized()) > 0.9 and tm.length() < 4.0 and tm.dot(_mirror_n) < 0.0
	var lit := false
	if c.get("torch_on", false) and dist < TORCH_RANGE and not mirror and not louvers:
		var bd: Vector3 = c.get("beam_dir", fwd)
		var chest := feet + Vector3(0.0, 1.2, 0.0)
		lit = (bd.dot(dir) > TORCH_COS or bd.dot((chest - eye).normalized()) > TORCH_COS) and direct
	if seen_t < 0.0:
		if on_screen and t > 0.12:
			seen_t = t
			seen_count += 1
			d.on_glimpse_seen(kind, dist, lit)
		elif t > timeout:
			_end("timeout", false)
			return false
		return true
	var since := t - seen_t
	if lit and since > 0.3:
		_end("torch", true)
		return false
	if not on_screen:
		_away_t += dt
		if _away_t > 0.12:
			_end("away", true)
			return false
	else:
		_away_t = 0.0
	if since > hold:
		_end("blink", true)
		return false
	return true


func abort() -> void:
	if active:
		_end("abort", false)


func _end(why: String, effects: bool) -> void:
	active = false
	reason = why
	history.append({"t": d.clock, "kind": kind, "seen": seen_t >= 0.0, "reason": why, "dur": snappedf(t, 0.01)})
	var ent = d.entity()
	if ent != null and ent.has_method("end_glimpse"):
		ent.call("end_glimpse")
	d.on_glimpse_end(kind, why, seen_t >= 0.0 and effects)
