## Game orchestrator (autoload "Game"). Core owns it. Holds references to the live systems registered by main.gd.
## States: "loading" | "menu" | "playing" | "paused" | "caught" | "gameover" | "won"
extends Node

const NIGHTS_TOTAL := 3

var state := "loading"
var night := 1
var time_played := 0.0
var mode := "normal"        # normal (with La Gardienne) | explore (no monster) | etage | dehors — chosen on the TV menu
## The chapters in story order: winning one leads straight on to the next (after the reload and its loading screen).
const CHAPTER_ORDER := ["normal", "etage", "dehors"]
var pending_mode := ""       # set by on_win(): the chapter scenes/main.gd starts by itself once the scene is rebuilt
var run_time := 0.0          # play time of the chapters already finished in this run (the last win screen shows the total)
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
var etage: Node = null       # scripts/etage/etage.gd (chapter 2: the ground floor of the house; mode "etage")
var dehors: Node = null      # scripts/dehors/dehors.gd (chapter 3: the yard, at night; mode "dehors")
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

var _busy := false           # start() / resume() is preparing the renderer: ignore a second call until it is done

## The quality preset was changed in the options: build its pipelines behind a black screen before play goes on
## (scenes/main.gd rehearse_again). Returns at once when there is nothing to prepare.
func _prepare_render() -> bool:
	if main == null or not main.has_method("needs_rehearsal") or not main.needs_rehearsal(): return false
	if ui and ui.has_method("fade_to"): ui.fade_to(1.0, 0.0)
	await main.rehearse_again()
	return true

func start() -> void:
	if state == "playing" or _busy: return
	_busy = true
	if await _prepare_render():
		if ui and ui.has_method("fade_to"): ui.fade_to(0.0, 1.6)     # the intro may fade in itself; this is the fallback
	_busy = false
	time_played = 0.0
	var dbg = get_node_or_null("/root/DebugTools")
	if pending_mode != "":           # the next chapter of a run in progress
		mode = pending_mode
		pending_mode = ""
	else:
		run_time = 0.0
		if dbg and (dbg.get("args") as Dictionary).has("mode"): mode = str(dbg.args["mode"])
	# "etage": chapter 2 — the level has its own threat, objectives and reset; the basement's puzzles never start
	var chapter2: bool = mode == "etage" and etage != null and is_instance_valid(etage)
	var chapter3: bool = mode == "dehors" and dehors != null and is_instance_valid(dehors)
	# "explore": no monster — La Gardienne is switched off for the whole run (puzzles have fallbacks for that)
	if entity and is_instance_valid(entity) and entity.has_method("set_enabled"): entity.set_enabled(mode == "normal")
	set_state("playing")
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if chapter2: etage.begin()
	elif chapter3: dehors.begin()
	elif puzzles and puzzles.has_method("start"): puzzles.start()

func pause() -> void:
	if state != "playing": return
	set_state("paused")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.set_paused(true)
	if ui and ui.has_method("show_pause"): await ui.show_pause()
	resume()

func resume() -> void:
	if state != "paused" or _busy: return
	_busy = true
	if ui and ui.has_method("hide_pause"): ui.hide_pause()
	# the tree is still paused here: the game stands still behind the black screen while the renderer is prepared
	if await _prepare_render():
		if ui and ui.has_method("fade_to"): ui.fade_to(0.0, 0.6)
	_busy = false
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
	for n in [player, entity, world, puzzles, garderie, etage, dehors]:      # (the chapters last: each puts the player back at ITS start)
		if n and n.has_method("reset_after_caught"): n.reset_after_caught()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_state("playing")
	if ui: await ui.fade_to(0.0, 1.5)

func on_win() -> void:
	if state != "playing": return
	set_state("won")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var nxt := next_mode()
	var total := run_time + time_played
	if ui:
		await ui.fade_to(1.0, 2.5)
		await ui.show_win(time_played if nxt != "" else total, night, NIGHTS_TOTAL, mode, nxt)
	night = 1
	run_time = total if nxt != "" else 0.0
	pending_mode = nxt
	get_tree().reload_current_scene()

## The chapter that follows the one being played ("" after the last one, or when its level was not built).
func next_mode() -> String:
	var i := CHAPTER_ORDER.find("normal" if mode == "explore" else mode)
	if i < 0 or i + 1 >= CHAPTER_ORDER.size(): return ""
	var nxt: String = CHAPTER_ORDER[i + 1]
	var level: Node = etage if nxt == "etage" else dehors
	return nxt if level != null and is_instance_valid(level) else ""

func _process(delta: float) -> void:
	if state == "playing": time_played += delta
	var target := 0.0
	if entity and (state == "playing" or state == "caught"): target = float(entity.get("fear") if entity.get("fear") != null else 0.0)
	if etage and etage.get("active") == true and state == "playing": target = maxf(target, float(etage.get("fear")))
	if dehors and dehors.get("active") == true and state == "playing": target = maxf(target, float(dehors.get("fear")))
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
