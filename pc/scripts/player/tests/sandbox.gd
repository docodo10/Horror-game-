## Player test sandbox (player module only): same flow as scenes/main.gd (input map, Game registration, loading ->
## playing) but with the player-test world (test_world.gd) so the player can be exercised and rendered independently of
## the other modules' progress. Run:
##   headless:  godot --headless --path pc res://scripts/player/tests/sandbox.tscn -- --autostart --player-log
##   render:    (xvfb + vulkan) ... res://scripts/player/tests/sandbox.tscn -- --shot=/abs/x.png --cam=x,y,z,yaw,pitch
##              --flashlight --power=off   (DebugTools handles --shot/--cam/--flashlight/--power)
##   test:      godot --headless --fixed-fps 60 --path pc -s res://scripts/player/tests/movement_test.gd
extends Node3D

signal built

const TestWorld := preload("res://scripts/player/tests/test_world.gd")
const Player := preload("res://scripts/player/player.gd")
const Inventory := preload("res://scripts/game/inventory.gd")

var is_built := false

func _ready() -> void:
	InputSetup.setup()
	Game.main = self
	Game.set_state("loading")
	var world := TestWorld.new()
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
	await get_tree().process_frame
	is_built = true
	built.emit()
	var args := OS.get_cmdline_user_args()
	var auto := args.has("--autostart")
	var cams := ""
	var prefix := ""
	for a in args:
		if a.begins_with("--shot"):
			auto = true
		elif a.begins_with("--player-cams="):
			cams = a.substr(a.find("=") + 1)
		elif a.begins_with("--player-shots="):
			prefix = a.substr(a.find("=") + 1)
	if cams != "" and prefix != "":
		Game.start()
		await _capture_views(prefix, cams, args)
		get_tree().quit()
	elif auto:
		Game.start()
	elif not args.has("--player-test"):
		Game.set_state("menu")

## Several custom views in one run: --player-shots=/abs/prefix --player-cams="name:x,y,z,yawDeg,pitchDeg[:on|off][:bat=N]|..."
## (on/off = ceiling power for that view; bat = flashlight battery %). Flashlight given and on; --shot-frames=N to settle.
func _capture_views(prefix: String, cams: String, args: PackedStringArray) -> void:
	var frames := 40
	for a in args:
		if a.begins_with("--shot-frames="):
			frames = a.substr(a.find("=") + 1).to_int()
	await get_tree().process_frame
	Game.player.give_flashlight()
	Game.player.set_flashlight_on(true)
	for spec in cams.split("|", false):
		var parts := spec.split(":")
		if parts.size() < 2:
			continue
		var c := parts[1].split(",")
		if c.size() < 5:
			continue
		var power := true
		var battery := 100.0
		for i in range(2, parts.size()):
			if parts[i] == "off":
				power = false
			elif parts[i].begins_with("bat="):
				battery = parts[i].get_slice("=", 1).to_float()
		Game.world.set_power(power)
		Game.player.flashlight.battery = battery
		Game.player.teleport(Vector3(c[0].to_float(), c[1].to_float() + 0.02, c[2].to_float()), deg_to_rad(c[3].to_float()), deg_to_rad(c[4].to_float()))
		for f in frames:
			await get_tree().process_frame
		var path := "%s_%s.png" % [prefix, parts[0]]
		if DisplayServer.get_name() == "headless":
			print("[player-shot] (headless, not saved) ", path, " eye=", Game.player.eye_position())
			continue
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("[player-shot] ", path)
