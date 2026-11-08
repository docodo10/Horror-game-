# Gameplay module (`scripts/game/**`)

Port of the web `src/game/{Interaction,Inventory,Puzzles}.js`. The web code is the reference; this is the same scenario,
the same French text and the same timings, on top of the Godot APIs in `ARCHITECTURE_PC.md`.

| File | What it does |
|---|---|
| `interaction.gd` | Camera ray (`Game.camera`, mask WORLD\|INTERACT), prompt + hold ring via `Game.ui.set_prompt(text, {key, hold})`, hold-to-use, busy lock (12 s safety), `when_hidden` entries (closet exit), gamepad key hint ("A"). |
| `inventory.gd` | Items (`flashlight`, `battery`, `key`) with French singular/plural names + SVG line icons, notes in discovery order. Emits `Events.inventory_changed`, mirrors to `Game.ui.set_inventory` if present. |
| `puzzles.gd` | The whole scenario: stages `intro → dark → power → code → escape → win`, notes, objectives, timed hints, noise table, scripted beats (blowout, rocking chair, first visit after the breaker, aggression after the key), ambient scares on a tension curve, clues (duck, horse, clock, TV), keypad, pickups, closet, upstairs door (locked / hold 2 s with the key / win), window, TV, batteries, gnome turned after a catch, mirror whisper, `debug_goto`. |
| `tests/` | `test_gameplay.gd` (SceneTree test) + driver + fakes; `main_runner.gd` / `main_like.gd` (copy of `scenes/main.gd`'s build order, only needed while `scenes/main.gd` does not parse). |

## What the world should provide (all optional — missing things are skipped and listed once in the log)

* `handles[id]` (`Handle`: `node`, `is_open`, `locked`, `open()/close()` awaitable, `world_position()`), ids as in the web
  (`dresser.drawerTop`, …, `powerBox.lever`, `lockedBox.lid`, `lockedBox.lock`, `door.upstairs`, `door.closet`).
  `powerBox.lever` may add `is_on` + `set_on(on)` (await; plays `breaker_flip`, calls `world.set_power`); the padlock may add
  `set_digits(code)` (called with every code tried).
* `items[id]` Node3D (`flashlight`, `battery1`, `battery2`, `key`, `note1..3`), `clues[duck|horse|clock|tv]` Node3D,
  `tv` (Node3D or object with `node`) with `is_on`, `set_on(on)`, `set_digit(d)`, `screen_position`,
  `hide_spots` [{id: "closet", door: Handle, hide_pos, hide_yaw, exit_pos}], `power`, `set_power(on)`, `set_clue_digits(d)`,
  `lighting.flicker(d, depth)` / `lighting.blowout()`, `rock_chair(seconds)`.
* Flavour props are found by node name: web names first (`photoFrame`, `alarmClock`, `cassette`, `rockingChair`,
  `extra_gnome`, `extra_mirror`, `extra_oldTv`, `extra_boombox`, `extra_toolbox`, `extra_laundry`, `extra_bat`, `extra_football`,
  `extra_gamepad`, `extra_mousetrap`, `extra_stairPhotoA/B`), then the layout key or model id; a `world.props` dictionary is
  checked before the tree search.

### Interaction bodies
* Put a `CollisionObject3D` (StaticBody3D or Area3D) on **LAYER_INTERACT** under each node (handle node, item, clue, TV). A body
  resolves to the entry of its nearest registered ancestor (most specific first), so an item body inside a drawer node picks
  the item. Bodies elsewhere can carry metadata `interact_id` = entry id (or the handle / item / clue id: `flashlight`,
  `duck`, `door.closet` are accepted aliases). Registration tags every body under a node with its entry id.
* Nothing hittable under a node and no tag → the interaction builds an invisible LAYER_INTERACT box from the node's meshes.
* WORLD bodies block the ray, but interactables **inside** the first WORLD collider the ray enters stay reachable (furniture
  colliders are AABBs: horse on the shelves, note 3 in the open cabinet, key in the box). Areas never block.

## Debug
`--stage=dark|power|code|escape|win` (through DebugTools → `debug_goto`), `--power=off`, `--code=1234` (debug builds).
Debug builds print the code and the number of interactables.

## Tests
```
godot --headless --path pc --fixed-fps 60 -s res://scripts/game/tests/test_gameplay.gd      # full scenario to the win, 95 checks
godot --headless --path pc --quit-after 900 -s res://scripts/game/tests/main_runner.gd -- --autostart [--stage=code]
```
