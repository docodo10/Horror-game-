## Defines the input map at startup (physical keys -> works on AZERTY too). Core owns it.
class_name InputSetup
extends RefCounted

static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new(); e.physical_keycode = code; return e

static func _mouse(btn: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new(); e.button_index = btn; return e

static func _joy(btn: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new(); e.button_index = btn; return e

static func _axis(axis: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new(); e.axis = axis; e.axis_value = v; return e

static func setup() -> void:
	var map := {
		"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"look_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"look_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"sprint": [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_STICK)],
		"crouch": [_key(KEY_C), _key(KEY_CTRL), _joy(JOY_BUTTON_B)],
		"interact": [_key(KEY_E), _mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_A)],
		"flashlight": [_key(KEY_F), _joy(JOY_BUTTON_Y)],
		"pause": [_key(KEY_ESCAPE), _key(KEY_P), _joy(JOY_BUTTON_START)],
		"objective": [_key(KEY_TAB), _joy(JOY_BUTTON_BACK)],
	}
	for action in map:
		if not InputMap.has_action(action): InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for ev in map[action]: InputMap.action_add_event(action, ev)
