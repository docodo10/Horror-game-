## Player settings (autoload "Settings"), persisted to user://settings.cfg.
## STUB-COMPLETE (core owns it): get_value / set_value / save. Quality is applied by scripts/render/quality.gd.
extends Node

const PATH := "user://settings.cfg"
var values := {
	"quality": "high",        # low | medium | high | ultra
	"sensitivity": 1.0,       # mouse look multiplier
	"invert_y": false,
	"brightness": 1.0,        # 0.6 .. 1.6
	"volume": 0.85,
	"subtitles": true,
	"fov": 72.0,
	"camera_motion": 1.0,     # 0..1 scales head bob / roll / tremor
	"fullscreen": true,
	"vsync": true,
	"max_fps": 0,              # frame-rate cap: 0 = unlimited (vsync still limits to the monitor refresh)
	"show_fps": false,         # small frame counter in the corner
	"hud": "none",             # none (no prompts / dot / meters; looked-at objects brighten) | full
}

var _fps_label: Label = null
var _fps_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in values.keys():
			values[k] = cfg.get_value("settings", k, values[k])
	_apply_perf()

## Frame-rate cap + optional FPS counter (core-owned; the UI only changes the values).
func _apply_perf() -> void:
	Engine.max_fps = maxi(0, int(values.get("max_fps", 0)))
	var show := bool(values.get("show_fps", false))
	if show and _fps_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_fps_label = Label.new()
		_fps_label.position = Vector2(12, 8)
		_fps_label.add_theme_font_size_override("font_size", 16)
		_fps_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.8, 0.85))
		_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_fps_label.add_theme_constant_override("outline_size", 4)
		layer.add_child(_fps_label)
	if _fps_label != null:
		_fps_label.get_parent().visible = show

func _process(dt: float) -> void:
	if _fps_label == null or not _fps_label.get_parent().visible: return
	_fps_t -= dt
	if _fps_t <= 0.0:
		_fps_t = 0.5
		_fps_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())

func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)

func set_value(key: String, value: Variant) -> void:
	values[key] = value
	save()
	if key == "max_fps" or key == "show_fps": _apply_perf()
	Events.settings_changed.emit(key, value)

func save() -> void:
	var cfg := ConfigFile.new()
	for k in values.keys():
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)
