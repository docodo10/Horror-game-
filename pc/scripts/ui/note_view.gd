## UI module — paper note reader (web .lg-notelayer / .lg-note): the note stays physical paper over a darkened screen.
## Styles: "note" (school paper: blue rules, red margin, Caveat ink), "child" (crayon words in random colours / angles,
## a little sun, wax tooth shader), "newspaper" (masthead + date + headline + two justified columns with a drop cap,
## torn bottom edge — masthead/date/headline are parsed from the text when not given). Long notes first shrink a little,
## then scroll (wheel, arrows, PgUp/PgDn, D-pad). Close: E / Enter / Space / Esc, gamepad A / B, click outside or on
## "Fermer". The paper is a ColorRect with shaders/ui_paper.gdshader; the ink is replayed from layout ops.
extends Control

const Style := preload("res://scripts/ui/ui_style.gd")
const PAPER_SHADER := preload("res://shaders/ui_paper.gdshader")
const CRAYON_SHADER := preload("res://shaders/ui_crayon.gdshader")

signal close_requested

const INK_NOTE := Color("#1d2746")
const INK_NEWS := Color("#1b1712")
const CRAYONS := [Color("#c2412d"), Color("#2c58a8"), Color("#3d8a3a"), Color("#7a3fa0"), Color("#d9792a"), Color("#1f1a16")]

var ui: Node = null
var is_open := false
var opened_at := 0.0
var key_label := "E"
var pad_mode := false
var note: Dictionary = {}

var _bg: ColorRect
var _holder: Control
var _shadow: Panel
var _paper: ColorRect
var _paper_mat: ShaderMaterial
var _ink: Control
var _ink_mat: ShaderMaterial
var _style := "note"
var _title := ""
var _ops: Array[Dictionary] = []
var _paper_size := Vector2(860, 400)
var _content_h := 0.0
var _scroll := 0.0
var _scroll_target := 0.0
var _max_scroll := 0.0
var _rot := 0.0
var _rule_base := 0.0
var _anim := 1.0
var _hover_btn := false
var _btn_rect := Rect2()
var _f_label: Font
var _f_btn: Font
var _f_key: Font
var _key_box := StyleBoxFlat.new()
var _btn_box := StyleBoxFlat.new()

func setup(ui_: Node) -> void:
	ui = ui_
	name = "NoteView"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_f_label = Style.spaced("ui_bold", 3.6)
	_f_btn = Style.spaced("ui_bold", 2.6)
	_f_key = Style.font("ui_bold")
	_key_box.bg_color = Color(0, 0, 0, 0.35)
	_key_box.border_color = Color(0.937, 0.925, 0.894, 0.7)
	_key_box.set_border_width_all(2)
	_key_box.set_corner_radius_all(6)
	_key_box.anti_aliasing = true
	_btn_box.bg_color = Color(0, 0, 0, 0)
	_btn_box.border_color = Style.NIGHTLIGHT
	_btn_box.set_border_width_all(2)
	_btn_box.set_corner_radius_all(8)
	_btn_box.anti_aliasing = true
	_bg = ColorRect.new()
	_bg.color = Color(0.016, 0.012, 0.008, 0.82)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.show_behind_parent = true
	add_child(_bg)
	_holder = Control.new()
	_holder.name = "Holder"
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_shadow = Panel.new()
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.0)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 42
	sb.shadow_offset = Vector2(0, 30)
	_shadow.add_theme_stylebox_override("panel", sb)
	_holder.add_child(_shadow)
	_paper = ColorRect.new()
	_paper.name = "Paper"
	_paper.color = Color.WHITE
	_paper.clip_contents = true
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper_mat = ShaderMaterial.new()
	_paper_mat.shader = PAPER_SHADER
	_paper.material = _paper_mat
	_holder.add_child(_paper)
	_ink = Control.new()
	_ink.name = "Ink"
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink_mat = ShaderMaterial.new()
	_ink_mat.shader = CRAYON_SHADER
	_paper.add_child(_ink)
	_ink.draw.connect(_draw_ink)
	resized.connect(_place)

# ================================================================ open / close

func open(n: Dictionary, key_label_: String, pad: bool) -> void:
	note = n
	key_label = key_label_
	pad_mode = pad
	var st := str(n.get("style", "note"))
	_style = st if st == "child" or st == "newspaper" else "note"
	_title = Style.fr(str(n.get("title", "")))
	var text := str(n.get("text", ""))
	var max_h := maxf(240.0, (size.y if size.y > 0.0 else 1080.0) - 40.0 - 60.0 - 100.0)
	match _style:
		"child": _layout_child(text, max_h)
		"newspaper": _layout_newspaper(n, text)
		_: _layout_note(text, max_h)
	_paper_size.y = minf(_content_h, max_h)
	_max_scroll = maxf(0.0, _content_h - _paper_size.y)
	_scroll = 0.0
	_scroll_target = 0.0
	_paper.size = _paper_size
	_shadow.size = _paper_size - Vector2(0.0, 34.0 if _style == "newspaper" else 0.0)
	_holder.size = _paper_size
	_holder.pivot_offset = _paper_size * 0.5
	_ink.position = Vector2.ZERO
	_ink.size = Vector2(_paper_size.x, maxf(_content_h, _paper_size.y))
	_ink.material = _ink_mat if _style == "child" else null
	_ink_mat.set_shader_parameter("seed", float(hash(text) % 1000) * 0.01)
	_paper_mat.set_shader_parameter("rect_size", _paper_size)
	_paper_mat.set_shader_parameter("seed", float(hash(text) % 997) * 0.37)
	opened_at = Style.now()
	_anim = 0.0
	is_open = true
	visible = true
	modulate.a = 0.0
	_place()
	_ink.queue_redraw()
	queue_redraw()

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

func _place() -> void:
	if _holder == null:
		return
	var vs := size
	var label_h := 0.0 if _title == "" or _style == "newspaper" else 46.0
	var total := label_h + _paper_size.y + 30.0 + 56.0
	var top := maxf(20.0, (vs.y - total) * 0.5)
	var k := _ease(_anim)
	_holder.position = Vector2(roundf((vs.x - _paper_size.x) * 0.5), roundf(top + label_h + (1.0 - k) * 18.0))
	_holder.rotation = deg_to_rad(_rot + (1.0 - k) * -3.0)
	_holder.scale = Vector2.ONE * lerpf(0.97, 1.0, k)
	var by := top + label_h + _paper_size.y + 30.0
	var bw := _btn_width()
	_btn_rect = Rect2(roundf(vs.x * 0.5 - bw * 0.5), roundf(by), bw, 56.0)

func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - Style.clamp01(x), 4.0)

func process_frame(dt: float) -> void:
	if not visible:
		return
	if is_open:
		modulate.a = move_toward(modulate.a, 1.0, dt / 0.3)
		if _anim < 1.0:
			_anim = minf(1.0, _anim + dt / 0.45)
			_place()
	var prev := _scroll
	_scroll = lerpf(_scroll, _scroll_target, 1.0 - exp(-dt * 14.0))
	if absf(_scroll - _scroll_target) < 0.3:
		_scroll = _scroll_target
	if _scroll != prev:
		_ink.position.y = -roundf(_scroll)
		if _style == "note":
			_paper_mat.set_shader_parameter("rule_offset", _rule_base - roundf(_scroll))
	queue_redraw()

func scroll_by(px: float) -> void:
	_scroll_target = clampf(_scroll_target + px, 0.0, _max_scroll)

## Keyboard / gamepad navigation from the UI router. Swallows everything while open.
func nav(action: String, _data := "") -> bool:
	if not is_open:
		return false
	match action:
		"back", "pause":
			if Style.now() - opened_at >= 0.25:
				close_requested.emit()
		"accept", "e":
			if Style.now() - opened_at >= 0.25:
				close_requested.emit()
		"up":
			scroll_by(-48.0)
		"down":
			scroll_by(48.0)
		"pgup":
			scroll_by(-_paper_size.y * 0.8)
		"pgdn":
			scroll_by(_paper_size.y * 0.8)
	return true

func _gui_input(e: InputEvent) -> void:
	if not is_open:
		return
	if ui and ui.has_method("note_input_device"):
		ui.note_input_device(e)
	if e is InputEventMouseMotion:
		var h := _btn_rect.has_point((e as InputEventMouseMotion).position)
		if h != _hover_btn:
			_hover_btn = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			scroll_by(-60.0 * maxf(1.0, mb.factor))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			scroll_by(60.0 * maxf(1.0, mb.factor))
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if Style.now() - opened_at < 0.38:
				return
			var paper_rect := Rect2(_holder.position, _paper_size)
			if _btn_rect.has_point(mb.position) or not paper_rect.has_point(mb.position):
				close_requested.emit()
		accept_event()

# ================================================================ chrome (title + close button)

func _btn_width() -> float:
	var tw := _f_btn.get_string_size("FERMER", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	return 28.0 + tw + 14.0 + _key_w() + 28.0

func _key_w() -> float:
	return maxf(30.0, _f_key.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0)

func _draw() -> void:
	if not visible:
		return
	var a := _ease(_anim)
	if _title != "" and _style != "newspaper":
		var t := _title.to_upper()
		var tw := _f_label.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(_f_label, Vector2(roundf(size.x * 0.5 - tw * 0.5), _holder.position.y - 24.0 - (1.0 - a) * 18.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Style.WHITE, 0.5))
	# close button: FERMER [E]
	var r := _btn_rect
	var op := 1.0 if _hover_btn else 0.78
	_btn_box.border_color = Color(Style.NIGHTLIGHT, 0.9 if _hover_btn else 0.55)
	draw_style_box(_btn_box, r)
	var tw2 := _f_btn.get_string_size("FERMER", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var x := r.position.x + 28.0
	var cy := r.position.y + r.size.y * 0.5
	draw_string(_f_btn, Vector2(x, cy + 7.0), "FERMER", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(Style.WHITE, op))
	x += tw2 + 14.0
	_draw_key(Vector2(x, cy - 15.0), key_label, pad_mode, op)

func _draw_key(pos: Vector2, label: String, round_: bool, op: float) -> void:
	var kw := _key_w()
	if round_:
		var c := pos + Vector2(15.0, 15.0)
		draw_circle(c, 15.0, Color(0, 0, 0, 0.4 * op))
		draw_arc(c, 14.0, 0.0, TAU, 40, Color(0.937, 0.925, 0.894, 0.75 * op), 2.0, true)
		kw = 30.0
	else:
		_key_box.border_color = Color(0.937, 0.925, 0.894, 0.7 * op)
		draw_style_box(_key_box, Rect2(pos, Vector2(kw, 30.0)))
	var s := _f_key.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(_f_key, Vector2(pos.x + kw * 0.5 - s.x * 0.5, pos.y + 20.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Style.WHITE, op))

# ================================================================ ink

func _draw_ink() -> void:
	for op in _ops:
		match String(op.k):
			"s":
				if op.has("xf"):
					_ink.draw_set_transform_matrix(op.xf)
					_ink.draw_string(op.f, Vector2.ZERO, op.t, HORIZONTAL_ALIGNMENT_LEFT, -1, op.fs, op.c)
					_ink.draw_set_transform_matrix(Transform2D.IDENTITY)
				else:
					_ink.draw_string(op.f, op.p, op.t, HORIZONTAL_ALIGNMENT_LEFT, -1, op.fs, op.c)
			"r":
				_ink.draw_rect(op.r, op.c)
			"l":
				_ink.draw_line(op.a, op.b, op.c, op.w, true)
			"sun":
				_draw_sun(op.p, op.s)

func _draw_sun(c: Vector2, s: float) -> void:
	var k := s / 60.0
	var stroke := Color("#e0a82e")
	for i in 8:
		var ang := i * TAU / 8.0
		var d := Vector2(cos(ang), sin(ang))
		_ink.draw_line(c + d * 17.0 * k, c + d * 25.0 * k, stroke, 3.0 * k, true)
	_ink.draw_circle(c, 10.0 * k, Color("#f1c84b"))
	_ink.draw_arc(c, 10.0 * k, 0.0, TAU, 32, stroke, 3.0 * k, true)

func _op_text(f: Font, p: Vector2, t: String, fs: int, c: Color) -> void:
	_ops.append({"k": "s", "f": f, "p": p.round(), "t": t, "fs": fs, "c": c})

# ---------------------------------------------------------------- note (school paper)

func _layout_note(text: String, max_h: float) -> void:
	_ops.clear()
	var w := 860.0
	var f := Style.font("hand")
	var fs := 42
	var lh := 65.0
	var pad_t := 40.0
	var lines := PackedStringArray()
	for sc in [1.0, 0.92, 0.85, 0.78]:
		fs = roundi(42.0 * sc)
		lh = roundf(fs * 1.55)
		pad_t = roundf(lh * 0.62)
		lines = PackedStringArray()
		for raw in text.split("\n"):
			var l := raw.strip_edges()
			if l == "":
				lines.append("")
			else:
				lines.append_array(Style.wrap_px(f, fs, l, w - 104.0 - 52.0))
		_content_h = pad_t * 2.0 + lines.size() * lh
		if _content_h <= max_h:
			break
	for i in lines.size():
		if lines[i] != "":
			_op_text(f, Vector2(104.0, pad_t + i * lh + lh * 0.7), lines[i], fs, Color(INK_NOTE, 0.93))
	_paper_size = Vector2(w, _content_h)
	_rot = -1.1
	_paper_mat.set_shader_parameter("col_a", Color("#efe6cf"))
	_paper_mat.set_shader_parameter("col_b", Color("#dccfae"))
	_paper_mat.set_shader_parameter("rule_spacing", lh)
	_rule_base = pad_t - 1.0
	_paper_mat.set_shader_parameter("rule_offset", pad_t - 1.0)
	_paper_mat.set_shader_parameter("margin_x", 76.0)
	_paper_mat.set_shader_parameter("stain1", Vector4(0.88, 0.14, 0.18, 0.18))
	_paper_mat.set_shader_parameter("stain2", Vector4(0.08, 0.92, 0.09, 0.08))
	_paper_mat.set_shader_parameter("torn", 0.0)
	_paper_mat.set_shader_parameter("grain", 1.0)

# ---------------------------------------------------------------- child drawing (crayons)

func _layout_child(text: String, max_h: float) -> void:
	var w := 900.0
	var f := Style.font("hand_bold")
	var pad_x := 56.0
	var pad_y := 46.0
	for sc in [1.0, 0.92, 0.85, 0.78, 0.7]:
		_ops.clear()
		var fs := roundi(56.0 * sc)
		var lh := roundf(fs * 1.32)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(text)
		var ci := rng.randi() % CRAYONS.size()
		var y := pad_y + fs * 0.86
		var space := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + fs * 0.24
		var paras := _paragraphs(text)
		for pi in paras.size():
			for line in paras[pi].split("\n"):
				var x := pad_x
				var words := Style.fr(line).split(" ", false)
				for word in words:
					var wfs := roundi(fs * rng.randf_range(0.9, 1.15))
					var ww := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs).x
					if x + ww > w - pad_x and x > pad_x:
						x = pad_x
						y += lh
					var rot := deg_to_rad(rng.randf_range(-3.0, 3.0))
					var dy := rng.randf_range(-2.0, 2.0)
					var col: Color = CRAYONS[ci % CRAYONS.size()]
					ci += 1
					var pivot := Vector2(x + ww * 0.5, y - wfs * 0.3 + dy)
					var xf := Transform2D(rot, pivot) * Transform2D(0.0, Vector2(-ww * 0.5, wfs * 0.3))
					_ops.append({"k": "s", "f": f, "t": word, "fs": wfs, "c": col, "xf": xf})
					x += ww + space
				y += lh
			y += fs * 0.25
		_content_h = y - lh + fs * 0.4 + pad_y
		if _content_h <= max_h:
			break
	_ops.append({"k": "sun", "p": Vector2(w - 16.0 - 42.0, 12.0 + 42.0), "s": 84.0})
	_paper_size = Vector2(w, _content_h)
	_rot = 1.3
	_paper_mat.set_shader_parameter("col_a", Color("#f4efe4"))
	_paper_mat.set_shader_parameter("col_b", Color("#e2d9c4"))
	_paper_mat.set_shader_parameter("rule_spacing", 0.0)
	_paper_mat.set_shader_parameter("margin_x", 0.0)
	_paper_mat.set_shader_parameter("stain1", Vector4(0.15, 0.85, 0.24, 0.12))
	_paper_mat.set_shader_parameter("stain2", Vector4(0.0, 0.0, 0.0, 0.0))
	_paper_mat.set_shader_parameter("torn", 0.0)
	_paper_mat.set_shader_parameter("grain", 0.9)

func _paragraphs(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := PackedStringArray()
	for l in text.split("\n"):
		if l.strip_edges() == "":
			if not cur.is_empty():
				out.append("\n".join(cur))
				cur = PackedStringArray()
		else:
			cur.append(l.strip_edges())
	if not cur.is_empty():
		out.append("\n".join(cur))
	return out

# ---------------------------------------------------------------- newspaper clipping

func _layout_newspaper(n: Dictionary, text: String) -> void:
	_ops.clear()
	var paras := _paragraphs(text)
	var masthead := str(n.get("masthead", ""))
	var date := str(n.get("date", ""))
	var headline := str(n.get("headline", ""))
	if masthead == "" and not paras.is_empty() and paras[0].find(" — ") > 0 and paras[0].length() < 90:
		var parts := paras[0].split(" — ", true, 1)
		masthead = parts[0]
		if date == "": date = parts[1]
		paras.remove_at(0)
	if headline == "" and not paras.is_empty() and paras[0] == paras[0].to_upper() and paras[0].length() < 90:
		headline = paras[0]
		paras.remove_at(0)
	if masthead == "": masthead = "L’Écho du quartier"
	if headline == "": headline = str(n.get("title", ""))
	var w := 980.0
	var pad_x := 46.0
	var inner := w - pad_x * 2.0
	var y := 36.0
	var f_mast := Style.spaced("serif_bold", 6.7)
	var f_date := Style.font("serif_italic")
	var f_head := Style.font("serif_bold")
	var f_body := Style.font("serif")
	var f_cap := Style.font("serif_bold")
	var ink := INK_NEWS
	# masthead + double rule
	var mt := Style.fr(masthead).to_upper()
	var mw := f_mast.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	_op_text(f_mast, Vector2(w * 0.5 - mw * 0.5, y + 17.0), mt, 21, ink)
	y += 21.0 + 10.0
	_ops.append({"k": "l", "a": Vector2(pad_x, y + 0.75), "b": Vector2(pad_x + inner, y + 0.75), "c": ink, "w": 1.6})
	_ops.append({"k": "l", "a": Vector2(pad_x, y + 4.25), "b": Vector2(pad_x + inner, y + 4.25), "c": ink, "w": 1.6})
	y += 5.0
	# date row + rule
	y += 6.0
	_op_text(f_date, Vector2(pad_x, y + 14.0), Style.fr(date), 17, ink)
	var rt := "Faits divers"
	var rw := f_date.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_op_text(f_date, Vector2(pad_x + inner - rw, y + 14.0), rt, 17, ink)
	y += 17.0 + 7.0
	_ops.append({"k": "l", "a": Vector2(pad_x, y + 0.6), "b": Vector2(pad_x + inner, y + 0.6), "c": ink, "w": 1.2})
	y += 2.0
	# headline
	if headline != "":
		y += 17.0
		for l in Style.wrap_px(f_head, 48, Style.fr(headline), inner):
			_op_text(f_head, Vector2(pad_x, y + 40.0), l, 48, ink)
			y += 52.0
		y += 12.0
	# body: two balanced, justified columns with a drop cap
	var col_gap := 34.0
	var col_w := (inner - col_gap) * 0.5
	var fs := 21
	var lh := 31.0
	var para_gap := 14.0
	var cap_letter := ""
	var cap_w := 0.0
	if not paras.is_empty() and paras[0].length() > 1:
		cap_letter = paras[0].substr(0, 1)
		paras[0] = paras[0].substr(1)
		cap_w = f_cap.get_string_size(cap_letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 67).x + 10.0
	var lines: Array[Dictionary] = []   # {words: PackedStringArray, last: bool, indent: float, gap_before: float}
	for pi in paras.size():
		var words := Style.fr(paras[pi].replace("\n", " ")).split(" ", false)
		var cur := PackedStringArray()
		var cur_w := 0.0
		var line_no := 0
		var sp := f_body.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		for wd in words:
			var indent := cap_w if pi == 0 and line_no < 2 else 0.0
			var ww := f_body.get_string_size(wd, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if not cur.is_empty() and cur_w + sp + ww > col_w - indent:
				lines.append({"words": cur, "last": false, "indent": indent, "gap": para_gap if line_no == 0 and pi > 0 else 0.0, "drop": pi == 0 and line_no == 0})
				line_no += 1
				cur = PackedStringArray()
				cur_w = 0.0
			cur.append(wd)
			cur_w += (sp if cur.size() > 1 else 0.0) + ww
		if not cur.is_empty():
			var indent2 := cap_w if pi == 0 and line_no < 2 else 0.0
			lines.append({"words": cur, "last": true, "indent": indent2, "gap": para_gap if line_no == 0 and pi > 0 else 0.0, "drop": pi == 0 and line_no == 0})
	var total := 0.0
	for l in lines:
		total += lh + float(l.gap)
	var body_top := y + 4.0
	var split := lines.size()
	var acc := 0.0
	for i in lines.size():
		acc += lh + float(lines[i].gap)
		if acc >= total * 0.5:
			split = i + 1
			break
	var col_h := [0.0, 0.0]
	for i in lines.size():
		var col := 0 if i < split else 1
		var l: Dictionary = lines[i]
		if not (col == 1 and i == split):
			col_h[col] += float(l.gap)
		var bx := pad_x + col * (col_w + col_gap)
		var by: float = body_top + col_h[col] + lh * 0.74
		if bool(l.drop) and cap_letter != "":
			_op_text(f_cap, Vector2(bx, body_top + 52.0), cap_letter, 67, ink)
		_justify(f_body, fs, l.words, bx + float(l.indent), by, col_w - float(l.indent), bool(l.last), ink)
		col_h[col] += lh
	var rx := pad_x + col_w + col_gap * 0.5
	_ops.append({"k": "l", "a": Vector2(rx, body_top + 4.0), "b": Vector2(rx, body_top + maxf(col_h[0], col_h[1]) - 4.0), "c": Color(ink, 0.3), "w": 1.0})
	_content_h = body_top + maxf(col_h[0], col_h[1]) + 50.0
	_paper_size = Vector2(w, _content_h)
	_rot = 0.7
	_paper_mat.set_shader_parameter("col_a", Color("#ddd2b6"))
	_paper_mat.set_shader_parameter("col_b", Color("#c4b791"))
	_paper_mat.set_shader_parameter("rule_spacing", 0.0)
	_paper_mat.set_shader_parameter("margin_x", 0.0)
	_paper_mat.set_shader_parameter("stain1", Vector4(0.8, 0.85, 0.26, 0.2))
	_paper_mat.set_shader_parameter("stain2", Vector4(0.06, 0.1, 0.18, 0.16))
	_paper_mat.set_shader_parameter("torn", 12.0)
	_paper_mat.set_shader_parameter("grain", 1.25)

func _justify(f: Font, fs: int, words: PackedStringArray, x: float, y: float, width: float, last: bool, col: Color) -> void:
	if words.is_empty():
		return
	if last or words.size() == 1:
		_op_text(f, Vector2(x, y), " ".join(words), fs, col)
		return
	var ws := PackedFloat32Array()
	var sum := 0.0
	for wd in words:
		var ww := f.get_string_size(wd, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ws.append(ww)
		sum += ww
	var gap := (width - sum) / float(words.size() - 1)
	var cx := x
	for i in words.size():
		_ops.append({"k": "s", "f": f, "p": Vector2(roundf(cx), roundf(y)), "t": words[i], "fs": fs, "c": col})
		cx += ws[i] + gap
