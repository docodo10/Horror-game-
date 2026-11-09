// Garderie: interlocking EVA foam puzzle mats (60 cm, 7 dovetail teeth per edge) drawn on a flat floor in world space.
// mat_edge.png is a signed-distance field of the dovetail edge (tools/gen_textures.py): each pixel finds the tile that
// owns it, and the metric distance to the seam gives a 4 mm dark gap (x0.25, the concrete under it) with a 1.5 cm AO
// falloff, like the reference mats. Seams wander +-4 mm (slightly shifted / rotated mats), the gap width varies per
// edge. Two-colour checker per zone (zone rect -> col_c / col_d), per-tile fading, footpath wear (lighter + glossier
// along wear segments), grime toward the walls (room rect), scuffs, fine foam grain. Missing tiles (hash) show the
// concrete with dust. Lifted corners are extra geometry using this material: the shading follows the mesh normal.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D edge_tex : filter_linear, repeat_enable;
uniform sampler2D grain_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D scratch_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float tile = 0.6;
uniform vec2 offset = vec2(0.0);
uniform vec4 col_a : source_color = vec4(0.78, 0.58, 0.12, 1.0);
uniform vec4 col_b : source_color = vec4(0.13, 0.25, 0.5, 1.0);
uniform vec4 col_c : source_color = vec4(0.6, 0.08, 0.06, 1.0);
uniform vec4 col_d : source_color = vec4(0.1, 0.4, 0.15, 1.0);
uniform vec4 zone = vec4(0.0);            // x0, z0, x1, z1 of the second colour pair (0 = none)
uniform vec4 room = vec4(0.0);            // x0, z0, x1, z1 of the room (grime toward its walls; 0 = none)
uniform vec4 wear[8];                     // footpath segments ax, az, bx, bz
uniform int wear_n = 0;
uniform float wear_w = 0.55;
uniform float missing = 0.025;
uniform float floor_y = 0.0;
uniform float dirt = 0.35;
uniform float fade = 0.2;
uniform float gap_w = 0.004;              // metres
uniform float jitter = 0.004;             // seam wander, metres

varying vec3 wpos;

const float D = 0.1;      // half width of the edge band in mat_edge.png (tile units)
const float DM = 0.04;    // SDF range (tile units): value 0.5 +- 0.5 = +-DM

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float seg_dist(vec2 p, vec4 s) {
	vec2 a = s.xy;
	vec2 ab = s.zw - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(p - a - ab * t);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 wz = texture(noise_tex, wpos.xz * 0.37 + vec2(0.31, 0.77));
	vec2 p = wpos.xz / tile + offset + (wz.rg - 0.5) * (2.0 * jitter / tile);
	vec2 c = floor(p);
	vec2 f = p - c;
	vec2 owner = c;
	float edge = 0.5;          // 0.5 = far from any seam
	vec2 grad = vec2(0.0);
	vec2 edge_id = vec2(-100.0);
	float mx;
	if (f.x < D) {
		mx = texture(edge_tex, vec2((f.x + D) / (2.0 * D), f.y)).r;
		if (mx > 0.5) owner.x -= 1.0;
		edge = abs(mx - 0.5);
		grad = vec2(mx > 0.5 ? 1.0 : -1.0, 0.0);
		edge_id = vec2(c.x * 2.0, c.y);
	} else if (f.x > 1.0 - D) {
		mx = texture(edge_tex, vec2((f.x - 1.0 + D) / (2.0 * D), f.y)).r;
		if (mx < 0.5) owner.x += 1.0;
		edge = abs(mx - 0.5);
		grad = vec2(mx > 0.5 ? 1.0 : -1.0, 0.0);
		edge_id = vec2(c.x * 2.0 + 2.0, c.y);
	}
	if (f.y < D) {
		float my = texture(edge_tex, vec2((f.y + D) / (2.0 * D), 1.0 - f.x)).r;
		if (my > 0.5) owner.y -= 1.0;
		float e = abs(my - 0.5);
		if (e < edge) {
			edge = e;
			grad = vec2(0.0, my > 0.5 ? 1.0 : -1.0);
			edge_id = vec2(c.x, c.y * 2.0 + 1.0);
		}
	} else if (f.y > 1.0 - D) {
		float my = texture(edge_tex, vec2((f.y - 1.0 + D) / (2.0 * D), 1.0 - f.x)).r;
		if (my < 0.5) owner.y += 1.0;
		float e = abs(my - 0.5);
		if (e < edge) {
			edge = e;
			grad = vec2(0.0, my > 0.5 ? 1.0 : -1.0);
			edge_id = vec2(c.x, c.y * 2.0 + 3.0);
		}
	}
	// metric distance to the seam (m), gap width varies per edge (mats pushed apart / squeezed)
	float em = edge * 2.0 * DM * tile;
	float gw = gap_w * (0.6 + 0.8 * hash12(edge_id + 0.5)) * 0.5;
	float aa = max(fwidth(em) * 0.75, 0.0004);
	float gap = 1.0 - smoothstep(gw - aa, gw + aa, em);
	float ao = mix(0.55, 1.0, smoothstep(gw, gw + 0.015, em));
	float bevel = 1.0 - smoothstep(gw, gw + 0.006, em);
	float h = hash12(owner + 17.0);
	float h2 = hash12(owner * 1.7 + 3.1);
	float h3 = hash12(owner * 0.37 + 11.0);
	vec2 tc = (owner + 0.5 - offset) * tile;     // tile centre (world xz)
	bool z2 = zone.z > zone.x && tc.x > zone.x && tc.x < zone.z && tc.y > zone.y && tc.y < zone.w;
	bool chk = mod(owner.x + owner.y, 2.0) < 1.0;
	vec3 col = z2 ? (chk ? col_c.rgb : col_d.rgb) : (chk ? col_a.rgb : col_b.rgb);
	// per-tile ageing: sun fade, value jitter
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * 1.05 + 0.02, h2 * fade);
	col *= 0.86 + h2 * 0.22;
	vec4 nz = texture(noise_tex, wpos.xz * 0.09);
	vec4 nz2 = texture(noise_tex, wpos.xz * 0.43 + vec2(0.3, 0.7));
	vec3 sc = texture(scratch_tex, wpos.xz * 0.9).rgb;
	// footpaths
	float wear_m = 0.0;
	for (int i = 0; i < wear_n; i++) {
		wear_m = max(wear_m, 1.0 - smoothstep(wear_w * 0.35, wear_w, seg_dist(wpos.xz, wear[i])));
	}
	wear_m *= 0.55 + 0.6 * nz2.b;
	// grime toward the walls
	float wall_g = 0.0;
	if (room.z > room.x) {
		float dw = min(min(wpos.x - room.x, room.z - wpos.x), min(wpos.z - room.y, room.w - wpos.z));
		wall_g = 1.0 - smoothstep(0.0, 1.1, dw);
	}
	bool miss = h3 < missing;
	vec3 base;
	float rough;
	if (miss) {
		vec3 cc = texture(concrete_tex, wpos.xz * 0.6).rgb * vec3(0.62, 0.6, 0.57);
		cc *= 0.55 + 0.45 * smoothstep(0.0, 0.02, em);
		cc = mix(cc, vec3(0.4, 0.37, 0.33), nz2.r * 0.35);
		base = cc;
		rough = 0.85;
	} else {
		base = col;
		float d = dirt * (0.3 + nz.r * 0.8) + sc.g * 0.15 + wall_g * (0.35 + nz2.r * 0.5);
		base = mix(base, base * vec3(0.55, 0.5, 0.44), clamp(d, 0.0, 0.85));
		base = mix(base, base * 1.15 + 0.012, sc.r * 0.25);
		// worn path: the top skin is polished, colour washed out
		float wl = dot(base, vec3(0.299, 0.587, 0.114));
		base = mix(base, mix(vec3(wl), base, 0.75) * 1.12 + 0.01, wear_m * 0.6);
		base *= 1.0 - bevel * 0.12;
		base = mix(base, base * 0.25, gap);
		rough = clamp(0.55 + nz2.g * 0.25 + gap * 0.25 - sc.r * 0.08 - wear_m * 0.17 + wall_g * 0.08, 0.3, 1.0);
	}
	ALBEDO = base;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	// geometric normal (flat floor or a lifted corner) + seam bevel + per-tile tilt (slightly curled mats)
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!miss) {
		vec2 tilt = (vec2(hash12(owner + 5.0), hash12(owner + 9.0)) - 0.5) * 0.04;
		wn = normalize(wn + vec3(grad.x * bevel * 0.6 + tilt.x, 0.0, grad.y * bevel * 0.6 + tilt.y));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	NORMAL_MAP = texture(grain_n, wpos.xz * 2.4).xyz;
	NORMAL_MAP_DEPTH = miss ? 0.2 : 0.8 * (1.0 - wear_m * 0.5);
	AO = ao * (1.0 - gap * 0.3);
	AO_LIGHT_AFFECT = 0.3;
}
