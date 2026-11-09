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
## Settings read live (Settings autoload, Events.settings_changed): quality, brightness (0.6..1.6 → exposure × b and a
##   display gamma), upscale ("off" | "fsr2_quality" 0.667 | "fsr2_balanced" 0.588 | "fsr2_performance" 0.5: FSR 2.2
##   temporal upscaling with its own AA — TAA / FXAA / SMAA off while it runs), render_scale (0.5..1.0, used when upscale
##   is "off": FSR 1 spatial below 1.0), depth_of_field / film_grain / chromatic_aberration (bool, default true).
##   Per-frame cost on the CPU side: ~15 shader uniforms, 5 physics rays every other frame (autofocus), no allocations.
##   vsync / fullscreen are the UI's. No auto-exposure (La Gardienne's torch exposure in gardienne.gd stays valid).
## Tone / bloom contract for other modules: AgX at exposure 1.0 (× brightness); bloom = Godot glow, threshold 1.15 with a
##   soft knee to ~3.75 (glow_hdr_scale 2.6), intensity 0.32, screen blend, levels 2–5. Emitters that should glow need
##   linear output ≥ ~2 (the fan bowl ≈ 8, a fluorescent tube 6–10); the TV glass at 1.55 glows only faintly.
## Debug args (after --): --look-nopost (no post pass), --look-nodof, --look-focus=<m> (fixed focus distance),
##   --look-fear=<v>, --look-hidden=<v>, --look-blur=<v>, --look-stats (prints the preset once),
##   --look-nogi / --look-nofog / --look-noglow, --look-upscale=<upscale value> (not saved), --look-tune=k:v;k:v (look_rig.gd TUNE_DEFAULTS)
## Look-dev: scripts/render/tests/lookdev.sh (variants × views in one session), tests/look_test.gd (headless contract test).
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
