## UI module — the keypad IS the brass 4-wheel combination padlock (web .lg-kplayer / .lg-kp): steel shackle, cast brass
## body (shaders/ui_brass.gdshader) with the stamp "LAITON · 4 CHIFFRES", a dark window with the knurled brass drums
## (digits roll smoothly, endless), index markers, chevrons, keyhole; under it the scrap of paper with the clue digits
## found so far, the actions "Essayer" / "Lâcher" and a help line.
## Input: arrows / WASD / D-pad / stick (←→ wheel, ↑↓ turn), digits 0–9 (set + next wheel), Backspace (previous wheel),
## Enter / gamepad A (try), Esc / gamepad B (let go), mouse wheel or drag on a drum, click a drum half or a chevron.
## Emits finished(result) — "" when cancelled. Sounds: lock_wheel per notch.
extends Control

const Style := preload("res://scripts/ui/ui_style.gd")
const BRASS_SHADER := preload("res://shaders/ui_brass.gdshader")
const PAPER_SHADER := preload("res://shaders/ui_paper.gdshader")

signal finished(result: String)

const DRUM_W := 82.0
const DRUM_H := 172.0
const KH := 68.0
const DRUM_GAP := 12.0
const WIN_PAD := 16.0
const BODY_PAD_X := 30.0
const CHEV_H := 44.0
const CLUE_KEYS := [["duck", "canard"], ["horse", "cheval"], ["clock", "horloge"], ["tv", "télé"]]

var ui: Node = null
var is_open := false
var opened_at := 0.0
var title := ""
var n := 4
var digits: Array[int] = [0, 0, 0, 0]
var active := 0
var clues: Dictionary = {}
var pad_mode := false

var _target: Array[float] = []
var _pos: Array[float] = []
var _bg: TextureRect
var _lock: Control
var _shackle: Control
var _body: ColorRect
var _body_mat: ShaderMaterial
var _window: Panel
var _drums: Array[Control] = []
var _over: Control
var _scrap: ColorRect
var _scrap_mat: ShaderMaterial
var _scrap_ink: Control
var _body_size := Vector2.ZERO
var _btn_try := Rect2()
var _btn_cancel := Rect2()
var _hover := ""
var _drag := {}
var _wheel_acc: Array[float] = []
var _anim := 1.0
var _f_btn: Font
var _f_key: Font
var _f_help: Font
var _f_digit: Font
var _f_stamp: Font
var _f_label: Font
var _f_hand: Font
var _f_hand_b: Font
var _box := StyleBoxFlat.new()
var _key_box := StyleBoxFlat.new()

func setup(ui_: Node) -> void:
	ui = ui_
	name = "KeypadView"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_f_btn = Style.spaced("ui_bold", 2.6)
	_f_key = Style.font("ui_bold")
	_f_help = Style.font("ui")
	_f_digit = Style.font("type")
	_f_stamp = Style.spaced("ui_bold", 4.4)
	_f_label = Style.spaced("ui_bold", 3.6)
	_f_hand = Style.font("hand")
	_f_hand_b = Style.font("hand_bold")
	_box.bg_color = Color(0, 0, 0, 0)
	_box.set_border_width_all(2)
	_box.set_corner_radius_all(8)
	_box.anti_aliasing = true
	_key_box.bg_color = Color(0, 0, 0, 0.35)
	_key_box.set_border_width_all(2)
	_key_box.set_corner_radius_all(6)
	_key_box.anti_aliasing = true
	# radial dim (web: rgba(4,3,2,.6) centre -> rgba(0,0,0,.9) edges)
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.016, 0.012, 0.008, 0.6))
	gr.set_color(1, Color(0, 0, 0, 0.9))
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	_bg = TextureRect.new()
	_bg.texture = gt
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	add_child(_bg)
	_lock = Control.new()
	_lock.name = "Lock"
	_lock.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_lock)
	_lock.gui_input.connect(_on_lock_input)
	_shackle = Control.new()
	_shackle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock.add_child(_shackle)
	_shackle.draw.connect(_draw_shackle)
	_body = ColorRect.new()
	_body.color = Color.WHITE
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = BRASS_SHADER
	_body.material = _body_mat
	_lock.add_child(_body)
	_window = Panel.new()
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color("#1a1209")
	wsb.set_corner_radius_all(9)
	wsb.border_color = Color(1.0, 0.925, 0.706, 0.32)
	wsb.border_width_bottom = 2
	wsb.border_color = Color(1.0, 0.925, 0.706, 0.3)
	wsb.shadow_color = Color(0, 0, 0, 0.0)
	wsb.anti_aliasing = true
	_window.add_theme_stylebox_override("panel", wsb)
	_lock.add_child(_window)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock.add_child(_over)
	_over.draw.connect(_draw_over)
	_scrap = ColorRect.new()
	_scrap.color = Color.WHITE
	_scrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrap_mat = ShaderMaterial.new()
	_scrap_mat.shader = PAPER_SHADER
	_scrap_mat.set_shader_parameter("col_a", Color("#ebe1c8"))
	_scrap_mat.set_shader_parameter("col_b", Color("#ddd1b3"))
	_scrap_mat.set_shader_parameter("stain1", Vector4(0.9, 0.3, 0.3, 0.1))
	_scrap_mat.set_shader_parameter("edge_dark", 0.6)
	_scrap.material = _scrap_mat
	add_child(_scrap)
	_scrap_ink = Control.new()
	_scrap_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrap.add_child(_scrap_ink)
	_scrap_ink.draw.connect(_draw_scrap)
	resized.connect(_layout)

func _build_drums(count: int) -> void:
	for d in _drums:
		d.queue_free()
	_drums.clear()
	for i in count:
		var d := Control.new()
		d.name = "Drum%d" % i
		d.clip_contents = true
		d.mouse_filter = Control.MOUSE_FILTER_STOP
		d.mouse_default_cursor_shape = Control.CURSOR_VSIZE
		d.size = Vector2(DRUM_W, DRUM_H)
		_lock.add_child(d)
		d.draw.connect(_draw_drum.bind(i))
		d.gui_input.connect(_on_drum_input.bind(i))
		_drums.append(d)
	_lock.move_child(_over, -1)

# ================================================================ open / close

func open(title_: String, length: int, combo: Array, clues_: Dictionary, pad: bool) -> void:
	title = Style.fr(title_)
	n = clampi(length, 1, 8)
	if _drums.size() != n:
		_build_drums(n)
	digits.clear()
	_target.clear()
	_pos.clear()
	_wheel_acc.clear()
	for i in n:
		var dgt := int(combo[i]) if i < combo.size() else 0
		digits.append(posmod(dgt, 10))
		_target.append(float(digits[i]))
		_pos.append(float(digits[i]))
		_wheel_acc.append(0.0)
	active = 0
	clues = clues_
	pad_mode = pad
	_drag = {}
	_hover = ""
	opened_at = Style.now()
	is_open = true
	visible = true
	modulate.a = 0.0
	_anim = 0.0
	_layout()
	_redraw_all()

func close() -> void:
	if not is_open:
		return
	is_open = false
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ignore_time_scale(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_after_close)

func _after_close() -> void:
	if not is_open:
		visible = false

func set_clues(c: Dictionary) -> void:
	clues = c
	if is_open:
		_layout()
		_scrap_ink.queue_redraw()

func code() -> String:
	var s := ""
	for d in digits:
		s += str(d)
	return s

# ================================================================ layout

func _layout() -> void:
	if _lock == null:
		return
	var win_w := n * DRUM_W + (n - 1) * DRUM_GAP + WIN_PAD * 2.0
	var win_h := DRUM_H + 8.0
	_body_size = Vector2(win_w + BODY_PAD_X * 2.0, CHEV_H + win_h + CHEV_H + 56.0)
	var shackle_h := 128.0
	var lock_size := Vector2(_body_size.x, shackle_h + _body_size.y)
	_lock.size = lock_size
	_shackle.size = lock_size
	_body.position = Vector2(0, shackle_h)
	_body.size = _body_size
	_body_mat.set_shader_parameter("rect_size", _body_size)
	var wx := BODY_PAD_X
	var wy := shackle_h + 24.0 + CHEV_H
	_window.position = Vector2(wx, wy)
	_window.size = Vector2(win_w, win_h)
	for i in _drums.size():
		_drums[i].position = Vector2(wx + WIN_PAD + i * (DRUM_W + DRUM_GAP), wy + 4.0)
		_drums[i].size = Vector2(DRUM_W, DRUM_H)
	_over.size = lock_size
	# scrap
	var scrap_w := _scrap_width()
	_scrap.size = Vector2(scrap_w, 58.0)
	_scrap.pivot_offset = _scrap.size * 0.5
	_scrap.rotation = deg_to_rad(-1.5)
	_scrap_mat.set_shader_parameter("rect_size", _scrap.size)
	_scrap_ink.size = _scrap.size
	_scrap.visible = not clues.is_empty()
	# vertical stack
	var vs := size if size.y > 0.0 else Vector2(1920, 1080)
	var title_h := 40.0 if title != "" else 0.0
	var total := title_h + lock_size.y + 30.0 + (58.0 + 28.0 if _scrap.visible else 0.0) + 56.0 + 18.0 + 26.0
	var top := maxf(16.0, (vs.y - total) * 0.5)
	var k := 1.0 - pow(1.0 - Style.clamp01(_anim), 4.0)
	_lock.position = Vector2(roundf((vs.x - lock_size.x) * 0.5), roundf(top + title_h + (1.0 - k) * 16.0))
	var y := _lock.position.y + lock_size.y + 30.0
	if _scrap.visible:
		_scrap.position = Vector2(roundf((vs.x - scrap_w) * 0.5), y)
		y += 58.0 + 28.0
	var bt := _btn_w("ESSAYER", _key_text(true))
	var bc := _btn_w("LÂCHER", _key_text(false))
	var gap := 36.0
	var x0 := roundf(vs.x * 0.5 - (bt + bc + gap) * 0.5)
	_btn_try = Rect2(x0, y, bt, 56.0)
	_btn_cancel = Rect2(x0 + bt + gap, y, bc, 56.0)

func _scrap_width() -> float:
	var w := 28.0
	for pair in CLUE_KEYS:
		var v: Variant = clues.get(pair[0])
		w += _f_hand.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 6.0
		w += _f_hand_b.get_string_size(str(v) if v != null else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x + 22.0
	return w + 6.0

func _key_text(try_: bool) -> String:
	if pad_mode:
		return "A" if try_ else "B"
	return "ENTRÉE" if try_ else "ÉCHAP"

func _btn_w(label: String, key: String) -> float:
	return 26.0 + _f_btn.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 14.0 + _key_w(key) + 26.0

func _key_w(key: String) -> float:
	if pad_mode:
		return 30.0
	return maxf(30.0, _f_key.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0)

func _redraw_all() -> void:
	queue_redraw()
	_shackle.queue_redraw()
	_over.queue_redraw()
	_scrap_ink.queue_redraw()
	for d in _drums:
		d.queue_redraw()

# ================================================================ per frame

func process_frame(dt: float) -> void:
	if not visible:
		return
	if is_open:
		modulate.a = move_toward(modulate.a, 1.0, dt / 0.3)
		if _anim < 1.0:
			_anim = minf(1.0, _anim + dt / 0.4)
			_layout()
	var k := 1.0 - exp(-dt / 0.055)
	for i in _pos.size():
		if absf(_pos[i] - _target[i]) > 0.001:
			_pos[i] = lerpf(_pos[i], _target[i], k)
			if absf(_pos[i] - _target[i]) < 0.002:
				_pos[i] = _target[i]
			_drums[i].queue_redraw()

# ================================================================ actions

func set_active(i: int) -> void:
	if i == active:
		return
	active = clampi(i, 0, n - 1)
	_over.queue_redraw()
	for d in _drums:
		d.queue_redraw()

func step(i: int, d: int) -> void:
	if i < 0 or i >= n or d == 0:
		return
	digits[i] = posmod(digits[i] + d, 10)
	_target[i] += float(d)
	_drums[i].queue_redraw()
	Audio.play("lock_wheel", {"volume_db": linear_to_db(0.6), "pitch": randf_range(0.96, 1.04)})

## Turns wheel i to digit by the shortest way (web _kpSet).
func set_digit(i: int, digit: int) -> void:
	var cur := digits[i]
	if cur == digit:
		return
	var d := digit - cur
	if d > 5: d -= 10
	if d < -5: d += 10
	var s := 1 if d > 0 else -1
	for k in absi(d):
		step(i, s)

func _try() -> void:
	if Style.now() - opened_at < 0.25:
		return
	finished.emit(code())

func _cancel() -> void:
	finished.emit("")

## Keyboard / gamepad navigation from the UI router. Swallows everything while open.
func nav(action: String, data := "") -> bool:
	if not is_open:
		return false
	match action:
		"back":
			_cancel()
		"accept":
			_try()
		"left":
			set_active((active - 1 + n) % n)
		"right":
			set_active((active + 1) % n)
		"up":
			step(active, 1)
		"down":
			step(active, -1)
		"bksp":
			set_active(maxi(0, active - 1))
		"digit":
			if data.is_valid_int():
				set_digit(active, int(data))
				if active < n - 1:
					set_active(active + 1)
	return true

# ================================================================ mouse

func _gui_input(e: InputEvent) -> void:
	if not is_open:
		return
	if ui and ui.has_method("note_input_device"):
		ui.note_input_device(e)
	if e is InputEventMouseMotion:
		var p := (e as InputEventMouseMotion).position
		var h := "try" if _btn_try.has_point(p) else ("cancel" if _btn_cancel.has_point(p) else "")
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _btn_try.has_point(mb.position):
				_try()
			elif _btn_cancel.has_point(mb.position):
				_cancel()
		accept_event()

## Clicks on the chevrons above / below the drums.
func _on_lock_input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			for i in _drums.size():
				var dr := Rect2(_drums[i].position, _drums[i].size)
				if mb.position.x >= dr.position.x and mb.position.x <= dr.end.x:
					if mb.position.y < dr.position.y and mb.position.y > dr.position.y - CHEV_H - 8.0:
						set_active(i)
						step(i, 1)
					elif mb.position.y > dr.end.y and mb.position.y < dr.end.y + CHEV_H + 8.0:
						set_active(i)
						step(i, -1)
		_lock.accept_event()

func _on_drum_input(e: InputEvent, i: int) -> void:
	if not is_open:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				set_active(i)
				_wheel_acc[i] += (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * maxf(1.0, mb.factor)
				if absf(_wheel_acc[i]) >= 1.0:
					step(i, 1 if _wheel_acc[i] > 0.0 else -1)
					_wheel_acc[i] = 0.0
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				set_active(i)
				_drag = {"i": i, "y": mb.position.y, "start": mb.position.y, "moved": 0.0}
			elif not _drag.is_empty() and int(_drag.i) == i:
				var moved: float = _drag.moved
				_drag = {}
				if moved < 6.0:
					var rel := mb.position.y / DRUM_H
					if rel < 0.36:
						step(i, -1)
					elif rel > 0.64:
						step(i, 1)
		_drums[i].accept_event()
	elif e is InputEventMouseMotion and not _drag.is_empty() and int(_drag.i) == i:
		var mm := e as InputEventMouseMotion
		var stp := maxf(18.0, KH * 0.55)
		var dy: float = float(_drag.y) - mm.position.y
		_drag.moved = maxf(float(_drag.moved), absf(mm.position.y - float(_drag.start)))
		if absf(dy) >= stp:
			var s := int(dy / stp)
			_drag.y = float(_drag.y) - s * stp
			for k in absi(s):
				step(i, 1 if s > 0 else -1)
		_drums[i].accept_event()

# ================================================================ drawing

func _draw() -> void:
	if not visible:
		return
	if title != "":
		var t := title.to_upper()
		var tw := _f_label.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(_f_label, Vector2(roundf(size.x * 0.5 - tw * 0.5), _lock.position.y - 18.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Style.WHITE, 0.5))
	_draw_button(_btn_try, "ESSAYER", _key_text(true), true, _hover == "try")
	_draw_button(_btn_cancel, "LÂCHER", _key_text(false), false, _hover == "cancel")
	var help := "Croix ou stick : tourner. A pour essayer, B pour lâcher." if pad_mode else "Flèches, molette ou clic pour tourner. Tape les chiffres 0 à 9."
	var hw := _f_help.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(_f_help, Vector2(roundf(size.x * 0.5 - hw * 0.5), _btn_try.end.y + 34.0), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(Style.WHITE, 0.5))

func _draw_button(r: Rect2, label: String, key: String, primary: bool, hover: bool) -> void:
	var op := 1.0 if hover or primary else 0.72
	if primary or hover:
		_box.border_color = Color(Style.NIGHTLIGHT, 0.95 if hover else 0.7)
		draw_style_box(_box, r)
	var cy := r.position.y + r.size.y * 0.5
	var x := r.position.x + 26.0
	draw_string(_f_btn, Vector2(x, cy + 7.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(Style.WHITE, op))
	x += _f_btn.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 14.0
	var kw := _key_w(key)
	if pad_mode:
		var c := Vector2(x + 15.0, cy)
		draw_circle(c, 15.0, Color(0, 0, 0, 0.4 * op))
		draw_arc(c, 14.0, 0.0, TAU, 40, Color(0.937, 0.925, 0.894, 0.75 * op), 2.0, true)
	else:
		_key_box.border_color = Color(0.937, 0.925, 0.894, 0.7 * op)
		draw_style_box(_key_box, Rect2(x, cy - 15.0, kw, 30.0))
	var ks := _f_key.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(_f_key, Vector2(x + kw * 0.5 - ks.x * 0.5, cy + 5.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Style.WHITE, op))

func _draw_shackle() -> void:
	# steel U-shackle: legs go into the body (drawn behind it)
	var w := _body_size.x * 0.6
	var cx := _body_size.x * 0.5
	var r := w * 0.5 - 12.0
	var top := 18.0
	var cy := top + r
	var leg_bottom := 128.0 + 30.0
	var layers := [[30.0, Color("#5f5a51")], [24.0, Color("#8d877b")], [16.0, Color("#a7a196")], [7.0, Color("#cfc9bb")], [2.5, Color("#ece7dc")]]
	for L in layers:
		var lw: float = L[0]
		var col: Color = L[1]
		var off := 0.0 if lw > 20.0 else -(24.0 - lw) * 0.18
		_shackle.draw_arc(Vector2(cx, cy), r + off, PI, TAU, 48, col, lw, true)
		_shackle.draw_line(Vector2(cx - r - off, cy), Vector2(cx - r - off, leg_bottom), col, lw, true)
		_shackle.draw_line(Vector2(cx + r + off, cy), Vector2(cx + r + off, leg_bottom), col, lw, true)

func _draw_drum(i: int) -> void:
	var d: Control = _drums[i]
	var w := DRUM_W
	var h := DRUM_H
	# brass drum body (cylinder shading), knurl lines, digits, then occlusion gradient
	var bands := 24
	for b in bands:
		var y0 := h * b / bands
		var t := (b + 0.5) / bands
		var lum := sin(t * PI)
		var col := Color("#2e2010").lerp(Color("#f0d690"), pow(lum, 0.8))
		d.draw_rect(Rect2(0, y0, w, h / bands + 1.0), col)
	for x in range(2, int(w), 4):
		d.draw_line(Vector2(x, 0), Vector2(x, h), Color(0, 0, 0, 0.07), 1.0)
	var p := _pos[i]
	var base := floori(p)
	var frac := p - base
	for k in range(-3, 4):
		var idx := base + k
		var digit := posmod(idx, 10)
		var cy := h * 0.5 + (float(k) - frac) * KH
		var ds := str(digit)
		var sz := _f_digit.get_string_size(ds, HORIZONTAL_ALIGNMENT_LEFT, -1, 44)
		var bp := Vector2(w * 0.5 - sz.x * 0.5, cy + 15.0)
		var fade := 1.0 - Style.clamp01(absf(cy - h * 0.5) / (h * 0.62))
		d.draw_string(_f_digit, bp + Vector2(0, 1.5), ds, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1.0, 0.93, 0.72, 0.55 * fade))
		d.draw_string(_f_digit, bp, ds, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(Color("#2a1b07"), 0.35 + 0.65 * fade))
	# cylinder occlusion top / bottom
	var steps := 16
	for s in steps:
		var t2 := float(s) / steps
		var a := pow(1.0 - t2, 2.0) * 0.78
		var hh := h * 0.32 / steps
		d.draw_rect(Rect2(0, t2 * h * 0.32, w, hh + 0.5), Color(0, 0, 0, a))
		d.draw_rect(Rect2(0, h - (t2 * h * 0.32) - hh, w, hh + 0.5), Color(0, 0, 0, a))
	# specular line
	d.draw_rect(Rect2(0, h * 0.44, w, 2.0), Color(1.0, 0.97, 0.85, 0.12))

func _draw_over() -> void:
	var o := _over
	var shackle_h := 128.0
	# stamp
	var stamp := "LAITON · %d CHIFFRES" % n
	var sw := _f_stamp.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var sp := Vector2(roundf(_body_size.x * 0.5 - sw * 0.5), shackle_h + 26.0)
	o.draw_string(_f_stamp, sp + Vector2(0, 1), stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.925, 0.706, 0.35))
	o.draw_string(_f_stamp, sp, stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.196, 0.125, 0.031, 0.62))
	# chevrons + active outline
	for i in _drums.size():
		var dr := Rect2(_drums[i].position, _drums[i].size)
		var act := i == active
		var col := Color(0.953, 0.902, 0.761, 0.95 if act else 0.5)
		var cx := dr.position.x + dr.size.x * 0.5
		var ty := dr.position.y - CHEV_H * 0.5 - 4.0
		var by := dr.end.y + CHEV_H * 0.5 + 4.0
		o.draw_polyline(PackedVector2Array([Vector2(cx - 10, ty + 5), Vector2(cx, ty - 5), Vector2(cx + 10, ty + 5)]), Color(0, 0, 0, 0.35), 4.0, true)
		o.draw_polyline(PackedVector2Array([Vector2(cx - 10, ty + 5), Vector2(cx, ty - 5), Vector2(cx + 10, ty + 5)]), col, 2.2, true)
		o.draw_polyline(PackedVector2Array([Vector2(cx - 10, by - 5), Vector2(cx, by + 5), Vector2(cx + 10, by - 5)]), Color(0, 0, 0, 0.35), 4.0, true)
		o.draw_polyline(PackedVector2Array([Vector2(cx - 10, by - 5), Vector2(cx, by + 5), Vector2(cx + 10, by - 5)]), col, 2.2, true)
		if act:
			var gr := dr.grow(2.0)
			for g in 3:
				o.draw_rect(gr.grow(float(g) * 2.5), Color(Style.NIGHTLIGHT, 0.18 - g * 0.05), false, 2.0)
			o.draw_rect(gr, Style.NIGHTLIGHT, false, 2.0)
	# index markers left / right of the window, on the reading line
	var win := Rect2(_window.position, _window.size)
	var my := win.position.y + win.size.y * 0.5
	o.draw_colored_polygon(PackedVector2Array([Vector2(win.position.x - 1, my - 7), Vector2(win.position.x + 9, my), Vector2(win.position.x - 1, my + 7)]), Style.NIGHTLIGHT)
	o.draw_colored_polygon(PackedVector2Array([Vector2(win.end.x + 1, my - 7), Vector2(win.end.x - 9, my), Vector2(win.end.x + 1, my + 7)]), Style.NIGHTLIGHT)
	# keyhole
	var kc := Vector2(_body_size.x * 0.5, shackle_h + _body_size.y - 20.0)
	o.draw_set_transform(kc, 0.0, Vector2(1.0, 0.45))
	o.draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.925, 0.706, 0.35))
	o.draw_circle(Vector2(0, -1.5), 11.0, Color("#2a1a06"))
	o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_scrap() -> void:
	var c := _scrap_ink
	var x := 16.0
	var y := 40.0
	var ink := Color("#2a2a48")
	for pair in CLUE_KEYS:
		var v: Variant = clues.get(pair[0])
		var known := v != null
		var a := 1.0 if known else 0.4
		var lab: String = pair[1]
		c.draw_string(_f_hand, Vector2(x, y), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.7 * a))
		x += _f_hand.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 6.0
		var vs := str(v) if known else "?"
		c.draw_string(_f_hand_b, Vector2(x, y + 1.0), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(ink, a))
		x += _f_hand_b.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x + 22.0
