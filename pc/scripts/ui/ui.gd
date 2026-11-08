## STUB — ui module replaces it (ARCHITECTURE_PC.md §UI). CanvasLayer; all text French.
## Public API (keep; every show_* that waits for the player is a coroutine — await it):
##   show_loading(p, text); show_menu(); hide_menu(); show_pause() (await until "Reprendre"); hide_pause()
##   show_caught(night, total) (await); show_game_over() (await); show_win(time, night, total) (await); fade_to(alpha, seconds) (await)
##   set_prompt(text_or_empty, opts := {}) {hold: 0..1, key: "E"}; subtitle(text, seconds := 3.5, opts := {critical}); set_objective(text)
##   alert(text, seconds := 2.0); set_battery(v_or_-1); set_stamina(v); set_night(n, total); set_clues(d: Dictionary)
##   show_note(note: Dictionary) (await); show_keypad(title: String, length := 4) -> String ("" = cancelled) (await)
##   set_hidden(on: bool); is_modal_open() -> bool
##   menu_camera_active: bool; update_menu_camera(delta) (the TV menu owns the camera while in the menu)
extends CanvasLayer

var label := Label.new()
var menu_camera_active := false
var _modal := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	label.position = Vector2(24, 24); add_child(label)

func show_loading(p: float, t: String) -> void: label.text = "%s %d%%" % [t, int(p * 100)]
func show_menu() -> void:
	label.text = "LA GARDIENNE — appuie sur Entrée"
func hide_menu() -> void: label.text = ""
func _unhandled_input(e: InputEvent) -> void:
	if Game.state == "menu" and e is InputEventKey and e.pressed and e.keycode == KEY_ENTER:
		hide_menu(); Events.ui_start.emit()
func show_pause() -> void: await get_tree().create_timer(0.1).timeout
func hide_pause() -> void: pass
func show_caught(_n: int, _t: int) -> void: await get_tree().create_timer(0.5).timeout
func show_game_over() -> void: await get_tree().create_timer(0.5).timeout
func show_win(_t: float, _n: int, _tot: int) -> void: await get_tree().create_timer(0.5).timeout
func fade_to(_a: float, s: float) -> void: await get_tree().create_timer(s).timeout
func set_prompt(t: String, _o := {}) -> void: label.text = t
func subtitle(t: String, _s := 3.5, _o := {}) -> void: print("[sub] ", t)
func set_objective(t: String) -> void: print("[obj] ", t)
func alert(t: String, _s := 2.0) -> void: print("[alert] ", t)
func set_battery(_v: float) -> void: pass
func set_stamina(_v: float) -> void: pass
func set_night(_n: int, _t: int) -> void: pass
func set_clues(_d: Dictionary) -> void: pass
func show_note(_n: Dictionary) -> void: await get_tree().process_frame
func show_keypad(_t: String, _l := 4) -> String: await get_tree().process_frame; return ""
func set_hidden(_on: bool) -> void: pass
func is_modal_open() -> bool: return _modal
func update_menu_camera(_d: float) -> void: pass
