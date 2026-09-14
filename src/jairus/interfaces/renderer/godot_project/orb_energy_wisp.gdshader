shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Camera-facing energy wisp -- billboard technique reused VERBATIM from
// billboard_wisp_poc.gdshader (ORB_VFX_TECHNIQUE_ANALYSIS.md's validated
// PoC): Godot 4's spatial shader render_mode has no `billboard` keyword
// (that only exists for shader_type particles), so a custom ShaderMaterial
// has to rebuild MODELVIEW_MATRIX by hand, replacing its rotation part with
// the camera's own inverse rotation while keeping the quad's world-position
// translation -- the same technique StandardMaterial3D.billboard_mode wraps
// internally. Soft radial-falloff quad, entirely procedural (no image
// asset): ALPHA/EMISSION both come from `falloff`, a distance-from-center
// gradient computed straight from UV, so there is no hard sprite-edge
// regardless of viewing angle. `use_noise` (a real FastNoiseLite-generated
// NoiseTexture2D) breaks the plain radial falloff into an irregular "wisp"
// shape -- this is what the PoC found makes the difference between a plain
// glow dot and something that reads as energy/plasma rather than a sprite.
uniform vec3 base_color : source_color = vec3(0.6, 0.8, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.5;
uniform float softness : hint_range(0.1, 1.0) = 0.5;
uniform sampler2D noise_tex : repeat_enable;
uniform float use_noise : hint_range(0.0, 1.0) = 1.0;
uniform float noise_speed : hint_range(0.0, 2.0) = 0.4;
// Added on top of the PoC's own uniforms (same technique, one more per-
// state knob): ALPHA and EMISSION are otherwise coupled through the same
// `intensity`, so STATE_PROFILES' wisp_intensity and wisp_opacity would
// collapse into the same control without this -- opacity_multiplier lets
// "how bright" and "how present/see-through" vary independently per state.
uniform float opacity_multiplier : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	float falloff = 1.0 - smoothstep(0.0, 1.0, dist);
	falloff = pow(falloff, mix(1.0, 4.0, 1.0 - softness));

	float noise_mod = 1.0;
	if (use_noise > 0.5) {
		// Stretched, not round, sampling: a round noise blob reads as a
		// cloud puff regardless of contrast. Squashing one axis elongates
		// the same noise field into streak-like filaments -- closer to an
		// energy tendril/field line than a puff of haze.
		vec2 nuv = UV * vec2(1.0, 2.6) + vec2(TIME * noise_speed, -TIME * noise_speed * 0.7);
		float n = texture(noise_tex, nuv).r;
		// A linear mix() here reads as soft, even density -- smoke/mist, the
		// explicitly-banned character. smoothstep's steep S-curve instead
		// pushes most of the shape toward fully-on or fully-off, carving the
		// soft falloff into torn, patchy regions -- closer to a field/plasma
		// tearing than an even cloud of haze.
		noise_mod = smoothstep(0.35, 0.65, n);
	}

	float a = falloff * noise_mod * opacity_multiplier;
	EMISSION = base_color * intensity * a;
	ALPHA = a;
}
