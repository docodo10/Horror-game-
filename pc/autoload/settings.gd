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
	"hud": "none",             # none (no prompts / dot / meters; looked-at objects brighten) | full
}

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in values.keys():
			values[k] = cfg.get_value("settings", k, values[k])

func get_value(key: String, default: Variant = null) -> Variant:
	return values.get(key, default)

func set_value(key: String, value: Variant) -> void:
	values[key] = value
	save()
	Events.settings_changed.emit(key, value)

func save() -> void:
	var cfg := ConfigFile.new()
	for k in values.keys():
		cfg.set_value("settings", k, values[k])
	cfg.save(PATH)
