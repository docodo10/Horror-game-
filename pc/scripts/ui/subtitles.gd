## UI module — subtitles: one line (two at most, then ellipsis), bottom centre, drawn above the black fade so the
## intro lines read over black. Hint lines are warm yellow (web .lg-subs.is-hint). Critical lines show even when the
## subtitles option is off (the UI decides before calling show_text()).
extends Control

const Style := preload("res://scripts/ui/ui_style.gd")
var text := ""
var speaker := ""
var is_hint := false
var critical := false
var until := 0.0
var _alpha := 0.0
var suppressed := false          # hidden behind full-screen pages (pause CRT, notes, keypad)
var _sup := 0.0
var _lines := PackedStringArray()
var _font: Font
var _font_spk: Font
const FS := 30

func _ready() -> void:
	name = "Subtitles"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Style.font("ui")
	_font_spk = Style.font("ui_bold")

func show_text(t: String, secs: float, crit: bool, spk := "", hint := false) -> void:
	text = t
	speaker = spk
	is_hint = hint
	critical = crit
	until = Style.now() + secs
	var full := (speaker + Style.NBSP + ": " + text) if speaker != "" else text
	var max_w := minf(size.x * 0.86, 1300.0) if size.x > 0.0 else 1300.0
	_lines = Style.wrap_px(_font, FS, full, max_w)
	if _lines.size() > 2:
		var l2 := _lines[1]
		_lines = PackedStringArray([_lines[0], l2 + "…"])

func hide_now() -> void:
	until = 0.0
	critical = false

func update(dt: float) -> void:
	if until > 0.0 and Style.now() > until:
		until = 0.0
		critical = false
	_alpha = move_toward(_alpha, 1.0 if until > 0.0 else 0.0, dt / 0.25)
	_sup = move_toward(_sup, 1.0 if suppressed else 0.0, dt / 0.2)
	queue_redraw()

func _draw() -> void:
	var a := _alpha * (1.0 - _sup)
	if a <= 0.002 or _lines.is_empty():
		return
	var lh := FS * 1.4
	var bottom := size.y - maxf(40.0, size.y * 0.07)
	var y := bottom - (_lines.size() - 1) * lh
	var col := Color("#f2e3b0") if is_hint else Color("#f6f2ea")
	for i in _lines.size():
		var line: String = _lines[i]
		var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
		var pos := Vector2(roundf(size.x * 0.5 - w * 0.5), roundf(y))
		draw_string_outline(_font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, 14, Color(0, 0, 0, 0.22 * a))
		draw_string_outline(_font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, 6, Color(0, 0, 0, 0.55 * a))
		draw_string(_font, pos + Vector2(0, 2), line, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0, 0, 0, a))
		draw_string(_font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(col, a))
		if i == 0 and speaker != "" and line.begins_with(speaker):
			draw_string(_font_spk, pos, speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(Style.NIGHTLIGHT, a))
		y += lh
