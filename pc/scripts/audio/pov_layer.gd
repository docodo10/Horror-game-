## Audio module — self-driven POV loop layer (port of the web `Layer`): its volume follows a target with attack/release,
## the loop starts when the target rises and stops after 1.5 s of silence. Used for panting, heartbeats, scared/hidden
## breathing, the sub drone and the chase music.
extends RefCounted

var mgr = null                       # the Audio autoload (untyped: calls loop())
var name := ""
var opts := {}
var ref = null                       # Audio.SoundHandle of the running loop
var v := 0.0
var sent := -1.0
var sent_rate := -1.0
var sent_f := -1.0
var idle := 0.0


func _init(manager, sound: String, options := {}) -> void:
	mgr = manager
	name = sound
	opts = options


## rate: NAN = leave the playback rate alone. filter_hz: <= 0 = no filter control.
func update(dt: float, target: float, attack: float, release: float, rate: float = NAN, filter_hz: float = -1.0) -> void:
	if ref != null and not ref.is_playing():
		ref = null # stopped from outside (stop_all)
	var k := attack if target > v else release
	v += (target - v) * minf(1.0, dt * k)
	if target > 0.004 or v > 0.004:
		idle = 0.0
		if ref == null:
			var o := opts.duplicate()
			o["volume"] = maxf(v, 0.0001)
			o["unique"] = true
			if not is_nan(rate):
				o["rate"] = rate
			if filter_hz > 0.0:
				o["filter_hz"] = filter_hz
			ref = mgr.loop(name, o)
			sent = v
			sent_rate = 1.0 if is_nan(rate) else rate
			sent_f = filter_hz if filter_hz > 0.0 else float(opts.get("filter_hz", -1.0))
			if not ref.is_playing():
				ref = null
				return
	elif ref != null:
		idle += dt
		if idle > 1.5:
			ref.stop(0.25)
			ref = null
			v = 0.0
		return
	if ref == null:
		return
	if absf(v - sent) > 0.004:
		ref.set_volume(v)
		sent = v
	if not is_nan(rate) and absf(rate - sent_rate) > 0.006:
		ref.set_rate(rate, 0.4)
		sent_rate = rate
	if filter_hz > 0.0 and absf(filter_hz - sent_f) > sent_f * 0.04:
		ref.set_filter(filter_hz)
		sent_f = filter_hz


func kill(fade := 0.3) -> void:
	if ref != null:
		ref.stop(fade)
		ref = null
	v = 0.0
	sent = -1.0
