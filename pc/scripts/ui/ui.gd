## UI module (ARCHITECTURE_PC.md §4) — port of src/ui/UI.js. CanvasLayer; all text French.
## The main menu lives ON the dresser TV (diegetic): teletext pages "CANAL 3 · LA GARDIENNE" rendered in a SubViewport
## and shown on the TV glass through a CRT shader, the menu camera framing the TV (scripts/ui/tv_menu.gd). The same
## teletext pages are reused full-screen for loading, pause, caught, game over and win (scripts/ui/crt_overlay.gd).
## Notes stay physical paper (note_view.gd), the keypad is the brass combination padlock (keypad_view.gd), the in-game
## HUD is almost empty (hud.gd + subtitles.gd). Mouse + keyboard + gamepad everywhere.
##
## Public API (keep; every show_* that waits for the player is a coroutine — await it):
##   show_loading(p, text); show_menu(); hide_menu(); show_pause() (await until "Reprendre"); hide_pause()
##   show_caught(night, total) (await); show_game_over() (await); show_win(time, night, total) (await); fade_to(alpha, seconds) (await)
##   set_prompt(text_or_empty, opts := {}) {hold: 0..1, key: "E" | "A"}; subtitle(text, seconds := 3.5, opts := {critical, hint, speaker})
##   set_objective(text); alert(text, seconds := 2.0); set_battery(v_or_-1); set_stamina(v); set_night(n, total); set_clues(d: Dictionary)
##   show_note(note: Dictionary) (await); show_keypad(title: String, length := 4) -> String ("" = cancelled) (await)
##   set_hidden(on: bool); is_modal_open() -> bool
##   menu_camera_active: bool; update_menu_camera(delta) (the TV menu owns the camera while in the menu; the UI calls it
##   itself every frame, calling it again in the same frame is harmless)
## Additions: set_inventory(items, notes); hide_loading(); show_options() / show_controls() / show_credits() (await, TV in
##   the menu, pause CRT otherwise); peek_objective(seconds); sfx(kind); last_input_gamepad; real_time.
## Emits Events.ui_start after the CRT power-off of "Nouvelle partie". Settings written by the options pages: quality,
##   brightness, fov, camera_motion, fullscreen, vsync (applied here: DisplayServer), volume (+ Audio.set_master_volume),
##   subtitles, sensitivity, invert_y.
## Calls (all optional): Game.world.lighting.set_tv_light(on, intensity) (else Game.world.tv.set_on) and
##   lighting.set_menu_mode(on) while the TV menu is up, Audio.play/loop/stop_all/set_master_volume.
## Debug (after --): --ui-shots=menu,options,...,win --ui-out=/abs/prefix  (scripts/ui/tests/ui_shots_driver.gd)
extends CanvasLayer

const Style := preload("res://scripts/ui/ui_style.gd")
const Pages := preload("res://scripts/ui/tt_pages.gd")
const TvMenu := preload("res://scripts/ui/tv_menu.gd")
const CrtOverlay := preload("res://scripts/ui/crt_overlay.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Subs := preload("res://scripts/ui/subtitles.gd")
const NoteView := preload("res://scripts/ui/note_view.gd")
const KeypadView := preload("res://scripts/ui/keypad_view.gd")
const TT := preload("res://scripts/ui/teletext.gd")

signal pause_closed
signal note_closed
signal keypad_closed(result: String)
signal end_closed

const CATCH_FLAVORS := [
	"Tu te réveilles en bas de l’escalier. La maison est silencieuse… pour l’instant.",
	"Tu rouvres les yeux sur le tapis. Quelqu’un a rangé tes affaires.",
	"Une berceuse s’éloigne à l’étage. Tu es encore dans le sous-sol.",
]

var label := Label.new()              # stub member (kept, hidden)
var menu_camera_active := false

# state read by the teletext pages
var real_time := 0.0
var night := 1
var nights_total := 3
var objective_text := ""
var clues: Dictionary = {}
var inventory_items: Array = []
var notes: Array = []
var loading_state := {"p": 0.0, "text": "Initialisation…", "hidden": false}
var tip := ""
var last_input_gamepad := false

var pages: Pages
var tv: TvMenu
var crt: CrtOverlay
var hud: Hud
var subs: Subs
var fade: ColorRect
var pulse: TextureRect
var note_view: NoteView
var keypad_view: KeypadView
var layers_root: Control

var _modal := false
var _layers: Array[Dictionary] = []
var _guard_until := 0.0
var _pause_open := false
var _end := {}
var _fade_seq := 0
var _fade_tween: Tween
var _last_us := 0
var _pulse_t0 := -10.0
var _combo: Array = [0, 0, 0, 0]
var _nav_dir := ""
var _nav_t := 0.0
var _nav_owner := ""
var _mouse_down := Vector2(-1, -1)
var _wheel := 0.0
var _quitting := false
var _sel_sfx_at := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	name = "UI"
	label.visible = false
	add_child(label)
	tip = Pages.TIPS[randi() % Pages.TIPS.size()]
	pages = Pages.new(self)
	hud = Hud.new()
	add_child(hud)
	pulse = TextureRect.new()
	pulse.name = "SpottedPulse"
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	gr.colors = PackedColorArray([Color(0.43, 0.047, 0.024, 0.0), Color(0.43, 0.047, 0.024, 0.0), Color(0.43, 0.047, 0.024, 0.55)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	pulse.texture = gt
	pulse.stretch_mode = TextureRect.STRETCH_SCALE
	pulse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.modulate.a = 0.0
	add_child(pulse)
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.visible = false
	add_child(fade)
	subs = Subs.new()
	add_child(subs)
	layers_root = Control.new()
	layers_root.name = "Layers"
	layers_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layers_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layers_root)
	crt = CrtOverlay.new()
	layers_root.add_child(crt)
	crt.setup(self)
	note_view = NoteView.new()
	layers_root.add_child(note_view)
	note_view.setup(self)
	note_view.close_requested.connect(_close_note)
	keypad_view = KeypadView.new()
	layers_root.add_child(keypad_view)
	keypad_view.setup(self)
	keypad_view.finished.connect(_kp_finish)
	tv = TvMenu.new()
	add_child(tv)
	tv.setup(self)
	Events.game_state.connect(_on_state)
	Events.inventory_changed.connect(_on_inventory)
	Events.player_flashlight.connect(_on_flashlight)
	Events.player_stamina.connect(_on_stamina)
	Events.player_hide.connect(_on_player_hide)
	Events.entity_spotted.connect(_pulse_spotted)
	Events.settings_changed.connect(_on_settings_changed)
	_open_crt("loading", "loading", 0.0)
	_apply_display_settings_at_boot()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--ui-shots="):
			var drv_script := load("res://scripts/ui/tests/ui_shots_driver.gd") as GDScript   # not in exported builds
			if drv_script != null:
				var drv: Node = drv_script.new()
				drv.name = "UiShotsDriver"
				add_child(drv)
			break

func _exit_tree() -> void:
	for pair in [[Events.game_state, _on_state], [Events.inventory_changed, _on_inventory], [Events.player_flashlight, _on_flashlight],
			[Events.player_stamina, _on_stamina], [Events.player_hide, _on_player_hide], [Events.entity_spotted, _pulse_spotted],
			[Events.settings_changed, _on_settings_changed]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# ================================================================ per frame

func _process(_delta: float) -> void:
	var us := Time.get_ticks_usec()
	var dt := clampf((us - _last_us) / 1000000.0, 0.0, 0.1) if _last_us > 0 else 0.016
	_last_us = us
	real_time += dt
	hud.update(dt)
	subs.suppressed = not _top_modal().is_empty() and Game.state != "playing"
	subs.update(dt)
	var pt := Style.now() - _pulse_t0
	pulse.modulate.a = 0.0 if pt > 1.2 else (pt / 0.168 if pt < 0.168 else 1.0 - (pt - 0.168) / 1.032)
	tv.process_frame(dt)
	_update_menu_flag()
	if menu_camera_active:
		tv.update_camera(dt)
	if crt.visible:
		if crt.mode == "end" and not _end.is_empty() and not bool(_end.ready) and Style.now() >= float(_end.ready_at):
			_end.ready = true
			crt.screen.dirty = true
		crt.process_frame(dt)
	note_view.process_frame(dt)
	keypad_view.process_frame(dt)
	_poll_nav(dt)

func _update_menu_flag() -> void:
	var s: String = Game.state
	menu_camera_active = tv.on and (s == "menu" or s == "loading")

func _menu_active() -> bool:
	return tv.on and Game.state == "menu"

## Writes the menu camera (web updateMenuCamera). Called by the UI every frame while menu_camera_active.
func update_menu_camera(delta := 0.0) -> void:
	tv.update_camera(delta)

# ================================================================ input

## Tracks the last input device (hints show "A"/"B" after gamepad input). Public: the views forward GUI events.
func note_input_device(e: InputEvent) -> void:
	var pad := last_input_gamepad
	if e is InputEventJoypadButton:
		pad = true
	elif e is InputEventJoypadMotion:
		if absf((e as InputEventJoypadMotion).axis_value) > 0.4:
			pad = true
	elif e is InputEventKey or e is InputEventMouseButton:
		pad = false
	elif e is InputEventMouseMotion and (e as InputEventMouseMotion).relative.length() > 3.0:
		pad = false
	if pad != last_input_gamepad:
		last_input_gamepad = pad
		tv.screen.dirty = true
		crt.screen.dirty = true
		hud.hide_hint = _hide_hint_text()

func _action_of(e: InputEvent) -> Array:
	if e is InputEventKey:
		var k := e as InputEventKey
		if not k.pressed:
			return []
		var echo := k.echo
		match k.keycode:
			KEY_UP: return ["up", ""]
			KEY_DOWN: return ["down", ""]
			KEY_LEFT: return ["left", ""]
			KEY_RIGHT: return ["right", ""]
			KEY_ENTER, KEY_KP_ENTER: return [] if echo else ["accept", ""]
			KEY_SPACE: return [] if echo else ["space", ""]
			KEY_ESCAPE: return [] if echo else ["back", ""]
			KEY_BACKSPACE: return ["bksp", ""]
			KEY_PAGEUP: return ["pgup", ""]
			KEY_PAGEDOWN: return ["pgdn", ""]
			KEY_TAB: return [] if echo else ["tab", ""]
		if k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
			return ["digit", str(k.keycode - KEY_KP_0)]
		if k.unicode >= 48 and k.unicode <= 57:
			return ["digit", String.chr(k.unicode)]
		if k.physical_keycode >= KEY_0 and k.physical_keycode <= KEY_9:
			return ["digit", str(k.physical_keycode - KEY_0)]
		match k.physical_keycode:
			KEY_W: return ["up", ""]
			KEY_S: return ["down", ""]
			KEY_A: return ["left", ""]
			KEY_D: return ["right", ""]
			KEY_E: return [] if echo else ["e", ""]
			KEY_P: return [] if echo else ["pause", ""]
		return []
	if e is InputEventJoypadButton:
		var b := e as InputEventJoypadButton
		if not b.pressed:
			return []
		match b.button_index:
			JOY_BUTTON_A: return ["accept", ""]
			JOY_BUTTON_B: return ["back", ""]
			JOY_BUTTON_START: return ["pause", ""]
			JOY_BUTTON_LEFT_SHOULDER: return ["pgup", ""]
			JOY_BUTTON_RIGHT_SHOULDER: return ["pgdn", ""]
			JOY_BUTTON_DPAD_UP: return ["up", ""]
			JOY_BUTTON_DPAD_DOWN: return ["down", ""]
			JOY_BUTTON_DPAD_LEFT: return ["left", ""]
			JOY_BUTTON_DPAD_RIGHT: return ["right", ""]
		return []
	return []

func _input(e: InputEvent) -> void:
	note_input_device(e)
	if _quitting:
		if e is InputEventKey or e is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	var top := _top_modal()
	if not top.is_empty():
		if e is InputEventMouse:
			return                                   # the layer's Controls handle the mouse (GUI input)
		var act := _action_of(e)
		if not act.is_empty():
			(top.nav as Callable).call(act[0], act[1])
			get_viewport().set_input_as_handled()
		elif e is InputEventKey or e is InputEventJoypadButton:
			get_viewport().set_input_as_handled()    # nothing leaks to the game behind a modal
		return
	if _menu_active():
		if _menu_mouse(e):
			get_viewport().set_input_as_handled()
			return
		var act2 := _action_of(e)
		if not act2.is_empty():
			_dispatch(act2[0], act2[1])
			get_viewport().set_input_as_handled()
		return
	if Game.state == "playing" and InputMap.has_action("objective") and e.is_action_pressed("objective") and not e.is_echo():
		hud.peek_objective(4.0)

func _menu_mouse(e: InputEvent) -> bool:
	if not tv.trans.is_empty():
		return e is InputEventMouseButton
	if e is InputEventMouseMotion:
		var hit := tv.pick((e as InputEventMouseMotion).position)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if not hit.is_empty() else Input.CURSOR_ARROW)
		if not hit.is_empty():
			tv.screen.select(hit.it.id)
		return false
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_wheel += (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0) * maxf(1.0, mb.factor)
				if absf(_wheel) >= 1.0:
					tv.screen.move(1 if _wheel > 0.0 else -1)
					_wheel = 0.0
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_down = mb.position
			elif _mouse_down.x >= 0.0:
				var moved := mb.position.distance_to(_mouse_down)
				_mouse_down = Vector2(-1, -1)
				if moved <= 14.0:
					var hit := tv.pick(mb.position)
					if not hit.is_empty():
						tv.screen.select(hit.it.id, false)
						tv.screen.activate(int(hit.side))
			return true
	return false

## Routes a navigation action to the top modal layer or to the TV menu.
func _dispatch(action: String, data := "") -> void:
	var top := _top_modal()
	if not top.is_empty():
		(top.nav as Callable).call(action, data)
		return
	if _menu_active():
		if not tv.trans.is_empty():
			return
		match action:
			"space": tv.screen.nav("accept")
			"bksp": tv.screen.nav("back")
			"pause", "tab", "e", "pgup", "pgdn": pass
			_: tv.screen.nav(action, data)

func _nav_target_id() -> String:
	var top := _top_modal()
	if not top.is_empty():
		return str((top.node as Node).get_instance_id())
	if _menu_active():
		return "menu"
	return ""

## Gamepad left stick (and held D-pad) with key repeat (0.38 s then every 0.11 s). A D-pad press itself acts through
## its button event (_action_of); polling only repeats it.
func _poll_nav(dt: float) -> void:
	var owner_id := _nav_target_id()
	var dir := ""
	var from_stick := false
	if owner_id != "":
		for dev in Input.get_connected_joypads():
			if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP): dir = "up"
			elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN): dir = "down"
			elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT): dir = "left"
			elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT): dir = "right"
			else:
				var x := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
				var y := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
				if absf(y) > 0.55 and absf(y) >= absf(x): dir = "down" if y > 0.0 else "up"
				elif absf(x) > 0.55: dir = "right" if x > 0.0 else "left"
				from_stick = dir != ""
			if dir != "":
				break
	if owner_id != _nav_owner:
		_nav_owner = owner_id
		_nav_dir = dir                                # a stick held while a modal opens does not act
		_nav_t = 0.38
		return
	if dir != _nav_dir:
		_nav_dir = dir
		_nav_t = 0.38
		if dir != "" and from_stick:
			_dispatch(dir)
	elif dir != "":
		_nav_t -= dt
		if _nav_t <= 0.0:
			_nav_t = 0.11
			_dispatch(dir)

func _crt_nav(action: String, data := "") -> void:
	var s := crt.screen
	if crt.mode == "pause":
		match action:
			"pause":
				hide_pause()
			"back":
				if s.page_name == "pause": hide_pause()
				else: s.nav("back")
			"bksp": s.nav("back")
			"space": s.nav("accept")
			"tab", "pgup", "pgdn": pass
			_: s.nav(action, data)
	elif crt.mode == "end":
		if _end.is_empty() or not bool(_end.ready):
			return
		match action:
			"space", "e": s.nav("accept")
			"up", "down", "left", "right", "accept": s.nav(action, data)

# ================================================================ layers (modal stack)

func _top_modal() -> Dictionary:
	for i in range(_layers.size() - 1, -1, -1):
		if bool(_layers[i].modal):
			return _layers[i]
	return {}

func _push_layer(node: Control, modal: bool, nav: Callable) -> void:
	for L in _layers:
		if L.node == node:
			L.nav = nav
			L.modal = modal
			layers_root.move_child(node, -1)
			_sync_modal()
			return
	_layers.append({"node": node, "modal": modal, "nav": nav})
	layers_root.move_child(node, -1)
	_sync_modal()

func _pop_layer(node: Control) -> void:
	for i in _layers.size():
		if _layers[i].node == node:
			_layers.remove_at(i)
			break
	_sync_modal()

func _sync_modal() -> void:
	var m := false
	for L in _layers:
		if bool(L.modal):
			m = true
	if not m and _modal:
		_guard_until = Style.now() + 0.2
	_modal = m

func is_modal_open() -> bool:
	return _modal or Style.now() < _guard_until

# ================================================================ teletext navigation helpers (used by the pages)

func goto_page(screen: TT, page: String, sel := "", sound := true) -> void:
	var prev := screen.page_name
	var fn := pages.get_fn(page)
	if not fn.is_valid():
		return
	screen.show_page(page, fn, sel)
	if sound and prev != page:
		screen.flick = 1.0
		sfx("page")
	if screen == crt.screen and prev != "" and prev != page:
		screen.burst = maxf(screen.burst, 0.12)
		screen.burst_max = 0.3

func _wait_page_left(screen: TT, page: String) -> void:
	while is_instance_valid(screen) and screen.page_name == page:
		await screen.page_changed

func sfx(kind: String) -> void:
	match kind:
		"select":
			var t := Style.now()
			if t - _sel_sfx_at < 0.04:
				return
			_sel_sfx_at = t
			Audio.play("flashlight_click", {"volume_db": linear_to_db(0.22), "pitch": 1.25, "ui": true})
		"value":
			Audio.play("lock_wheel", {"volume_db": linear_to_db(0.35), "pitch": 1.1, "ui": true})
		"page":
			Audio.play("tv_on", {"volume_db": linear_to_db(0.22), "pitch": 1.15, "ui": true})
		"off":
			Audio.play("tv_off", {"volume_db": linear_to_db(0.55), "ui": true})

func clock_minutes() -> int:
	return 3 * 60 + 7 + floori(real_time / 60.0)

func nav_hint(page: String) -> String:
	var pad := last_input_gamepad
	match page:
		"main": return "▲▼ CHOISIR   A OK" if pad else "▲▼ CHOISIR   ENTRÉE OK"
		"options": return "◄► RÉGLER   B RETOUR" if pad else "◄► RÉGLER   ÉCHAP RETOUR"
		"controls": return "◄► AUTRE PAGE   B RETOUR" if pad else "◄► AUTRE PAGE   ÉCHAP RETOUR"
		"pause": return "▲▼ CHOISIR   A OK   B REPRENDRE" if pad else "▲▼ CHOISIR   ENTRÉE OK   ÉCHAP REPRENDRE"
	return ""

func all_notes() -> Array:
	if not notes.is_empty():
		return notes
	var inv: Node = Game.inventory
	if inv != null and is_instance_valid(inv):
		var n: Variant = inv.get("notes")
		if n is Array:
			return n
	return []

func end_ready() -> bool:
	return not _end.is_empty() and bool(_end.ready)

func end_cfg() -> Dictionary:
	return _end.get("cfg", {})

# ================================================================ state

func _on_state(s: String, _prev: String) -> void:
	hud.set_on(s == "playing")
	if s == "playing":
		_hide_loading()
		if tv.on:
			_tv_deactivate()
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if s != "playing":
		set_prompt("")
	if s == "caught" or s == "gameover" or s == "won":
		subs.hide_now()
	_update_menu_flag()

func _on_inventory(items: Array, nts: Array) -> void:
	set_inventory(items, nts)

func _on_flashlight(has: bool, on: bool, battery: float) -> void:
	hud.flash_on = has and on
	set_battery(battery / 100.0 if has else -1.0)

func _on_stamina(value: float, _exhausted: bool, _breath: float) -> void:
	set_stamina(value)

func _on_player_hide(hidden_: bool, _spot: String) -> void:
	set_hidden(hidden_)

func _pulse_spotted() -> void:
	if Game.state == "playing":
		_pulse_t0 = Style.now()

func _on_settings_changed(key: String, value: Variant) -> void:
	tv.screen.dirty = true
	crt.screen.dirty = true
	match key:
		"subtitles":
			if value == false and not subs.critical:
				subs.hide_now()
		"fullscreen":
			_apply_fullscreen(bool(value))
		"vsync":
			_apply_vsync(bool(value))

# ================================================================ display settings

func set_fullscreen(on: bool) -> void:
	Settings.set_value("fullscreen", on)

func set_vsync(on: bool) -> void:
	Settings.set_value("vsync", on)

func _display_ok() -> bool:
	return DisplayServer.get_name() != "headless"

func _apply_fullscreen(on: bool) -> void:
	if not _display_ok():
		return
	var cur := DisplayServer.window_get_mode()
	var is_fs := cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if on and not is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not on and is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var scr := DisplayServer.window_get_current_screen()
		var ss := DisplayServer.screen_get_size(scr)
		var ws := Vector2i(int(ss.x * 0.75), int(ss.y * 0.75))
		DisplayServer.window_set_size(ws)
		DisplayServer.window_set_position(DisplayServer.screen_get_position(scr) + (ss - ws) / 2)

func _apply_vsync(on: bool) -> void:
	if not _display_ok():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)

## The saved fullscreen / vsync choices are applied at start, unless the command line forces a window mode.
func _apply_display_settings_at_boot() -> void:
	for a in OS.get_cmdline_args():
		if a in ["--windowed", "-w", "--fullscreen", "-f", "--maximized", "-m"] or a.begins_with("--resolution") or a.begins_with("--position"):
			return
	_apply_fullscreen(bool(Settings.get_value("fullscreen", true)))
	_apply_vsync(bool(Settings.get_value("vsync", true)))

# ================================================================ loading

func show_loading(p: float, text: String) -> void:
	if bool(loading_state.hidden):
		return
	loading_state.p = Style.clamp01(p)
	if text != "":
		loading_state.text = text
	crt.screen.dirty = true
	if p >= 0.85 and not tv.on and Game.world != null and Game.state == "loading":
		_tv_activate()
		update_menu_camera(0.0)

func hide_loading() -> void:
	_hide_loading()

func _hide_loading() -> void:
	if bool(loading_state.hidden):
		return
	loading_state.hidden = true
	if crt.mode == "loading" and crt.is_open:
		crt.close(0.95)

func _open_crt(mode: String, page: String, burst: float) -> void:
	crt.open(mode, burst)
	goto_page(crt.screen, page, "", false)
	crt.screen.build()
	if mode == "loading":
		_pop_layer(crt)
		layers_root.move_child(crt, -1)
	else:
		_push_layer(crt, true, _crt_nav)

func _close_crt(delay: float) -> void:
	crt.close(delay)
	_pop_layer(crt)

# ================================================================ menu (TV)

func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tv_activate()
	tv.screen.locked = false
	if tv.screen.page_name != "main":
		goto_page(tv.screen, "main", "", false)
	_update_menu_flag()
	update_menu_camera(0.0)
	_hide_loading()

func hide_menu() -> void:
	_hide_loading()
	_tv_deactivate()

func _tv_activate() -> void:
	tv.activate()
	if tv.screen.page_name == "":
		goto_page(tv.screen, "main", "", false)
	_update_menu_flag()

func _tv_deactivate() -> void:
	tv.deactivate()
	_update_menu_flag()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

## "Nouvelle partie": static burst + CRT power-off collapse, fade to black, then Events.ui_start.
func tv_start_game(mode := "normal") -> void:
	if not tv.trans.is_empty():
		return
	Game.mode = mode
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	tv.power_off(_on_power_off_start)

func _on_power_off_start() -> void:
	var seq := _fade_seq
	Events.ui_start.emit()
	# gameplay usually fades in itself (intro); otherwise reveal the room
	await get_tree().create_timer(0.12, true, false, true).timeout
	if _fade_seq == seq:
		fade_to(0.0, 1.6)

## "Quitter" in the index: same CRT power-off, then the game closes.
func tv_quit_game() -> void:
	if not tv.trans.is_empty():
		return
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	tv.power_off(_on_power_off_quit)

func _on_power_off_quit() -> void:
	_quitting = true
	Audio.stop_all(0.3)
	await get_tree().create_timer(0.4, true, false, true).timeout
	get_tree().quit()

# ================================================================ options / controls / credits (awaitable helpers)

func _page_screen() -> TT:
	if _menu_active():
		return tv.screen
	if not (crt.is_open and crt.mode == "pause"):
		_open_crt("pause", "pause", 0.0)
	return crt.screen

func show_options() -> void:
	var s := _page_screen()
	pages.opt_sub = 0
	goto_page(s, "options")
	await _wait_page_left(s, "options")

func show_controls() -> void:
	var s := _page_screen()
	pages.ctl_sub = -1
	goto_page(s, "controls")
	await _wait_page_left(s, "controls")

func show_credits() -> void:
	var s := _page_screen()
	goto_page(s, "credits")
	await _wait_page_left(s, "credits")

# ================================================================ pause

func show_pause() -> void:
	if not _pause_open:
		_pause_open = true
		_open_crt("pause", "pause", 0.12)
		sfx("page")
	await pause_closed

func hide_pause() -> void:
	var overlay := crt.is_open and crt.mode == "pause"
	if not _pause_open and not overlay:
		return
	if note_view.is_open:
		_close_note()
	if overlay:
		goto_page(crt.screen, "pause", "", false)     # resolves pending options / controls waiters
		_close_crt(0.2)
	if _pause_open:
		_pause_open = false
		pause_closed.emit()

## Pause "Quitter" → back to the TV menu (reloads the main scene).
func quit_to_menu() -> void:
	if _quitting:
		return
	_quitting = true
	crt.screen.locked = true
	Audio.stop_all(0.4)
	crt.close(0.35)
	await fade_to(1.0, 0.4)
	Game.night = 1
	Game.time_played = 0.0
	get_tree().paused = false
	get_tree().reload_current_scene()

## Pause "Quitter le jeu".
func quit_app() -> void:
	if _quitting:
		return
	_quitting = true
	crt.screen.locked = true
	Audio.stop_all(0.3)
	crt.close(0.35)
	await fade_to(1.0, 0.4)
	get_tree().quit()

# ================================================================ caught / game over / win

func _show_end(page: String, cfg: Dictionary, ready_delay: float) -> void:
	if not _end.is_empty():
		end_finish()
	if _pause_open:
		hide_pause()
	subs.hide_now()
	set_prompt("")
	_end = {"page": page, "cfg": cfg, "ready_at": Style.now() + ready_delay, "ready": false}
	_open_crt("end", page, 0.45 if page == "win" else 0.8)
	Audio.play("tv_static", {"volume_db": linear_to_db(0.25), "ui": true})
	await end_closed

func end_finish() -> void:
	if _end.is_empty():
		return
	_end = {}
	if crt.mode == "end":
		_close_crt(0.25)
	end_closed.emit()

func show_caught(night_: int, total: int) -> void:
	var left := maxi(0, total - night_)
	var rest := "C’est ta dernière nuit." if left == 0 else "Encore %d nuit%s avant qu’elle te garde." % [left, "s" if left > 1 else ""]
	var cfg := {
		"night": night_, "total": total, "rest": rest,
		"text": CATCH_FLAVORS[posmod(night_ - 2, CATCH_FLAVORS.size())],
		"tip": "Conseil : " + str(Pages.TIPS[randi() % Pages.TIPS.size()]),
	}
	await _show_end("caught", cfg, 1.5)

func show_game_over() -> void:
	var total := int(Game.NIGHTS_TOTAL)
	await _show_end("gameover", {"total": total, "text": "Trois nuits. Personne n’est venu te chercher. Tu fais partie du sous-sol, maintenant."}, 2.2)

func show_win(time: float, night_: int, total: int) -> void:
	var s := maxi(0, roundi(time))
	var hh := s / 3600
	var mm := (s % 3600) / 60
	var ss := s % 60
	var time_str := ("%d H %02d MIN" % [hh, mm]) if hh > 0 else ("%d MIN %02d S" % [mm, ss])
	var text := "Sans te faire attraper une seule fois." if night_ <= 1 else "En bas, quelqu’un fredonne encore."
	await _show_end("win", {"time_str": time_str, "nights_used": night_, "total": total, "text": text}, 2.0)

# ================================================================ fade

func fade_to(alpha: float, seconds := 1.0) -> void:
	_fade_seq += 1
	var a := Style.clamp01(alpha)
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if seconds <= 0.0:
		fade.color.a = a
		fade.visible = a > 0.001
		return
	fade.visible = true
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.tween_property(fade, "color:a", a, seconds)
	await get_tree().create_timer(seconds + 0.03, true, false, true).timeout
	if is_instance_valid(fade) and fade.color.a <= 0.001:
		fade.visible = false

# ================================================================ HUD API

func set_prompt(text: Variant, opts := {}) -> void:
	var t := "" if text == null else Style.fr(str(text))
	var key := str(opts.get("key", "E")) if opts is Dictionary else "E"
	var pad := key == "A" or key == "✋"
	var lab := "A" if pad else (Style.key_label(KEY_E) if key == "E" else key)
	var hold := -1.0
	if opts is Dictionary and opts.has("hold") and opts.hold != null:
		hold = Style.clamp01(float(opts.hold))
	hud.set_prompt(t, lab, pad, hold if t != "" else -1.0)

func subtitle(text: Variant, seconds := 3.5, opts := {}) -> void:
	var t := "" if text == null else str(text)
	if t == "":
		subs.hide_now()
		return
	var critical := bool(opts.get("critical", false)) or bool(opts.get("force", false))
	if not critical and Settings.get_value("subtitles", true) == false:
		return
	subs.show_text(Style.fr(t), maxf(0.8, seconds if seconds > 0.0 else 3.5), critical, Style.fr(str(opts.get("speaker", ""))), bool(opts.get("hint", false)))

func set_objective(text: Variant) -> void:
	objective_text = Style.fr("" if text == null else str(text))
	hud.set_objective(objective_text)
	if crt.is_open and crt.mode == "pause":
		crt.screen.dirty = true

func peek_objective(seconds := 4.0) -> void:
	hud.peek_objective(seconds)

func alert(text: Variant, seconds := 2.0) -> void:
	hud.alert(Style.up("" if text == null else str(text)), maxf(0.5, seconds))

func set_inventory(items: Array, notes_: Variant = null) -> void:
	inventory_items = []
	for it in items:
		if it is Dictionary and int(it.get("count", 1)) > 0:
			inventory_items.append(it)
	if notes_ is Array:
		notes = notes_
	if crt.is_open and crt.mode == "pause":
		crt.screen.dirty = true

func set_battery(v: float) -> void:
	hud.set_battery(-1.0 if v < 0.0 or is_nan(v) else Style.clamp01(v))

func set_stamina(v: float) -> void:
	hud.set_stamina(Style.clamp01(v))

func set_night(n: int, total: int) -> void:
	night = maxi(1, n)
	nights_total = maxi(1, total)

func set_clues(d: Dictionary) -> void:
	clues = {}
	for k in ["duck", "horse", "clock", "tv"]:
		var v: Variant = d.get(k)
		clues[k] = null if v == null or str(v) == "" else str(v)
	keypad_view.set_clues(clues)
	if crt.is_open and crt.mode == "pause":
		crt.screen.dirty = true

func set_hidden(on: bool) -> void:
	hud.hide_hint = _hide_hint_text()
	hud.set_hidden(on)

func _hide_hint_text() -> String:
	return "Caché. Appuie sur %s pour sortir." % ("A" if last_input_gamepad else Style.key_label(KEY_E))

# ================================================================ notes

func show_note(note: Dictionary) -> void:
	if note_view.is_open:
		_close_note()
	note_view.open(note, "A" if last_input_gamepad else Style.key_label(KEY_E), last_input_gamepad)
	_push_layer(note_view, true, note_view.nav)
	await note_closed

## Pause → Notes → a note (fire and forget; the notes page stays underneath).
func reread_note(n: Dictionary) -> void:
	show_note(n)

func _close_note() -> void:
	if not note_view.is_open:
		return
	note_view.close()
	_pop_layer(note_view)
	note_closed.emit()

# ================================================================ keypad (brass padlock)

func show_keypad(title: String, length := 4) -> String:
	if keypad_view.is_open:
		_kp_finish("")
	var n := clampi(length, 1, 8)
	if _combo.size() != n:
		_combo = []
		for i in n:
			_combo.append(0)
	keypad_view.open(title, n, _combo, clues, last_input_gamepad)
	_push_layer(keypad_view, true, keypad_view.nav)
	var r: Variant = await keypad_closed
	return str(r) if r != null else ""

func _kp_finish(result: String) -> void:
	if not keypad_view.is_open:
		return
	_combo = []
	for d in keypad_view.digits:
		_combo.append(d)
	keypad_view.close()
	_pop_layer(keypad_view)
	keypad_closed.emit(result)
