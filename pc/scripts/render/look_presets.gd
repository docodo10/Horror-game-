## Look module — graphics presets (data only). Read by quality.gd / look_rig.gd and lighting.gd (apply_quality).
## Every value here is tuned in the look-dev renders (see scripts/render/README.md). GPU cost estimates are for a
## mid-range desktop GPU (RTX 3060 / RX 6600 class) at 1080p native; 4K costs about 3x.
##   low     integrated GPUs / Steam Deck: no GI, no volumetric fog, SSAO half-res, FXAA, cheap post   (~3-4 ms)
##   medium  GTX 1060 class: SSAO, coarse volumetric fog (light shafts), SMAA, bloom                 (~6-7 ms)
##   high    SDFGI + SSIL + SSAO + SSR + volumetric fog + bloom + TAA + autofocus depth of field     (~10-12 ms)
##   ultra   more SDFGI cascades + occlusion, 8192 shadow atlas, finer fog/SSR/SSAO, FSR2 native AA,
##           stronger depth of field (circle bokeh, high quality)                                     (~15-18 ms)
## Positional shadows stay on in every preset (the player's torch cookie needs them).
extends RefCounted

const ORDER := ["low", "medium", "high", "ultra"]

const P := {
	"low": {
		# ---- anti-aliasing / resolution
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_FXAA, "taa": false, "fsr2_native": false,
		"upscaler": Viewport.SCALING_3D_MODE_FSR, "sharpen": 0.0, "aniso": 2, "lod": 2.0,
		# ---- shadows
		"atlas": 2048, "quads": [1, 4, 4, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "light_size": false,
		# ---- GI / screen space
		"sdfgi": false, "ssil": false, "ssr": false,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_LOW, "ssao_half": true,
		# ---- fog / glow / lens
		"vfog": false, "glow": true, "glow_bicubic": false, "dof": false, "dof_q": RenderingServer.DOF_BLUR_QUALITY_LOW,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_DISABLED,
		"ambient": 0.11,          # flat ambient stand-in for the missing bounce (kept low: grime / relief stay readable)
		"bounce": 0.16,           # unshadowed fill at the bulb (fraction of the key) — no GI on this preset
		"ca": 0.0, "grain_smooth": false, "edge_soft": 0.0, "blur_taps": 8, "toe": 0.0,
		"shaft_mesh": true,       # analytic moon shaft (no volumetric fog here)
		"tv_shadow": false, "tube_shadow": false,
	},
	"medium": {
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_SMAA, "taa": false, "fsr2_native": false,
		"upscaler": Viewport.SCALING_3D_MODE_FSR, "sharpen": 0.0, "aniso": 3, "lod": 1.0,
		"atlas": 4096, "quads": [1, 4, 4, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "light_size": false,
		"sdfgi": false, "ssil": false, "ssr": false,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_MEDIUM, "ssao_half": true,
		"vfog": true, "vfog_size": 64, "vfog_depth": 48, "glow": true, "glow_bicubic": false,
		"dof": false, "dof_q": RenderingServer.DOF_BLUR_QUALITY_LOW,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_LOW,
		"ambient": 0.1, "bounce": 0.15,
		"ca": 0.0026, "grain_smooth": false, "edge_soft": 0.0, "blur_taps": 10, "toe": 0.04,
		"shaft_mesh": false, "tv_shadow": false, "tube_shadow": true,
	},
	"high": {
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED, "taa": true, "fsr2_native": false,
		"upscaler": Viewport.SCALING_3D_MODE_FSR2, "sharpen": 0.3, "aniso": 4, "lod": 1.0,
		"atlas": 4096, "quads": [1, 4, 4, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "light_size": true,
		"sdfgi": true, "sdfgi_cascades": 4, "sdfgi_cell": 0.1, "sdfgi_occlusion": false,
		"sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_32, "sdfgi_converge": RenderingServer.ENV_SDFGI_CONVERGE_IN_15_FRAMES,
		"sdfgi_update": RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_4_FRAMES,
		"ssil": true, "ssil_q": RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
		"ssr": true, "ssr_steps": 56, "ssr_rough": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_HIGH, "ssao_half": false,
		"vfog": true, "vfog_size": 96, "vfog_depth": 64, "glow": true, "glow_bicubic": true,
		"dof": true, "dof_q": RenderingServer.DOF_BLUR_QUALITY_MEDIUM, "dof_amount": 0.11,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_MEDIUM,
		"ambient": 0.0, "bounce": 0.0,
		"ca": 0.0032, "grain_smooth": true, "edge_soft": 1.0, "blur_taps": 12, "toe": 0.06,
		"shaft_mesh": false, "tv_shadow": true, "tube_shadow": true,
	},
	"ultra": {
		"msaa": Viewport.MSAA_DISABLED, "ssaa": Viewport.SCREEN_SPACE_AA_DISABLED, "taa": true, "fsr2_native": true,
		"upscaler": Viewport.SCALING_3D_MODE_FSR2, "sharpen": 0.25, "aniso": 4, "lod": 0.5,
		"atlas": 8192, "quads": [1, 4, 4, 16], "soft": RenderingServer.SHADOW_QUALITY_SOFT_HIGH, "light_size": true,
		"sdfgi": true, "sdfgi_cascades": 6, "sdfgi_cell": 0.08, "sdfgi_occlusion": true,
		"sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_64, "sdfgi_converge": RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES,
		"sdfgi_update": RenderingServer.ENV_SDFGI_UPDATE_LIGHT_IN_2_FRAMES,
		"ssil": true, "ssil_q": RenderingServer.ENV_SSIL_QUALITY_HIGH,
		"ssr": true, "ssr_steps": 96, "ssr_rough": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM,
		"ssao": true, "ssao_q": RenderingServer.ENV_SSAO_QUALITY_ULTRA, "ssao_half": false,
		"vfog": true, "vfog_size": 128, "vfog_depth": 96, "glow": true, "glow_bicubic": true,
		"dof": true, "dof_q": RenderingServer.DOF_BLUR_QUALITY_HIGH, "dof_amount": 0.15,
		"sss": RenderingServer.SUB_SURFACE_SCATTERING_QUALITY_HIGH,
		"ambient": 0.0, "bounce": 0.0,
		"ca": 0.0034, "grain_smooth": true, "edge_soft": 1.0, "blur_taps": 16, "toe": 0.06,
		"shaft_mesh": false, "tv_shadow": true, "tube_shadow": true,
	},
}

static func get_preset(q: String) -> Dictionary:
	return P.get(q, P["high"])

static func valid(q: String) -> String:
	return q if P.has(q) else "high"
