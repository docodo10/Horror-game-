## Audio module — integration test in the real game flow: builds the game like scenes/main.gd (UI, World, Inventory,
## Player, Gardienne, Interaction, Puzzles), starts it, then runs the in-game audio self-test and checks the beds, the
## listener (player camera) and the upstairs door coupling.
##   godot --headless --path pc res://scripts/audio/tests/game_flow_test.tscn
extends Node3D

const World := preload("res://scripts/world/world.gd")
const Player := preload("res://scripts/player/player.gd")
const Gardienne := preload("res://scripts/entity/gardienne.gd")
const UI := preload("res://scripts/ui/ui.gd")
const Interaction := preload("res://scripts/game/interaction.gd")
const Inventory := preload("res://scripts/game/inventory.gd")
const Puzzles := preload("res://scripts/game/puzzles.gd")
const SelfTest := preload("res://scripts/audio/tests/audio_selftest.gd")

var failures: Array = []


func check(cond: bool, what: String) -> void:
	print("[audio-flow] %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		failures.append(what)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.setup()
	Game.main = self
	Game.set_state("loading")
	var ui := UI.new()
	ui.name = "UI"
	add_child(ui)
	Game.ui = ui
	await get_tree().process_frame
	var world := World.new()
	world.name = "World"
	add_child(world)
	Game.world = world
	await world.build(func(_p, _t): pass)
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	add_child(inventory)
	Game.inventory = inventory
	var player := Player.new()
	player.name = "Player"
	add_child(player)
	Game.player = player
	Game.camera = player.camera
	var entity := Gardienne.new()
	entity.name = "Gardienne"
	add_child(entity)
	Game.entity = entity
	await entity.build()
	var interaction := Interaction.new()
	interaction.name = "Interaction"
	add_child(interaction)
	Game.interaction = interaction
	var puzzles := Puzzles.new()
	puzzles.name = "Puzzles"
	add_child(puzzles)
	Game.puzzles = puzzles
	await puzzles.setup()
	await get_tree().process_frame
	Game.start()
	await get_tree().create_timer(1.0).timeout
	var st: Dictionary = Audio.stats()
	print("[audio-flow] after start: ", st)
	check(st.loaded == st.files and st.failed == 0, "library loaded (%d files)" % st.files)
	check(st.bed, "beds started with the game")
	check(Audio._has_listener and Audio._lpos.distance_to(Game.camera.global_position) < 0.01, "listener = player camera")
	check("room_tone" in st.loops and "clock_tick" in st.loops, "room tone + alarm clock beds")
	# upstairs door coupling (stub world has no door: closed)
	check(Audio._door_t == 0.0, "door closed when the world has no door")
	if "--audio-test" in OS.get_cmdline_user_args():
		# the Audio autoload runs the self-test itself (debug arg path): just give it time
		await get_tree().create_timer(12.0).timeout
	else:
		var r: Dictionary = await SelfTest.new().run(Audio, get_tree(), true)
		for f in r.failures:
			failures.append("selftest: " + f)
	# pause / resume through the Game state machine (the stub UI resumes by itself after 0.1 s)
	Game.pause()
	check(Audio._paused, "Game.pause() -> Audio.set_paused(true)")
	await get_tree().process_frame
	await get_tree().process_frame
	check(Audio._pause_hz < 20000.0, "pause low-pass engaging (%.0f Hz)" % Audio._pause_hz)
	await get_tree().create_timer(0.6).timeout
	check(not Audio._paused and Game.state == "playing", "Game.resume() -> Audio.set_paused(false)")
	print("[audio-flow] %s — %d failure(s)" % ["ALL PASSED" if failures.is_empty() else "FAILED", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
