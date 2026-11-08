// Garderie: painted / textured architecture (walls, floors, ceilings, wood, steel). PBR maps (Poly Haven, CC0) +
// paint tint (two-tone band with a stripe, by world height), large-scale blotches and grime that rises from the floor.
// Vertex COLOR multiplies the albedo (several paint colours share one material).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = true;
uniform float uv_scale = 1.0;
uniform vec2 uv_offset = vec2(0.0);
uniform vec2 detail_scale = vec2(1.0);   // extra scale of the normal / ORM maps (mural over a block wall)
uniform float normal_strength = 1.0;
uniform vec4 tint_low : source_color = vec4(1.0);
uniform vec4 tint_high : source_color = vec4(1.0);
uniform vec4 stripe_color : source_color = vec4(1.0);
uniform float band_y = -1000.0;
uniform float stripe_w = 0.0;
// 0: texture colour x tint, 1: paint colour modulated by the texture luminance (painted surface keeping its relief)
uniform float paint = 0.0;
uniform float paint_low = -1.0;     // >= 0: overrides `paint` below band_y
uniform float lum_ref = 0.45;
uniform float lum_contrast = 1.0;
uniform float floor_y = 0.0;
uniform float grime_h = 0.6;
uniform float grime = 0.35;
uniform vec4 grime_color : source_color = vec4(0.36, 0.31, 0.25, 1.0);
uniform float blotch = 0.12;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metal_mul = 0.0;
uniform float ao_strength = 1.0;
uniform float emission_mul = 0.0;

varying vec3 wpos;

// vertex / instance colours are authored in sRGB
vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec3 t = texture(albedo_tex, uv).rgb;
	float lum = dot(t, vec3(0.299, 0.587, 0.114));
	vec3 tint = wpos.y < band_y ? tint_low.rgb : tint_high.rgb;
	if (stripe_w > 0.0) {
		float s = 1.0 - smoothstep(stripe_w * 0.5, stripe_w * 0.5 + 0.004, abs(wpos.y - band_y));
		tint = mix(tint, stripe_color.rgb, s);
	}
	vec3 painted = tint * clamp(pow(max(lum, 1e-3) / lum_ref, lum_contrast), 0.0, 1.6);
	float pm = (wpos.y < band_y && paint_low >= 0.0) ? paint_low : paint;
	vec3 base = mix(t * tint, painted, pm) * srgb_to_lin(COLOR.rgb);
	vec4 nz = texture(noise_tex, wpos.xz * 0.071 + vec2(wpos.y * 0.05));
	vec4 nz2 = texture(noise_tex, vec2(wpos.x + wpos.z, wpos.y) * 0.13);
	base *= 1.0 + (nz.a - 0.5) * blotch * 2.0 + (nz2.g - 0.5) * blotch;
	float g = (1.0 - smoothstep(floor_y, floor_y + grime_h, wpos.y)) * grime * (0.45 + nz2.r);
	base = mix(base, base * grime_color.rgb * 1.5, clamp(g, 0.0, 1.0));
	ALBEDO = base;
	vec2 uvd = uv * detail_scale;
	vec3 orm = texture(orm_tex, uvd).rgb;
	AO = mix(1.0, orm.r, ao_strength);
	AO_LIGHT_AFFECT = 0.25;
	ROUGHNESS = clamp(orm.g * rough_mul + rough_add + g * 0.08, 0.04, 1.0);
	METALLIC = orm.b * metal_mul;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, uvd).xyz;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	EMISSION = base * emission_mul;
}
