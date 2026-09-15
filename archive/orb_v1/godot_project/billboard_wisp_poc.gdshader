shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// VFX technique investigation PoC only -- NOT wired into orb_scene.tscn.
// Camera-facing via a manual vertex() override (confirmed the hard way:
// Godot 4's spatial shader render_mode has no `billboard` keyword --
// that keyword only exists for `shader_type particles`; a custom
// `shader_type spatial` ShaderMaterial like this one has to rebuild
// MODELVIEW_MATRIX by hand, replacing its rotation part with the
// camera's own inverse rotation while keeping the quad's world-position
// translation -- the same technique StandardMaterial3D.billboard_mode
// wraps internally for the fixed-function pipeline) soft radial-falloff
// quad, entirely procedural (no image asset -- same discipline as every
// shader already in this project): ALPHA/EMISSION both come from
// `falloff`, a
// distance-from-center gradient computed straight from UV, so there is
// no hard sprite-edge regardless of viewing angle. `use_noise` (a real
// FastNoiseLite-generated NoiseTexture2D, not a hand-rolled hash) is
// optional so the SAME quad can be screenshotted both as a plain soft
// halo (use_noise=0) and as an irregular "wisp" (use_noise=1) for a
// direct, controlled before/after comparison of the specific technique
// named in the reference doc.
uniform vec3 base_color : source_color = vec3(0.6, 0.8, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.5;
uniform float softness : hint_range(0.1, 1.0) = 0.5;
uniform sampler2D noise_tex : repeat_enable;
uniform float use_noise : hint_range(0.0, 1.0) = 0.0;
uniform float noise_speed : hint_range(0.0, 2.0) = 0.4;

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
		vec2 nuv = UV + vec2(TIME * noise_speed, -TIME * noise_speed * 0.7);
		float n = texture(noise_tex, nuv).r;
		noise_mod = mix(0.4, 1.0, n);
	}

	float a = falloff * noise_mod;
	EMISSION = base_color * intensity * a;
	ALPHA = a;
}
