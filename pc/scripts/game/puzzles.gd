## Puzzles (gameplay module) — port of src/game/Puzzles.js. Owns the whole scenario: objectives, notes, code generation, every
## interactable, scripted beats (light blowout, rocking chair, first visit after the breaker, aggression after the key), ambient
## scares, hints, hiding, win condition. See ARCHITECTURE.md §5 (web) / ARCHITECTURE_PC.md §4.
## Public API (keep): setup() (await), start(), stage: String, code: String, found: Dictionary, debug_goto(stage), reset_after_caught()
##   stage: "intro" | "dark" | "power" | "code" | "escape" | "win"     code: 4 digits 1..9 (debug: --code=1234 with Game.debug)
##   found: {duck, horse, clock, tv} -> digit String or null
## Additions: flags: Dictionary (progress flags), stats {code_attempts, rattles}, stage_time, objective() -> String, tension() -> 0..1,
##   STAGES, NOTES, NOISE (loudness table), CLUES.
## Emits: Events.stage_changed(stage, prev), Events.noise(position, loudness, source), Events.game_win.
## Uses (all optional, called defensively): Game.world {handles, items, clues, tv, hide_spots, power, set_power, set_clue_digits,
##   lighting {flicker, blowout}, rock_chair}, Game.player {flashlight, give_flashlight, set_flashlight_on, hidden, enter_hide,
##   exit_hide}, Game.entity {state, active, summon, set_aggression}, Game.ui {subtitle, set_objective, alert, set_clues, set_night,
##   fade_to, show_note, show_keypad, is_modal_open}, Game.inventory, Game.interaction, Audio.play.
## Time: scripted waits/tweens advance with the game (only while Game.state == "playing"; they keep running behind a note/keypad).
extends Node

const STAGES := ["intro", "dark", "power", "code", "escape", "win"]
const CLUES := ["duck", "horse", "clock", "tv"]
const NBSP := "\u00a0"
const LAYER_WORLD := 1
const LAYER_INTERACT := 2

const NOTES := {
	"note1": {
		"title": "Note pliée", "style": "note",
		"text": "Reste en bas. Pas un bruit.\nElle a le sommeil léger…\n\nLa clé de la porte d’en haut est dans le coffret de Léa.\n\n— M.",
	},
	"note2": {
		"title": "Dessin d’enfant", "style": "child",
		"text": "MA GARDIENNE\n\nElle chante quand elle te cherche.\nSi tu l’entends, cours dans le placard sous l’escalier.\nElle regarde jamais dedans…\nsauf si elle te voit y aller.\n\nLéa, 7 ans",
	},
	"note3": {
		"title": "Coupure de journal", "style": "newspaper",
		"text": "LE COURRIER DU LAC — 14 novembre 1994\n\nDEUX ENFANTS RETROUVÉS DANS UN SOUS-SOL\n\n"
			+ "Léa, 7 ans, et son frère Mathis, 10 ans, ont été retrouvés hier, enfermés depuis trois jours dans le sous-sol "
			+ "de la maison familiale. Leur gardienne, une femme de 61 ans, reste introuvable.\n\n"
			+ "« Elle disait qu’elle nous protégeait de dehors. Elle chantait toute la nuit, en haut », a raconté la fillette.\n\n"
			+ "La maison est inhabitée depuis.",
	},
	"box": {
		"title": "Le coffret de Léa", "style": "child",
		"text": "MON COFFRET SECRET\nTOUCHE PAS !!\n\nLe code, dans l’ordre :\n1. le canard\n2. le cheval\n3. l’horloge\n4. la télé\n\n(chaque chose cache un chiffre)\n\nLéa",
	},
}

const CLUE_HINTS := {
	"duck": "Le canard en plastique, près du coin des enfants… Et en dessous ?",
	"horse": "Le petit cheval, sur l’étagère… Peut-être sous son socle.",
	"clock": "La grande horloge est arrêtée. Sur quelle heure ?",
	"tv": "La télé… Il faut du courant. Mais elle va faire du bruit.",
}

## Ambient random scares (recorded samples). min_t = tension needed before it can play, w = weight.
const SCARES := [
	{"name": "house_creak", "min_t": 0.0, "w": 3.0, "vol": 0.85},
	{"name": "stair_creak", "min_t": 0.1, "w": 2.0, "vol": 0.8},
	{"name": "ceiling_walk", "min_t": 0.2, "w": 2.0, "vol": 0.9},
	{"name": "knock_wall", "min_t": 0.4, "w": 1.4, "vol": 0.75},
	{"name": "ceiling_steps", "min_t": 0.45, "w": 1.2, "vol": 0.8},
	{"name": "window_tap", "min_t": 0.55, "w": 0.6, "vol": 0.6},
	{"name": "whisper", "min_t": 0.6, "w": 0.8, "vol": 0.55, "sub": "(Un chuchotement, tout près…)"},
	{"name": "giggle", "min_t": 0.7, "w": 0.6, "vol": 0.5, "sub": "(Un rire d’enfant…)"},
]
const STAGE_TENSION := {"intro": 0.0, "dark": 0.2, "power": 0.35, "code": 0.55, "escape": 0.85, "win": 0.0}

## Noise loudness table (web ARCHITECTURE.md §4 — the player uses the step values, gameplay the others). The entity hears these.
const NOISE := {
	"crouch_step": 0.03, "walk_carpet": 0.10, "walk_stairs": 0.18, "sprint_step": 0.45, "bump": 0.3,
	"drawer": 0.15, "closet": 0.12, "door_rattle": 0.35, "door_unlock": 0.35, "breaker": 1.0, "tv": 0.55,
	"box": 0.2, "lock_fail": 0.15, "flashlight_click": 0.02, "window": 0.1, "rummage": 0.06,
}

const GNOME_NAMES := ["extra_gnome", "gnome", "garden_gnome"]

class Waiter extends RefCounted:
	signal done
	var t := 0.0
	var fired := false

class TweenJob extends RefCounted:
	signal done
	var t := 0.0
	var dur := 1.0
	var fn := Callable()
	var fired := false

var stage := "intro"
var code := "0000"
var found := {"duck": null, "horse": null, "clock": null, "tv": null}
var flags := {
	"note1": false, "blackout": false, "flashlight": false, "breaker": false, "summoned": false, "summon_done": false,
	"box_note": false, "box_open": false, "key": false, "door_unlocked": false, "door_opened": false, "won": false,
	"rocked": false, "gnome_moved": false,
}
var stage_time := 0.0
var stats := {"code_attempts": 0, "rattles": 0}
var interaction: Node = null

var _started := false
var _clock := 0.0                  # game time (advances like the waits)
var _waits: Array = []
var _tweens: Array = []
var _gen := 0
var _taken := {}
var _seen := {}
var _obj_text := ""
var _obj_set := false
var _obj_sends := 0
var _idle := 0.0
var _hint_n := 0
var _flick_t := 7.0
var _tv_noise_t := 0.0
var _tv_look := 0.0
var _look_t := 0.0
var _scare_t := 40.0
var _last_scare := ""
var _summon_t := 0.0
var _summon_saw_active := false
var _win_t := INF
var _blowout_pending := false
var _proxy_root: Node3D = null
var _rock_pos := Vector3.ZERO
var _rock_node: Node3D = null
var _rock_rids: Array[RID] = []
var _tilting := {}
var _missing: Array[String] = []
var _los_query := PhysicsRayQueryParameters3D.new()

# =================================================================== lifecycle

func setup() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	interaction = Game.interaction
	_flick_t = randf_range(5.0, 9.0)
	var rp: Array = Layout.PROPS["rockingChair"]["pos"]
	_rock_pos = Vector3(rp[0], 0.7, rp[2])
	_proxy_root = Node3D.new()
	_proxy_root.name = "InteractProxies"
	add_child(_proxy_root)
	code = _make_code()
	var d := _digits()
	_world_call("set_clue_digits", [d])
	var tv = _tv()
	if tv != null and tv.has_method("set_digit"): tv.call("set_digit", d["tv"])
	if interaction != null and is_instance_valid(interaction):
		_register_all()
		if interaction.has_method("flush_proxies"): interaction.call("flush_proxies")
	else:
		push_warning("[puzzles] no Game.interaction: nothing is interactable")
	Events.power_changed.connect(_on_power_changed)
	Events.player_hide.connect(_on_player_hide)
	if not _missing.is_empty():
		print("[puzzles] not found in the world, left out: ", ", ".join(_missing))
	if Game.debug:
		print("[puzzles] code ", code, " interactables ", interaction.get("entries").size() if interaction != null else 0)

func start() -> void:
	if _started: return
	_started = true
	_ui("set_night", [Game.night, Game.NIGHTS_TOTAL])
	_ui("set_clues", [found.duplicate()])
	if _world_get(&"power") == false: flags.blackout = true
	_refresh_objective()
	var a := _args()
	if a.has("stage") or a.has("shot") or a.has("shots"): return   # debug jump / screenshots: no intro cinematic
	_intro_fade()
	_intro_line()

func _intro_fade() -> void:
	var ui := Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method("fade_to"): return
	await ui.fade_to(1.0, 0.0)
	ui.fade_to(0.0, 3.0)   # nothing follows: not awaited (no coroutine chain left pending if the game quits mid-fade)

func _intro_line() -> void:
	await _wait(1.6)
	if stage == "intro": _say("…Où suis-je ?", 3.5)

func _process(delta: float) -> void:
	if not _started or Game.state != "playing": return
	_tick_waits(delta)
	_tick_tweens(delta)
	if flags.won: return
	var modal := _modal_open()
	if not modal:
		stage_time += delta
		_idle += delta

	# ---- intro: flickering ceiling light, automatic blowout after 45 s
	if stage == "intro" and not flags.blackout:
		if _power():
			_flick_t -= delta
			if _flick_t <= 0.0:
				_flick_t = randf_range(6.0, 14.0)
				_lighting_call("flicker", [randf_range(0.3, 0.7), randf_range(0.5, 1.0)])
		if stage_time > 45.0 and not _blowout_pending and not modal: _blowout_sequence(0.0)

	# ---- first visit after the breaker: wait until she has gone back upstairs
	if flags.summoned and not flags.summon_done:
		var ent := Game.entity
		_summon_t += delta
		var ent_ok: bool = ent != null and is_instance_valid(ent)
		var ent_active: bool = ent_ok and ent.get(&"active") == true
		if ent_active: _summon_saw_active = true
		var disabled: bool = not ent_ok or ent.get(&"state") == "disabled"
		if (_summon_saw_active and not ent_active) or (not _summon_saw_active and _summon_t > (3.0 if disabled else 12.0)) or _summon_t > 180.0:
			flags.summon_done = true
			_progress()
			_say("Elle est remontée… Vite, le coffret de Léa." if _summon_saw_active else "Elle ne descend pas… Vite, le coffret de Léa.", 4.0)
			_advance()

	# ---- TV: loud while on (noise 0.55 every 0.5 s) + digit discovery when looked at
	var tv = _tv()
	if tv != null and tv.get(&"is_on") == true:
		var tp := _tv_pos()
		_tv_noise_t -= delta
		if _tv_noise_t <= 0.0:
			_tv_noise_t = 0.5
			_noise(tp, NOISE.tv, "tv")
		if found.tv == null and not modal:
			if _looks_at(tp, 0.9, 5.0, false): _tv_look += delta
			else: _tv_look = maxf(0.0, _tv_look - delta)
			if _tv_look > 0.9:
				_find_clue("tv", "Un chiffre apparaît dans la neige de l’écran : %s." % code[3])
	else:
		_tv_look = 0.0

	# ---- rocking chair rocks by itself the first time it is looked at after the blowout
	if flags.blackout and not flags.rocked and not modal:
		_look_t -= delta
		if _look_t <= 0.0:
			_look_t = 0.2
			if _can_see() and _looks_at(_rock_pos, 0.88, 6.0, true, 0.5): _rock_beat()

	# ---- win: walking through the open door (or 1.5 s after it opened)
	if flags.door_opened:
		_win_t -= delta
		if _win_t <= 0.0 or _in_hall(): _win()
	elif _in_hall() and (flags.key or flags.door_unlocked):
		_win()   # the entity left the door open and the player carries the key

	if not modal:
		_hints()
		_ambient(delta)

func reset_after_caught() -> void:
	_gen += 1
	if interaction != null and is_instance_valid(interaction) and interaction.has_method("reset"): interaction.call("reset")
	# finish running tweens (puts examined objects back in place)
	var jobs := _tweens.duplicate()
	_tweens.clear()
	for j in jobs:
		(j as TweenJob).fn.call(1.0)
		j.fired = true
		j.done.emit()

	if flags.summoned and not flags.summon_done: flags.summon_done = true   # she took the player back upstairs: the visit is over
	var tv = _tv()
	if tv != null and tv.get(&"is_on") == true and tv.has_method("set_on"): tv.call("set_on", false)
	if flags.door_opened and not flags.won: _win_t = INF   # must walk through now
	# keep the lights consistent with the progress
	if flags.breaker and not _power(): _world_call("set_power", [true])
	elif flags.blackout and not flags.breaker and _power(): _world_call("set_power", [false])

	# the garden gnome "moved" while the player was away
	var gnome := _find(GNOME_NAMES)
	if gnome != null and gnome.is_inside_tree():
		var wp := gnome.global_position
		var yaw := atan2(float(Layout.SPAWN.x) - wp.x, float(Layout.SPAWN.z) - wp.z) + randf_range(-0.15, 0.15)
		var r := gnome.global_rotation
		gnome.global_rotation = Vector3(r.x, yaw, r.z)
		flags.gnome_moved = true

	_idle = 0.0
	_hint_n = 0
	_scare_t = randf_range(30.0, 50.0)
	_refresh_objective()
	_ui("set_clues", [found.duplicate()])
	_ui("set_night", [Game.night, Game.NIGHTS_TOTAL])
	var inv := Game.inventory
	if inv != null and is_instance_valid(inv) and inv.has_method("emit_changed"): inv.call("emit_changed")
	_caught_line(Game.night)

func _caught_line(night: int) -> void:
	await _wait(1.8)
	_say("Encore ici… C’est ma dernière chance." if night >= Game.NIGHTS_TOTAL else "Encore ici… Elle ne me laissera pas partir.", 4.0)

# =================================================================== stage machine

func _compute_stage() -> String:
	if flags.won: return "win"
	if flags.key: return "escape"
	if flags.breaker and flags.summon_done: return "code"
	if flags.breaker or (flags.blackout and flags.flashlight): return "power"
	if flags.blackout: return "dark"
	return "intro"

func _advance() -> void:
	var nxt := _compute_stage()
	if STAGES.find(nxt) > STAGES.find(stage): _enter_stage(nxt)
	else: _set_objective(_objective_text())

func _enter_stage(nxt: String) -> void:
	var prev := stage
	stage = nxt
	stage_time = 0.0
	_idle = 0.0
	_hint_n = 0
	if Game.debug: print("[puzzles] stage %s -> %s" % [prev, nxt])
	Events.stage_changed.emit(nxt, prev)
	_set_objective(_objective_text())
	if nxt == "escape": _escape_beat()

func objective() -> String:
	return _objective_text()

func _objective_text() -> String:
	match stage:
		"intro": return "Explore le sous-sol."
		"dark": return "Trouve une lumière."
		"power":
			if flags.summoned and not flags.summon_done: return "Cache-toi ! (placard sous l’escalier)"
			return "Rétablis le courant (panneau électrique, buanderie)."
		"code":
			if flags.box_open: return "Prends la clé dans le coffret."
			var n := _found_count()
			if n >= 4: return "Ouvre le cadenas du coffret."
			return "Trouve le code du coffret (%d/4 chiffres)" % n if n > 0 else "Trouve le code du coffret (4 chiffres)"
		"escape": return "Monte l’escalier et ouvre la porte."
	return ""

func _set_objective(text: String, force := false) -> void:
	if not force and _obj_set and text == _obj_text: return
	_obj_text = text
	_obj_set = true
	_obj_sends += 1
	_ui("set_objective", [_fr(text)])

## _advance() + make sure the UI shows the objective (re-sent once even if unchanged: start, after a catch, debug jumps).
## `since`: objective send count at the start of the operation (default: now).
func _refresh_objective(since := -1) -> void:
	var before := _obj_sends if since < 0 else since
	_advance()
	if _obj_sends == before: _set_objective(_objective_text(), true)

func _progress() -> void:
	_idle = 0.0
	_hint_n = 0

func tension() -> float:
	var base := float(STAGE_TENSION.get(stage, 0.0))
	return clampf(base + 0.12 * float(Game.night - 1) + minf(0.15, Game.time_played / 1500.0), 0.0, 1.0)

# =================================================================== registration

func _register_all() -> void:
	var drawer := {"open": "Ouvrir le tiroir", "close": "Fermer le tiroir", "noise": NOISE.drawer}
	_reg_handle("dresser.drawerTop", drawer)
	_reg_handle("dresser.drawerMid", _with(drawer, {"empty": "Des vieux vêtements d’enfant, pliés avec soin."}))
	_reg_handle("dresser.drawerBottom", _with(drawer, {"empty": "Des cassettes vidéo sans étiquette."}))
	_reg_handle("endTable.drawer", drawer)
	_reg_handle("alcoveCabinet.drawer_01", drawer)
	_reg_handle("alcoveCabinet.drawer_02", _with(drawer, {"empty": "Des élastiques, des bouts de crayons… rien d’utile."}))
	var cab := {"open": "Ouvrir la porte du meuble", "close": "Fermer la porte du meuble", "noise": NOISE.drawer}
	_reg_handle("alcoveCabinet.door_01", cab)
	_reg_handle("alcoveCabinet.door_02", _with(cab, {"empty": "Des pots de peinture séchée."}))
	_reg_handle("powerBox.door", {"open": "Ouvrir le panneau électrique", "close": "Fermer le panneau électrique", "noise": NOISE.drawer})

	# ---- breaker lever
	var lever_node := _handle_node(_handle("powerBox.lever"))
	if lever_node != null:
		interaction.register({
			"id": "powerBox.lever", "node": lever_node, "prompt": "Abaisser le levier",
			"enabled": _lever_enabled,
			"on_interact": _flip_breaker,
		})
	else:
		_missing.append("powerBox.lever")

	# ---- locked box: label (child's code note) + padlock keypad
	var lid = _handle("lockedBox.lid")
	var lid_node := _handle_node(lid)
	if lid_node != null:
		interaction.register({
			"id": "lockedBox", "node": lid_node, "aliases": ["lockedBox.lid"],
			"prompt": _box_prompt.bind(lid),
			"on_interact": _box_interact.bind(lid),
		})
	else:
		_missing.append("lockedBox.lid")
	var lock_node := _handle_node(_handle("lockedBox.lock"))
	if lock_node != null:
		interaction.register({
			"id": "lockedBox.lock", "node": lock_node, "prompt": "Entrer le code",
			"enabled": func() -> bool: return not flags.box_open,
			"on_interact": _keypad,
		})
	else:
		_missing.append("lockedBox.lock")

	# ---- pickups
	_reg_item("flashlight", "Prendre la lampe de poche", "dresser.drawerTop")
	_reg_item("battery1", "Prendre la pile", "endTable.drawer")
	_reg_item("battery2", "Prendre la pile", "alcoveCabinet.drawer_01")
	_reg_item("key", "Prendre la clé", "lockedBox.lid", func() -> bool: return flags.box_open)

	# ---- notes
	_reg_note("note1", func() -> String: return "Relire la note" if flags.note1 else "Lire la note", NOTES.note1, "", _on_note1_read)
	_reg_note("note2", "Regarder le dessin", NOTES.note2, "", Callable())
	_reg_note("note3", "Lire la coupure de journal", NOTES.note3, "alcoveCabinet.door_01", Callable())

	# ---- clues
	var C := _clues()
	_reg_clue("duck", C.get("duck"), "Examiner le canard", true,
		func(d: String) -> String: return "Sous le canard, quelqu’un a écrit un chiffre au feutre : %s." % d)
	_reg_clue("horse", C.get("horse"), "Examiner le cheval", true,
		func(d: String) -> String: return "Un chiffre est gravé sous le socle du cheval : %s." % d)
	_reg_clue("clock", C.get("clock"), "Examiner l’horloge", false,
		func(d: String) -> String: return "L’horloge est arrêtée sur %s h pile. La petite aiguille pointe le %s." % [d, d])

	# ---- TV (needs power, loud while on)
	var tv_node := _tv_node()
	if tv_node != null:
		interaction.register({"id": "tv", "node": tv_node, "prompt": _tv_prompt, "on_interact": _toggle_tv})
		var ctv = C.get("tv")
		if ctv is Node3D and ctv != tv_node and not tv_node.is_ancestor_of(ctv):
			interaction.register({"id": "tv.screen", "node": ctv, "prompt": _tv_prompt, "on_interact": _toggle_tv})
	else:
		_missing.append("tv")

	# ---- upstairs door
	var door = _handle("door.upstairs")
	var door_node := _handle_node(door)
	if door_node != null:
		interaction.register({
			"id": "door.upstairs", "node": door_node, "max_distance": 2.4,
			"prompt": _door_prompt.bind(door),
			"hold": _door_hold.bind(door),
			"hold_prompt": "Déverrouillage…",
			"on_hold_start": _door_hold_start.bind(door),
			"on_interact": _door_interact.bind(door),
		})
	else:
		_missing.append("door.upstairs")

	# ---- closet (hiding spot). The spot handed to player.enter_hide always carries the real door Handle.
	var spot = _closet_spot()
	var cdoor = spot.get("door") if spot is Dictionary and _is_handle(spot.get("door")) else _handle("door.closet")
	var cdoor_node := _handle_node(cdoor)
	if spot is Dictionary and cdoor_node != null:
		interaction.register({
			"id": "closet.hide", "node": cdoor_node, "prompt": "Se cacher", "max_distance": 2.3, "aliases": ["door.closet", "closet"],
			"enabled": func() -> bool: return not _player_hidden(),
			"on_interact": _enter_closet.bind(spot),
		})
		interaction.register({
			"id": "closet.exit", "node": cdoor_node, "prompt": "Sortir du placard", "when_hidden": true,
			"enabled": func() -> bool: return _player_hidden(),
			"on_interact": _exit_closet.bind(spot),
		})
	else:
		_missing.append("closet")

	# ---- window (proxy box over the opening)
	var W: Dictionary = Layout.WINDOW
	var win := _proxy("window", Vector3(W.maxX - W.minX, W.maxY - W.minY, 0.06), Vector3((W.minX + W.maxX) * 0.5, (W.minY + W.maxY) * 0.5, W.z - 0.04))
	interaction.register({"id": "window", "node": win, "prompt": "Examiner la fenêtre", "max_distance": 2.8, "on_interact": _window_interact.bind(win)})

	_register_flavour()

## Atmosphere-only interactables (base props + batch-2 extras found by node name).
func _register_flavour() -> void:
	_look("look.photo", ["photoFrame", "standing_picture_frame_01"], "Regarder la photo",
		["Une très grande femme, derrière deux enfants. Elle ne regarde pas l’objectif."])
	_look("look.alarm", ["alarmClock", "alarm_clock_01"], "Examiner le réveil",
		["3 h 33. Le tic-tac est beaucoup trop fort.", "Il avance toujours. Pas l’horloge."])
	_look("look.cassette", ["cassette", "portable_cassette_player"], "Examiner le baladeur",
		["Une cassette étiquetée au crayon : « BERCEUSES — NE PAS ÉCOUTER »."])
	var rock := _find(["rockingChair", "Rockingchair_01"])
	if rock != null and rock.is_inside_tree():
		_rock_node = rock
		_rock_pos = rock.global_position + Vector3(0.0, 0.6, 0.0)
	_look("look.rocking", rock, "Examiner la chaise berçante",
		func() -> String: return "Elle s’est balancée toute seule… Je l’ai vue bouger." if flags.rocked else "Une vieille chaise berçante. Le coussin est encore creusé.")

	# pull-chain socket / dead bulb in the nook (proxy so it works whatever the node names are)
	var b: Array = Layout.PROPS["bulb"]["pos"]
	var bulb := _proxy("bulb", Vector3(0.3, 0.42, 0.3), Vector3(b[0], b[1] + 0.02, b[2]))
	_look("look.bulb", bulb, "Tirer la chaînette", ["Clic. Rien. L’ampoule est grillée.", "Clic… Clic. Toujours rien."],
		{"light": false, "sfx": "flashlight_click", "vol": 0.9, "max_distance": 2.3})

	# batch-2 extras (Layout.EXTRA_PROPS; web scene names "extra_<key>"; optional)
	_look("look.gnome", GNOME_NAMES, "Examiner le nain de jardin",
		func() -> String: return "Il… n’était pas tourné comme ça, avant." if flags.gnome_moved else "Il me fixe…")
	_look("look.mirror", ["extra_mirror", "mirror", "ornate_mirror_01"], "Se regarder dans le miroir",
		["Je ne me reconnais presque pas.", "Mes yeux… J’ai l’air de ne pas avoir dormi depuis des jours."],
		{"after": _mirror_after})
	_look("look.oldTv", ["extra_oldTv", "oldTv", "Television_01"], "Examiner la vieille télé",
		func() -> String: return "Elle grésille… Elle n’est même pas branchée." if _power() else "Une vieille télé. Le fil a été coupé.")
	_look("look.boombox", ["extra_boombox", "boombox"], "Allumer la radio", ["Rien. Les piles sont mortes."],
		{"light": false, "sfx": "flashlight_click", "vol": 0.8})
	_look("look.toolbox", ["extra_toolbox", "toolbox", "metal_toolbox"], "Fouiller le coffre à outils",
		["Des vis rouillées… Rien pour forcer une serrure."], {"sfx": "cloth_move", "noise": NOISE.rummage})
	_look("look.laundry", ["extra_laundry", "laundry", "plastic_crate_02"], "Fouiller le panier",
		["Des vêtements d’enfant. Ils sont encore humides…"], {"light": false, "sfx": "cloth_move", "vol": 0.8})
	_look("look.bat", ["extra_bat", "bat", "baseball_bat"], "Prendre le bâton", ["Non… Elle est bien trop grande pour ça."], {"light": false})
	_look("look.football", ["extra_football", "football"], "Examiner le ballon", ["Un ballon tout dégonflé. Il y a des marques de dents."])
	_look("look.gamepad", ["extra_gamepad", "gamepad"], "Examiner la manette", ["Une vieille manette. Le fil a été coupé net."])
	_look("look.mousetrap", ["extra_mousetrap", "mousetrap"], "Examiner la souricière", ["Une souricière. Il y a encore quelque chose dedans…"])
	_look("look.photoA", ["extra_stairPhotoA", "stairPhotoA"], "Regarder la photo", ["Une photo de famille. Le visage de la femme a été gratté."])
	_look("look.photoB", ["extra_stairPhotoB", "stairPhotoB"], "Regarder la photo", ["Deux enfants devant la maison, en hiver. Personne ne sourit."])

func _reg_handle(id: String, cfg: Dictionary) -> void:
	var h = _handle(id)
	var node := _handle_node(h)
	if node == null:
		_missing.append(id)
		return
	interaction.register({
		"id": id, "node": node,
		"prompt": func() -> String: return cfg.close if h.is_open else cfg.open,
		"on_interact": _handle_interact.bind(id, h, cfg),
	})

func _handle_interact(id: String, h, cfg: Dictionary) -> void:
	var opening: bool = not h.is_open
	_noise(_hpos(h), float(cfg.get("noise", NOISE.drawer)), id)
	if opening:
		if h.has_method("open"): await h.open()
		elif h.has_method("toggle"): await h.toggle()
	else:
		if h.has_method("close"): await h.close()
		elif h.has_method("toggle"): await h.toggle()
	if opening and cfg.has("empty") and not _seen.has("empty." + id):
		_seen["empty." + id] = true
		_say(cfg.empty, 3.0)

func _reg_item(item_id: String, prompt: String, inside_handle: String, extra := Callable()) -> void:
	var obj := _item(item_id)
	if obj == null:
		_missing.append(item_id)
		return
	var h = _handle(inside_handle) if inside_handle != "" else null
	interaction.register({
		"id": "item." + item_id, "node": obj, "prompt": prompt, "aliases": [item_id],
		"enabled": _item_enabled.bind(item_id, obj, h, extra),
		"on_interact": _take_item.bind(item_id, false),
	})

func _item_enabled(item_id: String, obj: Node3D, h, extra: Callable) -> bool:
	return not _taken.has(item_id) and is_instance_valid(obj) and obj.visible and (h == null or h.is_open) and (not extra.is_valid() or extra.call() == true)

func _reg_note(item_id: String, prompt: Variant, note: Dictionary, inside_handle: String, on_read: Callable) -> void:
	var obj := _item(item_id)
	if obj == null:
		_missing.append(item_id)
		return
	var h = _handle(inside_handle) if inside_handle != "" else null
	interaction.register({
		"id": item_id, "node": obj, "prompt": prompt, "aliases": ["item." + item_id],
		"enabled": func() -> bool: return obj.visible and (h == null or h.is_open),
		"on_interact": _read_note.bind(item_id, note, obj, on_read),
	})

func _reg_clue(key: String, obj, prompt: String, tilt: bool, text_fn: Callable) -> void:
	if not (obj is Node3D) or not is_instance_valid(obj):
		_missing.append("clue." + key)
		return
	interaction.register({
		"id": "clue." + key, "node": obj, "prompt": prompt, "aliases": [key],
		"on_interact": _clue_interact.bind(key, obj, tilt, text_fn),
	})

func _look(id: String, target, prompt: String, lines, opts := {}) -> void:
	var obj: Node3D = null
	if target is Array: obj = _find(target)
	elif target is Node3D and is_instance_valid(target): obj = target
	if obj == null:
		_missing.append(id)
		return
	interaction.register({
		"id": id, "node": obj, "prompt": prompt, "max_distance": float(opts.get("max_distance", 2.1)),
		"on_interact": _look_interact.bind(id, obj, lines, opts),
	})

func _look_interact(id: String, obj: Node3D, lines, opts: Dictionary) -> void:
	if opts.get("light", true) and not _can_see():
		_say("Il fait trop noir pour voir.", 2.5)
		return
	var p := obj.global_position
	if opts.has("sfx"): _sfx(str(opts.sfx), p, float(opts.get("vol", 0.7)))
	if opts.has("noise"): _noise(p, float(opts.noise), id)
	var text := ""
	if lines is Callable: text = str((lines as Callable).call())
	elif lines is Array: text = _cycle(id, lines)
	if text != "": _say(text, maxf(3.0, text.length() * 0.055))
	var after = opts.get("after")
	if after is Callable: await (after as Callable).call(p)
	await _wait(0.4)

# =================================================================== entry callbacks

func _lever_enabled() -> bool:
	var door = _handle("powerBox.door")
	return not flags.breaker and not _power() and (door == null or door.is_open)

func _box_prompt(lid) -> String:
	if not flags.box_open: return "Examiner le coffret"
	return "" if lid.is_open else "Ouvrir le coffret"

func _box_interact(lid) -> void:
	if not flags.box_open:
		await _read_note("box", NOTES.box, lid, _on_box_note_read)
		return
	_noise(_hpos(lid), NOISE.box, "box")
	if lid.has_method("open"): await lid.open()

func _on_box_note_read() -> void:
	flags.box_note = true
	_progress()

func _on_note1_read() -> void:
	if flags.note1: return
	flags.note1 = true
	_progress()
	if not flags.blackout: _blowout_sequence(1.4)

func _tv_prompt() -> String:
	var tv = _tv()
	return "Éteindre la télé" if tv != null and tv.get(&"is_on") == true else "Allumer la télé"

func _has_key() -> bool:
	if flags.key: return true
	var inv := Game.inventory
	return inv != null and is_instance_valid(inv) and inv.has_method("has") and inv.call("has", "key") == true

func _door_prompt(door) -> String:
	if flags.won or flags.door_opened: return ""
	if door.is_open: return "Passer la porte" if _has_key() else ""
	if door.locked: return "Déverrouiller (maintenir)" if _has_key() else "Ouvrir la porte"
	return "Ouvrir la porte"

func _door_hold(door) -> float:
	return 2.0 if (not door.is_open and door.locked and _has_key()) else 0.0

func _door_hold_start(door) -> void:
	var p := _hpos(door)
	_noise(p, NOISE.door_unlock, "door.unlock")
	_sfx("key_pickup", p, 0.7)

func _door_interact(door) -> void:
	if door.is_open or not door.locked:
		await _open_door_and_win()
		return
	if _has_key():
		await _unlock_door()
		return
	await _rattle()

func _clue_interact(key: String, obj: Node3D, tilt: bool, text_fn: Callable) -> void:
	if not _can_see():
		_say("Il fait trop noir pour voir.", 2.5)
		return
	var d: String = code[CLUES.find(key)]
	var known: bool = found.get(key) != null
	var p := obj.global_position
	var text := str(text_fn.call(d))
	if tilt:
		_sfx("pickup", p, 0.45)
		await _tilt_reveal(obj, _clue_reveal.bind(key, text, known))
	else:
		_clue_reveal(key, text, known)
		if key == "clock" and not _seen.has("chime") and _power():
			_seen["chime"] = true
			_clock_chime(p)
		await _wait(0.5)

func _clue_reveal(key: String, text: String, known: bool) -> void:
	if known: _say(text, 3.5)
	else: _find_clue(key, text)

func _clock_chime(p: Vector3) -> void:
	await _wait(2.2)
	_sfx("clock_chime", p, 0.55)
	await _wait(1.2)
	_say("Elle sonne… alors qu’elle est arrêtée ?", 3.0)

func _window_interact(win: Node3D) -> void:
	var p := win.global_position
	_sfx("window_tap", p, 0.8)
	_noise(p, NOISE.window, "window")
	_say(_cycle("window", ["Trop petite… et il y a des barreaux.", "Il neige, dehors. Personne ne viendra me chercher.", "Les barreaux sont scellés dans le béton."]), 3.5)
	await _wait(0.6)

func _mirror_after(_p: Vector3) -> void:
	_mirror_scare()

# =================================================================== actions

func _can_see() -> bool:
	if _power(): return true
	var pl := Game.player
	if pl == null or not is_instance_valid(pl): return false
	var fl = pl.get(&"flashlight")
	return fl is Dictionary and bool(fl.get("has", false)) and bool(fl.get("on", false)) and float(fl.get("battery", 1.0)) > 0.0

func _read_note(id: String, note: Dictionary, obj, on_read: Callable) -> void:
	if not _can_see():
		_say("Il fait trop noir pour lire.", 2.5)
		return
	var p := _hpos(obj)
	_sfx("paper", p, 0.8)
	var shown := {"id": id, "title": _fr(str(note.title)), "text": _fr(str(note.text)), "style": str(note.style)}
	var inv := Game.inventory
	if inv != null and is_instance_valid(inv) and inv.has_method("add_note"): inv.call("add_note", shown.duplicate())
	var ui := Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("show_note"):
		await Game.modal(func() -> void: await ui.show_note(shown))
	_sfx("paper", p, 0.5)
	if on_read.is_valid(): on_read.call()

func _take_item(item_id: String, quiet := false) -> void:
	if _taken.has(item_id): return
	_taken[item_id] = true
	var obj := _item(item_id)
	var pos: Vector3 = obj.global_position if obj != null and obj.is_inside_tree() else _cam_pos()
	if obj != null: obj.visible = false
	if interaction != null and is_instance_valid(interaction): interaction.unregister("item." + item_id)
	match item_id:
		"flashlight":
			_inv_add("flashlight")
			flags.flashlight = true
			var pl := Game.player
			if pl != null and is_instance_valid(pl):
				if pl.has_method("give_flashlight"): pl.call("give_flashlight")
				var fl = pl.get(&"flashlight")
				if fl is Dictionary and not bool(fl.get("on", false)) and pl.has_method("set_flashlight_on"): pl.call("set_flashlight_on", true)
			if not quiet:
				_sfx("pickup", pos, 0.9)
				var pad: bool = interaction != null and interaction.get(&"using_gamepad") == true
				_say("Une lampe de poche ! (Y pour l’allumer ou l’éteindre)" if pad else "Une lampe de poche ! (F pour l’allumer ou l’éteindre)", 4.0, {"critical": true})
		"battery1", "battery2":
			_inv_add("battery")
			if not quiet:
				_sfx("pickup", pos, 0.8)
				_say("Une pile de rechange. La lampe en aura besoin.", 3.0)
		"key":
			_inv_add("key")
			flags.key = true
			if not quiet:
				_sfx("key_pickup", pos, 1.0)
				_say("La clé ! Maintenant, la porte d’en haut.", 3.5)
		_:
			_inv_add(item_id)
	_progress()
	_advance()

func _inv_add(id: String) -> void:
	var inv := Game.inventory
	if inv != null and is_instance_valid(inv) and inv.has_method("add"): inv.call("add", id)

func _find_clue(key: String, text: String) -> void:
	if found.get(key) != null: return
	found[key] = code[CLUES.find(key)]
	_ui("set_clues", [found.duplicate()])
	_progress()
	_say(text, 4.0)
	if _found_count() == 4 and not flags.box_open: _all_digits_line()
	_set_objective(_objective_text())

func _all_digits_line() -> void:
	await _wait(4.2)
	if not flags.box_open: _say("J’ai les quatre chiffres : %s. Le cadenas du coffret, maintenant." % _code_from_found(), 4.5)

func _found_count() -> int:
	var n := 0
	for k in CLUES:
		if found.get(k) != null: n += 1
	return n

func _code_from_found() -> String:
	var parts: Array[String] = []
	for k in CLUES: parts.append(str(found[k]) if found.get(k) != null else "?")
	return " ".join(parts)

func _blowout_sequence(delay: float) -> void:
	if flags.blackout or _blowout_pending: return
	_blowout_pending = true
	if delay > 0.0: await _wait(delay)
	if flags.blackout:
		_blowout_pending = false
		return
	_lighting_call("flicker", [0.9, 1.0])
	await _wait(1.1)
	_do_blackout()

func _do_blackout(quiet := false) -> void:
	_blowout_pending = false
	if flags.blackout: return
	flags.blackout = true
	var l = _lighting()
	if l != null and l.has_method("blowout"): l.call("blowout")
	else: _world_call("set_power", [false])
	if _power(): _world_call("set_power", [false])
	var lever = _handle("powerBox.lever")   # the breaker tripped
	if lever != null and lever.get(&"is_on") == true and lever.has_method("set_on"): lever.call("set_on", false)
	_progress()
	if not quiet: _blackout_lines()
	_advance()

func _blackout_lines() -> void:
	await _wait(0.35)
	_sfx("player_gasp", null, 0.8)
	await _wait(0.9)
	_say("Non, non, non… Il fait tout noir.", 3.5)

func _rock_beat() -> void:
	flags.rocked = true
	var w := Game.world
	var props = w.get(&"props") if w != null and is_instance_valid(w) else null
	if w != null and w.has_method("rock_chair"): w.call("rock_chair", 6.0)
	elif props is Object and props.has_method("rock_chair"): props.call("rock_chair", 6.0)
	else: _sfx("rocking_chair", _rock_pos, 0.8)
	_heartbeat_after(0.5)

func _heartbeat_after(sec: float) -> void:
	await _wait(sec)
	_sfx("heartbeat_single", null, 0.8)

func _flip_breaker() -> void:
	if flags.breaker: return
	var lever = _handle("powerBox.lever")
	var pos := _panel_pos()
	flags.breaker = true
	_noise(pos, NOISE.breaker, "breaker")
	if lever != null:
		if lever.has_method("set_on"):
			await lever.set_on(true)
		elif _is_handle(lever):
			if str(lever.get(&"sfx_open")) == "": _sfx("breaker_flip", pos, 1.0)
			if not lever.is_open: await lever.open()
	if not _power(): _world_call("set_power", [true])
	flags.summoned = true
	_summon_t = 0.0
	_summon_saw_active = false
	var ent := Game.entity
	if ent != null and is_instance_valid(ent) and ent.has_method("summon"): ent.call("summon", pos, "breaker")
	_progress()
	_advance()
	_breaker_lines()
	await _wait(0.4)

func _breaker_lines() -> void:
	await _wait(0.9)
	_ui("alert", [_fr("CACHE-TOI !"), 2.5])
	_set_objective(_objective_text())
	await _wait(2.0)
	if not flags.summon_done: _say("Le bruit… Elle l’a entendu. Le placard sous l’escalier !", 4.0, {"critical": true})

func _toggle_tv() -> void:
	var tv = _tv()
	if tv == null: return
	var p := _tv_pos()
	if tv.get(&"is_on") != true:
		if not _power():
			_sfx("flashlight_click", p, 0.6)
			_say("Rien. Pas de courant.", 2.5)
			await _wait(0.4)
			return
		if tv.has_method("set_on"): tv.call("set_on", true)
		_sfx("tv_on", p, 0.9)
		_tv_noise_t = 0.0
		_tv_look = 0.0
		if not _seen.has("tv_loud"):
			_seen["tv_loud"] = true
			_say("Ça fait tellement de bruit…", 3.0)
	else:
		if tv.has_method("set_on"): tv.call("set_on", false)
		_sfx("tv_off", p, 0.9)
	await _wait(0.5)

func _keypad() -> void:
	if flags.box_open: return
	var ui := Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method("show_keypad"): return
	var lock = _handle("lockedBox.lock")
	var p := _hpos(lock)
	var title := _fr("Cadenas du coffret")
	var r = await Game.modal(func(): return await ui.show_keypad(title, 4))
	var s := _digits_only(str(r) if r != null else "")
	if s == "": return   # cancelled
	stats["code_attempts"] += 1
	if lock != null and lock.has_method("set_digits"): lock.call("set_digits", s)   # the brass wheels show what was tried
	if s == code:
		await _open_box()
		return
	_sfx("lock_fail", p, 0.9)
	_noise(p, NOISE.lock_fail, "lock")
	_say("Ça ne marche pas. Il me manque des chiffres…" if _found_count() < 4 else "Ça ne marche pas… L’ordre : canard, cheval, horloge, télé.", 3.5)
	await _wait(0.4)

func _open_box() -> void:
	if flags.box_open: return
	flags.box_open = true
	for i in CLUES.size():
		if found.get(CLUES[i]) == null: found[CLUES[i]] = code[i]
	_ui("set_clues", [found.duplicate()])
	var lock = _handle("lockedBox.lock")
	var lid = _handle("lockedBox.lid")
	var p: Vector3 = _hpos(lock if lock != null else lid)
	_sfx("lock_success", p, 1.0)
	if _is_handle(lock): await lock.open()
	_noise(p, NOISE.box, "box")
	if _is_handle(lid): await lid.open()
	_progress()
	_say("Ça s’ouvre ! La clé est dedans.", 3.0)
	_advance()

func _escape_beat() -> void:
	var ent := Game.entity
	if ent != null and is_instance_valid(ent) and ent.has_method("set_aggression"): ent.call("set_aggression", 2)
	_escape_lines()

func _escape_lines() -> void:
	await _wait(0.9)
	_sfx("ceiling_walk", Vector3(-3.0, 3.0, -3.8), 1.0)
	await _wait(1.6)
	_say("Elle bouge, là-haut… Elle sait.", 3.5)
	await _wait(2.5)
	_sfx("house_creak", Vector3(-3.0, 3.6, -3.4), 0.9)

func _rattle() -> void:
	var p := _hpos(_handle("door.upstairs"))
	stats["rattles"] += 1
	_sfx("door_locked", p, 1.0)
	_noise(p, NOISE.door_rattle, "door.rattle")
	_say("Verrouillée." if stats["rattles"] == 1 else "Verrouillée. Il me faut la clé… et pas de bruit.", 2.5)
	await _wait(0.8)

func _unlock_door() -> void:
	var door = _handle("door.upstairs")
	if door == null or flags.door_unlocked: return
	var p := _hpos(door)
	flags.door_unlocked = true
	door.locked = false
	_sfx("unlock", p, 1.0)
	_progress()
	await _wait(0.4)
	await _open_door_and_win()

func _open_door_and_win() -> void:
	if flags.door_opened or flags.won: return
	var door = _handle("door.upstairs")
	var p := _hpos(door)
	flags.door_opened = true
	if door != null: door.locked = false
	_sfx("win_door", p, 1.0)
	_say("De la lumière… Je sors d’ici !", 3.0)
	if _is_handle(door) and not door.is_open: await door.open()
	_win_t = 1.5

func _in_hall() -> bool:
	var pl := Game.player
	if pl == null or not is_instance_valid(pl) or not (pl is Node3D) or not (pl as Node3D).is_inside_tree(): return false
	var pp := (pl as Node3D).global_position
	var H: Dictionary = Layout.UPPER_HALL
	return pp.y > 2.0 and pp.x >= H.minX and pp.x <= H.maxX and pp.z < float(Layout.ROOM.minZ) - 0.12 and pp.z >= H.minZ - 0.5

func _win() -> void:
	if flags.won: return
	flags.won = true
	_win_t = INF
	_advance()
	if interaction != null and is_instance_valid(interaction) and interaction.has_method("reset"): interaction.call("reset")
	Events.game_win.emit()

func _enter_closet(spot: Dictionary) -> void:
	var pl := Game.player
	if pl == null or not is_instance_valid(pl) or pl.get(&"hidden") == true: return
	var pos := _hpos(spot.get("door"))
	_sfx("closet_enter", pos, 0.9)
	_noise(pos, NOISE.closet, "closet")
	var t0 := _clock
	if pl.has_method("enter_hide"): await pl.enter_hide(spot)
	if _clock - t0 < 0.7: await _wait(0.7 - (_clock - t0))   # at least 0.7 s, like Promise.all([enterHide, wait(0.7)])

func _exit_closet(spot: Dictionary) -> void:
	var pl := Game.player
	if pl == null or not is_instance_valid(pl) or pl.get(&"hidden") != true: return
	var pos := _hpos(spot.get("door"))
	_sfx("closet_exit", pos, 0.9)
	_noise(pos, NOISE.closet, "closet")
	var t0 := _clock
	if pl.has_method("exit_hide"): await pl.exit_hide()
	if _clock - t0 < 0.7: await _wait(0.7 - (_clock - t0))

func _mirror_scare() -> void:
	if _seen.has("mirror_scare") or STAGES.find(stage) < STAGES.find("code") or randf() > 0.5: return
	_seen["mirror_scare"] = true
	_mirror_lines(_cam_pos() - _flat_dir() * 1.1)

func _mirror_lines(behind: Vector3) -> void:
	await _wait(1.4)
	_sfx("whisper", behind, 0.7)
	await _wait(0.8)
	_say("…Derrière moi ?", 2.5)

func _on_player_hide(hidden: bool, _spot_id: String) -> void:
	if hidden and flags.summoned and not flags.summon_done and not _seen.has("hide_tip"):
		_seen["hide_tip"] = true
		_say("Ne bouge plus. Ne fais pas un bruit…", 3.5)

func _on_power_changed(on: bool) -> void:
	if on: return
	var tv = _tv()
	if tv != null and tv.get(&"is_on") == true and tv.has_method("set_on"): tv.call("set_on", false)
	# power cut from elsewhere (debug --power=off) during the intro: same progress as the blowout, quietly
	if _started and not flags.blackout and stage == "intro":
		flags.blackout = true
		_blowout_pending = false
		_progress()
		_advance()

# =================================================================== hints & ambience

func _hint_timing() -> Vector2:   # (first, every) in seconds of idle time; x < 0 = no hints
	match stage:
		"intro": return Vector2(25.0, 60.0)
		"dark": return Vector2(40.0, 50.0)
		"power": return Vector2(14.0, 25.0) if (flags.summoned and not flags.summon_done) else Vector2(50.0, 55.0)
		"code": return Vector2(45.0, 50.0)
		"escape": return Vector2(40.0, 50.0)
	return Vector2(-1.0, -1.0)

func _hint_text(n: int) -> String:
	match stage:
		"intro":
			return "Il y a un papier sur la table basse…" if not flags.note1 else ""
		"dark":
			return "La commode… il y avait une lampe de poche." if n == 0 else "Le tiroir du haut de la commode, sous la petite télé."
		"power":
			if flags.summoned and not flags.summon_done:
				return "" if _player_hidden() else "Le placard sous l’escalier… vite !"
			return "Le panneau électrique doit être dans la buanderie." if n == 0 else "Au fond de la buanderie, sur le mur : ouvre le panneau et abaisse le levier."
		"code":
			if flags.box_open: return "La clé, dans le coffret !"
			if not flags.box_note and n == 0: return "Le coffret de Léa… sur la console, près des chaises."
			var missing: Array[String] = []
			for k in CLUES:
				if found.get(k) == null: missing.append(k)
			if missing.is_empty(): return "Le cadenas du coffret : %s." % _code_from_found()
			return CLUE_HINTS[missing[n % missing.size()]]
		"escape":
			return "La porte en haut de l’escalier. Vite !" if n == 0 else "Avec la clé : maintiens le bouton sur la porte pour la déverrouiller."
	return ""

func _hints() -> void:
	var timing := _hint_timing()
	if timing.x < 0.0 or _entity_state() == "chasing": return
	if _idle < timing.x + _hint_n * timing.y: return
	var text := _hint_text(_hint_n)
	_hint_n += 1
	if text != "": _say(text, 4.5, {"critical": true, "hint": true})

func _ambient(dt: float) -> void:
	var ent := Game.entity
	if ent != null and is_instance_valid(ent) and ent.get(&"active") == true:
		_scare_t = maxf(_scare_t, 8.0)
		return
	_scare_t -= dt
	if _scare_t > 0.0: return
	var t := tension()
	_scare_t = lerpf(75.0, 24.0, t) * randf_range(0.75, 1.35)
	var pool: Array = []
	var sum := 0.0
	for s in SCARES:
		if float(s.min_t) <= t and s.name != _last_scare:
			pool.append(s)
			sum += float(s.w)
	if pool.is_empty(): return
	var r := randf() * sum
	var sc: Dictionary = pool[0]
	for s in pool:
		r -= float(s.w)
		if r <= 0.0:
			sc = s
			break
	_last_scare = sc.name
	_sfx(sc.name, _scare_pos(sc.name), float(sc.vol))
	if sc.has("sub"): _say(sc.sub, 2.5)

func _scare_pos(scare: String) -> Variant:
	match scare:
		"house_creak":
			return [Vector3(3.2, 2.3, -2.4), Vector3(-1.5, 2.4, 2.5), Vector3(2.0, 2.2, -4.2), Vector3(-3.3, 2.3, 1.5), Vector3(0.5, 2.45, 0.0)].pick_random()
		"stair_creak":
			var z := randf_range(-1.5, 1.4)
			var h := Layout.stair_height_at(-3.0, z)
			return Vector3(-3.0, (1.0 if is_nan(h) else h) + 0.1, z)
		"ceiling_walk", "ceiling_steps":
			return Vector3(randf_range(-2.2, 3.2), 2.9, randf_range(-2.5, 2.5))
		"knock_wall":
			return [Vector3(3.55, 1.2, -0.8), Vector3(-0.4, 1.3, -2.8), Vector3(-3.2, 0.9, -1.6), Vector3(1.2, 1.0, 2.8)].pick_random()
		"window_tap":
			var W: Dictionary = Layout.WINDOW
			return Vector3((W.minX + W.maxX) * 0.5, (W.minY + W.maxY) * 0.5, W.z)
		"whisper":
			return _cam_pos() - _flat_dir() * 1.2 + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		"giggle":
			return [Vector3(-2.0, 0.7, 0.3), Vector3(-3.0, 0.8, -1.4), Vector3(-3.0, 3.4, -2.3)].pick_random()
	return null

# =================================================================== debug

## Jump to a stage (debug, DebugTools --stage=...). Applies every earlier step's side effects without the cinematics.
func debug_goto(s: String) -> void:
	var idx := STAGES.find(s)
	if idx < 0:
		push_warning("[puzzles] unknown stage " + s)
		return
	_started = true
	var sends0 := _obj_sends
	if idx >= 1 and not flags.blackout:
		flags.note1 = true
		_do_blackout(true)
	if idx >= 2 and not flags.flashlight: _take_item("flashlight", true)
	if idx >= 3:
		if not flags.breaker:
			flags.breaker = true
			flags.summoned = true
			flags.summon_done = true
			var lever = _handle("powerBox.lever")
			if lever != null and lever.has_method("set_on"): await lever.set_on(true)
			if not _power(): _world_call("set_power", [true])
		else:
			flags.summon_done = true
		_advance()
	if idx >= 4:
		flags.box_note = true
		if not flags.box_open:
			flags.box_open = true
			for i in CLUES.size(): found[CLUES[i]] = code[i]
			_ui("set_clues", [found.duplicate()])
			var lock = _handle("lockedBox.lock")
			if _is_handle(lock): await lock.open()
			var lid = _handle("lockedBox.lid")
			if _is_handle(lid): await lid.open()
		if not flags.key: _take_item("key", true)
	if idx >= 5:
		await _unlock_door()
		_win()
	_refresh_objective(sends0)

# =================================================================== world / ui access (defensive)

func _world_get(prop: StringName) -> Variant:
	var w := Game.world
	if w == null or not is_instance_valid(w): return null
	return w.get(prop)

func _world_call(method: String, args: Array) -> Variant:
	var w := Game.world
	if w == null or not is_instance_valid(w) or not w.has_method(method): return null
	return w.callv(method, args)

func _lighting() -> Variant:
	var l = _world_get(&"lighting")
	return l if l is Object and is_instance_valid(l) else null

func _lighting_call(method: String, args: Array) -> void:
	var l = _lighting()
	if l != null and l.has_method(method): l.callv(method, args)

func _ui(method: String, args: Array) -> Variant:
	var ui := Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method(method): return null
	return ui.callv(method, args)

func _power() -> bool:
	return _world_get(&"power") == true

func _modal_open() -> bool:
	return _ui("is_modal_open", []) == true

func _player_hidden() -> bool:
	var pl := Game.player
	return pl != null and is_instance_valid(pl) and pl.get(&"hidden") == true

func _entity_state() -> String:
	var ent := Game.entity
	if ent == null or not is_instance_valid(ent): return ""
	var s = ent.get(&"state")
	return str(s) if s != null else ""

func _handles() -> Dictionary:
	var h = _world_get(&"handles")
	return h if h is Dictionary else {}

func _handle(id: String) -> Variant:
	var h = _handles().get(id)
	return h if h is Object and is_instance_valid(h) else null

func _handle_node(h) -> Node3D:
	if h == null or not (h is Object) or not is_instance_valid(h): return null
	if h is Node3D: return h
	for p in [&"node", &"object"]:
		var n = h.get(p)
		if n is Node3D and is_instance_valid(n): return n
	return null

func _is_handle(h) -> bool:
	return h != null and h is Object and is_instance_valid(h) and h.has_method("open") and _handle_node(h) != null

func _items() -> Dictionary:
	var it = _world_get(&"items")
	return it if it is Dictionary else {}

func _item(id: String) -> Node3D:
	var o = _items().get(id)
	return o if o is Node3D and is_instance_valid(o) else null

func _clues() -> Dictionary:
	var c = _world_get(&"clues")
	return c if c is Dictionary else {}

func _tv() -> Variant:
	var tv = _world_get(&"tv")
	return tv if tv is Object and is_instance_valid(tv) else null

func _tv_node() -> Node3D:
	var tv = _tv()
	if tv is Node3D: return tv
	if tv != null:
		for p in [&"node", &"object"]:
			var n = tv.get(p)
			if n is Node3D and is_instance_valid(n): return n
	var c = _clues().get("tv")
	return c if c is Node3D and is_instance_valid(c) else null

func _tv_pos() -> Vector3:
	var tv = _tv()
	if tv != null:
		var sp = tv.get(&"screen_position")
		if sp is Vector3 and sp != Vector3.ZERO: return sp
	var n := _tv_node()
	return n.global_position if n != null and n.is_inside_tree() else Vector3(-0.55, 1.47, -2.38)

func _closet_spot() -> Variant:
	var spots = _world_get(&"hide_spots")
	var spot = null
	if spots is Array:
		for s in spots:
			if s is Dictionary and s.get("id") == "closet":
				spot = s
				break
		if spot == null and not spots.is_empty() and spots[0] is Dictionary: spot = spots[0]
	var hd = _handle("door.closet")
	if spot == null and _is_handle(hd):
		var C: Dictionary = Layout.CLOSET
		spot = {
			"id": "closet", "door": hd,
			"hide_pos": Vector3(C.hidePos.x, C.hidePos.y, C.hidePos.z), "hide_yaw": float(C.hideYaw),
			"exit_pos": Vector3(C.exitPos.x, 0.0, C.exitPos.z),
			"minX": C.minX, "maxX": C.maxX, "minZ": C.minZ, "maxZ": C.maxZ,
		}
	elif spot != null and not _is_handle(spot.get("door")) and _is_handle(hd):
		spot = spot.duplicate()
		spot["door"] = hd
	return spot

## Searches the world for a node by name (world.props / prop_nodes dictionaries first, then the scene tree).
func _find(names: Array) -> Node3D:
	var w := Game.world
	if w == null or not is_instance_valid(w): return null
	for dict_name in [&"props", &"prop_nodes", &"nodes"]:
		var d = w.get(dict_name)
		if d is Dictionary:
			for n in names:
				var o = d.get(n)
				if o is Node3D and is_instance_valid(o): return o
	for n in names:
		var o := w.find_child(str(n), true, false)
		if o is Node3D: return o as Node3D
	return null

## Invisible box on LAYER_INTERACT for things that have no usable scene object (window, nook bulb).
func _proxy(pname: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "interact_" + pname
	body.collision_layer = LAYER_INTERACT
	body.collision_mask = 0
	body.set_meta(&"interact_proxy", true)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.position = pos
	_proxy_root.add_child(body)
	return body

func _hpos(h) -> Vector3:
	if h == null or not (h is Object) or not is_instance_valid(h): return Vector3.ZERO
	if h is Node3D: return (h as Node3D).global_position if (h as Node3D).is_inside_tree() else Vector3.ZERO
	if h.has_method("world_position"):
		var v = h.call("world_position")
		if v is Vector3: return v
	var n := _handle_node(h)
	return n.global_position if n != null and n.is_inside_tree() else Vector3.ZERO

func _panel_pos() -> Vector3:
	var h = _handle("powerBox.lever")
	if h == null: h = _handle("powerBox.door")
	if h != null:
		var v := _hpos(h)
		if v.length_squared() > 1e-6: return v
	var p: Array = Layout.PROPS["powerBox"]["pos"]
	return Vector3(p[0], p[1], p[2] + 0.1)

func _cam() -> Camera3D:
	var cam := Game.camera
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree(): return cam
	return null

func _cam_pos() -> Vector3:
	var cam := _cam()
	return cam.global_position if cam != null else Vector3(float(Layout.SPAWN.x), 1.62, float(Layout.SPAWN.z))

## Horizontal view direction (unit), -Z when unknown.
func _flat_dir() -> Vector3:
	var cam := _cam()
	if cam == null: return Vector3(0.0, 0.0, -1.0)
	var d := -cam.global_basis.z
	d.y = 0.0
	if d.length_squared() < 1e-6: return Vector3(0.0, 0.0, -1.0)
	return d.normalized()

func _looks_at(target: Vector3, min_dot: float, max_dist: float, need_los: bool, los_slack := 0.15) -> bool:
	var cam := _cam()
	if cam == null: return false
	var cp := cam.global_position
	var to := target - cp
	var d := to.length()
	if d > max_dist or d < 1e-3: return false
	if (-cam.global_basis.z.normalized()).dot(to) / d < min_dot: return false
	if need_los and _los_blocked(cp, target, los_slack): return false
	return true

## LOS on LAYER_WORLD that ignores the rocking chair's own colliders and anything within `slack` of the target
## (its box contains the target point).
func _los_blocked(from: Vector3, to: Vector3, slack: float) -> bool:
	var cam := _cam()
	if cam == null: return false
	var space := cam.get_world_3d().direct_space_state
	if space == null: return false
	if _rock_node != null and _rock_rids.is_empty() and is_instance_valid(_rock_node): _collect_rids(_rock_node, _rock_rids)
	_los_query.from = from
	_los_query.to = to
	_los_query.collision_mask = LAYER_WORLD
	_los_query.exclude = _rock_rids
	var hit := space.intersect_ray(_los_query)
	if hit.is_empty(): return false
	return from.distance_to(hit.get("position", to)) < from.distance_to(to) - slack

func _collect_rids(n: Node, out: Array[RID]) -> void:
	if n is CollisionObject3D: out.append((n as CollisionObject3D).get_rid())
	for c in n.get_children(): _collect_rids(c, out)

func _noise(position: Vector3, loudness: float, source: String) -> void:
	Events.noise.emit(position, loudness, source)

func _sfx(sound: String, position: Variant = null, volume := 1.0) -> void:
	var o := {"volume_db": linear_to_db(maxf(volume, 0.0001))}
	if position is Vector3: o["position"] = position
	Audio.play(sound, o)

func _say(text: String, seconds := -1.0, opts := {}) -> void:
	if text == "": return
	var sec := seconds if seconds > 0.0 else maxf(2.5, text.length() * 0.06)
	_ui("subtitle", [_fr(text), sec, opts])

## French typography: non-breaking space before ! ? : ; » and after «.
func _fr(s: String) -> String:
	for ch in ["!", "?", ":", ";", "»"]:
		s = s.replace(" " + ch, NBSP + ch)
	return s.replace("« ", "«" + NBSP)

func _cycle(id: String, lines: Array) -> String:
	var n := int(_seen.get("cycle." + id, 0))
	_seen["cycle." + id] = n + 1
	return str(lines[n % lines.size()]) if not lines.is_empty() else ""

func _with(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	r.merge(b, true)
	return r

func _make_code() -> String:
	var q := str(_args().get("code", ""))
	if Game.debug and q.length() == 4 and q.is_valid_int() and not q.contains("0") and not q.contains("-"): return q
	var s := ""
	for i in 4: s += str(randi_range(1, 9))
	return s

func _digits() -> Dictionary:
	return {"duck": code[0], "horse": code[1], "clock": code[2], "tv": code[3]}

func _digits_only(s: String) -> String:
	var out := ""
	for ch in s:
		if ch >= "0" and ch <= "9": out += ch
	return out

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out

# =================================================================== game-time waits & tweens

## `await _wait(s)`: resolves after `s` seconds of game time (advances only while playing). Returns the Waiter's signal so
## the awaiting coroutine never holds the Waiter itself (only _waits does): nothing leaks if the game quits mid-wait.
func _wait(seconds: float) -> Signal:
	var w := Waiter.new()
	w.t = seconds
	_waits.append(w)
	return w.done

func _tick_waits(dt: float) -> void:
	_clock += dt
	var i := _waits.size() - 1
	while i >= 0:
		if i < _waits.size():
			var w: Waiter = _waits[i]
			w.t -= dt
			if w.t <= 0.0:
				_waits.remove_at(i)
				w.fired = true
				w.done.emit()
		i -= 1

## `await _tween(d, fn)`: calls fn(k) with k going 0 -> 1 over `d` seconds of game time.
func _tween(duration: float, fn: Callable) -> Signal:
	var j := TweenJob.new()
	j.dur = maxf(1e-3, duration)
	j.fn = fn
	fn.call(0.0)
	_tweens.append(j)
	return j.done

func _tick_tweens(dt: float) -> void:
	var i := _tweens.size() - 1
	while i >= 0:
		if i < _tweens.size():
			var j: TweenJob = _tweens[i]
			j.t += dt
			var k := minf(1.0, j.t / j.dur)
			j.fn.call(k)
			if k >= 1.0:
				_tweens.erase(j)
				j.fired = true
				j.done.emit()
		i -= 1

static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)

## Lift + tilt a small object so its underside faces the camera, hold, put it back exactly.
func _tilt_reveal(obj: Node3D, on_revealed: Callable) -> void:
	var oid := obj.get_instance_id()
	if _tilting.has(oid) or not obj.is_inside_tree():
		on_revealed.call()
		return
	_tilting[oid] = true
	var t0 := obj.transform
	var d := _cam_pos() - obj.global_position
	d.y = 0.0
	if d.length_squared() < 1e-6: d = Vector3(0.0, 0.0, 1.0)
	d = d.normalized()
	var inv := Basis.IDENTITY
	var ps := 1.0
	var par := obj.get_parent() as Node3D
	if par != null:
		var pb := par.global_basis
		var sx := pb.get_scale().x
		ps = sx if absf(sx) > 1e-6 else 1.0
		inv = pb.orthonormalized().inverse()
	var axis := (inv * Vector3(-d.z, 0.0, d.x)).normalized()   # rotates -Y (the underside) toward the camera
	var lift := inv * Vector3(0.0, 0.12 / ps, 0.0)
	var gen := _gen
	var pose := func(e: float) -> void:
		if is_instance_valid(obj):
			obj.transform = Transform3D(Basis(axis, 1.15 * e) * t0.basis, t0.origin + lift * e)
	await _tween(0.4, func(k: float) -> void: pose.call(_ease(k)))
	if gen == _gen:
		on_revealed.call()
		await _wait(1.6)
		if gen == _gen:
			await _tween(0.4, func(k: float) -> void: pose.call(1.0 - _ease(k)))
	if is_instance_valid(obj): obj.transform = t0
	_tilting.erase(oid)
