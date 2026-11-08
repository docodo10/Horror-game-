## La Gardienne — procedural pose layer applied on top of the AnimationTree output (SkeletonModifier3D, runs after the
## mixer every frame, from the freshly animated pose, so nothing accumulates). Port of the parts of
## src/entity/GardienneModel.js that the exporter could not bake into the clips:
##   * look-at: absolute aim of the face at a world target (the player's eyes), spread over chest / neck / head (the web
##     split: the chest counter-twists a little, the head does most of it), limited to ±66° yaw, -40°..+34° pitch;
##   * glitches: head snaps (yaw + roll, neck roll) and left-arm spasms (the "frame skip" freezes are done by the model,
##     which simply stops advancing the tree).
## Driven by gardienne_model.gd (look_w / look_target / snap_* / spasm_*); owned by the entity module.
extends SkeletonModifier3D

const YAW_LIMIT := 1.15
const PITCH_DOWN := -0.7
const PITCH_UP := 0.6
# share of the yaw / pitch correction per bone (sum = 1: the face really reaches the target)
const YAW_SPLIT := {"chest": -0.12, "neck": 0.45, "head": 0.67}
const PITCH_SPLIT := {"neck": 0.3, "head": 0.7}

var look_w := 0.0                 # 0..1 (smoothed by the model)
var look_target := Vector3.ZERO   # world space
var pitch_gain := 0.85            # keep a little of her stoop even when she stares
var snap_yaw := 0.0               # glitch head snap (0 = off)
var snap_roll := 0.0
var spasm := 0.0                  # glitch arm spasm amount (sin wave, 0 = off)
var spasm_chest := 0.0

var _ids := {}
var _ok := false

func setup(sk: Skeleton3D) -> void:
	_ids.clear()
	for n in ["spine2", "chest", "neck", "head", "armL", "foreL", "clavL"]:
		_ids[n] = sk.find_bone(n)
	_ok = not _ids.values().has(-1)
	if not _ok:
		push_warning("[gardienne] pose layer: missing bones %s" % [_ids])

func _process_modification_with_delta(_delta: float) -> void:
	if not _ok: return
	var sk := get_skeleton()
	if sk == null: return
	if look_w > 0.001: _apply_look(sk)
	if snap_yaw != 0.0 or snap_roll != 0.0:
		var h: int = _ids.head
		sk.set_bone_pose_rotation(h, sk.get_bone_pose_rotation(h) * Quaternion.from_euler(Vector3(0.0, snap_yaw, snap_roll)))
		var nk: int = _ids.neck
		sk.set_bone_pose_rotation(nk, sk.get_bone_pose_rotation(nk) * Quaternion(Vector3.BACK, snap_roll * 0.3))
	if spasm != 0.0:
		# web: armL.x += j; foreL.x -= 0.8 j; clavL.z += 0.2; chest.y += sin(t*47)*0.08 (Euler XYZ: x pre-, y/z post-multiplied)
		var a: int = _ids.armL
		sk.set_bone_pose_rotation(a, Quaternion(Vector3.RIGHT, spasm) * sk.get_bone_pose_rotation(a))
		var f: int = _ids.foreL
		sk.set_bone_pose_rotation(f, Quaternion(Vector3.RIGHT, -spasm * 0.8) * sk.get_bone_pose_rotation(f))
		var c: int = _ids.clavL
		sk.set_bone_pose_rotation(c, sk.get_bone_pose_rotation(c) * Quaternion(Vector3.BACK, 0.2))
		var ch: int = _ids.chest
		sk.set_bone_pose_rotation(ch, sk.get_bone_pose_rotation(ch) * Quaternion(Vector3.UP, spasm_chest))

func _apply_look(sk: Skeleton3D) -> void:
	var head_g := sk.get_bone_global_pose(_ids.head)
	var eye := head_g * Vector3(0.0, 0.08, 0.05)
	var t := sk.global_transform.affine_inverse() * look_target
	var d := t - eye
	var dh := Vector2(d.x, d.z).length()
	if dh < 0.05: return
	var fwd := (head_g.basis * Vector3.BACK).normalized()   # the face looks down the head bone's +Z
	var want_yaw := clampf(atan2(d.x, d.z), -YAW_LIMIT, YAW_LIMIT)
	var want_pitch := clampf(atan2(d.y, dh), PITCH_DOWN, PITCH_UP)
	var cur_yaw := atan2(fwd.x, fwd.z)
	var cur_pitch := atan2(fwd.y, Vector2(fwd.x, fwd.z).length())
	var dyaw := wrapf(want_yaw - cur_yaw, -PI, PI) * look_w
	var dpitch := (want_pitch - cur_pitch) * look_w * pitch_gain
	# rotation axes in skeleton space: vertical for the yaw, the target's horizontal "right" for the pitch
	var right := Vector3.UP.cross(Vector3(sin(want_yaw), 0.0, cos(want_yaw))).normalized()
	# parents' ORIGINAL global bases (read before any change: each bone is rotated in its parent's frame)
	var pb := {}
	for n in ["chest", "neck", "head"]:
		pb[n] = sk.get_bone_global_pose(sk.get_bone_parent(_ids[n])).basis.orthonormalized()
	for n in ["chest", "neck", "head"]:
		var id: int = _ids[n]
		var inv: Basis = (pb[n] as Basis).inverse()
		var q := sk.get_bone_pose_rotation(id)
		var yw: float = YAW_SPLIT.get(n, 0.0) * dyaw
		if yw != 0.0: q = Quaternion((inv * Vector3.UP).normalized(), yw) * q
		var pw: float = PITCH_SPLIT.get(n, 0.0) * dpitch
		# positive pitch = face up = rotation about the right axis by -pitch (web: head.x -= lookPitch)
		if pw != 0.0: q = Quaternion((inv * right).normalized(), -pw) * q
		sk.set_bone_pose_rotation(id, q.normalized())
