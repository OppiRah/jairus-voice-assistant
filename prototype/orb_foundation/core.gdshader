shader_type spatial;

#include "res://energy_common.gdshaderinc"

// Prototype-tunable constants. Kept as regular (non-global) uniforms since
// they're per-material tuning knobs, not shared cross-system state.
uniform float base_radius = 1.0;
uniform float displacement_amplitude = 0.34;
uniform float fine_amplitude = 0.05;
uniform float fresnel_power = 5.5;
uniform float fresnel_weight = 0.35;
uniform float voronoi_edge_width = 0.12;
// Used only at low core_morph — see displacement_at()'s comment on why a
// fixed-sharpness crease made core_morph perceptually non-linear.
uniform float voronoi_edge_width_soft = 0.42;
uniform float structure_gain = 2.8;
// coherence's own lever, independent of warp_amount — see vertex()'s comment.
uniform float coherence_noise_amplitude = 0.16;
uniform vec3 color_white : source_color = vec3(0.96, 0.97, 0.99);
// Darker than the pre-redesign (0.28, 0.05, 0.08), but not darker than
// this: going darker still (0.10, 0.015, 0.03 was tried mid-iteration)
// pushed the color close enough to pure black that its red hue became
// imperceptible on its own, and any subsequent light — even a small
// amount — erased the little that was left. This value survives the
// EMISSION/SPECULAR budget below without losing its hue, confirmed by
// direct pixel sampling (red channel exceeding blue on thousands of
// visible pixels, not zero).
uniform vec3 color_maroon : source_color = vec3(0.20, 0.035, 0.06);
uniform vec3 color_gold : source_color = vec3(0.85, 0.65, 0.18);

varying float v_structure;
varying float v_gold_mask;

// Combined displacement at a point on the unit sphere: blends two noise
// *configurations* (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 9/15)
// by `morph` — configuration A is a coarse, low-frequency fbm (a few large
// deliberate lobes), configuration B is a cellular/Voronoi edge metric
// (sharp-crease plates, reads as crystalline/computational) — plus a finer
// secondary layer whose weight is `turbulence`. `warp_amount` (driven by
// coherence in vertex()) controls how organized vs. chaotic both
// configurations look.
float displacement_at(vec3 p, float t, float warp_amount, float morph, float turbulence, float coherence, out float structure_out) {
	// Coarse for the *geometry*: low enough frequency to read as a few
	// large deliberate lobes rather than fbm3's finer "many small bumps".
	vec3 pa = p * 0.85 + vec3(0.0, 0.0, t * 0.15);
	vec3 pb = p * 1.8 - vec3(0.0, t * 0.1, 0.0);

	// Coarse basis: fewer, larger lobes instead of fbm3's finer texture
	// (JAIRUS_ORB_FOUNDATION_PROTOTYPE.md section 15).
	float na = domain_warped_fbm_coarse(pa, warp_amount);
	float morph_c = clamp(morph, 0.0, 1.0);
	// Cellular/Voronoi basis for configuration B: the F2-F1 edge metric is
	// 0 exactly at a cell boundary and rises toward each cell's interior.
	// smoothstep (not a hard multiply+clamp) guarantees the crease band is
	// at least `voronoi_edge_width` wide in noise-space regardless of local
	// curvature — a hard threshold produces creases narrower than this
	// mesh's vertex spacing in places, which the displaced/finite-difference
	// vertex geometry then can't resolve at all (confirmed by this
	// prototype's own first attempt: the multiply+clamp version was
	// visually indistinguishable from a plain smooth sphere).
	// Warped less than configuration A's warp_amount*0.6 — heavy warping
	// bends cell boundaries into curves and reads as organic again, working
	// against the whole point of switching to a cellular basis.
	float nb_edge = domain_warped_voronoi(pb, warp_amount * 0.4);
	// core_morph perceptual-linearity fix: a *linear* mix() of na (smooth,
	// low slope everywhere) against nb (near-binary, razor-sharp slope at
	// its crease, regardless of how little of nb is blended in) makes
	// perceived "crystalline-ness" jump almost immediately once morph
	// leaves 0 — shading responds to slope, and scaling a sharp crease's
	// *height* down by 90% barely softens its *slope*, so even a 10% blend
	// still reads as a hard-edged crease, just a shallower one. Confirmed:
	// a raw mix() here made LISTENING (morph=0.25) look nearly as spiky as
	// EXECUTING (morph=0.8). The real fix is making the crease itself
	// genuinely soft at low morph (a wide smoothstep transition = low
	// slope) and only sharpening it as morph rises — not just downweighting
	// a permanently-sharp feature. Both the crease's width AND its blend
	// weight now ramp together with morph.
	float effective_edge_width = mix(voronoi_edge_width_soft, voronoi_edge_width, morph_c);
	float nb = smoothstep(0.0, effective_edge_width, nb_edge) * 2.0 - 1.0;

	float primary = mix(na, nb, morph_c);
	float fine = value_noise3(p * 7.0 + vec3(t * 0.4, 0.0, 0.0)) * turbulence;

	// coherence's own lever, independent of warp_amount: the coarser-
	// deformation pass narrowed warp_amount's range (1.4-0.35 -> 0.85-0.25)
	// so low coherence's warp wouldn't dissolve configuration A's larger
	// lobes — a deliberate, correct fix for that problem, but it also
	// shrank how much visual difference coherence alone could produce, since
	// warp_amount was coherence's only lever. This is a second, separate
	// mechanism: a mid-frequency noise layer whose amplitude is driven
	// directly by (1-coherence), at a frequency distinct from both the
	// geometry-basis frequencies and the `turbulence`-driven `fine` layer
	// above, so it doesn't get confused with either. High coherence
	// suppresses it to ~0 (clean surface); low coherence adds a visibly
	// rough, unstable-looking grain on top of whatever primary shape is
	// underneath, independent of core_morph or turbulence.
	float coherence_noise = value_noise3(p * 4.5 + vec3(t * 0.3, -t * 0.22, 0.0));
	coherence_noise *= (1.0 - clamp(coherence, 0.0, 1.0));

	// Palette reads from its own, higher-frequency sample of the same
	// basis rather than from `na` or `primary`. Two problems ruled that
	// out: nb's Voronoi crease is a thin band in object space that this
	// mesh's 2562 vertices essentially never land inside (confirmed by
	// direct pixel sampling — zero red-channel bias anywhere on the
	// surface), and `na` alone is coarse enough that a raw grayscale
	// visualization showed the entire visible hemisphere sitting inside a
	// single lobe from this fixed camera (all-white or all-maroon
	// depending on frequency/phase — there simply aren't enough lobes at
	// geometry-appropriate frequencies for a typical view to see more than
	// one). Geometry wants low frequency for "few large deliberate forms";
	// palette needs enough spatial frequency to show both colors in any
	// given view. These are different requirements, so this samples them
	// separately instead of compromising both on one frequency.
	float palette_field = fbm_coarse(p * 2.4 + vec3(0.0, 0.0, t * 0.15));
	structure_out = palette_field;
	return primary * displacement_amplitude
		+ fine * fine_amplitude * turbulence
		+ coherence_noise * coherence_noise_amplitude;
}

void vertex() {
	float t = TIME * mix(0.05, 1.0, energy_activity);
	// Coherence pulls the warp strength down — same noise configurations,
	// less chaotic warping — this is the prototype's test of section 16's
	// "high turbulence should still be able to look organized, not explosive."
	// This range is deliberately narrower than the pre-redesign 1.4-0.35 (so
	// warp doesn't break up the coarser, larger lobes above into mush) and
	// stays narrow here — it is NOT being re-widened to recover coherence's
	// lost range. That's a separate, second lever now (`coherence_noise` in
	// displacement_at()), specifically so this warp range can stay exactly
	// as narrow as the coarser-deformation pass needed. See
	// JAIRUS_ORB_FOUNDATION_PROTOTYPE.md for the reasoning and comparison
	// screenshots.
	float warp_amount = mix(0.85, 0.25, clamp(energy_coherence, 0.0, 1.0));
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
	float disp_c = displacement_at(dir_c, t, warp_amount, energy_core_morph, turbulence, energy_coherence, structure_c);
	float disp_t = displacement_at(dir_t, t, warp_amount, energy_core_morph, turbulence, energy_coherence, structure_unused_t);
	float disp_b = displacement_at(dir_b, t, warp_amount, energy_core_morph, turbulence, energy_coherence, structure_unused_b);

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
	// v_structure (an fbm_coarse blend of two octaves) rarely sits near its
	// nominal +/-1 bounds in practice — averaging octaves narrows the real
	// range to roughly +/-0.3-0.4 — so a plain linear mix between maroon and
	// near-white spent most of the surface in the middle of the gradient,
	// which blends two RGB-balanced-ish colors into flat gray rather than a
	// visible two-tone hierarchy. `structure_gain` stretches the realistic
	// range back out before the contrast curve below pushes it toward one
	// endpoint color or the other, confirmed against a raw grayscale
	// visualization of v_structure and direct pixel sampling of the
	// rendered output.
	float structure_raw = clamp(v_structure * structure_gain * 0.5 + 0.5, 0.0, 1.0);
	float structure_n = smoothstep(0.25, 0.75, structure_raw);
	vec3 base_color = mix(color_maroon, color_white, structure_n);

	// Masked by structure_n: an unmasked Fresnel rim adds white light
	// across a meaningful fraction of the curved surface, not just the
	// exact silhouette, and any additive white light shifts a color this
	// dark toward gray far more than it would a lighter one — confirmed by
	// direct pixel sampling, where even a small unmasked rim weight
	// dropped the surface's red-exceeds-blue pixel count to exactly zero.
	// Restricting the rim to where the surface is already white lets it
	// pop the primary body's silhouette without erasing the maroon.
	float fresnel = fresnel_term(NORMAL, VIEW, fresnel_power) * fresnel_weight;
	vec3 rim_color = color_white * fresnel * structure_n;

	// Gold stays at zero unless symbol_reveal or a pulse event asks for it —
	// deliberately not blended in by any other parameter (JAIRUS_ORB_VFX_
	// TECHNICAL_ARCHITECTURE.md section 15: gold must not bleed into other
	// states).
	float gold_amount = v_gold_mask * clamp(energy_symbol_reveal + energy_pulse, 0.0, 1.0) * 0.7;
	vec3 gold_glow = color_gold * gold_amount;

	// A ROUGHNESS/SPECULAR combo of 0.35/0.5 (this shader's pre-redesign
	// values) turned out to matter as much as the Fresnel rim for the
	// "palette never reads" symptom: it threw a broad, bright glossy
	// highlight across much of the visible surface from this scene's
	// single key light — an achromatic dielectric specular response, so it
	// washes a dark colored ALBEDO toward gray wherever it lands. Confirmed
	// with a diagnostic pass (SPECULAR zeroed, ROUGHNESS maxed): the
	// maroon/white hierarchy read clearly; a small fraction of SPECULAR
	// brought back was enough to erase it again.
	ALBEDO = base_color;
	EMISSION = rim_color * mix(0.2, 0.8, energy_intensity) + gold_glow;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
