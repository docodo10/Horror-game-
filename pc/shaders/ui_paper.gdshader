// UI module — procedural aged paper for the notes (web .lg-note backgrounds): tilted two-tone gradient, multi-scale
// grain + fibres, coffee / foxing stains (darker rims), optional ruled lines + red margin (school paper), inset edge
// darkening, optional torn bottom edge (newspaper clipping). rect_size = the ColorRect size in pixels.
shader_type canvas_item;

uniform vec2 rect_size = vec2(860.0, 500.0);
uniform vec4 col_a : source_color = vec4(0.937, 0.902, 0.812, 1.0);
uniform vec4 col_b : source_color = vec4(0.863, 0.812, 0.682, 1.0);
uniform float seed = 1.0;
uniform float grain = 1.0;
uniform float rule_spacing = 0.0;
uniform float rule_offset = 0.0;
uniform vec4 rule_color : source_color = vec4(0.275, 0.392, 0.588, 0.26);
uniform float margin_x = 0.0;
uniform vec4 margin_color : source_color = vec4(0.761, 0.255, 0.176, 0.38);
uniform vec4 stain1 = vec4(0.88, 0.14, 0.18, 0.18);   // xy = uv centre, z = radius (in height units), w = strength
uniform vec4 stain2 = vec4(0.0, 0.0, 0.0, 0.0);
uniform float edge_dark = 1.0;
uniform float torn = 0.0;                             // jag depth in px (0 = straight edges)

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float stain(vec2 uv, vec4 s) {
	if (s.w <= 0.0) return 0.0;
	float asp = rect_size.x / max(rect_size.y, 1.0);
	vec2 d = (uv - s.xy) * vec2(asp, 1.0);
	float r = length(d) / max(s.z, 1e-3);
	r += (vnoise(d * 9.0 + seed * 7.0) - 0.5) * 0.25;
	float body = 1.0 - smoothstep(0.55, 1.0, r);
	float rim = smoothstep(0.7, 0.93, r) * (1.0 - smoothstep(0.93, 1.05, r));
	return clamp(body * 0.55 + rim * 0.9, 0.0, 1.0) * s.w;
}

void fragment() {
	vec2 px = UV * rect_size;
	float g = clamp(UV.y * 0.94 + UV.x * 0.07, 0.0, 1.0);
	vec3 base = mix(col_a.rgb, col_b.rgb, smoothstep(0.0, 1.0, g));
	// grain: fine speckles, mottling, fibres
	float n1 = vnoise(px * 0.8 + seed * 13.1);
	float n2 = vnoise(px * 0.035 + seed * 3.7);
	float n3 = hash(floor(px) + seed);
	float fib = vnoise(vec2(px.x * 0.06, px.y * 0.9) + seed * 5.3);
	float fib2 = vnoise(vec2(px.x * 0.9, px.y * 0.05) + seed * 2.1);
	base *= 1.0 + ((n1 - 0.5) * 0.045 + (n2 - 0.5) * 0.09 + (n3 - 0.5) * 0.04) * grain;
	base *= 1.0 - 0.035 * grain * (smoothstep(0.62, 0.92, fib) + smoothstep(0.7, 0.95, fib2));
	// stains (brownish)
	vec3 stain_col = vec3(0.47, 0.33, 0.16);
	float st = max(stain(UV, stain1), stain(UV, stain2));
	base = mix(base, base * stain_col * 1.25, st);
	// foxing dots
	float fx = smoothstep(0.985, 1.0, vnoise(px * 0.09 + seed * 9.0));
	base = mix(base, base * vec3(0.78, 0.62, 0.42), fx * 0.5 * grain);
	// ruled lines + margin
	if (rule_spacing > 1.0) {
		float ry = mod(px.y - rule_offset, rule_spacing);
		float dl = min(ry, rule_spacing - ry);
		float l = 1.0 - smoothstep(0.35, 1.25, dl);
		l *= 0.8 + 0.2 * vnoise(vec2(px.x * 0.05, px.y));
		base = mix(base, rule_color.rgb, l * rule_color.a);
	}
	if (margin_x > 0.0) {
		float m = 1.0 - smoothstep(0.6, 1.6, abs(px.x - margin_x));
		base = mix(base, margin_color.rgb, m * margin_color.a);
	}
	// inset edge darkening (CSS inset 0 0 50px rgba(96,66,28,.28))
	vec2 e = min(px, rect_size - px);
	float ed = min(e.x, e.y);
	base = mix(base, base * vec3(0.376, 0.259, 0.11) * 1.6, 0.28 * edge_dark * (1.0 - smoothstep(0.0, 60.0, ed)));
	float alpha = 1.0;
	if (torn > 0.0) {
		float k = px.x * 0.045;
		float jag = (vnoise(vec2(k, seed)) * 0.7 + hash(vec2(floor(px.x * 0.35), seed)) * 0.3) * torn;
		float edge_y = rect_size.y - 2.0 - jag;
		alpha = 1.0 - smoothstep(edge_y - 0.8, edge_y + 0.8, px.y);
		// fibrous lighter rim along the tear
		base = mix(base, base * 1.08, (1.0 - smoothstep(0.0, 5.0, edge_y - px.y)) * 0.6);
	}
	COLOR = vec4(base, alpha * COLOR.a);
}
