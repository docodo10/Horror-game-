## Audio module — headless test harness (no audio device: Godot mixes through the Dummy driver in real time, so the
## Master output can be captured and measured). Verifies logic, not taste:
##   godot --headless --path pc -s res://scripts/audio/tests/audio_test.gd
## Exit code 0 = every check passed. Prints "[audio-test] ..." lines.
extends SceneTree

const SelfTest := preload("res://scripts/audio/tests/audio_selftest.gd")
const Buses := preload("res://scripts/audio/buses.gd")
const Acoustics := preload("res://scripts/audio/acoustics.gd")


class FakeDoor extends RefCounted:
	var is_open := false
	var animating := false
	var node: Node3D = null
	var closed_xform := Transform3D()
	var open_xform := Transform3D(Basis(Vector3.UP, -1.6), Vector3.ZERO)


class FakeWorld extends Node3D:
	var handles := {}
	var power := true
	var tv = null


class FakeEntity extends Node3D:
	var fear := 0.0
	var state := "dormant"


var audio: Node
var game: Node        # autoloads (not visible as globals to a -s main script)
var events: Node
var cam: Camera3D
var world: FakeWorld
var door: FakeDoor
var ent: FakeEntity
var cap: AudioEffectCapture
var failures: Array = []
var results := {}


func _initialize() -> void:
	_main.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func check(cond: bool, what: String) -> void:
	if cond:
		print("[audio-test] ok   ", what)
	else:
		failures.append(what)
		print("[audio-test] FAIL ", what)


func _main() -> void:
	await process_frame
	audio = root.get_node_or_null("Audio")
	game = root.get_node_or_null("Game")
	events = root.get_node_or_null("Events")
	if audio == null or game == null or events == null:
		print("[audio-test] FAIL Audio autoload missing")
		quit(1)
		return
	# minimal scene: a listener + a fake world (upstairs door handle) + a fake creature
	world = FakeWorld.new()
	world.name = "World"
	root.add_child(world)
	door = FakeDoor.new()
	door.node = Node3D.new()
	world.add_child(door.node)
	world.handles["door.upstairs"] = door
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	ent = FakeEntity.new()
	world.add_child(ent)
	ent.global_position = Vector3(-3.0, 2.75, -3.6)
	game.world = world
	game.camera = cam
	game.entity = ent
	_listener(Vector3(0.25, 1.6, 1.5), 0.0)
	cap = AudioEffectCapture.new()
	cap.buffer_length = 4.0
	AudioServer.add_bus_effect(0, cap) # end of Master: measures exactly what leaves the game
	await _wait(0.2)

	# ---- 1. library + every name (self-test)
	var t = SelfTest.new()
	var r: Dictionary = await t.run(audio, self, false)
	for f in r.failures:
		failures.append("selftest: " + f)
	audio.stop_all(0.05)
	await _wait(0.5)

	# ---- 2. bus graph
	check(Buses.is_valid(), "bus graph valid (%d buses)" % AudioServer.bus_count)
	check(audio._master_amp != null and audio._pause_lpf != null and audio._amb_lpfs.size() == 3, "master/pause/ambience effects found")
	var n_amps := 0
	for c in audio._cat_amps:
		n_amps += audio._cat_amps[c].size()
	check(n_amps == 13, "13 category duck amplifiers (got %d)" % n_amps)

	# ---- 3. acoustics (pure logic)
	check(Acoustics.zone_of(Vector3(0, 1.6, 0)) == Acoustics.Z_ROOM, "zone room")
	check(Acoustics.zone_of(Vector3(1.4, 1.6, -3.6)) == Acoustics.Z_NOOK, "zone nook")
	check(Acoustics.zone_of(Vector3(-3.0, 3.6, -3.6)) == Acoustics.Z_HALL, "zone hall")
	check(Acoustics.zone_of(Vector3(0.5, 2.95, 0.0)) == Acoustics.Z_CEIL, "zone ceiling")
	check(Acoustics.zone_of(Vector3(-3.0, 1.2, -2.0)) == Acoustics.Z_CLOSET, "zone closet")
	check(Acoustics.zone_of(Vector3(-3.0, 2.2, 0.5)) == Acoustics.Z_STAIR, "zone stairwell")
	check(Acoustics.zone_of(Vector3(2.4, 2.0, 3.1)) == Acoustics.Z_OUT, "zone outside")
	var oc := Acoustics.occlusion(Acoustics.Z_HALL, Acoustics.Z_ROOM, 0.0, Vector3.ZERO, Vector3.ZERO)
	var oo := Acoustics.occlusion(Acoustics.Z_HALL, Acoustics.Z_ROOM, 1.0, Vector3.ZERO, Vector3.ZERO)
	check(is_equal_approx(oc.x, 520.0) and is_equal_approx(oo.x, 5500.0), "hall occlusion closed 520 Hz / open 5500 Hz")

	# ---- 4. occlusion, measured at the output (tv static = broadband noise, a fixed loop)
	var tv_room := Vector3(-0.55, 1.4, -2.4)
	var m_room: Dictionary = await _measure_loop("tv_static", tv_room, 0.7)
	var m_hall_closed: Dictionary = await _measure_loop("tv_static", Vector3(-3.0, 3.6, -3.6), 0.7)
	door.is_open = true
	var m_hall_open: Dictionary = await _measure_loop("tv_static", Vector3(-3.0, 3.6, -3.6), 0.7)
	door.is_open = false
	door.animating = true
	door.node.transform = Transform3D(Basis(Vector3.UP, -0.8), Vector3.ZERO)
	var m_hall_half: Dictionary = await _measure_loop("tv_static", Vector3(-3.0, 3.6, -3.6), 0.7)
	var door_t: float = audio._door_t
	door.animating = false
	var m_ceil: Dictionary = await _measure_loop("tv_static", Vector3(0.5, 2.95, 0.0), 0.7)
	var m_out: Dictionary = await _measure_loop("tv_static", Vector3(2.45, 2.0, 3.2), 0.7)
	print("[audio-test] tv_static rms/hf(dB): room %s | hall closed %s | half open (t=%.2f) %s | open %s | ceiling %s | outside %s" % [
		_fmt(m_room), _fmt(m_hall_closed), door_t, _fmt(m_hall_half), _fmt(m_hall_open), _fmt(m_ceil), _fmt(m_out)])
	check(m_room.rms_db > -45.0, "room source audible (%.1f dB)" % m_room.rms_db)
	check(m_hall_closed.hf_db < m_room.hf_db - 8.0, "closed door muffles highs (hf %.1f vs %.1f)" % [m_hall_closed.hf_db, m_room.hf_db])
	check(m_hall_open.hf_db > m_hall_closed.hf_db + 5.0, "open door lets highs through (hf %.1f vs %.1f)" % [m_hall_open.hf_db, m_hall_closed.hf_db])
	check(m_hall_open.rms_db > m_hall_closed.rms_db + 3.0, "open door is louder (%.1f vs %.1f)" % [m_hall_open.rms_db, m_hall_closed.rms_db])
	check(door_t > 0.35 and door_t < 0.65, "door openness follows the swing (t=%.2f)" % door_t)
	check(m_hall_half.hf_db > m_hall_closed.hf_db and m_hall_half.hf_db < m_hall_open.hf_db, "half-open door is in between")
	check(m_ceil.hf_db < m_room.hf_db - 8.0, "ceiling muffles highs (hf %.1f)" % m_ceil.hf_db)
	# laundry nook doorway: straight through the doorway vs behind the wall
	_listener(Vector3(1.35, 1.6, -3.7), 180.0)
	var m_door_line: Dictionary = await _measure_loop("tv_static", Vector3(1.35, 1.4, -0.5), 0.7)
	var m_door_wall: Dictionary = await _measure_loop("tv_static", Vector3(-2.6, 1.4, -0.5), 0.7)
	print("[audio-test] nook listener: source through doorway %s | behind wall %s" % [_fmt(m_door_line), _fmt(m_door_wall)])
	check(m_door_wall.hf_db < m_door_line.hf_db - 3.0, "nook doorway diffraction (hf %.1f vs %.1f)" % [m_door_wall.hf_db, m_door_line.hf_db])
	_listener(Vector3(0.25, 1.6, 1.5), 0.0)
	# panning: a source on the right is louder in the right ear
	var m_right: Dictionary = await _measure_loop("tv_static", Vector3(3.2, 1.6, 1.5), 0.6)
	print("[audio-test] source at the right: L %.1f dB / R %.1f dB" % [m_right.l_db, m_right.r_db])
	check(m_right.r_db > m_right.l_db + 6.0, "stereo panning (R-L = %.1f dB)" % (m_right.r_db - m_right.l_db))

	# ---- 5. reverb: tail energy of a short tick (150..650 ms after the onset vs its first 80 ms), sources straight ahead.
	# Web reference (scratchpad audio_tools/web_reverb_sim.py: Audio.js _makeIR + Web Audio convolver normalisation):
	# carpeted room 1.5 m -40.4 dB, room 4.0 m -32.4 dB (far = wetter), laundry nook 1.4 m -27.5 dB.
	var tail_room: float = await _tail("lock_wheel", Vector3(0.25, 1.6, 1.5), 0.0, Vector3(0.25, 1.6, 0.0), false)
	var tail_far: float = await _tail("lock_wheel", Vector3(0.25, 1.6, 2.2), 0.0, Vector3(0.25, 1.6, -1.8), false)
	var tail_dry: float = await _tail("lock_wheel", Vector3(0.25, 1.6, 1.5), 0.0, Vector3(0.25, 1.6, 0.0), true)
	var tail_nook: float = await _tail("lock_wheel", Vector3(1.35, 1.6, -3.0), 0.0, Vector3(1.35, 1.6, -4.4), false)
	print("[audio-test] reverb tail: room 1.5 m %.1f dB (web -40.4), room 4 m %.1f dB (web -32.4), nook 1.4 m %.1f dB (web -27.5), dry %.1f dB" % [
		tail_room, tail_far, tail_nook, tail_dry])
	check(tail_room > tail_dry + 6.0, "room reverb adds a tail")
	check(absf(tail_room + 40.4) < 3.0, "room reverb level matches the web version (%.1f dB)" % tail_room)
	check(tail_far > tail_room + 4.0, "far sources are wetter (uniform reverberant field)")
	check(absf(tail_nook + 27.5) < 3.0, "laundry-nook reverb matches the web version (%.1f dB)" % tail_nook)
	# decay time of each reverb alone (the tick routed straight into the wet-only send bus), Schroeder T20 -> RT60
	var rt_room: float = await _rt60("SFX_Room")
	var rt_dark: float = await _rt60("SFX_Dark")
	print("[audio-test] reverb RT60 (T20): room %.2f s (web IR 0.44), dark %.2f s (web IR 0.97)" % [rt_room, rt_dark])
	check(rt_room > 0.3 and rt_room < 0.8, "carpeted-room reverb time")
	check(rt_dark > 0.75 and rt_dark < 1.5 and rt_dark > rt_room * 1.4, "dark reverb is clearly longer")
	_listener(Vector3(0.25, 1.6, 1.5), 0.0)

	# ---- 6. mix: ducking, pause, hidden muffle, master volume
	var bed = audio.loop("room_tone", {"volume": 1.0, "fade_in": 0.05})
	await _wait(0.6)
	var amb0: Dictionary = await _measure(0.5)
	audio._duck(0.3, 0.75, 0.85, 1.0, 2.0, 2.2) # = stinger
	await _wait(0.3)
	var amb1: Dictionary = await _measure(0.5)
	print("[audio-test] room tone %.1f dB, ducked %.1f dB (expected about -10.5)" % [amb0.rms_db, amb1.rms_db])
	check(absf((amb1.rms_db - amb0.rms_db) + 10.5) < 3.0, "ambience ducking under the stinger")
	await _wait(2.6)
	audio.set_paused(true)
	await _wait(0.8)
	var amb_p: Dictionary = await _measure(0.5)
	check(audio._pause_hz < 1000.0 and AudioServer.is_bus_effect_enabled(0, 0), "pause low-pass engaged (%.0f Hz)" % audio._pause_hz)
	audio.set_paused(false)
	await _wait(0.8)
	var amb2: Dictionary = await _measure(0.5)
	print("[audio-test] room tone paused %s, resumed %s" % [_fmt(amb_p), _fmt(amb2)])
	check(amb_p.rms_db < amb2.rms_db - 8.0 and amb_p.hf_db < amb2.hf_db - 3.0, "pause ducks + muffles")
	check(not AudioServer.is_bus_effect_enabled(0, 0), "pause low-pass bypassed again")
	audio.set_master_volume(0.25)
	await _wait(0.6)
	var amb_v: Dictionary = await _measure(0.5)
	audio.set_master_volume(0.85)
	print("[audio-test] master volume 0.25: %.1f dB (expected %.1f)" % [amb_v.rms_db, amb2.rms_db + 30.0 * log(0.25 / 0.85) / log(10.0)])
	check(absf(amb_v.rms_db - (amb2.rms_db + 30.0 * log(0.25 / 0.85) / log(10.0))) < 2.0, "master volume curve (v^1.5)")
	bed.stop(0.05)
	await _wait(0.3)

	# ---- 7. dynamics: compressor + limiter transfer curve with a 997 Hz tone through the Music bus (dry)
	await _dynamics()

	# ---- 7b. levels of typical gameplay sounds through the whole chain (master volume 0.85 = default)
	var levels := {}
	var walk := func():
		for i in 4:
			audio._last.erase("footstep_carpet")
			audio.play("footstep_carpet", {"volume": 0.66})
			await _wait(0.45)
	levels["footstep walk (x4)"] = await _level(walk, 2.0)
	levels["door creak 2 m"] = await _level(func(): audio.play("door_creak_open", {"position": Vector3(0.25, 1.2, -0.5)}), 3.0)
	levels["entity step 3 m"] = await _level(func(): audio.play("entity_step", {"position": Vector3(0.25, 0.05, -1.5), "volume": 0.72}), 0.8)
	levels["ceiling steps above"] = await _level(func(): audio.play("ceiling_steps", {"position": Vector3(0.5, 2.95, 1.0), "volume": 0.9}), 1.2)
	levels["jumpscare"] = await _level(func(): audio.play("jumpscare", {"volume": 1.0}), 2.0)
	levels["stinger"] = await _level(func(): audio.play("stinger", {"volume": 0.95}), 3.0)
	# like for like: the same creak (same variation), same 1.5 m, below the glue compressor's threshold, room vs above
	var creak_room := func():
		audio._samples["door_creak_open"].last = -1
		seed(7)
		audio.play("door_creak_open", {"position": Vector3(0.25, 1.6, 0.0), "no_jitter": true, "volume": 0.2})
	var creak_above := func():
		audio._samples["door_creak_open"].last = -1
		seed(7)
		audio.play("door_creak_open", {"position": Vector3(0.25, 3.1, 1.5), "no_jitter": true, "volume": 0.2})
	levels["creak 1.5 m room"] = await _level(creak_room, 2.0)
	levels["creak 1.5 m above"] = await _level(creak_above, 2.0)
	randomize()
	var txt := ""
	for k in levels:
		txt += " %s pk %.1f / rms %.1f |" % [k, levels[k].peak_db, levels[k].rms_db]
	print("[audio-test] levels (dBFS):", txt)
	check(levels["jumpscare"].peak_db <= -0.9, "loudest sound stays under the limiter ceiling (%.1f dBFS)" % levels["jumpscare"].peak_db)
	check(levels["footstep walk (x4)"].peak_db > -40.0 and levels["footstep walk (x4)"].peak_db < -10.0, "footsteps in a sane range")
	var r_room: Dictionary = levels["creak 1.5 m room"]
	var r_above: Dictionary = levels["creak 1.5 m above"]
	check(r_above.rms_db < r_room.rms_db - 4.0 and r_above.hf_db < r_room.hf_db - 6.0,
		"same creak through the ceiling: quieter (%.1f vs %.1f dB) and muffled (hf %.1f vs %.1f)" % [r_above.rms_db, r_room.rms_db, r_above.hf_db, r_room.hf_db])

	# ---- 8. game flow: beds, power, POV layers driven by Events / game.fear
	game.set_state("menu")
	await _wait(0.3)
	var loops: PackedStringArray = audio.stats().loops
	print("[audio-test] menu beds: ", loops)
	for n in ["room_tone", "clock_tick", "wind_outside", "light_buzz", "fan_hum"]:
		check(_has_loop(n), "bed %s running" % n)
	game.set_state("playing")
	events.power_changed.emit(false)
	await _wait(0.3)
	check(not _has_loop("light_buzz"), "power off stops the light buzz")
	events.power_changed.emit(true)
	await _wait(0.3)
	check(_has_loop("light_buzz") and _has_loop("fan_hum"), "power on restarts buzz + fan")
	events.player_stamina.emit(0.0, true, 1.0)
	ent.fear = 0.9
	await _wait(1.5)
	check(_has_loop("player_breath_run"), "sprint exhaustion panting")
	check(_has_loop("heartbeat_fast"), "fear 0.9 -> fast heartbeat")
	check(_has_loop("ambience_drone"), "fear drone")
	events.player_stamina.emit(1.0, false, 0.0)
	events.player_hide.emit(true, "closet")
	await _wait(1.0)
	var hide_head := false
	for l in audio._layers:
		if l == audio._l_hide and l.ref != null and l.ref._entry.voice != null:
			hide_head = l.ref._entry.voice.head_locked
	check(audio._l_hide.ref != null and hide_head, "hidden: muffled held breath (head-locked filtered voice)")
	check(audio._lz == Acoustics.Z_CLOSET, "hidden -> listener in the closet")
	events.player_hide.emit(false, "")
	events.entity_state.emit("chasing", "searching")
	await _wait(1.0)
	check(_has_loop("chase_music"), "chase music while chasing")
	events.entity_spotted.emit()
	await _wait(0.4)
	var names_playing := {}
	for v in audio._voices:
		names_playing[v.name] = true
	check(names_playing.has("stinger") and names_playing.has("player_gasp"), "spotted: stinger + gasp")
	events.entity_state.emit("dormant", "chasing")
	ent.fear = 0.0
	var lull = audio.loop("lullaby_hum")
	await _wait(0.3)
	var lv = lull._entry.voice
	check(lv != null and lv.is3d and lv.pos.distance_to(ent.global_position + Vector3(0, 1.7, 0)) < 0.05, "lullaby follows the creature's head")
	ent.global_position = Vector3(0.0, 0.0, 0.0)
	await _wait(0.2)
	check(lv != null and lv.pos.distance_to(Vector3(0, 1.7, 0)) < 0.05, "...and keeps following")
	lull.stop(0.1)
	await _wait(3.0)
	print("[audio-test] 3 s after calm: chase layer %.2f (was 0.95), panting %.2f" % [audio._l_chase.v, audio._l_run.v])
	check(audio._l_chase.v < 0.2 and audio._l_run.v < 0.5, "layers release when calm (web release rates)")

	# ---- 9. stop_all + scene reload
	audio.stop_all(0.1)
	await _wait(0.5)
	check(audio._voices.size() == 0 and audio._loops.size() == 0, "stop_all drains every voice (%d left)" % audio._voices.size())
	game.set_state("loading")
	await _wait(0.2)
	game.set_state("menu")
	await _wait(0.2)
	check(_has_loop("room_tone"), "beds restart after a reload")
	audio.stop_all(0.05)
	await _wait(0.3)
	print("[audio-test] stats: ", audio.stats())
	print("[audio-test] %s — %d failure(s)" % ["ALL PASSED" if failures.is_empty() else "FAILED", failures.size()])
	for f in failures:
		print("[audio-test]   - ", f)
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	quit(0 if failures.is_empty() else 1)


func _has_loop(n: String) -> bool:
	for e in audio._loops:
		if e.name == n and e.voice != null:
			return true
	return false


func _listener(p: Vector3, yaw_deg: float) -> void:
	cam.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), p)


func _fmt(m: Dictionary) -> String:
	return "%.1f/%.1f" % [m.rms_db, m.hf_db]


## Runs `fn` (plays something) and measures the Master output for `secs`.
func _level(fn: Callable, secs: float) -> Dictionary:
	await _wait(0.3)
	cap.clear_buffer()
	await fn.call()
	await _wait(secs)
	var buf := cap.get_buffer(cap.get_frames_available())
	audio.stop_all(0.05)
	await _wait(0.2)
	return _stats(buf, 0, buf.size())


## Plays a loop at `pos`, lets the occlusion settle, measures, stops it.
func _measure_loop(n: String, pos: Vector3, secs: float) -> Dictionary:
	var h = audio.loop(n, {"position": pos, "fade_in": 0.02, "unique": true, "offset": 0.0})
	await _wait(0.45)
	var m: Dictionary = await _measure(secs)
	h.stop(0.02)
	await _wait(0.15)
	return m


## Captures `secs` of the Master output: RMS, peak, high-frequency ratio (first-difference energy / energy) and per-ear RMS.
func _measure(secs: float) -> Dictionary:
	cap.clear_buffer()
	await _wait(secs)
	var buf := cap.get_buffer(cap.get_frames_available())
	return _stats(buf, 0, buf.size())


func _stats(buf: PackedVector2Array, from: int, to: int) -> Dictionary:
	var e := 0.0
	var ed := 0.0
	var el := 0.0
	var er := 0.0
	var pk := 0.0
	var prev := 0.0
	var n := maxi(1, to - from)
	for i in range(from, to):
		var f := buf[i]
		var x := (f.x + f.y) * 0.5
		e += x * x
		el += f.x * f.x
		er += f.y * f.y
		var d := x - prev
		ed += d * d
		prev = x
		pk = maxf(pk, maxf(absf(f.x), absf(f.y)))
	return {"rms_db": _db(e / n), "hf_db": _db(ed / maxf(e, 1e-20)), "peak_db": 20.0 * log(maxf(pk, 1e-10)) / log(10.0),
		"l_db": _db(el / n), "r_db": _db(er / n), "frames": buf.size()}


func _db(p: float) -> float:
	return 10.0 * log(maxf(p, 1e-20)) / log(10.0)


## Energy of the tail (150..650 ms after the onset) relative to the first 80 ms, in dB.
func _tail(n: String, lpos: Vector3, yaw: float, spos: Vector3, dry: bool) -> float:
	_listener(lpos, yaw)
	await _wait(0.3) # listener zone update
	var e_tail := 0.0
	var e_head := 0.0
	for k in 3:
		audio._last.erase(n)
		cap.clear_buffer()
		audio.play(n, {"position": spos, "no_jitter": true, "dry": dry})
		await _wait(0.9)
		var buf := cap.get_buffer(cap.get_frames_available())
		var onset := -1
		for i in buf.size():
			if absf(buf[i].x) + absf(buf[i].y) > 0.002:
				onset = i
				break
		if onset < 0:
			continue
		var sr := AudioServer.get_mix_rate()
		var h: Dictionary = _stats(buf, onset, mini(buf.size(), onset + int(0.08 * sr)))
		var t: Dictionary = _stats(buf, mini(buf.size(), onset + int(0.15 * sr)), mini(buf.size(), onset + int(0.65 * sr)))
		e_head += pow(10.0, h.rms_db / 10.0)
		e_tail += pow(10.0, t.rms_db / 10.0)
	return _db(e_tail / maxf(e_head, 1e-20))


## RT60 of a reverb bus: a short tick played straight into the wet-only send bus, Schroeder backward integral of the
## captured output, T20 (-5..-25 dB) x 3.
func _rt60(bus: String) -> float:
	audio._last.erase("lock_wheel")
	cap.clear_buffer()
	audio.play("lock_wheel", {"bus": bus, "no_jitter": true, "volume": 3.0})
	await _wait(2.2)
	var buf := cap.get_buffer(cap.get_frames_available())
	var n := buf.size()
	if n < 1000:
		return 0.0
	var e := PackedFloat64Array()
	e.resize(n)
	var acc := 0.0
	for i in range(n - 1, -1, -1):
		var f := buf[i]
		acc += f.x * f.x + f.y * f.y
		e[i] = acc
	var start := 0
	while start < n and e[start] >= e[0] * 0.999:
		start += 1 # skip the silence before the onset
	var top := e[start]
	var i5 := -1
	var i25 := -1
	for i in range(start, n):
		var db := 10.0 * log(maxf(e[i], 1e-30) / top) / log(10.0)
		if i5 < 0 and db < -5.0:
			i5 = i
		if db < -25.0:
			i25 = i
			break
	if i5 < 0 or i25 < 0:
		return 0.0
	return 3.0 * float(i25 - i5) / AudioServer.get_mix_rate()


## Compressor + limiter: steady 997 Hz tone through the dry Music bus at several levels, output peak measured.
func _dynamics() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AudioServer.get_mix_rate()
	gen.buffer_length = 0.25
	var p := AudioStreamPlayer.new()
	p.stream = gen
	p.bus = &"Music"
	root.add_child(p)
	audio.set_master_volume(1.0)
	await _wait(0.3)
	# Music bus = +12 dB headroom x 0.8 category level: input level at Master = amp * db_to_linear(-12 + 12) * 0.8
	p.volume_db = -Buses.HEADROOM_DB
	p.play()
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	var phase := 0.0
	var inc := TAU * 997.0 / gen.mix_rate
	var curve := []
	for lvl in [-30.0, -20.0, -12.0, -6.0, 0.0, 6.0]:
		var amp := db_to_linear(lvl) / 0.8 # so the tone reaches Master at `lvl` dBFS peak
		var t_end := Time.get_ticks_msec() + 900
		var measured := false
		while Time.get_ticks_msec() < t_end:
			var n := pb.get_frames_available()
			if n > 0:
				var frames := PackedVector2Array()
				frames.resize(n)
				for i in n:
					var s := sin(phase) * amp
					phase = fmod(phase + inc, TAU)
					frames[i] = Vector2(s, s)
				pb.push_buffer(frames)
			if not measured and Time.get_ticks_msec() > t_end - 400:
				cap.clear_buffer()
				measured = true
			await process_frame
		var buf := cap.get_buffer(cap.get_frames_available())
		var st: Dictionary = _stats(buf, int(buf.size() / 3.0), buf.size())
		curve.append([lvl, st.peak_db])
	p.stop()
	p.queue_free()
	audio.set_master_volume(0.85)
	var txt := ""
	for c in curve:
		txt += " in %+.0f -> out %+.1f |" % [c[0], c[1]]
	print("[audio-test] dynamics (master 1.0 = -0.45 dB):", txt)
	# below threshold (-18): unity (minus the 0.95 mix level)
	check(absf(curve[0][1] - (curve[0][0] - 0.45)) < 1.0, "unity gain below the compressor threshold")
	# above threshold: compressed (slope < 0.6 between -6 and 0 dBFS in)
	var slope: float = (curve[4][1] - curve[3][1]) / 6.0
	check(slope > 0.15 and slope < 0.6, "glue compressor slope above threshold = %.2f" % slope)
	check(curve[5][1] <= -0.9 + 0.3, "hard limiter ceiling (+6 dBFS in -> %.2f dBFS out)" % curve[5][1])
