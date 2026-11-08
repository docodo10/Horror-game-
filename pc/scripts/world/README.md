# World module (`scripts/world/**` except `lighting.gd`)

The basement level of the PC version. Port of the web `src/world/{World,Architecture,Props,ExtraProps}.js`, built from
the exporter's outputs (`res://assets/generated/`: `level.glb` + `level_meta.json`) and the **original**
`res://assets/models/*.glb` (Godot-imported, best fidelity), with real Jolt physics.

| File | What it does |
|---|---|
| `world.gd` | Public API (stub header kept + additions), build order, power, clue digits, nav (AStar3D), sight, reset, debug args |
| `handle.gd` | `Handle` (class_name): animated openable bound to a real node, web easing / durations / sounds, interruptible, awaitable |
| `level_loader.gd` | Threaded preload of every scene / texture (smooth loading bar; synchronous in headless), assembly with the exporter's `MetaUtil` (exact web matrices, hidden variants, node transforms, material overrides, attachments, reparents) |
| `props_physics.gd` | `LAYER_WORLD` movement boxes (web colliders), floors, **stair ramp**, landing, hallway; `LAYER_SIGHT` occluders; `LAYER_INTERACT` bodies |
| `props_handles.gd` | the 14 handles from `handles{}` (closed / open transforms measured in the web build) + `LeverHandle`, `PadlockHandle`, `LidHandle` |
| `props_tv.gd` | dresser TV: GPU static shader (snow, rolling bar, scanlines, CRT mask, clue digit pulses), warm-up / collapse, `tv_static` loop, TV light |
| `props_crt.gd` | old CRT in the nook: the ~1.9 s power-up flicker beat (additive phosphor shader, sounds, small light on high / ultra) |
| `props_anim.gd` | fan, alarm clock (ticking from 03:07:12), grandfather clock (clue hour), rocking chair, clue decals, pull chain, smoke-detector LED |
| `props_nook.gd` | the laundry-nook **fluorescent batten** (starter clicks / strikes on power-up, ageing dips; `level` for the look module's light) |
| `props_reflections.gd` | box-projected interior ReflectionProbes (fade with the mains) + the **live planar mirror** on high / ultra |
| `props_materials.gd` | thin glass for the scans' atlas glass, the dead nook bulb, no-receive-shadow list, dynamic GI mode for moving parts |
| `props_fallback_lighting.gd` | placeholder lights with the `lighting.gd` API — used only while the look module's `lighting.gd` builds no light |
| `props_fallback_level.gd` | Layout-built level + synthetic meta — used only when `assets/generated/` is missing (or `--world-fallback`) |
| `tests/` | `world_test.gd` (173 checks), `interact_test.gd` (gameplay ray x world bodies), `dump_level.gd`, `probe_mesh.gd` |

## Physics layers
* `LAYER_WORLD` (1): what blocks the player / the entity — the 45 web AABBs (walls, closed upstairs door, open closet leaf,
  furniture; clutter lower than 0.45 m is raised so the player's 0.3 m step-up never climbs it), the basement / nook
  floors, the **stair ramp** (plane through the foot of the first riser and the landing nosing, 39°: a capsule rides
  `r (1/cos a - 1)` = 7 cm above it, the player eases its camera on the Layout tread heights), landing, hallway.
  Bodies carry metadata `tag` (wall, door, sofa, prop, stairs, floor…).
* `LAYER_SIGHT` (16, world-internal): the web occluders (walls, ceiling slab, landing, knee-wall pieces, doors — children of
  the door pivots —, sofa / dresser / clock / shelves / console / cabinet / box sight boxes). `line_blocked()` uses only
  this layer, like the web `lineBlocked` (the stair railing and the chair AABBs do not block sight).
* `LAYER_INTERACT` (2): one box per handle node (child: follows drawers / doors / lids), item, clue and the TV, tagged with
  metadata `interact_id` (handle id, item id, clue key); the web hit proxies are rebuilt for the lid, padlock, breaker
  lever, batteries and key.

## API additions (see `world.gd` header)
`LAYER_SIGHT`, `rock_chair(s)` (await), `props {web name: Node3D}`, `meta`, `ctx`, `colliders`, `occluders`, `floors`,
`nav_nodes`, `ground_probe(x, z, from_y)`, `tv.screen` / `tv.node` / `tv.brightness`, `crt.flicker(delay)`,
`nook_tube` (`level`, `level_changed`, `auto`, `set_level`), `reflections` (`probes`, `mirror_active`, `refresh()`),
`anim` (`fan_speed`, `rocking`, `clock_hours`, `kick_chain`), `upper_hall`, `code_note`.
`Handle` additions: `kind`, `object`, `center`, `t`, `open_duration` / `close_duration`, `ease_open` / `ease_close`,
`moving[]`, `on_change` / `on_start` / `on_settled`, `settled` signal, `set_state(open)`, `wait()`.
`handles["powerBox.lever"]`: `is_on`, `set_on(on)` (await), `follow_power(on)`; `handles["lockedBox.lock"]`:
`set_digits(code)`, `removed`, `remove_lock(fast)`.

## Tests
```
godot --headless --fixed-fps 60 --path pc -s res://scripts/world/tests/world_test.gd               # WORLD TEST OK
godot --headless --fixed-fps 60 --path pc -s res://scripts/world/tests/world_test.gd -- --world-fallback
godot --headless --fixed-fps 60 --path pc -s res://scripts/world/tests/interact_test.gd -- --autostart   # INTERACT TEST OK
godot --headless --path pc --quit-after 900 -- --autostart --world-log
pc/tools/godot_shot.sh --res 960x540 -- --shots=/abs/prefix --views=spawn,stairs,kids,nook,tv,console,landing --quality=high
```
Debug args (after `--`): `--world-open=id1,id2|all`, `--world-tv[=digit]`, `--world-crt`, `--world-rock`, `--world-log`,
`--world-fallback`.
