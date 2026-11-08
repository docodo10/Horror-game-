## UI module — full-screen CRT layer (web .lg-crt): a 4:3 tube centred on a black backdrop (62 % black over the frozen
## room for the pause page) showing the 40 × 16 teletext pages (loading, pause, notes, options, controls, quit, caught,
## game over, win) through shaders/ui_crt_screen.gdshader. Mouse: hover selects, click activates (◄ ► halves of value
## fields), wheel moves. Keyboard / gamepad go through the UI input router (nav()).
extends Control

const Style := preload("res://scripts/ui/ui_style.gd")
const TT := preload("res://scripts/ui/teletext.gd")
const SCREEN_SHADER := preload("res://shaders/ui_crt_screen.gdshader")

var ui: Node = null
var screen: TT = null
var mode := ""                    # loading | pause | end
var is_open := false
var _bg: ColorRect
var _tube: ColorRect
var _mat: ShaderMaterial
var _tween: Tween
var _time := 0.0
var _wheel := 0.0
var _down := Vector2(-1, -1)

func setup(ui_: Node) -> void:
	ui = ui_
	name = "CrtOverlay"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_bg = ColorRect.new()
	_bg.name = "Backdrop"
	_bg.color = Color.BLACK
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	screen = TT.create(self, 40, 16, 15, 28, 20, 16, ui_, "CrtTeletext")
	_tube = ColorRect.new()
	_tube.name = "Tube"
	_tube.color = Color.WHITE
	_tube.mouse_filter = Control.MOUSE_FILTER_STOP
	_mat = ShaderMaterial.new()
	_mat.shader = SCREEN_SHADER
	_mat.set_shader_parameter("page", screen.get_texture())
	_mat.set_shader_parameter("tex_size", Vector2(screen.W, screen.H))
	_tube.material = _mat
	add_child(_tube)
	_tube.gui_input.connect(_on_tube_input)
	_tube.mouse_exited.connect(func() -> void: _tube.mouse_default_cursor_shape = Control.CURSOR_ARROW)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if _tube == null:
		return
	var vs := size
	var w := minf(vs.x - 10.0, (vs.y - 10.0) * 4.0 / 3.0)
	var h := w * 3.0 / 4.0
	_tube.position = ((vs - Vector2(w, h)) * 0.5).round()
	_tube.size = Vector2(w, h).round()

## mode: loading | pause | end
func open(mode_: String, burst := 0.0) -> void:
	mode = mode_
	var mix := mode == "pause"
	screen.mix = mix
	screen.home = "pause" if mix else ""
	screen.locked = false
	screen.allow_e = mode == "end"
	screen.burst = burst
	screen.burst_max = maxf(0.05, burst)
	screen.dirty = true
	_bg.color = Color(0, 0, 0, 0.62) if mix else Color.BLACK
	_mat.set_shader_parameter("mix_mode", 1.0 if mix else 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if mode == "loading" else Control.MOUSE_FILTER_STOP
	_tube.mouse_filter = Control.MOUSE_FILTER_IGNORE if mode == "loading" else Control.MOUSE_FILTER_STOP
	screen.set_active(true)
	_layout()
	if not is_open:
		is_open = true
		visible = true
		modulate.a = 0.0
		_fade(1.0, 0.3)

func close(delay := 0.32) -> void:
	if not is_open:
		return
	is_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade(0.0, delay)

func _fade(to: float, secs: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(self, "modulate:a", to, maxf(0.01, secs))
	if to <= 0.0:
		_tween.tween_callback(_hidden)

func _hidden() -> void:
	if not is_open:
		visible = false
		screen.set_active(false)

func process_frame(dt: float) -> void:
	if not visible:
		return
	_time += dt
	screen.tick(dt)
	_mat.set_shader_parameter("u_time", _time)
	_mat.set_shader_parameter("burst", screen.burst_amount())
	_mat.set_shader_parameter("flick", screen.flick)

## Page coordinates (0..1, v down) under a point in tube-local pixels (same barrel mapping as the shader).
func _page_uv(local: Vector2) -> Vector2:
	var uv := local / _tube.size
	var c := uv * 2.0 - Vector2.ONE
	c *= 1.0 + 0.03 * c.dot(c)
	return c * 0.5 + Vector2(0.5, 0.5)

func _hit(local: Vector2) -> Dictionary:
	var p := _page_uv(local)
	if p.x < 0.0 or p.x > 1.0 or p.y < 0.0 or p.y > 1.0:
		return {}
	return screen.hit(p.x, p.y)

func _on_tube_input(e: InputEvent) -> void:
	if not is_open or mode == "loading":
		return
	if ui and ui.has_method("note_input_device"):
		ui.note_input_device(e)
	if mode == "end" and ui and not ui.end_ready():
		return
	if e is InputEventMouseMotion:
		var hit := _hit((e as InputEventMouseMotion).position)
		_tube.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not hit.is_empty() else Control.CURSOR_ARROW
		if not hit.is_empty() and not screen.locked:
			screen.select(hit.it.id)
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_wheel += (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * maxf(1.0, mb.factor)
				if absf(_wheel) >= 1.0:
					screen.move(1 if _wheel > 0.0 else -1)
					_wheel = 0.0
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_down = mb.position
			elif _down.x >= 0.0:
				var moved := mb.position.distance_to(_down)
				_down = Vector2(-1, -1)
				if moved <= 14.0:
					var hit := _hit(mb.position)
					if not hit.is_empty() and not screen.locked:
						screen.select(hit.it.id, false)
						screen.activate(int(hit.side))
			accept_event()
