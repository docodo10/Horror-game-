## Look module — graphics presets (data only). Read by quality.gd / look_rig.gd and lighting.gd (apply_quality).
## Values tuned in look-dev renders (scripts/render/tests/lookdev.sh). Frame budgets (target, GPU time ESTIMATED from Godot
## 4.5 Forward+ feature costs — the test machine renders on a CPU, nothing here could be timed on a real GPU):
##   low     iGPU / Steam Deck, 60 fps at 1080p (~6-8 ms there): no GI, no volumetric fog (analytic moon shaft), SSAO low
##           half-res, FXAA, PCF shadows, no DOF, cheap post
##   medium  GTX 1660 / RTX 2060, 120 fps at 1080p (~5-6 ms): SSAO medium half-res, coarse volumetric fog (shafts), SMAA,
##           bloom, half-res DOF, PCF shadows, bounce stand-ins instead of GI
##   high    RTX 3060-4070, 120+ fps at 1440p native (~6.5-8 ms; ~5 ms with FSR 2 Quality): SDFGI (4 cascades, 16 rays,
##           half-res GI) + SSIL (low, half-res) + SSAO (medium) + SSR (32 steps) + volumetric fog (64x64) + bloom + TAA +
##           CAS + half-res autofocus DOF, 4096 shadow atlas, PCSS only on the bulb / moon (soft-low kernel)
##   ultra   same GPU class, 70-90 fps at 1440p (~11-14 ms): SDFGI 5 cascades / 32 rays / full-res GI, SSIL high, SSAO
##           high, SSR 64, fog 96x80, 8192 atlas + soft-high PCSS, TV / tube shadows, full-res circle-bokeh DOF, TAA
## Approximate per-feature costs at 1440p on an RTX 3070-class GPU (to trade in the options): SDFGI 0.8-1.2 ms half-res /
##   1.8-2.5 ms full-res (+0.3 ms per extra cascade); SSIL 0.3 (low half) / 1.2 (high); SSAO 0.3 (medium) / 0.8 (high);
##   SSR 0.4 (32 steps) / 0.8 (64); volumetric fog 0.3 (64x64) / 0.8 (96x80); DOF 0.3 (half-res) / 0.9 (high circle);
##   TAA 0.25; glow 0.25; post pass 0.15; positional shadows: re-rendered only when casters move (the bulb's cube map
##   ~1-2 ms on those frames), PCSS on the bulb 0.3-0.6 ms. FSR 2 Quality (0.67) cuts the per-pixel part by ~45 %.
## Positional shadows stay on in every preset (the player's torch cookie needs them).
## Shadow atlas: the four quadrants all use the same subdivision (16 slots each, 64 in all), so every light gets the same
## slot size. Read in Godot 4.5's LightStorage::shadow_atlas_update_light: a light whose slot is not of the size its
## screen coverage asks for is moved as soon as a slot of the "right" quadrant can be taken (also from a light the frame
## has not processed yet), and every move re-renders its shadow. With quadrants of different sizes that never settles:
##  * [1, 4, 4, 16]: an omni light needs two slots of one quadrant, so one that covers the screen (the ceiling bulb) can
##    never have the single big slot: its whole shadow cube was re-rendered EVERY frame (174 k triangles, 61 % of all the
##    basement drew, with every script frozen); in the garderie hall 250-780 k shadow triangles per frame.
##  * [4, 4, 16, 16]: fixed standing still, but walking with a dozen shadowed lights in view (leaving the hall) still
##    re-rendered 58-213 k shadow triangles every frame: more lights want a big slot than exist, and they keep taking
##    them from each other as the camera moves.
## With equal quadrants nothing is ever moved: shadows are rendered when something in them changes, and only then.
## The atlas is larger instead (slot = atlas / 8): 512 px per light on low / medium, 1024 px on high / ultra.
extends RefCounted

const ORDER := ["low", "medium", "high", "ultra"]
## Settings "upscale" -> FSR 2.2 render scale (temporal upscaling with its own anti-aliasing; TAA is switched off).
const UPSCALE := {"off": 1.0, "fsr2_quality": 0.667, "fsr2_balanced": 0.588, "fsr2_performance": 0.5}

const P := {
	"low": {
		# ---- anti-aliasing / resolution (render_scale < 1 with upscale "off" uses FSR 1, spatial)
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA, "taa": false,
		"sharpen": 0.0, "aniso": 2, "lod": 2.0,
		# ---- shadows
		"atlas": 4096, "quads": [16, 16, 16, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "light_size": false,
		# ---- GI / screen space
		"sdfgi": false, "ssil": false, "ssr": false, "gi_half": true,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_LOW, "ssao_half": true,
		# ---- fog / glow / lens
		"vfog": false, "glow": true, "glow_bicubic": false, "dof": false, "dof_q": RenderingServer.DOF_BLUR_QUALITY_VERY_LOW,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED,
		"ambient": 0.11,          # flat ambient stand-in for the missing bounce (kept low: grime / relief stay readable)
		"bounce": 0.16,           # unshadowed fill at the bulb (fraction of the key) — no GI on this preset
		"ca": 0.0, "grain_smooth": false, "edge_soft": 0.0, "blur_taps": 8, "toe": 0.0,
		"shaft_mesh": true,       # analytic moon shaft (no volumetric fog here)
		"tv_shadow": false, "tube_shadow": false,
	},
	"medium": {
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_SMAA, "taa": false,
		"sharpen": 0.0, "aniso": 3, "lod": 1.0,
		"atlas": 4096, "quads": [16, 16, 16, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "light_size": false,
		"sdfgi": false, "ssil": false, "ssr": false, "gi_half": true,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_MEDIUM, "ssao_half": true,
		"vfog": true, "vfog_size": 64, "vfog_depth": 48, "glow": true, "glow_bicubic": false,
		"dof": true, "dof_q": RenderingServer.DOF_BLUR_QUALITY_LOW, "dof_amount": 0.08,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW,
		"ambient": 0.1, "bounce": 0.15,
		"ca": 0.0026, "grain_smooth": false, "edge_soft": 0.0, "blur_taps": 10, "toe": 0.04,
		"shaft_mesh": false, "tv_shadow": false, "tube_shadow": true,
	},
	"high": {
		# SMAA, not TAA: a sharp image that does not smear or ghost when the camera moves (TAA stays on ultra)
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_SMAA, "taa": false,
		"sharpen": 0.0, "aniso": 4, "lod": 1.0,
		"atlas": 8192, "quads": [16, 16, 16, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "light_size": true,
		"sdfgi": true, "sdfgi_cascades": 4, "sdfgi_cell": 0.1, "sdfgi_occlusion": false, "gi_half": true,
		"sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_16, "sdfgi_converge": RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES,
		"sdfgi_update": RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES,
		"ssil": true, "ssil_q": RenderingServer.ENV_SSIL_QUALITY_LOW, "ssil_half": true,
		"ssr": true, "ssr_steps": 32, "ssr_rough": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_MEDIUM, "ssao_half": true,
		"vfog": true, "vfog_size": 64, "vfog_depth": 64, "glow": true, "glow_bicubic": true,
		"dof": true, "dof_q": RenderingServer.DOF_BLUR_QUALITY_LOW, "dof_amount": 0.11,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM,
		"ambient": 0.0, "bounce": 0.0,
		"ca": 0.0032, "grain_smooth": true, "edge_soft": 0.0, "blur_taps": 12, "toe": 0.06,
		"shaft_mesh": false, "tv_shadow": false, "tube_shadow": true,
	},
	"ultra": {
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED, "taa": true,
		"sharpen": 0.25, "aniso": 4, "lod": 0.5,
		"atlas": 8192, "quads": [16, 16, 16, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_HIGH, "light_size": true,
		"sdfgi": true, "sdfgi_cascades": 5, "sdfgi_cell": 0.08, "sdfgi_occlusion": false, "gi_half": false,
		"sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_32, "sdfgi_converge": RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES,
		"sdfgi_update": RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_2_FRAMES,
		"ssil": true, "ssil_q": RenderingServer.ENV_SSIL_QUALITY_HIGH, "ssil_half": false,
		"ssr": true, "ssr_steps": 64, "ssr_rough": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_HIGH, "ssao_half": false,
		"vfog": true, "vfog_size": 96, "vfog_depth": 80, "glow": true, "glow_bicubic": true,
		"dof": true, "dof_q": RenderingServer.DOF_BLUR_QUALITY_HIGH, "dof_amount": 0.15,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH,
		"ambient": 0.0, "bounce": 0.0,
		"ca": 0.0034, "grain_smooth": true, "edge_soft": 0.0, "blur_taps": 16, "toe": 0.06,
		"shaft_mesh": false, "tv_shadow": true, "tube_shadow": true,
	},
}

static func get_preset(q: String) -> Dictionary:
	return P.get(q, P["high"])

static func valid(q: String) -> String:
	return q if P.has(q) else "high"

## Settings "upscale" value -> render scale (1.0 = native).
static func upscale_scale(u: String) -> float:
	return float(UPSCALE.get(u, 1.0))
