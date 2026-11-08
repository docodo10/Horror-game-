## UI module debug driver (attached by ui.gd when the game is started with --ui-shots=...). Drives the real UI through
## its states and saves rendered screenshots, then quits. Needs a renderer (pc/tools/godot_shot.sh), e.g.
##   pc/tools/godot_shot.sh --res 1280x720 -- --ui-shots=menu,options,pause,hud,note,keypad,caught,win --ui-out=/abs/prefix
## Shots: menu options controls credits poweroff loading pause pause_options notes hud hud_pad note child newspaper keypad
##        caught gameover win. Optional: --ui-frames=N (frames to settle per shot, default 24).
extends Node

const Style := preload("res://scripts/ui/ui_style.gd")

var ui: Node
var out := "/tmp/ui_shot"
var settle := 24

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = get_parent()
	var shots := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-shots="):
			shots = a.get_slice("=", 1).split(",", false)
		elif a.begins_with("--ui-out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--ui-frames="):
			settle = maxi(2, int(a.get_slice("=", 1)))
	_run.call_deferred(shots)

func _wait(frames: int, min_secs := 0.0) -> void:
	var t0 := Style.now()
	var n := 0
	while n < frames or Style.now() - t0 < min_secs:
		await get_tree().process_frame
		n += 1

func _save(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("[ui-shots] no image (needs a renderer)")
		return
	var path := "%s_%s.png" % [out, name_]
	img.save_png(path)
	print("[ui-shots] ", path, " ", img.get_size())

func _run(shots: PackedStringArray) -> void:
	for i in 900:
		await get_tree().process_frame
		if Game.state == "menu" or Game.state == "playing":
			break
	await _wait(settle, 1.0)
	var notes := {
		"note": {"id": "note1", "title": "Note pliée", "style": "note", "text": "Reste en bas. Pas un bruit.\nElle a le sommeil léger…\n\nLa clé de la porte d’en haut est dans le coffret de Léa.\n\n— M."},
		"child": {"id": "note2", "title": "Dessin d’enfant", "style": "child", "text": "MA GARDIENNE\n\nElle chante quand elle te cherche.\nSi tu l’entends, cours dans le placard sous l’escalier.\nElle regarde jamais dedans…\nsauf si elle te voit y aller.\n\nLéa, 7 ans"},
		"newspaper": {"id": "note3", "title": "Coupure de journal", "style": "newspaper", "text": "LE COURRIER DU LAC — 14 novembre 1994\n\nDEUX ENFANTS RETROUVÉS DANS UN SOUS-SOL\n\nLéa, 7 ans, et son frère Mathis, 10 ans, ont été retrouvés hier, enfermés depuis trois jours dans le sous-sol de la maison familiale. Leur gardienne, une femme de 61 ans, reste introuvable.\n\n« Elle disait qu’elle nous protégeait de dehors. Elle chantait toute la nuit, en haut », a raconté la fillette.\n\nLa maison est inhabitée depuis."},
	}
	for s in shots:
		match s:
			"menu", "options", "controls", "credits":
				if Game.state != "menu":
					continue
				var page: String = "main" if s == "menu" else s
				ui.goto_page(ui.tv.screen, page, "", false)
				await _wait(settle, 0.6)
				await _save(s)
			"poweroff":
				if Game.state != "menu":
					continue
				ui.goto_page(ui.tv.screen, "main", "", false)
				await _wait(4)
				ui.tv_start_game()
				await _wait(2, 0.62)
				await _save(s)
				await _wait(2, 1.2)
			"loading":
				ui.loading_state.hidden = false
				ui.loading_state.p = 0.62
				ui.loading_state.text = "Construction du sous-sol…"
				ui._open_crt("loading", "loading", 0.0)
				await _wait(settle, 0.8)
				await _save(s)
				ui._hide_loading()
				await _wait(4, 1.0)
			_:
				await _ensure_playing()
				await _game_shot(s, notes)
	print("[ui-shots] done")
	get_tree().quit()

func _ensure_playing() -> void:
	if Game.state == "menu":
		Events.ui_start.emit()
	if Game.state != "playing" and Game.state != "paused":
		for i in 60:
			await get_tree().process_frame
	await ui.fade_to(0.0, 0.0)
	await _wait(8)

func _game_shot(s: String, notes: Dictionary) -> void:
	match s:
		"hud":
			ui.set_objective("Rétablis le courant (panneau électrique, buanderie).")
			ui.subtitle("Il fait tellement noir… Où est le panneau électrique ?", 6.0)
			ui.set_prompt("Ouvrir le tiroir", {"key": "E", "hold": 0.62})
			Events.player_flashlight.emit(true, true, 64.0)
			ui.set_stamina(0.22)
			await _wait(settle, 2.2)
			await _save(s)
			ui.set_prompt("", {})
		"hud_pad":
			ui.note_input_device(InputEventJoypadButton.new())
			ui.set_prompt("Se cacher dans le placard", {"key": "A"})
			ui.set_hidden(true)
			Events.entity_spotted.emit()
			ui.alert("Cache-toi !", 3.0)
			await _wait(settle, 0.5)
			await _save(s)
			ui.set_prompt("", {})
			ui.set_hidden(false)
		"pause", "pause_options", "notes":
			ui.set_objective("Rétablis le courant (panneau électrique, buanderie).")
			ui.set_clues({"duck": "3", "horse": null, "clock": "7", "tv": null})
			ui.set_inventory([{"id": "flashlight", "name": "Lampe de poche", "count": 1}, {"id": "battery", "name": "Piles", "count": 2}],
				[notes.note, notes.child])
			Game.pause()
			await _wait(settle, 0.6)
			if s == "pause_options":
				ui.goto_page(ui.crt.screen, "options", "", false)
				await _wait(settle, 0.5)
			elif s == "notes":
				ui.goto_page(ui.crt.screen, "notes", "", false)
				await _wait(settle, 0.5)
			await _save(s)
			ui.hide_pause()
			await _wait(8, 0.4)
		"note", "child", "newspaper":
			ui.show_note(notes[s])
			await _wait(settle, 0.8)
			await _save(s)
			ui._close_note()
			await _wait(8, 0.4)
		"keypad":
			ui.set_clues({"duck": "3", "horse": null, "clock": "7", "tv": null})
			ui.show_keypad("Cadenas du coffret", 4)
			await _wait(6, 0.3)
			ui.keypad_view.set_digit(0, 3)
			ui.keypad_view.set_digit(1, 1)
			ui.keypad_view.set_active(1)
			await _wait(settle, 0.8)
			await _save(s)
			ui._kp_finish("")
			await _wait(8, 0.4)
		"caught":
			ui.show_caught(2, 3)
			await _wait(settle, 1.8)
			await _save(s)
			ui.end_finish()
			await _wait(8, 0.4)
		"gameover":
			ui.show_game_over()
			await _wait(settle, 2.4)
			await _save(s)
			ui.end_finish()
			await _wait(8, 0.4)
		"win":
			ui.show_win(754.0, 2, 3)
			await _wait(settle, 2.2)
			await _save(s)
			ui.end_finish()
			await _wait(8, 0.4)
