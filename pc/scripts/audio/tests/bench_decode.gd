## Audio module micro-benchmark: native decode speed of the recorded library (MP3) through AudioStreamPlayback.mix_audio.
##   godot --headless --path pc -s res://scripts/audio/tests/bench_decode.gd
extends SceneTree


func _initialize() -> void:
	var files := ["res://assets/audio/player_music/chase_music.mp3", "res://assets/audio/electrical/room_tone.mp3",
		"res://assets/audio/electrical/fan_hum.mp3", "res://assets/audio/creature/lullaby_hum_1.mp3"]
	for f in files:
		var st: AudioStream = load(f)
		var pb := st.instantiate_playback()
		pb.start(0.0)
		var frames := int(st.get_length() * AudioServer.get_mix_rate())
		var t0 := Time.get_ticks_usec()
		var got := 0
		while got < frames:
			var b: PackedVector2Array = pb.mix_audio(1.0, 8192)
			if b.is_empty():
				break
			got += b.size()
		var us := Time.get_ticks_usec() - t0
		print("[bench] %s: %.1f s audio decoded in %.1f ms -> %.0fx realtime (%.3f%% of a core per voice)" % [
			f.get_file(), got / AudioServer.get_mix_rate(), us / 1000.0, (got / AudioServer.get_mix_rate()) / (us / 1e6),
			100.0 * (us / 1e6) / (got / AudioServer.get_mix_rate())])
	quit()
