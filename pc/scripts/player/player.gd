## Player module (ARCHITECTURE_PC.md §Player) — port of src/player/Player.js + the desktop/gamepad half of src/core/Input.js.
## First-person CharacterBody3D (Jolt): raw mouse look + gamepad look (response curve, turn boost), walk / crouch / sprint
## with stamina and exhaustion, stairs (world ramp collider + floor snap + tangent velocity, step-up for small ledges, the
## camera eased tread by tread like real steps), per-surface footsteps + Events.noise, bump noise, and the horror POV rig:
## head bob synced to the footfalls (sharp foot-strike low + lateral figure-8), sprint FOV kick and forward lean, strafe roll,
## breathing (calm / scared / exhausted / hidden), fear tremor (Game.fear), flinches (entity spotted, loud noises, blackout),
## stair/landing dips, crouch dip. The camera is written every rendered frame from the body position interpolated between
## physics ticks (smooth on 144 Hz+ monitors). Flashlight: SpotLight3D with a procedural projector cookie, lag spring, hand
## sway/tremor, battery drain/flicker/death/auto swap, real shadows, one-bounce fill light at the beam's hit point.
##
## Public API (keep): camera: Camera3D, yaw, pitch, crouched, sprinting, stamina, hidden, hide_spot, enabled, camera_override,
##   flashlight: {has, on, battery, light: SpotLight3D}; give_flashlight(); set_flashlight_on(on); add_battery(amount := 60.0)
##   enter_hide(spot) / exit_hide() (await); respawn(); teleport(pos: Vector3, yaw: float, pitch := 0.0); get_visibility() -> float;
##   eye_position() -> Vector3; flinch(strength := 1.0); reset_after_caught()
## Extra public members:
##   moving, speed (horizontal m/s), exhausted, on_stairs, surface ("carpet"|"wood"|"concrete"), breath 0..1, stress 0..1,
##   eye_height, radius, using_gamepad, flashlight_energy_scale (look module may tune the torch), set_crouch(on), is_in_alcove(),
##   update_idle_camera(delta) (menu fallback while the UI does not own the camera), hide_busy() -> bool,
##   set_flashlight_shadows(on) (keep on: Godot 4.5 renders a spot projector only with shadows; off swaps the cookie for an
##   equivalent cone falloff)
## Emits: Events.noise(feet, loudness, "player"), Events.player_flashlight(has, on, battery), Events.player_stamina(value,
##   exhausted, breath), Events.player_hide(hidden, spot_id), Events.player_bump(tag).
## Listens: Events.entity_spotted (flinch + gasp), Events.noise (startle), Events.power_changed (flinch on blackout),
##   Events.game_state (menu -> game camera blend), Events.settings_changed (quality, sensitivity, invert_y, fov, camera_motion).
## Calls (if present): Game.ui.subtitle/set_hidden/is_modal_open/menu_camera_active, Game.inventory.remove("battery"),
##   Quality.set_hidden_view(v) (closet slats), Game.world.ground_height_at / power, Audio.play.
## Debug args (after --): --battery=N  --player-stress=0..1  --crouch  --player-log
extends CharacterBody3D

const Cookie := preload("res://scripts/player/flashlight_cookie.gd")

# ---------------------------------------------------------------- tuning (web values from src/player/Player.js)
const WALK := 1.9
const CROUCH := 0.9
const SPRINT := 3.3
const EXHAUSTED_SPEED := 1.15
const EYE_STAND := 1.62
const EYE_CROUCH := 0.95
const RADIUS := 0.25
const HEIGHT_STAND := 1.75
const HEIGHT_CROUCH := 1.12
const STAMINA_TIME := 4.0
const REGEN_DELAY := 1.0
const BATTERY_LIFE := 360.0                 # seconds from 100 % to 0 while on
const HIDE_YAW := 0.8726646                 # ±50° look while hidden
const HIDE_PITCH := 0.5235988               # ±30°
const PITCH_LIMIT := 1.42
const LOOK_RAD_PER_PX := 0.0022             # mouse: radians per pixel at sensitivity 1 (web Input.LOOK_RAD_PER_PX)
const PAD_DEADZONE := 0.14
const PAD_CURVE := 1.8                      # stick response exponent (precision near the center)
const PAD_YAW_RATE := 2.7                   # rad/s at full deflection (x sensitivity)
const PAD_PITCH_RATE := 1.75
const PAD_TURN_BOOST := 0.7                 # extra yaw speed after holding the stick fully out
const GRAVITY := 9.8
const STEP_HEIGHT := 0.3                    # = the web's 0.3 m collision clearance above the feet
const ABS_SIN_MEAN := 0.63661977            # 2 / PI

# physics layers (scripts/world/world.gd)
const LAYER_WORLD := 1
const LAYER_PLAYER := 4

# noise loudness table (ARCHITECTURE.md §4)
const LOUD := {"crouch": 0.03, "carpet": 0.10, "concrete": 0.10, "wood": 0.18, "sprint": 0.45, "bump": 0.3, "click": 0.02, "land": 0.3}
const STEP_SFX := {"carpet": "footstep_carpet", "wood": "footstep_wood", "concrete": "footstep_concrete"}

# flashlight: three.js SpotLight(0xfff0dc, 42 cd, 18 m, 0.42 rad, penumbra 0.45, decay 2), camera-local offset right/down.
# Godot (non-physical units) multiplies energy by PI and its Lambert BRDF divides by PI: 42 cd <=> 42 / PI.
const FLASH_COLOR := Color(1.0, 0.941176, 0.862745)
const FLASH_COLOR_LOW := Color(1.0, 0.701961, 0.419608)
const FLASH_ENERGY := 13.37
const FLASH_RANGE := 18.0
const FLASH_ANGLE := 0.42
const FLASH_PENUMBRA := 0.45
const FLASH_POS := Vector3(0.15, -0.16, 0.02)
const BOUNCE_COLOR := Color(0.941176, 0.815686, 0.666667)
const CONE_FLAT := 0.05                     # 1 - rim^20: flat to ~90 % of the cone (cookie shapes the beam)
const CONE_PENUMBRA := 0.4                  # 1 - rim^2.5: ~ three.js penumbra 0.45 when the cookie is unavailable

# ---------------------------------------------------------------- public state
var camera := Camera3D.new()
var yaw := 0.0
var pitch := 0.0
var enabled := true
var camera_override := false
var hidden := false
var hide_spot = null
var crouched := false
var sprinting := false
var stamina := 1.0
var flashlight := {"has": false, "on": false, "battery": 100.0, "light": SpotLight3D.new()}

var moving := false
var speed := 0.0
var exhausted := false
var on_stairs := false
var surface := "carpet"
var speed_scale := 1.0          # external slowdown (garderie ball pit: 0.55)
var breath := 0.0
var stress := 0.0
var eye_height := EYE_STAND
var radius := RADIUS
var using_gamepad := false
var flashlight_energy_scale := 1.0

# ---------------------------------------------------------------- internals
class Spring:
	## Damped spring (semi-implicit Euler, sub-stepped for stability).
	var x := 0.0
	var v := 0.0
	func _init(x0 := 0.0) -> void:
		x = x0
	func step(target: float, omega: float, zeta: float, dt: float) -> float:
		var n := 1
		if dt > 0.016:
			n = ceili(dt / 0.016)
		var h := dt / n
		for i in n:
			var a := -2.0 * zeta * omega * v - omega * omega * (x - target)
			v += a * h
			x += v * h
		return x
	func reset(x0 := 0.0) -> void:
		x = x0
		v = 0.0

var _light: SpotLight3D
var _cookie: ImageTexture
var _bounce: OmniLight3D
var _shape: CapsuleShape3D
var _shape_node: CollisionShape3D
var _kc := KinematicCollision3D.new()
var _ray := PhysicsRayQueryParameters3D.new()
var _floor_min_y := 0.64

var _t := 0.0
var _hvel := Vector2.ZERO                  # intended horizontal velocity (x, z)
var _phys_prev := Vector3.ZERO             # body position at the previous / current physics tick (camera interpolation)
var _phys_cur := Vector3.ZERO
var _was_on_floor := true
var _air_top := 0.0
var _ground := 0.0                         # visual ground (tread heights on the stairs)
var _y1 := 0.0
var _y2 := 0.0
var _eye := Vector3.ZERO
var _eye_spring := Spring.new(EYE_STAND)
var _dip := Spring.new()
var _f_pitch := Spring.new()
var _f_yaw := Spring.new()
var _f_roll := Spring.new()
var _f_y := Spring.new()
var _f_fov := Spring.new()
var _stamina_delay := 0.0
var _sprint_time := 0.0
var _exhaust_t := 0.0
var _hunch := 0.0
var _last_stamina_q := -1
var _last_exh := false
var _last_breath_q := -1
var _phase := 0.5
var _step_idx := 0
var _bob_amp := 0.0
var _move_blend := 0.0
var _breath_ph := 0.0
var _sprint_blend := 0.0
var _strafe_roll := 0.0
var _strafe_vel := 0.0
var _bump_cd := 0.0
var _flinch_cd := 0.0
var _noise_src_t := {}
var _free_eye_y := NAN
var _eye_override_y := NAN
var _hide_busy := false
var _hide_gen := 0
var _hidden_view := 0.0
var _hidden_view_sent := -1.0
var _want_stand := false
# camera fx outputs
var _o_r := 0.0
var _o_u := 0.0
var _o_f := 0.0
var _o_pitch := 0.0
var _o_yaw := 0.0
var _o_roll := 0.0
var _fov := 72.0
var _bob_v := 0.0
var _bob_l := 0.0
var _trem_hand := 0.0
var _trem_hand2 := 0.0
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _prev_cam_yaw := 0.0
var _prev_cam_pitch := 0.0
# flashlight lag / flicker / bounce
var _lag_yaw := 0.0
var _lag_pitch := 0.0
var _lag_yaw_v := 0.0
var _lag_pitch_v := 0.0
var _fl_mul := 0.0
var _flick_on := false
var _flick_t := 2.0
var _flick_j := 0.0
var _flick_lvl := 1.0
var _die_t := 0.0
var _swap_dark := 0.0
var _last_battery_int := 100
var _flash_lin := Color()
var _flash_low_lin := Color()
var _beam_t := 9.0
var _bounce_pos := Vector3.ZERO
var _bounce_init := false
var _bounce_scale := 1.0
# hide animation
signal _anim_finished
var _anim_active := false
var _anim_from := Vector3.ZERO              # (x, eye y, z)
var _anim_to := Vector3.ZERO
var _anim_yaw0 := 0.0
var _anim_dyaw := 0.0
var _anim_pitch0 := 0.0
var _anim_pitch1 := 0.0
var _anim_dur := 0.5
var _anim_time := 0.0
var _anim_mid := Callable()
var _anim_mid_done := false
# menu -> game camera blend
var _idle_shown := false
var _idle_t := 12.0
var _blend_t := 1.0
var _blend_pos := Vector3.ZERO
var _blend_q := Quaternion.IDENTITY
var _blend_fov := 72.0
# input
var _look_dx := 0.0
var _look_dy := 0.0
var _pad_boost := 0.0
var _pad_device := 0
var _pad_sprint_latch := false
var _headless := false
var _mouse_mode_prev := -1
var _mouse_settle := 0
# settings cache
var _sens := 1.0
var _invert_y := false
var _cm := 1.0
var _fov_base := 72.0
var _quality := "high"
var _quality_script: Script = null
# debug
var _dbg_stress := -1.0
var _dbg_log := false
var _dbg_log_t := 0.0

# ====================================================================== setup

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = -10                    # camera written before interaction / UI read it
	process_physics_priority = -10
	_headless = DisplayServer.get_name() == "headless"
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD
	floor_max_angle = deg_to_rad(50.0)
	_floor_min_y = cos(floor_max_angle)
	floor_snap_length = 0.35
	floor_stop_on_slope = true
	floor_block_on_wall = true
	floor_constant_speed = false              # tangent velocity is computed by hand (exact horizontal speed on the ramp)
	max_slides = 6
	safe_margin = 0.002

	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = HEIGHT_STAND
	_shape_node = CollisionShape3D.new()
	_shape_node.name = "Capsule"
	_shape_node.shape = _shape
	_shape_node.position.y = HEIGHT_STAND * 0.5
	add_child(_shape_node)

	camera.name = "PlayerCamera"
	camera.top_level = true                   # world-space rig (the entity jumpscare can take it over freely)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near = 0.04
	camera.far = 120.0
	camera.fov = 72.0
	add_child(camera)
	camera.current = true

	_setup_flashlight()
	_ray.collision_mask = LAYER_WORLD
	_ray.exclude = [get_rid()]
	_read_settings()
	_parse_debug_args()

	Events.entity_spotted.connect(_on_entity_spotted)
	Events.noise.connect(_on_noise)
	Events.power_changed.connect(_on_power_changed)
	Events.game_state.connect(_on_game_state)
	Events.settings_changed.connect(_on_setting)

	respawn()
	if OS.get_cmdline_user_args().has("--crouch"):
		set_crouch(true)

func _setup_flashlight() -> void:
	_light = flashlight.light
	_light.name = "Flashlight"
	_light.light_color = FLASH_COLOR
	_light.light_energy = 0.0
	_light.visible = false
	_light.spot_range = FLASH_RANGE
	_light.spot_angle = rad_to_deg(FLASH_ANGLE)
	_light.spot_attenuation = 2.0              # inverse square (three.js decay 2)
	# Godot's cone falloff is 1 - rim^(1 / spot_angle_attenuation) (measured): a small value = flat cone; the three.js
	# penumbra is baked into the cookie instead
	_light.spot_angle_attenuation = CONE_FLAT
	_cookie = Cookie.make(256, FLASH_ANGLE, FLASH_PENUMBRA)
	_light.light_projector = _cookie
	_light.light_specular = 1.0
	_light.light_bake_mode = Light3D.BAKE_DISABLED   # a fast-moving light smears SDFGI; SSIL + the bounce light do it
	_light.light_volumetric_fog_energy = 1.0   # the beam shows in the look module's volumetric fog
	_light.shadow_enabled = true
	_light.shadow_bias = 0.02
	_light.shadow_normal_bias = 1.2
	_light.shadow_blur = 0.75                  # near-point source: tighter penumbrae (TAA smooths the PCF dither)
	_light.position = FLASH_POS
	_light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.add_child(_light)
	_flash_lin = FLASH_COLOR.srgb_to_linear()
	_flash_low_lin = FLASH_COLOR_LOW.srgb_to_linear()

	_bounce = OmniLight3D.new()
	_bounce.name = "FlashlightBounce"
	_bounce.top_level = true
	_bounce.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bounce.light_color = BOUNCE_COLOR
	_bounce.light_energy = 0.0
	_bounce.omni_range = 7.0
	_bounce.omni_attenuation = 2.0
	_bounce.shadow_enabled = false
	_bounce.light_specular = 0.0
	_bounce.light_bake_mode = Light3D.BAKE_DISABLED
	_bounce.light_volumetric_fog_energy = 0.0
	_bounce.visible = false
	add_child(_bounce)

func _read_settings() -> void:
	_sens = float(Settings.get_value("sensitivity", 1.0))
	_invert_y = Settings.get_value("invert_y", false) == true
	_cm = clampf(float(Settings.get_value("camera_motion", 1.0)), 0.0, 1.0)
	_fov_base = float(Settings.get_value("fov", 72.0))
	_apply_quality(str(Settings.get_value("quality", "high")))

func _on_setting(key: String, value: Variant) -> void:
	match key:
		"sensitivity": _sens = float(value)
		"invert_y": _invert_y = value == true
		"camera_motion": _cm = clampf(float(value), 0.0, 1.0)
		"fov": _fov_base = float(value)
		"quality": _apply_quality(str(value))

func _apply_quality(q: String) -> void:
	_quality = q
	# The torch keeps its shadow on every preset: it is THE light of the game, and in Godot 4.5 a SpotLight3D projector
	# (the cookie) only renders while the light casts shadows (without them the light goes black).
	set_flashlight_shadows(true)
	_light.light_size = 0.03 if q == "ultra" else 0.0      # PCSS contact-hardening on ultra
	# high / ultra have SSIL (screen-space bounce): the fake bounce only tops it up
	_bounce_scale = 1.0 if (q == "low" or q == "medium") else 0.6

## Shadows on: cookie projector + flat cone. Off (e.g. if a preset ever disables positional shadows): the cookie is
## dropped and the three.js beam profile is approximated with the cone falloff, so the torch never goes dark.
func set_flashlight_shadows(on: bool) -> void:
	_light.shadow_enabled = on
	if on:
		_light.light_projector = _cookie
		_light.spot_angle_attenuation = CONE_FLAT
	else:
		_light.light_projector = null
		_light.spot_angle_attenuation = CONE_PENUMBRA

func _parse_debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--battery="):
			flashlight.battery = clampf(a.substr(a.find("=") + 1).to_float(), 0.0, 100.0)
		elif a.begins_with("--player-stress="):
			_dbg_stress = clampf(a.substr(a.find("=") + 1).to_float(), 0.0, 1.0)
		elif a == "--player-log":
			_dbg_log = true

# ====================================================================== state helpers

func _sim_active() -> bool:
	var s: String = Game.state
	return s == "playing" or s == "caught" or s == "won"

func _modal_open() -> bool:
	var ui := Game.ui
	return ui != null and ui.has_method("is_modal_open") and ui.is_modal_open() == true

## Movement + look allowed (playing, not taken over by a cinematic, no modal UI).
func _can_control() -> bool:
	return Game.state == "playing" and enabled and not camera_override and not _modal_open()

func hide_busy() -> bool:
	return _hide_busy

static func _damp(k: float, dt: float) -> float:
	return 1.0 - exp(-k * dt)

static func _smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _ease_in_out(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

func _sfx(sound: String, vol := 1.0, pitch_scale := 1.0, bus := "Foley") -> void:
	Audio.play(sound, {"volume_db": linear_to_db(maxf(vol, 0.0001)), "pitch": pitch_scale, "bus": bus})

func _ui_subtitle(text: String, seconds: float) -> void:
	var ui := Game.ui
	if ui != null and ui.has_method("subtitle"):
		ui.subtitle(text, seconds)

func _rumble(weak: float, strong: float, dur: float) -> void:
	if using_gamepad:
		Input.start_joy_vibration(_pad_device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), dur)

# ====================================================================== input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var rel := mm.screen_relative
		if rel.length_squared() > 4.0:
			using_gamepad = false
		if not (_can_control() and not _anim_active):
			return
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _headless:
			return
		if _mouse_settle > 0:
			return                              # warp spike right after the cursor got captured
		_look_dx += rel.x                       # raw, unsmoothed (high-DPI flicks accumulate per frame: no clamping)
		_look_dy += rel.y
	elif event is InputEventJoypadButton:
		using_gamepad = true
		_pad_device = event.device
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.4:
			using_gamepad = true
			_pad_device = event.device
	elif event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false

func _unhandled_input(event: InputEvent) -> void:
	if not _can_control() or _anim_active:
		return
	if event.is_action_pressed("crouch"):
		if not hidden:
			set_crouch(not crouched)
	elif event.is_action_pressed("flashlight"):
		if flashlight.has:
			set_flashlight_on(not flashlight.on)
	elif event.is_action_pressed("sprint") and event is InputEventJoypadButton:
		_pad_sprint_latch = true                # L3 = sprint toggle on gamepad (held key on keyboard)

# ====================================================================== physics tick (movement, stamina, beam)

func _physics_process(dt: float) -> void:
	_phys_prev = _phys_cur
	if not _sim_active() or dt <= 0.0:
		_phys_cur = global_position
		_phys_prev = _phys_cur
		return
	_bump_cd -= dt
	if _anim_active or hidden:
		velocity = Vector3.ZERO
		_hvel = Vector2.ZERO
		speed = 0.0
		moving = false
		sprinting = false
		_strafe_vel = 0.0
		_phys_cur = global_position
		_phys_prev = _phys_cur
	else:
		_update_movement(dt)
		_phys_cur = global_position
	_update_stamina(dt)
	_update_beam()

func _update_movement(dt: float) -> void:
	var can_move := _can_control() and not hidden and not _anim_active
	var mv := Vector2.ZERO
	if can_move:
		mv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var m := mv.length()
	if m > 1.0:
		mv /= m
		m = 1.0
	if _pad_sprint_latch and (not can_move or m < 0.3 or mv.y < 0.2):
		_pad_sprint_latch = false
	var want_sprint := can_move and (Input.is_action_pressed("sprint") or _pad_sprint_latch) and mv.y > 0.35 and m > 0.5
	if want_sprint and crouched:
		set_crouch(false)
	if _want_stand and crouched and _can_stand():
		_set_crouch_state(false, true)
	var can_sprint := want_sprint and not exhausted and stamina > 0.0 and not crouched
	sprinting = can_sprint

	var spd := CROUCH if crouched else (SPRINT if can_sprint else WALK)
	if exhausted:
		spd = minf(spd, EXHAUSTED_SPEED)
	if on_stairs:
		spd *= 0.85 if can_sprint else 0.8
	var dir_k := 0.72 if mv.y < -0.1 else (0.9 if absf(mv.x) > absf(mv.y) else 1.0)
	spd *= dir_k * m * speed_scale
	var target := Vector2.ZERO
	if m > 1e-3:
		var s := sin(yaw)
		var c := cos(yaw)
		target = Vector2(mv.x * c - mv.y * s, -mv.x * s - mv.y * c).normalized() * spd
	var accel := (6.5 if can_sprint else 8.5) if target.length_squared() > _hvel.length_squared() else 10.0
	_hvel += (target - _hvel) * _damp(accel, dt)
	if absf(_hvel.x) < 1e-4 and target.x == 0.0:
		_hvel.x = 0.0
	if absf(_hvel.y) < 1e-4 and target.y == 0.0:
		_hvel.y = 0.0

	var on_floor := is_on_floor()
	if on_floor:
		# velocity tangent to the floor whose horizontal part is exactly _hvel (same speed on the stair ramp as the web)
		var n := get_floor_normal()
		var vy := 0.0
		if n.y > 0.3 and n.y < 0.999:
			vy = -(n.x * _hvel.x + n.z * _hvel.y) / n.y
		velocity = Vector3(_hvel.x, vy, _hvel.y)
	else:
		velocity.x = _hvel.x
		velocity.z = _hvel.y
		velocity.y -= GRAVITY * dt

	var start := global_position
	if on_floor and _hvel.length_squared() > 1e-6:
		_try_step_up(dt)
	move_and_slide()

	# results: real horizontal motion, bumps, slide-only velocity after a wall hit
	var moved := global_position - start
	var got := Vector2(moved.x, moved.z)
	var want_len := _hvel.length() * dt
	var wall: Object = null
	var wall_hit := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < _floor_min_y - 0.05:
			wall_hit = true
			wall = col.get_collider()
			break
	if wall_hit and dt > 0.0:
		if sprinting and want_len / dt > 2.3 and got.length() < want_len * 0.55 and _bump_cd <= 0.0:
			_bump(_tag_of(wall))
		_hvel = got / dt
		if _hvel.length() > SPRINT:
			_hvel = _hvel.normalized() * SPRINT
	speed = got.length() / dt
	moving = speed > 0.15
	if moving:
		_free_eye_y = NAN
	_strafe_vel = _hvel.x * cos(yaw) - _hvel.y * sin(yaw)

	# falls (the web's >= 0.6 m drop thump)
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		var drop := _air_top - global_position.y
		if drop >= 0.6:
			_dip.v -= 0.9
			_sfx("land_thump", 0.7)
			_emit_noise(LOUD.land)
			_rumble(0.3, 0.6, 0.18)
	if now_floor:
		_air_top = global_position.y
	else:
		_air_top = maxf(_air_top, global_position.y)
	_was_on_floor = now_floor

## Lifts the body onto a small ledge (<= STEP_HEIGHT) blocking the way: box treads, thresholds, low clutter.
## A walkable ramp is left to move_and_slide (tangent velocity + floor snap).
func _try_step_up(dt: float) -> bool:
	var h := Vector3(_hvel.x, 0.0, _hvel.y) * dt
	var hl := h.length()
	if hl < 1e-5:
		return false
	var xf := global_transform
	if not test_move(xf, h, _kc, safe_margin):
		return false
	if _kc.get_normal().y >= _floor_min_y:
		return false
	var up := Vector3(0.0, STEP_HEIGHT, 0.0)
	if test_move(xf, up, _kc, safe_margin):
		up = _kc.get_travel()
	if up.y < 0.04:
		return false
	var xf_up := xf.translated(up)
	var probe := (h / hl) * maxf(hl, 0.12)
	if test_move(xf_up, probe, _kc, safe_margin):
		return false                            # still blocked up there: furniture or a wall
	if not test_move(xf_up.translated(probe), Vector3(0.0, -up.y - 0.02, 0.0), _kc, safe_margin):
		return false                            # nothing to stand on
	if _kc.get_normal().y < _floor_min_y:
		return false
	var rise := up.y + _kc.get_travel().y
	if rise < 0.01 or rise > STEP_HEIGHT + 0.001:
		return false
	global_position.y += rise
	return true

func _tag_of(o: Object) -> String:
	if o == null:
		return "wall"
	if o.has_meta("tag"):
		return str(o.get_meta("tag"))
	var n := o as Node
	if n != null:
		if n.has_meta("tag"):
			return str(n.get_meta("tag"))
		var p := n.get_parent()
		if p != null and p.has_meta("tag"):
			return str(p.get_meta("tag"))
		return String(n.name)
	return "wall"

func _bump(tag: String) -> void:
	_bump_cd = 0.8
	Events.player_bump.emit(tag)
	_sfx("bump", 0.85, randf_range(0.95, 1.05))
	_emit_noise(LOUD.bump)
	_dip.v -= 0.25
	_f_pitch.v += 0.225 * (-1.0 if randf() < 0.5 else 1.0)
	_f_roll.v += (randf() - 0.5) * 0.6
	_rumble(0.35, 0.25, 0.12)

# ---------------------------------------------------------------- crouch

func set_crouch(on: bool) -> void:
	if on == crouched or hidden:
		return
	if not on and not _can_stand():
		_want_stand = true                      # stand up as soon as there is headroom
		return
	_set_crouch_state(on, true)

func _set_crouch_state(on: bool, with_fx: bool) -> void:
	_want_stand = false
	if on == crouched:
		return
	crouched = on
	var hgt := HEIGHT_CROUCH if on else HEIGHT_STAND
	_shape.height = hgt
	_shape_node.position.y = hgt * 0.5
	if with_fx:
		_sfx("cloth_move", 0.32, 0.95 if on else 1.05)
		if on:
			_dip.v -= 0.12                       # small extra dip (the eye spring overshoots a little on its own)

func _can_stand() -> bool:
	if not crouched:
		return true
	return not test_move(global_transform, Vector3(0.0, HEIGHT_STAND - HEIGHT_CROUCH, 0.0), null, safe_margin)

# ---------------------------------------------------------------- ground / stairs / surfaces (render rate)

func _update_ground(dt: float, body: Vector3) -> void:
	if not (_anim_active or hidden):
		_ground = _visual_ground(body)
	var k := _damp(15.0 if on_stairs else 18.0, dt)
	_y1 += (_ground - _y1) * k
	_y2 += (_y1 - _y2) * k
	if absf(_ground - _y2) < 1e-4:
		_y1 = _ground
		_y2 = _ground
	var S: Dictionary = Layout.STAIRS
	var x := body.x
	var z := body.z
	# stairs / landing / upper floor (a physics body on a rug or a small ledge is not "on the stairs": 0.1 m threshold)
	on_stairs = (x >= float(S.minX) and x <= float(S.maxX) and z <= float(S.bottomZ) and z > float(Layout.ROOM.minZ) - 0.01 \
		and _ground > 0.1) or _ground > 1.5
	var gard = Game.garderie
	if x < -3.7 and gard != null and is_instance_valid(gard) and gard.in_area(body):
		# garderie floors: concrete corridor, foam mats / vinyl (soft steps), wooden decks
		var gs := str(gard.surface_at(body))
		surface = "concrete" if gs == "concrete" else ("wood" if gs == "wood" else "carpet")
	elif on_stairs:
		surface = "wood"
	elif is_in_alcove():
		surface = "concrete"
	else:
		surface = "carpet"

## Physical floor everywhere, except on the stairs where the tread heights (Layout) are used so that the smooth ramp
## collider still reads as steps in the camera (web groundHeightAt).
func _visual_ground(body: Vector3) -> float:
	var by := body.y
	var S: Dictionary = Layout.STAIRS
	if by > 0.05 and body.x >= float(S.minX) and body.x <= float(S.maxX) and body.z <= float(S.bottomZ) and body.z > float(S.topZ):
		var g := Layout.stair_height_at(body.x, body.z)
		if not is_nan(g) and absf(g - by) <= 0.3:
			return g
	return by

func is_in_alcove() -> bool:
	var p := _phys_cur
	var A: Dictionary = Layout.ALCOVE
	return p.x >= float(A.minX) and p.x <= float(A.maxX) and p.z < float(Layout.ROOM.minZ) and _ground < 1.0

# ---------------------------------------------------------------- stamina / breathing

func _update_stamina(dt: float) -> void:
	var running := sprinting and speed > 1.6
	if running:
		stamina -= dt / STAMINA_TIME
		_stamina_delay = REGEN_DELAY
		_sprint_time += dt
	else:
		_stamina_delay -= dt
		_sprint_time = maxf(0.0, _sprint_time - dt * 1.5)
		if _stamina_delay <= 0.0:
			stamina += dt * (0.2 if moving else (0.32 if (crouched or hidden) else 0.28))
	stamina = clampf(stamina, 0.0, 1.0)
	if stamina <= 0.0 and not exhausted:
		exhausted = true
		_exhaust_t = 0.0
		sprinting = false
		breath = maxf(breath, 0.85)
	if exhausted:
		_exhaust_t += dt
		if _exhaust_t > 3.0 and stamina >= 0.4:
			exhausted = false
	var target := 1.0 if exhausted else clampf((_sprint_time - 1.2) / 2.5, 0.0, 0.55)
	breath += (target - breath) * _damp(1.6 if target > breath else 0.3, dt)
	if breath < 0.003:
		breath = 0.0
	_hunch += ((1.0 if exhausted else 0.0) - _hunch) * _damp(2.5 if exhausted else 0.9, dt)
	_emit_stamina(false)

func _emit_stamina(force: bool) -> void:
	var q := roundi(stamina * 200.0)
	var bq := roundi(breath * 20.0)
	if not force and q == _last_stamina_q and exhausted == _last_exh and bq == _last_breath_q:
		return
	_last_stamina_q = q
	_last_exh = exhausted
	_last_breath_q = bq
	Events.player_stamina.emit(q / 200.0, exhausted, bq / 20.0)

# ---------------------------------------------------------------- footsteps (synced with the bob)

func _update_steps(dt: float) -> void:
	var hs := 0.0 if (_anim_active or hidden) else speed
	_move_blend += ((1.0 if hs > 0.2 else 0.0) - _move_blend) * _damp(5.0 if hs > 0.2 else 3.0, dt)
	if hs > 0.05:
		var step_len := (0.78 if sprinting else 0.52) if on_stairs else clampf(0.42 + 0.2 * hs, 0.5, 1.12)
		_phase += hs * dt / step_len
		var idx := floori(_phase)
		if idx != _step_idx:
			_step_idx = idx
			if hs > 0.3:
				_footstep(hs)
	elif _move_blend < 0.03:
		# at rest: park the phase at the top of the arc so the next step starts naturally
		_phase = floorf(_phase) + 0.5
		_step_idx = floori(_phase)

func _footstep(hs: float) -> void:
	var surf := surface
	var run_fast := sprinting and hs > 2.2
	var vol := 0.0
	var loud := 0.0
	if crouched:
		vol = 0.3
		loud = float(LOUD.crouch) * (1.5 if surf == "wood" else 1.0)
	elif run_fast:
		vol = 1.0
		loud = LOUD.sprint
	else:
		var k := clampf(hs / WALK, 0.5, 1.0)
		vol = (0.55 if exhausted else 0.68) * (0.7 + 0.3 * k)
		loud = float(LOUD[surf]) * k
	_sfx(STEP_SFX[surf], vol, 0.94 + randf() * 0.1 + (0.04 if run_fast else 0.0))
	if surf == "wood" and _ground > 0.1 and _ground < 2.7 and randf() < 0.14:
		_sfx("stair_creak", 0.35 + randf() * 0.3)
		loud += 0.04
	_emit_noise(loud)
	# landing dip: each footfall going down the stairs (and the last one onto the floor) sinks the view a little
	if _ground < _y2 - 0.05:
		_dip.v -= (0.3 if sprinting else 0.2) * (0.5 if crouched else 1.0)

func _emit_noise(loudness: float) -> void:
	Events.noise.emit(_phys_cur, loudness, "player")

func _on_noise(pos: Vector3, loudness: float, source: String) -> void:
	if source.begins_with("player"):
		return
	var now := _t
	var last: float = _noise_src_t.get(source, -1000.0)
	_noise_src_t[source] = now
	if now - last < 1.5:
		return                                  # continuous source (TV static...): only the first burst startles
	if loudness < 0.5 or Game.state != "playing":
		return
	var d := pos.distance_to(_eye) if pos != Vector3.ZERO else 3.0
	var eff := loudness * clampf(1.4 - d / 6.0, 0.0, 1.0)
	if eff >= 0.45:
		flinch(minf(1.0, eff))

func _on_entity_spotted() -> void:
	flinch(1.0)
	_sfx("player_gasp", 0.6, 1.0, "Voice")

func _on_power_changed(on: bool) -> void:
	if not on and Game.state == "playing":
		flinch(0.55)

## Quick camera jolt (~0.15 s): startle reaction. Scripted scares can call it.
func flinch(strength := 1.0) -> void:
	if _flinch_cd > 0.0 and strength < 1.0:
		return
	_flinch_cd = 0.5
	var s := clampf(strength, 0.0, 1.5) * (0.35 + 0.65 * _cm)
	var side := -1.0 if randf() < 0.5 else 1.0
	_f_pitch.v += 1.4 * s
	_f_yaw.v += side * (0.25 + randf() * 0.35) * s
	_f_roll.v += -side * 0.55 * s
	_f_y.v -= 0.5 * s
	_f_fov.v -= 30.0 * s
	_lag_pitch_v += 1.5 * s                      # the torch jerks too
	_rumble(0.5 * s, 0.8 * s, 0.22)

# ====================================================================== render frame

func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	var mm := Input.mouse_mode
	if mm != _mouse_mode_prev:
		_mouse_mode_prev = mm
		if mm == Input.MOUSE_MODE_CAPTURED:
			_mouse_settle = 2
			_look_dx = 0.0
			_look_dy = 0.0
	elif _mouse_settle > 0:
		_mouse_settle -= 1
	var st: String = Game.state
	if st == "menu" or st == "loading":
		_menu_frame(dt)
		return
	_t += dt
	_flinch_cd -= dt
	_read_stress(dt)
	if _anim_active:
		_step_anim(dt)
	elif _can_control():
		_apply_look(dt)
	else:
		_look_dx = 0.0
		_look_dy = 0.0
	var body := _render_body()
	_update_ground(dt, body)
	_update_steps(dt)
	_update_flashlight(dt)
	_update_camera_fx(dt)
	_apply_camera(dt, body)
	_update_flashlight_pose(dt)
	_update_bounce(dt)
	_update_hidden_view(dt)
	if _dbg_log:
		_dbg_log_t -= dt
		if _dbg_log_t <= 0.0:
			_dbg_log_t = 1.0
			print("[player] pos=%s eye=%.2f spd=%.2f surf=%s stairs=%s st=%.2f exh=%s fov=%.1f bat=%.1f hid=%s" % [
				_phys_cur, _eye.y, speed, surface, on_stairs, stamina, exhausted, _fov, flashlight.battery, hidden])

func _render_body() -> Vector3:
	return _phys_prev.lerp(_phys_cur, clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0))

func _read_stress(dt: float) -> void:
	var s := clampf(Game.fear, 0.0, 1.0)
	var ent := Game.entity
	if ent != null:
		var est = ent.get("state")
		if est == "chasing":
			s = maxf(s, 0.7)
		elif est == "searching" or est == "descending":
			s = maxf(s, 0.22)
		elif est == "jumpscare":
			s = 1.0
	if _dbg_stress >= 0.0:
		s = maxf(s, _dbg_stress)
	stress += (s - stress) * _damp(3.0 if s > stress else 0.6, dt)

# ---------------------------------------------------------------- look

func _apply_look(dt: float) -> void:
	var inv := -1.0 if _invert_y else 1.0
	var k := LOOK_RAD_PER_PX * _sens
	yaw -= _look_dx * k
	pitch -= _look_dy * k * inv
	_look_dx = 0.0
	_look_dy = 0.0
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down", PAD_DEADZONE)
	var m := stick.length()
	if m > 0.0:
		var curved := stick * (pow(m, PAD_CURVE) / m)
		if m > 0.92:
			_pad_boost = minf(1.0, _pad_boost + dt / 0.35)
		else:
			_pad_boost = maxf(0.0, _pad_boost - dt * 4.0)
		yaw -= curved.x * PAD_YAW_RATE * (1.0 + PAD_TURN_BOOST * _pad_boost) * _sens * dt
		pitch -= curved.y * PAD_PITCH_RATE * _sens * dt * inv
	else:
		_pad_boost = 0.0
	if hidden and hide_spot != null:
		var base := _hide_yaw_of(hide_spot)
		yaw = base + clampf(wrapf(yaw - base, -PI, PI), -HIDE_YAW, HIDE_YAW)
		pitch = clampf(pitch, -HIDE_PITCH, HIDE_PITCH)
	else:
		pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	if yaw > 20.0 or yaw < -20.0:
		var w := wrapf(yaw, -PI, PI)
		var shift := w - yaw
		yaw = w
		_prev_cam_yaw += shift
		_cam_yaw += shift

# ---------------------------------------------------------------- camera fx (POV rig)

func _update_camera_fx(dt: float) -> void:
	var cm := _cm
	var hs := 0.0 if (_anim_active or hidden) else speed
	# sprint blend (FOV kick, lean)
	var sprint_t := 1.0 if (sprinting and hs > 2.0) else 0.0
	_sprint_blend += (sprint_t - _sprint_blend) * _damp(3.2 if sprint_t > 0.0 else 2.4, dt)
	var se := _smooth01(_sprint_blend)

	# head bob: sharp low at each foot strike (|sin| cusp) + lateral figure-8, amplitude with speed
	var speed_k := clampf(hs / WALK, 0.0, 1.75)
	var amp_t := 0.03 * speed_k * (0.5 if crouched else 1.0) * (1.0 + 0.25 * se) * (1.15 if exhausted else 1.0)
	if on_stairs:
		amp_t *= 0.8
	_bob_amp += (amp_t * _move_blend - _bob_amp) * _damp(7.0, dt)
	var amp := minf(_bob_amp, 0.058) * cm
	var ph := _phase * PI
	var s_abs := absf(sin(ph)) - ABS_SIN_MEAN
	var s_lat := sin(ph - 0.35)
	var bob_v := amp * s_abs
	var bob_l := amp * 0.7 * s_lat
	_bob_v = bob_v
	_bob_l = bob_l
	var bob_roll := amp * 0.32 * sin(ph)
	var bob_pitch := amp * 0.22 * s_abs
	var bob_yaw := amp * 0.12 * sin(ph - 0.6)

	# breathing: calm / scared / exhausted / hidden (slow, shallow, held)
	var st := stress
	var br := breath
	var rate := (0.15 + 0.1 * st) if hidden else (0.22 + 0.3 * st + 0.62 * br)
	_breath_ph = fmod(_breath_ph + dt * TAU * rate, TAU * 64.0)
	var quiet := 1.0 - 0.5 * _move_blend
	var b_amp := (0.0022 if hidden else (0.0042 + 0.003 * st) * quiet + 0.014 * br) * cm
	var breath_y := b_amp * sin(_breath_ph)
	var breath_p := b_amp * 0.85 * sin(_breath_ph - 0.7)
	var breath_r := b_amp * 0.25 * sin(_breath_ph * 0.5 + 1.1)

	# fear tremor: quasi-random hand-held shake (sum of incommensurate sines, no allocations)
	var t := _t
	var tr := cm * pow(st, 1.5)
	var hf1 := sin(t * 9.7) * 0.55 + sin(t * 13.3 + 1.7) * 0.3 + sin(t * 17.9 + 0.4) * 0.15
	var hf2 := sin(t * 10.9 + 2.3) * 0.5 + sin(t * 14.7 + 0.2) * 0.3 + sin(t * 19.3 + 1.1) * 0.2
	var hf3 := sin(t * 8.3 + 0.9) * 0.6 + sin(t * 15.1 + 2.9) * 0.4
	var lf1 := sin(t * 1.9 + 0.3) * 0.6 + sin(t * 3.1 + 2.2) * 0.4
	var lf2 := sin(t * 1.3 + 1.4) * 0.55 + sin(t * 2.7 + 0.6) * 0.45
	var trem_p := tr * (0.0023 * hf1 + 0.0034 * lf1)
	var trem_y := tr * (0.0019 * hf2 + 0.0030 * lf2)
	var trem_r := tr * (0.0014 * hf3 + 0.0022 * lf1)
	_trem_hand = tr * (0.0022 * hf2 + 0.0015 * lf2)
	_trem_hand2 = tr * (0.0022 * hf1 + 0.0015 * lf1)

	# eye height (crouch / stand) with a little undershoot = crouch dip
	var eye_t := eye_height if (hidden and hide_spot != null) else (EYE_CROUCH if crouched else EYE_STAND)
	if not hidden and not _anim_active:
		eye_height = _eye_spring.step(eye_t, 11.0, 0.72, dt)
	else:
		_eye_spring.reset(eye_height)

	# dips (stairs, bumps, landings) and flinch springs
	var dip := _dip.step(0.0, 14.0, 0.55, dt)
	var f_p := _f_pitch.step(0.0, 20.0, 0.42, dt)
	var f_yw := _f_yaw.step(0.0, 20.0, 0.42, dt)
	var f_r := _f_roll.step(0.0, 20.0, 0.42, dt)
	var f_y := _f_y.step(0.0, 20.0, 0.42, dt)
	var f_f := _f_fov.step(0.0, 20.0, 0.5, dt)

	# strafe roll (toward the strafe direction)
	var roll_t := -clampf(_strafe_vel / SPRINT, -1.0, 1.0) * 0.026 * cm
	_strafe_roll += (roll_t - _strafe_roll) * _damp(6.0, dt)

	# compose (yaw-relative right/up/forward offsets + rotation offsets)
	var lean_k := 0.5 + 0.5 * cm
	_o_r = bob_l
	_o_u = bob_v + breath_y + maxf(-0.12, dip) + f_y - 0.014 * se * lean_k - 0.04 * _hunch * cm
	_o_f = 0.05 * se * lean_k
	_o_pitch = bob_pitch + breath_p + trem_p + f_p - 0.024 * se * lean_k - 0.05 * _hunch * cm
	_o_yaw = bob_yaw + trem_y + f_yw
	_o_roll = bob_roll + breath_r + trem_r + f_r + _strafe_roll

	# FOV: settings base + sprint kick (+7°) - fear squeeze + flinch
	_fov = _fov_base + 7.0 * se * (0.5 + 0.5 * cm) - 3.0 * smoothstep(0.55, 0.95, st) + f_f

func _apply_camera(dt: float, body: Vector3) -> void:
	var ex := body.x
	var ez := body.z
	var ey := _eye_override_y if not is_nan(_eye_override_y) else _y2 + eye_height
	if not is_nan(_free_eye_y) and not _anim_active and not hidden:
		ey = _free_eye_y
	var s := sin(yaw)
	var c := cos(yaw)
	# right = (c, 0, -s), forward = (-s, 0, -c)
	ex += c * _o_r - s * _o_f
	ez += -s * _o_r - c * _o_f
	ey += _o_u
	_eye = Vector3(ex, ey, ez)
	_cam_yaw = yaw + _o_yaw
	_cam_pitch = pitch + _o_pitch
	if camera_override:
		return
	var q := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, _o_roll)).get_rotation_quaternion()
	var fov := _fov
	if _blend_t < 1.0 and dt > 0.0:
		_blend_t = minf(1.0, _blend_t + dt / 1.2)
		var k := _ease_in_out(_blend_t)
		camera.global_transform = Transform3D(Basis(_blend_q.slerp(q, k)), _blend_pos.lerp(_eye, k))
		fov = lerpf(_blend_fov, _fov, k)
	else:
		camera.global_transform = Transform3D(Basis(q), _eye)
	if absf(camera.fov - fov) > 0.01:
		camera.fov = fov

func _start_blend() -> void:
	var vc := get_viewport().get_camera_3d()
	var src: Camera3D = vc if vc != null else camera
	_blend_pos = src.global_transform.origin
	_blend_q = src.global_transform.basis.orthonormalized().get_rotation_quaternion()
	_blend_fov = src.fov
	_blend_t = 0.0
	_idle_shown = false

func _on_game_state(s: String, prev: String) -> void:
	if s == "playing":
		if (prev == "menu" or prev == "loading") and _idle_shown:
			_start_blend()
		if not camera_override and not camera.current:
			camera.make_current()

func _update_hidden_view(dt: float) -> void:
	var target := 1.0 if hidden else 0.0
	_hidden_view += (target - _hidden_view) * _damp(2.5 if hidden else 4.0, dt)
	if absf(_hidden_view - target) < 0.002:
		_hidden_view = target
	if absf(_hidden_view - _hidden_view_sent) > 0.002 or (_hidden_view == target and _hidden_view_sent != target):
		_hidden_view_sent = _hidden_view
		_set_hidden_view(_hidden_view)

func _set_hidden_view(v: float) -> void:
	# look module API (static on quality.gd); resolved at runtime so this compiles against the stub too
	if _quality_script == null:
		_quality_script = load("res://scripts/render/quality.gd")
	if _quality_script != null and _quality_script.has_method("set_hidden_view"):
		_quality_script.call("set_hidden_view", v)

# ====================================================================== menu camera

func _menu_frame(dt: float) -> void:
	var ui := Game.ui
	if ui != null and ui.get("menu_camera_active") == true:
		_idle_shown = true                      # the TV menu owns the camera; blend from its framing on start
		return
	update_idle_camera(dt)

## Fallback menu camera: slow cinematic drift in the room (web updateIdleCamera).
func update_idle_camera(dt: float) -> void:
	_idle_t += dt
	var t := _idle_t
	var x := 1.35 + 0.42 * sin(t * 0.047)
	var y := 1.47 + 0.03 * sin(t * 0.17) + 0.004 * sin(t * 1.3)
	var z := 1.52 + 0.12 * sin(t * 0.071 + 1.0)
	var yw := 0.5 + 0.2 * sin(t * 0.041 + 0.5)
	var pt := -0.075 + 0.03 * sin(t * 0.059) + 0.003 * sin(t * 1.3 - 0.6)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(pt, yw, 0.006 * sin(t * 0.09))), Vector3(x, y, z))
	if absf(camera.fov - _fov_base) > 0.01:
		camera.fov = _fov_base
	_idle_shown = true
	if not flashlight.on and _light.visible:
		_light.light_energy = 0.0
		_light.visible = false
		_bounce.visible = false

# ====================================================================== flashlight

func give_flashlight() -> void:
	if flashlight.has:
		return
	flashlight.has = true
	set_flashlight_on(true)

func set_flashlight_on(on: bool) -> void:
	if on and not flashlight.has:
		return
	if on and float(flashlight.battery) <= 0.0 and not _swap_battery():
		_sfx("flashlight_click", 0.5)
		_ui_subtitle("Plus de pile…", 2.0)
		flashlight.on = false
		_emit_flashlight()
		return
	if on == flashlight.on:
		_emit_flashlight()
		return
	flashlight.on = on
	_die_t = 0.0
	_sfx("flashlight_click", 0.55)
	_emit_noise(LOUD.click)
	_emit_flashlight()

func add_battery(amount := 60.0) -> void:
	flashlight.battery = clampf(float(flashlight.battery) + amount, 0.0, 100.0)
	_die_t = 0.0
	_emit_flashlight()

func _swap_battery() -> bool:
	var inv := Game.inventory
	if inv == null or not inv.has_method("remove") or inv.remove("battery") != true:
		return false
	_swap_dark = 0.7                            # a moment of darkness while the battery is swapped
	_sfx("battery_change", 0.8)
	_ui_subtitle("Tu changes la pile.", 2.0)
	add_battery(100.0)
	return true

func _emit_flashlight() -> void:
	var b := float(flashlight.battery)
	_last_battery_int = ceili(b)
	Events.player_flashlight.emit(flashlight.has, flashlight.on, roundf(b * 10.0) / 10.0)

func _update_flashlight(dt: float) -> void:
	var mul := 0.0
	if flashlight.on and flashlight.has:
		if _die_t <= 0.0:
			flashlight.battery = maxf(0.0, float(flashlight.battery) - dt * 100.0 / BATTERY_LIFE)
			if float(flashlight.battery) <= 0.0 and not _swap_battery():
				_die_t = 1.1
			if ceili(float(flashlight.battery)) != _last_battery_int:
				_emit_flashlight()
		var b := float(flashlight.battery)
		mul = 0.6 + 0.4 * smoothstep(0.0, 35.0, b)
		# low battery: random flicker bursts, more frequent as it drains; rare short stutters at extreme fear
		var low := b < 15.0
		_flick_t -= dt
		if not _flick_on:
			if (_flick_t <= 0.0) if low else (stress > 0.8 and randf() < dt * 0.12):
				_flick_on = true
				_flick_t = (0.1 + randf() * 0.45) if low else (0.08 + randf() * 0.18)
		elif _flick_t <= 0.0:
			_flick_on = false
			_flick_t = (0.7 + 3.5 * (b / 15.0)) * (0.5 + randf()) if low else 2.0
		if _flick_on:
			_flick_j -= dt
			if _flick_j <= 0.0:
				_flick_j = 0.02 + randf() * 0.06
				_flick_lvl = (0.04 + randf() * 0.2) if randf() < 0.45 else (0.55 + randf() * 0.45)
			mul *= _flick_lvl
		# dying: violent flicker then off
		if _die_t > 0.0:
			_die_t -= dt
			mul *= 0.03 if randf() < 0.5 else 0.25 + randf() * 0.35 * _die_t
			if _die_t <= 0.0:
				_die_t = 0.0
				flashlight.on = false
				mul = 0.0
				_ui_subtitle("La pile est morte…", 2.5)
				_emit_flashlight()
		if _swap_dark > 0.0:
			_swap_dark -= dt
			mul = 0.0
	else:
		_swap_dark = 0.0
	# filament response (fast but not instant)
	var rate := 90.0 if (_flick_on or _die_t > 0.0) else (45.0 if mul > _fl_mul else 30.0)
	_fl_mul += (mul - _fl_mul) * _damp(rate, dt)
	if _fl_mul < 0.002:
		_fl_mul = 0.0
	var lit := _fl_mul > 0.0
	_light.light_energy = FLASH_ENERGY * flashlight_energy_scale * _fl_mul
	if _light.visible != lit:
		_light.visible = lit                   # an unlit torch costs no shadow pass
	# weak battery = warmer light (blend in linear space)
	var warm := (1.0 - smoothstep(4.0, 30.0, float(flashlight.battery))) if flashlight.on else 0.0
	_light.light_color = _flash_lin.lerp(_flash_low_lin, warm * 0.6).linear_to_srgb()

func _update_flashlight_pose(dt: float) -> void:
	# the beam lags behind fast camera turns (spring), then catches up with a slight overshoot
	var d_yaw := wrapf(_cam_yaw - _prev_cam_yaw, -PI, PI)
	var d_pitch := _cam_pitch - _prev_cam_pitch
	if absf(d_yaw) > 0.8 or absf(d_pitch) > 0.8:
		d_yaw = 0.0
		d_pitch = 0.0
		_lag_yaw = 0.0
		_lag_pitch = 0.0
	_prev_cam_yaw = _cam_yaw
	_prev_cam_pitch = _cam_pitch
	_lag_yaw -= d_yaw
	_lag_pitch -= d_pitch
	var w := 13.0
	var z := 0.62
	var n := 1
	if dt > 0.016:
		n = ceili(dt / 0.016)
	var h := dt / n
	for i in n:
		_lag_yaw_v += (-2.0 * z * w * _lag_yaw_v - w * w * _lag_yaw) * h
		_lag_pitch_v += (-2.0 * z * w * _lag_pitch_v - w * w * _lag_pitch) * h
		_lag_yaw += _lag_yaw_v * h
		_lag_pitch += _lag_pitch_v * h
	var lim := 0.2
	if _lag_yaw > lim:
		_lag_yaw = lim
		_lag_yaw_v = minf(_lag_yaw_v, 0.0)
	elif _lag_yaw < -lim:
		_lag_yaw = -lim
		_lag_yaw_v = maxf(_lag_yaw_v, 0.0)
	if _lag_pitch > lim:
		_lag_pitch = lim
		_lag_pitch_v = minf(_lag_pitch_v, 0.0)
	elif _lag_pitch < -lim:
		_lag_pitch = -lim
		_lag_pitch_v = maxf(_lag_pitch_v, 0.0)
	# hand sway with the bob + hand tremor with fear (the hand shakes more than the head)
	var ay := _lag_yaw + _bob_l * 0.55 + _trem_hand * 1.6
	var ap := _lag_pitch + _bob_v * 0.45 + _trem_hand2 * 1.6 - _hunch * 0.04
	_light.rotation = Vector3(ap, ay, 0.0)
	_light.position = Vector3(FLASH_POS.x + _bob_l * 0.35, FLASH_POS.y + _bob_v * 0.4, FLASH_POS.z)

## Physics tick: where does the beam land? (feeds the bounce light)
func _update_beam() -> void:
	if not _light.visible:
		return
	var xf := _light.global_transform
	var o := xf.origin
	var d := -xf.basis.z.normalized()
	_ray.from = o
	_ray.to = o + d * 9.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	_beam_t = o.distance_to(hit.position) if not hit.is_empty() else 9.0

## Cheap one-bounce fill from the beam's hit point (warm, shadowless, fades when the beam escapes far away).
func _update_bounce(dt: float) -> void:
	var e := _light.light_energy if _light.visible else 0.0
	if e <= 0.01:
		if _bounce.visible:
			_bounce.visible = false
		_bounce.light_energy = 0.0
		_bounce_init = false                    # snap to the new hit point when the torch comes back on
		return
	var xf := _light.global_transform
	var d := -xf.basis.z.normalized()
	var p := xf.origin + d * maxf(0.05, _beam_t - 0.3)
	if not _bounce_init:
		_bounce_pos = p
		_bounce_init = true
	else:
		_bounce_pos = _bounce_pos.lerp(p, _damp(14.0, dt))
	_bounce.global_position = _bounce_pos
	_bounce.light_energy = e * 0.032 * (0.4 if _beam_t >= 9.0 else 1.0) * _bounce_scale
	if not _bounce.visible:
		_bounce.visible = true

# ====================================================================== hiding

func _spot_get(spot: Variant, key: String) -> Variant:
	if spot is Dictionary:
		return (spot as Dictionary).get(key)
	if spot is Object and spot != null:
		return (spot as Object).get(key)
	return null

func _spot_vec(spot: Variant, keys: Array, fallback: Vector3) -> Vector3:
	for k in keys:
		var v: Variant = _spot_get(spot, k)
		if v is Vector3:
			return v
		if v is Dictionary:
			var dv: Dictionary = v
			return Vector3(float(dv.get("x", fallback.x)), float(dv.get("y", fallback.y)), float(dv.get("z", fallback.z)))
	return fallback

func _hide_yaw_of(spot: Variant) -> float:
	for k in ["hide_yaw", "hideYaw"]:
		var v: Variant = _spot_get(spot, k)
		if v is float or v is int:
			return float(v)
	return float(Layout.CLOSET.hideYaw)

func _spot_id(spot: Variant) -> String:
	var v: Variant = _spot_get(spot, "id")
	return str(v) if v != null else ""

func _door_of(spot: Variant) -> Variant:
	var d: Variant = _spot_get(spot, "door")
	if d is Object and d != null and (d as Object).has_method("open"):
		return d
	var w := Game.world
	if w != null:
		var hs: Variant = w.get("handles")
		if hs is Dictionary:
			var id := _spot_id(spot)
			var h: Variant = (hs as Dictionary).get("door." + (id if id != "" else "closet"))
			if h is Object and h != null and (h as Object).has_method("open"):
				return h
	return null

func _hide_eye(spot: Variant) -> Vector3:
	var c: Dictionary = Layout.CLOSET.hidePos
	var hp := _spot_vec(spot, ["hide_pos", "hidePos"], Vector3(float(c.x), float(c.y), float(c.z)))
	if hp.y < 0.6:
		hp.y += float(c.y)                      # a feet position was given: crouched eye height in the closet
	return hp

func _exit_pos(spot: Variant) -> Vector3:
	var c: Dictionary = Layout.CLOSET.exitPos
	return _spot_vec(spot, ["exit_pos", "exitPos"], Vector3(float(c.x), 0.0, float(c.z)))

## Animated camera/body move: (x, eye_y, z) + yaw/pitch over dur seconds (eased); on_mid runs halfway.
func _anim_move(x: float, eye_y: float, z: float, to_yaw: float, to_pitch: float, dur: float, on_mid := Callable()) -> void:
	var from_eye := _eye_override_y if not is_nan(_eye_override_y) else _y2 + eye_height
	_anim_from = Vector3(_phys_cur.x, from_eye, _phys_cur.z)
	_anim_to = Vector3(x, eye_y, z)
	_anim_yaw0 = yaw
	_anim_dyaw = to_yaw - yaw
	_anim_pitch0 = pitch
	_anim_pitch1 = to_pitch
	_anim_dur = maxf(0.05, dur)
	_anim_time = 0.0
	_anim_mid = on_mid
	_anim_mid_done = false
	_eye_override_y = from_eye
	_anim_active = true
	await _anim_finished

func _step_anim(dt: float) -> void:
	_anim_time += dt
	var k := minf(1.0, _anim_time / _anim_dur)
	var e := _ease_in_out(k)
	var p := _anim_from.lerp(_anim_to, e)
	_set_body_position(Vector3(p.x, _ground, p.z))
	_eye_override_y = p.y
	yaw = _anim_yaw0 + _anim_dyaw * e
	pitch = lerpf(_anim_pitch0, _anim_pitch1, e)
	_hvel = Vector2.ZERO
	speed = 0.0
	moving = false
	sprinting = false
	_strafe_vel = 0.0
	if not _anim_mid_done and k >= 0.5:
		_anim_mid_done = true
		if _anim_mid.is_valid():
			_anim_mid.call()
	if k >= 1.0:
		_anim_active = false
		_anim_finished.emit()

func _cancel_anim() -> void:
	_hide_gen += 1
	_hide_busy = false
	if _anim_active:
		_anim_active = false
		_anim_finished.emit()

## Opens/closes a Handle; returns a state Dictionary whose "done" flips when the animation is over.
func _door_start(door: Variant, open: bool) -> Dictionary:
	var state := {"done": true}
	if door == null:
		return state
	if (open and door.is_open == true) or (not open and door.is_open != true):
		return state
	state.done = false
	_door_run(door, open, state)
	return state

func _door_run(door: Variant, open: bool, state: Dictionary) -> void:
	if open:
		await door.open()
	else:
		await door.close()
	state.done = true

func _door_wait(state: Dictionary, timeout: float) -> void:
	var waited := 0.0
	while state.done != true and waited < timeout and is_inside_tree():
		await get_tree().process_frame
		if not get_tree().paused:               # the door tween is paused too: don't time out during a pause
			waited += get_process_delta_time()

func _set_hidden(v: bool, spot: Variant) -> void:
	if hidden == v:
		return
	hidden = v
	hide_spot = spot if v else null
	if v:
		_set_crouch_state(false, false)
		sprinting = false
	var ui := Game.ui
	if ui != null and ui.has_method("set_hidden"):
		ui.set_hidden(v)
	Events.player_hide.emit(v, _spot_id(spot))

## Hide in a spot (closet): steps in front of the door while it opens, slips inside, turns around, crouches, the door
## closes. Returns (await) once the camera is in place (not when the door is shut).
func enter_hide(spot) -> void:
	if spot == null or hidden or _hide_busy:
		return
	_hide_busy = true
	_hvel = Vector2.ZERO
	velocity = Vector3.ZERO
	sprinting = false
	_set_crouch_state(false, false)
	_free_eye_y = NAN
	var door: Variant = _door_of(spot)
	var hp := _hide_eye(spot)
	var hide_yaw := _hide_yaw_of(spot)
	var ex := _exit_pos(spot)
	var face_yaw := yaw + wrapf(hide_yaw + PI - yaw, -PI, PI)
	_hide_gen += 1
	var gen := _hide_gen
	# 1) step in front of the door and face it while it opens
	var opening := _door_start(door, true)
	await _anim_move(ex.x, EYE_STAND - 0.06, hp.z, face_yaw, -0.06, 0.42)
	if gen != _hide_gen:
		return                                  # cancelled (respawn / teleport)
	await _door_wait(opening, 1.2)
	if gen != _hide_gen:
		return
	_sfx("closet_enter", 0.8)
	# 2) slip inside, turn around (via the left) and crouch down
	_ground = 0.0
	var turn := wrapf(hide_yaw - yaw, -PI, PI)
	if absf(absf(turn) - PI) < 0.3:
		turn = absf(turn)
	await _anim_move(hp.x, hp.y, hp.z, yaw + turn, 0.0, 0.8, _set_hidden.bind(true, spot))
	if gen != _hide_gen:
		return
	_set_hidden(true, spot)
	yaw = hide_yaw + wrapf(yaw - hide_yaw, -PI, PI)
	eye_height = hp.y - _ground
	_y1 = _ground
	_y2 = _ground
	_set_body_position(Vector3(hp.x, _ground, hp.z))
	# 3) pull the door shut (not awaited)
	_door_start(door, false)
	_hide_busy = false

## Leave the hide spot: the door opens, step out to the exit position facing the room, control is back at once.
func exit_hide() -> void:
	if not hidden or _hide_busy:
		return
	var spot: Variant = hide_spot
	_hide_busy = true
	var door: Variant = _door_of(spot)
	var ex := _exit_pos(spot)
	var hide_yaw := _hide_yaw_of(spot)
	_hide_gen += 1
	var gen := _hide_gen
	var opening := _door_start(door, true)
	await _door_wait(opening, 0.25)
	if gen != _hide_gen:
		return
	_sfx("closet_exit", 0.8)
	await _anim_move(ex.x, EYE_STAND, ex.z, yaw + wrapf(hide_yaw - yaw, -PI, PI), 0.0, 0.7, _set_hidden.bind(false, spot))
	if gen != _hide_gen:
		return
	_set_hidden(false, spot)
	_eye_override_y = NAN
	_ground = _ground_at(ex.x, ex.z, 0.0)
	_set_body_position(Vector3(ex.x, _ground, ex.z))
	_y1 = _ground
	_y2 = _ground
	eye_height = EYE_STAND
	_eye_spring.reset(EYE_STAND)
	_set_crouch_state(false, false)
	_door_start(door, false)                     # close behind (not awaited)
	_hide_busy = false

# ====================================================================== misc API

func _ground_at(x: float, z: float, prev_y: float) -> float:
	var w := Game.world
	if w != null and w.has_method("ground_height_at"):
		return float(w.ground_height_at(x, z, prev_y))
	return Layout.ground_height_at(x, z, prev_y)

func _set_body_position(p: Vector3) -> void:
	global_position = p
	_phys_prev = p
	_phys_cur = p

## Back to the spawn point, standing, flashlight state kept.
func respawn() -> void:
	_cancel_anim()
	var was_hidden := hidden
	var spot: Variant = hide_spot
	var sp: Dictionary = Layout.SPAWN
	var gy := _ground_at(float(sp.x), float(sp.z), 0.0)
	_set_body_position(Vector3(float(sp.x), gy + 0.01, float(sp.z)))
	yaw = float(sp.yaw)
	pitch = 0.0
	_reset_motion()
	_ground = gy
	_y1 = gy
	_y2 = gy
	_free_eye_y = NAN
	stamina = 1.0
	exhausted = false
	breath = 0.0
	_hunch = 0.0
	_sprint_time = 0.0
	if was_hidden:
		_set_hidden(false, spot)
	hidden = false
	hide_spot = null
	_hidden_view = 0.0
	_hidden_view_sent = -1.0
	_set_hidden_view(0.0)
	_snap_camera()
	_emit_stamina(true)
	_emit_flashlight()

## pos.y = feet; a y clearly above the floor is kept as a fixed eye height until the player moves (debug cams).
func teleport(pos: Vector3, y: float, p := 0.0) -> void:
	_cancel_anim()
	if hidden:
		_set_hidden(false, hide_spot)
	var gy := _ground_at(pos.x, pos.z, pos.y)
	_set_body_position(Vector3(pos.x, maxf(gy, pos.y if pos.y < gy + 0.3 else gy) + 0.01, pos.z))
	_ground = gy
	_y1 = gy
	_y2 = gy
	_free_eye_y = pos.y if pos.y > gy + 0.3 else NAN
	yaw = y
	pitch = p
	_reset_motion()
	_snap_camera()

func _snap_camera() -> void:
	_prev_cam_yaw = yaw
	_cam_yaw = yaw
	_prev_cam_pitch = pitch
	_cam_pitch = pitch
	_blend_t = 1.0
	_eye = Vector3(_phys_cur.x, (_free_eye_y if not is_nan(_free_eye_y) else _y2 + eye_height), _phys_cur.z)
	if not camera_override and is_inside_tree():
		camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), _eye)
	reset_physics_interpolation()

func _reset_motion() -> void:
	velocity = Vector3.ZERO
	_hvel = Vector2.ZERO
	speed = 0.0
	moving = false
	sprinting = false
	_pad_sprint_latch = false
	_set_crouch_state(false, false)
	eye_height = EYE_STAND
	_eye_spring.reset(EYE_STAND)
	_eye_override_y = NAN
	_dip.reset()
	_f_pitch.reset()
	_f_yaw.reset()
	_f_roll.reset()
	_f_y.reset()
	_f_fov.reset()
	_lag_yaw = 0.0
	_lag_pitch = 0.0
	_lag_yaw_v = 0.0
	_lag_pitch_v = 0.0
	_bob_amp = 0.0
	_move_blend = 0.0
	_sprint_blend = 0.0
	_strafe_roll = 0.0
	_strafe_vel = 0.0
	_o_r = 0.0
	_o_u = 0.0
	_o_f = 0.0
	_o_pitch = 0.0
	_o_yaw = 0.0
	_o_roll = 0.0
	_look_dx = 0.0
	_look_dy = 0.0
	_was_on_floor = true
	_air_top = global_position.y
	_bounce_init = false

## 0..1: how visible the player is to the entity right now.
func get_visibility() -> float:
	if hidden:
		return 0.0
	var v := 0.0
	if flashlight.on and flashlight.has:
		v = 1.0
	else:
		var w := Game.world
		var powered: bool = w == null or w.get("power") != false
		if powered:
			v = 0.5 if is_in_alcove() else 0.7
		else:
			v = 0.35
	if crouched:
		v *= 0.5
	return v

func eye_position() -> Vector3:
	return _eye

func reset_after_caught() -> void:
	respawn()
	camera_override = false
	enabled = true
	if is_inside_tree() and not camera.current:
		camera.make_current()
