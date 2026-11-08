# UI module (`scripts/ui/**`, `shaders/ui_*.gdshader`, `assets/fonts/**`)

Port of the web `src/ui/UI.js`: the diegetic **teletext menu on the dresser CRT TV** ("CANAL 3 · LA GARDIENNE"), the same
teletext pages full-screen for loading / pause / caught / game over / win, an almost empty HUD, paper notes and the brass
combination padlock. Same French text, colours, page numbers and timings as the web version. Mouse, keyboard and gamepad.

| File | What it does |
|---|---|
| `ui.gd` | CanvasLayer (layer 20). Public API (stub header kept), input router (keys → actions, gamepad buttons, stick/D-pad repeat), modal layer stack + 200 ms guard, menu / pause / end flows, fades, settings (applies fullscreen / vsync), Events wiring. |
| `teletext.gd` | One teletext display = Control in a SubViewport: build pass records blocks + glyphs (Atkinson Hyperlegible Bold, no AA, nearest), `_draw()` replays them. Page builder (header, pnum, item, info, ticker, mosaic…) + screen logic (selection, ◄► values, digit entry `P200`, hit testing). |
| `tt_pages.gd` | The pages: P100 index, P200/201 options, P300/301 controls (keyboard / gamepad), P400 credits, loading, P150 pause, P160 notes, P999 quit, caught, game over, win test card. |
| `tv_menu.gd` | 3D menu: curved glass mesh fitted on television_02 (found via `Game.world.tv`, any matching mesh, else `Layout.PROPS.tv`), `shaders/ui_crt_tv.gdshader`, menu Camera3D (framing, drift, dolly-in on start), analytic ray → glass picking, CRT power-off transition. |
| `crt_overlay.gd` | Full-screen 4:3 tube (`shaders/ui_crt_screen.gdshader`), 62 % black over the frozen room for the pause, mouse hover / click / wheel. |
| `hud.gd`, `subtitles.gd` | Objective typewriter + fade, dot → prompt + keycap (layout-aware key label, round "A" for gamepad) + hold ring, alert, battery (flashlight on), stamina (low), closet hint; subtitles (2 lines max, drawn above the fade). |
| `note_view.gd` | Paper notes: `note` (ruled school paper), `child` (crayon words, `shaders/ui_crayon.gdshader`), `newspaper` (masthead/date/headline parsed from the text, 2 justified columns, drop cap, torn edge). `shaders/ui_paper.gdshader` paper. |
| `keypad_view.gd` | Brass 4-wheel padlock (`shaders/ui_brass.gdshader`): rolling drums, chevrons, index marks, clue scrap, Essayer / Lâcher. |
| `ui_style.gd` | Fonts, palettes, French typography (`fr`, `up`), wrapping, layout-aware key labels. |

## Integration notes
* `menu_camera_active` is true while the TV menu owns the view (states `loading` once the TV exists, and `menu`). The UI
  calls `update_menu_camera()` itself every frame and makes its own `MenuCamera` current (it copies the game camera's
  `attributes` / `environment` / `compositor`). On `playing` the player blends from that camera (it reads the current
  camera in its `game_state` handler, which runs after the UI's), then the UI hands the view back (deferred).
* While the menu is up: `world.lighting.set_tv_light(true, 1)` (fallback `world.tv.set_on(true)`) and
  `lighting.set_menu_mode(true)`; both reverted when it closes. Positional `tv_static` hum at the glass.
* "Nouvelle partie": static burst + collapse (1.2 s wall clock), fade to black at 0.82 s, `Events.ui_start`; if nothing
  fades in within 120 ms, the UI fades in (puzzles' intro normally does).
* Pause: `Game.pause()` awaits `show_pause()`; Esc / P / Start / B / "Reprendre" call `hide_pause()` which resolves it.
  "Quitter" → P999: back to the TV menu (resets `Game.night`, `Game.time_played`, unpauses, reloads the scene) or quits.
* Modals (note, keypad, pause / end CRT) swallow keyboard / gamepad input; `is_modal_open()` stays true 200 ms after the
  last one closes (the E that closes a note does not re-open it).
* Settings written: quality (low/medium/high/ultra), brightness, fov, camera_motion, fullscreen, vsync, volume (+
  `Audio.set_master_volume`), subtitles, sensitivity, invert_y. Fullscreen / vsync are applied here (also at boot unless
  the command line forces a window mode).
* UI sounds go through `Audio.play(name, {volume_db, pitch, ui: true})` (also while the tree is paused).

## Tests
```
godot --headless --path pc -s res://scripts/ui/tests/test_ui.gd          # 94 checks on the real main scene (menu, options,
                                                                         # picking, start, HUD, pause, notes, keypad, endings)
godot --headless --path pc --quit-after 900 -- --autostart               # zero errors
pc/tools/godot_shot.sh --res 1280x720 -- --ui-shots=menu,options,controls,credits,poweroff,loading,hud,hud_pad,pause,pause_options,notes,note,child,newspaper,keypad,caught,gameover,win --ui-out=/abs/prefix
pc/scripts/ui/tests/ui_render.sh 1280x720 res://scripts/ui/tests/menu_on_tv.gd --out=/abs/prefix --pages=main,options
                                                                         # the menu on the real exported TV (MetaUtil level)
```
