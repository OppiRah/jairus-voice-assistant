shader_type spatial;
render_mode cull_back;

// Investigation-only: "cheap alternative" test for
// ORB_SILHOUETTE_MATERIAL_INVESTIGATION.md's Problem 2 -- fakes per-facet
// shading on a FLAT surface by quantizing UV space into a low-res grid and
// picking a pseudo-random tilted shading normal per cell (a hand-rolled
// hash, no texture asset -- same asset-free discipline as the rest of this
// project), directly assigning the result to NORMAL in fragment(). This is
// the same idea a real baked normal-map texture would achieve, just
// generated procedurally instead of sampled from an image -- if this
// doesn't look convincing, a real normal map won't either, since both
// perturb the SAME underlying flat surface the SAME way for lighting
// purposes; only the source of the perturbation differs.
uniform vec3 base_color : source_color = vec3(0.09, 0.095, 0.11);
uniform float metallic_value : hint_range(0.0, 1.0) = 0.65;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.35;
uniform float cell_count : hint_range(2.0, 24.0) = 6.0;
uniform float tilt_strength : hint_range(0.0, 1.0) = 0.6;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	ALBEDO = base_color;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;

	vec2 cell = floor(UV * cell_count);
	float h1 = hash21(cell) - 0.5;
	float h2 = hash21(cell + 17.0) - 0.5;
	NORMAL = normalize(NORMAL + TANGENT * h1 * tilt_strength + BINORMAL * h2 * tilt_strength);
}
