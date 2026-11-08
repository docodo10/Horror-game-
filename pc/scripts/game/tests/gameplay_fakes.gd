## Test doubles for the gameplay SceneTree test (gameplay_test_driver.gd). They implement the public API of the other modules
## (world / ui / player / entity) just enough to play the whole scenario; nothing here is used by the game itself.
extends RefCounted

const LAYER_WORLD := 1
const LAYER_INTERACT := 2

## World double: same public members as scripts/world/world.gd (handles, items, clues, tv, hide_spots, power, lighting...).
class FakeWorld extends Node3D:
	var power := true
	var handles := {}
	var items := {}
	var clues := {}
	var tv: Node = null
	var hide_spots: Array = []
	var lighting: Node = null
	var nav := AStar3D.new()
	var rock_calls := 0
	var digits := {}
	var power_log: Array = []

	func set_power(on: bool) -> void:
		power = on
		power_log.append(on)
		var lv = handles.get("powerBox.lever")
		if lv != null and lv.get("is_on") != null and lv.is_on != on:   # the breaker follows the power silently
			lv.is_on = on
			lv.is_open = on
			lv.node.transform = lv.open_xform if on else lv.closed_xform
		if lighting != null: lighting.set_power(on)
		Events.power_changed.emit(on)

	func set_clue_digits(d: Dictionary) -> void: digits = d
	func rock_chair(_seconds := 6.0) -> void: rock_calls += 1
	func ground_height_at(x: float, z: float, prev_y := NAN) -> float: return Layout.ground_height_at(x, z, prev_y)
	func line_blocked(from: Vector3, to: Vector3) -> bool:
		var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
		return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	func reset_after_caught() -> void: pass

class FakeLighting extends Node3D:
	var flickers := 0
	var blowouts := 0
	func build(_w: Node) -> void: pass
	func set_power(_on: bool) -> void: pass
	func blowout() -> void: blowouts += 1
	func flicker(_d := 0.6, _depth := 1.0) -> void: flickers += 1
	func set_stress(_v: float) -> void: pass
	func set_tv_light(_on: bool, _i := 1.0) -> void: pass

## Power box lever: a Handle that also has is_on / set_on(on) (web Props: plays breaker_flip, drives world.set_power).
class FakeLever extends Handle:
	var is_on := true
	var world: Node = null
	var set_on_calls := 0
	func set_on(on: bool) -> void:
		set_on_calls += 1
		if is_on == on: return
		is_on = on
		Audio.play("breaker_flip", {"position": world_position()})
		if on: await open()
		else: await close()
		if world != null and world.power != on: world.set_power(on)

class FakeTV extends Node3D:
	var is_on := false
	var screen_position := Vector3.ZERO
	var digit := ""
	var world: Node = null
	func set_on(on: bool) -> bool:
		if on and world != null and not world.power: return false
		is_on = on
		return true
	func set_digit(d: String) -> void: digit = d

## UI double: records what gameplay shows; the keypad answers from `keypad_answers` (the test sets the code).
class FakeUI extends CanvasLayer:
	var menu_camera_active := false
	var prompt_text := ""
	var prompt_opts := {}
	var prompts_seen := {}
	var subtitles: Array[String] = []
	var objectives: Array[String] = []
	var alerts: Array[String] = []
	var notes_shown: Array = []
	var clues := {}
	var night := 1
	var keypad_answers: Array[String] = []
	var keypad_titles: Array[String] = []
	var inventory_updates := 0
	var fades: Array = []
	var _modal := false

	func show_loading(_p: float, _t: String) -> void: pass
	func show_menu() -> void: pass
	func hide_menu() -> void: pass
	func show_pause() -> void: await get_tree().process_frame
	func hide_pause() -> void: pass
	func show_caught(_n: int, _t: int) -> void: await get_tree().process_frame
	func show_game_over() -> void: await get_tree().process_frame
	func show_win(_t: float, _n: int, _tot: int) -> void: await get_tree().process_frame
	func fade_to(a: float, s: float) -> void:
		fades.append([a, s])
		await get_tree().process_frame
	func set_prompt(t: String, o := {}) -> void:
		prompt_text = t
		prompt_opts = o
		if t != "": prompts_seen[t] = o.duplicate()
	func subtitle(t: String, _s := 3.5, _o := {}) -> void: subtitles.append(t)
	func set_objective(t: String) -> void: objectives.append(t)
	func alert(t: String, _s := 2.0) -> void: alerts.append(t)
	func set_battery(_v: float) -> void: pass
	func set_stamina(_v: float) -> void: pass
	func set_night(n: int, _t: int) -> void: night = n
	func set_clues(d: Dictionary) -> void: clues = d
	func set_inventory(_items: Array, _notes: Array) -> void: inventory_updates += 1
	func show_note(n: Dictionary) -> void:
		_modal = true
		notes_shown.append(n)
		for i in 6: await get_tree().process_frame
		_modal = false
	func show_keypad(t: String, _l := 4) -> String:
		_modal = true
		keypad_titles.append(t)
		for i in 6: await get_tree().process_frame
		_modal = false
		return keypad_answers.pop_front() if not keypad_answers.is_empty() else ""
	func set_hidden(_on: bool) -> void: pass
	func is_modal_open() -> bool: return _modal
	func update_menu_camera(_d: float) -> void: pass
	func last_subtitle() -> String: return subtitles.back() if not subtitles.is_empty() else ""
	func said(fragment: String) -> bool:
		for s in subtitles:
			if s.contains(fragment): return true
		return false

## Player double: a camera rig the test aims directly (aim(eye, target)), hide spots, flashlight dictionary.
class FakePlayer extends Node3D:
	var camera := Camera3D.new()
	var yaw := 0.0
	var pitch := 0.0
	var enabled := true
	var camera_override := false
	var hidden := false
	var hide_spot = null
	var crouched := false
	var sprinting := false
	var stamina := 1.0
	var flashlight := {"has": false, "on": false, "battery": 100.0}
	var hide_calls := 0

	func _ready() -> void:
		camera.position = Vector3(0.0, 1.62, 0.0)
		add_child(camera)
		camera.current = true

	func aim(eye: Vector3, target: Vector3) -> void:
		global_position = eye - Vector3(0.0, 1.62, 0.0)
		camera.look_at(target, Vector3.UP)

	func give_flashlight() -> void: flashlight["has"] = true
	func set_flashlight_on(on: bool) -> void: flashlight["on"] = on and flashlight["has"]
	func add_battery(a := 60.0) -> void: flashlight["battery"] = minf(100.0, flashlight["battery"] + a)
	func enter_hide(spot) -> void:
		hide_calls += 1
		for i in 12: await get_tree().process_frame
		hidden = true
		hide_spot = spot
		Events.player_hide.emit(true, str(spot.get("id", "")))
	func exit_hide() -> void:
		for i in 12: await get_tree().process_frame
		hidden = false
		hide_spot = null
		Events.player_hide.emit(false, "")
	func respawn() -> void: teleport(Vector3(Layout.SPAWN.x, 0.0, Layout.SPAWN.z), Layout.SPAWN.yaw)
	func teleport(p: Vector3, y: float, pt := 0.0) -> void:
		global_position = p
		yaw = y
		pitch = pt
	func get_visibility() -> float: return 0.0 if hidden else 0.6
	func eye_position() -> Vector3: return camera.global_position
	func flinch(_s := 1.0) -> void: pass
	func reset_after_caught() -> void: respawn()

## Entity double: summon() = a visit of `visit_time` seconds (active), then back to dormant.
class FakeEntity extends Node3D:
	var state := "dormant"
	var fear := 0.0
	var active := false
	var root := Node3D.new()
	var aggression := 0
	var summons: Array = []
	var visit_time := 3.0
	var _t := 0.0
	func _ready() -> void: add_child(root)
	func build() -> void: pass
	func summon(target: Vector3, reason := "") -> void:
		summons.append([target, reason])
		_set_state("descending")
		_t = visit_time
	func set_aggression(l: int) -> void: aggression = l
	func set_enabled(_on: bool) -> void: pass
	func reset_after_caught() -> void: _set_state("dormant")
	func _process(delta: float) -> void:
		if active:
			_t -= delta
			if _t <= 0.0: _set_state("dormant")
	func _set_state(s: String) -> void:
		var prev := state
		state = s
		active = not (s == "dormant" or s == "disabled")
		Events.entity_state.emit(s, prev)
