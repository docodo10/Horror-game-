# Automated tests & screenshot sets

Three tools, all headless Chromium (Playwright) with **software WebGL** (SwiftShader). They serve the repo
themselves (no web server needed) and can load three.js from a local package instead of the CDN:

```bash
export THREE_DIR=/path/to/node_modules/three   # optional but recommended (offline, faster); must be three@0.170.0
```

| Tool | What it is for |
|---|---|
| `tools/shot.cjs` | one screenshot or a scripted sequence (`--steps file.json`) — owned by the lead |
| `tools/playtest.cjs` | end-to-end playthrough: walking, the whole scenario, the entity, the caught flow → JSON report |
| `tools/shots/*.json` | ready-made step sets for `shot.cjs`: canonical views, dark views, the entity, every UI screen |

Software GL is slow (1–20 fps depending on machine load). Everything below measures time in **game seconds**
(`game.realTime`, whose frame delta is clamped to 50 ms), so the tools stay correct on a slow machine — they just
take longer. Use `--size 960x540` (or smaller) and `quality=low` while iterating.

---

## 1. `tools/playtest.cjs` — automated playthrough

```bash
THREE_DIR=$THREE_DIR node tools/playtest.cjs > report.json                       # walk + story (entity disabled)
THREE_DIR=$THREE_DIR node tools/playtest.cjs --all --size 960x540 --out /tmp/pt.json > /dev/null
THREE_DIR=$THREE_DIR node tools/playtest.cjs --scenario story --entity            # story with her visit after the breaker
THREE_DIR=$THREE_DIR node tools/playtest.cjs --scenario caught --gameover         # caught flow nights 2, 3 + game over
THREE_DIR=$THREE_DIR node tools/playtest.cjs --mobile --scenario walk,story       # phone: touch joystick + ✋ button
THREE_DIR=$THREE_DIR node tools/playtest.cjs --scenario story --from door         # re-test only the end (?stage=escape)
node tools/playtest.cjs --help
```

`--from start|breaker|clues|keypad|door` starts the story at a checkpoint: it adds the gameplay debug param
`&stage=intro|power|code|code|escape` and skips the earlier steps (the stage sequence check starts there too).
`--max-minutes` (default 90) is a hard wall-clock limit: when it is hit the running session is still exported and
the report written.

Progress goes to **stderr** (`PASS/FAIL/WARN id — message`), the final **JSON report to stdout** (and `--out FILE`).
Exit code `1` if any check failed (`--allow-stubs`: only failures *not* explained by a stub module count), `2` if
the harness itself crashed.

### Scenarios (each one is a fresh page load of `index.html?debug&autostart&quality=<q>[&noentity]`)

* **walk** — real keyboard input (`KeyW` held; on `--mobile` a CDP touch drag on the left half = the virtual
  joystick, falling back to `KeyW`). The yaw is steered toward the next waypoint through `player.yaw` (a wrapper
  around `player.update`). Route (nav-graph nodes from `layout.NAV_NODES`): spawn → coffee table (`sofaFront`) →
  dresser (`tvFront`) → stairs bottom → **landing** (y must be 2.75) → back down → **laundry nook** through its
  doorway (`alcoveEast`) → console (`consoleFront`). Arrival = within 0.3 m. When the player makes no progress for
  1.5 s (game) the report lists the **blocking colliders** (tag + box) and whether `world.segmentBlocked` agrees,
  then teleports to the waypoint and continues. Also reports walking speed (spec 1.9 m/s) and arrival heights.
* **story** — the full scenario through the Interaction API. Every step finds its entry in
  `game.interaction.entries` by **target object** (`world.items.*`, `world.handles[*].object`, `world.clues.*`,
  `world.tv.object`, the closet door), then id regex, then prompt text; teleports next to it (a free spot near a
  stand point), aims the camera at the object's bounding box and waits until `interaction.current` is that entry,
  then presses **E** (held for `entry.hold` seconds; ✋ touch button on mobile). If the aim never selects the entry
  it falls back to `interaction.activate(id, {force})` / `entry.onInteract()` and reports a WARN. Steps:
  note 1 → stage `dark` + power off → dresser drawer → flashlight (`has && on`) → stage `power` → panel door →
  lever (power on, noise 1.0, `ui.alert('CACHE-TOI !')`, `entity.summon` called) → hide in the closet / leave it →
  stage `code` → duck, horse, clock, TV (each `puzzles.found[k] === code[i]`) → TV off → `ui.setClues` → note 2,
  end-table drawer + battery, cabinet drawer + battery, cabinet door + note 3 (3 notes in the inventory) → the box
  note → keypad with a **wrong** code (rejected) then the **right** code (box opens) → key → stage `escape` →
  upstairs door (hold) → walk through → **`game:win`** + state `won` + `ui.showWin`. Finally the stage sequence
  `intro → dark → power → code → escape` (+ won) is asserted, and a heuristic flags non-French player text.
  With `--entity` she is enabled: after the breaker the player hides and her **state timeline** is logged
  (`entity.visit.wakes / descends / searches / returns / hiddenSafe`); before later steps, if she is active, the
  player hides again until she is dormant.
* **caught** (entity enabled) — gives the flashlight + a battery, `entity.summon()`s her to the player, waits until
  she is in the basement, places the player 1.5 m in front of her (facing her, LOS checked), waits for the
  jumpscare and `entity:caught`, clicks **Continuer** on the caught screen, then checks the reset for night 2 and
  night 3: state `caught → playing`, `game.night`, `ui.showCaught({night, nightsTotal})`, respawn at
  `layout.SPAWN`, not hidden, `cameraOverride === false`, `player.enabled`, entity `dormant`/inactive, inventory +
  stage kept. `--gameover` adds a third catch (state `gameover`, `ui.showGameOver`). If she never comes down /
  never catches, `entity:caught` is emitted manually so the Game reset flow is still tested (reported as FAIL for
  the entity part).

Before the first scenario a **contract check** verifies every documented public member (ARCHITECTURE.md),
the 14 handles, 7 items, 4 clues, the lever, the closet hide spot (and that its `door` really is the Handle),
`world.tv`, `puzzles.code` format and that interaction entries exist. Each session also reports page errors,
`console.error`s, failed requests (benign `ERR_ABORTED`s after a full download are counted separately), fps samples
(software GL), scene stats (meshes, triangles, lights, quality preset), the event log, the objective/alert/subtitle
texts, every prompt seen, every modal shown, loud noises, and stages forced.

### Reading the report

```jsonc
{
  "modules": { "gameplay": "stub", "player": "real", … },     // from the "// STUB" headers
  "checks": [ { "id": "interact.flashlight", "status": "fail", "msg": "…", "scenario": "story",
                "explainedByStubs": ["gameplay"], "details": { … } } ],
  "sessions": [ { "name": "story", "stages": […], "entityTimeline": […], "walk": { "legs": [ { "stuck": [ { "blockers": … } ] } ] },
                  "errors": {…}, "fps": {…}, "modals": {…}, "texts": {…}, "interactionEntries": […], "forcedStages": […] } ],
  "summary": { "ok": false, "pass": 40, "fail": 3, "failExplainedByStubs": 2, "failUnexplained": 1, "failures": [ "…" ] }
}
```

* `explainedByStubs` — the check depends on a module that still has its `// STUB` header (expected before merge).
* When a stage is not reached the harness calls `puzzles.debugGoto(stage)` and continues (`--no-force` disables it);
  the stage check stays FAIL and `forcedStages` records it. A missing interaction entry uses a documented-API fallback
  (`handle.open()`, `player.giveFlashlight()`, `world.setPower(true)`, …) recorded in `forcedActions`.
* `--shots DIR` saves a screenshot at every waypoint and story step (aim, note, keypad, after) — handy to see
  *why* an aim failed.

### Test-harness accommodations (all reported in `harness`)

* `input:pointerlock {locked:false}` events are swallowed (headless Chromium can never hold pointer lock, Game would
  pause); unexpected `paused` states are auto-resumed.
* `ui.showNote/showKeypad/showCaught` get passthrough wrappers: the real UI is shown and closed with its own buttons
  (Fermer/Continuer/OK…, clicked with the mouse or tapped); the wrapper only resolves the promise if no button works
  (reported FAIL). Keypad digits are injected through the `showKeypad` promise (the wheels are not driven), then the
  real keypad is closed with **Annuler**. `ui.showWin/showGameOver` are held open (Game would reload the page).
* `ui.setObjective/subtitle/alert/setClues/setHidden/setPrompt` and `entity.summon` are tapped (passthrough) to record
  calls.

---

## 2. Screenshot sets — `tools/shot.cjs --steps tools/shots/<set>.json`

Run from the **repo root** (the sets write to `shots/<set>/…`, which is git-ignored). Each set starts by installing
small helpers (`window.__qaCam(x, y, z, yawDeg, pitchDeg, fov)`, `__qaLight(power, flashlight)`,
`__qaWaitGame(s)`, `__qaClick(regex)`, `__qaFreeze()` — freezes `puzzles.update` so no blowout/scare interferes,
`__qaCloset()`), then every view is: lights → wait (game time) → exact camera (`player.teleport` +
`player.cameraOverride = true` + camera transform) → screenshot.

```bash
# canonical views, power on (+ breaker/window shots in the dark)
THREE_DIR=$THREE_DIR node tools/shot.cjs --query "autostart&debug&noentity&quality=high" --steps tools/shots/tour.json --size 1280x720
# the same views after the blowout, flashlight on
THREE_DIR=$THREE_DIR node tools/shot.cjs --query "autostart&debug&noentity&quality=high" --steps tools/shots/dark.json --size 1280x720
# the entity (NO noentity!): arrival at the stairs, under the ceiling light, in the flashlight beam, by the stairs,
# staged jumpscare frame (camera 0.45 m from her face, flash/shake), live jumpscare (best effort)
THREE_DIR=$THREE_DIR node tools/shot.cjs --query "autostart&debug&quality=high" --steps tools/shots/entity.json --size 1280x720
# every UI screen (NO autostart: starts on the menu) — desktop, then phone
THREE_DIR=$THREE_DIR node tools/shot.cjs --query "debug&noentity" --steps tools/shots/ui.json --size 1280x720
THREE_DIR=$THREE_DIR node tools/shot.cjs --query "debug&noentity" --steps tools/shots/ui-mobile.json --mobile
```

| Set | Shots |
|---|---|
| `tour.json` → `shots/tour/` | 01 spawn view toward the TV · 02 stairs from the south-east (fov 80) · 03 kids corner · 04 console + locked box · 05 dresser top drawer open with the flashlight · 06 grandfather clock face · 07 laundry nook through its doorway · 08 breaker panel open (power off, flashlight) · 09 landing looking down the stairs · 10 upstairs door from the stairs · 11 window with moonlight (power off) · 12 closet hide view (`player.enterHide`) |
| `dark.json` → `shots/dark/` | `lighting.blowout()` then the same 12 views with power off + flashlight on |
| `entity.json` → `shots/entity/` | 01 she comes down after `entity.summon()` (seen from the kids corner) · 02 under the ceiling light · 03 in the flashlight beam (power off) · 04 by the stairs in the dark · 05 staged jumpscare frame · 06 live jumpscare. From 02 her AI is frozen (`entity.update` replaced) and she is placed via `entity.position` / `entity.root`; 06 restores it. |
| `ui.json` → `shots/ui/desktop-*` · `ui-mobile.json` → `shots/ui/mobile-*` | 01 menu · 02 options · 03 controls · 04 in-game HUD (objective, carnet 2/4, inventory, battery, stamina, subtitle, prompt on the dresser drawer; touch controls on mobile) · 05 note · 06 child drawing · 07 newspaper · 08 keypad · 09 pause · 10 caught (night 2/3) · 11 game over · 12 win |

Each `[eval]` line printed by `shot.cjs` says what happened (e.g. `FALLBACK camera at hidePos: player.enterHide
did not move the camera (stub?)`, `no visible button /…/`, `she came down: false`). Look at the PNGs with an image
viewer; the views are fixed so before/after comparisons are meaningful. Tune a view by editing its `__qaCam(...)`
arguments (yaw 0 = north/−Z, +90 = west/−X; pitch + = up).

---

## 3. Tips

* Never leave Chromium running; both tools close it (Ctrl-C kills it too).
* Runtime ≈ game time × (20 / fps). A full `story` is ~2–3 min of game time: a few minutes on an idle machine, but
  close to an hour on a saturated one (1 fps). The playtest polls once per rendered frame to stay light.
  `--size 640x360` / `480x270` and `quality=low` make it much faster and do not change the logic.
* Slow or loaded machine: `--timeout-scale 2` (playtest) and a larger `--max-minutes`. A page that renders no frame
  for 60 s is reported as stalled. `shot.cjs` keeps Playwright's 30 s screenshot timeout: on a saturated machine a
  screenshot can time out — rerun when the machine is idle.
* Debug a single failing step: `--scenario story --shots /tmp/pt-shots --verbose` (page console echoed).
* `?stage=power|code|escape` and `?code=1234` (gameplay debug params) can be passed with `--query` to start later
  in the story; the stage checks before that stage will then fail by design.
