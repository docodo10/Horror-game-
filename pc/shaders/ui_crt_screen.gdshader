// UI module — full-screen CRT (loading, pause, caught, game over, win). Port of the web .lg-crt-screen CSS effects
// (scanlines, vignette, glass sheen, animated grain, flicker, rounded tube corners) plus the TV shader's tube model:
// slight barrel curvature, sharp-bilinear texels, horizontal bleed, texel scanlines and aperture-grille mask that only
// appear when a texel spans enough pixels, line jitter, rolling bar and the blocky static burst on page changes.
// mix_mode = 1: the page is transparent (pause over the frozen room) — alpha passes through, the vignette darkens.
shader_type canvas_item;

uniform sampler2D page : source_color, filter_linear, repeat_disable;
uniform vec2 tex_size = vec2(640.0, 480.0);
uniform float burst : hint_range(0.0, 1.5) = 0.0;
uniform float flick : hint_range(0.0, 1.0) = 0.0;
uniform float mix_mode : hint_range(0.0, 1.0) = 0.0;
uniform float curvature = 0.03;
uniform float aspect = 1.3333333;
uniform float corner = 0.043;
uniform float u_time = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 barrel(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + curvature * dot(c, c);
	return c * 0.5 + 0.5;
}

vec4 sharp(vec2 uv) {
	vec2 texel = uv * tex_size;
	vec2 sc = max(vec2(1.0), 1.0 / max(fwidth(texel), vec2(1e-4)));
	vec2 fl = floor(texel);
	vec2 s = fract(texel);
	vec2 rr = 0.5 - 0.5 / sc;
	vec2 cd = s - 0.5;
	vec2 f = (cd - clamp(cd, -rr, rr)) * sc + 0.5;
	return texture(page, (fl + f) / tex_size);
}

void fragment() {
	float t = u_time;
	vec2 uv = barrel(UV);
	float jl = floor(uv.y * 120.0);
	uv.x += (hash(vec2(jl, floor(t * 18.0))) - 0.5) * 0.0016 * (0.25 + flick) + sin(uv.y * 38.0 + t * 2.7) * 0.00022;
	// rounded tube corners (in screen proportions)
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	vec2 q = abs(p) - (vec2(aspect, 1.0) * 0.5 - corner);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	float aa = max(fwidth(d), 1e-4);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	vec4 col = sharp(uv);
	vec2 px = vec2(1.2 / tex_size.x, 0.0);
	vec4 nbr = texture(page, uv + px) + texture(page, uv - px);
	col.rgb = col.rgb * 0.84 + 0.08 * nbr.rgb;
	col.a = max(col.a, 0.5 * max(nbr.a * 0.5, 0.0) * mix_mode);
	// blocky static burst
	float nb = hash(floor(uv * vec2(160.0, 120.0)) + fract(t * 13.7) * vec2(57.0, 91.0));
	float bk = clamp(burst, 0.0, 1.0);
	col.rgb = mix(col.rgb, vec3(nb), bk);
	col.a = mix(col.a, 1.0, bk);
	// texel scanlines + aperture grille (fade in with magnification)
	vec2 texel = uv * tex_size;
	float scale = 1.0 / max(fwidth(texel.y), 1e-4);
	float sl = 0.5 + 0.5 * cos(6.28318 * (fract(texel.y) - 0.5));
	col.rgb *= 1.0 - clamp((scale - 1.3) / 2.0, 0.0, 1.0) * 0.32 * (1.0 - sl);
	float m = mod(FRAGCOORD.x, 3.0);
	vec3 msk = m < 1.0 ? vec3(1.07, 0.96, 0.96) : (m < 2.0 ? vec3(0.96, 1.07, 0.96) : vec3(0.96, 0.96, 1.07));
	col.rgb *= mix(vec3(1.0), msk, clamp((scale - 1.6) / 2.0, 0.0, 1.0));
	// rolling bar, grain, flicker
	float rb = fract((1.0 - UV.y) * 0.55 - t * 0.075);
	col.rgb *= 1.0 + 0.06 * smoothstep(0.0, 0.06, rb) * (1.0 - smoothstep(0.06, 0.2, rb));
	float n = hash(FRAGCOORD.xy * 0.37 + fract(t * 7.3) * 91.7);
	col.rgb += (n - 0.5) * 0.05 * col.a;
	col.rgb *= 0.985 + 0.015 * sin(t * 113.0);
	col.rgb += flick * 0.03 * col.a;
	// vignette (CSS: radial-gradient ellipse, transparent 58% -> rgba(0,0,0,.5) at the corners)
	float vd = length((UV - 0.5) * 2.0) * 0.70710678;
	float vig = smoothstep(0.58, 1.0, vd) * 0.5;
	col.rgb *= 1.0 - vig;
	col.a = max(col.a, vig * mix_mode);
	// glass sheen (radial-gradient at 26% 16%, white .07 -> 0 at 42%)
	float hl = (1.0 - smoothstep(0.0, 0.42, length((UV - vec2(0.26, 0.16)) * vec2(aspect, 1.0) * 0.75))) * 0.07;
	col.rgb += vec3(hl);
	col.a = max(col.a, hl);
	COLOR = vec4(col.rgb, col.a * inside * COLOR.a);
}
