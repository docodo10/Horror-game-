# La Gardienne — PC version (Godot 4.5.1, Forward+) — architecture & module contract

The PC version is a port of the web game (repo root: `index.html`, `src/**`, `ARCHITECTURE.md`) to **Godot 4.5.1**
(engine in C++, game code in GDScript, Jolt physics, Vulkan Forward+ renderer) exported as a **Windows .exe**.
Same level, same story, same assets, same French text. The web code is the **reference implementation**: port its
behaviour faithfully (read the matching `src/**` file before writing your module), then use Godot's strengths for
higher realism (SDFGI global illumination, SSIL, SSAO, SSR, volumetric fog, glow, AgX tonemapping, DOF, light projectors,
real physics, AudioStreamPlayer3D + reverb buses).

Project root: `pc/` (`res://`). Assets are symlinks to the repo's `assets/` (`res://assets/models/*.glb`,
`res://assets/textures/<set>/*.jpg`, `res://assets/audio/**.mp3` + `manifest.json`). Generated assets from the web build
(exporter) go to `res://assets/generated/`.

## 1. File ownership

| Module | Files (owner edits ONLY these; may create new files under its own folder) |
|---|---|
| core (lead) | `project.godot`, `export_presets.cfg`, `autoload/{events,settings,game,debug_tools}.gd`, `scenes/main.*`, `scripts/input_setup.gd`, `scripts/layout.gd` (generated), docs |
| exporter | `../tools/export-godot.cjs` (repo root tools, Node + Playwright), `res://assets/generated/**` (its outputs) |
| world | `scripts/world/world.gd`, `scripts/world/handle.gd`, `scripts/world/level_loader.gd` (new), `scripts/world/props_*.gd` (new) |
| look | `scripts/world/lighting.gd`, `scripts/render/**`, `shaders/**` (shared folder: prefix your files `look_`) |
| player | `scripts/player/**` |
| gameplay | `scripts/game/**` |
| entity | `scripts/entity/**` |
| audio | `autoload/audio_manager.gd`, `scripts/audio/**`, `default_bus_layout.tres` |
| ui | `scripts/ui/**`, `shaders/ui_*.gdshader`, `assets/fonts/**` |

Every module file currently contains a **working stub** whose header comment is the public API you must keep (you
may add members). Never edit files you don't own; if you need something, call it defensively (`has_method`, `get`)
and report it.

## 2. Conventions
* Coordinates are identical to the web version (meters, +Y up, −Z north; glTF and Godot share this). `Layout`
  (`scripts/layout.gd`, generated from `src/config/layout.js`) holds every constant: ROOM, STAIRS, doors, closet, nook,
  window, PROPS, EXTRA_PROPS, ITEMS, SPAWN, NAV_NODES/NAV_LINKS, `ground_height_at()`.
* Physics layers: 1 = WORLD (walls, floors, stairs, furniture: blocks movement and sight), 2 = INTERACT (interaction
  trigger bodies), 3 (value 4) = PLAYER, 4 (value 8) = ENTITY. Use the constants on `world.gd`.
* Pause: gameplay nodes use `PROCESS_MODE_PAUSABLE`; UI/autoloads `PROCESS_MODE_ALWAYS`. `Game.pause()` pauses the tree.
* Global signals live in `Events` (autoload). Shared services: `Game` (state machine + references to systems:
  `Game.world/player/camera/entity/ui/interaction/inventory/puzzles`), `Settings`, `Audio`, `DebugTools`.
* No per-frame allocations in hot paths; cache node references; use typed GDScript.
* All player-facing text in French (Québec-friendly, tutoiement).

## 3. Game flow (core)
`scenes/main.gd` builds, in order: UI → World (`await world.build(progress)`) → Inventory → Player → Gardienne
(`await entity.build()`) → Interaction → Puzzles (`await puzzles.setup()`) → `Quality.apply()` → menu (or autostart).
`Game` states: loading → menu → playing ⇄ paused; playing → caught → playing (nights 1..3) / gameover; playing → won.
Caught: entity plays its jumpscare, then emits `Events.entity_caught` → `Game.on_caught()` fades, shows the caught
screen, calls `reset_after_caught()` on player/entity/world/puzzles. Win: `Events.game_win` → `Game.on_win()`.

## 4. Module specs

### Exporter (`tools/export-godot.cjs`, repo root)
Run the **web build** headless (tools/shot.cjs harness pattern, THREE_DIR) and export the level so Godot reuses every
procedural thing already built (architecture, decals, procedural props, canvas textures):
1. `assets/generated/level.glb`: every mesh that is NOT an instance of an original model from `assets/models/`
   (Assets.instance clones — tag them; e.g. walk up the parents for a node whose name/userData matches a MODELS id,
   or patch `Assets.instance` in-page to set `userData.modelId` before the world builds), exported with GLTFExporter
   (binary, JPEG for photo textures / PNG only for alpha, KHR_texture_transform for repeats, node names kept and unique,
   InstancedMesh expanded or EXT_mesh_gpu_instancing removed if Godot can't import it, custom ShaderMaterials replaced
   by their closest MeshStandardMaterial or skipped and listed).
2. `assets/generated/level_meta.json`: (a) `instances`: every original-model instance {modelId, name, world matrix
   (16 floats, column-major), hidden child node names, material tint overrides if any}; (b) `handles`: for every
   `world.handles[id]`: {id, node path (instance name + child node name, or level.glb node name), kind, closed and open
   LOCAL transforms of the moving node (obtained by opening/closing the handle in-page), sfx names, contents node};
   (c) `items`, `clues`, `tv` screen transform, `hideSpots`, `colliders` (all AABBs with tags), lights (type, color,
   intensity, position, castShadow) for reference; (d) clue digit decal placements.
3. `assets/generated/gardienne.glb`: La Gardienne's procedural skinned model (src/entity/GardienneModel.js) with
   **baked animation clips** sampled at 30 fps by driving the model's own procedural animation in-page for each mode:
   `idle`, `walk`, `walk_stairs`, `search` (listening/tilts), `chase`, `reach` (door/closet), `jumpscare`, `duck_walk`;
   loopable where relevant (blend the last frames). Hair chains and gown springs are baked into the clips.
4. Procedural textures needed directly by Godot code (notes, child drawing, newspaper, code note, TV static
   frames if useful) as PNG under `assets/generated/textures/`.
Document everything in `assets/generated/README.md`. Re-runnable: `node tools/export-godot.cjs`.

### World (`world`)
`level_loader.gd`: instantiate `level.glb`, then every `instances[]` entry from the ORIGINAL `res://assets/models/*.glb`
(Godot-imported — best fidelity) with its transform/hidden nodes; build StaticBody3D colliders (LAYER_WORLD) from
`colliders[]` plus floors: main floor, stair ramp (invisible convex/box ramp under the treads so CharacterBody3D can climb
smoothly), landing and upper hallway floors, closet floor; interaction bodies (LAYER_INTERACT) around handles, items,
clues, TV, closet door, window. `handles` = `Handle` objects bound to the real nodes using the exported closed/open
transforms. `items`, `clues`, `tv` (CRT screen material with animated static/digit — port src/world/Props.js TV),
`hide_spots`, nav AStar3D (already in the stub), `line_blocked`, `ground_height_at`, `set_power` (fan blades spin,
TV availability, emits `Events.power_changed`), `set_clue_digits` (duck/horse decals, clock hands), rocking chair
`rock_chair(seconds)`, mirror (Godot `ReflectionProbe` or a planar mirror via SubViewport camera on high/ultra),
old CRT flicker on power-up, fluorescent tube in the nook. Until `assets/generated/` exists, keep a fallback that builds
the room from `Layout` + places `Layout.PROPS`/`EXTRA_PROPS` models directly so others can test.

### Look (`look`)
`lighting.gd`: warm 2700 K ceiling OmniLight3D (shadows, soft PCSS-like via `light_size`), moonlight SpotLight3D
through the window (bar shadows, volumetric fog contribution), door strip light, TV light, nook fluorescent; power
states/flicker/blowout/stress/menu mode with tweens (never add/remove lights at runtime). `scripts/render/quality.gd`:
WorldEnvironment + CameraAttributes presets — low (no SDFGI, SSAO low, no fog), medium, high (SDFGI, SSIL, SSAO, SSR,
volumetric fog, glow, AgX, TAA/FXAA, DOF far blur subtle), ultra (higher SDFGI cascades, shadow atlas 8192, MSAA 4x,
fog detail); plus brightness/FOV settings. Film grain / vignette / chromatic aberration / fear pulse / flash / shake /
closet slats as a full-screen `CanvasLayer` shader (`shaders/look_postfx.gdshader`) with an API on `quality.gd`
(`set_fear(v)`, `flash(color, amount, dur)`, `shake(amount, dur)`, `set_hidden_view(v)`, `set_blur(v)`).
Compare with the user's reference photos (paths in the web ARCHITECTURE.md / agent brief) and the web screenshots.

### Player (`player`) — port of src/player/Player.js + src/core/Input.js (desktop/gamepad only)
CharacterBody3D (capsule r 0.25), mouse look (sensitivity/invert from Settings), gamepad look, walk 1.9 / crouch 0.9 /
sprint 3.3 m/s with stamina, stairs via the ramp + floor snap, the full POV rig (head bob synced to footsteps, sprint FOV
kick, lean, strafe roll, breathing, fear tremor from `Game.fear`, flinch on `Events.entity_spotted`, landing dips),
footsteps per surface (carpet/wood/concrete) via `Audio.play` + `Events.noise` (loudness table in ARCHITECTURE.md),
flashlight SpotLight3D with a projector cookie texture, lag spring, battery drain/flicker/auto swap, hide spots
(animated, limited look), `get_visibility()`, respawn/teleport. Emits Events.player_*.

### Gameplay (`gameplay`) — port of src/game/{Interaction,Inventory,Puzzles}.js
Interaction: camera ray (PhysicsRayQueryParameters3D, mask LAYER_WORLD|LAYER_INTERACT, first hit wins; an interact
body maps to its entry via metadata `interact_id`), prompt + hold ring through `Game.ui.set_prompt`, busy lock.
Inventory. Puzzles: the complete scenario (stages, notes, objectives, hints, noise, scripted beats, ambient scares,
clues, keypad, closet, door with key, window, TV, batteries, win) exactly like the web version.

### Gardienne (`entity`) — port of src/entity/Gardienne.js
Load `res://assets/generated/gardienne.glb` (fallback: simple tall silhouette if missing), AnimationTree/AnimationPlayer
blending the baked clips, CharacterBody3D (r 0.3, height 1.72) moving along `world.nav_path` / direct pursuit, state
machine (dormant/waking/descending/searching/chasing/returning/jumpscare), hearing via `Events.noise`, sight (FOV 110°,
range × `player.get_visibility()`, LOS `world.line_blocked`), closet check, door handling, positional sounds, `fear`,
jumpscare camera takeover (`player.camera_override`), then `Events.entity_caught`.

### Audio (`audio`) — port of src/audio/Audio.js
Autoload `Audio`: load `manifest.json`, preload AudioStreamMP3s, random variation without repeats, gain/pitch jitter,
AudioStreamPlayer3D pool for positional sounds (attenuation tuned for a small room), buses (Master → SFX/Foley/
Ambience/Music/Voice, Reverb send with AudioEffectReverb small basement; darker reverb for nook/stairwell via Area3D
reverb zones or bus switching), occlusion low-pass for sounds behind the closed upstairs door and above the ceiling,
POV layers driven by events (panting, heartbeat by fear, hidden breathing, chase music, power hum, room tone, wind, clock).

### UI (`ui`) — port of src/ui/UI.js (diegetic CRT TV teletext menu)
Main menu ON the dresser TV: a SubViewport rendering the teletext pages (CANAL 3 · LA GARDIENNE, P100 index, P200
Options, P300 Contrôles, P400 Crédits) applied to the TV screen with a CRT shader; menu camera framing the TV
(`menu_camera_active` / `update_menu_camera`); power-off transition into the game. CRT full-screen pages for loading,
pause (objective, clues, inventory, notes), caught, game over, win. Minimal HUD (dot/prompt/keycap/hold ring, one-line
subtitles, objective fade, battery while flashlight on, stamina when low), paper notes, brass padlock keypad.
Mouse + keyboard + gamepad navigation.

## 5. Testing
* Headless logic run: `godot --headless --path pc --quit-after 600 -- --autostart` (prints errors).
* Rendered screenshots (Xvfb + lavapipe software Vulkan, slow, machine-wide lock):
  `pc/tools/godot_shot.sh --res 960x540 -- --shot=/abs/out.png --shot-frames=60 --cam=x,y,z,yawDeg,pitchDeg --quality=high [--power=off --flashlight --stage=code]`
  or multi-view: `-- --shots=/abs/prefix --views=spawn,stairs,kids,nook,tv,console,landing`.
* You may write your own SceneTree test scripts (`godot --headless --path pc -s res://scripts/<module>/tests/x.gd`).
* Export: `godot --headless --path pc --export-release "Windows Desktop" build/windows/LaGardienne.exe` (lead does it).

## 6. Integration requests from finished modules (READ if you own world / entity / player / ui)
Gameplay is merged (see `pc/scripts/game/README.md` for the full world conventions). What it calls on other modules:

**world**
* A CollisionObject3D on LAYER_INTERACT under every handle node, item, clue and the TV node. Bodies elsewhere need
  metadata `interact_id` = the entry id (or the plain handle/item/clue id). Full-box furniture colliders on LAYER_WORLD are fine.
* `handles["powerBox.lever"]`: `is_on` + awaitable `set_on(on)` that plays `breaker_flip` and calls `world.set_power(on)`;
  the lever follows `set_power` silently (so it trips at the blowout, like web Props).
* Optional `handles["lockedBox.lock"].set_digits(code)` (gameplay calls it with every code tried).
* `tv`: a Node3D (or object with a `node` property) exposing `is_on`, `set_on(on)`, `set_digit(d)`, `screen_position`.
  Gameplay plays tv_on/tv_off itself — the world TV must not also play tv_off.
* `rock_chair(seconds)`; `hide_spots = [{id:"closet", door: <closet Handle>, hide_pos, hide_yaw, exit_pos}]`;
  `set_clue_digits({duck, horse, clock, tv})`; `lighting.flicker(d, depth)` and `lighting.blowout()`
  (gameplay calls set_power(false) itself afterwards).
* Flavour props are found by node name — use the web names (photoFrame, alarmClock, cassette, rockingChair, extra_gnome,
  extra_mirror, extra_oldTv, extra_boombox, extra_toolbox, extra_laundry, extra_bat, extra_football, extra_gamepad,
  extra_mousetrap, extra_stairPhotoA, extra_stairPhotoB) or expose `world.props` keyed by those names.

**entity**
* `summon(pos, "breaker")` sets `active = true` during the visit and false once she is back upstairs (the code stage
  starts on that transition; 12 s fallback if she never becomes active, 3 s if state is "disabled").
* Gameplay calls `set_aggression(2)` after the key, suppresses hints while `state == "chasing"`, and blocks interaction
  while `state == "jumpscare"`.

**player**
* Awaitable `enter_hide(spot)` / `exit_hide()`; `flashlight` dictionary {has, on, battery}; `hidden`; `camera_override`
  (interaction blocked while true and not hidden); `global_position` at the feet (win check: y > 2 in the upper hall);
  `give_flashlight()`, `set_flashlight_on(true)`.

**ui**
* `set_prompt(text, {key: "E" | "A", hold: 0..1})` ("A" = last input was a gamepad); awaitable `show_keypad(title, 4)`
  returns "" when cancelled; `show_note({id, title, text, style})` with style note | child | newspaper; optional
  `set_inventory(items, notes)` (inventory entries carry an SVG `icon` with stroke="currentColor").
* Modals go through `Game.modal(func(): return await Game.ui.show_keypad(...))`.
