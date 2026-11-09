## Game orchestrator (autoload "Game"). Core owns it. Holds references to the live systems registered by main.gd.
## States: "loading" | "menu" | "playing" | "paused" | "caught" | "gameover" | "won"
extends Node

const NIGHTS_TOTAL := 3

var state := "loading"
var night := 1
var time_played := 0.0
var mode := "normal"        # normal (with La Gardienne) | explore (no monster) — chosen on the TV menu
var fear := 0.0              # smoothed 0..1 (from entity.fear)

# Registered by scenes/main.gd once built:
var main: Node = null        # scenes/main.gd root
var world: Node = null       # scripts/world/world.gd
var player: Node = null      # scripts/player/player.gd (CharacterBody3D)
var camera: Camera3D = null  # player camera
var entity: Node = null      # scripts/entity/gardienne.gd
var ui: Node = null          # scripts/ui/ui.gd (CanvasLayer)
var interaction: Node = null # scripts/game/interaction.gd
var inventory: Node = null   # scripts/game/inventory.gd
var puzzles: Node = null     # scripts/game/puzzles.gd
var garderie: Node = null    # scripts/garderie/garderie.gd (soft-play area west of the basement)
var debug := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	debug = OS.is_debug_build() or "--debug-game" in OS.get_cmdline_user_args()
	Events.ui_start.connect(start)
	Events.entity_caught.connect(on_caught)
	Events.game_win.connect(on_win)

func set_state(s: String) -> void:
	var prev := state
	state = s
	Events.game_state.emit(s, prev)

func start() -> void:
	if state == "playing": return
	time_played = 0.0
	var dbg = get_node_or_null("/root/DebugTools")
	if dbg and (dbg.get("args") as Dictionary).has("mode"): mode = str(dbg.args["mode"])
	# "explore": no monster — La Gardienne is switched off for the whole run (puzzles have fallbacks for that)
	if entity and is_instance_valid(entity) and entity.has_method("set_enabled"): entity.set_enabled(mode != "explore")
	set_state("playing")
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if puzzles and puzzles.has_method("start"): puzzles.start()

func pause() -> void:
	if state != "playing": return
	set_state("paused")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.set_paused(true)
	if ui and ui.has_method("show_pause"): await ui.show_pause()
	resume()

func resume() -> void:
	if state != "paused": return
	if ui and ui.has_method("hide_pause"): ui.hide_pause()
	Audio.set_paused(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_state("playing")

## Opens a UI modal (note, keypad): frees the mouse, awaits the callable, recaptures.
func modal(fn: Callable) -> Variant:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var r = await fn.call()
	if state == "playing": Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return r

func on_caught() -> void:
	if state != "playing": return
	set_state("caught")
	if ui: await ui.fade_to(1.0, 0.5)
	night += 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if night > NIGHTS_TOTAL:
		set_state("gameover")
		if ui: await ui.show_game_over()
		get_tree().reload_current_scene()
		night = 1
		return
	if ui: await ui.show_caught(night, NIGHTS_TOTAL)
	for n in [player, entity, world, puzzles, garderie]:
		if n and n.has_method("reset_after_caught"): n.reset_after_caught()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_state("playing")
	if ui: await ui.fade_to(0.0, 1.5)

func on_win() -> void:
	if state != "playing": return
	set_state("won")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ui:
		await ui.fade_to(1.0, 2.5)
		await ui.show_win(time_played, night, NIGHTS_TOTAL)
	night = 1
	get_tree().reload_current_scene()

func _process(delta: float) -> void:
	if state == "playing": time_played += delta
	var target := 0.0
	if entity and (state == "playing" or state == "caught"): target = float(entity.get("fear") if entity.get("fear") != null else 0.0)
	fear = lerpf(fear, target, clampf(delta * 2.5, 0.0, 1.0))
	Audio.set_fear(fear)

## Like most PC games: alt-tab / losing the window pauses the game (not during automated test runs).
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT or state != "playing": return
	var dbg = get_node_or_null("/root/DebugTools")
	if dbg and not (dbg.get("args") as Dictionary).is_empty(): return
	pause()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == "playing": pause()
		get_viewport().set_input_as_handled()
