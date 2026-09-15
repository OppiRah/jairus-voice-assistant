shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

// Diagnostic shader, NOT the recommended technique -- built specifically to
// empirically confirm the investigation's critical question: does
// SCREEN_TEXTURE sample the real desktop behind this transparent OS
// window, or only Godot's own rendered scene content? The GDShader
// reference confirms SCREEN_TEXTURE itself was removed in Godot 4 in favor
// of a manually declared sampler2D with the hint_screen_texture hint,
// copied "after the opaque geometry pass, but before the transparent
// geometry pass" -- i.e. mid-render, entirely inside Godot's own
// framebuffer, before the OS compositor ever sees the frame. This shell
// sits in front of glass_poc_test.tscn's magenta "BackgroundMarker" mesh
// specifically to make that concrete: if this shell visibly shows the
// magenta marker (warped), that confirms it refracts Godot's own scene,
// not the real desktop -- if it showed real desktop content instead, that
// would disprove the hypothesis.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float distortion_amount : hint_range(0.0, 0.3) = 0.08;

void fragment() {
	vec2 offset = NORMAL.xy * distortion_amount;
	vec3 refracted = textureLod(screen_tex, SCREEN_UV + offset, 0.0).rgb;
	ALBEDO = refracted;
	ALPHA = 0.9;
}
