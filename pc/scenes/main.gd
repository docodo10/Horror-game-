## Root of the game scene. Builds every system in order and registers them on the Game autoload. Core owns it.
extends Node3D

const World := preload("res://scripts/world/world.gd")
const Player := preload("res://scripts/player/player.gd")
const Gardienne := preload("res://scripts/entity/gardienne.gd")
const UI := preload("res://scripts/ui/ui.gd")
const Interaction := preload("res://scripts/game/interaction.gd")
const Inventory := preload("res://scripts/game/inventory.gd")
const Puzzles := preload("res://scripts/game/puzzles.gd")
const Quality := preload("res://scripts/render/quality.gd")
const SurfacesModule := preload("res://scripts/surfaces/surfaces.gd")
const GarderieModule := preload("res://scripts/garderie/garderie.gd")
const FearModule := preload("res://scripts/fear/fear_director.gd")
const AutoQuality := preload("res://scripts/render/auto_quality.gd")

func _ready() -> void:
	InputSetup.setup()
	Game.main = self
	Game.set_state("loading")
	var ui := UI.new(); ui.name = "UI"; add_child(ui); Game.ui = ui
	ui.show_loading(0.05, "Initialisation…")
	await get_tree().process_frame

	var world := World.new(); world.name = "World"; add_child(world); Game.world = world
	await world.build(func(p, t): ui.show_loading(0.05 + p * 0.75, t))
	# Hi-res surfaces (grime, wear, decals) over the exported materials; re-applied when the quality changes.
	SurfacesModule.apply(world, Settings.get_value("quality", "high"))
	# The soft-play "garderie" behind the new west-wall door (built before Interaction: it registers when that appears).
	ui.show_loading(0.82, "La garderie…")
	var garderie := GarderieModule.new(); garderie.name = "Garderie"; add_child(garderie); Game.garderie = garderie
	await garderie.build(world)
	world.garderie = garderie
	world.hide_spots.append_array(garderie.hide_spots)   # the closet stays first
	world.add_nav(garderie.nav_nodes, garderie.nav_links)
	Events.settings_changed.connect(_on_settings_changed)

	var inventory := Inventory.new(); inventory.name = "Inventory"; add_child(inventory); Game.inventory = inventory
	var player := Player.new(); player.name = "Player"; add_child(player); Game.player = player
	Game.camera = player.camera
	var entity := Gardienne.new(); entity.name = "Gardienne"; add_child(entity); Game.entity = entity
	await entity.build()
	var interaction := Interaction.new(); interaction.name = "Interaction"; add_child(interaction); Game.interaction = interaction
	var puzzles := Puzzles.new(); puzzles.name = "Puzzles"; add_child(puzzles); Game.puzzles = puzzles
	await puzzles.setup()
	# Fear director: heart-rate model, tension pacing, scares (finds itself at Game.main.get_node("FearDirector"))
	var fear := FearModule.new(); fear.name = "FearDirector"; add_child(fear); fear.setup()
	Quality.apply(Settings.get_value("quality", "high"))
	var aq := AutoQuality.new(); aq.name = "AutoQuality"; add_child(aq)
	await _warmup_tour(player, garderie)
	ui.show_loading(1.0, "Prêt")
	await get_tree().process_frame
	# User args come after "--" (e.g. `godot --path pc -- --autostart`).
	var autostart := false
	for a in OS.get_cmdline_user_args():
		if a == "--autostart" or a.begins_with("--shot"):
			autostart = true
	if autostart:
		Game.start()
	else:
		Game.set_state("menu")
		ui.show_menu()

func _on_settings_changed(key: String, value: Variant) -> void:
	if key == "quality" and Game.world:
		SurfacesModule.apply(Game.world, String(value))
		if Game.garderie and Game.garderie.has_method("recarve"): Game.garderie.recarve()

## Shader warm-up behind the loading screen: the camera visits every area for a few frames so the GPU compiles the
## pipelines of all materials, lights and shadows now instead of stuttering the first time each one appears in play.
## Skipped in headless runs (nothing is rendered there).
const WARMUP_BASEMENT := [[0.25, 0.0, 1.6, 0.0, -3.0], [2.3, 0.0, 1.6, 49.0, -2.0], [-0.6, 0.0, -0.4, 132.0, -14.0],
	[1.35, 0.0, -2.2, 0.0, -3.0], [-0.55, 0.0, -1.1, 0.0, -8.0], [2.2, 0.0, 0.15, -90.0, -18.0], [-3.0, 2.75, -2.1, 180.0, -25.0],
	[0.25, 0.0, 1.6, 180.0, 10.0]]
const WARMUP_GARDERIE := [[-4.1, 0.0, 2.05, 90.0, -4.0], [-11.5, 0.0, 2.4, 96.0, -6.0], [-17.9, -1.05, 2.7, 94.0, -11.0],
	[-18.3, -1.05, 3.9, 72.0, -9.0], [-19.0, -1.05, -4.2, 92.0, 6.0], [-23.7, -1.05, 5.6, 105.0, -28.0],
	[-27.6, -1.05, 9.8, 48.0, 6.0], [-26.0, -1.05, 1.2, 80.0, -5.0], [-34.6, -1.05, 6.8, 95.0, -18.0]]

func _warmup_tour(player: Node, garderie: Node) -> void:
	if DisplayServer.get_name() == "headless" or player == null or not player.has_method("teleport"): return
	for v in WARMUP_BASEMENT:
		player.teleport(Vector3(v[0], v[1], v[2]), deg_to_rad(v[3]), deg_to_rad(v[4]))
		for i in 3: await get_tree().process_frame
	if garderie != null and garderie.has_method("teleport_player"):
		for v in WARMUP_GARDERIE:
			garderie.teleport_player(Vector3(v[0], v[1], v[2]), deg_to_rad(v[3]), deg_to_rad(v[4]))
			for i in 3: await get_tree().process_frame
	var sp: Dictionary = Layout.SPAWN
	player.teleport(Vector3(float(sp.x), 0.0, float(sp.z)), float(sp.yaw), 0.0)
	for i in 2: await get_tree().process_frame
