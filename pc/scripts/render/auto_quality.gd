## Automatic graphics quality (core). Settings "auto_quality" (default true) keeps Settings "quality" on a preset the
## player's GPU can hold, without ever changing the preset in the middle of play unless the game really is too slow:
##  1. calibrate() runs behind the loading screen: with vsync off it times real frames of the heaviest views, starting
##     from the best candidate preset and stepping down until the frame time fits the budget (then, on "low" only, a
##     lower render scale). Changing presets there is free: nobody is watching, and it also compiles their pipelines.
##  2. While playing it only watches: two slow 5 s windows in a row -> a lower render scale first (cheap, no hitch),
##     and only after that a lower preset. It never steps up during play (no oscillation); the next launch re-measures.
## Every change goes through Settings.set_value, so all modules react exactly as if the player had picked it.
extends Node

const ORDER := ["low", "medium", "high", "ultra"]
const SCALES := [1.0, 0.85, 0.75, 0.67]
const WINDOW := 5.0          # seconds of play per measurement
const SETTLE := 8.0          # ignore the first seconds after start / after a change
const TARGET_FPS := 60.0
const BUDGET_FPS := 75.0     # calibration: the heaviest view must run at least this fast with vsync off

var _t := 0.0
var _settle := SETTLE
var _frames := 0
var _slow_windows := 0

## Best first guess for this GPU (used by Settings on the very first launch; calibrate() then measures for real).
static func guess_for_gpu(adapter: String) -> String:
	var a := adapter.to_upper()
	var rx := RegEx.new()
	rx.compile("RTX\\s*(\\d{2})(\\d{2})")
	var m := rx.search(a)
	if m:
		var gen := int(m.get_string(1))
		var tier := int(m.get_string(2))
		if (gen >= 40 and tier >= 60) or (gen == 30 and tier >= 70) or gen >= 50: return "high"
		return "medium"
	rx.compile("RX\\s*(\\d)(\\d)(\\d{2})\\b")          # RDNA: RX 5500..9070
	m = rx.search(a)
	if m:
		var series := int(m.get_string(1))
		var tier2 := int(m.get_string(2))
		if series >= 9 or (series == 7 and tier2 >= 7) or (series == 6 and tier2 >= 8): return "high"
		if series >= 6 or (series == 5 and tier2 >= 6): return "medium"
		return "low"
	if a.contains("ARC A7") or a.contains("ARC B5"): return "medium"
	return "low"   # integrated graphics, unknown GPUs: start light

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Events.game_state.connect(func(s: String, _p: String) -> void:
		if s == "playing": _reset_window(SETTLE))
	Events.settings_changed.connect(func(k: String, _v: Variant) -> void:
		if k == "quality" or k == "upscale" or k == "render_scale": _reset_window(SETTLE))

func _enabled() -> bool:
	return bool(Settings.get_value("auto_quality", true)) and DisplayServer.get_name() != "headless" \
		and not DebugTools.args.has("quality") and not DebugTools.args.has("no-auto-quality")

# ---------------------------------------------------------------- load-time calibration

## Median frame time (ms) over up to `n` rendered frames (at least 3, at most ~`max_s` seconds on very slow machines).
func _median_ms(n: int, max_s := 1.5) -> float:
	var ts: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ts.append(float(now - last) / 1000.0)
		last = now
		if i >= 2 and now - t0 > int(max_s * 1e6): break
	ts.sort()
	return ts[ts.size() / 2]

## Lets `n` frames pass (render buffers, pipelines, GI warm-up), bounded in time on very slow machines.
func _settle_frames(n: int, max_s := 1.0) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		if i >= 1 and Time.get_ticks_usec() - t0 > int(max_s * 1e6): break

## Measures the real frame cost of each view (set_view.call(i) frames the camera on view i) and picks the best preset
## that fits the budget. Must run while nothing else loads. Restores vsync and the frame cap when done.
func calibrate(set_view: Callable, n_views: int) -> void:
	if not _enabled() or n_views <= 0:
		return
	var budget := 1000.0 / BUDGET_FPS
	var vs_prev := DisplayServer.window_get_vsync_mode()
	var cap_prev := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var refresh := DisplayServer.screen_get_refresh_rate()
	var period := 1000.0 / refresh if refresh > 1.0 else 0.0
	# start from the best preset auto may use: "high", or lower if play already proved it too heavy ("auto_cap")
	var cap := str(Settings.get_value("auto_cap", "high"))
	var start := str(DebugTools.args.get("calib-start", cap))
	var i := clampi(ORDER.find(start), 0, 2)
	if float(Settings.get_value("render_scale", 1.0)) < 1.0 and str(Settings.get_value("upscale", "off")) == "off":
		Settings.set_value("render_scale", 1.0)
	var worst := 0.0
	var t0 := Time.get_ticks_msec()
	while true:
		if str(Settings.get_value("quality", "")) != ORDER[i]:
			Settings.set_value("quality", ORDER[i])
		worst = 0.0
		for v in n_views:
			set_view.call(v)
			await _settle_frames(10)
			var wall: float = await _median_ms(14)
			var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
			var ms := wall
			# vsync could not be switched off (frame time sits on the refresh period): trust the GPU timer instead
			if period > 0.0 and absf(wall - period) < 0.08 * period:
				ms = gpu if gpu > 0.2 else 0.0
			worst = maxf(worst, ms)
		print("[auto-quality] calibration: %s = %.1f ms (budget %.1f)" % [ORDER[i], worst, budget])
		if worst <= budget or i == 0:
			break
		if worst > budget * 6.0 or Time.get_ticks_msec() - t0 > 20000:
			# far too slow (or measuring takes too long): straight to the lightest setup, no more measuring
			Settings.set_value("quality", ORDER[0])
			worst = budget * 3.0
			i = 0
			break
		i -= 2 if (worst > budget * 2.4 and i >= 2) else 1
	if i == 0 and worst > budget and str(Settings.get_value("upscale", "off")) == "off":
		# still too slow on "low": per-pixel cost scales with the square of the render scale
		var want := sqrt(budget / worst)
		var s: float = SCALES[SCALES.size() - 1]
		for c in SCALES:
			if c <= want + 0.03:
				s = c
				break
		print("[auto-quality] calibration: render scale %.2f" % s)
		Settings.set_value("render_scale", s)
	DisplayServer.window_set_vsync_mode(vs_prev)
	Engine.max_fps = cap_prev
	_reset_window(SETTLE)

# ---------------------------------------------------------------- while playing

func _reset_window(settle: float) -> void:
	_t = 0.0
	_frames = 0
	_settle = settle

func _process(dt: float) -> void:
	if Game.state != "playing" or not _enabled():
		return
	if _settle > 0.0:
		_settle -= dt
		return
	_t += dt
	_frames += 1
	if _t < WINDOW:
		return
	var fps := float(_frames) / _t
	_reset_window(0.0)
	var target := TARGET_FPS
	var cap := int(Settings.get_value("max_fps", 0))
	if cap > 0: target = minf(target, float(cap))
	if fps >= target * 0.8:
		_slow_windows = 0
		return
	_slow_windows += 1
	if _slow_windows < 2:
		return
	_slow_windows = 0
	var q := str(Settings.get_value("quality", "medium"))
	var i := maxi(0, ORDER.find(q))
	var scale := float(Settings.get_value("render_scale", 1.0))
	var native := str(Settings.get_value("upscale", "off")) == "off"
	if native and scale > 0.8:
		var s := 0.85 if scale > 0.9 else 0.75
		print("[auto-quality] %.0f fps < %.0f: render scale %.2f" % [fps, target, s])
		Settings.set_value("render_scale", s)
	elif i > 0:
		print("[auto-quality] %.0f fps < %.0f: %s -> %s" % [fps, target, q, ORDER[i - 1]])
		Settings.set_value("auto_cap", ORDER[i - 1])
		Settings.set_value("quality", ORDER[i - 1])
	elif native and scale > 0.7:
		print("[auto-quality] %.0f fps on low: render scale 0.67" % fps)
		Settings.set_value("render_scale", 0.67)
