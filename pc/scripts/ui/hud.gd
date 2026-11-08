## UI module — the in-game HUD, almost empty on purpose (web .lg-hud): objective toast typed like a typewriter then
## faded, centre dot that grows into a prompt with a keycap (keyboard label or gamepad "A") and a hold ring, big alert
## ("CACHE-TOI !"), battery bar while the flashlight is on, stamina bar when low, closet hint while hidden.
## Everything is drawn in _draw() on real time (wall clock) at a 1080p reference size (canvas_items stretch scales it).
## Subtitles live in scripts/ui/subtitles.gd (a separate node, drawn above the black fade).
extends Control

const Style := preload("res://scripts/ui/ui_style.gd")

const PAD := 44.0
const SHADOW := Color(0, 0, 0, 0.85)

var hud_alpha := 0.0
var on := false

# objective
var obj_text := ""
var _obj_lines := PackedStringArray()
var _obj_shown := 0.0
var _obj_delay := -1.0
var _obj_typing := false
var _obj_hide_at := 0.0
var _obj_alpha := 0.0
var _obj_target := 0.0

# prompt
var prompt_text := ""
var prompt_key := "E"
var prompt_pad := false
var prompt_hold := -1.0
var _prompt_alpha := 0.0

# alert
var _alert_text := ""
var _alert_t0 := -10.0
var _alert_until := 0.0
var _alert_alpha := 0.0

# battery / stamina / hidden
var battery := -1.0
var flash_on: Variant = null
var _batt_alpha := 0.0
var stamina := 1.0
var _stam_on := false
var _stam_alpha := 0.0
var player_hidden := false
var _hidden_t0 := 0.0
var hide_hint := "Caché. Appuie sur E pour sortir."

var _f_label: Font
var _f_obj: Font
var _f_prompt: Font
var _f_key: Font
var _f_alert: Font
var _f_hint: Font
var _key_box := StyleBoxFlat.new()

func _ready() -> void:
	name = "Hud"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_label = Style.spaced("ui_bold", 3.6)
	_f_obj = Style.font("type")
	_f_prompt = Style.font("ui_bold")
	_f_key = Style.font("ui_bold")
	_f_alert = Style.spaced("ui_bold", 10.0)
	_f_hint = Style.font("ui")
	_key_box.bg_color = Color(0, 0, 0, 0.35)
	_key_box.border_color = Color(0.937, 0.925, 0.894, 0.75)
	_key_box.set_border_width_all(2)
	_key_box.set_corner_radius_all(6)
	_key_box.anti_aliasing = true

func set_on(v: bool) -> void:
	on = v

# ---------------------------------------------------------------- objective

func set_objective(t: String) -> void:
	if t == obj_text:
		return
	var was_on := _obj_target > 0.0 or _obj_alpha > 0.05
	obj_text = t
	_obj_typing = false
	_obj_hide_at = 0.0
	_obj_target = 0.0
	if t == "":
		_obj_delay = -1.0
		return
	_obj_lines = Style.wrap_px(_f_obj, 25, t, _obj_max_w())
	_obj_delay = 0.5 if was_on else 0.05

func _obj_max_w() -> float:
	return minf(size.x * 0.46, 700.0) if size.x > 0.0 else 700.0

## Re-shows the current objective for a few seconds (Tab / View button).
func peek_objective(sec := 4.0) -> void:
	if obj_text == "" or _obj_typing or _obj_delay > 0.0:
		return
	_obj_shown = obj_text.length()
	_obj_target = 0.92
	_obj_hide_at = Style.now() + sec

# ---------------------------------------------------------------- prompt / alert / bars

func set_prompt(t: String, key: String, pad: bool, hold: float) -> void:
	prompt_text = t
	prompt_key = key
	prompt_pad = pad
	prompt_hold = hold

func alert(t: String, secs: float) -> void:
	_alert_text = t
	_alert_t0 = Style.now()
	_alert_until = _alert_t0 + secs

func set_battery(v: float) -> void:
	battery = v

func set_stamina(v: float) -> void:
	if absf(v - stamina) < 0.004:
		return
	stamina = v
	if v < 0.3:
		_stam_on = true
	elif v > 0.5:
		_stam_on = false

func set_hidden(v: bool) -> void:
	if v == player_hidden:
		return
	player_hidden = v
	_hidden_t0 = Style.now()

# ---------------------------------------------------------------- per frame

func update(dt: float) -> void:
	var t := Style.now()
	hud_alpha = move_toward(hud_alpha, 1.0 if on else 0.0, dt / 0.6)
	if _obj_delay > 0.0:
		_obj_delay -= dt
		if _obj_delay <= 0.0:
			_obj_delay = -1.0
			_obj_shown = 0.0
			_obj_typing = true
			_obj_target = 0.92
	elif _obj_typing:
		_obj_shown += dt * 40.0
		if _obj_shown >= obj_text.length():
			_obj_shown = obj_text.length()
			_obj_typing = false
			_obj_hide_at = t + 6.5
	elif _obj_hide_at > 0.0 and t > _obj_hide_at:
		_obj_hide_at = 0.0
		_obj_target = 0.0
	var obj_rate := dt / 0.35 if _obj_target > _obj_alpha else dt / 1.2
	_obj_alpha = move_toward(_obj_alpha, _obj_target, obj_rate)
	_prompt_alpha = move_toward(_prompt_alpha, 1.0 if prompt_text != "" else 0.0, dt / 0.15)
	if _alert_until > 0.0 and t > _alert_until:
		_alert_until = 0.0
	_alert_alpha = 1.0 if _alert_until > 0.0 else move_toward(_alert_alpha, 0.0, dt / 0.6)
	var batt_vis: bool = battery >= 0.0 and not (flash_on is bool and flash_on == false)
	_batt_alpha = move_toward(_batt_alpha, 0.75 if batt_vis else 0.0, dt / 0.5)
	_stam_alpha = move_toward(_stam_alpha, 0.85 if _stam_on else 0.0, dt / (0.25 if _stam_on else 0.6))
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers

func _text_shadowed(f: Font, pos: Vector2, s: String, fs: int, col: Color, a: float, outline := 8) -> void:
	draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.32 * a))
	draw_string(f, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9 * a))
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, col.a * a))

func _draw() -> void:
	var a := hud_alpha
	if a <= 0.001:
		return
	_draw_objective(a)
	_draw_center(a)
	_draw_alert(a)
	_draw_bars(a)
	_draw_hidden_hint(a)

func _draw_objective(a: float) -> void:
	var oa := _obj_alpha * a
	if oa <= 0.002 or obj_text == "":
		return
	var y_off := (1.0 - Style.clamp01(_obj_alpha / 0.92)) * -6.0
	var x := PAD
	var y := PAD + 14.0 + y_off
	_text_shadowed(_f_label, Vector2(x, y), "OBJECTIF", 14, Style.NIGHTLIGHT, 0.85 * oa / 0.92, 6)
	y += 12.0
	var shown := int(_obj_shown) if (_obj_typing or _obj_delay > 0.0) else obj_text.length()
	var lh := 34.0
	var consumed := 0
	var caret := Vector2(-1, -1)
	for i in _obj_lines.size():
		var line: String = _obj_lines[i]
		y += lh
		var n := clampi(shown - consumed, 0, line.length())
		if n > 0:
			_text_shadowed(_f_obj, Vector2(x, y), line.substr(0, n), 25, Style.WHITE, oa / 0.92)
		if _obj_typing and caret.x < 0.0 and n < line.length():
			caret = Vector2(x + _f_obj.get_string_size(line.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x, y)
		consumed += line.length() + 1
	if _obj_typing:
		if caret.x < 0.0 and not _obj_lines.is_empty():
			var last: String = _obj_lines[_obj_lines.size() - 1]
			caret = Vector2(x + _f_obj.get_string_size(last, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x, y)
		if fmod(Style.now(), 0.7) < 0.35:
			draw_rect(Rect2(caret.x + 2.0, caret.y - 22.0, 11.0, 27.0), Color(Style.NIGHTLIGHT, 0.8 * oa))

func _draw_center(a: float) -> void:
	var c := (size * 0.5).round()
	var pa := _prompt_alpha
	var dot_r := lerpf(2.0, 3.0, pa)
	draw_circle(c, dot_r + 1.2, Color(0, 0, 0, 0.35 * a))
	draw_circle(c, dot_r, Color(Color("#f3eee2"), lerpf(0.32, 0.95, pa) * a))
	if pa <= 0.002 or prompt_text == "":
		return
	var pf := _f_prompt
	var fs := 22
	var tw := pf.get_string_size(prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var key_w := 30.0
	var hold := prompt_hold >= 0.0
	var gap := 22.0 if hold else 13.0
	var total := key_w + gap + tw
	var x0 := roundf(c.x - total * 0.5)
	var y0 := c.y + 26.0
	var kc := Vector2(x0 + key_w * 0.5, y0 + key_w * 0.5)
	var ka := 0.95 * pa * a
	# keycap (square key, or round gamepad button)
	if prompt_pad:
		draw_circle(kc, key_w * 0.5, Color(0, 0, 0, 0.45 * ka))
		draw_arc(kc, key_w * 0.5 - 1.0, 0.0, TAU, 40, Color(0.937, 0.925, 0.894, 0.8 * ka), 2.0, true)
	else:
		_key_box.bg_color = Color(0, 0, 0, 0.35 * ka)
		_key_box.border_color = Color(0.937, 0.925, 0.894, 0.75 * ka)
		draw_style_box(_key_box, Rect2(x0, y0, key_w, key_w))
	var kfs := 16
	var ks := _f_key.get_string_size(prompt_key, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs)
	draw_string(_f_key, Vector2(kc.x - ks.x * 0.5, kc.y + kfs * 0.36), prompt_key, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs, Color(Style.WHITE, ka))
	if hold:
		var r := 22.0
		draw_arc(kc, r, 0.0, TAU, 64, Color(0.94, 0.91, 0.84, 0.2 * ka), 3.0, true)
		var hv := Style.clamp01(prompt_hold)
		if hv > 0.001:
			draw_arc(kc, r, -PI * 0.5, -PI * 0.5 + TAU * hv, maxi(3, int(64 * hv)), Color(Style.NIGHTLIGHT, ka), 3.0, true)
	_text_shadowed(pf, Vector2(x0 + key_w + gap, kc.y + fs * 0.36), prompt_text, fs, Style.WHITE, pa * a)

func _draw_alert(a: float) -> void:
	var aa := _alert_alpha * a
	if aa <= 0.002 or _alert_text == "":
		return
	var t := Style.now() - _alert_t0
	var k := Style.clamp01(t / 0.35)
	var ease_k := 1.0 - pow(1.0 - k, 3.0)
	var sc := lerpf(1.5, 1.0, ease_k) if k < 1.0 else 1.0
	var op := ease_k * aa
	var jit := Vector2.ZERO
	if t > 0.35 and t < 0.35 + 0.09 * 10.0:
		var step := int((t - 0.35) / 0.045) % 2
		jit = Vector2(2, -1) if step == 0 else Vector2(-1, 1)
	var fs := 74
	var f := _f_alert
	var sz := f.get_string_size(_alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var center := Vector2(size.x * 0.5, size.y * 0.3)
	draw_set_transform(center + jit, 0.0, Vector2(sc, sc))
	var pos := Vector2(-sz.x * 0.5, fs * 0.35)
	draw_string_outline(f, pos, _alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 36, Color(1.0, 0.16, 0.08, 0.10 * op))
	draw_string_outline(f, pos, _alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 20, Color(1.0, 0.16, 0.08, 0.22 * op))
	draw_string_outline(f, pos, _alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(1.0, 0.24, 0.16, 0.55 * op))
	draw_string(f, pos + Vector2(0, 3), _alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8 * op))
	draw_string(f, pos, _alert_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Color("#fff3ee"), op))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_bars(a: float) -> void:
	# battery: thin bar top-right (blinks red when low)
	var ba := _batt_alpha * a
	if ba > 0.002 and battery >= 0.0:
		var w := 60.0
		var r := Rect2(size.x - PAD - w, PAD + 4.0, w, 4.0)
		var low := battery < 0.15
		if low and fmod(Style.now(), 1.0) >= 0.5:
			ba *= 0.33
		draw_rect(r.grow(1.5), Color(0, 0, 0, 0.45 * ba))
		draw_rect(r, Color(0.937, 0.925, 0.894, 0.16 * ba / 0.75))
		draw_rect(Rect2(r.position, Vector2(w * Style.clamp01(battery), r.size.y)), Color(Color("#ff5a3c") if low else Color(0.937, 0.925, 0.894, 0.8), ba / 0.75))
	# stamina: very thin bar low in the centre
	var sa := _stam_alpha * a
	if sa > 0.002:
		var w2 := 200.0
		var r2 := Rect2(size.x * 0.5 - w2 * 0.5, size.y - PAD - maxf(64.0, size.y * 0.1), w2, 3.0)
		draw_rect(r2, Color(0.937, 0.925, 0.894, 0.12 * sa))
		draw_rect(Rect2(r2.position, Vector2(w2 * Style.clamp01(stamina), r2.size.y)), Color(1.0, 0.47, 0.35, 0.85 * sa))

func _draw_hidden_hint(a: float) -> void:
	if not player_hidden:
		return
	var t := Style.now() - _hidden_t0
	var k := 0.0
	if t < 0.48: k = t / 0.48 * 0.9
	elif t < 3.6: k = 0.9
	elif t < 6.0: k = lerpf(0.9, 0.3, (t - 3.6) / 2.4)
	else: k = 0.3
	k *= a
	var fs := 21
	var tw := _f_hint.get_string_size(hide_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var icon_w := 30.0
	var x0 := size.x * 0.5 - (icon_w + 10.0 + tw) * 0.5
	var y := size.y - PAD - maxf(100.0, size.y * 0.14)
	# closed eye icon (lash arc + 4 lashes)
	var ic := Vector2(x0 + icon_w * 0.5, y - 7.0)
	var col := Color(Style.WHITE, k)
	var pts := PackedVector2Array()
	for i in 13:
		var u := -1.0 + i / 6.0
		pts.append(ic + Vector2(u * 12.0, 4.0 * (1.0 - u * u) - 3.0))
	draw_polyline(pts, Color(0, 0, 0, 0.6 * k), 4.0, true)
	draw_polyline(pts, col, 2.0, true)
	for u in [-0.75, -0.25, 0.25, 0.75]:
		var p0: Vector2 = ic + Vector2(u * 12.0, 4.0 * (1.0 - u * u) - 3.0)
		draw_line(p0, p0 + Vector2(u * 3.0, 4.0), col, 2.0, true)
	_text_shadowed(_f_hint, Vector2(x0 + icon_w + 10.0, y), hide_hint, fs, Style.WHITE, k)

