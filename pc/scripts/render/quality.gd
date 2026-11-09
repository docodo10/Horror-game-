## Look module (ARCHITECTURE_PC.md §4 Look) — graphics presets + the "camera" API. Port of src/render/Renderer.js +
## src/render/PostFX.js on Godot's renderer: WorldEnvironment (AgX, SDFGI, SSIL, SSAO, SSR, volumetric fog, glow),
## CameraAttributesPractical (exposure + physically-based autofocus depth of field), viewport AA / upscaling / shadow
## atlas, and a full-screen display-space "lens + film" pass (shaders/look_postfx.gdshader on a CanvasLayer below the UI):
## barrel distortion, edge chromatic aberration, contrast-adaptive sharpening, defocus/radial blur, filmic grade with a
## shadow toe, vignette, fear pulse, closet slats, flash, screen shake, luminance-aware film grain.
## Everything lives on one node (scripts/render/look_rig.gd, child of the main scene) created by the first apply().
##
## Public API (keep): static apply(q: String)                       q = low | medium | high | ultra
## Additions (all static, safe to call any time — no-ops until apply() ran):
##   set_fear(v 0..1)                fear response (grain, CA, desaturation, vignette, heartbeat pulse). Game.fear is
##                                   also read every frame; the stronger of the two wins.
##   flash(color, amount, dur)       full-screen flash (bright colours = screen blend, dark ones = mix toward them)
##   shake(amount, dur)              screen shake in post (UV offset + roll, auto zoom margin), not the camera
##   set_hidden_view(v 0..1)         closet view: dark edges + soft out-of-focus louver shadows
##   set_blur(v 0..1)                defocus + radial blur (jumpscare, waking up)
##   current() -> String             applied preset
##   rig() -> Node                   the LookRig node (environment, camera_attributes, focus_distance, post material…)
##   set_fill(v)                     lighting.gd: readability ambient (power off / menu), multiplier of the preset ambient
##   snap_focus()                    autofocus snaps instead of easing on the next frame (teleports, cuts)
##   set_dof_enabled(on)             force the depth of field off (e.g. a cinematic) — on by default where the preset has it
## Settings read (Settings autoload): quality, brightness (0.6..1.6 → exposure + display gamma), render_scale
##   (0.5..1.0, default 1.0: FSR2 on high/ultra, FSR1 on low/medium below 1), vsync / fullscreen are the UI's.
## Debug args (after --): --look-nopost (no post pass), --look-nodof, --look-focus=<m> (fixed focus distance),
##   --look-fear=<v>, --look-hidden=<v>, --look-blur=<v>, --look-stats (prints the preset + timings once)
class_name Quality
extends RefCounted

const LookRigScript := preload("res://scripts/render/look_rig.gd")

static var _rig: LookRigScript = null

## Applies a graphics preset to the viewport, environment, camera attributes and lights (Settings "quality").
static func apply(q: String) -> void:
	var r := _ensure_rig()
	if r == null: return
	r.apply_preset(q)

static func current() -> String:
	return String(_rig.quality) if _ok() else ""

static func rig() -> LookRigScript:
	return _rig if _ok() else null

static func set_fear(v: float) -> void:
	if _ok(): _rig.set_fear(v)

static func flash(color: Variant = Color(1, 1, 1), amount := 0.8, dur := 0.35) -> void:
	if _ok(): _rig.flash(color, amount, dur)

static func shake(amount := 0.5, dur := 0.4) -> void:
	if _ok(): _rig.shake(amount, dur)

static func set_hidden_view(v: float) -> void:
	if _ok(): _rig.set_hidden_view(v)

static func set_blur(v: float) -> void:
	if _ok(): _rig.set_blur(v)

static func set_fill(v: float) -> void:
	if _ok(): _rig.set_fill(v)

static func snap_focus() -> void:
	if _ok(): _rig.snap_focus()

static func set_dof_enabled(on: bool) -> void:
	if _ok(): _rig.set_dof_enabled(on)

static func _ok() -> bool:
	return _rig != null and is_instance_valid(_rig) and _rig.is_inside_tree()

static func _ensure_rig() -> LookRigScript:
	if _ok(): return _rig
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return null
	var parent: Node = null
	var game := tree.root.get_node_or_null("Game")
	if game != null:
		var m = game.get(&"main")
		if m is Node and is_instance_valid(m) and (m as Node).is_inside_tree(): parent = m
	if parent == null: parent = tree.current_scene
	if parent == null: parent = tree.root
	var r: LookRigScript = LookRigScript.new()
	r.name = "Look"
	parent.add_child(r)
	_rig = r
	return r
