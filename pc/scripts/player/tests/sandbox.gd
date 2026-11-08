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
	for a in args:
		if a.begins_with("--shot"):
			auto = true
	if auto:
		Game.start()
	elif not args.has("--player-test"):
		Game.set_state("menu")
