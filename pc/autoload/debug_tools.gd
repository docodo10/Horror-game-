## Command-line test hooks (autoload "DebugTools"). Core owns it; other modules may ADD args here in their own section.
## Usage (after `--`): --autostart --shot=/abs/file.png --shot-frames=90 --cam=x,y,z,yawDeg,pitchDeg --power=off
##   --flashlight --quality=low|medium|high|ultra --stage=dark|power|code|escape --quit-after-shot
##   --shots=/abs/prefix --views=spawn,stairs,... (multi-view capture using VIEWS below)
extends Node

const VIEWS := {
	"spawn": [0.25, 0.0, 1.6, 0.0, -3.0],
	"stairs": [2.3, 0.0, 1.6, 49.0, -2.0],
	"kids": [-0.6, 0.0, -0.4, 132.0, -14.0],
	"nook": [1.35, 0.0, -2.2, 0.0, -3.0],
	"tv": [-0.55, 0.0, -1.1, 0.0, -8.0],
	"console": [2.2, 0.0, 0.15, -90.0, -18.0],
	"landing": [-3.0, 2.75, -2.1, 180.0, -25.0],
}

var args := {}
var _frames := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("quality"): Settings.values["quality"] = args["quality"]
	if args.has("autostart") or args.has("shot") or args.has("shots"):
		Events.game_state.connect(_on_state)

func _on_state(s: String, _p: String) -> void:
	if s != "playing": return
	await get_tree().process_frame
	if args.has("power") and Game.world: Game.world.set_power(args["power"] != "off")
	if args.has("stage") and Game.puzzles and Game.puzzles.has_method("debug_goto"): Game.puzzles.debug_goto(args["stage"])
	if args.has("flashlight") and Game.player:
		Game.player.give_flashlight(); Game.player.set_flashlight_on(true)
	if args.has("cam") and Game.player: _cam(args["cam"].split(","))
	if args.has("shot"):
		await _wait(int(args.get("shot-frames", "90")))
		_save(args["shot"])
		get_tree().quit()
	elif args.has("shots"):
		for v in args.get("views", "spawn").split(","):
			if VIEWS.has(v):
				_cam(PackedStringArray(VIEWS[v].map(func(x): return str(x))))
				await _wait(int(args.get("shot-frames", "60")))
				_save("%s_%s.png" % [args["shots"], v])
		get_tree().quit()

func _cam(c: PackedStringArray) -> void:
	if c.size() < 3: return
	var yaw := deg_to_rad(float(c[3])) if c.size() > 3 else 0.0
	var pitch := deg_to_rad(float(c[4])) if c.size() > 4 else 0.0
	Game.player.teleport(Vector3(float(c[0]), float(c[1]) + 0.02, float(c[2])), yaw, pitch)

func _wait(n: int) -> void:
	for i in n: await get_tree().process_frame

func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] ", path, " ", img.get_size())
