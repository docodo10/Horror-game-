# Player module (Godot 4.5.1) — port of `src/player/Player.js` + desktop/gamepad `src/core/Input.js`

`player.gd` is a `CharacterBody3D` (Jolt). Public API and signals are listed in its header (stub API kept, extras added).
`flashlight_cookie.gd` generates the flashlight projector cookie (same seeded pixels as the web `makeCookieTexture`).

## How it maps to the web version
| web (`Player.js`) | Godot |
|---|---|
| `world.moveCircle` 2D sliding collision, `groundHeightAt` | `move_and_slide()` on the world colliders; on the stair **ramp** the velocity is made tangent to the floor so the horizontal speed is exactly the web's (walk 1.9 × 0.8); `floor_snap_length` 0.35; a step-up (≤ 0.3 m, the web's collision clearance) handles box treads, thresholds and low clutter |
| camera `_y1/_y2` filter on tread heights | same filter; on the stairs footprint the **Layout tread heights** feed it, so the smooth ramp still reads as steps |
| `update(dt)` once per frame | movement / stamina / beam ray in `_physics_process` (60 Hz); look, POV rig, footsteps, flashlight in `_process`; the camera uses the body position **interpolated between physics ticks** (smooth on 144 Hz+) |
| pointer-lock mouse deltas × 0.0022 rad/px | raw `InputEventMouseMotion.screen_relative` × 0.0022 × sensitivity (no smoothing / clamping; 2 frames ignored after capture) |
| touch joystick / look pad | gamepad: left stick move, right stick look (deadzone 0.14, response curve 1.8, 2.7 rad/s yaw + turn boost), L3 = sprint toggle, rumble on bump / flinch / landing |
| three.js SpotLight 42 cd, decay 2, angle 0.42, penumbra 0.45, `map` cookie | `SpotLight3D` energy 42/π (Godot multiplies by π and its Lambert divides by π — measured), `spot_attenuation` 2, `light_projector` cookie with the three.js penumbra baked in and a flat cone (`spot_angle_attenuation` 0.05) |
| `renderer.setHiddenView` | `Quality.set_hidden_view(v)` (called only if the look module defines it) |

## Godot 4.5.1 findings (measured with lavapipe probes)
* A `SpotLight3D.light_projector` renders **only while the light casts shadows**; without shadows the light is black.
  The torch therefore keeps `shadow_enabled` on every quality preset. If a preset ever disables positional shadows
  globally, call `Game.player.set_flashlight_shadows(false)`: the cookie is dropped and replaced by an equivalent cone falloff.
* Projector textures are sampled from the **sRGB** decal atlas: the cookie stores sRGB-encoded values of the web's linear cookie.
* Light energy: Godot's non-physical units carry an extra ×π (energy 2 at 2 m on a white Lambert wall = 0.497 linear).
* Spot cone falloff is `1 - rim^(1 / spot_angle_attenuation)` (rim = (1-cos a)/(1-cos angle)): LARGER values make the
  beam dimmer and peakier (12 gives only 53 % on the axis); a flat cone needs a small value (0.05).

## Tests
```
# scripted movement test (59 checks: walk/sprint/FOV/stamina/crouch/stairs/nook/bump/look/hide/flashlight/fear/visibility)
godot --headless --fixed-fps 60 --path pc -s res://scripts/player/tests/movement_test.gd
# player inside the real game flow (menu idle camera, menu->game blend, pause, caught -> reset_after_caught)
godot --headless --fixed-fps 60 --path pc -s res://scripts/player/tests/main_flow_test.gd
# sandbox (test world from Layout: ramp stairs, nook, closet + Handle door, real furniture); renders with DebugTools args
godot --path pc res://scripts/player/tests/sandbox.tscn -- --autostart --player-log
xvfb-run ... godot --path pc --rendering-driver vulkan res://scripts/player/tests/sandbox.tscn -- --shots=/abs/prefix \
  --views=spawn,kids,stairs,nook,landing --flashlight --power=off --quality=high
# several custom views in one renderer run (torch on; per view: power on|off, battery):
#   ... sandbox.tscn -- --no-fog --player-shots=/abs/prefix --shot-frames=36 \
#       --player-cams="dresser:-0.55,0,-0.45,0,-12:off|lowbat:-0.55,0,-0.45,8,-12:off:bat=7|lit:2,0,1.45,49,-4:on"
```
Debug args (game or sandbox): `--battery=N`, `--player-stress=0..1`, `--crouch`, `--player-log`.
