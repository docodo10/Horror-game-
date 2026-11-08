## STUB — player module replaces it (ARCHITECTURE_PC.md §Player). CharacterBody3D with a camera; WASD only.
## Public API (keep): camera: Camera3D, yaw, pitch, crouched, sprinting, stamina, hidden, hide_spot, enabled, camera_override,
##   flashlight: {has, on, battery, light: SpotLight3D}; give_flashlight(); set_flashlight_on(on); add_battery(amount := 60.0)
##   enter_hide(spot) / exit_hide() (await); respawn(); teleport(pos: Vector3, yaw: float, pitch := 0.0); get_visibility() -> float;
##   eye_position() -> Vector3; flinch(strength := 1.0); reset_after_caught()
extends CharacterBody3D

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 4; collision_mask = 1
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.25; cap.height = 1.75; cs.shape = cap; cs.position.y = 0.875; add_child(cs)
	camera.position.y = 1.62; camera.current = true; add_child(camera)
	camera.add_child(flashlight.light)
	respawn()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and enabled:
		yaw -= e.relative.x * 0.0022; pitch = clampf(pitch - e.relative.y * 0.0022, -1.4, 1.4)

func _physics_process(delta: float) -> void:
	if not enabled: return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (Basis(Vector3.UP, yaw) * Vector3(v.x, 0, v.y)) * 1.9
	velocity.x = dir.x; velocity.z = dir.z
	velocity.y -= 9.8 * delta
	move_and_slide()
	if not camera_override: camera.rotation = Vector3(pitch, 0, 0); rotation.y = yaw

func give_flashlight() -> void: flashlight.has = true
func set_flashlight_on(on: bool) -> void: flashlight.on = on; flashlight.light.light_energy = 4.0 if on else 0.0
func add_battery(a := 60.0) -> void: flashlight.battery = minf(100.0, flashlight.battery + a)
func enter_hide(spot) -> void: hidden = true; hide_spot = spot; Events.player_hide.emit(true, spot.get("id", ""))
func exit_hide() -> void: hidden = false; hide_spot = null; Events.player_hide.emit(false, "")
func respawn() -> void: teleport(Vector3(Layout.SPAWN.x, 0.05, Layout.SPAWN.z), Layout.SPAWN.yaw)
func teleport(pos: Vector3, y: float, p := 0.0) -> void: global_position = pos; yaw = y; pitch = p
func get_visibility() -> float: return 0.0 if hidden else 0.6
func eye_position() -> Vector3: return camera.global_position
func flinch(_s := 1.0) -> void: pass
func reset_after_caught() -> void: respawn()
