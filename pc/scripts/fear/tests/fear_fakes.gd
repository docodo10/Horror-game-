## Fear module tests — light fakes of the systems the director reads (player, entity, world, puzzles, garderie, UI).
extends RefCounted

const HOME := Vector3(-3.0, 2.75, -3.6)


class FakePlayer extends Node3D:
	var camera := Camera3D.new()
	var flashlight := {"has": false, "on": false, "battery": 100.0, "light": null}
	var hidden := false
	var hide_spot = null
	var stamina := 1.0
	var speed := 0.0
	var stress_bias := 0.0
	var flinches := 0
	var stutters := 0

	func _init() -> void:
		camera.top_level = true
		add_child(camera)

	func flinch(_s := 1.0) -> void:
		flinches += 1

	func flashlight_stutter(_s := 0.5) -> void:
		stutters += 1

	func get_visibility() -> float:
		return 0.7

	## feet position + yaw/pitch (radians, player convention: forward = (-sin yaw, 0, -cos yaw)).
	func place(feet: Vector3, yaw: float, pitch := 0.0, eye_h := 1.62) -> void:
		global_position = feet
		camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), feet + Vector3(0, eye_h, 0))


class FakeEntity extends Node3D:
	var state := "dormant"
	var fear := 0.0
	var active := false
	var seeing := false
	var glimpsing := false
	var glimpses := 0
	var glimpse_log: Array = []
	var bad_glimpses := 0

	func glimpse(pos: Vector3, _yaw := 0.0, _mode := "idle", _look: Variant = null) -> bool:
		if state != "dormant" or glimpsing:
			bad_glimpses += 1 if state != "dormant" else 0
			return false
		glimpsing = true
		glimpses += 1
		glimpse_log.append(pos)
		global_position = pos
		return true

	func end_glimpse() -> void:
		glimpsing = false
		global_position = HOME

	func get_head_position() -> Vector3:
		return global_position + Vector3(0, 1.62, 0)

	func set_state(s: String) -> void:
		var prev := state
		if s == prev:
			return
		state = s
		active = not (s == "dormant" or s == "disabled")
		Events.entity_state.emit(s, prev)


class FakeLighting extends Node:
	var calls := {}

	func flicker(_d := 0.6, _depth := 1.0) -> void:
		_n("flicker")

	func set_stress(_v: float) -> void:
		_n("set_stress")

	func door_strip_occluded(_v: float) -> void:
		_n("door_strip_occluded")

	func _n(k: String) -> void:
		calls[k] = int(calls.get(k, 0)) + 1


class FakeHandle extends RefCounted:
	var is_open := false
	var locked := true

	func world_position() -> Vector3:
		return Vector3(-3.0, 3.75, -2.78)


class FakeAnim extends RefCounted:
	var rocking := false
	var chain_kicks := 0

	func kick_chain(_a := 0.1) -> void:
		chain_kicks += 1


class FakeCrt extends RefCounted:
	var active := false
	var flickers := 0

	func flicker(_d := 0.0) -> void:
		flickers += 1


class FakeRefl extends RefCounted:
	var mirror_active := false


class FakeWorld extends Node3D:
	var power := true
	var lighting := FakeLighting.new()
	var handles := {"door.upstairs": FakeHandle.new()}
	var anim := FakeAnim.new()
	var crt := FakeCrt.new()
	var reflections := FakeRefl.new()
	var rocks := 0

	func _init() -> void:
		add_child(lighting)

	## Coarse sight model: the basement / garderie wall (x = -3.6, open only at the doorway z 1.72..2.48), the nook wall
	## (z = -2.75, open at the doorway x 0.9..1.8) and the basement ceiling slab (open over the stairs, z < 1.15).
	func line_blocked(a: Vector3, b: Vector3) -> bool:
		if (a.x < -3.6) != (b.x < -3.6):
			var t := (-3.6 - a.x) / (b.x - a.x)
			var z := a.z + (b.z - a.z) * t
			if z < 1.72 or z > 2.48:
				return true
		if (a.z < -2.75) != (b.z < -2.75) and maxf(a.y, b.y) < 2.6:
			var t2 := (-2.75 - a.z) / (b.z - a.z)
			var x := a.x + (b.x - a.x) * t2
			if x < 0.9 or x > 1.8:
				return true
		if (a.y < 2.5) != (b.y < 2.5):
			var t3 := (2.5 - a.y) / (b.y - a.y)
			var p := a.lerp(b, t3)
			if not (p.x < -2.5 and p.z < 1.15):
				return true
		return false

	func rock_chair(_s := 6.0) -> void:
		rocks += 1

	func ground_probe(_x: float, _z: float, _from_y := 6.0) -> float:
		return NAN


class FakePuzzles extends Node:
	var stage := "intro"
	var found := {"duck": null, "horse": null, "clock": null, "tv": null}
	var flags := {"rocked": false}
	var ambient_scares := true

	func goto(s: String) -> void:
		var prev := stage
		stage = s
		Events.stage_changed.emit(s, prev)


class FakeGarderie extends Node3D:
	var ambient_scares := true
	var light_scale := 1.0
	var scare_calls := 0

	func scare(_k: String) -> void:
		scare_calls += 1

	func set_light_scale(k: float) -> void:
		light_scale = k


class FakeUI extends Node:
	var modal := false
	var subtitles: Array = []

	func is_modal_open() -> bool:
		return modal

	func subtitle(text: Variant, _s := 3.0, _o := {}) -> void:
		subtitles.append(str(text))
