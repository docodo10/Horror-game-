## UI module headless test: runs the real main scene and drives the UI with simulated keyboard / mouse input.
##   godot --headless --path pc -s res://scripts/ui/tests/test_ui.gd
## Checks the TV menu (pages, navigation, digits, options writing Settings, mouse picking through the curved glass,
## menu camera), the power-off start, HUD API, pause CRT (Esc / Reprendre / options / notes), paper notes, the padlock
## keypad (digits, wheel steps, cancel), caught / game over / win screens and fades. Prints PASS/FAIL and exits 0/1.
extends SceneTree

var ui: Node
var G: Node
var S: Node
var E: Node
var fails := 0
var passes := 0
var _kp_result: Variant = null
var _kp_done := false
var _note_done := false
var _end_done := false
var _pause_done := false

func _initialize() -> void:
	var ps := load("res://scenes/main.tscn") as PackedScene
	var main := ps.instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func secs(s: float) -> void:
	await create_timer(s, true, false, true).timeout

func key(code: Key, physical := false, unicode := 0) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		if physical:
			e.physical_keycode = code
		else:
			e.keycode = code
		e.unicode = unicode
		e.pressed = pressed
		root.push_input(e)
	await process_frame

func digit(d: int) -> void:
	await key(KEY_0 + d, false, 48 + d)

func pad(btn: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = btn
		e.pressed = pressed
		root.push_input(e)
	await process_frame

func _run() -> void:
	G = root.get_node("Game")
	S = root.get_node("Settings")
	E = root.get_node("Events")
	print("[test_ui] waiting for the menu…")
	for i in 600:
		await process_frame
		if G.state == "menu":
			break
	ui = G.ui
	ok(G.state == "menu", "main scene reaches the menu state")
	ok(ui != null and ui.get("tv") != null, "UI built with the TV menu")
	await frames(5)
	var tv = ui.tv
	var scr = tv.screen
	ok(tv.on, "TV menu is on")
	ok(ui.menu_camera_active, "menu_camera_active while in the menu")
	ok(scr.page_name == "main", "P100 index shown")
	var ids := []
	for it in scr.items:
		ids.append(it.id)
	ok(ids == ["play", "explore", "options", "controls", "credits", "quit"], "index items %s" % [ids])
	ok(bool(ui.loading_state.hidden), "loading hidden after show_menu")
	# camera frames the TV
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	ok(cam != null and cam == tv.cam, "the menu camera is current in the menu")
	if cam:
		var to_tv: Vector3 = (tv.center - cam.global_position)
		var fwd := -cam.global_transform.basis.z
		ok(fwd.dot(to_tv.normalized()) > 0.995, "camera looks at the TV glass (dot %.4f)" % fwd.dot(to_tv.normalized()))
		ok(absf(cam.fov - 30.0) < 0.01, "menu FOV 30°")
		ok(to_tv.length() > 0.5 and to_tv.length() < 1.6, "camera distance %.2f m" % to_tv.length())
	# keyboard navigation
	await key(KEY_DOWN)
	ok(scr.sel_id == "explore", "↓ selects EXPLORER")
	await key(KEY_DOWN)
	ok(scr.sel_id == "options", "↓ selects OPTIONS")
	await key(KEY_ENTER)
	ok(scr.page_name == "options", "Entrée opens P200 options")
	var q0: String = S.get_value("quality", "high")
	var a0: bool = bool(S.get_value("auto_quality", true))
	await key(KEY_RIGHT)
	ok(S.get_value("quality") != q0 or bool(S.get_value("auto_quality", true)) != a0,
		"→ on QUALITÉ changes the preset (%s/auto %s → %s/auto %s)" % [q0, a0, S.get_value("quality"), S.get_value("auto_quality")])
	ok(not bool(S.get_value("auto_quality", true)), "picking a level turns AUTO off")
	await key(KEY_LEFT)
	if a0:
		ok(bool(S.get_value("auto_quality", false)), "← back to AUTO")
	else:
		ok(S.get_value("quality") == q0, "← restores quality")
	S.set_value("quality", q0)
	S.set_value("auto_quality", a0)
	await key(KEY_DOWN)
	ok(scr.sel_id == "brightness", "↓ LUMINOSITÉ")
	var b0: float = S.get_value("brightness", 1.0)
	await key(KEY_RIGHT)
	ok(absf(float(S.get_value("brightness")) - (b0 + 0.05)) < 0.001, "→ brightness +5 %")
	await key(KEY_LEFT)
	await key(KEY_DOWN)
	var f0: float = S.get_value("fov", 72.0)
	await key(KEY_LEFT)
	ok(float(S.get_value("fov")) < f0, "← on CHAMP DE VISION lowers fov (%s → %s)" % [f0, S.get_value("fov")])
	S.set_value("fov", f0)
	await key(KEY_ESCAPE)
	ok(scr.page_name == "main" and scr.sel_id == "options", "Échap goes back to P100 on OPTIONS")
	await digit(3)
	await digit(0)
	await digit(1)
	ok(scr.page_name == "controls", "digits 301 open the controls page")
	ok(ui.pages.ctl_sub == 1, "301 = gamepad page")
	await key(KEY_BACKSPACE)
	ok(scr.page_name == "main", "Backspace goes back")
	await digit(2)
	await digit(0)
	await digit(1)
	ok(scr.page_name == "options" and ui.pages.opt_sub == 1, "201 opens options page 2")
	await key(KEY_UP)
	await key(KEY_UP)
	await key(KEY_UP)
	ok(scr.sel_id == "fear", "↑ wraps through the options (sel %s)" % scr.sel_id)
	await key(KEY_UP)
	await key(KEY_UP)
	var inv0: bool = S.get_value("invert_y", false)
	await key(KEY_ENTER)
	ok(S.get_value("invert_y") != inv0, "Entrée toggles INVERSER Y")
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	await digit(4)
	await digit(0)
	await digit(0)
	ok(scr.page_name == "credits", "400 credits")
	await pad(JOY_BUTTON_B)
	ok(scr.page_name == "main", "gamepad B goes back")
	ok(ui.last_input_gamepad, "last input = gamepad")
	var sel0: String = scr.sel_id
	await pad(JOY_BUTTON_DPAD_DOWN)
	ok(scr.sel_id != sel0, "gamepad D-pad moves the selection (%s → %s)" % [sel0, scr.sel_id])
	await pad(JOY_BUTTON_DPAD_UP)
	ok(scr.sel_id == sel0, "D-pad up moves back")
	await key(KEY_DOWN)
	ok(not ui.last_input_gamepad, "keyboard resets the hint mode")
	# mouse picking through the curved glass: scan a vertical line across the TV
	var vs: Vector2 = root.get_viewport().get_visible_rect().size
	var c2: Vector2 = cam.unproject_position(tv.center)
	var found := Vector2(-1, -1)
	for i in 400:
		var p := Vector2(c2.x, c2.y - 220.0 + i * 1.1)
		var hit: Dictionary = tv.pick(p)
		if not hit.is_empty() and hit.it.id == "credits":
			found = p
			break
	ok(found.x >= 0.0, "picking finds the CRÉDITS line on the glass (%s, screen %s)" % [found, vs])
	if found.x >= 0.0:
		# (headless push_input does not deliver synthetic mouse events: drive the UI's mouse handler directly)
		var mm := InputEventMouseMotion.new()
		mm.position = found
		ui._menu_mouse(mm)
		await process_frame
		ok(scr.sel_id == "credits", "mouse hover selects CRÉDITS")
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = pressed
			mb.position = found
			ui._menu_mouse(mb)
		await process_frame
		ok(scr.page_name == "credits", "mouse click opens the page")
		var wh := InputEventMouseButton.new()
		wh.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wh.pressed = true
		wh.factor = 1.0
		var sel_before: String = scr.sel_id
		ui._menu_mouse(wh)
		ok(scr.sel_id == sel_before or scr.items.size() == 1, "wheel on a one-line page keeps the selection")
		await key(KEY_ESCAPE)
	# start: power-off transition -> ui_start -> playing
	while scr.sel_id != "play":
		await key(KEY_UP)
	await key(KEY_ENTER)
	ok(not tv.trans.is_empty(), "NOUVELLE PARTIE starts the power-off transition")
	await secs(0.6)
	ok(G.state == "menu", "still in the menu during the collapse")
	await secs(1.0)
	ok(G.state == "playing", "E.ui_start → playing after ~1.2 s")
	ok(not tv.on and not ui.menu_camera_active, "TV menu off, camera released")
	await frames(3)
	ok(root.get_viewport().get_camera_3d() == G.camera, "player camera current after the start")
	# HUD
	ui.set_prompt("Ouvrir le tiroir", {"key": "E", "hold": 0.4})
	ok(ui.hud.prompt_text == "Ouvrir le tiroir" and absf(ui.hud.prompt_hold - 0.4) < 0.001, "set_prompt with hold ring")
	ui.set_prompt("", {})
	ok(ui.hud.prompt_text == "", "set_prompt('') clears")
	ui.set_objective("Trouve une source de lumière.")
	await secs(0.3)
	ok(ui.hud.obj_text.begins_with("Trouve"), "objective typed")
	ui.subtitle("Il fait noir…", 2.0)
	ok(ui.subs.until > 0.0, "subtitle shown")
	S.set_value("subtitles", false)
	ui.subtitle("Pas critique", 2.0)
	ok(ui.subs.text != "Pas critique", "non-critical subtitle hidden when subtitles are off")
	ui.subtitle("Critique", 2.0, {"critical": true})
	ok(ui.subs.text == "Critique", "critical subtitle always shown")
	S.set_value("subtitles", true)
	E.player_flashlight.emit(true, true, 42.0)
	ok(absf(ui.hud.battery - 0.42) < 0.001 and ui.hud.flash_on == true, "battery from E.player_flashlight")
	E.player_stamina.emit(0.2, false, 0.5)
	await frames(2)
	ok(ui.hud._stam_on, "stamina bar shows when low")
	ui.alert("Cache-toi !", 1.0)
	ok(ui.hud._alert_text == "CACHE-TOI\u00a0!", "alert uppercased with French spacing (%s)" % ui.hud._alert_text)
	ui.set_clues({"duck": "3", "horse": null, "clock": "7", "tv": null})
	ok(ui.clues.duck == "3" and ui.clues.horse == null, "set_clues normalised")
	# pause
	ok(not ui.is_modal_open(), "no modal while playing")
	_pause_task()
	await frames(2)
	ok(G.state == "paused" and ui.crt.is_open and ui.crt.mode == "pause", "G.pause opens the pause CRT")
	ok(ui.is_modal_open(), "pause is modal")
	ok(ui.crt.screen.page_name == "pause", "P150 pause page")
	var pids := []
	for it in ui.crt.screen.items:
		pids.append(it.id)
	ok("resume" in pids and "options" in pids and "quit" in pids, "pause items %s" % [pids])
	await key(KEY_DOWN)
	await key(KEY_ENTER)
	var sub_page: String = ui.crt.screen.page_name
	ok(sub_page != "pause", "pause sub page opens (%s)" % sub_page)
	await key(KEY_ESCAPE)
	ok(ui.crt.screen.page_name == "pause", "Échap back to P150")
	await digit(9)
	await digit(9)
	await digit(9)
	ok(ui.crt.screen.page_name == "quit", "999 opens the quit confirmation")
	var qids := []
	for it in ui.crt.screen.items:
		qids.append(it.id)
	ok(qids == ["no", "menu", "desktop"], "quit choices %s" % [qids])
	await key(KEY_ENTER)
	ok(ui.crt.screen.page_name == "pause" and ui.crt.screen.sel_id == "quit", "NON, RESTER returns to P150 on QUITTER")
	_opt_done = false
	_opt_task()
	await frames(2)
	ok(ui.crt.screen.page_name == "options", "show_options() opens the options over the pause")
	await key(KEY_ESCAPE)
	await frames(2)
	ok(_opt_done, "show_options() resolves when the page is left")
	await pad(JOY_BUTTON_START)
	await frames(2)
	ok(_pause_done and G.state == "playing", "Start on P150 resumes the game")
	await secs(0.3)
	ok(not ui.is_modal_open(), "modal guard released")
	# note (paper)
	for style in ["note", "child", "newspaper"]:
		_note_done = false
		_note_task({"id": "t", "title": "Note pliée", "style": style,
			"text": "LE COURRIER DU LAC — 14 novembre 1994\n\nDEUX ENFANTS RETROUVÉS DANS UN SOUS-SOL\n\nLéa, 7 ans, et son frère Mathis, 10 ans, ont été retrouvés hier.\n\n« Elle chantait toute la nuit », a raconté la fillette." if style == "newspaper" else "Reste en bas. Pas un bruit.\nElle a le sommeil léger…\n\n— M."})
		await frames(3)
		ok(ui.note_view.is_open and ui.is_modal_open(), "show_note(%s) opens the paper" % style)
		await key(KEY_ENTER)
		ok(ui.note_view.is_open, "Entrée within 250 ms is ignored")
		await secs(0.3)
		await key(KEY_E, true)
		await frames(2)
		ok(_note_done and not ui.note_view.is_open, "E closes the %s note and resolves" % style)
	# keypad (brass padlock)
	_kp_done = false
	_kp_task()
	await frames(3)
	ok(ui.keypad_view.is_open, "show_keypad opens the padlock")
	await secs(0.3)
	await digit(1)
	await digit(2)
	await digit(3)
	await digit(4)
	ok(ui.keypad_view.code() == "1234", "digits set the wheels (%s)" % ui.keypad_view.code())
	await key(KEY_UP)
	ok(ui.keypad_view.code() == "1235", "↑ turns the active wheel (%s)" % ui.keypad_view.code())
	await key(KEY_LEFT)
	await key(KEY_DOWN)
	ok(ui.keypad_view.code() == "1225", "← then ↓ turns wheel 3 (%s)" % ui.keypad_view.code())
	await key(KEY_ENTER)
	await frames(2)
	ok(_kp_done and str(_kp_result) == "1225", "Entrée tries the code → %s" % str(_kp_result))
	_kp_done = false
	_kp_task()
	await frames(3)
	ok(ui.keypad_view.code() == "1225", "the padlock keeps the last combination")
	await key(KEY_ESCAPE)
	await frames(2)
	ok(_kp_done and str(_kp_result) == "", "Échap cancels → \"\"")
	await secs(0.3)
	# caught / game over / win
	for kind in ["caught", "gameover", "win"]:
		_end_done = false
		_end_task(kind)
		await frames(3)
		ok(ui.crt.is_open and ui.crt.mode == "end" and ui.crt.screen.page_name == kind, "%s screen opens" % kind)
		await key(KEY_ENTER)
		ok(not _end_done, "%s: input ignored before ready" % kind)
		await secs(2.4)
		var gids := []
		for it in ui.crt.screen.items:
			gids.append(it.id)
		ok(gids == ["go"], "%s: action line appears when ready" % kind)
		await key(KEY_ENTER)
		await frames(2)
		ok(_end_done, "%s: Entrée continues" % kind)
		await secs(0.4)
	# fades
	await ui.fade_to(1.0, 0.2)
	ok(ui.fade.color.a > 0.99, "fade_to(1)")
	await ui.fade_to(0.0, 0.0)
	ok(ui.fade.color.a < 0.01 and not ui.fade.visible, "fade_to(0, 0) immediate")
	print("[test_ui] %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)

func _pause_task() -> void:
	_pause_done = false
	await G.pause()
	_pause_done = true

var _opt_done := false

func _opt_task() -> void:
	await ui.show_options()
	_opt_done = true

func _note_task(n: Dictionary) -> void:
	await G.modal(func() -> void: await ui.show_note(n))
	_note_done = true

func _kp_task() -> void:
	_kp_result = await G.modal(func(): return await ui.show_keypad("Cadenas du coffret", 4))
	_kp_done = true

func _end_task(kind: String) -> void:
	match kind:
		"caught": await ui.show_caught(2, 3)
		"gameover": await ui.show_game_over()
		"win": await ui.show_win(754.0, 2, 3)
	_end_done = true
