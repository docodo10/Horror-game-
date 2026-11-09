## Fear module test (headless):
##   godot --headless --path pc -s res://scripts/fear/tests/test_fear.gd [-- --fear-out=/abs/dir] [--fear-skip-audio]
## Part A (fast, simulated): ~10 minutes of scripted play against fakes (wandering, the blowout, the torch, the breaker
##   visit while hiding, clues, a trip to the garderie corridor, a patrol + chase, the mirror, hiding, a note, the key,
##   a second chase ending in a catch, night 2, the escape), on "extreme" then "normal". Logs the BPM curve and every
##   scare with timestamps, checks the pacing (start calm, min gap, events per minute, majors apart, quiet stretches,
##   nothing while she is awake, glimpses only while she sleeps) and the heart (rest, chase, jumpscare, slow decay).
## Part B (real time, ~30 s): the real Audio autoload + director (fakes around it) measured at the Master output
##   (AudioEffectCapture): beat-synced heartbeat at 165 BPM, rumble + drone at full stress, the layered jumpscare
##   (peak loud but limited), a fake-out crash, tinnitus, muffle / silence effects, time scale restored.
## Exit code 0 = every check passed.
extends SceneTree

var _started := false


func _process(_dt: float) -> bool:
	if not _started:
		_started = true
		var scr: Script = load("res://scripts/fear/tests/fear_test_driver.gd")
		if scr == null or not scr.can_instantiate():
			printerr("FEAR TEST FAILED: driver does not compile")
			quit(1)
			return false
		create_timer(240.0).timeout.connect(func() -> void:
			printerr("FEAR TEST FAILED: timeout")
			quit(1))
		var drv: Node = scr.new()
		drv.name = "FearTestDriver"
		get_root().add_child(drv)
		drv.call("run")
	return false
