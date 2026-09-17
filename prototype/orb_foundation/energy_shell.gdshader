shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

#include "res://energy_common.gdshaderinc"

// Energy Field shell (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 3:
// "the layered translucent 'atmosphere' volume(s) immediately around the
// core"; section 7 names this exact file: "fragment-only (or very light
// vertex noise), alpha-blended, Fresnel-heavy, driven by field_strength").
//
// blend_mix (standard alpha blend), matching wisp_hero_ribbon.gdshader's
// already-validated pattern -- blend_add was tried first for its
// order-independence property, but a real screenshot-caught bug ruled it
// out: this project's per-pixel-transparent viewport writes near-zero
// alpha wherever ONLY additive geometry covers a pixel (no opaque geometry
// behind it to anchor alpha=1), so an additive shell/ring was only ever
// visible where it happened to overlap the opaque core, and invisible
// against plain background -- confirmed via an isolated diagnostic scene
// with no core present at all, which rendered completely blank despite
// correct, verified geometry and orientation. blend_mix's standard alpha
// channel doesn't have this failure mode. Two shells is still a small
// enough, mostly-non-intersecting (concentric, not overlapping in radius)
// set that Godot 4's AABB-center transparency sort (section 5/17) should
// behave reasonably -- worth re-checking if shell count or overlap ever
// grows (section 18's own risk register entry for this).
// depth_draw_never since this is an unshaded translucent layer -- writing
// depth here would only cause the *other* shell (and wisps) to incorrectly
// self-occlude against it.
//
// Two instances of this shader exist (ShellInner/ShellOuter in
// energy_field.gd), differentiated via these regular (per-instance) uniform
// values -- NOT by geometry asymmetry, per section 2's "symmetrical at
// rest; asymmetry is a function of transient energy behavior, not base
// geometry." Deliberately built against the V1 failure mode documented in
// archive/orb_v1/docs/ORB_CONCEPT_GAP_ANALYSIS.md ("4 equally bright
// concentric shells inherently read as 4 equally-visible nested rings"
// because only *transform* varied, never appearance): fresnel_power,
// base_alpha, intensity_weight, and field_weight are set differently per
// instance in energy_field.gd so the two shells' brightness ratio actually
// shifts across states instead of staying two proportionally-scaled copies
// of the same signal.
uniform vec3 color_white : source_color = vec3(0.96, 0.97, 0.99);
uniform vec3 color_maroon : source_color = vec3(0.20, 0.035, 0.06);
uniform float fresnel_power : hint_range(1.0, 10.0) = 4.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.18;
// How much this shell's brightness leans on energy_intensity/turbulence
// (the core's own "hot, active" signal) vs. energy_field_strength/coherence
// (the ambient field's own extent/organization) -- 1.0 = fully the former,
// 0.0 = fully the latter. Inner shell is set high, outer shell low, so the
// two shells respond to different parts of EnergyModel's state instead of
// both just echoing field_strength at different scales.
uniform float intensity_weight : hint_range(0.0, 1.0) = 0.7;
// Light vertex noise so the boundary isn't a mathematically perfect sphere
// (archive/orb_v1/docs/JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md: "does not
// look like a mathematically perfect collection of concentric circles"),
// reusing core.gdshader's existing noise infrastructure from
// energy_common.gdshaderinc rather than a second bespoke noise scheme.
// Kept far below core.gdshader's 0.34 displacement_amplitude -- this is an
// atmosphere, not a second core.
uniform float noise_amplitude : hint_range(0.0, 0.3) = 0.05;
uniform float noise_frequency : hint_range(0.5, 4.0) = 1.4;
uniform float noise_seed_offset = 0.0;

varying float v_edge_noise;

void vertex() {
	vec3 dir = normalize(VERTEX);
	float t = TIME * mix(0.05, 0.4, energy_activity) + noise_seed_offset;
	float warp_amount = mix(0.6, 0.15, clamp(energy_coherence, 0.0, 1.0));
	float n = domain_warped_fbm_coarse(dir * noise_frequency + vec3(0.0, 0.0, t), warp_amount);
	VERTEX += dir * n * noise_amplitude * clamp(energy_field_strength, 0.0, 1.0);
	// Reused directly (not recomputed via finite differences like
	// core.gdshader) -- at this small a displacement amplitude the
	// analytic sphere normal stays visually correct, and this shell's
	// vertex cost stays a single noise sample instead of core's three.
	NORMAL = dir;
	v_edge_noise = n;
}

void fragment() {
	float fresnel = fresnel_term(NORMAL, VIEW, fresnel_power);

	// Section 15's palette rule: maroon becomes more apparent at higher
	// energy states, driven off turbulence/intensity rather than held as a
	// static shadow color -- same rule core.gdshader already follows,
	// applied here per-shell instead of per-facet.
	float maroon_amount = clamp(energy_turbulence * 0.6 + energy_intensity * 0.4, 0.0, 1.0);
	vec3 shell_color = mix(color_white, color_maroon, maroon_amount * 0.5);

	float energy_signal = mix(energy_field_strength * clamp(energy_coherence, 0.2, 1.0),
		energy_intensity, intensity_weight);
	float brightness = fresnel * energy_signal;

	ALBEDO = shell_color;
	EMISSION = shell_color * brightness * 1.4;
	ALPHA = base_alpha * brightness * (0.85 + 0.3 * v_edge_noise);
}
