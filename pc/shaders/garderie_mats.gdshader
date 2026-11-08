// Garderie: interlocking EVA foam puzzle mats (60 cm) drawn on a flat floor in world space. Each pixel finds the tile
// that owns it through a dovetail edge mask (generated mat_edge.png), so tabs and notches interlock exactly; per-tile
// colour / fading / slight tilt from a hash, dark gaps with a rounded bevel, fine foam grain, scuffs and grime.
// Missing tiles (hash) show the bare concrete underneath with dust in the corners.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D edge_tex : filter_linear, repeat_enable;
uniform sampler2D grain_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scratch_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float tile = 0.6;
uniform vec2 offset = vec2(0.0);
uniform vec4 col_a : source_color = vec4(0.78, 0.18, 0.15, 1.0);
uniform vec4 col_b : source_color = vec4(0.13, 0.33, 0.68, 1.0);
uniform vec4 col_c : source_color = vec4(0.92, 0.68, 0.12, 1.0);
uniform vec4 col_d : source_color = vec4(0.18, 0.52, 0.25, 1.0);
uniform vec4 weights = vec4(0.25, 0.5, 0.75, 1.0);   // cumulative probabilities of a, b, c (d = rest)
uniform float checker = 0.0;                          // 1 = a/b checkerboard
uniform float missing = 0.025;
uniform float floor_y = 0.0;
uniform float dirt = 0.35;
uniform float fade = 0.25;

varying vec3 wpos;

const float D = 0.1;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz / tile + offset;
	vec2 c = floor(p);
	vec2 f = p - c;
	vec2 owner = c;
	float edge = 0.5;
	vec2 grad = vec2(0.0);
	float mx = 0.5;
	float my = 0.5;
	if (f.x < D) {
		mx = texture(edge_tex, vec2((f.x + D) / (2.0 * D), f.y)).r;
		if (mx > 0.5) owner.x -= 1.0;
		edge = abs(mx - 0.5);
		grad = vec2(mx > 0.5 ? 1.0 : -1.0, 0.0);
	} else if (f.x > 1.0 - D) {
		mx = texture(edge_tex, vec2((f.x - 1.0 + D) / (2.0 * D), f.y)).r;
		if (mx < 0.5) owner.x += 1.0;
		edge = abs(mx - 0.5);
		grad = vec2(mx > 0.5 ? 1.0 : -1.0, 0.0);
	}
	if (f.y < D) {
		my = texture(edge_tex, vec2((f.y + D) / (2.0 * D), 1.0 - f.x)).r;
		if (my > 0.5) owner.y -= 1.0;
		float e = abs(my - 0.5);
		if (e < edge) {
			edge = e;
			grad = vec2(0.0, my > 0.5 ? 1.0 : -1.0);
		}
	} else if (f.y > 1.0 - D) {
		my = texture(edge_tex, vec2((f.y - 1.0 + D) / (2.0 * D), 1.0 - f.x)).r;
		if (my < 0.5) owner.y += 1.0;
		float e = abs(my - 0.5);
		if (e < edge) {
			edge = e;
			grad = vec2(0.0, my > 0.5 ? 1.0 : -1.0);
		}
	}
	float h = hash12(owner + 17.0);
	float h2 = hash12(owner * 1.7 + 3.1);
	float h3 = hash12(owner * 0.37 + 11.0);
	vec3 col;
	if (checker > 0.5) {
		col = mod(owner.x + owner.y, 2.0) < 1.0 ? col_a.rgb : col_b.rgb;
	} else {
		col = h < weights.x ? col_a.rgb : (h < weights.y ? col_b.rgb : (h < weights.z ? col_c.rgb : col_d.rgb));
	}
	// per-tile ageing: sun fade, value jitter
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * 1.05 + 0.04, h2 * fade);
	col *= 0.88 + h2 * 0.2;
	vec4 nz = texture(noise_tex, wpos.xz * 0.09);
	vec4 nz2 = texture(noise_tex, wpos.xz * 0.43 + vec2(0.3, 0.7));
	vec3 sc = texture(scratch_tex, wpos.xz * 0.9).rgb;
	// antialiased gap + bevel
	float aa = max(fwidth(edge) * 1.5, 0.02);
	float gap = 1.0 - smoothstep(0.0, aa + 0.03, edge);
	float bevel = 1.0 - smoothstep(0.0, 0.16, edge);
	bool miss = h3 < missing;
	vec3 base;
	float rough;
	if (miss) {
		vec3 cc = texture(concrete_tex, wpos.xz * 0.6).rgb * vec3(0.72, 0.7, 0.66);
		// inside edge of a missing tile: dust lines and the neighbours' shadow
		cc *= 0.55 + 0.45 * smoothstep(0.0, 0.45, edge);
		cc = mix(cc, vec3(0.45, 0.42, 0.38), nz2.r * 0.35);
		base = cc;
		rough = 0.85;
	} else {
		base = col;
		base *= 1.0 - gap * 0.8;
		base *= 1.0 - bevel * 0.12;
		float d = dirt * (0.35 + nz.r * 0.9) + sc.g * 0.15;
		base = mix(base, base * vec3(0.55, 0.5, 0.44), clamp(d, 0.0, 0.8));
		base = mix(base, base * 1.18 + 0.03, sc.r * 0.25);
		rough = clamp(0.62 + nz2.g * 0.18 + gap * 0.3 - sc.r * 0.1, 0.3, 1.0);
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	// fine foam grain + bevel tilt (world xz -> view space) + per-tile tilt (slightly curled mats)
	vec3 wn = vec3(0.0, 1.0, 0.0);
	if (!miss) {
		vec2 tilt = (vec2(hash12(owner + 5.0), hash12(owner + 9.0)) - 0.5) * 0.05;
		wn = normalize(vec3(grad.x * bevel * 0.55 + tilt.x, 1.0, grad.y * bevel * 0.55 + tilt.y));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	NORMAL_MAP = texture(grain_n, wpos.xz * 2.4).xyz;
	NORMAL_MAP_DEPTH = miss ? 0.2 : 0.8;
	AO = 1.0 - gap * 0.6;
	AO_LIGHT_AFFECT = 0.2;
}
