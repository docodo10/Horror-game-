# Entity module — La Gardienne (`scripts/entity/**`)

Port of the web `src/entity/Gardienne.js` (AI) and of the runtime side of `src/entity/GardienneModel.js` on top of the
exporter's `res://assets/generated/gardienne.glb` (93 bones, 5 skinned meshes + eyes/glints, 9 baked clips).
Same states, numbers, timings and sounds as the web version.

| File | What it does |
|---|---|
| `gardienne.gd` | The entity (`Game.entity`): `CharacterBody3D` + the whole AI (states, hearing, sight, closet, doors, audio, fear, jumpscare, reset, watchdogs, debug args). |
| `gardienne_model.gd` | The body: glb loading (worker thread), materials, `AnimationTree` built in code, gait phase + footsteps, glitches, eyeshine, exposure, attach points (face / eyes / head / feet), fallback silhouette. |
| `gardienne_pose.gd` | `SkeletonModifier3D` after the tree: look-at (absolute aim, chest / neck / head split) + glitch head snaps / arm spasms. |
| `tests/` | `test_entity.gd` (AI scenarios, 48 checks), `lookdev.sh` + `lookdev.gd` (renders in the real basement). |

## Public API
Kept from the stub: `build()` (await), `state`, `fear`, `active`, `root`, `summon(target, reason := "")`,
`set_aggression(level)`, `set_enabled(on)`, `reset_after_caught()`. Events: emits `entity_state(state, prev)`,
`entity_spotted()`, `entity_caught()`; listens to `noise`, `player_hide`, `game_state`, `settings_changed`.

Added: `summon(target, reason, aggressive := false)`, `model`, `enabled`, `aggression`, `suspicion`, `yaw`, `seeing`,
`state_log` (`{t, state, prev, pos}`), `stall_events`, `head_position()`, `eye_position()`, `face_position()`,
`debug_place(pos, yaw, mode := "idle", t := -1.0, look := null)`, `debug_release()`, `debug_jumpscare(freeze_t := -1.0)`.
`state` values: `dormant waking descending searching chasing returning jumpscare disabled`; `active` is true from `waking`
until she is `dormant` again (gameplay waits on that after the breaker).

## Behaviour (web parity)
* **dormant** (hall, invisible): `Events.noise` >= 0.12 adds suspicion `(lv - 0.1) x 0.9 x falloff(distance to the
  stairwell door) x aggression gain`, 1.0 noises fill it; 1.6 wakes her. Patrols every 90-180 s after the first visit
  (70-140 s / 45-90 s with aggression 1 / 2). 25 s grace after a catch.
* **waking**: `ceiling_steps` (or one `ceiling_walk`) crossing the ceiling toward the door, door-strip occlusion
  (`lighting.door_strip_occluded`), `knock_wall`, then the upstairs door opens (`world.handles["door.upstairs"]`, its
  `locked` flag restored afterwards unless gameplay unlocked it).
* **descending / searching / returning**: nav path (`world.nav_path`), 0.95 m/s (0.78 on the stairs), search points around
  the noise with listening pauses (slow turn, `lullaby_hum` loop following her head, `whisper` / `giggle`), returns after
  the points or 50 s (+20 s per aggression level), closes the door behind her.
* **sight**: FOV 110°, range 12 m x `player.get_visibility()` (1.4 m sense radius), LOS `world.line_blocked` to the eyes
  then the chest. **chasing**: 0.45 s freeze-and-stare + `entity_croak` + `Events.entity_spotted`, then 2.9 m/s (+0.15 when
  hunting), direct when the capsule sweep is free, A* with 0.7 s repath otherwise, loses the player after 4 s (3x faster
  when they hid unseen). Saw the player slip into the closet -> walks to it, opens `door.closet` -> jumpscare.
* **jumpscare** (0.85 m + LOS): `player.camera_override = true`, `enabled = false`; she lunges until her face is 0.24 m
  from the lens (then hovers at 0.31 m), the camera locks onto her face trembling, `jumpscare` scream,
  `Quality.flash/shake/set_blur` (look module, called if present), a cold fill light under the lens and an exposure
  compensation from the torch irradiance; `Events.entity_caught` 1.4 s later. `reset_after_caught()` puts the house back
  (closet / upstairs doors), gives the camera back and sends her home (dormant, grace 25 s).
* **fear** 0..1 per state + distance (read by `Game`), `lighting.set_stress(0..1)` within 5 m, eyeshine when the torch
  points at her eyes (glint emission 0.25 + eyeshine x 7).

## Godot specifics
* **Body**: `CharacterBody3D` on LAYER_ENTITY (8), mask LAYER_WORLD, floating motion. Capsule r 0.3 from 0.45 m to 1.72 m
  above her feet (clears treads, the stair ramp, low clutter; ducks under the bulkhead), `move_and_slide` slides along
  walls / furniture, the height comes from `world.ground_height_at` like the web. The web `segmentBlocked()` is a Jolt
  capsule sweep (`cast_motion`, ~3.5 µs) with the same shape.
* **Never stuck**: the web per-waypoint watchdog (back off, skip a waypoint, give the goal up) + a global stall watchdog
  (no 0.6 m of travel in 4 s while she means to walk: detour, detour, 1.5 s collision-less squeeze, give the goal up) + a
  2-minute return timeout (only when the player can't see her). The tests show 0 interventions in the real layout.
* **Physics tick / frame split**: AI at 60 Hz in `_physics_process`; the model (`root`, top-level) is interpolated between
  ticks, the stair steps smoothed, the `AnimationTree` advanced and the jumpscare camera written every rendered frame.
* **AnimationTree** (manual process): gait clips are seeked every frame from one shared gait phase that advances like the
  web model (cycles/s = speed / (2 x step length)): speed-matched, no foot sliding, in phase with each other (per-clip
  phase offsets from the meta's heel strikes; footsteps land within 20 ms of the baked strikes).
  `chaseB` walk/chase, `stairsB` (Blend3) treads down/up, `duckB` upper body only (duck_walk) under the bulkhead,
  `moveB` idle/moving, `searchB`, `reachB`, `jumpB` (jumpscare clip seeked to the jumpscare time). Glitches: frame-skip
  freezes hold the pose, head snaps and spasms are added by `gardienne_pose.gd`.
* **Materials**: skin / face with screen-space subsurface scattering (skin mode, low on the body so bones stay readable,
  higher on the face) + transmittance (red through thin fingers against a light) + thin clear coat; teeth / eyes clear
  coat; gown fabric sheen (rim) + backlight; hair wet sheen (it is nearly black: albedo ~0.003); hair and gown tears
  alpha-to-coverage under MSAA, alpha hash under TAA (`apply_quality()` after each preset); "low" drops SSS / clear coat.
  Close to the torch her albedo adapts (irradiance > 9 -> x0.5 at most) so she never clips to flat white.

## Debug args (after `--`)
`--noentity`, `--entity-log` (state transitions + watchdog), `--entity-aggression=N`, `--entity-noise=x,y,z[,loudness]`,
`--entity-summon=x,z`, `--entity-place=x,y,z,yawDeg[,mode[,t[,stare]]]`, `--entity-front=dist[,mode[,t[,stare]]]`
(in front of the camera, facing it), `--entity-jumpscare[=t]` (t = frozen frame), `--entity-light` (key light near her).
Modes: `idle walk chase search reach duck_walk stairs_up stairs_down stairs_duck jumpscare`.
```
pc/tools/godot_shot.sh --res 960x540 -- --shot=/abs/a.png --cam=0.25,0,1.5,0,-3 --entity-front=2.2,walk,0.45
pc/tools/godot_shot.sh --res 960x540 -- --shot=/abs/b.png --cam=0.25,0,1.5,0,-3 --flashlight --entity-jumpscare=0.5
godot --headless --path pc --fixed-fps 60 --quit-after 7200 -- --autostart --entity-log --entity-noise=2.6,1.45,-4.553,1.0
```

## Tests
```
godot --headless --path pc --fixed-fps 60 -s res://scripts/entity/tests/test_entity.gd [-- --entity-log]   # ~3 s, 48 checks
pc/scripts/entity/tests/lookdev.sh /abs/prefix lit,lit_close,lit_side,stairs_duck,dark,dark_close,stare,jump,jump_lit 10
```
`test_entity.gd` builds the web basement's collision boxes (level_meta.json) with the two doors as real `Handle`s, a
scripted player double, and runs: A breaker noise while the player hides unseen (full visit, door opened / closed /
relocked), B summon -> chase -> jumpscare -> `Game.on_caught` reset, C chase lost, D closet, E crate blocking the stairs
(watchdog squeeze), F look-at aim, G footstep phase. The lookdev assembles the real level (meta_util.gd) with stand-in
lights calibrated like the player module's sandbox.
