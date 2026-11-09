## La Gardienne — the entity (ARCHITECTURE_PC.md §4 Gardienne). Faithful port of src/entity/Gardienne.js.
## Public API (keep): build() (await), state: String, fear: float, active: bool, root: Node3D,
##   summon(target: Vector3, reason := ""), set_aggression(level: int), set_enabled(on: bool), reset_after_caught()
## Signals via Events: entity_state, entity_spotted, entity_caught. Listens: Events.noise, Events.player_hide.
## Extra public members: model (gardienne_model.gd), enabled, aggression, suspicion, yaw, seeing, state_log (transitions
##   {t, state, prev, pos}), stall_events, summon(target, reason, aggressive := false),
##   debug_place(pos, yaw, mode := "idle", t := -1.0, look := null), debug_release(), debug_jumpscare(freeze_t := -1.0),
##   head_position() / eye_position() / face_position(), get_head_position() / get_feet_position() (audio module hooks),
##   glimpse(pos, yaw, mode, look) -> bool / end_glimpse() / glimpsing (fear module apparitions, dormant only).
##
## Behaviour (same states, numbers and timings as the web version):
##  dormant    upstairs (hall), invisible. Noise raises suspicion (muffled by the floor, scaled by distance to the stairwell
##             door and aggression); >= 1.6 wakes her. After the first visit she also patrols every 90-180 s (45-90 s hunting).
##  waking     heavy steps cross the ceiling toward the stairwell door (ceiling_steps / ceiling_walk), feet shadows in the
##             door strip light, a knock (knock_wall) — then she opens the upstairs door (its `locked` flag is preserved).
##  descending walks down the stairs (entity_step_stairs), door left open, ducks under the drywall bulkhead.
##  searching  goes to the noise, then 3-5 random nav nodes nearby; pauses with jerky listening head tilts, hums
##             (lullaby_hum loop). If she saw the player slip into the closet she walks to it, opens it -> jumpscare.
##  chasing    FOV 110°, range 12 m x player visibility, LOS world.line_blocked. Spots: freezes 0.45 s, croaks, charges at
##             2.9 m/s (direct when the straight capsule sweep is free, A* otherwise, repath 0.7 s). Loses the player after 4 s.
##  returning  walks back up, closes the door behind her, dormant again.
##  jumpscare  within 0.85 m + LOS: takes the camera (player.camera_override), lunges until her face is 0.24 m from the lens,
##             scream, red flash, shake, blur; ~1.4 s later emits Events.entity_caught (Game fades and resets everyone).
## Godot side: CharacterBody3D (Jolt) on LAYER_ENTITY, capsule r 0.3 spanning 0.45..1.72 m above her feet (clears treads,
## ramps and low clutter like the web's 0.3 m span), floating motion (move_and_slide slides along walls / furniture), height
## from world.ground_height_at like the web; the capsule sweep also answers the web's segmentBlocked(). AI on the physics
## tick (60 Hz), presentation (model interpolated between ticks, AnimationTree, jumpscare camera) every rendered frame.
## Never stuck: the web waypoint watchdog (back off, skip waypoint, give up the goal) + a global no-progress watchdog
## (detour through another nav node, then a short collision-less squeeze) + a visit timeout.
## Debug args (after --): --noentity  --entity-log  --entity-aggression=N  --entity-noise=x,y,z[,loudness]
##   --entity-summon=x,z  --entity-place=x,y,z,yawDeg[,mode[,t[,stare]]]  --entity-front=dist[,mode[,t[,stare]]] (in front
##   of the camera, facing it; stare = she looks into the lens)  --entity-jumpscare[=t] (t = frozen frame time)
##   --entity-light (lookdev: key light near her)
##   modes: idle walk chase search reach duck_walk stairs_up stairs_down stairs_duck jumpscare
extends CharacterBody3D

const Model := preload("res://scripts/entity/gardienne_model.gd")

const RADIUS := 0.3
const BODY_H := 1.72               # collision top above her feet (she is 1.98 m but walks stooped and ducks)
const FOOT_CLEAR := 0.45           # collision bottom above her feet
const WALK_SPEED := 0.95
const STAIR_SPEED := 0.78
const CHASE_SPEED := 2.9
const FOV_COS := 0.5735764         # cos(55°)
const SIGHT_RANGE := 12.0
const CATCH_DIST := 0.85
const LOSE_TIME := 4.0
const SUSPICION_MAX := 1.6
const DOOR_EAR := Vector3(-3.0, 3.2, -2.75)      # where she "listens" from (stairwell door)
const DOOR_BEHIND := Vector3(-3.0, 3.6, -2.95)   # knocks / breath behind the closed door
const LAYER_WORLD := 1
const LAYER_ENTITY := 8
const JS_LIGHT_COLOR := Color(0.866667, 0.894118, 0.941176)   # 0xdde4f0
const FLASH_EXPO_T := 9.0          # torch irradiance (web units) above which her exposure adapts (~1.9 m)
const FLASH_EXPO_MIN := 0.5

# ---------------------------------------------------------------- public state
var state := "dormant"
var fear := 0.0
var active := false
var root := Node3D.new()
var model: Model = null
var enabled := true
var aggression := 0
var suspicion := 0.0
var yaw := 0.0
var seeing := false
var state_log: Array = []
var stall_events := 0              # global watchdog interventions (tests: 0 in the real level)

# ---------------------------------------------------------------- internals (web field names, snake_case)
var _built := false
var _t := 0.0
var _state_t := 0.0
var _home := Vector3(-3.0, 2.75, -3.6)
var _target := Vector3.ZERO
var _last_noise := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _last_seen_t := -100.0
var _see_t := 0.0
var _lost_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _speed := 0.0
var _disp_y := 0.0
var _prev_pos := Vector3.ZERO
var _vel_y := 0.0
var _move_speed := 0.0
var _wp_pos := Vector3(1e9, 0, 0)  # waypoint watched by the never-stuck watchdog
var _best_d := INF
var _no_imp_t := 0.0
var _stuck := 0
var _backoff_t := 0.0
var _backoff := Vector3.ZERO
var _first_visit_done := false
var _visits := 0
var _patrol_t := 0.0
var _grace_t := 0.0
var _saw_hide := false
var _hide_spot_id := "closet"   # spot the player last hid in (closet, or the garderie tunnel)
var _door_busy := false
var _door_opened_by_me := false
var _door_was_locked := -1         # -1 unknown, 0 / 1
var _door_gen := 0
var _closet_opened_by_me := false
var _strip := 0.0
var _stress := -1.0
var _hum: Variant = null
var _hum_retry := 0.0
var _breath_t := 3.0
var _stair_sfx_t := -10.0
var _eyeshine := 0.1
var _debug_hold := {}              # {mode, t} while debug-placed
var _caught_sent := false
var _jump := {}                    # jumpscare scratch (empty = none)
var _sub := {}                     # per-state scratch
var _spot_hold := 0.0
var _summoned := false
var _face := Vector3.ZERO
var _cam_taken := false
var _cam_local0 := Transform3D.IDENTITY
var _flash_k := 1.0
# presentation (model interpolated between physics ticks)
var _phys_prev := Vector3.ZERO
var _phys_cur := Vector3.ZERO
var _yaw_prev := 0.0
var _yaw_cur := 0.0
# global watchdog (stall level)
var _stall_ref := Vector3.ZERO     # centre of the 0.6 m disc she has to leave
var _prog_t := 0.0                 # time spent in that disc while meaning to walk
var _free_t := 0.0                 # walking time since the last stall
var _unstick_n := 0
var _ghost_t := 0.0
var _ghost_ext := 0
# services
var _js_light: OmniLight3D = null
var _debug_light: OmniLight3D = null
var _shape: CapsuleShape3D = null
var _qparams := PhysicsShapeQueryParameters3D.new()
var _qshapes := {}
var _ray := PhysicsRayQueryParameters3D.new()
var _nodes: Array = []             # [{id, pos}] Layout.NAV_NODES at floor height
var _own_nav: AStar3D = null
var _quality_script: Script = null
var _dbg := {}
var _log_on := false
var _dbg_applied := false
var _quality_applied := false
var _ceiling_y: float = float(Layout.ROOM.ceilingY) + 0.45
var _bulk_z0: float = float(Layout.STAIRS.ceilingOpeningMaxZ)
var _bulk_y: float = float(Layout.ROOM.ceilingY) - 0.12

# ====================================================================== lifecycle

func build() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = LAYER_ENTITY
	collision_mask = LAYER_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var cs := CollisionShape3D.new()
	cs.name = "Capsule"
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = BODY_H - FOOT_CLEAR
	cs.shape = _shape
	cs.position.y = FOOT_CLEAR + _shape.height * 0.5
	add_child(cs)
	_parse_args()
	_build_nodes()
	for n in _nodes:
		if n.id == "hall": _home = n.pos
	_set_pos(_home, true)
	_disp_y = _home.y
	root.name = "Model"
	root.top_level = true
	add_child(root)
	model = Model.new()
	model.name = "GardienneModel"
	root.add_child(model)
	_place_root(0.0)
	await model.build(String(Settings.get_value("quality", "high")))
	model.footstep.connect(_on_footstep)
	# close fill light used only during the jumpscare (always present: no light-count change at the worst moment)
	_js_light = OmniLight3D.new()
	_js_light.name = "JumpscareFill"
	_js_light.top_level = true
	_js_light.light_color = JS_LIGHT_COLOR
	_js_light.light_energy = 0.0
	_js_light.omni_range = 3.0
	_js_light.omni_attenuation = 2.0   # inverse square (web decay 2; same calibration as the player's torch)
	_js_light.shadow_enabled = false
	_js_light.light_specular = 0.6
	add_child(_js_light)
	Events.noise.connect(_on_noise)
	Events.player_hide.connect(_on_hide)
	Events.game_state.connect(_on_game_state)
	Events.settings_changed.connect(_on_settings)
	_patrol_t = randf_range(90.0, 180.0)
	_place_root(0.0)
	root.visible = true             # visible while loading (pipelines compile), hidden once the game state settles
	_built = true
	_apply_visibility()
	if _dbg.has("noentity"): set_enabled(false)

func set_enabled(on: bool) -> void:
	if not on:
		_stop_sounds()
		enabled = false
		_set_state("disabled")
		active = false
		fear = 0.0
		root.visible = false
		_set_strip(0.0)
		_set_stress(0.0)
	elif not enabled or state == "disabled":
		enabled = true
		_set_pos(_home, true)
		_set_state("dormant")
		_apply_visibility()

func set_aggression(level: int) -> void:
	aggression = clampi(level, 0, 2)
	if aggression >= 2 and state == "dormant": _patrol_t = minf(_patrol_t, randf_range(18.0, 32.0))

## Scripted visit (e.g. breaker flipped): she comes down and searches around target.
func summon(target: Vector3, reason := "", aggressive := false) -> void:
	if not enabled or state == "disabled": return
	if aggressive: aggression = maxi(aggression, 1)
	var tgt := _floor_target(target)
	_summoned = true
	match state:
		"dormant": _wake(tgt, 3.6 if reason == "breaker" else randf_range(2.4, 3.4), reason if reason != "" else "script")
		"waking": _target = tgt
		"chasing", "jumpscare": pass
		_: _begin_search(tgt, true)

func reset_after_caught() -> void:
	_reset("caught")

func _reset(kind: String) -> void:
	_stop_sounds()
	_debug_hold = {}
	if model: model.debug_freeze = false
	_jump = {}
	_caught_sent = false
	if _js_light: _js_light.light_energy = 0.0
	_flash_k = 1.0
	if model: model.set_exposure(1.0)
	_quality_call("set_blur", [0.0])
	_release_camera()
	# put the house back the way she found it
	if _closet_opened_by_me:
		_closet_opened_by_me = false
		var cd = _handle("door.closet")
		if cd != null and cd.get("is_open") == true: _fire(cd, "close")
	_close_upstairs_door(true)
	suspicion = 0.0
	_saw_hide = false
	seeing = false
	_path.clear()
	_set_pos(_home, true)
	_disp_y = _home.y
	yaw = 0.0
	_yaw_prev = 0.0
	_yaw_cur = 0.0
	fear = 0.0
	if kind == "caught":
		_grace_t = 25.0
		_patrol_t = maxf(_patrol_t, randf_range(45.0, 80.0))
	_set_strip(0.0)
	_set_stress(0.0)
	if state != "disabled": _set_state("dormant")
	if model: model.reset_simulation()
	_place_root(0.0)
	_apply_visibility()

## Debug/test helper: freeze the AI and show her at a spot in a given animation mode (t >= 0: frozen frame time).
## look: null, a world point, or "camera" (she stares into the lens through the pose layer).
func debug_place(pos: Vector3, yaw_rad := 0.0, mode := "idle", t := -1.0, look: Variant = null) -> void:
	_stop_sounds()
	_debug_hold = {"mode": mode, "t": t, "jump_t": 0.0}
	if look != null: _debug_hold.look = look
	_set_pos(pos, true)
	_disp_y = pos.y
	yaw = yaw_rad
	_yaw_prev = yaw_rad
	_yaw_cur = yaw_rad
	if model:
		model.reset_simulation()
		if t >= 0.0: model.debug_pose(mode, t)
		else: model.debug_freeze = false
	root.visible = true
	_place_root(0.0)

func debug_release() -> void:
	_debug_hold = {}
	if model: model.debug_freeze = false
	_set_pos(_home, true)
	_apply_visibility()

## Fear module hook (scripts/fear/fear_glimpse.gd): a silent, AI-frozen apparition shown only while she sleeps upstairs.
## Her state stays "dormant" (no visit, no Events.entity_state, no sight / catch); end_glimpse() sends her home invisible.
## Refused (false) when she is awake, disabled, debug-placed or not built.
var glimpsing := false

func glimpse(pos: Vector3, yaw_rad := 0.0, mode := "idle", look: Variant = "camera") -> bool:
	if not _built or not enabled or state != "dormant" or not _debug_hold.is_empty() or Game.state != "playing":
		return false
	debug_place(pos, yaw_rad, mode, -1.0, look)
	glimpsing = true
	return true

func end_glimpse() -> void:
	if not glimpsing: return
	glimpsing = false
	if _debug_hold.is_empty() or state != "dormant": return   # released elsewhere (reset, debug): leave her be
	debug_release()

## Debug: jumpscare on the current camera now (freeze_t >= 0 holds that frame: screenshots).
func debug_jumpscare(freeze_t := -1.0) -> void:
	_debug_hold = {}
	if model: model.debug_freeze = false
	_start_jumpscare(false)
	if not _jump.is_empty() and freeze_t >= 0.0: _jump.freeze = freeze_t

func head_position() -> Vector3:
	return model.get_head_world() if model and root.visible else global_position + Vector3(0, 1.7, 0)

func eye_position() -> Vector3:
	return _eye_pos()

func face_position() -> Vector3:
	return model.get_face_world() if model else global_position + Vector3(0, 1.75, 0)

## Audio module hooks (entity-following sounds: hum, breath, steps).
func get_head_position() -> Vector3: return head_position()
func get_feet_position() -> Vector3: return global_position

# ====================================================================== main update

func _live() -> bool:
	var s := Game.state
	return s == "playing" or s == "caught" or s == "won"

func _physics_process(delta: float) -> void:
	if not _built or not _live(): return
	if state == "disabled" or not enabled:
		fear = 0.0
		return
	var dt := minf(delta, 0.05)
	_t += dt
	_state_t += dt
	if not _debug_hold.is_empty():
		_update_fear_and_stress(dt)
		return
	if _grace_t > 0.0: _grace_t -= dt
	_update_perception(dt)
	match state:
		"dormant": _upd_dormant(dt)
		"waking": _upd_waking(dt)
		"descending": _upd_descending(dt)
		"searching": _upd_searching(dt)
		"chasing": _upd_chasing(dt)
		"returning": _upd_returning(dt)
		_: pass   # jumpscare runs per rendered frame (_process)
	# speed / vertical motion bookkeeping
	var p := global_position
	var hs := Vector2(p.x - _prev_pos.x, p.z - _prev_pos.z).length() / maxf(dt, 1e-4)
	_move_speed = 0.0 if hs > 6.0 else _damp(_move_speed, hs, 10.0, dt)
	_vel_y = _damp(_vel_y, (p.y - _prev_pos.y) / maxf(dt, 1e-4), 6.0, dt)
	_prev_pos = p
	_phys_prev = _phys_cur
	_phys_cur = p
	_yaw_prev = _yaw_cur
	_yaw_cur = yaw
	_watchdog(dt)
	_update_fear_and_stress(dt)
	_update_audio(dt)

func _process(delta: float) -> void:
	if not _built: return
	if not _live():
		return
	if state == "disabled" or not enabled: return
	if not _debug_hold.is_empty():
		_debug_present(delta)
		return
	if state == "jumpscare":
		_upd_jumpscare(delta)
		return
	_place_root(delta)
	if root.visible and model:
		_animate(delta)
		_update_flash_exposure(delta)

# ====================================================================== states

func _set_state(s: String) -> void:
	var prev := state
	if prev == s: return
	state = s
	_state_t = 0.0
	active = not (s == "dormant" or s == "disabled")
	if s != "searching": _stop_hum()
	var p := global_position
	state_log.append({"t": snappedf(_t, 0.01), "state": s, "prev": prev, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]})
	if state_log.size() > 300: state_log.pop_front()
	if _log_on: print("[gardienne] %7.2f %s -> %s at (%.2f, %.2f, %.2f)" % [_t, prev, s, p.x, p.y, p.z])
	_apply_visibility()
	Events.entity_state.emit(s, prev)

func _apply_visibility() -> void:
	if not _debug_hold.is_empty():
		root.visible = true
		return
	if Game.state == "loading":
		root.visible = true   # pipeline warmup
		return
	root.visible = enabled and not (state == "dormant" or state == "waking" or state == "disabled")

func _wake(target: Vector3, duration: float, reason: String) -> void:
	_target = target
	suspicion = 0.0
	_visits += 1
	var R: Dictionary = Layout.ROOM
	var from := Vector3(clampf(target.x, float(R.minX) + 0.4, float(R.maxX) - 0.4), _ceiling_y, clampf(target.z, float(R.minZ) + 0.4, float(R.maxZ) - 0.4))
	_sub = {
		"reason": reason, "dur": duration, "step_t": 0.2, "step_i": 0,
		"from": from, "to": Vector3(-3.0, _ceiling_y, -2.4),
		"knock": reason == "breaker" or _visits == 1 or randf() < 0.45, "knocked": false, "walk": null,
	}
	# slow patrol: one continuous recorded walk across the floor above; urgent wakes: individual heavy steps
	if reason == "patrol" and duration >= 2.8:
		_sub.walk = _play("ceiling_walk", from, 0.9)
	_set_pos(_home, false)
	_set_state("waking")

func _upd_dormant(dt: float) -> void:
	_set_pos(_home, false)
	if _grace_t > 0.0:
		suspicion = minf(suspicion, SUSPICION_MAX * 0.5)
		return
	if suspicion < SUSPICION_MAX:
		suspicion = maxf(0.0, suspicion - dt * 0.06)
	else:
		suspicion = 0.0
		_wake(_floor_target(_last_noise), randf_range(2.2, 3.6), "noise")
		return
	if _first_visit_done:
		_patrol_t -= dt * (1.0 + aggression * 0.6)
		if _patrol_t <= 0.0:
			_patrol_t = _next_patrol_delay()
			var pl := _player()
			var tgt := _random_node_near(pl.global_position, 3.5) if pl else _random_node_near(_home, 8.0)
			_wake(_floor_target(tgt), randf_range(2.5, 4.0), "patrol")

func _next_patrol_delay() -> float:
	if aggression >= 2: return randf_range(45.0, 90.0)
	if aggression == 1: return randf_range(70.0, 140.0)
	return randf_range(90.0, 180.0)

func _upd_waking(dt: float) -> void:
	var s := _sub
	var k := clampf(_state_t / maxf(0.5, float(s.dur) - 0.9), 0.0, 1.0)
	s.step_t = float(s.step_t) - dt
	var from: Vector3 = s.from
	var to: Vector3 = s.to
	if s.walk != null:
		_snd(s.walk, "set_position", [from.lerp(to, k)])
		if k >= 1.0:
			_snd(s.walk, "stop", [0.6])
			s.walk = null
	elif float(s.step_t) <= 0.0 and k < 1.0:
		s.step_t = randf_range(0.55, 0.72)
		_play("ceiling_steps", from.lerp(to, k), 0.75 + 0.25 * k)
		s.step_i = int(s.step_i) + 1
	# behind the door: feet shadows in the light strip, maybe a knock
	if _state_t > float(s.dur) - 1.3: _set_strip(0.75 + 0.25 * sin(_t * 9.0))
	if s.knock and not s.knocked and _state_t > float(s.dur) - 1.0:
		s.knocked = true
		_play("knock_wall", DOOR_BEHIND, 0.9)
	if _state_t >= float(s.dur): _start_descending()

func _start_descending() -> void:
	_set_pos(_home, true)
	_disp_y = _home.y
	yaw = 0.0   # facing the door (south)
	_yaw_prev = yaw
	_yaw_cur = yaw
	if model: model.reset_simulation()
	_set_state("descending")
	_sub = {"phase": "door", "t": 0.0}
	_open_upstairs_door()
	_set_path(_target)

func _upd_descending(dt: float) -> void:
	var s := _sub
	if s.phase == "door":
		s.t = float(s.t) + dt
		_set_strip(0.5 if _door_busy else 0.0)
		if _door_busy and float(s.t) < 2.0: return   # wait for the door animation (with a safety timeout)
		s.phase = "walk"
		_set_strip(0.0)
	if seeing:
		_start_chase()
		return
	var on := _on_stairs()
	var arrived := _follow_path(STAIR_SPEED if on else WALK_SPEED, dt)
	# down in the basement, off the stairs -> searching
	if (global_position.y < 0.05 and not on) or arrived: _begin_search(_target, false)

func _begin_search(target: Vector3, reset: bool) -> void:
	var n := 3 + aggression + (1 if randf() < 0.5 else 0)
	var pts: Array[Vector3] = [_floor_target(target)]
	for i in n:
		for tries in 5:
			var c := _random_node_near(target, 3.5)
			var dup := false
			for q in pts:
				if q.distance_squared_to(c) < 0.5:
					dup = true
					break
			if not dup:
				pts.append(c)
				break
	var keep_t := float(_sub.get("total", 0.0)) if (not reset and state == "searching") else 0.0
	_sub = {"pts": pts, "i": 0, "phase": "go", "pause_t": 0.0, "total": keep_t, "max_t": 50.0 + aggression * 20.0, "closet": false}
	if state != "searching": _set_state("searching")
	_set_path(pts[0])

func _upd_searching(dt: float) -> void:
	var s := _sub
	s.total = float(s.total) + dt
	var pl := _player()
	if seeing:
		_start_chase()
		return
	# she saw the player slip into the closet: go straight for it
	if _saw_hide and pl and _p_hidden(pl) and not s.closet:
		s.closet = true
		s.phase = "closetGo"
		_set_path(_closet_approach())
	if s.phase == "closetGo" or s.phase == "closetReach":
		_upd_closet_check(dt)
		return
	if _hum == null:
		_hum_retry -= dt
		if _hum_retry <= 0.0: _start_hum()
	if s.phase == "go":
		if float(s.total) > float(s.max_t) + 10.0:
			_start_returning()
			return
		var arrived := _follow_path(WALK_SPEED * (1.0 + aggression * 0.06), dt)
		if arrived:
			s.phase = "pause"
			s.pause_t = randf_range(1.6, 3.4) + aggression * 0.4
			_on_search_pause()
	elif s.phase == "pause":
		s.pause_t = float(s.pause_t) - dt
		# slowly turn in place while listening
		yaw = wrapf(yaw + sin(_t * 0.7) * dt * 0.6, -PI, PI)
		if float(s.pause_t) <= 0.0:
			s.i = int(s.i) + 1
			var pts: Array = s.pts
			if int(s.i) >= pts.size() or float(s.total) > float(s.max_t):
				_start_returning()
				return
			s.phase = "go"
			_set_path(pts[int(s.i)])

func _on_search_pause() -> void:
	var pl := _player()
	var d := global_position.distance_to(pl.global_position) if pl else 99.0
	if pl and _p_hidden(pl) and d < 3.5 and randf() < 0.4:
		_play("whisper", head_position(), 0.75)
	elif d > 6.0 and randf() < 0.08:
		_play("giggle", global_position + Vector3(0, 1.2, 0), 0.5)

## The hide spot the player slipped into (world.hide_spots entry), {} when unknown.
func _hide_spot() -> Dictionary:
	var w = Game.world
	if w != null and is_instance_valid(w) and w.get("hide_spots") is Array:
		for sp in w.get("hide_spots"):
			if sp is Dictionary and str((sp as Dictionary).get("id", "")) == _hide_spot_id: return sp
	return {}

func _closet_approach() -> Vector3:
	var sp := _hide_spot()
	if sp.has("check_pos"): return sp["check_pos"]          # spots without a door (garderie tunnel)
	var c: Dictionary = Layout.CLOSET.door
	return Vector3(float(c.x) + 0.45, 0.0, float(c.centerZ))

func _check_yaw() -> float:
	return float(_hide_spot().get("check_yaw", -PI / 2.0))

func _upd_closet_check(dt: float) -> void:
	var s := _sub
	var ap := _closet_approach()
	if s.phase == "closetGo":
		_stop_hum()
		var arrived := _follow_path(WALK_SPEED * 1.15, dt)
		var dd := Vector2(global_position.x - ap.x, global_position.z - ap.z).length()
		if arrived or dd < 0.25:
			s.phase = "closetReach"
			s.reach_t = 0.0
			yaw = _check_yaw()   # facing the louvered door (or into the tunnel)
		return
	# reach for the door, open it, then the jumpscare
	s.reach_t = float(s.reach_t) + dt
	yaw = _damp(yaw, _check_yaw(), 8.0, dt)
	if float(s.reach_t) > 0.55 and not s.get("opened", false):
		s.opened = true
		var door = _handle("door.closet") if _hide_spot_id == "closet" else null
		if door != null and door.get("is_open") != true:
			_closet_opened_by_me = true
			_fire(door, "open")
	if float(s.reach_t) > 0.95:
		var pl := _player()
		if pl and _p_hidden(pl) and _player_spot_id(pl) == _hide_spot_id:
			_start_jumpscare(true)
		else:
			_saw_hide = false
			s.phase = "pause"
			s.pause_t = 1.0
			s.closet = false

func _start_chase() -> void:
	var first := state != "chasing"
	_set_state("chasing")
	_lost_t = 0.0
	_repath_t = 0.0
	_speed = 0.6
	if first:
		_spot_hold = 0.45
		Events.entity_spotted.emit()
		_play("entity_croak", head_position(), 1.0)
		_breath_t = 1.2

func _upd_chasing(dt: float) -> void:
	var pl := _player()
	if pl == null:
		_start_returning()
		return
	var pp := pl.global_position
	var hidden := _p_hidden(pl)
	if seeing:
		_lost_t = 0.0
	else:
		_lost_t += dt * (3.0 if (hidden and not _saw_hide) else 1.0)
		if _saw_hide and hidden:
			_begin_search(_last_seen, true)
			return
		if _lost_t > LOSE_TIME:
			_begin_search(_last_seen, true)
			return
	# freeze-and-stare moment when she first spots the player
	if _spot_hold > 0.0:
		_spot_hold -= dt
		yaw = _turn_toward(yaw, atan2(pp.x - global_position.x, pp.z - global_position.z), 9.0, dt)
		return
	var target := pp if seeing else _last_seen
	var top := CHASE_SPEED + (0.15 if aggression >= 2 else 0.0)
	_speed = minf(top, _speed + dt * 3.2)
	# caught?
	var p := global_position
	var dy := absf(pp.y - p.y)
	var dh := Vector2(pp.x - p.x, pp.z - p.z).length()
	if seeing and dh < CATCH_DIST and dy < 0.9 and not hidden:
		_start_jumpscare(false)
		return
	var direct := dy < 0.35 and not _on_stairs() and not _segment_blocked(p.x, p.z, target.x, target.z, RADIUS * 0.9, p.y + FOOT_CLEAR, p.y + BODY_H)
	if direct:
		_path.clear()
		_move_toward(target, _speed, dt, 7.0)
	else:
		_repath_t -= dt
		if _repath_t <= 0.0 or _path.is_empty():
			_repath_t = 0.7
			_set_path(target)
		_follow_path(minf(_speed, 2.1) if _on_stairs() else _speed, dt, 7.0)

func _start_returning() -> void:
	_set_state("returning")
	_sub = {"phase": "walk", "t": 0.0}
	_set_path(_home)

func _upd_returning(dt: float) -> void:
	var s := _sub
	if s.phase == "walk":
		if seeing:
			_start_chase()
			return
		var arrived := _follow_path(STAIR_SPEED if _on_stairs() else WALK_SPEED, dt)
		var p := global_position
		var at_hall := p.y > 2.5 and p.z < float(Layout.ROOM.minZ) - 0.45
		if arrived and not at_hall and p.distance_to(_home) > 0.8:
			_detour(_home)
			return
		# visit timeout: two minutes without reaching the hallway (never seen by the player meanwhile) -> she is home
		if _state_t > 120.0 and not seeing and not _player_sees_me():
			push_warning("[gardienne] returning timeout at %s: back home" % [p])
			_set_pos(_home, true)
			at_hall = true
		if arrived or at_hall:
			s.phase = "door"
			s.t = 0.0
			yaw = PI   # back to the hallway
			_close_upstairs_door(false)
		return
	s.t = float(s.t) + dt
	_set_strip(0.7 + 0.3 * sin(_t * 7.0) if float(s.t) < 1.6 else 0.0)
	if float(s.t) > 1.8 and (not _door_busy or float(s.t) > 3.5):
		_first_visit_done = true
		_patrol_t = maxf(_patrol_t, _next_patrol_delay() * (0.8 if _summoned else 1.0))
		_summoned = false
		_set_strip(0.0)
		_set_pos(_home, true)
		_set_state("dormant")

# ====================================================================== jumpscare

func _start_jumpscare(from_closet: bool) -> void:
	var pl := _player()
	var cam := Game.camera
	if Game.state != "playing":
		_start_returning()
		return
	var has_cam := cam != null and is_instance_valid(cam)
	_stop_sounds()
	_set_state("jumpscare")
	if pl:
		_cam_taken = true
		if has_cam: _cam_local0 = cam.transform
		pl.set("camera_override", true)
		pl.set("enabled", false)
	var cam_pos := cam.global_position if has_cam else _player_eye(pl) if pl else global_position + Vector3(0, 1.6, 1.0)
	# direction from the camera to her (horizontal)
	var dir := Vector3(global_position.x - cam_pos.x, 0.0, global_position.z - cam_pos.z)
	if dir.length_squared() < 1e-4:
		dir = -cam.global_basis.z if has_cam else Vector3.FORWARD
		dir.y = 0.0
	if dir.length_squared() < 1e-6: dir = Vector3.FORWARD
	dir = dir.normalized()
	var start_dist := 0.7 if from_closet else clampf(Vector2(global_position.x - cam_pos.x, global_position.z - cam_pos.z).length(), 0.6, 1.1)
	_jump = {
		"t": 0.0, "frames": 0, "from_closet": from_closet, "start_dist": start_dist, "cam_pos": cam_pos, "cam_y0": cam_pos.y,
		"dir": dir, "feet_y": pl.global_position.y if pl else global_position.y,
		"cam_q": cam.global_basis.orthonormalized().get_rotation_quaternion() if has_cam else Quaternion.IDENTITY,
		"yaw": atan2(-dir.x, -dir.z), "freeze": -1.0,
	}
	yaw = float(_jump.yaw)
	_play("jumpscare", null, 1.0)
	_quality_call("flash", [Color(0.478431, 0.043137, 0.019608), 0.35, 0.3])
	_quality_call("shake", [1.0, 1.3])
	_quality_call("set_blur", [0.16])
	root.visible = true
	if model: model.reset_simulation()

func _upd_jumpscare(dt: float) -> void:
	var j := _jump
	if j.is_empty(): return
	var cam := Game.camera
	var pl := _player()
	var frozen := float(j.freeze) >= 0.0
	if frozen: j.t = float(j.freeze)
	else: j.t = float(j.t) + dt
	var t := float(j.t)
	if pl and not _caught_sent:
		pl.set("camera_override", true)
		pl.set("enabled", false)
	var cam_pos: Vector3 = j.cam_pos
	# the player flinches upright (a crouched camera would stare at her chest)
	if not j.from_closet:
		cam_pos.y = lerpf(float(j.cam_y0), maxf(float(j.cam_y0), float(j.feet_y) + 1.42), _sstep01(t / 0.22))
	# her body: facing the camera, lunging from start_dist to point-blank, then hovering ~0.3 m from the lens
	var k := clampf(t / 0.16, 0.0, 1.0)
	var face_dist := lerpf(float(j.start_dist), 0.24, 1.0 - pow(1.0 - k, 3.0)) if t < 0.16 \
		else lerpf(0.24, 0.31, _sstep01((t - 0.16) / 0.5))
	yaw = float(j.yaw)
	var dir: Vector3 = j.dir
	root.global_transform = Transform3D(Basis(Vector3.UP, yaw), root.global_position)
	if model:
		model.mode = "jumpscare"
		model.speed = 0.0
		model.stairs = 0
		model.look_on = false
		model.jump_t = t
		model.aggression = aggression
		model.eyeshine_target = 1.0
		model.duck = 0.0
		model.update(0.0 if frozen else dt)
		var face := model.get_face_world()
		# desired face position: in front of the camera, eyes a little above the lens (she looms over)
		var want := cam_pos + dir * face_dist
		want.y = cam_pos.y + 0.03 + (0.0 if frozen else sin(t * 31.0) * 0.003)
		root.global_position += want - face
		_face = want
		j.frames = int(j.frames) + 1
	else:
		_face = global_position + Vector3(0, 1.7, 0)
	# camera: snaps to her face, trembling
	if cam != null and is_instance_valid(cam):
		var cp := cam_pos
		if not frozen:
			cp.x += (randf() - 0.5) * 0.006
			cp.y += (randf() - 0.5) * 0.006
		var to := _face - cp
		var q: Quaternion = j.cam_q
		if to.length_squared() > 1e-6:
			var want_q := Basis.looking_at(to, Vector3.UP).get_rotation_quaternion()
			q = want_q if frozen else q.slerp(want_q, 1.0 - exp(-30.0 * dt))
			j.cam_q = q
		cam.global_transform = Transform3D(Basis(q), cp)
		if model: _jump_lighting(t, cam)
	fear = 1.0
	if t > 1.4 and not _caught_sent and not frozen:
		_caught_sent = true
		Events.entity_caught.emit()

## Cold under-light from the torch spill + camera-style exposure so her face reads at point-blank range.
func _jump_lighting(t: float, cam: Camera3D) -> void:
	var face := _face
	# cold fill from below-left of the lens: cross-lights the face with the torch (from below-right)
	_js_light.global_position = cam.global_transform * Vector3(-0.13, -0.17, -0.03)
	var flick := 0.85 + 0.15 * sin(t * 43.0) * sin(t * 17.0)
	var js_i := 1.1 * flick * clampf(t / 0.05, 0.0, 1.0)     # web candela
	_js_light.light_energy = js_i / PI                          # Godot energy (x PI in the BRDF normalisation)
	var ejs := js_i / maxf(0.01, _js_light.global_position.distance_squared_to(face))
	var target := 4.2
	model.set_exposure(clampf(target / maxf(target, _torch_irradiance(face) + ejs), 0.03, 1.0))

## Flashlight irradiance actually reaching a point, in the web's units (cd / m²: Godot energy x PI, see the player module's
## calibration), with Godot's own spot falloff: distance^-spot_attenuation inside the range window, cone 1 - rim^(1 / angle
## attenuation) (measured by the player module). 0 when the torch is off or missing.
func _torch_irradiance(p: Vector3) -> float:
	var pl := _player()
	var fl = pl.get("flashlight") if pl else null
	if not (fl is Dictionary) or not fl.get("on", false) or not (fl.get("light") is SpotLight3D): return 0.0
	var L := fl.light as SpotLight3D
	if not L.is_visible_in_tree() or L.light_energy <= 0.0: return 0.0
	var to := p - L.global_position
	var dist := maxf(0.1, to.length())
	var cs := to.dot(-L.global_basis.z.normalized()) / dist
	var cut := cos(deg_to_rad(L.spot_angle))
	if cs <= cut: return 0.0
	var rim := clampf((1.0 - cs) / maxf(1e-4, 1.0 - cut), 0.0, 1.0)
	var cone := 1.0 - pow(rim, 1.0 / maxf(L.spot_angle_attenuation, 0.01))
	var nd := dist / maxf(L.spot_range, 0.01)
	nd *= nd
	nd *= nd
	var win := maxf(1.0 - nd, 0.0)
	return L.light_energy * PI * cone * win * win * pow(dist, -L.spot_attenuation)

## Torch-lit at close range her pale skin and gown would clip to flat white: like a camera adapting, her albedo / specular
## are scaled down once the beam's irradiance on her face or chest passes FLASH_EXPO_T (floor FLASH_EXPO_MIN). The web did
## this only for the jumpscare; here it also keeps her bones and veins readable when the torch finds her 1-2 m away.
func _update_flash_exposure(dt: float) -> void:
	if model == null: return
	var e := 0.0
	if root.visible:
		e = maxf(_torch_irradiance(model.get_eye_world()), _torch_irradiance(global_position + Vector3(0, 1.25, 0)))
	var k := clampf(FLASH_EXPO_T / maxf(FLASH_EXPO_T, e), FLASH_EXPO_MIN, 1.0)
	_flash_k = k if dt <= 0.0 else _damp(_flash_k, k, 4.0, dt)
	model.set_exposure(_flash_k)

func _release_camera() -> void:
	if not _cam_taken: return
	_cam_taken = false
	var pl := _player()
	if pl:
		if pl.get("camera_override") == true and pl.get("hidden") != true: pl.set("camera_override", false)
		pl.set("enabled", true)
	var cam := Game.camera
	if cam != null and is_instance_valid(cam): cam.transform = _cam_local0

# ====================================================================== perception

func _update_perception(dt: float) -> void:
	var s := state
	var can_look := s == "descending" or s == "searching" or s == "chasing" or s == "returning"
	if not can_look:
		seeing = false
		return
	_see_t -= dt
	if _see_t > 0.0: return
	_see_t = 0.08 if s == "chasing" else 0.12
	seeing = _can_see_player()
	if seeing:
		_last_seen = _player().global_position
		_last_seen_t = _t

func _can_see_player() -> bool:
	var pl := _player()
	if pl == null or _p_hidden(pl): return false
	if Game.state != "playing": return false
	var vis := 0.5
	if pl.has_method("get_visibility"): vis = float(pl.call("get_visibility"))
	vis = clampf(vis, 0.0, 1.0)
	if vis <= 0.01: return false
	var eye := _eye_pos()
	var pe := _player_eye(pl)
	var d := eye.distance_to(pe)
	var sense := 1.4
	if d > maxf(SIGHT_RANGE * vis, sense): return false
	if d > sense:
		var fx := sin(yaw)
		var fz := cos(yaw)
		var dx := pe.x - eye.x
		var dz := pe.z - eye.z
		var l := sqrt(dx * dx + dz * dz)
		if l < 1e-6: l = 1.0
		if (dx * fx + dz * fz) / l < FOV_COS: return false
	if not _line_blocked(eye, pe): return true
	return not _line_blocked(eye, pl.global_position + Vector3(0, 1.0, 0))

## Is she on the player's screen (in front of the camera, unobstructed)? Used by the never-stuck fallbacks only.
func _player_sees_me() -> bool:
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam) or not root.visible: return false
	var h := global_position + Vector3(0, 1.2, 0)
	if cam.is_position_behind(h): return false
	var to := h - cam.global_position
	if to.length() > 14.0: return false
	if (-cam.global_basis.z).dot(to.normalized()) < 0.5: return false
	return not _line_blocked(cam.global_position, h)

func _eye_pos() -> Vector3:
	if model and root.visible: return model.get_eye_world()
	return Vector3(global_position.x + sin(yaw) * 0.12, global_position.y + 1.72, global_position.z + cos(yaw) * 0.12)

func _on_noise(pos: Vector3, loudness: float, _source: String) -> void:
	if not _built or not enabled or state == "disabled" or state == "jumpscare": return
	var lv := clampf(loudness, 0.0, 1.0)
	var agg: float = [1.0, 1.4, 2.0][clampi(aggression, 0, 2)]
	if state == "waking":
		if lv >= 0.12: _target = _floor_target(pos)
		return
	if state == "dormant":
		if lv < 0.12: return
		var d := DOOR_EAR.distance_to(pos)
		var fall := clampf(1.35 - d / 8.0, 0.35, 1.3)
		var gain := agg * (1.0 if _first_visit_done else 0.7)
		suspicion += (lv - 0.1) * 0.9 * fall * gain * randf_range(0.8, 1.2)
		_last_noise = pos
		if lv >= 0.95 and _grace_t <= 0.0: suspicion = SUSPICION_MAX
		return
	if state == "chasing": return
	if state == "returning" and (_sub.get("phase") == "door" or global_position.y > float(Layout.UPPER.floorY) - 0.3):
		# already on the landing / in the hallway, closing the door: she comes back only for a real noise
		if lv >= 0.3:
			_last_noise = pos
			suspicion = minf(SUSPICION_MAX, suspicion + lv * 0.5)
		return
	# in the basement: does she hear it from where she is?
	var dd := global_position.distance_to(pos)
	var heard := lv * (1.0 / (1.0 + dd * dd / 10.0)) * agg
	if heard > 0.05 and lv >= 0.08:
		_last_noise = pos
		if state == "descending":
			_target = _floor_target(pos)
			_set_path(_target)
		else:
			_begin_search(pos, false)

func _player_spot_id(pl: Node) -> String:
	var hs = pl.get("hide_spot")
	return str((hs as Dictionary).get("id", "closet")) if hs is Dictionary else _hide_spot_id

func _on_hide(hidden: bool, spot_id: String) -> void:
	if hidden:
		_hide_spot_id = spot_id if spot_id != "" else "closet"
		var recently := _t - _last_seen_t < 1.3
		_saw_hide = active and state != "returning" and (recently or seeing) and state != "jumpscare"
	else:
		_saw_hide = false

func _on_game_state(s: String, _prev: String) -> void:
	_apply_visibility()
	if s == "playing" and not _quality_applied and model:
		_quality_applied = true   # Quality.apply() ran after build(): pick the preset's MSAA / TAA up now
		model.apply_quality(String(Settings.get_value("quality", "high")))
	if s == "playing" and not _dbg_applied and not _dbg.is_empty():
		_dbg_applied = true
		_apply_debug_args()

func _on_settings(key: String, v: Variant) -> void:
	if key == "quality" and model:
		await get_tree().process_frame   # the look module applies the preset to the viewport first
		if is_instance_valid(model): model.apply_quality(String(v))
	elif key == "upscale" and model:
		await get_tree().process_frame   # FSR 2 on/off switches the viewport's AA path
		if is_instance_valid(model): model.refresh_aa()

# ====================================================================== movement

func _floor_target(p: Vector3) -> Vector3:
	var t := Vector3(p.x, 0.0, p.z)
	var prev_y := float(Layout.UPPER.floorY) if p.y > 2.0 else 0.0
	t.y = _ground(t.x, t.z, prev_y)
	# pull targets that sit inside furniture/walls toward the nearest nav node
	var n := _nearest_node_pos(t)
	for i in 25:
		if not _segment_blocked(t.x, t.z, t.x, t.z, RADIUS, t.y + FOOT_CLEAR, t.y + BODY_H): break
		t = t.lerp(n, 0.15)
	return t

func _set_path(dest: Vector3) -> void:
	var p := global_position
	_path = _nav_path(p, dest)
	_path_i = 0
	# A* starts at the nearest node, which is often the one she just walked past: drop leading waypoints that lie behind
	# her when the next one is reachable in a straight line (no back-and-forth while chasing / repathing)
	while _path_i < _path.size() - 1:
		var a := _path[_path_i]
		var b := _path[_path_i + 1]
		if absf(b.y - p.y) > 0.25 or absf(a.y - p.y) > 0.25: break
		var behind := Vector2(b.x - p.x, b.z - p.z).length() < Vector2(b.x - a.x, b.z - a.z).length() + 0.15
		var r := RADIUS * (0.75 if behind else 0.9)
		if not _segment_blocked(p.x, p.z, b.x, b.z, r, p.y + FOOT_CLEAR, p.y + BODY_H): _path_i += 1
		else: break
		if not behind: break
	# the progress watchdog keeps running when a repath keeps the same waypoint (see _follow_path)

## Follow the current path. Returns true when the last waypoint is reached (or proved unreachable).
func _follow_path(spd: float, dt: float, turn_rate := 3.2) -> bool:
	if _path.is_empty(): return true
	var p := global_position
	while _path_i < _path.size():
		var w := _path[_path_i]
		var last := _path_i == _path.size() - 1
		if Vector2(w.x - p.x, w.z - p.z).length() < (0.3 if last else 0.32): _path_i += 1
		else: break
	if _path_i >= _path.size(): return true
	# shortcut to the next waypoint when the straight line is free and on the same level
	if _path_i + 1 < _path.size():
		var nx := _path[_path_i + 1]
		if absf(nx.y - p.y) < 0.2 and absf(_path[_path_i].y - p.y) < 0.2 and not _on_stairs() \
				and not _segment_blocked(p.x, p.z, nx.x, nx.z, RADIUS * 0.95, p.y + FOOT_CLEAR, p.y + BODY_H):
			_path_i += 1
	var wp := _path[_path_i]
	# never-stuck: watch progress toward the current waypoint (survives repaths that keep the same waypoint)
	if absf(wp.x - _wp_pos.x) + absf(wp.z - _wp_pos.z) > 0.03:
		_wp_pos = wp
		_best_d = INF
		_no_imp_t = 0.0
		_stuck = 0
	var d := Vector2(wp.x - p.x, wp.z - p.z).length()
	if d < _best_d - 0.05:
		_best_d = d
		_no_imp_t = 0.0
	elif _backoff_t <= 0.0:
		_no_imp_t += dt
	if _no_imp_t > 1.1:
		_no_imp_t = 0.0
		_best_d = d
		_stuck += 1
		_start_backoff(wp)
		if _stuck >= 3:
			if _path_i < _path.size() - 1: _path_i += 1   # skip an unreachable waypoint
			else:
				_path.clear()                                # goal unreachable: treat as reached
				return true
	_move_toward(wp, spd, dt, turn_rate)
	return false

func _move_toward(target: Vector3, spd: float, dt: float, turn_rate := 3.2) -> void:
	if _backoff_t > 0.0:
		_backoff_t -= dt
		_move_circle(_backoff.x * dt, _backoff.z * dt)
		return
	var p := global_position
	var dx := target.x - p.x
	var dz := target.z - p.z
	var d := sqrt(dx * dx + dz * dz)
	if d < 1e-3: return
	dx /= d
	dz /= d
	var want := atan2(dx, dz)
	yaw = _turn_toward(yaw, want, turn_rate, dt)
	# slow down when facing away (no moonwalking), accelerate into the turn
	var face := cos(wrapf(want - yaw, -PI, PI))
	var sp := spd * clampf(0.35 + 0.65 * face, 0.2, 1.0)
	var step := minf(d, sp * dt)
	_move_circle(dx * step, dz * step)

## Slide the capsule by (dx, dz) against LAYER_WORLD (Jolt), then put her feet on the walkable surface.
func _move_circle(dx: float, dz: float) -> void:
	var before := global_position
	var pdt := get_physics_process_delta_time()
	velocity = Vector3(dx, 0.0, dz) / maxf(pdt, 1e-4)
	move_and_slide()
	velocity = Vector3.ZERO
	var p := global_position
	p.y = _ground(p.x, p.z, before.y)
	global_position = p

## Step back (and a little sideways) away from whatever blocks the way to `toward`.
func _start_backoff(toward: Vector3) -> void:
	var dx := toward.x - global_position.x
	var dz := toward.z - global_position.z
	var l := sqrt(dx * dx + dz * dz)
	if l < 1e-6: l = 1.0
	dx /= l
	dz /= l
	var side := 1.0 if randf() < 0.5 else -1.0
	_backoff = Vector3(-dx * 0.6 - dz * side * 0.7, 0.0, -dz * 0.6 + dx * side * 0.7)
	_backoff_t = 0.4

## Re-route through a random nearby node (teleport-free fallback when a goal can't be reached directly).
func _detour(goal: Variant) -> void:
	var p := global_position
	var alt := _random_node_near(p, 2.5, p.y < 1.0)
	_path = _nav_path(p, alt)
	if goal is Vector3:
		var rest := _nav_path(alt, goal)
		for i in range(1, rest.size()): _path.append(rest[i])
	_path_i = 0
	_wp_pos = Vector3(1e9, 0, 0)

func _turn_toward(cur: float, want: float, rate: float, dt: float) -> float:
	var d := wrapf(want - cur, -PI, PI)
	var mx := rate * dt
	return wrapf(cur + clampf(d, -mx, mx), -PI, PI)

func _on_stairs() -> bool:
	var p := global_position
	var S: Dictionary = Layout.STAIRS
	return p.x >= float(S.minX) - 0.05 and p.x <= float(S.maxX) + 0.05 and p.z <= float(S.bottomZ) + 0.05 \
		and p.z > float(S.topZ) - 0.05 and p.y > 0.05 and p.y < float(Layout.UPPER.floorY) - 0.02

## Global never-stuck watchdog, on top of the web's per-waypoint one (whose backoffs make her oscillate and whose "goal
## unreachable = reached" hops from goal to goal). A stall = she means to walk but has not left a 0.6 m disc for 4 s.
## Each stall raises the level, which only falls back to 0 after 8 s of free walking: 1-2 -> back off + detour through
## another nav node; 3 -> squeeze through for 1.5 s without collisions; 4 -> give the goal up (next search point, or search
## where she stands). She is never left stuck, whatever the level geometry does.
func _watchdog(dt: float) -> void:
	if _ghost_t > 0.0:
		_ghost_t -= dt
		if _ghost_t <= 0.0:
			var p := global_position
			# still inside something: keep squeezing a little longer (bounded)
			if _segment_blocked(p.x, p.z, p.x, p.z, RADIUS * 0.8, p.y + FOOT_CLEAR, p.y + BODY_H) and _ghost_ext < 8:
				_ghost_t = 0.4
				_ghost_ext += 1
			else:
				collision_mask = LAYER_WORLD
	if not _wants_to_move():
		_prog_t = 0.0
		_stall_ref = global_position
		return
	var goal := _watch_goal()
	if global_position.distance_to(_stall_ref) > 0.6:
		_free_t += _prog_t
		if _free_t > 8.0: _unstick_n = 0
		_stall_ref = global_position
		_prog_t = 0.0
		return
	_prog_t += dt
	if _prog_t < 4.0: return
	_prog_t = 0.0
	_free_t = 0.0
	_unstick_n += 1
	stall_events += 1
	if _log_on: print("[gardienne] %7.2f watchdog: stalled in %s (level %d) at %s, goal %s" % [_t, state, _unstick_n, global_position, goal])
	match _unstick_n:
		1, 2:
			_start_backoff(_path[_path_i] if _path_i < _path.size() else goal)
			if state == "chasing": _repath_t = 0.0
			else: _detour(goal)
		3:
			collision_mask = 0
			_ghost_t = 1.5
			_ghost_ext = 0
			_set_path(goal)
		_:
			_unstick_n = 0
			match state:
				"searching":
					if _sub.get("phase") == "go": _path.clear()   # counts as arrived: pause, then the next point
				"descending": _begin_search(global_position, true)
				"returning": _detour(_home)
				"chasing": _begin_search(_last_seen, true)

func _watch_goal() -> Vector3:
	if state == "chasing":
		var pl := _player()
		return (pl.global_position if seeing and pl else _last_seen)
	if not _path.is_empty(): return _path[_path.size() - 1]
	return global_position

func _wants_to_move() -> bool:
	match state:
		"descending": return _sub.get("phase") == "walk"
		"searching": return _sub.get("phase") == "go" or _sub.get("phase") == "closetGo"
		"chasing": return _spot_hold <= 0.0
		"returning": return _sub.get("phase") == "walk"
	return false

func _set_pos(p: Vector3, snap: bool) -> void:
	global_position = p
	if snap:
		_prev_pos = p
		_phys_prev = p
		_phys_cur = p

# ====================================================================== presentation

func _place_root(dt: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var p := _phys_cur
	if _phys_prev.distance_squared_to(_phys_cur) < 1.0: p = _phys_prev.lerp(_phys_cur, f)
	# smooth the step-wise stair height into a ramp
	if dt <= 0.0 or absf(p.y - _disp_y) > 1.2: _disp_y = p.y
	else: _disp_y = _damp(_disp_y, p.y, 9.0, dt)
	var y := lerp_angle(_yaw_prev, _yaw_cur, f)
	root.global_transform = Transform3D(Basis(Vector3.UP, y), Vector3(p.x, _disp_y, p.z))

func _animate(dt: float) -> void:
	var m := model
	var md := "walk"
	var ph: String = String(_sub.get("phase", ""))
	match state:
		"chasing": md = "search" if _spot_hold > 0.0 else "chase"
		"searching": md = "search" if ph == "pause" else ("reach" if ph == "closetReach" else "walk")
		"returning": if ph == "door": md = "reach"
		"descending": if ph == "door": md = "idle"
	m.mode = md
	m.speed = _move_speed
	m.stairs = (1 if _vel_y > 0.05 else (-1 if _vel_y < -0.05 else 0)) if _on_stairs() else 0
	m.aggression = aggression
	var pl := _player()
	if pl and (state == "chasing" or _t - _last_seen_t < 1.5):
		m.look_on = true
		m.look_target = _player_eye(pl)
	else:
		m.look_on = false
	m.jump_t = -1.0
	m.eyeshine_target = _eyeshine
	m.duck = _duck_amount()
	m.update(dt)

## 0..1: how far she must duck under the drywall bulkhead at the bottom of the stairwell (she is 1.98 m tall).
func _duck_amount() -> float:
	var p := global_position
	if p.x > float(Layout.STAIRS.maxX) + 0.2 or p.y < 0.05: return 0.0
	var hz := p.z + cos(yaw) * 0.12   # her head is a little ahead of her feet
	var bz1 := _bulk_z0 + 0.15
	var dz := (_bulk_z0 - hz) if hz < _bulk_z0 else ((hz - bz1) if hz > bz1 else 0.0)
	var near := clampf(1.0 - (dz - 0.1) / 0.55, 0.0, 1.0)
	return near * clampf((_disp_y + 2.02 - _bulk_y) / 0.22, 0.0, 1.0)

func _debug_present(dt: float) -> void:
	var h := _debug_hold
	_place_root(0.0)
	root.visible = true
	if model == null: return
	_update_flash_exposure(0.0 if float(h.t) >= 0.0 else dt)
	# optional stare: h.look = a world point, or "camera" (she looks into the lens)
	var lk = h.get("look")
	var cam := Game.camera
	model.look_on = lk is Vector3 or (lk is String and cam != null and is_instance_valid(cam))
	if lk is Vector3: model.look_target = lk
	elif model.look_on: model.look_target = cam.global_position
	if float(h.t) >= 0.0:
		model.eyeshine_target = _eyeshine
		model.update(0.0)   # frozen frame (debug_pose already set every weight / clip time)
		return
	var md := String(h.mode)
	var walking := md in ["walk", "duck_walk", "stairs_up", "stairs_down", "stairs_duck"]
	model.mode = "walk" if walking else md
	model.speed = 0.9 if walking else (2.9 if md == "chase" else 0.0)
	model.stairs = 1 if md == "stairs_up" else (-1 if md in ["stairs_down", "stairs_duck"] else 0)
	model.duck = 1.0 if md in ["duck_walk", "stairs_duck"] else 0.0
	model.aggression = aggression
	model.eyeshine_target = _eyeshine
	if md == "jumpscare":
		h.jump_t = float(h.jump_t) + dt
		model.jump_t = float(h.jump_t)
	else:
		model.jump_t = -1.0
	model.update(dt)

func _update_fear_and_stress(_dt: float) -> void:
	var s := state
	var f := 0.0
	var stress := 0.0
	var pl := _player()
	if pl and s != "dormant" and s != "disabled":
		var d := global_position.distance_to(pl.global_position)
		var near := clampf(1.0 - d / 7.0, 0.0, 1.0)
		match s:
			"waking":
				f = 0.18
				stress = 0.2
			"descending": f = 0.32 + 0.4 * near
			"searching": f = 0.25 + 0.5 * near + (0.15 if seeing else 0.0)
			"chasing": f = 0.75 + 0.25 * clampf(1.0 - d / 6.0, 0.0, 1.0)
			"returning": f = 0.15 + 0.35 * near
			"jumpscare": f = 1.0
		if _p_hidden(pl) and s == "searching": f = minf(1.0, f + 0.1 * near)
		if s != "waking": stress = clampf(1.0 - d / 5.0, 0.0, 1.0) * (1.0 if root.visible else 0.4)
		# eyeshine: her pupils catch the flashlight beam
		var fl = pl.get("flashlight")
		var cam := Game.camera
		if fl is Dictionary and fl.get("on", false) and root.visible and model and cam != null and is_instance_valid(cam):
			var cdir := -cam.global_basis.z
			var to := model.get_eye_world() - cam.global_position
			var dd := to.length()
			if dd < 1e-4: dd = 1.0
			var cs := to.dot(cdir) / dd
			_eyeshine = clampf((cs - 0.92) / 0.06, 0.0, 1.0) * clampf(1.2 - dd / 10.0, 0.2, 1.0) if cs > 0.92 else 0.08
		else:
			_eyeshine = 0.08
	if s == "jumpscare": f = 1.0
	fear = clampf(f, 0.0, 1.0)
	if absf(stress - _stress) > 0.01 or (stress == 0.0 and _stress != 0.0): _set_stress(stress)

func _set_stress(v: float) -> void:
	_stress = v
	_lighting_call("set_stress", [v])

func _set_strip(v: float) -> void:
	if absf(v - _strip) < 0.02: return
	_strip = v
	_lighting_call("door_strip_occluded", [v])

# ====================================================================== doors

func _open_upstairs_door() -> void:
	var door = _handle("door.upstairs")
	if door == null or door.get("is_open") == true: return
	_door_was_locked = 1 if door.get("locked") == true else 0
	_door_opened_by_me = true
	_door_busy = true
	door.set("locked", false)
	_door_gen += 1
	_door_task(door, true, _door_gen)

func _close_upstairs_door(instant: bool) -> void:
	var door = _handle("door.upstairs")
	if door == null or not _door_opened_by_me: return
	_door_opened_by_me = false
	if _pflag("door_opened") or _pflag("won"): return   # the player opened it to escape: leave it
	if door.get("is_open") != true: return
	_door_busy = not instant
	_door_gen += 1
	_door_task(door, false, _door_gen)

func _door_task(door: Variant, open: bool, gen: int) -> void:
	if open:
		if door.has_method("open"): await door.open()
	else:
		if door.has_method("close"): await door.close()
	if gen != _door_gen: return
	_door_busy = false
	# keep the lock state the player knows about (gameplay may have unlocked it with the key meanwhile)
	if not _pflag("door_unlocked") and _door_was_locked >= 0: door.set("locked", _door_was_locked == 1)

## Fire-and-forget a Handle coroutine (closet door).
func _fire(h: Variant, method: String) -> void:
	if h != null and h.has_method(method): await h.call(method)

# ====================================================================== audio

func _on_footstep(_side: String, pos: Vector3) -> void:
	if not root.visible or state == "jumpscare" or state == "dormant": return
	var chase := state == "chasing"
	var nm := "entity_step"
	var p := global_position
	if _on_stairs() or (p.y > 0.1 and p.y < float(Layout.UPPER.floorY) - 0.05):
		if _t - _stair_sfx_t > 0.75:
			nm = "entity_step_stairs"
			_stair_sfx_t = _t
	_play(nm, pos, 1.0 if chase else 0.72, 1.08 if chase else 0.94 + randf() * 0.06)

func _update_audio(dt: float) -> void:
	if _hum != null: _snd(_hum, "set_position", [head_position()])
	var s := state
	if s == "descending" or s == "returning" or s == "chasing" or (s == "searching" and _hum == null):
		_breath_t -= dt
		if _breath_t <= 0.0:
			_breath_t = randf_range(1.6, 3.0) if s == "chasing" else randf_range(3.0, 6.0)
			_play("entity_breath", head_position(), 1.0 if s == "chasing" else 0.7)

func _start_hum() -> void:
	if _hum != null: return
	_hum = Audio.loop("lullaby_hum", {"position": head_position(), "volume_db": linear_to_db(0.75)})
	if _hum == null: _hum_retry = 5.0

func _stop_hum() -> void:
	if _hum == null: return
	_snd(_hum, "stop", [1.2])
	_hum = null

func _stop_sounds() -> void:
	_stop_hum()
	if _sub.get("walk") != null:
		_snd(_sub.walk, "stop", [0.3])
		_sub.walk = null

## Audio.play with the web's linear volume / rate. pos = null: non-positional.
func _play(sound: String, pos: Variant, volume := 1.0, rate := 1.0) -> Variant:
	var opts := {"volume_db": linear_to_db(maxf(volume, 0.0001))}
	if pos is Vector3: opts["position"] = pos
	if rate != 1.0: opts["pitch"] = rate
	return Audio.play(sound, opts)

## Calls a method on a sound handle (Object or Dictionary of Callables), ignoring dead handles.
func _snd(h: Variant, method: String, args: Array) -> void:
	if h == null: return
	if h is Object:
		if is_instance_valid(h) and (h as Object).has_method(method): (h as Object).callv(method, args)
	elif h is Dictionary and (h as Dictionary).get(method) is Callable:
		((h as Dictionary)[method] as Callable).callv(args)

# ====================================================================== world / player access (defensive)

func _player() -> Node3D:
	var pl = Game.player
	if pl != null and is_instance_valid(pl) and pl is Node3D: return pl
	return null

func _p_hidden(pl: Node) -> bool:
	return pl.get("hidden") == true

func _player_eye(pl: Node3D) -> Vector3:
	if pl.has_method("eye_position"):
		var e = pl.call("eye_position")
		if e is Vector3: return e
	return pl.global_position + Vector3(0, 1.6, 0)

func _handle(id: String) -> Variant:
	var w = Game.world
	if w == null or not is_instance_valid(w): return null
	var hs = w.get("handles")
	if hs is Dictionary: return (hs as Dictionary).get(id)
	return null

func _pflag(flag: String) -> bool:
	var pz = Game.puzzles
	if pz == null or not is_instance_valid(pz): return false
	var f = pz.get("flags")
	return f is Dictionary and (f as Dictionary).get(flag, false) == true

func _lighting_call(method: String, args: Array) -> void:
	var w = Game.world
	if w == null or not is_instance_valid(w): return
	var lt = w.get("lighting")
	if lt != null and is_instance_valid(lt) and lt.has_method(method): lt.callv(method, args)

func _quality_call(method: String, args: Array) -> void:
	if _quality_script == null: _quality_script = load("res://scripts/render/quality.gd")
	if _quality_script != null and _quality_script.has_method(method): _quality_script.callv(method, args)

func _ground(x: float, z: float, prev_y: float) -> float:
	var w = Game.world
	if w != null and is_instance_valid(w) and w.has_method("ground_height_at"): return float(w.ground_height_at(x, z, prev_y))
	return Layout.ground_height_at(x, z, prev_y)

func _line_blocked(a: Vector3, b: Vector3) -> bool:
	var w = Game.world
	if w != null and is_instance_valid(w) and w.has_method("line_blocked"): return bool(w.line_blocked(a, b))
	if not is_inside_tree(): return false
	_ray.from = a
	_ray.to = b
	_ray.collision_mask = LAYER_WORLD
	return not get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()

## True if the capsule (radius r, vertical span y_min..y_max) swept from (ax, az) to (bx, bz) hits LAYER_WORLD
## (web World.segmentBlocked; a zero-length segment tests the spot itself). Jolt shape cast.
func _segment_blocked(ax: float, az: float, bx: float, bz: float, r: float, y_min: float, y_max: float) -> bool:
	if not is_inside_tree(): return false
	var key := snappedf(r, 0.001)
	var sh: CapsuleShape3D = _qshapes.get(key)
	if sh == null:
		sh = CapsuleShape3D.new()
		sh.radius = r
		_qshapes[key] = sh
	sh.height = maxf(y_max - y_min, 2.0 * r + 0.01)
	_qparams.shape = sh
	_qparams.collision_mask = LAYER_WORLD
	_qparams.collide_with_areas = false
	_qparams.collide_with_bodies = true
	_qparams.transform = Transform3D(Basis.IDENTITY, Vector3(ax, (y_min + y_max) * 0.5, az))
	var m := Vector3(bx - ax, 0.0, bz - az)
	var space := get_world_3d().direct_space_state
	if m.length_squared() < 1e-6:
		_qparams.motion = Vector3.ZERO
		return not space.intersect_shape(_qparams, 1).is_empty()
	_qparams.motion = m
	var res := space.cast_motion(_qparams)
	return res.size() > 0 and res[0] < 0.999

# ---------------------------------------------------------------- navigation (world.nav_path; Layout fallback)

func _build_nodes() -> void:
	_nodes.clear()
	for id in Layout.NAV_NODES:
		var n: Dictionary = Layout.NAV_NODES[id]
		var y := float(Layout.UPPER.floorY) if n.get("upper", false) else Layout.ground_height_at(float(n.x), float(n.z))
		_nodes.append({"id": String(id), "pos": Vector3(float(n.x), y, float(n.z))})

func _nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var w = Game.world
	if w != null and is_instance_valid(w) and w.has_method("nav_path"):
		var p = w.nav_path(from, to)
		if p is PackedVector3Array and (p as PackedVector3Array).size() > 0: return p
		if p is Array and not (p as Array).is_empty(): return PackedVector3Array(p)
	if _own_nav == null:
		_own_nav = AStar3D.new()
		var ids := {}
		for i in _nodes.size():
			ids[_nodes[i].id] = i
			_own_nav.add_point(i, _nodes[i].pos)
		for l in Layout.NAV_LINKS: _own_nav.connect_points(ids[l[0]], ids[l[1]])
	var path := _own_nav.get_point_path(_nearest_node_idx(from), _nearest_node_idx(to))
	path.append(to)
	return path

## Nearest nav node (prefers the same floor level, like the web).
func _nearest_node_idx(pos: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in _nodes.size():
		var q: Vector3 = _nodes[i].pos
		var d := Vector2(q.x - pos.x, q.z - pos.z).length() + absf(q.y - pos.y) * 3.0
		if d < bd:
			bd = d
			best = i
	return best

func _nearest_node_pos(pos: Vector3) -> Vector3:
	return _nodes[_nearest_node_idx(pos)].pos if not _nodes.is_empty() else pos

## Random nav node position near a point (for searching), basement nodes only by default (web randomNodeNear).
func _random_node_near(pos: Vector3, radius := 3.0, lower_only := true) -> Vector3:
	var cands: Array[Vector3] = []
	var lower: Array[Vector3] = []
	for n in _nodes:
		var q: Vector3 = n.pos
		if q.y < 1.0: lower.append(q)
		if (not lower_only or q.y < 1.0) and Vector2(q.x - pos.x, q.z - pos.z).length() <= radius: cands.append(q)
	if cands.is_empty(): cands = lower
	if cands.is_empty(): return pos
	return cands[randi() % cands.size()]

# ====================================================================== debug args

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0].begins_with("entity") or kv[0] == "noentity":
			_dbg[kv[0]] = kv[1] if kv.size() > 1 else ""
	_log_on = _dbg.has("entity-log")

func _apply_debug_args() -> void:
	for i in 4: await get_tree().process_frame   # DebugTools applies --cam / --flashlight / --power first
	if _dbg.has("entity-aggression"): set_aggression(int(_dbg["entity-aggression"]))
	if _dbg.has("entity-noise"):
		var v := _floats(_dbg["entity-noise"])
		if v.size() >= 3:
			print("[gardienne] debug noise at (%.2f, %.2f, %.2f)" % [v[0], v[1], v[2]])
			Events.noise.emit(Vector3(v[0], v[1], v[2]), v[3] if v.size() > 3 else 1.0, "debug")
	if _dbg.has("entity-summon"):
		var v := _floats(_dbg["entity-summon"])
		if v.size() >= 2: summon(Vector3(v[0], 0.0, v[1]), "breaker")
	if _dbg.has("entity-light"): _add_debug_light()
	if _dbg.has("entity-place"):
		var parts: PackedStringArray = String(_dbg["entity-place"]).split(",")
		var v := _floats(_dbg["entity-place"])
		if v.size() >= 3:
			var md := parts[4] if parts.size() > 4 else "idle"
			debug_place(Vector3(v[0], v[1], v[2]), deg_to_rad(v[3]) if v.size() > 3 else 0.0, md,
				float(parts[5]) if parts.size() > 5 else -1.0, "camera" if parts.has("stare") else null)
	if _dbg.has("entity-front"):
		var parts: PackedStringArray = String(_dbg["entity-front"]).split(",")
		var dist := float(parts[0]) if parts.size() > 0 and parts[0] != "" else 2.0
		_place_in_front(dist, parts[1] if parts.size() > 1 else "idle", float(parts[2]) if parts.size() > 2 else -1.0, parts.has("stare"))
	if _dbg.has("entity-jumpscare"):
		var ft := float(_dbg["entity-jumpscare"]) if String(_dbg["entity-jumpscare"]) != "" else -1.0
		if not _dbg.has("entity-front"): _place_in_front(1.0, "chase", -1.0)
		debug_jumpscare(ft)

func _place_in_front(dist: float, md: String, t: float, stare := false) -> void:
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam): return
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD
	var p := cam.global_position + f * dist
	p.y = _ground(p.x, p.z, cam.global_position.y - 1.5)
	debug_place(p, atan2(-f.x, -f.z), md, t, "camera" if stare else null)

## Lookdev helper (--entity-light): a warm key light 1.6 m in front of her at head height + a dim cool rim behind.
func _add_debug_light() -> void:
	if _debug_light != null: return
	_debug_light = OmniLight3D.new()
	_debug_light.name = "EntityDebugKey"
	_debug_light.light_color = Color(1.0, 0.86, 0.7)
	_debug_light.light_energy = 1.6
	_debug_light.omni_range = 6.0
	_debug_light.shadow_enabled = true
	root.add_child(_debug_light)
	_debug_light.position = Vector3(0.7, 2.1, 1.4)

func _floats(s: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x in s.split(","):
		if x.is_valid_float(): out.append(float(x))
	return out

func _damp(cur: float, target: float, rate: float, dt: float) -> float:
	return cur + (target - cur) * (1.0 - exp(-rate * dt))

func _sstep01(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
