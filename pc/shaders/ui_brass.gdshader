// UI module — cast brass padlock body for the keypad (web .lg-kp-lock): rounded-rect SDF with antialiased edges,
// 160° gold gradient, warm specular highlight top-left, dark tarnish bottom-right, brushed streaks + pitting grain,
// bevel (bright top lip, dark bottom inner shadow) and a soft rim. rect_size = the ColorRect size in pixels.
shader_type canvas_item;

uniform vec2 rect_size = vec2(460.0, 330.0);
uniform float r_top = 22.0;
uniform float r_bottom = 36.0;
uniform vec4 c0 : source_color = vec4(0.788, 0.627, 0.294, 1.0);   // #c9a04b
uniform vec4 c1 : source_color = vec4(0.561, 0.404, 0.149, 1.0);   // #8f6726
uniform vec4 c2 : source_color = vec4(0.365, 0.259, 0.098, 1.0);   // #5d4219
uniform float seed = 3.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 p = px - rect_size * 0.5;
	float r = p.y < 0.0 ? r_top : r_bottom;
	float d = sd_round_box(p, rect_size * 0.5, r);
	float aa = max(fwidth(d), 0.75);
	float alpha = 1.0 - smoothstep(-aa, aa, d);
	// 160° gradient: from top-left to bottom-right, mostly vertical
	float g = clamp(dot(UV - 0.5, normalize(vec2(0.342, 0.94))) + 0.5, 0.0, 1.0);
	vec3 base = g < 0.55 ? mix(c0.rgb, c1.rgb, g / 0.55) : mix(c1.rgb, c2.rgb, (g - 0.55) / 0.45);
	// highlight (ellipse at 28% 16%) and tarnish (80% 90%)
	float hl = 1.0 - smoothstep(0.0, 0.5, length((UV - vec2(0.28, 0.16)) * vec2(1.0, 1.25)));
	base = mix(base, vec3(1.0, 0.933, 0.706), hl * 0.55);
	float dk = 1.0 - smoothstep(0.0, 0.6, length((UV - vec2(0.8, 0.9)) * vec2(1.0, 1.2)));
	base = mix(base, vec3(0.157, 0.094, 0.024), dk * 0.5);
	// brushed metal: fine horizontal streaks + low-frequency variation + pitting
	float br = vnoise(vec2(px.x * 0.02, px.y * 1.6) + seed) * 0.6 + vnoise(vec2(px.x * 0.05, px.y * 3.1) + seed * 2.0) * 0.4;
	base *= 0.93 + 0.14 * br;
	base *= 0.96 + 0.08 * vnoise(px * 0.03 + seed * 5.0);
	float pit = smoothstep(0.93, 0.99, hash(floor(px * 0.7) + seed));
	base *= 1.0 - 0.18 * pit;
	// bevel: bright lip along the top edge, inner shadow at the bottom, dark rim
	float inner = -d;
	float top_lip = (1.0 - smoothstep(0.0, 5.0, inner)) * smoothstep(0.0, -rect_size.y * 0.3, p.y);
	base += vec3(1.0, 0.925, 0.706) * 0.35 * top_lip;
	float bottom_shadow = (1.0 - smoothstep(0.0, 14.0, inner)) * smoothstep(0.0, rect_size.y * 0.4, p.y);
	base *= 1.0 - 0.5 * bottom_shadow;
	base *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 2.0, inner));
	COLOR = vec4(base, alpha * COLOR.a);
}
