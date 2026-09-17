shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

#include "res://energy_common.gdshaderinc"

// Structural Lattice ring (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section
// 3: "thin rings/curves establishing the orbital silhouette"; section 4:
// "thin, elegant, curve-driven shapes read as 'orbital,' not mechanical").
// blend_mix, not blend_add -- see energy_shell.gdshader's header comment
// for the real bug that ruled additive blending out in this project's
// per-pixel-transparent viewport (confirmed via an isolated diagnostic:
// rings rendered completely invisible without an opaque object behind
// them to anchor non-zero alpha, despite correct geometry/orientation).
//
// Two instances (RingA/RingB in structural_lattice.gd), differentiated via
// per-instance uniforms (activity_weight below) and orientation/radius set
// in structural_lattice.gd -- not by breaking ring symmetry into gapped/
// partial arcs, per section 2's "symmetrical at rest" design interpretation
// (a deliberate difference from the older archived V1 fix, which broke
// symmetry; this document's own stated intent supersedes that for this
// project).
uniform vec3 color_white : source_color = vec3(0.96, 0.97, 0.99);
// How much this ring's brightness leans on energy_activity/energy_intensity
// (a "live, responsive" ring) vs. staying close to a steady baseline (a
// "stable, structural" ring) -- 1.0 = fully the former. RingA/RingB are set
// differently in structural_lattice.gd so they don't brighten in lockstep.
uniform float activity_weight : hint_range(0.0, 1.0) = 0.5;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float fresnel_power : hint_range(1.0, 8.0) = 3.0;

void fragment() {
	float fresnel = fresnel_term(NORMAL, VIEW, fresnel_power);
	float steady_signal = 0.55; // a ring that never goes fully dark, even at OFFLINE-adjacent low activity
	float live_signal = clamp(energy_activity * 0.6 + energy_intensity * 0.4, 0.0, 1.0);
	float brightness = mix(steady_signal, live_signal, activity_weight);

	ALBEDO = color_white;
	EMISSION = color_white * brightness * fresnel * 1.1;
	ALPHA = base_alpha * brightness * (0.4 + 0.6 * fresnel);
}
