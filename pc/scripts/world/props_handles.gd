## Handles (world module): builds world.handles from level_meta.json `handles{}` — 14 openables bound to the REAL moving
## nodes (model nodes of the original glTF instances or procedural level.glb pivots) with the closed / open LOCAL
## transforms the exporter measured by opening and closing each one in the web build. Port of Props.js
## (_buildDrawers/_buildCabinet/_buildPowerBox/_buildLockedBox/_buildPadlock) and Architecture.js (_upstairsDoor, _closetDoor).
##   drawers / cabinet doors / power-box door: ease out / inOut, sound at the start
##   doors: open 1-(1-k)^3, close k²(1.6-0.6k), latch sound at the end, colliders swapped (props_physics door binding)
##   powerBox.lever: LeverHandle — is_on, set_on(on) (await: flip 0.2 s, breaker_flip, world.set_power), follow_power(on)
##   lockedBox.lock: PadlockHandle — set_digits(code) (wheels roll, lock_wheel ticks), open = shackle pops (0.18 s outBack)
##                   then the lock drops onto the console (0.5 s), close = reset
##   lockedBox.lid:  LidHandle — opening pops the padlock off first (like the web)
extends RefCounted

const LevelLoader := preload("res://scripts/world/level_loader.gd")

const EASES := {
	"drawer": ["out", "inOut"], "cabinetDoor": ["out", "inOut"], "lid": ["outBack", "inOut"],
	"lever": ["inQuad", "inQuad"], "door": ["doorOpen", "doorClose"], "padlock": ["outBack", "inOut"],
}
## Door centres (pivot-local, web Architecture.js `center`): world_position() for sounds / gameplay.
const DOOR_CENTER := {"door.upstairs": Vector3(0.425, 1.0, -0.0225), "door.closet": Vector3(-0.016, 0.95, 0.31)}

class LeverHandle extends Handle:
	var world: Node = null
	var is_on := true

	func set_on(on: bool) -> void:
		if is_on == on and not animating: return
		is_on = on
		is_open = on
		await _go(1.0 if on else 0.0)
		Audio.play("breaker_flip", {"position": world_position()})
		if world != null and is_instance_valid(world) and world.get(&"power") != on: world.call("set_power", on)

	func open() -> void: await set_on(true)
	func close() -> void: await set_on(false)
	func toggle() -> void: await set_on(not is_on)

	## The breaker follows the mains silently (tripped at the blowout, reset by a debug power-on), unless it is moving.
	func follow_power(on: bool) -> void:
		if animating or is_on == on: return
		is_on = on
		set_state(on)

class PadlockHandle extends Handle:
	var shackle: Node3D = null
	var shackle_closed := Transform3D()
	var shackle_open := Transform3D()
	var wheels: Array = []                # dial nodes 0..3
	var digits: Array = [0, 0, 0, 0]
	var removed := false
	var _wheel_target: Array = [0.0, 0.0, 0.0, 0.0]
	var _wheel_from: Array = []
	var _wheel_tween: Tween = null
	var _fall_tween: Tween = null
	var _falling := false

	func open() -> void:
		if is_open:
			if animating: await settled
			return
		is_open = true
		Audio.play("unlock", {"position": world_position()})
		await _shackle_to(1.0, 0.18)
		await remove_lock(false)

	func close() -> void:
		if not is_open: return
		is_open = false
		removed = false
		_kill_tweens()
		_set_fall(0.0)
		_set_shackle(0.0)
		animating = false

	func toggle() -> void:
		if is_open: await close()
		else: await open()

	func set_state(open_: bool) -> void:
		_kill_tweens()
		is_open = open_
		removed = open_
		_set_shackle(1.0 if open_ else 0.0)
		_set_fall(1.0 if open_ else 0.0)
		animating = false

	## Pops the lock off the staple and drops it on the console in front of the box (fast: 0.35 s when the lid forces it).
	func remove_lock(fast: bool) -> void:
		if removed:
			if _falling: await settled
			return
		removed = true
		is_open = true
		_set_shackle(1.0)
		_falling = true
		animating = true
		_kill_fall()
		_fall_tween = node.create_tween()
		_fall_tween.tween_method(_set_fall, 0.0, 1.0, 0.35 if fast else 0.5)
		await _fall_tween.finished
		_falling = false
		animating = false
		Audio.play("bump", {"position": world_position(), "volume_db": linear_to_db(0.35)})
		settled.emit(true)

	## Rolls the 4 number wheels to `code` (one lock_wheel tick per wheel that changes).
	func set_digits(code: String) -> void:
		var s := code.lpad(4, "0").right(4)
		var changed := false
		for i in 4:
			var d := int(s[i]) if s[i].is_valid_int() else 0
			if d != int(digits[i]): changed = true
			digits[i] = d
			_wheel_target[i] = wheel_angle(d)
		if changed: Audio.play("lock_wheel", {"position": world_position(), "volume_db": linear_to_db(0.6)})
		if wheels.is_empty() or node == null or not node.is_inside_tree():
			_apply_wheels(1.0)
			return
		if _wheel_tween != null and _wheel_tween.is_valid(): _wheel_tween.kill()
		_wheel_from.clear()
		for w in wheels: _wheel_from.append((w as Node3D).rotation.x)
		_wheel_tween = node.create_tween()
		_wheel_tween.tween_method(_wheels_step, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	func _wheels_step(k: float) -> void:
		for i in mini(4, mini(wheels.size(), _wheel_from.size())):
			var w := wheels[i] as Node3D
			w.rotation = Vector3(lerp_angle(float(_wheel_from[i]), float(_wheel_target[i]), k), w.rotation.y, w.rotation.z)

	func set_digits_instant(code: String) -> void:
		var s := code.lpad(4, "0").right(4)
		for i in 4:
			digits[i] = int(s[i]) if s[i].is_valid_int() else 0
			_wheel_target[i] = wheel_angle(int(digits[i]))
		_apply_wheels(1.0)

	static func wheel_angle(d: int) -> float:
		return ((float(d) + 0.5) / 10.0) * TAU

	func _apply_wheels(_k: float) -> void:
		for i in mini(4, wheels.size()):
			var w := wheels[i] as Node3D
			w.rotation = Vector3(float(_wheel_target[i]), w.rotation.y, w.rotation.z)

	func _shackle_to(target: float, dur: float) -> void:
		if shackle == null or node == null or not node.is_inside_tree():
			_set_shackle(target)
			return
		animating = true
		var tw := node.create_tween()
		tw.tween_method(func(k: float) -> void: _set_shackle(target * Handle.ease_curve("outBack", k)), 0.0, 1.0, dur)
		await tw.finished

	func _set_shackle(v: float) -> void:
		if shackle != null and is_instance_valid(shackle):
			shackle.transform = shackle_closed.interpolate_with(shackle_open, v)

	## Web _applyLockFall: lift off the staple, arc forward / down, turn onto its back.
	func _set_fall(v: float) -> void:
		if node == null or not is_instance_valid(node): return
		t = v
		if v <= 0.0:
			node.transform = closed_xform
			return
		var a := closed_xform
		var b := open_xform
		var lift := sin(minf(1.0, v * 2.2) * PI) * 0.012
		var p := a.origin.lerp(b.origin, Handle.ease_curve("inQuad", v))
		p.y += lift
		p.z = a.origin.z + (b.origin.z - a.origin.z) * Handle.ease_curve("out", v)
		var q := a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), Handle.ease_curve("inOut", v))
		node.transform = Transform3D(Basis(q), p)

	func _kill_fall() -> void:
		if _fall_tween != null and _fall_tween.is_valid(): _fall_tween.kill()

	func _kill_tweens() -> void:
		_kill_fall()
		_falling = false

class LidHandle extends Handle:
	var padlock: Handle = null

	func open() -> void:
		if padlock != null and padlock.has_method("remove_lock") and not bool(padlock.get(&"removed")):
			padlock.call("remove_lock", true)   # not awaited: the lock drops while the lid swings up
		await super.open()

## Builds every handle. Returns {id: Handle}. `world` receives the lever / door callbacks.
static func build(world: Node, ctx: Dictionary) -> Dictionary:
	var meta: Dictionary = ctx.get("meta", {})
	var out := {}
	for id in meta.get("handles", {}):
		var hm: Dictionary = meta.handles[id]
		var kind := String(hm.get("kind", "drawer"))
		var h: Handle
		match kind:
			"lever":
				var lv := LeverHandle.new()
				lv.world = world
				h = lv
			"padlock": h = PadlockHandle.new()
			"lid": h = LidHandle.new()
			_: h = Handle.new()
		h.id = String(id)
		h.kind = kind
		var moving: Array = []
		for mv in hm.get("moving", []):
			var n := LevelLoader.find(ctx, mv.ref)
			if n == null:
				push_warning("[world] handle %s: moving node %s not found" % [id, mv.ref])
				continue
			moving.append({"node": n, "closed": LevelLoader.mat16(mv.closed), "open": LevelLoader.mat16(mv.open)})
		if moving.is_empty():
			push_warning("[world] handle %s has no moving node" % id)
			continue
		var primary := clampi(int(hm.get("primary", 0)), 0, moving.size() - 1)
		var pm: Dictionary = moving[primary]
		h.node = pm.node
		h.closed_xform = pm.closed
		h.open_xform = pm.open
		h.object = LevelLoader.find(ctx, hm.get("object"))
		if h.object == null: h.object = h.node
		h.contents = LevelLoader.find(ctx, hm.get("contents"))
		h.locked = bool(hm.get("locked", false))
		var dur: Array = hm.get("duration", [0.5, 0.45])
		h.open_duration = float(dur[0]) if dur.size() > 0 else 0.5
		h.close_duration = float(dur[1]) if dur.size() > 1 else h.open_duration
		h.duration = h.open_duration
		var eases: Array = EASES.get(kind, ["out", "inOut"])
		h.ease_open = eases[0]
		h.ease_close = eases[1]
		var sfx: Dictionary = hm.get("sfx", {})
		if sfx.get("open") is Array:
			h.sfx_open = String(sfx.open[0]); h.sfx_open_volume = float(sfx.open[1]); h.sfx_open_pitch = float(sfx.open[2])
		if sfx.get("close") is Array:
			h.sfx_close = String(sfx.close[0]); h.sfx_close_volume = float(sfx.close[1]); h.sfx_close_pitch = float(sfx.close[2])
		if kind == "door":
			h.dur_pad = 0.0
			h.sfx_close_at_end = true
			var c := Node3D.new()
			c.name = "Center"
			c.position = DOOR_CENTER.get(h.id, Vector3(0.0, 1.0, 0.0))
			h.node.add_child(c)
			h.center = c
		match kind:
			"padlock":
				var pl := h as PadlockHandle
				pl.moving = [pm]
				if moving.size() > 1:
					var sm: Dictionary = moving[1]
					pl.shackle = sm.node
					pl.shackle_closed = sm.closed
					pl.shackle_open = sm.open
				var anim: Dictionary = meta.get("anim", {}).get("padlock", {})
				for w in anim.get("wheels", []):
					var wn := LevelLoader.find(ctx, w)
					if wn != null: pl.wheels.append(wn)
				pl.set_digits_instant("0000")
				pl.set_state(false)
			"lever":
				h.moving = moving
				(h as LeverHandle).is_on = bool(hm.get("initiallyOpen", true))
				h.set_state((h as LeverHandle).is_on)
			_:
				h.moving = moving
				h.set_state(bool(hm.get("initiallyOpen", false)))
		out[h.id] = h
	if out.get("lockedBox.lid") is LidHandle and out.get("lockedBox.lock") is PadlockHandle:
		(out["lockedBox.lid"] as LidHandle).padlock = out["lockedBox.lock"]
	return out

## Contract ids that must exist even if a node failed to load (web _ensureContract): inert handles on a dummy node.
const CONTRACT := ["dresser.drawerTop", "dresser.drawerMid", "dresser.drawerBottom", "endTable.drawer", "alcoveCabinet.drawer_01",
	"alcoveCabinet.drawer_02", "alcoveCabinet.door_01", "alcoveCabinet.door_02", "powerBox.door", "powerBox.lever",
	"lockedBox.lid", "lockedBox.lock", "door.upstairs", "door.closet"]

static func ensure_contract(world: Node3D, handles: Dictionary) -> void:
	for id in CONTRACT:
		if handles.has(id): continue
		push_warning("[world] missing handle %s: inert stand-in" % id)
		var n := Node3D.new()
		n.name = "Missing_" + id.replace(".", "_")
		world.add_child(n)
		var h: Handle
		if id == "powerBox.lever":
			var lv := LeverHandle.new()
			lv.world = world
			h = lv
		else:
			h = Handle.new()
		h.id = id
		h.node = n
		h.object = n
		h.contents = n
		h.closed_xform = n.transform
		h.open_xform = n.transform
		h.locked = id == "door.upstairs"
		handles[id] = h
