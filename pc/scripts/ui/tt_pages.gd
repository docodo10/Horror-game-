## UI module — the teletext pages ("CANAL 3 · LA GARDIENNE"), port of the web UI._pages with the same content, colours
## and numbering: P100 index, P200/201 options, P300/301 controls, P400 credits (dresser TV and pause CRT), plus the
## full-screen pages P100 loading, P150 pause, P160 notes, P999 quit, caught, game over and the win test card.
## PC additions: QUITTER in the index (CRT power-off, then quit), VSync option, gamepad controls page (301), quit page
## offers main menu / desktop. Each page is a method `func(b)` where b is the teletext display (scripts/ui/teletext.gd).
extends RefCounted

const Style := preload("res://scripts/ui/ui_style.gd")
const TT := preload("res://scripts/ui/teletext.gd")

const K := Style.TT_K
const R := Style.TT_R
const G := Style.TT_G
const Y := Style.TT_Y
const B := Style.TT_B
const M := Style.TT_M
const C := Style.TT_C
const W := Style.TT_W
const D := Style.TT_D

const QUALITY := [["low", "Basse"], ["medium", "Moyenne"], ["high", "Haute"], ["ultra", "Ultra"]]
const CLUES := [["duck", "Canard"], ["horse", "Cheval"], ["clock", "Horloge"], ["tv", "Télé"]]
const ITEM_NAMES := {"flashlight": "Lampe", "battery": "Pile", "key": "Clé"}

const TIPS := [
	"Accroupis-toi : tes pas feront moins de bruit.",
	"Elle entend tout. Les tiroirs aussi.",
	"Le placard sous l’escalier est une bonne cachette… si elle ne te voit pas y entrer.",
	"Ta lampe de poche te rend visible. Éteins-la quand elle approche.",
	"Les piles s’usent vite. Garde-en une de côté.",
	"Si elle te voit, cours. Puis cache-toi.",
	"La télé fait beaucoup de bruit quand elle est allumée.",
]
const TICKER_MENU := "MÉTÉO : −24 °C, RESSENTI −33. VERGLAS SUR LA 20   ·   AVIS DE RECHERCHE : GARDIENNE D’ENFANTS, 19 ANS, VUE POUR LA DERNIÈRE FOIS RUE DES ÉRABLES   ·   RAPPEL AUX PARENTS : VERROUILLEZ LA PORTE DU SOUS-SOL   ·   ÉCOLES FERMÉES DEMAIN   ·   BONNE NUIT LES PETITS. PAS UN BRUIT"
const DIGIT_PAGES := {"100": "main", "150": "pause", "160": "notes", "200": "options", "201": "options", "202": "options", "300": "controls", "301": "controls", "400": "credits", "999": "quit"}

var ui: Node
var opt_sub := 0
const OPT_PAGES := 3
var ctl_sub := -1

func _init(ui_: Node) -> void:
	ui = ui_

func get_fn(page: String) -> Callable:
	match page:
		"main": return main
		"options": return options
		"controls": return controls
		"credits": return credits
		"loading": return loading
		"pause": return pause
		"notes": return notes
		"quit": return quit
		"caught": return caught
		"gameover": return gameover
		"win": return win
	return Callable()

# ---------------------------------------------------------------- helpers

func _S(key: String, def: Variant = null) -> Variant:
	var v: Variant = Settings.get_value(key, def)
	return def if v == null else v

func _setv(key: String, v: Variant) -> void:
	Settings.set_value(key, v)

## Numeric setting step: off-grid values first snap toward the direction of travel.
func _num(key: String, d: int, step: float, lo: float, hi: float, def: float) -> void:
	var v := float(_S(key, def))
	var base := roundf(v / step) * step
	var n := base if absf(base - v) > 0.001 and signf(base - v) == float(d) else base + d * step
	_setv(key, snappedf(clampf(n, lo, hi), 0.001))

func _bar(v01: float, n := 5) -> String:
	var k := roundi(Style.clamp01(v01) * n)
	return "▮".repeat(k) + "▯".repeat(n - k)

func _oui(v: Variant) -> String:
	return "OUI" if bool(v) else "NON"

func _home_num(b: TT) -> String:
	return "150" if b.home == "pause" else "100"

func _back_home(b: TT) -> void:
	ui.goto_page(b, b.home if b.home != "" else "main", b.page_name)   # re-select the line we came from

func _goto(b: TT, page: String) -> void:
	if page == "options": opt_sub = 0
	if page == "controls": ctl_sub = -1
	ui.goto_page(b, page)

func _digit_entry(b: TT) -> void:
	b.digits(_on_digit.bind(b))

func _on_digit(k: String, b: TT) -> void:
	b.type_digit(k)
	if b.typed.length() < 3:
		return
	var typed: String = b.typed
	var target: String = DIGIT_PAGES.get(typed, "")
	var home: String = b.home if b.home != "" else "main"
	var ok := target != ""
	if target == "main" and home != "main": ok = false
	if (target == "pause" or target == "notes" or target == "quit") and home != "pause": ok = false
	if target == "notes" and ui.all_notes().is_empty(): ok = false
	b.typed = ""
	if ok:
		if target == "options": opt_sub = {"201": 1, "202": 2}.get(typed, 0)
		if target == "controls": ctl_sub = 1 if typed == "301" else 0
		ui.goto_page(b, target)
	else:
		ui.sfx("value")
		b.flick = 1.0

func _sub_switch(b: TT, row: int, n: int, getter: Callable, setter: Callable) -> void:
	var cur: int = getter.call()
	b.item(row, {"id": "sub", "label": "PAGE", "kind": "value", "right": "%d/%d" % [cur + 1, n],
		"change": _sub_change.bind(b, n, getter, setter)})

func _sub_change(d: int, b: TT, n: int, getter: Callable, setter: Callable) -> void:
	setter.call((int(getter.call()) + d + n) % n)
	b.flick = 1.0

func _change_volume(d: int) -> void:
	_num("volume", d, 0.05, 0.0, 1.0, 0.85)
	Audio.set_master_volume(float(_S("volume", 0.85)))

func _get_opt() -> int:
	return opt_sub

func _set_opt(v: int) -> void:
	opt_sub = v

func _get_ctl() -> int:
	return ctl_sub

func _set_ctl(v: int) -> void:
	ctl_sub = v

func _lr_opt(d: int, b: TT) -> void:
	opt_sub = (opt_sub + d + OPT_PAGES) % OPT_PAGES
	b.dirty = true
	b.flick = 1.0
	ui.sfx("value")

func _lr_ctl(d: int, b: TT) -> void:
	ctl_sub = (ctl_sub + d + 2) % 2
	b.dirty = true
	b.flick = 1.0
	ui.sfx("value")

# ---------------------------------------------------------------- P100 index (TV)

func main(b: TT) -> void:
	b.header()
	b.pnum("100", "INDEX")
	b.bar(2, R, 2)
	b.text(2, "c", "LA GARDIENNE", Y, true)
	b.text(4, "c", "CHAPITRE 1 — LE SOUS-SOL", C)
	var r := 5
	b.item(r, {"id": "play", "label": "JOUER (AVEC LA GARDIENNE)", "right": "101", "on": Callable(ui, "tv_start_game").bind("normal")}); r += 1
	b.item(r, {"id": "explore", "label": "EXPLORER (SANS MONSTRE)", "right": "102", "on": Callable(ui, "tv_start_game").bind("explore")}); r += 1
	b.item(r, {"id": "options", "label": "OPTIONS", "right": "200", "on": _goto.bind(b, "options")}); r += 1
	b.item(r, {"id": "controls", "label": "CONTRÔLES", "right": "300", "on": _goto.bind(b, "controls")}); r += 1
	b.item(r, {"id": "credits", "label": "CRÉDITS", "right": "400", "on": _goto.bind(b, "credits")}); r += 1
	b.item(r, {"id": "quit", "label": "QUITTER", "right": "999", "color": R, "on": Callable(ui, "tv_quit_game")}); r += 1
	var alt := floori(ui.real_time / 4.0) % 2 == 1
	b.hint("JOUE AVEC DES ÉCOUTEURS" if alt else ui.nav_hint("main"), M if alt else G, b.rows - 2)
	b.ticker(TICKER_MENU)
	_digit_entry(b)

# ---------------------------------------------------------------- P200 / P201 options

func options(b: TT) -> void:
	var sub := opt_sub
	b.header()
	b.pnum(str(200 + sub), "%d/%d" % [sub + 1, OPT_PAGES], Y)
	b.text(2, 1, "OPTIONS", Y, true)
	b.text(3, "r", ["IMAGE", "SON ET COMMANDES", "PERFORMANCE ET EFFETS"][sub], C)
	if sub == 0:
		var r := 4
		# AUTO first: the game picks and adapts the preset (scripts/render/auto_quality.gd)
		var qopts := [["auto", "AUTO"]] + QUALITY
		var auto_on := bool(_S("auto_quality", true))
		var qi := 0
		if not auto_on:
			for i in qopts.size():
				if qopts[i][0] == str(_S("quality", "high")): qi = i
		var qname := ""
		for e in QUALITY:
			if e[0] == str(_S("quality", "high")): qname = e[1]
		b.item(r, {"id": "quality", "label": "QUALITÉ", "kind": "value", "right": ("AUTO (%s)" % qname.to_upper()) if auto_on else qopts[qi][1],
			"change": func(d: int) -> void:
				var n: String = qopts[(qi + d + qopts.size()) % qopts.size()][0]
				if n == "auto":
					_setv("auto_quality", true)
				else:
					_setv("auto_quality", false)
					_setv("quality", n)}); r += 1
		var br := float(_S("brightness", 1.0))
		b.item(r, {"id": "brightness", "label": "LUMINOSITÉ", "kind": "value", "right": "%s %d%%" % [_bar(br - 0.6), roundi(br * 100.0)],
			"change": func(d: int) -> void: _num("brightness", d, 0.05, 0.6, 1.6, 1.0)}); r += 1
		# stored as vertical degrees; shown as the usual horizontal field of view on a 16:9 screen (54 -> 84)
		var fov_h := rad_to_deg(2.0 * atan(tan(deg_to_rad(float(_S("fov", 54.0))) * 0.5) * 16.0 / 9.0))
		b.item(r, {"id": "fov", "label": "CHAMP DE VISION", "kind": "value", "right": "%d°" % roundi(fov_h),
			"change": func(d: int) -> void: _num("fov", d, 2.0, 44.0, 76.0, 54.0)}); r += 1
		var cm := float(_S("camera_motion", 0.6))
		b.item(r, {"id": "camera_motion", "label": "MOUVEMENT CAMÉRA", "kind": "value", "right": "%s %d%%" % [_bar(cm), roundi(cm * 100.0)],
			"change": func(d: int) -> void: _num("camera_motion", d, 0.1, 0.0, 1.0, 0.6)}); r += 1
		b.item(r, {"id": "fullscreen", "label": "PLEIN ÉCRAN", "kind": "value", "right": _oui(_S("fullscreen", true)),
			"change": func(_d: int) -> void: ui.set_fullscreen(not bool(_S("fullscreen", true)))}); r += 1
		b.item(r, {"id": "vsync", "label": "SYNCHRO VERTICALE", "kind": "value", "right": _oui(_S("vsync", true)),
			"change": func(_d: int) -> void: ui.set_vsync(not bool(_S("vsync", true)))}); r += 1
	elif sub == 2:
		var r := 4
		var fps_caps := [0, 60, 120, 144, 165, 240]
		var fi := maxi(0, fps_caps.find(int(_S("max_fps", 0))))
		b.item(r, {"id": "max_fps", "label": "IMAGES / SECONDE", "kind": "value", "right": "ILLIMITÉ" if fps_caps[fi] == 0 else str(fps_caps[fi]),
			"change": func(d: int) -> void: _setv("max_fps", fps_caps[(fi + d + fps_caps.size()) % fps_caps.size()])}); r += 1
		b.item(r, {"id": "show_fps", "label": "COMPTEUR FPS", "kind": "value", "right": _oui(_S("show_fps", false)),
			"change": func(_d: int) -> void: _setv("show_fps", not bool(_S("show_fps", false)))}); r += 1
		var ups := [["off", "NON"], ["fsr2_quality", "FSR2 QUALITÉ"], ["fsr2_balanced", "FSR2 ÉQUILIBRÉ"], ["fsr2_performance", "FSR2 PERF."]]
		var ui_i := 0
		for i in ups.size():
			if ups[i][0] == str(_S("upscale", "off")): ui_i = i
		b.item(r, {"id": "upscale", "label": "MISE À L'ÉCHELLE", "kind": "value", "right": ups[ui_i][1],
			"change": func(d: int) -> void: _setv("upscale", ups[(ui_i + d + ups.size()) % ups.size()][0])}); r += 1
		for t in [["depth_of_field", "FLOU DE PROFONDEUR"], ["film_grain", "GRAIN DE FILM"], ["chromatic_aberration", "ABERRATION"]]:
			var key: String = t[0]
			b.item(r, {"id": key, "label": t[1], "kind": "value", "right": _oui(_S(key, true)),
				"change": func(_d: int) -> void: _setv(key, not bool(_S(key, true)))}); r += 1
	else:
		var r := 4
		var vol := float(_S("volume", 0.85))
		b.item(r, {"id": "volume", "label": "VOLUME", "kind": "value", "right": "%s %d%%" % [_bar(vol), roundi(vol * 100.0)],
			"change": _change_volume}); r += 1
		b.item(r, {"id": "subtitles", "label": "SOUS-TITRES", "kind": "value", "right": _oui(_S("subtitles", true)),
			"change": func(_d: int) -> void: _setv("subtitles", not bool(_S("subtitles", true)))}); r += 1
		var se := float(_S("sensitivity", 1.0))
		b.item(r, {"id": "sensitivity", "label": "SENSIBILITÉ", "kind": "value", "right": "%s %s" % [_bar((se - 0.3) / 2.7), ("%.1f" % se).replace(".", ",")],
			"change": func(d: int) -> void: _num("sensitivity", d, 0.1, 0.3, 3.0, 1.0)}); r += 1
		b.item(r, {"id": "invert_y", "label": "INVERSER Y", "kind": "value", "right": _oui(_S("invert_y", false)),
			"change": func(_d: int) -> void: _setv("invert_y", not bool(_S("invert_y", false)))}); r += 1
		var hud_modes := [["dot", "POINT"], ["none", "AUCUNE"], ["full", "COMPLÈTE"]]
		var hud_i := 0
		for i in hud_modes.size():
			if hud_modes[i][0] == str(_S("hud", "dot")): hud_i = i
		b.item(r, {"id": "hud", "label": "INTERFACE", "kind": "value", "right": hud_modes[hud_i][1],
			"change": func(d: int) -> void: _setv("hud", hud_modes[(hud_i + d + hud_modes.size()) % hud_modes.size()][0])}); r += 1
		b.item(r, {"id": "fear", "label": "PEUR", "kind": "value", "right": "EXTRÊME" if str(_S("fear", "extreme")) == "extreme" else "NORMALE",
			"change": func(_d: int) -> void: _setv("fear", "normal" if str(_S("fear", "extreme")) == "extreme" else "extreme")}); r += 1
	_sub_switch(b, b.rows - 3, OPT_PAGES, _get_opt, _set_opt)
	b.item(b.rows - 2, {"id": "back", "label": "RETOUR", "right": _home_num(b), "on": _back_home.bind(b)})
	b.hint(ui.nav_hint("options"))
	b.back(_back_home.bind(b))
	b.lr(_lr_opt.bind(b))
	_digit_entry(b)

# ---------------------------------------------------------------- P300 / P301 controls

func controls(b: TT) -> void:
	if ctl_sub < 0:
		ctl_sub = 1 if ui.last_input_gamepad else 0
	var sub := ctl_sub
	b.header()
	b.pnum("301" if sub else "300", "%s %d/2" % ["MANETTE" if sub else "CLAVIER", sub + 1], Y)
	b.text(2, 1, "CONTRÔLES", Y, true)
	var lines: Array
	if sub:
		lines = [["SE DÉPLACER", "STICK GAUCHE"], ["REGARDER", "STICK DROIT"], ["INTERAGIR", "A"], ["COURIR", "L3"],
			["ACCROUPI · LAMPE", "B · Y"], ["PAUSE · OBJECTIF", "START · VUE"]]
	else:
		var mv := Style.key_label(KEY_W) + Style.key_label(KEY_A) + Style.key_label(KEY_S) + Style.key_label(KEY_D)
		lines = [["SE DÉPLACER", mv], ["COURIR", "MAJ"], ["S’ACCROUPIR", "%s / CTRL" % Style.key_label(KEY_C)],
			["INTERAGIR", "%s / CLIC" % Style.key_label(KEY_E)], ["LAMPE", Style.key_label(KEY_F)],
			["PAUSE", "ÉCHAP / %s" % Style.key_label(KEY_P)]]
	var r := 4
	for l in lines:
		b.info(r, l[0], l[1])
		r += 1
	_sub_switch(b, b.rows - 3, 2, _get_ctl, _set_ctl)
	b.item(b.rows - 2, {"id": "back", "label": "RETOUR", "right": _home_num(b), "on": _back_home.bind(b)})
	b.hint(ui.nav_hint("controls"))
	b.back(_back_home.bind(b))
	b.lr(_lr_ctl.bind(b))
	_digit_entry(b)

# ---------------------------------------------------------------- P400 credits

func credits(b: TT) -> void:
	b.header()
	b.pnum("400", "MERCI")
	b.text(2, 1, "CRÉDITS", Y, true)
	var r := 4
	for l in [["MODÈLES 3D", "POLY HAVEN"], ["TEXTURES", "AMBIENTCG, POLY HAVEN"], ["SONS", "RED LIBRARY, KENNEY"],
			["LICENCES", "CC0 (DOMAINE PUBLIC)"], ["MOTEUR", "GODOT ENGINE"], ["POLICES", "GOOGLE FONTS (OFL)"]]:
		b.info(r, l[0], l[1])
		r += 1
	if b.rows > 13:
		b.text(r + 1, "c", "UN JEU ORIGINAL. PAS UN BRUIT…", M)
	b.item(b.rows - 2, {"id": "back", "label": "RETOUR", "right": _home_num(b), "on": _back_home.bind(b)})
	b.ticker("MERCI D’AVOIR REGARDÉ CANAL 3   ·   TOUTES LES RESSOURCES SONT LIBRES (CC0)", B, Y)
	b.back(_back_home.bind(b))
	_digit_entry(b)

# ---------------------------------------------------------------- full-screen CRT pages (40 × 16)

func loading(b: TT) -> void:
	var L: Dictionary = ui.loading_state
	b.header()
	b.pnum("100", "RECHERCHE DU SIGNAL", G)
	b.bar(3, R, 2)
	b.text(3, "c", "LA GARDIENNE", Y, true)
	b.text(5, "c", "CHAPITRE 1 — LE SOUS-SOL", C)
	b.text(7, "c", str(L.get("text", "")) if str(L.get("text", "")) != "" else "CHARGEMENT…", W)
	var p := Style.clamp01(float(L.get("p", 0.0)))
	var n := 24
	var k := roundi(p * n)
	var x0 := floori((b.cols - n - 5) / 2.0)
	for i in n:
		b.put(x0 + i, 8, "█" if i < k else "▯", G if i < k else D)
	b.put(x0 + n + 1, 8, ("%d" % roundi(p * 100.0)).lpad(3, Style.NBSP) + "%", W)
	b.text(10, "c", "JOUE AVEC DES ÉCOUTEURS,", M)
	b.text(11, "c", "LUMIÈRES ÉTEINTES.", M)
	var lines := b.wrap_text("CONSEIL : " + str(ui.tip), b.cols - 2)
	for i in mini(3, lines.size()):
		b.text(12 + i, "c", lines[i], G)
	b.ticker(TICKER_MENU)

func pause(b: TT) -> void:
	b.header()
	b.pnum("150", "NUIT %d/%d" % [ui.night, ui.nights_total], C)
	b.text(2, 1, "PAUSE", Y, true)
	var r := 4
	if ui.objective_text != "":
		b.text(r, 1, "OBJECTIF", G)
		r += 1
		var ls := b.wrap_text(ui.objective_text, b.cols - 2)
		for i in mini(2, ls.size()):
			b.text(r, 1, ls[i], W)
			r += 1
	var c: Dictionary = ui.clues
	var any := false
	for pair in CLUES:
		if c.get(pair[0]) != null: any = true
	if any:
		b.text(r, 1, "CODE", G)
		var x := 6
		for pair in CLUES:
			var nm := Style.up(pair[1])
			b.put(x, r, nm, C)
			var v: Variant = c.get(pair[0])
			b.put(x + nm.length() + 1, r, str(v) if v != null else "?", Y if v != null else D)
			x += nm.length() + 3
		r += 1
	var inv := PackedStringArray()
	for it in ui.inventory_items:
		var nm: String = ITEM_NAMES.get(str(it.get("id", "")), str(it.get("name", it.get("id", ""))))
		var cnt := int(it.get("count", 1))
		inv.append("%s ×%d" % [nm, cnt] if cnt > 1 else nm)
	if not inv.is_empty():
		b.text(r, 1, "SAC", G)
		b.text(r, 6, " · ".join(inv).left(b.cols - 7), C)
		r += 1
	var nts: Array = ui.all_notes()
	r = maxi(r + 1, b.rows - (7 if not nts.is_empty() else 6))
	b.item(r, {"id": "resume", "label": "REPRENDRE", "right": "B" if ui.last_input_gamepad else "ÉCHAP", "on": Callable(ui, "hide_pause")}); r += 1
	if not nts.is_empty():
		b.item(r, {"id": "notes", "label": "NOTES", "right": "160", "on": _goto.bind(b, "notes")}); r += 1
	b.item(r, {"id": "options", "label": "OPTIONS", "right": "200", "on": _goto.bind(b, "options")}); r += 1
	b.item(r, {"id": "controls", "label": "CONTRÔLES", "right": "300", "on": _goto.bind(b, "controls")}); r += 1
	b.item(r, {"id": "quit", "label": "QUITTER", "right": "999", "color": R, "on": _goto.bind(b, "quit")}); r += 1
	b.hint(ui.nav_hint("pause"))
	_digit_entry(b)

func notes(b: TT) -> void:
	b.header()
	b.pnum("160", "NOTES TROUVÉES", C)
	b.text(2, 1, "NOTES", Y, true)
	var nts: Array = ui.all_notes()
	var r := 5
	for i in mini(nts.size(), b.rows - 8):
		var n: Dictionary = nts[i]
		var title := str(n.get("title", "Note %d" % (i + 1))).left(b.cols - 2)
		b.item(r, {"id": "note%d" % i, "label": title, "kind": "action", "on": Callable(ui, "reread_note").bind(n)})
		r += 1
	b.item(b.rows - 2, {"id": "back", "label": "RETOUR", "right": "150", "on": _back_home.bind(b)})
	b.back(_back_home.bind(b))

func quit(b: TT) -> void:
	b.header()
	b.pnum("999", "FIN DE SOIRÉE", R)
	b.text(3, "c", "QUITTER LA PARTIE ?", Y, true)
	b.text(6, "c", "TA PROGRESSION SERA PERDUE.", W)
	b.item(9, {"id": "no", "label": "NON, RESTER", "kind": "action", "on": _back_home.bind(b)})
	b.item(10, {"id": "menu", "label": "OUI, RETOUR AU MENU", "kind": "action", "color": R, "on": Callable(ui, "quit_to_menu")})
	b.item(11, {"id": "desktop", "label": "OUI, QUITTER LE JEU", "kind": "action", "color": R, "on": Callable(ui, "quit_app")})
	b.back(_back_home.bind(b))

func _night_marks(b: TT, row: int, night: int, total: int, all_lost: bool) -> void:
	var x0 := floori((b.cols - total * 3) / 2.0)
	for i in range(1, total + 1):
		var lost := all_lost or i < night
		var cur := not all_lost and i == night
		b.put(x0 + (i - 1) * 3, row, "█" if lost else ("▮" if cur else "▯"), R if lost else (W if cur else D))

func _end_item(b: TT, row: int, label: String) -> void:
	if not ui.end_ready():
		return
	b.item(row, {"id": "go", "label": label, "kind": "action", "on": Callable(ui, "end_finish")})

func caught(b: TT) -> void:
	var e: Dictionary = ui.end_cfg()
	b.header("CANAL 3 · BULLETIN SPÉCIAL", R, W)
	b.text(1, "r", "● EN DIRECT" if b.blink else "  EN DIRECT", R)
	b.text(2, "c", "ELLE T’A TROUVÉ.", R, true)
	b.text(4, "c", "NUIT %d / %d" % [int(e.get("night", 2)), int(e.get("total", 3))], W, true)
	_night_marks(b, 6, int(e.get("night", 2)), int(e.get("total", 3)), false)
	var r := 8
	var ls := b.wrap_text(str(e.get("text", "")), b.cols - 4)
	for i in mini(3, ls.size()):
		b.text(r, "c", ls[i], C)
		r += 1
	ls = b.wrap_text(str(e.get("rest", "")), b.cols - 4)
	for i in mini(2, ls.size()):
		b.text(r, "c", ls[i], Y)
		r += 1
	_end_item(b, b.rows - 3, "CONTINUER")
	b.ticker("%s   ·   AVIS À LA POPULATION : NE QUITTEZ PAS VOTRE DOMICILE APRÈS MINUIT" % str(e.get("tip", "")), B, W)

func gameover(b: TT) -> void:
	var e: Dictionary = ui.end_cfg()
	b.header("CANAL 3 · FIN DU SIGNAL", R, W)
	b.text(2, "c", "ELLE T’A GARDÉ.", R, true)
	b.text(5, "c", " SIGNAL PERDU ", K, false, W)
	var total := int(e.get("total", 3))
	_night_marks(b, 7, total + 1, total, true)
	var r := 9
	var ls := b.wrap_text(str(e.get("text", "")), b.cols - 4)
	for i in mini(3, ls.size()):
		b.text(r, "c", ls[i], C)
		r += 1
	_end_item(b, b.rows - 3, "RECOMMENCER")
	b.ticker("LA PROGRAMMATION REPRENDRA DEMAIN MATIN   ·   BONNE NUIT")

func win(b: TT) -> void:
	var e: Dictionary = ui.end_cfg()
	var bars := [W, Y, C, G, M, R, B]
	var bw := b.cols / float(bars.size())
	for i in bars.size():
		b.rect(roundf(i * bw), 0, roundf((i + 1) * bw) - roundf(i * bw), 5, bars[i])
	for i in b.cols:
		b.rect(i, 5, 1, 1, K if i % 2 else W)
	b.text(6, "c", "FIN DE LA DIFFUSION", W, true)
	b.text(8, "c", "TU T’ES ÉCHAPPÉ.", Y)
	b.info(9, "TEMPS", str(e.get("time_str", "")))
	b.info(10, "NUITS", "%d / %d" % [int(e.get("nights_used", 1)), int(e.get("total", 3))])
	var ls := b.wrap_text(str(e.get("text", "")), b.cols - 4)
	for i in mini(2, ls.size()):
		b.text(11 + i, "c", ls[i], C)
	_end_item(b, b.rows - 3, "REJOUER")
	b.ticker("MERCI D’AVOIR REGARDÉ CANAL 3   ·   CHAPITRE 2 BIENTÔT   ·   BONNE NUIT", B, Y)
