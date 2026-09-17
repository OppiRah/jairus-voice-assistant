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

// Coarse 2-octave variant of fbm3, weighted toward its lowest frequency and
// missing fbm3's highest (p*4) octave entirely. Used for the *base* lobe
// shape so it reads as a handful of large deliberate forms instead of
// fbm3's finer, "many small bumps" texture (JAIRUS_ORB_FOUNDATION_PROTOTYPE.md
// section 15's "coarser base deformation" recommendation).
float fbm_coarse(vec3 p) {
	float sum = 0.0;
	sum += 0.7 * value_noise3(p);
	sum += 0.3 * value_noise3(p * 2.0);
	return sum;
}

// Domain-warped fbm_coarse: warps the sample position by a lower-frequency
// fbm field before taking the final noise sample. This is the specific
// technique JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 9 calls out as
// producing "liquified"/directed distortion rather than generic bumpy noise.
// `warp_amount` is the knob `coherence` drives down (see core.gdshader) —
// less warp reads as more organized/structured. The warp field itself stays
// fbm3-based; only the final sample uses the coarser basis, so the *result*
// reads as a few large deliberate lobes rather than fbm3's finer texture.
float domain_warped_fbm_coarse(vec3 p, float warp_amount) {
	vec3 warp = vec3(
		fbm3(p + vec3(11.3, 0.0, 0.0)),
		fbm3(p + vec3(0.0, 17.7, 0.0)),
		fbm3(p + vec3(0.0, 0.0, 23.1))
	);
	return fbm_coarse(p + warp * warp_amount);
}

// Cellular/Worley noise, F1 and F2 (distance to the nearest and
// second-nearest of one jittered feature point per unit grid cell, searched
// across the 3x3x3 neighborhood). Returns vec2(F1, F2), each roughly
// [0, 1.2]. This is the "cellular/Voronoi noise basis" investigated as an
// alternative to the value-noise-with-ridge-transform approach
// (JAIRUS_ORB_FOUNDATION_PROTOTYPE.md section 15).
//
// F1 alone is smooth within each cell (a gentle dome around each feature
// point, no discontinuity) — using it directly as a height field just
// produces more rounded bumps, not facets, as this prototype's own first
// attempt at this basis confirmed. F2-F1 is the standard fix: it goes to
// exactly 0 right on a cell boundary (equidistant from two feature points)
// and rises inside each cell, so it reads as flat-ish plates separated by
// sharp creases — the actual "crystalline" cue.
vec2 worley3_f1f2(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 cell_id = cell + offset;
				vec3 feature = vec3(
					hash13(cell_id + vec3(0.0, 0.0, 0.0)),
					hash13(cell_id + vec3(7.1, 3.3, 1.7)),
					hash13(cell_id + vec3(2.9, 5.5, 9.1))
				);
				float d = length(offset + feature - local);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec2(f1, f2);
}

// Same fbm3-based warp field as domain_warped_fbm_coarse, but the final
// sample is the Worley F2-F1 edge metric instead of fbm — same
// domain-warping stage feeding a different basis function.
float domain_warped_voronoi(vec3 p, float warp_amount) {
	vec3 warp = vec3(
		fbm3(p + vec3(11.3, 0.0, 0.0)),
		fbm3(p + vec3(0.0, 17.7, 0.0)),
		fbm3(p + vec3(0.0, 0.0, 23.1))
	);
	vec2 f1f2 = worley3_f1f2(p + warp * warp_amount);
	return f1f2.y - f1f2.x;
}
