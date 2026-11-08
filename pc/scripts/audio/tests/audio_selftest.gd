## Audio module — self-test: library loaded, every sound name plays (positional and not), voice limits, handles.
## Runs standalone (scripts/audio/tests/audio_test.gd) or in-game: `godot --path pc -- --autostart --audio-test`.
## Prints "[audio-test] ..." lines; returns {ok: bool, failures: Array}.
extends RefCounted

var failures: Array = []


func _fail(msg: String) -> void:
	failures.append(msg)
	print("[audio-test] FAIL ", msg)


func _wait(tree: SceneTree, s: float) -> void:
	await tree.create_timer(s, true, false, true).timeout


func run(audio: Node, tree: SceneTree, in_game := false) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	# 1. library
	var guard := 0
	while not audio.is_loaded() and guard < 600:
		await _wait(tree, 0.05)
		guard += 1
	var st: Dictionary = audio.stats()
	print("[audio-test] library: names=%d files=%d loaded=%d failed=%d seconds=%.1f buses=%d rebuilt=%s mix_rate=%d" % [
		st.names, st.files, st.loaded, st.failed, st.seconds, st.buses, st.bus_layout_rebuilt, st.mix_rate])
	if not audio.is_loaded():
		_fail("library not loaded after 30 s")
	if st.failed > 0:
		_fail("%d files failed to load" % st.failed)
	if st.loaded != st.files:
		_fail("loaded %d / %d files" % [st.loaded, st.files])
	# 2. every name: one-shots through play(), loops through loop() (also once through play() to check one-shot use)
	var started := 0
	var refused := PackedStringArray()
	var loops := 0
	for n in audio.names:
		var is_loop: bool = audio._samples.has(n) and audio._samples[n].loop
		var h
		if is_loop:
			h = audio.loop(n, {"volume": 0.8, "unique": true})
			loops += 1
		else:
			h = audio.play(n, {"volume": 0.8})
		if h != null and h.is_playing():
			started += 1
		else:
			refused.append(n)
		await _wait(tree, 0.06)
		if is_loop and h != null:
			h.stop(0.1)
	print("[audio-test] play every name: %d/%d started (%d loops)%s" % [started, audio.names.size(), loops,
		"" if refused.is_empty() else " refused: " + ", ".join(refused)])
	if not refused.is_empty():
		_fail("names that did not start: " + ", ".join(refused))
	# 3. positional variants: the same names at explicit positions (room, ceiling, hall, nook, outside)
	var spots := [Vector3(1.0, 1.0, 0.5), Vector3(0.5, 2.95, 0.0), Vector3(-3.0, 3.6, -3.6), Vector3(1.4, 1.0, -3.6), Vector3(2.4, 2.0, 3.1)]
	var pos_started := 0
	var pos_total := 0
	for n in ["door_creak_open", "entity_step", "house_creak", "whisper", "knock_wall", "giggle", "drawer_open", "stair_creak"]:
		for p in spots:
			pos_total += 1
			var h = audio.play(n, {"position": p, "volume": 0.6, "no_jitter": true})
			if h.is_playing():
				pos_started += 1
			audio._last.erase(n) # bypass the dedupe gap for the test
		await _wait(tree, 0.05)
	print("[audio-test] positional plays: %d/%d started" % [pos_started, pos_total])
	if pos_started < pos_total * 0.9:
		_fail("positional plays refused: %d/%d" % [pos_total - pos_started, pos_total])
	await _wait(tree, 0.4)
	# 4. limits: spam footsteps + creaks, the voice count must stay under the cap and the pools never run dry silently
	var peak_voices := 0
	for i in 120:
		audio._last.clear()
		audio.play(["footstep_carpet", "footstep_wood", "lock_wheel", "house_creak", "bump", "pickup"][i % 6], {"volume": 0.3})
		peak_voices = maxi(peak_voices, audio._voices.size())
		if i % 10 == 0:
			await tree.process_frame
	var cap: int = audio._max_voices
	print("[audio-test] spam: peak voices=%d (cap %d + fading), free3d=%d free2d=%d" % [peak_voices, cap, audio._free3d.size(), audio._free2d.size()])
	if peak_voices > cap + 24:
		_fail("voice cap not enforced: %d" % peak_voices)
	# 5. handles: loop idempotency, set_position promotes a 2D loop to 3D, stop releases only one owner
	var a = audio.loop("clock_tick", {"position": Vector3(0.55, 0.6, 0.9)})
	var b = audio.loop("clock_tick", {"position": Vector3(0.6, 0.6, 0.95)})
	var same: bool = a._entry == b._entry
	a.stop(0.1)
	await _wait(tree, 0.2)
	var still: bool = b.is_playing()
	b.stop(0.1)
	var c = audio.loop("lullaby_hum", {"positional": false, "unique": true})
	await _wait(tree, 0.1)
	var was2d: bool = c._entry.voice != null and not c._entry.voice.is3d
	c.set_position(Vector3(-1.0, 1.5, -1.0))
	await _wait(tree, 0.1)
	var now3d: bool = c._entry.voice != null and c._entry.voice.is3d
	c.set_rate(0.9, 0.5)
	c.set_volume_db(-6.0)
	c.stop(0.2)
	print("[audio-test] handles: loop shared=%s survives one stop=%s 2D->3D=%s/%s" % [same, still, was2d, now3d])
	if not (same and still and was2d and now3d):
		_fail("loop handle semantics")
	var unknown = audio.play("this_sound_does_not_exist")
	if unknown.is_playing():
		_fail("unknown name returned a live handle")
	# 6. drain
	await _wait(tree, 3.5)
	var left := 0
	for v in audio._voices:
		if not v.loop:
			left += 1
	print("[audio-test] after 3.5 s: one-shot voices left=%d loops=%s" % [left, audio.stats().loops])
	if left > 2:
		_fail("%d one-shot voices did not finish" % left)
	print("[audio-test] self-test %s in %.1f s (%d failures)" % ["PASSED" if failures.is_empty() else "FAILED", (Time.get_ticks_msec() - t0) / 1000.0, failures.size()])
	return {"ok": failures.is_empty(), "failures": failures, "in_game": in_game}
