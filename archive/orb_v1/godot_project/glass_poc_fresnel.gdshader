shader_type spatial;
render_mode blend_mix, cull_back, unshaded;

// Fresnel-based "glass rim" look: no SCREEN_TEXTURE, no ReflectionProbe, no
// idea of "what's behind the object" at all -- purely a function of the
// angle between the surface normal and the view direction (both real
// Godot spatial-shader built-ins, confirmed via the shader reference: NORMAL
// and VIEW are both in view space). This is the technique recommended by
// the glass/PBR material investigation specifically because it stays
// coherent inside a transparent OS-composited window, where there is no
// real "screen behind the object" for Godot to sample in the first place.
uniform vec3 base_color : source_color = vec3(0.55, 0.75, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float core_alpha : hint_range(0.0, 1.0) = 0.08;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.95;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	ALBEDO = base_color;
	EMISSION = base_color * fresnel * 2.0;
	ALPHA = mix(core_alpha, rim_alpha, fresnel);
}
