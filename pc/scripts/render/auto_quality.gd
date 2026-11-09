## Automatic graphics quality (core). Settings "auto_quality" (default true) keeps Settings "quality" on a preset the
## player's GPU can hold: a first guess from the GPU name, then live measurement while playing — if the frame rate
## stays under ~85 % of the target it steps down (ultra → high → medium → low, then a lower render scale), and it may
## step up once when there is a lot of headroom. Every change goes through Settings.set_value("quality"), so all
## modules (look, surfaces, world, entity, audio) react exactly as if the player had picked it in the options.
extends Node

const ORDER := ["low", "medium", "high", "ultra"]
const WINDOW := 5.0          # seconds of play per measurement
const SETTLE := 8.0          # ignore the first seconds after start / after a change (shader compiles)
const TARGET_FPS := 60.0

var _t := 0.0
var _settle := SETTLE
var _frames := 0
var _went_down := false
var _ups := 0
var _good_windows := 0

## Best first guess for this GPU (also used by Settings on the very first launch).
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
	if a.contains("GTX 16") or a.contains("GTX 10") or a.contains("RX 5") or a.contains("RX 4"): return "low"
	return "low"   # integrated graphics, unknown GPUs: start light, the live check steps up if there is headroom

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Events.game_state.connect(func(s: String, _p: String) -> void:
		if s == "playing": _reset_window(SETTLE))
	Events.settings_changed.connect(func(k: String, _v: Variant) -> void:
		if k == "quality" or k == "upscale" or k == "render_scale": _reset_window(SETTLE))

func _reset_window(settle: float) -> void:
	_t = 0.0
	_frames = 0
	_settle = settle

func _process(dt: float) -> void:
	if not bool(Settings.get_value("auto_quality", true)) or Game.state != "playing":
		return
	if DebugTools.args.has("quality") or DebugTools.args.has("no-auto-quality"):
		return   # debug runs that force a preset (screenshots, benchmarks) keep it
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
	var q := str(Settings.get_value("quality", "medium"))
	var i := maxi(0, ORDER.find(q))
	if fps < target * 0.85:
		_good_windows = 0
		_went_down = true
		if i > 0:
			print("[auto-quality] %.0f fps < %.0f: %s -> %s" % [fps, target, q, ORDER[i - 1]])
			Settings.set_value("quality", ORDER[i - 1])
		elif float(Settings.get_value("render_scale", 1.0)) > 0.8 and str(Settings.get_value("upscale", "off")) == "off":
			print("[auto-quality] %.0f fps on low: render scale 0.75" % fps)
			Settings.set_value("render_scale", 0.75)
	elif fps > target * 1.9 and not _went_down and _ups < 1 and i < 2:
		_good_windows += 1
		if _good_windows >= 2:
			_ups += 1
			_good_windows = 0
			print("[auto-quality] %.0f fps: %s -> %s" % [fps, q, ORDER[i + 1]])
			Settings.set_value("quality", ORDER[i + 1])
	else:
		_good_windows = 0
