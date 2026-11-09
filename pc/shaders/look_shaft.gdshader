// La Gardienne — look module: analytic moonlight shaft (port of src/world/Lighting.js BEAM_FS), used on the low preset
// where there is no volumetric fog. In-scattering integrated along each view ray through the shaft prism (the window
// aperture extruded along the moonlight down to the floor): each pixel is shaded exactly once (entry faces from outside,
// exit faces from inside), soft edges, thinning toward the floor, dissolves near the lens, slow dust drift.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 0.02;
uniform float time_s = 0.0;
uniform vec3 tint = vec3(0.32, 0.4, 0.62);
uniform vec3 shaft_dir = vec3(-0.17, -0.53, -0.83);   // unit, direction of travel
uniform vec4 aperture = vec4(1.95, 2.95, 1.8, 2.3);  // xMin, xMax, yMin, yMax in the window plane
uniform float win_z = 2.75;
uniform float inside = 0.0;                          // 1 when the camera is inside the volume
uniform float s_floor = 3.0;                         // shaft length (window -> floor) at the aperture centre
varying vec3 w_pos;
varying vec3 w_nrm;

void slab(float x0, float d, float a, float b, inout float t0, inout float t1) {
	if (abs(d) < 1e-6) {
		if (x0 < a || x0 > b) t1 = -1.0;
		return;
	}
	float ta = (a - x0) / d;
	float tb = (b - x0) / d;
	t0 = max(t0, min(ta, tb));
	t1 = min(t1, max(ta, tb));
}

void half_space(float x0, float d, inout float t0, inout float t1) {   // x0 + t d >= 0
	if (abs(d) < 1e-6) {
		if (x0 < 0.0) t1 = -1.0;
		return;
	}
	float t = -x0 / d;
	if (d > 0.0) t0 = max(t0, t);
	else t1 = min(t1, t);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = CAMERA_POSITION_WORLD;
	vec3 to_f = w_pos - c;
	float tf = length(to_f);
	vec3 w = to_f / tf;
	bool entry = dot(-to_f, w_nrm) > 0.0;
	if (entry == (inside > 0.5)) discard;
	vec3 sd = shaft_dir;
	float s0 = (c.z - win_z) / sd.z;
	float ds = w.z / sd.z;
	float u0 = c.x - s0 * sd.x;
	float du = w.x - ds * sd.x;
	float v0 = c.y - s0 * sd.y;
	float dv = w.y - ds * sd.y;
	float t0 = 0.0;
	float t1 = entry ? tf + 40.0 : tf + 1e-3;
	slab(u0, du, aperture.x, aperture.y, t0, t1);
	slab(v0, dv, aperture.z, aperture.w, t0, t1);
	half_space(s0, ds, t0, t1);
	half_space(c.y, w.y, t0, t1);
	t0 = max(t0, 0.3);                       // no haze glued to the lens
	float L = t1 - t0;
	if (L <= 0.0) discard;
	float acc = 0.0;
	for (int i = 0; i < 3; i++) {
		float tt = t0 + L * (0.16667 + 0.33333 * float(i));
		vec3 pm = c + w * tt;
		float um = u0 + tt * du;
		float vm = v0 + tt * dv;
		float sm = s0 + tt * ds;
		float soft = smoothstep(0.0, 0.22 * (aperture.y - aperture.x), min(um - aperture.x, aperture.y - um))
			* smoothstep(0.0, 0.34 * (aperture.w - aperture.z), min(vm - aperture.z, aperture.w - vm));
		float along = smoothstep(0.0, 0.35, sm) * (1.0 - 0.6 * clamp(sm / s_floor, 0.0, 1.0));
		float near_f = smoothstep(0.3, 1.5, tt);
		float dust = 0.78 + 0.22 * sin(pm.x * 23.0 + time_s * 0.6) * sin(pm.y * 17.0 - time_s * 0.45) * sin(pm.z * 19.0 + time_s * 0.3);
		acc += soft * along * near_f * dust;
	}
	// path length capped: seen edge-on, the thin light sheet must not pile up into a hard bright line
	float a = intensity * min(L, 0.9) * acc * 0.33333;
	ALBEDO = tint * a;
}
