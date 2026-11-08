## UI module visual check: the TV menu on the REAL dresser TV. Assembles the exported level (res://assets/generated,
## MetaUtil — exporter reference loader) with stand-in menu lighting (dim warm ceiling bulb, cool TV light, glow), registers
## a minimal Game.world {tv, lighting}, builds the UI, shows the menu and saves screenshots. Needs a renderer:
##   scripts/ui/tests/ui_render.sh 1280x720 res://scripts/ui/tests/menu_on_tv.gd --out=/abs/prefix [--pages=main,options]
extends SceneTree

const MetaUtil := preload("res://assets/generated/meta_util.gd")

var _args := {}
var _root: Node3D

class FakeLighting extends Node3D:
	var tv_light: OmniLight3D
	func set_tv_light(on: bool, intensity := 1.0) -> void:
		if tv_light:
			tv_light.light_energy = 1.1 * intensity if on else 0.0

class FakeWorld extends Node3D:
	var tv: Node3D = null
	var lighting: Node = null
	var power := true

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _save(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s_%s.png" % [_args.get("out", "/tmp/menu_on_tv"), name_]
	img.save_png(path)
	print("[menu_on_tv] ", path)

func _run() -> void:
	var game: Node = root.get_node("Game")
	var world := FakeWorld.new()
	world.name = "World"
	root.add_child(world)
	var meta := MetaUtil.load_json("res://assets/generated/level_meta.json")
	var ctx := MetaUtil.assemble(world, meta)
	for e in ctx.errors:
		printerr("assemble: ", e)
	world.tv = ctx.instances.get("tv")
	# stand-in menu lighting (the look module owns the real one)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.45, 0.4)
	e.ambient_light_energy = 0.08
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 0.9
	e.ssao_enabled = true
	env.environment = e
	world.add_child(env)
	var bulb := OmniLight3D.new()
	bulb.position = Vector3(0.25, 2.2, 0.35)
	bulb.light_color = Color(1.0, 0.78, 0.52)
	bulb.light_energy = 0.35
	bulb.omni_range = 7.0
	bulb.shadow_enabled = true
	world.add_child(bulb)
	var lighting := FakeLighting.new()
	world.add_child(lighting)
	var tvl := OmniLight3D.new()
	tvl.position = Vector3(-0.55, 1.47, -2.05)
	tvl.light_color = Color(0.62, 0.72, 1.0)
	tvl.light_energy = 0.0
	tvl.omni_range = 3.5
	tvl.shadow_enabled = true
	lighting.add_child(tvl)
	lighting.tv_light = tvl
	world.lighting = lighting
	game.world = world
	var ui: Node = (load("res://scripts/ui/ui.gd") as GDScript).new()
	root.add_child(ui)
	game.ui = ui
	await _frames(2)
	game.set_state("menu")
	ui.show_menu()
	print("[menu_on_tv] TV model found: ", ui.tv.found_model, " glass centre ", ui.tv.center)
	for page in String(_args.get("pages", "main")).split(","):
		ui.goto_page(ui.tv.screen, page, "", false)
		await _frames(int(_args.get("frames", "16")))
		await _save(page)
	quit()
