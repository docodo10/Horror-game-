## UI module — shared look: fonts (OFL / Apache, res://assets/fonts/**), the teletext palette, the HUD palette and
## French typography helpers. Static only (preload it: `const Style := preload("res://scripts/ui/ui_style.gd")`).
extends RefCounted

const NBSP := " "
const DOT := "․"          # leader dot (drawn as a square by the teletext renderer)

# Teletext palette (slightly softened for the eyes) — same values as the web version.
const TT_K := Color("#000000")
const TT_R := Color("#ff3b2f")
const TT_G := Color("#38f25b")
const TT_Y := Color("#ffe63c")
const TT_B := Color("#2c4bff")
const TT_M := Color("#ff4fe2")
const TT_C := Color("#40ecff")
const TT_W := Color("#f4f2ea")
const TT_D := Color("#626a78")

# HUD palette (web CSS variables).
const PAPER := Color("#e9dfc9")
const WHITE := Color("#efece4")
const NIGHTLIGHT := Color("#e8c66a")
const CRAYON := Color("#c2412d")
const INK := Color("#0b0907")

const FONT_FILES := {
	"ui": "res://assets/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Regular.ttf",
	"ui_bold": "res://assets/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Bold.ttf",
	"type": "res://assets/fonts/special_elite/SpecialElite-Regular.ttf",
	"hand": "res://assets/fonts/caveat/Caveat-Medium.ttf",
	"hand_bold": "res://assets/fonts/caveat/Caveat-Bold.ttf",
	"serif": "res://assets/fonts/gelasio/Gelasio-Regular.ttf",
	"serif_bold": "res://assets/fonts/gelasio/Gelasio-Bold.ttf",
	"serif_italic": "res://assets/fonts/gelasio/Gelasio-Italic.ttf",
}

static var _fonts := {}

## Font by id: ui, ui_bold, type, hand, hand_bold, serif, serif_bold, serif_italic, tt (aliased bold for the teletext
## grid: no antialiasing, like the web renderer's alpha threshold). Falls back to the theme default font.
static func font(id: String) -> Font:
	var f: Font = _fonts.get(id)
	if f != null:
		return f
	if id == "tt":
		var base := font("ui_bold")
		if base is FontFile:
			var ff := (base as FontFile).duplicate() as FontFile
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NORMAL
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.generate_mipmaps = false
			f = ff
		else:
			f = base
	else:
		var path: String = FONT_FILES.get(id, FONT_FILES["ui"])
		if ResourceLoader.exists(path):
			f = load(path) as Font
		if f == null:
			f = ThemeDB.fallback_font
	_fonts[id] = f
	return f

## Letter-spaced variant (CSS letter-spacing in px at the size it is used with).
static func spaced(id: String, px: float) -> Font:
	var key := "%s@%d" % [id, roundi(px * 10.0)]
	var f: Font = _fonts.get(key)
	if f != null:
		return f
	var v := FontVariation.new()
	v.base_font = font(id)
	v.set_spacing(TextServer.SPACING_GLYPH, roundi(px))
	_fonts[key] = v
	return v

## French typography: non-breaking space before ! ? : ; » and after «.
static func fr(s: Variant) -> String:
	var t := "" if s == null else str(s)
	for c in ["!", "?", ":", ";", "»"]:
		t = t.replace(" " + c, NBSP + c)
	return t.replace("« ", "«" + NBSP)

static func up(s: Variant) -> String:
	return fr(s).to_upper()

## Word wrap on regular spaces only (non-breaking spaces keep words together), hard-splits words longer than width.
static func wrap(s: String, width: int) -> PackedStringArray:
	var out := PackedStringArray()
	width = maxi(1, width)
	for para in s.split("\n"):
		var line := ""
		for w in para.split(" ", false):
			if line == "":
				line = w
			elif line.length() + 1 + w.length() <= width:
				line += " " + w
			else:
				out.append(line)
				line = w
			while line.length() > width:
				out.append(line.substr(0, width))
				line = line.substr(width)
		out.append(line)
	return out

## Pixel word wrap for proportional fonts (greedy). Empty input lines are kept (pre-wrap behaviour).
static func wrap_px(f: Font, size: int, s: String, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var space_w := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	for para in s.split("\n"):
		var line := ""
		var lw := 0.0
		for w in para.split(" ", false):
			var ww := f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if line == "":
				line = w
				lw = ww
			elif lw + space_w + ww <= max_w:
				line += " " + w
				lw += space_w + ww
			else:
				out.append(line)
				line = w
				lw = ww
		out.append(line)
	return out

static func clamp01(v: float) -> float:
	return clampf(v, 0.0, 1.0)

static func smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static var _key_labels := {}

## Label of a physical key in the current keyboard layout (AZERTY shows Z for W, etc.). Cached per session.
static func key_label(physical: Key) -> String:
	if _key_labels.has(physical):
		return _key_labels[physical]
	var s := ""
	if DisplayServer.get_name() != "headless":
		var k := DisplayServer.keyboard_get_label_from_physical(physical)
		s = OS.get_keycode_string(k) if k != KEY_NONE else ""
	if s == "" or s.length() > 1:
		s = OS.get_keycode_string(physical)
	s = s.to_upper()
	_key_labels[physical] = s
	return s

## Wall clock in seconds (UI animations run on real time, like performance.now() in the web version).
static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0
