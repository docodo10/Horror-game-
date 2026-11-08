// UI module — wax-crayon "tooth" for the child's drawings (web .lg-crayon background-clip:text with a wax texture):
// the glyph coverage is broken up by paper-grain noise and diagonal stroke streaks, in the item's local space.
shader_type canvas_item;

uniform float seed = 0.0;
uniform float strength = 1.0;

varying vec2 local_pos;

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

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos + seed * 31.0;
	// diagonal wax strokes (web: short strokes at -25°) + fine paper tooth
	vec2 r = vec2(p.x * 0.906 + p.y * 0.423, -p.x * 0.423 + p.y * 0.906);
	float streak = vnoise(vec2(r.x * 0.16, r.y * 1.1));
	float tooth = vnoise(p * 0.55) * 0.55 + hash(floor(p * 0.8)) * 0.45;
	float k = smoothstep(0.16, 0.62, tooth * 0.7 + streak * 0.5);
	float keep = mix(1.0, 0.25 + 0.75 * k, strength);
	COLOR.a *= keep;
	COLOR.rgb *= 0.92 + 0.12 * streak;
}
