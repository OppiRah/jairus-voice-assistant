shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

// Real orb glass shell: combines the two techniques validated separately
// in glass_poc_fresnel.gdshader and glass_poc_refraction.gdshader (see
// ORB_RENDERER_INVESTIGATION.md section 9). cull_back matches the PoC's
// validated choice for a volumetric shell shape (only the outward-facing
// hemisphere draws, avoiding a shell sorting against its own back faces) --
// distinct from the rings/arcs/particles' CULL_DISABLED, which stays
// correct for those thin, non-volumetric shapes.
//
// IMPORTANT, confirmed by the investigation's own docs research: the
// screen texture is copied once per frame, after the opaque pass but
// BEFORE any transparent geometry draws. That means this shell's "lensing"
// can only ever warp the orb's one OPAQUE element (the Core sphere) plus
// whatever's behind the transparent window (confirmed elsewhere to be
// empty/black here, never the real desktop) -- never the rings, particles,
// or other glass shells, since those are themselves transparent and have
// not been drawn yet at the moment this single copy is taken, regardless
// of render_priority draw order. The effect is real and worth having (a
// soft, subtly warped glow of the core bleeding through each shell,
// compounding visually as more alpha-blended shells stack on top of each
// other) -- it is deliberately not described as "distorts the rings" or
// "distorts particles" anywhere, because it can't.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec3 base_color : source_color = vec3(0.6, 0.75, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.85;
uniform float core_alpha : hint_range(0.0, 1.0) = 0.05;
uniform float lens_distortion : hint_range(0.0, 0.3) = 0.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);

	vec2 offset = NORMAL.xy * lens_distortion;
	vec3 lensed = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;

	ALBEDO = mix(lensed, base_color, fresnel);
	EMISSION = base_color * fresnel * 2.0;
	ALPHA = mix(core_alpha, rim_alpha, fresnel);
}
