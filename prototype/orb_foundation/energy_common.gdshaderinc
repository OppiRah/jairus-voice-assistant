// Shared include for the orb foundation prototype's shaders.
//
// Per JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 7/12: several small
// shaders sharing common logic, all driven by the same global shader
// uniforms EnergyModel (energy_model.gd) pushes every frame, instead of one
// mega-shader and instead of any shader knowing where these values come
// from. No shader that includes this file references Jairus, WebSockets, or
// state names — only these nine float parameters.

global uniform float energy_intensity;
global uniform float energy_activity;
global uniform float energy_turbulence;
global uniform float energy_coherence;
global uniform float energy_pulse;
global uniform float energy_core_morph;
global uniform float energy_field_strength;
global uniform float energy_particle_activity;
global uniform float energy_symbol_reveal;

// Standard Fresnel rim term: 0 head-on, 1 at grazing angles.
// (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 4/17 — the documented
// dot(NORMAL, VIEW) pattern, no hint_screen_texture dependency.)
float fresnel_term(vec3 normal, vec3 view, float power) {
	return pow(1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0), power);
}

// Cheap 3D hash -> [0,1).
float hash13(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

// Smoothstep-interpolated 3D value noise -> [-1, 1].
float value_noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z) * 2.0 - 1.0;
}

// Fractal Brownian motion over value_noise3, fixed 3-octave unroll
// (Godot's mobile-renderer shader compiler does not reliably accept
// dynamic-bound for-loops here, and 3 octaves was enough to read as
// structured rather than flat in this prototype's own testing).
float fbm3(vec3 p) {
	float sum = 0.0;
	sum += 0.5 * value_noise3(p);
	sum += 0.25 * value_noise3(p * 2.0);
	sum += 0.125 * value_noise3(p * 4.0);
	return sum;
}

// Domain-warped fbm: warps the sample position by a lower-frequency fbm
// field before taking the final noise sample. This is the specific
// technique JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 9 calls out as
// producing "liquified"/directed distortion rather than generic bumpy noise.
// `warp_amount` is the knob `coherence` drives down (see core.gdshader) —
// less warp reads as more organized/structured.
float domain_warped_fbm(vec3 p, float warp_amount) {
	vec3 warp = vec3(
		fbm3(p + vec3(11.3, 0.0, 0.0)),
		fbm3(p + vec3(0.0, 17.7, 0.0)),
		fbm3(p + vec3(0.0, 0.0, 23.1))
	);
	return fbm3(p + warp * warp_amount);
}
