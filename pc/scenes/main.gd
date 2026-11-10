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
	# (--no-garderie: test runs of the house alone; the software renderer of the test machine runs out of memory otherwise)
	if not DebugTools.args.has("no-garderie"):
		var garderie := GarderieModule.new(); garderie.name = "Garderie"; add_child(garderie); Game.garderie = garderie
		await garderie.build(world)
		world.garderie = garderie
		world.hide_spots.append_array(garderie.hide_spots)   # the closet stays first
		world.add_nav(garderie.nav_nodes, garderie.nav_links)
		if garderie.has_method("apply_quality"): garderie.apply_quality(str(Settings.get_value("quality", "high")))
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
	if entity.has_method("apply_quality_now"): entity.apply_quality_now()   # final materials before the rehearsal below
	var aq := AutoQuality.new(); aq.name = "AutoQuality"; add_child(aq)
	await _calibrate_and_warm_up(aq)
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
		if Game.garderie and Game.garderie.has_method("apply_quality"): Game.garderie.apply_quality(String(value))

## Behind the loading screen a temporary camera looks at the game (the TV menu / idle camera own the player camera
## until the game starts):
##  1. auto quality times real frames of the heaviest views and settles on a preset (scripts/render/auto_quality.gd);
##  2. dress rehearsal: from a stop in every area the camera looks in every direction with occlusion culling off, once
##     without and once with La Gardienne in view, so the GPU builds every pipeline now and not in the middle of play.
##     Measured with tools/hitch_hunt.gd — what froze a frame without it: the first seconds of play, the first quick
##     turn, the first highlighted object, the first prop a scare spawns, and above all her first appearance (her skin
##     uses subsurface scattering, which switches the whole frame to another set of pipelines).
## Skipped in headless runs (nothing is rendered there).
const CALIB_VIEWS := [[0.25, 1.6, 1.6, 0.0, -3.0], [-17.9, 0.55, 2.7, 94.0, -11.0]]
## x, eye y, z of the rehearsal stops: basement, nook, closet side, stairs, landing, upper hall, corridor, vestibule,
## hall entry / centre / far end, play frame deck.
const WARMUP_STOPS := [[0.4, 1.6, 0.2], [1.4, 1.6, -3.6], [-2.0, 1.6, -1.4], [-3.0, 2.8, 0.2], [-3.0, 4.35, -2.3],
	[-3.0, 4.35, -3.6], [-7.5, 1.6, 2.1], [-14.0, 1.6, 2.1], [-19.5, 0.55, 2.5], [-26.0, 0.55, 2.0], [-33.0, 0.55, 6.0],
	[-28.5, 2.4, 3.0]]
## yaw, pitch (degrees) looked at from each stop: four sides, then up and down.
const WARMUP_DIRS := [[0.0, -12.0], [90.0, -12.0], [180.0, -12.0], [270.0, -12.0], [45.0, 62.0], [225.0, -62.0]]

func _tour_view(cam: Camera3D, v: Array) -> void:
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(v[4]), deg_to_rad(v[3]), 0.0)), Vector3(v[0], v[1], v[2]))

func _refresh_zone() -> void:
	if Game.garderie and Game.garderie.has_method("refresh_zone"): Game.garderie.refresh_zone()

func _calibrate_and_warm_up(aq: Node) -> void:
	if DisplayServer.get_name() == "headless" or DebugTools.args.has("no-warmup"): return
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "TourCamera"
	cam.fov = float(Settings.get_value("fov", 54.0))
	cam.near = 0.05
	cam.far = 80.0
	add_child(cam)
	cam.make_current()
	await aq.calibrate(func(i: int) -> void:
		_tour_view(cam, CALIB_VIEWS[i])
		_refresh_zone(), CALIB_VIEWS.size())
	await _dress_rehearsal(cam)
	if prev != null and is_instance_valid(prev): prev.make_current()
	cam.queue_free()
	await get_tree().process_frame
	_refresh_zone()                      # back in the house: its rooms are shown again before play, not during it
	for i in 3: await get_tree().process_frame

func _dress_rehearsal(cam: Camera3D) -> void:
	var vp := get_viewport()
	var occ := vp.use_occlusion_culling
	vp.use_occlusion_culling = false     # draw what stands behind doors and inside furniture too
	cam.fov = 75.0
	# the looked-at highlight on every interactable; visuals that only show later; particles; scare props
	var hl: Array = Game.interaction.prewarm_begin() if Game.interaction and Game.interaction.has_method("prewarm_begin") else []
	var shown: Array = []
	if Game.world:
		# hidden meshes, and hidden groups such as what closed drawers and boxes hold (the items the player takes later)
		for n in (Game.world as Node).find_children("*", "Node3D", true, false):
			var n3 := n as Node3D
			if not n3.visible and not (n3 is Light3D):
				n3.visible = true
				shown.append(n3)
		var uh = Game.world.get("upper_hall")
		if uh is Node3D and not (uh as Node3D).visible:
			(uh as Node3D).visible = true
			shown.append(uh)
	var parts: Array = []
	for n in find_children("*", "GPUParticles3D", true, false):
		var gp := n as GPUParticles3D
		if not gp.emitting:
			gp.emitting = true
			parts.append(gp)
	var props := Node3D.new()            # the kind of props scares spawn (primitive meshes with a plain material)
	add_child(props)
	for m in [SphereMesh.new(), BoxMesh.new()]:
		var mi := MeshInstance3D.new()
		(m as PrimitiveMesh).material = StandardMaterial3D.new()
		mi.mesh = m
		mi.scale = Vector3.ONE * 0.1
		props.add_child(mi)
	var ent = Game.entity
	var has_ent: bool = ent != null and ent.has_method("debug_place") and ent.has_method("debug_release")
	var shot := String(DebugTools.args.get("warmup-shot", ""))
	if shot != "" and Game.ui and Game.ui.get("crt") is CanvasItem: (Game.ui.get("crt") as CanvasItem).visible = false
	var si := 0
	for st in WARMUP_STOPS:
		var di := 0
		for d in WARMUP_DIRS:
			_tour_view(cam, [st[0], st[1], st[2], d[0], d[1]])
			if di == 0: _refresh_zone()
			var fwd := -cam.global_transform.basis.z
			var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
			props.global_position = cam.global_position + fwd * 1.2
			if has_ent: ent.debug_release()
			await get_tree().process_frame
			if has_ent:
				# La Gardienne 2.2 m ahead, facing the camera: the frame switches to its subsurface-scattering pipelines
				var at := cam.global_position + flat * 2.2
				ent.debug_place(Vector3(at.x, st[1] - 1.6, at.z), atan2(-flat.x, -flat.z), "walk" if di % 2 == 0 else "chase", -1.0, "camera")
				if ent.has_method("prewarm_frame"): ent.prewarm_frame(0.05)
			await get_tree().process_frame
			if shot != "" and di < 2 and si in [0, 9]:
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png("%s_%d_%d.png" % [shot, si, di])
			di += 1
		si += 1
	if has_ent: ent.debug_release()
	props.queue_free()
	for gp in parts:
		if is_instance_valid(gp): (gp as GPUParticles3D).emitting = false
	for n in shown:
		if is_instance_valid(n): (n as Node3D).visible = false
	if Game.interaction and Game.interaction.has_method("prewarm_end"): Game.interaction.prewarm_end(hl)
	if shot != "" and Game.ui and Game.ui.get("crt") is CanvasItem: (Game.ui.get("crt") as CanvasItem).visible = true
	vp.use_occlusion_culling = occ
