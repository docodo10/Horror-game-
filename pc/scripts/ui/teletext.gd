## UI module — one teletext display (the dresser TV or the full-screen CRT): a character grid rendered by a Control inside
## a SubViewport. Port of the web Teletext + TTBuilder + TTScreen (src/ui/UI.js): pages are Callables `func(b)` that
## draw through the builder methods below while recording the selectable lines (hit testing, keyboard / gamepad).
## A build pass records draw commands (blocks first, then the text layer — like the web canvas layers) and _draw()
## replays them, so input always acts on the page as it is now (build() runs synchronously when the page is dirty).
## Text uses Atkinson Hyperlegible Bold without antialiasing + nearest filtering (bitmap teletext look); the special
## glyphs ◄ ► ▶ ▲ ▼ █ ▮ ▯ ● and the leader dot are drawn as shapes.
extends Control

const Style := preload("res://scripts/ui/ui_style.gd")

const C_K := Style.TT_K
const C_R := Style.TT_R
const C_G := Style.TT_G
const C_Y := Style.TT_Y
const C_B := Style.TT_B
const C_M := Style.TT_M
const C_C := Style.TT_C
const C_W := Style.TT_W
const C_D := Style.TT_D

signal page_changed(prev: String, next: String)
signal built

var cols := 32
var rows := 13
var cw := 14
var ch := 26
var pad_x := 16
var pad_y := 11
var mix := false                 # transparent background (pause page over the paused game)
var W := 0
var H := 0
var font: Font
var font_px := 19
var ui: Node = null              # scripts/ui/ui.gd (sfx, clock, input hints)
var viewport: SubViewport = null

# ---------------------------------------------------------------- screen state (TTScreen)
var page_name := ""
var page_fn := Callable()
var home := ""
var items: Array[Dictionary] = []
var sel_id := ""
var dirty := true
var blink := true
var flick := 0.0
var ticker_x := 0.0
var has_ticker := false
var typed := ""
var burst := 0.0                 # static burst remaining (s)
var burst_max := 1.0
var on_back := Callable()
var on_lr := Callable()
var on_digit := Callable()
var allow_e := false
var locked := false
var page_data := {}              # free per-page state (sub page index...)

var _blink_t := 0.0
var _typed_t := 0.0
var _last_ms := 0
var _building: Array[Dictionary] = []
var _mw := {}

# recorded commands
var _rect_r: Array[Rect2] = []
var _rect_c := PackedColorArray()
var _g_chr := PackedStringArray()
var _g_pos := PackedVector2Array()
var _g_col := PackedColorArray()
var _g_dh := PackedByteArray()

## Creates the SubViewport + this renderer. parent: node that owns the SubViewport.
static func create(parent: Node, cols_: int, rows_: int, cw_: int, ch_: int, px: int, py: int, ui_: Node, name_: String) -> Control:
	var vp := SubViewport.new()
	vp.name = name_ + "Viewport"
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.gui_disable_input = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	parent.add_child(vp)
	var tt: Control = (load("res://scripts/ui/teletext.gd") as GDScript).new()
	tt.name = name_
	tt.ui = ui_
	tt.viewport = vp
	tt.configure(cols_, rows_, cw_, ch_, px, py)
	vp.add_child(tt)
	return tt

func configure(cols_: int, rows_: int, cw_: int, ch_: int, px: int, py: int) -> void:
	cols = cols_
	rows = rows_
	cw = cw_
	ch = ch_
	pad_x = px
	pad_y = py
	W = cols * cw + pad_x * 2
	H = rows * ch + pad_y * 2
	font = Style.font("tt")
	font_px = roundi(ch * 0.72)
	_mw.clear()
	position = Vector2.ZERO
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if viewport:
		viewport.size = Vector2i(W, H)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_active(on: bool) -> void:
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

func get_texture() -> Texture2D:
	return viewport.get_texture() if viewport else null

# ================================================================ screen logic

func show_page(name_: String, fn: Callable, sel := "") -> void:
	var prev := page_name
	page_name = name_
	page_fn = fn
	sel_id = sel
	items.clear()
	dirty = true
	typed = ""
	_last_ms = 0
	if prev != name_:
		page_changed.emit(prev, name_)

## Inputs must act on the page as it is now (a page switch / value change may not be built yet).
func fresh() -> void:
	if dirty and page_fn.is_valid():
		build()

func tick(dt: float) -> void:
	# bursts / flicker are short visual events: decay them on wall-clock time
	var tn := Time.get_ticks_msec()
	var rdt := minf(0.25, (tn - _last_ms) / 1000.0) if _last_ms > 0 else dt
	_last_ms = tn
	_blink_t += dt
	if _blink_t >= 0.5:
		_blink_t -= 0.5
		blink = not blink
		dirty = true
	if flick > 0.0:
		flick = maxf(0.0, flick - rdt * 5.0)
	if has_ticker:
		var before := floori(ticker_x / 3.0)
		ticker_x += dt * 34.0
		if floori(ticker_x / 3.0) != before:
			dirty = true
	if typed != "":
		_typed_t -= dt
		if _typed_t <= 0.0:
			typed = ""
			dirty = true
	if burst > 0.0:
		burst = maxf(0.0, burst - rdt)
	if dirty:
		build()

## Static burst level for the CRT shaders (web: tt.noise(amount) over the page).
func burst_amount() -> float:
	if burst <= 0.0:
		return 0.0
	return Style.clamp01(burst / maxf(0.05, burst_max)) * (1.1 if burst_max > 0.5 else 0.55)

func build() -> void:
	_rect_r.clear()
	_rect_c.resize(0)
	_g_chr.resize(0)
	_g_pos.resize(0)
	_g_col.resize(0)
	_g_dh.resize(0)
	on_back = Callable()
	on_lr = Callable()
	on_digit = Callable()
	has_ticker = false
	_building = []
	if not mix:
		_add_rect(Rect2(0, 0, W, H), C_K)
	if page_fn.is_valid():
		page_fn.call(self)
	items = _building
	var found := false
	for it in items:
		if it.id == sel_id:
			found = true
			break
	if not items.is_empty() and not found:
		sel_id = items[0].id
		dirty = true
	else:
		dirty = false
	queue_redraw()
	built.emit()

func sel() -> Dictionary:
	for it in items:
		if it.id == sel_id:
			return it
	return {}

func select(id: String, sound := true) -> void:
	if id == sel_id:
		return
	sel_id = id
	dirty = true
	flick = 1.0
	if sound:
		_sfx("select")

func move(d: int) -> void:
	fresh()
	var n := items.size()
	if n == 0 or locked:
		return
	var i := -1
	for k in n:
		if items[k].id == sel_id:
			i = k
			break
	i = 0 if i < 0 else (i + d + n) % n
	select(items[i].id)

func activate(side := 0) -> void:
	fresh()
	var it := sel()
	if it.is_empty() or locked:
		return
	var change: Callable = it.get("change", Callable())
	var on: Callable = it.get("on", Callable())
	if change.is_valid():
		change.call(side if side != 0 else 1)
		_sfx("value")
		flick = maxf(flick, 0.5)
	elif on.is_valid():
		on.call()
	dirty = true
	if change.is_valid():
		fresh()

## Navigation from the UI input router. action: up | down | left | right | accept | e | back | digit (data = "0".."9").
## Returns true when the screen consumed it.
func nav(action: String, data := "") -> bool:
	if locked:
		return true
	fresh()
	match action:
		"up", "down":
			move(1 if action == "down" else -1)
			return true
		"left", "right":
			var d := 1 if action == "right" else -1
			var it := sel()
			var change: Callable = it.get("change", Callable()) if not it.is_empty() else Callable()
			if change.is_valid():
				change.call(d)
				_sfx("value")
				flick = maxf(flick, 0.5)
				dirty = true
				fresh()
			elif on_lr.is_valid():
				on_lr.call(d)
			return true
		"accept":
			activate(0)
			return true
		"e":
			if allow_e:
				activate(0)
				return true
			return false
		"back":
			if on_back.is_valid():
				on_back.call()
				return true
			return false
		"digit":
			if on_digit.is_valid():
				on_digit.call(data)
				return true
			return false
	return false

## u, v in 0..1 with v = 0 at the top of the page. Returns {it, side} or {}.
func hit(u: float, v: float) -> Dictionary:
	fresh()
	var col := floori((u * W - pad_x) / cw)
	var row := floori((v * H - pad_y) / ch)
	for it in items:
		if it.row == row:
			var side := 0
			var field: Vector2i = it.get("field", Vector2i(-1, -1))
			if field.x >= 0 and col >= field.x - 1:
				side = -1 if col < (field.x + field.y) / 2.0 else 1
			return {"it": it, "side": side}
	return {}

func _sfx(kind: String) -> void:
	if ui and ui.has_method("sfx"):
		ui.sfx(kind)

# ================================================================ low-level drawing (Teletext)

func X(col: float) -> float:
	return pad_x + col * cw

func Y(row: float) -> float:
	return pad_y + row * ch

func _add_rect(r: Rect2, c: Color) -> void:
	_rect_r.append(r)
	_rect_c.append(c)

func rect(col: float, row: float, w: float, h: float, color: Color) -> void:
	_add_rect(Rect2(X(col), Y(row), w * cw, h * ch), color)

## Full-width band (covers the side margins too; row 0 also covers the top margin).
func band(row: int, color: Color, hgt := 1) -> void:
	var top := Y(row) - (pad_y if row == 0 else 0)
	var h := hgt * ch + (pad_y if row == 0 else 0)
	_add_rect(Rect2(0, top, W, h), color)

## Teletext 2×3 mosaic cell (bits 0..5, row-major) with "separated" gaps.
func mosaic(col: int, row: int, bits: int, color: Color) -> void:
	var x := X(col)
	var y := Y(row)
	var w := cw / 2.0
	var hh := ch / 3.0
	for k in 6:
		if bits & (1 << k):
			_add_rect(Rect2(roundf(x + (k & 1) * w + 1.0), roundf(y + (k >> 1) * hh + 1.0), ceilf(w - 2.0), ceilf(hh - 2.0)), color)

## Raw string from (col,row) (no case change); ox = pixel offset (ticker). dh = double height (2 rows).
func put(col: float, row: float, s: String, color: Color, dh := false, ox := 0.0) -> void:
	var x := X(col) + ox
	var y := Y(row)
	for i in s.length():
		if x > W:
			break
		var c := s[i]
		if c != " " and c != Style.NBSP and x > -cw:
			_g_chr.append(c)
			_g_pos.append(Vector2(x, y))
			_g_col.append(color)
			_g_dh.append(1 if dh else 0)
		x += cw

func _draw() -> void:
	for i in _rect_r.size():
		draw_rect(_rect_r[i], _rect_c[i])
	for i in _g_chr.size():
		_draw_glyph(_g_chr[i], _g_pos[i].x, _g_pos[i].y, _g_dh[i] == 1, _g_col[i])

func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c]), col)

func _draw_glyph(c: String, x: float, y: float, dh: bool, col: Color) -> void:
	var w := float(cw)
	var hh := ch * 2.0 if dh else float(ch)
	match c:
		"◄":
			_tri(Vector2(x + w * 0.8, y + hh * 0.3), Vector2(x + w * 0.8, y + hh * 0.74), Vector2(x + w * 0.18, y + hh * 0.52), col)
		"►":
			_tri(Vector2(x + w * 0.2, y + hh * 0.3), Vector2(x + w * 0.2, y + hh * 0.74), Vector2(x + w * 0.82, y + hh * 0.52), col)
		"▶":
			_tri(Vector2(x + w * 0.12, y + hh * 0.24), Vector2(x + w * 0.12, y + hh * 0.8), Vector2(x + w * 0.92, y + hh * 0.52), col)
		"▲":
			_tri(Vector2(x + w * 0.12, y + hh * 0.72), Vector2(x + w * 0.88, y + hh * 0.72), Vector2(x + w * 0.5, y + hh * 0.3), col)
		"▼":
			_tri(Vector2(x + w * 0.12, y + hh * 0.32), Vector2(x + w * 0.88, y + hh * 0.32), Vector2(x + w * 0.5, y + hh * 0.74), col)
		"█":
			draw_rect(Rect2(x, y, w, hh), col)
		"▮":
			draw_rect(Rect2(x + w * 0.14, y + hh * 0.26, w * 0.72, hh * 0.54), col)
		"▯":
			var lw := maxf(2.0, roundf(w * 0.14))
			draw_rect(Rect2(x + w * 0.14, y + hh * 0.26, w * 0.72, lw), col)
			draw_rect(Rect2(x + w * 0.14, y + hh * 0.8 - lw, w * 0.72, lw), col)
			draw_rect(Rect2(x + w * 0.14, y + hh * 0.26, lw, hh * 0.54), col)
			draw_rect(Rect2(x + w * 0.86 - lw, y + hh * 0.26, lw, hh * 0.54), col)
		"●":
			draw_circle(Vector2(x + w * 0.5, y + hh * 0.55), w * 0.3, col)
		"․":
			var s := maxf(2.0, roundf(w * 0.18))
			draw_rect(Rect2(roundf(x + w * 0.42), roundf(y + hh * 0.68), s, s), col)
		_:
			var m: float = _mw.get(c, -1.0)
			if m < 0.0:
				m = font.get_char_size(c.unicode_at(0), font_px).x
				_mw[c] = m
			var sx := (w * 0.9) / m if m > w * 0.9 else 1.0
			if sx == 1.0 and not dh:
				draw_char(font, Vector2(roundf(x + w * 0.5 - m * 0.5), roundf(y + hh * 0.78)), c, font_px, col)
			else:
				draw_set_transform(Vector2(x + w * 0.5, roundf(y + hh * 0.78)), 0.0, Vector2(sx, 2.0 if dh else 1.0))
				draw_char(font, Vector2(-m * 0.5, 0.0), c, font_px, col)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ================================================================ page builder (TTBuilder)

func bar(row: int, color: Color, hgt := 1) -> void:
	band(row, color, hgt)

## col: int | "c" (centered) | "r" (right aligned). Uppercases with French typography. Returns the start column.
func text(row: int, col: Variant, s: String, color := C_W, dh := false, bg: Variant = null) -> int:
	var u := Style.up(s)
	var n := u.length()
	var x := 0
	if col is String:
		x = maxi(0, floori((cols - n) / 2.0)) if col == "c" else cols - n
	else:
		x = int(col)
	if bg is Color:
		rect(x, row, n, 2 if dh else 1, bg)
	put(x, row, u, color, dh)
	return x

func header(title := "CANAL 3 · LA GARDIENNE", bg := C_B, fg := C_Y) -> void:
	band(0, bg)
	text(0, 0, title, fg)
	var m := 3 * 60 + 7
	if ui and ui.has_method("clock_minutes"):
		m = ui.clock_minutes()
	put(cols - 5, 0, "%02d%s%02d" % [floori(m / 60.0) % 24, ":" if blink else " ", m % 60], C_W)

## Row 1: page number left (or the digits being typed), info right.
func pnum(num: String, right := "", right_color := C_C) -> void:
	if typed != "":
		put(0, 1, "P" + typed.rpad(3, "-"), C_Y)
	else:
		put(0, 1, "P" + num, C_W)
	if right != "":
		text(1, "r", right, right_color)

func info(row: int, label: String, value: String, value_color := C_C) -> void:
	var L := Style.up(label)
	var V := Style.up(value)
	put(1, row, L, C_W)
	var x := cols - V.length()
	for i in range(1 + L.length() + 1, x - 1):
		put(i, row, Style.DOT, C_B)
	put(x, row, V, value_color)

## Selectable line. o: {id, label, right, kind: link|value|action, on: Callable, change: Callable(dir), color}.
func item(row: int, o: Dictionary) -> Dictionary:
	var id: String = o.get("id", "item%d" % row)
	if sel_id == "":
		sel_id = id
	var is_sel := sel_id == id
	var kind: String = o.get("kind", "link")
	var color: Color = o.get("color", C_W)
	var L := Style.up(o.get("label", ""))
	var right: Variant = o.get("right", null)
	if is_sel:
		rect(0, row, cols, 1, C_W)
	var fg := C_K if is_sel else color
	if is_sel and blink:
		put(0, row, "▶", C_K)
	put(1, row, L, fg)
	var it := {"id": id, "row": row, "kind": kind, "on": o.get("on", Callable()), "change": o.get("change", Callable()), "field": Vector2i(-1, -1)}
	if kind == "value":
		var a := cols - 13
		var V := Style.up(right if right != null else "")
		put(a, row, "◄", C_K if is_sel else C_Y)
		put(a + 1 + maxi(0, floori((11 - V.length()) / 2.0)), row, V, C_K if is_sel else C_C)
		put(cols - 1, row, "►", C_K if is_sel else C_Y)
		it.field = Vector2i(a, cols - 1)
	elif right != null and str(right) != "":
		var R := Style.up(str(right))
		var x := cols - R.length()
		for i in range(1 + L.length() + 1, x - 1):
			put(i, row, Style.DOT, C_K if is_sel else C_B)
		put(x, row, R, C_K if is_sel else C_Y)
	_building.append(it)
	return it

## Decorative mosaic band (snowy rooftops).
func mosaic_band(row: int, color := C_C, seed_ := 3.0) -> void:
	for i in cols:
		var v := sin(i * 0.9 + seed_) + sin(i * 0.37 + seed_ * 2.0)
		var bits := 0b111111 if v > 0.9 else (0b111100 if v > 0.1 else (0b110000 if v > -0.7 else 0))
		if bits:
			mosaic(i, row, bits, color)

func ticker(s: String, bg := C_R, fg := C_W, row := -1) -> void:
	if row < 0:
		row = rows - 1
	band(row, bg)
	var str_ := Style.up(s) + "   ·   "
	var len_ := str_.length() * cw
	var ox := -fmod(ticker_x, float(len_))
	put(0, row, str_, fg, false, ox - pad_x)
	put(0, row, str_, fg, false, ox - pad_x + len_)
	if len_ < W:
		put(0, row, str_, fg, false, ox - pad_x + len_ * 2)
	has_ticker = true

func hint(s: String, color := C_G, row := -1) -> void:
	text(rows - 1 if row < 0 else row, "c", s, color)

func back(fn: Callable) -> void:
	on_back = fn

func lr(fn: Callable) -> void:
	on_lr = fn

func digits(fn: Callable) -> void:
	on_digit = fn

func wrap_text(s: String, width := -1) -> PackedStringArray:
	return Style.wrap(Style.up(s), cols - 2 if width < 0 else width)

func type_digit(k: String) -> void:
	typed = (typed + k).right(3)
	_typed_t = 2.5
	dirty = true
