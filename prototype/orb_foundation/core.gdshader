shader_type spatial;

#include "res://energy_common.gdshaderinc"

// Prototype-tunable constants. Kept as regular (non-global) uniforms since
// they're per-material tuning knobs, not shared cross-system state.
uniform float base_radius = 1.0;
uniform float displacement_amplitude = 0.18;
uniform float fine_amplitude = 0.05;
uniform float fresnel_power = 3.0;
uniform vec3 color_white : source_color = vec3(0.96, 0.97, 0.99);
uniform vec3 color_maroon : source_color = vec3(0.28, 0.05, 0.08);
uniform vec3 color_gold : source_color = vec3(0.85, 0.65, 0.18);

varying float v_structure;
varying float v_gold_mask;

// Combined displacement at a point on the unit sphere: blends two noise
// *configurations* (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 9/15)
// by `morph` — configuration A is smoother/organic, configuration B is
// ridged/angular (meant to read as more "crystalline/geometric") — plus a
// finer secondary layer whose weight is `turbulence`. `warp_amount` (driven
// by coherence in vertex()) controls how organized vs. chaotic both
// configurations look.
float displacement_at(vec3 p, float t, float warp_amount, float morph, float turbulence, out float structure_out) {
	vec3 pa = p * 1.6 + vec3(0.0, 0.0, t * 0.15);
	vec3 pb = p * 3.2 - vec3(0.0, t * 0.1, 0.0);

	float na = domain_warped_fbm(pa, warp_amount);
	float nb_raw = domain_warped_fbm(pb, warp_amount * 0.6);
	float nb = 1.0 - abs(nb_raw) * 2.0;

	float primary = mix(na, nb, clamp(morph, 0.0, 1.0));
	float fine = value_noise3(p * 7.0 + vec3(t * 0.4, 0.0, 0.0)) * turbulence;

	structure_out = primary;
	return primary * displacement_amplitude + fine * fine_amplitude * turbulence;
}

void vertex() {
	float t = TIME * mix(0.05, 1.0, energy_activity);
	// Coherence pulls the warp strength down — same noise configurations,
	// less chaotic warping — this is the prototype's test of section 16's
	// "high turbulence should still be able to look organized, not explosive."
	float warp_amount = mix(1.4, 0.35, clamp(energy_coherence, 0.0, 1.0));
	float turbulence = clamp(energy_turbulence + energy_pulse * 0.5, 0.0, 1.0);

	vec3 base_normal = normalize(VERTEX);
	vec3 up_hint = (abs(base_normal.y) < 0.99) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(up_hint, base_normal));
	vec3 bitangent = cross(base_normal, tangent);
	float eps = 0.02;

	vec3 dir_c = base_normal;
	vec3 dir_t = normalize(base_normal + tangent * eps);
	vec3 dir_b = normalize(base_normal + bitangent * eps);

	float structure_c;
	float structure_unused_t;
	float structure_unused_b;
	float disp_c = displacement_at(dir_c, t, warp_amount, energy_core_morph, turbulence, structure_c);
	float disp_t = displacement_at(dir_t, t, warp_amount, energy_core_morph, turbulence, structure_unused_t);
	float disp_b = displacement_at(dir_b, t, warp_amount, energy_core_morph, turbulence, structure_unused_b);

	vec3 pos_c = dir_c * (base_radius + disp_c);
	vec3 pos_t = dir_t * (base_radius + disp_t);
	vec3 pos_b = dir_b * (base_radius + disp_b);

	// Finite-difference recompute of the normal from the three displaced
	// sample points, since the analytic normal changes once we displace —
	// using the un-displaced normal here would light the surface as if it
	// were still a plain sphere and hide the deformation entirely.
	vec3 new_normal = normalize(cross(pos_t - pos_c, pos_b - pos_c));
	if (dot(new_normal, base_normal) < 0.0) {
		new_normal = -new_normal;
	}

	VERTEX = pos_c;
	NORMAL = new_normal;
	v_structure = structure_c;
	v_gold_mask = smoothstep(0.82, 0.98, value_noise3(base_normal * 9.0 + vec3(t * 0.2, 0.0, 0.0)) * 0.5 + 0.5);
}

void fragment() {
	float structure_n = clamp(v_structure * 0.5 + 0.5, 0.0, 1.0);
	vec3 base_color = mix(color_maroon, color_white, structure_n);

	float fresnel = fresnel_term(NORMAL, VIEW, fresnel_power);
	vec3 rim_color = color_white * fresnel;

	// Gold stays at zero unless symbol_reveal or a pulse event asks for it —
	// deliberately not blended in by any other parameter (JAIRUS_ORB_VFX_
	// TECHNICAL_ARCHITECTURE.md section 15: gold must not bleed into other
	// states).
	float gold_amount = v_gold_mask * clamp(energy_symbol_reveal + energy_pulse, 0.0, 1.0) * 0.7;
	vec3 gold_glow = color_gold * gold_amount;

	ALBEDO = base_color;
	EMISSION = (base_color * 0.4 + rim_color) * mix(0.15, 1.4, energy_intensity) + gold_glow;
	ROUGHNESS = 0.35;
	METALLIC = 0.05;
	SPECULAR = 0.5;
}
