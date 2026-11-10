## Player settings (autoload "Settings"), persisted to user://settings.cfg.
## STUB-COMPLETE (core owns it): get_value / set_value / save. Quality is applied by scripts/render/quality.gd.
extends Node

const PATH := "user://settings.cfg"
const AutoQualityScript := preload("res://scripts/render/auto_quality.gd")
var values := {
	"quality": "high",        # low | medium | high | ultra (kept up to date by auto quality when "auto_quality")
	"auto_quality": true,     # pick + adapt the preset to the GPU (scripts/render/auto_quality.gd)
	"sensitivity": 1.0,       # mouse look multiplier
	"invert_y": false,
	"brightness": 1.0,        # 0.6 .. 1.6
	"volume": 0.85,
	"subtitles": true,
	"fov": 54.0,              # vertical degrees (54 = 84 horizontal at 16:9, a natural eye-level lens)
	"camera_motion": 0.6,     # 0..1 scales head bob / roll / tremor
	"fullscreen": true,
	"vsync": true,
	"max_fps": 0,              # frame-rate cap: 0 = unlimited (vsync still limits to the monitor refresh)
	"show_fps": false,         # small frame counter in the corner
	"upscale": "off",          # off | fsr2_quality | fsr2_balanced | fsr2_performance (look module)
	"render_scale": 1.0,       # 0.5..1.0 when upscale is off
	"depth_of_field": false,   # off by default: a clean, sharp image (the options can turn the lens effects on)
	"film_grain": true,
	"chromatic_aberration": false,
	"auto_cap": "high",        # best preset auto quality may pick (lowered when play proved a preset too heavy)
	"settings_version": 3,
	"fear": "extreme",         # normal | extreme (fear director)
	"hud": "dot",              # dot (white centre dot, brighter on something usable) | none | full (prompts, meters)
}

const VERSION := 3
## Values reset once when a settings file from an older build is loaded (key = the version that changed their default).
## v2: clean image + natural lens by default, and auto quality measures the GPU again instead of keeping what the old
## live adaptation left behind. v3: the centre dot is the default interface.
const RESETS := {
	2: ["fov", "camera_motion", "depth_of_field", "chromatic_aberration", "render_scale", "auto_quality", "auto_cap"],
	3: ["hud"],
}

var _fps_label: Label = null
var _fps_t := 0.0
var _worst_ms := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	var loaded := cfg.load(PATH) == OK
	if loaded:
		var saved_v := int(cfg.get_value("settings", "settings_version", 1))
		var skip := ["settings_version"] if saved_v < VERSION else []
		for v in RESETS:
			if saved_v < int(v): skip.append_array(RESETS[v])
		for k in values.keys():
			if k in skip: continue
			values[k] = cfg.get_value("settings", k, values[k])
		if saved_v < VERSION: save()
	# First launch of a build with auto quality: start from a preset this GPU can hold (the live check refines it).
	if bool(values["auto_quality"]) and not (loaded and cfg.has_section_key("settings", "auto_quality")) \
			and DisplayServer.get_name() != "headless":
		values["quality"] = AutoQualityScript.guess_for_gpu(RenderingServer.get_video_adapter_name())
		save()
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

## F3 toggles the performance overlay anywhere (menu, game, pause).
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F3:
		set_value("show_fps", not bool(values.get("show_fps", false)))

func _process(dt: float) -> void:
	if _fps_label == null or not _fps_label.get_parent().visible: return
	_worst_ms = maxf(_worst_ms, dt * 1000.0)
	_fps_t -= dt
	if _fps_t <= 0.0:
		_fps_t = 0.5
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		# FPS + worst frame of the last half second (stutter), where the time goes (game scripts / CPU render submit /
		# GPU), which GPU and driver, which preset, output resolution x render scale, monitor refresh rate
		var win := DisplayServer.window_get_size()
		var scale := get_viewport().scaling_3d_scale
		_fps_label.text = "%d FPS · pire image %.0f ms   jeu %.1f ms · CPU rendu %.1f ms · GPU %.1f ms\n%s (%s) · %s%s · %dx%d x%.2f · %d Hz" % [
			roundi(Engine.get_frames_per_second()), _worst_ms, proc, cpu, gpu, RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_driver_name(), str(values.get("quality", "")),
			" (auto)" if bool(values.get("auto_quality", true)) else "", win.x, win.y, scale, roundi(DisplayServer.screen_get_refresh_rate())]
		_worst_ms = 0.0

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
