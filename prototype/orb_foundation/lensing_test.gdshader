shader_type spatial;
render_mode blend_mix;

// Minimal, standalone distortion/refraction experiment (section 19 of the
// task brief / section 19 of JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md).
// Standard view-space-normal-offset screen-reading technique — offsets the
// screen UV by the fragment's view-space normal before sampling
// `hint_screen_texture`. Deliberately NOT wired to EnergyModel: this is an
// isolated technical test of what this sampler can and cannot see in a
// transparent, OS-composited window, not part of the core prototype.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float distortion_strength : hint_range(0.0, 0.2) = 0.05;

void fragment() {
	vec2 offset_uv = SCREEN_UV + NORMAL.xy * distortion_strength;
	vec3 sampled = textureLod(screen_tex, offset_uv, 0.0).rgb;
	ALBEDO = sampled;
	ALPHA = 0.9;
}
