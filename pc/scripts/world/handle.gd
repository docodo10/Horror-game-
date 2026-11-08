## Animated openable (drawer, door, lid, lever, padlock…). World module: scripts/world/props_handles.gd builds one per
## level_meta.json `handles{}` entry, bound to the real moving node with the exported closed / open LOCAL transforms.
## Port of the web Props.js `Anim` + `_handle` and Architecture.js `_door`.
##
## Public API (keep): id, node, closed_xform, open_xform, is_open, locked, duration, sfx_open, sfx_close, contents, animating,
##   world_position(), open() / close() / toggle() (await)
## Additions:
##   kind              "drawer" | "door" | "cabinetDoor" | "lid" | "lever" | "padlock"
##   object            logical root (the node gameplay registers; = node unless set, e.g. the breaker lever group)
##   center            Node3D whose position world_position() returns (door: middle of the leaf), else node
##   t                 current pose 0 (closed) .. 1 (open), eased (outBack may overshoot a little)
##   open_duration / close_duration (s, -1 = duration), ease_open / ease_close (see ease_curve()), dur_pad (web Anim: the time is
##                     scaled by min(1, |target - t| + dur_pad) when an animation is redirected half-way)
##   sfx_open_volume / sfx_open_pitch / sfx_close_volume / sfx_close_pitch, sfx_close_at_end (doors: latch at the end)
##   moving            Array of {node: Node3D, closed: Transform3D, open: Transform3D}; every node follows t ([0] = node)
##   on_change(t)      called on every pose change (upper hall visibility…)
##   on_start(opening) called when an animation starts (door colliders), on_settled(open) when it ends
##   signal settled(open)
##   set_state(open)   instant pose, no sound (resets, debug); wait() awaits the running animation
## `is_open` flips when an animation STARTS (web semantics: prompts and pickups react at once); `animating` while moving.
## Animations are tweens bound to `node`: they pause with the game like every world node.
class_name Handle
extends RefCounted

signal settled(open: bool)

var id := ""
var kind := ""
var node: Node3D = null              # the moving node (raycast target is its collision body child or a proxy)
var object: Node3D = null
var center: Node3D = null
var closed_xform := Transform3D()
var open_xform := Transform3D()
var is_open := false
var locked := false
var duration := 0.6
var open_duration := -1.0
var close_duration := -1.0
var ease_open := "out"
var ease_close := "inOut"
var dur_pad := 0.15
var sfx_open := ""
var sfx_close := ""
var sfx_open_volume := 1.0
var sfx_open_pitch := 1.0
var sfx_close_volume := 1.0
var sfx_close_pitch := 1.0
var sfx_close_at_end := false
var contents: Node3D = null           # items parented here move with the drawer
var animating := false
var t := 0.0
var moving: Array = []
var on_change := Callable()
var on_start := Callable()
var on_settled := Callable()

var _tween: Tween = null
var _from := 0.0
var _target := 0.0
var _ease := "out"

func world_position() -> Vector3:
	var n: Node3D = center if center != null and is_instance_valid(center) else node
	if n == null or not is_instance_valid(n) or not n.is_inside_tree(): return Vector3.ZERO
	return n.global_position

func open() -> void:
	if node == null: return
	if is_open:
		if animating: await settled
		return
	is_open = true
	_play(sfx_open, sfx_open_volume, sfx_open_pitch)
	await _go(1.0)

func close() -> void:
	if node == null: return
	if not is_open:
		if animating: await settled
		return
	is_open = false
	if not sfx_close_at_end: _play(sfx_close, sfx_close_volume, sfx_close_pitch)
	await _go(0.0)

func toggle() -> void:
	if is_open: await close()
	else: await open()

## Awaits the running animation (returns at once when idle).
func wait() -> void:
	if animating: await settled

## Instant pose (no sound, no tween). Releases anyone awaiting a running animation.
func set_state(open_: bool) -> void:
	var was_animating := animating
	_kill()
	is_open = open_
	_from = 1.0 if open_ else 0.0
	_target = _from
	t = _target
	_apply(t)
	animating = false
	if on_settled.is_valid(): on_settled.call(open_)
	if was_animating: settled.emit(open_)

## Kept from the stub (tweens straight to a pose with a sound): prefer open() / close().
func _animate(target: Transform3D, sfx: String) -> void:
	var to_open := target.is_equal_approx(open_xform)
	if sfx != "": _play(sfx, 1.0, 1.0)
	is_open = to_open
	await _go(1.0 if to_open else 0.0)

# ------------------------------------------------------------------ internals

func _ensure_moving() -> void:
	if moving.is_empty() and node != null:
		moving.append({"node": node, "closed": closed_xform, "open": open_xform})

func _go(target: float) -> void:
	_ensure_moving()
	_kill()
	_from = t
	_target = target
	var opening := target > _from
	if absf(target - _from) < 1e-4:
		_finish()
		return
	var base := open_duration if opening else close_duration
	if base < 0.0: base = duration
	var dur := maxf(0.05, base * minf(1.0, absf(target - _from) + dur_pad))
	_ease = ease_open if opening else ease_close
	animating = true
	if on_start.is_valid(): on_start.call(opening)
	if node == null or not node.is_inside_tree():
		_finish()
		return
	_tween = node.create_tween()
	_tween.tween_method(_step, 0.0, 1.0, dur)
	_tween.finished.connect(_finish, CONNECT_ONE_SHOT)
	await settled

func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _step(k: float) -> void:
	t = _from + (_target - _from) * ease_curve(_ease, k)
	_apply(t)

func _finish() -> void:
	_tween = null
	t = _target
	_apply(t)
	animating = false
	var open_ := _target > 0.5
	if not open_ and sfx_close_at_end: _play(sfx_close, sfx_close_volume, sfx_close_pitch)
	if on_settled.is_valid(): on_settled.call(open_)
	settled.emit(open_)

func _apply(v: float) -> void:
	_ensure_moving()
	for m in moving:
		var n: Node3D = m.get("node")
		if n != null and is_instance_valid(n):
			n.transform = (m["closed"] as Transform3D).interpolate_with(m["open"] as Transform3D, v)
	if on_change.is_valid(): on_change.call(v)

func _play(sfx: String, volume: float, pitch: float) -> void:
	if sfx == "": return
	Audio.play(sfx, {"position": world_position(), "volume_db": linear_to_db(maxf(volume, 0.0001)), "pitch": pitch})

## Easing curves of the web build (Props.js `E` + the door curves of Architecture.js).
static func ease_curve(name: String, k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	match name:
		"linear": return k
		"in": return k * k * k
		"out", "doorOpen": return 1.0 - pow(1.0 - k, 3.0)
		"inOut": return 4.0 * k * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 3.0) / 2.0
		"sine": return -(cos(PI * k) - 1.0) / 2.0
		"outBack":
			var c1 := 1.3
			var c3 := c1 + 1.0
			return 1.0 + c3 * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
		"inQuad": return k * k
		"doorClose": return k * k * (1.6 - 0.6 * k)
	return k
