## Look-dev scene root (test only): scenes/main.gd's build order WITHOUT the garderie, for basement renders under the
## software renderer (lavapipe keeps every pipeline / texture in system RAM: the full game with the garderie needs ~13 GB,
## which the shared test machine cannot always give). Used by lookdev.gd with --lookdev-no-garderie.
extends Node3D

const World := preload("res://scripts/world/world.gd")
const Player := preload("res://scripts/player/player.gd")
const Gardienne := preload("res://scripts/entity/gardienne.gd")
const UI := preload("res://scripts/ui/ui.gd")
const Interaction := preload("res://scripts/game/interaction.gd")
const Inventory := preload("res://scripts/game/inventory.gd")
const Puzzles := preload("res://scripts/game/puzzles.gd")
const QualityScript := preload("res://scripts/render/quality.gd")
const SurfacesModule := preload("res://scripts/surfaces/surfaces.gd")

func _ready() -> void:
	InputSetup.setup()
	Game.main = self
	Game.set_state("loading")
	var ui := UI.new(); ui.name = "UI"; add_child(ui); Game.ui = ui
	await get_tree().process_frame
	var world := World.new(); world.name = "World"; add_child(world); Game.world = world
	await world.build(func(p, t): ui.show_loading(0.05 + p * 0.75, t))
	SurfacesModule.apply(world, Settings.get_value("quality", "high"))
	var inventory := Inventory.new(); inventory.name = "Inventory"; add_child(inventory); Game.inventory = inventory
	var player := Player.new(); player.name = "Player"; add_child(player); Game.player = player
	Game.camera = player.camera
	var entity := Gardienne.new(); entity.name = "Gardienne"; add_child(entity); Game.entity = entity
	await entity.build()
	var interaction := Interaction.new(); interaction.name = "Interaction"; add_child(interaction); Game.interaction = interaction
	var puzzles := Puzzles.new(); puzzles.name = "Puzzles"; add_child(puzzles); Game.puzzles = puzzles
	await puzzles.setup()
	QualityScript.apply(Settings.get_value("quality", "high"))
	await get_tree().process_frame
	var autostart := false
	for a in OS.get_cmdline_user_args():
		if a == "--autostart" or a.begins_with("--shot"): autostart = true
	if autostart:
		Game.start()
	else:
		Game.set_state("menu")
		ui.show_menu()
