## La Gardienne lookdev (loaded by lookdev.gd). Assembles the REAL basement from the exporter's level.glb + level_meta.json
## (assets/generated/meta_util.gd), stand-in lights calibrated like the player module's sandbox (warm ceiling lamp 1.6,
## AgX exposure 1, flashlight 13.37 / 24° / inverse square at the camera), then poses the real entity with debug_place()
## / debug_jumpscare() and saves one screenshot per view. Needs a renderer (xvfb + Vulkan), see lookdev.gd.
extends Node

const MetaUtil := preload("res://assets/generated/meta_util.gd")
const Entity := preload("res://scripts/entity/gardienne.gd")

## view: cam [x, y(eye), z, yawDeg, pitchDeg], her [x, z, yawDeg (null = face the camera), mode, t], light: lit | dark,
## flash: torch on, jump: frozen jumpscare time (her placement ignored)
const VIEWS := {
	"lit": {"cam": [0.25, 1.62, 0.15, 0.0, -3.0], "her": [0.25, -1.95, null, "walk", 0.45], "light": "lit", "flash": false},
	"lit_close": {"cam": [0.4, 1.68, -0.75, 8.0, 2.0], "her": [0.2, -1.95, null, "search", 1.2], "light": "lit", "flash": false},
	"lit_side": {"cam": [2.3, 1.35, -1.0, 90.0, 0.0], "her": [0.5, -1.0, -90.0, "chase", 0.2], "light": "lit", "flash": false},
	"stairs_duck": {"cam": [-1.6, 1.3, 2.4, 50.6, 9.4], "her": [-3.0, 1.22, 0.0, "stairs_duck", 0.3], "light": "lit", "flash": false},
	"dark": {"cam": [0.25, 1.62, 0.3, 0.0, -5.0], "her": [0.05, -1.95, null, "walk", 0.95], "light": "dark", "flash": true},
	"dark_close": {"cam": [0.3, 1.62, -0.75, 0.0, 2.0], "her": [0.2, -1.95, null, "search", 2.2], "light": "dark", "flash": true},
	"stare": {"cam": [0.3, 1.62, -0.15, 0.0, -1.0], "her": [0.25, -1.95, null, "idle", 1.0], "light": "dark", "flash": true, "look": "camera"},
	"jump": {"cam": [0.25, 1.62, -0.6, 0.0, 0.0], "her": [0.25, -1.6, null, "chase", 0.0], "light": "dark", "flash": true, "jump": 0.45},
	"jump_lit": {"cam": [0.25, 1.62, -0.6, 0.0, 0.0], "her": [0.25, -1.6, null, "chase", 0.0], "light": "lit", "flash": false, "jump": 0.6},
}

var args := {}
var cam: Camera3D
var env: Environment
var lamp: OmniLight3D
var moon: SpotLight3D
var flash: SpotLight3D
var entity: Entity
var player: Node3D

class LookPlayer extends Node3D:
	var camera: Camera3D
	var hidden := false
	var enabled := true
	var camera_override := false
	var flashlight := {"has": true, "on": false, "battery": 100.0, "light": null}
	func get_visibility() -> float: return 0.0
	func eye_position() -> Vector3: return camera.global_position

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()

func _run() -> void:
	var level := Node3D.new()
	level.name = "Level"
	add_child(level)
	var meta := MetaUtil.load_json("res://assets/generated/level_meta.json")
	var ctx := MetaUtil.assemble(level, meta)
	for e in ctx.errors: printerr("assemble: ", e)
	_lights()
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.03
	add_child(cam)
	cam.current = true
	flash = SpotLight3D.new()
	flash.light_color = Color(1.0, 0.941176, 0.862745)
	flash.spot_range = 18.0
	flash.spot_angle = rad_to_deg(0.42)
	flash.spot_attenuation = 2.0
	flash.spot_angle_attenuation = 0.4
	flash.shadow_enabled = true
	flash.position = Vector3(0.15, -0.16, 0.02)
	cam.add_child(flash)
	player = LookPlayer.new()
	player.name = "Player"
	player.camera = cam
	player.flashlight.light = flash
	add_child(player)
	Game.camera = cam
	Game.player = player
	Game.set_state("loading")
	entity = Entity.new()
	entity.name = "Gardienne"
	add_child(entity)
	Game.entity = entity
	await entity.build()
	Game.set_state("playing")
	var views := String(args.get("views", "lit,dark,jump")).split(",")
	var frames := int(args.get("frames", "10"))
	for v in views:
		if not VIEWS.has(v): continue
		await _view(v, VIEWS[v], frames)
	get_tree().quit()

func _lights() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.3, 0.28)
	env.ambient_light_energy = 0.08
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.02
	env.volumetric_fog_enabled = args.has("fog")
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.85, 0.82, 0.78)
	env.volumetric_fog_length = 16.0
	env.volumetric_fog_anisotropy = 0.35
	we.environment = env
	add_child(we)
	lamp = OmniLight3D.new()
	lamp.position = Vector3(Layout.FAN.x, 1.92, Layout.FAN.z)   # under the fan's glass bowl (web ceilingLight y 1.919)
	lamp.light_color = Color(1.0, 0.78, 0.52)
	lamp.light_energy = 1.6
	lamp.omni_range = 9.0
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = true
	add_child(lamp)
	moon = SpotLight3D.new()
	moon.light_color = Color(0.68, 0.77, 1.0)
	moon.light_energy = 1.2
	moon.spot_range = 30.0
	moon.spot_angle = 8.0
	moon.shadow_enabled = true
	add_child(moon)
	moon.global_position = Vector3(4.82, 9.47, 14.38)
	moon.look_at(Vector3(1.79, 0.0, -0.46))

func _view(vname: String, v: Dictionary, frames: int) -> void:
	var lit := String(v.light) == "lit"
	lamp.visible = lit
	env.ambient_light_energy = 0.08 if lit else 0.012
	moon.visible = not lit
	var on: bool = v.flash
	flash.light_energy = 13.37 if on else 0.0
	flash.visible = on
	player.flashlight.on = on
	var c: Array = v.cam
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(c[4]), deg_to_rad(c[3]), 0.0)), Vector3(c[0], c[1], c[2]))
	player.global_position = Vector3(c[0], 0.0, c[2])
	var h: Array = v.her
	var p := Vector3(h[0], 0.0, h[1])
	p.y = Layout.ground_height_at(p.x, p.z, 0.5 if String(h[3]).begins_with("stairs") else 0.0)
	var yaw: float = atan2(c[0] - p.x, c[2] - p.z) if h[2] == null else deg_to_rad(h[2])
	entity.debug_place(p, yaw, String(h[3]), float(h[4]), v.get("look"))
	if v.has("jump"):
		await get_tree().process_frame
		entity.debug_jumpscare(float(v.jump))
	for i in frames: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := "%s_%s.png" % [args.get("out", "/tmp/gardienne"), vname]
	if img == null:
		print("[lookdev] (no renderer) view %s state=%s face=%s cam=%s" % [vname, entity.state, entity.face_position(), cam.global_position])
	else:
		img.save_png(out)
		print("[lookdev] saved ", out, " state=", entity.state)
	if v.has("jump"):
		entity.reset_after_caught()
		player.camera_override = false
		await get_tree().process_frame
