// UI module — CRT screen of the dresser TV (main menu), port of the web CRT_FRAG (src/ui/UI.js): barrel curvature,
// sharp-bilinear texel sampling, horizontal bleed, scanlines and an aperture-grille RGB mask that fade in only when a
// texel covers enough pixels (no moiré), line jitter, rolling bar, grain, static, vignette, glass sheen and the
// power-off collapse (vertical then horizontal squash to a bright dot). Emissive HDR output (bloom-friendly).
// Drawn in the transparent pass without depth test (on top of the world's own static screen plane); the menu camera
// always faces the TV so nothing can be in front of it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_back, fog_disabled, shadows_disabled, ambient_light_disabled;

uniform sampler2D page : source_color, filter_linear, repeat_disable;
uniform vec2 tex_size = vec2(480.0, 360.0);
uniform float u_time = 0.0;
uniform float u_static : hint_range(0.0, 1.5) = 0.05;
uniform float u_collapse : hint_range(0.0, 1.0) = 0.0;
uniform float u_bright = 1.55;
uniform float u_jitter = 0.4;
uniform float u_burst : hint_range(0.0, 1.5) = 0.0;
uniform float u_alpha : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 barrel(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + 0.045 * dot(c, c);
	return c * 0.5 + 0.5;
}

// uv: page coordinates with v = 0 at the top (Godot texture space)
vec3 sharp(vec2 uv) {
	vec2 texel = uv * tex_size;
	vec2 sc = max(vec2(1.0), 1.0 / max(fwidth(texel), vec2(1e-4)));
	vec2 fl = floor(texel);
	vec2 s = fract(texel);
	vec2 rr = 0.5 - 0.5 / sc;
	vec2 cd = s - 0.5;
	vec2 f = (cd - clamp(cd, -rr, rr)) * sc + 0.5;
	return texture(page, (fl + f) / tex_size).rgb;
}

void fragment() {
	// web convention: v up
	vec2 vuv = vec2(UV.x, 1.0 - UV.y);
	vec2 uv = barrel(vuv);
	float t = u_time;
	float jl = floor(uv.y * 70.0);
	uv.x += (hash(vec2(jl, floor(t * 18.0))) - 0.5) * 0.004 * u_jitter + sin(uv.y * 38.0 + t * 2.7) * 0.00035;
	vec2 q = abs(uv - 0.5) - (0.5 - 0.05);
	float dmask = length(max(q, 0.0)) - 0.05;
	float mask = 1.0 - smoothstep(-0.006, 0.002, dmask);
	vec2 c = uv - 0.5;
	float sy = mix(1.0, 0.0035, smoothstep(0.0, 0.42, u_collapse));
	float sx = mix(1.0, 0.004, smoothstep(0.42, 0.78, u_collapse));
	vec2 cc = vec2(c.x / sx, c.y / sy);
	vec2 suv = cc + 0.5;
	float inside = step(abs(cc.x), 0.5) * step(abs(cc.y), 0.5);
	vec2 tuv = vec2(suv.x, 1.0 - suv.y);
	vec3 col = sharp(tuv);
	vec2 px = vec2(1.6 / tex_size.x, 0.0);
	col = col * 0.82 + 0.13 * (texture(page, tuv + px).rgb + texture(page, tuv - px).rgb);
	// blocky static burst (web: tt.noise over the page, before the tube effects)
	float nb = hash(floor(tuv * vec2(160.0, 120.0)) + fract(t * 13.7) * vec2(57.0, 91.0));
	col = mix(col, vec3(nb), clamp(u_burst, 0.0, 1.0));
	vec2 texel = tuv * tex_size;
	float scale = 1.0 / max(fwidth(texel.y), 1e-4);
	float sl = 0.5 + 0.5 * cos(6.28318 * (fract(texel.y) - 0.5));
	col *= 1.0 - clamp((scale - 1.3) / 2.0, 0.0, 1.0) * 0.38 * (1.0 - sl);
	float m = mod(FRAGCOORD.x, 3.0);
	vec3 msk = m < 1.0 ? vec3(1.08, 0.95, 0.95) : (m < 2.0 ? vec3(0.95, 1.08, 0.95) : vec3(0.95, 0.95, 1.08));
	col *= mix(vec3(1.0), msk, clamp((scale - 1.6) / 2.0, 0.0, 1.0));
	col *= inside;
	float g = exp(-pow(c.y / (sy * 0.5 + 0.0025), 2.0)) * exp(-pow(abs(c.x) / (sx * 0.5 + 0.004), 6.0));
	col = mix(col, vec3(1.0), smoothstep(0.12, 0.42, u_collapse) * inside);
	col += vec3(g) * smoothstep(0.25, 0.45, u_collapse) * 1.4;
	col *= 1.0 - smoothstep(0.8, 1.0, u_collapse);
	float rb = fract(vuv.y * 0.55 - t * 0.075);
	col *= 1.0 + 0.07 * smoothstep(0.0, 0.06, rb) * (1.0 - smoothstep(0.06, 0.2, rb));
	float n = hash(FRAGCOORD.xy * 0.37 + fract(t * 7.3) * 91.7);
	col += (n - 0.5) * 0.045 * (1.0 - u_collapse);
	col = mix(col, vec3(n * n), clamp(u_static, 0.0, 1.0) * (1.0 - smoothstep(0.3, 0.6, u_collapse)));
	col *= 0.985 + 0.015 * sin(t * 113.0);
	col *= 1.0 - 0.42 * pow(clamp(length(c * vec2(1.0, 1.12)) * 1.25, 0.0, 1.0), 3.0);
	vec3 glass = vec3(0.012, 0.014, 0.017) + 0.035 * smoothstep(0.55, 0.0, length(vuv - vec2(0.27, 0.8)));
	ALBEDO = glass + max(col, vec3(0.0)) * mask * u_bright;
	ALPHA = u_alpha;
}
