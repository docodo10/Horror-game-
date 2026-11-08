# La Gardienne — architecture & module contract

First-person 3D horror / escape game (Granny-like) running in the browser with **three.js r170 (WebGL2)**.
Chapter 1 = one level: a 1990s basement family room ("le salon du sous-sol") + a small laundry nook.
Target: photoreal look (photoscanned CC0 assets, PBR, soft shadows, baked environment lighting, filmic post-processing),
playable on **desktop (mouse/keyboard + pointer lock)** and **phones (touch controls, landscape)**.
All player-facing text is **French** (Québec-friendly, simple words, tutoiement).

No build step: plain ES modules + import map (`three` and `three/addons/` from jsDelivr, pinned 0.170.0).
`index.html` → `src/main.js` → `src/core/Game.js`.

## 1. File ownership

| Module | Files (owner edits ONLY these) |
|---|---|
| core (lead) | `index.html`, `src/main.js`, `src/core/Game.js`, `src/core/EventBus.js`, `src/core/Settings.js`, `src/core/Assets.js`, `src/world/World.js`, `src/config/layout.js`, `tools/*`, docs |
| render | `src/render/Renderer.js`, `src/render/PostFX.js` (new) |
| architecture | `src/world/Architecture.js`, `src/world/Lighting.js` |
| props | `src/world/Props.js`, `src/world/ProcTextures.js` (new) |
| player | `src/core/Input.js`, `src/player/Player.js` |
| gameplay | `src/game/Interaction.js`, `src/game/Inventory.js`, `src/game/Puzzles.js` |
| entity | `src/entity/Gardienne.js`, `src/entity/GardienneModel.js` (new) |
| audio | `src/audio/Audio.js` |
| ui | `src/ui/UI.js` |

Every module file currently contains a **working stub** with the full public API in its header comment.
Replace the stub with the real implementation **keeping every public member** (you may add more).
Never edit files you don't own. If you need something another module doesn't expose, call it defensively
(`obj.method?.()`), and list the request in your final report.

Each module injects its own CSS (a `<style>` element created in JS) — do not edit `index.html`.
Design tokens available as CSS variables (defined in index.html): `--ink #0b0907`, `--paper #e9dfc9`, `--dim #9b907c`,
`--crayon #c2412d`, `--nightlight #e8c66a`, `--glass`, fonts `--font-title` (Rock Salt, child scrawl), `--font-ui`
(Atkinson Hyperlegible), `--font-type` (Special Elite typewriter), `--font-hand` (Caveat handwriting).
z-index tokens: `--z-touch 10`, `--z-ui 20`, `--z-modal 30`. Containers: `#touch` (Input owns), `#ui` (UI owns).

## 2. Coordinates & level layout

**`src/config/layout.js` is the single source of truth** (room bounds, stairs, doors, closet, alcove, window, every
prop position/rotation, item spawns, player spawn, nav graph). Read it fully. Summary:

* Meters, Y up, main floor y=0, ceiling y=2.5. North = −Z. Room interior x∈[−3.5,3.5], z∈[−2.75,2.75].
* Models' front faces +Z when rotY=0.
* Stairs along the west wall x∈[−3.5,−2.55], first riser at z=1.6, 14 risers of 0.1964 m, treads 0.26 m, climbing north;
  landing z∈[−2.75,−1.78] at y=2.75. Room ceiling open above stairs for z<1.15 (stairwell up to y=5.2).
* Knee wall + railing line at x=−2.55 (z from −2.75 to 1.6) — one tall collider; player can't step onto the stairs sideways.
* Closet under the stairs (hiding spot): x∈[−3.45,−2.62], z∈[−2.7,−0.35]; louvered door in the knee wall facing east, centered z=−2.05.
* Upstairs door: north wall of the landing, centered x=−3.025, bottom y=2.75, hinge west, opens toward +Z. A short warm-lit hallway is behind it.
* Laundry nook ("buanderie"): x∈[0.2,3.5], z∈[−4.6,−2.75], open doorway in the north wall x∈[0.9,1.8], height 2.05. No working light.
* Barred basement window high in the south wall x∈[1.95,2.95], y∈[1.8,2.3] (moonlight).
* `groundHeightAt(x, z, prevY?)` gives the walkable floor height (stairs, landing, hallway, closet).

## 3. Core systems (already implemented by lead)

* `Game` (`game`): `events` (EventBus), `settings` (Settings: get/set; emits `settings:changed`), `scene`, `camera`
  (PerspectiveCamera, rotation order YXZ, **added to the scene** so camera children render), `assets`, `renderer`,
  `input`, `world`, `player`, `interaction`, `inventory`, `puzzles`, `entity`, `audio`, `ui`, `params` (URL debug params),
  `state`, `time`, `night`, `nightsTotal` (3), `fear` (smoothed 0..1).
  Methods: `start()`, `pause()`, `resume()`, `modal(() => promise)` (opens a UI modal safely w.r.t. pointer lock), `onCaught()`, `onWin()`.
* Init order: ui.init → renderer.init → input.init → audio.init → assets.preload → world.init (architecture.build →
  props.build → lighting.build → lighting.bakeEnvironment) → entity.init → player.init → interaction.init → inventory.init →
  puzzles.init → renderer.warmup → menu (or `?autostart`).
* Loop order each frame: input.update → [playing/caught/won: player.update → interaction.update → puzzles.update → entity.update]
  → world.update → fear smoothing (renderer.setFear, audio.setFear from entity.fear) → audio.update → renderer.render → ui.update → input.endFrame.
  `input.enabled` is set by Game: true only when state==='playing' and no UI modal is open.
* Caught flow (Game.onCaught, triggered by `entity:caught` AFTER the entity finished its jumpscare): fade to black →
  `ui.showCaught` → `player.respawn()`, `entity.reset('caught')`, `world.reset('caught')`, `puzzles.reset('caught')` → fade in.
  Inventory & puzzle progress are kept between nights. After night 3 → `ui.showGameOver()` → reload.
* Win flow: puzzles emits `game:win` → fade → `ui.showWin` → reload.
* `Assets`: `assets.instance(modelId, {uniqueMaterials})` returns a fresh clone of a preloaded GLB (see `MODELS` in
  `src/core/Assets.js` for sizes & animatable child node names). `assets.pbr(textureSetId, [u,v], opts)` returns a
  MeshStandardMaterial with color/normal/roughness/ao maps (sets: `carpet016`, `dirty_carpet`, `beige_wall_001`,
  `white_stucco`, `ceiling_interior`, `wood_floor_worn`, `stained_pine`). `assets.texture(path, {srgb, repeat})`.
* `World` (`game.world`): see `src/world/World.js`. Provides `colliders`, `occluders`, `handles`, `items`, `clues`, `tv`,
  `hideSpots`, `addCollider(min,max,tag)`, `addColliderFromObject(obj,tag,pad)`, `addOccluder(mesh)`,
  `moveCircle(pos, dx, dz, r, yMin, yMax)` (sliding collision, use it for player AND entity), `segmentBlocked(...)`,
  `lineBlocked(from, to)` (LOS vs occluders), `groundHeightAt`, nav: `path(from,to)`, `nearestNode(pos)`, `randomNodeNear(pos, r)`,
  `setPower(on)` (→ lighting.setPower + props.setPower + emits `power`), `update`, `reset`.

### Shared data shapes

```
Collider = { minX, minY, minZ, maxX, maxY, maxZ, tag, enabled }   // axis-aligned, world space
Handle = {
  id: string,
  object: THREE.Object3D,        // raycast target for interaction (its meshes)
  isOpen: boolean,
  locked?: boolean,              // doors only; gameplay sets/reads it
  open(): Promise<void>,         // animated (~0.35-0.8 s, eased); plays its own positional sfx (drawer_open, door_creak_open…)
  close(): Promise<void>,
  toggle(): Promise<void>,
  worldPosition(target?): THREE.Vector3,
  contents?: THREE.Object3D,     // drawers / box / cabinet: items parented here move with the drawer
}
// power box lever: handles['powerBox.lever'] also has { isOn, setOn(on): Promise } (plays breaker_flip)
HideSpot = { id: 'closet', door: Handle, hidePos:{x,y,z}, hideYaw, exitPos:{x,z}, ...CLOSET bounds }
TV = { object, isOn, setOn(on), setDigit(d: string), screenPosition: Vector3 }
```

Handle ids (must all exist after world.init):
`door.upstairs`, `door.closet` (architecture);
`dresser.drawerTop`, `dresser.drawerMid`, `dresser.drawerBottom`, `endTable.drawer`, `alcoveCabinet.drawer_01`,
`alcoveCabinet.drawer_02`, `alcoveCabinet.door_01`, `alcoveCabinet.door_02`, `powerBox.door`, `powerBox.lever`,
`lockedBox.lid`, `lockedBox.lock` (the padlock object; open() = shackle pops) (props).
Items (`world.items`): `flashlight` (inside dresser top drawer), `battery1` (end table drawer), `battery2`
(alcove cabinet drawer_01), `key` (inside the locked box), `note1` (coffee table), `note2` (child drawing on kid table),
`note3` (newspaper clipping inside alcove cabinet door_01). Items inside drawers are children of the handle's `contents`.
Clues (`world.clues`): `duck`, `horse`, `clock`, `tv`. `world.setClueDigits({duck, horse, clock, tv})` (props) writes the
digits: marker digit under the duck and under the horse base (canvas decals), grandfather clock hour hand pointing at the
clock digit (minute hand at 12, clock stopped), TV shows its digit inside the static when on.

## 4. Events (game.events)

| event | payload | emitted by → used by |
|---|---|---|
| `noise` | `{ position: Vector3, loudness: 0..1, source }` | player, gameplay → entity |
| `power` | `{ on }` | world.setPower → audio (hum), ui |
| `player:flashlight` | `{ has, on, battery }` | player → ui, audio |
| `player:stamina` | `{ value }` | player → ui |
| `player:hide` | `{ hidden, spotId }` | player → entity, ui, renderer (via game) |
| `player:bump` | `{ tag }` | player → audio/gameplay (bumping furniture while sprinting = noise 0.3) |
| `inventory:changed` | `{ items, notes }` | inventory → ui |
| `entity:state` | `{ state, prev }` | entity → audio (music), lighting (stress), ui |
| `entity:spotted` | `{}` | entity → audio stinger, ui |
| `entity:caught` | `{}` | entity (after jumpscare) → game |
| `game:state` | `{ state, prev }` | game → all |
| `game:win` | `{}` | gameplay → game |
| `quality:changed` | `{ quality, preset }` | renderer → lighting (shadow sizes), props |
| `settings:changed` | `{ key, value, settings }` | settings → renderer/audio/input/ui |
| `input:pause` | – | input → game |
| `input:pointerlock` | `{ locked }` | input → game |
| `ui:start` | – | ui → game |

**Noise loudness table** (gameplay/player must use these magnitudes): crouch step 0.03, walk step on carpet 0.10, walk on
stairs 0.18, sprint step 0.45, drawer/cabinet 0.15, closet door 0.12, bump furniture while sprinting 0.3, door rattle
(locked) 0.35, breaker flip 1.0, TV static while on: 0.55 every 0.5 s, box opening 0.2, flashlight click 0.02.

## 5. Scenario (gameplay owns; others provide hooks)

Stages (`puzzles.stage`):
1. `intro` — fade in from black, subtitle "…Où suis-je ?". Objective "Explore le sous-sol." Ceiling light flickers now and then.
   Note 1 on the coffee table: *« Reste en bas. Pas un bruit. Elle a le sommeil léger… La clé de la porte d'en haut est dans le coffret de Léa. — M. »*
   Upstairs door: "Verrouillée." (rattle noise 0.35 — she may hear it).
2. `dark` — after reading note 1 (or 45 s): `world.lighting.blowout()` (pop, darkness). Objective "Trouve une lumière."
   Hint after 40 s: "La commode… il y avait une lampe de poche."
3. `power` — flashlight found in the dresser top drawer (`player.giveFlashlight()`, auto ON). Objective
   "Rétablis le courant (panneau électrique, buanderie)." Panel: open door, flip lever (`powerBox.lever.setOn(true)` →
   `world.setPower(true)`) → noise 1.0 + `entity.summon(panelPos, {reason:'breaker'})` → `ui.alert('CACHE-TOI !')` +
   objective "Cache-toi ! (placard sous l'escalier)".
4. `code` — once she has returned upstairs (entity state dormant again): objective "Trouve le code du coffret (4 chiffres)".
   The locked box has a child's note: *canard · cheval · horloge · télé* (that order). Digits: duck (look under it),
   horse (under its base), grandfather clock (stopped: hour hand = digit), TV (turn on → digit flickers in the static; loud!).
   Found digits shown in the UI "carnet". Keypad UI on the box padlock; wrong code = lock_fail sfx + noise 0.15.
   Batteries: end table drawer, alcove cabinet drawer. Flashlight battery ~6 min; low battery flickers.
5. `escape` — box opens, key picked up → `entity.setAggression(2)` + scripted creak upstairs; objective
   "Monte l'escalier et ouvre la porte." Door with key: hold interact 2 s ("Déverrouiller…", noise 0.35) → door opens on a
   warm hallway → walking through (or 1.5 s after opening) → `game:win`.
Rocking chair rocks by itself once the first time the player looks at it after the blowout (`props.rockChair(6)`).
Hiding: interacting with the closet door from outside → `player.enterHide(spot)` (door opens, player slides in, door
closes); from inside → `player.exitHide()`. While hidden the entity can't see the player unless she **saw** them enter.

## 6. Module specs

### Renderer (`render`)
WebGLRenderer (antialias off when composer MSAA used), `outputColorSpace=SRGB`, physically based lights (r170 default),
**AgX or ACES filmic** tone mapping tuned for a dim warm interior, `shadowMap` PCFSoft (or VSM if it looks better).
EffectComposer: RenderPass (MSAA render target on high/ultra) → GTAOPass (high/ultra; tuned radius ~0.3–0.5, subtle) →
UnrealBloomPass (medium+; very subtle, for bulbs/TV) → OutputPass (tone mapping + sRGB) → custom FX ShaderPass in
`PostFX.js`: film grain (animated, luminance-aware), vignette, mild chromatic aberration at edges, slight barrel lens
distortion, warm/greenish color grade (lift/gamma/gain), brightness setting, `fear` response (more grain, desaturation,
CA, subtle pulse), `flash`, `shake` (UV offset), `blur` (radial), `hiddenView` (closet slats/vignette darkening).
Quality presets (`low` default on touch devices, `high` on desktop, `auto` = pick by device then step down if fps < 40 for 4 s):
`low {pixelRatio: min(dpr,1), shadowMapSize 512, shadowsFlashlight false, gtao false, bloom false, msaa 0, envSize 64}`,
`medium {min(dpr,1.25), 1024, true, false, true, 0, 128}`, `high {min(dpr,1.5), 1024, true, true, true, 4, 256}`,
`ultra {min(dpr,2), 2048, true, true, true, 4, 256}`. Read `game.params.quality` and `settings.quality`.
Expose `maxAnisotropy`. Handle resize + orientation change. No per-frame allocations.

### Architecture + Lighting (`architecture`)
Photoreal shell built from boxes/planes with **correct UVs in world units** (so tiling is uniform; use `assets.pbr`):
beige painted plaster walls (`beige_wall_001`, slight grime gradient near the floor via vertex colors or a second texture),
beige plush carpet floor (`carpet016`), popcorn/stucco ceiling (`ceiling_interior` or `white_stucco` tinted off-white),
white painted baseboards (≈10 cm) & door casings, stairs with carpeted treads + white risers, white balusters + stained
wood handrail + newel post, landing, stairwell walls up to y=5.2, upstairs 6-panel white door (procedural geometry, knob)
with a thin warm light strip under it, short hallway behind it (wallpaper-ish, lit warm — the win view), closet under the
stairs with a **louvered** white door (player can see through the slats while hidden; slats are separate thin boxes),
laundry nook (concrete/painted floor `wood_floor_worn` or `dirty_carpet`, unfinished feel, pipes on ceiling, dryer vent),
small barred window with dirty glass, outside: dark soil/grass + faint snow at ground level, moonlight.
Colliders: all walls (with door/window openings), knee wall/railing line, closed doors (toggle `collider.enabled` on
open/close; when the upstairs door is open its collider is disabled), stair side walls. Occluders: walls, doors, ceiling.
Handles `door.upstairs` (locked=true initially, hinge west, open angle −1.6 rad) and `door.closet` (hinge north, opens to +X).
`world.hideSpots.push({ id:'closet', door, ...CLOSET })`.
**Lighting.js**: warm ceiling-fan light (PointLight ~2700 K at the fan light kit, castShadow, intensity tuned for a dim
60 W bulb look — physically based units), faint cool moonlight SpotLight through the window (casts bar shadows on the
floor), warm door-strip light (small RectAreaLight or PointLight above the landing behind the door), TV light (cool,
flickering, only when TV on), very low HemisphereLight/ambient so pitch darkness is still readable on phones.
`bakeEnvironment()`: CubeCamera at room center (~1.4 m) + PMRemGenerator.fromCubemap → `scene.environment` for **power on**
and a darker one for **power off**; swap on `setPower`; tune `scene.environmentIntensity` (r170 property) — this gives
realistic bounce/reflections. `setPower(on)` ramps with a flicker when turning on. `blowout()` = bright flash + pop sfx
(`light_pop`) + off. `flicker()`, `setStress(v)` (entity nearby → flicker), `doorStrip.setOccluded(v)`.
Read shadow sizes from `game.renderer.preset` and react to `quality:changed`.

### Props (`props`)
Place every entry of `layout.PROPS` (fine-tune y so things sit exactly on surfaces; you may nudge positions ≤ 10 cm but keep
nav nodes/links clear). Colliders for furniture (`addColliderFromObject`, skip tiny props; pictures/frames none),
occluders for big furniture (sofa, dresser, console, clock, cabinet, shelves). Enable cast/receive shadows.
Handles: dresser drawers (GothicCommode door01=top, door02=mid, door03=bottom slide +Z local ~0.3 m), end table drawer,
alcove cabinet drawers (slide) & doors (rotate around their node origin / hinge), power box door (author OPEN → set closed at
build), procedural breaker lever inside the box (`powerBox.lever`), CheeseBox lid (hinge at back edge) + procedural brass
**4-wheel combination padlock** on the front (`lockedBox.lock`). Items: flashlight (`pastic_torch_6v`), batteries
(procedural cylinders, gold/black label), brass key (procedural, nice bevels, metal PBR), note papers (planes with canvas
text textures, slight curl), child drawing, newspaper clipping. The box lid carries the child's code note
("canard · cheval · horloge · télé" with little crayon doodles).
TV: emissive screen plane with an animated CanvasTexture (static noise + scanlines + rolling bar; digit flickering in the
static when `setDigit`), `setOn(on)` (needs world.power) → `lighting.setTVLight`, plays/stops `tv_static` loop.
Ceiling fan blades spin slowly when power is on (spin down when off). Grandfather clock: hands set by clue digit; it does
NOT tick (stopped) — the alarm clock on the coffee table ticks (second hand) and plays `clock_tick` loop.
`ProcTextures.js`: canvas generators — kids play rug (road map, 1.8×1.3 m, uses carpet normal map), several crayon kid
drawings taped on walls (one shows a tall long-haired woman: "MA GARDIENNE"), family photos in frames up the stairwell
(faded, one face scratched out), notes, newspaper, digit decals, TV static. Wait for fonts (`document.fonts.load`) with a
timeout fallback before drawing text.
Extra dressing for realism (procedural or model reuse): laundry basket, clothes on floor, toy blocks, crayons, electric
cable from the TV, outlet covers, light switch near the stairs, smoke detector, thermostat, wall stains/scuffs (decals),
dust. Keep total draw calls reasonable (< 250) and triangles < 400k.

### Player + Input (`player`)
Desktop: WASD/arrows, mouse look with pointer lock, Shift sprint, C/Ctrl crouch (toggle), E/left-click interact
(hold supported), F flashlight, Esc/P pause, Tab next. Touch: left-half dynamic virtual joystick, right-half drag to look,
buttons (bottom-right cluster, ≥ 56 px, safe-area aware): ✋ interact (large, highlights when `setInteractAvailable`),
flashlight, crouch toggle, sprint (hold), pause (top-right). Multi-touch correct (track touch identifiers). Sensitivity &
invertY from settings. Prevent page scroll/zoom. Show touch UI only when `isTouch` and state is playing.
Movement: walk 1.9 m/s, crouch 0.9, sprint 3.3 with stamina (4 s, regen after 1 s), acceleration/deceleration,
collision via `world.moveCircle` (radius 0.25, vertical span [feet+0.3, head]), floor via `world.groundHeightAt(x,z,y)`
with smooth stair stepping, eye height 1.62 / crouch 0.95 (smooth), head bob + subtle sway + breathing idle, camera roll
on strafe, landing dip on stairs. Footstep sfx per surface (`footstep_carpet`, `footstep_wood` for stairs/alcove) and
`noise` events per step. `player:bump` + noise when sprinting into furniture.
Flashlight: SpotLight child of the camera (slightly offset right/down, lags behind the view with smoothing), warm-white,
angle ~0.42 rad, penumbra 0.45, physically based intensity, decay 2, distance 18, castShadow when
`renderer.preset.shadowsFlashlight`; **cookie texture** (`light.map`, procedural canvas: hot center, ring, dark spots)
for a real-flashlight look; battery drains 100→0 in ~360 s while on, flickers below 15 %, dies at 0 (auto-uses a stored
battery from the inventory if any, with `battery_change` sfx). Optional: viewmodel of the torch (pastic_torch_6v) in the
bottom-right of the view when on.
Hiding: `enterHide(spot)`: opens `spot.door`, lerps camera to `hidePos` facing `hideYaw`, closes door; while hidden: limited
look (±50° yaw, ±30° pitch), no movement, renderer.setHiddenView(1), ui.setHidden(true), subtle breathing. `exitHide()`
reverses to `exitPos`. `getVisibility()`: 0 when hidden; else based on flashlight on (1.0), power on & standing (0.7),
dark (0.35), crouched ×0.5.
`updateIdleCamera(dt)`: slow cinematic camera drift in the room for the menu background.
Debug: `params.cam` → teleport at init.

### Gameplay (`gameplay`)
Interaction: camera-center raycast (max 2.1 m) against registered objects + occluders (first hit wins), prompt via
`ui.setPrompt(text, {hold})` with key hint (desktop "E" / touch "✋"), `input.setInteractAvailable`, hold-to-interact.
Inventory: items flashlight / battery (count) / key with French names and simple inline SVG icons; notes list.
Puzzles: the full scenario of §5, all interactables (drawers/doors toggle with noise; items pickup → hide object + inventory
+ `pickup`/`key_pickup` sfx; notes → `game.modal(() => ui.showNote(...))`; clues → subtitle + `ui.setClues`; keypad →
`game.modal(() => ui.showKeypad(...))`; TV toggle (requires power; noise while on); upstairs door (locked / key hold / win);
closet hide/exit; window ("Trop petite… et il y a des barreaux."); rocking chair beat; random ambient scares (house creaks,
distant footsteps upstairs) via audio). Code: 4 random digits 1–9 generated on new game; `world.setClueDigits`.
`reset('caught')`: close drawers? (no — keep world state), ensure stage consistency (e.g. if the entity was summoned, objective
returns to the right text). Debug: `?stage=power|code|escape` via `debugGoto`.

### Gardienne (`entity`)
Original creature: "La Gardienne", a former babysitter. Very tall (≈1.98 m), unnaturally thin, stooped; long matted black hair
hiding most of the face; grey-pale skin; stained off-white nightgown to the shins; bare feet; overly long arms and fingers.
Build procedurally in `GardienneModel.js` (no external assets): hierarchical skeleton of Object3D pivots (pelvis, spine, chest,
neck, head, shoulders/elbows/wrists, hips/knees/ankles) with smooth geometry (Lathe/Tube/Capsule with noise displacement, skin
material with subsurface-ish sheen via MeshPhysicalMaterial sheen/transmission off, hair as many thin curved tube/ribbon
strands with alpha, gown as a lathe with folds + vertex noise, cloth-like sway). Face (seen in the jumpscare): pale, sunken dark
eye sockets with tiny glinting pupils, too-wide mouth. Procedural animation: slow heavy walk with occasional jerky twitches
(head snaps, frame-skip "glitch" moves), searching pose (head tilting, listening), fast predatory chase gait, crawling NOT needed.
AI: states `dormant` (upstairs, invisible; suspicion accumulates from `noise` scaled by distance/upstairs muffling; random
patrol visits every 90–180 s after the first scripted visit; aggression raises frequency), `waking` (footsteps on the ceiling
moving toward the door 2–4 s, `ceiling_steps`), `descending` (upstairs door unlocks/opens via `world.handles['door.upstairs']`
— keep its `locked` flag as it was for the player —, walks down the stairs, door left open), `searching` (goes to the noise
position, then 3–5 random nodes nearby, pauses, head tilts, hums `lullaby_hum`; checks the closet if she saw the player enter →
opens it → caught), `chasing` (when she sees the player: FOV 110°, range by `player.getVisibility()` (×12 m), LOS via
`world.lineBlocked`; direct pursuit when `segmentBlocked` is false else A* path; speed 2.9 m/s vs player sprint 3.3; loses the
player after 4 s without LOS → searching last known position), `returning` (back up the stairs, closes the door, `dormant`),
`jumpscare` (within 0.85 m + LOS: takes control of the camera via `player.cameraOverride = true`, snaps the camera to look at her
face 0.45 m away, scream `jumpscare`, `renderer.flash`, `shake`, ~1.4 s, then emits `entity:caught`).
Movement via `world.moveCircle` (radius 0.3) + `groundHeightAt`. `fear` = f(distance, LOS, state). Drive
`world.lighting.setStress(…)` when within ~5 m, `doorStrip.setOccluded` while she is behind the door, positional audio
(`entity_step`, `entity_step_stairs`, `lullaby_hum` loop, `entity_breath`). Never stuck: repath every 0.7 s, teleport-free
unstick fallback (step back + pick another node). `?noentity` disables her.

### Audio (`audio`)
Procedural Web Audio only (noise buffers, oscillators, filters, convolver reverb generated from decaying noise for a small
basement room). Master → compressor → destination. Listener follows `game.camera` each frame. Positional sounds via
PannerNode (HRTF, inverse distance, refDistance ~1). Sounds (all required; realistic, not cartoonish):
`ambience` (room tone: low brown noise + faint furnace rumble), `light_buzz` (loop, 60 Hz hum when power on), `fan_hum`,
`clock_tick` (loop, alarm clock), `house_creak`, `ceiling_steps` (heavy slow steps above, positional), `footstep_carpet`,
`footstep_wood`, `entity_step`, `entity_step_stairs`, `entity_breath`, `lullaby_hum` (loop: eerie hummed French lullaby melody
— "Au clair de la lune" first phrase — wobbly, breathy formant-like voice via filtered saw/noise, positional),
`door_creak_open`, `door_close`, `door_locked` (rattle), `unlock`, `drawer_open`, `drawer_close`, `cabinet_open`,
`cabinet_close`, `breaker_flip` (heavy clunk), `power_up` (hum swell), `light_pop` (bulb pop + tinkle), `flashlight_click`,
`battery_change`, `pickup`, `key_pickup` (metallic jingle), `paper` (rustle), `box_open`, `lock_wheel` (tick), `lock_fail`,
`lock_success`, `tv_static` (loop, loud), `tv_off` (crt pop/whine down), `rocking_chair` (slow wood creak loop),
`closet_enter`, `closet_exit`, `bump`, `heartbeat` (driven by fear), `stinger` (spotted), `chase_music` (loop: pulsing low
strings/noise while chasing), `jumpscare` (loud harsh layered scream), `whisper` (unintelligible breathy whisper), `win_door`.
`setFear(v)`: heartbeat rate/volume + sub drone. Listen to `entity:state` for chase music, `power` for buzz/fan.
Respect `settings.volume`. Must not crash before `unlock()` (queue or ignore). iOS: resume context on first touch.

#### Recorded sample library (priority over procedural synthesis)
`assets/audio/manifest.json` maps every engine sound name → `{ files: [repo-relative mp3 paths], loop, gainDb }`
(63 sounds, 146 files, real CC0 foley recordings — mostly the Red Library collection; see assets/audio/CREDITS.md).
The engine must fetch the manifest (path relative to the page: `./assets/audio/manifest.json`), lazily `fetch` +
`decodeAudioData` the buffers (decode the small/critical ones right after `unlock()`, the rest in the background),
pick a random variation per play (never the same twice in a row), apply `gainDb`, small random pitch (±3 %) and volume
(±2 dB) jitter for one-shots, and loop seamlessly for `loop: true`. Procedural synthesis stays as the FALLBACK when a
sample is missing or not decoded yet. Extra names available in the library beyond the list above: `footstep_concrete`
(laundry nook floor), `stair_creak`, `cloth_move`, `land_thump`, `ceiling_walk`, `window_tap`, `tv_on`, `clock_chime`,
`furnace`, `room_tone`, `entity_croak`, `giggle`, `knock_wall`, `player_breath_run` (loop, sprint exhaustion),
`player_breath_scared` (loop, hiding / entity near), `player_gasp`, `heartbeat_fast`, `heartbeat_single`,
`ambience_drone`, `wind_outside`. Ceiling/upstairs sounds must be muffled (lowpass ~600 Hz) and positioned above the
ceiling; sounds behind the closed upstairs door are lowpassed until it opens (occlusion), and sounds in the laundry nook
get a slightly different reverb. Mix for headphones: ducking of ambience under stingers/jumpscare, a limiter on the master.

### UI (`ui`)
Distinctive, restrained horror UI (not generic): title "La Gardienne" scrawled in Rock Salt like a child's crayon on aged
paper, subtitle "Chapitre 1 — Le sous-sol" in Special Elite. Main menu over the live 3D scene (darkened): Jouer, Options
(qualité Auto/Basse/Moyenne/Haute/Ultra, sensibilité, inverser Y, luminosité, volume, sous-titres, champ de vision),
Contrôles (clavier + tactile), "Joue avec des écouteurs 🎧" (no emoji — use a small SVG icon), landscape hint on portrait phones,
fullscreen toggle on mobile (optional, handle rejection). Loading screen with progress bar. HUD: tiny crosshair dot → hand
glyph when interactable, prompt text under it with key hint + hold ring, objective top-left (typewriter appear), subtitles
bottom center (readable on phones, max 2 lines), night indicator "Nuit 1/3" (top-right, small), inventory slots bottom-right
(desktop) / above the touch buttons (mobile), flashlight battery meter, stamina bar (only when < 100 %), clue carnet
(4 slots with tiny icons: canard, cheval, horloge, télé). Modals: note reader (paper texture via CSS gradients, Caveat
handwriting, child style with crayon colors, newspaper style), keypad (4 rotating digit wheels, tap/scroll/arrow keys,
"Essayer", "Annuler"), pause (Reprendre, Options, Contrôles, Quitter → reload), caught screen ("Elle t'a trouvé." + Nuit 2/3 +
Continuer), game over, win screen (time, nights). All modals keyboard + touch friendly. `fadeTo` black overlay. Safe-area
insets everywhere. French text only.

## 7. Testing

`THREE_DIR=<path to node_modules/three> node tools/shot.cjs --query "autostart&debug&cam=x,y,z,yawDeg,pitchDeg" --out f.png --wait 4000 [--eval "code"] [--mobile]`
serves the repo, loads the game in headless Chromium (software WebGL), prints console/page errors, saves a screenshot.
`window.__game` is the Game instance. Yaw 0 looks north (−Z), positive yaw turns left (toward −X... i.e. standard three.js
YXZ: yaw +90° looks toward −X). Use `--steps steps.json` for scripted sequences. Software WebGL is slow (~5–20 fps with full
post) — judge visuals from screenshots, not speed. Check `node --check` on your files.
