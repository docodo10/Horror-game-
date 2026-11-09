// La Gardienne — look module: dust in the moonbeam (FogVolume shader, medium+ where volumetric fog runs).
// Density only inside a soft prism = the window aperture extruded along the moonlight down to the floor (same geometry as
// the analytic shaft, look_shaft.gdshader), slowly drifting dust, thinning toward the floor. The moonlight itself (its
// shadow map: window bars, frame) carves the shaft out of it; the bulb lights the same dust faintly when it is on.
shader_type fog;

uniform vec3 shaft_dir = vec3(-0.17, -0.53, -0.83);   // unit, direction of travel
uniform vec4 aperture = vec4(1.95, 2.95, 1.8, 2.3);  // xMin, xMax, yMin, yMax in the window plane
uniform float win_z = 2.75;
uniform float s_floor = 3.6;
uniform float density = 0.22;
uniform float spread = 0.12;                          // soft margin around the aperture (m)
uniform vec3 albedo = vec3(0.82, 0.84, 0.9);

void fog() {
	vec3 p = WORLD_POSITION;
	float s = (p.z - win_z) / shaft_dir.z;            // distance along the beam from the window plane
	float u = p.x - s * shaft_dir.x;
	float v = p.y - s * shaft_dir.y;
	float su = smoothstep(-spread, spread, min(u - aperture.x, aperture.y - u));
	float sv = smoothstep(-spread, spread * 1.5, min(v - aperture.z, aperture.w - v));
	float along = smoothstep(0.0, 0.4, s) * (1.0 - 0.45 * clamp(s / s_floor, 0.0, 1.0)) * step(0.0, p.y);
	float dust = 0.72 + 0.28 * sin(p.x * 13.0 + TIME * 0.35) * sin(p.y * 11.0 - TIME * 0.27) * sin(p.z * 9.0 + TIME * 0.21);
	DENSITY = density * su * sv * along * dust;
	ALBEDO = albedo;
}
